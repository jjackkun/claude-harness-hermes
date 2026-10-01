#!/usr/bin/env python3
"""한 에이전트의 기억(대화 요약 · 살아 있는 기억)에서 질문 낱말에 맞는 것을 찾아 글로 만드는 것만 담당한다. 읽기 전용, 모델 호출 없음(R3).

세션 시작 주입은 최근 것부터 4,096 B 까지만 싣는다. 넘어서 밀린 옛 대화, 다른 방에서 한 일은 에이전트가 이 검색으로 꺼내 온다
("바탕은 항상, 나머지는 필요할 때"). 범위는 주입과 같다 — 이 에이전트가 **부른 사람 본인과** 나눈 대화, 철회되지 않은 기억.

  낱말   공백으로 가른 낱말. 한글 3자 이상은 끝 1~2글자를 뗀 형태도 맞춘다("백로그를" → "백로그") — 뗀 뒤 2자 이상일 때만.
  순서   맞는 낱말 수 → 최근. 상한은 주입 구획과 같은 4,096 B(새 숫자를 만들지 않는다), 건수가 아니라 바이트로 채운다.
  실패   저장소 파일이 없으면 안내(rc 0) · 읽지 못하면 그렇다고 말한다(rc 1) — 거짓 "찾지 못했습니다" 를 하지 않는다.
계획: docs/exec-plans/completed/2026-10-01-agent-recall.md

공개: run
"""

import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_agent_slug import agent_by_slug  # noqa: E402
from hermes_agent_summaries import agent_summary_rows, summary_block  # noqa: E402
from hermes_memory_conflicts import current_memories  # noqa: E402
from hermes_person import person  # noqa: E402
from hermes_roster import find_agent, load_roster  # noqa: E402

MARK = "[기억 검색]"
_CAP = 4096
_TERM = re.compile(r"[A-Za-z0-9_./-]+|[가-힣]+")
_HANGUL = re.compile(r"^[가-힣]+$")
_MIN_STEM = 2          # 조사를 뗀 뒤 남아야 하는 최소 글자 수 — 1자 낱말은 우연 일치가 너무 많다
_MIN_STRIP = 3         # 이 길이 이상의 한글 낱말만 조사 떼기를 한다
_MIN_TERM = 2          # 이보다 짧은 낱말("방" · "-" · "a")은 거의 모든 요약에 맞아 버린다
_MAX_TERMS = 8         # 질문 낱말 상한 — 사람이 묻는 문장의 뜻 있는 낱말은 이 안에 든다. 머리에 싣는 글자도 이로써 묶인다
_MAX_TERM_LEN = 32     # 낱말 하나의 글자 수 상한 — 조사까지 붙은 긴 낱말도 32자 안이다


def _variants(term: str) -> list:
    """낱말 하나가 본문과 맞을 수 있는 형태들 — 원형, 끝 1글자, 끝 2글자(한글 3자 이상만)."""
    out = [term]
    if _HANGUL.match(term) and len(term) >= _MIN_STRIP:
        out += [term[:-n] for n in (1, 2) if len(term) - n >= _MIN_STEM]
    return out


def clean_terms(query: str) -> list:
    """질문 → 쓸 낱말들. 소문자 · 기호/한 글자 버림 · 중복 제거(반복으로 점수를 못 부풀린다) · 개수·길이 상한."""
    seen = []
    for raw in _TERM.findall(query):
        term = raw.lower()[:_MAX_TERM_LEN]
        if len(term) >= _MIN_TERM and any(c.isalnum() for c in term) and term not in seen:
            seen.append(term)
    return seen[:_MAX_TERMS]


def _score(text: str, terms: list) -> int:
    return sum(1 for term in terms if any(v in text for v in _variants(term)))


class Ambiguous(Exception):
    """호출명·id·이름이 서로 다른 에이전트를 가리킨다 — 엉뚱한 에이전트의 기억을 보이지 않도록 거부한다."""


def resolve_agent(roster: dict, token: str):
    """호출명·id·이름으로 찾는다. 없으면 None, 서로 다른 에이전트가 걸리면 Ambiguous."""
    found = {a["agent_id"]: a for a in (agent_by_slug(roster, token), find_agent(roster, token)) if a}
    if len(found) > 1:
        raise Ambiguous(f"'{token}' 이(가) 호출명·이름·id 에서 서로 다른 에이전트를 가리킨다 — id 로 다시 부른다")
    return next(iter(found.values()), None)


def _slot_text(raw) -> str:
    """요약 칸(결정·사실·남은 일·다음…)의 **내용**만 이은 검색 본문. 라벨(`결정:`)·날짜·방/@ 호출 표시는 뺀다 —
    넣으면 "결정"·"방" 같은 낱말이 내용과 상관없이 모든 요약에 맞는다."""
    try:
        slots = json.loads(raw) if raw else {}
    except ValueError:
        return ""
    if not isinstance(slots, dict):
        return ""
    return " ".join(str(x) for v in slots.values() if isinstance(v, list) for x in v).lower()


_SPOOF = re.compile(r"(?m)^(?=■|\[기억 검색\])")


def _defang(block: str) -> str:
    """저장된 본문 안의 줄바꿈으로 `■` 블록·`[기억 검색]` 머리를 흉내 내지 못하게 — 첫 줄(우리가 만든 머리)만 그대로 둔다."""
    head, _, rest = block.partition("\n")
    return head + ("\n" + _SPOOF.sub(" ", rest) if rest else "")


def _summary_items(project: str, agent_id: str) -> list:
    """[(날짜글자, 보여 줄 블록, 검색용 본문)] — 비어 있거나 깨진 행은 뺀다."""
    items = []
    for session_id, raw, updated_at in agent_summary_rows(project, agent_id, person(project)):
        block = summary_block(session_id, raw, updated_at)
        if block:
            items.append((str(updated_at or ""), _defang(block), _slot_text(raw)))
    return items


def _memory_items(project: str, agent_id: str) -> list:
    db = os.path.join(project, ".hermes", "state.db")
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        try:
            memories = current_memories(con, agent_id)
        finally:
            con.close()
    except sqlite3.OperationalError as exc:
        if "no such table" in str(exc):
            return []
        raise
    items = []
    for mem in memories:
        day = str(mem.get("ts") or "").replace("T", " ").rstrip("Z")
        block = _defang(f"■ {day[:10]} · 기억 · {mem.get('about') or '-'}\n  {mem.get('body') or ''}")
        items.append((day, block, f"{mem.get('about') or ''} {mem.get('body') or ''}".lower()))
    return items


def _fit(blocks: list, head: str, cap: int) -> str:
    """머리 + 블록들을 cap 바이트 안에. 못 들어간 것은 마지막 줄에 건수로 알린다."""
    used = len(head.encode("utf-8")) + 1
    tail_room = 90                                   # "… 외 N건 — 낱말을 좁혀 다시 찾는다" 자리
    kept = []
    for block in blocks:
        size = len(block.encode("utf-8")) + 1
        if used + size + tail_room > cap and kept:
            break
        if not kept and used + size + tail_room > cap:      # 첫 한 건도 안 들어가면 잘라서라도 넣는다
            room = max(cap - used - tail_room - 8, 0)         # 음수 슬라이스는 "끝에서 빼기" 라 통째로 나온다(리뷰 지적)
            block = block.encode("utf-8")[:room].decode("utf-8", errors="ignore").rstrip() + " …"
            size = len(block.encode("utf-8")) + 1
        kept.append(block)
        used += size
    lines = [head] + kept
    if len(kept) < len(blocks):
        lines.append(f"… 외 {len(blocks) - len(kept)}건 — 낱말을 좁혀 다시 찾는다")
    out = "\n".join(lines)
    if len(out.encode("utf-8")) > cap:                          # 어떤 입력에도 상한을 지킨다(마지막 안전망)
        out = out.encode("utf-8")[:cap - 4].decode("utf-8", errors="ignore").rstrip() + " …"
    return out


def search(project: str, agent: dict, query: str) -> str:
    """검색 결과 글(머리 포함). 읽기 실패는 sqlite3.Error 로 올린다."""
    terms = clean_terms(query)
    if not terms:
        return f"{MARK} {agent['name']} — 쓸 수 있는 낱말이 없습니다 (2자 이상의 글자·숫자 낱말로 다시 찾는다)"
    items = _summary_items(project, agent["agent_id"])
    memories = _memory_items(project, agent["agent_id"])
    scored = [(_score(text, terms), day, block) for day, block, text in items + memories]
    hits = sorted((h for h in scored if h[0] > 0), key=lambda h: (h[0], h[1]), reverse=True)
    label = f"{MARK} {agent['name']} · 낱말: {' '.join(terms)}"
    if not hits:
        return f"{label} — 찾지 못했습니다 (요약 {len(items)}개 · 기억 {len(memories)}개를 읽었습니다)"
    return _fit([h[2] for h in hits], f"{label} — {len(hits)}건 (요약 {len(items)}개 · 기억 {len(memories)}개 중)", _CAP)


def _refusal(agent, env: dict):
    """거부 사유 글. 거부할 것이 없으면 None. 호출자 확인은 소환 세션(HERMES_AGENT_ID)에서만 된다."""
    if agent is None:
        return "명부에 없는 에이전트"
    if agent.get("status") == "retired":
        return f"은퇴한 에이전트: {agent['name']}"
    caller = env.get("HERMES_AGENT_ID")
    if caller and caller != agent["agent_id"]:
        return f"소환된 에이전트는 자기 기억만 찾을 수 있다 ({agent['name']} 은 호출자가 아니다)"
    return None


def run(project: str, who: str, query: str, env: dict = None) -> int:
    """CLI 본체 — 결과를 찍고 종료 코드를 돌려준다(0 · 1 읽기 실패 · 2 거부/사용법)."""
    if not query.strip():
        print('사용: hermes-agent.py recall <호출명|이름|id> "<낱말>"', file=sys.stderr)
        return 2
    try:
        roster = load_roster(project)
    except (OSError, ValueError, KeyError) as exc:
        print(f"[hermes-agent] 명부를 읽지 못했습니다: {exc}", file=sys.stderr)
        return 1
    try:
        agent = resolve_agent(roster, who)
    except Ambiguous as exc:
        print(f"[hermes-agent] 거부: {exc}", file=sys.stderr)
        return 2
    reason = _refusal(agent, os.environ if env is None else env)
    if reason:
        print(f"[hermes-agent] 거부: {reason}", file=sys.stderr)
        return 2
    if not os.path.isfile(os.path.join(project, ".hermes", "state.db")):
        print(f"{MARK} {agent['name']} — 기억 저장소가 없습니다 (.hermes/state.db)")
        return 0
    try:
        print(search(project, agent, query))
    except sqlite3.Error as exc:
        print(f"{MARK} {agent['name']} — 읽지 못했습니다 ({exc}). 없다는 뜻이 아니다 — 잠시 뒤 다시 찾는다")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(run(os.getcwd(), sys.argv[1] if len(sys.argv) > 1 else "", " ".join(sys.argv[2:])))

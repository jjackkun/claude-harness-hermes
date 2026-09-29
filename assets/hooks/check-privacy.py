#!/usr/bin/env python3
"""R-privacy — 스테이징된 에이전트 지식 파일·스킬에 올리기 전 확인을 마치지 않은 문장이 있으면 커밋을 막는다.

본다: .hermes/agents/*/memory.jsonl · .hermes/agents/*/conversations/** · .hermes/journal.jsonl ·
      .hermes/skills/**/*.md · .hermes/agents/*/skills/**/*.md
통과: 문장마다 판정 표(privacy_review) 상태가 clean(판정 통과) 또는 keep(사람이 둠).
막음: pending(검토 대기) · drop(지움) · 판정 기록 없음 · **지금 마스킹 규칙으로 다시 가리면 달라지는 문장**
(옛 규칙 때 통과 판정을 받았어도 비밀·개인정보가 가려지지 않은 채 올라가지 않게 — 고치기: hermes-privacy-scrub.py files).
jsonl 은 이번에 **더해진 줄**만 본다(이미 올라간 줄은 이미 통과했다). 스킬·대화 요약은 스테이징된 본문 전체.
모델을 부르지 않는다(게이트는 모델을 안 부른다, R3) — 판정은 세션 끝 내보내기가 한다.
판정 표(state.db)나 헤르메스 스크립트가 없으면 건너뛴다(CI·헤르메스 없는 저장소). 종료 코드 0 통과 · 1 차단 · 2 건너뜀 · 3 스크립트가 구버전(재설치 필요).
계획: docs/exec-plans/completed/2026-09-28-carry-agent-knowledge.md 목표 8
"""

import fnmatch
import json
import os
import sqlite3
import subprocess
import sys

_PATTERNS = (".hermes/agents/*/memory.jsonl", ".hermes/agents/*/conversations/*", ".hermes/journal.jsonl",
             ".hermes/skills/*.md", ".hermes/agents/*/skills/*.md")
_SLOTS = ("decisions", "open", "prefs", "facts", "next")
_SHOW = 5                                  # 메시지에 보일 문장 수 — 나머지는 확인 명령이 보인다


def _git(*args) -> str:
    return subprocess.run(["git", *args], capture_output=True, text=True).stdout


def _staged() -> list:
    names = _git("diff", "--cached", "--name-only", "--diff-filter=ACM").splitlines()
    return [n for n in names if any(fnmatch.fnmatch(n, p) for p in _PATTERNS)]


def _added_json_lines(path: str) -> list:
    out = []
    for line in _git("diff", "--cached", "-U0", "--", path).splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            try:
                out.append(json.loads(line[1:]))
            except ValueError:
                continue
    return out


def _memory_texts(path: str) -> list:
    rows = [r for r in _added_json_lines(path) if isinstance(r, dict)]
    return [r["body"] for r in rows if r.get("body")]


def _journal_texts(path: str) -> list:
    rows = [r for r in _added_json_lines(path) if isinstance(r, dict)]
    texts = [r[k] for r in rows for k in ("intent", "lesson") if r.get(k)]
    return texts + [r["decision"] for r in rows if r.get("kind") == "decision" and r.get("decision")]


def _conversation_texts(blob: str) -> list:
    try:
        slots = (json.loads(blob) or {}).get("slots") or {}
    except ValueError:
        return [blob]                      # 깨진 파일 — 통째로 판정 기록이 없으니 막힌다
    return [str(x) for k in _SLOTS for x in (slots.get(k) or [])]


def _texts(path: str) -> list:
    if path.endswith("memory.jsonl"):
        return _memory_texts(path)
    if path.endswith("journal.jsonl"):
        return _journal_texts(path)
    blob = _git("show", f":{path}")
    return _conversation_texts(blob) if "/conversations/" in path else [blob]


def _first_line(text) -> str:
    lines = str(text).strip().splitlines()
    return lines[0][:80] if lines else ""


def _report(bad: list, drift: list) -> int:
    if not (bad or drift):
        return 0
    if bad:
        print(f"[R-privacy] 올리기 전 확인을 마치지 않은 문장 {len(bad)}개가 스테이징돼 있습니다.")
        for path, text in bad[:_SHOW]:
            print(f"  {path}: {_first_line(text)}")
        print("  → 판정: python3 scripts/hermes-knowledge-files.py export")
        print("  → 확인(지움/둠): python3 scripts/hermes-privacy-review.py")
        print("  → 지운 스킬은 스테이징에서 빼십시오: git restore --staged <파일>")
    if drift:
        print(f"[R-privacy] 지금 마스킹 규칙으로 다시 가리면 달라지는 문장 {len(drift)}개가 스테이징돼 있습니다(비밀·개인정보가 가려지지 않았을 수 있음).")
        for path, text in drift[:_SHOW]:
            print(f"  {path}: {_first_line(text)}")
        print("  → 다시 가리기: python3 scripts/hermes-privacy-scrub.py files --apply  (그 뒤 git add, 새 문장은 export 로 재판정)")
    return 1


def main() -> int:
    top = _git("rev-parse", "--show-toplevel").strip()
    staged = _staged()
    if not staged:
        return 0
    scripts, db = os.path.join(top, "scripts"), os.path.join(top, ".hermes", "state.db")
    if not (os.path.isfile(db) and os.path.isfile(os.path.join(scripts, "hermes_privacy_pending.py"))):
        print("[R-privacy] 판정 표 없음 — 건너뜀", file=sys.stderr)
        return 2
    sys.path.insert(0, scripts)
    try:
        from hermes_privacy_pending import allowed, scrub
    except ImportError as exc:              # 스크립트가 구버전이라 필요한 모듈이 없다 — 조용히 넘기지 않고 알린다
        print(f"[R-privacy] 하네스 스크립트가 구버전이라 이 검사를 건너뜁니다 — 재설치 필요(bash update-all.sh): {exc}", file=sys.stderr)
        return 3
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    texts = [(p, t) for p in staged for t in _texts(p)]
    bad = [(p, t) for p, t in texts if not allowed(con, t)]
    drift = [(p, t) for p, t in texts if scrub(t, top) != t]     # 게이트도 내보내기와 같은 project 로 가린다
    con.close()
    return _report(bad, drift)


if __name__ == "__main__":
    sys.exit(main())

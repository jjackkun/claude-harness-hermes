#!/usr/bin/env python3
"""헤르메스 지식 생애주기 린트 — 압축 후보 판정기 (Part D).

3중 게이트를 **모두** 통과한 세션만 압축 후보로 뽑는다:
  ① 오래됨   — .hermes/history/<날짜>-<session>.jsonl 의 파일명 날짜 기준
  ② 미사용   — session_reuse 에 재활용 기록이 없음 (T1 이 공급하는 신호)
  ③ 결정화됨 — pattern_session ⋈ pattern_count.crystallized=1

순수 나이 기반 압축은 금지(스펙) — ②·③ 이 실질 게이트다.
기본 모드는 **판정만** 한다. `--propose` 는 후보를 LLM 으로 주제 클러스터링해
제안 리포트(.hermes/lifecycle/<날짜>-proposal.md)만 쓴다 — history 원문·DB 는
절대 건드리지 않는다(실제 압축은 --apply 소관).
"""

import argparse
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from hermes_reuse import get_tracking_epoch
except ImportError:  # 헬퍼 미복사 — 추적 미도입으로 간주해 후보 0
    get_tracking_epoch = None
try:
    from hermes_redact import redact
except ImportError:  # 마스킹 헬퍼 부재 — LLM 입력을 만들지 않는다(안전측)
    redact = None

DATE_LEN = 10          # "YYYY-MM-DD"
SUFFIX = ".jsonl"

# LLM 입력 예산·타임아웃 — dream(_chunk_summaries/DREAM_TIMEOUT)과 같은 값을 기본으로 쓴다.
CHUNK_CHARS = int(os.environ.get("HERMES_LIFECYCLE_CHUNK_CHARS", "4000"))
LLM_TIMEOUT = int(os.environ.get("HERMES_LIFECYCLE_TIMEOUT", "90"))
# slots 없는 세션 폴백: 원문 전체가 아니라 앞부분만 — 5슬롯 요약에 준하는 분량 상한.
FALLBACK_LINES = int(os.environ.get("HERMES_LIFECYCLE_FALLBACK_LINES", "20"))


def _log(msg):
    print("[hermes-lifecycle] %s" % msg, file=sys.stderr)


def connect_db(db_path: str) -> sqlite3.Connection:
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def parse_history_name(name: str):
    """'<YYYY-MM-DD>-<session_id>.jsonl' → (date, session_id). 실패 시 (None, None)."""
    if not name.endswith(SUFFIX):
        return None, None
    stem = name[: -len(SUFFIX)]
    if len(stem) < DATE_LEN + 2 or stem[DATE_LEN] != "-":
        return None, None
    try:
        d = datetime.strptime(stem[:DATE_LEN], "%Y-%m-%d")
    except ValueError:      # unknown-date 등 — 나이 판정 불가라 제외(보수)
        return None, None
    return d, stem[DATE_LEN + 1:]


def _reused_ids(con) -> set:
    try:
        rows = con.execute(
            "SELECT session_id FROM session_reuse WHERE session_id != '__epoch__'"
        ).fetchall()
    except sqlite3.OperationalError:   # 테이블 부재 = 추적 미도입
        return set()
    return {r[0] for r in rows}


def _is_crystallized(con, session_id: str) -> bool:
    """이 세션이 기여한 패턴 중 결정화된 것이 있는가(근사 — 인과가 아니라 기여)."""
    try:
        row = con.execute(
            "SELECT 1 FROM pattern_session ps "
            "JOIN pattern_count pc ON pc.pattern_key = ps.pattern_key "
            "WHERE ps.session_id = ? AND pc.crystallized = 1 LIMIT 1",
            (session_id,),
        ).fetchone()
    except sqlite3.OperationalError:
        return False
    return row is not None


def select_candidates(con, hist_dir: str, now: datetime, age_days: int):
    """3중 게이트를 모두 통과한 session_id 목록(정렬)."""
    if get_tracking_epoch is None:
        return []
    epoch = get_tracking_epoch(con)
    if not epoch:
        return []                       # 추적 미도입 = 원년 → 후보 0 (D1)
    try:
        epoch_dt = datetime.fromisoformat(epoch)
    except ValueError:
        return []
    # 관측 기간 게이트: 추적을 켠 지 age_days 가 지나야 "그동안 안 쓰였다"를 신뢰할 수 있다.
    # (추적 이전 세션을 미사용으로 단정하지 않는 D1 보수 규칙의 구현)
    if (now - epoch_dt).days < age_days:
        return []
    if not os.path.isdir(hist_dir):
        return []

    reused = _reused_ids(con)
    out = []
    for name in os.listdir(hist_dir):
        d, sid = parse_history_name(name)
        if d is None or not sid:
            continue                     # ① 날짜 불명 — 제외
        if (now - d).days < age_days:
            continue                     # ① 아직 안 오래됨
        if sid in reused:
            continue                     # ② 재활용된 적 있음
        if not _is_crystallized(con, sid):
            continue                     # ③ 미결정화
        out.append(sid)
    return sorted(out)


# ───────────────── 압축 제안(dry-run) — LLM 주제 클러스터링 ─────────────────

CLUSTER_PROMPT = """\
아래는 오래되고 미사용인 대화 세션들의 압축 요약이다.
재사용 가치가 있는 지식을 주제로 묶고, 각 주제의 핵심을 짧게 요약하라.
출력은 JSON 배열 하나만. 설명·서두·코드펜스 금지.
각 원소: {{"topic": "주제(한 줄)", "session_ids": ["세션id", ...], "summary": "핵심 요약(2~3문장)"}}
묶을 지식이 없으면 [] 만 출력하라.

세션 요약:
{evidence}
"""


def _history_paths(hist_dir: str) -> dict:
    """{session_id: history 파일 경로}."""
    out = {}
    if not os.path.isdir(hist_dir):
        return out
    for name in os.listdir(hist_dir):
        _, sid = parse_history_name(name)
        if sid:
            out[sid] = os.path.join(hist_dir, name)
    return out


def _count_lines(path: str) -> int:
    try:
        with open(path, encoding="utf-8") as f:
            return sum(1 for _ in f)
    except OSError:
        return 0


def _fallback_evidence(path: str) -> str:
    """slots 부재 세션의 폴백 — history 앞부분 content 만. 읽기 전용."""
    lines = []
    try:
        with open(path, encoding="utf-8") as f:
            for i, raw in enumerate(f):
                if i >= FALLBACK_LINES:
                    break
                try:
                    content = json.loads(raw).get("content") or ""
                except (json.JSONDecodeError, AttributeError):
                    continue
                if content:
                    lines.append("- %s" % str(content).replace("\n", " ")[:200])
    except OSError:
        return ""
    return "\n".join(lines)


_REDACT_WARNED = False


def _warn_no_redact():
    """마스킹 헬퍼 부재 경고 — 프로세스당 1회만(세션마다 반복되면 노이즈)."""
    global _REDACT_WARNED
    if not _REDACT_WARNED:
        _REDACT_WARNED = True
        _log("hermes_redact 부재 — LLM 입력을 만들지 않는다(원문 유출 방지)")


def _session_evidence(con, sid: str, path: str) -> str:
    """세션 1건의 LLM 입력 텍스트. session_summary.slots_json 우선, 없으면 원문 폴백.
    부피·비용 때문에 원문 JSONL 전체는 절대 넣지 않는다. 마스킹은 안전 경계로 재적용."""
    slots = None
    try:
        row = con.execute(
            "SELECT slots_json FROM session_summary WHERE session_id=?", (sid,)
        ).fetchone()
        if row and row[0]:
            slots = json.loads(row[0])
    except (sqlite3.OperationalError, json.JSONDecodeError):
        slots = None

    lines = []
    if isinstance(slots, dict):
        for key, items in slots.items():
            for item in (items or []):
                lines.append("- [%s] %s" % (key, item))
    body = "\n".join(lines) or _fallback_evidence(path)
    if not body.strip():
        return ""
    text = "[session %s]\n%s" % (sid, body)
    if redact is None:      # 마스킹 부재 = LLM 입력 없음 (import 부 주석의 안전측 선언)
        _warn_no_redact()
        return ""
    return redact(text)


def _chunk_sessions(items, budget):
    """세션 evidence 를 char 예산으로 greedy 패킹(dream _chunk_summaries 골격).
    한 세션의 evidence 는 절대 분할하지 않는다. 반환: [{"ids": [...], "evidence": str}]."""
    chunks, cur_ids, cur_texts, cur_len = [], [], [], 0

    def flush():
        if cur_ids:
            chunks.append({"ids": list(cur_ids), "evidence": "\n\n".join(cur_texts)})

    for sid, text in items:
        if cur_ids and cur_len + len(text) > budget:
            flush()
            cur_ids, cur_texts, cur_len = [], [], 0
        cur_ids.append(sid)
        cur_texts.append(text)
        cur_len += len(text)
    flush()
    return chunks


def _parse_clusters(out: str, valid_ids: set):
    """LLM 출력 → 클러스터 목록. 파싱 실패는 예외로 올려 '보류'로 처리한다."""
    text = re.sub(r"^```[a-z]*\n", "", out.strip())
    text = re.sub(r"\n```$", "", text)
    data = json.loads(text)
    if isinstance(data, dict):
        data = data.get("clusters") or []
    clusters = []
    for item in data:
        if not isinstance(item, dict):
            continue
        # 환각 방지: 이번 청크에 실제로 넣은 세션만 남긴다.
        ids = [s for s in (item.get("session_ids") or []) if s in valid_ids]
        if not ids:
            continue
        clusters.append({
            "topic": str(item.get("topic") or "(무제)").strip(),
            "session_ids": ids,
            "summary": str(item.get("summary") or "").strip(),
        })
    return clusters


def _cluster_chunk(evidence: str, valid_ids: set):
    """한 청크를 주제 클러스터로. claude 부재·타임아웃·파싱실패는 None(=보류)."""
    if not evidence.strip():
        return []
    if not shutil.which("claude"):
        _log("claude 미발견 — 청크 보류")
        return None
    prompt = CLUSTER_PROMPT.format(evidence=evidence)
    for attempt in (1, 2):  # 1회 재시도
        try:
            result = subprocess.run(
                ["claude", "-p", prompt, "--model", "claude-haiku-4-5-20251001"],
                capture_output=True, text=True, timeout=LLM_TIMEOUT,
                env={**os.environ, "HERMES_DISABLED": "1"},
            )
            if result.returncode == 0:
                return _parse_clusters(result.stdout, valid_ids)
            _log("클러스터링 rc=%s (시도 %d)" % (result.returncode, attempt))
        except subprocess.TimeoutExpired:
            _log("클러스터링 타임아웃 %ss (시도 %d)" % (LLM_TIMEOUT, attempt))
        except Exception as e:
            _log("클러스터링 오류(시도 %d): %s" % (attempt, e))
    return None


def write_proposal(project: str, date: str, clusters, held, paths) -> str:
    """제안 리포트만 쓴다. history 원문·DB 는 건드리지 않는다(dry-run)."""
    out_dir = os.path.join(project, ".hermes", "lifecycle")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "%s-proposal.md" % date)
    total = sum(len(c["session_ids"]) for c in clusters)
    lines = ["---", "date: %s" % date, "hermes: lifecycle-proposal", "---", "",
             "# 압축 제안 (dry-run) · %s" % date, "",
             "클러스터 %d개 · 대상 세션 %d건 · 보류 %d건" % (len(clusters), total, len(held)),
             "",
             "> 제안일 뿐이다 — history 원문과 DB 는 변경되지 않았다. "
             "실제 압축은 검토 후 `--apply`.", ""]
    for i, c in enumerate(clusters, 1):
        before = sum(_count_lines(paths.get(s, "")) for s in c["session_ids"])
        saved = max(before - len(c["session_ids"]), 0)   # 세션당 요약본 1줄로 교체 가정
        lines += ["## 클러스터 %d: %s" % (i, c["topic"]), "",
                  "- 세션: %s" % ", ".join(c["session_ids"]),
                  "- 절약 예상: %d줄 → %d줄 (%d줄 절약)"
                  % (before, len(c["session_ids"]), saved), "",
                  c["summary"] or "(요약 없음)", ""]
    if not clusters:
        lines += ["## 클러스터", "", "- (없음)", ""]
    if held:
        lines += ["## 보류 (LLM 부재·실패·파싱실패 — 다음 기회에 재시도)", "",
                  "- %s" % ", ".join(held), ""]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return path


def propose(con, project: str, hist_dir: str, now: datetime, age_days: int):
    """후보 → 주제 클러스터 → 제안 리포트. 부작용은 리포트 파일 생성뿐."""
    candidates = select_candidates(con, hist_dir, now, age_days)
    if not candidates:
        return None                       # 조용한 종료 — 리포트도 안 쓴다
    paths = _history_paths(hist_dir)
    items = []
    for sid in candidates:
        text = _session_evidence(con, sid, paths.get(sid, ""))
        if text:
            items.append((sid, text))
    if not items:
        return None
    clusters, held = [], []
    for ch in _chunk_sessions(items, CHUNK_CHARS):
        got = _cluster_chunk(ch["evidence"], set(ch["ids"]))
        if got is None:
            held.extend(ch["ids"])        # 무손실: 그 청크는 이번엔 압축 제안 안 함
            continue
        clusters.extend(got)
    return write_proposal(project, now.strftime("%Y-%m-%d"), clusters, held, paths)


def main() -> int:
    p = argparse.ArgumentParser(description="헤르메스 생애주기 린트 — 압축 후보 판정")
    p.add_argument("--db", required=True)
    p.add_argument("--project", required=True)
    p.add_argument("--propose", action="store_true",
                   help="후보를 주제 클러스터링해 제안 리포트만 생성(dry-run)")
    p.add_argument("--age-days", type=int,
                   default=int(os.environ.get("HERMES_LIFECYCLE_AGE_DAYS", "90")))
    args = p.parse_args()

    if not os.path.isfile(args.db):
        return 0
    hist_dir = os.path.join(args.project, ".hermes", "history")
    con = connect_db(args.db)
    try:
        if args.propose:
            report = propose(con, args.project, hist_dir, datetime.now(), args.age_days)
            if report:
                print("[hermes-lifecycle] 압축 제안 → %s" % report)
        else:
            for sid in select_candidates(con, hist_dir, datetime.now(), args.age_days):
                print(sid)
    except Exception as exc:                      # 판정 실패가 파이프라인을 막지 않는다
        print("[hermes-lifecycle] 판정 실패: %s" % exc, file=sys.stderr)
    finally:
        con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

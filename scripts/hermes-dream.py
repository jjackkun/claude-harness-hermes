#!/usr/bin/env python3
"""헤르메스 드리밍 코어.

직전 드리밍 이후 누적된 5슬롯 세션 요약을 읽어:
  - 반복·지속된 결정/사실을 결정화 후보로 승격 → hermes-crystallize.py 구동(additive 자동)
  - junk 스킬은 삭제를 '제안'만(리포트), 실행은 --apply 게이트(hermes-cleanup.py)
조용한 날(요약 0)이라도 pending 이월 키가 있으면 드림이 돌아 이를 소진한다.
요약도 pending 도 없을 때만 dream_log 를 남기지 않고 조용히 끝난다.
(진화 구동은 Task 3 에서 추가)

사용법:
  python3 hermes-dream.py --db PATH --project-dir PATH [--apply]
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

# ───────────────────────── 데이터 접근 경계 ─────────────────────────
# 모든 SQL 은 이 구역에만 둔다. 향후 Postgres/Neo4j 이전 시 여기만 교체.

def connect_db(db_path: str) -> sqlite3.Connection:
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def _ensure_schema(con: sqlite3.Connection) -> None:
    con.execute("""
        CREATE TABLE IF NOT EXISTS dream_log (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            run_at          DATETIME DEFAULT CURRENT_TIMESTAMP,
            summary_count   INTEGER,
            crystallized    INTEGER,
            evolved         INTEGER,
            delete_proposed INTEGER,
            report_path     TEXT
        )
    """)
    con.execute("""
        CREATE TABLE IF NOT EXISTS session_summary (
            session_id     TEXT PRIMARY KEY,
            project_id     TEXT,
            slots_json     TEXT,
            last_msg_count INTEGER DEFAULT 0,
            turn_count     INTEGER DEFAULT 0,
            updated_at     DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    # 신규 컬럼 멱등 보강 (구버전 dream_log)
    cols = [r[1] for r in con.execute("PRAGMA table_info(dream_log)")]
    for col, ddl in (
        ("failed_chunks",  "ALTER TABLE dream_log ADD COLUMN failed_chunks INTEGER DEFAULT 0"),
        ("skipped_chunks", "ALTER TABLE dream_log ADD COLUMN skipped_chunks INTEGER DEFAULT 0"),
        ("watermark_at",   "ALTER TABLE dream_log ADD COLUMN watermark_at TEXT"),
    ):
        if col not in cols:
            con.execute(ddl)
    # 후보 키 이월 큐
    con.execute("""
        CREATE TABLE IF NOT EXISTS dream_pending_keys (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            key        TEXT NOT NULL UNIQUE,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    con.commit()


def get_dream_watermark(con):
    row = con.execute(
        "SELECT MAX(watermark_at) FROM dream_log WHERE watermark_at IS NOT NULL"
    ).fetchone()
    return row[0] if row and row[0] else None


def stall_count(con, since) -> int:
    """watermark_at 이 since 와 같은(NULL-안전) 최근 연속 dream_log 행 수.
    summary_count=0 행(조용한 날 pending 소진)은 청크 처리를 시도조차 안 했으므로
    stall 로 세지 않는다 — 안 그러면 false 독청크 skip 으로 증거가 폐기된다."""
    rows = con.execute(
        "SELECT watermark_at FROM dream_log WHERE summary_count > 0 ORDER BY id DESC"
    ).fetchall()
    n = 0
    for (wm,) in rows:
        same = (wm is None and since is None) or (wm == since)
        if same:
            n += 1
        else:
            break
    return n


def collect_summaries(con, since) -> list:
    rows = con.execute(
        "SELECT session_id, slots_json, updated_at FROM session_summary "
        "WHERE (? IS NULL OR updated_at > ?) ORDER BY updated_at",
        (since, since),
    ).fetchall()
    out = []
    for sid, raw, updated_at in rows:
        try:
            slots = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            slots = {}
        out.append({"session_id": sid, "slots": slots, "updated_at": updated_at})
    return out


def record_dream(con, summary_count, crystallized, evolved, delete_proposed,
                 report_path, watermark_at=None, failed_chunks=0, skipped_chunks=0):
    con.execute(
        "INSERT INTO dream_log "
        "(summary_count, crystallized, evolved, delete_proposed, report_path, "
        " watermark_at, failed_chunks, skipped_chunks) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (summary_count, crystallized, evolved, delete_proposed, report_path,
         watermark_at, failed_chunks, skipped_chunks),
    )
    con.commit()


def peek_pending_keys(con) -> int:
    """이월 큐에 남은 후보 키 개수 조회."""
    return con.execute("SELECT COUNT(*) FROM dream_pending_keys").fetchone()[0]


def drain_pending_keys(con, limit) -> list:
    """이월 큐에서 최대 limit 개의 키를 FIFO 순서(created_at, id)로 반환(삭제 안 함)."""
    rows = con.execute(
        "SELECT key FROM dream_pending_keys ORDER BY created_at, id LIMIT ?",
        (limit,),
    ).fetchall()
    return [r[0] for r in rows]


def enqueue_pending_keys(con, keys) -> None:
    """이월 큐에 키 목록을 추가(중복은 무시)."""
    for k in keys:
        if not k:
            continue
        con.execute(
            "INSERT OR IGNORE INTO dream_pending_keys (key) VALUES (?)", (k,)
        )
    con.commit()


def delete_pending_keys(con, keys) -> None:
    """이월 큐에서 소진된 키 목록을 삭제."""
    for k in keys:
        con.execute("DELETE FROM dream_pending_keys WHERE key=?", (k,))
    con.commit()

# ───────────────────────── 로직 ─────────────────────────

def _log(msg):
    print(f"[hermes-dream] {msg}", file=sys.stderr)


PROPOSE_PROMPT = """\
아래는 오늘 누적된 대화 요약의 '결정사항'과 '핵심 사실'이다.
이 중 앞으로 재사용할 가치가 있는 작업 지식만 골라, 각각 짧은 영문 kebab-case key 로 한 줄씩 출력하라.
재사용 가치가 없으면 다른 출력 없이 NONE 만 출력하라.
이것은 결정화 후보 key 목록이다. 설명·서두 금지.

결정사항·핵심 사실:
{evidence}
"""


DREAM_TIMEOUT = int(os.environ.get("HERMES_DREAM_TIMEOUT", "90"))
CHUNK_CHARS = int(os.environ.get("HERMES_DREAM_CHUNK_CHARS", "4000"))
CRYSTALLIZE_MAX = int(os.environ.get("HERMES_DREAM_CRYSTALLIZE_MAX", "10"))
STALL_SKIP = int(os.environ.get("HERMES_DREAM_STALL_SKIP", "3"))


def _parse_keys(out: str) -> list:
    if not out or out.splitlines()[0].strip().upper() == "NONE":
        return []
    keys = []
    for line in out.splitlines():
        k = re.sub(r"[^a-z0-9-]", "", line.strip().lower())
        if k and k not in keys:
            keys.append(k)
    return keys


def _propose_chunk(evidence: str):
    """한 청크 evidence(무손실)로 키 후보 추출. 타임아웃+1재시도, 실패면 None."""
    if not evidence.strip():
        return []          # 추출할 내용 없음 — 정상, 워터마크 전진 허용
    if not shutil.which("claude"):
        # claude 부재는 일시 실패로 취급 — [] 로 두면 워터마크가 증거 위로
        # 전진해 무신호 영구 손실. None 반환으로 첫실패 멈춤→다음 드림 재처리,
        # 영구 부재라도 STALL_SKIP 도달 시 로그된 skip 으로만 폐기된다.
        _log("claude 미발견 — 청크 보류")
        return None
    prompt = PROPOSE_PROMPT.format(evidence=evidence)
    for attempt in (1, 2):  # 1회 재시도
        try:
            result = subprocess.run(
                ["claude", "-p", prompt, "--model", "claude-haiku-4-5-20251001"],
                capture_output=True, text=True, timeout=DREAM_TIMEOUT,
                env={**os.environ, "HERMES_DISABLED": "1"},
            )
            if result.returncode == 0:
                return _parse_keys(result.stdout.strip())
            _log(f"propose 청크 rc={result.returncode} (시도 {attempt})")
        except subprocess.TimeoutExpired:
            _log(f"propose 청크 타임아웃 {DREAM_TIMEOUT}s (시도 {attempt})")
        except Exception as e:
            _log(f"propose 청크 오류(시도 {attempt}): {e}")
    return None


def _summary_evidence(summary) -> str:
    """한 요약의 decisions+facts 항목을 줄 단위 문자열로."""
    lines = []
    for k in ("decisions", "facts"):
        for item in (summary["slots"].get(k) or []):
            lines.append(f"- {item}")
    return "\n".join(lines)


def _chunk_summaries(summaries, budget):
    """요약을 char 예산으로 greedy 패킹. 요약은 절대 분할하지 않는다.
    빈 기여 요약도 청크의 summaries 에 포함(워터마크 전진용)이되 evidence 엔 빈 줄 제외.
    반환: [{"summaries": [...], "evidence": str, "last_updated_at": str}]."""
    chunks, cur, cur_texts, cur_len = [], [], [], 0

    def flush():
        nonlocal cur, cur_texts, cur_len
        if cur:
            chunks.append({
                "summaries": cur,
                "evidence": "\n".join(t for t in cur_texts if t),
                "last_updated_at": cur[-1].get("updated_at"),
            })
        cur, cur_texts, cur_len = [], [], 0

    for s in summaries:
        ev = _summary_evidence(s)
        # 현재 청크에 이미 내용이 있고, 추가 시 예산 초과면 먼저 flush.
        # 단 직전 요약과 updated_at 이 같으면 분할 금지 — 같은 워터마크 형제가
        # 다른 청크로 갈리면, 부분 실패 시 collect_summaries(updated_at > since)가
        # 미처리 형제를 영구 제외해 무손실 불변식이 깨진다(예산 초과는 감수).
        if (cur and cur_len + len(ev) > budget
                and cur[-1].get("updated_at") != s.get("updated_at")):
            flush()
        cur.append(s)
        cur_texts.append(ev)
        cur_len += len(ev)
    flush()
    return chunks


def _slot_text(summaries, keys) -> str:
    lines = []
    for s in summaries:
        for k in keys:
            for item in (s["slots"].get(k) or []):
                lines.append(f"- {item}")
    return "\n".join(lines)


def propose_keys(con, summaries, since):
    """map-reduce 무손실 키 추출. 첫 실패 멈춤(또는 STALL_SKIP 연속 정체 시 독 청크 skip).
    상한 초과 후보는 dream_pending_keys 로 이월.
    반환: (to_crystallize, watermark, failed_chunks, skipped_chunks)."""
    # 환경변수 재평가(테스트 오버라이드 대응)
    chunk_chars = int(os.environ.get("HERMES_DREAM_CHUNK_CHARS", str(CHUNK_CHARS)))
    cmax = int(os.environ.get("HERMES_DREAM_CRYSTALLIZE_MAX", str(CRYSTALLIZE_MAX)))
    stall_skip = int(os.environ.get("HERMES_DREAM_STALL_SKIP", str(STALL_SKIP)))

    stalls = stall_count(con, since)
    chunks = _chunk_summaries(summaries, chunk_chars)

    watermark = since          # 진척 없으면 since 그대로(불변) — stall 근거
    accumulated, failed_chunks, skipped_chunks = [], 0, 0
    i = 0
    while i < len(chunks):
        ch = chunks[i]
        keys = _propose_chunk(ch["evidence"])
        if keys is None:
            if stalls + 1 >= stall_skip:
                # 독 청크 — 영구 포기하고 워터마크 넘김
                sids = ",".join(s["session_id"] for s in ch["summaries"])
                _log(f"독 청크 skip — session_ids=[{sids}] (stall {stalls+1})")
                skipped_chunks += 1
                watermark = ch["last_updated_at"]
                i += 1
                continue
            # 첫 실패 — 멈춤, 남은 청크 보류
            failed_chunks = len(chunks) - i
            break
        accumulated.extend(keys)
        watermark = ch["last_updated_at"]
        i += 1

    # reduce: pending 먼저 + 누적, dedup, 기존 결정화 제외
    pending = drain_pending_keys(con, cmax)
    # pattern_count 는 hermes-init 소유 테이블 — 단독 실행 등으로 부재 시
    # "미결정화" 로 취급해 비차단 진행(스펙 §9). 정상 파이프라인은 init 선행이라 항상 존재.
    has_pc = con.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='pattern_count'"
    ).fetchone() is not None
    seen, candidates = set(), []
    for k in pending + accumulated:
        if k in seen:
            continue
        if has_pc:
            already = con.execute(
                "SELECT crystallized FROM pattern_count WHERE pattern_key=?", (k,)
            ).fetchone()
            if already and already[0] == 1:
                continue
        seen.add(k)
        candidates.append(k)

    to_crystallize = candidates[:cmax]
    overflow = candidates[cmax:]
    if overflow:
        enqueue_pending_keys(con, overflow)
    # 큐 정리: drain 한 pending 키 중 "아직 대기(overflow)" 가 아닌 것은 모두 삭제
    # — 이번에 결정화될 키(소진)와, dedup 에서 이미-결정화로 걸러진 junk 키(해소) 둘 다 제거.
    # 이 필터가 없으면 이미 결정화된 pending 키가 매 드림 재-drain 되어 큐가 영구히 막힌다.
    delete_pending_keys(con, [k for k in pending if k not in overflow])
    return to_crystallize, watermark, failed_chunks, skipped_chunks


def run_crystallize(keys, db, project_dir, scripts_dir) -> int:
    if not keys:
        return 0
    try:
        result = subprocess.run(
            ["python3", os.path.join(scripts_dir, "hermes-crystallize.py"),
             "--db", db, "--crystallize", ",".join(keys), "--project-dir", project_dir],
            capture_output=True, text=True, timeout=300,
            env={**os.environ, "HERMES_DISABLED": "1"},
        )
        return len(re.findall(r"^\[hermes\] DONE:", result.stdout, re.M))
    except Exception as e:
        _log(f"crystallize 오류: {e}")
        return 0


def run_cleanup(db, scripts_dir, apply) -> tuple:
    cmd = ["python3", os.path.join(scripts_dir, "hermes-cleanup.py"), "--db", db]
    if apply:
        cmd.append("--apply")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120,
                                env={**os.environ, "HERMES_DISABLED": "1"})
        text = result.stdout
        m = re.search(r"junk 스킬 파일: (\d+)개", text)
        proposed = int(m.group(1)) if m else 0
        return text, proposed
    except Exception as e:
        _log(f"cleanup 오류: {e}")
        return "", 0


_CORRECTION_RE = re.compile(r"(말고|대신|바꿔|수정|틀려|잘못|아니라|아니고)")
_SKILL_KW_RE = re.compile(
    r"(pnpm|npm|yarn|poetry|pip|docker|fastapi|svelte|postgres|mysql|redis"
    r"|pytest|vitest|eslint|prettier|ruff|mypy|버전|version)", re.IGNORECASE)


def collect_evolution_hints(summaries) -> list:
    hints, seen = [], set()
    for s in summaries:
        for k in ("open", "next", "decisions"):
            for item in (s["slots"].get(k) or []):
                if _CORRECTION_RE.search(item) and _SKILL_KW_RE.search(item):
                    kw = _SKILL_KW_RE.search(item).group(1).lower()
                    key = (kw, item[:50])
                    if key not in seen:
                        seen.add(key)
                        hints.append((kw, item[:200]))
    return hints


def run_evolve(hints, db, scripts_dir) -> int:
    n = 0
    for kw, feedback in hints:
        try:
            result = subprocess.run(
                ["python3", os.path.join(scripts_dir, "hermes-evolve-skill.py"),
                 "--db", db, "--keyword", kw, "--feedback", feedback],
                capture_output=True, text=True, timeout=300,
                env={**os.environ, "HERMES_DISABLED": "1"},
            )
            if "EVOLVED:" in result.stdout:
                n += 1
        except Exception as e:
            _log(f"evolve 오류({kw}): {e}")
    return n


def write_report(project_dir, date, *, summary_count, crystallized_keys,
                 evolved_keywords, delete_report) -> str:
    dreams = os.path.join(project_dir, ".hermes", "dreams")
    os.makedirs(dreams, exist_ok=True)
    path = os.path.join(dreams, f"{date}.md")
    lines = ["---", f"date: {date}", "hermes: dream", "---", "",
             f"# 드림 리포트 · {date}", "", f"읽은 요약: {summary_count}건", "",
             "## 결정화 (추가)"]
    lines += [f"- {k}" for k in crystallized_keys] if crystallized_keys else ["- (없음)"]
    lines += ["", "## 진화 (개선)"]
    lines += [f"- {k}" for k in evolved_keywords] if evolved_keywords else ["- (없음)"]
    lines += ["", "## 삭제 제안 (실행: /hermes-dream apply)", "```",
              (delete_report.strip() or "(없음)"), "```", ""]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return path


def main():
    parser = argparse.ArgumentParser(description="헤르메스 드리밍 코어")
    parser.add_argument("--db", required=True)
    parser.add_argument("--project-dir", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    if not os.path.isfile(args.db):
        _log(f"DB 없음: {args.db}")
        sys.exit(0)

    scripts_dir = os.path.dirname(os.path.abspath(__file__))
    con = connect_db(args.db)
    _ensure_schema(con)
    since = get_dream_watermark(con)
    summaries = collect_summaries(con, since)

    if not summaries and peek_pending_keys(con) == 0:
        print("[hermes-dream] 새 요약·이월 없음 — 조용히 종료")
        con.close()
        return

    keys, watermark, failed_chunks, skipped_chunks = propose_keys(con, summaries, since)
    crystallized = run_crystallize(keys, args.db, args.project_dir, scripts_dir)
    hints = collect_evolution_hints(summaries)
    evolved = run_evolve(hints, args.db, scripts_dir)
    delete_report, delete_proposed = run_cleanup(args.db, scripts_dir, args.apply)

    date = datetime.now().strftime("%Y-%m-%d")
    report_path = write_report(
        args.project_dir, date,
        summary_count=len(summaries),
        crystallized_keys=keys if crystallized else [],
        evolved_keywords=[kw for kw, _ in hints] if evolved else [],
        delete_report=delete_report,
    )
    record_dream(con, len(summaries), crystallized, evolved, delete_proposed,
                 report_path, watermark_at=watermark,
                 failed_chunks=failed_chunks, skipped_chunks=skipped_chunks)
    con.close()
    mode = "APPLY" if args.apply else "DRY-RUN"
    print(f"[hermes-dream] {mode}: 요약 {len(summaries)} · 결정화 {crystallized} · "
          f"진화 {evolved} · 삭제제안 {delete_proposed} · "
          f"보류 {failed_chunks} · 포기 {skipped_chunks} → {report_path}")


if __name__ == "__main__":
    main()

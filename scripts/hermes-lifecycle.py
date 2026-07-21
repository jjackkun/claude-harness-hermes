#!/usr/bin/env python3
"""헤르메스 지식 생애주기 린트 — 압축 후보 판정기 (Part D).

3중 게이트를 **모두** 통과한 세션만 압축 후보로 뽑는다:
  ① 오래됨   — .hermes/history/<날짜>-<session>.jsonl 의 파일명 날짜 기준
  ② 미사용   — session_reuse 에 재활용 기록이 없음 (T1 이 공급하는 신호)
  ③ 결정화됨 — pattern_session ⋈ pattern_count.crystallized=1

순수 나이 기반 압축은 금지(스펙) — ②·③ 이 실질 게이트다.
이 스크립트는 **판정만** 한다. 압축·덮어쓰기는 하지 않는다(부작용 없음).
"""

import argparse
import os
import sqlite3
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from hermes_reuse import get_tracking_epoch
except ImportError:  # 헬퍼 미복사 — 추적 미도입으로 간주해 후보 0
    get_tracking_epoch = None

DATE_LEN = 10          # "YYYY-MM-DD"
SUFFIX = ".jsonl"


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


def main() -> int:
    p = argparse.ArgumentParser(description="헤르메스 생애주기 린트 — 압축 후보 판정")
    p.add_argument("--db", required=True)
    p.add_argument("--project", required=True)
    p.add_argument("--age-days", type=int,
                   default=int(os.environ.get("HERMES_LIFECYCLE_AGE_DAYS", "90")))
    args = p.parse_args()

    if not os.path.isfile(args.db):
        return 0
    hist_dir = os.path.join(args.project, ".hermes", "history")
    con = connect_db(args.db)
    try:
        for sid in select_candidates(con, hist_dir, datetime.now(), args.age_days):
            print(sid)
    except Exception as exc:                      # 판정 실패가 파이프라인을 막지 않는다
        print("[hermes-lifecycle] 판정 실패: %s" % exc, file=sys.stderr)
    finally:
        con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

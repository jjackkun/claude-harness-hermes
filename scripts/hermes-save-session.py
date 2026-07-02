#!/usr/bin/env python3
"""헤르메스 세션 저장 스크립트.

Stop Hook에서 호출. Claude Code transcript를 읽어
session_history(FTS5)와 pattern_count 테이블에 저장한다.

같은 session_id 로 재저장하면 이전 행을 교체한다 (매 턴 누적 방지).
패턴 집계는 세션당 1회만 반영된다 (pattern_session 테이블로 보장).

로직은 다음 모듈로 분리되어 있다 (이 파일은 얇은 CLI 진입점):
  - hermes_save_session_storage.py  — DB 연결/transcript 로드/저장
  - hermes_save_session_signals.py  — B신호(테스트 실패, git revert) 탐지
  - hermes_save_session_patterns.py — 반복 패턴/스킬 수정 힌트 추출

사용법:
  python3 hermes-save-session.py --db PATH --transcript PATH \
      [--project-id ID] [--session-id ID]
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_save_session_patterns import (  # noqa: E402
    extract_evolution_hints,
    extract_patterns,
)
from hermes_save_session_signals import (  # noqa: E402
    detect_objective_signals,
    record_signal_context,
)
from hermes_save_session_storage import (  # noqa: E402
    load_transcript,
    save_session,
    update_patterns,
)


def main():
    parser = argparse.ArgumentParser(description="헤르메스 세션 저장")
    parser.add_argument("--db", required=True, help="state.db 경로")
    parser.add_argument("--transcript", required=True, help="transcript JSON 경로")
    parser.add_argument("--project-id", default="", help="프로젝트 식별자")
    parser.add_argument("--session-id", default="", help="세션 ID")
    args = parser.parse_args()

    if not os.path.isfile(args.db):
        print(f"[hermes] DB not found: {args.db}", file=sys.stderr)
        sys.exit(1)

    messages = load_transcript(args.transcript)
    if not messages:
        print("[hermes] transcript empty or not found — skipped")
        sys.exit(0)

    project_id = args.project_id or os.path.basename(os.path.dirname(args.db))
    # session_id 부재 시 transcript 경로 기반으로 안정적인 ID 를 만든다
    # (타임스탬프를 쓰면 매 턴 새 세션으로 저장돼 DB가 폭증한다 — C2)
    session_id = args.session_id or os.path.splitext(
        os.path.basename(args.transcript)
    )[0]

    save_session(args.db, messages, project_id, session_id)

    patterns = extract_patterns(messages, args.db)
    b_signals = detect_objective_signals(messages)
    b_keys = [k for k, _ in b_signals]
    if b_signals:
        record_signal_context(args.db, b_signals, project_id, session_id)
    crystallize = update_patterns(args.db, patterns + b_keys, session_id)

    if crystallize:
        print(f"[hermes] CRYSTALLIZE:{','.join(crystallize)}")
    else:
        print("[hermes] no crystallization needed")

    evolution_hints = extract_evolution_hints(messages)
    for kw, feedback in evolution_hints:
        print(f"[hermes] EVOLVE:{kw}|{feedback}")


if __name__ == "__main__":
    main()

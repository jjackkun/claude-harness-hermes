#!/usr/bin/env python3
"""헤르메스 결과 상관 — 주입 원장 ↔ transcript 편집경로 대조.

Stop 훅에서 호출. 이 세션에 주입된 스킬 중, transcript 의 Edit/Write/MultiEdit
대상 파일 경로 토큰과 스킬 키워드가 겹치면 helpful_count, 안 겹치면 noop_count 를
증가시킨다. 처리한 원장 행은 correlated=1 로 마킹해 중복 집계를 막는다.

비차단 — 항상 exit 0. 휴리스틱(키워드↔경로 겹침)이라 오탐·미탐 존재하나,
결과는 되돌릴 수 있는 강등으로만 이어진다.

사용법:
  python3 hermes-correlate.py --db PATH --transcript PATH --session-id ID
"""

import argparse
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timezone

# helpful 판정 최소 겹침 키워드 수 (설계 §4.3):
# 단어 하나짜리 파편 키워드로는 도달 불가(≥2 필요) → 파편 배제 + 단일 우연 겹침 거짓양성 차단.
MIN_KEYWORD_OVERLAP = int(os.environ.get("HERMES_CORRELATE_MIN_OVERLAP", "2"))

# 도구별 토큰화 대상 입력 필드 — 편집뿐 아니라 조회·실행·검색 활동까지 (설계 §4.2).
TOOL_TOKEN_FIELDS = {
    "edit": ("file_path",),
    "write": ("file_path",),
    "multiedit": ("file_path",),
    "read": ("file_path",),
    "bash": ("command",),
    "grep": ("pattern", "path"),
    "glob": ("pattern", "path"),
}


def connect_db(db_path: str) -> sqlite3.Connection:
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def _log(msg: str) -> None:
    print(f"[hermes-correlate] {msg}", file=sys.stderr)


def session_tool_tokens(transcript_path: str) -> set:
    """transcript JSONL 에서 세션의 모든 도구 활동 대상을 토큰 집합으로 모은다.

    편집(Edit/Write) 경로뿐 아니라 Read/Bash/Grep/Glob 의 대상 파일경로·명령·패턴까지
    포함한다 — 읽기·조회·테스트형 스킬도 효용 판정에 잡히게 하기 위함 (설계 §4.2).
    """
    tokens = set()
    try:
        with open(transcript_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                content = (obj.get("message") or {}).get("content")
                if not isinstance(content, list):
                    continue
                for blk in content:
                    if not isinstance(blk, dict):
                        continue
                    if blk.get("type") != "tool_use":
                        continue
                    fields = TOOL_TOKEN_FIELDS.get(str(blk.get("name", "")).lower())
                    if not fields:
                        continue
                    inp = blk.get("input") or {}
                    for field in fields:
                        val = str(inp.get(field, ""))
                        for tok in re.findall(r"[a-z0-9가-힣_\-]+", val.lower()):
                            if len(tok) >= 2:
                                tokens.add(tok)
    except Exception as e:
        _log(f"transcript 파싱 실패({transcript_path}): {e}")
    return tokens


def correlate(db_path: str, transcript_path: str, session_id: str) -> None:
    if not (os.path.isfile(db_path) and os.path.isfile(transcript_path) and session_id):
        return
    tokens = session_tool_tokens(transcript_path)
    now = datetime.now(timezone.utc).isoformat()
    try:
        con = connect_db(db_path)
        rows = con.execute(
            "SELECT id, skill_path FROM skill_injection "
            "WHERE session_id=? AND correlated=0",
            (session_id,),
        ).fetchall()
        for inj_id, skill_path in rows:
            kw_row = con.execute(
                "SELECT keywords FROM skill_index WHERE skill_path=?", (skill_path,)
            ).fetchone()
            kws = set()
            if kw_row and kw_row[0]:
                kws = {k for k in kw_row[0].lower().split(",") if len(k) >= 2}
            helped = len(kws & tokens) >= MIN_KEYWORD_OVERLAP
            if helped:
                con.execute(
                    "UPDATE skill_index SET helpful_count = helpful_count + 1, "
                    "last_helpful_at = ? WHERE skill_path = ?",
                    (now, skill_path),
                )
            else:
                con.execute(
                    "UPDATE skill_index SET noop_count = noop_count + 1 "
                    "WHERE skill_path = ?",
                    (skill_path,),
                )
            con.execute(
                "UPDATE skill_injection SET correlated=1 WHERE id=?", (inj_id,)
            )
        con.commit()
        con.close()
    except Exception as e:
        _log(f"상관 처리 실패: {e}")


def main():
    parser = argparse.ArgumentParser(description="헤르메스 결과 상관")
    parser.add_argument("--db", required=True)
    parser.add_argument("--transcript", required=True)
    parser.add_argument("--session-id", required=True)
    args = parser.parse_args()
    correlate(args.db, args.transcript, args.session_id)


if __name__ == "__main__":
    main()

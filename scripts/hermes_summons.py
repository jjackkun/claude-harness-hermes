#!/usr/bin/env python3
"""소환 토큰(nonce) — 발급·검증·사용 표시·만료만 담당한다.

에이전트 id 는 에이전트가 고르지 못한다(RV-06). 러너가 명부에서 대상을 찾아 1회용 nonce 를
발급하고 환경변수(`HERMES_AGENT_ID` · `HERMES_SUMMON_NONCE`)로 넘기면, 새 세션의 시작 훅이
짝·재사용·만료를 검증한다. `SubagentStop` 의 `agent_type` 은 직무 템플릿 이름이지 명부 id 가
아니므로 이 토큰이 없으면 남의 id 를 쓰는 것을 막을 수 없다(V-4).

  summons(nonce PK · agent_id · requested_by · issued_at · expires_at · used_at · session_id)
  .hermes/summons/<nonce>.pending   러너가 남기는 파일 — 세션 안 `claude -p` 가드가 이 존재로 판정
  .hermes/summons/<nonce>.verdict   시작 훅의 판정(ok | unverified:<사유>) — 기록기가 읽는다
계획: docs/exec-plans/active/2026-09-15-agent-identity.md 목표 5·6·7·16

공개 함수 6개: ensure_summons_table · issue · verify · consume · write_verdict · read_verdict
"""

import os
import secrets
import sqlite3
from datetime import datetime, timedelta, timezone

# 발급 뒤 세션 시작 훅이 검증하기까지의 허용 시간. 소환은 발급 직후 `claude -p` 를 띄우므로
# 필요한 것은 프로세스 기동 + 시작 훅 체인 시간뿐이다. 실측 근거가 아직 없어 넉넉히 두고
# HERMES_SUMMON_TTL_MIN 으로 바꾼다(계획 §7 "summons.expires_at 기본값 협의 대기").
_TTL_MIN = int(os.environ.get("HERMES_SUMMON_TTL_MIN", "10"))
_DIR = ".hermes/summons"
_SQL = """
CREATE TABLE IF NOT EXISTS summons (
  nonce        TEXT PRIMARY KEY,
  agent_id     TEXT NOT NULL,
  requested_by TEXT NOT NULL,
  issued_at    TEXT NOT NULL,
  expires_at   TEXT NOT NULL,
  used_at      TEXT,
  session_id   TEXT
);
"""


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _fmt(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def ensure_summons_table(con: sqlite3.Connection) -> None:
    """구 스키마 DB 에서도 훅이 죽지 않게 첫 실행 때 만든다(목표 16)."""
    con.executescript(_SQL)
    con.commit()


def _summons_dir(project: str) -> str:
    path = os.path.join(project, _DIR)
    os.makedirs(path, exist_ok=True)
    return path


def issue(con: sqlite3.Connection, project: str, agent_id: str, requested_by: str) -> str:
    """nonce 를 발급하고 pending 파일을 남긴다. 파일을 못 만들면 발급도 취소한다(§6)."""
    ensure_summons_table(con)
    nonce = secrets.token_hex(16)
    now = _now()
    con.execute("INSERT INTO summons (nonce, agent_id, requested_by, issued_at, expires_at)"
                " VALUES (?,?,?,?,?)",
                (nonce, agent_id, requested_by, _fmt(now), _fmt(now + timedelta(minutes=_TTL_MIN))))
    con.commit()
    pending = os.path.join(_summons_dir(project), f"{nonce}.pending")
    try:
        with open(pending, "w", encoding="utf-8") as fh:
            fh.write(f"{agent_id}\n")
    except OSError:
        con.execute("DELETE FROM summons WHERE nonce = ?", (nonce,))
        con.commit()
        raise
    return nonce


def verify(con: sqlite3.Connection, nonce: str, agent_id: str) -> tuple:
    """(ok, 사유). 부작용 없음. 사유: missing · mismatch · used · expired."""
    ensure_summons_table(con)
    row = con.execute("SELECT agent_id, expires_at, used_at FROM summons WHERE nonce = ?",
                      (nonce,)).fetchone()
    if row is None:
        return False, "missing"
    if row[0] != agent_id:
        return False, "mismatch"
    if row[2]:
        return False, "used"
    if _fmt(_now()) > row[1]:
        return False, "expired"
    return True, "ok"


def consume(con: sqlite3.Connection, project: str, nonce: str, session_id: str) -> None:
    """사용 표시. pending 파일을 지운다 — 가드가 더는 통과시키지 않는다."""
    con.execute("UPDATE summons SET used_at = ?, session_id = ? WHERE nonce = ?",
                (_fmt(_now()), session_id, nonce))
    con.commit()
    pending = os.path.join(project, _DIR, f"{nonce}.pending")
    if os.path.isfile(pending):
        os.unlink(pending)


def write_verdict(project: str, nonce: str, verdict: str) -> str:
    path = os.path.join(_summons_dir(project), f"{nonce}.verdict")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(verdict + "\n")
    return path


def read_verdict(project: str, nonce: str) -> str:
    """시작 훅의 판정. 없으면 'unverified:no-verdict' — 훅이 안 돌았으면 믿지 않는다."""
    path = os.path.join(project, _DIR, f"{nonce}.verdict")
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read().strip() or "unverified:empty"
    except OSError:
        return "unverified:no-verdict"

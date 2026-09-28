#!/usr/bin/env python3
"""로컬 산출물을 원격(`refs/hermes/sync`) 경로로 사상하고, 새 것만 고른다.
운반에 남은 것(계획 carry-agent-knowledge 목표 9·10): 패턴 수 · 판정 통과한 공통 요약. 평문 모드면 그대로, 잠금 모드면 자유 글만 암호문.
대화 원문은 어디에도 저장하지 않으므로 나르지 않는다. 에이전트 기억·작업 이력은 git 파일(hermes-knowledge-files)이 옮긴다.
자유 글은 올리기 직전 hermes_redact 를 거친다(T-20).

원격 배치:
  keys/<사람>/<지문>.pub · keys/<사람>/master.<지문>.age   — 자물쇠와 감싼 마스터(잠금 모드)
  summary/… · pattern/…                                    — 발전 재료(hermes_sync_learning, T-17)
옛 판이 올린 history/ · memory/ · journal/ 는 받지 않는다(RETIRED — 받는 쪽이 건너뛴다).

"새 것" 판정은 state.db 의 sync_cursor(받은 경로)·sync_outbox(올린 경로) 두 표로 한다.
계획: docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 2·8·10·11

공개 함수 5개: ensure_sync_tables · outgoing · mark_pushed · incoming_paths · carried_paths
"""

import glob
import os
import sqlite3

import hermes_crypto as crypto
from hermes_keys import key_path
from hermes_sync_learning import outgoing_learning

# 옛 판이 원격에 남긴 갈래 — 원문(history/)은 저장하지 않고, 기억·이력(memory/·journal/)은 git 파일이 옮긴다.
RETIRED = ("history/", "memory/", "journal/")
_SYNC_SQL = """
CREATE TABLE IF NOT EXISTS sync_outbox (
  path       TEXT PRIMARY KEY,
  pushed_at  TEXT
);
CREATE TABLE IF NOT EXISTS sync_cursor (
  path        TEXT PRIMARY KEY,
  imported_at TEXT NOT NULL
);
"""


def ensure_sync_tables(con: sqlite3.Connection) -> None:
    """두 표를 만든다(있으면 그대로) — 구 스키마 DB 에서도 훅이 죽지 않는다(목표 14·구버전 호환)."""
    con.executescript(_SYNC_SQL)
    con.commit()


def _pushed(con) -> set:
    return {r[0] for r in con.execute("SELECT path FROM sync_outbox WHERE pushed_at IS NOT NULL")}


def _imported(con) -> set:
    return {r[0] for r in con.execute("SELECT path FROM sync_cursor")}


def outgoing(con, project: str, universe_id: str, person: str, policy: dict = None) -> dict:
    """아직 올리지 않은 것들을 {원격 경로: 바이트} 로. 조각은 마스터 자물쇠로 잠근다.
    T-17: 기본은 발전 재료. 2026-09-28(계획 carry-agent-knowledge 목표 9): 에이전트 기억·작업 이력은 git 파일이 원본이라
    운반에서 뺐다 — 같은 표를 두 길로 나르면 한쪽이 낡은 사본이 된다. 운반에 남은 것은 패턴 수·공통 요약(판정 통과)."""
    policy = policy or {}
    plain = policy.get("mode", "locked") == "plain"          # T-18: 비공개 저장소는 평문, 열쇠 없음
    done = _pushed(con) | _imported(con)
    lock = None if plain else crypto.public_key(key_path(universe_id, "master"))
    out = {}
    if not plain:
        out.update(_outgoing_keys(universe_id, person, done))
    out.update(outgoing_learning(con, lock, done, project))
    return out


def _outgoing_keys(universe_id: str, person: str, done: set) -> dict:
    out = {}
    wrapped = os.path.join(key_path(universe_id), "wrapped")
    for path in sorted(glob.glob(os.path.join(wrapped, "*"))):
        remote = f"keys/{person}/{os.path.basename(path)}"
        if remote not in done:
            with open(path, "rb") as fh:
                out[remote] = fh.read()
    return out


def mark_pushed(con, paths, when: str) -> None:
    con.executemany("INSERT OR REPLACE INTO sync_outbox (path, pushed_at) VALUES (?, ?)",
                    [(p, when) for p in paths])
    con.commit()


def carried_paths(remote_paths) -> list:
    """원격 경로 중 받아 적재할 몫(summary/·pattern/) — 옛 갈래(RETIRED)와 열쇠(keys/)는 뺀다."""
    return [p for p in remote_paths if not p.startswith(RETIRED + ("keys/",))]


def incoming_paths(con, remote_paths, retry_skipped: bool = False) -> list:
    """원격에 있는데 아직 받지도 올리지도 않은 경로 — 다른 컴퓨터가 만든 것.
    평문 컴퓨터가 열쇠가 없어 건너뛴 암호문 조각(sync_cursor.imported_at = 'skip:locked')은 받은 것으로 친다(집계 고정 방지).
    잠금 모드 pull(retry_skipped=True)은 그것을 다시 받는다 — 열쇠가 생긴 컴퓨터가 뒤늦게 읽는 길."""
    done = _pushed(con) | _imported(con)
    if retry_skipped:
        done -= {r[0] for r in con.execute("SELECT path FROM sync_cursor WHERE imported_at = 'skip:locked'")}
    return [p for p in remote_paths if p not in done]

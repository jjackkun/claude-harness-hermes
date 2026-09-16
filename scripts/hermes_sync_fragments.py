#!/usr/bin/env python3
"""로컬 산출물을 원격(`refs/hermes/sync`) 경로로 사상하고, 새 것만 고른다.

원격 배치:
  keys/<사람>/<지문>.pub · keys/<사람>/master.<지문>.age   — 자물쇠와 감싼 마스터
  history/<session_id>/<순번>.enc                          — 턴 조각(마스터 자물쇠로 통째)
  history/<session_id>/<순번>.superseded                   — 압축 표시
  journal/<YYYY>/<MM>/<DD>/<event_id>.json                 — 기계 칸 평문, 자유 글 3칸 암호문(J-07)
  memory/…                                                 — 계획 4 (경로만 예약)

"새 것" 판정은 state.db 의 sync_cursor(받은 경로)·sync_outbox(올린 경로) 두 표로 한다.
계획: docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 2·8·10·11

공개 함수 6개: ensure_sync_tables · outgoing · mark_pushed · incoming_paths · import_fragment · import_journal
"""

import glob
import json
import os
import sqlite3

import hermes_crypto as crypto
from hermes_history_fragments import fragment_dir, superseded_names
from hermes_keys import key_path

_FREE_TEXT = ("intent", "lesson", "decision")
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


def outgoing(con, project: str, universe_id: str, person: str) -> dict:
    """아직 올리지 않은 것들을 {원격 경로: 바이트} 로. 조각은 마스터 자물쇠로 잠근다."""
    done = _pushed(con) | _imported(con)
    lock = crypto.public_key(key_path(universe_id, "master"))
    out = {}
    out.update(_outgoing_keys(universe_id, person, done))
    out.update(_outgoing_history(project, lock, done))
    out.update(_outgoing_journal(con, lock, done))
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


def _outgoing_history(project: str, lock: str, done: set) -> dict:
    out = {}
    hist = os.path.join(project, ".hermes", "history")
    for frag in sorted(glob.glob(os.path.join(hist, "*", "*.jsonl"))):
        sid = os.path.basename(os.path.dirname(frag))
        seq = os.path.basename(frag)[:-len(".jsonl")]
        remote = f"history/{sid}/{seq}.enc"
        if remote in done:
            continue
        with open(frag, "rb") as fh:
            out[remote] = crypto.encrypt_to([lock], fh.read())
    for sid_dir in sorted(glob.glob(os.path.join(hist, "*", ""))):
        sid = os.path.basename(os.path.dirname(sid_dir))
        for name in superseded_names(hist, sid):
            remote = f"history/{sid}/{name[:-len('.jsonl')]}.superseded"
            if remote not in done:
                out[remote] = b""
    return out


def _outgoing_journal(con, lock: str, done: set) -> dict:
    out = {}
    try:
        rows = con.execute("SELECT * FROM journal_events ORDER BY ts, event_id").fetchall()
        names = [d[0] for d in con.execute("SELECT * FROM journal_events LIMIT 0").description]
    except sqlite3.OperationalError:
        return out                         # 구 스키마 — 이력 없음
    for row in rows:
        event = dict(zip(names, row))
        day = (event.get("ts") or "")[:10].replace("-", "/") or "0000/00/00"
        remote = f"journal/{day}/{event['event_id']}.json"
        if remote in done:
            continue
        for field in _FREE_TEXT:          # 자유 글 3칸만 암호문(J-07). 기계 칸은 평문.
            if event.get(field):
                event[field] = crypto.encrypt_to([lock], event[field].encode(), armor=True).decode()
        out[remote] = json.dumps(event, ensure_ascii=False, sort_keys=True).encode()
    return out


def mark_pushed(con, paths, when: str) -> None:
    con.executemany("INSERT OR REPLACE INTO sync_outbox (path, pushed_at) VALUES (?, ?)",
                    [(p, when) for p in paths])
    con.commit()


def incoming_paths(con, remote_paths) -> list:
    """원격에 있는데 아직 받지도 올리지도 않은 경로 — 다른 컴퓨터가 만든 것."""
    done = _pushed(con) | _imported(con)
    return [p for p in remote_paths if p not in done]


def import_fragment(con, project: str, universe_id: str, remote: str, data: bytes, when: str) -> bool:
    """history/*.enc 를 복호해 로컬 조각으로 놓는다. 이미 있으면 덮지 않는다(추가 전용)."""
    hist = os.path.join(project, ".hermes", "history")
    parts = remote.split("/")
    if len(parts) != 3 or parts[0] != "history":
        return False
    sid, name = parts[1], parts[2]
    if name.endswith(".superseded"):
        _touch_superseded(hist, sid, name[:-len(".superseded")] + ".jsonl")
    elif name.endswith(".enc"):
        plain = crypto.decrypt_with(key_path(universe_id, "master"), data)
        dest = os.path.join(fragment_dir(hist, sid), name[:-len(".enc")] + ".jsonl")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if not os.path.exists(dest):
            with open(dest, "wb") as fh:
                fh.write(plain)
    else:
        return False
    con.execute("INSERT OR REPLACE INTO sync_cursor (path, imported_at) VALUES (?, ?)", (remote, when))
    con.commit()
    return True


def _touch_superseded(hist: str, sid: str, frag_name: str) -> None:
    from hermes_history_fragments import mark_superseded
    os.makedirs(fragment_dir(hist, sid), exist_ok=True)
    mark_superseded(hist, sid, [frag_name])


def import_journal(con, universe_id: str, remote: str, data: bytes, when: str) -> bool:
    """journal/*.json 을 복호해 journal_events 에 넣는다. 같은 event_id 가 있으면 건너뛴다."""
    try:
        event = json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return False
    master = key_path(universe_id, "master")
    for field in _FREE_TEXT:
        if event.get(field):
            event[field] = crypto.decrypt_with(master, event[field].encode()).decode()
    try:
        from hermes_journal_schema import ensure_schema, validate
        ensure_schema(con)
        row = validate(event)
        exists = con.execute("SELECT 1 FROM journal_events WHERE event_id = ?",
                             (row["event_id"],)).fetchone()
        if not exists:
            con.execute("INSERT INTO journal_events ({}) VALUES ({})".format(
                ", ".join(row), ", ".join("?" * len(row))), tuple(row.values()))
    except Exception as exc:               # noqa: BLE001 — 한 건 손상이 pull 전체를 막지 않는다
        import sys
        print(f"[hermes-sync] 이력 적재 실패 {remote}: {exc}", file=sys.stderr)
        return False
    con.execute("INSERT OR REPLACE INTO sync_cursor (path, imported_at) VALUES (?, ?)", (remote, when))
    con.commit()
    return True

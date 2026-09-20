#!/usr/bin/env python3
"""로컬 산출물을 원격(`refs/hermes/sync`) 경로로 사상하고, 새 것만 고른다.

원격 배치:
  keys/<사람>/<지문>.pub · keys/<사람>/master.<지문>.age   — 자물쇠와 감싼 마스터
  history/<session_id>/<순번>.enc                          — 턴 조각(마스터 자물쇠로 통째)
  history/<session_id>/<순번>.superseded                   — 압축 표시
  journal/<YYYY>/<MM>/<DD>/<event_id>.json                 — 기계 칸 평문, 자유 글 3칸 암호문(J-07)
  memory/<agent_id>/<memory_id>.json                        — 기억 이벤트 1개 = 파일 1개, body 만 암호문(C-14·C-20; 왕복 실측 2026-09-20)
  summary/… · pattern/…                                    — 발전 재료(hermes_sync_learning, T-17). history/ 는 정책 옵션

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
from hermes_sync_learning import open_text, outgoing_learning, seal_text
try:
    from hermes_redact import redact as _redact
except ImportError:            # 마스킹 모듈이 없는 옛 설치본 — 잠그기만 한다
    _redact = None

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


def outgoing(con, project: str, universe_id: str, person: str, policy: dict = None) -> dict:
    """아직 올리지 않은 것들을 {원격 경로: 바이트} 로. 조각은 마스터 자물쇠로 잠근다.
    T-17: 기본은 발전 재료(요약·패턴·기억·작업 이력). 대화 원문(history/)은 정책 `"history": true` 일 때만."""
    policy = policy or {}
    plain = policy.get("mode", "locked") == "plain"          # T-18: 비공개 저장소는 평문, 열쇠 없음
    done = _pushed(con) | _imported(con)
    lock = None if plain else crypto.public_key(key_path(universe_id, "master"))
    out = {}
    if not plain:
        out.update(_outgoing_keys(universe_id, person, done))
        if policy.get("history"):                              # 원문은 잠금 모드에서만 (T-17)
            out.update(_outgoing_history(project, lock, done))
    out.update(_outgoing_journal(con, lock, done, project))
    out.update(_outgoing_memory(con, lock, done, project))
    out.update(outgoing_learning(con, lock, done, project))
    return out


def _free_text(lock, text, project: str):
    """자유 글 한 칸: 업로드 직전 마스킹 게이트(T-20) → 잠금 모드면 암호문, 평문 모드면 그대로."""
    if not text:
        return text
    if _redact is not None:
        text = _redact(text, project_dir=project)
    return seal_text(lock, text)


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


def _outgoing_journal(con, lock, done: set, project: str = None) -> dict:
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
        for field in _FREE_TEXT:          # 자유 글 3칸만 마스킹+잠금(J-07·T-20). 기계 칸은 평문.
            if event.get(field):
                event[field] = _free_text(lock, event[field], project)
        out[remote] = json.dumps(event, ensure_ascii=False, sort_keys=True).encode()
    return out


def _outgoing_memory(con, lock, done: set, project: str = None) -> dict:
    """기억 이벤트를 memory/<agent_id>/<memory_id>.json 으로. body 만 암호문(6절)."""
    out = {}
    try:
        rows = con.execute("SELECT * FROM memory_events ORDER BY ts, memory_id").fetchall()
        names = [d[0] for d in con.execute("SELECT * FROM memory_events LIMIT 0").description]
    except sqlite3.OperationalError:
        return out
    for row in rows:
        event = dict(zip(names, row))
        remote = f"memory/{event['agent_id']}/{event['memory_id']}.json"
        if remote in done:
            continue
        if event.get("body"):
            event["body"] = _free_text(lock, event["body"], project)
        out[remote] = json.dumps(event, ensure_ascii=False, sort_keys=True).encode()
    return out


def import_memory(con, universe_id: str, remote: str, data: bytes, when: str) -> bool:
    """memory/*.json 을 복호해 memory_events 에 넣는다. 같은 memory_id 면 건너뛴다."""
    try:
        event = json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return False
    if event.get("body"):
        event["body"] = open_text(universe_id, event["body"])     # 암호문이면 복호, 평문이면 그대로
    try:
        from hermes_memory_events import ensure_memory_schema, record
        ensure_memory_schema(con)
        exists = con.execute("SELECT 1 FROM memory_events WHERE memory_id = ?",
                             (event.get("memory_id"),)).fetchone()
        if not exists:
            record(con, event)
    except Exception as exc:               # noqa: BLE001
        import sys
        print(f"[hermes-sync] 기억 적재 실패 {remote}: {exc}", file=sys.stderr)
        return False
    con.execute("INSERT OR REPLACE INTO sync_cursor (path, imported_at) VALUES (?, ?)", (remote, when))
    con.commit()
    return True


def mark_pushed(con, paths, when: str) -> None:
    con.executemany("INSERT OR REPLACE INTO sync_outbox (path, pushed_at) VALUES (?, ?)",
                    [(p, when) for p in paths])
    con.commit()


def incoming_paths(con, remote_paths, retry_skipped: bool = False) -> list:
    """원격에 있는데 아직 받지도 올리지도 않은 경로 — 다른 컴퓨터가 만든 것.
    평문 컴퓨터가 열쇠가 없어 건너뛴 암호문 조각(sync_cursor.imported_at = 'skip:locked')은 받은 것으로 친다(집계 고정 방지).
    잠금 모드 pull(retry_skipped=True)은 그것을 다시 받는다 — 열쇠가 생긴 컴퓨터가 뒤늦게 읽는 길."""
    done = _pushed(con) | _imported(con)
    if retry_skipped:
        done -= {r[0] for r in con.execute("SELECT path FROM sync_cursor WHERE imported_at = 'skip:locked'")}
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
    for field in _FREE_TEXT:
        if event.get(field):
            event[field] = open_text(universe_id, event[field])   # 암호문이면 복호, 평문이면 그대로
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

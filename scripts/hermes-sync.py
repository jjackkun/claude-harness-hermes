#!/usr/bin/env python3
"""기억 운반 CLI — 훅·사람이 부르는 진입점.

  status     이식 상태와 "기억 없음" 3분류(H-11)
  push       아직 올리지 않은 조각·이력·자물쇠를 refs/hermes/sync 로
  pull       원격의 새 조각·이력을 받아 복호·적재 (열쇠 없으면 H-10 안내)
  backfill   이 컴퓨터 DB 의 기존 원문을 조각으로 만들어 올린다 (세션당 1회, 멱등)
  tombstone  원격·로컬에서 경로 하나를 지운다 — **사람 실행 전용**(세션 안 차단)

push 정책은 `.hermes/sync.json`(컴퓨터 로컬, 커밋 안 함). 없으면 로컬 전용(C).
  {"push": true, "remote": "origin"}
계획: docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 6~11·14·15
"""

import argparse
import json
import os
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hermes_crypto as crypto  # noqa: E402
import hermes_sync_ref as ref  # noqa: E402
from hermes_keys import key_path  # noqa: E402
from hermes_sync_fragments import (  # noqa: E402
    ensure_sync_tables, import_fragment, import_journal, import_memory, incoming_paths,
    mark_pushed, outgoing)
from hermes_sync_learning import import_learning  # noqa: E402
from hermes_universe import universe_id  # noqa: E402

NO_STORE = "원격에 기억 저장소(refs/hermes/sync)가 없습니다"
MSG_KEYLESS = "열쇠가 없습니다 — 조각 {n}건을 열 수 없습니다. 다른 컴퓨터에서 hermes-keys.sh add-computer 로 이 컴퓨터 자물쇠를 등록하십시오(H-10, 절차: docs/hermes-sync-guide.md)"
NOTHING = "기억 0건 — 저장소·열쇠는 있으나 받은 조각이 없습니다"
UNSUPPORTED = "이식 불가 — 사람 판단: 서버가 refs/hermes/sync 를 거부합니다(T-15)"


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _policy(project: str) -> dict:
    try:
        with open(os.path.join(project, ".hermes", "sync.json"), encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def _person(project: str) -> str:
    try:
        name = subprocess.run(["git", "-C", project, "config", "user.name"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        name = ""
    return name or "unknown"


def _connect(project: str) -> sqlite3.Connection:
    con = sqlite3.connect(os.path.join(project, ".hermes", "state.db"))
    ensure_sync_tables(con)
    return con


def _has_master(uid: str) -> bool:
    return os.path.isfile(key_path(uid, "master"))


def _try_join(project: str, uid: str, remote_paths: list, person: str) -> bool:
    """마스터가 없고 이 컴퓨터 자물쇠는 있을 때, 원격에 감싼 마스터가 있으면 푼다(합류)."""
    comp = key_path(uid, "computer")
    if _has_master(uid) or not os.path.isfile(comp):
        return False
    from hermes_keys import fingerprint, unwrap_master
    fp = fingerprint(crypto.public_key(comp))
    for path in remote_paths:
        if path.endswith(f"master.{fp}.age"):
            unwrap_master(comp, ref.read_blob(project, path), key_path(uid, "master"))
            print(f"[hermes-sync] 이 컴퓨터 자물쇠로 감싼 마스터를 받아 풀었습니다 ({path})")
            return True
    return False


def _my_remote_paths(project: str, policy: dict) -> list:
    """이 컴퓨터가 받을 몫: 평문 모드는 원문(.enc)·열쇠 빼고 전부, 잠금 모드는 원문 조각."""
    paths = ref.list_remote(project)
    if _mode(policy) == "plain":
        return [p for p in paths if not p.startswith(("history/", "keys/"))]
    return [p for p in paths if p.startswith("history/") and p.endswith(".enc")]


def _classify(project: str, uid: str, policy: dict) -> str:
    """"기억 없음" 3분류(H-11) + 참조 거부(T-15) 를 한 문장으로."""
    try:
        has_store = ref.fetch(project, policy.get("remote", "origin"))
    except ref.SyncRefError as exc:
        return UNSUPPORTED if exc.unsupported else f"[hermes-sync] fetch 실패: {exc}"
    if not has_store:
        return NO_STORE
    frags = _my_remote_paths(project, policy)
    if _mode(policy) == "locked" and not _has_master(uid):
        return MSG_KEYLESS.format(n=len(frags))
    con = _connect(project)
    pending = incoming_paths(con, frags)
    imported = con.execute("SELECT COUNT(*) FROM sync_cursor").fetchone()[0]
    con.close()
    if imported == 0 and not pending:
        return NOTHING
    return f"받은 조각 {imported}건 · 아직 안 받은 조각 {len(pending)}건 · 원격 조각 {len(frags)}건"


def cmd_status(args) -> int:
    project, uid = args.project, universe_id(args.project)
    policy = _policy(project)
    print(f"소우주 {uid[:8]} · 이식 {'켜짐' if policy.get('push') else '꺼짐(로컬 전용)'}"
          f" · age {'있음' if crypto.age_available() else '없음'}"
          f" · 마스터 열쇠 {'있음' if _has_master(uid) else '없음'}")
    if policy.get("push"):
        print(_classify(project, uid, policy))
    return 0


def _precheck(args, verb: str):
    """push·pull 공통 전제 — 정책 켜짐 · age 있음. 아니면 한 줄 남기고 None(목표 14)."""
    policy = _policy(args.project)
    if not policy.get("push") and not args.force_policy:
        print(f"[hermes-sync] 이식 꺼짐(로컬 전용) — .hermes/sync.json 에 {{\"push\": true}} 로 켭니다")
        return None
    if _mode(policy) == "locked" and not crypto.age_available():   # 평문 모드는 age 가 필요 없다(T-18)
        print(f"[hermes-sync] age 가 없어 {verb} 을 건너뜁니다")
        return None
    return policy


def _mode(policy: dict) -> str:
    """'plain' 또는 'locked'. 칸이 없으면 locked(구버전 정책 파일 호환)."""
    return "plain" if str(policy.get("mode", "locked")).lower() == "plain" else "locked"


def cmd_push(args) -> int:
    project, uid = args.project, universe_id(args.project)
    policy = _precheck(args, "push")
    if policy is None:
        return 0
    if _mode(policy) == "plain" and policy.get("history"):
        print("[hermes-sync] 거부: 대화 원문(history)은 잠금 모드에서만 올립니다 — sync.json 의 \"history\" 를 빼거나 \"mode\": \"locked\" 로", file=sys.stderr)
        return 2
    if _mode(policy) == "locked" and not _has_master(uid):
        print("[hermes-sync] 마스터 열쇠가 없어 push 를 보류합니다 (hermes-keys.sh init 또는 pull 로 합류)")
        return 0
    con = _connect(project)
    files = outgoing(con, project, uid, _person(project), policy)
    if not files:
        print("[hermes-sync] 올릴 것 없음")
        con.close()
        return 0
    try:
        commit = ref.push_with_retry(project, files, policy.get("remote", "origin"))
    except ref.SyncRefError as exc:
        print(UNSUPPORTED if exc.unsupported else f"[hermes-sync] push 실패: {exc}", file=sys.stderr)
        con.close()
        return 1
    mark_pushed(con, files.keys(), _now())
    con.close()
    print(f"[hermes-sync] {len(files)}건 올림 → {ref.REF} ({commit[:7]})")
    return 0


def _import_all(con, project: str, uid: str, paths, plain: bool = False) -> int:
    got = 0
    touched = set()
    for path in paths:
        data = ref.read_blob(project, path)
        if plain and _is_locked_fragment(path, data):
            # 잠금 모드 컴퓨터가 올린 암호문 — 열쇠 없는 평문 컴퓨터의 몫이 아니다(T-18).
            # 받은 것으로 표시해 "안 받은 조각" 집계에 영원히 남지 않게 한다. 잠금 모드로 바뀌면 다시 받는다(retry_skipped).
            con.execute("INSERT OR IGNORE INTO sync_cursor (path, imported_at) VALUES (?, 'skip:locked')", (path,))
            con.commit()
            continue
        if path.startswith("history/"):
            got += import_fragment(con, project, uid, path, data, _now())
        elif path.startswith("journal/"):
            got += import_journal(con, uid, path, data, _now())
        elif path.startswith("memory/"):
            if import_memory(con, uid, path, data, _now()):
                got += 1
                touched.add(path.split("/")[1])
        elif path.startswith(("summary/", "pattern/")):
            got += import_learning(con, uid, path, data, _now())
    _refresh_memory_views(con, project, touched)
    return got


def _is_locked_fragment(path: str, data: bytes) -> bool:
    """자유 글 칸이 age 암호문인 조각인가 — JSON 필드 값의 접두어로만 판별한다(본문에 그 글자가 적힌 평문은 오탐하지 않는다)."""
    if not path.endswith(".json"):
        return path.endswith(".enc")
    try:
        body = json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return False
    return any(isinstance(v, str) and v.startswith("-----BEGIN AGE") for v in body.values())


def _refresh_memory_views(con, project: str, agent_ids: set) -> None:
    """받은 기억이 있는 에이전트의 MEMORY.md 를 이벤트에서 다시 만든다(계획 agent-memory-roundtrip 목표 1).
    보기 갱신 실패는 받기 자체를 되돌리지 않는다 — 원본은 이미 memory_events 에 있다."""
    if not agent_ids:
        return
    from hermes_memory_view import write_memory_md
    try:
        from hermes_roster import load_roster, find_agent
        roster = load_roster(project)
    except Exception:                      # noqa: BLE001 — 명부 없음/손상: 이름 없이 만든다
        roster, find_agent = {"agents": []}, (lambda r, x: None)
    for aid in sorted(agent_ids):
        agent = find_agent(roster, aid) or {}
        try:
            write_memory_md(con, project, aid, agent.get("name"))
        except Exception as exc:           # noqa: BLE001
            print(f"[hermes-sync] 기억 보기 갱신 실패 agent={aid[:8]}: {exc}", file=sys.stderr)


def cmd_pull(args) -> int:
    project, uid = args.project, universe_id(args.project)
    policy = _precheck(args, "pull")
    if policy is None:
        return 0
    try:
        if not ref.fetch(project, policy.get("remote", "origin")):
            print(NO_STORE)
            return 0
    except ref.SyncRefError as exc:
        print(UNSUPPORTED if exc.unsupported else f"[hermes-sync] fetch 실패: {exc}")
        return 0
    remote_paths = ref.list_remote(project)
    if _mode(policy) == "plain":
        # 평문 모드: 열쇠 없이 평문 조각만. 원문(.enc)·열쇠(keys/)는 이 컴퓨터 몫이 아니다 — 대기 목록에도 넣지 않는다.
        remote_paths = [p for p in remote_paths if not p.startswith(("history/", "keys/"))]
    else:
        _try_join(project, uid, remote_paths, _person(project))
        if not _has_master(uid):
            n = sum(1 for p in remote_paths if p.endswith(".enc"))
            print("[hermes] " + MSG_KEYLESS.format(n=n))
            return 0
    con = _connect(project)
    plain = _mode(policy) == "plain"
    got = _import_all(con, project, uid, incoming_paths(con, remote_paths, retry_skipped=not plain), plain=plain)
    con.close()
    print(f"[hermes-sync] 새 항목 {got}건 받음")
    return 0


def cmd_backfill(args) -> int:
    """기존 원문 전부를 조각으로 낸 뒤 push. 두 번 돌려도 조각·outbox 는 늘지 않는다(멱등)."""
    project = args.project
    export = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hermes-export-history.py")
    db = os.path.join(project, ".hermes", "state.db")
    subprocess.run([sys.executable, export, "--db", db, "--project", project, "--all"],
                   capture_output=True, text=True, timeout=600)
    return cmd_push(args)


def cmd_tombstone(args) -> int:
    """경로 하나를 원격·로컬에서 지운다. 사람 실행 전용 — 세션 안에서는 키 가드가 막는다."""
    if not args.confirm:
        print("[hermes-sync] --confirm 이 필요합니다. 되돌릴 수 없습니다.", file=sys.stderr)
        return 2
    project = args.project
    policy = _policy(project)
    try:
        ref.push_with_retry(project, {}, policy.get("remote", "origin"), remove=[args.path])
    except ref.SyncRefError as exc:
        print(f"[hermes-sync] 원격 삭제 실패: {exc}", file=sys.stderr)
        return 1
    local = os.path.join(project, ".hermes", "history", *args.path.split("/")[1:])
    local = local[:-len(".enc")] + ".jsonl" if local.endswith(".enc") else local
    if os.path.isfile(local):
        os.unlink(local)
    con = _connect(project)
    con.execute("DELETE FROM sync_cursor WHERE path = ?", (args.path,))
    con.execute("DELETE FROM sync_outbox WHERE path = ?", (args.path,))
    con.commit()
    con.close()
    print(f"[hermes-sync] 지움: {args.path} (원격 참조 재작성 · 로컬 조각 삭제)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="헤르메스 기억 운반")
    ap.add_argument("--project", default=os.getcwd())
    ap.add_argument("--force-policy", action="store_true", help="sync.json 없이도 실행(테스트용)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("status", "push", "pull", "backfill"):
        sub.add_parser(name)
    t = sub.add_parser("tombstone")
    t.add_argument("path")
    t.add_argument("--confirm", action="store_true")
    args = ap.parse_args()
    return {"status": cmd_status, "push": cmd_push, "pull": cmd_pull,
            "backfill": cmd_backfill, "tombstone": cmd_tombstone}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())

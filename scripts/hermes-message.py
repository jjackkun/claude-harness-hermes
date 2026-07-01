#!/usr/bin/env python3
"""헤르메스 에이전트 간 메시지 버스.

messages 테이블을 공용 게시판으로 사용한다.
에이전트들은 직접 통신하지 않고 DB를 통해 비동기 소통한다.

사용법:
  # 메시지 전송
  python3 hermes-message.py --db PATH send --from AGENT --to AGENT --content TEXT

  # 수신 메시지 조회 (자동 읽음 처리)
  python3 hermes-message.py --db PATH recv --to AGENT [--peek]

  # 특정 메시지 읽음 처리
  python3 hermes-message.py --db PATH ack --id ID

  # 전체 메시지 목록
  python3 hermes-message.py --db PATH list [--status STATUS] [--limit N]
"""

import argparse
import json
import os
import sqlite3
import sys
from datetime import datetime


def connect_db(db_path: str) -> sqlite3.Connection:
    """공통 SQLite 연결 헬퍼 — busy_timeout + WAL (M1)."""
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def get_conn(db_path):
    if not os.path.isfile(db_path):
        print(f"[hermes-msg] DB not found: {db_path}", file=sys.stderr)
        sys.exit(1)
    return connect_db(db_path)


def cmd_send(db_path, from_agent, to_agent, content):
    con = get_conn(db_path)
    cur = con.execute(
        "INSERT INTO messages (from_agent, to_agent, content, status, created_at) "
        "VALUES (?, ?, ?, 'unread', CURRENT_TIMESTAMP)",
        (from_agent, to_agent, content),
    )
    msg_id = cur.lastrowid
    con.commit()
    con.close()
    print(f"[hermes-msg] sent #{msg_id}: {from_agent} → {to_agent}")
    return msg_id


def cmd_recv(db_path, to_agent, peek=False):
    con = get_conn(db_path)
    rows = con.execute(
        "SELECT id, from_agent, content, created_at FROM messages "
        "WHERE to_agent=? AND status='unread' ORDER BY id ASC",
        (to_agent,),
    ).fetchall()

    if not rows:
        print(f"[hermes-msg] no unread messages for {to_agent}")
        con.close()
        return []

    results = []
    for row in rows:
        msg_id, from_agent, content, created_at = row
        results.append({
            "id": msg_id,
            "from": from_agent,
            "to": to_agent,
            "content": content,
            "created_at": created_at,
        })
        if not peek:
            con.execute(
                "UPDATE messages SET status='read' WHERE id=?",
                (msg_id,),
            )

    if not peek:
        con.commit()
    con.close()

    for msg in results:
        print(f"[#{msg['id']}] {msg['from']} → {msg['to']}  {msg['created_at']}")
        print(f"  {msg['content']}")

    return results


def cmd_ack(db_path, msg_id):
    con = get_conn(db_path)
    con.execute("UPDATE messages SET status='read' WHERE id=?", (msg_id,))
    con.commit()
    con.close()
    print(f"[hermes-msg] acked #{msg_id}")


def cmd_list(db_path, status=None, limit=20):
    con = get_conn(db_path)
    if status:
        rows = con.execute(
            "SELECT id, from_agent, to_agent, content, status, created_at "
            "FROM messages WHERE status=? ORDER BY id DESC LIMIT ?",
            (status, limit),
        ).fetchall()
    else:
        rows = con.execute(
            "SELECT id, from_agent, to_agent, content, status, created_at "
            "FROM messages ORDER BY id DESC LIMIT ?",
            (limit,),
        ).fetchall()
    con.close()

    if not rows:
        print("[hermes-msg] no messages")
        return

    for row in rows:
        msg_id, from_a, to_a, content, st, created_at = row
        snippet = content[:60].replace("\n", " ")
        mark = "●" if st == "unread" else "○"
        print(f"{mark} #{msg_id:4d}  {from_a} → {to_a}  [{st}]  {created_at[:16]}")
        print(f"       {snippet}")


def main():
    parser = argparse.ArgumentParser(description="헤르메스 메시지 버스")
    parser.add_argument("--db", required=True, help="state.db 경로")
    sub = parser.add_subparsers(dest="cmd")

    # send
    p_send = sub.add_parser("send", help="메시지 전송")
    p_send.add_argument("--from", dest="from_agent", required=True)
    p_send.add_argument("--to", dest="to_agent", required=True)
    p_send.add_argument("--content", required=True)

    # recv
    p_recv = sub.add_parser("recv", help="수신 메시지 조회 (자동 읽음 처리)")
    p_recv.add_argument("--to", dest="to_agent", required=True)
    p_recv.add_argument("--peek", action="store_true", help="읽음 처리 없이 조회")

    # ack
    p_ack = sub.add_parser("ack", help="읽음 처리")
    p_ack.add_argument("--id", dest="msg_id", type=int, required=True)

    # list
    p_list = sub.add_parser("list", help="전체 메시지 목록")
    p_list.add_argument("--status", choices=["unread", "read"], default=None)
    p_list.add_argument("--limit", type=int, default=20)

    args = parser.parse_args()

    if args.cmd == "send":
        cmd_send(args.db, args.from_agent, args.to_agent, args.content)
    elif args.cmd == "recv":
        cmd_recv(args.db, args.to_agent, peek=args.peek)
    elif args.cmd == "ack":
        cmd_ack(args.db, args.msg_id)
    elif args.cmd == "list":
        cmd_list(args.db, status=args.status, limit=args.limit)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()

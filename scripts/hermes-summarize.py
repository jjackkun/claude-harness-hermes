#!/usr/bin/env python3
"""헤르메스 롤링 요약 스크립트.

Stop Hook에서 호출. 직전 5슬롯 요약과 '아직 요약 안 된 새 핑퐁(델타)'만
Haiku에 넘겨 슬롯을 갱신하고, session_summary 행을 교체한다.
델타가 없으면 LLM 호출 없이 스킵한다(비용 0).

사용법:
  python3 hermes-summarize.py --db PATH --transcript PATH \
      --project-id ID --session-id ID --project-dir PATH
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_redact import redact  # noqa: E402  (민감정보 마스킹 공유 헬퍼)

SLOT_KEYS = ["decisions", "open", "prefs", "facts", "next"]
SLOT_HEADINGS = [
    ("decisions", "결정사항"), ("open", "미해결 과제"),
    ("prefs", "선호·제약"), ("facts", "핵심 사실"), ("next", "다음 액션"),
]


def connect_db(db_path: str) -> sqlite3.Connection:
    con = sqlite3.connect(db_path, timeout=5.0)
    con.execute("PRAGMA busy_timeout = 5000")
    con.execute("PRAGMA journal_mode = WAL")
    return con


def _log(msg: str) -> None:
    print(f"[hermes-summary] {msg}", file=sys.stderr)


def _ensure_schema(con: sqlite3.Connection) -> None:
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


def load_transcript(path: str) -> list:
    """Claude Code transcript(JSONL/JSON)를 message 리스트로 읽는다."""
    if not os.path.isfile(path):
        return []
    messages = []
    try:
        with open(path, "r", encoding="utf-8") as f:
            first = f.read(1)
            f.seek(0)
            if first == "[":
                data = json.load(f)
                return data if isinstance(data, list) else data.get("messages", [])
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    if obj.get("type") in ("user", "assistant") and "message" in obj:
                        messages.append(obj["message"])
                except json.JSONDecodeError:
                    continue
    except Exception as e:
        _log(f"transcript 읽기 실패: {e}")
        return []
    return messages


def _msg_text(msg: dict) -> str:
    raw = msg.get("content", "")
    if isinstance(raw, list):
        return " ".join(
            p.get("text", "") for p in raw if isinstance(p, dict) and "text" in p
        )
    return str(raw)


def messages_to_text(delta: list) -> str:
    parts = []
    for msg in delta:
        if not isinstance(msg, dict):
            continue
        role = msg.get("role", "")
        text = _msg_text(msg).strip()
        if text:
            parts.append(f"[{role}] {text}")
    # 델타가 Haiku(LLM)로 가기 전·요약 슬롯에 박히기 전 경계에서 마스킹
    return redact("\n".join(parts))


def load_summary_state(db_path: str, session_id: str):
    con = connect_db(db_path)
    _ensure_schema(con)
    row = con.execute(
        "SELECT slots_json, last_msg_count, turn_count "
        "FROM session_summary WHERE session_id=?", (session_id,)
    ).fetchone()
    con.close()
    if not row:
        return {}, 0, 0
    try:
        slots = json.loads(row[0]) if row[0] else {}
    except json.JSONDecodeError:
        slots = {}
    return slots, row[1] or 0, row[2] or 0


SUMMARY_PROMPT = """\
다음은 진행 중인 대화의 직전 요약(5슬롯 JSON)과 새로 오간 대화다.
새 대화를 반영해 5슬롯 JSON을 갱신해 출력하라.
5슬롯 JSON 외의 설명·서두·코드블록 래퍼를 출력하지 마라.

슬롯 정의:
- decisions: 합의한 결정사항
- open: 미해결 과제
- prefs: 사용자 선호·제약
- facts: 알아둘 핵심 사실·맥락
- next: 다음 액션

각 슬롯은 문자열 배열이다. 기존 항목을 보존하되 새 대화로 추가·갱신하라.

직전 요약:
{prev}

새 대화:
{delta}

출력(JSON만):
{{"decisions":[],"open":[],"prefs":[],"facts":[],"next":[]}}
"""


def _parse_slots(output: str, prev: dict) -> dict:
    output = re.sub(r"^```[a-z]*\n", "", output.strip())
    output = re.sub(r"\n```$", "", output)
    data = json.loads(output)
    slots = {}
    for k in SLOT_KEYS:
        v = data.get(k, prev.get(k, []))
        slots[k] = v if isinstance(v, list) else [str(v)]
    return slots


def generate_slots(prev_slots: dict, delta_text: str):
    """Haiku로 슬롯을 갱신한다. 실패 시 None(이전 요약 유지)."""
    if not shutil.which("claude"):
        _log("claude CLI 없음 — 스킵")
        return None
    prompt = SUMMARY_PROMPT.format(
        prev=json.dumps(prev_slots, ensure_ascii=False),
        delta=delta_text[:6000],
    )
    for _ in range(2):  # 1회 재시도
        try:
            result = subprocess.run(
                ["claude", "-p", prompt, "--model", "claude-haiku-4-5-20251001"],
                capture_output=True, text=True, timeout=60,
                env={**os.environ, "HERMES_DISABLED": "1"},
            )
            if result.returncode != 0:
                _log(f"claude 실패 rc={result.returncode}")
                continue
            out = result.stdout.strip()
            if not out:
                continue
            return _parse_slots(out, prev_slots)
        except subprocess.TimeoutExpired:
            _log("timeout")
        except json.JSONDecodeError as e:
            _log(f"JSON 파싱 실패: {e}")
        except Exception as e:
            _log(f"오류: {e}")
    return None


def save_summary(db_path, session_id, project_id, slots, msg_count, turn_count):
    con = connect_db(db_path)
    _ensure_schema(con)
    con.execute(
        "INSERT INTO session_summary "
        "(session_id, project_id, slots_json, last_msg_count, turn_count, updated_at) "
        "VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP) "
        "ON CONFLICT(session_id) DO UPDATE SET "
        "project_id=excluded.project_id, slots_json=excluded.slots_json, "
        "last_msg_count=excluded.last_msg_count, turn_count=excluded.turn_count, "
        "updated_at=CURRENT_TIMESTAMP",
        (session_id, project_id, json.dumps(slots, ensure_ascii=False),
         msg_count, turn_count),
    )
    con.commit()
    con.close()


def export_vault_note(project_dir, project_id, session_id, slots) -> str:
    """세션 요약을 옵시디언 호환 .md 노트로 내보낸다."""
    vault = os.path.join(project_dir, ".hermes", "vault")
    os.makedirs(vault, exist_ok=True)
    safe = re.sub(r"[^\w.-]", "_", f"{project_id}-{session_id}")
    path = os.path.join(vault, f"{safe}.md")
    date = datetime.now().strftime("%Y-%m-%d")
    lines = ["---", f"project: {project_id}", f"session: {session_id}",
             f"updated: {date}", "hermes: rolling-summary", "---", "",
             f"# {project_id} · {session_id}", ""]
    for key, heading in SLOT_HEADINGS:
        lines.append(f"## {heading}")
        items = slots.get(key) or []
        lines += [f"- {it}" for it in items] if items else ["- (없음)"]
        lines.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return path


def main():
    parser = argparse.ArgumentParser(description="헤르메스 롤링 요약")
    parser.add_argument("--db", required=True)
    parser.add_argument("--transcript", required=True)
    parser.add_argument("--project-id", default="")
    parser.add_argument("--session-id", default="")
    parser.add_argument("--project-dir", default="")
    args = parser.parse_args()

    if not os.path.isfile(args.db):
        _log(f"DB 없음: {args.db}")
        sys.exit(0)

    messages = load_transcript(args.transcript)
    if not messages:
        print("[hermes-summary] transcript 비어있음 — 스킵")
        return

    project_id = args.project_id or os.path.basename(os.path.dirname(args.db))
    session_id = args.session_id or os.path.splitext(
        os.path.basename(args.transcript))[0]
    project_dir = args.project_dir or os.path.dirname(os.path.dirname(args.db))

    prev_slots, last_count, turn = load_summary_state(args.db, session_id)
    delta = messages[last_count:]
    if not delta:
        print("[hermes-summary] 델타 없음 — 스킵")
        return

    slots = generate_slots(prev_slots, messages_to_text(delta))
    if slots is None:
        print("[hermes-summary] 생성 실패 — 이전 요약 유지(다음 턴 재시도)")
        return

    save_summary(args.db, session_id, project_id, slots, len(messages), turn + 1)
    note = export_vault_note(project_dir, project_id, session_id, slots)
    print(f"[hermes-summary] updated: {session_id} ({len(messages)} msgs) note={note}")


if __name__ == "__main__":
    main()

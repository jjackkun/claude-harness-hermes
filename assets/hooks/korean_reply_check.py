#!/usr/bin/env python3
"""한국어 답변 판정 — Stop 훅 페이로드(stdin)를 읽어 마지막 답변이 영어 위주면 block JSON 을 낸다.

호출: claude-stop-korean-guard.sh 가 stdin 페이로드를 그대로 넘긴다(비어 있어도 된다).
출력: 막을 때만 stdout 에 {"decision":"block","reason":...}. 그 밖에는 아무것도 내지 않는다.
오류는 전부 통과(종료 0) — 판정 실패로 세션을 막지 않는다. 로그는 호출한 훅이 stderr 를 받는다.

답변 글: 페이로드의 last_assistant_message 를 먼저 쓴다 — Claude Code 문서가 "Stop 시점에
transcript 에 마지막 답변이 없을 수 있다" 고 적었기 때문이다. 없으면 transcript 끝에서 뽑는다.
stdin 이 비면(형제 훅 stdin 경쟁) 프로젝트의 가장 최근 transcript 를 쓴다.

근거: docs/exec-plans/completed/2026-10-16-korean-reply-guard-plan.md
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path

TAIL_BYTES = 256 * 1024
MIN_LATIN = 40  # 이보다 짧은 영어는 "Done." 같은 한마디 — 막지 않는다
KOREAN_RATIO_MIN = 0.3  # 한글/(한글+라틴) 이 이보다 작으면 영어 위주
USER_LATIN_MIN = 10  # 사용자 글이 이만큼 라틴이고 한글 비율이 낮으면 영어로 물은 것
STATE_FILE = ".hermes/korean-guard.last"
STATE_KEYS_MAX = 20  # 막은 턴 키를 이만큼 기억한다 — 세션 여럿이 번갈아 막아도 서로 지우지 않게
REASON = (
    "[korean-guard] 직전 답변이 영어 위주입니다. 사용자는 한국어 사용자입니다 — "
    "같은 내용을 한국어로 다시 쓰십시오(코드·경로·명령·식별자는 원문 그대로). "
    "끄기: KOREAN_GUARD_DISABLED=1"
)
ENGLISH_REQUEST = re.compile(r"영어로|영문으로|in english|\benglish\b", re.IGNORECASE)

_NOISE = [
    re.compile(r"```.*?(```|$)", re.DOTALL),  # 코드 블록(닫히지 않아도)
    re.compile(r"`[^`\n]*`"),  # 인라인 코드 — 표의 식별자 칸 포함
    re.compile(r"<([a-z-]+)[^>]*>.*?</\1>", re.DOTALL),  # <system-reminder> 같은 태그 블록
    re.compile(r"https?://\S+"),
    re.compile(r"(?<![\w])(~|\.{1,2})?/[\w.\-/@]+"),  # 유닉스 경로
    re.compile(r"[A-Za-z]:\\[^\s]*"),  # 윈도 경로
    re.compile(r"^\s*>.*$", re.MULTILINE),  # 인용 블록
]
_HANGUL = re.compile(r"[가-힣ㄱ-ㆎ]")
_LATIN = re.compile(r"[A-Za-z]")


def _strip_noise(text: str) -> str:
    for pattern in _NOISE:
        text = pattern.sub(" ", text)
    return text


def _is_english_heavy(text: str, latin_min: int = MIN_LATIN) -> bool:
    clean = _strip_noise(text)
    hangul, latin = len(_HANGUL.findall(clean)), len(_LATIN.findall(clean))
    if latin < latin_min:
        return False
    return hangul / (hangul + latin) < KOREAN_RATIO_MIN


def _user_allows_english(user_text: str) -> bool:
    if ENGLISH_REQUEST.search(user_text):
        return True
    return _is_english_heavy(user_text, USER_LATIN_MIN)


def _user_text(row: dict) -> str | None:
    """사람이 친 글이면 그 글, 도구 결과·메타 줄이면 None."""
    if row.get("isMeta"):
        return None
    content = (row.get("message") or {}).get("content")
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return None
    blocks = [b for b in content if isinstance(b, dict)]
    if any(b.get("type") == "tool_result" for b in blocks):
        return None
    return "\n".join(b.get("text", "") for b in blocks if b.get("type") == "text")


def _assistant_texts(row: dict) -> list[str]:
    content = (row.get("message") or {}).get("content")
    if not isinstance(content, list):
        return []
    return [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]


def _tail_rows(path: Path) -> list[dict]:
    with path.open("rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        f.seek(max(0, size - TAIL_BYTES))
        raw = f.read().decode("utf-8", errors="replace")
    rows = []
    for line in raw.splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue  # 잘린 첫 줄 등
        if isinstance(row, dict):
            rows.append(row)
    return rows


def _last_turn(path: Path) -> tuple[str, str]:
    """(마지막 사용자 글, 그 뒤 assistant text 블록을 이은 글). 사용자 글을 못 찾으면 ("", "")."""
    texts: list[str] = []
    for row in reversed(_tail_rows(path)):
        kind = row.get("type")
        if kind == "assistant":
            texts = _assistant_texts(row) + texts
        elif kind == "user":
            user = _user_text(row)
            if user is not None:
                return user, "\n".join(t for t in texts if t)
    return "", ""


def _latest_transcript(project_dir: str) -> Path | None:
    config = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
    folder = config / "projects" / re.sub(r"[^A-Za-z0-9]", "-", project_dir)
    files = sorted(folder.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def _parse_payload(raw: str) -> dict:
    try:
        data = json.loads(raw) if raw.strip() else {}
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}


def _blocked_keys(state: Path) -> list[str]:
    try:
        return state.read_text(encoding="utf-8").split()
    except OSError:
        return []


def _remember_block(state: Path, keys: list[str], key: str) -> None:
    # 키를 여럿 둔다 — 같은 프로젝트의 두 세션이 서로 키를 덮어 같은 턴을 다시 막지 않게.
    state.parent.mkdir(parents=True, exist_ok=True)
    state.write_text("\n".join((keys + [key])[-STATE_KEYS_MAX:]) + "\n", encoding="utf-8")


def _read_turn(payload: dict, project_dir: str) -> tuple[Path | None, str, str]:
    """(transcript, 마지막 사용자 글, 답변 글)."""
    path_text = payload.get("transcript_path") or ""
    transcript = Path(path_text) if path_text else _latest_transcript(project_dir)
    user, reply = "", ""
    if transcript and transcript.is_file():
        user, reply = _last_turn(transcript)
    return transcript, user, payload.get("last_assistant_message") or reply


def _first_block_of_turn(project_dir: str, transcript: Path | None, user: str, reply: str) -> bool:
    """이 턴을 처음 막는 것이면 기록하고 True.

    한 턴에 한 번만 — 다시 쓴 글이 또 영어여도 통과(무한 반복 방지). stop_hook_active 를 모를 때(stdin 빔)의 대비.
    턴은 (transcript, 마지막 사용자 글) 로 가린다. 사용자 글을 못 읽었으면 답변 글로 대신한다.
    """
    turn = user if user else reply
    key = hashlib.sha256(f"{transcript}\0{turn}".encode()).hexdigest()
    state = Path(project_dir) / STATE_FILE
    keys = _blocked_keys(state)
    if key in keys:
        return False
    _remember_block(state, keys, key)
    return True


def decide(payload: dict, project_dir: str) -> str | None:
    """막을 때 reason, 아니면 None."""
    if payload.get("stop_hook_active"):
        return None
    transcript, user, reply = _read_turn(payload, project_dir)
    if not reply or not _is_english_heavy(reply) or _user_allows_english(user):
        return None
    return REASON if _first_block_of_turn(project_dir, transcript, user, reply) else None


def main() -> int:
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    try:
        reason = decide(_parse_payload(sys.stdin.read()), project_dir)
    except Exception as exc:  # 판정 실패로 세션을 막지 않는다 — 훅이 stderr 를 로그로 남긴다
        print(f"[korean-guard] 판정 실패, 통과: {exc!r}", file=sys.stderr)
        return 0
    if reason:
        print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())

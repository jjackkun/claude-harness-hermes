"""헤르메스 세션 저장 — B신호(객관적 실수 신호) 탐지.

hermes-save-session.py 에서 분리된 모듈.
tool_use/tool_result 블록에서 테스트/빌드 실패, git revert/reset 등을 탐지한다.
탐지는 순수 정규식(모델 호출 0). 채점은 결정화 단계의 별도 Haiku 만 — 자기채점 분리.
"""

import os
import re
import sqlite3
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_redact import redact  # noqa: E402  (민감정보 마스킹 공유 헬퍼)
from hermes_save_session_storage import connect_db  # noqa: E402

_BUILD_CMD_RE = re.compile(
    r"\b(pytest|jest|vitest|mocha|tsc|ruff|mypy"
    r"|go\s+test|go\s+build|cargo\s+test|cargo\s+build|make"
    r"|npm\s+(?:run\s+)?(?:test|build)"
    r"|pnpm\s+(?:run\s+)?(?:test|build)"
    r"|yarn\s+(?:run\s+)?(?:test|build))\b"
)
# 실패 시그니처 — is_error 플래그가 1차 신호, 이 시그니처는 보수적 보강용(대소문자 구분)
_FAIL_SIG_RE = re.compile(
    r"(FAILED|✗|Traceback|npm ERR|error\[E|error TS\d+)"
)
_SIGNAL_FILE_RE = re.compile(
    r"\b[\w./-]+\.(?:py|ts|tsx|js|jsx|mjs|svelte|vue|go|rs|sh|java|kt)\b"
)
_ERR_CODE_RE = re.compile(r"\b([A-Z]{2,}\d{3,})\b|error\[(E\d+)\]")
_GIT_UNDO_RE = re.compile(r"git\s+(?:revert\b|reset\s+--hard\b|checkout\s+--(?=\s|$)|restore\b)")


def _result_text(block: dict) -> str:
    """tool_result 블록에서 출력 텍스트를 추출한다 (str 또는 text 블록 리스트)."""
    c = block.get("content", "")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return " ".join(
            p.get("text", "") for p in c if isinstance(p, dict) and "text" in p
        )
    return ""


def _bash_commands(messages: list) -> dict:
    """assistant tool_use 중 Bash 명령을 {tool_use_id: command} 로 모은다."""
    cmds: dict = {}
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for blk in content:
            if not isinstance(blk, dict):
                continue
            if blk.get("type") == "tool_use" and str(blk.get("name", "")).lower() == "bash":
                cmd = (blk.get("input") or {}).get("command", "")
                if blk.get("id"):
                    cmds[blk["id"]] = cmd
    return cmds


def _derive_locus(text: str, cmd: str) -> str:
    """실패 위치 키를 도출한다. 파일 경로는 basename 으로 정규화(라인번호 제거)."""
    fm = _SIGNAL_FILE_RE.search(text)
    if fm:
        return os.path.basename(fm.group(0))
    cm = _ERR_CODE_RE.search(text)
    if cm:
        return cm.group(1) or cm.group(2)
    fmc = _SIGNAL_FILE_RE.search(cmd)
    if fmc:
        return os.path.basename(fmc.group(0))
    tm = _BUILD_CMD_RE.search(cmd)
    return re.sub(r"\s+", "-", tm.group(1)) if tm else "build"


def detect_objective_signals(messages: list) -> list:
    """tool_use/tool_result 블록에서 객관적 실수 신호(B신호)를 탐지한다.

    Returns: [(pattern_key, context_line), ...] — 세션 내 중복 키는 1개로 합친다.
    """
    cmds = _bash_commands(messages)
    seen: set = set()
    results: list = []

    # ① 테스트/빌드 실패 — 직전 Bash 명령이 빌드/테스트 계열이고 결과가 실패일 때
    for msg in messages:
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for blk in content:
            if not isinstance(blk, dict) or blk.get("type") != "tool_result":
                continue
            cmd = cmds.get(blk.get("tool_use_id"), "")
            if not _BUILD_CMD_RE.search(cmd):
                continue
            text = _result_text(blk)
            # 비정상 종료(is_error)만으로 실패로 간주한다 — 출력이 'passed' 여도 exit≠0 은 실패.
            if not (blk.get("is_error") or _FAIL_SIG_RE.search(text)):
                continue
            key = f"test-fail:{_derive_locus(text, cmd)}"
            if key in seen:
                continue
            seen.add(key)
            first_line = next((ln.strip() for ln in text.splitlines() if ln.strip()), "")
            results.append((key, f"{cmd[:60]} 실패: {first_line[:120]}"))

    # ② git revert/reset — 사용자가 AI 작업을 되돌린 무언의 불만 신호
    for cmd in cmds.values():
        if not _GIT_UNDO_RE.search(cmd):
            continue
        fm = _SIGNAL_FILE_RE.search(cmd)
        # 파일 인자가 없으면(예: git revert <sha>, git reset --hard) revert:HEAD 버킷으로 모은다 — 의도된 catch-all
        target = os.path.basename(fm.group(0)) if fm else "HEAD"
        key = f"revert:{target}"
        if key in seen:
            continue
        seen.add(key)
        results.append((key, f"git 되돌림: {cmd[:80]}"))

    return results


def record_signal_context(db_path: str, signals: list, project_id: str, session_id: str) -> None:
    """B신호 맥락을 session_history(role='tool')에 기록해 결정화 증거를 보강한다.

    save_session 이 같은 session_id 행을 먼저 DELETE+INSERT 하므로, 그 뒤에 호출되면
    재저장 때마다 자연히 교체되어 중복이 쌓이지 않는다 (idempotent).
    """
    con = connect_db(db_path)
    con.isolation_level = None
    cur = con.cursor()
    ts = datetime.now().isoformat()
    try:
        cur.execute("BEGIN IMMEDIATE")
        for key, ctx in signals:
            content = redact(f"[B신호] {key} :: {ctx}".strip())
            cur.execute(
                "INSERT INTO session_history (content, role, timestamp, project_id, session_id) "
                "VALUES (?, ?, ?, ?, ?)",
                (content, "tool", ts, project_id, session_id),
            )
        cur.execute("COMMIT")
    except Exception as e:
        try:
            cur.execute("ROLLBACK")
        except sqlite3.OperationalError:
            pass
        print(f"[hermes] B신호 맥락 기록 실패: {e}", file=sys.stderr)
    finally:
        con.close()

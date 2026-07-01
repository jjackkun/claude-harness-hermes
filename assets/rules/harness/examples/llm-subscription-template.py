"""[예시] subprocess 기반 LLM 호출 — 봉쇄(isolation) 패턴.

rim-kanban backend/app/llm/subscription/client.py 에서 핵심 부분 발췌 (요약본).

패턴의 요지 — "탐지 대신 봉쇄":
  - cwd="/tmp"               → 홈 디렉토리의 CLAUDE.md 자동 로드 차단
  - env 화이트리스트          → ANTHROPIC_API_KEY 등 민감 변수 제거
  - start_new_session=True   → 타임아웃 시 프로세스 그룹 전체 SIGTERM→SIGKILL
  - argv 직접 전달 (no shell)→ 주입 차단
  - `--` 구분자              → prompt 가 `-` 로 시작해도 플래그 해석 방지
  물리적으로 차단하면 탐지할 필요가 없어진다. PDF 8쪽 "엄격한 경계".

치환 대상: _CLI_NAME, _ENV_WHITELIST, _SENSITIVE_ENV_TO_STRIP, 타임아웃.
이 파일은 *실행 가능한 완제품이 아니라 구조 참고용*이다.
"""
from __future__ import annotations

import asyncio
import json
import os
import shutil
import signal

# ↓↓↓ 프로젝트별 치환 ↓↓↓
_CLI_NAME = "claude"
_ENV_WHITELIST = ("PATH", "HOME", "LANG", "LC_ALL", "CLAUDE_CONFIG_DIR")
_CWD_FOR_SUBPROCESS = "/tmp"
_DEFAULT_TIMEOUT_SEC = 120.0
_SENSITIVE_ENV_TO_STRIP = ("ANTHROPIC_API_KEY",)
# ↑↑↑ 프로젝트별 치환 ↑↑↑


class LLMError(Exception):
    """기반 예외."""


class LLMCLINotFoundError(LLMError):
    pass


class LLMTimeoutError(LLMError):
    pass


class LLMSubprocessError(LLMError):
    def __init__(self, returncode: int, stderr: str) -> None:
        self.returncode = returncode
        self.stderr = stderr
        super().__init__(f"{_CLI_NAME} CLI exited {returncode}: {stderr[:200]}")


def _resolve_cli_path(configured: str | None = None) -> str:
    if configured and os.path.isfile(configured) and os.access(configured, os.X_OK):
        return configured
    found = shutil.which(_CLI_NAME)
    if found:
        return found
    raise LLMCLINotFoundError(f"{_CLI_NAME} CLI not found.")


def _build_env() -> dict[str, str]:
    env = {k: os.environ[k] for k in _ENV_WHITELIST if k in os.environ}
    for key in _SENSITIVE_ENV_TO_STRIP:
        env.pop(key, None)
    env["NO_COLOR"] = "1"
    env["TERM"] = "dumb"
    return env


async def _kill_process_group(proc: asyncio.subprocess.Process) -> None:
    """SIGTERM -> 2s grace -> SIGKILL."""
    try:
        pgid = os.getpgid(proc.pid)
        os.killpg(pgid, signal.SIGTERM)
        try:
            await asyncio.wait_for(proc.wait(), timeout=2.0)
            return
        except asyncio.TimeoutError:
            pass
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    await proc.wait()


async def invoke_llm(prompt: str, timeout: float = _DEFAULT_TIMEOUT_SEC) -> dict:
    """LLM CLI subprocess 호출. 반환값은 파싱된 JSON dict."""
    cli = _resolve_cli_path()
    argv = [cli, "-p", "--output-format", "json", "--", prompt]

    proc = await asyncio.create_subprocess_exec(
        *argv,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=_build_env(),
        cwd=_CWD_FOR_SUBPROCESS,
        start_new_session=True,
    )

    try:
        stdout_b, stderr_b = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        await _kill_process_group(proc)
        raise LLMTimeoutError(f"{_CLI_NAME} CLI timeout after {timeout}s")

    if proc.returncode != 0:
        raise LLMSubprocessError(proc.returncode, stderr_b.decode("utf-8", "replace"))

    stdout = stdout_b.decode("utf-8", "replace")
    if not stdout.strip():
        raise LLMError(f"{_CLI_NAME} CLI returned empty stdout.")

    return json.loads(stdout)

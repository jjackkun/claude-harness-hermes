"""기계 프롬프트의 명령 줄 — 글만 만드는 헤르메스 배경 호출(요약·드리밍·결정화·판정 …)은 도구 없이 돈다.

기본 도구는 `--tools ""` 로, MCP 도구는 `--strict-mcp-config`(MCP 설정을 주지 않음)로 끈다.
도구가 열려 있으면 프로젝트 폴더의 권한 설정을 물려받아, 요약할 대화 속 명령을 실행할 수 있다 —
2026-10-22 요약기가 "커밋하고 푸시" 를 스스로 실행했다(jj-agent-room f036723).
도구를 쓰는 것이 본래 일인 소환·루프·평가는 이 함수를 쓰지 않는다.
계획: docs/exec-plans/active/2026-10-22-machine-prompt-no-tools.md
"""

NO_TOOLS = ("--tools", "", "--strict-mcp-config")


def machine_prompt_cmd(model=None, binary="claude", extra=()):
    """binary · -p · (--model model) · extra · NO_TOOLS 순서의 명령 줄. 프롬프트는 stdin 으로 준다(argv 에 싣지 않음)."""
    cmd = [binary, "-p"]
    if model:
        cmd += ["--model", model]
    cmd += list(extra)
    cmd += list(NO_TOOLS)
    return cmd

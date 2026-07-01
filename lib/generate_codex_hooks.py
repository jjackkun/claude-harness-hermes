#!/usr/bin/env python3
"""Generate Codex hook metadata from resolved presets.

The output uses Codex plugin-style hooks.json shape. Commands point at Codex
native hook scripts copied into the target project. Preset inline hook commands
are routed through a Codex runner so the original preset model can stay shared
without installing Claude hook files.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def _read_lines(tmpdir: Path, name: str) -> list[str]:
    path = tmpdir / name
    if not path.exists():
        return []
    return [line for line in path.read_text().splitlines() if line.strip()]


def _project_command(project_dir: str, rel: str) -> str:
    return str(Path(project_dir) / rel)


def _is_claude_project_hook(command: str) -> bool:
    return (
        "${CLAUDE_PROJECT_DIR}/scripts/hooks/claude-" in command
        or "/scripts/hooks/claude-" in command
    )


def _codex_command(command: str) -> str:
    return command.replace("CLAUDE_TOOL_FILE_PATH", "CODEX_TOOL_FILE_PATH")


def main(output_path: str) -> int:
    tmpdir_str = os.environ.get("DS_TMPDIR")
    project_dir = os.environ.get("CODEX_PROJECT_DIR")
    if not tmpdir_str or not project_dir:
        print("DS_TMPDIR and CODEX_PROJECT_DIR are required", file=sys.stderr)
        return 2

    tmpdir = Path(tmpdir_str)
    post_edit = _read_lines(tmpdir, "post_edit")
    stop = _read_lines(tmpdir, "stop")
    env_vars = _read_lines(tmpdir, "env")

    hooks: dict[str, list[dict]] = {}

    codex_size = _project_command(project_dir, "scripts/codex-hooks/codex-posttooluse-size-warn.sh")
    codex_runner = _project_command(project_dir, "scripts/codex-hooks/codex-posttooluse-command-runner.sh")
    codex_stop_runner = _project_command(project_dir, "scripts/codex-hooks/codex-stop-command-runner.sh")
    codex_prompt = _project_command(project_dir, "scripts/codex-hooks/codex-userpromptsubmit-reminders.sh")
    codex_bash_guard = _project_command(project_dir, "scripts/codex-hooks/codex-pretooluse-bash-guard.sh")

    hooks["UserPromptSubmit"] = [
        {
            "hooks": [
                {"type": "command", "command": codex_prompt},
            ]
        }
    ]
    hooks["PreToolUse"] = [
        {
            "matcher": "Bash",
            "hooks": [
                {"type": "command", "command": codex_bash_guard},
            ],
        }
    ]
    hooks["PostToolUse"] = [
        {
            "matcher": "Edit|Write|MultiEdit",
            "hooks": [
                {"type": "command", "command": codex_size},
            ],
        }
    ]

    post_edit = [_codex_command(cmd) for cmd in post_edit if not _is_claude_project_hook(cmd)]
    stop = [_codex_command(cmd) for cmd in stop if not _is_claude_project_hook(cmd)]

    if post_edit:
        hooks["PostToolUse"].append(
            {
                "matcher": "Edit|Write|MultiEdit",
                "hooks": [
                    {"type": "command", "command": f"{codex_runner} {json.dumps(cmd)}"}
                    for cmd in post_edit
                ],
            }
        )

    if stop:
        hooks["Stop"] = [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": f"{codex_stop_runner} {json.dumps(cmd)}",
                        "timeout": 30,  # hook timeout is in seconds (not ms)
                    }
                    for cmd in stop
                ]
            }
        ]

    env_obj: dict[str, str] = {}
    for kv in env_vars:
        if "=" in kv:
            key, value = kv.split("=", 1)
            env_obj[key.strip()] = value.strip()

    out = {
        "hooks": hooks,
    }
    if env_obj:
        out["env"] = env_obj

    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: generate_codex_hooks.py <output_path>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))

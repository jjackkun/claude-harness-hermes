#!/usr/bin/env python3
"""Generate .claude/settings.local.json (gitignored) from shell arrays.

Only machine-local / personal settings belong here:
  env

Hooks, permissions.deny, and permissions.allow are managed by
generate_settings_json.py → settings.json (committed).

Managed keys (overwritten each run):
  env

All other top-level keys are preserved. In particular, permissions and
hooks in this file are user data (Claude Code writes "don't ask again"
approvals to permissions.allow here) and must never be removed.
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


def main(output_path: str) -> int:
    tmpdir_str = os.environ.get("DS_TMPDIR")
    if not tmpdir_str:
        print("DS_TMPDIR is not set", file=sys.stderr)
        return 2
    tmpdir = Path(tmpdir_str)

    env_vars = _read_lines(tmpdir, "env")

    out = Path(output_path)
    if out.exists():
        try:
            existing = json.loads(out.read_text() or "{}")
            if not isinstance(existing, dict):
                existing = {}
        except json.JSONDecodeError:
            existing = {}
    else:
        existing = {}

    # ---- env ----
    env_obj: dict[str, str] = {}
    for kv in env_vars:
        if "=" in kv:
            k, v = kv.split("=", 1)
            env_obj[k.strip()] = v.strip()
    if env_obj:
        existing["env"] = env_obj
    else:
        existing.pop("env", None)

    # NOTE: never touch user-owned keys here. Claude Code stores user-approved
    # permissions (permissions.allow via "don't ask again") and user-added
    # hooks in settings.local.json — deleting them would silently destroy
    # the user's approval history on every reinstall.

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(existing, indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: generate_settings.py <output_path>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))

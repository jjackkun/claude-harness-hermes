#!/usr/bin/env python3
"""Generate .claude/settings.json (committed) from shell arrays.

Managed keys (merged each run, never deleting user entries):
  hooks, permissions.deny, permissions.allow

Merge policy: preset entries are added or updated in place; entries the
user added by hand are always preserved.

hooks are ownership-synced. Registrations pointing at scripts/hooks/<name>
for a name the harness ships (or has retired) belong to the harness: they are
reclaimed on every run and re-added only if a preset still provides them, so
dropping a preset actually unregisters its hooks. Hooks pointing anywhere else
are user-owned and never touched.

permissions.allow is ownership-synced, like hooks. Entries the harness ships
(any preset's HARNESS_PERMISSIONS_ALLOW, plus RETIRED_PERMISSION_ALLOW) are
reclaimed on every run and re-added only if a preset still provides them, so
dropping a preset actually revokes its permissions. Entries outside that
inventory are user-owned and never touched. This applies to settings.json only;
Claude Code's "don't ask again" approvals land in settings.local.json, which the
harness never touches (see generate_settings.py).

permissions.deny `Agent(...)` entries are the preset-managed namespace and are
synced to the current preset list. All other top-level keys are preserved.

See generate_settings.py for the DS_TMPDIR tmpfile protocol.
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


def _merge_hook_items(existing_items: list, preset_items: list) -> list:
    """Merge preset hook items into existing ones, keyed by command.

    Existing items whose command matches a preset item are replaced by the
    preset version (so managed fields like timeout stay current); all other
    existing items — i.e. user-added hooks — are preserved as-is.
    """
    preset_by_cmd = {
        item.get("command"): item for item in preset_items if isinstance(item, dict)
    }
    merged: list = []
    seen: set = set()
    for item in existing_items:
        cmd = item.get("command") if isinstance(item, dict) else None
        if cmd is not None and cmd in preset_by_cmd:
            merged.append(preset_by_cmd[cmd])
            seen.add(cmd)
        else:
            merged.append(item)
    for item in preset_items:
        if item.get("command") not in seen:
            merged.append(item)
    return merged


def _is_harness_hook(cmd: object, inventory: set[str]) -> bool:
    """True when a hook command points at a harness-installed script.

    Harness hooks always live at scripts/hooks/<name>, where <name> is a file
    shipped in assets/hooks (or listed in RETIRED_HOOK_SOURCES). Anything else
    is treated as user-owned and never touched.
    """
    if not isinstance(cmd, str):
        return False
    return any(f"scripts/hooks/{name}" in cmd for name in inventory)


def _strip_harness_hooks(existing_hooks: dict, inventory: set[str]) -> dict:
    """Drop every harness-installed hook entry from the existing settings.

    Preset-provided hooks are re-added by the merge immediately after, so
    entries a preset still ships survive the round trip; entries whose preset
    was removed (or which the preset stopped registering) disappear. Without
    this pass, a dropped preset's hooks are indistinguishable from user-added
    hooks and would stay registered forever.
    """
    if not inventory:
        return existing_hooks
    cleaned: dict = {}
    for event, groups in existing_hooks.items():
        if not isinstance(groups, list):
            cleaned[event] = groups
            continue
        new_groups: list = []
        for group in groups:
            items = group.get("hooks") if isinstance(group, dict) else None
            if not isinstance(items, list):
                new_groups.append(group)
                continue
            kept = [
                item
                for item in items
                if not _is_harness_hook(
                    item.get("command") if isinstance(item, dict) else None, inventory
                )
            ]
            if not kept:
                continue  # 그룹 전체가 하네스 소유 — matcher 껍데기까지 제거
            new_group = dict(group)
            new_group["hooks"] = kept
            new_groups.append(new_group)
        if new_groups:
            cleaned[event] = new_groups
    return cleaned


def _merge_hook_groups(existing_groups: list, preset_groups: list) -> list:
    """Merge preset matcher-groups into existing ones for a single event."""
    merged = [dict(g) if isinstance(g, dict) else g for g in existing_groups]
    for preset_group in preset_groups:
        target = next(
            (
                g
                for g in merged
                if isinstance(g, dict)
                and g.get("matcher") == preset_group.get("matcher")
            ),
            None,
        )
        if target is None:
            merged.append(preset_group)
            continue
        existing_items = target.get("hooks")
        if not isinstance(existing_items, list):
            existing_items = []
        target["hooks"] = _merge_hook_items(
            existing_items, preset_group.get("hooks") or []
        )
    return merged


def main(output_path: str) -> int:
    tmpdir_str = os.environ.get("DS_TMPDIR")
    if not tmpdir_str:
        print("DS_TMPDIR is not set", file=sys.stderr)
        return 2
    tmpdir = Path(tmpdir_str)

    post_edit = _read_lines(tmpdir, "post_edit")
    stop = _read_lines(tmpdir, "stop")
    deny = _read_lines(tmpdir, "deny")
    user_prompt_submit = _read_lines(tmpdir, "user_prompt_submit")
    session_start = _read_lines(tmpdir, "session_start")
    pre_tool_use = _read_lines(tmpdir, "pre_tool_use")
    post_tool_use = _read_lines(tmpdir, "post_tool_use")
    permissions_allow = _read_lines(tmpdir, "permissions_allow")
    owned_allow = set(_read_lines(tmpdir, "harness_permission_inventory"))
    hook_inventory = set(_read_lines(tmpdir, "harness_hook_inventory"))
    worktree_bg_isolation = _read_lines(tmpdir, "worktree_bg_isolation")

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

    # ---- hooks ----
    hooks: dict[str, list[dict]] = {}
    post_tool_use_entries: list[dict] = []
    if post_edit:
        post_tool_use_entries.append(
            {
                "matcher": "Edit|Write|MultiEdit",
                "hooks": [{"type": "command", "command": cmd} for cmd in post_edit],
            }
        )
    if post_tool_use:
        by_matcher: dict[str, list[str]] = {}
        for entry in post_tool_use:
            if "::" in entry:
                matcher, cmd = entry.split("::", 1)
            else:
                matcher, cmd = "*", entry
            by_matcher.setdefault(matcher, []).append(cmd)
        for matcher, cmds in by_matcher.items():
            post_tool_use_entries.append(
                {
                    "matcher": matcher,
                    "hooks": [{"type": "command", "command": cmd} for cmd in cmds],
                }
            )
    if post_tool_use_entries:
        hooks["PostToolUse"] = post_tool_use_entries
    if stop:
        hooks["Stop"] = [
            {
                "hooks": [
                    # Hook timeout is in seconds (not ms).
                    {"type": "command", "command": cmd, "timeout": 30}
                    for cmd in stop
                ]
            }
        ]
    if session_start:
        hooks["SessionStart"] = [
            {
                "hooks": [{"type": "command", "command": cmd} for cmd in session_start]
            }
        ]
    if user_prompt_submit:
        hooks["UserPromptSubmit"] = [
            {
                "hooks": [{"type": "command", "command": cmd} for cmd in user_prompt_submit]
            }
        ]
    if pre_tool_use:
        pre_by_matcher: dict[str, list[str]] = {}
        for entry in pre_tool_use:
            if "::" in entry:
                matcher, cmd = entry.split("::", 1)
            else:
                matcher, cmd = "*", entry
            pre_by_matcher.setdefault(matcher, []).append(cmd)
        hooks["PreToolUse"] = [
            {
                "matcher": matcher,
                "hooks": [{"type": "command", "command": cmd} for cmd in cmds],
            }
            for matcher, cmds in pre_by_matcher.items()
        ]

    # Reclaim harness-owned hook registrations, then merge the current preset
    # set back in. User-added hooks survive both passes; hooks whose preset was
    # removed are dropped. This runs even when the presets contribute no hooks
    # at all — that is precisely the "whole preset removed" case.
    existing_hooks = existing.get("hooks")
    if not isinstance(existing_hooks, dict):
        existing_hooks = {}
    merged_hooks = _strip_harness_hooks(existing_hooks, hook_inventory)
    for event, preset_groups in hooks.items():
        existing_groups = merged_hooks.get(event)
        if not isinstance(existing_groups, list):
            existing_groups = []
        merged_hooks[event] = _merge_hook_groups(existing_groups, preset_groups)
    if merged_hooks:
        existing["hooks"] = merged_hooks
    else:
        existing.pop("hooks", None)

    # ---- worktree ----
    # Set only when a preset provides a value; never delete a user-set key.
    if worktree_bg_isolation:
        existing["worktree"] = {"bgIsolation": worktree_bg_isolation[0]}

    # ---- permissions ----
    # allow: ownership-synced. Entries in the harness inventory are reclaimed and
    # re-added only if a preset still provides them; everything else is user-owned.
    # deny: `Agent(...)` entries are the preset-managed namespace and are
    # synced to the current preset list (entries dropped by presets are
    # removed); all other deny entries are user-owned and preserved.
    perms = existing.get("permissions") or {}
    if not isinstance(perms, dict):
        perms = {}

    existing_allow = perms.get("allow") or []
    if not isinstance(existing_allow, list):
        existing_allow = []

    if owned_allow:
        # An empty inventory means it could not be computed (older install path,
        # missing preset dir). Reclaiming against it would wipe every managed
        # permission, so fall back to merge-only instead.
        user_allow = [
            e for e in existing_allow
            if not (isinstance(e, str) and e in owned_allow)
        ]
    else:
        user_allow = existing_allow

    merged_allow = list(dict.fromkeys(user_allow + permissions_allow))
    if merged_allow:
        perms["allow"] = merged_allow
    else:
        perms.pop("allow", None)

    existing_deny = perms.get("deny") or []
    if not isinstance(existing_deny, list):
        existing_deny = []
    user_deny = [
        e
        for e in existing_deny
        if not (isinstance(e, str) and e.startswith("Agent(") and e.endswith(")"))
    ]
    preset_deny = [f"Agent({a})" for a in deny]
    merged_deny = list(dict.fromkeys(user_deny + preset_deny))
    if merged_deny:
        perms["deny"] = merged_deny
    else:
        perms.pop("deny", None)

    if perms:
        existing["permissions"] = perms

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(existing, indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: generate_settings_json.py <output_path>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))

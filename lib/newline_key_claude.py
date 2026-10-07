#!/usr/bin/env python3
"""Responsibility: Claude Code keybindings.json 에 shift+enter → chat:newline 이 없으면 더한다.

사용: newline_key_claude.py <claude_config_dir>
출력 한 줄: created | added | kept | skipped  (": 경로/이유" 가 붙는다)

사용자가 shift+enter 를 이미 정해 두었으면(null 로 푼 것 포함) 건드리지 않는다.
못 읽는 파일은 덮지 않고 건너뛴다.
"""
import json
import sys
from pathlib import Path

KEY = "shift+enter"
ACTION = "chat:newline"
CONTEXT = "Chat"
SCHEMA = "https://www.schemastore.org/claude-code-keybindings.json"
DOCS = "https://code.claude.com/docs/en/keybindings"


def normalize(key):
    return "".join(str(key).lower().split())


def is_chat_block(block):
    return (
        isinstance(block, dict)
        and block.get("context") == CONTEXT
        and isinstance(block.get("bindings"), dict)
    )


def has_key(blocks):
    return any(
        normalize(k) == KEY for b in blocks if is_chat_block(b) for k in b["bindings"]
    )


def with_key(blocks):
    """첫 Chat 블록에 더한 새 목록을 돌려준다. Chat 블록이 없으면 끝에 하나 만든다."""
    for i, block in enumerate(blocks):
        if is_chat_block(block):
            merged = {**block, "bindings": {**block["bindings"], KEY: ACTION}}
            return [*blocks[:i], merged, *blocks[i + 1 :]]
    return [*blocks, {"context": CONTEXT, "bindings": {KEY: ACTION}}]


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    path = Path(argv[1]) / "keybindings.json"
    existed = path.is_file()
    data = {"$schema": SCHEMA, "$docs": DOCS, "bindings": []}
    if existed:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as err:
            print(f"skipped: {path} 를 JSON 으로 읽지 못했습니다 ({err})")
            return 0
    blocks = data.get("bindings") if isinstance(data, dict) else None
    if not isinstance(blocks, list):
        print(f'skipped: {path} 에 "bindings" 배열이 없습니다')
        return 0
    if has_key(blocks):
        print(f"kept: {path} 에 {KEY} 가 이미 있습니다")
        return 0
    result = {**data, "bindings": with_key(blocks)}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"{'added' if existed else 'created'}: {path} ({KEY} → {ACTION})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

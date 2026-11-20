"""실수 감지 훅(claude-userpromptsubmit-mistake-detect.sh)이 세는 키 — 한 목록.

훅은 hermes-increment.py 로 count 만 올린다. 세션 저장(update_patterns)은 이 목록의 키도 결정화 목록에 올린다.
훅에 키를 더하면 여기에도 더한다 — tests/test_hermes_increment_crystallize.py 가 둘이 같은지 본다.
계획: docs/exec-plans/completed/2026-11-20-worktree-finish-plan.md (G5)
"""

MISTAKE_KEYS = ("worktree-not-synced", "css-property-missing", "repeated-mistake")

# "계속"·"반복" 한 단어로 걸리는 키 — 규칙으로 만들 내용이 없어 결정화하지 않는다.
NOT_CRYSTALLIZED = frozenset({"repeated-mistake"})

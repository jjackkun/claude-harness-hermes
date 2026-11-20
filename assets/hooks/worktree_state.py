#!/usr/bin/env python3
"""한 git worktree 의 상태 — main 에 합칠 것이 남았는지, 끝낸 계획서가 있는지, 지우면 잃는 파일이 있는지.

마무리 스킬(G1)·Stop 훅(G2)·시작 알림(G3)·계획서 편집 경고(G4)가 이 판정 하나를 함께 쓴다.
판정은 git 출력만 읽는다. 아무것도 쓰지 않는다.

- ahead: main 에 없는 이 브랜치(HEAD)의 커밋 수
- changes: 커밋 안 된 변경 수(추적 안 된 새 파일 포함, 무시 파일 제외)
- touched_plans: main 과 비교해 커밋이나 작업 트리에서 건드린 `docs/exec-plans/active/*.md`
- completed_plans: active/X 가 지워지고 completed/X 가 생긴 계획서 이름(커밋했든 안 했든)
  이름 바꾸기 감지에 기대지 않는다(--no-renames) — 많이 고친 뒤 옮겨도 놓치지 않는다.
- stray_ignored: git 이 무시하는 파일 가운데 다시 만들 수 있는 허용 목록 밖의 것(worktree 를 지우면 잃는다)

계획: docs/exec-plans/active/2026-11-20-worktree-finish-plan.md (Step 1 · G1 ⑧ · G2)
"""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

_ACTIVE = "docs/exec-plans/active/"
_COMPLETED = "docs/exec-plans/completed/"

# 지워도 다시 만들 수 있는 무시 파일. 경로 조각 이름(어디에 있든) 또는 저장소 맨 위 폴더.
_IGNORED_ALLOWLIST = {
    "parts": ("node_modules", ".venv", "__pycache__", ".pytest_cache", ".ruff_cache", ".mypy_cache"),
    "top": (".claude/", ".harness/", ".hermes/"),
}

_GIT_TIMEOUT_S = 10
# git 훅(pre-commit 등) 안에서 불리면 git 이 이 값들을 넘긴다. 이 모듈은 늘 경로(cwd)를 주고 부르므로,
# 물려받은 값은 다른 저장소를 가리키게 할 뿐이다 — 지우고 부른다(2026-11-20 커밋 게이트에서 실측).
_GIT_LOCATION_VARS = ("GIT_DIR", "GIT_INDEX_FILE", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY", "GIT_PREFIX")
_ENV = {k: v for k, v in os.environ.items() if k not in _GIT_LOCATION_VARS}


class WorktreeStateError(RuntimeError):
    """git 이 답하지 않았거나 main 브랜치가 없다 — 추측하지 않고 멈춘다."""


@dataclass(frozen=True)
class WorktreeState:
    path: str
    branch: str | None
    is_main_checkout: bool
    ahead: int
    changes: int
    touched_plans: list[str] = field(default_factory=list)
    completed_plans: list[str] = field(default_factory=list)
    stray_ignored: list[str] = field(default_factory=list)
    last_commit: str = ""


def _git(cwd: str | os.PathLike, *args: str) -> str:
    try:
        done = subprocess.run(
            ["git", *args], cwd=cwd, env=_ENV, capture_output=True, text=True, timeout=_GIT_TIMEOUT_S, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        raise WorktreeStateError(f"git {' '.join(args)}: {e}") from e
    if done.returncode != 0:
        raise WorktreeStateError(f"git {' '.join(args)}: {done.stderr.strip()}")
    return done.stdout


def _status_entries(cwd: str | os.PathLike) -> list[tuple[str, str]]:
    """(XY, 경로) — 이름 바꾸기를 지움+추가로 풀고, 새 폴더 안 파일도 하나씩."""
    raw = _git(cwd, "status", "--porcelain", "-z", "--no-renames", "--untracked-files=all")
    return [(item[:2], item[3:]) for item in raw.split("\0") if item]


def _diff_entries(cwd: str | os.PathLike, main_branch: str) -> list[tuple[str, str]]:
    raw = _git(cwd, "diff", "--name-status", "-z", "--no-renames", f"refs/heads/{main_branch}...HEAD")
    parts = [p for p in raw.split("\0") if p]
    return [(parts[i], parts[i + 1]) for i in range(0, len(parts) - 1, 2)]


def _names_under(entries: list[tuple[str, str]], prefix: str, codes: str) -> set[str]:
    """prefix 아래 파일 이름 가운데 상태 코드에 codes 의 글자가 하나라도 있는 것. "?" 는 추적 안 된 새 파일."""
    return {p[len(prefix):] for code, p in entries if p.startswith(prefix) and any(c in code for c in codes)}


def _completed(diff: list[tuple[str, str]], status: list[tuple[str, str]]) -> list[str]:
    """main 과 비교해 completed/ 에 새로 생긴 계획서 — active/ 에서 옮겼든, 가지에서 태어나 끝났든.
    active/ 에서 지워졌는지는 보지 않는다: 가지에서 쓰고 끝낸 계획서는 main 의 active/ 에 없었다(2026-11-20 복제본 실측)."""
    added = _names_under(diff, _COMPLETED, "A") | _names_under(status, _COMPLETED, "A?")
    return sorted(n for n in added if n.endswith(".md"))


# 허용 폴더 안이어도 지우면 잃는 파일 — 그 세션에서 승인한 권한(코드 리뷰 M3).
_KEEP = (".claude/settings.local.json",)


def _same_as_main(root: Path, main_root: Path | None, rel: str) -> bool:
    """메인 체크아웃의 같은 경로와 내용이 같다 — 앱이 메인에서 복사해 넣은 사본이라 지워도 잃지 않는다."""
    if main_root is None or main_root == root:
        return False
    mine, theirs = root / rel, main_root / rel
    return mine.is_file() and theirs.is_file() and mine.read_bytes() == theirs.read_bytes()


def _kept_inside(root: Path, rel: str) -> list[str]:
    """rel(파일 또는 뭉쳐 보인 폴더) 안에 있는 _KEEP 파일들."""
    if rel in _KEEP:
        return [rel]
    return [k for k in _KEEP if rel.endswith("/") and k.startswith(rel) and (root / k).exists()]


def _is_regenerable(root: Path, rel: str, main_root: Path | None = None) -> bool:
    if any(not _same_as_main(root, main_root, k) for k in _kept_inside(root, rel)):
        return False
    if any(rel.startswith(top) for top in _IGNORED_ALLOWLIST["top"]):
        return True
    if any(part in _IGNORED_ALLOWLIST["parts"] for part in rel.rstrip("/").split("/")):
        return True
    return Path(rel).name == ".env" and (root / rel).is_symlink()


def _stray_ignored(cwd: str | os.PathLike, main_root: Path | None = None) -> list[str]:
    # matching: 무시 규칙에 걸린 그 폴더·파일 단위로 나온다(traditional 은 바깥 폴더 `server/` 로 뭉갠다).
    raw = _git(cwd, "status", "--porcelain", "-z", "--ignored=matching")
    ignored = [item[3:] for item in raw.split("\0") if item.startswith("!! ")]
    return sorted(rel for rel in ignored if not _is_regenerable(Path(cwd), rel, main_root))


def is_linked_worktree(path: str | os.PathLike) -> bool:
    """앱이나 `git worktree add` 가 만든 worktree 면 True, 메인 체크아웃이면 False."""
    git_dir = Path(_git(path, "rev-parse", "--absolute-git-dir").strip())
    common = Path(_git(path, "rev-parse", "--git-common-dir").strip())
    common = common if common.is_absolute() else Path(path) / common
    return git_dir.resolve() != common.resolve()


def list_worktrees(repo: str | os.PathLike) -> list[tuple[str, str | None]]:
    """(경로, 브랜치) — 메인 체크아웃이 먼저 온다. detached 이면 브랜치는 None."""
    out: list[tuple[str, str | None]] = []
    for block in _git(repo, "worktree", "list", "--porcelain").strip().split("\n\n"):
        lines = dict(line.split(" ", 1) if " " in line else (line, "") for line in block.splitlines())
        if "worktree" in lines:
            ref = lines.get("branch")
            out.append((lines["worktree"], ref.removeprefix("refs/heads/") if ref else None))
    return out


def touches(path: str | os.PathLike, rel: str, main_branch: str = "main") -> bool:
    """이 worktree 가 main 에 없는 커밋이나 커밋 안 된 변경으로 `rel` 을 건드렸나 — 편집 경고(G4)용 가벼운 판정."""
    committed = _git(path, "diff", "--name-only", "-z", f"refs/heads/{main_branch}...HEAD", "--", rel)
    return bool(committed.strip("\0")) or bool(_status_entries_for(path, rel))


def _status_entries_for(path: str | os.PathLike, rel: str) -> list[str]:
    raw = _git(path, "status", "--porcelain", "-z", "--no-renames", "--untracked-files=all", "--", rel)
    return [item for item in raw.split("\0") if item]


def default_main(path: str | os.PathLike) -> str:
    """main 브랜치 이름 — WORKTREE_MAIN_BRANCH · origin/HEAD · 있는 main · 있는 master 순. 못 찾으면 "main"."""
    if os.environ.get("WORKTREE_MAIN_BRANCH"):
        return os.environ["WORKTREE_MAIN_BRANCH"]
    try:
        return _git(path, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD").strip().split("/", 1)[1]
    except (WorktreeStateError, IndexError):
        pass
    for name in ("main", "master"):
        try:
            _git(path, "rev-parse", "--verify", "--quiet", f"refs/heads/{name}")
            return name
        except WorktreeStateError:
            continue
    return "main"


def state_of(path: str | os.PathLike, main_branch: str = "main", with_stray: bool = True) -> WorktreeState:
    if not _git(path, "rev-parse", "--verify", "--quiet", f"refs/heads/{main_branch}").strip():
        raise WorktreeStateError(f"no branch {main_branch}")
    branch = _git(path, "branch", "--show-current").strip() or None
    status = _status_entries(path)
    diff = _diff_entries(path, main_branch)
    names = {p for _, p in diff} | {p for _, p in status}
    return WorktreeState(
        path=str(path),
        branch=branch,
        is_main_checkout=not is_linked_worktree(path),
        ahead=int(_git(path, "rev-list", "--count", f"refs/heads/{main_branch}..HEAD").strip()),
        changes=len(status),
        touched_plans=sorted(p for p in names if p.startswith(_ACTIVE) and p.endswith(".md")),
        completed_plans=_completed(diff, status),
        stray_ignored=_stray_ignored(path, Path(list_worktrees(path)[0][0])) if with_stray else [],  # 무시 파일 검사는 마무리(G1)만 — 훅은 건너뛴다(시간)
        last_commit=_git(path, "log", "-1", "--format=%cI").strip(),
    )


def _main(argv: list[str]) -> int:
    """`worktree_state.py <경로> [main 브랜치]` — 상태를 JSON 한 줄로. 판정 실패는 종료 2."""
    import json
    import sys
    from dataclasses import asdict

    if not 1 <= len(argv) <= 2:
        print("usage: worktree_state.py <path> [main-branch]", file=sys.stderr)
        return 2
    try:
        print(json.dumps(asdict(state_of(argv[0], *argv[1:])), ensure_ascii=False))
    except WorktreeStateError as e:
        print(f"worktree_state: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(_main(sys.argv[1:]))

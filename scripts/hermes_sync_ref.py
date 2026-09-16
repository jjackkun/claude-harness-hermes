#!/usr/bin/env python3
"""`refs/hermes/sync` 의 저수준 git 조작만 담당한다 — 작업 트리·코드 브랜치를 건드리지 않는다.

원격 배치는 **추가 전용**이고 경로가 유일하다(조각 = 세션/순번, 이력 = event_id). 그래서
두 클론이 동시에 밀어도 "원격 트리 + 내 새 파일" 합집합이 곧 병합이다. 임시 인덱스로
그 트리를 만들고 커밋해 다시 민다. worktree 도, `--force` 도 쓰지 않는다(RV-01).
계획: docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 6·7·15

공개 함수 6개: SyncRefError · fetch · list_remote · read_blob · commit_files · push_with_retry
"""

import os
import subprocess
import tempfile

REF = "refs/hermes/sync"
_REMOTE_TRACK = "refs/hermes/sync-remote"
_TIMEOUT = 120
_RETRIES = 3


class SyncRefError(RuntimeError):
    """git 호출 실패. `unsupported` 가 참이면 서버가 사용자 정의 참조를 거부한 것(T-15)."""

    def __init__(self, message: str, unsupported: bool = False):
        super().__init__(message)
        self.unsupported = unsupported


def _git(repo: str, *args, env: dict = None, ok_codes=(0,)) -> str:
    full_env = dict(os.environ)
    if env:
        full_env.update(env)
    try:
        done = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True,
                              timeout=_TIMEOUT, env=full_env)
    except subprocess.TimeoutExpired as exc:
        raise SyncRefError(f"git {' '.join(args[:2])} 가 {_TIMEOUT}초 안에 끝나지 않았다") from exc
    if done.returncode not in ok_codes:
        raise SyncRefError((done.stderr or done.stdout).strip() or f"git {args[0]} 실패")
    return done.stdout


def _ref_exists(repo: str, ref: str) -> bool:
    return subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "-q", ref],
                          capture_output=True).returncode == 0


def fetch(repo: str, remote: str = "origin") -> bool:
    """원격의 sync 참조를 로컬 추적 참조로 가져온다. 원격에 아직 없으면 False."""
    done = subprocess.run(
        ["git", "-C", repo, "fetch", "--quiet", remote, f"+{REF}:{_REMOTE_TRACK}"],
        capture_output=True, text=True, timeout=_TIMEOUT)
    if done.returncode == 0:
        return True
    err = (done.stderr or "").lower()
    if "couldn't find remote ref" in err or "no such ref" in err:
        return False
    raise SyncRefError(done.stderr.strip() or "fetch 실패")


def list_remote(repo: str, ref: str = _REMOTE_TRACK) -> list:
    """참조 트리의 파일 경로 목록. 참조가 없으면 빈 목록."""
    if not _ref_exists(repo, ref):
        return []
    out = _git(repo, "ls-tree", "-r", "--name-only", ref)
    return [line for line in out.splitlines() if line]


def read_blob(repo: str, path: str, ref: str = _REMOTE_TRACK) -> bytes:
    """참조 트리 안 파일 하나의 내용(바이트)."""
    done = subprocess.run(["git", "-C", repo, "show", f"{ref}:{path}"],
                          capture_output=True, timeout=_TIMEOUT)
    if done.returncode != 0:
        raise SyncRefError(done.stderr.decode("utf-8", "replace").strip() or f"{path} 읽기 실패")
    return done.stdout


def commit_files(repo: str, files: dict, base_ref: str = None, message: str = "hermes sync",
                 remove=()) -> str:
    """base 트리 위에 files({경로: 바이트})를 얹고 remove 경로를 뺀 커밋을 만들어 REF 를 옮긴다.

    임시 인덱스만 쓰므로 작업 트리와 HEAD 는 그대로다. 커밋 해시를 돌려준다.
    remove 는 tombstone(사람 실행 전용) 에서만 쓴다 — 추가 전용 원칙의 유일한 예외(G-5).
    """
    parents = []
    base = base_ref if base_ref and _ref_exists(repo, base_ref) else None
    if base:
        parents = ["-p", _git(repo, "rev-parse", base).strip()]
    fd, index = tempfile.mkstemp(prefix=".hermes-sync-index-")
    os.close(fd)
    os.unlink(index)                       # git 이 새로 만들게 한다
    env = {"GIT_INDEX_FILE": index}
    try:
        if base:
            _git(repo, "read-tree", base, env=env)
        else:
            _git(repo, "read-tree", "--empty", env=env)
        for path, data in sorted(files.items()):
            blob = _hash_object(repo, data)
            _git(repo, "update-index", "--add", "--cacheinfo", f"100644,{blob},{path}", env=env)
        for path in remove:
            _git(repo, "update-index", "--force-remove", path, env=env)
        tree = _git(repo, "write-tree", env=env).strip()
        commit = _git(repo, "commit-tree", tree, *parents, "-m", message,
                      env={**env, "GIT_AUTHOR_NAME": "hermes-sync", "GIT_AUTHOR_EMAIL": "hermes@local",
                           "GIT_COMMITTER_NAME": "hermes-sync", "GIT_COMMITTER_EMAIL": "hermes@local"}).strip()
        _git(repo, "update-ref", REF, commit)
        return commit
    finally:
        if os.path.exists(index):
            os.unlink(index)


def _hash_object(repo: str, data: bytes) -> str:
    done = subprocess.run(["git", "-C", repo, "hash-object", "-w", "--stdin"],
                          input=data, capture_output=True, timeout=_TIMEOUT)
    if done.returncode != 0:
        raise SyncRefError(done.stderr.decode("utf-8", "replace").strip())
    return done.stdout.decode().strip()


def push_with_retry(repo: str, files: dict, remote: str = "origin", remove=()) -> str:
    """files 를 원격 sync 참조에 올린다. 거부되면 원격을 다시 받아 그 위에 얹어 재시도한다.

    `--force` 는 절대 쓰지 않는다 — 추가 전용이라 합집합이 언제나 올바른 병합이다.
    """
    last = ""
    for attempt in range(_RETRIES):
        has_remote = fetch(repo, remote)
        commit = commit_files(repo, files, _REMOTE_TRACK if has_remote else None,
                              message=f"hermes sync: {len(files)} files", remove=remove)
        done = subprocess.run(["git", "-C", repo, "push", "--quiet", remote, f"{REF}:{REF}"],
                              capture_output=True, text=True, timeout=_TIMEOUT)
        if done.returncode == 0:
            return commit
        last = (done.stderr or "").strip()
        _raise_unless_race(last)           # 경합(다른 클론이 먼저 밈)만 다음 반복으로
    raise SyncRefError(f"{_RETRIES}회 재시도 뒤에도 push 거부: {last}")


_UNSUPPORTED_MARKS = ("refusing", "not allowed", "unsupported", "hook declined")
_RACE_MARKS = ("rejected", "fetch first", "non-fast-forward")


def _raise_unless_race(stderr: str) -> None:
    """push 거부 사유 분류: 서버 거부(T-15) → unsupported, 경합 → 통과(재시도), 그 밖 → 오류."""
    low = stderr.lower()
    if any(m in low for m in _UNSUPPORTED_MARKS):
        raise SyncRefError(f"서버가 {REF} 를 거부했다 — 이식 불가, 사람 판단(T-15): {stderr}",
                           unsupported=True)
    if not any(m in low for m in _RACE_MARKS):
        raise SyncRefError(stderr or "push 실패")

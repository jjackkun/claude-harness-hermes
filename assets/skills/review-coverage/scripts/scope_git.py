"""git 에서 리뷰 범위를 모은다 — 바뀐 파일, 파일마다 바뀐 줄, 뺀 파일과 이유.

모든 경로는 저장소 맨 위(toplevel) 기준이다. 하위 폴더에서 불러도 같다.
"""
import os
import re
import subprocess

from scope_glob import glob_match

EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
# OCR internal/diff/git.go providerDirIgnoreDirs 와 같은 목록
EXCLUDED_DIRS = (".idea/", ".vscode/", ".svn/", ".git/", "vendor/", "node_modules/", "target/",
                 ".happypack/", ".cachefile/", "_packages/", "rpm/")
GENERATED = ("**/package-lock.json", "**/pnpm-lock.yaml", "**/yarn.lock", "**/*.lock",
             "**/*.min.js", "**/*.min.css")
BINARY_SNIFF = 8000
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


class ScopeError(Exception):
    """git 호출이 실패했거나 인자가 맞지 않는다."""


def _git(repo, *args):
    proc = subprocess.run(["git", "-C", repo, "-c", "core.quotepath=false", *args],
                          capture_output=True, encoding="utf-8", errors="replace")
    if proc.returncode != 0:
        raise ScopeError(f"git {' '.join(args)}: {proc.stderr.strip()}")
    return proc.stdout


def _ok(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True).returncode == 0


def _resolve(repo, ref_from, ref_to, commit):
    if commit and ref_from:
        raise ScopeError("--commit 와 --from 은 함께 쓸 수 없습니다")
    if ref_to and not ref_from:
        raise ScopeError("--to 는 --from 과 함께 씁니다")
    if commit:
        target = _git(repo, "rev-parse", "--verify", commit + "^{commit}").strip()
        has_parent = _ok(repo, "rev-parse", "--verify", target + "^")
        base = _git(repo, "rev-parse", target + "^").strip() if has_parent else EMPTY_TREE
        return {"mode": "commit", "base": base, "target": target}
    if ref_from:
        target = ref_to or "HEAD"
        base = _git(repo, "merge-base", ref_from, target).strip()
        return {"mode": "range", "base": base, "target": _git(repo, "rev-parse", target).strip()}
    base = "HEAD" if _ok(repo, "rev-parse", "--verify", "HEAD") else EMPTY_TREE
    return {"mode": "workspace", "base": base, "target": None}


def _diff_args(scope):
    return [scope["base"]] + ([scope["target"]] if scope["target"] else [])


def _numstat(repo, scope):
    """{새 경로: (added, deleted, 옛 경로)} — -z 형식이라 이름 변경·특수 문자도 정확하다."""
    fields = _git(repo, "diff", "--numstat", "-z", "--find-renames", *_diff_args(scope)).split("\0")
    out, i = {}, 0
    while i < len(fields) and fields[i]:
        added, deleted, path = fields[i].split("\t", 2)
        if path:
            out[path], i = (added, deleted, None), i + 1
        else:
            out[fields[i + 2]], i = (added, deleted, fields[i + 1]), i + 3
    return out


def _tracked(repo, scope):
    fields = _git(repo, "diff", "--name-status", "-z", "--find-renames", *_diff_args(scope)).split("\0")
    counts = _numstat(repo, scope)
    files, i = [], 0
    while i < len(fields) and fields[i]:
        status = fields[i][0]
        step = 3 if status in "RC" else 2
        path = fields[i + step - 1]
        added, deleted, old = counts.get(path, ("0", "0", None))
        entry = {"path": path, "status": status, "added": added, "deleted": deleted}
        if old:
            entry["old_path"] = old
        files.append(entry)
        i += step
    return files


def _count_lines(full):
    """(줄 수, 바이너리 여부). 파일 전체를 메모리에 올리지 않는다."""
    lines, last, head = 0, b"\n", b""
    with open(full, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            if len(head) < BINARY_SNIFF:
                head += chunk[:BINARY_SNIFF - len(head)]
            lines += chunk.count(b"\n")
            last = chunk[-1:]
    is_binary = b"\0" in head
    return (lines + (0 if last == b"\n" else 1)), is_binary


def _untracked(repo):
    files = []
    for path in filter(None, _git(repo, "ls-files", "--others", "--exclude-standard", "-z").split("\0")):
        full = os.path.join(repo, path)
        if path.endswith("/") or os.path.islink(full) or not os.path.isfile(full):
            files.append({"path": path, "status": "?", "added": "-", "deleted": "-", "not_file": True})
            continue
        lines, is_binary = _count_lines(full)
        files.append({"path": path, "status": "?", "added": "-" if is_binary else str(lines),
                      "deleted": "-" if is_binary else "0"})
    return files


def _exclusion(entry, patterns):
    path = entry["path"]
    checks = (
        (entry["status"] == "D", "삭제된 파일 — 새 코드가 없다"),
        (entry.get("not_file"), "일반 파일이 아님(하위 저장소·폴더·링크)"),
        (next((p for p in EXCLUDED_DIRS if path.startswith(p) or "/" + p in path), None), None),
        (any(glob_match(p, path) for p in GENERATED), "생성물(잠금 파일·압축본)"),
        (entry["added"] == "-", "바이너리"),
    )
    for hit, reason in checks:
        if hit:
            return reason or f"제외 디렉터리 {hit}"
    return next((f"--exclude {p}" for p in patterns if glob_match(p, path)), None)


def toplevel(repo):
    """repo 안 어느 폴더를 주어도 저장소 맨 위 절대 경로."""
    return _git(repo, "rev-parse", "--show-toplevel").strip()


def collect_scope(repo, ref_from=None, ref_to=None, commit=None, exclude=()):
    """리뷰 범위 dict: root·mode·base·target·reviewable[]·excluded[]."""
    root = toplevel(repo)
    scope = _resolve(root, ref_from, ref_to, commit)
    scope["root"] = root
    entries = _tracked(root, scope) + (_untracked(root) if scope["mode"] == "workspace" else [])
    scope["reviewable"], scope["excluded"] = [], []
    for entry in entries:
        reason = _exclusion(entry, exclude)
        if reason:
            scope["excluded"].append({"path": entry["path"], "status": entry["status"], "reason": reason})
        else:
            entry.pop("not_file", None)
            scope["reviewable"].append(entry)
    return scope


def changed_lines(scope, entry):
    """새 파일 쪽에서 바뀐 줄 번호 집합. untracked 는 파일 전체, 이름 변경은 옛 경로와 비교."""
    if entry["status"] == "?":
        return set(range(1, int(entry["added"]) + 1))
    paths = [p for p in (entry.get("old_path"), entry["path"]) if p]
    lines = set()
    out = _git(scope["root"], "diff", "-U0", "--no-color", "--no-ext-diff", "--find-renames",
               *_diff_args(scope), "--", *paths)
    for line in out.splitlines():
        hit = HUNK.match(line)
        if hit:
            start, count = int(hit.group(1)), int(hit.group(2) or 1)
            lines.update(range(start, start + count))
    return lines


def file_length(scope, path):
    """리뷰 대상 쪽(작업 트리 또는 target 커밋) 파일의 줄 수. 없으면 None."""
    root = scope["root"]
    if scope["target"]:
        if not _ok(root, "cat-file", "-e", f"{scope['target']}:{path}"):
            return None
        text = _git(root, "show", f"{scope['target']}:{path}")
        return text.count("\n") + (0 if text.endswith("\n") or not text else 1)
    full = os.path.join(root, path)
    return _count_lines(full)[0] if os.path.isfile(full) else None

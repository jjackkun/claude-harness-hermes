#!/usr/bin/env python3
"""Bash 명령이 데이터를 **지우는지** 가른다 (R-del).

근거: docs/exec-plans/completed/2026-10-27-data-delete-guard-plan.md 목표 G1 · G2
      (실측 뒤 에이전트가 개발 DB 의 번역 결과를 묻지 않고 지웠다 — 되살릴 수 없었다)

단일 책임: 명령 문자열 → 무엇을 지우는지 한 줄(묻기) 또는 None(통과). 결정 출력·기록은 진입 훅 몫이다.

- DB: 접속 도구 이름이 명령에 있고 삭제 SQL(또는 몽고·레디스 삭제)이 있으면. 파이프·히어독·변수로
  넘긴 SQL 도 잡으려고 도구 이름은 명령 전체에서 찾고, `-f 파일` 의 SQL 은 파일을 읽어 본다.
- 파일: 임시 자리 밖을 지우는 재귀 rm · find -delete · find -exec rm · git clean -f.
  변수가 든 대상도 임시 자리 이름이 없으면 묻는다. 히어독 본문은 명령이 아니라 데이터다.
한계: 래퍼 스크립트(`node purge.js`) 안의 삭제는 글자로 안 보인다 — 규칙 문장이 맡는다(계획 §3).
"""

import os
import re
import shlex

_DB_CLIENTS = re.compile(r"(?<![\w.-])(psql|mysql|mariadb|sqlite3|sqlcmd|mongosh|mongo|clickhouse-client)(?![\w.-])")
_SQL_DELETE = re.compile(
    r"\bDELETE\s+FROM\b|\bTRUNCATE\b|\bDROP\s+(TABLE|DATABASE|SCHEMA|VIEW|INDEX|MATERIALIZED\s+VIEW|OWNED)\b"
    r"|\.(deleteMany|deleteOne|drop|dropDatabase|remove)\s*\(",
    re.IGNORECASE,
)
_REDIS_DELETE = re.compile(r"\b(FLUSHALL|FLUSHDB|DEL|UNLINK)\b", re.IGNORECASE)
_SQL_FILE_LIMIT = 1024 * 1024  # 이보다 큰 SQL 파일은 앞부분만 본다
_PUNCT = ";&|\n()"
_WRAPPERS = ("sudo", "env", "time", "nohup", "exec", "command", "builtin", "nice", "xargs", "timeout")
_RESERVED = ("if", "then", "elif", "else", "do", "while", "until", "{", "}", "!")
# 지워도 되살릴 수 있거나 다시 만들어지는 자리 — 경로 조각 이름
_SCRATCH_PARTS = {"node_modules", "dist", "build", "__pycache__", ".cache", "coverage", ".pytest_cache",
                  ".svelte-kit", ".next", ".turbo", ".parcel-cache", "tmp", ".tmp"}
_HEREDOC = re.compile(r"<<(?!<)-?\s*(['\"]?)(\w+)\1")


def _drop_heredoc_bodies(cmd):
    out, ends = [], []
    for line in cmd.split("\n"):
        if ends:
            if line.strip() == ends[0]:
                ends.pop(0)
            continue
        out.append(line)
        ends = [m.group(2) for m in _HEREDOC.finditer(line)]
    return "\n".join(out)


def _segments(cmd):
    lex = shlex.shlex(cmd.replace("`", " ; "), posix=True, punctuation_chars=_PUNCT)
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""
    words, out = [], []
    for tok in lex:
        if set(tok) <= set(_PUNCT):
            out.append(words)
            words = []
        else:
            words.append(tok)
    out.append(words)
    return [_strip_wrappers(w) for w in out if w]


def _strip_wrappers(words):
    i = 0
    while i < len(words) and (words[i] in _WRAPPERS or words[i] in _RESERVED
                              or ("=" in words[i] and not words[i].startswith("-"))
                              or (i > 0 and words[i - 1] in _WRAPPERS and words[i].startswith("-"))):
        i += 1
    return words[i:]


def _is_scratch(path):
    if not path:
        return False
    if path.startswith(("/tmp", "/var/tmp")) or ".harness/out" in path:
        return True
    return any(part in _SCRATCH_PARTS for part in path.rstrip("/").split("/"))


def _sql_files(words):
    files = []
    for i, w in enumerate(words):
        if w in ("-f", "--file") and i + 1 < len(words):
            files.append(words[i + 1])
        elif w.startswith("--file="):
            files.append(w.split("=", 1)[1])
    return files


def _redis_delete(segments):
    for words in segments:
        if words and os.path.basename(words[0]) == "redis-cli" and any(_REDIS_DELETE.fullmatch(w) for w in words[1:]):
            return "레디스 키 삭제"
    return None


def _file_has_delete_sql(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return bool(_SQL_DELETE.search(fh.read(_SQL_FILE_LIMIT)))
    except OSError:
        return False


def _sql_file_delete(segments):
    for words in segments:
        for path in _sql_files(words):
            if _file_has_delete_sql(path):
                return f"DB 삭제 SQL(파일 {path})"
    return None


def _db_delete(cmd, segments):
    found = _redis_delete(segments)
    if found or not _DB_CLIENTS.search(cmd):
        return found
    if _SQL_DELETE.search(cmd):
        return "DB 삭제 SQL"
    return _sql_file_delete(segments)


def _short_flags(flags):
    """-rf 같은 묶음 단축 옵션의 글자들."""
    return "".join(f[1:] for f in flags if not f.startswith("--"))


def _rm_delete(words):
    flags = [w for w in words[1:] if w.startswith("-") and w != "--"]
    recursive = "--recursive" in flags or "r" in _short_flags(flags) or "R" in _short_flags(flags)
    kept = [t for t in words[1:] if not t.startswith("-") and not _is_scratch(t)]
    return f"재귀 삭제 {' '.join(kept)}" if recursive and kept else None


def _find_delete(words):
    runs_rm = any(w == "-exec" and i + 1 < len(words) and os.path.basename(words[i + 1]) == "rm" for i, w in enumerate(words))
    root = words[1] if len(words) > 1 and not words[1].startswith("-") else "."
    return f"find 로 지우기 {root}" if ("-delete" in words or runs_rm) and not _is_scratch(root) else None


def _git_clean_delete(words):
    if "clean" not in words[1:]:
        return None
    flags = [w for w in words[words.index("clean") + 1:] if w.startswith("-")]
    forced = "--force" in flags or "f" in _short_flags(flags)
    dry = "--dry-run" in flags or "n" in _short_flags(flags)
    return "git clean (추적 안 되는 파일 삭제)" if forced and not dry else None


_FILE_JUDGES = {"rm": _rm_delete, "find": _find_delete, "git": _git_clean_delete}


def _file_delete(words):
    judge_one = _FILE_JUDGES.get(os.path.basename(words[0]))
    return judge_one(words) if judge_one else None


def judge(command):
    """무엇을 지우는지 한 줄, 지우지 않으면 None. 읽을 수 없는 명령은 None(막지 않는다)."""
    cmd = str(command or "")
    try:
        segments = _segments(_drop_heredoc_bodies(cmd))
        db_segments = _segments(cmd)
    except ValueError:
        return None  # 따옴표가 안 닫힘 — 판정 불가는 막지 않는다
    found = _db_delete(cmd, db_segments)
    if found:
        return found
    for words in segments:
        found = _file_delete(words)
        if found:
            return found
    return None

#!/usr/bin/env python3
"""Bash 명령이 모델을 여러 번 부르는 평가 도구를 **실행하는지** 가른다 (R-cost G1).

근거: docs/exec-plans/active/2026-10-21-cost-guard-plan.md 목표 G1
      (평가를 묻지 않고 대량 실행 → 사용자 구독 한도 소진)

단일 책임: 명령 문자열 → "ask" | "allow". 결정 출력·기록은 진입 훅 몫이다.

글자가 아니라 **단어**로 본다. `grep scripts.run_eval` 처럼 이름을 다루기만 하는 명령은
통과시키고, 실제로 python/bash 가 그 도구를 실행할 때만 묻는다.
한계: 사용자가 만든 래퍼 스크립트 안의 호출은 글자로 안 보여 못 잡는다(계획 §3).
"""

import os
import re
import shlex

# 모델을 반복 호출하는 평가 도구. -m 으로 부르는 모듈과 경로로 부르는 파일 이름.
_EXPENSIVE_MODULES = ("scripts.run_eval", "scripts.run_loop")
_EXPENSIVE_FILES = ("run_eval.py", "run_loop.py", "harness-eval.py")
# 실행하지 않고 설명만 보이는 인자
_SAFE_FLAGS = ("--dry-run", "--help", "-h")
# 구분자 글자. 괄호까지 넣어 `$(…)`·`( … )` 안쪽을 따로 본다(리뷰 지적).
_PUNCT = ";&|\n()"
# 앞에 붙어도 뒤 명령을 그대로 실행하는 래퍼. 뒤따르는 옵션·숫자 인자는 함께 벗긴다.
_WRAPPERS = ("env", "nohup", "time", "exec", "command", "sudo", "nice", "xargs", "timeout", "caffeinate")
# `uv run python …` 처럼 두 단어로 된 래퍼
_RUNNERS = ("uv", "poetry", "pipenv", "pdm", "hatch", "rye")
# 제어 구문 예약어 — 뒤에 오는 것이 실제 명령이다
_RESERVED = ("if", "then", "elif", "else", "do", "while", "until", "{", "}", "!")
# 값을 하나 받는 python 옵션 — 그 값을 실행 대상으로 착각하지 않게 건너뛴다
_PY_VALUE_OPTS = ("-W", "-X")
_NUMBER = re.compile(r"^\d+(\.\d+)?[smhd]?$")


def _segments(command):
    # 따옴표 밖 줄바꿈도 명령 구분자다 — 공백으로 두면 두 줄이 한 명령으로 붙는다.
    # 백틱은 shlex 가 모르므로 구분자로 바꾼다. 따옴표 짝은 바뀌지 않는다.
    lex = shlex.shlex(command.replace("`", " ; "), posix=True, punctuation_chars=_PUNCT)
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
    return [w for w in out if w]


def _is_single_prefix(w):
    """예약어나 `X=1` 처럼 혼자 벗겨지는 한 단어인가."""
    if w in _RESERVED:
        return True
    return "=" in w and not w.startswith("-") and w.split("=", 1)[0].isidentifier()


def _wrapper_width(words, i):
    """words[i] 가 래퍼면 그 래퍼와 옵션·숫자 인자가 차지하는 단어 수, 아니면 0."""
    w = words[i]
    if _is_single_prefix(w):
        return 1
    if w in _RUNNERS and i + 1 < len(words) and words[i + 1] == "run":
        n = 2
    elif w in _WRAPPERS:
        n = 1
    else:
        return 0
    while i + n < len(words) and (words[i + n].startswith("-") or _NUMBER.match(words[i + n])):
        n += 1
    return n


def _strip_prefix(words):
    i = 0
    while i < len(words):
        width = _wrapper_width(words, i)
        if not width:
            break
        i += width
    return words[i:]


def _is_python(word):
    base = os.path.basename(word)
    return base == "python" or base.startswith("python3")


def _python_target(args):
    """python 인자에서 실행 대상(모듈 또는 파일)을 꺼낸다."""
    skip = False
    for i, a in enumerate(args):
        if skip:
            skip = False
            continue
        if a in _PY_VALUE_OPTS:
            skip = True
            continue
        if a == "-m" and i + 1 < len(args):
            return args[i + 1]
        if a.startswith("-m") and len(a) > 2:
            return a[2:]
        if a == "-c":
            return None
        if not a.startswith("-"):
            return a
    return None


def _is_expensive_target(target):
    if not target:
        return False
    if any(target == m or target.endswith("." + m) for m in _EXPENSIVE_MODULES):
        return True
    return os.path.basename(target) in _EXPENSIVE_FILES


def _shell_c_flag(head, args):
    """bash/sh 의 -c 계열 플래그(-c · -lc · -xc …) 위치, 없으면 None."""
    if os.path.basename(head) not in ("bash", "sh", "zsh"):
        return None
    for i, a in enumerate(args):
        if a.startswith("-") and not a.startswith("--") and "c" in a[1:]:
            return i
    return None


def _segment_expensive(words, depth):
    words = _strip_prefix(words)
    if not words:
        return False
    head, args = words[0], words[1:]
    flag = _shell_c_flag(head, args)
    if flag is not None:
        inner = args[flag + 1:flag + 2]
        return bool(inner) and depth < 3 and _expensive(inner[0], depth + 1)
    if _is_python(head):
        target = _python_target(args)
    elif os.path.basename(head) in ("bash", "sh"):
        target = next((a for a in args if not a.startswith("-")), None)
    else:
        target = head  # ./scripts/harness-eval.py 처럼 직접 실행
    if not _is_expensive_target(target):
        return False
    return not any(f in args for f in _SAFE_FLAGS)


def _expensive(command, depth=0):
    try:
        segments = _segments(command)
    except ValueError:
        return False  # 따옴표가 안 닫힌 명령 — 셸도 못 돌리므로 통과
    return any(_segment_expensive(s, depth) for s in segments)


def classify(command):
    """명령이 비싼 평가를 실행하면 "ask", 아니면 "allow"."""
    return "ask" if _expensive(command or "") else "allow"

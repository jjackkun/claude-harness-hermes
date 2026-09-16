#!/usr/bin/env python3
"""`done_when` 다섯 형식의 파싱과 기계 검증만 담당한다 (G-21).

봉투의 `done_when` 은 받는 쪽이 "성공" 이라 주장할 때 기계가 **다시 재는** 기준이다.
형식이 부족하면 `manual` 이 늘고 `verified: none` 비율이 오른다 — 그 비율이 다음 형식을
추가할 신호다(설계).

  test:<이름>       그 테스트의 종료 코드            pass / fail
  file:<경로>       파일 존재                       pass / fail
  gate:<규칙>       .harness/gate-events.jsonl 판정   pass / fail
  commit:<해시|HEAD> 저장소에 그 커밋이 있는가          pass / fail
  manual            사람이 잰다                     none  ← 이 형식만
계획: docs/exec-plans/active/2026-09-15-agent-identity.md 목표 12

공개 함수 3개: is_valid · verify · DoneWhenError
"""

import json
import os
import subprocess

_FORMS = ("test", "file", "gate", "commit", "manual")
_TIMEOUT = 300


class DoneWhenError(ValueError):
    """done_when 형식이 다섯 가지 밖이다."""


def _split(spec: str):
    spec = (spec or "").strip()
    if spec == "manual":
        return "manual", ""
    if ":" not in spec:
        raise DoneWhenError(f"done_when 형식이 아니다: {spec} (허용: {', '.join(_FORMS)})")
    form, arg = spec.split(":", 1)
    if form not in _FORMS:
        raise DoneWhenError(f"모르는 done_when 형식: {form}")
    if not arg.strip():
        raise DoneWhenError(f"{form}: 뒤에 값이 없다")
    return form, arg.strip()


def is_valid(spec: str) -> bool:
    """봉투 검증기가 부르는 형식 검사 — 재지 않고 형식만 본다."""
    try:
        _split(spec)
        return True
    except DoneWhenError:
        return False


def verify(spec: str, project: str) -> str:
    """지금 상태로 done_when 을 재서 pass / fail / none 을 돌려준다.

    manual 만 none 이다 — 나머지는 기계가 재므로 언제나 pass 또는 fail.
    """
    form, arg = _split(spec)
    if form == "manual":
        return "none"
    return {"test": _verify_test, "file": _verify_file,
            "gate": _verify_gate, "commit": _verify_commit}[form](arg, project)


def _pass(ok: bool) -> str:
    return "pass" if ok else "fail"


def _verify_file(arg: str, project: str) -> str:
    path = arg if os.path.isabs(arg) else os.path.join(project, arg)
    return _pass(os.path.exists(path))


def _verify_test(arg: str, project: str) -> str:
    """tests/<이름> 또는 <이름> 스크립트를 돌려 종료 코드로 판정한다."""
    candidates = [os.path.join(project, "tests", arg), os.path.join(project, arg), arg]
    script = next((c for c in candidates if os.path.isfile(c)), None)
    if script is None:
        return "fail"
    runner = ["bash", script] if script.endswith(".sh") else ["python3", script]
    try:
        done = subprocess.run(runner, capture_output=True, timeout=_TIMEOUT, cwd=project)
    except (OSError, subprocess.SubprocessError):
        return "fail"
    return _pass(done.returncode == 0)


def _verify_gate(arg: str, project: str) -> str:
    """gate-events.jsonl 에서 그 규칙의 **가장 최근** 판정을 본다. block 이면 fail."""
    path = os.path.join(project, ".harness", "gate-events.jsonl")
    last = None
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if event.get("rule") == arg:
                    last = event.get("verdict")
    except OSError:
        return "fail"
    if last is None:
        return "fail"
    return _pass(last in ("pass", "allow"))


def _verify_commit(arg: str, project: str) -> str:
    ref = "HEAD" if arg == "HEAD" else arg
    done = subprocess.run(["git", "-C", project, "cat-file", "-e", f"{ref}^{{commit}}"],
                          capture_output=True)
    return _pass(done.returncode == 0)

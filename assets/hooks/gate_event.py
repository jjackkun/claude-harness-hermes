#!/usr/bin/env python3
"""게이트 판정 1건을 `.harness/gate-events.jsonl` 에 append 한다.

근거: docs/design-docs/core-beliefs.md — R 룰 10개가 Provisional 이면서
"발화율 관측 중" 이라고 적혀 있으나 발화를 기록하는 코드가 없었다.
승격·강등 판단의 입력을 만드는 것이 이 모듈의 유일한 책임이다.

단일 책임: **쓰기와 스키마 정의**. 읽기·집계는 gate_report.py 몫이다.
경로와 필드 이름의 주인은 이 파일 하나다 — 같은 것을 두 곳에서 정의하면
반드시 갈라진다(iface_width.py 통합과 같은 판단).

사용법:
  gate_event.py emit --rule R-iface --verdict block \
      [--stage pretooluse] [--path FILE] [--detail TEXT]

종료코드 계약: **항상 0**.
관측 장치가 게이트를 죽이면 안 된다. 실패는 stderr 한 줄로 알리되 막지 않는다.
(조용한 실패 금지 원칙은 지키고, 호출부 차단은 하지 않는다.)
"""

import json
import os
import subprocess
import sys
import time

# 이벤트 레코드의 필드 순서 = 스키마. gate_report.py 가 이 상수를 import 한다.
FIELDS = ("ts", "rule", "verdict", "stage", "path", "detail")

# 판정 종류.
#
# `waived` 를 `pass` 와 합치지 않는 이유: R-iface 가 경계하는 것은 차단 횟수가 아니라
# 우회의 상시화이고, 합치면 그 신호가 사라진다.
#
# `skipped` 는 **게이트가 판정하지 못한 것**이다 — 판정 모듈이 없거나 python3 가 없어
# 검사를 건너뛴 경우. pass 로 세면 "게이트가 죽었는데 통과 표시가 나는" 상태가
# 관측에서도 그대로 재현된다. 이 저장소는 그 실패를 이미 두 번 겪었다
# (R-test 가 테스트 0개로 늘 통과, pre-commit 이 .review-dirty 를 한 번도 읽지 않음).
VERDICTS = ("pass", "warn", "block", "waived", "skipped")

# 게이트가 도는 시점. pre-commit 에는 세션 개념이 없어 session 필드는 두지 않는다.
STAGES = ("pretooluse", "posttooluse", "precommit", "sessionstart")

_REL = os.path.join(".harness", "gate-events.jsonl")
_MAX_LINES_DEFAULT = 5000


def events_path():
    """이벤트 파일의 절대 경로. 프로젝트 루트를 못 찾으면 None.

    CLAUDE_PROJECT_DIR → git 최상위 순으로 찾는다. cwd 는 쓰지 않는다 —
    pre-commit 과 훅의 cwd 가 서로 달라 같은 프로젝트가 두 곳에 쌓인다.
    """
    root = os.environ.get("CLAUDE_PROJECT_DIR")
    if not root or not os.path.isdir(root):
        try:
            out = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                capture_output=True, text=True, timeout=5,
            )
            root = out.stdout.strip() if out.returncode == 0 else ""
        except (OSError, subprocess.SubprocessError):
            root = ""
    if not root or not os.path.isdir(root):
        return None
    return os.path.join(root, _REL)


def _max_lines():
    raw = os.environ.get("GATE_EVENTS_MAX_LINES", "")
    if raw.isdigit() and int(raw) > 0:
        return int(raw)
    return _MAX_LINES_DEFAULT


def _rotate(path, limit):
    """상한 초과 시 가장 오래된 줄부터 잘라낸다.

    시간이 아니라 줄 수 기준인 이유: 발화 빈도가 프로젝트마다 달라
    시간 상한은 부피를 보장하지 못한다. 디스크 상한은 부피의 함수다.
    """
    with open(path, "r", encoding="utf-8") as fh:
        lines = fh.readlines()
    if len(lines) <= limit:
        return
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.writelines(lines[-limit:])
    os.replace(tmp, path)


def emit(rule, verdict, stage=None, path=None, detail=None):
    """이벤트 1건 기록. 성공하면 True, 기록하지 못했으면 False."""
    if verdict not in VERDICTS:
        raise ValueError("알 수 없는 verdict: %s (허용: %s)" % (verdict, ", ".join(VERDICTS)))
    if stage is not None and stage not in STAGES:
        raise ValueError("알 수 없는 stage: %s (허용: %s)" % (stage, ", ".join(STAGES)))
    target = events_path()
    if target is None:
        return False
    record = dict(zip(FIELDS, (int(time.time()), rule, verdict, stage, path, detail)))
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    _rotate(target, _max_lines())
    return True


def _parse(tokens):
    """`--key value` 묶음을 dict 로. `+` 는 레코드 구분자다."""
    args, key = {}, None
    for tok in tokens:
        if tok.startswith("--"):
            key = tok[2:]
            args[key] = None
        elif key is not None:
            args[key] = tok
            key = None
    return args


def main(argv):
    if len(argv) < 2 or argv[1] != "emit":
        print(__doc__, file=sys.stderr)
        return 0
    # 한 번의 기동으로 여러 레코드를 쓴다. 훅 하나가 축을 둘 이상 판정할 때
    # (예: size-warn 의 줄 수 축 + 책임 축) 프로세스를 두 번 띄우면
    # 관측 비용이 게이트 비용을 넘는다 — 실측 2026-09-03: 기동 1회 21ms.
    groups, cur = [], []
    for tok in argv[2:]:
        if tok == "+":
            groups.append(cur)
            cur = []
        else:
            cur.append(tok)
    groups.append(cur)
    for tokens in groups:
        if not tokens:
            continue
        args = _parse(tokens)
        try:
            if not args.get("rule") or not args.get("verdict"):
                raise ValueError("--rule 과 --verdict 는 필수다")
            emit(args["rule"], args["verdict"], args.get("stage"),
                 args.get("path"), args.get("detail"))
        except Exception as exc:  # 관측 실패가 게이트를 죽이면 안 된다
            print("[gate-event] 기록 실패: %s" % exc, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""계획서 마크다운의 상태를 판정한다.

단일 책임: 마크다운 해석. 파일 열거와 git 조회는 호출부(bash) 몫이다.
이 경계 덕분에 git 없이 단위 테스트가 가능하다.

종료코드 계약:
  is-complete <path>   0=완료   1=미완료   2=판정불가
  retro-empty <path>   0=비었음 1=채워짐   2=판정불가
  pending <path>       0=성공              2=판정불가 (미완료 항목을 stdout 출력)
  list-complete    <path>...  해당 경로만 stdout, 0=성공 2=일부 판정불가(stderr 보고)
  list-retro-empty <path>...  동일. 프로세스 1회로 다수 파일을 훑는 배치 경로.

모든 예외는 exit 2 로 매핑한다. 파이썬 기본 예외 종료코드는 1 인데,
retro-empty 에서 1 은 "채워짐(통과)" 이므로 크래시가 조용한 통과로 둔갑한다.

stdin 을 읽지 않는다 — claude-userpromptsubmit-reminders.sh 가
`while read ... done < <(find ...)` 루프 안에서 호출하므로,
stdin 을 소비하면 그 루프가 깨진다.
"""

import os
import re
import sys

# assets/docs-templates/docs/exec-plans/template.md 의 §8 라벨.
# 템플릿을 고치면 여기도 함께 고쳐야 한다.
# tests/plan-state-test.sh 가 실제 template.md 를 입력으로 써서 어긋남을 잡는다.
RETRO_LABELS = ("잘된 것", "잘못된 것", "다음 룰 후보")

PENDING_MAX_DEFAULT = 3

# 체크박스만 센다. `- [foo.md](foo.md)` 같은 링크 불릿을 제외하기 위해
# 대괄호 안을 공백/x/X 로 한정하고 닫는 괄호 뒤 공백을 요구한다.
CHECKBOX_RE = re.compile(r"^\s*-\s*\[( |x|X)\]\s")

RETRO_HEADING_RE = re.compile(r"^##\s*8[.)]")
RETRO_FALLBACK_RE = re.compile(r"^##.*회고")
SECTION_END_RE = re.compile(r"^##\s")


def read_lines(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read().splitlines()


def count_boxes(lines):
    total = 0
    done = 0
    for line in lines:
        match = CHECKBOX_RE.match(line)
        if not match:
            continue
        total += 1
        if match.group(1) in ("x", "X"):
            done += 1
    return total, done


def is_complete(lines):
    total, done = count_boxes(lines)
    return total > 0 and total == done


def retro_lines(lines):
    """§8 회고 섹션의 본문 줄을 돌려준다. 섹션이 없으면 None."""
    start = None
    for index, line in enumerate(lines):
        if RETRO_HEADING_RE.match(line):
            start = index
            break
    if start is None:
        for index, line in enumerate(lines):
            if RETRO_FALLBACK_RE.match(line):
                start = index
                break
    if start is None:
        return None

    body = []
    for line in lines[start + 1:]:
        if SECTION_END_RE.match(line):
            break
        body.append(line)
    return body


def is_retro_empty(lines):
    """템플릿 라벨의 콜론 뒤가 전부 비었고 라벨 외 실질 텍스트도 없으면 True.

    기계가 판단할 수 있는 것은 '쓰지 않았음' 까지다. 회고의 품질은 보지 않는다.
    """
    body = retro_lines(lines)
    if body is None:
        return True

    for line in body:
        stripped = line.strip()
        if not stripped:
            continue

        matched_label = False
        for label in RETRO_LABELS:
            prefix = "- %s:" % label
            if stripped.startswith(prefix):
                matched_label = True
                if stripped[len(prefix):].strip():
                    return False
                break

        if not matched_label:
            return False

    return True


def pending_items(lines, max_count):
    """미완료 체크박스 줄을 최대 max_count 개 돌려준다."""
    items = []
    for line in lines:
        match = CHECKBOX_RE.match(line)
        if match and match.group(1) == " ":
            items.append(line.strip())
            if len(items) >= max_count:
                break
    return items


def scan(paths, predicate):
    """paths 중 predicate 가 참인 경로를 stdout 으로 출력한다.

    파일마다 프로세스를 새로 띄우면 completed/ 가 148개인 저장소에서 2.6초가 걸린다
    (2026-08-13 실측). 세션 시작 훅이 동기로 부르려면 한 번에 처리해야 한다.
    경로 열거는 여전히 호출부(bash) 몫이다 — 여기서는 넘겨받은 경로만 읽는다.

    판정불가 경로는 stderr 로 보고하고 나머지는 계속 처리한다. 하나라도 있으면 exit 2 —
    단일 경로 계약의 "2=판정불가" 를 배치 수준에서 유지한다.
    """
    had_error = False
    for path in paths:
        if os.path.basename(path) == "template.md":
            continue
        try:
            lines = read_lines(path)
        except Exception as exc:  # noqa: BLE001 — 한 파일의 실패가 전체를 멈추지 않는다
            print("unparsable: %s (%s)" % (path, exc), file=sys.stderr)
            had_error = True
            continue
        if predicate(lines):
            print(path)
    return 2 if had_error else 0


def main(argv):
    if len(argv) < 2:
        print("usage: plan_state.py {is-complete|retro-empty|pending|"
              "list-complete|list-retro-empty} <path>... [--max N]", file=sys.stderr)
        return 2

    command = argv[1]

    # 배치 명령은 경로를 0개 이상 받는다. 단일 경로 전처리보다 먼저 처리한다.
    if command == "list-complete":
        return scan(argv[2:], is_complete)
    if command == "list-retro-empty":
        return scan(argv[2:], is_retro_empty)

    if len(argv) < 3:
        print("usage: plan_state.py %s <path>" % command, file=sys.stderr)
        return 2

    path = argv[2]

    # 템플릿은 정의상 미체크에 §8 이 비어 있다. 판정 대상에 넣으면 영구 위반원이 된다.
    # 호출부(bash)도 걸러내지만 여기서도 막는다 — 이중 안전장치.
    if os.path.basename(path) == "template.md":
        return 1

    lines = read_lines(path)

    if command == "is-complete":
        return 0 if is_complete(lines) else 1

    if command == "retro-empty":
        return 0 if is_retro_empty(lines) else 1

    if command == "pending":
        max_count = PENDING_MAX_DEFAULT
        if "--max" in argv:
            max_count = int(argv[argv.index("--max") + 1])
        for item in pending_items(lines, max_count):
            print(item)
        return 0

    print("unknown subcommand: %s" % command, file=sys.stderr)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as exc:  # noqa: BLE001 — 모든 예외를 계약상 2 로 수렴시킨다
        print("plan_state: %s" % exc, file=sys.stderr)
        sys.exit(2)

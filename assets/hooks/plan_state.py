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
# 대괄호 안을 표시 문자로 한정하고 닫는 괄호 뒤 공백을 요구한다.
#
# `~`(진행 중)를 목록에 넣는 이유: 넣지 않으면 그 줄은 매치되지 않아 **아예 안 세어진다.**
# 안 센 것은 0 이 되고 0 은 "없다" 로 읽혀, 사람 손이 남은 계획을 계수기가 완료로
# 판정한다(하류에서 실제로 겪은 사고 — 2026-08-25). 침묵보다 나쁜 조용한 오답이다.
CHECKBOX_RE = re.compile(r"^\s*-\s*\[( |x|X|~)\]\s")

# 완료로 세는 표시. **정규식과 따로 둔다** — 완료 판정을 `!= " "` 로 쓰면
# `~` 가 완료로 세어져 지금보다 나빠진다. 표시를 늘릴 때 여기만 보면 된다.
DONE_MARKS = ("x", "X")

RETRO_HEADING_RE = re.compile(r"^##\s*8[.)]")
RETRO_FALLBACK_RE = re.compile(r"^##.*회고")
SECTION_END_RE = re.compile(r"^##\s")

# §2 목표 섹션. 회고(§8)와 같은 방식으로 번호 우선, 제목 폴백.
GOAL_HEADING_RE = re.compile(r"^##\s*2[.)]")
GOAL_FALLBACK_RE = re.compile(r"^##.*목표")

# §4 영향 영역. 신규 파일 선언이 여기 있다.
IMPACT_HEADING_RE = re.compile(r"^##\s*4[.)]")
IMPACT_FALLBACK_RE = re.compile(r"^##.*영향 영역")

# 선언 항목은 인라인 코드 스팬 안에 경로를 적는다 — 템플릿이 보여주는 형식이다.
DECL_PATH_RE = re.compile(r"`([^`]+)`")

# 템플릿이 그대로 남아 있는 것은 선언이 아니다. 채우지 않은 계획서를
# "선언했다" 로 세면 이 검사가 곧 무의미해진다.
PLACEHOLDER_PATHS = ("path/to/file.ext", "path/to/barrel/index.ts")

# 검증 명령의 표지는 인라인 코드 스팬이다. 명령을 파싱하지도 실행하지도 않는다 —
# 계획서는 에이전트가 쓰는 파일이고, 거기 적힌 것을 훅이 실행하면 게이트가
# 게이트 대상에게 실행 권한을 넘기는 것이 된다. "적혀 있는가" 까지만 본다.
INLINE_CODE_RE = re.compile(r"`[^`]+`")


def read_lines(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read().splitlines()


def _section_body(lines, heading_re, fallback_re):
    """제목 정규식으로 시작하는 섹션의 본문 줄을 돌려준다. 섹션이 없으면 None."""
    start = None
    for pattern in (heading_re, fallback_re):
        for index, line in enumerate(lines):
            if pattern.match(line):
                start = index
                break
        if start is not None:
            break
    if start is None:
        return None

    body = []
    for line in lines[start + 1:]:
        if SECTION_END_RE.match(line):
            break
        body.append(line)
    return body


def count_boxes(lines):
    total = 0
    done = 0
    for line in lines:
        match = CHECKBOX_RE.match(line)
        if not match:
            continue
        total += 1
        if match.group(1) in DONE_MARKS:
            done += 1
    return total, done


def is_complete(lines):
    total, done = count_boxes(lines)
    return total > 0 and total == done


def retro_lines(lines):
    """§8 회고 섹션의 본문 줄을 돌려준다. 섹션이 없으면 None."""
    return _section_body(lines, RETRO_HEADING_RE, RETRO_FALLBACK_RE)


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
        if match and match.group(1) not in DONE_MARKS:
            items.append(line.strip())
            if len(items) >= max_count:
                break
    return items


def _goal_items(lines):
    """§2 목표 항목을 [{checked, text, verified}] 로 돌려준다. §2 가 없으면 None.

    검증 명령은 목표 줄 자체 또는 그 뒤 이어지는 줄에 올 수 있다 —
    템플릿이 보여주는 형식이 명령을 다음 줄에 들여쓰는 형태이기 때문이다.
    """
    body = _section_body(lines, GOAL_HEADING_RE, GOAL_FALLBACK_RE)
    if body is None:
        return None

    items = []
    for line in body:
        match = CHECKBOX_RE.match(line)
        if match:
            items.append({
                "checked": match.group(1) in DONE_MARKS,
                "text": line.strip(),
                "verified": bool(INLINE_CODE_RE.search(line)),
            })
        elif items and line.strip() and INLINE_CODE_RE.search(line):
            items[-1]["verified"] = True
    return items


def _declared_files(lines):
    """§4 에 선언된 신규 파일 경로. §4 가 없으면 None.

    템플릿은 "신규 파일 목록 (파일별 책임 1줄 필수) ← 비워두지 말 것" 을 요구하고
    "위 목록을 먼저 못 쓰면 아직 설계가 덜 됐다는 뜻" 이라고까지 적는다.
    그런데 파서가 §4 를 몰라 강제가 없었다(2026-08-25).
    """
    body = _section_body(lines, IMPACT_HEADING_RE, IMPACT_FALLBACK_RE)
    if body is None:
        return None

    found = []
    for line in body:
        for path in DECL_PATH_RE.findall(line):
            path = path.strip()
            # 경로처럼 생긴 것만. 룰 번호(`R-iface`)나 명령은 선언이 아니다.
            if "/" not in path and "." not in path:
                continue
            if path in PLACEHOLDER_PATHS:
                continue
            if path not in found:
                found.append(path)
    return found


def _report_goals(lines, select):
    """§2 목표 중 select 가 참인 것을 출력한다. 0=해당 있음 1=없음 2=§2 부재."""
    items = _goal_items(lines)
    if items is None:
        return 2
    hits = [item["text"] for item in items if select(item)]
    for hit in hits:
        print(hit)
    return 0 if hits else 1


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


# 서브커맨드를 if 사슬로 늘어놓으면 명령 하나마다 main 의 복잡도가 1씩 오른다.
# R-acc 가 두 개를 더할 때 기준선(13)을 넘겨 R-cx 에 막혔다 — 표로 옮겨 분기를 없앤다.
# 배치 명령: 경로 0개 이상, 파일별 판정 술어를 받는다.
BATCH_COMMANDS = {
    "list-complete": is_complete,
    "list-retro-empty": is_retro_empty,
}

# 단일 경로 명령: lines 와 argv 를 받아 종료코드를 돌려준다.
SINGLE_COMMANDS = {
    "is-complete": lambda lines, argv: 0 if is_complete(lines) else 1,
    "retro-empty": lambda lines, argv: 0 if is_retro_empty(lines) else 1,
    "pending": lambda lines, argv: _print_pending(lines, argv),
    "goals-unverified": lambda lines, argv: _report_goals(
        lines, lambda item: not item["verified"]),
    "declared-files": lambda lines, argv: _print_declared(lines),
    "goals-pending": lambda lines, argv: _report_goals(
        lines, lambda item: not item["checked"]),
}


def _print_declared(lines):
    """0=선언 있음  1=§4 는 있으나 선언 0개  2=§4 부재."""
    found = _declared_files(lines)
    if found is None:
        return 2
    for path in found:
        print(path)
    return 0 if found else 1


def _print_pending(lines, argv):
    max_count = PENDING_MAX_DEFAULT
    if "--max" in argv:
        max_count = int(argv[argv.index("--max") + 1])
    for item in pending_items(lines, max_count):
        print(item)
    return 0


def main(argv):
    command = argv[1] if len(argv) >= 2 else ""

    if command in BATCH_COMMANDS:
        # 배치 명령은 경로를 0개 이상 받는다. 단일 경로 전처리보다 먼저 처리한다.
        return scan(argv[2:], BATCH_COMMANDS[command])

    if command not in SINGLE_COMMANDS:
        print("usage: plan_state.py {%s} <path>... [--max N]"
              % "|".join(list(SINGLE_COMMANDS) + list(BATCH_COMMANDS)), file=sys.stderr)
        return 2

    if len(argv) < 3:
        print("usage: plan_state.py %s <path>" % command, file=sys.stderr)
        return 2

    path = argv[2]

    # 템플릿은 정의상 미체크에 §8 이 비어 있다. 판정 대상에 넣으면 영구 위반원이 된다.
    # 호출부(bash)도 걸러내지만 여기서도 막는다 — 이중 안전장치.
    if os.path.basename(path) == "template.md":
        return 1

    return SINGLE_COMMANDS[command](read_lines(path), argv)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as exc:  # noqa: BLE001 — 모든 예외를 계약상 2 로 수렴시킨다
        print("plan_state: %s" % exc, file=sys.stderr)
        sys.exit(2)

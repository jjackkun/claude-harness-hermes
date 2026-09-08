#!/usr/bin/env python3
"""R-doc — 문서가 주장하는 수치를 소스에서 산출하고, 문서와 어긋나는지 판정한다.

근거: docs/exec-plans/active/2026-09-08-doc-counts-gate.md

왜 필요한가 (2026-09-08 실측):
  README 가 18일간 갱신되지 않은 채 "훅 8종"(실제 12) · "pre-commit 4단 검사"(실제 15종)
  라고 말하고 있었다. 같은 오정보가 CLAUDE.md 주입 블록을 타고 12개 프로젝트에 퍼졌다.
  알려주는 장치는 이미 있었다 — R-plan-stale 이 그날 커밋 3건 전부에서 발화했고
  3번 다 무시됐다. 경고는 무시할 수 있고, 무시된다.

왜 "README 를 고쳤는가" 가 아니라 "수치가 맞는가" 를 재는가:
  전자는 한 글자만 고쳐도 통과한다. 후자는 숫자를 맞춰야만 통과하므로 우회가 없다.

왜 게이트의 차단/경고 구분을 pre-commit.sh 파싱이 아니라 선언에서 읽는가:
  `FAIL=1` 근접 파싱은 코드 구조가 바뀌면 **조용히** 틀린다. 조용히 틀린 검사는
  없는 검사보다 나쁘다 — 있다고 믿게 만들기 때문이다. 판정 근거를 코드 옆에
  `# GATE: R-xxx block|warn` 으로 명시하고 그것만 읽는다.

사용법:
  doc_counts.py render              # 마커 블록 본문을 출력 (exit 0)
  doc_counts.py check <파일...>      # 파일의 블록이 산출값과 다르면 exit 1

종료코드 계약: 0 일치 · 1 문서 불일치 · 2 판정 불가(산출 근거 없음) · 3 사용법 오류.
"잴 수 없음" 을 "문서가 틀림" 과 절대 합치지 않는다. 합치면 게이트가 꺼진 상태가
문서 오류로 둔갑하고, 반대로 0 을 사실로 보고하면 조용히 통과한다.

외부 패키지 의존 0 — 설치 실패가 곧 게이트 침묵이 되는 것을 막는다.
"""

import re
import sys
from pathlib import Path

BEGIN = "<!--===DS:COUNTS:BEGIN===-->"
END = "<!--===DS:COUNTS:END===-->"

_ROOT = Path(__file__).resolve().parent.parent.parent
_HARNESS_CONF = "presets/workflow/harness.conf"
_PRECOMMIT = "assets/hooks/pre-commit.sh"
_RUNALL = "tests/run-all.sh"


class DocCountsUnavailable(RuntimeError):
    """수치를 산출할 근거가 없다 — 0 을 내지 않고 이 예외를 던진다."""


def _read(rel):
    """저장소 루트 기준 상대 경로를 읽는다.

    없으면 빈 문자열이 아니라 **예외**다. 빈 문자열을 돌려주면 모든 수치가 조용히
    0 이 되고 "문서와 일치" 판정까지 나온다 — 이 파일은 설치기가 배포처
    `.git/hooks/` 로도 복사하는데, 그곳의 배치는 이 저장소와 달라 경로가 전부 빗나간다.
    실측(2026-09-08): 배포처에서 render 가 "훅 0종 / 게이트 0종" 을 종료코드 0 으로 냈다.
    조용한 실패 금지(core-beliefs #r5)에 정면으로 걸린다.
    """
    path = _ROOT / rel
    if not path.is_file():
        raise DocCountsUnavailable(
            f"산출 근거 파일이 없습니다: {path}\n"
            "  이 스크립트는 claude-harness-hermes 저장소 안에서만 의미가 있습니다.\n"
            "  (배포처에는 수치 블록이 없으므로 R-doc 이 호출하지 않습니다.)"
        )
    return path.read_text(encoding="utf-8")


def _parse_inline_array(name, line):
    """한 줄 형태 `NAME+=(a b c)` 를 읽는다. 여러 줄 형태면 None.

    이 형태를 조용히 삼키면 뒤따르는 무관한 줄이 항목으로 흡수된다
    (실측 2026-09-08: `SKILLS+=(one two three)` 뒤에서 `['foo','bar']` 를 얻었다).
    """
    rest = line[len(name) + 3:].strip()
    if not rest:
        return None
    if not rest.endswith(")"):
        raise DocCountsUnavailable(
            f"{name}+=( 여는 줄에 항목이 섞여 있습니다: {line.strip()!r}\n"
            "  한 줄에 항목 하나씩 쓰거나, 한 줄 배열로 닫아 주십시오."
        )
    return [t for t in rest[:-1].split() if not t.startswith("#")]


def _scan_array_body(lines, name):
    """여는 줄 다음부터 닫는 줄까지의 항목을 모은다. (항목, 닫혔는가) 를 돌려준다.

    닫는 괄호는 *줄 전체가* `)` 인 줄로만 판정한다. 항목 주석에 괄호가 들어 있어
    (`iface-guard(생성)와 ...`) 첫 `)` 로 자르면 배열이 잘린다 — 2026-09-08 에
    실제로 그렇게 잘못 세어 "훅 10 / 모듈 4" 라는 틀린 값을 얻었다.
    """
    items = []
    for line in lines:
        if line.strip() == ")":
            return items, True
        item = line.strip()
        if item and not item.startswith("#"):
            items.append(item)
    return items, False


def _bash_array(text, name):
    """`NAME+=( ... )` 배열의 항목을 뽑는다. 주석 줄과 빈 줄은 뺀다.

    찾지 못함·닫히지 않음·빈 배열은 전부 예외다. 0 을 사실로 보고하지 않는다.
    """
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if not line.startswith(f"{name}+=("):
            continue
        inline = _parse_inline_array(name, line)
        if inline is not None:
            return inline
        items, closed = _scan_array_body(lines[i + 1:], name)
        if not closed:
            raise DocCountsUnavailable(
                f"배열 {name}+=( 가 닫히지 않았습니다 (줄 전체가 ')' 인 줄이 없음)"
            )
        if not items:
            raise DocCountsUnavailable(f"배열 {name} 이 비었습니다 — 0 을 사실로 보고하지 않습니다")
        return items
    raise DocCountsUnavailable(f"배열 {name}+=( 를 찾지 못했습니다 — 소스 구조가 바뀌었습니까?")


def _gate_verdicts():
    """pre-commit 의 `# GATE:` 선언을 읽는다. 선언이 없으면 예외."""
    gates = re.findall(r"^# GATE: (R-[a-z-]+) (block|warn)$", _read(_PRECOMMIT), re.M)
    if not gates:
        raise DocCountsUnavailable("`# GATE:` 선언을 하나도 찾지 못했습니다 — 선언이 지워졌습니까?")
    return gates


def _test_names():
    """run-all.sh 를 뺀 테스트 파일 이름. 하나도 없으면 예외."""
    names = sorted(p.name for p in (_ROOT / "tests").glob("*.sh") if p.name != "run-all.sh")
    if not names:
        raise DocCountsUnavailable("tests/*.sh 를 찾지 못했습니다")
    return names


def counts():
    """문서가 주장하는 수치를 소스에서 산출한다. 이 딕셔너리가 블록의 유일한 정의."""
    conf = _read(_HARNESS_CONF)
    sources = _bash_array(conf, "HARNESS_HOOK_SOURCES")
    gates = _gate_verdicts()
    names = _test_names()
    listed = _read(_RUNALL)
    verdicts = [v for _, v in gates]
    return {
        "hooks": len([x for x in sources if x.startswith("claude-")]),
        "modules": len([x for x in sources if not x.startswith("claude-")]),
        "gates": len(gates),
        "gates_block": verdicts.count("block"),
        "gates_warn": verdicts.count("warn"),
        "skills": len(_bash_array(conf, "SKILLS")),
        "agents": len(_bash_array(conf, "AGENTS")),
        "tests": len(names),
        "tests_unlisted": len([t for t in names if t not in listed]),
    }


def render():
    """마커 블록의 본문(마커 줄 제외)을 만든다."""
    c = counts()
    orphan = ""
    if c["tests_unlisted"]:
        orphan = f" (그중 {c['tests_unlisted']}개는 run-all.sh 미등재)"
    return "\n".join([
        f"- 세션 중 실행 훅 **{c['hooks']}종** + 훅이 공유하는 판정 모듈 **{c['modules']}개**",
        f"- git pre-commit 게이트 **{c['gates']}종** — 차단 {c['gates_block']} / 경고 {c['gates_warn']}",
        f"- 스킬 **{c['skills']}종** · 에이전트 **{c['agents']}종** · 테스트 **{c['tests']}개**{orphan}",
    ])


def check(paths):
    """각 파일의 블록이 산출값과 같은지 본다. 어긋난 항목을 문자열 목록으로 돌려준다."""
    want = render()
    problems = []
    for raw in paths:
        path = Path(raw)
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        if BEGIN not in text:
            problems.append(f"{path}: 수치 블록({BEGIN})이 없습니다")
            continue
        if END not in text:
            problems.append(f"{path}: 닫는 마커({END})가 없습니다")
            continue
        got = text.split(BEGIN, 1)[1].split(END, 1)[0].strip()
        if got != want:
            problems.append(f"{path}: 수치가 소스와 다릅니다\n--- 문서 ---\n{got}\n--- 실측 ---\n{want}")
    return problems


def main(argv):
    """종료코드 계약: 0 일치 · 1 불일치 · 2 판정 불가(근거 없음) · 3 사용법 오류.

    2 를 1 과 구분하는 이유: 호출부가 "문서가 틀렸다" 와 "잴 수 없다" 를 다르게
    다뤄야 한다. 하나로 합치면 잴 수 없는 상태가 문서 오류로 둔갑한다.
    """
    try:
        if len(argv) >= 2 and argv[1] == "render":
            print(render())
            return 0
        if len(argv) >= 3 and argv[1] == "check":
            problems = check(argv[2:])
            for p in problems:
                print(p)
            return 1 if problems else 0
    except DocCountsUnavailable as exc:
        print(f"[R-doc] 수치를 산출할 수 없습니다 — {exc}", file=sys.stderr)
        return 2
    print(__doc__.strip().splitlines()[0], file=sys.stderr)
    print("usage: doc_counts.py render | check <파일...>", file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv))

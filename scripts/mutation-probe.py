#!/usr/bin/env python3
"""변이 테스트 — 테스트의 존재가 아니라 유효성을 잰다.

근거: docs/design-docs/core-beliefs.md#r-mut
스펙: docs/superpowers/specs/2026-08-24-mutation-testing-design.md

소스의 연산자를 뒤집고 기존 테스트가 그 변이를 잡아내는지 본다.
잡으면 killed, 통과하면 survived — 생존한 변이는 **그 경로를 검증하는 테스트가 없다**는 뜻이다.

커버리지로는 안 보이는 공백을 찾는다. 파일럿(2026-08-24)에서 나온 생존 변이는
`prompt = _PROMPT_TMPL.format(body=(text or "")[:_MAX])` 의 `or` → `and` 였다.
프롬프트 본문이 통째로 사라지는데 테스트는 통과했다. 그 줄은 실행되므로 커버리지는 100% 다.

왜 tokenize 인가:
  스펙 초안은 라인 단위 정규식이었다. 그러면 주석과 문자열 안의 `>=`·`and` 까지
  변이 지점으로 세고, 변이를 주입해도 의미가 바뀌지 않아 전부 생존으로 보고된다 —
  노이즈가 신호를 덮는다. tokenize 는 STRING·COMMENT 를 별도 토큰으로 분류하므로
  실코드의 연산자만 정확히 짚는다. R-cx·R-dep·R-iface 가 AST 를 쓰는 것과 같은 이유다.

왜 mutmut 이 아닌가:
  테스트 러너로 pytest 를 가정하는데 이 저장소의 테스트는 bash 다.
  그리고 하네스는 여러 프로젝트에 설치되므로 외부 패키지 요구는 곧 게이트 침묵이 된다.

게이트가 아니다. 전체 실행이 수 분이라 커밋 경로에 맞지 않고, 변이 점수의 임계를
정할 근거도 아직 없다. 생존 변이 목록은 "테스트를 추가할 지점" 목록으로 쓴다.

종료코드:
  0 = 생존 변이 있음   1 = 전부 잡힘   2 = 판정불가(대상/테스트 없음, 베이스라인 실패)
"""

import argparse
import io
import os
import signal
import subprocess
import sys
import token as token_mod
import tokenize

# 변이 규칙. 값이 None 이면 토큰을 삭제한다.
OP_MUTATIONS = {
    ">=": "<",
    "<=": ">",
    ">": "<=",
    "<": ">=",
    "==": "!=",
    "!=": "==",
}
KEYWORD_MUTATIONS = {
    "and": "or",
    "or": "and",
    "not": None,
}

BASELINE_TIMEOUT = 300  # 초. 테스트 하나가 5분을 넘으면 변이 테스트 대상이 아니다.


def _read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def _sites(source):
    """(줄, 칸, 원본토큰, 변이토큰) 목록. 문자열·주석 안은 대상이 아니다.

    tokenize 가 STRING·COMMENT 를 별도 토큰으로 주므로, OP 와 NAME 만 보면
    실코드의 연산자만 남는다. 정규식으로는 이 구분이 불가능하다.
    """
    found = []
    reader = io.StringIO(source).readline
    for tok in tokenize.generate_tokens(reader):
        if tok.type == token_mod.OP and tok.string in OP_MUTATIONS:
            found.append((tok.start[0], tok.start[1], tok.string,
                          OP_MUTATIONS[tok.string]))
        elif tok.type == token_mod.NAME and tok.string in KEYWORD_MUTATIONS:
            found.append((tok.start[0], tok.start[1], tok.string,
                          KEYWORD_MUTATIONS[tok.string]))
    return found


def _apply(source, site):
    """한 지점에만 변이를 적용한 소스를 돌려준다."""
    lineno, col, original, replacement = site
    lines = source.splitlines(keepends=True)
    line = lines[lineno - 1]
    tail = line[col + len(original):]
    if replacement is None:
        # `not` 만 지우고 뒤 공백은 그대로 둔다. `if not x` → `if  x` 는 공백이 둘이지만
        # 파이썬 의미는 같다. 공백을 지우는 분기를 두면 그 분기 자체가 동등 변이를 낳는다 —
        # `==` 를 `!=` 로 뒤집어도 결과가 같아 어떤 테스트로도 잡을 수 없다(2026-08-25 자기 실행).
        lines[lineno - 1] = line[:col] + tail
    else:
        lines[lineno - 1] = line[:col] + replacement + tail
    return "".join(lines)


class _Guard:
    """원본을 반드시 되돌린다.

    복원이 깨지면 이 도구는 소스를 망가뜨린 채 종료하는 사고가 된다.
    그래서 세 겹으로 건다 — try/finally, 시그널 핸들러, 종료 시 내용 대조.
    파일럿 구현은 정상 종료 시에만 복원했다.
    """

    def __init__(self, path, original):
        self.path = path
        self.original = original
        self._previous = {}

    def __enter__(self):
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            try:
                self._previous[sig] = signal.signal(sig, self._on_signal)
            except (ValueError, OSError):  # 메인 스레드가 아니거나 미지원 플랫폼
                pass
        return self

    def _on_signal(self, signum, frame):
        self.restore()
        sys.exit(2)

    def write(self, content):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(content)

    def restore(self):
        if _read(self.path) != self.original:
            self.write(self.original)

    def __exit__(self, exc_type, exc, tb):
        self.restore()
        for sig, handler in self._previous.items():
            try:
                signal.signal(sig, handler)
            except (ValueError, OSError):
                pass
        # 복원 검증. 되돌렸다고 믿지 않고 실제 내용을 대조한다.
        if _read(self.path) != self.original:
            print("치명적: 원본 복원에 실패했다 — %s" % self.path, file=sys.stderr)
            os._exit(2)
        return False


def _run(test_cmd):
    """테스트를 돌리고 통과 여부를 돌려준다."""
    try:
        result = subprocess.run(["bash", test_cmd], capture_output=True,
                                timeout=BASELINE_TIMEOUT)
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        return False
    except Exception:  # noqa: BLE001 — 실행 자체가 안 되면 "못 잡았다" 가 아니다
        return False


def _guess_test(target):
    """scripts/hermes_loop.py → tests/hermes-loop-test.sh"""
    stem = os.path.splitext(os.path.basename(target))[0].replace("_", "-")
    return os.path.join("tests", "%s-test.sh" % stem)


def _cmd_list(target, sites):
    for lineno, col, original, replacement in sites:
        shown = "(삭제)" if replacement is None else replacement
        print("%s:%d:%d  %s → %s" % (target, lineno, col, original, shown))
    return 0


def _resolve(args):
    """(sites, original, test_cmd) 또는 오류 종료코드(int) 를 돌려준다.

    main 에서 분리한 이유는 준비 단계의 분기가 실행 단계와 섞이면 R-cx 한도를 넘기 때문이다.
    """
    if not os.path.isfile(args.target):
        print("대상이 없다: %s" % args.target, file=sys.stderr)
        return 2

    original = _read(args.target)
    try:
        sites = _sites(original)
    except (tokenize.TokenError, SyntaxError, IndentationError) as exc:
        print("대상을 해석할 수 없다: %s (%s)" % (args.target, exc), file=sys.stderr)
        return 2

    if args.list:
        return sites, original, None

    test_cmd = args.test or _guess_test(args.target)
    if not os.path.isfile(test_cmd):
        print("테스트가 없다: %s" % test_cmd, file=sys.stderr)
        return 2

    # 베이스라인. 원본에서 이미 실패하는 테스트로는 변이 결과가 무의미하다 —
    # 모든 변이가 killed 로 나와 100% 라는 거짓 점수가 만들어진다.
    if not _run(test_cmd):
        print("베이스라인 실패: 원본 상태에서 %s 가 이미 실패한다." % test_cmd,
              file=sys.stderr)
        print("  변이 결과가 전부 killed 로 나와 거짓 점수가 된다. 테스트를 먼저 고칠 것.",
              file=sys.stderr)
        return 2
    return sites, original, test_cmd


def _report(target, sites, survived, original):
    total = len(sites)
    killed = total - len(survived)
    score = 100.0 * killed / total if total else 100.0
    print("변이 %d개 / 잡힘 %d개 / 생존 %d개 — 변이 점수 %.1f%%"
          % (total, killed, len(survived), score))
    lines = original.splitlines()
    for lineno, col, op, replacement in survived:
        shown = "(삭제)" if replacement is None else replacement
        print("  %s:%d:%d  %s → %s   ★생존★" % (target, lineno, col, op, shown))
        print("      %s" % lines[lineno - 1].strip())
    if survived:
        print("  → 생존 변이는 그 경로를 검증하는 단언이 없다는 뜻이다.")
        print("  근거: docs/design-docs/core-beliefs.md#r-mut")
    return 0 if survived else 1


def main(argv):
    parser = argparse.ArgumentParser(description="변이 테스트 도구")
    parser.add_argument("--target", required=True, help="변이를 주입할 .py")
    parser.add_argument("--test", help="검증에 쓸 테스트. 생략하면 이름 규칙으로 찾는다")
    parser.add_argument("--list", action="store_true", help="변이 지점만 출력한다")
    args = parser.parse_args(argv[1:])

    resolved = _resolve(args)
    if isinstance(resolved, int):
        return resolved
    sites, original, test_cmd = resolved

    if args.list:
        return _cmd_list(args.target, sites)

    survived = []
    with _Guard(args.target, original) as guard:
        for site in sites:
            guard.write(_apply(original, site))
            if _run(test_cmd):
                survived.append(site)
            guard.restore()

    return _report(args.target, sites, survived, original)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as exc:  # noqa: BLE001 — 계약상 판정불가는 2 다
        print("mutation-probe: %s" % exc, file=sys.stderr)
        sys.exit(2)

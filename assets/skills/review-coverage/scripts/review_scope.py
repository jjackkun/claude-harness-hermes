#!/usr/bin/env python3
"""리뷰 범위 고정 CLI — scope(볼 파일) · rule(검사 기준) · check(장부 검사).

세 명령에는 같은 방식 인자(--from/--to/--commit)와 같은 --exclude 를 준다.
종료 코드: 0 정상 · 1 장부 불완전(check) · 2 사용 오류·git 실패·규칙 파일 깨짐·장부 형식 오류.
"""
import argparse
import json
import re
import sys

# 같은 폴더 모듈은 `python3 <경로>/review_scope.py` 로 부를 때 sys.path[0] 에 있다.
from scope_check import check_ledger
from scope_git import ScopeError, collect_scope
from scope_glob import split_patterns
from scope_rules import RuleFileError, resolve_rules


def _parser():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--repo", default=".", help="git 저장소 안 아무 폴더 (기본: 현재 폴더)")
    common.add_argument("--from", dest="ref_from", help="범위 방식 시작 ref (merge-base 부터)")
    common.add_argument("--to", dest="ref_to", help="범위 방식 끝 ref (기본 HEAD)")
    common.add_argument("-c", "--commit", help="커밋 하나만")
    common.add_argument("--exclude", action="append", default=[],
                        help="뺄 패턴. 쉼표로 여러 개(중괄호 안 쉼표는 그대로), 여러 번 줘도 된다")
    common.add_argument("--json", action="store_true", help="JSON 으로 출력")
    top = argparse.ArgumentParser(prog="review_scope.py", description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = top.add_subparsers(dest="cmd", required=True)
    sub.add_parser("scope", parents=[common], help="리뷰할 파일과 뺀 파일(이유)")
    rule = sub.add_parser("rule", parents=[common], help="파일별 검사 기준(같은 기준끼리 묶음)")
    rule.add_argument("paths", nargs="*", help="생략하면 scope 의 리뷰할 파일 전부")
    rule.add_argument("--no-text", action="store_true", help="기준 본문 없이 묶음과 파일만")
    check = sub.add_parser("check", parents=[common], help="리뷰 장부 검사")
    check.add_argument("ledger", help="장부 JSON 파일 경로, - 이면 표준입력")
    return top


def _cmd_scope(args, scope):
    if args.json:
        print(json.dumps(scope, ensure_ascii=False, indent=2))
        return 0
    span = f"{scope['base'][:9]}..{scope['target'][:9]}" if scope["target"] else scope["base"][:9]
    print(f"방식: {scope['mode']} ({span}) · 저장소 {scope['root']}")
    print(f"리뷰할 파일 {len(scope['reviewable'])}개")
    for e in scope["reviewable"]:
        print(f"  {e['status']}  {e['path']}  +{e['added']} -{e['deleted']}")
    print(f"뺀 파일 {len(scope['excluded'])}개")
    for e in scope["excluded"]:
        print(f"  {e['path']} — {e['reason']}")
    return 0


def _cmd_rule(args, scope):
    groups = resolve_rules(scope["root"], args.paths or [e["path"] for e in scope["reviewable"]])
    if args.no_text:
        groups = [{k: v for k, v in g.items() if k != "text"} for g in groups]
    if args.json:
        print(json.dumps(groups, ensure_ascii=False, indent=2))
        return 0
    for g in groups:
        print(f"=== 기준 {g['rule']} — 파일 {len(g['files'])}개")
        print("\n".join(f"  {p}" for p in g["files"]))
        print(("\n" + g["text"] + "\n") if "text" in g else "")
    return 0


def _read_ledger(source):
    if source == "-":
        return json.loads(sys.stdin.buffer.read().decode("utf-8"))
    with open(source, encoding="utf-8") as fh:
        return json.load(fh)


def _cmd_check(args, scope):
    errors, warnings, summary = check_ledger(scope, _read_ledger(args.ledger))
    if args.json:
        print(json.dumps({"ok": not errors, "errors": errors, "warnings": warnings, "summary": summary},
                         ensure_ascii=False, indent=2))
        return 1 if errors else 0
    for line in [f"✗ {e}" for e in errors] + [f"! {w}" for w in warnings]:
        print(line)
    skipped = summary.pop("skipped", [])
    print("요약: " + " · ".join(f"{k}={v}" for k, v in summary.items()))
    if skipped:
        print("건너뜀: " + ", ".join(skipped))
    print("결과: 통과" if not errors else f"결과: 실패 {len(errors)}건")
    return 1 if errors else 0


COMMANDS = {"scope": _cmd_scope, "rule": _cmd_rule, "check": _cmd_check}


def main(argv=None):
    args = _parser().parse_args(argv)
    try:
        scope = collect_scope(args.repo, args.ref_from, args.ref_to, args.commit, split_patterns(args.exclude))
        return COMMANDS[args.cmd](args, scope)
    except (ScopeError, RuleFileError, OSError, ValueError, re.error) as err:
        print(f"review_scope: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

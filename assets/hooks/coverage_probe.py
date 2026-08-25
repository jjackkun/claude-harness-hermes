#!/usr/bin/env python3
"""표준 라이브러리만으로 파이썬 줄 커버리지를 측정한다.

근거: docs/design-docs/core-beliefs.md#r-cov
스펙: docs/superpowers/specs/2026-08-24-coverage-enforcement-design.md

왜 coverage.py 를 쓰지 않는가:
  하네스는 여러 프로젝트에 설치되는 도구다. 각 프로젝트에 외부 패키지 설치를 요구하면
  설치 실패가 곧 게이트 침묵이 된다 — R-test 가 실제로 그 상태였다.
  전역 설치는 있는 머신과 없는 머신이 다른 결과를 내고, 프로젝트별 venv 는 하네스가
  프로젝트의 런타임 의존성 관리를 떠맡는 것이다. 선택지를 고르는 대신 의존을 없앤다.

왜 하위 프로세스까지 봐야 하는가:
  이 저장소의 검증 수단은 파이썬을 자식 프로세스로 띄우는 bash 통합 테스트다.
  부모만 추적하면 전부 0% 로 나온다. PYTHONPATH 에 sitecustomize.py 를 두면
  인터프리터가 뜰 때마다 추적이 붙는다 — coverage.py 의 COVERAGE_PROCESS_START 와
  같은 수법이며, 역시 표준 라이브러리만 쓴다.

속도: 순수 파이썬 추적이라 약 5배 느리다(실측 0.09초 → 0.47초).
  매 커밋이 아니라 커버리지를 잴 때만 켜는 경로이므로 감당 범위다.

사용법:
  coverage_probe.py run --data <dir> --scope <prefix> -- <command>...
      command 를 추적하며 실행하고 원시 데이터를 <dir> 에 쌓는다.
  coverage_probe.py report --data <dir> --scope <prefix> [--json]
      파일별 실행 줄/전체 줄/비율을 출력한다.
  coverage_probe.py uncovered --data <dir> <path>...
      해당 경로 중 **한 줄도 실행되지 않은** 파일만 출력한다.
      0=해당 있음 1=없음 2=데이터 없음.

종료코드 계약은 plan_state.py 와 같은 규칙을 따른다 — 판정불가는 2 다.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

# 추적 부트스트랩. 하위 인터프리터가 뜰 때 site 모듈이 자동으로 import 한다.
# 여기서 재귀 방지 플래그를 걸지 않으면 추적 대상이 띄우는 파이썬이 또 추적을 시작한다.
SITECUSTOMIZE = '''\
import atexit, os, sys, trace

_dir = os.environ.get("HARNESS_COV_DATA")
if _dir:
    _t = trace.Trace(count=1, trace=0, ignoredirs=[sys.prefix, sys.exec_prefix])
    sys.settrace(_t.globaltrace)

    def _dump(tracer=_t, out=_dir):
        sys.settrace(None)
        counts = {}
        for (path, lineno), hits in tracer.results().counts.items():
            counts.setdefault(path, {})[str(lineno)] = hits
        import json, tempfile
        fd, name = tempfile.mkstemp(dir=out, suffix=".cov")
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(counts, handle)

    atexit.register(_dump)
'''


def _executable_lines(path):
    """실행될 수 있는 줄 번호 집합. 주석·빈 줄·docstring 은 세지 않는다.

    trace 는 실행된 줄만 알려주므로 분모는 별도로 구해야 한다. ast 로 구한다 —
    정규식으로는 여러 줄 문자열 안의 코드처럼 보이는 텍스트를 걸러내지 못한다.
    """
    import ast
    try:
        with open(path, encoding="utf-8") as handle:
            tree = ast.parse(handle.read())
    except Exception:  # noqa: BLE001 — 문법 오류는 다른 게이트 관할
        return set()

    lines = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.stmt):
            continue
        # 순수 문자열 문장(docstring)은 실행 줄로 세지 않는다. 세면 docstring 이 긴
        # 파일일수록 커버리지가 낮게 나와, 문서를 잘 쓴 파일이 벌을 받는다.
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) \
                and isinstance(node.value.value, str):
            continue
        lines.add(node.lineno)
    return lines


def _load(data_dir):
    """원시 데이터 조각을 합쳐 {절대경로: {줄번호}} 로 돌려준다."""
    merged = {}
    if not os.path.isdir(data_dir):
        return merged
    for name in sorted(os.listdir(data_dir)):
        if not name.endswith(".cov"):
            continue
        try:
            with open(os.path.join(data_dir, name), encoding="utf-8") as handle:
                chunk = json.load(handle)
        except Exception:  # noqa: BLE001 — 조각 하나가 깨져도 나머지는 쓴다
            continue
        for path, hits in chunk.items():
            merged.setdefault(os.path.realpath(path), set()).update(
                int(line) for line in hits)
    return merged


def _tally(data_dir, scope, root):
    """[(상대경로, 실행줄수, 전체줄수)] 를 돌려준다. scope 안의 .py 전부가 대상이다.

    한 번도 실행되지 않은 파일이 목록에서 빠지면 안 된다 — 그 파일이야말로 찾는 대상이다.
    그래서 추적 데이터가 아니라 디스크의 파일 목록을 기준으로 순회한다.
    """
    hit = _load(data_dir)
    rows = []
    base = os.path.join(root, scope)
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in sorted(filenames):
            if not name.endswith(".py"):
                continue
            full = os.path.realpath(os.path.join(dirpath, name))
            total = _executable_lines(full)
            if not total:
                continue
            covered = len(total & hit.get(full, set()))
            rows.append((os.path.relpath(full, root), covered, len(total)))
    return rows


def _cmd_run(args):
    if "--" not in args:
        print("usage: coverage_probe.py run --data <dir> -- <command>...",
              file=sys.stderr)
        return 2
    split = args.index("--")
    opts, command = args[:split], args[split + 1:]
    if not command:
        print("실행할 명령이 없습니다.", file=sys.stderr)
        return 2

    data_dir = os.path.abspath(_opt(opts, "--data", "coverage-data"))
    os.makedirs(data_dir, exist_ok=True)

    boot = tempfile.mkdtemp(prefix="harness-cov-")
    with open(os.path.join(boot, "sitecustomize.py"), "w", encoding="utf-8") as handle:
        handle.write(SITECUSTOMIZE)

    env = dict(os.environ)
    env["HARNESS_COV_DATA"] = data_dir
    env["PYTHONPATH"] = os.pathsep.join(
        [boot] + ([env["PYTHONPATH"]] if env.get("PYTHONPATH") else []))
    try:
        return subprocess.call(command, env=env)
    finally:
        # 부트스트랩 디렉터리를 남기면 측정할 때마다 /tmp 에 쌓인다.
        shutil.rmtree(boot, ignore_errors=True)


def _cmd_report(args):
    root = os.getcwd()
    rows = _tally(os.path.abspath(_opt(args, "--data", "coverage-data")),
                  _opt(args, "--scope", ""), root)
    if "--json" in args:
        print(json.dumps([{"path": p, "covered": c, "total": t} for p, c, t in rows],
                         ensure_ascii=False))
        return 0
    for path, covered, total in sorted(rows, key=lambda r: r[1] / r[2]):
        print("%5.1f%%  %4d/%-4d  %s" % (100.0 * covered / total, covered, total, path))
    if rows:
        hit = sum(r[1] for r in rows)
        allv = sum(r[2] for r in rows)
        print("%5.1f%%  %4d/%-4d  (전체 %d개 파일)" % (
            100.0 * hit / allv, hit, allv, len(rows)))
    return 0


def _cmd_uncovered(args):
    data_dir = os.path.abspath(_opt(args, "--data", "coverage-data"))
    paths = [a for a in args if not a.startswith("--") and a != data_dir]
    if not os.path.isdir(data_dir) or not os.listdir(data_dir):
        return 2

    hit = _load(data_dir)
    found = False
    for path in paths:
        full = os.path.realpath(path)
        if not os.path.isfile(full) or not _executable_lines(full):
            continue
        if not hit.get(full):
            print(path)
            found = True
    return 0 if found else 1


def _cmd_baseline(args):
    """측정 결과를 .covbaseline 형식으로 stdout 에 낸다.

    커밋 훅은 스위트를 돌릴 수 없다(전체 실행에 수 분이 걸린다). 그래서 측정은 사람이
    돌리고 결과를 파일로 남긴다 — `.cxbaseline` 과 같은 방식이다.
    """
    root = os.getcwd()
    data_dir = os.path.abspath(_opt(args, "--data", "coverage-data"))
    # 측정 데이터가 없으면 _tally 는 모든 파일을 0/N 으로 돌려준다. 그대로 기준선을
    # 만들면 게이트가 저장소 전체를 "테스트 없음" 으로 신고한다 — 측정하지 않은 것과
    # 커버리지가 0 인 것은 다르다. 여기서 끊는다.
    if not os.path.isdir(data_dir) or not [
            n for n in os.listdir(data_dir) if n.endswith(".cov")]:
        print("측정 데이터가 없습니다: %s" % data_dir, file=sys.stderr)
        return 2
    rows = []
    for scope in _opt(args, "--scope", "").split(","):
        rows.extend(_tally(data_dir, scope.strip(), root))
    if not rows:
        print("측정 데이터가 없습니다.", file=sys.stderr)
        return 2

    print("# R-cov 커버리지 스냅샷. 값은 <실행줄>/<전체줄>.")
    print("# 갱신 방법 (스위트 전체 실행이 필요하므로 커밋 훅이 아니라 사람이 돌린다):")
    print("#   python3 assets/hooks/coverage_probe.py run --data .covdata -- \\")
    print("#     bash tests/run-all.sh")
    print("#   python3 assets/hooks/coverage_probe.py baseline --data .covdata \\")
    print("#     --scope assets/hooks,scripts > .covbaseline")
    for path, covered, total in sorted(rows):
        print("%s %d/%d" % (path, covered, total))
    return 0


def _opt(args, flag, default):
    return args[args.index(flag) + 1] if flag in args else default


COMMANDS = {"run": _cmd_run, "report": _cmd_report,
            "uncovered": _cmd_uncovered, "baseline": _cmd_baseline}


def main(argv):
    command = argv[1] if len(argv) >= 2 else ""
    if command not in COMMANDS:
        print("usage: coverage_probe.py {%s} ..." % "|".join(COMMANDS), file=sys.stderr)
        return 2
    return COMMANDS[command](argv[2:])


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as exc:  # noqa: BLE001 — 계약상 판정불가는 2 다
        print("coverage_probe: %s" % exc, file=sys.stderr)
        sys.exit(2)

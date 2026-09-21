#!/usr/bin/env python3
"""R-config — `.claude/` 설정이 연 위험 표면을 센다. 코드가 아니라 **설정**이 대상이다.

`check-secrets.py`(P9)는 코드 속 값을 본다. 이 판정기는 그 옆자리다 — 권한 allowlist·훅 명령·MCP 서버·
CLAUDE.md 가 무엇을 허용했는지. 모델 호출은 없다(R3). 표준 라이브러리만 쓴다(.deprc tier 0).

네 갈래:
  unscoped    도구 전체를 연 allow (`Bash` · `Bash(*)` · `*`)
  destructive 파괴적 명령을 **와일드카드와 함께** 허용 (`Bash(rm:*)` · `Bash(docker run *)`).
              구체 명령 허용(`Bash(rm -f .claude/.review-dirty)`)은 세지 않는다 — 2026-09-21 실측에서 12곳의
              그런 항목 166건이 전부 구체 명령이었고, 인자 무관 형식은 0건이었다. 전부 경고하면 소음만 남는다.
  hook        훅 command 가 저장소 밖 절대경로이거나 네트워크에서 받아 실행(`curl … | sh`)
  injection   CLAUDE.md·규칙 문서의 고전 인젝션 문구. 주석 속 평범한 낱말(`<!--… run …-->`)은 세지 않는다 —
              소박한 정규식이 공장 문서에서 곧바로 오탐을 냈다(같은 날 실측).

기준선 `.claude-config-baseline` 은 도입 시점에 이미 있던 항목을 잠근다 — 새 항목만 보고하고, 기준선은 줄어들기만 한다
(R-cx·R-design-cover 와 같은 방식). 이미 있는 것을 한 번에 지울 수는 없지만 느는 것은 막을 수 있다.

사용:
  claude_config_scan.py --root DIR             새 항목만 한 줄씩 출력 (없으면 0줄)
  claude_config_scan.py --root DIR --baseline  현재 항목 전부를 기준선 형식으로 출력(사람이 파일로 저장)
"""
import json
import os
import re
import sys

BASELINE = ".claude-config-baseline"
SETTINGS = ("settings.json", "settings.local.json")
DOC_FILES = ("CLAUDE.md", "AGENTS.md")
DOC_DIRS = (os.path.join(".claude", "rules"), os.path.join(".claude", "skills"))

# 도구 전체를 여는 꼴. `Bash(ls:*)` 처럼 범위가 있으면 여기 걸리지 않는다.
UNSCOPED_RE = re.compile(r"^(?:\*|[A-Z][A-Za-z]*(?:\(\s*\*?\s*\))?)$")
# 인자 무관 허용이 위험한 명령. 목록 밖은 보지 않는다 — 넓히면 소음이 된다.
DESTRUCTIVE = ("rm", "sudo", "chmod", "chown", "dd", "mkfs", "curl", "wget", "docker",
               "git push", "npm publish", "gh release")
NETWORK_EXEC_RE = re.compile(r"(curl|wget)[^|]*\|\s*(ba)?sh|eval\s+\$\(")
INJECTION_RE = re.compile(
    r"(?i)ignore\s+(?:all\s+)?(?:previous|prior|above)\s+instructions"
    r"|disregard\s+(?:all\s+)?(?:previous|prior|above)"
    r"|(?:이전|앞의)\s*(?:지시|규칙)\w*\s*(?:은|는)?\s*(?:무시|잊)"
    r"|new\s+instructions\s*:")


def _read_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:  # noqa: BLE001 — 깨진 설정은 이 판정기의 대상이 아니다
        return None


def _destructive_wildcard(inner, cmd):
    """파괴적 명령이 **인자 무관**(`rm:*`)이거나 인자에 와일드카드를 품었나(`docker run *`).

    구체 명령(`rm -f .claude/.review-dirty`)은 좁은 허용이라 세지 않는다 — 그것까지 경고하면
    게이트가 소음이 되고, 소음이 된 게이트는 꺼진다.
    """
    if inner == cmd or inner.startswith(cmd + ":"):
        return True
    return inner.startswith(cmd + " ") and "*" in inner


def _allow_findings(root):
    out = []
    for name in SETTINGS:
        data = _read_json(os.path.join(root, ".claude", name))
        if not isinstance(data, dict):
            continue
        for entry in (data.get("permissions") or {}).get("allow", []):
            entry = str(entry).strip()
            if UNSCOPED_RE.match(entry):
                out.append("unscoped:%s:%s" % (name, entry))
                continue
            inner = entry[entry.find("(") + 1:entry.rfind(")")] if "(" in entry else ""
            inner = inner.strip()
            if any(_destructive_wildcard(inner, cmd) for cmd in DESTRUCTIVE):
                out.append("destructive:%s:%s" % (name, entry))
    return out


def _hook_findings(root):
    out = []
    for name in SETTINGS:
        data = _read_json(os.path.join(root, ".claude", name))
        if not isinstance(data, dict):
            continue
        for group in (data.get("hooks") or {}).values():
            for entry in group if isinstance(group, list) else []:
                for hook in entry.get("hooks", []):
                    cmd = str(hook.get("command", ""))
                    outside = cmd.startswith("/") and "${CLAUDE_PROJECT_DIR}" not in cmd
                    if outside or NETWORK_EXEC_RE.search(cmd):
                        out.append("hook:%s:%s" % (name, cmd[:80]))
    return out


def _mcp_findings(root):
    data = _read_json(os.path.join(root, ".mcp.json"))
    if not isinstance(data, dict):
        return []
    out = []
    for srv, conf in (data.get("mcpServers") or {}).items():
        blob = json.dumps(conf, ensure_ascii=False)
        if "http://" in blob or "https://" in blob:
            out.append("mcp:%s:원격 출처" % srv)
    return out


def _doc_paths(root):
    for name in DOC_FILES:
        path = os.path.join(root, name)
        if os.path.isfile(path):
            yield path
    for rel in DOC_DIRS:
        for dirpath, _dirs, files in os.walk(os.path.join(root, rel)):
            for f in files:
                if f.endswith(".md"):
                    yield os.path.join(dirpath, f)


def _injection_findings(root):
    out = []
    for path in _doc_paths(root):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        if INJECTION_RE.search(text):
            out.append("injection:%s" % os.path.relpath(path, root))
    return out


def findings(root="."):
    return sorted(set(_allow_findings(root) + _hook_findings(root)
                      + _mcp_findings(root) + _injection_findings(root)))


def baseline(root="."):
    path = os.path.join(root, BASELINE)
    if not os.path.isfile(path):
        return set()
    with open(path, encoding="utf-8") as fh:
        return {line.strip() for line in fh if line.strip() and not line.startswith("#")}


def main(argv):
    root = argv[argv.index("--root") + 1] if "--root" in argv else "."
    found = findings(root)
    if "--baseline" in argv:
        print("# R-config 기준선 — 도입 시점(2026-09-21)에 이미 있던 항목. 줄어들기만 한다.")
        print("# 갈래: unscoped(도구 전체) · destructive(파괴적 명령 인자 무관) · hook(밖 경로·네트워크 실행) · mcp · injection")
        if found:
            print("\n".join(found))
        return 0
    new = [f for f in found if f not in baseline(root)]
    if new:
        print("\n".join(new))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception as exc:  # noqa: BLE001 — 판정 불가는 2
        print("claude_config_scan: %s" % exc, file=sys.stderr)
        sys.exit(2)

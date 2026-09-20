#!/usr/bin/env python3
"""ECC(everything-claude-code, MIT) `agents/*.md` → 우리 역할 템플릿 변환기 (계획 2026-09-20-role-templates 목표 1).

  python3 scripts/hermes-template-import.py --ecc <ecc 체크아웃> [--out assets/templates/agent/roles] [--only name,name]

규칙 변환, 모델 호출 0, 멱등(같은 입력 → 같은 출력). `## Prompt Defense Baseline` 의 불릿은 버리고(우리 가드가 그 역할),
그 절 안의 산문(“You are …”)은 역할 문단으로 남긴다. 나머지 절은 매핑표로 책임 경계·원칙·도구에 넣고, 제목은 한 단계 내린다.
"""
import argparse
import os
import re
import subprocess
import sys

DEFENSE = "## Prompt Defense Baseline"
TO_SCOPE = {"your role", "core responsibilities", "review priorities", "responsibilities", "scope", "when to use",
            "focus areas", "what you do", "role"}
TO_TOOLS = {"diagnostic commands", "reference", "tools", "commands", "resources", "references", "useful commands"}
HINTS = (("reviewer", "QA"), ("security", "QA"), ("tdd", "QA"), ("e2e", "QA"), ("test", "QA"), ("evaluator", "QA"),
         ("build-resolver", "백엔드"), ("resolver", "백엔드"), ("performance", "백엔드"), ("database", "백엔드"),
         ("network", "백엔드"), ("homelab", "백엔드"), ("architect", "기획"), ("planner", "기획"), ("spec", "기획"),
         ("doc", "기획"), ("explorer", "기획"), ("simplifier", "백엔드"), ("refactor", "백엔드"),
         ("a11y", "디자인"), ("design", "디자인"), ("seo", "영업"), ("marketing", "영업"))


def _frontmatter(text: str):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}, text
    fm = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip()
    return fm, text[m.end():]


def _sections(body: str) -> list:
    """[(제목 or None, 본문)] — 첫 '## ' 앞은 제목 None."""
    parts = re.split(r"^(## .+)$", body, flags=re.M)
    out = [(None, parts[0])]
    for i in range(1, len(parts), 2):
        out.append((parts[i][3:].strip(), parts[i + 1] if i + 1 < len(parts) else ""))
    return out


def _demote(text: str) -> str:
    return re.sub(r"^(#{2,5}) ", lambda m: "#" + m.group(1) + " ", text, flags=re.M)


def _hint(name: str) -> str:
    low = name.lower()
    for key, disc in HINTS:
        if key in low:
            return disc
    return "general"


def _defense_prose(content: str) -> str:
    """방어 절에서 불릿(우리 가드가 맡는 지시)을 버리고 산문("You are …")만 남긴다."""
    return "\n".join(ln for ln in content.splitlines() if ln.strip() and not ln.lstrip().startswith("- ")).strip()


def _bucket(body: str) -> dict:
    """절을 역할 문단(lead)·책임 경계(scope)·원칙(principles)·도구(tools) 네 통으로 나눈다."""
    b = {"lead": [], "scope": [], "principles": [], "tools": []}
    for title, content in _sections(body):
        content = content.strip("\n")
        if title is None or title == DEFENSE[3:]:
            prose = content.strip() if title is None else _defense_prose(content)
            if prose:
                b["lead"].append(prose)
            continue
        key = title.lower()
        block = f"### {title}\n{_demote(content).strip()}\n"
        if key in TO_SCOPE or key.startswith(("scope", "when ")):
            b["scope"].append(block)
        elif key in TO_TOOLS:
            b["tools"].append(block)
        else:
            b["principles"].append(block)
    return b


def convert(text: str, source_path: str, commit: str) -> str:
    fm, body = _frontmatter(text)
    name = fm.get("name") or os.path.basename(source_path)[:-3]
    b = _bucket(body)
    desc, tools, model = fm.get("description", ""), fm.get("tools", ""), fm.get("model", "")
    tools_line = f"- tools: {tools}" + (f" · model: {model}" if model else "")
    scope = "\n".join(b["scope"]) or "(원문에 역할 범위 절 없음 — 역할 문단을 따른다)\n"
    principles = "\n".join(b["principles"]) or "(원문에 절차 절 없음)\n"
    return (f"---\nname: {name}\norigin: ECC\nsource_commit: {commit}\nsource_path: {source_path}\n"
            f"description: {desc}\ntools: {tools}\nmodel: {model}\ndiscipline_hint: {_hint(name)}\n---\n"
            f"# {name} (역할 템플릿)\n\n"
            f"> 출처 ECC@{commit} `{source_path}` (MIT). 규칙 변환 — 본문은 영어 원문. `hire --template {name}` 이 SOUL 초안에 넣는다.\n\n"
            f"## 역할\n{desc}\n\n" + "\n\n".join(b["lead"]) + "\n\n"
            f"## 책임 경계\n{scope}\n## 원칙\n{principles}\n## 도구\n{tools_line}\n"
            + "\n".join(b["tools"])).rstrip("\n") + "\n"


def _source_commit(ecc: str, given: str) -> str:
    if given:
        return given
    try:
        out = subprocess.run(["git", "-C", ecc, "rev-parse", "--short", "HEAD"],
                             capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        out = ""
    return out or "unknown"


def _convert_dir(src: str, out_dir: str, only: set, commit: str) -> int:
    os.makedirs(out_dir, exist_ok=True)
    n = 0
    for fname in sorted(os.listdir(src)):
        if not fname.endswith(".md") or (only and fname[:-3] not in only):
            continue
        with open(os.path.join(src, fname), encoding="utf-8") as fh:
            converted = convert(fh.read(), f"agents/{fname}", commit)
        with open(os.path.join(out_dir, fname), "w", encoding="utf-8") as fh:
            fh.write(converted)
        n += 1
    return n


def main() -> int:
    ap = argparse.ArgumentParser(description="ECC agents → 역할 템플릿")
    ap.add_argument("--ecc", required=True, help="ECC 체크아웃 경로")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                                  "assets", "templates", "agent", "roles"))
    ap.add_argument("--only", default="", help="쉼표로 이름 제한")
    ap.add_argument("--commit", default="", help="출처 커밋(기본: git rev-parse --short)")
    args = ap.parse_args()
    src = os.path.join(args.ecc, "agents")
    if not os.path.isdir(src):
        print(f"[template-import] agents/ 없음: {src}", file=sys.stderr)
        return 2
    commit = _source_commit(args.ecc, args.commit)
    only = {n.strip() for n in args.only.split(",") if n.strip()}
    n = _convert_dir(src, args.out, only, commit)
    print(f"[template-import] {n}개 → {args.out} (ECC@{commit})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

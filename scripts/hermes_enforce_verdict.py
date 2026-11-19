#!/usr/bin/env python3
"""결정화 판정 해석 — 모델이 낸 `ENFORCE:` 한 줄을 읽어 covered · checkable · prose 로 가른다.

왜: 결정화가 반복 실수를 글로만 굳혀, 게이트가 이미 막는 것까지 매 턴 글로 주입됐다.
판정은 결정화와 같은 모델 호출에서 받는다(호출 수 그대로). 해석·강등만 여기서 한다 — 파일·DB 쓰기 없음.
계획: docs/exec-plans/active/2026-11-19-crystallize-check-first-plan.md

공개: gate_names · pre_commit_path · split_verdict · ENFORCE_RULE
"""

import os
import re
import subprocess

# covered 는 "이미 막는다" 라서 커밋을 실제로 차단하는 게이트만 인정한다. 그 목록은 설치된 pre-commit 첫머리
# `#   차단 12 — R-size R-fmt …` 한 줄이 정본이다. 문서 속 R- 이름을 다 모으면 측정·경고 훅(R-out·R-mut)까지 들어가
# 모델이 그 이름으로 covered 를 내면 스킬이 영영 안 생긴다(2026-11-19 리뷰 MEDIUM).
_BLOCK_LINE = re.compile(r"^#\s*차단\s*\d+\s*—\s*(.+)$", re.MULTILINE)
_GATE_NAME = re.compile(r"\bR-[a-z][a-z0-9-]*[a-z0-9]")
# 판정 줄 꾸밈(``` ` ```·`**`)과 뒤에 붙는 설명을 허용한다. 실측(2026-11-19 haiku 47회): 47 중 9가 이 꾸밈 때문에 prose 로 떨어졌다.
_VERDICT_LINE = re.compile(r"^[\s`*]*ENFORCE:\s*(.*?)\s*$")
_VERDICT_HEAD = re.compile(r"^[`*\s]*(covered|checkable|prose)\b[`*\s]*(?::[`*\s]*([A-Za-z][A-Za-z0-9-]*))?", re.IGNORECASE)
_TRAILING_FENCE = re.compile(r"\n```\s*$")
_KINDS = ("hook", "gate", "test")

# 두 결정화 프롬프트가 같이 쓰는 판정 지시. {gates} 는 gate_names 가 pre-commit 에서 뽑은 차단 게이트.
ENFORCE_RULE = """\
검사 판정 (본문 맨 끝에 한 줄 추가):
이 실수를 글이 아니라 기계로 막을 수 있는지 판정해 마지막 줄에 정확히 아래 셋 중 하나를 쓰세요.
- `ENFORCE: covered:<게이트 이름>` — 아래 목록의 게이트가 **이미** 이 실수를 막는다(같은 실수를 커밋 전에 잡는다).
- `ENFORCE: checkable:<hook|gate|test>` — 아직 막는 게이트는 없지만 훅·커밋 게이트·시험으로 결정적으로 잡을 수 있다.
- `ENFORCE: prose` — 사람·모델의 판단이 필요해 기계로 잡을 수 없다.
주의: "게이트에 막힌 뒤 어떻게 통과하나" 를 적은 규칙은 covered 가 아니라 prose 다.
커밋을 막는 게이트: {gates}
"""


def pre_commit_path(project_dir: str) -> str:
    """그 프로젝트의 설치된 pre-commit 경로. worktree 에서도 공용 hooks 를 가리킨다."""
    try:
        out = subprocess.run(["git", "-C", project_dir, "rev-parse", "--path-format=absolute",
                              "--git-path", "hooks/pre-commit"],
                             capture_output=True, text=True, timeout=10)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.join(project_dir, ".git", "hooks", "pre-commit")


def gate_names(pre_commit: str) -> list:
    """pre-commit 첫머리 `차단 N —` 줄의 게이트 이름. 파일·줄이 없으면 빈 목록(→ covered 는 모두 prose 로 강등)."""
    try:
        with open(pre_commit, encoding="utf-8") as fh:
            m = _BLOCK_LINE.search(fh.read(4096))
    except OSError:
        return []
    return list(dict.fromkeys(_GATE_NAME.findall(m.group(1)))) if m else []


def _classify(raw: str, gates: list) -> tuple:
    """(verdict, detail, note). 앞머리 `종류:값` 만 읽고 뒤 설명은 버린다. 목록 밖 게이트·틀린 종류는 prose 로 강등.
    게이트 이름은 대소문자·백틱 무시."""
    m = _VERDICT_HEAD.match(raw)
    if not m:
        return "prose", raw, "bad-format"
    head, detail = m.group(1).lower(), (m.group(2) or "")
    if head == "covered":
        canon = next((g for g in gates if g.lower() == detail.lower()), None)
        return ("covered", canon, "") if canon else ("prose", detail, "unknown-gate")
    if head == "checkable":
        return ("checkable", detail.lower(), "") if detail.lower() in _KINDS else ("prose", detail, "bad-kind")
    return "prose", "", ""


def _verdict_index(lines: list):
    """판정 줄 위치 — 마지막·첫 비어 있지 않은 줄을 먼저 본다. 둘 다 아니면 본문의 마지막 판정 줄
    (모델이 판정 뒤에 설명 문단을 붙인 경우, 실측 47 중 3). 끝줄이 판정이면 중간 예시 줄은 건드리지 않는다."""
    filled = [i for i, line in enumerate(lines) if line.strip()]
    for i in (filled[-1:] + filled[:1]) if filled else []:
        if _VERDICT_LINE.match(lines[i]):
            return i
    hits = [i for i, line in enumerate(lines) if _VERDICT_LINE.match(line)]
    return hits[-1] if hits else None


def split_verdict(text: str, gates: list) -> tuple:
    """(verdict, detail, note, body). 판정 줄은 body 에서 뗀다. 줄이 없으면 prose · note=missing."""
    lines = (text or "").splitlines()
    idx = _verdict_index(lines)
    if idx is None:
        return "prose", "", "missing", text or ""
    raw = _VERDICT_LINE.match(lines[idx]).group(1)
    body = "\n".join(lines[:idx] + lines[idx + 1:]).strip("\n")
    # 모델이 ```markdown … ``` 로 감싸고 그 뒤에 판정 줄을 쓰면 닫는 펜스가 남는다(생성부는 마지막 줄만 벗긴다).
    body = _TRAILING_FENCE.sub("", body)
    verdict, detail, note = _classify(raw, gates)
    return verdict, detail, note, body

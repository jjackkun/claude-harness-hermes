#!/usr/bin/env python3
"""매칭이 없을 때 claude -p 로 뉘앙스 기반 후보를 찾는다.

hermes-search.py 에서 분리했다. 키워드 매칭(그 파일의 책임)과 서브세션을 띄우는
폴백(이 파일의 책임)은 실패 양상도 비용도 다르다 — 폴백은 30초 타임아웃짜리
프로세스를 띄우므로 훅 경로에서는 `--no-fallback` 으로 꺼 둔다.

이 모듈은 스킬 목록을 모으고 claude 에게 물어보기만 한다. DB 도 원장도 건드리지 않는다.
"""

import os
import shutil
import subprocess
import sys

# 단독 임포트(시험·다른 스크립트)에서도 동작하도록 스스로 경로를 세운다 —
# 부르는 쪽이 sys.path 를 먼저 건드려 줬다는 전제에 기대지 않는다.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from hermes_skills import iter_skill_files  # noqa: E402  (스킬 파일 순회 공유 헬퍼)


def _log(msg: str) -> None:
    """폴백 경로의 진단은 stderr 로만 낸다 — stdout 은 프롬프트에 붙는다."""
    print(f"[hermes-search-fallback] {msg}", file=sys.stderr)


def _extract_description(skill_md: str) -> str:
    """SKILL.md frontmatter 의 description, 없으면 첫 제목 줄을 반환한다."""
    title = ""
    try:
        with open(skill_md, "r", encoding="utf-8") as f:
            in_frontmatter = False
            for line in f:
                line = line.rstrip()
                if line == "---":
                    in_frontmatter = not in_frontmatter
                    continue
                if in_frontmatter and line.startswith("description:"):
                    return line[len("description:"):].strip()
                if not title and line.startswith("# "):
                    title = line[2:].strip()
    except Exception as e:
        _log(f"description 추출 실패({skill_md}): {e}")
    return title


def collect_all_skills(skills_dirs: list) -> list:
    """모든 스킬 디렉토리에서 스킬 이름과 description을 수집한다.

    M4 — 평면 .md 스킬도 포함 (description 없으면 제목 줄 사용).
    """
    skills = []
    seen = set()
    for skills_dir in skills_dirs:
        if not os.path.isdir(skills_dir):
            continue
        for name, skill_md in iter_skill_files(skills_dir):
            if name in seen:
                continue
            description = _extract_description(skill_md)
            if description:
                seen.add(name)
                skills.append({"name": name, "path": skill_md, "description": description})
    return skills


def _ask_claude(prompt: str) -> str:
    """claude -p 를 한 번 호출하고 stdout 을 돌려준다. 실패는 빈 문자열.

    호출 자체의 실패 갈래(미설치·비정상 종료·타임아웃·기타)를 여기서 모두 흡수해
    haiku_fallback 이 "물어보고 고르기" 만 하도록 남긴다.
    """
    try:
        result = subprocess.run(
            ["claude", "-p", prompt],
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "HERMES_DISABLED": "1"},
        )
    except subprocess.TimeoutExpired:
        _log("claude -p timeout")
        return ""
    except Exception as e:
        _log(f"claude fallback 오류: {e}")
        return ""

    if result.returncode != 0:
        _log(f"claude -p 실패: rc={result.returncode} stderr={(result.stderr or '').strip()[-300:]}")
        return ""
    return (result.stdout or "").strip()


def haiku_fallback(query: str, skills_dirs: list, max_results: int) -> list:
    """FTS5 미스 시 claude -p 로 뉘앙스 기반 스킬을 찾는다."""
    if not shutil.which("claude"):
        return []

    skills = collect_all_skills(skills_dirs)
    if not skills:
        return []

    skill_list = "\n".join([f"- {s['name']}: {s['description']}" for s in skills])
    text = _ask_claude(
        f'사용자 메시지: "{query}"\n\n'
        f"아래 스킬 목록에서 이 메시지와 관련된 스킬 이름만 골라줘.\n"
        f"관련 없으면 아무것도 반환하지 마. 있으면 쉼표로 구분해서 이름만 반환해.\n\n"
        f"{skill_list}"
    )
    if not text:
        return []

    skill_map = {s["name"]: s for s in skills}
    results = []
    for name in (n.strip() for n in text.split(",")):
        if name in skill_map and len(results) < max_results:
            results.append({"name": name, "path": skill_map[name]["path"], "matched": "claude-p"})
    return results

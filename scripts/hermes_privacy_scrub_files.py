"""지식 파일(스킬·기억·이력·대화 요약)을 지금 마스킹 규칙으로 다시 가리는 논리만 담당한다.

게이트(R-privacy)와 내보내기가 보는 것과 같은 칸만 가린다 — 기억 본문 · 이력의 intent/lesson/decision · 대화 요약의
칸별 문장 · 스킬 본문 통째. 그 밖의 칸(id·시각·주제)은 건드리지 않는다. JSON 은 문자열 값 단위로 가려 유효성을 지킨다.
추적 중이고 변경 없는 파일은 git 이 백업이고, 그 밖의 파일은 원본을 백업 폴더에 복사한 뒤 쓴다.
적용 뒤 다시 가려 보아 또 달라지는 파일(마스킹이 멱등이 아님)은 쓰지 않고 실패로 돌려준다.
계획: docs/exec-plans/completed/2026-09-29-privacy-gate-hardening.md 목표 4

공개: KNOWLEDGE_GLOBS · plan · apply
"""

import glob
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hermes_conversation_file import SLOT_KEYS  # noqa: E402
from hermes_privacy_pending import scrub  # noqa: E402

KNOWLEDGE_GLOBS = (".hermes/skills/**/*.md", ".hermes/agents/*/skills/**/*.md", ".hermes/agents/*/memory.jsonl",
                   ".hermes/journal.jsonl", ".hermes/agents/*/conversations/**/*.json")
_JSONL_FIELDS = {"memory.jsonl": ("body",), "journal.jsonl": ("intent", "lesson", "decision")}
BACKUP_DIR = os.path.join(".hermes", ".scrub-backup")


def _jsonl_text(text: str, fields: tuple, project: str) -> str:
    out = []
    for line in text.splitlines(keepends=True):
        try:
            obj = json.loads(line)
        except ValueError:
            out.append(line)
            continue
        new = {**obj, **{f: scrub(obj[f], project) for f in fields if isinstance(obj.get(f), str)}} if isinstance(obj, dict) else obj
        out.append(line if new == obj else json.dumps(new, ensure_ascii=False, sort_keys=True) + "\n")
    return "".join(out)


def _conversation_text(text: str, project: str) -> str:
    try:
        data = json.loads(text)
    except ValueError:
        return text
    slots = data.get("slots") if isinstance(data, dict) else None
    if not isinstance(slots, dict):
        return text
    new_slots = {k: [scrub(str(x), project) for x in v] if k in SLOT_KEYS and isinstance(v, list) else v
                 for k, v in slots.items()}
    if new_slots == slots:
        return text
    return json.dumps({**data, "slots": new_slots}, ensure_ascii=False, sort_keys=True, indent=1) + "\n"


def scrubbed(path: str, text: str, project: str) -> str:
    name = os.path.basename(path)
    if name in _JSONL_FIELDS:
        return _jsonl_text(text, _JSONL_FIELDS[name], project)
    if path.endswith(".json"):
        return _conversation_text(text, project)
    return scrub(text, project)


def plan(project: str) -> list:
    """다시 가리면 달라지는 파일 [(상대경로, 새 본문, 멱등 여부)]."""
    out = []
    for pattern in KNOWLEDGE_GLOBS:
        for path in sorted(glob.glob(os.path.join(project, pattern), recursive=True)):
            try:
                with open(path, encoding="utf-8") as fh:
                    text = fh.read()
            except OSError:
                continue
            new = scrubbed(path, text, project)
            if new != text:
                out.append((os.path.relpath(path, project), new, scrubbed(path, new, project) == new))
    return out


def _git_clean(project: str, rel: str) -> bool:
    """추적 중이고 작업 트리 변경이 없는가 — 그러면 git 이 백업이다."""
    def run(*args):
        return subprocess.run(["git", "-C", project, *args], capture_output=True, text=True)
    return run("ls-files", "--error-unmatch", rel).returncode == 0 and not run("status", "--porcelain", "--", rel).stdout.strip()


def apply(project: str, entries: list):
    """→ (쓴 파일 목록, 멱등이 아니라 못 쓴 파일 목록, 백업 폴더)."""
    backup = os.path.join(project, BACKUP_DIR, datetime.now().strftime("%Y%m%d-%H%M%S"))
    written, failed = [], []
    for rel, new, stable in entries:
        if not stable:
            failed.append(rel)
            continue
        src = os.path.join(project, rel)
        if not _git_clean(project, rel):
            os.makedirs(os.path.dirname(os.path.join(backup, rel)), exist_ok=True)
            shutil.copy2(src, os.path.join(backup, rel))
        with open(src + ".tmp", "w", encoding="utf-8") as fh:
            fh.write(new)
        os.replace(src + ".tmp", src)
        written.append(rel)
    return written, failed, backup

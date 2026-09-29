"""스테이징된 지식 파일에서 판정 대상 문장을 뽑는다 — 게이트(R-privacy)와 커밋 때 묻기가 함께 쓴다.

본다: .hermes/agents/*/memory.jsonl · .hermes/agents/*/conversations/** · .hermes/journal.jsonl ·
      .hermes/skills/**/*.md · .hermes/agents/*/skills/**/*.md
jsonl 은 이번에 **더해진 줄**만 본다(이미 올라간 줄은 이미 통과했다). 스킬·대화 요약은 스테이징된 본문 전체.
git 은 현재 작업 디렉터리(저장소 안)에서 부른다.
계획: docs/exec-plans/completed/2026-09-29-privacy-gate-hardening.md (게이트 로직을 그대로 옮김 — 동작 동일)

공개: PATTERNS · staged_paths · texts_of · staged_texts
"""

import fnmatch
import json
import subprocess

PATTERNS = (".hermes/agents/*/memory.jsonl", ".hermes/agents/*/conversations/*", ".hermes/journal.jsonl",
             ".hermes/skills/*.md", ".hermes/agents/*/skills/*.md")
_SLOTS = ("decisions", "open", "prefs", "facts", "next")


def _git(*args) -> str:
    return subprocess.run(["git", *args], capture_output=True, text=True).stdout


def staged_paths() -> list:
    names = _git("diff", "--cached", "--name-only", "--diff-filter=ACM").splitlines()
    return [n for n in names if any(fnmatch.fnmatch(n, p) for p in PATTERNS)]


def _added_json_lines(path: str) -> list:
    out = []
    for line in _git("diff", "--cached", "-U0", "--", path).splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            try:
                out.append(json.loads(line[1:]))
            except ValueError:
                continue
    return out


def _memory_texts(path: str) -> list:
    rows = [r for r in _added_json_lines(path) if isinstance(r, dict)]
    return [r["body"] for r in rows if r.get("body")]


def _journal_texts(path: str) -> list:
    rows = [r for r in _added_json_lines(path) if isinstance(r, dict)]
    texts = [r[k] for r in rows for k in ("intent", "lesson") if r.get(k)]
    return texts + [r["decision"] for r in rows if r.get("kind") == "decision" and r.get("decision")]


def _conversation_texts(blob: str) -> list:
    try:
        slots = (json.loads(blob) or {}).get("slots") or {}
    except ValueError:
        return [blob]                      # 깨진 파일 — 통째로 판정 기록이 없으니 막힌다
    return [str(x) for k in _SLOTS for x in (slots.get(k) or [])]


def texts_of(path: str) -> list:
    if path.endswith("memory.jsonl"):
        return _memory_texts(path)
    if path.endswith("journal.jsonl"):
        return _journal_texts(path)
    blob = _git("show", f":{path}")
    return _conversation_texts(blob) if "/conversations/" in path else [blob]


def staged_texts() -> list:
    """스테이징된 지식 파일의 판정 대상 문장 [(경로, 문장)]."""
    return [(p, t) for p in staged_paths() for t in texts_of(p)]

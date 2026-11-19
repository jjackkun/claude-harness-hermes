"""파일마다 검사 기준을 고르고 같은 기준끼리 묶는다 — 내장(OCR 규칙) + 프로젝트 .claude/review-rules.json."""
import json
import os

from scope_glob import glob_match

RULES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "references", "rules")
PROJECT_RULES = os.path.join(".claude", "review-rules.json")


class RuleFileError(Exception):
    """프로젝트 규칙 파일이 깨졌다."""


def _load_project(repo):
    path = os.path.join(repo, PROJECT_RULES)
    if not os.path.isfile(path):
        return []
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError) as err:
        raise RuleFileError(f"{PROJECT_RULES}: JSON 을 읽지 못했습니다 — {err}") from err
    rules = data.get("rules") if isinstance(data, dict) else None
    if not isinstance(rules, list):
        raise RuleFileError(f'{PROJECT_RULES}: 맨 위에 {{"rules": [...]}} 가 있어야 합니다')
    for i, rule in enumerate(rules):
        if not isinstance(rule, dict) or not str(rule.get("path", "")).strip() or not str(rule.get("rule", "")).strip():
            raise RuleFileError(f'{PROJECT_RULES}: rules[{i}] 에 비지 않은 "path" 와 "rule" 이 필요합니다')
    return rules


def _system(path, table):
    for pattern, doc in table["path_rule_map"].items():
        if glob_match(pattern, path):
            return doc
    return table["default_rule"]


def _read_doc(doc):
    with open(os.path.join(RULES_DIR, doc), encoding="utf-8") as fh:
        return fh.read().strip()


def resolve_rules(repo, paths):
    """[{rule, files, text}] — 같은 기준을 쓰는 파일끼리 한 묶음."""
    with open(os.path.join(RULES_DIR, "path_rule_map.json"), encoding="utf-8") as fh:
        table = json.load(fh)
    project = _load_project(repo)
    groups = {}
    for path in paths:
        doc = _system(path, table)
        user = next((r for r in project if glob_match(r["path"], path)), None)
        if user is None:
            key, parts = doc, [_read_doc(doc)]
        elif user.get("merge_system_rule"):
            key, parts = f"{doc}+project:{user['path']}", [_read_doc(doc), user["rule"].strip()]
        else:
            key, parts = f"project:{user['path']}", [user["rule"].strip()]
        group = groups.setdefault(key, {"rule": key, "files": [], "text": "\n\n".join(parts)})
        group["files"].append(path)
    return list(groups.values())

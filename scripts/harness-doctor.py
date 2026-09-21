#!/usr/bin/env python3
"""소우주 설치 상태 진단·복구 (계획 2026-09-20-install-doctor-repair).

  python3 scripts/harness-doctor.py <소우주> [--json] [--brief]          진단(읽기 전용)
  python3 scripts/harness-doctor.py <소우주> --repair [--yes]           복구 계획 → --yes 면 설치기 재실행
  python3 scripts/harness-doctor.py --factory-self [--factory <공장>]   공장 쪽 폐로 점검

진단 네 종류: 불일치(sha256 ≠ 매니페스트 — 하류 수정 또는 옛 판 보존) · 누락(경로 없음) · lock 어긋남(설치된 rules 가 lock 의 프리셋 RULES 선언에 없음) · 갱신 대기(factory_commit ≠ HEAD).
매니페스트 밖 .claude/{skills,agents,rules} 는 사용자 자산으로 센다(오류 아님). 종료코드 0 깨끗 · 1 발견 · 2 진단 불가.
복구는 project-claude.sh 재실행 한 길뿐이고 .hermes/ 는 건드리지 않는다. 표준 모듈만(tier 0). 공개 심볼: diagnose · repair · factory_self · main
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

_FACTORY = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_KIND_DIRS = {"skills": ("skills", ""), "agents": ("agents", ".md"), "rules": ("rules", "")}
_COEXIST_KINDS = ("hook", "githook", "script", "lint")


def _sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def _sha_target(path):
    """lib/factory_manifest.sh `_manifest_sha` 와 같은 값: 디렉터리는 `find -type f | sort | sha256sum` 목록의 sha256."""
    if not os.path.isdir(path):
        return _sha_file(path)
    rels = []
    for root, _dirs, files in os.walk(path):
        for f in files:
            full = os.path.join(root, f)
            if not os.path.islink(full):
                rels.append("./" + os.path.relpath(full, path).replace(os.sep, "/"))
    rels.sort(key=lambda s: s.encode("utf-8", "surrogateescape"))   # LC_ALL=C sort 와 같은 바이트 순서; 비UTF-8 이름도 죽지 않는다
    listing = "".join(f"{_sha_file(os.path.join(path, r[2:]))}  {r}\n" for r in rels)
    return hashlib.sha256(listing.encode("utf-8")).hexdigest()


def _installed_path(project, item):
    kind, name = item.get("kind"), item.get("name", "")
    if kind in _KIND_DIRS:
        sub, ext = _KIND_DIRS[kind]
        return os.path.join(project, ".claude", sub, name + ext)
    return os.path.join(project, name)


def _load_manifest(project):
    p = os.path.join(project, ".claude", ".factory-manifest.json")
    if not os.path.isfile(p):
        return None
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh).get("items", [])
    except (ValueError, AttributeError):
        return None


def _lock(project):
    p = os.path.join(project, ".claude", "presets.lock")
    if not os.path.isfile(p):
        return None
    with open(p, encoding="utf-8") as fh:
        return [ln.strip() for ln in fh if ln.strip()]


_RULES_DECL = re.compile(r"^\s*RULES\+=\(([^)]*)\)", re.M)


def _expected_rules(factory, lock):
    """lock 의 프리셋(+ _common) conf 가 선언한 RULES 의 합집합. conf 를 못 찾는 프리셋은 건너뛴다(유령 프리셋은 update-all 이 따로 걷는다)."""
    confs = [os.path.join(factory, "presets", "_common.conf")]
    for root, _d, files in os.walk(os.path.join(factory, "presets")):
        confs += [os.path.join(root, f) for f in files if f.endswith(".conf") and f[:-5] in lock]
    rules = set()
    for c in confs:
        if os.path.isfile(c):
            with open(c, encoding="utf-8", errors="replace") as fh:
                text = "\n".join(ln for ln in fh if not ln.lstrip().startswith("#"))
            for m in _RULES_DECL.finditer(text):
                rules.update(m.group(1).split())
    return rules


def _factory_head(factory):
    try:
        out = subprocess.run(["git", "-C", factory, "rev-parse", "HEAD"], capture_output=True, text=True, timeout=5)
        return out.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def _user_assets(project, items):
    known = {(i.get("kind"), i.get("name")) for i in items}
    out = []
    for kind, (sub, ext) in _KIND_DIRS.items():
        d = os.path.join(project, ".claude", sub)
        if not os.path.isdir(d):
            continue
        for entry in sorted(os.listdir(d)):
            if entry.startswith("."):
                continue
            name = entry[:-len(ext)] if ext and entry.endswith(ext) else entry
            if (kind, name) not in known:
                out.append(f"{kind}/{entry}")
    return out


def _manifest_untracked(project):
    """설치 목록이 git 에 **안 들어가는가**. I-02 는 "목록은 커밋된다" 를 전제한다 — 다른 컴퓨터의 clone 도
    어느 파일이 공장 것인지 알아야 변조 감지·공존 설치 base 가 동작한다.

    돌려주는 값은 사유다: `"ignored"`(무시 규칙에 덮임 — 커밋할 수조차 없다) · `"uncommitted"`(규칙엔 안 걸리는데
    아직 add 되지 않음) · `""`(문제 없음). 판정은 git 에게 묻는다 — 규칙 문자열을 우리가 해석하면 순서·부정 규칙에서 틀린다.
    git 저장소가 아니면 판정 대상이 아니다.
    """
    rel = os.path.join(".claude", ".factory-manifest.json")
    if not os.path.isfile(os.path.join(project, rel)):
        return ""
    try:
        inside = subprocess.run(["git", "-C", project, "rev-parse", "--is-inside-work-tree"],
                                capture_output=True, text=True, timeout=10)
        if inside.returncode != 0 or inside.stdout.strip() != "true":
            return ""
        tracked = subprocess.run(["git", "-C", project, "ls-files", "--error-unmatch", rel],
                                 capture_output=True, text=True, timeout=10)
        if tracked.returncode == 0:
            return ""
        ignored = subprocess.run(["git", "-C", project, "check-ignore", "-q", rel],
                                 capture_output=True, text=True, timeout=10)
        return "ignored" if ignored.returncode == 0 else "uncommitted"
    except (OSError, subprocess.SubprocessError):
        return ""


def diagnose(project, factory=_FACTORY):
    """{ok, tampered, missing, lock_drift, stale, user_assets, total, head, lock} — 읽기 전용."""
    items = _load_manifest(project)
    if items is None:
        return {"ok": False, "error": "매니페스트 없음 또는 손상: .claude/.factory-manifest.json"}
    head, lock = _factory_head(factory), _lock(project)
    expected = _expected_rules(factory, lock) if lock is not None else None
    rep = {"ok": True, "total": len(items), "head": head, "lock": lock, "tampered": [], "missing": [], "lock_drift": [],
           "stale": [], "user_assets": _user_assets(project, items)}
    for it in items:
        _classify(project, it, expected, head, rep)
    # 정보 항목 — ok 를 거짓으로 만들지 않는다. 그 프로젝트의 `.gitignore` 선택이고,
    # 실패로 찍으면 doctor 가 늘 빨강이라 아무도 안 본다. "보이게 한다" 가 목적이다.
    rep["manifest_untracked"] = _manifest_untracked(project)
    rep["ok"] = not (rep["tampered"] or rep["missing"] or rep["lock_drift"])
    return rep


def _classify(project, it, expected, head, rep):
    label = f"{it.get('kind')}/{it.get('name')}"
    path = _installed_path(project, it)
    if not os.path.exists(path):
        rep["missing"].append(label)
    elif it.get("sha256") and _sha_target(path) != it["sha256"]:
        rep["tampered"].append(label)
    if it.get("kind") == "rules" and expected is not None and it.get("name") not in expected:
        rep["lock_drift"].append(label)
    if head and it.get("factory_commit") and it["factory_commit"] != head:
        rep["stale"].append(label)


def _render(project, rep, brief=False):
    if "error" in rep:
        return f"[doctor] {project}: 진단 불가 — {rep['error']}"
    parts = [f"불일치 {len(rep['tampered'])}", f"누락 {len(rep['missing'])}", f"lock 어긋남 {len(rep['lock_drift'])}",
             f"갱신 대기 {len(rep['stale'])}/{rep['total']}", f"사용자 자산 {len(rep['user_assets'])}"]
    head = f"[doctor] {project}: {'깨끗' if rep['ok'] else '발견'} — " + " · ".join(parts)
    if brief:
        return head
    lines = [head]
    for key, title in (("tampered", "불일치(매니페스트 sha256 ≠ 현재 — 하류에서 고쳤거나 옛 공장판이 보존됨)"), ("missing", "누락(경로 없음)"),
                       ("lock_drift", "lock 어긋남(lock 의 프리셋이 선언하지 않는 rules — 재설치 때 제거된다)"),
                       ("user_assets", "사용자 자산(매니페스트 밖 — 설치기가 건드리지 않음)")):
        if rep[key]:
            lines.append(f"  {title}:")
            lines.extend(f"    - {x}" for x in rep[key])
    if rep.get("manifest_untracked") == "ignored":
        lines.append("  설치 목록이 git 에 추적되지 않음 — 무시 규칙에 덮였다(커밋할 수조차 없다)."
                     " 그 규칙 뒤에 !.claude/.factory-manifest.json 한 줄을 두십시오")
    elif rep.get("manifest_untracked") == "uncommitted":
        lines.append("  설치 목록이 git 에 추적되지 않음 — 무시되지는 않으나 아직 커밋되지 않았다."
                     " 이대로 clone 하면 진단 불가(매니페스트 없음)·공존 설치 base 없음이 된다")
    if rep["stale"]:
        lines.append(f"  갱신 대기 {len(rep['stale'])}건 — 공장 HEAD {str(rep['head'])[:8]} 와 다른 factory_commit (update-all 로 맞춘다)")
    return "\n".join(lines)


def _print_plan(project, rep, lock):
    print("[doctor] 복구 계획 (설치기 재실행 = project-claude.sh %s %s):" % (project, " ".join(lock)))
    for x in rep.get("tampered") or []:
        coexist = x.split("/", 1)[0] in _COEXIST_KINDS
        print(f"  {'공존 규칙으로 판정(하류 수정이면 보존하고 .factory-new 로 알린다)' if coexist else '덮어쓴다'}: {x}")
    for key, verb in (("missing", "되살린다"), ("lock_drift", "제거된다(lock 에 프리셋을 넣으면 남는다)")):
        for x in rep.get(key) or []:
            print(f"  {verb}: {x}")
    print(f"  갱신 대기 {len(rep.get('stale') or [])}건은 공장 HEAD 로 맞춰진다. .hermes/ 는 건드리지 않는다.")


def repair(project, rep, yes, factory=_FACTORY):
    """복구 계획을 찍고, yes 일 때만 project-claude.sh <project> $(lock) 을 돌린다. .hermes/ 는 설치기도 건드리지 않는다."""
    lock = rep.get("lock")
    if not lock:
        print("[doctor] 복구 불가 — .claude/presets.lock 이 없거나 비었다", file=sys.stderr)
        return 2
    _print_plan(project, rep, lock)
    if not yes:
        print("[doctor] 계획만 — 실행하려면 --yes")
        return 0
    rc = subprocess.call(["bash", os.path.join(factory, "project-claude.sh"), project, *lock])
    after = diagnose(project, factory)
    print(_render(project, after, brief=True))
    return 0 if rc == 0 and after.get("ok") else 1


def _read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def _uncopied_scripts(factory):
    conf = os.path.join(factory, "presets", "workflow", "hermes.conf")
    m = re.search(r"hermes_scripts=\(([^)]*)\)", _read(conf) if os.path.isfile(conf) else "", re.S)
    copied = set(m.group(1).split()) if m else set()
    sdir = os.path.join(factory, "scripts")
    scripts = sorted(f for f in os.listdir(sdir) if f.startswith("hermes") and f.endswith(".py")) if os.path.isdir(sdir) else []
    return scripts, [f for f in scripts if f not in copied]


def _registry_blob(factory):
    """프리셋 conf 전부 + lib/*.sh 본문 — 훅 이름이 여기 없으면 어느 설치 경로에도 등록되지 않은 것."""
    corpus = []
    for root, _d, files in os.walk(os.path.join(factory, "presets")):
        corpus += [_read(os.path.join(root, f)) for f in files if f.endswith(".conf")]
    ldir = os.path.join(factory, "lib")
    if os.path.isdir(ldir):
        corpus += [_read(os.path.join(ldir, f)) for f in os.listdir(ldir) if f.endswith(".sh")]
    return "\n".join(corpus)


def _unregistered_hooks(factory):
    blob = _registry_blob(factory)
    hdir = os.path.join(factory, "assets", "hooks")
    hooks = sorted(f for f in os.listdir(hdir) if f.endswith((".sh", ".py", ".mjs"))) if os.path.isdir(hdir) else []
    return hooks, [f for f in hooks if f not in blob]


def factory_self(factory=_FACTORY):
    """공장 폐로: hermes*.py 중 hermes.conf 복사 목록에 없는 것 · assets/hooks 중 어느 conf/lib 에도 등록되지 않은 훅."""
    scripts, uncopied = _uncopied_scripts(factory)
    hooks, unregistered = _unregistered_hooks(factory)
    return {"ok": not (uncopied or unregistered), "uncopied_scripts": uncopied, "unregistered_hooks": unregistered,
            "scripts": len(scripts), "hooks": len(hooks)}


def _run_factory_self(a):
    rep = factory_self(a.factory)
    if a.json:
        print(json.dumps(rep, ensure_ascii=False, indent=2))
        return 0 if rep["ok"] else 1
    print(f"[doctor:factory] 스크립트 {rep['scripts']} · 훅 {rep['hooks']} — "
          f"복사 목록 누락 {len(rep['uncopied_scripts'])} · 미등록 훅 {len(rep['unregistered_hooks'])}")
    for x in rep["uncopied_scripts"]:
        print(f"  hermes.conf hermes_scripts 에 없음: scripts/{x}")
    for x in rep["unregistered_hooks"]:
        print(f"  어느 conf/lib 에도 없음: assets/hooks/{x}")
    return 0 if rep["ok"] else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description="소우주 설치 진단·복구")
    ap.add_argument("project", nargs="?")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--brief", action="store_true", help="한 줄 요약만")
    ap.add_argument("--repair", action="store_true")
    ap.add_argument("--yes", action="store_true", help="--repair 를 실제로 실행")
    ap.add_argument("--factory-self", action="store_true")
    ap.add_argument("--factory", default=_FACTORY)
    a = ap.parse_args(argv)
    if a.factory_self:
        return _run_factory_self(a)
    if not a.project:
        ap.error("소우주 경로가 필요하다")
    project = os.path.abspath(a.project)
    rep = diagnose(project, a.factory)
    if a.repair:
        if "error" in rep:
            print(_render(project, rep), file=sys.stderr)
            return 2
        return repair(project, rep, a.yes, a.factory)
    print(json.dumps(rep, ensure_ascii=False, indent=2) if a.json else _render(project, rep, a.brief))
    return 2 if "error" in rep else (0 if rep["ok"] else 1)


if __name__ == "__main__":
    sys.exit(main())

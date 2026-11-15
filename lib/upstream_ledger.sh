#!/usr/bin/env bash
# lib/upstream_ledger.sh
# Responsibility: 공장 장부(assets/upstream.json)에서 이 프로젝트에 깐 항목만 골라
#                 <프로젝트>/.claude/.upstream.json 에 쓰는 것만 담당한다.
# 계획: docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G3
#
# 공장이 없는 컴퓨터(소우주만 clone)도 새 버전을 확인할 수 있게, 확인에 필요한 장부를 프로젝트 안에 둔다.
# 이 파일은 설치가 매번 다시 쓰므로 커밋하지 않는다(.gitignore 블록).
#
# 공개 함수 1개: upstream_write_project_ledger

_UPSTREAM_PROJECT_LEDGER=".upstream.json"

# upstream_write_project_ledger <factory_dir> <claude_dir>
# 전역 배열 SKILLS·AGENTS·RULES(이번 설치 목록)를 본다. 깐 외부 에셋이 없으면 파일을 지운다.
# 실패해도 설치를 멈추지 않는다 — 경고만 남긴다.
upstream_write_project_ledger() {
  local factory="$1" claude_dir="$2"
  local src="$factory/assets/upstream.json" dst="$claude_dir/$_UPSTREAM_PROJECT_LEDGER"
  [[ -f "$src" ]] || { rm -f "$dst"; return 0; }
  local commit
  commit="$(git -C "$factory" rev-parse HEAD 2>/dev/null || echo unknown)"
  if ! UL_SKILLS="${SKILLS[*]+"${SKILLS[*]}"}" UL_AGENTS="${AGENTS[*]+"${AGENTS[*]}"}" UL_RULES="${RULES[*]+"${RULES[*]}"}" \
    python3 - "$src" "$dst" "$commit" <<'PY'
import json, os, sys
src, dst, commit = sys.argv[1:4]
installed = {
    'skills': set(os.environ.get('UL_SKILLS', '').split()),
    'agents': {n.removesuffix('.md') for n in os.environ.get('UL_AGENTS', '').split()},
    'rules': set(os.environ.get('UL_RULES', '').split()),
}
ledger = json.load(open(src))
mine = [it for it in ledger['items'] if it['name'] in installed.get(it['kind'], set())]
if not mine:
    if os.path.exists(dst):
        os.remove(dst)
    sys.exit(0)
out = {'version': ledger['version'], 'factory_commit': commit, 'items': mine}
tmp = dst + '.tmp'
with open(tmp, 'w') as f:
    json.dump(out, f, ensure_ascii=False, indent=2)
os.replace(tmp, dst)
PY
  then
    log_warn "  upstream 장부를 쓰지 못했습니다 — 새 버전 확인이 이 프로젝트에서 멈춥니다 ($dst)"
  fi
  return 0
}

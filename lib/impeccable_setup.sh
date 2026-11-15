#!/usr/bin/env bash
# lib/impeccable_setup.sh
# Responsibility: impeccable 스킬을 깐 프로젝트에 .impeccable/config.json 의 "telemetry": false 를 두는 것만 담당한다.
# 계획: docs/exec-plans/active/2026-11-15-impeccable-4-upgrade.md G6
#
# impeccable 4.x 엔진은 새 디자인을 시작할 때 고른 방향을 익명으로 보낸다. 끄는 법은 프로젝트의
# .impeccable/config.json 에 "telemetry": false (원본 README). 이 파일은 커밋 대상이다 — clone 한 컴퓨터도 꺼진 채로.
# 이미 있는 설정의 다른 칸은 지키고 telemetry 만 false 로 맞춘다. 실패해도 설치를 멈추지 않는다.
#
# 공개 함수 1개: impeccable_project_setup

# impeccable_project_setup <project_path> — 전역 배열 SKILLS 에 impeccable 이 있을 때만 쓴다.
impeccable_project_setup() {
  local project="$1" s found=0
  for s in "${SKILLS[@]+"${SKILLS[@]}"}"; do
    [[ "$s" == impeccable ]] && found=1
  done
  [[ $found -eq 1 ]] || return 0
  if ! python3 - "$project/.impeccable/config.json" <<'PY'
import json, os, sys
path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)
try:
    with open(path, encoding='utf-8') as f:
        cfg = json.load(f)
    if not isinstance(cfg, dict):
        cfg = {}
except (OSError, ValueError):
    cfg = {}
if cfg.get('telemetry') is False:
    sys.exit(0)
cfg['telemetry'] = False
tmp = path + '.tmp'
with open(tmp, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write('\n')
os.replace(tmp, path)
PY
  then
    log_warn "  impeccable 원격 통계를 끄지 못했습니다 — $project/.impeccable/config.json 에 \"telemetry\": false 를 직접 넣으세요"
  fi
  return 0
}

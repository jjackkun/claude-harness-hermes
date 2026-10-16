#!/usr/bin/env bash
# lib/struct_files.sh — R-struct 구조 검사기 파일 목록. 설치(harness_installers.sh)와
# 제거(uninstall_helpers.sh)가 같은 목록을 쓴다 — 흩어 두면 부분 설치·잔재가 생긴다.
# check-component-structure.mjs 는 옛 pre-commit 이 부르는 호환 래퍼다.
# shellcheck disable=SC2034  # 불러오는 쪽에서 쓴다
HARNESS_STRUCT_FILES=(
  check-structure.mjs structure-langs.json structure-config.mjs structure-resolve.mjs
  structure-output.mjs structure-rule-barrel.mjs structure-rule-deep-import.mjs
  structure-rule-reexport.mjs structure-rules-common.mjs structure-baseline.mjs
  check-component-structure.mjs
)

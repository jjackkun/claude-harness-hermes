#!/usr/bin/env bash
# dev-setting/lib/common.sh
# Barrel — 하위 lib 모듈을 한 번에 source. project-claude.sh / public-claude.sh /
# tests/harness-hooks-smoke.sh 가 이 파일 하나만 source 하면 모든 헬퍼 함수·전역 배열 API
# 가 로드된다 (Python `__init__.py` re-export 와 동일 역할).
#
# 책임 분산 (2026-04-21-split-lib-common):
#   - logging.sh            : 로그 레벨별 printf 헬퍼
#   - preset.sh             : config 디렉터리 탐지 + preset 배열 초기화·머지·dedupe·로드
#   - installers.sh         : 범용 에셋 installer (skills/agents/rules)
#   - plugins.sh            : preset 플러그인 동기화 (refcount 설치/제거)
#   - harness_installers.sh : 하네스 특화 installer 5종
#   - settings_gen.sh       : .claude/settings.local.json 생성
#   - claude_md_gen.sh      : CLAUDE.md 관리 블록 + manifest 작성
#
# Sourced, not executed directly.

_DS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Windows/WSL path helpers (must load first — used by all other modules) ----
# shellcheck source=lib/windows.sh
source "$_DS_LIB/windows.sh"

# 로딩 순서: logging 이 먼저 (모두가 log_* 사용). preset 은 전역 배열 초기화라 다음.
# 나머지는 독립적이지만 실행 순서상 installers → harness → settings → claude_md.
# shellcheck source=lib/logging.sh
source "$_DS_LIB/logging.sh"
# shellcheck source=lib/preset.sh
source "$_DS_LIB/preset.sh"
# shellcheck source=lib/installers.sh
source "$_DS_LIB/installers.sh"
# shellcheck source=lib/plugins.sh
source "$_DS_LIB/plugins.sh"
# shellcheck source=lib/harness_installers.sh
source "$_DS_LIB/harness_installers.sh"
# shellcheck source=lib/settings_gen.sh
source "$_DS_LIB/settings_gen.sh"
# shellcheck source=lib/claude_md_gen.sh
source "$_DS_LIB/claude_md_gen.sh"
# shellcheck source=lib/hermes_memory.sh
source "$_DS_LIB/hermes_memory.sh"

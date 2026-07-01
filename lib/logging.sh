#!/usr/bin/env bash
# dev-setting/lib/logging.sh
# Responsibility: 로그 레벨별 printf 헬퍼. 다른 모든 lib/*.sh 의 공통 기반.

log_info()    { printf "\033[0;34m[INFO]\033[0m  %s\n" "$*"; }
log_warn()    { printf "\033[0;33m[WARN]\033[0m  %s\n" "$*" >&2; }
log_error()   { printf "\033[0;31m[ERROR]\033[0m %s\n" "$*" >&2; }
log_success() { printf "\033[0;32m[ OK ]\033[0m  %s\n" "$*"; }

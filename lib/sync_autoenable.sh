#!/usr/bin/env bash
# 기억 운반을 설치기가 켠다 (T-19 · T-21, 계획 2026-09-20-transport-plain 목표 5).
# 왜 여기서: 켜는 절차가 사람 손에 있으면 아무 소우주도 켜지 않는다(2026-09-20 실측 0곳). 설치기는 이미 세션 밖에서 사람이 돌린다.
# 판단: 저장소가 비공개(PRIVATE·INTERNAL)면 평문 운반 켬 + 첫 push. 공개(PUBLIC)·미상이면 끔(sync.json 은 남겨 이유를 적는다).
# 건드리지 않는 것: 이미 있는 sync.json(사람이 정한 값) · HARNESS_SYNC_AUTOENABLE=0. 평문 모드라 세션 안에서도 켠다(열쇠 없음).
# 공개 함수 2개: sync_visibility <project> · sync_autoenable <project>

# sync_visibility <project> → PRIVATE | INTERNAL | PUBLIC | unknown
# 1) GitHub 면 gh 가 답한다. 2) 아니면 제공자 무관 **익명 프로브**(T-19 보강 2026-09-20): 자격증명 없이 https 로 읽히면 공개,
#    인증을 요구(Access denied·401·403·404)하면서 인증된 origin 은 읽히면 비공개. 네트워크 오류·로컬 경로 origin 은 unknown.
# HARNESS_SYNC_PROBE=public|private|unknown 은 테스트용 강제값.
sync_visibility() {
  local project="$1" out url
  git -C "$project" remote get-url origin >/dev/null 2>&1 || { echo unknown; return 0; }
  if [[ -n "${HARNESS_SYNC_PROBE:-}" ]]; then
    case "$HARNESS_SYNC_PROBE" in public) echo PUBLIC ;; private) echo PRIVATE ;; *) echo unknown ;; esac; return 0
  fi
  if command -v gh >/dev/null 2>&1; then
    out="$(cd "$project" && timeout "${HARNESS_GH_TIMEOUT:-8}" gh repo view --json visibility -q .visibility 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"
    case "$out" in PRIVATE|INTERNAL|PUBLIC) echo "$out"; return 0 ;; esac
  fi
  url="$(_sync_https_url "$(git -C "$project" remote get-url origin)")"
  [[ -n "$url" ]] || { echo unknown; return 0; }
  _sync_anon_probe "$project" "$url"
}

# ssh/https origin → 익명 프로브용 https URL. 로컬 경로·file:// 는 빈 문자열(판별 대상 아님).
_sync_https_url() {
  local o="$1"
  case "$o" in
    http://*|https://*) printf '%s' "$o" ;;
    ssh://git@*) printf 'https://%s' "${o#ssh://git@}" | sed -E 's#:[0-9]+/#/#' ;;
    git@*:*) local rest="${o#git@}"; printf 'https://%s/%s' "${rest%%:*}" "${rest#*:}" ;;
    *) printf '' ;;
  esac
}

_sync_anon_probe() {   # <project> <https url>
  local project="$1" url="$2" err rc
  err="$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true timeout "${HARNESS_PROBE_TIMEOUT:-15}" \
         git -c credential.helper= ls-remote --exit-code "$url" HEAD 2>&1 >/dev/null)"; rc=$?
  if [[ $rc -eq 0 ]]; then echo PUBLIC; return 0; fi
  if grep -qiE 'access denied|authentication|could not read username|terminal prompts disabled|HTTP 40[134]|not found' <<<"$err"; then
    # 익명은 막혔다 — 인증된 origin(ssh 등)으로는 읽혀야 "비공개" 다. 그것도 안 되면 존재·권한을 모른다.
    if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' timeout "${HARNESS_PROBE_TIMEOUT:-15}" \
         git -C "$project" ls-remote --exit-code origin HEAD >/dev/null 2>&1; then echo PRIVATE; else echo unknown; fi
    return 0
  fi
  echo unknown        # 네트워크·DNS·타임아웃 — 판단 근거 없음
}

# sync_autoenable <project>
# 항상 0 을 돌려준다 — 운반 설정 실패가 설치를 세우지 않는다.
sync_autoenable() {
  local project="$1" policy="$1/.hermes/sync.json" vis
  [[ "${HARNESS_SYNC_AUTOENABLE:-1}" == "0" ]] && { log_info "  sync    → 자동 켜기 생략(HARNESS_SYNC_AUTOENABLE=0)"; return 0; }
  # AI 세션 안에서도 켠다 — 평문 모드는 열쇠를 만들지 않으므로 세션 밖 규칙(T-11)과 무관하다(2026-09-20 정정, T-21).
  if [[ -f "$policy" ]]; then
    log_info "  sync    → sync.json 있음 — 그대로 둔다(사람이 정한 값)"; return 0
  fi
  [[ -d "$project/.hermes" ]] || return 0
  vis="$(sync_visibility "$project")"
  case "$vis" in
    PRIVATE|INTERNAL)
      printf '{"push": true, "mode": "plain", "visibility": "%s", "set_by": "installer"}\n' "$vis" > "$policy"
      log_info "  sync    → 비공개 저장소($vis): 평문 운반 켬 — 요약·패턴·기억·작업 이력이 refs/hermes/sync 로 간다(원문 제외, T-17)"
      if [[ -f "$project/scripts/hermes-sync.py" ]]; then
        (cd "$project" && timeout "${HERMES_SYNC_TIMEOUT:-60}" python3 scripts/hermes-sync.py --project "$project" push 2>&1 | sed 's/^/  sync    → /') || log_warn "  sync    → 첫 push 실패 — 다음 세션 종료 때 다시 시도한다"
      fi ;;
    PUBLIC)
      printf '{"push": false, "visibility": "PUBLIC", "set_by": "installer"}\n' > "$policy"
      log_info "  sync    → 공개 저장소: 운반 끔(T-19). 켜려면 잠금 모드 — docs/hermes-sync-guide.md" ;;
    *)
      printf '{"push": false, "visibility": "unknown", "set_by": "installer"}\n' > "$policy"
      log_info "  sync    → 공개 여부 미상(origin 없음·로컬 origin·네트워크 오류): 운반 끔. 비공개면 sync.json 을 {\"push\": true, \"mode\": \"plain\"} 로" ;;
  esac
  return 0
}

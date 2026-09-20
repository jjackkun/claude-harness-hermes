#!/usr/bin/env bash
# 기억 운반을 설치기가 켠다 (T-19 · T-21, 계획 2026-09-20-transport-plain 목표 5).
# 왜 여기서: 켜는 절차가 사람 손에 있으면 아무 소우주도 켜지 않는다(2026-09-20 실측 0곳). 설치기는 이미 세션 밖에서 사람이 돌린다.
# 판단: 저장소가 비공개(PRIVATE·INTERNAL)면 평문 운반 켬 + 첫 push. 공개(PUBLIC)·미상이면 끔(sync.json 은 남겨 이유를 적는다).
# 건드리지 않는 것: 이미 있는 sync.json(사람이 정한 값) · AI 세션 안 실행(CLAUDECODE) · HARNESS_SYNC_AUTOENABLE=0.
# 공개 함수 2개: sync_visibility <project> · sync_autoenable <project>

# sync_visibility <project> → PRIVATE | INTERNAL | PUBLIC | unknown  (origin 없음·gh 없음·실패는 unknown)
sync_visibility() {
  local project="$1" out
  git -C "$project" remote get-url origin >/dev/null 2>&1 || { echo unknown; return 0; }
  command -v gh >/dev/null 2>&1 || { echo unknown; return 0; }
  out="$(cd "$project" && timeout "${HARNESS_GH_TIMEOUT:-8}" gh repo view --json visibility -q .visibility 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"
  case "$out" in PRIVATE|INTERNAL|PUBLIC) echo "$out" ;; *) echo unknown ;; esac
}

# sync_autoenable <project>
# 항상 0 을 돌려준다 — 운반 설정 실패가 설치를 세우지 않는다.
sync_autoenable() {
  local project="$1" policy="$1/.hermes/sync.json" vis
  [[ "${HARNESS_SYNC_AUTOENABLE:-1}" == "0" ]] && { log_info "  sync    → 자동 켜기 생략(HARNESS_SYNC_AUTOENABLE=0)"; return 0; }
  if [[ -n "${CLAUDECODE:-}" ]]; then
    log_info "  sync    → AI 세션 안 실행 — 운반 설정은 세션 밖 설치(update-all)에서 한다(T-21)"; return 0
  fi
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
      log_info "  sync    → 공개 여부 미상(origin 없음·gh 없음·미인증): 운반 끔. 비공개면 sync.json 을 {\"push\": true, \"mode\": \"plain\"} 로" ;;
  esac
  return 0
}

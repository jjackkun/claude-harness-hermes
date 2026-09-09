#!/usr/bin/env bash
# UserPromptSubmit 디스패처 — stdin 을 한 번만 읽어 하위 훅들에 같은 페이로드를 먹인다.
#
# 왜 필요한가:
#   같은 이벤트에 훅이 여럿 등록되면 stdin 을 나눠 가질 수 없다. 먼저 `cat` 하는 훅이
#   전부 가져가고 나머지는 0바이트를 받는다. 2026-06 ~ 09 사이 reminders 의 스킬 주입은
#   19,939건 일어났어야 했으나 실제 0건이었다 — 항상 지는 쪽이었기 때문이다.
#   근거: docs/audits/2026-09-09-hermes-injection-gap.md
#
# 책임은 하나다 — 페이로드 배분. 판단·출력·기록은 전부 하위 훅이 한다.
#
# 대상: 같은 디렉터리의 claude-userpromptsubmit-*.sh (자기 자신 제외), 이름순.
# 종료코드: 2(차단) 를 만나면 즉시 멈추고 2 로 끝낸다. 그 밖의 0 아닌 값은 비차단
#           오류이므로 나머지 훅을 모두 돌린 뒤 처음 만난 값을 올린다.

# CWD 가드 — 하위 훅들이 프로젝트 루트를 $PWD 로 전제한다.
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}" 2>/dev/null || true

_payload="$(cat 2>/dev/null || true)"
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_self="$(basename "$0")"
_rc=0

for _hook in "$_dir"/claude-userpromptsubmit-*.sh; do
  [[ -f "$_hook" ]] || continue
  [[ "$(basename "$_hook")" == "$_self" ]] && continue

  printf '%s' "$_payload" | bash "$_hook"
  _sub_rc=$?

  # 2 = 프롬프트 차단. 이미 차단이 확정됐으므로 뒤 훅을 돌리지 않는다 —
  # 돌리면 버려질 프롬프트에 대해 DB·로그 부수효과만 쌓인다.
  if [[ $_sub_rc -eq 2 ]]; then
    exit 2
  fi

  # 그 밖의 0 아닌 값은 비차단 오류다(Claude Code 규약). 나머지 훅은 계속 돌리고
  # 처음 만난 값만 보존한다 — 뒤 훅이 성공해도 앞의 실패를 덮지 않는다.
  if [[ $_sub_rc -ne 0 && $_rc -eq 0 ]]; then
    _rc=$_sub_rc
  fi
done

exit $_rc

#!/usr/bin/env bash
# env-secrets 프리셋 — import · open · sync 동작 (계획 docs/exec-plans/active/2026-10-16-env-secrets-preset.md G2·G3·G8).
#
# 하류 jj-agent-room tests/fork-env-secrets.test.ts 27개 중 22개를 옮겼다. 옮기지 않은 5개:
#   - "this repo 의 .env.secrets 에 평문 없음" — 하류 저장소 자기 점검 (공장엔 .env.secrets 가 없다)
#   - "잠긴 금고면 init 단계는 경고하고 성공" · "clone 에 .env.secrets 없으면 init 단계 건너뜀"
#     — init-setting 단계 전용. 그 파일(lib/env-secrets.sh)은 하류에 남는다 (계획 §6)
#   - ".env.keys 는 무시, .env.secrets 는 추적" · ".harnessrc 커밋 게이트" — env-secrets-install-test.sh (G4·G5)
# init 단계로 돌던 하류 시험(G3 복원 등)은 같은 일을 하는 `open` 으로 돈다.
# 가짜 bw 가 금고를, 사용자 캐시의 고정 판 dotenvx 가 실제 암호화를 맡는다. 시험 프로젝트에는 package.json 이 없다 (G3).
#
# 실행: bash tests/env-secrets-test.sh
set -uo pipefail
source "$(dirname "$0")/fixtures/env-secrets/helpers.sh"
require_assets

echo "== import (첫 PC)"
original_pc
check "import 는 .env 의 모든 키를 암호화한다 (빠진 키 없음)" \
  diff <(envcheck keys "$SRC/.env.secrets") <(envcheck keys "$SRC_TEXT")
check "import 결과의 모든 값이 encrypted: 다" envcheck sealed "$SRC/.env.secrets"
check "import 결과 파일에 평문 값 없음" no_values "$(cat "$SRC/.env.secrets")" "${SRC_VALUES[@]}"
check "import 는 값도 열쇠도 화면에 내지 않는다" no_values "$SRC_OUT" "$SRC_KEY" "${SRC_VALUES[@]}"
check ".env.keys 권한 600" [ "$(mode_of "$SRC/.env.keys")" = 600 ]
check "열쇠가 Bitwarden 프로젝트 항목에 하나 저장된다" [ "$(vault_entry "$SRC_VAULT")" = "1 $SRC_KEY" ]
check "import 출력에 항목 이름이 나온다" has "$SRC_OUT" "$VAULT_ITEM"

D="$(new_repo locked)"; echo "OPENAI_API_KEY=openai-$(rand)" >"$D/.env"
run_in "$D" BW_BIN="$(fake_vault locked)/bw" import --yes
check "잠긴 금고(터미널 없음) → import 실패" [ "$RC" -ne 0 ]
check "잠긴 금고 → '잠김' 안내" has "$OUT" "잠김"
check "잠긴 금고 → .env.secrets·.env.keys 안 만든다" [ ! -e "$D/.env.secrets" -a ! -e "$D/.env.keys" ]

FIRST_VAULT="$SRC_VAULT"; FIRST_KEY="$SRC_KEY"
D="$(new_repo orphan)"; echo "OPENAI_API_KEY=openai-$(rand)" >"$D/.env"
run_in "$D" BW_BIN="$FIRST_VAULT/bw" import --yes
check "git 이 한 번도 안 본 짝 없는 항목은 갈아끼운다" [ "$RC" -eq 0 ]
check "갈아끼울 때 휴지통 안내" has "$OUT" "휴지통"
check "금고에 새 열쇠 하나만 남는다" [ "$(vault_entry "$FIRST_VAULT")" = "1 $(envcheck get "$D/.env.keys" DOTENV_PRIVATE_KEY_SECRETS)" ]

original_pc
D="$(new_repo live)"; cp "$SRC/.env.secrets" "$D/"
git_t "$D" add .env.secrets; git_t "$D" commit -qm s; git_t "$D" rm -q .env.secrets; git_t "$D" commit -qm gone
echo "OPENAI_API_KEY=openai-$(rand)" >"$D/.env"
run_in "$D" BW_BIN="$SRC_VAULT/bw" import --yes
check "git 이 본 적 있는 항목(살아 있을 수 있는 열쇠)은 지키고 실패" [ "$RC" -ne 0 ]
check "그때 git pull 안내" has "$OUT" "git pull"
check "금고 열쇠는 그대로" [ "$(vault_entry "$SRC_VAULT")" = "1 $SRC_KEY" ]

D="$(new_repo noyes)"; echo "OPENAI_API_KEY=openai-$(rand)" >"$D/.env"
run_in "$D" BW_BIN="$(fake_vault)/bw" import
check "터미널 없이 --yes 없으면 거절" [ "$RC" -ne 0 -a ! -e "$D/.env.secrets" ]

BEFORE="$(cat "$SRC/.env.secrets")"
run_in "$SRC" BW_BIN="$SRC_VAULT/bw" import --yes
check "이미 있는 .env.secrets 는 바꾸지 않는다" [ "$RC" -ne 0 -a "$(cat "$SRC/.env.secrets")" = "$BEFORE" ]

rm "$SRC/.env.secrets"
run_in "$SRC" BW_BIN="$(fake_vault)/bw" import --yes
check ".env.keys 에 이전 열쇠가 있으면 거절" [ "$RC" -ne 0 -a ! -e "$SRC/.env.secrets" ]
check "그때 .env.keys 를 짚는다" has "$OUT" '\.env\.keys'

source "$(dirname "$0")/fixtures/env-secrets/open-cases.sh"
source "$(dirname "$0")/fixtures/env-secrets/sync-cases.sh"
finish

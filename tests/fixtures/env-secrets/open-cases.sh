# env-secrets-test.sh 의 open 시나리오 (source 전용 — helpers.sh 와 original_pc 의 SRC 를 쓴다).
# 다른 PC: .env 없으면 바이트 그대로 복원, 있으면 값 갱신 (G2). 프로젝트 node_modules 없이 동작 (G3).
# Bitwarden 계정이 없으면 가입 안내 (G8).

echo "== open (다른 PC)"
original_pc
D="$(other_pc)"
run_in "$D" BW_BIN="$SRC_VAULT/bw" open
check ".env 없는 PC → open 성공" [ "$RC" -eq 0 ]
check ".env 를 주석·순서·빈 값까지 그대로 복원" cmp -s "$D/.env" "$SRC_TEXT"
check "복원한 .env 권한 600" [ "$(mode_of "$D/.env")" = 600 ]
check "열쇠 출처로 Bitwarden 을 알린다" has "$OUT" "Bitwarden"
check "성공 표시 ✔" has "$OUT" "✔"
check "open 은 값도 열쇠도 화면에 내지 않는다" no_values "$OUT" "$SRC_KEY" "${SRC_VALUES[@]}"

D="$(other_pc "OPENAI_API_KEY=stale-$(rand)
ONLY_HERE=x1
" with-keys)"
run_in "$D" open
check "자기 .env 가 있는 PC → open 성공" [ "$RC" -eq 0 ]
check "모든 값이 첫 PC 값으로 갱신된다" envcheck covers "$SRC_TEXT" "$D/.env"
check "그 PC 에만 있는 키는 남는다" [ "$(envcheck get "$D/.env" ONLY_HERE)" = x1 ]
check "갱신 개수 안내 (갱신 1)" has "$OUT" "갱신 1"
check "갱신 때도 값이 화면에 없다" no_values "$OUT" "${SRC_VALUES[@]}"

D="$(other_pc)"
run_in "$D" DOTENV_PRIVATE_KEY_SECRETS="$SRC_KEY" open
check "열쇠를 환경변수 DOTENV_PRIVATE_KEY_SECRETS 에서 받는다" cmp -s "$D/.env" "$SRC_TEXT"
check "환경변수 열쇠도 화면에 없다" no_values "$OUT" "$SRC_KEY" "${SRC_VALUES[@]}"

# bw 가 없는 PC: 대역 npm 이 "설치" 하면 시험 금고와 말하는 bw 가 PATH 에 생긴다.
D="$(other_pc)"; BIN="$(mktemp -d "$WORK/path-XXXX")"
ln -s "$(command -v node)" "$BIN/node"
cat >"$BIN/npm" <<EOF
#!/bin/sh
printf '#!/bin/sh\nexec "%s" "\$@"\n' '$SRC_VAULT/bw' > '$BIN/bw'
chmod +x '$BIN/bw'
EOF
chmod 755 "$BIN/npm"
run_in "$D" BW_BIN= PATH="$BIN:/usr/bin:/bin" open
check "bw 없는 PC → npm 으로 설치하고 열쇠를 읽는다" [ "$RC" -eq 0 -a -x "$BIN/bw" ]
check "설치 뒤 .env 복원" cmp -s "$D/.env" "$SRC_TEXT"

otherkey="$SRC_KEY"; original_pc
D="$(other_pc "PORT=6001
")"; BEFORE="$(cat "$D/.env")"
run_in "$D" DOTENV_PRIVATE_KEY_SECRETS="$otherkey" open
check "다른 열쇠 → 실패" [ "$RC" -ne 0 ]
check "실패 표시 ✘" has "$OUT" "✘"
check "다른 열쇠 → .env 는 그대로" [ "$(cat "$D/.env")" = "$BEFORE" ]
check "다른 열쇠도 화면에 없다" no_values "$OUT" "$otherkey"

# clone 직후: 캐시도 없다. 대역 npm 이 --prefix 자리에 진짜 캐시의 node_modules 를 잇는다 (G3).
D="$(other_pc)"; BIN="$(mktemp -d "$WORK/npm-XXXX")"; NEWCACHE="$WORK/fresh-cache-$RANDOM"
cat >"$BIN/npm" <<EOF
#!/bin/sh
while [ "\$1" != --prefix ]; do shift; done
ln -s '$CACHE/node_modules' "\$2/node_modules"
EOF
chmod 755 "$BIN/npm"
run_in "$D" BW_BIN="$SRC_VAULT/bw" PATH="$BIN:$PATH" ENV_SECRETS_CACHE="$NEWCACHE" open
check "package.json·node_modules 없는 clone → dotenvx 를 캐시에 받는다" [ -e "$NEWCACHE/node_modules" ]
check "받은 dotenvx 로 .env 복원" cmp -s "$D/.env" "$SRC_TEXT"

D="$(new_repo none)"
run_in "$D" open
check "git 에 .env.secrets 없으면 성공하고 그 사실만 알린다" [ "$RC" -eq 0 -a ! -e "$D/.env" ]
check "그때 첫 PC 에서 돌릴 명령 안내" has "$OUT" "secrets.sh import"

D="$(other_pc)"; vault_lock "$SRC_VAULT"
run_in "$D" BW_BIN="$SRC_VAULT/bw" open
check "잠긴 금고 → open 실패, .env 안 씀" [ "$RC" -ne 0 -a ! -e "$D/.env" ]
check "잠긴 금고 → '잠김' 안내" has "$OUT" "잠김"

echo "== Bitwarden 계정 없음 (G8)"
D="$(other_pc)"
run_in "$D" BW_BIN="$(fake_vault unauthenticated)/bw" open
check "로그인 안 된 금고 → open 실패, .env 안 씀" [ "$RC" -ne 0 -a ! -e "$D/.env" ]
check "가입 주소 안내" has "$OUT" "https://vault.bitwarden.com"
check "가입 뒤 다시 돌릴 명령 안내 (open)" has "$OUT" "bash scripts/env-secrets/secrets.sh open"
D="$(new_repo signup)"; echo "OPENAI_API_KEY=openai-$(rand)" >"$D/.env"
run_in "$D" BW_BIN="$(fake_vault unauthenticated)/bw" import --yes
check "로그인 안 된 금고 → import 도 가입 주소 안내" has "$OUT" "https://vault.bitwarden.com"
check "가입 뒤 다시 돌릴 명령 안내 (import)" has "$OUT" "bash scripts/env-secrets/secrets.sh import"

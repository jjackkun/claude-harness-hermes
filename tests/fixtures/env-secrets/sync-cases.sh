# env-secrets-test.sh 의 sync · merge 시나리오 (source 전용 — helpers.sh 를 쓴다).
# .env 가 바뀌면 같은 열쇠로 다시 암호화 (G2). 열쇠가 없어도 절대 실패하지 않는다 (커밋 게이트가 부른다).

echo "== sync (커밋 때 다시 암호화)"
original_pc
BEFORE="$(cat "$SRC/.env.secrets")"
run_in "$SRC" sync
check ".env 그대로면 sync 성공" [ "$RC" -eq 0 ]
check ".env 그대로면 .env.secrets 안 바뀜" [ "$(cat "$SRC/.env.secrets")" = "$BEFORE" ]

ADDED="new-service-$(rand)"
sed 's/^PORT=5181$/PORT=5999/' "$SRC_TEXT" >"$SRC/.env"
printf '# added later\nNEW_SERVICE_TOKEN=%s\n' "$ADDED" >>"$SRC/.env"
CHANGED="$WORK/changed.expected"; cp "$SRC/.env" "$CHANGED"
run_in "$SRC" sync
check "바뀐 .env (새 키·바뀐 값·주석) → sync 성공" [ "$RC" -eq 0 ]
check "다시 암호화했다고 알린다" has "$OUT" "다시 암호화"
check "새 값이 화면에 없다" no_values "$OUT" "$ADDED"
check "열쇠는 그대로 (Bitwarden 항목 계속 유효)" [ "$(envcheck get "$SRC/.env.keys" DOTENV_PRIVATE_KEY_SECRETS)" = "$SRC_KEY" ]
D="$(other_pc)"
run_in "$D" BW_BIN="$SRC_VAULT/bw" open
check "다른 PC 가 같은 금고 열쇠로 바뀐 .env 를 그대로 받는다" cmp -s "$D/.env" "$CHANGED"

# dotenvx decrypt --stdout 은 환경에 같은 이름이 있으면 파일 값 대신 그 값을 찍는다.
# 셸에 새 값이 export 돼 있으면 sync 가 "안 바뀜" 으로 속아 재암호화를 건너뛰었다
# (하류 jj-agent-room 5853b117, 2026-11-09).
sed 's/^PORT=5999$/PORT=6001/' "$CHANGED" >"$SRC/.env"
SHELL_VAR="$WORK/shell-var.expected"; cp "$SRC/.env" "$SHELL_VAR"
run_in "$SRC" PORT=6001 sync
check "셸에 같은 이름 변수가 있어도 다시 암호화한다" has "$OUT" "다시 암호화"
D="$(other_pc)"
run_in "$D" BW_BIN="$SRC_VAULT/bw" open
check "다른 PC 가 셸 변수가 아닌 파일 값을 받는다" cmp -s "$D/.env" "$SHELL_VAR"

D="$(other_pc "PORT=7001
")"; BEFORE="$(cat "$D/.env.secrets")"
run_in "$D" sync
check "열쇠가 어디에도 없어도 sync 는 실패하지 않는다" [ "$RC" -eq 0 ]
check "열쇠 없으면 .env.secrets 안 바뀜" [ "$(cat "$D/.env.secrets")" = "$BEFORE" ]

echo "== merge (env-file.mjs)"
D="$(new_repo merge)"; printf 'PORT=6001\n' >"$D/.env"
printf '{"OPENAI_API_KEY":"encrypted:%s"}' "$(rand)" \
  | ENV_SECRETS_DEPS="$CACHE" node "$ASSET_DIR/lib/env-file.mjs" merge "$D/.env" >/dev/null 2>&1
MERGE_RC=$?
check "아직 암호문인 값은 쓰지 않고 실패" [ "$MERGE_RC" -ne 0 ]
check "merge 실패 때 .env 는 그대로" [ "$(cat "$D/.env")" = "PORT=6001" ]

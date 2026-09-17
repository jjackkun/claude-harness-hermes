#!/usr/bin/env bash
# R-coexist 정적 가드 — 설치기·프리셋에 새 raw `cp` 가 생기면 빨강.
# (docs/design-docs/core-beliefs.md #r-coexist, 계획 completed/2026-09-17-install-coexistence.md 목표 1)
#
#   - 훑는 곳: lib/*.sh · presets/workflow/*.conf · project-claude.sh · project-codex.sh · public-claude.sh
#   - 허용: tests/fixtures/raw-copy-allowlist.txt (파일|부분문자열|이유) — 이유 없는 항목은 목록 자체가 빨강
#   - 자기 검사: 허용 밖 cp 를 심은 사본을 훑어 빨강이 나는지 본다 — 통과만 보는 검증 금지(08-27 §8)
#   - 허용 목록의 죽은 항목(아무 줄에도 안 맞음)은 경고가 아니라 실패 — 목록이 코드를 따라오게 한다
#
# 실행: bash tests/raw-copy-guard-test.sh

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLOW="$REPO_ROOT/tests/fixtures/raw-copy-allowlist.txt"
PASS=0; FAIL=0

assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# cp 호출 줄만 뽑는다: 주석 줄 제외, 단어 경계의 `cp` + 선택 플래그 + 공백.
# 출력: <파일 basename>:<줄번호>:<줄 내용>
_scan() { # _scan <파일...>
  grep -nHE '(^|[^A-Za-z0-9_./-])cp( -[A-Za-z]+)* ' "$@" 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | sed -E 's|^([^:]*/)?([^/:]+):|\2:|'
}

# 허용 목록 대조. 허용 밖 줄을 출력한다(없으면 무출력).
# 목록의 각 항목이 최소 한 줄에 맞았는지도 세어, 죽은 항목은 stderr 로 알린다.
_violations() { # _violations <allowlist> <파일...>
  local allow="$1"; shift
  _scan "$@" | ALLOW="$allow" python3 -c '
import os, sys
rules = []
for raw in open(os.environ["ALLOW"], encoding="utf-8"):
    line = raw.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    parts = line.split("|", 2)
    if len(parts) != 3 or not parts[2].strip():
        print("ALLOWLIST-MALFORMED: " + line); continue
    rules.append((parts[0].strip(), parts[1], parts[2].strip(), [0]))
for hit in sys.stdin:
    hit = hit.rstrip("\n")
    fname, _, rest = hit.partition(":")
    _, _, body = rest.partition(":")
    matched = False
    for f, sub, _, cnt in rules:
        if f == fname and sub in body:
            cnt[0] += 1; matched = True
    if not matched:
        print(hit)
for f, sub, _, cnt in rules:
    if cnt[0] == 0:
        print("ALLOWLIST-DEAD: %s|%s" % (f, sub), file=sys.stderr)
'
}

TARGETS=("$REPO_ROOT"/lib/*.sh "$REPO_ROOT"/presets/workflow/*.conf \
         "$REPO_ROOT/project-claude.sh" "$REPO_ROOT/project-codex.sh" "$REPO_ROOT/public-claude.sh")

echo "[1] 실 저장소 — 허용 밖 raw cp 0건, 죽은 허용 항목 0건"
ERR="$(mktemp)"; OUT="$(_violations "$ALLOW" "${TARGETS[@]}" 2>"$ERR")"
assert "허용 밖 raw cp 없음" "" "$OUT"
[[ -n "$OUT" ]] && printf '%s\n' "$OUT" | sed 's/^/      R-coexist 위반 → install_factory_file 을 쓰거나 허용 목록에 이유와 함께 적으십시오: /'
assert "허용 목록 죽은 항목 없음" "" "$(cat "$ERR")"
[[ -s "$ERR" ]] && sed 's/^/      /' "$ERR"
assert "허용 목록에 형식 불량 없음" "0" "$(printf '%s\n' "$OUT" | grep -c ALLOWLIST-MALFORMED)"
assert "훑은 cp 줄이 허용 항목 수 이상(가드가 실제로 뭔가를 봤다)" "1" \
  "$(( $(_scan "${TARGETS[@]}" | wc -l) >= $(grep -cvE '^\s*(#|$)' "$ALLOW") ))"

echo "[2] 자기 검사 — 심은 위반은 빨강, 주석 속 cp 는 무시"
T="$(mktemp -d)"; trap 'rm -rf "$T" "$ERR"' EXIT
cp "$REPO_ROOT/lib/harness_installers.sh" "$T/harness_installers.sh"
printf '\n  cp "$src_file" "$project_path/scripts/hooks/new-hook.sh"\n' >> "$T/harness_installers.sh"
printf '  # cp "$a" "$b"  주석은 무시돼야 한다\n' >> "$T/harness_installers.sh"
V="$(_violations "$ALLOW" "$T/harness_installers.sh" 2>/dev/null)"
assert "심은 raw cp 가 잡힌다" "1" "$(printf '%s\n' "$V" | grep -c 'new-hook.sh')"
assert "주석 속 cp 는 안 잡힌다" "0" "$(printf '%s\n' "$V" | grep -c '주석은')"
assert "원본에 있던 허용 줄은 여전히 통과(위반은 심은 1줄뿐)" "0" "$(printf '%s\n' "$V" | grep -v 'new-hook.sh' | grep -c .)"

echo "[3] 이유 없는 허용 항목은 목록 자체가 빨강"
printf 'harness_installers.sh|cp "$f" "$dest"|\n' > "$T/bad-allow.txt"
assert "이유 빈 항목 → MALFORMED" "1" "$(_violations "$T/bad-allow.txt" "$T/harness_installers.sh" 2>/dev/null | grep -c ALLOWLIST-MALFORMED)"

echo
echo "raw-copy-guard: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]

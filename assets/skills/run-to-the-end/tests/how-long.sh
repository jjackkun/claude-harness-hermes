#!/usr/bin/env bash
# 이 저장소의 검사 명령이 **앞에서 기다려도 되는 길이인지** 실제로 잰다.
#
# 🔴 이 스킬의 주장은 하나다 — "배경으로 돌릴 이유가 대개 없다".
#    그 주장은 **숫자에 기대고 있고, 숫자는 저장소마다 다르고 늙는다.**
#    그래서 외우게 하지 않고 재게 한다.
#
# 쓰기:
#   bash how-long.sh              빠른 것만 (린트·타입 검사)
#   bash how-long.sh --all        시험까지 (몇 분 걸릴 수 있다)
#   bash how-long.sh --list       무엇을 찾았는지만 보고 안 돌린다
set -u
# ⚠️ bash 는 한글 변수명을 못 받는다 — 이름만 영문으로 둔다

LIMIT=600   # Bash 도구가 앞에서 기다릴 수 있는 최대 초
fail=0
mode="${1:-}"

# ── 저장소 뿌리를 찾는다 ─────────────────────────────────────
root=$(git rev-parse --show-toplevel 2>/dev/null) || root="$PWD"
cd "$root" || exit 1

# ── 무엇으로 검사하나 — 있는 것만 고른다 ────────────────────
#
# ⚫ 지어내지 않는다. **파일에 실제로 있는 것만** 목록에 넣는다 —
#    없는 명령을 돌리면 "실패했다" 가 아니라 "잰 적 없다" 인데, 그 둘이
#    섞이면 이 도구가 거짓말을 하게 된다.
quick_labels=(); quick_cmds=()
slow_labels=();  slow_cmds=()

add_quick() { quick_labels+=("$1"); quick_cmds+=("$2"); }
add_slow()  { slow_labels+=("$1");  slow_cmds+=("$2"); }

has_script() {  # package.json 에 그 스크립트가 있나
  [ -f package.json ] && grep -qE "\"$1\"[[:space:]]*:" package.json
}

pm="npm run"
[ -f pnpm-lock.yaml ] && pm="pnpm"
[ -f yarn.lock ] && pm="yarn"

if [ -f package.json ]; then
  for s in lint lint:web typecheck check check:web build; do
    has_script "$s" && add_quick "$pm $s" "$pm $s"
  done
  has_script test && add_slow "$pm test" "$pm test"
fi

if [ -f pyproject.toml ] || [ -f setup.cfg ]; then
  command -v ruff >/dev/null && add_quick "ruff check" "ruff check ."
  if [ -d tests ] || [ -d test ]; then
    if command -v uv >/dev/null && [ -f uv.lock ]; then
      add_slow "pytest" "uv run pytest -q"
    elif command -v pytest >/dev/null; then
      add_slow "pytest" "pytest -q"
    fi
  fi
fi

[ -f Makefile ] && grep -qE '^test:' Makefile && add_slow "make test" "make test"

# ⚫ 셸로 검사하는 저장소도 있다 — 이 스킬이 사는 저장소가 그렇다.
#    ⚠️ 처음엔 이것을 빠뜨려 **자기 집에서 "검사 명령을 못 찾았다"** 고 했다.
for runner in tests/run-all.sh test/run-all.sh scripts/test.sh run-tests.sh; do
  [ -f "$runner" ] && add_slow "bash $runner" "bash $runner" && break
done
[ -f Cargo.toml ] && add_slow "cargo test" "cargo test -q"
[ -f go.mod ] && add_slow "go test" "go test ./..."

if [ "${#quick_labels[@]}" -eq 0 ] && [ "${#slow_labels[@]}" -eq 0 ]; then
  echo "🔴 검사 명령을 못 찾았다 ($root)."
  echo "   이 저장소의 관문을 손으로 재고, SKILL.md 가 시키는 대로 판단하라."
  exit 1
fi

# ── --list 면 여기서 끝 ──────────────────────────────────────
if [ "$mode" = "--list" ]; then
  echo "── 찾은 검사 명령 ($root)"
  for l in "${quick_labels[@]:-}"; do [ -n "$l" ] && echo "  빠름  $l"; done
  for l in "${slow_labels[@]:-}"; do [ -n "$l" ] && echo "  느림  $l   (--all 이라야 돈다)"; done
  exit 0
fi

# ── 잰다 ────────────────────────────────────────────────────
run_one() {
  local label="$1" cmd="$2" start end took code
  start=$(date +%s)
  eval "$cmd" >/dev/null 2>&1; code=$?
  end=$(date +%s); took=$((end - start))

  if [ "$took" -lt "$LIMIT" ]; then
    printf '  ✅ %-26s %4d초   (앞 한도까지 %d초 남는다)\n' "$label" "$took" "$((LIMIT - took))"
  else
    printf '  🔴 %-26s %4d초   앞 한도를 넘는다 — 이것만 배경으로 돌린다\n' "$label" "$took"
    fail=1
  fi
  # ⚫ 명령이 실패해도 시간은 잰다. 우리가 재는 것은 성패가 아니라 길이다
  [ "$code" -ne 0 ] && printf '     ⚠️ 그 명령이 실패했다 (종료 %d) — 길이만 참고한다\n' "$code"
}

echo "── 앞에서 기다려도 되나 (한도 ${LIMIT}초) · $root"
for i in "${!quick_labels[@]}"; do run_one "${quick_labels[$i]}" "${quick_cmds[$i]}"; done

if [ "$mode" = "--all" ]; then
  for i in "${!slow_labels[@]}"; do
    # ⚠️ 시험이 이미 돌고 있으면 건너뛴다 — 같은 DB·포트를 밟으면 둘 다 이상해진다
    if pgrep -f "pytest|jest|vitest|run-all.sh" >/dev/null 2>&1; then
      echo "  ⚠️ 시험이 이미 돌고 있다 — ${slow_labels[$i]} 측정을 건너뛴다"
    else
      run_one "${slow_labels[$i]}" "${slow_cmds[$i]}"
    fi
  done
elif [ "${#slow_labels[@]}" -gt 0 ]; then
  echo "  ⚫ 시험은 건너뛴다 — 재려면 --all"
fi

echo
if [ "$fail" = "0" ]; then
  echo "✅ 잰 것 전부 앞 한도 안이다. 배경으로 돌릴 이유가 없다."
else
  echo "🔴 한도를 넘는 것이 있다. 그것만 배경으로 돌리고, 같은 턴에서 결과를 읽는다."
fi
exit "$fail"

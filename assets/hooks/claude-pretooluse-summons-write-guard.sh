#!/usr/bin/env bash
# PreToolUse(Bash) hook — 세션 안에서 `summons` 테이블을 쓰는 것을 막는다.
# (identity.md §7 "state.db 는 러너가 쓰고, 세션 안 Bash 는 훅이 summons 테이블 쓰기를 막는다";
#  계획 2026-09-17-design-coverage-gaps 목표 7)
#
# 소환 토큰은 러너만 발급한다(RV-06). 세션이 sqlite3·python 으로 summons 에 INSERT/UPDATE/DELETE 를
# 하면 스스로 토큰을 만들어 시작 훅의 검증을 통과할 수 있다. 판정은 명령 문자열에서
# `summons` 와 쓰기 동사가 **함께** 보이는가 — SQL 은 따옴표 안에 오므로 따옴표를 벗기지 않는다.
# SELECT · 러너 호출(python3 scripts/hermes-summon.py …) · 다른 표의 쓰기는 통과.
# 한계: 변수 조립(`T=summ; U=ons; …${T}${U}`)·base64 같은 인코딩은 못 본다 — 결합 우회는 따옴표 제거로 막는다.
#
# 출력: 차단 시 [summons-write-guard BLOCK] … + exit 2.
set -uo pipefail
INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0
HIT="$(printf '%s' "$INPUT" | python3 -c '
import json, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if d.get("tool_name") != "Bash":
    sys.exit(0)
cmd = d.get("tool_input", {}).get("command", "") or ""
# 따옴표·백슬래시를 벗긴 뒤 본다 — `summ""ons` · `sum\mons` 같은 결합 우회를 막는다(리뷰 MEDIUM).
# 변수 조립(`${T}${U}`)·인코딩은 이 훅이 못 본다 — 심층 방어 한 겹이며, 실제 토큰 소비는
# 소환 러너 가드와 시작 훅 검증을 더 지나야 한다(identity.md §7).
cmd = re.sub(r"[\"\x27\\\\]", "", cmd)
if not re.search(r"\bsummons\b", cmd, re.I):
    sys.exit(0)
# 쓰기 동사 — SQL 키워드로서. 러너 파일명(hermes-summon.py)에는 어느 것도 없다.
if re.search(r"\b(insert|update|delete|replace|drop|alter|truncate)\b", cmd, re.I):
    print("hit")
' 2>/dev/null)"
[[ "$HIT" == "hit" ]] || exit 0
cat >&2 <<MSG
[summons-write-guard BLOCK] 세션 안에서 summons 테이블을 쓸 수 없습니다 — 소환 토큰은 러너만 발급합니다(RV-06).
  → 소환은 러너로: python3 scripts/hermes-summon.py run <에이전트> --task "…"
  근거: docs/hermes-universe/design/agent/identity.md §7
MSG
exit 2

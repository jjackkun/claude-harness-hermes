#!/usr/bin/env bash
# 진화 힌트 출처 테스트 — 사람이 친 이번 턴의 말에서만, 키워드는 단어 단위로.
#
# 배경: 세션 끝 훅의 EVOLVE 힌트가 스킬 본문·서브에이전트 반환·압축 요약에서 나와
# 소우주 3곳에서 스킬 19개가 96번 고쳐졌다(재현 48번 전부 비인간 근거).
# 대화 기록의 표시 구조(origin.kind · isMeta · isCompactSummary)는 2026-09-22 실측 그대로다.
# 근거: docs/exec-plans/completed/2026-09-22-evolve-hint-false-positive.md 목표 1~3
#
# 실행: bash tests/evolve-hint-source-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

# 대화 기록(JSONL) 한 벌을 만들고 추출 결과를 "키워드들" 로 돌려준다.
# 인자: 각 줄의 JSON (Claude Code transcript 한 줄 형식)
hints() {
  local f="$TMP/t$RANDOM.jsonl"
  printf '%s\n' "$@" > "$f"
  python3 - "$REPO_ROOT/scripts" "$f" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1])
from hermes_save_session_storage import load_transcript
from hermes_save_session_patterns import extract_evolution_hints
print(",".join(k for k, _ in extract_evolution_hints(load_transcript(sys.argv[2]))) or "none")
EOF
}

A='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"네"}]}}'
human() { printf '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"%s"}}' "$1"; }

echo "== 1. 사람이 친 메시지가 아니면 힌트가 없다 =="
assert "사람 교정은 힌트 1건" "pip" \
  "$(hints "$(human 'pip 말고 poetry 로 바꿔')" "$A")"
assert "스킬 본문(isMeta)" "none" \
  "$(hints '{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: /x  # svelte 대신 수정"}]}}' "$A")"
assert "서브에이전트 반환(peer + isMeta)" "none" \
  "$(hints '{"type":"user","isMeta":true,"origin":{"kind":"peer","from":"a1"},"message":{"role":"user","content":"Another Claude session sent a message: docker 대신 수정"}}' "$A")"
assert "작업 알림(task-notification)" "none" \
  "$(hints '{"type":"user","origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification> postgres 수정 </task-notification>"}}' "$A")"
assert "압축 요약(isCompactSummary)" "none" \
  "$(hints '{"type":"user","isCompactSummary":true,"isVisibleInTranscriptOnly":true,"message":{"role":"user","content":"This session is being continued ... pnpm 대신 npm 으로 수정"}}' "$A")"
assert "도구 결과" "none" \
  "$(hints '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"pip 대신 수정 필요"}]}}' "$A")"
assert "origin 없는 옛 기록의 사람 입력은 잡는다" "yarn" \
  "$(hints '{"type":"user","message":{"role":"user","content":"yarn 말고 pnpm 으로 바꿔"}}' "$A")"
assert "origin 없는 옛 기록의 < 주입은 뺀다" "none" \
  "$(hints '{"type":"user","message":{"role":"user","content":"<command-name>/x</command-name> ruff 대신 수정"}}' "$A")"

echo "== 2. 키워드는 단어 단위 =="
assert "pipeline 은 pip 가 아니다" "none" \
  "$(hints "$(human 'es-pipeline 을 수정해')" "$A")"
assert "pipefail 은 pip 가 아니다" "none" \
  "$(hints "$(human 'set -euo pipefail 대신 써')" "$A")"
assert "R-pipe 는 pip 가 아니다" "none" \
  "$(hints "$(human 'R-pipe 리뷰 빚 수정')" "$A")"
assert "pip install 은 pip" "pip" \
  "$(hints "$(human 'pip install 말고 uv 로')" "$A")"
assert "버전을 (한글 조사) 은 버전" "버전" \
  "$(hints "$(human '버전을 잘못 적었어')" "$A")"
assert "pnpm 안의 npm 은 npm 이 아니다" "pnpm" \
  "$(hints "$(human 'pnpm 대신 써')" "$A")"

echo "== 3. 가장 최근 사람 메시지만 본다 =="
assert "교정 뒤에 사람 메시지가 이어지면 힌트 없음" "none" \
  "$(hints "$(human 'pip 말고 poetry 로 바꿔')" "$A" "$(human '좋아 다음 진행')" "$A")"
assert "교정이 마지막 사람 메시지면 힌트" "docker" \
  "$(hints "$(human '좋아 다음 진행')" "$A" "$(human 'docker 대신 podman 으로 바꿔')" "$A")"
assert "마지막 사람 메시지 뒤의 비인간 글은 무시" "pip" \
  "$(hints "$(human 'pip 말고 poetry 로 바꿔')" "$A" '{"type":"user","isMeta":true,"message":{"role":"user","content":"svelte 대신 수정"}}')"

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]

#!/usr/bin/env bash
# 개인정보 마스킹 (T-20 ②·③, 계획 2026-09-20-transport-plain 목표 4): 주소·계좌 꼴, 자동 정답지 이름. 과마스킹 방지(날짜·main).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; S="$ROOT/scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q; git -C "$P" config user.name "홍길동테스트"; git -C "$P" config user.email t@t
git -C "$P" commit -q --allow-empty -m init
mkdir -p "$P/.hermes"; echo '{"agents":[{"agent_id":"x","name":"main","status":"active"},{"agent_id":"y","name":"선적QA담당","status":"active"}]}' > "$P/.hermes/agents.json"
OUT="$(PYTHONPATH="$S" python3 - "$P" <<'PY'
import sys
from hermes_redact import redact
p = sys.argv[1]
text = ("고객 사무실 서울 강남구 테헤란로 12 방문. 계좌 110-123-456789 로 입금. 날짜 2026-09-20 회의. "
        "담당 홍길동테스트 와 선적QA담당 이 참석. main 브랜치 병합. 버전 1.2.3 배포. 010-1234-5678 로 연락.")
print(redact(text, project_dir=p))
PY
)"
echo "$OUT"
assert "주소 → [REDACTED:ADDRESS]" 1 "$(grep -c 'REDACTED:ADDRESS' <<<"$OUT")"
assert "주소 원문 잔존 0" 0 "$(grep -c '테헤란로' <<<"$OUT")"
assert "계좌 → [REDACTED:ACCOUNT]" 1 "$(grep -c 'REDACTED:ACCOUNT' <<<"$OUT")"
assert "날짜는 안 가림(과마스킹 방지)" 1 "$(grep -c '2026-09-20' <<<"$OUT")"
assert "버전은 안 가림" 1 "$(grep -c '1\.2\.3' <<<"$OUT")"
assert "전화 여전히 가림" 1 "$(grep -c 'REDACTED:PHONE' <<<"$OUT")"
assert "git 작성자 이름 → [REDACTED:NAME](자동 정답지)" 0 "$(grep -c '홍길동테스트' <<<"$OUT")"
assert "명부 이름 → 가림" 0 "$(grep -c '선적QA담당' <<<"$OUT")"
assert "main 은 안 가림(일반어)" 1 "$(grep -c 'main 브랜치' <<<"$OUT")"
echo; echo "hermes-redact-pii: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]

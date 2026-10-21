#!/usr/bin/env bash
# 기획 문서 사슬 (계획 2026-10-21-planning-skill-chain 목표 G1) — 정적 검사만, 모델 호출 없음.
# idea-check → prd-writer → ui-prototype → 계획서 → intended-vs-implemented 가 같은 계약을 보는지 잰다.
# 망가뜨린 PRD 는 좋은 픽스처를 시험 안에서 고쳐 만든다 — 계약이 바뀌면 픽스처 하나만 고친다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SK="$REPO_ROOT/assets/skills"
CHAIN=(idea-check prd-writer intended-vs-implemented)
CONTRACT="$SK/prd-writer/references/contract.md"
CONTRACT_REF="prd-writer/references/contract.md"
CHECK="$SK/prd-writer/scripts/check_prd.py"
GOOD="$REPO_ROOT/tests/fixtures/planning-chain/prd-good.md"
README_TPL="$REPO_ROOT/assets/docs-templates/docs/product-specs/README.md"
MAX_LINES=400   # R-size 상한
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
has() { [[ -f "$1" ]] && grep -qE -- "$2" "$1" && echo 1 || echo 0; }
fm() { [[ -f "$1" ]] && awk -v k="$2" 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} index($0,k": ")==1{print substr($0,length(k)+3)}' "$1"; }
prd() { python3 "$CHECK" "$1" > "$TMP/prd.out" 2>&1; echo $?; }
saw() { grep -qF -- "$1" "$TMP/prd.out" && echo 1 || echo 0; }
broken() { cp "$GOOD" "$TMP/$1.md"; sed -i "$2" "$TMP/$1.md"; echo "$TMP/$1.md"; }

echo "[a] 세 스킬 frontmatter · 크기"
for s in "${CHAIN[@]}"; do
  f="$SK/$s/SKILL.md"
  assert "$s: name 이 폴더 이름" "$s" "$(fm "$f" name)"
  assert "$s: description 있음" 1 "$([[ -n "$(fm "$f" description)" ]] && echo 1 || echo 0)"
  over=0; while IFS= read -r x; do (( $(wc -l < "$x") > MAX_LINES )) && over=$((over+1)); done < <(find "$SK/$s" -type f 2>/dev/null)
  assert "$s: 파일마다 ${MAX_LINES}줄 이하" 0 "$over"
done

echo "[b] 계약은 한 곳 — 버전 줄이 같고 나머지는 가리킨다"
VER=$(grep -oE '^contract-version: [0-9]+' "$CONTRACT" 2>/dev/null | head -1)
assert "계약 정본에 버전 줄" 1 "$([[ -n "$VER" ]] && echo 1 || echo 0)"
assert "프로젝트 안내 README 도 같은 버전" 1 "$(has "$README_TPL" "^${VER:-NONE}$")"
for s in "${CHAIN[@]}"; do assert "$s: 같은 버전을 말한다" 1 "$(has "$SK/$s/SKILL.md" "${VER:-NONE}")"; done
for f in "$SK/idea-check/SKILL.md" "$SK/intended-vs-implemented/SKILL.md" "$SK/ui-prototype/references/spec-from-docs.md"; do
  assert "${f#$SK/}: 계약을 가리킨다" 1 "$(has "$f" "$CONTRACT_REF")"
done

echo "[c] 원본의 광고·외부 전송 문자열 0 (NOTICE 는 출처라 제외)"
hits=$(grep -rciE 'ycombinator|\.gstack|supabase|codex exec|\bcurl\b|\bwget\b' --exclude=NOTICE.md \
  "${CHAIN[@]/#/$SK/}" 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')
assert "금지 문자열 합계 0" 0 "$hits"
assert "CC BY-NC-SA 원본(deanpeters) 차용 0" 0 "$(grep -rli deanpeters "$SK" 2>/dev/null | wc -l)"

echo "[d] 출처·라이선스"
for s in "${CHAIN[@]}"; do
  n="$SK/$s/NOTICE.md"
  assert "$s: NOTICE 에 라이선스 이름" 1 "$(has "$n" 'MIT|Apache-2\.0')"
  assert "$s: NOTICE 에 바꾼 점 절" 1 "$(has "$n" '^## 바꾼 점')"
done
assert "prd-writer: Apache-2.0 차용 출처 명시" 1 "$(has "$SK/prd-writer/NOTICE.md" 'Apache-2\.0')"

echo "[e] 다음 단계 안내 한 줄"
for s in "${CHAIN[@]}" ui-prototype; do assert "$s: '다음:' 줄" 1 "$(has "$SK/$s/SKILL.md" '^다음:')"; done

echo "[f] check_prd — 계약을 지킨 PRD 통과, 망가뜨린 PRD 실패"
assert "좋은 픽스처 통과" 0 "$(prd "$GOOD")"
assert "머리 status 빠짐 → 실패" 1 "$(prd "$(broken no-status '/^- status:/d')")"; assert "  표식 [머리]" 1 "$(saw '[머리]')"
assert "유효 요구의 검증 칸 빔 → 실패" 1 "$(prd "$(broken empty-verify 's/^| FR-1 | \([^|]*\)| [^|]* |/| FR-1 | \1|  |/')")"
assert "  표식 [검증 빈칸] FR-1" 1 "$(saw '[검증 빈칸] FR-1')"
assert "FR 번호 중복 → 실패" 1 "$(prd "$(broken dup-id 's/^| FR-2 |/| FR-1 |/')")"; assert "  표식 [FR 중복]" 1 "$(saw '[FR 중복]')"
assert "FR 형식 어긋남 → 실패" 1 "$(prd "$(broken bad-id 's/^| FR-3 |/| FR3 |/')")"; assert "  표식 [FR 형식]" 1 "$(saw '[FR 형식]')"
assert "요구 표 뒤 둘째 표는 검사하지 않음 (계약: 첫 표만)" 0 "$(prd "$(broken second-table '/^| FR-4 |/a \\n| 참고 | 값 |\n|---|---|\n| 메모 | 아무거나 |')")"
assert "필수 절 빠짐 → 실패" 1 "$(prd "$(broken no-section 's/^## \([0-9]*\. \)*비범위/## 기타/')")"; assert "  표식 [절 없음] 비범위" 1 "$(saw '[절 없음] 비범위')"

echo "[g] 공통 폴더 안내 — 설치되고, 이미 있으면 덮지 않는다"
P="$TMP/proj"; mkdir -p "$P"; git -C "$P" init -q
inst() { HARNESS_DOCS_TEMPLATES=1 ASSETS_DIR="$REPO_ROOT/assets" bash -c \
  "source '$REPO_ROOT/lib/logging.sh'; source '$REPO_ROOT/lib/harness_installers.sh'; install_harness_docs_templates '$P'" >/dev/null 2>&1; }
inst
assert "설치 → docs/product-specs/README.md 생김" 1 "$([[ -f "$P/docs/product-specs/README.md" ]] && echo 1 || echo 0)"
echo "사용자가 고친 줄" >> "$P/docs/product-specs/README.md" 2>/dev/null; inst
assert "재설치 → 사용자가 고친 내용 그대로" 1 "$(has "$P/docs/product-specs/README.md" '^사용자가 고친 줄$')"

echo ""; echo "결과: 통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]]

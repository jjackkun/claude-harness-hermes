#!/usr/bin/env bash
# ui-prototype 스킬 (계획 2026-10-20-ui-prototype-skill 목표 G2·G3·G3b) — node·python 만, 브라우저 없음.
# 시작 틀을 임시 폴더에 복사해 망가뜨린 입력을 그 자리에서 만든다 — 틀이 바뀌어도 시험이 같은 틀을 본다.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/assets/skills/ui-prototype"; TPL="$SKILL/assets/template"; SC="$SKILL/scripts"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }
fresh() { rm -rf "$TMP/$1"; cp -r "$TPL" "$TMP/$1"; echo "$TMP/$1"; }
check() { python3 "$SC/check_spec.py" "$1" > "$TMP/check.out" 2>&1; echo $?; }
saw() { grep -qF -- "$1" "$TMP/check.out" && echo 1 || echo 0; }
jq_py() { python3 -c "import json,sys; d=json.load(open('$1')); print($2)"; }

echo "[G2] 시작 틀 — 문법·장면 등록·render"
bad=0; for f in "$TPL"/scripts/*.js; do node --check "$f" 2>/dev/null || bad=$((bad+1)); done
assert "스크립트 전부 node --check 통과" 0 "$bad"
assert "file:// 를 막는 ES 모듈·fetch 없음" 0 "$(grep -rlE 'type="module"|fetch\(' "$TPL" | wc -l)"
node "$SC/collect_scenes.js" "$TPL" > "$TMP/scenes.json" 2>"$TMP/scenes.err"
assert "collect_scenes 종료 0" 0 "$?"
assert "예시 장면 3개 등록" 3 "$(jq_py "$TMP/scenes.json" "len(d['scenes'])")"
assert "render 오류 0" 0 "$(jq_py "$TMP/scenes.json" "sum(1 for s in d['scenes'] if s.get('error'))")"
assert "틀이 섞임 (phone 2 · browser 1)" "browser,phone,phone" "$(jq_py "$TMP/scenes.json" "','.join(sorted(s['frame'] for s in d['scenes']))")"
assert "시작 틀은 check_spec 통과" 0 "$(check "$TPL")"
assert "시작 틀은 알림도 0 (세 장면 모두 들어오는 버튼 있음)" 0 "$(saw '[알림]')"
D=$(fresh h)
cat >> "$D/scripts/screens-example.js" <<'JS'
NB.register({ id: "EX-04", group: "관리자", name: "설정", frame: "browser", render: () => `<div class="web"><button data-go="EX-01">돌아가기</button></div>` });
JS
sed -i '/| EX-03 |/a | 1차 | 관리자 | EX-04 | 설정 | - | browser | - | 돌아가기→EX-01 | 가정 P2 |' "$D/spec.md"
assert "들어오는 버튼 없는 장면은 실패가 아니다 (목록 진입이 맞는 장면이 있다)" 0 "$(check "$D")"
assert "그래도 알림으로 EX-04 를 보여 준다" 1 "$(saw '[알림] 들어오는 버튼 없는 장면: EX-04')"

echo "[G3b] 망가뜨린 입력"
D=$(fresh a1); sed -i '/| EX-03 |/d' "$D/spec.md"
assert "(a) 등록됐는데 명세표에 없는 장면 → 실패" 1 "$(check "$D")"; assert "(a) 표식 [불일치]" 1 "$(saw '[불일치]')"
D=$(fresh a2); sed -i '/| EX-03 |/a | 1차 | 관리자 | EX-04 | 빠진 화면 | - | browser | - | - | 가정 P2 |' "$D/spec.md"
assert "(a) 1차 명세 장면이 등록 안 됨 → 실패" 1 "$(check "$D")"; assert "(a) 빠진 번호 EX-04 를 말한다" 1 "$(saw 'EX-04')"
D=$(fresh b); sed -i 's/data-go="EX-03"/data-go="ZZ-09"/' "$D/scripts/screens-example.js"
assert "(b) 명세표에 없는 data-go 대상 → 실패" 1 "$(check "$D")"; assert "(b) 표식 [끊김] EX-02 → ZZ-09" 1 "$(saw 'EX-02 → ZZ-09')"
D=$(fresh c); sed -i 's/<!-- ui-prototype:requires -->/<!-- ui-prototype:requires REQ-01 REQ-02 -->/' "$D/spec.md"
sed -i 's/| 가정 P2 |/| REQ-01, 가정 P2 |/' "$D/spec.md"
assert "(c) 범위 안 요구 ID 누락 → 실패" 1 "$(check "$D")"; assert "(c) 빠진 REQ-02 만 말한다" "1 0" "$(saw '[요구 누락] REQ-02') $(saw '[요구 누락] REQ-01')"
D=$(fresh d); sed -i 's/| EX-01 | 목록 |/| 목록-01 | 목록 |/' "$D/spec.md"
assert "(d) 허용 밖 글자가 든 화면 번호 → 실패" 1 "$(check "$D")"; assert "(d) 표식 [번호] 목록-01" 1 "$(saw '[번호] 목록-01')"
D=$(fresh e); printf '(function (NB) {})(window.NB);\n' > "$D/scripts/screens-extra.js"
assert "(e) index.html 에 로드 태그가 빠진 화면 파일 → 실패" 1 "$(check "$D")"; assert "(e) 표식 [로드] scripts/screens-extra.js" 1 "$(saw '[로드] scripts/screens-extra.js')"
D=$(fresh f); sed -i 's/| phone | 항목 목록 |/| tablet | 항목 목록 |/' "$D/spec.md"
assert "(f) 명세 틀과 등록 틀이 다름 → 실패" 1 "$(check "$D")"; assert "(f) 표식 [틀] EX-01" 1 "$(saw '[틀] EX-01')"
D=$(fresh g); sed -i 's/| 앱 화면으로→EX-01 |/| 앱 화면으로→EX-01; 상세 열기→EX-02 |/' "$D/spec.md"
assert "(g) 명세표 행동이 화면에 없음 → 실패" 1 "$(check "$D")"; assert "(g) 표식 [행동] EX-03 → EX-02" 1 "$(saw '[행동] EX-03 → EX-02')"

echo "[G3] 단일 HTML · 아티팩트용 파일"
D=$(fresh build); echo 'NB.content.trap = "</script><b>x</b>";' >> "$D/scripts/content.js"
python3 "$SC/build_single.py" "$D" --out "$TMP/one.html" --artifact "$TMP/art.html" > "$TMP/build.out" 2>&1
assert "build 종료 0" 0 "$?"
assert "로컬 CSS 참조 0" 0 "$(grep -cE '<link[^>]+href="(styles|\.\./)' "$TMP/one.html")"
assert "로컬 JS 참조 0" 0 "$(grep -cE '<script[^>]+src=' "$TMP/one.html")"
assert "문서 뼈대 포함 (doctype)" 1 "$(head -c 15 "$TMP/one.html" | grep -ci '<!doctype html')"
python3 - "$TMP/one.html" "$TMP/inline" <<'PY'
import sys, html.parser, os
class P(html.parser.HTMLParser):
    def __init__(s): super().__init__(); s.on=False; s.buf=[]; s.out=[]
    def handle_starttag(s,t,a): s.on = t == "script"
    def handle_endtag(s,t):
        if t == "script": s.out.append("".join(s.buf)); s.buf=[]; s.on=False
    def handle_data(s,d):
        if s.on: s.buf.append(d)
p=P(); p.feed(open(sys.argv[1]).read()); os.makedirs(sys.argv[2], exist_ok=True)
for i,c in enumerate(p.out): open(f"{sys.argv[2]}/{i}.js","w").write(c)
PY
bad=0; n=0; for f in "$TMP"/inline/*.js; do n=$((n+1)); node --check "$f" 2>/dev/null || bad=$((bad+1)); done
assert "인라인 스크립트 7개 (파일 6 + 시작) 모두 문법 통과 — </script 가 잘 막힘" "7 0" "$n $bad"
assert "아티팩트용 첫 글자가 <title>" "<title>" "$(head -c 7 "$TMP/art.html")"
# 스크립트·스타일·주석 안의 글자(예: 주석 속 "<html data-narrow>")는 태그가 아니므로 빼고 본다
skeleton=$(python3 -c "import re,sys; t=re.sub(r'(?is)<script\b.*?</script>|<style\b.*?</style>|<!--.*?-->','',open(sys.argv[1]).read()); print(len(re.findall(r'(?i)<html[ >]|<head[ >]|<body[ >]|</body>|<!doctype',t)))" "$TMP/art.html")
assert "아티팩트용에 doctype·html·head·body 태그 없음 (<header 는 화면 태그라 제외)" 0 "$skeleton"
assert "화면 안 <header> 는 그대로 남음" 1 "$([[ $(grep -c '<header' "$TMP/art.html") -gt 0 ]] && echo 1 || echo 0)"
assert "아티팩트용에 viewport-fit-sides 메타는 남음" 1 "$(grep -c 'claude:viewport-fit-sides' "$TMP/art.html")"
D=$(fresh ext); sed -i 's#</head>#<script src="https://cdn.example.com/x.js"></script></head>#' "$D/index.html"
python3 "$SC/build_single.py" "$D" --out "$TMP/x.html" >/dev/null 2>&1; assert "허용 목록 밖 외부 참조 → build 실패" 1 "$?"
D=$(fresh miss); rm "$D/styles/frames.css"
python3 "$SC/build_single.py" "$D" --out "$TMP/x.html" >/dev/null 2>&1; assert "참조 파일이 없으면 → build 실패" 1 "$?"

echo "[공유] 한 저장소 두 시안 — ../ 로 토큰·등록부 재사용"
mkdir -p "$TMP/protos"; cp -r "$TPL" "$TMP/protos/app"; cp -r "$TPL" "$TMP/protos/admin"
B="$TMP/protos/admin"; rm -r "$B/styles/tokens.css" "$B/scripts/shell"
sed -i 's#href="styles/tokens.css"#href="../app/styles/tokens.css"#; s#src="scripts/shell/#src="../app/scripts/shell/#g' "$B/index.html"
node "$SC/collect_scenes.js" "$B" > "$TMP/b.json" 2>/dev/null
assert "공유 파일을 쓰는 시안도 장면 3개" 3 "$(jq_py "$TMP/b.json" "len(d['scenes'])")"
python3 "$SC/build_single.py" "$B" --out "$TMP/b.html" >/dev/null 2>&1; assert "공유 파일을 쓰는 시안도 build 통과" 0 "$?"
assert "../ 파일이 펼쳐짐 (registry 의 ID_RE 가 들어 있음)" 1 "$(grep -c 'const ID_RE' "$TMP/b.html")"

echo; echo "ui-prototype-build: PASS=$PASS FAIL=$FAIL"; [[ $FAIL -eq 0 ]]

#!/usr/bin/env bash
# video-to-interaction 스킬 (계획 2026-10-22-video-to-interaction-skill 목표 G1·G2·G3) — 모델 0, 브라우저 없음.
# [구조] 흐름 ①~⑦ 과 참고 문서 · [추출] 2초 시험 영상 → 프레임 20 · 묶음 3 · 확대 1 · [천] node 로 찢김·되돌림
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/assets/skills/video-to-interaction"; VF="$SKILL/scripts/video_frames.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; SKIP=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

echo "[구조] SKILL.md · 참고 문서 · 예시"
assert "SKILL.md 의 name 이 폴더 이름과 같다" "video-to-interaction" "$(sed -n 's/^name: *//p' "$SKILL/SKILL.md" 2>/dev/null | head -1)"
assert "흐름 절 ①~⑦ 일곱 개" 7 "$(grep -cE '^## [①②③④⑤⑥⑦]' "$SKILL/SKILL.md" 2>/dev/null)"
missing=0; for f in references/observation.md references/techniques.md references/verification.md assets/cloth/cloth.js assets/cloth/render.js evals/evals.json; do [[ -f "$SKILL/$f" ]] || missing=$((missing+1)); done
assert "참고 문서 3 · 예시 2 · 평가 질문 파일 모두 있음" 0 "$missing"
assert "SKILL.md 가 가리키는 참고 문서가 실제로 있다" 0 "$(grep -oE 'references/[a-z-]+\.md' "$SKILL/SKILL.md" 2>/dev/null | sort -u | while read -r r; do [[ -f "$SKILL/$r" ]] || echo x; done | wc -l)"
bad=0; for f in "$SKILL"/assets/cloth/*.js; do node --check "$f" 2>/dev/null || bad=$((bad+1)); done
assert "예시 스크립트 node --check 통과" 0 "$bad"
assert "예시에 ES 모듈 문법 없음 (file:// 로 열면 막힌다)" 0 "$(grep -lE '^(import|export) ' "$SKILL"/assets/cloth/*.js 2>/dev/null | wc -l)"
bash -n "$VF" 2>/dev/null; assert "video_frames.sh 문법 통과" 0 "$?"

echo "[추출] 2초·30fps 시험 영상"
FF=$(VIDEO_UV_CACHE="$REPO_ROOT/.harness/out/uv-cache" bash "$VF" ffmpeg 2>"$TMP/ff.err")
if [[ -z "$FF" ]]; then
  echo "  - SKIP ffmpeg 를 구하지 못함: $(cat "$TMP/ff.err")"; SKIP=$((SKIP+1))
else
  "$FF" -loglevel error -y -f lavfi -i "testsrc=size=640x360:rate=30" -t 2 -c:v libx264 -pix_fmt yuv420p "$TMP/clip.mp4" 2>/dev/null \
    || "$FF" -loglevel error -y -f lavfi -i "testsrc=size=640x360:rate=30" -t 2 "$TMP/clip.mp4"
  export VIDEO_FFMPEG="$FF"
  assert "probe 가 길이를 말한다" 1 "$(bash "$VF" probe "$TMP/clip.mp4" | grep -c 'Duration: 00:00:02')"
  bash "$VF" sheets "$TMP/clip.mp4" "$TMP/out" "320:180:0:0" > "$TMP/sheets.out"
  assert "10fps 전수 → 프레임 20장" 20 "$(ls "$TMP/out/f" | wc -l)"
  assert "8장 묶음 → 3장" 3 "$(ls "$TMP/out/sheets" | wc -l)"
  assert "묶음 시간 안내 (0.8초 간격)" 1 "$(grep -c '0.8초' "$TMP/sheets.out")"
  bash "$VF" zoom "$TMP/out" 5 6 "160:90:0:0" moment > /dev/null
  assert "확대 묶음 한 장" 1 "$(ls "$TMP/out/zoom/moment.png" 2>/dev/null | wc -l)"
  bash "$VF" zoom "$TMP/out" 99 4 "160:90:0:0" none > /dev/null 2>&1
  assert "없는 프레임 확대 → 사용 오류(2)" 2 "$?"
  bash "$VF" sheets "$TMP/nothing.mp4" "$TMP/x" > /dev/null 2>&1
  assert "없는 영상 → 사용 오류(2)" 2 "$?"
fi

echo "[천] cloth.js — 반쪽권 찢김 · 본권 끌기 · 되돌림"
node - "$SKILL/assets/cloth/cloth.js" > "$TMP/cloth.out" 2>&1 <<'JS'
const fs = require('fs'); global.window = {}; eval(fs.readFileSync(process.argv[2], 'utf8'));
const { TK } = window, W = 290, H = 516, SEAM = 372;
const P = (c, i) => [c.pos[i * 3], c.pos[i * 3 + 1], c.pos[i * 3 + 2]];
const drag = (c, i, dx, dy, n, opt) => { const [x, y, z] = P(c, i); c.grab(i, x, y, z - 24);
  for (let s = 1; s <= n; s++) { const k = s / n; c.move(x + dx * k, y + dy * Math.sin(k * Math.PI * 0.6), z - 24); c.step(opt); } };
// 1) 반쪽권 오른쪽 아래 끝을 잡고 왼쪽 아래로 (미리보기의 "떼기 시연" 손길)
let c = TK.createCloth({ w: W, h: H, seam: SEAM });
drag(c, c.stubCorner(), -W * 0.9, H * 0.35, 66, { anchorMain: 0.25, anchorStub: 0, flip: 0, fall: 0.9, tear: true });
const torn = c.tornRatio();
// 2) 본권 위쪽을 잡고 크게 끌면 찢기지 않고, 놓으면 평평하게 돌아온다
c = TK.createCloth({ w: W, h: H, seam: SEAM });
drag(c, 6, 150, 110, 30, { anchorMain: 0.008, anchorStub: 0.008, flip: 0, fall: 0.9, tear: false });
let depth = 0; for (let i = 2; i < c.pos.length; i += 3) depth = Math.max(depth, Math.abs(c.pos[i]));
c.release(); for (let s = 0; s < 240; s++) c.step({ anchorMain: 0.06, anchorStub: 0.06, flip: 0, fall: 0.9, tear: false });
let flat = 0; for (let i = 2; i < c.pos.length; i += 3) flat = Math.max(flat, Math.abs(c.pos[i]));
console.log(JSON.stringify({ torn, mainTorn: c.tornRatio(), depth: Math.round(depth), flat: Math.round(flat * 10) / 10 }));
JS
r=$(tail -1 "$TMP/cloth.out")
val() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print($2)" "$r" 2>/dev/null; }
assert "반쪽권을 끝까지 당기면 100% 찢긴다" "1" "$(val "" "int(d['torn'] == 1)")"
assert "본권만 끌면 찢기지 않는다" "0" "$(val "" "d['mainTorn']")"
assert "끄는 동안 면이 접힌다 (깊이 > 10px)" "True" "$(val "" "d['depth'] > 10")"
assert "놓고 4초 뒤 평평 (깊이 < 1px)" "True" "$(val "" "d['flat'] < 1")"
[[ $FAIL -gt 0 ]] && sed 's/^/    /' "$TMP/cloth.out" | tail -5

echo; echo "video-to-interaction: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"; [[ $FAIL -eq 0 ]]

#!/usr/bin/env bash
# watch 스킬 (계획 2026-11-16-watch-skill 목표 G1·G3·G4) — 모델 0, 네트워크 0.
# [구조] SKILL.md·평가 질문·프리셋 등록 · [자막] vtt → [MM:SS] 정리 · [받기] 가짜 uv 로 yt-dlp 호출 인자 · [장면] video_frames.sh 위임
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/assets/skills/watch"; W="$SKILL/scripts/watch.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; PASS=$((PASS+1)); else echo "  ✗ $1 (expected=$2 actual=$3)"; FAIL=$((FAIL+1)); fi; }

echo "[구조] SKILL.md · 평가 질문 · 프리셋"
assert "SKILL.md 의 name 이 폴더 이름과 같다" "watch" "$(sed -n 's/^name: *//p' "$SKILL/SKILL.md" | head -1)"
assert "흐름 절 ①~⑤ 다섯 개" 5 "$(grep -cE '^## [①②③④⑤]' "$SKILL/SKILL.md")"
assert "기록 틀이 기존 docs/videos 절 이름을 담는다" 4 "$(grep -cE '^(## 개요|### 타임라인|## 본 프로젝트와의 접점|## 부록 — 확인 방법과 한계)' "$SKILL/SKILL.md")"
assert "evals.json 이 JSON 이고 질문 3개" 3 "$(python3 -c "import json;print(len(json.load(open('$SKILL/evals/evals.json'))['evals']))" 2>/dev/null)"
assert "workflow 프리셋에 등록" 1 "$(grep -cE '^\s+watch$' "$REPO_ROOT/presets/workflow/harness.conf")"
assert "video-to-interaction 과 같은 프리셋 (ffmpeg 찾기 위임)" 1 "$(grep -cE '^\s+video-to-interaction$' "$REPO_ROOT/presets/workflow/harness.conf")"
bash -n "$W"; assert "watch.sh 문법 통과" 0 "$?"
assert "전역 설치 명령 없음 (pip install · apt · npm -g)" 0 "$(grep -cE 'pip install|apt(-get)? install|npm i(nstall)? -g' "$W")"

echo "[자막] vtt → [MM:SS] 본문"
cat > "$TMP/a.vtt" <<'VTT'
WEBVTT
Kind: captions
Language: ko

00:00:00.160 --> 00:00:01.990 align:start position:0%

아,<00:00:00.400><c> 저는</c><00:00:00.640><c> 그냥</c>

00:00:01.990 --> 00:00:02.000 align:start position:0%
아, 저는 그냥


00:01:05.000 --> 00:01:07.000 align:start position:0%
아, 저는 그냥
절대 안 날립니다.
VTT
"$W" text "$TMP/a.vtt" > "$TMP/a.txt" 2>/dev/null || bash "$W" text "$TMP/a.vtt" > "$TMP/a.txt"
assert "되풀이 줄은 한 번만 (2줄)" 2 "$(wc -l < "$TMP/a.txt")"
assert "첫 줄 시각·태그 제거" "[00:00] 아, 저는 그냥" "$(sed -n 1p "$TMP/a.txt")"
assert "1분 넘는 시각" "[01:05] 절대 안 날립니다." "$(sed -n 2p "$TMP/a.txt")"
bash "$W" text "$TMP/none.vtt" > /dev/null 2>&1; assert "없는 자막 → 사용 오류(2)" 2 "$?"

echo "[받기] 가짜 uv 로 yt-dlp 호출 확인 (네트워크 0)"
mkdir -p "$TMP/home/.local/bin"
cat > "$TMP/home/.local/bin/uv" <<'UV'
#!/usr/bin/env bash
echo "$*" >> "$UV_LOG"
out=$(printf '%s\n' "$@" | grep -A1 '^-o$' | tail -1); dir=$(dirname "$out")
if printf '%s\n' "$@" | grep -q -- '--skip-download'; then
  echo '{"title":"T","channel":"C","duration":28,"description":"D","webpage_url":"U","chapters":[{"start_time":0,"title":"시작"}]}' > "$dir/video.info.json"
  echo WEBVTT > "$dir/video.ko.vtt"
else
  echo x > "$dir/video.mp4"
fi
UV
chmod +x "$TMP/home/.local/bin/uv"
printf '#!/usr/bin/env bash\n[[ $1 == ffmpeg ]] && echo /fake/ffmpeg\n' > "$TMP/vf-ff.sh"
SAFE_PATH="/nonexistent:$(dirname "$(command -v bash)"):$(dirname "$(command -v python3)")"
UV_LOG="$TMP/uv.log" HOME="$TMP/home" PATH="$SAFE_PATH" WATCH_VIDEO_FRAMES="$TMP/vf-ff.sh" \
  bash "$W" fetch "https://youtu.be/x" "$TMP/out" > "$TMP/fetch.out" 2>&1
assert "PATH 에 uv 가 없어도 ~/.local/bin/uv 로 두 번 부른다 (자막·영상)" 2 "$(wc -l < "$TMP/uv.log")"
assert "yt-dlp 최신판을 받게 한다 (--refresh-package)" 2 "$(grep -c -- '--refresh-package yt-dlp --from yt-dlp yt-dlp' "$TMP/uv.log")"
assert "자막은 원어 기본값" 1 "$(grep -c -- '--sub-langs ko,ko-orig,en-orig' "$TMP/uv.log")"
assert "영상은 720p 이하" 1 "$(grep -c 'height<=720' "$TMP/uv.log")"
assert "ffmpeg 가 있으면 화면·소리를 mp4 로 합친다" 1 "$(grep -c -- '--ffmpeg-location /fake/ffmpeg --merge-output-format mp4' "$TMP/uv.log")"
: > "$TMP/uv.log"; printf '#!/usr/bin/env bash\nexit 2\n' > "$TMP/vf-none.sh"
UV_LOG="$TMP/uv.log" HOME="$TMP/home" PATH="$SAFE_PATH" WATCH_VIDEO_FRAMES="$TMP/vf-none.sh" \
  bash "$W" fetch "https://youtu.be/x" "$TMP/out2" > /dev/null 2>&1
assert "ffmpeg 가 없으면 합칠 필요 없는 형식만 (+ba 없음)" 0 "$(grep -c -- '+ba' "$TMP/uv.log")"
assert "fetch 가 자막·영상 위치를 알린다" 2 "$(grep -cE '^(자막|영상): .*video\.' "$TMP/fetch.out")"
bash "$W" info "$TMP/out" > "$TMP/info.out" 2>&1
assert "info 가 길이를 분:초로" 1 "$(grep -c '길이: 0:28 (28초)' "$TMP/info.out")"
assert "info 가 챕터를 보인다" 1 "$(grep -c '챕터 0:00:00 시작' "$TMP/info.out")"

echo "[장면] video_frames.sh 위임"
printf '#!/usr/bin/env bash\necho "$*"\n' > "$TMP/vf.sh"; echo x > "$TMP/v.mp4"
got=$(WATCH_VIDEO_FRAMES="$TMP/vf.sh" bash "$W" frames "$TMP/v.mp4" "$TMP/fr" 4)
assert "4초 간격 → sheets 에 fps 0.25" "sheets $TMP/v.mp4 $TMP/fr  0.25" "$got"
WATCH_VIDEO_FRAMES="$TMP/none.sh" bash "$W" frames "$TMP/v.mp4" "$TMP/fr" > /dev/null 2>&1
assert "video_frames.sh 가 없으면 사용 오류(2)" 2 "$?"
assert "기본 경로가 형제 스킬 video-to-interaction 을 가리킨다" 1 "$(grep -c 'video-to-interaction/scripts/video_frames.sh' "$W")"

echo; echo "watch: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]

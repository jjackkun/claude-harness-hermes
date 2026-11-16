#!/usr/bin/env bash
# 영상 보기 도구 — 유튜브 URL 에서 정보·자막·영상 받기 · 자막을 [MM:SS] 글로 정리 · 장면 묶음.
#
#   watch.sh fetch  <URL> <출력폴더> [자막 언어]   # info.json · 자막(vtt) · 720p 이하 영상(video.*)
#   watch.sh info   <출력폴더>                      # 제목 · 채널 · 길이 · 설명 · 챕터
#   watch.sh text   <자막.vtt>                      # 태그·중복 줄을 지운 "[MM:SS] 본문" 을 표준 출력으로
#   watch.sh frames <영상> <출력폴더> [간격(초)]    # 간격마다 한 장 → 8장 묶음 (video_frames.sh sheets 에 맡긴다)
#
# yt-dlp 는 uv 캐시의 **최신판**을 쓴다(전역 설치 없음). 낡은 판은 유튜브가 바뀌면 403 을 낸다(2026-09-05·10-06 실측).
# ffmpeg 는 같은 프리셋에 깔리는 video-to-interaction 의 video_frames.sh 가 찾는다(시스템 → uv 캐시).
# 출력 폴더는 git 이 무시하는 곳(.harness/out/ 등)에 둔다. 기록으로 남길 것만 docs/videos/ 로 옮긴다.
set -euo pipefail

SUB_LANGS_DEFAULT="ko,ko-orig,en-orig"   # 원어 자막 우선. 자동 번역(en 등)은 429 를 잘 낸다(2026-11-16 실측)
MAX_HEIGHT=720
FRAME_INTERVAL_DEFAULT=2                 # 초. 쇼츠·슬라이드 강의는 2~5초면 화면이 바뀌는 곳을 잡는다
UV_CACHE="${VIDEO_UV_CACHE:-.harness/out/uv-cache}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIDEO_FRAMES="${WATCH_VIDEO_FRAMES:-$HERE/../../video-to-interaction/scripts/video_frames.sh}"

die() { echo "watch: $*" >&2; exit 2; }

# uv 는 PATH 가 먼저, 없으면 설치 기본 자리 — 비로그인 셸은 ~/.local/bin 을 PATH 에 넣지 않는다
find_uv() {
  if command -v uv >/dev/null 2>&1; then command -v uv; return; fi
  local c
  for c in "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv"; do [[ -x "$c" ]] && { echo "$c"; return; }; done
  return 1
}

ytdlp() {
  local uv
  uv=$(find_uv) || die "uv 가 없습니다. uv 를 설치하면 yt-dlp 는 따로 깔지 않아도 됩니다(전역 yt-dlp 설치는 사용자가 정할 일)"
  local js=(); command -v node >/dev/null 2>&1 && js=(--js-runtimes node --remote-components ejs:github)
  UV_CACHE_DIR="$UV_CACHE" "$uv" tool run --refresh-package yt-dlp --from yt-dlp yt-dlp "${js[@]}" "$@"
}

fetch() {
  local url=$1 out=$2 langs=${3:-$SUB_LANGS_DEFAULT}
  mkdir -p "$out"
  # 자막 실패(429 등)가 영상 받기를 막지 않게 두 번에 나눈다
  ytdlp --skip-download --write-info-json --write-subs --write-auto-subs --sub-langs "$langs" --sub-format vtt \
    --ignore-errors -o "$out/video.%(ext)s" "$url" > "$out/fetch-subs.log" 2>&1 || true
  # 화면·소리를 합치려면 yt-dlp 에 ffmpeg 가 필요하다. 없으면 합치지 않아도 되는 형식(화면만 또는 합쳐진 것)을 받는다
  local ff fmt=(-f "bv*[height<=$MAX_HEIGHT]/b[height<=$MAX_HEIGHT]/b")
  ff=$(bash "$VIDEO_FRAMES" ffmpeg 2>/dev/null) || ff=""
  [[ -n "$ff" ]] && fmt=(-f "bv*[height<=$MAX_HEIGHT]+ba/b[height<=$MAX_HEIGHT]/b" --ffmpeg-location "$ff" --merge-output-format mp4)
  ytdlp "${fmt[@]}" -o "$out/video.%(ext)s" "$url" > "$out/fetch-video.log" 2>&1 \
    || echo "영상 본체 받기 실패 — $out/fetch-video.log 의 ERROR 줄을 보십시오(자막만으로 진행 가능)" >&2
  echo "정보: $(ls "$out"/*.info.json 2>/dev/null | head -1)"
  echo "자막: $(ls "$out"/*.vtt 2>/dev/null | tr '\n' ' ')"
  echo "영상: $(ls "$out"/video.* 2>/dev/null | grep -vE '\.(vtt|json|log)$' | tr '\n' ' ')"
  ls "$out"/*.vtt >/dev/null 2>&1 || echo "자막 없음 — 장면과 설명만으로 보고, 보고서에 '자막 없음' 을 적는다" >&2
}

info() {
  local f
  f=$(ls "$1"/*.info.json 2>/dev/null | head -1) || true
  [[ -n "$f" ]] || die "info.json 이 없습니다 — fetch 를 먼저 돌리세요"
  python3 -I - "$f" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
s = int(d.get("duration") or 0)
print(f"제목: {d.get('title')}\n채널: {d.get('channel') or d.get('uploader')}\n길이: {s//60}:{s%60:02d} ({s}초)\n올린 날: {d.get('upload_date')}\nURL: {d.get('webpage_url')}")
for c in d.get("chapters") or []:
    t = int(c["start_time"]); print(f"챕터 {t//3600}:{t%3600//60:02d}:{t%60:02d} {c['title']}")
print("--- 설명 ---\n" + (d.get("description") or "(없음)"))
PY
}

# WebVTT → "[MM:SS] 본문". 자동 자막은 같은 줄이 다음 블록에 되풀이되므로 처음 나온 줄만 남긴다
text() {
  [[ -f "$1" ]] || die "text <자막.vtt>"
  awk '
    /-->/ { split($1, t, ":"); n = length(t); m = (n == 3) ? t[1]*60 + t[2] : t[1]; s = int(t[n]); ts = sprintf("[%02d:%02d]", m, s); next }
    /^(WEBVTT|Kind:|Language:)/ || /^[[:space:]]*$/ { next }
    { gsub(/<[^>]*>/, ""); gsub(/&nbsp;/, " "); sub(/[[:space:]]+$/, "") }
    $0 != "" && !seen[$0]++ { print ts " " $0 }
  ' "$1"
}

frames() {
  local video=$1 out=$2 every=${3:-$FRAME_INTERVAL_DEFAULT}
  [[ -f "$video" ]] || die "frames <영상> <출력폴더> [간격(초)]"
  [[ -f "$VIDEO_FRAMES" ]] || die "video_frames.sh 가 없습니다($VIDEO_FRAMES) — video-to-interaction 스킬이 함께 깔려야 합니다"
  VIDEO_UV_CACHE="$UV_CACHE" bash "$VIDEO_FRAMES" sheets "$video" "$out" "" "$(awk "BEGIN{print 1/$every}")"
}

cmd=${1:-}; shift || true
case "$cmd" in
  fetch)  [[ $# -ge 2 ]] || die "fetch <URL> <출력폴더> [자막 언어]"; fetch "$@" ;;
  info)   [[ $# -ge 1 ]] || die "info <출력폴더>"; info "$1" ;;
  text)   [[ $# -ge 1 ]] || die "text <자막.vtt>"; text "$1" ;;
  frames) [[ $# -ge 2 ]] || die "frames <영상> <출력폴더> [간격(초)]"; frames "$@" ;;
  *) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

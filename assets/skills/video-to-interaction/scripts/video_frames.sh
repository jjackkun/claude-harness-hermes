#!/usr/bin/env bash
# 참고 영상 전수 관찰 도구 — ffmpeg 찾기 · 영상 정보 · 자르기 범위용 전체 화면 · 전수 추출 + 8장 묶음 · 확대 묶음.
#
#   video_frames.sh ffmpeg                                   # 쓸 ffmpeg 경로 (H.264 를 푸는 것)
#   video_frames.sh probe  <영상>                             # 길이 · 크기 · fps
#   video_frames.sh full   <영상> <출력폴더>                   # 1초 간격 전체 화면 → 출력/full/ (자를 범위 정하기용)
#   video_frames.sh sheets <영상> <출력폴더> [자르기] [fps]     # 전수 추출 → 출력/f/ , 8장 묶음 → 출력/sheets/
#   video_frames.sh zoom   <출력폴더> <시작 프레임> <장 수> <자르기> <이름>   # 원본 해상도 확대 묶음 → 출력/zoom/<이름>.png
#
# 자르기 = ffmpeg crop 값 "폭:높이:x:y" (예 1342:773:94:62). 출력 폴더는 git 이 무시하는 곳(.harness/out/ 등)에 둔다.
# ffmpeg 순서: $VIDEO_FFMPEG → 시스템 ffmpeg(H.264 디코더가 있을 때만) → uv 로 imageio-ffmpeg 를 프로젝트 안 캐시에 받는다.
# 전역 설치는 하지 않는다 — Playwright 내장 ffmpeg 는 H.264 를 못 풀어 쓸 수 없다(2026-10-21 실측).
set -euo pipefail

FPS_DEFAULT=10          # 0.1초 간격 — 2fps(0.5초)로는 구멍·끈적임·휘며 돎을 놓쳤다(2026-10-21)
SHEET_COLS=2; SHEET_ROWS=4   # 8장 묶음 — 한 번에 읽어도 프레임마다 글자가 읽히는 크기
SHEET_FRAME_W=760       # 묶음 안 프레임 폭(px)
IMAGEIO_FFMPEG=imageio-ffmpeg==0.6.0
UV_CACHE="${VIDEO_UV_CACHE:-.harness/out/uv-cache}"

die() { echo "video_frames: $*" >&2; exit 2; }

find_ffmpeg() {
  if [[ -n "${VIDEO_FFMPEG:-}" ]]; then echo "$VIDEO_FFMPEG"; return; fi
  if command -v ffmpeg >/dev/null 2>&1 && ffmpeg -hide_banner -decoders 2>/dev/null | grep -q ' h264 '; then command -v ffmpeg; return; fi
  command -v uv >/dev/null 2>&1 || die "ffmpeg 가 없습니다. VIDEO_FFMPEG=<경로> 로 알려 주거나 uv 를 설치해 주세요(전역 ffmpeg 설치는 사용자가 정할 일)"
  local p
  p=$(UV_CACHE_DIR="$UV_CACHE" uv run --no-project --with "$IMAGEIO_FFMPEG" python -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())" 2>/dev/null) \
    || die "uv 로 $IMAGEIO_FFMPEG 를 받지 못했습니다(네트워크 확인)"
  echo "$p"
}

cmd=${1:-}; shift || true
case "$cmd" in
  ffmpeg) find_ffmpeg ;;
  probe)
    [[ $# -ge 1 && -f "$1" ]] || die "probe <영상>"
    "$(find_ffmpeg)" -hide_banner -i "$1" 2>&1 | grep -E 'Duration|Video:' | sed -E 's/^ +//' || true ;;
  full)
    [[ $# -ge 2 && -f "$1" ]] || die "full <영상> <출력폴더>"
    mkdir -p "$2/full"
    "$(find_ffmpeg)" -loglevel error -y -i "$1" -vf fps=1 "$2/full/f%03d.png"
    echo "전체 화면 $(ls "$2/full" | wc -l)장 → $2/full/ (UI 가 있는 범위를 보고 자르기 값을 정한다)" ;;
  sheets)
    [[ $# -ge 2 && -f "$1" ]] || die "sheets <영상> <출력폴더> [자르기] [fps]"
    video=$1 out=$2 crop=${3:-} fps=${4:-$FPS_DEFAULT}
    ff=$(find_ffmpeg); rm -rf "$out/f" "$out/sheets"; mkdir -p "$out/f" "$out/sheets"
    vf="fps=$fps"; [[ -n "$crop" ]] && vf="$vf,crop=$crop"
    "$ff" -loglevel error -y -i "$video" -vf "$vf" "$out/f/f%04d.png"
    "$ff" -loglevel error -y -framerate "$fps" -i "$out/f/f%04d.png" \
      -vf "scale=$SHEET_FRAME_W:-1,tile=${SHEET_COLS}x${SHEET_ROWS}:padding=4:color=red" "$out/sheets/s%02d.png"
    frames=$(ls "$out/f" | wc -l) sheets=$(ls "$out/sheets" | wc -l) per=$((SHEET_COLS * SHEET_ROWS))
    echo "프레임 ${frames}장 · 묶음 ${sheets}장 (묶음 n 은 $(awk "BEGIN{print $per/$fps}")초 × (n-1) 부터, 왼쪽→오른쪽·위→아래)"
    echo "→ $out/sheets/ 를 **전부** 읽는다. 하나라도 건너뛰면 그 사이 효과를 놓친다" ;;
  zoom)
    [[ $# -ge 5 ]] || die "zoom <출력폴더> <시작 프레임> <장 수> <자르기> <이름>"
    out=$1 start=$2 count=$3 crop=$4 name=$5
    [[ -f "$out/f/$(printf 'f%04d.png' "$start")" ]] || die "$out/f/ 에 $start 번 프레임이 없습니다 — sheets 를 먼저 돌리세요"
    cols=4; [[ $count -le 4 ]] && cols=2
    rows=$(( (count + cols - 1) / cols ))
    mkdir -p "$out/zoom"
    # 묶음 한 장만 쓴다: select 로 장 수를 자르고 -update 1 (안 그러면 "같은 이름에 여러 파일" 오류 — 2026-10-22 실측)
    "$(find_ffmpeg)" -loglevel error -y -start_number "$start" -i "$out/f/f%04d.png" \
      -vf "select='lt(n,$count)',crop=$crop,tile=${cols}x${rows}:padding=4:color=red" -frames:v 1 -update 1 "$out/zoom/$name.png"
    echo "확대 묶음 → $out/zoom/$name.png (프레임 $start ~ $((start + count - 1)))" ;;
  *) sed -n '2,12p' "$0"; exit 3 ;;
esac

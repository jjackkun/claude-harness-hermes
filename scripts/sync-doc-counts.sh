#!/usr/bin/env bash
# 문서의 수치 마커 블록을 소스 실측값으로 덮어쓴다 — R-doc 의 쓰기 담당.
#
# 근거: docs/exec-plans/active/2026-09-08-doc-counts-gate.md
#
# 읽기·판정은 assets/hooks/doc_counts.py 몫이다. 여기는 *쓰기만* 한다.
# 같은 것을 두 곳에서 정의하면 반드시 갈라진다 (iface_width.py 통합과 같은 판단).
#
# 사용: bash scripts/sync-doc-counts.sh [--stage] [파일...]   (인자 없으면 기본 대상)
#   --stage  커밋 검사(R-doc)가 부른다. 스테이징 안 된 변경이 없는 파일만 갱신하고 git add 한다 —
#            사용자의 다른 편집을 같이 올리지 않기 위해서다. 변경이 있는 파일은 건드리지 않고
#            비영 종료(수치가 아직 낡음)로 알려, 검사가 예전처럼 막고 안내하게 한다.

set -euo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)"

COUNTS="assets/hooks/doc_counts.py"
[[ -f "$COUNTS" ]] || { echo "doc_counts.py 없음: $COUNTS" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 없음" >&2; exit 1; }

STAGE=0
if [[ "${1:-}" == "--stage" ]]; then STAGE=1; shift; fi

if [[ $# -gt 0 ]]; then
  TARGETS=("$@")
else
  TARGETS=(README.md CLAUDE.md presets/workflow/harness.conf)
fi

BODY=$(python3 "$COUNTS" render)

for f in "${TARGETS[@]}"; do
  [[ -f "$f" ]] || { echo "  건너뜀 (없음): $f"; continue; }
  if ! grep -qF '<!--===DS:COUNTS:BEGIN===-->' "$f"; then
    echo "  건너뜀 (마커 없음): $f"
    continue
  fi
  if [[ $STAGE -eq 1 ]] && ! git diff --quiet -- "$f"; then
    echo "  건너뜀 (스테이징 안 된 변경 있음): $f"
    continue
  fi
  BODY="$BODY" python3 - "$f" <<'PY' || exit 1
import io, os, sys
p = sys.argv[1]
b, e = "<!--===DS:COUNTS:BEGIN===-->", "<!--===DS:COUNTS:END===-->"
raw = io.open(p, "rb").read()
s = raw.decode("utf-8")

# 마커가 정확히 한 쌍인지 확인한다. 중복이면 첫 쌍만 갱신되고 나머지는 조용히
# 낡은 채 남는다 — 생성물이 조용히 갈라지는 것이 이 게이트가 막으려는 바로 그것이다.
for mark, label in ((b, "BEGIN"), (e, "END")):
    n = s.count(mark)
    if n != 1:
        sys.exit(f"  {p}: {label} 마커가 {n}개입니다 (정확히 1개여야 합니다) — 손으로 정리해 주십시오")
if s.index(b) > s.index(e):
    sys.exit(f"  {p}: END 마커가 BEGIN 보다 앞에 있습니다")

# 줄바꿈을 파일에 맞춘다. LF 본문을 CRLF 파일에 끼워 넣으면 줄바꿈이 뒤섞인다.
nl = "\r\n" if b"\r\n" in raw else "\n"
body = os.environ["BODY"].replace("\r\n", "\n").replace("\n", nl)

head, rest = s.split(b, 1)
_, tail = rest.split(e, 1)
io.open(p, "w", encoding="utf-8", newline="").write(head + b + nl + body + nl + e + tail)
PY
  [[ $STAGE -eq 1 ]] && git add -- "$f"
  echo "  갱신: $f"
done

python3 "$COUNTS" check "${TARGETS[@]}" && echo "  대조 통과"

#!/usr/bin/env bash
# Prism.js 축소판 파일들을 모드가 읽을 수 있는 ES 모듈 하나로 묶는다.
# 사용: tools/build-prism.sh <prismjs 패키지 폴더>
# 결과: hooks/vendor/prism.js, hooks/vendor/PRISM-LICENSE
set -euo pipefail

SOURCE="${1:?prismjs 패키지 폴더를 넘기십시오 (예: <프로젝트>/node_modules/prismjs)}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$HERE/hooks/vendor"
# 의존 순서: 뒤의 언어가 앞의 언어를 확장한다(components.json 의 require).
LANGUAGES=(markup css clike javascript typescript jsx tsx json python bash yaml toml markdown scss sql go rust java ruby diff docker ini)

VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$SOURCE/package.json" | head -1)"
mkdir -p "$OUT"
{
  echo "// Prism.js $VERSION — MIT License, Copyright (c) 2012 Lea Verou. 전문: ./PRISM-LICENSE"
  echo "// 원본: prismjs/components/prism-core.min.js 와 언어 파일 ${#LANGUAGES[@]}개. 내용은 그대로이고,"
  echo "// 한 파일로 이어 붙인 뒤 끝에 export 한 줄만 더했다. 손으로 고치지 말고 tools/build-prism.sh 로 다시 만든다."
  cat "$SOURCE/components/prism-core.min.js"
  echo
  for language in "${LANGUAGES[@]}"; do
    cat "$SOURCE/components/prism-$language.min.js"
    echo
  done
  echo "export default Prism"
} > "$OUT/prism.js"
cp "$SOURCE/LICENSE" "$OUT/PRISM-LICENSE"
echo "built $OUT/prism.js ($(wc -c < "$OUT/prism.js") bytes, Prism $VERSION, ${#LANGUAGES[@]} languages)"

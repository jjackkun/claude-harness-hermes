#!/usr/bin/env bash
# R-struct 언어×규칙 회귀 시험 — 설정표(assets/hooks/structure-langs.json)의 규칙마다
# 위반(bad)·수정(good) 사례가 기대대로 판정되는지, 사례가 설정표를 빠짐없이 덮는지 단언한다.
#
# 사례는 tests/fixtures/structure/cases.json 한 장에 둔다 — 위반 예시를 실제 소스 파일로 두면
# 이 저장소 자신의 게이트(R-lint·R-struct)가 그 예시를 막는다.
# 계획: docs/exec-plans/active/2026-10-16-language-neutral-structure-gate.md G2
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "  - node 없음, 건너뜀"; exit 0; }
node "$ROOT/tests/structure-gate-run.mjs"

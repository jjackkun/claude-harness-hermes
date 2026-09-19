# gateguard — 편집 전 조사 증거(importer·영향 API) 제시를 기계로 요구한다

> 출처: `docs/audits/2026-09-19-ecc-gap-list.md` (ECC v2.2.1 대비 결핍 목록, 사용자 "다 필요한 것들" 확정 2026-09-19) — #4 (가치 중)

## 문제

"추측 금지 · 수정 전 import 그래프 1회 확인" 은 `assets/rules/harness/rules.md` 문서에만 있다. 훅은 형식만 본다
(`iface-guard` 공개 심볼 수, `plan-declare` 계획서 선언, `dead-file-warn` 실사용 여부). 편집 대상이 누구에게 import 되는지
에이전트가 실제로 봤는지는 아무도 묻지 않는다.

## ECC 의 실체

`scripts/hooks/gateguard-fact-force.js` — Edit/Write 전에 importer 목록·영향받는 API·스키마·근거 지시문 인용을 요구하고,
파괴적 Bash 에는 대상과 롤백 계획을 요구한다. ECC 는 자체 벤치에서 +2.25점 효과를 주장한다(검증 안 됨).

## 고칠 때 후보

- PreToolUse(Edit|Write) 훅: 같은 세션에서 그 파일에 대한 `grep -l`/`rg`/import 조회가 한 번도 없었으면 **경고**(차단 아님) —
  dead-file-warn 과 같은 관측 로그(`.harness/gate-events.jsonl`) 로 발화율을 본 뒤 차단 승격 여부 결정.
- 파괴적 Bash(rm·git reset --hard·DROP) 는 이미 `pretooluse-bash-guard` 가 막는다 — 롤백 계획 요구는 그 훅에 한 줄 추가.

## 착수 조건

skill-comply(agent-eval-regression) 로 "실제로 안 지켜지는 비율" 이 먼저 측정된 뒤. 측정 없이 훅을 늘리지 않는다(C-계열 원칙).

# PreCompact 훅 — 컨텍스트 압축 직전 상태를 .hermes 요약으로 보존

> 출처: `docs/audits/2026-09-19-ecc-gap-list.md` (ECC v2.2.1 대비 결핍 목록, 사용자 "다 필요한 것들" 확정 2026-09-19) — #7 (가치 중)

## 문제

`strategic-compact` 스킬은 있으나 PreCompact 훅이 0건이다. 긴 세션이 압축되면 그 시점까지의 결정·미완 작업은 압축 요약에만 남고,
`.hermes/state.db` 의 `session_summary` 는 Stop 훅 때만 쓰인다. 압축 뒤 세션이 비정상 종료되면 그 구간은 기억에서 사라진다.

## ECC 의 실체

`scripts/hooks/pre-compact.js` — 압축 직전 현재 상태(작업 중 파일·결정·다음 단계) 를 파일로 남기고 다음 컨텍스트에 다시 주입.

## 고칠 때 후보

- `assets/hooks/claude-precompact-summary.sh`: 기존 Stop 훅 요약기(`hermes_summary` 경로)를 그대로 호출해 5-슬롯 요약을 한 번 더 쓴다.
  새 요약 형식을 만들지 않는다. 마스킹 게이트(hermes-redact) 도 그대로 탄다.
- `settings.json` 훅 등록은 `hermes.conf` 로 12곳 전파. 훅 목록 문서(`hook_inventory`) 갱신.

## 착수 조건

없음. 구현이 작아(기존 요약기 재호출) 먼저 해도 된다. 검증: 압축 유도 세션에서 `session_summary` 가 Stop 전에 한 행 늘어남.

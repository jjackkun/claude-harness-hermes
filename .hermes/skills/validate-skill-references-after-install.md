# validate-skill-references-after-install
<!-- hermes:auto-generated version:1 created:2026-10-15 -->

## 문제 상황
새 프로젝트를 harness 설치할 때, 기존 스킬들이 하드코딩된 경로(예: rim-kanban examples), 도구명(context7), 모델/effort 지시를 그대로 참조하면서 설치 대상 프로젝트에 적용되지 않거나 모순되는 경우 발생. boundary-check의 outdated 경로, docs-lookup의 tool name 불일치, doc-updater의 missing commands, reasoning-sandwich와 planner 간 모델 지시 충돌, run-to-the-end의 모순 가이드 등이 설치 후 세션에서 적립됨.

## 규칙
- [ ] 스킬 본문의 파일 경로는 프로젝트 변수(`$project`, `$root`) 또는 상대 경로로 작성, 특정 프로젝트명 하드코딩 금지
- [ ] MCP 도구명 참조 전 `.claude/settings.json` 의 가용 도구 목록 및 MCP 서버 상태 확인
- [ ] 에이전트 배치 지시(model, effort)에서 상충하는 가이드 제거, 단일 출처만 참조
- [ ] 실행 시점 스킬(run-to-the-end, pre-commit-measure, tdd-guide)은 선행 조건 및 신호 명시
- [ ] 새 프로젝트 설치 완료 후 해당 프로젝트에서 최소 1회 스킬 호출로 경로·도구·모델 동작 확인

## 근거
- 감지 횟수: 5회 (boundary-check, docs-lookup, doc-updater, reasoning-sandwich, run-to-the-end)
- 패턴 키: rim-kanban
- 설치 대상: 11곳 중 4곳 완료 (2026-10-15), 호환성 검증 문제 누적

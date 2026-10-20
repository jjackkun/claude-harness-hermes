# verify-tool-names-before-use
<!-- hermes:auto-generated version:1 created:2026-10-16 -->

## 문제 상황
스킬과 에이전트에서 도구를 참조할 때 도구 이름이 변경되었음에도 하드코딩된 낡은 이름을 그대로 사용. 예: docs-lookup 스킬에서 context7 도구명 오류, doc-updater에서 MCP 도구 경로 누락, rim-kanban 예시의 경로 참조 오래됨.

## 규칙
- [ ] 도구를 스킬 본문에서 호출하기 전에 `ToolSearch(query="select:<toolname>")` 로 정식 스키마 조회
- [ ] MCP 도구는 항상 `mcp__<server>__<tool>` 형식으로 기재 (예: `mcp__context7__query-docs`)
- [ ] 스킬 description에 도구를 언급하는 경우 정식 이름만 사용, 별칭 금지
- [ ] 도구 이름이 변경되거나 deprecated되면 즉시 해당 스킬 검토 후 이름 갱신
- [ ] 스킬 작성 후 ToolSearch 오류가 나면 설명과 본문 모두 도구명 재확인

## 근거
- 감지 횟수: 3회 (docs-lookup, doc-updater, rim-kanban paths)
- 패턴 키: tool-use-id
- 심각도: High — 도구 호출 실패로 스킬 기능 정지

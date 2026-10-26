# hermes-local-skills-need-memory-links
<!-- hermes:auto-generated version:1 created:2026-10-26 -->

## 문제 상황
.hermes/skills/ 에 로컬 스킬이 생성되고 있으나, .hermes/memory/MEMORY.md 에 등록되지 않아 다음 세션의 hermes-recall 이나 hermes-dream 이 이들 스킬을 찾지 못하고, 스킬 메타데이터(주입 횟수, 발동율)가 누적되지 않는 문제.

## 규칙
- [ ] .hermes/skills/*.md 파일 생성 후 frontmatter 작성 (name, description, type)
- [ ] 즉시 .hermes/memory/MEMORY.md 에 "- [Title](file.md) — 한줄 설명" 형식으로 등록
- [ ] 세션 시작/종료 시 ls .hermes/skills/ 결과와 MEMORY.md 을 비교해 미등록 스킬 감지
- [ ] 감지 시 "Unregistered local skills" 경고 + 등록 제안

## 근거
- 감지 횟수: 0회
- 패턴 키: local-skill-untracked-retention
- 증거: .hermes/skills/ 에 3개 파일(mask-sensitive-data·selective-propagation·session-start-defer) 존재, MEMORY.md에는 미등록

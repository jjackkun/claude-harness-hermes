# clarify-skill-storage-layers
<!-- hermes:auto-generated version:1 created:2026-11-16 -->

## 문제 상황
스킬 파일이 세 곳에 분산: 로컬 개발용(~/.claude/skills/), 공장 정식용(claude-harness-hermes/assets/skills/), 헤르메스 학습 루프 산출물용(.hermes/skills/). watch 스킬이 로컬에만 있다가 공장으로 옮겨지는 과정에서, 어디에 무엇이 있는지 추적 불명확. 헤르메스 학습 루프 산출물 스킬은 의도적 미추적이지만 명시되지 않아 전파나 커밋 때마다 혼동.

## 규칙
- [ ] 스킬 저장소를 세 영역으로 명확히: 로컬(~/.claude/skills/, 커밋 금지) / 공장(assets/skills/, 커밋함) / 학습 루프(.hermes/skills/, 미추적)
- [ ] 새 스킬 추가 시 skill-creator 호출 전에 "이 스킬이 가야 할 영역"을 명시 — 로컬 개발, 공장 정식, 학습 루프 산출물 중 선택
- [ ] 공장 전파/update-all 시 .hermes/skills/ 는 제외 — 학습 루프 중간 산출물이므로 로컬에서만 사용
- [ ] 로컬 스킬을 공장으로 승격할 때 별도 PR: skill-creator로 정식화 → SKILL.md 확정 → 공장 assets/skills/ 에 커밋

## 근거
- 감지 횟수: 6회 (watch 스킬 위치 이동, hermes 스킬 6개 산재, 공장 미추적 파일 5개)
- 패턴 키: package_skill

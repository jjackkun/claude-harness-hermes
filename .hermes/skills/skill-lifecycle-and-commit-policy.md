# skill-lifecycle-and-commit-policy
<!-- hermes:auto-generated version:1 created:2026-10-22 -->

## 문제 상황
스킬을 skill-creator로 작성한 후 `.hermes/skills/` 또는 `.claude/skills/`에 저장할 때, 어느 폴더에 놓을지, 커밋할지 미추적으로 두를지 결정이 명확하지 않음. 공장 저장소(claude-harness-hermes)의 결정화 스킬과 로컬 전용 학습 스킬이 혼용되어, 같은 커밋에 묶을 때도 있고 따로 넣을 때도 있으며, .gitignore 정책이 일관되지 않음.

## 규칙

- [ ] **공장 저장소 스킬** (claude-harness-hermes): `.hermes/skills/` (리모트 추적) — 여러 결정화 스킬을 한 커밋으로 묶어 푸시
- [ ] **로컬 전용 학습 스킬** (현재 프로젝트): `.hermes/skills/` (로컬만, .gitignore 미추적) — 학습 루프 산출물, 커밋 금지
- [ ] **도구·설치기** (skill-creator 자체): `.claude/skills/` (공개 추적) — 사용자나 다른 프로젝트가 쓸 수 있는 템플릿
- [ ] 스킬 작성 완료 후: 공장 저장소와 파일명 겹침 확인 → 겹치면 로컬로, 신규면 공장 대상 검토
- [ ] 공장 스킬 동시 여러 개 결정화: 한 커밋으로 묶되, 로컬 학습 스킬과 섞지 않기

## 근거

- 감지 횟수: 8회 이상
- 패턴 키: skill
- 세션 기록: .hermes/skills/ 5개 파일 미추적 유지 · 공장 저장소 결정화 스킬 2개 한 커밋으로 병합 · 터미널-쉬핑 backup-* 미추적 · skill-creator 로드됨

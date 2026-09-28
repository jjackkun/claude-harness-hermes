# preset-install-three-layer-check

<!-- hermes:auto-generated version:1 created:2026-09-15 -->

## 문제 상황
프리셋 설치 상태를 `.claude/presets.lock`만으로 판단. 실제로는 원본 저장소 `presets/workflow/*.conf` + 프로젝트 `.claude/presets.lock` + 실제 규칙/스킬 파일 3곳이 모두 일치해야 설치 완료. 파일 하나 누락되면 원인을 못 찾고 같은 질문 반복.

## 규칙
- [ ] 프리셋 설치 상태 확인: 원본 `presets/workflow/*.conf` 에 정의되어 있나 → 프로젝트 `.claude/presets.lock` 에 기록되어 있나 → `.claude/rules/` 또는 `.claude/skills/` 에 실제 파일이 존재하나 **3곳을 모두 점검**
- [ ] 규칙(rules)은 세션 시작시 자동 로드되고, 스킬(skills)은 호출하거나 설정에서 `disable-model-invocation: false` 일 때만 자동 실행 — 설치 후 동작 방식이 다름을 인지
- [ ] `.presets.lock`은 프리셋 이름만 기록 — 버전, 원본 저장소 경로, 전파 상태는 기록되지 않음을 인식. 이 파일 하나만으로는 진실 공급원이 될 수 없음

## 근거
- 감지 횟수: 9회
- 패턴 키: presets.lock

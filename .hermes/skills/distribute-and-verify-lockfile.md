# distribute-and-verify-lockfile
<!-- hermes:auto-generated version:1 created:2026-09-15 -->

## 문제 상황
프리셋·규칙·스킬을 추가한 후 `update-all.sh`로 전파했을 때, 공통 파일(assets/, scripts/)은 모든 프로젝트에 닿지만, **프로젝트별 `presets.lock`에 새 항목이 없으면 실제 작동하지 않는다.** 예: `fluent-korean` 규칙을 전파했어도 대상 프로젝트의 `.claude/presets.lock`에 `fluent-korean`이 없으면 켜지지 않음.

## 규칙
- [ ] 설치형 기능(프리셋·규칙·스킬)을 추가했으면, **먼저 원본 프로젝트에서 `presets/workflow/*.conf`와 `.claude/presets.lock`을 확인·수정할 것**
- [ ] 수정 후 `update-all.sh --target claude`로 전파할 것
- [ ] 전파 완료 후 **각 영향 대상 프로젝트의 `.claude/presets.lock`을 확인**해 새 항목이 실제로 잠겨 있는지 검증할 것
- [ ] 선택 프리셋(adhd, fluent-korean)은 기본 잠금 대상이 아니므로, 대상 프로젝트의 `presets.lock`을 **미리 조정하거나 문서에 명시**해 설치 시 사용자가 선택하도록 할 것

## 근거
- 감지 횟수: 3회 이상
- 패턴 키: update-all
- 프로젝트 특정: 멀티 프로젝트 설치형 구조(`presets.lock` + `presets/workflow/` + `update-all.sh`)

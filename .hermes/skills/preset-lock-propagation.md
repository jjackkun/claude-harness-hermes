# preset-lock-propagation
<!-- hermes:auto-generated version:1 created:2026-09-10 -->

## 문제 상황
새 프리셋·플러그인을 단일 프로젝트에서 테스트하면 통과하지만, 다른 프로젝트에 전파할 때 활성화되지 않음. 원인: 프리셋 파일 작성만 완료하고 `presets.lock`과 의존도 선언 누락.

## 규칙
- [ ] 새 프리셋 파일 작성 후 `presets.lock`에 명시적 추가 (잠긴 상태 체크)
- [ ] 단일 프로젝트 테스트만으로 완료 선언하지 않기 — 전파 프로젝트도 재설치·검증
- [ ] 배포 후 타겟 프로젝트에서 실제 활성화 확인 (settings.json·agents·rules 생성)
- [ ] 프리셋 의존성 그래프 확인 (일부 프로젝트가 특정 프리셋 잠금 상태인지 점검)
- [ ] 프리셋 매니페스트에 메타데이터 완성 (설정 키·기본값·설명 명시)

## 근거
- 감지 횟수: 3회
- 패턴 키: plugin-preset-integration-pattern

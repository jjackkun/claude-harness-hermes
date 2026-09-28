# preset-install-uninstall-complete-steps
<!-- hermes:auto-generated version:1 created:2026-09-14 -->

## 문제 상황
프리셋 설치/제거 과정에서 다음을 반복 누락:
- 설치 전 자동화 전략(규칙/훅 vs 스킬) 선택 미흡
- 프리셋 상태(로그, DB, 캐시) 누적 인식 부족
- 제거 시 일부 계층만 정리 (플러그인 캐시, 마켓플레이스, 설정, 잠금 파일 중 일부 누락)

## 규칙
- [ ] 설치 전: 자동화 수준 결정 (규칙/훅은 세션마다 자동, 스킬은 매번 수동 호출)
- [ ] 설치 후: 로그/캐시 누적 정책 확인 및 로테이션 필요 여부 검토
- [ ] 제거 시: 플러그인 캐시(`~/.claude/plugins/cache/`), 마켓플레이스(`~/.claude/plugins/marketplaces/`), 설정 파일(`enabledPlugins`), 잠금 파일(`.claude/presets.lock`) 모두 확인
- [ ] 제거 후: 테스트 통과로 완전성 검증

## 근거
- 감지 횟수: 3회
- 패턴 키: 프리셋

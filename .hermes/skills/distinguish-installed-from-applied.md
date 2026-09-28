# distinguish-installed-from-applied
<!-- hermes:auto-generated version:1 created:2026-09-14 -->

## 문제 상황
설정 파일에 output-style이 등록되고, 플러그인 캐시에 파일이 존재하고, `enabledPlugins`에 항목이 있어도 실제 세션에는 로드되지 않음. 설치 상태 검증(파일/설정 존재)과 실행 상태 검증(세션에 로드됨)을 구분하지 않으면 무엇이 작동하는지 알 수 없음.

## 규칙
- [ ] 파일·설정 존재 확인만으로 "적용됨"이라고 결론짓지 않기
- [ ] output-style/플러그인 변경 후 실제 세션에서 동작하는지 별도 검증하기 (`/output-style` 명령 실행)
- [ ] "설치 경로 확인(캐시, settings.json)" ≠ "세션 시작 시 로딩 확인" 구분하기
- [ ] 설정 변경 시 현재 세션 vs 차후 세션의 적용 시점 명확히 하기

## 근거
- 감지 횟수: 1회
- 패턴 키: output-style-applied-at-session-startup

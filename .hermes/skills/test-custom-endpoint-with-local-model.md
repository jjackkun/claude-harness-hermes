# test-custom-endpoint-with-local-model
<!-- hermes:auto-generated version:1 created:2026-09-30 -->

## 문제 상황
새로운 도구(예: jevgrep)가 로컬 모델로 대체 가능한지 검토할 때, 그 도구가 커스텀 엔드포인트를 지원하는지 문서에 명시되지 않아 소스 코드를 일일이 뒤져서 확인한다.

## 규칙
- [ ] 도구의 소스(`args.ts`, 설정 파일)에서 엔드포인트 설정 옵션(`--base-url`, `--model`, `baseURL` 등) 검색
- [ ] 로컬 서버의 실제 API 엔드포인트 포맷 확인 (프로토콜, 호스트, 포트, 경로)
- [ ] 도구가 호출하는 API 경로와 로컬 서버의 응답 경로 호환성 검증 (URL 구조 일치)
- [ ] 작은 규모 통합 테스트(한두 개 요청)로 실제 연결 확인 후 성능 평가 진행

## 근거
- 감지 횟수: 0회
- 패턴 키: jevgrep-custom-endpoint-support

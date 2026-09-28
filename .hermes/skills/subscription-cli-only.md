# subscription-cli-only
<!-- hermes:auto-generated version:1 created:2026-09-17 -->

## 문제 상황
subscription 접근이 CLI 어댑터를 거치지 않고 직접 API 호출로 구현되는 경우. 일관된 인증·로깅·레이트 리미팅을 우회할 수 있음.

## 규칙
- [ ] Subscription 관련 코드 작성 전, 프로젝트의 CLI 어댑터 또는 구독 클라이언트 경로를 확인한다
- [ ] 직접 LLM/외부 API 패키지 import 발견 시 (예: `anthropic`, `openai`), CLI 경유 리팩토링
- [ ] 코드 리뷰 시, 모든 subscription 호출이 지정된 경로(예: `llm.subscription.client`)를 거치는지 검증

## 근거
- 감지 횟수: 0회
- 패턴 키: subscription-cli-only-no-direct-api

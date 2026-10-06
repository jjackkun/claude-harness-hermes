# enforce-llm-subscription-adapter-routing
<!-- hermes:auto-generated version:1 created:2026-10-01 -->

## 문제 상황
LLM 호출 구현 시 API 직접 호출이나 외부 SDK 사용을 제안하는 경우가 반복됨. 프로젝트 R3 규칙(구독 CLI 어댑터 경유 필수)을 확인하지 않고 기술적 편의성만 고려하여 제안함.

## 규칙
- [ ] 새로운 LLM 호출이 필요하면 먼저 프로젝트의 R3 규칙(구독 CLI 어댑터 경유 필수)을 확인한다
- [ ] API 직접 호출이나 외부 SDK 임포트 제안은 R3 충돌을 이유로 즉시 거절한다
- [ ] 로컬 모델·외부 전송 문제는 구독 CLI 어댑터 내 Jeff 로컬화로 해결하며, SDK 직접 설치는 제안하지 않는다
- [ ] 규칙 변경이 필요하면 근거(`docs/design-docs/`, `docs/audits/`)를 먼저 작성하고 사용자 승인을 받는다

## 근거
- 감지 횟수: 3회
- 패턴 키: r3-llm-subscription-cli-adapter

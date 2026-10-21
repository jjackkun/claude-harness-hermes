# redact-once-at-interface
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
작업 시퀀스가 완료되고 인터페이스(에이전트 출력, 작업 프롬프트, 메시지)를 생성할 때, 이미 감시·보안상 가려진 값(redacted value)을 다시 가리려고 시도하는 중복 처리가 발생합니다. 특히 hermes summon에서 `build_task_prompt`가 이미 가려진 값을 받을 때 출처가 명확하지 않으면 의도치 않게 재가림이 발생합니다.

## 규칙
- [ ] 값이 이미 가려짐을 알면 docstring에 명시: "이미 가려진 값을 받음" 또는 "redacted input expected"
- [ ] 가림 처리는 인터페이스 경계에서 **한 곳에서만** 수행 — 상류에서 가렸으면 하류는 재가림 금지
- [ ] 중복 가림이 필요하다면, 먼저 값의 출처와 가림 지점을 문서화하여 명확히 할 것
- [ ] 감시 값(password, token, key)과 조사 값(username, project name)을 구분하여 함수명/주석에 표기

## 근거
- 감지 횟수: 1회
- 패턴 키: task-sequence-completed-iface-redact
- 원본: hermes summon 프로세스 — build_task_prompt가 이미 가려진 값을 받을 때 docstring 부재로 재가림 시도

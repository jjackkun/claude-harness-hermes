# redact-pattern-gaps — hermes_redact 형태 규칙이 놓치는 비밀·개인정보를 보강한다

> 작성일: 2026-10-16
> 목적: `scripts/hermes_redact.py` 가 저장·LLM 전송 경계에서 놓치는 패턴을 채운다.
> 근거: `docs/exec-plans/completed/2026-10-16-redact-llm-input-gaps.md` 착수 전 전수 조사

## 놓치는 것 (2026-10-16 조사)

| 구멍 | 지금 | 근거 |
|---|---|---|
| 유선전화·01x 아닌 번호 | 휴대전화(01x)만 가림 | `hermes_redact.py:55` |
| 명부·git·OS 에 없는 타인 이름 | 아는 이름만 가림 | `hermes_redact.py:111-123` |
| JWT(`eyJ…`)·PEM 개인키 | redact 에 없음, 커밋 게이트(`check-secrets.py:74`)에서만 잡힘 | `assets/hooks/check-secrets.py:74` |
| 한글 값의 라벨=값 | 값이 ASCII 일 때만 가림 | `hermes_redact.py:38` |

## 착수 조건

과마스킹(한글 산문 훼손)이 실제 비용이다. 패턴마다 `tests/hermes-redact-pii-test.sh` 에 오탐 사례를 함께 넣고 시작한다.

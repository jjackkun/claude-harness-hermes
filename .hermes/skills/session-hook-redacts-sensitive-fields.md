# session-hook-redacts-sensitive-fields
<!-- hermes:auto-generated version:1 created:2026-09-16 -->

## 문제 상황
세션 훅이 대화 원문을 state.db에 저장할 때, API key·비밀값·민감한 프롬프트 같은 정보가 마스킹 없이 그대로 저장되고 있습니다. 특히 work-history의 자유 텍스트 필드(intent, lesson, decision)에는 사용자가 작성한 문맥 정보가 평문으로 들어가므로, 회사 공유 저장소에서는 누출 위험이 높습니다.

## 규칙
- [ ] session-hook이 session_history를 state.db에 저장하기 전에, 민감 필드(API key, password, token, secret) 패턴을 자동 감지하고 `[REDACTED]`로 마스킹
- [ ] work-history의 3개 자유 텍스트 필드(intent, lesson, decision)는 저장소 유형에 관계없이 AES-256으로 암호화 — 복호화는 대화 복기(`hermes-recall`) 시에만
- [ ] 개인 저장소(contributor 1명): 원문은 state.db에만 보관, git에는 커밋하지 않음
- [ ] 회사 공유 저장소(contributor 2명 이상): 원문을 별도 비공개 저장소로 옮김, 메인 저장소에는 요약만 남김
- [ ] 마스킹/암호화 실패 시 세션 훅이 경고 로그를 남기고 저장을 중단(데이터 누출보다 세션 유실이 낫다)

## 근거
- 감지 횟수: 2회
- 패턴 키: session-hook-prevents-key-leakage

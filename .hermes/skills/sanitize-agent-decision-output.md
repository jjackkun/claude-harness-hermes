# sanitize-agent-decision-output
<!-- hermes:auto-generated version:1 created:2026-10-07 -->

## 문제 상황
에이전트나 게이트에서 받은 결정을 전송·기록할 때 원본 텍스트(raw response)가 섞여 있으면 자동화 처리와 감사 추적이 어려워진다. 구조화되지 않은 형식은 나중에 파싱·검증·접근이 복잡하고 오류가 생기기 쉽다.

## 규칙
- [ ] 에이전트·게이트 응답을 받으면 원본 텍스트를 그대로 옮기지 않기
- [ ] JSON, 슬롯 구조(decision·reason·impact), 또는 정의된 필드 형식으로만 기록하기
- [ ] 의사 결정 내용과 근거만 추출, 대화·설명·배경은 제외하기
- [ ] 결정 기록 필드: timestamp, decision, rationale, consequence (최소)

## 근거
- 감지 횟수: 1회
- 패턴 키: gate-decision-transport-only-no-raw

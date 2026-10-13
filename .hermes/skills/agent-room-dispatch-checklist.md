# agent-room-dispatch-checklist
<!-- hermes:auto-generated version:1 created:2026-10-13 -->

## 문제 상황
에이전트 방(room)을 구성할 때 호출명(@hagent 등)과 메시징 채널 매핑이 불일치하거나, 모델/effort 라우팅이 계획 문서와 코드 간 동기화되지 않아 메시징 실패 또는 라우팅 블라인드스팟이 발생. Cross-Session-Messaging 사용 시 ListAgents 결과와 실제 훅 인식 범위의 괴리로 인해 세션 간 dispatch가 차단되는 경우도 반복.

## 규칙
- [ ] 에이전트 방 설정 후, 호출명 목록을 `scripts/hermes-agent.py`와 훅 설정(`.claude/settings.json`)에서 확인하고, 계획 문서와 코드가 일치하는지 검증
- [ ] Cross-Session-Messaging 사용 전 `ListAgents` 결과로 현재 방의 에이전트 목록을 확인하고, SendMessage 대상이 그 목록에 있는지 확인
- [ ] 에이전트 모델/effort 라우팅 결정 전 `docs/design-docs/agent-model-routing-blindspot.md`(또는 최신 설계 문서) 검토하여 블라인드스팟 확인
- [ ] 파일 치환이 필요한 작업(hagent-call 등)에서는 계획 문서 §4 선언과 실제 코드 간 일치를 구현 전 검증

## 근거
- 감지 횟수: 0회
- 패턴 키: agent-work-in-microcosm

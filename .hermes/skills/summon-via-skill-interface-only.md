# summon-via-skill-interface-only
<!-- hermes:auto-generated version:1 created:2026-09-28 -->

## 문제 상황
에이전트 소환 시 hermes-summon.py CLI 경로(`python3 scripts/hermes-summon.py run`)를 확인하거나 사용자에게 설명하려는 단계가 반복됨. hermes-agent 스킬이 이 CLI를 이미 감싸고 있으므로, 사용자는 자연어 요청("QA 한테 이것 넘겨")만으로 충분함.

## 규칙
- [ ] 에이전트 소환은 항상 hermes-agent 스킬 호출로만 한다
- [ ] CLI 경로는 내부 구현이므로 사용자에게 노출하지 않는다
- [ ] 사용자가 자연어로 요청하면 즉시 스킬을 호출하고, CLI 명령 상세는 설명하지 않는다

## 근거
- 감지 횟수: 2회
- 패턴 키: summon-via-hermes-cli

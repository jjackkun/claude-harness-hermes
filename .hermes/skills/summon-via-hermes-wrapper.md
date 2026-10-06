# Summon Via Hermes Wrapper
<!-- hermes:auto-generated version:1 created:2026-09-29 -->

## 문제 상황
에이전트 소환 시 Claude Code 공식 Agent 도구와 hermes-summon.py 커스텀 래퍼 간 혼동 — 직접 `claude -p` 호출 또는 공식 도구로 소환하면 기억 적립·조직 매칭·역할 추적이 누락됨.

## 규칙
- [ ] 에이전트 소환 시 hermes-agent 스킬만 사용
- [ ] 터미널에서 hermes-agent 스킬을 사용할 수 없으면 `python3 scripts/hermes-summon.py run "<이름|id>" --task "<지시>"` 호출
- [ ] `claude -p` 또는 Claude Code 공식 Agent 도구로 직접 소환하지 않기
- [ ] 자연어 지시("누구한테 넘겨", "입사시켜")는 hermes-agent 스킬이 명령으로 변환하도록 위임
- [ ] 모든 소환은 `scripts/hermes-summon.py` 를 반드시 경유해 기억·조직 매칭 자동 적립

## 근거
- 감지 횟수: 3회 (09-19, 09-20, 09-28)
- 패턴 키: hermes-summon-cli-interface
- 결정: 프로젝트 커스텀 에이전트 래퍼를 단일 진입점으로 강제하여 추적·기억·조직 인식 일관성 보장

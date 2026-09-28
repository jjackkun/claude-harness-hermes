# validate-skill-before-crystallize
<!-- hermes:auto-generated version:1 created:2026-09-22 -->

## 문제 상황

헤르메스가 스킬을 결정화할 때 검증 없이 다음과 같은 junk 스킬들을 만들고 있습니다:
- 단일 코드 단어(`array`, `shared`, `index`, `postgres`)가 스킬로 굳음 (도움 3회 / 주입 2,476회)
- 페이지 이름(`commoncodepage.md`, `app-layout__content`) 같은 이름이 규칙으로 결정화됨
- 스킬 진화 힌트가 사람이 고친 말이 아니라 다른 스킬 본문·압축 요약·서브에이전트 반환에서 추출됨
- 결과적으로 도움 없는 규칙이 매 턴 주입되어 인덱스 노이즈 증가

## 규칙

- [ ] 스킬이 결정화되기 전에 도움율(hit/inject) 을 먼저 측정하라. 0.1% 미만이면 결정화하지 마라.
- [ ] 단일 단어나 기술 용어(`array`, `shared`, `index`) 같은 공통 토큰은 스킬 후보에서 자동 제외하라.
- [ ] 진화 힌트 출처를 검증하라 — 사람이 직접 친 메시지(user 역할)에서만 추출하고, 스킬 본문·서브에이전트 반환·압축 요약에서는 제외하라.
- [ ] 페이지 이름이나 파일 경로 형태의 문자열은 스킬 후보에서 제외하라.

## 근거

- 감지 횟수: 3회 (evolve-hint-false-positive / skill-yield-junk / page-name-skills 백로그)
- 패턴 키: 스킬이
- 파급: 3개 프로젝트에서 스킬 19개가 96번 고쳐졌고, 도움 없는 스킬 1,094개가 zeroday-frontend에서 매 턴 주입 중

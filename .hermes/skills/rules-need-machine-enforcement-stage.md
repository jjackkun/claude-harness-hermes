# rules-need-machine-enforcement-stage
<!-- hermes:auto-generated version:1 created:2026-11-25 -->

## 문제 상황
결정화 스킬을 작성할 때 반복된 패턴을 규칙으로 뽑지만, "사람의 판단이 필요한 규칙(prose)"과 "기계로 검사할 수 있는 규칙(checkable: gate/test/lint)"을 구분하지 않는다. 결과적으로 hermes-dashboard 의 산문 규칙 비율이 높아지고, 같은 실수가 반복된다.

## 규칙
- [ ] 결정화 스킬 작성 후 각 규칙마다 "ENFORCE:" 판정을 필수로 첨부한다 — `ENFORCE: covered:<게이트명>` / `ENFORCE: checkable:<hook|gate|test>` / `ENFORCE: prose` 중 하나
- [ ] `prose` 판정인 규칙이 50% 를 넘으면, `checkable` 로 개선할 수 있는 것을 별도 backlog 작업으로 올린다 — 예시: "lint 규칙 추가", "test case 작성", "pre-commit hook 추가"
- [ ] 스킬 frontmatter 의 `description` 에 "[ENFORCE: 판정]" 을 명시해 대시보드 시각화에 포함시킨다

## 근거
- 감지 횟수: 1회 (현재 hermes-dashboard 개선 중 발견)
- 패턴 키: hermes-crystallize-add-machine-checkable-stage

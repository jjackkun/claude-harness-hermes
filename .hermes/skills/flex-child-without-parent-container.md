# flex-child-without-parent-container
<!-- hermes:auto-generated version:1 created:2026-11-25 -->

## 문제 상황
자식 요소에 `flex: 1` 또는 `flex-grow`, `flex-shrink` 등을 선언했는데, 부모 요소에 `display: flex`와 `flex-direction`이 없어서 자식의 flex 속성이 무시되는 경우. 화면 상 자식이 예상 크기로 늘어나지 않음.

## 규칙
- [ ] 자식 요소에 `flex:`, `flex-grow`, `flex-shrink`, `flex-basis`가 있으면 부모에 `display: flex` 확인
- [ ] 부모의 `flex-direction` (row/column)이 자식 늘이기 의도와 맞는지 확인
- [ ] Svelte/React 컴포넌트: wrapper에 flex 클래스가 붙었는지, 사용처에서 override되지 않았는지 확인
- [ ] UI 렌더링 테스트에서 자식 너비/높이가 예상값인지 검증 (getComputedStyle로 display 확인)

## 근거
- 감지 횟수: 4회
- 패턴 키: css-property-missing
- 프로젝트 맥락: Svelte/React UI 컴포넌트 layout 오류

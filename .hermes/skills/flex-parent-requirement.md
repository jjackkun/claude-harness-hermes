# flex-parent-requirement
<!-- hermes:auto-generated version:1 created:2026-11-25 -->

## 문제 상황
Svelte 컴포넌트에서 자식 요소에 `flex: 1` 또는 `flex-grow`를 적용해도 부모에 `display: flex`와 `flex-direction`이 없으면 레이아웃이 깨진다. 화면에는 엘리먼트가 붕괴되거나 여백이 무시된다.

## 규칙
- [ ] 자식 요소에 `flex: 1` 또는 `flex-grow`를 쓰기 전에 부모의 HTML 구조를 확인한다
- [ ] 부모 요소에 `display: flex`가 명시적으로 있는지 확인한다
- [ ] 부모 요소에 `flex-direction: row` 또는 `column` 중 하나가 명시적으로 있는지 확인한다
- [ ] 중간에 flexbox 맥락을 끊는 요소가 없는지 확인한다 (display 값 변경, position: absolute 등)
- [ ] 개발자 도구에서 부모의 Computed 탭을 열어 `display: flex` 실제 적용을 확인한다

## 근거
- 패턴 키: css-property-missing
- 프로젝트: Svelte UI 렌더링

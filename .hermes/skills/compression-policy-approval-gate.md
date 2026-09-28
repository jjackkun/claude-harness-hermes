# compression-policy-approval-gate
<!-- hermes:auto-generated version:1 created:2026-09-14 -->

## 문제 상황
생애주기 압축(lifecycle compression) 정책 변경이나 특정 영역에 적용할 때, 영향 범위와 예외 처리를 충분히 검토하지 않고 결정하면 데이터 무결성 손실이나 전파 불일치가 발생합니다. "쌓이게 두는 게 맞다"는 결론이 내려진 후에도 "두 군데는 손봐야 한다"는 예외가 발견되고, 전파 방식에 숨겨진 함정이 있을 수 있습니다.

## 규칙
- [ ] 생애주기 압축 정책 변경 전에 `history` → 파생물(`session_history_content`, `session_history_data`) 의존성을 명시적으로 맵핑했는가?
- [ ] 압축 대상 영역에서 "지우는 사람이 아무도 없다"는 상태가 정상인지, 아니면 누락된 cleanup 스크립트가 있는지 확인했는가?
- [ ] 전파 경로(`lib/harness_installers.sh` 같은 원본 배포 지점)에서 압축 정책이 일관되게 적용되는지 재확인했는가?
- [ ] 예외 영역("두 군데")을 명시적으로 문서화했는가? (어디인지, 왜 예외인지)
- [ ] 정책 변경을 `docs/design-docs/` 에 기록했는가?

## 근거
- 감지 횟수: 3회 (lifecycle 동작 확인, history 구조 재검토, 전파 함정 발견)
- 패턴 키: lifecycle-compression-requires-approval

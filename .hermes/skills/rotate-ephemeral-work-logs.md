# rotate-ephemeral-work-logs
<!-- hermes:auto-generated version:1 created:2026-09-14 -->

## 문제 상황
`hooks.log`와 같은 append-only 작업 로그가 로테이션 메커니즘 없이 무한정 쌓인다. 현재 프리셋에서 45일간 6.5MB까지 누적된 사례가 있으며, 하루에 1,500줄이 추가되는 상태다. 파생 로그(history나 DB와 달리 원본이 아니므로)는 지워도 복구 경로가 없지만, 로테이션은 안전하다.

## 규칙
- [ ] Append-only 로그(`.log`, `.jsonl`, 일지 형식)는 로테이션 스크립트를 갖춘다
- [ ] 파생 로그(원본이 아닌 작업 기록)는 정기적(일주일 또는 크기 기준)으로 truncate·rotate한다
- [ ] 로테이션 로직은 `scripts/` 또는 훅 자체에 내장하지 말고, 중앙 프리셋(`assets/hooks/rotate-logs` 등)에서 제공한다
- [ ] 로테이션 대상은 `.gitignore`에 명시하거나 pre-commit 게이트에서 제외한다
- [ ] **작업 이력(`journal_events`)은 로테이션 대상이 아니다** — 파생 로그가 아니라 원본이고,
      추가 전용이라 지우면 복구 경로가 없다. 지우는 일은 사람이 `hermes-journal.py rollback`
      으로만 하고 그것도 기록을 보존한다(계획 2026-09-15-universe-id-journal 목표 10).

## 근거
- 감지 횟수: 1회
- 패턴 키: hooks-log-is-ephemeral-rotatable
- 실측: hooks.log 67,934줄 / 6.5MB (45일), [hermes] 18,746줄 + [hermes-summary] 5,002줄 등 8종류 훅에서 축적

# CI 워크플로가 실패해도 아무도 모른다

> 2026-09-22 착수·완료 — `docs/exec-plans/completed/2026-09-22-ci-failure-notification.md`. 이 문서는 출처 기록으로 남긴다.

> 출처: `docs/exec-plans/completed/2026-09-21-weekly-gardening-red.md` §8

## 문제

`weekly-doc-gardening`(schedule) 이 08-30 · 09-06 · 09-13 · 09-20 네 번 연속 실패했는데 4주 동안 아무도 몰랐다.
사람이 실행 목록을 우연히 본 덕에 발견했다. push CI 는 눈에 띄지만 schedule 워크플로는 보는 사람이 없다.

## 후보

- 워크플로 마지막에 `if: failure()` 단계로 이슈를 열거나 기존 이슈에 코멘트(라벨 `harness`, 중복 방지는 제목 고정).
- 세션 시작 훅이 `gh run list --workflow=... --status=failure --limit=1` 로 최근 실패를 한 줄 알림 — `gh` 인증이 필요하고
  인증 없으면 조용히 넘어가야 한다.
- 어느 쪽이든 "알림이 실패해도 본 작업은 실패시키지 않는다"(알림이 게이트가 되면 안 된다).

## 먼저 잴 것

- 12곳 중 schedule 워크플로가 실제로 걸린 곳이 몇 곳인지(대부분 GitLab 안내만 배치됨).
  - **2026-09-22 실측: 공장 1곳뿐**(`claude-harness-hermes/.github/workflows/weekly-doc-gardening.yml`). 나머지 11곳은 `.github/workflows/` 에 `schedule:` 이 없다.
    → 알림은 공장 워크플로 하나에만 붙이면 된다. 세션 시작 훅으로 12곳에 퍼뜨릴 이유가 없다.
  - 최근 실행 결과는 이 머신의 `gh` 가 로그인돼 있지 않아 확인하지 못했다(`gh auth login` 필요). 세션 훅 후보는 이 조건에서 조용히 넘어가야 한다는 뜻이기도 하다.

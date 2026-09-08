# run-all.sh 고아 테스트 검사

> 출처: `docs/exec-plans/completed/2026-09-03-r5-false-positive.md` §7·§8

## 문제

`tests/run-all.sh` 는 실행할 테스트를 **명시 목록**으로 갖는다. 새 테스트 파일을 만들고
목록에 넣지 않으면 그 테스트는 **한 번도 실행되지 않는다.** 개별 실행으로 통과를 확인한
사람은 "테스트가 있다" 고 믿지만 CI 는 아무것도 검증하지 않는다.

관측(2026-09-03): 한 세션에서 만든 테스트 6개(`gate-event`·`gate-report`·
`gate-instrumentation`·`gate-precommit-instrumentation`·`mutation-trigger`·`r5-detection`)가
전부 미등록 상태였다. 우연히 발견해 등록했다.

이는 이 저장소가 반복해 겪은 **조용한 건너뜀**과 같은 형태다:
`R-test` 가 테스트 0개로 늘 통과한 것, pre-commit 이 `.review-dirty` 를 읽지 않은 것,
`size-warn` 의 `^export ` 가 Svelte 에서 한 번도 발화하지 못한 것.

## 해야 할 일

- `run-all.sh` 에 정적 검사 단계를 추가한다: `tests/` 의 `*-test.sh`·`*smoke*.sh` 중
  러너 목록에 없는 파일이 있으면 **실패**한다.
- 의도적 제외가 필요하면 명시적 스킵 목록(`_is_skipped` 가 이미 있다)을 쓰게 한다 —
  침묵으로 빠지는 경로를 없앤다.
- 검사 자체를 검증한다: 가짜 고아 테스트를 만들어 러너가 실제로 실패하는지 확인한다.
  (통과만 보는 검증 금지 — 이 리포의 반복 교훈이다.)

## 근거

- `assets/rules/harness/examples/README.md` — "가짜 위반을 일부러 만들어 테스트가
  *실제로* 차단하는지 확인한다. 통과만 보는 검증은 silent-skip 을 못 잡는다."

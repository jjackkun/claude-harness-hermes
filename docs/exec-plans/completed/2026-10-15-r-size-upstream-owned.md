# 2026-10-15-r-size-upstream-owned — 포크 프로젝트에서 원본(upstream) 소유 파일은 R-size 한도에서 뺀다

---

## 1. 동기 (Why)

2026-10-15 jj-agent-room(yetone/cumora 포크)에서 Step 1 커밋이 R-size 에 막혔다.

- 막힌 파일: `server/src/api/router.ts` 7,358줄 · `server/src/agents/computer/daemon.ts` 4,728줄 · `server/src/agents/computer/registry.ts` 1,350줄. 셋 다 **원본 파일**이고, 포크는 연결 몇 줄만 넣었다.
- 포크 규칙(`docs/design-docs/fork-upstream.md` §4)은 "원본 코드를 정리하지 않는다 — 포맷·이름·파일 위치를 바꾸지 않는다" 이다. 원본 파일을 500줄로 쪼개는 것은 이 규칙 위반이고, 원본 병합 때마다 충돌을 만든다.
- 그 프로젝트의 `.harnessrc` 에는 이미 `UPSTREAM_REF=upstream/main` 과 "R-size 한도는 포크가 만든 파일에만 건다" 가 적혀 있다 (2026-10-14 `eabe406`). 그런데 **공장 `assets/hooks/pre-commit.sh` 에는 `UPSTREAM_REF` 를 읽는 코드가 없다.** `.harnessrc` 가 근거로 든 공장 문서 `docs/audits/2026-10-14-r-size-fork-upstream-files.md` 도 공장 어느 브랜치에도 없다.
- 이전 PC 에서는 같은 커밋 흐름이 통과했다 (`eabe406` 이 `daemon.ts`·`registry.ts` 를 고쳤다). 이전 PC 의 `.git/hooks/pre-commit` 에만 붙어 있던 동작이 공장에 올라오지 않아, 새 클론에 재설치(`309ffae`)하면서 사라진 것으로 보인다 — 백로그 "새 클론에 하네스 설치물이 따라오지 않는 문제"(`97c2938`)와 같은 종류.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 — `.harnessrc` 에 `UPSTREAM_REF` 가 있고 그 ref 가 있으면, 스테이징된 파일이 그 ref 에 이미 있는 경우(원본 소유) R-size 가 막지 않는다. — 검증: `bash tests/r-size-upstream-owned-test.sh`
- [x] G2 — 포크가 새로 만든 파일(그 ref 에 없는 파일)은 지금처럼 500줄 초과 시 막는다. — 검증: 같은 시험
- [x] G3 — `UPSTREAM_REF` 가 설정됐는데 ref 가 없으면(받아오지 않은 클론) 지금처럼 막되, 안내에 `git fetch` 를 적는다. 조용히 통과시키지 않는다. — 검증: 같은 시험
- [x] G4 — `UPSTREAM_REF` 가 없는 프로젝트는 동작이 바뀌지 않는다. — 검증: 같은 시험 + 기존 공장 시험 전체
- [x] G5 — 빠진 판정은 게이트 이벤트에 남는다 (몰래 통과 금지). — 검증: 같은 시험이 출력에서 원본 소유 안내 줄을 확인

- [ ] G6 — jj-agent-room 에 재설치한 뒤, 그 저장소에서 막혔던 Step 1 커밋(원본 파일 `router.ts`·`daemon.ts`·`registry.ts` 수정 포함)이 R-size 에 막히지 않고 게이트를 통과한다. — 검증: 그 저장소 `git commit` 출력에 `[R-size:upstream]` 3줄, `[R-size]` 차단 0

## 2-bis. 착수 전 확인한 사실 (2026-10-15)

| 확인한 것 | 결과 |
| --------- | ---- |
| 공장 `assets/hooks/pre-commit.sh` 의 `UPSTREAM_REF` | 0건. `.harnessrc` 는 21행에서 `source` 만 한다 |
| R-size 루프 | 144~167행, `CHECKABLE` 각 파일의 `wc -l` > `MAX_LINES_HARD`(500) 면 차단 |
| 공장 전체 `UPSTREAM_REF` 이력 (`git log --all -S`) | 0건 |
| `.harnessrc` 가 가리키는 공장 문서 | 없음 |
| jj-agent-room `upstream/main` | `ae9e21e` (2026-10-15 받아옴) |

## 3. 비목표 (Out of Scope)

- 원본 소유 파일의 증가량 제한(예: 포크가 원본 파일에 N줄 넘게 더하면 경고) — 필요가 생기면 별도 계획
- R-cx 등 다른 게이트의 원본 파일 취급
- 새 클론에 하네스 설치물이 따라오지 않는 문제 전체 — 백로그 그대로

## 4. 영향 영역

- 코드: `assets/hooks/pre-commit.sh` — R-size 루프에서 원본 소유 파일을 건너뛰고 안내 줄을 남김, ref 없음 안내
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `tests/r-size-upstream-owned-test.sh` — 임시 git 저장소에서 pre-commit 을 돌려 G1~G5 를 확인
- 룰: R-size (`docs/design-docs/core-beliefs.md#r-size`) — 문서에 "포크 프로젝트의 `UPSTREAM_REF`" 한 줄 추가
- 데이터: 없음
- 외부 의존: 없음. `git cat-file -e <ref>:<path>` 만 쓴다

## 5. 단계 (Steps)

### Step 1. 시험 먼저 [TDD]

- 산출: `tests/r-size-upstream-owned-test.sh` — RED 확인

### Step 2. 게이트 수정 [Impl]

- 산출: `pre-commit.sh` R-size 루프 수정, core-beliefs R-size 문단 한 줄
- 검증: 새 시험 GREEN + 공장 시험 전체

### Step 3. 반영 [단순]

- 공장 커밋·푸시 → jj-agent-room 에 재설치 → 그 저장소의 막힌 Step 1 커밋을 게이트 통과로 커밋

## 6. 의사결정 로그

- 2026-10-15: 원본 판정은 "그 ref 에 같은 경로의 파일이 있는가" — 근거: `.harnessrc` 문구("원본에 이미 있는 파일은 원본 소유")와 같은 정의, git 명령 하나로 판정 가능
- 2026-10-15: ref 가 없으면 막는다(조용히 통과 금지) — 근거: 받아오지 않은 클론에서 포크 파일까지 통과하면 R-size 가 무력해진다
- 2026-10-15: 사용자 지시로 계획 → 구현 → 커밋·푸시까지 이 세션에서 진행 (공통 반영 승인)

## 7. 발견·예외

- jj-agent-room `.harnessrc` 가 근거로 든 공장 문서 `docs/audits/2026-10-14-r-size-fork-upstream-files.md` 는 공장에 없다. 이전 PC 에 푸시 안 된 작업이 남아 있을 수 있다 — 확인되면 이 계획과 합친다.

- 2026-10-15 검증: 새 시험 7/7 통과. 공장 전체(run-all 134개)는 두 번 돌려 매번 다른 2개가 실패
  (1회차 doc-counts·update-all-roundtrip, 2회차 update-all-roundtrip·precompact-summary).
  doc-counts 는 시험 수 129→130 으로 문서 수치가 낡은 것 → `scripts/sync-doc-counts.sh` 로 맞춤.
  나머지 둘은 혼자 돌리면 통과 — 병렬 실행 때의 흔들림으로 이번 변경(R-size 판정)과 무관. 별도 확인 대상

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:

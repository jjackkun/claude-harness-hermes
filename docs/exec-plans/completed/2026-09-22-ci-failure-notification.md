# 2026-09-22-ci-failure-notification — 스케줄 워크플로가 실패하면 이슈로 알린다

출처: `docs/audits/2026-09-21-ci-failure-notification.md` (2026-09-21 weekly-gardening-red 회고 §8)

---

## 1. 동기 (Why)

`weekly-doc-gardening`(schedule) 이 08-30 · 09-06 · 09-13 · 09-20 네 번 연속 실패했는데 4주 동안 아무도 몰랐다.
push CI 는 커밋 화면에 빨간 표시가 뜨지만 schedule 워크플로는 보는 사람이 없다. 검사가 죽으면 검사가 없는 것과 같다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 워크플로 단계가 실패하면 제목이 고정된 이슈가 열린다. 같은 제목의 열린 이슈가 있으면 새로 열지 않고 댓글로 실행 링크를 단다. 검증: `tests/workflow-failure-notice-test.sh` — 알림 단계의 스크립트를 템플릿에서 꺼내 node 로 가짜 `github`·`context` 에 돌려, 열린 이슈가 없으면 `issues.create` 1회, 있으면 `issues.createComment` 1회.
- [x] 목표 2 — 알림이 실패해도 알림이 새 실패를 만들지 않는다. 검증: 같은 시험 — 알림 단계에 `if: failure()` 와 `continue-on-error: true` 가 있고, 가짜 `github` 가 예외를 던져도 스크립트가 처리되지 않은 거부 없이 끝난다(로그만).
- [x] 목표 3 — 공장 설치본에 반영된다. 검증: `.github/workflows/weekly-doc-gardening.yml` 본문이 템플릿과 같다(마커 줄 제외).

## 2-bis. 착수 전 확인한 사실 (2026-09-22)

| 확인한 것 | 결과 |
| --------- | ---- |
| schedule 워크플로가 있는 곳 | 공장 1곳(`.github/workflows/weekly-doc-gardening.yml`). 나머지 11곳에는 `.github/workflows/` 에 `schedule:` 이 없다 |
| 공장 워크플로의 출처 | 템플릿 `assets/cron-templates/github-actions/weekly-doc-gardening.yml` 을 설치기가 마커(`harness-template-sha`)와 함께 복사(`lib/harness_installers.sh:504`). 본문이 템플릿과 같다 — 템플릿을 고치고 재설치하면 갱신된다 |
| 권한 | 워크플로에 이미 `issues: write`, 이슈 생성에 `actions/github-script@v7` 사용 중 |
| node | v22.15.1 — 스크립트를 로컬에서 돌릴 수 있다 |
| gh 인증 | 이 머신은 미로그인 — 세션 훅 방식은 조용히 넘어가야 해서 이번에는 쓰지 않는다 |

## 3. 비목표 (Out of Scope)

- GitLab 템플릿(`gitlab-ci/weekly-doc-gardening.gitlab-ci.yml`). 배치된 11곳 어디서도 CI 에 등록되지 않아 실행되지 않는다. GitLab 은 파이프라인 실패 메일을 기본으로 보낸다.
- 세션 시작 훅으로 `gh run list` 를 보는 방식. 워크플로가 한 곳뿐이고 이 머신의 `gh` 가 미로그인이다.
- push CI(`ci.yml`) — 커밋 화면에 이미 보인다.

## 4. 영향 영역

- 코드: `assets/cron-templates/github-actions/weekly-doc-gardening.yml` — 마지막 단계로 실패 알림 추가. 공장 설치본은 재설치로 갱신.
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `tests/workflow-failure-notice-test.sh` — 스케줄 워크플로의 실패 알림 단계가 이슈를 한 번만 열고 이후엔 댓글을 다는지, 알림 실패가 새 실패를 만들지 않는지 시험한다.
- 룰: 없음
- 데이터: 없음
- 외부 의존: GitHub REST(`issues.listForRepo` · `issues.create` · `issues.createComment`) — 기존 단계와 같은 권한.

## 5. 단계 (Steps)

### Step 1. 시험 먼저 [단순]
- 산출: `tests/workflow-failure-notice-test.sh` (알림 단계가 없어 실패)

### Step 2. 템플릿에 알림 단계 [Impl]
- 검증: 새 시험 통과 + `doc-gardening-drift-test.sh` 6절(본문이 끝까지 돈다) 회귀 없음

### Step 3. 공장 재설치 [단순]
- `project-claude.sh` 로 공장 한 곳만. 다른 소우주는 워크플로가 없으므로 전파 대상이 아니다.
- 검증: 목표 3

## 6. 의사결정 로그

- 2026-09-22: 알림 수단은 이슈(고정 제목, 열린 것이 있으면 댓글) — 근거: 워크플로가 이미 편차 보고를 이슈로 연다. 같은 곳에 모이고, 고정 제목으로 매주 새 이슈가 쌓이지 않는다.
- 2026-09-22: 공장만 재설치한다 — 근거: `update-all` 은 9곳의 설치 기록(factory_commit)을 다시 바꿔 전파 커밋을 한 벌 더 만든다. 이 템플릿을 쓰는 곳은 공장뿐이다.

## 7. 발견·예외

### 공장 설치본이 4주 동안 "사용자 수정본" 으로 얼어 있었다

- 첫 재설치에서 설치기가 `workflows → … (사용자 수정 감지 — 보존)` 을 냈다. 알림 단계가 공장에 들어가지 않았다.
- 원인: 직전 수정 `a1694a8`(weekly-gardening-red)이 템플릿과 공장 설치본을 **손으로 똑같이** 고치고 설치본의 마커(`harness-template-sha`)는
  옛 값(`5915c6…`) 그대로 뒀다. 본문 해시(`3a0aba…`)는 그 시점 템플릿과 정확히 같았지만 마커와 달라 설치기가 사용자 수정으로 판정했다
  (`lib/harness_installers.sh:521-530`). 이 판정은 이후 모든 템플릿 개정을 막는다.
- 처리: 본문이 직전 템플릿과 같음을 해시로 확인한 뒤 마커를 본문 해시로 바로잡고 재설치 → `(배치)`, 새 마커 `ad96fb…` = 본문 해시.
- 교훈: 설치본은 손으로 고치지 않고 템플릿을 고친 뒤 재설치한다. 손으로 고치면 마커가 어긋나 설치기가 그 파일을 영원히 놓는다.

### 검증 (2026-09-22)

- `tests/workflow-failure-notice-test.sh` 14/14 — 고치기 전 13개 실패를 먼저 확인했다. 알림 script 를 템플릿에서 꺼내 node 로 가짜 `github` 에 실제로 돌린다.
- `doc-gardening-drift-test.sh` 27/27 — 6절(검사 본문이 끝까지 돈다) 회귀 없음.
- YAML 파싱: 템플릿·설치본 모두 단계 4개, 마지막 단계 `if: failure()` · `continue-on-error: true`.
- 실제 GitHub 에서의 동작은 이 머신의 `gh` 미로그인으로 확인하지 못했다 — 다음 실패 때 또는 `workflow_dispatch` 로 확인할 수 있다.
- 전체 시험 97/97 (`bash tests/run-all.sh`, EXIT=0).

## 8. 회고 (완료 시 작성)

- 잘된 것: 알림 script 를 grep 으로 확인하지 않고 템플릿에서 꺼내 node 로 **실제로 돌렸다**. "YAML 안에만 있는 로직" 이 세 번째 사고가 되지 않게 했다.
  실패 경로(GitHub 호출 예외)도 가짜 객체로 재현해 알림이 새 실패를 만들지 않음을 확인했다.
- 잘못된 것: 설치본이 4주 동안 갱신 불가 상태였던 것을 이번 재설치에서야 알았다. 직전 수정이 설치본을 손으로 고치며 마커를 그대로 둔 탓이다(§7).
  설치기는 경고(`사용자 수정 감지 — 보존`)를 냈지만 `info` 줄이라 전파 때 눈에 띄지 않았다.
- 다음 룰 후보: "설치본은 손으로 고치지 않는다 — 템플릿을 고치고 재설치한다." 한 번 더 나오면 R 룰로 올리고,
  공장 자기 설치에서 마커 불일치를 경고로 올리는 것을 함께 본다.

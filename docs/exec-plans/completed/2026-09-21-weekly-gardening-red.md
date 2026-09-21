# 2026-09-21-weekly-gardening-red — 주간 문서 점검이 4주 연속 실패한 원인 제거

> 출처: `docs/exec-plans/backlog/weekly-doc-gardening-red.md` (본 계획으로 승격)
> 설계 결정 인용: 없음 — CI 워크플로 템플릿의 버그 수정. 원장 결정과 무관.

## 1. 동기 (Why)

`weekly-doc-gardening`(schedule) 이 08-30 · 09-06 · 09-13 · 09-20 네 번 연속 실패했고 아무에게도 알리지 않았다.
backlog 의 가설("편차 스크립트가 종료코드 1 을 돌려준다")은 **실측으로 틀렸다**: `doc-gardening-drift.sh` 는 rc 0 이다.

로컬 재현(2026-09-21, 단계 본문을 `bash -x` 로 그대로 실행 → rc 1): 3단계의

```bash
rid=$(echo "$rule" | grep -oE '^R[0-9]+')
```

에서 `$rule` 은 `## R5 — 우회 금지 {#r5}` 이므로 `^R` 앵커가 절대 매치되지 않는다. `grep` 이 1 을 돌려주고 `set -euo pipefail`
때문에 **첫 반복에서 단계가 죽는다**. 결과:

- 3단계(R 룰 ↔ 강제 장치)는 **한 번도 실행된 적이 없다** — "죽은 status grep" 과 같은 종류의 조용한 무발화(템플릿 §2 주석이 경고한 그것).
- 4단계(룰 승격 후보)도 도달하지 못한다.
- `has_drift` 를 쓰기 전에 죽으므로 이슈도 열리지 않는다.

같은 정규식이 GitHub 템플릿·GitLab 템플릿·공장 설치본 **3곳**에 있다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 세 파일의 `^R[0-9]+` 를 고쳐 단계 본문이 끝까지 돈다 — 검증: `bash tests/doc-gardening-drift-test.sh` §6
- [x] 목표 2 — 시험이 이 부류(단계 본문이 중간에 죽음)를 잡는다: 템플릿 두 판의 검사 본문을 픽스처 저장소에서 `set -euo pipefail` 로
  돌려 rc 0 과 `has_drift` 기록을 단언하고, 옛 정규식을 심으면 빨강 — 검증: 같은 절(자기 검사 포함)
- [x] 목표 3 — 처음으로 실행되는 3·4단계가 쏟아지지 않는지 실측: 공장 저장소에서 보고 줄 수를 세어 계획서 §7 에 기록
  — 검증: 로컬 실행 출력
- [x] 목표 4 — 훅과 CI 의 역할 구분을 문서에 남긴다(backlog 질문 "CI 가 실제로 필요한가") — 검증: §7 기록 + 템플릿 머리말 한 줄
- [x] 목표 5 — 설치본 갱신: 공장 `.github/workflows/weekly-doc-gardening.yml` 이 새 템플릿과 같아진다
  — 검증: `bash tests/doc-gardening-drift-test.sh` §3 + `diff` 로 본문 동일

## 3. 비목표 (Out of Scope)

- 3·4단계 검사 로직을 공용 스크립트로 옮기는 것 — 훅 출력까지 바뀌어 12곳에 영향. 이번은 "죽지 않게" 까지.
- 실패 알림(워크플로 실패 시 이슈·메일) — 별도 항목.
- GitLab 쪽 실행 확인 — 그 판은 스케줄이 걸린 프로젝트가 없다(설치 안내만).

## 4. 영향 영역

- 코드: `assets/cron-templates/github-actions/weekly-doc-gardening.yml`,
  `assets/cron-templates/gitlab-ci/weekly-doc-gardening.gitlab-ci.yml`, `.github/workflows/weekly-doc-gardening.yml`(설치본),
  `tests/doc-gardening-drift-test.sh`(절 추가)
- **신규 파일 목록**: 없음
- 룰: 없음. 템플릿 개정이므로 `harness-template-sha` 는 설치기가 다시 계산한다
- 데이터: 없음

## 5. 단계 (Steps)

### Step 1. 시험 절 추가(RED) → 정규식 교정(GREEN) [단순]
### Step 2. 3·4단계 첫 실행 결과 실측·기록 [단순]
### Step 3. 설치본 갱신·전체 스위트 [단순]

## 6. 의사결정 로그

- 2026-09-21: 앵커를 없애고(`grep -oE 'R[0-9]+' | head -1`) `|| true` 로 감싼다 — 근거: 매치 실패가 곧 단계 사망이 되지 않아야 한다.
  형식이 또 바뀌어도 그 항목만 건너뛴다.
- 2026-09-21: 시험은 정규식이 아니라 **단계 본문 실행**을 단언한다 — 근거: 같은 부류(중간에 죽는 검사)가 또 생기면 정규식 grep 은 못 잡는다.

## 7. 발견·예외

- **목표 3 실측(교정 뒤 첫 실행, rc 0)**: 보고 15줄 — 전부 `rule-candidate`(4단계). 3단계 `rule-unenforced` 는 **0건**
  (모든 R 룰이 코드·테스트에 언급돼 있다). 쏟아지지 않는다. 상위: `assets/hooks/pre-commit.sh`(12회) ·
  `presets/workflow/harness.conf`(8) · `CLAUDE.md`(8) · `tests/harness-hooks-smoke.sh`(7) · `tests/run-all.sh`(6) ·
  `docs/design-docs/core-beliefs.md`(6). 다음 일요일부터 이슈 1개가 열린다 — 정보성이고 주 1회라 받아들인다.
- **목표 4 — 훅과 CI 의 역할(backlog 질문 "CI 가 실제로 필요한가")**: 세션 시작 훅은 공용 스크립트만 부른다
  (`claude-sessionstart-doc-gardening.sh:65`) → **exec-plans 편차만**. 오늘 공장에서 훅 보고 0줄.
  CI 는 그 위에 **CLAUDE.md dead-link · R 룰 미강제 · 룰 승격 후보** 셋을 더 본다. 겹치지 않으므로 **CI 를 유지한다.**
  단 그 셋은 YAML 안에만 있어 시험이 닿지 않았다 — 이번에 §6 이 "본문이 끝까지 도는가" 만 고정했고, 검사 내용 자체를
  공용 스크립트로 옮기는 것은 비목표(훅 출력이 12곳에서 바뀐다).
- backlog 의 원인 가설(편차 스크립트가 1 을 돌려줌)은 틀렸다 — 그 스크립트는 rc 0 이다. 추정을 문서에 남길 때는
  "추정" 표시가 있었고, 실측이 뒤집었다. 표시가 있어서 빨리 버릴 수 있었다.

## 8. 회고 (완료 시 작성)

- 잘된 것: 정규식을 grep 으로 확인하는 시험 대신 **단계 본문을 실제로 돌리는** 시험을 넣었다. 자기 검사(옛 줄을 되돌려 심으면 빨강)까지
  붙여 "통과만 보는 시험" 을 피했다.
- 잘못된 것: 이 워크플로는 4주 넘게 빨간 채였고 아무도 몰랐다. 실패 알림이 없다는 것이 진짜 결함이다(비목표로 뒀지만 backlog 로 남긴다).
- 다음 룰 후보: "CI 워크플로의 검사 본문은 로컬에서 실행되는 시험을 갖는다" — YAML 안에만 있는 로직은 이번이 두 번째 사고다
  (죽은 `status:` grep, 이번 `^R` 앵커). 세 번째면 R 룰로 승격.

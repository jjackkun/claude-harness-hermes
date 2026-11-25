# 2026-11-25-manifest-batch-write — 설치 목록 기록을 설치 끝에 한 번에 쓴다

계기: 사용자가 준 영상(찐AI "느린 5%만 Rust로, fast-anything", 2026-11-24) — 프로파일로 가장 느린 함수
하나를 찾고, 바꾼 뒤 원래 답과 하나하나 대조해 같을 때만 바꾼다. 이 방법을 공장 설치기에 적용한다.

## 1. 동기 (Why)

- 2026-11-25 실측: `project-claude.sh <새 프로젝트> harness hermes` 1회 14.3초, 재설치 14.7초.
- `bash -x` 줄 단위 프로파일: `manifest_add` 가 설치 시간의 53~55%. 설치 1회에 347번 불리고,
  부를 때마다 `python3` 를 새로 띄워 JSON 전체를 읽고·고치고·다시 쓴다. `git rev-parse HEAD` 도 347번.
- 이 함수만 따로 347번 돌리면 9.5초.
- 전체 시험의 벽시계는 가장 긴 `copy-install-test.sh`(261초, 설치 12회)가 정한다. 상위 3개 시험이 모두 설치를 반복한다.
  update-all 은 프로젝트마다 설치를 돈다.
- 느린 원인은 계산이 아니라 프로세스 기동 횟수다 — 다른 언어로 옮길 일이 아니라 호출을 묶을 일이다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 설치 결과가 바이트까지 같다 — 검증: 고치기 전 기준선(새 설치·재설치·프리셋 줄이기 3장면)의
      `.factory-manifest.json` 과 설치 파일 전체 해시를 고친 뒤와 대조. 다르면 되돌린다.
- [x] G2 설치 1회 시간이 줄어든다 — 검증: 같은 기계에서 새 설치·재설치 전후 시간(초).
- [x] G3 라이브러리를 직접 부르는 쪽(uninstall·시험)은 동작이 그대로다 — 검증: `install-coexist-test.sh`
      · `copy-install-test.sh` · `harness-doctor-test.sh` 통과.
- [x] G4 설치가 중간에 죽어도 기록이 사라지지 않는다 — 검증: 모아 둔 기록 파일이 남은 상태에서 다음
      manifest 호출이 그것을 먼저 반영하는 시험.

## 2-bis. 착수 전 확인한 사실 (2026-11-25)

| 확인한 것 | 결과 |
| --------- | ---- |
| `manifest_add` 호출 수(설치 1회) | 347 (새 설치·재설치 같음) |
| `.factory-manifest.json` 을 직접 읽는 곳 | `harness-doctor.py` · tamper-warn 훅 · 시험 — 모두 설치 프로세스 밖 |
| 라이브러리를 source 하는 진입점 | `lib/common.sh`(project-claude·project-codex·public-claude) · `uninstall.sh` · 시험 2개 |
| 설치 중 manifest 를 읽는 함수 | `manifest_field`·`manifest_verify`·`manifest_prune` 등 — 모두 이 라이브러리 안 |

## 3. 비목표 (Out of Scope)

- 파일 복사(`install_factory_file`, 약 20%)·해시 계산 구조 변경.
- 설치 밖(훅·스킬)의 속도 — 따로 조사해 결과만 보고한다.

## 4. 영향 영역

- 코드: `lib/factory_manifest.sh`(모아 쓰기·비우기), `project-claude.sh`·`project-codex.sh`(묶음 시작·끝)
- **신규 파일 목록**:
  - `tests/manifest-batch-test.sh` — 묶음 모드의 결과 동일성·중간 사망 복구를 재는 시험
- 룰: 없음. 데이터: 없음(목록 형식 그대로).

## 5. 단계 (Steps)

### Step 1. 기준선 [단순]
- 산출: 고치기 전 3장면의 목록·파일 해시(스크래치).

### Step 2. 구현 [Impl]
- `manifest_add` 는 기록을 `<목록>.pending` 에 한 줄 덧붙인다. 묶음 모드가 아니면 바로 비운다(지금과 같은 동작).
- 묶음 모드(`manifest_batch_begin`~`manifest_batch_end`)면 설치 끝에 한 번 비운다. 읽는 함수는 먼저 비운다.
- 묶음 안에서만 공장 커밋 값을 한 번 읽어 둔다.

### Step 3. 검증 [Review]
- G1~G4. 관련 시험 실행.

## 6. 의사결정 로그

- 모아 둔 기록을 셸 변수 대신 파일에 둔다 — 서브셸에서 부른 manifest_add 도 잃지 않고, 중간에 죽어도 다음 호출이 반영한다.
- 묶음 모드는 진입 스크립트가 켤 때만 — 직접 source 하는 쪽은 지금처럼 바로 쓴다.

- codex 설치(`project-codex.sh`)는 손대지 않았다 — 기준선에서 `.factory-manifest.json` 을 만들지 않았다(manifest_add 0회).
- 해시 계산(`_manifest_sha` 의 awk 등)은 그대로 둔다 — 비목표. 남은 큰 몫은 파일 복사다.

## 7. 발견·예외

- 라이브러리를 다시 source 하면 묶음 상태 변수가 ""로 지워졌다(대조 스크립트를 짜다 발견). 변수 초기화를
  `${VAR:-}` 로 바꿔 다시 source 해도 묶음이 유지되게 했다.
- 기준선 잡음: `.dev-setting-manifest.json`(시각) · `.hermes/agents.json` · `.hermes/universe.id`(무작위 UUID) ·
  `.hermes/state.db` · `*.backup-<시각>` 폴더 이름. 고치기 전 두 번 찍은 기준선끼리도 이 다섯만 달랐다.
- 같은 날 설치 밖도 조사했다(서브에이전트, sonnet): pre-commit 게이트 전체 0.27~0.31초, 세션 종료 학습 루프는
  백그라운드(setsid), 스킬 스크립트(review_scope.py) 0.03~0.04초 — 사용자가 기다리는 곳은 설치뿐이었다.

## 8. 회고 (완료 시 작성)

실측(2026-11-25, 같은 기계):

| 장면 | 고치기 전 | 고친 뒤 |
| ---- | -------- | ------- |
| 새 설치 harness hermes | 13.9초 | 7.8초 |
| 재설치 | 14.8초 | 9.1초 |
| 로컬 수정 뒤 재설치 | 15.1초 | 9.0초 |
| 프리셋 줄이기(hermes) | 11.6초 | 7.3초 |
| codex 설치(목록 안 씀) | 1.0초 | 1.1초 |

- G1: 5장면 파일 432·432·441·287·40개와 설치 목록 4개가 기준선과 같다(잡음 다섯 종 제외, 기준선끼리도 같은 잡음).
  옛 `manifest_add` 와도 공백·탭·한글 이름·`manifest_mark` 섞은 순서에서 바이트까지 같다.
- G3: 설치 관련 시험 10개 통과. 10개를 동시에 돌린 시간 — copy-install 103초 · update-all-roundtrip 123초 ·
  preset-lock-tracked 82초(이전 기록 261·206·199초는 2026-11-02 전체 묶음 안에서 잰 값이라 조건이 다르다).
- G4: `tests/manifest-batch-test.sh` 17개 단언 통과(중간 사망 뒤 다음 호출이 반영).
- 리뷰(code-reviewer, sonnet): CRITICAL 0 · HIGH 0 · MEDIUM 1 · LOW 3. 반영 2 — `manifest_batch_end` 가 한 목록
  쓰기에 실패해도 나머지를 비우고 등록 파일을 지운 뒤 1 을 돌려준다(MEDIUM) · 쓰다 죽어 잘린 기록은 버린다(LOW).
  미반영 2 — 같은 프로젝트에 설치 둘이 동시에 도는 경쟁과 SIGKILL 뒤 `.pending` 잔존. 예전 코드에도 같은 경쟁이 있었고,
  잔존 파일은 다음 manifest 호출이 지운다. 시험 22개 단언.
- 배운 것: 느린 곳은 짐작(훅)이 아니라 프로파일이 가리킨 곳(설치)이었다. 훅·게이트는 모두 0.3초 아래였다.

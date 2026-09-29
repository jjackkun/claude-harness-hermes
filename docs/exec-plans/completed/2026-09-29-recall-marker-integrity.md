# 2026-09-29-recall-marker-integrity — 회상 표시가 진짜 세션 ID 로만 쌓이게 한다

> 출처: 2026-09-29 DB 쓰임새 논의(기억·회상). 앞선 계획 `completed/2026-09-29-skill-yield-integrity.md` 와 같은 결의 잡음 정리.
> 측정일: 2026-09-29, 이 저장소(공장)와 소우주 `.hermes/state.db`.

## 1. 동기 (Why)

다음 세션 첫 프롬프트에 직전 요약을 넣는 회상은 `recall_marker` 표에 "이 세션엔 넣었음" 을 적어 세션당 한 번만 나가게 한다. 그 표가 세션 ID 가 아닌 글로 채워지고 있다.

1. **표시의 대부분이 가짜다.** 공장 203건 중 176건(86%), `zeroday-frontend` 1,746건 중 1,503건(86%), `terminal-shipping` 414건 중 405건(97%)이 UUID 모양이 아니다. 예: `  "defaultMode": "bypassPermissions"`, 사용자의 질문 한 줄, 경로 문자열.
2. **원인은 훅의 세션 ID 읽기다.** `assets/hooks/claude-userpromptsubmit-mistake-detect.sh` 는 `jq` 가 없으면 파이썬 대체 경로가 "프롬프트, 세션 ID" 순으로 줄을 출력하고 `sed -n 2p` 로 세션 ID 를 읽는다. 프롬프트가 여러 줄이면 프롬프트의 2번째 줄이 세션 ID 가 된다. 이 기계에는 `jq` 가 없다(`command -v jq` 비어 있음). 한 줄로 재현했다.
3. **결과:** 여러 줄 프롬프트마다 "이 세션은 아직 회상 안 받았다" 로 판단해 같은 요약이 세션 안에서 다시 주입될 수 있고, 표에는 쓸모없는 행이 쌓인다.

> 여기까지 다시 읽었다: 고칠 것은 (가) 훅이 세션 ID 를 올바로 읽는 것, (나) 이미 쌓인 가짜 행을 지우는 것 둘이다. 회상 내용 자체·요약 저장은 손대지 않는다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — **여러 줄 프롬프트에서도 회상 표시에 진짜 세션 ID 가 들어간다.** 두 줄짜리 프롬프트를 훅에 넣으면 `recall_marker` 에 그 세션 ID 한 행만 생긴다. 검증: `bash tests/hermes-recall-marker-integrity-test.sh` §1.
- [x] 목표 2 — **같은 세션에서 여러 줄 프롬프트를 여러 번 보내도 회상은 한 번만 나간다.** 검증: 같은 시험 §2(주입 본문 횟수 1).
- [x] 목표 3 — **쌓인 가짜 표시를 지우는 명령을 둔다(삭제는 사람이 정한다).** `hermes-recall-repair.py` 는 기본이 미리보기이고, `recall_marker` 에서 UUID 모양이 아닌 세션 ID 행을 센다. `--apply` 일 때만 지우고, 지우기 직전 DB 를 sqlite 백업 API 로 복사한다. 진짜 UUID 행은 그대로 둔다. 검증: 같은 시험 §3(미리보기는 DB 무변경, apply 는 가짜 행만 지움, 백업 생성).
- [x] 목표 4 — **문서·등록.** 새 스크립트 둘을 `presets/workflow/hermes.conf` 복사 목록과 `.deprc` 에 넣고, 새 시험을 `tests/run-all.sh` 에 등록한다. 합격 기준: `grep -c "hermes-recall-repair.py\|hermes_db_backup.py" presets/workflow/hermes.conf` 가 2 · `.deprc` 에도 두 파일 · `grep -c hermes-recall-marker-integrity-test tests/run-all.sh` 가 1 · `python3 scripts/hooks/complexity.py` 가 새·바뀐 스크립트에서 0 · `bash tests/run-all.sh` 의 실패 목록에 이 계획이 건드린 시험이 없다(마지막에 한 번). 그리고 `bash tests/hermes-yield-integrity-test.sh` 19건이 그대로 통과한다.

## 2-bis. 착수 전 확인한 사실 (2026-09-29)

| 확인한 것 | 결과 |
| --------- | ---- |
| `recall_marker` 가짜 비율 | 공장 176/203 · zeroday 1,503/1,746 · terminal-shipping 405/414 |
| `jq` 유무 | 없음 → 대체 경로만 쓰인다 |
| 같은 읽기 방식을 쓰는 다른 훅 | stop-retrospective·precompact-summary 는 첫 줄이 파일 경로, 둘째 줄이 세션 ID 라 줄바꿈이 없어 안전. subagentstop-summarize 는 3필드 모두 경로·이름이라 안전 |
| `session_reuse` | 비UUID 행은 정상 표식 `__epoch__` 하나뿐(`hermes_reuse.py` EPOCH_MARKER) — 오염 아님. 이 계획의 대상에서 뺀다(초안에서 "가짜 1건" 이라 한 것은 오판이었다) |
| 프롬프트를 읽는 다른 훅 | soul-approval-intent·hag 는 JSON 전체를 파이썬으로 읽어 안전 |
| 기존 시험의 세션 ID | `sessNEWEST` 등 비UUID 를 쓴다 → 회상 스크립트에 모양 검사를 넣지 않는다(훅에서 바로잡는다) |

## 3. 비목표 (Out of Scope)

- 회상 내용·요약 저장 방식 변경 없음.
- `hermes-recall.py` 에 세션 ID 모양 검사를 넣지 않는다(기존 시험과 충돌, 원인은 훅).
- `session_history` 검색 색인 잔재(1,166블록)는 이번에 다루지 않는다(내용 복원 여부 미확인).
- 소우주 DB 의 가짜 행 정리는 사람이 미리보기를 보고 정한다(이번 계획은 명령까지).

## 4. 영향 영역

- 코드(수정): `assets/hooks/claude-userpromptsubmit-mistake-detect.sh` 와 공장 자기 설치본 `scripts/hooks/claude-userpromptsubmit-mistake-detect.sh` **두 벌을 같게** · `scripts/hermes-yield-repair.py`(백업 함수를 공용 모듈로) · `presets/workflow/hermes.conf` · `.deprc` · `tests/run-all.sh`.
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `scripts/hermes-recall-repair.py` — 가짜 세션 ID 로 쌓인 회상 표시(`recall_marker`)를 미리보기로 세고, `--apply` 일 때만 지운다.
  - `scripts/hermes_db_backup.py` — DB 를 sqlite 백업 API 로 시각이 붙은 파일에 복사한다(정리 명령들이 공유).
  - `tests/hermes-recall-marker-integrity-test.sh` — 목표 1~3 의 합성 자료 시험(임시 프로젝트, 공장 DB 무변경 확인 포함).
- 룰: R-cx(함수당 복잡도 11 이하) · R-size.
- 데이터: `recall_marker` 의 가짜 행 삭제(`--apply` 일 때만).
- 되돌리기: 훅 수정은 git, 삭제는 백업 파일.

## 5. 단계 (Steps)

### Step 1. 훅 세션 ID 읽기 수정 + 시험 §1·§2 [Impl]
- 세션 ID 를 첫 줄, 프롬프트를 그 뒤 나머지로 읽는다(세션 ID 는 줄바꿈이 없다). 시험을 먼저 써서 실패(RED)를 확인한다.
- 검증: 시험 §1·§2, 두 벌 동일(`diff`).

### Step 2. 공용 백업 모듈 + 정리 명령 + 시험 §3 [Impl/Review]
- 산출: `hermes_db_backup.py`, `hermes-recall-repair.py`, yield-repair 가 공용 모듈을 쓰도록 교체. 공장에서 미리보기 후 적용.
- 검증: 시험 §3, 복잡도 검사, 기존 `hermes-yield-integrity-test.sh` 재실행.

### Step 3. 등록 · 전체 시험 · 회고 [Review]
- 산출: 복사 목록·계약·시험 등록, 문서 개수 동기화, 회고. 전체 시험은 **마지막에 한 번**.

## 6. 의사결정 로그

- 2026-09-29: 회상 스크립트에 세션 ID 모양 검사를 넣지 않는다 — 근거: 기존 시험이 비UUID ID 를 쓰고, 원인은 훅이라 훅에서 바로잡는 것이 맞다. 손해: 다른 경로가 가짜 ID 를 넘기면 다시 쌓인다(그 경로는 지금 없다).
- 2026-09-29: 훅이 프롬프트를 첫 줄이 아니라 **전체**로 읽게 된다 — 근거: `jq` 경로(`jq -r .prompt`)는 원래 전체를 읽고, 대체 경로만 첫 줄이라 기계마다 실수 감지 범위가 달랐다. 전체가 의도된 동작이다. 손해: `jq` 없는 기계에서 실수 카테고리 감지(키워드 두 그룹이 메시지에 함께 있을 때)가 여러 줄 프롬프트에서 더 자주 걸릴 수 있다. 되돌리는 법: 훅 한 줄.
- 2026-09-29: 가짜 행의 기준은 UUID 모양이 아닌 것 — 근거: 공장에서 진짜 세션 27건이 모두 UUID 이고 가짜는 문장·경로 조각이다. 미리보기가 표본을 보여 주므로 사람이 확인한다.

## 7. 발견·예외

- 시험은 `jq` 가 없는 기계에서만 대체 경로(결함 경로)를 실제로 돌린다. `jq` 가 있는 기계에서는 `jq` 경로를 시험하므로 회귀 방지는 되지만 결함 재현은 안 된다(이 기계는 `jq` 없음 — 수정 전 시험 8건 실패로 재현 확인).
- 전파: 훅은 소우주에 설치되는 자산이라 수정 후 `update-all` 전파가 필요하다. 시점은 사용자 지시에 따른다(이전 전파와 같은 절차: 설치물만 커밋·푸시, zeroday-frontend 는 설치까지).
- 백업: `state.db.bak-<날짜시각>` 은 `.hermes/` 안에 남고 git 이 무시한다. 보존 기간을 두지 않고 사람이 지운다(현재 공장에 하나 있음).
- 가짜 행 기준(UUID 모양 아님)은 진짜 세션 ID 가 UUID 가 아닌 환경에서는 진짜 행을 지울 수 있다. 방어는 미리보기가 표본 5건을 보여 주는 것과 백업이다.
- `session_history` 색인 잔재(원문 행 0, 색인 블록 1,166)는 별도 확인 대상이다.

## 8. 회고 (완료 시 작성)

- 잘된 것: 시험을 먼저 써서 수정 전 8건 실패로 결함을 재현한 뒤 훅 수정으로 10건 통과시켰다. 백업 함수를 공용 모듈로 뽑아 정리 명령 둘이 함께 쓴다.
- 잘못된 것: 조사 때 `session_reuse` 의 비UUID 행 1건을 "가짜" 라고 보고했는데 정상 표식 `__epoch__` 였다. 기준(UUID 모양)만 보고 내용을 열어 보지 않은 탓이다 — 검토가 짚기 전에 시험 작성 중 발견해 계획서를 바로잡았다.
- 다음 룰 후보: 훅이 stdin JSON 에서 여러 필드를 뽑을 때 줄 단위 출력에 자유 텍스트(프롬프트)를 섞지 않는다 — 자유 텍스트는 마지막 필드로 두거나 구분자를 쓴다.

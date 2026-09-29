# 2026-09-29-drop-dead-tables — 할 일이 없어진 DB 표 4개를 걷고 용량을 돌려받는다

> 출처: 2026-09-29 DB 쓰임새 논의 6번 표(할 일 없어짐). 관련 결정: 원문은 저장하지 않는다(T-23).
> 측정일: 2026-09-29, 공장·소우주 `.hermes/state.db` 와 `~/.hermes/global.db`.

## 1. 동기 (Why)

1. **죽은 표가 DB 용량의 대부분이다.** 지운 원문의 검색 색인 잔재(`session_history_data`)가 zeroday 48.2 MB 중 38.7 MB(80%), 공장 6.5 MB 중 4.7 MB(72%)다. 행은 0인데 조각이 남아 있다.
2. **표 4개가 아무 일도 안 한다.** 코드 참조를 전부 찾았다(아래 2-bis).
3. **읽는 곳이 항상 0 을 본다.** `/hermes-status` 와 셸 현황이 `session_history`·`harness_rules` 의 개수를 읽어 늘 0 을 보여 준다. 회상 `--query` 는 원문 검색이 항상 빈 결과라 요약 검색만 실질적으로 돈다.

> 여기까지 다시 읽었다: 걷을 것은 표 자체와 그 표를 읽고 쓰던 코드다. 전역 DB 의 `harness_rules`(옛 행 1,172개)는 데이터가 있어 건드리지 않는다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — **새 DB 는 죽은 표를 만들지 않는다.** `hermes-init.py` 가 `session_history`(검색 색인)·`harness_rules`·`compaction_log`·`session_reuse` 를 만들지 않는다. 검증: `bash tests/hermes-db-prune-test.sh` §1(초기화한 DB 에 네 표가 없다 · 나머지 핵심 표는 있다).
- [x] 목표 2 — **읽고 쓰던 코드를 걷는다.** 회상은 원문 검색 단계(`search_history`)와 재활용 기록(`mark_reused`)을 쓰지 않고, `hermes_reuse.py` 는 삭제(설치본에서도 걷힌다), `/hermes-status` 와 셸 현황은 죽은 표 대신 `session_summary` 의 요약 수를 보인다. 없는 표를 만나도 죽지 않는다. 검증: 같은 시험 §2(회상 주입·질의가 표 없이 동작 · 현황 출력 성공 · `hermes_reuse` 를 import 하는 곳 0) · 기존 회상 시험 통과.
- [x] 목표 3 — **옛 DB 를 정리하는 명령을 둔다(적용은 사람이 정한다).** `hermes-db-prune.py` 는 미리보기가 기본이고, 표마다 행 수와 DB 크기를 보인다. `--apply` 는 지우기 직전에 DB 를 백업하고 죽은 표를 지운 뒤 `VACUUM`·체크포인트로 용량을 돌려준다. 다른 프로세스가 DB 를 잠그고 있으면 아무것도 지우지 않고 이유를 알리며 실패(rc 1)하고, 표 삭제는 됐으나 `VACUUM` 만 실패하면 "표는 지웠으나 용량 회수는 재시도"로 구분해 알린다. 가상 표 모듈이 없어 못 지운 표는 건너뛰고 표시한다. 프로젝트 DB 는 네 표를, 전역 DB(`--global`)는 `harness_rules` 를 **남기고** 나머지 셋만 지운다. 다시 돌려도 안전하다(멱등). 검증: 같은 시험 §3(미리보기 무변경 · 적용 뒤 표 사라짐·다른 표 행 수 그대로·백업 존재·크기 감소 · 전역은 `harness_rules` 유지 · 재실행 무해 · **잠긴 DB 에서 실패하고 표가 그대로**).
- [x] 목표 4 — **기존 시험을 새 현실에 맞춘다.** 원문 비저장을 확인하던 시험(`COUNT(*) FROM session_history` = 0)은 "표가 없거나 0" 으로 바꾸고, 원문 검색 시험은 삭제한다. 검증: 관련 시험 통과(`hermes-pipeline-test.sh` · `hermes-redact-boundary-test.sh` · `hermes-cleanup-step5-test.sh` · 회상 시험).
- [x] 목표 5 — **등록·문서.** 새 스크립트·시험을 복사 목록·계약·시험 목록에 넣고, 걷은 `hermes_reuse.py` 를 설치기의 걷는 목록(`hermes_retired_scripts`)에 더하며, `docs/design-docs/hermes-engineering.md`·`docs/hermes-sync-guide.md` 의 표 언급을 고친다. 합격 기준: `grep -c hermes-db-prune presets/workflow/hermes.conf .deprc tests/run-all.sh` 각 1 이상 · `grep -c hermes_reuse.py presets/workflow/hermes.conf` 가 **정확히 1**(걷는 목록의 줄; 복사 목록의 줄은 지웠다) · `grep -c hermes_reuse .deprc .covbaseline` 0 · 복잡도 검사 0 · `bash tests/run-all.sh` 를 마지막에 한 번.

## 2-bis. 착수 전 확인한 사실 (2026-09-29)

| 표 | 만드는 곳 | 쓰는 곳 | 읽는 곳 | 행 수 |
| --- | --- | --- | --- | --- |
| `session_history` | `hermes-init.py` | 없음(원문 저장 중단) | `hermes-recall.py` `search_history` · `lib/hermes_memory.sh` · `assets/skills/hermes-status/SKILL.md` | 0 (색인 조각만 남음) |
| `harness_rules` | `hermes-init.py` | 없음(L-05 중단) | `lib/hermes_memory.sh` · `hermes-status` 스킬(프로젝트 DB 개수 + **전역 DB** 통계) | 프로젝트 0 · **전역 1,172** |
| `compaction_log` | `hermes-init.py` | 없음 | 없음 | 0 |
| `session_reuse` | `hermes-init.py` · `hermes_reuse.py` | `hermes-recall.py` `mark_reused` | `hermes_reuse.get_tracking_epoch` 뿐이고 그 함수를 부르는 곳이 없다(생애주기 점검은 어제 걷었다) | 공장 19 · zeroday 156 · terminal-shipping 8 |

| 확인한 것 | 결과 |
| --------- | ---- |
| 전역 DB | `~/.hermes/global.db` 에도 네 표가 있다. `harness_rules` 1,172 행만 데이터, 나머지는 0 |
| 걷는 목록 | 설치기가 `hermes_retired_scripts` 로 하류의 옛 스크립트를 지우고 설치 목록에서 뺀다(`presets/workflow/hermes.conf` 298행) |
| 시험 참조 | `session_history`: `hermes-redact-boundary-test.sh` · `hermes-pipeline-test.sh` · `hermes-recall-history-search-test.sh` / `harness_rules`: `hermes-cleanup-step5-test.sh`(자기 표를 만듦) · `hermes-pipeline-test.sh`(전역 쓰기 중단 확인) |
| 색인 조각 | 공장·zeroday 는 색인에 남은 낱말 0개(구조 조각뿐), terminal-shipping 만 영어 단어 4개 |

## 3. 비목표 (Out of Scope)

- 전역 DB 의 `harness_rules`(옛 행 1,172개)와 그것을 읽는 `/hermes-status` 의 "전역 패턴" 줄은 그대로 둔다.
- 오래된 주석(`claude-sessionstart-sync-pull.sh` 의 "session_history 로 올린다" 등 옛 설명)의 정리는 하지 않는다.
- 소우주 DB 정리의 **적용**과 커밋은 사람이 정한다(zeroday 는 사용자 몫, `--apply` 는 지시 뒤에). 이 계획에서 적용하는 것은 이 저장소(공장)의 `.hermes/state.db` 뿐이고, 사용자 전역 DB(`~/.hermes/global.db`)의 `--global --apply` 는 지시 뒤로 미룬다.
- `docs/hermes-universe/**`·`docs/superpowers/specs/**` 의 옛 설계 기록에 남은 표 언급은 과거 기록이라 그대로 둔다.
- 자율 루프 표(`loops`·`loop_steps`·`messages`)·운반 표(`sync_cursor`)는 살아 있는 기능이라 남긴다.

## 4. 영향 영역

- 코드(수정): `scripts/hermes-init.py`(표 4개 생성 제거) · `scripts/hermes-recall.py`(원문 검색·재활용 기록 제거) · `lib/hermes_memory.sh`(현황 함수를 요약 수로, **`search` 갈래와 `hermes_search` 함수는 부르는 곳이 없어 삭제**) · `assets/skills/hermes-status/SKILL.md`(규칙 칸 삭제, 세션 → 세션 요약) · `presets/workflow/hermes.conf`(복사 목록에서 `hermes_reuse.py` 제거 + 걷는 목록에 추가 + 새 스크립트 추가) · `.deprc`(삭제 파일 줄 제거 + 새 스크립트) · `.covbaseline`(삭제 파일 줄 제거) · `tests/run-all.sh` · 기존 시험 3개(`hermes-pipeline-test.sh` 원문 0 확인 4곳 + 전역 `harness_rules` 확인 · `hermes-redact-boundary-test.sh` 원문 0 확인 · 회상 시험) · 문서 2개.
- 삭제: `scripts/hermes_reuse.py` · `tests/hermes-recall-history-search-test.sh`(원문 검색 시험 — `tests/run-all.sh` 등록도 함께).
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `scripts/hermes-db-prune.py` — 죽은 표를 미리보기로 보이고, `--apply` 일 때만 백업 뒤 지우고 용량을 돌려준다(프로젝트/전역 모드).
  - `tests/hermes-db-prune-test.sh` — 목표 1~3 의 합성 자료 시험(옛 스키마 DB 를 직접 만들어 정리, 공장 DB 무변경 확인 포함).
- 룰: R3(모델 호출 없음) · R-cx(함수당 복잡도 11 이하) · R-declare.
- 데이터: 죽은 표 삭제(`--apply` 일 때만, 백업 후). 삭제되는 데이터는 `session_reuse` 행(공장 19 등, 사용처 없는 재활용 횟수)뿐이고 나머지는 0행이다.
- 되돌리기: 코드는 git, DB 는 `state.db.bak-<날짜시각>` 으로 되돌린다.

## 5. 단계 (Steps)

### Step 1. 시험 먼저 [Impl]
- `tests/hermes-db-prune-test.sh` §1~§3 을 쓰고 실패(RED)를 확인한다. §3 은 옛 스키마를 시뮬레이트한다: 네 표를 만들고 `session_history` 에 행을 넣었다 지워 색인 조각이 남게 한다.

### Step 2. 정리 명령 [Impl]
- `hermes-db-prune.py`: 미리보기 기본 · 적용 전 `hermes_db_backup.backup_db` · 표별 `DROP TABLE IF EXISTS` · `VACUUM` · 전후 크기 출력. 가상 표 삭제에 FTS 모듈이 없으면 그 표만 건너뛰고 이유를 출력한다.
- 검증: 시험 §3.

### Step 3a. 읽고 쓰는 코드를 표 없이도 돌게 고친다 [Impl]
- 회상(원문 검색·재활용 기록 제거), 셸 현황(`search` 갈래 포함), 현황 스킬을 고치고 기존 시험을 "표가 없거나 0" 으로 맞춘다. 이 상태에서 옛 DB(표 있음)와 새 DB(표 없음) 모두에서 시험이 통과해야 한다.
### Step 3b. 새 DB 에서 표 생성을 걷는다 [Impl]
- `hermes-init.py` 에서 네 표의 생성문을 제거하고 `hermes_reuse.py` 를 삭제·등록 정리한다.
- 검증: 시험 §1·§2, 관련 기존 시험.

### Step 4. 등록 · 문서 · 전체 시험 · 공장 정리 · 회고 [Review]
- 등록·문서·`sync-doc-counts`, 전체 시험 **한 번**, 공장 DB 에 `--apply`(로컬·백업), 회고. 소우주 적용과 전파는 지시 뒤.

## 6. 의사결정 로그

- 2026-09-29: `session_reuse` 도 걷는다 — 근거: 쓰는 곳(회상의 `mark_reused`)만 있고 읽는 함수를 부르는 곳이 없어 아무도 결과를 쓰지 않는다(생애주기 점검을 어제 걷었다). 손해: 행(공장 19 등)이 사라진다 — 재활용 횟수뿐이라 복구할 가치가 낮고 백업이 있다.
- 2026-09-29: 전역 DB 의 `harness_rules` 는 남긴다 — 근거: 1,172 행이 있고 `/hermes-status` 의 "전역 패턴" 줄이 읽는다. 쓰기는 이미 중단됐으니(L-05) 보존만 한다.
- 2026-09-29: 새 DB 에서 표 생성을 걷는다(코드에서만 지우는 것이 아니라) — 근거: 표가 남아 있으면 다음 사람이 "쓰이는 표"로 오해한다. 손해: 옛 DB 를 정리하지 않은 소우주는 표가 그대로 있다 — 동작에는 영향이 없고 정리 명령으로 지운다.
- 2026-09-29: 표가 없을 때 현황은 **그 칸을 없앤다**(0 을 보이지 않는다) — 근거: 프로젝트 `harness_rules` 는 늘 0 이라 정보가 없고, 셸 현황과 스킬 현황을 같은 형식(스킬 · 세션 요약)으로 맞춘다. 전역 통계 줄은 이미 표가 없으면 0 으로 보이게 예외 처리돼 있어 새 전역 DB 에서도 동작한다.
- 2026-09-29: 정리 명령은 `--apply` 일 때만 지우고 백업 뒤 진행한다 — 근거: 앞선 정리 명령들(옛 원장·옛 판정 표)과 같은 원칙.

## 7. 발견·예외

- 디스크 여유: `VACUUM` 은 DB 크기만큼 임시 공간이 필요하다(zeroday 48 MB 정도라 문제없음). 미리보기에서 여유를 재지는 않는다.
- `hermes-cleanup.py` 는 `USING fts5` 표를 찾아 최적화하는데 표를 걷으면 대상이 없어 아무 일도 하지 않는다(옛 가정이 남은 주석만 있다).
- 회상 `--query` 는 원문 검색 결과가 늘 비어 요약 검색만 돌던 상태였다 — 걷어도 사용자에게 보이는 결과는 같다.
- `/hermes-status` 의 "규칙 수" 줄은 프로젝트 DB 의 `harness_rules` 가 늘 0 이라 의미가 없다 — 줄을 없애는 쪽으로 고친다.

## 8. 회고 (완료 시 작성)

- 잘된 것: 시험을 먼저 써서 실패 11건을 확인한 뒤 구현했다(최종 22건 통과, 잠긴 DB 시험 포함). 공장 DB 가 6,680 KB → 1,468 KB(78% 감소)로 줄었고 요약 23 · 판정 1,597 · 주입 원장 1,836 은 그대로다. 전체 시험 122개 통과. 계획 검토가 구현 전에 짚은 것 — `hermes_memory.sh` 의 `search` 갈래 누락, 현황 형식 미확정, 삭제 파일의 `.deprc`·`.covbaseline` 줄, 잠금 처리 — 을 반영했다.
- 잘못된 것: 첫 정리 명령은 DB 가 잠겨 있어도 "지운 표 0개 … 표는 지웠으나 용량 회수 실패" 라는 앞뒤가 맞지 않는 문구를 냈다. 시험으로 재현해 잠금을 전체 중단 사유로 바꾸고 아무것도 못 지웠으면 용량 회수도 하지 않게 고쳤다. 또 시험의 옛 스키마 준비가 `hermes-init.py` 가 아직 표를 만들던 동안 "이미 있음"으로 중단돼 RED 원인이 헷갈렸다.
- 다음 룰 후보: (1) 표를 걷을 때는 "읽는 곳"을 `FROM`/`JOIN` 만이 아니라 표 이름 전체 grep 으로 찾는다(이번에 처음 조사는 `FROM` 만 봐서 스킬·셸 갈래를 놓쳤다). (2) 정리 명령의 잠금 실패는 항상 전체 중단으로 다룬다.
- 전파: 사용자 지시 뒤. 소우주는 새 코드가 설치되어도 옛 표가 남고(무해), `hermes-db-prune.py --apply` 로 각자 정리한다. 전역 DB(`--global`)는 `harness_rules` 를 남기고 나머지 셋만 지운다.

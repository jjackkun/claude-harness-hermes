# 2026-09-29-carry-privacy-decisions — 사람이 정한 판정(둠·지움)이 컴퓨터를 따라간다

> 출처: 2026-09-29 DB 쓰임새 논의(올리기 전 판정 · 운반). 앞선 계획: `completed/2026-09-29-privacy-gate-hardening.md`, 운반 원안 `completed/2026-09-28-carry-agent-knowledge.md`.
> 제외한 것(같은 논의의 사용자 결정): 대화 원문 암호화 보관소는 공장에 넣지 않는다(기억 `project-raw-vault-out-of-scope`).

## 1. 동기 (Why)

올리기 전 판정 표(`privacy_review`)는 DB 에만 있고 컴퓨터를 따라가지 않는다. 운반이 나르는 것은 "판정을 통과한 요약 문장"과 패턴 수뿐이다(`hermes_sync_learning.py`).

1. **사람이 한 결정이 사라진다.** 사용자가 폼으로 고른 둠(keep)·지움(drop)은 그 컴퓨터의 판정 표에만 남는다(실측: terminal-shipping 지움 3 · 둠 1). 새 컴퓨터는 같은 문장을 다시 판정하고, 개인적인 문장이면 사용자에게 **같은 질문을 다시** 한다.
2. **지움이 사라지면 안전에도 구멍이다.** A 에서 지움으로 정한 문장이 B 에서는 미판정이라, B 의 모델 판정이 우연히 통과시키면 올라갈 수 있다. 사람의 지움이 기계 판정보다 강해야 한다.
3. 결정은 해시(32자)와 상태(keep|drop)뿐이라 원문이 없다. 원문을 나르는 것이 아니므로 공용 프로젝트에 맞다.

> 여기까지 다시 읽었다: 나를 것은 "사람의 결정" 하나뿐이다. 기계 판정(clean·pending)은 규칙 버전에 따라 달라지므로 나르지 않고, 원문·문장도 나르지 않는다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — **사람의 결정이 운반 조각으로 올라간다.** 판정 표의 keep·drop 행마다 `decision/<문장 해시>/<결정 시각 압축>-<상태>.json` 을 낸다(경로에 상태를 넣어 같은 초의 다른 결정이 서로 다른 경로가 된다)(본문: 해시 · 상태 · 결정 시각, **원문 없음**). clean·pending 은 내지 않는다. 같은 결정은 한 번만 올린다. 결정을 바꾸면(시각이 달라지면) 새 조각이 오른다. 검증: `bash tests/hermes-sync-decision-test.sh` §1.
- [x] 목표 2 — **받는 컴퓨터가 결정을 판정 표에 넣는다.** 행이 없으면 만들고 · 기계 판정(clean·pending)은 사람 결정이 덮고(이때 원문을 비운다) · 사람 결정끼리는 결정 시각이 더 새로운 쪽이 이기고 **같은 시각이면 지움이 이긴다**(받는 순서와 무관하게 수렴) · 같은 조각을 두 번 받아도 같고 받은 뒤 기계 판정이 덮지 못한다 · 잘못된 조각(해시 모양 아님 · keep/drop 아님 · 시각 형식이 `YYYY-MM-DD HH:MM:SS` 아님)은 받지 않는다. 새 행의 `kind` 는 `decision` 으로 한다(`kind` 는 NOT NULL). 검증: 같은 시험 §2.
- [x] 목표 3 — **결정이 실제로 효과를 낸다.** 두 클론 사이에서 A 가 drop 한 문장은 B 에서 `allowed` 가 거짓이고, A 가 keep 한 문장은 B 에서 참이며 B 의 내보내기가 그 문장을 다시 판정하거나 묻지 않는다. 검증: 같은 시험 §3(bare 원격을 공유하는 두 클론, `hermes-sync.py` push·pull).
- [x] 목표 4 — **구 동작을 깨지 않는다.** 결정 조각은 받는 쪽이 접두어(`decision/`)로 가려 받고, 접두어를 모르는 옛 판은 건너뛴다. 요약·패턴 운반과 잠금 모드(암호문 조각은 열쇠 없는 평문 컴퓨터가 건너뜀)는 그대로다. 검증: 기존 `hermes-sync-test.sh` 통과 · 같은 시험 §4(잠금 모드에서도 결정 조각은 평문 · 옛 접두어 조각 무시).
- [x] 목표 5 — **등록·문서.** 새 스크립트·시험을 복사 목록·계약·시험 목록에 넣고 `docs/hermes-sync-guide.md` 의 운반 항목에 결정을 적는다. 합격 기준: `grep -c hermes_sync_decisions presets/workflow/hermes.conf .deprc` 가 각 1 이상 · `grep -c hermes-sync-decision-test tests/run-all.sh` 가 1 · 복잡도 검사 0 · `bash tests/run-all.sh` 를 마지막에 한 번.

## 2-bis. 착수 전 확인한 사실 (2026-09-29)

| 확인한 것 | 결과 |
| --------- | ---- |
| 운반 모듈 | `hermes_sync_learning.py`(186줄): `outgoing_learning`(요약·패턴 조각) · `import_learning`(접두어로 갈라 되넣음, 받은 경로를 `sync_cursor` 에 적음) |
| 조각 조립 | `hermes_sync_fragments.outgoing` 이 `outgoing_learning` 을 부르고 이미 올린/받은 경로(`done`)를 건너뜀 |
| 받기 분기 | `hermes-sync.py` `_import_all` 이 `summary/`·`pattern/` 접두어만 `import_learning` 에 넘김 → `decision/` 추가 필요 |
| 잠금 모드 | 조각의 값 중 `-----BEGIN AGE` 로 시작하는 것이 있으면 암호문으로 봐서 평문 컴퓨터가 건너뜀. 결정 조각은 해시·상태·시각뿐이라 값이 평문이므로 잠금 모드 컴퓨터가 올려도 평문 컴퓨터가 받는다 |
| 판정 표 | `privacy_review(hash PK, kind, ref, text, status, ts)`. `decide` 가 `ts=CURRENT_TIMESTAMP`(UTC, `YYYY-MM-DD HH:MM:SS`) 를 적는다 → 결정 시각으로 쓴다 |
| 사람 결정 보호 | `mark` 의 `ON CONFLICT … WHERE status NOT IN ('keep','drop')` 가 이미 기계 판정이 사람 결정을 못 덮게 한다 |
| 실제 결정 수 | 공장 0 · terminal-shipping 4 · zeroday 0 |
| 시험 준비 | `hermes-sync-test.sh` 가 bare 원격 하나를 공유하는 두 클론을 만들고 `age` 가 필요(열쇠는 임시 HOME) |

## 3. 비목표 (Out of Scope)

- 기계 판정(clean·pending)·문장 원문·`privacy_gold`(정답지)를 나르지 않는다.
- 받은 지움으로 이미 있는 기억 이벤트를 철회(`memory.retracted`)하지 않는다 — 조각에 기억 id 가 없다. 지움은 앞으로의 내보내기를 막는 효과만 낸다.
- 요약 조각을 받은 컴퓨터가 그 문장들을 자동으로 `clean` 으로 표시해 재판정 비용을 줄이는 일은 이번에 하지 않는다(§7).
- 원문 보관소는 만들지 않는다(사용자 결정).

## 4. 영향 영역

- 코드(수정): `scripts/hermes_sync_learning.py`(결정 조각을 함께 내고 함께 받는다 — 위임만) · `scripts/hermes-sync.py`(받기 접두어에 `decision/`) · `presets/workflow/hermes.conf` · `.deprc` · `tests/run-all.sh` · `docs/hermes-sync-guide.md`.
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `scripts/hermes_sync_decisions.py` — 사람 결정(keep·drop)을 운반 조각으로 만들고, 받은 조각을 판정 표에 규칙대로 넣는 것만 담당한다.
  - `tests/hermes-sync-decision-test.sh` — 목표 1~4 의 합성 자료 시험(두 클론 · bare 원격, 공장 DB 무변경 확인 포함).
- 룰: R3(모델 호출 없음) · R-cx(함수당 복잡도 11 이하) · R-declare.
- 데이터: 원격 참조 `refs/hermes/sync` 에 `decision/…` 조각이 추가된다(해시·상태·시각). 판정 표 구조는 그대로.
- 외부 의존: `age`(기존 운반 시험이 이미 요구).
- 되돌리기: 코드는 git. 이미 올라간 결정 조각은 참조에서 지울 수 없지만 원문이 없어 내용이 해시뿐이다.

## 5. 단계 (Steps)

### Step 1. 시험 먼저 [Impl]
- `tests/hermes-sync-decision-test.sh` §1~§4 를 쓰고 실패(RED)를 확인한다. §1·§2 는 모듈 함수를 직접 부르고, §3 은 `hermes-sync.py` push·pull 로 두 클론을 잇는다.

### Step 2. 결정 모듈 + 배선 [Impl]
- `hermes_sync_decisions.py`: `outgoing_decisions(con, done)` · `import_decision(con, body)`. 받기 규칙은 하나의 UPSERT 로 쓴다:
  `INSERT (kind='decision') … ON CONFLICT(hash) DO UPDATE SET status=excluded.status, text='', ts=excluded.ts WHERE privacy_review.status NOT IN ('keep','drop') OR privacy_review.ts < excluded.ts OR (privacy_review.ts = excluded.ts AND excluded.status='drop')`. 받기 분기는 `import_learning` 의 접두어 갈래와 `hermes-sync.py` `_import_all` 의 접두어 목록 두 곳에 `decision/` 를 더한다.
- `hermes_sync_learning` 의 `outgoing_learning`·`import_learning` 이 위임하고, `hermes-sync.py` 의 받기 접두어에 `decision/` 를 더한다.
- 검증: 시험 §1~§4, 기존 `hermes-sync-test.sh`·`hermes-repo-sync-test.sh`.

### Step 3. 등록 · 문서 · 전체 시험 · 회고 [Review]
- 복사 목록·계약·시험 등록, 안내서, `sync-doc-counts`, 전체 시험 **한 번**, 회고. 전파는 사용자 지시 뒤.

## 6. 의사결정 로그

- 2026-09-29: 기계 판정은 나르지 않고 **사람의 결정만** 나른다 — 근거: 기계 판정은 마스킹·판정 규칙 버전에 따라 달라져(이번에 규칙이 바뀌며 해시가 달라졌다) 다른 컴퓨터에서 틀릴 수 있고, 사람의 결정은 의도라 규칙이 바뀌어도 유효하다. 손해: 새 컴퓨터는 통과 문장을 모델로 한 번 더 판정한다(비용).
- 2026-09-29: 사람 결정끼리 충돌하면 **더 새로운 결정 시각이 이기고, 같은 시각이면 지움이 이긴다** — 근거: 마음을 바꾼 최신 의도가 맞고(리뷰 검토에서 "받은 쪽 유지"는 두 컴퓨터가 영영 다르게 남는다고 지적돼 바꿨다), 동률은 안전한 쪽으로 수렴시킨다. 손해: 컴퓨터 시계가 앞선 곳의 keep 이 나중의 drop 을 이길 수 있다(백로그 `dream-watermark-clock-skew` 와 같은 부류). 기각한 대안 — "지움은 시각과 무관하게 항상 이긴다": 더 안전하지만 한 번 지운 문장을 다시 둠으로 바꾸는 결정이 영원히 전파되지 않는다.
- 2026-09-29: 받은 결정은 판정 표에 **원문 없이** 넣는다 — 근거: 표는 대기 문장만 원문을 갖는 규칙(같은 계획 B 단계)이 있고, 조각에도 원문이 없다.
- 2026-09-29: 잠금 모드에서도 결정 조각은 평문이다 — 근거: 내용이 해시·상태·시각뿐이라 암호화할 자유 글이 없다. 손해: 공개 원격(`PUBLIC`)에서는 "이 해시의 문장을 사용자가 지움/둠으로 정했다"가 보인다. 해시는 128비트 절단이라 원문을 되돌릴 수 없지만, 후보 문장을 넣어 보면 일치 여부는 확인된다(짧고 흔한 문장일수록 쉽다).

## 7. 발견·예외

- 요약 조각을 받은 컴퓨터는 그 문장들을 미판정으로 보고 모델로 다시 판정한다(송신자가 이미 통과시킨 문장인데). 받은 요약 문장을 `clean` 으로 표시하면 비용이 줄지만 원격 쓰기 권한자가 문장을 심는 경로가 늘어 이번에 다루지 않는다 — 후속 후보.
- 접두어를 모르는 옛 판 컴퓨터는 `decision/` 조각을 오류 없이 건너뛰지만 받은 것으로 표시하지 않아 "안 받은 조각"에 남고, 그 컴퓨터에서는 지움이 효과가 없다(안내서에 적음). 전파로 판을 맞추면 해소된다. 잘못된 조각이 매 pull 마다 "안 받은 조각"에 남는 것은 기존 요약·패턴과 같은 동작이라 이번에 고치지 않는다.
- 롤백: 결정 조각을 받지 않게 하는 스위치는 두지 않는다. 올리기는 기존 `push` 정책(`push: false`)으로 끌 수 있고, 잘못 들어온 결정은 `hermes-privacy-review.py decide` 로 다시 정하면 더 새로운 시각으로 전파된다.
- 지움을 받아도 그 문장이 이미 로컬 기억 이벤트에 있으면 그 이벤트는 그대로다(비목표).

## 8. 회고 (완료 시 작성)

- 잘된 것: 시험을 먼저 써서 실패 19건을 확인한 뒤 구현했다(최종 31건 통과). 계획 검토가 구현 전에 짚은 것 — 같은 초에 두 컴퓨터가 다른 결정을 내리면 수렴하지 않는다, 시각 형식을 검사하지 않으면 글자 비교가 틀어진다, 새 행의 `kind` 는 NOT NULL — 을 모두 코드와 시험에 반영했다. 동기화 관련 시험 5개(age 를 쓰는 것 포함)와 계약 검사가 통과했다.
- 잘못된 것: 계획 초안의 "같은 시각이면 받은 쪽이 유지한다"는 두 컴퓨터가 영영 다른 상태로 남는 결함이었고(지움이 둠에게 지는 컴퓨터가 생김) 리뷰가 잡았다. 초안 UPSERT 에는 `kind` 값이 빠져 있었다.
- 전체 시험은 122개 중 121개 통과, `hermes-handoff-test.sh` 하나가 병렬 실행 중 실패했으나 단독 재실행에서 55건 모두 통과했다(부하에 따른 불안정으로 추정, 원인 미확인 — 이번 변경과 무관한 파일이라 백로그 후보로만 남긴다).
- 다음 룰 후보: (1) 두 컴퓨터가 함께 쓰는 조각은 경로에 충돌을 가르는 값(상태)을 넣는다. (2) 동률 규칙은 안전한 쪽(지움)으로 수렴시킨다. (3) 받은 요약 문장을 `clean` 으로 표시해 재판정 비용을 줄이는 일(§7)은 별도 계획으로.
- 전파: 사용자 지시 뒤. 소우주가 결정 조각을 올리려면 그 소우주의 `sync.json` 이 `push: true` 여야 한다(terminal-shipping 의 4건이 첫 대상).

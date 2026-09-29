# 2026-09-29-privacy-gate-hardening — 올리기 전 판정을 믿을 수 있게 (다시 가리기 · 커밋 때 묻기 · 스킬 쓰기 경로)

> 출처: 2026-09-29 DB 쓰임새 논의(올리기 전 판정). 원 기능: `completed/2026-09-28-carry-agent-knowledge.md`(목표 2·3·8).
> 측정일: 2026-09-29, 공장·`zeroday-frontend`·`terminal-shipping` 의 `.hermes/state.db` 와 지식 파일.
> 순서: 사용자 결정으로 **B → A → C**. 단계마다 시험 먼저, 단계 끝에 개별 커밋.

## 1. 동기 (Why)

올리기 전 판정(`privacy_review`)은 문장마다 "개인적·업무 무관인가"를 한 번 물어 clean/pending 을 적고, 커밋 게이트 R-privacy 는 그 표만 읽는다. 세 가지가 어긋나 있다.

1. **가려지지 않은 비밀이 통과했다.** 지금 마스킹 규칙(`hermes_redact.redact`)으로 저장된 문장을 다시 가리면 달라지는 것이 공장 5 · zeroday 45 · terminal-shipping 3 문장이다(전체 8,572문장). zeroday 는 그중 13문장이 비밀값 유형이고 6개가 추적 중인 스킬 파일에 있다. 원인 둘: (가) 스킬을 굳혀 파일로 쓰는 `hermes-crystallize.py`(419행)·`hermes-evolve-skill.py`(236행)는 마스킹 없이 쓴다, (나) 기억·이력·대화 요약 내보내기 모듈은 저장 시점에 가린 문장을 그대로 쓰고, 규칙이 나중에 강화돼도 다시 가리지 않는다.
2. **통과한 문장의 원문이 표에 남는다.** `privacy_review.text` 에 판정한 문장 8,500여 개가 원문으로 있고, 읽는 곳은 사람에게 대기 문장을 보일 때(`pending_rows`) 하나뿐이다. 나머지는 필요 없는 저장이다.
3. **사람이 처리해야 하는 것이 사람 눈에 안 들어온다.** 대기 문장 13건(zeroday 12·terminal-shipping 1)과 사용자 성향 승인 대기 2건이 명령을 기억해서 돌려야만 처리된다. 사용자는 "처음 들어"라고 했다. 판정이 얼마나 맞는지 잴 정답지도 없다(놓친 개인 문장 수를 알 수 없음).

> 여기까지 다시 읽었다: 고칠 대상은 (B) 내보내기 직전·저장 직전의 마스킹과 그 재검사, (A) 커밋 때 사람에게 묻는 통로와 정답지, (C) 스킬 쓰기 경로다. 프로젝트 소스에 박힌 비밀(zeroday `LoginPage.vue` 등)은 그 팀 소관이라 건드리지 않는다.

## 2. 목표 (What — 검증 가능한 형태)

**B 단계**
- [x] 목표 1 — **파일로 나가는 기억·이력·대화 요약 문장은 지금 규칙으로 가린 것이다.** 판정(`judge_items`)과 쓰기(`export`)가 **같은** `redact(문장, project)` 값을 쓰므로 해시가 일치해 게이트가 통과한다(세 모듈이 같은 project 를 받는다는 것까지 시험). 가려서 달라진 문장은 다시 판정되고, 그 판정이 끝나기 전 첫 내보내기에서는 파일에서 잠시 빠진다. 가려도 원문과 같은 문장(요약 저장 시 이미 가려진 대부분 — `hermes-summarize.py` 는 변경 없음)은 해시가 그대로다. 검증: `bash tests/hermes-privacy-scrub-test.sh` §1.
- [x] 목표 2 — **R-privacy 는 지금 규칙으로 다시 가리면 달라지는 스테이징 문장을 막고 고치는 명령을 알려 준다.** 검사 범위는 기존과 같다: jsonl 은 이번에 더해진 줄만, 스킬·대화 요약은 스테이징된 본문 전체. 게이트는 `redact(문장, 저장소 루트)` 로 내보내기와 같은 project 를 쓴다. 필요한 모듈(`hermes_redact`·`hermes_privacy_staged`)이 없으면(구버전 스크립트) 종료 코드 3 으로 알리고 pre-commit 이 "재설치 필요"를 출력하며 `skipped` 로 기록한다(조용한 통과 금지). 검증: 같은 시험 §2(비밀형 문장 → 차단·안내 · 가린 줄 → 통과 · **비밀형이 아닌 정상 문장 → 통과** · 모듈 없음 → 종료 3).
- [x] 목표 3 — **판정 표는 대기(pending) 문장만 원문을 가진다.** clean 은 기록 시, keep·drop 은 결정 시 `text` 를 비운다. pending 이 나중에 clean 으로 재판정되면 옛 원문도 비운다(`ON CONFLICT` 가 text 를 함께 갱신). `allowed`·`status_of` 는 해시만 쓰므로 동작이 같다. 비우기는 되돌릴 수 없다(복구 = 백업 파일). 검증: 같은 시험 §3.
- [x] 목표 4 — **옛 것을 정리하는 명령을 둔다(적용은 사람이 정한다).** `hermes-privacy-scrub.py db` 는 판정 표의 비대기 `text` 를 비우고, `files` 는 지식 파일을 다시 가린다. 둘 다 미리보기가 기본이고 `--apply` 일 때만 바꾸며, `db` 는 적용 직전 DB 를 백업한다. `files` 는 JSON(줄) 파일은 문자열 값 단위로 가려 JSON 유효성을 유지하고, 마크다운은 게이트가 검사하는 단위(본문 통째)와 같게 가린다. 추적 중이고 변경 없는 파일은 git 이 백업이고, 그 밖의 파일은 `.hermes/.scrub-backup/<시각>/` 에 원본을 복사한 뒤 쓴다. 적용 뒤 다시 가려 보아 또 달라지는 파일(마스킹이 멱등이 아님)은 실패로 보고한다 — 게이트가 영원히 못 푸는 차단을 만들지 않기 위해서다. 검증: 같은 시험 §4(미리보기 무변경 · db 적용 뒤 원문 0 · files 적용 뒤 JSON 파싱 성공·재실행 멱등·백업 존재).

**A 단계**
- [x] 목표 5 — **커밋 직전에 대기 항목을 사람에게 묻게 한다.** 커밋 안내 훅이 사람 확인 대기 문장·성향 승인 대기·정답지 표본을 세어, 있으면 "질문 폼으로 한 번에 물어라"는 안내와 항목 목록(`hermes-ask.py list`)을 맨 위에 넣는다. 세션당 한 번(안내를 낼 때 표시 — 무시되거나 미뤄진 항목은 다음 세션에 다시 나온다), 한 폼 최대 4개, 정답지 표본이 목표에 못 미친 동안은 1칸을 표본용으로 예약, 대기 0건이면 아무것도 넣지 않는다. 세션 ID 는 훅 입력 JSON 을 파이썬으로 읽는다(줄 단위 자르기 금지 — 2f0c623 결함과 같은 부류). 검증: `bash tests/hermes-ask-test.sh` §1(개수 상한·우선순위·예약·세션당 1회·0건 침묵) · §4(훅 출력에 안내가 실린다 · 두 벌 `diff` 동일).
- [x] 목표 6 — **답이 즉시 기록된다.** `hermes-ask.py answer <항목> <선택>` 이 문장은 `keep|drop`, 성향은 `approve|reject`, 정답지 표본은 `ok|leak` 로 기록한다. `later` 는 기록하지 않는다. 표본이 `leak` 이면 그 문장을 `drop` 으로 바꿔 게이트가 막고 어느 파일에 있는지 알려 준다. 한 명령은 항목 하나만 다루며 `leak` 의 두 기록(정답지 + drop)은 한 트랜잭션이다. `answer` 는 모델도 부를 수 있어 사람 응답인지 기술적으로 검증하지 못한다 — 방어는 안내 문구(폼에서 고른 값만 기록)와 기록에 남는 시각뿐이다(§6). 검증: 같은 시험 §2.
- [x] 목표 7 — **정답지를 채우고 결과를 보고한다.** 커밋마다 스테이징된 통과 문장에서 최대 3개를 무작위로 골라 묻고(`privacy_gold` 표), `hermes-ask.py report` 가 표본 수·놓침 수·응답하지 않은 항목 수(표본 수에 넣지 않음)·대기 문장의 사람 판정 비율(둠=과탐)·놓침 0건일 때 95% 상한(3/n)을 낸다. 같은 문장은 해시로 한 번만 센다. 정답지 표에는 **해시와 판정만** 저장하고 원문은 저장하지 않는다. 표본이 100개에 이르면 더 묻지 않고 `report` 를 보여 준다. 판정 규칙: 놓침이 1건 이상이면 판정 문구(`RULE`) 개선 계획을 세운다. 상한은 "스테이징된 문장 중 응답한 표본"에 한한 값이고 모집단 전체의 보증이 아니다. 검증: 같은 시험 §3(계산값 대조 · 중복 표본 1회 · later 제외).

**C 단계**
- [ ] 목표 8 — **스킬 파일을 쓰는 경로는 모두 마스킹을 거친다.** 결정화·진화가 `hermes_skill_write.write_skill_file` 로만 스킬 파일을 쓰고, 그 함수가 가린 뒤 원자적으로 쓴다. 검증: `bash tests/hermes-skill-write-test.sh`(가림 · 두 스크립트가 직접 `open(…, "w")` 로 스킬을 쓰지 않음 · 원자적 쓰기).
- [ ] 목표 9 — **등록·문서·전체 시험.** 새 스크립트·시험을 복사 목록·계약·시험 목록에 넣는다. 합격 기준: `grep -c` 로 `hermes.conf`·`.deprc`·`tests/run-all.sh` 등록 확인, 새·바뀐 스크립트 복잡도 검사 0, `bash tests/run-all.sh` 를 마지막에 한 번(실패 목록에 이 계획이 건드린 시험 없음).

## 2-bis. 착수 전 확인한 사실 (2026-09-29)

| 확인한 것 | 결과 |
| --------- | ---- |
| 다시 가리기의 멱등성 | 저장 문장 8,572개 전부 `redact(redact(x)) == redact(x)` (위반 0) → 해시가 안정적이다 |
| 지식 파일 중 다시 가리면 달라지는 것 | 공장 1/47 · zeroday 18/1,106 · terminal-shipping 12/235 파일 |
| `privacy_review.text` 를 읽는 곳 | `pending_rows`(hermes_privacy_pending.py) 하나 |
| 스킬 쓰기 경로 | crystallize 419행 · evolve-skill 236행 — `redact` 호출 없음. dream 리포트는 패턴 낱말만 담아 이번 범위 밖 |
| 게이트 파일 | `assets/hooks/check-privacy.py` 101줄. 문장 추출 함수(`_texts` 계열)를 A 단계에서 공용 모듈로 옮긴다 |
| 커밋 안내 훅 | `assets/hooks/claude-pretooluse-bash-guard.sh`(134줄) — `git commit` 감지 시 additionalContext 를 낸다(리뷰 빚 유무로 두 갈래) |
| 성향 승인 대기 | `~/.hermes/global.db` 의 관찰 표, 조회는 `hermes_persona_commands._view` |
| 게이트 종료 코드 처리 | `pre-commit.sh` 6a: 1=차단, 2=`skipped`("판정 표 없음", **화면에는 안 나오고 기록만 남는다**), 0=통과 → 구버전 스크립트용 3 을 더하고 경고를 출력한다 |
| `hermes-summarize.py` | 모델 입력을 `redact`(110행) 한 뒤 요약하고 슬롯을 `mark` 한다 → 이 경로의 문장은 이미 가려져 있어 변경 없음 |
| 질문 폼 한도 | 한 번에 질문 4개(도구 제약) |
| 사용자 이전 지적 | 폼을 연달아 띄우면 "의미 없는 질문" → 세션당 한 번·한 폼에 묶음(기억 `feedback-no-template-forms`) |

## 3. 비목표 (Out of Scope)

- 프로젝트 소스·시험 코드에 박힌 비밀(zeroday `LoginPage.vue`·e2e 시험 등)은 건드리지 않는다. 사용자에게 보고만 했다.
- `.hermes/history/`(옛 대화 원문 파일)·dream 리포트의 마스킹은 이번 범위 밖.
- 이름 마스킹이 식별자 속 이름까지 가리는 문제(`jjackkun_bot` → `[REDACTED]_bot`)는 별도 백로그(`backlog/redact-name-in-identifier.md`).
- 소우주의 옛 파일·DB 정리 적용(`--apply`)과 커밋은 사람이 정한다(zeroday 는 특히 사용자 몫).
- 정답지 표본의 층화(경계선 근처 과표집)는 하지 않는다 — 판정 점수가 없어 경계를 알 수 없다. 대신 한계를 보고에 적는다.
- 판정 모델·프롬프트(`RULE`) 변경 없음. 정답지가 쌓인 뒤 다시 본다.

## 4. 영향 영역

- 코드(수정): `assets/hooks/pre-commit.sh`(6a: 종료 코드 3 처리, 약 4줄) · `scripts/hermes_privacy_pending.py`(mark·decide 가 text 비움) · `scripts/hermes_memory_file.py`·`hermes_journal_file.py`·`hermes_conversation_file.py`(가린 문장으로 판정·쓰기) · `scripts/hermes-knowledge-files.py`(project 를 넘김) · `assets/hooks/check-privacy.py`(재검사 + 공용 모듈 사용) · `assets/hooks/claude-pretooluse-bash-guard.sh` 와 공장 자기 설치본 `scripts/hooks/` **두 벌을 같게** · `scripts/hermes-crystallize.py`·`hermes-evolve-skill.py`(쓰기를 공용 함수로) · `presets/workflow/hermes.conf` · `.deprc` · `tests/run-all.sh`.
- 의존 방향(누가 누구를 부르는가): `hermes_redact`·`hermes_privacy_pending` 이 바닥. 내보내기 모듈 3개와 `check-privacy.py` 는 둘을 쓴다. `hermes_privacy_staged` ← `check-privacy.py`(게이트)·`hermes_ask_items`. `hermes_ask_items` ← `hermes-ask.py`. **두 DB(프로젝트 `state.db`·전역 `global.db`)를 가로지르는 곳은 `hermes_ask_items` 한 곳**이고, 성향 대기는 `persona_pending()` 함수 하나로만 읽는다(반환: `[(라벨, 문장)]`).
- `hermes-ask.py list` 출력 계약: 첫 줄 `[ASK] <N>`, 이어서 항목마다 한 줄 `<ID>\t<종류>\t<문장>`(ID 는 `p:<해시8>` 문장 대기 · `s:<라벨>` 성향 · `g:<해시8>` 표본), 마지막에 사용법 안내. 시험용 `--json` 도 둔다. `privacy_gold(hash PK, verdict, source, ts)`·`ask_marker(session_id PK, asked_at, n_items)` — 원문 열 없음.
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `scripts/hermes-privacy-scrub.py` — 옛 판정 표·지식 파일을 정리하는 명령(`db`·`files` 두 하위 명령, 미리보기 기본).
  - `scripts/hermes_privacy_scrub_files.py` — 지식 파일을 다시 가리는 논리(JSON 은 문자열 값 단위, 마크다운은 통째).
  - `scripts/hermes_privacy_staged.py` — 스테이징된 지식 파일에서 판정 대상 문장을 뽑는다(게이트와 묻기가 공유).
  - `scripts/hermes_privacy_gold.py` — 정답지 표(`privacy_gold`)와 통계(표본 수·놓침·95% 상한).
  - `scripts/hermes_ask_items.py` — 커밋 때 물을 항목(문장 대기·성향 대기·정답지 표본)을 모은다.
  - `scripts/hermes-ask.py` — `list`·`answer`·`report` 명령줄.
  - `scripts/hermes_skill_write.py` — 스킬 파일을 가린 뒤 원자적으로 쓴다.
  - `tests/hermes-privacy-scrub-test.sh` · `tests/hermes-ask-test.sh` · `tests/hermes-skill-write-test.sh` — 위 목표의 합성 자료 시험(임시 프로젝트, 공장 DB 무변경 확인 포함).
- 룰: R3(모델 호출 없음 — 새 코드는 모두 모델을 부르지 않는다) · R-cx(함수당 복잡도 11 이하) · R-size · R-declare.
- 데이터: `privacy_review.text` 비움(`db --apply`) · 새 표 `privacy_gold`·`ask_marker`(필요할 때 생성). 표 구조 변경 없음.
- 외부 의존: 없음. 되돌리기: 코드는 git, DB 정리는 백업 파일, 파일 정리는 git.

## 5. 단계 (Steps)

### Step B1. 시험 먼저 → 판정 표 text 비우기 + 내보내기 마스킹 [Impl]
- `tests/hermes-privacy-scrub-test.sh` §1·§3 을 쓰고 실패(RED)를 확인한다. 상수: 없음.
- `mark`: 상태가 pending 이면 text 저장, 아니면 빈 문자열(`ON CONFLICT` 에서도 같음). `decide`: 결정 뒤 text 비움.
- 세 내보내기 모듈: 문장을 `redact(text, project)` 한 값으로 판정·비교·쓰기를 한다. `judge_items`·`export` 에 `project` 인자를 더하고 호출처(`hermes-knowledge-files.py` 하나)를 함께 고친다. 스킬·패턴 항목(`skill_items`·`pattern_items`)의 판정 입력은 기존 그대로(스킬은 C 단계).
- 검증: 시험 §1·§3, 기존 `hermes-carry-knowledge-test.sh`·`hermes-privacy-review-test.sh`.

### Step B2. 게이트 재검사 + 정리 명령 [Impl]
- `check-privacy.py`: 판정 통과 여부와 별도로 `redact(문장) != 문장` 이면 차단 목록에 넣고 `python3 scripts/hermes-privacy-scrub.py files --apply` 를 안내한다. `hermes_redact` 가 없으면 이 재검사만 건너뛰고 이유를 출력한다(조용한 통과 금지).
- `hermes-privacy-scrub.py db|files` 와 `hermes_privacy_scrub_files.py`. 시험 §2·§4.
- 검증: 시험 §2·§4, 복잡도 검사. **B 단계 커밋.**

### Step A1. 문장 추출 공용화 + 정답지 · 항목 모으기 [Impl]
- `check-privacy.py` 의 추출 함수를 `hermes_privacy_staged.py` 로 옮기고 게이트가 그것을 쓴다(동작 동일 — 기존 시험이 증명). 게이트의 "판정 표 없음" 건너뜀 조건에 새 모듈 존재를 더한다.
- `hermes_privacy_gold.py`, `hermes_ask_items.py`, `hermes-ask.py`. 상수: 폼 한도 4(도구 제약) · 커밋당 표본 3 · 표본 목표 100(놓침 0건일 때 95% 상한 3/n = 3% — 규칙 세 배 법칙).
- 우선순위: 사람 확인 대기 문장(오래된 순) → 성향 승인 대기 → 정답지 표본. 합이 4 를 넘으면 뒤에서 자른다. `ask_marker` 로 세션당 한 번.
- 검증: 시험 §1~§3.

### Step A2. 커밋 안내 훅 배선 [Impl/Review]
- `claude-pretooluse-bash-guard.sh` 의 `git commit` 갈래(리뷰 빚 유무 두 곳)에서 `hermes-ask.py list --session <id>` 를 부르고, 출력이 있으면 additionalContext 맨 위에 붙인다. 스크립트가 없으면 조용히 건너뛴다(비차단 훅). 두 벌 동일.
- 검증: 시험 §4, `diff` 두 벌 동일. 공장 재설치. **A 단계 커밋.**

### Step C1. 스킬 쓰기 경로 [Impl]
- `hermes_skill_write.py` + 두 스크립트가 그것을 쓴다. 시험 먼저.
- 검증: `bash tests/hermes-skill-write-test.sh`, 기존 결정화·진화 시험. **C 단계 커밋.**

### Step 마무리. 등록 · 전체 시험 · 전파 · 회고 [Review]
- 복사 목록·계약·시험 등록, `sync-doc-counts`, 백로그 `redact-name-in-identifier.md` 작성, 전체 시험 **한 번**, 공장 재설치 뒤 `.git/hooks/check-privacy.py`·`pre-commit` 이 새 원본과 같은지 `diff`, 회고.
- **전파 순서(게이트 차단 전환의 완충):** 소우주에 `update-all` 을 하기 **전에** 소우주마다 `hermes-privacy-scrub.py files` 미리보기로 대상 수를 확인하고, 설치 직후 `files --apply` → `hermes-knowledge-files.py export`(재판정) → 커밋 순으로 한다. 순서를 어기면 그 소우주의 다음 커밋이 게이트에 막힌다(안내 문구에 명령이 있다). 적용은 사용자 지시 뒤, zeroday 는 사용자 몫.
- 끝에서 끝까지 실제 확인(회고 §8 **필수 항목**): 대기 문장이 있는 상태에서 커밋을 시도해 안내가 제 화면에 들어가고 폼이 뜨는지, 답이 기록되는지.

## 6. 의사결정 로그

- 2026-09-29: 다시 가리기는 **쓰기 직전에 가린 문장으로 판정·쓰기를 모두 한다** — 근거: 판정 해시와 파일 내용이 같아야 게이트가 통과한다(쓰기만 가리면 해시 불일치로 영원히 막힘). 손해: 가려서 달라진 문장이 한 번 다시 판정된다(공장 5·zeroday 45·terminal-shipping 3 문장, 모델 호출 몇 번).
- 2026-09-29: 게이트는 마스킹이 달라지는 문장을 **차단**한다(경고가 아니라) — 근거: 비밀 노출은 되돌릴 수 없고, 마스킹은 기계가 확인하므로 오탐 비용이 낮다(R-doc 과 같은 원칙). 손해: 옛 지식 파일을 고쳐 커밋하려면 먼저 `files --apply` 가 필요하다 — 안내 문구에 명령이 있다.
- 2026-09-29: 질문은 커밋 직전 훅이 **안내를 넣고 내가 폼으로 묻는다** — 근거: 훅은 사용자와 직접 대화할 수 없고 사용자와 이어진 통로는 나뿐이다. 손해: 내가 안내를 따르는 데 의존한다 → 끝에서 끝까지 실제 커밋으로 확인한다.
- 2026-09-29: 기각한 대안 — (게이트) 마스킹 차이를 차단이 아니라 경고로: 비밀 노출은 되돌릴 수 없어 기각. (판정 표) 원문 대신 해시만 저장하도록 표 재설계: 대기 문장을 사람에게 보이려면 원문이 필요해 대기 행만 원문을 두는 쪽이 작다. (묻기) 세션 시작 알림: 오늘 이미 실패했다(성향 승인 대기는 알림이 있었지만 사용자가 몰랐다).
- 2026-09-29: 게이트가 필요한 모듈을 못 찾으면 통과시키지 않고 종료 3 으로 구분해 경고·기록한다 — 근거: 종료 2 의 "판정 표 없음"은 화면에 안 나온다. 손해: 구버전 스크립트 프로젝트는 재설치 전까지 이 검사를 못 받는다(기존 정책과 같고 이제 소리가 난다).
- 2026-09-29: `answer` 는 사람 응답인지 검증하지 못한다 — 근거: 명령을 부르는 주체가 모델이라 서명할 방법이 없다. 방어는 "폼에서 고른 값만 기록" 안내 문구와 기록 시각, 대화 기록에 남는 폼 응답이다. 손해: 모델이 사용자 대신 기록할 수 있다 → 끝에서 끝까지 확인과 `report` 로 감시한다.
- 2026-09-29: 정답지 표본은 스테이징된 통과 문장에서 뽑는다 — 근거: 통과 문장의 원문은 B 단계 이후 표에 없다(비웠으므로). 손해: 스킬 파일 통째 판정 항목(문단 단위가 아님)은 표본에서 뺀다.
- 2026-09-29: 정답지 표본 목표 100개 — 근거: 놓침 0건일 때 95% 상한이 약 3/n 이라 100개면 3% 이하. 더 낮추려면 표본이 늘어야 한다(300개 1%).
- 2026-09-29: 옛 DB·파일 정리는 미리보기가 기본, DB 는 적용 전 백업 — 근거: 이전 정리 명령들과 같은 원칙(삭제·덮어쓰기는 사람이 정한다).

## 7. 발견·예외

- zeroday 의 개발 계정 비밀번호로 보이는 값이 프로젝트 소스와 `origin/develop` 에 이미 있다(헤르메스가 만든 노출이 아님). 사용자에게 보고했고 이 계획의 범위 밖이다.
- 마스킹의 이름 규칙이 식별자 안의 사용자 이름까지 가린다(`jjackkun_bot`). 백로그로 넘긴다.
- 규칙이 다시 강화되면 같은 절차(전파 전 `files` 정리 → 재판정)가 반복된다. 규칙 변경 때마다 이 순서를 지켜야 한다는 것이 이 게이트의 운영 비용이다.
- 성향 승인 대기는 세션 시작 알림이 있었지만 사용자가 알지 못했다 — 알림만으로는 처리되지 않는다는 증거이며 A 단계의 근거다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 끝에서 끝까지 확인 결과(필수 — 폼이 실제로 떴는가 · 답이 기록됐는가):
- 다음 룰 후보:

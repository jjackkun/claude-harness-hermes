# 2026-09-15-skill-layers-delivery — 스킬 4층, 주입 필터, 확장 기준 버전, 제안 봉투와 GitHub 이슈 배달

> 헤르메스 우주 구현 계획 **5/5**. 설계 원천: `design/world/skill-layers.md`(S-01~S-10, C-12 · C-13, RV-12 · RV-13 · RV-14), `skill-proposal-delivery.md`(P-03 · P-04, RV-15 · RV-16), 결정 L-01 · L-02 · L-05 · L-06.
> 선행: 계획 1(설치 목록 · `factory.json`), 계획 2(`universe_id`), 계획 4(`agent_id` · `unit_id`).
> 관련 진행 중 계획: `2026-09-09-hermes-skill-lifecycle.md`(도움 판정 신호 G-8) — 이 계획은 그 신호를 **쓰지 않는다**(사용 횟수는 기준이 아님, S-09 폐기). 강등 판정은 G-8 이 닫힌 뒤.

## 1. 동기 (Why)

- `skill_index` 에 소우주 칸도 층 칸도 없다. 설치본은 `scope='harness'`, 결정화는 `scope='local'` 두 값뿐(`evidence/current-state-audit.md` §1).
- zeroday-frontend 결정화 스킬 **1088개**가 소유자·단위 구분 없이 한 폴더에 있고, 813개(75%)는 한 번도 주입되지 않았다. 도움 판정은 주입과 거의 같아 좋고 나쁨을 못 가른다(G-8).
- 소우주가 공통 스킬을 고치면 공장 원본이 바뀌는 뒷문은 계획 1 이 막았다. 이제 **고친 것을 올리는 길**이 없다 — `.claude/presets.lock` 에는 프리셋 이름만 있고 공장 위치가 없었다(계획 1 이 `factory.json` 을 만듦).
- `~/.hermes/global.db` `harness_rules` 에 5개 소우주 기록 1142줄이 소우주 칸 없이 섞여 쌓인다(`scripts/hermes-crystallize.py:369-387`). 읽는 코드는 없다.
- 공장 저장소는 PUBLIC(V-7). 봉투 본문이 공개 게시물이다.
- 공장의 모순 결정화 스킬 2개는 계획 1 에서 삭제된다. 남은 것은 결정화가 폐기된 결정을 규칙으로 굳히는 장치 자체(G-25, L-06 — 백로그).

## 2. 목표 (What — 검증 가능한 형태)

- [ ] 목표 1 — `skill_index` 에 `universe_id` · `layer`(`universe|common|unit|agent`) · `unit_id` · `agent_id` · `skill_id`(층을 옮겨도 불변) 칸이 있고, 기존 1088행은 `layer='common'`, `universe_id` = 현 소우주, 나머지 NULL 로 채워진다(L-01 "소우주 공통(미배정)"). 검증: `tests/hermes-skill-layers-test.sh` — 마이그레이션 후 행 수 불변, 값 분포.
- [ ] 목표 2 — 층별 저장 위치가 코드로 고정된다: 우주 `.claude/skills/<이름>/`(설치 목록에 있음), 소우주 공통 `.hermes/skills/`(기존 자리 유지 — 옮기지 않는다), 단위 `.hermes/units/<unit_id>/skills/`, 개인 `.hermes/agents/<agent_id>/skills/`. 검증: `hermes_skill_layers.py` 경로 함수 테스트 + 색인기가 네 자리를 모두 훑음.
- [ ] 목표 3 — 주입 필터(RV-12): `hermes-search.py` 가 소환된 에이전트(`HERMES_AGENT_ID`, 없으면 `main`)의 `unit` · `agent_id` 에 맞는 층만 검색한다. 검증: 테스트 — 다른 단위의 스킬이 결과에 0건.
- [ ] 목표 4 — 주입 형식 하위 호환(RV-12): `description` 머리말이 있는 스킬은 `이름 — 설명` 한 줄로, 없는 스킬은 현행 `read_skill_snippet` 10줄로 주입된다. 검증: 테스트 두 종류 픽스처 + zeroday 스킬 1088개를 픽스처로 돌려 주입 형식이 전부 스니펫임을 확인(회귀 보호).
- [ ] 목표 5 — 스킬 본문 요청 경로: 에이전트가 `hermes-skill.py read <이름>` 으로 본문을 그 턴에 끌어온다(진행적 공개). 검증: CLI 출력 = 파일 본문, `skill_injection` 에 `source='read'` 기록.
- [ ] 목표 6 — 확장 파일(RV-13): 머리말 `extends: <skill_id>@<version>` 을 가진 파일은 "위 층 본문 + 확장" 으로 주입되고, `update-all` 이 기준 버전이 달라진 확장을 찾아 `[extends WARN]` 을 낸다. 검증: 테스트 — 공장 커밋 해시 바꾼 뒤 재설치 → 경고 1건.
- [ ] 목표 7 — 승격 제안 명령 `hermes-propose.py new|improve|exclude <스킬>` 이 (a) 일반화 자체 점검(`hermes_mesh_gate.py`) (b) 금지 내용 게이트(기억 · 원문 · 티켓 번호 · 파일 경로 · 사람이 읽는 이름) (c) `.hermes/outbox/<envelope_id>/` 봉투 작성 (d) **사람이 `--deliver` 를 붙였을 때만** `gh issue create --label proposal` 로 배달(RV-15) 을 한다. 검증: `tests/hermes-propose-test.sh` — 금지 내용 4종 각각 거부, `--deliver` 없이는 `gh` 호출 0(모의 gh 로 검증), 오프라인 실패 시 `status=pending`.
- [ ] 목표 8 — 봉투에는 `universe_id` · `agent_id` · `skill_id` · `base` · 본문 · 차이 · 이유 · 게이트 결과만 있고 소우주 이름·에이전트 이름·팀 이름이 없다. 검증: 봉투 JSON 에 명부의 `name` 값과 저장소 basename 이 문자열로 나타나지 않음(테스트가 grep).
- [ ] 목표 9 — 배달 목적지 보호(RV-16): `hermes-propose.py` 는 주소 인자를 받지 않고 `factory.json.remote_url` 만 쓰며, `factory.json` 은 설치 목록(계획 1)에 포함돼 변조 경고 대상이다. 검증: `--remote` 인자 → 오류, 파일 변조 → 계획 1 훅 경고.
- [ ] 목표 10 — 세션 시작 훅이 `outbox` 의 `delivered` 봉투 이슈 상태를 읽어(`gh issue view`) 허가면 "소우주 확장분 제거 안내", 거절이면 "확장으로 계속" 을 한 줄 알린다. `pending` 이 있으면 "배달 못 한 봉투 N개". 검증: 모의 gh 로 3상태.
- [ ] 목표 11 — `~/.hermes/global.db` `harness_rules` 쓰기 중단(L-05): `record_global_summary` 호출 제거. 기존 1142행은 그대로. 검증: 결정화 실행 후 `global.db` 행 수 불변(테스트).
- [ ] 목표 12 — 우주 판단 보조: `hermes_mesh_gate.py` 를 "허가자 1차 검사" CLI 로 노출하고 "사례 나열" 판정(RV-14)을 항목으로 추가 — **승격 심사에만**, 기존 스킬 삭제·재분류에 쓰지 않는다. 검증: 사례 나열 픽스처(`if convo has 1,2,3 …` 류 3줄 이상)가 `scenario-list` 로 표시, zeroday 1088개는 어떤 처리도 받지 않음(테스트가 파일 수·내용 불변 확인).
- [ ] 목표 13 — 폐기된 배달 경로 정리: `hermes-message.py` 와 `messages` 테이블은 제거하지 않고 **"폐기 예정"** 경고만 낸다(읽는 곳 확인 뒤 다음 계획에서 제거). 검증: 호출 시 경고 1줄.
- [ ] 목표 14 — 단위 층 스킬이 git 을 탄다(자체 리뷰 발견): `.gitignore` 마커에 `!.hermes/units/**/skills/**` 예외. `outbox/` 는 무시 그대로(봉투는 배달로 나간다). 검증: `git check-ignore` 테스트.

## 3. 비목표 (Out of Scope)

- 강등·제외 신고의 **자동 판정** — G-8(도움 신호) 이 닫힌 뒤. 이번에는 `exclude` 봉투 형식만.
- 우주 쪽 심사 자동화(공장에서 이슈를 읽어 PR 로 만드는 것) — 사람이 한다(S-06).
- 에이전트 복제 봉투(`kind: template`, G-23) — 봉투 `kind` 에 값만 예약.
- 기존 1088개 스킬의 이름 정리·소유자 배정 — L-01 확정: 하지 않는다.
- 결정화가 폐기 결정을 굳히지 않게 하는 장치(G-25, L-06) — 백로그 `docs/exec-plans/backlog/crystallize-reversed-decision-guard.md` 로 남긴다(이 계획에서 파일만 만든다).
- GitHub MCP 서버 인증 문제 — `gh` CLI 만 쓴다.

## 4. 영향 영역

- 코드(수정): `scripts/hermes-init.py`(skill_index 칸 추가 마이그레이션), `scripts/hermes-index-skills.py`(네 자리 색인 + 층 값), `scripts/hermes-search.py`(필터 + 주입 형식 분기), `scripts/hermes-crystallize.py`(`record_global_summary` 제거, 저장 층 `common`), `scripts/hermes_mesh_gate.py`(CLI + 사례 나열 항목), `scripts/hermes-message.py`(폐기 예정 경고), `lib/installers.sh` 또는 `lib/factory_manifest.sh`(확장 기준 버전 검사), `presets/workflow/hermes.conf`(복사 목록 · 훅), `assets/skills/claude-harness-hermes-install/SKILL.md`(제안 흐름 안내), `docs/hermes-universe/design/world/*.md`(확정 표시).
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `scripts/hermes_skill_layers.py` — 층 값·저장 경로·소유(`unit_id` · `agent_id`)·`skill_id` 규칙과 `skill_index` 마이그레이션만.
  - `scripts/hermes_skill_extends.py` — `extends:` 머리말 파싱과 기준 버전 대조(설치기와 검색기가 공유).
  - `scripts/hermes-skill.py` — CLI(`read <이름>` · `layers` · `where <이름>`) — 진행적 공개의 본문 읽기 진입점.
  - `scripts/hermes_envelope.py` — 봉투 스키마·`envelope_id`·`outbox` 읽기/쓰기·상태 전이(`pending → delivered → approved|rejected`)만.
  - `scripts/hermes_envelope_gate.py` — 봉투 금지 내용 게이트(기억 · 원문 · 티켓 · 경로 · 사람이 읽는 이름)만. 명부·저장소 이름을 읽어 대조한다.
  - `scripts/hermes-propose.py` — CLI(`new|improve|exclude`, `--deliver`, `status`) — 일반화 점검 → 봉투 → (사람 명령 시) `gh` 배달. 주소 인자 없음.
  - `assets/hooks/claude-sessionstart-outbox-status.sh` — 배달 결과 조회와 `pending` 알림.
  - `docs/exec-plans/backlog/crystallize-reversed-decision-guard.md` — G-25/L-06 백로그 항목(동기와 관측 사례만).
  - `tests/hermes-skill-layers-test.sh` · `tests/hermes-propose-test.sh` — 위 목표별 검증(모의 `gh` 포함).
- 게이트 대비: `hermes-search.py` 는 이미 분기가 많다(`_select_injections` 등). 필터·형식 분기를 `hermes_skill_layers.py` 의 순수 함수로 빼서 `hermes-search.py` 본문 증가를 최소화하고 R-cx(12)를 넘기지 않는다. 각 신규 모듈 공개 심볼 7개 이하.
- 룰: R 룰 후보 "소우주 밖으로 나가는 봉투에 사람이 읽는 이름을 넣지 않는다"(P-04 · RV-15). 강제: `hermes_envelope_gate.py` + 테스트.
- 데이터: `skill_index` 칸 5개 추가(`ALTER TABLE … ADD COLUMN`, 기존 행 기본값 채움). `global.db` 는 쓰기만 중단, 스키마 불변.
- 외부 의존: `gh` CLI(이미 이 환경에 있음 — V-7 확인에 사용). 배달 시에만 필요, 없으면 `pending`.

## 5. 단계 (Steps)

### Step 1. skill_index 마이그레이션 + 층 규칙 [Plan/Impl/Review]

- 산출: `hermes_skill_layers.py`, `hermes-init.py` 마이그레이션, 색인기 네 자리.
- 검증: 목표 1·2. zeroday `state.db` 사본으로 마이그레이션 리허설(행 수 1088 불변).
- Review 승격 사유: 데이터 마이그레이션(기존 12곳 DB).

### Step 2. 주입 필터·형식·본문 읽기 [Impl]

- 산출: `hermes-search.py` 수정, `hermes-skill.py`.
- 검증: 목표 3·4·5. zeroday 1088개 픽스처 회귀.

### Step 3. 확장 기준 버전 [Impl]

- 산출: `hermes_skill_extends.py`, 설치기 검사, 검색기 합성.
- 검증: 목표 6.

### Step 4. 봉투·제안·배달·상태 조회 [Plan/Impl/Review]

- 산출: `hermes_envelope.py`, `hermes-propose.py`, outbox 훅, `hermes_mesh_gate.py` CLI.
- 검증: 목표 7·8·9·10·12. 모의 `gh` 로 네트워크 없이.
- Review 승격 사유: 작업 공간 밖 부작용(공개 저장소 이슈 생성) — 사람 명령 게이트가 실제로 막는지 테스트가 고정.

### Step 5. 정리 [단순]

- 산출: `record_global_summary` 제거, `hermes-message.py` 경고, 백로그 파일, 문서 확정 표시(G-3? 아님 — G-8 제외 G-32 · G-33 · G-34 닫힘).
- 검증: 목표 11·13 + `bash tests/run-all.sh` 0 실패.

## 6. 의사결정 로그

- 2026-09-15: 소우주 공통 층의 저장 위치는 `.hermes/skills/` **그대로**(설계 안의 `skills/common/` 이 아님) — 근거: L-01 기존 1088개를 옮기지 않는다. 옮기면 zeroday 커밋 1088개 rename. 틀렸을 때 손해: 설계 문서의 경로 표를 고쳐야 함(이 계획에서 고친다).
- 2026-09-15: 배달은 `--deliver` 플래그가 있을 때만, 훅·세션 종료에서 자동 호출 없음 — 근거: RV-15(공장 PUBLIC). 틀렸을 때 손해: 제안이 outbox 에 쌓이고 잊힘 — 세션 시작 훅이 개수를 알린다.
- 2026-09-15: `gh` 배달 실패는 오류가 아니라 `pending` — 근거: P-03 손해 항목(오프라인 대기). 틀렸을 때 손해: 인증 오류를 오프라인으로 오인 — `status` 에 마지막 오류 문구를 남긴다.
- 2026-09-15: `messages` 테이블은 제거하지 않는다 — 근거: 읽는 코드가 남아 있는지 이번에 확인하지 않았다(추측 금지). 틀렸을 때 손해: 죽은 코드가 한 계획 더 산다.
- 2026-09-15: 강등 자동 판정을 넣지 않는다 — 근거: G-8 신호가 고장 나 있어 판정이 틀린다. `2026-09-09-hermes-skill-lifecycle.md` 목표 4 가 먼저. 틀렸을 때 손해: 잡음 스킬이 계속 주입됨 — RV-12 의 필터·형식이 잡음의 비용을 줄인다.

## 7. 발견·예외

- 설계 문서 `skill-layers.md` §1 표의 소우주 공통 위치(`.hermes/skills/common/`)는 이 계획의 결정(위 첫 항목)으로 `.hermes/skills/` 로 바뀐다 — decision-log 에 한 줄 추가 필요(S-01 보충).
- 우주 승격 후 "소우주 확장분 제거" 는 자동이 아니라 안내다 — 소우주가 우주판을 `update-all` 로 받은 뒤 사람이 확장 파일을 지운다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보: P-04 · RV-15 를 R 룰로.

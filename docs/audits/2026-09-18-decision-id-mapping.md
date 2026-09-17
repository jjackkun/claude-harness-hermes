# 설계 확정 절 ↔ 결정 원장 매핑 — 2026-09-18

> 작성일: 2026-09-18
> 목적: `.design-cover-baseline` 의 `heading:` 58건(ID 없는 확정/합의 절)을 `docs/hermes-universe/decision-log.md` 행에 대응시켜 절 제목에 달 ID 를 정한다(계획 `2026-09-18-decision-id-ledger` 목표 3).
> 방법: 서브에이전트가 절 본문과 원장 행을 대조(추측 금지 — 같은 결정을 적은 행만 "있음"). 본 세션이 판정기 실측(접두어·중복·V- 충돌)으로 보완.

## 원장 접두어(실측)

§1 경계·계층 **D** · §2 스킬 **S** · §3 제안 배달 **P** · §4 설치 **I** · §5 정체성 **A** · §6 작업 이력 **J** · §7 원문·운반·암호화 **T**(+`V-6` 예외) · §8 에이전트 생성·조직·기억 **C**(+`A-09`) · §9 인계 **H** · §10 기존 자산 **L** · §11 복사 설치 예외 **E** · §12 리뷰 판정 **RV**. 번호는 접두어 안에서 유일(중복 0건 실측).

## 매핑 표

판정: 절의 **핵심 결정**과 같은 행이 있으면 "있음"(부수 결정 누락은 비고 "보충 후보"). 핵심 결정이 없으면 "새 행 필요". 폐기 행만 대응하면 "확인 필요".

| # | 파일 | 절 제목 | 원장 ID(있음) | 새 행 초안(없을 때: 접두어 · 결정 — 이유 — 손해) | 비고 |
|---|---|---|---|---|---|
| 1 | agent/creation-and-organization.md | 2. 생성과 소환 (합의) | C-01 | — | "설치 시 `main`만 자동"은 C-03 과 겹침 |
| 2 | agent/creation-and-organization.md | 3. 입사 경로 (확정) | C-03 | — | 절 안의 "폐기" 문단 = C-02 폐기 |
| 3 | agent/creation-and-organization.md | 4. 수습 기간 (확정) | C-04 · C-10 · RV-17 | — | C-10 은 원장 "합의". 방치 수습의 은퇴 기간은 양쪽 모두 미정 |
| 4 | agent/creation-and-organization.md | 5. 일을 시켰을 때 담당을 찾는 흐름 (확정) | C-03 · C-05 · C-11 | — | 보충 후보(C): "담당 두지 않음 → 기억" 분기·"공통 컴포넌트는 쓰되 고치지 않는다" 는 행 없음(dd4dee0 에서 구현됨) |
| 5 | agent/creation-and-organization.md | 6. 조직 정의는 소우주가 (확정) | C-09 | — | 폐기 문단 = C-06 · C-07 · C-08 |
| 6 | agent/creation-and-organization.md | 7. 조직 단위와 스킬 세 번째 층 (확정) | C-12 · C-13 | — | — |
| 7 | agent/creation-and-organization.md | 8. 같은 에이전트의 동시 소환 (확정) | C-14 | — | — |
| 8 | agent/creation-and-organization.md | 공장의 조직 템플릿 (확정) | C-09 · C-18 | — | 템플릿 3종 목록·"수정은 이슈로 제안" 명시 행 없음 |
| 9 | agent/creation-and-organization.md | 담당 매칭 규칙 (합의) | C-11 | — | — |
| 10 | agent/creation-and-organization.md | 사람 대면 CLI (확정) | — (관련 C-03 · C-04 · RV-17) | **C-19** — `hermes-agent.py` 하나가 입사·정식·은퇴·복직·명부·whoami 를 맡고 사람만 부른다. 자연어를 축 값으로 판별하는 모델 호출은 두지 않고 에이전트가 인자를 채우며, 매칭 결과는 `task.assigned` 에 남겨 사후 대조한다 — 상태 전이는 전부 사람 권한이라 진입점을 하나로 모아야 훅·스킬이 같은 경로를 탄다; 모델 판별은 검증 근거가 없다 — 오판이 곧 잘못된 인자가 되고 대조는 사후에만 가능 | "CLI 하나·모델 판별 없음" 결정 행 없음 |
| 11 | agent/creation-and-organization.md | 틀은 하나 — 직군 · 수직 · 수평 (확정) | C-17 | — | — |
| 12 | agent/handoff-contract.md | 1. 인계의 네 방향 (확정) | H-01 · RV-07 | — | — |
| 13 | agent/handoff-contract.md | 2. 요청서(봉투) 칸 (확정) | H-02 · RV-08 | — | 보충 후보(H): `done_when` 5형식(G-21)·`inputs` 참조 강제는 RV-09 이유 칸에만 |
| 14 | agent/handoff-contract.md | 3. 되돌아오는 방식 (확정) | H-03 · H-05 · RV-07 · RV-08 | — | 2차 되묻기는 RV-08 |
| 15 | agent/handoff-contract.md | 4. 다른 소우주에 있는 일 (확정) | H-04 | — | — |
| 16 | agent/handoff-contract.md | 5. 에이전트는 소우주 하나에만 — 겸직 없음, 복제만 (확정) | H-09 | — | 폐기 표 = H-06 · H-07 · H-08 |
| 17 | agent/handoff-contract.md | 6. 다중 컴퓨터는 그대로 — 열쇠 없음 안내 (확정) | H-10 · RV-02 · RV-03 | — | `doctor` 만 세션 안 허용은 T-11 계열 |
| 18 | agent/handoff-contract.md | 기억을 물었을 때 "없음"의 구분 (확정) | H-11 | — | — |
| 19 | agent/identity.md | 3. 행위자 형식 (확정) | A-03 | — | 보충 후보(D/A): "사람 id 만 소우주를 넘나든다·`git config user.name` 대조" 행 없음 |
| 20 | agent/identity.md | 4. 수행자와 지시자 (확정) | A-04 · A-05 | — | 하위절 "세션별 지시자" = RV-05 |
| 21 | agent/identity.md | 6. 폴더 (합의) | A-08 | — | 폐기 = A-07 |
| 22 | agent/identity.md | SOUL.md 머리말 (합의) | A-09 | — | A-01(폐기)·A-02 → A-09. `universe_id`·`created_at`·`approved_by` 칸은 A-09 에 없음(보충 후보) |
| 23 | agent/identity.md | git 추적 (확정) | — (관련 C-14) | **A-10** — 정체성 자산(`agents/<id>/SOUL.md`·`skills/**`·`organization.yaml`·`agents.json`)은 git 추적, `MEMORY.md`·`summons/` 는 추적하지 않는다. `.gitignore` 마커는 `.hermes/*` 아래 디렉터리 단계마다 예외를 풀고 재무시 줄은 예외 뒤에 둔다 — 정체성·조직·명부는 다른 컴퓨터로 가야 할 원천이고 MEMORY 는 파생물, 토큰은 그 컴퓨터 안에서만 뜻 — 예외 줄 순서가 틀리면 파생물이 커밋되거나 SOUL 이 안 간다 | 정체성 자산 추적 행 없음 |
| 24 | agent/identity.md | 배선 (확정) | RV-05 · RV-06 | — | 판정 순서(환경변수→훅→main)는 구현 세부 |
| 25 | agent/memory-events.md | 2. git과 같은 원리 (확정) | C-14 · C-16 | — | — |
| 26 | agent/memory-events.md | 4. 내용 충돌 (확정) | C-15 · RV-11 | — | — |
| 27 | agent/memory-events.md | 6. 보호 (확정) | — (관련 J-07 · T-13) | **C-20** — 기억 이벤트 `body` 는 원격(`refs/hermes/sync` `memory/`)에 올릴 때 암호화하고 `memory_id`·`ts`·`kind`·`about`·`revises`·`content_hash` 기계 칸은 평문 — 작업 이력 자유 글 칸(J-07)과 같은 규칙, 칸 종류로 나누면 탐지에 의존하지 않는다 — `about` 에 민감 내용이 들어가면 평문 노출(주제 키 형식 미정) | J-07/T-13 은 이력 칸 3개만 |
| 28 | agent/memory-events.md | 저장 (확정) | C-14 | — | 구버전 DB 지연 생성은 #35 |
| 29 | agent/work-journal.md | 2. 이벤트 종류 (합의) | J-05 · RV-10 · H-03 · H-04 · RV-08 | — | 보충 후보(J): 종류 12개 열거. **문서 불일치**: 2절 heartbeat "미정" vs 8절 120분 확정 |
| 30 | agent/work-journal.md | 3. 결과는 세 층 (합의) | J-04 · RV-09 | — | — |
| 31 | agent/work-journal.md | 5. 원문을 담지 않는 허용목록 스키마 (합의) | J-06 | — | — |
| 32 | agent/work-journal.md | 6. 저장 — 원본 단위와 두 층 (합의) | J-03 | — | 폐기 = J-01 · J-02 |
| 33 | agent/work-journal.md | 7. 칸별 암호화 (확정) | J-07 · T-13 | — | — |
| 34 | agent/work-journal.md | 8. 누락 감지 (합의) | — (관련 RV-10) | **J-08** — 세션 종료 시 `task.started` 만 있고 `task.finished` 없는 작업에 Stop 훅이 `system:claude-stop-journal-gap` 누락 이벤트를 붙이고(`gap-check --all`, `session-end`), heartbeat `step` 이 120분 넘게 끊기면 다음 훅이 잡는다(`heartbeat-timeout`). 120분 = zeroday `loop_steps` 9구간 정상 최대 13.4분×1.5 를 넘는 관측 이상치(79.7분) 위, `.hermes/journal.json` `heartbeat_minutes` 로 조정 — 적히지 않은 작업이 조용히 사라지지 않게 — 표본 9구간뿐, `--all` 오용 시 진행 중 작업 오기록 | RV-10 은 "step 을 heartbeat 로" 까지만 |
| 35 | agent/work-journal.md | 구버전 DB 호환과 롤백 (확정) | — | **J-09** — 새 표·칸(`journal_events`·`loops.started_by`·`memory_events`·`summons`·`skill_index` 5칸)이 없는 기존 `state.db` 에서 훅은 죽지 않고 한 줄 알린 뒤 exit 0, 첫 실행에 `CREATE TABLE IF NOT EXISTS`·`ADD COLUMN` 으로 지연 생성. 롤백은 `hermes-journal.py rollback --confirm` 이 표를 지우지 않고 `journal_events_disabled_<ts>` 로 이름만 바꾼다 — 기존 소우주 훅이 스키마 차이로 멈추면 안 되고 이벤트는 원본이라 지우지 않는다 — 이름 바꾼 표가 남고, 지연 생성 실패는 조용히 건너뛰어 이력이 빠질 수 있다 | memory-events·identity §7·skill-layers 에 반복 서술 — 한 행으로 묶음 |
| 36 | protection/encryption-keys.md | 1. age 기반의 뜻 (확정) | T-08 · V-6 | — | V-6 은 재번호 대상(아래) |
| 37 | protection/encryption-keys.md | 2. 열쇠 단위 (확정·합의) | T-09 · T-12 · RV-02 · RV-03 | — | 보충 후보(T): 열쇠 경로·0600·명령 6종·`key.registered/revoked`(G-3) |
| 38 | protection/encryption-keys.md | 3. 비상 열쇠 (확정) | T-10 · T-14 · RV-03 | — | — |
| 39 | protection/encryption-keys.md | 4. 열쇠는 AI 세션 밖에서만 (확정) | T-11 · RV-04 | — | `hermes-sync.py tombstone` 차단(G-5) 행 없음 |
| 40 | protection/raw-transcript.md | 3. 원문 경계 원칙 (확정) | T-02 | — | D-05 4항과 같은 문장 |
| 41 | protection/raw-transcript.md | 5. 두 벌 구조 (확정) | T-05 | — | 4절 폐기 이유 = T-04 |
| 42 | protection/raw-transcript.md | 8. 이미 올라간 평문 (확정) | T-03 | — | `git rm --cached` 도 하지 않음 세부 |
| 43 | protection/sync-transport.md | 1. 무엇을 옮기나 (합의) | T-07 · RV-03 | — | T-06 폐기 포함 |
| 44 | world/skill-layers.md | "필요 없음"의 다른 원인과 판단 방법 (합의) | S-08 · RV-14 | — | — |
| 45 | world/skill-layers.md | 1. 네 층 (확정) | S-01 · C-12 · RV-18 · RV-19 | — | 보충 후보(S): 불변 `skill_id` 키·`.hermes/units/` gitignore 예외 |
| 46 | world/skill-layers.md | 2. 층 사이 관계 — 덮어쓰기가 아니라 확장 (합의) | S-03 · RV-13 | — | 읽는 순서는 RV-12 |
| 47 | world/skill-layers.md | 3. 승격 — 일반화 (합의) | S-02 · S-03 | — | — |
| 48 | world/skill-layers.md | 4. 제안과 허가 (확정) | S-06 | — | 폐기 = S-04 · S-05 |
| 49 | world/skill-layers.md | 6. 강등 (합의) | S-10 · S-08 | — | 보충 후보(S): "내리는 결정은 소유 층이"·"우주→소우주 강등은 fork" |
| 50 | world/skill-layers.md | 사용 횟수는 기준이 아니다 (확정) | 확인 필요 — S-09(폐기) | **S-11**(원하면) — 소우주가 사용 횟수를 우주에 올리는 경로를 두지 않는다; "조용히 안 쓰이는 스킬" 은 켠/끈 비교와 발동 정확도 평가로 가린다 — 1년에 한 번 쓰여도 중요한 스킬이 있어 횟수는 가치를 재지 못한다(S-09 폐기) — 무용 스킬 발견이 켠/끈 실험 비용에 좌우됨 | 이 절의 결정 = S-09 의 폐기 사유 |
| 51 | world/skill-layers.md | 색인 칸 — `skill_index` (확정) | RV-19 · RV-18 · L-01 · D-05 | — | 지연 추가는 #35 |
| 52 | world/skill-layers.md | 세 번째 층은 "팀"이 아니라 소우주가 지정한 조직 단위 (확정) | C-12 · C-13 | — | — |
| 53 | world/skill-layers.md | 핵심 기준 (확정) | S-07 | — | — |
| 54 | world/skill-proposal-delivery.md | 2. 소우주가 개선한 경우의 흐름 (확정) | P-03 · P-04 · RV-15 · S-03 · S-06 | — | 보충 후보(P): 봉투 상태 전이·`gh issue view` 로 읽기·확장분 제거는 안내만 |
| 55 | world/universe-isolation.md | 1. 정의 (확정) | D-04 | — | 3절 폐기 = D-02 · D-03 |
| 56 | world/universe-isolation.md | 2. 격리 원칙 (확정) | D-05 · T-02 · H-09 | — | 보충 후보(D): "우주가 소우주 안을 들여다보지 않는다"·"사람 id 는 공유" |
| 57 | world/universe-isolation.md | 4. 소우주 키 — universe_id (합의) | D-06 · D-05 | — | 보충 후보(D): `universe.id` 추적 마커·`project_id` 칸 이름 유지 |
| 58 | world/universe-isolation.md | 전환 후 동작 (확정) | D-06 · L-05 | — | 보충 후보(D): `universe.id` 없으면 basename 폴백+경고 |

## 집계

**있음 52 · 새 행 필요 5 · 확인 필요 1** (합 58). 새 행: #10 C-19 · #23 A-10 · #27 C-20 · #34 J-08 · #35 J-09. 확인: #50.

## 판정기 실측으로 함께 드러난 것

- `V-6`: `V-` 는 `open-questions.md` 의 실측 항목 번호(V-1~V-8)인데 원장 §7 이 `V-6` 을 결정 행으로 써 접두어가 두 뜻이다. 판정기가 `V-1~V-8` 을 `id-unknown` 7건으로 잡는다. 재번호(`T-` 다음 순번) 시 인용 9곳을 함께 고친다.
- 보충 후보 16건: 절의 핵심 결정은 원장에 있으나 부수 결정이 행으로 없는 것. ID 부착에는 지장 없음. 원장 완결성을 원하면 별도 작업.
- 문서 불일치 1건: `work-journal.md` 2절 heartbeat "미정" vs 8절 120분 확정.

## 2차 — 미인용 결정 ID 29건 ↔ 구현 계획서 대응 (2026-09-18)

절 제목에 ID 를 단 뒤 판정기 (A) 가 "계획서에 인용되지 않은 결정 ID" 29건을 냈다. 서브에이전트가 각 ID 의 원장 문장과 계획서 목표 문장을 대조(추측 금지):

| 계획서 | 대응 ID |
|---|---|
| `completed/2026-09-15-universe-id-journal.md` | A-04 · J-04 · J-08 · J-09 |
| `completed/2026-09-15-agent-identity.md` | A-08 · A-10 · C-03 · C-04 · C-09 · C-10 · C-15 · C-19 · H-03 · J-09 |
| `completed/2026-09-15-sync-transport-encryption.md` | T-09 · T-10 · T-13 · T-14 · T-16 |
| `completed/2026-09-15-skill-layers-delivery.md` | RV-19 · S-02 · S-03 · S-07 · S-08(부분: exclude 신고만) · S-11(부분: 횟수 전송 경로 없음) · J-09 |
| `completed/2026-09-17-design-gaps-tier2.md` | C-05 · C-19 |
| `completed/2026-09-17-design-coverage-gaps.md` | H-03 |

집계: 계획서 있음 23 · 부분 2 · **없음 4** — C-20(기억 body 원격 암호화: `hermes_sync_fragments.py` 에 코드는 있으나 계획 문장 없음) · D-04(정의성 결정, 코드 대상 아님) · H-04(다른 소우주 일은 사람 경유 — `handoff.external` kind 만 예약, 기록 코드 0) · H-09(에이전트 복제는 우주 템플릿 경유 — `kind: template` 값만 예약). 25건은 해당 계획서 §2 머리에 "설계 결정 인용(소급)" 한 줄로 적었다. 없음 4건은 `.design-cover-baseline` 에 남기고 `backlog/design-decisions-unplanned.md` 로 관리.

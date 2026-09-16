# 헤르메스 우주 설계 — 소우주 격리 · 스킬 계층 · 에이전트 정체성 · 기록 보호

> 작성일: 2026-09-15
> 목적: 2026-09-15 설계 논의에서 정한 결정을 한곳에 모아, 이후 구현 계획의 유일한 원천으로 삼는다.
> 상태: **설계 완료 · 구현 계획 작성 완료(구현 전).** 큰 주제 4건 중 Q-1(에이전트 생성) · Q-2(인계 계약) · Q-3(기존 자산 정리) · Q-4(복사 설치 예외) **모두 완료.** 2026-09-15 리뷰에서 빈틈 12건과 cumora 교훈 9건을 설계 문서에 넣었고, 사용자 위임으로 19건 전부 **확정(위임)** 했다([decision-log.md](decision-log.md) 12절 RV-01~19, 근거 [docs/audits/2026-09-15-hermes-universe-design-review.md](../audits/2026-09-15-hermes-universe-design-review.md)). 구현 계획서 5편(`docs/exec-plans/active/2026-09-15-{copy-install,universe-id-journal,sync-transport-encryption,agent-identity,skill-layers-delivery}.md`)을 썼고, 실측은 서버 항목 V-1~V-3 만 남았다(V-4~V-8 확인·결정됨). 다음은 설계 문서 갱신 완료 → 구현(계획 1 복사 설치부터, 순서 근거 G-24).

## 개요

### 출발점 — 무엇이 문제였나

헤르메스는 세션을 열 때마다 스킬을 주입하고 기록을 남긴다. 겉으로는 최상위 에이전트가 하위
에이전트를 만들어 일을 나누는 것처럼 보인다. 그러나 실제로는 **에이전트는 하나뿐이고, 스킬과
기록을 가져다 써서 역할이 나뉜 것처럼 보일 뿐**이다. 그래서 새 세션은 이전 일을 정확히 기억하지
못하고, 누가 무엇을 했는지 기록에 남지 않는다.

사용자가 제시한 방향:

1. 작업마다 에이전트를 만들고(자동 또는 수동) 그 에이전트가 자기 몫을 한다.
2. 에이전트는 자기 정체성(SOUL.md)과 자기 업무 기록을 따로 가진다.
3. 일이 끝나면 곧바로 기록한다. 깃처럼 "어떻게 무엇을 했고, 성공했는가 실패했는가"를 정확히
   남겨야 나중에 스레드·그래프·문서로 만들 수 있다.
4. 스킬은 공통·팀·개인으로 나누어, 하나를 고치면 여럿이 함께 좋아지게 한다.

이 방향을 따라가다 보니 경계(어디까지가 한 세계인가), 스킬 이동 규칙, 설치 방식, 정체성,
작업 기록, 그리고 기록에 섞이는 민감정보 보호까지 함께 다시 설계하게 되었다.

### 이 폴더를 읽는 규칙

- **헤르메스 회상(rolling summary)보다 이 폴더가 우선한다.** 논의 도중 뒤집힌 결정이 여럿 있고,
  회상은 뒤집히기 전의 옛 결정을 결정사항처럼 주입한 사례가 확인되었다.
- 결정이 바뀌면 먼저 [decision-log.md](decision-log.md)에 "무엇이 무엇으로 바뀌었는가"를 적고,
  그다음 해당 설계 문서를 고친다.
- 문서마다 **확정**(사용자가 명시적으로 확정) · **합의**(명시 확정은 없으나 이후 논의가 그 전제
  위에서 진행) · **미정**을 구분해 적는다.
- `✅ 리뷰 확정 (날짜, RV-xx)` 표시가 붙은 절은 리뷰에서 넣은 뒤 사용자 위임으로 확정한 보강이다. 상태
  **확정(위임)** 은 사용자가 뒤집을 수 있다는 뜻이다. 목록은 [open-questions.md](open-questions.md) 4절, 결정 근거는 [decision-log.md](decision-log.md) 12절.

## 용어

| 용어 | 뜻 |
|---|---|
| **우주 (설치 공장)** | 이 저장소 `claude-harness-hermes`. 규칙·스킬·훅의 설계도를 만들어 설치·전파한다 |
| **소우주** | 설치 대상 저장소 하나 = 프로젝트 하나. 예: `zeroday-frontend`, `terminal-shipping` |
| **universe_id** | 소우주를 가르는 불변 키(UUID) |
| **우주 공통 / 소우주 공통 / 팀 / 개인** | 스킬의 네 층 |
| **봉투** | 소우주가 우주에 스킬을 제안할 때 만드는 묶음 |
| **보낼 편지함** | 소우주 안에서 봉투를 먼저 쓰는 곳 `.hermes/outbox/` |
| **행위자** | 기록의 주체. `human:` · `agent:` · `system:` |
| **작업 이력 (journal)** | 에이전트 작업을 불변 이벤트로 남긴 기록 |
| **대화 원문** | 사용자 입력과 응답의 원래 글 |
| **금고본 / 공개본** | 원문의 두 벌. 금고본은 통째 암호화, 공개본은 사람이 승인한 검은 박스 평문 |
| **자물쇠 / 열쇠** | age의 공개키 / 개인키 |
| **비상 열쇠** | 모든 컴퓨터를 잃었을 때 쓰는, 컴퓨터 밖에 보관하는 열쇠 |

## 문서 지도

| 문서 | 다루는 것 |
|---|---|
| [design/world/universe-isolation.md](design/world/universe-isolation.md) | 우주·소우주 정의, 격리 원칙, universe_id |
| [design/world/skill-layers.md](design/world/skill-layers.md) | 스킬 4층, 승격(제안→허가)·강등, 우주의 판단 기준 |
| [design/world/skill-proposal-delivery.md](design/world/skill-proposal-delivery.md) | 소우주→우주 제안 봉투, 보낼 편지함, GitHub 이슈 배달 |
| [design/world/copy-install.md](design/world/copy-install.md) | symlink 설치 폐지, 복사 설치·설치 목록·버전 기록 |
| [design/agent/identity.md](design/agent/identity.md) | 에이전트 id·이름·상태·조직 값, 행위자 형식, SOUL/명부 |
| [design/agent/creation-and-organization.md](design/agent/creation-and-organization.md) | 입사·소환·수습 기간, 담당 찾기, 조직 정의는 소우주가 |
| [design/agent/memory-events.md](design/agent/memory-events.md) | PK를 가진 추가 전용 기억 이벤트, 내용 충돌 처리 |
| [design/agent/work-journal.md](design/agent/work-journal.md) | 작업 이력 이벤트, 결과 3층, 저장 2층, 칸별 암호화 |
| [design/agent/handoff-contract.md](design/agent/handoff-contract.md) | 인계 네 방향, 봉투 칸, 소우주 간 요청은 사람 경유, 겸직 없음 · 복제만, 열쇠 없음 안내 |
| [design/protection/raw-transcript.md](design/protection/raw-transcript.md) | 대화 원문 경계, 두 벌 구조, 마스킹의 역할 |
| [design/protection/encryption-keys.md](design/protection/encryption-keys.md) | age, 컴퓨터별 열쇠, 비상 열쇠 절차, AI 세션 밖 규칙 |
| [design/protection/sync-transport.md](design/protection/sync-transport.md) | `refs/hermes/sync` 운반, push 정책, 서버 호환성 |
| `migration/copy-install-all-universes.md` · `migration/enable-sync.md` (예정, 계획 1 · 3 에서 작성) | 사람이 실행하는 이전 절차 — 등록된 모든 소우주의 복사 설치 전환, 소우주에서 이식(sync) 켜기 |
| [evidence/current-state-audit.md](evidence/current-state-audit.md) | 2026-09-15 실측 사실과 확인 명령 |
| [evidence/existing-tools-research.md](evidence/existing-tools-research.md) | 공개 스킬·도구 웹 조사 결과 |
| [decision-log.md](decision-log.md) | 결정 순서 기록 (뒤집힌 결정 포함) |
| [open-questions.md](open-questions.md) | 남은 주제와 미확인 항목 |

## 확정 결정 한눈에

| 영역 | 결정 | 상태 |
|---|---|---|
| 경계 | 저장소 하나 = 프로젝트 하나 = 소우주 하나. 기억은 소우주 밖으로 나가지 않는다 | 확정 |
| 키 | 소우주는 폴더 이름이 아닌 UUID(`universe_id`)로 가른다 | 합의 |
| 스킬 | 우주 공통 · 소우주 공통 · 조직 단위 · 개인 4층, 위아래 양방향 이동. 소우주 공통은 `.hermes/skills/` 그대로, 층 구분은 폴더가 아니라 설치 목록 · `skill_index.layer`(RV-18 · RV-19) | 확정 |
| 스킬 3층 | 세 번째 층은 소우주 조직 정의의 수평 축 단위, 비우면 건너뜀 | 확정 |
| 승격 | 아래 층이 제안하고 받는 층이 허가한다. 다른 소우주 정보는 필요 없다 | 확정 |
| 우주 판단 | "특정 프로젝트에 국한되는가". 사용 횟수는 기준이 아니다 | 확정 |
| 제안 배달 | 소우주 보낼 편지함에 쓰고 공장 GitHub 이슈로만 배달. 로컬 배달 금지. 배달은 사람이 `--deliver` 를 붙였을 때만, `gh` CLI 로(RV-15) | 확정 |
| 설치 | symlink 설치 폐지, 복사 설치. 공장 자기 설치만 저장소 안 상대경로 링크 | 확정 |
| 정체성 | id(불변) · 이름(a.k.a.) · 상태 · 조직 값 (직무·소속은 소우주 조직 정의의 값) | 합의 (A-09) |
| 입사 | 사람이 자연어로 시키거나, 담당이 없을 때 문의해 승낙. 자동 생성은 설치 시 `main`뿐 | 확정 |
| 수습 기간 | 신규 에이전트는 수습 기간으로 시작, 정식 전환은 사람 판단 | 확정 |
| 조직 정의 | 틀은 하나: 직군 · 수직 · 수평 세 축. 축의 종류와 "사람이 맨 위"는 공장이 고정, 값은 각 소우주가 정의. 설치 시 빈 조직(`empty.yaml`)을 자동 복사하고 고르기는 사람이 나중에(C-18) | 확정 |
| 인계 | 지시 · 협업 · 요청 · 보고, 봉투에 `goal` · `done_when` 필수, 다른 소우주 일은 사람 경유 | 확정 |
| 이동 | 에이전트는 소우주 하나에만. 겸직 · 파견 없음, 우주 템플릿 경유 복제만 | 확정 |
| 열쇠 안내 | 열쇠 없는 컴퓨터는 세션 시작 시 기계가 알리고 세션 밖 생성 절차 안내 | 확정 |
| 기존 자산 | 기존 소우주 스킬은 그대로, 심링크→복사만 전환. 공장의 모순 스킬 2개 삭제, `global.db` 쓰기 중단 | 확정 |
| 기억 | UUIDv7 PK 추가 전용 기억 이벤트, `MEMORY.md`는 보기, 내용 충돌은 둘 다 보여 주고 정리 이벤트로 | 확정 |
| 행위자 | `human:` · `agent:` · `system:`, 기록에 `actor`·`requested_by` | 확정 |
| 기본 세션 | 에이전트 지정 없는 세션은 기본 에이전트 `main`이 수행자 | 확정 |
| 작업 이력 | 불변 이벤트 단위, 로컬 DB 즉시 기록(`journal_events`, INSERT 전용 트리거) + 코드와 분리된 git 참조 보존 | 합의 |
| 원문 경계 | 원문은 그 소우주 저장소와 그 원격 주소 밖으로 나가지 않는다 | 확정 |
| 이미 올라간 평문 | 손대지 않는다 | 확정 |
| 원문 보호 | 두 벌 구조: 금고본(항상, 통째 암호화) + 공개본(사람 승인 시만) | 확정 |
| 암호화 | age 기반 직접 구현(`age` CLI, V-6 확정), 기존 도구는 참고만 | 확정 |
| 열쇠 | 컴퓨터마다 자기 열쇠 + 소우주별 비상 열쇠(컴퓨터 밖 보관) | 확정 |
| 비상 열쇠 | 사용자 컴퓨터에서 생성, 24단어 니모닉으로 한 번만 표시(T-14), 시험 복호화로 확인 후 폐기 | 확정 |
| 열쇠 취급 | 열쇠 생성·입력은 AI 세션 밖 터미널에서만, 훅으로 차단 | 확정 |
| 이력 암호화 | 기계 칸은 평문, 자유 글 칸 3개는 암호화, 모든 소우주 동일 | 확정 |

## 읽는 순서

1. 이 README
2. [design/world/universe-isolation.md](design/world/universe-isolation.md) — 모든 결정의 바탕
3. 관심 영역의 설계 문서
4. [open-questions.md](open-questions.md) — 구현 계획을 쓰기 전에 반드시

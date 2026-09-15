# 남은 주제와 미확인 항목 — 헤르메스 우주 설계

> 작성일: 2026-09-15
> 목적: 아직 논의하지 않은 주제와, 설계는 정했지만 사실 확인·실측이 필요한 항목을 모아 구현 계획 전에 닫는다.

## 개요

- **1절**은 사용자와 이어서 논의하기로 한 큰 주제다.
- **2절**은 설계 문서가 전제로 삼았지만 아직 확인하지 않은 사실이다. 구현 계획을 쓰기 전에 닫아야 한다.
- **3절**은 설계 안에서 세부가 비어 있는 항목이다.
- **4절**은 2026-09-15 리뷰에서 나온 보강 제안과 그 판정이다. 사용자가 판정을 위임해 전부 확정(위임)됐다 — [decision-log.md](decision-log.md) 12절 RV-01~RV-17.

## 1. 큰 주제

| # | 주제 | 상태 | 논의할 내용 |
|---|---|---|---|
| Q-1 | 에이전트 생성 | **완료** (2026-09-15) | [creation-and-organization.md](design/agent/creation-and-organization.md), [memory-events.md](design/agent/memory-events.md) |
| Q-2 | 인계 계약 | **완료** (2026-09-15) | [handoff-contract.md](design/agent/handoff-contract.md) |
| Q-3 | 기존 자산 정리 | **완료** (2026-09-15) — 기존 스킬은 그대로, 심링크→복사만, 공장의 모순 스킬 2개 삭제, `global.db` 쓰기 중단 | zeroday-frontend 소유자 없는 스킬 1088개, `~/.hermes/global.db` `harness_rules` 1142줄, 잘못 결정화된 스킬 2개(`repository-isolation-principle.md` "다층 체계 금지", `unified-hook-deployment.md` "훅도 symlink로 통일") |
| Q-4 | 복사 설치의 예외 | **완료** (2026-09-15) — 공장은 상대경로 링크 + 깨진 링크 감지, 메모리 폴더 링크는 범위 밖 | 공장 자기 설치 시 링크 허용 여부, `lib/harness_installers.sh:721-723` 메모리 폴더 링크 범위 |

## 2. 사실 확인·실측이 필요한 항목

| # | 항목 | 왜 필요한가 | 확인 방법 |
|---|---|---|---|
| V-1 | gitlab.com이 `refs/hermes/sync` push를 받는가 | terminal-shipping 운반 경로. 공식 문서에 금지 목록만 있고 허용 명시가 없다 | 테스트 저장소에 `git push origin HEAD:refs/hermes/sync` |
| V-2 | zeroday-frontend 사내 서버(`211.206.116.39:3000`)의 소프트웨어 종류 | 포트로 Gitea류라고 **추정**했을 뿐. Gitea/Forgejo는 소스상 허용 확인 | 서버 웹 화면 확인 후 V-1과 같은 push 실측 |
| V-3 | 서버가 사용자 정의 참조를 광고(hideRefs)하는가 | fetch 가능 여부 | 실측 |
| V-4 | Claude Code 훅 입력에 하위 에이전트 종류·id가 넘어오는가 | 대화형 세션에서 기계가 `agent:` 행위자를 찍을 수 있는지 | **확인됨 (2026-09-15, 공식 문서 hooks.md)**: `SubagentStop` 에 `agent_id`(Claude Code 내부 id) · `agent_type`(예: `code-reviewer`) 이 오고, 모든 훅에 `session_id` · `transcript_path` 가 온다. `agent_type` 은 우리 직무 템플릿에 대응하고, 명부 id 는 소환 토큰(RV-06)으로 찍는다 |
| V-5 | 복사 설치 시 스킬을 하위 폴더로 나눠도 로딩되는가 | 공통 스킬과 소우주 자체 스킬을 폴더로 구분할 수 있는지 | **확인됨 (2026-09-15, 공식 문서 skills.md)**: `.claude/skills/<이름>/SKILL.md` **직계 폴더만** 읽는다. 하위 폴더 불가, 심링크 폴더는 지원. → 공통/자체 구분은 폴더가 아니라 설치 목록(`.claude/.factory-manifest.json`)으로만 한다 |
| V-6 | age CLI와 pyrage 중 무엇을 쓸 것인가 | 현재 둘 다 미설치, Python 3.10.12. 설치는 사용자가 WSL에서 직접 | 구현 계획에서 결정 |
| V-7 | 공장 GitHub 저장소가 공개인가 | 봉투에 이름을 넣지 않는 결정(3절)의 전제 | **확인됨 (2026-09-15)**: `gh repo view jjackkun/claude-harness-hermes --json visibility` → `PUBLIC`. 봉투 본문이 공개 게시물이 된다([skill-proposal-delivery.md](design/world/skill-proposal-delivery.md) 3절) |
| V-8 | Claude Code 훅 입력에 토큰 사용량이 오는가 | 작업 이력 `evidence.usage` 칸 제안의 전제 | **확인됨 (2026-09-15, 공식 문서 sessions.md)**: 훅 입력에 없고 transcript 형식은 비공개(버전마다 바뀜). `claude -p --output-format json` 은 usage 를 낸다 → RV-10 의 `usage` 칸은 **헤드리스 러너 경로에서만** 채운다 |

## 3. 설계 안에서 비어 있는 세부

| # | 항목 | 관련 문서 |
|---|---|---|
| G-1 | 압축(Part D)과 추가 전용 암호 조각의 충돌. 현재 압축은 jsonl을 요약본으로 덮어써 다른 컴퓨터에 전파한다 | [sync-transport.md](design/protection/sync-transport.md) |
| G-2 | 각 컴퓨터 `state.db`에 이미 있는 원문을 새 구조로 처음 올리는 백필 절차 | [sync-transport.md](design/protection/sync-transport.md) |
| G-3 | 자물쇠(공개키) 목록을 어디에 둘지 (`refs/hermes/sync` 안 등) | [encryption-keys.md](design/protection/encryption-keys.md) |
| G-4 | 키 교체 절차 — age에는 교체 명령이 없다. "새 조각부터 새 자물쇠" 흐름과 옛 열쇠 보관 | [encryption-keys.md](design/protection/encryption-keys.md) |
| G-5 | `tombstone` 비상 삭제의 실제 절차(참조 재작성 범위, 사람 승인 방식) | [work-journal.md](design/agent/work-journal.md) |
| G-6 | UUIDv7 생성 방법, `journal_events` 스키마와 UPDATE/DELETE 차단 트리거 | [work-journal.md](design/agent/work-journal.md) |
| G-7 | 공개본을 만드는 사용자 흐름(무엇을 고르고, 기계 제안을 어떻게 보여 주고, 어디에 올리는가) | [raw-transcript.md](design/protection/raw-transcript.md) |
| G-8 | 도움 판정 신호 고장(zeroday-frontend: 주입 275회 중 262회를 도움으로 셈, 강등 0건). 강등·승격 판단 전에 고쳐야 한다 | [skill-layers.md](design/world/skill-layers.md) |
| G-9 | 진행 중 계획 `docs/exec-plans/active/2026-09-15-decision-ledger.md`와 J-05(작업 이력으로 흡수)의 관계 | [work-journal.md](design/agent/work-journal.md) |
| G-10 | 결정화 스킬 `rotate-ephemeral-work-logs`("jsonl 로그는 로테이션")에서 작업 이력을 명시적으로 제외 | [work-journal.md](design/agent/work-journal.md) |
| G-11 | 헤르메스 회상이 뒤집힌 결정을 결정사항으로 주입하는 문제(이번 논의에서 여러 번 관측) | [decision-log.md](decision-log.md) |
| G-12 | 에이전트 성적·강등 기준(주장 vs 검증 차이 활용), SOUL.md 세부 형식, 명부 형식 | [identity.md](design/agent/identity.md) |
| G-13 | 함께 쓰는 소우주에서 동료도 헤르메스를 쓸 때 사람 id 결정 방법(`git config user.name` 대조) | [identity.md](design/agent/identity.md) |
| G-14 | 조직 정의 `organization.yaml`의 정확한 스키마(`discipline` · `rank` · `unit` 세 축의 값과 단위별 영역)와 수평 단위 id 형식 | [creation-and-organization.md](design/agent/creation-and-organization.md) |
| G-15 | 공장 조직 템플릿의 실제 내용(제품 개발 · 사무 · 빈 조직)과 비개발 직무 템플릿(기획·디자인·번역 등) 신설 | [creation-and-organization.md](design/agent/creation-and-organization.md) |
| G-16 | 요청 문장을 조직 축 값으로 판별하는 방법(경로 감지 + 문장 판별), 저장소 밖 산출물·경로 없는 일의 담당 표현 | [creation-and-organization.md](design/agent/creation-and-organization.md) |
| G-17 | 승인 없이 방치된 수습 에이전트의 은퇴 기간 — 근거 있는 값 없음 | [creation-and-organization.md](design/agent/creation-and-organization.md) |
| G-18 | "담당 두지 않음" 선택을 기억하는 방식과 다시 묻는 조건 | [creation-and-organization.md](design/agent/creation-and-organization.md) |
| G-19 | 기억 주제 칸 `about`의 키 형식(민감 내용이 평문 칸에 들어가지 않게), 누가 붙이는가 | [memory-events.md](design/agent/memory-events.md) |
| G-20 | 조직 정의의 허가 권한(`approval`)과 스킬·수습 전환·조직 단위 생성 권한의 연결 | [creation-and-organization.md](design/agent/creation-and-organization.md) |
| G-21 | 봉투 `done_when`을 기계가 검증하는 방법(테스트 이름 · 파일 존재 · 게이트 판정 등 허용 형식) | [handoff-contract.md](design/agent/handoff-contract.md) |
| G-22 | 열쇠 상태 점검 명령과 세션 시작 판정(열쇠 없음 · 조각 미복호화)의 구현 위치 | [handoff-contract.md](design/agent/handoff-contract.md) |
| G-23 | 에이전트 복제 봉투 형식(`kind: template`)과 우주 직무 템플릿 저장 위치 | [handoff-contract.md](design/agent/handoff-contract.md) |
| G-24 | 구현 순서: 복사 설치 전환을 가장 앞에 둔다 (zeroday-frontend가 공장 없는 컴퓨터에서 동작해야 함) | [copy-install.md](design/world/copy-install.md) |
| G-25 | 결정화가 폐기된 결정을 규칙으로 굳히지 않게 하는 장치 (백로그) | [decision-log.md](decision-log.md) |
| G-26 | Claude Code 자체 메모리(`.claude/memory`, `install_memory_symlink`)와 새 설계 에이전트 기억 이벤트의 관계 | [memory-events.md](design/agent/memory-events.md) |
| G-27 | `refs/hermes/sync` 트리 합집합 커밋의 구현(`mktree` · `commit-tree`)과 같은 경로 다른 내용일 때의 처리 | [sync-transport.md](design/protection/sync-transport.md) 4절 |
| G-28 | 마스터 열쇠 감싸기를 채택하면 비상 열쇠 절차(3절)가 "마스터 풀기 → 조각 풀기" 두 단계가 된다. 절차 문서 갱신 | [encryption-keys.md](design/protection/encryption-keys.md) 2절 |
| G-29 | 소환 러너(`hermes-summon`)의 형식과, 에이전트가 `claude -p` 를 직접 띄우는 것을 막는 훅의 판정 규칙 | [identity.md](design/agent/identity.md) 7절 |
| G-30 | 봉투 만료 판정을 세션 시작 훅이 돌린다(RV-08 로 확정, 기본 시간 없음). 남은 것: 훅이 "미착수" 를 판정하는 조회와 알림 문구 | [handoff-contract.md](design/agent/handoff-contract.md) 3절 |
| G-31 | 기억이 규칙과 모순되는지 찾는 기계 탐지의 범위(같은 `about` 키 대조로 충분한가) | [memory-events.md](design/agent/memory-events.md) 4절 |
| G-32 | `skill_index` 에 `universe_id` · 층 · 단위 id · `agent_id` 칸을 더하는 스키마 변경과, 주입 필터가 소환된 에이전트를 아는 방법(V-4 의존) | [skill-layers.md](design/world/skill-layers.md) 1절 |
| G-33 | 확장 파일 `extends: <skill_id>@<version>` 머리말 형식과 설치기의 어긋남 알림 | [skill-layers.md](design/world/skill-layers.md) 2절, [copy-install.md](design/world/copy-install.md) 5절 |
| G-34 | `factory.json` 을 설치 목록(변조 감지)에 넣는 방법과 배달 스크립트의 주소 인자 차단 | [skill-proposal-delivery.md](design/world/skill-proposal-delivery.md) 5절 |

## 4. 리뷰 제안 — 판정 완료 (2026-09-15, 사용자 위임)

2026-09-15 설계 리뷰([docs/audits/2026-09-15-hermes-universe-design-review.md](../audits/2026-09-15-hermes-universe-design-review.md))에서 나온 보강이다. 사용자가 "올바르고, 정상 동작하며, zeroday-frontend 에 문제를 주지 않는 방향" 으로 판정을 위임했고, 그 기준으로 17건 전부 확정(위임)했다. 설계 문서 안에는 `✅ 리뷰 확정 (2026-09-15, RV-xx)` 표시로 있고, 결정·이유·손해는 [decision-log.md](decision-log.md) 12절에 있다. 판정 열의 "조건" 은 zeroday 를 위해 붙인 제약이다.

| # | 제안 | 한 줄 | 문서 | 판정 |
|---|---|---|---|---|
| P-01 | 참조 갱신 경쟁 | 두 컴퓨터 push 는 fetch → 트리 합집합 두-부모 커밋 → 재시도, `--force` 금지 | sync-transport 4절 | 확정 (RV-01) |
| P-02 | 컴퓨터 id = 자물쇠 지문 | hostname 대신 공개키 지문 | encryption-keys 2절 | 확정 (RV-02) |
| P-03 | 마스터 열쇠 감싸기 | 조각은 마스터 자물쇠 하나로, 컴퓨터 추가는 마스터 열쇠 파일 재감싸기만 | encryption-keys 2절 | 확정 (RV-03) |
| P-04 | 훅 차단의 Codex 한계 명시 | 열쇠 차단 · 사칭 방지는 Claude Code 세션에서만 | encryption-keys 4절, identity 7절 | 확정 (RV-04) |
| P-05 | 사람 없는 세션의 지시자 | 루프 = 시작한 사람, cron = `system:hermes-cron` | identity 4절 | 확정 (RV-05) |
| P-06 | 사칭 방지 | 소환은 러너만, `requested_by` 는 호출 세션의 actor | identity 7절 | 확정 — 조건: 공장 러너 스크립트 경유는 허용 목록(헤드리스 루프 보호) (RV-06) |
| P-07 | 규칙 위반 지시는 막힘 | `claimed: blocked` + `rule:<이름>` | handoff 1절 | 확정 (RV-07) |
| P-08 | 응답 없음 처리 | `expires_at` → `handoff.expired` → 대체 수행 기본 경로, 되묻기 남용 제한 | handoff 3절 | 확정 — 조건: 기본 시간 없음, 만료 판정은 세션 시작 훅 (RV-08) |
| P-09 | `verified: none` 은 기계만 | `done_when` 형식이 기계 검증 불가일 때만 | work-journal 3절 | 확정 (RV-09) |
| P-10 | 비용 칸 · heartbeat | `evidence.usage`, `step` 을 heartbeat 로 | work-journal 4절 | 확정 — usage 칸은 V-8 예일 때만 (RV-10) |
| P-11 | 기억은 규칙 아래 | 규칙 충돌 표시, 단일 사례 표시, 철회 흔적 | memory-events 4절 | 확정 (RV-11) |
| P-12 | 층별 스킬 주입 경로 | 소환된 에이전트 기준 필터, 이름+설명만 주입 | skill-layers 1절 | 확정 — 조건: 이름+설명 주입은 description 있는 스킬만, 1088개는 현행 스니펫 유지 (RV-12) |
| P-13 | 확장 기준 버전 | `extends: skill_id@version`, 설치기 어긋남 알림 | skill-layers 2절, copy-install 5절 | 확정 (RV-13) |
| P-14 | 사례 나열 판단 항목 | 우주 판단 기준에 "형태 규칙인가 시나리오 목록인가" 추가 | skill-layers 5절 | 확정 — 조건: 승격 심사에만, 기존 스킬 삭제·재분류 금지(L-01) (RV-14) |
| P-15 | 봉투 공개 전제 | 공장 PUBLIC 확인, 일반화 · 게이트 필수, 사내 소우주는 사람 재검토 | skill-proposal-delivery 3절 | 확정 — 조건: 배달은 사람 명령으로만, 자동 배달 없음 (RV-15) |
| P-16 | `remote_url` 보호 | 설치기만 쓰고 변조 감지 대상, 배달 스크립트 주소 인자 없음 | skill-proposal-delivery 5절 | 확정 (RV-16) |
| P-17 | 은퇴 → 복직 | 소프트 상태, 사람 승인으로 복귀, id · 기억 · 이력 유지 | creation-and-organization 4절 | 확정 (RV-17) |

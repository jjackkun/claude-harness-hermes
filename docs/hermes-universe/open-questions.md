# 남은 주제와 미확인 항목 — 헤르메스 우주 설계

> 작성일: 2026-09-15
> 목적: 아직 논의하지 않은 주제와, 설계는 정했지만 사실 확인·실측이 필요한 항목을 모아 구현 계획 전에 닫는다.

## 개요

- **1절**은 사용자와 이어서 논의하기로 한 큰 주제다.
- **2절**은 설계 문서가 전제로 삼았지만 아직 확인하지 않은 사실이다. 구현 계획을 쓰기 전에 닫아야 한다.
- **3절**은 설계 안에서 세부가 비어 있는 항목이다.

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
| V-4 | Claude Code 훅 입력에 하위 에이전트 종류·id가 넘어오는가 | 대화형 세션에서 기계가 `agent:` 행위자를 찍을 수 있는지 | Claude Code 훅 문서 확인 + SubagentStop 훅 입력 덤프 |
| V-5 | 복사 설치 시 스킬을 하위 폴더로 나눠도 로딩되는가 | 공통 스킬과 소우주 자체 스킬을 폴더로 구분할 수 있는지 | Claude Code 스킬 로딩 규칙 확인 |
| V-6 | age CLI와 pyrage 중 무엇을 쓸 것인가 | 현재 둘 다 미설치, Python 3.10.12. 설치는 사용자가 WSL에서 직접 | 구현 계획에서 결정 |

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

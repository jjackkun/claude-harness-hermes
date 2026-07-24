# Hermes Part C — 계층형 지식 그물망 상세 설계

> 작성일: 2026-07-24
> 목적: 프로젝트에서 태어난 일반 지식(스킬)을 여러 컴퓨터가 공유하는 전용 그물망 저장소로 안전하게 승격·소비하는 파이프라인을 확정한다.
> 상위 스펙: [2026-07-15-hermes-knowledge-portability-design.md](./2026-07-15-hermes-knowledge-portability-design.md) Part C 를 구현 가능한 수준으로 구체화한다.

## 개요

Part A/B/D 와 export 레이어는 이미 main 에 병합됐다. Part C 는 마지막 조각으로, **프로젝트 로컬 지식 중 일반적인 것만** 전용 그물망 git 저장소로 끌어올려 사용자의 여러 컴퓨터가 공유하게 한다.

이 문서는 상위 스펙의 Part C 를 구현 착수 가능한 수준으로 구체화하며, 그 과정에서 **상위 스펙의 전제 하나를 정정**한다(발견 1). 본 문서가 Part C 에 대해 상위 스펙보다 우선한다.

## 상위 스펙 대비 정정 (구현 착수 전 코드 검증 결과)

### 발견 1 — `harness_rules` 는 지식이 아니라 포인터 로그다 (전제 정정)

상위 스펙은 "`harness_rules` 157행이 그물망의 살아있는 씨앗이며 Hermes 주입/회상이 소비한다"고 봤다. 코드·실데이터 검증 결과:

- `harness_rules.instruction` 은 `[project] 결정화 스킬: /abs/path/to/skill.md` 형태의 **기계-로컬 절대경로 포인터**다(현재 293행, 전부 이 형태). 지식 본문이 아니다.
- `harness_rules` 를 읽는 곳은 `hermes-init.py`(스키마)·`hermes-status`(COUNT 표시)뿐이다. **주입/회상 파이프라인은 `harness_rules` 를 소비하지 않는다.** 실제 주입은 `skill_index` → 스킬 `.md` 파일 경로다.

따라서 "`harness_rules` 통과분 → `rules/*.md`" 는 무의미한 절대경로를 export 하게 된다. **진짜 이식 가능한 지식 단위는 스킬 `.md` 본문**이다.

### 발견 2 — `harness_rules.scope` 컬럼은 이미 존재한다

`scope TEXT DEFAULT 'local'` 이 이미 스키마에 있고 293행 전부 `'local'` 이다. 승격 표식을 걸 자리가 준비돼 있다.

### 발견 3 — 주입은 "스킬 디렉토리 한 개"를 스캔한다

`UserPromptSubmit` 훅이 `hermes-search.py --db <프로젝트 state.db> --skills-dir "$PWD/.claude/skills"` 를 호출한다. 검색 풀 = 프로젝트 `skill_index`(FTS) + 단일 `--skills-dir` 파일 스캔. 그물망 스킬을 주입에 태우려면 **주입 훅이 그물망 스킬 폴더를 두 번째 소스로 추가**하면 된다 — 소비 측 변경이 아주 작다.

## 확정 결정 요약

| # | 결정 |
|---|---|
| 1 | 승격 단위 = **스킬 `.md` 본문**. 소비 = 기존 injection 재사용. `harness_rules.scope` 는 "어느 스킬이 global 인가" 색인으로 강등 |
| 2 | 그물망 = **새 전용 private git 저장소**. 각 기기 `~/.hermes/mesh/` 로 pull |
| 3 | 원격 모델 = **"URL 전역·인증 기기별"**. 최초 등록 절차는 **안내만**(자동 생성·자동 인증 안 함). 미등록 기기엔 **비차단 알림 1회** |
| 4 | 등록 불가 폴백 = **아웃박스 릴레이**. 위치 = 하네스 repo 최상위 `mesh-outbox/` |
| 5 | 소비 측 = `~/.hermes/mesh/skills/` 를 주입 **2차 스킬 소스**로 추가 |
| 6 | 승격 게이트 = **별도 동기화 패스**에서 실행(결정화 인라인 아님). 2단계(사전 필터 + LLM) + fail-closed 허용리스트 + 최종 redact 스크럽 |
| 7 | 엔진 = throttle 된 SessionStart 배치 패스 `hermes-mesh-sync`. 멱등 upsert, `promotion_log` 거부 기억 |

## 아키텍처

### 데이터 흐름 (전체)

```text
[생산 기기]
  결정화 → .hermes/skills/*.md (프로젝트 로컬, Part A/export 영역)
    → hermes-mesh-sync 패스:
        게이트 통과분만 →
          (등록됨) ~/.hermes/mesh/skills/ 에 upsert → commit → push
          (미등록) 하네스 repo mesh-outbox/ 에 stage → commit → push(프로젝트 sync 편승)

[릴레이]
  등록된 기기의 hermes-mesh-sync 패스가 mesh-outbox/ 의 스테이징 스킬 발견
    → 게이트 재확인 → 그물망에 upsert·push → mesh-outbox/ 에서 삭제·commit

[소비 기기]
  git pull(그물망) → ~/.hermes/mesh/skills/*.md 최신화
    → UserPromptSubmit 주입 훅이 ~/.hermes/mesh/skills 를 2차 소스로 검색
    → 프로젝트 스킬과 함께 주입/회상
```

### 컴포넌트

| 컴포넌트 | 책임 | 신규/변경 |
|---|---|---|
| `scripts/hermes-mesh-sync.py` | 동기화 패스 엔진(pull·gate·push/stage·flush·notify) | 신규 |
| `scripts/hermes_mesh_gate.py` | 2단계 승격 게이트(사전 필터 + LLM 일반성) | 신규 |
| `scripts/hermes_redact.py` | 사전 필터 확장(한국어 직함·사번·절대경로) | 변경 |
| `scripts/hermes-search.py` | 그물망 스킬 폴더를 2차 소스로 검색 | 변경 |
| `assets/hooks/claude-userpromptsubmit-reminders.sh` | 주입 호출에 그물망 스킬 dir 추가 | 변경 |
| `assets/hooks/claude-sessionstart-mesh-sync.sh` | 동기화 패스 throttle 트리거 | 신규 |
| `scripts/hermes-init.py` | `promotion_log` 테이블·`~/.hermes/mesh/` 생성 | 변경 |
| `presets/workflow/hermes.conf` | `HERMES_MESH_REMOTE`·throttle 파라미터 | 변경 |
| `mesh-outbox/` (하네스 repo) | 미등록 기기 스테이징 큐(git 추적, 설치 배포물 제외) | 신규 |

각 컴포넌트는 하나의 책임만 갖고, 게이트(`hermes_mesh_gate.py`)는 엔진(`hermes-mesh-sync.py`)과 분리돼 단독 테스트·재사용 가능하다.

## 승격 게이트 (안전 심장부)

### 원칙 — 허용리스트·비대칭

블록리스트("나쁜 것을 뺀다")가 아니라 **허용리스트("일반적이라 확인된 것만 통과")**다. 근거는 오류의 비대칭:

- **오탐**(일반 지식인데 탈락) = 로컬에만 남음 → 손해 없음, 되돌리기 쉬움.
- **미탐**(PII·프로젝트 종속이 통과) = 그물망 유출 → 치명적, 되돌리기 어려움.

따라서 **애매하면 무조건 탈락(로컬 유지)**. 두 단계 중 하나라도 불확실하거나, LLM 호출이 실패·비활성(`HERMES_DISABLED=1`)이면 승격하지 않는다(fail-closed).

### ① 값싼 사전 필터 (정규식/사전)

`hermes_redact.py` 가 이미 잡는 것: 이메일·전화·주민번호·카드·토큰(GitHub PAT·OpenAI·AWS·Google·Slack·Bearer·KV 시크릿).

**Part C 에서 추가**(하나라도 걸리면 탈락):
- 한국어 직함/호칭: `차장·과장·부장·대리·사원·팀장·실장·이사·상무·전무·대표·님·씨` 등. (범위는 구현 시 사전으로 관리·갱신 가능)
- 사번 패턴(사내 형식).
- **절대경로**: `/home/…`, `/Users/…`, `C:\…` — 기계-로컬이라 그물망에서 무의미하며 준-민감.

공격적으로 잡는다. "대리"가 "위임"의 뜻인 오탐도 감수한다(fail-closed 와 일치).

### ② LLM 일반성 분류

사전 필터 통과분에 대해 "이 지식이 **특정 개인·프로젝트에 종속되는가**"를 판정. 일반적인 것만 통과. 테스트에서는 mock claude 바이너리를 쓰고 실제 claude 를 호출하지 않는다. `HERMES_DISABLED=1` 이면 스킵 → 보수적으로 탈락.

현재 293개 스킬은 대부분 프로젝트 한정이므로 **초기 통과율은 매우 낮다 — 정상**이다. 그물망은 작게 시작해 천천히 자란다(양보다 질).

### 안전장치 — 최종 redact 스크럽

게이트를 통과한 본문도 아웃박스/그물망에 쓰기 **직전에 `redact()` 를 한 번 더** 통과시킨다. 사전 필터가 놓친 시크릿이 있으면 마스킹한다. (통과=reject 결정용, redact=마지막 belt-and-suspenders. 상위 스펙 H1 잔여위험 대응.)

### 게이트 위치 — 결정화 인라인이 아니라 별도 패스

"프로젝트 스킬로 만들 가치가 있나(결정화)"와 "프로젝트 밖으로 내보낼 자격이 있나(승격)"는 다른 질문이다. 게이트를 별도 패스에 두면:
- 결정화 Stop 훅 레이턴시 경로에서 게이트 LLM 비용을 빼낸다.
- 이미 쌓인 스킬을 **백필**·재평가할 수 있다(게이트 규칙 개선 시 소급).
- 게이트·아웃박스 flush·그물망 push 가 하나의 동기화 패스로 묶여 Part D 와 대칭을 이룬다.

## 동기화 패스 엔진 (`hermes-mesh-sync`)

### 트리거

SessionStart 훅(`claude-sessionstart-mesh-sync.sh`)에서 throttle. 기본 **24시간**(`HERMES_MESH_SYNC_HOURS`, 파라미터화). `setsid` 백그라운드로 세션 비차단. Part D·dream 의 throttle 훅과 동일 규약(`set -uo pipefail`, stdout 침묵, 진단은 `.hermes/hooks.log`, 모든 경로 `exit 0`).

### 등록 상태 판정

| 상태 | 조건 | 동작 |
|---|---|---|
| 그물망 미사용 | `HERMES_MESH_REMOTE` 미설정 | 순수 로컬. 아웃박스·알림 없음 |
| 등록됨 | REMOTE 설정 + `git ls-remote` 성공 | 직접 push 경로 |
| 미등록 기기 | REMOTE 설정 + `git ls-remote` 실패(인증X) | 아웃박스 폴백 + 등록 안내 1회 |

`HERMES_MESH_REMOTE` 는 `hermes.conf` 에 있으므로 하네스 repo 동기화를 타고 전 기기에 전파된다 → **URL 은 전역, 인증만 기기별**.

### 전 과정

```text
[등록됨 기기]
  1. pull:   git -C ~/.hermes/mesh pull  (소비 측 최신화)
  2. gate:   승격 안 된 로컬 결정화 스킬 → 2단계 게이트
  3. push:   통과분 → ~/.hermes/mesh/skills/ 멱등 upsert(키 기준) → commit → push
             harness_rules.scope 'local'→'global', promotion_log 기록
  4. flush:  mesh-outbox/ 스테이징 스킬 발견 → 게이트 재확인
             → 그물망 upsert·push → mesh-outbox/ 에서 삭제·commit

[미등록 기기]
  1'. gate:  동일 2단계 게이트
  2'. stage: 통과분 → mesh-outbox/ 저장 → commit·push(프로젝트/하네스 sync 편승)
  3'. notify: 등록 절차 안내 1회(마커 파일로 재알림 억제), 비차단
```

### 멱등·경쟁 안전

- 3·4 단계 그물망 쓰기는 전부 **스킬 키 기준 upsert** → 두 등록 기기가 같은 아웃박스를 동시 flush 해도 중복이 덮어쓰기로 흡수.
- 아웃박스 삭제는 "삭제+삭제" git 머지로 깨끗.
- **거부 기억**: `promotion_log(skill_key, content_hash, gate_version, decision, reason, ts)`. `(키, 내용 해시, gate_version)` 기준으로 판정을 캐시 → **내용이 바뀌거나 gate_version 이 오르면만 재평가**. 매 패스 LLM 재호출 낭비 방지 + 규칙 개선 시 소급 가능.

## 등록 모델·절차 (사용자 안내)

### 최초 활성화 (REMOTE 가 아직 어디에도 없음)

하네스가 절차를 출력(안내만):
1. private repo 1개 생성(사용자가 직접, GitHub 등).
2. `hermes.conf` 의 `HERMES_MESH_REMOTE` 에 URL 기입.
3. 이 기기 git 인증 확인(SSH 키/gh/PAT — WSL·CLAUDE.md 원칙상 사용자 몫).
4. 다음 동기화 패스가 빈 repo 에 뼈대(`skills/`·README·`.gitignore`) 써서 초기화·push.

이후 이 config 가 동기화되며 **다른 기기는 1·2 단계를 건너뛴다**.

### N번째 기기 (REMOTE 는 동기화됨, 인증 없음)

하네스 알림(1회):
> 그물망 원격(X)은 설정돼 있으나 이 기기에서 닿지 못함(인증). 이 기기를 등록하려면 [X 에 대한 SSH 키/gh 로그인/PAT 설정]. 그 전까지 승격 지식은 `mesh-outbox/` 에 쌓여, 등록된 기기가 나중에 반영함.

## 소비 측 (다른 컴퓨터에서 되살아나기)

- 그물망은 각 기기 `~/.hermes/mesh/` 로 pull, 스킬은 `~/.hermes/mesh/skills/*.md`.
- 주입 훅이 `hermes-search.py` 호출 시 `~/.hermes/mesh/skills` 를 **2차 스킬 소스**로 전달(`--skills-dir` 반복 허용 또는 `--global-skills-dir` 추가).
- 검색 풀 = 프로젝트 `skill_index`(FTS) + 프로젝트 `.claude/skills` + **그물망 스킬**. 그물망은 큐레이트된 소량이라 파일 스캔 매칭으로 충분.
- global.db 재색인은 "어느 스킬이 global 인가" 장부·FTS 가속용으로 선택적이며 주입 자체엔 필수 아님.

## SQLite·저장소 처분 (상위 스펙 방침과 정합)

| 대상 | 원본(권위) | 이식 | 비고 |
|---|---|:---:|---|
| 그물망 스킬 `.md` | 그물망 private repo `skills/*.md` | ✅ | 게이트 통과분만 |
| `mesh-outbox/*.md` | 하네스 repo(임시 큐) | ✅ | 삭제되는 운송용, 게이트 통과분만 |
| `promotion_log` | 로컬 전용(global.db) | ❌ | 재생성 가능한 판정 캐시 |
| `harness_rules.scope` | 로컬 전용(global.db) | ❌ | global 색인 표식 |

## 에러 처리·경계

- 동기화 패스는 훅 규약대로 모든 경로 `exit 0`, 진단은 `.hermes/hooks.log`.
- `git pull/push` 실패(오프라인·충돌) → 로컬 상태 유지, 다음 패스 재시도(멱등).
- LLM 실패·비활성 → 게이트 fail-closed(탈락), 순수 로컬 계속 동작.
- 그물망 repo 는 상위 스펙 L2 대로 **squash·prune·force-push 금지**(압축 전 원문 복구 보장 전제).

## 테스트 전략

- **게이트 단위 테스트**: 사전 필터 각 패턴(한국어 직함·사번·절대경로·기존 시크릿) RED→GREEN, fail-closed(LLM 비활성 시 탈락), 최종 redact 스크럽.
- **엔진 테스트**: mock claude, `HERMES_DISABLED=1` 경로, 멱등 upsert(중복 flush), 아웃박스 삭제 머지.
- **2-기기 릴레이 시뮬레이션**: 미등록 기기 stage → 등록 기기 flush → 그물망 반영 → 아웃박스 비움, 을 임시 git repo 쌍으로 out-of-harness 재현.
- **소비 측 테스트**: 그물망 스킬 dir 이 주입 결과에 포함되는지.
- 기존 규약 준수: 실제 claude 미호출, 훅 stdout 침묵, `run-all.sh` 에 신규 테스트 등록.

## 구현 단계 (writing-plans 에서 상세화)

의존 순서상 대략:
1. 소비 측 + 그물망 골격(`~/.hermes/mesh/` pull·주입 2차 소스·재색인).
2. 게이트(`hermes_mesh_gate.py` + `hermes_redact.py` 확장).
3. 동기화 엔진(`hermes-mesh-sync.py` + `promotion_log`) + 아웃박스 릴레이 + 등록 판정·알림.
4. 설치/업데이트 배선(`hermes-init.py`·`hermes.conf`·SessionStart 훅) + 테스트.

## 비목표 (Out of Scope)

- 팀 전체 공유 그물망(거버넌스·머지·승인) — 미래 확장. 지금 구조가 확장 경로를 막지 않는다.
- 원격 자동 생성(gh repo create)·자동 인증 — WSL·CLAUDE.md 원칙상 안내만.
- global.db FTS 로의 그물망 스킬 재색인 강제화 — 선택적 최적화로 남긴다.

## 미결 항목 (구현 시 확정)

- 한국어 직함/호칭 사전의 구체 범위·사번 정규식.
- LLM 일반성 분류 프롬프트의 정확한 문구·판정 스키마.
- throttle 기본값(24h) 실사용 튜닝.
- 등록 알림 재고지 주기(1회 vs 긴 주기).

## 개정 이력

- **2026-07-24 (초안)**: 상위 스펙 Part C 를 코드 검증 기반으로 구체화. 전제 정정(harness_rules=포인터), 승격 단위=스킬 .md, 별도 동기화 패스, 아웃박스 릴레이, "URL 전역·인증 기기별" 등록 모델 확정.

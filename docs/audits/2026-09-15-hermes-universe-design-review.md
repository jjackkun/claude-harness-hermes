# 헤르메스 우주 설계 문서 리뷰 — 빈틈과 cumora 교훈 반영

> 작성일: 2026-09-15
> 대상: `docs/hermes-universe/` 17개 문서 (2,118줄) 전부
> 비교 대상: `/home/jjackkun/PROJECT/cumora` (v0.11.1, 커밋 `65625b0`) — `docs/COORDINATION.md`, `docs/BYOA.md`, `SECURITY.md`, `server/src/agents/{memory-scope,memory-write,skills,personas,seen-boundary,convene}.ts`, `server/src/api/router.ts`(오프보딩·복직), `server/src/db/migrate.ts`
> 상태: **판정 완료.** 사용자가 "올바르고, 정상 동작하며, zeroday-frontend 에 문제를 주지 않는 방향" 으로 판정을 위임했고, 17건 전부 확정(위임) — [decision-log.md](../hermes-universe/decision-log.md) 12절 RV-01~RV-17. 설계 문서에는 `✅ 리뷰 확정 (2026-09-15, RV-xx)` 표시로 있다.

## 개요

설계 문서는 결정의 출처와 뒤집힌 이력이 정확하고, 실측 근거가 붙어 있다. 리뷰에서 찾은 것은 결정의 오류가 아니라 **결정과 결정 사이의 이음새가 비어 있는 곳** 12건과, cumora 가 운영 사고로 배운 뒤 코드로 굳힌 교훈 중 우리 설계에 그대로 옮겨 적을 만한 것 9건이다.

## 1. 설계 문서 안의 빈틈 (내부 정합성)

| # | 빈틈 | 왜 문제인가 | 보강한 문서 |
|---|---|---|---|
| R-1 | `refs/hermes/sync` 를 두 컴퓨터가 동시에 push 하면 **참조 갱신이 non-fast-forward 로 거부**된다 | 문서는 "파일이 겹치지 않아 충돌 없음"만 적었다. 파일 단위 합집합은 맞지만 git 참조는 하나이므로 두 번째 push 가 거부된다. 처리 규칙이 없으면 한쪽 컴퓨터의 조각이 영영 안 올라간다 | [sync-transport.md](../hermes-universe/design/protection/sync-transport.md) §4 |
| R-2 | 새 컴퓨터가 과거 조각을 읽으려면 "기존 컴퓨터가 다시 잠가 줘야" 한다고 했는데, 그것은 **과거 조각 전부를 재암호화해 다시 올리는 일**이다 | 컴퓨터를 추가할 때마다 저장소가 조각 수만큼 불어난다. age 형식은 파일 열쇠를 수신자마다 감싸므로 열쇠 계층(마스터 열쇠 감싸기)으로 피할 수 있다 | [encryption-keys.md](../hermes-universe/design/protection/encryption-keys.md) §2 |
| R-3 | 열쇠 파일 이름의 `<컴퓨터 id>` 가 정의되지 않았다 | hostname 은 겹친다(cumora 미확인 항목과 같은 문제). 자물쇠 지문이 곧 컴퓨터 id 가 되면 별도 등록부가 필요 없다 | encryption-keys.md §2 |
| R-4 | 열쇠 차단 훅(T-11)은 Claude Code 훅이다. **Codex 세션에서는 훅이 돌지 않는다**(CLAUDE.md 명시) | 세션 밖 규칙이 Codex 에서는 사람 규율로만 남는다. 한계를 적어야 "훅으로 차단" 이 과신되지 않는다 | encryption-keys.md §4 |
| R-5 | `HERMES_AGENT_ID` 환경변수로 행위자를 찍는데, 세션 안 에이전트가 `claude -p` 를 띄우며 **남의 id 를 넣을 수 있다** | 명부 검사는 "없는 id" 만 막는다. 등록된 남의 id 사칭은 못 막는다. cumora 는 신원을 요청 본문이 아닌 서명 토큰에서만 읽는다 | [identity.md](../hermes-universe/design/agent/identity.md) §7 |
| R-6 | 헤드리스 루프·cron 실행의 `requested_by` 가 정해지지 않았다 | 사람이 없는 세션은 C-05 로 `main` 이 수행한다고만 했다. 지시자 칸이 비면 "누가 시켰는가" 그래프가 끊긴다 | identity.md §4 |
| R-7 | 인계 후 받는 쪽이 **응답하지 않을 때**(헤드리스 죽음, 열쇠 없음, 사람 부재)의 처리가 없다 | `constraints` 에 기한을 적을 수 있지만 만료 시 무엇이 일어나는지 없다. 누락 감지(§8)는 세션 종료 시점만 본다 | [handoff-contract.md](../hermes-universe/design/agent/handoff-contract.md) §3 |
| R-8 | "지시는 거절 불가" 가 규칙 위반 지시(비밀값 출력, `--no-verify`)와 부딪힌다 | 막힘(blocked)으로 되돌리면 되지만 명시가 없다. 결정 원장 §1 의 "멈추는 네 경우" 와 이어야 한다 | handoff-contract.md §1 |
| R-9 | `verified: none`(검증 수단 없음)을 **에이전트가 고를 수 있으면** 검증 층이 무력화된다 | 기계 칸이라고 적혀 있지만, 언제 `none` 이 되는지 규칙이 없다. cumora 의 "우회 플래그는 서버가 보여 준 상태의 확인이어야" 교훈이 그대로 적용된다 | [work-journal.md](../hermes-universe/design/agent/work-journal.md) §3 |
| R-10 | 공장 수정을 `update-all` 로 받을 때 **소우주의 "확장 + 차이" 파일이 새 기준 버전과 어긋날 수 있다** | 확장 파일이 기준 `skill_id@version` 을 적지 않으면 어긋남을 기계가 모른다 | [copy-install.md](../hermes-universe/design/world/copy-install.md) §5, [skill-layers.md](../hermes-universe/design/world/skill-layers.md) §2 |
| R-11 | 4층 스킬의 저장 위치(`.hermes/agents/<id>/skills/` 등)는 Claude Code 가 읽는 자리가 아니다 | 층별 스킬은 헤르메스 주입 경로(`hermes-search.py`)로 읽힌다는 것과, 주입이 소환된 에이전트의 (universe, unit, agent) 로 걸러져야 한다는 것을 적어야 한다 | skill-layers.md §1 |
| R-12 | 공장 GitHub 저장소가 **PUBLIC** 임을 실측(`gh repo view` → `visibility: PUBLIC`) | 봉투에 이름을 넣지 않는 결정의 전제가 확인됐다. 동시에 **봉투의 스킬 본문 자체가 공개 게시물**이 된다. 일반화·게이트가 "권장" 이 아니라 "필수" 다 | [skill-proposal-delivery.md](../hermes-universe/design/world/skill-proposal-delivery.md) §3, open-questions V-7 |

작은 불일치: README 확정표의 "정체성 … 확정" 은 decision-log A-09 가 **합의** 다. README 쪽을 고쳤다.

## 2. cumora 에서 옮겨 적은 교훈

cumora 는 에이전트 여럿이 한 채팅방에서 충돌 없이 일하게 하려고 넉 달간 운영 사고를 겪고 그때마다 코드 장치를 넣었다. 채팅 조정 장치(HOLD, 시퀀스 커서, 트리아지)는 우리와 문제가 다르다. 옮길 것은 **장치가 아니라 장치를 만들게 한 원리** 다.

| # | cumora 교훈 | 출처 | 우리 설계에 넣은 자리 |
|---|---|---|---|
| K-1 | **우회 플래그는 서버가 보여 준 상태의 확인이어야 한다.** `--send-anyway` 를 공짜로 두자 에이전트가 선제적으로 붙여 게이트가 사라졌다. 고친 방법은 "책임감 있게 쓰라" 는 프롬프트가 아니라 HOLD 를 실제로 본 뒤에만 유효한 1회성 토큰 | `COORDINATION.md` §5d, "Don't ship an override flag without a cost" | work-journal §3 (`verified: none` 은 기계만 찍음), handoff §3 (되묻기 남용 방지) |
| K-2 | **기억 파일은 상태다 — 잘못된 교훈을 굳혀 안전망을 스스로 무력화한다.** 한 에이전트가 "정체된 사슬에는 침묵하라" 는 기억을 새로 써서 방금 만든 안전망을 무시하도록 미래의 자신을 훈련했다 | `COORDINATION.md` T6, "Memory files are state too" | memory-events §4 (규칙과 충돌하는 기억은 충돌 표시), G-25 와 연결 |
| K-3 | **결석한 구성원은 고칠 대상이 아니라 정상 조건이다.** "올리비아를 살리자" 가 아니라 "누가 없어도 팀이 끝낸다" 가 답이었다 | `COORDINATION.md` "Don't treat absent members as a failure mode" | handoff §3 (기한 만료 → 대체 수행 + 기록) |
| K-4 | **시나리오 나열을 프롬프트에 쌓지 않는다.** 형태 수준(shape-level) 규칙 다섯 개가, 사례를 붙일 때마다 나빠지던 프롬프트를 이겼다 | `COORDINATION.md` "Don't accrete scenario examples" | skill-layers §5 (우주 판단 항목에 "사례 나열인가 형태 규칙인가" 추가) — zeroday 의 `agg_xxx.md` 류 결정화 잡음과 같은 형태 |
| K-5 | **스킬은 이름+설명만 프롬프트에 넣고 본문은 필요할 때 읽는다**(진행적 공개, 스킬당 ~100 토큰) | `server/src/agents/skills.ts` 머리 주석 | skill-layers §1 (현재 `read_skill_snippet` 10줄 주입의 다음 단계로 제안) |
| K-6 | **신원은 요청 본문이 아니라 서명된 토큰에서 고정한다.** 모델 프로세스는 토큰도 서버 주소도 받지 않는다 | `SECURITY.md` "The trust model", `BYOA.md` "Authentication is shared; tool authority is not" | identity §7 (소환은 러너가, id 는 러너가 찍음) |
| K-7 | **에이전트가 목적지 URL 을 고르지 못한다.** 스킬 허브 주소는 운영자 설정이고 에이전트는 경로 조각만 준다 | `skills.ts` `resolveSkillHub…` 주석 | skill-proposal-delivery §5 (`factory.json.remote_url` 은 설치기만 쓰고 훅으로 보호) |
| K-8 | **오프보딩은 소프트 삭제, 복직하면 기억·이력이 그대로 돌아온다** | `router.ts` `DELETE /agents/:id`, `POST /agents/:id/rehire` | creation-and-organization §4 (은퇴 → 복직 경로 제안) |
| K-9 | **실행 단위(run)마다 heartbeat 와 비용 원장을 남긴다.** 긴 작업이 살아 있음을 보이고, 클라우드·로컬 모두 같은 `llm_calls` 원장에 적는다 | `BYOA.md` "Observability", `migrate.ts` `agent_runs`·`llm_calls` | work-journal §2 (`step` 을 heartbeat 로), §4 `usage` 기계 칸 제안 — 백로그 `platform-cost-performance-levers` 와 연결 |

### cumora 와 우리가 이미 같은 결론에 있는 것 (변경 없음)

| 논점 | cumora | 우리 |
|---|---|---|
| 기억을 옛 기록에서 추측해 재배치하지 않는다 | `memory-scope.ts`: "never migrates old memories into a project — that would be fake isolation" | L-01·L-02 |
| 애매하면 추측 귀속 금지 | 프로젝트가 둘 이상이면 전역(null)으로 | 우리는 저장소 하나 = 소우주라 애매함 자체가 없다 |
| 정체성(pinned)과 배운 사실을 나눈다 | pinned/persona/skills 는 전역, 작업 사실은 프로젝트 | SOUL.md ↔ 기억 이벤트 (D-01) |
| 1 에이전트 = 1 테넌트 | 복합 PK 버그 후 전역 유일 id 로 회귀 (`migrate.ts:2123` 부분 유일 인덱스) | H-09 |
| 상태와 직급 분리 | `status` 는 presence(`avail`/`resting`), 직급은 페르소나 | C-10 |

### cumora 에서 옮기지 않은 것

- 채팅 시퀀스 커서·HOLD·트리아지·세마포어·페이서: 채팅방 동시 발화 문제이지 우리 작업 단위 인계 문제가 아니다.
- 기억의 전역/프로젝트 두 스코프: 우리는 소우주 하나가 곧 경계라 필요 없다(H-08 폐기와 일치).
- climate(에이전트 간 호감도): 우리 설계 범위 밖.

## 3. 근거 문서 수정

- `evidence/existing-tools-research.md` §6 의 경로 `/home/jjackkun/PROJECT/cumora-main/cumora-main` → `/home/jjackkun/PROJECT/cumora` (옛 경로는 존재하지 않음).
- 줄 번호 갱신: `migrate.ts:2076-2093` → `:2123`(부분 유일 인덱스), `registry.ts:428-444` → `:232, :514`(2h TTL), `daemon.ts:640-693` → `:663-673`(페어링 안내).

## 4. 검증

- 문서 안 상대 링크 전부 존재 확인 (아래 명령).
- 새로 넣은 절은 모두 `✅ 리뷰 확정 (2026-09-15, RV-xx)` 표시를 달아 원래 결정과 구분된다. zeroday 를 위한 제약이 붙은 것: RV-06(러너 허용 목록) · RV-08(기본 시간 없음) · RV-12(1088개 스니펫 유지) · RV-14(기존 스킬 무변경) · RV-15(사람 명령 배달만).

```bash
cd docs/hermes-universe && python3 - <<'EOF'
import re, os, glob
bad = 0
for f in glob.glob('**/*.md', recursive=True):
    for m in re.finditer(r'\]\(([^)\s]+?\.md)(?:#[^)]*)?\)', open(f, encoding='utf-8').read()):
        if not os.path.exists(os.path.join(os.path.dirname(f), m.group(1))): bad += 1; print('BROKEN', f, m.group(1))
print('broken:', bad)
EOF
```

### 6. architect-lite 리뷰 (2026-09-15, 보강 직후)

| 심각도 | 발견 | 처리 |
|---|---|---|
| 차단 | handoff-contract.md §6 이 RV-03 이전 절차("기존 조각을 다시 잠금")를 안내 | §6 표 · 안내문을 마스터 열쇠 재감싸기로 고침 |
| 주의 | sync-transport.md §4 "`git merge` 는 못 쓴다" 는 과장 — merge 는 커밋에 동작 | `merge-tree --write-tree`(2.38+) → 임시 worktree merge → mktree 순으로 바로잡음. 이 컴퓨터 git 2.25.1 |
| 주의 | RV-06 허용 목록을 훅이 판정하는 방법 공백 — 명령줄 흉내로 뚫림 | identity.md §7 에 러너 발급 1회용 소환 토큰(`summons` nonce) 절차 추가 |
| 사소 | 이 문서 §4 의 링크 검증 명령이 목록만 뽑고 존재 대조를 안 함 | 실제 대조 스크립트로 교체 |
| 이상 없음 | RV-03↔T-09/T-12, RV-06↔C-01/C-14, RV-15↔P-03/P-04 모순 없음 · age 감싸기 구현 가능 · zeroday 보호 5건 적절 · R-번호↔RV 표시 1:1 | — |

## 5. 다음 행동

실측 V-1~V-6, V-8 을 닫고 실행 계획을 쓴다. 첫 계획은 G-24 에 따라 복사 설치 전환(zeroday-frontend 링크 41개 → 복사본).

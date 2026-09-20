# 운반 — 소우주 원격의 refs/hermes/sync

> 작성일: 2026-09-15
> 목적: 작업 이력과 암호화된 원문을 여러 컴퓨터 사이에서 옮기는 경로·시점·정책을 정한다.

## 개요

운반은 **그 소우주 자신의 원격**에서, 코드 브랜치와 분리된 전용 참조 `refs/hermes/sync` 하나로만 한다.
기본은 로컬 전용이고, 사람이 켠 소우주만 올린다. 원문은 턴 단위 암호 조각으로, 작업 이력은 이벤트 단위
파일로 추가만 한다.

## 1. 무엇을 옮기나 (합의, T-07 · RV-03)

> ⚠️ **2026-09-20 개정 (T-17 · T-18 · T-21)** — 기본 운반 대상은 발전 재료(요약 `summary/` · 패턴 수 · 기억 `memory/` · 작업 이력 `journal/`)이고 **비공개 저장소는 평문**이다.
> 대화 원문 `history/` 와 암호화·열쇠(`keys/`)는 공개 저장소에서 원문까지 올리려는 사람의 **옵션**이다. 아래 표는 그 옵션(잠금 모드)의 배치다.
> 근거: `docs/audits/2026-09-20-transport-keys-rethink.md`. 구현 계획: `docs/exec-plans/active/2026-09-20-transport-plain.md`.
```text
refs/hermes/sync   (그 소우주 원격, 코드 브랜치와 무관)
 ├─ keys/<사람 id>/master.<자물쇠 지문>.age     마스터 열쇠를 각 자물쇠로 감싼 것 (RV-03)
 ├─ keys/<사람 id>/<자물쇠 지문>.pub            자물쇠 (공개) — 이 목록이 곧 컴퓨터 목록 (G-3 닫힘)
 ├─ history/<session_id>/<순번>.enc             대화 원문 턴 조각 (마스터 자물쇠로 통째 암호문)
 ├─ history/<session_id>/<순번>.superseded      압축 표시 파일 — 원 조각은 그대로 (7절 G-1)
 ├─ journal/<YYYY>/<MM>/<DD>/<event_id>.json    작업 이력 (기계 칸 평문, 자유 글 칸 3개 암호문)
 └─ memory/<agent_id>/<memory_id>.json          기억 이벤트 ([memory-events.md](../agent/memory-events.md), 경로 예약)
```

- 처음에는 작업 이력용 `hermes/journal` 브랜치를 따로 두려 했으나, 올리기·받기 경로가 같아 하나로 합쳤다.
- 네 종류(`keys/` · `history/` · `journal/` · `memory/`) 모두 **추가만** 한다. 지우는 길은 `tombstone` 하나다(4절).
- **브랜치가 아닌 전용 참조**를 쓰는 이유: 기본 `git fetch`(`refs/heads/*`)에도, 브랜치 목록에도 나타나지 않는다. 함께 쓰는 저장소에서 동료의 브랜치 목록과 fetch 크기에 끼어들지 않는다.
- 선례: Entire CLI가 `refs/entire/checkpoints/...` 사용자 정의 참조로 에이전트 세션을 저장한다(조사 결과).

## 2. 소우주별 적용 (2026-09-15 실측)

| 소우주 | 원격 | 커밋 작성자 | 이식 |
|---|---|---|---|
| terminal-shipping | `gitlab.com/jjackkun/terminal-shipping` (개인 GitLab) | jjackkun 1명 | 필요 — 여러 컴퓨터 사용 |
| zeroday-frontend | `211.206.116.39:3000/zeroday/zeroday-frontend` (사내 서버) | jjackkun 외 3명(choijh15, ahnjunwoo, kimjk2), 원격 브랜치 17개 | 필요 — 여러 컴퓨터 사용 |

- 두 소우주 모두 **자기 원격 밖으로 나가지 않는다.** zeroday-frontend는 사내 서버에만 머문다.
- 동료는 암호문 내용을 읽을 수 없고, 사람별 자물쇠라 동료가 헤르메스를 써도 서로의 원문을 풀 수 없다([encryption-keys.md](encryption-keys.md)).

## 3. push 정책

| 정책 | 내용 | 상태 |
|---|---|---|
| **C. 로컬 전용** | 올리지 않는다 | **기본값** (확정) |
| **B. 소우주별 1회 허락** | 한 번 허락하면 세션 종료 때 게이트를 통과한 것을 자동으로 올린다 | 켤 때 (확정) |
| A. 매번 확인 | 세션마다 묻는다 | 채택 안 함 — 헤드리스·백그라운드에서 물을 사람이 없어 쌓이기만 한다 |
| D. 별도 비공개 원격 | 코드 원격이 아닌 다른 저장소로 올린다 | **폐기** — 원문이 다른 주소로 나가 경계 위반 |

허락 기록 — `<소우주>/.hermes/sync.json` (확정):

```json
{"push": true, "remote": "origin", "ref": "refs/hermes/sync", "approved_by": "human:jjackkun", "approved_at": "<날짜>"}
```

- **컴퓨터 로컬 파일이다. 커밋하지 않는다**(`.hermes/*` 무시 규칙 그대로, 예외 없음). 커밋하면 zeroday-frontend 동료의 clone 이 `push: true` 를 물려받아 열쇠 없는 컴퓨터가 매 세션 "보류" 를 찍는다. 사람마다 자기 컴퓨터에서 켠다 — 손해는 컴퓨터마다 한 번씩 켜야 한다는 것(절차 `docs/hermes-universe/migration/enable-sync.md`).
- 파일이 없으면 **로컬 전용(C)** 이다. 파일을 지우거나 `push`를 `false`로 바꾸면 멈춘다. 켜는 것을 잊으면 다른 컴퓨터에서 백지가 되므로 세션 시작 훅이 "이식 꺼짐" 을 한 줄 알린다.
- **fail-closed:** 보존 전 스캐너가 의심하면 올리지 않고 로컬에 둔다.
- 원격에 올리는 것은 작업 공간 밖으로 나가는 부작용이므로, 켜는 행위는 사람이 한다.

## 4. 올리기·받기 순서

| 단계 | 언제 | 무엇을 |
|---|---|---|
| 기록 | 매 턴 | `state.db`에 저장(마스킹). 그 턴만 암호화해 원문 조각 `history/<session_id>/<순번>.enc` 생성(세션 파일 전량 재작성 아님 — 기존 조각 바이트 불변). 작업 이벤트는 `journal_events`에 INSERT |
| 올리기 | 세션 종료 (Stop 훅 → `hermes-sync.py push`) | 게이트 통과 → 허락 기록 확인 → git 저수준 명령으로 `refs/hermes/sync`에 커밋 → push. 코드 브랜치·작업 트리 변경 0 |
| 받기 | 세션 시작 훅 (`hermes-sync.py pull`) | `git fetch origin refs/hermes/sync:refs/hermes/sync` (기본 refspec 밖이라 명시 필요) → 새 조각만 복호화 → `state.db` 재색인. 열쇠가 없으면 안내문([handoff-contract.md](../agent/handoff-contract.md) 6절)을 내고 push 를 보류한다 |
| 실패 | 오프라인·인증 오류 | 로컬에 남기고 다음 세션에 재시도 |
| `age` 없음 | 두 훅 모두 | **exit 0 + 한 줄 알림**, push·pull 을 건너뛴다. zeroday-frontend 동료 4명 전원이 매 세션 이 경로를 밟으므로 훅이 죽으면 안 된다. `state.db` 변경 0 |

- 사람이 부르는 CLI 는 `hermes-sync.py push · pull · backfill · status · tombstone`. `tombstone`(물리 삭제)은 세션 안에서 차단된다([encryption-keys.md](encryption-keys.md) 4절).
- `state.db` 에 테이블 둘을 더한다: `sync_cursor`(원격에서 받은 조각 id — "새 조각만" 의 기준) · `sync_outbox`(아직 못 올린 조각). `session_history` 는 그대로.

### 참조 갱신 경쟁 — 두 컴퓨터가 같은 참조에 push 할 때

> ✅ 리뷰 확정 (2026-09-15, RV-01) — 근거: [2026-09-15 리뷰](../../../audits/2026-09-15-hermes-universe-design-review.md) R-1

"파일 이름이 겹치지 않아 충돌이 없다" 는 **파일** 이야기다. `refs/hermes/sync` 는 참조 하나라서, 컴퓨터 A 가 올린 뒤 컴퓨터 B 가 옛 커밋 위에 만든 커밋을 push 하면 non-fast-forward 로 거부된다. 규칙이 없으면 B 의 조각은 다음 세션에도 계속 거부된다.

| 단계 | 처리 |
|---|---|
| push 전 | `git fetch origin refs/hermes/sync` 로 원격 최신을 받는다 |
| 원격이 앞서 있으면 | 로컬 sync 커밋과 원격 sync 커밋을 **3-way 병합**해 두 커밋을 부모로 하는 커밋을 만들고 `refs/hermes/sync` 를 그 커밋으로 `update-ref` 한다. 같은 경로가 양쪽에 있으면 내용도 같아야 정상이다(이벤트 id 가 곧 파일 이름). 병합 충돌이 나면 올리지 않고 세션에 알린다 |
| push 거부 | 다시 fetch 부터 반복. 상한(예: 3회) 넘으면 로컬에 두고 다음 세션에 재시도 |
| `--force` | **절대 쓰지 않는다.** 남의 컴퓨터 조각을 지운다 |

- `git merge` 는 브랜치가 아니라 임의의 커밋에 동작한다. 못 쓰는 것이 아니라 **코드 작업 트리를 건드리지 않으려고** 다음 순서로 고른다(2026-09-15 리뷰 후속): ① `git merge-tree --write-tree A B`(git 2.38+, 작업 트리 없이 병합 결과 트리를 냄) → `commit-tree -p A -p B`. ② git 이 낮으면(이 컴퓨터는 2.25.1) 임시 worktree(`git worktree add --detach <tmp> refs/hermes/sync`)에서 `git merge` 하고 결과 커밋으로 `update-ref` 한 뒤 worktree 를 지운다. ③ 둘 다 못 쓰면 `mktree` 로 트리 합집합을 직접 만든다. 세부는 G-27.
- 두 컴퓨터가 같은 세션 id 로 조각을 만들 수는 없으므로(세션 id 는 컴퓨터 안에서 발급) 원문 조각은 겹치지 않는다. 작업 이력·기억 이벤트는 UUIDv7 이라 겹치지 않는다.

### git 저수준 커밋을 쓰는 이유

- 작업 중인 파일과 브랜치를 전혀 건드리지 않는다.
- 코드 브랜치를 지워도 이력이 남는다.
- 주의: git-crypt·transcrypt 같은 필터 방식 암호화는 `git hash-object --stdin` 경로에서 필터가 적용되지 않아 **평문이 올라갈 수 있다.** 그래서 암호화는 커밋 전에 age로 명시적으로 한다.

## 5. 턴 단위 조각인 이유

| 방식 | 문제 |
|---|---|
| 지금: 매 턴 세션 파일 전량 재작성 | 평문이면 git이 차이만 저장하지만, 암호문은 조금만 바뀌어도 전체가 달라져 **매 턴 새 파일처럼 쌓인다** |
| **턴 단위 조각 추가** | 새 턴만 올라간다. 두 컴퓨터가 다른 세션을 써도 파일 이름이 겹치지 않아 충돌이 없다 |

## 6. 서버 호환성

| 서버 | 사용자 정의 참조 push | 근거 |
|---|---|---|
| Gitea | 허용 (소스 확인) | `routers/private/hook_pre_receive.go` default 분기가 쓰기 권한만 검사 |
| Forgejo | 허용 (소스 확인) | 같은 파일 default 분기, 용량 한도 + 쓰기 권한 |
| GitLab | **미확인** — 금지 목록(`refs/environments/`, `refs/keep-around/`, `refs/merge-requests/`, `refs/pipelines/`)에 없어 허용 추정 | Gitaly 문제 해결 문서 |
| zeroday-frontend 사내 서버 | **미확인** — 포트 3000으로 Gitea류 추정 | V-2 |

실측 방법은 [open-questions.md](../../open-questions.md) V-1~V-3. 결과에 따라 소우주마다 셋 중 하나로 간다(확정 — T-07 의 "거부 → 브랜치 회귀" 는 폐기):

| 서버 판정 | 처리 |
|---|---|
| 사용자 정의 참조 허용 | `refs/hermes/sync` 를 쓴다 |
| 거부 + 사람이 폴백 브랜치를 수용 | 브랜치 `hermes/sync`(참조 이름 상수 하나만 바뀜). **동료 브랜치 목록에 보인다** — 혼자 쓰는 소우주에서만 받아들일 만하다 |
| 거부 + 폴백 브랜치도 원치 않음 | **그 소우주는 이식을 켜지 않는다.** 로컬 전용으로 남는다 |

- zeroday-frontend(동료 3명)는 V-2 결과가 "참조 허용" 일 때만 켠다. terminal-shipping(혼자)부터 켠다.
- `hermes-sync.py status` 가 참조 거부를 감지하면 "이식 불가 — 사람 판단" 을 내고 자동으로 브랜치로 넘어가지 않는다.

## 7. 남은 과제

| 과제 | 내용 |
|---|---|
| 압축 충돌 (G-1) — **닫힘** | 현재 압축은 jsonl을 요약본으로 **덮어써** 다른 컴퓨터에 전파한다. 추가 전용 암호 조각에서는 덮어쓸 수 없다. 확정: 압축은 **요약 조각 추가 + 원 조각 옆에 `.superseded` 표시 파일**로 한다. 원 조각 바이트는 불변이고, 재색인이 표시를 보고 요약본을 택한다 |
| 백필 (G-2) — **닫힘** | `hermes-sync.py backfill` 이 그 컴퓨터 `state.db`에 이미 있는 원문을 조각으로 만들어 올린다. **세션당 1회, 멱등** — 두 번 실행해도 조각 수가 같다 |
| 기존 export·reindex 전환 | `hermes-export-history.py` 는 턴 조각 생성으로 축소, `hermes-reindex.py` 는 조각 복호 입력, 세션 시작 재색인 훅은 pull 훅으로 교체(옛 jsonl 경로는 "레거시 읽기 전용" 분기만 남김). 순증 비용은 세션 시작 시 fetch 한 번 |

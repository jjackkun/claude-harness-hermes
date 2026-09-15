# 운반 — 소우주 원격의 refs/hermes/sync

> 작성일: 2026-09-15
> 목적: 작업 이력과 암호화된 원문을 여러 컴퓨터 사이에서 옮기는 경로·시점·정책을 정한다.

## 개요

운반은 **그 소우주 자신의 원격**에서, 코드 브랜치와 분리된 전용 참조 `refs/hermes/sync` 하나로만 한다.
기본은 로컬 전용이고, 사람이 켠 소우주만 올린다. 원문은 턴 단위 암호 조각으로, 작업 이력은 이벤트 단위
파일로 추가만 한다.

## 1. 무엇을 옮기나 (합의)

```text
refs/hermes/sync   (그 소우주 원격, 코드 브랜치와 무관)
 ├─ journal/<YYYY>/<MM>/<DD>/<event_id>.json      작업 이력 (기계 칸 평문, 자유 글 칸 3개 암호문)
 └─ history/<session_id>/<순번>.enc                 대화 원문 (턴 통째 암호문)
```

- 처음에는 작업 이력용 `hermes/journal` 브랜치를 따로 두려 했으나, 올리기·받기 경로가 같아 하나로 합쳤다.
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

허락 기록(안):

```json
{"push": true, "remote": "origin", "ref": "refs/hermes/sync", "approved_by": "human:jjackkun", "approved_at": "<날짜>"}
```

- 파일을 지우거나 `push`를 `false`로 바꾸면 멈춘다.
- **fail-closed:** 보존 전 스캐너가 의심하면 올리지 않고 로컬에 둔다.
- 원격에 올리는 것은 작업 공간 밖으로 나가는 부작용이므로, 켜는 행위는 사람이 한다.

## 4. 올리기·받기 순서

| 단계 | 언제 | 무엇을 |
|---|---|---|
| 기록 | 매 턴 | `state.db`에 저장(마스킹). 그 턴만 암호화해 원문 조각 생성. 작업 이벤트는 `journal_events`에 INSERT |
| 올리기 | 세션 종료 (Stop 훅) | 게이트 통과 → 허락 기록 확인 → git 저수준 명령으로 `refs/hermes/sync`에 커밋 → push |
| 받기 | 세션 시작 훅 | `git fetch origin refs/hermes/sync:refs/hermes/sync` (기본 refspec 밖이라 명시 필요) → 새 조각만 복호화 → `state.db` 재색인 |
| 실패 | 오프라인·인증 오류 | 로컬에 남기고 다음 세션에 재시도 |

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

실패하면 브랜치 방식으로 되돌린다. 실측 방법은 [open-questions.md](../../open-questions.md) V-1~V-3.

## 7. 남은 과제

| 과제 | 내용 |
|---|---|
| 압축 충돌 (G-1) | 현재 압축은 jsonl을 요약본으로 **덮어써** 다른 컴퓨터에 전파한다. 추가 전용 암호 조각에서는 덮어쓸 수 없다. "요약 조각 추가 + 원 조각 삭제 표시"로 바꿔야 한다 |
| 백필 (G-2) | 각 컴퓨터 `state.db`에 이미 있는 원문을 새 구조로 처음 올리는 절차 |
| 기존 export·reindex 전환 | `hermes-export-history.py`, `hermes-reindex.py`, 세션 시작 재색인 훅을 새 경로로 교체 |

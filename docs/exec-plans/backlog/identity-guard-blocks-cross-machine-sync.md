# identity-guard-blocks-cross-machine-sync — 신원 가드가 "다른 컴퓨터의 정본 받아오기" 를 막는다

## 1. 동기 (Why)

**실측 2026-09-22.** ai-create 가 원격(GitLab)보다 10 커밋 뒤처져 있었다. 들어올 커밋이
`.hermes/agents.json` · `.hermes/organization.yaml` · `.hermes/universe.id` 를 건드리는데
같은 경로가 이 컴퓨터에 **미추적 파일**로 있어 `git pull` 이 거부된다. 비우려고
`rm` 을 걸자 `claude-pretooluse-identity-guard.sh` 가 차단했다.

두 가지가 겹쳐 있다.

### (a) 경로 해석 — 다른 저장소를 공장으로 오인

훅은 `PROJECT="${CLAUDE_PROJECT_DIR:-<훅의 저장소>}"` 로 프로젝트를 잡고, 명령 문자열에서
뽑은 경로를 `realpath` 로 푼다. 명령이 `cd /다른/저장소 && rm -f .hermes/agents.json` 이면
**상대 경로가 공장 기준으로 풀려** 공장 자신의 명부로 보인다. 이번 차단이 그 경우다.

뒤집으면: **절대 경로로 같은 일을 하면 통과한다**(공장 밖이라 `inside()` 가 거짓).
즉 지금 판정은 "무엇을 지우는가" 가 아니라 "어떻게 썼는가" 에 걸린다.

### (b) 정책 — 정본 채택 경로가 없다

가드의 취지는 옳다. 손으로 쓰면 조직 축 검증·id 발급·이력(agent.created)을 건너뛴다(RV-06).
그러나 **git 이 가져오는 정본을 받는 일은 손편집이 아니다.** 컴퓨터가 둘 이상이면
"저쪽에서 커밋된 명부를 이쪽이 받는다" 는 정상 작업인데, 세션 안에 그 길이 없다
(훅 주석: "세션 안 탈출구는 없다 — 사람이 손봐야 하면 세션 밖 터미널에서").

### 왜 미추적이었나 — 갈라진 신원

이 컴퓨터의 ai-create 는 파일이 없는 상태에서 스스로 id 를 발급했다. 그래서
같은 프로젝트가 컴퓨터마다 **다른 우주 id·에이전트 id** 를 갖게 됐다.

| 파일 | 원격(정본) | 이 컴퓨터 |
| --- | --- | --- |
| `.hermes/universe.id` | `86c47c92-…` | `213b2bc9-…` |
| `.hermes/agents.json` agent_id | `01a0ad8a-…` | `01a0bd84-…` |
| `.hermes/organization.yaml` | 동일 | 동일 |

영향 범위 실측: `skill_index.universe_id` 30행이 로컬 id 를 물고 있다. 스킬 **검색은
이 값으로 거르지 않는다**(`hermes-search.py` 에 조건 없음). 거르는 곳은
`hermes_journal_views.py:76` 과 기억 이벤트인데 두 표 모두 해당 행 0.
→ 정본 채택의 실제 손해는 거의 없고, `skill_index.universe_id` 만 맞춰 주면 된다.

## 2. 목표 후보

- [ ] 목표 후보 1 — 훅이 `cd` 로 옮긴 작업 디렉터리를 반영해 경로를 푼다(또는 상대 경로를
      판정 불가로 보고 **더 보수적으로** 막되 사유를 다르게 말한다).
      검증: `cd <다른 저장소> && rm .hermes/agents.json` 이 공장 명부로 오인되지 않음을 단언.
- [ ] 목표 후보 2 — 절대 경로/상대 경로가 **같은 판정**을 받는다.
      검증: 같은 대상에 두 표기로 단언, 결과 일치.
- [ ] 목표 후보 3 — "원격 정본 채택" 경로를 CLI 로 연다
      (예: `hermes-agent.py adopt-remote` — git 이 가져온 명부를 검증·이력과 함께 받아들임).
      검증: 갈라진 신원 픽스처에서 CLI 한 번으로 명부·우주id·`skill_index.universe_id` 가 정본에 맞음.

## 3. 비목표

- 가드를 느슨하게 푸는 것. 손편집 차단은 첫 행동 평가에서 4/4 통과를 막은 장치다.
- 세션 안 탈출구(환경변수 우회)를 만드는 것 — key-guard 와 같은 원칙을 깨뜨린다.

## 4. 관련

- `scripts/hooks/claude-pretooluse-identity-guard.sh`
- `docs/exec-plans/completed/2026-09-20-identity-files-edit-guard.md` · D-01 · C-20 · RV-06
- `docs/exec-plans/backlog/dashboard-sync-before-verdict.md` — 같은 사건에서 나온 다른 발견

# jj-agent-room 에 게임회사를 세운다 — 논의 기록 (2026-11-18)

[2026-11-18-findings.md](2026-11-18-findings.md) 뒤에 이어진 논의다. 무엇을 정했고, 무엇을 추천했고, 무엇이 아직 열려 있는지 적는다.
코드 근거는 모두 **읽어서** 확인했다. 실행해 본 것은 없다. 경로는 jj-agent-room 저장소 기준이다(공장 경로는 따로 표시).

## 1. 정한 것 (사용자 결정)

| # | 결정 | 출처 |
|---|---|---|
| D1 | 엔진은 하나로 고르지 않는다. Web·Godot·Unity·Unreal 을 **사용자가 게임마다 고른다** | "둘다 제공할 수 있게해야지. 사용자가 선택해서" |
| D2 | 처음부터 만들지 않고 **Claude Code Game Studios(이하 CCGS)를 가져와 고친다** (MIT) | "응 그게 낫겠어" |
| D3 | 입구는 공장이 아니라 **jj-agent-room** 이다. 회사 종류 "게임회사" 를 만들고 LNB 에 게임 메뉴를 둔다 | "게임회사의 게임 LNB를 만들어서 이어주는거지" |
| D4 | CCGS 에이전트 49명을 **전부 게임회사 직원으로 보이게** 한다. 다른 종류는 4명, 게임회사는 49명 | "전부 직원으로 보이게 하자" |
| D5 | CCGS 새 판은 jj-agent-room 이 원본을 확인하고 받는 방식처럼 처리한다 | "그 방식으로 처리하면 할 수 있지않아?" |

## 2. 이 결정이 기대는 jj-agent-room 의 구조

- **회사 종류** — 회사를 세울 때 종류를 고르고, 종류마다 처음 켜지는 메뉴가 다르다(`fork_kind_menus`, `docs/design-docs/menu-layers.md` ③층). 종류 예: `logistics` · `dev-team` · 마케팅 · 번역.
- **회사 전용 LNB 메뉴** — 한 줄에 화면 + 서버 경로 + 에이전트 명령(`cliCommands`) + 에이전트 안내문(`agentGuide`)이 붙는다(`server/src/fork/orgAdmin/menus/menuCatalog.ts`). 항만·마케팅·번역·출시가 이렇게 생겼다.
- **종류별 시작 팀** — `server/src/fork/orgAdmin/kinds/teams/<종류>.ts` 한 파일. 지금 7개 종류가 모두 4명, dev-team 은 원본 4명(Atlas·Iris·Bram·Nova), 미정 "일반" 은 다온 1명(`starterTeams.ts`).
- **내 PC 에이전트(BYOA)** — 사용자 PC 의 Claude Code 를 에이전트로 붙인다. 클라우드 에이전트는 OpenAI API 로 돈다(README) — CCGS 는 Claude Code 용이라 BYOA 로만 돈다.

### 그려 본 모양

- 회사 종류 `game-studio` → 처음 메뉴 `게임`.
- `게임` 화면: 게임 목록 · 새 게임(아이디어 한 줄 + 엔진 선택) · 진행 상태(질문 → 기획서 → 만들기 → 점검 카드) · 해 보기 링크.
- 에이전트: `cumora game …` 명령과 게임 안내문을 받는다.
- 유니티·Unreal 은 그 PC 에 엔진이 깔려 있어야 한다. 웹은 브라우저만 있으면 된다.

## 3. 49명은 누구인가

CCGS `.claude/agents/` 49개 파일의 설명·모델 줄을 모두 읽었다. 실제로 일하는 것은 Claude 하나이고, 역할(프롬프트)을 바꿔 부르는 구조다.

| 묶음 | 수 | 구성 |
|---|---:|---|
| 감독 | 3 | creative-director · technical-director · producer (opus) |
| 팀장 | 8 | game-designer · lead-programmer · art-director · audio-director · narrative-director · qa-lead · release-manager · localization-lead |
| 실무자 | 23 | 기획(systems · level · economy · ux) · 프로그래밍(gameplay · engine · ai · network · ui · tools · prototyper) · technical-artist · sound-designer · writer · world-builder · qa-tester · performance-analyst · security-engineer · accessibility-specialist · devops-engineer · analytics-engineer · live-ops-designer · community-manager |
| 엔진 전문가 | 15 | Godot 5 · Unity 5 · Unreal 5 (엔진마다 대표 1 + 세부 4) |

- 모델: 감독 3 opus · lead-programmer 와 실무자 15 sonnet · 나머지 30 세션 모델.
- **CCGS 기본 흐름(`/prototype`)에서는 거의 쉰다.** 게임은 세션이 직접 만들고, 노력을 따로 정할 때만 범용 에이전트가 붙는다. 49명은 "스튜디오 모드" 에서 일한다(README · `one-shot-2-build.md`).
- 그림 파일을 그리는 직원은 없다. art-director 는 기준, technical-artist 는 셰이더, sound-designer 는 명세다.

## 4. 열린 질문 셋과 추천

### Q1. 49명의 한도·비용 — 추천: **한도 예외(A) + 이미 있는 음소거**

확인한 사실:
- 요금 등급별 회사당 에이전트 한도: free 10 · pro 20 · max 50 (`server/src/api/router.ts:266-269`). 퇴사하지 않은 에이전트는 모두 센다(`server/src/fork/org/orgLimits.ts:101`). "쉬는 상태" 는 없다.
- 시작 팀을 넣을 때는 한도를 검사하지 않는다(`onboardCompany.ts` — `assertCompanyAgentLimit` 를 부르지 않음). free 회사에도 49명이 들어가고, 그 뒤 새 에이전트 만들기가 막힌다.
- 대화방에 메시지가 오면 **그 방의 에이전트 전원이 깨어난다.** @로 한 명을 불러도 같다 — 좁히면 노트북이 닫힌 에이전트 때문에 방이 조용해지는 문제가 있어서 일부러 그렇게 했다(`server/src/agents/scheduler.ts:1026-1038`).
- 깨어난 에이전트마다 작은 모델이 반응 여부를 정하는데, **사람이 쓴 메시지는 언제나 반응** 이다(`docs/COORDINATION.md` §6). 49명이 있는 전체 방에서 사람이 한 줄 쓰면 큰 모델이 최대 49번 돌 수 있다.
- 시작 팀마다 DM 방이 생기고, 전체 방(Everyone)에 대표와 직원 전원이 들어간다(`onboardCompany.ts` Phase 2 · all-hands).
- **음소거가 이미 있다.** 음소거된 에이전트는 단체 방에서 @로 부르거나 그 에이전트 글에 답할 때만 깨어난다. DM 은 늘 깨어난다(`scheduler.ts:1014` `shouldDeliverToMutedAgent`, 표 `conversation_mutes`).

추천:
- 49명 모두 명부에 올린다(D4).
- 전체 방에서는 감독 3명만 깨어 있고 46명은 음소거로 넣는다. 필요할 때 @로 부른다.
- 한도: 게임회사 시작 팀 49명은 한도 계산에서 뺀다. 사용자가 더 만드는 에이전트는 등급 한도를 그대로 쓴다.
- DM 방은 감독 3명만 만든다.

고르지 않은 안:
- B(일하는/대기 상태를 새로 만듦) — 반응·한도·명부 화면을 모두 고쳐야 하는데, 같은 효과를 음소거가 이미 낸다.
- C(11명으로 시작, 나머지는 필요할 때 입사) — D4 "전부 보이게" 와 어긋난다.

### Q2. CCGS 새 판을 어느 장부로 확인하나 — 추천: **jj-agent-room 별도 장부**

확인한 사실:
- jj-agent-room 이 새 판을 받는 길은 둘이다.
  1. Cumora 원본: git `upstream` 원격 + 릴리스 태그 단위 병합 커밋 + 원작자 값 되돌아옴 막는 훅·빌드 게이트(`docs/design-docs/fork-upstream.md` §3). 마지막 반영 2026-10-13. 새 판을 자동으로 알리는 장치는 찾지 못했다.
  2. 공장의 원본 판 감시(공장 `docs/exec-plans/completed/2026-11-15-upstream-version-watch-plan.md`): 장부 + 세션 시작 때 하루 한 번 GitHub 확인 + "올려" 하면 공장이 올림. 고쳐 쓴 것(`adapted`)은 덮지 않고 차이만 보인다.
- CCGS 자체에도 하루 한 번 새 릴리스를 알리는 훅이 있다(CCGS `.claude/hooks/update-check.sh`).
- 공장을 다시 설치하면 소우주의 `.claude/.upstream.json` 을 공장 항목만으로 **통째로 다시 쓴다**(공장 `lib/upstream_ledger.sh`). 거기 넣은 jj-agent-room 항목은 사라진다.
- 확인 프로그램 `scripts/upstream-check.py` 는 `--ledger <경로>` 로 다른 장부를 읽는다(공장 358-367행).

추천:
- jj-agent-room 에 장부 파일을 따로 두고 CCGS 항목을 `adapted` 로 적는다. 같은 확인 프로그램을 `--ledger` 로 돌린다.
- 시작 훅은 기본 장부만 보므로, jj-agent-room 쪽에 시작 훅 한 줄이 더 필요하다(미확인 — 착수 때 확인).
- 49명·스킬은 jj-agent-room 코드로 옮겨 고치므로 덮어쓰기(`vendored`)가 아니라 차이 보기(`adapted`)가 맞다. Cumora 를 "원본 변경분만 다시 옮기는" 방식과 같다.

### Q3. 에이전트가 게임 폴더에서 CCGS 를 그대로 쓸 수 있나 — **못 쓴다. 스킬을 옮겨 고쳐야 한다**

확인한 사실:
- BYOA 에이전트는 Claude Code 를 **에이전트 자기 폴더**(`<설정 폴더>/agents/<id>`)에서만 실행한다. 다른 작업 폴더는 거부한다(`server/src/fork/agentNamespace.ts:53` · `:99`).
- 그 폴더의 `CLAUDE.md` 는 시작할 때마다 페르소나로 다시 써진다. 제한 모드는 프로젝트 `settings.json` 을 무시한다(`server/src/agents/computer/engine.ts:1789-1800`). → CCGS 의 훅은 돌지 않는다.
- 에이전트 폴더 안 `.claude/skills/` 는 있다(`engine.ts:1793`). "지정한 폴더" 파일 접근으로 게임 폴더를 읽고 쓰게 할 수 있다(`src/components/fork/FileAccessField.tsx`, Claude Code 엔진 전용).
- CCGS README: 루트가 아닌 곳에서 켜면 훅·거부 규칙·묻기 모드가 꺼진다.

결론:
- 처음 그린 "게임마다 CCGS 를 받은 폴더에서 일한다" 는 그대로는 안 된다. (논의 중 이 부분을 확인하지 않고 말했다.)
- CCGS 의 필요한 스킬(`/prototype`, 점검 스크립트 `one-shot-check.sh`·`page-shot.sh` 등)을 에이전트 스킬로 옮겨 고치고, 게임 폴더는 "지정한 폴더" 로 준다.
- 비용: CCGS 스킬 안 경로(`.claude/scripts/…`, `design/`, `prototypes/`)와 `project.yaml` 설정 읽기를 손봐야 한다. 일이 커진다.

## 5. 정리된 질문

| 질문 | 결과 |
|---|---|
| 공장 프리셋인가, 따로 저장소인가 | jj-agent-room 으로 (D3) |
| 엔진을 언제 고르나 | 게임마다 (D1) |
| 49명을 세션 보조로 두나, 직원으로 올리나 | 전부 직원 (D4) |
| 첫 출시 목표(웹·스팀·모바일) | 엔진을 게임마다 고르므로 지금 정할 필요 없음 |

## 6. 다음에 정할 것

- Q1~Q3 추천을 받아들일지.
- 받아들이면 jj-agent-room 에 실행 계획서(`docs/exec-plans/active/`)를 쓴다 — 회사 종류 · 시작 팀 49명 · 게임 메뉴 · 스킬 이식 · 장부.
- 이 컴퓨터에서 작은 브라우저 게임 한 판을 먼저 돌려 볼지(헤드리스 브라우저 `PAGE_SHOT_BROWSER` 경로 확인 포함).

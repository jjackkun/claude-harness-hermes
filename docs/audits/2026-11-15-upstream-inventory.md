# 2026-11-15 밖에서 가져온 에셋 전수 조사

계획: `docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md` G2. 장부: `assets/upstream.json`.

## 방법

- `assets/` 의 스킬·규칙·에이전트·훅 165개를 하나씩 보았다.
- 흔적 찾기: 파일 안의 LICENSE·`license:`·NOTICE·`origin:` 주석·`출처:`·외부 GitHub URL, 그리고 그 에셋이 처음 들어온 커밋.
- 이름 대조: `affaan-m/ECC`(옛 이름 everything-claude-code)와 `anthropics/skills` 의 전체 트리를 받아 같은 이름의 스킬·에이전트·규칙 폴더를 찾았다.
- 내용 대조: 같은 이름이면 원본 SKILL.md(에이전트는 본문)와 공장 사본의 유사도를 쟀다. description 줄과 origin 주석은 빼고 쟀다. 0.99 이상이면 "그대로", 아니면 "고쳐 씀".
- 유사도가 낮은 것은 공장이 고쳤거나, 원본이 그 뒤에 크게 바뀐 것이다. 둘을 가를 기록이 없으므로 "고쳐 씀"(자동 덮어쓰기 안 함)으로 둔다.
- 장부의 `sha` 는 2026-11-15 원본의 git tree/blob sha 다. 복사 당시 판이 아니라 **오늘을 기준선으로** 삼는다. 앞으로 바뀌는 것만 감지한다.

## 요약

- 고쳐 씀: 37개
- 공장 제작: 107개
- 그대로: 13개
- 확인 못 함: 8개

훅 83개는 모두 공장(또는 사용자의 다른 프로젝트 rim-kanban)에서 만들었다. 외부 원본이 없다.

## 전체 표

| 종류 | 이름 | 분류 | 근거 |
|---|---|---|---|
| skills | backend-patterns | 고쳐 씀 | affaan-m/ECC `skills/backend-patterns` (유사도 0.947) |
| skills | coding-standards | 그대로 | affaan-m/ECC `skills/coding-standards` (유사도 0.997) |
| skills | continuous-learning-v2 | 고쳐 씀 | affaan-m/ECC `skills/continuous-learning-v2` (유사도 0.899) |
| skills | dart-flutter-patterns | 그대로 | affaan-m/ECC `skills/dart-flutter-patterns` (유사도 1.0) |
| skills | database-migrations | 그대로 | affaan-m/ECC `skills/database-migrations` (유사도 1.0) |
| skills | fastapi-patterns | 고쳐 씀 | affaan-m/ECC `skills/fastapi-patterns` (유사도 0.047) |
| skills | fastapi-testing | 확인 못 함 | Initial commit 에 들어왔고 원본 흔적(LICENSE·URL·origin 주석)이 없다. ECC·anthropics 저장소에 같은 이름 없음 |
| skills | file-explorer | 공장 제작 | 처음 커밋: e88ec94 feat(mods): 패널 모드 세 개를 전역 선택 프리셋으로 설치할 수 있게 한다 |
| skills | flutter-dart-code-review | 그대로 | affaan-m/ECC `skills/flutter-dart-code-review` (유사도 1.0) |
| skills | frontend-design | 고쳐 씀 | anthropics/skills `skills/frontend-design` (유사도 0.028) |
| skills | frontend-patterns | 고쳐 씀 | affaan-m/ECC `skills/frontend-patterns` (유사도 0.952) |
| skills | harness-boundary-check | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| skills | harness-eval | 공장 제작 | 처음 커밋: 1299a6e feat(harness): 행동 회귀 평가 harness-eval — 시나리오 6 × 엄격도 |
| skills | harness-promote-rule | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| skills | harness-reasoning-sandwich | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| skills | hermes-agent | 공장 제작 | 처음 커밋: 6f82144 feat(hermes): hermes-agent 스킬·계획 4 종료 (Step 5) |
| skills | hermes-crystallize | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| skills | hermes-dashboard | 공장 제작 | 처음 커밋: d61426d feat(hermes): /hermes-dashboard 스킬 + 세션 시작 훅 하루 1회 갱 |
| skills | hermes-dream | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| skills | hermes-loop | 공장 제작 | 처음 커밋: 6a1e36b feat(hermes): /hermes-loop 대화형 스킬 + 설치·제거 매니페스트 등록 |
| skills | hermes-recall | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| skills | hermes-room | 공장 제작 | 처음 커밋: 9c1aebd feat(skills): /hermes-roster · /hermes-room — 명부 전원· |
| skills | hermes-roster | 공장 제작 | 처음 커밋: 9c1aebd feat(skills): /hermes-roster · /hermes-room — 명부 전원· |
| skills | hermes-roster-pane | 공장 제작 | 처음 커밋: e88ec94 feat(mods): 패널 모드 세 개를 전역 선택 프리셋으로 설치할 수 있게 한다 |
| skills | hermes-status | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| skills | idea-check | 고쳐 씀 | garrytan/gstack `openclaw/skills/gstack-openclaw-office-hours` |
| skills | impeccable | 그대로 | pbakaus/impeccable `.claude/skills/impeccable` |
| skills | intended-vs-implemented | 고쳐 씀 | phuryn/pm-skills `pm-ai-shipping/skills/intended-vs-implemented` |
| skills | java-coding-standards | 고쳐 씀 | affaan-m/ECC `skills/java-coding-standards` (유사도 0.401) |
| skills | jpa-patterns | 그대로 | affaan-m/ECC `skills/jpa-patterns` (유사도 1.0) |
| skills | mcp-builder | 고쳐 씀 | anthropics/skills `skills/mcp-builder` (유사도 0.396) |
| skills | node-patterns | 확인 못 함 | Initial commit 에 들어왔고 원본 흔적(LICENSE·URL·origin 주석)이 없다. ECC·anthropics 저장소에 같은 이름 없음 |
| skills | plan-verification-split | 확인 못 함 | Initial commit 에 들어왔고 원본 흔적(LICENSE·URL·origin 주석)이 없다. ECC·anthropics 저장소에 같은 이름 없음 |
| skills | postgres-patterns | 그대로 | affaan-m/ECC `skills/postgres-patterns` (유사도 1.0) |
| skills | prd-writer | 고쳐 씀 | phuryn/pm-skills `pm-execution/skills/create-prd`, product-on-purpose/pm-skills `skills/deliver-prd/SKILL.md` |
| skills | pre-commit-measure | 공장 제작 | 처음 커밋: 44579b4 feat(skills): pre-commit-measure — 커밋 전에 주장마다 가장 작은 |
| skills | python-patterns | 그대로 | affaan-m/ECC `skills/python-patterns` (유사도 0.998) |
| skills | readme-sync-before-commit | 공장 제작 | 처음 커밋: ecc264c feat(skill): 커밋 전에 README 반영 여부를 판정하고 고치는 공장 전용 스킬을 |
| skills | run-to-the-end | 공장 제작 | 처음 커밋: 159315c feat(harness): 시작한 일은 그 턴 안에서 끝낸다 — 리마인더 한 줄 + 스킬 |
| skills | search-first | 고쳐 씀 | affaan-m/ECC `skills/search-first` (유사도 0.871) |
| skills | skill-creator | 그대로 | anthropics/skills `skills/skill-creator` (유사도 1.0) |
| skills | springboot-patterns | 그대로 | affaan-m/ECC `skills/springboot-patterns` (유사도 1.0) |
| skills | springboot-security | 그대로 | affaan-m/ECC `skills/springboot-security` (유사도 1.0) |
| skills | springboot-tdd | 그대로 | affaan-m/ECC `skills/springboot-tdd` (유사도 1.0) |
| skills | strategic-compact | 고쳐 씀 | affaan-m/ECC `skills/strategic-compact` (유사도 0.642) |
| skills | structured-file-layout | 확인 못 함 | Initial commit 에 들어왔고 원본 흔적(LICENSE·URL·origin 주석)이 없다. ECC·anthropics 저장소에 같은 이름 없음 |
| skills | svelte-patterns | 확인 못 함 | Initial commit 에 들어왔고 원본 흔적(LICENSE·URL·origin 주석)이 없다. ECC·anthropics 저장소에 같은 이름 없음 |
| skills | sveltekit-fastapi-scaffold | 공장 제작 | 처음 커밋: 608e66e feat(skill): sveltekit-fastapi-scaffold — 프로젝트 전용 Sv |
| skills | tdd-workflow | 고쳐 씀 | affaan-m/ECC `skills/tdd-workflow` (유사도 0.588) |
| skills | tool-calls-pane | 공장 제작 | 처음 커밋: e88ec94 feat(mods): 패널 모드 세 개를 전역 선택 프리셋으로 설치할 수 있게 한다 |
| skills | typescript-patterns | 고쳐 씀 | affaan-m/ECC `skills/typescript-patterns` (유사도 0.048) |
| skills | ui-prototype | 공장 제작 | 처음 커밋: 396d992 feat(skill): 문서에서 눌러 보는 시안을 만드는 ui-prototype 스킬 |
| skills | verification-loop | 고쳐 씀 | affaan-m/ECC `skills/verification-loop` (유사도 0.643) |
| skills | video-to-interaction | 공장 제작 | 처음 커밋: 8028e46 feat(skill): video-to-interaction — 참고 영상 10fps 전수 관 |
| skills | webapp-testing | 그대로 | anthropics/skills `skills/webapp-testing` (유사도 1.0) |
| rules | adhd | 고쳐 씀 | ayghri/i-have-adhd `skills/i-have-adhd/SKILL.md` |
| rules | common | 고쳐 씀 | affaan-m/ECC `rules/common` |
| rules | dart | 고쳐 씀 | affaan-m/ECC `rules/dart` |
| rules | fastapi | 확인 못 함 | Initial commit 에 들어왔고 원본 흔적(LICENSE·URL·origin 주석)이 없다. ECC·anthropics 저장소에 같은 이름 없음 |
| rules | harness | 고쳐 씀 | obra/superpowers `skills/subagent-driven-development/SKILL.md` |
| rules | java | 고쳐 씀 | affaan-m/ECC `rules/java` |
| rules | korean | 공장 제작 | 처음 커밋: 2fc6867 feat(korean): 사용자에게 보이는 답변을 한국어로 강제하는 선택 프리셋 korean |
| rules | postgres | 확인 못 함 | Initial commit 에 들어왔고 원본 흔적(LICENSE·URL·origin 주석)이 없다. ECC·anthropics 저장소에 같은 이름 없음 |
| rules | python | 고쳐 씀 | affaan-m/ECC `rules/python` |
| rules | typescript | 고쳐 씀 | affaan-m/ECC `rules/typescript` |
| rules | web | 고쳐 씀 | affaan-m/ECC `rules/web` |
| agents | architect-lite.md | 고쳐 씀 | affaan-m/ECC `agents/architect.md` |
| agents | architect.md | 고쳐 씀 | affaan-m/ECC `agents/architect.md` (유사도 0.03) |
| agents | code-reviewer.md | 고쳐 씀 | affaan-m/ECC `agents/code-reviewer.md` (유사도 0.017) |
| agents | database-reviewer.md | 고쳐 씀 | affaan-m/ECC `agents/database-reviewer.md` (유사도 0.882) |
| agents | devil-advocate.md | 공장 제작 | 처음 커밋: 8a91b6c feat(harness): 반대편 에이전트(devil-advocate) 시험 — 규격·실제 2 |
| agents | doc-updater.md | 고쳐 씀 | affaan-m/ECC `agents/doc-updater.md` (유사도 0.859) |
| agents | docs-lookup.md | 고쳐 씀 | affaan-m/ECC `agents/docs-lookup.md` (유사도 0.866) |
| agents | fullstack-developer.md | 확인 못 함 | origin 주석이 ECC 를 가리키지만 ECC 트리에 같은 이름이 없다 — 장부 `untracked` 에 기록 |
| agents | performance-optimizer.md | 고쳐 씀 | affaan-m/ECC `agents/performance-optimizer.md` (유사도 0.955) |
| agents | planner-lite.md | 고쳐 씀 | affaan-m/ECC `agents/planner.md` |
| agents | planner.md | 고쳐 씀 | affaan-m/ECC `agents/planner.md` (유사도 0.041) |
| agents | python-reviewer.md | 고쳐 씀 | affaan-m/ECC `agents/python-reviewer.md` (유사도 0.838) |
| agents | refactor-cleaner.md | 고쳐 씀 | affaan-m/ECC `agents/refactor-cleaner.md` (유사도 0.828) |
| agents | silent-failure-hunter.md | 고쳐 씀 | affaan-m/ECC `agents/silent-failure-hunter.md` (유사도 0.635) |
| agents | tdd-guide.md | 고쳐 씀 | affaan-m/ECC `agents/tdd-guide.md` (유사도 0.84) |
| agents | typescript-reviewer.md | 고쳐 씀 | affaan-m/ECC `agents/typescript-reviewer.md` (유사도 0.655) |
| hooks | agent_count.py | 공장 제작 | 처음 커밋: af007ba feat(hooks): cost-guard — 비싼 평가는 묻고, 서브에이전트는 모델을 정하게 |
| hooks | check-component-structure.mjs | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | check-privacy.py | 공장 제작 | 처음 커밋: 30733c1 feat(knowledge): 사람 칸 · 올리기 전 판정·확인 · 에이전트 지식 파일 · R |
| hooks | check-secrets.py | 공장 제작 | 처음 커밋: 1ed1697 fix: 세션 기록 평문 자격증명 유출 차단 — 네 겹 전부 보강 |
| hooks | check-structure.mjs | 공장 제작 | 처음 커밋: 3dfd678 feat(struct): R-struct 를 언어 무관 엔진 + 언어 설정표로 바꾸고 Tier |
| hooks | claude-posttooluse-dead-file-warn.sh | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | claude-posttooluse-factory-tamper-warn.sh | 공장 제작 | 처음 커밋: ee23daf feat(install): 심링크 설치를 복사 설치로 바꾼다 (계획 1 복사 설치, 목표 1~ |
| hooks | claude-posttooluse-hermes-assist.sh | 공장 제작 | 처음 커밋: 0ab1781 feat(hermes): Bash 실패 신호 기반 스킬 주입 훅 신설 (C1) |
| hooks | claude-posttooluse-output-budget.sh | 공장 제작 | 처음 커밋: 885e9e1 feat(harness): 도구 출력이 컨텍스트를 태우는 양을 실측한다 (R-out) |
| hooks | claude-posttooluse-prettier-warn.sh | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | claude-posttooluse-review-record.sh | 공장 제작 | 처음 커밋: 3b25161 feat(harness): 4개월간 문서만 존재하던 리뷰 강제를 실제로 붙인다 |
| hooks | claude-posttooluse-review-reminder.sh | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | claude-posttooluse-size-warn.sh | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | claude-precompact-summary.sh | 공장 제작 | 처음 커밋: 88f9329 feat(hermes): PreCompact 훅 — 압축 직전에 5슬롯 요약을 한 번 더 남긴 |
| hooks | claude-pretooluse-agent-guard.sh | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | claude-pretooluse-bash-guard.sh | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | claude-pretooluse-cost-guard.sh | 공장 제작 | 처음 커밋: af007ba feat(hooks): cost-guard — 비싼 평가는 묻고, 서브에이전트는 모델을 정하게 |
| hooks | claude-pretooluse-data-guard.sh | 공장 제작 | 처음 커밋: 6fa8a07 feat(hooks): R-del — 데이터를 지우는 명령은 사람 승인 뒤에만 (data-gu |
| hooks | claude-pretooluse-identity-guard.sh | 공장 제작 | 처음 커밋: 0be9add feat(hermes): identity-guard — 명부(agents.json)·기억 파생 |
| hooks | claude-pretooluse-iface-guard.sh | 공장 제작 | 처음 커밋: c6bf705 feat(harness): 인터페이스 폭을 파일이 쓰이기 전에 재고, 넓어지는 경로를 막는다 |
| hooks | claude-pretooluse-key-guard.sh | 공장 제작 | 처음 커밋: fcb350f feat(hermes): 암호 계층 — age 감싸기·열쇠 정책·24단어 비상 열쇠·키 가드 |
| hooks | claude-pretooluse-plan-declare.sh | 공장 제작 | 처음 커밋: 122eaa4 feat(harness): 새 파일은 만들기 전에 책임을 적게 한다 |
| hooks | claude-pretooluse-summon-guard.sh | 공장 제작 | 처음 커밋: f4d82cc feat(hermes): 소환 토큰·러너·claude 프린트 가드 — 사칭 방지 (계획 4 S |
| hooks | claude-pretooluse-summons-write-guard.sh | 공장 제작 | 처음 커밋: ed89793 feat(hermes): 설계 확정 동작 7건 채움 — 이력 자유 글 마스킹·agent.cre |
| hooks | claude-sessionstart-agent-soul.sh | 공장 제작 | 처음 커밋: c35012c feat(hermes): 소환된 에이전트가 정체성 폴더를 읽고 출근한다 — SOUL.md·ME |
| hooks | claude-sessionstart-dashboard.sh | 공장 제작 | 처음 커밋: d61426d feat(hermes): /hermes-dashboard 스킬 + 세션 시작 훅 하루 1회 갱 |
| hooks | claude-sessionstart-doc-gardening.sh | 공장 제작 | 처음 커밋: a9f7719 feat: 가드닝을 CI 배선 없이도 돌게 하고, 미배선을 경고로 승격 |
| hooks | claude-sessionstart-dream.sh | 공장 제작 | 처음 커밋: da1ef93 feat(hermes): 드림 세션시작 자동 트리거(cron 대체) + Codex 동결 명문화 |
| hooks | claude-sessionstart-factory-link-check.sh | 공장 제작 | 처음 커밋: ee23daf feat(install): 심링크 설치를 복사 설치로 바꾼다 (계획 1 복사 설치, 목표 1~ |
| hooks | claude-sessionstart-handoff-expiry.sh | 공장 제작 | 처음 커밋: edadeed feat(hermes): 인계 봉투·done_when 다섯 형식·만료 훅 (계획 4 Step |
| hooks | claude-sessionstart-install-uncommitted-warn.sh | 공장 제작 | 처음 커밋: 444184a feat(install): 설치 영수증과 미커밋 경고 훅을 넣는다 (커밋 경로를 기억으로 정하 |
| hooks | claude-sessionstart-memory-guard.sh | 공장 제작 | 처음 커밋: 39da880 feat(hermes): 메모리 심링크 자가치유 SessionStart 가드 훅 (Part A |
| hooks | claude-sessionstart-mutation-probe.sh | 공장 제작 | 처음 커밋: b11b93e feat(harness): 게이트 발화를 기록해 Provisional 룰의 승격 근거를 만든다 |
| hooks | claude-sessionstart-outbox-status.sh | 공장 제작 | 처음 커밋: 2cb118d feat(hermes): 제안 봉투·금지 게이트·gh 배달·상태 알림 (계획 5 Step 4) |
| hooks | claude-sessionstart-owner-proposals.sh | 공장 제작 | 처음 커밋: dd4dee0 feat(hermes): 설계 확정 기능 9건 보강 — 매칭 근거·출처 불명·전에 철회됨·만료 |
| hooks | claude-sessionstart-persona.sh | 공장 제작 | 처음 커밋: 3570fa7 feat(hermes): 사용자 성향 Step 4·5 — review·approve·rejec |
| hooks | claude-sessionstart-room-owner.sh | 공장 제작 | 처음 커밋: 13d31d6 feat(agent): 명부 에이전트와 어디서든 대화하고 기억을 잇는다 — hermes-cha |
| hooks | claude-sessionstart-summons-verify.sh | 공장 제작 | 처음 커밋: f4d82cc feat(hermes): 소환 토큰·러너·claude 프린트 가드 — 사칭 방지 (계획 4 S |
| hooks | claude-sessionstart-sync-pull.sh | 공장 제작 | 처음 커밋: 1406ad9 feat(hermes): 기억 운반 — refs/hermes/sync push·pull·합류· |
| hooks | claude-settings-hooks.json | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | claude-stop-journal-gap.sh | 공장 제작 | 처음 커밋: 3e63003 feat(hermes): 끝나지 않은 작업을 기계가 닫는다 — Stop 훅·heartbeat· |
| hooks | claude-stop-korean-guard.sh | 공장 제작 | 처음 커밋: 2fc6867 feat(korean): 사용자에게 보이는 답변을 한국어로 강제하는 선택 프리셋 korean |
| hooks | claude-stop-retrospective.sh | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | claude-subagentstart-agent-soul.sh | 공장 제작 | 처음 커밋: 46419b7 feat(hooks): SubagentStart 훅 — @agent-<slug> 로 불린 명부 |
| hooks | claude-subagentstart-journal.sh | 공장 제작 | 처음 커밋: 5004c56 feat(hooks): @ 로 부른 명부 에이전트의 일을 명부 id 로 이력에 남긴다 (age |
| hooks | claude-subagentstop-journal.sh | 공장 제작 | 처음 커밋: ad449e0 feat(hermes): 행위자를 기계가 찍는다 — SubagentStop 훅과 loops.s |
| hooks | claude-subagentstop-summarize.sh | 공장 제작 | 처음 커밋: 13d31d6 feat(agent): 명부 에이전트와 어디서든 대화하고 기억을 잇는다 — hermes-cha |
| hooks | claude-userpromptsubmit-dispatch.sh | 공장 제작 | 처음 커밋: 22e9f18 fix(hooks): UserPromptSubmit 이 stdin 을 나눠 갖지 못하던 구조를 |
| hooks | claude-userpromptsubmit-hag.sh | 공장 제작 | 처음 커밋: 13d31d6 feat(agent): 명부 에이전트와 어디서든 대화하고 기억을 잇는다 — hermes-cha |
| hooks | claude-userpromptsubmit-korean.sh | 공장 제작 | 처음 커밋: 2fc6867 feat(korean): 사용자에게 보이는 답변을 한국어로 강제하는 선택 프리셋 korean |
| hooks | claude-userpromptsubmit-mistake-detect.sh | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | claude-userpromptsubmit-reminders.sh | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | claude-userpromptsubmit-soul-approval-intent.sh | 공장 제작 | 처음 커밋: d3bbd5f feat(hermes): SOUL 승인은 사람의 말이 있을 때만 — 에이전트의 자기 승인 차단 |
| hooks | claude_config_scan.py | 공장 제작 | 처음 커밋: 3d05269 feat(harness): R-config — `.claude/` 설정이 연 위험 표면을 센다 |
| hooks | complexity.py | 공장 제작 | 처음 커밋: bc7d9b8 feat(harness): 함수가 얼마나 꼬였는지 재고, 나빠질 때만 막는다 |
| hooks | context_budget.py | 공장 제작 | 처음 커밋: 2dc0ab5 feat(harness): context-budget — 세션 고정 비용을 항목별로 센다 (계 |
| hooks | cost_agent_model.py | 공장 제작 | 처음 커밋: af007ba feat(hooks): cost-guard — 비싼 평가는 묻고, 서브에이전트는 모델을 정하게 |
| hooks | cost_command.py | 공장 제작 | 처음 커밋: af007ba feat(hooks): cost-guard — 비싼 평가는 묻고, 서브에이전트는 모델을 정하게 |
| hooks | coverage_probe.py | 공장 제작 | 처음 커밋: 219503c feat(harness): 테스트가 한 줄도 실행하지 않는 코드를 드러낸다 |
| hooks | data_delete.py | 공장 제작 | 처음 커밋: 6fa8a07 feat(hooks): R-del — 데이터를 지우는 명령은 사람 승인 뒤에만 (data-gu |
| hooks | depcheck.py | 공장 제작 | 처음 커밋: d43eae3 feat(harness): 모듈 의존 방향을 문서가 아니라 검사로 고정한다 |
| hooks | design_cover.py | 공장 제작 | 처음 커밋: a3e7fd5 feat(rules): R-design-cover 승격 — 설계 확정 결정은 계획서에 결정 I |
| hooks | doc-gardening-drift.sh | 공장 제작 | 처음 커밋: a330542 feat: 문서 갱신 축 — 계획서가 코드를 따라오는지 감지 |
| hooks | doc_counts.py | 공장 제작 | 처음 커밋: 62cff80 feat(harness): 문서가 주장하는 수치를 소스에서 강제한다 (R-doc) |
| hooks | gate_emit.sh | 공장 제작 | 처음 커밋: b11b93e feat(harness): 게이트 발화를 기록해 Provisional 룰의 승격 근거를 만든다 |
| hooks | gate_event.py | 공장 제작 | 처음 커밋: b11b93e feat(harness): 게이트 발화를 기록해 Provisional 룰의 승격 근거를 만든다 |
| hooks | gate_report.py | 공장 제작 | 처음 커밋: b11b93e feat(harness): 게이트 발화를 기록해 Provisional 룰의 승격 근거를 만든다 |
| hooks | iface_width.py | 공장 제작 | 처음 커밋: e01e772 fix(harness): 책임 누적 신호를 되살리고, 커밋을 침묵 차단하던 결함을 잡는다 |
| hooks | korean_reply_check.py | 공장 제작 | 처음 커밋: 2fc6867 feat(korean): 사용자에게 보이는 답변을 한국어로 강제하는 선택 프리셋 korean |
| hooks | out_report.py | 공장 제작 | 처음 커밋: cac49b8 feat(harness): R-out 기록에 명령 머리(cmd:<머리>) 추가 + out_re |
| hooks | out_shape.py | 공장 제작 | 처음 커밋: fbbc372 feat(r-out): 이벤트에 명령 모양과 에이전트를 남겨 "무엇이 바이트를 냈나" 를 가린 |
| hooks | plan_state.py | 공장 제작 | 처음 커밋: a330542 feat: 문서 갱신 축 — 계획서가 코드를 따라오는지 감지 |
| hooks | pre-commit.sh | 공장 제작 | 이름·내용이 이 공장(하네스·헤르메스) 고유 — Initial commit |
| hooks | pytest_gate.sh | 공장 제작 | 처음 커밋: b094fee fix(r-test): 커밋 게이트가 프로젝트 가상환경(.venv 포함)의 pytest 를 쓰 |
| hooks | structure-baseline.mjs | 공장 제작 | 처음 커밋: 3dfd678 feat(struct): R-struct 를 언어 무관 엔진 + 언어 설정표로 바꾸고 Tier |
| hooks | structure-config.mjs | 공장 제작 | 처음 커밋: 3dfd678 feat(struct): R-struct 를 언어 무관 엔진 + 언어 설정표로 바꾸고 Tier |
| hooks | structure-langs.json | 공장 제작 | 처음 커밋: 3dfd678 feat(struct): R-struct 를 언어 무관 엔진 + 언어 설정표로 바꾸고 Tier |
| hooks | structure-output.mjs | 공장 제작 | 처음 커밋: 3dfd678 feat(struct): R-struct 를 언어 무관 엔진 + 언어 설정표로 바꾸고 Tier |
| hooks | structure-resolve.mjs | 공장 제작 | 처음 커밋: 3dfd678 feat(struct): R-struct 를 언어 무관 엔진 + 언어 설정표로 바꾸고 Tier |
| hooks | structure-rule-barrel.mjs | 공장 제작 | 처음 커밋: 3dfd678 feat(struct): R-struct 를 언어 무관 엔진 + 언어 설정표로 바꾸고 Tier |
| hooks | structure-rule-deep-import.mjs | 공장 제작 | 처음 커밋: 3dfd678 feat(struct): R-struct 를 언어 무관 엔진 + 언어 설정표로 바꾸고 Tier |
| hooks | structure-rule-reexport.mjs | 공장 제작 | 처음 커밋: 3dfd678 feat(struct): R-struct 를 언어 무관 엔진 + 언어 설정표로 바꾸고 Tier |
| hooks | structure-rules-common.mjs | 공장 제작 | 처음 커밋: 3dfd678 feat(struct): R-struct 를 언어 무관 엔진 + 언어 설정표로 바꾸고 Tier |

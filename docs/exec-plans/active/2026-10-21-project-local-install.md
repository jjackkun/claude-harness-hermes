# 2026-10-21-project-local-install — 설치는 그 프로젝트 안에만 (전역 설치 금지 원칙의 규칙화·전파)

## 1. 동기 (Why)

- 2026-10-21 Nbbang-Run 세션: pytest 가 깨져 있어(`~/.local/bin/pytest` → `No module named 'pytest'`, python3.10 시절 pip 설치물을 3.12 가 못 읽음) 에이전트가 `sudo apt-get install -y python3-pytest && rm ~/.local/bin/pytest` 를 권했다.
- 사용자: "위 설치를 하면 우리 프로젝트에만 설치되는거지? 다른 프로젝트에 영향(피해)안주고" → 전역이라는 답을 듣고 **"설치는 항상 자신에게만 되어야지."** → "그 원칙을 공장에 설치나 전파하는 경우에 가능하게 하도록 active 문서로 만들어야 하지 않겠어?"
- 그 프로젝트의 자동 기억(`install-project-local-only.md`)에는 남겼지만 **기억은 그 프로젝트에서만 읽힌다.** 다른 소우주·다음 세션·공장 설치기 자체가 같은 실수를 하지 않으려면 공통 규칙 + 설치기 동작으로 들어가야 한다.
- 실제 영향 조사(2026-10-21, `~/PROJECT` 30개 폴더): 가상환경에 pytest 가 있는 프로젝트 7개는 시스템 설치와 무관, 가상환경 없이 `pytest` 명령에 기대는 프로젝트가 여럿 — 전역 설치는 그 프로젝트들의 시험 결과(플러그인 유무 등)를 말없이 바꾼다.
- **충돌**: 진행 중인 공장 계획 `2026-10-21-pytest-required-bin.md`(G1~G5 구현, 미커밋)는 setup·update-all 이 모든 컴퓨터에 `apt-get install python3-pytest`(시스템 전역)를 자동 실행한다. 이 원칙과 정면으로 어긋난다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 — 공통 규칙에 원칙이 있다: 도구·라이브러리 설치는 프로젝트 안(파이썬 `.venv`, Node 는 lockfile 의 패키지 매니저 devDependencies)으로만 제안·실행하고, `sudo apt-get install`·`pip install --user`·`npm i -g` 같은 전역 설치는 먼저 제안하지 않는다. 전역이 불가피하면 영향 범위(어떤 프로젝트가 바뀌는지)를 먼저 조사해 보이고 선택지로만 낸다.
      `grep -n '프로젝트 안' assets/rules/common/development-workflow.md`
- [x] G2 — 하네스 설치기(setup·update-all)가 시스템 전역 패키지를 자동 설치하지 않는다 — pytest 는 프로젝트 `.venv` 에 깔거나(파이썬 프로젝트일 때), 없으면 "프로젝트 안에 까는 한 줄"을 안내한다. 사용자 파일(`~/.local/bin/*`)을 지우지 않는다.
      `bash tests/tool-installers-test.sh`
- [x] G3 — 설치기가 `.venv/`·`backend/.venv/` 를 `.gitignore` 관리 블록에 넣는다 (가상환경이 저장소에 올라가지 않게).
      `bash tests/gitignore-block-test.sh` (기존 시험에 사례 추가 — 이름은 착수 때 확인)
- [x] G4 — pre-commit R-test 는 지금처럼 프로젝트 가상환경 pytest 를 먼저 쓴다(`pytest_gate.sh` `PYTEST_VENV_DIRS`). 가상환경도 시스템 pytest 도 없을 때의 안내 문구가 전역 설치가 아니라 프로젝트 가상환경 설치를 권한다.
      `grep -n 'venv' assets/hooks/pytest_gate.sh assets/hooks/pre-commit.sh`
- [x] G5 — `update-all` 로 전파되어 원칙이 모든 소우주에 적용된다. **경로 정정(2026-10-21 실측)**: `common` 규칙은 소우주가 아니라 사용자 전역 `~/.claude/rules/common/` 에 하나만 깔린다(`presets/_common.conf:57` `RULES+=(common)` → `public-claude.sh:136` `install_rules "$CLAUDE_DIR"`). 소우주 `.claude/rules/` 에는 프리셋 규칙(harness·python 등)만 있어 원래 문구의 경로는 생기지 않는다.
      `grep -c 'Install Scope' ~/.claude/rules/common/development-workflow.md && cmp ~/.claude/rules/common/development-workflow.md assets/rules/common/development-workflow.md` → 1 · 같음
- [ ] G6 — 공장 시험 전부 초록, 공장 README·CLAUDE.md 개수 표기와 맞음.
      `bash tests/run-all.sh` (이름은 착수 때 확인)

## 2-bis. 착수 전 확인한 사실 (2026-10-21)

| 확인한 것 | 결과 |
| --------- | ---- |
| `pytest_gate.sh` 의 pytest 고르기 | `backend/.venv` → `backend/venv` → `.venv` → `venv` → 시스템 `pytest` 순 (가상환경 우선이 이미 구현됨) |
| `presets/workflow/harness.conf` | `REQUIRED_BINS+=(pytest)` + "설치기가 apt 로 깐다(lib/tool_install_pytest.sh)" — **미커밋**(작업 트리 수정) |
| `lib/tool_install_pytest.sh` | 미추적 새 파일 — `2026-10-21-pytest-required-bin.md` 의 구현 |
| 공장 작업 트리 | 다른 세션의 미커밋 수정 다수 (README.md, ui-prototype SKILL.md, devil-advocate 등) — 이 계획은 그 파일들을 건드리기 전에 그 세션과 순서를 맞춘다 |
| 공통 규칙 폴더 | `assets/rules/common/` — agents · code-review · coding-style · development-workflow · git-workflow · hooks · patterns · performance · security · testing |
| 사용자 전역 규칙 | `~/.claude/CLAUDE.md` §9 "WSL 환경에서는 설치를 사용자가 직접 진행" — 설치 명령은 사용자가 친다 (이 원칙과 함께 간다) |

## 3. 비목표 (Out of Scope)

- 이미 컴퓨터에 깔린 전역 도구를 지우는 일 (사용자 결정 — 경로만 알린다)
- OS 수준 필수 도구(git·bash·python3 자체) — 프로젝트 안에 둘 수 없는 것은 대상 아님. 다만 설치기가 자동으로 깔지 않고 안내만 한다
- 소우주별 가상환경 자동 생성을 모든 프로젝트에 강제 (파이썬 시험이 있는 프로젝트에만)

## 4. 영향 영역

- 규칙: `assets/rules/common/development-workflow.md` (또는 새 `assets/rules/common/install-scope.md` — 착수 때 한 파일 한 책임으로 판단)
- 설치기: `lib/tool_installers.sh`, `lib/tool_install_pytest.sh`(진행 중 계획의 파일 — 방향 전환), `presets/workflow/harness.conf`
- 훅: `assets/hooks/pytest_gate.sh`·`assets/hooks/pre-commit.sh` 안내 문구
- `.gitignore` 관리 블록 생성기
- 시험: `tests/tool-installers-test.sh` 외
- **신규 파일 목록**: (착수 때 확정 — 새 규칙 파일을 만들면 여기에 책임 한 줄과 함께 적는다)

## 5. 단계 (Steps)

### Step 0. 진행 중 계획과 정리 [결정 — 완료 2026-10-21: 방향 전환 후 합침] — `2026-10-21-pytest-required-bin.md` 를 이 원칙에 맞게 고칠지(전역 apt → 프로젝트 .venv), 또는 그 계획을 중단하고 이 계획에 합칠지 사용자 확인
### Step 1. 규칙 문구 [단순] — common 규칙에 원칙 + 이유 + 적용 방법
### Step 2. 시험 먼저 [단순] — 설치기가 전역 설치를 하지 않음 · `.venv` gitignore · 안내 문구
### Step 3. 구현 [단순] — 설치기·훅·gitignore 블록
### Step 4. 실측·전파 [단순] — 공장 시험 초록, update-all 로 소우주 전파, Nbbang-Run 에서 `.venv/bin/pytest` 로 R-test 가 도는지 확인

## 6. 의사결정 로그

- 2026-10-21: 원칙의 출처는 사용자 결정 — "설치는 항상 자신에게만 되어야지." (Nbbang-Run 세션)
- 2026-10-21: 이 계획서는 Nbbang-Run 세션에서 작성. 공장 작업 트리의 다른 세션 수정 파일은 건드리지 않고 계획서 한 장만 추가했다.

- 2026-10-21: Step 0 — `2026-10-21-pytest-required-bin.md` 를 "전역 apt → 프로젝트 가상환경" 으로 바꿔 끝냈다(커밋 4b6b261, completed/ 로 이동). 이 계획의 G2·G3 은 그 커밋이 채웠다.
- 2026-10-21: G1 규칙은 새 파일이 아니라 `assets/rules/common/development-workflow.md` 의 절(Install Scope)로 넣었다 — 설치는 작업 흐름의 한 단계이고, 새 파일은 규칙 개수 표기·설치 목록 시험을 함께 건드린다.
- 2026-10-21: G4 — R-test "건너뜀"·"실행 불가" 두 안내에 프로젝트 가상환경 설치 한 줄 + 전역 금지를 덧붙였다(assets/hooks/pre-commit.sh).
- 2026-10-21: 공장 자신의 `.gitignore` 관리 블록에 `.venv/` 를 넣었다 — 공장에 `.venv` 가 생겼는데 무시되지 않아 `git add -A` 로 커밋될 위험이 있었다. 다음 자기 설치 때 설치기가 같은 줄을 만든다.
- 2026-10-21: jj-agent-room·Nbbang-Run 은 파이썬 시험이 없어 설치기가 건너뛰므로, 사용자 지시로 각 `.venv` 에 pytest 9.1.1 을 손으로 깔았다(전역 무변화 확인).

- 2026-10-21 전파: update-all 12곳 성공(공장 1f0cd33). 영수증·설치 목록 경로만 커밋 — 푸시 9곳: novel-ab d277c47 · novel-bc 296bf8b · rim-kanban 3bd7997 · jjackkun_bot d3b80bb · upbit-ai-trading bb0d946 · terminal-shipping 06dc6512(R-fmt: docs/product-specs/README.md prettier 수정 뒤 재시도, Node v22.23.3) · kis-trading 1aad1e6 · drh-cloth-shop 9d38105 · Nbbang-Run 37c9ea8. jj-agent-room ad38465 은 커밋만(남의 미푸시 기능 커밋 21df22c 가 앞에 있어 푸시 안 함).
- 2026-10-21: zeroday-frontend 는 사용자 지시로 레지스트리에서 뺐다(푸시=자동 배포, 프리징 중). 오늘 전파분은 ea0f5e9 판 재설치로 10-20 상태로 되돌리고 cost-guard 흔적·.venv·사슬 스킬을 지웠다. 원래 미커밋 20건 해시 변화 0, pnpm build:all(Node 22·pnpm 9.15.4) 통과, 커밋·푸시 0.
- 2026-10-21: 깨진 가상환경 3곳(rim-kanban·upbit-ai-trading·kis-trading backend/venv)은 pytest 설치 실패 — 3.10 으로 만든 venv 의 bin/python3 가 지금 3.12 인 /usr/bin/python3 를 가리켜 pip·패키지 전체가 안 보인다. 설치기 범위 밖, 각 프로젝트 가상환경 재생성이 필요.

## 7. 발견·예외

- 2026-10-21 G5 확인(cost-guard 전파 update-all 에 4fe90cd 가 함께 실림): 전역 `~/.claude/rules/common/development-workflow.md` 갱신 11:16, `Install Scope` 1회, 원본과 같음. 소우주 12곳 `.claude/rules/common/` 은 없음 — 설치 구조상 정상. 다른 컴퓨터는 그 컴퓨터에서 update-all 을 돌려야 전역이 갱신된다.
- 2026-10-21 전파 중 `_pytest_venv_of` 결함 발견·수정(4d3c13b) — 가상환경이 없고 파이썬 시험이 있는 소우주(zeroday-frontend)에서 `set -e` 설치기가 조용히 종료. 기록: `docs/exec-plans/completed/2026-10-21-cost-guard-plan.md` §7.

- 2026-10-21: 진행 중 계획 `2026-10-21-pytest-required-bin.md` 의 방향(전역 apt 자동 설치)이 이 원칙과 충돌 — Step 0 에서 사용자 확인 필요. 그 계획의 G5("깨진 pytest 는 지우지 않고 경로만 알림")·실행 성공 판정(G2)은 이 원칙과도 맞아 재사용할 수 있다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:

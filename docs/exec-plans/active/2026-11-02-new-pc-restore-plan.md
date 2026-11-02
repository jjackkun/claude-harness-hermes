# 2026-11-02-new-pc-restore — 포맷한 PC 에서 공장 설치를 한 번에 되살리기

> 작성일: 2026-11-02 (jj-agent-room 세션에서 작성 — 그 저장소의 새 PC 셋업 작업 중 공장 쪽 원인으로 겪은 일)
> 목적: 새로 clone 한 프로젝트에서 **커밋된 프리셋 목록만으로** 공장 설치가 같은 결과로 되살아나고, 넘긴 순서가 결과를 바꾸지 않으며, 설치가 막힐 때 무엇을 깔아야 하는지 말한다.
> 함께 볼 것: jj-agent-room `docs/exec-plans/active/2026-11-02-new-pc-setup-preflight-plan.md` (그 저장소 몫 — 시스템 패키지·Node·uv 를 그 저장소의 첫 세팅 스크립트가 챙김)

## 1. 동기 (Why)

2026-10-30 포맷한 WSL Ubuntu 24.04 PC 에서 jj-agent-room 에 공장 설치(`project-claude.sh`)를 다시 할 때 겪은 일(공장 커밋 `bc3dc19`):

1. **프리셋 목록이 없었다.** `.claude/presets.lock` 은 R-lock(2026-09-23)으로 공장 무시 목록에서 뺐지만, 그 프로젝트 자체 `.gitignore` 의 `.claude/*`(20행, 하네스 블록보다 앞)가 덮어 **커밋되지 않았다**. 하네스 블록은 `!.claude/.factory-manifest.json` 은 넣으면서 `!.claude/presets.lock` 은 넣지 않는다. 포맷과 함께 목록이 사라져, `CLAUDE.md` 관리 블록의 절 순서 · `settings.json` 의 pm2 권한 10/10 · git-write 권한 0/11 을 보고 13개를 역으로 알아냈다.
2. **넘긴 순서가 결과를 바꾼다.** 같은 13개를 다른 순서로 넘기자 `CLAUDE.md` · `settings.json` · `.gitignore` 가 474줄 바뀌었다(내용은 같고 순서만). 원래 순서로 다시 깔아 0줄로 맞췄는데, 2026-11-02 11:15 다른 순서(lang → framework → database → workflow 가나다 → permissions — `setup.sh` 대화형 단계 순서와 같음, 누가 돌렸는지는 확인 안 함)의 재설치가 같은 세 파일을 다시 순서만 바꿨다(`CLAUDE.md` 178줄 · `settings.json` 106줄 · `.gitignore` 2줄).
3. **`project-claude.sh` 가 실행되지 않는다.** git 에 `100644` 로 들어 있어 `Permission denied` — `bash project-claude.sh` 로 불렀다. `public-claude.sh` 도 `100644`(`setup.sh` · `update-all.sh` · `project-codex.sh` · `uninstall.sh` 는 `100755`).
4. **pytest 가상환경 실패가 원인을 말하지 않는다.** Ubuntu 기본 이미지에 `python3-venv`(ensurepip)가 없어 `lib/tool_install_pytest.sh:41` 의 `python3 -m venv` 가 실패 → `[WARN] pytest: 가상환경을 만들지 못했습니다 — 손으로: python3 -m venv .venv …` 만 남았다. 그 명령도 같은 이유로 실패한다. 커밋 게이트 R-test 가 Python 커밋을 막는 상태로 설치가 "성공" 으로 끝났다.

## 2. 목표 (What — 검증 가능한 형태)

공통: 시험은 임시 폴더의 가짜 프로젝트(`git init`)에 설치한다. 실제 프로젝트를 건드리지 않는다.

- [ ] G1 프리셋 목록이 커밋된다 — 프로젝트 `.gitignore` 에 하네스 블록보다 앞서 `.claude/*` 가 있어도, 설치 뒤 `git check-ignore -q .claude/presets.lock` 이 1(무시 안 됨)이다. 하네스 블록에 `!.claude/presets.lock` 을 매니페스트 예외와 같은 자리에 넣는다. 설치 끝의 "실제 추적 여부를 git 에 묻는 경고"(`warn_manifest_untracked`, `lib/harness_installers.sh:619` · 호출 `project-claude.sh:197`)가 presets.lock 도 본다 — 지금은 `rel` 이 `.factory-manifest.json` 으로 고정이라 경로를 인자로 받게 고친다(경고 문구의 `!…` 줄도 그 경로로).
      `bash tests/preset-lock-tracked-test.sh` (기존 R-lock 시험에 "블록보다 앞선 `.claude/*`" 경우를 더한다 — 새 파일을 만들지 않는다)
- [ ] G2 순서와 상관없는 결과 — 같은 프리셋 집합을 서로 다른 순서 3가지로 넘겨 설치하면 `CLAUDE.md` · `.claude/settings.json` · `.gitignore` · `.claude/presets.lock` 이 바이트 단위로 같다. 정렬 기준은 `setup.sh` 단계 순서(lang → framework → database → build → workflow → permissions → tools), 같은 분류 안에서는 이름순 — 지금 소우주들이 이미 받은 11:15 판과 같은 순서라 재설치 차이가 가장 적다.
      `bash tests/preset-order-stable-test.sh`
- [ ] G3 커밋된 목록으로 되살리기 — 프리셋 인자 없이 `project-claude.sh <경로>` 를 부르면 그 프로젝트의 커밋된 `.claude/presets.lock` 을 읽어 설치한다. 목록이 없으면 지금처럼 사용법을 보이고 끝낸다(추측해서 깔지 않음). 새 PC 는 `.installed-projects` 가 비어 `update-all` 이 그 프로젝트를 모르므로 이 길이 필요하다.
      `bash tests/project-claude-restore-test.sh`
- [ ] G4 실행 권한 — `git ls-files -s project-claude.sh public-claude.sh` 가 둘 다 `100755`.
      `git ls-files -s project-claude.sh public-claude.sh | awk '{print $1}' | sort -u` → `100755`
- [ ] G5 venv 실패가 원인과 한 줄을 말한다 — `python3 -c 'import ensurepip'` 가 실패하면, venv 를 새로 만들 때(`lib/tool_install_pytest.sh:41~44`)와 반쯤 만든 `.venv`(`bin/python` 은 있고 pip 없음)에 pip 를 깔다 실패할 때(`:51`) **두 경고 모두** `sudo apt-get install -y python3-venv` 를 보인다. 반쯤 만든 `.venv` 의 경고는 "지우고 다시 설치" 도 함께 보인다.
      (이미 되는 것 — 바꾸지 않는다: 요약의 `failed=pytest` 표기, 반쯤 만든 `.venv` 를 `present` 로 보지 않는 판정(`_pytest_runs_in`). 반쯤 만든 `.venv` 가 `:51` 로 가는 길은 코드를 읽은 추정이다 — S1 시험에서 먼저 확인한다.)
      `bash tests/tool-installers-test.sh` (기존 시험에 ensurepip 없는 가짜 `python3` 경우를 더한다)

## 2-bis. 착수 전 확인한 사실 (2026-11-02, jj-agent-room 세션에서 읽기만)

| 확인한 것 | 결과 |
| --------- | ---- |
| presets.lock 쓰는 곳 | `project-claude.sh:193` — `printf '%s\n' "${PRESETS[@]}" > "$CLAUDE_DIR/presets.lock"` (argv 그대로) |
| 무시 목록 | `lib/harness_installers.sh:650` 주석 — 2026-09-23 R-lock 으로 무시 목록에서 뺐음. 하네스 블록에 `!.claude/presets.lock` 예외는 없음(jj-agent-room `.gitignore` 82~120행 블록에 `!.claude/.factory-manifest.json` 만) |
| jj-agent-room 에서 무시되는 이유 | `git check-ignore -v .claude/presets.lock` → `.gitignore:20:.claude/*` (프로젝트 자체 줄, 블록보다 앞) |
| 실행 권한 | `git ls-files -s`: `project-claude.sh` · `public-claude.sh` 100644 / `setup.sh` · `update-all.sh` · `project-codex.sh` · `uninstall.sh` 100755 |
| pytest | `lib/tool_install_pytest.sh:39-44` — venv 실패 시 `_PYTEST_RESULT=failed` + 경고 한 줄, `return 0`. 설치 요약에는 `Tools (3): present=age-keygen installed=age failed=pytest` |
| update-all 의 대상 | `.installed-projects`(기계별, git 밖)를 읽음 — 새 PC 에서는 비어 있음 |
| 11:15 재설치의 lock 순서 | `node python fastapi svelte postgres redis adhd harness hermes korean mcp skill-dev pm2` |

## 2-ter. 만들기·보기·고치기·지우기 표

| 대상 | 만들기 | 보기 | 고치기 | 지우기 |
|---|---|---|---|---|
| `.claude/presets.lock` | 설치(정렬된 목록) | 설치 끝 추적 경고 · `--restore` 가 읽음 | 다른 프리셋으로 재설치 | ✕ (uninstall 이 관리 파일로 지움 — 지금과 같음) |
| 하네스 블록의 `!.claude/presets.lock` | 설치 | `git check-ignore` | 재설치 | uninstall 이 블록째 |

빈칸 점검: 없음.

## 3. 비목표 (Out of Scope)

- 시스템 패키지를 공장이 sudo 로 깔기 — 공장은 한 줄을 **보이기만** 한다. 각 프로젝트의 첫 세팅 스크립트가 맡는다(jj-agent-room 은 그 저장소 계획에서 처리).
- 전역 `setup.sh` 의 대화형 화면 바꾸기 · `~/.claude/rules` 전역 설치.
- 이미 퍼진 소우주들의 `.gitignore` 를 손으로 고치기 — 다음 `update-all` 이 블록을 다시 쓰며 고친다.
- 11:15 재설치를 누가 돌렸는지 추적.

## 4. 영향 영역

- 코드: `project-claude.sh`(정렬 · 인자 없을 때 lock 읽기 · 실행 비트) · `public-claude.sh`(실행 비트) · `lib/harness_installers.sh`(블록 예외 · 추적 경고) · `lib/tool_install_pytest.sh`(원인 · 반쯤 만든 venv) · `lib/preset.sh`(정렬 함수 — `resolve_preset` 옆).
- 기존 시험 확장: `tests/preset-lock-tracked-test.sh`(G1) · `tests/tool-installers-test.sh`(G5)
- **신규 파일 목록 (파일별 책임 1줄)**:
  - `tests/preset-order-stable-test.sh` — G2: 순서 3가지 → 관리 파일 4개가 같은가
  - `tests/project-claude-restore-test.sh` — G3: 인자 없는 설치가 커밋된 lock 을 읽는가 · 없으면 깔지 않는가
- 룰: R-lock(2026-09-23).
- 퍼짐: 모든 소우주의 `.gitignore` 하네스 블록 한 줄 · 정렬 뒤 첫 재설치에서 `CLAUDE.md`·`settings.json` 순서 차이가 한 번 생길 수 있다(11:15 판과 같은 순서를 고른 이유). `update-all.sh:96` 이 lock 을 읽어 인자로 넘기므로, 정렬 뒤 첫 전파에서 각 소우주의 `.claude/presets.lock` 내용도 한 번 바뀐다(줄 순서만) — 전파 커밋에 함께 실린다.

## 5. 단계 (Steps)

### Step S1. 시험 먼저 [Impl] (G1~G5 RED)

- G1 · G5 는 기존 시험에 경우를 더하고, G2 · G3 은 새 시험 파일. G4 는 한 줄 명령이라 RED 확인만.
- G5 의 가짜 `python3`(`tests/tool-installers-test.sh` 의 것)는 지금 `-m venv` 만 흉내 낸다 — `-c 'import ensurepip'` 실패 분기를 더한다. 이 PC 는 `python3-venv` 가 깔려 있어 `import ensurepip` 가 성공하므로(2026-11-02 실측) 실제 실패는 가짜로만 재현된다.
- 완료: 다섯 목표의 시험이 전부 RED.

### Step S2. lock 추적 [Impl] (G1)

- 하네스 블록에 `!.claude/presets.lock`. `warn_manifest_untracked` 를 경로 인자로 받게 고치고 manifest · lock 을 한 번씩 부른다(각자 `[[ -f ]]` 가드 · 경고는 파일마다 한 묶음).
- 같이 고칠 기존 결함: `lib/harness_installers.sh:629` 의 경고 문구가 큰따옴표 안에서 `` `.claude/*` `` 를 백틱으로 써 명령 치환이 일어난다 — 문구가 깨져 나온다. 백틱을 빼거나 작은따옴표로.
- 완료: `tests/preset-lock-tracked-test.sh` GREEN.

### Step S3. 정렬 [Impl] (G2)

- `PRESETS` 를 분류 순 → 이름순으로 정렬한 뒤 해석·설치·lock 쓰기. `setup.sh` · `update-all.sh` 가 넘기는 순서와 무관해진다.
- 자리: `lib/preset.sh` 에 둔다 — 분류 순서는 이미 `resolve_preset`(`lib/preset.sh:217`)의 `lang framework database build workflow permissions tools` 와 같다. 새 파일을 만들지 않는다.
- 이름순은 `LC_ALL=C sort` 로 고정한다(PC 마다 locale 이 달라 "바이트 단위 동일" 이 깨지지 않게). 같은 이름이 두 분류에 있으면 `resolve_preset` 이 먼저 찾는 분류를 쓴다.
- 완료: `tests/preset-order-stable-test.sh` GREEN.

### Step S4. 되살리기 [Impl] (G3)

- 입구를 바꾼다: 지금 `project-claude.sh:68` 은 `$# -lt 2` 면 사용법 + `exit 1` 이다. 인자가 경로 하나뿐이면 `<경로>/.claude/presets.lock` 을 읽어 `PRESETS` 로 삼고 "커밋된 목록으로 설치: …" 한 줄을 보인다. `--dry-run <경로>` 도 같은 길을 탄다(`-h`·`--list`·인자 0개는 지금 그대로).
- lock 이 없거나, 빈 줄을 뺀 뒤 비어 있으면 지금처럼 사용법 + `exit 1`.
- 모르는 이름이 섞이면 지금의 일괄 해석(`project-claude.sh:98~108`)이 설치 전에 `exit 1` 한다 — 아무것도 깔지 않는다. 복구 모드도 이 길을 그대로 쓴다.
- 시험 경우: lock 있음 · 없음 · 빈 파일 · 빈 줄 섞임 · 모르는 이름(설치물 0개 확인).
- 완료: `tests/project-claude-restore-test.sh` GREEN.

### Step S5. 실행 비트 · venv [Impl] (G4 · G5)

- 실행 비트: `git update-index --chmod=+x project-claude.sh public-claude.sh`(이 저장소 `core.fileMode=true` — 작업 트리 비트도 `chmod +x` 로 맞춘다).
- venv: G5 문구 두 곳.
- 완료: G4 명령이 `100755` · `tests/tool-installers-test.sh` GREEN.

### Step S6. 리뷰 · 퍼뜨리기 [Review — 사용자 확인 뒤]

- 리뷰: `code-reviewer`. 소우주 전파(`update-all`)는 사용자 승인 뒤.
- 전파 전 점검: 소우주 하나의 사본에 정렬 판을 깔고 `CLAUDE.md` · `settings.json` · `.gitignore` · `presets.lock` 의 차이가 **줄 순서뿐인지** 본다(`diff <(sort old) <(sort new)` 가 비어야 함). 내용 차이가 나오면 전파하지 않는다.

### 되돌리기

- 커밋을 되돌리고 `update-all` 로 다시 퍼뜨린다. 블록의 예외 한 줄이 빠질 뿐, lock 파일은 이미 커밋된 소우주에 남는다(해가 없음).

## 6. 의사결정 로그

- 2026-11-02: 정렬 기준을 `setup.sh` 단계 순서 + 이름순으로 — 근거: 11:15 재설치가 이미 그 순서로 jj-agent-room 을 썼다. 다른 기준이면 모든 소우주에 순서 차이가 한 번 더 퍼진다.
- 2026-11-02: lock 이 없으면 추측해서 깔지 않는다 — 근거: jj-agent-room 에서 `CLAUDE.md` 를 보고 역추적했지만, 기계가 추측하면 틀린 프리셋이 매니페스트의 추적된 설치물을 지운다(R-lock 의 2026-09-22 사고).

## 7. 발견·예외

- 2026-11-02 (planner-lite 리뷰): 프로젝트가 `.claude/`(디렉터리째)를 무시하면 git 은 그 안의 `!` 예외를 보지 않는다 — `!.claude/presets.lock` 도 먹지 않는다. 이 경우는 G1 이 고치지 않고 S2 의 추적 경고로만 알린다(manifest 와 같은 한계).
- 2026-11-02 (planner-lite 리뷰): `lib/harness_installers.sh:629` 경고 문구의 백틱 명령 치환 — 기존 결함, S2 에서 함께 고친다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:

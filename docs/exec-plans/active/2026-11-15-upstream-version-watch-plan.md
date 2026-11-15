# 2026-11-15-upstream-version-watch-plan — 밖에서 가져온 에셋의 새 버전을 스스로 알아채기

## 1. 동기 (Why)

- 2026-11-14 apt-curtain 결과 화면이 "AI 스럽다" 는 지적을 받았다. 원인 하나는 공장의 impeccable 사본이 Initial commit 때의 2.1.1 이었던 것이다. 원본은 이미 4.9.1 이었다(명령 3개 → 24개, AI 티 검출기 추가).
- 공장은 밖에서 가져온 스킬·규칙의 **출처와 버전을 적어 두지 않는다.** 그래서 원본이 올라가도 사람이 우연히 발견하기 전까지 모든 소우주가 낡은 판으로 개발한다.
- 사용자 결정(2026-11-15 대화):
  1. 장부를 만든다.
  2. 확인은 **어느 프로젝트(공장·소우주)든 세션을 열 때**, 컴퓨터마다 하루 한 번.
  3. 어디서 발견하든 **작업은 공장에서** 하고 공장이 전파한다. 공장이 언제나 기준이다.
  4. 소우주만 올라간 경우 전파가 그것을 **거꾸로 덮어쓰지 않게** 막는다.
  5. **공장이 없는 컴퓨터(소우주만 받은 곳)에서도 확인은 된다.** 장부와 확인 프로그램을 소우주에도 넣는다. 공장이 없으면 알림만 하고, 올리는 일은 공장이 있는 컴퓨터에서 한다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 공장 장부 `assets/upstream.json` 에 밖에서 온 에셋마다 출처·방식·버전 읽는 곳·기록 버전·관련 시험이 있다 — `bash tests/upstream-ledger-test.sh` (경로 존재 · 필수 칸 · LICENSE/`license:`/원본 URL 이 든 에셋의 누락)
- [x] G2 전수 조사 `docs/audits/2026-11-15-upstream-inventory.md`: 표의 이름 집합 = `assets/` 의 스킬·규칙·에이전트·훅 이름 집합이고, 행마다 분류(공장 제작 / 그대로 / 고쳐 씀 / 확인 못 함) 하나가 있다 — 같은 시험이 이름 집합과 분류 칸을 대조한다. "확인 못 함" 은 통과로 치되 개수를 출력한다.
- [ ] G3 소우주 장부: hermes 프리셋을 쓰는 프로젝트를 설치하면 공장 장부에서 **그 프로젝트에 깐 항목만** 골라 `<프로젝트>/.claude/.upstream.json` 에 쓴다(공장 자기 설치 포함). 깔린 외부 에셋이 없으면 파일을 지운다. 이 파일은 `.gitignore` 블록에 들어가 커밋되지 않고, 설치 영수증에 오르고, 언인스톨이 지운다 — `bash tests/upstream-project-ledger-test.sh` (프리셋에 따라 항목이 달라짐 · 빈 경우 · 재설치 때 갱신 · 영수증에 있음 · 언인스톨 뒤 없음 · 설치한 임시 프로젝트에 `scripts/upstream-check.py` 가 생김 · `settings.json` 에 시작 훅이 등록됨)
- [ ] G4 확인 프로그램 `scripts/upstream-check.py` 가 소우주에도 복사된다(`presets/workflow/hermes.conf` 의 `hermes_scripts` 목록). 다른 `.py` 를 import 하지 않는 한 파일로 둔다. **현재 프로젝트의** `.claude/.upstream.json` 을 읽어, 컴퓨터 공용 상태 `~/.hermes/upstream-status.json` 에서 20시간 안에 확인한 원본은 건너뛰고 나머지만 GitHub 에 묻는다. 결과는 원본(저장소+경로)별로 합쳐 임시 파일 + `mv` 로 쓴다. 항목 일부 실패는 `error` 로 남기고, **전부** 실패(연결 없음·403/429·시간 초과)면 상태를 건드리지 않고 종료 코드 3 — `bash tests/upstream-check-test.sh` (`UPSTREAM_FIXTURE_DIR` 로 가짜 응답: 새 버전 · 같음 · 일부 실패 · 전부 실패 · 한도 초과 · 응답 모양 바뀜 · 장부 깨짐 · 다른 프로젝트가 이미 확인한 원본은 다시 묻지 않음)
- [ ] G5 시작 훅 `assets/hooks/claude-sessionstart-upstream.sh`:
  (a) 컴퓨터 공용 잠금 `mkdir ~/.hermes/upstream-check.lock` 으로 한 번에 하나만 G4 를 뒤에서 돌린다. 잠금 안에 PID·시각을 적고, 10분이 넘은 잠금은 깨고 잡는다. 잠금을 못 잡은 쪽은 건너뛰지 않고 최대 40초 기다린 뒤 상태를 다시 읽어 **남은 원본만** 묻는다. 전부 실패면 `upstream-last-attempt` 를 남기고 1시간 안에는 다시 시도하지 않는다.
  (b) 이 프로젝트에 깐 항목 중 뒤처진 것이 있으면 **컴퓨터마다 하루 한 번** 알린다(`upstream-last-notice`). 알림은 JSON `systemMessage`(사람 화면) + `additionalContext`(모델 문맥) 한 줄이다. 알림은 세션 시작 때 이미 있는 상태로 판단하므로, 원본이 올라간 뒤 첫 확인 다음 세션부터 보인다.
  (c) 알림 문구는 셋이다: 공장이 없으면 "공장이 있는 컴퓨터에서 올려 주세요". 공장이 있고 공장 장부도 낡았으면 "공장에서 올릴까요?". 공장 장부는 이미 최신인데 이 프로젝트만 낡았으면 "공장은 올라가 있습니다 — 이 프로젝트에 전파가 필요합니다".
  (d) 프로젝트 장부가 없거나 `~/.hermes` 를 못 만들면 조용히 끝나고 `.hermes/hooks.log` 에만 남긴다.
  — `bash tests/upstream-sessionstart-test.sh` (가짜 `HOME` · **장부가 서로 다른** 두 프로젝트를 동시에 시작하면 두 장부의 합집합이 모두 확인되고 같은 원본은 1회만 물음 · 10분 넘은 잠금 깨기 · 전부 실패 뒤 1시간 재시도 · 알림 하루 1회 · 문구 셋 · `HERMES_DISABLED=1` · `~/.hermes` 쓰기 불가)
- [ ] G6 공장 위치 기록: 공장이 있는 컴퓨터에서 설치(공장 자기 설치 포함)가 `~/.hermes/factory-path` 에 **메인 저장소 루트**(워크트리면 `git rev-parse --git-common-dir` 의 부모)를 쓴다. 그 경로에 `assets/upstream.json` 이 없으면 쓰지 않는다. 공장이 없는 컴퓨터에는 이 파일이 없다. 설치 시험은 모두 가짜 `HOME` 에서 돌아 진짜 `~/.hermes` 를 건드리지 않는다 — `bash tests/upstream-factory-path-test.sh` (일반 설치 · 워크트리에서 설치 · 장부 없는 경로 · 임시 경로 공장은 기록하지 않음)
- [ ] G7 공장 업데이트 명령 `scripts/upstream-update.py <이름>` (공장에서만 돈다. 소우주 세션은 `factory-path` 로 공장의 이 스크립트를 부른다. 공장이 없으면 부르지 않는다):
  `vendored` 는 원본을 임시 폴더에 받아 `assets/` 를 바꾸고 장부의 `tests` 칸 시험을 돌린 뒤 `recorded` 를 갱신한다. `adapted` 는 덮어쓰지 않고 `recorded.commit..최신` 사이 원본 변경만 보여 준다. 사람이 반영한 뒤 `--mark-reviewed` 로 `recorded` 를 갱신한다 — `bash tests/upstream-update-test.sh` (가짜 원본으로 vendored 교체 · adapted 는 파일 무변경 · mark-reviewed 뒤 상태가 "최신")
- [ ] G8 거꾸로 덮어쓰기 막기: 전파 중 소우주 사본과 공장 사본의 버전을 **둘 다 읽을 수 있고** 소우주가 높으면, 그 항목은 백업·삭제·복사·`manifest_add` 를 모두 건너뛰고 경고와 요약 줄을 남긴다. 버전을 못 읽으면 지금처럼 백업 후 교체한다 — `bash tests/upstream-downgrade-guard-test.sh` (소우주 높음 → 유지 · 같음/낮음 → 교체 · 버전 없음 → 지금 동작 · 사용자 로컬 항목(rc=2) → 지금 동작 · 공장 자기 설치 → 지금 동작)
- [ ] G9 전체 시험 마지막 한 번 — `bash tests/run-all.sh`

## 2-bis. 착수 전 확인한 사실 (2026-11-15)

- 설치는 `lib/installers.sh` `_install_asset` 이 `cp -r` 로 복사하고 `lib/factory_manifest.sh` 의 `.claude/.factory-manifest.json` 에 `{name, kind, factory_commit, sha256}` 를 적는다. 공장 자기 설치(`_is_factory_self`)는 상대 링크다.
- 소우주 사본이 목록 해시와 다르면 `_backup_user_asset` 이 `<이름>.backup-<시각>` 으로 옮기고(rc=1) `_install_asset` 이 곧바로 `rm -rf` + `cp -r` 한다. **소우주에서 올린 새 버전도 이 길로 조용히 내려간다.** `_backup_user_asset` 는 항상 0 을 돌려주므로 "건너뛰기" 신호가 없다 — G8 이 고칠 곳.
- 시작 훅 등록은 `presets/workflow/hermes.conf` 의 `HARNESS_HOOK_SOURCES+=` · `SESSION_START_HOOKS+=` 두 줄이다(81~82행). 원본은 `assets/hooks/` 이고 `scripts/hooks/` 는 설치된 사본이다(드리밍 훅 두 파일이 같음). 소우주에 복사되는 파이썬 스크립트 목록도 같은 파일에 있다(`hermes-dream.py` 등, 270행 부근).
- 이 컴퓨터에 등록된 소우주 4곳(jj-agent-room · drh-cloth-shop · apt-curtain · 공장 자신)은 모두 `hermes` 프리셋을 쓴다. hermes 프리셋이 없는 프로젝트는 이 훅이 깔리지 않는다.
- 드리밍 훅 주석: "SessionStart 훅은 stdout 이 세션 컨텍스트로 주입되므로 아무것도 출력하지 않는다." 이 계획은 알림을 **의도해서** 내보내므로 JSON 출력 한 줄로 한정한다.
- 하루 한 번 시작 훅이 이미 셋 있다(드리밍 20h · 대시보드 24h · 문서 점검 168h). 셋 다 **프로젝트별** 표시 파일이고 검사와 touch 가 따로라 동시 시작 경쟁이 있다. G5 는 `mkdir` 잠금으로 막는다.
- `~/.hermes/` 가 있다(`global.db`, `mesh`, `skills`). 컴퓨터마다 따로이므로 컴퓨터가 둘이면 각자 하루 한 번 확인한다(의도).
- 소우주는 공장 경로를 기록하지 않고, `assets/` 는 소우주에 복사되지 않는다. 그래서 확인에 필요한 장부(그 프로젝트 몫)와 확인 프로그램을 **설치 때 소우주에 넣는다.** 공장 경로는 "올리기" 와 알림 문구에만 쓴다.
- `tests/run-all.sh` 는 `tests/*-test.sh` 를 스스로 찾아 돌리고 파이썬은 `py_compile` 만 한다. 그래서 새 시험은 전부 `*-test.sh` 로 쓴다.
- 이 컴퓨터에 `gh` CLI 가 없다. 확인은 GitHub 공개 API 를 HTTP 로 부른다(인증 없이 시간당 60회).
- `SKILL.md` 최상위에 `version:` 이 있는 스킬은 impeccable 하나다. 규칙·에이전트·훅에는 버전 칸이 없다. 그래서 장부가 항목마다 "버전을 어디서 읽나" 를 정한다.
- 출처가 보이는 에셋(이번에 본 것만): 스킬 impeccable(pbakaus/impeccable), frontend-design·mcp-builder·webapp-testing·skill-creator(LICENSE.txt), 규칙 adhd(ayghri/i-have-adhd), decision-ledger(obra/superpowers).

## 3. 비목표 (Out of Scope)

- 승인 없이 새 버전을 자동으로 까는 것. 확인만 자동이고 적용은 사람이 "올려" 라고 할 때다.
- 공장이 없는 컴퓨터에서 소우주만 직접 올리는 것. 그런 컴퓨터는 알림만 한다.
- 소우주의 npm·pip 의존성 버전 감시.
- impeccable 엔진 바이너리를 프로젝트마다 받게 하는 일 — `2026-11-15-impeccable-4-upgrade.md` G6.
- Codex 세션용 훅.
- 원본이 GitHub 가 아닌 에셋. 장부에 `source.type` 칸을 두고 지금은 `github` 만 처리한다.
- 출처를 아무도 적지 않은 에셋을 기계로 찾는 것. G1 시험은 LICENSE·URL 같은 흔적이 있는 것만 잡는다. 흔적 없는 것은 G2 사람 조사에 기댄다.

## 4. 영향 영역

새 파일:
- `assets/upstream.json` — 공장 장부
- `scripts/upstream-check.py` — 원본 최신 버전 확인 (모델 호출 0, 소우주에도 복사)
- `scripts/upstream-update.py` — 공장에서 한 항목 업데이트 (공장 전용)
- `lib/upstream_ledger.sh` — 공장 장부에서 그 프로젝트 몫을 골라 `.claude/.upstream.json` 을 쓰는 함수만 (G3)
- `lib/upstream_version.sh` — 장부 항목의 버전을 읽고 비교하는 함수만 (G8)
- `lib/factory_path.sh` — 메인 저장소 루트를 구해 `~/.hermes/factory-path` 에 쓰는 함수만 (G6)
- `assets/hooks/claude-sessionstart-upstream.sh` — 시작 훅 (공장에는 설치로 `scripts/hooks/` 사본이 생긴다)
- `tests/upstream-ledger-test.sh` · `tests/upstream-project-ledger-test.sh` · `tests/upstream-check-test.sh` · `tests/upstream-sessionstart-test.sh` · `tests/upstream-factory-path-test.sh` · `tests/upstream-update-test.sh` · `tests/upstream-downgrade-guard-test.sh`
- `docs/audits/2026-11-15-upstream-inventory.md` — 전수 조사

고치는 파일:
- `lib/installers.sh` — `_backup_user_asset` 가 "소우주가 더 새 버전" 이면 3 을 돌려주고, `_install_asset` 이 3 을 받으면 그 항목을 통째로 건너뛴다(G8). 이 파일에는 이것만 고친다.
- `project-claude.sh` — 설치 끝(영수증 시작 177행 이후)에서 `lib/upstream_ledger.sh`(G3)와 `lib/factory_path.sh`(G6)를 한 줄씩 부른다
- `lib/harness_installers.sh` — `.gitignore` 블록(674행 부근)에 `.claude/.upstream.json`
- `lib/uninstall_helpers.sh` — 언인스톨이 `.claude/.upstream.json` 을 지운다(182행 부근, 목록·영수증 옆)
- `presets/workflow/hermes.conf` — 시작 훅 등록 두 줄 + `hermes_scripts` 목록에 `upstream-check.py`
- `README.md` — 새 훅·명령 설명 (readme-sync-before-commit)

## 5. 단계 (Steps)

### Step 1. 전수 조사 + 공장 장부 [Plan/Impl]
`assets/` 의 스킬·규칙·에이전트·훅을 하나씩 보고 넷으로 나눈다: 공장 제작 / 그대로(vendored) / 고쳐 씀(adapted) / 확인 못 함. 근거(LICENSE·원본 URL·커밋 메시지)를 조사 문서에 적는다. 지어내지 않는다. 장부 형식:

```json
{ "version": 1, "items": [
  { "name": "impeccable", "kind": "skills", "path": "assets/skills/impeccable",
    "mode": "vendored",
    "sources": [ { "repo": "pbakaus/impeccable", "path": ".claude/skills/impeccable", "sha": "<git tree sha>" } ],
    "version_from": { "file": "SKILL.md", "frontmatter": "version" },
    "local_patch": { "description_prefix": "<공장이 붙인 한국어 첫 문장> " },
    "skip_files": ["scripts/live-browser.js"],
    "tests": ["tests/claude-md-skill-index-test.sh", "tests/mods-install-test.sh"] } ],
  "untracked": [ { "kind": "agents", "name": "fullstack-developer.md", "origin": "affaan-m/ECC", "reason": "..." } ] }
```
- **바뀜 감지는 git tree/blob sha 로 한다(2026-11-15 구현 중 바꿈).** 원본 저장소마다 `git/trees/HEAD?recursive=1` 을 **한 번** 받아 각 항목 경로의 sha 를 장부 값과 비교한다. 같으면 "같음", 다르면 "바뀜". 처음 계획의 `track: release / path-commit` 은 항목마다 요청이 나가 한도를 넘기 쉬워 뺐다.
- 버전 숫자는 `version_from` 이 있는 항목만 원본 파일(raw.githubusercontent, API 한도 밖)을 읽어 알림에 보인다. 비교는 숫자 마디(`4.9.1` < `4.10.0`). 못 읽으면 "모름" 이고 G8 보호에서 빠진다.
- `local_patch.description_prefix` — 그대로 가져온 스킬에 공장이 붙인 한국어 첫 문장. 업데이트 뒤 다시 붙인다.
- `skip_files` — 공장 게이트 때문에 사본에서 뺀 원본 파일.
- `untracked` — 밖에서 왔지만 감시할 원본 경로를 못 찾은 것.
- 2026-11-15 실측: 항목 50개, 원본 저장소 8개 → 하루 확인 요청 8회.

### Step 2. 설치가 소우주에 넣는 것 [Impl]
설치 끝에 (1) 그 프로젝트 몫 장부 `.claude/.upstream.json`, (2) 공장이 있는 컴퓨터면 `~/.hermes/factory-path`. 확인 프로그램은 `hermes.conf` 스크립트 목록으로 복사된다.

### Step 3. 확인 프로그램 [Impl]
현재 프로젝트 장부를 읽는다. 컴퓨터 공용 상태에서 원본별 `checked_at` 이 20시간 안이면 건너뛴다. 요청 하나 10초·전체 30초 제한. `HTTPS_PROXY` 는 파이썬 `urllib` 기본 동작을 따른다. 상태 형식 `{sources: {"<repo>:<path>": {checked_at, latest_version, latest_commit, error?}}}`. 프로젝트별 "뒤처짐" 판정은 알릴 때 그 프로젝트 장부의 `recorded` 와 상태를 비교해서 한다.

### Step 4. 시작 훅 [Impl]
드리밍 훅의 문(비활성 스위치 · startup/resume 만 · 백그라운드 분리)을 따르되 잠금은 `mkdir` 이다. 알림 문구 예:
- 공장 있음: `[upstream] 새 버전 2개: impeccable 4.9.1→5.0.0 · adhd 원본 바뀜 — "공장에서 올려" 라고 하세요.`
- 공장 없음: `[upstream] 새 버전 2개: impeccable 4.9.1→5.0.0 · adhd 원본 바뀜 — 공장이 있는 컴퓨터에서 올려 주세요.`
이미 설치된 소우주는 다음 전파(update-all) 때 훅·프로그램·장부가 생긴다.

### Step 5. 공장 업데이트 명령 [Impl]
공장 경로에서 일한다. 커밋·전파는 기존 규칙대로 사람이 시킨 뒤에 한다.

### Step 6. 거꾸로 덮어쓰기 막기 [Impl]
`lib/upstream_version.sh` 로 양쪽 버전을 읽어 비교한다. rc=1(공장 설치물이 로컬에서 바뀜) 길에서만 본다. 건너뛴 항목은 설치 요약에 "공장보다 새 버전이라 건너뜀: <이름> — 공장을 먼저 올리세요" 로 남는다. 목록 해시가 계속 어긋나므로 다음 전파 때도 같은 경고가 나온다(공장을 올리면 사라진다).

### Step 7. 검증·문서·전파 [Review]
새 시험 7개 → 전체 시험 1회 → README → `code-reviewer`(설치기·네트워크 호출을 바꾸므로) → 사용자가 시키면 update-all 로 전파.

## 6. 의사결정 로그

- 장부(그 프로젝트 몫)와 확인 프로그램을 소우주에 넣는다 — 사용자 결정 5 "공장 없는 컴퓨터에서도 확인" — 확인 방식을 고치면 전파해야 소우주에 반영된다.
- 확인 간격은 원본별로 컴퓨터 공용 상태에 둔다 — 프로젝트마다 깔린 외부 에셋이 달라서, 컴퓨터 하나의 표시 파일로는 먼저 연 프로젝트 몫만 확인된다 — 공용 상태가 깨지면 모든 프로젝트가 다시 묻는다(상태 파일은 `mv` 로 통째 교체한다).
- 알림은 하루 한 번만, 사람 화면과 모델 문맥에 한 줄씩 — 매 세션 반복하면 소음이 되고, 모델이 알아야 "공장에서 올릴까요" 를 제안할 수 있다 — 하루 안에 다른 프로젝트에서는 알림이 안 보인다.
- 공장이 없는 컴퓨터는 알림만 한다 — 공장이 언제나 기준이라는 사용자 결정 3 — 그 컴퓨터에서는 바로 올릴 수 없다.
- 전부 실패면 1시간 뒤 재시도 — 오프라인 하루를 통째로 잃지 않으려고 — 오프라인이 길면 세션을 열 때(1시간 간격) 짧은 요청이 뒤에서 나간다.
- 적용은 자동으로 하지 않는다 — 4.x 는 `.impeccable.md` 를 안 읽었고 큰 파일이 게이트에 막혔고 엔진 결정이 따라왔다 — 사람이 "올려" 를 말해야 새 판이 들어온다.
- `adapted` 는 덮어쓰지 않고 바뀐 부분만 보인다 — 한국어로 옮긴 규칙을 덮으면 공장 수정이 사라진다 — 반영과 `--mark-reviewed` 는 사람 몫이다.
- GitHub 공개 API 를 인증 없이 쓴다 — `gh` 가 없고 토큰을 다루지 않기 위해 — 시간당 60회 제한.
- 바뀜 감지를 원본 저장소당 트리 1회 요청으로 한다 — 항목 50개를 하나씩 물으면 무인증 60회 한도에 걸린다 — 트리가 아주 커서 GitHub 가 잘라 보내면(`truncated`) 그 저장소는 "모름" 이 된다(ECC 6,449개는 잘리지 않음).
- 장부 sha 의 기준선은 2026-11-15 원본이다 — 복사 당시 판을 기록한 적이 없어 알 수 없다 — 그 전에 원본에서 바뀐 것은 "바뀜" 으로 잡히지 않는다(조사 문서의 유사도 값으로만 보인다).
- 버전을 못 읽는 항목은 G8 보호에서 빠진다 — 지금 동작을 깨지 않으려고 — 그 항목은 여전히 내려갈 수 있다.
- `factory-path` 는 장부가 있는 메인 저장소 루트만 기록한다 — 워크트리·임시 사본이 기록되면 사라진 경로를 가리킨다 — 공장 클론이 여럿이면 마지막으로 설치한 클론이 기준이 된다.
- 시작 훅·확인 프로그램·프로젝트 장부는 hermes 프리셋일 때만 넣는다 — 드리밍·대시보드 훅과 같은 자리이고 이 컴퓨터의 소우주 4곳이 모두 hermes 를 쓴다 — hermes 를 안 쓰는 프로젝트는 확인하지 않는다.
- 프로젝트 장부는 커밋하지 않는다(`.gitignore`) — 설치가 매번 다시 쓰는 파일이라 커밋하면 버전이 바뀔 때마다 diff 가 생긴다 — 다른 컴퓨터에서 clone 만 하고 설치를 안 하면 장부가 없어 확인하지 않는다.
- 잠금을 못 잡으면 기다렸다가 남은 원본만 묻는다 — 장부가 다른 두 프로젝트가 동시에 열릴 때 한쪽 몫이 그날 빠지지 않게 — 늦게 연 세션의 확인이 최대 40초 늦다(뒤에서 돌아 작업은 막지 않는다).

## 7. 발견·예외

- 2026-11-15 planner-lite 1차 리뷰(HIGH 6 · MEDIUM 10 · LOW 4)를 코드로 확인하고 반영했다: 시작 훅 stdout 이 모델 문맥에 들어감 → JSON 한 줄·하루 1회, `_backup_user_asset` 에 건너뛰기 신호 없음 → 반환값 3, 동시 시작 경쟁 → `mkdir` 잠금, 파이썬 시험은 러너가 안 돎 → 전부 `*-test.sh`, 훅 원본은 `assets/hooks/` 한 곳.
- 2026-11-15 사용자 지적: "공장 없이 소우주만 받은 컴퓨터에서는 확인이 안 된다." 1차 반영안(확인 프로그램·장부를 공장 경로에서 읽기)이 그 경우를 놓쳤다. 장부(프로젝트 몫)·프로그램을 소우주에 넣고, 공장 경로는 올리기·알림 문구에만 쓰도록 바꿨다.
- 2026-11-15 planner-lite 2차 리뷰(HIGH 1 · MEDIUM 4 · LOW 2)를 코드로 확인하고 반영했다: 언인스톨이 새 파일을 안 지움(`uninstall_helpers.sh` 182~184행) → 지우기 추가, git 추적 정책 없음 → `.gitignore`, 낡은 잠금 → 10분 뒤 깨기, 잠금 못 잡은 프로젝트 몫 누락 → 기다렸다 남은 원본만, "설치 끝" 은 `installers.sh` 가 아니라 `project-claude.sh`, 공장은 최신인데 프로젝트만 낡은 경우 → 알림 문구 셋, 복사·훅 등록·HOME 격리 단언 추가.

## 8. 회고 (완료 시 작성)

# 2026-11-15-upstream-version-watch-plan — 밖에서 가져온 에셋의 새 버전을 스스로 알아채기

## 1. 동기 (Why)

- 2026-11-14 apt-curtain 결과 화면이 "AI 스럽다" 는 지적을 받았다. 원인 하나는 공장의 impeccable 사본이 Initial commit 때의 2.1.1 이었던 것이다. 원본은 이미 4.9.1 이었다(명령 3개 → 24개, AI 티 검출기 추가).
- 공장은 밖에서 가져온 스킬·규칙의 **출처와 버전을 적어 두지 않는다.** 그래서 원본이 올라가도 사람이 우연히 발견하기 전까지 모든 소우주가 낡은 판으로 개발한다.
- 사용자 결정(2026-11-15 대화):
  1. 장부를 만든다.
  2. 확인은 **어느 프로젝트(공장·소우주)든 세션을 열 때**, 컴퓨터마다 하루 한 번.
  3. 어디서 발견하든 **작업은 공장에서** 하고 공장이 전파한다. 공장이 언제나 기준이다.
  4. 소우주만 올라간 경우 전파가 그것을 **거꾸로 덮어쓰지 않게** 막는다.

## 2. 목표 (What — 검증 가능한 형태)

- [ ] G1 공장 위치 기록: 설치(공장 자기 설치 포함)가 `~/.hermes/factory-path` 에 **메인 저장소 루트**(워크트리면 `git rev-parse --git-common-dir` 의 부모)를 쓴다. 그 경로에 `assets/upstream.json` 이 없으면 쓰지 않는다 — `bash tests/upstream-factory-path-test.sh` (일반 설치 · 워크트리에서 설치 · 장부 없는 경로)
- [ ] G2 장부 `assets/upstream.json` 에 밖에서 온 에셋마다 출처·방식·기록 버전·관련 시험이 있다 — `bash tests/upstream-ledger-test.sh` (경로 존재 · 필수 칸 · LICENSE/`license:`/원본 URL 이 든 에셋의 누락)
- [ ] G3 전수 조사 `docs/audits/2026-11-15-upstream-inventory.md`: 표의 이름 집합 = `assets/` 의 스킬·규칙·에이전트·훅 이름 집합이고, 행마다 분류(공장 제작 / 그대로 / 고쳐 씀 / 확인 못 함) 하나가 있다 — 같은 시험이 이름 집합과 분류 칸을 대조한다. "확인 못 함" 은 통과로 치되 개수를 출력한다.
- [ ] G4 확인 스크립트 `scripts/upstream-check.py`: 공장 장부를 읽어 원본 최신 버전을 묻고 `~/.hermes/upstream-status.json` 에 임시 파일 + `mv` 로 쓴다. 항목 일부 실패는 그 항목에 `error` 를 남기고 나머지를 쓴다. **전부** 실패(연결 없음·한도 초과 403/429·시간 초과)면 상태 파일을 건드리지 않고 종료 코드 3 — `bash tests/upstream-check-test.sh` (`UPSTREAM_FIXTURE_DIR` 로 가짜 응답: 새 버전 · 같음 · 일부 실패 · 전부 실패 · 한도 초과 · 응답 모양 바뀜 · 장부 깨짐)
- [ ] G5 시작 훅 `assets/hooks/claude-sessionstart-upstream.sh`:
  (a) 컴퓨터 공용 잠금 `mkdir ~/.hermes/upstream-check.lock` 으로 한 번에 하나만 돌고, 성공했을 때만 `upstream-last-check` 를 갱신한다(20시간). 전부 실패면 `upstream-last-attempt` 만 갱신하고 1시간 뒤 다시 시도한다.
  (b) 뒤처진 항목이 있으면 **컴퓨터마다 하루 한 번** 알린다(`upstream-last-notice`). 알림은 JSON `systemMessage`(사람 화면) + `additionalContext`(모델이 "공장에서 올릴까요" 를 제안하도록) 한 줄이다.
  (c) `~/.hermes` 를 못 만들거나 공장 경로가 없으면 조용히 끝나고 `.hermes/hooks.log` 에만 남긴다.
  — `bash tests/upstream-sessionstart-test.sh` (두 프로젝트에서 **동시에** 2개 실행해도 확인 1회 · 20시간 안 재실행 안 함 · 전부 실패 뒤 1시간 재시도 · 알림 하루 1회 · `HERMES_DISABLED=1` · `~/.hermes` 쓰기 불가)
- [ ] G6 공장 업데이트 명령 `scripts/upstream-update.py <이름>` (공장에서만 돈다. 소우주 세션은 `factory-path` 로 이 스크립트를 부른다):
  `vendored` 는 원본을 임시 폴더에 받아 `assets/` 를 바꾸고 장부의 `tests` 칸 시험을 돌린 뒤 `recorded` 를 갱신한다. `adapted` 는 덮어쓰지 않고 `recorded.commit..최신` 사이 원본 변경만 보여 준다. 사람이 반영한 뒤 `--mark-reviewed` 로 `recorded` 를 갱신한다 — `bash tests/upstream-update-test.sh` (가짜 원본으로 vendored 교체 · adapted 는 파일 무변경 · mark-reviewed 뒤 상태가 "최신")
- [ ] G7 거꾸로 덮어쓰기 막기: 전파 중 소우주 사본과 공장 사본의 버전을 **둘 다 읽을 수 있고** 소우주가 높으면, 그 항목은 백업·삭제·복사·`manifest_add` 를 모두 건너뛰고 경고와 요약 줄을 남긴다. 버전을 못 읽으면 지금처럼 백업 후 교체한다 — `bash tests/upstream-downgrade-guard-test.sh` (소우주 높음 → 유지 · 같음/낮음 → 교체 · 버전 없음 → 지금 동작 · 사용자 로컬 항목(rc=2) → 지금 동작 · 공장 자기 설치 → 지금 동작)
- [ ] G8 전체 시험 마지막 한 번 — `bash tests/run-all.sh`

## 2-bis. 착수 전 확인한 사실 (2026-11-15)

- 설치는 `lib/installers.sh` `_install_asset` 이 `cp -r` 로 복사하고 `lib/factory_manifest.sh` 의 `.claude/.factory-manifest.json` 에 `{name, kind, factory_commit, sha256}` 를 적는다. 공장 자기 설치(`_is_factory_self`)는 상대 링크다.
- 소우주 사본이 목록 해시와 다르면 `_backup_user_asset` 이 `<이름>.backup-<시각>` 으로 옮기고(rc=1) `_install_asset` 이 곧바로 `rm -rf` + `cp -r` 한다. **소우주에서 올린 새 버전도 이 길로 조용히 내려간다.** `_backup_user_asset` 는 항상 0 을 돌려주므로 "건너뛰기" 신호가 없다 — G7 이 고칠 곳.
- 시작 훅 등록은 `presets/workflow/hermes.conf` 의 `HARNESS_HOOK_SOURCES+=` · `SESSION_START_HOOKS+=` 두 줄이다(81~82행). 원본은 `assets/hooks/` 이고 `scripts/hooks/` 는 설치된 사본이다(드리밍 훅 두 파일이 같음).
- 드리밍 훅 주석: "SessionStart 훅은 stdout 이 세션 컨텍스트로 주입되므로 아무것도 출력하지 않는다." 이 계획은 알림을 **의도해서** 내보내므로 JSON 출력 한 줄로 한정한다.
- 하루 한 번 시작 훅이 이미 셋 있다(드리밍 20h · 대시보드 24h · 문서 점검 168h). 셋 다 **프로젝트별** 표시 파일이고 검사와 touch 가 따로라 동시 시작 경쟁이 있다. G5 는 `mkdir` 잠금으로 막는다.
- `~/.hermes/` 가 있다(`global.db`, `mesh`, `skills`). 컴퓨터마다 따로이므로 컴퓨터가 둘이면 각자 하루 한 번 확인한다(의도).
- 소우주는 공장 경로를 기록하지 않는다. `assets/` 는 소우주에 복사되지 않는다. 그래서 훅은 확인 스크립트와 장부를 **공장 경로에서** 읽는다(스크립트를 소우주에 복사하지 않는다 → `hermes.conf` 스크립트 복사 목록은 바꾸지 않는다).
- `tests/run-all.sh` 는 `tests/*-test.sh` 를 스스로 찾아 돌리고 파이썬은 `py_compile` 만 한다. 그래서 새 시험은 전부 `*-test.sh` 로 쓴다.
- 이 컴퓨터에 `gh` CLI 가 없다. 확인은 GitHub 공개 API 를 HTTP 로 부른다(인증 없이 시간당 60회).
- `SKILL.md` 최상위에 `version:` 이 있는 스킬은 impeccable 하나다. 규칙·에이전트·훅에는 버전 칸이 없다. 그래서 장부가 항목마다 "버전을 어디서 읽나" 를 정한다.
- 출처가 보이는 에셋(이번에 본 것만): 스킬 impeccable(pbakaus/impeccable), frontend-design·mcp-builder·webapp-testing·skill-creator(LICENSE.txt), 규칙 adhd(ayghri/i-have-adhd), decision-ledger(obra/superpowers).

## 3. 비목표 (Out of Scope)

- 승인 없이 새 버전을 자동으로 까는 것. 확인만 자동이고 적용은 사람이 "올려" 라고 할 때다.
- 소우주의 npm·pip 의존성 버전 감시.
- impeccable 엔진 바이너리를 프로젝트마다 받게 하는 일 — `2026-11-15-impeccable-4-upgrade.md` G6.
- Codex 세션용 훅.
- 원본이 GitHub 가 아닌 에셋. 장부에 `source.type` 칸을 두고 지금은 `github` 만 처리한다.
- 출처를 아무도 적지 않은 에셋을 기계로 찾는 것. G2 시험은 LICENSE·URL 같은 흔적이 있는 것만 잡는다. 흔적 없는 것은 G3 사람 조사에 기댄다.

## 4. 영향 영역

새 파일:
- `assets/upstream.json` — 장부
- `scripts/upstream-check.py` — 원본 최신 버전 확인 (모델 호출 0)
- `scripts/upstream-update.py` — 공장에서 한 항목 업데이트
- `lib/upstream_version.sh` — 장부 항목의 버전을 읽고 비교하는 함수만 (G7 이 씀)
- `lib/factory_path.sh` — 메인 저장소 루트를 구해 `~/.hermes/factory-path` 에 쓰는 함수만 (G1)
- `assets/hooks/claude-sessionstart-upstream.sh` — 시작 훅 (공장에는 설치로 `scripts/hooks/` 사본이 생긴다)
- `tests/upstream-factory-path-test.sh` · `tests/upstream-ledger-test.sh` · `tests/upstream-check-test.sh` · `tests/upstream-sessionstart-test.sh` · `tests/upstream-update-test.sh` · `tests/upstream-downgrade-guard-test.sh`
- `docs/audits/2026-11-15-upstream-inventory.md` — 전수 조사

고치는 파일:
- `lib/installers.sh` — `_backup_user_asset` 가 "소우주가 더 새 버전" 이면 3 을 돌려주고, `_install_asset` 이 3 을 받으면 그 항목을 통째로 건너뛴다(G7). 설치 끝에 `factory_path` 기록(G1)
- `presets/workflow/hermes.conf` — 시작 훅 등록 두 줄
- `README.md` — 새 훅·명령 설명 (readme-sync-before-commit)

## 5. 단계 (Steps)

### Step 1. 전수 조사 + 장부 [Plan/Impl]
`assets/` 의 스킬·규칙·에이전트·훅을 하나씩 보고 넷으로 나눈다: 공장 제작 / 그대로(vendored) / 고쳐 씀(adapted) / 확인 못 함. 근거(LICENSE·원본 URL·커밋 메시지)를 조사 문서에 적는다. 지어내지 않는다. 장부 형식:

```json
{ "version": 1, "items": [
  { "name": "impeccable", "kind": "skills", "path": "assets/skills/impeccable",
    "mode": "vendored",
    "source": { "type": "github", "repo": "pbakaus/impeccable", "path": ".claude/skills/impeccable", "track": "release" },
    "version_from": { "file": "SKILL.md", "frontmatter": "version" },
    "recorded": { "version": "4.9.1", "commit": "1b2aa57" },
    "tests": ["tests/claude-md-skill-index-test.sh", "tests/mods-install-test.sh"] } ] }
```
- `track: release` — 최신 릴리스 태그. 버전 비교는 숫자 마디 비교(`4.9.1` < `4.10.0`). 숫자로 못 읽으면 "모름".
- `track: path-commit` — 그 경로의 최신 커밋. 순서가 없으므로 "바뀜/같음" 만 말하고 G7 보호에서 빠진다.
- `version_from` 이 없는 항목은 G7 보호에서 빠진다.
- 항목이 20개를 넘으면 무인증 60회 한도에 가까우므로 §6 을 다시 본다.

### Step 2. 공장 위치 기록 [Impl]
`lib/factory_path.sh` + 설치 끝에서 호출. G4·G5·G6 이 모두 이것에 기댄다.

### Step 3. 확인 스크립트 [Impl]
장부를 공장 경로에서 읽는다. 항목당 요청 1회, 요청 하나 10초·전체 30초 제한. `HTTPS_PROXY` 는 파이썬 `urllib` 기본 동작을 따른다. 결과 `{checked_at, items:[{name, mode, recorded, latest, state: behind|same|changed|unknown|error}]}`.

### Step 4. 시작 훅 [Impl]
드리밍 훅의 문(비활성 스위치 · startup/resume 만 · 백그라운드 분리)을 따르되, 표시 파일은 컴퓨터 공용이고 잠금은 `mkdir` 이다. 알림 문구 예: `[upstream] 새 버전 2개: impeccable 4.9.1→5.0.0 · adhd 원본 바뀜 — "공장에서 올려" 라고 하세요.` `hermes.conf` 에 등록한다. 이미 설치된 소우주는 다음 전파(update-all) 때 훅이 생긴다.

### Step 5. 공장 업데이트 명령 [Impl]
Step 2 의 공장 경로에서 일한다. 커밋·전파는 기존 규칙대로 사람이 시킨 뒤에 한다.

### Step 6. 거꾸로 덮어쓰기 막기 [Impl]
`lib/upstream_version.sh` 로 양쪽 버전을 읽어 비교한다. rc=1(공장 설치물이 로컬에서 바뀜) 길에서만 본다. 건너뛴 항목은 설치 요약에 "공장보다 새 버전이라 건너뜀: <이름> — 공장을 먼저 올리세요" 로 남는다. 목록 해시가 계속 어긋나므로 다음 전파 때도 같은 경고가 나온다(공장을 올리면 사라진다).

### Step 7. 검증·문서·전파 [Review]
새 시험 6개 → 전체 시험 1회 → README → `code-reviewer`(설치기·네트워크 호출을 바꾸므로) → 사용자가 시키면 update-all 로 전파.

## 6. 의사결정 로그

- 확인 표시·잠금·상태를 컴퓨터 공용(`~/.hermes/`)으로 둔다 — 사용자 결정 "어느 프로젝트에서 열든, 하루 한 번" — 공용 파일이 깨지면 모든 프로젝트에서 확인이 멈춘다(상태 파일은 `mv` 로 통째 교체해 반쯤 쓰인 상태를 막는다).
- 확인 스크립트와 장부는 소우주에 복사하지 않고 공장 경로에서 읽는다 — 확인 방식이 바뀌어도 전파 없이 바로 적용되고, 장부가 한 벌뿐이다 — 공장 경로가 틀리면 그 컴퓨터에서 확인이 멈춘다(G5 c 로 조용히 끝나고 로그에 남는다).
- 알림은 하루 한 번만, 사람 화면과 모델 문맥에 한 줄씩 — 매 세션 반복하면 소음이 되고, 모델이 알아야 "공장에서 올릴까요" 를 제안할 수 있다 — 하루 안에 다른 프로젝트에서는 알림이 안 보인다.
- 전부 실패면 성공 표시를 갱신하지 않고 1시간 뒤 재시도 — 오프라인 하루를 통째로 잃지 않으려고 — 오프라인이 길면 세션을 열 때마다(1시간 간격) 짧은 요청이 뒤에서 나간다.
- 적용은 자동으로 하지 않는다 — 4.x 는 `.impeccable.md` 를 안 읽었고 큰 파일이 게이트에 막혔고 엔진 결정이 따라왔다 — 사람이 "올려" 를 말해야 새 판이 들어온다.
- `adapted` 는 덮어쓰지 않고 바뀐 부분만 보인다 — 한국어로 옮긴 규칙을 덮으면 공장 수정이 사라진다 — 반영과 `--mark-reviewed` 는 사람 몫이다.
- GitHub 공개 API 를 인증 없이 쓴다 — `gh` 가 없고 토큰을 다루지 않기 위해 — 시간당 60회 제한.
- 버전을 못 읽는 항목과 `path-commit` 항목은 G7 보호에서 빠진다 — 지금 동작을 깨지 않으려고 — 그 항목은 여전히 내려갈 수 있다.
- `factory-path` 는 장부가 있는 메인 저장소 루트만 기록한다 — 워크트리·임시 사본이 기록되면 사라진 경로를 가리킨다 — 공장 클론이 여럿이면 마지막으로 설치한 클론이 기준이 된다.

## 7. 발견·예외

- 2026-11-15 planner-lite 리뷰(HIGH 6 · MEDIUM 10 · LOW 4)를 코드로 확인하고 반영했다: 소우주에 스크립트·장부가 없음 → 공장 경로에서 읽기, 시작 훅 stdout 이 모델 문맥에 들어감 → JSON 한 줄·하루 1회, `_backup_user_asset` 에 건너뛰기 신호 없음 → 반환값 3, 동시 시작 경쟁 → `mkdir` 잠금, 파이썬 시험은 러너가 안 돎 → 전부 `*-test.sh`, 훅 원본은 `assets/hooks/` 한 곳.

## 8. 회고 (완료 시 작성)

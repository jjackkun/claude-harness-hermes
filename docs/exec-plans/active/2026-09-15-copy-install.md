# 2026-09-15-copy-install — 복사 설치 전환 (symlink 설치 폐지)

> 헤르메스 우주 구현 계획 **1/5**. 설계 원천: `docs/hermes-universe/design/world/copy-install.md`, 결정 I-01~I-03 · E-02~E-04 · L-03 · L-04 · RV-13.
> 순서 근거: G-24 — 뒷문(symlink)이 열려 있는 한 제안·허가 흐름(계획 5)이 무의미하고, zeroday-frontend 가 공장 없는 컴퓨터에서 돌아야 한다.
> 다음 계획: `2026-09-15-universe-id-journal.md`.

## 1. 동기 (Why)

- Linux/macOS 설치는 스킬·규칙·에이전트를 공장 `assets/` 로 향하는 **절대경로 symlink** 로 깐다(`lib/installers.sh:61-65, 86-90, 112-116`). Windows 경로만 복사.
- zeroday-frontend 에 절대경로 링크 **41개가 git 에 커밋**돼 있다(모드 120000). 다른 컴퓨터·동료 clone 에서는 존재하지 않는 경로를 가리킨다.
- 소우주에서 공통 스킬을 고치면 **허가 없이 공장 원본이 바뀌고 전 소우주에 즉시 퍼진다**(뒷문). 2026-09-15 세션 시작 시점에 미커밋 `assets/skills/hermes-loop/SKILL.md` 수정이 링크로 전 소우주에 반영된 상태였다.
- 소우주가 어느 공장 버전을 보는지 기록이 없어 제안 봉투의 `base`(계획 5)를 채울 수 없다.
- 공장 자기 설치도 절대경로 링크 25개가 커밋돼 있어 다른 경로에서 clone 하면 공장 자체가 깨진다.
- 2026-09-15 실측: 이 컴퓨터의 `.installed-projects` 에는 3곳(ai-create · wonil · terminal-shipping)만 등록돼 있고 **zeroday-frontend 는 없다**. zeroday 이전은 `update-all` 이 아니라 명시 실행이 필요하다.

## 2. 목표 (What — 검증 가능한 형태)

- [ ] 목표 1 — 설치기가 OS 와 무관하게 **복사**한다. 검증: 임시 프로젝트에 `project-claude.sh <tmp> harness hermes` 후 `find <tmp>/.claude/{skills,rules,agents} -type l | wc -l` = 0.
- [ ] 목표 2 — 설치 목록 `.claude/.factory-manifest.json` 이 생기고 항목 수가 SKILLS+AGENTS+RULES 와 같으며 각 항목에 `name · kind · factory_commit · sha256` 이 있다. 검증: `tests/copy-install-test.sh` 의 manifest 절.
- [ ] 목표 3 — 낡은 항목 정리가 **링크 여부가 아니라 설치 목록 기준**이다. 검증: 소우주 자체 스킬 폴더(`<tmp>/.claude/skills/my-own/`)를 두고 프리셋에서 스킬 하나를 뺀 뒤 재설치 → 뺀 스킬은 지워지고 `my-own` 은 남는다(테스트).
- [ ] 목표 4 — 설치 목록에 있는 파일을 세션 안에서 편집하면 훅이 경고한다. 검증: `tests/copy-install-test.sh` 의 tamper 절 — PostToolUse 입력을 흉내 내 `[factory-tamper WARN]` 출력.
- [ ] 목표 5 — `.hermes/factory.json` 에 `remote_url` · `installed_version`(공장 HEAD 해시)이 기록된다. 검증: 설치 후 `python3 -c "import json;d=json.load(open('.hermes/factory.json'));assert d['remote_url'] and len(d['installed_version'])==40"`.
- [ ] 목표 6 — 공장 자기 설치는 **저장소 안 상대경로 링크**다. 검증: 공장에서 `find .claude -type l -exec readlink {} \; | grep -c '^/'` = 0, 그리고 `git ls-files -s .claude | grep -c 120000` 의 링크가 모두 `../../assets/...` 형태.
- [ ] 목표 7 — 세션 시작 훅이 깨진 링크를 감지해 재설치를 안내한다. 검증: 테스트에서 링크 대상을 지운 뒤 훅 실행 → `[factory-link WARN]` 출력.
- [ ] 목표 8 — 공장의 모순 결정화 스킬 2개(`.hermes/skills/repository-isolation-principle.md`, `unified-hook-deployment.md`)가 삭제되고 `skill_index` 에서 tombstone 된다. 검증: 파일 없음 + `hermes-search.py` 가 주입하지 않음.
- [ ] 목표 9 — 기존 테스트 전부 통과. 검증: `bash tests/run-all.sh` 0 실패, `tests/update-all-roundtrip-test.sh` · `tests/uninstall-roundtrip-test.sh` · `tests/windows-helpers-test.sh` 포함.
- [ ] 목표 10 — zeroday-frontend 이전: 링크 41개가 복사본으로 바뀐 상태를 **사용자가 커밋**한다. 검증: zeroday 에서 `git ls-files -s .claude | grep -c 120000` = 0, `.claude/.factory-manifest.json` 추적됨.
- [ ] 목표 11 — 제거도 설치 목록 기준이다: `uninstall.sh` 가 manifest 항목만 지우고 소우주 자체 스킬은 남긴다. 검증: `tests/uninstall-roundtrip-test.sh` 통과 + 자체 스킬 폴더 잔존 케이스 추가.
- [ ] 목표 12 — `is_windows_path` 분기가 설치·정리·백업 세 함수에서 사라지고 한 경로만 남는다. 검증: `grep -c is_windows_path lib/installers.sh` = 0, `tests/windows-helpers-test.sh` · `tests/windows-smoke.sh` 통과. `lib/harness_installers.sh:719-723` 의 `ln -s` 는 메모리 폴더 링크(E-04, 범위 밖)라 남는다 — 테스트가 "저장소 안 `ln -s` 는 이 한 곳뿐" 을 `grep -n 'ln -s' lib/*.sh` 로 고정.
- 비목표 추가(planner-lite 지적): 복사 설치로 소우주 저장소가 커진다 — 공장 `assets/skills` 39개 + 규칙 + 에이전트 15개 ≈ 수백 KB 텍스트(설치 전 `du -sh assets/skills assets/rules assets/agents` 로 수치를 이 문서 §7 에 적는다). 줄이는 일은 이번 범위 밖.

## 3. 비목표 (Out of Scope)

- 스킬 4층 저장 위치·주입 필터(계획 5). 이번에는 `.claude/skills/` 평면 구조 유지 — V-5 확인 결과 Claude Code 는 직계 폴더만 읽으므로 폴더 분리는 애초에 불가능하다.
- 훅·스크립트 배포 방식 — 이미 복사다(`HARNESS_HOOK_SOURCES`, `hermes.conf _hermes_setup`). 손대지 않는다.
- 메모리 폴더 링크 `install_memory_symlink`(E-04, 범위 밖).
- `presets.lock` 형식 변경. 공장 위치는 `factory.json` 에 따로 둔다.
- Codex 설치기(`lib/codex_installers.sh`) — 별도 계획.
- 확장 파일 `extends:` 머리말 검사(RV-13) — 확장 파일이 생기는 계획 5 에서.

## 4. 영향 영역

- 코드(수정): `lib/installers.sh`(`ln -s` 분기 제거, `_cleanup_stale_symlinks` → 목록 기준), `lib/harness_installers.sh`(설치 흐름에서 manifest 기록 호출, `.gitignore` 마커에 `.factory-manifest.json` 을 **넣지 않음** — 커밋 대상), `presets/workflow/hermes.conf`(`_hermes_setup` 에서 `factory.json` 기록), `setup.sh`(공장 자기 설치 분기 — 상대경로 링크), `assets/skills/claude-harness-hermes-install/SKILL.md`("Linux/macOS 는 symlink 라 즉시 반영" 문구 삭제), `presets/workflow/harness.conf`(새 훅 2개 등록), `docs/design-docs/core-beliefs.md`(설치물은 저장소 밖 경로를 가리키지 않는다 — R 룰 후보 등록).
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `lib/factory_manifest.sh` — 설치 목록(`.claude/.factory-manifest.json`)의 기록·읽기·해시 대조 한 가지만 담당한다.
  - `assets/hooks/claude-posttooluse-factory-tamper-warn.sh` — Edit/Write 대상이 설치 목록에 있고 해시가 달라지면 "소우주 확장으로 옮기고 제안하라" 경고를 낸다.
  - `assets/hooks/claude-sessionstart-factory-link-check.sh` — 공장 자기 설치의 상대경로 링크가 깨졌는지 판정해 재설치를 안내한다.
  - `tests/copy-install-test.sh` — 복사 설치·목록 기반 정리·변조 경고·깨진 링크 감지·factory.json 을 임시 프로젝트에서 검증한다.
  - `docs/hermes-universe/migration/copy-install-all-universes.md` — 등록된 모든 소우주의 이전 절차(사용자가 실행할 명령 순서와 저장소별 커밋 전 확인 목록)만 담는다.
- 게이트 대비: 신규 셸 모듈 `factory_manifest.sh` 는 공개 함수 4개(`manifest_add` · `manifest_read` · `manifest_prune` · `manifest_verify`)로 제한(R-iface 8 미만). 훅 2개는 각 80줄 이내(R-size).
- 룰: 새 R 룰 후보 "설치물은 저장소 밖 경로를 가리키지 않는다"(E-02). 이번에는 `core-beliefs.md` 에 후보로 적고 강제 장치는 목표 6·7 의 테스트·훅.
- 데이터: `skill_index` 의 모순 스킬 2행 tombstone(기존 `hermes-prune.py` 경로 사용, 새 스키마 없음).
- 외부 의존: 없음. `sha256sum`(coreutils) 사용.

## 5. 단계 (Steps)

### Step 1. V-5 결과를 배치에 반영 [단순]

- 입력: V-5 확인됨 — 직계 폴더만 로딩.
- 산출: 이 계획 §3 첫 항목. 설계 문서 `copy-install.md` §5 "폴더를 나누는 방법은 확인 필요" 문장을 "불가 — 목록으로 구분" 으로 갱신.
- 검증: 문서 diff.

### Step 2. 설치 목록 모듈 + 복사 전환 [Plan/Impl/Review]

- 입력: `lib/installers.sh` 세 함수, `_cleanup_stale_symlinks`, `_backup_user_asset`.
- 산출: `lib/factory_manifest.sh`, `installers.sh` 수정 — (a) `ln -s` 분기 삭제 (b) 설치마다 manifest 항목 기록 (c) 정리 함수는 "manifest 에 있고 현재 프리셋에 없는 이름" 만 삭제. 링크 여부는 더 이상 보지 않는다. (d) `_backup_user_asset` 은 "manifest 에 없는 실디렉터리" 를 사용자 자산으로 판정.
- 검증: 목표 1·2·3. 기존 `tests/preset-integrity-test.sh` · `update-all-roundtrip-test.sh` 통과.
- 주의: 기존 소우주는 링크가 있는 상태에서 처음 재설치된다. 링크는 `rm -rf` 로 지워지고 복사본이 놓인다 — 정리 함수가 manifest 없는 첫 실행에서 링크를 지우지 않도록 **첫 실행은 "링크이고 대상이 `$ASSETS_DIR` 아래" 인 항목을 manifest 로 옮겨 적는 이행 분기**를 둔다. 두 번째 실행부터 목록 기준.

### Step 3. factory.json + 변조 감지 훅 [Impl]

- 산출: `hermes.conf _hermes_setup` 에서 `.hermes/factory.json` 기록(`git -C $DEV_SETTING_DIR remote get-url origin`, `git rev-parse HEAD`), 훅 `claude-posttooluse-factory-tamper-warn.sh`(manifest 의 sha256 과 대조), `harness.conf` 등록.
- 검증: 목표 4·5.

### Step 4. 공장 자기 설치 상대경로 링크 + 깨진 링크 훅 [Impl]

- 입력: `setup.sh` 의 공장 자기 설치 경로, 커밋된 링크 25개.
- 산출: 공장(`$project_path == $DEV_SETTING_DIR`)일 때만 `ln -s ../../assets/skills/x`; 그 외 복사. 훅 `claude-sessionstart-factory-link-check.sh`. 공장 저장소에서 링크 25개를 상대경로로 바꾼 커밋.
- 검증: 목표 6·7.

### Step 5. 모순 스킬 삭제 [단순 — 사용자 확인]

- 산출: `.hermes/skills/repository-isolation-principle.md`, `unified-hook-deployment.md` 삭제(파괴적 작업 — 실행 전 사용자 확인) + `hermes-prune.py` 로 tombstone.
- 검증: 목표 8.

### Step 6. 테스트·문서 [Impl]

- 산출: `tests/copy-install-test.sh`, `run-all.sh` 등록, `doc_counts` 동기화(`scripts/sync-doc-counts.sh`), SKILL.md 문구.
- 검증: 목표 9.

### Step 7. 등록된 모든 소우주 이전 [사용자 실행]

- 대상: zeroday-frontend **와** 이 컴퓨터 `.installed-projects` 의 3곳(ai-create · wonil · terminal-shipping). 후자도 다음 `update-all` 에서 링크→파일 모드 변경(120000→100644) diff 가 각 저장소에 생긴다(planner-lite 지적) — 예고 없이 일어나면 안 된다.
- 산출: `docs/hermes-universe/migration/copy-install-all-universes.md` — ① zeroday 를 `.installed-projects` 에 **등록한 뒤** `update-all.sh`(직접 실행만 하면 계획 2·4·5 의 마이그레이션이 `hermes-init.py` 경유라 zeroday 에 영영 안 닿는다 — planner-lite 지적) ② 설치기가 "링크 → 복사본 N건" 을 stdout 한 줄로 보고 ③ 각 저장소에서 `git status` 로 변경 확인, `.claude/.factory-manifest.json` · `.hermes/factory.json` 추적 확인 ④ 사용자가 저장소마다 커밋. 자동 커밋 금지.
- 검증: 목표 10 + `grep -c zeroday-frontend .installed-projects` = 1 + 설치 로그의 변환 건수 = 41(zeroday). 다른 컴퓨터에서 pull 후 `.claude/skills/*/SKILL.md` 가 실제 파일로 존재.

## 6. 의사결정 로그

- 2026-09-15: `.claude/.factory-manifest.json` 은 **커밋한다**(`.dev-setting-manifest.json` 과 달리) — 근거: 다른 컴퓨터의 clone 도 어느 파일이 공장 것인지 알아야 변조 감지·정리가 동작한다. 틀렸을 때 손해: 설치마다 manifest diff 가 커밋에 섞인다(공장 커밋 해시가 바뀔 때만이라 드묾).
- 2026-09-15: 폴더 분리 대신 목록으로 공통/자체를 구분 — 근거: V-5(직계 폴더만 로딩). 틀렸을 때 손해: 없음(대안이 없다).
- 2026-09-15: 첫 재설치에 "링크 → manifest 이행 분기" 를 둔다 — 근거: 없으면 목록 기준 정리가 첫 실행에서 아무것도 못 지우거나(목록 비어 있음) 전부 지운다. 틀렸을 때 손해: 이행 분기 코드가 한 번 쓰고 남는다 — 3개월 뒤 제거 후보.
- 2026-09-15: 변조 감지는 **경고**지 차단이 아니다 — 근거: 소우주에서 급히 고쳐야 할 때 막으면 우회(`--no-verify` 류)를 유도한다(cumora K-1 의 반대 방향 교훈). 틀렸을 때 손해: 경고를 무시하고 공통 스킬을 고쳐 다음 `update-all` 에 덮어써진다 — 그때 manifest 해시 불일치를 설치기가 "사용자 수정 백업" 으로 남긴다.

## 7. 발견·예외

- 이 컴퓨터 `.installed-projects` 에 zeroday-frontend 가 없다(3곳만). 설계 근거 문서의 "등록 12곳" 은 다른 컴퓨터 기준으로 보인다 — Step 7 에서 명시 실행.
- 공장 자기 설치의 상대경로 링크는 `assets/` 이름이나 `.claude/` 깊이가 바뀌면 깨진다(E-02 손해). 훅이 잡는다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보: "설치물은 저장소 밖 경로를 가리키지 않는다"(E-02) → `core-beliefs.md` R 룰 + `tests/copy-install-test.sh` 가 강제 장치.

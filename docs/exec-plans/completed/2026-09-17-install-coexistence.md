# 2026-09-17-install-coexistence — 설치·전파가 하류 수정을 덮지 않고, 상류 개정과 공존시킨다

> 작성일: 2026-09-17
> 목적: 공장 파일을 프로젝트가 고쳐 두었을 때, 재설치·전파가 그것을 조용히 덮는 결함을 **근본에서** 막는다.
> 선행: 계획 1(copy-install — `.factory-manifest.json`, `factory_commit` 기록), 08-27 계획(propagation-reverts-downstream-fixes — 이 결함의 첫 기록).
> 설계 원천: `docs/exec-plans/completed/2026-08-27-propagation-reverts-downstream-fixes.md` §6, terminal-shipping `docs/audits/2026-09-08-secret-scanner-lost-project-rules.md` §4·§8·§9.

## 1. 동기 (Why)

- **같은 사고가 최소 5번 났다.** terminal-shipping `check-secrets.py`(프로젝트 비밀 규칙 161줄)·`plan_state.py`(`[~]` 세기): 09-08 → 09-14(전파) → 09-16 → 09-17 13:05(이번 전파, zeroday `plan_state.py` 58줄도 함께). 09-16 에는 덮인 판이 **커밋까지 됐다**.
- **공장은 이미 알고 있었다.** 08-27 계획이 이 결함을 기록했고("★ 조건 없는 cp"), §1-1 이 바로 `plan_state.py` 의 `[~]` 였다. 그때의 결정은 **"병합하지 않고 덮되 말한다"** — 해시 매니페스트로 하류 수정을 *감지까지 하면서* 덮고 경고만 냈다. 그 정책의 실측 결과가 위 다섯 번이다. 하류 감사의 결론: **"잡는 것과 막는 것은 다르다."**
- **보호가 한 경로에만 붙었다.** 09-16 리뷰(MEDIUM)로 `.claude/`(스킬·에이전트·규칙)는 `_backup_user_asset` 이 manifest sha 를 대조해 백업 뒤 덮는다. 그러나 **raw `cp` 5곳**은 그대로다: `assets/hooks/*`→`scripts/hooks/`, `.git/hooks/{check-secrets, check-component-structure, hermes_secret_values}`, `pre-commit`, hermes `scripts/*.py`(hermes.conf:184), `lint-configs/`. 사고 파일 둘은 정확히 이 경로에 산다.
- **기준(base)이 없었다.** 해법의 뼈대인 `.claude/harness-hooks.lock`(설치 sha 기록)은 지금 공장에 **작성자가 없고**(참조 0곳, gitignore 항목뿐) 기계별이라 커밋도 안 된다 — 다른 컴퓨터의 3-way 기준이 될 수 없다. `.factory-manifest.json` 은 커밋되고 `factory_commit` 을 갖지만 kind 가 `skills|agents|rules` 뿐이라 훅·스크립트는 미등록이다.
- **하류는 자기 범위 밖이라고 옳게 판단했다.** 감사 §8: "상류를 고치는 것은 이 저장소의 범위 밖 … PR 을 낼지는 사람이 정한다." 그 자리가 여기다.

## 2. 목표 (What — 검증 가능한 형태)

> 검증 명령: `bash tests/install-coexist-test.sh` (목표 2·3·4·6·8) · `bash tests/run-all.sh` (회귀) · 목표 5·9 는 §7 의 사본 리허설 기록.

- [x] 목표 1 — 공장이 소우주에 놓는 **모든 파일 복사가 한 함수** `install_factory_file <src> <dst> <kind> <name>` 를 거친다. raw `cp` 를 전부 치환 — 실측 결과 **호출 자리 4묶음, `cp` 17건**(`scripts/hooks/` 루프 1 · `.git/hooks/` 9 · hermes 스크립트 루프 1 · lint 2, 그리고 `.git/hooks` 9건은 헬퍼 `_install_git_hook` 하나로). 검증: `lib/`·`presets/` 에 남은 `cp` 가 허용 목록 6건 — 폴더형 자산 `cp -r`(installers.sh:79, 기존 백업 경로) · NTFS 메모리 폴백 `cp -r` · `data/bip39` 사전 · SOUL 틀 · `organization.yaml` 없을 때만 · docs 템플릿 신규 생성(있으면 `continue`) — 밖에 0건(테스트가 grep).
- [x] 목표 2 — 판정이 코드로 고정된다(base=마지막 설치판, ours=프로젝트 현재, theirs=새 공장판). **순서대로** 처음 맞는 분기를 탄다:
  ⓪ ours==theirs(내용 동일) → **아무것도 안 함, 무출력**(리뷰 HIGH① — 병합할 것이 없는데 알리면 G6 위반). (a) dst 없음 → 복사. (b) ours==base → 덮는다(조용). (c) ours≠base **이고** theirs==base → **손대지 않는다**(조용 — 상류가 준 것이 없다). (d) ours≠base, theirs≠base, base 내용 있음 → `git merge-file`; 충돌 0 **이고 구문 검사 통과**(`.py`→`py_compile`, `.sh`→`bash -n`, 리뷰 MED④) → 병합본을 쓰고 한 줄 알림; 충돌 >0 **또는** 구문 실패 → ours 유지 + `<dst>.factory-new` 로 theirs 를 옆에 두고 `[factory-merge CONFLICT]`. ⓔ ours≠base, theirs≠base, base 내용 **없음**(리뷰 MED⑤) → 판정 불가이므로 **덮지 않고** `<dst>.factory-new` + `[factory-merge UNKNOWN-BASE]`.
  **모드는 dst 가 이미 있었으면 그 모드를 보존하고, 새 파일이면 호출자가 정한다**(리뷰 HIGH② — `merge-file`·리다이렉트는 모드를 안 다룬다). ⚠️ "src 모드 복원" 이 아니다 — 2026-09-17 실측: `assets/hooks/plan_state.py`·`*.sh` 원본은 **644** 이고 설치기가 `chmod +x` 를 얹는다. 원본을 따르면 훅이 644 로 떨어져 pre-commit 이 죽는다. dst 가 **심링크**면 링크가 아니라 **타깃 파일**을 판정·기록·쓰기 대상으로 삼는다(리뷰 MED③).
  검증: `tests/install-coexist-test.sh` — 분기 ⓪·a·b·c·d(깨끗)·d(충돌)·d(구문 실패)·ⓔ 각 1건, **실행 비트 보존**(+x src → +x dst, 병합 뒤에도), **심링크 dst**(타깃이 바뀌고 링크는 유지), + **실물 픽스처**(terminal-shipping `plan_state.py` 의 ours/base/theirs — `check-secrets.py` 는 사내 경로·자격증명 꼴 문자열이 있어 PUBLIC 공장에 수록하지 않는다, R-leak) → 분기 (c), 결과 byte-equal. (2026-09-17 실측: 둘 다 충돌 0, plan_state 321→321 · check-secrets 407→407 — 후자는 수록 없이 실측치만.) 각 분기는 옛 코드(raw cp)로 되돌리면 빨개져야 한다.
- [x] 목표 3 — base 는 **두 단계**로 쓴다(리뷰 MED⑤ 반영): ① (b)(c) 판정은 manifest 에 **이미 있는 `sha256`** 만으로 한다 — `git show` 불필요, 공장 이력·clone 깊이와 무관. ② base **내용**은 (d) 에서만 필요하며 `git -C <공장> show <factory_commit>:<src>` 로 복원한다. 복원 실패(manifest 미등록·커밋 없음·얕은 clone·공장 경로 없음) → ⓔ. 설치는 언제나 공장 저장소 **안에서** 돌므로(`DEV_SETTING_DIR`) "공장 부재" 는 설치 중엔 성립하지 않고, 얕은 clone 만 실제 위험이다. 검증: 미등록 픽스처·존재하지 않는 커밋 픽스처·`git clone --depth 1` 한 공장 사본에서 (d) 상황 → 셋 다 ⓔ(`.factory-new`, 덮지 않음). 목표 9 리허설에 얕은 clone 공장 1회 포함.
- [x] 목표 4 — manifest 항목에 `path`(프로젝트 상대 설치 경로)·`src`(공장 상대 원본 경로)·`mode`(8진 파일 모드)를 더하고 kind `hook|githook|script|lint` 를 추가한다. 같은 이름이 두 경로에 깔리는 경우(`scripts/hooks/x` 와 `.git/hooks/x`)는 **경로마다 항목**이다(08-27 §7-bis "키를 이름에서 경로로" 와 일치). 기존 3 kind·`manifest_prune`(kind 별)·`copy-install-test`·변조 훅 무영향, 옛 항목(필드 없음)은 그대로 읽힌다. 검증: 기존 테스트 초록 + 새 kind 라운드트립(add→verify 0 / 수정→1 / 미등록→2) + 필드 없는 옛 manifest 로 verify 가 죽지 않음.
- [x] 목표 5 — G6(경고 피로) 준수: 소우주가 아무것도 안 고쳤으면 **출력 0줄**. 고쳤으면 파일당 1줄(G4). 검증: 차이 0 인 소우주 8곳 사본에 새 설치기 → 공존 관련 출력 0줄 실측 — `bash update-all.sh 2>&1 | grep -c '^\[factory-'` 가 고친 파일 수와 같다(§7 라이브 2차 전파: 변경 없는 소우주는 0줄). 단위로는 `bash tests/install-coexist-test.sh` §1 의 ⓪·b 분기가 "출력 0줄" 을 단언한다.
- [x] 목표 6 — 게이트: `*.factory-new` 가 워킹트리에 있으면 pre-commit 이 **차단**(`R-merge`), 해소는 사람(병합 뒤 삭제). 검증: 테스트 — 파일 있으면 차단, 지우면 통과.
- [x] 목표 7 — `harness-hooks.lock` 퇴역: `.gitignore` 생성 항목에서 제거, 소우주에 남은 고아 파일은 **건드리지 않는다**(문서로만 알림). 검증: 생성된 gitignore 에 항목 없음.
- [x] 목표 8 — 변조 경고 훅(`claude-posttooluse-factory-tamper-warn.sh`)이 `.claude/<kind>/<name>` 재구성이 아니라 manifest 의 `path` 로 판정해, 훅·스크립트 편집에도 `[factory-tamper WARN]` 을 낸다. 검증: 테스트 — `scripts/hooks/plan_state.py` 편집 → 경고 1건, 미등록 파일 → 0건.
- [x] 목표 9 — **실물 리허설**(라이브 금지): terminal-shipping·zeroday **사본**에 새 설치기 → 두 파일 byte-equal 유지, `.factory-new` 0개, 나머지 8곳 사본 변경 0. 그 뒤에만 사람 승인으로 라이브 `update-all`.
- [x] 목표 10 — 08-27 결정 "덮되 말한다" 를 §6 에서 **명시적으로 뒤집고** 근거를 남긴다. `core-beliefs.md` 룰 후보 `R-coexist` 는 이 계획 완료 뒤 `harness-promote-rule` 로 별도 승격(이 계획은 문장만 제안 — §8 "다음 룰 후보"). 검증: `grep -c '뒤집는다' docs/exec-plans/*/2026-09-17-install-coexistence.md` ≥1(§6 첫 항목) · 08-27 계획 §7 끝에 이 계획을 가리키는 상호 참조 1줄(`grep -c install-coexistence docs/exec-plans/completed/2026-08-27-propagation-reverts-downstream-fixes.md` ≥1).

## 3. 비목표 (Out of Scope)

- kis-trading 의 얼어붙은 hermes 스크립트 22개 정리 — hermes 를 안 켠 소우주에 남은 옛 사본이며 이 결함과 다른 문제(§7). 별도 정리 항목.
- **디렉터리형 자산**(스킬 폴더, NTFS 메모리 폴백 `cp -r`)의 3-way — 폴더는 기존 `_backup_user_asset` 백업 방식을 유지한다. 이 계획은 **파일** 단위다.
- 충돌을 모델로 자동 해결 — 절대 하지 않는다(R3, 08-27 의 옳은 통찰 "자동 병합은 조용히 틀린다").
- 어떤 파일이 공장 관리인지의 **경계 자체**를 바꾸는 것 — 경계는 그대로, 경계 안에서 덮지 않게만 한다.
- `.claude/` 3 kind 의 기존 백업 동작 변경 — 파일형은 새 함수로 통일하되 결과는 동일하거나 더 안전해야 한다.

## 4. 영향 영역

- 코드(수정): `lib/harness_installers.sh`(raw cp 5곳 → 함수 · gitignore lock 항목 제거), `presets/workflow/hermes.conf`(:184 루프 → 함수), `lib/factory_manifest.sh`(`path`·`src` 필드, 새 kind), `lib/installers.sh`(파일형 자산을 새 함수로), `assets/hooks/claude-posttooluse-factory-tamper-warn.sh`(path 기반 판정), `assets/pre-commit.sh`(`R-merge` 게이트), `tests/copy-install-test.sh`(새 필드 무영향 확인), `docs/design-docs/core-beliefs.md`(룰 후보 문장 — 승격은 별도).
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `lib/factory_coexist.sh` — 네 분기 판정·base 복원(`git show`)·`git merge-file`·`.factory-new` 기록만. 어디에 무엇을 까는지는 모른다(호출자가 준다).
  - `tests/install-coexist-test.sh` — 네 분기·base 복원 실패·실물 픽스처·G6 무출력·R-merge 게이트·변조 훅 path 판정 검증.
  - `tests/fixtures/coexist/` — terminal-shipping 실물 `plan_state` ours/base/theirs 1벌(3파일) + README. `check-secrets` 실물은 **수록하지 않는다**(사내 경로·자격증명 꼴 문자열 — PUBLIC 공장에 두면 R-leak, 스캐너가 실제로 막음). (d)·충돌 분기는 합성 픽스처를 테스트 안에서 만든다.
- 심링크 방침(리뷰 MED③): dst 가 심링크면 `readlink -f` 로 **타깃**을 판정·기록·쓰기 대상으로 삼고 링크는 그대로 둔다. manifest `path` 는 호출자가 준 dst(링크 경로)를 적되, sha 는 타깃 내용으로 잰다. 08-27 §1-0 의 우려와 하류 감사 §8 의 "lock 경로가 심링크 쪽을 가리켜 실물과 어긋남" 을 같은 규칙으로 막는다.
- 게이트 대비: `factory_coexist.sh` 는 셸이라 R-cx 밖이지만 분기 넷을 함수 넷(`_decide`·`_base_of`·`_merge`·`_park_new`)으로 나눈다. 훅 스크립트 수정은 `hook-stdin-dispatch-test`·`harness-hooks-smoke` 회귀 확인.
- 룰: 후보 `R-coexist` — "공장의 개정은 언제나 전달된다. 하류의 수정은 지워지지 않는다. 둘이 한 파일에서 만나면 합쳐서 둘 다 살리고, 같은 자리에서 겹치면 사람이 푼다." (⚠️ "고친 건 덮지 않는다" 로 줄여 말하지 말 것 — 그 요약은 "고쳤으면 못 받는다" 로 읽혀 2026-09-17 사용자가 정확히 그렇게 오해했다.) 강제: `install-coexist-test` + `R-merge` 게이트.
- 데이터: `.factory-manifest.json` 스키마 **추가만**(`path`·`src`·`mode` 선택 필드, 새 kind 값). 옛 항목은 필드가 없어도 읽힌다(하위호환 테스트).
- 외부 의존: `git merge-file`(git 표준, 이 저장소 첫 사용). 공장 저장소가 설치 시점에 존재해야 base 복원 가능 — 없으면 목표 3 의 보수 분기.

## 5. 단계 (Steps)

### Step 0. 실물 픽스처 채집 [단순]

- 입력: terminal-shipping `scripts/hooks/plan_state.py`(ours — **커밋 `266d0b9` 를 못 박아** 추출, HEAD 신뢰 안 함), 공장 `6f82144`·현재판(base·theirs).
- 산출: `tests/fixtures/coexist/plan_state.{ours,base,theirs}` + README. 수록 전 비밀 검사는 **스테이징 경로**로 한다 — 스캐너는 인자 파일을 보지 않고 `staged_files()` 만 본다(인자로 주고 rc=0 을 믿으면 헛검사).
- 검증: 픽스처로 `git merge-file` 충돌 0·byte-equal 재현(2026-09-17 완료: plan_state 321→321). `check-secrets` 는 실측만(407→407) 하고 수록 제외(R-leak).

### Step 1. 공존 판정 함수 + manifest 확장 [Plan/Impl/Review]

- 입력: `lib/factory_manifest.sh`, 08-27 §6 결정, 목표 2·3·4.
- 산출: `lib/factory_coexist.sh`(`install_factory_file` + 헬퍼 넷), manifest `path`·`src`·새 kind, `tests/install-coexist-test.sh` 의 분기·복원·라운드트립 절.
- 검증: 목표 2·3·4. 네 분기 각각 **옛 코드로 되돌리면 빨개지는지** 확인(통과만 보는 검증 금지 — 08-27 §8 교훈).
- Review 승격 사유: 공유 경계(설치기)·12개 소우주 데이터에 닿는 변경.

### Step 2. raw cp 5곳 치환 + lock 퇴역 [Impl]

- 입력: Step 1 함수, §1 의 5곳 목록.
- 산출: `harness_installers.sh`·`hermes.conf`·`installers.sh` 치환, gitignore 항목 제거.
- 검증: 목표 1(grep 0건)·목표 5(차이 0 소우주 사본 8곳 무출력)·목표 7. 전체 스위트 초록.

### Step 3. 게이트·변조 훅 [Impl]

- 입력: `assets/pre-commit.sh`, 변조 훅.
- 산출: `R-merge` 차단, 훅 path 판정.
- 검증: 목표 6·8. 훅 스모크 회귀.

### Step 4. 실물 리허설 → 사람 승인 뒤 라이브 [Review]

- 입력: 12개 소우주 **사본**.
- 산출: 리허설 보고(파일별 분기·변경 0 증빙). 승인 뒤 `update-all`, 직후 §A 방식 전수 대조.
- 검증: 목표 9. 라이브는 사용자 명령으로만.

### Step 5. 정리 [단순]

- 산출: 08-27 계획 §7 에 "이 계획으로 뒤집힘" 상호 참조, `core-beliefs.md` 룰 후보 문장, §8 회고, `completed/` 이동.
- 검증: 전체 스위트 0 실패, `R-retro`·`R-plan` 통과.

## 6. 의사결정 로그

- 2026-09-17: **08-27 의 "병합하지 않고 덮되 말한다" 를 뒤집는다 → "공장의 개정은 언제나 전달하고, 하류의 수정은 지우지 않으며, 한 파일에서 만나면 합쳐서 둘 다 살리고, 같은 자리에서 겹치면 사람이 푼다".** (요약을 "고친 건 덮지 않는다" 로 줄이면 "고쳤으면 새 기능을 못 받는다" 로 읽힌다 — 틀린 이해다. 둘 다 바뀐 파일도 (d) 에서 **합쳐서 받는다**.) 근거: 그 정책 아래 5회 재발(경고는 놓쳤고 09-16 엔 덮인 판이 커밋됨), 하류 감사 결론 "잡는 것과 막는 것은 다르다". 08-27 이 옳게 본 것("자동 병합은 조용히 틀린 결과를 만든다")은 **유지**한다 — 그래서 충돌은 자동 해결하지 않고 `.factory-new` 로 세워 두고 게이트가 막는다. 틀렸을 때 손해: 문법상 안 겹치는 두 수정이 **논리상** 충돌하는 "깨끗한 오병합"이 가능하다 → 완화: 병합 사실을 1줄 알리고(G4), 하류 시험은 R-test 가 이미 돌린다. ⚠️ **이 결정은 사용자 승인 대상**이다 — 기록된 결정을 뒤집기 때문.
- 2026-09-17: base 를 **저장하지 않고 `git show` 로 복원**한다. 근거: manifest 가 이미 `factory_commit` 을 갖고, 실측으로 `git show <commit>:assets/hooks/plan_state.py` 가 복원됨(308줄). 별도 저장은 기계별 lock 이 실패한 길이다. 틀렸을 때 손해: 공장 이력 rewrite·공장 부재 시 복원 실패 → 보수 분기(덮지 않음)로 안전하게 떨어진다.
- 2026-09-17: 판정 기준은 `cmp` 가 아니라 **base 대조**다. 근거: kis-trading 실측 — 공장과 다른 파일 22개가 "고친 것"이 아니라 hermes 미선택으로 **얼어붙은** 옛 사본. `cmp` 는 둘을 못 가른다(08-27 §8 이 이미 적은 교훈).
- 2026-09-17: 충돌 산출물 이름은 `<파일>.factory-new`(dpkg `.dpkg-dist`·rpm `.rpmnew` 관례). 근거: 수십 년 검증된 conffile 모델, 발명하지 않는다. 기존 `_backup_user_asset` 의 백업(`.orig` 성격)은 폴더형에만 남긴다.
- 2026-09-17: 같은 내용이 두 경로(`scripts/hooks/x`·`.git/hooks/x`)에 깔리면 **경로마다** 판정·기록한다. 근거: 하류 감사 §8 의 실패 원인 하나가 lock 경로가 심링크 쪽(`.git/hooks`)을 가리켜 실물(`scripts/`)과 어긋난 것.
- 2026-09-17 (planner-lite 리뷰 반영): **깨끗한 병합도 구문 검사를 통과해야 쓴다** — `.py` 는 `py_compile`, `.sh` 는 `bash -n`; 실패는 충돌과 같이 `.factory-new`. 근거: 병합 대상이 훅 스크립트라 "줄은 안 겹치나 문법이 깨진" 병합본은 pre-commit 을 즉시 죽인다. R-test 는 커밋 시점이라 설치 시점 피해를 못 막는다. 틀렸을 때 손해: 구문은 맞는데 뜻이 틀린 병합은 여전히 통과 → 1줄 알림 + R-test 가 남은 방어.
- 2026-09-17 (리뷰 반영): **내용이 같으면 무조건 no-op 무출력** — 판정 맨 앞. 근거: 하류·상류가 같은 수정으로 수렴한 경우 `merge-file` 을 돌리면 결과는 같은데 "병합했다" 가 떠 G6(읽히지 않는 경고는 없는 경고)를 깨뜨린다.
- 2026-09-17 (리뷰 반영, 내 논리 오류 정정): 초안 목표 3 의 "복원 불가 → (d)" 는 성립하지 않았다 — (d) 는 base **내용**이 있어야 하는 분기다. 고침: (b)(c) 는 manifest 의 sha 만으로 판정하고(내용 불필요), base 내용은 (d) 에서만 `git show` 로 가져오며, 없으면 새 분기 ⓔ "판정 불가 → 덮지 않고 세워 두고 경고". 근거: 덮지 않는 것이 유일하게 되돌릴 수 있는 실패다. 틀렸을 때 손해: 얕은 clone 공장에선 둘 다 바뀐 파일이 매번 `.factory-new` 로 서서 사람이 풀어야 함 — 드물고 안전한 쪽.
- 2026-09-17 (리뷰 반영, Step 0 실측으로 정정): **모드는 dst 가 이미 있었으면 그 모드를 보존하고, 새 파일이면 호출자가 정한다**; 결과 모드를 manifest `mode` 에 남긴다. 근거: `git merge-file`·리다이렉트 쓰기는 모드를 안 다룬다 — 훅이 644 로 떨어지면 pre-commit 자체가 안 돈다. 초안은 "src 모드 복원" 이었는데 실측하니 `assets/hooks/*.py`·`*.sh` 원본이 **644**(`check-secrets.py` 만 755)이고 설치기가 `chmod +x` 를 얹고 있었다 — src 를 따랐으면 리뷰가 경고한 그 회귀를 **고치면서** 냈을 것이다. 틀렸을 때 손해: 호출자가 새 파일에 모드를 안 주면 644 로 남음 → 각 호출 자리에서 기존 `chmod +x` 를 유지하고 테스트가 +x 를 단언.

## 7. 발견·예외

- 2026-09-17 예비 실측: terminal-shipping 실물 두 파일에 `git merge-file`(base=`6f82144`) → **충돌 0, 병합본==우리 판 byte-equal**(321·407줄). 단 이 base 는 **대용**이다 — 훅 kind 가 manifest 에 없어 진짜 설치 시점 커밋이 기록돼 있지 않다. 그 기록을 만드는 것이 이 계획이다.
- kis-trading: 공장과 다른 hermes 스크립트 22개 — `presets.lock` 에 hermes 없음. 고친 게 아니라 안 받은 것. 이 계획의 판정(base 대조)이 "안 고침"으로 옳게 분류할 것이며, 정리는 비목표.
- `harness-hooks.lock`: 공장에 작성자 없음(참조는 gitignore 한 줄). terminal-shipping 의 것은 08-27 에 멈춘 고아. 퇴역만 하고 지우지 않는다.
- 변조 경고 훅은 `.claude/skills|agents|rules` 경로에 하드와이어(`:30`) — 훅 편집엔 침묵하지만 깨지진 않는다. 목표 8 에서 path 기반으로 넓힌다.
- 설치 순서(`project-claude.sh`): `receipt_begin` → `install_skills` → `_hermes_setup` → `install_harness_hooks` → `write_manifest` → `receipt_end`. 새 함수는 각 복사 자리에서 `manifest_add` 를 부르면 되고 순서 변경은 불필요.
- 이번 사고의 복구(13:19)는 `git checkout --` 로 했는데, zeroday 에 덮어쓰기 8분 뒤 커밋(13:13)이 있었다. 그 커밋이 공장 파일을 안 담아 무사했을 뿐, `checkout --` 는 HEAD 를 믿는 방식이라 위험했다 — 복구는 **알려진 커밋을 못 박는** `git checkout <commit> -- <파일>` 로 한다(사용자 지적).
- **2026-09-17 planner-lite 리뷰(NEEDS_WORK: HIGH 2·MEDIUM 3·LOW 1) — 5건 전부 타당해 반영:**
  - HIGH① ours==theirs 인데 base 와 다른 경우가 판정표에 없었다 → 분기 ⓪(무출력 no-op)을 맨 앞에.
  - HIGH② 실행 비트 보존이 어디에도 없었다 → 모든 쓰기 뒤 src 모드 복원, manifest `mode`, 검증 케이스.
  - MED③ 심링크 dst 방침 부재 → 타깃 기준 판정·쓰기, 링크 유지(§4).
  - MED④ 깨끗한 오병합의 완화가 커밋 시점 R-test 뿐 → 설치 시점 구문 검사(`py_compile`/`bash -n`)를 (d) 에 삽입.
  - MED⑤ 초안 목표 3 "복원 불가 → (d)" 는 **모순**이었다((d) 는 base 내용이 필요) → sha 로 (b)(c) 판정, 내용은 (d) 만, 불가 시 분기 ⓔ. 얕은 clone 공장을 목표 9 리허설에 포함.
  - LOW: "경로마다 항목" 은 08-27 §7-bis 와 일치함을 리뷰가 확인.
  - 교훈: 초안의 보수 분기가 성립 불가였다는 것은 **판정표를 표로 그려 빈칸을 셌으면** 스스로 잡혔을 것이다. 다음 계획부터 분기 판정은 진리표로 먼저 쓴다.
- **2026-09-17 Step 0 에서 드러난 것:**
  - 비밀 스캐너는 **인자 파일을 보지 않는다**(`main()` 이 `staged_files()`/`--all` 만 봄). 인자로 주고 받은 rc=0 두 번은 **헛검사**였다. 스테이징 경로로 다시 돌리자 `check-secrets.ours` 에서 5건이 걸렸다(사내 경로 + `password=…` 꼴 예시 문자열, "과거 LDSP 비밀번호 형태"). 스캐너가 옳다 — PUBLIC 공장에 사내 소우주의 그 파일을 픽스처로 두는 것은 오늘 승격한 R-leak 위반. **수록 제외**, `plan_state` 만 실물 픽스처. (`tests/` 통째 면제를 타면 통과는 됐을 것이나, 그 면제가 방어를 줄인다고 하류 감사가 이미 지적했다.)
  - assets 원본 모드 실측: `plan_state.py` 644 · `check-secrets.py` 755 · `*.sh` 훅 644. 설치기가 복사 뒤 `chmod +x` 를 얹는다. 초안의 "src 모드 복원" 은 훅을 644 로 죽였을 것 → "기존 dst 모드 보존, 새 파일은 호출자" 로 정정(§6).
  - ours 추출은 HEAD 가 아니라 **커밋을 못 박아**(`266d0b9`) 했다 — 오늘 오후 복구 때 `checkout --` 가 HEAD 를 믿어 위험했던 교훈의 적용.

- **2026-09-17 Step 1~3 구현에서 드러난 것(코드 리뷰 HIGH 2·MED 3·LOW 1 전부 반영 + 스스로 잡은 것):**
  - `py_compile(cfile=/dev/null)` 이 3.12+ 에서 **항상** 실패해 모든 `.py` 병합이 충돌로 떨어졌고, 스모크의 "구문실패→충돌" 은 그래서 **거짓 통과**였다. `compile()` 로 교체하고, 테스트에 "고치면 d 로 병합돼야 한다" 대조 단언을 넣어 검사기가 실제로 가르는지 증명했다.
  - `git merge-file` 은 **인접한 줄**의 수정을 한 덩어리로 보아 충돌시킨다(1·2행 → 충돌, 3줄 띄우면 rc=0). 코드가 옳고 픽스처가 틀린 경우였다. 안전한 쪽 오류라 고치지 않는다 — 실제 사고 파일(321·407줄, 수정 자리가 멂)이 충돌 0 이었던 이유이기도 하다.
  - 첫 전환 때 이미 고쳐 둔 파일은 manifest 에 base 가 없어 전부 ⓔ 로 떨어졌다(사본 리허설: terminal-shipping 3·zeroday 1). `factory.json.installed_version`(계획 1 이 매 설치마다 적는 프로젝트 전체의 마지막 공장 커밋)을 파일별 base 의 **대용**으로 쓰자 4건 전부 조용한 c 로 판정됐고 manifest 에 진짜 base 가 기록됐다. 이 폴백은 계획 1 이 심어 둔 값의 재사용이지 새 저장이 아니다.
  - 그 c-복귀 분기를 처음 쓸 때 **하류 판의 sha 를 base 로 기록**하는 오류를 냈다 — 그러면 다음 설치가 하류 수정을 "설치판" 으로 오인해 b 로 덮는다. 테스트 전에 스스로 잡아 base 파일의 sha 를 적도록 고쳤고, "다음 설치도 c" 회귀 단언을 넣었다.
  - 리뷰 HIGH①(프로젝트 밖 심링크 → 공장 원본 덮음) 가드는 사본 리허설에서 **실제로 발화**했다(절대경로 심링크가 사본에선 원본 저장소를 가리킴). 라이브 terminal-shipping 은 링크가 프로젝트 안이라 c 로 판정됨을 쓰지 않고 시뮬해 확인했다.
  - `R-merge` 게이트를 처음 쓸 때 `grep -v '^$' | sort` 파이프가 정상 상태(파일 0개)에서 `pipefail` 로 스크립트를 **조용히 죽여 모든 커밋이 막혔다**. 테스트가 배포 전에 잡았다. `find` 한 번으로 바꿨다 — 리뷰 HIGH②(set -e 아래 실패 전파)와 같은 부류를 게이트 쪽에서 낸 것.
  - 리허설을 `TMPDIR` 격리 없이 돌려 실제 `.installed-projects` 에 `/tmp` 경로 8건을 **오염**시켰다(copy-install-test 가 잡음). 백업 뒤 제거했다. 리허설은 반드시 `export TMPDIR=<임시>` 아래서 돌린다 — update-all 테스트가 이미 그렇게 한다.
  - 두 옛 테스트의 가정이 낡았다: copy-install 은 "manifest 전체 = 3 kind 설치물" 을 가정(이제 훅·스크립트도 기록), skill-layers 는 라이브 zeroday DB 가 "전부 common" 이라 가정(전파 뒤 universe 50건). 숫자를 맞추지 않고 **참 불변식**(3 kind 만 세기 · layer NULL 0)으로 고쳤다.
  - 변조 훅의 옛 문구 "다음 update-all 에서 덮어써집니다" 는 공존 설치 뒤로 **거짓**이다. 경로 확장과 함께 "편집은 보존됩니다 … 겹치면 .factory-new" 로 고쳤다 — 틀린 경고는 훅에 대한 신뢰를 지운다.
  - 공장 자기 설치에서 `MERGED` 2건(`pre-commit`·변조 훅)이 떴다 — 새 함수의 첫 실전 판정. 병합본이 새 공장판과 byte-equal 임을 확인(무해).

- **2026-09-17 라이브 전파(Step 4)와 그 뒤에서 드러난 것:**
  - 1차 전파 12/12. **사고 파일(check-secrets·plan_state) 12곳 전부 불변 — 6번째 재발 없음.** pre-commit 새 판 11/11.
  - 그러나 hermes 없는 4곳(rim-kanban·rim-office·teulankkae·kis-trading)에서 옛 공장판 `pre-commit`·변조 훅이 `UNKNOWN-BASE` 로 세워졌다(7건). `factory.json` 이 없어 폴백 base 도 없었고, 그 파일들은 하류 수정이 아니라 공장 이력의 옛 판(`72a503d`·`ee23daf`)이었다. 마지막 질문 "ours 가 공장 이력의 어느 판인가?" 를 `_coexist_is_old_factory` 로 넣어 옛판이면 덮게 했다(최근 60커밋). 2차 전파가 7건을 자동 정리, 공존 출력 0줄, `.factory-new` 12곳 0.
  - **제 리허설이 라이브를 건드렸다.** 14:23 사본 리허설 때 사본 `.git/hooks/*` 의 **절대경로 심링크**가 라이브 terminal-shipping 을 가리켰고, 가드가 없던 그 판은 `readlink -f` 를 따라가 라이브에 `.factory-new` 2개를 썼다(원본 sha 는 무손상, 스냅샷으로 확인). 리뷰 HIGH① 이 실제로 난 것이다. 전파 전에 제거했고, 가드 있는 판으로 **같은 조건을 재현**해 라이브 변경 0·`OUTSIDE` 2건 차단을 증명했다.
  - **합침의 실물 증명**: novel-ab 사본에 하류 한 줄(끝) + 공장 개정 한 줄(첫 줄, 임시 커밋) → `MERGED`, 둘 다 살고 구문 유효, 755.
  - **가장 큰 사고 — 오늘 미커밋 작업 전체를 지웠다.** 위 실험의 임시 공장 커밋을 `git reset --hard HEAD~1` 로 되돌리며 워킹트리가 HEAD 로 돌아갔고, 커밋된 적 없는 하루치 작업(26파일 2233줄)이 사라졌다. 임시 커밋이 `git add -A` 스테이징 위에서 만들어져 **우연히** 전부 담고 있었던 덕에 `checkout 2ac145c -- .` 로 복구했다. 임시 커밋 이후 변경 2건(옛판 분기·테스트 §7c2)만 유실돼 재작성했고, 테스트 동일성(78/78·전체 69/69)으로 복구를 판정했다. 교훈: **미커밋 작업 위에서 `reset --hard`·`checkout .` 를 치지 않는다. 라이브 저장소에서 임시 커밋 실험을 하지 않는다 — 리허설은 별도 clone 에서.** 그리고 커밋을 미루면 한 번의 실수로 전부 잃는다.
  - 레지스트리(`.installed-projects`) 오염이 **두 번** 났다(8건·2건). `TMPDIR` 격리는 등록을 막지 못한다 — 설치기는 인자로 받은 경로를 그대로 적는다. 손으로 정리했다(백업 `.harness/out/`). 설치기가 `/tmp` 아래 경로를 등록하지 않게 하는 수정은 이 계획 밖 별도 결함으로 남긴다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
  - **결함을 한 함수로 좁혔다.** raw `cp` 17건이 `install_factory_file` 하나를 거치게 되자, "어느 경로가 보호를 못 받는가" 라는 질문 자체가 사라졌다(08-27 은 `.claude/` 한 경로만 보호해 사고 파일 둘이 정확히 그 밖에 있었다). 재발 시 볼 곳이 `lib/factory_coexist.sh` 한 파일이다.
  - **"덮지 않는다" 가 아니라 "합친다" 로 간 것.** 사용자 지적("소우주에서 고쳤다고 못 덮으면 상류 개선이 아무 상관 없어진다") 이 초안의 구멍을 짚었다. base 대조 + `git merge-file` 이라 하류 수정과 상류 개정이 한 파일에서 만나도 둘 다 산다 — 실물 사본에서 증명(하류 규칙 + 공장 개정 동시 보존, 구문 통과, 755 유지).
  - **리뷰가 잡은 셋이 전부 실측으로 확정됐다.** 모드 회귀(HIGH②: src 원본이 644 라 "src 복원" 이면 훅이 죽음), no-op 무출력(HIGH①), base 없음 분기 ⓔ(MED⑤). 리뷰 문장을 그대로 믿지 않고 `stat`·`git show`·얕은 clone 으로 각각 재현한 뒤 고쳤다.
  - **통과만 보는 테스트를 두 번 잡았다.** `py_compile(cfile=/dev/null)` 이 3.12+ 에서 항상 실패해 모든 병합이 충돌로 떨어졌는데 "구문 실패→충돌" 단언은 헛되이 초록이었다 → 대조 단언 추가. `check-secrets.py` 를 파일 인자로 돌린 스캔도 헛되이 초록(스테이징만 읽음) → 스테이징으로 재스캔하니 5건 → 픽스처 수록 취소(R-leak).
  - 라이브 전파 2회 12/12: 사고 파일 byte-equal, `.factory-new` 0, 변경 없는 소우주는 출력 0줄(G6).
- 잘못된 것:
  - **미커밋 작업 하루치를 `git reset --hard` 로 지웠다**(§7). 임시 커밋이 스테이징 트리를 잡아 둔 덕에 복구했고 잃은 함수 하나(`_coexist_is_old_factory`)·테스트 §7c2 는 다시 썼다. 원인은 두 가지 — 실험을 라이브 저장소에서 했고, 커밋을 미뤘다. 교훈: 리허설·실험은 **별도 clone** 에서, 검증이 끝난 단위는 그 자리에서 커밋(사용자 지시 대기 중이면 최소 `git stash`/임시 브랜치로 잡아 둔다), 미커밋 트리 위에서 `reset --hard`·`checkout .` 금지.
  - **리허설이 라이브를 두 번 건드렸다.** 사본의 `.git/hooks` 심링크가 절대경로라 라이브 terminal-shipping 에 `.factory-new` 2개가 섰고(→ 분기 f OUTSIDE 가드로 봉쇄), `.installed-projects` 에 `/tmp` 경로가 두 번 등록됐다(8·2건). Step 5 에서 원인을 실측으로 고쳐 잡았다: §7 의 "설치기가 인자 경로를 그대로 적는다" 는 **틀렸다** — 가드(`project-claude.sh:189`, 09-16)는 있으나 `${TMPDIR:-/tmp}` **한 곳만** 대조해, `TMPDIR` 을 잡 디렉터리로 둔 채 `/tmp` 사본을 설치하면 새어 나간다(재현: 가드 식에 그 조합을 넣으면 "등록됨"). 이 계획 밖 결함으로 `backlog/installer-registers-rehearsal-paths.md` 에 남긴다.
  - **첫 R-merge 게이트가 모든 커밋을 조용히 죽였다** — `grep -v '^$' | sort` 가 pipefail 아래서 빈 입력에 rc 1. 게이트 코드는 "차단이 나는지" 뿐 아니라 "정상 커밋이 통과하는지" 도 단언해야 한다(8b 에 통과 케이스 포함).
  - **슬로건이 오해를 낳았다.** "고친 건 덮지 않는다" 한 줄이 사용자에게 "업데이트를 못 받는다" 로 읽혔다. 정책은 네 문장(전달·보존·병합·충돌은 사람)으로만 말한다 — 계획서 세 곳 정정.
  - UNKNOWN-BASE 가 리허설 4건·라이브 7건 떴다 — 옛 공장판이 manifest 없이 깔린 소우주. `installed_version` 폴백과 공장 이력 대조(`git log -60`)로 흡수했지만, 이는 "manifest 가 없는 과거" 를 위한 보정이지 설계는 아니다. 두 번째 전파 뒤 0건이므로 이후 새로 뜨면 진짜 판정 불가다.
- 다음 룰 후보: `R-coexist`(공장의 개정은 언제나 전달되고, 하류의 수정은 지워지지 않으며, 한 파일에서 만나면 합쳐서 둘 다 살린다) — `harness-promote-rule` 로 승격.

# 2026-09-15-sync-transport-encryption — 원문 커밋 중단, refs/hermes/sync 운반, age 암호화

> 헤르메스 우주 구현 계획 **3/5**. 설계 원천: `design/protection/raw-transcript.md`(T-02 · T-03 · T-05), `sync-transport.md`(T-07, RV-01), `encryption-keys.md`(T-08~T-12, RV-02 · RV-03 · RV-04), `handoff-contract.md` §6(H-10 · H-11).
> 선행: 계획 2 — 옮길 이벤트(`journal_events`)가 있어야 한다. 계획 1 — `factory.json` 과 같은 설치 자리.
> 다음 계획: `2026-09-15-agent-identity.md`.

## 1. 동기 (Why)

- 대화 원문이 **평문으로 코드 브랜치에 커밋**된다: `.gitignore` 예외 `!.hermes/history/**`(`presets/workflow/hermes.conf:178`), Stop 훅 export(`assets/hooks/claude-stop-retrospective.sh:121`). 커밋된 원문 파일 zeroday-frontend **235개**(동료 3명 접근), terminal-shipping 31개.
- 2026-08-10 terminal-shipping 사고: 외부 계정 5종 평문 자격증명이 origin/main 까지 올라감. 네 겹 방어를 보강했지만 "원문을 git 에 싣는 구조" 는 비목표로 남았다(`docs/superpowers/specs/2026-08-10-hermes-secret-masking-design.md`).
- 원문 파일의 용도는 "다른 컴퓨터로 옮기기" 하나다 — 회상·결정화·압축은 전부 `state.db` 를 읽는다.
- 암호화 코드 0건(`grep -rnwE "encrypt|decrypt|…"`), `age` · `pyrage` 미설치.
- 이 컴퓨터 git 은 **2.25.1** — `merge-tree --write-tree`(2.38+) 없음 → RV-01 의 2순위(임시 worktree merge)가 실제 경로.

## 2. 목표 (What — 검증 가능한 형태)

- [ ] 목표 1 — 코드 브랜치 원문 커밋이 멈춘다. `hermes.conf:177-178` 의 `!.hermes/history/` **와** `!.hermes/history/**` 두 줄을 지운다(planner-lite 지적). 검증 두 줄: (a) 재설치 후 `git check-ignore .hermes/history/new.jsonl` 이 무시로 판정 — **새 파일만** (b) 이미 추적 중인 평문은 무시 규칙과 무관하게 그대로다 — `git ls-files .hermes/history | wc -l` 이 zeroday 235 · terminal-shipping 31 로 **불변**(T-03. 추적 해제 `git rm --cached` 도 하지 않는다 — 그것은 이력 재작성은 아니지만 동료 clone 의 작업 트리에서 파일을 지우는 부작용이 있어 저장소별 사용자 판단).
- [ ] 목표 2 — 매 턴 export 가 세션 파일 전량 재작성이 아니라 **턴 단위 조각**(`history/<session_id>/<순번>.enc`)을 만든다. 검증: `tests/hermes-sync-test.sh` — 3턴 후 파일 3개, 기존 조각 바이트 불변.
- [ ] 목표 3 — 조각은 `age` 로 **마스터 자물쇠 하나**에 잠기고, 마스터 열쇠는 컴퓨터 자물쇠·비상 자물쇠로 감싸 `keys/` 에 놓인다(RV-03). 검증: 테스트에서 자물쇠 두 개 등록 → 조각 헤더 수신자 1개, `keys/<사람>/master.<지문>.age` 2개, 어느 열쇠로도 복호 성공.
- [ ] 목표 4 — 열쇠 CLI 가 AI 세션 밖 절차를 구현한다: `init`(마스터+컴퓨터 열쇠), `add-computer`(다른 컴퓨터 자물쇠로 마스터 재감싸기), `emergency`(비상 열쇠 생성 → **24단어 니모닉으로 한 번 표시**(BIP-39 사전, age 32바이트 열쇠와 무손실 왕복) → "이 열쇠 없이는 복구 불가" 확인 입력 → 사용자가 옮겨 적은 단어를 다시 넣어 시험 복호 → 폐기 → 자물쇠 등록. `--save-file` 은 용도 · 경고 · `BEGIN/END HERMES RECOVERY KEY` 구간 · 번호 목록을 담은 텍스트를 사용자 지정 경로에만 씀), `revoke`, `rotate-master`(컴퓨터 분실 후 새 마스터 — 새 조각부터, 옛 마스터는 보관, G-4), `doctor`. 검증: `tests/hermes-keys-test.sh` 가 각 명령을 비대화(`--yes` + stdin) 로 돌림. `emergency` 는 시험 복호 실패 시 다음 단계로 못 감. 니모닉 왕복 테스트: 열쇠 → 24단어 → 열쇠 가 바이트 동일, 단어 하나 오타는 체크섬으로 거부. `rotate-master` 뒤 옛 조각은 옛 마스터로만 열린다.
- [ ] 목표 5 — 세션 안 열쇠 취급 차단(T-11): PreToolUse Bash 훅이 `age-keygen` · `AGE-SECRET-KEY-` · `hermes-keys.sh init|emergency` 를 막는다. 검증: `tests/hermes-key-guard-test.sh` 3케이스 차단 + `hermes-keys.sh doctor` 는 통과.
- [ ] 목표 6 — 세션 종료 훅이 push 정책(`.hermes/sync.json`, 기본 없음=로컬 전용)을 읽어 켜진 소우주만 `refs/hermes/sync` 에 저수준 커밋·push 한다. 검증: 테스트 bare 원격에 push 후 `git ls-remote <bare> refs/hermes/sync` 존재, 코드 브랜치 변경 0, 작업 트리 변경 0.
- [ ] 목표 7 — 두 클론이 각자 push 해도 둘 다 올라간다(RV-01). 검증: 테스트 — clone A·B 각각 조각 1개 push, 두 번째가 거부 → fetch·임시 worktree merge·재push → 원격 트리에 조각 2개, `--force` 호출 0(스크립트 grep).
- [ ] 목표 8 — 세션 시작 훅이 `refs/hermes/sync` 를 fetch 해 새 조각만 복호·재색인한다. 열쇠 없으면 H-10 안내문을 내고 push 를 보류한다. 검증: 테스트 — 열쇠 없는 clone 에서 `[hermes] … 열쇠가 없습니다` 출력 + `state.db` 변경 0.
- [ ] 목표 9 — 기억 "없음" 3분류(H-11)를 기계가 낸다. 검증: `bash tests/hermes-sync-test.sh` 의 없음-3분류 절 — 저장소 없음 / 조각 미복호 / 조회 0건 세 경우를 픽스처로 만들어 `hermes-sync.py status` 출력 문구가 세 가지로 서로 다름을 고정.
- [ ] 목표 10 — 백필(G-2): `hermes-sync.py backfill` 이 이 컴퓨터 `state.db` 의 기존 원문을 조각으로 만들어 올린다(세션당 1회, 멱등). 검증: 두 번 실행해도 조각 수 동일.
- [ ] 목표 11 — 작업 이력 자유 글 칸 3개(`intent` · `lesson` · `decision`)가 원격 사본에서만 암호문이다(J-07). 검증: 원격 `journal/…/<event_id>.json` 의 세 칸은 `age` 헤더로 시작, 기계 칸은 평문.
- [ ] 목표 12 — 압축(G-1)이 추가 전용과 충돌하지 않는다: 압축은 "요약 조각 추가 + 원 조각 `superseded` 표시 파일" 로 바뀌고, 원 조각을 덮어쓰지 않는다. 검증: 테스트 — 압축 후 원 조각 바이트 불변, 재색인이 요약본을 택함.
- [ ] 목표 13 — 서버 실측 V-1 · V-2 · V-3 결과가 이 문서 §7 에 기록된다(사용자 실행). 검증: §7 표에 세 서버(gitlab.com · 사내 서버 · V-3 광고) 결과 행이 채워져 있는지 `grep -c '^| V-[123] |.*| \(허용\|거부\)' docs/exec-plans/active/2026-09-15-sync-transport-encryption.md` = 3 으로 확인(빈칸 `—` 는 세지 않음).
- [ ] 목표 14 — `age` 미설치 컴퓨터에서 세션 시작·종료 훅이 exit 0 으로 한 줄만 알리고 push · pull 을 건너뛴다(planner-lite 지적 — zeroday 동료 4명 전원이 이 경로를 매 세션 밟는다). 검증: 테스트가 `PATH` 에서 `age` 를 뺀 채 두 훅 실행 → exit 0, `state.db` 변경 0, 알림 1줄.
- [ ] 목표 15 — 사내 서버가 사용자 정의 참조를 거부하고 폴백 브랜치도 원치 않으면 **그 소우주는 이식을 켜지 않는다**(planner-lite 지적). 폴백 브랜치 `hermes/sync` 는 동료 브랜치 목록에 보이므로 zeroday 는 V-2 결과가 "참조 허용" 일 때만 켠다. 검증: `enable-sync.md` 에 이 분기가 명시되고, `hermes-sync.py status` 가 참조 거부를 감지하면 "이식 불가 — 사람 판단" 을 낸다. (2026-09-16 사용자 위임으로 확정 — decision-log 7절 **T-15** 로 기록됨, T-07 의 "거부 시 브랜치 회귀" 는 부분 폐기.)

## 3. 비목표 (Out of Scope)

- 공개본(검은 박스 승인 흐름, G-7) — 별도 계획. 이번에는 금고본만.
- 이미 커밋된 평문 원문의 이력 재작성(T-03 확정: 손대지 않는다). 유효 자격증명 교체는 저장소별 사용자 판단.
- 마스킹 엔진 교체(Betterleaks 등) — 기존 `hermes_redact.py` · `hermes_secret_values.py` 유지.
- Claude Code 자체 기록(`~/.claude/projects/*.jsonl`) 보호 — 우리 범위 밖(설계 raw-transcript §1 표).
- Codex 세션 훅(RV-04 한계 — 문서로만).
- `tombstone` 물리 삭제 스크립트는 만들되 **사람 실행 전용**(세션 안 차단 목록에 포함).
- `hermes-scrub-history.py`(평문 jsonl 소급 제거 도구)를 암호 조각에 맞게 고치는 일 — 조각은 `tombstone` 경로로만 지운다. 옛 도구는 레거시 jsonl 전용으로 남긴다.

## 4. 영향 영역

- 코드(수정): `presets/workflow/hermes.conf`(gitignore 예외 제거, 새 훅·스크립트 등록, `_hermes_setup` 에서 `sync.json` 안내), `assets/hooks/claude-stop-retrospective.sh`(export 호출 → `hermes-sync.py push`), `assets/hooks/claude-sessionstart-history-reindex.sh`(→ 새 pull 훅으로 교체, 옛 jsonl 경로는 "레거시 읽기 전용" 분기만 유지), `scripts/hermes-export-history.py`(턴 조각 생성으로 축소), `scripts/hermes-reindex.py`(조각 복호 입력), `scripts/hermes-lifecycle.py` · `scripts/hermes_lifecycle_apply.py`(압축 방식 변경 G-1), `scripts/hermes_journal.py`(원격 사본 만들 때 세 칸 암호화 훅), `docs/hermes-universe/design/protection/*.md`(구현 확정 표시).
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `scripts/hermes_crypto.py` — `age` CLI 를 subprocess 로 감싸 암호화·복호화·수신자 목록·마스터 열쇠 감싸기/풀기만 제공한다(키 정책 없음).
  - `scripts/hermes_keys.py` — 열쇠 파일 위치(`~/.hermes/keys/<universe_id>/`)·자물쇠 지문·`keys/` 목록·`key.registered`/`key.revoked` 이벤트 등 열쇠 **정책**을 담당한다.
  - `scripts/hermes-keys.sh` — AI 세션 밖에서 사람이 부르는 열쇠 CLI(`init` · `add-computer` · `emergency` · `revoke` · `doctor`). 절차와 안내문만, 계산은 위 두 모듈.
  - `scripts/hermes_sync_ref.py` — `refs/hermes/sync` 의 저수준 git 조작만(트리 만들기 · commit-tree · update-ref · fetch · 임시 worktree 병합 · push · 재시도).
  - `scripts/hermes_sync_fragments.py` — 원문 턴 조각·이력 이벤트·기억 이벤트를 원격 경로(`history/` · `journal/` · `memory/` · `keys/`)로 사상하고 새 조각만 고르는 규칙.
  - `scripts/hermes-sync.py` — CLI(`push` · `pull` · `backfill` · `status` · `tombstone`)와 push 정책(`.hermes/sync.json`) 판정.
  - `assets/hooks/claude-pretooluse-key-guard.sh` — 세션 안 Bash 에서 열쇠 생성·입력 명령을 차단한다(T-11).
  - `assets/hooks/claude-sessionstart-sync-pull.sh` — fetch → 새 조각 복호 → 재색인, 열쇠 없음·미복호 판정과 H-10 안내.
  - `tests/hermes-keys-test.sh` — 열쇠 CLI 여섯 명령과 마스터 열쇠 감싸기(목표 3·4)를 임시 HOME 에서 검증한다.
  - `tests/hermes-sync-test.sh` — 조각·push/pull·참조 병합·백필·압축(목표 2·6~12)을 bare 원격으로 검증한다.
  - `tests/hermes-key-guard-test.sh` — 열쇠 차단 훅의 차단/통과 케이스.
  - `docs/hermes-universe/migration/enable-sync.md` — 소우주에서 이식을 켜는 사람 절차(열쇠 생성 → 비상 열쇠 → `sync.json` → 백필 → 첫 push)와 V-1~V-3 실측 명령.
- 게이트 대비: `hermes_sync_ref.py` 는 공개 심볼 7개 이하(`fetch` · `merge_into` · `commit_fragments` · `push_with_retry` 등, 임시 worktree 처리는 `_` 내부). 테스트를 둘로 나눈 이유는 R-size 400줄.
- 룰: 새 R 룰 후보 "원문은 소우주 저장소와 그 원격 밖으로 나가지 않는다"(T-02), "열쇠는 AI 세션 안에서 다루지 않는다"(T-11). 강제: gitignore 마커 + 키 가드 훅 + 테스트.
- 데이터: `state.db` 에 `sync_cursor`(원격에서 받은 조각 id) · `sync_outbox`(아직 못 올린 조각) 테이블 추가. `session_history` 는 그대로.
- 외부 의존: **`age` CLI**(V-6 결정, §6). 사용자가 WSL 에 설치(`apt install age` 또는 GitHub 릴리스 바이너리). `hermes-keys.sh doctor` 와 세션 시작 훅이 부재를 알린다.

### 원격 배치(안)

```text
refs/hermes/sync
 ├─ keys/<사람 id>/master.<자물쇠 지문>.age     마스터 열쇠를 각 자물쇠로 감싼 것 (RV-03)
 ├─ keys/<사람 id>/<자물쇠 지문>.pub            자물쇠 (공개, G-3 닫힘)
 ├─ history/<session_id>/<순번>.enc             원문 턴 조각 (마스터 자물쇠로 통째 암호화)
 ├─ history/<session_id>/<순번>.superseded      압축 표시 (G-1)
 ├─ journal/<YYYY>/<MM>/<DD>/<event_id>.json    기계 칸 평문, 자유 글 3칸 암호문
 └─ memory/<agent_id>/<memory_id>.json          계획 4 에서 채움 (경로만 예약)
```

## 5. 단계 (Steps)

### Step 0. 사용자 실측 V-1 · V-2 · V-3 [사용자 실행 — 구현 전]

- 명령(각 원격에서, AI 세션 밖 터미널):
  ```bash
  git push origin HEAD:refs/hermes/sync-probe          # V-1 (gitlab.com), V-2 (사내 서버)
  git ls-remote origin 'refs/hermes/*'                 # V-3 광고 여부
  git fetch origin refs/hermes/sync-probe:refs/hermes/sync-probe
  git push origin :refs/hermes/sync-probe              # 정리
  ```
- 산출: 결과를 §7 표에 기록. 거부된 서버가 있으면 그 소우주는 목표 15(T-15) 분기 — 사람이 폴백 브랜치 `hermes/sync` 를 원할 때만 `hermes_sync_ref.py` 의 참조 이름을 바꾸고, 원치 않으면 이식을 켜지 않는다.
- 검증: 목표 13.

### Step 1. gitignore 예외 제거 + export 축소 [Impl]

- 산출: `hermes.conf` 수정, `hermes-export-history.py` 를 "턴 조각 평문 생성" 으로 줄임(암호화는 Step 3 이 붙임). 옛 세션 파일 재작성 코드 삭제.
- 검증: 목표 1·2.

### Step 2. 암호 계층 [Plan/Impl/Review]

- 산출: `hermes_crypto.py`, `hermes_keys.py`, `hermes-keys.sh`, 키 가드 훅.
- 검증: 목표 3·4·5.
- Review 승격 사유: 보안. code-reviewer + 사람 확인. 열쇠 파일 권한 0600, 마스터 열쇠 평문은 `~/.hermes/keys/` 밖으로 나가지 않음을 테스트로 고정.

### Step 3. 운반 계층 [Plan/Impl/Review]

- 산출: `hermes_sync_ref.py`, `hermes_sync_fragments.py`, `hermes-sync.py`, Stop 훅·SessionStart 훅 교체, `sync_cursor` · `sync_outbox`.
- 검증: 목표 6·7·8·9·11. 참조 병합은 임시 worktree 경로(git 2.25.1)로 구현하고 `merge-tree --write-tree` 는 버전 감지 시 우선.
- Review 승격 사유: 동시성(두 컴퓨터 push) + 공유 경계.

### Step 4. 백필·압축 [Impl]

- 산출: `backfill`, 압축 방식 변경(요약 조각 + `.superseded`), `hermes-lifecycle.py` 수정.
- 검증: 목표 10·12. 기존 `tests/hermes-lifecycle-test.sh` · `hermes-history-export-test.sh` 통과(후자는 새 조각 형식으로 갱신).

### Step 5. 이식 켜기 절차 문서 + 소우주 적용 [사용자 실행]

- 산출: `migration/enable-sync.md`. terminal-shipping(혼자, B 정책)부터 켜고 zeroday-frontend(4명)는 V-2 결과 확인 후. 각 소우주 `.gitignore` 변경 커밋은 사용자.
- 검증: 다른 컴퓨터에서 clone → 열쇠 없음 안내 → `add-computer` → 재색인 성공.

## 6. 의사결정 로그

- 2026-09-15: **V-6 = `age` CLI**(pyrage 아님) — 근거: 기존 헤르메스 스크립트가 모두 subprocess·표준 모듈만 쓰고 pip 의존이 없다. 이 환경은 Python 3.10(WSL)·3.12(pyenv) 둘이라 pyrage 를 양쪽에 깔아야 한다. `age` 는 단일 바이너리. 틀렸을 때 손해: 컴퓨터마다 바이너리 설치 한 번(doctor 가 알림).
- 2026-09-15: 참조 이름은 `refs/hermes/sync`, 폴백은 브랜치 `hermes/sync` — 근거: T-07. V-1~V-3 이 거부되면 이름만 바꾼다(코드 상수 1개). 틀렸을 때 손해: 브랜치는 동료 브랜치 목록에 보인다.
- 2026-09-15: push 정책 파일이 없으면 로컬 전용(C) — 근거: T-01 기본값. 켜는 것은 사람의 명시 행위. 틀렸을 때 손해: 이식을 켜는 걸 잊으면 다른 컴퓨터에서 백지 — 세션 시작 훅이 "이식 꺼짐" 을 한 줄 알린다.
- 2026-09-15: `.hermes/sync.json` 은 **컴퓨터 로컬**(`.hermes/*` 무시 규칙 그대로, 커밋 안 함) — 근거: zeroday 동료 clone 이 `push: true` 를 물려받으면 열쇠 없는 컴퓨터가 매 세션 "보류" 를 찍는다. 사람마다 자기 컴퓨터에서 켠다. 틀렸을 때 손해: 컴퓨터마다 한 번씩 켜야 한다(`enable-sync.md` 절차).
- 2026-09-15: 마스터 열쇠 평문은 `~/.hermes/keys/<universe_id>/master.key`(0600) 에만, 원격에는 감싼 형태만 — 근거: RV-03. 틀렸을 때 손해: 컴퓨터 분실 시 마스터 교체 필요(G-4 절차, 옛 조각은 옛 마스터로).
- 2026-09-16: 비상 열쇠는 74자 age 문자열이 아니라 **24단어 니모닉**으로 보여 주고 받는다 — 근거: Aside Vault 복구 키 관찰(12단어 + 이해 확인 + 저장 파일). 손으로 옮겨 적을 때 오타가 줄고 체크섬으로 오타를 잡는다. 24단어인 이유: age 열쇠 32바이트를 파생 없이 그대로 담으려면 256비트 = 24단어. 틀렸을 때 손해: 니모닉 변환 코드(BIP-39 사전 2048단어 동봉)가 하나 늘고, 12단어 대비 옮겨 적을 양이 두 배.
- 2026-09-16: 설계 문서 갱신으로 계획서와 설계가 일치 — 근거: 대조 77건.
- 2026-09-15: `tombstone` 물리 삭제는 CLI 에 넣되 키 가드와 같은 차단 목록에 올려 세션 안에서 못 부르게 한다 — 근거: G-5 "사람 승인". 틀렸을 때 손해: 급할 때 세션 밖으로 나가야 함(의도된 마찰).

## 7. 발견·예외

- Step 0 결과 기록 자리(목표 13 검증이 이 표를 `grep` 한다 — 결과 칸에 `허용` 또는 `거부` 를 적는다):

  | # | 대상 | 결과 | 비고 |
  |---|---|---|---|
  | V-1 | gitlab.com `refs/hermes/sync` push | — | |
  | V-2 | 사내 서버(`211.206.116.39:3000`) 종류 · push | — | 종류: |
  | V-3 | 사용자 정의 참조 광고(`ls-remote`) | — | |
- 세션 시작 훅이 하나 더 늘어 시작 지연이 생긴다. 기존 `history-reindex` 훅을 교체하는 것이므로 순증은 fetch 한 번.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보: T-02 · T-11 을 R 룰로.

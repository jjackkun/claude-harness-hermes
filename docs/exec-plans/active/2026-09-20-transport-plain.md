# 2026-09-20-transport-plain — 발전 재료를 평문으로, 설치기가 켠다 (T-17 ~ T-21 구현)

> 출처: 2026-09-20 논의 — `docs/audits/2026-09-20-transport-keys-rethink.md`. 설계 결정: T-17(대상) · T-18(읽을 권리 = 접근권) · T-19(공개 판별) · T-20(마스킹 세 겹) · T-21(설치기 자동).
> 선행: agent-memory-roundtrip 목표 1~4·6~8 완료(MEMORY.md 재생성·기억 왕복 테스트·age 설치기). 이 계획이 끝나면 roundtrip 목표 5(시연)를 닫는다.

## 1. 동기 (Why)

실측: 발전에 쓰이는 요약·패턴 수는 안 올라가고, 발전에 안 쓰이는 원문은 암호화해 올리기로 했다. 열쇠는 사람이 세션 밖에서 만들어야 해 어느 소우주도 켜지 않았다.
결과 "원본 에이전트가 컴퓨터를 따라간다" 가 성립하지 않는다. 대상과 기본값을 바꾸면 사람 손 없이 성립한다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 (T-17) — `hermes-sync.py push` 가 **요약**(`summary/<session_id>.json`, `session_summary` 행)과 **패턴 수**(`pattern/<project_id>/<key>.json`, `pattern_count` 행)를 올리고, `pull` 이 `session_summary`·`pattern_count` 에 되넣는다(같은 키는 count 큰 쪽·최신 우선, 결정화 여부는 OR). — 검증: `hermes-sync-test.sh` 12절: A 요약 2·패턴 2(count 2·1) → B pull → B 에 요약 2, 패턴 키별 count 일치, A 에서 같은 키 1회 더 → B 재pull 시 count 3
- [x] 목표 2 (T-17) — `history/`(대화 원문)는 **기본 제외**. `sync.json` 에 `"history": true` 가 있을 때만 올린다(그때는 잠금 필수 → 열쇠 없으면 거부). — 검증: 같은 테스트 13절: 기본 push 뒤 원격에 `history/` 0 · `"history": true` + 열쇠 없음 → push 거부 exit 2 · 열쇠 있음 → 기존 9절대로
- [x] 목표 3 (T-18) — 평문 모드: `sync.json` 에 `"mode": "plain"` 이면 `journal/`·`memory/`·`summary/`·`pattern/` 의 자유 글을 **암호화하지 않고** 올리고, pull 은 복호 없이 적재. 열쇠·`keys/` 를 요구하지 않는다. 잠금 모드(`"mode": "locked"`)는 지금 코드 그대로. — 검증: 14절: plain 모드로 A push → 원격 memory 파일의 body 가 평문 · B(열쇠 없음) pull → memory_events 적재 · MEMORY.md 생성
- [x] 목표 4 (T-20) — 마스킹 세 겹이 **업로드 직전** 한 번 더 돈다: `outgoing()` 이 자유 글 칸마다 `hermes_redact.redact` 를 통과시킨다(plain·locked 모두). 생성 단계 치환은 `hermes-summarize.py` `SUMMARY_PROMPT` 와 `hermes-agent.py note`(agent-teaching 목표 9) 지시문에 "실제 사람 이름·주소·연락처·계좌·차량번호는 역할·종류로" 한 줄. 자동 정답지에 `git config user.name`·최근 커밋 작성자·명부 이름·OS 사용자명을 더한다(`hermes_secret_values` 옆 새 모듈, 값은 출력 금지). 꼴 규칙에 한국 주소(`시·도 + 구·군 + 로·길 + 번지`)·계좌번호 추가. — 검증: `hermes-redact-boundary-test.sh` 에 업로드 게이트 절 + `hermes-redact` 단위 테스트에 주소·계좌·작성자 이름 3건
- [x] 목표 5 (T-19·T-21) — 설치기(`project-claude.sh`, hermes 프리셋)가 원격 공개 여부를 판별해 `sync.json` 을 쓴다: 비공개 → `{"push": true, "mode": "plain"}` + 첫 push · 공개/미상 → `{"push": false}` + 설치 로그 한 줄(켜는 법). 이미 `sync.json` 이 있으면 손대지 않는다. `CLAUDECODE` 가 있으면 전체 건너뜀. 판별은 `gh repo view --json visibility` → 실패 시 미상. — 검증: `tests/sync-autoenable-test.sh`(gh 스텁으로 PRIVATE/PUBLIC/실패 세 경우 + 기존 sync.json 보존 + CLAUDECODE 건너뜀)
- [x] 목표 6 — 세션 시작 pull 훅·Stop push 훅이 plain 모드에서 age 없이 돈다(age 확인은 locked 모드에서만). — 검증: 9절 "age 없음" 을 plain 모드에서는 정상 pull 로 바꿔 단언
- [ ] 목표 7 — 안내서·CLAUDE.md 절 갱신: `docs/hermes-sync-guide.md` 를 "기본은 자동(설치기), 열쇠는 공개 저장소 옵션" 으로 다시 쓰고 hermes.conf 의 "기억 운반" 절도 맞춘다. `hermes_sync_fragments.py`·`hermes-sync.py` 머리말 갱신 — 검증: `grep` 으로 "세션 밖 터미널" 이 옵션 절에만
- [ ] 목표 8 — roundtrip 목표 5 시연: 비공개 임시 bare 원격에서 설치기 → 자동 켜짐 → 게이트QA `teach`/note 1건 → push → 두 번째 clone pull → MEMORY.md 일치. — 검증: 시연 기록(roundtrip §7)
- [ ] 목표 9 — 설치 폐로·의존 계층·고아 검사 — `install-closure-test` · `dep-contract-test` · `run-all.sh --check-orphans`

## 3. 비목표 (Out of Scope)

- 열쇠·age 코드 삭제 — 공개 저장소 옵션으로 남긴다.
- 기억·요약의 병합 규칙 고도화(충돌 해소는 memory-conflicts 그대로; 요약은 session_id 가 PK 라 충돌 없음).
- 사람이 관리하는 개인정보 목록(T-20 금지).
- Codex 세션 훅.

## 4. 영향 영역

- 코드: `scripts/hermes_sync_fragments.py`(summary/pattern 조각 · plain 모드 분기 · 업로드 게이트) · `scripts/hermes-sync.py`(mode·history 정책·age 요구 조건) · `scripts/hermes-summarize.py`(지시문) ·
  `assets/hooks/claude-sessionstart-sync-pull.sh`·`claude-stop-retrospective.sh`(age 확인 조건) · `presets/workflow/hermes.conf`(자동 켜기 훅·CLAUDE.md 절) · `scripts/hermes_redact.py`(꼴 2종)
- **신규 파일 목록**:
  - `scripts/hermes_sync_learning.py` — 세션 요약·패턴 수(발전 재료)를 운반 조각으로 내고 되넣는다(요약은 updated_at 최신, 패턴은 키별 max). 자물쇠가 없으면 평문. 공개 함수 2개
  - `lib/sync_autoenable.sh` — 공개 여부 판별 + `sync.json` 기본값 작성 + 첫 push(설치기 단계, 세션 안이면 건너뜀). 공개 함수 2개
  - `scripts/hermes_known_values.py` — 기계가 이미 아는 값(git 작성자·명부·OS 사용자명)을 마스킹 정답지로 모은다. 값 출력 금지. 공개 함수 1개
  - `tests/sync-autoenable-test.sh` — gh 스텁 세 경우·보존·세션 건너뜀
  - `tests/hermes-redact-pii-test.sh` — 개인정보 꼴(주소·계좌)과 자동 정답지 이름 마스킹, 날짜·`main` 은 안 가림(과마스킹 방지)
- 룰: R3(모델 호출 0 — 판별은 gh CLI, 마스킹은 규칙) · R-iface(신규 ≤7) · R-dep(`.deprc`: known_values tier 0, sync_fragments 가 import → tier 유지 확인)
- 설치: `hermes.conf` 복사 목록에 `hermes_known_values.py`, 설치기 단계 등록 → 전파.
- 데이터: `sync_cursor`·`sync_outbox` 그대로. `sync.json` 형식에 `mode`·`history` 칸 추가(없으면 locked·history false 로 해석해 구버전과 호환).

## 5. 단계 (Steps)

### Step 1. 요약·패턴 조각 push/pull + 원문 기본 제외 (목표 1·2, 테스트 RED→GREEN) [Impl]
### Step 2. plain 모드 + 업로드 직전 마스킹 게이트 + 자동 정답지·꼴 2종 (목표 3·4) [Impl]
### Step 3. 설치기 자동 켜기 + 훅의 age 조건 (목표 5·6) [Impl]
### Step 4. 문서·CLAUDE.md·머리말 (목표 7) · 시연 (목표 8) · 폐로 (목표 9) [Review]

## 6. 의사결정 로그

- 2026-09-20: 요약 병합은 session_id PK 로 단순 삽입, 패턴 수는 키별 max — 근거: 두 컴퓨터가 같은 세션을 만들 수 없고, 패턴은 "몇 번 봤나" 라 큰 쪽이 사실에 가깝다. 합산은 같은 세션이 양쪽에 있을 때 이중 계산.
- 2026-09-20: plain/locked 를 `sync.json` 한 칸으로 — 근거: 정책 파일이 이미 컴퓨터 로컬·비커밋이라 자리에 맞다.
- 2026-09-20: 공개 판별에 `gh` 만 쓴다(원격 URL 휴리스틱 없음) — 근거: URL 로는 공개 여부를 알 수 없다. gh 없으면 "미상=끔" 이 안전한 쪽.

## 7. 발견·예외

- 2026-09-20 Step 1 완료: `hermes_sync_learning.py`(summary/·pattern/ 조각) · `outgoing(policy)` 가 history/ 를 `"history": true` 일 때만 · `_import_all` 에 summary/pattern 분기.
  테스트 `hermes-sync-test.sh` 12절(13단언: 요약 2·패턴 2 업로드, 원문 0, 잠금 모드 암호문, G 적재·평문 복원·count max·멱등, 옵션 켜면 원문 업로드) → 64/64. 기존 2~11절은 픽스처 정책을 `"history": true` 로 바꿔 잠금+원문 검증으로 유지.
- 설계와 다른 점: 요약·패턴 조각 로직을 `hermes_sync_fragments.py` 안이 아니라 새 모듈로 뺐다 — fragments 의 공개 심볼이 이미 7 이고 책임(경로 사상·새 것 판정)과 다르다. `.deprc` 같은 tier 2.
- `_seal/_open` 이 자물쇠 없음·평문을 처리하므로 Step 2 평문 모드는 `lock=None` 만 넘기면 된다.
- 2026-09-20 Step 2 완료: 평문 모드(`sync.json "mode": "plain"`) — 열쇠·age·keys/ 없이 push/pull, 잠금 컴퓨터가 올린 암호문 조각은 평문 컴퓨터가 조용히 건너뜀(같은 원격 공존).
  업로드 직전 마스킹 게이트(`_free_text` → `hermes_redact.redact`)가 journal·memory·summary·pattern 자유 글 전부에 적용. 평문 + `"history": true` 는 push 거부 exit 2(목표 2 의 거부 조건 여기서 실측).
  마스킹 꼴 2종(한국 주소·계좌) + 자동 정답지(`hermes_known_values`: git user.name·커밋 작성자·명부 이름·OS 사용자명, 짧은 일반어 제외). 요약 지시문에 개인정보 치환 한 줄.
  테스트: sync 14절 17단언 → 79/79 · `hermes-redact-pii-test.sh` 9(주소·계좌·이름 가림, 날짜·버전·main 안 가림) · redact 15 · dep 21.
- 2026-09-20 Step 3 완료: `lib/sync_autoenable.sh`(gh 로 공개 판별 → 비공개면 `{"push": true, "mode": "plain"}` + 첫 push, 공개·미상은 push false + 이유, 있는 sync.json·세션 안·옵트아웃은 건드리지 않음) 을 `_hermes_setup` 끝에 연결.
  sync-pull 훅은 잠금 모드에서만 age 를 요구. 테스트 `sync-autoenable-test.sh` 10(gh 스텁 PRIVATE/PUBLIC/실패·보존·세션 건너뜀·origin 없음) · sync 14절 훅 단언. 설치기를 부르는 테스트 14개 + run-all 에 `HARNESS_SYNC_AUTOENABLE=0`.
- code-reviewer(2026-09-20) 지적 3건 반영: ① 평문 컴퓨터가 건너뛴 암호문이 "안 받은 조각" 에 영원히 남음 → `sync_cursor` 에 `skip:locked` 기록, 잠금 모드 pull 은 `retry_skipped` 로 다시 받음.
  ② 마스킹된 `pattern_key` 가 다른 행으로 갈라짐 → 경로의 원본 해시로 로컬 행을 찾아 병합(스키마 변경 없음). ③ 암호문 판별이 부분 문자열 매치 → JSON 필드 값 접두어로. 단언 3건 추가 → sync 83.
- 발견: 평문 컴퓨터와 잠금 컴퓨터가 같은 원격을 쓰면 서로 못 읽는 조각이 생긴다(평문 컴퓨터는 암호문을, 잠금 컴퓨터는 평문을 — 후자는 읽는다). 한 소우주는 한 모드로 통일하는 것이 맞고, 설치기(Step 3)가 그렇게 정한다.

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:

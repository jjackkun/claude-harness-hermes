# 2026-09-18-skill-yield-junk — 도움 없는 스킬의 증거 기반 강등 + 일반 코드 단어 키 결정화 거부

> 출처: `docs/exec-plans/backlog/zeroday-pagename-skills.md` (본 계획으로 승격, backlog 파일 삭제)
> 설계 결정 인용: L-06 (스킬 생애주기 — 결정화 후보 제외 장치), G-8 은 질문 ID(결정 아님)

## 1. 동기 (Why)

zeroday-frontend 실측(2026-09-18, 로컬 스킬 1,095개 · 주입 3,471회):

| 키 형태 | 스킬 | 주입 | 도움 | 도움률 |
|---|---:|---:|---:|---:|
| 단일 영단어(`array`·`shared`·`index`·`postgres`·`weightclass`) | 167 | 2,587 | 100 | **3.9%** |
| 2+토큰 구절(`jira-comment-approval-gate`) | 768 | 699 | 696 | 99.6% |
| 한글 제목 | 65 | 123 | 112 | 91.1% |

`array`·`shared`·`index` 세 파일이 각 775회(합 2,327 = 전체의 67%) 주입되고 도움 2회. 본문은 같은 규칙("압축 뒤 요약을
먼저 읽어라")의 세 벌 복제인데 **키가 압축 요약 속 흔한 코드 단어로 뽑혀** 제목이 됐고, 그 제목이 거의 모든 프롬프트에
매칭된다. 기존 cleanup 은 불용어·한글 조각만 junk 로 보고, `index` 는 `pattern_count` 에서 -1(거부)인데도 스킬 파일이 남아 있다.
"페이지 이름" 은 이 문제의 작은 부분(D 형태 41개, 도움률 85%)이었다 — backlog 의 첫 가설을 실측이 뒤집었다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — `low_yield_skills(con)`: 주입 ≥ 50회이고 도움률 ≤ 5% 인 스킬만 고른다(둘 중 하나라도 못 미치면 제외)
  — 검증: `tests/hermes-skill-yield-test.sh` (a)
- [x] 목표 2 — `hermes-cleanup.py` (e) 절이 그 목록을 보고하고 `--apply` 때만 파일·`skill_index` 행 삭제 + `pattern_count`
  거부(-1) 표시 — 검증: 같은 테스트 (b)(c)
- [x] 목표 3 — `is_generic_key(key)`: 단일 ASCII 토큰이 일반 코드 단어 목록에 있으면 참. 결정화가 그런 키를 모델 호출 없이
  거부(-1)한다 — 검증: 같은 테스트 (d) — 가짜 `claude` 가 호출되면 실패하는 픽스처
- [x] 목표 4 — zeroday 실 DB dry-run 에서 `array`·`shared`·`index`·`postgres` 가 (e) 목록에 있다 — 검증: 실행 출력(읽기 전용)
- [x] 목표 5 — 표준 모듈만(R3), `.deprc`·`hermes.conf`·run-all 등록 — 검증: dep-contract·install-closure·orphan 검사

## 3. 비목표 (Out of Scope)

- 검색(`hermes-search`)의 점수식 변경 — 주입 측 원인이지만 범위가 크다. 결정화 입구와 사후 강등으로 막는다.
- zeroday 실 DB 에 `--apply` 실행 — 삭제라 사용자 확인 뒤 별도 명령.
- 같은 본문의 중복 스킬 병합.

## 4. 영향 영역

- 코드: `scripts/hermes-cleanup.py` (e) 절 추가·tier 0→1, `scripts/hermes-crystallize.py` 일반 단어 키 거부 1분기
- **신규 파일 목록**:
  - `scripts/hermes_skill_yield.py` — 주입 증거로 도움 없는 스킬을 고르고(`low_yield_skills`), 일반 코드 단어 단일 토큰 키를 판정(`is_generic_key`). 표준 모듈만, tier 0
  - `tests/hermes-skill-yield-test.sh` — 임계 경계·dry-run/apply·결정화 거부(모델 미호출) 실측
- 룰: R3 준수. `.deprc` 갱신, `hermes.conf` 복사 목록
- 데이터: `--apply` 시 삭제(파일·index 행) + `pattern_count.crystallized=-1`

## 5. 단계 (Steps)

### Step 1. RED — 테스트 [단순]
### Step 2. GREEN — 모듈 + cleanup (e) + crystallize 거부 [단순]
### Step 3. 등록·전체 스위트·zeroday dry-run·backlog 정리 [단순]

## 6. 의사결정 로그

- 2026-09-18: 임계 "주입 ≥ 50 · 도움률 ≤ 5%" — 근거: 실측에서 형태별 도움률이 3.9% 와 91~99% 로 갈리고, 50회면 5% 기대 도움
  2.5회라 우연히 0 이 나올 확률이 작다(이항 (0.95)^50 ≈ 7.7%). 두 조건을 모두 요구해 새 스킬(주입 적음)은 보호한다.
- 2026-09-18: 일반 단어 목록은 어휘 상수(약 40개)로 — 근거: R3(모델 호출 금지). 목록 밖 단일 토큰은 거부하지 않는다 —
  D 형태(`noticemanagementpage`) 도움률 85% 가 단일 토큰 전면 거부를 막는다.
- 2026-09-18: 강등 = 삭제 + 거부 표시 — 근거: 본문이 유용해도 제목이 잘못됐으면 같은 규칙이 올바른 키로 다시 결정화될 수
  있게 두는 편이 낫다. 파일 삭제는 `--apply` 뒤에서만.

## 7. 발견·예외

- backlog 의 가설("페이지 이름이 스킬로 굳었다")은 실측이 뒤집었다: 페이지 이름 형태(D)는 41개·도움률 85% 로 멀쩡했고,
  진짜 문제는 단일 코드 단어 키 4개가 주입의 67% 를 먹은 것이었다. 가설을 실측 전에 항목 이름으로 박은 것이 오류의 형태.
- `array`·`shared`·`index` 세 파일의 본문은 같은 규칙의 복제였다 — "압축 뒤 요약을 먼저 읽어라". 키 추출이 압축 요약
  본문에서 흔한 코드 토큰을 뽑은 것. 이 규칙은 삭제 뒤 올바른 키로 다시 결정화될 수 있게 거부 표시만 남긴다.
- zeroday 실 DB dry-run(읽기 전용): (e) 4개 — array 778/2 · index 776/0 · shared 776/0 · postgres 146/1. `--apply` 는
  사용자 확인 뒤 별도 실행.
- 픽스처 이름 `good` 이 기존 (b) 절의 영어 불용어라 삭제돼 RED/GREEN 이 한 번 섞였다 → `jira-gate` 로 변경.

## 8. 회고 (완료 시 작성)

- 잘된 것: 키 모양 추정 대신 `skill_injection.correlated` 라는 이미 쌓인 증거로 판정해 임계를 데이터에서 잡았다.
- 잘못된 것: backlog 항목 이름에 가설을 박았다. 실측 결과와 이름이 어긋나 항목을 이 계획으로 승격하며 이름을 바꿨다.
- 다음 룰 후보: "backlog 항목 이름은 관측(무엇이 보였나)으로, 원인 가설은 본문에" — 반복 시 템플릿에 반영.
  후속: 검색 점수식에서 단일 일반 토큰 매칭의 가중치를 낮추는 것(주입 측 원인, 비목표로 남김).

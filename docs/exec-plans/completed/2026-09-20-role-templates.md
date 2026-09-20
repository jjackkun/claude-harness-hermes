# 2026-09-20-role-templates — 역할 템플릿 기본기: ECC 68 + cumora 4 를 SOUL 초안 재료로 들여온다

> 출처: 2026-09-20 대화 — 사용자 "cumora 와 ecc 는 몇 개의 템플릿을 가지고 있어?" → ECC 68(`agents/*.md`)·cumora 4(`onboardCompany.ts`)·우리 0 →
> "그걸 다 가져오면 기본기가 되는 거 아냐?" → "착수하자". 둘 다 MIT.
> 설계 결정 인용: D-01(SOUL 은 사람 승인) · H-09(우주 템플릿으로 `hire --template`) · C-19(자연어→축 값 판별 모델 호출 없음) · R3(모델 호출은 구독 CLI 경로만).
> 선행: agent-hire-form 목표 5 재정의(SOUL 기계 초안, `hermes_soul_draft.py`).

## 1. 동기 (Why)

SOUL 초안이 "공통 조직에서 QA 을 맡는 담당이다" 수준에 머문다 — 역할 템플릿 층이 비어 있어서다(`hire --template` 인자는 있으나 가리킬 것이 0).
ECC 는 코드 세계 역할 68개를 사람이 미리 써 두었고, cumora 는 회사 시작 인원 4명의 역할·말투를 코드에 박아 두었다. 둘을 우리 형식으로 규칙 변환하면
입사 때 역할·책임 경계·원칙·도구가 채워진 초안이 나온다. 목록 밖 분야는 별도(모델 초안·성장 경로)로 덮는다 — 이 계획은 **씨앗 72개**까지다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 변환기 `python3 scripts/hermes-template-import.py --ecc <ecc 체크아웃> --out assets/templates/agent/roles/` 가 ECC `agents/*.md` 68개를
  우리 역할 템플릿 형식(frontmatter `name·origin·source_commit·tools·model·discipline_hint` + 절 `역할/책임 경계/원칙/도구`)으로 쓴다. `## Prompt Defense Baseline` 은 버린다.
  모델 호출 0, 재실행 멱등(같은 입력 → 같은 출력). — 검증: `bash tests/hermes-role-templates-test.sh` 변환 절(픽스처 ECC 파일 2개 → 형식·절·origin·방어 문구 제거·멱등)
- [x] 목표 2 — cumora 4개(Researcher·Designer·Engineer·Product Manager)를 같은 형식으로 손으로 옮긴다(`origin: cumora`, 말투는 `## 원칙` 에 "- 말투:" 로). — 검증: 4 파일 존재·frontmatter 검사
- [x] 목표 3 — `hermes-agent.py templates [--discipline <분야>]` 가 템플릿 목록(이름·출처·한 줄 설명)을 낸다. — 검증: 테스트 목록 절(72개, 분야 필터)
- [x] 목표 4 — `hire --template <이름>` 이 그 템플릿의 역할·책임 경계·원칙·도구를 SOUL 초안에 넣는다(조직 값 문장 + 템플릿 절 병합, 초안 표시 줄 유지). 없는 템플릿 이름은 거부(exit 2). — 검증: roster 테스트 입사 절 + 새 테스트 병합 절
- [x] 목표 5 — 기존 `assets/agents/*.md` 15개(ECC 이름과 같음)에 `origin: ECC` 표시를 붙인다. 서브에이전트(위임용)와 역할 템플릿(입사용)은 층이 다르다는 것을 문서에 한 줄. — 검증: `grep -l 'origin: ECC' assets/agents/*.md | wc -l` = 15
- [x] 목표 6 — 설치 폐로: 템플릿 폴더가 소우주로 복사되고(`hermes.conf`), `.deprc`·`run-all` 등록. — 검증: `install-closure-test` · `dep-contract-test` · `run-all.sh --check-orphans`
- [x] 목표 7 — 스킬 문서(hermes-agent 1절·0-2 폼)에 "분야에 맞는 템플릿 후보를 보이고 고르게 한다" 한 줄. — 검증: grep

## 3. 비목표 (Out of Scope)

- 영어 본문 번역(모델 68회 + 검수) — 머리말만 한국어. 나중 결정.
- ECC 68개를 서브에이전트(`assets/agents/`)로도 까는 것 — dispatch 표면·R-agent 권장이 흐려진다.
- 목록 밖 분야의 모델 초안, 검증된 에이전트 → 우주 템플릿 성장(H-09) — 별도 계획.
- 상류 자동 추적 — 변환기는 사람이 돌린다(`origin`·`source_commit` 으로 대조).

## 4. 영향 영역

- 코드: `scripts/hermes_soul_draft.py`(템플릿 절 병합) · `scripts/hermes-agent.py`(`templates` 명령, `--template` 검증, `soul-draft --template`) · `assets/skills/hermes-agent/SKILL.md` · `project-claude.sh`(`HARNESS_REGISTER=0` 등록 옵트아웃 — 테스트 설치의 등록부 오염 방지) · `presets/workflow/hermes.conf`(스크립트 2 + roles/ 복사)
- **신규 파일 목록**:
  - `scripts/hermes-template-import.py` — ECC `agents/*.md` → 우리 역할 템플릿 변환기(규칙, 멱등). 공개 함수 ≤4
  - `scripts/hermes_role_templates.py` — 템플릿 폴더 읽기·목록·이름 검증·SOUL 절 추출. 공개 함수 ≤4
  - `assets/templates/agent/roles/<이름>.md` × 72 — 변환·수기 결과물(자료, 코드 아님)
  - `tests/hermes-role-templates-test.sh` — 변환·목록·병합·거부 실측(픽스처 ECC 파일 2개, 네트워크 0)
- 룰: R3(모델 호출 0) · R-iface(신규 ≤7) · R-dep(`hermes_role_templates` tier 0, soul_draft(2)·agent(3) 가 부름) · R-size(변환기 400줄 이내)
- 설치: `hermes.conf` 복사 목록에 스크립트 2 + `assets/templates/agent/roles/` 폴더 복사(기존 SOUL 틀 복사 경로와 같은 곳).
- 데이터: 없음(파일 자료). 출처 표시: 파일마다 `origin: ECC@<commit>` / `origin: cumora`.

## 5. 단계 (Steps)

### Step 1. 원본 확보(ECC 얕은 clone, cumora 4 문자열) + 변환기 + 픽스처 테스트(RED→GREEN) [Impl]
### Step 2. 72개 생성 · cumora 4 수기 · `templates` 목록 명령 [Impl]
### Step 3. `hire --template` 병합 + 거부 + 스킬 문서 + `assets/agents` origin 표시 [Impl]
### Step 4. 등록·폐로·시연(게이트QA 에 `qa` 계열 템플릿 적용) [Review]

## 6. 의사결정 로그

- 2026-09-20: 번역하지 않는다 — 근거: 모델 68회 호출과 사람 검수가 필요하고, 에이전트는 영어 본문을 읽는다. 머리말·절 제목만 한국어.
- 2026-09-20: 템플릿 파일은 코드가 아니라 자료로 취급(`assets/templates/agent/roles/`) — 근거: R-size·R-iface 게이트 밖, 소우주로 복사 설치.
- 2026-09-20: ECC 의 방어 문구 절은 버린다 — 근거: 우리 가드(훅·게이트)가 그 역할을 하고, SOUL 에 남으면 모든 에이전트가 같은 보일러플레이트를 읽는다.

## 7. 발견·예외

- ECC 68개 절 제목은 40여 종 — `Your Role/Core Responsibilities/Review Priorities/Scope*/When*` 은 책임 경계, `Diagnostic Commands/Reference` 는 도구, 나머지는 원칙으로 보냈다. 범위 절이 없는 16개(리뷰어 다수)는 안내 문구 한 줄로 둔다 — 역할 문단이 범위를 말한다.
- `Prompt Defense Baseline` 절 안의 산문("You are …")은 정체성 문장이라 역할로 살리고, 불릿(주입 방어 지시)만 버렸다.
- 템플릿을 이으면 SOUL 이 300줄을 넘는다(게이트QA + code-reviewer = 345줄). 소환 주입은 4,096 B 에서 잘리고 원문 경로를 가리키므로(soul-inject 목표 3) 세션 예산은 안전하다. 사람이 승인하며 줄이는 것이 D-01 의 뜻과 맞는다.
- 설치본에서 `templates` 가 ModuleNotFoundError — hermes.conf 복사 목록에 스크립트 2개를 빠뜨렸다. 폐로 테스트(5절)가 잡았다.
- `discipline_hint` 는 이름 규칙 매핑(QA 28·백엔드 18·기획 10·디자인 2·영업 1·general 10). 조직 축 값과 다르면 사람이 `templates` 전체 목록에서 고른다.
- 시연: `soul-draft 게이트QA --template code-reviewer` → 명부 template=code-reviewer@factory, SOUL 초안에 Review Process·Checklist·Approval Criteria 절이 이어졌고 초안 표시 줄은 남아 있다(승인 전).

## 8. 회고 (완료 시 작성)

- 잘된 것: 규칙 변환만으로 72개가 한 번에 섰고(모델 호출 0), 멱등이라 상류 갱신은 재실행 한 줄이다. 픽스처 2개 테스트가 변환 규칙을 고정한다.
- 잘못된 것: 복사 목록 누락을 코드로 먼저 발견하지 못하고 폐로 테스트로 발견 — 새 스크립트를 만들면 hermes.conf 복사 목록을 같은 커밋에서 손보는 것이 순서다. `convert()` 복잡도 17 → 통 나누기로 분리.
- 다음 룰 후보: "scripts/ 에 새 파일 → hermes.conf 복사 목록 등록" 을 R-declare 처럼 훅에서 경고(설치 폐로 자동 검사). 테스트 설치는 `HARNESS_REGISTER=0` 를 반드시 붙인다 — 기존 테스트(roster 등)도 옮길 것.

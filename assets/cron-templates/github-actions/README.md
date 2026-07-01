# Harness Garbage Collection Workflows (PDF 12쪽 — 4차원)

> PDF "하네스 엔지니어링" 12쪽 — 황금 원칙과 정기 정리 프로세스.
>
> 인용: *"가비지 컬렉션처럼 작동합니다. 기술 부채는 고금리 대출과 같아서,
> 이자가 쌓여 고통스럽게 한꺼번에 갚는 것보다 조금씩 꾸준히 갚아나가는
> 편이 훨씬 낫습니다."*

## 이것은 무엇인가

ai-dev-setting harness 의 **4차원 방어**. 1차(코드 강제 린터), 2차(pre-commit
게이트), 3차(UserPromptSubmit 리마인더) 위에 올라가는 *정기 정리 작업*.

세 개의 스케줄된 GitHub Actions 워크플로 템플릿:

| 파일 | 주기 | 역할 |
|---|---|---|
| `nightly-quality-score.yml` | 매일 새벽 | `docs/QUALITY_SCORE.md` 를 자동 갱신. 편차 점수화 |
| `weekly-doc-gardening.yml` | 매주 | 코드와 `docs/` 동기화 검증. 고아 문서/누락 링크 감지 |
| `weekly-tech-debt-pr.yml` | 매주 | `docs/tech-debt-tracker.md` 에서 상위 항목 1개를 골라 리팩터링 PR 생성 |

## 자동 배치 현황 (2026-04-21~)

| 파일 | 자동 설치 | 이유 |
|---|---|---|
| `weekly-doc-gardening.yml` | ✅ ON (HARNESS_DOC_GARDENING=1) | 비용 없음. remote 감지로 GitHub/GitLab 판별 (`lib/common.sh::install_harness_gc_workflows`). has_drift=false 면 Issue 안 만들므로 빈 프로젝트에도 노이즈 없음. |
| `nightly-quality-score.yml` | ❌ 수동 | Claude API 호출 — 명시 승인 필요 |
| `weekly-tech-debt-pr.yml` | ❌ 수동 | Claude API 호출 — 명시 승인 필요 |

**GitLab 판**은 `../gitlab-ci/weekly-doc-gardening.gitlab-ci.yml` 참조. 동일 검사 로직,
GitLab Issue API 사용. `HARNESS_DOC_GARDENING=1` 일 때 remote 가 gitlab 이면 자동 선택됨.

끄고 싶으면: `presets/workflow/harness.conf` 에서 `HARNESS_DOC_GARDENING=0`.

## 🚨 수동 설치 워크플로 — 켜기 전에 결정해야 할 것

아래 **자동 배치되지 않는 파일들** 은 비용/위험 때문에 사용자 명시 승인을 요구한다:

1. **PDF 11쪽 "일반화 금지"** — 각 프로젝트의 실제 편차 유형에 맞게 프롬프트를 수정해야 함.
2. **비용** — `weekly-tech-debt-pr.yml` 은 Claude API 를 호출한다. 초기엔 월
   구독 한도로 충분하지만, 인지하고 시작할 일.
3. **전제 조건** — 다음을 가정한다:
   - `docs/` 디렉터리가 존재 (`docs-templates` preset 로 생성된 상태)
   - `core-beliefs.md` 에 도메인 룰이 정의돼 있어 편차 측정의 기준점이 있음
   - GitHub Actions 가 활성화돼 있고 `ANTHROPIC_API_KEY` 시크릿이 등록됨

## 언제 켜는가

- ✅ 운영 중인 제품 리포 — 6개월 이상 유지될 예정
- ✅ 여러 에이전트가 동시에 작업 — 엔트로피 누적 속도가 빠름
- ✅ 도메인 룰(`core-beliefs.md`)이 10개 이상 — 편차가 생길 표면적이 큼
- ❌ 학습/실험 프로젝트 — 끝나면 버릴 코드
- ❌ 초기 부트스트랩(첫 2주) — 아직 룰이 안 굳음. 노이즈가 신호보다 큼

## 사용법

1. 본 디렉터리의 `.yml` 파일 중 필요한 것을 프로젝트의 `.github/workflows/` 로
   복사.
2. 각 파일 상단의 `### EDIT ME` 블록을 프로젝트 상황에 맞게 수정
   (시크릿 이름, branch 이름, 제외 경로 등).
3. GitHub 리포 설정에서 `Actions` 활성화 확인.
4. 시크릿 등록: `ANTHROPIC_API_KEY` (tech-debt-pr 용).
5. **수동으로 먼저 돌려본다** — 각 워크플로는 `workflow_dispatch` 를 지원.
   예상 결과가 나오는지 확인 후 cron 에 맡긴다.

## 일반화 금지 경고 (PDF 11쪽 적용)

> *"이 글에는 일반화될 만한 공통점이 있지만, 다른 것들은 저의 리포지토리
> 구조에 따라 다를 수 있습니다. 일반화 가능하다고 가정하고 읽지 마세요."*

본 템플릿은 *출발점* 이다. 각 프로젝트의 *실제 편차 유형* 이 무엇인지 알아낸
뒤 워크플로의 프롬프트·검사 로직을 *자기 도메인에 맞게 고친다*. 복사해서
그대로 돌리면 노이즈만 만든다.

# ci-red-restore — CI 가 60회 연속 실패 중이다: 신호를 되살린다

> 출처: 2026-09-20 check-secrets 작업 중 기존 테스트 하나가 이유 없이 빨개서 `gh run list` 를 처음 열어 봤다. 최근 60회 실행이 **전부 failure**.
> 그동안 "게이트 통과" 는 로컬 pre-commit(R-test = pytest 만)만 뜻했다. `tests/run-all.sh`(bash 테스트 84개)는 CI 에서만 도는데 아무도 결과를 보지 않았다.

## 실측 (커밋 d3bbd5f 의 CI 실행, 실패 10건을 로컬에서 재실행해 분류)

| 테스트 | 로컬 | 원인 | 누가 |
|---|---|---|---|
| check-secrets-answerkey-test | 실패 | 값 모듈을 픽스처 루트에 복사 — 검사기는 `scripts/` 에서 찾는다 | 기존(모듈 이동 뒤 방치) → **2026-09-20 수정** |
| harness-eval-test | 통과 | GitHub Actions 는 `CI=true` — 러너의 CI 거부에 자기 테스트가 걸림 | 이 세션 → **2026-09-20 수정** |
| raw-copy-guard-test | 실패 | `lib/tool_installers.sh:36` 의 raw `cp` 가 허용 목록 밖 | 이 세션(age 설치기) |
| harness-hooks-smoke | 실패 | `CLAUDE.md <= 100 줄 (102)` · "프로젝트 .py 가 섞이면 R-test 단계가 돈다" | 이 세션(CLAUDE.md 운반 절) + 미상 |
| sync-plugins.sh --check | 실패 | `agents/` 플러그인 사본 3개가 `assets/agents/` 와 어긋남(`origin: ECC` 주석 추가 뒤 동기화 안 함) | 이 세션(role-templates) |
| hermes-journal-test | 실패 | "rotate 스킬에 제외 문장" 없음 | 미상 |
| hermes-keys-test · hermes-sync-test | 통과 | 러너에 `age` 가 없다("전제: age 미설치") | CI 환경 — workflow 에 age 설치 단계 필요 |
| sync-autoenable-test | 통과 | 프로브·첫 push 단언이 러너에서 none (gh·네트워크·git 설정 차이 추정) | CI 환경 + 이 세션 |
| tool-installers-test | 통과 | `failed=age age-keygen` 기대가 러너에서 어긋남 | CI 환경 + 이 세션 |

## 고칠 때

1. 로컬에서도 빨간 넷(raw-copy-guard · hooks-smoke · sync-plugins · journal)부터 — 진짜 결함이다.
2. CI 전용 넷 — `.github/workflows/ci.yml` 에 age 설치(핀 고정·sha256, `lib/tool_installers.sh` 재사용) 또는 테스트가 "age 없음" 을 SKIP 으로 세게. sync-autoenable·tool-installers 는 러너 로그로 원인 확정.
3. 재발 방지: (a) 푸시 뒤 `gh run watch` 결과를 보고까지 "완료" 라고 하지 않는다. (b) pre-commit 의 R-test 가 pytest 만 돈다 — 바뀐 영역의 bash 테스트를 고르는 얇은 선택기(파일 → 테스트 매핑)를 검토. (c) 세션 시작 훅에 "마지막 CI 결과" 한 줄.

## 왜 가치 상인가

CI 가 늘 빨가면 빨간 것이 정보가 아니다. 오늘 하루 이 세션이 만든 회귀 5건이 그 뒤에 숨어 있었다.

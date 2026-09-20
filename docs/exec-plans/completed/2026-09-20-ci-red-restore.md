# 2026-09-20-ci-red-restore — CI 가 60회 연속 실패 중이었다: 신호를 되살린다 (완료)

> 백로그에서 바로 진행(사용자 "ci 고치자" 2026-09-20). 새 코드 파일 없음 — 테스트·설치기·워크플로 수정.

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

## 한 일 (2026-09-20)

| 실패 | 원인(실측) | 수정 |
|---|---|---|
| raw-copy-guard | 설치기의 raw `cp` 둘: ① 도구 배포 파일을 tmp 로 가져오는 것 ② **역할 템플릿 폴더를 `cp -r` 로 소우주에 쓰는 것**(오늘 role-templates) | ① 허용 목록에 이유와 함께 ② 파일마다 `install_factory_file` — 이제 매니페스트·doctor·공존 규칙이 72개를 추적한다 |
| harness-hooks-smoke | ① 하네스만 깐 CLAUDE.md 가 102줄(오늘 prettier 빈 줄 2개) ② `훅 \| grep -q` 가 pipefail 아래에서 훅의 종료코드를 돌려줌 — pytest 가 뜨는 기계·CI 에서는 [R-test] 가 찍혀도 빨강 | ① "세션 중" 문단 6줄 → 4줄(내용 그대로) ② 출력을 먼저 받아 검사. 덤으로 R-test 의 조용한 skip 을 경고 한 줄로 보이게(09-08 에 조용해짐) |
| sync-plugins --check | `assets/agents` 에 출처 주석을 넣고 플러그인 사본을 동기화하지 않음(오늘) | `scripts/sync-plugins.sh` 실행 |
| hermes-journal-test | `.gitignore` 된 기계 로컬 결정화 스킬을 단언 — 그 스킬을 만든 기계 밖에서는 늘 빨강 | 파일이 있을 때만 단언, 없으면 SKIP(통과로 세지 않음) |
| tool-installers · sync-autoenable | **run-all 이 설치기 옵트아웃을 전역 export**(이 세션에서 넣음) → 그 기능을 검증하는 두 테스트가 통째로 꺼짐. 로컬 단독 실행은 통과라 몰랐다 | 두 테스트가 스스로 켠다(네트워크 0 은 픽스처·스텁이 보장) |
| hermes-keys · hermes-sync | CI 러너에 age 없음 | `ci.yml` 에 age 설치 단계 |

**CI 에 age 를 깔자 드러난 2건**(a49aab0 의 CI: 실패 8 → 2): ① apt 의 age 는 버전을 `v` 없이 찍는다(`1.1.1`) — keys 테스트의 단언을 `v?` 로. ② tool-installers 테스트가 PATH 에 `/usr/bin` 을 통째로 넣어 러너의 시스템 age 를 발견 —
"없으면 설치한다" 시나리오가 성립하지 않았다 → 시스템 도구를 심링크로 모으되 age·age-keygen 만 뺀 PATH 를 쓴다.

**로컬 전용 4건도 찾았다**(CI 는 통과): 이 기계의 git 2.25 에서 `git init -b`(2.28+)가 실패하고 `check-ignore -q` 가 부정 패턴에도 0 을 돌려준다 —
hermes-loop · hermes-cleanup-step5 · memory-symlink-roundtrip · hermes-history-export 를 버전에 기대지 않게 고쳤다(roster 테스트가 이미 쓰던 `-v` 방식).

## 8. 회고

- 잘된 것: CI 실패 10건을 로컬에서 재실행해 "진짜 결함 / CI 환경 / 로컬 환경" 으로 먼저 갈랐다. run-all 과 같은 환경변수로 돌리자 CI 전용이라 여긴 두 건이 로컬에서 재현됐다 — 원인이 러너가 아니라 내 export 였다.
- 잘못된 것: 이 세션의 변경 여섯 개(옵트아웃 전역 export · raw cp · CLAUDE.md 줄 수 · 플러그인 사본 · CI 환경변수 · 역할 템플릿 복사)가 CI 를 더 빨갛게 만들었고, 60회 실패를 하루 종일 보지 않았다. "단독 실행 통과" 를 "전체 통과" 로 읽었다.
- 다음 룰 후보: (1) 푸시 뒤 CI 결과를 확인하고 나서 완료를 말한다. (2) 테스트를 단독으로만 돌려 보지 말고, 영향 범위가 설치기·run-all 이면 run-all 과 같은 환경변수로 돌린다. (3) `훅 | grep -q` 패턴은 pipefail 아래에서 금지 — 출력을 받아 검사한다. (4) 세션 시작 훅에 "마지막 CI 결과" 한 줄(backlog 후보).

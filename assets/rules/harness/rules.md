# Harness Engineering Rules

에이전트가 어기면 안 되는 불변 규칙. 코드·테스트·hook으로 기계 강제됨.

## R1. 실행 모드 격리

`once/` · `scheduled/` · `realtime/` 는 서로 import 금지.
공통 코드는 `shared/` 에만 위치.

**기계 강제**: `test_r1_boundary.py` AST 테스트 (pre-commit에서 실행)

## R2. legacy 디렉터리 읽기 전용

`docs_legacy/` 수정·import·재실행 금지. 어휘(enum 값)만 재사용 OK.

## R3. LLM 경로 강제

`anthropic` SDK 설치·import·호출 전부 금지.
모든 LLM 호출은 구독 CLI 어댑터 경유.

**기계 강제**: AST 스캔 + requirements 검사 + find_spec 3중 검증

## R4. 인코딩 주의 환경

한글이 포함된 환경에서 bash 실행 시 인코딩 깨짐 이력.
별도 인코딩 스킬이 있는 경우 반드시 사용.

## R5. 경계 위반 발견 시 수정 우선

위반 코드 발견 → 즉시 중단 → 사용자 보고 → 근본 수정.
우회(eslint-disable, --no-verify, # noqa) 금지.

## R6. UI 작업 전 스킬 호출 필수

`.svelte` · `.tsx` · `src/` UI 파일 수정 전
반드시 `Skill("impeccable")` 호출.

> NOTE: `impeccable`은 `frontend-design`을 포괄하는 상위 스킬이다.
> `impeccable`이 설치되지 않은 프로젝트에서는 `Skill("frontend-design")`으로 폴백.

## R7. 설계/계획 문서 작성 후 리뷰 제안

`docs/exec-plans/` · `docs/superpowers/` 경로 내에서
다음 패턴 파일을 `Write`/`Edit`로 저장 완료했을 때
사용자에게 리뷰 여부를 질의:

| 파일 패턴 | 담당 에이전트 |
|---|---|
| `*-design.md` · `*-spec.md` | `Agent(subagent_type="architect-lite")` |
| `*-plan.md` | `Agent(subagent_type="planner-lite")` |

- 질의 예시: "방금 작성한 `foo-plan.md`를 `planner-lite` 에이전트로 짧게 리뷰할까요?"
- 사용자가 거부하면 넘어감. 강제 차단 아님.
- 큰 설계 변경, 불명확한 요구사항, multi-day 구현이면 lite 리뷰 후 `architect`/`planner`로 승격.

---

## 작업 흐름 원칙

### 코드 작성 전

1. Grep/Glob으로 기존 함수·컴포넌트 먼저 확인 (중복 금지)
2. 새 파일 vs 기존 파일 확장 — 의식적으로 선택
3. 파일 400줄 초과 금지 — 초과 시 분리
4. 수정 전 import 그래프 1회 확인 — 파일명 추론 금지. dead file 편집 시 훅이 경고
   (`[dead-file WARN] ...` 발생하면 중단하고 실사용 파일 재확인).

### 커밋 전

1. pre-commit hook 통과 필수 (prettier + lint + pytest)
2. 큰 변경·공유 경계 변경·보안/DB/동시성 영향이 있으면 code-reviewer 검토
3. --no-verify 우회 절대 금지

### 세션 종료 시

- Stop hook 이 권한 프롬프트 피로도를 감지하면 (`[harness] 권한 프롬프트 피로도 감지 ...`)
  다음 세션에서 `/skill fewer-permission-prompts` 실행 검토. 자동 적용 금지 — 정책은 사람이 승인.

### 문서화

- 새 설계 결정 → `docs/design-docs/` 에 기록
- 새 실행 계획 → `docs/exec-plans/active/YYYY-MM-DD-slug.md`
- 완료 시 → `docs/exec-plans/completed/` 로 이동
- 감사/조사 → `docs/audits/YYYY-MM-DD-slug.md`

---
name: harness-promote-rule
description: 반복되는 결함·리뷰 지적·경계 위반을 docs/design-docs/core-beliefs.md 의 R 룰로 승격하고, 대응하는 강제 장치(테스트·린터 규칙)를 스캐폴드한다. Use when the same defect/review comment/boundary violation appears 2+ times, when the user says "이거 룰로 박아"/"rule로 올려", or when weekly-doc-gardening issues a rule-candidate. Invoke before continuing implementation if the pattern is load-bearing.
---

# Harness Promote Rule

> PDF 10쪽: *"인간의 취향은 시스템에 지속적으로 피드백됩니다. 리뷰 코멘트,
> 리팩터링 pull request, 사용자 측 버그는 문서화 업데이트로 기록되거나
> 툴링에 직접 인코딩됩니다. **문서화가 부족한 경우 규칙을 코드로 승격합니다.**"*

하네스 엔지니어링의 *진화 루프*. 1~4차원 방어가 기존 룰을 지키는 일이라면,
이 스킬은 **새 룰을 만드는 일**이다.

## 언제 invoke 하는가 (트리거)

1. **반복 신호** — 같은 유형의 결함·리뷰 지적·경계 위반이 2회 이상
2. **사용자 명령** — "이거 룰로 박아", "R 룰로 올려", "promote-to-rule"
3. **시스템 신호** — `weekly-doc-gardening` 워크플로가 `[rule-candidate]` 라벨의 Issue 를 생성
4. **대형 커밋 직전** — 도메인 불변 조건이 새로 발견됐는데 아직 강제 장치가 없을 때

## 언제 invoke 하지 *않는가*

- **일회성 버그** — 한 번 난 실수는 룰이 아니다. 고치고 넘어가라.
- **개인 취향** — "이렇게 하는 게 더 예뻐" 는 R 룰이 아니다. 팀 합의가 있어야 한다.
- **프레임워크 기본 규칙** — ESLint / ruff / prettier 가 이미 잡는 것은 거기서 끝낸다.
- **PDF 11쪽 경계 밖** — 다른 프로젝트에도 쓰일 것 같으면 ai-dev-setting 의
  `assets/rules/harness/examples/` 를 고려하지, 현재 프로젝트 `core-beliefs.md` 에 박지 않는다.

## 승격 절차 (6단계)

### 1. 패턴 요약

무엇이 반복됐는가? 3문장 이내로 요약:
- **증상**: 어떤 코드가 어떻게 잘못 작성됐는가
- **근본 원인**: 에이전트/사람이 이걸 왜 놓쳤는가 (*문서화 부족? 경계 불명확? 유혹?*)
- **영향**: 지금까지 발생한 피해 — 버그 티켓 번호, 프로덕션 사고, 시간 낭비

### 2. R 번호 할당

`docs/design-docs/core-beliefs.md` 의 마지막 R 번호 다음을 할당. 예: 기존 R1~R6 → 이번은 R7.

### 3. `core-beliefs.md` 에 R 룰 추가

아래 양식을 따른다 — rim-kanban 의 실제 형식:

```markdown
## R7: 시간 컬럼은 반드시 TIMESTAMPTZ

### 불변 조건
모든 PostgreSQL 시간 컬럼은 `TIMESTAMPTZ` 로 선언한다. `TIMESTAMP WITHOUT TIME ZONE` 금지.

### 근거
- 2026-03-XX 사건: 배포 시 서버 TZ 변경으로 주문 타임스탬프가 9시간 밀림
- 수정 PR: #142 (마이그레이션 0031_fix_tz.sql)

### 강제 장치
- `tests/test_r7_tz.py` — 모든 `Column(DateTime)` 이 `timezone=True` 인지 단언
- `scripts/lint/check_tz.py` — 마이그레이션 파일의 `TIMESTAMP WITHOUT` 패턴 차단

### 우회 조건 (있다면)
- 과거 데이터 import 전용 스테이징 테이블: `staging_*` 접두사. 이 경우 테스트 예외 처리.
```

### 4. 강제 장치 스캐폴드

*문서만 박으면 안 된다.* 반드시 대응하는 강제 장치를 만든다:

- **Python 프로젝트** → `tests/test_rN_<slug>.py` 를 생성. pytest 가 돌면서 실제로 위반을 잡도록.
- **TS/Svelte 프로젝트** → `eslint.config.js` 에 `no-restricted-imports` / `no-restricted-syntax` 블록 추가.
- **SQL/마이그레이션** → `scripts/lint/check_<topic>.sh` 에 grep 기반 검사 추가.
- **pre-commit 연동** → 위 장치가 `.git/hooks/pre-commit` 에서 자동으로 돌도록 `pre-commit` 혹은 custom hook 에 등록.

테스트/린터는 **실제 위반 케이스를 1개 이상** 포함해야 한다 (빨간불 → 초록불 증명).

### 5. `docs/audits/` 에 승격 기록

`docs/audits/YYYY-MM-DD-rN-promotion.md` 작성:

```markdown
# R7 승격 감사 — 2026-04-14

## 트리거
- 소스: [ ] 반복 결함  [ ] 리뷰 지적  [ ] 시스템 신호  [x] 사용자 명령
- 참조: 커밋 a1b2c3d, 이슈 #142, 리뷰 코멘트 #PR-138

## 변경
- `docs/design-docs/core-beliefs.md`: R7 섹션 추가
- `tests/test_r7_tz.py`: 새 파일 (12 LOC)
- `.git/hooks/pre-commit`: R7 검사 단계 등록

## 회고
이 룰을 *문서로만 남겼다면 6개월 뒤 동일 사건이 다시 났을 것이다*.
강제 장치 없는 R 룰은 무의미 — PDF 9쪽 "맞춤형 린터로 강제" 준수.
```

### 6. 사용자 승인 후 커밋

**절대 자동 커밋 금지.** 다음을 사용자에게 보여준다:
- 패턴 요약 (1단계)
- 추가될 R 룰 전문 (3단계)
- 생성될 테스트·린터 코드 (4단계)
- 감사 기록 초안 (5단계)

사용자가 "박아" 라고 하면 1개 커밋으로 묶는다. 메시지 예시:

```
feat(rules): R7 승격 — 시간 컬럼 TIMESTAMPTZ 강제

trigger: 반복 결함 (2회 — 커밋 a1b2c3d, 이슈 #142)
enforce: tests/test_r7_tz.py + pre-commit 검사
audit:   docs/audits/2026-04-14-r7-promotion.md
```

## 안티패턴

- ❌ **문서만 추가, 강제 장치 누락** — 6개월 안에 까먹고 다시 어긴다
- ❌ **자동 커밋** — 승격은 사람 판단이 핵심. 0.7-bis 메타 원칙
- ❌ **다른 프로젝트에도 통할 것 같다며 ai-dev-setting 에 직접 박음** — PDF 11쪽 일반화 금지. 예시로만 보존하거나, 별도 PR 로 논의
- ❌ **기존 R 룰을 *수정* 하면서 승격 절차 생략** — 수정도 audit 기록 대상. 룰은 *진화하는 코드* 다

## 관련 스킬·문서

- `harness-boundary-check` — 기존 R 룰(R1·R3) 의 *강제* 담당. 본 스킬은 *새 R 룰 생성* 담당
- `code-reviewer` — 강제 장치가 넓은 범위에 영향을 줄 때만 추가 검토
- `.00_docs/harness-integration-plan.md` § 진화 루프 — 본 스킬의 설계 근거

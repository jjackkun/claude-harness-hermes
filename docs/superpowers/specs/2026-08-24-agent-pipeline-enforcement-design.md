# R-pipe — 에이전트 파이프라인 강제

> 작성일: 2026-08-24
> 목적: 역할별 에이전트가 "권유"가 아니라 "통과 조건"으로 작동하게 한다.

## 개요

영상의 Agent Gauntlet 은 작업을 역할로 쪼개고 각 역할이 끝나면 소멸하는 파이프라인이다:
Specifier → Coder → Cleaner → Hardener → QA.

**이 저장소는 역할 구성이 이미 거의 일치한다.** `assets/agents/` 의 15개 중:

| 영상 역할 | 대응 자산 |
|---|---|
| Specifier | `planner`, `planner-lite`, `architect`, `architect-lite` |
| Coder | `fullstack-developer` |
| Cleaner | `refactor-cleaner` |
| Hardener | `tdd-guide`, `silent-failure-hunter` |
| QA | `code-reviewer`, `python-reviewer`, `typescript-reviewer` |

**빠진 것은 역할이 아니라 순서 강제다.**

## 문제 — 실측

### 1. 유일한 파이프라인 신호가 "첫 편집 1회 권유"다

`claude-posttooluse-review-reminder.sh` 헤더:

```text
- Write/Edit 발생 → .claude/.review-dirty 파일에 최근 코드 편집을 기록한다.
- 첫 코드 편집 때만 soft reminder 출력. 이후 편집은 조용히 누적한다.
- commit 단계 bash-guard 는 차단하지 않고 기록 요약만 컨텍스트에 주입한다.
```

세션당 한 번 권유하고, 커밋에서도 차단하지 않는다.
영상이 "모델은 이걸 가이드라인으로 취급한다"고 지적한 형태 그대로다.

### 2. 문서와 구현이 어긋나 있다

`assets/hooks/claude-settings-hooks.json` 의 설명:

```text
"_purpose": "Write/Edit 누적 15 회 도달 시 code-reviewer dispatch 리마인드"
```

**구현은 15회가 아니라 첫 편집 1회다.** 이 JSON 은 파일 상단에 `_comment` 로
"문서 전용"이라고 명시돼 있어 실제 등록은 `presets/workflow/harness.conf` 가 하지만,
문서가 구현과 다르면 하네스를 읽고 판단하는 에이전트가 잘못된 전제를 갖는다.
**이 불일치 자체가 별도 수정 대상이다.**

### 3. `agent-guard` 도 의도적으로 soft 다

```text
강제 모델: 다른 hook 과 동일하게 soft warning. 차단이 아니라 컨텍스트 주입으로
에이전트가 자기 검열하도록 유도.
```

즉 **파이프라인 축에서 차단하는 장치가 하나도 없다.**

### 4. 계획 템플릿에 골격은 이미 있다

`docs/exec-plans/template.md` 의 Step 항목:

```text
### Step 1. <제목> [Plan/Impl/Review 또는 단순]
```

Plan → Impl → Review 라는 3단 골격이 **템플릿에 이미 존재한다.**
새 개념을 도입하는 것이 아니라 이 골격에 강제력을 붙이는 작업이다.

## 설계

### 순서를 강제하지 않는다 — 출구를 막는다

영상처럼 에이전트 실행 순서 자체를 오케스트레이션하는 것은 이 하네스에서 불가능하다.
Claude Code 에서 하네스가 제어할 수 있는 것은 **훅 지점**뿐이고, 훅은 순서를 지시하지 못한다.

대신 **완료 선언 시점을 막는다.** 순서를 강제하는 대신, 필요한 단계를 안 거치면
"끝났다"고 말할 수 없게 만든다. 결과는 같다 — 통과하려면 거쳐야 한다.

### `R-pipe` — 커밋 시점 통과 조건

`pre-commit` 의 `bash-guard` 는 이미 커밋을 가로채고 있으나 차단하지 않는다.
여기에 조건을 건다.

| 조건 | 검사 | 행동 |
|---|---|---|
| Cleaner 통과 | `R-cx` 위반 0건 | 차단 (해당 스펙이 담당) |
| Hardener 통과 | 변경된 `.py` 에 대응 테스트 존재 | **경고** |
| QA 통과 | `.claude/.review-dirty` 가 리뷰 없이 커밋되지 않음 | **경고** |

**Cleaner 만 차단이고 나머지는 경고다.** Cleaner 조건(`R-cx`)은 기계 판정이라 이분법이 서지만,
"리뷰를 거쳤는가"는 기계가 확인할 수 없다 — 에이전트가 리뷰를 dispatch 했다는 사실과
리뷰가 유효했다는 사실은 다르다. 확인 못 하는 것을 차단 조건으로 삼으면
형식적 통과(리뷰 에이전트를 부르고 결과를 무시)를 학습시킨다.

### `.review-dirty` 를 실제로 쓴다

현재 이 파일은 기록만 되고 아무 판정에도 쓰이지 않는다.
커밋 시점에 "이번 커밋에 포함된 파일 중 리뷰 기록이 없는 것"을 계산해 경고로 낸다.

```text
[R-pipe] 이 커밋의 3개 파일이 리뷰 기록 없이 커밋된다.
  scripts/hermes_loop.py, scripts/hermes_redact.py, tests/foo-test.sh
  → code-reviewer 또는 도메인 리뷰어를 dispatch 하거나, 리뷰 불필요 사유를 커밋 메시지에 남길 것.
  근거: docs/design-docs/core-beliefs.md#r-review
```

`R-review`("리뷰 빚") 앵커가 `core-beliefs.md` 에 이미 있다 — 새 원칙이 아니다.

### 하지 않는 것

- **에이전트 자동 dispatch 를 훅이 수행하지 않는다.** 훅은 셸 스크립트이고
  에이전트를 부를 권한이 없다. 컨텍스트 주입으로 유도하는 것이 한계다.
- **역할별 에이전트를 새로 만들지 않는다.** 15개로 충분하다.

## 검증

| 항목 | 방법 |
|---|---|
| 문서 불일치 수정 | `claude-settings-hooks.json` 설명이 구현과 일치 |
| `.review-dirty` 판정 | 리뷰 기록 없는 파일 커밋 → 경고, 커밋 성공 |
| 오발화 없음 | 리뷰 기록이 있는 파일만 커밋 → 침묵 |
| 문서 전용 커밋 | `.md` 만 변경 → 침묵 |

`tests/pipe-gate-test.sh` 를 추가한다.

## 미해결

1. **"리뷰를 거쳤다"의 기록 방법.** 리뷰 에이전트가 돌았다는 사실을 훅이 알 방법이 없다.
   `PostToolUse(Task|Agent)` 훅으로 dispatch 를 기록하는 경로가 있으나,
   dispatch 사실이 리뷰 유효성을 뜻하지는 않는다. 무엇을 기록할지 결정이 필요하다.
2. **Specifier 단계의 강제.** `R-plan-missing` 이 이미 "코드 수정 시 계획 존재"를 검사한다.
   Specifier 축은 그것으로 충분한지, 별도 조건이 필요한지 판단이 필요하다.
   실행 가능한 인수 명세는 `2026-08-24-executable-acceptance-spec-design.md` 가 다룬다.
3. **경고 피로.** 이 스펙은 경고를 2개 추가한다. `size-warn` 이 이미
   "같은 편집에 두 경고를 겹치면 사람이 hook 을 꺼 버린다"고 기록하고 있다.
   커밋 시점 경고의 총량을 재점검해야 한다.

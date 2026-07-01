---
name: harness-reasoning-sandwich
description: 비자명한 작업에 계획 → 구현 → 검증 흐름을 적용하고, 큰 변경일 때만 깊은 리뷰로 승격한다. Use when starting a new feature, multi-file change, or any non-trivial implementation task.
---

# Harness Reasoning Sandwich

Ryan Lopopolo의 하네스 엔지니어링 원칙. TerminalBench 실험에서 52.8% → 66.5% 성능 향상 확인.

## 언제 적용하는가

| 상황 | 샌드위치 여부 |
|---|---|
| 새 기능 구현 | **필수** |
| 다파일 변경 (3개 이상) | **필수** |
| 아키텍처 결정 | **필수** |
| 단순 1파일 수정 | 생략 OK |
| 질의응답 | 생략 OK |
| 버그 수정 (원인 명확) | 생략 OK |

## 절차

### Step 1: Plan

```
Agent(
  subagent_type: "planner",
  model: "sonnet",
  prompt: "다음 작업의 구현 계획을 수립해줘: [작업 설명]
  
  포함할 것:
  - 변경할 파일 목록
  - 각 파일의 변경 내용 요약
  - 잠재적 위험 요소
  - 테스트 전략"
)
```

메인 세션은 계획만 받고 직접 구현하지 않는다.

### Step 2: Impl

메인 세션에서 계획대로 구현한다.
- 계획을 벗어나는 결정이 생기면 사용자에게 먼저 알린다
- 한 번에 너무 많이 만들지 않는다 — 논리적 단위로 나눈다

### Step 3: Verify

가능한 검증을 먼저 직접 수행한다.
- 테스트, 린트, 타입체크
- 변경 파일 주변 코드 확인
- 실패 경로와 롤백 경로 확인

### Step 4: Escalate Review When Needed

다음 중 하나가 있으면 `code-reviewer` 또는 도메인 reviewer 를 사용한다.
- 보안, 인증, 결제, 데이터 손실 위험
- DB schema/migration/transaction 변경
- 공유 경계, 공개 API, 아키텍처 결정 변경
- 동시성, 비동기, 프로세스 생명주기 변경
- 변경량이 크거나 테스트로 충분히 증명하기 어려움

## 금지 모델

- **Haiku 금지** — 단일 Haiku 실패 사례 확인됨. 비용 절감보다 품질 손실이 크다.

## 커밋 규칙

```bash
# pre-commit hook이 통과해야 커밋 가능
# --no-verify 우회 절대 금지
git commit -m "feat: [내용]"
```

hook이 막으면 우회하지 않고 근본 원인을 수정한다.

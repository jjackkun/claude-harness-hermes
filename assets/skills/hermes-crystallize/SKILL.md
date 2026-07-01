---
name: hermes-crystallize
description: Crystallize repeated conversation patterns into reusable skill files. Triggered automatically by the Hermes learning loop (Stop hook) when the same pattern is detected 3+ times (pattern_count count >= 3, crystallized = 0). Saves the new skill under [project]/.hermes/skills/, registers it in skill_index, and marks the pattern as crystallized.
---

# hermes-crystallize

반복된 패턴을 스킬 파일로 결정화(Crystallization)한다.

## 트리거

러닝 루프(Stop Hook)가 동일 패턴 3회 이상 감지 시 자동 호출.

## 개념

> 대화 속 흘러가는 지식(액체)을 재사용 가능한 스킬 파일(결정체)로 굳히는 과정.

## 동작 순서

1. `pattern_count` 테이블에서 count >= 3 이고 crystallized = 0 인 패턴 조회
2. 패턴 내용을 바탕으로 스킬 파일 초안 작성
3. `[project]/.hermes/skills/<slug>.md` 에 저장
4. `skill_index` 테이블에 등록
5. `pattern_count.crystallized = 1` 로 업데이트
6. 알림 박스 출력

## 알림 박스

```
╔══════════════════════════════════╗
║  🧠 헤르메스 결정화 완료          ║
║  <skill-name>.md  ← 신규생성     ║
╚══════════════════════════════════╝
```

## 스킬 파일 형식

결정화된 스킬은 아래 형식으로 저장된다:

```markdown
# <slug>
<!-- hermes:auto-generated version:1 created:YYYY-MM-DD -->

[패턴에서 추출된 규칙 내용]

## 근거
- 세션 ID: <source_session_id>
- 감지 횟수: 3회
```

## 로컬 vs 공통 진화

- **로컬 스킬** (`[project]/.hermes/skills/`): 자동 생성
- **공통 스킬** (`ai-dev-setting/assets/skills/`): 사용자 승인 후 PR 생성

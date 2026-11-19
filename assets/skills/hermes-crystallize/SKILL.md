---
name: hermes-crystallize
description: 3번 이상 반복된 대화 패턴을 재사용 스킬로 결정화한다(헤르메스 학습 루프). Crystallize repeated conversation patterns into reusable skill files. Triggered automatically by the Hermes learning loop (Stop hook) when the same pattern is detected 3+ times (pattern_count count >= 3, crystallized = 0). Saves the new skill under [project]/.hermes/skills/, registers it in skill_index, and marks the pattern as crystallized.
---

# hermes-crystallize

반복된 패턴을 스킬 파일로 결정화(Crystallization)한다.

## 트리거

러닝 루프(Stop Hook)가 동일 패턴 3회 이상 감지 시 자동 호출.

## 개념

> 대화 속 흘러가는 지식(액체)을 재사용 가능한 스킬 파일(결정체)로 굳히는 과정.

## 동작 순서

1. `pattern_count` 테이블에서 count >= 3 이고 crystallized = 0 인 패턴 조회
1-1. 철회 보류(L-06): 패턴 주제와 겹치는 기억(`memory_events`)이 **철회된 채**면 `HOLD:<키>` 를 출력하고 건너뛴다.
     장부에는 남기지 않아, 같은 주제가 다시 추가되면 다음 결정화에서 저절로 풀린다.
2. 패턴 내용을 바탕으로 스킬 파일 초안 작성. 같은 호출에서 모델은 끝줄에 **검사 판정** 한 줄을 낸다:
   `ENFORCE: covered:<R-이름>` · `ENFORCE: checkable:<hook|gate|test>` · `ENFORCE: prose`.
   글 규칙은 매 턴 주입돼도 지켜지는지 아무도 재지 않는다. 기계로 막을 수 있는 실수는 검사로 옮기는 편이 낫다.
   - 판정 줄은 본문에서 떼어 `.hermes/enforce-verdicts.jsonl`(장부)에 남긴다. 스킬 파일 안에 두지 않는다 — 진화가 파일을 통째로 다시 써서 지워진다.
   - 게이트 이름은 `core-beliefs.md` · `CLAUDE.md` 에 나온 `R-…` 만 인정한다. 목록 밖 이름·틀린 형식·판정 줄 없음은 `prose` 로 강등한다.
   - `covered` → 스킬 파일을 쓰지 않고 `crystallized = -1` 로 둔다(게이트가 이미 막는 것을 글로 다시 주입하지 않는다). `COVERED:<키>` 출력.
3. `[project]/.hermes/skills/<slug>.md` 에 저장
4. `skill_index` 테이블에 등록
5. `pattern_count.crystallized = 1` 로 업데이트
6. 알림 박스 출력

## 검사 후보 보기

`checkable` 판정은 훅·게이트·시험으로 옮길 후보다. 옮기는 일은 사람이 `harness-promote-rule` 스킬로 한다.

```bash
python3 scripts/hermes_enforce_ledger.py list --hermes-dir .hermes        # checkable 후보
python3 scripts/hermes_enforce_ledger.py list --hermes-dir .hermes --all  # 모든 판정
```

판정이 틀렸으면 장부 줄을 지우고 `UPDATE pattern_count SET crystallized=0 WHERE pattern_key='<키>'` — 다음 결정화에서 다시 판정한다.

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
- **공통 스킬** (`claude-harness-hermes/assets/skills/`): 사용자 승인 후 PR 생성

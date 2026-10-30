# 커밋·푸시한 턴 끝에 결정화 스킬이 생겨 매번 미커밋 파일로 남는다

> 작성일: 2026-10-30
> 목적: 커밋한 턴에는 저장소 추적 파일을 쓰지 않고 다음 턴으로 미뤄, "커밋 푸시" 뒤에 남는 파일을 없앤다.
> 출처: Nbbang-Run 세션(2026-10-30) — 사용자 질문 "푸시를 하면 꼭 남는 파일 하나가 생겨"

## 개요

사용자가 "커밋 푸시해" 라고 하면 에이전트는 한 턴 안에서 남은 변경을 전부 커밋·푸시한다.
그 턴이 끝나면 Stop 훅 `claude-stop-retrospective.sh` 가 돌고, 패턴이 3회에 닿으면
`hermes-crystallize.py` 가 `.hermes/skills/<키>.md` 를 새로 쓴다. 이 파일은 커밋보다 늦게 생기므로
**커밋 직후 항상 미커밋으로 남는다.** 사람은 "다 올렸는데 왜 또 남지" 를 겪고, 뒷수습 커밋을 따로 만든다.

## 실측 (Nbbang-Run, 2026-10-30)

- 커밋 `f340b1d` 08:54:36 → 푸시 → 턴 종료 → `.hermes/skills/verify-staged-files-ownership.md` 08:55:51 생성.
  `pattern_count` 의 `pre-commit-measure` 가 그 턴에 3회에 닿아 `crystallized=1`.
- 직전 커밋 때 남은 `stale-local-config-cleanup.md`(`local-command-caveat`, 2026-10-26)도 같은 경로였다.
- 뒷수습 커밋: 10일 동안 4번 — `b660202`(10-21) · `c12d462`(10-22) · `fdd861c`(10-26) · 이번 건.

## 원인 (코드)

- `assets/hooks/claude-stop-retrospective.sh:80~84` — Stop 훅이 `hermes-save-session.py` 출력의
  `[hermes] CRYSTALLIZE:` 줄을 받아 그 자리에서 결정화한다. Stop 은 세션 끝이 아니라 **턴 끝마다** 돈다.
- 훅은 그 턴에 커밋이 있었는지 보지 않는다.

## 개선안 (권고: A)

### A. 커밋 턴에는 파일 쓰기를 미루고, 다음 턴에 대기 패턴을 다시 줍는다

1. Stop 훅이 transcript 의 **마지막 사용자 메시지 뒤** Bash 호출에서 `git commit` 또는 `git push` 를 찾는다.
   찾으면 이번 턴은 "커밋 턴" 이다.
2. 커밋 턴에는 패턴 집계·요약·DB 기록은 그대로 하고, **저장소 추적 파일을 쓰는 단계만** 건너뛴다
   (결정화 · 스킬 진화 · 아래 "확인할 것" 의 지식 파일 내보내기).
3. 커밋 턴이 아니면, 이번 턴에 올라온 대상에 더해 `pattern_count` 에서 `count >= 3 AND crystallized = 0` 인
   대기 행을 함께 결정화한다.
   - **이 단계가 없으면 미룬 패턴을 잃는다.** `hermes_save_session_storage.py:103` 은 수가 올라가는 순간에만
     대상을 돌려준다. 같은 세션의 다음 턴은 `pattern_session` 중복으로 건너뛰고(87줄), 드리밍도
     `crystallized=0` 대기 행을 줍지 않는다(`hermes-dream.py` 에 그 조건 0곳).
   - 부작용 범위: 공장 DB 실측(2026-09-22, `backlog/crystallize-stability-score.md`)에서 "3회에 닿고도 대기 중인 행" 은 0 이었다.
     지금 대기 행은 이 개선이 만든 것뿐이다.
4. 세션이 커밋 턴으로 끝나면 다음 세션의 첫 Stop 에서 파일이 생긴다. 그 세션의 작업 커밋에 함께 실린다.

### 고르지 않은 것

- B. pre-commit 게이트에서 결정화 — 결정화는 모델을 부른다. 커밋마다 시간·사용량이 붙는다.
- C. 턴 끝에 자동으로 뒷수습 커밋 — 사용자 규칙 "자동 커밋 금지" 위반.
- D. `.hermes/skills/` 를 `.gitignore` — 결정화 스킬을 git 으로 운반하는 원칙(A-11, 지식이 컴퓨터를 따라간다) 위반.

## 확인할 것 (아직 안 봄)

- `hermes-evolve-skill.py`(기존 스킬 고침) · `hermes-knowledge-files.py export`(`agents/<id>/memory.jsonl` ·
  `.hermes/journal.jsonl`)도 커밋 뒤 미커밋 변경을 만드는지. 만들면 2번의 "건너뛰는 단계" 에 넣는다.
- `git commit` 판정이 커밋 메시지 본문의 낱말에 속지 않는지 — `claude-pretooluse-bash-guard.sh:134~140` 의 판정 방식을 재사용한다.

## 검증 방법

- 가짜 transcript 두 개로 훅을 돌린다(모델 호출은 결정화 스크립트를 가짜로 바꿔 0회).
  - 마지막 턴에 `git commit` Bash 호출 + 3회째 패턴 → 스킬 파일 0개, `pattern_count` 는 `count=3, crystallized=0`.
  - 이어서 커밋 없는 턴 → 스킬 파일 1개, `crystallized=1`.
  - 커밋 없는 턴만 → 지금과 같이 그 턴에 1개(바뀌면 안 되는 것).
- 소우주 하나(Nbbang-Run)에서 "커밋 푸시" 를 실제로 해 보고 `git status` 가 비어 있는지 본다.

## 같이 발견한 것

- 이번에 생긴 `verify-staged-files-ownership.md` 의 규칙("다른 세션 산출물은 커밋 전에 사용자에게 묻는다")이
  Nbbang-Run 사용자 기억 "커밋 푸시 = 남은 변경 전부" 와 어긋난다. 결정화가 사용자 승인 규칙과 반대되는 스킬을
  만들 수 있다 — 별도 후보로 볼지 정한다.

## 전파

공장에서 `assets/hooks/claude-stop-retrospective.sh` · `scripts/hermes_save_session_storage.py`(대기 행 조회) 를 고치고
시험을 더한 뒤 update-all 로 소우주에 전파한다.

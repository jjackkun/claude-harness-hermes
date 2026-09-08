# 헤르메스 스킬 미활용 근본원인 감사

> 작성일: 2026-07-08
> 목적: "결정화된 스킬이 만들어지기만 하고 거의 사용되지 않는다"는 현상의 근본원인을 실측으로 규명하고 개선 위치를 특정한다.
> 조사 대상 프로젝트: `zeroday-frontend` (`.hermes/state.db`)
> 소스(고칠 위치): `claude-harness-hermes/scripts/`

## 1. 발단

`zeroday-frontend`에서 "출발접수조회 체크리스트를 브라우저로 테스트"하려다 로그인이 필요해졌다.
로그인/토큰 발급 방법은 이미 `.hermes/skills/api-token.md`로 **결정화되어 있었음에도** 에이전트가 이를
자동으로 꺼내 쓰지 못했고, 사용자가 "매번 토큰 스킬이 있다고 알려줘야 하느냐"고 지적했다.

→ 단일 스킬 문제가 아니라 **헤르메스 학습 루프의 구조적 미활용**을 의심하고 조사에 착수했다.

## 2. 실측 데이터 (`.hermes/state.db`, 2026-07-08 기준)

`skill_index` 테이블 기준:

| 지표 | 값 | 해석 |
|---|---|---|
| 등록 스킬 총계 | 292 | 이 중 `.hermes/skills/` 258개(자동생성), `.claude/skills/` 34개(설치형) |
| `api-token.md` used_count | 0 | 2026-06-26 등록 후 한 번도 사용 기록 없음 |
| `api-token.md` helpful_count | 0 | 도움됨 상관 없음 |
| used_count 합계(292개) | 37 | 한 번이라도 used>0 인 스킬 22개뿐 |
| **helpful_count 합계(292개)** | **0** | **단 하나도 helpful 상관이 잡힌 적 없음** |
| `skill_injection` 원장 총 행수 | 3 | 세션 시작/프롬프트 주입이 역대 3건밖에 기록 안 됨 |

**핵심 관찰**: 생성(292개)은 과잉인데, 전달 원장(3건)과 효용 신호(helpful 0)가 사실상 죽어 있다.

## 3. 파이프라인 구조 (소스: `claude-harness-hermes/scripts/`)

| 단계 | 스크립트 | 역할 | 트리거 |
|---|---|---|---|
| 결정화 | `hermes-crystallize.py` | 패턴 3회+ 반복 시 `.hermes/skills/<key>.md` 생성 | Stop 훅 |
| 주입 | `hermes-search.py` | FTS5로 프롬프트 키워드 매칭 → 관련 스킬을 프롬프트에 주입 + `skill_injection` 원장 기록 | UserPromptSubmit 훅 (`claude-userpromptsubmit-reminders.sh`) |
| 효용 상관 | `hermes-correlate.py` | 주입된 스킬 중, transcript의 Edit/Write 대상 파일 경로 토큰과 스킬 키워드가 겹치면 `helpful_count++`, 아니면 `noop_count++` | Stop 훅 |
| 드리밍 | `hermes-dream.py` | 누적 요약 통합·결정화 후보 승격·junk 정리 제안. 효용 통계를 근거로 판단 | 하루 1회 / 수동 |

중요: **`.hermes/skills/` → `.claude/skills/` "승격" 단계는 설계상 존재하지 않는다.**
`.hermes/skills/`의 전달 경로는 오직 **주입(injection)**이다. (당초 "승격 기능 누락" 가설은 오진이었음 — §5 참조)

## 4. 재현 검증 (라이브 실행)

`hermes-search.py`를 로그인/토큰이 포함된 질의로 직접 실행:

```bash
python3 hermes-search.py --db .hermes/state.db \
  --query "출발접수조회 테스트하려는데 로그인 토큰 발급 필요" \
  --session-id test-probe-001 --skills-dir .claude/skills --max 3
```

결과:
- `api-token.md`, `token-ttl-auth-layer-issue.md` 를 **정확히 검색해 반환**했다.
- `skill_injection` 원장이 3 → 6으로 **정상 기록**되었다. (테스트 후 3건 원복 완료)

→ **주입 메커니즘 자체는 정상 작동한다.** 문제는 "무엇을 트리거로 삼는가"에 있다.

## 5. 근본원인 (3연쇄)

### C1. 주입 트리거가 "사용자 프롬프트 텍스트"에만 반응한다

`claude-userpromptsubmit-reminders.sh`는 `data.get('prompt','')` (사용자 원문)만 `--query`로 넘긴다.
그런데 `api-token` 같은 스킬의 필요성은 **사용자 문장이 아니라 에이전트의 작업 중 판단**에서 발생한다.
- 예: 사용자는 "출발접수조회 체크리스트 확인"이라고만 했다(로그인 키워드 0).
- 로그인 필요는 에이전트가 "브라우저로 테스트하자"고 결정하면서 중간에 생겼다.
- 이 판단은 사용자 프롬프트에 없으므로 FTS5가 매칭할 수 없다.

→ **에이전트가 작업 도중 필요로 하는 스킬은 구조적으로 주입에서 누락된다.**
이것이 injection 원장이 3건뿐인 근본 이유다(실제 사용 프롬프트가 결정화 스킬 키워드와 거의 안 겹침).

### C2. 효용 판정이 "파일 편집 경로 겹침"에만 걸린다

`hermes-correlate.py`는 helpful 판정을 **transcript의 Edit/Write/MultiEdit 대상 파일 경로 토큰**과
스킬 키워드의 겹침으로만 한다.
- `api-token`, `swagger-curl-lookup`, 각종 조회/조사/테스트 스킬은 **파일을 편집하지 않는다.**
- 따라서 설령 주입되어 실제로 도움이 됐어도 **helpful로 카운트될 방법이 없다.**

→ 읽기·조회·테스트·검증형 스킬은 **효용 판정의 영구 사각지대**다.
helpful_count가 292개 전부 0인 것은 "상관 로직 버그"가 아니라 **판정 기준이 편집 작업에만 국한**된 결과다.

### C3. 효용 신호가 0이라 드리밍이 정리·우선순위화를 못 한다

`hermes-dream.py`는 효용 통계(helpful/noop)를 근거로 승격·강등·junk 정리를 제안한다.
그런데 helpful이 항상 0이므로 **판단 근거 자체가 없다.**

→ 258개 자동생성 파편(`라우터.md`, `비밀번호.md`, `basebutton.md`, `테이블.md` 등 단어·컴포넌트명 조각)이
정리도 우선순위화도 안 된 채 무한 축적된다. 신호 결핍 → 정체 → 노이즈 누적의 악순환.

## 6. 결론

> 결정화와 주입 메커니즘 자체는 정상 동작한다. 그러나
> **(C1) 주입이 사용자 프롬프트 키워드에만 반응**해 에이전트가 작업 중 필요로 하는 스킬을 놓치고,
> **(C2) 효용 판정이 파일 편집에만 걸려** 읽기·조회·테스트형 스킬을 영영 인정하지 못한다.
> 이 둘 때문에 **(C3)** 드리밍이 근거를 잃고, "만들기만 하고 안 쓰는" 상태가 구조적으로 고착됐다.

당초 사용자·에이전트가 세운 "`.hermes → .claude` 승격 기능이 빠졌다"는 가설은 **오진**이다.
승격 단계는 설계상 없는 것이 정상이며(전달은 주입), 진짜 병목은 **주입 트리거 범위**와 **효용 판정 기준** 두 곳이다.

## 7. 고칠 위치 (소스: `claude-harness-hermes/scripts/`)

| # | 파일 | 개선 방향 (설계 결정 필요) |
|---|---|---|
| C1 | `hermes-search.py` + `claude-userpromptsubmit-reminders.sh` | 주입 트리거를 사용자 프롬프트 이상으로 확장. 후보: (a) 직전 대화/에이전트 의도 텍스트도 질의에 포함, (b) 세션 중 특정 신호(예: 401·로그인·테스트 착수) 감지 시 온디맨드 재검색, (c) 자주 필요한 핵심 스킬을 `.claude/skills/`로 승격해 Skill() 호출 가능하게 만들기 |
| C2 | `hermes-correlate.py` | 효용 판정에 "읽기·조회·테스트·검증형 스킬" 인정 경로 추가. 후보: 편집 경로 겹침 외에 (a) Read/Bash/조회 도구 대상과의 겹침, (b) 주입 후 동일 세션에서 스킬이 지목한 명령·경로가 실제 실행됐는지, (c) 세션 성공 종료 시 주입 스킬에 약한 크레딧 부여 |
| C3 | `hermes-dream.py` + `hermes-prune.py`/`hermes-cleanup.py` | 효용 신호 복구 후, 258개 파편 정리 전략 수립. 단어·컴포넌트명 조각류 junk 식별 기준 + 정리 배치. (파괴적 작업이므로 제안→사람 승인) |

## 8. 다음 작업

- [x] C2 효용 판정 신호 복구 — 도구 활동 전반 겹침 + 키워드 ≥2 (2026-07-08 머지)
- [x] C1 주입 트리거 확장 — Bash 터미널 실패 신호 기반 도중 주입 (2026-07-09)
- [ ] C3 파편 정리는 별도 배치로, dry-run 후 사람 승인
- [ ] 검증: 실제 세션 누적 후 `skill_injection.source='assist'` 행 증가 + 읽기형 스킬 `helpful_count` 상승 확인

> 참고: 본 조사 중 `skill_injection`에 테스트 목적 3행(`session_id=test-probe-001`)을 삽입했다가 삭제해 원상 복구했다. 그 외 DB·코드 변경 없음(조사 전용).

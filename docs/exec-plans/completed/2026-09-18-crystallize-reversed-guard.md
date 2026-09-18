# 2026-09-18-crystallize-reversed-guard — 결정화가 철회된 결정을 규칙으로 굳히지 않게

> 출처: `docs/exec-plans/backlog/crystallize-reversed-decision-guard.md` (본 계획으로 승격, backlog 파일 삭제)
> 설계 결정 인용: L-06 (스킬 생애주기 — 철회된 결정의 결정화 금지), G-25 는 질문 ID(결정 아님)

## 1. 동기 (Why)

결정화(`hermes-crystallize.py`)는 반복 패턴을 스킬로 굳힌다. 그 패턴이 **나중에 철회된 결정**이면 폐기된 방침이
규칙이 돼 계속 주입된다. 회상이 뒤집힌 결정을 주입하는 문제(G-11)와 같은 뿌리다.
현 상태(2026-09-18 코드 확인): `crystallize()` 는 `pattern_count.crystallized` 와 junk 판정만 보고, `memory_events` 의
철회(`memory.retracted`) 신호를 전혀 읽지 않는다. 철회 신호와 `previously_retracted` 계산은 기억 이벤트 쪽에 이미 있다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 패턴 키의 검색어와 겹치는 기억이 **철회된 채**면 결정화하지 않는다(HOLD, 스킬 파일 0, `crystallized` 0 유지)
  — 검증: `tests/hermes-crystallize-reversed-test.sh` (a)
- [x] 목표 2 — 철회 뒤 같은 주제가 다시 추가되면(가장 최근 일치 이벤트가 철회가 아님) 보류를 풀고 결정화한다 — (b)
- [x] 목표 3 — 겹치지 않는 철회는 영향 없음, `memory_events` 표가 없어도 기존 동작 그대로 — (c)(d)
- [x] 목표 4 — 판정은 어휘·이벤트로만, 모델 호출 없음(R3) — 검증: 모듈이 표준 라이브러리만 import (`.deprc` tier 0 게이트)
- [x] 목표 5 — 설치 폐로: 새 모듈이 `hermes.conf` 복사 목록에 있다 — 검증: `tests/install-closure-test.sh`

## 3. 비목표 (Out of Scope)

- 작업 이력(`journal_events.decision`)의 번복 판정 — 이력에는 명시적 번복 표식이 없어 어휘 추정이 된다. 표식이 생기면 후속.
- 이미 결정화된 스킬의 **강등**(철회가 결정화 뒤에 온 경우) — G-8 도움 판정과 함께 볼 후속. 여기서는 새 결정화만 막는다.
- 보류를 `pattern_count` 에 영구 표시하는 것 — 보류는 상태가 아니라 매번 다시 재는 판정이다(철회가 풀리면 자동 해제).

## 4. 영향 영역

- 코드: `scripts/hermes-crystallize.py` `crystallize()` — 상태 확인 뒤·본문 생성 전에 보류 판정 1회
- **신규 파일 목록**:
  - `scripts/hermes_reversed_guard.py` — 검색어와 겹치는 기억 이벤트 중 가장 최근 것이 철회인지 판정(표준 모듈만, tier 0)
  - `tests/hermes-crystallize-reversed-test.sh` — 철회·재추가·무관·표 없음 네 경우의 결정화 결과 실측
- 룰: R3(모델 호출 금지) 준수. `.deprc` tier 0 등록
- 설치: `presets/workflow/hermes.conf` 복사 목록
- 데이터: 없음(읽기만)

## 5. 단계 (Steps)

### Step 1. RED — 테스트 [단순]
### Step 2. GREEN — 판정 모듈 + crystallize 연결 [단순]
### Step 3. 등록(run-all·hermes.conf·.deprc)·전체 스위트·backlog 정리 [단순]

## 6. 의사결정 로그

- 2026-09-18: 신호를 `memory.retracted` 로 한정 — 근거: 명시적이고 어휘 추정이 없다(R3). `revised` 는 내용 갱신이지 번복이
  아니며, 부정형 어휘 판정은 tier 0 제약으로 `hermes_memory_conflicts` 를 import 할 수 없어 중복 구현이 된다.
- 2026-09-18: "가장 최근 일치 이벤트가 철회" 로 판정 — 근거: 철회 뒤 재추가(`previously_retracted`)는 사람이 다시 확정한 것.
- 2026-09-18: 보류를 장부에 기록하지 않고 매번 판정 — 근거: 상태로 두면 철회가 풀려도 수동 해제가 필요하다.

## 7. 발견·예외

- 첫 픽스처(손으로 만든 `skill_index`·`memory_events`)가 실제 스키마와 어긋나 RED 가 두 종류로 섞였다(`created_at` 없음,
  `memory_id`/`ts` 필수). `hermes-init.py --project` 로 DB 를 만들고 `record()` 를 그대로 써서 해결 — 픽스처는 실제
  초기화 도구로 만드는 것이 규칙이어야 한다.
- 보류 출력에 철회 이벤트 id 와 원 기억 id 를 둘 다 넣었다 — 사람이 어느 기억이 철회됐는지 바로 찾을 수 있어야 한다.
- 겹침은 부분 문자열(소문자) 비교다. 두 글자 토큰(예 "고정")은 넓게 걸릴 수 있다 — 넓게 걸리면 "보류" 가 늘 뿐
  잘못 결정화되지는 않으므로 안전한 쪽으로 기울였다. 오보류가 실측되면 토큰 길이 하한을 올린다.

## 8. 회고 (완료 시 작성)

- 잘된 것: 신호를 명시적 철회 하나로 한정해 어휘 추정(R3 위반 위험) 없이 끝냈다. 보류를 상태로 두지 않아 해제 경로가 필요 없다.
- 잘못된 것: 픽스처를 손으로 만들어 RED 를 한 번 오염시켰다.
- 다음 룰 후보: "테스트 DB 픽스처는 실제 초기화 도구로 만든다" — 손 스키마 픽스처 3회 반복 시 승격.
  후속 backlog 후보: 결정화 **뒤**에 철회가 오면 강등(G-8 도움 판정과 함께).

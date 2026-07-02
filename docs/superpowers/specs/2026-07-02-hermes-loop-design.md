# 헤르메스 목표 기반 자율 루프 설계 (2026-07-02)

> 작성일: 2026-07-02
> 목적: 사용자가 **목표(Goal)만** 주면 에이전트가 단계분해 → 실행 → 객관검증 → 자가교정 →
> 반복을 **완료(또는 안전캡)까지 스스로** 수행하는 목표 기반 자율 루프를 헤르메스에 추가한다.
> 헤드리스(무인)와 대화형(세션 내) 두 진입점이 **공용 코어**를 공유한다.

## 1. 동기 (Why)

헤르메스에는 이미 cron 기반 자율 매니저(`hermes-manager.py`의 start/check/end + `messages` 메시지
버스)가 있으나, 이것은 "정해진 시각에 서브에이전트를 **한 번** 배분"하는 구조다. 인포그래픽이 말하는
**"목표 → 실행 → 검증 → 오류감지 → 우회(detour) → 반복"의 진짜 피드백 루프**는 아직 없다.

루프 엔지니어링의 핵심은 사람이 매 스텝을 지시하는 대신, **목표를 정의하면 에이전트가 스스로
프롬프트를 생성하고 완료까지 반복**하는 것이다. 이때 안정성은 두 축으로 확보한다: (1) 완료판정·
안전캡은 결정적 코드(드라이버)가 쥐고, (2) 창의적 판단·검증명령 제안은 에이전트가 맡는 **책임 분리**
— "탐지는 정규식이, 채점은 별도 모델이"라는 기존 B신호 설계 원칙과 동일하다.

기존 인프라를 최대한 재사용한다: `nohup claude -p` 헤드리스 패턴, `STATUS:done/blocked` 보고
프로토콜, 객관신호(B신호) 탐지, SQLite `messages` 버스, `hermes_redact` 마스킹, HOME 격리 테스트.

## 2. 목표 (What — 검증 가능)

- [ ] **G1 목표 정의 → 상태 생성** — `hermes-loop.py init` 이 GOAL.md 를 생성하고 `loops` 행을
  INSERT(status=running)한다. 검증: init 후 `.hermes/loops/<id>/GOAL.md` 존재 + `loops` 에 해당 행 존재.
- [ ] **G2 반복 실행(헤드리스)** — `hermes-loop.py run <id>` 가 while-루프로 매 반복
  `claude -p`(동기)를 호출하고, REPORT 블록을 파싱해 continue/stop 을 결정한다. 검증: 모킹 claude 가
  `VERDICT:continue` 2회 후 `VERDICT:goal-met` 반환 → 3회 반복 후 status=done.
- [ ] **G3 객관신호 교차검증** — 에이전트가 `VERDICT:goal-met` 을 내도 `VERIFY:` 명령이 있으면
  드라이버가 그 명령을 실행하고, **fail 이면 goal-met 을 기각해 continue 로 강등**한다. 검증: 모킹
  claude 가 goal-met + `VERIFY:false` 반환 → 종료 안 됨(continue), goal-met 은 다음 pass 에서만 인정.
- [ ] **G4 완료 종료** — `VERDICT:goal-met` 이고 (VERIFY 없거나 pass)면 stop(finish_reason=goal-met,
  status=done). 검증: 모킹 claude 가 goal-met + `VERIFY:true` → status=done, finish_reason=goal-met.
- [ ] **G5 안전캡 — 최대반복** — `iterations_used ≥ max_iterations` 면 stop(max-iter). 검증:
  max_iterations=2 로 init, 모킹 claude 가 항상 continue → 2회 후 강제중단, finish_reason=max-iter.
- [ ] **G6 안전캡 — 무진전** — `no_progress_count ≥ no_progress_limit`(기본 3) 면 stop(no-progress).
  검증: 진전신호 없는 continue 3회 연속 → 중단, finish_reason=no-progress.
- [ ] **G7 블로커 → 사람 개입** — `VERDICT:blocked` 면 stop(finish_reason=blocked, status=stopped).
  검증: 모킹 claude 가 blocked 반환 → 즉시 중단, status=stopped.
- [ ] **G8 재개(resume)** — 프로세스가 죽어 status=running 인 루프를 `hermes-loop.py resume <id>` 가
  GOAL.md+DB 로 이어간다. 검증: run 을 1회 반복 후 강제 종료(kill) → resume → 이전 iterations_used 에서 이어짐.
- [ ] **G9 파괴적 작업 차단(헤드리스)** — 반복 프롬프트에 파괴적 작업 금지가 명문화되고, 헤드리스는
  기존 harness `bash-guard` 훅으로 파일삭제·force push 가 차단된다. 검증: 프롬프트 본문에 금지 문구
  존재 + `run` 이 `--dangerously-skip-permissions` 를 쓰지 않음.
- [ ] **G10 대화형 진입점** — `/hermes-loop <목표>` 스킬이 공용 코어로 GOAL.md+loops 를 만들고,
  현재 세션에서 반복을 구동하되 파괴적 작업은 표준 권한 프롬프트(승인 게이트)를 거친다. 검증:
  `assets/skills/hermes-loop/SKILL.md` 존재 + 프리셋 SKILLS 에 등록.
- [ ] **G11 완료 아카이브** — 종료 시 `messages` 테이블에 완료 아카이브 1건(from=loop, to=archive)을
  남긴다. 검증: 종료 후 `messages` 에 해당 아카이브 행 존재.
- [ ] **G12 마스킹** — GOAL.md/DB 저장 경계에서 `hermes_redact` 로 비밀이 마스킹된다. 검증: 토큰 형태
  문자열을 진행로그에 넣으면 `[REDACTED:*]` 로 치환되어 저장.
- [ ] **G13 설치·마이그레이션** — `hermes` 프리셋 설치 시 신규 스크립트 4개 + 스킬이 배포되고,
  `hermes-init.py` 가 `loops`/`loop_steps` 테이블을 `CREATE TABLE IF NOT EXISTS` 로 만든다. 검증:
  기존 DB 에 대해 init 재실행 시 오류 없이 테이블 추가.

## 3. 비목표 (Out of Scope)

- **결정적 루프(Ralph 스타일)·하이브리드 전환** — 이번엔 비결정적(목표 기반)만. 결정적/전환 전략은 후속(§11).
- **자율 매니저(cron start/check/end)** — 별개 기능. 본 루프는 이를 대체하지 않고 인프라만 공유(messages·redact).
- **멀티 루프 병렬 오케스트레이션** — v1 은 한 번에 루프 1개 실행. 큐/스케줄러는 후속.
- **드리밍·결정화 연동** — 루프 결과를 러닝 루프(스킬 결정화)에 먹이는 것은 후속(§11). v1 은 아카이브 기록까지만.
- **웹/대시보드 UI** — CLI + GOAL.md(사람이 읽는 파일)로 충분. 시각화는 후속.

## 4. 아키텍처

### 4.1 파일 구조 (1파일 = 1책임)

```
scripts/
├── hermes_loop.py          # 공용 코어 모듈(importable): DB 스키마·loops 상태모델·GOAL.md I/O
├── hermes_loop_prompt.py   # 반복 프롬프트 템플릿·조립 (hermes-manager.py 템플릿 방식 계승)
├── hermes-loop.py          # CLI(dash): init / run / status / resume, while-루프 소유
└── hermes-loop-run.sh      # 헤드리스 nohup 래퍼 (hermes-cron-run.sh 형제)

assets/skills/hermes-loop/SKILL.md   # 대화형 진입점 /hermes-loop <목표> (승인 게이트)
docs/hermes-loop-guide.md            # 사용 가이드 (hermes-cron-guide.md 형제)
tests/hermes-loop-test.sh            # HOME 격리 + claude 모킹 테스트
```

언더스코어(`hermes_loop.py`, `hermes_loop_prompt.py`)=importable 모듈, 대시(`hermes-loop.py`)=CLI
진입점 — 기존 `hermes_skills.py`/`hermes_redact.py` vs `hermes-*.py` 관례와 동일. 헤드리스(CLI)와
대화형(스킬)이 **공용 코어 두 모듈을 함께 사용**한다.

### 4.2 공용 코어 책임 분리

- `hermes_loop.py` — `loops`/`loop_steps` 스키마·마이그레이션, GOAL.md 읽기/쓰기(체크박스·진행로그
  파싱 포함), 루프 상태 전이(running→done/stopped/failed), 안전캡 판정 함수, `hermes_redact` 호출.
- `hermes_loop_prompt.py` — 반복 프롬프트 조립(목표+완료조건+최근 진행로그+직전 신호+REPORT 계약),
  파괴적 작업 금지 문구. `hermes-manager.py` 의 템플릿 상수 방식을 그대로 계승.

## 5. 상태 모델 (하이브리드)

### 5.1 GOAL.md — 진실의 원본

경로: `.hermes/loops/<loop-id>/GOAL.md` (사람이 읽고 편집·git 추적 가능)

```markdown
# Loop: <제목>
> loop-id: <id> · created: <YYYY-MM-DD> · mode: goal · status: running

## 목표
<자유 서술>

## 완료 조건 (Definition of Done)
- [ ] 조건 1
- [ ] 조건 2

## 객관 검증 (선택)
- verify: `<테스트/빌드 명령>`   # 통과해야 '완료' 인정

## 진행 로그  (에이전트가 매 반복 append)
- [iter 1] <했던 일> · signal:pass · verdict:continue
```

진행상태의 진실원본은 GOAL.md 다. 사람이 언제든 열어 완료조건을 고치거나 진행을 확인·중단할 수 있다.

### 5.2 SQLite (state.db) — 메타·이력·측정신호

```sql
CREATE TABLE IF NOT EXISTS loops (
  id                TEXT PRIMARY KEY,
  title             TEXT NOT NULL,
  goal_md_path      TEXT NOT NULL,
  mode              TEXT NOT NULL DEFAULT 'goal',
  status            TEXT NOT NULL DEFAULT 'running',   -- running|done|stopped|failed
  max_iterations    INTEGER NOT NULL,
  no_progress_limit INTEGER NOT NULL DEFAULT 3,
  iterations_used   INTEGER NOT NULL DEFAULT 0,
  no_progress_count INTEGER NOT NULL DEFAULT 0,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  finished_at       TEXT,
  finish_reason     TEXT                               -- goal-met|max-iter|no-progress|blocked|user-stop|error
);

CREATE TABLE IF NOT EXISTS loop_steps (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  loop_id          TEXT NOT NULL,
  iteration        INTEGER NOT NULL,
  action_summary   TEXT,
  verdict          TEXT,        -- continue|goal-met|blocked
  objective_signal TEXT,        -- pass|fail|none
  progressed       INTEGER NOT NULL DEFAULT 0,
  created_at       TEXT NOT NULL
);
```

완료 시 기존 `messages` 테이블에 아카이브 1건(from='loop', to='archive')을 기록 — cron 매니저의
end 아카이브와 동일 패턴.

## 6. 반복 알고리즘 (드라이버 while-루프)

```
init: GOAL.md 생성 + loops row INSERT(status=running)

while status == running:
  1. 안전캡 선행 체크 (목표 미달로 멈추는 것이므로 status=stopped)
       iterations_used ≥ max_iterations      → stop(finish_reason=max-iter, status=stopped)
       no_progress_count ≥ no_progress_limit → stop(finish_reason=no-progress, status=stopped)
  2. 프롬프트 조립(hermes_loop_prompt): 목표 + 완료조건 + 최근 진행로그(마지막 N) + 직전 객관신호
       + 파괴적 작업 금지 명문화 + REPORT 계약 지시
  3. 동기 실행: claude -p "<prompt>"   (드라이버가 순차 대기 — 격리된 cold start)
  4. REPORT 블록 파싱 (STATUS:done/blocked 프로토콜 계승):
       ACTION:  한 줄 요약
       VERDICT: continue | goal-met | blocked
       VERIFY:  <실행할 검증 명령 | none>
       NEXT:    다음 단계 제안
  5. 객관신호 게이트: VERIFY 명령을 '드라이버가' 실행 → pass/fail
       VERDICT=goal-met 인데 VERIFY=fail → goal-met 기각, continue 로 강등(교차검증)
  6. 진전 판정: GOAL.md 체크박스 변화 / 새 커밋 / 신호 개선 → progressed
       progressed=true → no_progress_count=0  else → no_progress_count++
  7. loop_steps INSERT, iterations_used++, updated_at 갱신
  8. 종료 판정:
       VERDICT=goal-met & (VERIFY 없거나 pass) → stop(goal-met, done)
       VERDICT=blocked                         → stop(blocked, stopped)   # 사람 개입 필요
```

REPORT 계약 예시(에이전트가 응답 말미에 출력, 드라이버가 정규식 파싱):

```
=== HERMES-LOOP REPORT ===
ACTION: 로그인 라우터에 입력검증 추가
VERDICT: continue
VERIFY: pytest tests/test_auth.py -q
NEXT: 토큰 만료 경계 테스트 보강
=== END REPORT ===
```

### 6.1 기본값 (근거 명시 — 매직넘버 금지)

- `max_iterations` — init 시 `--max-iter` 로 지정. 미지정 시 `max(완료조건 수 × 3, 5)`.
  근거: 완료조건 1개당 평균 재시도 여유 3회(HTTP 재시도 업계 관례 3회와 동일 근거), 조건이 0~1개인
  단순 목표에도 최소 5회는 시도.
- `no_progress_limit` = **3**. 근거: 헤르메스 결정화 임계(동일 패턴 3회 반복)와 동일한 상수 근거.
  3회 연속 진전이 없으면 스스로 못 푸는 것으로 간주하고 사람에게 넘긴다.
- 최근 진행로그 주입 개수 N = **5**. 근거: 롤링 요약이 이미 5슬롯이며, 최근 5회면 직전 시도 맥락을
  충분히 담으면서 프롬프트를 짧게 유지.

## 7. 안전 · 종료

- **파괴적 작업 차단(G9)**: 헤드리스 → 프롬프트 명문화 + 기존 harness `bash-guard` 훅 재사용(파일삭제·
  force push·배포 차단). `run` 은 `--dangerously-skip-permissions` 를 절대 쓰지 않는다. 대화형 →
  표준 Claude Code 권한 프롬프트가 승인 게이트.
- **재개(G8)**: cold start 구조라 안전 — `resume <id>` 가 GOAL.md+DB 로 이어감. 사용자 강제중단은
  `hermes-loop.py stop <id>`(finish_reason=user-stop).
- **마스킹(G12)**: GOAL.md/DB 저장 경계에서 `hermes_redact.py` 재사용.
- **오류 안전 종료**: claude 실행 실패·파싱 실패는 그 반복을 fail 로 기록하되 루프를 즉시 죽이지 않고
  no_progress 로 취급(안전캡이 결국 잡음). DB 부재·python3 부재는 명확한 에러로 exit.

## 8. 설치 · 통합

- `presets/workflow/hermes.conf`: 신규 스크립트 4개(`hermes_loop.py`, `hermes_loop_prompt.py`,
  `hermes-loop.py`, `hermes-loop-run.sh`) 설치 매니페스트 등록, 스킬 `hermes-loop` 를 SKILLS 에 등록,
  CLAUDE.md 섹션에 루프 사용법 추가.
- `hermes-init.py`: `loops`/`loop_steps` 테이블 `CREATE TABLE IF NOT EXISTS` 추가(기존 DB 자동
  마이그레이션).
- `uninstall.sh`: 신규 스크립트를 제거 매니페스트에 등록(README 규약 — 하네스 설치물만 제거).
- 슬래시 커맨드: `/hermes-loop <목표>`(대화형). `/hermes-loop-status`(선택, 후속).
- `docs/hermes-loop-guide.md`: cron 가이드 형제로 사용법·활성화 체크리스트 작성.

## 9. 테스트

`tests/hermes-loop-test.sh` (HOME 격리 + claude 모킹, `hermes-pipeline-test.sh` 패턴):

- init → GOAL.md 생성 + `loops` 행 검증 (G1)
- 모킹 claude 가 continue×2 → goal-met+VERIFY:true → status=done, finish_reason=goal-met (G2·G4)
- goal-met + VERIFY:false → 기각되고 continue (G3)
- max_iterations=2 + 항상 continue → 강제중단, finish_reason=max-iter (G5)
- 진전 없는 continue×3 → finish_reason=no-progress (G6)
- blocked → status=stopped (G7)
- run 1회 후 kill → resume → iterations_used 이어짐 (G8)
- 종료 후 `messages` 아카이브 행 검증 (G11)
- 진행로그의 토큰 문자열 → `[REDACTED:*]` 치환 (G12)

`run-all.sh` 의 `py_compile`·`bash -n` 글롭에 신규 스크립트가 자동 포함된다.

## 10. 데이터 흐름 일관성 (완성도 검증)

```
init(CLI/스킬) → hermes_loop.write_goal_md() + loops INSERT
              → run/스킬 반복:
                   hermes_loop_prompt.build() → claude -p → parse REPORT
                   → hermes_loop.run_verify() → hermes_loop.update_step() (redact 경유)
                   → hermes_loop.check_caps() → 종료 or 다음 반복
              → 종료 시 hermes_loop.archive_to_messages()
```

REPORT 필드명(ACTION/VERDICT/VERIFY/NEXT)은 프롬프트 지시 ↔ 드라이버 파서 ↔ `loop_steps` 컬럼에서
일관 유지한다. verdict 값 집합(continue|goal-met|blocked)은 세 곳에서 동일.

## 11. 후속 과제 (별건)

- 결정적 루프(Ralph 스타일: 조건 충족까지 고정 블록 반복)와 **결정적↔비결정적 전환 전략**(헤르메스
  전략) 추가 — mode 컬럼이 이미 확장 여지를 둠.
- 루프 결과를 러닝 루프(결정화·드리밍)에 먹이기 — 반복적으로 막힌 지점을 스킬로 결정화.
- 멀티 루프 큐/스케줄러, `/hermes-loop-status` 대시보드, cron 자동 트리거.

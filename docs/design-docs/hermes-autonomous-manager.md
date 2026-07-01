# 헤르메스 자율 매니저 에이전트 심화

> 작성일: 2026-07-01
> 목적: 헤르메스의 자율 매니저 에이전트(cron 기반 무인 다중 프로젝트 처리)의 구조·데이터 흐름·실행 방법·한계를 코드 기준으로 정리한다.

## 개요

자율 매니저 에이전트는 **사용자가 자리에 없어도, 정해진 시각에 여러 프로젝트를 순회하며 Claude 서브에이전트를 자동으로 띄워 그날 할 일(exec-plan)을 처리시키고, 결과를 수집·정리하는 무인 배치 시스템**이다.

드리밍(기억 정리)과는 완전히 별개다. 드리밍은 "무엇을 기억할지"를 통합하고, 자율 매니저는 "무슨 작업을 수행할지"를 배분·실행한다. 둘은 `hermes-cron-run.sh`라는 cron 래퍼를 공유할 뿐, 로직·목적이 다르다.

### 현재 상태 (중요)

이 기능은 **설치 시 자동 활성화되지 않는다.** `hermes.conf`는 "자동 cron 등록은 하지 않음 — 사용자가 직접 설정해야 한다"고 명시하며, 코드베이스 어디에도 `crontab`에 항목을 쓰는 코드는 없다. 즉 사용자가 직접 `crontab -e`로 등록하기 전까지 매니저는 **단 한 번도 실행되지 않는다.** 반면 러닝 루프(저장·요약·결정화 등)는 Stop 훅으로 설치 시 자동 배선되어 세션 종료마다 돈다 — 자율 매니저와 대비되는 지점이다.

## 아키텍처

```
[외부 cron — 사용자가 crontab에 직접 등록]
  0 9  * * 1-5   hermes-cron-run.sh <project> start proj-a,proj-b   (오전: 배분)
  0 12 * * 1-5   hermes-cron-run.sh <project> check                 (점심: 점검, 선택)
  0 18 * * 1-5   hermes-cron-run.sh <project> end                   (오후: 마감)
        │
        ▼
  scripts/hermes-cron-run.sh  (crontab 한 줄 호출용 래퍼)
        │  1) hermes-manager.py 로 액션별 프롬프트 조립 → 임시 파일
        │  2) nohup claude -p "<프롬프트>" >> 로그 2>&1 &   (매니저 에이전트 기동)
        ▼
  매니저 에이전트 (비대화형 claude -p 세션)
        │  각 프로젝트마다 서브에이전트를 nohup claude -p ... & 로 배분
        ▼
  서브에이전트 (프로젝트별 독립 claude -p 세션)
        │  exec-plan 처리 후 결과를 messages 테이블로 비동기 보고
        ▼
  messages 테이블 (SQLite 공용 게시판) ← 매니저가 check/end 시 수집
```

Claude Code 자체에는 스케줄러가 없으므로 OS cron이 매니저를 깨우는 유일한 트리거다. 새 Hook은 만들지 않는다 — 자율 매니저는 Hook이 아니라 cron·수동 명령으로 구동되는 배치 작업이다.

## 구성 요소

| 파일 | 책임 |
|------|------|
| `scripts/hermes-cron-run.sh` | crontab 한 줄 호출용 래퍼. 프롬프트 조립 → `nohup claude -p` 백그라운드 기동을 한 번에 처리. start/check/end 세 액션만 담당(드리밍은 이 래퍼에서 분리됨 — `/hermes-dream` 수동 및 세션 훅 예정) |
| `scripts/hermes-manager.py` | 액션(start/check/end)별 매니저 프롬프트를 조립하는 텍스트 생성기. LLM 호출 없이 템플릿 + 미읽은 메시지만 채워 출력 |
| `scripts/hermes-message.py` | 에이전트 간 메시지 버스 CLI (send/recv/ack/list). `messages` 테이블 읽고 쓰기 |
| `messages` 테이블 (`.hermes/state.db`) | 에이전트 간 비동기 통신용 공용 게시판. `hermes-init.py`가 생성 |

### 역할 분리 원칙

- **Python(`hermes-manager.py`)**: 데이터 준비만 담당 — SQLite 조회, 미읽은 메시지 포맷, 프롬프트 템플릿 채우기. 판단하지 않는다.
- **Claude(`claude -p` 세션)**: 판단·실행 담당 — 어떤 작업을 고를지, 어떻게 처리할지. 프롬프트를 받아 실제 작업을 수행한다.

## 세 가지 액션 상세

### ① start — 업무 시작·배분 (오전)

1. 등록된 프로젝트 목록을 순회하며 각 프로젝트에서 읽는다:
   - `docs/exec-plans/active/` — 진행 중인 작업 계획
   - `git status` — 미커밋 변경사항
2. 프로젝트마다 `nohup claude -p "..." &`로 **서브에이전트를 백그라운드로 배분**한다.
3. 각 서브에이전트 프롬프트에는 다음 지시가 포함된다:
   - exec-plan에서 오늘 처리할 항목 1~2개 선택
   - 선택 항목 처리 (파괴적 작업 금지)
   - 완료 후 `hermes-message.py send`로 결과 보고 (`STATUS:done` 또는 `STATUS:blocked`)
4. 시작 사실을 `manager → manager` 메시지로 기록(`STATUS:started`).

`--projects`(콤마 구분)가 비어 있으면 실행하지 않는다. exec-plan이 없는 프로젝트는 배분을 건너뛴다.

### ② check — 점심 체크인 (선택)

1. `messages`에서 매니저 앞으로 온 미읽은 메시지를 수신한다.
2. 분류: `STATUS:done` → 완료 목록 / `STATUS:blocked` → 블로커 확인 / 메시지 없음 → 진행 중(정상).
3. 블로커가 있으면 해당 프로젝트에 서브에이전트를 **재배분**한다.
4. 체크인 사실을 기록(`STATUS:checked DONE:N BLOCKED:M`).

오전 배분이 충분하면 생략 가능한 선택 단계다.

### ③ end — 업무 종료·이월 (오후)

1. 하루치 메시지를 전체 수신한다.
2. 결과 분류: `done` → 완료 목록 / `blocked` → 미완료(내일 이월) / 무응답 프로젝트 기록.
3. 일일 요약을 `manager → archive` 메시지로 저장.
4. 미완료 항목이 있으면 `manager → manager` 이월 메모를 남긴다. 이 이월 항목은 **다음 날 start 시 미읽은 메시지로 자동 반영**된다.

## 메시지 버스

에이전트들은 별개 프로세스라 직접 통신할 수 없다. `messages` 테이블을 공용 게시판으로 삼아 비동기로 소통한다(팀장-팀원 메신저 모델). 서브에이전트끼리 직접 소통하지 않고 반드시 매니저를 경유한다.

### 스키마 (`.hermes/state.db`)

```sql
CREATE TABLE IF NOT EXISTS messages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    from_agent  TEXT    NOT NULL,   -- 보낸 에이전트 (프로젝트명 / manager / archive)
    to_agent    TEXT    NOT NULL,   -- 받을 에이전트
    content     TEXT    NOT NULL,   -- 메시지 본문 (STATUS 규약 문자열)
    status      TEXT    DEFAULT 'unread',   -- unread / read
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### CLI (`hermes-message.py`)

```bash
# 전송
python3 hermes-message.py --db PATH send --from AGENT --to AGENT --content TEXT
# 수신 (자동 읽음 처리, --peek 시 읽음 처리 없이 조회)
python3 hermes-message.py --db PATH recv --to AGENT [--peek]
# 특정 메시지 읽음 처리
python3 hermes-message.py --db PATH ack --id ID
# 전체 목록 (최근 N개, 상태 필터)
python3 hermes-message.py --db PATH list [--status unread|read] [--limit N]
```

### 보고 포맷 규약

서브에이전트는 반드시 아래 포맷으로 보고하고, 매니저가 check/end 시 이 포맷으로 자동 분류한다:

```
STATUS:done    TASK:<한 줄 요약>  NOTE:<특이사항 또는 없음>
STATUS:blocked TASK:<작업명>      NOTE:<블로커 이유>
```

## 하루 사이클 데이터 흐름

```
[오전 9시] start
  매니저 → 프로젝트별 서브에이전트 배분 → messages: manager→manager (STATUS:started)
     ↓ 서브에이전트들이 각자 작업
  서브에이전트 → messages: <proj>→manager (STATUS:done / STATUS:blocked)
[점심 12시] check (선택)
  매니저 → messages recv → blocked 재배분 → messages: manager→manager (STATUS:checked)
[오후 6시] end
  매니저 → messages 전체 recv → 분류
     → messages: manager→archive (일일요약)
     → messages: manager→manager (이월 항목)  ─┐
                                               │ 다음 날 start의 미읽은 메시지로 자동 반영
[다음 날 오전] start ←───────────────────────────┘
```

## 활성화 방법

설치만으로는 켜지지 않는다. 사용자가 직접 cron을 등록해야 한다.

```cron
# cron 은 PATH 가 제한적 — claude 설치 경로를 PATH 에 포함
PATH=/usr/local/bin:/usr/bin:/bin
HERMES_SCRIPTS=/path/to/ai-dev-setting/scripts

# 오전 9시 업무 시작 (평일)
0 9 * * 1-5 $HERMES_SCRIPTS/hermes-cron-run.sh /path/to/project start proj-a,proj-b
# 점심 12시 체크인 (선택)
0 12 * * 1-5 $HERMES_SCRIPTS/hermes-cron-run.sh /path/to/project check
# 오후 6시 업무 종료 (평일)
0 18 * * 1-5 $HERMES_SCRIPTS/hermes-cron-run.sh /path/to/project end
```

선행 조건: `hermes` 프리셋 설치, `claude` CLI 설치, `hermes-init.py`로 DB 초기화. 실행 로그는 `<project>/.hermes/logs/cron-<action>-<날짜>.log`에 쌓인다. 상세 설정은 `docs/hermes-cron-guide.md` 참조.

## 안전 장치

| 동작 | 처리 |
|------|------|
| 파괴적 작업 (파일 삭제·force push·DB drop) | 매니저·서브에이전트 프롬프트에 **절대 자동 실행 금지**를 명시 |
| exec-plan 없는 프로젝트 | 배분 대상에서 제외 (엉뚱한 작업 방지) |
| 서브에이전트 완료 순서 | 보장하지 않음 — messages로 비동기 수집 |
| 에이전트 간 직접 대화 | 불가(별개 프로세스) — 반드시 messages 경유 |

## 알려진 한계 및 구현-설계 불일치

1. **`claude --bg` vs `nohup claude -p ... &`** — 설계 문서(`hermes-engineering.md` §12)와 일부 서술은 `claude --bg`를 전제로 쓰였으나, **claude CLI에는 `--bg` 플래그가 없다.** 실제 구현(`hermes-cron-run.sh`, `hermes-manager.py`)은 전부 `nohup claude -p "<프롬프트>" >> 로그 2>&1 &` 패턴을 사용한다. 설계 문서의 `--bg` 표현은 역사적 서술이며 현행 구현 기준은 `nohup claude -p`다.
2. **비대화형 한계** — `claude -p` 세션은 비대화형이라 실행 중 사람과 대화할 수 없다. 판단이 필요하면 작업을 멈추고 messages로 블로커를 보고하는 방식으로만 사람 개입을 유도한다("완전 자동"이 아닌 "대부분 자동 + 필요 시 개입").
3. **cron 의존** — Claude Code에 스케줄러가 없어 OS cron이 유일한 자동 트리거다. cron이 없는 환경(또는 미등록 시)에는 수동 실행(`hermes-cron-run.sh <project> <action>`)으로만 동작한다.
4. **프롬프트 품질 편차** — 서브에이전트 결과는 프롬프트 품질에 좌우된다. 헤르메스 스킬 축적으로 점진 개선하는 것을 전제로 한다.

## 관련 문서

- `docs/design-docs/hermes-engineering.md` §12(자율 에이전트)·§13(메시지 버스) — 상위 설계 맥락
- `docs/hermes-cron-guide.md` — cron 등록·모니터링 실무 가이드
- `presets/workflow/hermes.conf` — 설치 시 자율 에이전트 힌트(`HERMES_AUTONOMOUS=1`) 출력부

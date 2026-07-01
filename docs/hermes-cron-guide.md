# 헤르메스 자율 에이전트 — cron 설정 가이드

> 설계 문서: `docs/design-docs/hermes-engineering.md` §12
> 선행 조건: `hermes` 프리셋 설치 완료, `claude` CLI 설치

## 개요

헤르메스 자율 에이전트는 외부 cron + `hermes-cron-run.sh` 래퍼 조합으로 동작한다.
Claude Code 자체 스케줄러는 없으므로 OS cron 이 매니저 에이전트를 깨운다.

> 주의: claude CLI 에 `--bg` 플래그는 없다. 비대화형 백그라운드 실행은
> `nohup claude -p "<프롬프트>" >> 로그 2>&1 &` 패턴을 사용하며,
> 래퍼 스크립트가 이를 대신 처리한다.

```
cron (오전 9시)
    ↓
hermes-cron-run.sh <project> start <projects>
    ↓ (프롬프트 조립 → nohup claude -p ... &)
매니저 에이전트 → 각 프로젝트에 nohup claude -p 서브에이전트 배분
    ↓
서브에이전트 완료 → messages 테이블에 결과 INSERT
    ↓
cron (오후 6시)
    ↓
hermes-cron-run.sh <project> end
    ↓
매니저가 messages 수집 → 일일 요약 아카이브
```

## 필수 조건

```bash
# claude CLI 설치 확인
claude --version

# python3 확인
python3 --version

# hermes DB 초기화 (프로젝트별 1회)
python3 /path/to/ai-dev-setting/scripts/hermes-init.py \
  --both /path/to/your-project
```

## cron 설정

### 1. crontab 편집

```bash
crontab -e
```

### 2. 항목 추가

crontab 은 백슬래시 멀티라인을 지원하지 않으므로,
각 항목은 `hermes-cron-run.sh` 래퍼 **한 줄 호출**로 작성한다.

```cron
# ── 헤르메스 자율 에이전트 ──────────────────────────────────────
# cron 은 PATH 가 제한적 — claude 가 설치된 디렉터리를 PATH 에 포함시킨다
PATH=/usr/local/bin:/usr/bin:/bin
HERMES_SCRIPTS=/path/to/ai-dev-setting/scripts

# 오전 9시 업무 시작 (평일)
0 9 * * 1-5 $HERMES_SCRIPTS/hermes-cron-run.sh /path/to/your-project start proj-a,proj-b,proj-c

# 점심 체크인 (선택, 평일 12시)
0 12 * * 1-5 $HERMES_SCRIPTS/hermes-cron-run.sh /path/to/your-project check

# 오후 6시 업무 종료 (평일)
0 18 * * 1-5 $HERMES_SCRIPTS/hermes-cron-run.sh /path/to/your-project end
```

실행 로그는 `<project>/.hermes/logs/cron-<action>-<날짜>.log` 에 쌓인다.

### 3. 즉시 테스트

```bash
# 매니저 프롬프트 미리 보기 (실행 없이)
python3 /path/to/ai-dev-setting/scripts/hermes-manager.py \
  --db /path/to/project/.hermes/state.db \
  --action start \
  --projects myproject

# 실제 실행 (래퍼가 nohup claude -p 로 매니저 에이전트 시작)
/path/to/ai-dev-setting/scripts/hermes-cron-run.sh /path/to/project start myproject

# 실행 로그 확인
tail -f /path/to/project/.hermes/logs/cron-start-$(date +%Y%m%d).log
```

## 메시지 버스 모니터링

에이전트 실행 중 결과를 확인하는 방법:

```bash
DB=/path/to/project/.hermes/state.db
SCRIPT=/path/to/ai-dev-setting/scripts/hermes-message.py

# manager 에게 온 미읽은 메시지 조회 (읽음 처리 없이)
python3 $SCRIPT --db $DB recv --to manager --peek

# 전체 메시지 목록 (최근 20개)
python3 $SCRIPT --db $DB list

# 미읽은 메시지만
python3 $SCRIPT --db $DB list --status unread

# 수동으로 메시지 보내기 (서브에이전트 흉내)
python3 $SCRIPT --db $DB send \
  --from myproject \
  --to manager \
  --content "완료: README 업데이트"
```

## 에이전트 흐름 상세

### 매니저 에이전트 (hermes-cron-run.sh → nohup claude -p)
- 역할: 각 프로젝트에 서브에이전트 배분
- 입력: `hermes-manager.py --action start` 출력 프롬프트
- 출력: 서브에이전트 실행 + messages 테이블 기록

### 서브에이전트 (nohup claude -p ... &, 매니저가 생성)
- 역할: 특정 프로젝트의 오늘 할 일 처리 (`docs/exec-plans/active/` 기준)
- 완료 후: `hermes-message.py send --to manager --content "STATUS:done TASK:... NOTE:..."`
- 블로커 발생 시: `hermes-message.py send --to manager --content "STATUS:blocked TASK:... NOTE:..."`

### 보고 포맷 규약

서브에이전트는 반드시 아래 포맷으로 보고한다:
```
STATUS:done    TASK:<한 줄 요약>  NOTE:<특이사항 또는 없음>
STATUS:blocked TASK:<작업명>      NOTE:<블로커 이유>
```
매니저가 `check` / `end` 시 이 포맷으로 자동 분류한다.

### 메시지 버스 (messages 테이블)
- 에이전트 간 직접 통신은 불가능 (별개 프로세스)
- SQLite messages 테이블이 공용 게시판 역할
- 매니저가 주기적으로 `recv` 로 결과 수집

## 한계 및 주의사항

1. **대화 불가**: `claude -p` 세션은 비대화형. 완료 후 결과를 messages 에 기록해야 함.
2. **순서 보장 없음**: 서브에이전트 완료 순서는 보장되지 않음 — messages 로 비동기 처리.
3. **파괴적 작업 금지**: 자동 실행 세션에서 파일 삭제·force push 등은 절대 하지 않음.
4. **claude CLI 필요**: `claude` 명령이 cron 환경에서 실행 가능해야 함 (crontab `PATH` 설정 필수).
5. **로그 확인**: 실패 원인은 `<project>/.hermes/logs/` 의 cron 로그에서 확인.

## 즉시 테스트 (check 액션)

```bash
# 점심 체크인 프롬프트 미리 보기
python3 /path/to/ai-dev-setting/scripts/hermes-manager.py \
  --db /path/to/project/.hermes/state.db \
  --action check

# 체크인 실행
/path/to/ai-dev-setting/scripts/hermes-cron-run.sh /path/to/project check
```

## 활성화 체크리스트

- [ ] `claude --version` 확인
- [ ] `python3 hermes-init.py --both <project>` 실행
- [ ] `crontab -e` 로 cron 항목 추가 (`hermes-cron-run.sh` 한 줄 호출 × start / check / end)
- [ ] `hermes-cron-run.sh <project> start <projects>` 즉시 테스트 실행
- [ ] `hermes-message.py list` 로 메시지 버스 동작 확인
- [ ] 서브에이전트 보고 포맷(`STATUS:done/blocked`) 확인

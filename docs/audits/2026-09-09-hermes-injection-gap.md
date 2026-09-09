# 헤르메스 주입 원장이 3개월간 비어 있는 원인 조사

> 작성일: 2026-09-09
> 목적: `skill_injection` 원장에 실사용 기록이 남지 않는 원인을 재현으로 확정한다.
> 실행 계획: `docs/exec-plans/active/2026-09-09-hermes-skill-lifecycle.md` Step 1

## 개요

`hermes-search.py` 는 매 프롬프트마다 스킬을 검색해 주입하고, 주입 사실을
`skill_injection` 원장에 남긴다. 원장은 `hermes-correlate.py` 의 유일한 입력이고,
correlate 가 채우는 `helpful_count`/`noop_count` 는 `hermes-prune.py` 가 낡은 스킬을
강등하는 유일한 근거다. **원장이 비면 되먹임 사슬 전체가 정지한다.**

이 조사는 원인을 **확정하지 못했다.** 대신 가설 7개를 재현으로 반증하고, 원인 규명을
막고 있는 구조적 이유를 확정했다. 그 이유 자체가 이 조사의 결론이다.

## 실측

### 원장 상태 (2026-09-09, 사본 DB 기준)

| 프로젝트 | skill_index | used_count>0 | 원장 행 | helpful | noop |
|---|---:|---:|---:|---:|---:|
| zeroday-frontend | 1082 | 26 | 3 | 0 | 0 |
| novel-bc | 111 | 2 | 0 | 0 | 0 |
| terminal-shipping | 97 | 0 | 0 | 0 | 0 |
| ai-create | 27 | 0 | 0 | 0 | 0 |
| upbit-ai-trading | 27 | 0 | 0 | 0 | 0 |
| jjackkun_bot | 26 | 0 | 0 | 0 | 0 |
| novel-ab | 15 | 0 | 0 | 0 | 0 |

원장이 있는 유일한 프로젝트의 3행은 전부 `session_id='verify-sess'`,
`injected_at='2026-06-26 05:43:53'` — 손으로 돌린 검증 흔적이다.
**실사용 세션이 남긴 주입 기록은 전 프로젝트 통틀어 0건이다.**

### 훅은 실제로 돈다

zeroday 트랜스크립트 3,203개 중

| 문구 | 포함 파일 수 |
|---|---:|
| `[Harness Reminders]` (reminders.sh 출력) | 3,199 |
| `[Active Plans]` (같은 훅, 헤르메스 블록 앞) | 3,199 |
| `[Hermes 관련 규칙]` (헤르메스 블록 출력) | **0** |

헤르메스 블록은 `[Active Plans]` 뒤·`[Harness Reminders]` 앞에 출력된다.
앞뒤가 모두 찍혔으므로 **훅은 그 지점을 지나갔고, 블록만 아무것도 내지 않았다.**

배포본을 새로 깐 2026-09-08 14:02 이후 세션 181개로 좁혀도 주입은 0건이다.
전 프로젝트 트랜스크립트를 통틀어 그 문구가 있는 파일은 1개 — 이 조사 세션 자신이다.

## 반증된 가설

전부 **재현**으로 반증했다. 되풀이 금지.

| # | 가설 | 반증 근거 |
|---|---|---|
| 1 | `--session-id` 를 안 넘긴다 | 호출부 둘 다 넘긴다 (`reminders.sh:105`, `hermes-assist.sh:63`) |
| 2 | 원장 기록 코드가 고장 | 사본 DB 로 실행 시 정상 기록 (3→6행, used 43→46) |
| 3 | 짧은 한글 프롬프트가 매칭 안 됨 | "커밋 푸시하자" 로 스킬 3건 주입 |
| 4 | `$PWD` 가 프로젝트 밖을 가리킨다 | `reminders.sh:14` 가 `CLAUDE_PROJECT_DIR` 로 **cd 부터 한다**. zeroday 에 워크트리도 없다 |
| 5 | 실세션 페이로드에 `session_id` 가 없다 | 같은 이벤트의 `mistake-detect` 가 `session_id` 비었을 때만 건너뛰는데, `recall_marker` 에 1,574행이 쌓여 있다 (2026-06-19 ~ 2026-09-08) |
| 6 | 배포본이 옛 버전 | 12개 프로젝트 배포본 md5 가 원본과 전부 동일, 헤르메스 블록 존재 |
| 7 | 로케일·인코딩 (R4) | `LC_ALL=C`·`POSIX` 에서도 정상 주입. `PYTHONIOENCODING=ascii` 에서만 깨지는데 그건 설정되지 않는다 |

호출 방식도 4가지로 시험했다 — `bash <경로>` · 직접 실행 · `sh -c` 는 전부 정상,
`source` 만 깨진다. Claude Code 는 `source` 로 훅을 부르지 않는다.
훅 전체 소요는 0.11초로 타임아웃도 아니다 (`timeout` 미설정, DB 58MB).

## 확정된 것

**실패 경로가 관측 불가능하게 봉인돼 있다.**

```bash
# assets/hooks/claude-userpromptsubmit-reminders.sh:105-108
_hermes_out=$(python3 "$_hermes_search" \
  --db "$_hermes_db" --query "$_query" --session-id "$_sid" \
  --skills-dir "$PWD/.claude/skills" \
  --global-skills-dir "$HOME/.hermes/mesh/skills" --max 3 2>/dev/null || true)
```

`2>/dev/null || true` 가 stderr 와 종료 코드를 **둘 다** 버린다.
`hermes-search.py` 는 실패를 `[hermes-search] ...` 로 stderr 에만 쓰므로
(`scripts/hermes-search.py:50`), 이 경로의 실패는 어디에도 흔적을 남기지 않는다.

같은 헤르메스 계열인 `hermes-assist.sh:65` 는 같은 호출을
`2>>"$PWD/.hermes/hooks.log"` 로 받는다. **한쪽만 조용하다.**
zeroday `hooks.log` 64,596줄에 `hermes-search` 가 0회 등장하는 이유가 이것이다.

결과적으로 "블록에 진입했으나 검색이 빈손" 과 "블록을 건너뜀" 이 **구별되지 않는다.**
이 프로젝트 규칙의 조용한 실패 금지(R5 계열) 위반이며, 원인 규명을 막는 것도 이것이다.

## 부수 발견

### (1) `recall_marker.session_id` 에 프롬프트 문장이 저장된다

1,574행 중 표본 3건이 `('그리고 QA 체크 등록하고 검증했으니 체크해야겠지', ...)` 처럼
세션 ID 자리에 사용자 문장이 들어 있다. UUID 인 행도 섞여 있다.

`claude-userpromptsubmit-mistake-detect.sh:39-40` 이 python3 출력 2줄을
`sed -n 1p`(프롬프트) / `sed -n 2p`(세션ID) 로 가르는데, **프롬프트가 여러 줄이면
2번째 줄이 프롬프트의 둘째 줄**이 된다. 줄 수에 의존하는 파싱의 정렬 붕괴다.

이 결함은 주입 원장과 무관하지만 같은 훅 계열의 같은 종류(조용한 오정렬)다.

### (2) 6개 프로젝트는 `used_count` 조차 0이다

`used_count` 는 세션 ID 와 무관하게 증가한다(`hermes-search.py:466`).
그런데 zeroday·novel-bc 를 뺀 5개 프로젝트는 0이다. 주입 실패 이전에
**매칭 자체가 한 번도 일어나지 않았다**는 뜻이며, 실행 계획 목표 3(도메인 어휘
하드코딩)이 가리키는 문제와 같은 뿌리로 보인다.

## 다음 행동

원인을 더 좁히려면 **봉인을 먼저 풀어야 한다.** 정적 분석은 여기까지가 한계다.

1. `reminders.sh` 의 `2>/dev/null` 을 `hooks.log` 로 돌린다 — assist 와 동일하게.
2. 블록 **진입** 시점에도 한 줄 남긴다. 진입/빈손을 구별하기 위해 필요하다.
3. 실사용 1일 뒤 `hooks.log` 를 읽어 원인을 확정한다.

이는 실행 계획 Step 2 의 시작 조건이다.

## 결정 기록

| 날짜 | 결정 | 근거 |
|---|---|---|
| 2026-09-09 | 원인 미확정으로 Step 1 을 닫는다 | 가설 7개를 재현으로 반증했고, 남은 경로는 관측 불가능하다. 추측으로 고치지 않는다 |
| 2026-09-09 | `2>/dev/null` 제거를 Step 2 선행 조건으로 삼는다 | 봉인을 푸는 것 외에 원인에 접근할 방법이 없다 |
| 2026-09-09 | `recall_marker` 오정렬은 별건으로 분리한다 | 원장 공백과 인과가 없다. 섞으면 Step 2 측정이 오염된다 |

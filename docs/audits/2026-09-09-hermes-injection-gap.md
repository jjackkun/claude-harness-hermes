# 헤르메스 주입 원장이 3개월간 비어 있는 원인 조사

> 작성일: 2026-09-09
> 목적: `skill_injection` 원장에 실사용 기록이 남지 않는 원인을 재현으로 확정한다.
> 실행 계획: `docs/exec-plans/active/2026-09-09-hermes-skill-lifecycle.md` Step 1

## 개요

`hermes-search.py` 는 매 프롬프트마다 스킬을 검색해 주입하고, 주입 사실을
`skill_injection` 원장에 남긴다. 원장은 `hermes-correlate.py` 의 유일한 입력이고,
correlate 가 채우는 `helpful_count`/`noop_count` 는 `hermes-prune.py` 가 낡은 스킬을
강등하는 유일한 근거다. **원장이 비면 되먹임 사슬 전체가 정지한다.**

**원인을 확정했다: 훅이 사용자 프롬프트를 받지 못한다.** stdin 이 빈 채로 들어온다.

조사는 두 단계였다. 먼저 가설 7개를 재현으로 반증했으나 원인에 닿지 못했고(§반증된 가설),
실패 경로가 `2>/dev/null` 로 봉인돼 있다는 것만 확정했다. 봉인을 풀어 계장을 배포하자
**30분 만에** 실세션이 답을 남겼다(§확정된 원인).

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

## 왜 4개월간 확정하지 못했나 — 봉인

**실패 경로가 관측 불가능하게 봉인돼 있었다.**

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

## 확정된 원인

### (1) 계장이 실세션에서 남긴 줄

계장 배포 30분 뒤 zeroday 5줄, terminal-shipping 1줄:

```
[hermes-search-hook] no-query session=EMPTY
```

`_query` 도 `_sid` 도 비어 있다. 페이로드 파싱이 아니라 **stdin 자체가 비어서 들어온다.**

### (2) "매칭이 안 돼서" 가 아니다 — 4개월치로 배제

zeroday 트랜스크립트에서 실제 사용자 프롬프트 **7,074건**을 뽑아, 배포본
`hermes-search.py` 의 매칭 경로에 그대로 통과시켰다(DB 는 사본, 쓰기 없음).

| 항목 | 값 |
|---|---:|
| 실제 프롬프트 (2026-06 ~ 09) | 7,074 |
| 키워드 추출 실패 | 3 |
| 매칭 0건 (→ `claude -p` 폴백행) | 238 (3%) |
| **주입이 일어났어야 할 프롬프트** | **6,836 (96%)** |
| **일어났어야 할 총 주입 건수** | **19,939** |
| 실제 원장 행수 | 3 (전부 수동 `verify-sess`) |
| 실제 `used_count` 합계 | 43 |

19,939 대 0 이다. **"블록에 진입했으나 빈손" 은 배제된다.** 진입 자체를 못 했다.

### (3) 기전 — stdin 을 형제 훅과 경쟁한다 (강한 정황, 미확정)

같은 `UserPromptSubmit` 이벤트에 훅이 여럿 등록돼 있다.

| 프로젝트 | 등록 순서 |
|---|---|
| zeroday-frontend | kos-plans → **reminders** → mistake-detect |
| terminal-shipping | docs-first → mistake-detect → **reminders** |

`mistake-detect` 는 파일 검사 두 개만 하고 **곧바로** `input="$(cat)"` 로 stdin 을 통째로
읽는다(24행). `reminders` 는 계획·백로그 스캔(`find` + `plan_state.py` 여러 번)을
**모두 끝낸 뒤** 92행에서야 읽는다. 하나의 파이프를 나눠 쓰면 먼저 읽는 쪽이 다 가져간다:

```
$ echo '{"prompt":"...","session_id":"x"}' | { bash h1.sh; bash h2.sh; }
h1 got: 37 bytes
h2 got: 0 bytes
```

`recall_marker` 에 1,574행이 쌓인 것과 `skill_injection` 이 0행인 것이 이 구도와 맞는다.
다만 Claude Code 가 훅마다 stdin 을 따로 주는지 공유하는지는 **직접 확인하지 못했다.**
기전 확정에는 양쪽 훅에 원시 stdin 바이트 수를 남기는 계장이 더 필요하다.

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

계장은 배포·검증 완료(커밋 `068c871`). 남은 것은 **stdin 경쟁 제거**다.

`reminders` 가 stdin 을 먼저 읽게 바꾸는 것은 **해결이 아니다** — 지는 쪽이
`mistake-detect` 로 바뀔 뿐이다. 한 이벤트에서 stdin 이 필요한 훅이 둘인 구조 자체를
없애야 한다. 방향 두 가지:

1. **두 훅을 하나로 합친다** — stdin 을 한 번 읽고 recall·스킬검색·리마인더를 모두 수행.
   경쟁이 사라지고 파싱도 한 곳이 된다. 12개 프로젝트 공유 경계 변경이라 리뷰 승격 대상.
2. **먼저 읽는 훅이 페이로드를 파일로 넘긴다** — 순서 보장이 없으면 무의미하므로
   기전 (3) 을 먼저 확정해야 쓸 수 있다.

어느 쪽이든 사람의 결정이 필요하다. 실행 계획 Step 2 에서 다룬다.

## 결정 기록

| 날짜 | 결정 | 근거 |
|---|---|---|
| 2026-09-09 | 원인 미확정으로 Step 1 을 닫는다 | 가설 7개를 재현으로 반증했고, 남은 경로는 관측 불가능하다. 추측으로 고치지 않는다 |
| 2026-09-09 | `2>/dev/null` 제거를 Step 2 선행 조건으로 삼는다 | 봉인을 푸는 것 외에 원인에 접근할 방법이 없다 |
| 2026-09-09 | `recall_marker` 오정렬은 별건으로 분리한다 | 원장 공백과 인과가 없다. 섞으면 Step 2 측정이 오염된다 |

# kis-trading 얼어붙은 hermes 스크립트 — 프리셋 추가 설치로 해소 (2026-09-18)

> 목적: 전파할 때마다 반복 발견되던 kis-trading 의 옛 hermes 스크립트를 정리하고, 결정을 기록해 네 번째 재발견을 막는다.

## 반복 이력

| 날짜 | 어디서 | 무엇 | 처리 |
|---|---|---|---|
| 2026-08-20 | kis-trading `c801672` | hermes 스크립트가 그 저장소에 커밋됨(당시 22개) | — |
| 2026-09-15 | `completed/2026-09-15-copy-install.md` §7 | `.gitignore` 가 `.claude/*` 를 무시 → 훅 사본만 커밋 | 관찰만 |
| 2026-09-17 | `completed/2026-09-17-install-coexistence.md` §3·§6·§7 | 공장과 다른 22개 = "고친 게 아니라 안 받은 것" | **비목표로 미룸**, backlog 미작성 |
| 2026-09-18 | 결정화 철회 보류 전파 | 33개 DIFF/MISSING | 이 문서 |

원인: `presets.lock` 이 `node svelte python fastapi postgres harness prettier` 뿐이라 전파가 hermes 스크립트를 건드리지 않았다.
헤르메스 훅도 등록돼 있지 않아 옛 스크립트가 실행되지는 않았다. 세 번 마주치고도 backlog 로 남기지 않은 것이 "왜 또" 의 답이다.

## 결정 (사용자, 2026-09-18)

**hermes 프리셋 추가 설치.** 삭제안은 `.hermes/history`(과거 세션 저장 흔적)와 스크립트를 가르는 되돌리기 어려운 변경이라
부작용 우려로 기각. 형제 프로젝트 `upbit-ai-trading` 과 같은 구성이 된다.

## 실행

`bash project-claude.sh /home/jjackkun/PROJECT/kis-trading node svelte python fastapi postgres harness prettier hermes`

- `presets.lock` → `… harness prettier hermes`
- hermes 스크립트 76개 복사 — `hermes-crystallize.py`·`hermes_reversed_guard.py`·`hermes-dream.py`·`hermes-summarize.py` 공장과 byte 일치
- `.hermes/`: `state.db` 초기화, `factory.json`(d123542), `universe.id`, `agents.json`(main), `organization.yaml`(빈 조직), `skills/`
- `.claude/settings.json` 훅 37개 — upbit-ai-trading 과 집합 동일(차이 0)
- `.factory-new` 충돌 0

## 남은 것 (사용자 몫)

- kis-trading 작업 트리에 미커밋 101건(오늘 설치 + 이전 전파분). `.claude/*` 는 gitignore 라 훅·스크립트 사본만 커밋된다.
  그 저장소에서 커밋하는 일은 공장이 하지 않는다.

## 부하 실측 — "훅 37개가 작업에 악영향을 주는가" (2026-09-18, 사용자 질문)

결론: 없다. 스크립트 76개는 디스크에만 있어 컨텍스트 비용 0. 비용은 아래 둘뿐이다.

### 매 턴 컨텍스트 주입

| 프로젝트 | UserPromptSubmit 1턴 | 소요 | 내역 |
|---|---|---|---|
| upbit-ai-trading (로컬 스킬 0 — kis-trading 도 같은 출발점) | 1.9 KB (~600토큰) | 290 ms | 활성 계획·하네스 리마인더(hermes 없어도 나오는 몫) |
| zeroday-frontend (로컬 스킬 1,094) | 5.2 KB (~1,500토큰) | 430 ms | 위 1.7 KB + 헤르메스 규칙 2~3개 ≈ 2.1 KB(상한 있음) |

PostToolUse 8개 훅: 도구 호출당 0 B / ~200 ms. SessionStart 읽기 전용 훅 8개: 0 B.
(부작용 있는 dream·sync-pull·mutation-probe·reindex 는 라이브에서 실행하지 않고 코드로만 읽음 — 드림은 백그라운드라 대화 지연 없음.)

### 백그라운드 CLI 호출 (전부 haiku, 입력 상한 있음)

| 언제 | 횟수 | 입력 상한 | zeroday 30일 실측 |
|---|---|---|---|
| 세션 종료 요약 (Stop → hermes-summarize) | 세션당 1회 | 6,000자 | 130회 |
| 드리밍 (SessionStart, throttle 20h) | 하루 최대 1회 | 청크 4,000자, 평균 요약 8.3건/회 | 21회 |
| 결정화 | 패턴 3회 이상일 때 | — | 누적 943개 |

훅 경로의 검색 폴백(`hermes-search --no-fallback`)은 꺼져 있다. kis-trading·upbit 는 30일 세션 0건 — 실사용 0.

### 부하가 아니라 품질에서 본 것

zeroday 에서 이날 주입된 규칙이 `commoncodemanagementpage.md`·`app-layout__content.md` — 페이지 이름이 그대로 스킬이 된 것.
턴당 주입은 상한이 있어 토큰은 새지 않지만 쓸모없는 규칙이 주입된다. → `backlog/zeroday-pagename-skills.md`

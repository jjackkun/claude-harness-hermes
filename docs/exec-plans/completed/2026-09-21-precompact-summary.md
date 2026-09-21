# 2026-09-21-precompact-summary — 압축 직전에 5슬롯 요약을 한 번 더 남긴다

> 출처: `docs/exec-plans/backlog/precompact-summary-hook.md` (ECC 결핍 #7, 사용자 "다 필요한 것들" 확정 2026-09-19)
> 설계 결정 인용: 없음 — 기존 요약기 재호출. 새 형식·새 저장소 없음.

## 1. 동기 (Why)

실측(2026-09-21): 저장소 전체에 `PreCompact` 훅 등록이 **0건**이다(`grep -rn PreCompact` → 없음).
세션 기억(`session_summary`)은 Stop 훅에서만 쓰이므로, 긴 세션이 압축된 뒤 세션이 비정상 종료되면
그 구간의 결정·미완 작업은 어디에도 남지 않는다. 이 세션도 오늘 압축을 한 번 겪었다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — `assets/hooks/claude-precompact-summary.sh` 가 stdin JSON(`transcript_path`·`session_id`·`trigger`)을 읽고
  기존 `hermes-save-session.py` → `hermes-summarize.py` 를 **그대로** 부른다(새 요약 형식 없음)
  — 검증: `bash tests/precompact-summary-test.sh` (a) 픽스처 transcript 로 `session_summary` 1행 증가
- [x] 목표 2 — 훅은 대화를 막지 않는다: 즉시 rc 0, 처리는 `setsid` 백그라운드(Stop 훅과 같은 방식)
  — 검증: 같은 테스트 (b) 훅 자체 소요 < 1초 · 표준출력 0바이트
- [x] 목표 3 — 전제가 없으면 조용히 끝난다: transcript 없음·DB 없음·jq/python 없음 → rc 0, 부작용 0
  — 검증: 같은 테스트 (c)
- [x] 목표 4 — 마스킹 경로를 그대로 탄다: `CLAUDE_PROJECT_DIR` 를 넘겨 `.env` 정답지 기반 마스킹이 살아 있다
  — 검증: 같은 테스트 (d) 정답지 값이 요약에 원문으로 남지 않음
- [x] 목표 5 — 설치 배선: `PRE_COMPACT_HOOKS` 배열 → `settings.json` 의 `PreCompact` 항목으로 생성된다
  — 검증: `bash tests/precompact-summary-test.sh` (e) + `bash tests/harness-hooks-smoke.sh`
- [x] 목표 6 — 등록·폐로: `hermes.conf` 복사 목록·`run-all.sh`·문서 카운트
  — 검증: `bash tests/install-closure-test.sh` · `bash tests/run-all.sh --check-orphans` · `bash scripts/sync-doc-counts.sh`

## 3. 비목표 (Out of Scope)

- 압축 뒤 **재주입**(ECC 의 pre-compact.js 는 다음 컨텍스트에 다시 넣는다) — 세션 시작 훅의 회상이 이미 그 일을 한다.
  압축은 세션이 끊기는 것이 아니라 이어지므로, 먼저 "잃지 않는 것" 까지만 한다.
- 결정화·드리밍을 압축 시점에 돌리는 것 — 비용이 압축마다 든다. Stop 과 하루 1회 드림이 그대로 맡는다.
- 새 요약 형식·새 테이블.

## 4. 영향 영역

- 코드: `lib/settings_gen.sh`(배열 1줄), `lib/generate_settings_json.py`(이벤트 표 1줄 + 읽기 1줄),
  `presets/workflow/hermes.conf`(복사 목록 + 훅 등록)
- **신규 파일 목록**:
  - `assets/hooks/claude-precompact-summary.sh` — 압축 직전에 세션 저장·롤링 요약을 백그라운드로 한 번 돌린다(그 외 책임 없음)
  - `tests/precompact-summary-test.sh` — 요약 1행 증가·비차단·전제 부재·마스킹·설치 배선 실측
- 룰: R3(모델 호출은 기존 요약기 경로 그대로 — 훅이 직접 부르지 않는다) · R-iface
- 설치: 12곳 전파(훅 1개 추가)
- 데이터: `session_summary` 갱신(기존 upsert 경로)

## 5. 단계 (Steps)

### Step 1. 테스트 먼저(RED) [단순]
### Step 2. 훅 + 설치 배선(GREEN) [단순]
### Step 3. 등록·전체 스위트·전파 [단순]

## 6. 의사결정 로그

- 2026-09-21: 압축 시점에 결정화·드림은 돌리지 않는다 — 근거: 압축은 긴 세션에서 여러 번 일어날 수 있고, 그때마다 모델 호출이
  붙으면 크레딧이 샌다. 요약(haiku 1회)만 한다.
- 2026-09-21: `trigger`(manual/auto) 로 동작을 가르지 않는다 — 근거: 둘 다 "여기서 컨텍스트가 잘린다" 는 같은 사건이다.

## 7. 발견·예외

- **마스킹 검사 지점을 잘못 잡았다가 고쳤다.** 처음엔 "저장된 슬롯에 정답지 값이 없다" 를 단언했는데, 마스킹은
  `hermes-summarize.messages_to_text` 에서 **모델에 들어가기 전(델타)** 에 걸린다. 슬롯은 모델 출력이라 가짜 모델이 아무 값이나
  쓰면 통과·실패가 뒤집힌다. 시험을 "모델이 무엇을 받았는가" 로 옮기고, `.env` 를 치우면 값이 그대로 들어가는 자기 검사를 붙였다.
- `PreCompact` 는 설정 생성기에 없던 이벤트였다 — `settings_gen.sh` 배열 1줄 + `generate_settings_json.py` 표 1줄로 끝났다.
  이벤트 표가 if 사슬이 아니라 표라서 복잡도(R-cx) 가 오르지 않았다(2026-09-16 SubagentStop 때의 교훈이 값을 했다).
- 압축 뒤 **재주입**은 하지 않는다(비목표) — 세션 시작 훅의 회상이 이미 그 일을 한다. 압축은 세션을 끊지 않으므로
  "잃지 않는 것" 까지가 이번 몫이다.

## 8. 회고 (완료 시 작성)

- 잘된 것: 새 요약 형식을 만들지 않고 Stop 훅과 같은 도구를 그대로 불렀다. 훅 본문이 짧아 검사 지점이 분명하다.
- 잘못된 것: 마스킹 시험을 보장 지점이 아닌 곳에 걸었다 — "통과만 보는 시험" 이 될 뻔했고 자기 검사가 그것을 잡았다.
- 다음 룰 후보: "가짜 모델을 쓰는 시험은 모델 **입력**을 단언한다" — 출력은 픽스처가 정하는 값이라 아무것도 증명하지 않는다.

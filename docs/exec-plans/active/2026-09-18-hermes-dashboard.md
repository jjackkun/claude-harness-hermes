# 2026-09-18-hermes-dashboard — 소우주·우주 대시보드(에이전트·스킬 한눈에)

> 출처: 2026-09-18 대화 — 사용자 의견: "각 소우주가 현재의 에이전트 상황과 스킬 상황을 한눈에 볼 수 있는 대시보드 페이지"
> 설계 결정 인용: S-01(스킬 4층) · S-10(강등 스킬의 출처 표시) · L-01(기존 결정화 스킬은 지우지도 분류하지도 않는다 — 대시보드는 보여줄 뿐)
> · C-19(명부는 `hermes-agent.py` 가 정본) · R3(모델 호출 없음)

## 1. 동기 (Why)

현재 상태를 보는 수단은 `/hermes-status`(텍스트 몇 줄)와 루프 보고서(`hermes_loop_report.py` → report.html, 루프 1건 전용)뿐이다.
2026-09-18 하루 동안 사람이 눈으로 찾아낸 것들 — kis-trading 의 얼어붙은 스크립트 33개, zeroday 의 주입 71% 를 먹던 스킬 4개,
명부 9곳 전부 `main` 1명 — 은 전부 DB·파일에 이미 있던 사실이었다. 한 페이지에 모여 있었으면 첫 전파 때 보였다.
재료(실측, zeroday): `skill_index` 1,142 · `skill_injection` 5,093 · `pattern_count` 5,693 · `session_summary` 292 · `dream_log` 56 ·
`journal_events` 98 · `agents.json` · `organization.yaml` · `.harness/gate-events.jsonl`.

## 2. 목표 (What — 검증 가능한 형태)

- [ ] 목표 1 — `python3 scripts/hermes-dashboard.py --project-dir <소우주>` 가 `.hermes/dashboard.html` 하나를 쓴다(외부 자원 0, 모델 호출 0)
  — 검증: `bash tests/hermes-dashboard-test.sh` (생성·`<script src`/`<link href` 0·`claude` 호출 0)
- [ ] 목표 2 — **에이전트 판**: 명부(이름·상태·분야/직급/조직), 열린 인계(kind·기한·blocked)·최근 소환 10건, 담당 없음 제안 수
  — 검증: `bash tests/hermes-dashboard-test.sh` 에이전트 절 — 픽스처 명부 3명(1 은퇴)·인계 2건(1 blocked) 이 표에 그대로
- [ ] 목표 3 — **스킬 판**: 층별 개수(S-01 네 층), 주입 상위 10·도움률, 강등 후보(`hermes_skill_yield.low_yield_skills` 재사용, 기준 중복 정의 금지),
  결정화 대기(`pattern_count` count≥3·crystallized=0) — 검증: `bash tests/hermes-dashboard-test.sh` 스킬 절 — 강등 후보 1개가 `python3 scripts/hermes-cleanup.py --db … ` dry-run (e) 와 같은 집합
- [ ] 목표 4 — **학습 루프 판**: 요약 수·마지막 드림 시각·다음 드림 가능 시각(throttle 20h)·진화 건수 — 검증: `bash tests/hermes-dashboard-test.sh` 루프 절 — 픽스처 `dream_log` 2행으로 값 일치
- [ ] 목표 5 — **건강 판**: 게이트 발화율 상위 5(`gate_report.py` 재사용)·리뷰 빚(`.claude/.review-dirty`)·활성 계획 목록 — 검증: `bash tests/hermes-dashboard-test.sh` 건강 절 — 픽스처 이벤트 20건
- [ ] 목표 6 — **우주 페이지**: `python3 scripts/hermes-dashboard.py --universe` 가 `.installed-projects` 를 훑어 소우주별 한 행
  (에이전트 수·스킬 수·도움률·강등 후보 수·마지막 드림·factory_commit 일치 여부)을 `.hermes/universe-dashboard.html` 에 쓴다.
  hermes 미설치 프로젝트는 "미설치" 로 표시(kis-trading 사례) — 검증: `bash tests/hermes-dashboard-test.sh` 우주 절 — 임시 레지스트리 3곳(1 미설치)
- [ ] 목표 7 — `/hermes-dashboard` 스킬: 생성 후 경로를 알리고, 세션 시작 훅이 하루 1회 갱신(드림 throttle 과 같은 마커 방식, 백그라운드)
  — 검증: `tests/hermes-dashboard-test.sh` 훅 절(마커 24h 이내면 미실행)
- [ ] 목표 8 — 설치 폐로: 새 모듈이 `hermes.conf` 복사 목록·`.deprc`·`run-all.sh` 에 있다 — 검증: `bash tests/install-closure-test.sh` · `bash tests/dep-contract-test.sh` · `bash tests/run-all.sh --check-orphans`

## 3. 비목표 (Out of Scope)

- 서버·실시간 갱신·차트 라이브러리 — 정적 HTML(표 + 인라인 CSS)만. 외부 스크립트 0 이라 오프라인·보안 검토 불필요.
- 대시보드에서 조작(입사·강등 실행) — 보기 전용. 조작은 기존 CLI/스킬.
- 강등·junk 기준의 재정의 — `hermes_skill_yield.py` 가 정본(한 책임).
- 우주 페이지가 소우주 DB 에 쓰기 — 읽기 전용(`mode=ro`).

## 4. 영향 영역

- 코드: `scripts/hermes-cleanup.py`·`hermes_skill_yield.py`·`gate_report.py` 는 **재사용만**(변경 없음)
- **신규 파일 목록**:
  - `scripts/hermes_dashboard_data.py` — 소우주 한 곳의 DB·파일에서 네 판의 숫자·표 행을 dict 로 모은다(읽기 전용, 표준 모듈 + yield/layers import)
  - `scripts/hermes_dashboard_html.py` — dict → HTML 문자열(표·인라인 CSS·이스케이프). 데이터 로직 없음
  - `scripts/hermes-dashboard.py` — CLI 진입점(`--project-dir` / `--universe`), 파일 쓰기, 우주 집계 루프
  - `assets/skills/hermes-dashboard/SKILL.md` — `/hermes-dashboard` 트리거·출력 경로 안내
  - `assets/hooks/claude-sessionstart-dashboard.sh` — 하루 1회 백그라운드 갱신(마커 `.hermes/dashboard-last-run`)
  - `tests/hermes-dashboard-test.sh` — 픽스처 소우주(hermes-init + 명부·인계·주입·드림 삽입)로 네 판·우주 페이지·훅 throttle 검증
- 룰: R3(모델 호출 0) · R6(UI 작업 전 `frontend-design`/`impeccable` 스킬 호출 — HTML 작성 단계에서 준수) · R-iface(새 파일 공개 심볼 ≤7)
  · R-dep(`.deprc`: data=tier 1(yield·layers import), html=tier 0, CLI=tier 2)
- 설치: `presets/workflow/hermes.conf` 복사 목록 + SessionStart 훅 등록 → 12곳 전파
- 데이터: 쓰기는 `.hermes/dashboard.html`·`universe-dashboard.html`·마커뿐. `.gitignore` 에 둘을 추가(파생물, A-10 과 같은 판단)

## 5. 단계 (Steps)

### Step 1. 데이터 수집 모듈 + 테스트(RED→GREEN) [Plan/Impl]
- 픽스처: `hermes-init.py --project` + `hermes-agent.py hire` 3명(1 은퇴) + `open_handoff` 2건 + 주입 60건(1 스킬 도움 0) + `dream_log` 2행
### Step 2. HTML 렌더 모듈 — `frontend-design` 스킬 호출 후 작성 [Impl]
### Step 3. CLI + 우주 집계 + `.gitignore` [Impl]
### Step 4. 스킬 + SessionStart 훅 + 등록(hermes.conf·.deprc·run-all) + 설치 폐로 테스트 [Impl]
### Step 5. 실 소우주 3곳(zeroday·terminal-shipping·kis-trading)에서 생성해 눈으로 확인 → 전파 [Review]

## 6. 의사결정 로그

- 2026-09-18: 정적 HTML·서버 없음 — 근거: 루프 보고서가 같은 방식으로 이미 쓰이고, 소우주 12곳에 서버를 두는 운영 비용을 지지 않는다.
- 2026-09-18: 데이터/렌더/CLI 세 파일로 분리 — 근거: 루프 보고서(235줄 단일 파일)가 데이터와 HTML 을 섞어 테스트가 HTML 문자열을
  grep 하는 형태가 됐다. 데이터 dict 를 직접 단언하면 테스트가 렌더 변경에 흔들리지 않는다.
- 2026-09-18: 강등 후보는 `hermes_skill_yield` 를 import — 근거: 기준이 두 곳에 있으면 cleanup 과 대시보드가 다른 답을 낸다.
- 2026-09-18: 하루 1회 자동 갱신은 드림과 같은 throttle 마커 방식 — 근거: 이미 검증된 패턴(`claude-sessionstart-dream.sh`), 세션 시작 지연 0(백그라운드).

## 7. 발견·예외

## 8. 회고 (완료 시 작성)

- 잘된 것:
- 잘못된 것:
- 다음 룰 후보:

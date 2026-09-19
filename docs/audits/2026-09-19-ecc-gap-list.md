# 2026-09-19 — ECC(everything-claude-code v2.2.1) 대비 우리 하네스 결핍 목록

> 출처: 사용자 요청 "ECC 에서 우리에게 필요한 게 무엇이 있을까? 목록화해보자". 조사는 탐색 에이전트(gh api 원문 읽기 + 우리 assets/scripts/backlog grep 대조).
> 배경: 우리 하네스는 초기 커밋(2026-07-01)에 ECC 스킬 5개(`origin: ECC`)를 들여온 하류다. 에이전트 이름도 ECC 부분집합.
> ECC 2.0(06-09)·2.2(08-25) 변경 요지: 매니페스트 설치·소유권 원장·doctor/repair, MCP 기본 커넥터 1개로 축소, council, agent-eval, autonomous-loops, memory vault, instincts v2.1.

## 목록 (가치 상 → 하)

| # | 후보 | ECC 실체 | 우리 현황 | 가치 | 이유 |
|---|---|---|---|---|---|
| 1 | 설치 doctor / repair | `scripts/doctor.js`(drift·누락 진단, `--json`) · `scripts/repair.js`(`--dry-run`) | **약함** — 설치만 있고 진단은 factory-link/tamper 경고뿐, 복구 명령 없음 | 상 | 12곳 복사 설치에 "무엇이 어긋났나·되돌려라" 한 방 명령이 없다. 오늘 terminal-shipping adhd 유실이 그 사례 |
| 2 | skill-comply (규칙 준수율) | `skills/skill-comply/` — 3단계 엄격도 시나리오 → 툴콜 타임라인으로 준수율 | **없음** (backlog `agent-eval-regression` 과 겹침) | 상 | 훅·게이트가 실제로 지켜지는지 재는 장치가 없다. R-mut 은 게이트 코드만 본다 |
| 3 | eval-harness + harness-optimizer (pass@k) | `skills/eval-harness/` · `agents/harness-optimizer.md` | **없음** (backlog 부분 겹침) | 상 | 훅 추가·룰 승격의 효과를 수치로 못 잰다. #2 와 짝 |
| 4 | gateguard 사실 강제 | `scripts/hooks/gateguard-fact-force.js` — Edit 전 importer·영향 API 인용 요구 | **약함** — 형식 검사만 | 중 | "import 그래프 확인" 룰이 문서에만 있음 |
| 5 | 세션 비용·토큰 추적 | `scripts/hooks/cost-tracker.js` · `skills/cost-tracking/` | **없음** (backlog `platform-cost-performance-levers` 겹침) | 중 | 모델 라우팅 blind-spot 을 풀려면 토큰 실측이 선행 |
| 6 | context-budget 감사 | `skills/context-budget/` | **없음** | 중 | 매 세션 로드되는 스킬·룰·CLAUDE.md 의 비용 표가 없다 |
| 7 | PreCompact 요약 보존 | `scripts/hooks/pre-compact.js` | **약함** — 스킬만 있고 훅 0 | 중 | 압축 직전 상태를 `.hermes` 요약에 흘리면 recall 품질 상승. 구현 작음 |
| 8 | `.claude/` 보안 스캔(AgentShield) | `skills/security-scan/` | **없음** — check-secrets 는 코드 비밀만 | 중 | 권한 allowlist·훅을 배포하면서 설정 자체는 안 훑음 |
| 9 | council 구조적 반론 | `skills/council/` · `council-multi-model/` | **없음** | 중 | C-21~26 같은 설계 결정을 단일 시선으로만 검토 |
| 10 | orch-* 파이프라인 | `skills/orch-pipeline/`(크기 분류기·인간 게이트) | **약함** — reasoning-sandwich 원칙만 | 하 | 봉투/소환과 중복. 크기 분류기 아이디어만 |
| 11 | config-protection 훅 | `scripts/hooks/config-protection.js` | **약함** — 경고만 | 하 | 전역 규칙 1(설정 임의 변경 금지)의 기계 강제. 작은 작업 |
| 12 | skills-health / stocktake | `scripts/skills-health.js` · `skills/skill-stocktake/` | 부분 — 결정화 스킬엔 correlate 있음 | 하 | 배포 스킬(`assets/skills/`) 품질 감사 없음 |
| 13 | ADR 자동 포착 | `skills/architecture-decision-records/` | 다른 형태로 있음(design-docs + decision-ledger) | 하 | 감지 자동화만 차이 |
| 14 | agent-eval (A/B) | `skills/agent-eval/` | **없음** | 하 | 우리는 구독 CLI 단일 경로(R3) |
| 15 | work-items / worktree-lifecycle | `scripts/work-items.js` 등 | 대응물 있음(봉투·명부) | 하 | 가져올 이유 없음 |

대응물이 있어 제외: memory vault ↔ `.hermes/state.db`+journal · instincts ↔ 결정화·드림 · autonomous-loops ↔ hermes-loop · living-docs ↔ doc-gardening 훅 · delivery-gate ↔ stop-retrospective · plan-canvas ↔ 정적 HTML 보고서.

## "상" 3개를 지금 권하는 이유

1. **doctor/repair** — 설치 상태 어긋남이 수작업 커밋(`chore(harness): 자기 설치 상태 갱신`)으로 처리되고 있다. 매니페스트가 이미 있어 diff → 보고 → dry-run 복구는 하루 작업.
2. **skill-comply** — backlog `agent-eval-regression` 이 같은 문제를 적어 두었다. ECC 의 엄격도 3단계·툴콜 타임라인 설계를 그 계획의 구현 형태로.
3. **eval-harness/pass@k** — #2 시나리오를 재사용해 `gate-events.jsonl` 발화율과 합치면 "이 훅이 값을 하는가" 에 답할 수 있다.

## 다음

- 채택 여부는 사용자 결정. 채택 시 각각 `docs/exec-plans/active/` 계획서로.

## 채택 (2026-09-19, 사용자: "다 필요한 것들")

상 3 + 중 6 을 backlog 로 문서화했다. 하 6 은 대응물이 있어 보류.

| # | 후보 | 문서 |
|---|---|---|
| 1 | doctor / repair | `backlog/install-doctor-repair.md` |
| 2·3 | skill-comply · eval-harness/pass@k | `backlog/agent-eval-regression.md` §ECC 대조 |
| 4 | gateguard 사실 강제 | `backlog/gateguard-fact-force.md` |
| 5 | 세션 토큰 추적 | `backlog/platform-cost-performance-levers.md` §ECC 대조 (C6) |
| 6 | context-budget | `backlog/context-budget-audit.md` |
| 7 | PreCompact 훅 | `backlog/precompact-summary-hook.md` |
| 8 | `.claude/` 보안 스캔 | `backlog/claude-config-security-scan.md` |
| 9 | council 반론 | `backlog/council-review.md` |

착수 조건이 "없음" 인 것: PreCompact 훅(#7) · 보안 스캔(#8). 먼저 하기 좋은 순서: #7 → #8 → #5(09-29 관측 전) → #1.

# 2026-09-18-unplanned-decisions — 원장에 확정됐으나 계획서가 없던 결정 4건 닫기

> 작성일: 2026-09-18
> 목적: `backlog/design-decisions-unplanned.md` 의 4건(C-20 · D-04 · H-04 · H-09)을 인용 또는 구현으로 닫아 `R-design-cover` 기준선을 0 으로 만든다.
> 선행: 계획 `2026-09-18-decision-id-ledger`(기준선 71 → 4).

## 1. 동기 (Why)

- 기준선에 남은 4건은 "설계는 확정인데 어느 계획도 하기로 하지 않은 것" — 두 건(C-20·D-04)은 이미 구현·전제되어 인용만 빠졌고, 두 건(H-04·H-09)은 계획 4·5 가 "값만 예약" 으로 미룬 미구현이다.

## 2. 목표 (What — 검증 가능한 형태)

> 검증 명령: `bash tests/hermes-handoff-test.sh` · `bash tests/hermes-propose-test.sh` · `python3 assets/hooks/design_cover.py check`(rc 1, 기준선 0) · `bash tests/run-all.sh`.

- [x] 목표 1 — C-20 인용: 계획 3(`completed/2026-09-15-sync-transport-encryption.md`) §2 인용 줄에 C-20 을 더하고, 구현 근거(`hermes_sync_fragments.py` `_outgoing_memory`)가 테스트로 고정돼 있는지 확인. 검증: `grep -c 'body' tests/hermes-sync-test.sh` ≥1 이고 `design_cover.py check` 에서 `id:C-20` 사라짐.
- [x] 목표 2 — D-04 인용: 계획 2(`completed/2026-09-15-universe-id-journal.md`) §2 인용 줄에 D-04(전제). 검증: `id:D-04` 사라짐.
- [x] 목표 3 — H-04 구현: `open_handoff(…, envelope={"universe_id": <다른 소우주>})` 는 `task.assigned` 를 남기지 않고 **`handoff.external`** 이벤트(intent=goal, decision=`external=<universe_id> route=human`)를 남긴 뒤 id 를 돌려주고, 자동 이슈·원격 접근을 하지 않는다. 같은 소우주 id 면 평소 경로. 검증: `bash tests/hermes-handoff-test.sh` — 다른 universe → `handoff.external` 1·`task.assigned` 0, 같은 universe → 평소.
- [x] 목표 4 — H-09 구현: `hermes-propose.py template <에이전트 이름|id>` 가 SOUL.md 본문(머리말 제외) + `agents/<id>/skills/*.md` 를 합쳐 `kind: template` 봉투를 만든다. 기억(MEMORY.md)·이력은 넣지 않는다. 기존 누출 게이트(`hermes_envelope_gate`)·국한성 게이트(`mesh_gate`)를 그대로 통과해야 봉투가 써진다. 검증: `bash tests/hermes-propose-test.sh` — 봉투 kind=template, body 에 SOUL 본문·개인 스킬 포함·MEMORY 문장 미포함, 소우주 이름이 SOUL 에 있으면 거부.
- [x] 목표 5 — 스킬 문서: `hermes-agent` SKILL.md 에 "다른 소우주의 일"(사람 경유)·"에이전트 공유"(template 제안) 안내 2절. 검증: 두 문구 존재.
- [x] 목표 6 — 기준선 0: `python3 assets/hooks/design_cover.py check` rc 1, `.design-cover-baseline` 항목 0, backlog 파일 제거.

## 3. 비목표 (Out of Scope)

- 공장 측 template 봉투 승인 → `assets/agents/` 직무 템플릿 생성(사람 PR). B 소우주의 `hire --template` 은 기존 기능.

## 4. 영향 영역

- 수정: `scripts/hermes_handoff.py`(external 분기), `scripts/hermes_envelope.py`(`_KINDS` 에 template), `scripts/hermes-propose.py`(template 서브커맨드), `assets/skills/hermes-agent/SKILL.md`, 완료 계획서 2개(인용), 테스트 2개, `.design-cover-baseline`.
- 신규: `scripts/hermes_agent_export.py`(에이전트 정체성+개인 스킬을 봉투 본문으로 모으는 것만 — 기억·이력 제외 규칙 포함).
- 전파: 스크립트·스킬 → `update-all`.

## 5. 단계 (Steps)

### Step 1. 인용 [단순] — 목표 1·2
### Step 2. H-04 [Impl] — 목표 3
### Step 3. H-09 [Impl] — 목표 4·5
### Step 4. 기준선·회고·전파 [단순] — 목표 6

## 6. 의사결정 로그

- 2026-09-18: **H-04 는 이벤트 기록 + 안내까지만.** 근거: 설계 "경로는 사람 하나뿐", "자동 이슈 경로를 두지 않는다". 손해: 소우주 간 요청이 잦으면 사람 수고(원장 H-04 의 손해 그대로).
- 2026-09-18: **H-09 는 기존 제안 경로에 kind 하나를 더한다.** 근거: 설계 §5 "복제 경로 — 기존 스킬 승격 경로를 그대로 쓴다". 새 배달 경로·새 게이트를 만들지 않는다. 손해: SOUL 에 소우주 사실이 있으면 게이트에 막혀 사람이 일반화해야 한다 — 설계 의도.

## 7. 발견·예외

- 2026-09-18: 활성 계획서가 4개 ID 를 "하기로" 인용하는 순간 기준선이 0 이 됐다 — 활성 계획은 인용으로 치는 것이 맞지만, 계획이 완료로 닫히기 전까지는 "약속" 이지 "구현" 이 아니다. 이 계획은 H-04·H-09 를 실제로 구현해 약속을 지켰다.
- 2026-09-18: template 봉투의 첫 판은 누출 게이트가 SOUL 의 **에이전트 이름**을 "사람이 읽는 이름" 으로 잡아 거부했다 — 맞는 판정. 내보내기가 자기 이름을 벗기도록(`# 역할 템플릿`·"이 역할") 고침. 복제본은 새 이름·새 id 로 입사한다는 설계와도 일치.
- 2026-09-18: C-20 은 이미 `hermes-memory-events-test` §5 가 "body 만 암호문" 을 고정하고 있었다 — 계획 3 인용만 빠졌던 것.

## 8. 회고 (완료 시 작성)

- 잘된 것:
  - 4건을 인용 2·구현 2 로 정확히 갈랐고, 구현 2건은 설계 §4·§5 문장 그대로(사람 경유만·우주 템플릿 경유만)에 그쳤다 — 배달 경로·게이트를 새로 만들지 않았다.
  - 기존 누출 게이트가 template 봉투에서 그대로 일했다 — SOUL 의 이름·소우주 사실을 잡아냈다.
- 잘못된 것:
  - 테스트 진단 중 sed 로 단언의 `$?` 를 덮어 통과로 만든 뒤에야 알아챘다 — 진단용 출력은 단언을 건드리지 않는 자리(별도 echo)에 넣는다.
- 다음 룰 후보: 없음. R-design-cover 기준선 0 — 이후 새 틈은 새 확정에서만 생긴다.

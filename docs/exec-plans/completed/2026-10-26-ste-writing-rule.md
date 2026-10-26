# 2026-10-26-ste-writing-rule — 항공정비 문장 규칙(STE)을 adhd 프리셋에 더한다

## 1. 동기 (Why)

- 사용자가 다른 프로젝트 에이전트에 ASD-STE100 문장 규칙을 넣었고, 효과가 커서 전체 에이전트로 넓혀 쓰고 있다(2026-10-26 대화).
- 공장·`~/.claude` 에는 STE 규칙이 0건이다(2026-10-26 grep 실측). 사용자가 쓰는 규칙 원문은 이 컴퓨터에서 찾지 못했다.
- 기존 `adhd-output.md` 는 답변의 **순서**(첫 줄·마지막 줄)만 정하고 **문장**은 정하지 않는다. STE 가 그 빈칸을 메운다.
- 근거 조사: `docs/audits/2026-10-26-karpathy-ste100-research.md`.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 — `assets/rules/adhd/ste-writing.md` 가 있고, 규칙마다 근거(STE 번호·사용자 샘플·SimpleEnglish·전역 규칙)를 밝힌다. 검증: 숫자 2개(서술어 2, 명사 3)가 조사 문서 「사용자 실측 샘플」 표와 같다. (2026-10-26 실측: 일치, 9개 규칙 모두 근거 표기)
- [x] G2 — 기존 규칙과 충돌하지 않는다. 검증: ① 우선순위 절에 전역·decision-ledger·korean-reply 가, 본문에 adhd-output 이 이름으로 나온다(grep 1·1·2) ② planner-lite 가 짚은 충돌 3곳(규칙 7 단정 유도, 줄표 금지 vs `결정 — 이유 — 손해`, 블록 생략 vs "없음")을 고쳤다.
- [x] G3 — 프리셋 무결성 시험 통과. 검증: `bash tests/preset-integrity-test.sh` → PASS 30개 conf, 108개 참조.
- [x] G4 — 공장에서 새 파일이 보인다. 검증: `.claude/rules/adhd/ste-writing.md` 첫 줄 읽힘. 다른 5곳은 복사본이라 전파 전까지 안 보인다.

## 2-bis. 착수 전 확인한 사실 (2026-10-26)

| 확인한 것 | 결과 |
| --------- | ---- |
| adhd 설치 방식 | 공장만 `.claude/rules/adhd -> ../../assets/rules/adhd` 심볼릭 링크. 나머지 5곳(Nbbang-Run·drh-cloth-shop·jj-agent-room·terminal-shipping·zeroday-frontend)은 **복사본** — 전파 전에는 새 파일이 안 보인다 (2026-10-26 실측) |
| `assets/rules/adhd` 기존 파일 | `adhd-output.md` 1개 |
| `presets/workflow/adhd.conf` | `RULES+=(adhd)` 한 줄, 파일 목록 없음 |

## 3. 비목표 (Out of Scope)

- 영어 STE 사전(약 900 낱말) — 한국어에 옮길 수 없다.
- 매 턴 주입·Stop 훅 검사(korean 프리셋 방식). 규칙이 느슨해지는 것이 관측되면 별도 계획.
- 서브에이전트 프롬프트에 규칙 주입. 서브에이전트가 `.claude/rules` 를 읽는지 확인하지 않았다.
- 다른 소우주 전파(`update-all.sh`). 복사본 설치 5곳은 사용자가 전파를 지시할 때 받는다.

## 4. 영향 영역

- 코드: `presets/workflow/adhd.conf` 머리 주석 1줄(프리셋 설명에 STE 추가).
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `assets/rules/adhd/ste-writing.md` — 사용자에게 보이는 답변의 문장 규칙(STE 80%)과 보고 블록 구조를 에이전트에 지시한다.
  - `docs/audits/2026-10-26-karpathy-ste100-research.md` — 원문 조사·치트시트 오류·한국어 대응표·실측 샘플을 남긴다.
- 룰: 없음(R 룰 아님, 답변 형식 규칙).
- 데이터: 없음.
- 외부 의존: 없음. SimpleEnglish(MIT) 는 참고만 하고 문구를 옮기지 않는다.

## 5. 단계 (Steps)

### Step 1. 규칙 파일 작성 [단순]

- 산출: `ste-writing.md`, conf 주석.
- 검증: G1·G2.

### Step 2. 시험·리뷰 [단순]

- 산출: preset-integrity 실행, planner-lite 리뷰 1회(합격 기준: HIGH 0 이 될 때까지 반영).
- 검증: G3·G4.

## 6. 의사결정 로그

- 2026-10-26: 새 프리셋이 아니라 adhd 프리셋에 파일 추가 — 근거: 같은 목적(읽는 사람이 바로 움직이게)이고, 폴더 단위 설치라 conf 에 파일을 등록할 필요가 없다.
- 2026-10-26: 한국어 문장 길이를 단어 수가 아니라 서술어 수로 잰다 — 근거: STE 20단어를 한국어 어절로 바꿀 비율 근거가 없다. 서술어 수는 STE 5.2 와 같은 단위이고 사용자 샘플로 잴 수 있다.

## 7. 발견·예외

- 되돌리기: `assets/rules/adhd/ste-writing.md` 를 지우고 conf 주석 1줄을 되돌린다. 다른 파일은 이 파일을 부르지 않는다.
- planner-lite 지적 8건 중 7건 반영. "결정 블록 순서가 decision-ledger 와 어긋난다" 는 지적은 틀렸다 — 이미 다음 행동 바로 앞이다.

- 스레드 2번째 이미지(치트시트)에 규격과 다른 칸이 4곳 있다 — 조사 문서에 기록.

## 8. 회고 (완료 시 작성)

- 잘된 것: 한국어 숫자를 지어내지 않고 사용자가 좋다고 한 실제 출력에서 셌다. 설치가 링크라는 가정을 실측으로 깼다(5곳은 복사본).
- 잘못된 것: 첫 초안에서 "서술어 2" 의 출처를 STE 5.2 로 잘못 달았고, 줄표 금지를 근거 없이 넣었다. 리뷰가 잡았다.
- 검증하지 못한 것: 규칙이 실제 답변을 바꾸는지는 새 세션에서만 볼 수 있다. 서브에이전트가 `.claude/rules` 를 읽는지도 확인하지 않았다.
- 다음 룰 후보: 없음. 새 세션 답변에서 서술어 3 이상 문장이 반복되면 korean 프리셋처럼 Stop 훅 검사를 backlog 로 올린다.


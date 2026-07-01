# 헤르메스 B신호 연결 설계

> 작성일: 2026-06-16
> 목적: 사용자의 명시적 지적(A신호)에만 의존하던 헤르메스 러닝 루프에, 객관적 실패 신호(B신호)를 연결해 "조용한 실수"의 사각지대를 메운다.

## 개요

헤르메스 러닝 루프는 현재 **사용자가 입으로 지적한 실수**(`claude-userpromptsubmit-mistake-detect.sh`의 "자꾸/또야/계속" 키워드)만 학습 입력으로 받는다. 사용자가 지적하지 않은 실수는 루프에 들어오지 않는다.

이 설계는 실수 신호를 세 종류로 구분한다:

```
실수 신호의 출처
├── A. 사용자가 지적함        → 이미 잡음 (mistake-detect.sh)
├── B. 도구가 객관적으로 잡음  → 신호는 있으나 루프에 미연결  ← 이 설계가 메움
└── C. 아무도 모름            → ground truth 부재로 학습 불가 (범위 제외)
```

C는 정답이 없으므로 원리적으로 학습 불가능하며 본 설계의 범위가 아니다. 메울 수 있고 메워야 하는 것은 **B**다. 그리고 B 신호는 이미 transcript에 기록되고 있으나 헤르메스가 읽지 않을 뿐이다 — 즉 "없는 신호를 만드는" 것이 아니라 "있는 신호를 듣는" 작업이다.

### B신호 범위 (확정)

| 신호 | transcript 기록 여부 | 채택 |
|---|---|---|
| 테스트/빌드 실패 | Bash `tool_result`(exit code·출력) | ✅ |
| git revert/reset | Bash `tool_use`(명령 인자) | ✅ |
| 사용자의 외부 에디터 재수정 | transcript 미기록 — 탐지 불안정 | ❌ 제외 |
| 같은 파일 단시간 N회 재편집 | 거짓 양성 위험(정상 반복과 구분 불가) | ❌ 제외 |

외부 에디터 편집은 Claude Code Hook·transcript에 잡히지 않으므로 신뢰할 수 있는 토대가 아니다. 불안정한 신호 위에 루프를 의존시키면 헤르메스가 가장 경계하는 "쓰레기 패턴 오염"이 발생한다. 따라서 **확실히 기록되는 신호만** 채택한다.

## 아키텍처

새 Hook·새 파일을 만들지 않는다. 헤르메스 설계 원칙(`hermes-engineering.md` §10·§11: "기존 Hook 확장, 새 Hook 미생성")을 그대로 따른다.

`hermes-save-session.py`에 **탐지 함수 1개**를 추가하는 것이 변경의 전부다.

```
Stop Hook (claude-stop-retrospective.sh, 기존)
  └→ hermes-save-session.py
       ├─ extract_patterns()         ← 기존: 텍스트 토큰 추출 (A신호 계열)
       ├─ extract_evolution_hints()  ← 기존
       └─ detect_objective_signals() ← 신규: tool_use/tool_result 스캔 (B신호)
                                          │
                                          ▼
                          update_patterns() — 기존 pattern_count 파이프라인에 합류
                                          │
                                count ≥ 3 (서로 다른 3세션)
                                          ▼
                          hermes-crystallize.py — 별도 Haiku 프로세스가 채점
                                          │   (HERMES_DISABLED=1, 대화 맥락 0)
                                          ▼
                                자기채점 분리 유지
```

B신호는 기존 파이프라인에 "패턴 키를 만드는 새 입구"를 더할 뿐이다. 결정화·거부·인덱싱·검색은 전부 기존 코드를 재사용한다.

### 왜 새 탐지 함수가 필요한가

현재 `extract_patterns`는 메시지 content에서 `text` 필드만 읽는다(`p.get("text", "")`). Bash 명령은 `tool_use` 블록(`input` 필드), 실행 결과는 `tool_result` 블록(`content` 필드)에 있어 `text`가 없으므로 **현재 완전히 무시된다**. 따라서 B신호 탐지는 기존 함수 수정이 아니라, tool 블록을 전용으로 스캔하는 독립 함수가 맞다 — 텍스트 토큰 추출 로직과 섞이지 않아 단일 책임이 유지된다.

## 탐지 규칙

패턴 키를 **실패한 위치(locus)**로 만든다. 일반 키(`test-failure`)는 *"테스트가 자꾸 실패함"* 같은 쓸모없는 스킬을 낳으므로 금지한다. 가치는 *"특정 위치에서 반복되는 실수"*에 있다.

### ① 테스트/빌드 실패

- **선행 조건:** 직전 `tool_use`의 Bash 명령이 테스트/빌드 계열일 때만
  - 매칭: `pytest`, `jest`, `vitest`, `npm test`, `npm run build`, `tsc`, `cargo test`, `cargo build`, `go test`, `make` 등
- **실패 판정:** 대응하는 `tool_result`에서
  - exit code ≠ 0 (transcript에 `is_error` 또는 비정상 종료 표시가 있으면 우선), 또는
  - 출력에 실패 시그니처: `FAILED`, `Error`, `✗`, `npm ERR`, `error[`, `assertion`
- **키:** `test-fail:<실패 테스트파일 또는 첫 에러줄 핵심토큰>`
  - 예: `test-fail:auth_service.py`, `test-fail:tsc-TS2345`

### ② git revert/reset

- **탐지:** `tool_use`의 Bash 명령이 다음 패턴
  - `git revert`, `git reset --hard`, `git checkout -- <file>`, `git restore <file>`
- **키:** `revert:<되돌린 파일/경로>` (명령 인자에서 추출, 인자 없으면 `revert:HEAD`)

### locus 정규화

키 분산을 막기 위해 변동 토큰을 제거한다:
- 라인 번호, 타임스탬프, 임시 경로(`/tmp/...`), 해시 → 제거
- 절대경로 → 프로젝트 상대경로 또는 basename
- 목적: 같은 실수가 라인 번호만 달라 다른 키로 흩어지는 것을 방지

### 탐지 시점 모델 호출 = 0

`detect_objective_signals()`는 순수 정규식/문자열 처리만 한다. 모델 판단은 결정화 단계의 별도 Haiku 프로세스에서만 일어난다 — 작업하던 메인 세션은 자기 결과를 채점하지 않는다(자기채점 함정 회피).

## 데이터 흐름

```
detect_objective_signals(messages) → [B신호 키 목록]
        │
        ▼
update_patterns(db, A신호키 + B신호키, session_id)
        │  · pattern_session 으로 (키, 세션) 쌍 기록 → 세션내 1회만 집계 (기존 C2)
        │  · pattern_count 증가, crystallized=0 인 키만
        │  · count ≥ 3 인 키를 crystallize_targets 로 반환
        ▼
main() 이 "[hermes] CRYSTALLIZE:<keys>" 마커 출력 (기존)
        │
        ▼
Stop Hook 이 마커 grep → hermes-crystallize.py 호출 (기존)
        │  · B신호 키는 CATEGORY_METADATA 에 없는 동적 키
        │  · → SKILL_PROMPT_FROM_EVIDENCE 경로 (증거에서 규칙 도출) 사용 (기존)
        ▼
별도 Haiku 가 스킬 본문 생성 or SKIP 판정
```

### 결정화 증거 보강

B신호 키는 동적 키라 증거(evidence) 검색 품질이 결정화 결과를 좌우한다. 따라서 `detect_objective_signals()`는 신호 감지 시 **실패 맥락 한 줄**(어떤 명령이 왜 실패했는지)을 `session_history`에 함께 기록한다. 결정화 단계의 FTS5 검색이 이 맥락을 근거로 끌어와 구체적인 스킬을 만든다.

## 거짓 양성 방어 (4중)

| 방어 | 메커니즘 | 막는 것 |
|---|---|---|
| 3세션 임계 | 기존 `pattern_session` 재사용 — 서로 다른 3세션에서 반복돼야 결정화 | 일회성 실패 |
| 세션내 1회 집계 | 같은 session_id 재저장 시 중복 카운트 차단 (기존 C2 가드) | 한 세션의 폭주 |
| 결정화 게이트 | 별도 Haiku가 SKIP 시 `crystallized=-1` 영구 거부 (재시도 안 함) | junk가 스킬이 됨 |
| locus 정규화 | 키에서 변동 토큰 제거 | 같은 실패의 키 분산 |

핵심: **3세션 임계값이 곧 노이즈 필터**다. 한 번 실패하고 고친 테스트는 절대 3회에 도달하지 못한다. 서로 다른 3개 세션에서 같은 locus가 반복돼야 비로소 결정화 후보가 된다.

### 비활성화

`detect_objective_signals()`는 `hermes-save-session.py` 안에서 동작하고, 이 스크립트는 이미 `HERMES_DISABLED=1` 가드(Stop Hook·결정화 subprocess) 아래에서만 실행된다. 별도 토글이 필요 없다.

## 테스트 전략

`tests/hermes-pipeline-test.sh`에 B신호 단계를 **편입**한다(새 테스트 파일 미생성). 기존 방식(합성 JSONL transcript + 모킹된 `claude` 바이너리)을 그대로 따른다.

| 검증 | 입력(합성 transcript) | 단언 |
|---|---|---|
| 테스트 실패 탐지 | pytest `tool_use` + 실패 `tool_result`(exit≠0, FAILED) | `pattern_count` 에 `test-fail:<file>` 키 생성 |
| git revert 탐지 | `git reset --hard` `tool_use` 블록 | `revert:<file>` 키 생성 |
| 거짓 양성 차단 | 성공 테스트(exit 0) `tool_result` | 아무 키도 생기지 않음 |
| locus 정규화 | 라인번호만 다른 동일 실패 2건 | 같은 키로 합쳐짐 |
| 3세션 임계 | 같은 locus를 3개 session-id로 저장 | count=3 도달 시에만 `CRYSTALLIZE:` 마커 출력 |

검증 대상은 transcript 픽스처(파서 입력)이며 실데이터가 아니다 — 기존 테스트와 동일하게 "샘플 데이터 금지" 원칙과 충돌하지 않는다.

## 범위 밖 (명시)

- **C 신호(완전 무신호 실수):** ground truth 부재로 학습 불가. 시도하지 않는다.
- **외부 에디터 재수정 탐지:** transcript 미기록으로 신뢰 불가. 제외.
- **실시간 PostToolUse Hook:** save-session 확장으로 충분하므로 신설하지 않는다.
- **크로스 프로젝트 패턴 집계(미구현 ②):** 별도 작업. 본 설계 완료 후 결정.

## 변경 파일 요약

| 파일 | 변경 |
|---|---|
| `scripts/hermes-save-session.py` | `detect_objective_signals()` 추가, `main()`에서 호출해 `update_patterns()` 입력에 합류, 실패 맥락 `session_history` 기록 |
| `tests/hermes-pipeline-test.sh` | B신호 탐지·거짓양성·정규화·임계 검증 단계 편입 |

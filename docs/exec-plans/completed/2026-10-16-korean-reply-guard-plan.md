# 2026-10-16-korean-reply-guard — 사용자에게 가는 답변을 한국어로 강제한다 (선택 프리셋 `korean`)

## 1. 동기 (Why)

- 2026-10-16 jj-agent-room 세션에서 긴 작업 끝의 정리 보고(표·`result:`·"내가 대신 결정한 것"·다음 행동)를 **두 번 연달아 영어로** 썼다. 사용자 반응: "한국어로 해. 나 한국인이야. 제발." → 다음 보고에서 또 영어 → "왜애…!!!!!!!!!!!!! 또 영어야."
- 그 프로젝트에는 이미 자동 기억 `always-korean`(모든 사용자 출력은 한국어)이 있었다. 2026-10-14 에도 같은 지적이 있어 만든 기억이다. **기억은 참고라 긴 작업 끝에서 놓친다** — 강제 장치가 필요하다.
- 사용자 요청(2026-10-16): "메모리 말고 스킬이나 기능으로" → 공장에서 만들어 전파.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 — 마지막 답변이 영어 위주면 Stop 훅이 끝내기를 막고 "한국어로 다시 써라" 를 돌려준다(Claude 가 같은 턴에서 다시 씀).
      `bash tests/korean-reply-guard-test.sh`
- [x] G2 — 오탐 없음: 코드·경로·URL·명령·영어 식별자 표·인용한 영어 오류 문구가 많아도 본문이 한국어면, 그리고 사용자가 영어로 물었거나 영어 산출물을 요청했으면 막지 않는다.
      `bash tests/korean-reply-guard-test.sh`
- [x] G3 — 같은 답변을 두 번 막지 않는다(무한 반복 없음). stdin 이 비어 와도(형제 훅 경쟁) 동작한다.
      `bash tests/korean-reply-guard-test.sh`
- [x] G4 — 매 턴 프롬프트 앞에 한국어 한 줄이 붙는다 — **디스패처 경유**(dispatch.sh 에 페이로드를 먹여 출력 확인).
      `bash tests/korean-reply-guard-test.sh`
- [x] G5 — `korean` 프리셋을 켠 프로젝트에만 깔리고, 끄면 깔리지 않는다.
      `bash tests/korean-preset-test.sh` (신규)

## 2-bis. 착수 전 확인한 사실 (2026-10-16)

| 확인한 것 | 결과 |
| --------- | ---- |
| 매 턴 주입 구조 | UserPromptSubmit 은 디스패처 `claude-userpromptsubmit-dispatch.sh` 하나만 등록, 디스패처가 `scripts/hooks/claude-userpromptsubmit-*.sh` 를 이름순으로 부름(`assets/hooks/claude-userpromptsubmit-dispatch.sh:24`, `presets/workflow/harness.conf` 의 `USER_PROMPT_SUBMIT_HOOKS`) → 새 훅은 파일만 깔면 됨 |
| Stop 훅 등록 | `STOP_HOOKS+=` 배열에 개별 등록 — 이미 2개(`presets/workflow/hermes.conf:43` retrospective, `:50` journal-gap). `lib/settings_gen.sh:29` 가 읽음, `lib/codex_settings_gen.sh:30` 도 읽음 |
| stdin 경쟁 위험 | UserPromptSubmit 사고: 형제 훅이 있을 때 stdin 이 **빈 채로** 들어옴 — 기전은 "stdin 을 형제 훅과 경쟁(강한 정황, 미확정)"(`docs/audits/2026-09-09-hermes-injection-gap.md` §확정된 원인) → Stop 에서도 같을 수 있다고 전제하고 설계(Step 2) |
| transcript 구조 (실측, jj-agent-room 2026-10-16 세션 JSONL 끝 40줄) | assistant 항목이 **블록 종류마다 한 줄**(`thinking` 한 줄, `text` 한 줄 …). 사이에 `attachment`·`system`·`last-prompt`·`cost-state`·`api-request`·`atis-latch` 등 다른 `type` 줄이 섞임. 사용자 입력은 `type: user`(텍스트) — 도구 결과도 `user` 줄(`tool_result` 블록)이라 구분 필요 |
| Stop 훅 계약 (Step 0, 2026-10-16 code.claude.com/docs/en/hooks) | stdin 에 `transcript_path`·`stop_hook_active`·**`last_assistant_message`**(최종 답변 글). 문서: "Stop 시점에 transcript 에 마지막 답변이 없을 수 있다" → 판정은 `last_assistant_message` 우선, transcript 는 대체. 막기 = stdout `{"decision":"block","reason":…}`(exit 0), reason 이 Claude 에게 가서 같은 턴에서 이어 씀. `stop_hook_active` = 이미 Stop 훅 때문에 이어가는 중. 연속 이어가기 상한 8회 |
| 임계값 실측 (Step 1) | 최근 transcript 200개의 assistant text 블록 한글 비율 분포: 0.0 에 66건, 0.4~0.9 에 122건, **0.1~0.3 에 0건** → 0.3 확정. 최근 60개 transcript 의 124턴에 판정을 돌리면 막힘 2건 = 사용자가 지적한 실제 영어 보고 2건(오탐 0) |
| Codex 제외 | `lib/generate_codex_hooks.py` 의 `_is_claude_project_hook` 이 `${CLAUDE_PROJECT_DIR}/scripts/hooks/` 명령을 이미 걸러 냄 → 프리셋에서 따로 막지 않음(G5 [d] 가 잼) |
| 전파 | `update-all.sh` 는 각 프로젝트의 `.claude/presets.lock`(Codex 는 `.codex/presets.lock`)대로 다시 깐다(`update-all.sh:60~134`) → 선택 프리셋은 켠 프로젝트에만 갱신 |
| 답변 규칙 선례 | `presets/workflow/adhd.conf` 의 `RULES+=(adhd)` — 규칙 우선순위 문구("사용자 전역 규칙보다 낮다") |

## 3. 비목표 (Out of Scope)

- 코드·주석·커밋 메시지 언어 — 각 프로젝트 규칙 몫. 이 훅은 **사용자에게 보이는 답변 글**만 본다.
- 서브에이전트 출력(SubagentStop) — 사용자에게 바로 가지 않는다.
- **Codex 세션** — transcript 형식이 다르다. `lib/codex_settings_gen.sh` 도 `STOP_HOOKS` 를 읽으므로, 프리셋에서 Codex 쪽에는 등록하지 않는다(또는 훅이 Claude 형식이 아니면 즉시 통과).
- 영어 외 다른 언어 판정 — 한글 비율만 본다.
- 기본 켜기 — 공장은 범용이라 선택 프리셋으로만.

## 4. 영향 영역

- 코드: `presets/workflow/` (새 프리셋)
- **신규 파일 목록 (파일별 책임 1줄 필수)**:
  - `presets/workflow/korean.conf` — 한국어 답변 프리셋(규칙 1 + 훅 2 등록, Codex 제외)
  - `assets/rules/korean/korean-reply.md` — 세션 시작에 로드되는 "사용자 출력은 한국어" 규칙(예외: 코드·경로·명령·식별자 원문, 사용자가 영어를 요청한 경우). 우선순위 문구는 adhd 형식("사용자 전역 규칙보다 낮다")
  - `assets/hooks/claude-userpromptsubmit-korean.sh` — 매 턴 한국어 한 줄 주입(디스패처가 부름)
  - `assets/hooks/claude-stop-korean-guard.sh` — Stop 훅 진입점: stdin 읽기(비면 대체 경로)·끄기 스위치·판정 호출·block 출력
  - `assets/hooks/korean_reply_check.py` — 판정 모듈: transcript 끝에서 마지막 답변 글을 뽑고, 걸러 내고, 한글 비율로 판정
  - `tests/korean-reply-guard-test.sh` — 가짜 transcript 로 G1~G4
  - `tests/korean-preset-test.sh` — 켠/끈 프로젝트 설치 결과 비교(G5)
- 룰: 없음(새 R 룰 아님 — 선택 프리셋)
- 데이터: 없음
- 외부 의존: Claude Code Stop 훅의 block 응답(`{"decision":"block","reason":…}` — reason 이 Claude 에게 전달됨)과 `stop_hook_active` 필드 — 확인 결과는 §2-bis 「Stop 훅 계약」 줄

## 5. 단계 (Steps)

### Step 0. 사실 확인 [실측]

- Claude Code 문서(훅 레퍼런스)로 Stop 의 block 형식·reason 전달·`stop_hook_active` 의미 확인.
- jj-agent-room 실세션에서 Stop 훅들이 stdin 을 받는지 실측: 기존 retrospective·journal-gap 의 로그(`.hermes/hooks.log` 등)에 transcript 경로가 남는지, 또는 임시 계장 한 줄(받은 바이트 수만)을 하루 남겨 본다.
- 산출: §2-bis 갱신. **stdin 이 비어 오는 것이 확인되면** 별도 개선으로 Stop 디스패처(UserPromptSubmit 과 같은 방식)를 제안 — 이 계획은 Step 2 의 대체 경로로 그와 무관하게 동작한다.

### Step 1. 판정 모듈 + 시험 먼저 [Plan/Impl]

추출 규칙(못박음):
- transcript 를 **끝에서부터** 읽는다(끝 256KB 만, 2초 상한).
- 마지막 **사용자 텍스트 줄**(`type: user` 이고 `tool_result` 블록이 아닌 것)을 찾고, 그 뒤의 `type: assistant` 줄들에서 **`text` 블록만** 모은다. `thinking`·`tool_use` 와 다른 `type` 줄은 버린다.
- 모은 글이 비면 통과(아직 기록되지 않았을 수 있음 — 시험에 포함).

걸러 내기(판정 전에 지움): 코드 블록, 인라인 코드, URL, 경로(`/…`, `~/…`, `C:\…`), 표의 식별자 칸(백틱 안), 인용 블록(`>`).

통과 조건(막지 않음):
- 직전 사용자 텍스트가 영어 위주이거나 "영어로·in English·English" 요청이 있음.
- 남은 라틴 글자 < 40(짧은 답).
- 끄기 스위치 `KOREAN_GUARD_DISABLED=1`.

판정: 남은 글자의 한글 수 H, 라틴 수 L 에서 `H/(H+L) < 0.3` 이면 영어 위주(**임계값은 아래 시험 자료로 확정**).

시험 자료(가짜 transcript, 실제 구조 재현 — 블록마다 한 줄·사이에 다른 type 줄):
1. 영어 위주 작업 끝 보고(2026-10-16 실제 영어 보고 두 개, 식별 정보 제거) → **막음**
2. 한국어 보고 + 코드 블록·경로·영어 식별자 표 → 통과
3. 한국어 설명 + 인용한 영어 오류 문구 여러 줄 → 통과
4. 사용자가 영어로 물음 + 영어 답 → 통과
5. 사용자가 "README 를 영어로" 요청 + 영어 산출물 → 통과
6. 짧은 한 줄 영어("Done.") → 통과
7. 마지막 assistant 줄이 `thinking` 만 → 통과
8. 같은 답변으로 두 번 호출 → 두 번째는 통과(G3)
9. stdin 비어 옴 → 대체 경로로 동일 판정(G3)

### Step 2. Stop 훅 + 매 턴 훅 + 규칙 [Impl]

- `claude-stop-korean-guard.sh`:
  - stdin JSON 에서 `transcript_path`·`stop_hook_active` 를 읽는다. **stdin 이 비면** `~/.claude/projects/<프로젝트 경로 이름>/` 에서 가장 최근 `.jsonl` 을 쓴다(형제 훅 경쟁 대비).
  - 무한 반복 막기: `stop_hook_active` 가 참이면 통과 + 자체 표시(막은 답변 글의 해시를 `.hermes/korean-guard.last` 에 기록, 같은 해시면 통과) — stdin 이 비어 `stop_hook_active` 를 모를 때도 동작.
  - 오류(파싱 실패·python3 없음·시간 초과)는 통과 + 로그(기존 훅과 같은 로그 경로 — 착수 시 선례 확인).
  - 막을 때 reason: "직전 답변이 영어 위주입니다. 사용자는 한국어 사용자입니다 — 같은 내용을 한국어로 다시 쓰십시오(코드·경로·명령은 원문)."
- `claude-userpromptsubmit-korean.sh`: 한 줄만 출력(매 턴 비용 최소).
- `korean-reply.md`: 짧게, adhd 형식의 우선순위 문구.
- 검증: G1~G4 시험 통과(RED 먼저 확인).

### Step 3. 프리셋·설치 [Impl/Review]

- `korean.conf`: 규칙·훅 파일 복사 목록 + Stop 훅 등록(Claude 만, Codex 제외 방법 확인).
- 검증: G5 `tests/korean-preset-test.sh`(신규) — 켠/끈 프로젝트 설치 결과 비교.

### Step 4. 전파 [사람 승인]

- jj-agent-room 에 `korean` 을 추가(`presets.lock` 에 들어가는지 확인) → 실제 세션에서 영어 보고 흉내(시험 문장) → 막히는지 확인.
- 다른 프로젝트: 사람이 켤 프로젝트를 정하고, `update-all.sh` 가 켠 프로젝트만 갱신하는지(`presets.lock` 기준) 확인 후 전파.

## 6. 의사결정 로그

- 2026-10-16: 기억(메모리)이 아니라 훅으로 강제한다 — 근거: 기억 `always-korean` 이 있었는데도 같은 날 두 번 어김. 매 턴 주입(환기) + Stop 검사(차단) 두 겹.
- 2026-10-16: 선택 프리셋 `korean` 으로 — 근거: 공장은 범용 저장소, 한국어 강제는 사용자 성향.
- 2026-10-16: 같은 답변은 두 번 막지 않는다(`stop_hook_active` + 자체 해시 표시) — 근거: 오탐 시 무한 반복 방지, stdin 이 비어도 동작. 손해: 다시 쓴 글이 또 영어여도 한 번은 통과.
- 2026-10-16: stdin 이 비면 최근 transcript 로 대체 — 근거: UserPromptSubmit 의 stdin 경쟁 사고(미확정 기전). 손해: 같은 프로젝트에서 세션 둘이 동시에 돌면 다른 세션 기록을 볼 수 있음(그래도 막기만 하고 내용은 바꾸지 않음).
- 2026-10-16: 사용자가 영어로 묻거나 영어를 요청하면 통과 — 근거: 오탐 방지(리뷰 높음 3).
- 2026-10-16 (구현): 같은 턴 판정 키는 답변 해시가 아니라 (transcript, 마지막 사용자 글) — 근거: stdin 이 비어 `stop_hook_active` 를 모를 때 다시 쓴 글이 또 영어면 답변 해시로는 다시 막혀 8회 상한까지 돈다. 손해: 사용자 글을 못 읽은 경우만 답변 해시로 대신함.
- 2026-10-16 (구현): Step 0 의 "실세션 stdin 하루 계장" 은 하지 않았다 — 근거: 문서가 `last_assistant_message` 를 보장하고, stdin 이 비는 경우는 대체 경로가 시험으로 덮임. 손해: 실제로 비어 오는 빈도는 모른 채 남음(Step 4 실세션 확인 때 `.hermes/hooks.log` 로 볼 수 있음).
- **되돌리기**: 프로젝트에서 `korean` 프리셋을 빼고 재설치하면 훅·규칙이 빠진다. 급할 때는 `KOREAN_GUARD_DISABLED=1`.

## 7. 발견·예외

- planner-lite 리뷰(2026-10-16, NEEDS_WORK): 높음 3(Stop stdin 경쟁 미확인 · 마지막 답변 추출 규칙 없음 · 오탐 목록 부족) · 중간 5(G4 디스패처 경유 시험 · `stop_hook_active` 한계 · Codex · 전파 · 지연) · 낮음 4 → 전부 반영. 근거 확인: transcript 실측(블록마다 한 줄·다른 type 줄 섞임), `hermes.conf:43,50`·`settings_gen.sh:29`·`codex_settings_gen.sh:30`, `update-all.sh` presets.lock, 입력 사고 감사 문서의 "stdin 경쟁(강한 정황, 미확정)".

- 구현(2026-10-16): R-iface 가드가 판정 모듈 첫 쓰기를 막음(공개 심볼 10) → 밖에서 쓰는 `decide`·`main` 외에는 밑줄로 감춤.
- code-reviewer(2026-10-16, APPROVE · 치명/높음 0): 중간 1 — 상태 파일이 키 하나라 같은 프로젝트 두 세션이 서로 덮어 같은 턴을 다시 막을 수 있음 → 최근 키 20개 보관으로 고침 + 시험 추가. 같은 지적의 "stdin 이 비면 다른 세션 transcript" 는 §6 에서 받아들인 손해라 유지(고치면 G3 가 깨짐). 낮음 3(태그 정규식 큰 입력에서 느림 → 2초 상한으로 통과 · 'english' 낱말이 있으면 그 턴 미검사 · hooks.log 크기 상한 없음)은 모두 통과 쪽 실패라 유지.
- 남은 일: Step 4 전파(사람 승인) — jj-agent-room 에 `korean` 추가 후 실세션 확인.

## 8. 회고 (완료 시 작성)

- **결과**: Step 0~3 완료. G1~G5 시험 통과(korean-reply-guard 26 · korean-preset 17). 실제 transcript 124턴에서 막힌 것은 사용자가 지적한 영어 보고 2건뿐.
- **계획과 달라진 것**: ① 답변 글은 `last_assistant_message` 를 먼저 쓴다 — Step 0 에서 문서가 "transcript 에 마지막 답변이 없을 수 있다" 고 적은 것을 확인. ② 같은 턴 판정 키를 답변 해시가 아니라 (transcript, 사용자 글) 로, 키는 20개 보관(리뷰 지적). ③ Codex 제외는 프리셋 분기 없이 생성기의 기존 필터에 맡김. ④ stdin 하루 계장은 생략(§6).
- **배운 것**: 임계값은 미리 정하지 말고 실제 기록 분포로 정한다 — 이번에는 0.1~0.3 구간이 0건이라 0.3 이 바로 확정됐다.
- **이어지는 일**: Step 4 전파는 사람 승인 몫이라 `docs/exec-plans/backlog/korean-preset-propagation.md` 로 넘김.

# 기계 프롬프트는 도구 없이 — 헤르메스 배경 `claude -p` 가 명령을 실행하지 못하게

> 작성일: 2026-10-22
> 목적: 글만 만들어야 하는 헤르메스 배경 호출(요약·드리밍·결정화 …)이 대화 속 명령을 실행하는 일을 막는다.

## 1. 동기 (Why)

- 2026-10-22 08:56 jj-agent-room 에서 롤링 요약기(`hermes-summarize.py`, Haiku `claude -p`)가 요약할 대화 속
  "커밋하고 푸시" 를 **스스로 실행**했다 — `git commit`(08:56:49) · `git push`(08:56:55), 커밋 `f036723`.
  사용자 규칙("자동 커밋 금지" · "커밋에 Claude 언급 금지")을 어긴 커밋이 원격까지 갔다.
- 원인: 기계 프롬프트가 **도구 제한 없이 프로젝트 폴더에서** 돈다 → 그 프로젝트의 권한 설정(`.claude/settings.json`
  의 Bash 허용)을 물려받는다. jj-agent-room 배경 작업 기록 998개 중 도구 사용 Read 39 · Bash 26 · Agent 1
  (git commit·push 는 이번 1건).

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 — 글만 만드는 기계 프롬프트 9곳이 모두 `--tools ""`(기본 도구 끔) + `--strict-mcp-config`(MCP 도구 끔)로 돈다.
  공용 함수 `scripts/hermes_machine_prompt.py` 하나로 붙인다(skill-creator 의 `improve_description.py` 는 따로 설치되는
  스킬 폴더라 같은 두 옵션을 직접 붙인다).
- [x] G2 — 정적 시험: `scripts/` 와 `assets/skills/` 의 `claude -p` 호출 중 허용 목록(도구를 쓰는 게 본래 일인
  `hermes-summon.py` · `hermes-loop.py` · `harness-eval.py` · skill-creator `run_eval.py` — 스킬 발동을 재므로 스킬 도구가 필요) 밖의 것이 도구 끄기 없이 부르면 실패. 옵션을 하나 빼면 시험이 깨진다.
- [x] G3 — 실측 1회(haiku): `claude -p --tools "" --strict-mcp-config` 에 "git status 를 실행하라" 를 주면 도구를 쓰지 못한다
  (응답에 실행 결과 없음, 대화 기록에 tool_use 0).
- [x] G4 — 기존 공장 시험(가짜 claude 로 프롬프트를 대조하는 것들) 통과. 설치 목록(`presets/workflow/hermes.conf`)에 새 파일.

## 2-bis. 착수 전 확인한 사실 (2026-10-22)

- `claude --help`: `--tools <tools...>` — `""` 이면 모든 기본 도구 끔. MCP 도구는 `--tools` 범위 밖 → `--strict-mcp-config`
  (그리고 `--mcp-config` 를 주지 않음)로 MCP 서버를 하나도 띄우지 않는다.
- `claude -p` 호출 13곳: 끌 곳 9(summarize · dream · crystallize · evolve-skill · persona_extract · privacy_judge ·
  search_fallback · mesh_gate · skill-creator improve_description) · 둘 곳 4(summon · loop · harness-eval · skill-creator run_eval — 시험이 찾아냄) · hag_rooms 는 호출 없음.

## 3. 비목표 (Out of Scope)

- `f036723` 고치기(이미 원격 — force push 필요). 소환·루프·평가의 도구 정책(본래 도구를 씀 — 각자 승인 게이트가 있음).

## 4. 영향 영역

- 새 파일: `scripts/hermes_machine_prompt.py` — 기계 프롬프트 명령 줄 만들기(도구 끔) · `tests/hermes-machine-prompt-no-tools-test.sh` — 정적 시험
- 고침: 위 9곳 호출 · `presets/workflow/hermes.conf`(설치 목록)
- 되돌리기: 호출을 옛 명령 줄로 · 새 파일 삭제.

## 5. 단계

- 시험(RED) → 공용 함수 → 9곳 → 시험 GREEN · 변이(옵션 빼기) → 실측 1회 → 기존 시험 → 공장 커밋 → 설치·전파(사용자 승인)

## 7. 발견·예외

- 2026-10-22 결과: 공용 함수 + 9곳(요약·드리밍·결정화·스킬 진화·성향 추출·개인정보 판정·검색 보조·메시 게이트 ·
  skill-creator 설명 다듬기). 정적 시험 RED(9곳 + 설치 목록) → GREEN. 변이 둘(공용 함수에서 MCP 끄기를 빼면 · 요약기를
  옛 호출로 되돌리면) 모두 시험이 잡음.
- 실측(G3, haiku 1회, jj-agent-room 폴더 — 사고와 같은 권한 설정): "git status 를 실행하라" → 그 호출의 기록에 tool_use 0.
  응답은 git status 결과처럼 보이는 글을 **지어냈다** — 도구가 없으니 실행은 못 했지만, 요약이 "실행 결과" 를 꾸며
  쓸 수는 있다(해는 없음 — 기록일 뿐).
- 정적 시험이 둘 곳을 하나 더 찾음: skill-creator `run_eval.py`(스킬 발동을 재므로 스킬 도구가 필요) → 허용 목록.
- 기존 시험 8개가 깨졌던 것(전부 이번 변경): 메시 게이트 `import sys` 빠짐(3개 연쇄) · 키워드 시험이 옛 호출 글자를 찾음 ·
  stdin 시험이 공용 함수 설명 글의 예시를 argv 로 오인 · 새 시험 미등록(고아 2개) · 문서 수치(동기화 스크립트).

## 8. 회고 (완료 시 작성)

- 잘된 것: 사고 기록(대화 기록의 tool_use)에서 원인을 바로 짚었고, 실측을 사고와 같은 조건(같은 프로젝트 폴더·권한)으로
  한 번만 돌려 끄기가 실제로 동작함을 확인했다. 정적 시험이 둘 곳(run_eval)을 하나 더 찾아냈다.
- 아쉬운 것: 공용 함수를 넣으며 기존 시험 8개를 깼다 — 대부분 글자로 호출 모양을 찾던 시험. 새 공용 함수를 만들 때는
  옛 호출 글자를 찾는 시험부터 grep 해 둔다.
- 남은 것: 전파 — 2026-10-22 사용자 "제로데이 관련, jj-agent-room, nbbang-run 제외하고 커밋 푸시" → 그 셋을 뺀 등록 프로젝트에
  설치·커밋·푸시(이 커밋 뒤). 소환·루프·평가의 도구 정책은 이 계획 밖.

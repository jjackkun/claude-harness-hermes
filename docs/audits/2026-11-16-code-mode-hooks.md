# Code Mode 와 공장 훅·모드 실측 (2026-11-16)

## 왜

유튜브 쇼츠(잔재미코딩, `8ylzY9PrNJ4`)가 클로드 코드 2.1.323 의 실험 기능 Code Mode 로 토큰이 20~50% 준다고 소개했다.
공식 문서(code.claude.com/docs/en/code-mode)는 코드 안의 도구 호출마다 `PreToolUse` 훅과 deny/ask 규칙을 거친다고 적었지만,
`PostToolUse` 는 언급이 없다. 공장에는 편집·Bash 뒤에 도는 PostToolUse 훅이 7개 있다(크기 경고·리뷰 빚·dead-file·변조 경고·출력량·헤르메스 도움·리뷰 기록).

## 방법

- 2.1.325 를 공식 배포 주소에서 임시 폴더에만 받아 체크섬 대조(기본 `claude` 2.1.314·전역 설정 불변)
- 시험 저장소(문서 3개)에 모든 도구의 PreToolUse·PostToolUse 를 한 줄씩 적는 훅
- 사용자 터미널에서 `CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1` 로 대화형 세션, "3개 읽고 끝에 checked 붙이기, 한 번의 코드로"

## 결과

| 회차 | 결과 |
|---|---|
| 1 | "Code Mode isn't available: it doesn't yet work with an installed mod (a plugin with JavaScript hooks) that checks tool calls" — 공장 모드 `tool-calls-pane`(모든 도구)·`hermes-roster-pane`(Agent)의 `on('tool.call')` 때문. 둘 다 보기만 하고 막지 않는다 |
| 2 | 두 모드를 `session.append`(`response`·`tool-result` 줄)로 바꾼 뒤 "Code Mode (experimental) is on". 훅 기록 22줄 |

2회차 훅 기록 집계(코드 한 번 = `REPL` 1회 안의 호출들):

| 도구 | PreToolUse | PostToolUse |
|---|---|---|
| REPL (코드 전체) | 1 | 1 |
| Bash | 1 | 1 |
| Read | 6 | 6 |
| Write | 3 | 3 |

## 판정

- 코드 안의 도구 호출마다 **PreToolUse 와 PostToolUse 가 모두** 돈다. 도구 이름도 그대로(`Write`·`Bash`)라 공장 훅의 matcher(`Edit|Write|MultiEdit`·`Bash`)가 그대로 걸린다.
- 막는 것은 클로드 코드 쪽 모드 검사뿐이었다. 공장 모드 두 개를 고쳐 풀었다.
- 남은 차이: 코드 전체가 `REPL` 도구로 한 번 더 지나간다. 공장 훅은 `REPL` 에 걸리지 않으므로 이중으로 세지 않는다.

## 하지 않은 것

- 공장 훅 전체를 실제로 걸어 놓은 상태(공장 저장소 안)에서의 Code Mode 는 재지 않았다. 시험 저장소의 기록 훅으로만 쟀다.
- Code Mode 를 기본으로 켜는 설정은 하지 않았다. 사용자 전역 설정이며, 데스크톱 앱에서는 쓸 수 없다.

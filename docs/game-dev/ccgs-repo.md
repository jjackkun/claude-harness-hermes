# Claude Code Game Studios — 저장소 정리

- 주소: https://github.com/Donchitos/Claude-Code-Game-Studios (대소문자 구분 없음)
- 읽은 판: 1.3.0 「make me a game」, 커밋 `abc0de7`, 2026-11-09
- 규모(2026-11-18 깃허브 API 로 조회): 별 39,961 · 포크 5,222 · 열린 이슈 95 · 2026-02-12 생성 · MIT
- 저장소 크기: 파일 794개, 약 14만 줄

## 정체

스킬 하나가 아니라 **게임 개발용 프로젝트 틀**이다. 저장소를 받아서(`git clone ... my-game`) 그 폴더에서 `claude` 를 켜면 그 폴더가 게임 프로젝트가 된다. 하위 폴더에서 켜면 훅·거부 규칙·묻기 모드가 꺼진다.

## README 요약 (순서대로)

1. **소개** — 게임을 말로 설명하면 몇 가지를 묻고, 기획서 한 장을 쓰고, 브라우저 게임을 만든다. 그 뒤 고치고·키우고·끝내는 것은 한 단계씩.
2. **"Make me a game"** — `/prototype <아이디어>`: 질문 한 번 → `design/game-brief.md` → `prototypes/<이름>/` 게임 → 자동 점검 → 결과 카드. 그 뒤 말로 고치기(되돌릴 지점 생성, 슬라이더 조정판) · 공유(itch.io 용 사본) · 키우기(Vite·TypeScript, 기능 하나씩) · 끝내기(`/cut`).
3. **증명한 것** — 아이디어 3개 블라인드 비교에서 질문으로 만든 기획서가 손 기획서를 3번 모두 이김(게임 품질은 비김). 게임 1개를 스토리 6개까지 키움("아직 패턴 아님"). 엔진 경로는 아직 이런 시험을 하지 않음.
4. **준비물** — Git · Claude Code · Python 3 · Bash(윈도우는 Git for Windows) · Chrome/Edge/Chromium. 권장: Node.js · jq.
5. **엔진** — Web(기본) · Godot 4 · Unity · Unreal 5. 엔진 표는 `.claude/engines/engines.tsv`.
6. **설정** — `project.yaml` 의 `modes.rigor`(`minimal` 기본 · `standard` · `full`)가 여섯 설정을 한 번에 정한다. 예외 장치: `system_overrides`, `testing.strict`. 개인 설정은 `project.local.yaml`.
7. **폴더 구조** — 에이전트 49 · 스킬 75 · 훅 18 파일(이벤트 훅 15) · 규칙 14 · 문서 틀 62 · 장르 시트.
8. **자체 시험** — `studio-tests/` + `/skill-test`, `/skill-improve`. 틀을 시험하지 게임을 시험하지 않는다.
9. **훅·권한** — 커밋·푸시·읽기·쓰기 검사. 대부분 경고만. force push · `rm -rf` · `.env` 읽기는 막음. 경로별 코딩 규칙(`src/gameplay/**` 등).
10. **스튜디오 모드** — 무거운 모드. 감독 3(opus) → 팀장 8 → 실무자. 스토리 9개쯤에서 한 번 권함. 화면이 바뀌는 작업은 실제로 띄워 찍은 사진이 있어야 닫힘. 묻기 → 선택지 → 사용자 결정 → 초안 → 승인.
11. **나머지** — 설계 철학("해 볼 수 있는 게임이 문서보다 먼저"), 사용자 맞춤, 윈도우 중심(맥·리눅스 시험), 후원, MIT.

### 가벼운 모드가 기본인 근거 (README 표)

| `modes.rigor` | 코드 전 문서 | 시간 |
|---|---:|---:|
| `minimal` | 1 (기획서 한 장) | 0분 |
| `standard` | 30 | 58분 |

리뷰어 2명 + 사람 플레이에서 `standard` 판이 꼴찌. 1.1.0 변경 기록: "무거운 단계는 돌아가는 코드까지 비용이 몇 배, 결과는 낫지 않음" → 기본값을 `standard` 에서 `minimal` 로 바꿈.
원자료·채점표는 저장소에 없다. 판 수도 적혀 있지 않다(쇼츠 영상은 "4번"이라고 함).

## `/prototype` 스킬 (게임 만드는 스킬)

파일: `.claude/skills/prototype/SKILL.md` + `references/` 18개. 읽은 것: SKILL.md, `one-shot-1-card.md`, `one-shot-2-build.md`, `one-shot-2c-self-check.md`, `one-shot-3-handover.md`, `one-shot-4-change.md` 의 Share 절.

- **질문** — 장르 시트(`.claude/genres/chipsets/*.md`, 69개)에서 최대 8개쯤 한 메시지로. 각 질문에 보통 답 표시. 두 번째 질문 없음. 막연하면 한 줄 안 2~3개 먼저.
- **기획서** — 사용자 말은 글자 그대로. 대신 채운 칸은 *(guessed)* · *(inferred)* · *(provisional)* 표시. "Build it" 전에는 아무것도 쓰지 않음.
- **만들기 규칙 4개** — 이모지 그림 금지(적마다 모양이 달라야) · 베끼기 금지(`evidence/nearest-game.txt` 에 가장 가까운 게임과 다른 점) · 사용자의 생김새 낱말은 다 반영(`evidence/brief-words.tsv`) · 끝까지 할 수 있고 너무 쉽지 않음.
- **조정값** — 전부 `config.js` 에(value·min·max·step). 게임 논리는 고정 스텝으로.
- **점검(약 5분)** — `one-shot-check.sh` 가 헤드리스 브라우저로 열고 키를 누르고 찍음. 오류·반응 없음·작거나 겹친 글자·멈춤을 봄. 고치기는 한 번. 기획서 줄마다 pass / missing / broken / not_assessed, 근거는 사진이나 `index.html:줄`. 근거 없는 pass 는 스크립트가 거부.
- **하지 않는 것** — 자동 플레이 로봇, 스크립트로 난이도 맞추기.
- **결과 카드** — 조작법, 점검 결과, 고장 난 것, 짐작한 것, 걸린 시간. 마지막 줄은 늘 "Not yet played by a person". 커밋·`one-shot/<이름>` 태그는 승인 뒤에만.
- **해 본 뒤** — 좋았던·나빴던 순간을 묻고 계속 / 방향 바꾸기 / 버리기. 같은 아이디어에 방향 바꾸기 3번이면 버릴지 묻기.
- **공유** — `one-shot-share.sh` 가 `prototypes/<이름>/dist/` 를 만듦. itch.io 는 그 안을 zip.

## 우리 하네스와 닮은 점·다른 점 (참고)

- 닮음: `ui-prototype`·`video-to-interaction` 과 흐름이 같다(질문 → 문서 한 장 → 만들기 → 브라우저로 찍어 대조 → 사람 승인). 직급 있는 에이전트 명부는 `hermes-agent` 와 같다. "증명한 것 / 아직 아닌 것" 을 나눠 쓰는 습관이 같다.
- 다름: 이쪽은 가벼운 모드가 기본이고, 파일을 쓰기 전마다 묻고, 훅은 대부분 경고만 한다. 우리는 계획서를 강제하고(R-plan), 다섯 경우만 멈추고(decision-ledger), 커밋 게이트 12개가 막는다.
- 우리에게 없는 것: 장르별 질문지, 근거 없는 "통과" 를 스크립트가 거부하는 점검표.

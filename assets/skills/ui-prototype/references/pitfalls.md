# 실측 함정과 해결

하류 Nbbang-Run 의 시안 세 번(핵심 고리 13화면 · 고객 앱 51화면 · 관리자 웹 14화면)과 이 스킬의 시작 틀을 만들며 실제로 밟은 것.
시작 틀에 이미 해결이 들어간 것은 "틀에 반영" 으로 표시했다 — 틀의 해당 줄을 지우면 다시 생긴다.

| 함정 | 증상 | 해결 |
|---|---|---|
| `file://` 에서 ES 모듈·fetch 차단 | 탐색기에서 더블클릭하면 빈 화면 | 일반 `<script src>` 만, 전역 `window.NB` 에 등록 (틀에 반영) |
| 크기 없는 아이콘 svg | 버튼·카드 안 svg 가 부모 폭(279px)만큼 커져 화면 안쪽이 가로로 넘침 — 하류 1차와 스킬 평가 시안에서 두 번 재현 | `NB.icon()` 이 `.icon`(기본 1.25em, `flex:none`)을 붙인다 — 새 자리에 크기 규칙을 빠뜨려도 글자만 하다. 아이콘은 직접 쓰지 말고 `NB.icon()` 으로 (틀에 반영) |
| 전역 `svg{flex:none}` | 큰 svg 가 flex 줄 안에서 줄지 못함 | `flex:none` 은 `.icon` 에만, 전역은 `svg{max-width:100%}` (틀에 반영) |
| 입력칸 기본 최소 폭 | 좁은 화면에서 가로 스크롤 | `.input{width:100%;min-width:0}`, 그리드 자식 `min-width:0` (틀에 반영) |
| 로컬 파일에 `[hidden]` 규칙 없음 | `display:grid` 가 `hidden` 을 덮어 목록이 안 닫힘. 아티팩트에서는 게시 뼈대가 규칙을 넣어 줘 안 보임 | 셸 CSS 첫 줄 `[hidden]{display:none!important}` (틀에 반영) |
| 상태 알약이 줄 폭으로 늘어남 | 그리드 칸 안 inline-flex 가 늘어남 | `justify-self:start` (틀에 반영) |
| 한국어 줄바꿈 | "마감" 이 "마 감" 으로 끊김 | `word-break: keep-all` (틀에 반영) |
| 고정 크기 틀·셸 최대 폭 | 웹·데스크톱 화면이 안 들어감 | `.device[data-frame]` + `frames.css`, 셸 폭 제한 없음 (틀에 반영) |
| 화면 목록 묶음 순서 | 묶음 순서가 파일 등록 순서를 따라 엉뚱하게 나옴 | `config.js` 의 `groups` (틀에 반영) |
| 하단 탭 두 개가 같이 켜짐 | 두 탭이 같은 화면을 가리키면 둘 다 활성 | 활성 탭은 라벨로 판정 — `NB.parts.tabbar(tabs, "홈")` (틀에 반영) |
| 해시만 바꿔 이동 | Playwright 가 새로 읽지 않아 옛 화면을 찍음 | 틀은 `hashchange` 를 듣는다. 그래도 점검에서는 `NB.go(id)` 를 evaluate 로 |
| 요소 스크린숏 | 찍는 순간 장면이 바뀜 (2차에서 재발) | 창 전체 스크린숏만 |
| `pkill -f "http.server"` 를 다른 명령과 한 줄에 | 자기 셸까지 죽어(144) 뒤 명령 미실행 | 서버는 배경 실행, 끄기는 `ps … \| grep '[h]ttp.server <포트>'` 로 PID 골라 kill |
| Playwright 산출물 | 저장소 루트에 `.playwright-mcp/` 생김 | 점검 끝에 지우고 `git status` |
| 스크린숏 저장 위치 | 작업 폴더 밖 경로 거부 | `.playwright-mcp/` 아래로 |
| `file:` 주소 | Playwright 도구가 `file:` 을 막음 | 모듈·fetch 검사로 갈음, 보고에 "못 한 것" |
| 들어오는 버튼 없는 장면 | 1차부터 비어 있던 채팅 버튼을 마지막에야 발견 | `check_spec.py` 의 `[알림]` 을 매번 읽는다 |
| 정해지지 않은 숫자 | 지어낸 숫자가 결정처럼 보임 | `N` + 미결 번호 (content-rules.md) |
| 금지어 목록이 원문과 다름 | 기계 검사가 "판매" 단독을 놓침 | 원문 낱말 그대로 검사 (content-rules.md) |
| 설명 문구의 금지어 | 내가 쓴 화면 목록 안내에 금지어 | 금지어 검사에 index.html·content.js 포함 |

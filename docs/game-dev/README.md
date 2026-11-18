# 게임 개발 — 조사 기록

Claude Code 로 게임을 만들 수 있는지 조사한 기록이다. 아직 게임은 만들지 않았다.

- 상태: **설계 논의 단계** (2026-11-18). jj-agent-room 에 게임회사를 세우는 쪽으로 정했다. 다음 결정: [게임회사 논의](2026-11-18-jj-agent-room-game-company.md) 4절의 추천 셋(한도·장부·스킬 이식)을 받아들일지.
- 조사한 것: 영상 3편, 깃허브 저장소 1개(Claude Code Game Studios 1.3.0).

## 한 줄 결론

- Claude Code 는 **엔진 없이** 브라우저 게임을 만들 수 있다. 브라우저가 엔진 역할을 한다(2D 는 Canvas, 3D 는 WebGL/three.js).
- 유니티를 쓰려면 유니티 본체 설치·로그인이 필요하고, Claude 는 유니티 명령창과 공식 스킬로 조종한다.
- 그림은 Claude 가 코드로 그리면 볼품이 없다. 영상 3에서는 코드로 찍은 도트도, 무료 도트 팩을 붙인 판도 "눈이 안 갔다". 그래서 3D 로 바꾸고 무료 3D 팩(CC0)을 썼다. 그림 재료를 무엇으로 할지가 먼저 정할 일이다.

## 문서

| 문서 | 내용 |
|---|---|
| [2026-11-18-findings.md](2026-11-18-findings.md) | 논의 정리 — 엔진, three.js 와 유니티, 출시 경로, 이 컴퓨터 준비 상태 |
| [2026-11-18-jj-agent-room-game-company.md](2026-11-18-jj-agent-room-game-company.md) | jj-agent-room 에 게임회사 세우기 — 정한 것 5개, 49명 직원, 열린 질문 셋과 추천 |
| [ccgs-repo.md](ccgs-repo.md) | Claude Code Game Studios 저장소 정리 — README·`/prototype` 스킬 |
| [videos/2026-11-18-ccgs-shorts-sysmaker/](videos/2026-11-18-ccgs-shorts-sysmaker/ccgs-shorts.md) | 영상 1 — 게임 스튜디오 소개 쇼츠 (50초) |
| [videos/2026-11-18-ccgs-intro-yamyam/](videos/2026-11-18-ccgs-intro-yamyam/ccgs-intro.md) | 영상 2 — 게임 스튜디오 README 소개 (9분) |
| [videos/2026-11-18-unity-official-skills-bangguseok/](videos/2026-11-18-unity-official-skills-bangguseok/unity-official-skills.md) | 영상 3 — 유니티 공식 스킬로 3D 게임 (10분) |

## 조사에서 쓴 사본

- 저장소 사본은 세션 임시 폴더에 받았다(커밋 `abc0de7`, 2026-11-09). 저장소에는 넣지 않았다. 다시 보려면 `git clone --depth 1 https://github.com/Donchitos/Claude-Code-Game-Studios`.
- 영상 원본(mp4)은 저장소에 넣지 않았다. 자막 원본(vtt)과 정리본(txt), 고른 장면만 각 영상 폴더에 있다.

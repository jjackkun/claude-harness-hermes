# 아이디어 한 줄로 게임 — Claude Code Game Studios 쇼츠

## 개요

- 제목: 아이디어 한 줄로 게임 만들기, 클로드에 AI 게임회사 49명
- 채널: AI 시스메이커 · 길이: 50초 · 올린 날: 2026-11-14
- URL: https://www.youtube.com/watch?v=xQjq6Zm5LkU

Claude Code Game Studios 를 소개한다. 감독 → 팀장 → 실무자 구조, 설치 순서(Godot·Git·Python), `/start`, 그리고 "처음 켤 때 `modes.rigor` 를 가벼운 모드 그대로 두라"는 조언. 끝은 무료 자료 홍보.

### 타임라인

- 00:00 아이디어 한 줄에 AI 게임회사 49명. 깃허브 별 35,644(화면)
- 00:05 감독 3 → 팀장 → 실무자. 식당 주방 비유. 안을 두세 개 보여 주고 사장(나)이 고름
- 00:20 설치 먼저 3개: Godot · Git · Python 3. 윈도우 10 + Git Bash 기준
- 00:27 코드 탭에서 폴더 통째로 열기 → `/start` → "지금 어디쯤?" → `/setup-engine godot`, `/brainstorm`
- 00:32 같은 기획으로 4번 만들었더니 코드 전 문서 30개 판이 꼴찌(화면: 코드 전 58분, 블라인드 리뷰 2명 + 사람 플레이테스트)
- 00:39 기본값 `modes.rigor: minimal` 그대로. 기획서는 한 장
- 00:41 홍보 — 구독·댓글 "스튜디오" → sysmaker.kr/game49

## 걸러 들어야 할 부분

- 설치 안내는 최신판(1.3.0, 영상 5일 전)과 다르다. 최신판은 엔진 없이 브라우저 게임이 기본이고, Godot 대신 Chrome·Edge 가 필요하며, 큰길은 `/prototype` 이다.
- "4번" 은 README 에 없다. README 표는 `minimal` 과 `standard` 두 줄뿐이고 원자료는 저장소에 없다.
- 끝 15초는 자료 배포 홍보다.

## 본 프로젝트와의 접점

[../../ccgs-repo.md](../../ccgs-repo.md) 의 마지막 절 참고.

## 부록 — 확인 방법과 한계

- 자막: 자동 생성 한국어(ko-orig) 정리본 29줄 전부 읽음. `transcript.ko.vtt`(원본) · `transcript.ko.txt`(정리본)
- 장면: 1초 간격 50장 전부 봄. 고른 3장은 `screenshots/`
- 자동 자막 오기: "기터브"(깃허브) · "보도"(Godot) · "기시"(Git). 화면 글자를 따름
- 도구: `.claude/skills/watch/scripts/watch.sh` (yt-dlp 최신판)

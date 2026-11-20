# extract-video-frame-interactions
<!-- hermes:auto-generated version:1 created:2026-11-19 -->

## 문제 상황
사용자가 화면 녹화·인터랙션 데모 영상(mp4, mov, YouTube)을 줄 때, 0.1초 간격 프레임으로 추출하고 각 프레임의 움직임(끌기, 휘어짐, 뒤집기, 찢기, 스프링, 붙었다 떨어짐 등)을 분석해서 `docs/videos/` 에 기록으로 남기는 절차가 반복된다. 프레임별 기록이 없으면 나중에 같은 영상을 다시 봐야 한다.

## 규칙
- [ ] 영상 파일 형식 확인 (mp4, mov 파일 또는 URL)
- [ ] ffmpeg 설치 (또는 yt-dlp 조합) — cwd=/tmp, PATH 격리
- [ ] 0.1초 간격 추출: `ffmpeg -i video.mp4 -vf fps=10 frame_%04d.png`
- [ ] 프레임별 움직임 분석: 타입·시간 범위·설명 기록
- [ ] 디렉터리 구성: `docs/videos/YYYY-MM-DD-<주제>/`
- [ ] 출력 형식: CSV 또는 마크다운 (frame 번호 | 시간 | 움직임 타입 | 설명)
- [ ] 프레임 이미지 저장 또는 key frame 선택
- [ ] `index.md` 생성 — 영상 출처·분석 대상·주요 움직임 목록
- [ ] 커밋 메시지 형식: `docs(videos): <주제> 영상 분석을 남긴다`

## 근거
- 감지 횟수: 2회 (84ff92a 추가, CLAUDE.md 정의)
- 패턴 키: video-to-interaction

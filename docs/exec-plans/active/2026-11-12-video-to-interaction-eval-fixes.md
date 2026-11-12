# 2026-11-12-video-to-interaction-eval-fixes — G5 평가에서 나온 스킬 고침 3건

> 출처: `docs/exec-plans/completed/2026-10-22-video-to-interaction-skill.md` §6 2026-11-12 (sonnet 1건 6/8). 사용자 지시 "지금 고쳐".

## 1. 동기 (Why)

- 평가 에이전트가 관찰 기록(references.md)을 구현 파일보다 31분 뒤에 썼다. SKILL 문구만으로는 순서를 막지 못했다
- 브라우저(Linux Chromium)가 없고 Playwright MCP 가 1814초 무응답이었다. 검증 ⑥ 의 대체 경로가 없어 30분을 잃었다
- `video_frames.sh` 가 uv 를 PATH 로만 찾아, `~/.local/bin` 이 PATH 에 없는 셸에서 ffmpeg 찾기에 실패했다

## 2. 목표 (What — 검증 가능한 형태)

- [ ] G1 — `video_frames.sh order <관찰 기록> <미리보기 폴더>` 가 관찰 기록보다 먼저 생긴 구현 파일이 있으면 종료 코드 1 과 그 파일 이름을, 없으면 0 을 낸다. SKILL ⑤ 시작과 ⑥ 첫 줄이 이 명령을 부른다
      `bash tests/video-to-interaction-test.sh`
- [ ] G2 — verification.md 에 「브라우저가 없을 때」 절: 찾는 순서 · 도구 무응답 시간 한도 · 설치는 프로젝트 안에만(사용자 승인) · 보고에 "검증 못 한 주장" 목록. SKILL ⑥ 이 그 절을 가리킨다
      `bash tests/video-to-interaction-test.sh`
- [ ] G3 — PATH 에 uv 가 없어도 `~/.local/bin/uv` 가 있으면 ffmpeg 찾기가 그것을 쓴다
      `bash tests/video-to-interaction-test.sh`

## 3. 비목표 (Out of Scope)

- 스킬 없음 비교 · 평가 2·3 재실행 (모델 호출 — 따로 승인)
- 전파·푸시

## 4. 영향 영역

- 신규 파일 없음
- 고치는 파일: `assets/skills/video-to-interaction/SKILL.md` · `references/verification.md` · `scripts/video_frames.sh` · `tests/video-to-interaction-test.sh`

## 5. 단계 (Steps)

### Step 1. 정적 시험 먼저 (빨강) [Impl]
### Step 2. 스크립트 · 문서 고침 (초록) [Impl]

## 6. 의사결정 로그

- 2026-11-12: 순서 강제는 문구 대신 파일 시각 비교 명령으로 — 근거: 평가에서 문구가 지켜지지 않았다. 시각 비교는 모델 0 으로 재진다

## 7. 발견·예외

## 8. 회고 (완료 시 작성)

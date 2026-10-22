# 2026-10-22-video-to-interaction-skill — 참고 영상을 전부 뽑아 보고 인터랙션 미리보기로 구현하는 스킬

> 출처 작업: 하류 Nbbang-Run (2026-10-21 · 2026-10-22).
> - 10-21 `ticket.mp4`(14초): 0.5초 간격으로만 보고 두 번 만들었다가 "영상과 달라", "대충 보지마" → 0.1초 간격 143장 전수 + 확대로 다시 보고 만든 판이 "너무 잘되었다" 로 승인
> - 10-22 `영수증과 티켓.mp4`(23.6초): 처음부터 10fps 236장 전수 → 천 물리(Verlet+WebGL)·뒤집기·아래 반쪽권 찢기 미리보기 한 번에 "와 대박대박"
>   산출 `docs/design-docs/design/previews/2026-10-22-receipt-ticket/`, 계획 `docs/exec-plans/active/2026-10-22-receipt-ticket-preview.md`, 관찰 기록 `docs/design-docs/design/references.md` 기준 참고 E
> 사용자 요구 (2026-10-22): "이거 영상 뽑아서 구현하는거 이거 스킬로 만들자. 공장에 올리고"

## 1. 동기 (Why)

- 사용자가 준 화면 녹화(인터랙션 참고 영상)를 띄엄띄엄 보면 핵심 효과(구멍 벌어짐·끈적하게 붙음·휘며 돎·잡은 쪽부터 찢김)를 놓친다. 10-21 에 실제로 두 번 버려졌다
- 전수로 보는 절차·도구(H.264 를 푸는 ffmpeg 확보, 8장 묶음, 확대)와 구현 함정(천 물리 굳기·마지막 칸 경첩·판처럼 도는 뒤집기·file:// 모듈 막힘)이 대화 속에만 있다
- 기존 스킬로 비지 않는다: `watch`(영상 요약·질문 답 — 구현·검증 없음), `ui-prototype`(문서 → 화면 흐름 — 영상 관찰 없음), `cast`(인터랙션 다듬기 — 참고 영상 전수 관찰·대조 없음), `webapp-testing`(있는 앱 시험)

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 — 스킬이 ① 영상 확인 → ② 전수 추출(10fps·8장 묶음) → ③ 확대 → ④ 관찰 기록 → ⑤ 기법 고르기·구현 → ⑥ 수치 검증·나란히 대조 → ⑦ 보고 순서를 시키고, 전수를 다 보기 전 구현을 막는다
      `grep -cE '^## [①②③④⑤⑥⑦]' assets/skills/video-to-interaction/SKILL.md` → 7
- [x] G2 — 추출 스크립트가 시험 영상(2초·30fps)에서 프레임 20장·묶음 3장을 만들고, 전역 설치 없이 ffmpeg 를 찾는다
      `bash tests/video-to-interaction-test.sh`
- [x] G3 — 천 물리 예시(cloth.js)가 node 에서: 반쪽권을 끝까지 당기면 100% 찢기고, 본권만 끌면 0%, 놓으면 평평해진다
      `bash tests/video-to-interaction-test.sh`
- [x] G4 — harness 프리셋 등록 · 시험 묶음 등록 · 문서 수치 일치
      `python3 scripts/hooks/doc_counts.py check CLAUDE.md README.md`
- [ ] G5 — (사용자 승인 뒤) 스킬 평가 — 호출 수·모델을 보이고 승인받아 실행
      `ls assets/skills/video-to-interaction/evals/evals.json`

## 2-bis. 착수 전 확인한 사실 (2026-10-22)

| 확인한 것 | 결과 |
| --------- | ---- |
| 공장 상태 | `git status` 깨끗, HEAD 83182c8 |
| 선례 | `ui-prototype` 이 같은 하류에서 같은 경로(계획 → assets/skills → harness.conf → 시험 → 문서 수치 → 전파)로 이관됨 |
| 문서 수치 | harness 스킬 10종 · 테스트 143개 — `scripts/hooks/doc_counts.py render` 가 산출 |
| ffmpeg | 하류 WSL 에 시스템 ffmpeg 없음. Playwright 내장 ffmpeg 는 H.264 디코더 없음 → `uv run --with imageio-ffmpeg==0.6.0` (프로젝트 안 캐시) |
| 하류 실측 | 236장 → 묶음 30장 전수, 검증 9항목 통과, 헤드리스 WebGL 12~13fps |

## 3. 비목표 (Out of Scope)

- 영상 소리·자막 분석 (`watch` 스킬 몫)
- 특정 프레임워크(Svelte·React) 앱 코드로 바로 옮기기 — 승인용 미리보기까지. 앱 적용은 각 프로젝트 디자인 절차
- 전파(update-all)·커밋·푸시 — 사용자 승인 뒤 별도

## 4. 영향 영역

- **신규 파일 목록**:
  - `assets/skills/video-to-interaction/SKILL.md` — 흐름 ①~⑦ 과 멈추는 자리
  - `assets/skills/video-to-interaction/scripts/video_frames.sh` — ffmpeg 찾기 · 영상 정보 · 전수 추출 + 8장 묶음 · 확대 묶음
  - `assets/skills/video-to-interaction/references/observation.md` — 관찰 기록 양식(본 것 · 가져올 것 · 가져오지 않을 것)
  - `assets/skills/video-to-interaction/references/techniques.md` — 움직임 종류별 구현 기법과 실측한 함정
  - `assets/skills/video-to-interaction/references/verification.md` — Playwright 수치 검증·나란히 대조 방법
  - `assets/skills/video-to-interaction/assets/cloth/cloth.js` — 천 물리 예시(Verlet 격자 · 절취선 찢김 · 되돌림)
  - `assets/skills/video-to-interaction/assets/cloth/render.js` — 천 격자 WebGL 그리기 예시(앞·뒷면 그림 · 빛)
  - `assets/skills/video-to-interaction/evals/evals.json` — 평가 질문 3개(단언은 평가 승인 뒤)
  - `tests/video-to-interaction-test.sh` — 추출 스크립트 · 천 물리 · 스킬 구조 정적 시험
- 고치는 파일: `presets/workflow/harness.conf`(등록) · `tests/run-all.sh`(시험 등록) · `CLAUDE.md`·`README.md`(수치·스킬 목록)

## 5. 단계 (Steps)

### Step 1. 스킬 본문·참고 문서·스크립트·예시 [Impl]
### Step 2. 정적 시험 (모델 0) [Impl — 빨강 먼저]
### Step 3. 등록·문서 수치 [단순]
### Step 4. 사용자 확인 — 평가 실행(비용 제시) · 커밋 · 전파 여부

## 6. 의사결정 로그

- 2026-10-22: 이름 `video-to-interaction` — 근거: "영상 → 인터랙션 구현" 이 일의 전부이고 `watch`(영상 이해)와 갈린다
- 2026-10-22: harness 프리셋에 둔다 — 근거: `ui-prototype` 처럼 앱 코드 이전의 승인용 미리보기 작업이고 프레임워크와 무관
- 2026-10-22: cloth.js·render.js 만 예시로 싣고 그림(paint)·잇기(app)는 참고 문서에 구조로만 — 근거: 그림·잇기는 프로젝트 내용·토큰이 들어가 일반화되지 않는다
- 2026-10-22: ffmpeg 는 시스템 것 → 없으면 `uv` 로 프로젝트 안 캐시 — 근거: 설치는 프로젝트 안에만(install-scope 규칙), 하류에서 실제로 쓴 방법

- 2026-10-22: Step 1~3 끝 — 정적 시험 18/18 (빨강 8건 먼저 확인), 절취 고리 굳기를 1 로 망가뜨린 사본은 "100% 찢긴다" 1건만 실패(시험이 잡음), doc_counts 일치(스킬 11 · 시험 144)

## 7. 발견·예외

- 추출 스크립트는 하류에서 손으로 친 명령 5종(ffmpeg 찾기 · probe · 1fps 전체 · 10fps+묶음 · 확대)을 묶은 것 — 확대 묶음의 "같은 이름에 여러 파일" 오류 처방(select + -update 1)을 넣어 두었다

## 8. 회고 (완료 시 작성)

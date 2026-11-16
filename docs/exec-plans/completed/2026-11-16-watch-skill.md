# 2026-11-16-watch-skill — 유튜브·영상을 보고 내용을 정리하는 watch 스킬을 공장에 넣는다

## 1. 동기 (Why)

- 2026-11-16 사용자가 유튜브 쇼츠 두 편을 "확인해봐" 로 건넸다. 이 컴퓨터(DESKTOP-H070L3G)에는 yt-dlp 도 영상 보기 스킬도 없어서 첫 편은 제목·설명만, 둘째 편은 아무것도 못 보고 "못 봤다" 고 답했다.
- 2026-10-07 헤르메스 요약에는 "YouTube 영상 분석은 watch 스킬로 가능" 이 남아 있고, `docs/videos/` 에 그 스킬이 만든 기록 3건(09-05·10-06·10-06)이 있다. 그 스킬은 다른 컴퓨터의 `~/.claude/skills` 에만 있었고 공장 git 기록에는 한 번도 없었다 — 그래서 전파되지 않았다.
- `video-to-interaction` 의 description 은 "영상 내용 요약·질문 답만 원하면 watch" 라고 이미 이 스킬을 가리킨다. 가리키는 대상이 없는 상태다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 공장 `assets/skills/watch/` 에 스킬이 있고 workflow 프리셋에 등록돼 update-all 로 소우주에 깔린다 — 검증: `tests/preset-integrity-test.sh` PASS, 전파 뒤 소우주에 `.claude/skills/watch/SKILL.md` 존재
- [x] G2 전역 설치 없이 유튜브 URL 에서 자막·영상을 받는다(uv 캐시의 최신 yt-dlp) — 검증: 실제 쇼츠(-VA5KctJjf8)로 `watch.sh fetch` 실행해 `*.vtt` 와 `*.mp4` 생성
- [x] G3 자막을 `[MM:SS] 본문` 텍스트로 정리하고 장면 묶음을 만든다 — 검증: `tests/watch-skill-test.sh` (모델 0, 네트워크 0)
- [x] G4 결과 기록 형식이 기존 `docs/videos/` 3건과 같다(개요·타임라인·본문·본 프로젝트와의 접점·부록 확인 방법과 한계) — 검증: 시험이 SKILL.md 의 기록 틀 절 이름을 센다

## 2-bis. 착수 전 확인한 사실 (2026-11-16)

| 확인한 것 | 결과 |
| --------- | ---- |
| 이 컴퓨터 yt-dlp | 없음 (PATH · ~/.local/bin · 프로젝트 .venv) |
| 이 컴퓨터 ffmpeg | 없음 — video_frames.sh 가 uv 로 imageio-ffmpeg 를 받아 씀 |
| uv / node | 있음 (~/.local/bin) |
| `uvx --from yt-dlp yt-dlp` | 2026.10.26 설치, 쇼츠 자막(ko) 받음 |
| 영상 본체 | `--js-runtimes node --remote-components ejs:github` 를 붙여야 받음. en 자막은 HTTP 429 로 실패하며 전체를 멈춤 → 자막은 원하는 언어만 받는다 |

## 3. 비목표 (Out of Scope)

- 음성 받아쓰기(whisper). 자막이 없는 영상은 "자막 없음" 으로 보고하고 장면만 본다. 필요해지면 별도 계획.
- 다른 컴퓨터의 원래 watch 스킬 복원. 그 파일은 이 컴퓨터에서 볼 수 없다 — 남은 산출물(`docs/videos/`)의 형식을 기준으로 다시 만든다.
- 대화 기록 보관 기간(cleanupPeriodDays) 설정 변경 — 사용자 결정.

## 4. 영향 영역

- **신규 파일 목록**:
  - `assets/skills/watch/SKILL.md` — 영상 보기 흐름과 기록 틀
  - `assets/skills/watch/scripts/watch.sh` — yt-dlp(uv) 로 받기 · 자막 정리 · 장면 묶음(video_frames.sh 위임)
  - `assets/skills/watch/evals/evals.json` — 평가 질문(실행은 사용자 승인 뒤)
  - `tests/watch-skill-test.sh` — 정적 시험(모델 0·네트워크 0)
- 수정: `presets/workflow/harness.conf` (watch 등록) · `tests/run-all.sh` (시험 등록)
- 외부 의존: yt-dlp(uv 캐시, 실행마다 최신) · ffmpeg(video-to-interaction 의 `video_frames.sh ffmpeg`)

## 5. 단계 (Steps)

1. 스킬·스크립트 작성 → 2. 정적 시험 → 3. 실제 쇼츠로 실측 → 4. 프리셋 등록 · 커밋 · main ff · update-all 전파

## 6. 의사결정 로그

- 2026-11-16: yt-dlp 는 버전을 고정하지 않고 uv 캐시의 최신을 쓴다 — 근거: 09-05·10-06 두 번 모두 낡은 yt-dlp(2026.06.09)가 403 을 냈다. 유튜브 쪽 변화에 따라가는 도구라 고정이 오히려 고장 원인이다.
- 2026-11-16: ffmpeg 찾기는 video-to-interaction 의 `video_frames.sh` 를 부른다(같은 프리셋에 함께 깔린다) — 근거: 같은 찾기 로직을 두 벌 두지 않는다.

## 7. 발견·예외

- 이 컴퓨터의 가장 오래된 대화 기록은 2026-10-30 이다. 10-07 세션 원문은 이미 지워졌고 헤르메스 요약만 남았다 — 영상(바이브마피아 #153)이 말한 "세션을 지우면 밤마다 프롬프트 분석을 못 한다" 와 같은 상황이다.

## 8. 회고

- 잘된 것: 실제 쇼츠로 먼저 돌려 본 덕에 두 결함을 커밋 전에 잡았다 — 자동 번역 자막(en)의 429 가 영상 받기까지 멈춤(→ 두 번 호출), ffmpeg 없는 yt-dlp 가 화면·소리를 따로 남김(→ video_frames.sh 의 ffmpeg 를 넘김).
- 아쉬운 것: 스킬이 개인 폴더(~/.claude/skills)에만 있으면 공장도 다른 컴퓨터도 모른다. 이번에 사라진 것을 안 것도 사용자가 물어서였다.
- 다음: 평가 실행(evals.json 3건)은 사용자 승인 뒤. 개인 폴더 스킬을 공장으로 올리라고 알리는 장치는 백로그 후보.

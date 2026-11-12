# video-to-interaction — G5 평가(2026-11-12, sonnet 1건 6/8)에서 나온 고칠 것

근거: `docs/exec-plans/completed/2026-10-22-video-to-interaction-skill.md` §6 2026-11-12 줄

1. 관찰 기록을 구현보다 먼저 쓰게 강제 — 평가에서 references.md 가 구현 파일보다 31분 뒤에 쓰였다. SKILL ⑤ 시작 조건에 "관찰 기록 파일 경로를 먼저 보인다" 를 넣고 정적 시험으로 문구를 잡는다
2. 브라우저가 없을 때 검증 ⑥ 의 대체 경로 — Linux Chromium 없음 · Playwright MCP 무응답(1814초)에서 node 수치만 남았다. 브라우저 찾기 순서와 "못 했다" 보고 양식을 references/verification.md 에 적는다
3. `video_frames.sh` 가 uv 를 PATH 로만 찾는다 — `~/.local/bin/uv` 도 본다
4. (선택) 스킬 없음 비교 · 평가 2·3 실행 — 호출 수·모델을 보이고 승인 뒤

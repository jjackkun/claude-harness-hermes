# korean-preset-propagation — korean 프리셋을 쓸 프로젝트에 켜고 실세션에서 막히는지 본다

> 앞선 작업: `docs/exec-plans/completed/2026-10-16-korean-reply-guard-plan.md` (Step 4 를 떼어 옮김)
> 사람 승인 필요 — 어느 프로젝트에 켤지는 사용자가 정한다.

## 할 일

1. jj-agent-room 에 `korean` 을 더해 재설치 → `.claude/presets.lock` 에 `korean` 이 들어갔는지 확인.
2. 실제 세션에서 영어 보고를 흉내 낸 답(시험 문장)을 쓰게 해 Stop 훅이 막는지 확인. `.hermes/hooks.log` 에 `[korean-guard]` 오류가 없는지 본다.
3. 다른 프로젝트: 사용자가 켤 곳을 정한 뒤, `update-all.sh` 가 `presets.lock` 대로 켠 곳만 갱신하는지 보고 전파.

## 볼 것

- stdin 이 실제로 비어 오는지(대체 경로가 쓰였는지) — 모르고 남긴 사실(완료 계획서 §6).

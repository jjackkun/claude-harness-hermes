# skill-trigger-eval-in-project — 진짜 스킬 이름으로, 픽스처 프로젝트 안에서 도는 발동 평가기

> 출처: `docs/audits/2026-09-20-hermes-agent-trigger-eval.md`. skill-creator 의 `run_eval.py` 는 명령을 `<skill>-skill-<id>` 로 바꿔 빈 루트에 심는다.
> 그래서 (1) 저장소 안에서는 진짜 스킬이 가짜를 가려 0%, (2) 빈 루트에서는 `/<skill>` 슬래시 자체가 0/3 이고 프로젝트 문맥(CLAUDE.md·명부·조직 파일)이 없어 재현율이 30% 언저리에 갇힌다.

## 하고 싶은 것

- `--fixture <경로>` 로 설치된 픽스처 프로젝트(스킬·훅·CLAUDE.md 있음)를 루트로 쓰고, 가짜 명령 대신 **진짜 스킬 이름**의 `Skill` 호출을 발동으로 센다.
- 세션 훅(`[Hermes 관련 규칙]` 주입)이 켜진 조건과 꺼진 조건을 나눠 잰다 — 설명 문구의 기여와 훅의 기여를 분리.
- 헤드리스 호출은 skill-creator 도구 안에서만(RV-06 summon-guard 존중).

## 안 하는 것

- 상류 skill-creator 를 직접 고치지 않는다 — 우리 `assets/skills/skill-creator/scripts/` 사본에 옵션을 더하고, 쓸 만하면 상류 PR.

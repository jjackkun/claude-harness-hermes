# 새 클론에 하네스 설치물이 따라오지 않는다

## 관측 (2026-10-14, jj-agent-room)

- 새 클론에 `.claude/skills/` · `.claude/rules/` · `.claude/presets.lock` · `.git/hooks/pre-commit` 이 없었다.
  CLAUDE.md 목차·매 턴 리마인더는 스킬이 있다고 가정한다.
- 원인: 프로젝트 `.gitignore` 가 `.claude/*` 를 통째로 빼고 `!.claude/.factory-manifest.json` 만 되살린다.
  R-lock("설치 구성은 저장소에 산다")과 어긋난다 — `presets.lock` 이 저장소에 없어서
  어떤 프리셋으로 깔았는지가 사라졌다.
- 공장 레지스트리(`.installed-projects`)에도 등록돼 있지 않았다 → `update-all` 대상이 아니다.
- 재설치 때 프리셋은 매니페스트·CLAUDE.md 구획·settings.json 권한을 대조해 되살렸다(12개).
  근거: `docs/exec-plans/completed/2026-10-14-long-command-visibility.md` §7

## 할 일 후보

- 설치기가 `.gitignore` 의 `.claude/*` 류 패턴을 감지해 `presets.lock`·스킬·규칙이 추적되지 않음을 경고한다(R-lock 확장).
- 클론 직후 설치 진입점(예: 저장소 안 한 줄 명령)을 CLAUDE.md 에 둘지 정한다.
- 매니페스트에 프리셋 목록을 함께 적어, `presets.lock` 이 없어도 되살릴 수 있게 한다.

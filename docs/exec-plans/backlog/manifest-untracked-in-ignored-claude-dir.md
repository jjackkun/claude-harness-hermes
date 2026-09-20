# manifest-untracked-in-ignored-claude-dir — `.claude/*` 를 통째로 무시하는 소우주에서는 설치 목록이 git 에 없다

> 출처: 2026-09-21 소우주 커밋 대행 중 발견. ai-create 의 `.gitignore`(하네스 블록 밖, 프로젝트 자체 규칙)가 `.claude/*` 를 무시하고 `settings.json` 만 예외로 둔다.

## 문제

설계(`lib/factory_manifest.sh` 머리말, I-02)는 "설치 목록은 git 에 커밋된다 — 다른 컴퓨터의 clone 도 어느 파일이 공장 것인지 알아야 변조 감지·정리가 동작한다" 고 전제한다.
그러나 공장이 넣는 무시 규칙에는 `!.claude/.factory-manifest.json` 예외가 없어, 프로젝트가 `.claude/*` 를 무시하면 목록이 추적되지 않는다.

실측(ai-create): 작업 트리의 목록은 272 항목인데 `HEAD` 에는 파일이 없다. 다른 컴퓨터에서 clone 하면 doctor 는 "진단 불가(매니페스트 없음)", 공존 설치는 base 를 몰라 ⓔ(판정 불가) 갈래로 간다.
terminal-shipping 은 `.claude/` 를 추적하므로 해당 없음.

## 후보

- 하네스 무시 블록(`GITIGNORE_ENTRIES`)에 `!.claude/.factory-manifest.json` 을 넣는다 — 단, 프로젝트의 `.claude/*` 규칙이 블록보다 **뒤**에 있으면 예외가 다시 덮인다(순서 의존). 설치기가 `git check-ignore -v` 로 실제 추적 여부를 확인하고 경고하는 쪽이 확실하다.
- doctor 에 "매니페스트가 git 에 추적되지 않음" 한 줄(정보) — 다른 컴퓨터로 가져갈 수 없다는 뜻이다.
- 스킬·에이전트·룰 사본(`.claude/skills` 등)도 같은 프로젝트에서는 추적되지 않는다 — 그 프로젝트의 선택이므로 바꾸지 않되, clone 뒤 `update-all`(또는 `project-claude.sh`) 한 번이 필요하다는 것을 설치 안내에 적는다.

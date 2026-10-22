# commit-hermes-generated-skills
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
hermes-crystallize, hermes-dream, hermes-recall 등 hermes 시스템 실행 후 .hermes/skills/* 디렉토리에 새 스킬 파일이 생성되지만, 이 파일들이 git status에서 untracked(??)?? 상태로 남아있다. 커밋 전에 명시적으로 스테이징하지 않으면 새 스킬이 저장소에 반영되지 않는다.

## 규칙
- [ ] hermes 시스템(crystallize, dream, recall 등) 실행 후 `git status` 실행해서 .hermes/skills/*.md 파일 확인
- [ ] untracked 상태의 새 스킬 파일이 나타났는지 검사
- [ ] 새 스킬이 의도적이면 `git add .hermes/skills/` 로 스테이징
- [ ] 불필요한 파일이면 명시적으로 .gitignore에 패턴 추가하거나 삭제
- [ ] 커밋 전에 `git diff --cached` 로 의도한 스킬이 모두 staged 됐는지 최종 확인

## 근거
- 감지 횟수: 1회 이상
- 패턴 키: hermes-journal-untracked
- 영향: 새 스킬이 저장소에 누락되면 다음 전파·설치 시 스킬 부재로 오류 발생 가능

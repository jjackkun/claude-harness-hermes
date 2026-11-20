# respect-file-ownership-boundaries
<!-- hermes:auto-generated version:1 created:2026-11-19 -->

## 문제 상황
설정 파일을 수정하거나, 사용자가 직접 작성한 파일을 git add에 포함하거나, 헤르메스/메모리 기존 파일을 함께 커밋하는 등 파일 소유권 경계를 무시하고 작업하는 반복.

## 규칙
- [ ] 설정 파일(`.claude/settings.json`, `package.json` 등)은 읽기만 하고 수정하지 않는다
- [ ] `git add`는 현재 세션에서 만든 파일만 포함한다 (헤르메스·메모리·기존 파일 제외)
- [ ] 순서만 바뀐 파일은 커밋하지 않고 원래 상태로 복원한다
- [ ] `update-all.sh` 같은 도구는 표식된 구간만 덮어쓰고, 사용자 작성 부분은 보존한다

## 근거
- 감지 횟수: 4회
- 패턴 키: 파일은

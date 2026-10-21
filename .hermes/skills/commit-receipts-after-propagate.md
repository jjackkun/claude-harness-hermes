# commit-receipts-after-propagate
<!-- hermes:auto-generated version:1 created:2026-10-21 -->

## 문제 상황
전파(update-all) 설치 후 각 소우주에서 영수증 경로(설치 산출물) 커밋을 빠뜨리는 실수.

## 규칙
- [ ] 각 소우주 폴더로 이동
- [ ] `git status` 로 영수증 경로만 변경되었는지 확인
- [ ] `git add <영수증경로>` 로 경로 명시 스테이징 (git add -A 금지)
- [ ] `git commit -m "chore(install): 소우주명 설치 산출물"`
- [ ] `git push` 를 각 소우주마다 실행

## 근거
- 감지 횟수: 0회
- 패턴 키: propagate-receipt-commit

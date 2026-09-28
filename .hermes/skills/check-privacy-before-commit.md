# Check Privacy Before Commit
<!-- hermes:auto-generated version:1 created:2026-09-29 -->

## 문제 상황
커밋에 개인 정보, 개인적 문장, 또는 프로젝트와 무관한 개인 내용이 의도하지 않게 포함되어 리포지터리에 노출될 수 있습니다. 특히 `.hermes/`, `docs/` 같은 에이전트 기억·설계 문서 파일에 개인 기록이 섞여 올라가는 경우가 반복되었습니다.

## 규칙
- [ ] 커밋 전 `git diff` 또는 스테이징 목록을 읽고, 개인 정보나 개인적 문장이 포함되지 않았는지 확인한다
- [ ] R-privacy 게이트(`scripts/hermes-privacy-review.py`)를 pre-commit 훅으로 실행하여 자동 검증한다
- [ ] 의도하지 않은 개인 기록이 발견되면 `git reset` 또는 `git restore`로 해당 파일을 제거한 뒤 재커밋한다
- [ ] `.hermes/`, `docs/`, 설계·계획 파일에는 특히 주의하여 프로젝트 관련 내용만 포함시킨다

## 근거
- 감지 횟수: 0회
- 패턴 키: r-privacy-gate-precommit

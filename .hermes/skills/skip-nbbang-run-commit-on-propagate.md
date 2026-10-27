# skip-nbbang-run-commit-on-propagate
<!-- hermes:auto-generated version:1 created:2026-10-26 -->

## 문제 상황
전파 시 대부분의 프로젝트는 설치 후 커밋과 푸시를 수행하지만, Nbbang-Run 만 설치만 수행하고 커밋·푸시를 스킵하는 규칙이 반복됩니다.

## 규칙
- [ ] Nbbang-Run 은 전파 대상에 포함된다
- [ ] 설치만 수행한다 (미커밋 변경 포함)
- [ ] 커밋을 실행하지 않는다
- [ ] 푸시를 실행하지 않는다
- [ ] 다른 프로젝트는 정상적으로 커밋·푸시를 수행한다

## 근거
- 감지 횟수: 4회
- 패턴 키: nbbang-run

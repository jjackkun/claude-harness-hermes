# split-when-file-exceeds-gate
<!-- hermes:auto-generated version:1 created:2026-11-16 -->

## 문제 상황
코드 작성 중 파일이 복잡도 기준을 초과했을 때, 적절한 시점에 책임을 분리해 새 파일로 분할하지 못해 응집도와 유지보수성이 떨어지는 경우.

## 규칙
- [ ] 파일이 400줄을 초과하면 즉시 파일 분리 검토 (soft limit 경고)
- [ ] 파일이 500줄을 초과하면 반드시 책임 하나를 새 파일로 추출 (hard limit, 절대 규칙)
- [ ] 분리 시 한 파일 = 한 책임 원칙 준수 — 기존 코드를 완전히 재작성하지 않고 책임만 추출
- [ ] 분리 후 barrel 파일(index.ts / __init__.py)로 재수출 구조 정리
- [ ] 주요 소유자(ownership)와 의존성 구조를 미리 파악해 분리 지점 결정

## 근거
- 감지 횟수: 0회
- 패턴 키: split-file-for-complexity-gate
- 관련 규칙: CLAUDE.md 「코드 작성 전」, coding-style.md 「파일 조직화」

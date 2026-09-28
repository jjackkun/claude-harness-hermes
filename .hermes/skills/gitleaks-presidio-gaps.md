# gitleaks-presidio-gaps

<!-- hermes:auto-generated version:1 created:2026-09-16 -->

## 문제 상황
gitleaks와 presidio 같은 비밀값 탐지 도구를 pre-commit 게이트에 두어도, 새로운 형태의 비밀값과 한글 PII(주민번호, 연락처)를 놓친다. 탐지 필터가 정교해져도 "원문을 통째로 기록하는 구조"가 남으면, 단 한 번의 실패가 영구적 유출이 된다.

## 규칙
- [ ] git 커밋 전 gitleaks, presidio 스캔은 필수지만, 이것만으로 충분하지 않다고 가정한다.
- [ ] 탐지 도구의 오탐(false negative)을 대비해, 설계 단계부터 민감한 정보를 **원문으로 기록하지 않는다.**
- [ ] 코드, 스킬, 작업 이력 중 민감 정보가 필요하면 암호화하거나 토큰화하는 설계를 먼저 한다.
- [ ] 한글 PII(주민번호, 휴대폰, 계좌번호)는 탐지 도구가 특히 취약하므로, 별도 정규식 또는 커스텀 필터를 함께 사용한다.
- [ ] "이미 올라간 것은 지울 수 없다"는 가정 하에, 검증 게이트를 여러 층으로 겹친다(git hook + CI + 설계).

## 근거
- 감지 횟수: 3회
- 패턴 키: secret-detection-stack-gitleaks-presidio-ko-pii

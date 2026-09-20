# check-secrets-false-positives — P9 가 멀쩡한 코드를 비밀값으로 본다

> **완료 → `docs/exec-plans/completed/2026-09-20-check-secrets-false-positives.md`** (2026-09-20). 아래 "하류가 이미 고쳤다" 는 추정은 실측으로 틀렸다 — 완료 기록 §1 참고.

> 출처: `completed/2026-09-20-agent-eval-regression.md` §7 · `completed/2026-09-20-identity-files-edit-guard.md` §7.

## 실측 오탐 2종 (2026-09-20)

- ENV_SECRET: `API_KEY = os.environ.get("API_KEY", "")` — 환경변수에서 읽는 **올바른** 코드가 막힌다. 막힌 작업자는 우회를 배운다.
- ENV_SECRET: 이름에 TOKEN·KEY 가 든 **정규식·상수 변수**(`PATH_TOKEN = r"…"`) — 훅 소스 한 줄이 설치 직후 소우주의 첫 커밋을 막았다(변수 이름을 바꿔 피함).

## 고칠 때 후보

- terminal-shipping 의 하류 수정(`_is_ident_ref`·`_kv_exempt`·`_is_name_echo`)이 같은 계열을 이미 고쳤다 — 그쪽이 공장판의 상위 집합임을 확인했다(2026-09-20 병합). 일반 개선분을 공장으로 되돌려 받는다.
- 되돌려 받을 때 그 저장소 고유 규칙(`tests/` 통째 면제 거부, 시안 캔버스 면제)은 빼고, 시험(`tests/test_check_secrets.py` 50건)의 일반 사례를 같이 옮긴다.
- 같이 볼 것: harness-eval secret-hardcode/supportive 에서 모델이 실제 키 값을 `.env.example` 에 적었다(1/2) — 편집 순간 가드는 없다(커밋 때 P9).

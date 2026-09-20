# 2026-09-20-coexist-old-factory-detection — 공존 설치가 "옛 공장판" 을 하류 수정으로 오인해 보존한다 (완료)

> 백로그에서 바로 수정(원인이 명확한 결함이라 계획 단계 생략 — reasoning-sandwich 표 "버그 수정(원인 명확)"). 사용자 "응 그렇게 하자" 2026-09-20.

> 출처: `docs/exec-plans/active/2026-09-20-install-doctor-repair.md` §7 (doctor 첫 실측, 2026-09-20).

## 증상

update-all 직후인데 소우주 3곳 모두 훅 몇 개가 매니페스트 sha 와 다르고 factory_commit 이 옛 것(d61426d)에 머문다.

| 소우주 | 보존된 옛 판 |
|---|---|
| ai-create | `.git/hooks/pre-commit`(게이트 13종 — 공장은 18종), `.git/hooks/check-secrets.py`, `scripts/hooks/claude-sessionstart-history-reindex.sh`, `claude-stop-retrospective.sh`, `claude-userpromptsubmit-reminders.sh` |
| wonil | 위 훅 3개 |
| terminal-shipping | `pre-commit`, `check-secrets.py`, `plan_state.py`(githook·hook 둘 다) |

ai-create 의 pre-commit 은 옛 공장판 그대로다(하류 수정 흔적 없음). `lib/factory_coexist.sh` 의 c 갈래("공장은 그대로고 하류만 고쳤다 → 손대지 않는다")
또는 ⓔ 갈래에서 `_coexist_is_old_factory` 가 옛 판을 못 알아본 것으로 보인다. 결과: 소우주가 **옛 게이트로 커밋을 검사**한다 — 조용한 퇴행.

## 확인할 것

- `_coexist_is_old_factory` 가 `git log -p -- <src_rel>` 로 옛 sha 를 찾는 범위·깊이(얕은 clone·리네임·CRLF·모드 차이).
- 매니페스트 base sha(`sha256` 필드)가 ours 와 다른데 theirs 와도 다른 경우(d 갈래)의 처리.
- 재현: 픽스처에 옛 공장 커밋으로 설치 → 공장 HEAD 로 update → 훅이 새 판인지.

## 고치면

doctor 의 "불일치" 가 실제 하류 수정만 남는다. 그 전까지는 doctor 출력에서 이 목록을 "옛 판 보존" 으로 읽는다.

## 원인 (2026-09-20 실측)

ai-create `.git/hooks/pre-commit`: 파일 sha 95c547d1(공장 이력 3167d8 판) · manifest sha e3588a13 = 현재 공장판. `install_factory_file` 의 c 갈래
(`base_sha == theirs_sha` → "공장은 그대로고 하류만 고쳤다")가 ours 가 **옛 공장판**인 경우를 하류 수정과 구분하지 못했다. 옛 판 검사
(`_coexist_is_old_factory`)는 base 를 모르는 ⓔ 갈래에서만 돌았다. 한 번 이 상태가 되면 매 전파마다 c 로 빠져 영원히 옛 판이 남는다.

## 수정

- `lib/factory_coexist.sh`: `_coexist_deliver_if_old` — c 갈래와 "사실상 c" 갈래 앞에서 ours 가 공장 이력(200 커밋)의 옛 판이면 전달(b). 진짜 하류 수정(이력에 없는 내용)은 그대로 c.
- 같은 커밋에 리뷰 지적(HIGH) 수정: `_manifest_sha` 가 공백 든 파일 이름에서 xargs 단어 분리로 빈 목록 해시가 되던 결함 → `-print0 | sort -z | xargs -0`. doctor 는 비UTF-8 이름에서 죽지 않게 `surrogateescape`.

## 검증

- `tests/install-coexist-test.sh` 9절(85): c-old 전달 · 사실상-c 전달 · 진짜 하류 수정은 c 유지. `tests/harness-doctor-test.sh` 3b절(35): bash·python sha 일치(공백 이름).
- update-all 뒤 doctor: 아래 §실측.

## 실측 (수정 뒤 update-all, 2026-09-20)

| 소우주 | 전 | 후 |
|---|---|---|
| ai-create | 불일치 5(pre-commit 13종 판 등) | **깨끗** 0 — pre-commit 18종 판으로 교체됨 |
| wonil | 불일치 3 | **깨끗** 0 |
| terminal-shipping | 불일치 4 | 불일치 3 — `check-secrets.py`·`plan_state.py`(githook·hook) 는 공장 이력에 없는 **진짜 하류 수정**(프로젝트 고유 면제 규칙·주석). c 갈래가 맞게 보존. `.factory-new` 없음 |

doctor 의 "불일치" 는 이제 하류 수정만 남는다. terminal-shipping 3건은 하류가 공장에 되돌려 보낼지(제안) 사람이 정할 일이다.

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

## 8. 회고

- 잘된 것: doctor 가 첫 실행에서 잡은 결함을 같은 날 sha 세 값(ours·manifest·theirs) 대조 한 번으로 갈래까지 특정했고, 수정은 기존 옛 판 검사를 c 갈래 앞으로 옮긴 것뿐이다. 대조 사례(진짜 하류 수정은 c 유지)를 테스트에 같이 넣어 과잉 전달을 막았다.
- 잘못된 것: 옛 판 검사가 ⓔ 갈래에만 있었던 것은 "base 를 알면 하류 수정이다" 라는 가정 때문인데, base 기록 자체가 틀릴 수 있다는 경우(전파 누락 뒤 c 로 굳음)를 설계 때 안 봤다. 리뷰어가 잡은 공백 파일 이름 결함도 설치 초기부터 있었다 — sha 계산 함수에 이름 특수문자 테스트가 없었다.
- 다음 룰 후보: 설치기 판정 함수(`install_factory_file`)의 갈래 하나를 바꿀 때는 "ours 가 옛 공장판" 대조 사례를 반드시 포함한다(테스트 9절이 그 자리). 매니페스트 sha 함수는 공백·개행 이름 픽스처로 bash·python 양쪽을 대조한다(doctor 3b절).

## 후속 (같은 날) — 충돌 해소 기록이 없어 전파할 때마다 같은 충돌이 되살아났다

- 증상: terminal-shipping 의 `check-secrets.py`(하류 수정본)가 공장판과 충돌 → 사람이 합치고 `.factory-new` 를 지움 → **다음 update-all 에서 같은 충돌이 다시 세워짐**(공장판은 그대로였다). 그때마다 R-merge 가 그 프로젝트의 커밋을 막는다.
- 원인: 충돌(x) 갈래가 매니페스트를 건드리지 않아 base 가 옛 판에 머문다. "이 공장판에 대해서는 해소했다" 를 적는 자리가 없었다.
- 수정: 충돌 때 세워 둔 공장판의 sha 를 `parked_sha` 로 적는다(`manifest_mark`). 다음 설치에서 병합이 여전히 충돌이어도 `parked_sha == theirs` 이고 `.factory-new` 가 없으면 **해소로 인정(r 갈래)** — 다시 세우지 않고 base 를 그 공장판으로 올린다. `.factory-new` 가 남아 있으면 계속 충돌로 둔다. 병합이 되는 상황이면 r 보다 병합(d)이 먼저다.
- 검증: `tests/install-coexist-test.sh` 10절(96) — 충돌 → parked 기록 → 안 풀면 계속 x → 풀면 r(무출력, 되살아나지 않음) → 그 뒤 c → 공장의 다른 자리 개정은 새 base 에서 d 병합.
  실물: terminal-shipping 1차 설치 parked 기록, 파일 제거, 2차 설치 충돌 알림 0 · base = 현재 공장판 · 하류 면제 줄 유지.
- 테스트 픽스처 교훈: `$(…)` 명령 치환은 끝 줄바꿈을 자른다 — 공장판과 하류판의 끝 줄바꿈이 다르면 마지막 줄이 가짜 충돌을 낸다.

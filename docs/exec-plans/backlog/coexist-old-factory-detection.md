# coexist-old-factory-detection — 공존 설치가 "옛 공장판" 을 하류 수정으로 오인해 보존한다

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

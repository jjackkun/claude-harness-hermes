# dashboard-sync-before-verdict — "뒤처짐" 을 내기 전에 사본이 최신인지부터 본다

## 1. 동기 (Why)

우주 대시보드의 `factory` 칸은 `_factory_match()` 가 낸다
(`scripts/hermes_dashboard_data.py`). 이 함수는 **양쪽 다 로컬 사본만** 본다:

- 소우주의 `<소우주>/.hermes/factory.json.installed_version` 을 읽고
- **공장의 로컬 HEAD** 와 `git diff --name-only <installed> HEAD -- <설치대상>` 을 돌린다

원격은 어느 쪽도 조회하지 않는다. 그래서 한 칸이 서로 다른 세 상태를 뭉뚱그린다.

| 실제 상태 | 사람이 해야 할 일 | 지금 표시 |
| --- | --- | --- |
| 소우주 **사본**이 원격보다 뒤 | 그 저장소를 `git pull` | 뒤처짐 |
| **공장 사본**이 원격보다 뒤 | 공장을 `git pull` | 일치로 보일 수 있다 |
| 진짜 **미설치** | `update-all` 전파 | 뒤처짐 |

**실측 2026-09-22.** 이 컴퓨터에서 우주 대시보드가 ai-create·wonil 을 "뒤처짐" 으로
표시했다. 원인은 미설치가 아니었다 — 전파는 **다른 컴퓨터에서 이미 끝나 있었고**,
이 컴퓨터의 ai-create 사본이 origin/master 보다 **10 커밋 뒤**였을 뿐이다
(받아온 10개가 전부 `chore(harness): ... 재설치 반영`, 맨 위가 `factory 3e9272d`).
표시를 믿고 `update-all` 을 돌렸다면 이미 한 일을 다시 하는 것이었다.

`wonil` 은 한술 더 뜬다 — **git 저장소가 아니다**. 1번 축이 아예 없으므로
"뒤처짐" 을 봐도 풀로 고칠 길이 없는데 표에는 같은 낱말로 나온다.

> 사용자 지적(2026-09-22): "팩토리가 뒤처졌다는 것을 확인하기 전에
> 저장소가 최신으로 동기화되어 있는지부터를 확인해야겠네."

## 2. 목표 후보 (검증 가능한 형태로 다듬을 것)

- [ ] 목표 후보 1 — 우주 표에서 "사본이 옛것" 과 "설치가 옛것" 이 **다른 낱말**로 보인다.
      검증: 일부러 뒤처진 사본 픽스처와 미설치 픽스처를 만들어 표 문구가 다름을 단언.
- [ ] 목표 후보 2 — git 저장소가 아닌 소우주는 동기화 칸이 "해당 없음" 으로 보인다.
      검증: `.git` 없는 픽스처로 단언.
- [ ] 목표 후보 3 — 공장 사본 자신이 원격보다 뒤면 표 머리에 한 줄 경고가 붙는다.
      검증: 뒤처진 공장 픽스처로 단언.

## 3. 비목표 (지금 정해 둠)

- **대시보드가 fetch 를 돌리는 것.** 대시보드는 "모델 호출 0, 외부 자원 0, 보기 전용" 이
  선언된 도구다(SKILL.md). 망을 타면 그 성질이 깨지고 느려진다.
  → 이미 로컬에 있는 `refs/remotes/*` 만 읽어 비교한다. 마지막 fetch 가 언제였는지도
  함께 보여 "이 비교 자체가 옛것일 수 있다" 를 사람이 알게 한다.
- 자동 풀·자동 전파. 판단은 사람이 한다.

## 4. 착수 전 확인할 것

| 확인할 것 | 왜 |
| --- | --- |
| `git rev-list --count HEAD..@{u}` 가 원격 추적 없는 저장소에서 어떻게 실패하는가 | 실패를 "동기화됨" 으로 오인하면 안 된다(fail-closed) |
| 마지막 fetch 시각을 어디서 읽는가 (`.git/FETCH_HEAD` mtime) | 없을 수도 있다 |
| 우주 표의 칸 수가 늘어날 때 폭 | 이미 8칸 |

## 5. 관련

- `scripts/hermes_dashboard_data.py` — `_factory_match` · `_universe_row` · `collect_universe`
- `scripts/hermes_dashboard_html.py` — `render_universe` ("뒤처짐" 표기)
- 계획 `docs/exec-plans/completed/2026-09-22-rule-candidates-dashboard.md` — 이 칸을 만든 계획
- 계획 `docs/exec-plans/active/2026-09-22-universe-dashboard-auto.md` — 이 발견이 나온 자리

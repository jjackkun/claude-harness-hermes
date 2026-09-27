# 2026-09-27-dashboard-sync-before-verdict — "뒤처짐" 을 내기 전에 사본이 최신인지부터 본다

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

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — 우주 표에서 "사본이 옛것" 과 "설치가 옛것" 이 **다른 낱말**로 보인다.
      검증: 원격보다 뒤처진 사본 픽스처 → `사본` 칸 "N 뒤", factory 칸 "사본부터" / 사본 최신·설치 옛것 → "설치 뒤처짐".
- [x] 목표 2 — git 저장소가 아닌 소우주는 `사본` 칸이 "해당 없음" 이다. 검증: `.git` 없는 픽스처.
- [x] 목표 3 — 공장 사본 자신이 원격보다 뒤면 표 머리에 한 줄 경고가 붙는다. 검증: 뒤처진 공장 픽스처로 렌더.
- [x] 목표 4 — 판정 불가(원격 추적 없음·git 실패)는 "최신" 으로 보이지 않는다(fail-closed). 검증: upstream 없는 픽스처 → "원격 없음".

## 2-bis. 착수 전 확인한 사실 (2026-09-27)

| 확인한 것 | 결과 |
| --------- | ---- |
| `git rev-list --left-right --count HEAD...@{u}` (공장, 최신) | `0\t0` |
| wonil 에서 `git rev-parse --show-toplevel` | `fatal: not a git repository` — rc≠0 |
| 마지막 fetch 시각 | `git rev-parse --git-path FETCH_HEAD` → `.git/FETCH_HEAD` mtime (없을 수 있음) |
| 우주 표 폭 | 8칸 → `사본` 1칸 추가해 9칸 |
| 설치 목록 | `presets/workflow/hermes.conf` hermes_scripts — 새 모듈을 여기 추가해야 소우주에 깔린다 |

## 3. 비목표 (지금 정해 둠)

- **대시보드가 fetch 를 돌리는 것.** 대시보드는 "모델 호출 0, 외부 자원 0, 보기 전용" 이
  선언된 도구다(SKILL.md). 망을 타면 그 성질이 깨지고 느려진다.
  → 이미 로컬에 있는 `refs/remotes/*` 만 읽어 비교한다. 마지막 fetch 가 언제였는지도
  함께 보여 "이 비교 자체가 옛것일 수 있다" 를 사람이 알게 한다.
- 자동 풀·자동 전파. 판단은 사람이 한다.

## 4. 영향 영역

- 코드: `scripts/hermes_dashboard_data.py`(행에 sync) · `scripts/hermes_dashboard_html.py`(사본 칸·factory 낱말·머리 경고) · `scripts/hermes-dashboard.py`(공장 sync 전달) · `presets/workflow/hermes.conf`(설치 목록)
- **신규 파일 목록**:
  - `scripts/hermes_repo_sync.py` — 저장소 사본이 로컬에 있는 원격 추적 ref 보다 앞/뒤인지 망 없이 판정
  - `tests/hermes-repo-sync-test.sh` — 위 판정과 우주 표 문구 단언

## 4-bis. 착수 전 확인할 것 (백로그 원문)

| 확인할 것 | 왜 |
| --- | --- |
| `git rev-list --count HEAD..@{u}` 가 원격 추적 없는 저장소에서 어떻게 실패하는가 | 실패를 "동기화됨" 으로 오인하면 안 된다(fail-closed) |
| 마지막 fetch 시각을 어디서 읽는가 (`.git/FETCH_HEAD` mtime) | 없을 수도 있다 |
| 우주 표의 칸 수가 늘어날 때 폭 | 이미 8칸 |

## 5. 단계

1. 시험 먼저(RED) → 2. `hermes_repo_sync.py` → 3. 데이터·렌더 연결 → 4. 설치 목록 → 5. 주장별 실측 후 커밋

## 6. 의사결정 로그

- 2026-09-27: 사본 칸을 factory 칸과 따로 둔다(9칸) — 근거: 한 칸에 합치면 "해당 없음"(wonil) 과 "일치" 를 같이 못 보인다
- 2026-09-27: 사본이 뒤·갈라짐이면 factory 칸은 판정 대신 "사본부터" — 근거: 옛 사본의 영수증으로 낸 판정은 믿을 수 없다(ai-create 사례)
- 2026-09-27: 설치 판정 비교에서 `scripts/hooks` 를 뺀다 — 근거: 공장의 그 폴더 53개 파일이 전부 `assets/hooks` 에 원본이 있는 자기 설치 사본

## 7. 발견·예외

- **실측 중 발견(2026-09-27):** 방금 전파한 3곳이 전부 "설치 뒤처짐" 으로 나왔다. 깔린 판(44579b4)과 HEAD(8b13748) 사이
  설치 대상 변경은 `scripts/hooks/claude-pretooluse-bash-guard.sh` 하나 — 공장이 **자기에게 설치한 사본**이었다.
  전파할 때마다 공장이 자기 설치를 커밋하므로 이 칸은 사실상 늘 오판이었다. 시험으로 먼저 재현(RED) 후 제외 → 3곳 "일치".
- 실측(실제 이 컴퓨터 우주 표): wonil 사본 "해당 없음" · terminal-shipping·공장 "최신"(마지막 fetch 09-22 22:08) · factory 3곳 "일치" · 머리 경고 없음.
- 샌드박스 harness+hermes 설치 → `scripts/hermes_repo_sync.py` 깔림, 설치본 대시보드 rc 0.

## 8. 회고 (완료 시 작성)

- 잘된 것: 실제 우주 표로 실측하다가 기존 칸의 상시 오판(자기 설치본)을 잡았다 — 픽스처 시험만으로는 안 보였다.
- 잘못된 것: 이 칸을 만든 09-22 계획은 "영수증 커밋" 만 예외로 봤고, 공장이 `scripts/hooks` 에 자기 설치하는 경로를 몰랐다.
- 다음 룰 후보: 없음(한 번 발생). 설치 원본 목록(`_INSTALL_SOURCES`)과 설치기 실제 복사 경로가 또 어긋나면 대조 시험으로 승격.

## 9. 관련

- `scripts/hermes_dashboard_data.py` — `_factory_match` · `_universe_row` · `collect_universe`
- `scripts/hermes_dashboard_html.py` — `render_universe` ("뒤처짐" 표기)
- 계획 `docs/exec-plans/completed/2026-09-22-rule-candidates-dashboard.md` — 이 칸을 만든 계획
- 계획 `docs/exec-plans/active/2026-09-22-universe-dashboard-auto.md` — 이 발견이 나온 자리

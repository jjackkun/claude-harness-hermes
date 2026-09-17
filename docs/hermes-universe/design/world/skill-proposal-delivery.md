# 스킬 제안 배달 — 보낼 편지함과 GitHub 이슈

> 작성일: 2026-09-15
> 목적: 소우주가 "이런 스킬을 만들었다·고쳤다"를 우주에 전달하는 방법을 정한다.

## 개요

소우주는 제안 봉투를 **자기 안의 보낼 편지함에만** 쓴다. 배달은 **공장의 GitHub 원격에 이슈를 여는
방식 하나**뿐이다. 우주가 허가하면 공장 저장소에 커밋(PR)으로 반영하고, 소우주는 다음 세션 시작 때
자기 이슈의 상태를 읽는다.

## 1. 우주 공통 스킬이 고쳐지는 두 경우

| 경우 | 흐름 |
|---|---|
| 공장이 직접 개선 | 공장 커밋 → 소우주가 `update-all`로 받을 때 반영(복사 설치, [copy-install.md](copy-install.md)) |
| 소우주가 필요해서 개선 | 아래 흐름 |

## 2. 소우주가 개선한 경우의 흐름 (확정, P-03 · P-04 · RV-15 · S-03 · S-06)
```text
소우주                                               우주 (github.com/jjackkun/claude-harness-hermes)
1. 공통 스킬을 직접 고치지 않는다
   소우주 층에 "확장 + 차이"로 고친다 → 소우주에서는 바로 쓴다
2. 제안 명령  hermes-propose.py new|improve|exclude <스킬>
   ├ 일반화 (소우주 사실 제거)
   ├ 국한성 자체 점검 (mesh_gate) + 금지 내용 게이트 (3절)
   └ .hermes/outbox/<envelope_id>/ 에 봉투 작성 → status=pending
3. 배달 (사람이 --deliver 를 붙였을 때만) ────────────▶  이슈 (gh issue create --label proposal)
   성공 → status=delivered                            4. 우주 심사
   실패(오프라인·인증·gh 없음) → status=pending 유지        국한성 · 중복 · 전제 · 평가
        세션 시작 때 "배달 못 한 봉투 N개" 알림           5. 허가 → PR/커밋, 이슈 연결
                                                          거절 → 사유 남기고 이슈 닫음
6. 다음 세션 시작 때 자기 봉투의 이슈 상태 조회  ◀─────  (gh issue view)
   허가 → status=approved, "소우주 확장분 제거" 안내
   거절 → status=rejected, 소우주 확장으로 계속 사용
```

- 봉투 상태 전이는 `pending → delivered → approved|rejected` 하나뿐이다.
- 배달은 **사람이 `hermes-propose.py … --deliver` 를 명령했을 때만** 일어난다. 훅·세션 종료에서 자동 호출하지 않는다(RV-15). 제안이 outbox 에 쌓이고 잊히는 손해는 세션 시작 훅의 개수 알림으로 줄인다.
- 결과 통보는 **공장이 소우주에 쓰지 않는다.** 소우주가 읽으러 간다. 공장이 소우주 안에 쓰면 격리 원칙에 어긋난다.
- "소우주 확장분 제거" 는 자동이 아니라 안내다 — 소우주가 우주판을 `update-all` 로 받은 뒤 사람이 확장 파일을 지운다.
- 공장이 로컬에 있든 없든 흐름은 하나다. 공장 쪽 작업자도 로컬 폴더가 아니라 GitHub 이슈에서 제안을 받는다. 우주 쪽 심사(이슈를 읽어 PR 로 만드는 일)는 사람이 한다.

## 3. 봉투 형식

| 칸 | 내용 |
|---|---|
| `envelope_id` | 봉투 식별자 |
| `universe_id` | 결과를 돌려받을 곳(강등 반환 시에도 사용) |
| `kind` | `new`(신규) / `improve`(개선) / `exclude`(제외 신고). `template`(에이전트 복제, G-23)은 값만 예약 |
| `skill_id` | 층을 옮겨도 불변인 스킬 키([skill-layers.md](skill-layers.md) 1절) |
| `base` | 개선일 때 기준 스킬 `skill_id@version` — 그사이 공장도 같은 스킬을 고쳤는지 알기 위해 |
| 스킬 본문 + 차이 | 일반화된 본문과 기준 버전 대비 차이 |
| 이유 | 어떤 문제가 있었고 무엇이 좋아졌는가 |
| 게이트 결과 | 판정 내역 — mesh_gate(일반화 자체 점검)와 금지 내용 게이트 각 항목의 통과 여부 |
| 제안자 | `agent_id`, 층 |
| `status` | `pending` / `delivered` / `approved` / `rejected`. `pending` 에는 마지막 배달 오류 문구를 함께 남긴다(인증 오류를 오프라인으로 오인하지 않기 위해) |

### 넣지 않는 것

- 기억, 대화 원문, 티켓 번호, 파일 경로 — 봉투 작성 전 게이트에서 막는다(제안 명령이 거부한다).
- **사람이 읽는 이름(소우주 이름·팀 이름·에이전트 이름).** 이슈는 소우주 밖(GitHub)으로 나간다. 공장
  저장소가 공개라면 `zeroday-frontend` 같은 이름이 드러난다. 봉투에는 `universe_id`와 `agent_id`만 넣고,
  그 id가 누구인지는 소우주 안의 명부에서만 풀린다. 결과를 돌려받는 데는 id만으로 충분하다.

> ✅ 리뷰 확정 (2026-09-15, RV-15) — **공장 저장소는 PUBLIC 이다.** `gh repo view jjackkun/claude-harness-hermes --json visibility` → `PUBLIC`(V-7). 위 결정의 전제가 확인됐고, 따라 나오는 것이 하나 더 있다: **봉투의 스킬 본문과 "이유" 칸 자체가 공개 게시물**이다. 그래서 (a) 배달은 **사람이 명령으로만** 한다 — 세션 종료 훅 등 자동 배달 경로는 두지 않는다, (b) 일반화와 mesh_gate 는 권장이 아니라 **배달 전 필수 통과**다. 사내 서버에만 두는 zeroday-frontend 에 사내 정보가 새는 새 경로를 열지 않기 위해서다. 이슈 본문에 들어간 글은 나중에 지워도 알림 메일과 캐시에 남는다.

## 4. 폐기된 배달 방식

| 방식 | 폐기 이유 |
|---|---|
| 공장 안 우편함 폴더에 직접 넣기 | 공장이 로컬에 없으면 우편함도 없다 |
| 공장이 로컬에 있으면 폴더 복사 | **로컬 배달은 부작용이 많다**(사용자 판단): 공장 작업 트리가 더러워지고, 진행 중 작업과 섞이며, 공장 커밋 게이트가 남의 파일에 걸린다 |
| 곧바로 공장에 PR | 허가 전 제안은 코드 변경이 아니라 의견 전달이다. 소우주 세션이 남의 저장소에 브랜치를 만든다 |
| DB `messages` 테이블(`hermes-message.py`) | 사람이 열어 볼 수 없고, `global.db`에 기록이 섞여 쌓인 문제를 되풀이한다 [^messages] |

[^messages]: 폐기 **결정**이다. 실제 제거는 읽는 코드가 남아 있는지 확인한 뒤 다음 계획에서 한다. 지금은 호출 시 "폐기 예정" 경고 한 줄만 낸다.

## 5. 소우주가 공장을 찾는 방법 — factory.json

현재 `.claude/presets.lock`에는 **프리셋 이름만** 있다(예: zeroday-frontend의 `node`, `python`, `harness`,
`hermes`, `adhd` …). 공장 위치와 설치 버전이 없어 소우주가 공장을 찾아갈 수 없다.

설치 시 소우주에 기록한다.

```json
{
  "remote_url": "git@github.com:jjackkun/claude-harness-hermes.git",
  "installed_version": "<설치 시점 공장 커밋 해시>"
}
```

- `installed_version`은 봉투의 `base`를 채우는 데 쓴다.
- `local_path`는 두지 않는다(로컬 배달 폐지).
- `remote_url` 은 설치기만 쓴다. `hermes-propose.py` 는 주소 인자(`--remote` 류)를 받지 않고 이 파일 값만 읽으며, `factory.json` 은 설치 목록에 들어 변조 경고 대상이다([copy-install.md](copy-install.md) 4절).

> ✅ 리뷰 확정 (2026-09-15, RV-16) — `remote_url` 은 설치기만 쓴다 (근거: cumora K-7). 배달 목적지를 에이전트가 바꿀 수 있으면 봉투(그리고 그 안의 소우주 정보)가 다른 주소로 나간다 — 원문 경계 원칙(T-02)의 스킬판 위반이다. cumora 는 스킬 허브 주소를 운영자 설정으로만 두고 에이전트에게는 경로 조각만 주며, 리다이렉트도 끈다(`server/src/agents/skills.ts` "Agent-controlled URLs are intentionally rejected"). `factory.json` 은 설치 목록에 넣어 변조 감지 대상으로 삼고, 배달 스크립트는 파일 값 외의 주소 인자를 받지 않는다.

## 6. 현재 상태와 걸리는 점

- symlink 설치에서는 소우주가 공통 스킬을 고치면 **허가 없이 공장 원본이 바로 바뀐다.** 이 뒷문이 열려 있는 한 제안·허가 흐름은 우회된다. 복사 설치로 막는다([copy-install.md](copy-install.md)).
- 공장 GitHub에 이슈를 여는 인증이 필요하다. GitHub MCP 서버는 인증 헤더 오류로 연결에 실패한 이력이 있어 쓰지 않는다. **배달은 `gh` CLI 만 쓴다(확정)** — 이 환경에 이미 있고(V-7 확인에 사용) 배달 시에만 필요하다. `gh` 가 없거나 실패하면 오류가 아니라 `status=pending` 으로 두고 마지막 오류 문구를 보존한다.

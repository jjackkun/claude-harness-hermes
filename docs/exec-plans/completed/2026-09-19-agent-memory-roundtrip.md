# 2026-09-19-agent-memory-roundtrip — 원본 에이전트의 기억이 컴퓨터를 따라간다

> 출처: 2026-09-19 대화 — 사용자: "같은 저장소에서 원본 에이전트가 풀·푸시 했으면 존재해야지. 다른 컴퓨터라는 것 하나 때문에 기억을
> 잃어버린다고? 복제는 기억을 빼고 다 갖고, 원본마저 그러면 안 되잖아."
> 설계 결정 인용: C-14(기억 원본 `memory_events`, 원격 `refs/hermes/sync` 의 `memory/<agent_id>/<memory_id>.json`) · C-20(본문 암호화) ·
> A-10(MEMORY.md 는 파생물, 어느 컴퓨터든 다시 만든다) · H-09(복제는 새 id·수습·기억 없음) · RV-03(마스터 열쇠 감싸기)

## 1. 동기 (Why)

실측(2026-09-19): 운반 코드는 있다 — `hermes_sync_fragments._outgoing_memory`(push, 본문 암호화)·`import_memory`(pull)·`hermes-sync.py _import_all` 의
`memory/` 분기. 그런데 세 가지가 비어 있어 "원본이 기억을 갖고 다닌다" 가 성립하지 않는다.

1. **MEMORY.md 를 다시 만드는 호출이 0건** — `hermes_memory_view.write_memory_md` 를 부르는 스크립트·훅이 없다. pull 로 이벤트가 들어와도 보기는 그대로다.
2. **운반이 어느 소우주에서도 켜져 있지 않다** — `.hermes/sync.json`·열쇠·`refs/hermes/sync` 전부 0(공장·ai-create·terminal-shipping).
3. **기억 왕복 테스트가 없다** — `tests/hermes-sync-test.sh` 에 `memory` 0건. `hermes_sync_fragments.py` 머리말은 아직 "memory/… 경로만 예약".

## 2. 목표 (What — 검증 가능한 형태)

- [x] 목표 1 — `memory_events` 에 이벤트가 쌓이거나 pull 로 들어오면 그 에이전트의 `MEMORY.md` 가 이벤트에서 다시 만들어진다.
  호출 지점 둘: `hermes-agent.py teach`·리뷰 닫기 등 `record` 뒤(같은 트랜잭션 밖, 실패해도 이벤트는 남음) + 세션 시작 훅(`claude-sessionstart-agent-soul.sh` 가 읽기 전).
  검증: `bash tests/hermes-memory-events-test.sh` 에 "record 뒤 MEMORY.md 갱신" 절 · 훅 절
- [x] 목표 2 — push → 빈 clone 에서 pull → 같은 `memory_id` 집합이 `memory_events` 에 있고 본문이 복호돼 있으며 `MEMORY.md` 가 같은 내용.
  검증: `bash tests/hermes-sync-test.sh` 에 기억 왕복 절(임시 bare 원격 + 열쇠 픽스처, 이벤트 3건 중 1건 철회)
- [x] 목표 3 — 복제(H-09, `hermes-propose.py template`)는 여전히 기억을 싣지 않는다 — 검증: 기존 propose 테스트에 `memory_events` 0건 단언 추가
- [x] 목표 4 — 운반 켜기 절차가 한 곳에 있고 실행 가능하다: 열쇠 만들기 → `.hermes/sync.json {"push": true}` → 첫 push → 다른 컴퓨터 join → pull.
  `docs/hermes-sync-guide.md`(신규 또는 기존 보강) + 세션 시작 훅의 H-10 안내문이 그 문서를 가리킨다 — 검증: 문서의 명령을 공장에서 그대로 실행해 `refs/hermes/sync` 생성
- [x] 목표 5 (2026-09-20 재정의, T-18·T-21) — 실제 켜기는 열쇠 없이 설치기가 한다. 이 공장은 공개 저장소(PUBLIC 실측)라 기본 꺼짐이므로, 시연은 **비공개 임시 원격**에서:
  설치기 → 평문 운반 켜짐 → 게이트QA `teach` 1건 → push → 두 번째 clone pull → MEMORY.md 일치. 구현은 계획 `2026-09-20-transport-plain` 이 맡고, 이 목표는 그 계획 완료 뒤 시연만 한다
- [x] 목표 6 — `hermes_sync_fragments.py` 머리말의 "경로만 예약" 을 현재 상태로 고친다. 검증: `grep -c '경로만 예약' scripts/hermes_sync_fragments.py` = 0
- [x] 목표 8 (2026-09-20 추가, 사용자: "필요한 도구면 setup·update-all 로 깔려야지 따로 설치하면 안 된다") — hermes 프리셋이 `REQUIRED_BINS+=(age age-keygen)` 을 선언하고
  설치기(`project-claude.sh`, 따라서 `setup`·`update-all` 모두)가 없으면 설치한다: 핀 고정 v1.3.2 배포 파일을 받아 sha256 대조 뒤 `~/.local/bin` 에 놓는다(apt 에 없는 Ubuntu 20.04 실측).
  대조 실패면 설치하지 않고 경고. 이미 있으면 건너뜀. 검증: `bash tests/tool-installers-test.sh`(있음→무동작 · 픽스처 설치 · 해시 불일치 거부) + 이 컴퓨터에서 재설치 뒤 `age --version`
- [x] 목표 7 — 설치 폐로·의존 계층: 새 훅/문서가 `hermes.conf`·`.deprc`·`run-all.sh` 에 있다 — 검증: `bash tests/install-closure-test.sh` · `bash tests/dep-contract-test.sh`

## 3. 비목표 (Out of Scope)

- 기억 충돌 해소 규칙 변경(`hermes_memory_conflicts.py` 그대로) · 기억 본문 암호화 방식 변경(C-20 그대로).
- `state.db` 전체를 git 에 넣는 것 — 파생·요약·주입 로그까지 실어 나를 이유가 없고 충돌만 는다. 옮기는 원본은 기억 이벤트·작업 이력·대화 조각뿐.
- 복제 에이전트에 기억을 싣는 것(H-09 위반).
- 열쇠 배포 자동화 — 열쇠는 사람이 옮긴다(encryption-keys.md).

## 4. 영향 영역

- 코드: `scripts/hermes-agent.py`(record 뒤 `write_memory_md` 호출) · `scripts/hermes_handoff.py`(리뷰 닫기 — agent-teaching 과 합류) ·
  `assets/hooks/claude-sessionstart-agent-soul.sh`(읽기 전 재생성) · `scripts/hermes_sync_fragments.py`(머리말)
- **신규 파일 목록**:
  - `docs/hermes-sync-guide.md` — 운반 켜기·다른 컴퓨터 합류·상태 확인 절차(명령 그대로)
  - `lib/tool_installers.sh` — 프리셋이 선언한 외부 바이너리(`REQUIRED_BINS`)를 확인·설치한다. 도구별 핀(버전·sha256) 표 포함. 공개 함수 2개
  - `tests/tool-installers-test.sh` — 픽스처 tar.gz 로 설치·해시 거부·무동작 실측(네트워크 0)
  - (테스트는 기존 `hermes-sync-test.sh`·`hermes-memory-events-test.sh` 에 절 추가 — 신규 없음)
- 룰: R3(모델 호출 0) · R-iface(기존 파일 공개 심볼 수 유지) · R-dep(`hermes-agent.py` tier 3 → `hermes_memory_view` tier 1 import 가능, 실측 `.deprc`)
- 데이터: 스키마 변경 없음. `MEMORY.md` 는 파생물(무시 유지).

## 5. 단계 (Steps)

### Step 1. MEMORY.md 재생성 연결 + 테스트(RED→GREEN) [Impl]
### Step 2. 기억 왕복 테스트(bare 원격·열쇠 픽스처) — 실패하면 운반 코드 수정 [Impl]
### Step 3. 켜기 절차 문서 + H-10 안내문 연결 [Docs]
### Step 4. 공장에서 켜고 두 clone 시연 · 머리말 정정 · 폐로 테스트 [Review]

## 6. 의사결정 로그

- 2026-09-19: 새 운반 경로를 만들지 않고 기존 `refs/hermes/sync` 를 쓴다 — 근거: C-14 가 그렇게 정했고 코드가 이미 그 모양이다. 빠진 건 호출·테스트·켜기뿐.
- 2026-09-19: MEMORY.md 재생성은 record 직후 + 세션 시작 둘 다 — 근거: record 직후만이면 pull 로 들어온 이벤트가 반영 안 되고, 세션 시작만이면 같은 세션 안의 `teach` 가 안 보인다.
- 2026-09-19: agent-teaching 의 착수 조건에 이 계획을 넣는다 — 근거: teaching 이 만드는 것이 곧 기억 이벤트라, 운반 없이는 한 컴퓨터에서만 배운 에이전트가 된다.

## 7. 발견·예외

- 2026-09-20 Step 1 완료: `hermes-agent.py refresh-memory [이름|id]`(DB·표 없으면 건너뜀) · `hermes-sync.py pull` 이 받은 기억의 에이전트만 재생성 ·
  세션 시작 훅이 읽기 전에 refresh 호출. 검증: `hermes-memory-events-test.sh` §6(6단언) · `hermes-soul-inject-test.sh` [6](4단언) · roster 51 · dep-contract 21 · install-closure 9 전부 통과.
- `rule_keys`(규칙 충돌 표시)를 제공하는 호출자가 운영 코드에 없다 — refresh 는 None 으로 부른다. 규칙 키 원천(설치된 룰 파일명?)은 별도 결정 필요.
- 기존 결함 수정: `tests/hermes-roster-test.sh` 의 `ig()` 가 git 2.25 `check-ignore -q` 의 부정 패턴 exit 0 을 "무시" 로 읽어 4단언이 항상 빨갰다 — `-v` 로 매치 패턴을 보고 판정하도록 고침.
- 환경: 이 컴퓨터에 `age` 가 없어 `hermes-sync-test.sh` 가 전제에서 멈췄다. 사용자: "필요한 도구면 setup·update-all 로 깔려야지 따로 설치하면 안 된다" → 목표 8 로 설치기에 넣음.
- 2026-09-20 Step 2·3 완료: `hermes-sync-test.sh` 11절 기억 왕복(11단언: 원격 3조각·본문 암호문·about 평문·B 적재 3·평문 복원·id 집합 동일·MEMORY.md pull 생성·철회 제외·A/B 동일·멱등) → 53/53.
  `hermes-propose-test.sh` 에 memory_events 미포함 단언(33/33). `hermes_sync_fragments.py` 머리말 정정. 안내서 `docs/hermes-sync-guide.md` + `hermes-keys.sh lock`(두 번째 컴퓨터 자물쇠만) 신설,
  `doctor`·H-10 문구가 설치기·안내서를 가리킴, 소우주 CLAUDE.md 에 "기억 운반" 절(hermes.conf).
- 목표 5(공장에서 실제 켜기)는 열쇠 생성이 T-11(세션 밖 사람) 이라 에이전트가 못 한다 — 사용자가 터미널에서 안내서 1단계를 실행해야 진행.
  → 2026-09-20 논의로 뒤집힘: 열쇠는 공개 저장소 옵션으로 강등(T-18), 비공개는 평문·설치기 자동(T-21). `docs/audits/2026-09-20-transport-keys-rethink.md`.
- 2026-09-20 목표 8 완료: `lib/tool_installers.sh`(핀 v1.3.2 · sha256 4플랫폼 · 대조 실패 시 미설치 · `HARNESS_TOOL_INSTALL=0` 옵트아웃) + `preset.sh` `REQUIRED_BINS` 칸 + hermes.conf 선언 +
  `project-claude.sh` 단계·요약 줄. 실측: terminal-shipping 재설치 로그 `tool → age v1.3.2 (linux-amd64, sha256 대조 통과) → ~/.local/bin` · `age --version` = v1.3.2.
  테스트: `tool-installers-test.sh` 10단언(네트워크 0). 설치기를 부르는 테스트 13개 + run-all 에 옵트아웃을 넣어 테스트가 다운로드를 타지 않게 함.
  Ubuntu 20.04 는 apt 에 age 가 없어 배포 파일 방식이 유일했다. Windows 는 핀이 없어 손 설치 안내만.

- 2026-09-20 목표 5 완료: 계획 transport-plain 의 시연(§7)으로 닫음 — 열쇠 없이 설치기가 켜고, 두 번째 컴퓨터가 pull 만으로 같은 MEMORY.md(마스킹 제외)를 얻는다.

## 8. 회고 (완료 시 작성)

- 잘된 것: "원본 에이전트가 기억을 잃으면 안 된다" 는 사용자 원칙 하나가 재생성 연결(목표 1)·왕복 테스트(2)·설치기 도구 설치(8)·그리고 운반 설계 자체의 재검토(transport-plain)까지 끌고 갔다. 각 단계가 테스트로 실측됐다.
- 잘못된 것: 처음에 "기억 운반 미구현" 이라 잘못 보고했다(코드는 있었고 호출·켜기가 없던 것). 열쇠 절차를 사람에게 넘기려다 두 번 지적받았다("따로 설치하면 되겠어?", "너무 일이 많아져") — 사람 손이 가는 절차는 설계 신호로 읽어야 했다.
- 다음 룰 후보: "파생 파일(MEMORY.md 등)은 원본 이벤트에서 재생성되는 호출자가 있어야 한다 — 호출자 0 인 생성기는 결함".

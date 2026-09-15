# 우주와 소우주 — 격리 원칙과 universe_id

> 작성일: 2026-09-15
> 목적: 모든 설계의 바탕인 "한 세계의 경계"를 정의한다.

## 개요

헤르메스의 기억·스킬·기록은 **소우주 하나 안에서만** 존재한다. 소우주는 설치 대상 저장소 하나다.
설치 공장인 우주는 설계도를 아래로 내려보내고, 소우주는 제안만 위로 올린다.

## 1. 정의 (확정)

| 이름 | 실체 | 예 |
|---|---|---|
| **우주 (설치 공장)** | `claude-harness-hermes` 저장소 | 규칙·스킬·훅·에이전트 설계도를 만들고 설치·전파한다 |
| **소우주** | 설치가 되는 저장소 하나 = 프로젝트 하나 | `zeroday-frontend`, `terminal-shipping` |

- 프론트엔드와 백엔드가 서로 다른 저장소라면 **서로 다른 소우주**다.
- 공장과 소우주의 관계는 "배포 — 수신"이지 "부모 — 자식"이 아니다.

```text
claude-harness-hermes (우주, 설계도 공장)
   │ 설치·전파 (아래로만)                  ▲ 제안 (GitHub 이슈로만)
   ▼                                        │
┌─ 소우주 A: zeroday-frontend ─┐   ┌─ 소우주 B: terminal-shipping ─┐
│ .hermes/  기억·스킬·기록     │   │ .hermes/  (A와 무관)           │
└──────────────────────────────┘   └───────────────────────────────┘
```

## 2. 격리 원칙 (확정)

1. 소우주의 기억은 그 소우주의 것이다. **다른 소우주의 정보와 겹치거나 맞물리면 안 된다(인커전 금지).**
2. 우주가 소우주 안을 들여다보지 않는다. 우주에 필요한 정보는 소우주가 **제안·신고로 올린다.**
3. 소우주 사이의 학습 전달은 사람이 승인한 제안(→ 우주 공통 스킬)으로만 일어난다. 기억은 옮기지 않는다.
4. 대화 원문은 그 소우주 저장소와 **그 저장소의 원격 주소** 밖으로 나가지 않는다([raw-transcript.md](../protection/raw-transcript.md)).
5. 사람(`human:`)은 여러 소우주에서 같은 id를 가진다. 사람은 실제로 여러 프로젝트에 걸쳐 일하므로 격리와 부딪히지 않는다([identity.md](../agent/identity.md)).

## 3. 폐기된 설계 — 회사 층

논의 초기에 "공통 직무 → 회사 → 팀 → 개인"을 두고, 여러 저장소를 묶는 회사 층을 따로 세웠다.
사용자가 **저장소 하나가 곧 프로젝트이자 소우주**라고 정의하면서 회사 층은 폐기됐다. 회사처럼 보이던
묶음은 프로젝트(소우주) 자체다.

> ⚠️ 이 논의 중 자동 결정화된 스킬 `.hermes/skills/repository-isolation-principle.md`는 회사 층 폐기를
> "저장소/프로젝트를 계층 구조로 설계하지 말 것(다층 체계 금지)"으로 **잘못 일반화**했다. 스킬 4층 구조와
> 모순되므로 정리 대상이다([open-questions.md](../../open-questions.md) Q-3).

## 4. 소우주 키 — universe_id (합의)

### 결정

- 설치할 때 한 번 만드는 UUID를 `<소우주>/.hermes/universe.id` 파일에 두고 **git으로 추적**한다.
- 모든 기록 행(세션, 스킬, 작업 이력, 결정)에 `universe_id`를 붙인다.

### 폴더 이름을 키로 쓰지 않는 이유

| 문제 | 설명 |
|---|---|
| 겹침 | 다른 경로에 같은 이름의 폴더가 있으면 두 소우주가 같은 키를 갖는다 |
| 바뀜 | 폴더 이름을 바꾸면 과거 기록과 끊긴다 |
| 이동 | 다른 컴퓨터에서 다른 경로로 clone해도 같은 소우주로 인식돼야 한다 |

## 5. 현재 코드의 상태 (2026-09-15 실측)

| 사실 | 위치 |
|---|---|
| 프로젝트 id를 폴더 이름(basename)으로 정한다 | `scripts/hermes-crystallize.py:393`, `scripts/hermes-save-session.py:57`, `scripts/hermes-summarize.py:248` |
| `skill_index` 테이블에 소우주 칸이 없다. 파일 절대경로가 사실상 키 | `.hermes/state.db` |
| `~/.hermes/global.db`의 `harness_rules`에 5개 소우주 기록 1142줄이 소우주 칸 없이 섞여 있다. 소우주 이름은 본문 문자열 `[zeroday-frontend] …` 안에만 있다 | 쓰기: `scripts/hermes-crystallize.py:369-387` |
| 위 1142줄을 **읽는 코드는 없다** (쓰기 전용) | `grep harness_rules` 결과 |
| 전역 그물망 `~/.hermes/mesh/skills/`는 비어 있으나(0개) 매 세션 검색 대상이다 | `scripts/hermes-search.py`, 훅 2곳 |

세부 수치와 확인 명령은 [current-state-audit.md](../../evidence/current-state-audit.md).

## 6. 이 원칙에서 따라 나오는 설계

| 원칙 | 적용 문서 |
|---|---|
| 우주는 들여다보지 않고 제안을 받는다 | [skill-layers.md](skill-layers.md), [skill-proposal-delivery.md](skill-proposal-delivery.md) |
| 공장 설치물이 소우주 안에서 몰래 공장 원본을 바꾸면 안 된다 | [copy-install.md](copy-install.md) |
| 기록은 소우주 원격 밖으로 나가지 않는다 | [sync-transport.md](../protection/sync-transport.md) |

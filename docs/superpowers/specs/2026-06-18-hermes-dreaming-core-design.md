# 헤르메스 드리밍 코어 설계 (①통합·결정화 + ②진화·삭제)

> 작성일: 2026-06-18
> 목적: 하루(또는 직전 드리밍 이후) 누적된 5슬롯 세션 요약을 읽어, 반복·지속된 중요한 것을 강하게 인식해 스킬로 결정화·진화하고, 불필요한 스킬은 삭제를 제안하는 드리밍 통합 엔진의 코어를 정의한다.

## 개요

A(롤링 요약 메모리)가 모든 핑퐁을 5슬롯 요약으로 보존하면, **그 누적 요약을 "자면서" 돌아보며 정리하는 것**이 드리밍(B)이다. 드리밍은 여러 능력의 묶음이며, 본 설계는 그중 **코어 두 가지**만 다룬다:

```
B 드리밍
├── ① 통합·결정화   하루 요약 → 중요한 것 강하게 인식 → 스킬 신규/강화   ← 본 설계
├── ② 진화·삭제     기존 스킬 개선 / 불필요 스킬 삭제 제안              ← 본 설계
├── ③ 기억 망각·압축  Tier + tombstone 강등                            ← 후속 spec
└── ④ 그래프 형성    노트 [[링크]] = 옵시디언 뇌                        ← 후속 spec
```

### 핵심 원칙: 드리밍은 오케스트레이터다

헤르메스에는 이미 액추에이터가 존재한다 — 결정화(`hermes-crystallize.py`), 진화(`hermes-evolve-skill.py`), 정리(`hermes-cleanup.py`). 드리밍은 이것들을 **다시 만들지 않고**, 무엇을 결정화/진화/삭제할지 판단해 **구동만** 한다. 차이는 입력이다: 기존 파이프라인은 `session_history`의 토큰 빈도를 보지만, 드리밍은 A가 만든 **이미 증류된 5슬롯 요약**(신호 품질이 높음)을 읽는다.

### 조용한 날은 정상이다

매일 결정화할 것이 있으리란 법은 없다. **억지로 만들면 그것이 곧 junk**이며 헤르메스가 가장 경계하는 오염이다. 따라서 "오늘은 만들 게 없다"고 판단하고 조용히 끝나는 것도 **정상 결과**다(기존 3세션 임계·SKIP 게이트 철학과 동일).

```
요약 0건(그날 작업 없음)        → 즉시 스킵. dream_log 도 안 남김
후보는 있으나 게이트 전부 SKIP   → 결정화/진화 강제하지 않음
                                  dream_log 에 0건 실행만 기록
                                  리포트: "조용한 날 — 결정화할 것 없음" 한 줄
```

## 범위

| 포함 (B 코어) | 제외 (후속 spec) |
|---|---|
| 직전 드리밍 이후 요약 수집·후보 추출 | ③ 기억 망각·압축(Tier+tombstone) |
| Haiku 게이트로 결정화/진화/삭제 판정 | ④ 노트 `[[링크]]`·그래프 형성 |
| additive(결정화·진화) 자동 적용 | 크로스 프로젝트(global.db) 통합 |
| 삭제는 리포트 제안 + `--apply` 게이트 | DB 운영 이전(Postgres/Neo4j) |
| cron 자율 + `/hermes-dream` 수동 | |

## 아키텍처

```
[트리거]
  cron (기존 hermes-cron-run.sh 확장, 일 1회)  ─┐
  /hermes-dream (수동, dry-run 기본)           ─┤
  /hermes-dream --apply (삭제 제안 실행)        ─┘
                          │
                          ▼
              scripts/hermes-dream.py
  1. 직전 드리밍 이후 요약 수집 (dream_log.MAX(run_at) 기준)
  2. 후보 추출 (규칙 — 모델 0):
       decisions·facts 반복/지속  → 결정화 후보
       prefs 반복                 → 규칙 후보
       요약 속 사용자 정정         → 진화 후보 (기존 hint 추출 재사용)
       명백한 junk 스킬            → 삭제 후보
  3. LLM 게이트 (Haiku): 후보별 '재사용 지식인가' SKIP/채택
  4. 액추에이터 구동:
       결정화 → hermes-crystallize.py    (additive, 자동)
       진화   → hermes-evolve-skill.py   (개선, 자동·기존 쿨다운)
       삭제   → 실행 안 함. 리포트에 '삭제 제안'으로만 기록 (게이트)
  5. 드림 리포트 .md 작성 → .hermes/dreams/<날짜>.md  (옵시디언에서 사람이 읽음)
  6. dream_log 에 이번 실행 기록
```

새 Hook은 만들지 않는다(헤르메스 §10·§11). 드리밍은 Hook이 아니라 cron·수동 명령으로 구동되는 배치 작업이다.

## 입력

- **주 입력**: 이 프로젝트 `.hermes/state.db`의 `session_summary` 중 **직전 드리밍 이후 갱신분**(`updated_at > last_dream_at`). `last_dream_at = MAX(dream_log.run_at)`, 없으면 전체.
- **보조**: 원본 `session_history`(증거 교차검증 — 요약의 "요약의 요약" 유실 보완), `skill_index`(진화·삭제 대상 파악).
- **스코프**: 프로젝트 단위. 크로스 프로젝트 통합은 후속 spec.

## "강하게 인식"의 구체화

사용자 의도 "중요한 것을 강하게 인식" = **하루 요약에서 반복·지속된 `decisions`/`facts`를 결정화 후보로 승격**시키는 것. 이미 해당 스킬이 있으면 진화로 보강하고, 없으면 신규 결정화한다.

## 데이터 접근 경계 (DB 이전 대비)

헤르메스 기존 코드는 `connect_db` + 원시 SQL을 파일마다 복제한다. 전면 추상화는 범위 폭증(YAGNI 위반)이므로 하지 않는다. 대신 **신규 `hermes-dream.py` 안에서 모든 DB 접근을 한 곳(데이터 접근 함수 묶음)에 모은다.** 나중에 PostgreSQL 등으로 이전할 때 *이 파일의 그 구역만* 수정하면 되도록 한다(사용자 규칙 `coding-style.md` Repository 패턴과 일치).

> **이전은 future 과제**: 다중 사용자 동시성·서버 호스팅·여러 컴퓨터 동기화가 필요해지면 관계형 테이블을 Postgres로(FTS5→`tsvector`/`pg_trgm`, `PRAGMA` 제거), 그래프(④)가 무거워지면 Neo4j 또는 Postgres+Apache AGE를 검토한다. 본 설계 범위 밖.

## 스키마 (`.hermes/state.db`, SQLite)

```sql
CREATE TABLE dream_log (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  run_at          DATETIME DEFAULT CURRENT_TIMESTAMP,
  summary_count   INTEGER,   -- 이번에 읽은 요약 수
  crystallized    INTEGER,   -- 결정화 건수
  evolved         INTEGER,   -- 진화 건수
  delete_proposed INTEGER,   -- 삭제 제안 건수
  report_path     TEXT       -- 드림 리포트 .md 경로 (조용한 날은 NULL 가능)
);
```

`last_dream_at` 은 별도 컬럼 없이 `MAX(run_at)` 으로 도출한다. 마이그레이션은 `CREATE TABLE IF NOT EXISTS`.

## 산출물 (하이브리드 유지)

- **상태·통계** → `dream_log`(SQLite, 기계가 읽음).
- **드림 리포트** → `.hermes/dreams/<날짜>.md`(옵시디언에서 사람이 읽음): 무엇을 결정화/진화했고 무엇을 삭제 제안하는지. 조용한 날은 한 줄 리포트 또는 생략.
- **실제 스킬 변경** → 기존 액추에이터가 `.hermes/skills/*.md` 와 `skill_index` 에 반영.

## 안전·자율 모델

| 동작 | 위험도 | 처리 |
|---|---|---|
| 결정화(추가) | 낮음(additive) | cron 자동 적용 |
| 진화(개선) | 중간(기존 버전 보존·쿨다운) | cron 자동 적용 |
| 삭제·강등 | 높음(파괴적) | **자동 실행 안 함.** 리포트에 제안만. `/hermes-dream --apply` 로만 실행(기존 cleanup dry-run/apply 패턴 재사용) |

모든 LLM 호출은 Haiku(`claude-haiku-4-5-20251001`) + `HERMES_DISABLED=1`. 비차단, 에러는 `.hermes/hooks.log`.

## 신규/수정 파일

| 파일 | 책임 | 신규/수정 |
|---|---|---|
| `scripts/hermes-dream.py` | 드리밍 코어: 요약 수집 + 후보 추출 + Haiku 게이트 + 액추에이터 구동 + 리포트 + DB접근 집중 | 신규 |
| `assets/skills/hermes-dream/SKILL.md` | `/hermes-dream`(드림 1회) / `--apply`(삭제 제안 실행) | 신규 |
| `scripts/hermes-init.py` | `dream_log` 스키마 추가 | 수정 |
| `scripts/hermes-cron-run.sh` | 일 1회 드리밍 잡 연결 | 수정 |
| `tests/hermes-pipeline-test.sh` | 드리밍 회귀(결정화 구동·조용한 날·삭제 게이트·--apply) | 수정 |

`hermes-dream.py`가 500줄에 근접하면 후보 추출(`hermes-dream-extract.py`)과 오케스트레이션을 분리한다.

## 에러 처리

- 요약 수집 0건 → 즉시 정상 종료(로그만).
- 게이트 전부 SKIP → 강제 생성 없이 0건 기록.
- 액추에이터(crystallize/evolve) 실패 → 해당 건만 건너뛰고 리포트에 실패 기록, 드리밍 자체는 계속.
- DB 잠금 → 기존 `busy_timeout`+`WAL` 로 대기. 실패 시 다음 실행에서 재시도(요약은 그대로 남아 있음).

## 테스트

`tests/hermes-pipeline-test.sh` 확장(mock claude 재사용):

1. 요약 N건 주입 → 드리밍 실행 → 결정화 액추에이터 구동, `dream_log` 1행 기록 검증.
2. **조용한 날**: 요약 0건/전부 SKIP → 강제 생성 없음, junk 스킬 0개 검증.
3. **삭제 게이트**: junk 스킬 존재 → 드리밍 dry-run 은 삭제 안 함(리포트에 제안만) 검증.
4. **`--apply`**: 리포트의 삭제 제안 실행 → 해당 스킬 삭제 검증.
5. 델타: 직전 드리밍 이후 갱신분만 읽음(`last_dream_at` 기준) 검증.
6. 드림 리포트 `.hermes/dreams/*.md` 생성 검증.

LLM 호출은 mock claude 로 결정적 검증.

## 후속 spec과의 경계

- **③ 기억 망각·압축**: 본 코어가 "무엇이 중요한가"를 판단하는 토대를 제공하면, 그 위에서 오래된 요약을 Tier 강등·tombstone 처리. (A 스펙 `B가 다룰 기억 망각·압축` 절 참조)
- **④ 그래프 형성**: 드림 리포트·스킬 사이의 `[[링크]]` 연결로 옵시디언 그래프(뇌) 구성.
- **크로스 프로젝트 통합**: 프로젝트별 드리밍 결과를 `~/.hermes/global.db` 로 모으는 단계.

## 미해결 / 추후 결정

- 결정화 후보의 "반복·지속" 판정 기준(몇 회/며칠) — 구현 시 실제 요약량 측정 후 결정(매직넘버 금지).
- cron 실행 시각·주기 — 기존 `hermes-cron-guide.md` 관례에 맞춰 설치 시 결정.

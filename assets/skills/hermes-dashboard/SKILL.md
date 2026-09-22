---
name: hermes-dashboard
description: 소우주(현재 프로젝트)의 에이전트·스킬·학습 루프·건강 현황을 정적 HTML 한 장으로 만들어 경로를 알린다. 사용자가 `/hermes-dashboard` 를 치거나 "대시보드 보여줘", "현황 페이지", "에이전트 상황 한눈에", "스킬 상태 보고서", "지금 소우주 어때" 처럼 전체 상황을 한 페이지로 보고 싶어 할 때 반드시 이 스킬을 쓴다. `--universe` 는 공장에서 설치된 소우주 전부를 한 표로 본다. 모델 호출 0, 외부 자원 0, 보기 전용.
---

# hermes-dashboard

소우주 상태를 **한 페이지**로 본다. `/hermes-status` 는 텍스트 몇 줄, 루프 보고서는 루프 1건 전용인데 이 페이지는 네 판을 한꺼번에 담는다:

| 판 | 내용 |
|---|---|
| 에이전트 | 명부(이름·상태·분야/직급/조직), 열린·막힌 인계, 최근 소환 10, 담당 없음 제안 수, **about 별 리뷰 지적 누적**(3회면 결정화 임계) |
| 스킬 | 네 층(universe·common·unit·agent) 개수, 주입 상위 10·도움률, 강등 후보(`hermes-cleanup` 과 같은 기준), 결정화 대기 |
| 학습 루프 | 세션 요약 수, 드림 실행·진화·결정화 수, 마지막 드림·다음 가능 시각 |
| 건강 | 게이트 발화율 상위 5, 리뷰 빚 파일, 활성 계획 |

## 트리거

`/hermes-dashboard` · "대시보드 보여줘" · "현황 한눈에" · "지금 소우주 상태". 대상은 **현재 프로젝트** — 어느 프로젝트인지 묻지 않는다.

## 동작 순서

1. 생성한다:
   ```bash
   python3 scripts/hermes-dashboard.py --project-dir .
   ```
2. 출력된 경로(`.hermes/dashboards/dashboard.html`)를 사용자에게 알린다. 브라우저 열기는 사용자 몫 — 세션은 파일을 열지 않는다.
3. 페이지에서 눈에 띄는 것 **셋 이내**를 한 줄씩 짚는다(예: 강등 후보 N개, 막힌 인계 N건, 결정화 임계에 닿은 about). 페이지 내용을 다시 나열하지 않는다.

우주 전체(공장에서만):
```bash
python3 scripts/hermes-dashboard.py --universe      # → .hermes/dashboards/universe-dashboard.html — 소우주별 에이전트·스킬·도움률·강등 후보·드림·factory 일치
```

## 자동 갱신

세션 시작 훅(`claude-sessionstart-dashboard.sh`)이 **하루 1회** 백그라운드로 다시 만든다(마커 `.hermes/dashboard-last-run`, 드림 throttle 과 같은 방식).
끄기: `HERMES_DASHBOARD_ON_SESSION_START=0`. 간격: `HERMES_DASHBOARD_THROTTLE_HOURS`.

## 원칙

- **보기 전용.** 여기서 입사·강등·정리를 실행하지 않는다 — 그건 `hermes-agent`·`hermes-cleanup`·`hermes-dream` 의 일이다.
- 기준을 다시 정의하지 않는다. 강등 후보·열린 인계·발화율은 각각 정본 모듈을 그대로 부른다.
- `state.db` 가 없으면 페이지는 만들어지되 "미설치" 안내만 담긴다 — hermes 프리셋 설치를 안내한다.

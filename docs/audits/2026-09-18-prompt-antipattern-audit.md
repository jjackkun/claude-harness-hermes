# 규칙·스킬 문구 안티패턴 감사 (2026-09-18)

> 목적: `backlog/platform-cost-performance-levers.md` C4 — Claude Platform 비용 글이 꼽은 프롬프트 안티패턴이 이 저장소의
> 공통 자산(`assets/rules`·`assets/skills`)과 매 턴 주입 텍스트에 얼마나 있는지 센다. **자산 수정 0** — 고칠지는 사용자 승인 뒤.
> 방법: `prompt-audit` 스킬이 미설치(플러그인 캐시·마켓플레이스 어디에도 없음)라 어휘 정규식으로 수동 감사. 글의 5종 중
> grep 으로 셀 수 있는 3종만(검증 의식·강조 명령·옛 모델 예시). "고정 절차 스캐폴드"·"모순 규칙" 은 어휘로 못 잰다.

## 결과

| 대상 | 파일 | 검증 의식 | 강조 명령 | 옛 모델 예시 |
|---|---:|---:|---:|---:|
| `assets/rules/**/*.md` + `assets/skills/**/SKILL.md` | 83 (해당 22) | 2 | **46** | **2** |
| 매 턴 주입(UserPromptSubmit dispatch 출력, 2,990 B) | — | 0 | 0 | 0 |

강조 어휘 분포: `반드시` 11 · `CRITICAL` 9 · `ALWAYS` 9 · `NEVER` 9 · `절대` 3. 검증 의식: `재확인` 2.
옛 모델: `rules/common/performance.md` 의 "Sonnet 4.6"·"Opus 4.5"(모델 선택 표 — 현재 최신은 Claude 5 계열이라 사실 자체가 낡음).

상위 파일:

| 파일 | 검증 | 강조 | 옛모델 | 비고 |
|---|---:|---:|---:|---|
| `skills/impeccable/SKILL.md` | 0 | 6 | 0 | 외부 스킬(사용자 설치본 사본) |
| `rules/common/coding-style.md` | 0 | 5 | 0 | "ALWAYS create new objects, NEVER mutate" 류 |
| `rules/harness/rules.md` | 1 | 3 | 0 | R5·R6 "반드시" — 실패 사례에서 온 강제 |
| `skills/frontend-design/SKILL.md` | 0 | 4 | 0 | 외부 스킬 |
| `rules/common/security.md` | 0 | 3 | 0 | "NEVER hardcode secrets" |
| `skills/coding-standards/SKILL.md` | 0 | 3 | 0 | |
| `skills/harness-promote-rule/SKILL.md` | 0 | 3 | 0 | |
| `skills/hermes-agent/SKILL.md` | 0 | 3 | 0 | "반드시 이 스킬을 쓴다"(트리거 문구) |
| `skills/skill-creator/SKILL.md` | 0 | 3 | 0 | 외부 스킬 |
| `rules/common/performance.md` | 0 | 0 | 2 | 모델 선택 표가 4.x 세대 |

## 해석

- **매 턴 비용에 직접 얹히는 주입 텍스트는 깨끗하다**(0/0/0). 글이 경고한 "매 요청 입력 토큰이 되는 안티패턴" 은 이 저장소에 없다.
- 강조 46건은 세션 시작 시 한 번 로드되는 규칙·스킬에 있다. 이 가운데 상당수는 **실패 사례에서 나온 강제**다
  (`rules.md` R5 우회 금지, `hermes-agent` 트리거, `run-to-the-end`). 글의 권고("강조 대문자는 신형 모델에 역효과")를 그대로
  적용해 지우면 그 사례가 재발할 수 있다 — 지우기 전 문구의 출처 계획서·감사 기록을 확인해야 한다(backlog 의 주의 그대로).
- 즉시 고칠 가치가 있는 것은 하나: `rules/common/performance.md` 의 모델 선택 표(옛 세대). 사실 오류이지 문체 문제가 아니다.

## 권고 (사용자 승인 대상, 이 감사에서는 실행하지 않음)

1. ~~`rules/common/performance.md` 모델 표를 현재 세대(Fable 5.1 · Opus 5 · Sonnet 5 · Haiku 4.5)로 갱신.~~ **완료(2026-09-18, 사용자 승인)** —
   근거 없는 수치("90% of Sonnet"·"3x")는 뺐다. 재측정 옛모델 0. 이 파일은 소우주로 복사되지 않고 `~/.claude/rules/common/` 전역
   사본으로 로드되므로 전역 사본도 같은 내용으로 맞췄다(새 세션부터 적용).
2. 강조 문구는 파일별로 "출처 있음/없음" 을 가른 뒤, 출처 없는 것만 평서문으로 — 외부 스킬(impeccable·frontend-design·
   skill-creator) 사본은 상류가 바뀌면 덮이므로 손대지 않는다.
3. 어휘로 못 재는 두 종(고정 절차 스캐폴드·모순 규칙)은 `prompt-audit` 스킬이 설치되면 그때 돌린다.

## 재측정

```bash
python3 - <<'PY'
import re, glob, collections
PATS = {"검증": re.compile(r"두 번 확인|다시 확인|재확인|double[- ]check", re.I),
        "강조": re.compile(r"반드시|절대|\bMUST\b|\bNEVER\b|\bALWAYS\b|\bCRITICAL\b|\bIMPORTANT\b"),
        "옛모델": re.compile(r"Opus 4\.\d|Sonnet 4\.\d|Haiku 3|claude-3-")}
files = glob.glob("assets/rules/**/*.md", recursive=True) + glob.glob("assets/skills/**/SKILL.md", recursive=True)
tot = collections.Counter()
for f in files:
    t = open(f, encoding="utf-8", errors="ignore").read()
    for k, p in PATS.items(): tot[k] += len(p.findall(t))
print(dict(tot))
PY
```

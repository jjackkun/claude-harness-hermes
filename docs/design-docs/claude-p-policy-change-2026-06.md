# Claude 프로그래밍 방식 사용 정책 변경 대응

작성일: 2026-05-15  
검토 예정일: **2026-06-30** (정책 시행 15일 후)

---

## 배경

Anthropic은 2026년 6월 15일부터 `claude -p`, Claude Agent SDK, GitHub Actions 등
프로그래밍 방식 사용을 **별도 월간 크레딧** 체계로 분리한다.

| 플랜 | 월간 크레딧 |
|------|-----------|
| Pro ($20) | $20 |
| Max 5x ($100) | $100 |
| Max 20x ($200) | $200 |

- 크레딧 소진 후에는 Extra Usage 설정을 켜야 API 요금으로 계속 사용 가능
- 미사용 크레딧은 다음 달로 이월되지 않음
- **적용 제외**: 터미널/IDE에서의 대화형 Claude Code 사용 (기존 구독 한도 유지)

---

## 현재 프로젝트 내 영향 범위

| 파일 | 방식 | 영향 |
|------|------|------|
| `scripts/hermes-search.py` | `claude -p` (FTS5 미스 시만 실행) | 낮음 |
| `scripts/hermes-evolve-skill.py` | `claude -p` (스킬 진화 시) | 중간 |
| `assets/skills/skill-creator/scripts/improve_description.py` | `claude -p` | 낮음 |
| `assets/skills/skill-creator/scripts/run_eval.py` | `claude -p` | 낮음 |

Max 20x 기준 월 $200 크레딧 → 약 2,200회 호출 여유. 현재 사용 패턴으로는 문제없을 가능성이 높음.

---

## 잠재적 우회 아이디어 (검증 필요)

### pexpect를 이용한 대화형 세션 자동화

**원리**: `claude -p` 대신 대화형 `claude`를 PTY(가짜 터미널)로 실행해,
Anthropic 서버가 "사람이 직접 입력하는 세션"으로 인식하게 만드는 방법.

```python
import pexpect

def run_claude_task(prompt):
    child = pexpect.spawn('claude', encoding='utf-8')
    child.expect('>', timeout=30)
    child.sendline(prompt)
    child.expect('>', timeout=300)
    output = child.before
    child.sendline('exit')
    return output
```

**장점**: 대화형 모드로 인식되면 월간 크레딧이 아닌 기존 구독 한도 사용.

**리스크**:
- `CLAUDE_CODE_ENTRYPOINT` 환경변수로 실행 방식을 이미 추적 중 (`observe.sh` Layer 1 참고)
- Anthropic이 PTY 기반 실행을 감지해 크레딧 차감 대상으로 분류할 가능성 있음
- Claude Code 업데이트 시 프롬프트 패턴 변경으로 `child.expect('>')` 깨질 수 있음
- 이용약관 위반 소지

**결론**: 기술적으로는 가능하나, 언제 막힐지 모르는 불안정한 방법. 프로덕션 의존 비권장.

---

## 2026-06-30 검토 항목

6월 15일 정책 시행 후 2주가 지난 시점에 아래를 조사한다:

- [ ] pexpect 우회 방식이 실제로 통하는지 커뮤니티 보고 확인
- [ ] Anthropic이 추가 대응(PTY 감지 등)을 했는지 확인
- [ ] 개발자 커뮤니티(Reddit, HN, GeekNews 등)의 대처 사례 수집
- [ ] 실제 크레딧 소진 속도 측정 (현재 사용 패턴 기준)
- [ ] 필요 시 플랜 업그레이드 또는 `claude -p` 호출 최적화 검토

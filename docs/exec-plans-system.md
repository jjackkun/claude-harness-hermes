# 작업 기록 시스템 (exec-plans)

> PDF 5~6쪽 "리포지터리 지식을 기록 시스템으로 만듦" 구현

## 개요

에이전트가 세션 간 작업을 이어갈 수 있도록, 진행 중인 계획과 완료된 기록을
리포지터리 안(`docs/exec-plans/`)에 저장한다.
`.claude/memory/`의 핸드오프 파일 대신 git에 커밋되는 계획 문서가 세션 연속성의 원천이다.

## 폴더 구조

```
docs/
├── exec-plans/
│   ├── template.md          ← 새 계획 작성 시 복사
│   ├── active/              ← 진행 중인 작업
│   │   └── YYYY-MM-DD-<slug>.md
│   └── completed/           ← 완료된 작업 (의사결정 로그 보존)
│       └── YYYY-MM-DD-<slug>.md
├── design-docs/             ← 설계 결정, 불변 원칙(R 룰)
│   └── core-beliefs.md
└── audits/                  ← 조사/감사 기록
    └── YYYY-MM-DD-<slug>.md
```

## 생명주기

```
작업 시작 → template.md 복사 → active/YYYY-MM-DD-<slug>.md 작성
    ↓
작업 중 → 체크박스 [x] 체크 + 의사결정 로그(§6) 추가
    ↓
작업 완료 → 회고(§8) 작성 → git mv active/ → completed/
```

## 강제 장치 (hooks)

### 1. 세션 시작 알림 — UserPromptSubmit hook

`claude-userpromptsubmit-reminders.sh`에서 매 턴:
- `docs/exec-plans/active/`에 `.md` 파일이 있으면 목록 출력
- 에이전트에게 "먼저 읽고 이어가세요" 알림

**효과**: 세션 시작 시 이전 작업을 자동으로 인지

### 2. 완료 계획 이동 강제 — pre-commit hook

`pre-commit.sh`의 R-plan 검사:
- `active/`의 `.md` 파일에서 체크박스를 스캔
- 전부 `[x]`인데 아직 `active/`에 있으면 **커밋 차단**
- 에이전트에게 `git mv` + 회고 작성 지시

**효과**: 완료된 계획이 active에 방치되는 것을 방지

### 3. 계획 없음 경고 — pre-commit hook

`pre-commit.sh`의 R-plan-missing 검사:
- 코드 파일을 수정했는데 `active/`에 계획이 없으면 **경고** (차단 아님)
- 단순 버그 수정은 무시 가능, 비자명한 작업은 계획 작성 유도

**효과**: 작업 기록 누락 방지 (강제가 아닌 리마인드)

## CLAUDE.md 규칙

`harness.conf`가 CLAUDE.md에 다음 규칙을 주입:

```markdown
## 작업 기록 시스템 (PDF 5~6쪽)

1. 비자명한 작업 시작 전 active/ 에 계획 작성
2. 작업 완료 시 회고 작성 후 completed/ 로 이동
3. 세션 시작 시 active/ 에 문서가 있으면 먼저 읽고 이어감
4. .claude/memory/ 핸드오프 파일 대신 docs/exec-plans/ 사용
```

## 설치

`setup.sh` 실행 시 harness 프리셋 선택하면 자동 설치:
1. `docs/exec-plans/active/`, `completed/` 폴더 생성 (`.gitkeep`)
2. `template.md` 복사
3. hooks에 R-plan, R-plan-missing 검사 포함
4. CLAUDE.md에 규칙 섹션 주입

## 기존 핸드오프에서 전환

`.claude/memory/`의 핸드오프 파일 → `docs/exec-plans/active/`로 내용 이동 후 삭제.
memory는 사용자 프로필, 피드백 등 **세션 간 불변 정보**만 저장.
작업 진행 상황은 **exec-plans**가 담당.

## FAQ

**Q: 단순 1줄 버그 수정도 계획을 써야 하나?**
A: 아니요. R-plan-missing은 경고만 하고 차단하지 않습니다. 단순 수정은 무시하세요.

**Q: 계획이 여러 세션에 걸치면?**
A: active/에 계속 둡니다. 매 세션 시작 시 hook이 알려주고, 에이전트가 이어갑니다.

**Q: 체크박스를 안 쓰면?**
A: R-plan 검사가 체크박스 기반이므로, 목표(§2)에 체크박스를 사용해야 자동 완료 감지가 됩니다.

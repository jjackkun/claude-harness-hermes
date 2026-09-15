# 공개 스킬·도구 조사 — 민감정보 암호화·마스킹

> 작성일: 2026-09-15
> 목적: 우리 설계와 같은 일을 하는 공개 스킬·도구가 이미 있는지 확인하고, 재사용할 부분과 직접 만들 부분을 가른다.

## 개요

- 조사 에이전트 두 개가 웹 검색 후 원본 README·SKILL.md·소스를 WebFetch로 열어 확인했다.
- **한계:** WebFetch는 요약 모델을 거친다. 별 수·커밋 수·날짜 같은 수치는 원문 그대로 확인하지 못했다. 열지 못한 페이지는 "미확인"이다. 채택 전에는 설치된 규칙 `verify-external-skill-scope`에 따라 실제 코드를 직접 열어 확인한다.
- **결론:** 우리 설계를 통째로 대신할 공개 스킬은 없다. age 기반으로 직접 구현하고, 아래 조각은 참고만 한다(확정).

## 1. 설계 항목별 결론

| 우리 설계 | 이미 있는 것 | 우리가 가진 것 | 직접 만들 것 |
|---|---|---|---|
| 금고본 (턴 통째 암호화, 소우주 × 사람 키) | age, enclaude의 봉인·해제 훅 흐름 | — | 키 단위, 턴 조각, `refs/hermes/sync` 운반 |
| 공개본 (기계 제안 → 사람 승인 → 검은 박스) | 없음. 가장 가까운 것은 specstory-guard(막으면 사람이 직접 고침) | — | 전부 |
| 로컬 마스킹 — 형태 기반 | Betterleaks/gitleaks, Entire CLI 가림 계층 | `hermes_redact.py` | 엔진 교체 검토 |
| 로컬 마스킹 — `.env` 실제 값 대조 | **조사한 19개 후보 중 없음** | `hermes_secret_values.py` | — |
| 원문 없는 작업 이력 스키마 | 없음 | — | 전부 |

## 2. 파일 암호화 도구

| 도구 | 사람별 키 | 추가 전용 조각 | 키 교체 | 판정 |
|---|---|---|---|---|
| **age** | 됨 (`-r` 반복, `-R` 수신자 파일, X25519·ssh 키·플러그인) | 잘 맞음 (파일 단위, 스트리밍) | 교체 명령 없음, 새 수신자로 재암호화 | **1순위** |
| pyrage (age Python 바인딩) | 됨 | 맞음 | age와 같음 | 1순위 후보 (Python 3.10+) |
| SOPS | 됨 (age·PGP·KMS, key group) | 가능하나 설정 파일 편집용이라 과함 | `updatekeys`, `rotate` | 과함 |
| git-crypt | GPG 사용자 추가 | **부적합** | 이미 준 접근 철회 불가(README 명시) | 부적합 |
| transcrypt | 안 됨 (저장소 공유 비밀번호) | **부적합** | `--rekey` 전체 재암호화 | 부적합 |
| git-remote-gcrypt | GPG participants | 안 맞음 (원격 전체 암호화, 매 push가 사실상 force) | participants 변경 | 부적합 |
| `cryptography` Fernet/AES-GCM | 안 됨 (대칭키만) | 맞음 (Fernet은 큰 파일 부적합) | `MultiFernet.rotate()` | 암호 설계를 직접 책임져야 함 |

**필터 방식(git-crypt, transcrypt)이 부적합한 이유:** `.gitattributes` clean/smudge 필터로 동작한다. git 공식
문서상 `git hash-object --stdin`은 `--path` 없이 쓰면 필터를 적용하지 않는다. 비-브랜치 참조에 저수준으로
커밋하면 **암호화가 조용히 빠져 평문이 원격에 올라갈 수 있다.**

## 3. 비밀·개인정보 탐지 도구

| 도구 | 방식 | 한국어 | 딱지 없는 `아이디 \| 비번` | 호출 |
|---|---|---|---|---|
| gitleaks | 정규식·엔트로피·키워드, TOML 사용자 규칙, stdin, `--redact` | 전용 규칙 없음 | 기본 규칙으로 어려움(추정) | Go 바이너리. README에 "기능 완성, 보안 패치만" |
| Betterleaks | gitleaks 원작자 후속작. 정규식·엔트로피·BPE 필터·검증 호출, MIT | 미확인 | BPE 필터가 유리할 수 있음(미검증) | CLI |
| trufflehog | 800종 이상 탐지기, 실제 로그인 검증 | 없음 | 서비스 키 위주라 약함 | CLI, **AGPL-3.0** |
| detect-secrets (Yelp) | 정규식 플러그인·고엔트로피·KeywordDetector | 없음 | 딱지 없으면 약함 | **Python API**, Apache-2.0, 최신 1.5.0(2024-05) |
| Microsoft Presidio | NER·정규식·문맥 단어·체크섬 | 한국 인식기(KR_RRN, KR_FRN, KR_BRN, KR_PASSPORT, KR_DRIVER_LICENSE), 기본 비활성 | 비밀번호 엔티티 없음 | Python |
| ko-pii (Marker-Inc-Korea) | 체크섬·정규식·사전·키워드 앵커, 오프라인 | 한국어 전용 33종 | 자격증명 언급 없음 | Python, MIT |

- **딱지 없는 `아이디 | 비번` 형태를 확실히 잡는다고 명시한 도구는 없다.** 이 형태는 자체 규칙과 `.env` 값 대조로 잡아야 한다.
- 조합 후보: Betterleaks(또는 gitleaks) 규칙 형식 + 한국어 개인정보 라이브러리 + 자체 규칙. 외부 바이너리 없이 Python 안에서만 돌리려면 detect-secrets.

## 4. 공개 스킬·플러그인

### 세션 기록 암호화 동기화

| 이름 | 하는 일 | 우리 원칙과의 차이 |
|---|---|---|
| enclaude (`github.com/coredipper/enclaude`, MIT) | `~/.claude/` 전체를 age로 봉인해 `~/.enclaude/` git에 올림. SessionStart에 풀고 SessionEnd에 봉인·push. 키는 OS 키체인, 암호 잠금 백업 `key.age.backup`을 저장소에 함께 올림 | **모든 프로젝트를 한 저장소에 섞어 다른 주소로 올린다**(소우주 격리·원문 경계 위반). 키가 사용자 전역. 백업 열쇠가 저장소 안 → **참고만** |
| claude-device-sync (`github.com/hmennen90/claude-device-sync`, MIT) | 세션·메모리를 `.enc`로 개인 git 저장소에 올림, 팀 모드 사용자별 공간 | 초기 단계. 마스킹·공개본 없음 |
| claude-code-sync (porkchop, MIT) | 셸 스크립트로 대화를 git 동기화, 선택적 git-crypt | 저장소 단위 공용 키, 필터 방식 |
| claude-code-sync (FelixIsaac, MIT) | 설정만 동기화, 세션 원문 제외 | 원문을 다루지 않음 |
| claude-sync (tawanorg, MIT) | gzip + age로 R2·S3·GCS·WebDAV에 업로드 | git 원격 아님 |
| cs / claude-sessions (hex, MIT) | 비밀값을 age 파일에 두고 기기별 파일 `.cs/secrets.<machine-id>.age.enc`로 동기화. 인계 문서의 자격증명은 LLM 지시로 뺌 | 기기별 파일 병합은 참고할 만함. LLM 지시 레닥션은 보장 없음 |
| agentexport (MIT) | 세션 원문을 AES-256-GCM으로 암호화해 R2에 올리고 URL 조각으로 키 공유 | 마스킹·미리보기 없음 |

### 세션 기록을 git에 넣으며 가리는 도구

| 이름 | 하는 일 | 우리 원칙과의 차이 |
|---|---|---|
| Entire CLI (`github.com/entireio/cli`, MIT) | git 훅으로 에이전트 세션을 `refs/entire/checkpoints/...`에 저장. 엔트로피·Betterleaks·연결 문자열 등 가림 계층, 선택적 모델 필터. 스스로 "best-effort" | **가린 평문을 원격에 올리는 구조 — 8월 사고와 같은 위험.** 가리지 않은 원본이 임시 섀도 브랜치에 남는다고 경고. 암호화·값 대조·승인 없음 |
| SpecStory CLI | 세션을 `.specstory/history` 마크다운으로 저장, Betterleaks로 가림 | 값 대조·암호화 없음 |
| specstory-guard (SKILL.md, Apache-2.0) | `.specstory/history`만 검사하는 pre-commit, 정규식으로 찾으면 커밋 차단, 사람이 직접 `[REDACTED]`로 고침 | 공개본 승인 게이트의 뼈대로 참고. 기계 제안 → 승인 흐름은 아님 |

### 커밋 전 탐지·앞단 방어

| 이름 | 하는 일 |
|---|---|
| agent-guard (JeongJaeSoon, MIT) | Claude Code·Codex 플러그인 + git 훅. gitleaks로 도구 실행 전 차단·출력 가림·변경 후 재검사 |
| implementing-secret-scanning-with-gitleaks (SKILL.md) | gitleaks 설치 절차 안내 문서형 스킬 |
| claude-code-hooks protect-secrets (karanb192, MIT) | `.env`·SSH 키 등 파일 읽기를 경로 기준으로 차단 |
| ruvnet redaction hooks gist | PreToolUse 차단, PostToolUse 출력 정규식 가림 |
| varlock-claude-skill (MIT) | 에이전트가 `.env` 대신 스키마만 보게 하는 원천 차단 |

### 개인정보 레닥션

| 이름 | 하는 일 | 사람 검토 |
|---|---|---|
| presidio-pii-skill | 로컬 Presidio로 PII를 복원 가능 토큰으로 바꿔 모델에 보냄, 꺼지면 멈춤 | 미확인 |
| AgentWard sanitize | PII 15종 탐지, `--preview`로 범주만 표시 | 미리보기만, 승인 없음. BUSL 1.1 |
| DataFog 훅 (MIT) | 프롬프트·도구 호출 PII 탐지, 기본 경고 | 없음 |
| claude-mem (Apache-2.0) | `<private>` 태그 내용은 저장 안 함 | 사람이 **미리** 태그 |

## 5. 설계에 반영한 교훈

| 교훈 | 반영 |
|---|---|
| Entire: "가리지 않은 원본 사본이 생긴다" | 원격에는 암호화본만 ([raw-transcript.md](../design/protection/raw-transcript.md)) |
| 모델 필터·LLM 지시 레닥션은 보장이 없다 | 기계 탐지는 제안용, 최종 결정은 사람 승인 |
| 필터 방식 암호화는 저수준 커밋에서 빠진다 | 커밋 전 age로 명시 암호화 ([sync-transport.md](../design/protection/sync-transport.md)) |
| enclaude의 저장소 내 백업 열쇠 | 비상 열쇠는 컴퓨터·저장소 밖 ([encryption-keys.md](../design/protection/encryption-keys.md)) |
| Entire의 `refs/entire/checkpoints` | 사용자 정의 참조 운반의 실사용 선례 |
| Gitea·Forgejo 소스 확인, GitLab 미확인 | 실측 항목 V-1~V-3 |

## 6. Cumora 조사 (2026-09-15, 로컬 저장소 `/home/jjackkun/PROJECT/cumora-main/cumora-main`)

Cumora는 AI 에이전트가 사람과 함께 팀 채팅에 참여하는 제품이다(에이전트가 페르소나 · 기억을 갖고 여러 방에 참여, 클라우드 pod 또는 로컬 데몬 BYOA). 우리 겸직 · 기억 범위 · 다중 기기 논점과 비교했다.

| 논점 | Cumora | 우리 결정 | 근거 파일 |
|---|---|---|---|
| 에이전트의 소속 | **1 에이전트 = 1 워크스페이스.** 처음엔 복합 PK로 다중 테넌트를 허용했다가 id만으로 조회하는 코드가 다른 테넌트 데이터를 돌려주는 버그를 겪고 전역 유일 id로 되돌림 | 1 에이전트 = 1 소우주, 복제만 | `server/src/db/migrate.ts:2076-2093` |
| 기억 범위 | 에이전트 소유, **전역 / 프로젝트** 두 스코프. 정체성 · 스킬 · 고정 기억은 전역, 작업 사실은 프로젝트. 애매하면 전역(추측 귀속 금지) | 기억은 전부 그 소우주 것 (스코프 구분 폐기) | `server/src/agents/memory-scope.ts:1-29` |
| 스코프 도입 동기 | 한 활동에서 배운 규칙이 다른 활동을 오염시킨 운영 사고 | 격리 원칙의 근거와 같음 | `docs/COORDINATION.md:725-740` |
| 여러 기기 | **1 에이전트 = 1 기기.** 기기 토큰(영구) + 에이전트 토큰(2시간) 2단 | 다중 컴퓨터 허용, 컴퓨터별 열쇠 | `migrate.ts:1466-1467`, `registry.ts:428-444` |
| 첫 페어링 안내 | UI 코드 → 터미널 명령 → 엔진 CLI 없으면 설치 안내 → `--doctor` 점검 | 열쇠 없음 안내 절차와 점검 명령에 참고 | `agent-cli/src/daemon.ts:640-693, 3142-3152` |
| 인계 | 전용 형식 없음. @멘션 · DM · 칸반 카드 배정. 채팅에 잠금 없이 서버 HOLD로 늦은 답을 붙잡음 | 봉투(`goal` · `done_when`) — 채팅이 아닌 작업 단위라 다름 | `docs/COORDINATION.md:178-222` |
| 생성 | owner/admin 즉시 생성, 수습 없음, 삭제 대신 소프트 오프보딩(`departed_at`)과 재고용 | 수습 기간 있음. 은퇴를 표시로 두는 점은 같음 | `router.ts:2372-2397, 2535-2566` |

미확인: 세션 컴팩션의 방별 분리, 같은 hostname 두 기기의 토큰 상호 무효화.

## 7. 출처 (조사 에이전트가 연 페이지)

- age: https://github.com/FiloSottile/age · pyrage: https://github.com/woodruffw/pyrage · SOPS: https://github.com/getsops/sops
- git-crypt: https://github.com/AGWA/git-crypt · transcrypt: https://github.com/elasticdog/transcrypt · git-remote-gcrypt: https://github.com/spwhitton/git-remote-gcrypt
- cryptography Fernet: https://cryptography.io/en/latest/fernet/ · git hash-object: https://git-scm.com/docs/git-hash-object
- gitleaks: https://github.com/gitleaks/gitleaks · Betterleaks: https://github.com/betterleaks/betterleaks · trufflehog: https://github.com/trufflesecurity/trufflehog
- detect-secrets: https://github.com/Yelp/detect-secrets · Presidio: https://presidio.dataprivacystack.org/supported_entities/ · ko-pii: https://github.com/Marker-Inc-Korea/ko-pii
- GitLab Gitaly: https://docs.gitlab.com/administration/gitaly/troubleshooting/
- Gitea: https://raw.githubusercontent.com/go-gitea/gitea/main/routers/private/hook_pre_receive.go · Forgejo: https://codeberg.org/forgejo/forgejo/raw/branch/forgejo/routers/private/hook_pre_receive.go
- enclaude: https://github.com/coredipper/enclaude · Entire CLI: https://github.com/entireio/cli · specstory-guard: https://github.com/specstoryai/agent-skills/blob/main/skills/specstory-guard/SKILL.md
- claude-device-sync: https://github.com/hmennen90/claude-device-sync · claude-sessions: https://github.com/hex/claude-sessions · agent-guard: https://github.com/JeongJaeSoon/agent-guard

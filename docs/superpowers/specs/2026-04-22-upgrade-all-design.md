# update-all 설계 문서

> 작성일: 2026-04-22
> 목적: ai-dev-setting이 설치된 프로젝트들을 한 번에 재설치/업그레이드하는 기능

## 개요

`project-claude.sh`를 실행할 때마다 대상 프로젝트 경로를 머신 로컬 레지스트리
(`.installed-projects`)에 등록한다. `update-all.sh` (또는 `setup.sh --update-all`)
실행 시 레지스트리를 읽어 각 프로젝트에 `project-claude.sh`를 재실행한다.

## 파일 구조

```
ai-dev-setting/
├── update-all.sh              # 신규: 업그레이드 진입점
├── setup.sh                    # 수정: --update-all 옵션 추가
├── project-claude.sh           # 수정: 실행 시 레지스트리 자동 등록
└── .installed-projects         # 신규: gitignored, 머신 로컬 경로 목록
```

`.installed-projects`는 `.gitignore`에 추가한다 (머신별 로컬 파일).

## 컴포넌트별 설계

### 1. `.installed-projects` 레지스트리

- **위치**: `$DEV_SETTING_DIR/.installed-projects`
- **형식**: 줄당 절대 경로 하나
- **관리**: `project-claude.sh` 실행 시 자동 append (중복 제거)
- **git**: `.gitignore`에 추가 — 푸시되지 않음, 머신마다 독립

```
/home/user/PROJECT/my-app
/home/user/PROJECT/another-project
```

### 2. `project-claude.sh` 수정 (등록 로직)

`write_manifest` 호출 직후, 레지스트리에 경로 등록. `--dry-run` 모드에서는 등록하지 않음:

```bash
# 레지스트리에 등록 (중복 제거, dry-run 제외)
if [[ "$DRY_RUN" -eq 0 ]]; then
  REGISTRY="$DEV_SETTING_DIR/.installed-projects"
  touch "$REGISTRY"
  if ! grep -qxF "$PROJECT_PATH" "$REGISTRY"; then
    echo "$PROJECT_PATH" >> "$REGISTRY"
  fi
fi
```

### 3. `update-all.sh`

```
동작 순서:
1. .installed-projects 읽기 (없으면 안내 후 종료)
2. 각 경로 순회:
   a. 경로 없음 → 경고 출력 + 레지스트리에서 제거 → 다음으로
   b. .claude/presets.lock 없음 → 경고 출력 → 다음으로
   c. presets.lock 읽어 preset 목록 추출
   d. project-claude.sh <path> <presets...> 실행
   e. 성공/실패 집계
3. 완료 요약: "성공 N / 실패 M / 스킵 K"
```

레지스트리 정리: 실행 완료 후 존재하지 않는 경로를 `.installed-projects`에서 제거.

### 4. `setup.sh --update-all`

fzf 버전 체크 **이전**에 `--update-all`을 감지해 `update-all.sh`를 호출하고 종료.
fzf는 update-all에서 사용하지 않으므로 버전 체크·설치를 건너뜀.

```bash
# fzf 체크보다 먼저 위치
if [[ "${1:-}" == "--update-all" ]]; then
  exec bash "$DEV_SETTING_DIR/update-all.sh"
fi
```

## 데이터 흐름

```
project-claude.sh 실행
  └→ .installed-projects 에 경로 등록

update-all.sh (또는 setup.sh --update-all)
  └→ .installed-projects 읽기
      └→ 각 경로:
          ├→ 경로 없음: 경고 + 레지스트리 제거
          ├→ presets.lock 없음: 경고 + 스킵
          └→ project-claude.sh <path> <presets> 실행
              └→ 완료 요약 출력
```

## 오류 처리

| 상황 | 동작 |
|------|------|
| `.installed-projects` 없음 | "등록된 프로젝트 없음. 먼저 project-claude.sh를 실행하세요." 출력 후 종료 |
| 경로 없음 | 경고 출력 + 레지스트리에서 제거 |
| `presets.lock` 없음 또는 빈 파일 | 경고 출력 + 스킵 (레지스트리에서 제거하지 않음) |
| `project-claude.sh` 실패 | 에러 출력 + 실패 카운트 증가, 나머지 프로젝트는 계속 진행 |

## 테스트 계획

- `project-claude.sh` 실행 후 `.installed-projects`에 경로 등록 확인
- 동일 경로 두 번 실행 시 중복 등록 안 됨 확인
- `update-all.sh`: 정상 경로 → 재설치 성공
- `update-all.sh`: 없는 경로 → 경고 + 레지스트리 정리
- `setup.sh --update-all` → update-all.sh로 위임 확인
- `.installed-projects`가 git에 포함 안 됨 확인

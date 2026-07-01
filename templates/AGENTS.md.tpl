# {{PROJECT_NAME}}

> 이 파일의 일부 섹션은 `dev-setting/project-codex.sh` 가 관리합니다.
> 자동 마커(DS-CODEX:BEGIN ~ DS-CODEX:END) 안쪽만 갱신되며, 바깥쪽은 자유롭게 수정 가능합니다.

## Project Context

(프로젝트 목적, 범위, 핵심 의사결정을 짧게 적으세요.)

## Working Principles

- 사용자님이 명시하지 않은 설정값, 의존성 버전, 권한 정책은 임의로 바꾸지 않습니다.
- 변경 전 영향 범위를 확인하고, 위험한 작업은 사용자님께 먼저 확인합니다.
- 기존 코드 패턴과 로컬 helper API를 우선합니다.
- 비자명한 변경은 구현 후 검증하고, 큰 변경은 `codex review --uncommitted` 흐름을 거칩니다.

## Knowledge Base

- **항상 필요한 핵심 규칙·결정은 이 파일에 짧게 노출**합니다 — 모델이 찾아 호출하기를 기대하지 않고 눈앞에 둡니다.
- 특별한 대형 작업에서만 쓰는 긴 절차는 Codex skill 또는 `docs/exec-plans/`·`docs/design-docs/`로 분리하고, 이 파일에는 "언제 쓰는지"만 가리킵니다.
- 반복되는 오류·해결 패턴은 skill/`docs/`로 승격하되, 핵심 한 줄은 이 파일에 남깁니다.

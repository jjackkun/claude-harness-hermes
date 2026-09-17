# coexist 픽스처 — terminal-shipping 실물 plan_state (계획 2026-09-17-install-coexistence Step 0)

| 파일 | 출처 |
|---|---|
| `plan_state.ours`   | terminal-shipping 커밋 `266d0b9` 의 `scripts/hooks/plan_state.py` — 소우주가 고친 판(`[~]` 세기) |
| `plan_state.base`   | 공장 `6f82144` 의 `assets/hooks/plan_state.py` — 마지막 설치판의 **대용**(훅 kind 가 manifest 에 없어 진짜 설치 커밋 미기록) |
| `plan_state.theirs` | 공장 현재 `assets/hooks/plan_state.py` |

- `check-secrets.py` 실물은 **수록하지 않는다** — 사내 소우주의 내부 경로·자격증명 꼴 문자열이 들어 있어 PUBLIC 공장에 두면 R-leak 위반. 스캐너가 실제로 막았다(2026-09-17, 5건). byte-equal 증명은 계획서 §7 에 실측치로만 남긴다.
- 확장자를 `.py` 로 두지 않는 이유: R-lint·R-cx·R-test 가 픽스처를 소스로 오인하지 않게.
- 스캔은 스테이징 경로로 해야 실제다 — 스캐너는 인자 파일을 보지 않는다(`staged_files()`).

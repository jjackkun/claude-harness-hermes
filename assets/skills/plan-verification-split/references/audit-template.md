# Audit document template

Use this shape when writing / updating the audit doc after running `plan-verification-split`. Path convention: `docs/audits/<date>-<feature>-verify.md` (or whatever the project already uses for audits).

Examples below are deliberately stack-neutral. Replace them with your project's real tables, endpoints, and paths when you fill in the template.

## Minimum structure

```markdown
# <Feature name> — 수용 기준 검증 기록

- 날짜: YYYY-MM-DD
- 브랜치 / 커밋: <branch> @ <sha>
- 환경: <where the verification was run — staging / local docker / prod-mirror>
- plan 문서: <relative path>

## 검증 결과

| #   | 기준                | 태그                | 상태     | 증거 / 명령                                  |
| --- | ------------------- | ------------------- | -------- | -------------------------------------------- |
| 1   | <criterion text>    | `[auto:db-query]`   | ✅ PASS  | `SELECT ...` → 1 row matching                |
| 2   | <criterion text>    | `[auto:api-call]`   | ✅ PASS  | `POST /... → 202 {...}`                      |
| 3   | <criterion text>    | `[auto:code-grep]`  | ✅ PASS  | `grep 'status=active' src/... #87`           |
| 4   | <criterion text>    | `[human:visual]`    | ⏳ PENDING | 사용자 브라우저 확인 필요 — `<URL>`        |
| 5   | <criterion text>    | `[human:env]`       | ⏳ PENDING | 폴더에 파일 N개 drop 필요 — `<path>`       |
| 6   | <criterion text>    | `[auto:api-call]`   | ❌ FAIL  | 409 body → `{"detail":"..."}` (→ §A fix)    |

## 발견된 결함

For every FAIL row above, a numbered section with:

### §A. <short defect title> (fix <commit-sha>)

- Symptom: what the auto check observed vs. what the spec required
- Root cause: the code-level reason (file:line)
- Fix: one-line summary of the code change
- Re-verify: the auto command rerun after the fix + its new output

After the fix, either flip the status in the table to `✅ PASS (fix <sha>)` or add a new row below the original and leave the FAIL for history. Both are fine; pick one convention and stick with it in the project.

## 사용자에게 남긴 질문 (human residual)

Only the `[human:*]` items that are still PENDING. Formatted as a short checklist the user can answer in one message:

- [ ] 기준 #4: `<URL>` 에서 해당 화면을 열고 의도한 상태(빨간 뱃지 / 비어있는 상태 문구 / 애니메이션)가 보이는지
- [ ] 기준 #5: `<path>` 에 파일 N개를 drop 하고 기대한 부수효과가 관찰되는지

If this section is empty, write "모든 auto 항목 PASS, 사용자 확인 필요 없음." so the audit explicitly documents a clean close.

## 후속 개선 과제

Things you noticed while verifying that are out of scope for the current feature but should not be forgotten. Keep it bulleted and short. Link to tickets or issues if the project tracks them separately.
```

## Example row patterns

**auto:db-query**

| 4 | 수동 트리거 → 주문 레코드 1건 생성 | `[auto:db-query]` | ✅ PASS | `SELECT id, source, status FROM orders WHERE user_id=42 ORDER BY id DESC LIMIT 2;` → `#1001 manual success`, `#1002 manual success` |

**auto:api-call — FAIL then fixed**

| 5 | 충돌 시 409 에러 메시지가 스펙 문구와 일치 | `[auto:api-call]` | ✅ PASS (fix a1b2c3d) | `POST /api/orders → 409 {"detail":"이미 진행 중입니다"}` (fix §A: 영어 메시지 + 프론트 폴백 체인 누락) |

**auto:code-grep**

| 1 | 목록 쿼리에 active 필터가 적용되어 있음 | `[auto:code-grep]` | ✅ PASS | `grep 'status="active"' src/services/users.py` → `87: query = query.filter(User.status == "active")` |

**auto:log-scan**

| 7 | 백그라운드 이벤트가 실제로 emit 됨 | `[auto:log-scan]` | ✅ PASS | `grep 'order.created' logs/app.log` → `2026-01-15 09:31:02 INFO order.created id=1001 user_id=42` |

**human:visual**

| 3 | 그룹 헤더가 시각적으로 구분되는지 | `[human:visual]` | ⏳ PENDING | 사용자가 <URL> 해당 탭 확인 |

**human:env**

| 6 | 감시 폴더 파일 N개 drop → artifact N건 | `[human:env]` | ⏳ PENDING | 사용자 머신 로컬 폴더 drop — 에이전트 접근 불가 |

## Keep the tags after the audit

Do not strip `[auto:*]` / `[human:*]` from the committed file. They are the trail that lets the next person re-run the same verification without re-deciding which items are automatable. Tags are load-bearing metadata, not scaffolding.

#!/usr/bin/env bash
# 스케줄 워크플로 실패 알림 시험 — 실패하면 고정 제목 이슈를 한 번만 열고, 이후엔 댓글을 단다.
#
# 배경: weekly-doc-gardening 이 네 번 연속 실패했는데 4주 동안 아무도 몰랐다(schedule 은 보는 사람이 없다).
# YAML 안에만 있는 로직은 시험이 닿지 않아 두 번 사고가 났다 — 그래서 알림 스크립트를 템플릿에서
# 꺼내 node 로 **실제로 돌린다**. github-script 는 script 본문을 (github, context, core) 를 받는
# async 함수로 실행하므로 같은 방식으로 감싼다.
# 근거: docs/exec-plans/completed/2026-09-22-ci-failure-notification.md 목표 1~3
#
# 실행: bash tests/workflow-failure-notice-test.sh
# 종료 코드: 0 = 모든 단언 통과, 1 = 실패

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$REPO_ROOT/assets/cron-templates/github-actions/weekly-doc-gardening.yml"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $desc"; PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected=$expected actual=$actual)"; FAIL=$((FAIL+1))
  fi
}

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node 없음"; exit 0
fi

# 알림 단계(name: Report workflow failure)의 속성과 script 본문을 꺼낸다.
python3 - "$TPL" "$TMP" <<'PY'
import sys, os
tpl, out = sys.argv[1], sys.argv[2]
lines = open(tpl, encoding="utf-8").read().split("\n")
start = next((i for i, l in enumerate(lines) if l.strip() == "- name: Report workflow failure"), None)
if start is None:
    open(os.path.join(out, "attrs"), "w").write("missing\n"); sys.exit(0)
step_indent = len(lines[start]) - len(lines[start].lstrip())
step = [lines[start]]
for l in lines[start + 1:]:
    if l.strip() and len(l) - len(l.lstrip()) <= step_indent:
        break
    step.append(l)
attrs = [l.strip() for l in step if l.strip().startswith(("if:", "continue-on-error:"))]
open(os.path.join(out, "attrs"), "w").write("\n".join(attrs) + "\n")
last_step = [l for l in lines if l.strip().startswith("- name:")][-1].strip()
open(os.path.join(out, "last"), "w").write(last_step + "\n")
i = next(i for i, l in enumerate(step) if l.strip() == "script: |")
body = step[i + 1:]
ind = min(len(l) - len(l.lstrip()) for l in body if l.strip())
open(os.path.join(out, "script.js"), "w").write("\n".join(l[ind:] for l in body))
PY

echo "== 1. 알림 단계의 자리와 속성 =="
assert "알림 단계가 있다" "0" "$(grep -qv missing "$TMP/attrs"; echo $?)"
assert "실패할 때만 돈다 (if: failure())" "0" "$(grep -qx 'if: failure()' "$TMP/attrs"; echo $?)"
assert "알림 실패가 새 실패를 만들지 않는다 (continue-on-error)" "0" "$(grep -qx 'continue-on-error: true' "$TMP/attrs"; echo $?)"
assert "마지막 단계다" "- name: Report workflow failure" "$(cat "$TMP/last")"

# 가짜 github·context·core 로 스크립트를 돌린다. 인자: 열린 이슈 제목들(JSON 배열), 목록 호출을 실패시킬지
run_script() {
  node - "$TMP/script.js" "$1" "${2:-0}" <<'JS'
const fs = require("fs");
const [file, openJson, failList] = process.argv.slice(2);
const calls = { create: 0, comment: 0, warn: 0, title: "", labels: [], body: "" };
const open = JSON.parse(openJson).map((title, i) => ({ number: i + 1, title }));
const github = { rest: { issues: {
  listForRepo: async () => { if (failList === "1") throw new Error("boom"); return { data: open }; },
  create: async (a) => { calls.create++; calls.title = a.title; calls.labels = a.labels || []; calls.body = a.body; },
  createComment: async (a) => { calls.comment++; calls.body = a.body; },
} } };
const context = { repo: { owner: "o", repo: "r" }, serverUrl: "https://github.com", runId: 42, workflow: "weekly-doc-gardening" };
const core = { warning: () => { calls.warn++; } };
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
new AsyncFunction("github", "context", "core", fs.readFileSync(file, "utf8"))(github, context, core)
  .then(() => console.log(JSON.stringify({ ok: true, ...calls })))
  .catch((e) => console.log(JSON.stringify({ ok: false, err: String(e), ...calls })));
JS
}
field() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); v=d.get(sys.argv[2]); print(','.join(v) if isinstance(v,list) else v)" "$1" "$2"; }

echo "== 2. 열린 알림 이슈가 없으면 연다 =="
r=$(run_script '[]')
assert "이슈 1개 생성" "1" "$(field "$r" create)"
assert "댓글 없음" "0" "$(field "$r" comment)"
assert "harness 라벨" "0" "$(field "$r" labels | grep -q harness; echo $?)"
assert "본문에 실행 링크" "0" "$(field "$r" body | grep -qF 'https://github.com/o/r/actions/runs/42'; echo $?)"
title=$(field "$r" title)

echo "== 3. 같은 제목의 열린 이슈가 있으면 댓글만 =="
r=$(run_script "[\"$title\"]")
assert "새 이슈 없음" "0" "$(field "$r" create)"
assert "댓글 1개" "1" "$(field "$r" comment)"

echo "== 4. 제목이 다른 이슈(편차 보고)만 있으면 연다 =="
r=$(run_script '["[doc-gardening] 편차 감지 — 2026-09-21"]')
assert "이슈 1개 생성" "1" "$(field "$r" create)"

echo "== 5. GitHub 호출이 실패해도 스크립트는 거부 없이 끝난다 =="
r=$(run_script '[]' 1)
assert "처리되지 않은 거부 없음" "True" "$(field "$r" ok)"
assert "경고를 남긴다" "1" "$(field "$r" warn)"

echo "== 6. 공장 설치본이 템플릿과 같다 =="
diff <(grep -v '^# harness-template-sha:' "$TPL") \
     <(grep -v '^# harness-template-sha:' "$REPO_ROOT/.github/workflows/weekly-doc-gardening.yml") >/dev/null; _rc=$?
assert "본문 일치(마커 줄 제외)" "0" "$_rc"

echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]

#!/usr/bin/env bash
# dev-setting/lib/harness_hook_manifest.sh
# 하네스가 **마지막에 깐** 파일 본문의 sha256 을 프로젝트에 기록하고 대조한다.
#
# 왜 필요한가: 전파는 조건 없는 복사다. 하류가 이유를 대고 고쳐 둔 것도 덮는다.
# 덮는 것 자체는 전파의 일이지만, 무엇을 덮었는지 말하지 않으면 하류는 잃은 줄도
# 모른다 — 2026-08-27 terminal-shipping 이 같은 수정을 두 번 되살렸다.
#
# 왜 `cmp src dest` 가 아닌가: 그것은 두 가지 다른 사실을 한 값으로 뭉갠다.
#   dest != src  →  ① 하류가 고쳤다      (말해야 하는 것)
#                →  ② 상류가 개정했다    (말하면 안 되는 것 — 평범한 갱신)
# ②가 압도적으로 흔해서, 하나만 고쳐도 전 프로젝트가 "덮었다" 목록을 띄운다.
# 매번 뜨는 경고는 읽히지 않고, 읽히지 않는 경고는 없는 경고다.
# 같은 이유로 harness_write_marked_template 이 이미 cmp 를 버렸다 — 그 주석:
# "cmp -s 와 달리 템플릿이 개정돼도 판정이 유지된다."
#
# 왜 파일 안 마커(harness-template-sha)가 아닌가: HARNESS_HOOK_SOURCES 에
# claude-settings-hooks.json 이 있다. JSON 에는 주석 줄을 넣을 문법이 없다.
#
# 키는 **프로젝트 상대경로**다 (`scripts/hooks/x.sh`, `.git/hooks/pre-commit`).
# 이름이 아니라 경로를 키로 쓰면 세 가지가 한꺼번에 풀린다:
#   - 같은 이름이 두 자리에 깔려도 충돌하지 않는다 (plan_state.py 가 실제로 그렇다)
#   - 보고 문구가 곧 경로라 사람이 바로 찾아갈 수 있다
#   - 기록을 정리할 때 "그 경로에 파일이 있는가" 만 보면 된다
#
# 형식: `<sha256>  <상대경로>` 한 줄씩. `.claude/presets.lock` 과 같은 자리·성격.
#
# Sourced, not executed directly.

HARNESS_HOOK_MANIFEST_REL=".claude/harness-hooks.lock"

# harness_hook_manifest_path <project_path>
harness_hook_manifest_path() {
  echo "$1/$HARNESS_HOOK_MANIFEST_REL"
}

# harness_content_sha <file>
harness_content_sha() {
  sha256sum "$1" | cut -d' ' -f1
}

# harness_hook_recorded_sha <project_path> <relpath>
# 상류가 마지막에 깐 본문의 sha. 기록이 없으면 빈 문자열.
#
# grep 을 쓰지 않는 이유: 경로에 정규식 메타문자가 들어간다. `.git/hooks/pre-commit`
# 의 `.` 는 아무 글자나 매치하므로 `  Xgit/hooks/pre-commit` 같은 줄이 먼저 걸리면
# **엉뚱한 해시를 그 경로의 기록으로 읽는다.** 문자열 그대로 비교한다.
#
# `\r` 을 떼는 이유: Windows 편집기가 매니페스트를 건드리면 경로 끝에 `\r` 이 붙어
# 비교가 빗나가고, 그러면 "기록 없음" 으로 떨어져 **조용히** 판정을 포기한다.
# 이 저장소는 CRLF .gitignore 로 이미 한 번 당했다(harness-hooks-smoke.sh §16).
harness_hook_recorded_sha() {
  local manifest line key
  manifest="$(harness_hook_manifest_path "$1")"
  [[ -f "$manifest" ]] || return 0
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line#*  }"
    if [[ "$key" == "$2" ]]; then
      echo "${line%%  *}"
      return 0
    fi
  done < "$manifest"
  return 0
}

# harness_hook_is_downstream_edit <project_path> <relpath>
# 하류가 고친 것이면 0(=말한다). 다음 셋 중 하나면 1(=말하지 않는다):
#   - 설치본이 없다      → 신규 배치. 덮은 것이 없다
#   - 기록이 없다        → 첫 도입. 판정 불가 — 조용히 기록만 한다
#   - 기록과 본문이 같다 → 상류만 바뀌었다. 하류가 잃는 것이 없다
#
# ⚠️ 둘째 줄은 **의도한 손실**이다. 첫 도입 때 하류 수정 한 번을 못 잡는다.
# "모르면 경고" 를 택하면 첫 전파에서 전 프로젝트가 울어 경고가 통째로 죽는다.
harness_hook_is_downstream_edit() {
  local project_path="$1" relpath="$2"
  local dest="$project_path/$relpath"
  [[ -f "$dest" ]] || return 1
  local recorded
  recorded="$(harness_hook_recorded_sha "$project_path" "$relpath")"
  [[ -n "$recorded" ]] || return 1
  [[ "$(harness_content_sha "$dest")" != "$recorded" ]]
}

# harness_hook_manifest_write <project_path> <"sha  상대경로" 줄들...>
# 주어진 경로의 기록만 갱신하고 나머지는 보존한다. 순서 의존을 없애기 위해서다 —
# 훅 설치와 pre-commit 설치가 같은 매니페스트를 각자 갱신하므로, 통째로 쓰면
# 나중에 도는 쪽이 먼저 도는 쪽의 기록을 지운다.
#
# 동시에 **파일이 사라진 경로의 기록은 버린다.** 은퇴한 훅은 _cleanup_stale_hooks 가
# 회수하는데 기록만 남으면 매니페스트가 끝없이 자란다. 판정에 해롭지는 않지만
# (파일이 없으면 애초에 판정을 안 한다) 읽을 수 없는 파일은 고쳐지지도 않는다.
harness_hook_manifest_write() {
  local project_path="$1"; shift
  [[ $# -gt 0 ]] || return 0
  local manifest
  manifest="$(harness_hook_manifest_path "$project_path")"
  mkdir -p "$(dirname "$manifest")"
  HARNESS_MANIFEST_PATH="$manifest" HARNESS_PROJECT_PATH="$project_path" \
    python3 - "$@" <<'PYEOF'
import io
import os
import sys

path = os.environ["HARNESS_MANIFEST_PATH"]
project = os.environ["HARNESS_PROJECT_PATH"]


def split(text):
    sha, _, key = text.rstrip("\r").partition("  ")
    return sha, key


records = {}
if os.path.exists(path):
    for line in io.open(path, encoding="utf-8"):
        line = line.rstrip("\n").rstrip("\r")
        if not line or line.startswith("#"):
            continue
        sha, key = split(line)
        if key:
            records[key] = sha

for arg in sys.argv[1:]:
    sha, key = split(arg)
    if key:
        records[key] = sha

# 파일이 사라진 경로는 버린다. 방금 깐 것들은 전부 존재하므로 여기서 안 걸린다.
live = {k: v for k, v in records.items() if os.path.exists(os.path.join(project, k))}

with io.open(path, "w", encoding="utf-8") as handle:
    handle.write("# 하네스가 마지막에 깐 파일 본문의 sha256. 손으로 고치지 말 것.\n")
    handle.write("# 이 기록이 있어야 전파가 '하류가 고친 것' 과 '상류가 개정한 것' 을 구분한다.\n")
    for key in sorted(live):
        handle.write("%s  %s\n" % (live[key], key))
PYEOF
}

# harness_report_overwritten <라벨> <상대경로들...>
# 덮은 것을 한 번에 보고한다. **막지 않는다** — 덮는 것이 전파의 일이다.
# 다만 조용히 덮지 않는다. "덮었다" 만으로는 부족하므로 *어느 파일인지* 와
# *되돌리려면 무엇을 보라* 까지 말한다.
harness_report_overwritten() {
  local label="$1"; shift
  [[ $# -gt 0 ]] || return 0
  log_warn "  $label → 하류가 고쳐 둔 파일 $# 개를 덮었습니다:"
  local path
  for path in "$@"; do
    log_warn "            · $path"
  done
  log_warn "            ↳ 잃은 것이 있는지 \`git diff -- <경로>\` 로 확인하십시오"
  log_warn "            ↳ .git/hooks/ 아래는 추적되지 않습니다 — 되얹는 스크립트가 있다면 지금 실행하십시오"
  log_warn "            ↳ 그 수정이 옳다면 상류(assets/hooks/)에 올려야 다음 전파가 안 되돌립니다"
}

# harness_report_pre_commit_replaced
# pre-commit 은 성격이 다르다. 훅 파일의 "다르다" 는 *하류가 고쳤다* 지만
# pre-commit 의 "다르다" 는 **하류가 단계를 얹었다** 는 뜻일 때가 많고,
# 갈아치는 순간 그 단계가 실제로 사라진다.
harness_report_pre_commit_replaced() {
  log_warn "  hook    → .git/hooks/pre-commit 을 갈아쳤습니다 (하네스가 주는 것과 달랐습니다)"
  log_warn "            ↳ 얹어 두신 단계가 있었다면 다시 얹으십시오 — 무엇을 얹었는지는 하네스가 알지 못합니다"
  log_warn "            ↳ 빠져도 티가 안 나는 단계가 특히 위험합니다 (시크릿 스캔이 빠지면 평소처럼 커밋됩니다)"
}

#!/usr/bin/env bash
# lib/factory_coexist.sh — 공존 설치: 하류가 고친 파일을 덮지 않고, 상류 개정은 합쳐서 전달한다.
#
# 이 파일의 유일한 책임: 파일 하나를 놓을 때 base(마지막 설치판)·ours(프로젝트 현재)·theirs(새 공장판)
# 를 대조해 분기를 정하고, 필요하면 3-way 병합하고, 못 합치면 옆에 세워 둔다. 어디에 무엇을 까는지는
# 모른다 — 호출자가 준다. 계획: docs/exec-plans/active/2026-09-17-install-coexistence.md 목표 2·3.
#
#   install_factory_file <src> <dst> <kind> <name> <claude_dir> [new_mode]
#     src        공장 안 원본(절대 경로, 파일만 — 디렉터리는 installers.sh 의 백업 경로가 맡는다)
#     dst        프로젝트 안 설치 경로. 심링크면 타깃이 실물이되, 타깃이 프로젝트 밖이면 손대지 않는다
#     kind/name  manifest 키. 훅·스크립트는 name 에 프로젝트 상대 경로를 준다(경로마다 항목)
#     claude_dir <프로젝트>/.claude — manifest 가 있는 곳. 프로젝트 루트 = 그 부모
#     new_mode   새 파일일 때만 적용할 8진 모드(예: 755). 기존 파일은 제 모드를 지킨다
#
# 분기(순서대로 처음 맞는 것): ⓪ ours==theirs → no-op │ a dst 없음 → 복사 │ b ours==base → 덮음
#   │ c theirs==base → 손대지 않음 │ d 둘 다 바뀜 → merge-file+구문검사 │ ⓔ base 불명 → 세워 둠
# 출력: ⓪·a·b·c 는 조용(G6). d·충돌·ⓔ 만 stderr 한 줄(G4).
# 종료코드는 언제나 0 — 설치를 멈추지 않는다. 호출자가 `set -e` 라도 이 안의 실패는 밖으로 안 새게
# 모든 외부 명령을 잡는다(리뷰 2026-09-17 HIGH②). 분기는 COEXIST_LAST_BRANCH 에 남긴다(0 a b c d x e f).
#
# 근거 결정: "고친 것은 덮지 않는다" 가 아니라 **공장 개정은 언제나 전달하고, 하류 수정은 지우지
# 않으며, 만나면 합친다**. 08-27 의 "덮되 말한다" 를 뒤집되 "자동 병합은 조용히 틀린다" 는 지킨다 —
# 충돌·구문 실패·base 불명·쓰기 실패는 절대 자동으로 풀지 않고 사람 책상(.factory-new + pre-commit 차단)에 올린다.

if ! declare -F manifest_add >/dev/null 2>&1; then
  # shellcheck source=lib/factory_manifest.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/factory_manifest.sh"
fi

COEXIST_LAST_BRANCH=""

_coexist_factory_root() {
  if [[ -n "${DEV_SETTING_DIR:-}" ]]; then printf '%s' "$DEV_SETTING_DIR"
  else cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; fi
}

# 8진 모드. GNU(stat -c) 와 BSD/macOS(stat -f) 겸용 — 같은 저장소의 observer-loop.sh 와 같은 패턴(리뷰 MED①).
_coexist_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null || printf '644'
}

# 원자적 쓰기: 같은 파일시스템의 .tmp 에 쓰고 rename. 도중에 죽어도 훅이 잘린 채 남지 않는다(리뷰 MED③).
# 성공 0, 실패 1(임시 파일 정리). 모드는 인자로 못 박는다.
_coexist_write() {
  local from="$1" to="$2" mode="$3" tmp="$2.tmp.$$"
  if cp "$from" "$tmp" 2>/dev/null && chmod "$mode" "$tmp" 2>/dev/null && mv -f "$tmp" "$to" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp"; return 1
}

# base 내용을 임시 파일로 복원한다. 되면 경로를 출력, 안 되면 아무것도 출력하지 않는다(→ ⓔ).
# ① manifest 의 factory_commit + src. ② 없으면 factory.json.installed_version(계획 1 이 매 설치마다 적는
#    프로젝트 전체의 마지막 공장 커밋)을 파일별 base 의 대용으로 — 옛 설치기가 훅 kind 를 manifest 에 안 적어
#    첫 전환 때 이미 고쳐 둔 파일이 전부 ⓔ 로 떨어지는 것을 막는다(2026-09-17 리허설 실측: terminal-shipping 3·zeroday 1).
# 커밋은 hex sha 형식만 받고 --end-of-options 뒤에 둔다 — manifest 는 사람이 고칠 수 있는 파일이라 옵션 스머글링을 막는다(리뷰 MED②).
_coexist_base() {
  local claude_dir="$1" kind="$2" name="$3" factory="$4" src_rel="$5"
  local commit srcrel tmp origin
  commit="$(manifest_field "$claude_dir" "$kind" "$name" factory_commit)"
  srcrel="$(manifest_field "$claude_dir" "$kind" "$name" src)"
  if [[ -z "$commit" || -z "$srcrel" ]]; then
    commit="$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("installed_version",""))
except Exception: print("")' "$(dirname "$claude_dir")/.hermes/factory.json" 2>/dev/null)"
    srcrel="$src_rel"; origin="installed_version"
  else
    origin="manifest"
  fi
  [[ "$commit" =~ ^[0-9a-f]{7,40}$ && -n "$srcrel" && "$srcrel" != -* ]] || return 0
  tmp="$(mktemp)" || return 0
  if git -C "$factory" show --end-of-options "$commit:$srcrel" > "$tmp" 2>/dev/null; then
    printf '%s\t%s' "$tmp" "$origin"      # 명령치환(서브셸)으로 불리므로 출처도 stdout 으로 돌려준다
  else
    rm -f "$tmp"
  fi
}

# 병합본의 구문을 본다. 확장자로, 없으면 shebang 으로 검사기를 고른다. 모르는 종류는 통과(검사할 수 없는 것을 막지 않는다).
_coexist_syntax_ok() {
  local file="$1" dst="$2" kind=""
  case "$dst" in
    *.py) kind=py ;;
    *.sh) kind=sh ;;
    *) case "$(head -n1 "$file" 2>/dev/null)" in
         *python*) kind=py ;;
         *bash*|*"/bin/sh"*) kind=sh ;;
       esac ;;
  esac
  case "$kind" in
    # py_compile(cfile=/dev/null) 은 3.12+ 에서 FileExistsError 로 **항상** 실패한다 — 그러면 모든 병합이
    # 충돌로 떨어지고, 테스트는 "구문 실패 → 충돌" 이 통과했다고 착각한다(2026-09-17 실측). compile() 은 파일을 안 만든다.
    py) python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' "$file" >/dev/null 2>&1 ;;
    sh) bash -n "$file" >/dev/null 2>&1 ;;
    *)  return 0 ;;
  esac
}

# 3-way 병합해 ours 에 원자적으로 쓴다. 충돌·오류·구문 실패·쓰기 실패면 ours 를 건드리지 않고 1.
_coexist_merge() {
  local ours="$1" base="$2" theirs="$3" mode="$4" out
  out="$(mktemp)" || return 1
  if ! git merge-file -p -L ours -L base -L factory "$ours" "$base" "$theirs" > "$out" 2>/dev/null; then
    rm -f "$out"; return 1
  fi
  if ! _coexist_syntax_ok "$out" "$ours"; then
    rm -f "$out"; return 1
  fi
  local rc=0
  _coexist_write "$out" "$ours" "$mode" || rc=1
  rm -f "$out"
  return $rc
}

# ours 가 공장 이력의 어느 판과 같은가 — 같으면 하류 수정이 아니라 **그냥 옛 공장판**이다.
# base 를 못 찾을 때 마지막으로 묻는 질문. 2026-09-17 라이브 전파에서 hermes 없는 소우주 4곳(factory.json 없음
# → 폴백 base 없음)의 옛 pre-commit 이 전부 ⓔ 로 세워졌다 — 하류 수정이 아니었는데 사람 손을 7번 부를 뻔했다.
# 설치는 공장 저장소 안에서 돌므로 이 질문은 언제나 답할 수 있다. 최근 60커밋만 본다(그보다 오래된 사본은 어차피 재검토 대상).
_coexist_is_old_factory() {
  local factory="$1" src_rel="$2" ours_sha="$3" c
  for c in $(git -C "$factory" log --format=%H -200 -- "$src_rel" 2>/dev/null); do
    [[ "$(git -C "$factory" show --end-of-options "$c:$src_rel" 2>/dev/null | sha256sum | awk '{print $1}')" == "$ours_sha" ]] && return 0
  done
  return 1
}

# ours 가 공장 이력의 옛 판이면 하류 수정이 아니다 → 그냥 전달(b). 전달했으면 0.
# 2026-09-20 doctor 실측: 소우주 3곳의 pre-commit·훅이 옛 공장판인데 manifest 는 현재판 sha 라 c 갈래가 "하류 수정" 으로 보고 영원히 놔뒀다
# (backlog coexist-old-factory-detection). c 판정 앞에서 이 검사를 한 번 한다 — git log 는 c 갈래에서만 돈다.
_coexist_deliver_if_old() {
  local factory="$1" src_rel="$2" ours_sha="$3" src="$4" real="$5" mode="$6" claude_dir="$7" kind="$8" name="$9"
  _coexist_is_old_factory "$factory" "$src_rel" "$ours_sha" || return 1
  if ! _coexist_write "$src" "$real" "$mode"; then
    echo "[factory-coexist WARN] 쓰기 실패, 이전 판 유지: $real" >&2; return 0
  fi
  rm -f "$real.factory-new"
  manifest_add "$claude_dir" "$kind" "$name" "$real" "$src_rel" "$mode" || true
  COEXIST_LAST_BRANCH=b; return 0
}

# 덮지 않고 공장 판을 옆에 세운다. pre-commit(R-merge)이 이 파일을 보고 커밋을 막는다.
_coexist_park() {
  local src="$1" real="$2" label="$3" name="$4"
  cp "$src" "$real.factory-new" 2>/dev/null || true
  echo "[factory-merge $label] $name — 하류 수정을 지키려 덮지 않았습니다. 공장 판: ${real}.factory-new (합친 뒤 지우십시오; pre-commit 이 막습니다)" >&2
}

install_factory_file() {
  local src="$1" dst="$2" kind="$3" name="$4" claude_dir="$5" new_mode="${6:-}"
  COEXIST_LAST_BRANCH=""; COEXIST_BASE_SOURCE=""
  if [[ -d "$src" ]]; then
    echo "[factory-coexist WARN] 디렉터리는 이 함수로 설치할 수 없습니다(파일 전용), 건너뜀: $src" >&2; return 0
  fi
  if [[ ! -f "$src" ]]; then
    echo "[factory-coexist WARN] 원본 없음, 건너뜀: $src" >&2; return 0
  fi
  local factory src_rel real project
  factory="$(_coexist_factory_root)"
  src_rel="${src#"$factory"/}"
  project="$(cd "$(dirname "$claude_dir")" 2>/dev/null && pwd -P)"
  real="$dst"
  if [[ -L "$dst" ]]; then
    real="$(readlink -f "$dst" 2>/dev/null)"
    # 타깃이 프로젝트 밖(계획 1 이전의 공장 심링크 등)이면 쓰는 순간 공장 원본을 덮는다 — 절대 쓰지 않는다(리뷰 HIGH①).
    if [[ -z "$real" || -z "$project" || "$real" != "$project"/* ]]; then
      echo "[factory-merge OUTSIDE] $name — 심링크가 프로젝트 밖($real)을 가리켜 손대지 않았습니다. 링크를 지우고 다시 설치하십시오" >&2
      COEXIST_LAST_BRANCH=f; return 0
    fi
  fi

  # a — 처음 놓는 파일
  if [[ ! -e "$real" ]]; then
    mkdir -p "$(dirname "$real")" 2>/dev/null || true
    if ! _coexist_write "$src" "$real" "${new_mode:-$(_coexist_mode "$src")}"; then
      echo "[factory-coexist WARN] 쓰기 실패, 건너뜀: $real" >&2; return 0
    fi
    manifest_add "$claude_dir" "$kind" "$name" "$real" "$src_rel" "$(_coexist_mode "$real")" || true
    COEXIST_LAST_BRANCH=a; return 0
  fi

  local ours_sha theirs_sha mode base_sha
  ours_sha="$(_manifest_sha "$real")"
  theirs_sha="$(_manifest_sha "$src")"
  mode="$(_coexist_mode "$real")"

  # ⓪ — 내용이 같다. 병합할 것도 알릴 것도 없다(기록만 최신으로).
  if [[ "$ours_sha" == "$theirs_sha" ]]; then
    manifest_add "$claude_dir" "$kind" "$name" "$real" "$src_rel" "$mode" || true
    COEXIST_LAST_BRANCH=0; return 0
  fi

  base_sha="$(manifest_field "$claude_dir" "$kind" "$name" sha256)"

  # b — 하류는 안 고쳤고 공장이 개정됐다 → 그냥 전달(원자적)
  if [[ -n "$base_sha" && "$base_sha" == "$ours_sha" ]]; then
    if ! _coexist_write "$src" "$real" "$mode"; then
      echo "[factory-coexist WARN] 쓰기 실패, 이전 판 유지: $real" >&2; return 0
    fi
    manifest_add "$claude_dir" "$kind" "$name" "$real" "$src_rel" "$mode" || true
    COEXIST_LAST_BRANCH=b; return 0
  fi

  # c — 공장은 그대로고 하류만 고쳤다 → 손대지 않는다. manifest 도 그대로(수정 신호를 지우지 않는다)
  #     단, ours 가 옛 공장판이면 하류 수정이 아니라 전파 누락이다 → 전달(2026-09-20).
  if [[ -n "$base_sha" && "$base_sha" == "$theirs_sha" ]]; then
    _coexist_deliver_if_old "$factory" "$src_rel" "$ours_sha" "$src" "$real" "$mode" "$claude_dir" "$kind" "$name" && return 0
    COEXIST_LAST_BRANCH=c; return 0
  fi

  # d / ⓔ — 둘 다 바뀌었거나(base 있음) base 를 모른다
  local base_file base_pair
  base_pair="$(_coexist_base "$claude_dir" "$kind" "$name" "$factory" "$src_rel")"
  base_file="${base_pair%%$'\t'*}"; COEXIST_BASE_SOURCE="${base_pair#*$'\t'}"
  [[ "$base_pair" == *$'\t'* ]] || COEXIST_BASE_SOURCE=""
  if [[ -z "$base_file" ]]; then
    # base 는 몰라도 ours 가 옛 공장판이면 하류 수정이 아니다 → 그냥 전달(b 와 같음). 남은 .factory-new 도 치운다.
    if _coexist_is_old_factory "$factory" "$src_rel" "$ours_sha"; then
      if ! _coexist_write "$src" "$real" "$mode"; then
        echo "[factory-coexist WARN] 쓰기 실패, 이전 판 유지: $real" >&2; return 0
      fi
      rm -f "$real.factory-new"
      manifest_add "$claude_dir" "$kind" "$name" "$real" "$src_rel" "$mode" || true
      COEXIST_LAST_BRANCH=b; return 0
    fi
    _coexist_park "$src" "$real" "UNKNOWN-BASE" "$name"
    COEXIST_LAST_BRANCH=e; return 0
  fi
  # base 대용(installed_version)으로 복원했더니 theirs 와 같다 → 공장은 그사이 이 파일을 안 바꿨다 → 사실상 c.
  # manifest 에는 **base(=theirs) 의 sha** 를 적어 다음부터 진짜 base 를 알게 한다. ours 의 sha 를 적으면 안 된다 —
  # 하류 판이 "설치판" 으로 오인돼 다음 설치에서 b 로 덮인다(작성 중 스스로 낸 오류, 테스트 전 정정).
  if [[ "$(_manifest_sha "$base_file")" == "$theirs_sha" ]]; then
    rm -f "$base_file"
    _coexist_deliver_if_old "$factory" "$src_rel" "$ours_sha" "$src" "$real" "$mode" "$claude_dir" "$kind" "$name" && return 0
    manifest_add "$claude_dir" "$kind" "$name" "$src" "$src_rel" "$mode" || true   # base(=theirs) 의 sha — src 와 같은 내용
    COEXIST_LAST_BRANCH=c; return 0
  fi
  if _coexist_merge "$real" "$base_file" "$src" "$mode"; then
    manifest_add "$claude_dir" "$kind" "$name" "$real" "$src_rel" "$mode" || true
    echo "[factory-merge MERGED] $name — 하류 수정과 공장 개정을 합쳤습니다(구문 검사 통과)" >&2
    COEXIST_LAST_BRANCH=d
  else
    _coexist_park "$src" "$real" "CONFLICT" "$name"
    COEXIST_LAST_BRANCH=x
  fi
  rm -f "$base_file"
  return 0
}

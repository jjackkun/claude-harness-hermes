#!/usr/bin/env bash
# lib/install_receipt.sh
# Responsibility: 설치 시작 표식을 만들고, 끝에서 표식 이후 바뀐 파일을
# .claude/.last-install.txt(설치 영수증)에 저장소 상대경로로 남긴다.
# 근거: docs/exec-plans/active/2026-09-16-install-receipt.md — 커밋할 경로를 기억으로 정하다
# hermes 스크립트 7개를 5곳에서 빠뜨린 사고.
#
# 공개 함수 2개: receipt_begin · receipt_end

_RECEIPT_NAME=".last-install.txt"
_RECEIPT_MARK=""
# 설치기가 쓰지 않는 큰 디렉터리. 여기 안은 스캔하지 않는다.
_RECEIPT_PRUNE=(.git node_modules .venv venv __pycache__)

# receipt_begin — 지금 이 순간을 표식으로 잡는다. 이 뒤에 쓰인 파일만 영수증에 오른다.
receipt_begin() {
  _RECEIPT_MARK="$(mktemp "${TMPDIR:-/tmp}/install-receipt.XXXXXX")"
  # 파일 시각은 커널 틱 단위라 표식과 같은 틱에 쓰인 파일은 ctime 이 같아 "이후"로 잡히지 않는다
  # (실측 2026-09-16: 나노초까지 동일). 탐침 파일이 표식보다 새로워질 때까지 기다린다.
  local probe="$_RECEIPT_MARK.probe"
  until touch "$probe" && [[ -n "$(find "$probe" -cnewer "$_RECEIPT_MARK")" ]]; do sleep 0.001; done
  rm -f "$probe"
}

# receipt_end <project_path>
# 표식 이후 ctime 이 바뀐 파일(cp -p 로 mtime 이 보존된 것도 포함)을 모아 영수증에 쓴다.
receipt_end() {
  local project="$1"
  [[ -n "$_RECEIPT_MARK" && -f "$_RECEIPT_MARK" ]] || return 0
  local receipt="$project/.claude/$_RECEIPT_NAME"
  local prune_expr=() name
  for name in "${_RECEIPT_PRUNE[@]}"; do
    prune_expr+=(-name "$name" -o)
  done
  unset 'prune_expr[-1]'
  (cd "$project" && find . \( "${prune_expr[@]}" \) -prune -o \( -type f -o -type l \) -cnewer "$_RECEIPT_MARK" -print) \
    | sed 's|^\./||' | grep -vxF ".claude/$_RECEIPT_NAME" | LC_ALL=C sort > "$receipt"
  rm -f "$_RECEIPT_MARK"; _RECEIPT_MARK=""
  log_info "이번 설치가 쓴 파일 $(wc -l < "$receipt")건 → .claude/$_RECEIPT_NAME (커밋: git add \$(git ls-files -co --exclude-standard \$(cat .claude/$_RECEIPT_NAME)))"
}

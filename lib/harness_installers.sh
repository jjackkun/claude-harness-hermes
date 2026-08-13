#!/usr/bin/env bash
# dev-setting/lib/harness_installers.sh
# Responsibility: 하네스(PDF 8~9쪽) 특화 installer — hooks / pre-commit / docs-templates /
# lint-configs / GC workflows / gitignore. 모두 *복사* 사용 (심볼릭 X, 이유: 사용자 편집 + WSL 호환).

# _cleanup_stale_hooks <target_dir>
# 하네스가 과거에 배포했으나 현재 preset 조합에는 없는 hook 스크립트를 제거.
# 사용자가 직접 넣은 스크립트(harness_hook_inventory 에 없는 파일명)는 보존한다.
# hook 은 심볼릭이 아닌 *복사* 라 _cleanup_stale_symlinks 로는 회수되지 않는다.
_cleanup_stale_hooks() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0

  local -A keep=()
  local entry
  for entry in "${HARNESS_HOOK_SOURCES[@]:-}"; do
    [[ -n "$entry" ]] && keep["${entry%%:*}"]=1
  done

  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ -n "${keep[$name]:-}" ]] && continue
    [[ -f "$dir/$name" ]] || continue
    rm -f "$dir/$name"
    log_info "  removed → scripts/hooks/$name"
  done < <(harness_hook_inventory)
}

# install_harness_hooks <project_path>
# assets/hooks/ 의 Claude hook 스크립트를 프로젝트 scripts/hooks/ 로 복사하고
# settings.local.json 에 등록할 hook 항목을 USER_PROMPT_SUBMIT_HOOKS / PRE_TOOL_USE_HOOKS /
# POST_EDIT_HOOKS 에 추가한다. HARNESS_HOOK_SOURCES 에 등록된 파일만 처리.
install_harness_hooks() {
  local project_path="$1"
  local count=${#HARNESS_HOOK_SOURCES[@]}
  local target_dir="$project_path/scripts/hooks"
  if [[ $count -gt 0 ]]; then
    mkdir -p "$target_dir"
    local entry name dest
    for entry in "${HARNESS_HOOK_SOURCES[@]}"; do
      name="${entry%%:*}"
      local src="$ASSETS_DIR/hooks/$name"
      [[ -f "$src" ]] || { log_warn "harness hook missing: $name (skipped)"; continue; }
      dest="$target_dir/$name"
      cp "$src" "$dest"
      chmod +x "$dest"
      log_info "  hook    → scripts/hooks/$name"
    done
  fi
  # preset 에서 빠진 hook 회수 — count==0 (hook 을 쓰는 preset 이 전부 빠진 경우) 에도
  # 실행돼야 하므로 early-return 하지 않는다.
  _cleanup_stale_hooks "$target_dir"
}

# install_harness_pre_commit <project_path>
# assets/hooks/pre-commit.sh 를 .git/hooks/pre-commit 으로 복사 (심볼릭 X — WSL 호환).
install_harness_pre_commit() {
  local project_path="$1"
  [[ ${HARNESS_PRE_COMMIT:-0} -eq 1 ]] || return 0
  local src="$ASSETS_DIR/hooks/pre-commit.sh"
  local git_dir="$project_path/.git"
  [[ -d "$git_dir" ]] || { log_warn ".git not found → pre-commit hook skipped"; return 0; }
  [[ -f "$src" ]] || { log_warn "pre-commit.sh missing in assets (skipped)"; return 0; }
  local dest="$git_dir/hooks/pre-commit"
  mkdir -p "$git_dir/hooks"
  cp "$src" "$dest"
  chmod +x "$dest"
  log_info "  hook    → .git/hooks/pre-commit (4단 검사)"

  # check-component-structure.mjs — pre-commit 이 $(dirname $0) 에서 참조
  local struct_src="$ASSETS_DIR/hooks/check-component-structure.mjs"
  if [[ -f "$struct_src" ]]; then
    cp "$struct_src" "$git_dir/hooks/check-component-structure.mjs"
    chmod +x "$git_dir/hooks/check-component-structure.mjs"
    log_info "  hook    → .git/hooks/check-component-structure.mjs"
  fi

  # check-secrets.py (R-secret) — pre-commit 이 $(dirname $0) 에서 참조.
  local secrets_src="$ASSETS_DIR/hooks/check-secrets.py"
  if [[ -f "$secrets_src" ]]; then
    cp "$secrets_src" "$git_dir/hooks/check-secrets.py"
    chmod +x "$git_dir/hooks/check-secrets.py"
    log_info "  hook    → .git/hooks/check-secrets.py"
  fi

  # plan_state.py (R-plan / R-plan-stale / R-retro) — pre-commit 이 $(dirname $0) 에서 참조.
  # scripts/hooks/ 쪽 사본은 HARNESS_HOOK_SOURCES 가 배치한다(UserPromptSubmit·CI 용).
  local plan_state_src="$ASSETS_DIR/hooks/plan_state.py"
  if [[ -f "$plan_state_src" ]]; then
    if cp "$plan_state_src" "$git_dir/hooks/plan_state.py"; then
      log_info "  hook    → .git/hooks/plan_state.py"
    else
      log_warn "  hook    → .git/hooks/plan_state.py 복사 실패"
    fi
  fi

  # 정답지 모듈(.env 값 집합)을 훅 옆에 둔다 — check-secrets.py 가 import 한다.
  # 복제하지 않고 scripts/ 의 원본을 그대로 복사한다: 복제본만 고치고 원본을 두면
  # 원본을 쓰는 경로(DB 적재 마스킹)가 계속 뚫려 있게 된다.
  # hermes 프리셋 없이 harness 만 설치한 프로젝트에서도 값 기반 차단이 동작한다.
  local values_src="$DEV_SETTING_DIR/scripts/hermes_secret_values.py"
  if [[ -f "$values_src" ]]; then
    cp "$values_src" "$git_dir/hooks/hermes_secret_values.py"
    log_info "  hook    → .git/hooks/hermes_secret_values.py"
  fi
}

# harness_sync_marker_block <src> <dest> <begin> <end>
# src 의 마커 블록으로 dest 의 마커 블록을 교체. dest 에 블록이 없으면 파일 끝에 추가.
# 마커 밖 내용은 건드리지 않는다 (install_harness_gitignore 와 같은 방식).
harness_sync_marker_block() {
  local src="$1" dest="$2" begin="$3" end="$4"
  local block
  block="$(awk -v b="$begin" -v e="$end" '$0==b{f=1} f{print} $0==e{f=0}' "$src")"
  [[ -n "$block" ]] || return 0

  if grep -qF "$begin" "$dest"; then
    awk -v b="$begin" -v e="$end" -v blk="$block" '
      $0==b {print blk; skip=1; next}
      $0==e {skip=0; next}
      !skip {print}
    ' "$dest" > "$dest.tmp$$" && mv "$dest.tmp$$" "$dest"
  else
    printf '\n%s\n' "$block" >> "$dest"
  fi
  log_info "  doc     → $(basename "$dest") (하네스 룰 블록 갱신)"
}

# install_harness_docs_templates <project_path>
# assets/docs-templates/ 의 템플릿을 프로젝트로 복사. *기존 파일 덮어쓰지 않음*
# (사용자가 채운 내용을 지키기 위해).
install_harness_docs_templates() {
  local project_path="$1"
  [[ ${HARNESS_DOCS_TEMPLATES:-0} -eq 1 ]] || return 0
  local src_dir="$ASSETS_DIR/docs-templates"
  [[ -d "$src_dir" ]] || { log_warn "docs-templates missing in assets (skipped)"; return 0; }

  local copied=0
  # 루트 템플릿 (CLAUDE.md.tmpl, ARCHITECTURE.md.tmpl) — 이름에서 .tmpl 제거 후 복사.
  local f base dest
  for f in "$src_dir"/*.tmpl; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f" .tmpl)"
    dest="$project_path/$base"
    if [[ -e "$dest" ]]; then
      log_info "  doc     → $base (이미 존재, 보존)"
    else
      sed "s|{{PROJECT_NAME}}|$(basename "$project_path")|g; s|{{PROJECT_ROOT}}|$(basename "$project_path")|g" "$f" > "$dest"
      log_info "  doc     → $base (생성)"
      copied=$((copied + 1))
    fi
  done

  # docs/ 하위 템플릿 — 디렉터리 구조 유지.
  if [[ -d "$src_dir/docs" ]]; then
    while IFS= read -r f; do
      local rel="${f#$src_dir/}"
      base="${rel%.tmpl}"
      dest="$project_path/$base"
      # core-beliefs 는 마커 블록만 갱신한다 — 프로젝트 고유 R 룰은 사용자 소유이고,
      # 하네스 룰 앵커는 하네스 소유다. 통째로 보존하면 pre-commit 메시지가 가리키는
      # 앵커가 설치 프로젝트에서 영원히 깨진 채로 남는다.
      if [[ "$base" == "docs/design-docs/core-beliefs.md" && -e "$dest" ]]; then
        harness_sync_marker_block "$f" "$dest" \
          '<!--===HARNESS-RULES:BEGIN===-->' '<!--===HARNESS-RULES:END===-->'
        continue
      fi
      if [[ -e "$dest" ]]; then
        continue
      fi
      mkdir -p "$(dirname "$dest")"
      cp "$f" "$dest"
      copied=$((copied + 1))
    done < <(find "$src_dir/docs" -type f \( -name "*.tmpl" -o -name "*.md" \) 2>/dev/null)
    log_info "  docs/   → $copied 개 템플릿 (기존 보존)"
  fi
}

# install_harness_lint_configs <project_path>
# assets/lint-configs/eslint/max-lines.config.js 를 프로젝트의 lint-configs/ 폴더로 복사.
install_harness_lint_configs() {
  local project_path="$1"
  [[ ${HARNESS_LINT_MAX_LINES:-0} -eq 1 ]] || return 0
  local src="$ASSETS_DIR/lint-configs/eslint/max-lines.config.js"
  [[ -f "$src" ]] || return 0
  local target_dir="$project_path/lint-configs"
  mkdir -p "$target_dir"
  cp "$src" "$target_dir/harness-max-lines.config.js"
  log_info "  lint    → lint-configs/harness-max-lines.config.js"

  # R-struct-3: .vue 직접 import 금지 ESLint config
  if [[ ${HARNESS_COMPONENT_STRUCTURE:-0} -eq 1 ]]; then
    local struct_src="$ASSETS_DIR/lint-configs/eslint/component-structure.config.js"
    if [[ -f "$struct_src" ]]; then
      cp "$struct_src" "$target_dir/harness-component-structure.config.js"
      log_info "  lint    → lint-configs/harness-component-structure.config.js"
    fi
  fi
}

# install_harness_gc_workflows <project_path>
# PDF 12쪽 "정기 가비지 컬렉션" 중 weekly-doc-gardening 만 자동 배치.
# git remote 를 감지해 host 에 맞는 템플릿을 복사한다.
#   - github.com → .github/workflows/weekly-doc-gardening.yml
#   - gitlab.com 또는 host 에 'gitlab' 포함 → .gitlab/doc-gardening.yml
#   - 기타/없음 → 스킵 + 안내 로그
# 사용자가 손대지 않은 설치본은 갱신한다 (harness_write_marked_template).

# harness_template_sha <file>
# 마커 줄을 제외한 본문의 sha256. 설치본이 사용자에 의해 수정됐는지 판정하는 데 쓴다.
# cmp -s 와 달리 템플릿이 개정돼도 판정이 유지된다.
# `|| true` 필수: 호출부가 set -euo pipefail 아래에서 돈다(project-claude.sh:23).
# grep 이 아무것도 못 찾으면 1 을 반환하고 pipefail 이 그것을 파이프라인 상태로 올려
# 설치기 전체가 중단된다.
harness_template_sha() {
  { grep -v '^# harness-template-sha:' "$1" || true; } | sha256sum | cut -d' ' -f1
}

# 마커 도입(2026-08-13) 이전에 배포된 템플릿의 본문 해시.
#
# 마커가 없는 설치본은 기본적으로 "사용자 수정본" 으로 보고 보존하는데, 첫 세대는
# 마커 자체가 없었으므로 손대지 않은 파일까지 전부 보존돼 개정본이 영원히 도달하지
# 않는다. 실제로 2026-08-13 전파에서 8개 프로젝트가 미수정인데도 모두 보존됐고,
# 그 결과 죽은 status grep 이 그대로 남았다.
#
# 이 목록과 일치하면 미수정 구버전으로 보고 갱신한다. 템플릿을 개정할 때 직전
# 배포본의 해시를 추가할 필요는 없다 — 마커가 심긴 뒤부터는 마커로 판정된다.
HARNESS_LEGACY_TEMPLATE_SHAS=(
  # weekly-doc-gardening.gitlab-ci.yml @ 6b27dfa
  "468f5ec6b5120baf3e681d94cc45924016b9dfaa0e040e8f4b6a5eca0539cdfd"
  # weekly-doc-gardening.yml (github-actions) @ 6b27dfa
  "2de09d9f7f3ff94aacded7eaa2f6d8e3417a16078304f9227da7ee49eb72f385"
)

# harness_is_known_legacy <file>
harness_is_known_legacy() {
  local sha
  sha="$(sha256sum "$1" | cut -d' ' -f1)"
  local known
  for known in "${HARNESS_LEGACY_TEMPLATE_SHAS[@]:-}"; do
    [[ "$sha" == "$known" ]] && return 0
  done
  return 1
}

# harness_write_marked_template <src> <dest> <label>
# 사용자가 손대지 않은 설치본만 덮어쓴다.
#
# 이 판정이 없으면 "기존 보존" 정책 탓에 템플릿 개정본이 기존 프로젝트에 영원히
# 도달하지 않는다 — 경고하는 검사만 배포되고 그것을 보완할 수거 장치는 배포되지 않는
# 비대칭이 생긴다(2026-08-13 확인).
harness_write_marked_template() {
  local src="$1" dest="$2" label="$3"
  local src_sha
  src_sha="$(harness_template_sha "$src")"

  if [[ -e "$dest" ]]; then
    local dest_marker dest_sha
    # 마커가 없으면 grep 이 1 을 반환하고 pipefail 이 설치기를 중단시킨다 — `|| true` 필수.
    dest_marker="$(grep -m1 '^# harness-template-sha:' "$dest" 2>/dev/null | awk '{print $3}' || true)"
    if [[ -z "$dest_marker" ]]; then
      # 마커 도입 이전 배포본이면 미수정으로 보고 갱신한다(위 목록 참조).
      # 마커가 없으므로 아래 해시 비교는 건너뛴다 — 비교하면 항상 불일치라 보존으로 빠진다.
      if harness_is_known_legacy "$dest"; then
        log_info "  workflows → $label (알려진 구버전 — 갱신)"
      else
        log_warn "  workflows → $label (마커 없는 구버전 — 보존. 수동 갱신 필요)"
        return 0
      fi
    else
      dest_sha="$(harness_template_sha "$dest")"
      if [[ "$dest_sha" != "$dest_marker" ]]; then
        log_info "  workflows → $label (사용자 수정 감지 — 보존)"
        return 0
      fi
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  if sed "s|^# harness-template-sha:.*|# harness-template-sha: $src_sha|" "$src" > "$dest"; then
    log_info "  workflows → $label (배치)"
  else
    log_warn "  workflows → $label 쓰기 실패"
  fi
}
install_harness_gc_workflows() {
  local project_path="$1"
  [[ ${HARNESS_DOC_GARDENING:-0} -eq 1 ]] || return 0

  local remote=""
  if [[ -d "$project_path/.git" ]]; then
    remote=$(git -C "$project_path" config --get remote.origin.url 2>/dev/null || true)
  fi

  if [[ -z "$remote" ]]; then
    log_info "  workflows → skipped (git remote 없음 — doc-gardening 배치 생략)"
    return 0
  fi

  case "$remote" in
    *github.com*)
      local src="$ASSETS_DIR/cron-templates/github-actions/weekly-doc-gardening.yml"
      local dest_dir="$project_path/.github/workflows"
      local dest="$dest_dir/weekly-doc-gardening.yml"
      [[ -f "$src" ]] || { log_warn "github doc-gardening template missing"; return 0; }
      harness_write_marked_template "$src" "$dest" ".github/workflows/weekly-doc-gardening.yml"
      log_info "            ↳ scripts/hooks/{plan_state.py,doc-gardening-drift.sh} 를 커밋해야 주간 점검이 동작합니다"
      ;;
    *gitlab*|git@*gitlab*)
      local src="$ASSETS_DIR/cron-templates/gitlab-ci/weekly-doc-gardening.gitlab-ci.yml"
      local dest_dir="$project_path/.gitlab"
      local dest="$dest_dir/doc-gardening.yml"
      [[ -f "$src" ]] || { log_warn "gitlab doc-gardening template missing"; return 0; }
      harness_write_marked_template "$src" "$dest" ".gitlab/doc-gardening.yml"
      log_info "            ↳ .gitlab-ci.yml 에 'include: { local: .gitlab/doc-gardening.yml }' 추가 + Schedules 설정 필요"
      log_info "            ↳ scripts/hooks/{plan_state.py,doc-gardening-drift.sh} 를 커밋해야 주간 점검이 동작합니다"
      ;;
    *)
      log_info "  workflows → skipped (미지원 remote host: $remote)"
      ;;
  esac
}

# install_harness_gitignore <project_path> <target>
# .gitignore 에 머신 로컬 항목(settings.local.json 등)을 마커 블록으로 추가/갱신.
# 마커 사이만 교체하므로 재실행 시 중복이 쌓이지 않고, 마커 밖의 사용자 항목은 보존.
#   target: claude | codex
install_harness_gitignore() {
  local project_path="$1"
  local target="$2"
  local gitignore="$project_path/.gitignore"
  local begin="# >>> harness-agent-preset >>>"
  local end="# <<< harness-agent-preset <<<"

  local entries=()
  case "$target" in
    claude) entries=(
      ".claude/settings.local.json"
      ".claude/worktrees/"
      ".claude/.review-dirty"
      ".claude/.dev-setting-manifest.json"
      ".claude/presets.lock"
      "!.claude/memory/"
      "!.claude/memory/**"
    ) ;;
    codex)  entries=(".codex/settings.local.json") ;;
    *) return 0 ;;
  esac

  # 프리셋에서 GITIGNORE_ENTRIES 배열로 추가된 항목 병합 (중복 제거)
  local _extra_count=0
  [[ -n "${GITIGNORE_ENTRIES+x}" ]] && _extra_count=${#GITIGNORE_ENTRIES[@]}
  if [[ $_extra_count -gt 0 ]]; then
    local e_extra e_existing found
    for e_extra in "${GITIGNORE_ENTRIES[@]}"; do
      found=0
      for e_existing in "${entries[@]}"; do
        [[ "$e_existing" == "$e_extra" ]] && found=1 && break
      done
      [[ $found -eq 0 ]] && entries+=("$e_extra")
    done
  fi

  local block
  block="$begin"$'\n'
  block+="# Auto-managed by ai-dev-setting. Do not edit between markers."$'\n'
  local e
  for e in "${entries[@]}"; do
    block+="$e"$'\n'
  done
  block+="$end"

  # .claude/ (통째 ignore) → .claude/* + !.claude/settings.json 자동 교체
  # git 은 디렉터리 자체가 ignored 이면 하위 negation 이 무시됨.
  if [[ -f "$gitignore" ]] && grep -qE '^\.claude/?$' "$gitignore"; then
    local tmp_fix
    tmp_fix="$(mktemp)"
    awk '
      /^\.claude\/?$/ { print ".claude/*"; print "!.claude/settings.json"; print "!.claude/memory/"; print "!.claude/memory/**"; next }
      { print }
    ' "$gitignore" > "$tmp_fix"
    mv "$tmp_fix" "$gitignore"
    log_info "  gitignore → .claude/ 를 .claude/* 로 교체 (settings.json 추적 가능)"
  fi

  if [[ ! -f "$gitignore" ]]; then
    printf '%s\n' "$block" > "$gitignore"
    log_info "  gitignore → .gitignore (생성, ${#entries[@]}개 항목)"
    return 0
  fi

  # ★CR 을 벗겨 비교한다. Windows 에서 만들어진 .gitignore 는 CRLF 라 마커가
  # "# >>> … >>>\r" 이 되고, 정확 일치 매칭이 실패해 **갱신 대신 블록이 중복 추가**된다.
  # 실제로 jjackkun_bot 에서 블록이 두 벌 쌓였다. 재설치할 때마다 늘어난다.
  # LF 판과 CR 판을 **고정 문자열로** 각각 확인한다. 정규식(`\r\?$`)은 grep 구현에
  # 따라 `\?` 해석이 갈려 매칭이 조용히 실패했다 — 그러면 갱신 대신 블록이 덧붙는다.
  if grep -qxF "$begin" "$gitignore" || grep -qxF "$begin"$'\r' "$gitignore"; then
    local tmp
    tmp="$(mktemp)"
    awk -v b="$begin" -v e="$end" -v repl="$block" '
      { line = $0; sub(/\r$/, "", line) }
      line == b { skip=1; print repl; next }
      skip && line == e { skip=0; next }
      !skip { print }
    ' "$gitignore" > "$tmp"
    mv "$tmp" "$gitignore"
    log_info "  gitignore → .gitignore (블록 갱신)"
  else
    [[ -s "$gitignore" ]] && [[ -n "$(tail -c1 "$gitignore")" ]] && printf '\n' >> "$gitignore"
    printf '\n%s\n' "$block" >> "$gitignore"
    log_info "  gitignore → .gitignore (블록 추가, ${#entries[@]}개 항목)"
  fi
}

# install_memory_symlink <project_path>
# 네이티브 메모리(~/.claude/projects/<키>/memory)를 <project>/.claude/memory 로 링크해 버전관리.
# 심링크 우선, NTFS 마운트면 복사 폴백(설치 실패 방지). 기존 메모리는 비파괴 이관. 멱등.
install_memory_symlink() {
  local project_path="$1"
  local repo_mem="$project_path/.claude/memory"          # git 추적 실원본
  local key native_mem
  key="$(printf '%s' "$project_path" | sed 's/[^a-zA-Z0-9]/-/g')"
  native_mem="$HOME/.claude/projects/$key/memory"        # Claude Code 기록 위치

  mkdir -p "$repo_mem"

  if [[ -L "$native_mem" ]]; then
    # 이미 심링크 — 올바른 대상이면 멱등 종료, 아니면 교정
    [[ "$(readlink "$native_mem")" == "$repo_mem" ]] && return 0
    rm -f "$native_mem"
  elif [[ -d "$native_mem" ]]; then
    # 실디렉터리 — 기존 .md 를 repo 로 비파괴 이관 후 제거(cp 전량 성공 검증 없이는 삭제 금지)
    # (동기화 유지: 동일 비파괴 이관 로직이 assets/hooks/claude-sessionstart-memory-guard.sh 에도 인라인 존재)
    local copy_failed=0 f rel dest
    while IFS= read -r -d '' f; do
      rel="${f#"$native_mem"/}"
      dest="$repo_mem/$rel"
      mkdir -p "$(dirname "$dest")"
      if [[ -e "$dest" ]]; then
        # 동명 충돌 — 내용이 다르면 네이티브본을 .native 로 보존(무손실), repo 본은 유지
        if ! cmp -s "$f" "$dest"; then
          # .native 백업 자체도 충돌-안전하게: 기존 백업을 덮어쓰지 않고 번호 부여
          local native_dest="$dest.native" n=1
          while [[ -e "$native_dest" ]]; do
            cmp -s "$f" "$native_dest" && native_dest=""  # 이미 동일 내용으로 백업됨 — no-op
            [[ -z "$native_dest" ]] && break
            native_dest="$dest.native.$n"
            n=$((n + 1))
          done
          if [[ -n "$native_dest" ]] && ! cp -p "$f" "$native_dest" 2>/dev/null; then
            echo "install_memory_symlink: 충돌본 보존 실패 — $rel" >&2
            copy_failed=1
          fi
        fi
      elif ! cp -p "$f" "$dest" 2>/dev/null; then
        echo "install_memory_symlink: 이관 실패 — $rel" >&2
        copy_failed=1
      fi
    done < <(find "$native_mem" -type f -print0)

    if [[ "$copy_failed" -ne 0 ]]; then
      echo "install_memory_symlink: 일부 파일 이관 실패 — 네이티브 보존, 심링크 생략(재시도 필요)" >&2
      return 1
    fi
    rm -rf "$native_mem"
  fi

  mkdir -p "$(dirname "$native_mem")"

  if is_windows_path "$native_mem" || is_windows_path "$repo_mem"; then
    # NTFS 마운트: 심링크 불가 → 복사 폴백(설치는 성공). 지속 동기화는 가드 훅(Task 3)이 보완.
    cp -r "$repo_mem" "$native_mem"
  else
    ln -s "$repo_mem" "$native_mem"
  fi
}

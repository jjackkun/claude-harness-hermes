#!/usr/bin/env bash
# dev-setting/lib/harness_installers.sh
# Responsibility: 하네스(PDF 8~9쪽) 특화 installer — hooks / pre-commit / docs-templates /
# lint-configs / GC workflows / gitignore. 모두 *복사* 사용 (심볼릭 X, 이유: 사용자 편집 + WSL 호환).

# install_harness_hooks <project_path>
# assets/hooks/ 의 Claude hook 스크립트를 프로젝트 scripts/hooks/ 로 복사하고
# settings.local.json 에 등록할 hook 항목을 USER_PROMPT_SUBMIT_HOOKS / PRE_TOOL_USE_HOOKS /
# POST_EDIT_HOOKS 에 추가한다. HARNESS_HOOK_SOURCES 에 등록된 파일만 처리.
install_harness_hooks() {
  local project_path="$1"
  local count=${#HARNESS_HOOK_SOURCES[@]}
  [[ $count -eq 0 ]] && return 0
  local target_dir="$project_path/scripts/hooks"
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
# 기존 파일은 덮어쓰지 않는다 (사용자 개인화 보존).
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
      mkdir -p "$dest_dir"
      if [[ -e "$dest" ]]; then
        log_info "  workflows → .github/workflows/weekly-doc-gardening.yml (이미 존재, 보존)"
      else
        cp "$src" "$dest"
        log_info "  workflows → .github/workflows/weekly-doc-gardening.yml (신규)"
      fi
      ;;
    *gitlab*|git@*gitlab*)
      local src="$ASSETS_DIR/cron-templates/gitlab-ci/weekly-doc-gardening.gitlab-ci.yml"
      local dest_dir="$project_path/.gitlab"
      local dest="$dest_dir/doc-gardening.yml"
      [[ -f "$src" ]] || { log_warn "gitlab doc-gardening template missing"; return 0; }
      mkdir -p "$dest_dir"
      if [[ -e "$dest" ]]; then
        log_info "  workflows → .gitlab/doc-gardening.yml (이미 존재, 보존)"
      else
        cp "$src" "$dest"
        log_info "  workflows → .gitlab/doc-gardening.yml (신규)"
        log_info "            ↳ .gitlab-ci.yml 에 'include: { local: .gitlab/doc-gardening.yml }' 추가 + Schedules 설정 필요"
      fi
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
      /^\.claude\/?$/ { print ".claude/*"; print "!.claude/settings.json"; next }
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

  if grep -qxF "$begin" "$gitignore"; then
    local tmp
    tmp="$(mktemp)"
    awk -v b="$begin" -v e="$end" -v repl="$block" '
      $0 == b { skip=1; print repl; next }
      skip && $0 == e { skip=0; next }
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
    local copy_failed=0 f rel dest
    while IFS= read -r -d '' f; do
      rel="${f#"$native_mem"/}"
      dest="$repo_mem/$rel"
      mkdir -p "$(dirname "$dest")"
      if [[ -e "$dest" ]]; then
        # 동명 충돌 — 내용이 다르면 네이티브본을 .native 로 보존(무손실), repo 본은 유지
        if ! cmp -s "$f" "$dest"; then
          if ! cp -p "$f" "$dest.native" 2>/dev/null; then
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

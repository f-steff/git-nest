#!/bin/sh
#
# git-stack 0.4.1
#
# Lightweight multi-repository workspace coordination for ordinary Git remotes.
# A stack root repository tracks a manifest of nested stack module repositories,
# while this script provides the command behavior for initializing, syncing,
# branching, uploading, finalizing, and verifying that workspace state.
#
# This file is the shared shell implementation sourced by bin/git-stack.
# Keeping command logic here leaves the PATH-facing entrypoint tiny while
# avoiding a separate lib/ tree for a small script-first project. The Windows
# wrapper reaches this code indirectly by launching bin/git-stack through
# Git Bash.
#
# Copyright (C) 2026 fsteff.
# License: GNU Affero General Public License v3.0 or later
# SPDX-License-Identifier: AGPL-3.0-or-later

MANIFEST_FILE=${GIT_STACK_MANIFEST:-.stack}
CONFIG_FILE=${GIT_STACK_CONFIG:-.stack-rc}
GIT_STACK_VERSION=0.4.1

# Print a user-facing error and stop the current command with a nonzero exit.
die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

# Print a recoverable warning while allowing the caller to continue.
warn() {
    printf 'Warning: %s\n' "$*" >&2
}

# Print an informational diagnostic for optional follow-up actions.
notice() {
    printf 'Notice: %s\n' "$*" >&2
}

# Guard required values before writing manifest state or invoking Git actions.
require_value() {
    value=$1
    message=$2
    [ -n "$value" ] || die "$message"
}

# Resolve a ref to a commit SHA and explain how to recover if it cannot resolve.
resolve_commit() {
    repo=$1
    ref=$2
    context=$3
    require_value "$ref" "$context: missing ref; provide an explicit commit, tag, or branch"
    sha=$(git -C "$repo" rev-parse --verify "$ref^{commit}" 2>/dev/null) ||
        die "$context: ref '$ref' does not resolve to a commit in $repo; fetch the repository or provide an explicit revision"
    require_value "$sha" "$context: resolved ref '$ref' to an empty commit id in $repo"
    printf '%s\n' "$sha"
}

# Resolve HEAD for callers that need the current commit, such as add/upload.
resolve_head_commit() {
    repo=$1
    context=$2
    resolve_commit "$repo" HEAD "$context"
}

# Show the command surface exposed by the shared implementation.
usage() {
    cat <<'EOF'
git-stack: coordinate branches and pinned revisions across nested Git repositories

Usage:
  git-stack init [--rc]
  git-stack add [--clone <full|partial>] <repo> <path>
  git-stack status [--recursive] [--porcelain]
  git-stack available [--recursive] [--porcelain]
  git-stack verify [--recursive]
  git-stack log [--max-count <n>] [--since <date>] [--until <date>] [--module <path>] [--oneline] [--recursive]
  git-stack start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]
  git-stack refresh [--quiet]
  git-stack upload [--finalize]
  git-stack install-hooks
  git-stack remove-hooks
  git-stack foreach -- <command> [args...]
  git-stack foreach-modified -- <command> [args...]
  git-stack check
  git-stack update <module> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]
  git-stack finalize <module> [--cleanup] [--revision <sha> | --tag <tag> | --use-target-head]
  git-stack cleanup-branches
  git-stack sync [--recursive]
  git-stack version

Commands:
  init [--rc]
      Create a .stack manifest in the current workspace.
          --rc also creates .stack-rc with default values.
  add [--clone <full|partial>] <repo> <path>
      Add and clone a stack module, ignore its path in the outer repo, and
      record its current target branch and revision.
          --clone selects full or partial clone storage for this module.
  status [--recursive] [--porcelain]
      Show stack and module state.
          --recursive includes nested stacks.
          --porcelain prints stable tab-separated dirty/missing records for scripts.
  available [--recursive] [--porcelain]
      Check module remotes for newer target-branch commits without fetching.
          --recursive includes nested stacks.
          --porcelain prints stable records for available updates, missing
          checkouts, and remote query errors.
  verify [--recursive]
      Validate manifest, remotes, refs, clone mode, and checked-out revisions.
          --recursive includes nested stacks.
  log [--max-count <n>] [--since <date>] [--until <date>] [--module <path>] [--oneline] [--recursive]
      Show combined stack history. Filters mirror common git log concepts;
          --max-count limits commits per repository before the final sort.
          --since and --until filter commits by date.
          --module restricts output to one module path.
          --oneline uses compact commit output.
          --recursive includes nested stacks.
  start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]
      Start or track a coordinated stack branch.
          --stash-dirty stashes dirty repositories before switching.
          --discard-dirty discards tracked edits, then rejects untracked files.
          --cancel-dirty fails if any repository is dirty.
          --hooks installs managed hooks.
          --sure confirms startup in a non-Git folder with subdirectories.
  refresh [--quiet]
      Refresh local manifest state without pushing.
          --quiet suppresses skip warnings for dirty modules.
  upload [--finalize]
      Push changed module branches and the outer branch. By default records
      pending module state.
          --finalize pins pushed module commits directly.
  install-hooks
      Install managed local Git hooks for this stack.
  remove-hooks
      Remove managed local Git hooks for this stack.
  foreach -- <command> [args...]
      Run a command in every checked-out stack module.
  foreach-modified -- <command> [args...]
      Run a command only in manifest-pending stack modules.
  check
      Fail while any module remains pending.
  update <module> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]
      Move one clean, non-pending module to a selected revision.
          --remote and --target-head use the target branch head.
          --revision pins an explicit commit-ish.
          --tag pins a tag and records the tag name.
          --branch retargets before resolving the selected revision.
          --no-fetch resolves only local refs.
  finalize <module> [--cleanup] [--revision <sha> | --tag <tag> | --use-target-head]
      Convert a pending module to a pinned revision.
          --revision pins an explicit commit.
          --tag pins a tag and records the tag name.
          --use-target-head pins the target branch head.
          --cleanup deletes the local pending branch after finalization.
  cleanup-branches
      Delete local branches recorded as finalized cleanup hints.
  sync [--recursive]
      Clone/fetch modules and restore the manifest state.
          --recursive includes nested stacks.
  version
      Print the git-stack version.

Manifest: .stack
EOF
}

# Dispatch the public command name to the matching command handler.
git_stack_main() {
    cmd=${1:-}
    [ $# -gt 0 ] && shift || true

    case "$cmd" in
        init) enter_workspace_root_if_present; cmd_init "$@" ;;
        add) enter_workspace_root_if_present; cmd_add "$@" ;;
        status) enter_stack_root_required; cmd_status "$@" ;;
        available) enter_stack_root_required; cmd_available "$@" ;;
        verify) enter_stack_root_required; cmd_verify "$@" ;;
        log) enter_stack_root_required; cmd_log "$@" ;;
        start) enter_workspace_root_if_present; cmd_start "$@" ;;
        refresh) enter_stack_root_required; cmd_refresh "$@" ;;
        record) enter_stack_root_required; cmd_refresh "$@" ;;
        upload) enter_stack_root_required; cmd_upload "$@" ;;
        install-hooks) enter_stack_root_required; cmd_install_hooks "$@" ;;
        remove-hooks) enter_stack_root_required; cmd_remove_hooks "$@" ;;
        foreach) enter_stack_root_required; cmd_foreach "$@" ;;
        foreach-modified) enter_stack_root_required; cmd_foreach_modified "$@" ;;
        check) enter_stack_root_required; cmd_check "$@" ;;
        update) enter_stack_root_required; cmd_update "$@" ;;
        finalize) enter_stack_root_required; cmd_finalize "$@" ;;
        cleanup-branches) enter_stack_root_required; cmd_cleanup_branches "$@" ;;
        sync) enter_stack_root_required; cmd_sync "$@" ;;
        version|--version) cmd_version "$@" ;;
        -h|--help|help|"") usage ;;
        *) die "unknown command: $cmd" ;;
    esac
}

# Report the implemented tool version used by docs and tests.
cmd_version() {
    [ $# -eq 0 ] || die "version takes no arguments"
    printf 'git-stack %s\n' "$GIT_STACK_VERSION"
}

# Ensure Git is available before commands depend on it.
require_git() {
    command -v git >/dev/null 2>&1 || die "git is required"
}

# Walk upward from the current directory to find the outer stack manifest. Git
# repository discovery stops at nested module roots, so stack discovery must use
# the manifest instead of git rev-parse.
find_stack_root() {
    dir=$(pwd)
    while :; do
        if [ -f "$dir/$MANIFEST_FILE" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        parent=$(dirname "$dir")
        [ "$parent" != "$dir" ] || return 1
        dir=$parent
    done
}

# Commands that can create a workspace still anchor to an existing stack or Git
# root when one is visible, preventing accidental nested manifests from subdirs.
enter_workspace_root_if_present() {
    require_git
    if root=$(find_stack_root 2>/dev/null); then
        cd "$root" || die "cannot enter stack root $root"
        return
    fi
    if root=$(git rev-parse --show-toplevel 2>/dev/null); then
        cd "$root" || die "cannot enter Git root $root"
    fi
}

# Operational commands need an existing manifest and always run from its root so
# module paths in .stack are interpreted consistently.
enter_stack_root_required() {
    require_git
    root=$(find_stack_root 2>/dev/null) ||
        die "not inside a git-stack workspace; run git-stack init or cd to a stack"
    cd "$root" || die "cannot enter stack root $root"
}

# Return the outer repository root when inside Git, otherwise the current path.
repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Make sure the outer workspace is a Git repository, creating it if needed.
ensure_outer_repo() {
    require_git
    if [ ! -d .git ]; then
        git init >/dev/null
    fi
}

# Check whether a non-Git startup folder contains immediate subdirectories.
startup_has_subdirectories() {
    for path in ./*; do
        [ -d "$path" ] || continue
        return 0
    done
    return 1
}

# Ask before initializing a non-Git folder with subdirectories unless --sure is set.
confirm_startup_directory() {
    sure=$1
    if [ -d .git ]; then
        return
    fi
    startup_has_subdirectories || return 0
    [ "$sure" -eq 1 ] && return
    if [ ! -t 0 ]; then
        die "start would initialize a folder containing subdirectories; rerun with --sure to confirm"
    fi
    printf 'This folder contains subdirectories. Initialize it as a git-stack workspace? [y/N] ' >/dev/tty
    IFS= read -r answer </dev/tty || answer=
    case "$answer" in
        y|Y|yes|YES) ;;
        *) die "start canceled" ;;
    esac
}

# Create the manifest skeleton lazily for commands that need manifest state.
ensure_manifest() {
    if [ ! -f "$MANIFEST_FILE" ]; then
        {
            printf '# git-stack manifest\n\n'
            printf '[stack]\n'
        } >"$MANIFEST_FILE"
    fi
}

# Create the default runtime configuration file when a workspace is initialized.
ensure_config() {
    [ -f "$CONFIG_FILE" ] || {
        {
            printf '[branch]\n'
            printf 'pattern={ticket}-{slug}\n\n'
            printf '[ticket]\n'
            printf 'regex=[A-Z]+-[0-9]+\n\n'
            printf '[defaults]\n'
            printf 'target_branch=main\n'
            printf 'manifest=%s\n\n' "$MANIFEST_FILE"
            printf '[clone]\n'
            printf 'mode=manifest\n'
        } >"$CONFIG_FILE"
    }
}

# Normalize module paths so manifest section names are stable across platforms.
normalize_path() {
    printf '%s\n' "$1" | sed 's#\\#/#g; s#//*#/#g; s#/$##'
}

# Create a temporary file next to a target file so later mv is same-directory.
tmp_for() {
    dir=$(dirname -- "$1")
    base=$(basename -- "$1")
    mktemp "$dir/.${base}.tmp.XXXXXX"
}

# Read one key from one manifest section; callers decide whether empty is valid.
manifest_get() {
    section=$1
    key=$2
    awk -v section="$section" -v key="$key" '
        $0 == "[" section "]" { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && index($0, key "=") == 1 {
            print substr($0, length(key) + 2)
            exit
        }
    ' "$MANIFEST_FILE"
}

# Read a value from .stack-rc. Missing config is normal for copied manifests, so
# callers provide defaults after this helper returns no value.
config_get() {
    section=$1
    key=$2
    [ -f "$CONFIG_FILE" ] || return 1
    awk -v section="$section" -v key="$key" '
        $0 == "[" section "]" { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && index($0, key "=") == 1 {
            print substr($0, length(key) + 2)
            exit
        }
    ' "$CONFIG_FILE"
}

# List module paths from manifest section headers.
manifest_modules() {
    [ -f "$MANIFEST_FILE" ] || return 0
    sed -n 's/^\[module "\([^"]*\)"\]$/\1/p' "$MANIFEST_FILE"
}

# Remove one complete section before rewriting fresh state for it.
manifest_remove_section() {
    section=$1
    tmp=$(tmp_for "$MANIFEST_FILE")
    awk -v section="$section" '
        $0 == "[" section "]" { skip=1; next }
        /^\[/ { skip=0 }
        !skip { print }
    ' "$MANIFEST_FILE" >"$tmp"
    mv "$tmp" "$MANIFEST_FILE"
}

# Rewrite the stack section with the current ticket and outer branch identity.
manifest_write_stack() {
    stack_id=$1
    branch=$2
    ensure_manifest
    manifest_remove_section "stack"
    tmp=$(tmp_for "$MANIFEST_FILE")
    {
        printf '[stack]\n'
        [ -n "$stack_id" ] && printf 'id=%s\n' "$stack_id"
        [ -n "$branch" ] && printf 'branch=%s\n' "$branch"
        printf '\n'
        sed '/^$/N;/^\n$/D' "$MANIFEST_FILE"
    } >"$tmp"
    mv "$tmp" "$MANIFEST_FILE"
}

# Write one module section after validating state-specific required fields.
manifest_write_module() {
    path=$1
    repo=$2
    state=$3
    a=${4:-}
    b=${5:-}
    c=${6:-}
    d=${7:-}
    e=${8:-}
    previous_clone=
    [ -f "$MANIFEST_FILE" ] && previous_clone=$(module_key "$path" clone || true)

    require_value "$path" "cannot write manifest module with an empty path"
    require_value "$repo" "cannot write manifest module $path without a repository URL"
    case "$state" in
        finalized)
            require_value "$a" "cannot finalize $path without a resolved revision; fetch the module or pass --revision <sha>"
            clone=${d:-$previous_clone}
            ;;
        pending)
            require_value "$a" "cannot mark $path pending without a target branch"
            require_value "$b" "cannot mark $path pending without a pending branch; check out a named branch first"
            require_value "$c" "cannot mark $path pending without a base revision; fetch the module target branch"
            require_value "$d" "cannot mark $path pending without a pushed commit; commit work before upload"
            clone=${e:-$previous_clone}
            ;;
        tracked)
            require_value "$a" "cannot track $path without a target branch"
            clone=${c:-$previous_clone}
            ;;
        *) die "unknown manifest state for $path: $state" ;;
    esac
    validate_clone_mode "$clone" "module $path clone mode"

    ensure_manifest
    manifest_remove_section "module \"$path\""
    {
        printf '\n[module "%s"]\n' "$path"
        printf 'repo=%s\n' "$repo"
        if [ -n "$clone" ]; then
            printf 'clone=%s\n' "$clone"
        fi
        case "$state" in
            finalized)
                if [ -n "$b" ]; then
                    printf 'tag=%s\n' "$b"
                fi
                printf 'revision=%s\n' "$a"
                if [ -n "$c" ]; then
                    printf 'finalized_from_branch=%s\n' "$c"
                fi
                ;;
            pending)
                printf 'target_branch=%s\n' "$a"
                printf 'pending_branch=%s\n' "$b"
                printf 'base_revision=%s\n' "$c"
                printf 'pushed_commit=%s\n' "$d"
                ;;
            tracked)
                printf 'target_branch=%s\n' "$a"
                if [ -n "$b" ]; then
                    printf 'revision=%s\n' "$b"
                fi
                ;;
        esac
    } >>"$MANIFEST_FILE"
}

# Remove one key from a module section, used for cleanup hints after deletion.
manifest_remove_module_key() {
    path=$1
    key=$2
    section=$(module_section "$path")
    tmp=$(tmp_for "$MANIFEST_FILE")
    awk -v section="$section" -v key="$key" '
        $0 == "[" section "]" { in_section=1; print; next }
        /^\[/ { in_section=0 }
        in_section && index($0, key "=") == 1 { next }
        { print }
    ' "$MANIFEST_FILE" >"$tmp"
    mv "$tmp" "$MANIFEST_FILE"
}

# Build the manifest section name for a module path.
module_section() {
    printf 'module "%s"\n' "$1"
}

# Read the configured module repository URL.
module_repo() {
    manifest_get "$(module_section "$1")" repo
}

# Read an arbitrary key from a module section.
module_key() {
    manifest_get "$(module_section "$1")" "$2"
}

# Validate a module clone mode. Empty means "use the default full clone".
validate_clone_mode() {
    value=$1
    context=$2
    case "$value" in
        ""|full|partial) ;;
        *) die "$context must be full or partial, got '$value'" ;;
    esac
}

# Resolve the repository-wide clone override from .stack-rc.
configured_clone_mode() {
    mode=$(config_get clone mode || true)
    [ -n "$mode" ] || mode=manifest
    case "$mode" in
        manifest|full|partial) printf '%s\n' "$mode" ;;
        *) die "$CONFIG_FILE [clone] mode must be manifest, full, or partial, got '$mode'" ;;
    esac
}

# Read and validate a module's manifest clone preference.
module_clone_mode() {
    path=$1
    mode=$(module_key "$path" clone || true)
    validate_clone_mode "$mode" "module $path clone mode"
    [ -n "$mode" ] || mode=full
    printf '%s\n' "$mode"
}

# Apply the global override to the module clone preference.
effective_clone_mode() {
    path=$1
    configured=$(configured_clone_mode)
    case "$configured" in
        manifest) module_clone_mode "$path" ;;
        full|partial) printf '%s\n' "$configured" ;;
    esac
}

# Return the current branch name, or HEAD when detached.
current_branch() {
    git symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'HEAD\n'
}

# Infer the target branch from origin refs, defaulting to main.
default_target_branch() {
    path=${1:-.}
    if git -C "$path" show-ref --verify --quiet refs/remotes/origin/main; then
        printf 'main\n'
    elif git -C "$path" show-ref --verify --quiet refs/remotes/origin/master; then
        printf 'master\n'
    else
        printf 'main\n'
    fi
}

# Extract the ticket key from branch names such as XX-123-description.
ticket_from_branch() {
    printf '%s\n' "$1" | sed -n 's/^\([A-Z][A-Z0-9]*-[0-9][0-9]*\).*/\1/p'
}

# Report whether a repository has any working tree or index changes.
repo_dirty() {
    repo_has_dirty "$1"
}

# Check whether a repository has an origin remote configured.
remote_exists() {
    git -C "$1" remote get-url origin >/dev/null 2>&1
}

# Fetch refs and tags opportunistically; callers can still use local refs.
fetch_quiet() {
    git -C "$1" fetch --tags --prune origin >/dev/null 2>&1 || warn "fetch failed in $1; using local refs"
}

# Clone a module using the selected storage mode. Partial clone remains strict:
# if Git cannot create the requested partial checkout, callers get a hard error.
clone_module() {
    repo=$1
    path=$2
    mode=$3
    no_checkout=${4:-0}
    case "$mode" in
        full)
            git clone "$repo" "$path" ||
                die "failed to clone module $repo into $path; verify the repository URL and network access"
            ;;
        partial)
            if [ "$no_checkout" -eq 1 ]; then
                git clone --filter=blob:none --no-checkout "$repo" "$path" ||
                    die "failed to partial-clone module $repo into $path; verify the repository supports partial clone"
            else
                git clone --filter=blob:none "$repo" "$path" ||
                    die "failed to partial-clone module $repo into $path; verify the repository supports partial clone"
            fi
            repo_is_partial_clone "$path" ||
                die "Git did not configure $path as a partial clone; enable partial clone on the remote or use clone=full"
            ;;
        *) die "unknown effective clone mode for $path: $mode" ;;
    esac
}

# A partial clone is identified by the promisor remote and blob filter Git writes
# during clone --filter=blob:none.
repo_is_partial_clone() {
    check_path=$1
    promisor=$(git -C "$check_path" config --get remote.origin.promisor 2>/dev/null || true)
    filter=$(git -C "$check_path" config --get remote.origin.partialclonefilter 2>/dev/null || true)
    [ "$promisor" = "true" ] && [ "$filter" = "blob:none" ]
}

# Check out a tracked target branch after --no-checkout partial sync.
checkout_target_branch() {
    path=$1
    target=$2
    require_value "$target" "cannot sync tracked module $path without a target branch"
    if git -C "$path" show-ref --verify --quiet "refs/heads/$target"; then
        git -C "$path" checkout "$target" || die "failed to check out target branch $target in $path"
    elif git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1; then
        git -C "$path" checkout -b "$target" "origin/$target" ||
            die "failed to create target branch $target from origin/$target in $path"
    else
        die "target branch $target not found for $path; fetch the module or fix target_branch"
    fi
}

# Read porcelain status with a tool-level error if Git cannot inspect the repo.
repo_status_porcelain() {
    repo=$1
    context=$2
    status=$(git -C "$repo" status --porcelain 2>/dev/null) ||
        die "$context: cannot read Git status in $repo; verify the checkout is not corrupted"
    printf '%s\n' "$status"
}

# Detect untracked files for start --discard-dirty validation.
repo_has_untracked() {
    repo_status_porcelain "$1" "cannot inspect untracked files" | grep '^?? ' >/dev/null 2>&1
}

# Detect any dirty state for preflight and status reporting.
repo_has_dirty() {
    [ -n "$(repo_status_porcelain "$1" "cannot inspect dirty state")" ]
}

# List the outer repository and all checked-out modules for workspace-wide scans.
list_repos() {
    printf '.\n'
    manifest_modules | while IFS= read -r path; do
        [ -d "$path/.git" ] && printf '%s\n' "$path"
    done
}

# Return a stable absolute path for recursion and duplicate detection.
abs_path_for() {
    path=$1
    (CDPATH= cd -- "$path" && pwd)
}

# Join stack-relative labels without turning the root label "." into a prefix.
join_stack_label() {
    base=$1
    child=$2
    if [ "$base" = "." ] || [ -z "$base" ]; then
        printf '%s\n' "$child"
    else
        printf '%s/%s\n' "$base" "$child"
    fi
}

# Report checked-out modules that are themselves stack roots.
notice_nested_stacks() {
    ensure_manifest
    manifest_modules | while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            notice "nested stack found at $path; rerun with --recursive to include it"
        fi
    done
}

# Parse the common optional --recursive flag for read-only/restore commands.
parse_recursive_only() {
    [ $# -le 1 ] || die "$1 takes only optional --recursive"
    if [ $# -eq 1 ]; then
        [ "$1" = "--recursive" ] || die "unknown option: $1"
        printf '1\n'
    else
        printf '0\n'
    fi
}

# Parse read-only commands that support both recursive and porcelain output.
parse_recursive_porcelain() {
    command=$1
    shift
    PARSED_RECURSIVE=0
    PARSED_PORCELAIN=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --recursive) PARSED_RECURSIVE=1 ;;
            --porcelain) PARSED_PORCELAIN=1 ;;
            *) die "unknown $command option: $1" ;;
        esac
        shift
    done
}

# Write dirty repository paths to a file so start can preflight before switching.
dirty_repos_file() {
    out=$1
    : >"$out"
    list_repos | while IFS= read -r path; do
        if repo_has_dirty "$path"; then
            printf '%s\n' "$path" >>"$out"
        fi
    done
}

# Stash all dirty repositories discovered by start preflight.
stash_dirty_repos() {
    dirty_file=$1
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        git -C "$path" stash push -u -m "git-stack start preflight" >/dev/null
    done <"$dirty_file"
}

# Discard tracked edits in dirty repositories, then reject remaining untracked files.
discard_tracked_dirty_repos() {
    dirty_file=$1
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        git -C "$path" reset --hard >/dev/null
    done <"$dirty_file"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if repo_has_untracked "$path"; then
            die "repo $path still has untracked files after --discard-dirty; stash or remove them before start"
        fi
    done <"$dirty_file"
}

# Resolve the start dirty-work policy, including interactive prompting.
resolve_start_dirty() {
    action=$1
    dirty_file=$2
    if [ ! -s "$dirty_file" ]; then
        return
    fi

    printf 'Warning: dirty or untracked repositories:\n' >&2
    while IFS= read -r path; do
        printf '  %s\n' "$path" >&2
    done <"$dirty_file"

    case "$action" in
        stash)
            stash_dirty_repos "$dirty_file"
            ;;
        discard)
            discard_tracked_dirty_repos "$dirty_file"
            ;;
        cancel)
            die "start canceled because repositories have uncommitted changes"
            ;;
        ask)
            [ -t 0 ] || die "start needs clean repositories or --stash-dirty/--discard-dirty/--cancel-dirty"
            printf 'Action: [s] stash all, [d] discard tracked edits, [c] cancel (default): ' >/dev/tty
            IFS= read -r answer </dev/tty || answer=
            case "$answer" in
                s|S) stash_dirty_repos "$dirty_file" ;;
                d|D) discard_tracked_dirty_repos "$dirty_file" ;;
                c|C|"") die "start canceled" ;;
                *) die "unknown start action: $answer" ;;
            esac
            ;;
        *) die "unknown dirty action: $action" ;;
    esac
}

# Initialize an outer workspace and create default manifest/config files.
cmd_init() {
    create_rc=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --rc)
                create_rc=1
                shift
                ;;
            *) die "unknown init option: $1" ;;
        esac
    done
    ensure_outer_repo
    ensure_manifest
    [ -f .gitignore ] || : >.gitignore
    [ "$create_rc" -eq 0 ] || ensure_config
    printf 'Initialized git-stack workspace.\n'
}

# Add a module checkout and record its repo, target branch, and current revision.
cmd_add() {
    clone_mode=
    while [ $# -gt 0 ]; do
        case "$1" in
            --clone)
                [ $# -ge 2 ] || die "--clone requires full or partial"
                clone_mode=$2
                validate_clone_mode "$clone_mode" "add --clone"
                [ -n "$clone_mode" ] || die "--clone requires full or partial"
                shift 2
                ;;
            --*) die "unknown add option: $1" ;;
            *) break ;;
        esac
    done
    [ $# -eq 2 ] || die "usage: git-stack add [--clone <full|partial>] <repo> <path>"
    repo=$1
    path=$(normalize_path "$2")
    ensure_outer_repo
    ensure_manifest

    if [ ! -d "$path/.git" ]; then
        [ ! -e "$path" ] || die "$path exists but is not a Git repository"
        mode=$clone_mode
        if [ -z "$mode" ] && [ "$(configured_clone_mode)" = partial ]; then
            mode=partial
        fi
        [ -n "$mode" ] || mode=full
        clone_module "$repo" "$path" "$mode" 0
    fi

    grep -Fx "$path/" .gitignore >/dev/null 2>&1 || printf '%s/\n' "$path" >>.gitignore

    fetch_quiet "$path"
    target=$(default_target_branch "$path")
    revision=$(resolve_head_commit "$path" "cannot add module $path")
    manifest_write_module "$path" "$repo" tracked "$target" "$revision" "$clone_mode"
    install_hooks_in_repo_if_stack_managed "$path"
    printf 'Added module %s.\n' "$path"
}

# Print a compact view of the current stack and module state for humans.
status_current() {
    ensure_manifest
    branch=$(current_branch)
    stack_id=$(manifest_get stack id || true)
    stack_branch=$(manifest_get stack branch || true)

    printf 'outer branch: %s\n' "$branch"
    [ -n "$stack_id" ] && printf 'stack id: %s\n' "$stack_id"
    [ -n "$stack_branch" ] && printf 'stack branch: %s\n' "$stack_branch"
    printf 'modules:\n'

    manifest_modules | while IFS= read -r path; do
        pending=$(module_key "$path" pending_branch || true)
        revision=$(module_key "$path" revision || true)
        if [ ! -d "$path/.git" ]; then
            printf '  %s: missing\n' "$path"
        elif [ -n "$pending" ]; then
            dirty=
            repo_dirty "$path" && dirty=' dirty'
            printf '  %s: pending %s%s\n' "$path" "$pending" "$dirty"
        elif [ -n "$revision" ]; then
            dirty=
            repo_dirty "$path" && dirty=' dirty'
            printf '  %s: finalized %.12s%s\n' "$path" "$revision" "$dirty"
        else
            printf '  %s: tracked\n' "$path"
        fi
    done
}

# Print dirty or incomplete state in a stable, Git-like script format.
status_porcelain_current() {
    label=$1

    repo_status_porcelain . "cannot inspect dirty state" | while IFS= read -r line; do
        [ -n "$line" ] || continue
        printf '%s\t%s\n' "$label" "$line"
    done

    manifest_modules | while IFS= read -r path; do
        [ -n "$path" ] || continue
        module_label=$(join_stack_label "$label" "$path")
        if [ ! -d "$path/.git" ]; then
            printf '%s\t!! missing\n' "$module_label"
            continue
        fi
        repo_status_porcelain "$path" "cannot inspect dirty state" | while IFS= read -r line; do
            [ -n "$line" ] || continue
            printf '%s\t%s\n' "$module_label" "$line"
        done
    done
}

# Recursively print status for the current stack and nested stack roots.
status_recursive() {
    label=$1
    visited=$2
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    printf 'stack: %s\n' "$label"
    status_current

    manifest_modules | while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_stack_label "$label" "$path")
            (
                cd "$path" || exit 1
                printf '\n'
                status_recursive "$child_label" "$visited"
            )
        fi
    done
}

# Recursively print porcelain status for the current stack and nested stack roots.
status_porcelain_recursive() {
    label=$1
    visited=$2
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    status_porcelain_current "$label"

    manifest_modules | while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_stack_label "$label" "$path")
            (
                cd "$path" || exit 1
                status_porcelain_recursive "$child_label" "$visited"
            )
        fi
    done
}

# Print stack state, optionally including nested stacks.
cmd_status() {
    parse_recursive_porcelain status "$@"
    recursive=$PARSED_RECURSIVE
    porcelain=$PARSED_PORCELAIN
    if [ "$porcelain" -eq 1 ]; then
        if [ "$recursive" -eq 1 ]; then
            visited=$(mktemp)
            : >"$visited"
            status_porcelain_recursive "." "$visited"
            rm -f "$visited"
        else
            status_porcelain_current "."
        fi
    elif [ "$recursive" -eq 1 ]; then
        visited=$(mktemp)
        : >"$visited"
        status_recursive "." "$visited"
        rm -f "$visited"
    else
        status_current
        notice_nested_stacks
    fi
}

# Pick the branch used for remote availability checks. Existing finalized
# entries may not record target_branch, so follow the normal target inference.
available_target_branch() {
    path=$1
    target=$(module_key "$path" target_branch || true)
    if [ -n "$target" ]; then
        printf '%s\n' "$target"
    elif [ -d "$path/.git" ]; then
        default_target_branch "$path"
    else
        printf 'main\n'
    fi
}

# Query a module remote without updating local refs.
remote_branch_commit() {
    repo=$1
    target=$2
    out=$3
    git ls-remote "$repo" "refs/heads/$target" >"$out" 2>/dev/null || return 1
    awk 'NR == 1 { print $1 }' "$out"
}

# Report whether module remotes have target-branch commits newer than .stack.
available_current() {
    ensure_manifest
    errors=$(tmp_for "$MANIFEST_FILE.available_errors")
    : >"$errors"

    printf 'modules:\n'
    manifest_modules | while IFS= read -r path; do
        [ -n "$path" ] || continue
        repo=$(module_repo "$path" || true)
        if [ -z "$repo" ]; then
            printf '  %s: error missing repo\n' "$path"
            printf 'Error: %s: missing repo in %s\n' "$path" "$MANIFEST_FILE" >>"$errors"
            continue
        fi

        pending=$(module_key "$path" pending_branch || true)
        if [ -n "$pending" ]; then
            printf '  %s: pending %s\n' "$path" "$pending"
            continue
        fi

        target=$(available_target_branch "$path")
        remote_tmp=$(tmp_for "$MANIFEST_FILE.available_remote")
        remote_commit=$(remote_branch_commit "$repo" "$target" "$remote_tmp" || true)
        rm -f "$remote_tmp"
        if [ -z "$remote_commit" ]; then
            if git ls-remote "$repo" >/dev/null 2>&1; then
                printf '  %s: remote branch missing %s\n' "$path" "$target"
                printf 'Error: %s: remote branch %s is not available\n' "$path" "$target" >>"$errors"
            else
                printf '  %s: remote unavailable %s\n' "$path" "$target"
                printf 'Error: %s: cannot query remote %s\n' "$path" "$repo" >>"$errors"
            fi
            continue
        fi

        revision=$(module_key "$path" revision || true)
        tag=$(module_key "$path" tag || true)
        remote_short=$(printf '%s\n' "$remote_commit" | cut -c1-12)

        if [ ! -d "$path/.git" ]; then
            printf '  %s: missing checkout; remote %s %s\n' "$path" "$target" "$remote_short"
        elif [ -n "$revision" ]; then
            revision_short=$(printf '%s\n' "$revision" | cut -c1-12)
            if [ "$remote_commit" = "$revision" ]; then
                if [ -n "$tag" ]; then
                    printf '  %s: tag-pinned %s; up to date %s %s\n' "$path" "$tag" "$target" "$remote_short"
                else
                    printf '  %s: up to date %s %s\n' "$path" "$target" "$remote_short"
                fi
            else
                if [ -n "$tag" ]; then
                    printf '  %s: tag-pinned %s; available %s %s -> %s\n' "$path" "$tag" "$target" "$revision_short" "$remote_short"
                else
                    printf '  %s: available %s %s -> %s\n' "$path" "$target" "$revision_short" "$remote_short"
                fi
            fi
        else
            head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
            head_short=$(printf '%s\n' "$head" | cut -c1-12)
            if [ -n "$head" ] && [ "$remote_commit" = "$head" ]; then
                printf '  %s: up to date %s %s\n' "$path" "$target" "$remote_short"
            elif [ -n "$head" ]; then
                printf '  %s: available %s %s -> %s\n' "$path" "$target" "$head_short" "$remote_short"
            else
                printf '  %s: remote %s %s\n' "$path" "$target" "$remote_short"
            fi
        fi
    done

    if [ -s "$errors" ]; then
        cat "$errors" >&2
        rm -f "$errors"
        return 1
    fi
    rm -f "$errors"
}

# Report remote availability in stable records for scripts.
available_porcelain_current() {
    label=$1
    ensure_manifest
    errors=$(tmp_for "$MANIFEST_FILE.available_errors")
    : >"$errors"

    manifest_modules | while IFS= read -r path; do
        [ -n "$path" ] || continue
        module_label=$(join_stack_label "$label" "$path")
        repo=$(module_repo "$path" || true)
        if [ -z "$repo" ]; then
            printf '%s\terror\tmissing-repo\n' "$module_label"
            printf 'Error: %s: missing repo in %s\n' "$module_label" "$MANIFEST_FILE" >>"$errors"
            continue
        fi

        pending=$(module_key "$path" pending_branch || true)
        [ -z "$pending" ] || continue

        target=$(available_target_branch "$path")
        remote_tmp=$(tmp_for "$MANIFEST_FILE.available_remote")
        remote_commit=$(remote_branch_commit "$repo" "$target" "$remote_tmp" || true)
        rm -f "$remote_tmp"
        if [ -z "$remote_commit" ]; then
            if git ls-remote "$repo" >/dev/null 2>&1; then
                printf '%s\terror\tremote-branch-missing\t%s\n' "$module_label" "$target"
                printf 'Error: %s: remote branch %s is not available\n' "$module_label" "$target" >>"$errors"
            else
                printf '%s\terror\tremote-unavailable\t%s\n' "$module_label" "$target"
                printf 'Error: %s: cannot query remote %s\n' "$module_label" "$repo" >>"$errors"
            fi
            continue
        fi

        revision=$(module_key "$path" revision || true)
        if [ ! -d "$path/.git" ]; then
            printf '%s\tmissing\t%s\t%s\n' "$module_label" "$target" "$remote_commit"
        elif [ -n "$revision" ]; then
            if [ "$remote_commit" != "$revision" ]; then
                printf '%s\tavailable\t%s\t%s\t%s\n' "$module_label" "$target" "$revision" "$remote_commit"
            fi
        else
            head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
            if [ -n "$head" ] && [ "$remote_commit" != "$head" ]; then
                printf '%s\tavailable\t%s\t%s\t%s\n' "$module_label" "$target" "$head" "$remote_commit"
            elif [ -z "$head" ]; then
                printf '%s\tremote\t%s\t%s\n' "$module_label" "$target" "$remote_commit"
            fi
        fi
    done

    if [ -s "$errors" ]; then
        cat "$errors" >&2
        rm -f "$errors"
        return 1
    fi
    rm -f "$errors"
}

# Recursively check availability for the current stack and nested stack roots.
available_recursive() {
    label=$1
    visited=$2
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    printf 'stack: %s\n' "$label"
    rc=0
    available_current || rc=1

    modules_tmp=$(tmp_for "$MANIFEST_FILE.available_recursive")
    manifest_modules >"$modules_tmp"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_stack_label "$label" "$path")
            (
                cd "$path" || exit 1
                printf '\n'
                available_recursive "$child_label" "$visited"
            ) || rc=1
        fi
    done <"$modules_tmp"
    rm -f "$modules_tmp"
    return "$rc"
}

# Recursively check availability in stable records for scripts.
available_porcelain_recursive() {
    label=$1
    visited=$2
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    rc=0
    available_porcelain_current "$label" || rc=1

    modules_tmp=$(tmp_for "$MANIFEST_FILE.available_recursive")
    manifest_modules >"$modules_tmp"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_stack_label "$label" "$path")
            (
                cd "$path" || exit 1
                available_porcelain_recursive "$child_label" "$visited"
            ) || rc=1
        fi
    done <"$modules_tmp"
    rm -f "$modules_tmp"
    return "$rc"
}

# Check module remotes for newer target-branch commits without changing state.
cmd_available() {
    parse_recursive_porcelain available "$@"
    recursive=$PARSED_RECURSIVE
    porcelain=$PARSED_PORCELAIN
    if [ "$porcelain" -eq 1 ]; then
        if [ "$recursive" -eq 1 ]; then
            visited=$(mktemp)
            : >"$visited"
            available_porcelain_recursive "." "$visited"
            rc=$?
            rm -f "$visited"
            return "$rc"
        fi
        available_porcelain_current "."
        return "$?"
    elif [ "$recursive" -eq 1 ]; then
        visited=$(mktemp)
        : >"$visited"
        available_recursive "." "$visited"
        rc=$?
        rm -f "$visited"
        return "$rc"
    fi
    available_current
    notice_nested_stacks
}

# Validate that the current checkout still matches the manifest and config.
verify_current() {
    ensure_manifest
    configured_clone_mode >/dev/null
    errors=$(tmp_for "$MANIFEST_FILE.verify_errors")
    warnings=$(tmp_for "$MANIFEST_FILE.verify_warnings")
    : >"$errors"
    : >"$warnings"

    duplicates=$(manifest_modules | sort | uniq -d)
    if [ -n "$duplicates" ]; then
        printf '%s\n' "$duplicates" | while IFS= read -r path; do
            [ -n "$path" ] && printf 'Error: %s: duplicate module path in %s\n' "$path" "$MANIFEST_FILE" >>"$errors"
        done
    fi

    manifest_modules | while IFS= read -r path; do
        [ -n "$path" ] || continue
        repo=$(module_repo "$path" || true)
        if [ -z "$repo" ]; then
            printf 'Error: %s: missing repo in %s\n' "$path" "$MANIFEST_FILE" >>"$errors"
            continue
        fi
        mode=$(effective_clone_mode "$path")
        if [ ! -d "$path/.git" ]; then
            printf 'Error: %s: module checkout is missing; run git-stack sync\n' "$path" >>"$errors"
            continue
        fi

        actual_repo=$(git -C "$path" remote get-url origin 2>/dev/null || true)
        if [ "$actual_repo" != "$repo" ]; then
            printf 'Error: %s: origin remote differs from manifest\n' "$path" >>"$errors"
            printf '  expected: %s\n  actual:   %s\n' "$repo" "$actual_repo" >>"$errors"
        fi

        if [ "$mode" = partial ]; then
            repo_is_partial_clone "$path" ||
                printf 'Error: %s: manifest/config requests clone=partial, but existing checkout is full; remove the module and run git-stack sync or use clone=full\n' "$path" >>"$errors"
        else
            if repo_is_partial_clone "$path"; then
                printf 'Error: %s: manifest/config requests clone=full, but existing checkout is partial; remove the module and run git-stack sync or use clone=partial\n' "$path" >>"$errors"
            fi
        fi

        pending=$(module_key "$path" pending_branch || true)
        tag=$(module_key "$path" tag || true)
        revision=$(module_key "$path" revision || true)
        target=$(module_key "$path" target_branch || true)
        [ -n "$target" ] || target=$(default_target_branch "$path")

        if [ -n "$pending" ]; then
            git -C "$path" rev-parse --verify "$pending^{commit}" >/dev/null 2>&1 ||
            git -C "$path" rev-parse --verify "origin/$pending^{commit}" >/dev/null 2>&1 ||
                printf 'Error: %s: pending branch %s is not resolvable\n' "$path" "$pending" >>"$errors"
        elif [ -n "$tag" ]; then
            expected=$(git -C "$path" rev-parse --verify "$tag^{commit}" 2>/dev/null || true)
            if [ -z "$expected" ]; then
                printf 'Error: %s: tag %s is not resolvable\n' "$path" "$tag" >>"$errors"
            else
                head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
                [ "$head" = "$expected" ] ||
                    printf 'Error: %s: checked-out commit does not match tag %s\n' "$path" "$tag" >>"$errors"
            fi
        elif [ -n "$revision" ]; then
            expected=$(git -C "$path" rev-parse --verify "$revision^{commit}" 2>/dev/null || true)
            if [ -z "$expected" ]; then
                printf 'Error: %s: revision %s is not resolvable\n' "$path" "$revision" >>"$errors"
            else
                head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
                [ "$head" = "$expected" ] ||
                    printf 'Error: %s: checked-out commit does not match revision %.12s\n' "$path" "$revision" >>"$errors"
            fi
        else
            git -C "$path" rev-parse --verify "$target^{commit}" >/dev/null 2>&1 ||
            git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1 ||
                printf 'Error: %s: target branch %s is not resolvable\n' "$path" "$target" >>"$errors"
        fi

        if repo_dirty "$path"; then
            printf 'Warning: %s: module has uncommitted changes\n' "$path" >>"$warnings"
        fi
    done

    if [ -s "$warnings" ]; then
        cat "$warnings" >&2
    fi
    if [ -s "$errors" ]; then
        cat "$errors" >&2
        rm -f "$errors" "$warnings"
        return 1
    fi
    rm -f "$errors" "$warnings"
    printf 'Stack verified.\n'
}

# Recursively verify the current stack and nested stack roots.
verify_recursive() {
    label=$1
    visited=$2
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    printf 'Verifying stack: %s\n' "$label"
    rc=0
    verify_current || rc=1

    modules_tmp=$(tmp_for "$MANIFEST_FILE.verify_recursive")
    manifest_modules >"$modules_tmp"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_stack_label "$label" "$path")
            (
                cd "$path" || exit 1
                verify_recursive "$child_label" "$visited"
            ) || rc=1
        fi
    done <"$modules_tmp"
    rm -f "$modules_tmp"
    return "$rc"
}

# Validate stack state, optionally including nested stacks.
cmd_verify() {
    recursive=$(parse_recursive_only "$@")
    if [ "$recursive" -eq 1 ]; then
        visited=$(mktemp)
        : >"$visited"
        verify_recursive "." "$visited"
        rc=$?
        rm -f "$visited"
        return "$rc"
    fi
    verify_current
    notice_nested_stacks
}

# Validate positive integer options such as log --max-count.
is_positive_integer() {
    case "$1" in
        ""|*[!0-9]*) return 1 ;;
        0) return 1 ;;
        *) return 0 ;;
    esac
}

# Append one repository's recent commits to the combined stack log input.
append_log_for_repo() {
    log_repo=$1
    log_label=$2
    log_out=$3
    log_max_count=$4
    log_since=$5
    log_until=$6
    log_filter=$7
    log_visited_repos=$8

    if [ -n "$log_filter" ] && [ "$log_filter" != "$log_label" ]; then
        return 0
    fi
    if [ ! -d "$log_repo/.git" ]; then
        warn "missing repository for log: $log_label"
        return 0
    fi
    log_repo_abs=$(abs_path_for "$log_repo")
    if grep -F -x "$log_repo_abs" "$log_visited_repos" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$log_repo_abs" >>"$log_visited_repos"
    git -C "$log_repo" rev-parse --verify HEAD >/dev/null 2>&1 || return 0

    if [ -n "$log_since" ] && [ -n "$log_until" ]; then
        git -C "$log_repo" log --max-count="$log_max_count" --since="$log_since" --until="$log_until" --format='%ct|%cI|%h|%s'
    elif [ -n "$log_since" ]; then
        git -C "$log_repo" log --max-count="$log_max_count" --since="$log_since" --format='%ct|%cI|%h|%s'
    elif [ -n "$log_until" ]; then
        git -C "$log_repo" log --max-count="$log_max_count" --until="$log_until" --format='%ct|%cI|%h|%s'
    else
        git -C "$log_repo" log --max-count="$log_max_count" --format='%ct|%cI|%h|%s'
    fi | while IFS='|' read -r epoch iso sha subject; do
        [ -n "$epoch" ] || continue
        printf '%s|%s|%s|%s|%s\n' "$epoch" "$iso" "$log_label" "$sha" "$subject" >>"$log_out"
    done
}

# Collect commits from the current stack, recursing into nested stacks on demand.
collect_log_for_stack() {
    label=$1
    out=$2
    max_count=$3
    since=$4
    until=$5
    recursive=$6
    filter=$7
    visited_stacks=$8
    visited_repos=$9

    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited_stacks" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited_stacks"
    root_label=${label:-.}
    append_log_for_repo . "$root_label" "$out" "$max_count" "$since" "$until" "$filter" "$visited_repos"

    modules_tmp=$(tmp_for "$MANIFEST_FILE.log_modules")
    manifest_modules >"$modules_tmp"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        child_label=$(join_stack_label "$label" "$path")
        if [ -d "$path/.git" ]; then
            append_log_for_repo "$path" "$child_label" "$out" "$max_count" "$since" "$until" "$filter" "$visited_repos"
            if [ "$recursive" -eq 1 ] && [ -f "$path/$MANIFEST_FILE" ]; then
                (
                    cd "$path" || exit 1
                    collect_log_for_stack "$child_label" "$out" "$max_count" "$since" "$until" "$recursive" "$filter" "$visited_stacks" "$visited_repos"
                )
            fi
        elif [ -z "$filter" ] || [ "$filter" = "$child_label" ]; then
            warn "missing repository for log: $child_label"
        fi
    done <"$modules_tmp"
    rm -f "$modules_tmp"
}

# Show a combined, read-only history view across the active stack.
cmd_log() {
    max_count=50
    since=
    until=
    module_filter=
    oneline=0
    recursive=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --max-count)
                [ $# -ge 2 ] || die "--max-count requires a value"
                is_positive_integer "$2" || die "--max-count must be a positive integer"
                max_count=$2
                shift 2
                ;;
            --since)
                [ $# -ge 2 ] || die "--since requires a value"
                since=$2
                shift 2
                ;;
            --until)
                [ $# -ge 2 ] || die "--until requires a value"
                until=$2
                shift 2
                ;;
            --module)
                [ $# -ge 2 ] || die "--module requires a value"
                if [ "$2" = "." ]; then
                    module_filter=.
                else
                    module_filter=$(normalize_path "$2")
                    [ -n "$(module_repo "$module_filter" || true)" ] ||
                        die "--module must be . or a module path in $MANIFEST_FILE"
                fi
                shift 2
                ;;
            --oneline)
                oneline=1
                shift
                ;;
            --recursive)
                recursive=1
                shift
                ;;
            *) die "unknown log option: $1" ;;
        esac
    done

    ensure_manifest
    log_tmp=$(mktemp)
    sorted_tmp=$(mktemp)
    visited_stacks=$(mktemp)
    visited_repos=$(mktemp)
    : >"$log_tmp"
    : >"$visited_stacks"
    : >"$visited_repos"

    collect_log_for_stack "" "$log_tmp" "$max_count" "$since" "$until" "$recursive" "$module_filter" "$visited_stacks" "$visited_repos"
    sort -t '|' -k1,1nr "$log_tmp" | sed -n "1,${max_count}p" >"$sorted_tmp"

    if [ "$oneline" -eq 1 ]; then
        awk -F '|' '{ printf "%-24s %s %s\n", $3, $4, $5 }' "$sorted_tmp"
    else
        awk -F '|' '{ printf "%s  %-24s  %s  %s\n", $2, $3, $4, $5 }' "$sorted_tmp"
    fi

    rm -f "$log_tmp" "$sorted_tmp" "$visited_stacks" "$visited_repos"
    if [ "$recursive" -eq 0 ]; then
        notice_nested_stacks
    fi
}

# Start a coordinated branch, or record current state when branch is ".".
cmd_start() {
    install_hooks=0
    dirty_action=ask
    sure=0
    branch=

    # Parse options in any position so users can put --hooks after the branch.
    while [ $# -gt 0 ]; do
        case "$1" in
            --hooks) install_hooks=1; shift ;;
            --sure) sure=1; shift ;;
            --stash-dirty) dirty_action=stash; shift ;;
            --discard-dirty) dirty_action=discard; shift ;;
            --cancel-dirty) dirty_action=cancel; shift ;;
            --*) die "unknown start option: $1" ;;
            *)
                [ -z "$branch" ] || die "usage: git-stack start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]"
                branch=$1
                shift
                ;;
        esac
    done
    [ -n "$branch" ] || die "usage: git-stack start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]"
    [ -d .git ] && startup_new=0 || startup_new=1
    confirm_startup_directory "$sure"
    ensure_outer_repo
    ensure_manifest

    if [ "$branch" = "." ]; then
        quiet_arg=
        if [ -n "${GIT_STACK_REFRESH_QUIET:-}" ] || [ -n "${GIT_STACK_RECORD_QUIET:-}" ]; then
            quiet_arg=--quiet
        fi
        cmd_refresh ${quiet_arg:+--quiet}
        [ "$install_hooks" -eq 0 ] || install_hooks_all
        return
    fi

    # Dirty repositories are handled before any checkout so the workspace is not
    # left half-switched if the user cancels or untracked files block discard.
    ticket=$(ticket_from_branch "$branch")
    if [ "$startup_new" -eq 0 ]; then
        dirty_tmp=$(mktemp)
        dirty_repos_file "$dirty_tmp"
        resolve_start_dirty "$dirty_action" "$dirty_tmp"
        rm -f "$dirty_tmp"
    fi

    # Switch the outer repository first, then checked-out modules. Missing
    # modules stay in the manifest and can later be restored by sync.
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        git checkout "$branch" || die "failed to check out outer branch $branch"
    else
        git checkout -b "$branch" || die "failed to create outer branch $branch"
    fi

    manifest_modules | while IFS= read -r path; do
        [ -d "$path/.git" ] || continue
        if git -C "$path" show-ref --verify --quiet "refs/heads/$branch"; then
            git -C "$path" checkout "$branch" || die "failed to check out branch $branch in module $path"
        else
            git -C "$path" checkout -b "$branch" || die "failed to create branch $branch in module $path"
        fi
    done

    # Only stack metadata is written here. Module pending state is created later
    # by refresh/upload once a module actually has committed work.
    manifest_write_stack "$ticket" "$branch"
    [ "$install_hooks" -eq 0 ] || install_hooks_all
    printf 'Started stack branch %s.\n' "$branch"
}

# Record pending metadata for one clean module that has committed local work.
record_module_if_needed() {
    path=$1
    quiet=$2
    [ -d "$path/.git" ] || return 0
    if repo_has_dirty "$path"; then
        [ "$quiet" -eq 1 ] || warn "skipping dirty module $path during refresh"
        return 0
    fi
    repo=$(module_repo "$path")
    require_value "$repo" "module $path is missing repo in $MANIFEST_FILE; run git-stack add again or fix the manifest"
    target=$(module_key "$path" target_branch || true)
    [ -n "$target" ] || target=$(default_target_branch "$path")
    mod_branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    [ -n "$mod_branch" ] || return 0
    work_count=$(module_work_count "$path" "$target")
    if [ "$work_count" -gt 0 ]; then
        base=$(base_for_module "$path" "$target")
        pushed=$(resolve_head_commit "$path" "cannot refresh module $path")
        manifest_write_module "$path" "$repo" pending "$target" "$mod_branch" "$base" "$pushed"
        [ "$quiet" -eq 1 ] || printf 'Recorded module %s branch %s at %.12s.\n' "$path" "$mod_branch" "$pushed"
    fi
}

# Refresh manifest state from local branches without pushing anything.
cmd_refresh() {
    quiet=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --quiet) quiet=1; shift ;;
            *) die "unknown refresh option: $1" ;;
        esac
    done
    ensure_outer_repo
    ensure_manifest
    branch=$(current_branch)
    [ "$branch" != "HEAD" ] || die "refresh requires the outer repository to be on a named branch"
    ticket=$(ticket_from_branch "$branch")
    manifest_write_stack "$ticket" "$branch"
    manifest_modules | while IFS= read -r path; do
        record_module_if_needed "$path" "$quiet"
    done
    [ "$quiet" -eq 1 ] || printf 'Refreshed current git-stack state.\n'
}

# Find the base commit used to compare module work against its target branch.
base_for_module() {
    path=$1
    target=$2
    require_value "$target" "cannot calculate base revision for $path without a target branch"
    fetch_quiet "$path"
    if git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1; then
        base=$(git -C "$path" merge-base HEAD "origin/$target" 2>/dev/null) ||
            die "cannot find a merge base for $path between HEAD and origin/$target; fetch the module or check target_branch"
    elif git -C "$path" rev-parse --verify "$target^{commit}" >/dev/null 2>&1; then
        base=$(git -C "$path" merge-base HEAD "$target" 2>/dev/null) ||
            die "cannot find a merge base for $path between HEAD and $target; fetch the module or check target_branch"
    else
        base=$(git -C "$path" rev-parse --verify "HEAD^" 2>/dev/null ||
            git -C "$path" rev-parse --verify HEAD 2>/dev/null) ||
            die "cannot calculate base revision for $path; repository has no commits"
    fi
    require_value "$base" "calculated an empty base revision for $path; fetch the module or check target_branch"
    printf '%s\n' "$base"
}

# Count commits in a module that are ahead of the resolved base revision.
module_work_count() {
    path=$1
    target=$2
    base=$(base_for_module "$path" "$target")
    count=$(git -C "$path" rev-list --count "$base..HEAD" 2>/dev/null) ||
        die "cannot count commits for $path from $base to HEAD; verify the module history"
    require_value "$count" "commit count for $path from $base to HEAD was empty"
    printf '%s\n' "$count"
}

# Commit outer manifest/config changes when there is a configured Git identity.
commit_manifest_if_needed() {
    branch=$1
    [ -f "$MANIFEST_FILE" ] && git add "$MANIFEST_FILE" 2>/dev/null || true
    [ -f .gitignore ] && git add .gitignore 2>/dev/null || true
    [ -f "$CONFIG_FILE" ] && git add "$CONFIG_FILE" 2>/dev/null || true
    if git diff --cached --quiet; then
        return
    fi
    if git config user.name >/dev/null 2>&1 && git config user.email >/dev/null 2>&1; then
        git commit -m "Update git-stack manifest for $branch" >/dev/null ||
            die "failed to commit manifest update on $branch"
    else
        warn "manifest changed but Git user.name/user.email are not configured; skipping outer commit"
    fi
}

# Push changed module branches, record pending/finalized state, and push the outer branch.
cmd_upload() {
    finalize=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --finalize)
                finalize=1
                shift
                ;;
            *) die "unknown upload option: $1" ;;
        esac
    done
    ensure_manifest
    branch=$(current_branch)
    [ "$branch" != "HEAD" ] || die "upload requires a named branch"

    modules_tmp=$(tmp_for "$MANIFEST_FILE.modules")
    manifest_modules >"$modules_tmp"

    # A dirty module blocks the whole upload so the manifest never records a
    # branch that does not contain all local work.
    while IFS= read -r path; do
        [ -d "$path/.git" ] || continue
        dirty=$(repo_status_porcelain "$path" "cannot inspect module $path before upload")
        [ -z "$dirty" ] || die "module $path has uncommitted changes; commit or stash before upload"
    done <"$modules_tmp"

    # Candidate branches from start are skipped unless they have commits ahead
    # of the target branch. The module's actual branch name is recorded.
    while IFS= read -r path; do
        [ -d "$path/.git" ] || continue
        repo=$(module_repo "$path")
        require_value "$repo" "module $path is missing repo in $MANIFEST_FILE; run git-stack add again or fix the manifest"
        target=$(module_key "$path" target_branch || true)
        [ -n "$target" ] || target=$(default_target_branch "$path")
        mod_branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
        work_count=$(module_work_count "$path" "$target")
        if [ "$work_count" -gt 0 ]; then
            [ -n "$mod_branch" ] || die "module $path has committed work on detached HEAD; check out a branch before upload"
            base=$(base_for_module "$path" "$target")
            pushed=$(resolve_head_commit "$path" "cannot upload module $path")
            remote_exists "$path" || die "module $path has no origin remote"
            git -C "$path" push -u origin "HEAD:$mod_branch" ||
                die "failed to push module $path branch $mod_branch to origin"
            if [ "$finalize" -eq 1 ]; then
                manifest_write_module "$path" "$repo" finalized "$pushed" "" "$mod_branch"
                printf 'Uploaded and finalized module %s branch %s at %.12s.\n' "$path" "$mod_branch" "$pushed"
            else
                manifest_write_module "$path" "$repo" pending "$target" "$mod_branch" "$base" "$pushed"
                printf 'Uploaded module %s branch %s at %.12s.\n' "$path" "$mod_branch" "$pushed"
            fi
        fi
    done <"$modules_tmp"
    rm -f "$modules_tmp"

    # The outer push is best-effort when no origin is configured; module pushes
    # remain strict because pending manifest state points at those branches.
    commit_manifest_if_needed "$branch"
    if remote_exists .; then
        git push -u origin "HEAD:$branch" || die "failed to push outer branch $branch to origin"
    else
        warn "outer repository has no origin remote; skipped outer push"
    fi
}

# Shared foreach engine for all modules or only manifest-pending modules.
run_foreach() {
    mode=$1
    shift
    [ $# -gt 0 ] || die "usage: git-stack $mode -- <command> [args...]"
    if [ "$1" = "--" ]; then
        shift
    fi
    [ $# -gt 0 ] || die "usage: git-stack $mode -- <command> [args...]"

    ensure_manifest
    root=$(repo_root)
    root=$(CDPATH= cd -- "$root" && pwd)
    modules_tmp=$(tmp_for "$MANIFEST_FILE.foreach")
    manifest_modules >"$modules_tmp"

    rc=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        pending=$(module_key "$path" pending_branch || true)
        if [ "$mode" = "foreach-modified" ] && [ -z "$pending" ]; then
            continue
        fi
        if [ ! -d "$path/.git" ]; then
            warn "skipping missing module $path"
            continue
        fi

        repo=$(module_repo "$path")
        target=$(module_key "$path" target_branch || true)
        base=$(module_key "$path" base_revision || true)
        pushed=$(module_key "$path" pushed_commit || true)
        revision=$(module_key "$path" revision || true)
        tag=$(module_key "$path" tag || true)
        branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
        module_abs=$(CDPATH= cd -- "$path" && pwd)

        # Run in a subshell so each module gets its own working directory and
        # exported context without leaking changes into the next iteration.
        (
            cd "$path" || exit 1
            GIT_STACK_ROOT=$root \
            GIT_STACK_MODULE_PATH=$path \
            GIT_STACK_MODULE_ABSPATH=$module_abs \
            GIT_STACK_MODULE_REPO=$repo \
            GIT_STACK_BRANCH=$branch \
            GIT_STACK_TARGET_BRANCH=$target \
            GIT_STACK_PENDING_BRANCH=$pending \
            GIT_STACK_BASE_REVISION=$base \
            GIT_STACK_PUSHED_COMMIT=$pushed \
            GIT_STACK_REVISION=$revision \
            GIT_STACK_TAG=$tag \
            REPO_PATH=$path \
            REPO_PROJECT=$path \
            "$@"
        ) || rc=$?

        [ "$rc" -eq 0 ] || break
    done <"$modules_tmp"

    rm -f "$modules_tmp"
    return "$rc"
}

# Public wrapper for running a command in every checked-out module.
cmd_foreach() {
    run_foreach foreach "$@"
}

# Public wrapper for running a command only in pending modules.
cmd_foreach_modified() {
    run_foreach foreach-modified "$@"
}

# Resolve the actual hook path for a repo, handling Git's relative path output.
hook_path_for() {
    hook_path_repo=$1
    hook_path_name=$2
    resolved_hook_path=$(git -C "$hook_path_repo" rev-parse --git-path "hooks/$hook_path_name" 2>/dev/null) ||
        die "cannot resolve hook path for $hook_path_repo; ensure it is a Git repository"
    require_value "$resolved_hook_path" "resolved an empty hook path for $hook_path_repo hook $hook_path_name"
    case "$resolved_hook_path" in
        /*|?:/*) printf '%s\n' "$resolved_hook_path" ;;
        *) printf '%s/%s\n' "$hook_path_repo" "$resolved_hook_path" ;;
    esac
}

# Write a managed hook that calls refresh --quiet from the outer workspace.
write_managed_hook() {
    write_hook_repo=$1
    write_hook_name=$2
    write_hook_outer_root=$3
    write_hook_git_stack_path=$4
    write_hook_file=$(hook_path_for "$write_hook_repo" "$write_hook_name")
    if [ -f "$write_hook_file" ] && ! grep -F '# git-stack managed hook' "$write_hook_file" >/dev/null 2>&1; then
        die "refusing to overwrite unmanaged hook: $write_hook_file"
    fi
    mkdir -p "$(dirname "$write_hook_file")"
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' '# git-stack managed hook'
        printf '%s\n' '[ "${GIT_STACK_HOOK:-}" = "1" ] && exit 0'
        printf 'cd "%s" || exit 0\n' "$write_hook_outer_root"
        printf 'GIT_STACK_HOOK=1 "%s" refresh --quiet >/dev/null 2>&1 || true\n' "$write_hook_git_stack_path"
    } >"$write_hook_file"
    chmod +x "$write_hook_file" 2>/dev/null || true
}

# Report whether the stack root already has the complete managed hook set.
managed_hooks_installed_in_repo() {
    managed_hooks_repo=$1
    git -C "$managed_hooks_repo" rev-parse --git-dir >/dev/null 2>&1 || return 1
    for managed_hooks_name in post-checkout post-commit pre-push; do
        managed_hooks_file=$(hook_path_for "$managed_hooks_repo" "$managed_hooks_name")
        [ -f "$managed_hooks_file" ] || return 1
        grep -F '# git-stack managed hook' "$managed_hooks_file" >/dev/null 2>&1 || return 1
    done
    return 0
}

# Install managed hooks in one repository when the outer stack already uses them.
install_hooks_in_repo_if_stack_managed() {
    install_hooks_repo=$1
    [ -d "$install_hooks_repo/.git" ] || return 0
    managed_hooks_installed_in_repo . || return 0
    install_hooks_outer_root=$(repo_root)
    install_hooks_outer_root=$(CDPATH= cd -- "$install_hooks_outer_root" && pwd)
    install_hooks_git_stack_path=$(CDPATH= cd -- "$(dirname -- "${0}")" && pwd)/git-stack
    preflight_managed_hook "$install_hooks_repo" post-checkout
    preflight_managed_hook "$install_hooks_repo" post-commit
    preflight_managed_hook "$install_hooks_repo" pre-push
    write_managed_hook "$install_hooks_repo" post-checkout "$install_hooks_outer_root" "$install_hooks_git_stack_path"
    write_managed_hook "$install_hooks_repo" post-commit "$install_hooks_outer_root" "$install_hooks_git_stack_path"
    write_managed_hook "$install_hooks_repo" pre-push "$install_hooks_outer_root" "$install_hooks_git_stack_path"
    printf 'Installed hooks in %s.\n' "$install_hooks_repo"
}

# Build the all-or-nothing hook target list: outer repo plus checked-out modules.
hook_targets_file() {
    out=$1
    : >"$out"
    printf '.\n' >>"$out"
    manifest_modules | while IFS= read -r path; do
        if [ -d "$path/.git" ]; then
            printf '%s\n' "$path" >>"$out"
        fi
    done
    return 0
}

# Refuse unmanaged hooks before installation starts writing files.
preflight_managed_hook() {
    preflight_hook_repo=$1
    preflight_hook_name=$2
    preflight_hook_file=$(hook_path_for "$preflight_hook_repo" "$preflight_hook_name")
    if [ -f "$preflight_hook_file" ] && ! grep -F '# git-stack managed hook' "$preflight_hook_file" >/dev/null 2>&1; then
        die "refusing to overwrite unmanaged hook: $preflight_hook_file"
    fi
}

# Check every hook target up front so install is all-or-nothing.
preflight_hooks_all() {
    targets=$1
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        preflight_managed_hook "$repo" post-checkout
        preflight_managed_hook "$repo" post-commit
        preflight_managed_hook "$repo" pre-push
    done <"$targets"
}

# Install managed hooks in the outer repo and all checked-out modules.
install_hooks_all() {
    ensure_manifest
    outer_root=$(repo_root)
    outer_root=$(CDPATH= cd -- "$outer_root" && pwd)
    git_stack_path=$(CDPATH= cd -- "$(dirname -- "${0}")" && pwd)/git-stack
    targets=$(mktemp)
    hook_targets_file "$targets"

    # Preflight first so an unmanaged hook in any repo prevents partial install.
    preflight_hooks_all "$targets"
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        write_managed_hook "$repo" post-checkout "$outer_root" "$git_stack_path"
        write_managed_hook "$repo" post-commit "$outer_root" "$git_stack_path"
        write_managed_hook "$repo" pre-push "$outer_root" "$git_stack_path"
        printf 'Installed hooks in %s.\n' "$repo"
    done <"$targets"
    rm -f "$targets"
}

# Command wrapper for managed hook installation.
cmd_install_hooks() {
    [ $# -eq 0 ] || die "install-hooks takes no arguments"
    install_hooks_all
}

# Remove one hook only when it is git-stack managed.
remove_managed_hook() {
    repo=$1
    hook=$2
    hook_file=$(hook_path_for "$repo" "$hook")
    [ -f "$hook_file" ] || return 0
    if grep -F '# git-stack managed hook' "$hook_file" >/dev/null 2>&1; then
        rm -f "$hook_file"
    else
        warn "leaving unmanaged hook in place: $hook_file"
    fi
}

# Command wrapper for managed hook removal across all hook targets.
cmd_remove_hooks() {
    [ $# -eq 0 ] || die "remove-hooks takes no arguments"
    ensure_manifest
    targets=$(mktemp)
    hook_targets_file "$targets"
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        remove_managed_hook "$repo" post-checkout
        remove_managed_hook "$repo" post-commit
        remove_managed_hook "$repo" pre-push
        printf 'Removed managed hooks in %s.\n' "$repo"
    done <"$targets"
    rm -f "$targets"
}

# Report pending modules and return nonzero as the outer-merge gate.
cmd_check() {
    [ $# -eq 0 ] || die "check takes no arguments"
    ensure_manifest
    manifest_modules | while IFS= read -r path; do
        pb=$(module_key "$path" pending_branch || true)
        [ -n "$pb" ] || continue
        printf '%s: pending branch %s\n' "$path" "$pb"
    done
    if grep -q '^pending_branch=' "$MANIFEST_FILE"; then
        return 1
    fi
    printf 'No pending modules.\n'
}

# Delete one local pending branch after or after-deferred finalization cleanup.
cleanup_branch_for_module() {
    path=$1
    branch=$2
    [ -n "$branch" ] || return 0
    [ -d "$path/.git" ] || return 0
    if ! git -C "$path" show-ref --verify --quiet "refs/heads/$branch"; then
        warn "cleanup branch already absent for $path: $branch"
        manifest_remove_module_key "$path" finalized_from_branch
        return 0
    fi
    current=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    if [ "$current" = "$branch" ]; then
        revision=$(module_key "$path" revision || true)
        [ -n "$revision" ] || die "cannot clean current branch for $path without finalized revision"
        revision=$(resolve_commit "$path" "$revision" "cannot clean current branch for $path")
        git -C "$path" checkout --detach "$revision" >/dev/null ||
            die "failed to detach $path at finalized revision $revision"
    fi
    git -C "$path" branch -D "$branch" >/dev/null ||
        die "failed to delete local branch $branch in $path"
    manifest_remove_module_key "$path" finalized_from_branch
    printf 'Deleted local branch %s in %s.\n' "$branch" "$path"
}

# Delete all local branches recorded as finalized cleanup hints.
cmd_cleanup_branches() {
    [ $# -eq 0 ] || die "cleanup-branches takes no arguments"
    ensure_manifest
    manifest_modules | while IFS= read -r path; do
        branch=$(module_key "$path" finalized_from_branch || true)
        [ -n "$branch" ] || continue
        cleanup_branch_for_module "$path" "$branch"
    done
}

# Update one clean, non-pending stack module to another recorded version.
cmd_update() {
    [ $# -ge 1 ] || die "usage: git-stack update <module> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]"
    path=$(normalize_path "$1")
    shift
    ensure_manifest
    [ -d "$path/.git" ] || die "$path is not a checked-out module; run git-stack sync first"
    repo=$(module_repo "$path")
    [ -n "$repo" ] || die "$path is not in $MANIFEST_FILE"
    pending=$(module_key "$path" pending_branch || true)
    [ -z "$pending" ] || die "$path is pending on branch $pending; finalize or remove pending state before update"
    if repo_has_dirty "$path"; then
        die "$path has uncommitted changes; commit, stash, or discard them before update"
    fi

    update_target=$(module_key "$path" target_branch || true)
    [ -n "$update_target" ] || update_target=$(default_target_branch "$path")
    update_mode=target_head
    update_value=
    selected=0
    target_changed=0
    fetch=1
    while [ $# -gt 0 ]; do
        case "$1" in
            --revision)
                [ "$selected" -eq 0 ] || die "update selectors are mutually exclusive"
                [ $# -ge 2 ] || die "--revision requires a value"
                update_mode=revision
                update_value=$2
                selected=1
                shift 2
                ;;
            --tag)
                [ "$selected" -eq 0 ] || die "update selectors are mutually exclusive"
                [ $# -ge 2 ] || die "--tag requires a value"
                update_mode=tag
                update_value=$2
                selected=1
                shift 2
                ;;
            --target-head|--remote)
                [ "$selected" -eq 0 ] || die "update selectors are mutually exclusive"
                update_mode=target_head
                selected=1
                shift
                ;;
            --branch|--set-branch)
                [ $# -ge 2 ] || die "$1 requires a value"
                update_target=$2
                target_changed=1
                shift 2
                ;;
            --no-fetch)
                fetch=0
                shift
                ;;
            *) die "unknown update option: $1" ;;
        esac
    done
    require_value "$update_target" "cannot update $path without a target branch"
    if [ "$update_mode" = tag ] && [ "$target_changed" -eq 1 ]; then
        die "--branch cannot be combined with --tag because tag-pinned modules do not record target_branch"
    fi

    update_tag=
    case "$update_mode" in
        revision)
            [ "$fetch" -eq 1 ] && fetch_quiet "$path"
            revision=$(resolve_commit "$path" "$update_value" "cannot update $path with --revision")
            git -C "$path" checkout "$revision" || die "failed to check out revision $revision in $path"
            manifest_write_module "$path" "$repo" tracked "$update_target" "$revision"
            ;;
        tag)
            [ "$fetch" -eq 1 ] && fetch_quiet "$path"
            update_tag=$update_value
            revision=$(resolve_commit "$path" "$update_tag" "cannot update $path with --tag")
            git -C "$path" checkout --detach "$revision" || die "failed to check out tag $update_tag in $path"
            manifest_write_module "$path" "$repo" finalized "$revision" "$update_tag"
            ;;
        target_head)
            revision=$(resolve_target_ref "$path" "$update_target" "$fetch")
            git -C "$path" checkout "$revision" || die "failed to check out target revision $revision in $path"
            manifest_write_module "$path" "$repo" tracked "$update_target" "$revision"
            ;;
    esac
    printf 'Updated %s to %.12s.\n' "$path" "$revision"
}

# Resolve a module target branch to a commit for --use-target-head finalization.
resolve_target_ref() {
    path=$1
    target=$2
    fetch=${3:-1}
    require_value "$target" "cannot resolve target head for $path without a target branch"
    [ "$fetch" -eq 1 ] && fetch_quiet "$path"
    if git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1; then
        resolve_commit "$path" "origin/$target" "cannot resolve target head for $path"
    else
        resolve_commit "$path" "$target" "cannot resolve target head for $path"
    fi
}

# Conservatively infer the finalized commit from exactly one ticket-key match.
auto_finalize_revision() {
    path=$1
    target=$2
    ticket=$(manifest_get stack id || true)
    [ -n "$ticket" ] || ticket=$(ticket_from_branch "$(module_key "$path" pending_branch || true)")
    [ -n "$ticket" ] || die "auto-finalize needs a stack id; use --revision, --tag, or --use-target-head"
    base=$(module_key "$path" base_revision || true)
    fetch_quiet "$path"
    git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1 ||
        die "auto-finalize cannot find origin/$target for $path; fetch the module or use --revision/--tag"
    range=
    if [ -n "$base" ] && git -C "$path" cat-file -e "$base^{commit}" 2>/dev/null; then
        range="$base..origin/$target"
    else
        range="origin/$target"
    fi
    matches=$(git -C "$path" log --format='%H %s' "$range" 2>/dev/null | grep "$ticket" || true)
    count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
    [ "$count" = "1" ] || die "auto-finalize found $count candidates for $ticket; use an explicit selector"
    revision=$(printf '%s\n' "$matches" | awk '{print $1}')
    require_value "$revision" "auto-finalize matched $ticket but produced an empty revision for $path; use --revision"
    resolve_commit "$path" "$revision" "cannot auto-finalize $path"
}

# Convert a module from pending to finalized state using an explicit or auto selector.
cmd_finalize() {
    [ $# -ge 1 ] || die "usage: git-stack finalize <module> [--cleanup] [--revision <sha> | --tag <tag> | --use-target-head]"
    path=$(normalize_path "$1")
    shift
    ensure_manifest
    [ -d "$path/.git" ] || die "$path is not a checked-out module"
    repo=$(module_repo "$path")
    [ -n "$repo" ] || die "$path is not in $MANIFEST_FILE"
    target=$(module_key "$path" target_branch || true)
    [ -n "$target" ] || target=main

    mode=auto
    value=
    cleanup=0

    # Selectors are mutually exclusive so the manifest gets one clear source of
    # truth: explicit revision, explicit tag, target head, or conservative auto.
    while [ $# -gt 0 ]; do
        case "$1" in
            --cleanup)
                cleanup=1
                shift
                ;;
            --revision)
                [ "$mode" = auto ] || die "finalize selectors are mutually exclusive"
                [ $# -ge 2 ] || die "--revision requires a value"
                mode=revision
                value=$2
                shift 2
                ;;
            --tag)
                [ "$mode" = auto ] || die "finalize selectors are mutually exclusive"
                [ $# -ge 2 ] || die "--tag requires a value"
                mode=tag
                value=$2
                shift 2
                ;;
            --use-target-head)
                [ "$mode" = auto ] || die "finalize selectors are mutually exclusive"
                mode=target_head
                shift
                ;;
            *) die "unknown finalize option: $1" ;;
        esac
    done

    tag=
    # Every path resolves to a concrete commit before the manifest is touched.
    case "$mode" in
        revision)
            revision=$(resolve_commit "$path" "$value" "cannot finalize $path with --revision")
            ;;
        tag)
            tag=$value
            revision=$(resolve_commit "$path" "$value" "cannot finalize $path with --tag")
            ;;
        target_head)
            revision=$(resolve_target_ref "$path" "$target")
            ;;
        auto)
            revision=$(auto_finalize_revision "$path" "$target")
            ;;
    esac
    require_value "$revision" "finalize produced an empty revision for $path; use --revision <sha>"

    old_pending=$(module_key "$path" pending_branch || true)
    manifest_write_module "$path" "$repo" finalized "$revision" "$tag" "$old_pending"

    # Cleanup is local-only: remote review branches and untracked files are not
    # deleted by finalize.
    if [ "$cleanup" -eq 1 ] && [ -n "$old_pending" ]; then
        cleanup_branch_for_module "$path" "$old_pending"
    fi
    printf 'Finalized %s at %.12s.\n' "$path" "$revision"
}

# Clone/fetch modules and restore their pending or finalized manifest state.
sync_current() {
    ensure_manifest
    modules_tmp=$(tmp_for "$MANIFEST_FILE.sync")
    failures_tmp=$(tmp_for "$MANIFEST_FILE.sync_failures")
    manifest_modules >"$modules_tmp"
    : >"$failures_tmp"
    rc=0

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if (
            repo=$(module_repo "$path")
            [ -n "$repo" ] || die "missing repo for $path"
            created=0
            clone_mode=$(effective_clone_mode "$path")
            if [ ! -d "$path/.git" ]; then
                clone_module "$repo" "$path" "$clone_mode" 1
                created=1
            fi
            if [ "$created" -eq 1 ]; then
                install_hooks_in_repo_if_stack_managed "$path"
            fi
            fetch_quiet "$path"
            pending=$(module_key "$path" pending_branch || true)
            tag=$(module_key "$path" tag || true)
            revision=$(module_key "$path" revision || true)
            target=$(module_key "$path" target_branch || true)
            [ -n "$target" ] || target=main

            # Pending branches take precedence because they represent work still in
            # review; finalized tags/revisions are checked out only after pending is gone.
            if [ -n "$pending" ]; then
                if git -C "$path" show-ref --verify --quiet "refs/heads/$pending"; then
                    git -C "$path" checkout "$pending" || die "failed to check out pending branch $pending in $path"
                elif git -C "$path" rev-parse --verify "origin/$pending^{commit}" >/dev/null 2>&1; then
                    git -C "$path" checkout -b "$pending" "origin/$pending" ||
                        die "failed to create pending branch $pending from origin/$pending in $path"
                else
                    warn "pending branch $pending not found for $path"
                fi
            elif [ -n "$tag" ]; then
                resolve_commit "$path" "$tag" "cannot sync $path tag $tag" >/dev/null
                git -C "$path" checkout "$tag" || die "failed to check out tag $tag in $path"
            elif [ -n "$revision" ]; then
                revision=$(resolve_commit "$path" "$revision" "cannot sync $path revision")
                git -C "$path" checkout "$revision" || die "failed to check out revision $revision in $path"
            elif [ "$created" -eq 1 ] && [ "$clone_mode" = partial ]; then
                checkout_target_branch "$path" "$target"
            fi
            printf 'Synced %s.\n' "$path"
        ); then
            :
        else
            rc=1
            printf '%s\n' "$path" >>"$failures_tmp"
        fi
    done <"$modules_tmp"

    rm -f "$modules_tmp"
    if [ "$rc" -ne 0 ]; then
        printf 'Error: sync failed for one or more modules:\n' >&2
        while IFS= read -r path; do
            [ -n "$path" ] && printf '  %s\n' "$path" >&2
        done <"$failures_tmp"
        rm -f "$failures_tmp"
        return 1
    fi
    rm -f "$failures_tmp"
}

# Recursively sync the current stack and nested stack roots.
sync_recursive() {
    label=$1
    visited=$2
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    printf 'Syncing stack: %s\n' "$label"
    sync_current || return 1

    modules_tmp=$(tmp_for "$MANIFEST_FILE.sync_recursive")
    manifest_modules >"$modules_tmp"
    rc=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_stack_label "$label" "$path")
            (
                cd "$path" || exit 1
                sync_recursive "$child_label" "$visited"
            ) || rc=1
        fi
    done <"$modules_tmp"
    rm -f "$modules_tmp"
    return "$rc"
}

# Sync stack state, optionally including nested stacks.
cmd_sync() {
    recursive=$(parse_recursive_only "$@")
    if [ "$recursive" -eq 1 ]; then
        visited=$(mktemp)
        : >"$visited"
        sync_recursive "." "$visited"
        rc=$?
        rm -f "$visited"
        return "$rc"
    fi
    sync_current
    notice_nested_stacks
}

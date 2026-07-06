#!/bin/sh
#
# git-lego 0.7.1
#
# Lightweight multi-repository workspace coordination for ordinary Git remotes.
# A project root repository tracks a manifest of nested subproject repositories,
# while this script provides the command behavior for initializing, syncing,
# branching, uploading, finalizing, and verifying that workspace state.
#
# This file is the shared shell implementation sourced by bin/git-lego.
# Keeping command logic here leaves the PATH-facing entrypoint tiny while
# avoiding a separate lib/ tree for a small script-first project. The Windows
# wrapper reaches this code indirectly by launching bin/git-lego through
# Git Bash.
#
# Copyright (c) 2026 Flemming Steffensen.
# License: MIT
# SPDX-License-Identifier: MIT

MANIFEST_FILE=${GIT_LEGO_MANIFEST:-.gitlego}
CONFIG_FILE=${GIT_LEGO_CONFIG:-.gitlego-rc}
GIT_LEGO_VERSION=0.7.1
MANIFEST_SCHEMA_VERSION=1
JSON_SCHEMA_VERSION=1
GITATTRIBUTES_GUARD='.gitlego text eol=lf'
GITATTRIBUTES_BEGIN='# BEGIN git-lego attributes'
GITATTRIBUTES_END='# END git-lego attributes'
GITIGNORE_GIT_DIR_GUARD_ONE='**/.git/'
GITIGNORE_GIT_DIR_GUARD_TWO='**/.git'
OLD_HOOK_WARNING_PRINTED=0
MANIFEST_LOCK_HELD=
MANIFEST_LOCK_PATH=
GIT_LEGO_EXIT_HANDLER_INSTALLED=0
GIT_LEGO_NO_FETCH=0
GIT_LEGO_BASE_OVERRIDES=
GIT_LEGO_DRY_RUN=0
GIT_LEGO_JSON_DRY_RUN=0

EXIT_ISSUES=1
EXIT_USAGE=2
EXIT_PRECONDITION=3
EXIT_LOCK=4
EXIT_GIT=5

# Print a user-facing error and stop the current command with a nonzero exit.
die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

die_code() {
    code=$1
    shift
    printf 'Error: %s\n' "$*" >&2
    exit "$code"
}

usage_error() {
    die_code "$EXIT_USAGE" "$@"
}

precondition_error() {
    die_code "$EXIT_PRECONDITION" "$@"
}

git_error() {
    die_code "$EXIT_GIT" "$@"
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
    [ -n "$value" ] || precondition_error "$message"
}

cleanup_manifest_lock() {
    if [ -n "$MANIFEST_LOCK_HELD" ] && [ -n "$MANIFEST_LOCK_PATH" ]; then
        rm -rf "$MANIFEST_LOCK_PATH" 2>/dev/null || true
        MANIFEST_LOCK_HELD=
    fi
}

install_exit_handler() {
    [ "$GIT_LEGO_EXIT_HANDLER_INSTALLED" -eq 0 ] || return 0
    trap 'status=$?; cleanup_manifest_lock; exit $status' EXIT
    trap 'cleanup_manifest_lock; trap - INT; kill -INT $$' INT
    trap 'cleanup_manifest_lock; trap - TERM; kill -TERM $$' TERM
    GIT_LEGO_EXIT_HANDLER_INSTALLED=1
}

sleep_ms() {
    ms=$1
    case "$ms" in
        50) sleep 0.05 ;;
        100) sleep 0.1 ;;
        200) sleep 0.2 ;;
        400) sleep 0.4 ;;
        *) sleep 0.5 ;;
    esac
}

utc_now() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

acquire_manifest_lock() {
    [ -z "$MANIFEST_LOCK_HELD" ] || return 0
    MANIFEST_LOCK_PATH=$MANIFEST_FILE.lock
    delay=50
    waited=0
    while [ "$waited" -lt 10000 ]; do
        if mkdir "$MANIFEST_LOCK_PATH" 2>/dev/null; then
            {
                printf 'pid=%s\n' "$$"
                printf 'created_utc=%s\n' "$(utc_now)"
            } >"$MANIFEST_LOCK_PATH/info"
            MANIFEST_LOCK_HELD=1
            install_exit_handler
            return 0
        fi
        sleep_ms "$delay"
        waited=$((waited + delay))
        if [ "$delay" -lt 500 ]; then
            delay=$((delay * 2))
            [ "$delay" -le 500 ] || delay=500
        fi
    done

    pid=unknown
    created=unknown
    if [ -f "$MANIFEST_LOCK_PATH/info" ]; then
        pid=$(sed -n 's/^pid=//p' "$MANIFEST_LOCK_PATH/info" | sed -n '1p')
        created=$(sed -n 's/^created_utc=//p' "$MANIFEST_LOCK_PATH/info" | sed -n '1p')
        [ -n "$pid" ] || pid=unknown
        [ -n "$created" ] || created=unknown
    fi
    printf 'Error: could not acquire manifest lock %s after 10 seconds\n' "$MANIFEST_LOCK_PATH" >&2
    printf '  lock pid: %s\n' "$pid" >&2
    printf '  lock created UTC: %s\n' "$created" >&2
    printf '  if no git-lego process is using it, remove it with: rm -rf %s\n' "$MANIFEST_LOCK_PATH" >&2
    exit "$EXIT_LOCK"
}

json_escape() {
    awk '
        BEGIN { ORS="" }
        {
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "\\") printf "\\\\"
                else if (c == "\"") printf "\\\""
                else if (c == "\b") printf "\\b"
                else if (c == "\f") printf "\\f"
                else if (c == "\n") printf "\\n"
                else if (c == "\r") printf "\\r"
                else if (c == "\t") printf "\\t"
                else printf "%s", c
            }
        }
    '
}

json_string() {
    printf '"'
    printf '%s' "$1" | json_escape
    printf '"'
}

json_row_object() {
    code=$1
    path=$2
    state=$3
    target=$4
    current=$5
    expected=$6
    detail=$7
    printf '{"code":'
    json_string "$code"
    printf ',"path":'
    json_string "$path"
    printf ',"state":'
    json_string "$state"
    printf ',"target":'
    json_string "$target"
    printf ',"current":'
    json_string "$current"
    printf ',"expected":'
    json_string "$expected"
    printf ',"detail":'
    json_string "$detail"
    printf '}'
}

json_array_from_lines() {
    file=$1
    first=1
    printf '['
    if [ -f "$file" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            [ "$first" -eq 1 ] || printf ','
            first=0
            json_string "$line"
        done <"$file"
    fi
    printf ']'
}

json_rows_from_porcelain_file() {
    file=$1
    first=1
    printf '['
    if [ -f "$file" ]; then
        while IFS='	' read -r code path state target current expected detail rest; do
            [ -n "$code" ] || continue
            [ "$first" -eq 1 ] || printf ','
            first=0
            json_row_object "$code" "$path" "$state" "$target" "$current" "$expected" "$detail"
        done <"$file"
    fi
    printf ']'
}

emit_json_result() {
    command=$1
    recursive=$2
    ok=$3
    rows_file=$4
    errors_file=$5
    warnings_file=$6
    pretty=${7:-0}
    if [ "$pretty" -eq 1 ]; then
        # Keep generation dependency-free; python is only a best-effort pretty printer.
        compact=$(mktemp)
        emit_json_result "$command" "$recursive" "$ok" "$rows_file" "$errors_file" "$warnings_file" 0 >"$compact"
        if command -v python >/dev/null 2>&1; then
            python -m json.tool "$compact"
        elif command -v python3 >/dev/null 2>&1; then
            python3 -m json.tool "$compact"
        else
            cat "$compact"
        fi
        rm -f "$compact"
        return
    fi
    printf '{"version":%s,"command":' "$JSON_SCHEMA_VERSION"
    json_string "$command"
    if [ "$GIT_LEGO_JSON_DRY_RUN" -eq 1 ]; then
        printf ',"dry_run":true'
    fi
    printf ',"recursive":'
    [ "$recursive" -eq 1 ] && printf 'true' || printf 'false'
    printf ',"ok":'
    [ "$ok" -eq 1 ] && printf 'true' || printf 'false'
    printf ',"subprojects":'
    json_rows_from_porcelain_file "$rows_file"
    printf ',"errors":'
    json_array_from_lines "$errors_file"
    printf ',"warnings":'
    json_array_from_lines "$warnings_file"
    printf '}\n'
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

regex_escape() {
    printf '%s\n' "$1" | sed 's/[][(){}.^$*+?|\\-]/\\&/g'
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
git-lego: coordinate branches and pinned revisions across nested Git repositories

Usage:
  git-lego init [--rc]
  git-lego add [--clone <full|partial>] <repo> <path>
  git-lego remove|rm <path> [--force] [--keep-files]
  git-lego mv <old-path> <new-path> [--force]
  git-lego mv --url <new-url> <path>
  git-lego clone <outer-repo-url> [target-dir] [--no-sync] [--depth <n>] [--branch <branch>] [--single-branch]
  git-lego status [--recursive] [--porcelain | --json | --json-pretty] [--exit-code]
  git-lego outdated [--recursive] [--porcelain | --json | --json-pretty]
  git-lego verify [--recursive] [--json | --json-pretty]
  git-lego diff [--since <ref>] [--stat] [--json | --json-pretty]
  git-lego log [--max-count <n>] [--since <date>] [--until <date>] [--subproject <path>] [--oneline] [--recursive]
  git-lego start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]
  git-lego snapshot [--recursive] [--quiet] [--dry-run] [--no-fetch] [--base <subproject>=<ref>]
  git-lego upload [--finalize] [--dry-run] [--no-fetch] [--base <subproject>=<ref>]
  git-lego freeze [--force] [--only <path>[,<path>...]] [--dry-run]
  git-lego install-hooks
  git-lego remove-hooks
  git-lego foreach -- <command> [args...]
  git-lego foreach-pending -- <command> [args...]
  git-lego foreach-modified [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]
  git-lego foreach-clean [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]
  git-lego no-pending [--json | --json-pretty]
  git-lego config <get|set|list|unset> ...
  git-lego update <subproject> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]
  git-lego finalize <subproject> [--dry-run] [--cleanup] [--revision <sha> | --tag <tag> | --use-target-head]
  git-lego cleanup-branches
  git-lego sync [--recursive] [--prune] [--force] [--dry-run]
  git-lego doctor [--json | --json-pretty] [--offline] [--timeout <seconds>] [--exit-code]
  git-lego completion <bash|zsh|fish>
  git-lego export --output <path> [--format <tar.gz|zip|dir>] [--include-git] [--deterministic] [--allow-dirty]
  git-lego extract <path> <remote-url> [--branch <name>] [--clone-mode <full|partial>] [--preserve-history] [--push] [--message <msg>] [--force] [--dry-run]
  git-lego absorb <path> [--commit] [--message <msg>] [--dry-run]
  git-lego version

Commands:
  init [--rc]
      Create a .gitlego manifest in the current workspace.
          --rc also creates .gitlego-rc with default values.
  add [--clone <full|partial>] <repo> <path>
      Add and clone a subproject, ignore its path in the outer repo, and
      record its current target branch and revision.
          --clone selects full or partial clone storage for this subproject.
  remove|rm <path> [--force] [--keep-files]
      Remove a subproject from the manifest.
          --force skips dirty/current-branch safety checks.
          --keep-files leaves the checkout on disk and keeps its ignore entry.
  mv <old-path> <new-path> [--force]
      Move a subproject path while preserving manifest state.
          --force skips dirty/current-branch safety checks.
  mv --url <new-url> <path>
      Change a subproject repository URL in the manifest only.
  clone <outer-repo-url> [target-dir] [--no-sync] [--depth <n>] [--branch <branch>] [--single-branch]
      Clone an outer repository and automatically sync when it has a manifest.
          --no-sync skips the automatic sync.
  status [--recursive] [--porcelain | --json | --json-pretty] [--exit-code]
      Show project and subproject state.
          --recursive includes nested projects.
          --porcelain prints stable fixed-column records for scripts.
          --json and --json-pretty print machine-readable output.
          --exit-code returns 1 when dirty or missing rows exist.
  outdated [--recursive] [--porcelain | --json | --json-pretty]
      Check subproject remotes for newer target-branch commits without fetching.
          --recursive includes nested projects.
          --porcelain prints stable fixed-column records for scripts.
          --json and --json-pretty print machine-readable output.
  verify [--recursive] [--json | --json-pretty]
      Validate manifest, remotes, refs, clone mode, and checked-out revisions.
          --recursive includes nested projects.
          --json and --json-pretty print machine-readable output.
  diff [--since <ref>] [--stat] [--json | --json-pretty]
      Show subproject commits between manifest revisions and current checkouts.
          --since reads manifest revisions from the outer repo at ref.
          --stat includes file statistics in human output.
          --json and --json-pretty print machine-readable commit rows.
  log [--max-count <n>] [--since <date>] [--until <date>] [--subproject <path>] [--oneline] [--recursive]
      Show combined project history. Filters mirror common git log concepts;
          --max-count limits commits per repository before the final sort.
          --since and --until filter commits by date.
          --subproject restricts output to one subproject path.
          --oneline uses compact commit output.
          --recursive includes nested projects.
  start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]
      Start or track a coordinated project branch.
          --stash-dirty stashes dirty repositories before switching.
          --discard-dirty discards tracked edits, then rejects untracked files.
          --cancel-dirty fails if any repository is dirty.
          --hooks installs managed hooks.
          --sure confirms startup in a non-Git folder with subdirectories.
  snapshot [--recursive] [--quiet] [--dry-run] [--no-fetch] [--base <subproject>=<ref>]
      Snapshot local manifest state without pushing.
          --recursive includes nested projects.
          --quiet suppresses skip warnings for dirty subprojects.
          --dry-run prints planned manifest changes without writing.
          --no-fetch uses local refs for base detection.
          --base sets an explicit base ref for one subproject.
  upload [--finalize] [--dry-run] [--no-fetch] [--base <subproject>=<ref>]
      Push changed subproject branches and the outer branch. By default records
          pending subproject state.
          --finalize pins pushed subproject commits directly.
          --dry-run prints planned pushes and manifest changes without writing.
          --no-fetch uses local refs for base detection.
          --base sets an explicit base ref for one subproject.
  freeze [--force] [--only <path>[,<path>...]] [--dry-run]
      Pin tracked subprojects to their current checkout commits.
          --force freezes dirty subprojects with warnings.
          --only limits freezing to a comma-separated path list.
          --dry-run prints what would change without writing.
  install-hooks
      Install managed local Git hooks for this project.
  remove-hooks
      Remove managed local Git hooks for this project.
  foreach -- <command> [args...]
      Run a command in every checked-out subproject.
  foreach-pending -- <command> [args...]
      Run a command only in manifest-pending subprojects.
  foreach-modified [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]
      Run a command in dirty subprojects, or list them with machine output.
  foreach-clean [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]
      Run a command in clean checked-out subprojects, or list them with machine output.
  no-pending [--json | --json-pretty]
      Fail while any subproject remains pending.
  config <get|set|list|unset> ...
      Read or update allowlisted manifest settings.
  update <subproject> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]
      Move one clean, non-pending subproject to a selected revision.
          --remote and --target-head use the target branch head.
          --revision pins an explicit commit-ish.
          --tag pins a tag and records the tag name.
          --branch retargets before resolving the selected revision.
          --no-fetch resolves only local refs.
  finalize <subproject> [--dry-run] [--cleanup] [--revision <sha> | --tag <tag> | --use-target-head]
      Convert a pending subproject to a pinned revision.
          --revision pins an explicit commit.
          --tag pins a tag and records the tag name.
          --use-target-head pins the target branch head.
          --dry-run prints planned manifest/cleanup changes without writing.
          --cleanup deletes the local pending branch after finalization.
  cleanup-branches
      Delete local branches recorded as finalized cleanup hints.
  sync [--recursive] [--prune] [--force] [--dry-run]
      Clone/fetch subprojects and restore the manifest state.
          --recursive includes nested projects.
          --prune removes stale local-state paths after review when sync suggests it.
          --force proceeds when a tag moved away from the recorded revision.
          --dry-run prints planned clone/fetch/checkout/prune actions without writing.
  doctor [--json | --json-pretty] [--offline] [--timeout <seconds>] [--exit-code]
      Report environment and workspace health without modifying files.
  completion <bash|zsh|fish>
      Print a shell completion script to stdout.
  export --output <path> [--format <tar.gz|zip|dir>] [--include-git] [--deterministic] [--allow-dirty]
      Export a source snapshot with .gitlego and MANIFEST.lock.
          --format overrides output extension inference.
          --include-git keeps nested .git directories.
          --deterministic normalizes archive ordering and metadata where supported.
          --allow-dirty permits dirty subproject working trees.
  extract <path> <remote-url> [options]
      Convert a tracked directory into a managed subproject.
          --branch names the initial branch; default is main.
          --clone-mode records full or partial clone preference.
          --preserve-history uses git-filter-repo when installed.
          --push pushes the new subproject branch to origin.
          --message sets the initial commit message.
          --force bypasses metadata conflicts only.
          --dry-run reports planned changes without writing.
  absorb <path> [options]
      Convert a managed subproject back into ordinary outer-repo files.
          --commit commits the staged outer-repo changes.
          --message sets the commit message and implies --commit.
          --dry-run reports planned changes without writing.
  version
      Print the git-lego version.

Manifest: .gitlego
EOF
}

# Dispatch the public command name to the matching command handler.
git_lego_main() {
    cmd=${1:-}
    [ $# -gt 0 ] && shift || true

    case "$cmd" in
        init) enter_workspace_root_if_present; cmd_init "$@" ;;
        add) enter_workspace_root_if_present; cmd_add "$@" ;;
        remove|rm) enter_project_root_required; cmd_remove "$@" ;;
        mv) enter_project_root_required; cmd_mv "$@" ;;
        clone) cmd_clone "$@" ;;
        status) enter_project_root_required; cmd_status "$@" ;;
        outdated) enter_project_root_required; cmd_outdated "$@" ;;
        available) usage_error "unknown command: available; use outdated" ;;
        verify) enter_project_root_required; cmd_verify "$@" ;;
        diff) enter_project_root_required; cmd_diff "$@" ;;
        log) enter_project_root_required; cmd_log "$@" ;;
        start) enter_workspace_root_if_present; cmd_start "$@" ;;
        snapshot) enter_project_root_required; cmd_snapshot "$@" ;;
        refresh) usage_error "unknown command: refresh; use snapshot" ;;
        record) usage_error "unknown command: record; use snapshot" ;;
        upload) enter_project_root_required; cmd_upload "$@" ;;
        freeze) enter_project_root_required; cmd_freeze "$@" ;;
        install-hooks) enter_project_root_required; cmd_install_hooks "$@" ;;
        remove-hooks) enter_project_root_required; cmd_remove_hooks "$@" ;;
        foreach) enter_project_root_required; cmd_foreach "$@" ;;
        foreach-pending) enter_project_root_required; cmd_foreach_pending "$@" ;;
        foreach-modified) enter_project_root_required; cmd_foreach_modified "$@" ;;
        foreach-clean) enter_project_root_required; cmd_foreach_clean "$@" ;;
        no-pending) enter_project_root_required; cmd_no_pending "$@" ;;
        config) enter_project_root_required; cmd_config "$@" ;;
        check) usage_error "unknown command: check; use no-pending" ;;
        update) enter_project_root_required; cmd_update "$@" ;;
        finalize) enter_project_root_required; cmd_finalize "$@" ;;
        cleanup-branches) enter_project_root_required; cmd_cleanup_branches "$@" ;;
        sync) enter_project_root_required; cmd_sync "$@" ;;
        doctor) cmd_doctor "$@" ;;
        completion) cmd_completion "$@" ;;
        export) enter_project_root_required; cmd_export "$@" ;;
        extract) enter_project_root_required; cmd_extract "$@" ;;
        absorb) enter_project_root_required; cmd_absorb "$@" ;;
        __complete) cmd_internal_complete "$@" ;;
        __owning-manifest) cmd_internal_owning_manifest "$@" ;;
        version|--version) cmd_version "$@" ;;
        -h|--help|help|"") usage ;;
        *) usage_error "unknown command: $cmd" ;;
    esac
}

# Report the implemented tool version used by docs and tests.
cmd_version() {
    [ $# -eq 0 ] || die "version takes no arguments"
    printf 'git-lego %s\n' "$GIT_LEGO_VERSION"
}

cmd_internal_owning_manifest() {
    [ $# -le 1 ] || usage_error "usage: git-lego __owning-manifest [path]"
    find_owning_manifest "$@"
}

# Ensure Git is available before commands depend on it.
require_git() {
    command -v git >/dev/null 2>&1 || die "git is required"
}

# Detect old manifests only to fail clearly. git-lego does not migrate .stack.
find_legacy_manifest_root() {
    dir=$(pwd)
    while :; do
        if [ -f "$dir/.stack" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        parent=$(dirname "$dir")
        [ "$parent" != "$dir" ] || return 1
        dir=$parent
    done
}

canonical_start_dir_for_path() {
    target=$1
    [ -e "$target" ] || precondition_error "$target does not exist; cannot locate owning $MANIFEST_FILE"
    resolved=
    if command -v readlink >/dev/null 2>&1; then
        resolved=$(readlink -f -- "$target" 2>/dev/null || true)
    fi
    [ -n "$resolved" ] || resolved=$target
    if [ -d "$resolved" ]; then
        (CDPATH= cd -P -- "$resolved" && pwd) ||
            precondition_error "cannot resolve path $target"
    else
        dir=$(dirname -- "$resolved")
        (CDPATH= cd -P -- "$dir" && pwd) ||
            precondition_error "cannot resolve path $target"
    fi
}

# Walk upward to find the nearest owning manifest. This never walks downward;
# recursive operations use purpose-specific traversal helpers.
find_owning_manifest() {
    if [ $# -gt 0 ]; then
        dir=$(canonical_start_dir_for_path "$1")
    else
        dir=$(pwd -P)
    fi
    while :; do
        if [ -f "$dir/$MANIFEST_FILE" ]; then
            printf '%s/%s\n' "$dir" "$MANIFEST_FILE"
            return 0
        fi
        parent=$(dirname "$dir")
        [ "$parent" != "$dir" ] || precondition_error "not inside a git-lego project"
        dir=$parent
    done
}

find_project_root() {
    manifest=$(find_owning_manifest 2>/dev/null) || return 1
    dirname -- "$manifest"
}

# Commands that can create a workspace still anchor to an existing project or Git
# root when one is visible, preventing accidental nested manifests from subdirs.
enter_workspace_root_if_present() {
    require_git
    if root=$(find_project_root 2>/dev/null); then
        cd "$root" || die "cannot enter project root $root"
        return
    fi
    if root=$(find_legacy_manifest_root 2>/dev/null); then
        precondition_error "legacy .stack manifest found at $root; git-lego uses .gitlego and does not migrate old manifests"
    fi
    if root=$(git rev-parse --show-toplevel 2>/dev/null); then
        cd "$root" || die "cannot enter Git root $root"
    fi
}

# Operational commands need an existing manifest and always run from its root so
# subproject paths in .gitlego are interpreted consistently.
enter_project_root_required() {
    require_git
    root=$(find_project_root 2>/dev/null) ||
        {
            if legacy_root=$(find_legacy_manifest_root 2>/dev/null); then
                precondition_error "legacy .stack manifest found at $legacy_root; git-lego uses .gitlego and does not migrate old manifests"
            fi
            precondition_error "not inside a git-lego workspace; run git-lego init or cd to a project"
        }
    cd "$root" || die "cannot enter project root $root"
    validate_manifest_schema
    project_invocation_warnings
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

gitattributes_has_guard() {
    [ -f .gitattributes ] || return 1
    awk '
        /^[[:space:]]*\.gitlego[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { gitlego=1 }
        /^[[:space:]]*\.gitlego-rc[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { rc=1 }
        /^[[:space:]]*bin\/git-lego[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { entrypoint=1 }
        /^[[:space:]]*bin\/git_lego\.sh[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { shell=1 }
        /^[[:space:]]*bin\/git-lego\.bat[[:space:]]+text[[:space:]]+eol=crlf[[:space:]]*$/ { batch=1 }
        END { exit !(gitlego && rc && entrypoint && shell && batch) }
    ' .gitattributes
}

print_gitattributes_guard() {
    printf '%s\n' "$GITATTRIBUTES_BEGIN"
    printf '%s\n' "$GITATTRIBUTES_GUARD"
    printf '.gitlego-rc text eol=lf\n'
    printf 'bin/git-lego text eol=lf\n'
    printf 'bin/git_lego.sh text eol=lf\n'
    printf 'bin/git-lego.bat text eol=crlf\n'
    printf '%s\n' "$GITATTRIBUTES_END"
}

ensure_gitattributes_guard() {
    if gitattributes_has_guard; then
        return 0
    fi
    if [ ! -f .gitattributes ]; then
        print_gitattributes_guard >.gitattributes
        return
    fi
    tmp=$(tmp_for .gitattributes)
    {
        print_gitattributes_guard
        awk '
            /^[[:space:]]*# BEGIN git-lego attributes[[:space:]]*$/ { in_block=1; next }
            /^[[:space:]]*# END git-lego attributes[[:space:]]*$/ { in_block=0; next }
            in_block { next }
            {
                trimmed=$0
                sub(/^[[:space:]]+/, "", trimmed)
                sub(/[[:space:]]+$/, "", trimmed)
                if (trimmed ~ /^\.gitlego([[:space:]]|$)/) next
                if (trimmed ~ /^\.gitlego-rc([[:space:]]|$)/) next
                if (trimmed ~ /^bin\/git-lego([[:space:]]|$)/) next
                if (trimmed ~ /^bin\/git_lego\.sh([[:space:]]|$)/) next
                if (trimmed ~ /^bin\/git-lego\.bat([[:space:]]|$)/) next
                print
            }
        ' .gitattributes
    } >"$tmp"
    mv "$tmp" .gitattributes
}

warn_missing_gitattributes_guard() {
    gitattributes_has_guard && return 0
    warn "missing or stale git-lego .gitattributes guard; run git-lego init to repair it"
}

warn_old_managed_hooks() {
    [ "$OLD_HOOK_WARNING_PRINTED" -eq 0 ] || return 0
    git rev-parse --git-dir >/dev/null 2>&1 || return 0
    for hook_name in post-checkout post-commit pre-push; do
        hook_file=$(hook_path_for . "$hook_name" 2>/dev/null || true)
        [ -n "$hook_file" ] || continue
        [ -f "$hook_file" ] || continue
        if grep -F 'refresh --quiet' "$hook_file" >/dev/null 2>&1; then
            warn "old git-stack managed hook detected; run git-lego install-hooks to update hooks"
            OLD_HOOK_WARNING_PRINTED=1
            return 0
        fi
    done
}

project_invocation_warnings() {
    warn_missing_gitattributes_guard
    warn_old_managed_hooks
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
    printf 'This folder contains subdirectories. Initialize it as a git-lego workspace? [y/N] ' >/dev/tty
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
            printf '# git-lego manifest\n\n'
            printf '[project]\n'
            printf 'version=%s\n' "$MANIFEST_SCHEMA_VERSION"
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

# Normalize subproject paths so manifest section names are stable across platforms.
normalize_path() {
    printf '%s\n' "$1" | sed 's#//*#/#g; s#/$##'
}

reject_backslash_path() {
    case "$1" in
        *[\\]*)
            suggested=$(printf '%s\n' "$1" | tr '\\' '/')
            usage_error "subproject paths must use forward slashes; got \"$1\". Use \"$suggested\"."
            ;;
    esac
}

path_is_relative_safe() {
    case "$1" in
        ""|/*|[A-Za-z]:*|../*|*/../*|..|.) return 1 ;;
        .git|.gitlego|.gitlego.lock|.gitlego-rc|.gitignore|.gitattributes) return 1 ;;
        .git/*|*/.git|*/.git/*) return 1 ;;
        *) return 0 ;;
    esac
}

assert_safe_project_path() {
    path=$1
    path_is_relative_safe "$path" ||
        precondition_error "path must be a relative path inside the current project: $path"
}

assert_path_not_inside_nested_project() {
    candidate=$1
    assert_safe_project_path "$candidate"
    manifest_subprojects | while IFS= read -r boundary; do
        [ -n "$boundary" ] || continue
        [ -f "$boundary/$MANIFEST_FILE" ] || continue
        case "$candidate" in
            "$boundary"/*)
                precondition_error "$candidate is inside nested project $boundary; run git-lego from $boundary instead"
                ;;
        esac
    done
}

assert_path_not_containing_nested_project() {
    candidate=$1
    [ -d "$candidate" ] || return 0
    if find "$candidate" -mindepth 1 -name "$MANIFEST_FILE" -type f 2>/dev/null | sed -n '1p' | grep . >/dev/null 2>&1; then
        precondition_error "$candidate contains a nested git-lego project; recursive extract/absorb is not supported yet"
    fi
}

stage_outer_paths() {
    git add -- "$@" || git_error "failed to stage outer repository changes"
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
    manifest_get_from_file "$MANIFEST_FILE" "$section" "$key"
}

# Read one key from one section in a specific manifest file.
manifest_get_from_file() {
    file=$1
    section=$2
    key=$3
    awk -v section="$section" -v key="$key" '
        $0 == "[" section "]" { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && index($0, key "=") == 1 {
            print substr($0, length(key) + 2)
            exit
        }
    ' "$file"
}

manifest_section_kind() {
    section=$1
    case "$section" in
        project) printf 'project\n' ;;
        subproject\ \"*\") printf 'subproject\n' ;;
        *) printf 'unknown\n' ;;
    esac
}

validate_manifest_schema() {
    [ -f "$MANIFEST_FILE" ] || precondition_error "missing $MANIFEST_FILE; run git-lego init"

    errors=$(tmp_for "$MANIFEST_FILE.schema_errors")
    : >"$errors"
    awk -v expected="$MANIFEST_SCHEMA_VERSION" -v errors="$errors" '
        function add_error(message) {
            print "Error: " message >> errors
        }
        /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
        /^\[/ {
            if ($0 == "[project]") {
                section = "project"
            } else if ($0 ~ /^\[subproject "[^"]+"\]$/) {
                section = substr($0, 2, length($0) - 2)
            } else if ($0 ~ /^\[subproject /) {
                add_error("malformed subproject section in .gitlego: " $0)
                section = ""
                next
            } else if ($0 ~ /^\[[^]]+\]$/) {
                section = substr($0, 2, length($0) - 2)
            } else {
                add_error("malformed section in .gitlego: " $0)
                section = ""
                next
            }
            if ((section == "project" || section ~ /^subproject "[^"]+"$/) && seen_section[section]++) {
                add_error("duplicate section in .gitlego: [" section "]")
            }
            next
        }
        index($0, "=") > 0 {
            if (section == "") {
                add_error("key outside a valid section in .gitlego: " $0)
                next
            }
            key = substr($0, 1, index($0, "=") - 1)
            value = substr($0, index($0, "=") + 1)
            if (key ~ /^[[:space:]]/ || key ~ /[[:space:]]$/ || key == "") {
                add_error("malformed key in .gitlego: " $0)
                next
            }
            sk = section SUBSEP key
            if ((section == "project" || section ~ /^subproject "[^"]+"$/) && seen_key[sk]++) {
                add_error("duplicate key in [" section "]: " key)
            }
            value_for[sk] = value
            if (section == "project" && key == "version") {
                project_version = value
            }
            if (section ~ /^subproject /) {
                subprojects[section] = 1
            }
            next
        }
        { add_error("malformed line in .gitlego: " $0) }
        END {
            if (!seen_section["project"]) {
                add_error("missing [project] section in .gitlego")
            }
            if (project_version == "") {
                add_error("missing manifest schema version; expected version=" expected " in [project]")
            } else if (project_version != expected) {
                add_error("unsupported manifest schema version " project_version "; expected " expected)
            }
            for (section in subprojects) {
                repo = value_for[section SUBSEP "repo"]
                clone = value_for[section SUBSEP "clone"]
                pending = value_for[section SUBSEP "pending_branch"]
                base = value_for[section SUBSEP "base_revision"]
                pushed = value_for[section SUBSEP "pushed_commit"]
                revision = value_for[section SUBSEP "revision"]
                target = value_for[section SUBSEP "target_branch"]
                tag = value_for[section SUBSEP "tag"]
                if (repo == "") {
                    path = section
                    sub(/^subproject "/, "", path)
                    sub(/"$/, "", path)
                    add_error("subproject " path " is missing repo")
                }
                if (clone != "" && clone != "full" && clone != "partial") add_error("invalid clone mode in [" section "]: " clone)
                if (pending != "") {
                    if (target == "") add_error("pending subproject missing target_branch in [" section "]")
                    if (base == "") add_error("pending subproject missing base_revision in [" section "]")
                    if (pushed == "") add_error("pending subproject missing pushed_commit in [" section "]")
                } else if (base != "" || pushed != "") {
                    add_error("base_revision/pushed_commit require pending_branch in [" section "]")
                }
                if (tag != "" && revision == "") add_error("tag requires revision in [" section "]")
            }
        }
    ' "$MANIFEST_FILE"

    if [ -s "$errors" ]; then
        cat "$errors" >&2
        rm -f "$errors"
        exit "$EXIT_PRECONDITION"
    fi
    rm -f "$errors"
}

# Read a value from .gitlego-rc. Missing config is normal for copied manifests, so
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

# List subproject paths from manifest section headers.
manifest_subprojects() {
    [ -f "$MANIFEST_FILE" ] || return 0
    manifest_subprojects_from_file "$MANIFEST_FILE"
}

# List subproject paths from section headers in a specific manifest file.
manifest_subprojects_from_file() {
    [ -f "$1" ] || return 0
    sed -n 's/^\[subproject "\([^"]*\)"\]$/\1/p' "$1"
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

manifest_preserved_keys() {
    section=$1
    known_pattern=$2
    [ -f "$MANIFEST_FILE" ] || return 0
    awk -v section="$section" -v known_pattern="$known_pattern" '
        $0 == "[" section "]" { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && index($0, "=") > 0 {
            key = substr($0, 1, index($0, "=") - 1)
            if (key !~ known_pattern) print
        }
    ' "$MANIFEST_FILE"
}

# Rewrite the project section with the current ticket and outer branch identity.
manifest_write_project() {
    project_id=$1
    branch=$2
    ensure_manifest
    preserved=$(mktemp)
    manifest_preserved_keys "project" "^(version|id|branch)$" >"$preserved"
    manifest_remove_section "project"
    tmp=$(tmp_for "$MANIFEST_FILE")
    {
        printf '[project]\n'
        printf 'version=%s\n' "$MANIFEST_SCHEMA_VERSION"
        [ -n "$project_id" ] && printf 'id=%s\n' "$project_id"
        [ -n "$branch" ] && printf 'branch=%s\n' "$branch"
        cat "$preserved"
        printf '\n'
        sed '/^$/N;/^\n$/D' "$MANIFEST_FILE"
    } >"$tmp"
    mv "$tmp" "$MANIFEST_FILE"
    rm -f "$preserved"
}

# Write one subproject section after validating state-specific required fields.
manifest_write_subproject() {
    path=$1
    repo=$2
    state=$3
    a=${4:-}
    b=${5:-}
    c=${6:-}
    d=${7:-}
    e=${8:-}
    previous_clone=
    [ -f "$MANIFEST_FILE" ] && previous_clone=$(subproject_key "$path" clone || true)
    preserved=$(mktemp)
    [ -f "$MANIFEST_FILE" ] && manifest_preserved_keys "$(subproject_section "$path")" "^(repo|clone|target_branch|revision|tag|pending_branch|base_revision|pushed_commit|finalized_from_branch)$" >"$preserved" || : >"$preserved"

    require_value "$path" "cannot write manifest subproject with an empty path"
    require_value "$repo" "cannot write manifest subproject $path without a repository URL"
    case "$state" in
        finalized)
            require_value "$a" "cannot finalize $path without a resolved revision; fetch the subproject or pass --revision <sha>"
            clone=${d:-$previous_clone}
            ;;
        pending)
            require_value "$a" "cannot mark $path pending without a target branch"
            require_value "$b" "cannot mark $path pending without a pending branch; check out a named branch first"
            require_value "$c" "cannot mark $path pending without a base revision; fetch the subproject target branch"
            require_value "$d" "cannot mark $path pending without a pushed commit; commit work before upload"
            clone=${e:-$previous_clone}
            ;;
        tracked)
            require_value "$a" "cannot track $path without a target branch"
            clone=${c:-$previous_clone}
            ;;
        *) die "unknown manifest state for $path: $state" ;;
    esac
    validate_clone_mode "$clone" "subproject $path clone mode"

    ensure_manifest
    manifest_remove_section "subproject \"$path\""
    {
        printf '\n[subproject "%s"]\n' "$path"
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
        cat "$preserved"
    } >>"$MANIFEST_FILE"
    rm -f "$preserved"
}

# Remove one key from a subproject section, used for cleanup hints after deletion.
manifest_remove_subproject_key() {
    path=$1
    key=$2
    section=$(subproject_section "$path")
    tmp=$(tmp_for "$MANIFEST_FILE")
    awk -v section="$section" -v key="$key" '
        $0 == "[" section "]" { in_section=1; print; next }
        /^\[/ { in_section=0 }
        in_section && index($0, key "=") == 1 { next }
        { print }
    ' "$MANIFEST_FILE" >"$tmp"
    mv "$tmp" "$MANIFEST_FILE"
}

# Build the manifest section name for a subproject path.
subproject_section() {
    printf 'subproject "%s"\n' "$1"
}

# Read the configured subproject repository URL.
subproject_repo() {
    manifest_get "$(subproject_section "$1")" repo
}

# Read an arbitrary key from a subproject section.
subproject_key() {
    manifest_get "$(subproject_section "$1")" "$2"
}

# Validate a subproject clone mode. Empty means "use the default full clone".
validate_clone_mode() {
    value=$1
    context=$2
    case "$value" in
        ""|full|partial) ;;
        *) die "$context must be full or partial, got '$value'" ;;
    esac
}

# Resolve the repository-wide clone override from .gitlego-rc.
configured_clone_mode() {
    mode=$(config_get clone mode || true)
    [ -n "$mode" ] || mode=manifest
    case "$mode" in
        manifest|full|partial) printf '%s\n' "$mode" ;;
        *) die "$CONFIG_FILE [clone] mode must be manifest, full, or partial, got '$mode'" ;;
    esac
}

# Read and validate a subproject's manifest clone preference.
subproject_clone_mode() {
    path=$1
    mode=$(subproject_key "$path" clone || true)
    validate_clone_mode "$mode" "subproject $path clone mode"
    [ -n "$mode" ] || mode=full
    printf '%s\n' "$mode"
}

# Apply the global override to the subproject clone preference.
effective_clone_mode() {
    path=$1
    configured=$(configured_clone_mode)
    case "$configured" in
        manifest) subproject_clone_mode "$path" ;;
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

# Clone a subproject using the selected storage mode. Partial clone remains strict:
# if Git cannot create the requested partial checkout, callers get a hard error.
clone_subproject() {
    repo=$1
    path=$2
    mode=$3
    no_checkout=${4:-0}
    case "$mode" in
        full)
            git clone "$repo" "$path" ||
                git_error "failed to clone subproject $repo into $path; verify the repository URL and network access"
            ;;
        partial)
            if [ "$no_checkout" -eq 1 ]; then
                git clone --filter=blob:none --no-checkout "$repo" "$path" ||
                    git_error "failed to partial-clone subproject $repo into $path; verify the repository supports partial clone"
            else
                git clone --filter=blob:none "$repo" "$path" ||
                    git_error "failed to partial-clone subproject $repo into $path; verify the repository supports partial clone"
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
    require_value "$target" "cannot sync tracked subproject $path without a target branch"
    if git -C "$path" show-ref --verify --quiet "refs/heads/$target"; then
        git -C "$path" checkout "$target" || die "failed to check out target branch $target in $path"
    elif git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1; then
        git -C "$path" checkout -b "$target" "origin/$target" ||
            die "failed to create target branch $target from origin/$target in $path"
    else
        die "target branch $target not found for $path; fetch the subproject or fix target_branch"
    fi
}

# Read porcelain status with a tool-level error if Git cannot inspect the repo.
repo_status_porcelain() {
    repo=$1
    context=$2
    status=$(git -C "$repo" status --porcelain 2>/dev/null) ||
        die "$context: cannot read Git status in $repo; verify the checkout is not corrupted"
    printf '%s\n' "$status" | sed '/^?? \.gitlego\.lock\//d; /^?? \.gitlego\.lock$/d'
}

# Detect untracked files for start --discard-dirty validation.
repo_has_untracked() {
    repo_status_porcelain "$1" "cannot inspect untracked files" | grep '^?? ' >/dev/null 2>&1
}

# Detect any dirty state for preflight and status reporting.
repo_has_dirty() {
    [ -n "$(repo_status_porcelain "$1" "cannot inspect dirty state")" ]
}

path_is_manifest_subproject_or_child() {
    candidate=$1
    paths=$(mktemp)
    manifest_subprojects >"$paths"
    while IFS= read -r managed; do
        [ -n "$managed" ] || continue
        case "$candidate" in
            "$managed"|"$managed"/*) rm -f "$paths"; return 0 ;;
        esac
    done <"$paths"
    rm -f "$paths"
    return 1
}

unmanaged_subprojects() {
    [ -f "$MANIFEST_FILE" ] || return 0
    find . \( -type d -o -type f \) -name .git 2>/dev/null | while IFS= read -r gitpath; do
        repo=$(dirname -- "$gitpath")
        repo=$(normalize_path "$repo")
        repo=${repo#./}
        [ "$repo" = "." ] && continue
        [ -n "$repo" ] || continue
        if path_is_manifest_subproject_or_child "$repo"; then
            continue
        fi
        printf '%s\n' "$repo"
    done | sort -u
}

subproject_manifest_mismatch() {
    path=$1
    revision=$(subproject_key "$path" revision || true)
    [ -n "$revision" ] || return 1
    [ -d "$path/.git" ] || return 1
    head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
    expected=$(git -C "$path" rev-parse --verify "$revision^{commit}" 2>/dev/null || true)
    [ -n "$head" ] && [ -n "$expected" ] && [ "$head" != "$expected" ]
}

status_code_for_subproject() {
    path=$1
    pending=$(subproject_key "$path" pending_branch || true)
    if [ -n "$pending" ] || subproject_manifest_mismatch "$path"; then
        printf 'C\n'
    else
        printf 'D\n'
    fi
}

status_state_for_code() {
    case "$1" in
        C) printf 'composite\n' ;;
        *) printf 'dirty\n' ;;
    esac
}

# Return the untracked local materialization state file for Git workspaces.
# Copied-manifest folders without an outer .git still sync normally, but cannot
# remember stale paths until they become a Git workspace.
materialized_state_file() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    state_dir=$(git rev-parse --git-path git-lego 2>/dev/null) || return 1
    printf '%s/subprojects\n' "$state_dir"
}

# Write the currently materialized manifest subprojects after a successful sync.
write_materialized_state() {
    state_file=$(materialized_state_file 2>/dev/null || true)
    [ -n "$state_file" ] || return 0
    state_dir=$(dirname -- "$state_file")
    mkdir -p "$state_dir" || die "cannot create git-lego state directory $state_dir"
    tmp=$(mktemp "$state_dir/subprojects.tmp.XXXXXX") ||
        die "cannot create temporary git-lego state file"
    current_pairs=$(mktemp "$state_dir/subprojects.current.XXXXXX") ||
        die "cannot create temporary git-lego state file"
    manifest_pairs_file "$current_pairs"
    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -d "$path/.git" ] || continue
        repo=$(subproject_repo "$path" || true)
        [ -n "$repo" ] || continue
        printf '%s\t%s\n' "$path" "$repo"
    done >"$tmp"
    if [ -f "$state_file" ]; then
        while IFS='	' read -r old_path old_repo; do
            [ -n "$old_path" ] || continue
            [ -n "$old_repo" ] || continue
            pair_path_exists "$current_pairs" "$old_path" && continue
            [ -e "$old_path" ] || continue
            printf '%s\t%s\n' "$old_path" "$old_repo" >>"$tmp"
        done <"$state_file"
    fi
    rm -f "$current_pairs"
    mv "$tmp" "$state_file"
}

# Read current manifest subproject path/repo pairs into a tab-separated file.
manifest_pairs_file() {
    out=$1
    : >"$out"
    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        repo=$(subproject_repo "$path" || true)
        [ -n "$repo" ] || continue
        printf '%s\t%s\n' "$path" "$repo" >>"$out"
    done
}

pair_path_exists() {
    pairs=$1
    path=$2
    awk -F '	' -v path="$path" '$1 == path { found=1 } END { exit !found }' "$pairs"
}

# Guard stale cleanup paths. The state file is local, but deletion still stays
# relative to the project root and avoids parent traversal.
safe_stale_path() {
    path=$1
    case "$path" in
        ""|"."|".."|/*|*":*"|../*|*/../*|*"/.."|*//*) return 1 ;;
        *) return 0 ;;
    esac
}

count_stale_repo_paths() {
    previous=$1
    current=$2
    repo=$3
    count=0
    while IFS='	' read -r path old_repo; do
        [ -n "$path" ] || continue
        [ "$old_repo" = "$repo" ] || continue
        pair_path_exists "$current" "$path" && continue
        [ -e "$path" ] || continue
        count=$((count + 1))
    done <"$previous"
    printf '%s\n' "$count"
}

missing_manifest_paths_for_repo() {
    current=$1
    repo=$2
    while IFS='	' read -r path current_repo; do
        [ -n "$path" ] || continue
        [ "$current_repo" = "$repo" ] || continue
        [ ! -d "$path/.git" ] || continue
        printf '%s\n' "$path"
    done <"$current"
}

first_line() {
    sed -n '1p' "$1"
}

line_count() {
    sed '/^$/d' "$1" | wc -l | tr -d ' '
}

# Return an empty string when a stale subproject is safe to delete or move.
stale_subproject_safety_reason() {
    path=$1
    [ -d "$path/.git" ] || {
        printf 'is not a Git checkout'
        return 0
    }
    dirty=$(repo_status_porcelain "$path" "cannot inspect stale subproject $path")
    [ -z "$dirty" ] || {
        printf 'has local changes or untracked files'
        return 0
    }
    branches=$(mktemp)
    git -C "$path" for-each-ref --format='%(refname:short) %(objectname)' refs/heads >"$branches" ||
        die "cannot inspect local branches in stale subproject $path"
    while IFS=' ' read -r branch sha; do
        [ -n "$branch" ] || continue
        if ! git -C "$path" branch -r --contains "$sha" 2>/dev/null | grep -v ' -> ' | grep . >/dev/null 2>&1; then
            rm -f "$branches"
            printf 'has local-only branch tip %s' "$branch"
            return 0
        fi
    done <"$branches"
    rm -f "$branches"
}

remove_stale_subproject() {
    path=$1
    rm -rf -- "$path" || die "failed to remove stale subproject $path"
}

move_stale_subproject() {
    old_path=$1
    new_path=$2
    new_parent=$(dirname -- "$new_path")
    mkdir -p "$new_parent" || die "failed to create parent directory $new_parent"
    mv -- "$old_path" "$new_path" || die "failed to move stale subproject $old_path to $new_path"
}

# Reconcile paths remembered from the previous sync with the current manifest.
reconcile_stale_subprojects() {
    prune=${1:-0}
    state_file=$(materialized_state_file 2>/dev/null || true)
    [ -n "$state_file" ] || return 0
    [ -f "$state_file" ] || return 0

    current_pairs=$(tmp_for "$MANIFEST_FILE.current_subprojects")
    candidates=$(tmp_for "$MANIFEST_FILE.move_candidates")
    manifest_pairs_file "$current_pairs"

    while IFS='	' read -r old_path old_repo; do
        [ -n "$old_path" ] || continue
        [ -n "$old_repo" ] || continue
        pair_path_exists "$current_pairs" "$old_path" && continue
        [ -e "$old_path" ] || continue

        if ! safe_stale_path "$old_path"; then
            warn "stale subproject path $old_path is not a safe relative path; leaving it in place for manual review"
            continue
        fi
        if [ ! -d "$old_path/.git" ]; then
            warn "stale subproject $old_path is no longer in $MANIFEST_FILE but is not a Git checkout; leaving it in place for manual review"
            continue
        fi

        missing_manifest_paths_for_repo "$current_pairs" "$old_repo" >"$candidates"
        candidate_count=$(line_count "$candidates")
        stale_count=$(count_stale_repo_paths "$state_file" "$current_pairs" "$old_repo")
        new_path=
        if [ "$candidate_count" = 1 ] && [ "$stale_count" = 1 ]; then
            new_path=$(first_line "$candidates")
        elif [ "$candidate_count" -gt 1 ] || [ "$stale_count" -gt 1 ]; then
            warn "stale subproject $old_path could match multiple paths for repo $old_repo; leaving it in place for manual review"
            continue
        fi

        reason=$(stale_subproject_safety_reason "$old_path")
        if [ -n "$reason" ]; then
            if [ "$prune" -eq 1 ]; then
                remove_stale_subproject "$old_path"
                notice "removed stale subproject $old_path with --prune despite local state: $reason"
                continue
            fi
            warn "stale subproject $old_path $reason; leaving it in place. Review it, then commit/stash/discard the work, push/delete local-only branches, or run git-lego sync --prune to remove it."
            continue
        fi

        if [ -n "$new_path" ]; then
            if [ -e "$new_path" ]; then
                warn "stale subproject $old_path appears to have moved to $new_path, but the destination exists; leaving it in place for manual review"
                continue
            fi
            if ! safe_stale_path "$new_path"; then
                warn "new subproject path $new_path is not a safe relative path; leaving stale subproject $old_path in place for manual review"
                continue
            fi
            move_stale_subproject "$old_path" "$new_path"
            notice "moved stale subproject $old_path to $new_path"
        else
            remove_stale_subproject "$old_path"
            notice "removed stale subproject $old_path because it is no longer in $MANIFEST_FILE"
        fi
    done <"$state_file"

    rm -f "$current_pairs" "$candidates"
}

# List the outer repository and all checked-out subprojects for workspace-wide scans.
list_repos() {
    printf '.\n'
    manifest_subprojects | while IFS= read -r path; do
        [ -d "$path/.git" ] && printf '%s\n' "$path"
    done
}

# Return a stable absolute path for recursion and duplicate detection.
abs_path_for() {
    path=$1
    (CDPATH= cd -- "$path" && pwd)
}

# Join project-relative labels without turning the root label "." into a prefix.
join_project_label() {
    base=$1
    child=$2
    if [ "$base" = "." ] || [ -z "$base" ]; then
        printf '%s\n' "$child"
    else
        printf '%s/%s\n' "$base" "$child"
    fi
}

# Report checked-out subprojects that are themselves project roots.
notice_nested_projects() {
    ensure_manifest
    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            notice "nested project found at $path; rerun with --recursive to include it"
        fi
    done
}

subproject_would_snapshot() {
    path=$1
    [ -d "$path/.git" ] || return 1
    repo_has_dirty "$path" && return 1
    target=$(subproject_key "$path" target_branch || true)
    [ -n "$target" ] || target=$(default_target_branch "$path")
    mod_branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    [ -n "$mod_branch" ] || return 1
    base_ref=
    if git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1; then
        base_ref=origin/$target
    elif git -C "$path" rev-parse --verify "$target^{commit}" >/dev/null 2>&1; then
        base_ref=$target
    else
        return 1
    fi
    ahead=$(git -C "$path" rev-list --count "$base_ref..HEAD" 2>/dev/null || printf '0')
    [ "$ahead" -gt 0 ] 2>/dev/null
}

project_would_snapshot() {
    ensure_manifest
    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        if subproject_would_snapshot "$path"; then
            printf 'yes\n'
            break
        fi
    done | grep '^yes$' >/dev/null 2>&1
}

nested_snapshot_candidates() {
    label=$1
    out=$2
    visited=$3
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_project_label "$label" "$path")
            (
                cd "$path" || exit 1
                if project_would_snapshot; then
                    printf '%s\n' "$child_label" >>"$out"
                fi
                nested_snapshot_candidates "$child_label" "$out" "$visited"
            )
        fi
    done
}

notice_nested_snapshot_candidates() {
    candidates=$(mktemp)
    visited=$(mktemp)
    : >"$candidates"
    : >"$visited"
    nested_snapshot_candidates "." "$candidates" "$visited" || true
    if [ -s "$candidates" ]; then
        count=$(sed '/^$/d' "$candidates" | wc -l | tr -d ' ')
        notice "$count nested project(s) have committed work not covered by this snapshot:"
        while IFS= read -r path; do
            [ -n "$path" ] && printf '  %s\n' "$path" >&2
        done <"$candidates"
        printf '  run git-lego status --recursive to inspect them, or git-lego snapshot --recursive to include them\n' >&2
    else
        notice_nested_projects
    fi
    rm -f "$candidates" "$visited"
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

# Parse read-only commands that support recursive, porcelain, and JSON output.
parse_recursive_output() {
    command=$1
    shift
    PARSED_RECURSIVE=0
    PARSED_PORCELAIN=0
    PARSED_JSON=0
    PARSED_JSON_PRETTY=0
    PARSED_EXIT_CODE=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --recursive) PARSED_RECURSIVE=1 ;;
            --porcelain) PARSED_PORCELAIN=1 ;;
            --json) PARSED_JSON=1 ;;
            --json-pretty) PARSED_JSON=1; PARSED_JSON_PRETTY=1 ;;
            --exit-code)
                [ "$command" = status ] || usage_error "--exit-code is only supported by status"
                PARSED_EXIT_CODE=1
                ;;
            *) usage_error "unknown $command option: $1" ;;
        esac
        shift
    done
    if [ "$PARSED_PORCELAIN" -eq 1 ] && [ "$PARSED_JSON" -eq 1 ]; then
        usage_error "$command cannot combine --porcelain with --json/--json-pretty"
    fi
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
        git -C "$path" stash push -u -m "git-lego start preflight" >/dev/null
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

add_base_override() {
    value=$1
    case "$value" in
        *=*) ;;
        *) usage_error "--base requires <subproject>=<ref>" ;;
    esac
    path_arg=${value%%=*}
    reject_backslash_path "$path_arg"
    path=$(normalize_path "$path_arg")
    ref=${value#*=}
    [ -n "$path" ] || usage_error "--base requires a subproject path"
    [ -n "$ref" ] || usage_error "--base requires a ref"
    [ -n "$GIT_LEGO_BASE_OVERRIDES" ] || GIT_LEGO_BASE_OVERRIDES=$(tmp_for "$MANIFEST_FILE.base_overrides")
    printf '%s\t%s\n' "$path" "$ref" >>"$GIT_LEGO_BASE_OVERRIDES"
}

base_override_for() {
    path=$1
    [ -n "$GIT_LEGO_BASE_OVERRIDES" ] || return 1
    [ -f "$GIT_LEGO_BASE_OVERRIDES" ] || return 1
    awk -F '	' -v path="$path" '$1 == path { value=$2 } END { if (value != "") print value; else exit 1 }' "$GIT_LEGO_BASE_OVERRIDES"
}

clear_base_overrides() {
    [ -z "$GIT_LEGO_BASE_OVERRIDES" ] || rm -f "$GIT_LEGO_BASE_OVERRIDES"
    GIT_LEGO_BASE_OVERRIDES=
    GIT_LEGO_NO_FETCH=0
}

ensure_gitignore_entry() {
    path=$1
    [ -f .gitignore ] || : >.gitignore
    if awk -v path="$path" '
        {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line == path || line == path "/") found=1
        }
        END { exit !found }
    ' .gitignore; then
        return 0
    fi
    if [ -s .gitignore ] && [ "$(tail -c 1 .gitignore | wc -l | tr -d ' ')" = "0" ]; then
        printf '\n' >>.gitignore
    fi
    printf '%s/\n' "$path" >>.gitignore
}

ensure_gitignore_line() {
    line_to_add=$1
    [ -f .gitignore ] || : >.gitignore
    if awk -v wanted="$line_to_add" '
        {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line == wanted) found=1
        }
        END { exit !found }
    ' .gitignore; then
        return 0
    fi
    if [ -s .gitignore ] && [ "$(tail -c 1 .gitignore | wc -l | tr -d ' ')" = "0" ]; then
        printf '\n' >>.gitignore
    fi
    printf '%s\n' "$line_to_add" >>.gitignore
}

remove_gitignore_entry() {
    path=$1
    [ -f .gitignore ] || return 0
    tmp=$(tmp_for .gitignore)
    awk -v path="$path" '
        {
            line=$0
            trimmed=line
            sub(/^[[:space:]]+/, "", trimmed)
            sub(/[[:space:]]+$/, "", trimmed)
            if (trimmed == path || trimmed == path "/") next
            print line
        }
    ' .gitignore >"$tmp"
    mv "$tmp" .gitignore
}

ensure_gitignore_hygiene() {
    ensure_gitignore_line "$GITIGNORE_GIT_DIR_GUARD_ONE"
    ensure_gitignore_line "$GITIGNORE_GIT_DIR_GUARD_TWO"
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
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    ensure_gitattributes_guard
    [ -f .gitignore ] || : >.gitignore
    ensure_gitignore_hygiene
    [ "$create_rc" -eq 0 ] || ensure_config
    printf 'Initialized git-lego workspace.\n'
}

# Add a subproject checkout and record its repo, target branch, and current revision.
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
    [ $# -eq 2 ] || die "usage: git-lego add [--clone <full|partial>] <repo> <path>"
    repo=$1
    reject_backslash_path "$2"
    path=$(normalize_path "$2")
    ensure_outer_repo
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$path"
    project_invocation_warnings

    if [ ! -d "$path/.git" ]; then
        [ ! -e "$path" ] || die "$path exists but is not a Git repository"
        mode=$clone_mode
        if [ -z "$mode" ] && [ "$(configured_clone_mode)" = partial ]; then
            mode=partial
        fi
        [ -n "$mode" ] || mode=full
        clone_subproject "$repo" "$path" "$mode" 0
    fi

    ensure_gitignore_hygiene
    ensure_gitignore_entry "$path"

    [ "$GIT_LEGO_DRY_RUN" -eq 1 ] || fetch_quiet "$path"
    target=$(default_target_branch "$path")
    revision=$(resolve_head_commit "$path" "cannot add subproject $path")
    manifest_write_subproject "$path" "$repo" tracked "$target" "$revision" "$clone_mode"
    install_hooks_in_repo_if_project_managed "$path"
    write_materialized_state
    printf 'Added subproject %s.\n' "$path"
}

subproject_exists_in_manifest() {
    path=$1
    [ -n "$(subproject_repo "$path" || true)" ]
}

current_branch_safety_reason() {
    path=$1
    target=$2
    [ -d "$path/.git" ] || {
        [ -e "$path" ] && printf '%s is not a Git checkout' "$path"
        return 0
    }
    dirty=$(repo_status_porcelain "$path" "cannot inspect subproject $path")
    if [ -n "$dirty" ]; then
        printf '%s has local changes or untracked files' "$path"
        return 0
    fi
    current=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    [ -n "$current" ] || return 0
    upstream=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
    base_ref=
    if [ -n "$upstream" ] && git -C "$path" rev-parse --verify "$upstream^{commit}" >/dev/null 2>&1; then
        base_ref=$upstream
    elif [ -n "$target" ] && git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1; then
        base_ref=origin/$target
    elif [ -n "$target" ] && git -C "$path" rev-parse --verify "$target^{commit}" >/dev/null 2>&1; then
        base_ref=$target
    fi
    if [ -z "$base_ref" ]; then
        case "$current" in
            main|master) return 0 ;;
            *) printf '%s has current branch %s without an upstream or target comparison ref' "$path" "$current"; return 0 ;;
        esac
    fi
    ahead=$(git -C "$path" rev-list --count "$base_ref..HEAD" 2>/dev/null || printf '0')
    if [ "$ahead" -gt 0 ] 2>/dev/null; then
        printf '%s has %s commit(s) ahead of %s' "$path" "$ahead" "$base_ref"
    fi
}

manifest_rename_subproject_section() {
    old_path=$1
    new_path=$2
    tmp=$(tmp_for "$MANIFEST_FILE")
    awk -v old="subproject \"$old_path\"" -v new="subproject \"$new_path\"" '
        $0 == "[" old "]" { print "[" new "]"; next }
        { print }
    ' "$MANIFEST_FILE" >"$tmp"
    mv "$tmp" "$MANIFEST_FILE"
}

manifest_set_subproject_key() {
    path=$1
    key=$2
    value=$3
    section=$(subproject_section "$path")
    tmp=$(tmp_for "$MANIFEST_FILE")
    awk -v section="$section" -v key="$key" -v value="$value" '
        $0 == "[" section "]" { in_section=1; wrote=0; print; next }
        /^\[/ {
            if (in_section && !wrote) print key "=" value
            in_section=0
        }
        in_section && index($0, key "=") == 1 {
            if (!wrote) print key "=" value
            wrote=1
            next
        }
        { print }
        END {
            if (in_section && !wrote) print key "=" value
        }
    ' "$MANIFEST_FILE" >"$tmp"
    mv "$tmp" "$MANIFEST_FILE"
}

remote_head_commit_for_url() {
    repo=$1
    git ls-remote "$repo" HEAD 2>/dev/null | awk 'NR == 1 { print $1 }'
}

cmd_remove() {
    force=0
    keep_files=0
    path_arg=
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1; shift ;;
            --keep-files) keep_files=1; shift ;;
            --*) usage_error "unknown remove option: $1" ;;
            *)
                [ -z "$path_arg" ] || usage_error "usage: git-lego remove <path> [--force] [--keep-files]"
                path_arg=$1
                shift
                ;;
        esac
    done
    [ -n "$path_arg" ] || usage_error "usage: git-lego remove <path> [--force] [--keep-files]"
    reject_backslash_path "$path_arg"
    path=$(normalize_path "$path_arg")
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$path"
    repo=$(subproject_repo "$path" || true)
    [ -n "$repo" ] || precondition_error "$path is not a tracked subproject in $MANIFEST_FILE"
    target=$(subproject_key "$path" target_branch || true)
    if [ "$force" -eq 0 ]; then
        reason=$(current_branch_safety_reason "$path" "$target")
        [ -z "$reason" ] || precondition_error "$reason; rerun with --force to remove anyway"
    fi
    manifest_remove_section "$(subproject_section "$path")"
    if [ "$keep_files" -eq 1 ]; then
        printf 'Removed subproject %s from %s; kept files and kept %s/ ignored.\n' "$path" "$MANIFEST_FILE" "$path"
    else
        remove_gitignore_entry "$path"
        if [ -e "$path" ]; then
            rm -rf -- "$path" || git_error "failed to remove subproject directory $path"
        fi
        printf 'Removed subproject %s.\n' "$path"
    fi
    write_materialized_state
}

cmd_mv() {
    force=0
    old_arg=
    new_arg=
    if [ "${1:-}" = "--url" ]; then
        [ $# -eq 3 ] || usage_error "usage: git-lego mv --url <new-url> <path>"
        new_url=$2
        reject_backslash_path "$3"
        path=$(normalize_path "$3")
        acquire_manifest_lock
        ensure_manifest
        validate_manifest_schema
        assert_path_not_inside_nested_project "$path"
        repo=$(subproject_repo "$path" || true)
        [ -n "$repo" ] || precondition_error "$path is not a tracked subproject in $MANIFEST_FILE"
        if [ -d "$path/.git" ]; then
            current_head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
            remote_head=$(remote_head_commit_for_url "$new_url" || true)
            if [ -n "$current_head" ] && [ -n "$remote_head" ] && [ "$current_head" != "$remote_head" ]; then
                warn "new URL HEAD differs from current checkout for $path"
            fi
        fi
        manifest_set_subproject_key "$path" repo "$new_url"
        printf 'Updated subproject %s URL.\n' "$path"
        return 0
    fi
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1; shift ;;
            --*) usage_error "unknown mv option: $1" ;;
            *)
                if [ -z "${old_arg:-}" ]; then
                    old_arg=$1
                elif [ -z "${new_arg:-}" ]; then
                    new_arg=$1
                else
                    usage_error "usage: git-lego mv <old-path> <new-path> [--force]"
                fi
                shift
                ;;
        esac
    done
    [ -n "${old_arg:-}" ] && [ -n "${new_arg:-}" ] || usage_error "usage: git-lego mv <old-path> <new-path> [--force]"
    reject_backslash_path "$old_arg"
    reject_backslash_path "$new_arg"
    old_path=$(normalize_path "$old_arg")
    new_path=$(normalize_path "$new_arg")
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$old_path"
    assert_path_not_inside_nested_project "$new_path"
    repo=$(subproject_repo "$old_path" || true)
    [ -n "$repo" ] || precondition_error "$old_path is not a tracked subproject in $MANIFEST_FILE"
    [ -z "$(subproject_repo "$new_path" || true)" ] || precondition_error "$new_path is already a tracked subproject"
    [ ! -e "$new_path" ] || precondition_error "$new_path already exists"
    target=$(subproject_key "$old_path" target_branch || true)
    if [ "$force" -eq 0 ]; then
        reason=$(current_branch_safety_reason "$old_path" "$target")
        [ -z "$reason" ] || precondition_error "$reason; rerun with --force to move anyway"
    fi
    parent=$(dirname -- "$new_path")
    [ "$parent" = "." ] || mkdir -p "$parent" || git_error "failed to create parent directory $parent"
    if [ -e "$old_path" ]; then
        mv -- "$old_path" "$new_path" || git_error "failed to move $old_path to $new_path"
    fi
    manifest_rename_subproject_section "$old_path" "$new_path"
    remove_gitignore_entry "$old_path"
    ensure_gitignore_hygiene
    ensure_gitignore_entry "$new_path"
    write_materialized_state
    printf 'Moved subproject %s to %s.\n' "$old_path" "$new_path"
}

cmd_clone() {
    no_sync=0
    depth=
    branch=
    single_branch=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-sync) no_sync=1; shift ;;
            --depth)
                [ $# -ge 2 ] || usage_error "--depth requires a value"
                depth=$2
                shift 2
                ;;
            --branch|-b)
                [ $# -ge 2 ] || usage_error "$1 requires a value"
                branch=$2
                shift 2
                ;;
            --single-branch) single_branch=1; shift ;;
            --*) usage_error "unknown clone option: $1" ;;
            *) break ;;
        esac
    done
    [ $# -ge 1 ] && [ $# -le 2 ] || usage_error "usage: git-lego clone <outer-repo-url> [target-dir]"
    outer_repo=$1
    target_dir=${2:-}
    set -- git clone
    if [ -n "$depth" ]; then
        set -- "$@" --depth "$depth"
    fi
    if [ -n "$branch" ]; then
        set -- "$@" --branch "$branch"
    fi
    if [ "$single_branch" -eq 1 ]; then
        set -- "$@" --single-branch
    fi
    if [ -n "$target_dir" ]; then
        "$@" "$outer_repo" "$target_dir" || git_error "failed to clone outer repository $outer_repo"
    else
        "$@" "$outer_repo" || git_error "failed to clone outer repository $outer_repo"
        target_dir=$(basename -- "$outer_repo")
        target_dir=${target_dir%.git}
    fi
    if [ "$no_sync" -eq 1 ]; then
        printf 'Cloned %s.\n' "$target_dir"
        return 0
    fi
    if [ -f "$target_dir/$MANIFEST_FILE" ]; then
        (cd "$target_dir" && git_lego_main sync) || return $?
    else
        notice "cloned repository has no $MANIFEST_FILE; skipped sync"
    fi
}

path_in_only_list() {
    path=$1
    list=$2
    [ -n "$list" ] || return 0
    old_ifs=$IFS
    IFS=,
    for item in $list; do
        reject_backslash_path "$item"
        item=$(normalize_path "$item")
        if [ "$item" = "$path" ]; then
            IFS=$old_ifs
            return 0
        fi
    done
    IFS=$old_ifs
    return 1
}

validate_only_list_boundaries() {
    list=$1
    [ -n "$list" ] || return 0
    old_ifs=$IFS
    IFS=,
    for item in $list; do
        reject_backslash_path "$item"
        item=$(normalize_path "$item")
        [ -n "$item" ] || continue
        assert_path_not_inside_nested_project "$item"
    done
    IFS=$old_ifs
}

cmd_freeze() {
    force=0
    dry_run=0
    only=
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1; shift ;;
            --dry-run) dry_run=1; shift ;;
            --only)
                [ $# -ge 2 ] || usage_error "--only requires a value"
                only=$2
                shift 2
                ;;
            --*) usage_error "unknown freeze option: $1" ;;
            *) usage_error "unknown freeze argument: $1" ;;
        esac
    done
    [ "$dry_run" -eq 1 ] || acquire_manifest_lock
    validate_only_list_boundaries "$only"
    frozen=0
    pinned=0
    skipped=0
    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.freeze")
    manifest_subprojects >"$subprojects_tmp"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        path_in_only_list "$path" "$only" || continue
        repo=$(subproject_repo "$path" || true)
        [ -n "$repo" ] || continue
        pending=$(subproject_key "$path" pending_branch || true)
        revision=$(subproject_key "$path" revision || true)
        if [ -n "$pending" ]; then
            pinned=$((pinned + 1))
            continue
        fi
        if [ ! -d "$path/.git" ]; then
            warn "skipping missing subproject $path during freeze"
            skipped=$((skipped + 1))
            continue
        fi
        head=$(resolve_head_commit "$path" "cannot freeze $path")
        if [ -n "$revision" ]; then
            recorded=$(git -C "$path" rev-parse --verify "$revision^{commit}" 2>/dev/null || true)
            if [ -n "$recorded" ] && [ "$recorded" = "$head" ]; then
                pinned=$((pinned + 1))
                continue
            fi
        fi
        target=$(subproject_key "$path" target_branch || true)
        [ -n "$target" ] || target=$(default_target_branch "$path")
        reason=$(current_branch_safety_reason "$path" "$target")
        if [ -n "$reason" ]; then
            if [ "$force" -eq 0 ]; then
                precondition_error "$reason; rerun with --force to freeze anyway"
            fi
            warn "$reason; freezing current HEAD because --force was used"
        fi
        if [ "$dry_run" -eq 1 ]; then
            printf 'Would freeze %s at %.12s.\n' "$path" "$head"
        else
            manifest_write_subproject "$path" "$repo" tracked "$target" "$head"
            printf 'Frozen %s at %.12s.\n' "$path" "$head"
        fi
        frozen=$((frozen + 1))
    done <"$subprojects_tmp"
    rm -f "$subprojects_tmp"
    printf 'Freeze summary: %s frozen, %s already pinned, %s skipped.\n' "$frozen" "$pinned" "$skipped"
}

# Print a compact view of the current project and subproject state for humans.
status_current() {
    ensure_manifest
    branch=$(current_branch)
    project_id=$(manifest_get project id || true)
    project_branch=$(manifest_get project branch || true)

    printf 'outer branch: %s\n' "$branch"
    [ -n "$project_id" ] && printf 'project id: %s\n' "$project_id"
    [ -n "$project_branch" ] && printf 'project branch: %s\n' "$project_branch"
    printf 'subprojects:\n'

    manifest_subprojects | while IFS= read -r path; do
        pending=$(subproject_key "$path" pending_branch || true)
        revision=$(subproject_key "$path" revision || true)
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
    unmanaged=$(unmanaged_subprojects)
    if [ -n "$unmanaged" ]; then
        printf 'unmanaged subprojects:\n'
        printf '%s\n' "$unmanaged" | while IFS= read -r path; do
            [ -n "$path" ] && printf '  %s: unmanaged nested Git repository\n' "$path"
        done
    fi
}

# Print dirty or incomplete state in a stable, fixed-column script format.
status_porcelain_current() {
    label=$1

    repo_status_porcelain . "cannot inspect dirty state" | while IFS= read -r line; do
        [ -n "$line" ] || continue
        printf 'D\t%s\tdirty\t-\t-\t-\t%s\n' "$label" "$line"
    done

    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        subproject_label=$(join_project_label "$label" "$path")
        if [ ! -d "$path/.git" ]; then
            printf 'M\t%s\tmissing\t-\t-\t-\tcheckout-missing\n' "$subproject_label"
            continue
        fi
        pending=$(subproject_key "$path" pending_branch || true)
        code=$(status_code_for_subproject "$path")
        state=$(status_state_for_code "$code")
        dirty_status=$(repo_status_porcelain "$path" "cannot inspect dirty state")
        printf '%s\n' "$dirty_status" | while IFS= read -r line; do
            [ -n "$line" ] || continue
            printf '%s\t%s\t%s\t-\t-\t-\t%s\n' "$code" "$subproject_label" "$state" "$line"
        done
        if [ -n "$pending" ] && [ -n "$dirty_status" ]; then
            printf 'C\t%s\tcomposite\t-\t-\t-\tdirty-and-pending\n' "$subproject_label"
        fi
        if subproject_manifest_mismatch "$path"; then
            printf 'C\t%s\tcomposite\t-\t-\t-\thead-differs-from-manifest\n' "$subproject_label"
        fi
    done
    unmanaged_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        unmanaged_label=$(join_project_label "$label" "$path")
        printf 'U\t%s\tunmanaged\t-\t-\t-\tnested-git-repo\n' "$unmanaged_label"
    done
}

# Recursively print status for the current project and nested project roots.
status_recursive() {
    label=$1
    visited=$2
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    printf 'project: %s\n' "$label"
    status_current

    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_project_label "$label" "$path")
            (
                cd "$path" || exit 1
                printf '\n'
                status_recursive "$child_label" "$visited"
            )
        fi
    done
}

# Recursively print porcelain status for the current project and nested project roots.
status_porcelain_recursive() {
    label=$1
    visited=$2
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    status_porcelain_current "$label"

    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_project_label "$label" "$path")
            (
                cd "$path" || exit 1
                status_porcelain_recursive "$child_label" "$visited"
            )
        fi
    done
}

# Print project state, optionally including nested projects.
cmd_status() {
    parse_recursive_output status "$@"
    recursive=$PARSED_RECURSIVE
    porcelain=$PARSED_PORCELAIN
    json=$PARSED_JSON
    json_pretty=$PARSED_JSON_PRETTY
    exit_code=$PARSED_EXIT_CODE
    if [ "$porcelain" -eq 1 ]; then
        if [ "$recursive" -eq 1 ]; then
            visited=$(mktemp)
            : >"$visited"
            status_porcelain_recursive "." "$visited"
            rm -f "$visited"
        else
            status_porcelain_current "."
        fi
    elif [ "$json" -eq 1 ]; then
        rows=$(mktemp)
        errors=$(mktemp)
        warnings=$(mktemp)
        : >"$errors"
        : >"$warnings"
        if [ "$recursive" -eq 1 ]; then
            visited=$(mktemp)
            : >"$visited"
            status_porcelain_recursive "." "$visited" >"$rows"
            rm -f "$visited"
        else
            status_porcelain_current "." >"$rows"
        fi
        [ -s "$rows" ] && ok=0 || ok=1
        emit_json_result status "$recursive" "$ok" "$rows" "$errors" "$warnings" "$json_pretty"
        rm -f "$rows" "$errors" "$warnings"
    elif [ "$recursive" -eq 1 ]; then
        visited=$(mktemp)
        : >"$visited"
        status_recursive "." "$visited"
        rm -f "$visited"
    else
        status_current
        notice_nested_projects
    fi
    if [ "$exit_code" -eq 1 ]; then
        rows=$(mktemp)
        if [ "$recursive" -eq 1 ]; then
            visited=$(mktemp)
            : >"$visited"
            status_porcelain_recursive "." "$visited" >"$rows"
            rm -f "$visited"
        else
            status_porcelain_current "." >"$rows"
        fi
        [ ! -s "$rows" ] || { rm -f "$rows"; return "$EXIT_ISSUES"; }
        rm -f "$rows"
    fi
}

# Pick the branch used for remote query checks. Existing finalized
# entries may not record target_branch, so follow the normal target inference.
outdated_target_branch() {
    path=$1
    target=$(subproject_key "$path" target_branch || true)
    if [ -n "$target" ]; then
        printf '%s\n' "$target"
    elif [ -d "$path/.git" ]; then
        default_target_branch "$path"
    else
        printf 'main\n'
    fi
}

# Query a subproject remote without updating local refs.
remote_branch_commit() {
    repo=$1
    target=$2
    out=$3
    git ls-remote "$repo" "refs/heads/$target" >"$out" 2>/dev/null || return 1
    awk 'NR == 1 { print $1 }' "$out"
}

remote_tag_commit() {
    repo=$1
    tag=$2
    out=$3
    git ls-remote "$repo" "refs/tags/$tag" "refs/tags/$tag^{}" >"$out" 2>/dev/null || return 1
    awk '
        $2 ~ /\^\{\}$/ { peeled=$1 }
        $2 !~ /\^\{\}$/ && commit == "" { commit=$1 }
        END {
            if (peeled != "") print peeled
            else if (commit != "") print commit
            else exit 1
        }
    ' "$out"
}

# Report whether subproject remotes have target-branch commits newer than .gitlego.
outdated_current() {
    ensure_manifest
    errors=$(tmp_for "$MANIFEST_FILE.outdated_errors")
    : >"$errors"

    printf 'subprojects:\n'
    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        repo=$(subproject_repo "$path" || true)
        if [ -z "$repo" ]; then
            printf '  %s: error missing repo\n' "$path"
            printf 'Error: %s: missing repo in %s\n' "$path" "$MANIFEST_FILE" >>"$errors"
            continue
        fi

        pending=$(subproject_key "$path" pending_branch || true)
        if [ -n "$pending" ]; then
            printf '  %s: pending %s\n' "$path" "$pending"
            continue
        fi

        target=$(outdated_target_branch "$path")
        remote_tmp=$(tmp_for "$MANIFEST_FILE.outdated_remote")
        remote_commit=$(remote_branch_commit "$repo" "$target" "$remote_tmp" || true)
        rm -f "$remote_tmp"
        if [ -z "$remote_commit" ]; then
            if git ls-remote "$repo" >/dev/null 2>&1; then
                printf '  %s: remote branch missing %s\n' "$path" "$target"
                printf 'Error: %s: remote branch %s is missing\n' "$path" "$target" >>"$errors"
            else
                printf '  %s: remote unavailable %s\n' "$path" "$target"
                printf 'Error: %s: cannot query remote %s\n' "$path" "$repo" >>"$errors"
            fi
            continue
        fi

        revision=$(subproject_key "$path" revision || true)
        tag=$(subproject_key "$path" tag || true)
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
                    printf '  %s: tag-pinned %s; outdated %s %s -> %s\n' "$path" "$tag" "$target" "$revision_short" "$remote_short"
                else
                    printf '  %s: outdated %s %s -> %s\n' "$path" "$target" "$revision_short" "$remote_short"
                fi
            fi
        else
            head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
            head_short=$(printf '%s\n' "$head" | cut -c1-12)
            if [ -n "$head" ] && [ "$remote_commit" = "$head" ]; then
                printf '  %s: up to date %s %s\n' "$path" "$target" "$remote_short"
            elif [ -n "$head" ]; then
                printf '  %s: outdated %s %s -> %s\n' "$path" "$target" "$head_short" "$remote_short"
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

# Report remote query results in stable fixed-column records for scripts.
outdated_porcelain_current() {
    label=$1
    ensure_manifest
    errors=$(tmp_for "$MANIFEST_FILE.outdated_errors")
    : >"$errors"

    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        subproject_label=$(join_project_label "$label" "$path")
        repo=$(subproject_repo "$path" || true)
        if [ -z "$repo" ]; then
            printf 'E\t%s\terror\t-\t-\t-\tmissing-repo\n' "$subproject_label"
            printf 'Error: %s: missing repo in %s\n' "$subproject_label" "$MANIFEST_FILE" >>"$errors"
            continue
        fi

        pending=$(subproject_key "$path" pending_branch || true)
        [ -z "$pending" ] || continue

        target=$(outdated_target_branch "$path")
        remote_tmp=$(tmp_for "$MANIFEST_FILE.outdated_remote")
        remote_commit=$(remote_branch_commit "$repo" "$target" "$remote_tmp" || true)
        rm -f "$remote_tmp"
        if [ -z "$remote_commit" ]; then
            if git ls-remote "$repo" >/dev/null 2>&1; then
                printf 'E\t%s\tremote-branch-missing\t%s\t-\t-\tremote-branch-missing\n' "$subproject_label" "$target"
                printf 'Error: %s: remote branch %s is missing\n' "$subproject_label" "$target" >>"$errors"
            else
                printf 'E\t%s\tremote-unavailable\t%s\t-\t-\tremote-unavailable\n' "$subproject_label" "$target"
                printf 'Error: %s: cannot query remote %s\n' "$subproject_label" "$repo" >>"$errors"
            fi
            continue
        fi

        revision=$(subproject_key "$path" revision || true)
        if [ ! -d "$path/.git" ]; then
            printf 'M\t%s\tmissing\t%s\t-\t%s\tcheckout-missing\n' "$subproject_label" "$target" "$remote_commit"
        elif [ -n "$revision" ]; then
            if [ "$remote_commit" != "$revision" ]; then
                printf 'O\t%s\toutdated\t%s\t%s\t%s\tremote-target\n' "$subproject_label" "$target" "$revision" "$remote_commit"
            fi
        else
            head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
            if [ -n "$head" ] && [ "$remote_commit" != "$head" ]; then
                printf 'O\t%s\toutdated\t%s\t%s\t%s\tremote-target\n' "$subproject_label" "$target" "$head" "$remote_commit"
            elif [ -z "$head" ]; then
                printf 'M\t%s\tmissing-head\t%s\t-\t%s\thead-unresolved\n' "$subproject_label" "$target" "$remote_commit"
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

# Recursively check outdated state for the current project and nested project roots.
outdated_recursive() {
    label=$1
    visited=$2
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    printf 'project: %s\n' "$label"
    rc=0
    outdated_current || rc=1

    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.outdated_recursive")
    manifest_subprojects >"$subprojects_tmp"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_project_label "$label" "$path")
            (
                cd "$path" || exit 1
                printf '\n'
                outdated_recursive "$child_label" "$visited"
            ) || rc=1
        fi
    done <"$subprojects_tmp"
    rm -f "$subprojects_tmp"
    return "$rc"
}

# Recursively check outdated state in stable records for scripts.
outdated_porcelain_recursive() {
    label=$1
    visited=$2
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    rc=0
    outdated_porcelain_current "$label" || rc=1

    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.outdated_recursive")
    manifest_subprojects >"$subprojects_tmp"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_project_label "$label" "$path")
            (
                cd "$path" || exit 1
                outdated_porcelain_recursive "$child_label" "$visited"
            ) || rc=1
        fi
    done <"$subprojects_tmp"
    rm -f "$subprojects_tmp"
    return "$rc"
}

# Check subproject remotes for newer target-branch commits without changing state.
cmd_outdated() {
    parse_recursive_output outdated "$@"
    recursive=$PARSED_RECURSIVE
    porcelain=$PARSED_PORCELAIN
    json=$PARSED_JSON
    json_pretty=$PARSED_JSON_PRETTY
    if [ "$porcelain" -eq 1 ]; then
        rows=$(mktemp)
        if [ "$recursive" -eq 1 ]; then
            visited=$(mktemp)
            : >"$visited"
            rc=0
            outdated_porcelain_recursive "." "$visited" >"$rows" || rc=$?
            rm -f "$visited"
        else
            rc=0
            outdated_porcelain_current "." >"$rows" || rc=$?
        fi
        cat "$rows"
        if [ "$rc" -ne 0 ] || [ -s "$rows" ]; then
            rm -f "$rows"
            return "$EXIT_ISSUES"
        fi
        rm -f "$rows"
        return 0
    elif [ "$json" -eq 1 ]; then
        rows=$(mktemp)
        errors=$(mktemp)
        warnings=$(mktemp)
        : >"$errors"
        : >"$warnings"
        if [ "$recursive" -eq 1 ]; then
            visited=$(mktemp)
            : >"$visited"
            rc=0
            outdated_porcelain_recursive "." "$visited" >"$rows" 2>"$errors" || rc=$?
            rm -f "$visited"
        else
            rc=0
            outdated_porcelain_current "." >"$rows" 2>"$errors" || rc=$?
        fi
        if [ "$rc" -ne 0 ] || [ -s "$rows" ]; then ok=0; else ok=1; fi
        emit_json_result outdated "$recursive" "$ok" "$rows" "$errors" "$warnings" "$json_pretty"
        rm -f "$rows" "$errors" "$warnings"
        [ "$ok" -eq 1 ] || return "$EXIT_ISSUES"
        return 0
    elif [ "$recursive" -eq 1 ]; then
        visited=$(mktemp)
        : >"$visited"
        outdated_recursive "." "$visited"
        rc=$?
        rm -f "$visited"
        return "$rc"
    fi
    rows=$(mktemp)
    rc=0
    outdated_current || rc=$?
    outdated_porcelain_current "." >"$rows" 2>/dev/null || true
    if [ "$rc" -ne 0 ] || [ -s "$rows" ]; then
        rm -f "$rows"
        return "$EXIT_ISSUES"
    fi
    rm -f "$rows"
    notice_nested_projects
}

# Validate that the current checkout still matches the manifest and config.
verify_current() {
    ensure_manifest
    configured_clone_mode >/dev/null
    errors=$(tmp_for "$MANIFEST_FILE.verify_errors")
    warnings=$(tmp_for "$MANIFEST_FILE.verify_warnings")
    : >"$errors"
    : >"$warnings"

    duplicates=$(manifest_subprojects | sort | uniq -d)
    if [ -n "$duplicates" ]; then
        printf '%s\n' "$duplicates" | while IFS= read -r path; do
            [ -n "$path" ] && printf 'Error: %s: duplicate subproject path in %s\n' "$path" "$MANIFEST_FILE" >>"$errors"
        done
    fi

    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        repo=$(subproject_repo "$path" || true)
        if [ -z "$repo" ]; then
            printf 'Error: %s: missing repo in %s\n' "$path" "$MANIFEST_FILE" >>"$errors"
            continue
        fi
        mode=$(effective_clone_mode "$path")
        if [ ! -d "$path/.git" ]; then
            printf 'Error: %s: subproject checkout is missing; run git-lego sync\n' "$path" >>"$errors"
            continue
        fi

        actual_repo=$(git -C "$path" remote get-url origin 2>/dev/null || true)
        if [ "$actual_repo" != "$repo" ]; then
            printf 'Error: %s: origin remote differs from manifest\n' "$path" >>"$errors"
            printf '  expected: %s\n  actual:   %s\n' "$repo" "$actual_repo" >>"$errors"
        fi

        if [ "$mode" = partial ]; then
            repo_is_partial_clone "$path" ||
                printf 'Error: %s: manifest/config requests clone=partial, but existing checkout is full; remove the subproject and run git-lego sync or use clone=full\n' "$path" >>"$errors"
        else
            if repo_is_partial_clone "$path"; then
                printf 'Error: %s: manifest/config requests clone=full, but existing checkout is partial; remove the subproject and run git-lego sync or use clone=partial\n' "$path" >>"$errors"
            fi
        fi

        pending=$(subproject_key "$path" pending_branch || true)
        tag=$(subproject_key "$path" tag || true)
        revision=$(subproject_key "$path" revision || true)
        target=$(subproject_key "$path" target_branch || true)
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
            printf 'Warning: %s: subproject has uncommitted changes\n' "$path" >>"$warnings"
        fi
    done

    unmanaged_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        printf 'Warning: %s: unmanaged nested Git repository\n' "$path" >>"$warnings"
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
    printf 'Project verified.\n'
}

# Recursively verify the current project and nested project roots.
verify_recursive() {
    label=$1
    visited=$2
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    printf 'Verifying project: %s\n' "$label"
    rc=0
    verify_current || rc=1

    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.verify_recursive")
    manifest_subprojects >"$subprojects_tmp"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_project_label "$label" "$path")
            (
                cd "$path" || exit 1
                verify_recursive "$child_label" "$visited"
            ) || rc=1
        fi
    done <"$subprojects_tmp"
    rm -f "$subprojects_tmp"
    return "$rc"
}

# Validate project state, optionally including nested projects.
cmd_verify() {
    parse_recursive_output verify "$@"
    recursive=$PARSED_RECURSIVE
    json=$PARSED_JSON
    json_pretty=$PARSED_JSON_PRETTY
    [ "$PARSED_PORCELAIN" -eq 0 ] || usage_error "verify does not support --porcelain"
    if [ "$json" -eq 1 ]; then
        rows=$(mktemp)
        errors=$(mktemp)
        warnings=$(mktemp)
        out=$(mktemp)
        : >"$rows"
        : >"$warnings"
        if [ "$recursive" -eq 1 ]; then
            visited=$(mktemp)
            : >"$visited"
            rc=0
            verify_recursive "." "$visited" >"$out" 2>"$errors" || rc=$?
            rm -f "$visited"
        else
            rc=0
            verify_current >"$out" 2>"$errors" || rc=$?
        fi
        [ "$rc" -eq 0 ] && ok=1 || ok=0
        emit_json_result verify "$recursive" "$ok" "$rows" "$errors" "$warnings" "$json_pretty"
        rm -f "$rows" "$errors" "$warnings" "$out"
        [ "$rc" -eq 0 ] || return "$EXIT_ISSUES"
        return 0
    fi
    if [ "$recursive" -eq 1 ]; then
        visited=$(mktemp)
        : >"$visited"
        verify_recursive "." "$visited"
        rc=$?
        rm -f "$visited"
        return "$rc"
    fi
    verify_current
    notice_nested_projects
}

# Validate positive integer options such as log --max-count.
is_positive_integer() {
    case "$1" in
        ""|*[!0-9]*) return 1 ;;
        0) return 1 ;;
        *) return 0 ;;
    esac
}

# Append one repository's recent commits to the combined project log input.
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

# Collect commits from the current project, recursing into nested projects on demand.
collect_log_for_project() {
    label=$1
    out=$2
    max_count=$3
    since=$4
    until=$5
    recursive=$6
    filter=$7
    visited_projects=$8
    visited_repos=$9

    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited_projects" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited_projects"
    root_label=${label:-.}
    append_log_for_repo . "$root_label" "$out" "$max_count" "$since" "$until" "$filter" "$visited_repos"

    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.log_subprojects")
    manifest_subprojects >"$subprojects_tmp"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        child_label=$(join_project_label "$label" "$path")
        if [ -d "$path/.git" ]; then
            append_log_for_repo "$path" "$child_label" "$out" "$max_count" "$since" "$until" "$filter" "$visited_repos"
            if [ "$recursive" -eq 1 ] && [ -f "$path/$MANIFEST_FILE" ]; then
                (
                    cd "$path" || exit 1
                    collect_log_for_project "$child_label" "$out" "$max_count" "$since" "$until" "$recursive" "$filter" "$visited_projects" "$visited_repos"
                )
            fi
        elif [ -z "$filter" ] || [ "$filter" = "$child_label" ]; then
            warn "missing repository for log: $child_label"
        fi
    done <"$subprojects_tmp"
    rm -f "$subprojects_tmp"
}

# Show a combined, read-only history view across the active project.
cmd_log() {
    max_count=50
    since=
    until=
    subproject_filter=
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
            --subproject)
                [ $# -ge 2 ] || die "--subproject requires a value"
                if [ "$2" = "." ]; then
                    subproject_filter=.
                else
                    reject_backslash_path "$2"
                    subproject_filter=$(normalize_path "$2")
                    [ -n "$(subproject_repo "$subproject_filter" || true)" ] ||
                        die "--subproject must be . or a subproject path in $MANIFEST_FILE"
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
    visited_projects=$(mktemp)
    visited_repos=$(mktemp)
    : >"$log_tmp"
    : >"$visited_projects"
    : >"$visited_repos"

    collect_log_for_project "" "$log_tmp" "$max_count" "$since" "$until" "$recursive" "$subproject_filter" "$visited_projects" "$visited_repos"
    sort -t '|' -k1,1nr "$log_tmp" | sed -n "1,${max_count}p" >"$sorted_tmp"

    if [ "$oneline" -eq 1 ]; then
        awk -F '|' '{ printf "%-24s %s %s\n", $3, $4, $5 }' "$sorted_tmp"
    else
        awk -F '|' '{ printf "%s  %-24s  %s  %s\n", $2, $3, $4, $5 }' "$sorted_tmp"
    fi

    rm -f "$log_tmp" "$sorted_tmp" "$visited_projects" "$visited_repos"
    if [ "$recursive" -eq 0 ]; then
        notice_nested_projects
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
                [ -z "$branch" ] || die "usage: git-lego start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]"
                branch=$1
                shift
                ;;
        esac
    done
    [ -n "$branch" ] || die "usage: git-lego start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]"
    [ -d .git ] && startup_new=0 || startup_new=1
    confirm_startup_directory "$sure"
    ensure_outer_repo
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    ensure_gitattributes_guard

    if [ "$branch" = "." ]; then
        quiet_arg=
        if [ -n "${GIT_LEGO_SNAPSHOT_QUIET:-}" ] || [ -n "${GIT_LEGO_RECORD_REMOVED_QUIET:-}" ]; then
            quiet_arg=--quiet
        fi
        cmd_snapshot ${quiet_arg:+--quiet}
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

    # Switch the outer repository first, then checked-out subprojects. Missing
    # subprojects stay in the manifest and can later be restored by sync.
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        git checkout "$branch" || die "failed to check out outer branch $branch"
    else
        git checkout -b "$branch" || die "failed to create outer branch $branch"
    fi

    manifest_subprojects | while IFS= read -r path; do
        [ -d "$path/.git" ] || continue
        if git -C "$path" show-ref --verify --quiet "refs/heads/$branch"; then
            git -C "$path" checkout "$branch" || die "failed to check out branch $branch in subproject $path"
        else
            git -C "$path" checkout -b "$branch" || die "failed to create branch $branch in subproject $path"
        fi
    done

    # Only project metadata is written here. Subproject pending state is created later
    # by snapshot/upload once a subproject actually has committed work.
    manifest_write_project "$ticket" "$branch"
    [ "$install_hooks" -eq 0 ] || install_hooks_all
    printf 'Started project branch %s.\n' "$branch"
}

# Record pending metadata for one clean subproject that has committed local work.
record_subproject_if_needed() {
    path=$1
    quiet=$2
    [ -d "$path/.git" ] || return 0
    if repo_has_dirty "$path"; then
        [ "$quiet" -eq 1 ] || warn "skipping dirty subproject $path during snapshot"
        return 0
    fi
    repo=$(subproject_repo "$path")
    require_value "$repo" "subproject $path is missing repo in $MANIFEST_FILE; run git-lego add again or fix the manifest"
    target=$(subproject_key "$path" target_branch || true)
    [ -n "$target" ] || target=$(default_target_branch "$path")
    mod_branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    [ -n "$mod_branch" ] || return 0
    work_count=$(subproject_work_count "$path" "$target")
    if [ "$work_count" -gt 0 ]; then
        base=$(base_for_subproject "$path" "$target")
        pushed=$(resolve_head_commit "$path" "cannot snapshot subproject $path")
        manifest_write_subproject "$path" "$repo" pending "$target" "$mod_branch" "$base" "$pushed"
        [ "$quiet" -eq 1 ] || printf 'Recorded subproject %s branch %s at %.12s.\n' "$path" "$mod_branch" "$pushed"
    fi
}

preflight_subproject_snapshot() {
    path=$1
    [ -d "$path/.git" ] || return 0
    repo_has_dirty "$path" && return 0
    repo=$(subproject_repo "$path")
    require_value "$repo" "subproject $path is missing repo in $MANIFEST_FILE; run git-lego add again or fix the manifest"
    target=$(subproject_key "$path" target_branch || true)
    [ -n "$target" ] || target=$(default_target_branch "$path")
    mod_branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    [ -n "$mod_branch" ] || return 0
    subproject_work_count "$path" "$target" >/dev/null
}

snapshot_current() {
    quiet=$1
    dry_run=${2:-0}
    ensure_outer_repo
    [ "$dry_run" -eq 1 ] || acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    branch=$(current_branch)
    [ "$branch" != "HEAD" ] || die "snapshot requires the outer repository to be on a named branch"
    ticket=$(ticket_from_branch "$branch")
    manifest_subprojects | while IFS= read -r path; do
        if [ "$dry_run" -eq 1 ]; then
            [ -d "$path/.git" ] || continue
            repo_has_dirty "$path" && continue
            repo=$(subproject_repo "$path")
            require_value "$repo" "subproject $path is missing repo in $MANIFEST_FILE; run git-lego add again or fix the manifest"
        else
            preflight_subproject_snapshot "$path"
        fi
    done
    if [ "$dry_run" -eq 1 ]; then
        old_id=$(manifest_get project id || true)
        old_branch=$(manifest_get project branch || true)
        printf '[dry-run] project id: %s -> %s\n' "${old_id:-<unset>}" "${ticket:-<unset>}"
        printf '[dry-run] project branch: %s -> %s\n' "${old_branch:-<unset>}" "$branch"
        manifest_subprojects | while IFS= read -r path; do
            [ -d "$path/.git" ] || continue
            if repo_has_dirty "$path"; then
                [ "$quiet" -eq 1 ] || printf '[dry-run] %s: would skip dirty subproject\n' "$path"
                continue
            fi
            target=$(subproject_key "$path" target_branch || true)
            [ -n "$target" ] || target=$(default_target_branch "$path")
            mod_branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
            [ -n "$mod_branch" ] || continue
            if count=$(subproject_work_count "$path" "$target" 2>/dev/null); then
                if [ "$count" -gt 0 ]; then
                    base=$(base_for_subproject "$path" "$target" 2>/dev/null || printf 'unknown')
                    pushed=$(resolve_head_commit "$path" "cannot snapshot subproject $path")
                    old_pending=$(subproject_key "$path" pending_branch || true)
                    old_base=$(subproject_key "$path" base_revision || true)
                    old_pushed=$(subproject_key "$path" pushed_commit || true)
                    printf '[dry-run] %s target_branch: %s -> %s\n' "$path" "${target:-<unset>}" "$target"
                    printf '[dry-run] %s pending_branch: %s -> %s\n' "$path" "${old_pending:-<unset>}" "$mod_branch"
                    printf '[dry-run] %s base_revision: %s -> %s\n' "$path" "${old_base:-<unset>}" "$base"
                    printf '[dry-run] %s pushed_commit: %s -> %s\n' "$path" "${old_pushed:-<unset>}" "$pushed"
                fi
            else
                printf '[dry-run] %s pending state: unknown; real run would fetch first if needed\n' "$path"
            fi
        done
        clear_base_overrides
        return 0
    fi
    manifest_write_project "$ticket" "$branch"
    manifest_subprojects | while IFS= read -r path; do
        record_subproject_if_needed "$path" "$quiet"
    done
    clear_base_overrides
    [ "$quiet" -eq 1 ] || printf 'Refreshed current git-lego state.\n'
}

snapshot_recursive() {
    label=$1
    visited=$2
    quiet=$3
    dry_run=${4:-0}
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    [ "$quiet" -eq 1 ] || printf 'Snapshotting project: %s\n' "$label"
    snapshot_current "$quiet" "$dry_run"
    cleanup_manifest_lock

    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.snapshot_recursive")
    manifest_subprojects >"$subprojects_tmp"
    rc=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_project_label "$label" "$path")
            (
                cd "$path" || exit 1
                snapshot_recursive "$child_label" "$visited" "$quiet" "$dry_run"
            ) || rc=1
        fi
    done <"$subprojects_tmp"
    rm -f "$subprojects_tmp"
    return "$rc"
}

# Snapshot manifest state from local branches without pushing anything.
cmd_snapshot() {
    quiet=0
    recursive=0
    dry_run=0
    clear_base_overrides
    while [ $# -gt 0 ]; do
        case "$1" in
            --recursive) recursive=1; shift ;;
            --quiet) quiet=1; shift ;;
            --dry-run) dry_run=1; GIT_LEGO_DRY_RUN=1; shift ;;
            --no-fetch) GIT_LEGO_NO_FETCH=1; shift ;;
            --base)
                [ $# -ge 2 ] || usage_error "--base requires <subproject>=<ref>"
                add_base_override "$2"
                shift 2
                ;;
            *) usage_error "unknown snapshot option: $1" ;;
        esac
    done
    if [ "$recursive" -eq 1 ]; then
        visited=$(mktemp)
        : >"$visited"
        snapshot_recursive "." "$visited" "$quiet" "$dry_run"
        rc=$?
        rm -f "$visited"
        return "$rc"
    fi
    snapshot_current "$quiet" "$dry_run"
    [ "$quiet" -eq 1 ] || notice_nested_snapshot_candidates
}

# Find the base commit used to compare subproject work against its target branch.
base_for_subproject() {
    path=$1
    target=$2
    require_value "$target" "cannot calculate base revision for $path without a target branch"
    override=$(base_override_for "$path" 2>/dev/null || true)
    if [ -n "$override" ]; then
        resolve_commit "$path" "$override" "cannot use --base for $path"
        return
    fi
    fetch_note=
    if [ "$GIT_LEGO_NO_FETCH" -eq 0 ] && [ "$GIT_LEGO_DRY_RUN" -eq 0 ]; then
        fetch_note=$(fetch_quiet "$path" 2>&1 || true)
    fi
    if git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1; then
        base=$(git -C "$path" merge-base HEAD "origin/$target" 2>/dev/null) ||
            die "cannot find a merge base for $path between HEAD and origin/$target; fetch the subproject or check target_branch"
    elif git -C "$path" rev-parse --verify "$target^{commit}" >/dev/null 2>&1; then
        base=$(git -C "$path" merge-base HEAD "$target" 2>/dev/null) ||
            die "cannot find a merge base for $path between HEAD and $target; fetch the subproject or check target_branch"
    else
        printf 'Error: cannot calculate base revision for %s\n' "$path" >&2
        printf '  requested target ref: %s\n' "$target" >&2
        if [ "$GIT_LEGO_DRY_RUN" -eq 1 ]; then
            printf '  dry-run does not fetch; the real run would fetch first if needed\n' >&2
        elif [ "$GIT_LEGO_NO_FETCH" -eq 1 ]; then
            printf '  fetch was skipped by --no-fetch and no local target ref resolved\n' >&2
        elif [ -n "$fetch_note" ]; then
            printf '  fetch result: %s\n' "$fetch_note" >&2
        else
            printf '  fetch completed, but origin/%s and %s did not resolve\n' "$target" "$target" >&2
        fi
        printf '  recovery: fetch/fix target_branch, rerun with --no-fetch if local refs are authoritative, or pass --base %s=<ref>\n' "$path" >&2
        exit "$EXIT_PRECONDITION"
    fi
    require_value "$base" "calculated an empty base revision for $path; fetch the subproject or check target_branch"
    printf '%s\n' "$base"
}

# Count commits in a subproject that are ahead of the resolved base revision.
subproject_work_count() {
    path=$1
    target=$2
    base=$(base_for_subproject "$path" "$target")
    count=$(git -C "$path" rev-list --count "$base..HEAD" 2>/dev/null) ||
        die "cannot count commits for $path from $base to HEAD; verify the subproject history"
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
        git commit -m "Update git-lego manifest for $branch" >/dev/null ||
            die "failed to commit manifest update on $branch"
    else
        warn "manifest changed but Git user.name/user.email are not configured; skipping outer commit"
    fi
}

# Push changed subproject branches, record pending/finalized state, and push the outer branch.
cmd_upload() {
    finalize=0
    dry_run=0
    clear_base_overrides
    while [ $# -gt 0 ]; do
        case "$1" in
            --finalize)
                finalize=1
                shift
                ;;
            --dry-run)
                dry_run=1
                GIT_LEGO_DRY_RUN=1
                shift
                ;;
            --no-fetch)
                GIT_LEGO_NO_FETCH=1
                shift
                ;;
            --base)
                [ $# -ge 2 ] || usage_error "--base requires <subproject>=<ref>"
                add_base_override "$2"
                shift 2
                ;;
            *) usage_error "unknown upload option: $1" ;;
        esac
    done
    [ "$dry_run" -eq 1 ] || acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    branch=$(current_branch)
    [ "$branch" != "HEAD" ] || die "upload requires a named branch"

    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.subprojects")
    manifest_subprojects >"$subprojects_tmp"

    # A dirty subproject blocks the whole upload so the manifest never records a
    # branch that does not contain all local work.
    while IFS= read -r path; do
        [ -d "$path/.git" ] || continue
        dirty=$(repo_status_porcelain "$path" "cannot inspect subproject $path before upload")
        [ -z "$dirty" ] || die "subproject $path has uncommitted changes; commit or stash before upload"
    done <"$subprojects_tmp"

    upload_plan=$(tmp_for "$MANIFEST_FILE.upload_plan")
    : >"$upload_plan"

    # Candidate branches from start are skipped unless they have commits ahead
    # of the target branch. Preflight every changed subproject before pushing or
    # rewriting the manifest so one bad repository does not strand earlier ones
    # in a surprising partially uploaded state.
    while IFS= read -r path; do
        [ -d "$path/.git" ] || continue
        repo=$(subproject_repo "$path")
        require_value "$repo" "subproject $path is missing repo in $MANIFEST_FILE; run git-lego add again or fix the manifest"
        target=$(subproject_key "$path" target_branch || true)
        [ -n "$target" ] || target=$(default_target_branch "$path")
        mod_branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
        if [ "$dry_run" -eq 1 ]; then
            if ! work_count=$(subproject_work_count "$path" "$target" 2>/dev/null); then
                printf '[dry-run] %s upload state: unknown; real run would fetch first if needed\n' "$path"
                continue
            fi
        else
            work_count=$(subproject_work_count "$path" "$target")
        fi
        if [ "$work_count" -gt 0 ]; then
            [ -n "$mod_branch" ] || die "subproject $path has committed work on detached HEAD; check out a branch before upload"
            base=$(base_for_subproject "$path" "$target")
            pushed=$(resolve_head_commit "$path" "cannot upload subproject $path")
            remote_exists "$path" || die "subproject $path has no origin remote; restore or add origin, then rerun git-lego upload"
            if [ "$dry_run" -eq 1 ]; then
                printf '[dry-run] would push subproject %s branch %s with refspec HEAD:%s\n' "$path" "$mod_branch" "$mod_branch"
                if [ "$finalize" -eq 1 ]; then
                    printf '[dry-run] would finalize %s at %s from branch %s\n' "$path" "$pushed" "$mod_branch"
                else
                    printf '[dry-run] would record pending %s target=%s branch=%s base=%s pushed=%s\n' "$path" "$target" "$mod_branch" "$base" "$pushed"
                fi
                continue
            fi
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$path" "$repo" "$target" "$mod_branch" "$base" "$pushed" >>"$upload_plan"
        fi
    done <"$subprojects_tmp"

    if [ "$dry_run" -eq 0 ]; then
        while IFS='	' read -r path repo target mod_branch base pushed; do
            [ -n "$path" ] || continue
            if ! git -C "$path" push -u origin "HEAD:$mod_branch"; then
                printf 'Error: failed to push subproject %s branch %s to origin\n' "$path" "$mod_branch" >&2
                printf '  recovery: fix the remote, credentials, or rejected branch, then rerun git-lego upload.\n' >&2
                printf '  note: any subproject branches already pushed by this run may remain on their remotes; rerunning upload will reuse the current manifest and branch state.\n' >&2
                rm -f "$upload_plan" "$subprojects_tmp"
                return "$EXIT_GIT"
            fi
            if [ "$finalize" -eq 1 ]; then
                manifest_write_subproject "$path" "$repo" finalized "$pushed" "" "$mod_branch"
                printf 'Uploaded and finalized subproject %s branch %s at %.12s.\n' "$path" "$mod_branch" "$pushed"
            else
                manifest_write_subproject "$path" "$repo" pending "$target" "$mod_branch" "$base" "$pushed"
                printf 'Uploaded subproject %s branch %s at %.12s.\n' "$path" "$mod_branch" "$pushed"
            fi
        done <"$upload_plan"
    fi
    rm -f "$upload_plan"
    rm -f "$subprojects_tmp"

    # The outer push is best-effort when no origin is configured; subproject pushes
    # remain strict because pending manifest state points at those branches.
    if [ "$dry_run" -eq 1 ]; then
        if remote_exists .; then
            printf '[dry-run] would push outer branch %s with refspec HEAD:%s\n' "$branch" "$branch"
        else
            printf '[dry-run] outer repository has no origin remote; would skip outer push\n'
        fi
    else
        commit_manifest_if_needed "$branch"
        if remote_exists .; then
            git push -u origin "HEAD:$branch" || git_error "failed to push outer branch $branch to origin"
        else
            warn "outer repository has no origin remote; skipped outer push"
        fi
    fi
    clear_base_overrides
}

# Read the manifest revision value used as a diff base.
manifest_diff_base_from_file() {
    file=$1
    path=$2
    section=$(subproject_section "$path")
    base=$(manifest_get_from_file "$file" "$section" revision || true)
    [ -n "$base" ] || base=$(manifest_get_from_file "$file" "$section" pushed_commit || true)
    printf '%s\n' "$base"
}

# Emit changed subproject commits since the recorded manifest revisions.
diff_porcelain_from_manifest() {
    base_manifest=$1
    rows=$2
    errors=$3
    : >"$rows"

    manifest_subprojects_from_file "$base_manifest" | while IFS= read -r path; do
        [ -n "$path" ] || continue
        base=$(manifest_diff_base_from_file "$base_manifest" "$path")
        if [ -z "$base" ]; then
            printf 'E\t%s\tmissing-base\t-\t-\t-\tmissing-recorded-revision\n' "$path" >>"$rows"
            printf 'Error: %s has no recorded revision in %s\n' "$path" "$base_manifest" >>"$errors"
            continue
        fi
        if [ ! -d "$path/.git" ]; then
            printf 'E\t%s\tmissing\t-\t%s\t-\tcheckout-missing\n' "$path" "$base" >>"$rows"
            printf 'Error: %s checkout is missing\n' "$path" >>"$errors"
            continue
        fi
        head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
        if [ -z "$head" ]; then
            printf 'E\t%s\tmissing-head\t-\t%s\t-\thead-unresolved\n' "$path" "$base" >>"$rows"
            printf 'Error: cannot resolve HEAD in %s\n' "$path" >>"$errors"
            continue
        fi
        if [ "$base" = "$head" ]; then
            continue
        fi
        if ! git -C "$path" rev-parse --verify "$base^{commit}" >/dev/null 2>&1; then
            printf 'E\t%s\tmissing-base\t-\t%s\t%s\tbase-unresolved\n' "$path" "$base" "$head" >>"$rows"
            printf 'Error: cannot resolve recorded revision %.12s in %s\n' "$base" "$path" >>"$errors"
            continue
        fi
        git -C "$path" log --format='%H%x09%s' "$base..HEAD" | while IFS='	' read -r sha subject; do
            [ -n "$sha" ] || continue
            safe_subject=$(printf '%s\n' "$subject" | tr '	' ' ')
            printf 'L\t%s\tdiff\t%s\t%s\t%s\t%s\n' "$path" "$base" "$head" "$sha" "$safe_subject" >>"$rows"
        done
    done
}

# Show changed subproject commits relative to manifest-recorded revisions.
cmd_diff() {
    since=
    stat=0
    json=0
    json_pretty=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --since)
                [ $# -ge 2 ] || usage_error "--since requires a ref"
                since=$2
                shift 2
                ;;
            --stat)
                stat=1
                shift
                ;;
            --json)
                json=1
                shift
                ;;
            --json-pretty)
                json=1
                json_pretty=1
                shift
                ;;
            *) usage_error "unknown diff option: $1" ;;
        esac
    done
    ensure_manifest
    validate_manifest_schema

    base_manifest=$MANIFEST_FILE
    base_label=$MANIFEST_FILE
    if [ -n "$since" ]; then
        base_manifest=$(tmp_for "$MANIFEST_FILE.diff_since")
        if ! git show "$since:$MANIFEST_FILE" >"$base_manifest" 2>/dev/null; then
            rm -f "$base_manifest"
            precondition_error "cannot read $MANIFEST_FILE at $since"
        fi
        base_label="$since:$MANIFEST_FILE"
    fi

    rows=$(tmp_for "$MANIFEST_FILE.diff_rows")
    errors=$(tmp_for "$MANIFEST_FILE.diff_errors")
    warnings=$(tmp_for "$MANIFEST_FILE.diff_warnings")
    : >"$errors"
    : >"$warnings"
    diff_porcelain_from_manifest "$base_manifest" "$rows" "$errors"

    if [ "$json" -eq 1 ]; then
        if [ -s "$rows" ] || [ -s "$errors" ]; then ok=0; else ok=1; fi
        emit_json_result diff 0 "$ok" "$rows" "$errors" "$warnings" "$json_pretty"
        rm -f "$rows" "$errors" "$warnings"
        [ "$base_manifest" = "$MANIFEST_FILE" ] || rm -f "$base_manifest"
        [ "$ok" -eq 1 ] || return "$EXIT_ISSUES"
        return 0
    fi

    if [ ! -s "$rows" ]; then
        printf 'No subproject commit differences since %s.\n' "$base_label"
        rm -f "$rows" "$errors" "$warnings"
        [ "$base_manifest" = "$MANIFEST_FILE" ] || rm -f "$base_manifest"
        return 0
    fi

    current_path=
    while IFS='	' read -r code path state base head sha detail; do
        [ -n "$code" ] || continue
        if [ "$code" = "E" ]; then
            continue
        fi
        if [ "$current_path" != "$path" ]; then
            [ -z "$current_path" ] || printf '\n'
            current_path=$path
            printf '%s: %s..%s\n' "$path" "$(printf '%s\n' "$base" | cut -c1-12)" "$(printf '%s\n' "$head" | cut -c1-12)"
            if [ "$stat" -eq 1 ]; then
                git -C "$path" log --stat --oneline "$base..HEAD"
                continue
            fi
        fi
        if [ "$stat" -eq 0 ]; then
            printf '  %.12s %s\n' "$sha" "$detail"
        fi
    done <"$rows"

    if [ -s "$errors" ]; then
        cat "$errors" >&2
    fi
    had_errors=0
    [ ! -s "$errors" ] || had_errors=1
    rm -f "$rows" "$errors" "$warnings"
    [ "$base_manifest" = "$MANIFEST_FILE" ] || rm -f "$base_manifest"
    [ "$had_errors" -eq 0 ] || return "$EXIT_ISSUES"
    return "$EXIT_ISSUES"
}

config_manifest_key() {
    case "$1" in
        clone-mode) printf 'clone\n' ;;
        *) return 1 ;;
    esac
}

validate_config_value() {
    key=$1
    value=$2
    case "$key:$value" in
        clone-mode:full|clone-mode:partial) ;;
        *) usage_error "$key must be full or partial" ;;
    esac
}

ensure_manifest_subproject_path() {
    path=$1
    if ! manifest_subprojects | grep -F -x "$path" >/dev/null 2>&1; then
        precondition_error "unknown subproject: $path"
    fi
}

# Manage manifest-backed subproject settings.
cmd_config() {
    [ $# -ge 1 ] || usage_error "usage: git-lego config <get|set|list|unset> ..."
    action=$1
    shift
    ensure_manifest
    validate_manifest_schema

    case "$action" in
        get)
            [ $# -eq 2 ] || usage_error "usage: git-lego config get <path> clone-mode"
            reject_backslash_path "$1"
            path=$(normalize_path "$1")
            key=$2
            manifest_key=$(config_manifest_key "$key") || usage_error "unknown config key: $key"
            assert_path_not_inside_nested_project "$path"
            ensure_manifest_subproject_path "$path"
            value=$(subproject_key "$path" "$manifest_key" || true)
            [ -n "$value" ] || return 1
            printf '%s\n' "$value"
            ;;
        set)
            [ $# -eq 3 ] || usage_error "usage: git-lego config set <path> clone-mode <value>"
            reject_backslash_path "$1"
            path=$(normalize_path "$1")
            key=$2
            value=$3
            manifest_key=$(config_manifest_key "$key") || usage_error "unknown config key: $key"
            validate_config_value "$key" "$value"
            assert_path_not_inside_nested_project "$path"
            ensure_manifest_subproject_path "$path"
            acquire_manifest_lock
            manifest_set_subproject_key "$path" "$manifest_key" "$value"
            warn "set $key for $path to $value; existing checkouts are not converted"
            ;;
        list)
            [ $# -le 1 ] || usage_error "usage: git-lego config list [<path>]"
            if [ $# -eq 1 ]; then
                reject_backslash_path "$1"
                path=$(normalize_path "$1")
                assert_path_not_inside_nested_project "$path"
                ensure_manifest_subproject_path "$path"
                value=$(subproject_key "$path" clone || true)
                if [ -n "$value" ]; then
                    printf '%s\tclone-mode=%s\n' "$path" "$value"
                fi
            else
                manifest_subprojects | while IFS= read -r path; do
                    [ -n "$path" ] || continue
                    value=$(subproject_key "$path" clone || true)
                    if [ -n "$value" ]; then
                        printf '%s\tclone-mode=%s\n' "$path" "$value"
                    fi
                done
            fi
            ;;
        unset)
            [ $# -eq 2 ] || usage_error "usage: git-lego config unset <path> clone-mode"
            reject_backslash_path "$1"
            path=$(normalize_path "$1")
            key=$2
            manifest_key=$(config_manifest_key "$key") || usage_error "unknown config key: $key"
            assert_path_not_inside_nested_project "$path"
            ensure_manifest_subproject_path "$path"
            acquire_manifest_lock
            manifest_remove_subproject_key "$path" "$manifest_key"
            ;;
        *) usage_error "unknown config action: $action" ;;
    esac
}

# Shared foreach engine for all subprojects or only manifest-pending subprojects.
run_foreach() {
    mode=$1
    shift
    [ $# -gt 0 ] || die "usage: git-lego $mode -- <command> [args...]"
    if [ "$1" = "--" ]; then
        shift
    fi
    [ $# -gt 0 ] || die "usage: git-lego $mode -- <command> [args...]"

    root=$(repo_root)
    root=$(CDPATH= cd -- "$root" && pwd)
    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.foreach")
    manifest_subprojects >"$subprojects_tmp"

    rc=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        pending=$(subproject_key "$path" pending_branch || true)
        if [ "$mode" = "foreach-pending" ] && [ -z "$pending" ]; then
            continue
        fi
        if [ ! -d "$path/.git" ]; then
            warn "skipping missing subproject $path"
            continue
        fi

        repo=$(subproject_repo "$path")
        target=$(subproject_key "$path" target_branch || true)
        base=$(subproject_key "$path" base_revision || true)
        pushed=$(subproject_key "$path" pushed_commit || true)
        revision=$(subproject_key "$path" revision || true)
        tag=$(subproject_key "$path" tag || true)
        branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
        subproject_abs=$(CDPATH= cd -- "$path" && pwd)

        # Run in a subshell so each subproject gets its own working directory and
        # exported context without leaking changes into the next iteration.
        child_rc=0
        (
            cd "$path" || exit 1
            GIT_LEGO_ROOT=$root \
            GIT_LEGO_SUBPROJECT_PATH=$path \
            GIT_LEGO_SUBPROJECT_ABSPATH=$subproject_abs \
            GIT_LEGO_SUBPROJECT_REPO=$repo \
            GIT_LEGO_BRANCH=$branch \
            GIT_LEGO_TARGET_BRANCH=$target \
            GIT_LEGO_PENDING_BRANCH=$pending \
            GIT_LEGO_BASE_REVISION=$base \
            GIT_LEGO_PUSHED_COMMIT=$pushed \
            GIT_LEGO_REVISION=$revision \
            GIT_LEGO_TAG=$tag \
            REPO_PATH=$path \
            REPO_PROJECT=$path \
            "$@"
        ) || rc=$?

        [ "$rc" -eq 0 ] || break
    done <"$subprojects_tmp"

    rm -f "$subprojects_tmp"
    return "$rc"
}

# Public wrapper for running a command in every checked-out subproject.
cmd_foreach() {
    run_foreach foreach "$@"
}

# Public wrapper for running a command only in pending subprojects.
cmd_foreach_pending() {
    run_foreach foreach-pending "$@"
}

foreach_filtered_rows() {
    mode=$1
    rows=$2
    : >"$rows"
    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -d "$path/.git" ] || continue
        dirty=0
        repo_has_dirty "$path" && dirty=1
        case "$mode:$dirty" in
            foreach-modified:1)
                printf 'F\t%s\tmodified\t-\t-\t-\tdirty\n' "$path" >>"$rows"
                ;;
            foreach-clean:0)
                printf 'F\t%s\tclean\t-\t-\t-\tclean\n' "$path" >>"$rows"
                ;;
        esac
    done
}

run_foreach_filtered_command() {
    rows=$1
    continue_on_error=$2
    shift 2
    root=$(repo_root)
    root=$(CDPATH= cd -- "$root" && pwd)
    rc=0

    while IFS='	' read -r code path state target current expected detail; do
        [ -n "$code" ] || continue
        if [ ! -d "$path/.git" ]; then
            warn "skipping missing subproject $path"
            continue
        fi

        repo=$(subproject_repo "$path")
        target=$(subproject_key "$path" target_branch || true)
        pending=$(subproject_key "$path" pending_branch || true)
        base=$(subproject_key "$path" base_revision || true)
        pushed=$(subproject_key "$path" pushed_commit || true)
        revision=$(subproject_key "$path" revision || true)
        tag=$(subproject_key "$path" tag || true)
        branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
        subproject_abs=$(CDPATH= cd -- "$path" && pwd)

        child_rc=0
        (
            cd "$path" || exit 1
            GIT_LEGO_ROOT=$root \
            GIT_LEGO_SUBPROJECT_PATH=$path \
            GIT_LEGO_SUBPROJECT_ABSPATH=$subproject_abs \
            GIT_LEGO_SUBPROJECT_REPO=$repo \
            GIT_LEGO_BRANCH=$branch \
            GIT_LEGO_TARGET_BRANCH=$target \
            GIT_LEGO_PENDING_BRANCH=$pending \
            GIT_LEGO_BASE_REVISION=$base \
            GIT_LEGO_PUSHED_COMMIT=$pushed \
            GIT_LEGO_REVISION=$revision \
            GIT_LEGO_TAG=$tag \
            REPO_PATH=$path \
            REPO_PROJECT=$path \
            "$@"
        ) || child_rc=$?
        if [ "$child_rc" -ne 0 ]; then
            [ "$rc" -ne 0 ] || rc=$child_rc
            [ "$continue_on_error" -eq 1 ] || break
        fi
        child_rc=0
    done <"$rows"

    return "$rc"
}

run_foreach_filtered() {
    mode=$1
    shift
    continue_on_error=0
    porcelain=0
    json=0
    json_pretty=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --continue-on-error) continue_on_error=1; shift ;;
            --porcelain) porcelain=1; shift ;;
            --json) json=1; shift ;;
            --json-pretty) json=1; json_pretty=1; shift ;;
            --) shift; break ;;
            --*) usage_error "unknown $mode option: $1" ;;
            *) break ;;
        esac
    done
    if [ "$porcelain" -eq 1 ] && [ "$json" -eq 1 ]; then
        usage_error "$mode cannot combine --porcelain with --json/--json-pretty"
    fi
    if { [ "$porcelain" -eq 1 ] || [ "$json" -eq 1 ]; } && [ $# -gt 0 ]; then
        usage_error "$mode machine-readable output cannot be combined with a command"
    fi

    rows=$(tmp_for "$MANIFEST_FILE.$mode")
    errors=$(tmp_for "$MANIFEST_FILE.$mode.errors")
    warnings=$(tmp_for "$MANIFEST_FILE.$mode.warnings")
    : >"$errors"
    : >"$warnings"
    foreach_filtered_rows "$mode" "$rows"

    if [ "$porcelain" -eq 1 ]; then
        cat "$rows"
        rm -f "$rows" "$errors" "$warnings"
        return 0
    fi
    if [ "$json" -eq 1 ]; then
        emit_json_result "$mode" 0 1 "$rows" "$errors" "$warnings" "$json_pretty"
        rm -f "$rows" "$errors" "$warnings"
        return 0
    fi

    [ $# -gt 0 ] || die "usage: git-lego $mode [--continue-on-error] [-- <command> [args...]]"
    run_foreach_filtered_command "$rows" "$continue_on_error" "$@"
    rc=$?
    rm -f "$rows" "$errors" "$warnings"
    return "$rc"
}

cmd_foreach_modified() {
    run_foreach_filtered foreach-modified "$@"
}

cmd_foreach_clean() {
    run_foreach_filtered foreach-clean "$@"
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

# Write a managed hook that calls snapshot --quiet from the outer workspace.
write_managed_hook() {
    write_hook_repo=$1
    write_hook_name=$2
    write_hook_outer_root=$3
    write_hook_git_lego_path=$4
    write_hook_file=$(hook_path_for "$write_hook_repo" "$write_hook_name")
    if [ -f "$write_hook_file" ] && ! grep -F '# git-lego managed hook' "$write_hook_file" >/dev/null 2>&1; then
        die "refusing to overwrite unmanaged hook: $write_hook_file"
    fi
    mkdir -p "$(dirname "$write_hook_file")"
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' '# git-lego managed hook'
        printf '%s\n' '[ "${GIT_LEGO_HOOK:-}" = "1" ] && exit 0'
        printf 'cd "%s" || exit 0\n' "$write_hook_outer_root"
        printf 'GIT_LEGO_HOOK=1 "%s" snapshot --quiet >/dev/null 2>&1 || true\n' "$write_hook_git_lego_path"
    } >"$write_hook_file"
    chmod +x "$write_hook_file" 2>/dev/null || true
}

# Report whether the project root already has the complete managed hook set.
managed_hooks_installed_in_repo() {
    managed_hooks_repo=$1
    git -C "$managed_hooks_repo" rev-parse --git-dir >/dev/null 2>&1 || return 1
    for managed_hooks_name in post-checkout post-commit pre-push; do
        managed_hooks_file=$(hook_path_for "$managed_hooks_repo" "$managed_hooks_name")
        [ -f "$managed_hooks_file" ] || return 1
        grep -F '# git-lego managed hook' "$managed_hooks_file" >/dev/null 2>&1 || return 1
    done
    return 0
}

# Install managed hooks in one repository when the outer project already uses them.
install_hooks_in_repo_if_project_managed() {
    install_hooks_repo=$1
    [ -d "$install_hooks_repo/.git" ] || return 0
    managed_hooks_installed_in_repo . || return 0
    install_hooks_outer_root=$(repo_root)
    install_hooks_outer_root=$(CDPATH= cd -- "$install_hooks_outer_root" && pwd)
    install_hooks_git_lego_path=$(CDPATH= cd -- "$(dirname -- "${0}")" && pwd)/git-lego
    preflight_managed_hook "$install_hooks_repo" post-checkout
    preflight_managed_hook "$install_hooks_repo" post-commit
    preflight_managed_hook "$install_hooks_repo" pre-push
    write_managed_hook "$install_hooks_repo" post-checkout "$install_hooks_outer_root" "$install_hooks_git_lego_path"
    write_managed_hook "$install_hooks_repo" post-commit "$install_hooks_outer_root" "$install_hooks_git_lego_path"
    write_managed_hook "$install_hooks_repo" pre-push "$install_hooks_outer_root" "$install_hooks_git_lego_path"
    printf 'Installed hooks in %s.\n' "$install_hooks_repo"
}

# Build the all-or-nothing hook target list: outer repo plus checked-out subprojects.
hook_targets_file() {
    out=$1
    : >"$out"
    printf '.\n' >>"$out"
    manifest_subprojects | while IFS= read -r path; do
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
    if [ -f "$preflight_hook_file" ] && ! grep -F '# git-lego managed hook' "$preflight_hook_file" >/dev/null 2>&1; then
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

# Install managed hooks in the outer repo and all checked-out subprojects.
install_hooks_all() {
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    outer_root=$(repo_root)
    outer_root=$(CDPATH= cd -- "$outer_root" && pwd)
    git_lego_path=$(CDPATH= cd -- "$(dirname -- "${0}")" && pwd)/git-lego
    targets=$(mktemp)
    hook_targets_file "$targets"

    # Preflight first so an unmanaged hook in any repo prevents partial install.
    preflight_hooks_all "$targets"
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        write_managed_hook "$repo" post-checkout "$outer_root" "$git_lego_path"
        write_managed_hook "$repo" post-commit "$outer_root" "$git_lego_path"
        write_managed_hook "$repo" pre-push "$outer_root" "$git_lego_path"
        printf 'Installed hooks in %s.\n' "$repo"
    done <"$targets"
    rm -f "$targets"
}

# Command wrapper for managed hook installation.
cmd_install_hooks() {
    [ $# -eq 0 ] || die "install-hooks takes no arguments"
    install_hooks_all
}

# Remove one hook only when it is git-lego managed.
remove_managed_hook() {
    repo=$1
    hook=$2
    hook_file=$(hook_path_for "$repo" "$hook")
    [ -f "$hook_file" ] || return 0
    if grep -F '# git-lego managed hook' "$hook_file" >/dev/null 2>&1; then
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

# Report pending subprojects and return nonzero as the outer-merge gate.
no_pending_rows() {
    manifest_subprojects | while IFS= read -r path; do
        pb=$(subproject_key "$path" pending_branch || true)
        [ -n "$pb" ] || continue
        printf 'P\t%s\tpending\t-\t%s\t-\tpending-branch\n' "$path" "$pb"
    done
}

cmd_no_pending() {
    json=0
    json_pretty=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) json=1; shift ;;
            --json-pretty) json=1; json_pretty=1; shift ;;
            *) usage_error "unknown no-pending option: $1" ;;
        esac
    done
    ensure_manifest
    rows=$(mktemp)
    no_pending_rows >"$rows"
    if [ "$json" -eq 1 ]; then
        errors=$(mktemp)
        warnings=$(mktemp)
        : >"$errors"
        : >"$warnings"
        [ -s "$rows" ] && ok=0 || ok=1
        emit_json_result no-pending 0 "$ok" "$rows" "$errors" "$warnings" "$json_pretty"
        rm -f "$errors" "$warnings"
        [ "$ok" -eq 1 ] || { rm -f "$rows"; return "$EXIT_ISSUES"; }
        rm -f "$rows"
        return 0
    fi
    while IFS='	' read -r code path state target current expected detail; do
        [ -n "$path" ] || continue
        printf '%s: pending branch %s\n' "$path" "$current"
    done <"$rows"
    if [ -s "$rows" ]; then
        rm -f "$rows"
        return "$EXIT_ISSUES"
    fi
    rm -f "$rows"
    printf 'No pending subprojects.\n'
}

# Delete one local pending branch after or after-deferred finalization cleanup.
cleanup_branch_for_subproject() {
    path=$1
    branch=$2
    [ -n "$branch" ] || return 0
    [ -d "$path/.git" ] || return 0
    if ! git -C "$path" show-ref --verify --quiet "refs/heads/$branch"; then
        warn "cleanup branch already absent for $path: $branch"
        manifest_remove_subproject_key "$path" finalized_from_branch
        return 0
    fi
    current=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    if [ "$current" = "$branch" ]; then
        revision=$(subproject_key "$path" revision || true)
        [ -n "$revision" ] || die "cannot clean current branch for $path without finalized revision"
        revision=$(resolve_commit "$path" "$revision" "cannot clean current branch for $path")
        git -C "$path" checkout --detach "$revision" >/dev/null ||
            die "failed to detach $path at finalized revision $revision"
    fi
    git -C "$path" branch -D "$branch" >/dev/null ||
        die "failed to delete local branch $branch in $path"
    manifest_remove_subproject_key "$path" finalized_from_branch
    printf 'Deleted local branch %s in %s.\n' "$branch" "$path"
}

# Delete all local branches recorded as finalized cleanup hints.
cmd_cleanup_branches() {
    [ $# -eq 0 ] || die "cleanup-branches takes no arguments"
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    manifest_subprojects | while IFS= read -r path; do
        branch=$(subproject_key "$path" finalized_from_branch || true)
        [ -n "$branch" ] || continue
        cleanup_branch_for_subproject "$path" "$branch"
    done
}

# Update one clean, non-pending subproject to another recorded version.
cmd_update() {
    [ $# -ge 1 ] || die "usage: git-lego update <subproject> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]"
    reject_backslash_path "$1"
    path=$(normalize_path "$1")
    shift
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$path"
    [ -d "$path/.git" ] || die "$path is not a checked-out subproject; run git-lego sync first"
    repo=$(subproject_repo "$path")
    [ -n "$repo" ] || die "$path is not in $MANIFEST_FILE"
    pending=$(subproject_key "$path" pending_branch || true)
    [ -z "$pending" ] || die "$path is pending on branch $pending; finalize or remove pending state before update"
    if repo_has_dirty "$path"; then
        die "$path has uncommitted changes; commit, stash, or discard them before update"
    fi

    update_target=$(subproject_key "$path" target_branch || true)
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
        die "--branch cannot be combined with --tag because tag-pinned subprojects do not record target_branch"
    fi

    update_tag=
    case "$update_mode" in
        revision)
            [ "$fetch" -eq 1 ] && fetch_quiet "$path"
            revision=$(resolve_commit "$path" "$update_value" "cannot update $path with --revision")
            git -C "$path" checkout "$revision" || die "failed to check out revision $revision in $path"
            manifest_write_subproject "$path" "$repo" tracked "$update_target" "$revision"
            ;;
        tag)
            [ "$fetch" -eq 1 ] && fetch_quiet "$path"
            update_tag=$update_value
            revision=$(resolve_commit "$path" "$update_tag" "cannot update $path with --tag")
            git -C "$path" checkout --detach "$revision" || die "failed to check out tag $update_tag in $path"
            manifest_write_subproject "$path" "$repo" finalized "$revision" "$update_tag"
            ;;
        target_head)
            revision=$(resolve_target_ref "$path" "$update_target" "$fetch")
            git -C "$path" checkout "$revision" || die "failed to check out target revision $revision in $path"
            manifest_write_subproject "$path" "$repo" tracked "$update_target" "$revision"
            ;;
    esac
    printf 'Updated %s to %.12s.\n' "$path" "$revision"
}

# Resolve a subproject target branch to a commit for --use-target-head finalization.
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
    ticket=$(manifest_get project id || true)
    [ -n "$ticket" ] || ticket=$(ticket_from_branch "$(subproject_key "$path" pending_branch || true)")
    [ -n "$ticket" ] || die "auto-finalize needs a project id; use --revision, --tag, or --use-target-head"
    base=$(subproject_key "$path" base_revision || true)
    [ "$GIT_LEGO_DRY_RUN" -eq 1 ] || fetch_quiet "$path"
    git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1 ||
        die "auto-finalize cannot find origin/$target for $path; fetch the subproject or use --revision/--tag"
    range=
    if [ -n "$base" ] && git -C "$path" cat-file -e "$base^{commit}" 2>/dev/null; then
        range="$base..origin/$target"
    else
        range="origin/$target"
    fi
    ticket_re=$(regex_escape "$ticket")
    matches=$(git -C "$path" log --format='%H %s' "$range" 2>/dev/null | grep -E "(^|[^A-Za-z0-9])$ticket_re([^0-9]|$)" || true)
    count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
    [ "$count" = "1" ] || die "auto-finalize found $count candidates for $ticket; use an explicit selector"
    revision=$(printf '%s\n' "$matches" | awk '{print $1}')
    require_value "$revision" "auto-finalize matched $ticket but produced an empty revision for $path; use --revision"
    resolve_commit "$path" "$revision" "cannot auto-finalize $path"
}

# Convert a subproject from pending to finalized state using an explicit or auto selector.
cmd_finalize() {
    [ $# -ge 1 ] || die "usage: git-lego finalize <subproject> [--dry-run] [--cleanup] [--revision <sha> | --tag <tag> | --use-target-head]"
    reject_backslash_path "$1"
    path=$(normalize_path "$1")
    shift

    mode=auto
    value=
    cleanup=0
    dry_run=0

    # Selectors are mutually exclusive so the manifest gets one clear source of
    # truth: explicit revision, explicit tag, target head, or conservative auto.
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                dry_run=1
                GIT_LEGO_DRY_RUN=1
                shift
                ;;
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

    [ "$dry_run" -eq 1 ] || acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$path"
    [ -d "$path/.git" ] || die "$path is not a checked-out subproject"
    repo=$(subproject_repo "$path")
    [ -n "$repo" ] || die "$path is not in $MANIFEST_FILE"
    target=$(subproject_key "$path" target_branch || true)
    [ -n "$target" ] || target=main

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
            if [ "$dry_run" -eq 1 ]; then
                remote_tmp=$(tmp_for "$MANIFEST_FILE.finalize_target")
                remote_revision=$(remote_branch_commit "$repo" "$target" "$remote_tmp" || true)
                rm -f "$remote_tmp"
                if [ -n "$remote_revision" ]; then
                    revision=$remote_revision
                else
                    revision=$(resolve_target_ref "$path" "$target" 0)
                fi
            else
                revision=$(resolve_target_ref "$path" "$target")
            fi
            ;;
        auto)
            if [ "$dry_run" -eq 1 ]; then
                if git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1; then
                    revision=$(auto_finalize_revision "$path" "$target")
                else
                    revision=unknown
                    printf '[dry-run] %s auto-finalize revision: unknown; real run would fetch first if needed\n' "$path"
                fi
            else
                revision=$(auto_finalize_revision "$path" "$target")
            fi
            ;;
    esac
    require_value "$revision" "finalize produced an empty revision for $path; use --revision <sha>"

    old_pending=$(subproject_key "$path" pending_branch || true)
    if [ "$dry_run" -eq 1 ]; then
        old_revision=$(subproject_key "$path" revision || true)
        old_tag=$(subproject_key "$path" tag || true)
        printf '[dry-run] %s revision: %s -> %s\n' "$path" "${old_revision:-<unset>}" "$revision"
        printf '[dry-run] %s tag: %s -> %s\n' "$path" "${old_tag:-<unset>}" "${tag:-<unset>}"
        if [ "$cleanup" -eq 1 ] && [ -n "$old_pending" ]; then
            printf '[dry-run] would delete local branch %s in %s\n' "$old_pending" "$path"
        fi
        return 0
    fi
    manifest_write_subproject "$path" "$repo" finalized "$revision" "$tag" "$old_pending"

    # Cleanup is local-only: remote review branches and untracked files are not
    # deleted by finalize.
    if [ "$cleanup" -eq 1 ] && [ -n "$old_pending" ]; then
        cleanup_branch_for_subproject "$path" "$old_pending"
    fi
    printf 'Finalized %s at %.12s.\n' "$path" "$revision"
}

# Clone/fetch subprojects and restore their pending or finalized manifest state.
sync_current() {
    prune=${1:-0}
    force=${2:-0}
    dry_run=${3:-0}
    ensure_manifest
    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.sync")
    failures_tmp=$(tmp_for "$MANIFEST_FILE.sync_failures")
    manifest_subprojects >"$subprojects_tmp"
    : >"$failures_tmp"
    rc=0

    if [ "$dry_run" -eq 1 ]; then
        if [ "$prune" -eq 1 ]; then
            printf '[dry-run] would reconcile stale subprojects with prune enabled\n'
        else
            printf '[dry-run] would inspect stale subprojects for reconciliation\n'
        fi
    else
        reconcile_stale_subprojects "$prune"
    fi

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if (
            repo=$(subproject_repo "$path")
            [ -n "$repo" ] || die "missing repo for $path"
            created=0
            clone_mode=$(effective_clone_mode "$path")
            pending=$(subproject_key "$path" pending_branch || true)
            tag=$(subproject_key "$path" tag || true)
            revision=$(subproject_key "$path" revision || true)
            target=$(subproject_key "$path" target_branch || true)
            [ -n "$target" ] || target=main
            if [ "$dry_run" -eq 1 ]; then
                if [ ! -d "$path/.git" ]; then
                    printf '[dry-run] would clone %s into %s using clone=%s\n' "$repo" "$path" "$clone_mode"
                else
                    printf '[dry-run] would fetch %s before sync\n' "$path"
                fi
                if [ -n "$pending" ]; then
                    printf '[dry-run] would check out pending branch %s in %s\n' "$pending" "$path"
                elif [ -n "$tag" ]; then
                    remote_tag=unknown
                    if [ -n "$revision" ]; then
                        tag_tmp=$(tmp_for "$MANIFEST_FILE.sync_tag")
                        remote_tag=$(remote_tag_commit "$repo" "$tag" "$tag_tmp" || printf 'unknown')
                        rm -f "$tag_tmp"
                        if [ "$remote_tag" != unknown ] && [ "$remote_tag" != "$revision" ] && [ "$force" -eq 0 ]; then
                            printf 'Error: tag/revision mismatch for %s\n' "$path" >&2
                            exit "$EXIT_ISSUES"
                        fi
                    fi
                    printf '[dry-run] would check out tag %s in %s (remote=%s)\n' "$tag" "$path" "$remote_tag"
                elif [ -n "$revision" ]; then
                    printf '[dry-run] would check out revision %s in %s\n' "$revision" "$path"
                elif [ ! -d "$path/.git" ] && [ "$clone_mode" = partial ]; then
                    printf '[dry-run] would check out target branch %s in %s after partial clone\n' "$target" "$path"
                else
                    printf '[dry-run] would leave checkout state unchanged for %s\n' "$path"
                fi
                exit 0
            fi
            if [ ! -d "$path/.git" ]; then
                clone_subproject "$repo" "$path" "$clone_mode" 1
                created=1
            fi
            if [ "$created" -eq 1 ]; then
                install_hooks_in_repo_if_project_managed "$path"
            fi
            fetch_quiet "$path"
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
                if [ -n "$revision" ]; then
                    tag_tmp=$(tmp_for "$MANIFEST_FILE.sync_tag")
                    remote_tag=$(remote_tag_commit "$repo" "$tag" "$tag_tmp" || true)
                    rm -f "$tag_tmp"
                    if [ -n "$remote_tag" ] && [ "$remote_tag" != "$revision" ]; then
                        if [ "$force" -eq 1 ]; then
                            warn "tag $tag for $path moved from $revision to $remote_tag; --force is proceeding"
                        else
                            printf 'Error: tag/revision mismatch for %s\n' "$path" >&2
                            printf '  tag: %s\n' "$tag" >&2
                            printf '  recorded revision: %s\n' "$revision" >&2
                            printf '  current remote SHA: %s\n' "$remote_tag" >&2
                            printf '  recovery: investigate the moved tag, then run git-lego update %s --tag %s to re-pin\n' "$path" "$tag" >&2
                            exit "$EXIT_ISSUES"
                        fi
                    fi
                fi
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
    done <"$subprojects_tmp"

    rm -f "$subprojects_tmp"
    if [ "$rc" -ne 0 ]; then
        printf 'Error: sync failed for one or more subprojects:\n' >&2
        while IFS= read -r path; do
            [ -n "$path" ] && printf '  %s\n' "$path" >&2
        done <"$failures_tmp"
        printf 'Recovery: review the error for each listed subproject, fix the manifest, remote access, or local checkout, then rerun git-lego sync. Run git-lego verify for a read-only consistency report.\n' >&2
        rm -f "$failures_tmp"
        return 1
    fi
    rm -f "$failures_tmp"
    [ "$dry_run" -eq 1 ] || write_materialized_state
}

# Recursively sync the current project and nested project roots.
sync_recursive() {
    label=$1
    visited=$2
    prune=${3:-0}
    force=${4:-0}
    dry_run=${5:-0}
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    printf 'Syncing project: %s\n' "$label"
    sync_current "$prune" "$force" "$dry_run" || return 1

    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.sync_recursive")
    manifest_subprojects >"$subprojects_tmp"
    rc=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_project_label "$label" "$path")
            (
                cd "$path" || exit 1
                sync_recursive "$child_label" "$visited" "$prune" "$force" "$dry_run"
            ) || rc=1
        fi
    done <"$subprojects_tmp"
    rm -f "$subprojects_tmp"
    return "$rc"
}

# Sync project state, optionally including nested projects.
cmd_sync() {
    recursive=0
    prune=0
    force=0
    dry_run=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --recursive) recursive=1; shift ;;
            --prune) prune=1; shift ;;
            --force) force=1; shift ;;
            --dry-run) dry_run=1; GIT_LEGO_DRY_RUN=1; shift ;;
            *) usage_error "unknown sync option: $1" ;;
        esac
    done
    if [ "$recursive" -eq 1 ]; then
        visited=$(mktemp)
        : >"$visited"
        sync_recursive "." "$visited" "$prune" "$force" "$dry_run"
        rc=$?
        rm -f "$visited"
        return "$rc"
    fi
    sync_current "$prune" "$force" "$dry_run"
    notice_nested_projects
}

doctor_add_check() {
    file=$1
    code=$2
    name=$3
    detail=$4
    printf '%s\t%s\t%s\n' "$code" "$name" "$detail" >>"$file"
}

doctor_code_to_status() {
    case "$1" in
        I) printf 'info\n' ;;
        W) printf 'warn\n' ;;
        E) printf 'error\n' ;;
        *) printf 'info\n' ;;
    esac
}

emit_doctor_json() {
    checks=$1
    ok=$2
    pretty=$3
    if [ "$pretty" -eq 1 ]; then
        compact=$(mktemp)
        emit_doctor_json "$checks" "$ok" 0 >"$compact"
        if command -v python >/dev/null 2>&1; then
            python -m json.tool "$compact"
        elif command -v python3 >/dev/null 2>&1; then
            python3 -m json.tool "$compact"
        else
            cat "$compact"
        fi
        rm -f "$compact"
        return
    fi
    printf '{"version":%s,"command":"doctor","recursive":false,"ok":' "$JSON_SCHEMA_VERSION"
    [ "$ok" -eq 1 ] && printf 'true' || printf 'false'
    printf ',"subprojects":[],"errors":[],"warnings":[],"checks":['
    first=1
    while IFS='	' read -r code name detail; do
        [ -n "$code" ] || continue
        [ "$first" -eq 1 ] || printf ','
        first=0
        printf '{"code":'
        json_string "$code"
        printf ',"name":'
        json_string "$name"
        printf ',"status":'
        json_string "$(doctor_code_to_status "$code")"
        printf ',"detail":'
        json_string "$detail"
        printf '}'
    done <"$checks"
    printf ']}'
}

doctor_hook_status() {
    repo=$1
    hook=$2
    hook_file=$(hook_path_for "$repo" "$hook" 2>/dev/null || true)
    [ -n "$hook_file" ] || { printf 'absent\n'; return; }
    [ -f "$hook_file" ] || { printf 'absent\n'; return; }
    if grep -F '# git-lego managed hook' "$hook_file" >/dev/null 2>&1; then
        printf 'installed\n'
    else
        printf 'unmanaged\n'
    fi
}

doctor_ls_remote() {
    repo=$1
    timeout_seconds=$2
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_seconds" git ls-remote --exit-code "$repo" HEAD >/dev/null 2>&1
    else
        git ls-remote --exit-code "$repo" HEAD >/dev/null 2>&1
    fi
}

cmd_doctor() {
    json=0
    json_pretty=0
    offline=0
    timeout_seconds=5
    use_exit_code=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) json=1; shift ;;
            --json-pretty) json=1; json_pretty=1; shift ;;
            --offline) offline=1; shift ;;
            --timeout)
                [ $# -ge 2 ] || usage_error "--timeout requires seconds"
                timeout_seconds=$2
                case "$timeout_seconds" in
                    *[!0-9]*|"") usage_error "--timeout requires a positive integer" ;;
                esac
                [ "$timeout_seconds" -gt 0 ] || usage_error "--timeout requires a positive integer"
                shift 2
                ;;
            --exit-code) use_exit_code=1; shift ;;
            *) usage_error "unknown doctor option: $1" ;;
        esac
    done

    require_git
    root=$(find_project_root 2>/dev/null || true)
    [ -n "$root" ] || precondition_error "not inside a git-lego workspace; run git-lego init or cd to a project"
    cd "$root" || die "cannot enter project root $root"

    checks=$(mktemp)
    : >"$checks"

    git_version=$(git --version 2>/dev/null | sed 's/^git version //')
    [ -n "$git_version" ] && doctor_add_check "$checks" I git-version "git $git_version; minimum supported version is 2.20" ||
        doctor_add_check "$checks" E git-version "git is not available"

    shell_name=${BASH_VERSION:+bash}
    [ -n "$shell_name" ] || shell_name=sh
    doctor_add_check "$checks" I shell "running under $shell_name"

    if [ -f "$MANIFEST_FILE" ]; then
        errors=$(tmp_for "$MANIFEST_FILE.doctor_schema")
        if ( validate_manifest_schema ) >"$errors" 2>&1; then
            doctor_add_check "$checks" I manifest "$MANIFEST_FILE is present and parseable"
        else
            detail=$(tr '\n' ' ' <"$errors" | sed 's/[[:space:]][[:space:]]*/ /g')
            doctor_add_check "$checks" E manifest "$detail"
        fi
        rm -f "$errors"
    else
        doctor_add_check "$checks" E manifest "$MANIFEST_FILE is missing"
    fi

    if [ -d "$MANIFEST_FILE.lock" ]; then
        pid=$(sed -n 's/^pid=//p' "$MANIFEST_FILE.lock/info" 2>/dev/null | sed -n '1p')
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            doctor_add_check "$checks" W lock "$MANIFEST_FILE.lock exists and pid $pid appears alive"
        else
            doctor_add_check "$checks" W lock "$MANIFEST_FILE.lock appears stale; remove it if no git-lego process is running"
        fi
    else
        doctor_add_check "$checks" I lock "no manifest lock present"
    fi

    if gitattributes_has_guard; then
        doctor_add_check "$checks" I gitattributes "git-lego attributes guard present"
    else
        doctor_add_check "$checks" W gitattributes "missing or stale git-lego attributes guard; run git-lego init to repair it"
    fi

    if [ -f .gitignore ]; then
        grep -F '.gitlego-extract-backup/' .gitignore >/dev/null 2>&1 &&
            doctor_add_check "$checks" I extract-backup-ignore ".gitlego-extract-backup/ ignored" ||
            doctor_add_check "$checks" I extract-backup-ignore ".gitlego-extract-backup/ ignore entry absent"
        grep -F '.gitlego-absorb-backup/' .gitignore >/dev/null 2>&1 &&
            doctor_add_check "$checks" I absorb-backup-ignore ".gitlego-absorb-backup/ ignored" ||
            doctor_add_check "$checks" I absorb-backup-ignore ".gitlego-absorb-backup/ ignore entry absent"
    else
        doctor_add_check "$checks" W gitignore ".gitignore is missing"
    fi

    for repo in . $(manifest_subprojects 2>/dev/null); do
        [ "$repo" = "." ] || [ -d "$repo/.git" ] || continue
        for hook in post-checkout post-commit pre-push; do
            status=$(doctor_hook_status "$repo" "$hook")
            case "$status" in
                unmanaged) code=W ;;
                *) code=I ;;
            esac
            doctor_add_check "$checks" "$code" "hook:$repo:$hook" "$status"
        done
    done

    if [ "$offline" -eq 1 ]; then
        doctor_add_check "$checks" I remotes "remote reachability skipped by --offline"
    else
        manifest_subprojects 2>/dev/null | while IFS= read -r path; do
            repo=$(subproject_repo "$path" || true)
            [ -n "$repo" ] || continue
            if doctor_ls_remote "$repo" "$timeout_seconds"; then
                doctor_add_check "$checks" I "remote:$path" "reachable"
            else
                doctor_add_check "$checks" W "remote:$path" "unreachable within ${timeout_seconds}s or authentication failed"
            fi
        done
    fi

    if command -v git-filter-repo >/dev/null 2>&1; then
        doctor_add_check "$checks" I git-filter-repo "available"
    else
        doctor_add_check "$checks" I git-filter-repo "not found; required only for extract --preserve-history"
    fi

    if grep -E '^(W|E)	' "$checks" >/dev/null 2>&1; then
        ok=0
    else
        ok=1
    fi

    if [ "$json" -eq 1 ]; then
        emit_doctor_json "$checks" "$ok" "$json_pretty"
    else
        while IFS='	' read -r code name detail; do
            [ -n "$code" ] && printf '%s\t%s\t%s\n' "$code" "$name" "$detail"
        done <"$checks"
    fi
    rm -f "$checks"
    if [ "$use_exit_code" -eq 1 ] && [ "$ok" -eq 0 ]; then
        return "$EXIT_ISSUES"
    fi
    return 0
}

git_lego_command_names() {
    printf '%s\n' "init add remove rm mv clone status outdated verify diff log start snapshot upload freeze install-hooks remove-hooks foreach foreach-pending foreach-modified foreach-clean no-pending config update finalize cleanup-branches sync doctor completion export extract absorb version"
}

# Internal completion data endpoint used by generated shell completion scripts.
cmd_internal_complete() {
    [ $# -eq 1 ] || usage_error "usage: git-lego __complete <commands|subprojects>"
    case "$1" in
        commands)
            git_lego_command_names
            ;;
        subprojects)
            if root=$(find_project_root 2>/dev/null); then
                (cd "$root" && manifest_subprojects)
            fi
            ;;
        *) usage_error "unknown completion data: $1" ;;
    esac
}

completion_bash() {
    cat <<'EOF'
_git_lego_complete()
{
    local cur cmd commands subprojects
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    commands="init add remove rm mv clone status outdated verify diff log start snapshot upload freeze install-hooks remove-hooks foreach foreach-pending foreach-modified foreach-clean no-pending config update finalize cleanup-branches sync doctor completion export extract absorb version"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi

    cmd="${COMP_WORDS[1]}"
    case "$cmd" in
        completion)
            COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") )
            ;;
        export)
            COMPREPLY=( $(compgen -W "--output --format --include-git --deterministic --allow-dirty tar.gz zip dir" -- "$cur") )
            ;;
        extract)
            COMPREPLY=( $(compgen -W "--branch --clone-mode --preserve-history --push --message --force --dry-run full partial" -- "$cur") )
            ;;
        absorb)
            subprojects="$(git-lego __complete subprojects 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$subprojects --commit --message --dry-run" -- "$cur") )
            ;;
        status)
            COMPREPLY=( $(compgen -W "--recursive --porcelain --json --json-pretty --exit-code" -- "$cur") )
            ;;
        outdated)
            COMPREPLY=( $(compgen -W "--recursive --porcelain --json --json-pretty" -- "$cur") )
            ;;
        verify)
            COMPREPLY=( $(compgen -W "--recursive --json --json-pretty" -- "$cur") )
            ;;
        sync)
            COMPREPLY=( $(compgen -W "--recursive --prune --force --dry-run" -- "$cur") )
            ;;
        doctor)
            COMPREPLY=( $(compgen -W "--json --json-pretty --offline --timeout --exit-code" -- "$cur") )
            ;;
        diff)
            COMPREPLY=( $(compgen -W "--since --stat --json --json-pretty" -- "$cur") )
            ;;
        log)
            COMPREPLY=( $(compgen -W "--max-count --since --until --subproject --oneline --recursive" -- "$cur") )
            ;;
        start)
            COMPREPLY=( $(compgen -W "--stash-dirty --discard-dirty --cancel-dirty --hooks --sure" -- "$cur") )
            ;;
        snapshot)
            COMPREPLY=( $(compgen -W "--recursive --quiet --dry-run --no-fetch --base" -- "$cur") )
            ;;
        upload)
            COMPREPLY=( $(compgen -W "--finalize --dry-run --no-fetch --base" -- "$cur") )
            ;;
        freeze)
            COMPREPLY=( $(compgen -W "--force --only --dry-run" -- "$cur") )
            ;;
        foreach-modified|foreach-clean)
            COMPREPLY=( $(compgen -W "--continue-on-error --porcelain --json --json-pretty --" -- "$cur") )
            ;;
        config)
            if [ "$COMP_CWORD" -eq 2 ]; then
                COMPREPLY=( $(compgen -W "get set list unset" -- "$cur") )
            elif [ "$COMP_CWORD" -eq 3 ] || { [ "${COMP_WORDS[2]}" = "list" ] && [ "$COMP_CWORD" -eq 3 ]; }; then
                subprojects="$(git-lego __complete subprojects 2>/dev/null)"
                COMPREPLY=( $(compgen -W "$subprojects" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "clone-mode full partial" -- "$cur") )
            fi
            ;;
        remove|rm|mv|update|finalize)
            subprojects="$(git-lego __complete subprojects 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$subprojects --force --keep-files --url --remote --target-head --revision --tag --branch --no-fetch --dry-run --cleanup --use-target-head" -- "$cur") )
            ;;
    esac
}

complete -F _git_lego_complete git-lego
EOF
}

completion_zsh() {
    cat <<'EOF'
#compdef git-lego

_git_lego()
{
    local -a commands subprojects
    commands=(init add remove rm mv clone status outdated verify diff log start snapshot upload freeze install-hooks remove-hooks foreach foreach-pending foreach-modified foreach-clean no-pending config update finalize cleanup-branches sync doctor completion export extract absorb version)

    if (( CURRENT == 2 )); then
        _describe 'git-lego command' commands
        return
    fi

    local cmd=${words[2]}
    case "$cmd" in
        completion)
            _arguments '1:shell:(bash zsh fish)'
            ;;
        export)
            _arguments '--output[write archive or directory]:path:_files' '--format[archive format]:format:(tar.gz zip dir)' '--include-git[keep .git directories]' '--deterministic[normalize archive metadata]' '--allow-dirty[allow dirty subprojects]'
            ;;
        extract)
            _arguments '1:path:_files -/' '2:remote-url:' '--branch[initial branch]:branch:' '--clone-mode[clone mode]:mode:(full partial)' '--preserve-history[preserve path history with git-filter-repo]' '--push[push extracted repository]' '--message[commit message]:message:' '--force[bypass metadata conflicts only]' '--dry-run[show planned changes]'
            ;;
        absorb)
            _arguments '1:subproject:__git_lego_subprojects' '--commit[commit staged outer changes]' '--message[commit message]:message:' '--dry-run[show planned changes]'
            ;;
        status)
            _arguments '--recursive[include nested projects]' '--porcelain[print fixed-column output]' '--json[print JSON]' '--json-pretty[print formatted JSON]' '--exit-code[return nonzero for dirty or missing rows]'
            ;;
        outdated)
            _arguments '--recursive[include nested projects]' '--porcelain[print fixed-column output]' '--json[print JSON]' '--json-pretty[print formatted JSON]'
            ;;
        verify)
            _arguments '--recursive[include nested projects]' '--json[print JSON]' '--json-pretty[print formatted JSON]'
            ;;
        sync)
            _arguments '--recursive[include nested projects]' '--prune[remove reviewed stale paths]' '--force[proceed past tag drift warnings]' '--dry-run[show planned actions without writing]'
            ;;
        doctor)
            _arguments '--json[print JSON]' '--json-pretty[print formatted JSON]' '--offline[skip remote checks]' '--timeout[remote timeout seconds]:seconds:' '--exit-code[return nonzero for warnings or errors]'
            ;;
        diff)
            _arguments '--since[read manifest from ref]:ref:' '--stat[include file statistics]' '--json[print JSON]' '--json-pretty[print formatted JSON]'
            ;;
        log)
            _arguments '--max-count[count]:count:' '--since[date]:date:' '--until[date]:date:' '--subproject[path]:subproject:' '--oneline[compact output]' '--recursive[include nested projects]'
            ;;
        start)
            _arguments '--stash-dirty[stash dirty repositories]' '--discard-dirty[discard tracked edits]' '--cancel-dirty[fail on dirty repositories]' '--hooks[install managed hooks]' '--sure[confirm noninteractive startup]'
            ;;
        snapshot)
            _arguments '--recursive[include nested projects]' '--quiet[suppress dirty skip warnings]' '--dry-run[show planned changes without writing]' '--no-fetch[use local refs]' '--base[set explicit base]:subproject=ref:'
            ;;
        upload)
            _arguments '--finalize[pin pushed commits directly]' '--dry-run[show planned pushes without writing]' '--no-fetch[use local refs]' '--base[set explicit base]:subproject=ref:'
            ;;
        freeze)
            _arguments '--force[freeze dirty subprojects]' '--only[limit paths]:paths:' '--dry-run[show changes without writing]'
            ;;
        foreach-modified|foreach-clean)
            _arguments '--continue-on-error[keep iterating after failures]' '--porcelain[print fixed-column output]' '--json[print JSON]' '--json-pretty[print formatted JSON]'
            ;;
        config)
            subprojects=("${(@f)$(_call_program subprojects git-lego __complete subprojects 2>/dev/null)}")
            _arguments '1:action:(get set list unset)' '2:subproject:->subproject' '3:key:(clone-mode)' '4:value:(full partial)'
            if [[ $state == subproject ]]; then
                _describe 'subproject' subprojects
            fi
            ;;
        remove|rm|mv|update|finalize)
            subprojects=("${(@f)$(_call_program subprojects git-lego __complete subprojects 2>/dev/null)}")
            _describe 'subproject' subprojects
            ;;
    esac
}

_git_lego "$@"
EOF
}

completion_fish() {
    cat <<'EOF'
function __git_lego_subprojects
    git-lego __complete subprojects 2>/dev/null
end

complete -c git-lego -f -n "__fish_use_subcommand" -a "init add remove rm mv clone status outdated verify diff log start snapshot upload freeze install-hooks remove-hooks foreach foreach-pending foreach-modified foreach-clean no-pending config update finalize cleanup-branches sync doctor completion export extract absorb version"
complete -c git-lego -f -n "__fish_seen_subcommand_from completion" -a "bash zsh fish"
complete -c git-lego -f -n "__fish_seen_subcommand_from export" -a "--output --format --include-git --deterministic --allow-dirty tar.gz zip dir"
complete -c git-lego -f -n "__fish_seen_subcommand_from extract" -a "--branch --clone-mode --preserve-history --push --message --force --dry-run full partial"
complete -c git-lego -f -n "__fish_seen_subcommand_from absorb" -a "--commit --message --dry-run"
complete -c git-lego -f -n "__fish_seen_subcommand_from status" -a "--recursive --porcelain --json --json-pretty --exit-code"
complete -c git-lego -f -n "__fish_seen_subcommand_from outdated" -a "--recursive --porcelain --json --json-pretty"
complete -c git-lego -f -n "__fish_seen_subcommand_from verify" -a "--recursive --json --json-pretty"
complete -c git-lego -f -n "__fish_seen_subcommand_from sync" -a "--recursive --prune --force --dry-run"
complete -c git-lego -f -n "__fish_seen_subcommand_from doctor" -a "--json --json-pretty --offline --timeout --exit-code"
complete -c git-lego -f -n "__fish_seen_subcommand_from diff" -a "--since --stat --json --json-pretty"
complete -c git-lego -f -n "__fish_seen_subcommand_from log" -a "--max-count --since --until --subproject --oneline --recursive"
complete -c git-lego -f -n "__fish_seen_subcommand_from start" -a "--stash-dirty --discard-dirty --cancel-dirty --hooks --sure"
complete -c git-lego -f -n "__fish_seen_subcommand_from snapshot" -a "--recursive --quiet --dry-run --no-fetch --base"
complete -c git-lego -f -n "__fish_seen_subcommand_from upload" -a "--finalize --dry-run --no-fetch --base"
complete -c git-lego -f -n "__fish_seen_subcommand_from freeze" -a "--force --only --dry-run"
complete -c git-lego -f -n "__fish_seen_subcommand_from foreach-modified" -a "--continue-on-error --porcelain --json --json-pretty"
complete -c git-lego -f -n "__fish_seen_subcommand_from foreach-clean" -a "--continue-on-error --porcelain --json --json-pretty"
complete -c git-lego -f -n "__fish_seen_subcommand_from config" -a "get set list unset clone-mode full partial"
complete -c git-lego -f -n "__fish_seen_subcommand_from remove rm mv update finalize config" -a "(__git_lego_subprojects)"
EOF
}

# Print shell completion scripts.
cmd_completion() {
    [ $# -eq 1 ] || usage_error "usage: git-lego completion <bash|zsh|fish>"
    case "$1" in
        bash) completion_bash ;;
        zsh) completion_zsh ;;
        fish) completion_fish ;;
        *) usage_error "unknown completion shell: $1" ;;
    esac
}

infer_export_format() {
    output=$1
    case "$output" in
        *.tar.gz|*.tgz) printf 'tar.gz\n' ;;
        *.zip) printf 'zip\n' ;;
        */) printf 'dir\n' ;;
        *)
            base=$(basename -- "$output")
            case "$base" in
                *.*) usage_error "cannot infer export format from $output; use --format" ;;
                *) printf 'dir\n' ;;
            esac
            ;;
    esac
}

validate_export_format() {
    case "$1" in
        tar.gz|zip|dir) ;;
        *) usage_error "--format must be tar.gz, zip, or dir" ;;
    esac
}

absolute_output_path() {
    output=$1
    case "$output" in
        /*) printf '%s\n' "$output" ;;
        ?:/*) printf '%s\n' "$output" ;;
        *)
            dir=$(dirname -- "$output")
            base=$(basename -- "$output")
            mkdir -p "$dir" || git_error "failed to create output parent $dir"
            printf '%s/%s\n' "$(CDPATH= cd -- "$dir" && pwd)" "$base"
            ;;
    esac
}

ensure_clean_subprojects_for_export() {
    dirty_file=$1
    : >"$dirty_file"
    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -d "$path/.git" ] || continue
        if repo_has_dirty "$path"; then
            printf '%s\n' "$path" >>"$dirty_file"
        fi
    done
}

write_export_manifest_lock() {
    stage=$1
    deterministic=$2
    lock_file=$stage/MANIFEST.lock
    if [ "$deterministic" -eq 1 ]; then
        created="1970-01-01T00:00:00Z"
    else
        created=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)
    fi
    {
        printf '[export]\n'
        printf 'version=1\n'
        printf 'created=%s\n' "$created"
        printf 'tool=git-lego %s\n' "$GIT_LEGO_VERSION"
        printf '\n'
        manifest_subprojects | while IFS= read -r path; do
            [ -n "$path" ] || continue
            repo=$(subproject_repo "$path" || true)
            [ -n "$repo" ] || continue
            [ -d "$path/.git" ] || continue
            revision=$(resolve_head_commit "$path" "cannot export $path")
            branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
            tag=$(subproject_key "$path" tag || true)
            printf '[subproject "%s"]\n' "$path"
            printf 'repo=%s\n' "$repo"
            printf 'revision=%s\n' "$revision"
            [ -n "$branch" ] && printf 'branch=%s\n' "$branch"
            [ -n "$tag" ] && printf 'tag=%s\n' "$tag"
            printf '\n'
        done
    } >"$lock_file"
}

path_has_export_ignore() {
    repo=$1
    rel=$2
    git -C "$repo" check-attr export-ignore -- "$rel" 2>/dev/null |
        grep ': export-ignore: set$' >/dev/null 2>&1
}

copy_file_to_stage() {
    src=$1
    dst=$2
    dst_dir=$(dirname -- "$dst")
    mkdir -p "$dst_dir" || git_error "failed to create export directory $dst_dir"
    cp -p "$src" "$dst" || git_error "failed to copy $src"
}

copy_subproject_files_to_stage() {
    path=$1
    stage=$2
    include_git=$3
    git -C "$path" ls-files -c -o --exclude-standard | while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        [ -f "$path/$rel" ] || continue
        path_has_export_ignore "$path" "$rel" && continue
        copy_file_to_stage "$path/$rel" "$stage/$path/$rel"
    done
    if [ "$include_git" -eq 1 ] && [ -e "$path/.git" ]; then
        mkdir -p "$stage/$path" || git_error "failed to create export directory $stage/$path"
        cp -R "$path/.git" "$stage/$path/.git" || git_error "failed to copy $path/.git"
    fi
}

stage_export_tree() {
    stage=$1
    include_git=$2
    deterministic=$3
    copy_file_to_stage "$MANIFEST_FILE" "$stage/$MANIFEST_FILE"
    write_export_manifest_lock "$stage" "$deterministic"
    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ ! -d "$path/.git" ]; then
            precondition_error "cannot export missing subproject $path; run git-lego sync"
        fi
        copy_subproject_files_to_stage "$path" "$stage" "$include_git"
    done
}

make_deterministic_stage() {
    stage=$1
    find "$stage" -exec touch -h -t 198001010000.00 {} + 2>/dev/null ||
        find "$stage" -exec touch -t 198001010000.00 {} +
}

write_tar_export() {
    stage=$1
    output=$2
    deterministic=$3
    rm -f "$output"
    if [ "$deterministic" -eq 1 ]; then
        (cd "$stage" && GZIP=-n tar --sort=name --mtime='UTC 1980-01-01' --owner=0 --group=0 --numeric-owner -czf "$output" .) ||
            git_error "failed to write deterministic tar.gz export $output"
    else
        (cd "$stage" && tar -czf "$output" .) ||
            git_error "failed to write tar.gz export $output"
    fi
}

write_zip_export() {
    stage=$1
    output=$2
    deterministic=$3
    python_cmd=$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)
    [ -n "$python_cmd" ] || precondition_error "zip export requires python or python3"
    rm -f "$output"
    (cd "$stage" && "$python_cmd" - "$output" "$deterministic" <<'PY'
import os
import stat
import sys
import zipfile

output = sys.argv[1]
deterministic = sys.argv[2] == "1"
entries = []
for root, dirs, files in os.walk("."):
    dirs.sort()
    files.sort()
    for name in files:
        path = os.path.join(root, name)
        arc = path[2:] if path.startswith("./") else path
        entries.append((path, arc.replace(os.sep, "/")))

with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for path, arc in entries:
        if deterministic:
            info = zipfile.ZipInfo(arc, (1980, 1, 1, 0, 0, 0))
            mode = os.stat(path).st_mode
            info.external_attr = ((mode & 0o777) | stat.S_IFREG) << 16
            with open(path, "rb") as fh:
                zf.writestr(info, fh.read(), compress_type=zipfile.ZIP_DEFLATED)
        else:
            zf.write(path, arc)
PY
    ) || git_error "failed to write zip export $output"
}

write_dir_export() {
    stage=$1
    output=$2
    [ ! -e "$output" ] || precondition_error "output directory already exists: $output"
    mkdir -p "$output" || git_error "failed to create export directory $output"
    cp -R "$stage/." "$output/" || git_error "failed to write directory export $output"
}

# Export a source/archive snapshot of tracked subprojects.
cmd_export() {
    output=
    format=
    include_git=0
    deterministic=0
    allow_dirty=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --output)
                [ $# -ge 2 ] || usage_error "--output requires a path"
                output=$2
                shift 2
                ;;
            --format)
                [ $# -ge 2 ] || usage_error "--format requires tar.gz, zip, or dir"
                format=$2
                validate_export_format "$format"
                shift 2
                ;;
            --include-git) include_git=1; shift ;;
            --deterministic) deterministic=1; shift ;;
            --allow-dirty) allow_dirty=1; shift ;;
            *) usage_error "unknown export option: $1" ;;
        esac
    done
    [ -n "$output" ] || usage_error "export requires --output <path>"
    ensure_manifest
    validate_manifest_schema
    [ -n "$format" ] || format=$(infer_export_format "$output")
    validate_export_format "$format"
    output_abs=$(absolute_output_path "$output")

    dirty_file=$(tmp_for "$MANIFEST_FILE.export_dirty")
    ensure_clean_subprojects_for_export "$dirty_file"
    if [ "$allow_dirty" -eq 0 ] && [ -s "$dirty_file" ]; then
        printf 'Error: dirty subprojects block export:\n' >&2
        while IFS= read -r path; do
            [ -n "$path" ] && printf '  %s\n' "$path" >&2
        done <"$dirty_file"
        rm -f "$dirty_file"
        printf 'Use --allow-dirty to export the working tree anyway.\n' >&2
        return "$EXIT_PRECONDITION"
    fi
    rm -f "$dirty_file"

    stage=$(mktemp -d "${TMPDIR:-/tmp}/git-lego-export.XXXXXX") ||
        die "cannot create temporary export staging directory"
    stage_export_tree "$stage" "$include_git" "$deterministic"
    if [ "$deterministic" -eq 1 ]; then
        make_deterministic_stage "$stage"
    fi

    case "$format" in
        tar.gz) write_tar_export "$stage" "$output_abs" "$deterministic" ;;
        zip) write_zip_export "$stage" "$output_abs" "$deterministic" ;;
        dir) write_dir_export "$stage" "$output_abs" ;;
    esac
    rm -rf "$stage"
    printf 'Exported workspace to %s.\n' "$output_abs"
}

backup_timestamp() {
    date -u '+%Y%m%dT%H%M%SZ'
}

ensure_backup_ignored() {
    ensure_gitignore_line ".gitlego-absorb-backup/"
}

copy_path_backup() {
    src=$1
    dst=$2
    mkdir -p "$(dirname -- "$dst")" || git_error "failed to create backup parent for $dst"
    cp -R "$src" "$dst" || git_error "failed to back up $src to $dst"
}

extract_preserve_history_repo() {
    path=$1
    branch=$2
    remote_url=$3
    tmp_parent=$4
    if ! command -v git-filter-repo >/dev/null 2>&1; then
        precondition_error "extract --preserve-history requires git-filter-repo; install it from https://github.com/newren/git-filter-repo and rerun"
    fi
    filtered=$tmp_parent/filtered
    git clone --no-hardlinks . "$filtered" >/dev/null 2>&1 ||
        git_error "failed to clone outer repository for history-preserving extract"
    (
        cd "$filtered" || exit 1
        git-filter-repo --path "$path/" --path-rename "$path/": --force >/dev/null 2>&1 ||
            git_error "git-filter-repo failed while extracting $path"
        git branch -M "$branch" || git_error "failed to rename extracted branch to $branch"
        git remote remove origin >/dev/null 2>&1 || true
        git remote add origin "$remote_url" || git_error "failed to set extracted origin"
    )
    rm -rf -- "$path" || git_error "failed to replace $path with extracted repository"
    cp -R "$filtered" "$path" || git_error "failed to install extracted repository at $path"
}

extract_snapshot_repo() {
    path=$1
    branch=$2
    remote_url=$3
    message=$4
    outer_user_name=$(git config user.name 2>/dev/null || true)
    outer_user_email=$(git config user.email 2>/dev/null || true)
    (
        cd "$path" || exit 1
        git init -b "$branch" >/dev/null 2>&1 || {
            git init >/dev/null
            git checkout -b "$branch" >/dev/null
        }
        [ -z "$outer_user_name" ] || git config user.name "$outer_user_name"
        [ -z "$outer_user_email" ] || git config user.email "$outer_user_email"
        git remote add origin "$remote_url" || git_error "failed to set origin for $path"
        git add -A || git_error "failed to stage extracted files in $path"
        git commit --allow-empty -m "$message" >/dev/null ||
            git_error "failed to create initial extract commit in $path"
    )
}

cmd_extract() {
    branch=main
    clone_mode=
    preserve_history=0
    push_after=0
    message=
    force=0
    dry_run=0
    path_arg=
    repo_arg=
    while [ $# -gt 0 ]; do
        case "$1" in
            --branch)
                [ $# -ge 2 ] || usage_error "--branch requires a name"
                branch=$2
                shift 2
                ;;
            --clone-mode)
                [ $# -ge 2 ] || usage_error "--clone-mode requires full or partial"
                clone_mode=$2
                validate_clone_mode "$clone_mode" "--clone-mode"
                shift 2
                ;;
            --preserve-history) preserve_history=1; shift ;;
            --push) push_after=1; shift ;;
            --message)
                [ $# -ge 2 ] || usage_error "--message requires text"
                message=$2
                shift 2
                ;;
            --force) force=1; shift ;;
            --dry-run) dry_run=1; shift ;;
            --*) usage_error "unknown extract option: $1" ;;
            *)
                if [ -z "$path_arg" ]; then
                    path_arg=$1
                elif [ -z "$repo_arg" ]; then
                    repo_arg=$1
                else
                    usage_error "usage: git-lego extract <path> <remote-url> [options]"
                fi
                shift
                ;;
        esac
    done
    [ -n "$path_arg" ] && [ -n "$repo_arg" ] || usage_error "usage: git-lego extract <path> <remote-url> [options]"
    reject_backslash_path "$path_arg"
    path=$(normalize_path "$path_arg")
    [ -n "$message" ] || message="Extract $path"

    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$path"
    assert_path_not_containing_nested_project "$path"
    [ -d "$path" ] || precondition_error "$path is not a directory"
    [ ! -d "$path/.git" ] || precondition_error "$path is already a Git repository"
    [ -z "$(subproject_repo "$path" || true)" ] || precondition_error "$path is already a tracked subproject"
    if ! git ls-files -- "$path" | sed -n '1p' | grep . >/dev/null 2>&1; then
        precondition_error "$path has no tracked outer-repository files to extract; commit these files in the outer repo first, then rerun extract"
    fi
    staged_under_path=$(git diff --cached --name-only -- "$path" 2>/dev/null | sed -n '1p')
    if [ -n "$staged_under_path" ] && [ "$force" -eq 0 ]; then
        precondition_error "$path has staged outer-repository changes; review them or rerun extract with --force to replace that staged state"
    fi

    if [ "$dry_run" -eq 1 ]; then
        printf 'Would extract %s to %s on branch %s.\n' "$path" "$repo_arg" "$branch"
        [ "$push_after" -eq 1 ] && printf 'Would push %s to origin/%s.\n' "$path" "$branch"
        return 0
    fi
    unstaged_under_path=$(git diff --name-only -- "$path" 2>/dev/null | sed -n '1p')
    [ -z "$unstaged_under_path" ] || precondition_error "$path has unstaged content changes; commit these files in the outer repo first, then rerun extract"
    untracked_under_path=$(git ls-files --others --exclude-standard -- "$path" 2>/dev/null | sed -n '1p')
    [ -z "$untracked_under_path" ] || precondition_error "$path has untracked files; commit these files in the outer repo first, then rerun extract"
    if [ "$preserve_history" -eq 1 ] && ! command -v git-filter-repo >/dev/null 2>&1; then
        precondition_error "extract --preserve-history requires git-filter-repo; install it from https://github.com/newren/git-filter-repo and rerun"
    fi
    if [ "$push_after" -eq 1 ]; then
        remote_refs=$(mktemp)
        if ! git ls-remote "$repo_arg" >"$remote_refs" 2>/dev/null; then
            rm -f "$remote_refs"
            precondition_error "cannot reach extract remote $repo_arg"
        fi
        if [ -s "$remote_refs" ]; then
            rm -f "$remote_refs"
            precondition_error "extract remote $repo_arg is not empty; overriding non-empty remotes is deliberately not implemented"
        fi
        rm -f "$remote_refs"
    fi

    ensure_gitignore_hygiene
    tmp_parent=$(mktemp -d "${TMPDIR:-/tmp}/git-lego-extract.XXXXXX") ||
        die "cannot create extract temporary directory"
    if [ "$preserve_history" -eq 1 ]; then
        ensure_gitignore_line ".gitlego-extract-backup/"
        backup=".gitlego-extract-backup/$(basename -- "$path")-$(backup_timestamp)"
        copy_path_backup "$path" "$backup"
        extract_preserve_history_repo "$path" "$branch" "$repo_arg" "$tmp_parent"
    else
        backup=
        extract_snapshot_repo "$path" "$branch" "$repo_arg" "$message"
    fi
    rm -rf "$tmp_parent"
    if [ "$push_after" -eq 1 ]; then
        git -C "$path" push -u origin "$branch" || git_error "failed to push extracted subproject $path"
        pushed_remote=$(git ls-remote "$repo_arg" "refs/heads/$branch" 2>/dev/null | awk 'NR == 1 { print $1 }')
        local_head=$(resolve_head_commit "$path" "cannot resolve extracted subproject $path")
        [ "$pushed_remote" = "$local_head" ] ||
            git_error "pushed branch $branch on $repo_arg did not resolve to expected commit"
    fi
    revision=$(resolve_head_commit "$path" "cannot resolve extracted subproject $path")
    git rm -r --cached -- "$path" >/dev/null 2>&1 ||
        git_error "failed to untrack extracted files from outer repository"
    ensure_gitignore_entry "$path"
    manifest_write_subproject "$path" "$repo_arg" tracked "$branch" "$revision" "$clone_mode"
    write_materialized_state
    stage_outer_paths "$MANIFEST_FILE" .gitignore
    if [ -n "$backup" ]; then
        rm -rf -- "$backup"
        rmdir .gitlego-extract-backup 2>/dev/null || true
    fi
    printf 'Extracted %s as a git-lego subproject at %.12s.\n' "$path" "$revision"
    if [ "$push_after" -eq 0 ]; then
        printf 'Push when ready with: git -C %s push -u origin %s\n' "$path" "$branch"
    fi
}

cmd_absorb() {
    commit_after=0
    message=
    dry_run=0
    path_arg=
    while [ $# -gt 0 ]; do
        case "$1" in
            --commit) commit_after=1; shift ;;
            --message)
                [ $# -ge 2 ] || usage_error "--message requires text"
                message=$2
                commit_after=1
                shift 2
                ;;
            --dry-run) dry_run=1; shift ;;
            --*) usage_error "unknown absorb option: $1" ;;
            *)
                [ -z "$path_arg" ] || usage_error "usage: git-lego absorb <path> [options]"
                path_arg=$1
                shift
                ;;
        esac
    done
    [ -n "$path_arg" ] || usage_error "usage: git-lego absorb <path> [options]"
    reject_backslash_path "$path_arg"
    path=$(normalize_path "$path_arg")
    [ -n "$message" ] || message="Absorb subproject $path"

    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$path"
    [ -d "$path/.git" ] || precondition_error "$path is not a checked-out subproject"
    [ ! -f "$path/$MANIFEST_FILE" ] || precondition_error "$path is a nested git-lego project; recursive absorb is not supported yet"
    repo=$(subproject_repo "$path" || true)
    [ -n "$repo" ] || precondition_error "$path is not a tracked subproject in $MANIFEST_FILE"
    reason=$(stale_subproject_safety_reason "$path")
    [ -z "$reason" ] || precondition_error "$path $reason; push or remove local-only work before absorb"

    if [ "$dry_run" -eq 1 ]; then
        printf 'Would absorb %s into the outer repository and leave remote %s untouched.\n' "$path" "$repo"
        [ "$commit_after" -eq 1 ] && printf 'Would commit outer changes with message: %s\n' "$message"
        return 0
    fi

    ensure_backup_ignored
    backup=".gitlego-absorb-backup/$(basename -- "$path")-$(backup_timestamp)"
    mkdir -p "$backup" || git_error "failed to create absorb backup $backup"
    cp -R "$path/.git" "$backup/.git" || git_error "failed to back up $path/.git"
    rm -rf -- "$path/.git" || git_error "failed to remove nested Git metadata from $path"
    manifest_remove_section "$(subproject_section "$path")"
    remove_gitignore_entry "$path"
    write_materialized_state
    stage_outer_paths "$MANIFEST_FILE" .gitignore "$path"
    if [ "$commit_after" -eq 1 ]; then
        git commit -m "$message" ||
            git_error "failed to commit absorbed subproject $path; staged files remain and backup is in $backup. Fix the commit problem and run git commit, or restore $backup/.git to $path/.git and revert the staged manifest changes"
    fi
    rm -rf -- "$backup"
    rmdir .gitlego-absorb-backup 2>/dev/null || true
    printf 'Absorbed %s into the outer repository; remote %s was not changed.\n' "$path" "$repo"
}

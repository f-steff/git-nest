#!/bin/sh
#
# git-nest 0.8.2
#
# Lightweight multi-repository workspace coordination for ordinary Git remotes.
# A project root repository tracks a manifest of nested subproject repositories,
# while this script provides the command behavior for initializing, restoring,
# snapshotting, and verifying that workspace state.
#
# This file is the shared shell implementation sourced by bin/git-nest.
# Keeping command logic here leaves the PATH-facing entrypoint tiny while
# avoiding a separate lib/ tree for a small script-first project. The Windows
# wrapper reaches this code indirectly by launching bin/git-nest through
# Git Bash.
#
# Copyright (c) 2026 Flemming Steffensen.
# License: MIT
# SPDX-License-Identifier: MIT

MANIFEST_FILE=${GIT_NEST_MANIFEST:-.gitnest}
CONFIG_FILE=${GIT_NEST_CONFIG:-.gitnest-rc}
BRANCH_MARKS_FILE=${GIT_NEST_BRANCH_MARKS:-.gitnest-branches}
PUSH_CANDIDATES_FILE=${GIT_NEST_PUSH_CANDIDATES:-.gitnest-push-candidates}
GIT_NEST_VERSION=0.8.2
GIT_NEST_LOCK_TIMEOUT_SECONDS=${GIT_NEST_LOCK_TIMEOUT_SECONDS:-10}
GIT_NEST_DOCTOR_TIMEOUT_SECONDS=${GIT_NEST_DOCTOR_TIMEOUT_SECONDS:-5}
MANIFEST_SCHEMA_VERSION=1
JSON_SCHEMA_VERSION=1
GITATTRIBUTES_GUARD='.gitnest text eol=lf'
GITATTRIBUTES_BEGIN='# BEGIN git-nest attributes'
GITATTRIBUTES_END='# END git-nest attributes'
GITIGNORE_GIT_DIR_GUARD_ONE='**/.git/'
GITIGNORE_GIT_DIR_GUARD_TWO='**/.git'
GITIGNORE_BEGIN='# BEGIN git-nest ignores'
GITIGNORE_END='# END git-nest ignores'
RECOVERY_BACKUP_PREFIX='.gitnest-recovery'
OLD_HOOK_WARNING_PRINTED=0
MANIFEST_LOCK_HELD=
MANIFEST_LOCK_PATH=
GIT_NEST_EXIT_HANDLER_INSTALLED=0
GIT_NEST_NO_FETCH=0
GIT_NEST_BASE_OVERRIDES=
GIT_NEST_DRY_RUN=0
GIT_NEST_JSON_DRY_RUN=0

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

validate_positive_integer() {
    vpi_value=$1
    vpi_name=$2
    case "$vpi_value" in
        *[!0-9]*|"") usage_error "$vpi_name requires a positive integer" ;;
    esac
    [ "$vpi_value" -gt 0 ] || usage_error "$vpi_name requires a positive integer"
}

cleanup_manifest_lock() {
    if [ -n "$MANIFEST_LOCK_HELD" ] && [ -n "$MANIFEST_LOCK_PATH" ]; then
        rm -rf "$MANIFEST_LOCK_PATH" 2>/dev/null || true
        MANIFEST_LOCK_HELD=
    fi
}

install_exit_handler() {
    [ "$GIT_NEST_EXIT_HANDLER_INSTALLED" -eq 0 ] || return 0
    trap 'status=$?; cleanup_manifest_lock; exit $status' EXIT
    trap 'cleanup_manifest_lock; trap - INT; kill -INT $$' INT
    trap 'cleanup_manifest_lock; trap - TERM; kill -TERM $$' TERM
    GIT_NEST_EXIT_HANDLER_INSTALLED=1
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
    validate_positive_integer "$GIT_NEST_LOCK_TIMEOUT_SECONDS" GIT_NEST_LOCK_TIMEOUT_SECONDS
    MANIFEST_LOCK_PATH=$MANIFEST_FILE.lock
    lock_timeout_ms=$((GIT_NEST_LOCK_TIMEOUT_SECONDS * 1000))
    delay=50
    waited=0
    while [ "$waited" -lt "$lock_timeout_ms" ]; do
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
    printf 'Error: could not acquire manifest lock %s after %s seconds\n' "$MANIFEST_LOCK_PATH" "$GIT_NEST_LOCK_TIMEOUT_SECONDS" >&2
    printf '  lock pid: %s\n' "$pid" >&2
    printf '  lock created UTC: %s\n' "$created" >&2
    printf '  if no git-nest process is using it, remove it with: rm -rf %s\n' "$MANIFEST_LOCK_PATH" >&2
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
    if [ "$GIT_NEST_JSON_DRY_RUN" -eq 1 ]; then
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

# Emit the shared JSON envelope for a mutating command as a single-row result.
# absorb, inline, detach, and remove use this so their machine output stays on
# the same schema as the inspection commands instead of inventing new shapes.
json_single_row_result() {
    jsr_pretty=$1
    jsr_command=$2
    jsr_ok=$3
    jsr_code=$4
    jsr_path=$5
    jsr_state=$6
    jsr_target=$7
    jsr_current=$8
    jsr_expected=$9
    shift 9
    jsr_detail=${1:-}
    # Build a one-line porcelain row and reuse the standard emitter and its
    # temp-file contract so dry-run and escaping behavior stay identical.
    jsr_rows=$(mktemp)
    jsr_empty=$(mktemp)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$jsr_code" "$jsr_path" "$jsr_state" "$jsr_target" "$jsr_current" "$jsr_expected" "$jsr_detail" >"$jsr_rows"
    emit_json_result "$jsr_command" 0 "$jsr_ok" "$jsr_rows" "$jsr_empty" "$jsr_empty" "$jsr_pretty"
    rm -f "$jsr_rows" "$jsr_empty"
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

# Set help color escapes. Output stays plain when stdout is not a terminal,
# TERM is dumb, or NO_COLOR/GIT_NEST_NO_COLOR is set.
help_setup_colors() {
    HELP_RESET=
    HELP_BOLD=
    HELP_DIM=
    HELP_SECTION=
    HELP_CMD=
    HELP_OPT=
    HELP_ARG=

    case "${GIT_NEST_COLOR:-auto}" in
        never|no|0|false) return 0 ;;
        always|yes|1|true) use_color=1 ;;
        *)
            use_color=0
            [ -t 1 ] && use_color=1
            [ "${TERM:-}" = dumb ] && use_color=0
            [ -n "${NO_COLOR:-}" ] && use_color=0
            [ -n "${GIT_NEST_NO_COLOR:-}" ] && use_color=0
            ;;
    esac
    [ "$use_color" -eq 1 ] || return 0

    esc=$(printf '\033')
    HELP_RESET="${esc}[0m"
    HELP_BOLD="${esc}[1m"
    HELP_DIM="${esc}[2m"
    HELP_SECTION="${esc}[1;36m"
    HELP_CMD="${esc}[32m"
    HELP_OPT="${esc}[33m"
    HELP_ARG="${esc}[36m"
}

help_title() {
    printf '%s%s%s\n\n' "$HELP_BOLD" "$1" "$HELP_RESET"
}

help_heading() {
    printf '%s%s%s\n' "$HELP_SECTION" "$1" "$HELP_RESET"
}

help_usage_group() {
    printf '\n  %s%s%s\n' "$HELP_BOLD" "$1" "$HELP_RESET"
}

help_usage() {
    printf '    %sgit-nest%s %s%s%s' "$HELP_DIM" "$HELP_RESET" "$HELP_CMD" "$1" "$HELP_RESET"
    [ -n "${2:-}" ] && printf ' %s' "$2"
    printf '\n'
}

help_command_group() {
    printf '\n  %s%s%s\n' "$HELP_BOLD" "$1" "$HELP_RESET"
}

help_command() {
    printf '    %s%s%s\n' "$HELP_CMD" "$1" "$HELP_RESET"
}

help_text() {
    printf '        %s\n' "$1"
}

help_detail() {
    printf '            %s\n' "$1"
}

# Show the command surface exposed by the shared implementation.
usage() {
    help_setup_colors
    help_title "git-nest: record and restore reproducible nests of independent Git repositories"

    help_heading "Usage:"
    help_usage_group "Nest setup"
    help_usage "init" "[--rc] [--sure]"
    help_usage "repair" "[--rc]"
    help_usage "clone" "<nest-repo-url> [target-dir] [--no-restore] [--depth <n>] [--branch <branch>] [--single-branch]"

    help_usage_group "Subprojects"
    help_usage "add" "[--clone <full|partial>] <repo> <path>"
    help_usage "remove|rm" "<path> [--force] [--dry-run] [--json|--json-pretty]"
    help_usage "detach" "<path> [--dry-run] [--json|--json-pretty]"
    help_usage "move|mv" "<old-path> <new-path> [--force]"
    help_usage "move|mv" "--url <new-url> <path>"
    help_usage "config" "<get|set|list|unset> ..."
    help_usage "update" "<subproject> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]"

    help_usage_group "Workspace state"
    help_usage "restore" "[--recursive] [--prune] [--force] [--dry-run]"
    help_usage "snapshot" "[<path>] [--recursive] [--quiet] [--dry-run] [--check] [--strict] [--no-fetch]"
    help_usage "freeze" "[--force] [--only <path>[,<path>...]] [--dry-run]"

    help_usage_group "Inspection"
    help_usage "status" "[--recursive] [--porcelain | --json | --json-pretty] [--exit-code]"
    help_usage "outdated" "[--recursive] [--porcelain | --json | --json-pretty]"
    help_usage "verify" "[--recursive] [--json | --json-pretty]"
    help_usage "diff" "[--since <ref>] [--stat] [--json | --json-pretty]"
    help_usage "log" "[--max-count <n>] [--since <date>] [--until <date>] [--subproject <path>] [--oneline] [--recursive]"
    help_usage "list" "[--porcelain | --json | --json-pretty]"
    help_usage "discover" "[--max-depth <n>] [--exclude <name>]... [--porcelain | --json | --json-pretty]"
    help_usage "doctor" "[--json | --json-pretty] [--offline] [--timeout <seconds>] [--exit-code]"

    help_usage_group "Branch bookmarks"
    help_usage "branch-mark" "[name]"
    help_usage "branch-unmark" "<name>"
    help_usage "branch-list" "[--verbose|--json]"
    help_usage "branch-cleanup"

    help_usage_group "Hooks"
    help_usage "hooks-install"
    help_usage "hooks-uninstall"

    help_usage_group "Iteration"
    help_usage "foreach" "-- <command> [args...]"
    help_usage "foreach-modified" "[--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"
    help_usage "foreach-clean" "[--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"

    help_usage_group "Export and nest membership"
    help_usage "export" "--output <path> [--format <tar.gz|zip|dir>] [--include-git] [--deterministic] [--allow-dirty]"
    help_usage "absorb" "<path> [<remote-url>] [--branch <name>] [--clone-mode <full|partial>] [--preserve-history] [--push] [--message <msg>] [--force] [--dry-run] [--json|--json-pretty]"
    help_usage "inline" "<path> [--commit] [--message <msg>] [--dry-run] [--json|--json-pretty]"

    help_usage_group "Tooling"
    help_usage "completion" "<bash|zsh|fish>"
    help_usage "version"

    printf '\n'
    help_heading "Commands:"
    help_command_group "Nest setup"
    help_command "init [--rc]"
    help_text "Create a new .gitnest manifest at the current Git root or directory."
    help_detail "--rc also creates .gitnest-rc with default values."
    help_detail "--sure allows intentional nested-nest creation inside an existing nest."
    help_detail "Existing nest roots are reported as already initialized; use repair to refresh support files."
    help_command "repair [--rc]"
    help_text "Repair managed support files for the current nest."
    help_detail "Can be run from anywhere inside the nest."
    help_command "clone <nest-repo-url> [target-dir] [--no-restore] [--depth <n>] [--branch <branch>] [--single-branch]"
    help_text "Run git clone for a nest repository and restore when it has a manifest."
    help_detail "Convenience wrapper around git clone plus git-nest restore."
    help_detail "It does not copy an existing local checkout."
    help_detail "--no-restore skips the automatic restore."

    help_command_group "Subprojects"
    help_command "add [--clone <full|partial>] <repo> <path>"
    help_text "Add and clone a subproject, ignore its path in the outer repo, and"
    help_text "record its current target branch and revision."
    help_detail "<path> is relative to the current nest root; . is not valid here."
    help_detail "--clone selects full or partial clone storage for this subproject."
    help_detail "This clone mode is used by restore and is unrelated to the clone command."
    help_command "remove|rm <path> [--force] [--dry-run] [--json|--json-pretty]"
    help_text "Remove a subproject from the nest and delete its checkout on disk."
    help_detail "<path> is a managed subproject path relative to the current nest root."
    help_detail "--force skips dirty/current-branch safety checks."
    help_detail "The remote is never touched; to keep the checkout use detach instead."
    help_command "detach <path> [--dry-run] [--json|--json-pretty]"
    help_text "Remove a subproject from the nest but keep its checkout as a standalone repo."
    help_detail "<path> is a managed subproject path relative to the current nest root."
    help_detail "Keeps the files and the ignore entry; the remote is never touched."
    help_command "move|mv <old-path> <new-path> [--force]"
    help_text "Move a subproject path while preserving manifest state."
    help_detail "Both paths are relative to the current nest root; . is not valid here."
    help_detail "--force skips dirty/current-branch safety checks."
    help_command "move|mv --url <new-url> <path>"
    help_text "Change a subproject repository URL in the manifest only."
    help_detail "<path> is a managed subproject path relative to the current nest root."
    help_command "config <get|set|list|unset> ..."
    help_text "Read or update allowlisted manifest settings."
    help_detail "Subproject paths are relative to the current nest root."
    help_detail "Only clone-mode is currently configurable; values are full or partial."
    help_detail "clone-mode controls future restore clones, not the clone command."
    help_detail "config list shows explicitly set config values only."
    help_command "update <subproject> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]"
    help_text "Move one clean subproject to a selected revision."
    help_detail "<subproject> is a managed path in the current nest; . is not valid here."
    help_detail "--remote and --target-head use the target branch head."
    help_detail "--revision pins an explicit commit-ish."
    help_detail "--tag pins a tag and records the tag name."
    help_detail "--branch retargets before resolving the selected revision."
    help_detail "--no-fetch resolves only local refs."

    help_command_group "Workspace state"
    help_command "restore [--recursive] [--prune] [--force] [--dry-run]"
    help_text "Clone/fetch subprojects and restore the manifest state on disk."
    help_detail "Operates on the whole current nest; it does not accept a path."
    help_detail "--recursive includes nested projects."
    help_detail "--prune removes stale local-state paths after review when suggested."
    help_detail "--force proceeds when a tag moved away from the recorded revision."
    help_detail "--dry-run prints planned clone/fetch/checkout/prune actions without writing."
    help_command "snapshot [<path>] [--recursive] [--quiet] [--dry-run] [--check] [--strict] [--no-fetch]"
    help_text "Record clean, reproducible checked-out subproject commits in .gitnest."
    help_detail "No path snapshots all subprojects in the current nest."
    help_detail "At the nest root, . also means all subprojects."
    help_detail "Inside a managed subproject, . means that subproject only."
    help_detail "An explicit path may name a managed subproject or a path inside one."
    help_detail "--recursive includes nested projects."
    help_detail "--quiet suppresses skip warnings for dirty subprojects."
    help_detail "--dry-run prints planned manifest changes without writing."
    help_detail "--check reports stale state without writing."
    help_detail "--strict returns nonzero for dirty or unreproducible subprojects."
    help_detail "--no-fetch uses local refs only."
    help_command "freeze [--force] [--only <path>[,<path>...]] [--dry-run]"
    help_text "Pin tracked subprojects to their current checkout commits."
    help_detail "Without --only, freezes every tracked subproject in the current nest."
    help_detail "--force freezes dirty subprojects with warnings."
    help_detail "--only limits freezing to a comma-separated path list."
    help_detail "--dry-run prints what would change without writing."

    help_command_group "Inspection"
    help_command "status [--recursive] [--porcelain | --json | --json-pretty] [--exit-code]"
    help_text "Show nest root and subproject state."
    help_detail "--recursive includes nested projects."
    help_detail "--porcelain prints stable fixed-column records for scripts."
    help_detail "--json and --json-pretty print machine-readable output."
    help_detail "--exit-code returns 1 when dirty or missing rows exist."
    help_command "outdated [--recursive] [--porcelain | --json | --json-pretty]"
    help_text "Check subproject remotes for newer target-branch commits without fetching."
    help_detail "--recursive includes nested projects."
    help_detail "--porcelain prints stable fixed-column records for scripts."
    help_detail "--json and --json-pretty print machine-readable output."
    help_command "verify [--recursive] [--json | --json-pretty]"
    help_text "Validate manifest, remotes, refs, clone mode, and checked-out revisions."
    help_detail "--recursive includes nested projects."
    help_detail "--json and --json-pretty print machine-readable output."
    help_command "diff [--since <ref>] [--stat] [--json | --json-pretty]"
    help_text "Show subproject commits between manifest revisions and current checkouts."
    help_detail "--since reads manifest revisions from the outer repo at ref."
    help_detail "--stat includes file statistics in human output."
    help_detail "--json and --json-pretty print machine-readable commit rows."
    help_command "log [--max-count <n>] [--since <date>] [--until <date>] [--subproject <path>] [--oneline] [--recursive]"
    help_text "Show combined nest history. Filters mirror common git log concepts;"
    help_detail "--max-count limits commits per repository before the final sort."
    help_detail "--since and --until filter commits by date."
    help_detail "--subproject restricts output to one subproject path."
    help_detail "--oneline uses compact commit output."
    help_detail "--recursive includes nested projects."
    help_command "list [--porcelain | --json | --json-pretty]"
    help_text "List managed subprojects with URL, target branch, revision, tag, state, and reproducibility."
    help_detail "Stable order for scripts; --porcelain and --json/--json-pretty print machine-readable output."
    help_command "discover [--max-depth <n>] [--exclude <name>]... [--porcelain | --json | --json-pretty]"
    help_text "Scan for nested Git repositories and submodules not managed by .gitnest."
    help_detail "Bounded by --max-depth (default 4) and pruned by default and extra --exclude directory names."
    help_detail "Discovery only; it never adds, syncs, or registers anything."
    help_command "doctor [--json | --json-pretty] [--offline] [--timeout <seconds>] [--exit-code]"
    help_text "Report environment and workspace health without modifying files."
    help_detail "Can be run from anywhere inside the nest."
    help_detail "Remote checks default to GIT_NEST_DOCTOR_TIMEOUT_SECONDS or 5 seconds."

    help_command_group "Branch bookmarks"
    help_command "branch-mark|branch-unmark|branch-list|branch-cleanup"
    help_text "Manage local branch-name memory for the current nest. These commands do"
    help_text "not create, switch, push, or delete Git branches."
    help_detail "branch-mark with no name uses the current Git branch."
    help_detail "Marks are stored in .gitnest-branches and ignored by Git."

    help_command_group "Hooks"
    help_command "hooks-install"
    help_text "Install managed local Git hooks in all checked-out repositories in the current nest."
    help_detail "Includes the nest root and checked-out subprojects; it is not recursive into nested nests."
    help_command "hooks-uninstall"
    help_text "Remove managed local Git hooks from all checked-out repositories in the current nest."

    help_command_group "Iteration"
    help_command "foreach -- <command> [args...]"
    help_text "Run a command in every checked-out subproject in the current nest."
    help_command "foreach-modified [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"
    help_text "Run a command in dirty subprojects, or list them with machine output."
    help_command "foreach-clean [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"
    help_text "Run a command in clean checked-out subprojects, or list them with machine output."

    help_command_group "Export and outer-repo conversion"
    help_command "export --output <path> [--format <tar.gz|zip|dir>] [--include-git] [--deterministic] [--allow-dirty]"
    help_text "Export a source snapshot with .gitnest and MANIFEST.lock."
    help_detail "dir output uses shell file copy; tar.gz requires system tar; zip requires python or python3."
    help_detail "--format overrides output extension inference."
    help_detail "--include-git keeps nested .git directories."
    help_detail "--deterministic normalizes archive ordering and metadata where supported."
    help_detail "--allow-dirty permits dirty subproject working trees."
    help_command "absorb <path> [<remote-url>] [options]"
    help_text "Bring something already on disk into the nest as a managed subproject."
    help_detail "Auto-detects the source: outer-repo tracked files, a standalone nested repo, or a submodule."
    help_detail "Outer-repo files require a remote URL and support --branch, --clone-mode, --preserve-history, --push, --message, and --force."
    help_detail "An existing repo or submodule keeps its own history and records its own remote."
    help_detail "Refuses a path that is already a subproject and refuses deeper nested repos/submodules."
    help_detail "--dry-run reports planned changes without writing; --json/--json-pretty print machine output."
    help_command "inline <path> [options]"
    help_text "Dissolve a managed subproject into the outer repo as ordinary tracked files."
    help_detail "This removes the subproject from the current nest and stages its files in the nest root."
    help_detail "--commit commits the staged outer-repo changes."
    help_detail "--message sets the commit message and implies --commit."
    help_detail "--dry-run reports planned changes without writing; --json/--json-pretty print machine output."

    help_command_group "Tooling"
    help_command "completion <bash|zsh|fish>"
    help_text "Print a shell completion script to stdout."
    help_command "version"
    help_text "Print the git-nest version."

    printf '\nManifest: %s\n' "$MANIFEST_FILE"
}

help_example() {
    printf '        %s%s%s\n' "$HELP_DIM" "$1" "$HELP_RESET"
}

help_opposite() {
    printf '        Opposite: %s\n' "$1"
}

command_help_branch_bookmarks() {
    help_command "branch-mark [name]"
    help_command "branch-unmark <name>"
    help_command "branch-list [--verbose|--json]"
    help_command "branch-cleanup"
    help_text "Branch bookmarks remember useful branch names for the current nest."
    help_text "They do not create, switch, push, delete, or otherwise manage Git branches."
    help_text "They are local helper state for humans and scripts that want to reuse the"
    help_text "same branch name in more than one repository."
    help_detail "branch-mark with no name records the current Git branch for the current repository."
    help_detail "branch-unmark removes one remembered branch name for the current repository."
    help_detail "branch-list shows remembered names and, with --verbose, the origin repository path."
    help_detail "branch-cleanup removes bookmarks whose local Git branch no longer exists."
    help_detail "Bookmarks are stored in .gitnest-branches and ignored by Git."
    help_heading "Examples:"
    help_example "git switch -c feature/cache"
    help_example "git-nest branch-mark"
    help_example "git-nest branch-list --verbose"
    help_example "git-nest branch-unmark feature/cache"
}

command_help() {
    topic=$1
    case "$topic" in
        rm) topic=remove ;;
        mv) topic=move ;;
        sync) topic=restore ;;
        install-hooks) topic=hooks-install ;;
        remove-hooks) topic=hooks-uninstall ;;
        extract) topic=absorb ;;
    esac

    help_setup_colors
    help_title "git-nest help: $topic"

    case "$topic" in
        init)
            help_command "init [--rc] [--sure]"
            help_text "Create a new .gitnest manifest at the current Git root or current directory."
            help_text "Plain init is creation-only. Use repair for an existing nest."
            help_detail "--rc also creates .gitnest-rc with default values."
            help_detail "--sure confirms intentional nested-nest creation inside an existing nest."
            help_heading "Examples:"
            help_example "git init"
            help_example "git-nest init"
            help_example "git-nest init --rc"
            help_example "git-nest init --sure"
            help_opposite "repair refreshes support files for a nest that already exists."
            ;;
        repair)
            help_command "repair [--rc]"
            help_text "Refresh managed support files for the current nest without creating a new nest."
            help_text "Can be run from anywhere inside the nest."
            help_detail "Refreshes files such as .gitattributes and managed ignore entries."
            help_detail "--rc also creates or refreshes .gitnest-rc defaults."
            help_heading "Examples:"
            help_example "git-nest repair"
            help_example "git-nest repair --rc"
            help_opposite "init creates a new nest when one does not already exist."
            ;;
        clone)
            help_command "clone <nest-repo-url> [target-dir] [--no-restore] [--depth <n>] [--branch <branch>] [--single-branch]"
            help_text "Run git clone for a nest repository, then restore it when .gitnest exists."
            help_detail "This is a convenience wrapper around git clone plus git-nest restore."
            help_detail "It does not copy an existing local checkout."
            help_detail "--no-restore leaves subprojects missing until restore is run manually."
            help_detail "--depth, --branch, and --single-branch are passed to the outer git clone."
            help_heading "Examples:"
            help_example "git-nest clone https://example.invalid/product.git"
            help_example "git-nest clone https://example.invalid/product.git product --branch main"
            help_example "git-nest clone https://example.invalid/product.git --no-restore"
            help_opposite "restore materializes subprojects after an ordinary git clone."
            ;;
        add)
            help_command "add [--clone <full|partial>] <repo> <path>"
            help_text "Add and clone a subproject into the current nest."
            help_detail "<path> is relative to the current nest root; . is not valid."
            help_detail "The path is ignored by the outer repository so files stay owned by the subproject."
            help_detail "--clone records full or partial clone preference for future restore."
            help_detail "This clone mode is unrelated to the clone command."
            help_heading "Examples:"
            help_example "git-nest add https://example.invalid/libs/foo.git libs/foo"
            help_example "git-nest add --clone partial https://example.invalid/libs/big.git libs/big"
            help_opposite "remove/rm removes a managed subproject from the nest."
            ;;
        remove)
            help_command "remove|rm <path> [--force] [--dry-run] [--json|--json-pretty]"
            help_text "Remove a managed subproject from the nest and delete its checkout on disk."
            help_detail "<path> is relative to the current nest root."
            help_detail "--force skips dirty/current-branch safety checks."
            help_detail "The remote is never touched. To keep the checkout, use detach instead."
            help_heading "Examples:"
            help_example "git-nest remove libs/foo"
            help_example "git-nest remove libs/foo --force"
            help_example "git-nest remove libs/foo --dry-run"
            help_opposite "add records and clones a subproject into the nest."
            ;;
        detach)
            help_command "detach <path> [--dry-run] [--json|--json-pretty]"
            help_text "Remove a managed subproject from the nest but keep its checkout as a standalone repo."
            help_detail "<path> is relative to the current nest root."
            help_detail "Keeps the files on disk and keeps the ignore entry; the remote is never touched."
            help_detail "Does not rebuild a submodule/subtree/subrepo; it only guarantees a standalone repo remains."
            help_heading "Examples:"
            help_example "git-nest detach libs/foo"
            help_example "git-nest detach libs/foo --dry-run"
            help_opposite "absorb brings an existing repository into the nest."
            ;;
        move)
            help_command "move|mv <old-path> <new-path> [--force]"
            help_command "move|mv --url <new-url> <path>"
            help_text "Move a managed subproject path, or retarget its recorded URL."
            help_detail "Paths are relative to the current nest root; . is not valid."
            help_detail "Path moves update the checkout location, .gitnest, and ignore hygiene."
            help_detail "--url changes only the manifest URL and does not move files."
            help_heading "Examples:"
            help_example "git-nest move libs/foo components/foo"
            help_example "git-nest mv libs/foo components/foo --force"
            help_example "git-nest move --url https://example.invalid/new/foo.git components/foo"
            help_opposite "remove/rm detaches a subproject instead of moving it."
            ;;
        config)
            help_command "config <get|set|list|unset> ..."
            help_text "Read or update allowlisted manifest settings."
            help_detail "Subproject paths are relative to the current nest root."
            help_detail "Only clone-mode is currently configurable."
            help_detail "clone-mode values are full or partial."
            help_detail "clone-mode controls future restore clones, not the clone command."
            help_detail "config list shows explicitly set config values only."
            help_detail "Unknown keys such as repo are rejected for get, set, and unset."
            help_heading "Examples:"
            help_example "git-nest config list"
            help_example "libs/foo    clone-mode=partial"
            help_example "git-nest config get libs/foo clone-mode"
            help_example "partial"
            help_example "git-nest config set libs/foo clone-mode partial"
            help_example "git-nest config unset libs/foo clone-mode"
            help_example "git-nest config unset libs/foo repo"
            help_example "Error: unknown config key: repo"
            ;;
        update)
            help_command "update <subproject> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]"
            help_text "Move one clean managed subproject to a selected revision."
            help_detail "<subproject> is relative to the current nest root; . is not valid."
            help_detail "--remote and --target-head use the target branch head."
            help_detail "--revision pins an explicit commit-ish."
            help_detail "--tag pins a tag and records the tag name."
            help_detail "--branch retargets before resolving the selected revision."
            help_heading "Examples:"
            help_example "git-nest update libs/foo --remote"
            help_example "git-nest update libs/foo --revision abc1234"
            help_example "git-nest update libs/foo --tag v1.2.3"
            help_opposite "restore returns subprojects to the manifest state instead of advancing one."
            ;;
        restore)
            help_command "restore [--recursive] [--prune] [--force] [--dry-run]"
            help_text "Clone, fetch, and check out the manifest state on disk."
            help_detail "Operates on the whole current nest; it does not accept a path."
            help_detail "--recursive includes nested nests."
            help_detail "--prune removes reviewed stale local-state paths."
            help_detail "--force proceeds when a tag moved away from the recorded revision."
            help_detail "--dry-run shows planned clone/fetch/checkout/prune actions."
            help_heading "Examples:"
            help_example "git-nest restore"
            help_example "git-nest restore --dry-run"
            help_example "git-nest restore --recursive"
            help_opposite "snapshot records the current reproducible checkout state into .gitnest."
            ;;
        snapshot)
            help_command "snapshot [<path>] [--recursive] [--quiet] [--dry-run] [--check] [--strict] [--no-fetch]"
            help_text "Record clean, reproducible checked-out subproject commits in .gitnest."
            help_detail "No path snapshots all subprojects in the current nest."
            help_detail "At the nest root, . also means all subprojects."
            help_detail "Inside a managed subproject, . means that subproject only."
            help_detail "An explicit path may name a managed subproject or a path inside one."
            help_detail "--check reports stale state without writing."
            help_detail "--strict returns nonzero for dirty or unreproducible subprojects."
            help_heading "Examples:"
            help_example "git-nest snapshot"
            help_example "git-nest snapshot ."
            help_example "git-nest snapshot libs/foo --dry-run"
            help_example "git-nest snapshot --check --strict"
            help_opposite "restore materializes the recorded manifest state on disk."
            ;;
        freeze)
            help_command "freeze [--force] [--only <path>[,<path>...]] [--dry-run]"
            help_text "Pin tracked subprojects to their current checkout commits."
            help_detail "Without --only, freezes every tracked subproject in the current nest."
            help_detail "--only limits freezing to a comma-separated path list."
            help_detail "--force freezes dirty subprojects with warnings."
            help_heading "Examples:"
            help_example "git-nest freeze"
            help_example "git-nest freeze --only libs/foo,libs/bar"
            help_example "git-nest freeze --dry-run"
            help_opposite "update moves one subproject to a selected remote/tag/revision."
            ;;
        status)
            help_command "status [--recursive] [--porcelain | --json | --json-pretty] [--exit-code]"
            help_text "Show nest root and subproject state."
            help_detail "--recursive includes nested nests."
            help_detail "--porcelain prints stable fixed-column records for scripts."
            help_detail "--json and --json-pretty print machine-readable output."
            help_detail "--exit-code returns 1 when dirty or missing rows exist."
            help_heading "Examples:"
            help_example "git-nest status"
            help_example "git-nest status --recursive"
            help_example "git-nest status --porcelain --exit-code"
            ;;
        outdated)
            help_command "outdated [--recursive] [--porcelain | --json | --json-pretty]"
            help_text "Check subproject remotes for newer target-branch commits without changing checkouts."
            help_detail "--recursive includes nested nests."
            help_detail "This is an inspection command; use update when you choose to move a subproject."
            help_heading "Examples:"
            help_example "git-nest outdated"
            help_example "git-nest outdated --recursive"
            help_example "git-nest outdated --json-pretty"
            help_opposite "update performs a selected subproject move after inspection."
            ;;
        verify)
            help_command "verify [--recursive] [--json | --json-pretty]"
            help_text "Validate manifest entries, remotes, refs, clone mode, and checkout drift."
            help_detail "--recursive includes nested nests."
            help_heading "Examples:"
            help_example "git-nest verify"
            help_example "git-nest verify --recursive"
            help_example "git-nest verify --json-pretty"
            ;;
        diff)
            help_command "diff [--since <ref>] [--stat] [--json | --json-pretty]"
            help_text "Show subproject commits between manifest revisions and current checkouts."
            help_detail "--since reads manifest revisions from the outer repo at ref."
            help_detail "--stat includes file statistics in human output."
            help_heading "Examples:"
            help_example "git-nest diff"
            help_example "git-nest diff --since HEAD~1"
            help_example "git-nest diff --stat"
            ;;
        log)
            help_command "log [--max-count <n>] [--since <date>] [--until <date>] [--subproject <path>] [--oneline] [--recursive]"
            help_text "Show combined nest history across the nest root and checked-out subprojects."
            help_detail "--subproject restricts output to one subproject path."
            help_detail "--recursive includes nested nests."
            help_heading "Examples:"
            help_example "git-nest log --max-count 10"
            help_example "git-nest log --subproject libs/foo --oneline"
            help_example "git-nest log --recursive --since 2026-01-01"
            ;;
        doctor)
            help_command "doctor [--json | --json-pretty] [--offline] [--timeout <seconds>] [--exit-code]"
            help_text "Report environment and workspace health without modifying files."
            help_detail "Can be run from anywhere inside the nest."
            help_detail "--offline skips remote reachability checks."
            help_detail "--timeout overrides GIT_NEST_DOCTOR_TIMEOUT_SECONDS for remote checks."
            help_detail "--exit-code returns nonzero when warnings or errors are present."
            help_heading "Examples:"
            help_example "git-nest doctor --offline"
            help_example "git-nest doctor --timeout 20"
            help_example "git-nest doctor --json-pretty"
            ;;
        list)
            help_command "list [--porcelain | --json | --json-pretty]"
            help_text "List managed subprojects in a stable order with their recorded and on-disk state."
            help_detail "Shows path, repository URL, target branch, revision, tag, checkout state, and reproducibility."
            help_detail "The leading code is reproducibility: R reproducible, D drift, M missing, U unpinned."
            help_detail "--porcelain prints fixed-column records; --json/--json-pretty print machine-readable output."
            help_heading "Examples:"
            help_example "git-nest list"
            help_example "git-nest list --porcelain"
            help_example "git-nest list --json-pretty"
            help_detail "status stays focused on workspace health; use list for a scriptable inventory."
            ;;
        discover)
            help_command "discover [--max-depth <n>] [--exclude <name>]... [--porcelain | --json | --json-pretty]"
            help_text "Scan the current nest for nested Git repositories and submodules not in .gitnest."
            help_detail "--max-depth bounds the scan depth (default 4)."
            help_detail "--exclude adds directory names to the default prune list; it may be repeated."
            help_detail "The leading code is the kind: S submodule, R nested repo, N nested nest root."
            help_detail "Discovery only; it never adds, syncs, or registers repositories. Symlinked directories are not followed."
            help_heading "Examples:"
            help_example "git-nest discover"
            help_example "git-nest discover --max-depth 6 --exclude third_party"
            help_example "git-nest discover --porcelain"
            help_opposite "absorb brings a discovered repository into the nest."
            ;;
        branch-mark|branch-unmark|branch-list|branch-cleanup)
            command_help_branch_bookmarks
            ;;
        hooks-install)
            help_command "hooks-install"
            help_text "Install managed local Git hooks in all checked-out repositories in the current nest."
            help_detail "Includes the nest root and checked-out subprojects."
            help_detail "Does not accept --recursive; nested nests manage their own hooks."
            help_detail "Refuses to overwrite unmanaged hooks."
            help_heading "Examples:"
            help_example "git-nest hooks-install"
            help_example "git-nest doctor --offline"
            help_opposite "hooks-uninstall removes the managed local hooks."
            ;;
        hooks-uninstall)
            help_command "hooks-uninstall"
            help_text "Remove managed local Git hooks from all checked-out repositories in the current nest."
            help_detail "Only git-nest-owned hook blocks are removed."
            help_detail "Does not accept --recursive; nested nests manage their own hooks."
            help_heading "Examples:"
            help_example "git-nest hooks-uninstall"
            help_example "git-nest doctor --offline"
            help_opposite "hooks-install installs the managed local hooks."
            ;;
        foreach)
            help_command "foreach -- <command> [args...]"
            help_text "Run a command in every checked-out subproject in the current nest."
            help_detail "The command runs inside each subproject checkout."
            help_detail "Use -- to separate git-nest options from the command to run."
            help_heading "Examples:"
            help_example "git-nest foreach -- git status --short"
            help_example "git-nest foreach -- sh -c 'git rev-parse --show-toplevel'"
            ;;
        foreach-modified)
            help_command "foreach-modified [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"
            help_text "Run a command in dirty checked-out subprojects, or list them."
            help_detail "Without a command, it reports the matching subprojects."
            help_detail "Machine-readable output cannot be combined with a command."
            help_heading "Examples:"
            help_example "git-nest foreach-modified"
            help_example "git-nest foreach-modified --porcelain"
            help_example "git-nest foreach-modified -- git status --short"
            help_opposite "foreach-clean selects clean checked-out subprojects."
            ;;
        foreach-clean)
            help_command "foreach-clean [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"
            help_text "Run a command in clean checked-out subprojects, or list them."
            help_detail "Without a command, it reports the matching subprojects."
            help_detail "Machine-readable output cannot be combined with a command."
            help_heading "Examples:"
            help_example "git-nest foreach-clean"
            help_example "git-nest foreach-clean --json-pretty"
            help_example "git-nest foreach-clean -- git fetch --all --prune"
            help_opposite "foreach-modified selects dirty checked-out subprojects."
            ;;
        export)
            help_command "export --output <path> [--format <tar.gz|zip|dir>] [--include-git] [--deterministic] [--allow-dirty]"
            help_text "Export a source snapshot with .gitnest and MANIFEST.lock."
            help_detail "dir output uses shell file copy."
            help_detail "tar.gz output requires system tar."
            help_detail "zip output requires python or python3."
            help_detail "--allow-dirty permits dirty subproject working trees."
            help_heading "Examples:"
            help_example "git-nest export --output build/source.tar.gz --deterministic"
            help_example "git-nest export --output build/source.zip --format zip"
            help_example "git-nest export --output build/source-dir --format dir"
            ;;
        absorb)
            help_command "absorb <path> [<remote-url>] [--branch <name>] [--clone-mode <full|partial>] [--preserve-history] [--push] [--message <msg>] [--force] [--dry-run] [--json|--json-pretty]"
            help_text "Bring something already on disk into the nest as a managed subproject."
            help_detail "Auto-detects the source: outer-repo tracked files, a standalone nested repo, or a submodule."
            help_detail "Outer-repo files require a remote URL; --branch, --clone-mode, --preserve-history, --push, --message, and --force apply to that source only."
            help_detail "An existing repo or submodule keeps its own history and records its own remote."
            help_detail "Refuses a path already tracked as a subproject and refuses deeper nested repos/submodules."
            help_detail "extract is the old name for the files source and now points here."
            help_heading "Examples:"
            help_example "git-nest absorb src/lib https://example.invalid/src-lib.git --push --message 'Create src-lib'"
            help_example "git-nest absorb libs/foo   # existing nested repo, uses its origin remote"
            help_example "git-nest absorb vendor/bar --dry-run   # a Git submodule"
            help_opposite "inline dissolves a subproject into outer files; detach keeps it as a standalone repo; remove deletes it."
            ;;
        inline)
            help_command "inline <path> [--commit] [--message <msg>] [--dry-run] [--json|--json-pretty]"
            help_text "Dissolve a managed subproject into the outer repo as ordinary tracked files."
            help_detail "This removes the subproject from the current nest and stages its files in the nest root."
            help_detail "--message sets the commit message and implies --commit."
            help_detail "The subproject's own Git history is discarded; the remote is left untouched."
            help_heading "Examples:"
            help_example "git-nest inline libs/foo --dry-run"
            help_example "git-nest inline libs/foo --commit --message 'Inline foo'"
            help_opposite "absorb brings outer-repo files into the nest as a subproject."
            ;;
        completion)
            help_command "completion <bash|zsh|fish>"
            help_text "Print a shell completion script to stdout."
            help_heading "Examples:"
            help_example "git-nest completion bash > ~/.local/share/bash-completion/completions/git-nest"
            help_example "git-nest completion zsh > ~/.zfunc/_git-nest"
            help_example "git-nest completion fish > ~/.config/fish/completions/git-nest.fish"
            ;;
        version)
            help_command "version"
            help_text "Print the tool name, version, and logo."
            help_heading "Example:"
            help_example "git-nest version"
            ;;
        help)
            help_command "help [command]"
            help_text "Show the grouped command overview or focused help for one command."
            help_detail "Alias topics such as rm, mv, sync, install-hooks, and remove-hooks point to their current command names."
            help_heading "Examples:"
            help_example "git-nest help"
            help_example "git-nest help snapshot"
            help_example "git-nest help branch-mark"
            ;;
        *)
            usage_error "unknown help topic: $1"
            ;;
    esac
}

cmd_help() {
    case $# in
        0) usage ;;
        1) command_help "$1" ;;
        *) usage_error "usage: git-nest help [command]" ;;
    esac
}

# Dispatch the public command name to the matching command handler.
git_nest_main() {
    cmd=${1:-}
    [ $# -gt 0 ] && shift || true

    case "$cmd" in
        init) require_git; cmd_init "$@" ;;
        repair) enter_project_root_required; cmd_repair "$@" ;;
        add) enter_workspace_root_if_present; cmd_add "$@" ;;
        remove|rm) enter_project_root_required; cmd_remove "$@" ;;
        move|mv) enter_project_root_required; cmd_mv "$@" ;;
        clone) cmd_clone "$@" ;;
        status) enter_project_root_required; cmd_status "$@" ;;
        outdated) enter_project_root_required; cmd_outdated "$@" ;;
        available) usage_error "unknown command: available; use outdated" ;;
        verify) enter_project_root_required; cmd_verify "$@" ;;
        diff) enter_project_root_required; cmd_diff "$@" ;;
        log) enter_project_root_required; cmd_log "$@" ;;
        start) usage_error "unknown command: start; use Git branch commands and git-nest snapshot" ;;
        snapshot) enter_project_root_required; cmd_snapshot "$@" ;;
        refresh) usage_error "unknown command: refresh; use snapshot" ;;
        record) usage_error "unknown command: record; use snapshot" ;;
        upload) usage_error "unknown command: upload; use git push and git-nest snapshot" ;;
        freeze) enter_project_root_required; cmd_freeze "$@" ;;
        hooks-install) enter_project_root_required; cmd_hooks_install "$@" ;;
        hooks-uninstall) enter_project_root_required; cmd_hooks_uninstall "$@" ;;
        install-hooks) usage_error "unknown command: install-hooks; use hooks-install" ;;
        remove-hooks) usage_error "unknown command: remove-hooks; use hooks-uninstall" ;;
        foreach) enter_project_root_required; cmd_foreach "$@" ;;
        foreach-pending) usage_error "unknown command: foreach-pending; pending manifest state is no longer supported" ;;
        foreach-modified) enter_project_root_required; cmd_foreach_modified "$@" ;;
        foreach-clean) enter_project_root_required; cmd_foreach_clean "$@" ;;
        no-pending) usage_error "unknown command: no-pending; pending manifest state is no longer supported" ;;
        config) enter_project_root_required; cmd_config "$@" ;;
        check) usage_error "unknown command: check; pending manifest state is no longer supported" ;;
        branch-mark) enter_project_root_required; cmd_branch_mark "$@" ;;
        branch-unmark) enter_project_root_required; cmd_branch_unmark "$@" ;;
        branch-list) enter_project_root_required; cmd_branch_list "$@" ;;
        branch-cleanup) enter_project_root_required; cmd_branch_cleanup "$@" ;;
        update) enter_project_root_required; cmd_update "$@" ;;
        finalize) usage_error "unknown command: finalize; use git-nest snapshot to record reproducible revisions" ;;
        cleanup-branches) usage_error "unknown command: cleanup-branches; git-nest no longer deletes Git branches" ;;
        restore) enter_project_root_required; cmd_restore "$@" ;;
        sync) usage_error "unknown command: sync; use restore" ;;
        doctor) cmd_doctor "$@" ;;
        discover) enter_project_root_required; cmd_discover "$@" ;;
        list) enter_project_root_required; cmd_list "$@" ;;
        completion) cmd_completion "$@" ;;
        export) enter_project_root_required; cmd_export "$@" ;;
        absorb) enter_project_root_required; cmd_absorb "$@" ;;
        inline) enter_project_root_required; cmd_inline "$@" ;;
        detach) enter_project_root_required; cmd_detach "$@" ;;
        extract) usage_error "unknown command: extract; use git-nest absorb to bring files, repositories, or submodules into the nest" ;;
        __complete) cmd_internal_complete "$@" ;;
        __owning-manifest) cmd_internal_owning_manifest "$@" ;;
        __hook) enter_project_root_required; cmd_internal_hook "$@" ;;
        version|--version) cmd_version "$@" ;;
        help) cmd_help "$@" ;;
        -h|--help|"") usage ;;
        *) usage_error "unknown command: $cmd" ;;
    esac
}

# Report the implemented tool version used by docs and tests.
cmd_version() {
    [ $# -eq 0 ] || die "version takes no arguments"
    printf 'git-nest %s \\\\_oOO_//\n' "$GIT_NEST_VERSION"
}

cmd_internal_owning_manifest() {
    [ $# -le 1 ] || usage_error "usage: git-nest __owning-manifest [path]"
    find_owning_manifest "$@"
}

cmd_internal_hook() {
    hook_action=${1:-}
    shift || true
    case "$hook_action" in
        root-post-checkout)
            root=$(pwd -P)
            printf 'git-nest: manifest changed; run `git-nest restore` inside %s to restore this nest.\n' "$root"
            ;;
        root-pre-commit)
            before=$(git diff -- "$MANIFEST_FILE" 2>/dev/null || true)
            cmd_snapshot --quiet || true
            after=$(git diff -- "$MANIFEST_FILE" 2>/dev/null || true)
            if [ "$before" != "$after" ]; then
                warn "$MANIFEST_FILE changed during hook; review and stage it before committing if intended"
            fi
            ;;
        root-pre-push)
            if ! cmd_snapshot --check --strict --quiet; then
                warn "nest is not fully reproducible from $MANIFEST_FILE; run git-nest snapshot, review, commit, and push again"
            fi
            ;;
        subproject-pre-push)
            [ $# -eq 1 ] || usage_error "usage: git-nest __hook subproject-pre-push <path>"
            path=$1
            ensure_gitignore_line "$PUSH_CANDIDATES_FILE"
            [ -f "$PUSH_CANDIDATES_FILE" ] || : >"$PUSH_CANDIDATES_FILE"
            origin=$(repo_origin_url_for_mark "$path")
            now=$(utc_now)
            while read -r local_ref local_sha remote_ref remote_sha; do
                [ -n "$local_ref" ] || continue
                case "$local_sha" in
                    0000000000000000000000000000000000000000) continue ;;
                esac
                printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$local_ref" "$local_sha" "$remote_ref" "$now" >>"$PUSH_CANDIDATES_FILE"
            done
            [ -n "$origin" ] || true
            ;;
        *) usage_error "unknown hook action: $hook_action" ;;
    esac
}

# Ensure Git is available before commands depend on it.
require_git() {
    command -v git >/dev/null 2>&1 || die "git is required"
}

# Detect old manifests only to fail clearly. git-nest does not migrate .stack.
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
        [ "$parent" != "$dir" ] || precondition_error "not inside a git-nest project"
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
        precondition_error "legacy .stack manifest found at $root; git-nest uses .gitnest and does not migrate old manifests"
    fi
    if root=$(git rev-parse --show-toplevel 2>/dev/null); then
        cd "$root" || die "cannot enter Git root $root"
    fi
}

# Operational commands need an existing manifest and always run from its root so
# subproject paths in .gitnest are interpreted consistently.
enter_project_root_required() {
    require_git
    GIT_NEST_CALLER_PWD=$(pwd -P)
    root=$(find_project_root 2>/dev/null) ||
        {
            if legacy_root=$(find_legacy_manifest_root 2>/dev/null); then
                precondition_error "legacy .stack manifest found at $legacy_root; git-nest uses .gitnest and does not migrate old manifests"
            fi
            precondition_error "not inside a git-nest workspace; run git-nest init or cd to a project"
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
        /^[[:space:]]*\.gitnest[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { gitnest=1 }
        /^[[:space:]]*\.gitnest-rc[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { rc=1 }
        /^[[:space:]]*bin\/git-nest[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { entrypoint=1 }
        /^[[:space:]]*bin\/git_nest\.sh[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { shell=1 }
        /^[[:space:]]*bin\/git-nest\.bat[[:space:]]+text[[:space:]]+eol=crlf[[:space:]]*$/ { batch=1 }
        END { exit !(gitnest && rc && entrypoint && shell && batch) }
    ' .gitattributes
}

print_gitattributes_guard() {
    printf '%s\n' "$GITATTRIBUTES_BEGIN"
    printf '%s\n' "$GITATTRIBUTES_GUARD"
    printf '.gitnest-rc text eol=lf\n'
    printf 'bin/git-nest text eol=lf\n'
    printf 'bin/git_nest.sh text eol=lf\n'
    printf 'bin/git-nest.bat text eol=crlf\n'
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
            /^[[:space:]]*# BEGIN git-nest attributes[[:space:]]*$/ { in_block=1; next }
            /^[[:space:]]*# END git-nest attributes[[:space:]]*$/ { in_block=0; next }
            in_block { next }
            {
                trimmed=$0
                sub(/^[[:space:]]+/, "", trimmed)
                sub(/[[:space:]]+$/, "", trimmed)
                if (trimmed ~ /^\.gitnest([[:space:]]|$)/) next
                if (trimmed ~ /^\.gitnest-rc([[:space:]]|$)/) next
                if (trimmed ~ /^bin\/git-nest([[:space:]]|$)/) next
                if (trimmed ~ /^bin\/git_nest\.sh([[:space:]]|$)/) next
                if (trimmed ~ /^bin\/git-nest\.bat([[:space:]]|$)/) next
                print
            }
        ' .gitattributes
    } >"$tmp"
    mv "$tmp" .gitattributes
}

warn_missing_gitattributes_guard() {
    gitattributes_has_guard && return 0
    warn "missing or stale git-nest .gitattributes guard; run git-nest repair to refresh it"
}

warn_old_managed_hooks() {
    [ "$OLD_HOOK_WARNING_PRINTED" -eq 0 ] || return 0
    git rev-parse --git-dir >/dev/null 2>&1 || return 0
    for hook_name in post-checkout post-commit pre-push; do
        hook_file=$(hook_path_for . "$hook_name" 2>/dev/null || true)
        [ -n "$hook_file" ] || continue
        [ -f "$hook_file" ] || continue
        if grep -F 'refresh --quiet' "$hook_file" >/dev/null 2>&1; then
            warn "old git-stack managed hook detected; run git-nest hooks-install to update hooks"
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
    printf 'This folder contains subdirectories. Initialize it as a git-nest workspace? [y/N] ' >/dev/tty
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
            printf '# git-nest manifest\n\n'
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
        .git|.gitnest|.gitnest.lock|.gitnest-rc|.gitignore|.gitattributes) return 1 ;;
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
                precondition_error "$candidate is inside nested project $boundary; run git-nest from $boundary instead"
                ;;
        esac
    done
}

assert_path_not_containing_nested_project() {
    candidate=$1
    [ -d "$candidate" ] || return 0
    if find "$candidate" -mindepth 1 -name "$MANIFEST_FILE" -type f 2>/dev/null | sed -n '1p' | grep . >/dev/null 2>&1; then
        precondition_error "$candidate contains a nested git-nest project; recursive absorb is not supported yet"
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
    [ -f "$MANIFEST_FILE" ] || precondition_error "missing $MANIFEST_FILE; run git-nest init"

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
                add_error("malformed subproject section in .gitnest: " $0)
                section = ""
                next
            } else if ($0 ~ /^\[[^]]+\]$/) {
                section = substr($0, 2, length($0) - 2)
            } else {
                add_error("malformed section in .gitnest: " $0)
                section = ""
                next
            }
            if ((section == "project" || section ~ /^subproject "[^"]+"$/) && seen_section[section]++) {
                add_error("duplicate section in .gitnest: [" section "]")
            }
            next
        }
        index($0, "=") > 0 {
            if (section == "") {
                add_error("key outside a valid section in .gitnest: " $0)
                next
            }
            key = substr($0, 1, index($0, "=") - 1)
            value = substr($0, index($0, "=") + 1)
            if (key ~ /^[[:space:]]/ || key ~ /[[:space:]]$/ || key == "") {
                add_error("malformed key in .gitnest: " $0)
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
        { add_error("malformed line in .gitnest: " $0) }
        END {
            if (!seen_section["project"]) {
                add_error("missing [project] section in .gitnest")
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
                cleanup = value_for[section SUBSEP "finalized_from_branch"]
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
                if (pending != "") add_error("pending_branch is no longer supported in [" section "]; use git-nest snapshot after pushing the subproject commit")
                if (base != "") add_error("base_revision is no longer supported in [" section "]")
                if (pushed != "") add_error("pushed_commit is no longer supported in [" section "]")
                if (cleanup != "") add_error("finalized_from_branch is no longer supported in [" section "]")
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

# Read a value from .gitnest-rc. Missing config is normal for copied manifests, so
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
    [ -f "$MANIFEST_FILE" ] && manifest_preserved_keys "$(subproject_section "$path")" "^(repo|clone|target_branch|revision|tag)$" >"$preserved" || : >"$preserved"

    require_value "$path" "cannot write manifest subproject with an empty path"
    require_value "$repo" "cannot write manifest subproject $path without a repository URL"
    case "$state" in
        finalized)
            require_value "$a" "cannot pin $path without a resolved revision; fetch the subproject or pass --revision <sha>"
            clone=${d:-$previous_clone}
            ;;
        pending)
            die "pending manifest state is no longer supported; use git-nest snapshot after pushing the subproject commit"
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

# Resolve the repository-wide clone override from .gitnest-rc.
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
    require_value "$target" "cannot restore tracked subproject $path without a target branch"
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
    printf '%s\n' "$status" | sed '/^?? \.gitnest\.lock\//d; /^?? \.gitnest\.lock$/d'
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
    state_dir=$(git rev-parse --git-path git-nest 2>/dev/null) || return 1
    printf '%s/subprojects\n' "$state_dir"
}

# Write the currently materialized manifest subprojects after a successful sync.
write_materialized_state() {
    state_file=$(materialized_state_file 2>/dev/null || true)
    [ -n "$state_file" ] || return 0
    state_dir=$(dirname -- "$state_file")
    mkdir -p "$state_dir" || die "cannot create git-nest state directory $state_dir"
    tmp=$(mktemp "$state_dir/subprojects.tmp.XXXXXX") ||
        die "cannot create temporary git-nest state file"
    current_pairs=$(mktemp "$state_dir/subprojects.current.XXXXXX") ||
        die "cannot create temporary git-nest state file"
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
            warn "stale subproject $old_path $reason; leaving it in place. Review it, then commit/stash/discard the work, push/delete local-only branches, or run git-nest restore --prune to remove it."
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
        printf '  run git-nest status --recursive to inspect them, or git-nest snapshot --recursive to include them\n' >&2
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
        git -C "$path" stash push -u -m "git-nest start preflight" >/dev/null
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
    [ -n "$GIT_NEST_BASE_OVERRIDES" ] || GIT_NEST_BASE_OVERRIDES=$(tmp_for "$MANIFEST_FILE.base_overrides")
    printf '%s\t%s\n' "$path" "$ref" >>"$GIT_NEST_BASE_OVERRIDES"
}

base_override_for() {
    path=$1
    [ -n "$GIT_NEST_BASE_OVERRIDES" ] || return 1
    [ -f "$GIT_NEST_BASE_OVERRIDES" ] || return 1
    awk -F '	' -v path="$path" '$1 == path { value=$2 } END { if (value != "") print value; else exit 1 }' "$GIT_NEST_BASE_OVERRIDES"
}

clear_base_overrides() {
    [ -z "$GIT_NEST_BASE_OVERRIDES" ] || rm -f "$GIT_NEST_BASE_OVERRIDES"
    GIT_NEST_BASE_OVERRIDES=
    GIT_NEST_NO_FETCH=0
}

# Print the constant lines git-nest always keeps inside its managed ignore block,
# in a deterministic order. These are workspace hygiene rules, not subproject
# paths. Transient conversion backups are intentionally absent: they are ignored
# on demand through the repo-local exclude file so they never linger here.
print_gitignore_constants() {
    printf '%s\n' "$GITIGNORE_GIT_DIR_GUARD_ONE"
    printf '%s\n' "$GITIGNORE_GIT_DIR_GUARD_TWO"
    printf '%s\n' "$BRANCH_MARKS_FILE"
    printf '%s\n' "$PUSH_CANDIDATES_FILE"
}

# Report whether a trimmed .gitignore line is one of the managed constant rules.
is_gitignore_constant() {
    case "$1" in
        "$GITIGNORE_GIT_DIR_GUARD_ONE"|"$GITIGNORE_GIT_DIR_GUARD_TWO"|"$BRANCH_MARKS_FILE"|"$PUSH_CANDIDATES_FILE") return 0 ;;
        *) return 1 ;;
    esac
}

# Print the bare subproject paths (no trailing slash) recorded inside the managed
# ignore block, excluding the constant hygiene rules. These are the entries whose
# fate (keep, retain, or prune) reconcile_gitignore must decide.
gitignore_block_paths() {
    [ -f .gitignore ] || return 0
    awk -v b="$GITIGNORE_BEGIN" -v e="$GITIGNORE_END" '
        $0 == b { inb = 1; next }
        $0 == e { inb = 0; next }
        inb {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line != "") print line
        }
    ' .gitignore | sed 's#/*$##' | while IFS= read -r p; do
        is_gitignore_constant "$p/" && continue
        is_gitignore_constant "$p" && continue
        [ -n "$p" ] && printf '%s\n' "$p"
    done
}

# Rewrite .gitignore so all nest-owned entries live in a single managed block at
# the end of the file, self-healing entries a user moved outside the block and
# deduping them, while preserving user-authored lines in order. add_path adds a
# subproject path, del_path drops one. When prune is 1, orphan block paths that
# are neither managed nor present on disk are removed and reported to report_file.
reconcile_gitignore() {
    rg_add=$(printf '%s' "${1:-}" | sed 's#/*$##')
    rg_del=$(printf '%s' "${2:-}" | sed 's#/*$##')
    rg_prune=${3:-0}
    rg_report=${4:-/dev/null}
    [ -f .gitignore ] || : >.gitignore

    rg_managed=$(mktemp)
    rg_desired=$(mktemp)
    rg_strip=$(mktemp)
    rg_user=$(mktemp)
    : >"$rg_report" 2>/dev/null || true

    # Current managed subproject paths (bare).
    manifest_subprojects | sed 's#/*$##' | sort -u >"$rg_managed"

    # Seed the desired path set with managed paths and the added path.
    cp "$rg_managed" "$rg_desired"
    [ -z "$rg_add" ] || printf '%s\n' "$rg_add" >>"$rg_desired"

    # Decide the fate of each orphan block path (in the block but not managed).
    gitignore_block_paths | sort -u | while IFS= read -r orphan; do
        [ -n "$orphan" ] || continue
        grep -Fxq "$orphan" "$rg_managed" && continue
        if [ "$rg_prune" -eq 1 ] && [ ! -e "$orphan" ]; then
            printf '%s\n' "$orphan" >>"$rg_report"
        else
            printf '%s\n' "$orphan" >>"$rg_desired"
        fi
    done

    # Remove the explicitly deleted path from the desired set.
    if [ -n "$rg_del" ]; then
        rg_tmp_desired=$(mktemp)
        grep -Fxv "$rg_del" "$rg_desired" >"$rg_tmp_desired" 2>/dev/null || true
        mv "$rg_tmp_desired" "$rg_desired"
    fi
    sort -u "$rg_desired" -o "$rg_desired"

    # Build the set of exact lines to strip from outside the block: every
    # nest-owned path (managed, orphan, added, or deleted) in both slash forms,
    # plus the constant rules. Anything else stays as a user line.
    {
        gitignore_block_paths
        cat "$rg_managed"
        [ -z "$rg_add" ] || printf '%s\n' "$rg_add"
        [ -z "$rg_del" ] || printf '%s\n' "$rg_del"
    } | sed 's#/*$##' | sort -u | while IFS= read -r p; do
        [ -n "$p" ] || continue
        printf '%s\n%s/\n' "$p" "$p"
    done >"$rg_strip"
    print_gitignore_constants >>"$rg_strip"

    # Emit user lines (outside the old block, not nest-owned), dropping trailing
    # blank lines so the managed block attaches cleanly at the end.
    awk -v b="$GITIGNORE_BEGIN" -v e="$GITIGNORE_END" -v stripfile="$rg_strip" '
        BEGIN { while ((getline s < stripfile) > 0) strip[s] = 1 }
        $0 == b { inb = 1; next }
        $0 == e { inb = 0; next }
        inb { next }
        {
            t = $0
            sub(/^[[:space:]]+/, "", t)
            sub(/[[:space:]]+$/, "", t)
            if (t in strip) next
            print
        }
    ' .gitignore | awk '
        # Buffer trailing blank lines so they do not separate user content from
        # the managed block; emit them only when more content follows.
        /^[[:space:]]*$/ { blanks = blanks "\n"; next }
        { if (seen) printf "%s", blanks; blanks = ""; print; seen = 1 }
    ' >"$rg_user"

    rg_out=$(tmp_for .gitignore)
    {
        cat "$rg_user"
        [ -s "$rg_user" ] && printf '\n' || true
        printf '%s\n' "$GITIGNORE_BEGIN"
        print_gitignore_constants
        while IFS= read -r p; do
            [ -n "$p" ] && printf '%s/\n' "$p"
        done <"$rg_desired"
        printf '%s\n' "$GITIGNORE_END"
    } >"$rg_out"
    mv "$rg_out" .gitignore
    rm -f "$rg_managed" "$rg_desired" "$rg_strip" "$rg_user"
}

# Append a single literal line to .gitignore if absent. Used for lightweight,
# location-local ignore needs (branch-mark and push-candidate hook state) that
# must not trigger a full manifest-based reconcile of the managed block.
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

# Add a subproject path to the managed ignore block (self-healing, no pruning).
ensure_gitignore_entry() {
    reconcile_gitignore "$1" "" 0
}

# Remove a subproject path from the managed ignore block wherever it appears.
remove_gitignore_entry() {
    reconcile_gitignore "" "$1" 0
}

# Ensure the managed ignore block exists with its constant hygiene rules and the
# current subproject paths, healing stray entries without pruning present orphans.
ensure_gitignore_hygiene() {
    reconcile_gitignore "" "" 0
}

# Report bare paths in the managed ignore block that are neither managed nor
# present on disk, i.e. stale orphans that repair would prune. Read-only.
stale_gitignore_orphans() {
    rg_managed=$(mktemp)
    manifest_subprojects | sed 's#/*$##' | sort -u >"$rg_managed"
    gitignore_block_paths | sort -u | while IFS= read -r orphan; do
        [ -n "$orphan" ] || continue
        grep -Fxq "$orphan" "$rg_managed" && continue
        [ -e "$orphan" ] && continue
        printf '%s\n' "$orphan"
    done
    rm -f "$rg_managed"
}

# Repair managed support files for an existing nest.
cmd_repair() {
    create_rc=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --rc) create_rc=1; shift ;;
            *) usage_error "unknown repair option: $1" ;;
        esac
    done
    ensure_outer_repo
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    ensure_gitattributes_guard
    [ -f .gitignore ] || : >.gitignore
    # repair is the one place that prunes stale nest-owned ignore entries: orphan
    # block paths that are neither managed nor present on disk (the leftover after
    # a detached repo is physically removed). Report what was pruned.
    pruned=$(mktemp)
    reconcile_gitignore "" "" 1 "$pruned"
    if [ -s "$pruned" ]; then
        while IFS= read -r stale; do
            [ -n "$stale" ] && printf 'Pruned stale ignore entry: %s/\n' "$stale"
        done <"$pruned"
    fi
    rm -f "$pruned"
    [ "$create_rc" -eq 0 ] || ensure_config
    printf 'Repaired git-nest managed support files.\n'
}

nearest_parent_manifest_root() {
    dir=$(pwd -P)
    parent=$(dirname "$dir")
    while [ "$parent" != "$dir" ]; do
        if [ -f "$parent/$MANIFEST_FILE" ]; then
            printf '%s\n' "$parent"
            return 0
        fi
        dir=$parent
        parent=$(dirname "$dir")
    done
    return 1
}

# Initialize an outer workspace and create default manifest/config files.
cmd_init() {
    create_rc=0
    sure=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --rc)
                create_rc=1
                shift
                ;;
            --sure)
                sure=1
                shift
                ;;
            *) usage_error "unknown init option: $1" ;;
        esac
    done
    if root=$(git rev-parse --show-toplevel 2>/dev/null); then
        cd "$root" || die "cannot enter Git root $root"
    fi
    if [ -f "$MANIFEST_FILE" ]; then
        printf 'git-nest workspace already initialized at %s.\n' "$(pwd)"
        printf 'Run git-nest doctor to inspect it or git-nest repair to refresh managed support files.\n'
        return 0
    fi
    if parent_root=$(nearest_parent_manifest_root 2>/dev/null); then
        [ "$sure" -eq 1 ] || precondition_error "this directory is inside existing git-nest workspace $parent_root; rerun git-nest init --sure to create an intentional nested nest"
    fi
    ensure_outer_repo
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    ensure_gitattributes_guard
    [ -f .gitignore ] || : >.gitignore
    ensure_gitignore_hygiene
    [ "$create_rc" -eq 0 ] || ensure_config
    printf 'Initialized git-nest workspace.\n'
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
    [ $# -eq 2 ] || die "usage: git-nest add [--clone <full|partial>] <repo> <path>"
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

    [ "$GIT_NEST_DRY_RUN" -eq 1 ] || fetch_quiet "$path"
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

# remove drops a subproject from the nest and deletes its checkout on disk. It
# is the destructive leave-the-nest verb; the remote is never touched. Use detach
# to keep the checkout as a standalone repository instead of deleting it.
cmd_remove() {
    force=0
    dry_run=0
    json=0
    pretty=0
    path_arg=
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1; shift ;;
            # --keep-files used to mean "remove entry but keep files"; that is now
            # the dedicated detach command, so reject it with clear guidance.
            --keep-files) usage_error "remove now always deletes the checkout; use git-nest detach <path> to leave the nest but keep the checkout" ;;
            --dry-run) dry_run=1; shift ;;
            --json) json=1; shift ;;
            --json-pretty) json=1; pretty=1; shift ;;
            --*) usage_error "unknown remove option: $1" ;;
            *)
                [ -z "$path_arg" ] || usage_error "usage: git-nest remove <path> [--force] [--dry-run] [--json|--json-pretty]"
                path_arg=$1
                shift
                ;;
        esac
    done
    [ -n "$path_arg" ] || usage_error "usage: git-nest remove <path> [--force] [--dry-run] [--json|--json-pretty]"
    reject_backslash_path "$path_arg"
    path=$(normalize_path "$path_arg")
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$path"
    repo=$(subproject_repo "$path" || true)
    [ -n "$repo" ] || precondition_error "$path is not a tracked subproject in $MANIFEST_FILE"
    target=$(subproject_key "$path" target_branch || true)
    # Guard against discarding local-only work unless the caller forces it.
    if [ "$force" -eq 0 ]; then
        reason=$(current_branch_safety_reason "$path" "$target")
        [ -z "$reason" ] || precondition_error "$reason; rerun with --force to remove anyway"
    fi
    # Snapshot output values before mutating helpers reuse the global variables.
    emit_path=$path
    emit_repo=$repo
    emit_target=${target:--}
    # Dry-run reports the plan without mutating the manifest or the filesystem.
    if [ "$dry_run" -eq 1 ]; then
        [ "$json" -eq 0 ] || GIT_NEST_JSON_DRY_RUN=1
        if [ "$json" -eq 1 ]; then
            json_single_row_result "$pretty" remove 1 R "$emit_path" removed "$emit_target" - "$emit_repo" "would remove subproject and delete files"
        else
            printf 'Would remove subproject %s and delete %s/.\n' "$emit_path" "$emit_path"
        fi
        return 0
    fi
    manifest_remove_section "$(subproject_section "$path")"
    remove_gitignore_entry "$path"
    if [ -e "$path" ]; then
        rm -rf -- "$path" || git_error "failed to remove subproject directory $path"
    fi
    write_materialized_state
    if [ "$json" -eq 1 ]; then
        json_single_row_result "$pretty" remove 1 R "$emit_path" removed "$emit_target" - "$emit_repo" "removed subproject and deleted files"
    else
        printf 'Removed subproject %s and deleted its files.\n' "$emit_path"
    fi
}

# detach drops a subproject from the nest but keeps its checkout on disk as a
# standalone, still-ignored Git repository. It is the non-destructive inverse of
# absorbing an existing repository: no files are deleted and the remote is left
# untouched. Reversing to a specific submodule/subtree/subrepo shape is out of
# scope; detach only guarantees a standalone repository remains.
cmd_detach() {
    dry_run=0
    json=0
    pretty=0
    path_arg=
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run=1; shift ;;
            --json) json=1; shift ;;
            --json-pretty) json=1; pretty=1; shift ;;
            --*) usage_error "unknown detach option: $1" ;;
            *)
                [ -z "$path_arg" ] || usage_error "usage: git-nest detach <path> [--dry-run] [--json|--json-pretty]"
                path_arg=$1
                shift
                ;;
        esac
    done
    [ -n "$path_arg" ] || usage_error "usage: git-nest detach <path> [--dry-run] [--json|--json-pretty]"
    reject_backslash_path "$path_arg"
    path=$(normalize_path "$path_arg")
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$path"
    repo=$(subproject_repo "$path" || true)
    [ -n "$repo" ] || precondition_error "$path is not a tracked subproject in $MANIFEST_FILE"
    target=$(subproject_key "$path" target_branch || true)
    # Snapshot output values before mutating helpers reuse the global variables.
    emit_path=$path
    emit_repo=$repo
    emit_target=${target:--}
    # detach keeps files and the ignore entry, so there is no dirty/ahead safety
    # gate: nothing on disk is lost by dropping the manifest entry.
    if [ "$dry_run" -eq 1 ]; then
        [ "$json" -eq 0 ] || GIT_NEST_JSON_DRY_RUN=1
        if [ "$json" -eq 1 ]; then
            json_single_row_result "$pretty" detach 1 T "$emit_path" detached "$emit_target" - "$emit_repo" "would detach and keep files ignored"
        else
            printf 'Would detach %s from the nest; keep files and keep %s/ ignored.\n' "$emit_path" "$emit_path"
        fi
        return 0
    fi
    manifest_remove_section "$(subproject_section "$path")"
    write_materialized_state
    if [ "$json" -eq 1 ]; then
        json_single_row_result "$pretty" detach 1 T "$emit_path" detached "$emit_target" - "$emit_repo" "detached and kept files ignored"
    else
        printf 'Detached %s from %s; kept files and kept %s/ ignored.\n' "$emit_path" "$MANIFEST_FILE" "$emit_path"
        printf 'After you move or delete %s, run git-nest repair to prune its ignore entry.\n' "$emit_path"
    fi
}

cmd_mv() {
    force=0
    old_arg=
    new_arg=
    if [ "${1:-}" = "--url" ]; then
        [ $# -eq 3 ] || usage_error "usage: git-nest move|mv --url <new-url> <path>"
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
            --*) usage_error "unknown move option: $1" ;;
            *)
                if [ -z "${old_arg:-}" ]; then
                    old_arg=$1
                elif [ -z "${new_arg:-}" ]; then
                    new_arg=$1
                else
                    usage_error "usage: git-nest move|mv <old-path> <new-path> [--force]"
                fi
                shift
                ;;
        esac
    done
    [ -n "${old_arg:-}" ] && [ -n "${new_arg:-}" ] || usage_error "usage: git-nest move|mv <old-path> <new-path> [--force]"
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
    no_restore=0
    depth=
    branch=
    single_branch=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-restore) no_restore=1; shift ;;
            --no-sync) usage_error "unknown clone option: --no-sync; use --no-restore" ;;
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
    [ $# -ge 1 ] && [ $# -le 2 ] || usage_error "usage: git-nest clone <nest-repo-url> [target-dir]"
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
    if [ "$no_restore" -eq 1 ]; then
        printf 'Cloned %s.\n' "$target_dir"
        return 0
    fi
    if [ -f "$target_dir/$MANIFEST_FILE" ]; then
        (cd "$target_dir" && git_nest_main restore) || return $?
    else
        notice "cloned repository has no $MANIFEST_FILE; skipped restore"
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
            printf '  %s: pinned %.12s%s\n' "$path" "$revision" "$dirty"
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

# Report whether subproject remotes have target-branch commits newer than .gitnest.
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
# Populate the caller-provided errors and warnings files with verification
# findings for the current nest, one message line each. Returns 0 when there are
# no errors. It does not print; callers decide how to present the results (human
# stderr, or JSON arrays), which keeps errors and warnings cleanly separated and
# avoids clobbering the caller's own temp-file variables.
verify_current() {
    vc_errors=$1
    vc_warnings=$2
    ensure_manifest
    configured_clone_mode >/dev/null
    : >"$vc_errors"
    : >"$vc_warnings"

    duplicates=$(manifest_subprojects | sort | uniq -d)
    if [ -n "$duplicates" ]; then
        printf '%s\n' "$duplicates" | while IFS= read -r path; do
            [ -n "$path" ] && printf 'Error: %s: duplicate subproject path in %s\n' "$path" "$MANIFEST_FILE" >>"$vc_errors"
        done
    fi

    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        repo=$(subproject_repo "$path" || true)
        if [ -z "$repo" ]; then
            printf 'Error: %s: missing repo in %s\n' "$path" "$MANIFEST_FILE" >>"$vc_errors"
            continue
        fi
        mode=$(effective_clone_mode "$path")
        if [ ! -d "$path/.git" ]; then
            printf 'Error: %s: subproject checkout is missing; run git-nest restore\n' "$path" >>"$vc_errors"
            continue
        fi

        actual_repo=$(git -C "$path" remote get-url origin 2>/dev/null || true)
        if [ "$actual_repo" != "$repo" ]; then
            printf 'Error: %s: origin remote differs from manifest\n' "$path" >>"$vc_errors"
            printf '  expected: %s\n  actual:   %s\n' "$repo" "$actual_repo" >>"$vc_errors"
        fi

        if [ "$mode" = partial ]; then
            repo_is_partial_clone "$path" ||
                printf 'Error: %s: manifest/config requests clone=partial, but existing checkout is full; remove the subproject and run git-nest restore or use clone=full\n' "$path" >>"$vc_errors"
        else
            if repo_is_partial_clone "$path"; then
                printf 'Error: %s: manifest/config requests clone=full, but existing checkout is partial; remove the subproject and run git-nest restore or use clone=full\n' "$path" >>"$vc_errors"
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
                printf 'Error: %s: pending branch %s is not resolvable\n' "$path" "$pending" >>"$vc_errors"
        elif [ -n "$tag" ]; then
            expected=$(git -C "$path" rev-parse --verify "$tag^{commit}" 2>/dev/null || true)
            if [ -z "$expected" ]; then
                printf 'Error: %s: tag %s is not resolvable\n' "$path" "$tag" >>"$vc_errors"
            else
                head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
                [ "$head" = "$expected" ] ||
                    printf 'Error: %s: checked-out commit does not match tag %s\n' "$path" "$tag" >>"$vc_errors"
            fi
        elif [ -n "$revision" ]; then
            expected=$(git -C "$path" rev-parse --verify "$revision^{commit}" 2>/dev/null || true)
            if [ -z "$expected" ]; then
                printf 'Error: %s: revision %s is not resolvable\n' "$path" "$revision" >>"$vc_errors"
            else
                head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
                [ "$head" = "$expected" ] ||
                    printf 'Error: %s: checked-out commit does not match revision %.12s\n' "$path" "$revision" >>"$vc_errors"
            fi
        else
            git -C "$path" rev-parse --verify "$target^{commit}" >/dev/null 2>&1 ||
            git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1 ||
                printf 'Error: %s: target branch %s is not resolvable\n' "$path" "$target" >>"$vc_errors"
        fi

        if repo_dirty "$path"; then
            printf 'Warning: %s: subproject has uncommitted changes\n' "$path" >>"$vc_warnings"
        fi
    done

    unmanaged_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        printf 'Warning: %s: unmanaged nested Git repository\n' "$path" >>"$vc_warnings"
    done

    [ ! -s "$vc_errors" ]
}

# Present current-nest verification for humans: warnings and errors to stderr, a
# success line to stdout, returning nonzero when errors were found.
verify_report_human() {
    vrh_errors=$(tmp_for "$MANIFEST_FILE.verify_errors")
    vrh_warnings=$(tmp_for "$MANIFEST_FILE.verify_warnings")
    vrh_rc=0
    verify_current "$vrh_errors" "$vrh_warnings" || vrh_rc=$?
    [ ! -s "$vrh_warnings" ] || cat "$vrh_warnings" >&2
    [ ! -s "$vrh_errors" ] || cat "$vrh_errors" >&2
    [ "$vrh_rc" -ne 0 ] || printf 'Project verified.\n'
    rm -f "$vrh_errors" "$vrh_warnings"
    return "$vrh_rc"
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
    verify_report_human || rc=1

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
        # Use uniquely named variables so verify_current cannot clobber them, and
        # feed errors/warnings straight from verify_current for clean separation.
        v_rows=$(mktemp)
        v_errors=$(mktemp)
        v_warnings=$(mktemp)
        : >"$v_rows"
        : >"$v_errors"
        : >"$v_warnings"
        v_rc=0
        if [ "$recursive" -eq 1 ]; then
            # Recursive verification aggregates human findings across nests; capture
            # them as diagnostic lines (warnings and errors are not separated here).
            v_out=$(mktemp)
            v_visited=$(mktemp)
            : >"$v_visited"
            verify_recursive "." "$v_visited" >"$v_out" 2>"$v_errors" || v_rc=$?
            rm -f "$v_visited" "$v_out"
        else
            verify_current "$v_errors" "$v_warnings" || v_rc=$?
        fi
        [ "$v_rc" -eq 0 ] && ok=1 || ok=0
        emit_json_result verify "$recursive" "$ok" "$v_rows" "$v_errors" "$v_warnings" "$json_pretty"
        rm -f "$v_rows" "$v_errors" "$v_warnings"
        [ "$v_rc" -eq 0 ] || return "$EXIT_ISSUES"
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
    # Capture and return the verification result explicitly so the trailing
    # notice cannot mask a failure (same class of bug fixed in cmd_snapshot).
    verify_rc=0
    verify_report_human || verify_rc=$?
    notice_nested_projects
    return "$verify_rc"
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
                [ -z "$branch" ] || die "usage: git-nest start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]"
                branch=$1
                shift
                ;;
        esac
    done
    [ -n "$branch" ] || die "usage: git-nest start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]"
    [ -d .git ] && startup_new=0 || startup_new=1
    confirm_startup_directory "$sure"
    ensure_outer_repo
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    ensure_gitattributes_guard

    if [ "$branch" = "." ]; then
        quiet_arg=
        if [ -n "${GIT_NEST_SNAPSHOT_QUIET:-}" ] || [ -n "${GIT_NEST_RECORD_REMOVED_QUIET:-}" ]; then
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

# Resolve a snapshot path argument relative to the caller, then map it to a
# manifest subproject. Empty output means "all subprojects".
snapshot_selected_subprojects() {
    arg=${1:-}
    if [ -z "$arg" ]; then
        manifest_subprojects
        return 0
    fi
    caller=${GIT_NEST_CALLER_PWD:-$(pwd -P)}
    root=$(pwd -P)
    target_abs=$(CDPATH= cd -- "$caller" && {
        if [ -d "$arg" ]; then
            CDPATH= cd -P -- "$arg" && pwd
        else
            dir=$(dirname -- "$arg")
            base=$(basename -- "$arg")
            CDPATH= cd -P -- "$dir" && printf '%s/%s\n' "$(pwd)" "$base"
        fi
    }) || precondition_error "cannot resolve snapshot path: $arg"
    if [ "$target_abs" = "$root" ]; then
        manifest_subprojects
        return 0
    fi
    match=
    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -d "$path" ] || continue
        path_abs=$(CDPATH= cd -P -- "$path" && pwd) || continue
        case "$target_abs" in
            "$path_abs"|"$path_abs"/*)
                printf '%s\n' "$path"
                exit 0
                ;;
        esac
    done
}

subproject_head_is_reproducible() {
    path=$1
    head=$2
    if [ "$GIT_NEST_DRY_RUN" -eq 0 ] && [ "$GIT_NEST_NO_FETCH" -eq 0 ]; then
        fetch_quiet "$path" 2>/dev/null || return 1
    fi
    git -C "$path" branch -r --contains "$head" 2>/dev/null | grep -E '^[* ]+origin/' >/dev/null 2>&1 && return 0
    git -C "$path" tag --contains "$head" 2>/dev/null | grep . >/dev/null 2>&1 && return 0
    return 1
}

snapshot_one_subproject() {
    path=$1
    quiet=$2
    dry_run=$3
    strict=$4
    check_only=$5
    [ -d "$path/.git" ] || {
        [ "$quiet" -eq 1 ] || warn "skipping missing subproject $path during snapshot"
        [ "$strict" -eq 1 ] && return "$EXIT_PRECONDITION"
        return 0
    }
    repo=$(subproject_repo "$path")
    require_value "$repo" "subproject $path is missing repo in $MANIFEST_FILE; run git-nest add again or fix the manifest"
    if repo_has_dirty "$path"; then
        [ "$quiet" -eq 1 ] || warn "cannot snapshot $path: working tree is dirty; commit, stash, or discard changes first"
        [ "$strict" -eq 1 ] && return "$EXIT_ISSUES"
        return 0
    fi
    head=$(resolve_head_commit "$path" "cannot snapshot subproject $path")
    target=$(subproject_key "$path" target_branch || true)
    [ -n "$target" ] || target=$(default_target_branch "$path")
    if ! subproject_head_is_reproducible "$path" "$head"; then
        [ "$quiet" -eq 1 ] || warn "cannot snapshot $path at $(printf '%s' "$head" | cut -c1-12): commit is not reachable from origin or a local tag"
        [ "$strict" -eq 1 ] && return "$EXIT_ISSUES"
        return 0
    fi
    old_revision=$(subproject_key "$path" revision || true)
    if [ "$old_revision" = "$head" ]; then
        [ "$quiet" -eq 1 ] || printf 'Snapshot unchanged for %s at %.12s.\n' "$path" "$head"
        return 0
    fi
    if [ "$dry_run" -eq 1 ] || [ "$check_only" -eq 1 ]; then
        printf '[dry-run] %s revision: %s -> %s\n' "$path" "${old_revision:-<unset>}" "$head"
        [ "$check_only" -eq 1 ] && return "$EXIT_ISSUES"
        return 0
    fi
    manifest_write_subproject "$path" "$repo" tracked "$target" "$head"
    [ "$quiet" -eq 1 ] || printf 'Snapshotted %s at %.12s.\n' "$path" "$head"
}

snapshot_current() {
    quiet=$1
    dry_run=${2:-0}
    selected=${3:-}
    strict=${4:-0}
    check_only=${5:-0}
    ensure_outer_repo
    [ "$dry_run" -eq 1 ] || [ "$check_only" -eq 1 ] || acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    selected_paths=$(snapshot_selected_subprojects "$selected")
    if [ -z "$selected_paths" ]; then
        [ -z "$selected" ] || precondition_error "snapshot path is not the nest root or a managed subproject: $selected"
        [ "$quiet" -eq 1 ] || [ "$check_only" -eq 1 ] || printf 'Refreshed git-nest snapshot.\n'
        return 0
    fi
    rc=0
    printf '%s\n' "$selected_paths" | while IFS= read -r path; do
        [ -n "$path" ] || continue
        snapshot_one_subproject "$path" "$quiet" "$dry_run" "$strict" "$check_only" || exit $?
    done || rc=$?
    clear_base_overrides
    [ "$quiet" -eq 1 ] || [ "$check_only" -eq 1 ] || printf 'Refreshed git-nest snapshot.\n'
    return "$rc"
}

snapshot_recursive() {
    label=$1
    visited=$2
    quiet=$3
    dry_run=${4:-0}
    strict=${5:-0}
    check_only=${6:-0}
    root_abs=$(abs_path_for .)
    if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "$root_abs" >>"$visited"
    [ "$quiet" -eq 1 ] || printf 'Snapshotting project: %s\n' "$label"
    snapshot_current "$quiet" "$dry_run" "" "$strict" "$check_only"
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
                snapshot_recursive "$child_label" "$visited" "$quiet" "$dry_run" "$strict" "$check_only"
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
    strict=0
    check_only=0
    selected=
    clear_base_overrides
    while [ $# -gt 0 ]; do
        case "$1" in
            --recursive) recursive=1; shift ;;
            --quiet) quiet=1; shift ;;
            --dry-run) dry_run=1; GIT_NEST_DRY_RUN=1; shift ;;
            --check) check_only=1; GIT_NEST_DRY_RUN=1; shift ;;
            --strict) strict=1; shift ;;
            --no-fetch) GIT_NEST_NO_FETCH=1; shift ;;
            --base)
                [ $# -ge 2 ] || usage_error "--base requires <subproject>=<ref>"
                add_base_override "$2"
                shift 2
                ;;
            --*) usage_error "unknown snapshot option: $1" ;;
            *)
                [ -z "$selected" ] || usage_error "snapshot accepts at most one path"
                selected=$1
                shift
                ;;
        esac
    done
    [ "$recursive" -eq 0 ] || [ -z "$selected" ] || usage_error "snapshot --recursive cannot be combined with a path"
    if [ "$recursive" -eq 1 ]; then
        visited=$(mktemp)
        : >"$visited"
        snapshot_recursive "." "$visited" "$quiet" "$dry_run" "$strict" "$check_only"
        rc=$?
        rm -f "$visited"
        return "$rc"
    fi
    # Capture the snapshot result and return it explicitly. Without this, the
    # trailing notice command would become the function's exit status and mask a
    # nonzero result, which breaks callers that inspect it (for example the root
    # pre-push hook's `if ! cmd_snapshot --check --strict --quiet`).
    snapshot_current "$quiet" "$dry_run" "$selected" "$strict" "$check_only"
    snapshot_rc=$?
    [ "$quiet" -eq 1 ] || notice_nested_snapshot_candidates
    return "$snapshot_rc"
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
    if [ "$GIT_NEST_NO_FETCH" -eq 0 ] && [ "$GIT_NEST_DRY_RUN" -eq 0 ]; then
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
        if [ "$GIT_NEST_DRY_RUN" -eq 1 ]; then
            printf '  dry-run does not fetch; the real run would fetch first if needed\n' >&2
        elif [ "$GIT_NEST_NO_FETCH" -eq 1 ]; then
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
        git commit -m "Update git-nest manifest for $branch" >/dev/null ||
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
                GIT_NEST_DRY_RUN=1
                shift
                ;;
            --no-fetch)
                GIT_NEST_NO_FETCH=1
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
        require_value "$repo" "subproject $path is missing repo in $MANIFEST_FILE; run git-nest add again or fix the manifest"
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
            remote_exists "$path" || die "subproject $path has no origin remote; restore or add origin, then rerun git-nest upload"
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
                printf '  recovery: fix the remote, credentials, or rejected branch, then rerun git-nest upload.\n' >&2
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
    [ $# -ge 1 ] || usage_error "usage: git-nest config <get|set|list|unset> ..."
    action=$1
    shift
    ensure_manifest
    validate_manifest_schema

    case "$action" in
        get)
            [ $# -eq 2 ] || usage_error "usage: git-nest config get <path> clone-mode"
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
            [ $# -eq 3 ] || usage_error "usage: git-nest config set <path> clone-mode <value>"
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
            [ $# -le 1 ] || usage_error "usage: git-nest config list [<path>]"
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
            [ $# -eq 2 ] || usage_error "usage: git-nest config unset <path> clone-mode"
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
    [ $# -gt 0 ] || die "usage: git-nest $mode -- <command> [args...]"
    if [ "$1" = "--" ]; then
        shift
    fi
    [ $# -gt 0 ] || die "usage: git-nest $mode -- <command> [args...]"

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
            GIT_NEST_ROOT=$root \
            GIT_NEST_SUBPROJECT_PATH=$path \
            GIT_NEST_SUBPROJECT_ABSPATH=$subproject_abs \
            GIT_NEST_SUBPROJECT_REPO=$repo \
            GIT_NEST_BRANCH=$branch \
            GIT_NEST_TARGET_BRANCH=$target \
            GIT_NEST_PENDING_BRANCH=$pending \
            GIT_NEST_BASE_REVISION=$base \
            GIT_NEST_PUSHED_COMMIT=$pushed \
            GIT_NEST_REVISION=$revision \
            GIT_NEST_TAG=$tag \
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
            GIT_NEST_ROOT=$root \
            GIT_NEST_SUBPROJECT_PATH=$path \
            GIT_NEST_SUBPROJECT_ABSPATH=$subproject_abs \
            GIT_NEST_SUBPROJECT_REPO=$repo \
            GIT_NEST_BRANCH=$branch \
            GIT_NEST_TARGET_BRANCH=$target \
            GIT_NEST_PENDING_BRANCH=$pending \
            GIT_NEST_BASE_REVISION=$base \
            GIT_NEST_PUSHED_COMMIT=$pushed \
            GIT_NEST_REVISION=$revision \
            GIT_NEST_TAG=$tag \
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

    [ $# -gt 0 ] || die "usage: git-nest $mode [--continue-on-error] [-- <command> [args...]]"
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

current_repo_mark_path() {
    caller=${GIT_NEST_CALLER_PWD:-$(pwd -P)}
    root=$(pwd -P)
    if git_root=$(CDPATH= cd -- "$caller" && git rev-parse --show-toplevel 2>/dev/null); then
        git_root=$(CDPATH= cd -P -- "$git_root" && pwd)
    else
        git_root=$root
    fi
    if [ "$git_root" = "$root" ]; then
        printf '.\n'
        return 0
    fi
    manifest_subprojects | while IFS= read -r path; do
        [ -n "$path" ] || continue
        [ -d "$path" ] || continue
        path_abs=$(CDPATH= cd -P -- "$path" && pwd) || continue
        [ "$git_root" = "$path_abs" ] && { printf '%s\n' "$path"; exit 0; }
    done
}

repo_origin_url_for_mark() {
    path=$1
    git -C "$path" remote get-url origin 2>/dev/null || true
}

ensure_branch_marks_file() {
    [ -f "$BRANCH_MARKS_FILE" ] || : >"$BRANCH_MARKS_FILE"
    ensure_gitignore_line "$BRANCH_MARKS_FILE"
}

cmd_branch_mark() {
    [ $# -le 1 ] || usage_error "usage: git-nest branch-mark [name]"
    repo_path=$(current_repo_mark_path)
    [ -n "$repo_path" ] || precondition_error "current Git repository is not the nest root or a managed subproject"
    branch=${1:-}
    if [ -z "$branch" ]; then
        branch=$(git -C "$repo_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
        [ -n "$branch" ] || precondition_error "cannot mark detached HEAD; pass a branch name explicitly"
    fi
    origin=$(repo_origin_url_for_mark "$repo_path")
    now=$(utc_now)
    ensure_branch_marks_file
    tmp=$(tmp_for "$BRANCH_MARKS_FILE")
    awk -F '	' -v repo="$repo_path" -v branch="$branch" '!(($1 == repo) && ($2 == branch))' "$BRANCH_MARKS_FILE" >"$tmp"
    printf '%s\t%s\t%s\t%s\n' "$repo_path" "$branch" "$origin" "$now" >>"$tmp"
    mv "$tmp" "$BRANCH_MARKS_FILE"
    printf 'Marked branch %s for %s.\n' "$branch" "$repo_path"
}

cmd_branch_unmark() {
    [ $# -eq 1 ] || usage_error "usage: git-nest branch-unmark <name>"
    repo_path=$(current_repo_mark_path)
    [ -n "$repo_path" ] || precondition_error "current Git repository is not the nest root or a managed subproject"
    branch=$1
    [ -f "$BRANCH_MARKS_FILE" ] || { printf 'No branch marks.\n'; return 0; }
    tmp=$(tmp_for "$BRANCH_MARKS_FILE")
    awk -F '	' -v repo="$repo_path" -v branch="$branch" '!(($1 == repo) && ($2 == branch))' "$BRANCH_MARKS_FILE" >"$tmp"
    mv "$tmp" "$BRANCH_MARKS_FILE"
    printf 'Unmarked branch %s for %s.\n' "$branch" "$repo_path"
}

cmd_branch_list() {
    verbose=0
    json=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --verbose) verbose=1; shift ;;
            --json) json=1; shift ;;
            *) usage_error "unknown branch-list option: $1" ;;
        esac
    done
    if [ ! -s "$BRANCH_MARKS_FILE" ]; then
        [ "$json" -eq 1 ] && printf '{"branches":[]}\n' || printf 'No branch marks.\n'
        return 0
    fi
    if [ "$json" -eq 1 ]; then
        printf '{"branches":['
        first=1
        while IFS='	' read -r repo branch origin seen; do
            [ -n "$repo" ] || continue
            [ "$first" -eq 1 ] || printf ','
            first=0
            printf '{"repo":'; json_string "$repo"; printf ',"branch":'; json_string "$branch"; printf ',"origin":'; json_string "$origin"; printf ',"last_seen":'; json_string "$seen"; printf '}'
        done <"$BRANCH_MARKS_FILE"
        printf ']}\n'
        return 0
    fi
    while IFS='	' read -r repo branch origin seen; do
        [ -n "$repo" ] || continue
        if [ "$verbose" -eq 1 ]; then
            printf '%s\t%s\t%s\t%s\n' "$branch" "$repo" "$origin" "$seen"
        else
            printf '%s\t%s\n' "$branch" "$repo"
        fi
    done <"$BRANCH_MARKS_FILE"
}

cmd_branch_cleanup() {
    [ $# -eq 0 ] || usage_error "branch-cleanup takes no arguments"
    [ -f "$BRANCH_MARKS_FILE" ] || { printf 'No branch marks.\n'; return 0; }
    tmp=$(tmp_for "$BRANCH_MARKS_FILE")
    : >"$tmp"
    removed=0
    while IFS='	' read -r repo branch origin seen; do
        [ -n "$repo" ] || continue
        if [ -d "$repo/.git" ] && git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
            printf '%s\t%s\t%s\t%s\n' "$repo" "$branch" "$origin" "$seen" >>"$tmp"
        else
            removed=$((removed + 1))
        fi
    done <"$BRANCH_MARKS_FILE"
    mv "$tmp" "$BRANCH_MARKS_FILE"
    printf 'Removed %s stale branch mark(s).\n' "$removed"
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

# Write a managed hook for the root or a subproject.
write_managed_hook() {
    write_hook_repo=$1
    write_hook_name=$2
    write_hook_outer_root=$3
    write_hook_git_nest_path=$4
    write_hook_file=$(hook_path_for "$write_hook_repo" "$write_hook_name")
    if [ -f "$write_hook_file" ] && ! grep -F '# git-nest managed hook' "$write_hook_file" >/dev/null 2>&1; then
        die "refusing to overwrite unmanaged hook: $write_hook_file"
    fi
    mkdir -p "$(dirname "$write_hook_file")"
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' '# git-nest managed hook'
        printf '%s\n' '[ "${GIT_NEST_HOOK:-}" = "1" ] && exit 0'
        printf 'cd "%s" || exit 0\n' "$write_hook_outer_root"
        if [ "$write_hook_repo" = "." ]; then
            case "$write_hook_name" in
                post-checkout)
                    printf 'GIT_NEST_HOOK=1 "%s" __hook root-post-checkout || true\n' "$write_hook_git_nest_path"
                    ;;
                pre-commit)
                    printf 'GIT_NEST_HOOK=1 "%s" __hook root-pre-commit || true\n' "$write_hook_git_nest_path"
                    ;;
                pre-push)
                    printf 'GIT_NEST_HOOK=1 "%s" __hook root-pre-push || true\n' "$write_hook_git_nest_path"
                    ;;
            esac
        else
            case "$write_hook_name" in
                post-checkout)
                    printf 'GIT_NEST_HOOK=1 "%s" snapshot "%s" --quiet || true\n' "$write_hook_git_nest_path" "$write_hook_repo"
                    ;;
                pre-push)
                    printf 'GIT_NEST_HOOK=1 "%s" __hook subproject-pre-push "%s" || true\n' "$write_hook_git_nest_path" "$write_hook_repo"
                    ;;
            esac
        fi
    } >"$write_hook_file"
    chmod +x "$write_hook_file" 2>/dev/null || true
}

# Report whether the project root already has the complete managed hook set.
managed_hooks_installed_in_repo() {
    managed_hooks_repo=$1
    git -C "$managed_hooks_repo" rev-parse --git-dir >/dev/null 2>&1 || return 1
    if [ "$managed_hooks_repo" = "." ]; then
        managed_hooks_name_list="post-checkout pre-commit pre-push"
    else
        managed_hooks_name_list="post-checkout pre-push"
    fi
    for managed_hooks_name in $managed_hooks_name_list; do
        managed_hooks_file=$(hook_path_for "$managed_hooks_repo" "$managed_hooks_name")
        [ -f "$managed_hooks_file" ] || return 1
        grep -F '# git-nest managed hook' "$managed_hooks_file" >/dev/null 2>&1 || return 1
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
    install_hooks_git_nest_path=$(CDPATH= cd -- "$(dirname -- "${0}")" && pwd)/git-nest
    preflight_managed_hook "$install_hooks_repo" post-checkout
    write_managed_hook "$install_hooks_repo" post-checkout "$install_hooks_outer_root" "$install_hooks_git_nest_path"
    preflight_managed_hook "$install_hooks_repo" pre-push
    write_managed_hook "$install_hooks_repo" pre-push "$install_hooks_outer_root" "$install_hooks_git_nest_path"
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
    if [ -f "$preflight_hook_file" ] && ! grep -F '# git-nest managed hook' "$preflight_hook_file" >/dev/null 2>&1; then
        die "refusing to overwrite unmanaged hook: $preflight_hook_file"
    fi
}

# Check every hook target up front so install is all-or-nothing.
preflight_hooks_all() {
    targets=$1
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        preflight_managed_hook "$repo" post-checkout
        [ "$repo" != "." ] || preflight_managed_hook "$repo" pre-commit
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
    GIT_NEST_path=$(CDPATH= cd -- "$(dirname -- "${0}")" && pwd)/git-nest
    targets=$(mktemp)
    hook_targets_file "$targets"

    # Preflight first so an unmanaged hook in any repo prevents partial install.
    preflight_hooks_all "$targets"
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        write_managed_hook "$repo" post-checkout "$outer_root" "$GIT_NEST_path"
        [ "$repo" != "." ] || write_managed_hook "$repo" pre-commit "$outer_root" "$GIT_NEST_path"
        write_managed_hook "$repo" pre-push "$outer_root" "$GIT_NEST_path"
        printf 'Installed hooks in %s.\n' "$repo"
    done <"$targets"
    rm -f "$targets"
}

# Command wrapper for managed hook installation.
cmd_hooks_install() {
    [ $# -eq 0 ] || usage_error "hooks-install takes no arguments"
    install_hooks_all
}

# Remove one hook only when it is git-nest managed.
remove_managed_hook() {
    repo=$1
    hook=$2
    hook_file=$(hook_path_for "$repo" "$hook")
    [ -f "$hook_file" ] || return 0
    if grep -F '# git-nest managed hook' "$hook_file" >/dev/null 2>&1; then
        rm -f "$hook_file"
    else
        warn "leaving unmanaged hook in place: $hook_file"
    fi
}

# Command wrapper for managed hook removal across all hook targets.
cmd_hooks_uninstall() {
    [ $# -eq 0 ] || usage_error "hooks-uninstall takes no arguments"
    ensure_manifest
    targets=$(mktemp)
    hook_targets_file "$targets"
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        remove_managed_hook "$repo" post-checkout
        [ "$repo" != "." ] || remove_managed_hook "$repo" pre-commit
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
    [ $# -ge 1 ] || die "usage: git-nest update <subproject> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]"
    reject_backslash_path "$1"
    path=$(normalize_path "$1")
    shift
    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$path"
    [ -d "$path/.git" ] || die "$path is not a checked-out subproject; run git-nest restore first"
    repo=$(subproject_repo "$path")
    [ -n "$repo" ] || die "$path is not in $MANIFEST_FILE"
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
    [ "$GIT_NEST_DRY_RUN" -eq 1 ] || fetch_quiet "$path"
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
    [ $# -ge 1 ] || die "usage: git-nest finalize <subproject> [--dry-run] [--cleanup] [--revision <sha> | --tag <tag> | --use-target-head]"
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
                GIT_NEST_DRY_RUN=1
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

# Clone/fetch subprojects and restore their recorded manifest state.
restore_current() {
    prune=${1:-0}
    force=${2:-0}
    dry_run=${3:-0}
    ensure_manifest
    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.restore")
    failures_tmp=$(tmp_for "$MANIFEST_FILE.restore_failures")
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
            tag=$(subproject_key "$path" tag || true)
            revision=$(subproject_key "$path" revision || true)
            target=$(subproject_key "$path" target_branch || true)
            [ -n "$target" ] || target=main
            if [ "$dry_run" -eq 1 ]; then
                if [ ! -d "$path/.git" ]; then
                    printf '[dry-run] would clone %s into %s using clone=%s\n' "$repo" "$path" "$clone_mode"
                else
                    printf '[dry-run] would fetch %s before restore\n' "$path"
                fi
                if [ -n "$tag" ]; then
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
            if [ -n "$tag" ]; then
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
                            printf '  recovery: investigate the moved tag, then run git-nest update %s --tag %s to re-pin\n' "$path" "$tag" >&2
                            exit "$EXIT_ISSUES"
                        fi
                    fi
                fi
                resolve_commit "$path" "$tag" "cannot restore $path tag $tag" >/dev/null
                git -C "$path" checkout "$tag" || die "failed to check out tag $tag in $path"
            elif [ -n "$revision" ]; then
                revision=$(resolve_commit "$path" "$revision" "cannot restore $path revision")
                git -C "$path" checkout "$revision" || die "failed to check out revision $revision in $path"
            elif [ "$created" -eq 1 ] && [ "$clone_mode" = partial ]; then
                checkout_target_branch "$path" "$target"
            fi
            printf 'Restored %s.\n' "$path"
        ); then
            :
        else
            rc=1
            printf '%s\n' "$path" >>"$failures_tmp"
        fi
    done <"$subprojects_tmp"

    rm -f "$subprojects_tmp"
    if [ "$rc" -ne 0 ]; then
        printf 'Error: restore failed for one or more subprojects:\n' >&2
        while IFS= read -r path; do
            [ -n "$path" ] && printf '  %s\n' "$path" >&2
        done <"$failures_tmp"
        printf 'Recovery: review the error for each listed subproject, fix the manifest, remote access, or local checkout, then rerun git-nest restore. Run git-nest verify for a read-only consistency report.\n' >&2
        rm -f "$failures_tmp"
        return 1
    fi
    rm -f "$failures_tmp"
    [ "$dry_run" -eq 1 ] || write_materialized_state
}

# Recursively restore the current project and nested project roots.
restore_recursive() {
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
    printf 'Restoring project: %s\n' "$label"
    restore_current "$prune" "$force" "$dry_run" || return 1

    subprojects_tmp=$(tmp_for "$MANIFEST_FILE.restore_recursive")
    manifest_subprojects >"$subprojects_tmp"
    rc=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
            child_label=$(join_project_label "$label" "$path")
            (
                cd "$path" || exit 1
                restore_recursive "$child_label" "$visited" "$prune" "$force" "$dry_run"
            ) || rc=1
        fi
    done <"$subprojects_tmp"
    rm -f "$subprojects_tmp"
    return "$rc"
}

# Restore project state, optionally including nested projects.
cmd_restore() {
    recursive=0
    prune=0
    force=0
    dry_run=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --recursive) recursive=1; shift ;;
            --prune) prune=1; shift ;;
            --force) force=1; shift ;;
            --dry-run) dry_run=1; GIT_NEST_DRY_RUN=1; shift ;;
            *) usage_error "unknown restore option: $1" ;;
        esac
    done
    if [ "$recursive" -eq 1 ]; then
        visited=$(mktemp)
        : >"$visited"
        restore_recursive "." "$visited" "$prune" "$force" "$dry_run"
        rc=$?
        rm -f "$visited"
        return "$rc"
    fi
    restore_current "$prune" "$force" "$dry_run"
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
    if grep -F '# git-nest managed hook' "$hook_file" >/dev/null 2>&1; then
        printf 'installed\n'
    else
        printf 'unmanaged\n'
    fi
}

doctor_ls_remote() {
    repo=$1
    timeout_seconds=$2
    validate_positive_integer "$timeout_seconds" "--timeout"
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_seconds" git ls-remote --exit-code "$repo" HEAD >/dev/null 2>&1
    else
        git ls-remote --exit-code "$repo" HEAD >/dev/null 2>&1 &
        child=$!
        elapsed=0
        while kill -0 "$child" 2>/dev/null; do
            [ "$elapsed" -lt "$timeout_seconds" ] || {
                kill "$child" 2>/dev/null || true
                wait "$child" 2>/dev/null || true
                return 124
            }
            sleep 1
            elapsed=$((elapsed + 1))
        done
        wait "$child"
    fi
}

cmd_doctor() {
    json=0
    json_pretty=0
    offline=0
    timeout_seconds=$GIT_NEST_DOCTOR_TIMEOUT_SECONDS
    use_exit_code=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) json=1; shift ;;
            --json-pretty) json=1; json_pretty=1; shift ;;
            --offline) offline=1; shift ;;
            --timeout)
                [ $# -ge 2 ] || usage_error "--timeout requires seconds"
                timeout_seconds=$2
                validate_positive_integer "$timeout_seconds" "--timeout"
                shift 2
                ;;
            --exit-code) use_exit_code=1; shift ;;
            *) usage_error "unknown doctor option: $1" ;;
        esac
    done
    validate_positive_integer "$timeout_seconds" GIT_NEST_DOCTOR_TIMEOUT_SECONDS

    require_git
    root=$(find_project_root 2>/dev/null || true)
    [ -n "$root" ] || precondition_error "not inside a git-nest workspace; run git-nest init or cd to a project"
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
            doctor_add_check "$checks" W lock "$MANIFEST_FILE.lock appears stale; remove it if no git-nest process is running"
        fi
    else
        doctor_add_check "$checks" I lock "no manifest lock present"
    fi

    if gitattributes_has_guard; then
        doctor_add_check "$checks" I gitattributes "git-nest attributes guard present"
    else
        doctor_add_check "$checks" W gitattributes "missing or stale git-nest attributes guard; run git-nest repair to refresh it"
    fi

    if [ -f .gitignore ]; then
        # Warn about nest-owned ignore entries whose path is gone and unmanaged;
        # these are left behind after a detached repo is physically removed.
        stale_orphans=$(stale_gitignore_orphans)
        if [ -n "$stale_orphans" ]; then
            stale_count=$(printf '%s\n' "$stale_orphans" | sed '/^$/d' | wc -l | tr -d ' ')
            doctor_add_check "$checks" W gitignore-stale "$stale_count stale nest-owned ignore entry(s); run git-nest repair to prune them"
        else
            doctor_add_check "$checks" I gitignore-stale "no stale nest-owned ignore entries"
        fi
    else
        doctor_add_check "$checks" W gitignore ".gitignore is missing"
    fi

    # Surface leftover transient recovery backups from an interrupted conversion
    # so a stuck workspace is easy to discover even though the backups are ignored.
    leftover_recovery=$(find . -maxdepth 1 -type d -name "$RECOVERY_BACKUP_PREFIX-*" 2>/dev/null | sed 's#^\./##' | sort)
    if [ -n "$leftover_recovery" ]; then
        recovery_count=$(printf '%s\n' "$leftover_recovery" | sed '/^$/d' | wc -l | tr -d ' ')
        doctor_add_check "$checks" W recovery-backup "$recovery_count interrupted conversion backup(s) present; open the directory's RECOVERY.txt, then remove it"
    else
        doctor_add_check "$checks" I recovery-backup "no interrupted conversion backups"
    fi

    for repo in . $(manifest_subprojects 2>/dev/null); do
        [ "$repo" = "." ] || [ -d "$repo/.git" ] || continue
        if [ "$repo" = "." ]; then
            hook_list="post-checkout pre-commit pre-push"
        else
            hook_list="post-checkout pre-push"
        fi
        for hook in $hook_list; do
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
            doctor_add_check "$checks" I git-filter-repo "not found; required only for absorb --preserve-history"
    fi

    if command -v tar >/dev/null 2>&1; then
        doctor_add_check "$checks" I export-tar "available; required for export --format tar.gz"
    else
        doctor_add_check "$checks" I export-tar "not found; required only for export --format tar.gz"
    fi

    export_python=$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)
    if [ -n "$export_python" ]; then
        doctor_add_check "$checks" I export-zip "python available; required for export --format zip"
    else
        doctor_add_check "$checks" I export-zip "python/python3 not found; required only for export --format zip"
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

# Default directory names discover prunes so scans stay bounded and quiet. These
# are dependency, build, cache, and git-nest backup directories that never hold
# subprojects worth managing.
DISCOVER_DEFAULT_EXCLUDES="node_modules vendor build dist target out bin obj .cache .gradle .venv venv __pycache__ .gitnest-recovery-*"

# Reject exclude names that could inject shell syntax, since discover_scan builds
# a find expression with eval. Only simple directory-name tokens are allowed.
validate_discover_exclude() {
    case "$1" in
        ""|*[!A-Za-z0-9._*-]*) usage_error "invalid --exclude value: $1 (use simple directory names)" ;;
    esac
}

# Print every .git entry (repository or submodule gitlink) under the current nest
# root, bounded by a maximum path depth and pruning excluded directory names. It
# does not follow symlinks because plain find never descends symlinked dirs.
discover_scan() {
    ds_depth=$1
    ds_excludes=$2
    # The .git component sits one level below its repository path.
    ds_find_depth=$((ds_depth + 1))
    # Build an alternation of directory names to prune from the scan. Each name is
    # single-quoted so a glob such as .gitnest-recovery-* reaches find literally
    # instead of being expanded by the shell during eval.
    ds_group=""
    for ds_name in $ds_excludes; do
        if [ -z "$ds_group" ]; then
            ds_group="-name '$ds_name'"
        else
            ds_group="$ds_group -o -name '$ds_name'"
        fi
    done
    # eval expands the prune group into separate find operands. Inputs are
    # validated (defaults are constant, user excludes pass validate_discover_exclude).
    if [ -n "$ds_group" ]; then
        eval "find . -maxdepth $ds_find_depth \\( $ds_group \\) -prune -o -name .git -print" 2>/dev/null
    else
        find . -maxdepth "$ds_find_depth" -name .git -print 2>/dev/null
    fi
}

# Classify one discovered repository and append a porcelain row describing it.
# Rows reuse the shared 7-column layout: code, path, state, target, current,
# expected, detail. code is S(ubmodule)/R(epo)/N(est root); target carries the
# managing subproject when the repo sits inside one; detail is a next-step hint.
discover_classify_row() {
    dcr_path=$1
    dcr_rows=$2
    # Determine whether the repo lives inside a managed subproject and find that
    # parent so the suggestion can point at the right nest.
    dcr_parent=-
    dcr_inside=0
    paths=$(mktemp)
    manifest_subprojects >"$paths"
    while IFS= read -r managed; do
        [ -n "$managed" ] || continue
        # A repo exactly at a managed path is the subproject's own checkout; skip.
        [ "$dcr_path" = "$managed" ] && { rm -f "$paths"; return 0; }
        case "$dcr_path" in
            "$managed"/*) dcr_parent=$managed; dcr_inside=1 ;;
        esac
    done <"$paths"
    rm -f "$paths"

    # Classify the kind of repository so callers know how to handle it. A plain
    # nested repo whose path still carries a nest-owned ignore entry is a former
    # subproject left behind by detach, so it is labeled detached.
    if outer_submodule_name_for_path "$dcr_path" >/dev/null 2>&1; then
        dcr_code=S
        dcr_state=submodule
    elif [ -f "$dcr_path/$MANIFEST_FILE" ]; then
        dcr_code=N
        dcr_state=nest-root
    elif gitignore_block_paths | grep -Fxq "$dcr_path"; then
        dcr_code=D
        dcr_state=detached
    else
        dcr_code=R
        dcr_state=nested-repo
    fi

    # Build a next-step suggestion appropriate to the situation.
    if [ "$dcr_inside" -eq 1 ]; then
        dcr_detail="inside managed subproject $dcr_parent; run git-nest from there"
    elif [ "$dcr_state" = nest-root ]; then
        dcr_detail="nested nest; run git-nest inside it or use --recursive commands"
    elif [ "$dcr_state" = submodule ]; then
        dcr_detail="run git-nest absorb $dcr_path to convert the submodule"
    elif [ "$dcr_state" = detached ]; then
        dcr_detail="detached former subproject; git-nest absorb $dcr_path to re-manage, or move/remove it and run git-nest repair"
    else
        dcr_detail="run git-nest absorb $dcr_path to manage it"
    fi
    printf '%s\t%s\t%s\t%s\t-\t-\t%s\n' "$dcr_code" "$dcr_path" "$dcr_state" "$dcr_parent" "$dcr_detail" >>"$dcr_rows"
}

# discover scans the current nest for nested Git repositories and submodules that
# are not managed by .gitnest, and reports them with a suggested next step. It is
# discovery only: it never adds, syncs, or registers anything.
cmd_discover() {
    max_depth=4
    porcelain=0
    json=0
    pretty=0
    excludes=$DISCOVER_DEFAULT_EXCLUDES
    while [ $# -gt 0 ]; do
        case "$1" in
            --max-depth)
                [ $# -ge 2 ] || usage_error "--max-depth requires a positive integer"
                validate_positive_integer "$2" "--max-depth"
                max_depth=$2
                shift 2
                ;;
            --exclude)
                [ $# -ge 2 ] || usage_error "--exclude requires a directory name"
                validate_discover_exclude "$2"
                excludes="$excludes $2"
                shift 2
                ;;
            --porcelain) porcelain=1; shift ;;
            --json) json=1; shift ;;
            --json-pretty) json=1; pretty=1; shift ;;
            --*) usage_error "unknown discover option: $1" ;;
            *) usage_error "discover takes no positional arguments" ;;
        esac
    done
    [ "$porcelain" -eq 0 ] || [ "$json" -eq 0 ] || usage_error "discover cannot combine --porcelain with --json/--json-pretty"
    ensure_manifest
    validate_manifest_schema

    # Collect and classify discovered repositories into a stable, sorted rows file.
    raw=$(mktemp)
    rows=$(mktemp)
    empty=$(mktemp)
    discover_scan "$max_depth" "$excludes" | while IFS= read -r gitpath; do
        repo=$(dirname -- "$gitpath")
        repo=$(normalize_path "$repo")
        repo=${repo#./}
        # The nest root's own .git is expected and never reported.
        [ "$repo" = "." ] && continue
        [ -n "$repo" ] && printf '%s\n' "$repo"
    done | sort -u >"$raw"
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        discover_classify_row "$repo" "$rows"
    done <"$raw"

    if [ "$json" -eq 1 ]; then
        emit_json_result discover 0 1 "$rows" "$empty" "$empty" "$pretty"
    elif [ "$porcelain" -eq 1 ]; then
        # Stable fixed-column records for scripts; empty output means nothing found.
        cat "$rows"
    else
        if [ -s "$rows" ]; then
            printf 'Unmanaged repositories discovered under the current nest:\n'
            while IFS='	' read -r code path state target current expected detail; do
                printf '  %s  %-28s %-12s %s\n' "$code" "$path" "$state" "$detail"
            done <"$rows"
        else
            printf 'No unmanaged repositories found under the current nest (max depth %s).\n' "$max_depth"
        fi
    fi
    rm -f "$raw" "$rows" "$empty"
}

# Report the reproducibility state of one managed subproject as a single letter:
# R reproducible (HEAD matches the recorded revision), D drift (HEAD differs),
# M missing checkout, U unpinned (no recorded revision).
list_reproducibility_code() {
    lrc_path=$1
    lrc_revision=$2
    if [ ! -d "$lrc_path/.git" ]; then
        printf 'M\n'
        return 0
    fi
    if [ -z "$lrc_revision" ]; then
        printf 'U\n'
        return 0
    fi
    lrc_head=$(git -C "$lrc_path" rev-parse --verify HEAD 2>/dev/null || true)
    lrc_expected=$(git -C "$lrc_path" rev-parse --verify "$lrc_revision^{commit}" 2>/dev/null || true)
    if [ -n "$lrc_head" ] && [ -n "$lrc_expected" ] && [ "$lrc_head" = "$lrc_expected" ]; then
        printf 'R\n'
    else
        printf 'D\n'
    fi
}

# Build one list porcelain row per managed subproject. Columns reuse the shared
# layout: code=reproducibility, path, state=checkout state, target=target branch,
# current=revision, expected=tag, detail=repository URL.
list_rows() {
    lr_rows=$1
    manifest_subprojects | sort -u | while IFS= read -r path; do
        [ -n "$path" ] || continue
        lr_repo=$(subproject_repo "$path" || true)
        lr_target=$(subproject_key "$path" target_branch || true)
        lr_revision=$(subproject_key "$path" revision || true)
        lr_tag=$(subproject_key "$path" tag || true)
        # Determine the on-disk checkout state without contacting any remote.
        if [ ! -d "$path/.git" ]; then
            lr_state=missing
        elif repo_has_dirty "$path"; then
            lr_state=dirty
        else
            lr_state=clean
        fi
        lr_code=$(list_reproducibility_code "$path" "$lr_revision")
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$lr_code" "$path" "$lr_state" "${lr_target:--}" "${lr_revision:--}" "${lr_tag:--}" "${lr_repo:--}" >>"$lr_rows"
    done
}

# list prints the managed subprojects in a stable order with their URL, target
# branch, revision, tag, checkout state, and reproducibility. It is a script-first
# inventory command; status stays focused on workspace health.
cmd_list() {
    porcelain=0
    json=0
    pretty=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --porcelain) porcelain=1; shift ;;
            --json) json=1; shift ;;
            --json-pretty) json=1; pretty=1; shift ;;
            --*) usage_error "unknown list option: $1" ;;
            *) usage_error "list takes no positional arguments" ;;
        esac
    done
    [ "$porcelain" -eq 0 ] || [ "$json" -eq 0 ] || usage_error "list cannot combine --porcelain with --json/--json-pretty"
    ensure_manifest
    validate_manifest_schema

    rows=$(mktemp)
    empty=$(mktemp)
    list_rows "$rows"
    if [ "$json" -eq 1 ]; then
        emit_json_result list 0 1 "$rows" "$empty" "$empty" "$pretty"
    elif [ "$porcelain" -eq 1 ]; then
        cat "$rows"
    else
        if [ -s "$rows" ]; then
            # Human table; the leading code column is the reproducibility state.
            printf '%-2s %-28s %-8s %-14s %-14s %s\n' '' 'PATH' 'STATE' 'TARGET' 'REVISION' 'REPO'
            while IFS='	' read -r code path state target current expected detail; do
                printf '%-2s %-28s %-8s %-14s %-14.12s %s\n' "$code" "$path" "$state" "$target" "$current" "$detail"
            done <"$rows"
        else
            printf 'No subprojects are recorded in %s.\n' "$MANIFEST_FILE"
        fi
    fi
    rm -f "$rows" "$empty"
}

GIT_NEST_command_names() {
    printf '%s\n' "init repair add remove rm move mv clone status outdated verify diff log snapshot restore freeze hooks-install hooks-uninstall branch-mark branch-unmark branch-list branch-cleanup foreach foreach-modified foreach-clean config update doctor discover list completion export absorb inline detach version help"
}

# Internal completion data endpoint used by generated shell completion scripts.
cmd_internal_complete() {
    [ $# -eq 1 ] || usage_error "usage: git-nest __complete <commands|subprojects>"
    case "$1" in
        commands)
            GIT_NEST_command_names
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
_git_nest_complete()
{
    local cur cmd commands subprojects
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    commands="init repair add remove rm move mv clone status outdated verify diff log snapshot restore freeze hooks-install hooks-uninstall branch-mark branch-unmark branch-list branch-cleanup foreach foreach-modified foreach-clean config update doctor discover list completion export absorb inline detach version help"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi

    cmd="${COMP_WORDS[1]}"
    case "$cmd" in
        completion)
            COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") )
            ;;
        help)
            COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            ;;
        export)
            COMPREPLY=( $(compgen -W "--output --format --include-git --deterministic --allow-dirty tar.gz zip dir" -- "$cur") )
            ;;
        absorb)
            subprojects="$(git-nest __complete subprojects 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$subprojects --branch --clone-mode --preserve-history --push --message --force --dry-run --json --json-pretty full partial" -- "$cur") )
            ;;
        inline)
            subprojects="$(git-nest __complete subprojects 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$subprojects --commit --message --dry-run --json --json-pretty" -- "$cur") )
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
        restore)
            COMPREPLY=( $(compgen -W "--recursive --prune --force --dry-run" -- "$cur") )
            ;;
        doctor)
            COMPREPLY=( $(compgen -W "--json --json-pretty --offline --timeout --exit-code" -- "$cur") )
            ;;
        discover)
            COMPREPLY=( $(compgen -W "--max-depth --exclude --porcelain --json --json-pretty" -- "$cur") )
            ;;
        list)
            COMPREPLY=( $(compgen -W "--porcelain --json --json-pretty" -- "$cur") )
            ;;
        diff)
            COMPREPLY=( $(compgen -W "--since --stat --json --json-pretty" -- "$cur") )
            ;;
        log)
            COMPREPLY=( $(compgen -W "--max-count --since --until --subproject --oneline --recursive" -- "$cur") )
            ;;
        snapshot)
            subprojects="$(git-nest __complete subprojects 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$subprojects --recursive --quiet --dry-run --check --strict --no-fetch" -- "$cur") )
            ;;
        branch-list)
            COMPREPLY=( $(compgen -W "--verbose --json" -- "$cur") )
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
                subprojects="$(git-nest __complete subprojects 2>/dev/null)"
                COMPREPLY=( $(compgen -W "$subprojects" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "clone-mode full partial" -- "$cur") )
            fi
            ;;
        remove|rm|detach|move|mv|update)
            subprojects="$(git-nest __complete subprojects 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$subprojects --force --url --remote --target-head --revision --tag --branch --no-fetch --dry-run --json --json-pretty" -- "$cur") )
            ;;
    esac
}

complete -F _git_nest_complete git-nest
EOF
}

completion_zsh() {
    cat <<'EOF'
#compdef git-nest

_git_nest()
{
    local -a commands subprojects
    commands=(init repair add remove rm move mv clone status outdated verify diff log snapshot restore freeze hooks-install hooks-uninstall branch-mark branch-unmark branch-list branch-cleanup foreach foreach-modified foreach-clean config update doctor discover list completion export absorb inline detach version help)

    if (( CURRENT == 2 )); then
        _describe 'git-nest command' commands
        return
    fi

    local cmd=${words[2]}
    case "$cmd" in
        completion)
            _arguments '1:shell:(bash zsh fish)'
            ;;
        help)
            _arguments '1:command:(init repair add remove rm move mv clone status outdated verify diff log snapshot restore freeze hooks-install hooks-uninstall branch-mark branch-unmark branch-list branch-cleanup foreach foreach-modified foreach-clean config update doctor discover list completion export absorb inline detach version help)'
            ;;
        export)
            _arguments '--output[write archive or directory]:path:_files' '--format[archive format]:format:(tar.gz zip dir)' '--include-git[keep .git directories]' '--deterministic[normalize archive metadata]' '--allow-dirty[allow dirty subprojects]'
            ;;
        absorb)
            _arguments '1:path:_files -/' '2:remote-url:' '--branch[initial branch for the files source]:branch:' '--clone-mode[clone mode]:mode:(full partial)' '--preserve-history[preserve path history with git-filter-repo]' '--push[push absorbed repository]' '--message[commit message]:message:' '--force[bypass metadata conflicts only]' '--dry-run[show planned changes]' '--json[print JSON]' '--json-pretty[print formatted JSON]'
            ;;
        inline)
            _arguments '1:subproject:__git_nest_subprojects' '--commit[commit staged outer changes]' '--message[commit message]:message:' '--dry-run[show planned changes]' '--json[print JSON]' '--json-pretty[print formatted JSON]'
            ;;
        detach)
            _arguments '1:subproject:__git_nest_subprojects' '--dry-run[show planned changes]' '--json[print JSON]' '--json-pretty[print formatted JSON]'
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
        restore)
            _arguments '--recursive[include nested projects]' '--prune[remove reviewed stale paths]' '--force[proceed past tag drift warnings]' '--dry-run[show planned actions without writing]'
            ;;
        doctor)
            _arguments '--json[print JSON]' '--json-pretty[print formatted JSON]' '--offline[skip remote checks]' '--timeout[remote timeout seconds]:seconds:' '--exit-code[return nonzero for warnings or errors]'
            ;;
        discover)
            _arguments '--max-depth[maximum scan depth]:depth:' '--exclude[exclude directory name]:name:' '--porcelain[print fixed-column output]' '--json[print JSON]' '--json-pretty[print formatted JSON]'
            ;;
        list)
            _arguments '--porcelain[print fixed-column output]' '--json[print JSON]' '--json-pretty[print formatted JSON]'
            ;;
        diff)
            _arguments '--since[read manifest from ref]:ref:' '--stat[include file statistics]' '--json[print JSON]' '--json-pretty[print formatted JSON]'
            ;;
        log)
            _arguments '--max-count[count]:count:' '--since[date]:date:' '--until[date]:date:' '--subproject[path]:subproject:' '--oneline[compact output]' '--recursive[include nested projects]'
            ;;
        snapshot)
            _arguments '1:subproject:__git_nest_subprojects' '--recursive[include nested projects]' '--quiet[suppress dirty skip warnings]' '--dry-run[show planned changes without writing]' '--check[check without writing]' '--strict[fail for unreproducible state]' '--no-fetch[use local refs]'
            ;;
        branch-list)
            _arguments '--verbose[include origin and timestamp]' '--json[print JSON]'
            ;;
        freeze)
            _arguments '--force[freeze dirty subprojects]' '--only[limit paths]:paths:' '--dry-run[show changes without writing]'
            ;;
        foreach-modified|foreach-clean)
            _arguments '--continue-on-error[keep iterating after failures]' '--porcelain[print fixed-column output]' '--json[print JSON]' '--json-pretty[print formatted JSON]'
            ;;
        config)
            subprojects=("${(@f)$(_call_program subprojects git-nest __complete subprojects 2>/dev/null)}")
            _arguments '1:action:(get set list unset)' '2:subproject:->subproject' '3:key:(clone-mode)' '4:value:(full partial)'
            if [[ $state == subproject ]]; then
                _describe 'subproject' subprojects
            fi
            ;;
        remove|rm|detach|move|mv|update)
            subprojects=("${(@f)$(_call_program subprojects git-nest __complete subprojects 2>/dev/null)}")
            _describe 'subproject' subprojects
            ;;
    esac
}

_git_nest "$@"
EOF
}

completion_fish() {
    cat <<'EOF'
function __git_nest_subprojects
    git-nest __complete subprojects 2>/dev/null
end

complete -c git-nest -f -n "__fish_use_subcommand" -a "init repair add remove rm move mv clone status outdated verify diff log snapshot restore freeze hooks-install hooks-uninstall branch-mark branch-unmark branch-list branch-cleanup foreach foreach-modified foreach-clean config update doctor discover list completion export absorb inline detach version help"
complete -c git-nest -f -n "__fish_seen_subcommand_from help" -a "init repair add remove rm move mv clone status outdated verify diff log snapshot restore freeze hooks-install hooks-uninstall branch-mark branch-unmark branch-list branch-cleanup foreach foreach-modified foreach-clean config update doctor discover list completion export absorb inline detach version help"
complete -c git-nest -f -n "__fish_seen_subcommand_from completion" -a "bash zsh fish"
complete -c git-nest -f -n "__fish_seen_subcommand_from export" -a "--output --format --include-git --deterministic --allow-dirty tar.gz zip dir"
complete -c git-nest -f -n "__fish_seen_subcommand_from absorb" -a "--branch --clone-mode --preserve-history --push --message --force --dry-run --json --json-pretty full partial (__git_nest_subprojects)"
complete -c git-nest -f -n "__fish_seen_subcommand_from inline" -a "--commit --message --dry-run --json --json-pretty (__git_nest_subprojects)"
complete -c git-nest -f -n "__fish_seen_subcommand_from detach" -a "--dry-run --json --json-pretty (__git_nest_subprojects)"
complete -c git-nest -f -n "__fish_seen_subcommand_from status" -a "--recursive --porcelain --json --json-pretty --exit-code"
complete -c git-nest -f -n "__fish_seen_subcommand_from outdated" -a "--recursive --porcelain --json --json-pretty"
complete -c git-nest -f -n "__fish_seen_subcommand_from verify" -a "--recursive --json --json-pretty"
complete -c git-nest -f -n "__fish_seen_subcommand_from restore" -a "--recursive --prune --force --dry-run"
complete -c git-nest -f -n "__fish_seen_subcommand_from doctor" -a "--json --json-pretty --offline --timeout --exit-code"
complete -c git-nest -f -n "__fish_seen_subcommand_from discover" -a "--max-depth --exclude --porcelain --json --json-pretty"
complete -c git-nest -f -n "__fish_seen_subcommand_from list" -a "--porcelain --json --json-pretty"
complete -c git-nest -f -n "__fish_seen_subcommand_from diff" -a "--since --stat --json --json-pretty"
complete -c git-nest -f -n "__fish_seen_subcommand_from log" -a "--max-count --since --until --subproject --oneline --recursive"
complete -c git-nest -f -n "__fish_seen_subcommand_from snapshot" -a "--recursive --quiet --dry-run --check --strict --no-fetch (__git_nest_subprojects)"
complete -c git-nest -f -n "__fish_seen_subcommand_from branch-list" -a "--verbose --json"
complete -c git-nest -f -n "__fish_seen_subcommand_from freeze" -a "--force --only --dry-run"
complete -c git-nest -f -n "__fish_seen_subcommand_from foreach-modified" -a "--continue-on-error --porcelain --json --json-pretty"
complete -c git-nest -f -n "__fish_seen_subcommand_from foreach-clean" -a "--continue-on-error --porcelain --json --json-pretty"
complete -c git-nest -f -n "__fish_seen_subcommand_from config" -a "get set list unset clone-mode full partial"
complete -c git-nest -f -n "__fish_seen_subcommand_from remove rm detach move mv update config" -a "(__git_nest_subprojects)"
EOF
}

# Print shell completion scripts.
cmd_completion() {
    [ $# -eq 1 ] || usage_error "usage: git-nest completion <bash|zsh|fish>"
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
        printf 'tool=git-nest %s\n' "$GIT_NEST_VERSION"
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
            precondition_error "cannot export missing subproject $path; run git-nest restore"
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

    stage=$(mktemp -d "${TMPDIR:-/tmp}/git-nest-export.XXXXXX") ||
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

# Compute a self-documenting, timestamped recovery-backup directory name for an
# interrupted-safe conversion. The name alone signals that it is a transient
# git-nest artifact tied to one operation on one path.
recovery_backup_dir() {
    printf '%s-%s-%s-%s\n' "$RECOVERY_BACKUP_PREFIX" "$1" "$(basename -- "$2")" "$(backup_timestamp)"
}

# Resolve the repo-local exclude file (.git/info/exclude). It is never committed,
# so it is the right place for the transient recovery-dir ignore rule: git status
# stays clean during the conversion without polluting the tracked .gitignore.
git_local_exclude_file() {
    gle_dir=$(git rev-parse --git-path info 2>/dev/null) || return 1
    [ -n "$gle_dir" ] || return 1
    mkdir -p "$gle_dir" 2>/dev/null || true
    printf '%s/exclude\n' "$gle_dir"
}

# Add an on-demand, self-explanatory ignore rule for a recovery dir to the
# repo-local exclude file. Added before the backup exists and removed on success.
recovery_exclude_add() {
    re_dir=$1
    re_file=$(git_local_exclude_file) || return 0
    grep -Fxq "$re_dir/" "$re_file" 2>/dev/null && return 0
    {
        printf '# git-nest transient conversion backup (auto-removed on success); if left, see %s/RECOVERY.txt\n' "$re_dir"
        printf '%s/\n' "$re_dir"
    } >>"$re_file"
}

# Remove the on-demand recovery-dir ignore rule (and its comment) after success.
recovery_exclude_remove() {
    rr_dir=$1
    rr_file=$(git_local_exclude_file) || return 0
    [ -f "$rr_file" ] || return 0
    rr_tmp=$(tmp_for "$rr_file")
    awk -v d="$rr_dir/" -v c="# git-nest transient conversion backup" '
        # Drop the comment line that names this dir and the ignore entry itself.
        index($0, c) && index($0, d) { next }
        {
            t = $0
            sub(/^[[:space:]]+/, "", t)
            sub(/[[:space:]]+$/, "", t)
            if (t == d) next
            print
        }
    ' "$rr_file" >"$rr_tmp"
    mv "$rr_tmp" "$rr_file"
}

# Write a plain-language recovery guide inside a backup dir so a human who finds
# a leftover after an interrupted conversion knows exactly what it is and how to
# restore or remove it. This is the same "make hidden state visible" goal that
# motivates git-nest over bare submodules.
write_recovery_note() {
    wr_dir=$1
    wr_op=$2
    wr_path=$3
    wr_steps=$4
    # Substitute the real backup directory for the <this-dir> placeholder so the
    # printed steps are copy-pasteable.
    wr_steps=$(printf '%s' "$wr_steps" | sed "s#<this-dir>#$wr_dir#g")
    cat >"$wr_dir/RECOVERY.txt" <<EOF
git-nest transient conversion backup
====================================
Operation : $wr_op
Subproject: $wr_path
Created   : $(utc_now)

git-nest creates this directory only while it performs the conversion, and
removes it automatically when the conversion succeeds. If git-nest is not
running and this directory is still here, the conversion was interrupted.

To recover:

$wr_steps

Once you have recovered, or if you are sure you no longer need it, delete it:

    rm -rf "$wr_dir"
EOF
}

# Begin a recovery backup: create the directory, ignore it locally, and drop a
# recovery note. Echoes the directory path for the caller to fill and finish.
begin_recovery_backup() {
    br_op=$1
    br_path=$2
    br_steps=$3
    br_dir=$(recovery_backup_dir "$br_op" "$br_path")
    recovery_exclude_add "$br_dir"
    mkdir -p "$br_dir" || git_error "failed to create recovery backup $br_dir"
    write_recovery_note "$br_dir" "$br_op" "$br_path" "$br_steps"
    printf '%s\n' "$br_dir"
}

# Finish a recovery backup on success: remove the directory and its local ignore.
end_recovery_backup() {
    er_dir=$1
    [ -n "$er_dir" ] || return 0
    rm -rf -- "$er_dir"
    recovery_exclude_remove "$er_dir"
}

# Copy a path into a recovery backup under a fixed "original" subdirectory.
copy_path_backup() {
    src=$1
    dst=$2
    mkdir -p "$(dirname -- "$dst")" || git_error "failed to create backup parent for $dst"
    cp -R "$src" "$dst" || git_error "failed to back up $src to $dst"
}

# Build a history-preserving subproject repo from tracked outer files using
# git-filter-repo. Used by the files source of absorb with --preserve-history.
absorb_files_preserve_history_repo() {
    path=$1
    branch=$2
    remote_url=$3
    tmp_parent=$4
    if ! command -v git-filter-repo >/dev/null 2>&1; then
        precondition_error "absorb --preserve-history requires git-filter-repo; install it from https://github.com/newren/git-filter-repo and rerun"
    fi
    filtered=$tmp_parent/filtered
    git clone --no-hardlinks . "$filtered" >/dev/null 2>&1 ||
        git_error "failed to clone outer repository for history-preserving absorb"
    (
        cd "$filtered" || exit 1
        git-filter-repo --path "$path/" --path-rename "$path/": --force >/dev/null 2>&1 ||
            git_error "git-filter-repo failed while absorbing $path"
        git branch -M "$branch" || git_error "failed to rename absorbed branch to $branch"
        git remote remove origin >/dev/null 2>&1 || true
        git remote add origin "$remote_url" || git_error "failed to set absorbed origin"
    )
    rm -rf -- "$path" || git_error "failed to replace $path with absorbed repository"
    cp -R "$filtered" "$path" || git_error "failed to install absorbed repository at $path"
}

# Build a fresh single-commit subproject repo from tracked outer files. Used by
# the files source of absorb without --preserve-history.
absorb_files_snapshot_repo() {
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
        git add -A || git_error "failed to stage absorbed files in $path"
        git commit --allow-empty -m "$message" >/dev/null ||
            git_error "failed to create initial absorb commit in $path"
    )
}

# Print the .gitmodules submodule name whose recorded path equals <path>, or
# return nonzero when the outer repo has no submodule registered at that path.
outer_submodule_name_for_path() {
    osp_path=$1
    [ -f .gitmodules ] || return 1
    osp_name=$(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk -v p="$osp_path" '
        { key=$1; $1=""; sub(/^ /, ""); if ($0 == p) { n=key; sub(/^submodule\./, "", n); sub(/\.path$/, "", n); print n; exit } }')
    [ -n "$osp_name" ] || return 1
    printf '%s\n' "$osp_name"
}

# Classify what lives at <path> so absorb can auto-route to the right handler.
# Prints exactly one of: subproject | submodule | nested-repo | files.
absorb_detect_source() {
    ads_path=$1
    # An existing manifest entry means it is already managed by the nest.
    if [ -n "$(subproject_repo "$ads_path" || true)" ]; then
        printf 'subproject\n'
        return 0
    fi
    # A matching .gitmodules entry means the outer repo tracks it as a submodule,
    # even when the submodule is not yet checked out.
    if outer_submodule_name_for_path "$ads_path" >/dev/null 2>&1; then
        printf 'submodule\n'
        return 0
    fi
    # A .git dir or gitlink file that is not a registered submodule is a
    # standalone nested repository already sitting in the workspace.
    if [ -e "$ads_path/.git" ]; then
        printf 'nested-repo\n'
        return 0
    fi
    # Anything else is ordinary outer-repository content (the former extract).
    printf 'files\n'
}

# Refuse when a directory hides deeper nested repositories or submodules that
# absorb would silently swallow. Preserving repository boundaries is a hard rule.
assert_no_deeper_repos() {
    andr_path=$1
    # Any .git below the immediate level is a deeper repo or submodule checkout.
    deeper=$(find "$andr_path" -mindepth 2 -name .git 2>/dev/null | sed -n '1p')
    [ -z "$deeper" ] || precondition_error "$andr_path contains a deeper nested repository at $(dirname -- "$deeper"); absorb or remove it explicitly first"
    # A .gitmodules inside the directory declares embedded submodules.
    [ ! -f "$andr_path/.gitmodules" ] || precondition_error "$andr_path declares Git submodules in $andr_path/.gitmodules; handle them explicitly before absorb"
}

# Stage the given outer-repository paths only when an outer Git work tree exists,
# so absorb still works inside copied-manifest folders that have no outer .git.
stage_outer_paths_if_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    stage_outer_paths "$@"
}

# Absorb ordinary outer-repository tracked files into a new managed subproject.
# This is the former extract behavior: it requires a remote URL so the resulting
# subproject is restorable on a fresh clone. Reads parsed globals from cmd_absorb.
absorb_files() {
    [ -n "$repo_arg" ] || usage_error "absorbing outer-repository files needs a remote URL: git-nest absorb <path> <remote-url> [options]"
    [ -n "$message" ] || message="Absorb $path"
    assert_path_not_containing_nested_project "$path"
    [ -d "$path" ] || precondition_error "$path is not a directory"
    if ! git ls-files -- "$path" | sed -n '1p' | grep . >/dev/null 2>&1; then
        precondition_error "$path has no tracked outer-repository files to absorb; commit these files in the outer repo first, then rerun absorb"
    fi
    # Refuse to clobber staged edits under the path unless the caller forces it.
    staged_under_path=$(git diff --cached --name-only -- "$path" 2>/dev/null | sed -n '1p')
    if [ -n "$staged_under_path" ] && [ "$force" -eq 0 ]; then
        precondition_error "$path has staged outer-repository changes; review them or rerun absorb with --force to replace that staged state"
    fi

    if [ "$dry_run" -eq 1 ]; then
        [ "$json" -eq 0 ] || GIT_NEST_JSON_DRY_RUN=1
        if [ "$json" -eq 1 ]; then
            json_single_row_result "$pretty" absorb 1 A "$path" files "$branch" - "$repo_arg" "would absorb outer-repo files as a subproject"
        else
            printf 'Would absorb outer-repo files %s into subproject %s on branch %s.\n' "$path" "$repo_arg" "$branch"
            [ "$push_after" -eq 1 ] && printf 'Would push %s to origin/%s.\n' "$path" "$branch"
        fi
        return 0
    fi
    unstaged_under_path=$(git diff --name-only -- "$path" 2>/dev/null | sed -n '1p')
    [ -z "$unstaged_under_path" ] || precondition_error "$path has unstaged content changes; commit these files in the outer repo first, then rerun absorb"
    untracked_under_path=$(git ls-files --others --exclude-standard -- "$path" 2>/dev/null | sed -n '1p')
    [ -z "$untracked_under_path" ] || precondition_error "$path has untracked files; commit these files in the outer repo first, then rerun absorb"
    if [ "$preserve_history" -eq 1 ] && ! command -v git-filter-repo >/dev/null 2>&1; then
        precondition_error "absorb --preserve-history requires git-filter-repo; install it from https://github.com/newren/git-filter-repo and rerun"
    fi
    # A push target must exist and be empty; overriding non-empty remotes is out.
    if [ "$push_after" -eq 1 ]; then
        remote_refs=$(mktemp)
        if ! git ls-remote "$repo_arg" >"$remote_refs" 2>/dev/null; then
            rm -f "$remote_refs"
            precondition_error "cannot reach absorb remote $repo_arg"
        fi
        if [ -s "$remote_refs" ]; then
            rm -f "$remote_refs"
            precondition_error "absorb remote $repo_arg is not empty; overriding non-empty remotes is deliberately not implemented"
        fi
        rm -f "$remote_refs"
    fi

    ensure_gitignore_hygiene
    tmp_parent=$(mktemp -d "${TMPDIR:-/tmp}/git-nest-absorb.XXXXXX") ||
        die "cannot create absorb temporary directory"
    # Optionally keep the path's history with git-filter-repo, or snapshot it as a
    # fresh single commit. The history rewrite is destructive, so first make an
    # on-demand, self-documenting recovery backup that is cleaned up on success.
    if [ "$preserve_history" -eq 1 ]; then
        backup=$(begin_recovery_backup "absorb --preserve-history" "$path" \
"    rm -rf \"$path\"
    mv \"<this-dir>/original\" \"$path\"

This restores the original files that were at $path before the history rewrite.")
        copy_path_backup "$path" "$backup/original"
        absorb_files_preserve_history_repo "$path" "$branch" "$repo_arg" "$tmp_parent"
    else
        backup=
        absorb_files_snapshot_repo "$path" "$branch" "$repo_arg" "$message"
    fi
    rm -rf "$tmp_parent"
    if [ "$push_after" -eq 1 ]; then
        git -C "$path" push -u origin "$branch" || git_error "failed to push absorbed subproject $path"
        pushed_remote=$(git ls-remote "$repo_arg" "refs/heads/$branch" 2>/dev/null | awk 'NR == 1 { print $1 }')
        local_head=$(resolve_head_commit "$path" "cannot resolve absorbed subproject $path")
        [ "$pushed_remote" = "$local_head" ] ||
            git_error "pushed branch $branch on $repo_arg did not resolve to expected commit"
    fi
    revision=$(resolve_head_commit "$path" "cannot resolve absorbed subproject $path")
    # Snapshot output values before mutating helpers reuse the global path/branch.
    emit_path=$path
    emit_branch=$branch
    emit_url=$repo_arg
    emit_revision=$revision
    git rm -r --cached -- "$path" >/dev/null 2>&1 ||
        git_error "failed to untrack absorbed files from outer repository"
    ensure_gitignore_entry "$path"
    manifest_write_subproject "$path" "$repo_arg" tracked "$branch" "$revision" "$clone_mode"
    write_materialized_state
    stage_outer_paths "$MANIFEST_FILE" .gitignore
    # Success: drop the recovery backup and its local ignore rule.
    end_recovery_backup "$backup"
    if [ "$json" -eq 1 ]; then
        json_single_row_result "$pretty" absorb 1 A "$emit_path" files "$emit_branch" "$emit_revision" "$emit_url" "absorbed outer-repo files as a subproject"
    else
        printf 'Absorbed %s as a git-nest subproject at %.12s.\n' "$emit_path" "$emit_revision"
        [ "$push_after" -eq 1 ] || printf 'Push when ready with: git -C %s push -u origin %s\n' "$emit_path" "$emit_branch"
    fi
}

# Absorb an existing on-disk Git repository (a standalone nested repo, or a
# submodule) into the nest as a managed subproject, keeping its own history.
# Reads parsed globals from cmd_absorb; $source selects the exact behavior.
absorb_existing_repo() {
    # File-only options do not apply to existing repositories; reject them so the
    # user is not misled into thinking history is being rewritten.
    if [ "$branch_set" -eq 1 ] || [ "$preserve_history" -eq 1 ] || [ "$push_after" -eq 1 ] || [ -n "$message" ]; then
        usage_error "--branch, --preserve-history, --push, and --message only apply when absorbing outer-repository files"
    fi

    if [ "$source" = submodule ]; then
        # Read the submodule wiring from the outer repo before changing anything.
        sub_name=$(outer_submodule_name_for_path "$path") ||
            precondition_error "$path is not a registered submodule"
        [ -e "$path/.git" ] || precondition_error "submodule $path is not checked out; run git submodule update --init -- $path first, then rerun absorb"
        sub_url=$(git config -f .gitmodules --get "submodule.$sub_name.url" 2>/dev/null || true)
        url=${repo_arg:-$sub_url}
        [ -n "$url" ] || precondition_error "submodule $path has no URL to record; pass a remote URL to absorb it"
        sub_branch=$(git config -f .gitmodules --get "submodule.$sub_name.branch" 2>/dev/null || true)
    else
        # Standalone nested repository: take its origin URL unless overridden.
        [ -e "$path/.git" ] || precondition_error "$path is not a Git repository"
        origin_url=$(git -C "$path" remote get-url origin 2>/dev/null || true)
        url=${repo_arg:-$origin_url}
        [ -n "$url" ] || precondition_error "$path has no origin remote; pass a remote URL so restore can reach it: git-nest absorb $path <remote-url>"
        sub_branch=
    fi
    assert_no_deeper_repos "$path"

    # Resolve the commit to pin. Prefer the checked-out HEAD; fall back to the
    # recorded gitlink for a submodule that is only present as an index entry.
    if [ -e "$path/.git" ]; then
        revision=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
    else
        revision=$(git ls-files -s -- "$path" 2>/dev/null | awk 'NR == 1 { print $2 }')
    fi
    [ -n "$revision" ] || precondition_error "cannot resolve a commit for $path; check the repository state"
    # Choose the target branch: an explicit submodule branch, else the current
    # branch, else the origin default.
    target=$sub_branch
    if [ -z "$target" ] && [ -e "$path/.git" ]; then
        target=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
        [ -n "$target" ] || target=$(default_target_branch "$path")
    fi
    [ -n "$target" ] || target=main

    # Snapshot output values before any mutating helper runs. Helpers such as
    # write_materialized_state and hook installation reuse the global variables
    # path/repo/target, so reporting must read from these stable copies instead.
    emit_path=$path
    emit_source=$source
    emit_target=$target
    emit_revision=$revision
    emit_url=$url

    if [ "$dry_run" -eq 1 ]; then
        [ "$json" -eq 0 ] || GIT_NEST_JSON_DRY_RUN=1
        if [ "$json" -eq 1 ]; then
            json_single_row_result "$pretty" absorb 1 A "$emit_path" "$emit_source" "$emit_target" "$emit_revision" "$emit_url" "would absorb existing $emit_source into the nest"
        else
            printf 'Would absorb %s %s into the nest as a subproject at %.12s (remote %s).\n' "$emit_source" "$emit_path" "$emit_revision" "$emit_url"
        fi
        return 0
    fi

    ensure_gitignore_hygiene
    if [ "$source" = submodule ]; then
        # Convert the submodule into a standalone repository while keeping files:
        # drop the gitlink, relocate the module git dir into the checkout, and
        # remove submodule registration from .gitmodules and .git/config.
        git rm --cached -- "$path" >/dev/null 2>&1 ||
            git_error "failed to unregister submodule gitlink for $path"
        module_dir=$(git -C "$path" rev-parse --absolute-git-dir 2>/dev/null || true)
        if [ -f "$path/.git" ] && [ -n "$module_dir" ] && [ -d "$module_dir" ]; then
            rm -f "$path/.git" || git_error "failed to remove submodule gitlink file in $path"
            mv "$module_dir" "$path/.git" || git_error "failed to relocate submodule git dir into $path"
            # Operate on the config file directly: the stale core.worktree points
            # at the old module location, so `git -C "$path"` cannot run until it
            # is unset. Removing it lets Git default the work tree to the checkout.
            git config --file "$path/.git/config" --unset core.worktree 2>/dev/null || true
        fi
        git config -f .gitmodules --remove-section "submodule.$sub_name" >/dev/null 2>&1 || true
        # Drop an emptied .gitmodules so the outer tree stays tidy.
        if [ -f .gitmodules ] && [ ! -s .gitmodules ]; then
            rm -f .gitmodules
        elif [ -f .gitmodules ] && ! git config -f .gitmodules --get-regexp '^submodule\.' >/dev/null 2>&1; then
            rm -f .gitmodules
        fi
        git config --remove-section "submodule.$sub_name" >/dev/null 2>&1 || true
    else
        # A standalone nested repo may still be tracked by the outer repo as plain
        # files or an embedded gitlink; untrack it so only the manifest owns it.
        if git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
            git rm -r --cached -- "$path" >/dev/null 2>&1 ||
                git_error "failed to untrack $path from the outer repository"
        fi
    fi
    ensure_gitignore_entry "$path"
    manifest_write_subproject "$path" "$url" tracked "$target" "$revision" "$clone_mode"
    install_hooks_in_repo_if_project_managed "$path"
    write_materialized_state
    stage_outer_paths_if_repo "$MANIFEST_FILE" .gitignore
    [ -f .gitmodules ] && stage_outer_paths_if_repo .gitmodules || true
    if [ "$json" -eq 1 ]; then
        json_single_row_result "$pretty" absorb 1 A "$emit_path" "$emit_source" "$emit_target" "$emit_revision" "$emit_url" "absorbed existing $emit_source into the nest"
    else
        printf 'Absorbed %s %s as a git-nest subproject at %.12s (remote %s).\n' "$emit_source" "$emit_path" "$emit_revision" "$emit_url"
    fi
}

# absorb brings something already on disk into the nest as a managed subproject,
# auto-detecting the source: outer-repository files, a standalone nested repo, or
# a submodule. It is the single into-the-nest conversion verb; add clones a new
# remote, while inline, detach, and remove take subprojects back out of the nest.
cmd_absorb() {
    branch=main
    branch_set=0
    clone_mode=
    preserve_history=0
    push_after=0
    message=
    force=0
    dry_run=0
    json=0
    pretty=0
    path_arg=
    repo_arg=
    while [ $# -gt 0 ]; do
        case "$1" in
            --branch)
                [ $# -ge 2 ] || usage_error "--branch requires a name"
                branch=$2
                branch_set=1
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
            --json) json=1; shift ;;
            --json-pretty) json=1; pretty=1; shift ;;
            --*) usage_error "unknown absorb option: $1" ;;
            *)
                if [ -z "$path_arg" ]; then
                    path_arg=$1
                elif [ -z "$repo_arg" ]; then
                    repo_arg=$1
                else
                    usage_error "usage: git-nest absorb <path> [<remote-url>] [options]"
                fi
                shift
                ;;
        esac
    done
    [ -n "$path_arg" ] || usage_error "usage: git-nest absorb <path> [<remote-url>] [options]"
    reject_backslash_path "$path_arg"
    path=$(normalize_path "$path_arg")

    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$path"
    # Route by source type; refuse when the path is already managed so the old
    # reversed meaning of absorb can never run by accident.
    source=$(absorb_detect_source "$path")
    case "$source" in
        subproject)
            precondition_error "$path is already a nest subproject; use git-nest inline, git-nest detach, or git-nest remove to take it out of the nest"
            ;;
        files) absorb_files ;;
        nested-repo|submodule) absorb_existing_repo ;;
        *) die "internal error: unknown absorb source $source" ;;
    esac
}

# inline dissolves a managed subproject back into the outer repository as ordinary
# tracked files, discarding the subproject's separate Git identity. It is the
# opposite of absorbing outer-repository files. The remote is left untouched.
cmd_inline() {
    commit_after=0
    message=
    dry_run=0
    json=0
    pretty=0
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
            --json) json=1; shift ;;
            --json-pretty) json=1; pretty=1; shift ;;
            --*) usage_error "unknown inline option: $1" ;;
            *)
                [ -z "$path_arg" ] || usage_error "usage: git-nest inline <path> [--commit] [--message <msg>] [--dry-run] [--json|--json-pretty]"
                path_arg=$1
                shift
                ;;
        esac
    done
    [ -n "$path_arg" ] || usage_error "usage: git-nest inline <path> [--commit] [--message <msg>] [--dry-run] [--json|--json-pretty]"
    reject_backslash_path "$path_arg"
    path=$(normalize_path "$path_arg")
    [ -n "$message" ] || message="Inline subproject $path"

    acquire_manifest_lock
    ensure_manifest
    validate_manifest_schema
    assert_path_not_inside_nested_project "$path"
    [ -d "$path/.git" ] || precondition_error "$path is not a checked-out subproject"
    [ ! -f "$path/$MANIFEST_FILE" ] || precondition_error "$path is a nested git-nest project; recursive inline is not supported yet"
    repo=$(subproject_repo "$path" || true)
    [ -n "$repo" ] || precondition_error "$path is not a tracked subproject in $MANIFEST_FILE"
    # Refuse to dissolve local-only work, which would be unrecoverable once the
    # subproject's own history is discarded.
    reason=$(stale_subproject_safety_reason "$path")
    [ -z "$reason" ] || precondition_error "$path $reason; push or remove local-only work before inline"

    # Snapshot output values before mutating helpers reuse the global variables.
    emit_path=$path
    emit_repo=$repo
    if [ "$dry_run" -eq 1 ]; then
        [ "$json" -eq 0 ] || GIT_NEST_JSON_DRY_RUN=1
        if [ "$json" -eq 1 ]; then
            json_single_row_result "$pretty" inline 1 I "$emit_path" inlined - - "$emit_repo" "would inline into outer files"
        else
            printf 'Would inline %s into the outer repository and leave remote %s untouched.\n' "$emit_path" "$emit_repo"
            [ "$commit_after" -eq 1 ] && printf 'Would commit outer changes with message: %s\n' "$message"
        fi
        return 0
    fi

    # Deleting the subproject's .git is destructive, so first make an on-demand,
    # self-documenting recovery backup that is cleaned up on success.
    backup=$(begin_recovery_backup "inline" "$path" \
"    mv \"<this-dir>/.git\" \"$path/.git\"
    git -C \"$path\" status

Then unstage the outer-repo changes that inline staged:

    git restore --staged \"$path\" .gitnest .gitignore")
    cp -R "$path/.git" "$backup/.git" || git_error "failed to back up $path/.git"
    rm -rf -- "$path/.git" || git_error "failed to remove nested Git metadata from $path"
    manifest_remove_section "$(subproject_section "$path")"
    remove_gitignore_entry "$path"
    write_materialized_state
    stage_outer_paths "$MANIFEST_FILE" .gitignore "$path"
    if [ "$commit_after" -eq 1 ]; then
        git commit -m "$message" ||
            git_error "failed to commit inlined subproject $path; staged files remain and a recovery backup is in $backup (see $backup/RECOVERY.txt). Restore with: mv $backup/.git $path/.git; then git restore --staged $path .gitnest .gitignore"
    fi
    # Success: drop the recovery backup and its local ignore rule.
    end_recovery_backup "$backup"
    if [ "$json" -eq 1 ]; then
        json_single_row_result "$pretty" inline 1 I "$emit_path" inlined - - "$emit_repo" "inlined into outer files"
    else
        printf 'Inlined %s into the outer repository; remote %s was not changed.\n' "$emit_path" "$emit_repo"
    fi
}

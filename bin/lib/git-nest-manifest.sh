#!/bin/sh
#
# git-nest: record and restore reproducible nests of independent Git repositories.
# https://github.com/f-steff/git-nest
#
# Core manifest and helper functions for git-nest.
# Sourced by bin/git-nest-main.sh and its library modules.
#
# Copyright (c) 2026 Flemming Steffensen.
# License: MIT
# SPDX-License-Identifier: MIT

# Print a user-facing error and stop the current command with a nonzero exit.
die() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

# Single-quote a value (typically a path) for safe embedding in a suggested
# shell command shown to the user, e.g. "run: git -C <path> checkout main" in
# pull's summary or "run git-nest absorb <path>" in discover/survey's
# next-step hints. Without this, a path containing a space or other shell
# metacharacter would print a suggestion that looks correct but breaks or
# does the wrong thing if the user copies and pastes it verbatim.
#
# Only quotes when the value actually needs it (matches the same safe
# character class tests/integration-tests/helper.sh's print_command already
# uses), so an ordinary path prints exactly as before and only a path with a
# space or other shell metacharacter gains quotes.
shell_quote() {
	case "$1" in
	*[!A-Za-z0-9_./:=,@%+-]* | '')
		printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
		;;
	*) printf '%s' "$1" ;;
	esac
}

# Exit with the given code after printing an Error: line on stderr; the
# dedicated wrappers below give each error class its own stable exit code.
die_code() {
	code=$1
	shift
	printf 'Error: %s\n' "$*" >&2
	exit "$code"
}

# Fail with the usage-error code for invalid command-line usage.
usage_error() {
	die_code "$EXIT_USAGE" "$@"
}

# Fail with the precondition-error code for invalid workspace state.
precondition_error() {
	die_code "$EXIT_PRECONDITION" "$@"
}

# Fail with the git-error code after a Git operation fails.
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

# Validate that a value is a positive integer (for timeout/depth options)
# before it is used in arithmetic or passed to external tools.
validate_positive_integer() {
	vpi_value=$1
	vpi_name=$2
	case "$vpi_value" in
	*[!0-9]* | "") usage_error "$vpi_name requires a positive integer" ;;
	esac
	[ "$vpi_value" -gt 0 ] || usage_error "$vpi_name requires a positive integer"
}

# Remove the manifest lock directory if this process holds it, so an
# interrupted command never leaves the workspace locked.
cleanup_manifest_lock() {
	if [ -n "$MANIFEST_LOCK_HELD" ] && [ -n "$MANIFEST_LOCK_PATH" ]; then
		rm -rf "$MANIFEST_LOCK_PATH" 2>/dev/null || true
		MANIFEST_LOCK_HELD=
	fi
}

# Install EXIT/INT/TERM traps that release the manifest lock, so locks are
# never left behind even when a command dies unexpectedly (idempotent).
install_exit_handler() {
	[ "$GIT_NEST_EXIT_HANDLER_INSTALLED" -eq 0 ] || return 0
	trap 'status=$?; cleanup_manifest_lock; exit $status' EXIT
	trap 'cleanup_manifest_lock; trap - INT; kill -INT $$' INT
	trap 'cleanup_manifest_lock; trap - TERM; kill -TERM $$' TERM
	GIT_NEST_EXIT_HANDLER_INSTALLED=1
}

# Sleep for a fractional number of milliseconds; uses awk to compute the
# fractional seconds, because not all sleep implementations support sub-second
# arguments (e.g. macOS sleep accepts "0.1" but has a fixed limit of 1s resolution
# before macOS 13, and busybox sleep ignores sub-second values).
# LC_NUMERIC=C ensures awk always produces a dot decimal (e.g. "0.050") regardless
# of the user's locale -- non-C locales may emit "0,050" which macOS sleep rejects.
sleep_ms() {
	ms=$1
	seconds=$(LC_NUMERIC=C awk -v ms="$ms" 'BEGIN { printf "%.3f", ms / 1000 }')
	sleep "$seconds"
}

# Print the current UTC timestamp in ISO-8601 form for reproducible metadata.
utc_now() {
	date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# Acquire the manifest lock directory with exponential backoff up to the
# configured timeout; concurrent commands wait rather than corrupt the file.
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

# Escape a stream on stdin into a JSON string body (quotes, backslashes, and
# control characters), used by json_string for safe machine output.
json_escape() {
	command awk '
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

# Print a value as a quoted, escaped JSON string.
json_string() {
	printf '"'
	printf '%s' "$1" | json_escape
	printf '"'
}

# Build one JSON object for a porcelain row (code/path/state/target/current/
# expected/detail) so machine output has one stable shape everywhere.
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

# Print a JSON array of strings from a line-per-entry file (skipping blanks).
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

# Print a JSON array of row objects parsed from a tab-separated porcelain file,
# used by commands that reuse status-style output for their JSON form.
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

# Emit the shared JSON output envelope (rows/errors/warnings arrays plus
# ok/recursive flags) so every command's JSON form is consistent.
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

# Redact sensitive and user-specific substrings from a text or JSON stream so
# machine output can be shared safely: strip credentials embedded in URLs
# (scheme://user:token@host -> scheme://***@host) and replace the home directory
# with ~. Used by --redact on the diagnostics commands.
redact_stream() {
	if [ -n "${HOME:-}" ]; then
		redact_home=$(printf '%s' "$HOME" | sed 's/[^A-Za-z0-9_/-]/\\&/g')
		sed -E -e 's#([A-Za-z][A-Za-z0-9+.-]*://)[^/@" ]+@#\1***@#g' -e "s#$redact_home#~#g"
	else
		sed -E -e 's#([A-Za-z][A-Za-z0-9+.-]*://)[^/@" ]+@#\1***@#g'
	fi
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

# Escape a string for use in a BRE/ERE pattern, so user input is matched
# literally inside sed/grep expressions.
regex_escape() {
	printf '%s\n' "$1" | sed 's/[][(){}.^$*+?|\\-]/\\&/g'
}

# Resolve HEAD for callers that need the current commit, such as add/upload.
resolve_head_commit() {
	repo=$1
	context=$2
	resolve_commit "$repo" HEAD "$context"
}

# Ensure Git is available before commands depend on it.
require_git() {
	command -v git >/dev/null 2>&1 || die "git is required"
}

# Resolve a path to its canonical absolute form (following symlinks when
# readlink exists) so manifest lookups are stable regardless of invocation
# directory or link structure.
canonical_start_dir_for_path() {
	target=$1
	[ -e "$target" ] || precondition_error "$target does not exist; cannot locate owning $MANIFEST_FILE"
	resolved=
	if command -v readlink >/dev/null 2>&1; then
		resolved=$(readlink -f -- "$target" 2>/dev/null || true)
	fi
	[ -n "$resolved" ] || resolved=$target
	if [ -d "$resolved" ]; then
		(CDPATH='' cd -P -- "$resolved" && pwd) ||
			precondition_error "cannot resolve path $target"
	else
		dir=$(dirname -- "$resolved")
		(CDPATH='' cd -P -- "$dir" && pwd) ||
			precondition_error "cannot resolve path $target"
	fi
}

# Walk upward to find the nearest owning manifest. This never walks downward;
# recursive operations use purpose-specific traversal helpers.
# Accepts an optional starting path; defaults to the current directory.
find_owning_manifest() {
	dir=$(canonical_start_dir_for_path "${1:-.}")
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

# Print the absolute path of the nest root (directory containing the owning
# manifest) or fail silently for callers that tolerate "no nest".
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
		manifest_load_cache
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
	manifest_load_cache
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

# Return 0 only when .gitattributes contains the complete git-nest guard
# (all six owned entries), so tidy knows whether to refresh it.
gitattributes_has_guard() {
	[ -f .gitattributes ] || return 1
	awk '
        /^[[:space:]]*\.gitnest[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { gitnest=1 }
        /^[[:space:]]*\.gitnest-rc[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { rc=1 }
        /^[[:space:]]*bin\/git-nest[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { entrypoint=1 }
        /^[[:space:]]*bin\/git-nest-main\.sh[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { shell=1 }
        /^[[:space:]]*bin\/git-nest\.ps1[[:space:]]+text[[:space:]]+eol=lf[[:space:]]*$/ { ps=1 }
        /^[[:space:]]*bin\/git-nest\.bat[[:space:]]+text[[:space:]]+eol=crlf[[:space:]]*$/ { batch=1 }
        END { exit !(gitnest && rc && entrypoint && shell && ps && batch) }
    ' .gitattributes
}

# Print the full git-nest .gitattributes guard block (BEGIN/END markers plus
# the six owned entries) so every platform keeps the same line endings.
print_gitattributes_guard() {
	printf '%s\n' "$GITATTRIBUTES_BEGIN"
	printf '%s\n' "$GITATTRIBUTES_GUARD"
	printf '.gitnest-rc text eol=lf\n'
	printf 'bin/git-nest text eol=lf\n'
	printf 'bin/git-nest-main.sh text eol=lf\n'
	printf 'bin/git-nest.ps1 text eol=lf\n'
	printf 'bin/git-nest.bat text eol=crlf\n'
	printf '%s\n' "$GITATTRIBUTES_END"
}

# Create NEST_README.md in the nest root if it does not exist. The file is
# a short pointer for someone who clones the repository without having met
# git-nest: it says what the workspace is and how to materialize it with
# git-nest restore. It is created only by init (never by tidy), and never
# overwritten, so the maintainer can edit, commit, ignore, or delete it
# freely and tidy will not resurrect it.
ensure_nest_readme() {
	[ -f NEST_README.md ] && return 0
	cat >NEST_README.md <<'EOF'
# NEST_README - this repository is a git-nest workspace

This repository coordinates independent Git repositories (its
subprojects) through the `.gitnest` manifest. The subproject checkouts
are not part of a plain clone; they are materialized by git-nest.

## Restore the workspace

Install git-nest (https://github.com/f-steff/git-nest), then from a
fresh clone of this repository run:

    git-nest restore

This clones and checks out every subproject at the exact revision the
manifest pins, so the workspace is reproducible on any machine.

## Everyday commands

    git-nest status        show nest root and subproject state
    git-nest verify        validate the manifest and checkouts
    git-nest snapshot      record clean subproject revisions
    git-nest add <url> <path>   bring a repository into the nest
    git-nest update <path>      move a subproject to a new revision

See the project README and docs/ for the full command reference.
EOF
}

# Create or refresh the managed .gitattributes block, removing any stale
# git-nest entries outside the block and preserving user lines.
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
                if (trimmed ~ /^bin\/git-nest-main\.sh([[:space:]]|$)/) next
                if (trimmed ~ /^bin\/git-nest\.ps1([[:space:]]|$)/) next
                if (trimmed ~ /^bin\/git-nest\.bat([[:space:]]|$)/) next
                print
            }
        ' .gitattributes
	} >"$tmp"
	mv "$tmp" .gitattributes
}

# Warn once per run when the git-nest .gitattributes guard is missing, so
# users learn about the fix without repeated noise.
warn_missing_gitattributes_guard() {
	gitattributes_has_guard && return 0
	warn "missing or stale git-nest .gitattributes guard; run git-nest tidy to refresh it"
}

# Warn once when a hook written by the retired git-stack tool is detected, so
# users know to reinstall the current git-nest hook set.
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

# Run all startup warnings (gitattributes guard, old hooks) once per command.
project_invocation_warnings() {
	warn_missing_gitattributes_guard
	warn_old_managed_hooks
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

# Reject Windows-style backslash paths with guidance, because subproject
# paths are stored with forward slashes and backslashes would be ambiguous.
reject_backslash_path() {
	case "$1" in
	*[\\]*)
		suggested=$(printf '%s\n' "$1" | tr '\\' '/')
		usage_error "subproject paths must use forward slashes; got \"$1\". Use \"$suggested\"."
		;;
	esac
}

# Return 0 only for safe relative subproject paths: no absolute, parent
# escape, drive-letter, or Git-internal names.
path_is_relative_safe() {
	case "$1" in
	"" | /* | [A-Za-z]:* | ../* | */../* | .. | .) return 1 ;;
	.git | .gitnest | .gitnest.lock | .gitnest-rc | .gitignore | .gitattributes) return 1 ;;
	.git/* | */.git | */.git/*) return 1 ;;
	*) return 0 ;;
	esac
}

# Fail unless the given subproject path is a safe relative path inside the
# current project (used by every path-taking command before any writes).
assert_safe_project_path() {
	path=$1
	path_is_relative_safe "$path" ||
		precondition_error "path must be a relative path inside the current project: $path"
}

# Refuse a candidate path that lies inside any existing managed subproject,
# whether or not that subproject is itself a nested nest. A subproject's
# checkout belongs to its own repository, not the outer nest, so no new
# manifest entry, clone, or conversion may ever be created underneath one.
#
# Reads the boundary list from a temp file rather than piping directly into
# the while loop: piping runs the loop in a subshell, so a precondition_error
# (which calls exit) inside it would only terminate that subshell and let the
# caller silently continue past the guard instead of aborting the command.
assert_path_not_inside_nested_project() {
	candidate=$1
	assert_safe_project_path "$candidate"
	apinp_tmp=$(tmp_for "$MANIFEST_FILE.boundarycheck")
	manifest_subprojects >"$apinp_tmp"
	while IFS= read -r boundary; do
		[ -n "$boundary" ] || continue
		case "$candidate" in
		"$boundary"/*)
			rm -f "$apinp_tmp"
			if [ -f "$boundary/$MANIFEST_FILE" ]; then
				precondition_error "$candidate is inside nested project $boundary; run git-nest from $boundary instead"
			else
				precondition_error "$candidate is inside managed subproject $boundary; that path belongs to $boundary's own repository, not this nest"
			fi
			;;
		esac
	done <"$apinp_tmp"
	rm -f "$apinp_tmp"
}

# Refuse a new subproject path that differs from an existing managed path only by
# letter case. On case-insensitive filesystems (Windows, macOS) two such entries
# map to the same directory and would corrupt each other. Reads from a file, not
# a pipe, so precondition_error exits the whole command.
assert_no_case_collision() {
	ncc_path=$1
	ncc_lower=$(printf '%s' "$ncc_path" | tr '[:upper:]' '[:lower:]')
	ncc_tmp=$(tmp_for "$MANIFEST_FILE.casecheck")
	manifest_subprojects >"$ncc_tmp"
	while IFS= read -r ncc_existing; do
		[ -n "$ncc_existing" ] || continue
		# An exact match is handled by each command's own "already tracked" check.
		[ "$ncc_existing" = "$ncc_path" ] && continue
		ncc_existing_lower=$(printf '%s' "$ncc_existing" | tr '[:upper:]' '[:lower:]')
		if [ "$ncc_existing_lower" = "$ncc_lower" ]; then
			rm -f "$ncc_tmp"
			precondition_error "$ncc_path collides with existing subproject $ncc_existing on case-insensitive filesystems; choose a name that differs by more than letter case"
		fi
	done <"$ncc_tmp"
	rm -f "$ncc_tmp"
}

# Refuse a candidate path that contains a nested git-nest project, or that
# contains any existing managed subproject beneath it. A new subproject's
# working tree must belong entirely to the outer nest: converting a path that
# swallows another subproject's separately tracked checkout would merge two
# unrelated repositories' files together and corrupt both.
assert_path_not_containing_nested_project() {
	candidate=$1
	[ -d "$candidate" ] || return 0
	if find "$candidate" -mindepth 1 -name "$MANIFEST_FILE" -type f 2>/dev/null | sed -n '1p' | grep . >/dev/null 2>&1; then
		precondition_error "$candidate contains a nested git-nest project; recursive absorb is not supported yet"
	fi
	# See assert_path_not_inside_nested_project for why this reads from a temp
	# file rather than piping into the while loop.
	apcnp_tmp=$(tmp_for "$MANIFEST_FILE.containcheck")
	manifest_subprojects >"$apcnp_tmp"
	while IFS= read -r boundary; do
		[ -n "$boundary" ] || continue
		case "$boundary" in
		"$candidate"/*)
			rm -f "$apcnp_tmp"
			precondition_error "$candidate contains managed subproject $boundary; converting $candidate would swallow that subproject's separate checkout"
			;;
		esac
	done <"$apcnp_tmp"
	rm -f "$apcnp_tmp"
}

# Refuse creating a new nest (at the current directory) whose subtree would
# contain a path already registered as a subproject by an ancestor nest. This
# can only happen if a directory that is an ancestor of an already-registered
# deep subproject is later, retroactively, given its own Git repository and
# becomes a valid new nest root -- see todo.md (won't do: `init --adopt`) for
# the full scenario and why absorb itself cannot hit this (assert_no_deeper_repos
# and assert_path_not_containing_nested_project already guard every absorb
# path; only nest creation itself was missing this check). Called from
# cmd_init and absorb_all_ensure_nest before either creates anything at the
# new root.
#
# Walks the full ancestor chain, not just the nearest manifest (unlike
# nearest_parent_manifest_root): the premise of this bug is a broken
# invariant, so a second retroactive repo boundary stacked on the first could
# put the conflicting registration two ancestors up instead of one.
assert_new_nest_excludes_ancestor_subprojects() {
	anes_new_root=$(pwd -P)
	anes_dir=$anes_new_root
	anes_parent=$(dirname "$anes_dir")
	while [ "$anes_parent" != "$anes_dir" ]; do
		if [ -f "$anes_parent/$MANIFEST_FILE" ]; then
			anes_tmp=$(tmp_for "$MANIFEST_FILE.ancestorcheck")
			manifest_subprojects_from_file "$anes_parent/$MANIFEST_FILE" >"$anes_tmp"
			while IFS= read -r anes_rel; do
				[ -n "$anes_rel" ] || continue
				anes_abs=$anes_parent/$anes_rel
				case "$anes_abs" in
				"$anes_new_root"/*)
					anes_from_new=${anes_abs#"$anes_new_root"/}
					anes_parent_q=$(shell_quote "$anes_parent")
					anes_rel_q=$(shell_quote "$anes_rel")
					anes_from_new_q=$(shell_quote "$anes_from_new")
					rm -f "$anes_tmp"
					precondition_error "$anes_new_root would become a nest whose subtree contains $anes_abs, already managed as subproject $anes_rel by the nest at $anes_parent; resolve this manually: (cd $anes_parent_q && git-nest detach $anes_rel_q), retry this init here, then run git-nest absorb $anes_from_new_q"
					;;
				esac
			done <"$anes_tmp"
			rm -f "$anes_tmp"
		fi
		anes_dir=$anes_parent
		anes_parent=$(dirname "$anes_dir")
	done
}

# Stage outer-repository paths with git add, translating git failures into
# the standard git-error diagnostic.
stage_outer_paths() {
	git add -- "$@" || git_error "failed to stage outer repository changes"
}

# Create a temporary file next to a target file so later mv is same-directory.
tmp_for() {
	dir=$(dirname -- "$1")
	base=$(basename -- "$1")
	mktemp "$dir/.${base}.tmp.XXXXXX"
}

# Parse the manifest into shell variables via a single awk pass, then eval the
# result. This eliminates N-per-key subprocess overhead while keeping manifest
# reads O(1). The awk script outputs shell-assignable variable declarations with
# single-quote-safe value escaping.
manifest_load_cache() {
	# Re-load when entering a different working directory (nested nest recursion)
	# so the cache always reflects the current nest's manifest. The pair of
	# guards handles both fresh processes and subshell directory changes.
	if [ -n "${_MNF_LOADED:-}" ]; then
		[ "$_MNF_CACHED_PWD" = "$(pwd -P)" ] && return
	fi
	_MNF_LOADED=1
	_MNF_CACHED_PWD=$(pwd -P)
	[ -f "$MANIFEST_FILE" ] || return 0
	eval "$(awk -f "$SCRIPT_DIR/lib/git-nest-parse.awk" "$MANIFEST_FILE")"
}

# Build the encoded variable name for a section+key pair. Must match the naming
# convention used by manifest_load_cache (git-nest-parse.awk computes the same
# subproject hash independently; the two must always agree).
#
# The subproject path is hashed with cksum rather than lossily encoded by
# character substitution: a path may contain spaces or other characters that
# are not valid in a shell variable name (a literal space would previously
# break the "${...}" expansion in manifest_get with "bad substitution"), and a
# naive substitution (e.g. "-"/"." -> "_") can collide between two genuinely
# different paths ("libs/foo-bar" and "libs/foo.bar" would both encode to
# "libs_foo_bar"). cksum's output is deterministic for identical input and
# available on every platform this tool targets (POSIX-specified, present in
# GNU coreutils and BSD userland alike), so hashing the raw path keeps the
# variable name always well-formed and, for realistic subproject counts,
# effectively collision-free.
manifest_varname() {
	section=$1
	key=$2
	kee=$(printf '%s' "$key" | sed 's/[-.]/_/g')
	case "$section" in
	project) printf '_mnf_project_%s\n' "$kee" ;;
	subproject\ \"*\")
		path=${section#subproject \"}
		path=${path%\"}
		cksum_out=$(printf '%s' "$path" | cksum 2>/dev/null || printf '%s' "$path" | /usr/bin/cksum 2>/dev/null || printf '%s' "$path" | /bin/cksum 2>/dev/null)
		cksum_out=${cksum_out%% *}
		printf '_mnf_sp_%s_%s\n' "$cksum_out" "$kee"
		;;
	esac
}

# Read one key from one manifest section using the cached variable store.
# Falls back to file parsing when the cache has not been loaded (rare edge
# cases such as callers that source a bare manifest file path).
manifest_get() {
	manifest_load_cache
	section=$1
	key=$2
	if [ -z "${_MNF_LOADED:-}" ]; then
		manifest_get_from_file "$MANIFEST_FILE" "$section" "$key"
		return
	fi
	_v=$(manifest_varname "$section" "$key") || return 1
	eval "printf '%s' \"\${$_v:-}\""
}

# Read one key from one section in a specific manifest file. Used only for
# diff --since where the manifest is read at a different Git ref.
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

# Classify a manifest section header as project, subproject, or unknown so
# schema validation and rewriting treat each section type consistently.
manifest_section_kind() {
	section=$1
	case "$section" in
	project) printf 'project\n' ;;
	subproject\ \"*\") printf 'subproject\n' ;;
	*) printf 'unknown\n' ;;
	esac
}

# Validate the manifest schema (version, section structure, key allowlist)
# before any command trusts its content; collects all errors at once.
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
                revision = value_for[section SUBSEP "revision"]
                target = value_for[section SUBSEP "target_branch"]
                tag = value_for[section SUBSEP "tag"]
                if (repo == "") {
                    path = section
                    sub(/^subproject "/, "", path)
                    sub(/"$/, "", path)
                    add_error("subproject " path " is missing repo")
                }
                if (clone != "" && clone != "full" && clone != "partial" && clone != "shallow") add_error("invalid clone mode in [" section "]: " clone)
                if (tag != "" && revision == "") add_error("tag requires revision in [" section "]")
            }
        }
    ' "$MANIFEST_FILE"

	# Reject unsafe subproject paths in the manifest content itself. Commands
	# that clone, check out, or remove use these paths, so an absolute path, a
	# parent-directory escape (..), a backslash, or a .git-like name must never
	# reach the filesystem. Read from a file, not a pipe, so the error exits.
	schema_paths=$(tmp_for "$MANIFEST_FILE.schema_paths")
	manifest_subprojects_from_file "$MANIFEST_FILE" >"$schema_paths"
	while IFS= read -r schema_path; do
		[ -n "$schema_path" ] || continue
		case "$schema_path" in
		*[\\]*) printf 'Error: subproject path uses a backslash in %s: %s\n' "$MANIFEST_FILE" "$schema_path" >>"$errors" ;;
		esac
		path_is_relative_safe "$schema_path" ||
			printf 'Error: unsafe subproject path in %s: %s (must be a relative path inside the nest)\n' "$MANIFEST_FILE" "$schema_path" >>"$errors"
	done <"$schema_paths"
	rm -f "$schema_paths"

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

# List subproject paths from manifest section headers. Uses the cached variable
# store when available; falls back to file parsing when unloaded.
# Calls manifest_load_cache first so the PWD guard detects nested-nest recursion
# and reloads for the new nest automatically.
manifest_subprojects() {
	manifest_load_cache
	if [ -n "${_MNF_LOADED:-}" ]; then
		if [ -n "${_MNF_SP:-}" ]; then
			printf '%s\n' "$_MNF_SP"
		fi
		return
	fi
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
	_MNF_LOADED=
}

# List the manifest keys that rewrites must preserve verbatim (extension
# keys and command-owned keys), so untouched data survives a rewrite.
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
	_MNF_LOADED=
	rm -f "$preserved"
}

# Write one subproject section after validating state-specific required fields.
# Uses an mws_-prefixed path/repo (rather than bare path/repo) because this is
# called without a subshell from callers (add, freeze, snapshot, upload,
# update, finalize, absorb) that hold their own bare path/repo across the call.
manifest_write_subproject() {
	mws_path=$1
	mws_repo=$2
	state=$3
	a=${4:-}
	b=${5:-}
	c=${6:-}
	d=${7:-}
	e=${8:-}
	previous_clone=
	[ -f "$MANIFEST_FILE" ] && previous_clone=$(subproject_key "$mws_path" clone || true)
	preserved=$(mktemp)
	[ -f "$MANIFEST_FILE" ] && manifest_preserved_keys "$(subproject_section "$mws_path")" "^(repo|clone|target_branch|revision|tag)$" >"$preserved" || : >"$preserved"

	require_value "$mws_path" "cannot write manifest subproject with an empty path"
	require_value "$mws_repo" "cannot write manifest subproject $mws_path without a repository URL"
	case "$state" in
	finalized)
		require_value "$a" "cannot pin $mws_path without a resolved revision; fetch the subproject or pass --revision <sha>"
		clone=${d:-$previous_clone}
		;;
	pending)
		die "pending manifest state is no longer supported; use git-nest snapshot after pushing the subproject commit"
		;;
	tracked)
		require_value "$a" "cannot track $mws_path without a target branch"
		clone=${c:-$previous_clone}
		;;
	*) die "unknown manifest state for $mws_path: $state" ;;
	esac
	validate_clone_mode "$clone" "subproject $mws_path clone mode"

	ensure_manifest
	manifest_remove_section "subproject \"$mws_path\""
	{
		printf '\n[subproject "%s"]\n' "$mws_path"
		printf 'repo=%s\n' "$mws_repo"
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
# Bare "path" here is safe today (audited): cmd_config's "unset" call is the
# function's last statement in its case branch (no read-after), and
# cleanup_branch_for_subproject's two calls are safe because that function's
# own path parameter is prefixed (cbfs_path), so this callee's bare "path"
# no longer collides with anything the caller reads afterward. If a new
# caller is added that holds its own bare "path"/"repo" across a call to
# this function without an intervening subshell, prefix this parameter
# (e.g. mrsk_path) the same way the other helpers in this file were fixed.
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
	_MNF_LOADED=
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
	"" | full | partial | shallow) ;;
	*) die "$context must be full, partial, or shallow, got '$value'" ;;
	esac
}

# Resolve the repository-wide clone override from .gitnest-rc.
configured_clone_mode() {
	mode=$(config_get clone mode || true)
	[ -n "$mode" ] || mode=manifest
	case "$mode" in
	manifest | full | partial | shallow) printf '%s\n' "$mode" ;;
	*) die "$CONFIG_FILE [clone] mode must be manifest, full, partial, or shallow, got '$mode'" ;;
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
	full | partial | shallow) printf '%s\n' "$configured" ;;
	esac
}

# ---------------------------------------------------------------------------
# .gitnest-rc writers -- the existing config_get reads [section] key = value;
# these helpers write back so the config command can manage rc keys.
# ---------------------------------------------------------------------------

# Write key=value into a section of CONFIG_FILE. If the file does not
# exist it is created. If the key already exists in the section it is
# replaced; if the section exists but the key does not, the key is
# appended; if the section is absent it is appended at the end of the
# file.
rc_set() {
	_section=$1
	_key=$2
	_value=$3
	[ -f "$CONFIG_FILE" ] || : >"$CONFIG_FILE"
	_tmp=$(mktemp "${TMPDIR:-/tmp}/gn-rc-set.XXXXXX")
	awk -v section="$_section" -v key="$_key" -v val="$_value" '
        $0 == "[" section "]" { in_section=1; seen=1; print; next }
        /^\[/ { in_section=0 }
        in_section && index($0, key "=") == 1 { found=1; print key "=" val; next }
        { print }
        END {
            if (!found && !seen) {
                print "[" section "]"
                print key "=" val
            } else if (in_section && !found) {
                print key "=" val
            }
        }
    ' "$CONFIG_FILE" >"$_tmp"
	mv "$_tmp" "$CONFIG_FILE"
}

# Remove key from a section in CONFIG_FILE. Other keys in the section are
# preserved. If the section becomes empty after removal, the section header
# is also removed.
rc_unset() {
	_section=$1
	_key=$2
	[ -f "$CONFIG_FILE" ] || return 0
	_tmp=$(mktemp "${TMPDIR:-/tmp}/gn-rc-unset.XXXXXX")
	awk -v section="$_section" -v key="$_key" '
        $0 == "[" section "]" { in_section=1; hdr=$0; had=0; next }
        /^\[/ {
            if (in_section) {
                if (had) print hdr
                in_section=0
                hdr=""
                had=0
            }
        }
        in_section && index($0, key "=") == 1 { next }
        in_section && $0 !~ /^[[:space:]]*$/ { had=1 }
        {
            if (in_section) {
                if (had || $0 !~ /^[[:space:]]*$/) print
            } else {
                print
            }
        }
        END { if (in_section && had) print hdr }
    ' "$CONFIG_FILE" >"$_tmp"
	mv "$_tmp" "$CONFIG_FILE"
}

# Convenience: substitute-url for a given path lives under
# [remote "<path>"] substitute-url.
rc_url_set() {
	rc_set "remote \"$1\"" substitute-url "$2"
}
rc_url_unset() {
	rc_unset "remote \"$1\"" substitute-url
}
rc_url_get() {
	config_get "remote \"$1\"" substitute-url
}
rc_url_list() {
	[ -f "$CONFIG_FILE" ] || return 0
	awk '
        /^\[remote "/ { gsub(/^\[remote "|"]$/, ""); path=$0; next }
        /^substitute-url=/ && path {
            print path "\t" substr($0, 16)
            path=""
        }
    ' "$CONFIG_FILE"
}

# ---------------------------------------------------------------------------
# Protocol preference -- per-developer transport choice stored under
# [clone] protocol in .gitnest-rc.
# ---------------------------------------------------------------------------

configured_protocol() {
	mode=$(config_get clone protocol || true)
	[ -n "$mode" ] || mode=manifest
	case "$mode" in
	manifest | ssh | https | http) printf '%s\n' "$mode" ;;
	*) die "$CONFIG_FILE [clone] protocol must be manifest, ssh, https, or http, got '$mode'" ;;
	esac
}

# The preference that apply_protocol_preference should use: an explicit
# override (flag), or the rc setting, or manifest default.
resolve_protocol_preference() {
	_override=$1
	[ -n "$_override" ] && {
		printf '%s\n' "$_override"
		return
	}
	configured_protocol
}

# ---------------------------------------------------------------------------
# Effective URL resolution -- per subproject the URL that git-nest should
# use for network operations and that verify should compare origin
# against. Precedence: rc substitute-url > manifest repo with protocol
# rewrite (or explicit preference) > manifest repo as recorded.
# ---------------------------------------------------------------------------

# Return the effective URL for a subproject path, applying any rc
# substitute-url override and the chosen protocol preference.
effective_repo_url() {
	_path=$1
	_prefer=$2
	_manifest_url=$(subproject_repo "$_path" || true)
	[ -n "$_manifest_url" ] || return 1

	# rc per-subproject substitute-url wins verbatim.
	_sub=$(rc_url_get "$_path" || true)
	if [ -n "$_sub" ]; then
		printf '%s\n' "$_sub"
		return 0
	fi

	# Protocol preference rewriting.
	_pref=$(resolve_protocol_preference "$_prefer")
	case "$_pref" in
	manifest | "") printf '%s\n' "$_manifest_url" ;;
	ssh)
		_rewritten=$(derive_ssh_url "$_manifest_url" || true)
		if [ -n "$_rewritten" ]; then
			printf '%s\n' "$_rewritten"
		else
			warn "cannot derive SSH URL for $_manifest_url (non-standard shape); using recorded URL"
			printf '%s\n' "$_manifest_url"
		fi
		;;
	https)
		case "$_manifest_url" in
		https://*) printf '%s\n' "$_manifest_url" ;;
		http://*) printf 'https://%s\n' "${_manifest_url#http://}" ;;
		ssh://* | git@*)
			_rewritten=$(derive_https_url "$_manifest_url" || true)
			if [ -n "$_rewritten" ]; then
				printf '%s\n' "$_rewritten"
			else
				warn "cannot derive HTTPS URL for $_manifest_url (non-standard shape); using recorded URL"
				printf '%s\n' "$_manifest_url"
			fi
			;;
		*) printf '%s\n' "$_manifest_url" ;;
		esac
		;;
	http)
		case "$_manifest_url" in
		http://*) printf '%s\n' "$_manifest_url" ;;
		https://*) printf 'http://%s\n' "${_manifest_url#https://}" ;;
		*) printf '%s\n' "$_manifest_url" ;;
		esac
		;;
	esac
}

# ---------------------------------------------------------------------------
# URL shape helpers -- standard GitHub-style hosts only; exotic shapes
# (Azure _git paths, ports, custom users) are returned empty.
# ---------------------------------------------------------------------------

# Derive git@HOST:path/repo.git from https://HOST/path/repo.git.
derive_ssh_url() {
	_url=$1
	case "$_url" in
	https://*.git)
		_host_path=${_url#https://}
		_host=${_host_path%%/*}
		_path=${_host_path#"$_host"}
		# Only derive for standard host/org/repo shapes (exclude Azure _git etc.).
		case "${_host_path}" in
		*[:@]* | *'~'* | *' '_* | *'##'* | *';;'*) return 1 ;; # unusual chars -- bail
		esac
		printf 'git@%s:%s\n' "$_host" "${_path#/}"
		;;
	*) return 1 ;;
	esac
}

# Derive https://HOST/path/repo.git from git@HOST:path/repo.git or
# ssh://HOST/path/repo.git.
derive_https_url() {
	_url=$1
	case "$_url" in
	git@*:*)
		_host=${_url#git@}
		_path=${_host#*:}
		_host=${_host%%:*}
		printf 'https://%s/%s\n' "$_host" "$_path"
		;;
	ssh://*)
		_url=${_url#ssh://}
		_user_host=${_url%%/*}
		_path=${_url#"$_user_host"}
		_host=${_user_host##*@}
		printf 'https://%s%s\n' "$_host" "$_path"
		;;
	*) return 1 ;;
	esac
}

# ---------------------------------------------------------------------------
# URL normalisation -- reduce two URLs to a host+path identity so verify
# (default mode) can accept protocol-equivalent checkouts.
# ---------------------------------------------------------------------------

# Strip scheme, user, port, and scp-syntax to a bare <host>/<path>.
url_normalize_identity() {
	_url=$1
	case "$_url" in
	https://* | http://*)
		_host_path=${_url#*://}
		printf '%s\n' "${_host_path#*/}"
		;;
	ssh://*)
		_host_path=${_url#ssh://}
		_user=${_host_path%%@*}
		_rest=${_host_path#"$_user@"}
		_host=${_rest%%/*}
		_path=${_rest#"$_host"}
		printf '%s\n' "${_host}${_path}"
		;;
	git@*:*)
		_host=${_url#git@}
		_path=${_host#*:}
		_host=${_host%%:*}
		printf '%s\n' "${_host}${_path}"
		;;
	*) printf '%s\n' "$_url" ;; # file://, git:// -- pass through unchanged
	esac
}

# Are two URLs pointing at the same repository (same host + path,
# protocol/credentials/port ignored)?
url_protocol_equivalent() {
	_a=$1
	_b=$2
	[ "$(url_normalize_identity "$_a")" = "$(url_normalize_identity "$_b")" ]
}

# ---------------------------------------------------------------------------
# Transport rewrite -- set GIT_CONFIG_* env so every git subprocess
# inherits url.<base>.insteadOf rewriting. Only standard-shaped hosts
# get a rule; non-standard shapes are skipped with a warning.
# ---------------------------------------------------------------------------

apply_protocol_preference() {
	_prefer=$1
	_pref=$(resolve_protocol_preference "$_prefer")
	case "$_pref" in
	manifest | "") return 0 ;; # nothing to do
	esac

	# Collect unique standard https hosts from the manifest into a temp
	# file so the second pass reads it in the current shell (no pipe).
	_hosts_file=$(mktemp "${TMPDIR:-/tmp}/gn-hosts.XXXXXX")
	manifest_subprojects >"$_hosts_file.in"
	while IFS= read -r _ap_path; do
		[ -n "$_ap_path" ] || continue
		_ap_url=$(subproject_repo "$_ap_path" || true)
		[ -n "$_ap_url" ] || continue
		case "$_ap_url" in https://* | http://*) ;; *) continue ;; esac
		_host_path=${_ap_url#*://}
		_host=${_host_path%%/*}
		_repo_path=${_host_path#"$_host"}
		_repo_path=${_repo_path#/}
		case "$_repo_path" in
		*[!A-Za-z0-9._/-]*)
			warn "skipping protocol rewrite for non-standard URL: $_ap_url"
			continue
			;;
		*_git/* | *_git$)
			warn "skipping protocol rewrite for non-standard URL: $_ap_url"
			continue
			;;
		esac
		printf '%s\n' "$_host"
	done <"$_hosts_file.in" | sort -u >"$_hosts_file"
	rm -f "$_hosts_file.in"

	_cnt=0
	while IFS= read -r _host; do
		[ -n "$_host" ] || continue
		case "$_pref" in
		ssh)
			eval "export GIT_CONFIG_KEY_$_cnt=url.git@$_host:.insteadOf"
			eval "export GIT_CONFIG_VALUE_$_cnt=https://$_host/"
			_cnt=$((_cnt + 1))
			;;
		https)
			eval "export GIT_CONFIG_KEY_$_cnt=url.https://$_host/.insteadOf"
			eval "export GIT_CONFIG_VALUE_$_cnt=ssh://git@$_host/"
			_cnt=$((_cnt + 1))
			eval "export GIT_CONFIG_KEY_$_cnt=url.https://$_host/.insteadOf"
			eval "export GIT_CONFIG_VALUE_$_cnt=git@$_host:"
			_cnt=$((_cnt + 1))
			;;
		http)
			eval "export GIT_CONFIG_KEY_$_cnt=url.http://$_host/.insteadOf"
			eval "export GIT_CONFIG_VALUE_$_cnt=https://$_host/"
			_cnt=$((_cnt + 1))
			;;
		esac
	done <"$_hosts_file"
	rm -f "$_hosts_file"

	[ "$_cnt" -gt 0 ] || return 0
	export GIT_CONFIG_COUNT=$_cnt
}

# Report whether the subproject has an active substitute-url in .gitnest-rc.
rc_url_is_overridden() {
	_path=$1
	rc_url_get "$_path" >/dev/null 2>&1
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
# Uses a cs_-prefixed repo/path (rather than bare repo/path) because cmd_add
# calls this without a subshell while holding its own bare repo/path across the call.
clone_subproject() {
	cs_repo=$1
	cs_path=$2
	mode=$3
	no_checkout=${4:-0}
	cs_depth=${5:-}
	case "$mode" in
	full)
		if [ -n "$cs_depth" ]; then
			git clone --depth "$cs_depth" "$cs_repo" "$cs_path" ||
				git_error "failed to shallow-clone subproject $cs_repo into $cs_path (depth $cs_depth); verify the repository URL and network access"
		else
			git clone "$cs_repo" "$cs_path" ||
				git_error "failed to clone subproject $cs_repo into $cs_path; verify the repository URL and network access"
		fi
		;;
	shallow)
		if [ -n "$cs_depth" ]; then
			git clone --depth "$cs_depth" "$cs_repo" "$cs_path" ||
				git_error "failed to shallow-clone subproject $cs_repo into $cs_path (depth $cs_depth); verify the repository URL and network access"
		else
			git clone --depth 1 "$cs_repo" "$cs_path" ||
				git_error "failed to shallow-clone subproject $cs_repo into $cs_path (depth 1); verify the repository URL and network access"
		fi
		;;
	partial)
		if [ "$no_checkout" -eq 1 ]; then
			git clone --filter=blob:none --no-checkout "$cs_repo" "$cs_path" ||
				git_error "failed to partial-clone subproject $cs_repo into $cs_path; verify the repository supports partial clone"
		else
			git clone --filter=blob:none "$cs_repo" "$cs_path" ||
				git_error "failed to partial-clone subproject $cs_repo into $cs_path; verify the repository supports partial clone"
		fi
		repo_is_partial_clone "$cs_path" ||
			die "Git did not configure $cs_path as a partial clone; enable partial clone on the remote or use clone=full"
		;;
	*) die "unknown effective clone mode for $cs_path: $mode" ;;
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

# Return 0 when the candidate path is itself a managed subproject or sits
# inside one, so nested boundaries are never crossed by path commands.
path_is_manifest_subproject_or_child() {
	candidate=$1
	paths=$(mktemp)
	manifest_subprojects >"$paths"
	while IFS= read -r managed; do
		[ -n "$managed" ] || continue
		case "$candidate" in
		"$managed" | "$managed"/*)
			rm -f "$paths"
			return 0
			;;
		esac
	done <"$paths"
	rm -f "$paths"
	return 1
}

# List local Git repositories that are not part of the manifest, used by
# survey-style scans to surface unmanaged checkouts.
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

# Return 0 when a subproject's checked-out HEAD differs from its recorded
# revision, i.e. the checkout has drifted from the manifest.
subproject_manifest_mismatch() {
	path=$1
	revision=$(subproject_key "$path" revision || true)
	[ -n "$revision" ] || return 1
	[ -d "$path/.git" ] || return 1
	head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
	expected=$(git -C "$path" rev-parse --verify "$revision^{commit}" 2>/dev/null || true)
	[ -n "$head" ] && [ -n "$expected" ] && [ "$head" != "$expected" ]
}

# Classify a subproject's drift state into a one-letter status code (C for
# composite/mismatched, D for dirty) used by status and verify output.
status_code_for_subproject() {
	path=$1
	if subproject_manifest_mismatch "$path"; then
		printf 'C\n'
	else
		printf 'D\n'
	fi
}

# Map a status code to its human label (composite/dirty) for report output.
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
	# Prefixed loop variables (not path/repo): callers such as add/absorb keep
	# their own path/repo globals in scope across this call, and reusing those
	# names here would silently clobber them the same way old_path/old_repo
	# did below before that was fixed (see the comment there).
	manifest_subprojects | while IFS= read -r wms_path; do
		[ -n "$wms_path" ] || continue
		[ -d "$wms_path/.git" ] || continue
		wms_repo=$(subproject_repo "$wms_path" || true)
		[ -n "$wms_repo" ] || continue
		printf '%s\t%s\n' "$wms_path" "$wms_repo"
	done >"$tmp"
	if [ -f "$state_file" ]; then
		# Prefixed loop variables (not old_path/old_repo): this function is called
		# from commands such as move that keep their own old_path/new_path in
		# scope across the call, and this shell has no per-function variable
		# scoping, so reusing those names here would silently clobber the
		# caller's values (the final read past the last line clears them even if
		# the loop body never matched anything).
		while IFS='	' read -r wms_old_path wms_old_repo; do
			[ -n "$wms_old_path" ] || continue
			[ -n "$wms_old_repo" ] || continue
			pair_path_exists "$current_pairs" "$wms_old_path" && continue
			[ -e "$wms_old_path" ] || continue
			printf '%s\t%s\n' "$wms_old_path" "$wms_old_repo" >>"$tmp"
		done <"$state_file"
	fi
	rm -f "$current_pairs"
	mv "$tmp" "$state_file"
}

# Read current manifest subproject path/repo pairs into a tab-separated file.
# Prefixed loop variables for consistency with the other helpers in this
# file that share this call chain, even though this particular loop is
# piped (and therefore already subshell-isolated from any caller's own
# path/repo globals).
manifest_pairs_file() {
	out=$1
	: >"$out"
	manifest_subprojects | while IFS= read -r mpf_path; do
		[ -n "$mpf_path" ] || continue
		mpf_repo=$(subproject_repo "$mpf_path" || true)
		[ -n "$mpf_repo" ] || continue
		printf '%s\t%s\n' "$mpf_path" "$mpf_repo" >>"$out"
	done
}

# Prefixed parameters (not pairs/path): called from write_materialized_state's
# stale-entry loop, which itself runs without a subshell (redirected from a
# file, not piped) so callers such as add/absorb further up the call chain
# keep their own path/repo globals live across the call -- a bare "path=$2"
# here would silently clobber them (this really happened: a second add in
# the same process printed the first subproject's path in its success
# message because of exactly this collision).
pair_path_exists() {
	ppe_pairs=$1
	ppe_path=$2
	awk -F '	' -v path="$ppe_path" '$1 == path { found=1 } END { exit !found }' "$ppe_pairs"
}

# Guard stale cleanup paths. The state file is local, but deletion still stays
# relative to the project root and avoids parent traversal.
safe_stale_path() {
	path=$1
	case "$path" in
	"" | "." | ".." | /* | *":*" | ../* | */../* | *"/.." | *//*) return 1 ;;
	*) return 0 ;;
	esac
}

# Count how many recorded stale paths for a repository no longer exist or
# were already reconciled, so restore can report a clean stale-state summary.
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

# List recorded manifest paths for a repository whose checkout is missing,
# so restore knows exactly what to re-clone.
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

# Print the first line of a file (e.g. a single recorded value).
first_line() {
	sed -n '1p' "$1"
}

# Count non-empty lines in a file, used for stable summary reporting.
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

# Delete a stale subproject checkout that is no longer in the manifest.
remove_stale_subproject() {
	path=$1
	rm -rf -- "$path" || die "failed to remove stale subproject $path"
}

# Move a stale subproject checkout aside (instead of deleting) so the user
# can review it after restore reconciles the stale state.
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
	(CDPATH='' cd -- "$path" && pwd)
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

# Return 0 when a subproject has committed work ahead of its recorded target
# that a plain snapshot would silently leave out (drives --check warnings).
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

# Return 0 when any subproject in the nest has unreported committed work,
# used by snapshot --check to warn before recording state.
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

# Recursively collect labels of nested projects with unreported commits into
# a candidates file, de-duplicating via a visited-roots file.
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

# Print one notice per nested project that has unreported commits, telling
# the user to run snapshot --recursive to include them.
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

# Validate and record a --base <subproject>=<ref> override for the current
# command, so restore/update can pin a different revision per subproject.
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

# Look up the --base override ref recorded for a subproject, if any.
base_override_for() {
	path=$1
	[ -n "$GIT_NEST_BASE_OVERRIDES" ] || return 1
	[ -f "$GIT_NEST_BASE_OVERRIDES" ] || return 1
	awk -F '	' -v path="$path" '$1 == path { value=$2 } END { if (value != "") print value; else exit 1 }' "$GIT_NEST_BASE_OVERRIDES"
}

# Drop all --base overrides and re-enable fetching after the command using
# them finishes, so no state leaks into later commands.
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
	"$GITIGNORE_GIT_DIR_GUARD_ONE" | "$GITIGNORE_GIT_DIR_GUARD_TWO" | "$BRANCH_MARKS_FILE" | "$PUSH_CANDIDATES_FILE") return 0 ;;
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
# present on disk, i.e. stale orphans that tidy would prune. Read-only.
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

# Walk upward to the nearest ancestor directory that owns a manifest, used
# by nested-nest overlap checks to detect conflicting nest boundaries.
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

# Return 0 when a path is already recorded as a subproject in the manifest.
subproject_exists_in_manifest() {
	path=$1
	[ -n "$(subproject_repo "$path" || true)" ]
}

# Explain why switching a subproject to its target branch is unsafe right now
# (missing checkout, dirty state, or a conflicting current branch), or print
# nothing when the switch is safe.
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
		main | master) return 0 ;;
		*)
			printf '%s has current branch %s without an upstream or target comparison ref' "$path" "$current"
			return 0
			;;
		esac
	fi
	ahead=$(git -C "$path" rev-list --count "$base_ref..HEAD" 2>/dev/null || printf '0')
	if [ "$ahead" -gt 0 ] 2>/dev/null; then
		printf '%s has %s commit(s) ahead of %s' "$path" "$ahead" "$base_ref"
	fi
}

# Rename a subproject section header in the manifest in place, invalidating
# the parse cache so later reads see the new name.
manifest_rename_subproject_section() {
	old_path=$1
	new_path=$2
	tmp=$(tmp_for "$MANIFEST_FILE")
	awk -v old="subproject \"$old_path\"" -v new="subproject \"$new_path\"" '
        $0 == "[" old "]" { print "[" new "]"; next }
        { print }
    ' "$MANIFEST_FILE" >"$tmp"
	mv "$tmp" "$MANIFEST_FILE"
	_MNF_LOADED=
}

# Uses an mssk_-prefixed path (rather than bare path) because cmd_mv and
# cmd_config call this without a subshell while holding their own bare path
# across the call.
manifest_set_subproject_key() {
	mssk_path=$1
	key=$2
	value=$3
	section=$(subproject_section "$mssk_path")
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

# Query a remote's HEAD commit SHA without touching local refs, used by
# add/update to record what the remote currently points at.
remote_head_commit_for_url() {
	repo=$1
	git ls-remote "$repo" HEAD 2>/dev/null | awk 'NR == 1 { print $1 }'
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

# Resolve the commit a remote tag points at (preferring the peeled ^{} form)
# without updating local refs, for tag-drift checks.
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

# Uses an shr_-prefixed path (rather than bare path) because snapshot_one_subproject
# calls this without a subshell while holding its own bare path across the call.
subproject_head_is_reproducible() {
	shr_path=$1
	head=$2
	if [ "$GIT_NEST_DRY_RUN" -eq 0 ] && [ "$GIT_NEST_NO_FETCH" -eq 0 ]; then
		fetch_quiet "$shr_path" 2>/dev/null || return 1
	fi
	git -C "$shr_path" branch -r --contains "$head" 2>/dev/null | grep -E '^[* ]+origin/' >/dev/null 2>&1 && return 0
	git -C "$shr_path" tag --contains "$head" 2>/dev/null | grep . >/dev/null 2>&1 && return 0
	return 1
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

# Read the manifest revision value used as a diff base.
manifest_diff_base_from_file() {
	file=$1
	path=$2
	section=$(subproject_section "$path")
	base=$(manifest_get_from_file "$file" "$section" revision || true)
	printf '%s\n' "$base"
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

# Append one doctor check result row (code, name, detail) to the results file
# so the doctor report is built incrementally in a stable order.
doctor_add_check() {
	file=$1
	code=$2
	name=$3
	detail=$4
	printf '%s\t%s\t%s\n' "$code" "$name" "$detail" >>"$file"
}

# Map a doctor check code (I/W/E) to its human status label for output.
doctor_code_to_status() {
	case "$1" in
	I) printf 'info\n' ;;
	W) printf 'warn\n' ;;
	E) printf 'error\n' ;;
	*) printf 'info\n' ;;
	esac
}

# Reachability-check one remote with a timeout, using the external timeout
# utility when present and a shell watchdog fallback otherwise.
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

# Stage the given outer-repository paths only when an outer Git work tree exists,
# so absorb still works inside copied-manifest folders that have no outer .git.
stage_outer_paths_if_repo() {
	git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
	stage_outer_paths "$@"
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

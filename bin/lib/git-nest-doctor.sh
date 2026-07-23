#!/bin/sh
#
# git-nest: record and restore reproducible nests of independent Git repositories.
# https://github.com/f-steff/git-nest
#
# git-nest doctor -- sourced by bin/git_nest.sh
#
# Environment and workspace diagnostics, repository discovery, and listing.
#
# Copyright (c) 2026 Flemming Steffensen.
# License: MIT
# SPDX-License-Identifier: MIT

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
	[ -n "$hook_file" ] || {
		printf 'absent\n'
		return
	}
	[ -f "$hook_file" ] || {
		printf 'absent\n'
		return
	}
	if grep -F '# git-nest managed hook' "$hook_file" >/dev/null 2>&1; then
		printf 'installed\n'
	else
		printf 'unmanaged\n'
	fi
}

cmd_doctor() {
	json=0
	json_pretty=0
	offline=0
	timeout_seconds=$GIT_NEST_DOCTOR_TIMEOUT_SECONDS
	use_exit_code=0
	redact=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			json_pretty=1
			shift
			;;
		--online)
			offline=0
			shift
			;;
		--offline)
			offline=1
			shift
			;;
		--timeout)
			[ $# -ge 2 ] || usage_error "--timeout requires seconds"
			timeout_seconds=$2
			validate_positive_integer "$timeout_seconds" "--timeout"
			shift 2
			;;
		--exit-code)
			use_exit_code=1
			shift
			;;
		--redact)
			redact=1
			shift
			;;
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

	shell_name=$(ps -o comm= -p $$ 2>/dev/null | sed 's/.*\///; s/[^a-zA-Z0-9]//g')
	[ -n "$shell_name" ] || shell_name='sh'
	doctor_add_check "$checks" I shell "running under $shell_name"

	if [ -f "$MANIFEST_FILE" ]; then
		errors=$(tmp_for "$MANIFEST_FILE.doctor_schema")
		if (validate_manifest_schema) >"$errors" 2>&1; then
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

	# Emit the report, then optionally redact credentials and the home directory.
	{
		if [ "$json" -eq 1 ]; then
			emit_doctor_json "$checks" "$ok" "$json_pretty"
		else
			while IFS='	' read -r code name detail; do
				[ -n "$code" ] && printf '%s\t%s\t%s\n' "$code" "$name" "$detail"
			done <"$checks"
		fi
	} | if [ "$redact" -eq 1 ]; then redact_stream; else cat; fi
	rm -f "$checks"
	if [ "$use_exit_code" -eq 1 ] && [ "$ok" -eq 0 ]; then
		return "$EXIT_ISSUES"
	fi
	return 0
}

# Default directory names survey prunes so scans stay bounded and quiet. These
# are dependency, build, cache, and git-nest backup directories that never hold
# subprojects worth managing.
SURVEY_DEFAULT_EXCLUDES="node_modules vendor build dist target out bin obj .cache .gradle .venv venv __pycache__ .gitnest-recovery-*"

# Reject exclude names that could inject shell syntax. Only simple directory-name
# tokens are allowed (alphanumeric, dot, underscore, star, hyphen).
validate_survey_exclude() {
	case "$1" in
	"" | *[!A-Za-z0-9._*-]*) usage_error "invalid --exclude value: $1 (use simple directory names)" ;;
	esac
}

# Validate and normalize a --include path: unlike --exclude (a bare name matched
# anywhere), --include takes a relative path and narrows the scan to it, so it
# gets the same path-safety treatment as other path arguments and must exist.
validate_survey_include() {
	vsi_arg=$1
	reject_backslash_path "$vsi_arg"
	vsi_path=$(normalize_path "$vsi_arg")
	[ -d "$vsi_path" ] || usage_error "--include path does not exist: $vsi_path"
	printf '%s\n' "$vsi_path"
}

# Print every .git or .gitrepo entry under the given scan roots (the current
# directory by default, or each --include path), bounded by a maximum path
# depth and pruning excluded directory names. It does not follow symlinks
# because plain find never descends symlinked dirs. Uses set -- to build the
# argument list positionally, avoiding eval entirely, so root and exclude
# values may contain spaces safely.
survey_scan() {
	ds_depth=$1
	ds_excludes=$2
	ds_includes_file=$3
	ds_find_depth=$((ds_depth + 1))
	ds_have_prune=0

	set -- find
	if [ -s "$ds_includes_file" ]; then
		while IFS= read -r ds_root; do
			[ -n "$ds_root" ] || continue
			set -- "$@" "$ds_root"
		done <"$ds_includes_file"
	else
		set -- "$@" .
	fi
	set -- "$@" -maxdepth "$ds_find_depth"

	# Append the prune expression from the exclude list, if any.
	# Disable globbing so patterns like .gitnest-recovery-* stay literal.
	set -f
	for ds_name in $ds_excludes; do
		[ -n "$ds_name" ] || continue
		if [ "$ds_have_prune" -eq 0 ]; then
			set -- "$@" '('
			ds_have_prune=1
		else
			set -- "$@" -o
		fi
		set -- "$@" -name "$ds_name"
	done
	set +f

	if [ "$ds_have_prune" -eq 1 ]; then
		set -- "$@" ')' -prune -o '(' -name .git -o -name .gitrepo ')' -print
	else
		set -- "$@" '(' -name .git -o -name .gitrepo ')' -print
	fi

	"$@" 2>/dev/null
}

# Classify one discovered repository and append a porcelain row describing it.
# Rows reuse the shared 7-column layout: code, path, state, target, current,
# expected, detail. code is S(ubmodule)/R(nested-repo)/N(est root)/D(etached)/
# G(it-subrepo); target carries the managing boundary when the path sits
# inside one; detail is a next-step hint.
#
# dcr_boundaries is a growing file of paths already known to be boundaries:
# it starts as the manifest's managed subprojects and gains one line per row
# this function classifies. Callers must process candidates shallowest-first
# (see survey_collect_rows) so that a path found underneath a boundary this
# same scan already classified is recognized and never treated as a second,
# independent finding -- the outer nest must never act on anything inside a
# submodule/subrepo/nested-repo/nest-root it already identified.
survey_classify_row() {
	dcr_path=$1
	dcr_rows=$2
	dcr_boundaries=$3
	dcr_parent=-
	dcr_inside=0
	while IFS= read -r managed; do
		[ -n "$managed" ] || continue
		# A path exactly at a boundary is that boundary's own checkout; skip it.
		[ "$dcr_path" = "$managed" ] && return 0
		case "$dcr_path" in
		"$managed"/*)
			dcr_parent=$managed
			dcr_inside=1
			;;
		esac
	done <"$dcr_boundaries"

	# Classify the kind of repository so callers know how to handle it. A plain
	# nested repo whose path still carries a nest-owned ignore entry is a former
	# subproject left behind by detach, so it is labeled detached.
	if [ -f "$dcr_path/.gitrepo" ]; then
		dcr_code=G
		dcr_state=subrepo
	elif outer_submodule_name_for_path "$dcr_path" >/dev/null 2>&1; then
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

	# Build a next-step suggestion appropriate to the situation. The path is
	# shell-quoted so the suggested command is safe to copy and paste verbatim
	# even when the path contains a space or other shell metacharacter.
	dcr_path_q=$(shell_quote "$dcr_path")
	if [ "$dcr_inside" -eq 1 ]; then
		# dcr_parent is a boundary either way, but only some boundaries are
		# actually persisted, managed subprojects; a boundary this same survey
		# scan just discovered (an unmanaged submodule/subrepo/nested-repo/nest
		# root) is not "managed" yet, so the message must not claim it is.
		if [ -n "$(subproject_repo "$dcr_parent" || true)" ]; then
			dcr_detail="inside managed subproject $dcr_parent; run git-nest from there"
		else
			dcr_detail="inside $dcr_parent (listed above); resolve that first, then re-run survey to see what is inside it"
		fi
	elif [ "$dcr_state" = nest-root ]; then
		dcr_detail="nested nest; run git-nest inside it or use --recursive commands"
	elif [ "$dcr_state" = submodule ]; then
		if [ -e "$dcr_path/.git" ]; then
			dcr_detail="run git-nest absorb $dcr_path_q to convert the submodule"
		else
			dcr_detail="submodule $dcr_path_q is not checked out; run git submodule update --init $dcr_path_q first, then re-run survey"
		fi
	elif [ "$dcr_state" = detached ]; then
		dcr_detail="detached former subproject; git-nest absorb $dcr_path_q to re-manage, or move/remove it and run git-nest repair"
	elif [ "$dcr_state" = subrepo ]; then
		dcr_detail="run git-nest absorb --subrepo $dcr_path_q (not absorbed by absorb-all)"
	else
		dcr_detail="run git-nest absorb $dcr_path_q to manage it"
	fi
	printf '%s\t%s\t%s\t%s\t-\t-\t%s\n' "$dcr_code" "$dcr_path" "$dcr_state" "$dcr_parent" "$dcr_detail" >>"$dcr_rows"
	# Record this path as a boundary for any deeper candidate processed later in
	# this same scan.
	printf '%s\n' "$dcr_path" >>"$dcr_boundaries"
}

# Shared scan-and-classify step used by both cmd_survey (display) and
# cmd_absorb_all (candidate selection), so the two commands can never
# disagree about what is out there. Appends stable, shallowest-first-safe
# rows to scr_rows (an existing empty file the caller provides).
survey_collect_rows() {
	scr_max_depth=$1
	scr_excludes=$2
	scr_includes_file=$3
	scr_rows=$4

	scr_raw=$(mktemp)
	scr_boundaries=$(mktemp)
	manifest_subprojects >"$scr_boundaries"

	survey_scan "$scr_max_depth" "$scr_excludes" "$scr_includes_file" | while IFS= read -r gitpath; do
		repo=$(dirname -- "$gitpath")
		repo=$(normalize_path "$repo")
		repo=${repo#./}
		# The nest root's own .git is expected and never reported.
		[ "$repo" = "." ] && continue
		[ -n "$repo" ] && printf '%s\n' "$repo"
	done | sort -u | awk -F/ '{ print NF, $0 }' | sort -n | sed 's/^[0-9]* //' >"$scr_raw"

	while IFS= read -r repo; do
		[ -n "$repo" ] || continue
		survey_classify_row "$repo" "$scr_rows" "$scr_boundaries"
	done <"$scr_raw"

	# Enumerate .gitmodules entries to find submodules registered in the
	# manifest but not checked out on disk. The find-based scan above only
	# finds paths that have a .git file/directory, so an un-initialized
	# submodule (registered via .gitmodules but never checked out) would
	# be invisible without this pass.
	if [ -f .gitmodules ]; then
		git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null |
		while IFS=' ' read -r scr_key scr_subm_path; do
			[ -n "$scr_subm_path" ] || continue
			# Already classified by the filesystem scan -- skip to avoid
			# duplicates.
			if grep -qxF "$scr_subm_path" "$scr_boundaries" >/dev/null 2>&1; then
				continue
			fi
			# Only report un-initialized submodules (no .git on disk).
			if [ ! -e "$scr_subm_path/.git" ]; then
				scr_subm_q=$(shell_quote "$scr_subm_path")
				printf 'S\t%s\tsubmodule\t-\t-\t-\tsubmodule %s is not checked out; run git submodule update --init %s first, then re-run survey\n' \
					"$scr_subm_path" "$scr_subm_q" "$scr_subm_q" >>"$scr_rows"
				printf '%s\n' "$scr_subm_path" >>"$scr_boundaries"
			fi
		done
	fi

	rm -f "$scr_raw" "$scr_boundaries"
}

# discover scans the current nest for nested Git repositories and submodules that
# are not managed by .gitnest, and reports them with a suggested next step. It is
# discovery only: it never adds, syncs, or registers anything.
cmd_survey() {
	max_depth=4
	porcelain=0
	json=0
	pretty=0
	excludes=$SURVEY_DEFAULT_EXCLUDES
	includes_file=$(mktemp)
	: >"$includes_file"
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
			validate_survey_exclude "$2"
			excludes="$excludes $2"
			shift 2
			;;
		--include)
			[ $# -ge 2 ] || usage_error "--include requires a path"
			validate_survey_include "$2" >>"$includes_file"
			shift 2
			;;
		--porcelain)
			porcelain=1
			shift
			;;
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			pretty=1
			shift
			;;
		--*) usage_error "unknown survey option: $1" ;;
		*) usage_error "survey takes no positional arguments" ;;
		esac
	done
	[ "$porcelain" -eq 0 ] || [ "$json" -eq 0 ] || usage_error "survey cannot combine --porcelain with --json/--json-pretty"
	ensure_manifest
	validate_manifest_schema

	rows=$(mktemp)
	empty=$(mktemp)
	survey_collect_rows "$max_depth" "$excludes" "$includes_file" "$rows"
	rm -f "$includes_file"

	if [ "$json" -eq 1 ]; then
		emit_json_result survey 0 1 "$rows" "$empty" "$empty" "$pretty"
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
	rm -f "$rows" "$empty"
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

# Resolve the repository URL for a survey-discovered path given its state code.
# Returns the URL or "No URI" if none can be determined.
tree_survey_url() {
	tsu_code=$1
	tsu_path=$2
	tsu_state=$3
	case "$tsu_code" in
	S)
		tsu_url=$(git config -f .gitmodules --get "submodule.$(outer_submodule_name_for_path "$tsu_path" 2>/dev/null || true).url" 2>/dev/null || true)
		[ -n "$tsu_url" ] || tsu_url="No URI"
		printf '%s\n' "$tsu_url"
		;;
	G)
		if [ -f "$tsu_path/.gitrepo" ]; then
			tsu_url=$(awk -v key='remote' '/^\[subrepo\]/ { ins=1 } ins && index($0, key "=") == 1 { v=substr($0, index($0, "=")+1); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }' "$tsu_path/.gitrepo")
		fi
		[ -n "${tsu_url:-}" ] || tsu_url="No URI"
		printf '%s\n' "$tsu_url"
		;;
	N)
		tsu_url=$(subproject_repo "$tsu_path" 2>/dev/null || true)
		if [ -z "$tsu_url" ] && [ -f "$tsu_path/$MANIFEST_FILE" ]; then
			tsu_url=$(awk -F= '/^repo=/ { print $2; exit }' "$tsu_path/$MANIFEST_FILE" 2>/dev/null || true)
		fi
		[ -n "${tsu_url:-}" ] || tsu_url="No URI"
		printf '%s\n' "$tsu_url"
		;;
	R | D)
		tsu_url=$(git -C "$tsu_path" remote get-url origin 2>/dev/null || true)
		[ -n "$tsu_url" ] || tsu_url="No URI"
		printf '%s\n' "$tsu_url"
		;;
	*) printf 'No URI\n' ;;
	esac
}

# Map survey state value to human-readable typelabel.
tree_survey_typelabel() {
	case "$1" in
	submodule) printf 'Unmanaged Submodule\n' ;;
	nested-repo) printf 'Unmanaged Repo\n' ;;
	subrepo) printf 'Unmanaged Subrepo\n' ;;
	detached) printf 'Unmanaged Detached\n' ;;
	nest-root) printf 'Unmanaged Nest Root\n' ;;
	*) printf 'Unmanaged\n' ;;
	esac
}

# Collect rows for tree: root line, one per managed subproject, plus (with
# tcr_all=1) survey's own unmanaged findings reusing survey_collect_rows so
# tree never disagrees with survey about what is out there. Output is 4
# tab-separated columns: code, path, url, typelabel.
# tcr_prefix is prepended to every path so a recursive call from inside a
# nested nest reports paths relative to the outermost root; pass "." for the
# top-level call. With tcr_recursive=1, a managed subproject that is itself
# a nested nest (has its own .gitnest) is also descended into, in its own
# subshell (isolating that recursive call's own variables from this loop,
# the same pattern pull_recursive already uses), so a mid-recursion path
# never corrupts an in-progress sibling iteration here.
tree_collect_rows() {
	tcr_all=$1
	tcr_recursive=$2
	tcr_prefix=$3
	tcr_rows=$4

	# Root line: the nest root with its origin URL.
	tcr_root_url=$(git remote get-url origin 2>/dev/null || true)
	[ -n "$tcr_root_url" ] || tcr_root_url="No URI"
	printf 'N\t.\t%s\tNest Root\n' "$tcr_root_url" >>"$tcr_rows"

	tcr_managed=$(mktemp)
	manifest_subprojects >"$tcr_managed"
	while IFS= read -r tcr_path; do
		[ -n "$tcr_path" ] || continue
		tcr_full=$tcr_path
		[ "$tcr_prefix" = "." ] || tcr_full="$tcr_prefix/$tcr_path"
		tcr_url=$(subproject_repo "$tcr_path" || true)
		[ -n "$tcr_url" ] || tcr_url="No URI"
		if [ -f "$tcr_path/$MANIFEST_FILE" ]; then
			printf 'M\t%s\t%s\tManaged (nested nest)\n' "$tcr_full" "$tcr_url" >>"$tcr_rows"
			if [ "$tcr_recursive" -eq 1 ] && [ -d "$tcr_path/.git" ]; then
				(cd "$tcr_path" && tree_collect_rows "$tcr_all" "$tcr_recursive" "$tcr_full" "$tcr_rows")
			fi
		else
			printf 'M\t%s\t%s\tManaged\n' "$tcr_full" "$tcr_url" >>"$tcr_rows"
		fi
	done <"$tcr_managed"
	rm -f "$tcr_managed"

	if [ "$tcr_all" -eq 1 ]; then
		tcr_scan_rows=$(mktemp)
		tcr_includes=$(mktemp)
		: >"$tcr_includes"
		survey_collect_rows 4 "$SURVEY_DEFAULT_EXCLUDES" "$tcr_includes" "$tcr_scan_rows"
		rm -f "$tcr_includes"
		while IFS='	' read -r tcr_code tcr_path tcr_state tcr_target tcr_current tcr_expected tcr_detail; do
			[ -n "$tcr_code" ] || continue
			tcr_full=$tcr_path
			[ "$tcr_prefix" = "." ] || tcr_full="$tcr_prefix/$tcr_path"
			tcr_surl=$(tree_survey_url "$tcr_code" "$tcr_path" "$tcr_state")
			tcr_stype=$(tree_survey_typelabel "$tcr_state")
			printf '%s\t%s\t%s\t%s\n' "$tcr_code" "$tcr_full" "$tcr_surl" "$tcr_stype" >>"$tcr_rows"
		done <"$tcr_scan_rows"
		rm -f "$tcr_scan_rows"
	fi
}

# tree displays an ASCII-art tree of the current nest, grouped by shared path
# prefixes. Plain: every managed subproject. --all: also survey's own
# detected-but-unmanaged findings (submodules, nested repos, git-subrepos,
# nest roots, detached former subprojects); subtrees remain undetectable, the
# same limitation survey already has. --recursive: also descends into nested
# nests, rendering their own subprojects nested under that branch.
cmd_tree() {
	show_all=0
	recursive=0
	plain=0
	porcelain=0
	json=0
	pretty=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--all)
			show_all=1
			shift
			;;
		--recursive)
			recursive=1
			shift
			;;
		--plain)
			plain=1
			shift
			;;
		--porcelain)
			porcelain=1
			shift
			;;
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			pretty=1
			shift
			;;
		--*) usage_error "unknown tree option: $1" ;;
		*) usage_error "tree takes no positional arguments" ;;
		esac
	done
	[ "$porcelain" -eq 0 ] || [ "$json" -eq 0 ] || usage_error "tree cannot combine --porcelain with --json/--json-pretty"
	[ "$plain" -eq 0 ] || [ "$porcelain" -eq 0 ] || usage_error "tree --plain cannot be combined with --porcelain"
	[ "$plain" -eq 0 ] || [ "$json" -eq 0 ] || usage_error "tree --plain cannot be combined with --json/--json-pretty"
	ensure_manifest
	validate_manifest_schema

	tree_rows=$(mktemp)
	tree_collect_rows "$show_all" "$recursive" "." "$tree_rows"

	if [ "$json" -eq 1 ] || [ "$porcelain" -eq 1 ]; then
		# Expand 4-column (code/path/url/typelabel) rows into the shared 7-column
		# porcelain schema. state receives the typelabel, detail receives the url.
		tree_full=$(mktemp)
		while IFS='	' read -r tf_code tf_path tf_url tf_typelabel; do
			[ -n "$tf_code" ] || continue
			[ -n "$tf_typelabel" ] || tf_typelabel=-
			printf '%s\t%s\t%s\t-\t-\t-\t%s\n' "$tf_code" "$tf_path" "$tf_typelabel" "$tf_url" >>"$tree_full"
		done <"$tree_rows"
		rm -f "$tree_rows"

		if [ "$json" -eq 1 ]; then
			tree_empty=$(mktemp)
			emit_json_result tree 0 1 "$tree_full" "$tree_empty" "$tree_empty" "$pretty"
			rm -f "$tree_empty"
		else
			cat "$tree_full"
		fi
		rm -f "$tree_full"
	else
		# Feed the raw 4-column rows directly to the awk renderer for human output.
		tree_tab=$(printf '\t')
		sort -t "$tree_tab" -k2,2 "$tree_rows" | awk -v plain="$plain" -f "$SCRIPT_DIR/lib/tree-render.awk"
		rm -f "$tree_rows"
	fi
}

# list prints the managed subprojects in a stable order with their URL, target
# branch, revision, tag, checkout state, and reproducibility. It is a script-first
# inventory command; status stays focused on workspace health.
cmd_list() {
	porcelain=0
	json=0
	pretty=0
	redact=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--porcelain)
			porcelain=1
			shift
			;;
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			pretty=1
			shift
			;;
		--redact)
			redact=1
			shift
			;;
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
	# Produce the chosen output, then optionally redact credentials and paths.
	{
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
	} | if [ "$redact" -eq 1 ]; then redact_stream; else cat; fi
	rm -f "$rows" "$empty"
}

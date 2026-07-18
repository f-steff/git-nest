#!/bin/sh
#
# git-nest hooks ? sourced by bin/git_nest.sh
#
# Managed hook installation, removal, and preflight for git-nest.
#
# Copyright (c) 2026 Flemming Steffensen.
# License: MIT
# SPDX-License-Identifier: MIT

# Resolve the actual hook path for a repo, handling Git's relative path output.
hook_path_for() {
	hook_path_repo=$1
	hook_path_name=$2
	resolved_hook_path=$(git -C "$hook_path_repo" rev-parse --git-path "hooks/$hook_path_name" 2>/dev/null) ||
		die "cannot resolve hook path for $hook_path_repo; ensure it is a Git repository"
	require_value "$resolved_hook_path" "resolved an empty hook path for $hook_path_repo hook $hook_path_name"
	case "$resolved_hook_path" in
	/* | ?:/*) printf '%s\n' "$resolved_hook_path" ;;
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
	install_hooks_outer_root=$(CDPATH='' cd -- "$install_hooks_outer_root" && pwd)
	install_hooks_git_nest_path=$(CDPATH='' cd -- "$(dirname -- "${0}")" && pwd)/git-nest
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
	outer_root=$(CDPATH='' cd -- "$outer_root" && pwd)
	GIT_NEST_path=$(CDPATH='' cd -- "$(dirname -- "${0}")" && pwd)/git-nest
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

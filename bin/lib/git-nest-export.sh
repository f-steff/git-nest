#!/bin/sh
#
# git-nest export ? sourced by bin/git_nest.sh
#
# Export archive creation, path absorption, and subproject inlining.
#
# Copyright (c) 2026 Flemming Steffensen.
# License: MIT
# SPDX-License-Identifier: MIT

infer_export_format() {
	output=$1
	case "$output" in
	*.tar.gz | *.tgz) printf 'tar.gz\n' ;;
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
	tar.gz | zip | dir) ;;
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
		printf '%s/%s\n' "$(CDPATH='' cd -- "$dir" && pwd)" "$base"
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
	(
		cd "$stage" && "$python_cmd" - "$output" "$deterministic" <<'PY'
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
		--include-git)
			include_git=1
			shift
			;;
		--deterministic)
			deterministic=1
			shift
			;;
		--allow-dirty)
			allow_dirty=1
			shift
			;;
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
		--preserve-history)
			preserve_history=1
			shift
			;;
		--push)
			push_after=1
			shift
			;;
		--message)
			[ $# -ge 2 ] || usage_error "--message requires text"
			message=$2
			shift 2
			;;
		--force)
			force=1
			shift
			;;
		--dry-run)
			dry_run=1
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
	files)
		assert_no_case_collision "$path"
		absorb_files
		;;
	nested-repo | submodule)
		assert_no_case_collision "$path"
		absorb_existing_repo
		;;
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
		--commit)
			commit_after=1
			shift
			;;
		--message)
			[ $# -ge 2 ] || usage_error "--message requires text"
			message=$2
			commit_after=1
			shift 2
			;;
		--dry-run)
			dry_run=1
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

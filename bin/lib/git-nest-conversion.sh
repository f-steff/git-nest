#!/bin/sh
#
# git-nest: record and restore reproducible nests of independent Git repositories.
# https://github.com/f-steff/git-nest
#
# git-nest conversion -- sourced by bin/git-nest-main.sh
#
# Nest-boundary conversions: export archive creation, path absorption
# (bringing external repos into the nest), and subproject inlining
# (dissolving a subproject back into outer files), plus the shared
# recovery-backup infrastructure used by the destructive conversions.
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

# Reject export formats other than tar.gz, zip, or dir with a clear message.
validate_export_format() {
	case "$1" in
	tar.gz | zip | dir) ;;
	*) usage_error "--format must be tar.gz, zip, or dir" ;;
	esac
}

# Resolve the export output path to an absolute form, creating the parent
# directory for relative paths so the archive or directory lands predictably.
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

# Collect checked-out subprojects with dirty working trees into a file, so
# export can refuse (or warn) before producing an inconsistent archive.
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

# Write a MANIFEST.lock placeholder into the staged tree when exporting
# deterministically, so consumers can detect a concurrent manifest update.
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

# Return 0 when a tracked file carries the export-ignore attribute, so it is
# excluded from the staged export tree.
path_has_export_ignore() {
	repo=$1
	rel=$2
	git -C "$repo" check-attr export-ignore -- "$rel" 2>/dev/null |
		grep ': export-ignore: set$' >/dev/null 2>&1
}

# Copy one file into the export stage, creating parent directories and
# preserving permissions (cp -p) for reproducible archives.
copy_file_to_stage() {
	src=$1
	dst=$2
	dst_dir=$(dirname -- "$dst")
	mkdir -p "$dst_dir" || git_error "failed to create export directory $dst_dir"
	cp -p "$src" "$dst" || git_error "failed to copy $src"
}

# Copy all tracked (and optionally .git) files of one subproject into the
# export stage, honoring export-ignore attributes per file.
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

# Build the full export staging tree (manifest, lock, and every subproject),
# aborting with a precondition error when any subproject checkout is missing.
stage_export_tree() {
	stage=$1
	include_git=$2
	deterministic=$3
	copy_file_to_stage "$MANIFEST_FILE" "$stage/$MANIFEST_FILE"
	write_export_manifest_lock "$stage" "$deterministic"
	# Read from a temp file rather than piping into the while loop: piping runs
	# the loop in a subshell, so a precondition_error (which calls exit) inside
	# it would only terminate that subshell, letting the export silently
	# continue and produce an incomplete archive instead of aborting.
	set_tmp=$(mktemp)
	manifest_subprojects >"$set_tmp"
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if [ ! -d "$path/.git" ]; then
			rm -f "$set_tmp"
			precondition_error "cannot export missing subproject $path; run git-nest restore"
		fi
		copy_subproject_files_to_stage "$path" "$stage" "$include_git"
	done <"$set_tmp"
	rm -f "$set_tmp"
}

# Normalize all timestamps in the stage to a fixed 1980-01-01 so archives
# are byte-identical across runs (deterministic export).
make_deterministic_stage() {
	stage=$1
	find "$stage" -exec touch -h -t 198001010000.00 {} + 2>/dev/null ||
		find "$stage" -exec touch -t 198001010000.00 {} +
}

# Write the staged tree as a tar.gz archive, using deterministic ordering
# and metadata when requested.  GNU tar provides --sort=name, --mtime,
# --owner/--group, and --numeric-owner to produce byte-identical archives;
# BSD tar (macOS, FreeBSD) has none of these flags, so we fall back to
# Python's tarfile module which is already required for deterministic zip exports.
write_tar_export() {
	stage=$1
	output=$2
	deterministic=$3
	rm -f "$output"
	if [ "$deterministic" -eq 1 ]; then
		if tar --version 2>/dev/null | grep -q "GNU tar"; then
			(cd "$stage" && GZIP=-n tar --sort=name --mtime='UTC 1980-01-01' --owner=0 --group=0 --numeric-owner -czf "$output" .) ||
				git_error "failed to write deterministic tar.gz export $output"
		else
			python_cmd=$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)
			[ -n "$python_cmd" ] || precondition_error "deterministic tar.gz export requires GNU tar or python"
			(
				cd "$stage" && "$python_cmd" - "$output" <<'PY'
import gzip
import io
import os
import sys
import tarfile

output = sys.argv[1]
MTIME = 315532800  # 1980-01-01 00:00:00 UTC

file_entries = []
dir_entries = set()
for root, dirs, files in os.walk("."):
    dirs.sort()
    files.sort()
    dir_entries.add(root)
    for name in files:
        path = os.path.join(root, name)
        file_entries.append(path)

buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w") as tar:
    for d in sorted(dir_entries):
        arcname = d + "/" if not d.endswith("/") and d != "." else d
        info = tarfile.TarInfo(arcname)
        info.type = tarfile.DIRTYPE
        info.mtime = MTIME
        info.uid = 0
        info.gid = 0
        info.uname = "root"
        info.gname = "root"
        info.mode = 0o755
        try:
            st = os.stat(d)
            info.mode = st.st_mode
        except OSError:
            pass
        tar.addfile(info)
    for path in sorted(file_entries):
        info = tar.gettarinfo(path, arcname=path)
        info.mtime = MTIME
        info.uid = 0
        info.gid = 0
        info.uname = "root"
        info.gname = "root"
        with open(path, "rb") as fh:
            tar.addfile(info, fh)

# filename="" suppresses the FNAME flag in the gzip header; without it
# Python's GzipFile derives the archive name from the file object's .name
# attribute, making the output non-deterministic when the user passes
# different --output filenames across runs.
with open(output, "wb") as f:
    with gzip.GzipFile(fileobj=f, mode="wb", mtime=0, compresslevel=9, filename="") as gz:
        gz.write(buf.getvalue())
PY
			) || git_error "failed to write deterministic tar.gz export $output"
		fi
	else
		(cd "$stage" && tar -czf "$output" .) ||
			git_error "failed to write tar.gz export $output"
	fi
}

# Write the staged tree as a zip archive via the standard library zipfile,
# with deterministic entry timestamps and modes when requested.
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

# Copy the staged tree into a plain output directory, preserving the exact
# file layout of the export (used by --format dir).
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

# Print a UTC timestamp for recovery-backup directory names, stable and
# sortable across platforms.
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
# Uses an afph_-prefixed path (rather than bare path) because absorb_files
# calls this without a subshell while holding its own bare path across the call.
absorb_files_preserve_history_repo() {
	afph_path=$1
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
		git-filter-repo --path "$afph_path/" --path-rename "$afph_path/": --force >/dev/null 2>&1 ||
			git_error "git-filter-repo failed while absorbing $afph_path"
		git branch -M "$branch" || git_error "failed to rename absorbed branch to $branch"
		git remote remove origin >/dev/null 2>&1 || true
		git remote add origin "$remote_url" || git_error "failed to set absorbed origin"
	)
	rm -rf -- "$afph_path" || git_error "failed to replace $afph_path with absorbed repository"
	cp -R "$filtered" "$afph_path" || git_error "failed to install absorbed repository at $afph_path"
}

# Build a fresh single-commit subproject repo from tracked outer files. Used by
# the files source of absorb without --preserve-history.
# Uses an afsr_-prefixed path (rather than bare path) because absorb_files,
# absorb_subrepo, and absorb_subtree all call this without a subshell while
# holding their own bare path across the call.
absorb_files_snapshot_repo() {
	afsr_path=$1
	branch=$2
	remote_url=$3
	message=$4
	outer_user_name=$(git config user.name 2>/dev/null || true)
	outer_user_email=$(git config user.email 2>/dev/null || true)
	(
		cd "$afsr_path" || exit 1
		git init -b "$branch" >/dev/null 2>&1 || {
			git init >/dev/null
			git checkout -b "$branch" >/dev/null
		}
		[ -z "$outer_user_name" ] || git config user.name "$outer_user_name"
		[ -z "$outer_user_email" ] || git config user.email "$outer_user_email"
		git remote add origin "$remote_url" || git_error "failed to set origin for $afsr_path"
		git add -A || git_error "failed to stage absorbed files in $afsr_path"
		git commit --allow-empty -m "$message" >/dev/null ||
			git_error "failed to create initial absorb commit in $afsr_path"
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

# Read one key from a .gitrepo file (git-subrepo metadata). Values use
# "key = value" syntax inside a bracketed [subrepo] section.
gitrepo_get() {
	gr_file=$1
	gr_key=$2
	awk -v key="$gr_key" '
		/^\[subrepo\]/ { insec = 1; next }
		/^\[/ { insec = 0 }
		insec {
			line = $0
			eq = index(line, "=")
			if (eq == 0) next
			k = substr(line, 1, eq - 1)
			gsub(/^[ \t]+|[ \t]+$/, "", k)
			if (k == key) {
				v = substr(line, eq + 1)
				gsub(/^[ \t]+|[ \t]+$/, "", v)
				print v
				exit
			}
		}
	' "$gr_file"
}

# Absorb a git-subrepo (marked by <path>/.gitrepo) into the nest as a managed
# subproject. Forward-only: no attempt is made to reconstruct or preserve the
# subrepo's own merge/split history -- the resulting subproject is a fresh
# single-commit snapshot, exactly like absorbing plain outer-repository files.
# Reads parsed globals from cmd_absorb.
absorb_subrepo() {
	if [ "$branch_set" -eq 1 ] || [ "$preserve_history" -eq 1 ] || [ "$push_after" -eq 1 ]; then
		usage_error "--branch, --preserve-history, and --push do not apply to --subrepo; the branch and remote come from .gitrepo unless overridden by <remote-url>"
	fi
	gitrepo_file="$path/.gitrepo"
	[ -f "$gitrepo_file" ] || precondition_error "$path has no .gitrepo file; it is not a git-subrepo (use plain absorb for outer-repo files, or absorb --subtree for a Git subtree)"
	sr_remote=$(gitrepo_get "$gitrepo_file" remote)
	sr_commit=$(gitrepo_get "$gitrepo_file" commit)
	sr_branch=$(gitrepo_get "$gitrepo_file" branch)
	[ -n "$sr_remote" ] || precondition_error "$gitrepo_file has no remote entry; cannot determine the subrepo's upstream URL"
	url=${repo_arg:-$sr_remote}
	# Target branch: the .gitrepo branch, else the subrepo's own remote
	# default (the subrepo path is tracked by the outer repo, so there is
	# no local checkout to infer from). main is the absolute last resort.
	target=$sr_branch
	[ -n "$target" ] || target=$(git ls-remote --symref "$url" HEAD 2>/dev/null | sed -n 's/^ref: refs\/heads\/\([^\t]*\)\tHEAD$/\1/p' || true)
	[ -n "$target" ] || target=main
	assert_path_not_containing_nested_project "$path"
	[ -d "$path" ] || precondition_error "$path is not a directory"
	if ! git ls-files -- "$path" | sed -n '1p' | grep . >/dev/null 2>&1; then
		precondition_error "$path has no tracked files to absorb"
	fi

	emit_path=$path
	emit_target=$target
	emit_url=$url

	if [ "$dry_run" -eq 1 ]; then
		[ "$json" -eq 0 ] || GIT_NEST_JSON_DRY_RUN=1
		if [ "$json" -eq 1 ]; then
			json_single_row_result "$pretty" absorb 1 A "$emit_path" subrepo "$emit_target" - "$emit_url" "would absorb git-subrepo into the nest (forward-only; upstream merge/split history is not reconstructed)"
		else
			printf 'Would absorb subrepo %s into the nest as a subproject (remote %s).\n' "$emit_path" "$emit_url"
			printf 'The .gitrepo-recorded upstream commit %s and its merge/split history would NOT be reconstructed; the subproject starts as a single fresh commit.\n' "${sr_commit:-unknown}"
		fi
		return 0
	fi

	[ -n "$message" ] || message="Absorb subrepo $path"
	staged_under_path=$(git diff --cached --name-only -- "$path" 2>/dev/null | sed -n '1p')
	if [ -n "$staged_under_path" ] && [ "$force" -eq 0 ]; then
		precondition_error "$path has staged outer-repository changes; review them or rerun absorb --subrepo with --force to replace that staged state"
	fi
	unstaged_under_path=$(git diff --name-only -- "$path" 2>/dev/null | sed -n '1p')
	[ -z "$unstaged_under_path" ] || precondition_error "$path has unstaged content changes; commit these files in the outer repo first, then rerun absorb --subrepo"
	untracked_under_path=$(git ls-files --others --exclude-standard -- "$path" 2>/dev/null | sed -n '1p')
	[ -z "$untracked_under_path" ] || precondition_error "$path has untracked files; commit these files in the outer repo first, then rerun absorb --subrepo"

	ensure_gitignore_hygiene
	backup=$(begin_recovery_backup "absorb --subrepo" "$path" \
		"    rm -rf \"$path\"
    mv \"<this-dir>/original\" \"$path\"

This restores the original git-subrepo directory (including its .gitrepo
metadata file) that was at $path before the conversion.")
	copy_path_backup "$path" "$backup/original"

	rm -f "$path/.gitrepo" || git_error "failed to remove .gitrepo metadata from $path"
	absorb_files_snapshot_repo "$path" "$target" "$url" "$message"

	revision=$(resolve_head_commit "$path" "cannot resolve absorbed subrepo $path")
	emit_revision=$revision
	git rm -r --cached -- "$path" >/dev/null 2>&1 ||
		git_error "failed to untrack absorbed subrepo files from outer repository"
	ensure_gitignore_entry "$path"
	manifest_write_subproject "$path" "$url" tracked "$target" "$revision" "$clone_mode"
	write_materialized_state
	stage_outer_paths "$MANIFEST_FILE" .gitignore
	end_recovery_backup "$backup"

	if [ "$json" -eq 1 ]; then
		json_single_row_result "$pretty" absorb 1 A "$emit_path" subrepo "$emit_target" "$emit_revision" "$emit_url" "absorbed git-subrepo into the nest"
	else
		printf 'Absorbed subrepo %s as a git-nest subproject at %.12s (remote %s).\n' "$emit_path" "$emit_revision" "$emit_url"
		printf 'The upstream merge/split history recorded in the former .gitrepo file was not preserved.\n'
	fi
}

# Absorb a Git subtree (a plain tracked folder previously added with
# `git subtree add`) into the nest as a managed subproject. There is no
# reliable marker for a subtree, so this path is reached only when the caller
# explicitly passes --subtree; the remote URL must be supplied because a
# subtree keeps no record of it once merged. Forward-only: the resulting
# subproject is a fresh single-commit snapshot, exactly like plain outer-repo
# file absorption. Reads parsed globals from cmd_absorb.
absorb_subtree() {
	if [ "$preserve_history" -eq 1 ] || [ "$push_after" -eq 1 ]; then
		usage_error "--preserve-history and --push do not apply to --subtree; the conversion is always a fresh single-commit snapshot"
	fi
	[ -n "$repo_arg" ] || usage_error "absorbing a subtree needs a remote URL: git-nest absorb --subtree <path> <remote-url> [options]"
	assert_path_not_containing_nested_project "$path"
	[ -d "$path" ] || precondition_error "$path is not a directory"
	if ! git ls-files -- "$path" | sed -n '1p' | grep . >/dev/null 2>&1; then
		precondition_error "$path has no tracked outer-repository files to absorb; commit these files in the outer repo first, then rerun absorb --subtree"
	fi

	emit_path=$path
	emit_target=$branch
	emit_url=$repo_arg

	if [ "$dry_run" -eq 1 ]; then
		[ "$json" -eq 0 ] || GIT_NEST_JSON_DRY_RUN=1
		if [ "$json" -eq 1 ]; then
			json_single_row_result "$pretty" absorb 1 A "$emit_path" subtree "$emit_target" - "$emit_url" "would absorb subtree into the nest as a fresh single-commit subproject (forward-only; prior subtree history is not carried across)"
		else
			printf 'Would absorb subtree %s into the nest as subproject on branch %s (remote %s).\n' "$emit_path" "$branch" "$emit_url"
			printf 'Prior subtree merge/split history would NOT be carried across; the subproject starts as a single fresh commit.\n'
		fi
		return 0
	fi

	[ -n "$message" ] || message="Absorb subtree $path"
	staged_under_path=$(git diff --cached --name-only -- "$path" 2>/dev/null | sed -n '1p')
	if [ -n "$staged_under_path" ] && [ "$force" -eq 0 ]; then
		precondition_error "$path has staged outer-repository changes; review them or rerun absorb --subtree with --force to replace that staged state"
	fi
	unstaged_under_path=$(git diff --name-only -- "$path" 2>/dev/null | sed -n '1p')
	[ -z "$unstaged_under_path" ] || precondition_error "$path has unstaged content changes; commit these files in the outer repo first, then rerun absorb --subtree"
	untracked_under_path=$(git ls-files --others --exclude-standard -- "$path" 2>/dev/null | sed -n '1p')
	[ -z "$untracked_under_path" ] || precondition_error "$path has untracked files; commit these files in the outer repo first, then rerun absorb --subtree"

	ensure_gitignore_hygiene
	backup=$(begin_recovery_backup "absorb --subtree" "$path" \
		"    rm -rf \"$path\"
    mv \"<this-dir>/original\" \"$path\"

This restores the original tracked files that were at $path before the
subtree conversion.")
	copy_path_backup "$path" "$backup/original"

	absorb_files_snapshot_repo "$path" "$branch" "$repo_arg" "$message"

	revision=$(resolve_head_commit "$path" "cannot resolve absorbed subtree $path")
	emit_revision=$revision
	git rm -r --cached -- "$path" >/dev/null 2>&1 ||
		git_error "failed to untrack absorbed subtree files from outer repository"
	ensure_gitignore_entry "$path"
	manifest_write_subproject "$path" "$repo_arg" tracked "$branch" "$revision" "$clone_mode"
	write_materialized_state
	stage_outer_paths "$MANIFEST_FILE" .gitignore
	end_recovery_backup "$backup"

	if [ "$json" -eq 1 ]; then
		json_single_row_result "$pretty" absorb 1 A "$emit_path" subtree "$emit_target" "$emit_revision" "$emit_url" "absorbed subtree into the nest"
	else
		printf 'Absorbed subtree %s as a git-nest subproject at %.12s (remote %s).\n' "$emit_path" "$emit_revision" "$emit_url"
		printf 'Prior subtree history was not carried across.\n'
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
	# Choose the target branch: an explicit submodule branch, else the
	# current branch, else the origin default. No name is assumed; the
	# main fallback below applies only when nothing exists to infer from.
	target=$sub_branch
	if [ -z "$target" ] && [ -e "$path/.git" ]; then
		target=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
		[ -n "$target" ] || target=$(default_target_branch "$path")
	fi
	# Absolute last resort for a submodule with no checkout and no
	# recorded branch; the materialized checkout later follows the
	# remote default instead of trusting this guess.
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
	# Default branch for a newly created files-source repo. This is a
	# creation choice, not an assumption about an existing repository:
	# honor the user's init.defaultBranch, falling back to main.
	branch=$(git config --get init.defaultBranch 2>/dev/null || true)
	[ -n "$branch" ] || branch=main
	branch_set=0
	clone_mode=
	preserve_history=0
	push_after=0
	message=
	force=0
	dry_run=0
	json=0
	pretty=0
	subrepo=0
	subtree=0
	path_arg=
	repo_arg=
	while [ $# -gt 0 ]; do
		case "$1" in
		--subrepo)
			subrepo=1
			shift
			;;
		--subtree)
			subtree=1
			shift
			;;
		--branch)
			[ $# -ge 2 ] || usage_error "--branch requires a name"
			branch=$2
			branch_set=1
			shift 2
			;;
		--clone-mode)
			[ $# -ge 2 ] || usage_error "--clone-mode requires full, partial, or shallow"
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
	[ "$subrepo" -eq 0 ] || [ "$subtree" -eq 0 ] || usage_error "--subrepo and --subtree are mutually exclusive"
	[ -n "$path_arg" ] || usage_error "usage: git-nest absorb <path> [<remote-url>] [options]"
	reject_backslash_path "$path_arg"
	path=$(normalize_path "$path_arg")

	acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	assert_path_not_inside_nested_project "$path"

	# --subrepo and --subtree are explicit, conscious conversions: they touch
	# actual tracked files in the outer repository, so they are never
	# auto-detected. Refuse an already-managed path before routing to them.
	if [ "$subrepo" -eq 1 ] || [ "$subtree" -eq 1 ]; then
		if [ -n "$(subproject_repo "$path" || true)" ]; then
			precondition_error "$path is already a nest subproject; use git-nest inline, git-nest detach, or git-nest remove to take it out of the nest"
		fi
		assert_no_case_collision "$path"
		if [ "$subrepo" -eq 1 ]; then
			absorb_subrepo
		else
			absorb_subtree
		fi
		return
	fi

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

# Make sure a nest exists at the current Git root before absorb-all scans and
# absorbs, mirroring cmd_init's own nested-nest-conflict handling exactly (see
# docs/command-behavior-contract.md) rather than reimplementing it differently.
# Already a nest: return immediately. Not yet a nest, but nested inside an
# ancestor one: refuse unless --sure, exactly like init --sure. Otherwise:
# initialize here, the same as plain init would.
#
# The lock is released immediately after use (cleanup_manifest_lock) instead
# of being held for the rest of the batch: each subsequent per-item absorb
# call runs in its own subshell to survive a mid-batch failure (see
# cmd_absorb_all), and a subshell inherits MANIFEST_LOCK_HELD and the EXIT
# trap that releases it -- if this function left the lock held, the first
# such subshell to exit would prematurely delete it out from under the rest
# of the batch.
absorb_all_ensure_nest() {
	aan_sure=$1
	aan_dry_run=$2
	aan_json=$3
	if root=$(git rev-parse --show-toplevel 2>/dev/null); then
		cd "$root" || die "cannot enter Git root $root"
	fi
	[ -f "$MANIFEST_FILE" ] && return 0
	if parent_root=$(nearest_parent_manifest_root 2>/dev/null); then
		[ "$aan_sure" -eq 1 ] || precondition_error "this directory is inside existing git-nest workspace $parent_root; rerun git-nest absorb-all --sure to create an intentional nested nest here"
	fi
	assert_new_nest_excludes_ancestor_subprojects
	if [ "$aan_dry_run" -eq 1 ]; then
		# --dry-run must never write, so report the plan and stop here; the
		# caller skips validate_manifest_schema when no manifest exists yet.
		[ "$aan_json" -eq 1 ] || printf 'Would create a git-nest workspace at %s before absorbing.\n' "$(pwd)"
		return 0
	fi
	ensure_outer_repo
	acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	ensure_gitattributes_guard
	[ -f .gitignore ] || : >.gitignore
	ensure_gitignore_hygiene
	cleanup_manifest_lock
}

# absorb-all scans like survey, then absorbs every detected submodule and
# nested repo into the nest in one step. It never absorbs git-subrepos or
# subtrees (always a conscious absorb --subrepo/--subtree action) and never
# absorbs anything found underneath a boundary the scan already classified
# (survey's boundary rule -- see development/technical_docs.md).
cmd_absorb_all() {
	sure=0
	force_partial=0
	dry_run=0
	json=0
	pretty=0
	max_depth=4
	excludes=$SURVEY_DEFAULT_EXCLUDES
	includes_file=$(mktemp)
	: >"$includes_file"
	while [ $# -gt 0 ]; do
		case "$1" in
		--sure)
			sure=1
			shift
			;;
		--force-partial)
			force_partial=1
			shift
			;;
		--dry-run)
			dry_run=1
			shift
			;;
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
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			pretty=1
			shift
			;;
		--*) usage_error "unknown absorb-all option: $1" ;;
		*) usage_error "absorb-all takes no positional arguments" ;;
		esac
	done

	absorb_all_ensure_nest "$sure" "$dry_run" "$json"
	[ ! -f "$MANIFEST_FILE" ] || validate_manifest_schema

	scan_rows=$(mktemp)
	survey_collect_rows "$max_depth" "$excludes" "$includes_file" "$scan_rows"
	rm -f "$includes_file"

	# Only submodules and nested repos, and only ones not already inside
	# another boundary this same scan classified (target column is "-").
	# Carries the source kind (sc_state) alongside the path so the result rows
	# below can report it, matching plain absorb's own JSON row shape.
	candidates=$(mktemp)
	while IFS='	' read -r sc_code sc_path sc_state sc_target sc_current sc_expected sc_detail; do
		[ -n "$sc_code" ] || continue
		case "$sc_code" in
		S | R) ;;
		*) continue ;;
		esac
		[ "$sc_target" = "-" ] || continue
		printf '%s\t%s\n' "$sc_path" "$sc_state" >>"$candidates"
	done <"$scan_rows"
	rm -f "$scan_rows"

	# Absorb deepest paths first, so a nested repo is absorbed before any repo
	# containing it. survey_collect_rows already sorted shallowest-first;
	# reverse that stable order rather than re-deriving depth here.
	ordered=$(mktemp)
	sed '1!G;h;$!d' "$candidates" >"$ordered"
	rm -f "$candidates"

	result_rows=$(mktemp)
	empty=$(mktemp)

	if [ "$dry_run" -eq 1 ]; then
		while IFS='	' read -r cpath ckind; do
			[ -n "$cpath" ] || continue
			cpath_q=$(shell_quote "$cpath")
			printf 'A\t%s\t%s\t-\t-\t-\twould absorb %s into the nest\n' "$cpath" "$ckind" "$cpath_q" >>"$result_rows"
		done <"$ordered"
		if [ "$json" -eq 1 ]; then
			GIT_NEST_JSON_DRY_RUN=1
			emit_json_result absorb-all 1 1 "$result_rows" "$empty" "$empty" "$pretty"
		elif [ -s "$result_rows" ]; then
			printf 'Would absorb %s subproject(s):\n' "$(wc -l <"$result_rows" | tr -d '[:space:]')"
			while IFS='	' read -r rc_code rc_path rc_state rc_target rc_current rc_expected rc_detail; do
				printf '  %s\n' "$rc_detail"
			done <"$result_rows"
		else
			printf 'No submodules or nested repos found to absorb.\n'
		fi
		rm -f "$ordered" "$result_rows" "$empty"
		return 0
	fi

	if [ ! -s "$ordered" ]; then
		rm -f "$ordered" "$result_rows"
		if [ "$json" -eq 1 ]; then
			emit_json_result absorb-all 0 1 "$empty" "$empty" "$empty" "$pretty"
		else
			printf 'No submodules or nested repos found to absorb.\n'
		fi
		rm -f "$empty"
		return 0
	fi

	# Back up everything this batch could touch before absorbing anything, so
	# a mid-batch failure can be rolled back completely by default: the three
	# shared outer-repo files, plus (per item) a full copy of the path as it
	# looked before that item's absorb ran. Uses the same transient,
	# self-documenting recovery-backup convention as inline/absorb
	# --preserve-history, so a leftover after a crash is discoverable the
	# same way (git-nest doctor's recovery-backup check, RECOVERY.txt).
	batch=$(begin_recovery_backup "absorb-all" "batch" \
		"    rm -rf \"$MANIFEST_FILE\" .gitignore .gitmodules
    cp \"<this-dir>/$MANIFEST_FILE.orig\" \"$MANIFEST_FILE\" 2>/dev/null
    cp \"<this-dir>/gitignore.orig\" .gitignore 2>/dev/null
    cp \"<this-dir>/gitmodules.orig\" .gitmodules 2>/dev/null
    for d in \"<this-dir>\"/item-*; do
        p=\$(cat \"\$d/path\")
        rm -rf -- \"\$p\"
        mv \"\$d/original\" \"\$p\"
    done

This restores every subproject absorbed by this absorb-all run, and the
outer manifest/ignore/submodule files, to how they looked before it started.")
	[ -f "$MANIFEST_FILE" ] && cp "$MANIFEST_FILE" "$batch/$MANIFEST_FILE.orig"
	[ -f .gitignore ] && cp .gitignore "$batch/gitignore.orig"
	[ -f .gitmodules ] && cp .gitmodules "$batch/gitmodules.orig"

	absorbed=0
	failed_path=
	failed_err=$(mktemp)

	while IFS='	' read -r cpath ckind; do
		[ -n "$cpath" ] || continue
		item_hash=$(printf '%s' "$cpath" | cksum)
		item_hash=${item_hash%% *}
		item_dir="$batch/item-$item_hash"
		mkdir -p "$item_dir"
		printf '%s\n' "$cpath" >"$item_dir/path"
		copy_path_backup "$cpath" "$item_dir/original"

		item_err=$(mktemp)
		if (cmd_absorb "$cpath") >/dev/null 2>"$item_err"; then
			absorbed=$((absorbed + 1))
			# The subshell wrote fresh manifest content to disk, but this
			# process's own manifest cache does not know that (subshell
			# variable changes never propagate back); force a re-read so the
			# lookups below see what was actually just written.
			_MNF_LOADED=
			c_repo=$(subproject_repo "$cpath" || true)
			c_target=$(subproject_key "$cpath" target_branch || true)
			c_revision=$(subproject_key "$cpath" revision || true)
			printf 'A\t%s\t%s\t%s\t%s\t%s\tabsorbed %s into the nest\n' "$cpath" "$ckind" "${c_target:--}" "${c_revision:--}" "${c_repo:--}" "$ckind" >>"$result_rows"
			rm -f "$item_err"
		else
			failed_path=$cpath
			cp "$item_err" "$failed_err"
			rm -f "$item_err"
			break
		fi
	done <"$ordered"
	rm -f "$ordered"

	if [ -n "$failed_path" ]; then
		printf 'Error: absorb-all failed on %s:\n' "$failed_path" >&2
		cat "$failed_err" >&2
		if [ "$force_partial" -eq 1 ]; then
			printf '%s subproject(s) already absorbed remain in place (--force-partial). Fix the problem above, then rerun absorb-all for the rest.\n' "$absorbed" >&2
			end_recovery_backup "$batch"
		else
			printf 'Rolling back %s already-absorbed subproject(s)...\n' "$absorbed" >&2
			for item_dir in "$batch"/item-*; do
				[ -d "$item_dir" ] || continue
				spath=$(cat "$item_dir/path")
				rm -rf -- "$spath"
				mv "$item_dir/original" "$spath"
			done
			if [ -f "$batch/$MANIFEST_FILE.orig" ]; then
				cp "$batch/$MANIFEST_FILE.orig" "$MANIFEST_FILE"
			else
				rm -f "$MANIFEST_FILE"
			fi
			if [ -f "$batch/gitignore.orig" ]; then
				cp "$batch/gitignore.orig" .gitignore
			else
				rm -f .gitignore
			fi
			if [ -f "$batch/gitmodules.orig" ]; then
				cp "$batch/gitmodules.orig" .gitmodules
			else
				rm -f .gitmodules
			fi
			stage_outer_paths_if_repo "$MANIFEST_FILE" .gitignore
			[ -f .gitmodules ] && stage_outer_paths_if_repo .gitmodules || true
			_MNF_LOADED=
			end_recovery_backup "$batch"
			printf 'Rolled back. Fix the problem above and re-run absorb-all, or pass --force-partial next time to keep partial progress instead of rolling back.\n' >&2
		fi
		rm -f "$result_rows" "$empty" "$failed_err"
		exit "$EXIT_PRECONDITION"
	fi

	end_recovery_backup "$batch"
	rm -f "$failed_err"

	if [ "$json" -eq 1 ]; then
		emit_json_result absorb-all 0 1 "$result_rows" "$empty" "$empty" "$pretty"
	else
		printf 'Absorbed %s subproject(s):\n' "$absorbed"
		while IFS='	' read -r rc_code rc_path rc_state rc_target rc_current rc_expected rc_detail; do
			printf '  %s (%s) at %.12s\n' "$rc_path" "$rc_state" "$rc_current"
		done <"$result_rows"
	fi
	rm -f "$result_rows" "$empty"
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

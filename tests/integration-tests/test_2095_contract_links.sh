#!/bin/sh
# Test: hardlinks, symlinks, and junctions are handled safely. Survey
# never descends symlinked directories, absorb/add/move refuse paths
# that resolve through a link (a link can point outside the nest), the
# interactive browser hides links, and hardlinked files survive
# snapshot/restore/inline. Link steps skip gracefully on platforms that
# cannot create real directory links (Windows without junctions).

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_links

work=$(test_workspace contract_links)
# make_bare_remote reassigns the global `work` variable, so keep the
# workspace root in its own variable for the later steps.
work_root=$work
mkdir -p "$work"
cd "$work"

# Create a real directory link (symlink on POSIX, junction on Windows).
# Returns 0 when the link exists, 1 when the platform cannot create one.
make_dir_link() {
	link=$1
	target=$2
	ln -s "$target" "$link" 2>/dev/null || true
	[ -L "$link" ] && return 0
	# On MSYS, ln -s may have copied the target instead of linking;
	# remove the copy so the junction attempt below is not blocked.
	rm -rf "$link" 2>/dev/null || true
	# Windows: a junction works without admin rights; MSYS exposes it
	# as a symlink, so the same guards apply. MSYS2 path conversion is
	# disabled for the call so cmd receives /c and /J as flags.
	if command -v cmd >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
		MSYS2_ARG_CONV_EXCL='*' cmd /c mklink /J "$(cygpath -w "$link")" "$(cygpath -w "$target")" >/dev/null 2>&1 || true
		[ -L "$link" ] && return 0
	fi
	return 1
}

test_step "survey and tree never descend symlinked directories" "A directory link inside the nest that points at a repository outside the nest must be invisible to survey and tree: their scans use plain find, which does not descend links."
nest_dir="$work/nest"
mkdir -p "$nest_dir"
cd "$nest_dir"
"$GIT_NEST" init >/dev/null
git commit -qm start --allow-empty
make_repo "$work_root/outside-repo"
if make_dir_link "lib-escaped" "$work_root/outside-repo"; then
	"$GIT_NEST" survey --porcelain >survey.out 2>&1 || true
	assert_file_not_contains survey.out "lib-escaped"
	"$GIT_NEST" tree --all >tree.out 2>&1 || true
	assert_file_not_contains tree.out "lib-escaped"
	links_available=1
else
	echo "SKIP link steps: platform cannot create real directory links"
	links_available=0
fi

if [ "$links_available" -eq 1 ]; then
	test_step "absorb, add, and move refuse paths that resolve through a link" "A symlinked component can point outside the nest, so no command may manage a checkout through one; each must fail with exit 3 and name the symlink."
	set +e
	"$GIT_NEST" absorb lib-escaped >absorb.out 2>absorb.err
	absorb_rc=$?
	set -e
	[ "$absorb_rc" -eq 3 ] || {
		printf 'UNEXPECTED RESULT: absorb through a symlink must be refused (exit 3), got %s\n' "$absorb_rc" >&2
		exit 1
	}
	assert_file_contains absorb.err "symlink"
	grep -q 'subproject' .gitnest && {
		printf 'UNEXPECTED RESULT: refused absorb must not touch the manifest\n' >&2
		exit 1
	}
	set +e
	"$GIT_NEST" add "$work/outside-repo" lib-escaped >add.out 2>add.err
	add_rc=$?
	set -e
	[ "$add_rc" -eq 3 ] || {
		printf 'UNEXPECTED RESULT: add through a symlink must be refused (exit 3), got %s\n' "$add_rc" >&2
		exit 1
	}
	assert_file_contains add.err "symlink"
	# move: a real subproject may not be relocated through a link.
	make_bare_remote "$nest_dir/remotes/plain.git" "$work_root/plain-seed"
	git clone -q "$nest_dir/remotes/plain.git" real/plain
	"$GIT_NEST" absorb real/plain >/dev/null
	set +e
	"$GIT_NEST" move real/plain lib-escaped/elsewhere >move.out 2>move.err
	move_rc=$?
	set -e
	[ "$move_rc" -eq 3 ] || {
		printf 'UNEXPECTED RESULT: move through a symlink must be refused (exit 3), got %s\n' "$move_rc" >&2
		exit 1
	}
	assert_file_contains move.err "symlink"
	"$GIT_NEST" remove real/plain --force >/dev/null

	test_step "The interactive browser hides symlinked directories" "The folder browser must not list directory links, so the session can never cd or select a destination through one."
	run_capture "menu probe for browser step" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
	cd_num=$(sed -n "s|^ *\([0-9][0-9]*\)\. change directory .*|\1|p" probe.out | sed -n '1p')
	run_capture "browser hides links" browser.out browser.err -- "$GIT_NEST" interactive --ii-test "$cd_num" b q
	assert_file_not_contains browser.out "lib-escaped"

	test_step "Anchors deduplicate when the session starts through a link" "The nest root, start cwd, and current cwd anchors must compare as one entry even when the session was launched through a symlink (physical path normalization)."
	make_repo "$work_root/outside-repo"
	(cd "$work_root/outside-repo" && "$GIT_NEST" init >/dev/null)
	(cd "$work_root/outside-repo" && git commit -qm start --allow-empty)
	run_capture "menu probe through a link" probe.out probe.err -- "$GIT_NEST" interactive --ii-test q
	cd_num=$(sed -n "s|^ *\([0-9][0-9]*\)\. change directory .*|\1|p" probe.out | sed -n '1p')
	cd "$nest_dir/lib-escaped"
	run_capture "anchors through a link" anchors.out anchors.err -- "$GIT_NEST" interactive --ii-test "$cd_num" b q
	[ "$(grep -c 'jump to this start point' anchors.out)" -eq 1 ] || {
		printf 'UNEXPECTED RESULT: the three anchors must deduplicate to one entry when reached through a link\n' >&2
		exit 1
	}
fi

test_step "Hardlinked files survive snapshot, restore, and inline" "A subproject whose files share inodes must keep identical content through snapshot/restore and after inline dissolves it into the outer repo."
hard_dir="$work_root/hard"
mkdir -p "$hard_dir"
cd "$hard_dir"
"$GIT_NEST" init >/dev/null
git commit -qm start --allow-empty
make_bare_remote "$hard_dir/remotes/sub.git" "$work_root/hard-seed"
git clone -q "$hard_dir/remotes/sub.git" libs/hl
cd libs/hl
ln file.txt hardcopy.txt 2>/dev/null || cp file.txt hardcopy.txt
git add .
git commit -qm hardlinks
# inline refuses subprojects with local-only branch tips; the hardlink
# commit must be on the remote before the dissolve.
git push -qu origin main
cd "$hard_dir"
"$GIT_NEST" absorb libs/hl >/dev/null
"$GIT_NEST" snapshot >/dev/null
"$GIT_NEST" restore --force >/dev/null
cmp libs/hl/file.txt libs/hl/hardcopy.txt || {
	printf 'UNEXPECTED RESULT: hardlinked content differs after restore\n' >&2
	exit 1
}
"$GIT_NEST" inline libs/hl >/dev/null
[ -f libs/hl/file.txt ] && [ -f libs/hl/hardcopy.txt ] || {
	printf 'UNEXPECTED RESULT: inline must keep both linked files\n' >&2
	exit 1
}
cmp libs/hl/file.txt libs/hl/hardcopy.txt || {
	printf 'UNEXPECTED RESULT: hardlinked content differs after inline\n' >&2
	exit 1
}

describe_result "git-nest never descends or manages through directory links (survey/tree scans, absorb/add/move guards, interactive browser), deduplicates browser anchors through links, and preserves hardlinked content across snapshot/restore/inline."

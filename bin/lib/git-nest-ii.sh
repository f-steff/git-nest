#!/bin/sh
#
# git-nest interactive: a line-based guided menu over the full command
# surface (alias: git-nest ii). Why it exists: a full-screen TUI needed
# raw terminal mode and ANSI repainting, which is slow and impossible on
# the Windows console; a numbered menu read as plain lines works
# identically in Git Bash, cmd.exe, PowerShell, and piped scripts.
#
# Every action runs a fresh git-nest (or git) sub-process with inherited
# stdio, so output streams live and the interactive shell itself stays
# stateless; the workspace state (repos, nests, cwd) lives on disk.
#
# Test switches (internal, undocumented): --ii-test feeds scripted input
# tokens, --ii-skip drops the first n tokens, so tests can drive the
# loop without a terminal.

# ---------------------------------------------------------------------------
# Menu tables
# ---------------------------------------------------------------------------
# Each entry is label|kind|cmd|description; lines starting with ':' are
# group headings. Kinds: run = execute as-is, text = prompt for
# arguments, path = pick a subproject, path-text = pick plus one text
# prompt, cd = directory navigation, absorb-flow / takeout-flow = the
# combined membership workflows. The `change directory` entry is
# last in every context because filesystem navigation is always useful,
# no matter the workspace state.

II_ACTIONS_NONE="
:Get started
git init|run|git init|Initialize a Git repository in this folder
:Tooling
version|run|version|Show the git-nest version
:Navigation
change directory|cd|-|Move one level into a subfolder"

II_ACTIONS_GIT_ONLY="
:Nest setup
git-nest init|run|init|Create a .gitnest manifest at the Git root
git-nest clone|text|clone|Clone a nest repository and restore it here
:Tooling
version|run|version|Show the git-nest version
:Navigation
change directory|cd|-|Move one level into a subfolder"

II_ACTIONS_NEST="
:Nest setup
tidy|run|tidy|Refresh managed support files
clone|text|clone|Clone a nest repository and restore it here
:Subprojects
add|text|add|Add a repository as a managed subproject (URL + path)
move|path-text|move|Move a subproject to a new path
config|text|config|Read or update manifest and local settings
update|path-text|update|Move a subproject to a selected revision
:Workspace state
restore|run|restore|Materialize the recorded manifest state on disk
pull|run|pull|Fast-forward subprojects to their upstream heads
snapshot|run|snapshot|Record clean checkout commits in .gitnest
gc|run|gc|Prune unreferenced objects across subprojects
freeze|run|freeze|Pin subprojects to their current commits
:Inspection
status|run|status|Show nest root and subproject state
outdated|run|outdated|Check remotes for newer target-branch commits
verify|run|verify|Validate manifest, remotes, refs, and revisions
diff|run|diff|Show subproject commits since the manifest revisions
log|run|log|Show combined nest history
list|run|list|List managed subprojects with recorded and on-disk state
tree|run|tree|Show an ASCII tree of the nest
survey|run|survey|Scan for nested repos, submodules, and subrepos
doctor|run|doctor|Report environment and workspace health
:Branch bookmarks
branch-mark|run|branch-mark|Remember the current branch name
branch-unmark|text|branch-unmark|Forget a remembered branch name
branch-list|run|branch-list|List remembered branch names
branch-cleanup|run|branch-cleanup|Prune remembered branches that are gone
:Hooks
hooks-install|run|hooks-install|Install managed hooks in all repos
hooks-uninstall|run|hooks-uninstall|Remove managed hooks from all repos
:Iteration
foreach|text|foreach|Run a command in every checked-out subproject
foreach-modified|text|foreach-modified|Run a command in dirty subprojects
foreach-clean|text|foreach-clean|Run a command in clean subprojects
:Nest contents
bring in (absorb)|absorb-flow|-|Show detected repos/submodules, then absorb them
take out (inline/detach/remove)|takeout-flow|-|Show the tree, pick a subproject, inline/detach/remove
export|text|export|Export a source snapshot with MANIFEST.lock
:Tooling
version|run|version|Show the git-nest version
:Navigation
change directory|cd|-|Move one level into a subfolder"

# Pick the menu table for a context so the offered actions always match
# the workspace state (virgin folder, git repo, or nest).
ii_menu_for() {
	case "$1" in
	none) printf '%s\n' "$II_ACTIONS_NONE" ;;
	git-only) printf '%s\n' "$II_ACTIONS_GIT_ONLY" ;;
	*) printf '%s\n' "$II_ACTIONS_NEST" ;;
	esac
}

# Print a menu (table on stdin) as numbered lines with a right-aligned
# three-digit gutter so the units column of every number lines up, plus
# the b/q footer. Leaves the entry count in II_MENU_COUNT so callers can
# validate input against it.
ii_menu_show() {
	ii_mfile=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/ii-menu.$$")
	cat >"$ii_mfile"
	ii_w=0
	ii_n=0
	while IFS='|' read -r ii_lbl ii_kind ii_cmd ii_desc; do
		[ -n "$ii_lbl" ] || continue
		case "$ii_lbl" in
		:*) continue ;;
		esac
		ii_n=$((ii_n + 1))
		[ "${#ii_lbl}" -gt "$ii_w" ] && ii_w=${#ii_lbl}
	done <"$ii_mfile"
	II_MENU_COUNT=$ii_n
	ii_n=0
	while IFS='|' read -r ii_lbl ii_kind ii_cmd ii_desc; do
		[ -n "$ii_lbl" ] || continue
		case "$ii_lbl" in
		:*)
			printf '%s%s%s\n' "${HELP_SECTION:-}" "${ii_lbl#:}" "${HELP_RESET:-}"
			continue
			;;
		esac
		ii_n=$((ii_n + 1))
		printf '%3d. %-*s - %s\n' "$ii_n" "$ii_w" "$ii_lbl" "$ii_desc"
	done <"$ii_mfile"
	printf '%3s. %-*s - %s\n' 'b' "$ii_w" 'back' 'Return to the previous menu'
	printf '%3s. %-*s - %s\n' 'q' "$ii_w" 'quit' 'Exit git-nest interactive'
	rm -f "$ii_mfile"
}

# Classify an input line against the current menu count. Prints one
# token: run (a valid menu number), back (b or empty line), quit (q),
# or invalid. Numbers are bounded to three digits so the arithmetic
# below can never overflow.
ii_parse_input() {
	case "$1" in
	'') printf 'back\n' ;;
	q) printf 'quit\n' ;;
	b) printf 'back\n' ;;
	*[!0-9]* | ????*) printf 'invalid\n' ;;
	*)
		if [ "${#1}" -le 3 ] && [ "$1" -ge 1 ] && [ "$1" -le "$2" ]; then
			printf 'run\n'
		else
			printf 'invalid\n'
		fi
		;;
	esac
}

# Classify the current folder: none (no Git repo), git-only (repo but no
# nest), or nest. The menu adapts to this because the available commands
# depend on which setup steps the workspace has completed.
ii_context() {
	if command -v git >/dev/null 2>&1; then
		if git rev-parse --show-toplevel >/dev/null 2>&1; then
			if find_project_root >/dev/null 2>&1; then
				printf 'nest\n'
			else
				printf 'git-only\n'
			fi
		else
			printf 'none\n'
		fi
	else
		printf 'none\n'
	fi
}

# List the subdirectories one level down (hidden ones excluded, sorted),
# one per line. The glob skips dot-directories without needing find.
ii_subdirs() {
	for ii_d in */; do
		[ -d "$ii_d" ] || continue
		printf '%s\n' "${ii_d%/}"
	done | sort
}

# Read one input line into II_LINE. With --ii-test the next scripted
# token is served instead of the terminal and echoed so transcripts show
# what was "typed"; a nonzero return means EOF, which callers treat as a
# graceful quit.
ii_read_line() {
	ii_prompt=${1:-}
	if [ "$II_SCRIPTED" -eq 1 ]; then
		II_LINE=$(sed -n "${II_TOKEN_POS}p" "$II_TOKEN_FILE" 2>/dev/null || true)
		[ -n "$II_LINE" ] || return 1
		II_TOKEN_POS=$((II_TOKEN_POS + 1))
		printf '%s%s\n' "$ii_prompt" "$II_LINE"
	else
		printf '%s' "$ii_prompt"
		IFS= read -r II_LINE || return 1
	fi
	return 0
}

# Resolve the git-nest executable once. The entrypoint next to this
# module serves the checkout layout; installed copies fall back to PATH.
ii_resolve_git_nest() {
	if [ -x "$SCRIPT_DIR/git-nest" ]; then
		II_GIT_NEST="$SCRIPT_DIR/git-nest"
	elif command -v git-nest >/dev/null 2>&1; then
		II_GIT_NEST=git-nest
	else
		echo "git-nest interactive cannot find the git-nest executable." >&2
		exit 3
	fi
}

# Run one action: echo the command as `cwd>command ...`, then execute it
# with inherited stdio so output streams live. A nonzero exit from the
# action is shown but never kills the menu loop.
ii_run_command() {
	ii_cmdline=$1
	set -f
	set -- $ii_cmdline
	set +f
	[ $# -gt 0 ] || return 0
	if [ "$1" = "git" ]; then
		printf '%s%s>%s%s\n' "${HELP_CMD:-}" "$(pwd)" "$ii_cmdline" "${HELP_RESET:-}"
		"$@" || true
	else
		printf '%s%s>git-nest %s%s\n' "${HELP_CMD:-}" "$(pwd)" "$ii_cmdline" "${HELP_RESET:-}"
		"$II_GIT_NEST" "$@" || true
	fi
}

# Subproject picker for path-taking commands. Renders the same numbered
# menu with one entry per managed path; sets II_PATH on success. Returns
# nonzero when cancelled (back) or when quitting (II_QUIT is set).
ii_pick_subproject() {
	II_PATH=
	ii_rows=$("$II_GIT_NEST" list --porcelain 2>/dev/null | cut -f2 || true)
	ii_pick_table=
	while IFS= read -r ii_row; do
		[ -n "$ii_row" ] || continue
		ii_pick_table="$ii_pick_table$ii_row|run|$ii_row|managed subproject
"
	done <<EOF
$ii_rows
EOF
	if [ -z "$ii_pick_table" ]; then
		printf 'No subprojects are recorded in this nest.\n'
		return 1
	fi
	while :; do
		ii_menu_show <<EOF
$ii_pick_table
EOF
		ii_read_line '> ' || {
			II_QUIT=1
			return 1
		}
		case "$(ii_parse_input "$II_LINE" "$II_MENU_COUNT")" in
		back) return 1 ;;
		quit)
			II_QUIT=1
			return 1
			;;
		invalid) printf 'Unknown choice: %s\n' "$II_LINE" ;;
		run)
			II_PATH=$(printf '%s\n' "$ii_pick_table" | ii_table_entry "$II_LINE" | cut -d'|' -f1)
			return 0
			;;
		esac
	done
}

# Directory browser: move the interactive shell's own cwd one layer at a
# time. Subdirectories are numbered entries; `..` goes up one level;
# `b` returns to the main menu, where the context (and therefore the
# menu) is re-detected for the new location.
ii_pick_directory() {
	while :; do
		ii_cd_table=
		ii_parent=$(cd .. 2>/dev/null && pwd || true)
		if [ -n "$ii_parent" ] && [ "$ii_parent" != "$(pwd)" ]; then
			ii_cd_table="..|run|..|Go up one level
"
		fi
		ii_dirs=$(ii_subdirs)
		while IFS= read -r ii_d; do
			[ -n "$ii_d" ] || continue
			ii_cd_table="$ii_cd_table$ii_d|run|$ii_d|Open this folder
"
		done <<EOF
$ii_dirs
EOF
		if [ -z "$ii_cd_table" ]; then
			printf 'No subdirectories here.\n'
			return 1
		fi
		ii_menu_show <<EOF
$ii_cd_table
EOF
		ii_read_line '> ' || {
			II_QUIT=1
			return 1
		}
		case "$(ii_parse_input "$II_LINE" "$II_MENU_COUNT")" in
		back) return 0 ;;
		quit)
			II_QUIT=1
			return 1
			;;
		invalid) printf 'Unknown choice: %s\n' "$II_LINE" ;;
		run)
			ii_target=$(printf '%s\n' "$ii_cd_table" | ii_table_entry "$II_LINE" | cut -d'|' -f1)
			if [ "$ii_target" = ".." ]; then
				cd .. 2>/dev/null || printf 'Cannot go up from here.\n'
			else
				cd "$ii_target" 2>/dev/null || printf 'Cannot enter %s.\n' "$ii_target"
			fi
			;;
		esac
	done
}

# Print the nth entry line (skipping group headings and blank lines)
# from a menu table on stdin. The renderer numbers entries the same way,
# so this keeps choice extraction and display numbering in lockstep.
ii_table_entry() {
	ii_tn=$1
	awk -v want="$ii_tn" '
		/^:/ || length($0) == 0 { next }
		{ got++; if (got == want) { print; exit } }'
}

# Bring-in flow: show what survey found, then let the user absorb the
# detected targets one by one, all at once, or a manually typed path.
# The survey state code selects the right absorb form: git-subrepos need
# the explicit --subrepo flag, everything else absorbs plainly. The
# picker re-renders after every action, so absorbed items disappear.
ii_pick_absorb() {
	ii_run_command survey
	while :; do
		ii_rows=$("$II_GIT_NEST" survey --porcelain 2>/dev/null || true)
		ii_abs_table=
		while IFS='	' read -r ii_code ii_apath ii_astate ii_arest; do
			[ -n "$ii_apath" ] || continue
			case "$ii_astate" in
			subrepo) ii_form="absorb --subrepo" ;;
			*) ii_form="absorb" ;;
			esac
			ii_abs_table="$ii_abs_table$ii_apath|run|$ii_form|$ii_astate
"
		done <<EOF
$ii_rows
EOF
		if [ -n "$ii_abs_table" ]; then
			ii_menu_show <<EOF
$ii_abs_table
EOF
		else
			printf 'No unmanaged repositories or submodules detected.\n'
			II_MENU_COUNT=0
		fi
		ii_read_line '> ' || {
			II_QUIT=1
			return 1
		}
		case "$II_LINE" in
		a | A)
			# Bulk absorb, confirmed: absorb-all also rolls back its
			# own batch on failure, so the confirm is the only guard.
			ii_read_line "Absorb all detected? [y/N]: " || {
				II_QUIT=1
				return 1
			}
			case "$II_LINE" in
			y | Y | yes | YES) ii_run_command absorb-all ;;
			*) printf 'Cancelled.\n' ;;
			esac
			;;
		m | M)
			ii_pick_absorb_manual
			;;
		*)
			case "$(ii_parse_input "$II_LINE" "$II_MENU_COUNT")" in
			back) return 0 ;;
			quit)
				II_QUIT=1
				return 1
				;;
			invalid) printf 'Unknown choice: %s\n' "$II_LINE" ;;
			run)
				ii_target=$(printf '%s\n' "$ii_abs_table" | ii_table_entry "$II_LINE" | cut -d'|' -f1)
				ii_form=$(printf '%s\n' "$ii_abs_table" | ii_table_entry "$II_LINE" | cut -d'|' -f3)
				ii_run_command "$ii_form $ii_target"
				;;
			esac
			;;
		esac
	done
}

# Manual bring-in target: classify the typed path so folders (which
# cannot absorb without a remote URL) are prompted for one, while
# repositories and git-subrepos absorb without extra input.
ii_pick_absorb_manual() {
	ii_read_line "Path (folders need a remote URL after): " || {
		II_QUIT=1
		return 1
	}
	[ -n "$II_LINE" ] || {
		printf 'Cancelled.\n'
		return 0
	}
	ii_manual_path=$II_LINE
	if [ -e "$ii_manual_path/.git" ]; then
		ii_run_command "absorb $ii_manual_path"
	elif [ -e "$ii_manual_path/.gitrepo" ]; then
		ii_run_command "absorb --subrepo $ii_manual_path"
	else
		ii_read_line "Remote URL for $ii_manual_path: " || {
			II_QUIT=1
			return 1
		}
		if [ -n "$II_LINE" ]; then
			ii_run_command "absorb $ii_manual_path $II_LINE"
		else
			printf 'Cancelled.\n'
		fi
	fi
}

# Take-out flow: show the whole nest first (tree --all marks managed and
# unmanaged findings), then pick a managed subproject and choose inline,
# detach, or remove -- each confirmed before it runs.
ii_pick_takeout() {
	ii_run_command "tree --all"
	if ! ii_pick_subproject; then
		return 0
	fi
	ii_read_line "Take out $II_PATH: inline (i), detach (d), or remove (r)? " || {
		II_QUIT=1
		return 0
	}
	case "$II_LINE" in
	i | I) ii_takeout_verb="inline" ;;
	d | D) ii_takeout_verb="detach" ;;
	r | R) ii_takeout_verb="remove" ;;
	*)
		printf 'Cancelled.\n'
		return 0
		;;
	esac
	ii_read_line "Run git-nest $ii_takeout_verb $II_PATH? [y/N]: " || {
		II_QUIT=1
		return 0
	}
	case "$II_LINE" in
	y | Y | yes | YES) ii_run_command "$ii_takeout_verb $II_PATH" ;;
	*) printf 'Cancelled.\n' ;;
	esac
}

# Dispatch one menu entry by its kind: run, prompt-for-text, pick a
# subproject, pick plus text, directory browsing, or one of the
# membership flows.
ii_exec_entry() {
	ii_entry=$1
	II_ENTRY_LABEL=${ii_entry%%|*}
	ii_rest=${ii_entry#*|}
	II_ENTRY_KIND=${ii_rest%%|*}
	ii_rest=${ii_rest#*|}
	II_ENTRY_CMD=${ii_rest%%|*}
	case "$II_ENTRY_KIND" in
	run)
		ii_run_command "$II_ENTRY_CMD"
		;;
	text)
		ii_read_line "Enter arguments for $II_ENTRY_CMD (empty cancels): " || {
			II_QUIT=1
			return 0
		}
		if [ -n "$II_LINE" ]; then
			ii_run_command "$II_ENTRY_CMD $II_LINE"
		else
			printf 'Cancelled.\n'
		fi
		;;
	path)
		ii_pick_subproject || return 0
		ii_run_command "$II_ENTRY_CMD $II_PATH"
		;;
	path-text)
		ii_pick_subproject || return 0
		ii_read_line "Value for $II_ENTRY_CMD (empty cancels): " || {
			II_QUIT=1
			return 0
		}
		if [ -n "$II_LINE" ]; then
			ii_run_command "$II_ENTRY_CMD $II_PATH $II_LINE"
		else
			printf 'Cancelled.\n'
		fi
		;;
	cd)
		# The pickers return 1 to signal quit/EOF; the loop only acts on
		# II_QUIT, so the dispatch arm must not propagate that status
		# (the session runs under set -e).
		ii_pick_directory || true
		;;
	absorb-flow)
		ii_pick_absorb || true
		;;
	takeout-flow)
		ii_pick_takeout || true
		;;
	esac
}

# The interactive loop: startup banner, then menu -> input -> action,
# repeating until the user quits or stdin ends.
ii_run() {
	ii_resolve_git_nest
	help_setup_colors
	# Startup banner: run `git-nest version` through the same runner as
	# any action, so the version is shown and verified by the same path.
	ii_run_command version
	while :; do
		[ "$II_QUIT" -eq 1 ] && break
		II_CTX=$(ii_context)
		II_TABLE=$(ii_menu_for "$II_CTX")
		printf '\n'
		# Here-doc, not a pipe: the renderer must set II_MENU_COUNT in
		# this shell so the choice below can be validated against it.
		ii_menu_show <<EOF
$II_TABLE
EOF
		ii_read_line '> ' || break
		case "$(ii_parse_input "$II_LINE" "$II_MENU_COUNT")" in
		back)
			# The top-level menu has no previous menu to return to.
			printf 'You are already at the top-level menu.\n'
			;;
		quit) break ;;
		invalid) printf 'Unknown choice: %s\n' "$II_LINE" ;;
		run)
			ii_entry=$(printf '%s\n' "$II_TABLE" | ii_table_entry "$II_LINE")
			ii_exec_entry "$ii_entry"
			;;
		esac
	done
}

# Entry point: parse the internal testing switches, then run the loop.
cmd_interactive() {
	# Globals must exist before use because bin/git-nest runs with set -u.
	II_SCRIPTED=0
	II_TOKEN_FILE=
	II_TOKEN_POS=1
	II_QUIT=0
	II_MENU_COUNT=0
	II_TABLE=
	II_LINE=
	II_PATH=
	II_CTX=
	II_GIT_NEST=
	II_ENTRY_LABEL=
	II_ENTRY_KIND=
	II_ENTRY_CMD=
	while [ $# -gt 0 ]; do
		case "$1" in
		--ii-test)
			# Every remaining argument is one scripted input line; the
			# token file is a plain FIFO-less queue the reader walks.
			II_SCRIPTED=1
			II_TOKEN_FILE=$(mktemp 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/ii-tokens.$$")
			: >"$II_TOKEN_FILE"
			shift
			while [ $# -gt 0 ]; do
				case "$1" in
				--ii-skip)
					# --ii-skip may follow --ii-test; consume both words.
					[ $# -ge 2 ] || usage_error "--ii-skip requires a count"
					case "$2" in
					*[!0-9]* | '') usage_error "--ii-skip requires a number" ;;
					esac
					II_TOKEN_POS=$((II_TOKEN_POS + $2))
					shift 2
					;;
				*)
					printf '%s\n' "$1" >>"$II_TOKEN_FILE"
					shift
					;;
				esac
			done
			;;
		--ii-skip)
			# Drop the first n scripted tokens so a test can fast-forward
			# past steps a previous invocation already applied on disk.
			[ $# -ge 2 ] || usage_error "--ii-skip requires a count"
			case "$2" in
			*[!0-9]* | '') usage_error "--ii-skip requires a number" ;;
			esac
			II_TOKEN_POS=$((II_TOKEN_POS + $2))
			shift 2
			;;
		*)
			usage_error "interactive takes no arguments: $1"
			;;
		esac
	done
	if [ "$II_SCRIPTED" -eq 1 ]; then
		trap 'rm -f "$II_TOKEN_FILE"' EXIT INT TERM
	fi
	ii_run
}

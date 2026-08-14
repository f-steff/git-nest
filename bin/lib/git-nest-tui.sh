#!/bin/sh
#
# git-nest tui: a minimal pure-POSIX-shell terminal UI.
#
# The module is split into a testable "functional core" and a thin
# "imperative shell":
#
#   Pure functions (no TTY, no git -- unit-testable):
#     tui_key_normalize  byte sequence -> key token
#     tui_box            draw an ASCII box
#     tui_clip           truncate a line to a width
#     tui_wrap           wrap text to a width
#     tui_trim_help      extract the description block from `git-nest help`
#     tui_layout         terminal rows/cols -> pane rectangles
#     tui_menu_step      two-tier menu state machine
#     tui_input_step     single-line input buffer machine
#
#   Imperative shell (TTY/git -- integration-tested):
#     tui_read_key       stty raw + dd bs=1 single-byte read
#     cmd_tui            entry point: gate, then tui_run
#     tui_run            main loop: render -> read -> dispatch
#
# Rendering is ASCII-only (full printable set; no box-drawing Unicode).
# ANSI escapes are emitted via printf '\033' so this source stays ASCII.

# ---------------------------------------------------------------------------
# Key handling
# ---------------------------------------------------------------------------

# Map a raw byte sequence to a normalized key token. Takes up to three
# bytes as separate arguments (b1 [b2] [b3]); the ESC-prefixed sequences
# are two or three bytes long. Prints the token on stdout.
# Tokens: up down left right enter tab backtab esc ctrl_h ctrl_l ctrl_c
#         q printable:<char>
tui_key_normalize() {
	kb1=${1:-}
	kb2=${2:-}
	kb3=${3:-}
	esc=$(printf '\033')
	case "$kb1" in
	"$esc")
		case "$kb2$kb3" in
		'[A') echo up ;;
		'[B') echo down ;;
		'[C') echo right ;;
		'[D') echo left ;;
		'[Z') echo backtab ;;
		'') echo esc ;;
		*) echo "printable:$kb2" ;;
		esac
		;;
	"$(printf '\r')") echo enter ;;
	"$(printf '\t')") echo tab ;;
	"$(printf '\b')") echo ctrl_h ;;
	"$(printf '\f')") echo ctrl_l ;;
	"$(printf '\003')") echo ctrl_c ;;
	q | Q) echo q ;;
	*) echo "printable:$kb1" ;;
	esac
}

# Read one key from the terminal and print its normalized token. Handles
# multi-byte ESC sequences by polling with a short timeout (stty min 0
# time 1) so a lone ESC is distinguishable from an arrow key.
tui_read_key() {
	rk_b1=$(dd bs=1 count=1 2>/dev/null) || true
	[ -n "$rk_b1" ] || {
		echo none
		return
	}
	esc=$(printf '\033')
	if [ "$rk_b1" = "$esc" ]; then
		rk_b2=$(dd bs=1 count=1 2>/dev/null) || true
		if [ "$rk_b2" = '[' ]; then
			rk_b3=$(dd bs=1 count=1 2>/dev/null) || true
			tui_key_normalize "$rk_b1" "$rk_b2" "$rk_b3"
		else
			tui_key_normalize "$rk_b1" "$rk_b2"
		fi
	else
		tui_key_normalize "$rk_b1"
	fi
}

# ---------------------------------------------------------------------------
# ASCII rendering primitives
# ---------------------------------------------------------------------------

# Print a horizontal rule of the given width using the given character,
# WITHOUT a trailing newline (callers add it).
tui_rule() {
	ru_width=$1
	ru_char=${2:--}
	ru_i=0
	while [ "$ru_i" -lt "$ru_width" ]; do
		printf '%s' "$ru_char"
		ru_i=$((ru_i + 1))
	done
}

# Truncate a line to at most width characters (ASCII; no wide-char math).
tui_clip() {
	cl_width=$1
	cl_line=$2
	if [ "${#cl_line}" -gt "$cl_width" ]; then
		printf '%s\n' "$(printf '%s' "$cl_line" | cut -c1-"$cl_width")"
	else
		printf '%s\n' "$cl_line"
	fi
}

# Wrap text to a width, printing one line per paragraph line. Long words
# are hard-truncated (no reflow across words). A break at a space does not
# leave a leading space on the next line.
tui_wrap() {
	wr_width=$1
	wr_text=$2
	wr_rest=$wr_text
	while [ -n "$wr_rest" ]; do
		if [ "${#wr_rest}" -le "$wr_width" ]; then
			printf '%s\n' "$wr_rest"
			break
		fi
		wr_chunk=$(printf '%s' "$wr_rest" | cut -c1-"$wr_width")
		wr_next=$(printf '%s' "$wr_rest" | cut -c$((wr_width + 1))-)
		# If the chunk ends exactly at a word boundary (next char is a
		# space or the text ends), keep the whole chunk.
		case "$wr_next" in
		' '* | '')
			wr_head=$(printf '%s' "$wr_chunk" | sed 's/ *$//')
			printf '%s\n' "$wr_head"
			wr_rest=${wr_rest#"$wr_head"}
			case "$wr_rest" in
			' '*) wr_rest=${wr_rest# } ;;
			esac
			continue
			;;
		esac
		# The chunk cuts a word in half: back up to the last space inside
		# it (position of the last space, 0 = none).
		wr_sp=$(printf '%s' "$wr_chunk" | awk '{ p = match($0, / [^ ]*$/); print p ? p : 0 }')
		if [ "$wr_sp" -gt 1 ]; then
			wr_keep=$((wr_sp - 1))
			wr_head=$(printf '%s' "$wr_chunk" | cut -c1-"$wr_keep")
		else
			wr_head=$wr_chunk
		fi
		printf '%s\n' "$wr_head"
		wr_rest=${wr_rest#"$wr_head"}
		case "$wr_rest" in
		' '*) wr_rest=${wr_rest# } ;;
		esac
	done
}

# Draw a full ASCII box of the given inner height and width, with an
# optional title on the top border. Prints to stdout.
tui_box() {
	bx_height=$1
	bx_width=$2
	bx_title=${3:-}
	[ "$bx_width" -ge 4 ] || bx_width=4
	bx_i=0
	while [ "$bx_i" -lt "$bx_height" ]; do
		if [ "$bx_i" -eq 0 ]; then
			printf '+'
			if [ -n "$bx_title" ]; then
				printf '%s' "$bx_title"
				tui_rule $((bx_width - 2 - ${#bx_title})) -
			else
				tui_rule $((bx_width - 2)) -
			fi
			printf '+\n'
		elif [ "$bx_i" -eq $((bx_height - 1)) ]; then
			printf '+'
			tui_rule $((bx_width - 2)) -
			printf '+\n'
		else
			printf '|'
			tui_rule $((bx_width - 2)) ' '
			printf '|\n'
		fi
		bx_i=$((bx_i + 1))
	done
}

# ---------------------------------------------------------------------------
# Help text trimming
# ---------------------------------------------------------------------------

# Extract the "description + bullets" block from `git-nest help <cmd>`
# output: drop the title line, the usage line, and the Examples: section.
# Reads the help text on stdin; prints the trimmed block to stdout.
tui_trim_help() {
	th_skip=0
	th_seen=0
	while IFS= read -r th_line; do
		case "$th_line" in
		'git-nest help:'*) continue ;;
		'Latest version:'*) continue ;;
		'Examples:'*) break ;;
		'')
			# Keep the first blank line (separates usage from description).
			if [ "$th_seen" -eq 0 ]; then
				th_seen=1
			fi
			;;
		*)
			printf '%s\n' "$th_line"
			th_seen=1
			;;
		esac
	done
}

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

# Compute pane rectangles for the given terminal rows/cols. Prints four
# lines: header_rows, menu_rows, log_rows, desc_width. The menu pane and
# description pane share the middle rows; the log pane sits at the bottom.
tui_layout() {
	ly_rows=$1
	ly_cols=$2
	ly_header=1
	ly_log=$((ly_rows / 3))
	[ "$ly_log" -gt 5 ] || ly_log=5
	ly_mid=$((ly_rows - ly_header - ly_log))
	[ "$ly_mid" -gt 1 ] || ly_mid=1
	ly_desc=$((ly_cols / 3))
	[ "$ly_desc" -gt 20 ] || ly_desc=20
	printf '%s\n%s\n%s\n%s\n' "$ly_header" "$ly_mid" "$ly_log" "$ly_desc"
}

# ---------------------------------------------------------------------------
# Menu state machine (pure)
# ---------------------------------------------------------------------------

# The menu model: a list of items, a cursor index, and a level. Items are
# passed as newline-separated text via stdin. tui_menu_step takes the
# current state as "level cursor" plus a token and prints the new state.
tui_menu_step() {
	ms_level=$1
	ms_cursor=$2
	ms_token=$3
	# Count items from stdin.
	ms_count=0
	while IFS= read -r ms_item; do
		ms_count=$((ms_count + 1))
	done
	case "$ms_token" in
	up)
		[ "$ms_cursor" -gt 0 ] && ms_cursor=$((ms_cursor - 1))
		;;
	down)
		[ "$ms_cursor" -lt $((ms_count - 1)) ] && ms_cursor=$((ms_cursor + 1))
		;;
	esac
	printf '%s %s\n' "$ms_level" "$ms_cursor"
}

# ---------------------------------------------------------------------------
# Input strip state machine (pure)
# ---------------------------------------------------------------------------

# Single-line free-text input. Takes the current buffer and a token;
# prints the new buffer, or "DONE:<value>" when Enter commits, or
# "CANCEL" when ESC aborts.
tui_input_step() {
	is_buffer=$1
	is_token=$2
	case "$is_token" in
	enter) echo "DONE:$is_buffer" ;;
	esc) echo CANCEL ;;
	backspace)
		# Delete the last character.
		is_len=${#is_buffer}
		[ "$is_len" -gt 0 ] && is_buffer=$(printf '%s' "$is_buffer" | cut -c1-$((is_len - 1)))
		echo "$is_buffer"
		;;
	printable:*)
		is_ch=${is_token#printable:}
		echo "$is_buffer$is_ch"
		;;
	*) echo "$is_buffer" ;;
	esac
}

# ---------------------------------------------------------------------------
# Imperative shell: gate, render, main loop
# ---------------------------------------------------------------------------

# The class-1 zero-arg action menu (level 1). Each entry is "label|command".
TUI_ACTIONS="Status|status
Tree|tree
List|list
Survey|survey
Verify|verify
Outdated|outdated
Diff|diff
Doctor|doctor
Snapshot|snapshot
Pull|pull
Restore|restore
GC|gc
Freeze|freeze
Help|help"

# Path-taking actions (level 2 = subproject picker). class-2 entries carry
# "label|command" and run against the selected subproject; class-3 entries
# carry "label|command|input-prompt" and collect one free-text field.
TUI_PATH_ACTIONS="Snapshot|snapshot
Update|update|revision/tag/branch
Detach|detach
Remove|remove
Inline|inline
Add|add|repository URL
Move|move|new path
Export|export|output directory"

# Restore the terminal state saved at TUI start; also re-enable echo and the
# cursor, and reset colors. Idempotent.
tui_restore_terminal() {
	[ -n "$TUI_TTY_STATE" ] && stty "$TUI_TTY_STATE" 2>/dev/null || true
	TUI_TTY_STATE=
	printf '\033[0m\033[?25h'
}

# Install EXIT/INT/TERM/HUP traps that restore the terminal, so a killed TUI
# never leaves the user with a raw, echo-off terminal.
tui_install_traps() {
	trap 'tui_restore_terminal; exit 0' EXIT INT TERM HUP
}

# Gate: refuse to run unless stdin and stdout are real terminals, stty
# raw mode can be engaged, and we are NOT launched through the Windows
# Find the mintty launcher (git-bash.exe) that pairs with the running
# bash, so the graceful-exit hint can open a real terminal window. It
# lives at the MSYS root (e.g. C:\Program Files\Git\git-bash.exe);
# fall back to walking up from the running bash.
tui_find_git_bash() {
	if [ -f /git-bash.exe ]; then
		printf '/git-bash.exe\n'
		return 0
	fi
	fgb_dir=/usr/bin
	while :; do
		if [ -f "$fgb_dir/git-bash.exe" ]; then
			printf '%s\n' "$fgb_dir/git-bash.exe"
			return 0
		fi
		fgb_next=$(dirname "$fgb_dir")
		[ "$fgb_next" = "$fgb_dir" ] && break
		fgb_dir=$fgb_next
	done
	return 1
}

# Print the graceful-exit hint for the Windows-launcher case: the exact
# one-liner that opens Git Bash (mintty) in the current folder and runs
# the TUI, for the launcher that started git-nest (cmd or powershell).
# `git-bash.exe --cd=... -c ...` opens a real mintty window, so pasting
# the line into that host works.
#
# The command line is static except for --cd: the -c argument always runs
# a helper script at the FIXED name /tmp/git-nest-tui.sh (no PID), so the
# same line can be re-run any number of times. The helper:
#   - clears GIT_NEST_WIN_LAUNCHER, which the launcher session inherited
#     into mintty (otherwise the TUI gate would refuse again, rc=2);
#   - prefers git-nest on PATH, falling back to $PWD/bin/git-nest (the
#     checkout layout), where $PWD is the folder --cd landed in;
#   - keeps the window open after the TUI exits.
tui_win_hint() {
	th_launcher=$1
	th_dir=$(pwd 2>/dev/null || printf '.')
	if command -v cygpath >/dev/null 2>&1; then
		th_dir_w=$(cygpath -w "$th_dir" 2>/dev/null || printf '%s' "$th_dir")
	else
		th_dir_w=$th_dir
	fi
	th_bash=$(tui_find_git_bash || true)
	if [ -n "$th_bash" ]; then
		th_bash_w=$(command -v cygpath >/dev/null 2>&1 && cygpath -w "$th_bash" 2>/dev/null || printf '%s' "$th_bash")
		if [ -n "${TMPDIR:-}" ]; then
			th_tmp=$TMPDIR
		else
			th_tmp=/tmp
		fi
		th_script="$th_tmp/git-nest-tui.sh"
		{
			printf '#!/bin/sh\n'
			# The launcher env var leaks into mintty; the TUI gate would
			# refuse again. Clear it.
			printf 'unset GIT_NEST_WIN_LAUNCHER\n'
			# $PWD is the folder --cd landed in (the nest root).
			printf 'if command -v git-nest >/dev/null 2>&1; then\n'
			printf '    git-nest tui\n'
			printf 'else\n'
			printf '    "$PWD/bin/git-nest" tui\n'
			printf 'fi\n'
			printf 'rc=$?\n'
			printf 'echo\n'
			printf 'read -r -p "TUI exited (rc=$rc). Press Enter to close the window... " _\n'
			printf 'exit $rc\n'
		} >"$th_script"
		# The -c argument is interpreted by bash, so the helper path must
		# be the MSYS path (a Windows path with backslashes would be
		# mangled by bash escapes). git-bash.exe --cd puts us in the nest
		# folder.
		printf 'Please start it directly in Git Bash (mintty) using:\n' >&2
		case "$th_launcher" in
		cmd)
			printf '  "%s" --cd="%s" -c "sh %s"\n' "$th_bash_w" "$th_dir_w" "$th_script" >&2
			;;
		powershell | *)
			printf '  & "%s" --cd="%s" -c "sh %s"\n' "$th_bash_w" "$th_dir_w" "$th_script" >&2
			;;
		esac
	else
		printf 'Please start it directly in a Git Bash (mintty) window in %s and run: git-nest tui\n' "$th_dir_w" >&2
	fi
}

# cmd.exe / PowerShell launchers (which attach bash to the console, not
# mintty). Prints a message and exits cleanly.
tui_gate() {
	# The .bat / .ps1 launchers set this marker: bash is attached to the
	# Windows console where stty raw mode reports success but single-byte
	# key reads never return -- the TUI would spin. Refuse up front.
	if [ -n "${GIT_NEST_WIN_LAUNCHER:-}" ]; then
		# Best-effort: drop helper scripts from previous refused launches
		# that were never run (the mintty run deletes its own on exit).
		th_tmp=${TMPDIR:-/tmp}
		rm -f "$th_tmp"/git-nest-tui-*.sh 2>/dev/null || true
		echo "The git-nest tui cannot launch itself into a Git Bash (mintty) window when launched via the $GIT_NEST_WIN_LAUNCHER launcher." >&2
		tui_win_hint "$GIT_NEST_WIN_LAUNCHER"
		exit 2
	fi
	if [ ! -t 0 ] || [ ! -t 1 ]; then
		echo "git-nest tui needs an interactive terminal (stdin/stdout must be a TTY)." >&2
		exit 2
	fi
	if [ "${TERM:-}" = dumb ] || [ -z "${TERM:-}" ]; then
		echo "git-nest tui needs a real terminal (TERM is '$TERM')." >&2
		exit 2
	fi
	# Probe raw mode without leaving it on: save, engage, restore.
	TUI_TTY_STATE=$(stty -g 2>/dev/null) || {
		echo "git-nest tui cannot engage raw terminal mode here (no usable stty)." >&2
		echo "Run it from a Git Bash (mintty) window or a real POSIX terminal." >&2
		exit 2
	}
	if ! stty -echo -icanon min 0 time 1 2>/dev/null; then
		echo "git-nest tui cannot engage raw terminal mode here (stty failed)." >&2
		echo "Run it from a Git Bash (mintty) window or a real POSIX terminal." >&2
		[ -n "$TUI_TTY_STATE" ] && stty "$TUI_TTY_STATE" 2>/dev/null || true
		TUI_TTY_STATE=
		exit 2
	fi
	stty "$TUI_TTY_STATE" 2>/dev/null || true
	TUI_TTY_STATE=
}

# Fetch and cache the trimmed help description for one command. The result
# is stored in the shell variable named by the second argument.
tui_help_for() {
	th_cmd=$1
	th_var=$2
	[ -n "${TUI_GIT_NEST:-}" ] || tui_resolve_git_nest
	th_text=$("$TUI_GIT_NEST" help "$th_cmd" 2>/dev/null | tui_trim_help)
	th_trimmed=$(printf '%s\n' "$th_text" | sed -n '1,6p')
	eval "$th_var=\$th_trimmed"
}

# Render the menu + description panes side by side (one awk pass over the
# two cached pane texts). Emits the joined lines to stdout. Called only
# when the cursor or level changes, never per frame.
tui_panes_render() {
	pr_cols=$1
	pr_desc_w=$((pr_cols / 3))
	[ "$pr_desc_w" -gt 20 ] || pr_desc_w=20
	pr_menu_w=$((pr_cols - pr_desc_w - 3))
	pr_menu_file=$(mktemp 2>/dev/null || printf '%s' "$TMPDIR/tui-menu.$$")
	pr_desc_file=$(mktemp 2>/dev/null || printf '%s' "$TMPDIR/tui-desc.$$")
	tui_menu_text >"$pr_menu_file"
	tui_desc_text >"$pr_desc_file"
	awk -v mw="$pr_menu_w" -v dw="$pr_desc_w" '
		NR == FNR {
			menu[NR] = $0
			next
		}
		{
			desc[FNR] = $0
		}
		END {
			rows = (length(menu) > length(desc)) ? length(menu) : length(desc)
			for (i = 1; i <= rows; i++) {
				m = (i in menu) ? menu[i] : ""
				d = (i in desc) ? desc[i] : ""
				printf "%-*s| %-*s\n", mw, m, dw, d
			}
		}' "$pr_menu_file" "$pr_desc_file"
	rm -f "$pr_menu_file" "$pr_desc_file"
}

# Render the whole frame to stdout using ANSI cursor control, from cached
# pane/log text (recomputed only when the selection or log changes), so a
# steady-state frame costs one stty subprocess.
tui_render() {
	set -- $(stty size 2>/dev/null || printf '24 80')
	tr_rows=${1:-24}
	tr_cols=${2:-80}
	[ "$tr_rows" -gt 0 ] || tr_rows=24
	[ "$tr_cols" -gt 0 ] || tr_cols=80
	# Full clear + home.
	printf '\033[2J\033[H'
	# Header line.
	printf '\033[7m %s \033[0m\n' "git-nest tui  -  $TUI_ROOT  -  $TUI_COUNT subprojects"
	printf '%s\n' '  ^ arrowkeys move, Enter select, Tab focus, ^H help, ^L resize, ESC back, q quit'
	# Cached menu|description panes.
	printf '%s\n' "$TUI_PANE_TEXT"
	# Log pane at the bottom.
	printf '\n'
	printf '%s\n' "$TUI_LOG_TEXT"
}

# Produce the menu pane text: the active item list with the cursor marked.
tui_menu_text() {
	if [ "$TUI_LEVEL" -eq 1 ]; then
		tui_list_text "$TUI_ACTIONS" "$TUI_CURSOR"
	else
		tui_list_text "$TUI_SUBPROJECTS" "$TUI_CURSOR"
	fi
}

# Render a newline-separated item list with the cursor line prefixed ">".
tui_list_text() {
	lt_items=$1
	lt_cursor=$2
	lt_i=0
	printf '%s\n' "$lt_items" | while IFS= read -r lt_item; do
		lt_label=${lt_item%%|*}
		if [ "$lt_i" -eq "$lt_cursor" ]; then
			printf '> %s\n' "$lt_label"
		else
			printf '  %s\n' "$lt_label"
		fi
		lt_i=$((lt_i + 1))
	done
}

# Produce the description pane text for the currently highlighted item.
# Cached by command name: the help text never changes, and spawning
# `git-nest help` every frame is the single most expensive thing the
# render does on Windows.
tui_desc_text() {
	if [ "$TUI_LEVEL" -eq 1 ]; then
		dt_cmd=$(tui_current_action_command)
		[ -n "$dt_cmd" ] || return 0
		if [ "$TUI_DESC_KEY" != "1:$dt_cmd" ]; then
			tui_help_for "$dt_cmd" TUI_DESC_TEXT
			TUI_DESC_KEY="1:$dt_cmd"
		fi
		printf '%s\n' "$TUI_DESC_TEXT"
	else
		# Subproject picker: show the selected row's state from list --porcelain.
		dt_row=$(printf '%s\n' "$TUI_SUBPROJECTS" | sed -n "$((TUI_CURSOR + 1))p")
		printf 'Selected: %s\n' "${dt_row:-}"
	fi
}

# The command token for the current level-1 cursor position ("" if none).
tui_current_action_command() {
	dt_i=0
	printf '%s\n' "$TUI_ACTIONS" | while IFS= read -r dt_item; do
		if [ "$dt_i" -eq "$TUI_CURSOR" ]; then
			printf '%s\n' "${dt_item#*|}"
			return 0
		fi
		dt_i=$((dt_i + 1))
	done
}

# Render the log pane (the last N lines of the log buffer), padded to the
# given width. One awk pass; runs only when the log changes.
tui_log_render() {
	lr_cols=$1
	printf '%s\n' "$TUI_LOG" | awk -v n="$TUI_LOG_H" -v w="$lr_cols" '
		{ lines[NR] = $0 }
		END {
			first = NR - n + 1
			if (first < 1) first = 1
			for (i = first; i <= NR; i++) printf "%-*s\n", w, lines[i]
		}'
}

# Append text to the log buffer, capping its size with a single awk, and
# refresh the cached padded log text used by tui_render.
tui_log_append() {
	la_text=$1
	if [ -n "$TUI_LOG" ]; then
		TUI_LOG=$(printf '%s\n%s\n' "$TUI_LOG" "$la_text")
	else
		TUI_LOG=$la_text
	fi
	TUI_LOG=$(printf '%s\n' "$TUI_LOG" | awk -v n="$TUI_LOG_CAP" '
		{ lines[NR] = $0 }
		END {
			first = NR - n + 1
			if (first < 1) first = 1
			for (i = first; i <= NR; i++) print lines[i]
		}')
	TUI_LOG_TEXT=$(tui_log_render "$TUI_LOG_COLS")
}

# Run a git-nest command through a fresh instance and append its output
# (stdout+stderr) to the log, prefixed with "> git-nest ...".
tui_run_command() {
	rc_cmd=$1
	shift
	rc_label="git-nest $rc_cmd"
	for rc_a in "$@"; do
		rc_label="$rc_label $rc_a"
	done
	tui_log_append "> $rc_label"
	rc_out=$("$TUI_GIT_NEST" "$rc_cmd" "$@" 2>&1) || true
	tui_log_append "$rc_out"
}

# Resolve the git-nest executable. The launchers run git-nest-main.sh
# directly (bin/ is not on PATH there), so prefer the entrypoint adjacent
# to this module; fall back to the PATH command.
tui_resolve_git_nest() {
	if [ -x "$SCRIPT_DIR/git-nest" ]; then
		TUI_GIT_NEST="$SCRIPT_DIR/git-nest"
	elif command -v git-nest >/dev/null 2>&1; then
		TUI_GIT_NEST=git-nest
	else
		echo "git-nest tui cannot find the git-nest executable." >&2
		exit 3
	fi
}

# The main interactive loop. Assumes the gate passed and raw mode is on.
tui_run() {
	# Save terminal state, engage raw mode, install traps.
	TUI_TTY_STATE=$(stty -g 2>/dev/null) || TUI_TTY_STATE=
	stty -echo -icanon min 0 time 1 2>/dev/null || true
	tui_install_traps
	printf '\033[?25l'
	tui_resolve_git_nest

	TUI_LEVEL=1
	TUI_CURSOR=0
	TUI_DESC_KEY=
	TUI_DESC_TEXT=
	TUI_SUBPROJECTS=$("$TUI_GIT_NEST" list --porcelain 2>/dev/null | awk '{print $2"|"$2}' || true)
	TUI_COUNT=$(printf '%s\n' "$TUI_SUBPROJECTS" | grep -c . || true)
	TUI_ROOT=$(pwd)
	TUI_LOG_CAP=200
	TUI_LOG_H=6
	set -- $(stty size 2>/dev/null || printf '24 80')
	TUI_LOG_COLS=${2:-80}
	TUI_LOG=""
	TUI_LOG_TEXT=""
	tui_log_append "> git-nest version"
	tui_log_append "$("$TUI_GIT_NEST" version 2>&1 || true)"
	# Prefetch the first description so the first frame is not slowed by
	# spawning `git-nest help` (expensive on Windows).
	TUI_DESC_KEY=
	TUI_DESC_TEXT=
	tui_desc_text >/dev/null
	TUI_PANE_TEXT=
	tui_refresh_panes

	while :; do
		tui_render
		tui_key=$(tui_read_key)
		case "$tui_key" in
		q | ctrl_c) break ;;
		up | down)
			tui_menu_move "$tui_key"
			tui_refresh_panes
			;;
		enter)
			tui_select || break
			tui_refresh_panes
			;;
		tab | backtab)
			# Single pane set for now; focus cycling is a no-op stub.
			:
			;;
		esc)
			if [ "$TUI_LEVEL" -eq 2 ]; then
				TUI_LEVEL=1
				TUI_CURSOR=0
				tui_refresh_panes
			else
				break
			fi
			;;
		ctrl_l)
			# Re-measure the size and refresh the cached text.
			set -- $(stty size 2>/dev/null || printf '24 80')
			TUI_LOG_COLS=${2:-80}
			TUI_LOG_TEXT=$(tui_log_render "$TUI_LOG_COLS")
			tui_refresh_panes
			;;
		ctrl_h)
			tui_help_overlay
			tui_refresh_panes
			;;
		esac
	done
	tui_restore_terminal
}

# Recompute the cached side-by-side pane text from the current selection.
# Called only when the cursor/level/state changes, never per frame.
tui_refresh_panes() {
	set -- $(stty size 2>/dev/null || printf '24 80')
	TUI_PANE_TEXT=$(tui_panes_render "${2:-80}")
}

# Move the menu cursor (level-aware) by up/down.
tui_menu_move() {
	mm_dir=$1
	mm_count=$(printf '%s\n' "$TUI_ACTIONS" | grep -c . || true)
	[ "$TUI_LEVEL" -eq 2 ] && mm_count=$(printf '%s\n' "$TUI_SUBPROJECTS" | grep -c . || true)
	[ "$mm_count" -gt 0 ] || return 0
	if [ "$mm_dir" = up ]; then
		[ "$TUI_CURSOR" -gt 0 ] && TUI_CURSOR=$((TUI_CURSOR - 1))
	else
		[ "$TUI_CURSOR" -lt $((mm_count - 1)) ] && TUI_CURSOR=$((TUI_CURSOR + 1))
	fi
}

# Handle Enter on the current menu item: run class-1, descend into the
# picker for path-taking actions, or prompt for class-3 free text.
# Returns nonzero when the user wants to quit.
tui_select() {
	if [ "$TUI_LEVEL" -eq 1 ]; then
		sl_cmd=$(tui_current_action_command)
		case "$sl_cmd" in
		help)
			tui_help_overlay
			return 0
			;;
		snapshot | pull | restore | gc | freeze | status | tree | list | survey | verify | outdated | diff | doctor)
			tui_run_command "$sl_cmd"
			return 0
			;;
		esac
		# Otherwise: descend into the subproject picker for the action.
		if printf '%s\n' "$TUI_PATH_ACTIONS" | grep -q "^$sl_cmd|"; then
			TUI_LEVEL=2
			TUI_CURSOR=0
			TUI_ACTION=$sl_cmd
			return 0
		fi
		tui_run_command "$sl_cmd"
		return 0
	fi

	# Level 2: run the selected action against the selected subproject.
	sl_path=$(printf '%s\n' "$TUI_SUBPROJECTS" | sed -n "$((TUI_CURSOR + 1))p")
	sl_path=${sl_path%%|*}
	sl_action=${TUI_ACTION:-}
	sl_spec=$(printf '%s\n' "$TUI_PATH_ACTIONS" | grep "^$sl_action|" | head -n 1 || true)
	sl_input_prompt=$(printf '%s' "$sl_spec" | cut -d'|' -f3-)
	if [ -n "$sl_input_prompt" ]; then
		# Class 3: prompt for one free-text field.
		sl_value=$(tui_prompt "$sl_input_prompt")
		case "$sl_value" in
		CANCEL) return 0 ;;
		esac
		case "$sl_action" in
		add) tui_run_command add "$sl_value" "$sl_path" ;;
		move) tui_run_command move "$sl_path" "$sl_value" ;;
		update) tui_run_command update "$sl_path" --revision "$sl_value" ;;
		export) tui_run_command export --output "$sl_value" ;;
		*) tui_run_command "$sl_action" "$sl_path" "$sl_value" ;;
		esac
	else
		# Class 2: run against the selected subproject (with confirm for
		# destructive actions).
		case "$sl_action" in
		remove | detach | inline)
			sl_conf=$(tui_prompt "confirm $sl_action $sl_path [y/N]")
			case "$sl_conf" in
			y | Y | yes | YES) ;;
			*) return 0 ;;
			esac
			;;
		esac
		tui_run_command "$sl_action" "$sl_path"
	fi
	return 0
}

# Single-line free-text prompt. Prints the collected value, or CANCEL.
tui_prompt() {
	pr_label=$1
	pr_buffer=
	while :; do
		# Render a one-line prompt above the log pane.
		printf '\033[%d;1H\033[K%s: %s_\033[0m\n' "$((TUI_LOG_H + 3))" "$pr_label" "$pr_buffer"
		pr_key=$(tui_read_key)
		case "$pr_key" in
		enter)
			printf '\n'
			echo "$pr_buffer"
			return 0
			;;
		esc | ctrl_c)
			printf '\n'
			echo CANCEL
			return 0
			;;
		backspace)
			pr_len=${#pr_buffer}
			[ "$pr_len" -gt 0 ] && pr_buffer=$(printf '%s' "$pr_buffer" | cut -c1-$((pr_len - 1)))
			;;
		printable:*)
			pr_ch=${pr_key#printable:}
			pr_buffer="$pr_buffer$pr_ch"
			;;
		esac
	done
}

# Full-screen help overlay; any key dismisses it.
tui_help_overlay() {
	printf '\033[2J\033[H'
	printf 'git-nest tui - help\n'
	printf '%s\n' '==================='
	printf '%s\n' '  arrow keys  move the menu highlight'
	printf '%s\n' '  Enter       run the selected action'
	printf '%s\n' '  Tab         move pane focus (Shift-Tab: reverse)'
	printf '%s\n' '  Ctrl-H      toggle this help overlay'
	printf '%s\n' '  Ctrl-L      re-measure the terminal and redraw'
	printf '%s\n' '  ESC         back to the previous menu level (quit at top)'
	printf '%s\n' '  q / Ctrl-C  quit'
	printf '%s\n' '==================='
	printf '%s\n' 'Press any key to continue...'
	tui_read_key >/dev/null
	tui_render
}

# Command entry point: gate, then run the interactive loop.
cmd_tui() {
	[ $# -eq 0 ] || usage_error "usage: git-nest tui"
	tui_gate
	tui_run
}

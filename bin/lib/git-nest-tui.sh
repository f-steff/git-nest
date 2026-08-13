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

# Gate: refuse to run unless stdin and stdout are real terminals and stty
# raw mode can be engaged. Prints a one-line message and exits cleanly.
tui_gate() {
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
	th_text=$(git-nest help "$th_cmd" 2>/dev/null | tui_trim_help)
	th_trimmed=$(printf '%s\n' "$th_text" | sed -n '1,6p')
	eval "$th_var=\$th_trimmed"
}

# Render the whole frame to stdout using ANSI cursor control. Reads the
# terminal size fresh each frame (cheap), so Ctrl-L / resize reflows.
tui_render() {
	tr_rows=$(stty size 2>/dev/null | awk '{print $1}')
	tr_cols=$(stty size 2>/dev/null | awk '{print $2}')
	[ -n "$tr_rows" ] || tr_rows=24
	[ -n "$tr_cols" ] || tr_cols=80
	# Full clear + home.
	printf '\033[2J\033[H'
	# Header line.
	printf '\033[7m %s \033[0m\n' "git-nest tui  -  $TUI_ROOT  -  $TUI_COUNT subprojects"
	printf '%s\n' '  ^ arrowkeys move, Enter select, Tab focus, ^H help, ^L resize, ESC back, q quit'
	# Menu pane (left) + description pane (right).
	tr_mid=$((tr_rows - 2 - tr_log_h))
	[ "$tr_mid" -gt 6 ] || tr_mid=6
	tr_desc_w=$((tr_cols / 3))
	[ "$tr_desc_w" -gt 20 ] || tr_desc_w=20
	tr_menu_w=$((tr_cols - tr_desc_w - 3))
	# Build menu lines into a variable.
	tr_menu_text=$(tui_menu_text)
	tr_desc_text=$(tui_desc_text)
	printf '%s\n' "$tr_menu_text" | while IFS= read -r tr_line; do
		printf '%-*s' "$tr_menu_w" "$tr_line"
		printf '| '
		# Next description line (if any).
		tr_dl=$(printf '%s\n' "$tr_desc_text" | sed -n '1p')
		printf '%-*s\n' "$tr_desc_w" "$tr_dl"
		if [ -n "$tr_desc_text" ]; then
			tr_desc_text=$(printf '%s\n' "$tr_desc_text" | sed '1d')
		fi
	done
	# Log pane at the bottom.
	printf '\n'
	tui_log_render "$tr_cols"
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
tui_desc_text() {
	if [ "$TUI_LEVEL" -eq 1 ]; then
		dt_cmd=$(tui_current_action_command)
		[ -n "$dt_cmd" ] || return 0
		tui_help_for "$dt_cmd" dt_out
		printf '%s\n' "$dt_out"
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

# Render the log pane (the last N lines of the log buffer), full width.
tui_log_render() {
	lr_cols=$1
	lr_lines=$(printf '%s\n' "$TUI_LOG" | tail -n "$TUI_LOG_H")
	printf '%s\n' "$lr_lines" | while IFS= read -r lr_line; do
		printf '%-*s\n' "$lr_cols" "$lr_line"
	done
}

# Append text to the log buffer, capping its size.
tui_log_append() {
	la_text=$1
	if [ -n "$TUI_LOG" ]; then
		TUI_LOG=$(printf '%s\n%s\n' "$TUI_LOG" "$la_text")
	else
		TUI_LOG=$la_text
	fi
	TUI_LOG=$(printf '%s\n' "$TUI_LOG" | tail -n "$TUI_LOG_CAP")
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
	rc_out=$(git-nest "$rc_cmd" "$@" 2>&1) || true
	tui_log_append "$rc_out"
}

# The main interactive loop. Assumes the gate passed and raw mode is on.
tui_run() {
	# Save terminal state, engage raw mode, install traps.
	TUI_TTY_STATE=$(stty -g 2>/dev/null) || TUI_TTY_STATE=
	stty -echo -icanon min 0 time 1 2>/dev/null || true
	tui_install_traps
	printf '\033[?25l'

	TUI_LEVEL=1
	TUI_CURSOR=0
	TUI_SUBPROJECTS=$(git-nest list --porcelain 2>/dev/null | awk '{print $2"|"$2}' || true)
	TUI_COUNT=$(printf '%s\n' "$TUI_SUBPROJECTS" | grep -c . || true)
	TUI_ROOT=$(pwd)
	TUI_LOG_CAP=200
	TUI_LOG_H=6
	TUI_LOG=""
	tui_log_append "> git-nest version"
	tui_log_append "$(git-nest version 2>&1 || true)"

	while :; do
		tui_render
		tui_key=$(tui_read_key)
		case "$tui_key" in
		q | ctrl_c) break ;;
		up | down)
			tui_menu_move "$tui_key"
			;;
		enter)
			tui_select || break
			;;
		tab | backtab)
			# Single pane set for now; focus cycling is a no-op stub.
			:
			;;
		esc)
			if [ "$TUI_LEVEL" -eq 2 ]; then
				TUI_LEVEL=1
				TUI_CURSOR=0
			else
				break
			fi
			;;
		ctrl_l)
			# Re-measure happens in tui_render; force a redraw.
			:
			;;
		ctrl_h)
			tui_help_overlay
			;;
		esac
	done
	tui_restore_terminal
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
		enter) printf '\n'; echo "$pr_buffer"; return 0 ;;
		esc | ctrl_c) printf '\n'; echo CANCEL; return 0 ;;
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

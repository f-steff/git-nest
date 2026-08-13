#!/bin/sh
# Unit test: TUI pure functions (key normalization, box, wrap, clip, help trimming, layout, menu step, input step)
# Coverage: tui_key_normalize, tui_box, tui_clip, tui_wrap, tui_trim_help, tui_layout, tui_menu_step, tui_input_step, tui_rule

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-tui.sh"

esc=$(printf '\033')

# --- tui_key_normalize: single-byte keys ---
assert_eq "$(tui_key_normalize "$(printf '\r')")" "enter" "enter"
assert_eq "$(tui_key_normalize "$(printf '\t')")" "tab" "tab"
assert_eq "$(tui_key_normalize "$(printf '\b')")" "ctrl_h" "ctrl-h"
assert_eq "$(tui_key_normalize "$(printf '\f')")" "ctrl_l" "ctrl-l"
assert_eq "$(tui_key_normalize "$(printf '\003')")" "ctrl_c" "ctrl-c"
assert_eq "$(tui_key_normalize q)" "q" "lowercase q"
assert_eq "$(tui_key_normalize Q)" "q" "uppercase Q"
assert_eq "$(tui_key_normalize x)" "printable:x" "printable char"

# --- tui_key_normalize: ESC sequences ---
assert_eq "$(tui_key_normalize "$esc" '[' A)" "up" "arrow up"
assert_eq "$(tui_key_normalize "$esc" '[' B)" "down" "arrow down"
assert_eq "$(tui_key_normalize "$esc" '[' C)" "right" "arrow right"
assert_eq "$(tui_key_normalize "$esc" '[' D)" "left" "arrow left"
assert_eq "$(tui_key_normalize "$esc" '[' Z)" "backtab" "shift-tab (backtab)"
assert_eq "$(tui_key_normalize "$esc")" "esc" "lone ESC"
assert_eq "$(tui_key_normalize "$esc" '[' X)" "printable:[" "unknown ESC sequence falls back to printable"

# --- tui_box: draws a frame with a title ---
box_out=$(tui_box 3 12 "Title")
box_first=$(printf '%s\n' "$box_out" | sed -n '1p')
box_last=$(printf '%s\n' "$box_out" | sed -n '3p')
assert_eq "$box_first" "+Title-----+" "top border carries the title (12 cols)"
assert_eq "$box_last" "+----------+" "bottom border closes the frame"

# --- tui_clip: truncates long lines, keeps short ones ---
assert_eq "$(tui_clip 4 abcdef)" "abcd" "truncates to width"
assert_eq "$(tui_clip 8 ab)" "ab" "short line passes through"

# --- tui_wrap: breaks at spaces and hard-truncates long words ---
wrap_out=$(tui_wrap 7 "one two three four")
assert_eq "$(printf '%s\n' "$wrap_out" | sed -n '1p')" "one two" "first wrapped line"
assert_eq "$(printf '%s\n' "$wrap_out" | sed -n '2p')" "three" "second wrapped line"
assert_eq "$(printf '%s\n' "$wrap_out" | sed -n '3p')" "four" "third wrapped line"
long_word=$(tui_wrap 5 "abcdefghij")
assert_eq "$(printf '%s\n' "$long_word" | sed -n '1p')" "abcde" "long word hard-truncated"
assert_eq "$(printf '%s\n' "$long_word" | sed -n '2p')" "fghij" "remainder wraps to the next line"

# --- tui_trim_help: drops title/usage/blank header, keeps description ---
help_text=$(printf 'git-nest help: status\n\nLatest version: ...\n\n    status [opts]\n        Show nest root and subproject state.\n            bullet one\nExamples:\n    git-nest status\n' | tui_trim_help)
assert_eq "$(printf '%s\n' "$help_text" | sed -n '1p')" "    status [opts]" "usage line kept"
assert_eq "$(printf '%s\n' "$help_text" | sed -n '2p')" "        Show nest root and subproject state." "description kept"
assert_eq "$(printf '%s\n' "$help_text" | sed -n '3p')" "            bullet one" "detail bullet kept"
if printf '%s\n' "$help_text" | grep -q "Examples:"; then
    echo "UNEXPECTED RESULT: tui_trim_help kept the Examples: heading" >&2
    exit 1
fi

# --- tui_layout: returns four numbers ---
layout_out=$(tui_layout 24 80)
assert_eq "$(printf '%s\n' "$layout_out" | sed -n '1p')" "1" "header rows"
assert_eq "$(printf '%s\n' "$layout_out" | sed -n '3p')" "8" "log rows for 24-row terminal"
assert_eq "$(printf '%s\n' "$layout_out" | sed -n '4p')" "26" "description width for 80 columns"

# --- tui_menu_step: clamps the cursor ---
assert_eq "$(printf 'a\nb\nc\n' | tui_menu_step 1 1 down)" "1 2" "move down"
assert_eq "$(printf 'a\nb\nc\n' | tui_menu_step 1 0 up)" "1 0" "move up at top stays"
assert_eq "$(printf 'a\nb\nc\n' | tui_menu_step 1 2 down)" "1 2" "move down at bottom stays"

# --- tui_input_step: buffer machine ---
assert_eq "$(tui_input_step "" "printable:h")" "h" "append char"
assert_eq "$(tui_input_step "h" "printable:i")" "hi" "append second char"
assert_eq "$(tui_input_step "hi" backspace)" "h" "backspace deletes last char"
assert_eq "$(tui_input_step "" backspace)" "" "backspace on empty buffer is a no-op"
assert_eq "$(tui_input_step "hi" enter)" "DONE:hi" "enter commits"
assert_eq "$(tui_input_step "hi" esc)" "CANCEL" "esc cancels"

printf 'All tests passed.\n'

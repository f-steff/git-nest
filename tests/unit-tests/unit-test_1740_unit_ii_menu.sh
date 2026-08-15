#!/bin/sh
# Unit test: interactive menu input parsing and rendering (ii_parse_input,
# ii_menu_show, ii_table_entry, ii_menu_for).
# Coverage: ii_parse_input, ii_menu_show, ii_table_entry, ii_menu_for

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-ii.sh"

# --- ii_parse_input: choice tokens ---
assert_eq "$(ii_parse_input 1 5)" "run" "first entry"
assert_eq "$(ii_parse_input 5 5)" "run" "last entry"
assert_eq "$(ii_parse_input 6 5)" "invalid" "beyond menu count"
assert_eq "$(ii_parse_input 0 5)" "invalid" "zero is not an entry"
assert_eq "$(ii_parse_input b 5)" "back" "b goes back"
assert_eq "$(ii_parse_input q 5)" "quit" "q quits"
assert_eq "$(ii_parse_input '' 5)" "back" "empty line goes back"
assert_eq "$(ii_parse_input abc 5)" "invalid" "text is invalid"
assert_eq "$(ii_parse_input 1000 5)" "invalid" "four digits are rejected"
assert_eq "$(ii_parse_input 123 999)" "run" "three-digit entries are allowed"

# --- ii_menu_show: right-aligned numbers, padded labels, footer ---
table=':Nest setup
git init|run|git init|Initialize a Git repository in this folder
version|run|version|Show the git-nest version'

ii_menu_show <<EOF >menu_out.txt
$table
EOF

assert_eq "$(sed -n '1p' menu_out.txt)" "Nest setup" "group heading printed plain (no color in tests)"
assert_eq "$(sed -n '2p' menu_out.txt)" "  1. git init - Initialize a Git repository in this folder" "first entry right-aligned"
assert_eq "$(sed -n '3p' menu_out.txt)" "  2. version  - Show the git-nest version" "second entry aligned to first"
assert_eq "$(sed -n '4p' menu_out.txt)" "  b. back     - Return to the previous menu" "back footer in the same gutter"
assert_eq "$(sed -n '5p' menu_out.txt)" "  q. quit     - Exit git-nest interactive" "quit footer in the same gutter"
assert_eq "$II_MENU_COUNT" "2" "entry count excludes headings"

# --- ii_menu_show: 10+ entries keep the units column aligned ---
many=
i=1
while [ "$i" -le 10 ]; do
    many="$many
item-$i|run|item-$i|entry"
    i=$((i + 1))
done
ii_menu_show <<EOF >menu_wide_out.txt
$many
EOF
assert_eq "$(sed -n '1p' menu_wide_out.txt)" "  1. item-1  - entry" "units column at one digit"
assert_eq "$(sed -n '10p' menu_wide_out.txt)" " 10. item-10 - entry" "tens digit right-aligned under the units column"

# --- ii_table_entry: skips headings and blank lines ---
assert_eq "$(printf '%s\n' "$table" | ii_table_entry 1)" "git init|run|git init|Initialize a Git repository in this folder" "first entry past the heading"
assert_eq "$(printf '%s\n' "$table" | ii_table_entry 2)" "version|run|version|Show the git-nest version" "second entry"

# --- ii_menu_for: context selects the right table ---
none_menu=$(ii_menu_for none)
git_menu=$(ii_menu_for git-only)
nest_menu=$(ii_menu_for nest)
printf '%s\n' "$none_menu" | grep -q '^git init|run|git init|' || {
    printf 'UNEXPECTED RESULT: virgin menu must offer the real git init\n' >&2
    exit 1
}
printf '%s\n' "$none_menu" | grep -q '|run|init|' && {
    printf 'UNEXPECTED RESULT: virgin menu must not offer git-nest init\n' >&2
    exit 1
}
printf '%s\n' "$git_menu" | grep -q '^git-nest init|run|init|' || {
    printf 'UNEXPECTED RESULT: git-only menu must offer git-nest init\n' >&2
    exit 1
}
printf '%s\n' "$git_menu" | grep -q '^git init|' && {
    printf 'UNEXPECTED RESULT: git-only menu must not offer git init\n' >&2
    exit 1
}
printf '%s\n' "$nest_menu" | grep -q '^status|run|status|' || {
    printf 'UNEXPECTED RESULT: nest menu must offer status\n' >&2
    exit 1
}
printf '%s\n' "$nest_menu" | grep -q '^tidy|run|tidy|' || {
    printf 'UNEXPECTED RESULT: nest menu must offer tidy\n' >&2
    exit 1
}
printf '%s\n' "$nest_menu" | grep -q '^bring in (absorb)|absorb-flow|' || {
    printf 'UNEXPECTED RESULT: nest menu must offer the bring-in flow\n' >&2
    exit 1
}
printf '%s\n' "$nest_menu" | grep -q '^take out (inline/detach/remove)|takeout-flow|' || {
    printf 'UNEXPECTED RESULT: nest menu must offer the take-out flow\n' >&2
    exit 1
}
for gone in '^absorb|text|' '^absorb-all|run|' '^inline|path|' '^detach|path|' '^remove|path|'; do
    printf '%s\n' "$nest_menu" | grep -q "$gone" && {
        printf 'UNEXPECTED RESULT: standalone membership entries must be folded into the flows (%s)\n' "$gone" >&2
        exit 1
    }
done
for menu in "$none_menu" "$git_menu" "$nest_menu"; do
    printf '%s\n' "$menu" | grep -q '^change directory|cd|' || {
        printf 'UNEXPECTED RESULT: every menu must offer directory navigation\n' >&2
        exit 1
    }
done

printf 'All tests passed.\n'

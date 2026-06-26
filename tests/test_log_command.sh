#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin log_command

commit_with_date() {
    repo=$1
    file=$2
    text=$3
    message=$4
    date=$5
    (cd "$repo" && git_config)
    printf '%s\n' "$text" >>"$repo/$file"
    git -C "$repo" add "$file"
    GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" git -C "$repo" commit -m "$message" >/dev/null
}

root=$(test_workspace log_command)
remote_one="$root/remotes/one.git"
remote_two="$root/remotes/two.git"
seed_one="$root/seed/one"
seed_two="$root/seed/two"
outer="$root/outer"

mkdir -p "$root/remotes" "$root/seed"
make_bare_remote "$remote_one" "$seed_one"
make_bare_remote "$remote_two" "$seed_two"
make_repo "$outer"

cd "$outer"
"$GIT_STACK" init >/dev/null
"$GIT_STACK" add "$remote_one" libs/one >/dev/null
"$GIT_STACK" add "$remote_two" libs/two >/dev/null
(cd "$outer" && git_config)
git add .stack .gitignore
GIT_AUTHOR_DATE="2030-01-01T00:00:00+0000" GIT_COMMITTER_DATE="2030-01-01T00:00:00+0000" \
    git commit -m "LOG-100 outer baseline" >/dev/null

commit_with_date "$outer/libs/one" file.txt "one" "LOG-101 module one" "2030-01-02T00:00:00+0000"
commit_with_date "$outer/libs/two" file.txt "two" "LOG-102 module two" "2030-01-03T00:00:00+0000"

"$GIT_STACK" log --max-count 3 >log.out
sed -n '1p' log.out >first.txt
sed -n '2p' log.out >second.txt
sed -n '3p' log.out >third.txt
assert_file_contains first.txt "libs/two"
assert_file_contains first.txt "LOG-102 module two"
assert_file_contains second.txt "libs/one"
assert_file_contains second.txt "LOG-101 module one"
assert_file_contains third.txt "."
assert_file_contains third.txt "LOG-100 outer baseline"

"$GIT_STACK" log --max-count 1 --oneline >oneline.out
assert_file_contains oneline.out "libs/two"
assert_file_contains oneline.out "LOG-102 module two"

"$GIT_STACK" log --module . --max-count 5 >module_root.out
assert_file_contains module_root.out "LOG-100 outer baseline"
assert_file_not_contains module_root.out "libs/one"
assert_file_not_contains module_root.out "libs/two"

"$GIT_STACK" log --module libs/one --max-count 5 >module_one.out
assert_file_contains module_one.out "libs/one"
assert_file_contains module_one.out "LOG-101 module one"
assert_file_not_contains module_one.out "libs/two"

"$GIT_STACK" log --since "2030-01-02T12:00:00+0000" --max-count 5 >since.out
assert_file_contains since.out "LOG-102 module two"
assert_file_not_contains since.out "LOG-101 module one"
assert_file_not_contains since.out "LOG-100 outer baseline"

rm -rf libs/two
"$GIT_STACK" log --module libs/two >missing.out 2>missing.err
assert_file_contains missing.err "Warning: missing repository for log: libs/two"

if "$GIT_STACK" log --max-count 0 >bad_count.out 2>bad_count.err; then
    echo "log should reject invalid max-count" >&2
    exit 1
fi
assert_file_contains bad_count.err "Error: --max-count must be a positive integer"

if "$GIT_STACK" log --bad-option >bad_option.out 2>bad_option.err; then
    echo "log should reject unknown options" >&2
    exit 1
fi
assert_file_contains bad_option.err "Error: unknown log option"

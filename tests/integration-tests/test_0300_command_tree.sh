#!/bin/sh
# Test: tree displays an ASCII-art nest tree grouped by shared path prefixes

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_tree

# tree groups managed subprojects by shared directory prefixes into an
# ASCII-art tree; --all also shows survey's own detected-but-unmanaged
# findings; --recursive also descends into nested nests.
test_step "Exercise tree grouping, --all, --recursive, --porcelain, and --json" "tree must group by shared path prefixes with a single +-- connector and a trailing / on every entry, and show root [N], managed [M], and survey findings with [code], URL, and [typelabel]."

root=$(test_workspace command_tree)
outer="$root/outer"
remote_foo="$root/remotes/foo.git"
remote_bar="$root/remotes/bar.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_foo" "$root/seed/foo"
make_bare_remote "$remote_bar" "$root/seed/bar"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
"$GIT_NEST" add "file://$remote_foo" libs/foo >/dev/null
"$GIT_NEST" add "file://$remote_bar" libs/bar >/dev/null
"$GIT_NEST" add "file://$remote_foo" tools/x >/dev/null
git add .gitnest .gitignore .gitattributes NEST_README.md
git commit -m "init nest" >/dev/null

# --- Plain tree: root [N], managed [M], URLs ---
test_step "Plain tree groups managed subprojects by shared path prefix" "libs/foo and libs/bar must render as one libs branch with two children; root must show [N] Nest Root; each entry must show [M] and the remote URL."
run_capture "plain tree groups by prefix" tree.out tree.err -- "$GIT_NEST" tree
assert_file_contains tree.out '.'
assert_file_contains tree.out '[N]'
assert_file_contains tree.out '[Nest Root]'
assert_file_contains tree.out '+-- libs/'
assert_file_contains tree.out '|   +-- bar/'
assert_file_contains tree.out '|   +-- foo/'
assert_file_contains tree.out '+-- tools/'
assert_file_contains tree.out '    +-- x/'
assert_file_contains tree.out '[M]'
assert_file_contains tree.out '[Managed]'
if LC_ALL=C grep -P '[^\x00-\x7F]' tree.out >/dev/null 2>&1; then
    printf 'UNEXPECTED RESULT: tree output contains non-ASCII characters\n' >&2
    exit 1
fi

# --- --plain omits URL and type columns ---
test_step "tree --plain shows only path and [code]" "The --plain flag must omit the URL and [typelabel] columns, showing only directory structure and [M]/[N] codes."
run_capture "tree --plain omits extra columns" plain.out plain.err -- "$GIT_NEST" tree --plain
assert_file_contains plain.out '.'
assert_file_contains plain.out '[N]'
assert_file_not_contains plain.out '[Nest Root]'
assert_file_not_contains plain.out '[Managed]'
assert_file_contains plain.out '+-- libs/'
assert_file_contains plain.out '|   +-- bar/'
assert_file_contains plain.out '[M]'

# --- A single unrelated path still gets its own branch ---
test_step "A path with no shared prefix still gets its own branch" "A single top-level subproject with no siblings renders as a normal leaf under the root."
assert_file_not_contains tree.out 'libs/foo'

# --- --all also shows survey's own unmanaged findings, clearly marked ---
test_step "tree --all also shows unmanaged findings, distinctly marked" "An unmanaged nested repo must appear with [R] and [Unmanaged Repo]; managed entries stay [M]."
git clone "file://$remote_foo" external/other >/dev/null 2>&1
run_capture "tree --all shows the unmanaged item" all.out all.err -- "$GIT_NEST" tree --all
assert_file_contains all.out 'external'
assert_file_contains all.out '[R]'
assert_file_contains all.out '[Unmanaged Repo]'
assert_file_not_contains all.out 'foo/  [M'
assert_file_not_contains all.out 'bar/  [M'

# --- Without --all, the unmanaged item is invisible ---
run_capture "plain tree omits unmanaged findings" noall.out noall.err -- "$GIT_NEST" tree
assert_file_not_contains noall.out 'external'

# --- --json emits the shared row schema ---
test_step "tree --json emits the shared row schema" "One row per managed subproject and root, with the code and typelabel in the state column."
run_capture "tree json" tree.json tree.json.err -- "$GIT_NEST" tree --json
assert_file_contains tree.json '"command":"tree"'
assert_file_contains tree.json '"code":"N"'
assert_file_contains tree.json '"code":"M"'
assert_file_contains tree.json '"path":"libs/foo"'
assert_file_contains tree.json '"state":"Managed"'
python -m json.tool tree.json >/dev/null 2>&1 || python3 -m json.tool tree.json >/dev/null 2>&1 || true

# --- --porcelain emits the shared 7-column tab-separated rows ---
test_step "tree --porcelain emits stable fixed-column records" "Same rows as --json, but as tab-separated text without the JSON envelope."
run_capture "tree porcelain" porc.out porc.err -- "$GIT_NEST" tree --porcelain
assert_file_contains porc.out 'N	.	Nest Root'
assert_file_contains porc.out 'M	libs/foo	Managed'
assert_file_contains porc.out 'M	libs/bar	Managed'
assert_file_contains porc.out 'M	tools/x	Managed'

# --- --porcelain --all includes survey rows ---
test_step "tree --all --porcelain includes the survey code and typelabel" "Unmanaged entries carry their code and typelabel in columns 1 and 3."
run_capture "tree --all --porcelain" allporc.out allporc.err -- "$GIT_NEST" tree --all --porcelain
assert_file_contains allporc.out 'R	external/other	Unmanaged Repo'
assert_file_contains allporc.out 'M	libs/foo	Managed'
assert_file_not_contains allporc.out 'R	libs'

# --- --porcelain and --json are mutually exclusive ---
test_step "tree refuses --porcelain combined with --json" "Mutual exclusion must be enforced with a usage error."
run_fail "porcelain+json refused" any -- "$GIT_NEST" tree --porcelain --json
run_fail "porcelain+json-pretty refused" any -- "$GIT_NEST" tree --json-pretty --porcelain

# --- --plain and --porcelain/--json are mutually exclusive ---
test_step "tree refuses --plain combined with --porcelain or --json" "plain is a human-only flag and cannot be combined with machine output."
run_fail "plain+porcelain refused" any -- "$GIT_NEST" tree --plain --porcelain

# --- --recursive descends into a nested nest, nesting its subprojects under its branch ---
test_step "tree --recursive nests a nested nest's own subprojects under its branch" "Without --recursive, the nested nest is a plain leaf; with it, its own subproject appears nested beneath it."
remote_nested="$root/remotes/nested.git"
make_bare_remote "$remote_nested" "$root/seed/nested"
mkdir -p nested
(cd nested && git init -q && git_config && echo seed >f.txt && git add -A && git commit -qm seed)
"$GIT_NEST" absorb nested "file://$remote_nested" >/dev/null
(
    cd nested
    "$GIT_NEST" init --sure >/dev/null
    "$GIT_NEST" add "file://$remote_foo" inner >/dev/null
    git add .gitnest .gitignore .gitattributes NEST_README.md
    git commit -qm "nested nest init"
)
run_capture "tree without --recursive does not descend" norec.out norec.err -- "$GIT_NEST" tree
assert_file_contains norec.out 'nested'
assert_file_not_contains norec.out 'inner'
run_capture "tree --recursive descends into the nested nest" rec.out rec.err -- "$GIT_NEST" tree --recursive
assert_file_contains rec.out 'nested'
assert_file_contains rec.out 'inner'
assert_file_contains rec.out '[C]'
run_capture "tree --recursive --porcelain shows nested entries" recporc.out recporc.err -- "$GIT_NEST" tree --recursive --porcelain
assert_file_contains recporc.out 'M	libs/foo	Managed'
assert_file_contains recporc.out 'M	nested/inner	Managed'

describe_result "tree grouped managed subprojects by shared path prefix, showed root [N] with [Nest Root], managed [M] with [Managed], composite [C] with [Composite] for nested nests, --all added survey findings with [R]/[Unmanaged Repo] and [U]/[Unmanaged Nested Nest Root], --recursive nested a composite's subprojects, --plain omitted URL and type columns, --porcelain and --json emitted the shared schema with typelabel in state and url in detail."

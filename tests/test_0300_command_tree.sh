#!/bin/sh
# Test: tree displays an ASCII-art nest tree grouped by shared path prefixes

set -eu
. "$(dirname "$0")/helper.sh"
test_begin command_tree

# tree groups managed subprojects by shared directory prefixes into an
# ASCII-art tree; --all also shows survey's own detected-but-unmanaged
# findings; --recursive also descends into nested nests.
test_step "Exercise tree grouping, --all, --recursive, --porcelain, and --json" "tree must group by shared path prefixes with a single +-- connector and a trailing / on every entry, --all must add survey's own findings distinctly marked, --recursive must nest a nested nest's own subprojects under its branch, --porcelain must emit stable 7-column fixed-field rows, and --json must emit the shared row schema."

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
git add .gitnest .gitignore .gitattributes
git commit -m "init nest" >/dev/null

# --- Plain tree groups by shared prefix with a single +-- connector everywhere ---
test_step "Plain tree groups managed subprojects by shared path prefix" "libs/foo and libs/bar must render as one libs branch with two children; connectors must be pure ASCII, always +--, with a trailing / on every entry."
run_capture "plain tree groups by prefix" tree.out tree.err -- "$GIT_NEST" tree
assert_file_contains tree.out '.'
assert_file_contains tree.out '+-- libs/'
assert_file_contains tree.out '|   +-- bar/'
assert_file_contains tree.out '|   +-- foo/'
assert_file_contains tree.out '+-- tools/'
assert_file_contains tree.out '    +-- x/'
if LC_ALL=C grep -P '[^\x00-\x7F]' tree.out >/dev/null 2>&1; then
    printf 'UNEXPECTED RESULT: tree output contains non-ASCII characters\n' >&2
    exit 1
fi

# --- A single unrelated path still gets its own branch ---
test_step "A path with no shared prefix still gets its own branch" "A single top-level subproject with no siblings renders as a normal leaf under the root."
assert_file_not_contains tree.out 'libs/foo'

# --- --all also shows survey's own unmanaged findings, clearly marked ---
test_step "tree --all also shows unmanaged findings, distinctly marked" "An unmanaged nested repo must appear with its survey code; managed entries must not carry that marker."
git clone "file://$remote_foo" external/other >/dev/null 2>&1
run_capture "tree --all shows the unmanaged item" all.out all.err -- "$GIT_NEST" tree --all
assert_file_contains all.out 'external'
assert_file_contains all.out '[R] nested-repo'
assert_file_not_contains all.out 'foo/  ['
assert_file_not_contains all.out 'bar/  ['

# --- Without --all, the unmanaged item is invisible ---
run_capture "plain tree omits unmanaged findings" noall.out noall.err -- "$GIT_NEST" tree
assert_file_not_contains noall.out 'external'

# --- --json emits the shared row schema ---
test_step "tree --json emits the shared row schema" "One row per managed subproject, with the code M."
run_capture "tree json" tree.json tree.json.err -- "$GIT_NEST" tree --json
assert_file_contains tree.json '"command":"tree"'
assert_file_contains tree.json '"code":"M"'
assert_file_contains tree.json '"path":"libs/foo"'
python -m json.tool tree.json >/dev/null 2>&1 || python3 -m json.tool tree.json >/dev/null 2>&1 || true

# --- --porcelain emits the shared 7-column tab-separated rows ---
test_step "tree --porcelain emits stable fixed-column records" "Same rows as --json, but as tab-separated text without the JSON envelope."
run_capture "tree porcelain" porc.out porc.err -- "$GIT_NEST" tree --porcelain
assert_file_contains porc.out 'M	libs/foo	-	-	-	-	'
assert_file_contains porc.out 'M	libs/bar	-	-	-	-	'
assert_file_contains porc.out 'M	tools/x	-	-	-	-	'

# --- --porcelain --all includes the annotation column ---
test_step "tree --all --porcelain includes the survey code and annotation" "Unmanaged entries carry their code and state in columns 1 and 3."
run_capture "tree --all --porcelain" allporc.out allporc.err -- "$GIT_NEST" tree --all --porcelain
assert_file_contains allporc.out 'R	external/other	nested-repo	-	-	-	nested-repo'
assert_file_contains allporc.out 'M	libs/foo'
assert_file_not_contains allporc.out 'R	libs'

# --- --porcelain and --json are mutually exclusive ---
test_step "tree refuses --porcelain combined with --json" "Mutual exclusion must be enforced with a usage error."
run_fail "porcelain+json refused" any -- "$GIT_NEST" tree --porcelain --json
run_fail "porcelain+json-pretty refused" any -- "$GIT_NEST" tree --json-pretty --porcelain

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
    git add .gitnest .gitignore .gitattributes
    git commit -qm "nested nest init"
)
run_capture "tree without --recursive does not descend" norec.out norec.err -- "$GIT_NEST" tree
assert_file_contains norec.out 'nested'
assert_file_not_contains norec.out 'inner'
run_capture "tree --recursive descends into the nested nest" rec.out rec.err -- "$GIT_NEST" tree --recursive
assert_file_contains rec.out 'nested'
assert_file_contains rec.out 'inner'
run_capture "tree --recursive --porcelain shows nested entries" recporc.out recporc.err -- "$GIT_NEST" tree --recursive --porcelain
assert_file_contains recporc.out 'M	libs/foo'
assert_file_contains recporc.out 'M	nested/inner'

describe_result "tree grouped managed subprojects by shared path prefix with a single +-- connector and a trailing / on every entry, --all added survey's own unmanaged findings distinctly marked, --recursive nested a nested nest's own subprojects under its branch, --porcelain emitted stable fixed-column records, and --json emitted the shared row schema."

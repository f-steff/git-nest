#!/bin/sh
# Test: survey and absorb never cross submodule/subrepo/subtree boundaries

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_survey_boundary_enforcement

# Nested-repository, submodule, subrepo, and subtree boundaries are impossible
# to cross by design: once a path is inside one of these, it belongs to that
# inner repository exclusively. This is a critical, dedicated test (not just
# incidental coverage elsewhere).
test_step "Exercise boundary enforcement across submodule, subrepo, and subtree shapes" "A nested repo inside a submodule or subrepo must never be reported by survey as an independent top-level finding; a subtree has no detectable marker, so the actual protection there is absorb's own untracked-files guard refusing to swallow it."

root=$(test_workspace contract_survey_boundary_enforcement)
outer="$root/outer"
remote_foo="$root/remotes/foo.git"
remote_sub="$root/remotes/sub.git"
remote_inner="$root/remotes/inner.git"

mkdir -p "$root/remotes"
make_bare_remote "$remote_foo" "$root/seed/foo"
make_bare_remote "$remote_sub" "$root/seed/sub"
make_bare_remote "$remote_inner" "$root/seed/inner"
make_repo "$outer"

cd "$outer"
"$GIT_NEST" init >/dev/null
git add .gitnest .gitignore .gitattributes
git commit -m "init nest" >/dev/null

# --- Boundary 1: a nested repo inside a submodule ---
test_step "A nested repo inside a submodule is not reported as independent" "Only the submodule boundary itself is a first-class finding; anything found underneath belongs to it."
git -c protocol.file.allow=always submodule add "file://$remote_sub" components/sub >/dev/null 2>&1
git commit -m "add submodule" >/dev/null
git clone "file://$remote_inner" components/sub/inner >/dev/null 2>&1
run_capture "survey reports the submodule and the bounded inner repo" sub.out sub.err -- "$GIT_NEST" survey --porcelain
assert_file_contains sub.out 'S	components/sub	submodule'
assert_file_contains sub.out 'components/sub/inner	nested-repo	components/sub'
assert_file_not_contains sub.out 'R	components/sub/inner	nested-repo	-	-	-	run git-nest absorb components/sub/inner'
rm -rf components/sub/inner

# --- Boundary 2: a nested repo inside a git-subrepo ---
test_step "A nested repo inside a git-subrepo is not reported as independent" "Only the subrepo boundary itself is a first-class finding; anything found underneath belongs to it."
mkdir -p components/subrepo
printf 'hi\n' >components/subrepo/a.txt
cat >components/subrepo/.gitrepo <<EOF
[subrepo]
	remote = file://$remote_foo
	branch = main
	commit = 0000000000000000000000000000000000000000
EOF
git add components/subrepo
git commit -m "add components/subrepo" >/dev/null
git clone "file://$remote_inner" components/subrepo/inner >/dev/null 2>&1
run_capture "survey reports the subrepo and the bounded inner repo" subrepo.out subrepo.err -- "$GIT_NEST" survey --porcelain
assert_file_contains subrepo.out 'G	components/subrepo	subrepo'
assert_file_contains subrepo.out 'components/subrepo/inner	nested-repo	components/subrepo'
assert_file_not_contains subrepo.out 'R	components/subrepo/inner	nested-repo	-	-	-	run git-nest absorb components/subrepo/inner'
rm -rf components/subrepo/inner

# --- Boundary 3: a subtree-shaped directory has no detectable marker, so
# survey cannot fence it off by scanning; absorb's own untracked-files guard
# is the actual protection when someone tries to act on it. ---
test_step "A subtree has no marker, so survey cannot detect its boundary, but absorb still refuses to swallow one" "This is a documented, accepted limitation of detection, not of enforcement: the real protection point is absorb --subtree itself, which never gets a --force override for untracked content underneath the path."
mkdir -p components/subtree
printf 'hi\n' >components/subtree/a.txt
git add components/subtree
git commit -m "add components/subtree files" >/dev/null
git clone "file://$remote_inner" components/subtree/inner >/dev/null 2>&1
run_capture "survey reports the inner repo directly since the outer subtree is invisible to it" subtree.out subtree.err -- "$GIT_NEST" survey --porcelain
assert_file_contains subtree.out 'R	components/subtree/inner	nested-repo	-	-	-	run git-nest absorb components/subtree/inner to manage it'
run_fail "absorb --subtree refuses to swallow the untracked inner repo, even with --force" any -- sh -c '"$1" absorb --subtree components/subtree "$2" --force >subtreeabsorb.out 2>subtreeabsorb.err' sh "$GIT_NEST" "file://$remote_foo"
assert_file_contains subtreeabsorb.err 'has untracked files'
test -d components/subtree/inner/.git
git -C components/subtree/inner rev-parse HEAD >/dev/null
rm -rf components/subtree/inner

describe_result "Boundaries were never crossed: submodule and subrepo boundaries fenced off what survey reports underneath them, and a subtree's lack of a detectable marker did not let absorb --subtree swallow a nested unmanaged repo."

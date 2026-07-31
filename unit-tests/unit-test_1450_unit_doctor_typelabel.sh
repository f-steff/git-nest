#!/bin/sh
# Unit test: tree_survey_typelabel and list_reproducibility_code
# Coverage: tree_survey_typelabel, list_reproducibility_code

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-doctor.sh"

# tree_survey_typelabel: maps internal state names to display labels.
assert_eq "$(tree_survey_typelabel 'submodule')" "Unmanaged Submodule"
assert_eq "$(tree_survey_typelabel 'nested-repo')" "Unmanaged Repo"
assert_eq "$(tree_survey_typelabel 'subrepo')" "Unmanaged Subrepo"
assert_eq "$(tree_survey_typelabel 'detached')" "Unmanaged Detached"
assert_eq "$(tree_survey_typelabel 'nest-root')" "Unmanaged Nested Nest Root"
assert_eq "$(tree_survey_typelabel 'unknown')" "Unmanaged"
assert_eq "$(tree_survey_typelabel '')" "Unmanaged"

# list_reproducibility_code: M = missing checkout (no .git).
assert_eq "$(list_reproducibility_code 'libs/missing' 'anything')" "M"
# U = unpinned (has .git, no revision).
mkdir -p libs/unpinned/.git
assert_eq "$(list_reproducibility_code 'libs/unpinned' '')" "U"
# R = reproducible (HEAD matches revision, mock returns same SHA for both).
mkdir -p libs/repro/.git
assert_eq "$(list_reproducibility_code 'libs/repro' 'anything')" "R"

printf 'All tests passed.\n'

#!/bin/sh
# Unit test: config_get and configured_clone_mode read and resolve config values
# Coverage: config_get, configured_clone_mode, effective_clone_mode

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# Set required globals normally defined by git_nest.sh.
CONFIG_FILE=.gitnest-rc
MANIFEST_FILE=.gitnest
SCRIPT_DIR="$REPO_ROOT/bin"

# config_get: reads a key from a .gitnest-rc section.
cat >.gitnest-rc <<'RC'
[clone]
mode=full
[defaults]
target_branch=main
RC

assert_eq "$(config_get 'clone' 'mode')" "full" "clone mode read"
assert_eq "$(config_get 'defaults' 'target_branch')" "main" "target branch read"
assert_eq "$(config_get 'nonexistent' 'mode')" "" "missing section returns empty"

# configured_clone_mode: defaults to manifest when no config file exists.
rm -f .gitnest-rc
assert_eq "$(configured_clone_mode)" "manifest" "defaults to manifest when no config"

# configured_clone_mode: reads full.
cat >.gitnest-rc <<'RC'
[clone]
mode=full
RC
assert_eq "$(configured_clone_mode)" "full" "reads full from config"

# configured_clone_mode: reads shallow.
cat >.gitnest-rc <<'RC'
[clone]
mode=shallow
RC
assert_eq "$(configured_clone_mode)" "shallow" "shallow accepted"

# effective_clone_mode with a manifest entry.
cat >.gitnest <<'MNF'
[project]
version=1
[subproject "libs/foo"]
repo=https://example.invalid/foo.git
target_branch=main
clone=partial
MNF
rm -f .gitnest-rc
manifest_load_cache

# configured_clone_mode defaults to manifest, so effective uses manifest value.
assert_eq "$(effective_clone_mode 'libs/foo')" "partial" "manifest clone mode used"

# A config override wins over the manifest value.
cat >.gitnest-rc <<'RC'
[clone]
mode=shallow
RC
assert_eq "$(effective_clone_mode 'libs/foo')" "shallow" "config override wins"

printf 'All tests passed.\n'

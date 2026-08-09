#!/bin/sh
# Unit test: recovery_backup_dir, backup_timestamp, gitrepo_get
# Coverage: recovery_backup_dir, backup_timestamp, gitrepo_get

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-conversion.sh"

# RECOVERY_BACKUP_PREFIX is defined in git-nest-main.sh. Set it here.
RECOVERY_BACKUP_PREFIX=.gitnest-recovery

# backup_timestamp: outputs a UTC timestamp in compact form.
_ts=$(backup_timestamp)
printf '%s\n' "$_ts" | grep -qE '^[0-9]{8}T[0-9]{6}Z$' || {
    echo "FAIL: backup_timestamp format: $_ts" >&2
    exit 1
}

# recovery_backup_dir: builds a timestamped path from operation and path.
_rdir=$(recovery_backup_dir "inline" "libs/foo")
printf '%s\n' "$_rdir" | grep -q '^.gitnest-recovery-inline-foo-' || {
    echo "FAIL: recovery dir prefix: $_rdir" >&2
    exit 1
}

# gitrepo_get: reads a key from a .gitrepo file.
cat >.gitrepo <<'GR'
[subrepo]
	remote = https://example.invalid/legacy-tool.git
	branch = main
	commit = abc123def456
	method = merge
	cmdver = 0.4.6
GR

assert_eq "$(gitrepo_get '.gitrepo' 'remote')" "https://example.invalid/legacy-tool.git" "gitrepo remote read"
assert_eq "$(gitrepo_get '.gitrepo' 'branch')" "main" "gitrepo branch read"
assert_eq "$(gitrepo_get '.gitrepo' 'commit')" "abc123def456" "gitrepo commit read"
assert_eq "$(gitrepo_get '.gitrepo' 'cmdver')" "0.4.6" "gitrepo cmdver read"
assert_eq "$(gitrepo_get '.gitrepo' 'method')" "merge" "gitrepo method read"

printf 'All tests passed.\n'

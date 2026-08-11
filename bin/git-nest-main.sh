#!/bin/sh
#
# git-nest: record and restore reproducible nests of independent Git repositories.
# https://github.com/f-steff/git-nest
#
# Lightweight multi-repository workspace coordination for ordinary Git remotes.
# A project root repository tracks a manifest of nested subproject repositories,
# while this script provides the command behavior for initializing, restoring,
# snapshotting, and verifying that workspace state.
#
# This file is the shared shell implementation. bin/git-nest sources it and
# then dispatches into git_nest_main; the Windows launchers (git-nest.bat /
# git-nest.ps1) forward straight to this file through Git Bash thanks to the
# self-dispatch guard at the bottom, so the extra bin/git-nest hop is not
# needed on Windows.
#
# Command implementations live in bin/lib/*.sh and are sourced below so the
# PATH-facing entrypoint stays thin while the library tree keeps each module
# focused on its own responsibility.
#
# Copyright (c) 2026 Flemming Steffensen.
# License: MIT
# SPDX-License-Identifier: MIT

# Source library modules
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib/git-nest-manifest.sh"
. "$SCRIPT_DIR/lib/git-nest-commands.sh"
. "$SCRIPT_DIR/lib/git-nest-hooks.sh"
. "$SCRIPT_DIR/lib/git-nest-conversion.sh"
. "$SCRIPT_DIR/lib/git-nest-doctor.sh"

MANIFEST_FILE=${GIT_NEST_MANIFEST:-.gitnest}
CONFIG_FILE=${GIT_NEST_CONFIG:-.gitnest-rc}
BRANCH_MARKS_FILE=${GIT_NEST_BRANCH_MARKS:-.gitnest-branches}
PUSH_CANDIDATES_FILE=${GIT_NEST_PUSH_CANDIDATES:-.gitnest-push-candidates}
GIT_NEST_VERSION=0.8.19
GIT_NEST_LOCK_TIMEOUT_SECONDS=${GIT_NEST_LOCK_TIMEOUT_SECONDS:-10}
GIT_NEST_DOCTOR_TIMEOUT_SECONDS=${GIT_NEST_DOCTOR_TIMEOUT_SECONDS:-5}
MANIFEST_SCHEMA_VERSION=1
JSON_SCHEMA_VERSION=1
GITATTRIBUTES_GUARD='.gitnest text eol=lf'
GITATTRIBUTES_BEGIN='# BEGIN git-nest attributes'
GITATTRIBUTES_END='# END git-nest attributes'
GITIGNORE_GIT_DIR_GUARD_ONE='**/.git/'
GITIGNORE_GIT_DIR_GUARD_TWO='**/.git'
GITIGNORE_BEGIN='# BEGIN git-nest ignores'
GITIGNORE_END='# END git-nest ignores'
RECOVERY_BACKUP_PREFIX='.gitnest-recovery'
OLD_HOOK_WARNING_PRINTED=0
MANIFEST_LOCK_HELD=
MANIFEST_LOCK_PATH=
GIT_NEST_EXIT_HANDLER_INSTALLED=0
GIT_NEST_NO_FETCH=0
GIT_NEST_BASE_OVERRIDES=
GIT_NEST_DRY_RUN=0
GIT_NEST_JSON_DRY_RUN=0

EXIT_ISSUES=1
EXIT_USAGE=2
EXIT_PRECONDITION=3
EXIT_LOCK=4
EXIT_GIT=5

# Self-dispatch when executed directly (not sourced). bin/git-nest sources
# this file and then calls git_nest_main itself; the Windows launchers run
# this file directly through Git Bash, so they need this guard to dispatch.
# When this file is sourced, $0 is the sourcing script and this block is
# skipped.
if [ "$(basename -- "$0")" = "git-nest-main.sh" ]; then
	git_nest_main "$@"
fi

#!/bin/sh
#
# version-check.sh -- verify that GIT_NEST_VERSION has been bumped upward
# relative to the last release tag. Used as the gate in the release
# workflow: same or earlier versions must be rejected.
#
# Usage:
#   sh scripts/package/version-check.sh [--current X.Y.Z] [--last A.B.C]
#
#   --current   The version to release (default: read GIT_NEST_VERSION
#               from bin/git-nest-main.sh).
#   --last      The last released version, without a leading 'v'
#               (default: the newest git tag, 'v'-stripped, or 0.0.0).
#
# Exit 0 when the current version is strictly greater than the last;
# exit 1 with a message otherwise.

set -eu

current=
last=

while [ $# -gt 0 ]; do
	case "$1" in
	--current)
		[ $# -ge 2 ] || {
			echo "version-check.sh: --current needs a value" >&2
			exit 2
		}
		current=$2
		shift 2
		;;
	--last)
		[ $# -ge 2 ] || {
			echo "version-check.sh: --last needs a value" >&2
			exit 2
		}
		last=$2
		shift 2
		;;
	-h | --help)
		sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "version-check.sh: unknown argument: $1 (see --help)" >&2
		exit 2
		;;
	esac
done

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

if [ -z "$current" ]; then
	current=$(sed -n 's/^GIT_NEST_VERSION=//p' "$repo/bin/git-nest-main.sh" | head -n 1)
fi
if [ -z "$last" ]; then
	last=$(git -C "$repo" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")
	last=${last#v}
fi

case "$current" in
[0-9]*.[0-9]*.[0-9]*) ;;
*)
	echo "version-check.sh: current version '$current' is not X.Y.Z" >&2
	exit 1
	;;
esac

if [ "$(printf '%s\n%s\n' "$last" "$current" | sort -V | tail -n1)" != "$current" ]; then
	echo "version-check.sh: version $current is not newer than the last release $last" >&2
	exit 1
fi
if [ "$last" = "$current" ]; then
	echo "version-check.sh: version $current equals the last release; bump the version first" >&2
	exit 1
fi

echo "version-check.sh: version $current is newer than $last - OK"

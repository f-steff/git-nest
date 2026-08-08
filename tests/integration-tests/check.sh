#!/bin/sh
#
# git-nest quality checks -- run this before committing to verify that all
# shell files pass syntax, formatting, shellcheck, and bashism checks.
#
# This file can be executed directly (sh tests/integration-tests/check.sh) or sourced by other
# scripts that want access to the tool_check, pass, fail, and skip functions.
#
# Missing tools are auto-installed to ~/bin/ on first run.
# Use --no-install to skip auto-install (useful in CI or offline).
# Supported auto-install: shellcheck, shfmt, checkbashisms.

SCRIPT_DIR=$(dirname -- "$0")
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)
FILES="bin/git_nest.sh bin/lib/*.sh"
NO_INSTALL=0
BIN_DIR="${HOME:-~}/bin"

# Count shell source files once for stats in pass/fail messages.
# Use absolute glob relative to REPO_ROOT so checks work from any cwd.
FILE_COUNT=0
LINE_COUNT=0
for _f in "$REPO_ROOT"/bin/git_nest.sh "$REPO_ROOT"/bin/lib/*.sh; do
	[ -f "$_f" ] || continue
	FILE_COUNT=$((FILE_COUNT + 1))
	_l=$(wc -l <"$_f")
	LINE_COUNT=$((LINE_COUNT + _l))
done

# ANSI colors (if supported)
if [ -t 1 ]; then
	RED='\033[31m'
	GREEN='\033[32m'
	YELLOW='\033[33m'
	BOLD='\033[1m'
	NC='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
	BOLD=''
	NC=''
fi

pass_() { printf '  [%sPASS%s] %s\n' "$GREEN" "$NC" "$*"; }
fail_() { printf '  [%sFAIL%s] %s\n' "$RED" "$NC" "$*"; }
skip_() { printf '  [%sSKIP%s] %s\n' "$YELLOW" "$NC" "$*"; }
info_() { printf '  [%sINFO%s] %s\n' "$YELLOW" "$NC" "$*"; }

# --- Auto-install ---
# Download a tool to ~/bin if missing. Supports shellcheck, shfmt, and
# checkbashisms on Linux, macOS, and Windows/Git Bash.

install_tool() {
	name=$1
	mkdir -p "$BIN_DIR"

	case "$name" in
	shellcheck)
		info_ "Downloading shellcheck to $BIN_DIR/ ..."
		curl -sL "https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.zip" -o /tmp/shellcheck.zip &&
			unzip -o -q /tmp/shellcheck.zip shellcheck.exe -d "$BIN_DIR" 2>/dev/null ||
			unzip -o -q /tmp/shellcheck.zip -d "$BIN_DIR" 2>/dev/null
		chmod +x "$BIN_DIR/shellcheck.exe" 2>/dev/null
		# On Linux/macOS the binary has no .exe suffix
		if [ -f "$BIN_DIR/shellcheck" ]; then
			chmod +x "$BIN_DIR/shellcheck"
		elif [ -f "$BIN_DIR/shellcheck.exe" ]; then
			: # already handled
		else
			# Try common extracted paths
			for _d in "$BIN_DIR"/shellcheck-*/; do
				[ -f "${_d}shellcheck" ] && cp "${_d}shellcheck" "$BIN_DIR/shellcheck" && chmod +x "$BIN_DIR/shellcheck"
				[ -f "${_d}shellcheck.exe" ] && cp "${_d}shellcheck.exe" "$BIN_DIR/shellcheck.exe"
			done
		fi
		rm -f /tmp/shellcheck.zip
		;;
	shfmt)
		info_ "Downloading shfmt to $BIN_DIR/ ..."
		os=$(uname -s 2>/dev/null || echo "Linux")
		case "$os" in
		*linux* | *Linux*) sfx="" ;;
		*darwin* | *Darwin*) sfx="" ;;
		*) sfx=".exe" ;;
		esac
		curl -sL "https://github.com/mvdan/sh/releases/download/v3.8.0/shfmt_v3.8.0_${os}_amd64${sfx}" -o "$BIN_DIR/shfmt${sfx}" 2>/dev/null ||
			curl -sL "https://github.com/mvdan/sh/releases/download/v3.8.0/shfmt_v3.8.0_windows_amd64.exe" -o "$BIN_DIR/shfmt.exe"
		chmod +x "$BIN_DIR/shfmt" "$BIN_DIR/shfmt.exe" 2>/dev/null
		;;
	checkbashisms)
		info_ "Downloading checkbashisms to $BIN_DIR/ ..."
		curl -sL "https://salsa.debian.org/debian/devscripts/-/raw/main/scripts/checkbashisms.pl" -o "$BIN_DIR/checkbashisms"
		chmod +x "$BIN_DIR/checkbashisms"
		;;
	esac

	# Create a wrapper script in ~/bin/ for any .exe we installed, so the
	# tool is invocable without the .exe suffix and takes priority over
	# any blocked shims from Chocolatey or other package managers.
	if [ -f "$BIN_DIR/${name}.exe" ] && [ ! -f "$BIN_DIR/$name" ]; then
		printf '#!/bin/sh\nexec "%s/%s.exe" "$@"\n' "$BIN_DIR" "$name" >"$BIN_DIR/$name"
		chmod +x "$BIN_DIR/$name"
	fi

	if command -v "$name" >/dev/null 2>&1; then
		pass_ "$name installed"
		return 0
	fi
	fail_ "failed to install $name; install manually (see script header)"
	return 1
}

# Run a tool check, auto-installing if missing (unless NO_INSTALL is set).
tool_check() {
	name=$1
	shift
	if ! command -v "$name" >/dev/null 2>&1; then
		if [ "$NO_INSTALL" -eq 1 ]; then
			skip_ "$name not found"
			return 2
		fi
		install_tool "$name" || return 2
	fi
	set +e
	"$@"
	rc=$?
	set -e
	if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
		info_ "$name exists but is blocked (exit $rc); attempting fresh install to $BIN_DIR/ ..."
		if [ "$NO_INSTALL" -eq 0 ]; then
			install_tool "$name"
		fi
		# Try again with the newly installed copy
		if command -v "$name" >/dev/null 2>&1; then
			set +e
			"$@"
			rc=$?
			set -e
		fi
		if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
			skip_ "$name still not usable after install attempt (exit $rc)"
			return 2
		fi
	fi
	return "$rc"
}

# --- Individual check functions ---

check_syntax() {
	rc=0
	for f in "$REPO_ROOT"/bin/git_nest.sh "$REPO_ROOT"/bin/lib/*.sh; do
		[ -f "$f" ] || continue
		sh -n "$f" 2>/dev/null || {
			fail_ "${f##*/}"
			rc=1
		}
	done
	[ "$rc" -eq 0 ] && pass_ "${FILE_COUNT} files, ${LINE_COUNT} lines"
	return "$rc"
}

check_shellcheck() {
	if tool_check shellcheck shellcheck -s sh "$REPO_ROOT"/bin/git_nest.sh "$REPO_ROOT"/bin/lib/*.sh 2>/dev/null; then
		pass_ "${FILE_COUNT} files, 0 warnings"
		return 0
	fi
	return $?
}

check_shfmt() {
	if tool_check shfmt shfmt --version 2>/dev/null; then
		issues=0
		for f in "$REPO_ROOT"/bin/git_nest.sh "$REPO_ROOT"/bin/lib/*.sh; do
			[ -f "$f" ] || continue
			if shfmt -d -ln posix "$f" 2>/dev/null | grep . >/dev/null 2>&1; then
				fail_ "${f##*/} (run: shfmt -w -ln posix ${f##*/})"
				issues=$((issues + 1))
			fi
		done
		[ "$issues" -eq 0 ] && pass_ "${FILE_COUNT} files, all formatted"
		return "$issues"
	fi
	return $?
}

check_bashisms() {
	if tool_check checkbashisms checkbashisms --version >/dev/null 2>&1; then
		issues=0
		for f in "$REPO_ROOT"/bin/git_nest.sh "$REPO_ROOT"/bin/lib/*.sh; do
			[ -f "$f" ] || continue
			if checkbashisms "$f" 2>/dev/null | grep . >/dev/null 2>&1; then
				fail_ "${f##*/}"
				issues=$((issues + 1))
			fi
		done
		[ "$issues" -eq 0 ] && pass_ "${FILE_COUNT} files, 0 bashisms"
		return "$issues"
	fi
	return $?
}

# Every shell source file, test, and doc must be plain ASCII (see the "Keep
# all files plain ASCII" rule in docs/maintainer.md): no em/en dashes, curly
# quotes, arrows, or other non-ASCII punctuation. This keeps diffs and
# terminal rendering identical across editors, shells, and platforms, and
# needs no external tool, so it never skips. ANSI escape sequences (used by
# help_setup_colors for optional, TTY-only, NO_COLOR-respecting colored help
# output) are plain ASCII bytes and are unaffected by this check.
#
# Unlike grep -P "[^\x00-\x7F]" (which requires Perl-compatible regex and
# may miss some bytes on certain platforms), this uses od (octal dump) for
# accurate byte-level detection of non-ASCII content (bytes 0x80-0xFF).
check_ascii() {
	found=0
	_temp=$(mktemp /tmp/ascii-scan-XXXXXX)
	git ls-files >"$_temp"
	while IFS= read -r f; do
		case "$f" in
		*.ico | *.png | *.jpg | *.gif | *.woff2 | *.eot | *.ttf | *.svg) continue ;;
		*.bat) continue ;;
		esac
		if od -An -tx1 "$f" 2>/dev/null | tr ' ' '\n' | grep -q '^[89a-f][0-9a-f]$' 2>/dev/null; then
			fail_ "$f"
			found=$((found + 1))
		fi
	done <"$_temp"
	rm -f "$_temp"
	[ "$found" -eq 0 ] && pass_ "no non-ASCII characters in bin, tests, docs, skills, or root markdown"
	return "$found"
}

# The tool version reported by bin/git-nest version (GIT_NEST_VERSION) must
# match the newest "## x.y.z" entry in version.md. The two are updated
# together on every release, so a stale value in either file is a release
# blocker (see docs/maintainer.md "Keep GIT_NEST_VERSION aligned with
# README.md, version.md, and release tests").
check_version_alignment() {
	_version_file="$REPO_ROOT/version.md"
	_shell_file="$REPO_ROOT/bin/git_nest.sh"
	_code_version=$(sed -n 's/^GIT_NEST_VERSION=//p' "$_shell_file" | head -n 1)
	_doc_version=$(sed -n 's/^## \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' "$_version_file" | head -n 1)
	if [ -z "$_code_version" ] || [ -z "$_doc_version" ]; then
		fail_ "could not extract version (code='$_code_version' doc='$_doc_version')"
		return 1
	fi
	if [ "$_code_version" = "$_doc_version" ]; then
		pass_ "GIT_NEST_VERSION $_code_version matches the newest version.md entry"
		return 0
	fi
	fail_ "GIT_NEST_VERSION=$_code_version does not match the newest version.md entry $_doc_version; update both atomically"
	return 1
}

# Every relative link in committed markdown must point at a file that
# exists. GitHub transforms relative links per-branch, so a missing target
# is a broken link on every branch; this check keeps the docs and the
# README consistent with the tree they live in.
check_links() {
	_failfile=$(mktemp /tmp/link-fail-XXXXXX)
	_linksfile=$(mktemp /tmp/link-list-XXXXXX)
	git ls-files '*.md' >"$_linksfile"
	while IFS= read -r f; do
		# Generated by the test runner; never a link source.
		case "$f" in
		run-all-tests-results.md) continue ;;
		esac
		_dir=$(dirname "$f")
		# Extract markdown link targets: [text](target). Skip external
		# URLs, anchors, and mailto: links. Relative targets must resolve
		# to an existing file relative to the containing document.
		sed -n 's/.*](\([^)]*\)).*/\1/p' "$REPO_ROOT/$f" | while IFS= read -r t; do
			case "$t" in
			http://* | https://* | mailto:* | '#'* | '') continue ;;
			esac
			# Strip any fragment/anchor from a relative target.
			target=${t%%#*}
			real=$(CDPATH= cd -- "$REPO_ROOT/$_dir" 2>/dev/null && realpath -m -- "$target" 2>/dev/null || echo "")
			[ -n "$real" ] || continue
			[ -f "$real" ] || {
				printf '  %s: broken link -> %s\n' "$f" "$t" >&2
				printf 'x\n' >>"$_failfile"
			}
		done
	done <"$_linksfile"
	rm -f "$_linksfile"
	if [ -s "$_failfile" ]; then
		rm -f "$_failfile"
		fail_ "broken relative link(s) in committed markdown"
		return 1
	fi
	rm -f "$_failfile"
	pass_ "all relative links in committed markdown resolve to existing files"
	return 0
}

# The release gate: GIT_NEST_VERSION must be strictly newer than the last
# release tag. check_version_alignment verifies the file pair; this check
# runs the release workflow's own gate script so the CI-verified logic is
# exactly what the workflow uses.
check_version_gate() {
	_script="$REPO_ROOT/scripts/package/version-check.sh"
	[ -f "$_script" ] || {
		fail_ "missing scripts/package/version-check.sh"
		return 1
	}
	# No tags exist locally, so the script falls back to 0.0.0 and passes.
	if sh "$_script" >/dev/null 2>&1; then
		pass_ "GIT_NEST_VERSION passes the release version gate"
		return 0
	fi
	fail_ "GIT_NEST_VERSION does not pass the release version gate"
	return 1
}

# --- Stats ---

print_stats() {
	total_files=0
	total_lines=0
	for f in $FILES; do
		fpath="$REPO_ROOT/$f"
		[ -f "$fpath" ] || continue
		total_files=$((total_files + 1))
		l=$(wc -l <"$fpath")
		total_lines=$((total_lines + l))
	done
	echo "  Files: ${total_files},  Lines: ${total_lines}"
}

# --- Standalone execution ---
case "$(basename -- "$0")" in check.sh)
	set -eu
	rc=0

	# Parse --no-install
	for arg in "$@"; do
		case "$arg" in
		--no-install) NO_INSTALL=1 ;;
		esac
	done

	echo "${BOLD}git-nest quality checks${NC}" ""
	print_stats
	echo ""
	check_syntax || rc=1
	echo ""

	echo "--- ShellCheck ---"
	check_shellcheck || [ $? -eq 2 ] || rc=1
	echo ""

	echo "--- shfmt (formatting diff) ---"
	check_shfmt || [ $? -eq 2 ] || rc=1
	echo ""

	echo "--- checkbashisms (POSIX compliance) ---"
	check_bashisms || [ $? -eq 2 ] || rc=1
	echo ""

	echo "--- ASCII-only (bin, tests, docs, skills, root markdown) ---"
	check_ascii || rc=1
	echo ""

	echo "--- Version alignment (GIT_NEST_VERSION vs version.md) ---"
	check_version_alignment || rc=1
	echo ""

	echo "--- Relative links in committed markdown ---"
	check_links || rc=1
	echo ""

	echo "--- Release version gate (version-check.sh) ---"
	check_version_gate || rc=1
	echo ""

	echo "${BOLD}Summary${NC}"
	if [ "$rc" -eq 0 ]; then
		echo "  ${GREEN}All checks passed.${NC}"
	else
		echo "  ${RED}Some checks failed.${NC}"
	fi
	exit "$rc"
	;;
esac

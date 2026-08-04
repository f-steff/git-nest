#!/bin/sh
#
# run-cross-shell-tests.sh -- Test git-nest across multiple POSIX shells in
# Docker. Each source file and each unit test runs under every available shell.
#
# Usage: sh run-cross-shell-tests.sh [--alpine|--debian]
#
# ASCII only.

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
RUN_ALPINE=1; RUN_DEBIAN=1

while [ $# -gt 0 ]; do
    case "$1" in
        --alpine) RUN_ALPINE=1; RUN_DEBIAN=0; shift ;;
        --debian) RUN_ALPINE=0; RUN_DEBIAN=1; shift ;;
        --help|-h) sed -n '2s/^# //p;4,7s/^# //p' "$0"; exit 0 ;;
        *) printf 'Error: %s\n' "$1" >&2; exit 2 ;;
    esac
done

HOST_PATH="$REPO_ROOT"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)
    HOST_PATH=$(cd "$REPO_ROOT" && pwd -W 2>/dev/null || echo "$REPO_ROOT")
esac
export MSYS2_ARG_CONV_EXCL="*"

TOTAL_PASS=0; TOTAL_FAIL=0

run_in_docker() {
    _image=$1; _install=$2; _all_shells=$3; _label=$4
    printf '\n=== %s (%s) ===\n' "$_label" "$_image"

    # Results file has lines: PASS/FAIL<TAB>shell<TAB>file
    _out=$(mktemp)

    set +e
    docker run --rm -v "$HOST_PATH:/mnt:ro" "$_image" sh -c "
        $_install 2>/dev/null | tail -1
        # Copy entire repo to a writable directory so all shells (including
        # zsh, which has issues reading from Docker volumes) can access files.
        cp -r /mnt /work; cd /work/mnt
        cd /work

        for sh in $_all_shells; do
            command -v \"\$sh\" >/dev/null 2>&1 || continue

            if [ \"\$sh\" = pwsh ]; then
                # pwsh is not a POSIX shell -- run a launcher smoketest
                # (version output) instead of syntax/unit tests.
                if \"\$sh\" -noprofile /work/bin/git-nest.ps1 2>/dev/null; then printf 'PASS\\t%s\\t%s\\n' \"\$sh\" \"git-nest.ps1 (syntax)\"; else printf 'FAIL\\t%s\\t%s\\n' \"\$sh\" \"git-nest.ps1 (syntax)\"; fi
                # Also test __complete dispatch through the .ps1 launcher
                if \"\$sh\" -noprofile -c \"& '/work/bin/git-nest.ps1' __complete 0 -- '' 2>&1 | Select-String -Quiet 'C.*init.*command'\" 2>/dev/null; then printf 'PASS\\t%s\\t%s\\n' \"\$sh\" \"git-nest.ps1 (__complete dispatch)\"; else printf 'FAIL\\t%s\\t%s\\n' \"\$sh\" \"git-nest.ps1 (__complete dispatch)\"; fi
                continue
            fi

            # Check that fish syntax check uses fish --no-execute
            if [ \"\$sh\" = fish ]; then
                for f in /work/tests/unit-tests/unit-test_*.sh; do
                    [ -f \"\$f\" ] || continue
                    bn=\$(basename \"\$f\")
                    # Fish has its own syntax; skip POSIX unit tests
                    printf 'SKIP\\t%s\\t%s\\n' \"\$sh\" \"\$bn\"
                done
                # Fish syntax check on generated completion script
                /work/bin/git-nest completion fish >/tmp/git-nest.fish 2>/dev/null || true
                if \"\$sh\" --no-execute /tmp/git-nest.fish 2>/dev/null; then printf 'PASS\\t%s\\t%s\\n' \"\$sh\" \"completion fish\"; else printf 'FAIL\\t%s\\t%s\\n' \"\$sh\" \"completion fish\"; fi
                # __complete engine test: invoke via /bin/sh (fish cannot run POSIX scripts itself)
                if /bin/sh /work/bin/git-nest __complete 0 -- '' >/tmp/complete.out 2>/dev/null && grep -q 'C.*init.*command' /tmp/complete.out 2>/dev/null; then
                    printf 'PASS\\t%s\\t%s\\n' \"\$sh\" \"__complete engine\"
                else
                    printf 'FAIL\\t%s\\t%s\\n' \"\$sh\" \"__complete engine\"
                fi
                continue
            fi

            for f in bin/git_nest.sh bin/lib/git-nest-manifest.sh bin/lib/git-nest-commands.sh bin/lib/git-nest-conversion.sh bin/lib/git-nest-doctor.sh bin/lib/git-nest-hooks.sh; do
                [ -f \"/work/\$f\" ] || continue
                if \"\$sh\" -n \"/work/\$f\" 2>/dev/null; then printf 'PASS\\t%s\\t%s\\n' \"\$sh\" \"\$f\"; else printf 'FAIL\\t%s\\t%s\\n' \"\$sh\" \"\$f\"; fi
            done
            for f in /work/tests/unit-tests/unit-test_*.sh; do
                [ -f \"\$f\" ] || continue
                bn=\$(basename \"\$f\")
                # zsh: known issue in container environments -- command
                # resolution fails for functions defined via sourced files.
                # Syntax checks still run; unit tests are skipped.
                [ \"\$sh\" = zsh ] && printf 'SKIP\\t%s\\t%s\\n' \"\$sh\" \"\$bn\" && continue
                if \"\$sh\" \"\$f\" >/dev/null 2>&1; then printf 'PASS\\t%s\\t%s\\n' \"\$sh\" \"\$bn\"; else printf 'FAIL\\t%s\\t%s\\n' \"\$sh\" \"\$bn\"; fi
            done

            # __complete engine test: invoke the engine through each POSIX shell
            _complete_out=\$(mktemp)
            if \"\$sh\" /work/bin/git-nest __complete 0 -- '' >\"\$_complete_out\" 2>/dev/null && grep -q 'C.*init.*command' \"\$_complete_out\" 2>/dev/null; then
                printf 'PASS\\t%s\\t%s\\n' \"\$sh\" \"__complete engine\"
            else
                printf 'FAIL\\t%s\\t%s\\n' \"\$sh\" \"__complete engine\"
            fi
            rm -f \"\$_complete_out\"
        done
    " >"$_out" 2>/dev/null
    _rc=$?
    set -e

    _pass=$(grep -c '^PASS' "$_out" 2>/dev/null || printf '0')
    _fail=$(grep -c '^FAIL' "$_out" 2>/dev/null || printf '0')

    # Print per-shell table
    for sh in $_all_shells; do
        _spass=$(grep "^PASS	$sh	" "$_out" 2>/dev/null | wc -l | tr -d ' ')
        _sfail=$(grep "^FAIL	$sh	" "$_out" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$_sfail" -gt 0 ]; then
            printf '  %-6s  %3s pass, %3s fail -- FAILING:\n' "$sh" "$_spass" "$_sfail"
            grep "^FAIL	$sh	" "$_out" | while IFS='	' read -r _s _sh2 _file; do
                printf '    FAIL: %s\n' "$_file"
            done
        else
            printf '  %-6s  %3s pass, %3s fail\n' "$sh" "$_spass" "$_sfail"
        fi
    done

    # Parse counts for individual files
    _syn_pass=$(grep -c '^PASS.*bin/' "$_out" 2>/dev/null || true)
    _syn_fail=$(grep -c '^FAIL.*bin/' "$_out" 2>/dev/null || true)
    _unit_pass=$(grep -c '^PASS.*unit-test' "$_out" 2>/dev/null || true)
    _unit_fail=$(grep -c '^FAIL.*unit-test' "$_out" 2>/dev/null || true)
    : "${_syn_pass:=0}" "${_syn_fail:=0}" "${_unit_pass:=0}" "${_unit_fail:=0}"
    printf 'Syntax: %s/%s  Unit: %s/%s\n' "$_syn_pass" "$((_syn_pass + _syn_fail))" "$_unit_pass" "$((_unit_pass + _unit_fail))"

    rm -f "$_out"
    _fail=$(printf '%s' "$_fail" | tr -cd '0-9')
    return "$_fail"
}

if [ "$RUN_ALPINE" -eq 1 ]; then
    run_in_docker "alpine:3.21" \
        "apk add -q dash bash zsh mksh yash powershell fish coreutils git tar python3 gawk diffutils" \
        "dash bash ash zsh mksh yash fish pwsh" \
        "Alpine" && TOTAL_PASS=$((TOTAL_PASS + 1)) || TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

if [ "$RUN_DEBIAN" -eq 1 ]; then
    run_in_docker "debian:bookworm-slim" \
        "apt-get update -qq 2>/dev/null; apt-get install -y -qq wget apt-transport-https 2>&1 | tail -1; wget -q https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O /tmp/pkgs.deb; dpkg -i /tmp/pkgs.deb 2>/dev/null; apt-get update -qq 2>/dev/null; apt-get install -y -qq powershell dash bash zsh ksh mksh posh git tar python3 gawk 2>&1 | tail -1" \
        "dash bash zsh ksh mksh posh pwsh" \
        "Debian" && TOTAL_PASS=$((TOTAL_PASS + 1)) || TOTAL_FAIL=$((TOTAL_FAIL + 1))
fi

printf '\nContainers passed: %s, failed: %s\n' "$TOTAL_PASS" "$TOTAL_FAIL"
[ "$TOTAL_FAIL" -eq 0 ] || exit 1

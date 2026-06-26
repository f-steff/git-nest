#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin nested_stacks

PATH="$REPO_ROOT/bin:$PATH"
export PATH

make_stack_remote() {
    remote=$1
    work=$2
    module_path=$3
    module_repo=$4
    make_repo "$work"
    printf 'root\n' >"$work/root.txt"
    cat >"$work/.stack" <<EOF
# git-stack manifest

[stack]

[module "$module_path"]
repo=$module_repo
target_branch=main
EOF
    printf '/%s/\n' "$module_path" >"$work/.gitignore"
    git -C "$work" add root.txt .stack .gitignore
    git -C "$work" commit -m "nested stack root" >/dev/null
    git -C "$work" init --bare --initial-branch=main "$remote" >/dev/null 2>&1 || git -C "$work" init --bare "$remote" >/dev/null
    git -C "$work" remote add origin "$remote"
    git -C "$work" push -u origin main >/dev/null
    git -C "$remote" symbolic-ref HEAD refs/heads/main
}

root=$(test_workspace nested_stacks)
mkdir -p "$root/remotes" "$root/seed"
tab=$(printf '\t')

adc_remote="$root/remotes/adc.git"
adc_seed="$root/seed/adc"
make_bare_remote "$adc_remote" "$adc_seed"
adc_url="file://$adc_remote"

driver_remote="$root/remotes/driver.git"
driver_seed="$root/seed/driver"
make_stack_remote "$driver_remote" "$driver_seed" "chips/adc" "$adc_url"
driver_url="file://$driver_remote"

firmware_remote="$root/remotes/firmware.git"
firmware_seed="$root/seed/firmware"
make_stack_remote "$firmware_remote" "$firmware_seed" "drivers/io" "$driver_url"
firmware_url="file://$firmware_remote"

outer="$root/outer"
make_repo "$outer"
cd "$outer"
"$GIT_STACK" init >/dev/null
"$GIT_STACK" add "$firmware_url" firmware >/dev/null
git add .stack .gitignore
git commit -m "parent stack" >/dev/null

"$GIT_STACK" status >status.out 2>status.err
assert_file_contains status.err "Notice: nested stack found at firmware"

"$GIT_STACK" verify >verify.out 2>verify.err
assert_file_contains verify.out "Stack verified."
assert_file_contains verify.err "Notice: nested stack found at firmware"

"$GIT_STACK" sync >sync.out 2>sync.err
assert_file_contains sync.err "Notice: nested stack found at firmware"
test ! -d firmware/drivers/io/.git

"$GIT_STACK" log --max-count 5 >log.out 2>log.err
assert_file_contains log.out "firmware"
assert_file_contains log.err "Notice: nested stack found at firmware"
assert_file_not_contains log.out "firmware/drivers/io"

cd firmware
git stack status >"$root/inner_status.out"
assert_file_contains "$root/inner_status.out" "drivers/io: missing"
assert_file_not_contains "$root/inner_status.out" "firmware:"
cd "$outer"

"$GIT_STACK" sync --recursive >sync_recursive.out
test -d firmware/drivers/io/.git
test -d firmware/drivers/io/chips/adc/.git
assert_file_contains sync_recursive.out "Syncing stack: ."
assert_file_contains sync_recursive.out "Syncing stack: firmware"
assert_file_contains sync_recursive.out "Syncing stack: firmware/drivers/io"

"$GIT_STACK" status --recursive >status_recursive.out
assert_file_contains status_recursive.out "stack: ."
assert_file_contains status_recursive.out "stack: firmware"
assert_file_contains status_recursive.out "stack: firmware/drivers/io"
assert_file_contains status_recursive.out "firmware/drivers/io"

# Keep generated assertion files from making the outer repository dirty before
# the porcelain status checks.
rm -f *.out *.err

printf 'dirty nested\n' >>firmware/drivers/io/root.txt
"$GIT_STACK" status --porcelain >"$root/status_porcelain.out"
test ! -s "$root/status_porcelain.out"
"$GIT_STACK" status --recursive --porcelain >"$root/status_recursive_porcelain.out"
assert_file_contains "$root/status_recursive_porcelain.out" "firmware/drivers/io${tab} M root.txt"
git -C firmware/drivers/io checkout -- root.txt

"$GIT_STACK" verify --recursive >verify_recursive.out
assert_file_contains verify_recursive.out "Verifying stack: ."
assert_file_contains verify_recursive.out "Verifying stack: firmware"
assert_file_contains verify_recursive.out "Verifying stack: firmware/drivers/io"

printf 'adc second\n' >>"$adc_seed/file.txt"
git -C "$adc_seed" add file.txt
git -C "$adc_seed" commit -m "adc second" >/dev/null
git -C "$adc_seed" push origin main >/dev/null
adc_initial=$(git -C firmware/drivers/io/chips/adc rev-parse HEAD)
adc_second=$(git -C "$adc_seed" rev-parse HEAD)
"$GIT_STACK" available --porcelain >available_porcelain.out
test ! -s available_porcelain.out
"$GIT_STACK" available --recursive --porcelain >available_recursive_porcelain.out
assert_file_contains available_recursive_porcelain.out "firmware/drivers/io/chips/adc${tab}available${tab}main${tab}$adc_initial${tab}$adc_second"

"$GIT_STACK" log --recursive --max-count 20 >log_recursive.out
assert_file_contains log_recursive.out "firmware"
assert_file_contains log_recursive.out "firmware/drivers/io"
assert_file_contains log_recursive.out "firmware/drivers/io/chips/adc"

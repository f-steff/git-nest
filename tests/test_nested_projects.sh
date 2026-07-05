#!/bin/sh

set -eu
. "$(dirname "$0")/helper.sh"
test_begin nested_projects

PATH="$REPO_ROOT/bin:$PATH"
export PATH

make_project_remote() {
    remote=$1
    work=$2
    subproject_path=$3
    subproject_repo=$4
    make_repo "$work"
    printf 'root\n' >"$work/root.txt"
    cat >"$work/.gitlego" <<EOF
# git-lego manifest

[project]
version=1

[subproject "$subproject_path"]
repo=$subproject_repo
target_branch=main
EOF
    printf '/%s/\n' "$subproject_path" >"$work/.gitignore"
    git -C "$work" add root.txt .gitlego .gitignore
    git -C "$work" commit -m "nested project root" >/dev/null
    git -C "$work" init --bare --initial-branch=main "$remote" >/dev/null 2>&1 || git -C "$work" init --bare "$remote" >/dev/null
    git -C "$work" remote add origin "$remote"
    git -C "$work" push -u origin main >/dev/null
    git -C "$remote" symbolic-ref HEAD refs/heads/main
}

root=$(test_workspace nested_projects)
mkdir -p "$root/remotes" "$root/seed"
tab=$(printf '\t')

adc_remote="$root/remotes/adc.git"
adc_seed="$root/seed/adc"
make_bare_remote "$adc_remote" "$adc_seed"
adc_url="file://$adc_remote"

driver_remote="$root/remotes/driver.git"
driver_seed="$root/seed/driver"
make_project_remote "$driver_remote" "$driver_seed" "chips/adc" "$adc_url"
driver_url="file://$driver_remote"

firmware_remote="$root/remotes/firmware.git"
firmware_seed="$root/seed/firmware"
make_project_remote "$firmware_remote" "$firmware_seed" "drivers/io" "$driver_url"
firmware_url="file://$firmware_remote"

outer="$root/outer"
make_repo "$outer"
cd "$outer"
"$GIT_LEGO" init >/dev/null
"$GIT_LEGO" add "$firmware_url" firmware >/dev/null
git add .gitlego .gitignore .gitattributes
git commit -m "parent project" >/dev/null

"$GIT_LEGO" status >status.out 2>status.err
assert_file_contains status.err "Notice: nested project found at firmware"

"$GIT_LEGO" verify >verify.out 2>verify.err
assert_file_contains verify.out "Project verified."
assert_file_contains verify.err "Notice: nested project found at firmware"

"$GIT_LEGO" sync >sync.out 2>sync.err
assert_file_contains sync.err "Notice: nested project found at firmware"
test ! -d firmware/drivers/io/.git

"$GIT_LEGO" log --max-count 5 >log.out 2>log.err
assert_file_contains log.out "firmware"
assert_file_contains log.err "Notice: nested project found at firmware"
assert_file_not_contains log.out "firmware/drivers/io"

cd firmware
git lego status >"$root/inner_status.out"
assert_file_contains "$root/inner_status.out" "drivers/io: missing"
assert_file_not_contains "$root/inner_status.out" "firmware:"
cd "$outer"

"$GIT_LEGO" sync --recursive >sync_recursive.out
test -d firmware/drivers/io/.git
test -d firmware/drivers/io/chips/adc/.git
assert_file_contains sync_recursive.out "Syncing project: ."
assert_file_contains sync_recursive.out "Syncing project: firmware"
assert_file_contains sync_recursive.out "Syncing project: firmware/drivers/io"

"$GIT_LEGO" status --recursive >status_recursive.out
assert_file_contains status_recursive.out "project: ."
assert_file_contains status_recursive.out "project: firmware"
assert_file_contains status_recursive.out "project: firmware/drivers/io"
assert_file_contains status_recursive.out "firmware/drivers/io"

# Keep generated assertion files from making the outer repository dirty before
# the porcelain status checks.
rm -f *.out *.err

printf 'dirty nested\n' >>firmware/drivers/io/root.txt
"$GIT_LEGO" status --porcelain >"$root/status_porcelain.out"
test ! -s "$root/status_porcelain.out"
"$GIT_LEGO" status --recursive --porcelain >"$root/status_recursive_porcelain.out"
assert_file_contains "$root/status_recursive_porcelain.out" "D${tab}firmware/drivers/io${tab}dirty${tab}-${tab}-${tab}-${tab} M root.txt"
"$GIT_LEGO" status --recursive --json >"$root/status_recursive.json"
assert_file_contains "$root/status_recursive.json" '"recursive":true'
assert_file_contains "$root/status_recursive.json" '"path":"firmware/drivers/io"'
git -C firmware/drivers/io checkout -- root.txt

"$GIT_LEGO" verify --recursive >verify_recursive.out
assert_file_contains verify_recursive.out "Verifying project: ."
assert_file_contains verify_recursive.out "Verifying project: firmware"
assert_file_contains verify_recursive.out "Verifying project: firmware/drivers/io"
"$GIT_LEGO" verify --recursive --json >verify_recursive.json
assert_file_contains verify_recursive.json '"command":"verify"'
assert_file_contains verify_recursive.json '"recursive":true'

printf 'adc second\n' >>"$adc_seed/file.txt"
git -C "$adc_seed" add file.txt
git -C "$adc_seed" commit -m "adc second" >/dev/null
git -C "$adc_seed" push origin main >/dev/null
adc_initial=$(git -C firmware/drivers/io/chips/adc rev-parse HEAD)
adc_second=$(git -C "$adc_seed" rev-parse HEAD)
"$GIT_LEGO" outdated --porcelain >outdated_porcelain.out
test ! -s outdated_porcelain.out
if "$GIT_LEGO" outdated --recursive --porcelain >outdated_recursive_porcelain.out; then
    echo "recursive outdated should return nonzero when updates are available" >&2
    exit 1
fi
assert_file_contains outdated_recursive_porcelain.out "O${tab}firmware/drivers/io/chips/adc${tab}outdated${tab}main${tab}$adc_initial${tab}$adc_second${tab}remote-target"
if "$GIT_LEGO" outdated --recursive --json >outdated_recursive.json; then
    echo "recursive outdated JSON should return nonzero when updates are available" >&2
    exit 1
fi
assert_file_contains outdated_recursive.json '"command":"outdated"'
assert_file_contains outdated_recursive.json '"path":"firmware/drivers/io/chips/adc"'

"$GIT_LEGO" log --recursive --max-count 20 >log_recursive.out
assert_file_contains log_recursive.out "firmware"
assert_file_contains log_recursive.out "firmware/drivers/io"
assert_file_contains log_recursive.out "firmware/drivers/io/chips/adc"

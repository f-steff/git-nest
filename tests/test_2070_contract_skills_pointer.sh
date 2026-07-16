#!/bin/sh
# Test: the git-nest usage skill lives in skills/ with an .agents/skills pointer

set -eu
. "$(dirname "$0")/helper.sh"
test_begin contract_skills_pointer

test_step "Verify the git-nest usage skill layout" "The product usage skill must live in skills/ as the single source of truth, and the development-agent copy under .agents/skills/ must be a pointer to it, so opencode/Codex discovery works without duplicating skill content."

source_skill="$REPO_ROOT/skills/git-nest/SKILL.md"
pointer_skill="$REPO_ROOT/.agents/skills/git-nest/SKILL.md"

# The product source of truth exists and declares the git-nest skill.
print_command test -f skills/git-nest/SKILL.md
[ -f "$source_skill" ] || {
    printf 'UNEXPECTED RESULT: missing source of truth skills/git-nest/SKILL.md\n' >&2
    exit 1
}
assert_file_contains "$source_skill" "name: git-nest"

# The development pointer exists, is discoverable under .agents/skills, and
# redirects to the product source instead of duplicating workflow guidance.
print_command test -f .agents/skills/git-nest/SKILL.md
[ -f "$pointer_skill" ] || {
    printf 'UNEXPECTED RESULT: missing pointer .agents/skills/git-nest/SKILL.md\n' >&2
    exit 1
}
assert_file_contains "$pointer_skill" "name: git-nest"
assert_file_contains "$pointer_skill" "skills/git-nest/SKILL.md"

# The stale, non-discoverable location must not come back.
print_command test ! -e .agents/git-nest/SKILL.md
[ ! -e "$REPO_ROOT/.agents/git-nest/SKILL.md" ] || {
    printf 'UNEXPECTED RESULT: .agents/git-nest/SKILL.md is not discoverable by opencode; move it to skills/git-nest/SKILL.md\n' >&2
    exit 1
}

# Discovery uses the frontmatter description, so the pointer description must
# match the source description exactly.
source_desc=$(grep '^description:' "$source_skill" | head -n 1)
pointer_desc=$(grep '^description:' "$pointer_skill" | head -n 1)
if [ "$source_desc" != "$pointer_desc" ]; then
    printf 'UNEXPECTED RESULT: pointer description drifted from source description\n' >&2
    printf '  source : %s\n' "$source_desc" >&2
    printf '  pointer: %s\n' "$pointer_desc" >&2
    exit 1
fi

describe_result "The usage skill lives in skills/ as the source of truth and the .agents/skills pointer redirects to it with a matching description."

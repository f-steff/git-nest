#!/bin/sh
#
# git-nest: record and restore reproducible nests of independent Git repositories.
# https://github.com/f-steff/git-nest
#
# git-nest commands -- sourced by bin/git_nest.sh
#
# All command implementations not covered by the manifest, hooks, export,
# or doctor library modules.
#
# Copyright (c) 2026 Flemming Steffensen.
# License: MIT
# SPDX-License-Identifier: MIT
help_setup_colors() {
	HELP_RESET=
	HELP_BOLD=
	HELP_DIM=
	HELP_SECTION=
	HELP_CMD=
	HELP_OPT=
	HELP_ARG=

	case "${GIT_NEST_COLOR:-auto}" in
	never | no | 0 | false) return 0 ;;
	always | yes | 1 | true) use_color=1 ;;
	*)
		use_color=0
		[ -t 1 ] && use_color=1
		[ "${TERM:-}" = dumb ] && use_color=0
		[ -n "${NO_COLOR:-}" ] && use_color=0
		[ -n "${GIT_NEST_NO_COLOR:-}" ] && use_color=0
		;;
	esac
	[ "$use_color" -eq 1 ] || return 0

	esc=$(printf '\033')
	HELP_RESET="${esc}[0m"
	HELP_BOLD="${esc}[1m"
	HELP_DIM="${esc}[2m"
	HELP_SECTION="${esc}[1;36m"
	HELP_CMD="${esc}[32m"
	HELP_OPT="${esc}[33m"
	HELP_ARG="${esc}[36m"
}

help_title() {
	printf '%s%s%s\n\n' "$HELP_BOLD" "$1" "$HELP_RESET"
}

help_heading() {
	printf '%s%s%s\n' "$HELP_SECTION" "$1" "$HELP_RESET"
}

help_usage_group() {
	printf '\n  %s%s%s\n' "$HELP_BOLD" "$1" "$HELP_RESET"
}

help_usage() {
	printf '    %sgit-nest%s %s%s%s' "$HELP_DIM" "$HELP_RESET" "$HELP_CMD" "$1" "$HELP_RESET"
	[ -n "${2:-}" ] && printf ' %s' "$2"
	printf '\n'
}

help_command_group() {
	printf '\n  %s%s%s\n' "$HELP_BOLD" "$1" "$HELP_RESET"
}

help_command() {
	printf '    %s%s%s\n' "$HELP_CMD" "$1" "$HELP_RESET"
}

help_text() {
	printf '        %s\n' "$1"
}

help_detail() {
	printf '            %s\n' "$1"
}

# Show the command surface exposed by the shared implementation.
usage() {
	help_setup_colors
	help_title "git-nest: record and restore reproducible nests of independent Git repositories"
	printf '%s%s%s\n\n' "$HELP_DIM" "Latest version: https://github.com/f-steff/git-nest" "$HELP_RESET"

	help_heading "Usage:"
	help_usage_group "Nest setup"
	help_usage "init" "[--rc] [--sure]"
	help_usage "tidy" "[--rc]"
	help_usage "clone" "<nest-repo-url> [target-dir] [--no-restore] [--depth <n>] [--branch <branch>] [--single-branch]"

	help_usage_group "Subprojects"
	help_usage "add" "[--clone <full|partial|shallow>] [--depth <n>] <repo> <path>"
	help_usage "remove|rm" "<path> [--force] [--dry-run] [--json|--json-pretty]"
	help_usage "detach" "<path> [--dry-run] [--json|--json-pretty]"
	help_usage "move|mv" "<old-path> <new-path> [--force]"
	help_usage "move|mv" "--url <new-url> <path>"
	help_usage "config" "<get|set|list|unset> ..."
	help_usage "update" "<subproject> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]"

	help_usage_group "Workspace state"
	help_usage "restore" "[--recursive] [--prune] [--force] [--dry-run] [--depth <n>]"
	help_usage "pull" "[--recursive] [--sure] [--no-fetch] [--dry-run] [--json | --json-pretty]"
	help_usage "snapshot" "[<path>] [--recursive] [--quiet] [--dry-run] [--check] [--strict] [--no-fetch]"
	help_usage "freeze" "[--force] [--only <path>[,<path>...]] [--dry-run]"
	help_usage "gc" "[--aggressive] [--dry-run] [--json | --json-pretty]"

	help_usage_group "Inspection"
	help_usage "status" "[--recursive] [--porcelain | --json | --json-pretty] [--exit-code]"
	help_usage "outdated" "[--recursive] [--porcelain | --json | --json-pretty]"
	help_usage "verify" "[--recursive] [--json | --json-pretty]"
	help_usage "diff" "[--since <ref>] [--stat] [--json | --json-pretty]"
	help_usage "log" "[--max-count <n>] [--since <date>] [--until <date>] [--subproject <path>] [--oneline] [--recursive]"
	help_usage "list" "[--porcelain | --json | --json-pretty] [--redact]"
	help_usage "tree" "[--all] [--recursive] [--plain] [--json | --json-pretty]"
	help_usage "survey" "[--exclude <name>]... [--include <path>]... [--max-depth <n>] [--porcelain | --json | --json-pretty]"
	help_usage "doctor" "[--json | --json-pretty] [--online | --offline] [--timeout <seconds>] [--exit-code] [--redact]"

	help_usage_group "Branch bookmarks"
	help_usage "branch-mark" "[name]"
	help_usage "branch-unmark" "<name>"
	help_usage "branch-list" "[--verbose|--json]"
	help_usage "branch-cleanup"

	help_usage_group "Hooks"
	help_usage "hooks-install"
	help_usage "hooks-uninstall"

	help_usage_group "Iteration"
	help_usage "foreach" "[--include-root-first|--include-root-last] [--only-nested|--no-nested] [--] <command> [args...]"
	help_usage "foreach-modified" "[--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"
	help_usage "foreach-clean" "[--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"

	help_usage_group "Export and nest membership"
	help_usage "export" "--output <path> [--format <tar.gz|zip|dir>] [--include-git] [--deterministic] [--allow-dirty]"
	help_usage "absorb" "<path> [<remote-url>] [--branch <name>] [--clone-mode <full|partial>] [--preserve-history] [--push] [--message <msg>] [--force] [--dry-run] [--json|--json-pretty]"
	help_usage "absorb" "--subrepo <path> [<remote-url>] [--force] [--dry-run] [--json|--json-pretty]"
	help_usage "absorb" "--subtree <path> <remote-url> [--branch <name>] [--message <msg>] [--force] [--dry-run] [--json|--json-pretty]"
	help_usage "absorb-all" "[--sure] [--force-partial] [--dry-run] [--exclude <name>]... [--include <path>]... [--max-depth <n>] [--json|--json-pretty]"
	help_usage "inline" "<path> [--commit] [--message <msg>] [--dry-run] [--json|--json-pretty]"

	help_usage_group "Tooling"
	help_usage "completion" "<bash|zsh|fish>"
	help_usage "version"

	printf '\n'
	help_heading "Commands:"
	help_command_group "Nest setup"
	help_command "init [--rc]"
	help_text "Create a new .gitnest manifest at the current Git root or directory."
	help_detail "--rc also creates .gitnest-rc with default values."
	help_detail "--sure allows intentional nested-nest creation inside an existing nest."
	help_detail "Existing nest roots are reported as already initialized; use tidy to refresh support files."
	help_command "tidy [--rc]"
	help_text "Tidy managed support files for the current nest."
	help_detail "Can be run from anywhere inside the nest."
	help_command "clone <nest-repo-url> [target-dir] [--no-restore] [--depth <n>] [--branch <branch>] [--single-branch]"
	help_text "Run git clone for a nest repository and restore when it has a manifest."
	help_detail "Convenience wrapper around git clone plus git-nest restore."
	help_detail "It does not copy an existing local checkout."
	help_detail "--no-restore skips the automatic restore."

	help_command_group "Subprojects"
	help_command "add [--clone <full|partial|shallow>] [--depth <n>] <repo> <path>"
	help_text "Add and clone a subproject, ignore its path in the outer repo, and"
	help_text "record its current target branch and revision."
	help_detail "<path> is relative to the current nest root; . is not valid here."
	help_detail "--clone selects full, partial (blobless), or shallow clone storage for this subproject."
	help_detail "--depth specifies the clone depth (default 1 for shallow; ignored for full/partial)."
	help_detail "This clone mode is used by restore and is unrelated to the clone command."
	help_command "remove|rm <path> [--force] [--dry-run] [--json|--json-pretty]"
	help_text "Remove a subproject from the nest and delete its checkout on disk."
	help_detail "<path> is a managed subproject path relative to the current nest root."
	help_detail "--force skips dirty/current-branch safety checks."
	help_detail "The remote is never touched; to keep the checkout use detach instead."
	help_command "detach <path> [--dry-run] [--json|--json-pretty]"
	help_text "Remove a subproject from the nest but keep its checkout as a standalone repo."
	help_detail "<path> is a managed subproject path relative to the current nest root."
	help_detail "Keeps the files and the ignore entry; the remote is never touched."
	help_command "move|mv <old-path> <new-path> [--force]"
	help_text "Move a subproject path while preserving manifest state."
	help_detail "Both paths are relative to the current nest root; . is not valid here."
	help_detail "--force skips dirty/current-branch safety checks."
	help_command "move|mv --url <new-url> <path>"
	help_text "Change a subproject repository URL in the manifest only."
	help_detail "<path> is a managed subproject path relative to the current nest root."
	help_command "config <get|set|list|unset> ..."
	help_text "Read or update allowlisted manifest settings."
	help_detail "Subproject paths are relative to the current nest root."
	help_detail "Only clone-mode is currently configurable; values are full, partial, or shallow."
	help_detail "clone-mode controls future restore clones, not the clone command."
	help_detail "config list shows explicitly set config values only."
	help_command "update <subproject> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]"
	help_text "Move one clean subproject to a selected revision."
	help_detail "<subproject> is a managed path in the current nest; . is not valid here."
	help_detail "--remote and --target-head use the target branch head."
	help_detail "--revision pins an explicit commit-ish."
	help_detail "--tag pins a tag and records the tag name."
	help_detail "--branch retargets before resolving the selected revision."
	help_detail "--no-fetch resolves only local refs."

	help_command_group "Workspace state"
	help_command "restore [--recursive] [--prune] [--force] [--dry-run] [--depth <n>]"
	help_text "Clone/fetch subprojects and restore the manifest state on disk."
	help_detail "Operates on the whole current nest; it does not accept a path."
	help_detail "--recursive includes nested projects."
	help_detail "--prune removes stale local-state paths after review when suggested."
	help_detail "--force proceeds when a tag moved away from the recorded revision."
	help_detail "--depth overrides per-project clone depth for shallow subprojects."
	help_detail "--dry-run prints planned clone/fetch/checkout/prune actions without writing."
	help_command "pull [--recursive] [--sure] [--no-fetch] [--dry-run] [--json|--json-pretty]"
	help_text "Fast-forward clean subprojects to their upstream branch heads and snapshot."
	help_detail "Default pull only subprojects; --sure also pulls the nest root."
	help_detail "--recursive includes nested nests."
	help_detail "--no-fetch uses local refs only."
	help_detail "--dry-run prints planned pull actions without writing."
	help_detail "--json and --json-pretty print machine-readable dry-run output."
	help_command "snapshot [<path>] [--recursive] [--quiet] [--dry-run] [--check] [--strict] [--no-fetch]"
	help_text "Record clean, reproducible checked-out subproject commits in .gitnest."
	help_detail "No path snapshots all subprojects in the current nest."
	help_detail "At the nest root, . also means all subprojects."
	help_detail "Inside a managed subproject, . means that subproject only."
	help_detail "An explicit path may name a managed subproject or a path inside one."
	help_detail "--recursive includes nested projects."
	help_detail "--quiet suppresses skip warnings for dirty subprojects."
	help_detail "--dry-run prints planned manifest changes without writing."
	help_detail "--check reports stale state without writing."
	help_detail "--strict returns nonzero for dirty or unreproducible subprojects."
	help_detail "--no-fetch uses local refs only."
	help_command "freeze [--force] [--only <path>[,<path>...]] [--dry-run]"
	help_text "Pin tracked subprojects to their current checkout commits."
	help_detail "Without --only, freezes every tracked subproject in the current nest."
	help_detail "--only limits freezing to a comma-separated path list."
	help_detail "--force freezes dirty subprojects with warnings."
	help_detail "--dry-run prints what would change without writing."
	help_command "gc [--aggressive] [--dry-run] [--json | --json-pretty]"
	help_text "Run git gc in the nest root and every checked-out subproject."
	help_detail "--aggressive passes --aggressive to git gc."
	help_detail "--dry-run prints planned gc actions without running."
	help_detail "--json and --json-pretty print machine-readable output."

	help_command_group "Inspection"
	help_command "status [--recursive] [--porcelain | --json | --json-pretty] [--exit-code]"
	help_text "Show nest root and subproject state."
	help_detail "--recursive includes nested projects."
	help_detail "--porcelain prints stable fixed-column records for scripts."
	help_detail "--json and --json-pretty print machine-readable output."
	help_detail "--exit-code returns 1 when dirty or missing rows exist."
	help_command "outdated [--recursive] [--porcelain | --json | --json-pretty]"
	help_text "Check subproject remotes for newer target-branch commits without fetching."
	help_detail "--recursive includes nested projects."
	help_detail "--porcelain prints stable fixed-column records for scripts."
	help_detail "--json and --json-pretty print machine-readable output."
	help_command "verify [--recursive] [--json | --json-pretty]"
	help_text "Validate manifest, remotes, refs, clone mode, and checked-out revisions."
	help_detail "--recursive includes nested projects."
	help_detail "--json and --json-pretty print machine-readable output."
	help_command "diff [--since <ref>] [--stat] [--json | --json-pretty]"
	help_text "Show subproject commits between manifest revisions and current checkouts."
	help_detail "--since reads manifest revisions from the outer repo at ref."
	help_detail "--stat includes file statistics in human output."
	help_detail "--json and --json-pretty print machine-readable commit rows."
	help_command "log [--max-count <n>] [--since <date>] [--until <date>] [--subproject <path>] [--oneline] [--recursive]"
	help_text "Show combined nest history. Filters mirror common git log concepts;"
	help_detail "--max-count limits commits per repository before the final sort."
	help_detail "--since and --until filter commits by date."
	help_detail "--subproject restricts output to one subproject path."
	help_detail "--oneline uses compact commit output."
	help_detail "--recursive includes nested projects."
	help_command "list [--porcelain | --json | --json-pretty] [--redact]"
	help_text "List managed subprojects with URL, target branch, revision, tag, state, and reproducibility."
	help_detail "Stable order for scripts; --porcelain and --json/--json-pretty print machine-readable output."
	help_command "tree [--all] [--recursive] [--plain] [--json | --json-pretty]"
	help_text "Display an ASCII-art tree of the nest, grouped by shared path prefixes."
	help_detail "--all also shows survey's own detected-but-unmanaged findings, marked with their code."
	help_detail "--recursive also descends into nested nests, rendering their subprojects nested under that branch."
	help_detail "--plain omits the URL and type columns, showing only the tree structure with [code] markers."
	help_command "survey [--exclude <name>]... [--include <path>]... [--max-depth <n>] [--porcelain | --json | --json-pretty]"
	help_text "Scan for nested Git repositories, submodules, and git-subrepos not managed by .gitnest."
	help_detail "Bounded by --max-depth (default 4) and pruned by default and extra --exclude directory names."
	help_detail "--include narrows the scan to one or more paths instead of the whole tree."
	help_detail "Detection only; it never adds, syncs, or registers anything. Use absorb-all to act on it."
	help_command "doctor [--json | --json-pretty] [--online | --offline] [--timeout <seconds>] [--exit-code] [--redact]"
	help_text "Report environment and workspace health without modifying files."
	help_detail "Can be run from anywhere inside the nest."
	help_detail "By default contacts subproject remotes; use --offline to skip remote checks."
	help_detail "Remote check timeout uses GIT_NEST_DOCTOR_TIMEOUT_SECONDS or 5 seconds."

	help_command_group "Branch bookmarks"
	help_command "branch-mark|branch-unmark|branch-list|branch-cleanup"
	help_text "Manage local branch-name memory for the current nest. These commands do"
	help_text "not create, switch, push, or delete Git branches."
	help_detail "branch-mark with no name uses the current Git branch."
	help_detail "Marks are stored in .gitnest-branches and ignored by Git."

	help_command_group "Hooks"
	help_command "hooks-install"
	help_text "Install managed local Git hooks in all checked-out repositories in the current nest."
	help_detail "Includes the nest root and checked-out subprojects; it is not recursive into nested nests."
	help_command "hooks-uninstall"
	help_text "Remove managed local Git hooks from all checked-out repositories in the current nest."

	help_command_group "Iteration"
	help_command "foreach [--include-root-first|--include-root-last] [--] <command> [args...]"
	help_text "Run a command in every checked-out subproject in the current nest."
	help_command "foreach-modified [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"
	help_text "Run a command in dirty subprojects, or list them with machine output."
	help_command "foreach-clean [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"
	help_text "Run a command in clean checked-out subprojects, or list them with machine output."

	help_command_group "Export and outer-repo conversion"
	help_command "export --output <path> [--format <tar.gz|zip|dir>] [--include-git] [--deterministic] [--allow-dirty]"
	help_text "Export a source snapshot with .gitnest and MANIFEST.lock."
	help_detail "dir output uses shell file copy; tar.gz requires system tar; zip requires python or python3."
	help_detail "--format overrides output extension inference."
	help_detail "--include-git keeps nested .git directories."
	help_detail "--deterministic normalizes archive ordering and metadata where supported."
	help_detail "--allow-dirty permits dirty subproject working trees."
	help_command "absorb <path> [<remote-url>] [options]"
	help_text "Bring something already on disk into the nest as a managed subproject."
	help_detail "Auto-detects the source: outer-repo tracked files, a standalone nested repo, or a submodule."
	help_detail "Outer-repo files require a remote URL and support --branch, --clone-mode, --preserve-history, --push, --message, and --force."
	help_detail "An existing repo or submodule keeps its own history and records its own remote."
	help_detail "Refuses a path that is already a subproject and refuses deeper nested repos/submodules."
	help_detail "--subrepo and --subtree are explicit, never auto-detected; both are forward-only conversions with no history reconstruction."
	help_detail "--dry-run reports planned changes without writing; --json/--json-pretty print machine output."
	help_command "absorb-all [--sure] [--force-partial] [--dry-run] [options]"
	help_text "Scan like survey, then absorb every detected submodule and nested repo in one step."
	help_detail "Never absorbs git-subrepos or subtrees; those stay a conscious absorb --subrepo/--subtree action."
	help_detail "--sure confirms creating or extending a nest here; --force-partial skips rollback on a mid-batch failure."
	help_command "inline <path> [options]"
	help_text "Dissolve a managed subproject into the outer repo as ordinary tracked files."
	help_detail "This removes the subproject from the current nest and stages its files in the nest root."
	help_detail "--commit commits the staged outer-repo changes."
	help_detail "--message sets the commit message and implies --commit."
	help_detail "--dry-run reports planned changes without writing; --json/--json-pretty print machine output."

	help_command_group "Tooling"
	help_command "completion <bash|zsh|fish>"
	help_text "Print a shell completion script to stdout."
	help_command "version"
	help_text "Print the git-nest version."

	printf '\nManifest: %s\n' "$MANIFEST_FILE"
}

help_example() {
	printf '        %s%s%s\n' "$HELP_DIM" "$1" "$HELP_RESET"
}

help_opposite() {
	printf '        Opposite: %s\n' "$1"
}

command_help_branch_bookmarks() {
	help_command "branch-mark [name]"
	help_command "branch-unmark <name>"
	help_command "branch-list [--verbose|--json]"
	help_command "branch-cleanup"
	help_text "Branch bookmarks remember useful branch names for the current nest."
	help_text "They do not create, switch, push, delete, or otherwise manage Git branches."
	help_text "They are local helper state for humans and scripts that want to reuse the"
	help_text "same branch name in more than one repository."
	help_detail "branch-mark with no name records the current Git branch for the current repository."
	help_detail "branch-unmark removes one remembered branch name for the current repository."
	help_detail "branch-list shows remembered names and, with --verbose, the origin repository path."
	help_detail "branch-cleanup removes bookmarks whose local Git branch no longer exists."
	help_detail "Bookmarks are stored in .gitnest-branches and ignored by Git."
	help_heading "Examples:"
	help_example "git switch -c feature/cache"
	help_example "git-nest branch-mark"
	help_example "git-nest branch-list --verbose"
	help_example "git-nest branch-unmark feature/cache"
}

command_help() {
	topic=$1
	case "$topic" in
	rm) topic=remove ;;
	mv) topic=move ;;
	sync) topic=restore ;;
	install-hooks) topic=hooks-install ;;
	remove-hooks) topic=hooks-uninstall ;;
	extract) topic=absorb ;;
	esac

	help_setup_colors
	help_title "git-nest help: $topic"
	printf '%s%s%s\n\n' "$HELP_DIM" "Latest version: https://github.com/f-steff/git-nest" "$HELP_RESET"

	case "$topic" in
	init)
		help_command "init [--rc] [--sure]"
		help_text "Create a new .gitnest manifest at the current Git root or current directory."
		help_text "Plain init is creation-only. Use tidy for an existing nest."
		help_detail "--rc also creates .gitnest-rc with default values."
		help_detail "--sure confirms intentional nested-nest creation inside an existing nest."
		help_heading "Examples:"
		help_example "git init"
		help_example "git-nest init"
		help_example "git-nest init --rc"
		help_example "git-nest init --sure"
		help_opposite "tidy refreshes support files for a nest that already exists."
		;;
	tidy)
		help_command "tidy [--rc]"
		help_text "Tidy managed support files for the current nest without creating a new nest."
		help_text "Can be run from anywhere inside the nest."
		help_detail "Refreshes files such as .gitattributes and managed ignore entries."
		help_detail "--rc also creates or refreshes .gitnest-rc defaults."
		help_heading "Examples:"
		help_example "git-nest tidy"
		help_example "git-nest tidy --rc"
		help_opposite "init creates a new nest when one does not already exist."
		;;
	clone)
		help_command "clone <nest-repo-url> [target-dir] [--no-restore] [--depth <n>] [--branch <branch>] [--single-branch]"
		help_text "Run git clone for a nest repository, then restore it when .gitnest exists."
		help_detail "This is a convenience wrapper around git clone plus git-nest restore."
		help_detail "It does not copy an existing local checkout."
		help_detail "--no-restore leaves subprojects missing until restore is run manually."
		help_detail "--depth, --branch, and --single-branch are passed to the outer git clone."
		help_heading "Examples:"
		help_example "git-nest clone https://example.invalid/product.git"
		help_example "git-nest clone https://example.invalid/product.git product --branch main"
		help_example "git-nest clone https://example.invalid/product.git --no-restore"
		help_opposite "restore materializes subprojects after an ordinary git clone."
		;;
	add)
		help_command "add [--clone <full|partial|shallow>] [--depth <n>] <repo> <path>"
		help_text "Add and clone a subproject into the current nest."
		help_detail "<path> is relative to the current nest root; . is not valid."
		help_detail "The path is ignored by the outer repository so files stay owned by the subproject."
		help_detail "--clone records full, partial (blobless), or shallow clone preference for future restore."
		help_detail "--depth specifies the clone depth (default 1 for shallow; ignored for full/partial)."
		help_detail "This clone mode is unrelated to the clone command."
		help_heading "Examples:"
		help_example "git-nest add https://example.invalid/libs/foo.git libs/foo"
		help_example "git-nest add --clone partial https://example.invalid/libs/big.git libs/big"
		help_example "git-nest add --clone shallow --depth 5 https://example.invalid/tip-only.git libs/tip"
		help_opposite "remove/rm removes a managed subproject from the nest."
		;;
	remove)
		help_command "remove|rm <path> [--force] [--dry-run] [--json|--json-pretty]"
		help_text "Remove a managed subproject from the nest and delete its checkout on disk."
		help_detail "<path> is relative to the current nest root."
		help_detail "--force skips dirty/current-branch safety checks."
		help_detail "The remote is never touched. To keep the checkout, use detach instead."
		help_heading "Examples:"
		help_example "git-nest remove libs/foo"
		help_example "git-nest remove libs/foo --force"
		help_example "git-nest remove libs/foo --dry-run"
		help_opposite "add records and clones a subproject into the nest."
		;;
	detach)
		help_command "detach <path> [--dry-run] [--json|--json-pretty]"
		help_text "Remove a managed subproject from the nest but keep its checkout as a standalone repo."
		help_detail "<path> is relative to the current nest root."
		help_detail "Keeps the files on disk and keeps the ignore entry; the remote is never touched."
		help_detail "Does not rebuild a submodule/subtree/subrepo; it only guarantees a standalone repo remains."
		help_heading "Examples:"
		help_example "git-nest detach libs/foo"
		help_example "git-nest detach libs/foo --dry-run"
		help_opposite "absorb brings an existing repository into the nest."
		;;
	move)
		help_command "move|mv <old-path> <new-path> [--force]"
		help_command "move|mv --url <new-url> <path>"
		help_text "Move a managed subproject path, or retarget its recorded URL."
		help_detail "Paths are relative to the current nest root; . is not valid."
		help_detail "Path moves update the checkout location, .gitnest, and ignore hygiene."
		help_detail "--url changes only the manifest URL and does not move files."
		help_heading "Examples:"
		help_example "git-nest move libs/foo components/foo"
		help_example "git-nest mv libs/foo components/foo --force"
		help_example "git-nest move --url https://example.invalid/new/foo.git components/foo"
		help_opposite "remove/rm detaches a subproject instead of moving it."
		;;
	config)
		help_command "config <get|set|list|unset> ..."
		help_text "Read or update allowlisted manifest settings."
		help_detail "Subproject paths are relative to the current nest root."
		help_detail "Only clone-mode is currently configurable."
		help_detail "clone-mode values are full, partial, or shallow."
		help_detail "clone-mode controls future restore clones, not the clone command."
		help_detail "config list shows explicitly set config values only."
		help_detail "Unknown keys such as repo are rejected for get, set, and unset."
		help_heading "Examples:"
		help_example "git-nest config list"
		help_example "libs/foo    clone-mode=partial"
		help_example "git-nest config get libs/foo clone-mode"
		help_example "partial"
		help_example "git-nest config set libs/foo clone-mode partial"
		help_example "git-nest config unset libs/foo clone-mode"
		help_example "git-nest config unset libs/foo repo"
		help_example "Error: unknown config key: repo"
		;;
	update)
		help_command "update <subproject> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]"
		help_text "Move one clean managed subproject to a selected revision."
		help_detail "<subproject> is relative to the current nest root; . is not valid."
		help_detail "--remote and --target-head use the target branch head."
		help_detail "--revision pins an explicit commit-ish."
		help_detail "--tag pins a tag and records the tag name."
		help_detail "--branch retargets before resolving the selected revision."
		help_heading "Examples:"
		help_example "git-nest update libs/foo --remote"
		help_example "git-nest update libs/foo --revision abc1234"
		help_example "git-nest update libs/foo --tag v1.2.3"
		help_opposite "restore returns subprojects to the manifest state instead of advancing one."
		;;
	restore)
		help_command "restore [--recursive] [--prune] [--force] [--dry-run] [--depth <n>]"
		help_text "Clone, fetch, and check out the manifest state on disk."
		help_detail "Operates on the whole current nest; it does not accept a path."
		help_detail "--recursive includes nested nests."
		help_detail "--prune removes reviewed stale local-state paths."
		help_detail "--force proceeds when a tag moved away from the recorded revision."
		help_detail "--depth overrides per-project clone depth for shallow subprojects."
		help_detail "--dry-run shows planned clone/fetch/checkout/prune actions."
		help_heading "Examples:"
		help_example "git-nest restore"
		help_example "git-nest restore --dry-run"
		help_example "git-nest restore --recursive"
		help_opposite "snapshot records the current reproducible checkout state into .gitnest."
		;;
	pull)
		help_command "pull [--recursive] [--sure] [--no-fetch] [--dry-run] [--json|--json-pretty]"
		help_text "Fast-forward clean subprojects to their upstream branch heads and snapshot."
		help_detail "Without options, only clean subprojects that have upstream tracking are pulled."
		help_detail "Dirty subprojects, detached HEAD, and missing upstream branches are skipped."
		help_detail "--sure also pulls the nest root itself."
		help_detail "--recursive enters nested nests and runs pull inside each."
		help_detail "--no-fetch uses local refs only without contacting remotes."
		help_detail "--dry-run shows planned actions without changing checkouts."
		help_detail "--json and --json-pretty print machine-readable dry-run output."
		help_heading "Examples:"
		help_example "git-nest pull"
		help_example "git-nest pull --recursive"
		help_example "git-nest pull --sure"
		help_example "git-nest pull --dry-run"
		help_example "git-nest pull --no-fetch"
		help_opposite "update moves one subproject to a selected remote/tag/revision."
		;;
	snapshot)
		help_command "snapshot [<path>] [--recursive] [--quiet] [--dry-run] [--check] [--strict] [--no-fetch]"
		help_text "Record clean, reproducible checked-out subproject commits in .gitnest."
		help_detail "No path snapshots all subprojects in the current nest."
		help_detail "At the nest root, . also means all subprojects."
		help_detail "Inside a managed subproject, . means that subproject only."
		help_detail "An explicit path may name a managed subproject or a path inside one."
		help_detail "--check reports stale state without writing."
		help_detail "--strict returns nonzero for dirty or unreproducible subprojects."
		help_heading "Examples:"
		help_example "git-nest snapshot"
		help_example "git-nest snapshot ."
		help_example "git-nest snapshot libs/foo --dry-run"
		help_example "git-nest snapshot --check --strict"
		help_opposite "restore materializes the recorded manifest state on disk."
		;;
	freeze)
		help_command "freeze [--force] [--only <path>[,<path>...]] [--dry-run]"
		help_text "Pin tracked subprojects to their current checkout commits."
		help_detail "Without --only, freezes every tracked subproject in the current nest."
		help_detail "--only limits freezing to a comma-separated path list."
		help_detail "--force freezes dirty subprojects with warnings."
		help_heading "Examples:"
		help_example "git-nest freeze"
		help_example "git-nest freeze --only libs/foo,libs/bar"
		help_example "git-nest freeze --dry-run"
		help_opposite "update moves one subproject to a selected remote/tag/revision."
		;;
	gc)
		help_command "gc [--aggressive] [--dry-run] [--json | --json-pretty]"
		help_text "Run git gc in the nest root and every checked-out subproject."
		help_detail "Without --aggressive, runs plain git gc."
		help_detail "--aggressive passes --aggressive to git gc."
		help_detail "--dry-run prints planned gc actions without running."
		help_detail "--json and --json-pretty print machine-readable output."
		help_heading "Examples:"
		help_example "git-nest gc"
		help_example "git-nest gc --aggressive"
		help_example "git-nest gc --dry-run"
		;;
	status)
		help_command "status [--recursive] [--porcelain | --json | --json-pretty] [--exit-code]"
		help_text "Show nest root and subproject state."
		help_detail "--recursive includes nested nests."
		help_detail "--porcelain prints stable fixed-column records for scripts."
		help_detail "--json and --json-pretty print machine-readable output."
		help_detail "--exit-code returns 1 when dirty or missing rows exist."
		help_heading "Examples:"
		help_example "git-nest status"
		help_example "git-nest status --recursive"
		help_example "git-nest status --porcelain --exit-code"
		;;
	outdated)
		help_command "outdated [--recursive] [--porcelain | --json | --json-pretty]"
		help_text "Check subproject remotes for newer target-branch commits without changing checkouts."
		help_detail "--recursive includes nested nests."
		help_detail "This is an inspection command; use update when you choose to move a subproject."
		help_heading "Examples:"
		help_example "git-nest outdated"
		help_example "git-nest outdated --recursive"
		help_example "git-nest outdated --json-pretty"
		help_opposite "update performs a selected subproject move after inspection."
		;;
	verify)
		help_command "verify [--recursive] [--json | --json-pretty]"
		help_text "Validate manifest entries, remotes, refs, clone mode, and checkout drift."
		help_detail "--recursive includes nested nests."
		help_heading "Examples:"
		help_example "git-nest verify"
		help_example "git-nest verify --recursive"
		help_example "git-nest verify --json-pretty"
		;;
	diff)
		help_command "diff [--since <ref>] [--stat] [--json | --json-pretty]"
		help_text "Show subproject commits between manifest revisions and current checkouts."
		help_detail "--since reads manifest revisions from the outer repo at ref."
		help_detail "--stat includes file statistics in human output."
		help_heading "Examples:"
		help_example "git-nest diff"
		help_example "git-nest diff --since HEAD~1"
		help_example "git-nest diff --stat"
		;;
	log)
		help_command "log [--max-count <n>] [--since <date>] [--until <date>] [--subproject <path>] [--oneline] [--recursive]"
		help_text "Show combined nest history across the nest root and checked-out subprojects."
		help_detail "--subproject restricts output to one subproject path."
		help_detail "--recursive includes nested nests."
		help_heading "Examples:"
		help_example "git-nest log --max-count 10"
		help_example "git-nest log --subproject libs/foo --oneline"
		help_example "git-nest log --recursive --since 2026-01-01"
		;;
	doctor)
		help_command "doctor [--json | --json-pretty] [--online | --offline] [--timeout <seconds>] [--exit-code] [--redact]"
		help_text "Report environment and workspace health without modifying files."
		help_detail "Can be run from anywhere inside the nest."
		help_detail "By default contacts subproject remotes; use --offline to skip remote checks."
		help_detail "--online is the explicit default and does the same as bare doctor."
		help_detail "--timeout overrides GIT_NEST_DOCTOR_TIMEOUT_SECONDS for remote checks."
		help_detail "--exit-code returns nonzero when warnings or errors are present."
		help_detail "--redact strips credentials from URLs and the home directory from paths in the output."
		help_heading "Examples:"
		help_example "git-nest doctor --offline"
		help_example "git-nest doctor --online"
		help_example "git-nest doctor --json-pretty --redact"
		;;
	list)
		help_command "list [--porcelain | --json | --json-pretty] [--redact]"
		help_text "List managed subprojects in a stable order with their recorded and on-disk state."
		help_detail "Shows path, repository URL, target branch, revision, tag, checkout state, and reproducibility."
		help_detail "The leading code is reproducibility: R reproducible, D drift, M missing, U unpinned."
		help_detail "--porcelain prints fixed-column records; --json/--json-pretty print machine-readable output."
		help_detail "--redact strips credentials from URLs and the home directory from paths in the output."
		help_heading "Examples:"
		help_example "git-nest list"
		help_example "git-nest list --porcelain"
		help_example "git-nest list --json-pretty --redact"
		help_detail "status stays focused on workspace health; use list for a scriptable inventory."
		;;
	tree)
		help_command "tree [--all] [--recursive] [--plain] [--porcelain | --json | --json-pretty]"
		help_text "Display an ASCII-art tree of the current nest, grouped by shared path prefixes."
		help_detail "Plain: every managed subproject, as a branch from the nest root."
		help_detail "--all also shows survey's own detected-but-unmanaged findings (submodules, nested repos, git-subrepos, nest roots, detached former subprojects), each marked with its code."
		help_detail "--recursive also descends into nested nests, rendering their own subprojects nested under that branch."
		help_detail "--plain omits URL and type columns, showing only path and [code] marker."
		help_detail "Uses a single +-- connector for every branch and a trailing / on every entry; no Unicode box-drawing characters."
		help_detail "--porcelain prints stable fixed-column records for scripts."
		help_detail "--json/--json-pretty print the same shared row schema other inspection commands use."
		help_heading "Examples:"
		help_example "git-nest tree"
		help_example "git-nest tree --all"
		help_example "git-nest tree --all --recursive"
		help_example "git-nest tree --plain"
		help_example "git-nest tree --porcelain"
		help_opposite "list prints the same managed subprojects as a flat, scriptable table."
		;;
	survey)
		help_command "survey [--exclude <name>]... [--include <path>]... [--max-depth <n>] [--porcelain | --json | --json-pretty]"
		help_text "Scan the current nest for nested Git repositories, submodules, and git-subrepos not in .gitnest."
		help_detail "--max-depth bounds the scan depth (default 4)."
		help_detail "--exclude adds directory names to the default prune list; it may be repeated."
		help_detail "--include narrows the scan to one or more paths instead of the whole tree; it may be repeated."
		help_detail "The leading code is the kind: S submodule, R nested repo, U unmanaged nested nest root, D detached, G git-subrepo."
		help_detail "A path found inside a boundary this same scan already classified (a submodule, subrepo, nested repo, or nested nest) is never reported again on its own."
		help_detail "Detection only; it never adds, syncs, or registers repositories. Symlinked directories are not followed."
		help_heading "Examples:"
		help_example "git-nest survey"
		help_example "git-nest survey --max-depth 6 --exclude third_party"
		help_example "git-nest survey --include vendor --porcelain"
		help_opposite "absorb brings one discovered repository into the nest; absorb-all brings in every discovered submodule and nested repo at once."
		;;
	absorb-all)
		help_command "absorb-all [--sure] [--force-partial] [--dry-run] [--exclude <name>]... [--include <path>]... [--max-depth <n>] [--json|--json-pretty]"
		help_text "Scan like survey, then absorb every detected submodule and nested repo into the nest in one step."
		help_detail "Never absorbs git-subrepos or subtrees; those always require the explicit absorb --subrepo/--subtree action."
		help_detail "Never absorbs anything found inside a boundary the scan already classified (see survey's boundary rule)."
		help_detail "--sure confirms running init here if this is not yet a nest, or extending an existing nested nest; without it, either situation is refused."
		help_detail "Absorbs deepest paths first, so a nested repo is absorbed before any repo containing it."
		help_detail "On a mid-batch failure, every absorb already done in this run is rolled back by default; --force-partial skips the rollback and keeps what succeeded."
		help_detail "--exclude, --include, and --max-depth match survey exactly."
		help_detail "--dry-run reports the planned init/absorb actions without writing; --json/--json-pretty print machine output."
		help_heading "Examples:"
		help_example "git-nest absorb-all --dry-run"
		help_example "git-nest absorb-all --sure"
		help_example "git-nest absorb-all --include vendor --force-partial"
		help_opposite "survey reports the same candidates without acting on them."
		;;
	branch-mark | branch-unmark | branch-list | branch-cleanup)
		command_help_branch_bookmarks
		;;
	hooks-install)
		help_command "hooks-install"
		help_text "Install managed local Git hooks in all checked-out repositories in the current nest."
		help_detail "Includes the nest root and checked-out subprojects."
		help_detail "Does not accept --recursive; nested nests manage their own hooks."
		help_detail "Refuses to overwrite unmanaged hooks."
		help_heading "Examples:"
		help_example "git-nest hooks-install"
		help_example "git-nest doctor --offline"
		help_opposite "hooks-uninstall removes the managed local hooks."
		;;
	hooks-uninstall)
		help_command "hooks-uninstall"
		help_text "Remove managed local Git hooks from all checked-out repositories in the current nest."
		help_detail "Only git-nest-owned hook blocks are removed."
		help_detail "Does not accept --recursive; nested nests manage their own hooks."
		help_heading "Examples:"
		help_example "git-nest hooks-uninstall"
		help_example "git-nest doctor --offline"
		help_opposite "hooks-install installs the managed local hooks."
		;;
	foreach)
	help_command "foreach [--include-root-first|--include-root-last] [--only-nested|--no-nested] [--] <command> [args...]"
	help_text "Run a command in every checked-out subproject in the current nest."
	help_detail "The command runs inside each subproject checkout."
	help_detail "--include-root-first runs the command on the nest root before subprojects."
	help_detail "--include-root-last runs the command on the nest root after subprojects."
	help_detail "--only-nested limits execution to subprojects that are themselves git-nest workspaces."
	help_detail "--no-nested excludes nested nests, running only in plain subproject checkouts."
	help_detail "The -- separator is optional. Omit it for ordinary commands: git-nest foreach git status."
	help_detail "Use -- when the command starts with a word that could be confused with an option."
	help_heading "Examples:"
	help_example "git-nest foreach git status --short"
	help_example "git-nest foreach -- sh -c 'git rev-parse --show-toplevel'"
	help_example "git-nest foreach --include-root-last -- git add -A && git commit -m 'batch commit'"
	help_example "git-nest foreach --only-nested -- git status"
		;;
	foreach-modified)
		help_command "foreach-modified [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"
		help_text "Run a command in dirty checked-out subprojects, or list them."
		help_detail "Without a command, it reports the matching subprojects."
		help_detail "Machine-readable output cannot be combined with a command."
		help_heading "Examples:"
		help_example "git-nest foreach-modified"
		help_example "git-nest foreach-modified --porcelain"
		help_example "git-nest foreach-modified git status --short"
		help_example "git-nest foreach-modified --continue-on-error -- git status --short"
		help_opposite "foreach-clean selects clean checked-out subprojects."
		;;
	foreach-clean)
		help_command "foreach-clean [--continue-on-error] [--porcelain | --json | --json-pretty] [-- <command> [args...]]"
		help_text "Run a command in clean checked-out subprojects, or list them."
		help_detail "Without a command, it reports the matching subprojects."
		help_detail "Machine-readable output cannot be combined with a command."
		help_heading "Examples:"
		help_example "git-nest foreach-clean"
		help_example "git-nest foreach-clean --json-pretty"
		help_example "git-nest foreach-clean -- git fetch --all --prune"
		help_opposite "foreach-modified selects dirty checked-out subprojects."
		;;
	export)
		help_command "export --output <path> [--format <tar.gz|zip|dir>] [--include-git] [--deterministic] [--allow-dirty]"
		help_text "Export a source snapshot with .gitnest and MANIFEST.lock."
		help_detail "dir output uses shell file copy."
		help_detail "tar.gz output requires system tar."
		help_detail "zip output requires python or python3."
		help_detail "--allow-dirty permits dirty subproject working trees."
		help_heading "Examples:"
		help_example "git-nest export --output build/source.tar.gz --deterministic"
		help_example "git-nest export --output build/source.zip --format zip"
		help_example "git-nest export --output build/source-dir --format dir"
		;;
	absorb)
		help_command "absorb <path> [<remote-url>] [--branch <name>] [--clone-mode <full|partial>] [--preserve-history] [--push] [--message <msg>] [--force] [--dry-run] [--json|--json-pretty]"
		help_text "Bring something already on disk into the nest as a managed subproject."
		help_detail "Auto-detects the source: outer-repo tracked files, a standalone nested repo, or a submodule."
		help_detail "Outer-repo files require a remote URL; --branch, --clone-mode, --preserve-history, --push, --message, and --force apply to that source only."
		help_detail "An existing repo or submodule keeps its own history and records its own remote."
		help_detail "Refuses a path already tracked as a subproject and refuses deeper nested repos/submodules."
		help_detail "extract is the old name for the files source and now points here."
		help_heading "Examples:"
		help_example "git-nest absorb src/lib https://example.invalid/src-lib.git --push --message 'Create src-lib'"
		help_example "git-nest absorb libs/foo   # existing nested repo, uses its origin remote"
		help_example "git-nest absorb vendor/bar --dry-run   # a Git submodule"
		help_opposite "inline dissolves a subproject into outer files; detach keeps it as a standalone repo; remove deletes it."
		printf '\n'
		help_command "absorb --subrepo <path> [<remote-url>] [--force] [--dry-run] [--json|--json-pretty]"
		help_text "Bring a git-subrepo (a directory with a .gitrepo file) into the nest as a managed subproject."
		help_detail "Never auto-detected; requires the explicit --subrepo flag because it touches actual tracked files."
		help_detail "Reads the remote URL and branch from .gitrepo; pass <remote-url> to override the recorded remote."
		help_detail "Forward-only: the resulting subproject is a fresh single commit. The subrepo's own merge/split history in .gitrepo is not reconstructed."
		help_detail "Removes the .gitrepo file as part of the conversion."
		help_heading "Examples:"
		help_example "git-nest absorb --subrepo vendor/thing"
		help_example "git-nest absorb --subrepo vendor/thing --dry-run"
		printf '\n'
		help_command "absorb --subtree <path> <remote-url> [--branch <name>] [--message <msg>] [--force] [--dry-run] [--json|--json-pretty]"
		help_text "Bring a Git subtree (a plain tracked folder added with git subtree add) into the nest as a managed subproject."
		help_detail "Never auto-detected: a subtree has no marker file, so <remote-url> must always be supplied explicitly."
		help_detail "Forward-only: the resulting subproject is a fresh single commit. Prior subtree history is not carried across."
		help_heading "Examples:"
		help_example "git-nest absorb --subtree vendor/thing https://example.invalid/thing.git"
		help_example "git-nest absorb --subtree vendor/thing https://example.invalid/thing.git --dry-run"
		;;
	inline)
		help_command "inline <path> [--commit] [--message <msg>] [--dry-run] [--json|--json-pretty]"
		help_text "Dissolve a managed subproject into the outer repo as ordinary tracked files."
		help_detail "This removes the subproject from the current nest and stages its files in the nest root."
		help_detail "--message sets the commit message and implies --commit."
		help_detail "The subproject's own Git history is discarded; the remote is left untouched."
		help_heading "Examples:"
		help_example "git-nest inline libs/foo --dry-run"
		help_example "git-nest inline libs/foo --commit --message 'Inline foo'"
		help_opposite "absorb brings outer-repo files into the nest as a subproject."
		;;
	completion)
		help_command "completion <bash|zsh|fish>"
		help_text "Print a shell completion script to stdout."
		help_heading "Examples:"
		help_example "git-nest completion bash > ~/.local/share/bash-completion/completions/git-nest"
		help_example "git-nest completion zsh > ~/.zfunc/_git-nest"
		help_example "git-nest completion fish > ~/.config/fish/completions/git-nest.fish"
		;;
	version)
		help_command "version"
		help_text "Print the tool name, version, and logo."
		help_heading "Example:"
		help_example "git-nest version"
		;;
	help)
		help_command "help [command]"
		help_text "Show the grouped command overview or focused help for one command."
		help_detail "Alias topics such as rm, mv, sync, install-hooks, and remove-hooks point to their current command names."
		help_heading "Examples:"
		help_example "git-nest help"
		help_example "git-nest help snapshot"
		help_example "git-nest help branch-mark"
		;;
	*)
		usage_error "unknown help topic: $1"
		;;
	esac
}

cmd_help() {
	case $# in
	0) usage ;;
	1) command_help "$1" ;;
	*) usage_error "usage: git-nest help [command]" ;;
	esac
}

# Dispatch the public command name to the matching command handler.
git_nest_main() {
	cmd=${1:-}
	[ $# -gt 0 ] && shift || true

	# Intercept --help/-h on any command. Scan arguments before a -- separator
	# so git-nest foreach -- --help still runs --help inside each subproject.
	for gn_help_arg in "$@"; do
		case "$gn_help_arg" in
		--) break ;;
		--help | -h)
			command_help "$cmd"
			return
			;;
		esac
	done

	case "$cmd" in
	init)
		require_git
		cmd_init "$@"
		;;
	tidy)
		enter_project_root_required
		cmd_tidy "$@"
		;;
	add)
		enter_workspace_root_if_present
		cmd_add "$@"
		;;
	remove | rm)
		enter_project_root_required
		cmd_remove "$@"
		;;
	move | mv)
		enter_project_root_required
		cmd_mv "$@"
		;;
	clone) cmd_clone "$@" ;;
	status)
		enter_project_root_required
		cmd_status "$@"
		;;
	outdated)
		enter_project_root_required
		cmd_outdated "$@"
		;;
	available) usage_error "unknown command: available; use outdated" ;;
	verify)
		enter_project_root_required
		cmd_verify "$@"
		;;
	diff)
		enter_project_root_required
		cmd_diff "$@"
		;;
	log)
		enter_project_root_required
		cmd_log "$@"
		;;
	start) usage_error "unknown command: start; use Git branch commands and git-nest snapshot" ;;
	snapshot)
		enter_project_root_required
		cmd_snapshot "$@"
		;;
	refresh) usage_error "unknown command: refresh; use snapshot" ;;
	record) usage_error "unknown command: record; use snapshot" ;;
	upload) usage_error "unknown command: upload; use git push and git-nest snapshot" ;;
	freeze)
		enter_project_root_required
		cmd_freeze "$@"
		;;
	gc)
		enter_project_root_required
		cmd_gc "$@"
		;;
	hooks-install)
		enter_project_root_required
		cmd_hooks_install "$@"
		;;
	hooks-uninstall)
		enter_project_root_required
		cmd_hooks_uninstall "$@"
		;;
	install-hooks) usage_error "unknown command: install-hooks; use hooks-install" ;;
	remove-hooks) usage_error "unknown command: remove-hooks; use hooks-uninstall" ;;
	foreach)
		enter_project_root_required
		cmd_foreach "$@"
		;;
	foreach-pending) usage_error "unknown command: foreach-pending; pending manifest state is no longer supported" ;;
	foreach-modified)
		enter_project_root_required
		cmd_foreach_modified "$@"
		;;
	foreach-clean)
		enter_project_root_required
		cmd_foreach_clean "$@"
		;;
	no-pending) usage_error "unknown command: no-pending; pending manifest state is no longer supported" ;;
	config)
		enter_project_root_required
		cmd_config "$@"
		;;
	check) usage_error "unknown command: check; pending manifest state is no longer supported" ;;
	branch-mark)
		enter_project_root_required
		cmd_branch_mark "$@"
		;;
	branch-unmark)
		enter_project_root_required
		cmd_branch_unmark "$@"
		;;
	branch-list)
		enter_project_root_required
		cmd_branch_list "$@"
		;;
	branch-cleanup)
		enter_project_root_required
		cmd_branch_cleanup "$@"
		;;
	update)
		enter_project_root_required
		cmd_update "$@"
		;;
	finalize) usage_error "unknown command: finalize; use git-nest snapshot to record reproducible revisions" ;;
	cleanup-branches) usage_error "unknown command: cleanup-branches; git-nest no longer deletes Git branches" ;;
	restore)
		enter_project_root_required
		cmd_restore "$@"
		;;
	sync) usage_error "unknown command: sync; use restore" ;;
	pull)
		enter_project_root_required
		cmd_pull "$@"
		;;
	doctor) cmd_doctor "$@" ;;
	discover) usage_error "unknown command: discover; use git-nest survey" ;;
	repair) usage_error "unknown command: repair; use git-nest tidy" ;;
	survey)
		enter_project_root_required
		cmd_survey "$@"
		;;
	absorb-all)
		require_git
		GIT_NEST_CALLER_PWD=$(pwd -P)
		cmd_absorb_all "$@"
		;;
	list)
		enter_project_root_required
		cmd_list "$@"
		;;
	tree)
		enter_project_root_required
		cmd_tree "$@"
		;;
	completion) cmd_completion "$@" ;;
	export)
		enter_project_root_required
		cmd_export "$@"
		;;
	absorb)
		enter_project_root_required
		cmd_absorb "$@"
		;;
	inline)
		enter_project_root_required
		cmd_inline "$@"
		;;
	detach)
		enter_project_root_required
		cmd_detach "$@"
		;;
	extract) usage_error "unknown command: extract; use git-nest absorb to bring files, repositories, or submodules into the nest" ;;
	__complete) cmd_internal_complete "$@" ;;
	__owning-manifest) cmd_internal_owning_manifest "$@" ;;
	__hook)
		enter_project_root_required
		cmd_internal_hook "$@"
		;;
	version | --version | -v) cmd_version "$@" ;;
	help) cmd_help "$@" ;;
	-h | --help | "") usage ;;
	*) usage_error "unknown command: $cmd" ;;
	esac
}

# Report the implemented tool version used by docs and tests.
cmd_version() {
	[ $# -eq 0 ] || die "version takes no arguments"
	printf 'git-nest %s \\\\_oOO_//\n' "$GIT_NEST_VERSION"
}

cmd_internal_owning_manifest() {
	[ $# -le 1 ] || usage_error "usage: git-nest __owning-manifest [path]"
	find_owning_manifest "$@"
}
find_legacy_manifest_root() {
	dir=$(pwd)
	while :; do
		if [ -f "$dir/.stack" ]; then
			printf '%s\n' "$dir"
			return 0
		fi
		parent=$(dirname "$dir")
		[ "$parent" != "$dir" ] || return 1
		dir=$parent
	done
}

# Walk upward to find the nearest owning manifest. This never walks downward;
# recursive operations use purpose-specific traversal helpers.

# Commands that can create a workspace still anchor to an existing project or Git
# root when one is visible, preventing accidental nested manifests from subdirs.

# Operational commands need an existing manifest and always run from its root so
# subproject paths in .gitnest are interpreted consistently.

# Return the outer repository root when inside Git, otherwise the current path.

# Make sure the outer workspace is a Git repository, creating it if needed.

# Check whether a non-Git startup folder contains immediate subdirectories.
startup_has_subdirectories() {
	for path in ./*; do
		[ -d "$path" ] || continue
		return 0
	done
	return 1
}

# Ask before initializing a non-Git folder with subdirectories unless --sure is set.
confirm_startup_directory() {
	sure=$1
	if [ -d .git ]; then
		return
	fi
	startup_has_subdirectories || return 0
	[ "$sure" -eq 1 ] && return
	if [ ! -t 0 ]; then
		die "start would initialize a folder containing subdirectories; rerun with --sure to confirm"
	fi
	printf 'This folder contains subdirectories. Initialize it as a git-nest workspace? [y/N] ' >/dev/tty
	IFS= read -r answer </dev/tty || answer=
	case "$answer" in
	y | Y | yes | YES) ;;
	*) die "start canceled" ;;
	esac
}

# Create the manifest skeleton lazily for commands that need manifest state.

# Create the default runtime configuration file when a workspace is initialized.

# Normalize subproject paths so manifest section names are stable across platforms.

# Refuse a new subproject path that differs from an existing managed path only by
# letter case. On case-insensitive filesystems (Windows, macOS) two such entries
# map to the same directory and would corrupt each other. Reads from a file, not
# a pipe, so precondition_error exits the whole command.

# Create a temporary file next to a target file so later mv is same-directory.

# Read one key from one manifest section; callers decide whether empty is valid.

# Read one key from one section in a specific manifest file.

# Reject unsafe subproject paths in the manifest content itself. Commands
# that clone, check out, or remove use these paths, so an absolute path, a
# parent-directory escape (..), a backslash, or a .git-like name must never
# reach the filesystem. Read from a file, not a pipe, so the error exits.
# Read a value from .gitnest-rc. Missing config is normal for copied manifests, so
# callers provide defaults after this helper returns no value.

# List subproject paths from manifest section headers.

# List subproject paths from section headers in a specific manifest file.

# Remove one complete section before rewriting fresh state for it.

# Rewrite the project section with the current ticket and outer branch identity.

# Write one subproject section after validating state-specific required fields.

# Remove one key from a subproject section, used for cleanup hints after deletion.

# Build the manifest section name for a subproject path.

# Read the configured subproject repository URL.

# Read an arbitrary key from a subproject section.

# Validate a subproject clone mode. Empty means "use the default full clone".

# Resolve the repository-wide clone override from .gitnest-rc.

# Read and validate a subproject's manifest clone preference.

# Apply the global override to the subproject clone preference.

# Return the current branch name, or HEAD when detached.

# Infer the target branch from origin refs, defaulting to main.

# Extract the ticket key from branch names such as XX-123-description.

# Report whether a repository has any working tree or index changes.

# Check whether a repository has an origin remote configured.

# Fetch refs and tags opportunistically; callers can still use local refs.

# Clone a subproject using the selected storage mode. Partial clone remains strict:
# if Git cannot create the requested partial checkout, callers get a hard error.

# A partial clone is identified by the promisor remote and blob filter Git writes
# during clone --filter=blob:none.

# Check out a tracked target branch after --no-checkout partial sync.

# Read porcelain status with a tool-level error if Git cannot inspect the repo.

# Detect untracked files for start --discard-dirty validation.

# Detect any dirty state for preflight and status reporting.

# Return the untracked local materialization state file for Git workspaces.
# Copied-manifest folders without an outer .git still sync normally, but cannot
# remember stale paths until they become a Git workspace.

# Write the currently materialized manifest subprojects after a successful sync.

# Read current manifest subproject path/repo pairs into a tab-separated file.

# Guard stale cleanup paths. The state file is local, but deletion still stays
# relative to the project root and avoids parent traversal.

# Return an empty string when a stale subproject is safe to delete or move.

# Reconcile paths remembered from the previous sync with the current manifest.

# List the outer repository and all checked-out subprojects for workspace-wide scans.

# Return a stable absolute path for recursion and duplicate detection.

# Join project-relative labels without turning the root label "." into a prefix.

# Report checked-out subprojects that are themselves project roots.

# Parse the common optional --recursive flag for read-only/restore commands.
parse_recursive_only() {
	[ $# -le 1 ] || die "$1 takes only optional --recursive"
	if [ $# -eq 1 ]; then
		[ "$1" = "--recursive" ] || die "unknown option: $1"
		printf '1\n'
	else
		printf '0\n'
	fi
}

# Parse read-only commands that support recursive, porcelain, and JSON output.
parse_recursive_output() {
	command=$1
	shift
	PARSED_RECURSIVE=0
	PARSED_PORCELAIN=0
	PARSED_JSON=0
	PARSED_JSON_PRETTY=0
	PARSED_EXIT_CODE=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--recursive) PARSED_RECURSIVE=1 ;;
		--porcelain) PARSED_PORCELAIN=1 ;;
		--json) PARSED_JSON=1 ;;
		--json-pretty)
			PARSED_JSON=1
			PARSED_JSON_PRETTY=1
			;;
		--exit-code)
			[ "$command" = status ] || usage_error "--exit-code is only supported by status"
			PARSED_EXIT_CODE=1
			;;
		*) usage_error "unknown $command option: $1" ;;
		esac
		shift
	done
	if [ "$PARSED_PORCELAIN" -eq 1 ] && [ "$PARSED_JSON" -eq 1 ]; then
		usage_error "$command cannot combine --porcelain with --json/--json-pretty"
	fi
}

# Write dirty repository paths to a file so start can preflight before switching.
dirty_repos_file() {
	out=$1
	: >"$out"
	list_repos | while IFS= read -r path; do
		if repo_has_dirty "$path"; then
			printf '%s\n' "$path" >>"$out"
		fi
	done
}

# Stash all dirty repositories discovered by start preflight.
stash_dirty_repos() {
	dirty_file=$1
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		git -C "$path" stash push -u -m "git-nest start preflight" >/dev/null
	done <"$dirty_file"
}

# Discard tracked edits in dirty repositories, then reject remaining untracked files.
discard_tracked_dirty_repos() {
	dirty_file=$1
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		git -C "$path" reset --hard >/dev/null
	done <"$dirty_file"
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if repo_has_untracked "$path"; then
			die "repo $path still has untracked files after --discard-dirty; stash or remove them before start"
		fi
	done <"$dirty_file"
}

# Resolve the start dirty-work policy, including interactive prompting.
resolve_start_dirty() {
	action=$1
	dirty_file=$2
	if [ ! -s "$dirty_file" ]; then
		return
	fi

	printf 'Warning: dirty or untracked repositories:\n' >&2
	while IFS= read -r path; do
		printf '  %s\n' "$path" >&2
	done <"$dirty_file"

	case "$action" in
	stash)
		stash_dirty_repos "$dirty_file"
		;;
	discard)
		discard_tracked_dirty_repos "$dirty_file"
		;;
	cancel)
		die "start canceled because repositories have uncommitted changes"
		;;
	ask)
		[ -t 0 ] || die "start needs clean repositories or --stash-dirty/--discard-dirty/--cancel-dirty"
		printf 'Action: [s] stash all, [d] discard tracked edits, [c] cancel (default): ' >/dev/tty
		IFS= read -r answer </dev/tty || answer=
		case "$answer" in
		s | S) stash_dirty_repos "$dirty_file" ;;
		d | D) discard_tracked_dirty_repos "$dirty_file" ;;
		c | C | "") die "start canceled" ;;
		*) die "unknown start action: $answer" ;;
		esac
		;;
	*) die "unknown dirty action: $action" ;;
	esac
}
cmd_tidy() {
	create_rc=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--rc)
			create_rc=1
			shift
			;;
		*) usage_error "unknown tidy option: $1" ;;
		esac
	done
	ensure_outer_repo
	acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	ensure_gitattributes_guard
	[ -f .gitignore ] || : >.gitignore
	# tidy is the one place that prunes stale nest-owned ignore entries: orphan
	# block paths that are neither managed nor present on disk (the leftover after
	# a detached repo is physically removed). Report what was pruned.
	pruned=$(mktemp)
	reconcile_gitignore "" "" 1 "$pruned"
	if [ -s "$pruned" ]; then
		while IFS= read -r stale; do
			[ -n "$stale" ] && printf 'Pruned stale ignore entry: %s/\n' "$stale"
		done <"$pruned"
	fi
	rm -f "$pruned"
	[ "$create_rc" -eq 0 ] || ensure_config
	printf 'Tidied git-nest managed support files.\n'
}

# Initialize an outer workspace and create default manifest/config files.
cmd_init() {
	create_rc=0
	sure=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--rc)
			create_rc=1
			shift
			;;
		--sure)
			sure=1
			shift
			;;
		*) usage_error "unknown init option: $1" ;;
		esac
	done
	if root=$(git rev-parse --show-toplevel 2>/dev/null); then
		cd "$root" || die "cannot enter Git root $root"
	fi
	if [ -f "$MANIFEST_FILE" ]; then
		printf 'git-nest workspace already initialized at %s.\n' "$(pwd)"
		printf 'Run git-nest doctor to inspect it or git-nest tidy to refresh managed support files.\n'
		return 0
	fi
	if parent_root=$(nearest_parent_manifest_root 2>/dev/null); then
		[ "$sure" -eq 1 ] || precondition_error "this directory is inside existing git-nest workspace $parent_root; rerun git-nest init --sure to create an intentional nested nest"
	fi
	assert_new_nest_excludes_ancestor_subprojects
	ensure_outer_repo
	acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	ensure_gitattributes_guard
	[ -f .gitignore ] || : >.gitignore
	ensure_gitignore_hygiene
	[ "$create_rc" -eq 0 ] || ensure_config
	printf 'Initialized git-nest workspace.\n'
}

# Add a subproject checkout and record its repo, target branch, and current revision.
cmd_add() {
	clone_mode=
	add_depth=
	while [ $# -gt 0 ]; do
		case "$1" in
		--clone)
			[ $# -ge 2 ] || die "--clone requires full, partial, or shallow"
			clone_mode=$2
			validate_clone_mode "$clone_mode" "add --clone"
			[ -n "$clone_mode" ] || die "--clone requires full, partial, or shallow"
			shift 2
			;;
		--depth)
			[ $# -ge 2 ] || die "--depth requires a positive integer"
			add_depth=$2
			validate_positive_integer "$add_depth" "--depth"
			shift 2
			;;
		--*) die "unknown add option: $1" ;;
		*) break ;;
		esac
	done
	[ $# -eq 2 ] || die "usage: git-nest add [--clone <full|partial|shallow>] [--depth <n>] <repo> <path>"
	repo=$1
	reject_backslash_path "$2"
	path=$(normalize_path "$2")
	ensure_outer_repo
	acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	assert_path_not_inside_nested_project "$path"
	assert_no_case_collision "$path"
	project_invocation_warnings

	if [ ! -d "$path/.git" ]; then
		[ ! -e "$path" ] || die "$path exists but is not a Git repository"
		mode=$clone_mode
		if [ -z "$mode" ]; then
			configured=$(configured_clone_mode)
			[ "$configured" = partial ] && mode=partial
			[ "$configured" = shallow ] && mode=shallow
		fi
		[ -n "$mode" ] || mode=full
		cs_depth=${add_depth:-}
		clone_subproject "$repo" "$path" "$mode" 0 "$cs_depth"
	fi

	ensure_gitignore_hygiene
	ensure_gitignore_entry "$path"

	[ "$GIT_NEST_DRY_RUN" -eq 1 ] || fetch_quiet "$path"
	target=$(default_target_branch "$path")
	revision=$(resolve_head_commit "$path" "cannot add subproject $path")
	manifest_write_subproject "$path" "$repo" tracked "$target" "$revision" "$clone_mode"
	if [ -n "$add_depth" ]; then
		manifest_set_subproject_key "$path" depth "$add_depth"
	fi
	install_hooks_in_repo_if_project_managed "$path"
	write_materialized_state
	printf 'Added subproject %s.\n' "$path"
}

# remove drops a subproject from the nest and deletes its checkout on disk. It
# is the destructive leave-the-nest verb; the remote is never touched. Use detach
# to keep the checkout as a standalone repository instead of deleting it.
cmd_remove() {
	force=0
	dry_run=0
	json=0
	pretty=0
	path_arg=
	while [ $# -gt 0 ]; do
		case "$1" in
		--force)
			force=1
			shift
			;;
		# --keep-files used to mean "remove entry but keep files"; that is now
		# the dedicated detach command, so reject it with clear guidance.
		--keep-files) usage_error "remove now always deletes the checkout; use git-nest detach <path> to leave the nest but keep the checkout" ;;
		--dry-run)
			dry_run=1
			shift
			;;
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			pretty=1
			shift
			;;
		--*) usage_error "unknown remove option: $1" ;;
		*)
			[ -z "$path_arg" ] || usage_error "usage: git-nest remove <path> [--force] [--dry-run] [--json|--json-pretty]"
			path_arg=$1
			shift
			;;
		esac
	done
	[ -n "$path_arg" ] || usage_error "usage: git-nest remove <path> [--force] [--dry-run] [--json|--json-pretty]"
	reject_backslash_path "$path_arg"
	path=$(normalize_path "$path_arg")
	acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	assert_path_not_inside_nested_project "$path"
	repo=$(subproject_repo "$path" || true)
	[ -n "$repo" ] || precondition_error "$path is not a tracked subproject in $MANIFEST_FILE"
	target=$(subproject_key "$path" target_branch || true)
	# Guard against discarding local-only work unless the caller forces it.
	if [ "$force" -eq 0 ]; then
		reason=$(current_branch_safety_reason "$path" "$target")
		[ -z "$reason" ] || precondition_error "$reason; rerun with --force to remove anyway"
	fi
	# Snapshot output values before mutating helpers reuse the global variables.
	emit_path=$path
	emit_repo=$repo
	emit_target=${target:--}
	# Dry-run reports the plan without mutating the manifest or the filesystem.
	if [ "$dry_run" -eq 1 ]; then
		[ "$json" -eq 0 ] || GIT_NEST_JSON_DRY_RUN=1
		if [ "$json" -eq 1 ]; then
			json_single_row_result "$pretty" remove 1 R "$emit_path" removed "$emit_target" - "$emit_repo" "would remove subproject and delete files"
		else
			printf 'Would remove subproject %s and delete %s/.\n' "$emit_path" "$emit_path"
		fi
		return 0
	fi
	manifest_remove_section "$(subproject_section "$path")"
	remove_gitignore_entry "$path"
	if [ -e "$path" ]; then
		rm -rf -- "$path" || git_error "failed to remove subproject directory $path"
	fi
	write_materialized_state
	if [ "$json" -eq 1 ]; then
		json_single_row_result "$pretty" remove 1 R "$emit_path" removed "$emit_target" - "$emit_repo" "removed subproject and deleted files"
	else
		printf 'Removed subproject %s and deleted its files.\n' "$emit_path"
	fi
}

# detach drops a subproject from the nest but keeps its checkout on disk as a
# standalone, still-ignored Git repository. It is the non-destructive inverse of
# absorbing an existing repository: no files are deleted and the remote is left
# untouched. Reversing to a specific submodule/subtree/subrepo shape is out of
# scope; detach only guarantees a standalone repository remains.
cmd_detach() {
	dry_run=0
	json=0
	pretty=0
	path_arg=
	while [ $# -gt 0 ]; do
		case "$1" in
		--dry-run)
			dry_run=1
			shift
			;;
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			pretty=1
			shift
			;;
		--*) usage_error "unknown detach option: $1" ;;
		*)
			[ -z "$path_arg" ] || usage_error "usage: git-nest detach <path> [--dry-run] [--json|--json-pretty]"
			path_arg=$1
			shift
			;;
		esac
	done
	[ -n "$path_arg" ] || usage_error "usage: git-nest detach <path> [--dry-run] [--json|--json-pretty]"
	reject_backslash_path "$path_arg"
	path=$(normalize_path "$path_arg")
	acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	assert_path_not_inside_nested_project "$path"
	repo=$(subproject_repo "$path" || true)
	[ -n "$repo" ] || precondition_error "$path is not a tracked subproject in $MANIFEST_FILE"
	target=$(subproject_key "$path" target_branch || true)
	# Snapshot output values before mutating helpers reuse the global variables.
	emit_path=$path
	emit_repo=$repo
	emit_target=${target:--}
	# detach keeps files and the ignore entry, so there is no dirty/ahead safety
	# gate: nothing on disk is lost by dropping the manifest entry.
	if [ "$dry_run" -eq 1 ]; then
		[ "$json" -eq 0 ] || GIT_NEST_JSON_DRY_RUN=1
		if [ "$json" -eq 1 ]; then
			json_single_row_result "$pretty" detach 1 T "$emit_path" detached "$emit_target" - "$emit_repo" "would detach and keep files ignored"
		else
			printf 'Would detach %s from the nest; keep files and keep %s/ ignored.\n' "$emit_path" "$emit_path"
		fi
		return 0
	fi
	manifest_remove_section "$(subproject_section "$path")"
	write_materialized_state
	if [ "$json" -eq 1 ]; then
		json_single_row_result "$pretty" detach 1 T "$emit_path" detached "$emit_target" - "$emit_repo" "detached and kept files ignored"
	else
		printf 'Detached %s from %s; kept files and kept %s/ ignored.\n' "$emit_path" "$MANIFEST_FILE" "$emit_path"
		printf 'After you move or delete %s, run git-nest tidy to prune its ignore entry.\n' "$emit_path"
	fi
}

cmd_mv() {
	force=0
	old_arg=
	new_arg=
	if [ "${1:-}" = "--url" ]; then
		[ $# -eq 3 ] || usage_error "usage: git-nest move|mv --url <new-url> <path>"
		new_url=$2
		reject_backslash_path "$3"
		path=$(normalize_path "$3")
		acquire_manifest_lock
		ensure_manifest
		validate_manifest_schema
		assert_path_not_inside_nested_project "$path"
		repo=$(subproject_repo "$path" || true)
		[ -n "$repo" ] || precondition_error "$path is not a tracked subproject in $MANIFEST_FILE"
		if [ -d "$path/.git" ]; then
			current_head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
			remote_head=$(remote_head_commit_for_url "$new_url" || true)
			if [ -n "$current_head" ] && [ -n "$remote_head" ] && [ "$current_head" != "$remote_head" ]; then
				warn "new URL HEAD differs from current checkout for $path"
			fi
		fi
		manifest_set_subproject_key "$path" repo "$new_url"
		printf 'Updated subproject %s URL.\n' "$path"
		return 0
	fi
	while [ $# -gt 0 ]; do
		case "$1" in
		--force)
			force=1
			shift
			;;
		--*) usage_error "unknown move option: $1" ;;
		*)
			if [ -z "${old_arg:-}" ]; then
				old_arg=$1
			elif [ -z "${new_arg:-}" ]; then
				new_arg=$1
			else
				usage_error "usage: git-nest move|mv <old-path> <new-path> [--force]"
			fi
			shift
			;;
		esac
	done
	[ -n "${old_arg:-}" ] && [ -n "${new_arg:-}" ] || usage_error "usage: git-nest move|mv <old-path> <new-path> [--force]"
	reject_backslash_path "$old_arg"
	reject_backslash_path "$new_arg"
	old_path=$(normalize_path "$old_arg")
	new_path=$(normalize_path "$new_arg")
	acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	assert_path_not_inside_nested_project "$old_path"
	assert_path_not_inside_nested_project "$new_path"
	repo=$(subproject_repo "$old_path" || true)
	[ -n "$repo" ] || precondition_error "$old_path is not a tracked subproject in $MANIFEST_FILE"
	[ -z "$(subproject_repo "$new_path" || true)" ] || precondition_error "$new_path is already a tracked subproject"
	assert_no_case_collision "$new_path"
	[ ! -e "$new_path" ] || precondition_error "$new_path already exists"
	target=$(subproject_key "$old_path" target_branch || true)
	if [ "$force" -eq 0 ]; then
		reason=$(current_branch_safety_reason "$old_path" "$target")
		[ -z "$reason" ] || precondition_error "$reason; rerun with --force to move anyway"
	fi
	parent=$(dirname -- "$new_path")
	[ "$parent" = "." ] || mkdir -p "$parent" || git_error "failed to create parent directory $parent"
	if [ -e "$old_path" ]; then
		mv -- "$old_path" "$new_path" || git_error "failed to move $old_path to $new_path"
	fi
	manifest_rename_subproject_section "$old_path" "$new_path"
	remove_gitignore_entry "$old_path"
	ensure_gitignore_hygiene
	ensure_gitignore_entry "$new_path"
	write_materialized_state
	printf 'Moved subproject %s to %s.\n' "$old_path" "$new_path"
}

cmd_clone() {
	no_restore=0
	depth=
	branch=
	single_branch=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--no-restore)
			no_restore=1
			shift
			;;
		--no-sync) usage_error "unknown clone option: --no-sync; use --no-restore" ;;
		--depth)
			[ $# -ge 2 ] || usage_error "--depth requires a value"
			depth=$2
			shift 2
			;;
		--branch | -b)
			[ $# -ge 2 ] || usage_error "$1 requires a value"
			branch=$2
			shift 2
			;;
		--single-branch)
			single_branch=1
			shift
			;;
		--*) usage_error "unknown clone option: $1" ;;
		*) break ;;
		esac
	done
	[ $# -ge 1 ] && [ $# -le 2 ] || usage_error "usage: git-nest clone <nest-repo-url> [target-dir]"
	outer_repo=$1
	target_dir=${2:-}
	set -- git clone
	if [ -n "$depth" ]; then
		set -- "$@" --depth "$depth"
	fi
	if [ -n "$branch" ]; then
		set -- "$@" --branch "$branch"
	fi
	if [ "$single_branch" -eq 1 ]; then
		set -- "$@" --single-branch
	fi
	if [ -n "$target_dir" ]; then
		"$@" "$outer_repo" "$target_dir" || git_error "failed to clone outer repository $outer_repo into $target_dir; verify the URL and network access"
	else
		"$@" "$outer_repo" || git_error "failed to clone outer repository $outer_repo; verify the URL and network access"
		target_dir=$(basename -- "$outer_repo")
		target_dir=${target_dir%.git}
	fi
	if [ "$no_restore" -eq 1 ]; then
		printf 'Cloned %s.\n' "$target_dir"
		return 0
	fi
	if [ -f "$target_dir/$MANIFEST_FILE" ]; then
		(cd "$target_dir" && git_nest_main restore) || return $?
	else
		notice "cloned repository has no $MANIFEST_FILE; skipped restore"
	fi
}

# Uses a pol_-prefixed path (rather than bare path) because cmd_freeze calls
# this without a subshell while holding its own bare path across the call.
path_in_only_list() {
	pol_path=$1
	list=$2
	[ -n "$list" ] || return 0
	old_ifs=$IFS
	IFS=,
	for item in $list; do
		reject_backslash_path "$item"
		item=$(normalize_path "$item")
		if [ "$item" = "$pol_path" ]; then
			IFS=$old_ifs
			return 0
		fi
	done
	IFS=$old_ifs
	return 1
}

validate_only_list_boundaries() {
	list=$1
	[ -n "$list" ] || return 0
	old_ifs=$IFS
	IFS=,
	for item in $list; do
		reject_backslash_path "$item"
		item=$(normalize_path "$item")
		[ -n "$item" ] || continue
		assert_path_not_inside_nested_project "$item"
	done
	IFS=$old_ifs
}

cmd_freeze() {
	force=0
	dry_run=0
	only=
	while [ $# -gt 0 ]; do
		case "$1" in
		--force)
			force=1
			shift
			;;
		--dry-run)
			dry_run=1
			shift
			;;
		--only)
			[ $# -ge 2 ] || usage_error "--only requires a value"
			only=$2
			shift 2
			;;
		--*) usage_error "unknown freeze option: $1" ;;
		*) usage_error "unknown freeze argument: $1" ;;
		esac
	done
	[ "$dry_run" -eq 1 ] || acquire_manifest_lock
	validate_only_list_boundaries "$only"
	frozen=0
	pinned=0
	skipped=0
	subprojects_tmp=$(tmp_for "$MANIFEST_FILE.freeze")
	manifest_subprojects >"$subprojects_tmp"
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		path_in_only_list "$path" "$only" || continue
		repo=$(subproject_repo "$path" || true)
		[ -n "$repo" ] || continue
		pending=$(subproject_key "$path" pending_branch || true)
		revision=$(subproject_key "$path" revision || true)
		if [ -n "$pending" ]; then
			pinned=$((pinned + 1))
			continue
		fi
		if [ ! -d "$path/.git" ]; then
			warn "skipping missing subproject $path during freeze"
			skipped=$((skipped + 1))
			continue
		fi
		head=$(resolve_head_commit "$path" "cannot freeze $path")
		if [ -n "$revision" ]; then
			recorded=$(git -C "$path" rev-parse --verify "$revision^{commit}" 2>/dev/null || true)
			if [ -n "$recorded" ] && [ "$recorded" = "$head" ]; then
				pinned=$((pinned + 1))
				continue
			fi
		fi
		target=$(subproject_key "$path" target_branch || true)
		[ -n "$target" ] || target=$(default_target_branch "$path")
		reason=$(current_branch_safety_reason "$path" "$target")
		if [ -n "$reason" ]; then
			if [ "$force" -eq 0 ]; then
				precondition_error "$reason; rerun with --force to freeze anyway"
			fi
			warn "$reason; freezing current HEAD because --force was used"
		fi
		if [ "$dry_run" -eq 1 ]; then
			printf 'Would freeze %s at %.12s.\n' "$path" "$head"
		else
			manifest_write_subproject "$path" "$repo" tracked "$target" "$head"
			printf 'Frozen %s at %.12s.\n' "$path" "$head"
		fi
		frozen=$((frozen + 1))
	done <"$subprojects_tmp"
	rm -f "$subprojects_tmp"
	printf 'Freeze summary: %s frozen, %s already pinned, %s skipped.\n' "$frozen" "$pinned" "$skipped"
}

# Print a compact view of the current project and subproject state for humans.
status_current() {
	ensure_manifest
	branch=$(current_branch)
	project_id=$(manifest_get project id || true)
	project_branch=$(manifest_get project branch || true)

	printf 'outer branch: %s\n' "$branch"
	[ -n "$project_id" ] && printf 'project id: %s\n' "$project_id"
	[ -n "$project_branch" ] && printf 'project branch: %s\n' "$project_branch"
	printf 'subprojects:\n'

	manifest_subprojects | while IFS= read -r path; do
		pending=$(subproject_key "$path" pending_branch || true)
		revision=$(subproject_key "$path" revision || true)
		if [ ! -d "$path/.git" ]; then
			printf '  %s: missing\n' "$path"
		elif [ -n "$pending" ]; then
			dirty=
			repo_dirty "$path" && dirty=' dirty'
			printf '  %s: pending %s%s\n' "$path" "$pending" "$dirty"
		elif [ -n "$revision" ]; then
			dirty=
			repo_dirty "$path" && dirty=' dirty'
			printf '  %s: pinned %.12s%s\n' "$path" "$revision" "$dirty"
		else
			printf '  %s: tracked\n' "$path"
		fi
	done
	unmanaged=$(unmanaged_subprojects)
	if [ -n "$unmanaged" ]; then
		printf 'unmanaged subprojects:\n'
		printf '%s\n' "$unmanaged" | while IFS= read -r path; do
			[ -n "$path" ] && printf '  %s: unmanaged nested Git repository\n' "$path"
		done
	fi
}

# Print dirty or incomplete state in a stable, fixed-column script format.
status_porcelain_current() {
	label=$1

	repo_status_porcelain . "cannot inspect dirty state" | while IFS= read -r line; do
		[ -n "$line" ] || continue
		printf 'D\t%s\tdirty\t-\t-\t-\t%s\n' "$label" "$line"
	done

	manifest_subprojects | while IFS= read -r path; do
		[ -n "$path" ] || continue
		subproject_label=$(join_project_label "$label" "$path")
		if [ ! -d "$path/.git" ]; then
			printf 'M\t%s\tmissing\t-\t-\t-\tcheckout-missing\n' "$subproject_label"
			continue
		fi
		pending=$(subproject_key "$path" pending_branch || true)
		code=$(status_code_for_subproject "$path")
		state=$(status_state_for_code "$code")
		dirty_status=$(repo_status_porcelain "$path" "cannot inspect dirty state")
		printf '%s\n' "$dirty_status" | while IFS= read -r line; do
			[ -n "$line" ] || continue
			printf '%s\t%s\t%s\t-\t-\t-\t%s\n' "$code" "$subproject_label" "$state" "$line"
		done
		if [ -n "$pending" ] && [ -n "$dirty_status" ]; then
			printf 'C\t%s\tcomposite\t-\t-\t-\tdirty-and-pending\n' "$subproject_label"
		fi
		if subproject_manifest_mismatch "$path"; then
			printf 'C\t%s\tcomposite\t-\t-\t-\thead-differs-from-manifest\n' "$subproject_label"
		fi
	done
	unmanaged_subprojects | while IFS= read -r path; do
		[ -n "$path" ] || continue
		unmanaged_label=$(join_project_label "$label" "$path")
		printf 'U\t%s\tunmanaged\t-\t-\t-\tnested-git-repo\n' "$unmanaged_label"
	done
}

# Recursively print status for the current project and nested project roots.
status_recursive() {
	label=$1
	visited=$2
	root_abs=$(abs_path_for .)
	if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
		return 0
	fi
	printf '%s\n' "$root_abs" >>"$visited"
	printf 'project: %s\n' "$label"
	status_current

	manifest_subprojects | while IFS= read -r path; do
		[ -n "$path" ] || continue
		if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
			child_label=$(join_project_label "$label" "$path")
			(
				cd "$path" || exit 1
				printf '\n'
				status_recursive "$child_label" "$visited"
			)
		fi
	done
}

# Recursively print porcelain status for the current project and nested project roots.
status_porcelain_recursive() {
	label=$1
	visited=$2
	root_abs=$(abs_path_for .)
	if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
		return 0
	fi
	printf '%s\n' "$root_abs" >>"$visited"
	status_porcelain_current "$label"

	manifest_subprojects | while IFS= read -r path; do
		[ -n "$path" ] || continue
		if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
			child_label=$(join_project_label "$label" "$path")
			(
				cd "$path" || exit 1
				status_porcelain_recursive "$child_label" "$visited"
			)
		fi
	done
}

# Print project state, optionally including nested projects.
cmd_status() {
	parse_recursive_output status "$@"
	recursive=$PARSED_RECURSIVE
	porcelain=$PARSED_PORCELAIN
	json=$PARSED_JSON
	json_pretty=$PARSED_JSON_PRETTY
	exit_code=$PARSED_EXIT_CODE
	if [ "$porcelain" -eq 1 ]; then
		if [ "$recursive" -eq 1 ]; then
			visited=$(mktemp)
			: >"$visited"
			status_porcelain_recursive "." "$visited"
			rm -f "$visited"
		else
			status_porcelain_current "."
		fi
	elif [ "$json" -eq 1 ]; then
		rows=$(mktemp)
		errors=$(mktemp)
		warnings=$(mktemp)
		: >"$errors"
		: >"$warnings"
		if [ "$recursive" -eq 1 ]; then
			visited=$(mktemp)
			: >"$visited"
			status_porcelain_recursive "." "$visited" >"$rows"
			rm -f "$visited"
		else
			status_porcelain_current "." >"$rows"
		fi
		[ -s "$rows" ] && ok=0 || ok=1
		emit_json_result status "$recursive" "$ok" "$rows" "$errors" "$warnings" "$json_pretty"
		rm -f "$rows" "$errors" "$warnings"
	elif [ "$recursive" -eq 1 ]; then
		visited=$(mktemp)
		: >"$visited"
		status_recursive "." "$visited"
		rm -f "$visited"
	else
		status_current
		notice_nested_projects
	fi
	if [ "$exit_code" -eq 1 ]; then
		rows=$(mktemp)
		if [ "$recursive" -eq 1 ]; then
			visited=$(mktemp)
			: >"$visited"
			status_porcelain_recursive "." "$visited" >"$rows"
			rm -f "$visited"
		else
			status_porcelain_current "." >"$rows"
		fi
		[ ! -s "$rows" ] || {
			rm -f "$rows"
			return "$EXIT_ISSUES"
		}
		rm -f "$rows"
	fi
}

# Pick the branch used for remote query checks. Existing finalized
# entries may not record target_branch, so follow the normal target inference.

# Query a subproject remote without updating local refs.

# Report whether subproject remotes have target-branch commits newer than .gitnest.
outdated_current() {
	ensure_manifest
	errors=$(tmp_for "$MANIFEST_FILE.outdated_errors")
	: >"$errors"

	printf 'subprojects:\n'
	manifest_subprojects | while IFS= read -r path; do
		[ -n "$path" ] || continue
		repo=$(subproject_repo "$path" || true)
		if [ -z "$repo" ]; then
			printf '  %s: error missing repo\n' "$path"
			printf 'Error: %s: missing repo in %s\n' "$path" "$MANIFEST_FILE" >>"$errors"
			continue
		fi

		pending=$(subproject_key "$path" pending_branch || true)
		if [ -n "$pending" ]; then
			printf '  %s: pending %s\n' "$path" "$pending"
			continue
		fi

		target=$(outdated_target_branch "$path")
		remote_tmp=$(tmp_for "$MANIFEST_FILE.outdated_remote")
		remote_commit=$(remote_branch_commit "$repo" "$target" "$remote_tmp" || true)
		rm -f "$remote_tmp"
		if [ -z "$remote_commit" ]; then
			if git ls-remote "$repo" >/dev/null 2>&1; then
				printf '  %s: remote branch missing %s\n' "$path" "$target"
				printf 'Error: %s: remote branch %s is missing\n' "$path" "$target" >>"$errors"
			else
				printf '  %s: remote unavailable %s\n' "$path" "$target"
				printf 'Error: %s: cannot query remote %s\n' "$path" "$repo" >>"$errors"
			fi
			continue
		fi

		revision=$(subproject_key "$path" revision || true)
		tag=$(subproject_key "$path" tag || true)
		remote_short=$(printf '%s\n' "$remote_commit" | cut -c1-12)

		if [ ! -d "$path/.git" ]; then
			printf '  %s: missing checkout; remote %s %s\n' "$path" "$target" "$remote_short"
		elif [ -n "$revision" ]; then
			revision_short=$(printf '%s\n' "$revision" | cut -c1-12)
			if [ "$remote_commit" = "$revision" ]; then
				if [ -n "$tag" ]; then
					printf '  %s: tag-pinned %s; up to date %s %s\n' "$path" "$tag" "$target" "$remote_short"
				else
					printf '  %s: up to date %s %s\n' "$path" "$target" "$remote_short"
				fi
			else
				if [ -n "$tag" ]; then
					printf '  %s: tag-pinned %s; outdated %s %s -> %s\n' "$path" "$tag" "$target" "$revision_short" "$remote_short"
				else
					printf '  %s: outdated %s %s -> %s\n' "$path" "$target" "$revision_short" "$remote_short"
				fi
			fi
		else
			head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
			head_short=$(printf '%s\n' "$head" | cut -c1-12)
			if [ -n "$head" ] && [ "$remote_commit" = "$head" ]; then
				printf '  %s: up to date %s %s\n' "$path" "$target" "$remote_short"
			elif [ -n "$head" ]; then
				printf '  %s: outdated %s %s -> %s\n' "$path" "$target" "$head_short" "$remote_short"
			else
				printf '  %s: remote %s %s\n' "$path" "$target" "$remote_short"
			fi
		fi
	done

	if [ -s "$errors" ]; then
		cat "$errors" >&2
		rm -f "$errors"
		return 1
	fi
	rm -f "$errors"
}

# Report remote query results in stable fixed-column records for scripts.
outdated_porcelain_current() {
	label=$1
	ensure_manifest
	errors=$(tmp_for "$MANIFEST_FILE.outdated_errors")
	: >"$errors"

	manifest_subprojects | while IFS= read -r path; do
		[ -n "$path" ] || continue
		subproject_label=$(join_project_label "$label" "$path")
		repo=$(subproject_repo "$path" || true)
		if [ -z "$repo" ]; then
			printf 'E\t%s\terror\t-\t-\t-\tmissing-repo\n' "$subproject_label"
			printf 'Error: %s: missing repo in %s\n' "$subproject_label" "$MANIFEST_FILE" >>"$errors"
			continue
		fi

		pending=$(subproject_key "$path" pending_branch || true)
		[ -z "$pending" ] || continue

		target=$(outdated_target_branch "$path")
		remote_tmp=$(tmp_for "$MANIFEST_FILE.outdated_remote")
		remote_commit=$(remote_branch_commit "$repo" "$target" "$remote_tmp" || true)
		rm -f "$remote_tmp"
		if [ -z "$remote_commit" ]; then
			if git ls-remote "$repo" >/dev/null 2>&1; then
				printf 'E\t%s\tremote-branch-missing\t%s\t-\t-\tremote-branch-missing\n' "$subproject_label" "$target"
				printf 'Error: %s: remote branch %s is missing\n' "$subproject_label" "$target" >>"$errors"
			else
				printf 'E\t%s\tremote-unavailable\t%s\t-\t-\tremote-unavailable\n' "$subproject_label" "$target"
				printf 'Error: %s: cannot query remote %s\n' "$subproject_label" "$repo" >>"$errors"
			fi
			continue
		fi

		revision=$(subproject_key "$path" revision || true)
		if [ ! -d "$path/.git" ]; then
			printf 'M\t%s\tmissing\t%s\t-\t%s\tcheckout-missing\n' "$subproject_label" "$target" "$remote_commit"
		elif [ -n "$revision" ]; then
			if [ "$remote_commit" != "$revision" ]; then
				printf 'O\t%s\toutdated\t%s\t%s\t%s\tremote-target\n' "$subproject_label" "$target" "$revision" "$remote_commit"
			fi
		else
			head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
			if [ -n "$head" ] && [ "$remote_commit" != "$head" ]; then
				printf 'O\t%s\toutdated\t%s\t%s\t%s\tremote-target\n' "$subproject_label" "$target" "$head" "$remote_commit"
			elif [ -z "$head" ]; then
				printf 'M\t%s\tmissing-head\t%s\t-\t%s\thead-unresolved\n' "$subproject_label" "$target" "$remote_commit"
			fi
		fi
	done

	if [ -s "$errors" ]; then
		cat "$errors" >&2
		rm -f "$errors"
		return 1
	fi
	rm -f "$errors"
}

# Recursively check outdated state for the current project and nested project roots.
outdated_recursive() {
	label=$1
	visited=$2
	root_abs=$(abs_path_for .)
	if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
		return 0
	fi
	printf '%s\n' "$root_abs" >>"$visited"
	printf 'project: %s\n' "$label"
	rc=0
	outdated_current || rc=1

	subprojects_tmp=$(tmp_for "$MANIFEST_FILE.outdated_recursive")
	manifest_subprojects >"$subprojects_tmp"
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
			child_label=$(join_project_label "$label" "$path")
			(
				cd "$path" || exit 1
				printf '\n'
				outdated_recursive "$child_label" "$visited"
			) || rc=1
		fi
	done <"$subprojects_tmp"
	rm -f "$subprojects_tmp"
	return "$rc"
}

# Recursively check outdated state in stable records for scripts.
outdated_porcelain_recursive() {
	label=$1
	visited=$2
	root_abs=$(abs_path_for .)
	if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
		return 0
	fi
	printf '%s\n' "$root_abs" >>"$visited"
	rc=0
	outdated_porcelain_current "$label" || rc=1

	subprojects_tmp=$(tmp_for "$MANIFEST_FILE.outdated_recursive")
	manifest_subprojects >"$subprojects_tmp"
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
			child_label=$(join_project_label "$label" "$path")
			(
				cd "$path" || exit 1
				outdated_porcelain_recursive "$child_label" "$visited"
			) || rc=1
		fi
	done <"$subprojects_tmp"
	rm -f "$subprojects_tmp"
	return "$rc"
}

# Check subproject remotes for newer target-branch commits without changing state.
cmd_outdated() {
	parse_recursive_output outdated "$@"
	recursive=$PARSED_RECURSIVE
	porcelain=$PARSED_PORCELAIN
	json=$PARSED_JSON
	json_pretty=$PARSED_JSON_PRETTY
	if [ "$porcelain" -eq 1 ]; then
		rows=$(mktemp)
		if [ "$recursive" -eq 1 ]; then
			visited=$(mktemp)
			: >"$visited"
			rc=0
			outdated_porcelain_recursive "." "$visited" >"$rows" || rc=$?
			rm -f "$visited"
		else
			rc=0
			outdated_porcelain_current "." >"$rows" || rc=$?
		fi
		cat "$rows"
		if [ "$rc" -ne 0 ] || [ -s "$rows" ]; then
			rm -f "$rows"
			return "$EXIT_ISSUES"
		fi
		rm -f "$rows"
		return 0
	elif [ "$json" -eq 1 ]; then
		rows=$(mktemp)
		errors=$(mktemp)
		warnings=$(mktemp)
		: >"$errors"
		: >"$warnings"
		if [ "$recursive" -eq 1 ]; then
			visited=$(mktemp)
			: >"$visited"
			rc=0
			outdated_porcelain_recursive "." "$visited" >"$rows" 2>"$errors" || rc=$?
			rm -f "$visited"
		else
			rc=0
			outdated_porcelain_current "." >"$rows" 2>"$errors" || rc=$?
		fi
		if [ "$rc" -ne 0 ] || [ -s "$rows" ]; then ok=0; else ok=1; fi
		emit_json_result outdated "$recursive" "$ok" "$rows" "$errors" "$warnings" "$json_pretty"
		rm -f "$rows" "$errors" "$warnings"
		[ "$ok" -eq 1 ] || return "$EXIT_ISSUES"
		return 0
	elif [ "$recursive" -eq 1 ]; then
		visited=$(mktemp)
		: >"$visited"
		outdated_recursive "." "$visited"
		rc=$?
		rm -f "$visited"
		return "$rc"
	fi
	rows=$(mktemp)
	rc=0
	outdated_current || rc=$?
	outdated_porcelain_current "." >"$rows" 2>/dev/null || true
	if [ "$rc" -ne 0 ] || [ -s "$rows" ]; then
		rm -f "$rows"
		return "$EXIT_ISSUES"
	fi
	rm -f "$rows"
	notice_nested_projects
}

# Validate that the current checkout still matches the manifest and config.
# Populate the caller-provided errors and warnings files with verification
# findings for the current nest, one message line each. Returns 0 when there are
# no errors. It does not print; callers decide how to present the results (human
# stderr, or JSON arrays), which keeps errors and warnings cleanly separated and
# avoids clobbering the caller's own temp-file variables.
verify_current() {
	vc_errors=$1
	vc_warnings=$2
	ensure_manifest
	configured_clone_mode >/dev/null
	: >"$vc_errors"
	: >"$vc_warnings"

	duplicates=$(manifest_subprojects | sort | uniq -d)
	if [ -n "$duplicates" ]; then
		printf '%s\n' "$duplicates" | while IFS= read -r path; do
			[ -n "$path" ] && printf 'Error: %s: duplicate subproject path in %s\n' "$path" "$MANIFEST_FILE" >>"$vc_errors"
		done
	fi

	manifest_subprojects | while IFS= read -r path; do
		[ -n "$path" ] || continue
		repo=$(subproject_repo "$path" || true)
		if [ -z "$repo" ]; then
			printf 'Error: %s: missing repo in %s\n' "$path" "$MANIFEST_FILE" >>"$vc_errors"
			continue
		fi
		mode=$(effective_clone_mode "$path")
		if [ ! -d "$path/.git" ]; then
			printf 'Error: %s: subproject checkout is missing; run git-nest restore\n' "$path" >>"$vc_errors"
			continue
		fi

		actual_repo=$(git -C "$path" remote get-url origin 2>/dev/null || true)
		if [ "$actual_repo" != "$repo" ]; then
			printf 'Error: %s: origin remote differs from manifest\n' "$path" >>"$vc_errors"
			printf '  expected: %s\n  actual:   %s\n' "$repo" "$actual_repo" >>"$vc_errors"
		fi

		if [ "$mode" = partial ]; then
			repo_is_partial_clone "$path" ||
				printf 'Error: %s: manifest/config requests clone=partial, but existing checkout is full; remove the subproject and run git-nest restore or use clone=full\n' "$path" >>"$vc_errors"
		else
			if repo_is_partial_clone "$path"; then
				printf 'Error: %s: manifest/config requests clone=full, but existing checkout is partial; remove the subproject and run git-nest restore or use clone=full\n' "$path" >>"$vc_errors"
			fi
		fi

		pending=$(subproject_key "$path" pending_branch || true)
		tag=$(subproject_key "$path" tag || true)
		revision=$(subproject_key "$path" revision || true)
		target=$(subproject_key "$path" target_branch || true)
		[ -n "$target" ] || target=$(default_target_branch "$path")

		if [ -n "$pending" ]; then
			git -C "$path" rev-parse --verify "$pending^{commit}" >/dev/null 2>&1 ||
				git -C "$path" rev-parse --verify "origin/$pending^{commit}" >/dev/null 2>&1 ||
				printf 'Error: %s: pending branch %s is not resolvable\n' "$path" "$pending" >>"$vc_errors"
		elif [ -n "$tag" ]; then
			expected=$(git -C "$path" rev-parse --verify "$tag^{commit}" 2>/dev/null || true)
			if [ -z "$expected" ]; then
				printf 'Error: %s: tag %s is not resolvable\n' "$path" "$tag" >>"$vc_errors"
			else
				head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
				[ "$head" = "$expected" ] ||
					printf 'Error: %s: checked-out commit does not match tag %s\n' "$path" "$tag" >>"$vc_errors"
			fi
		elif [ -n "$revision" ]; then
			expected=$(git -C "$path" rev-parse --verify "$revision^{commit}" 2>/dev/null || true)
			if [ -z "$expected" ]; then
				printf 'Error: %s: revision %s is not resolvable\n' "$path" "$revision" >>"$vc_errors"
			else
				head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
				[ "$head" = "$expected" ] ||
					printf 'Error: %s: checked-out commit does not match revision %.12s\n' "$path" "$revision" >>"$vc_errors"
			fi
		else
			git -C "$path" rev-parse --verify "$target^{commit}" >/dev/null 2>&1 ||
				git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1 ||
				printf 'Error: %s: target branch %s is not resolvable\n' "$path" "$target" >>"$vc_errors"
		fi

		if repo_dirty "$path"; then
			printf 'Warning: %s: subproject has uncommitted changes\n' "$path" >>"$vc_warnings"
		fi
	done

	unmanaged_subprojects | while IFS= read -r path; do
		[ -n "$path" ] || continue
		printf 'Warning: %s: unmanaged nested Git repository\n' "$path" >>"$vc_warnings"
	done

	[ ! -s "$vc_errors" ]
}

# Present current-nest verification for humans: warnings and errors to stderr, a
# success line to stdout, returning nonzero when errors were found.
verify_report_human() {
	vrh_errors=$(tmp_for "$MANIFEST_FILE.verify_errors")
	vrh_warnings=$(tmp_for "$MANIFEST_FILE.verify_warnings")
	vrh_rc=0
	verify_current "$vrh_errors" "$vrh_warnings" || vrh_rc=$?
	[ ! -s "$vrh_warnings" ] || cat "$vrh_warnings" >&2
	[ ! -s "$vrh_errors" ] || cat "$vrh_errors" >&2
	[ "$vrh_rc" -ne 0 ] || printf 'Project verified.\n'
	rm -f "$vrh_errors" "$vrh_warnings"
	return "$vrh_rc"
}

# Recursively verify the current project and nested project roots.
verify_recursive() {
	label=$1
	visited=$2
	root_abs=$(abs_path_for .)
	if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
		return 0
	fi
	printf '%s\n' "$root_abs" >>"$visited"
	printf 'Verifying project: %s\n' "$label"
	rc=0
	verify_report_human || rc=1

	subprojects_tmp=$(tmp_for "$MANIFEST_FILE.verify_recursive")
	manifest_subprojects >"$subprojects_tmp"
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
			child_label=$(join_project_label "$label" "$path")
			(
				cd "$path" || exit 1
				verify_recursive "$child_label" "$visited"
			) || rc=1
		fi
	done <"$subprojects_tmp"
	rm -f "$subprojects_tmp"
	return "$rc"
}

# Validate project state, optionally including nested projects.
cmd_verify() {
	parse_recursive_output verify "$@"
	recursive=$PARSED_RECURSIVE
	json=$PARSED_JSON
	json_pretty=$PARSED_JSON_PRETTY
	[ "$PARSED_PORCELAIN" -eq 0 ] || usage_error "verify does not support --porcelain"
	if [ "$json" -eq 1 ]; then
		# Use uniquely named variables so verify_current cannot clobber them, and
		# feed errors/warnings straight from verify_current for clean separation.
		v_rows=$(mktemp)
		v_errors=$(mktemp)
		v_warnings=$(mktemp)
		: >"$v_rows"
		: >"$v_errors"
		: >"$v_warnings"
		v_rc=0
		if [ "$recursive" -eq 1 ]; then
			# Recursive verification aggregates human findings across nests; capture
			# them as diagnostic lines (warnings and errors are not separated here).
			v_out=$(mktemp)
			v_visited=$(mktemp)
			: >"$v_visited"
			verify_recursive "." "$v_visited" >"$v_out" 2>"$v_errors" || v_rc=$?
			rm -f "$v_visited" "$v_out"
		else
			verify_current "$v_errors" "$v_warnings" || v_rc=$?
		fi
		[ "$v_rc" -eq 0 ] && ok=1 || ok=0
		emit_json_result verify "$recursive" "$ok" "$v_rows" "$v_errors" "$v_warnings" "$json_pretty"
		rm -f "$v_rows" "$v_errors" "$v_warnings"
		[ "$v_rc" -eq 0 ] || return "$EXIT_ISSUES"
		return 0
	fi
	if [ "$recursive" -eq 1 ]; then
		visited=$(mktemp)
		: >"$visited"
		verify_recursive "." "$visited"
		rc=$?
		rm -f "$visited"
		return "$rc"
	fi
	# Capture and return the verification result explicitly so the trailing
	# notice cannot mask a failure (same class of bug fixed in cmd_snapshot).
	verify_rc=0
	verify_report_human || verify_rc=$?
	notice_nested_projects
	return "$verify_rc"
}

# Validate positive integer options such as log --max-count.
is_positive_integer() {
	case "$1" in
	"" | *[!0-9]*) return 1 ;;
	0) return 1 ;;
	*) return 0 ;;
	esac
}

# Append one repository's recent commits to the combined project log input.
append_log_for_repo() {
	log_repo=$1
	log_label=$2
	log_out=$3
	log_max_count=$4
	log_since=$5
	log_until=$6
	log_filter=$7
	log_visited_repos=$8

	if [ -n "$log_filter" ] && [ "$log_filter" != "$log_label" ]; then
		return 0
	fi
	if [ ! -d "$log_repo/.git" ]; then
		warn "missing repository for log: $log_label"
		return 0
	fi
	log_repo_abs=$(abs_path_for "$log_repo")
	if grep -F -x "$log_repo_abs" "$log_visited_repos" >/dev/null 2>&1; then
		return 0
	fi
	printf '%s\n' "$log_repo_abs" >>"$log_visited_repos"
	git -C "$log_repo" rev-parse --verify HEAD >/dev/null 2>&1 || return 0

	if [ -n "$log_since" ] && [ -n "$log_until" ]; then
		git -C "$log_repo" log --max-count="$log_max_count" --since="$log_since" --until="$log_until" --format='%ct|%cI|%h|%s'
	elif [ -n "$log_since" ]; then
		git -C "$log_repo" log --max-count="$log_max_count" --since="$log_since" --format='%ct|%cI|%h|%s'
	elif [ -n "$log_until" ]; then
		git -C "$log_repo" log --max-count="$log_max_count" --until="$log_until" --format='%ct|%cI|%h|%s'
	else
		git -C "$log_repo" log --max-count="$log_max_count" --format='%ct|%cI|%h|%s'
	fi | while IFS='|' read -r epoch iso sha subject; do
		[ -n "$epoch" ] || continue
		printf '%s|%s|%s|%s|%s\n' "$epoch" "$iso" "$log_label" "$sha" "$subject" >>"$log_out"
	done
}

# Collect commits from the current project, recursing into nested projects on demand.
collect_log_for_project() {
	label=$1
	out=$2
	max_count=$3
	since=$4
	until=$5
	recursive=$6
	filter=$7
	visited_projects=$8
	visited_repos=$9

	root_abs=$(abs_path_for .)
	if grep -F -x "$root_abs" "$visited_projects" >/dev/null 2>&1; then
		return 0
	fi
	printf '%s\n' "$root_abs" >>"$visited_projects"
	root_label=${label:-.}
	append_log_for_repo . "$root_label" "$out" "$max_count" "$since" "$until" "$filter" "$visited_repos"

	subprojects_tmp=$(tmp_for "$MANIFEST_FILE.log_subprojects")
	manifest_subprojects >"$subprojects_tmp"
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		child_label=$(join_project_label "$label" "$path")
		if [ -d "$path/.git" ]; then
			append_log_for_repo "$path" "$child_label" "$out" "$max_count" "$since" "$until" "$filter" "$visited_repos"
			if [ "$recursive" -eq 1 ] && [ -f "$path/$MANIFEST_FILE" ]; then
				(
					cd "$path" || exit 1
					collect_log_for_project "$child_label" "$out" "$max_count" "$since" "$until" "$recursive" "$filter" "$visited_projects" "$visited_repos"
				)
			fi
		elif [ -z "$filter" ] || [ "$filter" = "$child_label" ]; then
			warn "missing repository for log: $child_label"
		fi
	done <"$subprojects_tmp"
	rm -f "$subprojects_tmp"
}

# Show a combined, read-only history view across the active project.
cmd_log() {
	max_count=50
	since=
	until=
	subproject_filter=
	oneline=0
	recursive=0

	while [ $# -gt 0 ]; do
		case "$1" in
		--max-count)
			[ $# -ge 2 ] || die "--max-count requires a value"
			is_positive_integer "$2" || die "--max-count must be a positive integer"
			max_count=$2
			shift 2
			;;
		--since)
			[ $# -ge 2 ] || die "--since requires a value"
			since=$2
			shift 2
			;;
		--until)
			[ $# -ge 2 ] || die "--until requires a value"
			until=$2
			shift 2
			;;
		--subproject)
			[ $# -ge 2 ] || die "--subproject requires a value"
			if [ "$2" = "." ]; then
				subproject_filter=.
			else
				reject_backslash_path "$2"
				subproject_filter=$(normalize_path "$2")
				[ -n "$(subproject_repo "$subproject_filter" || true)" ] ||
					die "--subproject must be . or a subproject path in $MANIFEST_FILE"
			fi
			shift 2
			;;
		--oneline)
			oneline=1
			shift
			;;
		--recursive)
			recursive=1
			shift
			;;
		*) die "unknown log option: $1" ;;
		esac
	done

	ensure_manifest
	log_tmp=$(mktemp)
	sorted_tmp=$(mktemp)
	visited_projects=$(mktemp)
	visited_repos=$(mktemp)
	: >"$log_tmp"
	: >"$visited_projects"
	: >"$visited_repos"

	collect_log_for_project "" "$log_tmp" "$max_count" "$since" "$until" "$recursive" "$subproject_filter" "$visited_projects" "$visited_repos"
	sort -t '|' -k1,1nr "$log_tmp" | sed -n "1,${max_count}p" >"$sorted_tmp"

	if [ "$oneline" -eq 1 ]; then
		awk -F '|' '{ printf "%-24s %s %s\n", $3, $4, $5 }' "$sorted_tmp"
	else
		awk -F '|' '{ printf "%s  %-24s  %s  %s\n", $2, $3, $4, $5 }' "$sorted_tmp"
	fi

	rm -f "$log_tmp" "$sorted_tmp" "$visited_projects" "$visited_repos"
	if [ "$recursive" -eq 0 ]; then
		notice_nested_projects
	fi
}

# Start a coordinated branch, or record current state when branch is ".".
cmd_start() {
	install_hooks=0
	dirty_action=ask
	sure=0
	branch=

	# Parse options in any position so users can put --hooks after the branch.
	while [ $# -gt 0 ]; do
		case "$1" in
		--hooks)
			install_hooks=1
			shift
			;;
		--sure)
			sure=1
			shift
			;;
		--stash-dirty)
			dirty_action=stash
			shift
			;;
		--discard-dirty)
			dirty_action=discard
			shift
			;;
		--cancel-dirty)
			dirty_action=cancel
			shift
			;;
		--*) die "unknown start option: $1" ;;
		*)
			[ -z "$branch" ] || die "usage: git-nest start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]"
			branch=$1
			shift
			;;
		esac
	done
	[ -n "$branch" ] || die "usage: git-nest start <ticket-and-slug|.> [--stash-dirty|--discard-dirty|--cancel-dirty] [--hooks] [--sure]"
	[ -d .git ] && startup_new=0 || startup_new=1
	confirm_startup_directory "$sure"
	ensure_outer_repo
	acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	ensure_gitattributes_guard

	if [ "$branch" = "." ]; then
		quiet_arg=
		if [ -n "${GIT_NEST_SNAPSHOT_QUIET:-}" ] || [ -n "${GIT_NEST_RECORD_REMOVED_QUIET:-}" ]; then
			quiet_arg=--quiet
		fi
		cmd_snapshot ${quiet_arg:+--quiet}
		[ "$install_hooks" -eq 0 ] || install_hooks_all
		return
	fi

	# Dirty repositories are handled before any checkout so the workspace is not
	# left half-switched if the user cancels or untracked files block discard.
	ticket=$(ticket_from_branch "$branch")
	if [ "$startup_new" -eq 0 ]; then
		dirty_tmp=$(mktemp)
		dirty_repos_file "$dirty_tmp"
		resolve_start_dirty "$dirty_action" "$dirty_tmp"
		rm -f "$dirty_tmp"
	fi

	# Switch the outer repository first, then checked-out subprojects. Missing
	# subprojects stay in the manifest and can later be restored by sync.
	if git show-ref --verify --quiet "refs/heads/$branch"; then
		git checkout "$branch" || die "failed to check out outer branch $branch"
	else
		git checkout -b "$branch" || die "failed to create outer branch $branch"
	fi

	manifest_subprojects | while IFS= read -r path; do
		[ -d "$path/.git" ] || continue
		if git -C "$path" show-ref --verify --quiet "refs/heads/$branch"; then
			git -C "$path" checkout "$branch" || die "failed to check out branch $branch in subproject $path"
		else
			git -C "$path" checkout -b "$branch" || die "failed to create branch $branch in subproject $path"
		fi
	done

	# Only project metadata is written here. Subproject pending state is created later
	# by snapshot/upload once a subproject actually has committed work.
	manifest_write_project "$ticket" "$branch"
	[ "$install_hooks" -eq 0 ] || install_hooks_all
	printf 'Started project branch %s.\n' "$branch"
}

# Resolve a snapshot path argument relative to the caller, then map it to a
# manifest subproject. Empty output means "all subprojects".
snapshot_selected_subprojects() {
	arg=${1:-}
	if [ -z "$arg" ]; then
		manifest_subprojects
		return 0
	fi
	caller=${GIT_NEST_CALLER_PWD:-$(pwd -P)}
	root=$(pwd -P)
	target_abs=$(CDPATH='' cd -- "$caller" && {
		if [ -d "$arg" ]; then
			CDPATH='' cd -P -- "$arg" && pwd
		else
			dir=$(dirname -- "$arg")
			base=$(basename -- "$arg")
			CDPATH='' cd -P -- "$dir" && printf '%s/%s\n' "$(pwd)" "$base"
		fi
	}) || precondition_error "cannot resolve snapshot path: $arg"
	if [ "$target_abs" = "$root" ]; then
		manifest_subprojects
		return 0
	fi
	match=
	manifest_subprojects | while IFS= read -r path; do
		[ -n "$path" ] || continue
		[ -d "$path" ] || continue
		path_abs=$(CDPATH='' cd -P -- "$path" && pwd) || continue
		case "$target_abs" in
		"$path_abs" | "$path_abs"/*)
			printf '%s\n' "$path"
			exit 0
			;;
		esac
	done
}

snapshot_one_subproject() {
	path=$1
	quiet=$2
	dry_run=$3
	strict=$4
	check_only=$5
	[ -d "$path/.git" ] || {
		[ "$quiet" -eq 1 ] || warn "skipping missing subproject $path during snapshot; run git-nest restore first"
		[ "$strict" -eq 1 ] && return "$EXIT_PRECONDITION"
		return 0
	}
	repo=$(subproject_repo "$path")
	require_value "$repo" "subproject $path is missing repo in $MANIFEST_FILE; run git-nest add again or fix the manifest"
	if repo_has_dirty "$path"; then
		[ "$quiet" -eq 1 ] || warn "cannot snapshot $path: working tree is dirty; commit, stash, or discard changes first"
		[ "$strict" -eq 1 ] && return "$EXIT_ISSUES"
		return 0
	fi
	head=$(resolve_head_commit "$path" "cannot snapshot subproject $path")
	target=$(subproject_key "$path" target_branch || true)
	[ -n "$target" ] || target=$(default_target_branch "$path")
	if ! subproject_head_is_reproducible "$path" "$head"; then
		[ "$quiet" -eq 1 ] || warn "cannot snapshot $path at $(printf '%s' "$head" | cut -c1-12): commit is not reachable from origin or a local tag; push the subproject first"
		[ "$strict" -eq 1 ] && return "$EXIT_ISSUES"
		return 0
	fi
	old_revision=$(subproject_key "$path" revision || true)
	if [ "$old_revision" = "$head" ]; then
		[ "$quiet" -eq 1 ] || printf 'Snapshot unchanged for %s at %.12s.\n' "$path" "$head"
		return 0
	fi
	if [ "$dry_run" -eq 1 ] || [ "$check_only" -eq 1 ]; then
		printf '[dry-run] %s revision: %s -> %s\n' "$path" "${old_revision:-<unset>}" "$head"
		[ "$check_only" -eq 1 ] && return "$EXIT_ISSUES"
		return 0
	fi
	manifest_write_subproject "$path" "$repo" tracked "$target" "$head"
	[ "$quiet" -eq 1 ] || printf 'Snapshotted %s at %.12s.\n' "$path" "$head"
}

snapshot_current() {
	quiet=$1
	dry_run=${2:-0}
	selected=${3:-}
	strict=${4:-0}
	check_only=${5:-0}
	ensure_outer_repo
	[ "$dry_run" -eq 1 ] || [ "$check_only" -eq 1 ] || acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	selected_paths=$(snapshot_selected_subprojects "$selected")
	if [ -z "$selected_paths" ]; then
		[ -z "$selected" ] || precondition_error "snapshot path is not the nest root or a managed subproject: $selected"
		[ "$quiet" -eq 1 ] || [ "$check_only" -eq 1 ] || printf 'Refreshed git-nest snapshot.\n'
		return 0
	fi
	rc=0
	printf '%s\n' "$selected_paths" | while IFS= read -r path; do
		[ -n "$path" ] || continue
		snapshot_one_subproject "$path" "$quiet" "$dry_run" "$strict" "$check_only" || exit $?
	done || rc=$?
	clear_base_overrides
	[ "$quiet" -eq 1 ] || [ "$check_only" -eq 1 ] || printf 'Refreshed git-nest snapshot.\n'
	return "$rc"
}

snapshot_recursive() {
	label=$1
	visited=$2
	quiet=$3
	dry_run=${4:-0}
	strict=${5:-0}
	check_only=${6:-0}
	root_abs=$(abs_path_for .)
	if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
		return 0
	fi
	printf '%s\n' "$root_abs" >>"$visited"
	[ "$quiet" -eq 1 ] || printf 'Snapshotting project: %s\n' "$label"
	snapshot_current "$quiet" "$dry_run" "" "$strict" "$check_only"
	cleanup_manifest_lock

	subprojects_tmp=$(tmp_for "$MANIFEST_FILE.snapshot_recursive")
	manifest_subprojects >"$subprojects_tmp"
	rc=0
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
			child_label=$(join_project_label "$label" "$path")
			(
				cd "$path" || exit 1
				snapshot_recursive "$child_label" "$visited" "$quiet" "$dry_run" "$strict" "$check_only"
			) || rc=1
		fi
	done <"$subprojects_tmp"
	rm -f "$subprojects_tmp"
	return "$rc"
}

# Snapshot manifest state from local branches without pushing anything.
cmd_snapshot() {
	quiet=0
	recursive=0
	dry_run=0
	strict=0
	check_only=0
	selected=
	clear_base_overrides
	while [ $# -gt 0 ]; do
		case "$1" in
		--recursive)
			recursive=1
			shift
			;;
		--quiet)
			quiet=1
			shift
			;;
		--dry-run)
			dry_run=1
			GIT_NEST_DRY_RUN=1
			shift
			;;
		--check)
			check_only=1
			GIT_NEST_DRY_RUN=1
			shift
			;;
		--strict)
			strict=1
			shift
			;;
		--no-fetch)
			GIT_NEST_NO_FETCH=1
			shift
			;;
		--base)
			[ $# -ge 2 ] || usage_error "--base requires <subproject>=<ref>"
			add_base_override "$2"
			shift 2
			;;
		--*) usage_error "unknown snapshot option: $1" ;;
		*)
			[ -z "$selected" ] || usage_error "snapshot accepts at most one path"
			selected=$1
			shift
			;;
		esac
	done
	[ "$recursive" -eq 0 ] || [ -z "$selected" ] || usage_error "snapshot --recursive cannot be combined with a path"
	if [ "$recursive" -eq 1 ]; then
		visited=$(mktemp)
		: >"$visited"
		snapshot_recursive "." "$visited" "$quiet" "$dry_run" "$strict" "$check_only"
		rc=$?
		rm -f "$visited"
		return "$rc"
	fi
	# Capture the snapshot result and return it explicitly. Without this, the
	# trailing notice command would become the function's exit status and mask a
	# nonzero result, which breaks callers that inspect it (for example the root
	# pre-push hook's `if ! cmd_snapshot --check --strict --quiet`).
	snapshot_current "$quiet" "$dry_run" "$selected" "$strict" "$check_only"
	snapshot_rc=$?
	[ "$quiet" -eq 1 ] || notice_nested_snapshot_candidates
	return "$snapshot_rc"
}

# Find the base commit used to compare subproject work against its target branch.

# Count commits in a subproject that are ahead of the resolved base revision.

# Commit outer manifest/config changes when there is a configured Git identity.
commit_manifest_if_needed() {
	branch=$1
	[ -f "$MANIFEST_FILE" ] && git add "$MANIFEST_FILE" 2>/dev/null || true
	[ -f .gitignore ] && git add .gitignore 2>/dev/null || true
	[ -f "$CONFIG_FILE" ] && git add "$CONFIG_FILE" 2>/dev/null || true
	if git diff --cached --quiet; then
		return
	fi
	if git config user.name >/dev/null 2>&1 && git config user.email >/dev/null 2>&1; then
		git commit -m "Update git-nest manifest for $branch" >/dev/null ||
			die "failed to commit manifest update on $branch"
	else
		warn "manifest changed but Git user.name/user.email are not configured; skipping outer commit"
	fi
}

# Push changed subproject branches, record pending/finalized state, and push the outer branch.
cmd_upload() {
	finalize=0
	dry_run=0
	clear_base_overrides
	while [ $# -gt 0 ]; do
		case "$1" in
		--finalize)
			finalize=1
			shift
			;;
		--dry-run)
			dry_run=1
			GIT_NEST_DRY_RUN=1
			shift
			;;
		--no-fetch)
			GIT_NEST_NO_FETCH=1
			shift
			;;
		--base)
			[ $# -ge 2 ] || usage_error "--base requires <subproject>=<ref>"
			add_base_override "$2"
			shift 2
			;;
		*) usage_error "unknown upload option: $1" ;;
		esac
	done
	[ "$dry_run" -eq 1 ] || acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	branch=$(current_branch)
	[ "$branch" != "HEAD" ] || die "upload requires a named branch"

	subprojects_tmp=$(tmp_for "$MANIFEST_FILE.subprojects")
	manifest_subprojects >"$subprojects_tmp"

	# A dirty subproject blocks the whole upload so the manifest never records a
	# branch that does not contain all local work.
	while IFS= read -r path; do
		[ -d "$path/.git" ] || continue
		dirty=$(repo_status_porcelain "$path" "cannot inspect subproject $path before upload")
		[ -z "$dirty" ] || die "subproject $path has uncommitted changes; commit or stash before upload"
	done <"$subprojects_tmp"

	upload_plan=$(tmp_for "$MANIFEST_FILE.upload_plan")
	: >"$upload_plan"

	# Candidate branches from start are skipped unless they have commits ahead
	# of the target branch. Preflight every changed subproject before pushing or
	# rewriting the manifest so one bad repository does not strand earlier ones
	# in a surprising partially uploaded state.
	while IFS= read -r path; do
		[ -d "$path/.git" ] || continue
		repo=$(subproject_repo "$path")
		require_value "$repo" "subproject $path is missing repo in $MANIFEST_FILE; run git-nest add again or fix the manifest"
		target=$(subproject_key "$path" target_branch || true)
		[ -n "$target" ] || target=$(default_target_branch "$path")
		mod_branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
		if [ "$dry_run" -eq 1 ]; then
			if ! work_count=$(subproject_work_count "$path" "$target" 2>/dev/null); then
				printf '[dry-run] %s upload state: unknown; real run would fetch first if needed\n' "$path"
				continue
			fi
		else
			work_count=$(subproject_work_count "$path" "$target")
		fi
		if [ "$work_count" -gt 0 ]; then
			[ -n "$mod_branch" ] || die "subproject $path has committed work on detached HEAD; check out a branch before upload"
			base=$(base_for_subproject "$path" "$target")
			pushed=$(resolve_head_commit "$path" "cannot upload subproject $path")
			remote_exists "$path" || die "subproject $path has no origin remote; restore or add origin, then rerun git-nest upload"
			if [ "$dry_run" -eq 1 ]; then
				printf '[dry-run] would push subproject %s branch %s with refspec HEAD:%s\n' "$path" "$mod_branch" "$mod_branch"
				if [ "$finalize" -eq 1 ]; then
					printf '[dry-run] would finalize %s at %s from branch %s\n' "$path" "$pushed" "$mod_branch"
				else
					printf '[dry-run] would record pending %s target=%s branch=%s base=%s pushed=%s\n' "$path" "$target" "$mod_branch" "$base" "$pushed"
				fi
				continue
			fi
			printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$path" "$repo" "$target" "$mod_branch" "$base" "$pushed" >>"$upload_plan"
		fi
	done <"$subprojects_tmp"

	if [ "$dry_run" -eq 0 ]; then
		while IFS='	' read -r path repo target mod_branch base pushed; do
			[ -n "$path" ] || continue
			if ! git -C "$path" push -u origin "HEAD:$mod_branch"; then
				printf 'Error: failed to push subproject %s branch %s to origin\n' "$path" "$mod_branch" >&2
				printf '  recovery: fix the remote, credentials, or rejected branch, then rerun git-nest upload.\n' >&2
				printf '  note: any subproject branches already pushed by this run may remain on their remotes; rerunning upload will reuse the current manifest and branch state.\n' >&2
				rm -f "$upload_plan" "$subprojects_tmp"
				return "$EXIT_GIT"
			fi
			if [ "$finalize" -eq 1 ]; then
				manifest_write_subproject "$path" "$repo" finalized "$pushed" "" "$mod_branch"
				printf 'Uploaded and finalized subproject %s branch %s at %.12s.\n' "$path" "$mod_branch" "$pushed"
			else
				manifest_write_subproject "$path" "$repo" pending "$target" "$mod_branch" "$base" "$pushed"
				printf 'Uploaded subproject %s branch %s at %.12s.\n' "$path" "$mod_branch" "$pushed"
			fi
		done <"$upload_plan"
	fi
	rm -f "$upload_plan"
	rm -f "$subprojects_tmp"

	# The outer push is best-effort when no origin is configured; subproject pushes
	# remain strict because pending manifest state points at those branches.
	if [ "$dry_run" -eq 1 ]; then
		if remote_exists .; then
			printf '[dry-run] would push outer branch %s with refspec HEAD:%s\n' "$branch" "$branch"
		else
			printf '[dry-run] outer repository has no origin remote; would skip outer push\n'
		fi
	else
		commit_manifest_if_needed "$branch"
		if remote_exists .; then
			git push -u origin "HEAD:$branch" || git_error "failed to push outer branch $branch to origin"
		else
			warn "outer repository has no origin remote; skipped outer push"
		fi
	fi
	clear_base_overrides
}

# Read the manifest revision value used as a diff base.

# Emit changed subproject commits since the recorded manifest revisions.
diff_porcelain_from_manifest() {
	base_manifest=$1
	rows=$2
	errors=$3
	: >"$rows"

	manifest_subprojects_from_file "$base_manifest" | while IFS= read -r path; do
		[ -n "$path" ] || continue
		base=$(manifest_diff_base_from_file "$base_manifest" "$path")
		if [ -z "$base" ]; then
			printf 'E\t%s\tmissing-base\t-\t-\t-\tmissing-recorded-revision\n' "$path" >>"$rows"
			printf 'Error: %s has no recorded revision in %s\n' "$path" "$base_manifest" >>"$errors"
			continue
		fi
		if [ ! -d "$path/.git" ]; then
			printf 'E\t%s\tmissing\t-\t%s\t-\tcheckout-missing\n' "$path" "$base" >>"$rows"
			printf 'Error: %s checkout is missing\n' "$path" >>"$errors"
			continue
		fi
		head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || true)
		if [ -z "$head" ]; then
			printf 'E\t%s\tmissing-head\t-\t%s\t-\thead-unresolved\n' "$path" "$base" >>"$rows"
			printf 'Error: cannot resolve HEAD in %s\n' "$path" >>"$errors"
			continue
		fi
		if [ "$base" = "$head" ]; then
			continue
		fi
		if ! git -C "$path" rev-parse --verify "$base^{commit}" >/dev/null 2>&1; then
			printf 'E\t%s\tmissing-base\t-\t%s\t%s\tbase-unresolved\n' "$path" "$base" "$head" >>"$rows"
			printf 'Error: cannot resolve recorded revision %.12s in %s\n' "$base" "$path" >>"$errors"
			continue
		fi
		git -C "$path" log --format='%H%x09%s' "$base..HEAD" | while IFS='	' read -r sha subject; do
			[ -n "$sha" ] || continue
			safe_subject=$(printf '%s\n' "$subject" | tr '	' ' ')
			printf 'L\t%s\tdiff\t%s\t%s\t%s\t%s\n' "$path" "$base" "$head" "$sha" "$safe_subject" >>"$rows"
		done
	done
}

# Show changed subproject commits relative to manifest-recorded revisions.
cmd_diff() {
	since=
	stat=0
	json=0
	json_pretty=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--since)
			[ $# -ge 2 ] || usage_error "--since requires a ref"
			since=$2
			shift 2
			;;
		--stat)
			stat=1
			shift
			;;
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			json_pretty=1
			shift
			;;
		*) usage_error "unknown diff option: $1" ;;
		esac
	done
	ensure_manifest
	validate_manifest_schema

	base_manifest=$MANIFEST_FILE
	base_label=$MANIFEST_FILE
	if [ -n "$since" ]; then
		base_manifest=$(tmp_for "$MANIFEST_FILE.diff_since")
		if ! git show "$since:$MANIFEST_FILE" >"$base_manifest" 2>/dev/null; then
			rm -f "$base_manifest"
			precondition_error "cannot read $MANIFEST_FILE at $since"
		fi
		base_label="$since:$MANIFEST_FILE"
	fi

	rows=$(tmp_for "$MANIFEST_FILE.diff_rows")
	errors=$(tmp_for "$MANIFEST_FILE.diff_errors")
	warnings=$(tmp_for "$MANIFEST_FILE.diff_warnings")
	: >"$errors"
	: >"$warnings"
	diff_porcelain_from_manifest "$base_manifest" "$rows" "$errors"

	if [ "$json" -eq 1 ]; then
		if [ -s "$rows" ] || [ -s "$errors" ]; then ok=0; else ok=1; fi
		emit_json_result diff 0 "$ok" "$rows" "$errors" "$warnings" "$json_pretty"
		rm -f "$rows" "$errors" "$warnings"
		[ "$base_manifest" = "$MANIFEST_FILE" ] || rm -f "$base_manifest"
		[ "$ok" -eq 1 ] || return "$EXIT_ISSUES"
		return 0
	fi

	if [ ! -s "$rows" ]; then
		printf 'No subproject commit differences since %s.\n' "$base_label"
		rm -f "$rows" "$errors" "$warnings"
		[ "$base_manifest" = "$MANIFEST_FILE" ] || rm -f "$base_manifest"
		return 0
	fi

	current_path=
	while IFS='	' read -r code path state base head sha detail; do
		[ -n "$code" ] || continue
		if [ "$code" = "E" ]; then
			continue
		fi
		if [ "$current_path" != "$path" ]; then
			[ -z "$current_path" ] || printf '\n'
			current_path=$path
			printf '%s: %s..%s\n' "$path" "$(printf '%s\n' "$base" | cut -c1-12)" "$(printf '%s\n' "$head" | cut -c1-12)"
			if [ "$stat" -eq 1 ]; then
				git -C "$path" log --stat --oneline "$base..HEAD"
				continue
			fi
		fi
		if [ "$stat" -eq 0 ]; then
			printf '  %.12s %s\n' "$sha" "$detail"
		fi
	done <"$rows"

	if [ -s "$errors" ]; then
		cat "$errors" >&2
	fi
	had_errors=0
	[ ! -s "$errors" ] || had_errors=1
	rm -f "$rows" "$errors" "$warnings"
	[ "$base_manifest" = "$MANIFEST_FILE" ] || rm -f "$base_manifest"
	[ "$had_errors" -eq 0 ] || return "$EXIT_ISSUES"
	return "$EXIT_ISSUES"
}

config_manifest_key() {
	case "$1" in
	clone-mode) printf 'clone\n' ;;
	*) return 1 ;;
	esac
}

validate_config_value() {
	key=$1
	value=$2
	case "$key:$value" in
	clone-mode:full | clone-mode:partial) ;;
	*) usage_error "$key must be full or partial" ;;
	esac
}

# Uses an emsp_-prefixed path (rather than bare path) because cmd_config's
# get/set/list/unset branches call this without a subshell while holding
# their own bare path across the call.
ensure_manifest_subproject_path() {
	emsp_path=$1
	if ! manifest_subprojects | grep -F -x "$emsp_path" >/dev/null 2>&1; then
		precondition_error "unknown subproject: $emsp_path"
	fi
}

# Manage manifest-backed subproject settings.
cmd_config() {
	[ $# -ge 1 ] || usage_error "usage: git-nest config <get|set|list|unset> ..."
	action=$1
	shift
	ensure_manifest
	validate_manifest_schema

	case "$action" in
	get)
		[ $# -eq 2 ] || usage_error "usage: git-nest config get <path> clone-mode"
		reject_backslash_path "$1"
		path=$(normalize_path "$1")
		key=$2
		manifest_key=$(config_manifest_key "$key") || usage_error "unknown config key: $key"
		assert_path_not_inside_nested_project "$path"
		ensure_manifest_subproject_path "$path"
		value=$(subproject_key "$path" "$manifest_key" || true)
		[ -n "$value" ] || return 1
		printf '%s\n' "$value"
		;;
	set)
		[ $# -eq 3 ] || usage_error "usage: git-nest config set <path> clone-mode <value>"
		reject_backslash_path "$1"
		path=$(normalize_path "$1")
		key=$2
		value=$3
		manifest_key=$(config_manifest_key "$key") || usage_error "unknown config key: $key"
		validate_config_value "$key" "$value"
		assert_path_not_inside_nested_project "$path"
		ensure_manifest_subproject_path "$path"
		acquire_manifest_lock
		manifest_set_subproject_key "$path" "$manifest_key" "$value"
		warn "set $key for $path to $value; existing checkouts are not converted"
		;;
	list)
		[ $# -le 1 ] || usage_error "usage: git-nest config list [<path>]"
		if [ $# -eq 1 ]; then
			reject_backslash_path "$1"
			path=$(normalize_path "$1")
			assert_path_not_inside_nested_project "$path"
			ensure_manifest_subproject_path "$path"
			value=$(subproject_key "$path" clone || true)
			if [ -n "$value" ]; then
				printf '%s\tclone-mode=%s\n' "$path" "$value"
			fi
		else
			manifest_subprojects | while IFS= read -r path; do
				[ -n "$path" ] || continue
				value=$(subproject_key "$path" clone || true)
				if [ -n "$value" ]; then
					printf '%s\tclone-mode=%s\n' "$path" "$value"
				fi
			done
		fi
		;;
	unset)
		[ $# -eq 2 ] || usage_error "usage: git-nest config unset <path> clone-mode"
		reject_backslash_path "$1"
		path=$(normalize_path "$1")
		key=$2
		manifest_key=$(config_manifest_key "$key") || usage_error "unknown config key: $key"
		assert_path_not_inside_nested_project "$path"
		ensure_manifest_subproject_path "$path"
		acquire_manifest_lock
		manifest_remove_subproject_key "$path" "$manifest_key"
		;;
	*) usage_error "unknown config action: $action" ;;
	esac
}

# Shared foreach engine for all subprojects or only manifest-pending subprojects.
run_foreach() {
	mode=$1
	shift
	include_root_first=0
	include_root_last=0
	only_nested=0
	no_nested=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--include-root-first)
			include_root_first=1
			shift
			;;
		--include-root-last)
			include_root_last=1
			shift
			;;
		--only-nested)
			only_nested=1
			shift
			;;
		--no-nested)
			no_nested=1
			shift
			;;
		--)
			shift
			break
			;;
		--*) usage_error "unknown $mode option: $1" ;;
		*) break ;;
		esac
	done
	[ "$only_nested" -eq 0 ] || [ "$no_nested" -eq 0 ] || usage_error "$mode cannot combine --only-nested with --no-nested"
	[ $# -gt 0 ] || die "usage: git-nest $mode [--include-root-first|--include-root-last] [--only-nested|--no-nested] [--] <command> [args...]"

	root=$(repo_root)
	root=$(CDPATH='' cd -- "$root" && pwd)
	subprojects_tmp=$(tmp_for "$MANIFEST_FILE.foreach")
	manifest_subprojects >"$subprojects_tmp"

	rc=0

	run_foreach_in_root() {
		child_rc=0
		(
			cd "$root" || exit 1
			GIT_NEST_ROOT=$root \
				GIT_NEST_SUBPROJECT_PATH=. \
				"$@"
		) || child_rc=$?
		return "$child_rc"
	}

	if [ "$include_root_first" -eq 1 ]; then
		run_foreach_in_root "$@" || rc=$?
	fi

	while IFS= read -r path; do
		[ -n "$path" ] || continue
		pending=$(subproject_key "$path" pending_branch || true)
		if [ "$mode" = "foreach-pending" ] && [ -z "$pending" ]; then
			continue
		fi
		if { [ "$only_nested" -eq 1 ] || [ "$no_nested" -eq 1 ]; }; then
			is_nested=0
			[ -f "$path/$MANIFEST_FILE" ] && is_nested=1
			[ "$only_nested" -eq 0 ] || [ "$is_nested" -eq 1 ] || continue
			[ "$no_nested" -eq 0 ] || [ "$is_nested" -eq 0 ] || continue
		fi
		if [ ! -d "$path/.git" ]; then
			warn "skipping missing subproject $path"
			continue
		fi

		repo=$(subproject_repo "$path")
		target=$(subproject_key "$path" target_branch || true)
		base=$(subproject_key "$path" base_revision || true)
		pushed=$(subproject_key "$path" pushed_commit || true)
		revision=$(subproject_key "$path" revision || true)
		tag=$(subproject_key "$path" tag || true)
		branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
		subproject_abs=$(CDPATH='' cd -- "$path" && pwd)

		# Run in a subshell so each subproject gets its own working directory and
		# exported context without leaking changes into the next iteration.
		(
			cd "$path" || exit 1
			GIT_NEST_ROOT=$root \
				GIT_NEST_SUBPROJECT_PATH=$path \
				GIT_NEST_SUBPROJECT_ABSPATH=$subproject_abs \
				GIT_NEST_SUBPROJECT_REPO=$repo \
				GIT_NEST_BRANCH=$branch \
				GIT_NEST_TARGET_BRANCH=$target \
				GIT_NEST_PENDING_BRANCH=$pending \
				GIT_NEST_BASE_REVISION=$base \
				GIT_NEST_PUSHED_COMMIT=$pushed \
				GIT_NEST_REVISION=$revision \
				GIT_NEST_TAG=$tag \
				REPO_PATH=$path \
				REPO_PROJECT=$path \
				"$@"
		) || { rc=$?; [ "$include_root_last" -eq 1 ] || break; }
	done <"$subprojects_tmp"

	if [ "$include_root_last" -eq 1 ]; then
		run_foreach_in_root "$@" || rc=$?
	fi

	rm -f "$subprojects_tmp"
	return "$rc"
}

# Public wrapper for running a command in every checked-out subproject.
cmd_foreach() {
	run_foreach foreach "$@"
}

# Public wrapper for running a command only in pending subprojects.
cmd_foreach_pending() {
	run_foreach foreach-pending "$@"
}

foreach_filtered_rows() {
	mode=$1
	rows=$2
	ffr_only_nested=${3:-0}
	ffr_no_nested=${4:-0}
	: >"$rows"
	manifest_subprojects | while IFS= read -r path; do
		[ -n "$path" ] || continue
		[ -d "$path/.git" ] || continue
		if { [ "$ffr_only_nested" -eq 1 ] || [ "$ffr_no_nested" -eq 1 ]; }; then
			ffr_is_nested=0
			[ -f "$path/$MANIFEST_FILE" ] && ffr_is_nested=1
			[ "$ffr_only_nested" -eq 0 ] || [ "$ffr_is_nested" -eq 1 ] || continue
			[ "$ffr_no_nested" -eq 0 ] || [ "$ffr_is_nested" -eq 0 ] || continue
		fi
		dirty=0
		repo_has_dirty "$path" && dirty=1
		case "$mode:$dirty" in
		foreach-modified:1)
			printf 'F\t%s\tmodified\t-\t-\t-\tdirty\n' "$path" >>"$rows"
			;;
		foreach-clean:0)
			printf 'F\t%s\tclean\t-\t-\t-\tclean\n' "$path" >>"$rows"
			;;
		esac
	done
}

run_foreach_filtered_command() {
	rows=$1
	continue_on_error=$2
	shift 2
	root=$(repo_root)
	root=$(CDPATH='' cd -- "$root" && pwd)
	rc=0

	while IFS='	' read -r code path state target current expected detail; do
		[ -n "$code" ] || continue
		if [ ! -d "$path/.git" ]; then
			warn "skipping missing subproject $path"
			continue
		fi

		repo=$(subproject_repo "$path")
		target=$(subproject_key "$path" target_branch || true)
		pending=$(subproject_key "$path" pending_branch || true)
		base=$(subproject_key "$path" base_revision || true)
		pushed=$(subproject_key "$path" pushed_commit || true)
		revision=$(subproject_key "$path" revision || true)
		tag=$(subproject_key "$path" tag || true)
		branch=$(git -C "$path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
		subproject_abs=$(CDPATH='' cd -- "$path" && pwd)

		child_rc=0
		(
			cd "$path" || exit 1
			GIT_NEST_ROOT=$root \
				GIT_NEST_SUBPROJECT_PATH=$path \
				GIT_NEST_SUBPROJECT_ABSPATH=$subproject_abs \
				GIT_NEST_SUBPROJECT_REPO=$repo \
				GIT_NEST_BRANCH=$branch \
				GIT_NEST_TARGET_BRANCH=$target \
				GIT_NEST_PENDING_BRANCH=$pending \
				GIT_NEST_BASE_REVISION=$base \
				GIT_NEST_PUSHED_COMMIT=$pushed \
				GIT_NEST_REVISION=$revision \
				GIT_NEST_TAG=$tag \
				REPO_PATH=$path \
				REPO_PROJECT=$path \
				"$@"
		) || child_rc=$?
		if [ "$child_rc" -ne 0 ]; then
			[ "$rc" -ne 0 ] || rc=$child_rc
			[ "$continue_on_error" -eq 1 ] || break
		fi
		child_rc=0
	done <"$rows"

	return "$rc"
}

run_foreach_filtered() {
	mode=$1
	shift
	continue_on_error=0
	only_nested=0
	no_nested=0
	porcelain=0
	json=0
	json_pretty=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--continue-on-error)
			continue_on_error=1
			shift
			;;
		--only-nested)
			only_nested=1
			shift
			;;
		--no-nested)
			no_nested=1
			shift
			;;
		--porcelain)
			porcelain=1
			shift
			;;
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			json_pretty=1
			shift
			;;
		--)
			shift
			break
			;;
		--*) usage_error "unknown $mode option: $1" ;;
		*) break ;;
		esac
	done
	if [ "$porcelain" -eq 1 ] && [ "$json" -eq 1 ]; then
		usage_error "$mode cannot combine --porcelain with --json/--json-pretty"
	fi
	if { [ "$porcelain" -eq 1 ] || [ "$json" -eq 1 ]; } && [ $# -gt 0 ]; then
		usage_error "$mode machine-readable output cannot be combined with a command"
	fi
	[ "$only_nested" -eq 0 ] || [ "$no_nested" -eq 0 ] || usage_error "$mode cannot combine --only-nested with --no-nested"

	rows=$(tmp_for "$MANIFEST_FILE.$mode")
	errors=$(tmp_for "$MANIFEST_FILE.$mode.errors")
	warnings=$(tmp_for "$MANIFEST_FILE.$mode.warnings")
	: >"$errors"
	: >"$warnings"
	foreach_filtered_rows "$mode" "$rows" "$only_nested" "$no_nested"

	if [ "$porcelain" -eq 1 ]; then
		cat "$rows"
		rm -f "$rows" "$errors" "$warnings"
		return 0
	fi
	if [ "$json" -eq 1 ]; then
		emit_json_result "$mode" 0 1 "$rows" "$errors" "$warnings" "$json_pretty"
		rm -f "$rows" "$errors" "$warnings"
		return 0
	fi

	[ $# -gt 0 ] || die "usage: git-nest $mode [--continue-on-error] [-- <command> [args...]]"
	run_foreach_filtered_command "$rows" "$continue_on_error" "$@"
	rc=$?
	rm -f "$rows" "$errors" "$warnings"
	return "$rc"
}

cmd_foreach_modified() {
	run_foreach_filtered foreach-modified "$@"
}

cmd_foreach_clean() {
	run_foreach_filtered foreach-clean "$@"
}

current_repo_mark_path() {
	caller=${GIT_NEST_CALLER_PWD:-$(pwd -P)}
	root=$(pwd -P)
	if git_root=$(CDPATH='' cd -- "$caller" && git rev-parse --show-toplevel 2>/dev/null); then
		git_root=$(CDPATH='' cd -P -- "$git_root" && pwd)
	else
		git_root=$root
	fi
	if [ "$git_root" = "$root" ]; then
		printf '.\n'
		return 0
	fi
	manifest_subprojects | while IFS= read -r path; do
		[ -n "$path" ] || continue
		[ -d "$path" ] || continue
		path_abs=$(CDPATH='' cd -P -- "$path" && pwd) || continue
		[ "$git_root" = "$path_abs" ] && {
			printf '%s\n' "$path"
			exit 0
		}
	done
}

repo_origin_url_for_mark() {
	path=$1
	git -C "$path" remote get-url origin 2>/dev/null || true
}

ensure_branch_marks_file() {
	[ -f "$BRANCH_MARKS_FILE" ] || : >"$BRANCH_MARKS_FILE"
	ensure_gitignore_line "$BRANCH_MARKS_FILE"
}

cmd_branch_mark() {
	[ $# -le 1 ] || usage_error "usage: git-nest branch-mark [name]"
	repo_path=$(current_repo_mark_path)
	[ -n "$repo_path" ] || precondition_error "current Git repository is not the nest root or a managed subproject"
	branch=${1:-}
	if [ -z "$branch" ]; then
		branch=$(git -C "$repo_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
		[ -n "$branch" ] || precondition_error "cannot mark detached HEAD; pass a branch name explicitly"
	fi
	origin=$(repo_origin_url_for_mark "$repo_path")
	now=$(utc_now)
	ensure_branch_marks_file
	tmp=$(tmp_for "$BRANCH_MARKS_FILE")
	awk -F '	' -v repo="$repo_path" -v branch="$branch" '!(($1 == repo) && ($2 == branch))' "$BRANCH_MARKS_FILE" >"$tmp"
	printf '%s\t%s\t%s\t%s\n' "$repo_path" "$branch" "$origin" "$now" >>"$tmp"
	mv "$tmp" "$BRANCH_MARKS_FILE"
	printf 'Marked branch %s for %s.\n' "$branch" "$repo_path"
}

cmd_branch_unmark() {
	[ $# -eq 1 ] || usage_error "usage: git-nest branch-unmark <name>"
	repo_path=$(current_repo_mark_path)
	[ -n "$repo_path" ] || precondition_error "current Git repository is not the nest root or a managed subproject"
	branch=$1
	[ -f "$BRANCH_MARKS_FILE" ] || {
		printf 'No branch marks.\n'
		return 0
	}
	tmp=$(tmp_for "$BRANCH_MARKS_FILE")
	awk -F '	' -v repo="$repo_path" -v branch="$branch" '!(($1 == repo) && ($2 == branch))' "$BRANCH_MARKS_FILE" >"$tmp"
	mv "$tmp" "$BRANCH_MARKS_FILE"
	printf 'Unmarked branch %s for %s.\n' "$branch" "$repo_path"
}

cmd_branch_list() {
	verbose=0
	json=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--verbose)
			verbose=1
			shift
			;;
		--json)
			json=1
			shift
			;;
		*) usage_error "unknown branch-list option: $1" ;;
		esac
	done
	if [ ! -s "$BRANCH_MARKS_FILE" ]; then
		[ "$json" -eq 1 ] && printf '{"branches":[]}\n' || printf 'No branch marks.\n'
		return 0
	fi
	if [ "$json" -eq 1 ]; then
		printf '{"branches":['
		first=1
		while IFS='	' read -r repo branch origin seen; do
			[ -n "$repo" ] || continue
			[ "$first" -eq 1 ] || printf ','
			first=0
			printf '{"repo":'
			json_string "$repo"
			printf ',"branch":'
			json_string "$branch"
			printf ',"origin":'
			json_string "$origin"
			printf ',"last_seen":'
			json_string "$seen"
			printf '}'
		done <"$BRANCH_MARKS_FILE"
		printf ']}\n'
		return 0
	fi
	while IFS='	' read -r repo branch origin seen; do
		[ -n "$repo" ] || continue
		if [ "$verbose" -eq 1 ]; then
			printf '%s\t%s\t%s\t%s\n' "$branch" "$repo" "$origin" "$seen"
		else
			printf '%s\t%s\n' "$branch" "$repo"
		fi
	done <"$BRANCH_MARKS_FILE"
}

cmd_branch_cleanup() {
	[ $# -eq 0 ] || usage_error "branch-cleanup takes no arguments"
	[ -f "$BRANCH_MARKS_FILE" ] || {
		printf 'No branch marks.\n'
		return 0
	}
	tmp=$(tmp_for "$BRANCH_MARKS_FILE")
	: >"$tmp"
	removed=0
	while IFS='	' read -r repo branch origin seen; do
		[ -n "$repo" ] || continue
		if [ -d "$repo/.git" ] && git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
			printf '%s\t%s\t%s\t%s\n' "$repo" "$branch" "$origin" "$seen" >>"$tmp"
		else
			removed=$((removed + 1))
		fi
	done <"$BRANCH_MARKS_FILE"
	mv "$tmp" "$BRANCH_MARKS_FILE"
	printf 'Removed %s stale branch mark(s).\n' "$removed"
}

# Resolve the actual hook path for a repo, handling Git's relative path output.
# Report pending subprojects and return nonzero as the outer-merge gate.
no_pending_rows() {
	manifest_subprojects | while IFS= read -r path; do
		pb=$(subproject_key "$path" pending_branch || true)
		[ -n "$pb" ] || continue
		printf 'P\t%s\tpending\t-\t%s\t-\tpending-branch\n' "$path" "$pb"
	done
}

cmd_no_pending() {
	json=0
	json_pretty=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			json_pretty=1
			shift
			;;
		*) usage_error "unknown no-pending option: $1" ;;
		esac
	done
	ensure_manifest
	rows=$(mktemp)
	no_pending_rows >"$rows"
	if [ "$json" -eq 1 ]; then
		errors=$(mktemp)
		warnings=$(mktemp)
		: >"$errors"
		: >"$warnings"
		[ -s "$rows" ] && ok=0 || ok=1
		emit_json_result no-pending 0 "$ok" "$rows" "$errors" "$warnings" "$json_pretty"
		rm -f "$errors" "$warnings"
		[ "$ok" -eq 1 ] || {
			rm -f "$rows"
			return "$EXIT_ISSUES"
		}
		rm -f "$rows"
		return 0
	fi
	while IFS='	' read -r code path state target current expected detail; do
		[ -n "$path" ] || continue
		printf '%s: pending branch %s\n' "$path" "$current"
	done <"$rows"
	if [ -s "$rows" ]; then
		rm -f "$rows"
		return "$EXIT_ISSUES"
	fi
	rm -f "$rows"
	printf 'No pending subprojects.\n'
}

# Delete one local pending branch after or after-deferred finalization cleanup.
# Uses a cbfs_-prefixed path (rather than bare path) because cmd_finalize
# calls this without a subshell while holding its own bare path across the call.
cleanup_branch_for_subproject() {
	cbfs_path=$1
	branch=$2
	[ -n "$branch" ] || return 0
	[ -d "$cbfs_path/.git" ] || return 0
	if ! git -C "$cbfs_path" show-ref --verify --quiet "refs/heads/$branch"; then
		warn "cleanup branch already absent for $cbfs_path: $branch"
		manifest_remove_subproject_key "$cbfs_path" finalized_from_branch
		return 0
	fi
	current=$(git -C "$cbfs_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
	if [ "$current" = "$branch" ]; then
		revision=$(subproject_key "$cbfs_path" revision || true)
		[ -n "$revision" ] || die "cannot clean current branch for $cbfs_path without finalized revision"
		revision=$(resolve_commit "$cbfs_path" "$revision" "cannot clean current branch for $cbfs_path")
		git -C "$cbfs_path" checkout --detach "$revision" >/dev/null ||
			die "failed to detach $cbfs_path at finalized revision $revision"
	fi
	git -C "$cbfs_path" branch -D "$branch" >/dev/null ||
		die "failed to delete local branch $branch in $cbfs_path"
	manifest_remove_subproject_key "$cbfs_path" finalized_from_branch
	printf 'Deleted local branch %s in %s.\n' "$branch" "$cbfs_path"
}

# Delete all local branches recorded as finalized cleanup hints.
cmd_cleanup_branches() {
	[ $# -eq 0 ] || die "cleanup-branches takes no arguments"
	acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	manifest_subprojects | while IFS= read -r path; do
		branch=$(subproject_key "$path" finalized_from_branch || true)
		[ -n "$branch" ] || continue
		cleanup_branch_for_subproject "$path" "$branch"
	done
}

# Update one clean, non-pending subproject to another recorded version.
cmd_update() {
	[ $# -ge 1 ] || die "usage: git-nest update <subproject> [--remote | --target-head | --revision <sha-or-ref> | --tag <tag>] [--branch <branch>] [--no-fetch]"
	reject_backslash_path "$1"
	path=$(normalize_path "$1")
	shift
	acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	assert_path_not_inside_nested_project "$path"
	[ -d "$path/.git" ] || die "$path is not a checked-out subproject; run git-nest restore first"
	repo=$(subproject_repo "$path")
	[ -n "$repo" ] || die "$path is not in $MANIFEST_FILE"
	if repo_has_dirty "$path"; then
		die "$path has uncommitted changes; commit, stash, or discard them before update"
	fi

	update_target=$(subproject_key "$path" target_branch || true)
	[ -n "$update_target" ] || update_target=$(default_target_branch "$path")
	update_mode=target_head
	update_value=
	selected=0
	target_changed=0
	fetch=1
	while [ $# -gt 0 ]; do
		case "$1" in
		--revision)
			[ "$selected" -eq 0 ] || die "update selectors are mutually exclusive"
			[ $# -ge 2 ] || die "--revision requires a value"
			update_mode=revision
			update_value=$2
			selected=1
			shift 2
			;;
		--tag)
			[ "$selected" -eq 0 ] || die "update selectors are mutually exclusive"
			[ $# -ge 2 ] || die "--tag requires a value"
			update_mode=tag
			update_value=$2
			selected=1
			shift 2
			;;
		--target-head | --remote)
			[ "$selected" -eq 0 ] || die "update selectors are mutually exclusive"
			update_mode=target_head
			selected=1
			shift
			;;
		--branch | --set-branch)
			[ $# -ge 2 ] || die "$1 requires a value"
			update_target=$2
			target_changed=1
			shift 2
			;;
		--no-fetch)
			fetch=0
			shift
			;;
		*) die "unknown update option: $1" ;;
		esac
	done
	require_value "$update_target" "cannot update $path without a target branch"
	if [ "$update_mode" = tag ] && [ "$target_changed" -eq 1 ]; then
		die "--branch cannot be combined with --tag because tag-pinned subprojects do not record target_branch"
	fi

	update_tag=
	case "$update_mode" in
	revision)
		[ "$fetch" -eq 1 ] && fetch_quiet "$path"
		revision=$(resolve_commit "$path" "$update_value" "cannot update $path with --revision")
		git -C "$path" checkout "$revision" || die "failed to check out revision $revision in $path"
		manifest_write_subproject "$path" "$repo" tracked "$update_target" "$revision"
		;;
	tag)
		[ "$fetch" -eq 1 ] && fetch_quiet "$path"
		update_tag=$update_value
		revision=$(resolve_commit "$path" "$update_tag" "cannot update $path with --tag")
		git -C "$path" checkout --detach "$revision" || die "failed to check out tag $update_tag in $path"
		manifest_write_subproject "$path" "$repo" finalized "$revision" "$update_tag"
		;;
	target_head)
		revision=$(resolve_target_ref "$path" "$update_target" "$fetch")
		git -C "$path" checkout "$revision" || die "failed to check out target revision $revision in $path"
		manifest_write_subproject "$path" "$repo" tracked "$update_target" "$revision"
		;;
	esac
	printf 'Updated %s to %.12s.\n' "$path" "$revision"
}

# Resolve a subproject target branch to a commit for --use-target-head finalization.

# Conservatively infer the finalized commit from exactly one ticket-key match.
auto_finalize_revision() {
	path=$1
	target=$2
	ticket=$(manifest_get project id || true)
	[ -n "$ticket" ] || ticket=$(ticket_from_branch "$(subproject_key "$path" pending_branch || true)")
	[ -n "$ticket" ] || die "auto-finalize needs a project id; use --revision, --tag, or --use-target-head"
	base=$(subproject_key "$path" base_revision || true)
	[ "$GIT_NEST_DRY_RUN" -eq 1 ] || fetch_quiet "$path"
	git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1 ||
		die "auto-finalize cannot find origin/$target for $path; fetch the subproject or use --revision/--tag"
	range=
	if [ -n "$base" ] && git -C "$path" cat-file -e "$base^{commit}" 2>/dev/null; then
		range="$base..origin/$target"
	else
		range="origin/$target"
	fi
	ticket_re=$(regex_escape "$ticket")
	matches=$(git -C "$path" log --format='%H %s' "$range" 2>/dev/null | grep -E "(^|[^A-Za-z0-9])$ticket_re([^0-9]|$)" || true)
	count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
	[ "$count" = "1" ] || die "auto-finalize found $count candidates for $ticket; use an explicit selector"
	revision=$(printf '%s\n' "$matches" | awk '{print $1}')
	require_value "$revision" "auto-finalize matched $ticket but produced an empty revision for $path; use --revision"
	resolve_commit "$path" "$revision" "cannot auto-finalize $path"
}

# Convert a subproject from pending to finalized state using an explicit or auto selector.
cmd_finalize() {
	[ $# -ge 1 ] || die "usage: git-nest finalize <subproject> [--dry-run] [--cleanup] [--revision <sha> | --tag <tag> | --use-target-head]"
	reject_backslash_path "$1"
	path=$(normalize_path "$1")
	shift

	mode=auto
	value=
	cleanup=0
	dry_run=0

	# Selectors are mutually exclusive so the manifest gets one clear source of
	# truth: explicit revision, explicit tag, target head, or conservative auto.
	while [ $# -gt 0 ]; do
		case "$1" in
		--dry-run)
			dry_run=1
			GIT_NEST_DRY_RUN=1
			shift
			;;
		--cleanup)
			cleanup=1
			shift
			;;
		--revision)
			[ "$mode" = auto ] || die "finalize selectors are mutually exclusive"
			[ $# -ge 2 ] || die "--revision requires a value"
			mode=revision
			value=$2
			shift 2
			;;
		--tag)
			[ "$mode" = auto ] || die "finalize selectors are mutually exclusive"
			[ $# -ge 2 ] || die "--tag requires a value"
			mode=tag
			value=$2
			shift 2
			;;
		--use-target-head)
			[ "$mode" = auto ] || die "finalize selectors are mutually exclusive"
			mode=target_head
			shift
			;;
		*) die "unknown finalize option: $1" ;;
		esac
	done

	[ "$dry_run" -eq 1 ] || acquire_manifest_lock
	ensure_manifest
	validate_manifest_schema
	assert_path_not_inside_nested_project "$path"
	[ -d "$path/.git" ] || die "$path is not a checked-out subproject"
	repo=$(subproject_repo "$path")
	[ -n "$repo" ] || die "$path is not in $MANIFEST_FILE"
	target=$(subproject_key "$path" target_branch || true)
	[ -n "$target" ] || target=main

	tag=
	# Every path resolves to a concrete commit before the manifest is touched.
	case "$mode" in
	revision)
		revision=$(resolve_commit "$path" "$value" "cannot finalize $path with --revision")
		;;
	tag)
		tag=$value
		revision=$(resolve_commit "$path" "$value" "cannot finalize $path with --tag")
		;;
	target_head)
		if [ "$dry_run" -eq 1 ]; then
			remote_tmp=$(tmp_for "$MANIFEST_FILE.finalize_target")
			remote_revision=$(remote_branch_commit "$repo" "$target" "$remote_tmp" || true)
			rm -f "$remote_tmp"
			if [ -n "$remote_revision" ]; then
				revision=$remote_revision
			else
				revision=$(resolve_target_ref "$path" "$target" 0)
			fi
		else
			revision=$(resolve_target_ref "$path" "$target")
		fi
		;;
	auto)
		if [ "$dry_run" -eq 1 ]; then
			if git -C "$path" rev-parse --verify "origin/$target^{commit}" >/dev/null 2>&1; then
				revision=$(auto_finalize_revision "$path" "$target")
			else
				revision=unknown
				printf '[dry-run] %s auto-finalize revision: unknown; real run would fetch first if needed\n' "$path"
			fi
		else
			revision=$(auto_finalize_revision "$path" "$target")
		fi
		;;
	esac
	require_value "$revision" "finalize produced an empty revision for $path; use --revision <sha>"

	old_pending=$(subproject_key "$path" pending_branch || true)
	if [ "$dry_run" -eq 1 ]; then
		old_revision=$(subproject_key "$path" revision || true)
		old_tag=$(subproject_key "$path" tag || true)
		printf '[dry-run] %s revision: %s -> %s\n' "$path" "${old_revision:-<unset>}" "$revision"
		printf '[dry-run] %s tag: %s -> %s\n' "$path" "${old_tag:-<unset>}" "${tag:-<unset>}"
		if [ "$cleanup" -eq 1 ] && [ -n "$old_pending" ]; then
			printf '[dry-run] would delete local branch %s in %s\n' "$old_pending" "$path"
		fi
		return 0
	fi
	manifest_write_subproject "$path" "$repo" finalized "$revision" "$tag" "$old_pending"

	# Cleanup is local-only: remote review branches and untracked files are not
	# deleted by finalize.
	if [ "$cleanup" -eq 1 ] && [ -n "$old_pending" ]; then
		cleanup_branch_for_subproject "$path" "$old_pending"
	fi
	printf 'Finalized %s at %.12s.\n' "$path" "$revision"
}

# Clone/fetch subprojects and restore their recorded manifest state.
restore_current() {
	prune=${1:-0}
	force=${2:-0}
	dry_run=${3:-0}
	ensure_manifest
	subprojects_tmp=$(tmp_for "$MANIFEST_FILE.restore")
	failures_tmp=$(tmp_for "$MANIFEST_FILE.restore_failures")
	manifest_subprojects >"$subprojects_tmp"
	: >"$failures_tmp"
	rc=0

	if [ "$dry_run" -eq 1 ]; then
		if [ "$prune" -eq 1 ]; then
			printf '[dry-run] would reconcile stale subprojects with prune enabled\n'
		else
			printf '[dry-run] would inspect stale subprojects for reconciliation\n'
		fi
	else
		reconcile_stale_subprojects "$prune"
	fi

	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if (
			repo=$(subproject_repo "$path")
			[ -n "$repo" ] || die "missing repo for $path"
			created=0
			clone_mode=$(effective_clone_mode "$path")
			tag=$(subproject_key "$path" tag || true)
			revision=$(subproject_key "$path" revision || true)
			target=$(subproject_key "$path" target_branch || true)
			[ -n "$target" ] || target=main
			if [ "$dry_run" -eq 1 ]; then
				if [ ! -d "$path/.git" ]; then
					printf '[dry-run] would clone %s into %s using clone=%s\n' "$repo" "$path" "$clone_mode"
				else
					printf '[dry-run] would fetch %s before restore\n' "$path"
				fi
				if [ -n "$tag" ]; then
					remote_tag=unknown
					if [ -n "$revision" ]; then
						tag_tmp=$(tmp_for "$MANIFEST_FILE.sync_tag")
						remote_tag=$(remote_tag_commit "$repo" "$tag" "$tag_tmp" || printf 'unknown')
						rm -f "$tag_tmp"
						if [ "$remote_tag" != unknown ] && [ "$remote_tag" != "$revision" ] && [ "$force" -eq 0 ]; then
							printf 'Error: tag/revision mismatch for %s\n' "$path" >&2
							exit "$EXIT_ISSUES"
						fi
					fi
					printf '[dry-run] would check out tag %s in %s (remote=%s)\n' "$tag" "$path" "$remote_tag"
				elif [ -n "$revision" ]; then
					printf '[dry-run] would check out revision %s in %s\n' "$revision" "$path"
				elif [ ! -d "$path/.git" ] && [ "$clone_mode" = partial ]; then
					printf '[dry-run] would check out target branch %s in %s after partial clone\n' "$target" "$path"
				else
					printf '[dry-run] would leave checkout state unchanged for %s\n' "$path"
				fi
				exit 0
			fi
			if [ ! -d "$path/.git" ]; then
				sp_depth=${restore_depth:-$(subproject_key "$path" depth || true)}
				clone_subproject "$repo" "$path" "$clone_mode" 1 "$sp_depth"
				created=1
			fi
			if [ "$created" -eq 1 ]; then
				install_hooks_in_repo_if_project_managed "$path"
			fi
			fetch_quiet "$path"
			if [ -n "$tag" ]; then
				if [ -n "$revision" ]; then
					tag_tmp=$(tmp_for "$MANIFEST_FILE.sync_tag")
					remote_tag=$(remote_tag_commit "$repo" "$tag" "$tag_tmp" || true)
					rm -f "$tag_tmp"
					if [ -n "$remote_tag" ] && [ "$remote_tag" != "$revision" ]; then
						if [ "$force" -eq 1 ]; then
							warn "tag $tag for $path moved from $revision to $remote_tag; --force is proceeding"
						else
							printf 'Error: tag/revision mismatch for %s\n' "$path" >&2
							printf '  tag: %s\n' "$tag" >&2
							printf '  recorded revision: %s\n' "$revision" >&2
							printf '  current remote SHA: %s\n' "$remote_tag" >&2
							printf '  recovery: investigate the moved tag, then run git-nest update %s --tag %s to re-pin\n' "$path" "$tag" >&2
							exit "$EXIT_ISSUES"
						fi
					fi
				fi
				resolve_commit "$path" "$tag" "cannot restore $path tag $tag" >/dev/null
				git -C "$path" checkout "$tag" || die "failed to check out tag $tag in $path"
			elif [ -n "$revision" ]; then
				revision=$(resolve_commit "$path" "$revision" "cannot restore $path revision")
				git -C "$path" checkout "$revision" || die "failed to check out revision $revision in $path"
			elif [ "$created" -eq 1 ] && [ "$clone_mode" = partial ]; then
				checkout_target_branch "$path" "$target"
			fi
			printf 'Restored %s.\n' "$path"
		); then
			:
		else
			rc=1
			printf '%s\n' "$path" >>"$failures_tmp"
		fi
	done <"$subprojects_tmp"

	rm -f "$subprojects_tmp"
	if [ "$rc" -ne 0 ]; then
		printf 'Error: restore failed for one or more subprojects:\n' >&2
		while IFS= read -r path; do
			[ -n "$path" ] && printf '  %s\n' "$path" >&2
		done <"$failures_tmp"
		printf 'Recovery: review the error for each listed subproject, fix the manifest, remote access, or local checkout, then rerun git-nest restore. Run git-nest verify for a read-only consistency report.\n' >&2
		rm -f "$failures_tmp"
		return 1
	fi
	rm -f "$failures_tmp"
	[ "$dry_run" -eq 1 ] || write_materialized_state
}

# Recursively restore the current project and nested project roots.
restore_recursive() {
	label=$1
	visited=$2
	prune=${3:-0}
	force=${4:-0}
	dry_run=${5:-0}
	root_abs=$(abs_path_for .)
	if grep -F -x "$root_abs" "$visited" >/dev/null 2>&1; then
		return 0
	fi
	printf '%s\n' "$root_abs" >>"$visited"
	printf 'Restoring project: %s\n' "$label"
	restore_current "$prune" "$force" "$dry_run" || return 1

	subprojects_tmp=$(tmp_for "$MANIFEST_FILE.restore_recursive")
	manifest_subprojects >"$subprojects_tmp"
	rc=0
	while IFS= read -r path; do
		[ -n "$path" ] || continue
		if [ -d "$path/.git" ] && [ -f "$path/$MANIFEST_FILE" ]; then
			child_label=$(join_project_label "$label" "$path")
			(
				cd "$path" || exit 1
				restore_recursive "$child_label" "$visited" "$prune" "$force" "$dry_run"
			) || rc=1
		fi
	done <"$subprojects_tmp"
	rm -f "$subprojects_tmp"
	return "$rc"
}

# Restore project state, optionally including nested projects.
cmd_restore() {
	recursive=0
	prune=0
	force=0
	dry_run=0
	restore_depth=
	while [ $# -gt 0 ]; do
		case "$1" in
		--recursive)
			recursive=1
			shift
			;;
		--prune)
			prune=1
			shift
			;;
		--force)
			force=1
			shift
			;;
		--depth)
			[ $# -ge 2 ] || usage_error "--depth requires a positive integer"
			restore_depth=$2
			validate_positive_integer "$restore_depth" "--depth"
			shift 2
			;;
		--dry-run)
			dry_run=1
			GIT_NEST_DRY_RUN=1
			shift
			;;
		*) usage_error "unknown restore option: $1" ;;
		esac
	done
	if [ "$recursive" -eq 1 ]; then
		visited=$(mktemp)
		: >"$visited"
		restore_recursive "." "$visited" "$prune" "$force" "$dry_run"
		rc=$?
		rm -f "$visited"
		return "$rc"
	fi
	restore_current "$prune" "$force" "$dry_run"
	notice_nested_projects
}

# Pull upstream changes into clean subprojects, then snapshot the result.
# Operates on the current nest; use --recursive for nested nests.
pull_current() {
	sure=$1
	no_fetch=$2
	dry_run=$3
	json=${4:-0}
	pretty=${5:-0}
	ensure_manifest
	[ "$dry_run" -eq 1 ] || acquire_manifest_lock

	pull_subprojects_tmp=$(tmp_for "$MANIFEST_FILE.pull")
	manifest_subprojects >"$pull_subprojects_tmp"

	pull_pulled_list=$(mktemp)
	pull_dirty_list=$(mktemp)
	pull_detached_list=$(mktemp)
	pull_noupstream_list=$(mktemp)
	pull_diverged_list=$(mktemp)
	pull_failed_list=$(mktemp)
	pull_rows=$(mktemp)
	: >"$pull_pulled_list"
	: >"$pull_dirty_list"
	: >"$pull_detached_list"
	: >"$pull_noupstream_list"
	: >"$pull_diverged_list"
	: >"$pull_failed_list"
	pulled=0
	skipped_dirty=0
	skipped_detached=0
	skipped_no_upstream=0
	diverged=0
	failed=0

	while IFS= read -r pull_path; do
		[ -n "$pull_path" ] || continue
		[ -d "$pull_path/.git" ] || continue

		# Skip dirty subprojects
		if repo_has_dirty "$pull_path"; then
			printf '%s\n' "$pull_path" >>"$pull_dirty_list"
			skipped_dirty=$((skipped_dirty + 1))
			printf 'Y\t%s\tdirty\t-\t-\t-\tcommit or stash changes first\n' "$pull_path" >>"$pull_rows"
			continue
		fi

		# Check for detached HEAD
		pull_branch=$(git -C "$pull_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
		if [ -z "$pull_branch" ]; then
			printf '%s\n' "$pull_path" >>"$pull_detached_list"
			skipped_detached=$((skipped_detached + 1))
			pull_path_q=$(shell_quote "$pull_path")
			printf 'H\t%s\tdetached\t-\t-\t-\trun git -C %s checkout <branch>\n' "$pull_path" "$pull_path_q" >>"$pull_rows"
			continue
		fi

		# Check for upstream tracking
		if ! git -C "$pull_path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
			printf '%s\n' "$pull_path" >>"$pull_noupstream_list"
			skipped_no_upstream=$((skipped_no_upstream + 1))
			pull_path_q=$(shell_quote "$pull_path")
			printf 'N\t%s\tno-upstream\t%s\t-\t-\trun git -C %s branch --set-upstream-to=origin/%s\n' "$pull_path" "$pull_branch" "$pull_path_q" "$pull_branch" >>"$pull_rows"
			continue
		fi

		# Dry-run: show planned action
		if [ "$dry_run" -eq 1 ]; then
			pull_current_sha=$(git -C "$pull_path" rev-parse HEAD 2>/dev/null || true)
			pull_repo=$(subproject_repo "$pull_path" || true)
			pull_target=$(subproject_key "$pull_path" target_branch || true)
			[ -n "$pull_target" ] || pull_target=$(default_target_branch "$pull_path")
			pull_ls_remote=$(git ls-remote "$pull_repo" "refs/heads/$pull_target" 2>/dev/null | awk '{print $1}' || true)
			if [ -n "$pull_ls_remote" ] && [ "$pull_ls_remote" != "$pull_current_sha" ]; then
				[ "$json" -eq 1 ] || printf '[dry-run] would pull %s: %.12s -> %.12s\n' "$pull_path" "$pull_current_sha" "$pull_ls_remote"
				printf 'P\t%s\twould-pull\t%s\t%s\t%s\twould pull\n' "$pull_path" "$pull_target" "$pull_current_sha" "$pull_ls_remote" >>"$pull_rows"
			else
				[ "$json" -eq 1 ] || printf '[dry-run] %s: already up to date at %.12s\n' "$pull_path" "$pull_current_sha"
				printf 'A\t%s\tup-to-date\t%s\t%s\t%s\talready up to date\n' "$pull_path" "$pull_target" "$pull_current_sha" "$pull_current_sha" >>"$pull_rows"
			fi
			continue
		fi

		# Fetch unless --no-fetch
		if [ "$no_fetch" -eq 0 ]; then
			if ! git -C "$pull_path" fetch origin >/dev/null 2>&1; then
				printf '%s\n' "$pull_path" >>"$pull_failed_list"
				failed=$((failed + 1))
				printf 'F\t%s\tfailed\t-\t-\t-\tfetch failed; check network/remote access, then retry\n' "$pull_path" >>"$pull_rows"
				continue
			fi
		fi

		# Resolve upstream commit; if HEAD is already its ancestor, we are up to date
		pull_upstream_commit=$(git -C "$pull_path" rev-parse '@{upstream}' 2>/dev/null || true)
		if [ -z "$pull_upstream_commit" ]; then
			printf '%s\n' "$pull_path" >>"$pull_failed_list"
			failed=$((failed + 1))
			printf 'F\t%s\tfailed\t-\t-\t-\tcould not resolve upstream commit\n' "$pull_path" >>"$pull_rows"
			continue
		fi

		pull_head_commit=$(git -C "$pull_path" rev-parse HEAD 2>/dev/null || true)
		if [ "$pull_head_commit" = "$pull_upstream_commit" ]; then
			[ "$json" -eq 1 ] || printf '%s: already up to date.\n' "$pull_path"
			printf 'A\t%s\tup-to-date\t%s\t%s\t%s\talready up to date\n' "$pull_path" "$pull_branch" "$pull_head_commit" "$pull_upstream_commit" >>"$pull_rows"
		elif git -C "$pull_path" merge-base --is-ancestor "$pull_head_commit" "$pull_upstream_commit" 2>/dev/null; then
			# Fast-forward possible
			git -C "$pull_path" merge --ff-only '@{upstream}' >/dev/null 2>&1 || {
				printf '%s\n' "$pull_path" >>"$pull_failed_list"
				failed=$((failed + 1))
				printf 'F\t%s\tfailed\t-\t-\t-\tfast-forward merge failed\n' "$pull_path" >>"$pull_rows"
				continue
			}
			pull_new_head=$(git -C "$pull_path" rev-parse HEAD)
			[ "$json" -eq 1 ] || printf 'Pulled %s to %.12s.\n' "$pull_path" "$pull_new_head"
			printf '%s\n' "$pull_path" >>"$pull_pulled_list"
			pulled=$((pulled + 1))
			printf 'P\t%s\tpulled\t%s\t%s\t%s\tpulled\n' "$pull_path" "$pull_branch" "$pull_head_commit" "$pull_new_head" >>"$pull_rows"
		else
			printf '%s\n' "$pull_path" >>"$pull_diverged_list"
			diverged=$((diverged + 1))
			pull_path_q=$(shell_quote "$pull_path")
			printf 'V\t%s\tdiverged\t%s\t%s\t%s\trun git -C %s merge origin/<branch> or git -C %s rebase origin/<branch>\n' "$pull_path" "$pull_branch" "$pull_head_commit" "$pull_upstream_commit" "$pull_path_q" "$pull_path_q" >>"$pull_rows"
		fi
	done <"$pull_subprojects_tmp"
	rm -f "$pull_subprojects_tmp"

	# Snapshot successfully pulled subprojects
	while IFS= read -r pull_path; do
		[ -n "$pull_path" ] || continue
		snapshot_one_subproject "$pull_path" 1 0 0 0 || true
	done <"$pull_pulled_list"
	rm -f "$pull_pulled_list"

	# Pull the nest root if --sure
	if [ "$sure" -eq 1 ]; then
		if [ "$dry_run" -eq 1 ]; then
			if remote_exists .; then
				[ "$json" -eq 1 ] || printf '[dry-run] would pull nest root\n'
				printf 'P\t.\twould-pull\t-\t-\t-\twould pull nest root\n' >>"$pull_rows"
			else
				[ "$json" -eq 1 ] || printf '[dry-run] nest root has no remote; would skip root pull\n'
				printf 'F\t.\tfailed\t-\t-\t-\tnest root has no remote\n' >>"$pull_rows"
			fi
		else
			if remote_exists .; then
				root_ok=1
				if [ "$no_fetch" -eq 0 ]; then
					git fetch origin >/dev/null 2>&1 || {
						warn "pull failed in nest root: network error fetching from origin"
						root_ok=0
					}
				fi
				if [ "$root_ok" -eq 1 ]; then
					if git merge --ff-only '@{upstream}' >/dev/null 2>&1; then
						printf 'P\t.\tpulled\t-\t-\t-\tpulled nest root\n' >>"$pull_rows"
					else
						warn "nest root: cannot fast-forward; diverged or no upstream"
						printf 'V\t.\tdiverged\t-\t-\t-\tnest root cannot fast-forward; diverged or no upstream\n' >>"$pull_rows"
					fi
				else
					printf 'F\t.\tfailed\t-\t-\t-\tnest root fetch failed\n' >>"$pull_rows"
				fi
			fi
		fi
	fi

	if [ "$json" -eq 1 ]; then
		pull_empty=$(mktemp)
		[ "$dry_run" -eq 0 ] || GIT_NEST_JSON_DRY_RUN=1
		emit_json_result pull 0 1 "$pull_rows" "$pull_empty" "$pull_empty" "$pretty"
		rm -f "$pull_empty"
	else
		printf '\n=== Pull Summary ===\n'
		printf '  Pulled:        %s\n' "$pulled"
		if [ "$skipped_dirty" -gt 0 ]; then
			printf '  Skipped (dirty):\n'
			while IFS= read -r p; do printf '    %s (commit or stash changes first)\n' "$p"; done <"$pull_dirty_list"
		fi
		if [ "$skipped_detached" -gt 0 ]; then
			printf '  Skipped (detached HEAD):\n'
			while IFS= read -r p; do
				pb=$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
				pq=$(shell_quote "$p")
				printf '    %s (run: git -C %s checkout <branch>)\n' "$p" "$pq"
			done <"$pull_detached_list"
		fi
		if [ "$skipped_no_upstream" -gt 0 ]; then
			printf '  Skipped (no upstream tracking):\n'
			while IFS= read -r p; do
				pb=$(git -C "$p" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "HEAD")
				pq=$(shell_quote "$p")
				printf '    %s (run: git -C %s branch --set-upstream-to=origin/%s)\n' "$p" "$pq" "$pb"
			done <"$pull_noupstream_list"
		fi
		if [ "$diverged" -gt 0 ]; then
			printf '  Diverged (not fast-forward):\n'
			while IFS= read -r p; do
				pq=$(shell_quote "$p")
				printf '    %s (run: git -C %s merge origin/<branch> or git -C %s rebase origin/<branch>)\n' "$p" "$pq" "$pq"
			done <"$pull_diverged_list"
		fi
		if [ "$failed" -gt 0 ]; then
			printf '  Failed:\n'
			while IFS= read -r p; do
				printf '    %s (check network/remote access, then retry)\n' "$p"
			done <"$pull_failed_list"
		fi
	fi
	rm -f "$pull_dirty_list" "$pull_detached_list" "$pull_noupstream_list" "$pull_diverged_list" "$pull_failed_list" "$pull_rows"
}

# Recursively pull the current project and nested project roots.
pull_recursive() {
	pull_label=$1
	pull_visited=$2
	pull_sure=$3
	pull_no_fetch=$4
	pull_dry_run=$5
	pull_json=${6:-0}
	pull_pretty=${7:-0}
	pull_root_abs=$(abs_path_for .)
	if grep -F -x "$pull_root_abs" "$pull_visited" >/dev/null 2>&1; then
		return 0
	fi
	printf '%s\n' "$pull_root_abs" >>"$pull_visited"
	[ "$pull_json" -eq 1 ] || printf 'Pulling project: %s\n' "$pull_label"
	pull_current "$pull_sure" "$pull_no_fetch" "$pull_dry_run" "$pull_json" "$pull_pretty" || return 1
	cleanup_manifest_lock

	pull_sub_tmp=$(tmp_for "$MANIFEST_FILE.pull_recursive")
	manifest_subprojects >"$pull_sub_tmp"
	pull_rc=0
	while IFS= read -r pull_path; do
		[ -n "$pull_path" ] || continue
		if [ -d "$pull_path/.git" ] && [ -f "$pull_path/$MANIFEST_FILE" ]; then
			pull_child=$(join_project_label "$pull_label" "$pull_path")
			(
				cd "$pull_path" || exit 1
				pull_recursive "$pull_child" "$pull_visited" "$pull_sure" "$pull_no_fetch" "$pull_dry_run" "$pull_json" "$pull_pretty"
			) || pull_rc=1
		fi
	done <"$pull_sub_tmp"
	rm -f "$pull_sub_tmp"
	return "$pull_rc"
}

cmd_pull() {
	recursive=0
	sure=0
	no_fetch=0
	dry_run=0
	json=0
	json_pretty=0

	while [ $# -gt 0 ]; do
		case "$1" in
		--recursive)
			recursive=1
			shift
			;;
		--sure)
			sure=1
			shift
			;;
		--no-fetch)
			no_fetch=1
			shift
			;;
		--dry-run)
			dry_run=1
			GIT_NEST_DRY_RUN=1
			shift
			;;
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			json_pretty=1
			shift
			;;
		*) usage_error "unknown pull option: $1" ;;
		esac
	done

	if [ "$recursive" -eq 1 ]; then
		pull_visited=$(mktemp)
		: >"$pull_visited"
		pull_recursive "." "$pull_visited" "$sure" "$no_fetch" "$dry_run" "$json" "$json_pretty"
		pull_rc=$?
		rm -f "$pull_visited"
		return "$pull_rc"
	fi

	pull_current "$sure" "$no_fetch" "$dry_run" "$json" "$json_pretty"
	[ "$json" -eq 1 ] || notice_nested_projects
}

# Run git gc in the nest root and every checked-out subproject.
cmd_gc() {
	aggressive=0
	dry_run=0
	json=0
	json_pretty=0
	while [ $# -gt 0 ]; do
		case "$1" in
		--aggressive)
			aggressive=1
			shift
			;;
		--dry-run)
			dry_run=1
			shift
			;;
		--json)
			json=1
			shift
			;;
		--json-pretty)
			json=1
			json_pretty=1
			shift
			;;
		*) usage_error "unknown gc option: $1" ;;
		esac
	done

	gc_opts=
	[ "$aggressive" -eq 1 ] && gc_opts="--aggressive"

	gc_rows=$(mktemp)
	gc_errors=$(mktemp)
	gc_warnings=$(mktemp)
	: >"$gc_errors"
	: >"$gc_warnings"

	gc_run() {
		gc_repo=$1
		gc_label=${2:-$1}
		if [ "$dry_run" -eq 1 ]; then
			[ "$json" -eq 1 ] || printf '[dry-run] would run git gc %s in %s\n' "$gc_opts" "$gc_label"
			printf 'W\t%s\tgc\t-\t-\t-\twould run git gc %s\n' "$gc_label" "$gc_opts" >>"$gc_rows"
		else
			if git -C "$gc_repo" gc $gc_opts >/dev/null 2>&1; then
				printf 'P\t%s\tgc\t-\t-\t-\trun git gc\n' "$gc_label" >>"$gc_rows"
			else
				printf 'F\t%s\tgc\t-\t-\t-\tgit gc failed\n' "$gc_label" >>"$gc_warnings"
			fi
		fi
	}

	gc_run "." "."

	manifest_subprojects | while IFS= read -r gc_path; do
		[ -n "$gc_path" ] || continue
		[ -d "$gc_path/.git" ] || continue
		gc_run "$gc_path" "$gc_path"
	done

	if [ "$json" -eq 1 ]; then
		emit_json_result gc 0 1 "$gc_rows" "$gc_errors" "$gc_warnings" "$json_pretty"
	else
		label="Nest root"
		while IFS='	' read -r gc_code gc_path gc_state gc_target gc_current gc_expected gc_detail; do
			[ -n "$gc_code" ] || continue
			case "$gc_code" in
			P) printf 'Ran git gc in %s.\n' "$gc_path" ;;
			W) printf '[dry-run] %s: would run git gc\n' "$gc_path" ;;
			F) printf 'Warning: git gc failed in %s.\n' "$gc_path" ;;
			esac
		done <"$gc_rows"
	fi

	rm -f "$gc_rows" "$gc_errors" "$gc_warnings"
}

GIT_NEST_command_names() {
	printf '%s\n' "init tidy add remove rm move mv clone status outdated verify diff log snapshot restore pull gc freeze hooks-install hooks-uninstall branch-mark branch-unmark branch-list branch-cleanup foreach foreach-modified foreach-clean config update doctor survey list tree completion export absorb absorb-all inline detach version help"
}

# Internal completion data endpoint used by generated shell completion scripts.
cmd_internal_complete() {
	# Legacy interface: __complete commands | __complete subprojects
	if [ $# -eq 1 ]; then
		case "$1" in
		commands) GIT_NEST_command_names ;;
		subprojects) _GIT_NEST_emit_subprojects ;;
		*) usage_error "unknown completion data: $1" ;;
		esac
		return
	fi
	# New interface: __complete CURSOR_INDEX [--] ARG...
	[ $# -ge 2 ] || return 1
	_GIT_NEST_complete "$@"
}

# --- TSV protocol helpers ---

_GIT_NEST_emit_commands() {
	for _c in $(GIT_NEST_command_names); do
		printf 'C\t%s\t\tcommand\n' "$_c"
	done
}

_GIT_NEST_emit_option() {
	printf 'C\t%s\t%s\toption\n' "$1" "${2:-}"
}

_GIT_NEST_emit_value() {
	printf 'C\t%s\t%s\tvalue\n' "$1" "${2:-}"
}

_GIT_NEST_emit_subprojects() {
	_root=$(find_project_root 2>/dev/null) || return 0
	(cd "$_root" && manifest_subprojects) 2>/dev/null | while IFS= read -r _sp; do
		printf 'C\t%s\t\tsubproject\n' "$_sp"
	done
}

_GIT_NEST_emit_directive() {
	printf 'D\t%s\n' "$1"
}

# Return 0 if argument is a flag that takes a value.
_GIT_NEST_opt_takes_arg() {
	case "$1" in
	--output|--format|--clone-mode|--max-depth|--exclude|--include|--timeout|--since|--until|--max-count|--subproject|--branch|--url|--remote|--target-head|--revision|--tag|--message|--only|--depth) return 0 ;;
	esac
	return 1
}

# Complete a value for the given flag.
_GIT_NEST_complete_opt_value() {
	case "$1" in
	--format)     _GIT_NEST_emit_value tar.gz "gzip tar archive"; _GIT_NEST_emit_value zip "zip archive"; _GIT_NEST_emit_value dir "directory"; _GIT_NEST_emit_directive no-file ;;
	--clone-mode) _GIT_NEST_emit_value full  "full clone"; _GIT_NEST_emit_value partial "partial clone"; _GIT_NEST_emit_value shallow "shallow clone"; _GIT_NEST_emit_directive no-file ;;
	--max-depth|--depth) _GIT_NEST_emit_directive no-file ;;
	--exclude)    _GIT_NEST_emit_directive no-file ;;
	--include|--output) _GIT_NEST_emit_directive file ;;
	--timeout)    _GIT_NEST_emit_directive no-file ;;
	--since|--until|--branch|--target-head|--revision|--tag) _GIT_NEST_emit_directive no-file ;;
	--url|--remote) _GIT_NEST_emit_directive no-file ;;
	--message|--only) _GIT_NEST_emit_directive no-file ;;
	--subproject) _GIT_NEST_emit_subprojects; _GIT_NEST_emit_directive no-file ;;
	esac
}

# Main dispatch: parse cursor_index and args, delegate to case table.
_GIT_NEST_complete() {
	_cursor_index="$1"
	shift
	[ "$1" = "--" ] && shift

	# Position 0: completing command name
	if [ "$_cursor_index" -eq 0 ]; then
		_GIT_NEST_emit_commands
		_GIT_NEST_emit_directive no-file
		return
	fi

	_cmd="$1"
	_cmd_ai=$((_cursor_index - 1))   # 0-based index within this command's args
	_prev=""

	# Determine previous word (the word just before the one being completed)
	eval "_prev=\"\${$_cursor_index}\"" 2>/dev/null || true

	# If previous word is a known value-taking flag, complete its value
	if _GIT_NEST_opt_takes_arg "$_prev"; then
		_GIT_NEST_complete_opt_value "$_prev"
		return
	fi

	_GIT_NEST_complete_for "$_cmd" "$_cmd_ai"
}

# Per-command completion table -- single source of truth for all shells.
_GIT_NEST_complete_for() {
	_ai="$2"
	case "$1" in
	init)
		_GIT_NEST_emit_option --rc "set up .gitnest-rc"
		_GIT_NEST_emit_option --sure "confirm initialization"
		_GIT_NEST_emit_directive no-file
		;;
	tidy)
		_GIT_NEST_emit_option --rc "set up .gitnest-rc"
		_GIT_NEST_emit_directive no-file
		;;
	completion)
		for _s in bash zsh fish yash powershell; do
			_GIT_NEST_emit_value "$_s" "generate $_s completion script"
		done
		_GIT_NEST_emit_directive no-file
		;;
	help)
		_GIT_NEST_emit_commands
		_GIT_NEST_emit_directive no-file
		;;
	version)
		_GIT_NEST_emit_directive no-file
		;;
	status)
		_GIT_NEST_emit_option --recursive "include nested projects"
		_GIT_NEST_emit_option --porcelain "stable fixed-column records"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_option --exit-code "return nonzero for dirty or missing rows"
		_GIT_NEST_emit_directive no-file
		;;
	outdated)
		_GIT_NEST_emit_option --recursive "include nested projects"
		_GIT_NEST_emit_option --porcelain "stable fixed-column records"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_directive no-file
		;;
	verify)
		_GIT_NEST_emit_option --recursive "include nested projects"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_directive no-file
		;;
	diff)
		_GIT_NEST_emit_option --since "read manifest from ref"
		_GIT_NEST_emit_option --stat "include file statistics"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_directive no-file
		;;
	log)
		_GIT_NEST_emit_option --max-count "number of commits"
		_GIT_NEST_emit_option --since "start date"
		_GIT_NEST_emit_option --until "end date"
		_GIT_NEST_emit_option --subproject "filter by subproject"
		_GIT_NEST_emit_option --oneline "compact output"
		_GIT_NEST_emit_option --recursive "include nested projects"
		_GIT_NEST_emit_directive no-file
		;;
	restore)
		_GIT_NEST_emit_option --recursive "include nested projects"
		_GIT_NEST_emit_option --prune "remove reviewed stale paths"
		_GIT_NEST_emit_option --force "proceed past tag drift warnings"
		_GIT_NEST_emit_option --dry-run "show planned actions without writing"
		_GIT_NEST_emit_directive no-file
		;;
	pull)
		_GIT_NEST_emit_option --recursive "include nested nests"
		_GIT_NEST_emit_option --sure "also pull nest root"
		_GIT_NEST_emit_option --no-fetch "use local refs only"
		_GIT_NEST_emit_option --dry-run "show planned changes"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_directive no-file
		;;
	freeze)
		_GIT_NEST_emit_option --force "freeze dirty subprojects"
		_GIT_NEST_emit_option --only "limit paths"
		_GIT_NEST_emit_option --dry-run "show changes without writing"
		_GIT_NEST_emit_directive no-file
		;;
	gc)
		_GIT_NEST_emit_option --aggressive "pass --aggressive to git gc"
		_GIT_NEST_emit_option --dry-run "show planned actions"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_directive no-file
		;;
	doctor)
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_option --online "contact subproject remotes"
		_GIT_NEST_emit_option --offline "skip remote checks"
		_GIT_NEST_emit_option --timeout "remote timeout seconds"
		_GIT_NEST_emit_option --exit-code "return nonzero for warnings or errors"
		_GIT_NEST_emit_option --redact "strip credentials and home paths"
		_GIT_NEST_emit_directive no-file
		;;
	survey)
		_GIT_NEST_emit_option --max-depth "maximum scan depth"
		_GIT_NEST_emit_option --exclude "exclude directory name"
		_GIT_NEST_emit_option --include "narrow scan to path"
		_GIT_NEST_emit_option --porcelain "stable fixed-column records"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_directive no-file
		;;
	list)
		_GIT_NEST_emit_option --porcelain "stable fixed-column records"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_option --redact "strip credentials and home paths"
		_GIT_NEST_emit_directive no-file
		;;
	tree)
		_GIT_NEST_emit_option --all "also show unmanaged findings"
		_GIT_NEST_emit_option --recursive "descend into nested nests"
		_GIT_NEST_emit_option --porcelain "stable fixed-column records"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_directive no-file
		;;
	export)
		_GIT_NEST_emit_option --output "write archive or directory"
		_GIT_NEST_emit_option --format "archive format"
		_GIT_NEST_emit_option --include-git "keep .git directories"
		_GIT_NEST_emit_option --deterministic "normalize archive metadata"
		_GIT_NEST_emit_option --allow-dirty "allow dirty subprojects"
		_GIT_NEST_emit_directive no-file
		;;
	clone)
		_GIT_NEST_emit_option --branch "initial branch"
		_GIT_NEST_emit_option --no-restore "skip restore after clone"
		_GIT_NEST_emit_directive no-file
		;;
	add)
		_GIT_NEST_emit_option --force "bypass metadata conflicts"
		_GIT_NEST_emit_option --url "repository URL"
		_GIT_NEST_emit_option --remote "remote name"
		_GIT_NEST_emit_option --target-head "branch for tracking"
		_GIT_NEST_emit_option --revision "exact commit SHA"
		_GIT_NEST_emit_option --tag "tag name"
		_GIT_NEST_emit_option --branch "initial branch"
		_GIT_NEST_emit_option --no-fetch "use local refs only"
		_GIT_NEST_emit_option --dry-run "show planned changes"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_option --clone-mode "clone mode (full|partial|shallow)"
		_GIT_NEST_emit_directive no-file
		;;
	snapshot)
		if [ "$_ai" -eq 0 ]; then
			_GIT_NEST_emit_subprojects
			_GIT_NEST_emit_option --recursive "include nested projects"
			_GIT_NEST_emit_option --quiet "suppress dirty skip warnings"
			_GIT_NEST_emit_option --dry-run "show planned changes"
			_GIT_NEST_emit_option --check "check without writing"
			_GIT_NEST_emit_option --strict "fail on unreproducible state"
			_GIT_NEST_emit_option --no-fetch "use local refs"
		fi
		_GIT_NEST_emit_directive no-file
		;;
	absorb)
		if [ "$_ai" -eq 0 ]; then
			_GIT_NEST_emit_option --branch "initial branch for source"
			_GIT_NEST_emit_option --clone-mode "clone mode"
			_GIT_NEST_emit_option --preserve-history "preserve path history"
			_GIT_NEST_emit_option --push "push absorbed repository"
			_GIT_NEST_emit_option --message "commit message"
			_GIT_NEST_emit_option --force "bypass metadata conflicts"
			_GIT_NEST_emit_option --dry-run "show planned changes"
			_GIT_NEST_emit_option --json "print JSON"
			_GIT_NEST_emit_option --json-pretty "print formatted JSON"
			_GIT_NEST_emit_option --subrepo "absorb a git-subrepo path"
			_GIT_NEST_emit_option --subtree "absorb a git-subtree path"
		fi
		_GIT_NEST_emit_directive file
		;;
	absorb-all)
		_GIT_NEST_emit_option --sure "confirm creating or extending a nest"
		_GIT_NEST_emit_option --force-partial "skip rollback on failure"
		_GIT_NEST_emit_option --dry-run "show planned actions"
		_GIT_NEST_emit_option --max-depth "maximum scan depth"
		_GIT_NEST_emit_option --exclude "exclude directory name"
		_GIT_NEST_emit_option --include "narrow scan to path"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_directive no-file
		;;
	inline)
		if [ "$_ai" -eq 0 ]; then
			_GIT_NEST_emit_subprojects
			_GIT_NEST_emit_option --commit "commit staged outer changes"
			_GIT_NEST_emit_option --message "commit message"
			_GIT_NEST_emit_option --dry-run "show planned changes"
			_GIT_NEST_emit_option --json "print JSON"
			_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		fi
		_GIT_NEST_emit_directive no-file
		;;
	detach)
		if [ "$_ai" -eq 0 ]; then
			_GIT_NEST_emit_subprojects
			_GIT_NEST_emit_option --dry-run "show planned changes"
			_GIT_NEST_emit_option --json "print JSON"
			_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		fi
		_GIT_NEST_emit_directive no-file
		;;
	remove|rm)
		if [ "$_ai" -eq 0 ]; then
			_GIT_NEST_emit_subprojects
			_GIT_NEST_emit_option --force "bypass metadata conflicts"
			_GIT_NEST_emit_option --dry-run "show planned changes"
			_GIT_NEST_emit_option --json "print JSON"
			_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		fi
		_GIT_NEST_emit_directive no-file
		;;
	move|mv)
		if [ "$_ai" -eq 0 ]; then
			_GIT_NEST_emit_subprojects
			_GIT_NEST_emit_option --force "bypass metadata conflicts"
			_GIT_NEST_emit_option --dry-run "show planned changes"
			_GIT_NEST_emit_option --json "print JSON"
			_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		fi
		_GIT_NEST_emit_directive no-file
		;;
	update)
		if [ "$_ai" -eq 0 ]; then
			_GIT_NEST_emit_subprojects
			_GIT_NEST_emit_option --force "proceed past conflicts"
			_GIT_NEST_emit_option --dry-run "show planned changes"
			_GIT_NEST_emit_option --json "print JSON"
			_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		fi
		_GIT_NEST_emit_directive no-file
		;;
	config)
		case "$_ai" in
		0) for _v in get set list unset; do _GIT_NEST_emit_value "$_v" "config action"; done ;;
		1) _GIT_NEST_emit_subprojects ;;
		2) _GIT_NEST_emit_value "clone-mode" "configuration key" ;;
		3) _GIT_NEST_emit_value full "full clone"; _GIT_NEST_emit_value partial "partial clone"; _GIT_NEST_emit_value shallow "shallow clone" ;;
		esac
		_GIT_NEST_emit_directive no-file
		;;
	foreach)
		_GIT_NEST_emit_option --include-root-first "run on nest root before subprojects"
		_GIT_NEST_emit_option --include-root-last "run on nest root after subprojects"
		_GIT_NEST_emit_option --only-nested "limit to nested nests"
		_GIT_NEST_emit_option --no-nested "exclude nested nests"
		_GIT_NEST_emit_value "--" "end of options"
		_GIT_NEST_emit_directive no-file
		;;
	foreach-modified|foreach-clean)
		_GIT_NEST_emit_option --continue-on-error "keep iterating after failures"
		_GIT_NEST_emit_option --porcelain "stable fixed-column records"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_option --json-pretty "print formatted JSON"
		_GIT_NEST_emit_value "--" "end of options"
		_GIT_NEST_emit_directive no-file
		;;
	branch-mark)
		if [ "$_ai" -eq 0 ]; then
			_GIT_NEST_emit_value "<branch>" "branch name to mark"
		fi
		_GIT_NEST_emit_directive no-file
		;;
	branch-unmark)
		if [ "$_ai" -eq 0 ]; then
			_GIT_NEST_emit_value "<branch>" "branch name to unmark"
		fi
		_GIT_NEST_emit_directive no-file
		;;
	branch-list)
		_GIT_NEST_emit_option --verbose "include origin and timestamp"
		_GIT_NEST_emit_option --json "print JSON"
		_GIT_NEST_emit_directive no-file
		;;
	branch-cleanup)
		_GIT_NEST_emit_option --dry-run "show branches that would be removed"
		_GIT_NEST_emit_directive no-file
		;;
	hooks-install|hooks-uninstall)
		_GIT_NEST_emit_directive no-file
		;;
	__complete|__owning-manifest|__hook)
		_GIT_NEST_emit_directive no-file
		;;
	esac
}

# --- Shell adapter generators (thin translators) ---

completion_bash() {
	cat <<'GENEOF'
_git_nest_complete()
{
    local cur="${COMP_WORDS[COMP_CWORD]}" words=("${COMP_WORDS[@]:1}")
    COMPREPLY=()
    while IFS=$'\t' read -r _t _v _d _k; do
        [ "$_t" = "C" ] && [[ "$_v" == "$cur"* ]] && COMPREPLY+=("$_v")
    done < <(git-nest __complete $((COMP_CWORD - 1)) -- "${words[@]}" 2>/dev/null)
}
complete -F _git_nest_complete git-nest
GENEOF
}

completion_zsh() {
	cat <<'GENEOF'
#compdef git-nest
_git_nest()
{
    local -a candidates
    while IFS=$'\t' read -r _t _v _d _k; do
        [ "$_t" = "C" ] && candidates+=("$_v:$_d")
    done < <(git-nest __complete $((CURRENT - 2)) -- "${words[@]:2}" 2>/dev/null)
    _describe 'git-nest' candidates
}
_git_nest "$@"
GENEOF
}

completion_fish() {
	cat <<'GENEOF'
function __git_nest_complete
    set -l tokens (commandline -opc)
    if test "$tokens[1]" = git
        set tokens $tokens[2..-1]
        if test "$tokens[1]" = nest
            set tokens $tokens[2..-1]
        end
    else
        set tokens $tokens[2..-1]
    end
    set -l idx (math (count $tokens) - 1)
    test $idx -ge 0; or set idx 0
    git-nest __complete $idx -- $tokens 2>/dev/null | string match -r '^C\t' | string replace -r '^C\t([^\t]+).*' '$1'
end
complete -c git-nest -f -a "(__git_nest_complete)"
GENEOF
}

completion_yash() {
	cat <<'GENEOF'
# yash completion for git-nest -- place in your completion load path
completion//argument-git-nest() {
    git-nest __complete $((${#WORDS[*]} - 1)) -- "${WORDS[@]:2}" 2>/dev/null |
    awk -F '\t' '
    /^C\t/ { v=$2; d=$3; k=$4
        if (k == "option") print "complete -O -D \"" d "\" -- \"" v "\""
        else print "complete -D \"" d "\" -- \"" v "\""
    }
    /^D\tno-file/ { print "complete -N" }
    ' | sh
}
GENEOF
}

completion_powershell() {
	cat <<'GENEOF'
# git-nest PowerShell completion -- dot-source this file
Register-ArgumentCompleter -Native -CommandName git-nest -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $args = $commandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Value }
    $idx = if ($args) { $args.Count } else { 0 }
    $result = & git-nest __complete $idx -- @args 2>$null
    $result | ForEach-Object {
        if ($_ -match "^C\t(.+?)\t(.*?)\t(.+)$") {
            [System.Management.Automation.CompletionResult]::new(
                $matches[1], $matches[1],
                [System.Management.Automation.CompletionResultType]::ParameterValue,
                $matches[2]
            )
        }
    }
}
GENEOF
}

# Print shell completion scripts.
cmd_completion() {
	[ $# -eq 1 ] || usage_error "usage: git-nest completion <bash|zsh|fish|yash|powershell>"
	case "$1" in
	bash)       completion_bash ;;
	zsh)        completion_zsh ;;
	fish)       completion_fish ;;
	yash)       completion_yash ;;
	powershell) completion_powershell ;;
	*) usage_error "unknown completion shell: $1" ;;
	esac
}

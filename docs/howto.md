# git-nest How-To

Practical step-by-step recipes for scenarios that span several commands.
git-nest deliberately keeps these explicit and under your control rather than
automating cross-nest state changes.

## Moving A Subproject Between Nests

A subproject that currently lives in one nest can be moved into a nested nest
(or back out into a parent nest). git-nest never edits two nests in one
command; the move is always under your control, done as an explicit
`detach` + `init` + `absorb` sequence, one nest at a time.

For example, to move `libs/theme` out of the current nest and into a nested
nest rooted at `libs/theme` itself:

```sh
# 1. Remove the subproject from the parent nest, keeping the checkout on disk.
git-nest detach libs/theme

# 2. Make the kept checkout its own nest (--sure confirms an intentional
#    nested nest inside the parent).
cd libs/theme
git-nest init --sure

# 3. Bring it back under the new nested nest's manifest.
git-nest absorb .
```

To move it the other way -- pull a subproject out of a nested nest back into
the parent -- run the same steps from the nested nest: `detach` there, then
`absorb` from the parent nest root. Because `absorb` refuses a path that is
already managed by an ancestor nest, the ordering (detach from the owning
nest first, then absorb into the target nest) is what keeps the operation
unambiguous.

## Pinning And Unpinning Subprojects

By default a subproject tracks an upstream branch: the manifest records a
`target_branch`, and `git-nest pull` fast-forwards it to the branch head.
Sometimes you want the opposite -- a subproject locked to one exact commit
that `pull` leaves alone, until you deliberately move it. That state is
called **pinning**.

### What pinning looks like in the manifest

A tracked subproject records the branch it follows:

```ini
[subproject "libs/foo"]
repo=https://github.com/you/foo.git
target_branch=main
```

A pinned subproject records the exact commit instead. A tag-pinned entry
drops `target_branch` entirely:

```ini
[subproject "libs/foo"]
repo=https://github.com/you/foo.git
revision=abc1234...

[subproject "libs/bar"]
repo=https://github.com/you/bar.git
tag=v2.0
revision=abc1234...
```

`git-nest pull` skips subprojects that are pinned (checked out detached
from a branch), so they stay at the locked revision until you move them.

### Pin to a specific commit

```sh
git-nest update libs/foo --revision abc1234
```

This checks out `abc1234` (detached) and records it as the pinned
revision. The subproject now stays there; `git-nest pull` skips it.

### Pin to a tag

```sh
git-nest update libs/bar --tag v2.0
```

This records both `tag=v2.0` and the resolved `revision`, and drops the
`target_branch` so the subproject is fully pinned. `git-nest verify`
checks that the tag still points at the recorded revision; if the tag
moved, `git-nest update libs/bar --tag v2.0 --force` re-pins to the new
commit (see the `update` help for the exact semantics).

### Unpin and resume tracking

```sh
git-nest update libs/foo --target-head
```

This checks out the branch head again (attached, upstream configured) and
restores the `target_branch` entry. `git-nest pull` fast-forwards the
subproject from now on. To follow a different branch instead, add
`--branch <name>`.

### Repin to a newer commit

```sh
git-nest update libs/foo --revision def5678
```

Same as pinning: the subproject moves to the new commit and stays there.

### Check the pin state of every subproject

```sh
git-nest list
```

The leading reproducibility code per subproject is `R` (reproducible:
checkout matches the recorded revision), `D` (drift: tracked but ahead of
the recorded revision), `M` (missing checkout), or `U` (unpinned: no
revision recorded at all). A pinned subproject shows `R`; a tracked
subproject that has been fast-forwarded but not snapshotted shows `D`.

### Freeze the current checkouts without moving them

`git-nest freeze` records every clean subproject's current HEAD as its
revision in the manifest, without touching any working tree:

```sh
git-nest freeze
```

Use `--only <path>` for a single subproject and `--force` to freeze dirty
subprojects. Freezing pins the recorded revision for reproducibility but
keeps the `target_branch`; run `git-nest snapshot` instead when you want
to record branch-following state without pinning.

## Running One Command After A Batch Operation

`foreach`, `foreach-modified`, `foreach-clean`, `restore`, `snapshot`,
`pull`, and `gc` accept `--finally <cmd>`, `--finally-no-error <cmd>`, and
`--finally-on-error <cmd>` to run a shell command in the nest root once,
after the operation completes. `--finally` always runs; `--finally-no-error`
runs only on full success; `--finally-on-error` runs only when any part
failed. A typical batch recipe commits work inside every dirty subproject
and snapshots the result only when all of it succeeded:

```sh
git-nest foreach-modified \
  --finally-no-error 'git-nest snapshot && git add .gitnest && git commit -m "batch snapshot"' \
  --finally-on-error 'git checkout .gitnest' \
  -- sh -c 'git add -A && git commit -m "WIP"'
```

The manifest lock is released before the callback runs, so a callback may
itself invoke `git-nest` (for example `pull --finally 'git-nest snapshot'`,
or a nested-nest operation). See
[examples.md](examples.md#15-iterate-across-subprojects-with-foreach) for
the full walkthrough with real command output.


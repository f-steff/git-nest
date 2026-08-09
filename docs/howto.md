---
layout: default
title: How-To
nav_order: 6
---

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

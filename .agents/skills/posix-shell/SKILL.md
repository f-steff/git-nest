---
name: posix-shell
description: >
  Expert POSIX sh / Bash shell scripting: write, lint, test, and harden scripts
  for cross-platform portability. Tests across dash, bash --posix, ash, zsh, ksh,
  mksh, yash, posh via Docker Alpine. Also supports Windows Git Bash. Use when
  writing, debugging, or reviewing shell scripts that must work across systems.
---

# posix-shell (pointer)

This is a development-agent pointer. The authoritative posix-shell skill is
maintained in a separate repository, not shipped inside this one:

**<https://github.com/f-steff/POSIX_Shell_Skill>**

## If `source/SKILL.md` exists (skill is installed)

Read and follow `source/SKILL.md` now -- it is the authoritative skill body
with the full guidance, scripts, and reference material. After reading it,
return here and continue.

## If `source/` does not exist (skill not yet installed)

Install it once from the repository root:

```sh
git clone https://github.com/f-steff/POSIX_Shell_Skill.git \
    .agents/skills/posix-shell/source
```

Then re-read this file, which will redirect you to `source/SKILL.md`.

The `source/` directory is ignored via `.gitignore` and must not be committed.
To update the installed skill later, run `git -C .agents/skills/posix-shell/source pull`.
Do not edit this pointer or the installed copy with workflow guidance --
update the upstream repository instead.

---
name: windows-powershell-shell
description: Use when running or composing shell commands on Windows/PowerShell in this repository, especially when commands involve paths with spaces, Git Bash, quoting, escalation after sandbox CreateProcess failures, PowerShell scripts, Git commands, or avoiding mixed-shell filesystem operations.
---

# Windows Powershell Shell

## Purpose

Use this skill to keep Windows command execution predictable. The default shell is
PowerShell, and many failures come from treating it like Bash or from invoking
Bash paths without PowerShell quoting.

## Command Selection

- Prefer native PowerShell for filesystem, process, and simple text inspection:
  `Get-Content`, `Get-ChildItem`, `Select-String`, `Remove-Item`, `New-Item`.
- Prefer `rg` for repository search.
- Use Git directly for Git operations instead of wrapping it in Bash unless a
  repository script explicitly requires Bash.
- Use Git Bash only for repository Bash scripts or inline Bash that is easier
  to express correctly in Bash than in PowerShell.
- Do not mix shells for destructive filesystem operations. If PowerShell finds
  paths, PowerShell should also move or delete them.

## PowerShell Quoting Rules

- Quote executable paths with spaces and invoke them with `&`:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/run-all-tests.sh
```

- Do not write an unquoted path with spaces:

```powershell
C:\Program Files\Git\bin\bash.exe tests/run-all-tests.sh
```

PowerShell parses that as command `C:\Program`.

- Prefer single quotes for literal Windows paths.
- When a command contains both quoting and variables, keep it as PowerShell
  syntax rather than trying to write Bash syntax.
- Avoid command separators and noisy chained commands in normal tool calls.
  Run parallel independent reads with `multi_tool_use.parallel`.

## Sandbox And Escalation Pattern

- If a read-only or necessary command fails with
  `CreateProcessAsUserW failed: 5` or a Windows sandbox runner spawn error,
  rerun the same command with `sandbox_permissions: "require_escalated"` and a
  narrow justification.
- Do not change the command semantics when escalating; keep the retry visibly
  equivalent.
- Use a narrow `prefix_rule` only when it is safe and reusable, such as:
  `["git"]`, `["rg"]`, `["Get-Content"]`, or the exact PowerShell script path.
- Do not request broad prefixes for arbitrary `python`, shell heredocs, or
  destructive commands.

## Git Bash From PowerShell

- Use this pattern when a repository Bash script is required:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/run-all-tests.sh
```

- For inline Bash, keep the outer command PowerShell and the `-lc` payload
  Bash. Quote the Git Bash path and put Bash syntax inside the payload:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -lc 'sh -n bin/git-nest && tests/run-all-tests.sh'
```

- Do not put PowerShell syntax such as `$env:TEMP`, `Get-Content`, or
  `Select-String` inside the `-lc` payload. Do not put Bash syntax such as
  `for f in tests/integration-tests/*.sh; do ...; done` directly in PowerShell.
- If Git Bash startup prints `.bashrc` noise, ignore it only when the command
  exit code and expected output are otherwise correct; do not hide real command
  failures behind startup warnings.
- Prefer repository-native Windows launchers when Windows launcher behavior is
  what needs testing: `bin/git-nest.bat` from cmd.exe or Git Bash, and
  `bin/git-nest.ps1` from PowerShell.

## Editing Files

- Use `apply_patch` for manual source and documentation edits.
- If `apply_patch` cannot run because of a sandbox runner failure, prefer
  retrying with a safe native PowerShell edit only for small, controlled text
  changes, and state why.
- Do not use Python to edit files when `apply_patch` or a simple PowerShell
  operation is sufficient.
- When reading paths outside the current workspace, expect the sandbox to block
  otherwise harmless `Get-Content` or Git Bash reads. Retry the same read-only
  command with escalation instead of changing shells or rewriting the command.

## Practical Checks

- Before committing or reporting shell-sensitive work, check:

```powershell
git status --short
```

- For repository searches that should ignore test artifacts, add explicit globs:

```powershell
rg "GIT_NEST" bin tests -n
```

- For line-numbered file inspection in PowerShell:

```powershell
$i=0; Get-Content tests\run-all-tests.sh | ForEach-Object { $i++; if ($i -ge 10 -and $i -le 30) { '{0,4}: {1}' -f $i, $_ } }
```

If that hits the Windows sandbox spawn issue, rerun it escalated as the same
read-only command.

- When rerunning integration tests manually, use a fresh `TEST_ROOT` or clear
  the previous one. Reusing numbered test workspaces can make setup fail before
  the first logged test step and look like a shell failure.

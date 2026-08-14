# git-nest tui

`git-nest tui` is a minimal, pure-POSIX-shell terminal UI over the
git-nest inspection commands. It shows the nest as an interactive menu:
pick an action, optionally pick a subproject, and git-nest runs it -- the
output appears in the command log pane below. Every action spawns a fresh
`git-nest` instance; the TUI itself only orchestrates.

```
+--------------------------------------------------------------------------------------------+
|  git-nest tui  -  /home/you/acme-app  -  3 subprojects                                      |
|  ^ arrowkeys move, Enter select, Tab focus, ^H help, ^L resize, ESC back, q quit           |
|  +--- menu (actions) ----------------------+--- description (Snapshot) ---+                |
|  > Status                                  |  Record clean, reproducible  |                |
|    Tree                                    |  checked-out subproject       |                |
|    List                                    |  commits in .gitnest.         |                |
|    Survey                                  |                                |                |
|    Verify                                  |                                |                |
|    Outdated                                |                                |                |
|    Diff                                    |                                |                |
|    Doctor                                  |                                |                |
|    Snapshot                                |                                |                |
|    Pull                                    |                                |                |
|  +------------------------------------------+-------------------------------+                |
|  > git-nest version                                                                         |
|  git-nest 0.8.26 \\_oOO_//                                                                  |
|  > git-nest status                                                                          |
|  outer branch: main                                                                         |
|  libs/one: clean                                                                            |
+--------------------------------------------------------------------------------------------+
```

The screen is split into three panes:

- **Menu pane** (left): the action list, or the subproject picker when a
  path-taking action is selected. The highlighted row is prefixed with
  `>`.
- **Description pane** (right, read-only): a few lines about the
  highlighted action, reused from `git-nest help <command>`. In the
  subproject picker it shows the selected subproject's recorded state.
- **Log pane** (bottom): every git-nest command that the TUI runs,
  prefixed with `>`, followed by its output. The log starts with
  `> git-nest version` and its result.

## Requirements

`git-nest tui` needs a real interactive terminal:

- stdin and stdout must be a TTY (`[ -t 0 ] && [ -t 1 ]`).
- `stty` raw mode must be available.
- On Windows, run it from a **Git Bash (mintty) window**. The
  `git-nest.bat` and `git-nest.ps1` launchers attach bash to the Windows
  console (no mintty), so the TUI refuses to start there with a message
  that includes the exact one-liner to open mintty instead (see below).

If the gate fails, the command exits cleanly with a message like:

```
$ git-nest tui < /dev/null
git-nest tui needs an interactive terminal (stdin/stdout must be a TTY).
```

### Why the TUI does not run in cmd.exe / PowerShell

The TUI reads a single keystroke at a time (`stty -icanon` raw mode plus
a one-byte read). That only works when bash has a real **pseudo-terminal
(pty)**. The two ways to start git-nest on Windows differ in exactly that
respect:

| Start git-nest via... | bash stdin/stdout | Result |
|-|-|-|
| `git-nest.bat` / `git-nest.ps1` | **Windows console (no pty)** -- `tty` reports "not a tty" | the TUI refuses; raw key reads would never return |
| `git-bash.exe` (mintty) | **real pty** (`/dev/pty0`) | the TUI runs normally |

The `.bat` and `.ps1` launchers spawn `bash.exe --noprofile --norc`
inside your current console window. MSYS fakes termios over the console
well enough that `stty` reports success, but a single-byte read from the
console blocks until Enter is pressed -- so the TUI cannot work there.
It is not a scripting problem that shell code could work around; the
console is simply not a pty. This is the same reason `vim`, `tmux`, and
`fzf` require mintty (or `winpty`) on Windows.

### Opening mintty from the message

When the gate refuses a launcher start, it prints the exact command to
open a **new mintty window** in the current folder and run the TUI:

```
git-nest tui needs a Git Bash (mintty) window; you launched it via the powershell launcher.
Open Git Bash here and run the TUI:
  cmd.exe:        "C:\Program Files\Git\git-bash.exe" --cd="C:\Projects\github\f-steff\git-nest" -c "git-nest tui"
  PowerShell:     & "C:\Program Files\Git\git-bash.exe" --cd="C:\Projects\github\f-steff\git-nest" -c "git-nest tui"
```

`git-bash.exe --cd="<dir>" -c "<command>"` is mintty's launcher: it opens
a new window with a real pty, changes to `<dir>`, and runs the command.
Pasting either line into cmd.exe or PowerShell works -- it does not run
the TUI *in* your console window, it opens a separate Git Bash window
for it (that is inherent: the current console cannot host the TUI).

The path and folder in the message are resolved on the machine where the
message is printed (`git-bash.exe` from the MSYS root, the nest folder
via `cygpath -w`), so the line is ready to paste as-is.

## Keys

| Key | What it does |
|-|-|
| Arrow up / down | Move the menu highlight |
| Enter | Run the highlighted action (or select the highlighted subproject) |
| Tab / Shift-Tab | Move pane focus forward / backward |
| Ctrl-H | Toggle the help overlay |
| Ctrl-L | Re-measure the terminal and redraw (also after resize) |
| ESC | Back to the previous menu level; at the top level, quit |
| q / Ctrl-C | Quit |

The terminal is restored on quit and on Ctrl-C (echo, cursor, colors).

## Actions

The top-level menu offers the zero-argument commands:

```
Status   Tree   List   Survey   Verify   Outdated   Diff   Doctor
Snapshot Pull   Restore GC       Freeze   Help
```

`Help` opens the help overlay. The others run `git-nest <command>` and
show the output in the log.

Selecting **Snapshot**, **Update**, **Detach**, **Remove**, **Inline**,
**Add**, **Move**, or **Export** switches the menu to the subproject
picker. Move the highlight to a subproject and press Enter:

```
+--- menu (subproject picker) -----------------+
> libs/one                                     |
  libs/two                                     |
  vendor/ui-kit                                |
+----------------------------------------------+
```

### Per-subproject actions

| Action | Runs | Notes |
|-|-|-|
| Snapshot | `git-nest snapshot <path>` | Records the subproject's current revision |
| Update | `git-nest update <path> --revision <value>` | Prompts for revision/tag/branch first |
| Detach | `git-nest detach <path>` | Asks for confirmation |
| Remove | `git-nest remove <path>` | Asks for confirmation |
| Inline | `git-nest inline <path>` | Asks for confirmation |
| Add | `git-nest add <url> <path>` | Prompts for the repository URL first |
| Move | `git-nest move <path> <new-path>` | Prompts for the new path first |
| Export | `git-nest export --output <dir>` | Prompts for the output directory first |

Actions that take one free-text value show a single-line prompt above the
log pane. Type the value and press Enter to run, or ESC to cancel:

```
update libs/one -- revision/tag/branch: v2.0.1_
```

Destructive actions ask for confirmation before running:

```
confirm remove libs/two [y/N]: y
```

## Examples

Start the TUI in the nest root:

```sh
git-nest tui
```

Run it through `git nest` (the git-subcommand alias) identically:

```sh
git nest tui
```

Pick **Snapshot**, then a subproject, then read the log to confirm:

```
> git-nest snapshot libs/one
Snapshot unchanged for libs/one at a1b2c3d.
```

The description pane always mirrors `git-nest help <command>`, so the TUI
is consistent with the command-line documentation:

```sh
git-nest help snapshot   # the same text the description pane shows
```

## See Also

- [`examples.md`](examples.md) -- full walkthroughs of the underlying
  commands.
- [`howto.md`](howto.md) -- recipes for multi-step scenarios.
- [`manifest.md`](manifest.md) -- the `.gitnest` format reference.

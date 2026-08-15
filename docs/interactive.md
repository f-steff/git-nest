# git-nest interactive

`git-nest interactive` (short alias `git-nest ii`) is a line-based,
guided menu over the full git-nest command surface. It needs no
terminal UI machinery: menus are numbered lines, input is plain lines,
and every action runs a fresh `git-nest` (or `git`) sub-process with
live output. It works identically in Git Bash, mintty, cmd.exe,
PowerShell, and even through pipes.

Why it exists: a full-screen TUI needs raw terminal mode and ANSI
repainting, which is slow and does not work on the Windows console.
A numbered menu avoids all of that.

## Starting

```
$ git-nest interactive
$ git-nest ii
```

The startup banner runs `git-nest version` through the same runner as
every other action, so the transcript starts with:

```
/home/you/acme-app>git-nest version
git-nest 0.8.26 \_oOO_//
```

## The menu

```
Nest setup
  1. tidy             - Refresh managed support files
  2. clone            - Clone a nest repository and restore it here
Subprojects
  3. add              - Add a repository as a managed subproject (URL + path)
  4. move             - Move a subproject to a new path
  ...
Nest contents
 30. bring in (absorb)               - Show detected repos/submodules, then absorb them
 31. take out (inline/detach/remove) - Show the tree, pick a subproject, inline/detach/remove
 32. export                          - Export a source snapshot with MANIFEST.lock
Tooling
 33. version          - Show the git-nest version
Navigation
 34. change directory - Move one level into a subfolder
  b. back             - Return to the previous menu
  q. quit             - Exit git-nest interactive
```

- Numbers are right-aligned so the units column lines up (` 10.` sits
  under `  1.`); labels are padded to the longest label in the menu.
- Type a number and press Enter to run that option.
- `b` (or an empty line) goes back to the previous menu.
- `q` exits gracefully. EOF (Ctrl-D, or an exhausted scripted input
  list) also exits gracefully.

## The menu adapts to the folder

The offered commands depend on what the current folder already is:

| Folder state | Menu |
|-|-|
| No Git repository anywhere up the tree | `git init` (the real Git command), `version`, `change directory` |
| Git repository, no `.gitnest` | `git-nest init`, `git-nest clone`, `version`, `change directory` |
| Inside a nest | the full grouped command surface plus `change directory` |

The context is re-detected after every action, so the menu follows the
workspace as it changes:

```
> 1
/home/you/acme-app>git init
Initialized empty Git repository in /home/you/acme-app/.git/

Nest setup
  1. git-nest init    - Create a .gitnest manifest at the Git root
  ...

> 1
/home/you/acme-app>git-nest init
Initialized git-nest workspace.

Nest setup
  1. tidy             - Refresh managed support files
  ...
```

## Running actions

Every action first prints the exact command that is about to run in the
`cwd>command ...` format, then executes it with stdout and stderr
inherited, so the output streams live:

```
> 14
/home/you/acme-app>git-nest status
outer branch: main
subprojects:
```

A command that ends nonzero does not kill the session; its output is
shown and the menu returns.

## Commands that need arguments

Some menu entries ask for arguments on the next line. The value is
appended to the command verbatim:

```
> 2
Enter arguments for git-nest clone (empty cancels): https://example.invalid/acme-nest.git
/home/you/acme-app>git-nest clone https://example.invalid/acme-nest.git
```

- `add` takes a repository URL and a target path, e.g.
  `git@example.com:team/libs.git libs/team`.
- `config` takes the full config arguments, e.g. `list` or
  `set libs/team clone-mode partial`.
- `update` takes the target, e.g. `--remote` or `--revision <sha>`.
- `foreach`, `foreach-modified`, and `foreach-clean` take the shell
  command to run in each subproject, e.g. `git status --short`.
- `branch-unmark` takes a branch name.
- `export` takes the output path.
- An empty line cancels the command.

## Commands that need a subproject

`move` and `update` first show a picker with one numbered entry per
managed subproject:

```
> 4
  1. libs/team - managed subproject
  b. back      - Return to the previous menu
  q. quit      - Exit git-nest interactive
> 1
/home/you/acme-app>git-nest move libs/team
```

The chosen path is then followed by the free-text value on the next
line.

## Membership flows (bring in / take out)

The "Nest contents" group combines seeing with acting, so the options
are easy to discover.

**Bring in (absorb)** first runs `survey` (live output showing what it
found and the suggested next step), then shows a picker of the detected
targets with their kinds:

```
> 30
/home/you/acme-app>git-nest survey
Unmanaged repositories discovered under the current nest:
  R  libs/team                    nested-repo  run git-nest absorb libs/team to manage it
  G  vendor/thing                 subrepo      run git-nest absorb --subrepo vendor/thing to manage it
  1. libs/team   - nested-repo
  2. vendor/thing - subrepo
  a. absorb all detected
  m. type a folder or path manually
  b. back - Return to the previous menu
  q. quit - Exit git-nest interactive
> 1
/home/you/acme-app>git-nest absorb libs/team
```

- Picking a target runs the right absorb form automatically:
  submodules, nested repos, nest roots, and detached former subprojects
  absorb plainly; git-subrepos get the explicit `--subrepo` flag.
- `a` absorbs every detected target in one batch (confirmed with
  `[y/N]`), equivalent to `git-nest absorb-all`.
- `m` accepts a manually typed path. Folders (outer-repo files) have no
  `.git`, so the flow asks for the remote URL before running:
  `absorb <path> <url>`; repositories and subrepos absorb without one.
  Subtree-shaped directories have no marker and are always reached
  through `m` with a remote URL.
- After every action the picker re-renders from a fresh survey, so
  absorbed items disappear.

**Take out (inline/detach/remove)** first runs `tree --all` (the whole
nest, managed and unmanaged), then lets you pick a managed subproject
and choose what to do with it:

```
> 31
/home/you/acme-app>git-nest tree --all
...
  1. libs/team - managed subproject
  b. back      - Return to the previous menu
  q. quit      - Exit git-nest interactive
> 1
Take out libs/team: inline (i), detach (d), or remove (r)? d
Run git-nest detach libs/team? [y/N]: y
/home/you/acme-app>git-nest detach libs/team
```

`i` dissolves the subproject into outer tracked files (inline), `d`
detaches it as a standalone still-ignored repository, `r` removes it
and deletes the checkout. Each verb is confirmed before it runs.

## Navigating the filesystem

The `change directory` entry moves the session's working directory one
layer at a time. Subdirectories are numbered entries; `..` (when the
current folder has a parent) goes up one level; `b` returns to the main
menu, where the context is re-detected for the new location:

```
> 34
  1. ..  - Go up one level
  2. sub - Open this folder
  b. back - Return to the previous menu
  q. quit - Exit git-nest interactive
> 2
  1. .. - Go up one level
  b. back - Return to the previous menu
  q. quit - Exit git-nest interactive
> b
> 33
/home/you/acme-app/sub>git-nest version
```

Hidden directories are excluded, and the current folder is never
changed unless the chosen entry is selected.

## Scripted input (testing)

`git-nest interactive` accepts two internal switches so tests and
scripts can drive the loop without a terminal. They are not part of the
documented command surface or shell completion.

- `--ii-test <token>...` feeds the listed tokens as scripted input
  lines, one per read. The consumed tokens are echoed so the transcript
  shows what was "typed". When the list runs out, the session exits
  gracefully.
- `--ii-skip <n>` drops the first n tokens before feeding begins,
  letting a test fast-forward past steps a previous invocation already
  applied to the filesystem.

```
$ git-nest interactive --ii-test 1 q                 # git init, quit
$ git-nest interactive --ii-test 1 14 q              # git-nest init, status, quit
$ git-nest interactive --ii-test 1 2 14 q --ii-skip 2   # status only
```

## Windows

Because the menu never enters raw terminal mode, `git-nest interactive`
runs directly in cmd.exe and PowerShell through the normal launchers:

```
.\bin\git-nest.ps1 interactive
bin\git-nest.bat ii
```

No mintty window or terminal trickery is involved.

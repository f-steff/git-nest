# Rich's sh (POSIX shell) Tricks -- Condensed Reference

Source: https://www.etalabs.net/sh_tricks.html

## Table of Contents

- [Output & Printing](#output--printing)
- [Input & Reading](#input--reading)
- [Variables & Strings](#variables--strings)
- [Functions & Scope](#functions--scope)
- [Pattern Matching & Globs](#pattern-matching--globs)
- [Files & Directories](#files--directories)
- [Data Processing](#data-processing)
- [Environment & Locale](#environment--locale)
- [Portable Commands](#portable-commands)

---

## Output & Printing

**Printing a variable** (use case: safe output)
- SAFE: `printf '%s\n' "$var"`
- UNSAFE: `echo "$var"` -- unspecified with `\` or `-n`
- *Reference:* SKILL.md "printf vs echo"

**Writing bytes by numeric value** (use case: binary data)
```sh
writebytes() { printf %b "$(printf '\\%03o' "$@")"; }
```

---

## Input & Reading

**Reading input line-by-line** (use case: file parsing)
- `IFS= read -r var` -- always use both IFS= and -r
- Pipeline pitfall: `foo | IFS= read var` -- may run in subshell
  Use heredoc instead: `IFS= read var <<EOF\n$(foo)\nEOF`
- *Reference:* SKILL.md "Reading Input"

**Reading binary byte-by-byte** (use case: binary file processing)
```sh
read dummy oct <<EOF
$(dd bs=1 count=1 | od -b)
EOF
```

---

## Variables & Strings

**Parameter expansion** (use case: string manipulation)
- `${var:-word}` -- default if unset/null
- `${var:=word}` -- assign default
- `${var:?msg}` -- error if unset/null
- `${var:+word}` -- alternate if set
- `${var#pat}` / `${var##pat}` -- remove prefix
- `${var%pat}` / `${var%%pat}` -- remove suffix
- *Reference:* SKILL.md "Parameter Expansion"

**Shell-quoting arbitrary strings** (use case: safe eval, generated scripts)
```sh
quote() { printf '%s\n' "$1" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/"; }
```

**Counting character occurrences** (use case: text analysis)
```sh
tr -dc 'a' | wc -c        # unsafe for non-ASCII
tr 'a\n' '\na' | wc -l     # safe alternative
```

---

## Functions & Scope

**Returning strings from functions** (use case: output capture without subshell)
```sh
func() {
  # ... compute result into $foo ...
  eval "$1=\$foo"
}
```
*Note:* This technique avoids the trailing-newline stripping of `$()`.

**Working with arrays (using $@)** (use case: array-like data in POSIX sh)
```sh
save() {
  for i do printf '%s\n' "$i" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/' \\\\/"; done
  echo " "
}
myarray=$(save "$@")
set -- foo bar baz
eval "set -- $myarray"
```

**Removing all exports** (use case: sanitizing environment)
```sh
unexport_all() {
  eval set -- "$(export -p)"
  for i; do
    case "$i" in
      *=*) unset "${i%%=*}"; eval "${i%%=*}=\$ {i#*=}" ;;
    esac
  done
}
```

---

## Pattern Matching & Globs

**Filename pattern matching** (use case: test string against glob)
```sh
fnmatch() { case "$2" in $1) return 0;; *) return 1;; esac; }
```

**Matching dotfiles** (use case: iterating hidden files)
- `. [!. ]*` -- hidden files except `.` and `..`
- `.. ?*` -- double-dot files with 2+ chars
- `*` -- non-hidden files
- *Reference:* SKILL.md "Glob Patterns for Dotfiles"

---

## Files & Directories

**Testing if directory is empty** (use case: pre-cleanup check)
```sh
is_empty() (
  cd "$1"
  set -- .[!.]*; [ -f "$1" ] && return 1
  set -- ..?*;  [ -f "$1" ] && return 1
  set -- *;     [ -f "$1" ] && return 1
  return 0
)
```

**Querying a user's home directory** (use case: user-specific paths)
```sh
eval "foo=~$user"  # safe if $user is trusted
```

---

## Data Processing

**Counting character occurrences** (use case: text analysis)
```sh
tr -dc 'a' | wc -c        # unsafe for non-ASCII
tr 'a\n' '\na' | wc -l     # safe alternative
```

---

## Environment & Locale

**Locale override** (use case: predictable sorting/parsing)
```sh
eval export "$(locale)"; unset LC_ALL
LC_COLLATE=C ls
```
- *Reference:* SKILL.md "Locale Safety"

---

## Portable Commands

**Portable find with xargs** (use case: batch file processing)
```sh
find ... | sed 's/./\\&/g' | xargs command
```
Better: `find ... -exec command '{}' +`

**Portable find -print0** (use case: safe filename handling with xargs)
```sh
find ... -exec printf '%s\0' '{}' +
```

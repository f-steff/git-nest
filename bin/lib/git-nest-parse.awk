# git-nest: record and restore reproducible nests of independent Git repositories.
# https://github.com/f-steff/git-nest
#
# Single-pass .gitnest parser used by manifest_load_cache in
# git-nest-manifest.sh: emits shell-assignable variable declarations for eval,
# avoiding a subprocess per key read.
#
# Copyright (c) 2026 Flemming Steffensen.
# License: MIT
# SPDX-License-Identifier: MIT

# Encode a subproject path into a variable-name-safe, collision-resistant
# segment. Must match manifest_varname() in git-nest-manifest.sh exactly:
# both hash the raw path with cksum rather than lossily substituting
# characters, so a path containing spaces (or other characters that are not
# valid in a shell variable name) never breaks the eval'd assignment, and two
# different paths never collapse onto the same variable name.
function shquote(s,   r) {
    r = s
    gsub(/'/, "'\\''", r)
    return "'" r "'"
}

function path_hash(p,   hashcmd, hashline, hashparts) {
    hashcmd = "printf '%s' " shquote(p) " | cksum"
    hashcmd | getline hashline
    close(hashcmd)
    split(hashline, hashparts, " ")
    return hashparts[1]
}

BEGIN { sp_list = ""; section = "" }

/^[[:space:]]*$/ || /^[[:space:]]*#/ { next }

/^\[project\]$/ { section = "project"; next }

/^\[subproject "[^"]*"\]$/ {
    p = $0
    gsub(/^\[subproject "/, "", p)
    gsub(/"\]$/, "", p)
    if (sp_list == "") sp_list = p; else sp_list = sp_list "\n" p
    section = "sp_" path_hash(p)
    next
}

/^\[/ { section = ""; next }

index($0, "=") > 0 {
    eq = index($0, "=")
    if (section == "") next
    key = substr($0, 1, eq - 1)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
    gsub(/[-.]/, "_", key)
    val = substr($0, eq + 1)
    gsub(/'/, "'\\''", val)
    printf "_mnf_%s_%s='%s'\n", section, key, val
}

END {
    if (sp_list != "") {
        printf "_MNF_SP='%s'\n", sp_list
    }
}

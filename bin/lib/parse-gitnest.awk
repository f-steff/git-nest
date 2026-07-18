BEGIN { sp_list = ""; section = "" }

/^[[:space:]]*$/ || /^[[:space:]]*#/ { next }

/^\[project\]$/ { section = "project"; next }

/^\[subproject "[^"]*"\]$/ {
    p = $0
    gsub(/^\[subproject "/, "", p)
    gsub(/"\]$/, "", p)
    if (sp_list == "") sp_list = p; else sp_list = sp_list "\n" p
    section = p
    gsub(/\//, "__", section)
    gsub(/[-.]/, "_", section)
    section = "sp_" section
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

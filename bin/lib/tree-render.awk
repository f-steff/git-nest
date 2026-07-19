# git-nest: record and restore reproducible nests of independent Git repositories.
# https://github.com/f-steff/git-nest
#
# Renders a flat list of paths (one code<TAB>path<TAB>annotation triple per
# line on stdin, pre-sorted by path) as an ASCII-art tree grouped by shared
# directory prefixes. Uses only ASCII connectors (|--, `--, |, spaces), the
# same convention GNU tree's --charset=ascii mode uses -- no Unicode
# box-drawing characters, per the project's ASCII-only rule.
#
# Copyright (c) 2026 Flemming Steffensen.
# License: MIT
# SPDX-License-Identifier: MIT

function shownode(key, prefix,    kids, n, i, childkey, name, is_last, connector, line, childprefix) {
	n = split(order[key], kids, "\x1f")
	for (i = 1; i <= n; i++) {
		childkey = kids[i]
		name = childkey
		sub(/^.*\//, "", name)
		is_last = (i == n)
		connector = is_last ? "`-- " : "|-- "
		line = prefix connector name
		if (childkey in leafannot && leafannot[childkey] != "") {
			line = line "  " leafannot[childkey]
		}
		print line
		childprefix = prefix (is_last ? "    " : "|   ")
		shownode(childkey, childprefix)
	}
}

BEGIN { FS = "\t" }

{
	code = $1
	path = $2
	annot = $3
	if (path == "") next
	n = split(path, parts, "/")
	key = ""
	for (i = 1; i <= n; i++) {
		parentkey = key
		key = (key == "" ? parts[i] : key "/" parts[i])
		if (!(key in seen)) {
			seen[key] = 1
			order[parentkey] = order[parentkey] (order[parentkey] == "" ? "" : "\x1f") key
		}
	}
	leafannot[path] = (code == "M" ? "" : "[" code "] " annot)
}

END {
	print "."
	shownode("", "")
}

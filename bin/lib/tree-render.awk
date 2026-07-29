# git-nest: record and restore reproducible nests of independent Git repositories.
# https://github.com/f-steff/git-nest
#
# Renders a flat list of paths (one code<TAB>path<TAB>annotation triple per
# line on stdin, pre-sorted by path) as an ASCII-art tree grouped by shared
# directory prefixes. Every branch uses a single "+-- " connector (never a
# different glyph for the last child of a level) and every entry gets a
# trailing "/" (everything git-nest's tree shows is a directory: a managed
# subproject checkout or an ordinary path-grouping directory above one).
# Continuation columns still use "|" for an ancestor level that has further
# siblings below it and blank spaces once it does not, the same convention
# GNU tree's --charset=ascii mode uses -- no Unicode box-drawing characters,
# per the project's ASCII-only rule. This single-glyph style is deliberately
# simpler to paste and share (e.g. in an issue or chat) than alternating
# connectors, since every line looks the same regardless of position.
#
# Copyright (c) 2026 Flemming Steffensen.
# License: MIT
# SPDX-License-Identifier: MIT

function shownode(key, prefix,    kids, n, i, childkey, name, is_last, line, childprefix) {
	n = split(order[key], kids, "\x1f")
	for (i = 1; i <= n; i++) {
		childkey = kids[i]
		name = childkey
		sub(/^.*\//, "", name)
		is_last = (i == n)
		line = prefix "+-- " name "/"
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

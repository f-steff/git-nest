# git-nest: record and restore reproducible nests of independent Git repositories.
# https://github.com/f-steff/git-nest
#
# Renders a flat list of paths (tab-separated records on stdin) as an ASCII-art
# tree grouped by shared directory prefixes. Input is 4 columns:
#   code \t path \t url \t typelabel
# where path "." is the nest root line (not rendered as a tree branch).
#
# In full mode (plain=0) each leaf shows:
#   +-- name/    [code] url    [typelabel]
#
# In plain mode (plain=1) each leaf shows only:
#   +-- name/    [code]
#
# Every branch uses a single "+-- " connector, every entry gets a trailing "/",
# continuation columns use "|" for levels with further siblings and blank spaces
# once they do not. No Unicode box-drawing characters.
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
			line = line " " leafannot[childkey]
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
	url = $3
	typelabel = $4

	if (path == "") next

	# Root line: store and skip tree building.
	if (path == ".") {
		root_code = code
		root_url = url
		root_typelabel = typelabel
		next
	}

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

	if (plain) {
		if (code != "") {
			leafannot[path] = "[" code "]"
		}
	} else {
		annot = ""
		if (code != "") {
			annot = "[" code "]"
		}
		if (url != "") {
			annot = annot (annot == "" ? "" : " ") url
		}
		if (typelabel != "") {
			annot = annot "    [" typelabel "]"
		}
		leafannot[path] = annot
	}
}

END {
	# Root line
	root_line = "."
	if (root_code != "") {
		root_line = root_line "    [" root_code "]"
		if (!plain) {
			if (root_url != "") {
				root_line = root_line " " root_url
			}
			if (root_typelabel != "") {
				root_line = root_line "    [" root_typelabel "]"
			}
		}
	}
	print root_line
	shownode("", "")
}

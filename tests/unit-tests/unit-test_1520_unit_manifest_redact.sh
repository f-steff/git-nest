#!/bin/sh
# Unit test: redact_stream and json_array_from_lines
# Coverage: redact_stream, json_array_from_lines

set -eu
. "$(dirname "$0")/helper.sh"

setup_unit_test
load_lib "git-nest-manifest.sh"

# redact_stream: strips credentials from URLs in a text stream.
# Supply a HOME directory so the home-path redaction also fires.
HOME=/home/testuser
export HOME

# Test credential redaction in URLs.
printf 'repo is https://user:pass@example.invalid/path.git\n' | redact_stream >_redacted.txt
grep -F 'https://***@example.invalid/path.git' _redacted.txt >/dev/null || {
    echo "FAIL: credentials not redacted" >&2
    cat _redacted.txt >&2
    exit 1
}

# Non-credential URLs pass through unchanged.
printf 'repo is https://example.invalid/path.git\n' | redact_stream >_redacted2.txt
grep -F 'https://example.invalid/path.git' _redacted2.txt >/dev/null || {
    echo "FAIL: clean URL should not be touched" >&2
    cat _redacted2.txt >&2
    exit 1
}

# json_array_from_lines: converts a file of lines to a JSON string array.
printf 'hello\nworld\n' >_lines.txt
_json=$(json_array_from_lines _lines.txt)
printf '%s\n' "$_json" | grep -F '"hello"' >/dev/null || { echo "FAIL: hello not in array" >&2; exit 1; }
printf '%s\n' "$_json" | grep -F '"world"' >/dev/null || { echo "FAIL: world not in array" >&2; exit 1; }

printf 'All tests passed.\n'

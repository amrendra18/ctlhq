#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' 'Stand-in files only. No external downloads or Java execution.'
python3 "$here/test_formal_tools.py"
test_exit=$?
printf 'formal tools tests exit %s\n' "$test_exit"
exit "$test_exit"

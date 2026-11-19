#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/speechara-auth-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cat "$project_dir/Speechara/Services/AuthService.swift" "$project_dir/Tests/AuthSecurity/Harness.swift" > "$test_dir/AuthSecurity.swift"
xcrun swiftc -swift-version 5 -parse-as-library "$test_dir/AuthSecurity.swift" -o "$test_dir/auth-security-tests"
"$test_dir/auth-security-tests"

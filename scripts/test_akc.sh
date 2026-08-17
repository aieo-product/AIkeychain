#!/bin/bash
# Integration tests for akc CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AKC="$SCRIPT_DIR/akc"
PASS=0
FAIL=0

assert_exit() {
    local expected=$1; shift
    local actual
    set +e
    "$@" >/dev/null 2>&1
    actual=$?
    set -e
    if [ "$actual" -eq "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  ✅ exit=$actual (expected $expected): $*"
    else
        FAIL=$((FAIL + 1))
        echo "  ❌ exit=$actual (expected $expected): $*"
    fi
}

assert_contains() {
    local pattern=$1; shift
    local output
    set +e
    output=$("$@" 2>&1)
    set -e
    if echo "$output" | grep -q "$pattern"; then
        PASS=$((PASS + 1))
        echo "  ✅ output contains '$pattern'"
    else
        FAIL=$((FAIL + 1))
        echo "  ❌ output missing '$pattern': got '$output'"
    fi
}

echo "=== akc CLI Tests ==="

echo ""
echo "--- Basic commands ---"
assert_exit 0 "$AKC" help
assert_exit 0 "$AKC" version
assert_exit 0 "$AKC" --help
assert_contains "akc 2.0.0" "$AKC" version

echo ""
echo "--- Error handling ---"
assert_exit 1 "$AKC" invalid_command
assert_exit 1 "$AKC" run
assert_exit 1 "$AKC" run --invalid-flag

echo ""
echo "--- Run with no keychain refs ---"
# Should pass through cleanly when no keychain:// vars exist
assert_exit 0 env -i PATH="$PATH" "$AKC" run -- echo "hello"
assert_contains "hello" env -i PATH="$PATH" "$AKC" run -- echo "hello"

echo ""
echo "--- Dry run ---"
assert_exit 0 env -i PATH="$PATH" "$AKC" run --dry-run
assert_contains "Resolved: 0" env -i PATH="$PATH" "$AKC" run --dry-run

echo ""
echo "--- Dry run with keychain ref ---"
# Set a fake keychain:// ref — it won't resolve but dry-run should report it
assert_contains "not found" env -i PATH="$PATH" AKC_TEST_KEY="keychain://AKC_NONEXISTENT_TEST_KEY_12345" "$AKC" run --dry-run

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]

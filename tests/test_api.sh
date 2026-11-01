#!/usr/bin/env bash
# Dependency-free unit checks for the Bash router, with a JUnit XML report.
set -uo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=app/router.sh
source "$root/app/router.sh"
mkdir -p "$root/reports"
report="$root/reports/test-results.xml"
total=0
failed=0
results=()

check() {
    local name=$1 target=$2 expected_status=$3 expected_body=$4
    route GET "$target"
    total=$((total + 1))
    if [[ $status == "$expected_status" && $body == "$expected_body" ]]; then
        printf 'PASS %s\n' "$name"
        results+=("<testcase classname=\"api\" name=\"$name\" />")
    else
        failed=$((failed + 1))
        printf 'FAIL %s: expected HTTP %s %s; got HTTP %s %s\n' \
            "$name" "$expected_status" "$expected_body" "$status" "$body" >&2
        results+=("<testcase classname=\"api\" name=\"$name\"><failure message=\"response mismatch\" /></testcase>")
    fi
}

router='{"id":1,"name":"router","stock":8}'
switch='{"id":2,"name":"switch","stock":3}'
both="{\"items\":[$router,$switch]}"
switch_only="{\"items\":[$switch]}"
none='{"items":[]}'
bad_threshold='{"error":"threshold must be an integer from 0 to 100"}'

check health /health 200 '{"status":"ok"}'
check items /api/items 200 "$both"
check item_not_found /api/items/999 404 '{"error":"item not found"}'
check low_stock_0 '/api/items/low-stock?threshold=0' 200 "$none"
check low_stock_3 '/api/items/low-stock?threshold=3' 200 "$none"
check low_stock_4 '/api/items/low-stock?threshold=4' 200 "$switch_only"
check low_stock_8 '/api/items/low-stock?threshold=8' 200 "$switch_only"
check low_stock_9 '/api/items/low-stock?threshold=9' 200 "$both"
check low_stock_100 '/api/items/low-stock?threshold=100' 200 "$both"
check missing_threshold '/api/items/low-stock' 400 "$bad_threshold"
check negative_threshold '/api/items/low-stock?threshold=-1' 400 "$bad_threshold"
check too_large_threshold '/api/items/low-stock?threshold=101' 400 "$bad_threshold"
check text_threshold '/api/items/low-stock?threshold=abc' 400 "$bad_threshold"
check decimal_threshold '/api/items/low-stock?threshold=3.5' 400 "$bad_threshold"
check signed_threshold '/api/items/low-stock?threshold=+3' 400 "$bad_threshold"
check repeated_threshold '/api/items/low-stock?threshold=4&threshold=8' 400 "$bad_threshold"

{
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<testsuite name="bash-api" tests="%d" failures="%d">\n' "$total" "$failed"
    printf '  %s\n' "${results[@]}"
    printf '</testsuite>\n'
} > "$report"

printf '%d tests, %d failures; JUnit: %s\n' "$total" "$failed" "$report"
(( failed == 0 ))

#!/usr/bin/env bash
#
# Runs warrantiak's ASUS check against the local mock (test/asus_mock).
# Playwright tests are skipped when the Python module is not installed.
#
# Usage: test/test_asus.sh        (or: make test)
# Env:   MOCK_PORT (default 18765)

set -o nounset
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${MOCK_PORT:-18765}"
BASE="http://127.0.0.1:$PORT"
TMP="$(mktemp -d)"
PASS=0
FAIL=0
SKIP=0

cleanup() {
    [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null
    rm -rf "$TMP"
}
trap cleanup EXIT

# Fake browser openers, so browser mode never opens a real browser
mkdir -p "$TMP/bin"
for opener in xdg-open open; do
    printf '#!/bin/sh\necho "$1" > "%s/opened.txt"\n' "$TMP" > "$TMP/bin/$opener"
    chmod +x "$TMP/bin/$opener"
done

# Start the mock in autosubmit mode (the page clicks Submit by itself)
python3 "$ROOT/test/asus_mock/server.py" --port "$PORT" --autosubmit 2>"$TMP/server.log" &
SERVER_PID=$!
for _ in $(seq 50); do
    curl -fs -o /dev/null "$BASE/global/support/warranty-status-inquiry/" && break
    sleep 0.1
done
curl -fs -o /dev/null "$BASE/global/support/warranty-status-inquiry/" \
    || { echo "Mock server did not start:"; cat "$TMP/server.log"; exit 1; }

# run <mode> <args...>: runs warrantiak, sets $OUT, $ERR and $RC
run() {
    local mode="$1"; shift
    rm -f "$TMP/opened.txt"
    RC=0
    env -u _SERIAL_NUMBER -u _ASUS_WEBSITE -u _ASUS_DEBUG -u _JSON_OUTPUT \
        PATH="$TMP/bin:$PATH" TZ="Europe/Copenhagen" \
        _ASUS_MODE="$mode" _ASUS_HEADLESS=1 _ASUS_BASE_URL="$BASE" \
        timeout 60 "$ROOT/warrantiak" -A -j "$@" >"$TMP/out" 2>"$TMP/err" || RC=$?
    OUT="$(cat "$TMP/out")"
    ERR="$(cat "$TMP/err")"
}

# check <name> <expected rc> <python expression on the JSON object `d`>
check() {
    local name="$1" want_rc="$2" expr="$3"
    if [[ "$RC" == "$want_rc" ]] && python3 -c '
import json, sys
d = json.loads(sys.argv[1])
sys.exit(0 if eval(sys.argv[2]) else 1)' "$OUT" "$expr" 2>/dev/null; then
        echo "PASS  $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL  $name (rc=$RC, want $want_rc)"
        echo "      stdout: $OUT"
        echo "      stderr: ${ERR//$'\n'/$'\n'              }"
        FAIL=$((FAIL + 1))
    fi
}

skip() {
    echo "SKIP  $1"
    SKIP=$((SKIP + 1))
}

opened() { cat "$TMP/opened.txt" 2>/dev/null; }

# --- browser mode -----------------------------------------------------------
run browser -s 84OAAQ047369 --asus-website uk
check "browser: opens mock inquiry page with serial" 0 \
    "d['status'] == 'manual_check_required' and d['url'] == '$BASE/uk/support/warranty-status-inquiry/?sn=84OAAQ047369' and '$(opened)' == d['url']"

run browser -s 84OAAQ047369 --asus-website it
check "browser: country without inquiry page falls back to global" 0 \
    "d['url'] == '$BASE/global/support/warranty-status-inquiry/?sn=84OAAQ047369'"

# --- playwright mode --------------------------------------------------------
PLAYWRIGHT_TESTS=(
    "playwright: 84OAAQ047369 returns warranty data"
    "playwright: InNotRegion with data shows data and notice"
    "playwright: unknown serial is reported as invalid"
    "playwright: Status FAIL falls back to the default browser"
    "playwright: --asus-website it uses the global page"
)
if ! python3 -c 'import playwright.sync_api' 2>/dev/null; then
    for t in "${PLAYWRIGHT_TESTS[@]}"; do skip "$t (Python module playwright not installed)"; done
else
    run playwright -s 84OAAQ047369 --asus-website uk
    check "${PLAYWRIGHT_TESTS[0]}" 0 "d == {
        'serial': '84OAAQ047369', 'model': 'EEEPC4G-W038', 'series': 'Eee PC (System)',
        'warranty_start': '2008-04-10', 'warranty_expiration': '2010-04-09',
        'warranty_status': 'Out of Warranty', 'warranty_territory': 'SINGAPORE',
        'warranty_country': 'SG'}"

    run playwright -s MOCKNOTINREGION
    check "${PLAYWRIGHT_TESTS[1]}" 0 \
        "d['model'] == 'MOCK-MODEL-1' and d['notice'] == 'Serial number is not sold in this region'"

    run playwright -s UNKNOWN123
    check "${PLAYWRIGHT_TESTS[2]}" 2 \
        "d == {'serial': 'UNKNOWN123', 'status': 'error', 'error': 'Invalid serial number'}"

    run playwright -s MOCKFAIL --asus-website uk
    check "${PLAYWRIGHT_TESTS[3]}" 0 \
        "d['status'] == 'manual_check_required' and d['url'] == '$BASE/uk/support/warranty-status-inquiry/?sn=MOCKFAIL' and '$(opened)' == d['url']"

    run playwright -s 84OAAQ047369 --asus-website it
    check "${PLAYWRIGHT_TESTS[4]}" 0 \
        "d['model'] == 'EEEPC4G-W038' and 'NOTE' in '''$ERR'''"
fi

echo ""
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[[ "$FAIL" -eq 0 ]]

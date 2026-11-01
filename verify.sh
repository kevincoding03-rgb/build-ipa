#!/usr/bin/env bash
#  Look4Sat iOS port — compile verification script (run on macOS)
#  License: GPL-3.0
#
#  Usage:
#    cd ios_Look4Sat
#    ./verify.sh
#
#  Runs the three-layer verification:
#    1. swift build      — compiles Look4SatCore + look4sat-cli
#    2. swift test       — runs the XCTest unit test suite
#    3. swift run        — runs the CLI driver (TLE parse + pass prediction)
set -euo pipefail

cd "$(dirname "$0")"

echo "=== [1/3] swift build ==="
swift build -q
echo "build OK"

echo ""
echo "=== [2/3] swift test ==="
swift test 2>&1 | tail -n 40

echo ""
echo "=== [3/3] swift run look4sat-cli ==="
swift run look4sat-cli

echo ""
echo "All verification steps completed."

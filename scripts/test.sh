#!/bin/zsh
# Runs the tests of every package and prints a one-line total per package.
# For the tests that use a real phone:  BENZMIRROR_TEST_SERIAL=<adb serial> scripts/test.sh
set -uo pipefail

ROOT="${0:A:h:h}"
failed=0
for package in DesignSystem Core Features; do
  log="$(mktemp)"
  (cd "$ROOT/Packages/$package" && swift test > "$log" 2>&1) || failed=1
  # Counts per-test results; SwiftPM's "Executed N tests" lines are per suite and easy to misread.
  counts="$(grep -E "^Test Case '.*' (passed|failed|skipped)" "$log" | sed -E "s/.*' (passed|failed|skipped).*/\1/" | sort | uniq -c | tr -s ' ' | tr '\n' ',' )"
  total="${counts:-no results}"
  echo "== $package: $total"
  grep -E "error:|failed \(" "$log" | head -20
  rm -f "$log"
done
exit $failed

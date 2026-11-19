#!/usr/bin/env bash
# Runs the end-to-end test on the running emulator; saves logs + a screenshot on failure.
adb logcat -c || true
set -o pipefail
if flutter test integration_test/app_test.dart -d emulator-5554 --reporter expanded 2>&1 | tee e2e.txt; then
  echo "E2E passed"
else
  adb logcat -d > logcat-e2e.txt || true
  adb exec-out screencap -p > e2e-fail.png || true
  echo "::error::End-to-end test failed (see e2e-result artifact / log above)"
  exit 1
fi

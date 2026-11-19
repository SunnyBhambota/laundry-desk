#!/usr/bin/env bash
# Runs the end-to-end test (already built into app-debug.apk) on the running emulator.
adb logcat -c || true
set -o pipefail
if flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart \
    --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk -d emulator-5554 2>&1 | tee e2e.txt; then
  echo "E2E passed"
else
  adb logcat -d > logcat-e2e.txt || true
  adb exec-out screencap -p > e2e-fail.png || true
  echo "::error::End-to-end test failed (see e2e-result artifact / log above)"
  exit 1
fi

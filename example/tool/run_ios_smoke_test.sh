#!/usr/bin/env bash
set -euo pipefail

SIMULATOR_ID="${IOS_DEVICE_ID:-}"
if [[ -z "${SIMULATOR_ID}" ]]; then
  SIMULATOR_ID="$(
    flutter devices 2>/dev/null |
      awk -F '•' '/ios/ {id=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id); print id; exit}'
  )"
fi

if [[ -z "${SIMULATOR_ID}" ]]; then
  SIMULATOR_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')"
fi

if [[ -z "${SIMULATOR_ID}" ]]; then
  echo "No iOS device/simulator found. Set IOS_DEVICE_ID to override."
  exit 1
fi

if xcrun simctl list devices available | grep -q "${SIMULATOR_ID}"; then
  xcrun simctl boot "${SIMULATOR_ID}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${SIMULATOR_ID}" -b
fi

echo "Running iOS smoke test on target: ${SIMULATOR_ID}"
flutter test integration_test/smoke_test.dart -d "${SIMULATOR_ID}"

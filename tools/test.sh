#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

TEST_BINARY="${TEMP_DIR}/NotificationSweepTests"
APP_SOURCES=("${ROOT_DIR}/src/"*.m)
APP_NAME="Notification Sweep"
APP_PATH="${HOME}/Applications/${APP_NAME}.app"
APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/NotificationSweep"
MARKER="Notification Sweep Integration $(date +%s)-$$"

click_notification_center_clock() {
  osascript -e 'tell application "System Events" to tell process "ControlCenter" to click (first menu bar item of menu bar 1 whose description is "Clock")' >/dev/null
  sleep 1
}

contains_marker() {
  "${APP_EXECUTABLE}" --contains-text "${MARKER}" >/dev/null 2>&1
}

wait_until_marker_visible() {
  local attempts=10
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt += 1)); do
    click_notification_center_clock
    if contains_marker; then
      return 0
    fi
  done

  return 1
}

wait_until_marker_gone() {
  local attempts=10
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt += 1)); do
    click_notification_center_clock
    if contains_marker; then
      sleep 1
      continue
    fi

    click_notification_center_clock
    if ! contains_marker; then
      return 0
    fi

    sleep 1
  done

  return 1
}

clang -fobjc-arc \
  -Wall \
  -Wextra \
  -Werror \
  -framework AppKit \
  -framework ApplicationServices \
  "${APP_SOURCES[@]}" \
  -o "${TEST_BINARY}"

"${TEST_BINARY}" --self-test
"${ROOT_DIR}/tools/build-app.sh"

printf 'Posting real test notifications: %s\n' "${MARKER}"
"${ROOT_DIR}/tools/post-test-notifications.sh" "${MARKER}" 2

if ! wait_until_marker_visible; then
  printf 'Real notification test failed: generated notifications were not visible in Notification Center.\n' >&2
  printf 'Check that notifications are enabled for osascript/iTerm/Terminal and that Notification Sweep has Accessibility permission.\n' >&2
  exit 1
fi

printf 'Before sweep: '
"${APP_EXECUTABLE}" --count-candidates

open -W -a "${APP_PATH}"

if ! wait_until_marker_gone; then
  printf 'Real notification test failed: generated notifications were still visible after running Notification Sweep.\n' >&2
  exit 1
fi

printf 'After sweep: '
"${APP_EXECUTABLE}" --count-candidates

printf 'All tests passed\n'

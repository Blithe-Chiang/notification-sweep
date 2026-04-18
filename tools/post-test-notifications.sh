#!/usr/bin/env bash

set -euo pipefail

MARKER="${1:-Notification Sweep Manual $(date +%s)-$$}"
COUNT="${2:-2}"
SUBTITLE="notification-sweep-test"

if ! [[ "${COUNT}" =~ ^[0-9]+$ ]] || [[ "${COUNT}" -lt 1 ]]; then
  printf 'Usage: %s [marker] [count]\n' "$0" >&2
  printf 'count must be a positive integer.\n' >&2
  exit 2
fi

for ((index = 1; index <= COUNT; index += 1)); do
  NOTIFICATION_SWEEP_MARKER="${MARKER}" \
  NOTIFICATION_SWEEP_BODY="test notification ${index}" \
  NOTIFICATION_SWEEP_SUBTITLE="${SUBTITLE}" \
    osascript -e 'display notification (system attribute "NOTIFICATION_SWEEP_BODY") with title (system attribute "NOTIFICATION_SWEEP_MARKER") subtitle (system attribute "NOTIFICATION_SWEEP_SUBTITLE")'
done

printf 'Posted %s notification(s) with marker: %s\n' "${COUNT}" "${MARKER}"

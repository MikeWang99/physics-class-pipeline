#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_QUERY="$SCRIPT_DIR/query_calendar_events.swift"
ARG="${1:-1}"

attempt=1
while [ "$attempt" -le 3 ]; do
  if output="$("$SWIFT_QUERY" "$ARG" 2>&1)"; then
    printf '%s\n' "$output"
    exit 0
  fi

  if printf '%s' "$output" | grep -qi "calendar access denied"; then
    /usr/bin/open -gj -a Calendar >/dev/null 2>&1 || true
  fi

  if [ "$attempt" -lt 3 ]; then
    sleep 2
  fi
  attempt=$((attempt + 1))
done

printf '%s\n' "$output" >&2
exit 1

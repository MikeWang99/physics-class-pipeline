#!/usr/bin/env bash
# match_calendar_event.sh - find the nearest Calendar event named "{SYSTEM} Class-{STUDENT}".
#
# AppleScript returns list values as a comma-joined string, which can smear
# unrelated reminders into the student name. Build explicit line-delimited
# output instead, then choose the closest event to "now".
#
# Output: "SYSTEM|STUDENT" on stdout.
# Exit 0 if found, 1 if not found.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

KEYWORD="${CALENDAR_KEYWORD:-Class}"
TIMEOUT_SECONDS="${CALENDAR_MATCH_TIMEOUT_SECONDS:-8}"
EVENTS_FILE="$(mktemp "${TMPDIR:-/tmp}/physicsclass-events.XXXXXX")"
trap 'rm -f "$EVENTS_FILE"' EXIT

osascript - "$KEYWORD" >"$EVENTS_FILE" 2>/dev/null <<'APPLESCRIPT' &
on run argv
set keyword to item 1 of argv
set nowDate to current date
set windowStart to nowDate - 2 * days
set windowEnd to nowDate + 2 * days
set out to ""
tell application "Calendar"
  repeat with cal in calendars
    repeat with ev in (every event of cal whose start date > windowStart and start date < windowEnd and summary contains keyword)
      set delta to (start date of ev) - nowDate
      if delta < 0 then set delta to -delta
      set out to out & (delta as integer) & tab & (summary of ev as text) & linefeed
    end repeat
  end repeat
end tell
return out
end run
APPLESCRIPT
OSA_PID=$!

for _ in $(seq 1 "$TIMEOUT_SECONDS"); do
  if ! kill -0 "$OSA_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done

if kill -0 "$OSA_PID" 2>/dev/null; then
  kill "$OSA_PID" 2>/dev/null || true
  wait "$OSA_PID" 2>/dev/null || true
  exit 1
fi
wait "$OSA_PID" 2>/dev/null || true

EVENTS=$(cat "$EVENTS_FILE")

[ -n "$EVENTS" ] || exit 1

while IFS=$'\t' read -r _delta summary; do
  [ -n "${summary:-}" ] || continue
  if printf '%s\n' "$summary" | grep -qiE "${KEYWORD}[[:space:]]*[-－—]"; then
    SYSTEM=$(printf '%s\n' "$summary" | sed -E "s/[[:space:]]*${KEYWORD}[[:space:]]*[-－—].*//I" | xargs)
    STUDENT=$(printf '%s\n' "$summary" | sed -E "s/.*${KEYWORD}[[:space:]]*[-－—][[:space:]]*//I" | xargs)
    [ -n "$SYSTEM" ] || SYSTEM="未命名体系"
    [ -n "$STUDENT" ] || continue
    printf '%s|%s\n' "$SYSTEM" "$STUDENT"
    exit 0
  fi
done < <(printf '%s\n' "$EVENTS" | sort -n)

exit 1

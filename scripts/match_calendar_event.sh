#!/usr/bin/env bash
# match_calendar_event.sh - find a Class event in calendar within +/- 2 days
# Output: "SYSTEM|STUDENT" on stdout, empty if no match
# Exit 0 if found, 1 if not found
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

EVENTS=$(osascript -e '
  set now to current date
  set evs to {}
  tell application "Calendar"
    repeat with cal in calendars
      repeat with ev in (every event of cal whose start date > (now - 2*days) and start date < (now + 2*days))
        set end of evs to summary of ev
      end repeat
    end repeat
  end tell
  return evs
' 2>/dev/null || true)

while IFS= read -r line; do
  [ -z "$line" ] && continue
  if echo "$line" | grep -qiE 'class\s*[-－—]'; then
    SYSTEM=$(echo "$line" | sed -E 's/[[:space:]]*class[[:space:]]*[-－—].*//i' | xargs)
    STUDENT=$(echo "$line" | sed -E 's/.*class[[:space:]]*[-－—][[:space:]]*//i' | xargs)
    echo "${SYSTEM}|${STUDENT}"
    exit 0
  fi
done <<< "$EVENTS"

exit 1

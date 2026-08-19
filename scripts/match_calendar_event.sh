#!/usr/bin/env bash
# match_calendar_event.sh - find the nearest Calendar event named "{SYSTEM} Class-{STUDENT}".
#
# Uses the same EventKit-backed query path as preclass_scan.py so prep scanning
# and post-class matching read from one data source.
#
# Output: "SYSTEM|STUDENT" on stdout.
# Exit 0 if found, 1 if not found.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

KEYWORD="${CALENDAR_KEYWORD:-Class}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUERY_SCRIPT="$SCRIPT_DIR/query_calendar_events.swift"

SESSION_ARG="${1:-}"
REF_Y=""
REF_M=""
REF_D=""
REF_H=""
REF_MIN=""
REF_S=""

if [ -n "$SESSION_ARG" ] && [ -d "$SESSION_ARG" ]; then
  BASE="$(basename "$SESSION_ARG")"
  if printf '%s' "$BASE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}$'; then
    REF_Y="${BASE:0:4}"
    REF_M="${BASE:5:2}"
    REF_D="${BASE:8:2}"
    REF_H="${BASE:11:2}"
    REF_MIN="${BASE:13:2}"
    REF_S="${BASE:15:2}"
  fi
fi

if [ -z "$REF_Y" ]; then
  REF_Y="$(date '+%Y')"
  REF_M="$(date '+%m')"
  REF_D="$(date '+%d')"
  REF_H="$(date '+%H')"
  REF_MIN="$(date '+%M')"
  REF_S="$(date '+%S')"
fi

REF_DATE="${REF_Y}-${REF_M}-${REF_D}"
REF_ISO="${REF_DATE}T${REF_H}:${REF_MIN}:${REF_S}"

EVENTS="$("$QUERY_SCRIPT" "$REF_DATE" 2>/dev/null)" || exit 1
[ -n "$EVENTS" ] || exit 1

BEST_SYSTEM=""
BEST_STUDENT=""
BEST_DELTA=""

while IFS=$'\t' read -r summary start_iso _notes; do
  [ -n "${summary:-}" ] || continue
  if ! printf '%s\n' "$summary" | grep -qiE "${KEYWORD}[[:space:]]*[-－—]"; then
    continue
  fi

  DELTA=$(python3 - "$REF_ISO" "$start_iso" <<'PY'
import sys
from datetime import datetime

ref = datetime.fromisoformat(sys.argv[1]).replace(
    tzinfo=datetime.now().astimezone().tzinfo
)
start = datetime.fromisoformat(sys.argv[2])
print(int(abs((start - ref).total_seconds())))
PY
) || continue

  SYSTEM=$(printf '%s\n' "$summary" | sed -E "s/[[:space:]]*${KEYWORD}[[:space:]]*[-－—].*//I" | xargs)
  STUDENT=$(printf '%s\n' "$summary" | sed -E "s/.*${KEYWORD}[[:space:]]*[-－—][[:space:]]*//I" | xargs)
  [ -n "$SYSTEM" ] || SYSTEM="未命名体系"
  [ -n "$STUDENT" ] || continue

  if [ -z "$BEST_DELTA" ] || [ "$DELTA" -lt "$BEST_DELTA" ]; then
    BEST_DELTA="$DELTA"
    BEST_SYSTEM="$SYSTEM"
    BEST_STUDENT="$STUDENT"
  fi
done < <(printf '%s\n' "$EVENTS")

[ -n "$BEST_STUDENT" ] || exit 1
printf '%s|%s\n' "$BEST_SYSTEM" "$BEST_STUDENT"

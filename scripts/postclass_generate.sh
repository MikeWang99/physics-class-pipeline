#!/usr/bin/env bash
# postclass_generate.sh - auto-generate post-class feedback after transcription
# Usage: postclass_generate.sh <session_dir> <vault_path>
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SESSION_DIR="$1"
VAULT_PATH="$2"
TRANSCRIPT="$SESSION_DIR/transcript.txt"
[ -f "$TRANSCRIPT" ] || { echo "no transcript: $TRANSCRIPT"; exit 1; }

# Match student from calendar events (today +/- 2 days, containing "Class")
STUDENT="unknown"
SYSTEM="unknown"
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
  if echo "$line" | grep -qiE 'class\s*[-]'; then
    SYSTEM=$(echo "$line" | sed -E 's/[[:space:]]*class[[:space:]]*[-].*//i' | xargs)
    STUDENT=$(echo "$line" | sed -E 's/.*class[[:space:]]*[-][[:space:]]*//i' | xargs)
    break
  fi
done <<< "$EVENTS"

CONTENT=$(head -c 8000 "$TRANSCRIPT")
DATE=$(date '+%Y-%m-%d')

# Detect proxy
PROXY=""
for var in https_proxy HTTPS_PROXY http_proxy HTTP_PROXY all_proxy; do
  [ -n "${!var:-}" ] && { PROXY="${!var}"; break; }
done
if [ -z "$PROXY" ]; then
  PROXY=$(scutil --proxy 2>/dev/null | awk '
    /HTTPSEnable|HTTPEnable/{e=$3}
    /HTTPSProxy|HTTPProxy/{if(!h)h=$3}
    /HTTPSPort|HTTPPort/{if(!p)p=$3}
    END{if(e==1 && h && p) print "http://"h":"p}')
fi

# Read API key
GROQ_API_KEY="${GROQ_API_KEY:-}"
if [ -z "$GROQ_API_KEY" ] && [ -f "$HOME/.zshrc" ]; then
  GROQ_API_KEY=$(grep -E '^[[:space:]]*(export[[:space:]]+)?GROQ_API_KEY=' "$HOME/.zshrc" | tail -1 | sed -E 's/^[^=]*=[[:space:]]*//; s/^["'"'"']+//; s/["'"'"']+$//')
fi
[ -z "$GROQ_API_KEY" ] && { echo "GROQ_API_KEY not found"; exit 1; }

# Build prompt
PROMPT="You are an experienced physics teacher. Based on the following class transcript, generate a concise post-class feedback in Chinese for the student, including:
1. Class topic (one sentence)
2. Student strengths (2-3 points)
3. Areas for improvement (1-2 points)
4. Suggested homework direction (1-2 specific suggestions)

Student: $STUDENT
Course system: $SYSTEM
Transcript:
$CONTENT

Output format: Markdown with title '# Post-class Feedback - $STUDENT - $DATE', 300-500 Chinese characters total."

# Build JSON payload via python3
PAYLOAD=$(echo "$PROMPT" | python3 -c "
import json, sys
prompt = sys.stdin.read()
print(json.dumps({'model':'llama-3.1-8b-instant','messages':[{'role':'user','content':prompt}],'temperature':0.7,'max_tokens':1024}))
")

# Call Groq
CURL_ARGS=(-s --max-time 120 https://api.groq.com/openai/v1/chat/completions
  -H "Authorization: Bearer $GROQ_API_KEY"
  -H "Content-Type: application/json"
  -d "$PAYLOAD")
[ -n "$PROXY" ] && CURL_ARGS+=(-x "$PROXY")

RESPONSE=$(curl "${CURL_ARGS[@]}")
FEEDBACK=$(echo "$RESPONSE" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["choices"][0]["message"]["content"])' 2>/dev/null)
[ -z "$FEEDBACK" ] && { echo "Groq parse failed: ${RESPONSE:0:200}"; exit 1; }

# Write to Vault
FEEDBACK_DIR="$VAULT_PATH/上课记录/课后反馈"
mkdir -p "$FEEDBACK_DIR"
OUTFILE="$FEEDBACK_DIR/${DATE}-${STUDENT}-feedback.md"
echo "$FEEDBACK" > "$OUTFILE"
echo "$OUTFILE"

#!/bin/bash
# meeting_watcher.sh — resident meeting detector + auto recorder + auto transcriber.
#
# Loops every 15s. When a meeting app is detected it starts recording
# (BlackHole + microphone). When the meeting has been gone for 3 consecutive
# checks (~45s) it stops recording, transcribes via Groq Whisper and posts a
# macOS notification.
#
# Usage:
#   bash meeting_watcher.sh          # daemon loop (used by launchd)
#   bash meeting_watcher.sh once     # record one session manually (Ctrl-C to stop)
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG="$SKILL_DIR/config.json"
INTERVAL=15
MISS_LIMIT=3   # 3 x 15s without meeting => class over

cfg() { python3 -c "import json,os;print(json.load(open('$CONFIG')).get('$1','$2'))" 2>/dev/null || echo "$2"; }

if [ ! -f "$CONFIG" ]; then
  echo "config.json missing — run setup.sh first" >&2
  exit 1
fi
RECORD_DIR="$(cfg recordings_dir "$HOME/physics-class-pipeline-data")"
RECORD_DIR="${RECORD_DIR/#\~/$HOME}"
LOG_DIR="$RECORD_DIR/logs"
mkdir -p "$RECORD_DIR/sessions" "$LOG_DIR"
LOG="$LOG_DIR/watcher.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
notify() {
  osascript -e "display notification \"$2\" with title \"Physics Class Pipeline\"" 2>/dev/null || true
  log "NOTIFY: $1"
}

# ---------- audio device lookup ----------
# launchd/background processes cannot see microphone devices until macOS grants
# mic access to the responsible app. Actually opening a capture stream triggers
# the system permission prompt, so try a 1-second capture; user approves once.
mic_permission() {
  local stamp="$LOG_DIR/.mic_perm_ok"
  if [ -f "$stamp" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$(date '+%Y-%m-%d')" ]; then return 0; fi
  ffmpeg -hide_banner -loglevel error -f avfoundation -i ":0" -t 1 -f null - >/dev/null 2>&1
  echo "$(date '+%Y-%m-%d')" > "$stamp"
}

# one-shot self test at startup; setup.sh polls the log for these lines
perm_selftest() {
  if ffmpeg -hide_banner -loglevel error -f avfoundation -i ":0" -t 1 -f null - >/dev/null 2>&1; then
    log "MIC PERMISSION: granted"
  else
    log "MIC PERMISSION: missing (waiting for user to click Allow in the system dialog)"
  fi
}

# prints "blackhole_index mic_index" from ffmpeg avfoundation device list
audio_indices() {
  local listing bh mic
  listing=$(ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1)
  bh=$(echo "$listing" | grep -i "blackhole" | head -1 | grep -o '\[[0-9]*\]' | head -1 | tr -d '[]')
  mic=$(echo "$listing" | awk '/AVFoundation audio devices/{f=1} f' | grep -iE "microphone|麦克风" | head -1 | grep -o '\[[0-9]*\]' | head -1 | tr -d '[]')
  echo "${bh:-NONE} ${mic:-NONE}"
}

# ---------- meeting detection ----------
meeting_running() {
  # native apps (process name match)
  if pgrep -qi "zoom\.us" || pgrep -qi "wemeetapp" || pgrep -qi "xmeet" \
     || pgrep -qi "DingTalk" || pgrep -qi "Lark" || pgrep -qi "Feishu" \
     || pgrep -qi "TencentMeeting"; then
    echo "native-app"
    return 0
  fi
  # Google Meet in Chrome / Safari (tab URL match)
  local urls=""
  urls=$(osascript -e 'tell application "System Events"
    set out to ""
    if (name of processes) contains "Google Chrome" then
      tell application "Google Chrome"
        repeat with w in windows
          repeat with t in tabs of w
            set out to out & (URL of t) & linefeed
          end repeat
        end repeat
      end tell
    end if
    return out
  end tell' 2>/dev/null)
  if echo "$urls" | grep -q "meet.google.com"; then
    echo "google-meet"
    return 0
  fi
  urls=$(osascript -e 'tell application "System Events"
    if (name of processes) contains "Safari" then
      tell application "Safari"
        set out to ""
        repeat with w in windows
          repeat with t in tabs of w
            set out to out & (URL of t) & linefeed
          end repeat
        end repeat
        return out
      end tell
    end if
    return ""
  end tell' 2>/dev/null)
  if echo "$urls" | grep -q "meet.google.com"; then
    echo "google-meet"
    return 0
  fi
  return 1
}

# ---------- recording ----------
SESSION=""
FFPID=""

start_recording() {
  local platform="$1"
  mic_permission
  read -r BH MIC <<< "$(audio_indices)"
  local inputs=() filters=() n=0
  if [ "$BH" != "NONE" ]; then inputs+=(-f avfoundation -i ":$BH"); filters+=("[$n:a]"); n=$((n+1)); else log "WARNING: BlackHole not found, recording mic only"; fi
  if [ "$MIC" != "NONE" ]; then inputs+=(-f avfoundation -i ":$MIC"); filters+=("[$n:a]"); n=$((n+1)); fi
  if [ "$n" -eq 0 ]; then
    log "ERROR: no audio input available (microphone permission likely missing)"
    notify "no-input" "检测到开会但无可用音频输入：请授权麦克风（系统设置→隐私与安全性→麦克风，添加 ffmpeg 或 bash），录音将在下次检测重试"
    return 1
  fi
  SESSION="$RECORD_DIR/sessions/$(date '+%Y-%m-%d_%H%M')"
  mkdir -p "$SESSION"
  echo "$platform" > "$SESSION/platform.txt"
  local mix
  if [ "$n" -eq 1 ]; then mix="${filters[0]}acopy"
  else mix="$(IFS=; echo "${filters[*]}")amix=inputs=$n:duration=longest"; fi
  ffmpeg -hide_banner -loglevel error "${inputs[@]}" \
    -filter_complex "$mix" -ac 1 -ar 44100 -c:a pcm_s16le \
    "$SESSION/audio.wav" >> "$LOG" 2>&1 &
  FFPID=$!
  log "RECORDING started (pid $FFPID, platform=$platform, session=$SESSION, bh=$BH mic=$MIC)"
  notify "recording" "检测到开课（$platform），录音已开始"
  # route system output through the multi-output device if available
  bash "$SCRIPT_DIR/setup_audio.sh" activate >> "$LOG" 2>&1 || true
}

stop_recording() {
  [ -z "$FFPID" ] && return
  kill -INT "$FFPID" 2>/dev/null
  wait "$FFPID" 2>/dev/null
  log "RECORDING stopped (session=$SESSION)"
  bash "$SCRIPT_DIR/setup_audio.sh" restore >> "$LOG" 2>&1 || true
  transcribe_session "$SESSION"
  FFPID=""; SESSION=""
}

transcribe_session() {
  local dir="$1"
  [ -f "$dir/audio.wav" ] || { log "no audio.wav in $dir"; return; }
  local size
  size=$(stat -f%z "$dir/audio.wav" 2>/dev/null || echo 0)
  if [ "$size" -lt 100000 ]; then log "audio too small ($size bytes), skipping transcription"; notify "skip" "录音文件过小，跳过转写"; return; fi
  notify "transcribing" "会议结束，正在转写文字稿…"
  # pick up GROQ_API_KEY from user shell config if not in env
  if [ -z "${GROQ_API_KEY:-}" ] && [ -f "$HOME/.zshrc" ]; then
    export GROQ_API_KEY="$(grep -o 'GROQ_API_KEY[="'"'"' ]*[A-Za-z0-9_-]*' "$HOME/.zshrc" | tail -1 | sed 's/.*[='"'"' ]//')"
  fi
  if python3 "$SCRIPT_DIR/transcribe_audio.py" "$dir/audio.wav" "$dir" >> "$LOG" 2>&1; then
    notify "done" "转写完成 ✅ 在 AI 助手里说「下课」生成课后产出"
  else
    notify "transcribe-failed" "转写失败，查看日志：$LOG"
  fi
}

# ---------- modes ----------
if [ "${1:-}" = "once" ]; then
  echo "Manual recording — press Ctrl-C when class ends."
  start_recording "manual" || exit 1
  trap 'stop_recording; exit 0' INT TERM
  while true; do sleep 5; done
fi

# daemon loop
log "watcher started (pid $$)"
perm_selftest
miss=0
while true; do
  platform=$(meeting_running) && in_meeting=1 || in_meeting=0
  if [ "$in_meeting" = 1 ]; then
    miss=0
    [ -z "$FFPID" ] && start_recording "$platform"
  else
    if [ -n "$FFPID" ]; then
      miss=$((miss+1))
      if [ "$miss" -ge "$MISS_LIMIT" ]; then stop_recording; fi
    fi
  fi
  sleep "$INTERVAL"
done

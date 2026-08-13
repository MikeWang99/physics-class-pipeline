#!/bin/bash
# setup.sh — one-command closed-loop installer for physics-class-pipeline.
#
# Steps:
#   1. dependency check (brew / ffmpeg / python3 / swift)
#   2. install BlackHole 2ch virtual audio device + create multi-output device
#   3. detect Obsidian vault (search common locations, take first .obsidian dir)
#   4. check GROQ_API_KEY
#   5. write config.json
#   6. register two launchd jobs: daily pre-class scan + resident meeting watcher
#   7. link the skill into ~/.qoder/skills and ~/.codex/skills
#
# Re-running is safe (idempotent). Uninstall with uninstall.sh.
set -u

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_SCAN="$HOME/Library/LaunchAgents/com.physicsclass.preclass-scan.plist"
PLIST_WATCH="$HOME/Library/LaunchAgents/com.physicsclass.meeting-watcher.plist"
DATA_DIR="$HOME/physics-class-pipeline-data"
SCAN_HOUR=10
SCAN_MINUTE=0

ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; }
fail() { echo "  ❌ $*"; }
step() { echo; echo "==> $*"; }

# ---------- 1. dependencies ----------
step "1/7 依赖检查"
MISSING=()
for tool in brew ffmpeg python3 swift osascript; do
  if command -v "$tool" >/dev/null 2>&1; then ok "$tool: $(command -v "$tool")"
  else MISSING+=("$tool"); fail "$tool 未安装"; fi
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  fail "请先安装缺失依赖（brew install ffmpeg 等）后重跑本脚本"; exit 1
fi

# ---------- 2. audio chain ----------
step "2/7 音频链路（BlackHole + 多输出设备）"
bash "$SKILL_DIR/scripts/setup_audio.sh" install || warn "音频链路安装未完成，可稍后运行 scripts/setup_audio.sh install 补齐"

# ---------- 3. vault detection ----------
step "3/7 探测 Obsidian Vault"
VAULT=""
CANDIDATES=()
while IFS= read -r d; do CANDIDATES+=("$d"); done < <(
  find "$HOME/Documents" "$HOME/Desktop" "$HOME/Library/Mobile Documents" \
       -maxdepth 5 -name ".obsidian" -type d 2>/dev/null | head -3)
if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  fail "未找到 Obsidian Vault（含 .obsidian 目录）。请手动创建后编辑 config.json 的 vault_path。"
else
  VAULT="$(dirname "${CANDIDATES[0]}")"
  ok "Vault: $VAULT"
fi

# ---------- 4. GROQ key ----------
step "4/7 GROQ_API_KEY 检查"
if [ -n "${GROQ_API_KEY:-}" ]; then
  ok "环境变量已设置"
elif grep -q "GROQ_API_KEY" "$HOME/.zshrc" 2>/dev/null; then
  ok "已在 ~/.zshrc 中找到（转写脚本会自动读取）"
else
  warn "未找到 GROQ_API_KEY。转写功能需要它：https://console.groq.com/keys 免费申请后写入 ~/.zshrc"
fi

# ---------- 5. config.json ----------
step "5/7 写入 config.json"
python3 - "$SKILL_DIR" "$VAULT" "$DATA_DIR" "$SCAN_HOUR" "$SCAN_MINUTE" <<'PYEOF'
import json, sys
skill_dir, vault, data_dir, hour, minute = sys.argv[1:6]
cfg = {
    "vault_path": vault,
    "recordings_dir": data_dir,
    "calendar_keyword": "Class",
    "scan_hour": int(hour),
    "scan_minute": int(minute),
}
with open(f"{skill_dir}/config.json", "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
print("  written:", f"{skill_dir}/config.json")
PYEOF
mkdir -p "$DATA_DIR/sessions" "$DATA_DIR/logs"
# note folders in vault (Obsidian creates on demand, but pre-create for clarity)
if [ -n "$VAULT" ]; then
  mkdir -p "$VAULT/上课记录/备课内容" "$VAULT/上课记录/课堂文字稿" \
           "$VAULT/上课记录/课后反馈" "$VAULT/上课记录/学生档案"
  ok "Vault 笔记分区已就绪：上课记录/{备课内容,课堂文字稿,课后反馈,学生档案}"
fi

# ---------- 6. launchd jobs ----------
step "6/7 注册 launchd 定时任务"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_SCAN" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.physicsclass.preclass-scan</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/python3</string>
    <string>$SKILL_DIR/scripts/preclass_scan.py</string>
  </array>
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>$SCAN_HOUR</integer>
    <key>Minute</key><integer>$SCAN_MINUTE</integer>
  </dict>
  <key>StandardOutPath</key><string>$DATA_DIR/logs/preclass-scan.log</string>
  <key>StandardErrorPath</key><string>$DATA_DIR/logs/preclass-scan.log</string>
</dict></plist>
EOF

cat > "$PLIST_WATCH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.physicsclass.meeting-watcher</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string>
    <string>$SKILL_DIR/scripts/meeting_watcher.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$DATA_DIR/logs/watcher-stdout.log</string>
  <key>StandardErrorPath</key><string>$DATA_DIR/logs/watcher-stderr.log</string>
</dict></plist>
EOF

launchctl unload "$PLIST_SCAN" 2>/dev/null; launchctl load "$PLIST_SCAN"
launchctl unload "$PLIST_WATCH" 2>/dev/null; launchctl load "$PLIST_WATCH"
ok "每日 $SCAN_HOUR:${SCAN_MINUTE}0 课前扫描（com.physicsclass.preclass-scan）"
ok "常驻会议监听（com.physicsclass.meeting-watcher）"

# ---------- 7. skill install ----------
step "7/7 安装 skill 到 AI 助手"
for dest in "$HOME/.qoder/skills" "$HOME/.codex/skills"; do
  mkdir -p "$dest"
  ln -sfn "$SKILL_DIR" "$dest/physics-class-pipeline"
  ok "$dest/physics-class-pipeline -> $SKILL_DIR"
done

echo
echo "================ 安装完成 ================"
echo "  config.json : $SKILL_DIR/config.json"
echo "  录音目录    : $DATA_DIR"
echo "  日志        : $DATA_DIR/logs/"
echo "  卸载        : bash $SKILL_DIR/uninstall.sh"
echo "=========================================="
echo "下一步：在 AI 助手里说「备课」补全明天的备课内容，或直接开会测试自动录音。"

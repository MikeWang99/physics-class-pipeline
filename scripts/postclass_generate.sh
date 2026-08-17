#!/usr/bin/env bash
# postclass_generate.sh - auto-generate post-class feedback after transcription
# Usage: postclass_generate.sh <session_dir> <vault_path>
# Exit 0: success, 1: error, 2: no calendar match (skip feedback)
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if [ "$#" -lt 2 ]; then
  echo "Usage: postclass_generate.sh <session_dir> <vault_path> [system student]" >&2
  exit 1
fi

SESSION_DIR="$1"
VAULT_PATH="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRANSCRIPT="$SESSION_DIR/transcript.txt"
[ -f "$TRANSCRIPT" ] || { echo "no transcript: $TRANSCRIPT"; exit 1; }

# Match student from the watcher-provided calendar event when available. Falling
# back keeps the script usable when run by hand.
if [ -n "${3:-}" ] && [ -n "${4:-}" ]; then
  SYSTEM="$3"
  STUDENT="$4"
else
  MATCH=$("$SCRIPT_DIR/match_calendar_event.sh" "$SESSION_DIR" 2>/dev/null) || { echo "no calendar match, skipping feedback"; exit 2; }
  SYSTEM="${MATCH%%|*}"
  STUDENT="${MATCH##*|}"
fi
[ -z "$STUDENT" ] && { echo "empty student name"; exit 2; }

# 日历标题可能被污染（含无关文字），只取第一段并去掉首尾空白
STUDENT_CLEAN=$(printf '%s' "$STUDENT" | cut -d',' -f1 | xargs)
[ -z "$STUDENT_CLEAN" ] && STUDENT_CLEAN="$STUDENT"

# 在 Vault 学生档案里模糊匹配真实学生名（档案是台账，优先）
PROFILE=""
PROFILE_DIR="$VAULT_PATH/上课记录/学生档案"
if [ -d "$PROFILE_DIR" ]; then
  for f in "$PROFILE_DIR"/*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .md)
    base_lower=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
    clean_lower=$(printf '%s' "$STUDENT_CLEAN" | tr '[:upper:]' '[:lower:]')
    case "$clean_lower" in
      *"$base_lower"*|"$base_lower"*) STUDENT_CLEAN="$base"; PROFILE="$f"; break ;;
    esac
  done
  # 前缀匹配兜底：Julien -> Julian
  if [ -z "$PROFILE" ]; then
    for f in "$PROFILE_DIR"/*.md; do
      [ -f "$f" ] || continue
      base=$(basename "$f" .md)
      prefix=$(printf '%s' "$STUDENT_CLEAN" | cut -c1-4)
      case "$base" in
        "$prefix"*) STUDENT_CLEAN="$base"; PROFILE="$f"; break ;;
      esac
    done
  fi
fi
STUDENT="$STUDENT_CLEAN"

# 文字稿截取：TPM 限额内取头部 8000 + 尾部 4000（长课的结尾总结/作业布置在尾部）
CONTENT=$( { head -c 8000 "$TRANSCRIPT"; printf '\n…（中段省略）…\n'; tail -c 4000 "$TRANSCRIPT"; } )
DATE=$(date '+%Y-%m-%d')

# 读取学生档案与最近一次反馈（保持问题跟踪连续性）
PROFILE_TEXT=""
[ -n "$PROFILE" ] && PROFILE_TEXT=$(head -c 4000 "$PROFILE")
PREV_FEEDBACK=""
PREV_FILE=$(ls -t "$VAULT_PATH/上课记录/课后反馈/"*-"$STUDENT"-feedback.md 2>/dev/null | head -1)
[ -n "$PREV_FILE" ] && PREV_FEEDBACK=$(head -c 2500 "$PREV_FILE")

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

# 反馈写作规范紧凑版（Groq 免费档 TPM 限额内）；完整规范见 docs/feedback-spec.md
FEEDBACK_SPEC_FILE="$SCRIPT_DIR/../docs/feedback-spec.md"
if [ -f "$FEEDBACK_SPEC_FILE" ]; then
  FEEDBACK_SPEC="篇幅 350-550 字。第一行固定「本节课反馈：」。四个「」标题之间空一行：
「1. 本节课内容」：1-3 个 bullet，格式 - **模块名**：一句说明，不写开场白。
「2. 本节课进步」：按能力模块组织（一、二…），每模块 1-3 个 bullet，只写有前后变化证据的进步，提示后完成要写明；结尾一句「阶段判断：」。
「3. 当前待解决问题」：最多 2 条 bullet，格式 - **<问题概括>**（本节课新增）：一句话描述 / - **<问题概括>**（历史问题）：一句话描述现状。标签只有这两种；冒号后一句话概括，不展开课堂细节（不写具体数值、改错过程）；本节不写解决方案。
「4. 下一步计划」：「过去的问题：」一句话说明哪些老问题还在跟踪；「下节课安排：」bullet 最多 5 条，每条是针对第 3 节问题的解决方案（练什么/怎么练/怎么检查）或具体教学安排。
硬性规则：只基于文字稿证据，不编造；第一人称「我」，面向不懂物理的家长；问题概括用温和准确的语言（禁：基础很差/粗心/完全不会）；禁用空话（继续加强/多做练习/巩固基础）；老问题与学生档案用词一致，不许凭空消失。"
else
  # 兜底：规范文件丢失时的最小规则集
  FEEDBACK_SPEC="四段式输出：「1. 本节课内容」「2. 本节课进步」（按能力模块 bullet + 阶段判断）「3. 当前待解决问题」（最多两条 bullet：问题概括 +（本节课新增/历史问题）标签 + 一句话描述）「4. 下一步计划」（过去的问题一句话 + 下节课安排 bullet，解决方案放在这里）。第一行必须是：本节课反馈：篇幅 350-550 字，只基于文字稿证据，问题跟踪与学生档案保持用词一致。"
fi

# Build prompt - 注入完整反馈写作规范（docs/feedback-spec.md）
PROMPT="你是一位物理老师，要给家长写课后反馈。严格遵循以下规范：

【完整写作规范】
$FEEDBACK_SPEC

补充说明：
- 文字稿是语音识别自动生成的，可能有错误和碎片，善意解读但不要添加内容
- 如果信息不足以判断，写「本节课未出现新的明显表现，继续观察」而不是猜测
- 新问题只有文字稿中有清晰、可重复的证据才能标（本节课新增），一次性失误不新增

学生：$STUDENT
课程体系：$SYSTEM
日期：$DATE

【学生档案】
$PROFILE_TEXT

【上次课后反馈（保持连续性参考）】
$PREV_FEEDBACK

【本节课文字稿】
$CONTENT"

# Build JSON payload via python3
PAYLOAD=$(echo "$PROMPT" | python3 -c "
import json, sys
prompt = sys.stdin.read()
print(json.dumps({'model':'llama-3.3-70b-versatile','messages':[{'role':'user','content':prompt}],'temperature':0.4,'max_tokens':2048}))
")

# Call Groq
CURL_ARGS=(-s --max-time 120 https://api.groq.com/openai/v1/chat/completions
  -H "Authorization: Bearer $GROQ_API_KEY"
  -H "Content-Type: application/json"
  -d "$PAYLOAD")
[ -n "$PROXY" ] && CURL_ARGS+=(-x "$PROXY")

# 限流重试：Groq TPM 限额，遇 429/rate limit 等 65 秒重试，最多 3 次
FEEDBACK=""
for attempt in 1 2 3; do
  RESPONSE=$(curl "${CURL_ARGS[@]}")
  FEEDBACK=$(echo "$RESPONSE" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["choices"][0]["message"]["content"])' 2>/dev/null)
  [ -n "$FEEDBACK" ] && break
  if echo "$RESPONSE" | grep -q 'rate_limit\|429\|tokens per minute'; then
    echo "rate limited, retry in 65s (attempt $attempt/3)..."
    sleep 65
  else
    break
  fi
done
[ -z "$FEEDBACK" ] && { echo "Groq parse failed: ${RESPONSE:0:200}"; exit 1; }

# Write to Vault
FEEDBACK_DIR="$VAULT_PATH/上课记录/课后反馈"
mkdir -p "$FEEDBACK_DIR"
OUTFILE="$FEEDBACK_DIR/${DATE}-${STUDENT}-feedback.md"
echo "$FEEDBACK" > "$OUTFILE"
echo "$OUTFILE"

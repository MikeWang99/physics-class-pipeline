#!/usr/bin/env bash
# postclass_generate.sh - auto-generate post-class feedback after transcription
# Usage: postclass_generate.sh <session_dir> <vault_path>
# Exit 0: success, 1: error, 2: no calendar match (skip feedback)
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SESSION_DIR="$1"
VAULT_PATH="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRANSCRIPT="$SESSION_DIR/transcript.txt"
[ -f "$TRANSCRIPT" ] || { echo "no transcript: $TRANSCRIPT"; exit 1; }

# Match student from calendar
MATCH=$("$SCRIPT_DIR/match_calendar_event.sh" 2>/dev/null) || { echo "no calendar match, skipping feedback"; exit 2; }
SYSTEM="${MATCH%%|*}"
STUDENT="${MATCH##*|}"
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

# 取文字稿更多内容（8000 字符会漏掉后半节课）
CONTENT=$(head -c 20000 "$TRANSCRIPT")
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

# Build prompt - parent-lesson-feedback skill 四段式规范
PROMPT="你是一位物理老师，要给家长写课后反馈。严格遵循以下规范：

【核心原则】
- 反馈是给家长的合理确定性，不是课堂流水账
- 只包含文字稿中明确出现的内容，不许编造课堂细节
- 文字稿是语音识别自动生成的，可能有错误和碎片，善意解读但不要添加内容
- 如果信息不足以判断，写「本节课未出现新的明显表现，继续观察」而不是猜测

【问题跟踪连续性】
- 学生档案和上次反馈里跟踪的老问题必须保持用词一致，不许重新诊断改名
- 老问题不能凭空消失：最重要的 1-2 个放进「暴露问题」，其余在「下一步计划-过去的问题」里提及
- 新问题只有文字稿中有清晰、可重复的证据才能标（新增），一次性失误不新增
- 阶段标签（新增/好转中/稳定）依据本次课证据推进或维持

【输出格式】（严格遵守）
第一行必须是：本节课反馈：
然后用四个「」标题，标题之间空一行：
「1. 本节课内容」- 讲清主题和目的，2-4 个要点，不列公式清单
「2. 本节课进步」- 用 提升表现：/具体例子：/阶段判断： 三行，每个进步必须有课堂实例支撑
「3. 孩子本节课暴露问题」- 最多两条，每条用 一：<问题概括>（<阶段>）+ 本节课表现：+ 我的判断：
「4. 下一步计划」- 两段式：过去的问题：（老问题+整体思路）/ 下节课安排：（具体安排）/ 其他安排：（可选）

【写作规则】
- 第一人称「我」，面向不懂物理的家长，总篇幅 400-600 字
- 不用「继续加强」「多做练习」等空话，每个安排必须具体
- 问题描述不贴孩子标签，用「掌握尚不稳定」「在提示下可以完成」这类表述

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

RESPONSE=$(curl "${CURL_ARGS[@]}")
FEEDBACK=$(echo "$RESPONSE" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["choices"][0]["message"]["content"])' 2>/dev/null)
[ -z "$FEEDBACK" ] && { echo "Groq parse failed: ${RESPONSE:0:200}"; exit 1; }

# Write to Vault
FEEDBACK_DIR="$VAULT_PATH/上课记录/课后反馈"
mkdir -p "$FEEDBACK_DIR"
OUTFILE="$FEEDBACK_DIR/${DATE}-${STUDENT}-feedback.md"
echo "$FEEDBACK" > "$OUTFILE"
echo "$OUTFILE"

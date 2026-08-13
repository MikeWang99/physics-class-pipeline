#!/usr/bin/env python3
"""preclass_scan.py — 扫描明天苹果日历中的课程事件，自动生成完整备课笔记。

日历事件格式：`{体系} Class-{学生名}`（含关键词 Class，默认大小写不敏感匹配）。
为每节课在 {vault}/上课记录/备课内容/ 下生成备课笔记，自动嵌入：
  - 学生档案摘要（学生档案/{学生}.md 的基本信息/当前进度/主要问题）
  - 最近一次课后反馈（课后反馈/ 下该学生最新一篇）
  - 上一次备课/课次线索
  - 调用 Groq API 自动生成教学目标、流程、关键题目、预判卡点。
已存在同名笔记则跳过（幂等，可重复运行）。完成后发 macOS 通知。
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
CONFIG = SKILL_DIR / "config.json"
PLACEHOLDER = "> AI 生成中..."

APPLESCRIPT = """
set t to (current date) + 1 * days
set time of t to 0
set tEnd to t + 1 * days
tell application "Calendar"
    set out to ""
    repeat with c in calendars
        repeat with e in (events of c whose start date >= t and start date < tEnd)
            set out to out & (summary of e) & tab & ((start date of e) as string) & tab & (description of e) & linefeed
        end repeat
    end repeat
    return out
end tell
"""


def load_config() -> dict:
    if not CONFIG.exists():
        sys.exit("config.json 不存在，请先运行 setup.sh")
    return json.loads(CONFIG.read_text(encoding="utf-8"))


def parse_event(summary: str, keyword: str):
    """从 '体系 Class-学生' 提取 (体系, 学生)。"""
    m = re.search(rf"^(.*?)\s*{re.escape(keyword)}\s*[-－—]\s*(.+)$", summary.strip(), re.IGNORECASE)
    if m:
        return m.group(1).strip() or "未命名体系", m.group(2).strip()
    if keyword.lower() in summary.lower():
        return "未命名体系", summary.replace(keyword, "").strip("- –—·").strip()
    return None


def read_head(path: Path, max_lines: int = 80) -> str:
    if not path.exists():
        return ""
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    return "\n".join(lines[:max_lines])


def latest_file_for_student(folder: Path, student: str) -> Path | None:
    if not folder.exists():
        return None
    hits = [p for p in sorted(folder.glob("*.md")) if student.lower() in p.name.lower()]
    return hits[-1] if hits else None


def build_skeleton(when: str, system: str, student: str, notes: str,
                   profile_md: str, last_feedback_md: str, last_prep_md: str) -> str:
    return f"""---
date: {when}
system: {system}
student: {student}
status: AI生成
---

# {when} {system} Class-{student} · 备课

## 日历备注
{notes.strip() or '（无）'}

## 学生档案摘要
{profile_md.strip() or '（尚无学生档案，请课后建立）'}

## 最近一次课后反馈
{last_feedback_md.strip() or '（无历史记录）'}

## 上一次备课参考
{last_prep_md.strip() or '（无历史记录）'}

## 本次课教学目标
{PLACEHOLDER}

## 教学流程与时间分配
{PLACEHOLDER}

## 关键题目与演示
{PLACEHOLDER}

## 预判学生卡点
{PLACEHOLDER}
"""


def detect_proxy() -> str | None:
    """读取 macOS 系统代理（Clash Verge 等）。"""
    for var in ("https_proxy", "HTTPS_PROXY", "http_proxy", "HTTP_PROXY", "all_proxy"):
        if os.environ.get(var):
            return os.environ[var]
    try:
        out = subprocess.run(["scutil", "--proxy"], capture_output=True, text=True, timeout=5).stdout
        enabled = "HTTPSEnable : 1" in out or "HTTPEnable : 1" in out
        host = port = None
        for line in out.splitlines():
            key, _, val = line.partition(":")
            key, val = key.strip(), val.strip()
            if key == "HTTPSProxy" or (host is None and key == "HTTPProxy"):
                host = val
            if key == "HTTPSPort" or (port is None and key == "HTTPPort"):
                port = val
        if enabled and host and port:
            return f"http://{host}:{port}"
    except Exception:
        pass
    return None


def groq_generate(prompt: str, api_key: str) -> str:
    """调用 Groq API 生成文本（使用 curl 走代理）。"""
    proxy = detect_proxy()
    payload = json.dumps({
        "model": "llama-3.3-70b-versatile",
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.4,
        "max_tokens": 3000,
    })
    cmd = ["curl", "-s", "--connect-timeout", "30", "-m", "120",
           "https://api.groq.com/openai/v1/chat/completions",
           "-H", f"Authorization: Bearer {api_key}",
           "-H", "Content-Type: application/json",
           "-d", payload]
    if proxy:
        cmd.extend(["-x", proxy])
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=130)
    if result.returncode != 0:
        raise RuntimeError(f"curl failed: {result.stderr}")
    data = json.loads(result.stdout)
    if "choices" not in data:
        raise RuntimeError(f"Groq error: {data}")
    return data["choices"][0]["message"]["content"].strip()


def generate_teaching_plan(system: str, student: str, profile_md: str,
                           last_feedback_md: str, api_key: str) -> dict:
    """用 Groq 生成备课四段内容。"""
    prompt = f"""You are an experienced physics tutor preparing a lesson plan.

STUDENT PROFILE:
{profile_md[:3000]}

LAST CLASS FEEDBACK:
{last_feedback_md[:2000]}

CURRICULUM SYSTEM: {system} (use the official syllabus for this system)

Based on the student's current progress, known issues, and the official syllabus,
generate the following 4 sections for the NEXT lesson. Be specific and actionable.
Write in Chinese. Keep it practical — this teacher will use it directly.

Format your response EXACTLY as:

【教学目标】
(2-3 specific, testable objectives based on where the student left off)

【教学流程与时间分配】
(Break down a 60-minute lesson into segments with time allocations)

【关键题目与演示】
(List 3-5 specific problem types or demos to cover, aligned with the issues found)

【预判学生卡点】
(Predict 1-3 likely stumbling points based on the student's known weaknesses, with brief mitigation strategies)

IMPORTANT:
- Base everything on the student's ACTUAL progress and issues, not generic content
- Reference specific problems from the profile (e.g., if they struggle with trig, include trig practice)
- The next lesson should naturally continue from where the last one ended
- Do NOT repeat content already covered — advance the syllabus"""

    try:
        result = groq_generate(prompt, api_key)
    except Exception as e:
        print(f"  Groq 生成失败: {e}")
        return None

    # 解析四段
    sections = {}
    markers = [
        ("教学目标", "【教学目标】"),
        ("教学流程与时间分配", "【教学流程与时间分配】"),
        ("关键题目与演示", "【关键题目与演示】"),
        ("预判学生卡点", "【预判学生卡点】"),
    ]
    for name, marker in markers:
        idx = result.find(marker)
        if idx >= 0:
            start = idx + len(marker)
            end = len(result)
            for _, m2 in markers:
                idx2 = result.find(m2, idx + 1)
                if idx2 > idx and idx2 < end:
                    end = idx2
            sections[name] = result[start:end].strip()

    if len(sections) < 4:
        return {"raw": result}
    return sections


def notify(msg: str) -> None:
    subprocess.run(["osascript", "-e",
                    f'display notification "{msg}" with title "Physics Class Pipeline"'],
                   capture_output=True)


def main() -> None:
    cfg = load_config()
    vault = Path(os.path.expanduser(cfg["vault_path"]))
    keyword = cfg.get("calendar_keyword", "Class")
    root = vault / "上课记录"
    prep_dir = root / "备课内容"
    profile_dir = root / "学生档案"
    feedback_dir = root / "课后反馈"
    for d in (prep_dir, profile_dir, feedback_dir, root / "课堂文字稿"):
        d.mkdir(parents=True, exist_ok=True)

    # 读取 Groq API key
    api_key = os.environ.get("GROQ_API_KEY", "")
    if not api_key:
        try:
            zshrc = Path.home() / ".zshrc"
            for line in zshrc.read_text().splitlines():
                m = re.match(r'^\s*(export\s+)?GROQ_API_KEY=["\']?(.+?)["\']?\s*$', line)
                if m:
                    api_key = m.group(2)
        except Exception:
            pass

    out = subprocess.run(["osascript", "-e", APPLESCRIPT],
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"读取日历失败：{out.stderr.strip()}")

    tomorrow = (date.today() + timedelta(days=1)).isoformat()
    created = 0
    for line in out.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        summary, start_str = parts[0].strip(), parts[1].strip()
        notes = parts[2] if len(parts) > 2 else ""
        parsed = parse_event(summary, keyword)
        if not parsed:
            continue
        system, student = parsed
        target = prep_dir / f"{tomorrow} {system} Class-{student}.md"
        if target.exists():
            print(f"skip (exists): {target.name}")
            continue

        profile = read_head(profile_dir / f"{student}.md", 80)
        last_feedback = read_head(latest_file_for_student(feedback_dir, student) or Path("/nonexistent"), 60)
        last_prep = read_head(latest_file_for_student(prep_dir, student) or Path("/nonexistent"), 40)

        skeleton = build_skeleton(tomorrow, system, student, notes,
                                  profile, last_feedback, last_prep)

        # 用 Groq 生成备课内容
        if api_key and profile.strip():
            print(f"generating teaching plan for {student}...")
            plan = generate_teaching_plan(system, student, profile, last_feedback, api_key)
            if plan:
                if "raw" in plan:
                    skeleton = skeleton.replace(PLACEHOLDER, plan["raw"], 1)
                else:
                    for section_name in ["教学目标", "教学流程与时间分配", "关键题目与演示", "预判学生卡点"]:
                        content = plan.get(section_name, "（生成失败）")
                        skeleton = skeleton.replace(PLACEHOLDER, content, 1)
                print(f"  plan generated successfully")
            else:
                skeleton = skeleton.replace(PLACEHOLDER, "> 生成失败，请手动补全")
        else:
            skeleton = skeleton.replace(PLACEHOLDER, "> 未配置 GROQ_API_KEY 或无学生档案，请手动补全")

        target.write_text(skeleton, encoding="utf-8")
        created += 1
        print(f"created: {target}")

    if created:
        notify(f"明天有 {created} 节课的备课笔记已自动生成 ✅")
    else:
        print("明天没有新的课程事件（或笔记已存在）。")


if __name__ == "__main__":
    main()

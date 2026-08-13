#!/usr/bin/env python3
"""preclass_scan.py — 扫描明天苹果日历中的课程事件，生成备课笔记骨架。

日历事件格式：`{体系} Class-{学生名}`（含关键词 Class，默认大小写不敏感匹配）。
为每节课在 {vault}/上课记录/备课内容/ 下生成骨架笔记，自动嵌入：
  - 学生档案摘要（学生档案/{学生}.md 的基本信息/当前进度/主要问题）
  - 最近一次课后反馈（课后反馈/ 下该学生最新一篇）
  - 上一次备课/课次线索，供 AI 或教师补全教学目标与流程。
已存在同名笔记则跳过（幂等，可重复运行）。完成后发 macOS 通知。
"""
import json
import os
import re
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
CONFIG = SKILL_DIR / "config.json"

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


def read_head(path: Path, max_lines: int = 60) -> str:
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
status: 待补全
---

# {when} {system} Class-{student} · 备课

## 日历备注
{notes.strip() or '（无）'}

## 学生档案摘要（自动填入）
{profile_md.strip() or '（尚无学生档案，请课后建立）'}

## 最近一次课后反馈（自动填入）
{last_feedback_md.strip() or '（无历史记录）'}

## 上一次备课参考（自动填入）
{last_prep_md.strip() or '（无历史记录）'}

## 本次课教学目标
> 待补全：结合该体系官方 syllabus 与学生当前进度，写 2-3 条可检验的目标。

## 教学流程与时间分配
> 待补全：按分钟划分，含讲解 / 例题 / 练习 / 回顾。

## 关键题目与演示
> 待补全：列出本节课要讲的题目、实验或图示。

## 预判学生卡点
> 待补全：依据档案中的薄弱项，预判 1-3 个卡点及应对话术。
"""


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

        profile = read_head(profile_dir / f"{student}.md")
        last_feedback = read_head(latest_file_for_student(feedback_dir, student) or Path("/nonexistent"), 50)
        last_prep = read_head(latest_file_for_student(prep_dir, student) or Path("/nonexistent"), 40)

        target.write_text(build_skeleton(tomorrow, system, student, notes,
                                         profile, last_feedback, last_prep),
                          encoding="utf-8")
        created += 1
        print(f"created: {target}")

    if created:
        notify(f"明天有 {created} 节课的备课骨架已生成，请说「备课」补全")
    else:
        print("明天没有新的课程事件（或骨架已存在）。")


if __name__ == "__main__":
    main()

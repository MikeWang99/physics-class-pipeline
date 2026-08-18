#!/usr/bin/env python3
"""preclass_scan.py — 扫描明天日历中的课程事件，自动生成备课笔记草稿。

日历事件格式：`{体系} Class-{学生名}`（含关键词 Class，默认大小写不敏感匹配）。
为每节课在 {vault}/上课记录/备课内容/ 下生成备课笔记，自动嵌入：
  - 学生档案摘要（学生档案/{学生}.md 的基本信息/当前进度/主要问题）
  - 最近一次课后反馈（课后反馈/ 下该学生最新一篇）
  - 上一次备课/课次线索
  - 为 AI 生成部分预留固定结构和提示语。
已存在同名笔记则跳过（幂等，可重复运行）。完成后发 macOS 通知。
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
CONFIG = SKILL_DIR / "config.json"
PLACEHOLDER = "> 待装有该 Skill 的 AI 根据现有材料补全"


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
status: 待AI补全
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

## AI 补全要求
- 结合这位学生现有档案、最近一次反馈、以及该体系 syllabus，补全本次课安排
- 不要脱离当前进度重写整套计划，要紧贴明天这节课真正要上的内容
- 先给整体框架，再细化重点题型、时间分配和预判卡点

## 本次课教学目标
{PLACEHOLDER}

## 教学流程与时间分配
{PLACEHOLDER}

## 关键题目与演示
{PLACEHOLDER}

## 预判学生卡点
{PLACEHOLDER}
"""


def notify(msg: str) -> None:
    subprocess.run(["osascript", "-e",
                    f'display notification "{msg}" with title "Physics Class Pipeline"'],
                   capture_output=True)


def read_tomorrow_events() -> str:
    query_script = SKILL_DIR / "scripts" / "query_calendar_events.swift"
    out = subprocess.run(
        [str(query_script), "1"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "读取日历失败")
    return out.stdout


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

    try:
        events_output = read_tomorrow_events()
    except Exception as exc:
        sys.exit(f"读取日历失败：{exc}")

    tomorrow = (date.today() + timedelta(days=1)).isoformat()
    created = 0
    for line in events_output.splitlines():
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

        target.write_text(skeleton, encoding="utf-8")
        created += 1
        print(f"created: {target}")

    if created:
        notify(f"明天有 {created} 节课的备课笔记已自动生成 ✅")
    else:
        print("明天没有新的课程事件（或笔记已存在）。")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


def normalize(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", text.lower())


def clean_candidate(raw: str) -> str:
    text = raw.strip()
    if not text:
        return text
    text = re.split(r"[,，;；(（|｜/]", text, maxsplit=1)[0].strip()
    return text


def resolve(vault_path: Path, raw_name: str) -> str:
    cleaned = clean_candidate(raw_name)
    if not cleaned:
      return raw_name.strip()

    profile_dir = vault_path / "上课记录" / "学生档案"
    if not profile_dir.exists():
        return cleaned

    normalized_target = normalize(cleaned)
    candidates = sorted(profile_dir.glob("*.md"))

    for path in candidates:
        base = path.stem
        if base.lower() == cleaned.lower():
            return base

    for path in candidates:
        base = path.stem
        base_norm = normalize(base)
        if not base_norm:
            continue
        if base_norm in normalized_target or normalized_target in base_norm:
            return base

    prefix = normalized_target[:4]
    if prefix:
        for path in candidates:
            base = path.stem
            if normalize(base).startswith(prefix):
                return base

    return cleaned


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: resolve_student_name.py <vault_path> <student_raw>", file=sys.stderr)
        return 1

    vault_path = Path(sys.argv[1]).expanduser()
    raw_name = sys.argv[2]
    print(resolve(vault_path, raw_name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

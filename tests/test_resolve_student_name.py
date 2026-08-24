#!/usr/bin/env python3

import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "resolve_student_name.py"


class ResolveStudentNameTests(unittest.TestCase):
    def test_old_julian_spelling_resolves_to_julien_profile(self):
        with tempfile.TemporaryDirectory(prefix="physicsclass-test-") as tmp:
            vault = Path(tmp) / "vault"
            profile_dir = vault / "上课记录" / "学生档案"
            profile_dir.mkdir(parents=True)
            (profile_dir / "Julien.md").write_text(
                "# 学生档案 · Julien\n", encoding="utf-8"
            )

            result = subprocess.run(
                ["python3", str(SCRIPT), str(vault), "Julian"],
                check=True,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.stdout.strip(), "Julien")


if __name__ == "__main__":
    unittest.main()

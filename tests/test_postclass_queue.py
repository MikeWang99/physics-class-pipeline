#!/usr/bin/env python3

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SCRIPT = ROOT / "scripts" / "postclass_generate.sh"


class PostclassQueueTests(unittest.TestCase):
    def test_unmatched_transcript_is_queued_as_valid_utf8(self):
        with tempfile.TemporaryDirectory(prefix="physicsclass-test-") as tmp:
            root = Path(tmp)
            session = root / "1999-01-01_120000"
            vault = root / "vault"
            session.mkdir()
            for name in ("学生档案", "课后反馈", "课堂文字稿"):
                (vault / "上课记录" / name).mkdir(parents=True, exist_ok=True)
            transcript = "\n".join(
                f"[{index:02d}:00] 中英文课堂文字稿 Internal Energy"
                for index in range(240)
            )
            (session / "transcript.txt").write_text(transcript, encoding="utf-8")

            env = os.environ.copy()
            env["CALENDAR_QUERY_SCRIPT"] = "/usr/bin/false"
            subprocess.run(
                ["bash", str(SCRIPT), str(session), str(vault)],
                check=True,
                env=env,
                capture_output=True,
                text=True,
            )

            materials = list(
                (vault / "上课记录" / "课后反馈草稿").glob("*.md")
            )
            self.assertEqual(len(materials), 1)
            text = materials[0].read_text(encoding="utf-8")
            self.assertIn("status: 待AI识别学生", text)
            self.assertIn("calendar_match_status: unmatched", text)


if __name__ == "__main__":
    unittest.main()

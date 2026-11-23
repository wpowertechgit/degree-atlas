"""Regression tests for sourced curriculum mapping and generation order."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from mapper import curriculum_entries  # noqa: E402


class CurriculumMappingTests(unittest.TestCase):
    def test_requirement_kind_and_semester_stay_degree_specific(self):
        degree = {
            "name": "Chemical Engineering",
            "courses": [
                {"code": "C1"},
                {"code": "C2"},
                {"code": "E1"},
                {"code": "U1"},
            ],
        }
        plan = {
            "source": "https://example.edu/study-plan",
            "required": {"C2": 2, "C1": 1},
            "choices": [{
                "name": "Technical electives",
                "source": "https://example.edu/electives",
                "courses": ["E1"],
            }],
        }
        entries = curriculum_entries(
            degree,
            plan,
            lambda code: {"C1": "math-i", "C2": "chemistry", "E1": "elective", "U1": "imported"}.get(code),
        )

        self.assertEqual(
            [(e["subject"], e["kind"], e["semester"]) for e in entries],
            [
                ("math-i", "mandatory", 1),
                ("chemistry", "mandatory", 2),
                ("elective", "elective", None),
                ("imported", "unverified", None),
            ],
        )
        self.assertEqual(entries[0]["source"], plan["source"])
        self.assertEqual(entries[2]["source"], "https://example.edu/electives")
        self.assertEqual(entries[2]["group"], "Technical electives")

    def test_sourced_but_unmapped_course_fails_closed(self):
        degree = {"name": "Chemical Engineering", "courses": [{"code": "C1"}]}
        plan = {"source": "https://example.edu/study-plan", "required": {"C1": 1}}

        with self.assertRaisesRegex(ValueError, "sourced course C1 is unmapped"):
            curriculum_entries(degree, plan, lambda _code: None)

    def test_plan_with_unknown_course_code_is_rejected(self):
        degree = {"name": "Chemical Engineering", "courses": [{"code": "C1"}]}
        plan = {"source": "https://example.edu/study-plan", "required": {"MISSING": 1}}

        with self.assertRaisesRegex(ValueError, "unknown codes: MISSING"):
            curriculum_entries(degree, plan, lambda _code: None)


class NextScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.subjects = self.root / "data" / "subjects"
        self.subjects.mkdir(parents=True)
        self.degree_dir = self.root / "data" / "degrees"
        self.degree_dir.mkdir(parents=True)
        self._subject("foundations", [])
        self._subject("core-course", ["foundations"])
        self._subject("elective-course", [])
        self._subject("imported-course", [])
        (self.degree_dir / "chem-eng.json").write_text(json.dumps({
            "id": "chem-eng",
            "subjects": [
                {"subject": "core-course", "kind": "mandatory", "semester": 2,
                 "source": "https://example.edu/plan"},
                {"subject": "foundations", "kind": "mandatory", "semester": 1,
                 "source": "https://example.edu/plan"},
                {"subject": "elective-course", "kind": "elective", "semester": None,
                 "group": "Technical electives", "source": "https://example.edu/plan"},
                {"subject": "imported-course", "kind": "unverified", "semester": None},
            ],
        }), encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def _subject(self, sid, prerequisites):
        folder = self.subjects / sid
        folder.mkdir()
        (folder / "meta.json").write_text(json.dumps({
            "id": sid,
            "levels": {f"L{level}": {"state": "none"} for level in range(4)},
            "prerequisites": prerequisites,
        }), encoding="utf-8")

    def _run_next(self, *args):
        env = os.environ.copy()
        env["DEGREE_ATLAS_PROFILE"] = str(self.root)
        return subprocess.run(
            [sys.executable, str(SCRIPTS / "next.py"), "L0", "--degree", "chem-eng", *args],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        ).stdout

    def test_mandatory_courses_are_semester_ordered_and_prerequisites_are_pulled_in(self):
        rows = [line.split("\t") for line in self._run_next().splitlines()]
        subjects = [sid for sid, _status in rows]

        self.assertEqual(subjects, ["foundations", "core-course"])
        self.assertEqual(rows[0][1], "READY")
        self.assertTrue(rows[1][1].startswith("BLOCKED needs L0 of foundations"))

    def test_electives_are_only_added_when_requested(self):
        default = self._run_next()
        with_choices = self._run_next("--include-electives")

        self.assertNotIn("elective-course", default)
        self.assertNotIn("imported-course", default)
        self.assertIn("elective-course", with_choices)
        self.assertNotIn("imported-course", with_choices)


if __name__ == "__main__":
    unittest.main()

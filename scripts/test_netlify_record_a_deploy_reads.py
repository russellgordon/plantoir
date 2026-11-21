#!/usr/bin/env python3
"""
Which Netlify record a deploy of a section reads (#899 U3b, the review of
U3b's fixes, round three): every row of contracts/shared-rules.json ->
undo.netlifyRecordCases, run through deploy.py's OWN function,
`load_netlify_marker`. The Mac runs the same rows through
`DeployCommand.netlifyRecordADeployReads` and rolls each one over, undoes and
redoes it (UndoRolloverStepTests), so the one question that decides which
record is a section's website has the same answer in Swift as in the deploy.

Pure stdlib, no Docker and no network. Run with:

    python3 scripts/test_netlify_record_a_deploy_reads.py
"""
import json
import tempfile
import unittest
from pathlib import Path

import deploy

CONTRACT = Path(__file__).resolve().parent.parent / "contracts" / "shared-rules.json"


def netlify_record_cases():
    return json.loads(CONTRACT.read_text(encoding="utf-8"))["undo"]["netlifyRecordCases"]


def what_a_deploy_reads(case):
    """Lays the row's records out, calls load_netlify_marker, and says which
    record it went on with: `legacy` when it migrated the legacy one,
    `current` when the current record parses (whatever it holds), `none`
    otherwise; and the `id` of the site it returned, or None."""
    with tempfile.TemporaryDirectory() as folder:
        course_dir = Path(folder) / "courses" / "TST1O"
        section_dir = course_dir / ".merged_output" / "section1"
        section_dir.mkdir(parents=True)
        stable = course_dir / ".netlify_sites" / "section1.json"
        legacy = section_dir / ".netlify_site.json"
        if "current" in case:
            stable.parent.mkdir(parents=True)
            mark = b"\xef\xbb\xbf" if case.get("currentStartsWithAByteOrderMark") else b""
            stable.write_bytes(mark + case["current"].encode("utf-8"))
        if "legacy" in case:
            legacy.write_bytes(case["legacy"].encode("utf-8"))
        site = deploy.load_netlify_marker(course_dir, section_dir, 1)
        if "legacy" in case and not legacy.exists():
            reads = "legacy"
        elif stable.exists() and parses(stable):
            reads = "current"
        else:
            reads = "none"
        site_id = site.get("id") if isinstance(site, dict) else None
        return reads, site_id


def parses(path):
    """Whether the file parses as deploy.py reads it."""
    try:
        json.loads(path.read_text(encoding="utf-8"))
    except ValueError:
        return False
    return True


class NetlifyRecordADeployReadsTests(unittest.TestCase):

    def test_every_row_is_what_deploy_py_reads(self):
        cases = netlify_record_cases()
        self.assertGreaterEqual(len(cases), 10)
        for case in cases:
            with self.subTest(case=case["name"]):
                reads, site = what_a_deploy_reads(case)
                self.assertEqual(reads, case["reads"])
                self.assertEqual(site, case["site"])

    def test_a_broken_current_record_is_written_over_by_the_migration(self):
        # The state the review found: a migration's write_text killed part
        # way leaves a current record that is not JSON; the next deploy
        # migrates the good legacy record over it.
        case = {"current": '{"id": "cur', "legacy": '{"id": "legacy-good"}'}
        self.assertEqual(what_a_deploy_reads(case), ("legacy", "legacy-good"))


if __name__ == "__main__":
    unittest.main()

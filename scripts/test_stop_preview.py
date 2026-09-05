#!/usr/bin/env python3
"""
Which processes belong to a section's preview — run against the SHARED contract.

The cases are deserialised from `contracts/shared-rules.json` -> stopPreview,
never retyped. That is the whole point of this file's existence in its current
form: the version before it re-implemented the matching rule as a local
`would_stop()` helper and ran THAT, so it could not have caught the drift it
was written to catch. It even carried a test called "section 1 does not match
section 10" while the platform that had the bug went on having it.

Pure stdlib and no container: `stop_preview` imports nothing that is not in
the standard library, so unlike `test_graded_folders.py` this runs on the host.

Run with:

    python3 scripts/test_stop_preview.py
"""
import sys
import unittest
from pathlib import Path

scripts_dir = Path(__file__).resolve().parent
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

import contracts
import stop_preview
import toolchain_paths

REPO = scripts_dir.parent


class StopPreviewContractTests(unittest.TestCase):
    """Every case in the contract, against the real rule."""

    @classmethod
    def setUpClass(cls):
        repo_contracts = REPO / "contracts"
        if repo_contracts.is_dir():
            toolchain_paths.CONTRACTS_DIR = repo_contracts
        contracts.reset_cache()
        cls.contract = contracts.section("shared-rules", "stopPreview")

    def test_every_case(self):
        cases = self.contract["cases"]
        # A floor rather than an equality, so a case PROPOSED FROM WINDOWS
        # makes this suite fail loudly rather than being skipped quietly —
        # which is the mechanism the contract exists for.
        self.assertGreaterEqual(len(cases), 17, "the contract lost stopPreview cases")
        for case in cases:
            with self.subTest(case=case["name"]):
                section = case["section"]
                self.assertEqual(
                    stop_preview.pids_to_stop(
                        case["snapshot"],
                        section["directories"],
                        course=section.get("course"),
                        section=section.get("number"),
                        mode=case["mode"],
                    ),
                    case["stops"],
                    case.get("why", ""))

    def test_both_modes_are_exercised(self):
        """
        A case list that drifted into testing one question twice would look
        healthy and prove half of what it claims.
        """
        modes = set()
        for case in self.contract["cases"]:
            modes.add(case["mode"])
        self.assertEqual(modes, {"everything", "servingOnly"})

    def test_the_contract_describes_the_modes_the_code_has(self):
        self.assertEqual(set(self.contract["modes"]), set(stop_preview.MODES))


class TheRuleStopsStrictlyMoreThanTheOldSweepDid(unittest.TestCase):
    """
    The behaviour CHANGE, pinned deliberately rather than discovered later.

    Unifying three partial rules could not leave behaviour identical, and the
    honest way to say so is to run the old rule beside the new one on a
    realistic snapshot and state exactly what is gained. What is gained is the
    build driver and the children that hang off it — the processes a sweep by
    working directory could never see, because `build_site.py` passes `cwd=` to
    its children and never chdirs itself.
    """

    # A build of section 1 in flight, mid-npm-install, exactly as it appears
    # inside the container: the driver in /teaching, npm in the section's
    # folder, esbuild with no directory anywhere.
    SNAPSHOT = [
        {"pid": 1, "ppid": 0, "name": "sh", "commandLine": "sleep infinity",
         "cwd": "/teaching"},
        {"pid": 200, "ppid": 1, "name": "python3",
         "commandLine": "python3 -u /opt/scripts/build_site.py --host-os mac "
                        "--course=ADA1O --section=1 --port 8081",
         "cwd": "/teaching"},
        {"pid": 201, "ppid": 200, "name": "npm",
         "commandLine": "npm install --no-audit --silent",
         "cwd": "/tmp/quartz-builds/ADA1O/section1"},
        {"pid": 202, "ppid": 201, "name": "esbuild",
         "commandLine": "esbuild --service=0.19.9", "cwd": ""},
        {"pid": 300, "ppid": 1, "name": "node",
         "commandLine": "node /tmp/quartz-builds/ADA1O/section2/quartz/bootstrap-cli.mjs "
                        "build --concurrency 1 --serve --port 8082 --wsPort 9082",
         "cwd": "/tmp/quartz-builds/ADA1O/section2"},
    ]
    DIRECTORIES = [
        "/teaching/courses/ADA1O/.merged_output/section1",
        "/tmp/quartz-builds/ADA1O/section1",
    ]

    def old_sweep(self, snapshot, directories):
        """
        What `preview.sh --stop` did before this change: working directory
        only, no command lines, no descendants.
        """
        found = []
        for process in snapshot:
            cwd = process.get("cwd") or ""
            for directory in directories:
                if cwd == directory or cwd.startswith(directory + "/"):
                    found.append(process["pid"])
                    break
        return found

    def test_the_old_sweep_missed_the_driver_and_its_relative_path_children(self):
        self.assertEqual(self.old_sweep(self.SNAPSHOT, self.DIRECTORIES), [201])

    def test_the_new_rule_finds_all_three_and_still_leaves_section_2_alone(self):
        self.assertEqual(
            stop_preview.pids_to_stop(
                self.SNAPSHOT, self.DIRECTORIES, course="ADA1O", section=1,
                mode=stop_preview.MODE_EVERYTHING),
            [200, 201, 202])

    def test_what_is_gained_is_only_the_driver_and_its_descendants(self):
        """
        Superset, and named. A unification that quietly stopped something else
        as well would pass the two tests above and still be wrong.
        """
        before = set(self.old_sweep(self.SNAPSHOT, self.DIRECTORIES))
        after = set(stop_preview.pids_to_stop(
            self.SNAPSHOT, self.DIRECTORIES, course="ADA1O", section=1,
            mode=stop_preview.MODE_EVERYTHING))
        self.assertTrue(before.issubset(after))
        self.assertEqual(after - before, {200, 202})

    def test_a_publish_build_stops_none_of_it(self):
        """
        The other question, on the same snapshot: nothing here is a server for
        section 1, so a build for publishing stops nothing at all — including
        the build of section 1 that is already running, and section 2's
        preview.
        """
        self.assertEqual(
            stop_preview.pids_to_stop(
                self.SNAPSHOT, self.DIRECTORIES, course="ADA1O", section=1,
                mode=stop_preview.MODE_SERVING_ONLY),
            [])


class ThereIsOnlyOneCopyOfTheRule(unittest.TestCase):
    """
    The anti-drift gate, and the reason this piece was worth doing at all.

    Three implementations is the state this replaces. A fourth would arrive
    the same way the first three did — locally, reasonably, and invisibly — so
    the two callers are checked for having gone back to answering the question
    themselves. These read the files rather than the behaviour on purpose:
    the failure being prevented is a copy that WORKS, and therefore passes
    every behavioural test right up until the day it drifts.
    """

    def test_build_site_delegates(self):
        source = (REPO / "scripts" / "build_site.py").read_text(encoding="utf-8")
        self.assertTrue("import stop_preview" in source,
                        "build_site.py does not import the shared rule.")
        self.assertTrue("stop_preview.pids_to_stop" in source,
                        "build_site.py does not call the shared rule.")

    def test_build_site_has_no_proc_walk_of_its_own(self):
        source = (REPO / "scripts" / "build_site.py").read_text(encoding="utf-8")
        # assertFalse rather than assertNotIn: a failing assertNotIn prints the
        # whole haystack, and the haystack here is a five-thousand-line file.
        self.assertFalse(
            'Path("/proc")' in source,
            "build_site.py is reading /proc again — the rule moved to stop_preview.py, "
            "and a second copy here is how the three implementations happened the "
            "first time.")

    def test_the_launcher_ships_the_shared_module_rather_than_its_own_sweep(self):
        source = (REPO / "preview.sh").read_text(encoding="utf-8")
        self.assertTrue("stop_preview.py" in source)
        self.assertFalse("/proc/{entry}/cwd" in source,
                         "preview.sh has its own process sweep again.")

    def test_the_launcher_sends_the_code_rather_than_naming_a_baked_path(self):
        """
        Version independence, which is not a detail here.

        Stop mode must never build anything, so it runs against whatever
        container is ALREADY there — which after an upgrade is one built from
        the previous image. A `docker exec python3 /opt/scripts/stop_preview.py`
        would fail on such a container with a message nobody reads (both
        callers send this launcher's output to the null device and neither
        checks its exit code), and report success.
        """
        source = (REPO / "preview.sh").read_text(encoding="utf-8")
        self.assertFalse("python3 /opt/scripts/stop_preview.py" in source,
                         "preview.sh names a path baked into the image; an older "
                         "container does not have it and the failure is silent.")
        self.assertTrue("scripts/stop_preview.py" in source)


class WhereThereIsNoProcThisDoesNothing(unittest.TestCase):
    """
    Windows, natively. A no-op rather than an error — the same shape
    `kill_existing_quartz` already has there without `lsof`.
    """

    def test_an_absent_proc_yields_an_empty_snapshot(self):
        self.assertEqual(
            stop_preview.read_proc_snapshot(Path("/definitely/not/here")), [])

    def test_stopping_is_a_no_op(self):
        self.assertEqual(
            stop_preview.stop_section(
                ["/tmp/quartz-builds/ADA1O/section1"], course="ADA1O", section=1,
                proc_root=Path("/definitely/not/here")),
            [])


class ArgumentsAreReadAsArgumentsNotSubstrings(unittest.TestCase):
    """
    The second prefix bug, at the level it actually lives at. The contract
    covers it through a whole snapshot; this covers the helper directly, since
    it is the piece that is easy to "simplify" back into a substring test.
    """

    DRIVER = ("python3 -u /opt/scripts/build_site.py --host-os mac "
              "--course=ADA1O --section=10 --port 8082")

    def test_section_1_does_not_match_section_10(self):
        self.assertFalse(stop_preview.command_is_the_driver(self.DRIVER, "ADA1O", 1))

    def test_section_10_matches_section_10(self):
        self.assertTrue(stop_preview.command_is_the_driver(self.DRIVER, "ADA1O", 10))

    def test_the_space_separated_spelling_is_read_too(self):
        """`--section 10`, which build_site.py's own argparse accepts."""
        spaced = self.DRIVER.replace("--section=10", "--section 10")
        self.assertTrue(stop_preview.command_is_the_driver(spaced, "ADA1O", 10))
        self.assertFalse(stop_preview.command_is_the_driver(spaced, "ADA1O", 1))

    def test_a_directory_ending_an_argument_still_counts(self):
        self.assertTrue(stop_preview.command_names_directory(
            "node build.mjs --directory /tmp/quartz-builds/ADA1O/section1",
            "/tmp/quartz-builds/ADA1O/section1"))

    def test_but_section_1_still_does_not_match_section_10(self):
        self.assertFalse(stop_preview.command_names_directory(
            "node build.mjs --directory /tmp/quartz-builds/ADA1O/section10",
            "/tmp/quartz-builds/ADA1O/section1"))

    def test_a_windows_command_line_is_matched_with_either_separator(self):
        self.assertTrue(stop_preview.command_names_directory(
            r'"C:\Users\person\AppData\Local\Plantoir\builds\a1b2c3d4\work\ADA1O\section1'
            r'\quartz\bootstrap-cli.mjs"',
            r"C:\Users\person\AppData\Local\Plantoir\builds\a1b2c3d4\work\ADA1O\section1"))

    def test_and_windows_casing_does_not_change_the_answer(self):
        self.assertTrue(stop_preview.command_names_directory(
            r"C:\USERS\PERSON\APPDATA\LOCAL\PLANTOIR\BUILDS\A1B2C3D4\WORK\ADA1O\SECTION1\q.mjs",
            r"C:\Users\person\AppData\Local\Plantoir\builds\a1b2c3d4\work\ADA1O\section1"))


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""
Nothing the build starts in Node prints a deprecation into the teacher's
console (#640).

Quartz v4.5.0's dependencies require Node's built-in `punycode`, and from
Node 21 every Quartz build prints "[DEP0040] DeprecationWarning: The
`punycode` module is deprecated" to stderr, which the app shows in its
console: machinery, in plain sight (CLAUDE.md rule 1). The image moved to
Node 22 with #640, so toolchain_paths.node_environment adds
`--disable-warning=DEP0040` to NODE_OPTIONS - that one code only, never
NODE_NO_WARNINGS, which would hide every warning a real break prints.

This checks the helper (the flag is added, a NODE_OPTIONS already set is
kept, the flag is never doubled, the caller's mapping is not changed), that
build_site.py builds Quartz's environment with it, and that the figure
helper is started with it too. verify.sh carries the real check on the mac:
the Example Course's build log must hold no "[DEP" line.

Stdlib only (build_site imports python-frontmatter only if it is there), so
Windows' PythonToolchainTests discovers and runs it too.

Run with:

    python3 scripts/test_node_warnings.py
"""
import os
import re
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import toolchain_paths  # noqa: E402

FLAG = "--disable-warning=DEP0040"


class NodeEnvironmentTests(unittest.TestCase):

    def test_the_flag_is_added_when_nothing_was_set(self):
        environment = toolchain_paths.node_environment({"PATH": "/usr/bin"})
        self.assertEqual(environment["NODE_OPTIONS"], FLAG)
        self.assertEqual(environment["PATH"], "/usr/bin", "everything else is kept")

    def test_an_existing_node_options_is_kept(self):
        environment = toolchain_paths.node_environment({"NODE_OPTIONS": "--max-old-space-size=4096"})
        self.assertEqual(environment["NODE_OPTIONS"], "--max-old-space-size=4096 " + FLAG)

    def test_the_flag_is_never_written_twice(self):
        once = toolchain_paths.node_environment({})
        twice = toolchain_paths.node_environment(once)
        self.assertEqual(twice["NODE_OPTIONS"].split().count(FLAG), 1)

    def test_the_callers_environment_is_not_changed(self):
        base = {"NODE_OPTIONS": "--trace-warnings"}
        toolchain_paths.node_environment(base)
        self.assertEqual(base, {"NODE_OPTIONS": "--trace-warnings"})

    def test_only_that_one_warning_is_silenced(self):
        environment = toolchain_paths.node_environment({})
        self.assertNotIn("NODE_NO_WARNINGS", environment)
        self.assertNotIn("--no-warnings", environment["NODE_OPTIONS"])
        self.assertNotIn("--no-deprecation", environment["NODE_OPTIONS"])


class EveryNodeTheBuildStartsTests(unittest.TestCase):

    def test_quartz_is_run_with_the_node_environment(self):
        source = (HERE / "build_site.py").read_text(encoding="utf-8")
        built = re.search(r"^\s*env = toolchain_paths\.node_environment\(os\.environ\)\s*$", source, re.M)
        self.assertIsNotNone(built, "build_site.py must build Quartz's env with toolchain_paths.node_environment")
        runs = [match.start() for match in re.finditer(r'bootstrap-cli\.mjs"\), "build"', source)]
        self.assertTrue(runs, "build_site.py no longer runs Quartz's CLI where this test looks")
        for position in runs:
            self.assertLess(built.start(), position, "the env must be built before Quartz runs")
            line = source[position:source.index("\n", position)]
            self.assertIn("env=env", line, "every Quartz run must be given that env")

    def test_the_figure_helper_is_started_with_the_node_environment(self):
        import figures
        seen = {}

        class FakeProcess:
            stdout = iter(())
            stderr = iter(())

        def fake_popen(command, **keywords):
            seen.update(keywords)
            return FakeProcess()

        real_popen = figures.subprocess.Popen
        figures.subprocess.Popen = fake_popen
        try:
            figures._Helper(["node", "plantoir-figures.mjs"])
        finally:
            figures.subprocess.Popen = real_popen
        self.assertIn("env", seen, "the figure helper must be given an environment of its own")
        self.assertIn(FLAG, seen["env"]["NODE_OPTIONS"].split())
        self.assertEqual(seen["env"].get("PATH"), os.environ.get("PATH"), "the rest of the environment is kept")


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""
The shared tests that need python-frontmatter say so on a Mac, and fail
everywhere else (#907).

`verify.sh` runs these files in the image, where python-frontmatter and PyYAML
are installed. Run directly with a Mac's own Python, which has neither, they
used to stop with a `ModuleNotFoundError` or with dozens of wrong counts
(`build_site.py` reads pages without frontmatter when the module is missing),
and three agents on 2026-11-13 reported them as failures on `dev`. Each now
opens with the same block, between the markers below: on a Mac without the
module it prints one line naming the module and `verify.sh`, and exits 77, a
code a caller can tell from a failure (1). On any other platform the block
does nothing, so in the image and in Windows' PythonToolchainTests, whose
fetched runtime carries the modules, a missing module stays a failure.

How each reads it:

* `verify.sh` runs the seven only in the image (Linux), where the block does
  nothing, and reads any exit but 0 as a FAIL, 77 included.
* A direct run on a Mac without the module: the one line, exit 77.
* Windows: the block does nothing; a missing module fails the file, and
  PythonToolchainTests reads that as the failure it is.

Pure stdlib. The modules are kept from the child Pythons with a finder put in
front of `sys.meta_path`, so this runs the same on a Mac that has them and on
Windows. Run with:

    python3 scripts/test_image_only_tests_say_so.py
"""

import ast
import subprocess
import sys
import textwrap
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
START = "# ---- runs in the image (#907) ----\n"
END = "# ---- end of runs in the image ----\n"
MISSING_MODULE_EXIT = 77

# Every file that fails on a Mac's own Python for want of python-frontmatter
# (measured 2026-11-13: each failed on Homebrew Python 3.14 without it and
# passed in a venv with python-frontmatter and PyYAML installed).
NEEDS_FRONTMATTER = [
    "test_coverage_tab.py",
    "test_dates_follow_the_class.py",
    "test_front_page_title_repair.py",
    "test_links_checklist.py",
    "test_links_into_hidden_pages.py",
    "test_page_sources.py",
    "test_unreadable_page_settings.py",
]

# Put in front of the child's imports: frontmatter and yaml cannot be found.
WITHOUT_THE_MODULES = textwrap.dedent("""
    import sys
    class _NotHere:
        def find_spec(self, name, path=None, target=None):
            if name.split(".")[0] in ("frontmatter", "yaml"):
                raise ModuleNotFoundError(f"No module named {name!r}", name=name)
            return None
    sys.meta_path.insert(0, _NotHere())
    for _name in list(sys.modules):
        if _name.split(".")[0] in ("frontmatter", "yaml"):
            del sys.modules[_name]
""")


def the_block(text: str) -> str:
    start = text.index(START)
    return text[start:text.index(END, start) + len(END)]


class ImageOnlyTestsSaySoTests(unittest.TestCase):
    def test_every_file_opens_with_the_same_block_before_its_imports(self):
        blocks = set()
        for name in NEEDS_FRONTMATTER:
            text = (SCRIPTS / name).read_text(encoding="utf-8")
            self.assertIn(START, text, f"{name} has no runs-in-the-image block")
            blocks.add(the_block(text))
            block_line = text[:text.index(START)].count("\n") + 1
            for node in ast.parse(text).body:
                if isinstance(node, (ast.Import, ast.ImportFrom)):
                    self.assertGreater(node.lineno, block_line, f"{name} imports at line {node.lineno}, before the block")
                    break
        self.assertEqual(len(blocks), 1, "the blocks differ from file to file")

    def run_the_block(self, platform: str) -> subprocess.CompletedProcess:
        block = the_block((SCRIPTS / NEEDS_FRONTMATTER[0]).read_text(encoding="utf-8"))
        program = (WITHOUT_THE_MODULES + f"sys.platform = {platform!r}\n" + f"sys.argv = ['test_example.py']\n"
                   + block + "print('the block let the file go on')\nimport frontmatter\n")
        return subprocess.run([sys.executable, "-B", "-c", program], capture_output=True, text=True, timeout=60)

    def test_on_a_mac_the_block_says_which_module_in_one_line_and_exits_77(self):
        answer = self.run_the_block("darwin")
        self.assertEqual(answer.returncode, MISSING_MODULE_EXIT, answer.stderr)
        lines = answer.stdout.strip().splitlines()
        self.assertEqual(len(lines), 1, answer.stdout)
        self.assertIn("test_example.py", lines[0])
        self.assertIn("frontmatter", lines[0])
        self.assertIn("verify.sh", lines[0])
        self.assertEqual(answer.stderr.strip(), "")

    def test_anywhere_else_a_missing_module_stays_a_failure(self):
        for platform in ("win32", "linux"):
            answer = self.run_the_block(platform)
            self.assertIn("the block let the file go on", answer.stdout, platform)
            self.assertIn("ModuleNotFoundError", answer.stderr, platform)
            self.assertNotIn(answer.returncode, (0, MISSING_MODULE_EXIT), platform)

    def test_a_real_file_run_directly_without_the_module(self):
        # On this computer, as it is: 77 and the one line on a Mac, a
        # failure that is not 77 anywhere else.
        name = "test_dates_follow_the_class.py"
        program = WITHOUT_THE_MODULES + textwrap.dedent(f"""
            import runpy
            sys.argv = [{str(SCRIPTS / name)!r}]
            sys.path.insert(0, {str(SCRIPTS)!r})
            runpy.run_path(sys.argv[0], run_name="__main__")
        """)
        answer = subprocess.run([sys.executable, "-B", "-c", program], capture_output=True, text=True,
                                timeout=300, cwd=SCRIPTS)
        if sys.platform == "darwin":
            self.assertEqual(answer.returncode, MISSING_MODULE_EXIT, answer.stdout + answer.stderr)
            self.assertEqual(answer.stdout.strip(), f"{name}: needs the module frontmatter, which this Python does "
                             f"not have; verify.sh runs it in the image, where it is installed (exit 77)")
        else:
            self.assertNotIn(answer.returncode, (0, MISSING_MODULE_EXIT), answer.stdout + answer.stderr)


if __name__ == "__main__":
    unittest.main()

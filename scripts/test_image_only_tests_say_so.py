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

* `verify.sh` runs their tests in the image (Linux), where the block does
  nothing, and reads any exit but 0 as a FAIL, 77 included.
* `verify.sh` also runs one of them on the HOST, in a mode that needs neither
  module: `python3 scripts/test_page_sources.py --site <built> <course>`
  (step 6a2). The block lets `--site` through, so that run does what it did
  before the block. The first version of the block looked at no argument and
  exited 77 there too, which that step's `if` reads as a FAIL on a good tree
  (found by the Fable sweep, 2026-11-14); the host-run rule below pins it.
* A direct run on a Mac without the module: the one line, exit 77.
* Windows: the block does nothing; a missing module fails the file, and
  PythonToolchainTests reads that as the failure it is.

Pure stdlib. The modules are kept from the child Pythons with a finder put in
front of `sys.meta_path`, so this runs the same on a Mac that has them and on
Windows. Run with:

    python3 scripts/test_image_only_tests_say_so.py
"""

import ast
import re
import shlex
import subprocess
import sys
import textwrap
import unittest
from pathlib import Path

import launcher_test_trail  # noqa: E402,F401  every launcher run here keeps its trail in a temp folder (#738)

SCRIPTS = Path(__file__).resolve().parent
START = "# ---- runs in the image (#907) ----\n"
END = "# ---- end of runs in the image ----\n"
MISSING_MODULE_EXIT = 77

# The files are not listed by hand. Which files carry the block is read from
# the files; which files verify.sh runs in the image is read from verify.sh
# (`python3 /opt/scripts/test_<name>.py`); and on a Mac each of those is run
# with the modules hidden, so one that needs them and does not say so is
# found. On 2026-11-13 verify.sh ran 14 files in the image; seven carried the
# block and exited 77, the other seven passed without the modules, and the
# fourteen took 1.5 s on the M4 Pro.
IMAGE_RUN = re.compile(r"python3 /opt/scripts/(test_[a-z0-9_]+\.py)")

# A HOST run, in either form verify.sh writes one: `python3 scripts/test_<name>.py
# <arguments>` from the checkout's root, or `(cd scripts && python3 test_<name>.py
# <arguments>)`, up to the first redirect, pipe, bracket or end of command.
# Read from every script that runs tests or builds. On 2026-11-14 verify.sh
# ran 93 files on the host this way, and one of them carries the block: step
# 6a2's `python3 scripts/test_page_sources.py --site ...`. No other script ran
# a test file on the host.
HOST_RUN = re.compile(r"python3(?: -[A-Za-z]+)* +(scripts/)?(test_[a-z0-9_]+\.py)([^\n>|;&)]*)")
SCRIPTS_THAT_RUN_THEM = ("verify.sh", "verify-deploy.sh", "setup.sh", "preview.sh", "deploy.sh")


def files_with_the_block() -> list:
    found = []
    for path in sorted(SCRIPTS.glob("test_*.py")):
        if path.name == Path(__file__).name:
            continue
        if START in path.read_text(encoding="utf-8"):
            found.append(path.name)
    return found


def files_verify_runs_in_the_image() -> list:
    text = (SCRIPTS.parent / "verify.sh").read_text(encoding="utf-8")
    found = set()
    for name in IMAGE_RUN.findall(text):
        if (SCRIPTS / name).exists() and name != Path(__file__).name:
            found.add(name)
    return sorted(found)

def host_runs(names: list) -> list:
    """Every host run of one of these test files, as (script, folder it runs
    from, file, arguments), in the words the script wrote them."""
    found = []
    for script in SCRIPTS_THAT_RUN_THEM:
        path = SCRIPTS.parent / script
        if not path.exists():
            continue
        for from_the_root, name, arguments in HOST_RUN.findall(path.read_text(encoding="utf-8")):
            if name not in names:
                continue
            folder = SCRIPTS.parent if from_the_root else SCRIPTS
            found.append((script, folder, name, shlex.split(arguments)))
    return found

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


def run_without_the_modules(name: str, arguments: tuple = ()) -> subprocess.CompletedProcess:
    """The file run directly, as `python3 <file> <arguments>` would run it,
    with frontmatter and yaml hidden from it."""
    program = WITHOUT_THE_MODULES + textwrap.dedent(f"""
        import runpy
        sys.argv = {[str(SCRIPTS / name)] + list(arguments)!r}
        sys.path.insert(0, {str(SCRIPTS)!r})
        runpy.run_path(sys.argv[0], run_name="__main__")
    """)
    return subprocess.run([sys.executable, "-B", "-c", program], capture_output=True, text=True,
                          timeout=300, cwd=SCRIPTS)


def the_line(name: str) -> str:
    return (f"{name}: needs the module frontmatter, which this Python does not have; "
            f"verify.sh runs it in the image, where it is installed (exit 77)")


class ImageOnlyTestsSaySoTests(unittest.TestCase):
    def test_the_block_is_only_in_files_verify_runs_in_the_image(self):
        carrying = files_with_the_block()
        self.assertGreaterEqual(len(carrying), 7, "the rule no longer finds the files that carry the block")
        image_run = files_verify_runs_in_the_image()
        self.assertGreaterEqual(len(image_run), 7, "the rule no longer reads which files verify.sh runs in the image")
        outside = []
        for name in carrying:
            if name not in image_run:
                outside.append(name)
        self.assertEqual(outside, [], "these say verify.sh runs them in the image, and it does not")

    @unittest.skipUnless(sys.platform == "darwin", "the block acts on a Mac only; elsewhere a missing module fails")
    def test_on_a_mac_every_file_run_in_the_image_passes_or_says_so_without_the_modules(self):
        carrying = files_with_the_block()
        unsaid = []
        for name in files_verify_runs_in_the_image():
            answer = run_without_the_modules(name)
            if name in carrying:
                self.assertEqual(answer.returncode, MISSING_MODULE_EXIT, name + answer.stdout + answer.stderr)
                self.assertEqual(answer.stdout.strip(), the_line(name))
            elif answer.returncode != 0:
                last_lines = answer.stderr.strip().splitlines()
                last_line = last_lines[-1] if last_lines else "(nothing on stderr)"
                unsaid.append(f"{name} (exit {answer.returncode}: {last_line})")
        self.assertEqual(unsaid, [], "these fail on a Mac's own Python with frontmatter and yaml hidden, "
                                     "and do not carry the block; the reason may be something else, so read "
                                     "the last line of each")

    def test_every_host_run_of_a_file_with_the_block_runs_its_mode_without_the_modules(self):
        # The run as the script writes it, its arguments included, from the
        # repository's root, with frontmatter and yaml hidden. The folders it
        # names are not there, so the mode itself fails (1) or passes; what it
        # must never do is stop at the block with 77, which verify.sh reads as
        # a FAIL on a good tree. On every platform, so the rule holds wherever
        # the block is edited.
        checked = []
        for script, folder, name, arguments in host_runs(files_with_the_block()):
            program = WITHOUT_THE_MODULES + "sys.platform = 'darwin'\n" + textwrap.dedent(f"""
                import runpy
                sys.argv = {[str(SCRIPTS / name)] + arguments!r}
                sys.path.insert(0, {str(SCRIPTS)!r})
                runpy.run_path(sys.argv[0], run_name="__main__")
            """)
            answer = subprocess.run([sys.executable, "-B", "-c", program], capture_output=True, text=True,
                                    timeout=120, cwd=folder)
            said = f"{script}: python3 scripts/{name} {' '.join(arguments)}: exit {answer.returncode}, {answer.stdout}{answer.stderr}"
            self.assertNotEqual(answer.returncode, MISSING_MODULE_EXIT, said)
            self.assertNotIn(the_line(name), answer.stdout, said)
            checked.append(name)
        self.assertGreaterEqual(len(checked), 1, "the rule no longer finds verify.sh's host run of test_page_sources.py")

    def test_every_file_opens_with_the_same_block_before_its_imports(self):
        blocks = set()
        for name in files_with_the_block():
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
        block = the_block((SCRIPTS / files_with_the_block()[0]).read_text(encoding="utf-8"))
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
        answer = run_without_the_modules(name)
        if sys.platform == "darwin":
            self.assertEqual(answer.returncode, MISSING_MODULE_EXIT, answer.stdout + answer.stderr)
            self.assertEqual(answer.stdout.strip(), the_line(name))
        else:
            self.assertNotIn(answer.returncode, (0, MISSING_MODULE_EXIT), answer.stdout + answer.stderr)


if __name__ == "__main__":
    unittest.main()

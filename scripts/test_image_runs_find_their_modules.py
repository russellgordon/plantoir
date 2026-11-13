#!/usr/bin/env python3
"""
Every script `verify.sh` runs INSIDE the image finds the sibling modules it
imports there (#883).

`verify.sh` runs a few dozen of the shared tests in the image, from
`/opt/scripts`, because they need the build's own Python, Node or Quartz. What
sits in `/opt/scripts` during such a run is two lists and nothing else: the
scripts the `Dockerfile` copies in one by one, and the files that run's own
`docker run` mounts beside them. A test that imports a sibling outside both
lists stops with `ModuleNotFoundError` in the image while passing everywhere
else, because in a working copy every sibling is beside it.

**This exists because it happened.** On 2026-11-13 `test_coverage_tab.py`
started importing `test_deploy_non_interactive` to find a bash that can run the
launchers (on Windows plain `bash` is the WSL launcher). It passed on the mac
working copy and on Windows, and `verify.sh` was red on `dev` until the run
mounted the module too. Windows has no image, so its suite could not see it;
this test reads the two lists as text, needs no Docker, and runs on both.

`test_baked_modules.py` asks the same question of the scripts the image BAKES
(a product script importing an unbaked product module). This one asks it of
the scripts `verify.sh` RUNS there, test modules included, following imports
from module to module.

Imports are read with `ast`, so a module named in a docstring or a comment
does not count. Every import counts wherever it sits, inside a function or a
branch for one platform included: the image runs whichever branch it reaches.

Pure stdlib, no Docker. Run with:

    python3 scripts/test_image_runs_find_their_modules.py
"""
import ast
import pathlib
import re
import sys
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent
REPOSITORY_ROOT = SCRIPTS.parent
DOCKERFILE = REPOSITORY_ROOT / "Dockerfile"
VERIFY = REPOSITORY_ROOT / "verify.sh"

# The mount form verify.sh uses for every file it hands a run:
#   --mount "$(bind_mount_argument "$(pwd)/scripts/x.py" /opt/scripts/x.py),readonly"
MOUNTED_SCRIPT = re.compile(r'bind_mount_argument\s+"[^"]*"\s+/opt/scripts/([A-Za-z0-9_]+)\.py\)')
# The script a run executes: python3 /opt/scripts/x.py
RUN_SCRIPT = re.compile(r'python3\s+/opt/scripts/([A-Za-z0-9_]+)\.py')


def baked_scripts() -> set:
    """The module names the Dockerfile copies into /opt/scripts."""
    text = DOCKERFILE.read_text(encoding="utf-8")
    found = set()
    for name in re.findall(r"^COPY scripts/([A-Za-z0-9_]+)\.py /opt/scripts/", text, re.M):
        found.add(name)
    return found


def sibling_modules() -> set:
    """Every module in scripts/ that a sibling could import by bare name."""
    names = set()
    for path in SCRIPTS.glob("*.py"):
        names.add(path.stem)
    return names


def commands_in(shell_text: str) -> list:
    """verify.sh's text as logical commands: lines ending in a backslash
    joined to the line after them."""
    commands = []
    current = ""
    for line in shell_text.splitlines():
        stripped = line.rstrip()
        if stripped.endswith("\\"):
            current += stripped[:-1] + " "
        else:
            commands.append(current + stripped)
            current = ""
    if current:
        commands.append(current)
    return commands


def image_runs(shell_text: str) -> list:
    """Each `docker run` that executes a script from /opt/scripts, as
    (the script it runs, the scripts that run mounts beside it)."""
    runs = []
    for command in commands_in(shell_text):
        if "docker run" not in command:
            continue
        executed = RUN_SCRIPT.search(command)
        if executed is None:
            continue
        mounted = set()
        for name in MOUNTED_SCRIPT.findall(command):
            mounted.add(name)
        runs.append((executed.group(1), mounted))
    return runs


def imported_siblings(module: str, siblings: set) -> set:
    """The sibling modules this script imports, anywhere in it."""
    tree = ast.parse((SCRIPTS / f"{module}.py").read_text(encoding="utf-8"))
    found = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                head = alias.name.split(".")[0]
                if head in siblings:
                    found.add(head)
        elif isinstance(node, ast.ImportFrom):
            if node.level == 0 and node.module:
                head = node.module.split(".")[0]
                if head in siblings:
                    found.add(head)
    return found


def missing_in_the_image(executed: str, present: set, siblings: set) -> list:
    """(importer, module) for every sibling reached from `executed`, import by
    import, that is not among `present`."""
    missing = []
    seen = set()
    to_read = [executed]
    while to_read:
        module = to_read.pop()
        if module in seen:
            continue
        seen.add(module)
        if module not in siblings:
            continue
        for imported in sorted(imported_siblings(module, siblings)):
            if imported in present:
                to_read.append(imported)
            else:
                missing.append((module, imported))
    return missing


def every_gap(shell_text: str) -> list:
    """Every missing import across verify.sh's image runs, as sentences."""
    baked = baked_scripts()
    siblings = sibling_modules()
    gaps = []
    for executed, mounted in image_runs(shell_text):
        present = set(baked)
        for name in mounted:
            present.add(name)
        present.add(executed)
        for importer, module in missing_in_the_image(executed, present, siblings):
            gaps.append(
                f"{executed}.py runs in the image, and {importer}.py imports "
                f"{module}, which is neither baked by the Dockerfile nor "
                f"mounted by that run in verify.sh"
            )
    return gaps


class ImageRunsFindTheirModules(unittest.TestCase):

    def test_verify_sh_runs_scripts_in_the_image(self):
        """A guard on the guard: a parse that found no runs would pass silently."""
        runs = image_runs(VERIFY.read_text(encoding="utf-8"))
        self.assertGreater(len(runs), 10,
                           "No docker runs of /opt/scripts found; has verify.sh changed shape?")
        self.assertGreater(len(baked_scripts()), 5,
                           "No COPY scripts/*.py lines found; has the Dockerfile changed shape?")

    def test_the_coverage_tab_run_is_read_with_its_mounts(self):
        """The run that went red in #883 is found, with the module it needs."""
        runs = image_runs(VERIFY.read_text(encoding="utf-8"))
        mounts_by_script = {}
        for executed, mounted in runs:
            mounts_by_script[executed] = mounted
        self.assertIn("test_coverage_tab", mounts_by_script)
        self.assertIn("test_coverage_tab", mounts_by_script["test_coverage_tab"])

    def test_a_missing_mount_is_found(self):
        """The check itself: a run without its helper's mount is reported."""
        shell = (
            'if docker run --rm \\\n'
            '  --mount "$(bind_mount_argument "$(pwd)/scripts/test_coverage_tab.py" '
            '/opt/scripts/test_coverage_tab.py),readonly" \\\n'
            '  "$DEV_TEST_IMAGE" python3 /opt/scripts/test_coverage_tab.py >/tmp/x.log 2>&1; then\n'
        )
        gaps = every_gap(shell)
        joined = "\n".join(gaps)
        self.assertIn("imports test_deploy_non_interactive", joined)

    def test_every_image_run_finds_what_it_imports(self):
        gaps = every_gap(VERIFY.read_text(encoding="utf-8"))
        self.assertEqual(gaps, [], "\n" + "\n".join(gaps))


if __name__ == "__main__":
    unittest.main(verbosity=1)

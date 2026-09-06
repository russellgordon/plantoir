#!/usr/bin/env python3
"""
Every module a baked script imports must itself be baked into the image.

The image copies scripts one by one, by name, rather than the whole folder —
so splitting a rule out into a new sibling module is a change to the Dockerfile
whether or not anybody remembers it is. `setup_course.py` and `build_site.py`
import their siblings by BARE NAME, which resolves only if the file is sitting
beside them in `/opt/scripts`.

**This exists because it happened.** `class_pages.py` was added on 2026-09-04,
imported from both of those, and not copied. Every unit test was green and the
Docker image could not be built AT ALL: the Dockerfile imports `setup_course`
during the build to bake the Explorer's hide filter, so the missing module was
not a run-time surprise for one teacher, it was a hard failure of the build
that produces the toolchain. `verify.sh` caught it. This test makes the next
one cheaper to catch than a full image build.

The check is deliberately about IMPORTS rather than about a hand-kept list: a
list is a second place to forget.
"""
import ast
import pathlib
import re
import sys
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent
DOCKERFILE = SCRIPTS.parent / "Dockerfile"


def baked_scripts() -> set:
    """The script file names the image copies into /opt/scripts."""
    text = DOCKERFILE.read_text()
    return set(re.findall(r"^COPY scripts/([A-Za-z0-9_]+)\.py ", text, re.M))


def local_modules() -> set:
    """Every module in scripts/ that a sibling could import by bare name."""
    names = set()
    for path in SCRIPTS.glob("*.py"):
        if not path.name.startswith("test_"):
            names.add(path.stem)
    return names


def imported_by(module: str) -> set:
    """
    The sibling modules this script imports.

    Read with `ast` rather than by grepping for "import": a grep matches the
    word inside a docstring or a comment, and this test failing for a sentence
    somebody wrote would teach everyone to ignore it.
    """
    tree = ast.parse((SCRIPTS / f"{module}.py").read_text())
    siblings = local_modules()
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


class BakedModuleTests(unittest.TestCase):

    def test_the_dockerfile_bakes_some_scripts(self):
        """A guard on the guard: a parse that found nothing would pass silently."""
        self.assertGreater(
            len(baked_scripts()), 5,
            "No COPY scripts/*.py lines found — has the Dockerfile changed shape?",
        )

    def test_every_import_of_a_baked_script_is_also_baked(self):
        baked = baked_scripts()
        missing = []
        for module in sorted(baked):
            if not (SCRIPTS / f"{module}.py").exists():
                self.fail(f"The Dockerfile bakes scripts/{module}.py, which does not exist")
            for needed in sorted(imported_by(module)):
                if needed not in baked:
                    missing.append(f"{module}.py imports {needed}, which the image does not carry")
        self.assertEqual(
            missing, [],
            "A baked script imports a sibling the image does not have. Add a "
            "`COPY scripts/<name>.py /opt/scripts/<name>.py` line to the Dockerfile — "
            "the image copies scripts one at a time, so a new module is a Dockerfile "
            "change. Details: " + "; ".join(missing),
        )

    def test_the_transitive_case_is_covered_too(self):
        """
        A module baked because something imports it can import a third one.
        Walked to a fixed point rather than one level deep, because the one-level
        version passes right up until somebody splits a module twice.
        """
        baked = baked_scripts()
        reachable = set(baked)
        frontier = set(baked)
        while frontier:
            nextFrontier = set()
            for module in frontier:
                if not (SCRIPTS / f"{module}.py").exists():
                    continue
                for needed in imported_by(module):
                    if needed not in reachable:
                        reachable.add(needed)
                        nextFrontier.add(needed)
            frontier = nextFrontier
        notBaked = sorted(reachable - baked)
        self.assertEqual(
            notBaked, [],
            "These modules are reachable by import from a baked script but are not "
            "themselves baked: " + ", ".join(notBaked),
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)

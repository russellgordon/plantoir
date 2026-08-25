#!/usr/bin/env python3
"""
The toolchain recipe's folder list has FOUR copies. This pins them together.

The list lives in `contracts/toolchain.json` -> recipeFolders. The carriers are:

* the Dockerfile's `COPY` lines — checked in BOTH directions,
* the mac app's `WorkspaceModel.refreshToolchain`,
* Windows' `ToolchainMirror.RecipeFolders`,
* the marketing screenshot harness, `website/shots/capture.py`,
* `mac-app/project.yml`, which bundles them,
* `windows-app/Plantoir/Plantoir.csproj`, which ships them.

They drifted the moment a fifth folder was added, and capture.py — whose own
docstring said "keep them in step" — was the one that did not. That failure is
not subtle: capture.py copies the Dockerfile too, so the demo workspace got a
Dockerfile COPYing a folder that was not there. `docker buildx build` fails
outright, and preview.sh's friendly "missing the build recipe" message cannot
fire, because the Dockerfile IS present.

This test reads the source files rather than the running code, which is what
lets one Python test cover a Swift list and a C# list. Run with:

    python3 scripts/test_recipe_folders.py
"""
import json
import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def expected_folders() -> list:
    data = json.loads((REPO / "contracts" / "toolchain.json").read_text(encoding="utf-8"))
    return list(data["recipeFolders"]["folders"])


def _strip_comments(text: str) -> str:
    """
    Remove `//` line comments, keeping anything inside a string literal.

    This is what makes the scrape honest. An adversarial review defeated the
    first version by writing the list multi-line with one entry commented out
    — `// "contracts",   // temporarily disabled` — which is exactly how a
    person disables a folder, and the test reported OK while the demo
    workspace became unbuildable.
    """
    out = []
    for line in text.split("\n"):
        cleaned, in_string, index = [], False, 0
        while index < len(line):
            char = line[index]
            if char == '"':
                in_string = not in_string
            if not in_string and char == "/" and line[index + 1:index + 2] == "/":
                break
            cleaned.append(char)
            index += 1
        out.append("".join(cleaned))
    return "\n".join(out)


def _bracketed_list(text: str, anchor: str) -> list:
    """
    The string literals in the first bracketed group after `anchor` that
    actually contains one, with comments removed first.

    "the first bracket" is not good enough: C# spells the list
    `new[] { "patches", ... }`, so the first `[` is the empty pair in `new[]`
    and yields nothing.
    """
    text = _strip_comments(text)
    if anchor not in text:
        raise AssertionError(
            f"anchor {anchor!r} not found — the list was renamed or moved, "
            "which this test cannot follow. Update the anchor deliberately "
            "rather than letting the pin silently stop covering anything."
        )
    window = text[text.index(anchor):][:600]
    for match in re.finditer(r"[\[{]([^\]}]*)[\]}]", window, re.S):
        found = re.findall(r'"([^"]+)"', match.group(1))
        if found:
            return found
    return []


class RecipeFolderListsAgree(unittest.TestCase):

    def test_the_contract_lists_something(self):
        self.assertTrue(expected_folders())

    def test_the_mac_app_mirrors_every_recipe_folder(self):
        text = (REPO / "mac-app" / "QuartzTeachers" / "Models" / "WorkspaceModel.swift").read_text(encoding="utf-8")
        found = _bracketed_list(text, "for folderName in")
        self.assertEqual(found, expected_folders(),
                         "WorkspaceModel.refreshToolchain's folder list has drifted "
                         "from contracts/toolchain.json -> recipeFolders")

    def test_the_windows_app_mirrors_every_recipe_folder(self):
        text = (REPO / "windows-app" / "Plantoir.Core" / "Models" / "ToolchainMirror.cs").read_text(encoding="utf-8")
        found = _bracketed_list(text, "RecipeFolders")
        self.assertEqual(found, expected_folders(),
                         "ToolchainMirror.RecipeFolders has drifted from "
                         "contracts/toolchain.json -> recipeFolders")

    def test_the_screenshot_harness_stages_every_recipe_folder(self):
        """
        capture.py reads the contract rather than holding a copy, so what this
        checks is that it has not gone back to a literal list.
        """
        text = (REPO / "website" / "shots" / "capture.py").read_text(encoding="utf-8")
        self.assertIn("_recipe_folders()", text)
        self.assertNotIn('for folder in ["patches"', text)

    def test_the_dockerfile_copies_NOTHING_the_contract_does_not_list(self):
        """
        The reverse direction, and the one that matters most: the original bug
        was a Dockerfile that COPYed a folder the carriers did not know about.

        Checking only "every contract folder has a COPY" leaves that hole wide
        open — add `COPY newthing/ /opt/newthing/`, forget the contract, and
        every .toolchain/ becomes unbuildable again with a green suite. The pin
        must work whichever side moves first.
        """
        text = (REPO / "Dockerfile").read_text(encoding="utf-8")
        expected = set(expected_folders())
        copied = set()
        for match in re.finditer(r"^COPY\s+([A-Za-z0-9_.-]+)/", text, re.M):
            copied.add(match.group(1))
        # Directories the image builds FROM rather than recipe folders the
        # working folder mirrors; named explicitly so a new one is a decision.
        not_recipe_folders = {"quartz"}
        unexpected = copied - expected - not_recipe_folders
        self.assertEqual(
            unexpected, set(),
            f"the Dockerfile copies {sorted(unexpected)}, which "
            "contracts/toolchain.json -> recipeFolders does not list. Add it "
            "there (and to both mirrors) or the .toolchain/ this stages will "
            "not build."
        )

    def test_the_dockerfile_copies_every_recipe_folder(self):
        text = (REPO / "Dockerfile").read_text(encoding="utf-8")
        for folder in expected_folders():
            with self.subTest(folder=folder):
                copies_whole_folder = re.search(rf"^COPY {re.escape(folder)}/ ", text, re.M)
                copies_files_from_it = re.search(rf"^COPY {re.escape(folder)}/\S", text, re.M)
                self.assertTrue(copies_whole_folder or copies_files_from_it,
                                f"the Dockerfile never COPYs anything from {folder}/")

    def test_the_csproj_carries_every_recipe_folder(self):
        text = (REPO / "windows-app" / "Plantoir" / "Plantoir.csproj").read_text(encoding="utf-8")
        for folder in expected_folders():
            with self.subTest(folder=folder):
                self.assertIn(f"..\\..\\{folder}\\**", text,
                              f"Plantoir.csproj does not ship {folder}/ in Toolchain\\")

    def test_the_mac_bundle_carries_every_recipe_folder(self):
        text = (REPO / "mac-app" / "project.yml").read_text(encoding="utf-8")
        for folder in expected_folders():
            with self.subTest(folder=folder):
                self.assertIn(f"../{folder}", text,
                              f"project.yml does not bundle {folder}/")


if __name__ == "__main__":
    unittest.main(verbosity=2)

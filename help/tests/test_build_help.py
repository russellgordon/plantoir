"""build_help.py on the REAL repository, and the rules the script itself keeps:
Python 3.9 syntax, no third-party module, no bytecode left behind."""

from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import ast  # noqa: E402
import json  # noqa: E402
import shutil  # noqa: E402
import tempfile  # noqa: E402
import unittest  # noqa: E402

from helpers import HELP_DIR, REPO, run_build  # noqa: E402

STANDARD_LIBRARY = {
    "__future__", "argparse", "ast", "datetime", "functools", "hashlib", "html", "http", "json", "os",
    "pathlib", "plistlib", "re", "shutil", "struct", "subprocess", "sys", "tempfile", "typing", "unittest", "urllib", "time",
}


def outline_ids():
    outline = json.loads((HELP_DIR / "outline.json").read_text(encoding="utf-8"))
    ids = []
    assistant_ids = []
    assistant_sections = []
    for section in outline["sections"]:
        for entry in section["pages"]:
            ids.append(entry["id"])
            if entry.get("assistant") is True:
                assistant_ids.append(entry["id"])
        if section.get("assistant") is True:
            assistant_sections.append(section["title"])
    return ids, assistant_ids, assistant_sections


class RealRepositoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.mkdtemp(prefix="plantoir-help-real-")

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.temporary)

    def test_the_real_repository_checks_green_with_100_stubs(self) -> None:
        code, output = run_build(["--check"])
        self.assertEqual(code, 0, output)
        self.assertIn("Help: 0 pages written, 100 stubs, ", output)
        self.assertIn(" 0 failures", output)
        self.assertNotIn("FAILED", output)

    def test_the_real_outline_has_its_counts(self) -> None:
        ids, assistant_ids, assistant_sections = outline_ids()
        self.assertEqual(len(ids), 100)
        self.assertEqual(len(set(ids)), 100)
        self.assertEqual(len(assistant_ids), 14)
        self.assertEqual(len(assistant_sections), 1)

    @unittest.skipIf(shutil.which("hiutil") is None, "hiutil is not on this machine")
    def test_the_real_mac_book_has_every_outline_id_as_an_anchor(self) -> None:
        book = Path(self.temporary) / "Plantoir.help"
        code, output = run_build(["--mac", str(book), "--app-version", "2.0.0"])
        self.assertEqual(code, 0, output)
        self.assertIn("Plantoir.help: 100 pages, ", output)
        ids, _assistant_ids, _sections = outline_ids()
        anchors = json.loads((book / "Contents" / "Resources" / "anchors.json").read_text(encoding="utf-8"))
        self.assertEqual(anchors, ids)
        language_folder = book / "Contents" / "Resources" / "en.lproj"
        for page_id in ids:
            self.assertTrue((language_folder / (page_id + ".html")).exists(), page_id)

    def test_the_real_web_copy_leaves_out_the_assistant_section(self) -> None:
        web = Path(self.temporary) / "web"
        code, output = run_build(["--web", str(web)])
        self.assertEqual(code, 0, output)
        self.assertIn("web copy: 86 pages", output)
        ids, assistant_ids, assistant_sections = outline_ids()
        index = (web / "assets" / "search-index.js").read_text(encoding="utf-8")
        contents = (web / "index.html").read_text(encoding="utf-8")
        for page_id in assistant_ids:
            self.assertFalse((web / (page_id + ".html")).exists(), page_id)
            self.assertNotIn('"' + page_id + '"', index)
            self.assertNotIn(page_id + ".html", contents)
        for title in assistant_sections:
            self.assertNotIn(title, contents)
        for page_id in ids:
            if page_id not in assistant_ids:
                self.assertTrue((web / (page_id + ".html")).exists(), page_id)

    def test_the_real_web_copy_is_not_ready_to_go_live(self) -> None:
        code, output = run_build(["--release-web", str(Path(self.temporary) / "live")])
        self.assertNotEqual(code, 0, output)
        self.assertIn("is still a stub", output)


class ScriptRuleTests(unittest.TestCase):
    def python_files(self):
        files = [HELP_DIR / "build_help.py"]
        for folder in (HELP_DIR / "helpbook", HELP_DIR / "tests"):
            for path in sorted(folder.glob("*.py")):
                files.append(path)
        return files

    def test_every_file_parses_as_python_3_9(self) -> None:
        for path in self.python_files():
            ast.parse(path.read_text(encoding="utf-8"), filename=str(path), feature_version=(3, 9))

    def test_no_module_outside_the_standard_library_and_help(self) -> None:
        local = {"helpbook", "helpers"}
        for path in self.python_files():
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                names = []
                if isinstance(node, ast.Import):
                    for alias in node.names:
                        names.append(alias.name.split(".")[0])
                elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module is not None:
                    names.append(node.module.split(".")[0])
                for name in names:
                    self.assertTrue(name in STANDARD_LIBRARY or name in local, path.name + " imports " + name)

    def test_the_script_finds_the_repository_from_its_own_folder(self) -> None:
        elsewhere = tempfile.mkdtemp(prefix="plantoir-help-cwd-")
        try:
            import os
            import subprocess

            completed = subprocess.run(
                [sys.executable, "-I", "-B", str(HELP_DIR / "build_help.py"), "--check"],
                cwd=elsewhere, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
                env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"),
            )
            self.assertEqual(completed.returncode, 0, completed.stdout)
        finally:
            shutil.rmtree(elsewhere)

    def test_no_bytecode_is_left_in_help(self) -> None:
        import os
        import subprocess

        # Run WITHOUT -B and without PYTHONDONTWRITEBYTECODE: the script itself must not write any.
        environment = dict(os.environ)
        environment.pop("PYTHONDONTWRITEBYTECODE", None)
        completed = subprocess.run(
            [sys.executable, str(HELP_DIR / "build_help.py"), "--check"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True, env=environment,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        found = []
        for path in HELP_DIR.rglob("__pycache__"):
            found.append(str(path.relative_to(REPO)))
        self.assertEqual(found, [])


if __name__ == "__main__":
    unittest.main()

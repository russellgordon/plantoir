"""build_help.py on the REAL repository, and the rules the script itself keeps:
Python 3.9 syntax, no third-party module, no bytecode left behind."""

from __future__ import annotations

import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import ast  # noqa: E402
import re  # noqa: E402
import json  # noqa: E402
import shutil  # noqa: E402
import tempfile  # noqa: E402
import unittest  # noqa: E402
from typing import Dict, List  # noqa: E402

from helpers import HELP_DIR, REPO, run_build, run_page_search  # noqa: E402

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

    def test_the_real_repository_checks_green(self) -> None:
        # What stays true as pages are written: every outline page is written or a stub, nothing fails.
        code, output = run_build(["--check"])
        self.assertEqual(code, 0, output)
        found = re.search(r"Help: (\d+) pages written, (\d+) stubs, ", output)
        self.assertIsNotNone(found, output)
        ids, _assistant_ids, _sections = outline_ids()
        self.assertEqual(int(found.group(1)) + int(found.group(2)), len(ids))
        self.assertIn(" 0 failures", output)
        self.assertNotIn("FAILED", output)

    def test_every_outline_page_can_be_written(self) -> None:
        # A plain written page for EVERY outline id, in a copy of help/, checked against the real
        # repository: no approved title or question can stop its page building (review H2).
        copy = Path(self.temporary) / "every-page-help"
        shutil.copytree(str(HELP_DIR), str(copy), ignore=shutil.ignore_patterns("tests", "__pycache__"))
        ids, _assistant_ids, _sections = outline_ids()
        for page_id in ids:
            (copy / "pages" / (page_id + ".md")).write_text(
                "---\nid: " + page_id + "\nchecked: 2.0.0\nkeywords:\n- word\ndescription: A page.\n---\nWords.\n",
                encoding="utf-8",
            )
        code, output = run_build(["--check", "--help-dir", str(copy), "--repo", str(REPO)])
        self.assertEqual(code, 0, output)
        self.assertIn("Help: " + str(len(ids)) + " pages written, 0 stubs, ", output)

    def test_the_real_outline_has_its_counts(self) -> None:
        ids, assistant_ids, assistant_sections = outline_ids()
        self.assertEqual(len(ids), 104)
        self.assertEqual(len(set(ids)), 104)
        self.assertEqual(len(assistant_ids), 14)
        self.assertEqual(len(assistant_sections), 1)

    @unittest.skipIf(shutil.which("hiutil") is None, "hiutil is not on this machine")
    def test_the_real_mac_book_has_every_outline_id_as_an_anchor(self) -> None:
        book = Path(self.temporary) / "Plantoir.help"
        code, output = run_build(["--mac", str(book), "--app-version", "2.0.0"])
        self.assertEqual(code, 0, output)
        self.assertIn("Plantoir.help: 104 pages, ", output)
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
        ids, assistant_ids, assistant_sections = outline_ids()
        withheld = json.loads((HELP_DIR / "withheld-on-the-web.json").read_text(encoding="utf-8"))
        for entry in withheld.get("pages", []):
            assistant_ids.append(entry["id"])
        self.assertIn("web copy: " + str(len(ids) - len(assistant_ids)) + " pages", output)
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

    def search_the_real_pages(self, queries: List[str]) -> Dict[str, List[str]]:
        # Over the real pages, with the assistant switch on in a copy so the Coverage and
        # GitHub Copilot pages are in the index.
        node = shutil.which("node")
        if node is None:
            self.skipTest("node is not installed; the search was not run")
        copy = Path(self.temporary) / "search-help"
        if not copy.exists():
            shutil.copytree(str(HELP_DIR), str(copy), ignore=shutil.ignore_patterns("tests", "__pycache__"))
            facts = copy / "facts.json"
            facts.write_text(facts.read_text(encoding="utf-8").replace('"assistantOnTheWeb": false', '"assistantOnTheWeb": true'), encoding="utf-8")
        web = Path(self.temporary) / "search-web"
        if not web.exists():
            code, output = run_build(["--web", str(web), "--help-dir", str(copy), "--repo", str(REPO)])
            self.assertEqual(code, 0, output)
        script = Path(self.temporary) / "search.js"
        script.write_text(
            'const fs=require("fs"),vm=require("vm");const sb={window:{}};vm.createContext(sb);'
            'vm.runInContext(fs.readFileSync(process.argv[2],"utf8"),sb);const s=require(process.argv[3]);'
            'const out={};for(const q of process.argv.slice(4)){out[q]=s.searchHelp(sb.window.PLANTOIR_HELP_INDEX,q).map(r=>r.id);}'
            "console.log(JSON.stringify(out));",
            encoding="utf-8",
        )
        import subprocess

        completed = subprocess.run(
            [node, str(script), str(web / "assets" / "search-index.js"), str(web / "assets" / "search.js")] + queries,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        return json.loads(completed.stdout)

    def assert_first(self, firsts: Dict[str, str]) -> Dict[str, List[str]]:
        found = self.search_the_real_pages(list(firsts))
        for query in firsts:
            with self.subTest(query=query):
                self.assertGreater(len(found[query]), 0)
                self.assertEqual(found[query][0], firsts[query], found[query][:5])
        return found

    def test_ten_teacher_queries_put_the_right_page_first(self) -> None:
        # Measured over stubs on 2026-11-13, and again over the 73 written pages.
        firsts = {
            "how do I deploy my site": "deploy",
            "print a worksheet": "printing",
            "Coverage tab": "coverage",
            "GitHub Copilot": "copilot",
            "classes": "class-pages",
            "scheduled deploy": "schedule-deploy",
            "how do I hide pages from students": "publish-pages",
            "my students can't see the new page": "missing-page",
            "change the dates of my classes after a snow day": "redate",
            "make room for a class": "make-room",
            "quizzes": "quizzes",
            "quiz": "quizzes",
        }
        found = self.assert_first(firsts)
        # "classes" and "class" fold both ways; the floor keeps a long query short.
        self.assertEqual(found["classes"][:3], ["class-pages", "class-dates", "later-classes"])
        self.assertLessEqual(len(found["change the dates of my classes after a snow day"]), 5)

    def test_twenty_seven_more_teacher_queries_put_the_right_page_first(self) -> None:
        # Written against the 73 written pages (#839): a teacher's words, misspellings,
        # plurals, questions, symptoms and the exact names of menu items.
        firsts = {
            "snow day": "redate",
            "students still see the old version of the site": "deploy",
            "cloudfare": "cloudflare",
            "quizes": "quizzes",
            "it is stuck on the first preview": "slow-first-build",
            "backup my course": "backups",
            "I deleted a course by mistake": "archive",
            "add a youtube video": "videos",
            "chemical formulas": "notation",
            "checklist students can tick": "task-boxes",
            "move my working folder to dropbox": "synced-folder",
            "deploy greyed out": "deploy-failed",
            "Set School Year": "school-year",
            "Make Room for Classes": "make-room",
            "Copy a Page": "copy-a-page",
            "Get Ready for the Start of the Year": "start-of-year",
            "start of the school year": "start-of-year",
            "add another section": "add-section",
            "my diagrams show as text in obsidian": "obsidian-addons",
            "how do I show a pie chart": "diagrams-from-text",
            "what's the difference between publish and deploy": "publish-and-deploy",
            "problems tab warning": "problems",
            "change the color of my site": "section-look",
            "students run python code": "code",
            "where do pictures go": "media",
            "share a unit plan with a colleague": "share-plan",
            "my site address is taken": "site-address",
        }
        self.assert_first(firsts)

    def test_the_real_contents_page_caps_its_results_at_ten(self) -> None:
        # The whole page path over the real web copy: a query that finds more than ten pages
        # lists ten, and a line counts the rest.
        node = shutil.which("node")
        if node is None:
            self.skipTest("node is not installed; the page's search was not run")
        web = Path(self.temporary) / "cap-web"
        code, output = run_build(["--web", str(web)])
        self.assertEqual(code, 0, output)
        shown = run_page_search(node, web, "how do I deploy my site")
        self.assertIsNone(shown["threw"], shown)
        self.assertFalse(shown["hidden"])
        self.assertEqual(len(shown["items"]), 10)
        self.assertEqual(shown["items"][0]["href"], "deploy.html")
        self.assertEqual(len(shown["paragraphs"]), 1)
        found = re.match(r"^(\d+) more pages match\.$", shown["paragraphs"][-1])
        self.assertIsNotNone(found, shown["paragraphs"])
        self.assertGreater(int(found.group(1)), 0)

    def test_the_review_sentences_build_on_a_real_page(self) -> None:
        # Ordinary English that holds a FRAGMENT of a contract sentence passes (second review, HIGH 1),
        # in the body of the page whose title holds one.
        copy = Path(self.temporary) / "fragment-help"
        shutil.copytree(str(HELP_DIR), str(copy), ignore=shutil.ignore_patterns("tests", "__pycache__"))
        (copy / "pages" / "start-of-year.md").write_text(
            "---\nid: start-of-year\nchecked: 2.0.0\nkeywords:\n- year\ndescription: A page.\n---\n"
            "This gets a section ready for the start of the year.\n\n"
            "Everything is already for the start of the year.\n\n"
            "Plantoir keeps the first class of the year as it is.\n\n"
            "Pick a folder on this computer for your work.\n\n"
            "A class page can link to another section of this course.\n\n"
            "Most students get it right on the first try.\n\n"
            "The page you last viewed opens again.\n\n"
            "Put back as they were, the pages show again.\n\n"
            "If it fails, try again in a moment and it usually works.\n\n"
            "Their names do not change when you move them.\n\n"
            "It is as it was before you opened it.\n",
            encoding="utf-8",
        )
        code, output = run_build(["--check", "--help-dir", str(copy), "--repo", str(REPO)])
        self.assertEqual(code, 0, output)
        self.assertIn("Help: 86 pages written, ", output)

    def test_the_real_web_copy_is_not_ready_to_go_live(self) -> None:
        # RETIRED AT THE CUT: true until every page is written and every picture taken (CF);
        # delete this test then, when --release-web goes green.
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

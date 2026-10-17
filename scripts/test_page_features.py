#!/usr/bin/env python3
"""
Pages that ask for something extra on the built site (#454): `printable:` and
`printPdf:`, against the CONTRACT - and since #455 `codeRunner:` and its
runnable blocks (contracts/shared-rules.json -> codeRunnerBlocks: the language
table, the fence rule, where a fence can sit, the ids, what a site carries, the
engine's overlay and the words the page reads).

The cases are not retyped here. They are deserialised from
`contracts/file-formats.json` -> `pageOptIns` (readingCases, printPdfCases) and
`contracts/shared-rules.json` -> `siteHealth.checks` (printPdfNotFound), so the
rule a teacher's page is held to has one home.

**Stdlib only.** `page_features` reads values python-frontmatter has ALREADY
parsed - the build hands them over - so this needs nothing but Python and runs
on the Windows machine too (PythonToolchainTests discovers every
`scripts/test_*.py`). What PyYAML makes of each typed line is checked down the
real chain, in the image, by `check_print_rules_against_the_site.py`.

Run with:

    python3 scripts/test_page_features.py
"""
import os
import shutil
import tempfile
import unittest
from pathlib import Path

import contracts
import page_features
import site_health
import toolchain_paths

# A real (if minimal) PDF's first bytes, and a file that merely claims the name.
PDF_BYTES = b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n"
NOT_A_PDF_BYTES = b"PK\x03\x04 this is a word-processor file, not a PDF"


def use_the_repository_contract():
    repo_contracts = Path(__file__).resolve().parent.parent / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


def fill_media_folder(media_dir: Path, media_files: list) -> None:
    media_dir.mkdir(parents=True, exist_ok=True)
    for entry in media_files:
        data = PDF_BYTES if entry["isPdf"] else NOT_A_PDF_BYTES
        (media_dir / entry["name"]).write_bytes(data)


def value_after(lines: list, key: str):
    """The plain text after `key:` in a reading case's lines, or None."""
    for line in lines:
        if line.startswith(key + ":"):
            text = line[len(key) + 1:].strip()
            return text if text else None
    return None


class ReadingCaseTests(unittest.TestCase):
    """`printable:` - which pages opt in, and which make the site carry the engine."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()
        cls.cases = contracts.section("file-formats", "pageOptIns", "readingCases", "cases")

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-optins-"))

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def test_the_contract_still_carries_its_cases(self):
        self.assertGreaterEqual(len(self.cases), 10, "the contract lost reading cases")

    def test_every_reading_case_opts_in_as_the_contract_says(self):
        for case in self.cases:
            with self.subTest(lines=case["lines"]):
                self.assertIs(page_features.opts_in(case["printable"]), case["optsIn"])

    def test_every_reading_case_says_whether_the_site_carries_the_print_layout(self):
        for index, case in enumerate(self.cases):
            with self.subTest(lines=case["lines"]):
                media_dir = self.folder / f"case{index}" / "Media"
                fill_media_folder(media_dir, case.get("mediaFiles", []))
                visible = "publish: false" not in case["lines"]
                printable = page_features.opts_in(case["printable"])
                resolution = page_features.resolve_print_pdf(
                    value_after(case["lines"], "printPdf"), printable, visible, media_dir)
                self.assertIs(
                    page_features.carries_the_print_layout(case["printable"], visible,
                                                           resolution["button"]),
                    case["carriesThePrintLayout"])


class PrintPdfCaseTests(unittest.TestCase):
    """`printPdf:` - a teacher's own PDF, resolved against the course's Media folder."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()
        cls.cases = contracts.section("file-formats", "pageOptIns", "printPdfCases", "cases")

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-printpdf-"))

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def test_the_contract_still_carries_its_cases(self):
        self.assertGreaterEqual(len(self.cases), 15, "the contract lost printPdf cases")

    def test_every_case_resolves_as_the_contract_says(self):
        for index, case in enumerate(self.cases):
            with self.subTest(case=case["name"]):
                media_dir = self.folder / f"case{index}" / "Media"
                fill_media_folder(media_dir, case["mediaFiles"])
                before = sorted(os.listdir(media_dir))
                resolution = page_features.resolve_print_pdf(
                    case["printPdf"], case["printable"], case["visible"], media_dir)
                self.assertEqual(resolution["button"], case["expect"]["button"])
                self.assertEqual(resolution["file"], case["expect"]["file"])
                self.assertEqual(resolution["problem"], case["expect"]["problem"])
                self.assertEqual(sorted(os.listdir(media_dir)), before,
                                 "resolving a PDF must never touch the teacher's Media folder")

    def test_a_media_folder_that_is_not_there_finds_nothing(self):
        resolution = page_features.resolve_print_pdf(
            "Worksheet 3.pdf", True, True, self.folder / "no-such-folder")
        self.assertEqual(resolution["problem"], "missing")
        self.assertEqual(resolution["button"], "handout")

    def test_the_name_a_problem_reports_is_the_one_the_page_gives(self):
        resolution = page_features.resolve_print_pdf(
            "[[Unit 4 Key.pdf|the key]]", False, True, self.folder)
        self.assertEqual(resolution["typed"], "Unit 4 Key.pdf")

    def test_two_spellings_of_one_name_in_media_choose_the_exact_one(self):
        media_dir = self.folder / "Media"
        media_dir.mkdir()
        try:
            (media_dir / "Key.pdf").write_bytes(PDF_BYTES)
            (media_dir / "KEY.pdf").write_bytes(PDF_BYTES)
        except OSError:
            self.skipTest("this file system cannot hold two spellings of one name")
        if len(os.listdir(media_dir)) < 2:
            self.skipTest("this file system cannot hold two spellings of one name")
        resolution = page_features.resolve_print_pdf("KEY.pdf", False, True, media_dir)
        self.assertEqual(resolution["file"], "KEY.pdf")


class GateTests(unittest.TestCase):
    """The print engine reaches a section's site only when a page there opts in."""

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-gate-"))
        self.vendor = self.folder / "vendor"
        (self.vendor / "pagedjs").mkdir(parents=True)
        (self.vendor / "pagedjs" / "paged.min.js").write_text("/* engine */\n", encoding="utf-8")
        (self.vendor / "pagedjs" / "LICENSE.md").write_text("MIT\n", encoding="utf-8")
        self.output = self.folder / "section1"
        (self.output / "quartz" / "static").mkdir(parents=True)
        self.said = []

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def _gate(self, count):
        return page_features.install_gated_assets(
            self.output, {"pagedjs": count}, vendor_dir=self.vendor, printer=self.said.append)

    def test_the_default_vendor_folder_sits_beside_quartz(self):
        if os.environ.get("PLANTOIR_VENDOR_DIR", "").strip():
            self.skipTest("PLANTOIR_VENDOR_DIR is set in this environment")
        self.assertEqual(toolchain_paths.VENDOR_DIR, toolchain_paths.QUARTZ_DIR.parent / "vendor")

    def test_one_page_copies_the_engine_into_the_site(self):
        self._gate(1)
        engine = self.output / "quartz" / "static" / "pagedjs" / "paged.min.js"
        self.assertTrue(engine.is_file())
        self.assertTrue((self.output / "quartz" / "static" / "pagedjs" / "LICENSE.md").is_file())
        self.assertTrue(any("1 page" in line for line in self.said), self.said)

    def test_no_page_takes_away_an_engine_an_earlier_build_left(self):
        self._gate(2)
        self.said.clear()
        self._gate(0)
        self.assertFalse((self.output / "quartz" / "static" / "pagedjs").exists())

    def test_a_site_that_never_printed_is_left_exactly_as_it_was(self):
        before = sorted(str(path.relative_to(self.output)) for path in self.output.rglob("*"))
        self._gate(0)
        after = sorted(str(path.relative_to(self.output)) for path in self.output.rglob("*"))
        self.assertEqual(before, after)
        self.assertEqual(self.said, [])

    def test_running_twice_copies_nothing_the_second_time(self):
        first = self._gate(1)
        second = self._gate(1)
        self.assertGreater(first["pagedjs"]["copied"], 0)
        self.assertEqual(second["pagedjs"]["copied"], 0)

    def test_a_missing_engine_warns_and_never_stops_the_build(self):
        shutil.rmtree(self.vendor)
        self._gate(3)
        self.assertFalse((self.output / "quartz" / "static" / "pagedjs").exists())
        self.assertTrue(self.said, "a page asked for printing and nothing said the engine was missing")


class PrintPdfFindingTests(unittest.TestCase):
    """siteHealth -> printPdfNotFound: the teacher is told, in the app, not only the console."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()
        cls.entry = None
        for check in contracts.section("shared-rules", "siteHealth", "checks"):
            if check["name"] == "printPdfNotFound":
                cls.entry = check

    def _found(self, problems):
        facts = {
            "coverage_wanted": False, "media_target_exists": True,
            "section_index_exists": True, "print_pdf_problems": problems,
        }
        found = site_health.findings(facts, "ICS3U", 1)
        return [item for item in found if item.name == "printPdfNotFound"]

    def test_the_contract_carries_a_sentence_for_every_problem(self):
        self.assertIsNotNone(self.entry)
        for key in ("pageMissing", "pageNotAPdf", "pageHasAPath", "sentence",
                    "sentenceForSeveral", "detail", "andMore"):
            self.assertIn(key, self.entry)
        self.assertFalse(self.entry["fixable"])

    def test_no_problem_says_nothing(self):
        self.assertEqual(self._found([]), [])

    def test_one_page_is_named_with_its_reason(self):
        found = self._found([{"page": "Unit 3/Review", "file": "Worksheet 3.pdf", "problem": "missing"}])
        self.assertEqual(len(found), 1)
        self.assertIn("“Unit 3/Review”", found[0].sentence)
        self.assertIn("Worksheet 3.pdf", found[0].detail)
        self.assertNotIn("{", found[0].sentence + found[0].detail)

    def test_each_reason_has_its_own_words(self):
        found = self._found([
            {"page": "A", "file": "a.pdf", "problem": "missing"},
            {"page": "B", "file": "b.docx", "problem": "notAPdf"},
            {"page": "C", "file": "Media/c.pdf", "problem": "hasAPath"},
        ])
        self.assertEqual(len(found), 1, "one finding per section build, never one per page")
        detail = found[0].detail
        for key, page, name in (("pageMissing", "A", "a.pdf"), ("pageNotAPdf", "B", "b.docx"),
                                ("pageHasAPath", "C", "Media/c.pdf")):
            expected = site_health.filled(self.entry[key], {"page": page, "file": name})
            self.assertIn(expected, detail)
        self.assertIn("3", found[0].sentence)

    def test_eleven_pages_name_ten_and_count_the_rest(self):
        problems = [{"page": f"Page {n}", "file": f"{n}.pdf", "problem": "missing"} for n in range(11)]
        detail = self._found(problems)[0].detail
        self.assertIn(site_health.filled(self.entry["andMore"], {"count": 1}), detail)
        self.assertNotIn("“Page 10”", detail)

    def test_a_page_named_with_braces_is_named_as_it_is(self):
        found = self._found([{"page": "{course} notes", "file": "{section}.pdf", "problem": "missing"}])
        self.assertIn("“{course} notes”", found[0].sentence)
        self.assertIn("{section}.pdf", found[0].detail)


# ---- Runnable code (#455): contracts/shared-rules.json -> codeRunnerBlocks ----

def runner_rules(*keys):
    return contracts.section("shared-rules", "codeRunnerBlocks", *keys)


class RunnerLanguageTableTests(unittest.TestCase):
    """The ONE table: page_features' literal mirror equals the contract's, field for field."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def test_the_mirror_is_the_contracts_table_field_for_field(self):
        rows = runner_rules("languages")
        self.assertEqual(len(rows), len(page_features.RUNNER_LANGUAGES))
        for row in rows:
            with self.subTest(fence=row["fence"]):
                mirror = page_features.RUNNER_LANGUAGES.get(row["fence"])
                self.assertIsNotNone(mirror, "the mirror has no row for this fence")
                for field, value in row.items():
                    if field == "fence":
                        continue
                    got = mirror[field]
                    if isinstance(got, tuple):
                        got = list(got)
                    self.assertEqual(got, value, field)
                self.assertEqual(set(mirror), set(row) - {"fence"}, "the mirror has a field the contract does not")

    def test_every_language_engine_is_gated_by_the_codeRunner_key(self):
        for row in runner_rules("languages"):
            self.assertEqual(page_features.GATED_ASSETS.get(row["engine"]), "codeRunner")
            self.assertIn(row["engine"], page_features.ENGINE_WORDS)


class RunnerFenceTests(unittest.TestCase):
    """Which fences run, with which flags, where they can sit, and their ids."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def test_the_contract_still_carries_its_cases(self):
        self.assertGreaterEqual(len(runner_rules("fences", "cases")), 17)
        self.assertGreaterEqual(len(runner_rules("fences", "pageShapes", "cases")), 8)

    def test_every_fence_case_is_a_runner_as_the_contract_says(self):
        for case in runner_rules("fences", "cases"):
            with self.subTest(case=case["name"]):
                found = page_features.runner_for(case["lang"], case["meta"], case["optedIn"])
                if not case["runner"]:
                    self.assertIsNone(found)
                    continue
                self.assertIsNotNone(found)
                self.assertEqual(found["fence"], case.get("fence", case["lang"]))
                self.assertEqual(found["flags"], case["flags"])

    def test_every_page_shape_has_as_many_runners_as_the_contract_says(self):
        for case in runner_rules("fences", "pageShapes", "cases"):
            with self.subTest(case=case["name"]):
                found = page_features.runner_fences(case["page"], True)
                self.assertEqual(len(found), case["runners"])
                self.assertEqual(page_features.runner_fences(case["page"], False), [],
                                 "a page that does not opt in has no runner")

    def test_every_ids_case_names_its_runners_as_the_contract_says(self):
        for case in runner_rules("ids", "cases"):
            with self.subTest(slug=case["slug"]):
                self.assertEqual(page_features.runner_ids(case["slug"], case["page"]), case["ids"])

    def test_the_engines_a_page_needs(self):
        body = "```python run\nprint(1)\n```\n"
        self.assertEqual(page_features.runner_engines_on_page(True, body), {"pyodide"})
        self.assertEqual(page_features.runner_engines_on_page(None, body), set())
        self.assertEqual(page_features.runner_engines_on_page("true", body), set())
        self.assertEqual(page_features.runner_engines_on_page(True, "```python\nprint(1)\n```\n"), set())
        self.assertEqual(page_features.runner_engines_on_page(True, "```swift run\nprint(1)\n```\n"), {"swift"})
        both = "```python run\nprint(1)\n```\n\n```swift run\nprint(2)\n```\n"
        self.assertEqual(page_features.runner_engines_on_page(True, both), {"pyodide", "swift"})


class CodeRunnerReadingCaseTests(unittest.TestCase):
    """`codeRunner:` - only the boolean true opts a page in."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()
        cls.cases = contracts.section("file-formats", "pageOptIns", "codeRunnerReadingCases", "cases")

    def test_the_contract_still_carries_its_cases(self):
        self.assertGreaterEqual(len(self.cases), 6)

    def test_every_reading_case_opts_in_as_the_contract_says(self):
        for case in self.cases:
            with self.subTest(lines=case["lines"]):
                self.assertIs(page_features.opts_in(case["codeRunner"]), case["optsIn"])

    def test_the_key_is_listed_with_the_other_opt_ins(self):
        keys = [entry["key"] for entry in contracts.section("file-formats", "pageOptIns", "keys")]
        self.assertIn("codeRunner", keys)


class RunnerEngineWorkspace:
    """A section's output folder, a vendor folder holding stand-ins for every
    engine, and a support folder holding the runner overlay."""

    def __init__(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-runner-gate-"))
        self.vendor = self.folder / "vendor"
        (self.vendor / "pagedjs").mkdir(parents=True)
        (self.vendor / "pagedjs" / "paged.min.js").write_text("/* print */\n", encoding="utf-8")
        (self.vendor / "pyodide").mkdir(parents=True)
        for name in ("pyodide.mjs", "pyodide.asm.mjs", "pyodide.asm.wasm", "python_stdlib.zip",
                     "pyodide-lock.json", "README.txt"):
            (self.vendor / "pyodide" / name).write_text(f"/* {name} */\n", encoding="utf-8")
        self.support = self.folder / "support"
        (self.support / "gated" / "pyodide").mkdir(parents=True)
        (self.support / "gated" / "pyodide" / "plantoir-worker.js").write_text("/* worker */\n", encoding="utf-8")
        (self.support / "gated" / "swift").mkdir(parents=True)
        for name in ("plantoir-swift-worker.js", "plantoir-wasi.mjs"):
            (self.support / "gated" / "swift" / name).write_text(f"/* {name} */\n", encoding="utf-8")
        self.output = self.folder / "section1"
        (self.output / "quartz" / "static").mkdir(parents=True)
        self.said = []

    def gate(self, counts):
        return page_features.install_gated_assets(
            self.output, counts, vendor_dir=self.vendor, printer=self.said.append,
            support_dir=self.support)

    def static(self, engine):
        return self.output / "quartz" / "static" / engine

    def remove(self):
        shutil.rmtree(self.folder, ignore_errors=True)


class RunnerGateTests(unittest.TestCase):
    """What a site carries (siteCarriesEngine), the overlay, and the missing engine."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def setUp(self):
        self.space = RunnerEngineWorkspace()

    def tearDown(self):
        self.space.remove()

    def test_every_site_carries_engine_case_holds(self):
        for case in runner_rules("siteCarriesEngine", "cases"):
            with self.subTest(case=case["name"]):
                counts = {}
                for page in case["pages"]:
                    if not page["visible"]:
                        continue
                    for engine in page_features.runner_engines_on_page(page["codeRunner"], page["body"]):
                        counts[engine] = counts.get(engine, 0) + 1
                    if page_features.opts_in(page["printable"]):
                        counts["pagedjs"] = counts.get("pagedjs", 0) + 1
                self.space.gate(counts)
                for engine, carried in case["engines"].items():
                    self.assertIs(self.space.static(engine).is_dir(), carried, engine)

    def test_the_overlay_arrives_with_the_engine_and_leaves_with_it(self):
        self.space.gate({"pyodide": 1})
        carried = sorted(path.name for path in self.space.static("pyodide").iterdir())
        self.assertEqual(carried, ["README.txt", "plantoir-worker.js", "pyodide-lock.json", "pyodide.asm.mjs",
                                   "pyodide.asm.wasm", "pyodide.mjs", "python_stdlib.zip"])
        self.assertTrue(any("1 page" in line for line in self.space.said), self.space.said)
        self.space.gate({"pyodide": 0})
        self.assertFalse(self.space.static("pyodide").exists())

    def test_a_second_build_copies_nothing_and_keeps_the_overlay(self):
        first = self.space.gate({"pyodide": 2})
        second = self.space.gate({"pyodide": 2})
        self.assertEqual(first["pyodide"]["copied"], 7)
        self.assertEqual(second["pyodide"]["copied"], 0)
        self.assertTrue((self.space.static("pyodide") / "plantoir-worker.js").is_file())

    def test_the_overlay_wins_over_a_vendor_file_of_the_same_name(self):
        (self.space.vendor / "pyodide" / "plantoir-worker.js").write_text("/* old */\n", encoding="utf-8")
        self.space.gate({"pyodide": 1})
        self.assertEqual((self.space.static("pyodide") / "plantoir-worker.js").read_text(encoding="utf-8"),
                         "/* worker */\n")

    def test_a_stale_file_in_the_sites_copy_is_removed(self):
        self.space.gate({"pyodide": 1})
        (self.space.static("pyodide") / "stale.js").write_text("old\n", encoding="utf-8")
        self.space.gate({"pyodide": 1})
        self.assertFalse((self.space.static("pyodide") / "stale.js").exists())

    def test_a_missing_engine_with_its_overlay_installs_nothing_and_warns(self):
        shutil.rmtree(self.space.vendor / "pyodide")
        outcome = self.space.gate({"pyodide": 3})
        self.assertFalse(self.space.static("pyodide").exists(), "the overlay alone is not an engine")
        self.assertFalse(outcome["pyodide"]["installed"])
        self.assertTrue(self.space.said, "a page asked for runnable code and nothing said the engine was missing")

    def test_the_words_a_teacher_reads_name_the_language_and_no_machinery(self):
        self.space.gate({"pyodide": 1})
        shutil.rmtree(self.space.vendor / "pyodide")
        self.space.gate({"pyodide": 1})
        said = " ".join(self.space.said)
        self.assertIn("Python", said)
        for word in ("pyodide", "webassembly", "wasm", "worker", "docker", "container", "toolchain", "{"):
            self.assertNotIn(word, said.lower())

    def test_a_prebuilt_languages_overlay_is_its_engine(self):
        """#493: Swift's programs are compiled per course, so its overlay -
        the page's thread and its WASI shim - is all the engine there is,
        with no VENDOR_DIR/swift."""
        self.assertFalse((self.space.vendor / "swift").exists())
        outcome = self.space.gate({"swift": 1})
        self.assertTrue(outcome["swift"]["installed"])
        self.assertEqual(sorted(path.name for path in self.space.static("swift").iterdir()),
                         ["plantoir-swift-worker.js", "plantoir-wasi.mjs"])
        self.assertTrue(any("Swift" in line and "1 page" in line for line in self.space.said), self.space.said)
        self.space.gate({"swift": 0})
        self.assertFalse(self.space.static("swift").exists())

    def test_a_prebuilt_language_with_no_overlay_warns(self):
        shutil.rmtree(self.space.support / "gated" / "swift")
        outcome = self.space.gate({"swift": 2})
        self.assertFalse(outcome["swift"]["installed"])
        self.assertFalse(self.space.static("swift").exists())
        self.assertTrue(any("Swift" in line for line in self.space.said), self.space.said)

    def test_only_prebuilt_languages_have_an_overlay_for_an_engine(self):
        for fence, row in page_features.RUNNER_LANGUAGES.items():
            with self.subTest(fence=fence):
                self.assertEqual(row["engine"] in page_features.OVERLAY_IS_THE_ENGINE, row["prebuilt"])

    def test_engines_with_no_overlay_are_unchanged(self):
        outcome = self.space.gate({"pagedjs": 1})
        self.assertEqual(outcome["pagedjs"]["copied"], 1)
        self.assertEqual(sorted(path.name for path in self.space.static("pagedjs").iterdir()), ["paged.min.js"])


class RunnerWordsTests(unittest.TestCase):
    """quartz/plantoir_code_runner.json - what the page's code and the transformer read."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-runner-words-"))
        (self.folder / "quartz").mkdir()

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def read(self):
        import json
        return json.loads((self.folder / "quartz" / page_features.RUNNER_WORDS_FILE).read_text(encoding="utf-8"))

    def test_the_file_carries_the_contracts_words_limits_and_what_the_site_carries(self):
        page_features.write_runner_words(self.folder, {"pyodide"})
        written = self.read()
        words = dict(runner_rules("words"))
        words.pop("note")
        self.assertEqual(written["words"], words)
        self.assertEqual(written["carried"], ["pyodide"])
        self.assertEqual(written["limits"], {
            "outputCharacters": runner_rules("output", "maxCharacters"),
            "loadSeconds": runner_rules("loading", "watchdogSeconds"),
            "debounceMilliseconds": runner_rules("storage", "debounceMilliseconds"),
            "editorLines": runner_rules("editor", "maxLines"),
            "indent": runner_rules("editor", "indent"),
            "answerCharacters": runner_rules("liveInput", "answerCharacters"),
        })

    def test_writing_twice_gives_the_same_bytes_and_changes_nothing(self):
        self.assertTrue(page_features.write_runner_words(self.folder, {"pyodide"}))
        first = (self.folder / "quartz" / page_features.RUNNER_WORDS_FILE).read_bytes()
        self.assertFalse(page_features.write_runner_words(self.folder, {"pyodide"}))
        self.assertEqual((self.folder / "quartz" / page_features.RUNNER_WORDS_FILE).read_bytes(), first)
        page_features.write_runner_words(self.folder, set())
        self.assertEqual(self.read()["carried"], [])

    def test_no_word_a_student_reads_names_the_machinery(self):
        for key, text in runner_rules("words").items():
            if key == "note":
                continue
            with self.subTest(key=key):
                for word in ("pyodide", "webassembly", "wasm", "worker", "thread", "docker", "container",
                             "toolchain", "script", "quartz", "json"):
                    self.assertNotIn(word, text.lower())


if __name__ == "__main__":
    unittest.main()

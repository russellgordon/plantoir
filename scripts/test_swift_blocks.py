#!/usr/bin/env python3
"""
Runnable Swift (#493): scripts/swift_blocks.py and the Swift image's recipe,
against contracts/shared-rules.json -> codeRunnerBlocks.swift and
contracts/toolchain.json -> swiftImage.

Stdlib only, no Docker and no compiler, so Windows' PythonToolchainTests runs
it too: the key every block is cached by (the site's transformer computes the
same one - check_runner_rules_against_the_site.py runs the same cases in
Node), the toolchain id, what the launcher's plan writes, what the build's
prepare gives the site and says, and that the recipe holds every pin and
every flag the contract names. The compiler itself is exercised by verify.sh's
Swift gate.
"""

import json
import os
import shutil
import tempfile
import time
import unittest
from pathlib import Path

import contracts
import page_features
import swift_blocks
import toolchain_paths

REPO = Path(__file__).resolve().parent.parent


def use_the_repository_contract():
    """The repository's contract and support/ (the image's are elsewhere)."""
    if (REPO / "contracts").is_dir():
        toolchain_paths.CONTRACTS_DIR = REPO / "contracts"
    if (REPO / "support").is_dir():
        toolchain_paths.SUPPORT_DIR = REPO / "support"
    contracts.reset_cache()


def swift_rules(*keys):
    return contracts.section("shared-rules", "codeRunnerBlocks", "swift", *keys)


def recipe_copy(folder: Path) -> Path:
    """A copy of support/swift's recipe files, to change without touching the repository."""
    target = folder / "swift-recipe"
    target.mkdir()
    for name in swift_blocks.RECIPE_FILES:
        shutil.copyfile(REPO / "support" / "swift" / name, target / name)
    return target


class CacheKeyTests(unittest.TestCase):
    """codeRunnerBlocks.swift.cacheKey: normalise, then SHA-256."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def test_the_contract_still_carries_its_cases(self):
        self.assertGreaterEqual(len(swift_rules("cacheKey", "cases")), 8)

    def test_every_case_normalises_and_keys_as_the_contract_says(self):
        for case in swift_rules("cacheKey", "cases"):
            with self.subTest(case=case["name"]):
                text, dropped = swift_blocks.normalise(case["body"])
                self.assertEqual(text, case["normalised"])
                self.assertEqual(dropped, case["droppedAtTop"])
                self.assertEqual(swift_blocks.key_of(case["body"]), case["key"])

    def test_the_key_names_the_code_and_nothing_else(self):
        self.assertEqual(swift_blocks.key_of("print(1)\n"), swift_blocks.key_of("  print(1)  \n\n"))
        self.assertNotEqual(swift_blocks.key_of("print(1)"), swift_blocks.key_of("print(2)"))


class ToolchainIdTests(unittest.TestCase):
    """codeRunnerBlocks.swift.cache.toolchainIdFrom (#493 acceptance 12)."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-swift-id-"))

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def test_the_id_is_made_of_the_files_the_contract_names(self):
        named = [Path(path).name for path in swift_rules("cache", "toolchainIdFrom")]
        self.assertEqual(list(swift_blocks.RECIPE_FILES), named)
        for path in swift_rules("cache", "toolchainIdFrom"):
            self.assertTrue((REPO / path).is_file(), path)

    def test_the_id_is_stable_and_sixteen_hex(self):
        recipe = recipe_copy(self.folder)
        first = swift_blocks.toolchain_id(recipe)
        self.assertEqual(first, swift_blocks.toolchain_id(recipe))
        self.assertRegex(first, r"^[0-9a-f]{16}$")
        self.assertEqual(first, swift_blocks.toolchain_id(REPO / "support" / "swift"))

    def test_changing_a_flag_or_a_pin_changes_the_id(self):
        recipe = recipe_copy(self.folder)
        before = swift_blocks.toolchain_id(recipe)
        for name in swift_blocks.RECIPE_FILES:
            with self.subTest(changed=name):
                path = recipe / name
                original = path.read_bytes()
                path.write_bytes(original + b"\n")
                self.assertNotEqual(swift_blocks.toolchain_id(recipe), before)
                path.write_bytes(original)
                self.assertEqual(swift_blocks.toolchain_id(recipe), before)


class Course:
    """A course folder and its Swift cache, with pages written on request."""

    def __init__(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-swift-course-"))
        self.course = self.folder / "courses" / "ICS4U"
        self.course.mkdir(parents=True)
        self.cache_root = self.folder / "builds" / "ICS4U" / swift_blocks.CACHE_FOLDER
        self.output = self.folder / "builds" / "ICS4U" / "section1"
        (self.output / "quartz" / "static").mkdir(parents=True)
        self.said = []

    def page(self, name: str, text: str) -> Path:
        path = self.course / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def cache(self) -> Path:
        return self.cache_root / swift_blocks.toolchain_id(windows=False)

    def compiled(self, body: str, sdk="embedded", data=b"\0asm\1\0\0\0"):
        key = swift_blocks.key_of(body)
        self.cache().mkdir(parents=True, exist_ok=True)
        (self.cache() / f"{key}.wasm").write_bytes(data)
        (self.cache() / f"{key}.json").write_text(json.dumps({"ok": True, "sdk": sdk, "bytes": len(data)}))
        return key

    def failed(self, body: str, diagnostics: str):
        key = swift_blocks.key_of(body)
        self.cache().mkdir(parents=True, exist_ok=True)
        (self.cache() / f"{key}.json").write_text(json.dumps({"ok": False, "reason": "compileError",
                                                              "diagnostics": diagnostics}))
        return key

    def prepare(self, pages, windows=False):
        return swift_blocks.prepare(pages, self.output, self.cache_root, windows=windows, printer=self.said.append)

    def manifest(self):
        return json.loads((self.output / "quartz" / swift_blocks.MANIFEST).read_text(encoding="utf-8"))

    def static(self) -> Path:
        return self.output / "quartz" / "static" / swift_blocks.STATIC_FOLDER

    def remove(self):
        shutil.rmtree(self.folder, ignore_errors=True)


OPTED = "---\ntitle: Strings\ncodeRunner: true\n---\n"
BLOCK_ONE = 'print("one")'
BLOCK_TWO = 'let name = readLine() ?? ""\nprint("Hello, \\(name)!")'


class PlanTests(unittest.TestCase):
    """What the launcher's plan writes (#493 §4, review S3)."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def setUp(self):
        self.space = Course()

    def tearDown(self):
        self.space.remove()

    def plan(self, now=None):
        return swift_blocks.plan(self.space.course, self.space.cache_root, now=now, windows=False)

    def test_every_block_on_a_page_that_opts_in_becomes_one_job(self):
        self.space.page("Strings.md", OPTED + f"```swift run\n{BLOCK_ONE}\n```\n\n```swift run stdin\n{BLOCK_TWO}\n```\n"
                        f"\n```swift run\n{BLOCK_ONE}\n```\n\n```swift\nprint(\"not run\")\n```\n\n```python run\nprint(1)\n```\n")
        self.space.page("Unit 2/Hidden.md", "---\ncodeRunner: yes\npublish: false\n---\n```swift run\nprint(3)\n```\n")
        self.space.page("Plain.md", "---\ntitle: Plain\n---\n```swift run\nprint(4)\n```\n")
        self.space.page(".merged_output/section1/Copy.md", OPTED + "```swift run\nprint(5)\n```\n")
        self.space.page("Media/Notes.md", OPTED + "```swift run\nprint(6)\n```\n")
        planned = self.plan()
        self.assertEqual(planned["count"], 3, "two distinct blocks on the opted-in page, and the hidden page's")
        jobs = sorted(path.name for path in Path(planned["jobs"]).iterdir())
        wanted = sorted(f"{swift_blocks.key_of(body)}.swift" for body in (BLOCK_ONE, BLOCK_TWO, "print(3)"))
        self.assertEqual(jobs, wanted)
        self.assertEqual((Path(planned["jobs"]) / f"{swift_blocks.key_of(BLOCK_TWO)}.swift").read_text(encoding="utf-8"),
                         swift_blocks.normalise(BLOCK_TWO)[0] + "\n", "a job is exactly the normalised code")
        self.assertEqual(planned["cache"], str(self.space.cache()))
        self.assertEqual(planned["root"], str(self.space.cache_root))

    def test_a_block_the_cache_holds_is_not_a_job_and_nothing_is_made_for_nothing(self):
        self.space.page("Strings.md", OPTED + f"```swift run\n{BLOCK_ONE}\n```\n")
        self.space.compiled(BLOCK_ONE)
        planned = self.plan()
        self.assertEqual(planned["count"], 0)
        self.assertIsNone(planned["jobs"])
        self.assertFalse((self.space.cache_root / swift_blocks.JOBS_FOLDER).exists())

    def test_a_compile_error_is_cached_too(self):
        self.space.page("Strings.md", OPTED + f"```swift run\n{BLOCK_ONE}\n```\n")
        self.space.failed(BLOCK_ONE, "main.swift:1:1: error: nope")
        self.assertEqual(self.plan()["count"], 0, "an unchanged block that did not compile is not compiled again")

    def test_two_runs_never_share_a_job_folder(self):
        self.space.page("Strings.md", OPTED + f"```swift run\n{BLOCK_ONE}\n```\n")
        first, second = self.plan(), self.plan()
        self.assertNotEqual(first["jobs"], second["jobs"])
        self.assertTrue(Path(first["jobs"]).is_dir() and Path(second["jobs"]).is_dir())

    def test_a_killed_runs_jobs_are_removed_after_a_day(self):
        self.space.page("Strings.md", OPTED + f"```swift run\n{BLOCK_ONE}\n```\n")
        old = Path(self.plan()["jobs"])
        long_ago = time.time() - swift_rules("cache", "orphanJobSeconds") - 60
        os.utime(old, (long_ago, long_ago))
        fresh = Path(self.plan()["jobs"])
        self.assertFalse(old.exists())
        self.assertTrue(fresh.exists())

    def test_each_run_forgets_what_the_last_could_not_do(self):
        self.space.cache_root.mkdir(parents=True)
        (self.space.cache_root / swift_blocks.STATE_FILE).write_text('{"state": "noRoom"}')
        self.plan()
        self.assertFalse((self.space.cache_root / swift_blocks.STATE_FILE).exists())

    def test_the_settings_block_is_read_generously(self):
        for line, compiled in (("codeRunner: true", True), ("codeRunner: yes", True), ("codeRunner: True", True),
                               ("codeRunner: \"true\"", True), ("codeRunner: false", False), ("title: x", False)):
            with self.subTest(line=line):
                text = f"---\n{line}\n---\n```swift run\nprint(1)\n```\n"
                self.assertEqual(bool(swift_blocks.blocks_to_compile([text])), compiled)


class PrepareTests(unittest.TestCase):
    """What the build gives the site and says (codeRunnerBlocks.swift.site, reasons)."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def setUp(self):
        self.space = Course()

    def tearDown(self):
        self.space.remove()

    @staticmethod
    def page(body, place="Units/Strings", code_runner=True, source=None):
        return {"place": place, "codeRunner": code_runner, "body": body, "source": source}

    def test_a_compiled_block_is_copied_in_and_listed(self):
        key = self.space.compiled(BLOCK_ONE, sdk="full")
        outcome = self.space.prepare([self.page(f"```swift run\n{BLOCK_ONE}\n```\n")])
        self.assertEqual(outcome["problems"], [])
        self.assertEqual(self.space.manifest(), {key: {"ok": True, "file": f"{key}.wasm", "sdk": "full"}})
        self.assertEqual(sorted(path.name for path in self.space.static().iterdir()), [f"{key}.wasm"])
        self.assertTrue(any("1 of 1 Swift program" in line for line in self.space.said), self.space.said)

    def test_the_sites_programs_are_exactly_the_ones_its_pages_use(self):
        self.space.compiled(BLOCK_ONE)
        two = self.space.compiled(BLOCK_TWO)
        self.space.prepare([self.page(f"```swift run\n{BLOCK_ONE}\n```\n```swift run\n{BLOCK_TWO}\n```\n")])
        self.assertEqual(len(list(self.space.static().iterdir())), 2)
        self.space.prepare([self.page(f"```swift run\n{BLOCK_TWO}\n```\n")])
        self.assertEqual([path.name for path in self.space.static().iterdir()], [f"{two}.wasm"],
                         "a program no page uses any more is removed")
        self.space.prepare([])
        self.assertFalse(self.space.static().exists())
        self.assertEqual(self.space.manifest(), {})

    def test_preparing_twice_copies_nothing_the_second_time(self):
        self.space.compiled(BLOCK_ONE)
        self.space.prepare([self.page(f"```swift run\n{BLOCK_ONE}\n```\n")])
        self.space.said.clear()
        manifest = (self.space.output / "quartz" / swift_blocks.MANIFEST).stat().st_mtime_ns
        self.space.prepare([self.page(f"```swift run\n{BLOCK_ONE}\n```\n")])
        self.assertFalse(any("copied in" in line for line in self.space.said), self.space.said)
        self.assertEqual((self.space.output / "quartz" / swift_blocks.MANIFEST).stat().st_mtime_ns, manifest)

    def test_a_page_that_does_not_opt_in_gives_nothing(self):
        self.space.compiled(BLOCK_ONE)
        outcome = self.space.prepare([self.page(f"```swift run\n{BLOCK_ONE}\n```\n", code_runner="true")])
        self.assertEqual(outcome["blocks"], 0)
        self.assertEqual(self.space.manifest(), {})

    def test_a_compile_error_is_named_at_its_line_in_the_teachers_file(self):
        body = "\n\nlet name = readLine() ?? \"\"\nprint(nmae)"
        diagnostics = "main.swift:2:7: error: cannot find 'nmae' in scope\nprint(nmae)\n      ^~~~"
        key = self.space.failed(body, diagnostics)
        source = OPTED + "Some words.\n\n```swift run\n" + body + "\n```\n"
        outcome = self.space.prepare([self.page(f"```swift run\n{body}\n```\n", source=source)])
        self.assertEqual(self.space.manifest(), {key: {"ok": False, "reason": "compileError"}})
        problem = outcome["problems"][0]
        # The fence opens on line 7 of the file; two blank lines were dropped
        # from the top, and the error is on the program's line 2: line 11.
        self.assertEqual((problem["line"], problem["block"], problem["reason"]), (11, 1, "compileError"))
        self.assertEqual(problem["said"], "cannot find 'nmae' in scope")
        lines = [line for line in self.space.said if line.startswith("plantoir: error:")]
        reason = swift_rules("reasons", "compileError").replace("{said}", "cannot find 'nmae' in scope")
        self.assertEqual(lines, [f"plantoir: error: Units/Strings.md: swift block 1, line 11: {reason}"])
        self.assertFalse(self.space.static().exists())

    def test_every_reason_case_holds(self):
        for case in swift_rules("reasonCases"):
            with self.subTest(case=case["name"]):
                self.assertEqual(swift_blocks.missing_reason(case["state"], case["appliesOn"] == "windows"),
                                 case["reason"])

    def test_a_block_with_no_program_says_why(self):
        for state, windows, reason in ((None, False, "notCompiled"), ({"state": "noRoom"}, False, "noRoom"),
                                       ({"state": "notDownloaded"}, True, "notDownloaded"),
                                       (None, True, "notCompiled")):
            with self.subTest(reason=reason):
                shutil.rmtree(self.space.cache_root, ignore_errors=True)
                if state is not None:
                    self.space.cache_root.mkdir(parents=True)
                    (self.space.cache_root / swift_blocks.STATE_FILE).write_text(json.dumps(state))
                self.space.said.clear()
                outcome = self.space.prepare([self.page(f"```swift run\n{BLOCK_ONE}\n```\n",
                                                        source=OPTED + f"```swift run\n{BLOCK_ONE}\n```\n")],
                                             windows=windows)
                self.assertEqual(outcome["problems"][0]["reason"], reason)
                self.assertEqual(outcome["problems"][0]["line"], 5, "the opening fence's line")
                self.assertEqual(self.space.manifest()[swift_blocks.key_of(BLOCK_ONE)], {"ok": False, "reason": reason})
                said = [line for line in self.space.said if line.startswith("plantoir: error:")]
                self.assertEqual(len(said), 1)
                self.assertIn("swift block 1, line 5: ", said[0])

    def test_an_old_toolchains_programs_are_kept_until_this_one_has_every_block(self):
        old = self.space.cache_root / "0123456789abcdef"
        old.mkdir(parents=True)
        (old / "kept.wasm").write_bytes(b"old")
        self.space.prepare([self.page(f"```swift run\n{BLOCK_ONE}\n```\n")])
        self.assertTrue(old.exists(), "pruned while this toolchain still lacked a block (review N5)")
        self.space.compiled(BLOCK_ONE)
        self.space.prepare([self.page(f"```swift run\n{BLOCK_ONE}\n```\n")])
        self.assertFalse(old.exists())

    def test_entries_unused_for_the_prune_days_go_and_used_ones_stay(self):
        used = self.space.compiled(BLOCK_ONE)
        unused = self.space.compiled(BLOCK_TWO)
        long_ago = time.time() - swift_rules("cache", "pruneDays") * 86400 - 60
        for key in (used, unused):
            for suffix in (".wasm", ".json"):
                os.utime(self.space.cache() / f"{key}{suffix}", (long_ago, long_ago))
        self.space.prepare([self.page(f"```swift run\n{BLOCK_ONE}\n```\n")])
        self.assertTrue((self.space.cache() / f"{used}.wasm").exists())
        self.assertFalse((self.space.cache() / f"{unused}.wasm").exists())

    def test_the_finding_names_the_block_and_its_reason(self):
        import site_health
        facts = {"swift_problems": [{"page": "Units/Strings", "block": 2, "line": 14, "reason": "compileError",
                                     "said": "expected '}', got ','"},
                                    {"page": "Units/Loops", "block": 1, "line": None, "reason": "noRoom", "said": ""}]}
        found = site_health.swift_finding(facts, "ICS4U", 1, site_health._checks_by_name())
        check = [entry for entry in contracts.section("shared-rules", "siteHealth", "checks")
                 if entry["name"] == "swiftCouldNotBePrepared"][0]
        self.assertEqual(found.sentence, check["sentenceForSeveral"].replace("{count}", "2")
                         .replace("{course}", "ICS4U").replace("{section}", "1"))
        self.assertIn("“Units/Strings”, Swift block 2, line 14: Swift found an error in it: expected '}', got ','", found.detail)
        self.assertIn(f"about {swift_rules('room', 'needGigabytes')} GB", found.detail)
        self.assertIn("swiftCouldNotBePrepared",
                      contracts.section("shared-rules", "siteHealth", "repair", "neverOffered", "checks"))


class GroupingNotesAndCacheCaseTests(unittest.TestCase):
    """The finding says a shared cause once (groupingCases, implementation
    review S4); the note lines (noteCases, S2 and N2); what plan compiles
    again (cacheCases, S3)."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()

    def setUp(self):
        self.space = Course()

    def tearDown(self):
        self.space.remove()

    def test_every_grouping_case_holds(self):
        import site_health
        check = [entry for entry in contracts.section("shared-rules", "siteHealth", "checks")
                 if entry["name"] == "swiftCouldNotBePrepared"][0]
        self.assertGreaterEqual(len(check["groupingCases"]), 3)
        for case in check["groupingCases"]:
            with self.subTest(case=case["name"]):
                # A case that says which platform it is on is rendered there
                # (downloadGigabytes, #570); the others read the same on both.
                windows = None if "on" not in case else case["on"] == "windows"
                found = site_health.swift_finding({"swift_problems": case["problems"]}, "ICS4U", 1,
                                                  site_health._checks_by_name(), windows=windows)
                self.assertEqual(found.detail, case["detail"])

    def test_every_cache_case_holds(self):
        for case in swift_rules("cacheCases"):
            with self.subTest(case=case["name"]):
                shutil.rmtree(self.space.cache_root, ignore_errors=True)
                self.space.page("Strings.md", OPTED + f"```swift run\n{BLOCK_ONE}\n```\n")
                key = swift_blocks.key_of(BLOCK_ONE)
                if case["entry"] is not None:
                    self.space.cache().mkdir(parents=True, exist_ok=True)
                    (self.space.cache() / f"{key}.json").write_text(json.dumps(case["entry"]))
                planned = swift_blocks.plan(self.space.course, self.space.cache_root,
                                            full_rebuild=case["fullRebuild"], windows=False)
                self.assertEqual(planned["count"] == 1, case["compiledAgain"])

    def test_a_large_program_is_named_on_a_note_line(self):
        notes = swift_rules("notes")
        for case in swift_rules("noteCases"):
            if "bytes" not in case:
                continue
            with self.subTest(case=case["name"]):
                self.space.said.clear()
                shutil.rmtree(self.space.cache_root, ignore_errors=True)
                self.space.compiled(BLOCK_ONE, sdk="full", data=b"\0asm" + b"x" * (case["bytes"] - 4))
                outcome = self.space.prepare([PrepareTests.page(f"```swift run\n{BLOCK_ONE}\n```\n")])
                lines = [line for line in self.space.said if line.startswith("plantoir: note:")]
                if case["note"]:
                    want = "plantoir: note: Units/Strings.md: swift block 1: " + notes["large"].replace("{megabytes}", case["megabytes"])
                    self.assertEqual(lines, [want])
                else:
                    self.assertEqual(lines, [])
                self.assertEqual(outcome["problems"], [], "a note is not a folder problem")

    def test_the_previous_recipes_compile_error_is_still_a_compile_error(self):
        """The fixes review's nit 5: after a recipe change with too little
        room, a block the previous recipe could not compile is said as a
        compile error, not as lack of room."""
        old = self.space.cache_root / "0123456789abcdef"
        old.mkdir(parents=True)
        key = swift_blocks.key_of(BLOCK_ONE)
        (old / f"{key}.json").write_text(json.dumps({"ok": False, "reason": "compileError",
                                                     "diagnostics": "main.swift:1:7: error: cannot find 'nmae' in scope"}))
        (self.space.cache_root / swift_blocks.STATE_FILE).write_text('{"state": "noRoom"}')
        outcome = self.space.prepare([PrepareTests.page(f"```swift run\n{BLOCK_ONE}\n```\n")])
        self.assertEqual([problem["reason"] for problem in outcome["problems"]], ["compileError"])
        self.assertEqual(outcome["problems"][0]["said"], "cannot find 'nmae' in scope")

    def test_the_previous_recipes_program_is_served_until_this_one_compiles(self):
        case = [case for case in swift_rules("noteCases") if case.get("served")][0]
        old = self.space.cache_root / "0123456789abcdef"
        old.mkdir(parents=True)
        bodies = [BLOCK_ONE, BLOCK_TWO][:case["fromBefore"]]
        for body in bodies:
            key = swift_blocks.key_of(body)
            (old / f"{key}.wasm").write_bytes(b"\0asm old")
            (old / f"{key}.json").write_text(json.dumps({"ok": True, "sdk": "embedded"}))
        page = "".join(f"```swift run\n{body}\n```\n" for body in bodies)
        outcome = self.space.prepare([PrepareTests.page(page)])
        self.assertEqual(outcome["problems"], [])
        self.assertEqual(outcome["fromBefore"], case["fromBefore"])
        self.assertEqual(sorted(path.read_bytes() for path in self.space.static().iterdir()),
                         [b"\0asm old"] * case["fromBefore"])
        notes = [line for line in self.space.said if line.startswith("plantoir: note:")]
        self.assertEqual(notes, ["plantoir: note: " + swift_rules("notes", "fromBefore").replace(
            "{count}", str(case["fromBefore"]))])
        self.assertTrue(old.exists(), "the old folder is kept while it is still being served")


class RecipeTests(unittest.TestCase):
    """The Swift image's recipe holds every pin and flag the contract names."""

    @classmethod
    def setUpClass(cls):
        use_the_repository_contract()
        cls.dockerfile = (REPO / "support" / "swift" / "Dockerfile").read_text(encoding="utf-8")
        cls.compile_py = (REPO / "support" / "swift" / "compile.py").read_text(encoding="utf-8")
        cls.image = contracts.section("toolchain", "swiftImage")

    def test_every_pin_is_in_the_swift_dockerfile(self):
        self.assertGreaterEqual(len(self.image["pins"]), 6)
        for pin in self.image["pins"]:
            with self.subTest(pin=pin["pin"]):
                self.assertIn(pin["recipeContains"], self.dockerfile)
                if "url" in pin:
                    self.assertIn(pin["url"], self.dockerfile)

    def test_the_image_is_not_under_pins(self):
        names = [pin["pin"] for pin in contracts.section("toolchain", "pins")]
        for pin in self.image["pins"]:
            self.assertNotIn(pin["pin"], names)
        self.assertEqual(self.image["recipe"], "support/swift")

    def test_downloads_are_chosen_by_the_architecture(self):
        self.assertIn("ARG TARGETARCH", self.dockerfile)
        self.assertEqual(self.dockerfile.count('case "$TARGETARCH" in'), 2)

    def test_the_sdk_is_installed_from_a_checked_local_file(self):
        """Spike G1: `swift sdk install <url>` crashes on Linux 6.4.0."""
        self.assertIn("swift sdk install /tmp/wasm-sdk.tar.gz --swift-sdks-path /opt/swift-sdks", self.dockerfile)
        self.assertNotIn("swift sdk install http", self.dockerfile)
        self.assertIn('echo "$WASM_SDK_SHA256  /tmp/wasm-sdk.tar.gz" | sha256sum -c -', self.dockerfile)

    def test_wasm_opt_is_never_on_path(self):
        """Phase 0 trap 1: clang runs any wasm-opt on PATH by itself."""
        for line in self.dockerfile.splitlines():
            if line.startswith("ENV") and "PATH" in line:
                self.assertNotIn("binaryen", line)

    def test_the_toolchain_is_trimmed_in_the_layer_that_unpacks_it(self):
        """#493 ruling Q2, review S10: the trim in the same RUN, after the SDK install."""
        unpack = self.dockerfile.index("tar -xzf /tmp/swift.tar.gz")
        install = self.dockerfile.index("swift sdk install /tmp/wasm-sdk.tar.gz")
        trim = self.dockerfile.index("rm -rf bin/lldb")
        self.assertLess(unpack, install)
        self.assertLess(install, trim)
        self.assertNotIn("\nRUN ", self.dockerfile[unpack:trim])

    def test_compile_py_holds_every_flag_the_contract_names(self):
        for text in swift_rules("compile", "mustContain"):
            with self.subTest(text=text):
                self.assertIn(text, self.compile_py)
        self.assertIn(f"MAX_MEMORY = {swift_rules('compile', 'maxMemoryBytes')}", self.compile_py)
        self.assertIn(f"JOB_SECONDS = {swift_rules('compile', 'jobSeconds')}", self.compile_py)
        self.assertIn(swift_rules("compile", "placeholder"), self.compile_py)

    def test_the_language_row_is_prebuilt_and_read_only(self):
        row = page_features.RUNNER_LANGUAGES[swift_blocks.FENCE]
        self.assertTrue(row["prebuilt"])
        self.assertFalse(row["editable"])
        self.assertTrue((REPO / "support" / "gated" / row["engine"] / row["worker"]).is_file())
        self.assertTrue((REPO / "support" / "gated" / row["engine"] / "plantoir-wasi.mjs").is_file())


FAKE_SWIFTC = r'''#!{python}
# A stand-in for swiftc: "compiles" by copying the sources into the object,
# "links" by copying the object (adding the placeholder sentence when an
# Embedded link is given code that asks for it), and fails as the code says.
import sys
from pathlib import Path
args = sys.argv[1:]
out = Path(args[args.index("-o") + 1])
embedded = "Embedded" in args
if "-c" in args:
    sources = [a for a in args if a.endswith(".swift")]
    text = "".join(Path(s).read_text() for s in sources)
    if "KILLED" in text:
        import os, signal
        os.kill(os.getpid(), signal.SIGKILL)
    if "SILENT_FAIL" in text:
        sys.exit(1)
    if "ECHO_ERROR" in text:
        # As swiftc does: the error, with the code around it echoed.
        print("main.swift:1:7: error: cannot find 'killedCount' in scope\n" + text, file=sys.stderr)
        sys.exit(1)
    if "ECHO_WARNING" in text:
        print("main.swift:1:5: warning: variable was never mutated\n" + text, file=sys.stderr)
    if "BOTH_FAIL" in text or ("EMBEDDED_FAILS" in text and embedded):
        print("main.swift:2:7: error: cannot find 'nmae' in scope", file=sys.stderr)
        sys.exit(1)
    out.write_text(text)
else:
    objects = [a for a in args if a.endswith(".o")]
    text = "".join(Path(o).read_text() for o in objects)
    if "PLACEHOLDER" in text and embedded:
        text += "cannot print value in embedded Swift"
    out.write_text(("EMBEDDED " if embedded else "FULL ") + text)
'''

FAKE_TOOL = r'''#!{python}
# A stand-in for wasm-opt and clang: copies its input to -o, or fails when
# the code asks it to.
import sys
from pathlib import Path
args = sys.argv[1:]
out = Path(args[args.index("-o") + 1])
inputs = [a for a in args[:args.index("-o")] if not a.startswith("-") and Path(a).is_file()]
text = "".join(Path(i).read_text(errors="replace") for i in inputs)
if "OPT_FAILS" in text:
    print("wasm-opt: something broke", file=sys.stderr)
    sys.exit(1)
out.write_text(text)
'''


@unittest.skipIf(os.name == "nt", "the stand-in tools are scripts with a #! line")
class CompileStepTests(unittest.TestCase):
    """support/swift/compile.py's choices, with stand-ins for swiftc, clang
    and wasm-opt (codeRunnerBlocks.swift.compile and cache): Embedded first;
    the full library when Embedded does not compile or would print its
    placeholder; a compile error cached with the compiler's words; a failure
    that is not the compiler's never cached (review S3); the jobs folder
    removed. The real compiler is verify.sh's Swift gate."""

    def setUp(self):
        import importlib.util
        import sys
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-swift-compile-"))
        tools = self.folder / "tools"
        tools.mkdir()
        for name, body in (("swiftc", FAKE_SWIFTC), ("clang", FAKE_TOOL), ("wasm-opt", FAKE_TOOL)):
            path = tools / name
            path.write_text(body.replace("{python}", sys.executable), encoding="utf-8")
            path.chmod(0o755)
        self.saved = {name: os.environ.get(name) for name in ("PLANTOIR_SWIFTC", "PLANTOIR_SWIFT_SDK", "PLANTOIR_WASM_OPT")}
        os.environ["PLANTOIR_SWIFTC"] = str(tools / "swiftc")
        os.environ["PLANTOIR_SWIFT_SDK"] = str(self.folder / "sdk")
        os.environ["PLANTOIR_WASM_OPT"] = str(tools / "wasm-opt")
        spec = importlib.util.spec_from_file_location("plantoir_compile", REPO / "support" / "swift" / "compile.py")
        self.compile = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.compile)
        self.compile.OBJECT_ROOT = self.folder / "objects"
        self.jobs = self.folder / "jobs"
        self.jobs.mkdir()
        self.out = self.folder / "out"

    def tearDown(self):
        for name, value in self.saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
        shutil.rmtree(self.folder, ignore_errors=True)

    def job(self, key, code):
        (self.jobs / f"{key}.swift").write_text(code + "\n", encoding="utf-8")

    def entry(self, key):
        path = self.out / f"{key}.json"
        return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None

    def test_each_block_takes_the_library_it_needs(self):
        self.job("a" * 64, 'print("plain")')
        self.job("b" * 64, 'print([1]) // PLACEHOLDER')
        self.job("c" * 64, 'let x = 1 // EMBEDDED_FAILS')
        self.job("d" * 64, 'print(nmae) // BOTH_FAIL')
        self.assertEqual(self.compile.main(["compile.py", str(self.jobs), str(self.out)]), 0)
        self.assertEqual(self.entry("a" * 64)["sdk"], "embedded")
        self.assertTrue((self.out / ("a" * 64 + ".wasm")).read_text().startswith("EMBEDDED "))
        self.assertEqual(self.entry("b" * 64)["sdk"], "full", "the placeholder means the full library")
        self.assertTrue((self.out / ("b" * 64 + ".wasm")).read_text().startswith("FULL "))
        self.assertEqual(self.entry("c" * 64)["sdk"], "full", "Embedded refusing means the full library")
        broken = self.entry("d" * 64)
        self.assertEqual((broken["ok"], broken["reason"]), (False, "compileError"))
        self.assertIn("main.swift:2:7: error: cannot find 'nmae' in scope", broken["diagnostics"])
        self.assertFalse((self.out / ("d" * 64 + ".wasm")).exists())
        self.assertFalse(self.jobs.exists(), "the run's job folder is removed")

    def test_a_failure_that_is_not_the_compilers_is_never_cached(self):
        self.job("e" * 64, 'print("x") // OPT_FAILS')
        self.job("f" * 64, 'print("x") // KILLED')
        self.job("0" * 64, 'print("x") // SILENT_FAIL')
        self.compile.main(["compile.py", str(self.jobs), str(self.out)])
        self.assertIsNone(self.entry("e" * 64), "a wasm-opt failure was cached as the code's fault")
        self.assertFalse((self.out / ("e" * 64 + ".wasm")).exists())
        self.assertIsNone(self.entry("f" * 64), "a compiler killed by a signal was cached as the code's fault")
        self.assertIsNone(self.entry("0" * 64), "a failure with no diagnostics was cached as the code's fault")
        self.assertEqual(list(self.out.glob(".*.tmp")), [], "a temporary file was left behind")

    def test_code_that_says_killed_is_not_a_killed_compiler(self):
        """The fixes review's F1: the compiler echoes the student's code, so
        'killed' or 'terminated due to signal' in a variable, a string or a
        comment must not read as a compiler that was killed."""
        warned = "1" * 64
        failed = "2" * 64
        self.job(warned, 'var enemiesKilled = 0 // the game was terminated due to signal 9 // ECHO_WARNING\nprint("Killed: \\(enemiesKilled)")')
        self.job(failed, 'print(killedCount) // Killed, terminated due to signal // ECHO_ERROR')
        self.compile.main(["compile.py", str(self.jobs), str(self.out)])
        self.assertEqual(self.entry(warned)["sdk"], "embedded", "a warning that echoes 'killed' code was taken for a kill")
        broken = self.entry(failed)
        self.assertIsNotNone(broken, "an error naming killedCount was taken for a kill and not cached")
        self.assertIn("cannot find 'killedCount' in scope", broken["diagnostics"])


class PruneKeepsTheLogsTests(unittest.TestCase):
    def test_a_prune_keeps_the_launchers_logs(self):
        # #570: every prune used to remove logs/ with the old toolchains'
        # folders, so a launcher's compile log never survived its own build.
        root = Path(tempfile.mkdtemp(prefix="plantoir-swift-prune-"))
        try:
            for name in ("0123456789abcdef", "fedcba9876543210", swift_blocks.LOGS_FOLDER, swift_blocks.JOBS_FOLDER):
                (root / name).mkdir()
            swift_blocks.prune(root, "fedcba9876543210", time.time())
            self.assertEqual(sorted(path.name for path in root.iterdir()),
                             sorted(["fedcba9876543210", swift_blocks.LOGS_FOLDER, swift_blocks.JOBS_FOLDER]))
        finally:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()

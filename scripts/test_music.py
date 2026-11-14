#!/usr/bin/env python3
"""
Tunes from a page's ```abc fences (#679), against the CONTRACT.

The cases are not retyped here. They are deserialised from
`contracts/shared-rules.json` -> `musicFences` (fences, settings, sounds,
percentPercent, describe, lines, siteCarries), `keptDownloads` (the kind
`sounds`) and `siteHealth.checks` (musicTunesNotRight), and from
`contracts/toolchain.json` -> pins (abcjs, linkedom, fluidR3Sounds).

No sound set is ever asked: a local server of the test's own answers small
stand-in sound files, whose SHA-256s the test pins in place of the real
ones, and counts what it was asked. The drawing is done by a stand-in helper
(a few lines of Python speaking the helper's protocol), so this file needs
no Node and runs in Windows' PythonToolchainTests too. The REAL helper and
abcjs are run by RealEngineTests when the engine is installed (in the image,
or PLANTOIR_VENDOR_DIR naming a folder holding music-engine/), and by
scripts/check_music_rules_against_the_site.py in the image; elsewhere those
tests SKIP, saying so.

Run with:

    python3 scripts/test_music.py
"""
import base64
import hashlib
import http.server
import json
import os
import shutil
import sys
import tempfile
import threading
import unittest
from pathlib import Path

import contracts
import kept_downloads
import markdown_code
import music
import section_problems
import site_health
import toolchain_paths

REPO = Path(__file__).resolve().parent.parent


def use_the_repository_contract():
    repo_contracts = REPO / "contracts"
    if repo_contracts.is_dir():
        toolchain_paths.CONTRACTS_DIR = repo_contracts
    contracts.reset_cache()


def rules(*keys):
    return contracts.section("shared-rules", "musicFences", *keys)


# ---- Stand-ins ------------------------------------------------------------------

FAKE_HELPER = r'''
import json, re, sys
print(json.dumps({"ready": True, "abcjs": "stand-in"}), flush=True)
for line in sys.stdin:
    job = json.loads(line)
    abc = job["abc"]
    if not abc.strip():
        print(json.dumps({"id": job["id"], "ok": False, "reason": "nothingToDraw", "said": ""}), flush=True)
        continue
    programs = sorted({int(n) for n in re.findall(r"(?m)^%%MIDI program (\d+)$", abc)} or {0})
    if '"' in abc and "%%MIDI chordprog" not in abc:
        programs = sorted(set(programs) | {0})
    warnings = []
    for number, text in enumerate(abc.split("\n"), start=1):
        if "[" in text and "]" not in text:
            warnings.append({"line": number, "column": 1, "said": "Expected ']' to end the chords"})
    # Width as abcjs answers it, roughly: 770 for a line it can fit, 77 a
    # bar beyond ten bars on one line; abcjs's wrap fits any line that has
    # bar lines, never one without (musicFences.drawing.wrap).
    widest = 770
    wrapping = isinstance(job.get("options"), dict) and "wrap" in job["options"]
    for text in abc.split("\n"):
        bars = text.count("|")
        if wrapping and bars > 0:
            continue
        widest = max(widest, 77 * bars, 13 * len(text.replace(" ", "")) if bars == 0 and len(text) > 60 else 0)
    print(json.dumps({"id": job["id"], "ok": True, "notes": abc.count(" ") + 1, "staffLines": 1, "width": widest,
                      "wrapped": wrapping,
                      "html": '<div class="abcjs-container"><svg class="stand-in"></svg></div>',
                      "programs": programs, "warnings": warnings}), flush=True)
'''


def a_sound_file(name: str) -> bytes:
    """A stand-in `<name>-mp3.js`: the sound set's shape, two notes."""
    one = base64.b64encode(("note A4 of " + name).encode()).decode()
    two = base64.b64encode(("note Bb4 of " + name).encode()).decode()
    return ("if (typeof(MIDI) === 'undefined') var MIDI = {};\n"
            "if (typeof(MIDI.Soundfont) === 'undefined') MIDI.Soundfont = {};\n"
            f"MIDI.Soundfont.{name} = {{\n"
            f'"A4": "data:audio/mp3;base64,{one}",\n'
            f'"Bb4": "data:audio/mp3;base64,{two}",\n'
            "}\n").encode("ascii")


class FakeSounds:
    """A local server answering as the sound set's host does, in a mood:
    answers, wrongFile, notFound."""

    def __init__(self, mood="answers"):
        self.mood = mood
        self.asked = []
        fake = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                fake.asked.append(self.path)
                name = self.path.rsplit("/", 1)[-1][:-len("-mp3.js")]
                if fake.mood == "notFound" or not self.path.endswith("-mp3.js"):
                    body, status = b"", 404
                elif fake.mood == "wrongFile":
                    body, status = b"<html>Sign in to the school network</html>", 200
                else:
                    body, status = a_sound_file(name), 200
                self.send_response(status)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}/FluidR3_GM"

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def stand_in_pin(base: str) -> dict:
    """The real pin's names, files and spelling, with the stand-in files'
    hashes: what the test's own server answers."""
    real = music.sound_pin()
    files = {}
    for name, entry in real["files"].items():
        data = a_sound_file(entry["file"][:-len("-mp3.js")])
        files[name] = {"file": entry["file"], "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    return dict(real, base=base, files=files)


def page(text, place="Unit 1/Scales"):
    return {"place": place, "text": text, "source": text, "path": place + ".md"}


SCALE = "X:1\nT:G major scale\nM:4/4\nL:1/4\nK:G\nG A B c | d e f g |]\n"


class Scratch(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()
        self.root = Path(tempfile.mkdtemp(prefix="plantoir-music-"))
        self.output = self.root / "section1"
        (self.output / "quartz" / "static").mkdir(parents=True)
        self.kept = self.root / "builds" / ".downloaded"
        self.helper = self.root / "helper.py"
        self.helper.write_text(FAKE_HELPER, encoding="utf-8")
        self.vendor = self.root / "vendor"
        dist = self.vendor / music.ENGINE_FOLDER / "node_modules" / "abcjs" / "dist"
        dist.mkdir(parents=True)
        (dist / music.ENGINE_FILE).write_text("/* abcjs stand-in */", encoding="utf-8")
        (dist.parent / "LICENSE.md").write_text("MIT stand-in", encoding="utf-8")
        self.servers = []
        self.real_pin = music.sound_pin

    def tearDown(self):
        music.sound_pin = self.real_pin
        for server in self.servers:
            server.close()
        shutil.rmtree(self.root, ignore_errors=True)

    def sounds(self, mood="answers"):
        server = FakeSounds(mood)
        self.servers.append(server)
        pin = stand_in_pin(server.base)
        music.sound_pin = lambda: pin
        return server

    def fetcher(self):
        return kept_downloads.Fetcher(["127.0.0.1"], schemes=("http",), timeout=5)

    def prepare(self, pages, fetcher=None, kept=None, **more):
        lines = []
        outcome = music.prepare(pages, self.output, self.kept if kept is None else kept, course="AMU1O",
                                section=1, fetcher=fetcher or self.fetcher(),
                                command=[sys.executable, str(self.helper)], vendor_dir=self.vendor,
                                printer=lines.append, **more)
        return outcome, lines

    def site_folder(self) -> Path:
        return self.output / "quartz" / "static" / music.SITE_FOLDER


# ---- musicFences.fences --------------------------------------------------------------

class FenceTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()

    def test_every_fences_case(self):
        for case in rules("fences", "cases"):
            with self.subTest(case["name"]):
                found = music.tunes_on_page(case["page"])
                self.assertEqual([{"block": t["block"], "line": t["line"], "lang": t["lang"]} for t in found],
                                 case["tunes"])

    def test_every_page_with_a_tune_is_one_the_scan_keeps(self):
        root = Path(tempfile.mkdtemp(prefix="plantoir-music-scan-"))
        try:
            for index, case in enumerate(rules("fences", "cases")):
                (root / f"page{index}.md").write_text(case["page"], encoding="utf-8")
            pages = music.pages_students_see(root, lambda text: False, lambda path: path.stem, lambda path: None)
            kept = {Path(entry["path"]).stem for entry in pages}
            for index, case in enumerate(rules("fences", "cases")):
                if case["tunes"]:
                    self.assertIn(f"page{index}", kept, case["name"])
        finally:
            shutil.rmtree(root, ignore_errors=True)

    def test_the_languages_are_the_transformers(self):
        source = (REPO / "support" / "quartz" / "plugins" / "transformers" / "plantoirMusic.ts").read_text(
            encoding="utf-8")
        self.assertIn("const LANGUAGES = " + json.dumps(rules("fences", "languages")), source)


# ---- musicFences.settings, sounds, describe, lines ---------------------------------------

class SettingsAndSoundTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()

    def test_every_settings_case(self):
        for case in rules("settings", "cases"):
            with self.subTest(case["name"]):
                read = music.read_settings(case["body"])
                for key, value in case["expect"].items():
                    self.assertEqual(read[key], value, key)
                self.assertEqual(read["notes"], case["notes"])

    def test_every_sound_case(self):
        for case in rules("sounds", "cases"):
            with self.subTest(case["value"]):
                self.assertEqual(music.program_of(case["value"]), case["program"])
                if "near" in case:
                    self.assertIn(case["near"], music.nearest_sounds(case["value"]))

    def test_there_are_128_sounds_and_every_alias_names_one(self):
        names = music.sound_names()
        self.assertEqual(len(names), 128)
        self.assertEqual(len(set(names)), 128)
        for alias, target in rules("sounds", "aliases").items():
            self.assertIn(target, names, alias)

    def test_every_emitted_case(self):
        for case in rules("sounds", "emitted"):
            with self.subTest(case["name"]):
                played = music.tune_as_played(case["body"], music.read_settings(case["body"]))
                self.assertEqual(played["abc"], case["abc"])
                self.assertEqual(played["problems"], case["problems"])
                # Every line the build did not add maps to its own fence line.
                body_lines = case["body"].split("\n")
                for emitted, came_from in zip(played["abc"].split("\n"), played["from"]):
                    if came_from is None:
                        self.assertTrue(emitted.startswith("%%MIDI "))
                    else:
                        self.assertEqual(emitted, body_lines[came_from - 1])

    def test_every_describe_case(self):
        for case in rules("describe", "cases"):
            with self.subTest(case["body"][:30]):
                self.assertEqual(music.description(case["body"], music.read_settings(case["body"])), case["alt"])

    def test_every_lines_case(self):
        for case in rules("lines", "cases"):
            with self.subTest(case["name"]):
                played = music.tune_as_played(case["body"], music.read_settings(case["body"]))
                found = {"place": "P", "block": 1, "key": "k", "fileLine": case["openingLine"]}
                problems = music._tune_problems(found, played, {"warnings": [
                    {"line": case["abcjsLine"], "column": 1, "said": "x"}]})
                located = music._located(found, problems[0])
                self.assertEqual(located["line"], case["pageLine"])

    def test_every_percent_percent_case(self):
        for case in rules("percentPercent", "cases"):
            with self.subTest(case["name"]):
                found = music.tunes_on_page(case["page"])
                self.assertEqual(music.percent_percent_lines(case["page"], found[0]["line"]), case["lines"])

    def test_every_reason_and_site_word_is_written(self):
        said = music.words()
        for reason in ("percentPercentLine", "unknownSound", "unknownSoundNear", "abcSaid", "abcSaidMore", "noKey",
                       "emptyTune", "engineMissing", "drawingStopped", "tuneNotDrawn", "settingAfterTheTune",
                       "moreThanOneTune"):
            self.assertTrue(said["reasons"].get(reason), reason)
        for word in ("play", "stop", "playLabel", "stopLabel", "gettingReady", "couldNotPlay", "untitledTune"):
            self.assertTrue(said["site"].get(word), word)
        self.assertIn("% sound:", said["reasons"]["percentPercentLine"])

    def test_no_example_names_the_sound_the_rules_keep_out_of_examples(self):
        # Russell's ruling of 2026-11-13: offered, never used or featured.
        cases = json.dumps({key: rules(key) for key in ("fences", "settings", "describe", "lines", "percentPercent",
                                                       "siteCarries")})
        emitted = json.dumps(rules("sounds", "emitted")) + json.dumps(rules("sounds", "cases"))
        for text in (cases, emitted, json.dumps(rules("sounds", "aliases"))):
            self.assertNotIn("gunshot", text.lower())


# ---- Pins and the sound file -----------------------------------------------------------

class PinTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()
        self.pins = {pin["pin"]: pin for pin in contracts.load("toolchain")["pins"]}

    def test_the_package_and_lockfile_hold_the_pinned_versions(self):
        package = json.loads((REPO / "support" / "music" / "package.json").read_text(encoding="utf-8"))
        lock = json.loads((REPO / "support" / "music" / "package-lock.json").read_text(encoding="utf-8"))
        for name in ("abcjs", "linkedom"):
            version = self.pins[name]["value"]
            self.assertEqual(package["dependencies"][name], version)
            self.assertEqual(lock["packages"][f"node_modules/{name}"]["version"], version)
            self.assertIn(f"{name}@{version}", self.pins[name]["dockerfileContains"])
        self.assertEqual(rules("engine", "version"), self.pins["abcjs"]["value"])

    def test_windows_runtime_is_watched_for_both_engine_pins(self):
        # Plan section 8: Windows' ToolchainContractTests are red until its
        # runtime recipe names these, which is the contract asking.
        for name in ("abcjs", "linkedom"):
            self.assertEqual(self.pins[name].get("windowsRuntimeContains"), f"{name}@{self.pins[name]['value']}")

    def test_the_dockerfile_installs_the_engine(self):
        dockerfile = (REPO / "Dockerfile").read_text(encoding="utf-8")
        for name in ("abcjs", "linkedom"):
            self.assertIn(self.pins[name]["dockerfileContains"], dockerfile)
        self.assertIn("/opt/vendor/" + music.ENGINE_FOLDER, dockerfile)

    def test_every_sound_is_pinned_by_its_one_file(self):
        pin = self.pins["fluidR3Sounds"]
        names = music.sound_names()
        self.assertEqual(sorted(pin["files"]), sorted(names + ["percussion"]))
        self.assertEqual(pin["fileCount"], len(pin["files"]))
        total = 0
        for name, entry in pin["files"].items():
            self.assertRegex(entry["sha256"], r"^[0-9a-f]{64}$", name)
            self.assertTrue(entry["file"].endswith("-mp3.js"), name)
            self.assertTrue(kept_downloads.safe_name(name), name)
            total += entry["bytes"]
        self.assertEqual(total, pin["bytes"])
        self.assertEqual(pin["files"]["lead_8_bass_lead"]["file"], "lead_8_bass__lead-mp3.js")
        self.assertTrue(pin["base"].startswith("https://raw.githubusercontent.com/"))
        self.assertIn(pin["value"], pin["base"])
        self.assertEqual(rules("download", "hosts"), ["raw.githubusercontent.com"])
        self.assertTrue(pin["value"].startswith(pin["version"]))

    def test_a_sound_file_decodes_into_the_notes_abcjs_asks_for(self):
        notes = music.notes_of(a_sound_file("flute"))
        self.assertEqual(sorted(notes), ["A4.mp3", "Bb4.mp3"])
        self.assertEqual(notes["A4.mp3"], b"note A4 of flute")
        with self.assertRaises(ValueError):
            music.notes_of(b"<html>Sign in</html>")


# ---- keptDownloads, kind sounds ---------------------------------------------------------

class KindTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()

    def test_the_kind_is_in_the_kept_downloads_rules(self):
        kind = contracts.section("shared-rules", "keptDownloads", "kinds", music.KIND)
        self.assertEqual(kind["fences"], "musicFences")
        self.assertEqual(kept_downloads.what(music.KIND, 1), kind["one"])
        self.assertEqual(kept_downloads.what(music.KIND, 3), "3 " + kind["several"])

    def test_the_app_explains_the_sounds_stop_from_what_this_prints(self):
        # Plan review MUST 4: app-rules.json -> failureExplanations holds a
        # case for the sounds stop, and its output is exactly what
        # music.stop_lines prints for it, so the apps' explainers are tested
        # against the real lines.
        cases = contracts.load("app-rules")["failureExplanations"]["cases"]
        ours = [case for case in cases if '"kind":"sounds"' in case["output"]]
        self.assertEqual(len(ours), 1)
        missing = []
        for line in ours[0]["output"].split("\n")[1:]:
            if line.startswith("   "):
                item, page = line.strip()[1:-1].split("” on “")
                missing.append({"item": item, "page": page})
        course, section = "AMU1O", 1
        printed = music.stop_lines({"stop": {"reason": "offline", "missing": missing}}, course, section)
        self.assertEqual(ours[0]["output"], "\n".join(printed))
        self.assertTrue(ours[0]["expect"].startswith(printed[0][len("❌ "):]))

    def test_the_credit_links_the_licence_the_sound_set_names(self):
        # The sound set's README at the pinned commit names "Creative Commons
        # Attribution 3.0 license" and links the United States port.
        credit = rules("credit")
        self.assertEqual(credit["licenceUrl"], "https://creativecommons.org/licenses/by/3.0/us/")
        self.assertIn(credit["licenceName"], credit["sentence"])
        self.assertEqual(credit["licenceName"], "CC BY 3.0 US")

    def test_the_stop_line_is_the_kept_downloads_one(self):
        lines = kept_downloads.stop_lines(music.KIND, "AMU1O", 1, [{"item": "flute", "page": "Unit 1/Scales"}],
                                          "offline")
        self.assertTrue(lines[0].startswith("❌ AMU1O Section 1 was not built: "))
        self.assertIn("GitHub", lines[0])
        self.assertIn("a sound", lines[0])
        self.assertEqual(lines[1], "   “flute” on “Unit 1/Scales”")


# ---- The whole pass ---------------------------------------------------------------------

class PrepareTests(Scratch):
    def test_every_site_carries_case(self):
        for case in rules("siteCarries", "cases"):
            with self.subTest(case["name"]):
                self.sounds()
                shutil.rmtree(self.output / "quartz", ignore_errors=True)
                (self.output / "quartz" / "static").mkdir(parents=True)
                content = self.root / "content" / case["name"].replace(" ", "-").replace(":", "")
                for index, about in enumerate(case["pages"]):
                    body = about["page"] if "page" in about else "```abc\n" + about["body"] + "```\n"
                    text = ("---\npublish: false\n---\n" if about["hidden"] else "") + body
                    (content / f"Tune {index}.md").parent.mkdir(parents=True, exist_ok=True)
                    (content / f"Tune {index}.md").write_text(text, encoding="utf-8")
                content.mkdir(parents=True, exist_ok=True)
                pages = music.pages_students_see(content, lambda text: "publish: false" in text,
                                                 lambda path: path.stem, lambda path: None)
                outcome, _ = self.prepare(pages)
                self.assertIsNone(outcome["stop"])
                self.assertEqual(self.site_folder().exists(), case["carries"])
                if case["carries"]:
                    carried = sorted(path.name[:-len("-mp3")] for path in (self.site_folder() / "sounds").iterdir())
                    self.assertEqual(carried, case["sounds"])
                    self.assertTrue((self.site_folder() / music.ENGINE_FILE).is_file())
                    self.assertTrue((self.site_folder() / "LICENSE.md").is_file())
                    readme = (self.site_folder() / "README.txt").read_text(encoding="utf-8")
                    self.assertIn(rules("credit", "sentence"), readme)
                workspace = self.output / "quartz" / music.WORKSPACE / "manifest.json"
                self.assertEqual(workspace.is_file(), any(not about["hidden"] for about in case["pages"]))

    def test_a_flute_tune_with_chords_carries_flute_only(self):
        self.sounds()
        outcome, _ = self.prepare([page("```abc\n% sound: flute\nX:1\nK:G\n\"G\"G A B c|]\n```\n")])
        self.assertEqual(outcome["sounds"], ["flute"])

    def test_the_second_build_uses_the_kept_copy_and_asks_nothing(self):
        server = self.sounds()
        first, _ = self.prepare([page("```abc\n% sound: flute\n" + SCALE + "```\n")])
        self.assertEqual(first["downloaded"], ["flute"])
        self.assertEqual(len(server.asked), 1)
        second, _ = self.prepare([page("```abc\n% sound: flute\n" + SCALE + "```\n")])
        self.assertEqual(second["downloaded"], [])
        self.assertEqual(second["fromBefore"], ["flute"])
        self.assertEqual(len(server.asked), 1)
        self.assertEqual(music.downloaded_line(second, "AMU1O", 1), None)
        self.assertTrue(music.downloaded_line(first, "AMU1O", 1).startswith(kept_downloads.MARKER))

    def test_a_kept_copy_changed_on_disk_is_thrown_away_and_downloaded_again(self):
        server = self.sounds()
        self.prepare([page("```abc\n" + SCALE + "```\n")])
        kept = next((self.kept / music.KIND / "acoustic_grand_piano").rglob("*-mp3.js"))
        kept.write_bytes(b"changed")
        outcome, _ = self.prepare([page("```abc\n" + SCALE + "```\n")])
        self.assertEqual(outcome["downloaded"], ["acoustic_grand_piano"])
        self.assertEqual(len(server.asked), 2)

    def test_offline_stops_naming_the_sound_and_every_page(self):
        self.sounds()
        music.sound_pin = (lambda pin: (lambda: dict(pin, base="http://127.0.0.1:9/FluidR3_GM")))(music.sound_pin())
        outcome, _ = self.prepare([page("```abc\n% sound: flute\n" + SCALE + "```\n"),
                                   page("```abc\n% sound: flute\n" + SCALE + "```\n", place="Unit 2/Rhythm")])
        self.assertEqual(outcome["stop"]["reason"], "offline")
        self.assertEqual(outcome["stop"]["missing"], [{"item": "flute", "page": "Unit 1/Scales"},
                                                      {"item": "flute", "page": "Unit 2/Rhythm"}])
        self.assertFalse(self.site_folder().exists())
        self.assertFalse((self.output / "quartz" / music.WORKSPACE).exists())
        lines = music.stop_lines(outcome, "AMU1O", 1)
        self.assertIn("a sound", lines[0])
        self.assertEqual(json.loads(lines[-1][len(kept_downloads.MARKER):]),
                         {"kind": "sounds", "course": "AMU1O", "section": 1, "failed": 1, "reason": "offline"})

    def test_a_file_that_is_not_the_pinned_one_is_damaged_and_never_kept(self):
        for mood in ("wrongFile", "notFound"):
            with self.subTest(mood):
                self.sounds(mood)
                outcome, _ = self.prepare([page("```abc\n" + SCALE + "```\n")])
                self.assertEqual(outcome["stop"]["reason"], "damaged")
                self.assertFalse((self.kept / music.KIND / "acoustic_grand_piano").exists())

    def test_with_nowhere_to_keep_it_the_build_uses_what_it_downloaded_once(self):
        self.sounds()
        lines = []
        outcome = music.prepare([page("```abc\n" + SCALE + "```\n")], self.output, None, course="AMU1O", section=1,
                                fetcher=self.fetcher(), command=[sys.executable, str(self.helper)],
                                vendor_dir=self.vendor, printer=lines.append)
        self.assertIsNone(outcome["stop"])
        self.assertTrue((self.site_folder() / "sounds" / "acoustic_grand_piano-mp3" / "A4.mp3").is_file())

    def test_a_misspelt_sound_is_a_problem_and_the_tune_plays_in_piano(self):
        self.sounds()
        outcome, lines = self.prepare([page("Intro\n\n```abc\n% sound: flut\n" + SCALE + "```\n")])
        self.assertEqual(outcome["sounds"], ["acoustic_grand_piano"])
        self.assertEqual([(p["reason"], p["line"], p["near"]) for p in outcome["problems"]],
                         [("unknownSound", 4, "flute, pan flute")])
        self.assertIn("plantoir: error: Unit 1/Scales.md: abc block 1, line 4: there is no sound called “flut”"
                      " (the closest: flute, pan flute)", lines)

    def test_a_percent_percent_line_is_a_problem_naming_its_line(self):
        self.sounds()
        outcome, _ = self.prepare([page("```abc\nX:1\nK:G\n%%MIDI program 73\nG2|]\n```\n")])
        self.assertIn(("percentPercentLine", 4), [(p["reason"], p["line"]) for p in outcome["problems"]])

    def test_an_empty_tune_stays_code_and_says_so(self):
        self.sounds()
        outcome, _ = self.prepare([page("```abc\n\n```\n")])
        self.assertEqual(outcome["shown"], 0)
        self.assertEqual([p["reason"] for p in outcome["problems"]], ["emptyTune"])
        self.assertFalse((self.output / "quartz" / music.WORKSPACE).exists())

    def test_a_missing_engine_is_a_problem_for_every_tune(self):
        self.sounds()
        lines = []
        outcome = music.prepare([page("```abc\n" + SCALE + "```\n```abc\n" + SCALE + "```\n")], self.output,
                                self.kept, fetcher=self.fetcher(), command=[str(self.root / "no-node-here")],
                                vendor_dir=self.vendor, printer=lines.append)
        self.assertEqual([p["reason"] for p in outcome["problems"]], ["engineMissing", "engineMissing"])
        self.assertIsNone(outcome["stop"])
        self.assertFalse(self.site_folder().exists())

    def test_what_abcjs_said_is_mapped_to_the_teachers_line(self):
        self.sounds()
        outcome, _ = self.prepare([page("Text\n\n```abc\n% sound: flute\nX:1\nK:G\nG A [B c|\n```\n")])
        said = [p for p in outcome["problems"] if p["reason"] == "abcSaid"]
        self.assertEqual(said[0]["line"], 7)

    def test_the_manifest_holds_the_tune_as_played_and_its_description(self):
        self.sounds()
        self.prepare([page("```abc\n% sound: flute\n% alt: A scale.\n" + SCALE + "```\n")])
        manifest = json.loads((self.output / "quartz" / music.WORKSPACE / "manifest.json").read_text(encoding="utf-8"))
        entry = next(iter(manifest["pages"]["Unit 1/Scales.md"].values()))
        self.assertEqual(entry["alt"], "A scale.")
        self.assertIn("%%MIDI program 73", entry["abc"])
        self.assertTrue(entry["play"])
        self.assertEqual(manifest["options"], rules("drawing", "options"))
        self.assertEqual(manifest["credit"], rules("credit"))

    def test_a_sound_no_tune_needs_any_more_leaves_the_site(self):
        self.sounds()
        self.prepare([page("```abc\n% sound: flute\n" + SCALE + "```\n")])
        self.assertTrue((self.site_folder() / "sounds" / "flute-mp3").is_dir())
        self.prepare([page("```abc\n" + SCALE + "```\n")])
        self.assertFalse((self.site_folder() / "sounds" / "flute-mp3").exists())
        self.prepare([])
        self.assertFalse(self.site_folder().exists())


    def test_a_tune_in_a_quiz_choice_has_no_play_and_downloads_nothing_even_offline(self):
        server = self.sounds()
        music.sound_pin = (lambda pin: (lambda: dict(pin, base="http://127.0.0.1:9/FluidR3_GM")))(music.sound_pin())
        quiz = ("> [!quiz] Which of these is a D major chord?\n> - [x] This one\n>   ```abc\n"
                ">   % sound: trumpet\n>   X:1\n>   K:D\n>   [DFA]4 |]\n>   ```\n> - [ ] Not this one\n")
        outcome, _ = self.prepare([page(quiz)])
        self.assertIsNone(outcome["stop"], "offline, a tune nothing can play must not stop the build")
        self.assertEqual((outcome["shown"], outcome["playable"], outcome["sounds"]), (1, 0, []))
        self.assertEqual(server.asked, [])
        manifest = json.loads((self.output / "quartz" / music.WORKSPACE / "manifest.json").read_text(encoding="utf-8"))
        entry = next(iter(manifest["pages"]["Unit 1/Scales.md"].values()))
        self.assertFalse(entry["play"])
        self.assertFalse(self.site_folder().exists())

    def test_a_tune_in_a_quizs_question_keeps_its_play(self):
        self.sounds()
        quiz = ("> [!quiz] Which chord is this?\n> ```abc\n> X:1\n> K:D\n> [DFA]4 |]\n> ```\n"
                "> - [x] D major\n> - [ ] G major\n")
        outcome, _ = self.prepare([page(quiz)])
        self.assertEqual((outcome["playable"], outcome["sounds"]), (1, ["acoustic_grand_piano"]))

    def test_every_layout_case(self):
        for case in rules("drawing", "readable", "cases"):
            with self.subTest(case["name"]):
                self.assertEqual(music.layout_of(case["width"], case["wrappedWidth"]),
                                 {"drawnWith": case["drawnWith"], "problem": case["problem"]})

    def test_a_tune_on_one_long_line_is_drawn_again_with_wrap_and_the_page_carries_its_options(self):
        self.sounds()
        long_line = "X:1\nT:Long\nM:4/4\nL:1/4\nK:D\n" + "D E F G | " * 240 + "]\n"
        outcome, _ = self.prepare([page("```abc\n" + long_line + "```\n" + "```abc\n" + SCALE + "```\n")])
        self.assertEqual(outcome["problems"], [])
        manifest = json.loads((self.output / "quartz" / music.WORKSPACE / "manifest.json").read_text(encoding="utf-8"))
        entries = list(manifest["pages"]["Unit 1/Scales.md"].values())
        self.assertEqual([entry["options"] for entry in entries], [rules("drawing", "wrap", "options"), None])

    def test_a_long_stretch_with_no_bar_line_is_a_problem_and_still_drawn(self):
        self.sounds()
        no_bars = "X:1\nT:No bars\nL:1/8\nK:C\n" + "CDEFGABc " * 20 + "\n"
        outcome, lines = self.prepare([page("Intro\n\n```abc\n" + no_bars + "```\n")])
        self.assertEqual(outcome["shown"], 1)
        self.assertEqual([(p["reason"], p["line"]) for p in outcome["problems"]], [("tooLongToRead", 3)])
        self.assertIn("plantoir: error: Unit 1/Scales.md: abc block 1, line 3: "
                      + rules("words", "reasons", "tooLongToRead"), lines)


class BuildStopTests(Scratch):
    def test_the_build_stops_before_anything_is_said_or_quartz_runs(self):
        import contextlib
        import inspect
        import io
        import build_site
        self.sounds()
        music.sound_pin = (lambda pin: (lambda: dict(pin, base="http://127.0.0.1:9/FluidR3_GM")))(music.sound_pin())
        outcome, _ = self.prepare([page("```abc\n" + SCALE + "```\n")])
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed), self.assertRaises(SystemExit) as stopped:
            build_site._stop_for_music(outcome, "AMU1O", 1)
        self.assertEqual(stopped.exception.code, 1)
        lines = [line for line in printed.getvalue().split("\n") if line.strip()]
        self.assertEqual(lines, music.stop_lines(outcome, "AMU1O", 1))
        source = inspect.getsource(build_site.build_section_site)
        stop_at = source.index("_stop_for_music(music_here")
        for later in ("site_health.announce_or_stay_quiet(", "wire_quartz_additions(output_dir)", '"bootstrap-cli.mjs"'):
            self.assertLess(stop_at, source.index(later), later)
        self.assertIn('"music_problems": music.health_finding_facts(music_here)', source)

    def test_a_fault_in_the_pass_stops_when_a_tune_has_play_and_never_names_pythons_class(self):
        import contextlib
        import io
        import build_site
        content = self.root / "content"
        content.mkdir(parents=True)
        (content / "Scales.md").write_text("```abc\n% sound: flute\n" + SCALE + "```\n", encoding="utf-8")
        real_prepare = music.prepare
        for fault in (AttributeError("x"), KeyError("x"), OSError(28, "No space left on device")):
            with self.subTest(type(fault).__name__):
                def broken(*args, **kwargs):
                    raise fault
                music.prepare = broken
                printed = io.StringIO()
                try:
                    with contextlib.redirect_stdout(printed):
                        outcome = build_site._prepare_music(content, self.output, self.root / "course", "AMU1O", 1)
                finally:
                    music.prepare = real_prepare
                self.assertEqual(outcome["stop"]["reason"], "notReady")
                self.assertEqual(outcome["stop"]["missing"], [{"item": "flute", "page": "Scales"}])
                said = printed.getvalue().strip()
                self.assertTrue(said.startswith("⚠️ Could not prepare the tunes"), said)
                self.assertNotIn("Error", said)
                self.assertNotIn(str(self.root), said)

    def test_a_fault_with_no_tune_to_play_lets_the_build_carry_on(self):
        import build_site
        content = self.root / "content"
        content.mkdir(parents=True)
        (content / "Theory.md").write_text("```abc\n% play: no\n" + SCALE + "```\n", encoding="utf-8")
        real_prepare = music.prepare

        def broken(*args, **kwargs):
            raise RuntimeError("x")
        music.prepare = broken
        import contextlib
        import io
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                outcome = build_site._prepare_music(content, self.output, self.root / "course", "AMU1O", 1)
        finally:
            music.prepare = real_prepare
        self.assertIsNone(outcome["stop"])


# ---- The folder problem --------------------------------------------------------------

class ProblemTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()

    def test_every_site_health_case(self):
        table = {entry["name"]: entry for entry in contracts.section("shared-rules", "siteHealth", "checks")}
        for case in table["musicTunesNotRight"]["cases"]:
            with self.subTest(case["name"]):
                finding = site_health.music_finding({"music_problems": case["tunes"]}, case["course"],
                                                    case["section"], table)
                self.assertEqual(finding.sentence, case["sentence"])
                self.assertEqual(finding.detail, case["detail"])

    def test_the_kind_is_a_section_problem_kind(self):
        kinds = {entry["kind"]: entry for entry in contracts.section("shared-rules", "sectionProblems", "kinds")}
        self.assertEqual(kinds["musicTunesNotRight"]["facts"], "music_problems")
        self.assertIn("musicTunesNotRight", section_problems._MAKERS)


class LoaderTests(unittest.TestCase):
    def test_the_page_keeps_one_audio_context_and_closes_it_on_leaving(self):
        # #679's implementation review: ten presses made ten contexts and
        # closed none. Measured since: one made, closed on leaving the page,
        # in both engines (documentation/05-build-pipeline.md).
        source = (REPO / "support" / "quartz" / "components" / "scripts" / "music.inline.ts").read_text(
            encoding="utf-8")
        self.assertEqual(source.count("new Context()"), 1)
        made = source.index("function musicAudioContext()")
        self.assertGreater(source.index("new Context()"), made)
        self.assertIn("musicContext = null", source)
        cleanup = source[source.index("window.addCleanup(() => {\n    musicPageChanges += 1"):]
        self.assertIn("closeMusicContext()", cleanup[:200])
        self.assertIn("context.close()", source)


# ---- The real engine, where it is installed ------------------------------------------------

def _real_engine():
    folder = music.engine_dir()
    if (folder / "node_modules" / "abcjs" / "package.json").is_file() and shutil.which("node"):
        return folder
    return None


@unittest.skipIf(_real_engine() is None,
                 "the music engine is not installed here (it is in the image: verify.sh runs these through "
                 "scripts/check_music_rules_against_the_site.py; or set PLANTOIR_VENDOR_DIR)")
class RealEngineTests(unittest.TestCase):
    def setUp(self):
        use_the_repository_contract()
        self.command = music.helper_command()
        self.command[1] = str(REPO / "support" / "music" / "plantoir-music.mjs")

    def test_every_needed_case_is_abcjss_own_answer(self):
        cases = rules("sounds", "needed", "cases")
        answers = music.draw_all([{"id": str(i), "abc": c["abc"]} for i, c in enumerate(cases)], self.command)
        for index, case in enumerate(cases):
            with self.subTest(case["name"]):
                self.assertTrue(answers[str(index)]["ok"], answers[str(index)])
                self.assertEqual(answers[str(index)]["programs"], case["programs"])

    def test_a_tune_is_drawn_with_every_note_classed(self):
        answer = music.draw_all([{"id": "1", "abc": SCALE}], self.command)["1"]
        self.assertTrue(answer["ok"])
        self.assertEqual(answer["notes"], 8)
        self.assertIn('fill="currentColor"', answer["html"])
        self.assertTrue(answer["html"].startswith("<div"))

    def test_the_reviewers_240_bars_on_one_line_are_wrapped_and_readable(self):
        long_line = "X:1\nT:Long\nM:4/4\nL:1/4\nK:D\n" + "D E F G | A B c d | c B A G | F E D2 | " * 60 + "]\n"
        first = music.draw_all([{"id": "1", "abc": long_line}], self.command)["1"]
        self.assertGreater(first["width"], rules("drawing", "wrap", "widerThan"))
        wrapped = music.draw_all([{"id": "1", "abc": long_line, "options": rules("drawing", "wrap", "options")}],
                                 self.command)["1"]
        self.assertTrue(wrapped["ok"])
        self.assertLessEqual(wrapped["width"], rules("drawing", "wrap", "widerThan"))
        self.assertEqual(music.layout_of(first["width"], wrapped["width"]), {"drawnWith": "wrap", "problem": None})
        self.assertEqual(wrapped["notes"], 900)
        height = float(wrapped["html"].split('viewBox="0 0 ')[1].split('"')[0].split()[1])
        # At the page's width the drawing keeps its own size: 61 staff lines,
        # where the drawing as written was 138 high at 13,723 wide (7 px tall).
        self.assertGreater(height, 5000)

    def test_a_tune_set_out_two_bars_to_a_line_is_drawn_as_written(self):
        two = "X:1\nT:t\nM:4/4\nL:1/4\nK:D\n" + "D E F G | A B c d |\n" * 4
        answer = music.draw_all([{"id": "1", "abc": two}], self.command)["1"]
        self.assertLessEqual(answer["width"], rules("drawing", "wrap", "widerThan"))

    def test_no_bar_lines_stay_too_long_even_wrapped(self):
        no_bars = "X:1\nT:t\nL:1/8\nK:C\n" + "CDEFGABc " * 20 + "\n"
        options = rules("drawing", "wrap", "options")
        wrapped = music.draw_all([{"id": "1", "abc": no_bars, "options": options}], self.command)["1"]
        self.assertEqual(music.layout_of(wrapped["width"], wrapped["width"])["problem"], "tooLongToRead")

    def test_what_abcjs_says_is_read_with_its_line(self):
        answer = music.draw_all([{"id": "1", "abc": "X:1\nK:G\nG A [B c | d e f g |]\n"}], self.command)["1"]
        self.assertEqual(answer["warnings"][0]["line"], 3)
        self.assertEqual(answer["warnings"][0]["said"], "Expected ']' to end the chords")
        self.assertEqual(music.draw_all([{"id": "2", "abc": ""}], self.command)["2"]["reason"], "nothingToDraw")


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""
GeoGebra's engine (#578, stage 1): scripts/geogebra_engine.py `adapt`, the
pin it is held to (contracts/toolchain.json -> pins -> geogebra), and the
Dockerfile layer that runs it.

The bundle is 33 MB, so these tests build a SMALL zip shaped like it - the
same folders, the same file names, GeoGebra's exact text in the two files the
replacements touch - and pass its own SHA-256. The real bundle is checked in
the image by verify.sh (the pinned file count, bytes and hashes). Set
PLANTOIR_GEOGEBRA_ZIP to a downloaded copy of the pinned zip to run the
real-bundle case here too.

Stdlib only, so Windows' PythonToolchainTests runs it as well. Run with:

    python3 scripts/test_geogebra_engine.py
"""
import hashlib
import json
import os
import re
import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path

import geogebra_engine

REPO = Path(__file__).resolve().parent.parent
NOCACHE = "GeoGebra/" + geogebra_engine.NOCACHE
CACHE_JS = "GeoGebra/" + geogebra_engine.CACHE_JS


def the_pin() -> dict:
    data = json.loads((REPO / "contracts" / "toolchain.json").read_text(encoding="utf-8"))
    for pin in data["pins"]:
        if pin["pin"] == "geogebra":
            return pin
    raise AssertionError("contracts/toolchain.json has no geogebra pin")


def original_text(file: str) -> str:
    """A stand-in for GeoGebra's file: each original text once, between other code."""
    parts = ["function web3d(){var n=window;"]
    for name, _purpose, old, _new in geogebra_engine.REPLACEMENTS:
        if name == file:
            parts.append(old)
            parts.append(";var spacer=1;")
    parts.append("}")
    return "".join(parts)


def bundle_members(nocache: str = None, cache_js: str = None) -> dict:
    """Every kind of file the real bundle has, by its path in the zip."""
    members = {
        "README.txt": "GeoGebra Math Apps\n",
        "GeoGebra/deployggb.js": "/* deployggb */\n",
        "GeoGebra/HTML5/5.0/GeoGebra.html": "<html></html>\n",
        "GeoGebra/HTML5/5.0/css/bundles/bundle.css": "body{}\n",
        "GeoGebra/HTML5/5.0/css/fonts.css": "@font-face{}\n",
        "GeoGebra/HTML5/5.0/web/web.nocache.js": "/* web */\n",
        "GeoGebra/HTML5/5.0/webSimple/webSimple.nocache.js": "/* webSimple */\n",
        NOCACHE: nocache if nocache is not None else original_text(geogebra_engine.NOCACHE),
        CACHE_JS: cache_js if cache_js is not None else original_text(geogebra_engine.CACHE_JS),
        "GeoGebra/HTML5/5.0/web3d/web3d.nocache.mjs": "/* module */\n",
        "GeoGebra/HTML5/5.0/web3d/sworker-locked.js": "/* worker */\n",
        "GeoGebra/HTML5/5.0/web3d/clear.cache.gif": "GIF89a",
        "GeoGebra/HTML5/5.0/web3d/html/ggtcallback.html": "<html></html>\n",
        "GeoGebra/HTML5/5.0/web3d/js/Roboto.js": "/* font */\n",
        "GeoGebra/HTML5/5.0/web3d/js/properties_keys_fr.js": "/* fr */\n",
        "GeoGebra/HTML5/5.0/web3d/js/properties_keys_de.js": "/* de */\n",
        "GeoGebra/HTML5/5.0/web3d/deferredjs/29EB0586CD5B749E221F6BB019F1B206/1.cache.js": "/* cas */\n",
        "GeoGebra/HTML5/5.0/web3d/fonts/latin/jlm_cmr10.js": "/* cmr10 */\n",
    }
    return members


KEPT = [
    "HTML5/5.0/css/bundles/bundle.css",
    "HTML5/5.0/css/fonts.css",
    "HTML5/5.0/web3d/29EB0586CD5B749E221F6BB019F1B206.cache.js",
    "HTML5/5.0/web3d/clear.cache.gif",
    "HTML5/5.0/web3d/deferredjs/29EB0586CD5B749E221F6BB019F1B206/1.cache.js",
    "HTML5/5.0/web3d/fonts/latin/jlm_cmr10.js",
    "HTML5/5.0/web3d/js/Roboto.js",
    "HTML5/5.0/web3d/web3d.nocache.js",
    "README.txt",
    "deployggb.js",
]


class EngineTestCase(unittest.TestCase):

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="plantoir-geogebra-engine-"))
        self.out = self.folder / "vendor" / "geogebra"

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def make_zip(self, members: dict, name: str = "bundle.zip") -> Path:
        path = self.folder / name
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as bundle:
            for member, text in members.items():
                bundle.writestr(member, text)
        return path

    def adapt(self, zip_path: Path):
        digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
        return geogebra_engine.adapt(zip_path, self.out, expected_sha256=digest)

    def files_written(self) -> list:
        found = []
        if self.out.exists():
            for path in sorted(self.out.rglob("*")):
                if path.is_file():
                    found.append(path.relative_to(self.out).as_posix())
        return found

    def assert_nothing_written(self):
        self.assertFalse(self.out.exists(), "a refusal wrote the engine folder")
        leftovers = []
        if (self.folder / "vendor").exists():
            for path in (self.folder / "vendor").iterdir():
                leftovers.append(path.name)
        self.assertEqual(leftovers, [], "a refusal left a staging folder behind")


class AdaptTests(EngineTestCase):

    def test_keeps_exactly_the_web3d_codebase_its_styles_and_the_loader(self):
        outcome = self.adapt(self.make_zip(bundle_members()))
        self.assertEqual(self.files_written(), sorted(KEPT))
        self.assertEqual(outcome["files"], len(KEPT))
        self.assertEqual(outcome["removedLanguages"], 2)
        total = 0
        for relative in KEPT:
            total += (self.out / relative).stat().st_size
        self.assertEqual(outcome["bytes"], total)

    def test_every_replacement_is_made_and_geogebras_own_text_is_gone(self):
        self.adapt(self.make_zip(bundle_members()))
        for file, purpose, old, new in geogebra_engine.REPLACEMENTS:
            with self.subTest(purpose=purpose):
                text = (self.out / file).read_text(encoding="utf-8")
                self.assertEqual(text.count(old), 0)
                self.assertEqual(text.count(new), 1)

    def test_there_are_six_replacements_in_the_two_files_the_pin_hashes(self):
        self.assertEqual(len(geogebra_engine.REPLACEMENTS), 6)
        files = set()
        for file, _purpose, old, new in geogebra_engine.REPLACEMENTS:
            files.add(file)
            self.assertNotEqual(old, new)
            self.assertNotIn(old, new, "a replacement that still contains the original would match again")
        self.assertEqual(files, {geogebra_engine.NOCACHE, geogebra_engine.CACHE_JS})
        self.assertTrue(files <= set(the_pin()["files"]))

    def test_the_loaders_frame_goes_under_html_not_body(self):
        self.adapt(self.make_zip(bundle_members()))
        text = (self.out / geogebra_engine.NOCACHE).read_text(encoding="utf-8")
        self.assertIn("o.documentElement.appendChild(a)", text)
        self.assertNotIn("o.body.appendChild(a)", text)

    def test_a_replacement_whose_text_is_missing_refuses_and_writes_nothing(self):
        for file, purpose, old, _new in geogebra_engine.REPLACEMENTS:
            with self.subTest(purpose=purpose):
                members = bundle_members()
                key = "GeoGebra/" + file
                members[key] = members[key].replace(old, "/* changed upstream */")
                with self.assertRaises(geogebra_engine.Refusal) as caught:
                    self.adapt(self.make_zip(members))
                self.assertIn("found it 0 time(s)", str(caught.exception))
                self.assert_nothing_written()

    def test_a_replacement_whose_text_appears_twice_refuses_and_writes_nothing(self):
        for file, purpose, old, _new in geogebra_engine.REPLACEMENTS:
            with self.subTest(purpose=purpose):
                members = bundle_members()
                key = "GeoGebra/" + file
                members[key] = members[key] + ";" + old
                with self.assertRaises(geogebra_engine.Refusal) as caught:
                    self.adapt(self.make_zip(members))
                self.assertIn("found it 2 time(s)", str(caught.exception))
                self.assert_nothing_written()

    def test_a_zip_that_is_not_the_pinned_one_refuses_and_writes_nothing(self):
        bundle = self.make_zip(bundle_members())
        with self.assertRaises(geogebra_engine.Refusal) as caught:
            geogebra_engine.adapt(bundle, self.out)
        self.assertIn(geogebra_engine.ZIP_SHA256, str(caught.exception))
        self.assert_nothing_written()

    def test_a_bundle_without_one_of_the_two_files_refuses(self):
        members = bundle_members()
        del members[CACHE_JS]
        with self.assertRaises(geogebra_engine.Refusal):
            self.adapt(self.make_zip(members))
        self.assert_nothing_written()

    def test_a_member_that_climbs_out_of_the_folder_refuses(self):
        members = bundle_members()
        members["GeoGebra/HTML5/5.0/css/../../../../escape.js"] = "/* out */\n"
        with self.assertRaises(geogebra_engine.Refusal):
            self.adapt(self.make_zip(members))
        self.assert_nothing_written()
        self.assertFalse((self.folder / "escape.js").exists())

    def test_running_again_replaces_the_folder_whole(self):
        self.adapt(self.make_zip(bundle_members()))
        (self.out / "stale.js").write_text("left from an older version\n", encoding="utf-8")
        self.adapt(self.make_zip(bundle_members(), name="again.zip"))
        self.assertEqual(self.files_written(), sorted(KEPT))
        self.assertEqual(sorted(path.name for path in (self.folder / "vendor").iterdir()), ["geogebra"])

    def test_a_refusal_leaves_an_earlier_good_copy_alone(self):
        self.adapt(self.make_zip(bundle_members()))
        before = self.files_written()
        members = bundle_members()
        members[NOCACHE] = "/* nothing to replace */"
        with self.assertRaises(geogebra_engine.Refusal):
            self.adapt(self.make_zip(members, name="bad.zip"))
        self.assertEqual(self.files_written(), before)

    def test_the_readme_names_the_version_the_attribution_and_what_changed(self):
        self.adapt(self.make_zip(bundle_members()))
        readme = (self.out / "README.txt").read_text(encoding="utf-8")
        self.assertIn(geogebra_engine.VERSION, readme)
        self.assertIn("Made with GeoGebra", readme)
        self.assertIn("https://www.geogebra.org", readme)
        self.assertIn("NON-COMMERCIAL", readme)
        self.assertIn("2 language files", readme)
        self.assertIn(geogebra_engine.ZIP_SHA256, readme)
        for number in range(1, 7):
            self.assertIn(f"  {number}. ", readme)
        # The changes rest on the EUPL (the source code's licence), with a
        # pointer to GeoGebra's source - not on the Materials clause's
        # "modify" (stage-1 review, 2026-10-24).
        self.assertIn("EUPL 1.2", readme)
        self.assertIn("modifications made, and redistributed, under the", readme)
        self.assertIn("https://github.com/geogebra/geogebra", readme)

    @unittest.skipUnless(os.name == "posix", "a Windows directory reports 0o777 to CPython, so the mode means nothing there")
    def test_the_folder_is_readable_by_everyone_not_only_its_maker(self):
        # mkdtemp makes 0700, and a rename keeps it; the site build may run as
        # another user (stage-1 review, 2026-10-24).
        self.adapt(self.make_zip(bundle_members()))
        self.assertEqual(self.out.stat().st_mode & 0o777, 0o755)

    def test_the_command_line_refuses_in_one_plain_line(self):
        bundle = self.make_zip(bundle_members())
        self.assertEqual(geogebra_engine.main(["geogebra_engine.py", "adapt", str(bundle), str(self.out)]), 1)
        self.assertEqual(geogebra_engine.main(["geogebra_engine.py"]), 2)
        self.assertEqual(geogebra_engine.main(["geogebra_engine.py", "version"]), 0)
        self.assert_nothing_written()


class RealBundleTests(EngineTestCase):
    """The pinned zip itself, when a downloaded copy is named. verify.sh checks the image either way."""

    def test_the_pinned_zip_gives_exactly_the_pinned_files(self):
        named = os.environ.get("PLANTOIR_GEOGEBRA_ZIP", "").strip()
        if not named:
            self.skipTest("PLANTOIR_GEOGEBRA_ZIP is not set")
        pin = the_pin()
        outcome = geogebra_engine.adapt(Path(named), self.out)
        self.assertEqual(outcome["files"], pin["fileCount"])
        self.assertEqual(outcome["bytes"], pin["bytes"])
        self.assertEqual(outcome["removedLanguages"], 83)
        for relative, digest in pin["files"].items():
            self.assertEqual(geogebra_engine.sha256_of(self.out / relative), digest, relative)


class PinTests(unittest.TestCase):
    """The script, the contract and the Dockerfile name one bundle."""

    def setUp(self):
        self.pin = the_pin()
        self.dockerfile = (REPO / "Dockerfile").read_text(encoding="utf-8")

    def test_the_script_carries_the_pins_version_and_hash(self):
        self.assertEqual(geogebra_engine.VERSION, self.pin["value"])
        self.assertEqual(geogebra_engine.ZIP_SHA256, self.pin["sha256"])
        self.assertEqual(geogebra_engine.ZIP_NAME,
                         "geogebra-math-apps-bundle-" + self.pin["value"].replace(".", "-") + ".zip")

    def test_both_addresses_name_the_same_zip_and_the_second_is_plantoir_apps_mirror(self):
        urls = self.pin["urls"]
        self.assertEqual(len(urls), 2)
        self.assertTrue(urls[0].startswith("https://download.geogebra.org/"))
        self.assertTrue(urls[1].startswith("https://plantoir.app/mirror/"))
        for url in urls:
            self.assertTrue(url.endswith("/" + geogebra_engine.ZIP_NAME), url)

    def test_the_dockerfile_fetches_the_first_then_the_mirror_and_checks_one_hash(self):
        self.assertIn(self.pin["dockerfileContains"], self.dockerfile)
        self.assertIn("ARG GEOGEBRA_URL=" + self.pin["urls"][0] + "\n", self.dockerfile)
        self.assertIn("ARG GEOGEBRA_MIRROR=" + self.pin["urls"][1] + "\n", self.dockerfile)
        self.assertEqual(self.dockerfile.count(self.pin["sha256"] + "  /tmp/ggb.zip\" | sha256sum -c -"), 1)
        layer = self.dockerfile[self.dockerfile.index("ARG GEOGEBRA_VERSION="):]
        layer = layer[:layer.index("\n\n")]
        primary = layer.index('"$GEOGEBRA_URL"')
        mirror = layer.index('"$GEOGEBRA_MIRROR"')
        check = layer.index("sha256sum -c -")
        adapt = layer.index("geogebra_engine.py adapt /tmp/ggb.zip /opt/vendor/geogebra")
        self.assertLess(primary, mirror)
        self.assertLess(mirror, check, "the hash must be checked whichever address answered")
        self.assertLess(check, adapt)
        self.assertEqual(len(re.findall(r"--retry \d+ --retry-all-errors", layer)), 2)

    def test_the_layer_comes_after_the_certificate_store_and_before_the_scripts(self):
        layer = self.dockerfile.index("ARG GEOGEBRA_VERSION=")
        self.assertLess(self.dockerfile.index("ge 20250419+deb13u1"), layer)
        self.assertLess(layer, self.dockerfile.index("COPY scripts/toolchain_paths.py"))

    def test_the_pinned_files_are_the_two_changed_files_and_the_loader(self):
        self.assertEqual(sorted(self.pin["files"]), sorted([
            "deployggb.js", geogebra_engine.NOCACHE, geogebra_engine.CACHE_JS]))
        for digest in self.pin["files"].values():
            self.assertRegex(digest, r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()

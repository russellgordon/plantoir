#!/usr/bin/env python3
"""Tests for the mac's update feed: building it at a cut, and checking it (#204).

macOS only by construction — hdiutil, codesign and Sparkle's own tools — which
is why it lives in website/ and not scripts/ (Windows' PythonToolchainTests
discovers only scripts/test_*.py). Run by the cut-release skill before a cut
and by hand after touching website/update_feed.py or website/update_feeds.py:

    python3 website/test_update_feed.py

Every signature here is made with a THROWAWAY key generated in a temporary
folder (openssl ed25519 → its 32-byte seed), never the plantoir-macos key.
FAILS, naming fetch-sparkle.sh, when the Sparkle tools are absent.
"""

from __future__ import annotations

import base64
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WEBSITE = Path(__file__).resolve().parent
sys.path.insert(0, str(WEBSITE))

import build  # noqa: E402
import update_feed  # noqa: E402
import update_feeds  # noqa: E402

OPENSSL = shutil.which("openssl") or "/usr/bin/openssl"


def make_key(folder: Path) -> tuple[Path, str]:
    """A throwaway ed25519 key: (private key file for --ed-key-file, public key)."""
    der = folder / "throwaway.der"
    subprocess.run([OPENSSL, "genpkey", "-algorithm", "ed25519", "-outform", "DER", "-out", str(der)],
                   check=True, capture_output=True)
    seed = der.read_bytes()[-32:]
    private = folder / "throwaway-private.txt"
    private.write_text(base64.b64encode(seed).decode())
    public_der = subprocess.run([OPENSSL, "pkey", "-inform", "DER", "-in", str(der), "-pubout", "-outform", "DER"],
                                check=True, capture_output=True).stdout
    return private, base64.b64encode(public_der[-32:]).decode()


def make_dmg(folder: Path, version: str, build_number: str, public_key: str) -> Path:
    """A DMG holding a tiny signed app shaped like Plantoir, the way publish.sh packs one."""
    stage = folder / f"stage-{build_number}"
    app = stage / "Plantoir.app"
    (app / "Contents" / "MacOS").mkdir(parents=True)
    shutil.copyfile("/usr/bin/true", app / "Contents" / "MacOS" / "Plantoir")
    (app / "Contents" / "MacOS" / "Plantoir").chmod(0o755)
    with open(app / "Contents" / "Info.plist", "wb") as handle:
        plistlib.dump({
            "CFBundleIdentifier": "ca.russellgordon.Plantoir",
            "CFBundleName": "Plantoir",
            "CFBundleExecutable": "Plantoir",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build_number,
            "LSMinimumSystemVersion": "15.0",
            "SUPublicEDKey": public_key,
            "SURequireSignedFeed": True,
            "SUVerifyUpdateBeforeExtraction": True,
        }, handle)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
    (stage / "Applications").symlink_to("/Applications")
    dmg = folder / f"Plantoir-{build_number}.dmg"
    subprocess.run(["hdiutil", "create", "-fs", "APFS", "-volname", "Plantoir", "-srcfolder", str(stage),
                    "-ov", "-format", "UDZO", str(dmg)], check=True, capture_output=True)
    return dmg


class UpdateFeedTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls) -> None:
        for name in ("generate_appcast", "sign_update"):
            if not (update_feed.SPARKLE_BIN / name).is_file():
                raise AssertionError(f"{update_feed.SPARKLE_BIN / name} is missing — run "
                                     f"mac-app/Vendor/fetch-sparkle.sh (these tests fail rather than skip).")
        # generate_appcast caches what it unpacks here; tidied afterwards only
        # when these tests made it, so a cache someone else had is left alone.
        cls.cache = Path.home() / "Library" / "Caches" / "Sparkle_generate_appcast"
        cls.cache_existed = cls.cache.exists()
        cls.folder = Path(tempfile.mkdtemp(prefix="plantoir-feed-test-"))
        cls.key, cls.public = make_key(cls.folder)
        cls.dmg_one = make_dmg(cls.folder, "1.3.2", "3100", cls.public)
        cls.dmg_two = make_dmg(cls.folder, "1.3.3", "3150", cls.public)

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.folder, ignore_errors=True)
        if not cls.cache_existed:
            shutil.rmtree(cls.cache, ignore_errors=True)

    def setUp(self) -> None:
        self.updates = Path(tempfile.mkdtemp(prefix="updates-", dir=self.folder))

    def earlier(self, item: dict, folder: Path) -> Path:
        """An earlier release's DMG, handed over rather than downloaded."""
        self.fetched.append(item["build"])
        return {"3100": self.dmg_one, "3150": self.dmg_two}[item["build"]]

    def cut(self, version: str, dmg: Path, notes: str, required: bool = False) -> Path:
        self.fetched = []
        return update_feed.build_feed(version, dmg, notes, required, self.updates, ed_key_file=self.key,
                                      earlier_dmg=self.earlier)

    def verifies(self, feed: Path) -> bool:
        result = subprocess.run([str(update_feed.SPARKLE_BIN / "sign_update"), "--verify",
                                 "--ed-key-file", str(self.key), str(feed)], capture_output=True)
        return result.returncode == 0

    # MARK: building

    def test_a_first_cut_is_signed_and_points_at_its_own_release(self) -> None:
        feed = self.cut("1.3.2", self.dmg_one, "- Something new.")
        self.assertTrue(self.verifies(feed))
        newest = update_feeds.newest_item(feed)
        self.assertEqual(newest["build"], "3100")
        self.assertEqual(newest["url"], update_feeds.RELEASE_DOWNLOADS + "v1.3.2/Plantoir-macOS.dmg")
        self.assertEqual(newest["length"], str(self.dmg_one.stat().st_size))
        self.assertEqual(update_feeds.problems_with(feed), [])
        self.assertNotIn(b"criticalUpdate", feed.read_bytes())

    def test_one_changed_byte_breaks_the_signature(self) -> None:
        feed = self.cut("1.3.2", self.dmg_one, "- Something new.")
        data = feed.read_bytes().replace(b"Something new", b"Something neW", 1)
        tampered = self.updates / "tampered.xml"
        tampered.write_bytes(data)
        self.assertFalse(self.verifies(tampered))

    def test_a_second_cut_keeps_the_first_item_and_the_notes_are_cumulative(self) -> None:
        first = self.cut("1.3.2", self.dmg_one, "- First.").read_bytes()
        feed = self.cut("1.3.3", self.dmg_two, "- Second.")
        self.assertTrue(self.verifies(feed))
        builds = sorted(item["build"] for item in update_feeds.items_of(feed))
        self.assertEqual(builds, ["3100", "3150"])
        notes = (self.updates / "macos-notes.html").read_text(encoding="utf-8")
        self.assertLess(notes.index('data-sparkle-version="3150"'), notes.index('data-sparkle-version="3100"'))
        self.assertEqual(notes.count(update_feed.STYLE_LINE), 1)
        self.assertIn(b"3100", first)

    # MARK: deltas (#312)

    def test_a_second_cut_carries_a_delta_from_the_first_and_leaves_its_item_alone(self) -> None:
        first = self.cut("1.3.2", self.dmg_one, "- First.")
        self.assertEqual(self.fetched, [], "a first cut has nothing to make a delta from")
        first_item = update_feed.items_by_build(first)["3100"]
        feed = self.cut("1.3.3", self.dmg_two, "- Second.")
        self.assertEqual(self.fetched, ["3100"], "the delta source is the build in the feed")
        self.assertTrue(self.verifies(feed))
        self.assertEqual(update_feed.items_by_build(feed)["3100"], first_item, "the first release's item changed")
        deltas = update_feed.deltas_of(feed, "3150")
        self.assertEqual(len(deltas), 1, feed.read_text(encoding="utf-8"))
        self.assertEqual(deltas[0]["from"], "3100")
        name = deltas[0]["url"].rsplit("/", 1)[-1]
        self.assertEqual(deltas[0]["url"], update_feeds.RELEASE_DOWNLOADS + "v1.3.3/" + name)
        self.assertTrue(name.endswith(".delta"), name)
        written = self.dmg_two.parent / name
        self.assertTrue(written.is_file(), "the delta is not beside the DMG, to be uploaded")
        self.assertEqual(str(written.stat().st_size), deltas[0]["length"])
        self.assertEqual(update_feeds.problems_with(feed), [])
        written.unlink()

    def test_a_delta_that_is_not_under_its_own_release_is_refused_by_the_check(self) -> None:
        self.cut("1.3.2", self.dmg_one, "- First.")
        feed = self.cut("1.3.3", self.dmg_two, "- Second.")
        for delta in update_feed.deltas_of(feed, "3150"):
            (self.dmg_two.parent / delta["url"].rsplit("/", 1)[-1]).unlink(missing_ok=True)
        moved = self.updates / "check-delta" / "macos.xml"
        moved.parent.mkdir()
        data = feed.read_bytes()
        index = data.index(b".delta")
        start = data.rindex(b'url="', 0, index)
        moved.write_bytes(data[:start] + data[start:index].replace(b"/v1.3.3/", b"/v1.3.2/") + data[index:])
        self.assertTrue(any("delta" in problem for problem in update_feeds.problems_with(moved)),
                        update_feeds.problems_with(moved))

    def test_a_required_warning_makes_the_release_critical_and_keeps_it_critical_below_it(self) -> None:
        feed = self.cut("1.3.2", self.dmg_one, "- Update both Macs first.", required=True)
        self.assertIn(b"criticalUpdate", feed.read_bytes())
        self.assertIn('data-sparkle-version="3100" data-required-warning',
                      (self.updates / "macos-notes.html").read_text(encoding="utf-8"))
        feed = self.cut("1.3.3", self.dmg_two, "- Ordinary.")
        self.assertIn(b'sparkle:criticalUpdate sparkle:version="3100"', feed.read_bytes())

    def test_a_dmg_of_another_version_is_refused(self) -> None:
        with self.assertRaises(update_feed.Refusal):
            self.cut("1.3.3", self.dmg_one, "- Wrong bundle.")
        self.assertFalse((self.updates / "macos.xml").exists())

    def test_a_rehearsal_never_touches_the_real_feed(self) -> None:
        real = self.cut("1.3.2", self.dmg_one, "- Real.")
        before = real.read_bytes()
        notes_before = (self.updates / "macos-notes.html").read_bytes()
        rehearsal = self.updates / "rehearsal-204" / "macos.xml"
        written = update_feed.build_feed(
            "1.3.3", self.dmg_two, "- Rehearsal.", False, self.updates, ed_key_file=self.key,
            rehearsal=rehearsal,
            download_prefix="https://github.com/russellgordon/plantoir/releases/download/v1.3.3-rehearsal-204/")
        self.assertEqual(written, rehearsal)
        self.assertTrue(self.verifies(rehearsal))
        self.assertTrue(update_feeds.newest_item(rehearsal)["url"].endswith("/Plantoir-macOS-REHEARSAL.dmg"))
        self.assertEqual(real.read_bytes(), before)
        self.assertEqual((self.updates / "macos-notes.html").read_bytes(), notes_before)
        with self.assertRaises(update_feed.Refusal):
            update_feed.build_feed("1.3.3", self.dmg_two, "- x", False, self.updates, ed_key_file=self.key,
                                   rehearsal=self.updates / "macos.xml", download_prefix="https://x/")

    def test_the_approved_notes_render_for_the_mac_window(self) -> None:
        """The cut-release skill's own notes shape (website/testdata/release-notes-template.md,
        kept in step with the skill below): headings, bullets, bold, code and links become
        HTML; the Downloads section, its checksum table, Windows-only lines and the
        one-platform sentence about Windows are not shown to a Mac (the slice-2 review's M1)."""
        template = (WEBSITE / "testdata" / "release-notes-template.md").read_text(encoding="utf-8")
        section = update_feed.notes_section("1.3.2", "3100", template, False)
        for gone in ("|", "**", "SHA-256", "Downloads", "Course Settings opens faster", "Windows:",
                     "(macOS)", "(Windows)", "5708cc"):
            self.assertNotIn(gone, section, f"{gone!r} reached the update window")
        for kept in ("<h3>New</h3>", "<h3>Improved</h3>", "<h3>Fixed</h3>",
                     "<li>Plantoir finds its own new versions and asks before installing one.</li>",
                     '<a href="https://plantoir.app/support.html">the support page</a>',
                     "<code>brackets</code>"):
            self.assertIn(kept, section)
        skill = (WEBSITE.parent / ".claude" / "skills" / "cut-release" / "SKILL.md").read_text(encoding="utf-8")
        for shape in ("| File | Size | SHA-256 |", '"(Windows)"', "**New**, **Improved**, **Fixed**"):
            self.assertIn(shape, skill, f"The skill no longer writes {shape!r}; update the fixture and the renderer")

    def test_the_renderers_edge_cases(self) -> None:
        """An emptied heading is dropped, a quote is a quote, and backticks keep their stars."""
        notes = "**New**\n\n- Mac thing.\n\n**Fixed**\n\n- Only Windows. (Windows)\n\n> Update both Macs first.\n\n- Use `**star**` here."
        section = update_feed.notes_section("1.3.2", "3100", notes, False)
        self.assertIn("<h3>New</h3>", section)
        self.assertIn("<h3>Fixed</h3>", section, "Fixed still has the quote and the code line under it")
        only_windows = update_feed.notes_section("1.3.2", "3100", "**New**\n\n- Mac.\n\n**Fixed**\n\n- Windows. (Windows)", False)
        self.assertNotIn("<h3>Fixed</h3>", only_windows, "An emptied heading was shown")
        self.assertIn("<blockquote><p>Update both Macs first.</p></blockquote>", section)
        self.assertNotIn("&gt; Update", section)
        self.assertIn("<code>**star**</code>", section)
        self.assertNotIn("<code><strong>", section)

    def test_notes_are_text_never_markup(self) -> None:
        section = update_feed.notes_section("1.3.2", "3100", "- <script>alert(1)</script>", False)
        self.assertNotIn("<script>", section)
        self.assertIn("&lt;script&gt;", section)

    # MARK: checking (website/update_feeds.py, run by build.py)

    def test_the_check_refuses_the_other_platforms_download_and_a_wrong_release(self) -> None:
        feed = self.cut("1.3.2", self.dmg_one, "- Something.")
        data = feed.read_bytes()
        wrong_platform = self.updates / "check-a" / "macos.xml"
        wrong_platform.parent.mkdir()
        wrong_platform.write_bytes(data.replace(b"Plantoir-macOS.dmg", b"PlantoirSetup.exe"))
        self.assertTrue(any("PlantoirSetup.exe" in problem for problem in update_feeds.problems_with(wrong_platform)))
        wrong_release = self.updates / "check-b" / "macos.xml"
        wrong_release.parent.mkdir()
        wrong_release.write_bytes(data.replace(b"/v1.3.2/", b"/v1.3.1/"))
        self.assertTrue(update_feeds.problems_with(wrong_release))

    def test_the_check_refuses_an_unsigned_or_reserialised_feed(self) -> None:
        feed = self.cut("1.3.2", self.dmg_one, "- Something.")
        data = feed.read_bytes()
        unsigned = self.updates / "check-c" / "macos.xml"
        unsigned.parent.mkdir()
        unsigned.write_bytes(data[:data.index(b"<!-- sparkle-signatures:")])
        self.assertTrue(any("signature" in problem for problem in update_feeds.problems_with(unsigned)))
        import xml.etree.ElementTree as ElementTree
        reserialised = self.updates / "check-d" / "macos.xml"
        reserialised.parent.mkdir()
        reserialised.write_bytes(ElementTree.tostring(ElementTree.fromstring(data)))
        self.assertTrue(update_feeds.problems_with(reserialised), "A re-serialised feed passed the check")
        self.assertFalse(self.verifies(reserialised))

    def test_the_site_copies_the_feed_byte_for_byte(self) -> None:
        feed = self.cut("1.3.2", self.dmg_one, "- Something.")
        destination = self.updates / "site-updates"
        copied = update_feeds.copy_feeds(self.updates, destination)
        self.assertIn(destination / "macos.xml", copied)
        self.assertNotIn(destination / "macos-notes.html", copied, "The notes are not served")
        self.assertEqual((destination / "macos.xml").read_bytes(), feed.read_bytes())

    def test_deploy_refuses_a_feed_for_another_version(self) -> None:
        feed = self.cut("1.3.2", self.dmg_one, "- Something.")
        project = self.updates / "project.yml"
        project.write_text('        MARKETING_VERSION: "1.3.3"\n')
        self.assertIsNotNone(build.feed_version_refusal(feed, project))
        project.write_text('        MARKETING_VERSION: "1.3.2"\n')
        self.assertIsNone(build.feed_version_refusal(feed, project))
        self.assertIsNone(build.feed_version_refusal(self.updates / "absent.xml", project))

    def test_the_live_check_catches_a_changed_feed_and_a_missing_download(self) -> None:
        feed = self.cut("1.3.2", self.dmg_one, "- Something.")
        good = feed.read_bytes()
        size = str(self.dmg_one.stat().st_size)

        def site(feed_bytes: bytes, download_status: int):
            def fetch(url: str, method: str):
                if url.endswith("/updates/macos.xml"):
                    return 200, {}, feed_bytes
                return download_status, {"Content-Length": size}, b""
            return fetch

        self.assertEqual(update_feeds.verify_live("https://plantoir.app", feed, site(good, 200)), "match")
        self.assertEqual(update_feeds.verify_live("https://plantoir.app", feed, site(good + b" ", 200)), "mismatch")
        self.assertEqual(update_feeds.verify_live("https://plantoir.app", feed, site(good, 404)), "mismatch")

    def test_the_live_check_catches_a_delta_that_was_not_uploaded(self) -> None:
        self.cut("1.3.2", self.dmg_one, "- First.")
        feed = self.cut("1.3.3", self.dmg_two, "- Second.")
        for delta in update_feed.deltas_of(feed, "3150"):
            (self.dmg_two.parent / delta["url"].rsplit("/", 1)[-1]).unlink(missing_ok=True)
        good = feed.read_bytes()
        size = str(self.dmg_two.stat().st_size)

        def site(delta_status: int):
            def fetch(url: str, method: str):
                if url.endswith("/updates/macos.xml"):
                    return 200, {}, good
                if url.endswith(".delta"):
                    return delta_status, {}, b""
                return 200, {"Content-Length": size}, b""
            return fetch

        self.assertEqual(update_feeds.verify_live("https://plantoir.app", feed, site(200)), "match")
        self.assertEqual(update_feeds.verify_live("https://plantoir.app", feed, site(404)), "mismatch")


if __name__ == "__main__":
    unittest.main(verbosity=2)

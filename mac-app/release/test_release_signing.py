#!/usr/bin/env python3
"""Tests for signing the updater into a release, and the checks that refuse a bad one (#204).

    python3 mac-app/release/test_release_signing.py

Everything here is signed AD-HOC ("-") in a temporary folder — never with a
Developer ID, never notarized. What ad-hoc CAN prove: the signing order
verifies, the entitlement and hardened-runtime checks fire, and the team
check refuses an ad-hoc app and every item of one against a real team. What
it cannot: the positive team check, which needs a Developer ID and is
measured at the dress rehearsal's first signed build (RELEASING.md → "The
dress rehearsal"). macOS only, which is why it is not in scripts/. Run by the
cut-release skill before a cut and by hand after touching mac-app/release/
or publish.sh. FAILS, naming fetch-sparkle.sh, when the framework is absent.
"""

from __future__ import annotations

import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

RELEASE = Path(__file__).resolve().parent
MAC_APP = RELEASE.parent
FRAMEWORK = MAC_APP / "Vendor" / "Sparkle" / "Sparkle.framework"
ENTITLEMENTS = MAC_APP / "QuartzTeachers" / "QuartzTeachers.entitlements"
REAL_TEAM = "U2ZN2W2UQJ"


def run(*arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(list(arguments), capture_output=True, text=True)


class ReleaseSigningTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls) -> None:
        if not FRAMEWORK.is_dir():
            raise AssertionError(f"{FRAMEWORK} is missing — run mac-app/Vendor/fetch-sparkle.sh "
                                 f"(these tests fail rather than skip).")
        cls.folder = Path(tempfile.mkdtemp(prefix="plantoir-signing-test-"))

    @classmethod
    def tearDownClass(cls) -> None:
        shutil.rmtree(cls.folder, ignore_errors=True)

    def fake_app(self, name: str, feed: str = "https://plantoir.app/updates/macos.xml",
                 automatic: bool = False) -> Path:
        """A bundle shaped like a staged release: an executable, the updater, the real entitlements' target."""
        app = self.folder / name / "Plantoir.app"
        (app / "Contents" / "MacOS").mkdir(parents=True)
        (app / "Contents" / "Frameworks").mkdir()
        shutil.copyfile("/usr/bin/true", app / "Contents" / "MacOS" / "Plantoir")
        (app / "Contents" / "MacOS" / "Plantoir").chmod(0o755)
        with open(app / "Contents" / "Info.plist", "wb") as handle:
            plistlib.dump({
                "CFBundleIdentifier": "ca.russellgordon.Plantoir",
                "CFBundleExecutable": "Plantoir",
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.3.2",
                "CFBundleVersion": "3100",
                "SUFeedURL": feed,
                "SUPublicEDKey": "lYt8VK8iKB4jMy+b06j1m+GAedeTChAbX5NkMW2FSMw=",
                "SUAllowsAutomaticUpdates": automatic,
            }, handle)
        # ditto keeps the framework's version symlinks as symlinks.
        subprocess.run(["ditto", str(FRAMEWORK), str(app / "Contents" / "Frameworks" / "Sparkle.framework")],
                       check=True)
        return app

    def sign_the_release_way(self, app: Path) -> None:
        result = run(str(RELEASE / "sign-updater.sh"), str(app), "-", "--no-timestamp")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = run("codesign", "--force", "--timestamp=none", "--options", "runtime",
                     "--entitlements", str(ENTITLEMENTS), "--sign", "-", str(app))
        self.assertEqual(result.returncode, 0, result.stderr)

    @staticmethod
    def cdhash(item: Path) -> str:
        info = run("codesign", "-dvvv", str(item)).stderr
        for line in info.splitlines():
            if line.startswith("CDHash="):
                return line
        raise AssertionError(f"{item} has no CDHash")

    def check(self, app: Path, *options: str) -> subprocess.CompletedProcess:
        return run(str(RELEASE / "check-signatures.sh"), str(app), *options)

    # MARK: the order publish.sh signs in

    def test_the_release_order_verifies_and_passes_every_check_but_the_team(self) -> None:
        app = self.fake_app("right")
        self.sign_the_release_way(app)
        verify = run("codesign", "--verify", "--deep", "--strict", str(app))
        self.assertEqual(verify.returncode, 0, verify.stderr)
        passed = self.check(app, "--ad-hoc-for-tests")
        self.assertEqual(passed.returncode, 0, passed.stdout)

    def test_an_ad_hoc_app_is_refused(self) -> None:
        app = self.fake_app("adhoc")
        self.sign_the_release_way(app)
        refused = self.check(app)
        self.assertEqual(refused.returncode, 1)
        self.assertIn("NOT SIGNED BY A TEAM", refused.stdout)

    def test_every_item_off_the_team_is_named(self) -> None:
        app = self.fake_app("offteam")
        self.sign_the_release_way(app)
        refused = self.check(app, "--expect-team", REAL_TEAM)
        self.assertEqual(refused.returncode, 1)
        for item in ("Autoupdate", "Updater.app", "Sparkle.framework", "Plantoir.app"):
            self.assertIn(item, refused.stdout, f"{item} was not named")
        self.assertEqual(refused.stdout.count("WRONG TEAM"), 4)
        # Signed --timestamp=none, as every item here is: refused outside the tests.
        self.assertEqual(refused.stdout.count("NO SECURE TIMESTAMP"), 4)

    def test_the_updaters_helpers_left_as_fetched_are_caught_by_the_team_and_not_by_verify(self) -> None:
        """The failure the check exists for: the app re-signed, the helpers left as Sparkle ships them."""
        app = self.fake_app("untouched")
        # Only the framework's top level and the app — what Xcode's Code Sign On Copy plus a
        # publish.sh without sign-updater.sh would leave.
        run("codesign", "--force", "--timestamp=none", "--options", "runtime", "--sign", "-",
            str(app / "Contents" / "Frameworks" / "Sparkle.framework"))
        run("codesign", "--force", "--timestamp=none", "--options", "runtime",
            "--entitlements", str(ENTITLEMENTS), "--sign", "-", str(app))
        verify = run("codesign", "--verify", "--deep", "--strict", str(app))
        self.assertEqual(verify.returncode, 0, "verify --deep --strict is expected to PASS here — that is the point")
        # The helper really is the one Sparkle shipped: its code-signature hash is the vendored
        # copy's. (After sign-updater.sh it is not — asserted below — so this test tells the two
        # bundles apart, which a team comparison alone cannot do ad-hoc: the slice-2 review's L1.)
        autoupdate = "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
        self.assertEqual(self.cdhash(app / autoupdate), self.cdhash(FRAMEWORK / "Versions" / "B" / "Autoupdate"))
        signed = self.fake_app("untouched-then-signed")
        self.sign_the_release_way(signed)
        self.assertNotEqual(self.cdhash(signed / autoupdate), self.cdhash(FRAMEWORK / "Versions" / "B" / "Autoupdate"))
        refused = self.check(app, "--expect-team", REAL_TEAM)
        self.assertEqual(refused.returncode, 1)
        self.assertIn("Autoupdate", refused.stdout)

    def test_the_apps_entitlements_on_the_helpers_are_refused(self) -> None:
        app = self.fake_app("deep")
        result = run("codesign", "--force", "--deep", "--timestamp=none", "--options", "runtime",
                     "--entitlements", str(ENTITLEMENTS), "--sign", "-", str(app))
        self.assertEqual(result.returncode, 0, result.stderr)
        refused = self.check(app, "--ad-hoc-for-tests")
        self.assertEqual(refused.returncode, 1)
        self.assertIn("CARRIES THE APP'S ENTITLEMENTS: Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate",
                      refused.stdout)

    def test_a_helper_without_the_hardened_runtime_is_refused(self) -> None:
        app = self.fake_app("noruntime")
        self.sign_the_release_way(app)
        framework = app / "Contents" / "Frameworks" / "Sparkle.framework"
        run("codesign", "--force", "--timestamp=none", "--sign", "-", str(framework / "Versions" / "B" / "Autoupdate"))
        run("codesign", "--force", "--timestamp=none", "--options", "runtime", "--sign", "-", str(framework))
        run("codesign", "--force", "--timestamp=none", "--options", "runtime",
            "--entitlements", str(ENTITLEMENTS), "--sign", "-", str(app))
        refused = self.check(app, "--ad-hoc-for-tests")
        self.assertEqual(refused.returncode, 1)
        self.assertIn("NO HARDENED RUNTIME: Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate",
                      refused.stdout)

    # MARK: the update keys in the built bundle

    def test_the_update_keys_are_checked_in_the_built_bundle(self) -> None:
        keys = str(RELEASE / "check-update-keys.sh")
        self.assertEqual(run(keys, str(self.fake_app("keys-ok"))).returncode, 0)
        self.assertEqual(run(keys, str(self.fake_app("keys-nofeed", feed=""))).returncode, 1)
        self.assertEqual(run(keys, str(self.fake_app("keys-auto", automatic=True))).returncode, 1)
        rehearsal = "https://plantoir.app/updates/rehearsal-204/macos.xml"
        self.assertEqual(run(keys, str(self.fake_app("keys-rehearsal", feed=rehearsal)), rehearsal).returncode, 0)
        self.assertEqual(run(keys, str(self.fake_app("keys-rehearsal-2", feed=rehearsal))).returncode, 1)

    # MARK: publish.sh calls them, in order

    def test_publish_sh_runs_each_step_in_its_place(self) -> None:
        text = (MAC_APP / "publish.sh").read_text(encoding="utf-8")

        def at(needle: str) -> int:
            index = text.find(needle)
            self.assertNotEqual(index, -1, f"publish.sh never says {needle}")
            return index

        self.assertLess(at("./Vendor/fetch-sparkle.sh"), at("xcodegen generate"))
        # The CALLS, not a mention in a comment.
        sign_updater = at('./release/sign-updater.sh "${STAGE_APP}" "${IDENTITY}"')
        check_signatures = at('./release/check-signatures.sh "${STAGE_APP}"')
        self.assertLess(at("xcodebuild -project"), at('./release/check-update-keys.sh "${STAGE_APP}"'))
        self.assertLess(sign_updater, at('-name "*.dylib"'))
        self.assertLess(sign_updater, at("Signing Plantoir.app with entitlements"))
        self.assertLess(at("Signing Plantoir.app with entitlements"), check_signatures)
        self.assertLess(check_signatures, at("hdiutil create"))
        for line in text.splitlines():
            if line.strip().startswith("codesign") and "--sign" in line:
                self.assertNotIn("--deep", line, "a signing line uses --deep")


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""
plantoir.app's mirror (#578): website/mirror.py and its two callers.

The list in site.json agrees with contracts/toolchain.json; build.py fills
site/mirror/ from a cache outside the repository; --deploy REFUSES while a
listed file is missing or wrong (a mirror that 404s breaks a teacher's first
build on the day GeoGebra's own host is down, and nothing else would notice);
--verify-deploy fetches each file back. Pure stdlib, no network. Run with:

    python3 website/test_mirror.py
"""
import copy
import hashlib
import json
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build  # noqa: E402
import mirror  # noqa: E402
import netlify_deploy  # noqa: E402

WEBSITE = Path(__file__).resolve().parent
REPO = WEBSITE.parent
PAYLOAD = b"PK\x03\x04 a stand-in for GeoGebra's bundle"
PAYLOAD_SHA = hashlib.sha256(PAYLOAD).hexdigest()


def real_site() -> dict:
    return json.loads((WEBSITE / "site.json").read_text(encoding="utf-8"))


def real_pins() -> list:
    return json.loads((REPO / "contracts" / "toolchain.json").read_text(encoding="utf-8"))["pins"]


def a_site(file: str = "geogebra/bundle.zip", sha: str = PAYLOAD_SHA) -> dict:
    return {"base_url": "https://plantoir.app",
            "mirror": {"files": [{"file": file, "sha256": sha, "source": "https://example.org/bundle.zip"}]}}


class Fetcher:
    """Stands in for mirror.download: writes `body` and counts calls."""

    def __init__(self, body: bytes = PAYLOAD, error: Exception = None):
        self.body = body
        self.error = error
        self.calls = []

    def __call__(self, url, destination):
        self.calls.append(url)
        if self.error is not None:
            raise self.error
        Path(destination).write_bytes(self.body)


class MirrorTestCase(unittest.TestCase):

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.output = self.root / "site"
        self.output.mkdir()
        self.cache = self.root / "cache"

    def tearDown(self):
        self.temporary.cleanup()


class ListTests(unittest.TestCase):

    def test_the_real_list_and_the_real_pins_agree(self):
        self.assertEqual(mirror.entry_problems(real_site(), real_pins()), [])

    def test_the_geogebra_pins_mirror_address_is_listed_with_its_hash(self):
        site = real_site()
        pin = [pin for pin in real_pins() if pin["pin"] == "geogebra"][0]
        prefix = site["base_url"] + "/mirror/"
        self.assertTrue(pin["urls"][1].startswith(prefix))
        listed = {entry["file"]: entry for entry in mirror.entries(site)}
        entry = listed[pin["urls"][1][len(prefix):]]
        self.assertEqual(entry["sha256"], pin["sha256"])
        self.assertEqual(entry["source"], pin["urls"][0])

    def test_a_pin_bumped_without_mirroring_its_new_version_is_a_problem(self):
        pins = copy.deepcopy(real_pins())
        for pin in pins:
            if pin["pin"] == "geogebra":
                pin["urls"][1] = pin["urls"][1].replace("5-4-933-1", "5-4-940-0")
        problems = mirror.entry_problems(real_site(), pins)
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("5-4-940-0", problems[0])

    def test_a_listed_hash_that_is_not_the_pins_is_a_problem(self):
        site = real_site()
        site["mirror"]["files"][0]["sha256"] = "0" * 64
        problems = mirror.entry_problems(site, real_pins())
        self.assertEqual(len(problems), 1, problems)

    def test_a_file_at_the_site_root_or_outside_mirror_is_refused(self):
        for name in ("bundle.zip", "../bundle.zip", "geogebra/../../x.zip", "/geogebra/x.zip", "geogebra/.x.zip"):
            with self.subTest(name=name):
                problems = mirror.entry_problems(a_site(file=name), [])
                self.assertTrue(problems)


class FillTests(MirrorTestCase):

    def test_a_build_that_is_not_a_deploy_tries_the_download_once(self):
        # Stage-1 review: six 60-second tries stalled an offline build.py.
        calls = []
        def fake_download(url, destination, attempts=mirror.ATTEMPTS, pause=None):
            calls.append(attempts)
            raise OSError("offline")
        real = mirror.download
        mirror.download = fake_download
        try:
            mirror.fill(a_site(), self.output, cache=self.cache, attempts=1)
            mirror.fill(a_site(), self.output, cache=self.cache)
        finally:
            mirror.download = real
        self.assertEqual(calls, [1, mirror.ATTEMPTS])

    def test_build_py_asks_for_retries_only_when_deploying(self):
        source = (Path(__file__).resolve().parent / "build.py").read_text(encoding="utf-8")
        self.assertIn("attempts = mirror.ATTEMPTS if deploying else 1", source)
        self.assertIn("build(check_only=arguments.check, deploying=arguments.deploy)", source)

    def test_the_first_build_downloads_into_the_cache_and_copies_into_the_site(self):
        fetch = Fetcher()
        said = mirror.fill(a_site(), self.output, cache=self.cache, fetch=fetch)
        self.assertEqual(fetch.calls, ["https://example.org/bundle.zip"])
        self.assertEqual((self.cache / "geogebra" / "bundle.zip").read_bytes(), PAYLOAD)
        self.assertEqual((self.output / "mirror" / "geogebra" / "bundle.zip").read_bytes(), PAYLOAD)
        self.assertEqual(len(said), 1)

    def test_a_later_build_downloads_nothing(self):
        mirror.fill(a_site(), self.output, cache=self.cache, fetch=Fetcher())
        (self.output / "mirror" / "geogebra" / "bundle.zip").unlink()
        fetch = Fetcher()
        mirror.fill(a_site(), self.output, cache=self.cache, fetch=fetch)
        self.assertEqual(fetch.calls, [])
        self.assertTrue((self.output / "mirror" / "geogebra" / "bundle.zip").is_file())
        self.assertEqual(mirror.fill(a_site(), self.output, cache=self.cache, fetch=fetch), [])

    def test_a_download_with_the_wrong_bytes_is_never_kept(self):
        said = mirror.fill(a_site(), self.output, cache=self.cache, fetch=Fetcher(body=b"something else"))
        self.assertFalse((self.output / "mirror" / "geogebra" / "bundle.zip").exists())
        self.assertFalse((self.cache / "geogebra" / "bundle.zip").exists())
        self.assertEqual(list((self.cache / "geogebra").iterdir()), [], "a partial download was left")
        self.assertIn("deploy will refuse", said[0])

    def test_no_network_is_said_and_never_stops_the_build(self):
        said = mirror.fill(a_site(), self.output, cache=self.cache, fetch=Fetcher(error=OSError("offline")))
        self.assertIn("offline", said[0])
        self.assertFalse((self.output / "mirror" / "geogebra" / "bundle.zip").exists())

    def test_a_wrong_copy_in_the_site_is_replaced_and_an_unlisted_one_removed(self):
        stale = self.output / "mirror" / "old" / "gone.zip"
        stale.parent.mkdir(parents=True)
        stale.write_bytes(b"no longer listed")
        wrong = self.output / "mirror" / "geogebra" / "bundle.zip"
        wrong.parent.mkdir(parents=True)
        wrong.write_bytes(b"tampered")
        mirror.fill(a_site(), self.output, cache=self.cache, fetch=Fetcher())
        self.assertEqual(wrong.read_bytes(), PAYLOAD)
        self.assertFalse(stale.exists())
        self.assertFalse(stale.parent.exists())

    def test_the_real_download_retries_then_gives_up_with_a_plain_error(self):
        pauses = []
        destination = self.root / "x.zip"
        missing = (self.root / "not-there.zip").as_uri()
        with self.assertRaises(OSError) as caught:
            mirror.download(missing, destination, attempts=3, pause=pauses.append)
        self.assertEqual(len(pauses), 2)
        self.assertIn("after 3 attempts", str(caught.exception))
        source = self.root / "there.zip"
        source.write_bytes(PAYLOAD)
        mirror.download(source.as_uri(), destination, pause=pauses.append)
        self.assertEqual(destination.read_bytes(), PAYLOAD)


class RefusalTests(MirrorTestCase):

    def test_a_missing_file_refuses(self):
        refusal = mirror.deploy_refusal(a_site(), self.output)
        self.assertIsNotNone(refusal)
        self.assertTrue(refusal.startswith("Not deploying:"))
        self.assertIn("site/mirror/geogebra/bundle.zip is missing", refusal)

    def test_a_file_with_the_wrong_hash_refuses(self):
        target = self.output / "mirror" / "geogebra" / "bundle.zip"
        target.parent.mkdir(parents=True)
        target.write_bytes(b"not the pinned bytes")
        self.assertIn("is not SHA-256", mirror.deploy_refusal(a_site(), self.output))

    def test_the_file_at_the_site_root_instead_refuses(self):
        (self.output / "bundle.zip").write_bytes(PAYLOAD)
        self.assertIsNotNone(mirror.deploy_refusal(a_site(), self.output))

    def test_the_right_file_in_the_right_place_deploys(self):
        mirror.fill(a_site(), self.output, cache=self.cache, fetch=Fetcher())
        self.assertIsNone(mirror.deploy_refusal(a_site(), self.output))


class DeployWiringTests(MirrorTestCase):
    """The refusal is reached on both ways of deploying, before anything is uploaded."""

    def test_build_py_deploy_refuses_before_netlify_is_called(self):
        site = a_site()
        deployed = []
        with mock.patch.object(build, "OUTPUT", self.output), \
                mock.patch.object(build, "build", return_value=0), \
                mock.patch.object(build, "native_corners_refusal", return_value=None), \
                mock.patch.object(build, "committed_feed_bytes_refusal", return_value=None), \
                mock.patch.object(build, "feed_version_refusal", return_value=None), \
                mock.patch.object(build.windows_feed, "version_refusal", return_value=None), \
                mock.patch.object(build, "release_readiness_refusal", return_value=None), \
                mock.patch.object(build, "read_json", side_effect=lambda path: site), \
                mock.patch.object(netlify_deploy, "deploy", side_effect=lambda: deployed.append(1) or 0), \
                mock.patch.object(sys, "argv", ["build.py", "--deploy"]), \
                mock.patch("sys.stderr") as stderr:
            result = build.main()
            self.assertEqual(result, 1)
            self.assertEqual(deployed, [])
            written = "".join(str(call.args[0]) for call in stderr.write.call_args_list if call.args)
            self.assertIn("Not deploying: plantoir.app's mirror", written)
            # With the file in place, the same run reaches the deploy.
            mirror.fill(site, self.output, cache=self.cache, fetch=Fetcher())
            self.assertEqual(build.main(), 0)
            self.assertEqual(deployed, [1])

    def test_netlify_deploy_on_its_own_refuses_before_reading_a_token(self):
        (self.output / "index.html").write_text("<html></html>", encoding="utf-8")
        with mock.patch.object(netlify_deploy, "SITE_DIR", self.output), \
                mock.patch.object(netlify_deploy, "read_config", return_value=a_site()), \
                mock.patch.object(netlify_deploy, "read_token", side_effect=AssertionError("read a token")):
            with self.assertRaises(SystemExit) as caught:
                netlify_deploy.deploy()
        self.assertIn("Not deploying: plantoir.app's mirror", str(caught.exception.code))


class LiveTests(unittest.TestCase):

    def check(self, answer) -> str:
        def fetch(url):
            self.asked.append(url)
            if isinstance(answer, Exception):
                raise answer
            return answer
        self.asked = []
        with mock.patch("builtins.print"):
            return mirror.verify_live(a_site(), fetch=fetch)

    def test_the_right_bytes_match(self):
        self.assertEqual(self.check((200, PAYLOAD)), "match")
        self.assertEqual(self.asked, ["https://plantoir.app/mirror/geogebra/bundle.zip"])

    def test_not_served_is_a_mismatch(self):
        self.assertEqual(self.check((404, b"")), "mismatch")

    def test_the_wrong_bytes_are_a_mismatch(self):
        self.assertEqual(self.check((200, b"other")), "mismatch")

    def test_no_answer_is_unknown(self):
        self.assertEqual(self.check(urllib.error.URLError("offline")), "unknown")

    def test_verify_deploy_counts_the_mirror(self):
        with mock.patch.object(netlify_deploy, "verify_live", return_value="match"), \
                mock.patch.object(netlify_deploy, "verify_feeds_live", return_value="match"), \
                mock.patch.object(netlify_deploy, "verify_mirror_live", return_value="mismatch"), \
                mock.patch.object(sys, "argv", ["build.py", "--verify-deploy"]):
            self.assertEqual(build.main(), 2)


if __name__ == "__main__":
    unittest.main()

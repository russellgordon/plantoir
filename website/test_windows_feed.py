#!/usr/bin/env python3
"""Tests for the Windows update feed's checker and the deploy's feed-bytes
refusal (#428 items 3 and 7).

Plain standard library, no network, no key: runs with `python
website/test_windows_feed.py` on Windows and the mac alike. Feeds are signed
here with a THROWAWAY Ed25519 key (RFC 8032's signing, below), never the
release key; the one real-key test reads only the committed feed and its
public half.
"""

from __future__ import annotations

import base64
import hashlib
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build  # noqa: E402
import windows_feed  # noqa: E402

WEBSITE = Path(__file__).resolve().parent


# ---- A throwaway signer (RFC 8032 section 6), for tests only -----------------

def _compress(point) -> bytes:
    p = windows_feed._P
    z_inverse = pow(point[2], p - 2, p)
    x = point[0] * z_inverse % p
    y = point[1] * z_inverse % p
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def _keypair(secret: bytes):
    digest = hashlib.sha512(secret).digest()
    scalar = int.from_bytes(digest[:32], "little")
    scalar &= (1 << 254) - 8
    scalar |= 1 << 254
    public = _compress(windows_feed._mul(scalar, windows_feed._G))
    return scalar, digest[32:], public


def _sign(secret: bytes, message: bytes) -> bytes:
    scalar, prefix, public = _keypair(secret)
    r = int.from_bytes(hashlib.sha512(prefix + message).digest(), "little") % windows_feed._L
    big_r = _compress(windows_feed._mul(r, windows_feed._G))
    k = int.from_bytes(hashlib.sha512(big_r + public + message).digest(), "little") % windows_feed._L
    return big_r + ((r + k * scalar) % windows_feed._L).to_bytes(32, "little")


SECRET = b"\x01" * 32
PUBLIC = base64.b64encode(_keypair(SECRET)[2]).decode()
INSTALLERS = {"1.4.2": b"installer one" * 100, "1.4.3": b"installer two" * 100}


def _item(version: str, signature: str | None = None, url: str | None = None, notes: str = "") -> str:
    if signature is None:
        signature = base64.b64encode(_sign(SECRET, INSTALLERS.get(version, b""))).decode()
    url = url or f"https://github.com/russellgordon/plantoir/releases/download/v{version}/PlantoirSetup.exe"
    description = f"<description>{notes}</description>" if notes else ""
    signature_attribute = f' sparkle:signature="{signature}"' if signature else ""
    return (f"<item><title>Plantoir {version}</title>{description}"
            f"<sparkle:version>{version}</sparkle:version>"
            f'<enclosure url="{url}" sparkle:version="{version}" '
            f'length="{len(INSTALLERS.get(version, b""))}" sparkle:os="windows"{signature_attribute} /></item>')


def _feed(*items: str) -> bytes:
    body = ('<?xml version="1.0" encoding="utf-8"?>\r\n<rss version="2.0" '
            'xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">\r\n<channel>'
            "<title>Plantoir</title>" + "".join(items) + "</channel>\r\n</rss>")
    return body.encode()


class _Folder:
    """A temporary updates/ folder with a signed windows.xml."""

    def __enter__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)
        return self

    def __exit__(self, *_):
        self.tmp.cleanup()

    def write(self, feed: bytes, signed: bool = True, signature_of: bytes | None = None) -> Path:
        target = self.path / "windows.xml"
        target.write_bytes(feed)
        if signed:
            signature = _sign(SECRET, feed if signature_of is None else signature_of)
            (self.path / "windows.xml.signature").write_text(base64.b64encode(signature).decode())
        return target


class Ed25519Tests(unittest.TestCase):

    def test_rfc_8032_vectors_verify_and_a_changed_byte_does_not(self):
        vectors = [
            ("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
             "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
            ("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
             "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
        ]
        for public, message, signature in vectors:
            key, msg, sig = bytes.fromhex(public), bytes.fromhex(message), bytes.fromhex(signature)
            self.assertTrue(windows_feed.ed25519_verify(key, sig, [msg]))
            self.assertFalse(windows_feed.ed25519_verify(key, sig, [msg + b"\x00"]))
            self.assertFalse(windows_feed.ed25519_verify(key, sig[:-1] + bytes([sig[-1] ^ 1]), [msg]))

    def test_the_message_may_arrive_in_pieces(self):
        message = b"a" * 5000
        signature = _sign(SECRET, message)
        key = base64.b64decode(PUBLIC)
        self.assertTrue(windows_feed.ed25519_verify(key, signature, [message[:7], message[7:4096], message[4096:]]))

    def test_the_committed_feed_is_signed_by_the_key_the_app_carries(self):
        feed = WEBSITE / "updates" / "windows.xml"
        signature = (WEBSITE / "updates" / "windows.xml.signature").read_text(encoding="ascii")
        key = windows_feed.public_key()
        self.assertIsNotNone(key)
        self.assertTrue(windows_feed.verify_bytes(key, signature, feed.read_bytes()))
        # It is CR LF on purpose; the same feed with LF is refused.
        self.assertIn(b"\r\n", feed.read_bytes())
        self.assertFalse(windows_feed.verify_bytes(key, signature, feed.read_bytes().replace(b"\r\n", b"\n")))
        self.assertEqual([], windows_feed.problems_with(feed))


class CheckerTests(unittest.TestCase):

    def test_versions_compare_as_numbers(self):
        self.assertGreater(windows_feed.version_key("1.4.10"), windows_feed.version_key("1.4.9"))
        self.assertEqual(windows_feed.version_key("1.4"), windows_feed.version_key("1.4.0"))
        self.assertLess(windows_feed.version_key("1.4.x"), windows_feed.version_key("1.4.1"))

    def test_the_newest_item_is_found_by_version_not_by_place(self):
        feed = _feed(_item("1.4.2"), _item("1.4.10"), _item("1.4.9"))
        self.assertEqual("1.4.10", windows_feed.newest_item(feed)["version"])

    def test_a_good_two_item_feed_newest_first_passes(self):
        with _Folder() as folder:
            feed = folder.write(_feed(_item("1.4.3", notes="Back up first."), _item("1.4.2")))
            self.assertEqual([], windows_feed.problems_with(feed, PUBLIC))

    def test_each_fault_is_named(self):
        cases = {
            "first item is 1.4.2, but the newest is": _feed(_item("1.4.2"), _item("1.4.3")),
            "carries no signature for its download": _feed(_item("1.4.3", signature="")),
            "expected https://github.com/russellgordon/plantoir/releases/download/v1.4.3/PlantoirSetup.exe":
                _feed(_item("1.4.3", url="https://example.com/PlantoirSetup.exe")),
            "appears twice": _feed(_item("1.4.3"), _item("1.4.3")),
            "has no items": _feed(),
            "Plantoir-macOS.dmg": _feed(_item("1.4.3") + "<!-- Plantoir-macOS.dmg -->"),
        }
        for expected, feed_bytes in cases.items():
            with self.subTest(expected), _Folder() as folder:
                problems = windows_feed.problems_with(folder.write(feed_bytes), PUBLIC)
                self.assertTrue(any(expected in problem for problem in problems), problems)

    def test_a_feed_whose_signature_does_not_sign_it_is_refused(self):
        with _Folder() as folder:
            good = _feed(_item("1.4.3"))
            feed = folder.write(good.replace(b"\r\n", b"\n"), signature_of=good)
            self.assertTrue(any("does not sign these bytes" in p for p in windows_feed.problems_with(feed, PUBLIC)))
        with _Folder() as folder:
            feed = folder.write(_feed(_item("1.4.3")), signed=False)
            self.assertTrue(any("no windows.xml.signature" in p for p in windows_feed.problems_with(feed, PUBLIC)))

    def test_the_feed_must_offer_the_version_in_the_csproj(self):
        with _Folder() as folder:
            feed = folder.write(_feed(_item("1.4.2"), _item("1.4.3")))
            csproj = folder.path / "Plantoir.csproj"
            csproj.write_text("<Project><PropertyGroup><Version>1.4.3</Version></PropertyGroup></Project>")
            self.assertIsNone(windows_feed.version_refusal(feed, csproj))
            csproj.write_text("<Project><PropertyGroup><Version>1.4.4</Version></PropertyGroup></Project>")
            refusal = windows_feed.version_refusal(feed, csproj)
            self.assertIn("offers 1.4.3", refusal)
            self.assertIn("says 1.4.4", refusal)

    def test_the_committed_feed_agrees_with_the_committed_csproj(self):
        self.assertIsNone(windows_feed.version_refusal(WEBSITE / "updates" / "windows.xml"))


class LiveCheckTests(unittest.TestCase):

    def _run(self, feed_bytes: bytes, installer: bytes, signature_of: bytes | None = None, length=None,
             read_installer: bool = True):
        with _Folder() as folder:
            local = folder.write(feed_bytes, signature_of=signature_of)
            signature = (folder.path / "windows.xml.signature").read_bytes()

            def fetch(url, method):
                if url.endswith("/updates/windows.xml"):
                    return 200, {}, feed_bytes
                if url.endswith("/updates/windows.xml.signature"):
                    return 200, {}, signature
                return 200, {"Content-Length": str(len(installer) if length is None else length)}, b""

            def stream(url):
                return 200, iter([installer[:10], installer[10:]])

            with redirect_stdout(io.StringIO()) as said:
                outcome = windows_feed.verify_live("https://plantoir.app", local, PUBLIC, fetch, stream,
                                                   read_installer=read_installer)
            return outcome, said.getvalue()

    def test_a_live_feed_with_its_signed_installer_matches(self):
        outcome, said = self._run(_feed(_item("1.4.3"), _item("1.4.2")), INSTALLERS["1.4.3"])
        self.assertEqual("match", outcome, said)

    def test_the_newest_by_version_is_the_one_read_even_when_not_first(self):
        outcome, said = self._run(_feed(_item("1.4.2"), _item("1.4.3")), INSTALLERS["1.4.3"])
        self.assertEqual("match", outcome, said)
        self.assertIn("(1.4.3)", said)

    def test_an_installer_of_the_same_length_but_other_bytes_is_a_mismatch(self):
        other = bytes(len(INSTALLERS["1.4.3"]))
        outcome, said = self._run(_feed(_item("1.4.3")), other)
        self.assertEqual("mismatch", outcome)
        self.assertIn("not the installer the feed signed", said)

    def test_a_live_signature_that_does_not_sign_the_live_feed_is_a_mismatch(self):
        feed_bytes = _feed(_item("1.4.3"))
        outcome, said = self._run(feed_bytes, INSTALLERS["1.4.3"], signature_of=b"something else")
        self.assertEqual("mismatch", outcome)
        self.assertIn("does not sign the live feed", said)

    def test_where_the_installer_is_not_read_the_check_is_the_length_and_says_so(self):
        # A mac deploy (ruling 3): no 240 MB download; same-length other bytes pass, and the line says why.
        other = bytes(len(INSTALLERS["1.4.3"]))
        outcome, said = self._run(_feed(_item("1.4.3")), other, read_installer=False)
        self.assertEqual("match", outcome)
        self.assertIn("NOT read (length only", said)
        outcome, _ = self._run(_feed(_item("1.4.3")), INSTALLERS["1.4.3"], length=5, read_installer=False)
        self.assertEqual("mismatch", outcome)

    def test_the_installer_is_read_on_windows_or_when_asked(self):
        import os
        saved_platform, saved = sys.platform, os.environ.pop(windows_feed.READ_INSTALLER_VARIABLE, None)
        try:
            windows_feed.sys.platform = "darwin"
            self.assertFalse(windows_feed.reads_the_installer())
            os.environ[windows_feed.READ_INSTALLER_VARIABLE] = "1"
            self.assertTrue(windows_feed.reads_the_installer())
            del os.environ[windows_feed.READ_INSTALLER_VARIABLE]
            windows_feed.sys.platform = "win32"
            self.assertTrue(windows_feed.reads_the_installer())
        finally:
            windows_feed.sys.platform = saved_platform
            os.environ.pop(windows_feed.READ_INSTALLER_VARIABLE, None)
            if saved is not None:
                os.environ[windows_feed.READ_INSTALLER_VARIABLE] = saved

    def test_a_length_that_disagrees_is_a_mismatch(self):
        outcome, _ = self._run(_feed(_item("1.4.3")), INSTALLERS["1.4.3"], length=5)
        self.assertEqual("mismatch", outcome)


class CommittedFeedBytesRefusalTests(unittest.TestCase):
    """#428 item 7: build.py --deploy refuses a feed file whose working-copy
    bytes are not the committed ones."""

    def _updates(self, folder: Path, files: dict[str, bytes]) -> Path:
        updates = folder / "website" / "updates"
        updates.mkdir(parents=True)
        for name, data in files.items():
            (updates / name).write_bytes(data)
        return updates

    def test_identical_bytes_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            committed = {"macos.xml": b"<rss/>\n", "windows.xml": b"<rss/>\r\n", "windows.xml.signature": b"abc",
                         "macos-notes.html": b"<p>not a feed</p>"}
            updates = self._updates(repo, committed)
            show = lambda relative: committed.get(relative.rsplit("/", 1)[-1])
            self.assertIsNone(build.committed_feed_bytes_refusal(repo, updates, show))

    def test_line_endings_changed_by_a_checkout_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            committed = {"macos.xml": b"<rss/>\n", "windows.xml.signature": b"abc"}
            updates = self._updates(repo, {"macos.xml": b"<rss/>\r\n", "windows.xml.signature": b"abc"})
            show = lambda relative: committed.get(relative.rsplit("/", 1)[-1])
            refusal = build.committed_feed_bytes_refusal(repo, updates, show)
            self.assertIsNotNone(refusal)
            self.assertIn("website/updates/macos.xml", refusal)
            self.assertNotIn("windows.xml.signature", refusal)

    def test_a_changed_signature_file_and_an_uncommitted_feed_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            committed = {"windows.xml.signature": b"abc"}
            updates = self._updates(repo, {"windows.xml.signature": b"abd", "windows.xml": b"<rss/>"})
            show = lambda relative: committed.get(relative.rsplit("/", 1)[-1])
            refusal = build.committed_feed_bytes_refusal(repo, updates, show)
            self.assertIn("website/updates/windows.xml.signature", refusal)
            self.assertIn("website/updates/windows.xml (not committed)", refusal)

    def test_this_checkout_is_its_own_committed_bytes(self):
        # Run against the real repository and the real git: a fresh worktree
        # has the committed bytes, so this passes; on a checkout where it fails,
        # the deploy would have refused too — which is the point.
        self.assertIsNone(build.committed_feed_bytes_refusal())


if __name__ == "__main__":
    unittest.main()

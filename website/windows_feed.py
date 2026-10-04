"""The Windows update feed's own checker (#428 item 3).

``update_feeds.problems_with`` reads Sparkle's shape and is run on the mac
feed only. NetSparkle's ``windows.xml`` differs in three ways that matter, and
this module is the one place that knows them:

- **Its versions are not whole numbers** ("1.4.3"), so "newest" is a real
  version comparison, never ``int(build)`` (which scored every Windows item 0
  and made the first one in the file "newest").
- **Its signature is a file of its own**, ``windows.xml.signature``: Ed25519
  over the feed's exact bytes. It is VERIFIED here, with the public key the app
  carries (``AppUpdates.PublicKey``), so a feed whose line endings changed on
  the way (it is CR LF on purpose) fails before it is deployed rather than
  after, silently, on every teacher's daily check.
- **Each item carries its download's signature** as an attribute. The deploy's
  live check READS the newest download and verifies that signature, where the
  mac's compares only its length — on Windows, or when asked for with
  ``PLANTOIR_VERIFY_WINDOWS_INSTALLER=1``; from the mac it stays the length.

Pure standard library — Ed25519 verification included (RFC 8032 section 6,
below), since ``cryptography`` is not installed on either machine and a check
that needs a pip install is one that gets skipped. Runs on Windows and the mac
with plain ``python``.

Documented in RELEASING.md → "The update feed (Windows)".
"""

from __future__ import annotations

import base64
import hashlib
import os
import re
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ElementTree
from pathlib import Path
from typing import Callable, Iterable

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
RELEASE_DOWNLOADS = "https://github.com/russellgordon/plantoir/releases/download/"
ASSET = "PlantoirSetup.exe"
OTHER_PLATFORMS_ASSET = "Plantoir-macOS.dmg"

WEBSITE = Path(__file__).resolve().parent
REPO = WEBSITE.parent
APP_UPDATES_CS = REPO / "windows-app" / "Plantoir.Core" / "Assist" / "AppUpdates.cs"
CSPROJ = REPO / "windows-app" / "Plantoir" / "Plantoir.csproj"


# ---- Ed25519 verification (RFC 8032 section 6, verify only) -----------------

_P = 2 ** 255 - 19
_L = 2 ** 252 + 27742317777372353535851937790883648493
_D = -121665 * pow(121666, _P - 2, _P) % _P
_SQRT_M1 = pow(2, (_P - 1) // 4, _P)


def _add(a, b):
    p_ = _P
    aa = (a[1] - a[0]) * (b[1] - b[0]) % p_
    bb = (a[1] + a[0]) * (b[1] + b[0]) % p_
    cc = 2 * a[3] * b[3] * _D % p_
    dd = 2 * a[2] * b[2] % p_
    e, f, g, h = bb - aa, dd - cc, dd + cc, bb + aa
    return (e * f % p_, g * h % p_, f * g % p_, e * h % p_)


def _mul(scalar: int, point):
    result = (0, 1, 1, 0)
    while scalar > 0:
        if scalar & 1:
            result = _add(result, point)
        point = _add(point, point)
        scalar >>= 1
    return result


def _equal(a, b) -> bool:
    return (a[0] * b[2] - b[0] * a[2]) % _P == 0 and (a[1] * b[2] - b[1] * a[2]) % _P == 0


def _recover_x(y: int, sign: int):
    if y >= _P:
        return None
    x2 = (y * y - 1) * pow(_D * y * y + 1, _P - 2, _P) % _P
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (_P + 3) // 8, _P)
    if (x * x - x2) % _P != 0:
        x = x * _SQRT_M1 % _P
    if (x * x - x2) % _P != 0:
        return None
    if (x & 1) != sign:
        x = _P - x
    return x


def _decompress(data: bytes):
    if len(data) != 32:
        return None
    y = int.from_bytes(data, "little")
    sign = y >> 255
    y &= (1 << 255) - 1
    x = _recover_x(y, sign)
    if x is None:
        return None
    return (x, y, 1, x * y % _P)


_GY = 4 * pow(5, _P - 2, _P) % _P
_G = (_recover_x(_GY, 0), _GY, 1, _recover_x(_GY, 0) * _GY % _P)


def ed25519_verify(public_key: bytes, signature: bytes, message_chunks: Iterable[bytes]) -> bool:
    """Whether ``signature`` is ``public_key``'s Ed25519 signature of the
    concatenated chunks. Streams the message, so a 240 MB installer is never
    held in memory."""
    if len(public_key) != 32 or len(signature) != 64:
        return False
    a = _decompress(public_key)
    r = _decompress(signature[:32])
    if a is None or r is None:
        return False
    s = int.from_bytes(signature[32:], "little")
    if s >= _L:
        return False
    digest = hashlib.sha512(signature[:32] + public_key)
    for chunk in message_chunks:
        digest.update(chunk)
    h = int.from_bytes(digest.digest(), "little") % _L
    return _equal(_mul(s, _G), _add(r, _mul(h, a)))


def verify_bytes(public_key_b64: str, signature_b64: str, data: bytes) -> bool:
    try:
        key = base64.b64decode(public_key_b64.strip(), validate=True)
        signature = base64.b64decode(signature_b64.strip(), validate=True)
    except ValueError:
        return False
    return ed25519_verify(key, signature, [data])


# ---- What the repository says -----------------------------------------------

def public_key(app_updates_cs: Path = APP_UPDATES_CS) -> str | None:
    """``AppUpdates.PublicKey``: the key every installed copy checks against."""
    match = re.search(r'PublicKey\s*=\s*"([A-Za-z0-9+/=]+)"', app_updates_cs.read_text(encoding="utf-8"))
    return match.group(1) if match else None


def csproj_version(csproj: Path = CSPROJ) -> str | None:
    """``<Version>`` in Plantoir.csproj: the version the next installer carries."""
    match = re.search(r"<Version>\s*([^<\s]+)\s*</Version>", csproj.read_text(encoding="utf-8"))
    return match.group(1) if match else None


def version_key(text: str) -> tuple[int, ...]:
    """"1.4.10" > "1.4.9": compared as numbers, part by part. A part that is
    not a number counts as -1, so a malformed version is never "newest"."""
    parts: list[int] = []
    for part in (text or "").strip().split("."):
        parts.append(int(part) if part.isdigit() else -1)
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


# ---- Reading the feed ----------------------------------------------------------

def items_of(feed_bytes: bytes) -> list[dict]:
    """Every item, in file order: version, url, length, the download's
    signature, and whether it carries notes."""
    root = ElementTree.fromstring(feed_bytes)
    found: list[dict] = []
    for item in root.iter("item"):
        enclosure = item.find("enclosure")
        attributes = enclosure.attrib if enclosure is not None else {}
        version = (attributes.get(f"{{{SPARKLE_NAMESPACE}}}version")
                   or item.findtext(f"{{{SPARKLE_NAMESPACE}}}version") or "").strip()
        signature = (attributes.get(f"{{{SPARKLE_NAMESPACE}}}signature")
                     or attributes.get(f"{{{SPARKLE_NAMESPACE}}}edSignature") or "").strip()
        found.append({
            "version": version,
            "url": attributes.get("url", ""),
            "length": attributes.get("length", ""),
            "signature": signature,
            "notes": (item.findtext("description") or "").strip(),
        })
    return found


def newest_item(feed_bytes: bytes) -> dict | None:
    """The item the updater offers: the highest version, wherever it is in the file."""
    newest: dict | None = None
    for item in items_of(feed_bytes):
        if newest is None or version_key(item["version"]) > version_key(newest["version"]):
            newest = item
    return newest


def problems_with(feed: Path, key: str | None = None) -> list[str]:
    """Why ``windows.xml`` must not be published, or an empty list.

    Asked by ``build.py`` in every mode, beside the mac feed's checker."""
    name = f"updates/{feed.name}"
    if key is None:
        key = public_key()
    data = feed.read_bytes()
    try:
        items = items_of(data)
    except ElementTree.ParseError as error:
        return [f"{name}: not well-formed XML ({error})"]

    problems: list[str] = []
    signature_file = feed.with_name(feed.name + ".signature")
    if not signature_file.is_file():
        problems.append(f"{name}: no {signature_file.name} beside it — the app refuses an unsigned feed")
    elif not key:
        problems.append(f"{name}: could not read AppUpdates.PublicKey to check {signature_file.name}")
    elif not verify_bytes(key, signature_file.read_text(encoding="ascii", errors="replace"), data):
        problems.append(f"{name}: {signature_file.name} does not sign these bytes (were its line endings "
                        f"changed? it is CR LF on purpose) — every installed copy would refuse it")

    if not items:
        problems.append(f"{name}: has no items")
    seen: set[tuple[int, ...]] = set()
    for item in items:
        label = item["version"] or "an item with no version"
        if version_key(item["version"]) in seen:
            problems.append(f"{name}: {label} appears twice")
        seen.add(version_key(item["version"]))
        if not item["signature"]:
            problems.append(f"{name}: {label} carries no signature for its download — the app refuses it")
        expected = f"{RELEASE_DOWNLOADS}v{item['version']}/{ASSET}"
        if item["url"] != expected:
            problems.append(f"{name}: {label} downloads {item['url'] or 'nothing'}, expected {expected}")
    newest = newest_item(data) if items else None
    if newest is not None and items[0] is not newest and items[0]["version"] != newest["version"]:
        problems.append(f"{name}: the first item is {items[0]['version']}, but the newest is "
                        f"{newest['version']} — the generator writes the newest first, so the file was "
                        f"edited by hand")
    if OTHER_PLATFORMS_ASSET.encode() in data:
        problems.append(f"{name}: names {OTHER_PLATFORMS_ASSET}, the other platform's download")
    return problems


def version_refusal(feed: Path, csproj: Path = CSPROJ) -> str | None:
    """Why the Windows feed must not be deployed with this site, or None —
    the Windows twin of ``build.feed_version_refusal``.

    Deploys run from ``main``, where the feed's newest version and
    ``<Version>`` agree after a Windows cut, and still agree after a mac-only
    cut, which leaves both alone."""
    if not feed.is_file():
        return None
    newest = newest_item(feed.read_bytes())
    ours = csproj_version(csproj)
    newest_version = newest["version"] if newest else None
    if newest_version is None or ours is None or version_key(newest_version) != version_key(ours):
        return (f"Not deploying: updates/{feed.name} offers {newest_version}, but "
                f"windows-app/Plantoir/Plantoir.csproj says {ours}. Rebuild the feed at the cut "
                f"(RELEASING.md → \"The update feed (Windows)\").")
    return None


# ---- The live check, after a deploy -------------------------------------------

def _fetch(url: str, method: str) -> tuple[int, dict, bytes]:
    request = urllib.request.Request(
        url, method=method, headers={"Cache-Control": "no-cache", "Pragma": "no-cache"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read() if method == "GET" else b""
            return response.status, dict(response.headers), body
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers or {}), b""


def _stream(url: str) -> tuple[int, Iterable[bytes]]:
    response = urllib.request.urlopen(urllib.request.Request(url), timeout=60)

    def chunks():
        with response:
            while True:
                chunk = response.read(1 << 20)
                if not chunk:
                    return
                yield chunk
    return response.status, chunks()


READ_INSTALLER_VARIABLE = "PLANTOIR_VERIFY_WINDOWS_INSTALLER"


def reads_the_installer() -> bool:
    """Whether the live check downloads the newest installer to verify its
    signature: on Windows, where the installer is cut, or anywhere when
    ``PLANTOIR_VERIFY_WINDOWS_INSTALLER=1`` asks for it (#428 review, ruling 3).
    A deploy from the mac — a mac-only cut included — would otherwise pull
    about 240 MB from GitHub every time, for a feed it did not change."""
    return sys.platform == "win32" or os.environ.get(READ_INSTALLER_VARIABLE, "") == "1"


def verify_live(base_url: str, local_feed: Path, key: str | None = None,
                fetch: Callable | None = None, stream: Callable | None = None,
                read_installer: bool | None = None) -> str:
    """The live Windows feed is these bytes, its live signature file signs
    them, and its NEWEST download (by version) is there, is as long as the
    feed says, and is signed by the key the app carries.

    "match", "mismatch" or "unknown", as ``update_feeds.verify_live``. Reads
    the whole installer (about 240 MB) to check its signature: that is the
    part the length could not prove — a re-built installer of the same size
    passes a length check and is refused by every installed copy. Only where
    ``reads_the_installer()`` says so (or ``read_installer``); elsewhere the
    download's check is its length, as before #428, and the line says so."""
    fetch = fetch or _fetch
    stream = stream or _stream
    key = key or public_key()
    base = f"{base_url.rstrip('/')}/updates/"
    feed_url = base + local_feed.name
    signature_url = feed_url + ".signature"
    try:
        status, _, body = fetch(feed_url, "GET")
        signature_status, _, signature = fetch(signature_url, "GET")
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        print(f"⚠️ Could not fetch {feed_url} ({error}); check it by hand.")
        return "unknown"
    if status != 200 or signature_status != 200:
        print(f"❌ {feed_url} answered {status}; its signature answered {signature_status}.")
        return "mismatch"
    if body != local_feed.read_bytes():
        print(f"❌ {feed_url} is not the feed in site/. A changed byte breaks its signature.")
        return "mismatch"
    if not key or not verify_bytes(key, signature.decode("ascii", errors="replace"), body):
        print(f"❌ {signature_url} does not sign the live feed. Every installed copy refuses it.")
        return "mismatch"
    newest = newest_item(body)
    if newest is None:
        print(f"❌ {feed_url} has no items.")
        return "mismatch"
    try:
        status, headers, _ = fetch(newest["url"], "HEAD")
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        print(f"⚠️ Could not reach {newest['url']} ({error}); check it by hand.")
        return "unknown"
    if status != 200:
        print(f"❌ The newest update, {newest['version']}, points at {newest['url']}, which answered "
              f"{status}. Was the feed deployed before its release was published?")
        return "mismatch"
    length = headers.get("Content-Length", "")
    if length and newest["length"] and length != newest["length"]:
        print(f"❌ {newest['url']} is {length} bytes; the feed says {newest['length']}.")
        return "mismatch"
    if read_installer is None:
        read_installer = reads_the_installer()
    if not read_installer:
        print(f"✅ {feed_url} is live, signed as committed, and its newest download ({newest['version']}) "
              f"is there at the length the feed says. Its signature was NOT read (length only; "
              f"set {READ_INSTALLER_VARIABLE}=1 to read the installer).")
        return "match"
    print(f"   Reading {newest['url']} to check its signature…")
    try:
        status, chunks = stream(newest["url"])
        counted = 0

        def counting():
            nonlocal counted
            for chunk in chunks:
                counted += len(chunk)
                yield chunk
        signed = ed25519_verify(base64.b64decode(key), base64.b64decode(newest["signature"] or ""), counting())
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as error:
        print(f"⚠️ Could not read {newest['url']} ({error}); its signature is unchecked.")
        return "unknown"
    if status != 200 or not signed:
        print(f"❌ {newest['url']} is not the installer the feed signed. Every installed copy would "
              f"refuse the update.")
        return "mismatch"
    if newest["length"] and str(counted) != newest["length"]:
        print(f"❌ {newest['url']} is {counted} bytes; the feed says {newest['length']}.")
        return "mismatch"
    print(f"✅ {feed_url} is live, signed as committed, and its newest download ({newest['version']}) "
          f"is there and signed.")
    return "match"

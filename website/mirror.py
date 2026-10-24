#!/usr/bin/env python3
"""
plantoir.app's mirror of the files the website builder downloads (#578).

The image build fetches GeoGebra's bundle from download.geogebra.org, which
is FLAKY (4 of 8 connections timed out, 2026-10-23) and keeps no old
versions. So the same zip is served from https://plantoir.app/mirror/, the
second address in contracts/toolchain.json -> pins -> geogebra -> urls, and
the Dockerfile falls back to it - checking the same SHA-256 whichever
answered.

What is mirrored is listed in website/site.json -> "mirror": every version a
released app still names (a released Dockerfile names its own mirror
address, so a version stays listed until no supported release names it).

The files are NEVER committed (the repository ships recipes, not binaries;
33.5 MB in every clone, and every bump kept in history forever), so
``site/mirror/`` is git-ignored and filled here from a cache OUTSIDE the
repository (``$PLANTOIR_MIRROR_CACHE``, else
``~/Library/Caches/Plantoir-dev/mirror``), which is filled from each entry's
``source`` the first time, with retries, and checked against its SHA-256.

``build.py --deploy`` refuses while a listed file is missing from
``site/mirror/`` or is not its SHA-256 (``deploy_refusal``): a mirror that
404s is invisible until GeoGebra's own host is down on the day a teacher's
first preview needs it, and then that teacher's build fails. ``--verify-deploy``
fetches each one back from the live site (``verify_live``).

Stdlib only.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

MIRROR_FOLDER = "mirror"
ATTEMPTS = 6
TIMEOUT_SECONDS = 60


def cache_dir() -> Path:
    named = os.environ.get("PLANTOIR_MIRROR_CACHE", "").strip()
    if named:
        return Path(named).expanduser()
    return Path.home() / "Library" / "Caches" / "Plantoir-dev" / "mirror"


def entries(site: dict) -> list:
    return list(site.get("mirror", {}).get("files", []))


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _is_safe_relative(name: str) -> bool:
    parts = name.split("/")
    if not name or name.startswith("/") or "\\" in name or len(parts) < 2:
        return False
    for part in parts:
        if part in ("", ".", "..") or part.startswith("."):
            return False
    return True


def entry_problems(site: dict, pins: list) -> list:
    """
    What is wrong with site.json's list, or [] - checked in --check too.

    Every entry names a file in a folder under mirror/ (never the site root:
    netlify_deploy.build_manifest skips a .zip there), a SHA-256 and an https
    source; and every pin whose `urls` name a plantoir.app mirror address has
    an entry for that file with the pin's SHA-256, so bumping a pin without
    mirroring the new version is caught here rather than on the day
    download.geogebra.org is down.
    """
    problems = []
    listed = {}
    base = site.get("base_url", "").rstrip("/")
    for entry in entries(site):
        name = entry.get("file", "")
        if not _is_safe_relative(name):
            problems.append(f"site.json mirror: {name!r} must be a file in a folder under mirror/")
            continue
        digest = entry.get("sha256", "")
        if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
            problems.append(f"site.json mirror: {name} has no SHA-256")
        if not str(entry.get("source", "")).startswith("https://"):
            problems.append(f"site.json mirror: {name} has no https source to fill the cache from")
        if name in listed:
            problems.append(f"site.json mirror: {name} is listed twice")
        listed[name] = digest
    prefix = f"{base}/{MIRROR_FOLDER}/"
    for pin in pins:
        for url in pin.get("urls", []):
            if not base or not url.startswith(prefix):
                continue
            name = url[len(prefix):]
            if name not in listed:
                problems.append(f"contracts/toolchain.json pin {pin.get('pin')} names {url}, "
                                f"but site.json mirror does not list {name}")
            elif listed[name] != pin.get("sha256"):
                problems.append(f"site.json mirror: {name}'s SHA-256 is not the {pin.get('pin')} pin's")
    return problems


def download(url: str, destination: Path, attempts: int = ATTEMPTS, pause=time.sleep) -> None:
    """Fetch `url` into `destination`, retrying; raises OSError when every attempt failed."""
    last_error = None
    delay = 2.0
    for attempt in range(attempts):
        if attempt:
            pause(min(delay, 30.0))
            delay *= 2
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "plantoir-website-build"})
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response, \
                    open(destination, "wb") as handle:
                shutil.copyfileobj(response, handle, 1024 * 1024)
            return
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last_error = error
    raise OSError(f"{url} did not answer after {attempts} attempts ({last_error})")


def _cached_copy(entry: dict, cache: Path, fetch) -> Path:
    """The verified file in the cache, downloading it the first time."""
    cached = cache.joinpath(*entry["file"].split("/"))
    if cached.is_file() and sha256_of(cached) == entry["sha256"]:
        return cached
    cached.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=".download-", dir=str(cached.parent))
    os.close(handle)
    temporary = Path(temporary)
    try:
        fetch(entry["source"], temporary)
        actual = sha256_of(temporary)
        if actual != entry["sha256"]:
            raise OSError(f"{entry['source']} gave SHA-256 {actual}, not {entry['sha256']}")
        os.replace(temporary, cached)
    finally:
        if temporary.exists():
            temporary.unlink()
    return cached


def fill(site: dict, output: Path, cache: Path | None = None, fetch=None,
         attempts: int = ATTEMPTS) -> list:
    """
    Put every listed file into output/mirror/, from the cache, and take out
    anything there that is not listed. Never raises: answers the lines to
    print, and a file it could not get is simply missing, which the deploy
    then refuses.

    `attempts` is how often a missing cache entry is downloaded before giving
    up. build.py passes ATTEMPTS only for --deploy, where the file must be
    there, and 1 otherwise: six 60-second tries of a 33 MB download would
    stall an offline `build.py` or `--serve` for minutes over a file nothing
    but the deploy needs (stage-1 review, 2026-10-24).
    """
    cache = cache if cache is not None else cache_dir()
    if fetch is None:
        def fetch(url, destination):
            download(url, destination, attempts=attempts)
    folder = Path(output) / MIRROR_FOLDER
    said = []
    wanted = set()
    for entry in entries(site):
        name = entry.get("file", "")
        if not _is_safe_relative(name):
            continue
        wanted.add(name)
        target = folder.joinpath(*name.split("/"))
        try:
            if target.is_file() and sha256_of(target) == entry["sha256"]:
                continue
            source = _cached_copy(entry, cache, fetch)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            said.append(f"🪞 Mirrored {name} into site/{MIRROR_FOLDER}/ from {cache}.")
        except OSError as error:
            if target.exists():
                target.unlink()
            said.append(f"⚠️  Could not mirror {name}: {error}. The deploy will refuse until it is there.")
    if folder.is_dir():
        for existing in sorted(folder.rglob("*"), reverse=True):
            relative = existing.relative_to(folder).as_posix()
            if existing.is_file() and relative not in wanted:
                existing.unlink()
            elif existing.is_dir() and not any(existing.iterdir()):
                existing.rmdir()
    return said


def deploy_refusal(site: dict, output: Path) -> str | None:
    """Why site/ must not be deployed, or None: a listed mirror file is missing or wrong."""
    folder = Path(output) / MIRROR_FOLDER
    wrong = []
    for entry in entries(site):
        name = entry.get("file", "")
        target = folder.joinpath(*name.split("/")) if _is_safe_relative(name) else None
        if target is None or not target.is_file():
            wrong.append(f"site/{MIRROR_FOLDER}/{name} is missing")
        elif sha256_of(target) != entry.get("sha256"):
            wrong.append(f"site/{MIRROR_FOLDER}/{name} is not SHA-256 {entry.get('sha256')}")
    if not wrong:
        return None
    listed = "\n  ".join(wrong)
    return ("Not deploying: plantoir.app's mirror would not serve what the website builder falls back to "
            "when GeoGebra's own download does not answer, and a teacher's first build would then fail:\n  "
            + listed + "\nBuild again with the network (website/build.py fills site/mirror/ from "
            "$PLANTOIR_MIRROR_CACHE or ~/Library/Caches/Plantoir-dev/mirror), then deploy.")


def _fetch_bytes(url: str) -> tuple:
    request = urllib.request.Request(url, headers={"Cache-Control": "no-cache", "Pragma": "no-cache",
                                                   "User-Agent": "plantoir-website-verify"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, b""


def verify_live(site: dict, fetch=None) -> str:
    """
    Each listed file, fetched back from the live site, is its SHA-256.
    "match", "mismatch" (served wrong, or not at all) or "unknown" (the
    network did not answer) - the same three answers as the feeds' check,
    for the same reason. Advisory after a deploy.
    """
    fetch = fetch or _fetch_bytes
    base = site.get("base_url", "").rstrip("/")
    outcome = "match"
    for entry in entries(site):
        url = f"{base}/{MIRROR_FOLDER}/{entry.get('file', '')}"
        try:
            status, body = fetch(url)
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            print(f"⚠️ Could not fetch {url} ({error}); check it by hand.")
            if outcome == "match":
                outcome = "unknown"
            continue
        if status != 200:
            print(f"❌ {url} answered {status}: the image build's fallback for it is not there.")
            outcome = "mismatch"
            continue
        live = hashlib.sha256(body).hexdigest()
        if live != entry.get("sha256"):
            print(f"❌ {url} is SHA-256 {live[:12]}…, not {str(entry.get('sha256'))[:12]}….")
            outcome = "mismatch"
            continue
        print(f"✅ {url} is live, {len(body):,} bytes, SHA-256 matching.")
    return outcome

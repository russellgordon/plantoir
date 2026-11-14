#!/usr/bin/env python3
"""
Files a build downloads the first time a page uses them, and keeps (#674).

Some of what a class site carries is not Plantoir's to ship and is too large
to put in the website builder: a PhET simulation (#674, 2.6 to 4.8 MB each,
127 of them) and, with #679, the sounds a tune names (about 2 MB each, 128 of
them). Russell's rulings say both are downloaded to the teacher's computer
on the first build whose pages use one, kept, and copied into the site from
there; a build with no internet that needs one it does not have STOPS, in
words, before the site is made (contracts/shared-rules.json -> keptDownloads,
phetFences.stop).

This module is that ONE rule for every such kind, so #679 uses it unchanged:

* **Where.** `.downloaded/<kind>/` in the WORKING FOLDER's builds folder,
  beside the courses' built sites: `~/Library/Application Support/Plantoir/
  builds/<folder id>/.downloaded/` on a Mac, `%LOCALAPPDATA%\\Plantoir\\builds\\
  <folder id>\\.downloaded\\` on Windows (root_for). One copy serves every
  course and section of the working folder. The Mac's website builder sees it
  at the same absolute path, because the builds folder is the second of its
  two mounts (CLAUDE.md, "How the toolchain ships"); nothing new is mounted.
* **What an entry is.** `<kind>/<name>/<version>/`: the files, and
  `kept.json` naming each file's SHA-256 and size, where it came from and
  when, and what the kind wants to remember (a simulation's titles). An
  entry is written in a hidden folder beside it and RENAMED into place, so
  two sections built at once never read half of one; the second to finish
  throws its own copy away.
* **Pinned.** Every file's SHA-256 is checked every time an entry is used.
  A kind whose hashes are known before the download (#679's sounds, pinned
  in contracts/toolchain.json) passes them to `put` and a download that does
  not match is refused; a kind whose files have no published checksum
  (PhET publishes none, measured 2026-11-13) records the hash of what it
  checked and kept, and from then on that copy is what every build uses. An
  entry whose files no longer match is thrown away and counts as not
  downloaded.
* **Kept for ever, pruned when unused.** Every build that uses an entry
  touches its kept.json; an entry unused for figures.PRUNE_DAYS (90) goes.
  Nothing is ever downloaded again on its own: a site must not change under
  a teacher mid-unit, and a build must not need the internet once it has
  what it needs.
* **Asking.** `Fetcher`: https only, to the kind's own hosts (a redirect
  anywhere else is refused), a ceiling on size, a body shorter than its
  Content-Length refused (GeoGebra's lesson, geogebraFences.fetch), and each
  failure sorted into the reason the teacher is told: `offline` (no answer,
  a timeout, a refusal, a server error, an answer from somewhere else, a
  cut-off body) or `notFound` (404 or 410: the address names nothing).
  A kind's own checks decide `damaged`.

Every rule a case can pin is in contracts/shared-rules.json ->
keptDownloads, run by scripts/test_kept_downloads.py. The reasons, the
measurements and what was rejected are in documentation/05-build-pipeline.md
-> "Files downloaded when a page first uses them".
"""

import hashlib
import http.client
import json
import os
import re
import shutil
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import contracts
import figures

FOLDER = ".downloaded"
RECORD = "kept.json"
MARKER = "PLANTOIR_DOWNLOADED:"
# The name of an entry or a version: what a kind may use as a folder name.
_SAFE_NAME = re.compile(r"^[a-z0-9][a-z0-9._-]{0,79}$")


def rules(*keys):
    return contracts.section("shared-rules", "keptDownloads", *keys)


# ---- Where ---------------------------------------------------------------------

def root_for(course_dir, environ=None) -> Path:
    """
    The working folder's `.downloaded` folder (keptDownloads.where): beside
    the courses' built sites in the working folder's builds folder.

    * Windows' layout (PLANTOIR_BUILD_ROOT is that builds folder): straight
      inside it.
    * The Mac's layout (courses/<CODE>/.merged_output is a link to
      builds/<folder id>/<CODE>): inside the folder the link's target is in.
    * A course whose .merged_output is still a real folder inside the course
      (a folder from before the builds moved, not yet built again): inside
      that .merged_output, so nothing is ever written among the teacher's
      notes. The next build moves the site out and starts a new `.downloaded`
      in the builds folder; the old one goes with the old .merged_output.
    """
    environ = os.environ if environ is None else environ
    build_root = str(environ.get("PLANTOIR_BUILD_ROOT", "")).strip()
    if build_root:
        return Path(build_root) / FOLDER
    course = Path(course_dir)
    link = course / ".merged_output"
    try:
        if link.is_symlink():
            return link.resolve().parent / FOLDER
    except OSError:
        pass
    return link / FOLDER


# ---- Asking --------------------------------------------------------------------

class DownloadFailed(Exception):
    """A download that did not happen: `reason` is offline or notFound."""

    def __init__(self, reason: str, detail: str = ""):
        super().__init__(detail or reason)
        self.reason = reason


class _OwnHostsOnly(urllib.request.HTTPRedirectHandler):
    """Follows a redirect only to one of the kind's own hosts, over https."""

    def __init__(self, hosts, schemes):
        super().__init__()
        self.hosts = hosts
        self.schemes = schemes

    def redirect_request(self, request, fp, code, message, headers, new_url):
        address = urllib.parse.urlsplit(new_url)
        if address.scheme not in self.schemes or (address.hostname or "").lower() not in self.hosts:
            raise urllib.error.URLError(f"a redirect left the download's own hosts: {address.hostname}")
        return super().redirect_request(request, fp, code, message, headers, new_url)


class Fetcher:
    """
    Asks a kind's own hosts for one file at a time (keptDownloads.asking).
    `get(url)` answers the bytes or raises DownloadFailed. A test passes its
    own local server's host and the http scheme; the product never does.
    """

    def __init__(self, hosts, schemes=("https",), timeout=None, largest_bytes=None):
        asking = rules("asking")
        self.hosts = tuple(host.lower() for host in hosts)
        self.schemes = tuple(schemes)
        self.timeout = timeout or asking["requestSeconds"]
        self.largest = largest_bytes or int(asking["largestFileMegabytes"]) * 1024 * 1024
        self.requests = 0
        self.received = 0
        self.opener = urllib.request.build_opener(_OwnHostsOnly(self.hosts, self.schemes))

    def allowed(self, url: str) -> bool:
        address = urllib.parse.urlsplit(url)
        return address.scheme in self.schemes and (address.hostname or "").lower() in self.hosts

    def get(self, url: str) -> bytes:
        if not self.allowed(url):
            raise DownloadFailed("offline", f"not one of the download's own hosts: {url}")
        self.requests += 1
        # Accept */*, never text/html: PhET's servers add a third party's
        # script to an HTML answer when a request says it wants HTML
        # (keptDownloads.asking.accept, measured 2026-11-13).
        request = urllib.request.Request(url, headers={
            "User-Agent": "Plantoir", "Accept": rules("asking", "accept"), "Accept-Encoding": "identity"})
        try:
            with self.opener.open(request, timeout=self.timeout) as answer:
                data = answer.read(self.largest + 1)
                promised = answer.headers.get("Content-Length")
        except urllib.error.HTTPError as error:
            error.close()
            if error.code in rules("asking", "notFoundStatuses"):
                raise DownloadFailed("notFound", f"HTTP {error.code}") from None
            raise DownloadFailed("offline", f"HTTP {error.code}") from None
        except (OSError, ValueError, http.client.HTTPException, urllib.error.URLError) as error:
            # http.client.HTTPException is not an OSError: a body cut off
            # mid-answer (IncompleteRead) is one (geogebraFences.fetch).
            raise DownloadFailed("offline", str(error)) from None
        if len(data) > self.largest:
            raise DownloadFailed("offline", "larger than any file this download can be")
        if promised is not None and promised.strip().isdigit() and len(data) != int(promised.strip()):
            raise DownloadFailed("offline", f"{len(data)} of {promised.strip()} bytes arrived")
        self.received += len(data)
        return data


# ---- Keeping -------------------------------------------------------------------

def sha256_of(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_name(name: str) -> bool:
    return bool(_SAFE_NAME.match(str(name or "")))


def _version_key(version: str):
    parts = []
    for piece in re.split(r"[.\-]", version):
        parts.append((0, int(piece), "") if piece.isdigit() else (1, 0, piece))
    return parts


class Store:
    """
    One kind's kept entries: `<root>/<kind>/<name>/<version>/`
    (keptDownloads.entries). `root` is root_for's answer, or None when there
    is nowhere to keep anything (then nothing is kept and nothing is found).
    """

    def __init__(self, root, kind: str):
        self.root = Path(root) / kind if root is not None else None
        self.kind = kind

    def _entry_folder(self, name: str, version: str) -> Path:
        return self.root / name / version

    def versions(self, name: str) -> list:
        """The versions of `name` kept here, newest first (by number)."""
        if self.root is None or not safe_name(name):
            return []
        try:
            found = [entry.name for entry in (self.root / name).iterdir()
                     if entry.is_dir() and not entry.name.startswith(".")]
        except OSError:
            return []
        found.sort(key=_version_key, reverse=True)
        return found

    def get(self, name: str, version: str = None, expected: dict = None):
        """
        The kept entry, checked file by file, or None: {"name", "version",
        "folder" (a Path), "files" {file: {"sha256", "bytes"}}, "about"}.
        With no `version`, the newest kept. `expected` ({file: sha256}) must
        match too, when given. An entry that fails is thrown away.
        """
        if self.root is None or not safe_name(name):
            return None
        candidates = [version] if version is not None else self.versions(name)
        for candidate in candidates:
            if not safe_name(candidate):
                continue
            entry = self._checked(name, candidate, expected)
            if entry is not None:
                return entry
        return None

    def _checked(self, name: str, version: str, expected):
        folder = self._entry_folder(name, version)
        record_path = folder / RECORD
        if not record_path.is_file():
            return None
        try:
            record = json.loads(record_path.read_text(encoding="utf-8"))
            files = record["files"]
            for file_name, wanted in files.items():
                if not safe_name(file_name.lower()) or "/" in file_name or "\\" in file_name:
                    raise ValueError("not a file name")
                data = (folder / file_name).read_bytes()
                if len(data) != int(wanted["bytes"]) or sha256_of(data) != wanted["sha256"]:
                    raise ValueError("changed since it was kept")
                if expected is not None and expected.get(file_name) not in (None, wanted["sha256"]):
                    raise ValueError("not the pinned file")
        except (OSError, ValueError, KeyError, TypeError):
            # Not what was kept: thrown away, so the next build that is
            # online downloads it again (keptDownloads.entries.checked).
            shutil.rmtree(folder, ignore_errors=True)
            return None
        try:
            os.utime(record_path, None)
        except OSError:
            pass
        return {"name": name, "version": version, "folder": folder, "files": files,
                "about": record.get("about") or {}}

    def put(self, name: str, version: str, files: dict, about: dict = None, sources: dict = None,
            expected: dict = None):
        """
        Keeps `files` ({file name: bytes}) as `name` at `version`, and
        answers the entry as get() would, or None when it could not be kept
        (then the build uses the bytes it has, once). `expected`
        ({file: sha256}) refuses a file that does not match: raises
        ValueError, nothing kept.
        """
        if expected is not None:
            for file_name, data in files.items():
                if file_name in expected and sha256_of(data) != expected[file_name]:
                    raise ValueError(f"{file_name} is not the pinned file")
        if self.root is None or not safe_name(name) or not safe_name(version):
            return None
        record = {
            "name": name,
            "version": version,
            "files": {file_name: {"sha256": sha256_of(data), "bytes": len(data)}
                      for file_name, data in files.items()},
            "from": dict(sources or {}),
            "downloadedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "about": dict(about or {}),
        }
        target = self._entry_folder(name, version)
        hidden = self.root / name / f".{version}.{os.getpid()}.{threading.get_ident()}.tmp"
        try:
            shutil.rmtree(hidden, ignore_errors=True)
            hidden.mkdir(parents=True)
            for file_name, data in files.items():
                (hidden / file_name).write_bytes(data)
            (hidden / RECORD).write_text(json.dumps(record, ensure_ascii=False, indent=1) + "\n",
                                         encoding="utf-8")
            try:
                os.rename(hidden, target)
            except OSError:
                # Another build kept it first: theirs is used, ours goes.
                shutil.rmtree(hidden, ignore_errors=True)
        except OSError:
            shutil.rmtree(hidden, ignore_errors=True)
            return None
        return self.get(name, version)

    def prune(self, now=None) -> list:
        """Every entry unused for figures.PRUNE_DAYS goes, and a hidden
        half-written folder older than a day. Answers what went."""
        if self.root is None:
            return []
        now = time.time() if now is None else now
        gone = []
        try:
            names = [entry for entry in self.root.iterdir() if entry.is_dir()]
        except OSError:
            return gone
        for name in names:
            try:
                versions = list(name.iterdir())
            except OSError:
                continue
            for version in versions:
                try:
                    if version.name.startswith("."):
                        if now - version.stat().st_mtime > 86400:
                            shutil.rmtree(version, ignore_errors=True)
                        continue
                    record = version / RECORD
                    stamp = record.stat().st_mtime if record.is_file() else version.stat().st_mtime
                    if now - stamp > figures.PRUNE_DAYS * 86400:
                        shutil.rmtree(version, ignore_errors=True)
                        gone.append(f"{name.name}/{version.name}")
                except OSError:
                    continue
            try:
                name.rmdir()
            except OSError:
                pass
        return gone


# ---- Saying --------------------------------------------------------------------

def _filled(template: str, values: dict) -> str:
    """Every {name} in ONE pass, so a value holding braces is never refilled."""
    return re.sub(r"\{([A-Za-z]+)\}", lambda match: str(values.get(match.group(1), match.group(0))), template)


def what(kind: str, count: int) -> str:
    """'a science simulation', '3 science simulations' (keptDownloads.kinds)."""
    said = rules("kinds", kind)
    if count == 1:
        return said["one"]
    return f"{count} {said['several']}"


def marker_line(kind: str, course: str, section, *, downloaded=None, failed=None) -> str:
    """
    The one PLANTOIR_DOWNLOADED: line a build prints for a kind
    (keptDownloads.marker): {"kind", "course", "section", "downloaded": n,
    "bytes", "seconds"} when it downloaded something, or {"kind", "course",
    "section", "failed": n, "reason"} when it stopped. Names no page.
    """
    payload = {"kind": kind, "course": course, "section": section}
    if downloaded is not None:
        payload.update({"downloaded": int(downloaded["count"]), "bytes": int(downloaded["bytes"]),
                        "seconds": round(float(downloaded["seconds"]), 1)})
    if failed is not None:
        payload.update({"failed": int(failed["count"]), "reason": failed["reason"]})
    return MARKER + " " + json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def stop_lines(kind: str, course: str, section, missing: list, reason: str) -> list:
    """
    What a build that STOPS prints (keptDownloads.stop): the first line, which
    the apps lift into the sentence a teacher reads (app-rules.json ->
    failureExplanations), then one line per item and page, at most
    `listedAtMost`, then "and N more". `missing` is [{"item", "page"}] in the
    order the pages were read; `reason` is offline or damaged.
    """
    stop = rules("stop")
    said = rules("kinds", kind)
    distinct = []
    for item in missing:
        if item["item"] not in distinct:
            distinct.append(item["item"])
    first = _filled(stop["first"][reason], {
        "course": course, "section": section, "what": what(kind, len(distinct)), "source": said["source"]})
    lines = ["❌ " + first]
    most = int(stop["listedAtMost"])
    for item in missing[:most]:
        lines.append("   " + _filled(stop["item"], {"item": item["item"], "page": item["page"]}))
    if len(missing) > most:
        lines.append("   " + _filled(stop["andMore"], {"count": len(missing) - most}))
    return lines


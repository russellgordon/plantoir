#!/usr/bin/env python3
"""
GeoGebra sketches from a page's own ```geogebra fences (#578).

A teacher writes, on a page:

    ```geogebra
    file: Slope Angle Conjecture.ggb
    alt: Three right triangles that share one marked angle.
    ```

or GeoGebra commands, one per line, as in GeoGebra's Input Bar. Students get
a sketch they can drag, opened with a tap and served by the class site itself.
This module is the build's half: it finds those fences on the pages students
can see, reads each one's settings and commands (contracts/shared-rules.json
-> geogebraFences.settings), finds the sketch's file (geogebraFences.files),
reads its size and thumbnail, and hands the site's transformer
(support/quartz/plugins/transformers/plantoirGeoGebra.ts) a manifest in
`quartz/plantoir-geogebra/`. The site's loader
(support/quartz/components/scripts/geogebra.inline.ts) loads the engine
only when a student taps.

**Python prepares and Quartz places**, as figures.py does and for the same
reasons: a sketch that cannot be shown must reach the teacher as a folder
problem (siteHealth -> geogebraSketchesNotReady), a preview build never
returns, and this file runs on Windows too.

**Each .ggb is published ONCE** (plan review finding 4): Quartz already
publishes every file under content/ that is not a page, so the manifest
records where the file is in content/ and the transformer makes its address
with Quartz's own slugifyFilePath - the function Quartz's Assets emitter
uses. Nothing is copied. Only the thumbnails are written, to
`quartz/static/geogebra-sketches/`.

What a site carries is decided here as well (the #454 gate): `counts` says
how many pages students can see have a sketch that can be shown, and
page_features.GATED_ASSETS["geogebra"] puts the engine (static/geogebra,
27 MB) into the site only then.

A sketch named by `material_id:` (a geogebra.org sketch, #578 stage 4) is
FETCHED ONCE and kept (ruling Q2): its .ggb is copied from geogebra.org the
first time a build meets the fence and saved beside the course's built sites,
in `.geogebra-cache/`, under the FENCE's key (figureRules.keyOf). A build
whose fence has a saved copy asks geogebra.org nothing at all; changing the
fence (`version: 2`) is how a teacher gets a changed sketch fetched again.
`--full-rebuild` keeps the saved copies; a copy unused for 90 days goes
(figures.PRUNE_DAYS). geogebraFences.cache and .fetch.

Every rule a case can pin is in contracts/shared-rules.json ->
geogebraFences, and scripts/test_geogebra.py runs them. The reasons are in
documentation/05-build-pipeline.md -> "GeoGebra sketches: what the build does".
"""

import hashlib
import io
import json
import os
import re
import shutil
import struct
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

import contracts
import figures
import markdown_code
import page_features
import site_health
import toolchain_paths

LANGUAGE = "geogebra"
# The engine's folder under VENDOR_DIR and under the site's quartz/static
# (page_features.GATED_ASSETS, stage 1).
ENGINE = "geogebra"
WORKSPACE = "plantoir-geogebra"
THUMBNAILS = "geogebra-sketches"
DEFAULT_APP = "classic"
# A sketch made from commands alone has no size of its own.
COMMANDS_SIZE = (800, 500)
# geogebra.xml is read, never unpacked, and never past this many bytes.
LARGEST_XML_BYTES = 20 * 1024 * 1024
LARGEST_THUMBNAIL_BYTES = 4 * 1024 * 1024


CACHE_FOLDER = ".geogebra-cache"


def rules(*keys):
    return contracts.section("shared-rules", "geogebraFences", *keys)


def words() -> dict:
    return rules("words")


# ---- Reading a fence -----------------------------------------------------------

_SETTING = re.compile(r"^([a-z_0-9]+)[ \t]*:[ \t]*(.*?)[ \t]*$")
# A command that reads like a setting: a word, then a colon. GeoGebra's own
# `a: x + y = 3` matches too, which is why only a KNOWN key is noted.
_LOOKS_LIKE_SETTING = re.compile(r"^([A-Za-z_]+)[ \t]*:")
_NUMBER = re.compile(r"^([0-9]{1,5})(?:[ \t]*px)?$")
_TRUE = {"true", "yes", "on"}
_FALSE = {"false", "no", "off"}


def _unquoted(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def _setting_of(line: str):
    """(key, value) when the line is `key: value`, else None. Not yet known."""
    match = _SETTING.match(figures.js_trim(line))
    if match is None:
        return None
    return match.group(1), match.group(2)


def read_fence(body: str) -> dict:
    """
    One fence's settings and commands (geogebraFences.settings): answers
    {"settings": {...}, "commands": [{"line", "text"}], "problems": [...],
    "notes": [...], "lines": {setting: its line}}, each problem and note
    {"reason", "blockLine", and "name" / "value" where they apply}. `blockLine` is the line within the fence,
    from 1; None when the problem is the fence as a whole.
    """
    known = set(rules("settings", "known"))
    lines = body.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    settings = {}
    problems = []
    notes = []
    commands = []
    given_at = {}

    def take(key, raw, line_number):
        value = _unquoted(raw)
        if key == "file":
            text = value.strip()
            if text.startswith("[[") and text.endswith("]]"):
                text = text[2:-2].split("|", 1)[0].strip()
            value = text
        elif key in rules("settings", "numbers"):
            match = _NUMBER.match(value.strip())
            if match is None or int(match.group(1)) <= 0:
                problems.append({"reason": "numberExpected", "blockLine": line_number,
                                 "name": key, "value": value})
                return
            value = int(match.group(1))
        elif key in rules("settings", "switches"):
            lowered = value.strip().lower()
            if lowered in _TRUE:
                value = True
            elif lowered in _FALSE:
                value = False
            else:
                problems.append({"reason": "trueOrFalseExpected", "blockLine": line_number,
                                 "name": key, "value": value})
                return
        elif key == "app":
            lowered = value.strip().lower()
            if lowered not in rules("settings", "apps"):
                problems.append({"reason": "appNotKnown", "blockLine": line_number, "value": value})
                return
            value = lowered
        settings[key] = value
        given_at[key] = line_number

    index = 0
    # Blank lines before the settings.
    while index < len(lines) and not figures.js_trim(lines[index]):
        index += 1
    if index < len(lines) and figures.js_trim(lines[index]) == "---":
        # A block that opens with ---, read to the next ---. Never closed,
        # it would swallow every command as a setting left out: said.
        opened_at = index + 1
        closed = False
        for later in range(index + 1, len(lines)):
            if figures.js_trim(lines[later]) == "---":
                closed = True
                break
        if not closed:
            return {"settings": {}, "commands": [], "notes": [], "lines": {},
                    "problems": [{"reason": "settingsNotClosed", "blockLine": opened_at}]}
        index += 1
        while index < len(lines) and figures.js_trim(lines[index]) != "---":
            line = lines[index]
            if figures.js_trim(line):
                found = _setting_of(line)
                if found is not None and found[0] in known:
                    take(found[0], found[1], index + 1)
                else:
                    name = found[0] if found is not None else figures.js_trim(line)
                    notes.append({"reason": "unknownSetting", "blockLine": index + 1, "name": name})
            index += 1
        index += 1
    else:
        while index < len(lines):
            line = lines[index]
            if not figures.js_trim(line):
                index += 1
                continue
            found = _setting_of(line)
            if found is None or found[0] not in known:
                break
            take(found[0], found[1], index + 1)
            index += 1
        if index < len(lines) and figures.js_trim(lines[index]) == "---":
            index += 1
    while index < len(lines):
        text = figures.js_trim(lines[index])
        if text and not text.startswith("//"):
            commands.append({"line": index + 1, "text": text})
            # A setting written among the commands (in capitals, or after a
            # line that started the commands) is run as a command, which
            # GeoGebra refuses: said at build time, where the teacher reads.
            looks = _LOOKS_LIKE_SETTING.match(text)
            if looks is not None and looks.group(1).lower() in known:
                notes.append({"reason": "settingAmongCommands", "blockLine": index + 1,
                              "name": looks.group(1)})
        index += 1

    if settings.get("file") == "":
        problems.append({"reason": "fileHasNoName", "blockLine": given_at["file"]})
    elif "file" in settings and "material_id" in settings:
        problems.append({"reason": "fileAndMaterialBoth",
                         "blockLine": max(given_at["file"], given_at["material_id"])})
    elif "file" not in settings and "material_id" not in settings and not commands:
        problems.append({"reason": "nothingToShow", "blockLine": None})
    return {"settings": settings, "commands": commands, "problems": problems, "notes": notes,
            "lines": given_at}


_MATERIAL_PATHS = (
    re.compile(r"^/(?:m|classic|graphing|geometry|3d|calculator)/([A-Za-z0-9]{4,16})(?:[/?#].*)?$"),
    re.compile(r"^/material/(?:show|iframe)/id/([A-Za-z0-9]{4,16})(?:[/?#].*)?$"),
)
_MATERIAL_ID = re.compile(r"^[A-Za-z0-9]{4,16}$")


def material_id_of(value: str):
    """The geogebra.org sketch id `material_id:` names, or None (geogebraFences.materialIds)."""
    text = figures.js_trim(str(value or ""))
    if _MATERIAL_ID.match(text):
        return text
    address = re.sub(r"^https?://", "", text)
    host, slash, path = address.partition("/")
    if host.lower() not in ("geogebra.org", "www.geogebra.org") or not slash:
        return None
    for pattern in _MATERIAL_PATHS:
        match = pattern.match("/" + path)
        if match:
            return match.group(1)
    return None


def sketches_on_page(text: str) -> list:
    """
    The geogebra fences on one page, in order: [{"block" (from 1), "line"
    (the opening fence's line), "body", "key"}] (geogebraFences.fences).
    """
    found = []
    for block in markdown_code.fenced_blocks(text):
        if block["lang"] != LANGUAGE or block["nested"]:
            continue
        found.append({
            "block": len(found) + 1,
            "line": block["line"],
            "body": block["body"],
            "key": figures.key_of(block["body"]),
        })
    return found


# ---- The sketch's file -----------------------------------------------------------

def _same_name(one: str, other: str) -> bool:
    return (unicodedata.normalize("NFC", one).casefold()
            == unicodedata.normalize("NFC", other).casefold())


def _entry_in(folder: Path, name: str):
    """The folder's own spelling of `name` by its LISTING, exact first
    (page_features._find_in_media's rule), or None."""
    try:
        entries = sorted(entry.name for entry in folder.iterdir())
    except OSError:
        return None
    for entry in entries:
        if unicodedata.normalize("NFC", entry) == unicodedata.normalize("NFC", name):
            return entry
    for entry in entries:
        if _same_name(entry, name):
            return entry
    return None


def _walk(root: Path, start: Path, parts: list):
    """The file `parts` names from `start`, spelt as the folders spell it,
    as a path relative to `root`; None when it is not there or leaves `root`."""
    current = start
    for part in parts:
        if part in ("", "."):
            continue
        if part == "..":
            if current == root:
                return None
            current = current.parent
            continue
        entry = _entry_in(current, part)
        if entry is None:
            return None
        current = current / entry
    if not current.is_file():
        return None
    try:
        return current.relative_to(root).as_posix()
    except ValueError:
        return None


def find_file(value: str, page_path: str, content_root) -> str | None:
    """
    Where `file:` leads, as a path in the site's content with forward
    slashes, or None (geogebraFences.files): beside the page, then from the
    top of the course folder, then by its file name alone in Media.
    """
    root = Path(content_root)
    text = value.replace("\\", "/").strip()
    if not text or text.startswith("/"):
        return None
    parts = text.split("/")
    page_folder = PurePosixPath(page_path).parent
    beside = root.joinpath(*[part for part in page_folder.parts if part not in ("", ".")])
    found = _walk(root, beside, parts)
    if found is None:
        found = _walk(root, root, parts)
    if found is None:
        media = _entry_in(root, "Media")
        if media is not None and parts[-1] not in ("", ".", ".."):
            found = _walk(root, root / media, [parts[-1]])
    if found is not None and not is_published(found):
        # Quartz leaves it out of the site, so a sketch made from it could
        # never open: not found, said once (stage 2 review item 6).
        return None
    return found


def is_published(content_path: str) -> bool:
    """Whether Quartz publishes the file at `content_path` (geogebraFences.
    files.notPublished): not under a folder its ignorePatterns name, and no
    part of the path starting with a dot (its file walk skips those)."""
    parts = PurePosixPath(content_path).parts
    if parts and parts[0] in rules("files", "notPublished", "folders"):
        return False
    for part in parts:
        if part.startswith("."):
            return False
    return True


def _sketch_size(xml: bytes):
    """The sketch's own width and height: the first <euclidianView>'s
    <size>, as GeoGebra writes it. None when there is none."""
    text = xml.decode("utf-8", errors="replace")
    view = text.find("<euclidianView")
    if view < 0:
        return None
    match = re.search(r'<size\s+width="([0-9]+)"\s+height="([0-9]+)"', text[view:view + 4000])
    if match is None:
        return None
    width, height = int(match.group(1)), int(match.group(2))
    if width <= 0 or height <= 0:
        return None
    return width, height


def _sketch_app(xml: bytes):
    match = re.search(rb'<geogebra[^>]*\bapp="([a-z0-9]+)"', xml[:2000])
    if match is None:
        return None
    app = match.group(1).decode("ascii")
    return app if app in rules("settings", "apps") else None


def _png_size(data: bytes):
    if len(data) >= 24 and data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
        width, height = struct.unpack(">II", data[16:24])
        return width, height
    return None


def read_sketch(path: Path, largest_bytes: int) -> dict:
    """
    What a .ggb holds that the site needs: {"ok": True, "bytes", "size"
    (w, h) or None, "app" or None, "thumbnail" (bytes) or None}, or {"ok":
    False, "reason", "megabytes"}. Read, never unpacked.
    """
    try:
        size = path.stat().st_size
    except OSError:
        return {"ok": False, "reason": "fileNotFound"}
    return _read_zip(path, size, largest_bytes)


def read_sketch_data(data: bytes, largest_bytes: int) -> dict:
    """read_sketch for a sketch held in memory (one copied from geogebra.org)."""
    return _read_zip(io.BytesIO(data), len(data), largest_bytes)


def _read_zip(source, size: int, largest_bytes: int) -> dict:
    if size > largest_bytes:
        return {"ok": False, "reason": "fileTooLarge", "megabytes": _megabytes(size)}
    try:
        with zipfile.ZipFile(source) as sketch:
            info = None
            for member in sketch.infolist():
                if member.filename == "geogebra.xml":
                    info = member
                    break
            if info is None or info.file_size > LARGEST_XML_BYTES:
                return {"ok": False, "reason": "notAGeoGebraFile"}
            xml = sketch.read(info)
            thumbnail = None
            for member in sketch.infolist():
                if member.filename == "geogebra_thumbnail.png" and member.file_size <= LARGEST_THUMBNAIL_BYTES:
                    data = sketch.read(member)
                    if _png_size(data) is not None:
                        thumbnail = data
                    break
    except (OSError, zipfile.BadZipFile, ValueError, RuntimeError, NotImplementedError):
        return {"ok": False, "reason": "notAGeoGebraFile"}
    if b"<geogebra" not in xml[:4000]:
        return {"ok": False, "reason": "notAGeoGebraFile"}
    return {"ok": True, "bytes": size, "size": _sketch_size(xml), "app": _sketch_app(xml),
            "thumbnail": thumbnail}


def _megabytes(count: int) -> str:
    value = round(count / 1_000_000, 1)
    return str(int(value)) if value == int(value) else str(value)


# ---- A sketch from geogebra.org, fetched once (stage 4) ----------------------------

class _SameHostsOnly(urllib.request.HTTPRedirectHandler):
    """Follows a redirect only to another of geogebra.org's own hosts
    (geogebraFences.fetch.hosts), over an allowed scheme."""

    def __init__(self, hosts, schemes):
        super().__init__()
        self.hosts = hosts
        self.schemes = schemes

    def redirect_request(self, request, fp, code, message, headers, new_url):
        address = urllib.parse.urlsplit(new_url)
        if address.scheme not in self.schemes or (address.hostname or "").lower() not in self.hosts:
            raise urllib.error.URLError(f"a redirect left geogebra.org: {address.hostname}")
        return super().redirect_request(request, fp, code, message, headers, new_url)


class MaterialFetcher:
    """
    Copies a geogebra.org sketch (geogebraFences.fetch): GeoGebra's public
    materials API for the sketch's author and its ONE applet's .ggb, then
    the .ggb. Answers {"ok": True, "ggb": bytes, "title", "author"} or
    {"ok": False, "reason"} - materialNotFound for an answer that says there
    is no such sketch anyone can open, materialHasNoSketch /
    materialHasSeveralSketches for what the sketch holds, and
    materialCouldNotBeFetched for everything else (no network, a timeout, a
    server error, a redirect elsewhere, a file too large).

    The api, hosts and schemes are the contract's; a test passes its own
    local server's (never the real API in a test).
    """

    def __init__(self, api=None, hosts=None, schemes=None, timeout=None, largest_bytes=None):
        fetch = rules("fetch")
        self.api = api or fetch["api"]
        self.hosts = tuple(host.lower() for host in (hosts or fetch["hosts"]))
        self.schemes = tuple(schemes or ("https",))
        self.timeout = timeout or fetch["requestSeconds"]
        self.largest = largest_bytes or int(rules("files", "largestFileMegabytes")) * 1024 * 1024
        self.requests = 0
        self.opener = urllib.request.build_opener(_SameHostsOnly(self.hosts, self.schemes))

    def _allowed(self, url: str) -> bool:
        address = urllib.parse.urlsplit(url)
        return address.scheme in self.schemes and (address.hostname or "").lower() in self.hosts

    def _get(self, url: str) -> bytes:
        if not self._allowed(url):
            raise urllib.error.URLError(f"not one of geogebra.org's hosts: {url}")
        self.requests += 1
        request = urllib.request.Request(url, headers={"User-Agent": "Plantoir", "Accept": "*/*"})
        with self.opener.open(request, timeout=self.timeout) as answer:
            data = answer.read(self.largest + 1)
        if len(data) > self.largest:
            raise urllib.error.URLError("larger than a sketch can be")
        return data

    def material(self, material_id: str) -> dict:
        try:
            described = json.loads(self._get(self.api.replace("{id}", urllib.parse.quote(material_id))))
        except urllib.error.HTTPError as error:
            error.close()
            if error.code in (403, 404, 410):
                return {"ok": False, "reason": "materialNotFound"}
            return {"ok": False, "reason": "materialCouldNotBeFetched"}
        except (OSError, ValueError, urllib.error.URLError):
            return {"ok": False, "reason": "materialCouldNotBeFetched"}
        if not isinstance(described, dict) or described.get("deleted") is True:
            return {"ok": False, "reason": "materialNotFound"}
        applets = []
        for element in described.get("elements") or []:
            if isinstance(element, dict) and element.get("type") == "G":
                applets.append(element)
        if not applets:
            return {"ok": False, "reason": "materialHasNoSketch"}
        if len(applets) > 1:
            return {"ok": False, "reason": "materialHasSeveralSketches"}
        url = str(applets[0].get("url") or "")
        if not url:
            return {"ok": False, "reason": "materialHasNoSketch"}
        try:
            data = self._get(url)
        except urllib.error.HTTPError as error:
            error.close()
            if error.code in (403, 404, 410):
                return {"ok": False, "reason": "materialNotFound"}
            return {"ok": False, "reason": "materialCouldNotBeFetched"}
        except (OSError, urllib.error.URLError):
            return {"ok": False, "reason": "materialCouldNotBeFetched"}
        creator = described.get("creator") if isinstance(described.get("creator"), dict) else {}
        # The name the attribution gives (CC BY-NC-SA asks for one): the
        # author's display name, else their user name, else the sketch's
        # own address, so the card never says "by " and nothing.
        author = str(creator.get("displayname") or creator.get("username") or "").strip() \
            or f"geogebra.org/m/{material_id}"
        return {"ok": True, "ggb": data, "title": str(described.get("title") or ""), "author": author}


class SavedCopies:
    """
    `<course's builds folder>/.geogebra-cache/<the fence's key>.{ggb,json}`
    (geogebraFences.cache). Shared by the course's sections, so each file is
    written to a temporary name first and moved into place, the .ggb before
    the .json - an entry is whole only once its .json is there. Every build
    that uses an entry touches it; an entry unused for PRUNE_DAYS goes.
    Outside the teacher's folder: the builds folder is the app's.
    """

    def __init__(self, root):
        self.root = Path(root) if root is not None else None

    def _paths(self, key: str):
        return self.root / f"{key}.ggb", self.root / f"{key}.json"

    def get(self, key: str):
        if self.root is None:
            return None
        sketch, about = self._paths(key)
        try:
            described = json.loads(about.read_text(encoding="utf-8"))
            data = sketch.read_bytes()
        except (OSError, ValueError):
            return None
        for path in (sketch, about):
            try:
                os.utime(path, None)
            except OSError:
                pass
        described["ggb"] = data
        return described

    def put(self, key: str, material: dict) -> None:
        if self.root is None:
            return
        sketch, about = self._paths(key)
        described = {"id": material["id"], "title": material.get("title") or "",
                     "author": material.get("author") or ""}
        stamp = f".{os.getpid()}.{threading.get_ident()}.tmp"
        try:
            self.root.mkdir(parents=True, exist_ok=True)
            for path, data in ((sketch, material["ggb"]),
                               (about, json.dumps(described, ensure_ascii=False).encode("utf-8"))):
                temporary = path.with_name(path.name + stamp)
                temporary.write_bytes(data)
                os.replace(temporary, path)
        except OSError:
            # Not kept, and nothing lost: the next build asks again.
            for path in (sketch, about):
                try:
                    path.with_name(path.name + stamp).unlink()
                except OSError:
                    pass

    def prune(self, now=None) -> None:
        """Every entry unused for figures.PRUNE_DAYS, and any temporary file
        a stopped build left behind as old."""
        if self.root is None:
            return
        now = time.time() if now is None else now
        try:
            entries = list(self.root.iterdir())
        except OSError:
            return
        for entry in entries:
            try:
                if now - entry.stat().st_mtime > figures.PRUNE_DAYS * 86400:
                    entry.unlink()
            except OSError:
                pass


# ---- Which pages count -----------------------------------------------------------

def pages_students_see(content_root, is_hidden, place_of, source_of, skip=None) -> list:
    """
    The pages students can see that could hold a sketch. TWO scans, one per
    fence character, merged by path (geogebraFences.fences: `must_contain`
    is a plain substring test, so one scan misses every ~~~geogebra fence -
    plan review finding 9).
    """
    merged = {}
    for opener in ("```" + LANGUAGE, "~~~" + LANGUAGE):
        for page in figures.pages_students_see(content_root, is_hidden, place_of, source_of,
                                               skip=skip, must_contain=opener):
            merged.setdefault(page["path"], page)
    return [merged[path] for path in sorted(merged)]


# ---- The words ---------------------------------------------------------------------

def reason_sentence(problem: dict, said: dict) -> str:
    reasons = said["reasons"]
    text = reasons.get(problem.get("reason") or "") or reasons["nothingToShow"]
    return site_health.filled(text, {
        "file": problem.get("file") or "",
        "name": problem.get("name") or "",
        "value": problem.get("value") or "",
        "id": problem.get("id") or "",
        "megabytes": problem.get("megabytes") or "",
        "limit": rules("files", "largestFileMegabytes"),
    })


def error_line(problem: dict, said: dict, kind="error") -> str:
    """`plantoir: error: Unit 3/Slopes.md: geogebra block 1, line 22: ...`."""
    where = f"{problem['page']}.md: geogebra block {problem['block']}"
    if problem.get("line") is not None:
        where += f", line {problem['line']}"
    return f"plantoir: {kind}: {where}: {reason_sentence(problem, said)}"


def health_finding_facts(outcome: dict) -> list:
    """The `geogebra_problems` fact for site_health: one entry per sketch."""
    return list(outcome.get("problems") or [])


# ---- The whole pass ---------------------------------------------------------------

def _file_line_of(sketch: dict, source_sketches: list):
    """The opening fence's line in the TEACHER's page (figures._file_line_of's rule)."""
    for candidate in source_sketches:
        if candidate["key"] == sketch["key"] and candidate["block"] == sketch["block"]:
            return candidate["line"]
    for candidate in source_sketches:
        if candidate["key"] == sketch["key"]:
            return candidate["line"]
    return None


def _located(sketch: dict, problem: dict) -> dict:
    """A problem with its page, sketch and line in the teacher's file: the
    setting's own line when there is one, the opening fence's otherwise."""
    line = None
    if sketch.get("fileLine") is not None:
        line = sketch["fileLine"]
        if problem.get("blockLine") is not None:
            line += problem["blockLine"]
    located = {"page": sketch["place"], "block": sketch["block"], "line": line,
               "blockLine": problem.get("blockLine"), "reason": problem.get("reason")}
    for name in ("file", "name", "value", "id", "megabytes"):
        if problem.get(name) is not None:
            located[name] = problem[name]
    return located


def _write_if_changed(path: Path, data: bytes) -> None:
    if path.is_file():
        try:
            if path.read_bytes() == data:
                return
        except OSError:
            pass
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def _write_site_files(output_dir, manifest, thumbnails: dict) -> None:
    """quartz/plantoir-geogebra/manifest.json and quartz/static/
    geogebra-sketches/<name>.png - or neither, when nothing can be shown,
    so the transformer leaves every page exactly as it was."""
    workspace = Path(output_dir) / "quartz" / WORKSPACE
    pictures = Path(output_dir) / "quartz" / "static" / THUMBNAILS
    if manifest is None:
        for folder in (workspace, pictures):
            if folder.exists():
                shutil.rmtree(folder, ignore_errors=True)
        return
    _write_if_changed(workspace / "manifest.json",
                      (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=1) + "\n").encode("utf-8"))
    for existing in list(workspace.iterdir()):
        if existing.name != "manifest.json":
            try:
                existing.unlink()
            except OSError:
                pass
    if not thumbnails:
        if pictures.exists():
            shutil.rmtree(pictures, ignore_errors=True)
        return
    for name, data in thumbnails.items():
        _write_if_changed(pictures / name, data)
    for existing in list(pictures.iterdir()):
        if existing.name not in thumbnails:
            try:
                existing.unlink()
            except OSError:
                pass


def page_key(content_path: str) -> str:
    """A page's name in the manifest: its path in the site's content, in
    NFC - what the transformer reads as file.data.relativePath, normalised
    the same way (geogebraFences.manifest)."""
    return unicodedata.normalize("NFC", content_path)


def engine_present(vendor_dir=None) -> bool:
    vendor = Path(vendor_dir) if vendor_dir is not None else toolchain_paths.VENDOR_DIR
    return (vendor / ENGINE / "deployggb.js").is_file()


def prepare(pages: list, output_dir, content_root, vendor_dir=None, printer=print,
            cache_root=None, fetcher=None, full_rebuild=False) -> dict:
    """
    Every geogebra fence on the pages students can see, read, its file
    found (or its geogebra.org sketch fetched once and kept) and checked,
    and handed to the site.

    `pages` is figures.pages_students_see's shape ({"place", "text",
    "source", "path"}) - ONLY pages students can see. `cache_root` is the
    course's `.geogebra-cache` beside its built sites; `fetcher` a
    MaterialFetcher (the contract's API by default). `full_rebuild` is
    taken and deliberately NOT used: a full rebuild keeps the saved copies
    (geogebraFences.cache - one way to fetch again, the fence, and a full
    rebuild while geogebra.org is down must not turn a working sketch into
    a folder problem). Answers {"counts": {"geogebra": pages with a sketch
    that can be shown}, "problems": [...], "notes": [...], "sketches": n,
    "shown": n, "fetched": sketches copied from geogebra.org now,
    "fromBefore": sketches from geogebra.org kept from an earlier build}.
    """
    said = words()
    largest = int(rules("files", "largestFileMegabytes")) * 1024 * 1024
    first_load = int(rules("engine", "firstLoadBytes", "gzipped"))
    engine_ready = engine_present(vendor_dir)
    outcome = {"counts": {ENGINE: 0}, "problems": [], "notes": [], "sketches": 0, "shown": 0,
               "fetched": 0, "fromBefore": 0}
    entries = {}
    thumbnails = {}
    pages_shown = set()
    sketch_reads = {}
    store = SavedCopies(cache_root)
    store.prune()
    materials = {"store": store, "fetcher": fetcher, "answers": {}, "outcome": outcome}

    for page in pages:
        sketches = sketches_on_page(page["text"])
        if not sketches:
            continue
        source_sketches = sketches_on_page(page["source"]) if page.get("source") else []
        for sketch in sketches:
            outcome["sketches"] += 1
            sketch["place"] = page["place"]
            sketch["fileLine"] = _file_line_of(sketch, source_sketches)
            read = read_fence(sketch["body"])
            for note in read["notes"]:
                outcome["notes"].append(_located(sketch, note))
            settings = read["settings"]
            problem = read["problems"][0] if read["problems"] else None
            entry = None
            if problem is None and "material_id" in settings:
                material = material_id_of(settings["material_id"])
                if material is None:
                    problem = {"reason": "materialNotUnderstood", "value": settings["material_id"],
                               "blockLine": read["lines"].get("material_id")}
                else:
                    settings["material_id"] = material
            if problem is None and not engine_ready:
                problem = {"reason": "engineMissing", "blockLine": None}
            if problem is None:
                entry, problem = _entry_for(sketch, page, settings, read["commands"], read["lines"], content_root,
                                            largest, first_load, said, thumbnails, sketch_reads, materials)
            if problem is not None:
                outcome["problems"].append(_located(sketch, problem))
                continue
            if "alt" not in settings:
                outcome["notes"].append(_located(sketch, {"reason": "missingAlt", "blockLine": None}))
            # By page AND fence (stage 2 review item 1): the same fence on
            # two pages can name two different files beside them.
            entries.setdefault(page_key(page["path"]), {})[sketch["key"]] = entry
            pages_shown.add(page["path"])
            outcome["shown"] += 1

    manifest = None
    if entries:
        manifest = {"version": 2, "words": said["site"], "attribution": rules("attribution"),
                    "endOfLine": rules("commands", "endOfLine"), "pages": entries}
    _write_site_files(output_dir, manifest, thumbnails)
    outcome["counts"][ENGINE] = len(pages_shown)
    if outcome["sketches"]:
        printer(f"📐 {outcome['shown']} of {outcome['sketches']} GeoGebra sketch"
                f"{'es' if outcome['sketches'] != 1 else ''} ready to open on the site.")
    if outcome["fetched"] or outcome["fromBefore"] or materials["answers"]:
        printer(f"📐 Sketches from geogebra.org: {outcome['fetched']} copied now, "
                f"{outcome['fromBefore']} kept from before.")
    for note in outcome["notes"]:
        printer(error_line(note, said, kind="note"))
    for problem in outcome["problems"]:
        printer(error_line(problem, said))
    return outcome


def _material(key: str, material_id: str, materials: dict) -> dict:
    """
    The fence's geogebra.org sketch: its saved copy when there is one - and
    then NOTHING is asked of geogebra.org - or copied now and saved under
    the fence's key (geogebraFences.cache). One fence met on several pages
    is fetched once.
    """
    answers = materials["answers"]
    if key in answers:
        return answers[key]
    saved = materials["store"].get(key)
    if saved is not None and saved.get("id") == material_id:
        saved["ok"] = True
        materials["outcome"]["fromBefore"] += 1
        answers[key] = saved
        return saved
    if materials["fetcher"] is None:
        materials["fetcher"] = MaterialFetcher()
    answer = materials["fetcher"].material(material_id)
    answer["id"] = material_id
    if answer["ok"]:
        materials["outcome"]["fetched"] += 1
        answer["fresh"] = True
    answers[key] = answer
    return answer


def _entry_for(sketch, page, settings, commands, lines, content_root, largest, first_load, said,
               thumbnails, sketch_reads, materials):
    """The manifest entry for one sketch, or (None, the problem)."""
    app = settings.get("app")
    width = height = None
    source = None
    thumbnail = None
    sketch_bytes = 0
    attribution = {"kind": "file"}
    read = None
    if "material_id" in settings:
        material_id = settings["material_id"]
        answer = _material(sketch["key"], material_id, materials)
        if not answer["ok"]:
            return None, {"reason": answer["reason"], "id": material_id, "blockLine": lines.get("material_id")}
        # Checked as a teacher's file is, BEFORE it is kept: what is not a
        # GeoGebra file is never saved, so the next build asks again.
        name = f"{sketch['key'][:16]}.ggb"
        if name not in sketch_reads:
            sketch_reads[name] = read_sketch_data(answer["ggb"], largest)
        read = sketch_reads[name]
        if not read["ok"]:
            return None, {"reason": "materialHasNoSketch", "id": material_id,
                          "blockLine": lines.get("material_id")}
        if answer.pop("fresh", False):
            materials["store"].put(sketch["key"], answer)
        # The site's copy, in static/, named by the fence's key: a sketch
        # from geogebra.org has no file in content/ for Quartz to publish.
        thumbnails[name] = answer["ggb"]
        source = {"kind": "material", "storePath": f"static/{THUMBNAILS}/{name}"}
        attribution = {"kind": "material", "author": answer.get("author") or "", "id": material_id,
                       "title": answer.get("title") or ""}
    elif "file" in settings:
        found = find_file(settings["file"], page["path"], content_root)
        if found is None:
            return None, {"reason": "fileNotFound", "file": settings["file"], "blockLine": lines.get("file")}
        if found not in sketch_reads:
            sketch_reads[found] = read_sketch(Path(content_root) / found, largest)
        read = sketch_reads[found]
        if not read["ok"]:
            problem = {"reason": read["reason"], "file": settings["file"], "blockLine": lines.get("file")}
            if read.get("megabytes"):
                problem["megabytes"] = read["megabytes"]
            return None, problem
        source = {"kind": "file", "contentPath": found}
    if read is not None:
        sketch_bytes = read["bytes"]
        if read["size"] is not None:
            width, height = read["size"]
        app = app or read["app"]
        if read["thumbnail"] is not None:
            # Named by the picture's own bytes, so one sketch named by
            # several fences is one picture on the site.
            picture = f"{hashlib.sha256(read['thumbnail']).hexdigest()[:16]}.png"
            thumbnails[picture] = read["thumbnail"]
            picture_width, picture_height = _png_size(read["thumbnail"])
            thumbnail = {"name": picture, "width": picture_width, "height": picture_height}
    if width is None or height is None:
        width, height = COMMANDS_SIZE
    width = settings.get("width", width)
    height = settings.get("height", height)
    size = site_health.filled(said["site"]["sketchSize"],
                              {"megabytes": _megabytes(sketch_bytes + first_load)})
    entry = {
        "ok": True,
        "app": app or DEFAULT_APP,
        "width": width,
        "height": height,
        "alt": settings.get("alt") or said["site"]["untitledSketch"],
        "caption": settings.get("caption"),
        "commands": commands,
        "toolbar": bool(settings.get("toolbar", False)),
        "algebra": bool(settings.get("algebra", False)),
        "source": source,
        "thumbnail": thumbnail,
        "attribution": attribution,
        "size": size,
    }
    return entry, None

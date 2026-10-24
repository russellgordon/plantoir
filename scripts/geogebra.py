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

A sketch named by `material_id:` (a geogebra.org sketch) is read here but
not yet fetched: that is #578 stage 4, and until it lands such a sketch is
reported as materialCouldNotBeFetched and stays a code block.

Every rule a case can pin is in contracts/shared-rules.json ->
geogebraFences, and scripts/test_geogebra.py runs them. The reasons are in
documentation/05-build-pipeline.md -> "GeoGebra sketches: what the build does".
"""

import json
import re
import shutil
import struct
import unicodedata
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


def rules(*keys):
    return contracts.section("shared-rules", "geogebraFences", *keys)


def words() -> dict:
    return rules("words")


# ---- Reading a fence -----------------------------------------------------------

_SETTING = re.compile(r"^([a-z_0-9]+)[ \t]*:[ \t]*(.*?)[ \t]*$")
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
        # A block that opens with ---, read to the next ---.
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
        index += 1

    if "file" in settings and "material_id" in settings:
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
    return found


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
    if size > largest_bytes:
        return {"ok": False, "reason": "fileTooLarge", "megabytes": _megabytes(size)}
    try:
        with zipfile.ZipFile(path) as sketch:
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


def engine_present(vendor_dir=None) -> bool:
    vendor = Path(vendor_dir) if vendor_dir is not None else toolchain_paths.VENDOR_DIR
    return (vendor / ENGINE / "deployggb.js").is_file()


def prepare(pages: list, output_dir, content_root, vendor_dir=None, printer=print) -> dict:
    """
    Every geogebra fence on the pages students can see, read, its file
    found and checked, and handed to the site.

    `pages` is figures.pages_students_see's shape ({"place", "text",
    "source", "path"}) - ONLY pages students can see. Answers {"counts":
    {"geogebra": pages with a sketch that can be shown}, "problems": [...],
    "notes": [...], "sketches": n, "shown": n}.
    """
    said = words()
    largest = int(rules("files", "largestFileMegabytes")) * 1024 * 1024
    first_load = int(rules("engine", "firstLoadBytes", "gzipped"))
    engine_ready = engine_present(vendor_dir)
    outcome = {"counts": {ENGINE: 0}, "problems": [], "notes": [], "sketches": 0, "shown": 0}
    entries = {}
    thumbnails = {}
    pages_shown = set()
    sketch_reads = {}

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
                    # Fetched and kept from #578 stage 4.
                    problem = {"reason": "materialCouldNotBeFetched", "id": material,
                               "blockLine": read["lines"].get("material_id")}
            if problem is None and not engine_ready:
                problem = {"reason": "engineMissing", "blockLine": None}
            if problem is None:
                entry, problem = _entry_for(sketch, page, settings, read["commands"], read["lines"], content_root,
                                            largest, first_load, said, thumbnails, sketch_reads)
            if problem is not None:
                outcome["problems"].append(_located(sketch, problem))
                continue
            if "alt" not in settings:
                outcome["notes"].append(_located(sketch, {"reason": "missingAlt", "blockLine": None}))
            entries[sketch["key"]] = entry
            pages_shown.add(page["path"])
            outcome["shown"] += 1

    manifest = None
    if entries:
        manifest = {"version": 1, "words": said["site"], "attribution": rules("attribution"),
                    "sketches": entries}
    _write_site_files(output_dir, manifest, thumbnails)
    outcome["counts"][ENGINE] = len(pages_shown)
    if outcome["sketches"]:
        printer(f"📐 {outcome['shown']} of {outcome['sketches']} GeoGebra sketch"
                f"{'es' if outcome['sketches'] != 1 else ''} ready to open on the site.")
    for note in outcome["notes"]:
        printer(error_line(note, said, kind="note"))
    for problem in outcome["problems"]:
        printer(error_line(problem, said))
    return outcome


def _entry_for(sketch, page, settings, commands, lines, content_root, largest, first_load, said,
               thumbnails, sketch_reads):
    """The manifest entry for one sketch, or (None, the problem)."""
    app = settings.get("app")
    width = height = None
    source = None
    thumbnail = None
    sketch_bytes = 0
    if "file" in settings:
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
        sketch_bytes = read["bytes"]
        if read["size"] is not None:
            width, height = read["size"]
        app = app or read["app"]
        if read["thumbnail"] is not None:
            name = f"{sketch['key'][:16]}.png"
            thumbnails[name] = read["thumbnail"]
            picture_width, picture_height = _png_size(read["thumbnail"])
            thumbnail = {"name": name, "width": picture_width, "height": picture_height}
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
        "attribution": {"kind": "file"},
        "size": size,
    }
    return entry, None

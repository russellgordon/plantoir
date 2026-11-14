#!/usr/bin/env python3
"""
A built site carries only the files its published pages use (#901).

The site's own emitter (support/quartz/plugins/emitters/plantoirAssets.ts,
with its rules in siteFilesRules.ts) decides which of the course's files go
into `public/`: a file goes in only when a page students can see shows it,
links to it, or names it in a way Plantoir draws (the Print button's PDF, a
GeoGebra sketch, the footer). Quartz's own Assets emitter, which it replaces,
copied every file that is not a page.

This module is the SECOND reading, written separately and run on the BUILT
site after Quartz has finished (contracts/shared-rules.json -> siteFiles):

* **A hole**: a built page names a course file that is not in `public/`. The
  file is PUT BACK (copied in at the address Quartz would have used) and the
  teacher is told in one line (Russell's ruling on #901, 2026-11-13). A name
  that matches no course file at all is the teacher's own broken link and is
  left alone, as before.
* **An exposure**: a course file in `public/` that no built page names.
  Counted as `unreferenced`, which the gates treat as a failure. Of those, a
  file is taken out (`takenOut`) only when every reading agrees nothing that
  stays names it: this reader does not, and no text file that stays on the
  site (the site's own files, the course files this reader names, and in
  turn any mentioned course file) mentions its name in any spelling the
  emitter's reading could decode to it, case and Unicode form folded. A
  browser fetches only an address some file it was sent contains, so taking
  out cannot make a hole; where the readings disagree the file STAYS and
  is counted (901a's Fable sweep, MUST 1).

Both safety counts are zero on a correct build, and verify.sh and the tests
fail when either is not. In the field they keep a page whole and an unused
file off the site whatever the emitter got wrong.

Both readers follow ONE list of the places that hold an address
(siteFiles.addresses: src, href, srcset, poster, an object's data, SVG's
href, a style's url(), data-geogebra and the like, on the elements that use
them, and the meta tags whose content is an address). A page that only
mentions a file's name, in alt text, a link's title, a description or its
text, does not use the file. A file a CARRIED file loads is used too: a
carried HTML, SVG or CSS file is read at the same places, from its own
address, transitively (siteFiles.followed). JavaScript is never read. Both
readers read an address by the same steps (siteFiles.resolve).

It reads `content/` to know which files are the course's (the same walk
Quartz's Assets emitter makes: every non-page file, no dotted names, not
under an ignored folder, symlinks followed), to read a carried HTML, SVG or
CSS file, and to copy a hole back. It never reads a page's Markdown: it
reads the HTML students are sent.

Stdlib only; shared by the image and Windows' runtime.
"""
from __future__ import annotations

import json
import os
import re
import shutil
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit

import sys as _sys
_sys.path.insert(0, str(Path(__file__).resolve().parent))
import contracts  # noqa: E402

MARKER = "PLANTOIR_SITE_FILES:"
# Beside the built site (`.merged_output/section<N>/`), counts only: whether
# a build is the first to leave files off, and whether the count changed.
# contracts/file-formats.json -> siteFilesRecord. Hidden: the freshness checks
# skip it, and nothing outside public/ is deployed.
RECORD_NAME = ".site-files.json"
# Written by the section's quartz/build.ts beside public/ once every emitter
# has finished (siteFiles.doneMarker): the moment a preview's check may read
# the site. Removed by build_site.py before Quartz starts.
DONE_MARKER = ".plantoir-emit-done"
# Written by the emitter beside public/ when it stops a build at the follow
# limit (siteFiles.followed.stopFile), so build_site.py can say why Quartz
# exited. Removed by build_site.py before Quartz starts.
FOLLOW_LIMIT_FILE = ".plantoir-follow-limit"
SIDE_FILE = "plantoir_site_files.json"

# Quartz 4.5.0's own defaults (quartz.config.ts), the folders its file walk
# leaves out. A section's settings never change them.
DEFAULT_IGNORE_PATTERNS = ("private", "templates", ".obsidian")
# Written into content/ by the build itself; always carried
# (siteFiles.alwaysCarried).
ALWAYS_CARRIED = ("favicon.ico",)

_BASE = "https://site.invalid/"
_SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
# The one way both readers read an address (siteFiles.resolve, cases in
# siteFiles.resolveCases): siteFilesRules.ts has the same steps. Whitespace
# is named character by character, because Python's \s and str.strip() and
# JavaScript's \s and trim() do not agree (U+001C to U+001F, U+0085, U+FEFF).
_ASCII_SPACE = "\t\n\f\r "
_URL_EDGES = re.compile("^[\x00-\x20]+|[\x00-\x20]+$")
_URL_INSIDE = re.compile("[\t\n\r]")
_SLASHES = re.compile("/{2,}")
_DOT_SEGMENTS = {".": ".", "%2e": "."}
_DOT_DOT_SEGMENTS = {"..": "..", ".%2e": "..", "%2e.": "..", "%2e%2e": ".."}
_CSS_URL = re.compile(r"url\([\t\n\f\r ]*(['\"]?)(.*?)\1[\t\n\f\r ]*\)", re.IGNORECASE | re.DOTALL)
# CSS's other two places that hold an address as a plain string (901a fix
# review, I2): `@import "x.css"` and the strings inside image-set(...).
# siteFilesRules.ts has the same three, letter for letter.
_CSS_IMPORT = re.compile(r"@import[\t\n\f\r ]+(['\"])([\s\S]*?)\1", re.IGNORECASE)
_IMAGE_SET = re.compile(r"image-set\(", re.IGNORECASE)
# <meta http-equiv="refresh" content="5; url=x.pdf">: the time, a separator,
# an optional `url=`, then the address, quoted or not (the HTML standard's
# shared declarative refresh steps, simplified the same way in both readers).
_REFRESH = re.compile(r"^[\t\n\f\r ]*[0-9.]+[\t\n\f\r ]*[;,]?[\t\n\f\r ]*(?:url[\t\n\f\r ]*=[\t\n\f\r ]*)?([\s\S]*)$",
                      re.IGNORECASE)
# JavaScript's \s, which Quartz's sluggify uses, is not Python's: it has the
# byte-order mark and lacks \x1c-\x1f.
_JS_SPACE = re.compile("[\t\n\v\f\r    -     　﻿]")
_EXTENSION = re.compile(r"\.[A-Za-z0-9]+$")
_SRCSET_NAMES = ("srcset", "imagesrcset")
# Text files the built site is searched for a file's name before it may be
# taken out (mention-anywhere, check.exposure): by the name in public/ for a
# file the site made, by the content path's ending for a course file (a
# course .html file is in public/ without its ending).
_TEXT_SUFFIXES = (".html", ".htm", ".svg", ".json", ".xml", ".js", ".mjs", ".css", ".txt", ".webmanifest")
_JSON_ESCAPE = re.compile(r"\\u([0-9A-Fa-f]{4})")


def rules(*keys, optional: bool = False):
    return contracts.section("shared-rules", "siteFiles", *keys, optional=optional)


# ---- Quartz's own names ----------------------------------------------------

def slugify_file_path(path: str) -> str:
    """Quartz 4.5.0's slugifyFilePath (quartz/util/path.ts), letter for
    letter: the address below the site's root that its Assets emitter copies
    a content file to. Pinned against the TypeScript by siteFiles.slugCases,
    run here and in the image (check_site_files_rules_against_the_site.py)."""
    text = path
    if text.startswith("/"):
        text = text[1:]
    if text.endswith("/"):
        text = text[:-1]
    found = _EXTENSION.search(text)
    extension = found.group(0) if found else None
    without = text[: len(text) - len(extension)] if extension else text
    if extension is None or extension in (".md", ".html"):
        extension = ""
    segments = []
    for segment in without.split("/"):
        segment = _JS_SPACE.sub("-", segment)
        segment = segment.replace("&", "-and-").replace("%", "-percent")
        segment = segment.replace("?", "").replace("#", "")
        segments.append(segment)
    slug = "/".join(segments)
    if slug.endswith("/"):
        slug = slug[:-1]
    if slug == "_index" or slug.endswith("/_index"):
        slug = slug[: -len("_index")] + "index"
    return slug + extension


def _is_ignored(parts: tuple, ignore_patterns) -> bool:
    if parts and parts[0] in ignore_patterns:
        return True
    for part in parts:
        if part.startswith("."):
            return True
    return False


def course_files(content_dir: Path, ignore_patterns=DEFAULT_IGNORE_PATTERNS) -> dict:
    """{address: path below content/} for every file Quartz's Assets emitter
    would have copied: not a page (`.md`, matched exactly, as Quartz does), no
    part of the path starting with a dot, not under an ignored folder, with
    symbolic links followed (content/Media is one on a Mac)."""
    found = {}
    root = Path(content_dir)
    if not root.is_dir():
        return found
    seen = set()
    for folder, folders, files in os.walk(root, followlinks=True):
        relative_folder = Path(folder).relative_to(root)
        # A link back up the tree is walked once, never round and round.
        try:
            real = os.path.realpath(folder)
        except OSError:
            real = folder
        if real in seen:
            folders[:] = []
            continue
        seen.add(real)
        kept = []
        for name in sorted(folders):
            if not _is_ignored(relative_folder.parts + (name,), ignore_patterns):
                kept.append(name)
        folders[:] = kept
        for name in sorted(files):
            parts = relative_folder.parts + (name,)
            if name.endswith(".md") or _is_ignored(parts, ignore_patterns):
                continue
            relative = "/".join(parts)
            found.setdefault(slugify_file_path(relative), relative)
    return found


# ---- Reading a built page --------------------------------------------------

_ADDRESS_RULES: dict = {}


def address_rules_cached() -> dict:
    if not _ADDRESS_RULES:
        _ADDRESS_RULES.update(address_rules())
    return _ADDRESS_RULES


def address_rules() -> dict:
    """siteFiles.addresses: which attributes, on which elements, hold an
    address, and which meta tags' content is one. The ONE list this reader
    and the site's emitter follow (the emitter gets it in the side file)."""
    return rules("addresses")


class _AddressReader(HTMLParser):
    """Every address a built page holds, and only those: an attribute
    siteFiles.addresses names, on an element it names, read as it says; a
    <meta> whose content is an address (metaContent); url(...) inside a
    <style> element. A page that only MENTIONS a file's name (alt text, a
    link's title, a description Quartz fills from the page's opening text,
    text, code) does not use it."""

    def __init__(self, address_rules: dict):
        super().__init__(convert_charrefs=True)
        self.addresses: list = []
        self._in_style = 0
        self._by_attribute: dict = {}
        for rule in address_rules.get("attributes", []):
            self._by_attribute.setdefault(rule["attribute"], []).append(rule)
        self._meta_names = set(address_rules.get("metaContent", []))
        self._meta_http_equiv = set()
        for kind in address_rules.get("metaHttpEquiv", []):
            self._meta_http_equiv.add(kind.lower())

    def _rule_for(self, tag: str, name: str):
        for rule in self._by_attribute.get(name, []):
            if "*" in rule["elements"] or tag in rule["elements"]:
                return rule
        return None

    def _read(self, read: str, value: str) -> None:
        if read == "css":
            self.addresses.extend(addresses_in_css(value))
        elif read == "geogebraSketch":
            sketch = geogebra_sketch_address(value)
            if sketch is not None:
                self.addresses.append(sketch)
        elif read == "jsonUrl":
            url = json_url(value)
            if url is not None:
                self.addresses.append(url)
        elif read == "fromSiteRoot":
            if value.strip(_ASCII_SPACE) != "":
                self.addresses.append("/" + value.strip(_ASCII_SPACE).lstrip("/"))
        elif read == "srcset":
            for item in value.split(","):
                first = re.split("[\t\n\f\r ]+", item.strip(_ASCII_SPACE))
                if first and first[0] != "":
                    self.addresses.append(first[0])
        elif read == "address":
            self.addresses.append(value)

    def _element(self, tag, attrs):
        tag = tag.lower()
        if tag == "meta":
            # `property` is read before `name` when a <meta> has both, in
            # both readers (addresses.metaRule; 901a fix review, M3).
            meta_property, meta_name, content, http_equiv = None, None, None, None
            for name, value in attrs:
                if value is None:
                    continue
                if name == "property" and meta_property is None:
                    meta_property = value
                elif name == "name" and meta_name is None:
                    meta_name = value
                elif name == "content" and content is None:
                    content = value
                elif name == "http-equiv" and http_equiv is None:
                    http_equiv = value
            named = meta_property if meta_property is not None else meta_name
            if named in self._meta_names and content is not None:
                self.addresses.append(content)
            if http_equiv is not None and http_equiv.strip(_ASCII_SPACE).lower() in self._meta_http_equiv and content is not None:
                refreshed = refresh_address(content)
                if refreshed is not None:
                    self.addresses.append(refreshed)
        for name, value in attrs:
            if value is None:
                continue
            rule = self._rule_for(tag, name.lower())
            if rule is not None:
                self._read(rule["read"], value)

    def handle_starttag(self, tag, attrs):
        self._element(tag, attrs)
        if tag == "style":
            self._in_style += 1

    def handle_startendtag(self, tag, attrs):
        self._element(tag, attrs)

    def handle_endtag(self, tag):
        if tag == "style" and self._in_style:
            self._in_style -= 1

    def handle_data(self, data):
        if self._in_style:
            self.addresses.extend(addresses_in_css(data))


def json_url(value: str):
    """A data-phet JSON's `url`, or None (phet.inline.ts sets a frame's src
    to it)."""
    try:
        data = json.loads(value)
    except ValueError:
        return None
    if isinstance(data, dict) and isinstance(data.get("url"), str):
        return data["url"]
    return None


def addresses_in_css(text: str) -> list:
    """Every address a piece of CSS holds (addresses.reads.css): each
    url(...), each string after @import, and each string directly inside an
    image-set(...) or -webkit-image-set(...)."""
    text = text or ""
    found = []
    for match in _CSS_URL.finditer(text):
        found.append(match.group(2).strip(_ASCII_SPACE))
    for match in _CSS_IMPORT.finditer(text):
        found.append(match.group(2).strip(_ASCII_SPACE))
    found.extend(_strings_in_image_sets(text))
    return found


def _strings_in_image_sets(text: str) -> list:
    """The quoted strings at the first level of each image-set(...): an
    address. A url(...) inside it is read by _CSS_URL, and a type("...")
    is one level deeper, so neither is taken here."""
    found = []
    for match in _IMAGE_SET.finditer(text):
        depth = 1
        position = match.end()
        while position < len(text) and depth > 0:
            character = text[position]
            if character in ("'", '"'):
                closing = text.find(character, position + 1)
                if closing < 0:
                    break
                if depth == 1:
                    found.append(text[position + 1:closing].strip(_ASCII_SPACE))
                position = closing + 1
                continue
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            position += 1
    return found


def refresh_address(content: str):
    """The address in a <meta http-equiv="refresh"> content, or None."""
    match = _REFRESH.match(content or "")
    if match is None:
        return None
    rest = match.group(1).strip(_ASCII_SPACE)
    if rest[:1] in ("'", '"'):
        closing = rest.find(rest[0], 1)
        rest = rest[1:closing] if closing >= 0 else rest[1:]
    rest = rest.strip(_ASCII_SPACE)
    if rest == "":
        return None
    return rest


def geogebra_sketch_address(value: str):
    """`<root>/<sketch>` from a data-geogebra JSON, or None. A sketch from
    geogebra.org's store is under static/, never a course file."""
    try:
        data = json.loads(value)
    except ValueError:
        return None
    if not isinstance(data, dict):
        return None
    sketch = data.get("sketch")
    root = data.get("root")
    if not isinstance(sketch, str) or sketch == "":
        return None
    if not isinstance(root, str) or root == "":
        root = "."
    return root.rstrip("/") + "/" + sketch


def addresses_in_html(text: str, address_rules: dict | None = None) -> list:
    reader = _AddressReader(address_rules if address_rules is not None else address_rules_cached())
    try:
        reader.feed(text)
        reader.close()
    except Exception:
        pass
    return reader.addresses


def page_slug_of(html_relative: str) -> str:
    """The address a built page is served at: `Unit-1/Day-1.html` is
    `Unit-1/Day-1`, a folder's `Unit-1/index.html` is `Unit-1/index` (the
    same folder for a relative address)."""
    if html_relative.endswith(".html"):
        return html_relative[: -len(".html")]
    return html_relative


def resolved_from_page(page_slug: str, address: str):
    """The address below the site's root that `address`, written on the page
    (or carried file) at `page_slug`, asks a browser for, read by the steps of
    siteFiles.resolve, which siteFilesRules.resolvedFromPage takes too: the
    edges' controls and spaces dropped, tabs and line breaks inside dropped,
    a backslash read as a slash, dot segments (%2e spellings included)
    resolved, no query or fragment, decoded, a run of slashes read as one,
    no leading slash. None for an address on another site, an anchor, or no
    address at all. Case and Unicode form are kept (exactMatch)."""
    value = _URL_EDGES.sub("", str(address or ""))
    value = _URL_INSIDE.sub("", value).replace("\\", "/")
    if value == "" or value.startswith("#") or value.startswith("//") or _SCHEME.match(value):
        return None
    cut = len(value)
    for mark in ("?", "#"):
        found = value.find(mark)
        if found >= 0 and found < cut:
            cut = found
    segments = []
    for segment in value[:cut].split("/"):
        lowered = segment.lower()
        if lowered in _DOT_SEGMENTS:
            segments.append(_DOT_SEGMENTS[lowered])
        elif lowered in _DOT_DOT_SEGMENTS:
            segments.append(_DOT_DOT_SEGMENTS[lowered])
        else:
            segments.append(segment)
    try:
        joined = urljoin(_BASE + page_slug, "/".join(segments))
        parts = urlsplit(joined)
    except ValueError:
        return None
    if parts.scheme != "https" or parts.netloc != "site.invalid":
        return None
    path = _SLASHES.sub("/", unquote(parts.path))
    return path.lstrip("/")


def _built_pages(public_dir: Path):
    for folder, _folders, files in os.walk(public_dir):
        for name in sorted(files):
            if name.endswith(".html"):
                full = Path(folder) / name
                yield full, full.relative_to(public_dir).as_posix()


def addresses_the_site_uses(public_dir: Path) -> set:
    """Every address below the root that a built page asks for."""
    used = set()
    address_rules_now = address_rules()
    for full, relative in _built_pages(public_dir):
        try:
            text = full.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        slug = page_slug_of(relative)
        for address in addresses_in_html(text, address_rules_now):
            target = resolved_from_page(slug, address)
            if target:
                used.add(target)
    return used


# ---- Following a carried file ---------------------------------------------

def followed_rules() -> dict:
    return rules("followed")


def kind_of_carried_file(relative: str, kinds: dict):
    """"html", "css" or None, by the content path's ending, lower-cased
    (siteFiles.followed.kinds)."""
    lower = relative.lower()
    for ending, kind in kinds.items():
        if lower.endswith(ending):
            return kind
    return None


def follow_carried_files(used, files: dict, content_dir, address_rules: dict, followed: dict) -> set:
    """`used`, with every course file a carried HTML, SVG or CSS file loads,
    transitively (siteFiles.followed; 901a fix review, I1). Each carried file
    of a followed kind is read from content/ at the same places as a built
    page (addresses_in_html, or addresses_in_css for a stylesheet), each
    address is resolved from the file's OWN address, and only a course file
    is followed: an address on another site, or one that names no course
    file, is never read. Breadth first with a visited set, so a loop is read
    once and the walk reads no more files than the course holds. No depth
    limit and no count limit here: the count limit is the emitter's
    (followed.limits), which stops the build before this check runs
    (followed.limitsRule). JavaScript is never read (siteFiles.knownLimits)."""
    kinds = followed.get("kinds", {})
    content = Path(content_dir)
    result = set(used)
    queue = sorted(used)
    visited = set()
    position = 0
    while position < len(queue):
        address = queue[position]
        position += 1
        if address in visited:
            continue
        visited.add(address)
        relative = files.get(address)
        if relative is None:
            continue
        kind = kind_of_carried_file(relative, kinds)
        if kind is None:
            continue
        try:
            text = (content / relative).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if kind == "html":
            found = addresses_in_html(text, address_rules)
        else:
            found = addresses_in_css(text)
        for candidate in found:
            target = resolved_from_page(address, candidate)
            if target is None or target not in files:
                continue
            result.add(target)
            if target not in visited:
                queue.append(target)
    return result


def _folded(text: str) -> str:
    """Composed Unicode form, lower case: the mention search folds both, so
    no spelling difference can let a file be taken out (check.exposure)."""
    import unicodedata
    return unicodedata.normalize("NFC", text).lower()


def _mention_forms(text: str) -> list:
    """The text a file's name is looked for in: as written, and as the
    emitter's reading would have it after every decoding it makes on the
    way to an address (an HTML character reference, a JSON \\u escape in
    data-geogebra or data-phet, the tabs and line breaks a browser drops,
    a percent escape). Both folded (_folded)."""
    import html as html_module
    decoded = html_module.unescape(text)
    decoded = _JSON_ESCAPE.sub(lambda match: chr(int(match.group(1), 16)), decoded)
    decoded = _URL_INSIDE.sub("", decoded)
    decoded = unquote(decoded)
    forms = [_folded(text)]
    folded_decoded = _folded(decoded)
    if folded_decoded != forms[0]:
        forms.append(folded_decoded)
    return forms


def _mentioned_names(address: str) -> list:
    """The last part of the file's address, folded, as written and as a
    browser would encode it."""
    from urllib.parse import quote
    name = address.rsplit("/", 1)[-1]
    if name == "":
        return []
    names = [_folded(name)]
    encoded = _folded(quote(name, safe=""))
    if encoded != names[0]:
        names.append(encoded)
    return names


def _is_text(relative: str) -> bool:
    return relative.lower().endswith(_TEXT_SUFFIXES)


def _addresses_mentioned(public_dir: Path, addresses, files: dict) -> set:
    """Which of `addresses` (course files on the site that the check's
    reader does not name) the site's text mentions, where the text is every
    text file on the site that STAYS: every file the site made (pages,
    contentIndex.json, sitemap.xml, scripts, stylesheets; by its name in
    public/), every course file the check names (by its content path's
    ending, so a course .html file served without its ending is read), and,
    in turn, every one of `addresses` that is mentioned and is text itself
    (check.exposure, 901a's Fable sweep, MUST 1: a picture named only by a
    carried page the check reads differently was taken out). Each file is
    read once, and the search stops as soon as every address is found."""
    public = Path(public_dir)
    waiting = {}
    found = set()
    for address in addresses:
        names = _mentioned_names(address)
        if not names:
            found.add(address)
        else:
            waiting[address] = names
    if not waiting:
        return found
    candidates = set(addresses)
    sources = []
    for folder, _folders, names in os.walk(public):
        for name in sorted(names):
            relative = (Path(folder) / name).relative_to(public).as_posix()
            if relative in candidates:
                continue
            content_path = files.get(relative)
            if _is_text(content_path if content_path is not None else relative):
                sources.append(relative)
    position = 0
    while position < len(sources) and waiting:
        relative = sources[position]
        position += 1
        try:
            text = (public / relative).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        forms = _mention_forms(text)
        for address in list(waiting):
            hit = False
            for candidate in waiting[address]:
                for form in forms:
                    if candidate in form:
                        hit = True
                        break
                if hit:
                    break
            if hit:
                found.add(address)
                del waiting[address]
                if _is_text(files.get(address, address)):
                    sources.append(address)
    return found


# ---- The check -------------------------------------------------------------

def check(public_dir, content_dir, *, repair: bool = True, emitter: str = "plantoir",
          always_carried=ALWAYS_CARRIED, ignore_patterns=DEFAULT_IGNORE_PATTERNS) -> dict:
    """
    Read the built site and say what it carries (siteFiles.check):

        {"carried", "leftOff", "leftOffBytes", "putBack", "putBackFailed",
         "takenOut", "unreferenced", "putBackFiles", "putBackFailedFiles"}

    With `repair`, a hole is put back and a file no page names and nothing
    that stays on the site mentions is taken out (check.exposure), with
    Plantoir's emitter and with Quartz's own alike: `emitter` changes nothing
    the check does (901a's Fable sweep, MUST 1, which also retired the
    quartz-only rule that took every unreferenced file out unread). The
    `*Files` lists are paths below content/, for the teacher's console only:
    never on the trail or in the marker.
    """
    public = Path(public_dir)
    content = Path(content_dir)
    files = course_files(content, ignore_patterns)
    always = set()
    for name in always_carried:
        always.add(slugify_file_path(name))
    # What the built pages name, then what the files they carry load.
    used = follow_carried_files(addresses_the_site_uses(public), files, content, address_rules(),
                                followed_rules())

    put_back, put_back_failed = [], []
    for address in sorted(used):
        relative = files.get(address)
        if relative is None:
            continue
        target = public / address
        if target.is_file():
            continue
        if not repair:
            put_back.append(relative)
            continue
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(content / relative, target)
            put_back.append(relative)
        except OSError:
            put_back_failed.append(relative)

    unreferenced = []
    for address in sorted(files):
        if address in always or address in used:
            continue
        if (public / address).is_file():
            unreferenced.append(address)

    # Taken out only when every reading agrees that nothing which stays names
    # it: the check's reader does not, and no text that stays mentions it in
    # any spelling. Where they disagree the file STAYS and is counted in
    # unreferenced, which fails the gates (check.exposure). The same with
    # Quartz's own emitter, which read nothing.
    taken_out = 0
    if unreferenced:
        mentioned = _addresses_mentioned(public, unreferenced, files)
        for address in unreferenced:
            if address in mentioned:
                continue
            if repair:
                try:
                    (public / address).unlink()
                    taken_out += 1
                except OSError:
                    pass
            else:
                taken_out += 1

    carried, left_off, left_off_bytes = 0, 0, 0
    for address, relative in files.items():
        present = (public / address).is_file()
        if not repair:
            present = present or relative in put_back
        if present:
            carried += 1
        else:
            left_off += 1
            try:
                left_off_bytes += (content / relative).stat().st_size
            except OSError:
                pass
    return {
        "carried": carried,
        "leftOff": left_off,
        "leftOffBytes": left_off_bytes,
        "putBack": len(put_back),
        "putBackFailed": len(put_back_failed),
        "takenOut": taken_out,
        "unreferenced": len(unreferenced),
        "putBackFiles": put_back,
        "putBackFailedFiles": put_back_failed,
    }


# ---- What is said ----------------------------------------------------------

def read_record(host_output_dir) -> dict | None:
    try:
        with open(Path(host_output_dir) / RECORD_NAME, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def write_record(host_output_dir, outcome: dict, build_id: str) -> None:
    record = {"buildId": build_id}
    for key in ("carried", "leftOff", "leftOffBytes", "putBack", "putBackFailed", "takenOut", "unreferenced"):
        record[key] = int(outcome.get(key, 0))
    path = Path(host_output_dir) / RECORD_NAME
    temporary = path.with_name(path.name + ".tmp")
    try:
        Path(host_output_dir).mkdir(parents=True, exist_ok=True)
        with open(temporary, "w", encoding="utf-8") as handle:
            json.dump(record, handle, indent=2)
            handle.write("\n")
        os.replace(temporary, path)
    except OSError:
        try:
            temporary.unlink()
        except OSError:
            pass


def size_words(byte_count: int) -> str:
    """siteFiles.words.size: GB or MB with one decimal (10^9, 10^6 bytes), KB
    rounded up below a megabyte, with a full stop whatever the language."""
    if byte_count >= 1_000_000_000:
        return f"{byte_count / 1_000_000_000:.1f} GB"
    if byte_count >= 1_000_000:
        return f"{byte_count / 1_000_000:.1f} MB"
    kilobytes = (byte_count + 999) // 1000
    return f"{max(kilobytes, 1)} KB"


def _filled(template: str, values: dict) -> str:
    text = template
    for key, value in values.items():
        text = text.replace("{" + key + "}", str(value))
    return text


def lines_to_say(outcome: dict, previous: dict | None, *, mode: str, section,
                 side_file_written: bool = True) -> list:
    """The sentences the console shows for one build (siteFiles.words and
    siteFiles.whenSaid): the first build that leaves anything off says what
    changed and why, once; a later build says the count only when it is not
    the last one's; a file put back is said, one line each.

    When the build could not write the side file (`side_file_written`
    False), the emitter read no page's addresses and the check put back
    every file the pages use: that is said in ONE line, which says the site
    is complete, instead of a line per file (siteFiles.sideFile.whenMissing).
    A file that could not be put back is still said on its own line, and
    then the site is not called complete."""
    words = rules("words")
    said = []
    put_back_key = "putBackPreview" if mode == "preview" else "putBack"
    failed_key = "putBackFailedPreview" if mode == "preview" else "putBackFailed"
    put_back_files = outcome.get("putBackFiles", [])
    if not side_file_written and put_back_files and not outcome.get("putBackFailedFiles"):
        whole_key = "sideFileMissingPutBackPreview" if mode == "preview" else "sideFileMissingPutBack"
        put_back_count = len(put_back_files)
        said.append(_filled(words[counted_key(whole_key, put_back_count)], {
            "count": put_back_count,
            "section": section,
        }))
        put_back_files = []
    for relative in put_back_files:
        said.append(_filled(words[put_back_key], {"file": relative}))
    for relative in outcome.get("putBackFailedFiles", []):
        said.append(_filled(words[failed_key], {"file": relative}))
    count = int(outcome.get("leftOff", 0))
    values = {
        "count": count,
        "size": size_words(int(outcome.get("leftOffBytes", 0))),
        "section": section,
    }
    if previous is None:
        if count > 0:
            key = "firstTimePreview" if mode == "preview" else "firstTimeDeploy"
            said.append(_filled(words[counted_key(key, count)], values))
    elif count != int(previous.get("leftOff", -1)) and (count > 0 or int(previous.get("leftOff", 0)) > 0):
        said.append(_filled(words[counted_key("changed", count)], values))
    return said


def counted_key(key: str, count: int) -> str:
    """A counted sentence's key for `count` files (siteFiles.words.counted):
    `<key>One` for one, `<key>Several` for any other count, the way the app's
    other counted sentences are kept (assist wording's alreadyHiddenOne and
    alreadyHiddenSeveral)."""
    return key + ("One" if count == 1 else "Several")


def marker_line(outcome: dict, previous: dict | None, *, course: str, section, mode: str,
                emitter: str) -> str:
    """The one PLANTOIR_SITE_FILES: line a build prints (siteFiles.marker).
    Counts only: never a file's or a page's name."""
    payload = {"course": course, "section": section, "mode": mode}
    for key in ("carried", "leftOff", "leftOffBytes", "putBack", "putBackFailed", "takenOut", "unreferenced"):
        payload[key] = int(outcome.get(key, 0))
    payload["firstTime"] = previous is None
    payload["changed"] = previous is not None and int(previous.get("leftOff", -1)) != payload["leftOff"]
    payload["assetsEmitter"] = emitter
    return MARKER + " " + json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def follow_limit() -> int:
    """siteFiles.followed.limits.files: how many carried HTML, SVG and CSS
    files the emitter reads in one build before it stops the build."""
    return int(followed_rules()["limits"]["files"])


def stopped_at_the_follow_limit(output_dir) -> bool:
    """Whether the emitter of the build in `output_dir` stopped it at the
    follow limit: it writes followed.stopFile beside public/ before it
    throws (siteFiles.followed.limitsRule)."""
    return (Path(output_dir) / FOLLOW_LIMIT_FILE).exists()


def forget_the_follow_limit(output_dir) -> None:
    """Remove an earlier build's stop file, so only this build's is read."""
    try:
        (Path(output_dir) / FOLLOW_LIMIT_FILE).unlink()
    except OSError:
        pass


def stopped_marker_line(*, course: str, section, mode: str) -> str:
    """The PLANTOIR_SITE_FILES: line of a build the emitter stopped at the
    follow limit (siteFiles.marker.stoppedRule): no counts, because nothing
    was checked or put on the website."""
    payload = {"course": course, "section": section, "mode": mode, "stopped": "followLimit",
               "limit": follow_limit()}
    return MARKER + " " + json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def stopped_lines(*, course: str, section, mode: str) -> list:
    """What a build the emitter stopped at the follow limit prints: the
    teacher's sentence (words.followLimitStopped, or its preview form), then
    the marker."""
    key = "followLimitStoppedPreview" if mode == "preview" else "followLimitStopped"
    sentence = _filled(rules("words", key), {"limit": f"{follow_limit():,}", "section": section})
    return [sentence, stopped_marker_line(course=course, section=section, mode=mode)]


def after_the_build(public_dir, content_dir, host_output_dir, *, course: str, section, mode: str,
                    emitter: str, build_id: str, printer=print, side_file_written: bool = True) -> dict:
    """Run the check on the finished build, say what a teacher reads, print
    the marker and keep the record. Raises only what the check itself
    raises; the caller decides what a failure costs."""
    previous = read_record(host_output_dir)
    outcome = check(public_dir, content_dir, repair=True, emitter=emitter)
    if emitter != "plantoir":
        printer("plantoir: error: " + rules("words", "emitterNotSwapped"))
    for line in lines_to_say(outcome, previous, mode=mode, section=section,
                             side_file_written=side_file_written):
        printer(line)
    printer(marker_line(outcome, previous, course=course, section=section, mode=mode, emitter=emitter))
    write_record(host_output_dir, outcome, build_id)
    return outcome


def side_file(footer_html: str) -> dict:
    """quartz/plantoir_site_files.json, which the site's emitter reads
    (siteFiles.sideFile): the files always carried and every address the
    footer names, which the emitter resolves from each page as it resolves
    the page's own, siteFiles.addresses, so the emitter reads a page's tree
    by the same list as this module reads the built page, and
    siteFiles.followed, so it follows a carried file as this module does."""
    return {
        "alwaysCarried": list(ALWAYS_CARRIED),
        "footerAddresses": addresses_in_html(footer_html or ""),
        "addresses": address_rules(),
        "followed": followed_rules(),
    }


def write_side_file(quartz_dir, footer_html: str) -> None:
    path = Path(quartz_dir) / SIDE_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(side_file(footer_html), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main(argv=None) -> int:
    """`site_files.py --check <public> <content>`: count only, change
    nothing, print the outcome as JSON (verify.sh). Exit 1 when either safety
    count is above zero."""
    import argparse
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", nargs=2, metavar=("PUBLIC", "CONTENT"), required=True)
    args = parser.parse_args(argv)
    outcome = check(args.check[0], args.check[1], repair=False)
    shown = {}
    for key, value in outcome.items():
        if not key.endswith("Files"):
            shown[key] = value
    print(json.dumps(shown, sort_keys=True))
    if outcome["putBack"] or outcome["putBackFailed"] or outcome["unreferenced"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

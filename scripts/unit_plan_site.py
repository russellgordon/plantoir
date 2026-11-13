#!/usr/bin/env python3
"""
A course's unit plans, made ready to share as a small website (#709).

The plans live in `courses/<CODE>/.internal/planning/` (contracts/
shared-rules.json -> unitPlanning), written by an outside assistant through the
`plantoir-unit-planning` skill. Sharing sends them to Cloudflare Pages
(`share_plan.py`); this module holds everything about that which needs no
network, so both platforms run the same rules and the tests run them with no
account:

  * `check`: the problems that stop a share, one kind per rule the skill
    already asks an assistant to keep (unitPlanning.share.checkKinds);
  * `is_answer_key`: the one rule for which PDFs are answer keys
    (unitPlanning.share.answerKeys), so an open share leaves them out;
  * `stage`: the files that are uploaded, by allowlist, into a folder of
    their own, with a `404.html` so a missing path is never answered by the
    list of plans (Cloudflare's single-page-app rule, measured for #709);
  * `worker_js`: the small program that asks for the username and password;
  * `open_headers`: the one header an open share sends;
  * `school_year`, `year_label` and `project_name`: one plan site per school
    year, its name ending in a random suffix that is never cut.

Every rule's data is read from the contract rather than retyped here, so the
contract is the one place it is written. Stdlib only.
"""
from __future__ import annotations

import base64
import datetime as dt
import hashlib
import json
import re
import secrets
import shutil
import unicodedata
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote

import sys as _sys
_sys.path.insert(0, str(Path(__file__).resolve().parent))
import contracts  # noqa: E402
import toolchain_paths  # noqa: E402

# The files a plan site may hold. Everything else is left out by name: a
# teacher's `plan.json`, a `.tex`, an `.htaccess` or `.htpasswd`, and a
# `_headers`, `_redirects`, `_routes.json` or `_worker.js` of their own, which
# Cloudflare would otherwise obey.
ALLOWED_SUFFIXES = (".html", ".css", ".woff2", ".pdf", ".png", ".jpg", ".jpeg", ".svg", ".txt")

# The largest single file Cloudflare Pages takes, as deploy.py's
# CF_MAX_FILE_BYTES (25 MiB).
MAX_FILE_BYTES = 25 * 1024 * 1024

# Where the app's own copy of the stylesheets and fonts is, inside the image
# and in Windows' runtime alike: the skill's template, which reaches every
# working folder unchanged (unitPlanning.assetsAreThePlantoirs).
BUNDLED_ASSETS_PARTS = ("agent_guidance", "skills", "plantoir-unit-planning", "template", "assets")

SUFFIX_LETTERS = "abcdefghijklmnopqrstuvwxyz0123456789"


def unit_planning() -> dict:
    return contracts.load("shared-rules")["unitPlanning"]


def share_rules() -> dict:
    return unit_planning()["share"]


def bundled_assets_dir() -> Path:
    return Path(toolchain_paths.SUPPORT_DIR).joinpath(*BUNDLED_ASSETS_PARTS)


# ---------------------------------------------------------------- answer keys

def _name_words(stem: str) -> list[str]:
    """The words of a name: accents folded first (Corrigé reads as corrige,
    Réponses as reponses), then split at a lower-case letter followed by a
    capital (AnswerKey) and at every character that is not a letter."""
    folded = unicodedata.normalize("NFKD", stem)
    plain = ""
    for character in folded:
        if not unicodedata.combining(character):
            plain += character
    spaced = re.sub(r"([a-z])([A-Z])", r"\1 \2", plain)
    words = []
    for word in re.split(r"[^a-z]+", spaced.lower()):
        if word:
            words.append(word)
    return words


def is_answer_key(file_name: str) -> bool:
    """The answer-key HINT (unitPlanning.share.answerKeys), for a file
    outside a unit's Answer Keys folder: a name holding one of `phrases` as
    words in a row, or one of `atTheEndOrBeside` as its last word or beside
    one of `besideWords`. Since #833 the folder is the rule and this only
    catches the obvious names a plan made before it carries, so Dissolution
    Lab.pdf, Key Ideas.pdf and Answer Sheet.pdf are not caught (Russell,
    2026-11-13). Only the name is read, never the file."""
    rule = share_rules()["answerKeys"]
    name = Path(file_name).name
    suffix = Path(name).suffix.lower()
    if suffix not in rule["appliesTo"]:
        return False
    words = _name_words(name[: len(name) - len(suffix)])
    for phrase in rule["phrases"]:
        length = len(phrase)
        for index in range(0, len(words) - length + 1):
            if words[index:index + length] == phrase:
                return True
    beside = set(rule["besideWords"])
    for index, word in enumerate(words):
        if word not in rule["atTheEndOrBeside"]:
            continue
        if index == len(words) - 1:
            return True
        if index > 0 and words[index - 1] in beside:
            return True
        if index + 1 < len(words) and words[index + 1] in beside:
            return True
    return False


def in_answer_keys_folder(place: str) -> bool:
    """Whether a place in the plan is inside a folder named Answer Keys, in
    any letter case, at any depth (unitPlanning.share.answerKeysFolder)."""
    folder_name = share_rules()["answerKeysFolder"]["name"].lower()
    parts = Path(place).parts
    for part in parts[:-1]:
        if part.lower() == folder_name:
            return True
    return False


# --------------------------------------------------------------------- check

@dataclass
class Problem:
    kind: str
    place: str
    detail: str = ""

    def line(self) -> str:
        if self.detail:
            return f"{self.place}: {self.detail}"
        return self.place


class _PageReader(HTMLParser):
    """Classes, links, what a page loads, its stylesheets and its metas.
    Comments are not read: the template's patterns are written in them."""

    LOADS = {("link", "href"), ("script", "src"), ("img", "src"), ("iframe", "src"),
             ("source", "src"), ("video", "src"), ("audio", "src"), ("embed", "src"),
             ("object", "data"), ("track", "src"), ("img", "srcset"), ("source", "srcset")}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.classes: set[str] = set()
        self.links: list[str] = []
        self.loads: list[str] = []
        self.sheets: list[str] = []
        self.metas: list[dict] = []
        self.styles: list[str] = []
        self._in_style = False

    def handle_starttag(self, tag, attributes):
        values = {}
        for name, value in attributes:
            values[name.lower()] = value or ""
        if "class" in values:
            self.classes.update(values["class"].split())
        for name in ("href", "src", "data"):
            if name in values:
                self.links.append(values[name])
        for (load_tag, load_attr) in self.LOADS:
            if tag == load_tag and load_attr in values:
                self.loads.append(values[load_attr])
        if tag == "link" and "stylesheet" in values.get("rel", "").lower().split():
            self.sheets.append(values.get("href", ""))
        if tag == "meta":
            self.metas.append(values)
        if "style" in values:
            self.styles.append(values["style"])
        if tag == "style":
            self._in_style = True

    def handle_endtag(self, tag):
        if tag == "style":
            self._in_style = False

    def handle_data(self, data):
        if self._in_style:
            self.styles.append(data)


def _read_page(path: Path) -> _PageReader:
    reader = _PageReader()
    reader.feed(path.read_text(encoding="utf-8", errors="replace"))
    reader.close()
    return reader


def _defined_classes(sheet_text: str) -> set[str]:
    text = re.sub(r"/\*.*?\*/", "", sheet_text, flags=re.DOTALL)
    classes: set[str] = set()
    for selector in re.findall(r"([^{}]+)\{", text):
        classes.update(re.findall(r"\.([A-Za-z_][\w-]*)", selector))
    return classes


_EXTERNAL = re.compile(r"^\s*(?:[a-z][a-z0-9+.-]*:)?//", re.IGNORECASE)
_CSS_LOADS = re.compile(r"""@import\s+(?:url\(\s*)?["']?([^"')\s;]+)|url\(\s*["']?([^"')\s]+)""", re.IGNORECASE)


def _loads_from_the_internet(target: str) -> bool:
    lowered = target.strip().lower()
    return lowered.startswith(("http:", "https:")) or bool(_EXTERNAL.match(lowered))


def _is_relative(target: str) -> bool:
    lowered = target.strip().lower()
    if not lowered or lowered.startswith("#"):
        return False
    if re.match(r"^[a-z][a-z0-9+.-]*:", lowered):
        return False  # mailto:, tel:, data:, https: ...
    if lowered.startswith("//"):
        return False
    return True


def _target_exists(page: Path, target: str, planning_dir: Path) -> bool:
    path_part = target.split("#", 1)[0].split("?", 1)[0]
    if not path_part:
        return True
    decoded = unquote(path_part)
    if decoded.startswith("/"):
        resolved = (planning_dir / decoded.lstrip("/")).resolve()
    else:
        resolved = (page.parent / decoded).resolve()
    try:
        resolved.relative_to(planning_dir.resolve())
    except ValueError:
        return False
    if resolved.is_file():
        return True
    if resolved.is_dir() and (resolved / "index.html").is_file():
        return True
    return False


def _hidden(relative: Path) -> bool:
    for part in relative.parts:
        if part.startswith("."):
            return True
    return False


def _unit_folders(planning_dir: Path) -> list[Path]:
    rules = unit_planning()
    pattern = re.compile(rules["slugRules"]["pattern"])
    never = set(rules["neverSlugs"])
    units = []
    for child in sorted(planning_dir.iterdir()):
        if child.is_dir() and not child.is_symlink() and pattern.match(child.name) \
                and child.name not in never and (child / "index.html").is_file():
            units.append(child)
    return units


def _files_to_share(planning_dir: Path):
    """Every regular file under the planning folder that is not hidden, not
    inside an excluded folder and not a link, with its relative path."""
    never_folders = set(unit_planning()["neverFolderNames"])
    for path in sorted(planning_dir.rglob("*")):
        relative = path.relative_to(planning_dir)
        if _hidden(relative):
            continue
        skip = False
        for part in relative.parts[:-1]:
            if part in never_folders:
                skip = True
        if skip:
            continue
        if path.is_symlink() or not path.is_file():
            continue
        yield path, relative


def check(planning_dir: Path, assets_dir: Path | None = None) -> list[Problem]:
    """The problems that stop a share, in the order of the contract's
    checkKinds. `assets_dir` is the stylesheets the share will carry (the
    app's own copy); left out, the planning folder's own are read."""
    planning_dir = Path(planning_dir)
    rules = unit_planning()
    problems: list[Problem] = []
    if not planning_dir.is_dir():
        return [Problem("noPlans", "the planning folder", "there is no planning folder")]
    units = _unit_folders(planning_dir)
    if not units:
        problems.append(Problem("noPlans", "the planning folder", "no unit folder holds an index.html"))

    pattern = re.compile(rules["slugRules"]["pattern"])
    never_slugs = set(rules["neverSlugs"])
    never_folders = set(rules["neverFolderNames"])

    # Folders: a top-level one that is neither assets nor a unit name, and any
    # folder at any depth with a name a backup leaves out.
    for path in sorted(planning_dir.rglob("*")):
        relative = path.relative_to(planning_dir)
        if not path.is_dir() or path.is_symlink():
            continue
        if path.name in never_folders:
            problems.append(Problem("excludedName", relative.as_posix(),
                                    "a folder of this name is left out of every backup"))
            continue
        if _hidden(relative):
            continue
        if len(relative.parts) == 1 and path.name != "assets":
            if not pattern.match(path.name) or path.name in never_slugs:
                problems.append(Problem("badSlug", relative.as_posix(),
                                        "a unit folder's name is lowercase letters, digits and hyphens"))

    # The list of plans names every unit.
    root_index = planning_dir / "index.html"
    listed: set[str] = set()
    if root_index.is_file():
        for link in _read_page(root_index).links:
            if not _is_relative(link):
                continue
            path_part = unquote(link.split("#", 1)[0].split("?", 1)[0])
            while path_part.startswith("./"):
                path_part = path_part[2:]
            first = path_part.split("/", 1)[0]
            if first:
                listed.add(first)
    for unit in units:
        if unit.name not in listed:
            problems.append(Problem("unitNotListed", unit.name,
                                    "the list of plans has no link to this unit"))

    stylesheets = rules["stylesheets"]
    sheet_names = set()
    for sheet in stylesheets.values():
        sheet_names.add(Path(sheet).name)
    sheets_dir = Path(assets_dir) if assets_dir is not None else planning_dir / "assets"
    defined: dict[str, set[str]] = {}
    for name in sheet_names:
        sheet_path = sheets_dir / name
        if sheet_path.is_file():
            defined[name] = _defined_classes(sheet_path.read_text(encoding="utf-8", errors="replace"))
        else:
            defined[name] = set()

    for path, relative in _files_to_share(planning_dir):
        place = relative.as_posix()
        try:
            size = path.stat().st_size
        except OSError:
            size = 0
        if size > MAX_FILE_BYTES:
            problems.append(Problem("tooLarge", place, f"{size / (1024 * 1024):.1f} MB, over 25 MB"))
        suffix = path.suffix.lower()
        if suffix == ".css":
            text = path.read_text(encoding="utf-8", errors="replace")
            for match in _CSS_LOADS.finditer(text):
                target = match.group(1) or match.group(2) or ""
                if _loads_from_the_internet(target):
                    problems.append(Problem("externalUrl", place, target))
        if suffix != ".html":
            continue
        reader = _read_page(path)
        for link in reader.links:
            if _is_relative(link) and not _target_exists(path, link, planning_dir):
                problems.append(Problem("brokenLink", place, link))
        for target in reader.loads:
            if _loads_from_the_internet(target):
                problems.append(Problem("externalUrl", place, target))
        for style in reader.styles:
            for match in _CSS_LOADS.finditer(style):
                target = match.group(1) or match.group(2) or ""
                if _loads_from_the_internet(target):
                    problems.append(Problem("externalUrl", place, target))
        has_noindex = False
        for meta in reader.metas:
            if meta.get("name", "").lower() == "robots":
                words = set(re.split(r"[\s,]+", meta.get("content", "").lower()))
                if "noindex" in words and "nofollow" in words:
                    has_noindex = True
        if not has_noindex:
            problems.append(Problem("noNoindex", place, "no robots noindex, nofollow meta"))
        # The pages the skill makes link exactly one of the two sheets.
        if path.name in stylesheets and (len(relative.parts) == 1 or relative.parts[0] != "assets"):
            linked = set()
            for href in reader.sheets:
                linked.add(Path(unquote(href.split("?", 1)[0])).name)
            linked = linked & sheet_names
            if len(linked) != 1:
                problems.append(Problem("wrongSheet", place,
                                        "a plan page links exactly one of plan.css and correlation.css"))
            else:
                sheet = next(iter(linked))
                for name in sorted(reader.classes):
                    if name not in defined.get(sheet, set()):
                        problems.append(Problem("missingClass", place, f"class {name} has no rule in {sheet}"))

    robots = planning_dir / "robots.txt"
    expected = ["User-agent: *", "Disallow: /"]
    if not robots.is_file():
        problems.append(Problem("noRobots", "robots.txt", "there is no robots.txt"))
    else:
        lines = []
        for line in robots.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.strip():
                lines.append(line.strip())
        if lines != expected:
            problems.append(Problem("noRobots", "robots.txt", "it is not the two lines the template has"))

    order = rules["share"]["checkKinds"]
    problems.sort(key=lambda problem: order.index(problem.kind) if problem.kind in order else len(order))
    return problems


# ----------------------------------------------------------------- documents

PICTURE_SUFFIXES = (".png", ".jpg", ".jpeg", ".svg")
ALWAYS_GO_SUFFIXES = (".html", ".css", ".woff2") + PICTURE_SUFFIXES
DOCUMENT_SUFFIXES = (".pdf", ".txt")
SHARED = "shared"
NOT_SHARED = "notShared"


@dataclass
class Document:
    """One row of the tables before a share (unitPlanning.share.documents):
    a file the teacher may hold back, or one listed to say it cannot go."""
    place: str
    name: str
    unit: str
    unit_order: int
    folder: str
    kind: str
    answer_key: str | None
    movable: bool

    def line(self, start: str) -> dict:
        return {"place": self.place, "name": self.name, "unit": self.unit, "unitOrder": self.unit_order,
                "folder": self.folder, "kind": self.kind, "answerKey": self.answer_key,
                "movable": self.movable, "start": start}


def kind_of(name: str) -> str:
    """The Kind column (documents.kinds), by extension without case."""
    suffix = Path(name).suffix.lower()
    kinds = share_rules()["documents"]["kinds"]
    if suffix in kinds:
        return kinds[suffix]
    if not suffix:
        return "File"
    return suffix[1:].upper() + " file"


def class_of(place: str, unit_names: set | None = None, loaded: set | None = None) -> str:
    """documents.rule: document, cannotShare, alwaysGoes or neverListed, for
    a place the share would consider (not hidden, not a link, not in a
    folder a backup leaves out). `loaded` is every place a page of the plan
    loads (`loaded_by_pages`): a picture a page shows is the plan's own and
    always goes; any other picture is one a teacher attached, a handout or a
    key, and is a document (review M1). With no `loaded` given, every
    picture outside the folder and the hint is taken as the plan's own."""
    relative = Path(place)
    name = relative.name
    suffix = relative.suffix.lower()
    if relative.parts[0] == "assets":
        return "neverListed"
    if name in share_rules()["documents"]["neverListed"]:
        return "neverListed"
    if len(relative.parts) == 1 and name.lower() == "404.html":
        return "neverListed"
    if len(relative.parts) == 1 and name.lower() == "robots.txt":
        return "alwaysGoes"
    keys_folder = in_answer_keys_folder(place)
    if suffix not in ALLOWED_SUFFIXES:
        return "cannotShare"
    if keys_folder or suffix in DOCUMENT_SUFFIXES:
        return "document"
    if suffix in PICTURE_SUFFIXES and is_answer_key(name):
        return "document"
    if suffix in PICTURE_SUFFIXES and loaded is not None and place not in loaded:
        return "document"
    return "alwaysGoes"


def _srcset_targets(value: str) -> list[str]:
    targets = []
    for part in value.split(","):
        words = part.strip().split()
        if words:
            targets.append(words[0])
    return targets


def loaded_by_pages(planning_dir: Path) -> set:
    """Every place in the plan a page LOADS (an img, a source, a link such
    as an icon, a style's url()), as the page shows it rather than offers it
    to be opened: the pictures that are the plan's own. A picture a page only
    links to (an <a href>) is not among them."""
    planning_dir = Path(planning_dir)
    found: set = set()
    if not planning_dir.is_dir():
        return found
    root = planning_dir.resolve()
    for path, relative in _files_to_share(planning_dir):
        if path.suffix.lower() != ".html":
            continue
        reader = _read_page(path)
        targets = []
        for target in reader.loads:
            # A srcset ("a.png 1x, b.png 2x") names several; a src with a
            # space in its name names one.
            if re.search(r"\s\d+(?:\.\d+)?[wx]\s*(?:,|$)", target):
                targets.extend(_srcset_targets(target))
            else:
                targets.append(target)
        for style in reader.styles:
            for match in _CSS_LOADS.finditer(style):
                targets.append(match.group(1) or match.group(2) or "")
        for target in targets:
            if not _is_relative(target):
                continue
            decoded = unquote(target.split("#", 1)[0].split("?", 1)[0])
            if not decoded:
                continue
            if decoded.startswith("/"):
                resolved = (planning_dir / decoded.lstrip("/")).resolve()
            else:
                resolved = (path.parent / decoded).resolve()
            try:
                found.add(resolved.relative_to(root).as_posix())
            except ValueError:
                continue
    return found


def answer_key_of(place: str) -> str | None:
    """folder (inside an Answer Keys folder), hint (outside it, and the name
    hint matches) or None."""
    if in_answer_keys_folder(place):
        return "folder"
    if is_answer_key(Path(place).name):
        return "hint"
    return None


def _unit_order(planning_dir: Path, units: list[Path]) -> dict:
    """Each unit's place in the list of plans: the order the root index.html
    links them, then the rest by name."""
    names = []
    for unit in units:
        names.append(unit.name)
    linked: list[str] = []
    root_index = planning_dir / "index.html"
    if root_index.is_file():
        for link in _read_page(root_index).links:
            if not _is_relative(link):
                continue
            path_part = unquote(link.split("#", 1)[0].split("?", 1)[0])
            while path_part.startswith("./"):
                path_part = path_part[2:]
            first = path_part.split("/", 1)[0]
            if first in names and first not in linked:
                linked.append(first)
    for name in sorted(names):
        if name not in linked:
            linked.append(name)
    order = {}
    for index, name in enumerate(linked):
        order[name] = index
    return order


@dataclass
class Listing:
    documents: list = field(default_factory=list)
    own_files: int = 0


def list_documents(planning_dir: Path, bundled_assets: Path | None = None) -> Listing:
    """The documents a share lists, sorted by place, and the count of the
    plan's own files that always go (the app's assets included)."""
    planning_dir = Path(planning_dir)
    listing = Listing()
    units = _unit_folders(planning_dir) if planning_dir.is_dir() else []
    order = _unit_order(planning_dir, units)
    unit_names = set(order.keys())
    if not planning_dir.is_dir():
        return listing
    loaded = loaded_by_pages(planning_dir)
    for path, relative in _files_to_share(planning_dir):
        place = relative.as_posix()
        kind = class_of(place, unit_names, loaded)
        if kind == "alwaysGoes":
            listing.own_files += 1
            continue
        if kind == "neverListed":
            continue
        unit = relative.parts[0] if len(relative.parts) > 1 and relative.parts[0] in unit_names else ""
        inner = relative.parts[1:-1] if unit else relative.parts[:-1]
        listing.documents.append(Document(
            place=place, name=relative.name, unit=unit, unit_order=order.get(unit, len(order)),
            folder="/".join(inner), kind=kind_of(relative.name), answer_key=answer_key_of(place),
            movable=(kind == "document")))
    if bundled_assets is not None and Path(bundled_assets).is_dir():
        for path in Path(bundled_assets).rglob("*"):
            relative = path.relative_to(bundled_assets)
            if _hidden(relative) or path.is_symlink() or not path.is_file():
                continue
            if path.suffix.lower() in ALLOWED_SUFFIXES:
                listing.own_files += 1
    return listing


def starting_place(document: Document, protected: bool, include_answer_keys: bool,
                   remembered: dict | None = None) -> str:
    """unitPlanning.share.startingPlace: where a listed document starts."""
    if not document.movable:
        return NOT_SHARED
    if remembered and remembered.get(document.place) in (SHARED, NOT_SHARED):
        return remembered[document.place]
    if document.answer_key is not None:
        return SHARED if (protected or include_answer_keys) else NOT_SHARED
    return SHARED


def remembered_choices(marker: dict | None) -> dict:
    """The marker's `documents`, or {} for a marker from before #833."""
    if not marker:
        return {}
    choices = marker.get("documents")
    if not isinstance(choices, dict):
        return {}
    return choices


def refused_choices(choices: dict, listing: Listing, planning_dir: Path | None = None) -> list[str]:
    """rememberedChoices: the entries the share refuses, a Shared entry for
    a place it would never send (one listed as cannotShare, a path outside
    the plan, a hidden one, one in a folder a backup leaves out, or, given
    `planning_dir`, a link or a place under a linked folder) or a value that
    is neither of the two. An entry for a place not listed (renamed,
    deleted, or a page that always goes) is not refused: it is forgotten."""
    movable = set()
    listed = set()
    for document in listing.documents:
        listed.add(document.place)
        if document.movable:
            movable.add(document.place)
    refused = []
    for place, value in choices.items():
        if not isinstance(place, str) or value not in (SHARED, NOT_SHARED):
            refused.append(str(place))
            continue
        if value != SHARED or place in movable:
            continue
        if place in listed:
            refused.append(place)
            continue
        relative = Path(place)
        never_folders = set(unit_planning()["neverFolderNames"])
        escapes = place.startswith("/") or ".." in relative.parts or place == ""
        hidden = False
        for part in relative.parts:
            if part.startswith(".") or part in never_folders:
                hidden = True
        if escapes or hidden:
            refused.append(place)
            continue
        if planning_dir is not None and _is_a_link_in(Path(planning_dir), relative):
            refused.append(place)
    return refused


def _is_a_link_in(planning_dir: Path, relative: Path) -> bool:
    """Whether a place, or any folder on the way to it, is a link."""
    current = Path(planning_dir)
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            return True
    return False


def settle(listing: Listing, protected: bool, include_answer_keys: bool, remembered: dict | None) -> dict:
    """Every listed document's place: the remembered choice, else the rule."""
    settled = {}
    for document in listing.documents:
        settled[document.place] = starting_place(document, protected, include_answer_keys, remembered)
    return settled


def hold_back_keys_with_nobody_to_look(listing: Listing, settled: dict) -> int:
    """unitPlanning.share.unattendedKeys: with nobody at the lists, an open
    share sends no answer key, of either kind, on the strength of a
    remembered choice or the tick alone. Moves every key settled in Shared
    to Not shared and returns how many moved."""
    held = 0
    for document in listing.documents:
        if document.answer_key is not None and settled.get(document.place) == SHARED:
            settled[document.place] = NOT_SHARED
            held += 1
    return held


def kept_choices(choices: dict, listing: Listing) -> dict:
    """rememberedChoices pruned: only the entries for movable documents that
    are listed now, so a renamed or deleted file is forgotten."""
    kept = {}
    for document in listing.documents:
        if document.movable and choices.get(document.place) in (SHARED, NOT_SHARED):
            kept[document.place] = choices[document.place]
    return kept


def mark_of(document: Document) -> str | None:
    """startingPlace.mark: what the Note column says beside a name."""
    if not document.movable:
        return "cannotShare"
    if document.answer_key == "folder":
        return "answerKey"
    if document.answer_key == "hint":
        return "mayBeAnswerKey"
    return None


def warns(document: Document, place: str, protected: bool) -> bool:
    """startingPlace.warns: an answer key in Shared in a share with no
    password carries the warning."""
    return document.answer_key is not None and place == SHARED and not protected


ADVICE_KIND = "keyOutsideFolder"


def advice(planning_dir: Path) -> list[Problem]:
    """unitPlanning.share.advice: never a refusal. Each file outside an
    Answer Keys folder whose name the hint matches, to move into it."""
    found = []
    words = share_rules()["advice"]["line"]
    for document in list_documents(planning_dir).documents:
        if document.answer_key == "hint":
            found.append(Problem(ADVICE_KIND, document.place, words.replace("{place}", document.place)))
    return found


# --------------------------------------------------------------------- stage

@dataclass
class Staged:
    files: list[str] = field(default_factory=list)
    left_out: list[str] = field(default_factory=list)
    answer_keys_left_out: int = 0
    answer_keys_left_out_names: list[str] = field(default_factory=list)
    answer_keys_shared: int = 0
    documents_shared: int = 0
    documents_held_back: int = 0
    units: int = 0
    bytes: int = 0


def not_shared_here_page() -> str:
    sentence = share_rules()["words"]["notSharedHere"]
    return ("<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
            "<meta name=\"robots\" content=\"noindex, nofollow\">\n"
            "<title>Not shared</title>\n</head>\n<body>\n"
            f"<p>{sentence}</p>\n</body>\n</html>\n")


def stage(planning_dir: Path, out_dir: Path, bundled_assets: Path | None,
          include_answer_keys: bool, settled: dict | None = None) -> Staged:
    """Copies what is shared into `out_dir`: the plan's own files that always
    go (pages, pictures, stylesheets, fonts), and each listed document whose
    place in `settled` is shared; never a hidden file, a link, anything in a
    folder a backup leaves out, a file of a kind no share takes, or a
    document `settled` does not name (one that appeared after the teacher
    saw the lists). With no `settled`, the rule decides with
    `include_answer_keys` as the only choice (unitPlanning.share.stage).
    The app's own `assets/` replaces the plan's (left out, the plan's own
    are copied), and a `404.html` is written last so a teacher's own cannot
    replace it."""
    planning_dir = Path(planning_dir)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    staged = Staged()
    staged.units = len(_unit_folders(planning_dir))
    order = _unit_order(planning_dir, _unit_folders(planning_dir))
    loaded = loaded_by_pages(planning_dir)
    if settled is None:
        settled = settle(list_documents(planning_dir), False, include_answer_keys, None)
    for path, relative in _files_to_share(planning_dir):
        place = relative.as_posix()
        if relative.parts[0] == "assets":
            # The plan's own stylesheets and fonts: replaced by the app's
            # copy when there is one, and copied as they are otherwise.
            if bundled_assets is not None:
                continue
            # Only stylesheets, fonts and pictures: a document under assets/
            # is never listed, so it never goes (review L4).
            kind = "alwaysGoes" if path.suffix.lower() in (".css", ".woff2") + PICTURE_SUFFIXES else "cannotShare"
        else:
            kind = class_of(place, set(order.keys()), loaded)
        if kind in ("neverListed", "cannotShare"):
            staged.left_out.append(place)
            continue
        if kind == "document":
            key = answer_key_of(place)
            if settled.get(place) != SHARED:
                staged.documents_held_back += 1
                if key is not None:
                    staged.answer_keys_left_out += 1
                    staged.answer_keys_left_out_names.append(place)
                else:
                    staged.left_out.append(place)
                continue
            staged.documents_shared += 1
            if key is not None:
                staged.answer_keys_shared += 1
        target = out_dir / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        staged.files.append(place)
        staged.bytes += target.stat().st_size
    if bundled_assets is not None and Path(bundled_assets).is_dir():
        for path in sorted(Path(bundled_assets).rglob("*")):
            relative = path.relative_to(bundled_assets)
            if _hidden(relative) or path.is_symlink() or not path.is_file():
                continue
            if path.suffix.lower() not in ALLOWED_SUFFIXES:
                continue
            target = out_dir / "assets" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            staged.files.append(("assets" / relative).as_posix())
            staged.bytes += target.stat().st_size
    page = out_dir / "404.html"
    page.write_text(not_shared_here_page(), encoding="utf-8")
    staged.files.append("404.html")
    staged.bytes += page.stat().st_size
    return staged


# ------------------------------------------------------------- the password

def realm_for(course_code: str) -> str:
    """The words a browser shows in its password box: "<CODE> unit plans",
    ASCII only, with nothing that could end the header's quoted string."""
    code = re.sub(r"[^A-Za-z0-9 .-]", "", str(course_code)).strip() or "Course"
    return f"{code} unit plans"


def credential_b64(username: str, password: str) -> str:
    return base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")


WORKER_TEMPLATE = """// Written by Plantoir for a shared unit plan (#709). Every request comes here
// first. With a password, it is asked for before any page is sent, and only a
// salted hash of it is kept here. Either way, only the files this share holds
// are answered: Cloudflare's edge cache keeps a file a later share left out
// (an answer key, a deleted page) for up to a week at its old address, and
// this list is what stops it being served from there.
const PROTECTED = __PROTECTED__;
const SALT = "__SALT__";
const HASH = "__HASH__";
const REALM = "__REALM__";
// Which share this is, sent on every answer, so the share that sent it can
// tell its own deployment from the one before (the main address answers the
// old one for up to 2.2 s, measured).
const SHARE = "__SHARE__";
const FILES = new Set(__FILES__);
let verified = null;
function hex(buf) {
  const bytes = new Uint8Array(buf);
  let out = "";
  for (let i = 0; i < bytes.length; i++) out += bytes[i].toString(16).padStart(2, "0");
  return out;
}
function same(a, b) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
async function allowed(header) {
  if (!PROTECTED) return true;
  if (!header || !header.startsWith("Basic ")) return false;
  const given = header.slice(6).trim();
  if (verified !== null && same(given, verified)) return true;
  const data = new TextEncoder().encode(SALT + given);
  const digest = hex(await crypto.subtle.digest("SHA-256", data));
  if (same(digest, HASH)) { verified = given; return true; }
  return false;
}
function shared(pathname) {
  let path;
  try { path = decodeURIComponent(pathname); } catch (e) { return false; }
  path = path.replace(/^\\/+/, "");
  if (path === "" || path.endsWith("/")) return FILES.has(path + "index.html");
  return FILES.has(path) || FILES.has(path + ".html") || FILES.has(path + "/index.html");
}
const HEADERS = { "X-Robots-Tag": "noindex, nofollow", "Cache-Control": "no-store", "X-Plantoir-Share": SHARE };
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!(await allowed(request.headers.get("Authorization")))) {
      return new Response("This page needs a username and password.", {
        status: 401,
        headers: Object.assign({ "WWW-Authenticate": 'Basic realm="' + REALM + '", charset="UTF-8"' }, HEADERS)
      });
    }
    if (!shared(url.pathname)) {
      const missing = await env.ASSETS.fetch(new Request(new URL("/404.html", url), request));
      return new Response(missing.body, { status: 404, headers: Object.assign({ "Content-Type": "text/html; charset=utf-8" }, HEADERS) });
    }
    const asset = await env.ASSETS.fetch(request);
    const answer = new Response(asset.body, asset);
    answer.headers.set("X-Robots-Tag", "noindex, nofollow");
    answer.headers.set("X-Plantoir-Share", SHARE);
    answer.headers.set("Cache-Control", PROTECTED ? "private, no-store" : "no-store");
    return answer;
  }
};
"""


def worker_js(credential: str | None, realm: str, files: list[str], salt: str | None = None,
              share_id: str = "") -> str:
    """The share's `_worker.js`, for an open share and a protected one alike.

    Protected (`credential` given): SHA-256 of a fresh 16-byte salt followed
    by the base64 credential, compared in constant time and remembered once
    verified, so a page and its PDFs are hashed once per isolate; the
    password itself is never in it. Open (`credential` None): no question.

    Both answer only the paths in `files` (the staged files, `_worker.js`
    never among them), with 404 and the staged 404.html for anything else:
    measured 2026-11-12, Cloudflare's edge cache went on serving an answer key
    an open re-share had left out (cf-cache-status HIT, s-maxage=604800), and
    the worker runs before the cache. `salt` is for tests."""
    if salt is None:
        salt = secrets.token_hex(16)
    shared_files = []
    for name in sorted(files):
        if name != "_worker.js" and name != "_headers":
            shared_files.append(name)
    safe_realm = re.sub(r'[^A-Za-z0-9 .-]', "", realm)
    if credential is None:
        digest = ""
        salt = ""
    else:
        digest = hashlib.sha256((salt + credential).encode("utf-8")).hexdigest()
    text = WORKER_TEMPLATE.replace("__PROTECTED__", "true" if credential is not None else "false")
    text = text.replace("__SALT__", salt)
    text = text.replace("__HASH__", digest)
    text = text.replace("__REALM__", safe_realm)
    text = text.replace("__SHARE__", re.sub(r"[^a-f0-9]", "", share_id))
    return text.replace("__FILES__", json.dumps(shared_files, ensure_ascii=True))


def open_headers() -> str:
    return "/*\n  X-Robots-Tag: noindex, nofollow\n"


# ---------------------------------------------------------- names and years

def school_year(today: dt.date) -> int:
    """The calendar year the school year starts in: from 1 August
    (SchoolYear.rolloverMonth on the mac, Timetable.AcademicYearStarting on
    Windows) the new year, before it the one that started last August."""
    rollover = share_rules()["schoolYear"]["rolloverMonth"]
    if today.month >= rollover:
        return today.year
    return today.year - 1


def year_label(year: int) -> str:
    return f"{year}-{(year + 1) % 100:02d}"


def new_suffix() -> str:
    length = share_rules()["names"]["suffixLength"]
    letters = []
    for _ in range(length):
        letters.append(secrets.choice(SUFFIX_LETTERS))
    return "".join(letters)


def _name_part(text: str | None) -> str:
    text = (text or "").lower().replace(" ", "-").replace("_", "-")
    text = re.sub(r"[^a-z0-9-]", "-", text)
    return re.sub(r"-{2,}", "-", text).strip("-")


def project_name(code: str, year: int, surname: str | None, suffix: str) -> str:
    """`<code>-plans-<year label>-<surname>-<suffix>`, at most 58 characters
    (Cloudflare's limit, measured). The suffix is NEVER cut: the surname is
    shortened first, then dropped, and only then the code. A plain
    sanitize_pages_name would cut the end, which is the suffix."""
    limit = share_rules()["names"]["maxLength"]
    tail = f"-plans-{year_label(year)}"
    code_part = _name_part(code) or "course"
    surname_part = re.sub(r"[^a-z0-9]", "", (surname or "").lower())
    ending = f"-{suffix}"
    room_for_code = limit - len(tail) - len(ending)
    if len(code_part) > room_for_code:
        code_part = code_part[:room_for_code].strip("-") or "c"
    base = code_part + tail
    room = limit - len(base) - len(ending) - 1
    if surname_part and room >= 1:
        return f"{base}-{surname_part[:room]}{ending}"
    return base + ending


def marker_name(year: int) -> str:
    return f"plans-{year}.json"


def read_json_file(path: Path) -> dict | None:
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if isinstance(data, dict):
        return data
    return None

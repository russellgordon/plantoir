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

def is_answer_key(file_name: str) -> bool:
    """A PDF named the way the handouts and test skills name an answer key:
    its name without `.pdf`, ignoring case, ends in one of the contract's
    endings (" - Answers", " - Solutions" ...) or is one of its whole names
    ("Marking Guide"). Nothing is guessed from other words in a name, so a
    teacher can predict the rule."""
    rule = share_rules()["answerKeys"]
    name = Path(file_name).name
    if not name.lower().endswith(".pdf"):
        return False
    stem = name[:-4].lower()
    for ending in rule["endings"]:
        if stem.endswith(ending.lower()):
            return True
    for whole in rule["wholeNames"]:
        if stem == whole.lower():
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


# --------------------------------------------------------------------- stage

@dataclass
class Staged:
    files: list[str] = field(default_factory=list)
    left_out: list[str] = field(default_factory=list)
    answer_keys_left_out: int = 0
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
          include_answer_keys: bool) -> Staged:
    """Copies what is shared into `out_dir`: the allowlisted files, never a
    hidden one, a link or anything in a folder a backup leaves out; every
    answer key left out unless `include_answer_keys`; the app's own `assets/`
    in place of the plan's (left out, the plan's own are copied); and a
    `404.html`, written last so a teacher's own cannot replace it."""
    planning_dir = Path(planning_dir)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    staged = Staged()
    staged.units = len(_unit_folders(planning_dir))
    for path, relative in _files_to_share(planning_dir):
        place = relative.as_posix()
        if bundled_assets is not None and relative.parts[0] == "assets":
            continue
        if len(relative.parts) == 1 and relative.name.lower() == "404.html":
            staged.left_out.append(place)
            continue
        if path.suffix.lower() not in ALLOWED_SUFFIXES:
            staged.left_out.append(place)
            continue
        if is_answer_key(relative.name) and not include_answer_keys:
            staged.answer_keys_left_out += 1
            continue
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
  path = path.replace(/^\/+/, "");
  if (path === "" || path.endsWith("/")) return FILES.has(path + "index.html");
  return FILES.has(path) || FILES.has(path + ".html") || FILES.has(path + "/index.html");
}
const HEADERS = { "X-Robots-Tag": "noindex, nofollow", "Cache-Control": "no-store" };
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
    answer.headers.set("Cache-Control", PROTECTED ? "private, no-store" : "no-store");
    return answer;
  }
};
"""


def worker_js(credential: str | None, realm: str, files: list[str], salt: str | None = None) -> str:
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

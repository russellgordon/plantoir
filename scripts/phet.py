#!/usr/bin/env python3
"""
PhET simulations from a page's own ```phet fences (#674).

A teacher writes, on a page:

    ```phet
    sim: gas-properties
    alt: Pump gas into a box and watch pressure, temperature and volume change.
    locale: fr
    screens: 1, 2
    ```

and students get a card with the simulation's picture, its title and a
button; a tap opens the simulation in place, served by the class site itself.
A student's browser asks PhET nothing (phetFences.address: every frame's
address starts `yotta=false&allowLinks=false`, which stops the simulation's
reports to PhET, its Google Tag Manager load and its update check, measured
2026-11-13 in Chromium and WebKit).

This module is the build's half. It finds those fences on the pages students
can see (by the gate's own visibility rule), reads each one
(phetFences.settings), and makes sure the site has a copy of every
simulation they name: the copy kept on this computer, or one downloaded from
PhET now and kept (scripts/kept_downloads.py, keptDownloads; Russell's
ruling of 2026-11-13: downloaded only when a page uses it). It writes the
simulation and its picture into `quartz/static/phet/<sim>/` and a manifest
into `quartz/plantoir-phet/` for the site's transformer
(support/quartz/plugins/transformers/plantoirPhet.ts); the site's loader
(support/quartz/components/scripts/phet.inline.ts) makes the frame only when
a student taps.

**A build with no internet and a simulation not downloaded before STOPS**
(ruling, 2026-11-13; phetFences.stop): `prepare` answers `stop`, and
build_site prints keptDownloads.stop's lines and exits before Quartz runs.
That is the opposite of GeoGebra's choice (a sketch that cannot be fetched
is a folder problem and the page shows its lines), and on purpose: a site
that says it built and shows no simulation where the page promises one is
the fault this prevents. A misspelt name is NOT a stop: the internet was
there, the next build will not fix it, and the Problems tab says which page
and line (phetSimulationsNotReady, simulationNotFound).

Every rule a case can pin is in contracts/shared-rules.json -> phetFences,
and scripts/test_phet.py runs them. The reasons are in
documentation/05-build-pipeline.md -> "PhET simulations: what the build
does".
"""

import difflib
import gzip
import json
import re
import shutil
import struct
import time
import unicodedata
from pathlib import Path

import contracts
import figures
import kept_downloads
import markdown_code
import site_health

LANGUAGE = "phet"
KIND = "phet"
WORKSPACE = "plantoir-phet"
SITE_FOLDER = "phet"
SIMULATION_FILE = "simulation.html"
SCREENSHOT_FILE = "screenshot.png"


def rules(*keys):
    return contracts.section("shared-rules", "phetFences", *keys)


def words() -> dict:
    return rules("words")


# ---- Reading a fence -----------------------------------------------------------

_SETTING = re.compile(r"^([a-z_0-9]+)[ \t]*:[ \t]*(.*?)[ \t]*$")


def _unquoted(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


_SIM_NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
_SIM_PATHS = (
    re.compile(r"^/(?:[A-Za-z_]{2,6}/)?simulations?/([A-Za-z0-9-]+)(?:[/?#].*)?$"),
    re.compile(r"^/sims/html/([A-Za-z0-9-]+)(?:[/?#].*)?$"),
)


def sim_name_of(value: str):
    """The simulation `sim:` names, or None (phetFences.simNames): its name
    as in its address, or a phet.colorado.edu address that holds one."""
    text = figures.js_trim(str(value or ""))
    if _SIM_NAME.match(text.lower()) and "/" not in text:
        return text.lower()
    address = re.sub(r"^https?://", "", text, flags=re.IGNORECASE)
    host, slash, path = address.partition("/")
    if host.lower() not in rules("simNames", "hosts") or not slash:
        return None
    for pattern in _SIM_PATHS:
        match = pattern.match("/" + path)
        if match and _SIM_NAME.match(match.group(1).lower()):
            return match.group(1).lower()
    return None


def screens_of(value: str):
    """`screens:` as a list of distinct whole numbers from 1, or None."""
    pieces = [piece.strip() for piece in str(value or "").replace(";", ",").split(",")]
    found = []
    for piece in pieces:
        if not piece.isdigit() or int(piece) < 1 or int(piece) in found:
            return None
        found.append(int(piece))
    return found or None


_LOCALE = re.compile(r"^([A-Za-z]{2,3})(?:[-_]([A-Za-z]{2}))?$")


def locale_tag(value: str):
    """A language as PhET names one (`fr`, `fr_CA`), or None."""
    match = _LOCALE.match(figures.js_trim(str(value or "")))
    if match is None:
        return None
    language = match.group(1).lower()
    region = match.group(2)
    return f"{language}_{region.upper()}" if region else language


def read_fence(body: str) -> dict:
    """
    One fence's settings (phetFences.settings): {"settings", "problems",
    "notes", "lines" {setting: its line in the fence}}. Every line is a
    `key: value` setting; a block may open and close with `---`.
    """
    known = set(rules("settings", "known"))
    lines = body.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    settings = {}
    problems = []
    notes = []
    given_at = {}
    for index, line in enumerate(lines):
        text = figures.js_trim(line)
        if not text or text == "---" or text.startswith("//"):
            continue
        match = _SETTING.match(text)
        if match is None or match.group(1) not in known:
            name = match.group(1) if match is not None else text
            notes.append({"reason": "unknownSetting", "blockLine": index + 1, "name": name})
            continue
        key, value = match.group(1), _unquoted(match.group(2))
        given_at[key] = index + 1
        if key == "sim":
            name = sim_name_of(value)
            if name is None:
                problems.append({"reason": "simulationNotUnderstood", "blockLine": index + 1, "value": value})
                continue
            settings["sim"] = name
        elif key == "screens":
            screens = screens_of(value)
            if screens is None:
                problems.append({"reason": "screensNotUnderstood", "blockLine": index + 1, "value": value})
                continue
            settings["screens"] = screens
        elif key == "locale":
            tag = locale_tag(value)
            if tag is None:
                problems.append({"reason": "localeNotUnderstood", "blockLine": index + 1, "value": value})
                continue
            settings["locale"] = tag
        else:
            settings[key] = value.strip()
    if "sim" not in settings and not any(problem["reason"] == "simulationNotUnderstood" for problem in problems):
        problems.append({"reason": "simulationNotNamed", "blockLine": None})
    return {"settings": settings, "problems": problems, "notes": notes, "lines": given_at}


def simulations_on_page(text: str) -> list:
    """The phet fences on one page, in order: [{"block", "line", "body", "key"}]."""
    found = []
    for block in markdown_code.fenced_blocks(text):
        if block["lang"] != LANGUAGE or block["nested"]:
            continue
        found.append({"block": len(found) + 1, "line": block["line"], "body": block["body"],
                      "key": figures.key_of(block["body"])})
    return found


def pasted_frames_on_page(text: str) -> int:
    """How many of PhET's own frames a page pastes (phetFences.pastedFrames)."""
    return len(re.findall(rules("pastedFrames", "pattern"), text, flags=re.IGNORECASE))


# ---- The language, and the address ----------------------------------------------

def resolve_locale(fence_locale, course_locale, languages) -> dict:
    """
    The language the simulation shows in (phetFences.locale): the fence's,
    else the course's; then, of the simulation's own languages, that exact
    language and region, else the language alone, else English with a note.
    Answers {"locale", "wanted", "fellBack"}.
    """
    wanted = fence_locale or locale_tag(course_locale or "") or "en"
    have = set(languages or [])
    if wanted in have:
        return {"locale": wanted, "wanted": wanted, "fellBack": False}
    language = wanted.split("_")[0]
    if language in have:
        return {"locale": language, "wanted": wanted, "fellBack": False}
    return {"locale": "en", "wanted": wanted, "fellBack": language != "en"}


def address_query(locale: str, screens) -> str:
    """
    What follows the `?` in every simulation's frame (phetFences.address):
    the fixed settings first, always, then the language, then the screens.
    Nothing a page writes reaches it but those two.
    """
    parts = list(rules("address", "fixed"))
    parts.append(f"locale={locale}")
    if screens:
        parts.append("screens=" + ",".join(str(number) for number in screens))
    return "&".join(parts)


# ---- PhET's own site ---------------------------------------------------------------

def _filled(template: str, values: dict) -> str:
    return re.sub(r"\{([A-Za-z]+)\}", lambda match: str(values.get(match.group(1), match.group(0))), template)


class PhetSite:
    """
    What a build asks phet.colorado.edu for (phetFences.download): one
    simulation's metadata, its file at the version the metadata names, its
    picture, and, only for a name PhET does not have, the list of every name
    (to offer the closest). `fetcher` is a kept_downloads.Fetcher; a test
    passes one that asks its own local server, and `base` that server.
    """

    def __init__(self, fetcher=None, base=None):
        download = rules("download")
        self.base = (base or download["base"]).rstrip("/")
        self.fetcher = fetcher or kept_downloads.Fetcher(download["hosts"])

    def _url(self, key: str, **values) -> str:
        return self.base + _filled(rules("download", key), values)

    def metadata(self, sim: str):
        """{"project", "version", "languages", "titles"} for `sim`, or None
        when PhET has no such simulation. Raises DownloadFailed (offline, or
        damaged for an answer of any other shape).

        "No such simulation" is PhET's own answer only: an `error` and no
        projects, as measured for a misspelt name (phetFences.download). An
        empty answer ({}, null, no projects, a project naming no simulation)
        is damaged, so it stops the build as every other odd answer does,
        rather than reading as a teacher's misspelling while the page
        deploys without its simulation."""
        data = self.fetcher.get(self._url("metadata", sim=sim))
        try:
            answer = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            raise kept_downloads.DownloadFailed("damaged", "PhET's answer was not what was expected") from None
        if not isinstance(answer, dict):
            raise kept_downloads.DownloadFailed("damaged", "PhET's answer was not what was expected")
        if not answer.get("projects"):
            if answer.get("error"):
                return None
            raise kept_downloads.DownloadFailed("damaged", "PhET's answer was not what was expected")
        projects = answer["projects"]
        if not isinstance(projects, list):
            raise kept_downloads.DownloadFailed("damaged", "PhET's answer was not what was expected")
        for project in projects:
            if not isinstance(project, dict) or not isinstance(project.get("simulations") or [], list):
                raise kept_downloads.DownloadFailed("damaged", "PhET's answer was not what was expected")
            for simulation in (project.get("simulations") or []):
                if not isinstance(simulation, dict):
                    raise kept_downloads.DownloadFailed("damaged", "PhET's answer was not what was expected")
                if simulation.get("name") != sim:
                    continue
                version_about = project.get("version")
                version = str(version_about.get("string") or "") if isinstance(version_about, dict) else ""
                project_name = str(project.get("name") or "")
                if not kept_downloads.safe_name(version) or not re.match(r"^html/[a-z0-9-]+$", project_name):
                    raise kept_downloads.DownloadFailed("damaged", "PhET's answer named no version")
                localized = simulation.get("localizedSimulations") or {}
                if not isinstance(localized, dict):
                    localized = {}
                titles = {}
                for locale, about in localized.items():
                    if isinstance(about, dict) and about.get("title"):
                        titles[str(locale)] = str(about["title"])
                return {"project": project_name, "version": version, "languages": sorted(titles),
                        "titles": titles}
        raise kept_downloads.DownloadFailed("damaged", "PhET's answer named no such simulation")

    def all_names(self) -> list:
        try:
            answer = json.loads(self.fetcher.get(self._url("allNames")).decode("utf-8"))
        except (kept_downloads.DownloadFailed, UnicodeDecodeError, ValueError):
            return []
        names = []
        projects = answer.get("projects") if isinstance(answer, dict) else None
        for project in projects if isinstance(projects, list) else []:
            simulations = project.get("simulations") if isinstance(project, dict) else None
            for simulation in simulations if isinstance(simulations, list) else []:
                if isinstance(simulation, dict) and simulation.get("name"):
                    names.append(str(simulation["name"]))
        return sorted(set(names))

    def simulation(self, project: str, version: str, sim: str) -> bytes:
        return self.fetcher.get(self._url("simulation", project=project, version=version, sim=sim))

    def screenshot(self, project: str, version: str, sim: str):
        """The picture, or None when PhET has none at that address."""
        try:
            return self.fetcher.get(self._url("screenshot", project=project, version=version, sim=sim))
        except kept_downloads.DownloadFailed as failed:
            if failed.reason == "notFound":
                return None
            raise


# ---- Checking a download ---------------------------------------------------------

def cleaned(data: bytes) -> bytes:
    """
    The simulation as PhET published it: what PhET's servers add on the way
    is taken out before anything is checked or kept
    (phetFences.download.removedOnTheWay; measured 2026-11-13: a request
    that says it wants HTML is sent the file with a Cloudflare Web Analytics
    script added, which would make every student's browser ask
    static.cloudflareinsights.com). Taking it out gives the file byte for byte
    as the same version is answered without it.
    """
    for pattern in rules("download", "removedOnTheWay", "patterns"):
        data = re.sub(pattern.encode("utf-8"), b"", data)
    return data


_OUTSIDE_SCRIPT = re.compile(rb"<script\b[^>]*\bsrc\s*=\s*[\"']?\s*(?:https?:)?//", re.IGNORECASE)


def simulation_problem(data: bytes):
    """None when `data` is a PhET simulation as phetFences.download.checks
    asks, else what is wrong with it, in a few words."""
    checks = rules("download", "checks")
    if len(data) > int(checks["largestMegabytes"]) * 1024 * 1024:
        return "too large"
    if not data[:200].lstrip().lower().startswith(b"<!doctype html"):
        return "not a web page"
    for needed in checks["mustContain"]:
        if needed.encode("utf-8") not in data:
            return f"no {needed!r}"
    if _OUTSIDE_SCRIPT.search(data):
        return "a script from another site"
    return None


def png_size(data):
    if data and len(data) >= 24 and data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
        return struct.unpack(">II", data[16:24])
    return None


def _megabytes_for_button(gzipped: int) -> str:
    value = round(gzipped / 1_000_000, 1)
    if value < 0.1:
        value = 0.1
    return str(int(value)) if value == int(value) else str(value)


# ---- Which pages count -----------------------------------------------------------

def pages_students_see(content_root, is_hidden, place_of, source_of, skip=None) -> list:
    """The pages students can see that could hold a simulation, and the
    pages that paste PhET's own frame, for the note: every page whose text
    holds the language's word at all (phetFences.fences.rule). The scan is a
    plain substring test, so it looks for the word alone rather than for a
    fence opener: CommonMark lets spaces stand between the fence and its
    language (``` phet, ~~~ phet), the site reads those as simulations, and
    an opener-shaped scan skipped them, so the page deployed with no
    simulation and nothing said so. simulations_on_page then reads each page
    exactly; a page that only mentions the word costs one more read."""
    return figures.pages_students_see(content_root, is_hidden, place_of, source_of,
                                      skip=skip, must_contain=LANGUAGE)


# ---- The words ---------------------------------------------------------------------

def reason_sentence(problem: dict, said: dict) -> str:
    reasons = said["reasons"]
    reason = problem.get("reason") or ""
    if reason == "simulationNotFound" and problem.get("near"):
        reason = "simulationNotFoundNear"
    text = reasons.get(reason) or reasons["simulationNotNamed"]
    return site_health.filled(text, {
        "name": problem.get("name") or "",
        "value": problem.get("value") or "",
        "sim": problem.get("sim") or "",
        "near": problem.get("near") or "",
        "language": problem.get("language") or "",
        "count": str(problem.get("count") or ""),
    })


def error_line(problem: dict, said: dict, kind="error") -> str:
    """`plantoir: error: Unit 3/Gases.md: phet block 1, line 12: ...`."""
    where = f"{problem['page']}.md"
    if problem.get("block") is not None:
        where += f": phet block {problem['block']}"
    if problem.get("line") is not None:
        where += f", line {problem['line']}"
    return f"plantoir: {kind}: {where}: {reason_sentence(problem, said)}"


def health_finding_facts(outcome: dict) -> list:
    """The `phet_problems` fact for site_health: one entry per simulation."""
    return list(outcome.get("problems") or [])


# ---- The whole pass ---------------------------------------------------------------

def _file_line_of(found: dict, source_found: list):
    for candidate in source_found:
        if candidate["key"] == found["key"] and candidate["block"] == found["block"]:
            return candidate["line"]
    for candidate in source_found:
        if candidate["key"] == found["key"]:
            return candidate["line"]
    return None


def _located(found: dict, problem: dict) -> dict:
    line = None
    if found.get("fileLine") is not None:
        line = found["fileLine"]
        if problem.get("blockLine") is not None:
            line += problem["blockLine"]
    located = {"page": found["place"], "block": found["block"], "key": found.get("key"), "line": line,
               "blockLine": problem.get("blockLine"), "reason": problem.get("reason")}
    for name in ("name", "value", "sim", "near", "language"):
        if problem.get(name) is not None:
            located[name] = problem[name]
    return located


def page_key(content_path: str) -> str:
    return unicodedata.normalize("NFC", content_path)


def _write_if_changed(path: Path, data: bytes) -> None:
    if path.is_file():
        try:
            if path.stat().st_size == len(data) and path.read_bytes() == data:
                return
        except OSError:
            pass
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def _about_text(sim: str, entry: dict) -> str:
    """static/phet/<sim>/ABOUT.txt: the credit and licence PhET's terms ask
    for, carried with the copy (phetFences.attribution)."""
    attribution = rules("attribution")
    return "\n".join([
        f"{entry['about'].get('titles', {}).get('en') or sim} {entry['version']}",
        "",
        attribution["sentence"],
        "",
        f"Licence: {attribution['licenceName']}, {attribution['licenceUrl']}",
        f"Terms: {attribution['termsUrl']}",
        f"Downloaded from {entry['about'].get('from') or attribution['siteUrl']}"
        f" on {entry['about'].get('downloadedOn') or ''} and carried unchanged.",
        "",
    ])


def _write_site_files(output_dir, manifest, simulations: dict) -> None:
    """quartz/plantoir-phet/manifest.json and quartz/static/phet/<sim>/ -
    or neither, when no simulation is shown, so the transformer leaves every
    page exactly as it was and the site carries none."""
    workspace = Path(output_dir) / "quartz" / WORKSPACE
    folder = Path(output_dir) / "quartz" / "static" / SITE_FOLDER
    if manifest is None:
        for gone in (workspace, folder):
            if gone.exists():
                shutil.rmtree(gone, ignore_errors=True)
        return
    _write_if_changed(workspace / "manifest.json",
                      (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=1) + "\n").encode("utf-8"))
    for sim, entry in simulations.items():
        target = folder / sim
        _write_if_changed(target / "index.html", (entry["folder"] / SIMULATION_FILE).read_bytes())
        picture = entry["folder"] / SCREENSHOT_FILE
        if SCREENSHOT_FILE in entry["files"]:
            _write_if_changed(target / SCREENSHOT_FILE, picture.read_bytes())
        elif (target / SCREENSHOT_FILE).exists():
            (target / SCREENSHOT_FILE).unlink()
        _write_if_changed(target / "ABOUT.txt", _about_text(sim, entry).encode("utf-8"))
    for existing in list(folder.iterdir()):
        if existing.name not in simulations:
            shutil.rmtree(existing, ignore_errors=True) if existing.is_dir() else existing.unlink()


def _download(sim: str, site: PhetSite, store) -> dict:
    """
    One simulation downloaded, checked and kept. Answers {"ok": True,
    "entry", "bytes"} or {"ok": False, "reason"}: notFound (PhET has no such
    simulation), offline or damaged.
    """
    try:
        described = site.metadata(sim)
        if described is None:
            return {"ok": False, "reason": "notFound"}
        data = cleaned(site.simulation(described["project"], described["version"], sim))
        picture = site.screenshot(described["project"], described["version"], sim)
    except kept_downloads.DownloadFailed as failed:
        # A simulation the metadata names but whose file is not there is
        # PhET's answer being wrong, not a misspelt name: damaged.
        return {"ok": False, "reason": "damaged" if failed.reason in ("notFound", "damaged") else "offline"}
    if simulation_problem(data) is not None:
        return {"ok": False, "reason": "damaged"}
    files = {SIMULATION_FILE: data}
    if picture is not None and png_size(picture) is not None \
            and len(picture) <= int(rules("download", "checks", "largestPictureMegabytes")) * 1024 * 1024:
        files[SCREENSHOT_FILE] = picture
    from_url = site._url("simulation", project=described["project"], version=described["version"], sim=sim)
    about = {"project": described["project"], "languages": described["languages"],
             "titles": described["titles"], "gzippedBytes": len(gzip.compress(data, 9)),
             "from": from_url, "downloadedOn": time.strftime("%Y-%m-%d", time.gmtime())}
    entry = store.put(sim, described["version"], files, about=about, sources={SIMULATION_FILE: from_url})
    if entry is None:
        # Nowhere to keep it: this build uses what it downloaded, once.
        return {"ok": False, "reason": "notKept", "files": files, "about": about,
                "version": described["version"]}
    return {"ok": True, "entry": entry, "bytes": sum(len(part) for part in files.values())}


def prepare(pages: list, output_dir, kept_root, course_locale="en-US", course="", section=None,
            site=None, printer=print, now=None) -> dict:
    """
    Every phet fence on the pages students can see, read, its simulation
    found among the kept copies or downloaded now, and handed to the site.

    `pages` is figures.pages_students_see's shape. `kept_root` is
    kept_downloads.root_for's answer. Answers {"counts": {"phet": pages with
    a simulation shown}, "problems", "notes", "simulations": n, "shown": n,
    "downloaded": [sim], "fromBefore": [sim], "bytes": n, "seconds": n,
    "stop": None or {"reason": offline|damaged, "missing": [{"item",
    "page"}]}}. When `stop` is set nothing is written to the site.
    """
    said = words()
    store = kept_downloads.Store(kept_root, KIND)
    store.prune(now)
    outcome = {"counts": {KIND: 0}, "problems": [], "notes": [], "simulations": 0, "shown": 0,
               "downloaded": [], "fromBefore": [], "bytes": 0, "seconds": 0.0, "stop": None}
    entries = {}
    simulations = {}
    pages_shown = set()
    answers = {}
    missing = []
    stop_reason = None
    started = time.monotonic()
    phet_site = site

    for page in pages:
        pasted = pasted_frames_on_page(page["text"])
        if pasted:
            outcome["notes"].append({"page": page["place"], "block": None, "line": None,
                                     "reason": "pastedPhetFrame", "count": pasted})
        found_here = simulations_on_page(page["text"])
        if not found_here:
            continue
        source_found = simulations_on_page(page["source"]) if page.get("source") else []
        for found in found_here:
            outcome["simulations"] += 1
            found["place"] = page["place"]
            found["fileLine"] = _file_line_of(found, source_found)
            read = read_fence(found["body"])
            for note in read["notes"]:
                outcome["notes"].append(_located(found, note))
            if read["problems"]:
                outcome["problems"].append(_located(found, read["problems"][0]))
                continue
            settings = read["settings"]
            sim = settings["sim"]
            if sim not in answers:
                kept = store.get(sim)
                if kept is not None:
                    answers[sim] = {"ok": True, "entry": kept, "fresh": False}
                else:
                    if phet_site is None:
                        phet_site = PhetSite()
                    answers[sim] = _download(sim, phet_site, store)
                    answers[sim]["fresh"] = True
            answer = answers[sim]
            if not answer["ok"] and answer["reason"] == "notFound":
                # PhET's full list of names, asked once per build and only
                # for a name it does not have (phetFences.download).
                if "\0names" not in answers:
                    answers["\0names"] = phet_site.all_names() if phet_site else []
                near = difflib.get_close_matches(sim, answers["\0names"], n=3, cutoff=0.6)
                outcome["problems"].append(_located(found, {
                    "reason": "simulationNotFound", "sim": sim, "blockLine": read["lines"].get("sim"),
                    "near": ", ".join(near)}))
                continue
            if not answer["ok"] and answer["reason"] == "notKept":
                answer = {"ok": True, "fresh": True, "entry": _unkept_entry(sim, answer, output_dir)}
                answers[sim] = answer
            if not answer["ok"]:
                stop_reason = "damaged" if answer["reason"] == "damaged" or stop_reason == "damaged" else "offline"
                missing.append({"item": sim, "page": page["place"]})
                continue
            entry = answer["entry"]
            about = entry["about"]
            language = resolve_locale(settings.get("locale"), course_locale, about.get("languages"))
            if language["fellBack"]:
                outcome["notes"].append(_located(found, {"reason": "notInThisLanguage", "sim": sim,
                                                         "language": language["wanted"],
                                                         "blockLine": read["lines"].get("locale")}))
            if "alt" not in settings:
                outcome["notes"].append(_located(found, {"reason": "missingAlt", "blockLine": None}))
            titles = about.get("titles") or {}
            title = titles.get(language["locale"]) or titles.get("en") or sim
            picture = None
            if SCREENSHOT_FILE in entry["files"]:
                size = png_size((entry["folder"] / SCREENSHOT_FILE).read_bytes())
                picture = {"path": f"static/{SITE_FOLDER}/{sim}/{SCREENSHOT_FILE}",
                           "width": size[0] if size else None, "height": size[1] if size else None}
            entries.setdefault(page_key(page["path"]), {})[found["key"]] = {
                "ok": True,
                "sim": sim,
                "title": title,
                "alt": settings.get("alt") or site_health.filled(said["site"]["untitled"], {"title": title}),
                "locale": language["locale"],
                "query": address_query(language["locale"], settings.get("screens")),
                "folder": f"static/{SITE_FOLDER}/{sim}/",
                "picture": picture,
                "size": site_health.filled(said["site"]["size"], {
                    "megabytes": _megabytes_for_button(int(about.get("gzippedBytes") or 0))}),
                "version": entry["version"],
            }
            simulations[sim] = entry
            pages_shown.add(page["path"])
            outcome["shown"] += 1
            if answer.get("fresh"):
                if sim not in outcome["downloaded"]:
                    outcome["downloaded"].append(sim)
                    outcome["bytes"] += sum(int(part["bytes"]) for part in entry["files"].values())
            elif sim not in outcome["fromBefore"]:
                outcome["fromBefore"].append(sim)

    outcome["seconds"] = round(time.monotonic() - started, 1)
    if missing:
        outcome["stop"] = {"reason": stop_reason, "missing": missing}
        return outcome

    manifest = None
    if entries:
        manifest = {"version": 1, "words": said["site"], "attribution": rules("attribution"), "pages": entries}
    _write_site_files(output_dir, manifest, simulations)
    outcome["counts"][KIND] = len(pages_shown)
    if outcome["simulations"]:
        printer(f"🔬 {outcome['shown']} of {outcome['simulations']} science simulation"
                f"{'s' if outcome['simulations'] != 1 else ''} ready to open on the site"
                f" ({len(outcome['downloaded'])} downloaded now, {len(outcome['fromBefore'])} kept from before).")
    for note in outcome["notes"]:
        printer(error_line(note, said, kind="note"))
    for problem in outcome["problems"]:
        printer(error_line(problem, said))
    return outcome


def _unkept_entry(sim: str, answer: dict, output_dir) -> dict:
    """A download that could not be kept (nowhere to keep it), held for this
    build only in the site's own workspace."""
    folder = Path(output_dir) / "quartz" / WORKSPACE / "unkept" / sim
    folder.mkdir(parents=True, exist_ok=True)
    files = {}
    for name, data in answer["files"].items():
        (folder / name).write_bytes(data)
        files[name] = {"sha256": kept_downloads.sha256_of(data), "bytes": len(data)}
    return {"name": sim, "version": answer["version"], "folder": folder, "files": files, "about": answer["about"]}


def places_after_a_failed_pass(list_pages, content_root):
    """
    Where the pages students can see use a simulation, for the stop a build
    makes when the pass ITSELF failed (keptDownloads.stop, notReady;
    phetFences.stop.passFails): [{"item", "page"}] in the order the pages
    are read, [] when no page shows one (the build carries on), or None when
    even that cannot be told (the build stops, naming nothing). Never
    raises. `list_pages` is a callable answering pages_students_see's shape;
    when it fails, every Markdown file under `content_root` is read as text,
    so a fault in the visibility rule still never lets a promised
    simulation go missing in silence.
    """
    try:
        pages = list_pages()
    except Exception:
        pages = None
    if pages is None:
        try:
            root = Path(content_root)
            pages = []
            for path in sorted(root.rglob("*.md")):
                text = path.read_text(encoding="utf-8", errors="replace")
                place = path.relative_to(root).with_suffix("").as_posix()
                pages.append({"place": place, "text": text})
        except Exception:
            return None
    try:
        places = []
        for page in pages:
            for found in simulations_on_page(page["text"]):
                sim = read_fence(found["body"])["settings"].get("sim")
                if sim:
                    places.append({"item": sim, "page": page["place"]})
        return places
    except Exception:
        return None


def stop_lines(outcome: dict, course: str, section) -> list:
    """What build_site prints when `prepare` answered a stop: the lines, then
    the marker for the app's trail."""
    stop = outcome["stop"]
    lines = kept_downloads.stop_lines(KIND, course, section, stop["missing"], stop["reason"])
    distinct = []
    for item in stop["missing"]:
        if item["item"] not in distinct:
            distinct.append(item["item"])
    lines.append(kept_downloads.marker_line(KIND, course, section,
                                            failed={"count": len(distinct), "reason": stop["reason"]}))
    return lines


def downloaded_line(outcome: dict, course: str, section):
    """The marker for the trail when this build downloaded anything, else None."""
    if not outcome.get("downloaded"):
        return None
    return kept_downloads.marker_line(KIND, course, section, downloaded={
        "count": len(outcome["downloaded"]), "bytes": outcome["bytes"], "seconds": outcome["seconds"]})

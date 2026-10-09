#!/usr/bin/env python3
"""
Diagrams and graphs drawn from a page's own fences (#485 E1).

A teacher writes ```tikz (a LaTeX TikZ picture, as the Obsidian TikZJax
plugin draws it) or ```functionplot (a graph of y = f(x), in the syntax of
the obsidian-functionplot plugin 1.2.1) on a page. This module is the build's
half: it finds those fences on the pages students can see, has every TikZ
picture DRAWN here, at build time, by the same TeX engine the Obsidian plugin
carries (node-tikzjax 1.0.5 - its tex.wasm, core.dump and all 212 TeX files
are byte-identical to the plugin's, plan M1), checks every graph with the
evaluator the site will draw it with (function-plot 1.25.4), and hands the
results to the site's transformer (support/quartz/plugins/transformers/
plantoirFigures.ts) through `quartz/plantoir-figures/`.

**Python prepares and Quartz places.** Not inside Quartz, because a failure
must reach the teacher as a folder problem (siteHealth -> figuresCouldNotBeDrawn)
and a preview build never returns; the cache and the clock are Python's; and
this file runs on Windows too, where every `scripts/test_*.py` is run.

What a site carries is decided here as well (the #454 gate):
* a site with a graph on a page students can see carries function-plot
  (`static/function-plot/`, 202,953 bytes) - `page_features.GATED_ASSETS`;
* a site with a TikZ diagram carries ONLY the Computer Modern faces its
  diagrams use (`static/tikz/`, with fonts.css and the BaKoMa LICENCE);
* a site with neither carries neither, and its pages are byte for byte what
  they were before E1 (verify.sh checks it).

Every rule a case can pin is in contracts/shared-rules.json -> figureFences,
and scripts/test_figures.py runs them. The reasons are in
documentation/05-build-pipeline.md -> "Diagrams and graphs".
"""

import hashlib
import json
import os
import queue
import shutil
import subprocess
import threading
import time
from pathlib import Path

import contracts
import markdown_code
import site_health
import toolchain_paths

ENGINES = ("tikz", "functionplot")
# The engine folder a graph's site carries, under VENDOR_DIR and under the
# site's quartz/static (the #454 convention: the same name in both).
GRAPH_ENGINE = "function-plot"
# The TikZ engine's folder under VENDOR_DIR. NEVER copied into a site (39 MB,
# 5,445 files) - which is why it is not called `tikz`, the name of the site's
# fonts folder: one slip into GATED_ASSETS would otherwise ship it (review S8).
TIKZ_ENGINE = "tikz-engine"
FONTS_FOLDER = "tikz"
WORKSPACE = "plantoir-figures"
CACHE_FOLDER = ".figure-cache"
# Seconds a diagram may take once the engine is up (25 times the slowest
# measured, pgfplots at 842 ms), and seconds the engine may take to start
# (measured 0.5 to 0.8 s; Windows' first start, against 5,445 files and an
# antivirus, is unmeasured - review S5).
JOB_SECONDS = 20
START_SECONDS = 120
# A cached figure nobody has used for this long is removed.
PRUNE_DAYS = 90

# JavaScript's String.prototype.trim() set: WhiteSpace and LineTerminator.
# Python's str.strip() is a DIFFERENT set (it strips U+001C-U+001F and U+0085,
# and keeps U+FEFF), and the site's transformer trims with JavaScript, so the
# set is spelt out (review S4).
_JS_WHITESPACE = (
    "\u0009\u000a\u000b\u000c\u000d   "
    "           "
    "    　﻿"
)


def js_trim(text: str) -> str:
    """`text.trim()` as JavaScript does it."""
    return text.strip(_JS_WHITESPACE)


def tidy_lines(body: str):
    """
    The TikZ plugin's tidying (obsidian-tikzjax 0.5.2, tidyTikzSource): take
    out every "&nbsp;", trim each line, drop the empty ones. Split on "\\n"
    ONLY - never `splitlines()`, which also splits on characters JavaScript
    does not (review S4). Answers (lines, from), `from[i]` being the 1-based
    line of the fence that tidied line i+1 came from.
    """
    lines = []
    came_from = []
    for index, line in enumerate(body.replace("&nbsp;", "").split("\n")):
        trimmed = js_trim(line)
        if trimmed:
            lines.append(trimmed)
            came_from.append(index + 1)
    return lines, came_from


def tidy(body: str) -> str:
    return "\n".join(tidy_lines(body)[0])


def key_of(body: str) -> str:
    """The name a figure is cached and looked up by: SHA-256 of the tidied
    fence (figureRules.keyOf). The engine is in the cache FOLDER's name."""
    return hashlib.sha256(tidy(body).encode("utf-8")).hexdigest()


def tikz_alt(body: str):
    """`% alt: ...` on the first non-empty line, or None (figureRules.altOf)."""
    lines, _ = tidy_lines(body)
    if not lines:
        return None
    first = lines[0]
    if not first.startswith("%"):
        return None
    rest = first[1:].lstrip(" \t")
    if not rest.startswith("alt"):
        return None
    rest = rest[3:].lstrip(" \t")
    if not rest.startswith(":"):
        return None
    alt = js_trim(rest[1:])
    return alt or None


def figures_on_page(text: str) -> list:
    """
    The figure fences on one page, in order: [{"engine", "block" (1-based,
    per engine), "body", "line" (the opening fence's line), "key"}]. The
    language is the info string's first word, exactly - `TikZ` and
    `function-plot` are not figures (figureFences.fences).
    """
    found = []
    counts = {engine: 0 for engine in ENGINES}
    for block in markdown_code.fenced_blocks(text):
        engine = block["lang"]
        if engine not in ENGINES:
            continue
        counts[engine] += 1
        found.append({
            "engine": engine,
            "block": counts[engine],
            "body": block["body"],
            "line": block["line"],
            "key": key_of(block["body"]),
        })
    return found


def words() -> dict:
    return contracts.section("shared-rules", "figureFences", "words")


def _number(value) -> str:
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    return str(value)


def describe_plot(plot: dict, said: dict) -> str:
    """The description a graph without `alt:` is given (words.describePlot)."""
    lines = list(plot.get("lines") or [])
    if len(lines) <= 1:
        functions = "".join(lines)
    else:
        functions = ", ".join(lines[:-1]) + said["describePlotAnd"] + lines[-1]
    bounds = plot.get("bounds") or [-10, 10, -10, 10]
    return site_health.filled(said["describePlot"], {
        "functions": functions, "xMin": _number(bounds[0]), "xMax": _number(bounds[1]),
    })


# ---- The engine's identity and the cache ------------------------------------

def engine_files(support_dir=None, vendor_dir=None) -> list:
    """What changes a drawing or a check when it changes (review S3): the
    lockfile (node-tikzjax and everything under it, svgo and jsdom among
    them), the helper, the rules it shares with the site, and function-plot."""
    support = Path(support_dir) if support_dir is not None else toolchain_paths.SUPPORT_DIR
    vendor = Path(vendor_dir) if vendor_dir is not None else toolchain_paths.VENDOR_DIR
    return [
        support / "figures" / "package-lock.json",
        support / "figures" / "plantoir-figures.mjs",
        support / "quartz" / "plugins" / "transformers" / "figureRules.js",
        vendor / GRAPH_ENGINE / "function-plot.js",
    ]


def engine_id(files: list) -> str:
    digest = hashlib.sha256()
    for path in files:
        digest.update(Path(path).name.encode("utf-8") + b"\0")
        try:
            digest.update(Path(path).read_bytes())
        except OSError:
            digest.update(b"(missing)")
        digest.update(b"\0")
    return digest.hexdigest()[:16]


class Cache:
    """
    `<course's builds folder>/.figure-cache/<engine id>/<engine>-<key>.json`.

    Shared by a course's sections (previewing one while publishing another is
    the supported way of working), so every write goes to a temporary file
    first and is then moved into place, and a reader treats a file that is not
    there - or not yet whole - as not cached (review S7). Outside the
    teacher's folder: the builds folder is the app's.
    """

    def __init__(self, root, engine: str):
        self.root = Path(root)
        self.folder = self.root / engine

    def _path(self, engine: str, key: str) -> Path:
        return self.folder / f"{engine}-{key}.json"

    def get(self, engine: str, key: str):
        path = self._path(engine, key)
        try:
            entry = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        try:
            os.utime(path, None)
        except OSError:
            pass
        return entry

    def put(self, engine: str, key: str, entry: dict) -> None:
        path = self._path(engine, key)
        try:
            self.folder.mkdir(parents=True, exist_ok=True)
            temporary = path.with_name(f".{path.name}.{os.getpid()}.{threading.get_ident()}.tmp")
            temporary.write_text(json.dumps(entry, ensure_ascii=False), encoding="utf-8")
            os.replace(temporary, path)
        except OSError:
            pass

    def clear(self) -> None:
        """--full-rebuild: this engine's entries, each one that can be
        removed. Never fails a build over a file another build moved."""
        try:
            entries = list(self.folder.iterdir())
        except OSError:
            return
        for entry in entries:
            try:
                entry.unlink()
            except OSError:
                pass

    def prune(self, now=None) -> None:
        """Drop every OTHER engine's folder (a new engine draws afresh) and
        this engine's entries unused for PRUNE_DAYS."""
        now = time.time() if now is None else now
        try:
            folders = list(self.root.iterdir())
        except OSError:
            return
        for folder in folders:
            if folder.name != self.folder.name and folder.is_dir():
                shutil.rmtree(folder, ignore_errors=True)
        try:
            entries = list(self.folder.iterdir())
        except OSError:
            return
        for entry in entries:
            try:
                if now - entry.stat().st_mtime > PRUNE_DAYS * 86400:
                    entry.unlink()
            except OSError:
                pass


# ---- The helper --------------------------------------------------------------

class _Helper:
    """One run of support/figures/plantoir-figures.mjs, read line by line on
    a thread so the clock works on Windows too (no `select` on a pipe)."""

    def __init__(self, command: list):
        self.process = subprocess.Popen(
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace", bufsize=1)
        self.lines = queue.Queue()
        self.complaints = []
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=self._drain, daemon=True).start()

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def _drain(self):
        for line in self.process.stderr:
            if len(self.complaints) < 20:
                self.complaints.append(line.rstrip())

    def read(self, seconds: float):
        """The next message, or None when the clock ran out or it stopped."""
        deadline = time.monotonic() + seconds
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                return None
            try:
                line = self.lines.get(timeout=left)
            except queue.Empty:
                return None
            if line is None:
                return None
            try:
                return json.loads(line)
            except ValueError:
                continue

    def send(self, message: dict) -> bool:
        try:
            self.process.stdin.write(json.dumps(message, ensure_ascii=False) + "\n")
            self.process.stdin.flush()
            return True
        except (OSError, ValueError):
            return False

    def kill(self):
        try:
            self.process.kill()
        except OSError:
            pass
        try:
            self.process.wait(timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            pass

    def close(self):
        try:
            self.process.stdin.close()
        except OSError:
            pass
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.kill()


def helper_command(output_dir) -> list:
    return [
        "node", str(toolchain_paths.SUPPORT_DIR / "figures" / "plantoir-figures.mjs"),
        "--engine", str(toolchain_paths.VENDOR_DIR / TIKZ_ENGINE),
        "--function-plot", str(toolchain_paths.VENDOR_DIR / GRAPH_ENGINE / "function-plot.js"),
        "--rules", str(Path(output_dir) / "quartz" / "plugins" / "transformers" / "figureRules.js"),
        "--quartz", str(toolchain_paths.QUARTZ_DIR),
    ]


def run_jobs(jobs: list, command: list, job_seconds=JOB_SECONDS, start_seconds=START_SECONDS,
             printer=print) -> dict:
    """
    Each job ({"id", "engine", "body"}) answered by the helper, one at a time.
    The clock starts once the engine is ready (review S5). A job that runs
    past `job_seconds` is answered {"ok": False, "reason": "tookTooLong"}, the
    helper is ended and started again for the rest; one that cannot be
    answered because the engine is missing, {"reason": "engineMissing"}.
    Neither of those two is ever cached.
    """
    results = {}
    pending = list(jobs)
    helper = None
    tikz_ready = False
    tikz_missing = False
    while pending:
        job = pending[0]
        if job["engine"] == "tikz" and tikz_missing:
            results[job["id"]] = {"ok": False, "reason": "engineMissing"}
            pending.pop(0)
            continue
        if helper is None:
            try:
                helper = _Helper(command)
            except OSError as error:
                printer(f"⚠️ Could not start drawing diagrams and graphs: {error}")
                for left in pending:
                    results[left["id"]] = {"ok": False, "reason": "engineMissing"}
                break
            ready = helper.read(start_seconds)
            if not ready or not ready.get("ready"):
                complaint = helper.complaints[0] if helper.complaints else "it did not start"
                printer(f"⚠️ Could not start drawing diagrams and graphs: {complaint}")
                helper.kill()
                helper = None
                for left in pending:
                    results[left["id"]] = {"ok": False, "reason": "engineMissing"}
                break
            tikz_ready = False
        if job["engine"] == "tikz" and not tikz_ready:
            helper.send({"load": "tikz"})
            loaded = helper.read(start_seconds)
            if not loaded or loaded.get("loaded") != "tikz":
                printer("⚠️ This copy of Plantoir cannot draw TikZ diagrams: "
                        + str((loaded or {}).get("said") or "the drawing engine did not start"))
                tikz_missing = True
                if loaded is None:
                    helper.kill()
                    helper = None
                continue
            tikz_ready = True
        helper.send({"id": job["id"], "engine": job["engine"], "body": job["body"]})
        answer = helper.read(job_seconds)
        if answer is None or answer.get("id") != job["id"]:
            helper.kill()
            helper = None
            results[job["id"]] = {"ok": False, "reason": "tookTooLong"}
            pending.pop(0)
            continue
        results[job["id"]] = answer
        pending.pop(0)
    if helper is not None:
        helper.close()
    return results


# ---- What the site carries ---------------------------------------------------

def fonts_in(svg: str) -> list:
    """The Computer Modern faces an SVG names (`font-family="cmr10"`)."""
    found = set()
    marker = 'font-family="'
    position = 0
    while True:
        start = svg.find(marker, position)
        if start < 0:
            break
        end = svg.find('"', start + len(marker))
        if end < 0:
            break
        name = svg[start + len(marker):end]
        if name and all(character.isalnum() for character in name):
            found.add(name)
        position = end + 1
    return sorted(found)


def fonts_css(families: list) -> str:
    rules = []
    for family in sorted(families):
        rules.append(f'@font-face {{ font-family: {family}; src: url("{family}.ttf") format("truetype"); '
                     f'font-display: block; }}')
    return "\n".join(rules) + "\n"


def _write_if_changed(path: Path, data: bytes) -> bool:
    if path.is_file():
        try:
            if path.read_bytes() == data:
                return False
        except OSError:
            pass
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


def install_fonts(output_dir, families: list, vendor_dir=None, printer=print) -> list:
    """
    `static/tikz/` holding exactly the faces this site's diagrams use, with
    fonts.css and the BaKoMa LICENCE - or no folder at all when no diagram is
    drawn (figureFences.siteCarriesEngine). Answers the faces installed.
    """
    vendor = Path(vendor_dir) if vendor_dir is not None else toolchain_paths.VENDOR_DIR
    target = Path(output_dir) / "quartz" / "static" / FONTS_FOLDER
    if not families:
        if target.exists():
            shutil.rmtree(target, ignore_errors=True)
        return []
    source = vendor / TIKZ_ENGINE / "node_modules" / "node-tikzjax" / "css" / "bakoma"
    installed = []
    wanted = {"fonts.css", "LICENCE"}
    try:
        for family in sorted(families):
            face = source / "ttf" / f"{family}.ttf"
            if not face.is_file():
                continue
            _write_if_changed(target / face.name, face.read_bytes())
            wanted.add(face.name)
            installed.append(family)
        _write_if_changed(target / "fonts.css", fonts_css(installed).encode("utf-8"))
        licence = source / "LICENCE"
        if licence.is_file():
            _write_if_changed(target / "LICENCE", licence.read_bytes())
        for existing in list(target.iterdir()):
            if existing.name not in wanted:
                existing.unlink()
    except OSError as error:
        printer(f"⚠️ Could not set up the diagrams' lettering: {error}")
    return installed


def _write_workspace(output_dir, manifest: dict, svgs: dict) -> None:
    """quartz/plantoir-figures/: manifest.json and one <key>.svg per drawn
    diagram, for the site's transformer to read. Gone when nothing is drawn,
    so the transformer leaves every page exactly as it was."""
    workspace = Path(output_dir) / "quartz" / WORKSPACE
    if manifest is None:
        if workspace.exists():
            shutil.rmtree(workspace, ignore_errors=True)
        return
    workspace.mkdir(parents=True, exist_ok=True)
    wanted = {"manifest.json"}
    for key, svg in svgs.items():
        name = f"{key}.svg"
        wanted.add(name)
        _write_if_changed(workspace / name, svg.encode("utf-8"))
    _write_if_changed(workspace / "manifest.json",
                      (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=1) + "\n").encode("utf-8"))
    for existing in list(workspace.iterdir()):
        if existing.name not in wanted:
            try:
                existing.unlink()
            except OSError:
                pass


# ---- Which pages count ------------------------------------------------------------

def pages_students_see(content_root, is_hidden, place_of, source_of, skip=None) -> list:
    """
    The build's copies of the pages students can see, ready for prepare():
    every `.md` under `content_root` that `is_hidden(text)` does not hold
    back (the build passes its own `_is_draft`, the gate's rule), outside any
    folder `skip(first part of its path)` says to leave out (the Media
    folder). A page that cannot be read is left out, as the site leaves it.
    """
    root = Path(content_root)
    pages = []
    for page in sorted(root.rglob("*.md")):
        try:
            parts = page.relative_to(root).parts
        except ValueError:
            continue
        if skip is not None and parts and skip(parts[0]):
            continue
        try:
            text = page.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if "```" not in text and "~~~" not in text:
            continue
        if is_hidden(text):
            continue
        source_text = None
        source = source_of(page)
        if source is not None:
            try:
                source_text = Path(source).read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                source_text = None
        pages.append({"place": place_of(page), "text": text, "source": source_text})
    return pages


# ---- The words a teacher reads -------------------------------------------------

def reason_sentence(problem: dict, said: dict) -> str:
    reasons = said["reasons"]
    reason = problem.get("reason") or "texSaid"
    text = reasons.get(reason) or reasons["texSaid"]
    return site_health.filled(text, {
        "name": problem.get("name") or "",
        "said": problem.get("said") or "",
        "seconds": JOB_SECONDS,
    })


def error_line(problem: dict, said: dict, kind="error") -> str:
    """The line an assistant reads in the build's output (issue #485 §7.5):
    `plantoir: error: Units/Similar Triangles.md: tikz block 2, line 14: ...`."""
    where = f"{problem['page']}.md: {problem['engine']} block {problem['block']}"
    if problem.get("line") is not None:
        where += f", line {problem['line']}"
    elif problem.get("blockLine") is not None:
        where += f", line {problem['blockLine']} of the block"
    return f"plantoir: {kind}: {where}: {reason_sentence(problem, said)}"


# ---- The whole pass --------------------------------------------------------------

def prepare(pages: list, output_dir, cache_root, full_rebuild=False, command=None,
            vendor_dir=None, support_dir=None, printer=print,
            job_seconds=JOB_SECONDS, start_seconds=START_SECONDS) -> dict:
    """
    Every figure on the pages students can see, drawn or checked, cached, and
    handed to the site.

    `pages` is [{"place": the page's place in the course folder without .md,
    "text": the build's copy, "source": the teacher's own copy's text or None}],
    ONLY pages students can see - the caller applies the build's visibility
    rule. Answers {"counts": {"function-plot": pages with a graph that can be
    drawn}, "fonts": [...], "problems": [...], "drawn": n, "fromBefore": n,
    "figures": n}.
    """
    said = words()
    found = []
    for page in pages:
        figures = figures_on_page(page["text"])
        if not figures:
            continue
        source_figures = figures_on_page(page["source"]) if page.get("source") else []
        for figure in figures:
            figure["place"] = page["place"]
            figure["fileLine"] = _file_line_of(figure, source_figures)
            found.append(figure)

    outcome = {"counts": {GRAPH_ENGINE: 0}, "fonts": [], "problems": [], "notes": [],
               "drawn": 0, "fromBefore": 0, "figures": len(found)}
    if not found:
        _write_workspace(output_dir, None, {})
        install_fonts(output_dir, [], vendor_dir=vendor_dir, printer=printer)
        return outcome

    cache = Cache(cache_root, engine_id(engine_files(support_dir, vendor_dir)))
    if full_rebuild:
        cache.clear()
    cache.prune()

    answers = {}
    jobs = []
    seen = set()
    for figure in found:
        handle = (figure["engine"], figure["key"])
        if handle in answers or handle in seen:
            continue
        cached = cache.get(*handle)
        if cached is not None:
            answers[handle] = cached
            outcome["fromBefore"] += 1
            continue
        seen.add(handle)
        jobs.append({"id": len(jobs) + 1, "engine": figure["engine"], "key": figure["key"],
                     "body": figure["body"]})
    if jobs:
        results = run_jobs(jobs, command if command is not None else helper_command(output_dir),
                           job_seconds=job_seconds, start_seconds=start_seconds, printer=printer)
        for job in jobs:
            answer = results.get(job["id"]) or {"ok": False, "reason": "engineMissing"}
            answer = _kept_answer(job["engine"], answer)
            answers[(job["engine"], job["key"])] = answer
            if answer.get("reason") not in ("tookTooLong", "engineMissing"):
                cache.put(job["engine"], job["key"], answer)
            if job["engine"] == "tikz" and answer.get("ok"):
                outcome["drawn"] += 1

    manifest = {"version": 1, "words": said["site"], "figures": {"tikz": {}, "functionplot": {}}}
    svgs = {}
    fonts = set()
    pages_with_a_graph = set()
    for figure in found:
        engine = figure["engine"]
        answer = answers[(engine, figure["key"])]
        entry = {"ok": bool(answer.get("ok"))}
        if engine == "tikz":
            given = tikz_alt(figure["body"])
            entry["alt"] = given or said["site"]["untitledDiagram"]
            if given is None:
                outcome["notes"].append(_located(figure, {"reason": "missingAlt"}))
            if entry["ok"]:
                svgs[figure["key"]] = answer["svg"]
                entry["svg"] = f"{figure['key']}.svg"
                fonts.update(answer.get("fonts") or fonts_in(answer["svg"]))
            else:
                outcome["problems"].append(_located(figure, answer))
        else:
            plot = answer.get("plot") or {}
            entry["plot"] = plot
            entry["alt"] = answer.get("alt") or describe_plot(plot, said["site"])
            for name in answer.get("unknown") or []:
                outcome["notes"].append(_located(figure, {"reason": "unknownSetting", "name": name}))
            if entry["ok"]:
                pages_with_a_graph.add(figure["place"])
            else:
                problems = answer.get("problems") or [{"reason": answer.get("reason") or "engineMissing"}]
                outcome["problems"].append(_located(figure, sorted(
                    problems, key=lambda problem: problem.get("blockLine") or 0)[0]))
        manifest["figures"][engine][figure["key"]] = entry

    _write_workspace(output_dir, manifest, svgs)
    outcome["fonts"] = install_fonts(output_dir, sorted(fonts), vendor_dir=vendor_dir, printer=printer)
    outcome["counts"][GRAPH_ENGINE] = len(pages_with_a_graph)

    diagrams = sum(1 for figure in found if figure["engine"] == "tikz")
    graphs = len(found) - diagrams
    printer(f"📐 Drew {outcome['drawn']} diagram{'s' if outcome['drawn'] != 1 else ''} "
            f"({outcome['fromBefore']} from before); {diagrams} diagram(s) and {graphs} graph(s) on the site.")
    for note in outcome["notes"]:
        printer(error_line(note, said, kind="note"))
    for problem in outcome["problems"]:
        printer(error_line(problem, said))
    return outcome


def _kept_answer(engine: str, answer: dict) -> dict:
    """What is cached and used: the drawing and its faces, or the reason."""
    if engine == "tikz":
        if answer.get("ok") and isinstance(answer.get("svg"), str):
            return {"ok": True, "svg": answer["svg"], "fonts": fonts_in(answer["svg"])}
        return {"ok": False, "reason": answer.get("reason") or "texSaid",
                "texLine": answer.get("texLine"), "name": answer.get("name"),
                "said": answer.get("said") or ""}
    kept = {"ok": bool(answer.get("ok")), "plot": answer.get("plot") or {},
            "alt": answer.get("alt"), "unknown": answer.get("unknown") or [],
            "problems": answer.get("problems") or []}
    if not kept["ok"] and not kept["problems"]:
        kept["problems"] = [{"reason": answer.get("reason") or "engineMissing"}]
    return kept


def _file_line_of(figure: dict, source_figures: list):
    """The opening fence's line in the TEACHER's page: the same engine's
    block holding the same figure. None when the two cannot be matched (a
    page the build wrote itself), and the problem is then placed by its
    line within the block alone."""
    for candidate in source_figures:
        if candidate["engine"] == figure["engine"] and candidate["key"] == figure["key"] \
                and candidate["block"] == figure["block"]:
            return candidate["line"]
    for candidate in source_figures:
        if candidate["engine"] == figure["engine"] and candidate["key"] == figure["key"]:
            return candidate["line"]
    return None


def _located(figure: dict, problem: dict) -> dict:
    """A problem with its page, block and line in the teacher's file."""
    block_line = problem.get("blockLine")
    if block_line is None and problem.get("texLine") is not None:
        _, came_from = tidy_lines(figure["body"])
        index = int(problem["texLine"]) - 1
        if 0 <= index < len(came_from):
            block_line = came_from[index]
    line = None
    if figure.get("fileLine") is not None:
        line = figure["fileLine"] + (block_line if block_line is not None else 0)
        if block_line is None:
            line = figure["fileLine"]
    return {
        "page": figure["place"],
        "engine": figure["engine"],
        "block": figure["block"],
        "line": line,
        "blockLine": block_line,
        "reason": problem.get("reason"),
        "name": problem.get("name"),
        "said": problem.get("said"),
    }


def health_finding_facts(outcome: dict) -> list:
    """The `figure_problems` fact for site_health: one entry per figure."""
    return list(outcome.get("problems") or [])

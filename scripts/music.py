#!/usr/bin/env python3
"""
Music from a page's own ```abc fences (#679).

A teacher writes a tune in ABC notation, the plain-text notation the
Obsidian plugin "ABC Music Notation" draws:

    ```abc
    % alt: The G major scale, one octave up, with sol-fa names under the notes.
    % sound: flute
    X:1
    T:G major scale
    M:4/4
    L:1/4
    K:G
    G A B c | d e f g |]
    w: do re mi fa sol la ti do
    ```

and students see the notation, drawn when the site is BUILT (no script is
needed to see it, and it prints), with a Play button under it that plays
the tune in the named sound with each note lit as it sounds.

This module is the build's half. It finds those fences on the pages
students can see (by the gate's own visibility rule), reads Plantoir's
`%` settings at the top of each (musicFences.settings), writes the tune as
the site will play it (a named sound becomes the `%%MIDI program` line
abcjs reads, placed after the K: line, which a page could not carry itself:
Quartz removes the text between any two `%%` on a page, musicFences.sounds),
has every tune DRAWN here by abcjs (support/music/plantoir-music.mjs, the
same engine the site plays it with), asks abcjs which sounds each tune
needs (chord symbols play on their own program), and makes sure the site
has a copy of each of those sounds: the copy kept on this computer, or one
downloaded now from the pinned commit of the sound set and kept
(scripts/kept_downloads.py, keptDownloads; Russell's ruling of 2026-11-13
on #679). It writes the engine, its licence and the sounds into
`quartz/static/abcjs/` and a manifest into `quartz/plantoir-music/` for the
site's transformer (support/quartz/plugins/transformers/plantoirMusic.ts).

**A build with no internet and a sound not downloaded before STOPS**
(keptDownloads.stop, musicFences.stop), exactly as #674's simulations do:
a site that says it built with a Play button that plays nothing is the
fault this prevents. A misspelt sound, a tune abcjs reads with a problem,
or a `%%` line is a folder problem instead (siteHealth -> musicNotRight).

Every rule a case can pin is in contracts/shared-rules.json ->
musicFences, run by scripts/test_music.py. The reasons, what was measured
and what was rejected are in documentation/05-build-pipeline.md ->
"Music notation".
"""

import base64
import difflib
import json
import re
import shutil
import time
import unicodedata
from pathlib import Path

import contracts
import figures
import kept_downloads
import markdown_code
import site_health
import toolchain_paths

KIND = "sounds"
ENGINE = "music"
WORKSPACE = "plantoir-music"
SITE_FOLDER = "abcjs"
SOUNDS_FOLDER = "sounds"
# The engine's folder under VENDOR_DIR (the image's /opt/vendor/music-engine,
# Windows' runtime\vendor\music-engine): abcjs and linkedom, from
# support/music's lockfile. Its abcjs file is what a site carries.
ENGINE_FOLDER = "music-engine"
ENGINE_FILE = "abcjs-basic-min.js"
# Chord symbols play in the tune's own sound unless `% chords:` names
# another (plan review item 3, built as recommended; a question for Russell
# in the closing note). False gives abcjs's own default, piano for every
# chord, which is a second download for most tunes and a sound the teacher
# did not name. One constant, so the choice is cheap to turn; the contract's
# musicFences.sounds.emitted cases pin the True behaviour.
CHORDS_FOLLOW_THE_TUNE = True
# Seconds a tune may take once the helper is up (the slowest measured was
# 17 ms, the first tune of a run), and seconds the helper may take to start.
JOB_SECONDS = 20
START_SECONDS = 120


def rules(*keys):
    return contracts.section("shared-rules", "musicFences", *keys)


def words() -> dict:
    return rules("words")


def sound_pin() -> dict:
    """contracts/toolchain.json -> pins -> fluidR3Sounds."""
    for pin in contracts.load("toolchain")["pins"]:
        if pin.get("pin") == "fluidR3Sounds":
            return pin
    raise KeyError("fluidR3Sounds")


# ---- Finding the tunes --------------------------------------------------------

def tunes_on_page(text: str) -> list:
    """The music fences on one page, in order: [{"block", "line", "body",
    "key", "lang"}]. The language is the info string's first word, exactly
    (musicFences.fences): ```abc and ```music-abc, the two names the
    Obsidian plugin registers; ```ABC is not a tune."""
    languages = rules("fences", "languages")
    found = []
    for block in markdown_code.fenced_blocks(text):
        if block["lang"] not in languages or block["nested"]:
            continue
        found.append({"block": len(found) + 1, "line": block["line"], "body": block["body"],
                      "key": figures.key_of(block["body"]), "lang": block["lang"]})
    return found


def pages_students_see(content_root, is_hidden, place_of, source_of, skip=None) -> list:
    """The pages students can see that could hold a tune: every page whose
    text holds `abc` at all, so a fence written with spaces before its
    language (``` abc) is found as the site finds it (#674's lesson)."""
    return figures.pages_students_see(content_root, is_hidden, place_of, source_of,
                                      skip=skip, must_contain="abc")


# ---- Plantoir's settings, at the top of a tune ----------------------------------

_SETTING = re.compile(r"^%(?!%)[ \t]*([A-Za-z]+)(?:[ \t]+V:[ \t]*([^\s:]+))?[ \t]*:[ \t]*(.*?)[ \t]*$")


def read_settings(body: str) -> dict:
    """
    Plantoir's settings (musicFences.settings): `%` comment lines at the TOP
    of the fence, before its first line of ABC, which ABC itself and the
    Obsidian plugin read as comments. Answers {"alt", "play", "sound",
    "voiceSounds" {voice: value}, "chords", "lines" {setting: fence line},
    "notes": [...]}. A known setting written after the tune has begun is a
    comment, and a note says so; an unknown word after `%` is the teacher's
    own comment, and nothing is said.
    """
    known = rules("settings", "known")
    settings = {"alt": None, "play": True, "sound": None, "voiceSounds": {}, "chords": None,
                "lines": {}, "notes": []}
    started = False
    for index, line in enumerate(body.split("\n")):
        text = figures.js_trim(line)
        if not text:
            continue
        match = _SETTING.match(text)
        if match is None or match.group(1).lower() not in known:
            if not text.startswith("%"):
                started = True
            continue
        key, voice, value = match.group(1).lower(), match.group(2), match.group(3)
        if started:
            settings["notes"].append({"reason": "settingAfterTheTune", "blockLine": index + 1, "name": key})
            continue
        if key == "alt":
            settings["alt"] = value or None
        elif key == "play":
            settings["play"] = value.strip().lower() not in rules("settings", "playOff")
        elif key == "sound" and voice:
            settings["voiceSounds"][voice] = value
            settings["lines"][f"sound V:{voice}"] = index + 1
            continue
        elif key == "sound":
            settings["sound"] = value
        elif key == "chords":
            settings["chords"] = value
        settings["lines"][key] = index + 1
    return settings


# ---- Sounds ---------------------------------------------------------------------

def _plain(name: str) -> str:
    return re.sub(r"[\s_\-]+", " ", str(name or "").strip().lower())


def sound_names() -> list:
    """The 128 General MIDI sounds by program (0-based), as abcjs names
    them (musicFences.sounds.names)."""
    return list(rules("sounds", "names"))


def program_of(value: str):
    """
    The 0-based program a teacher's sound names, or None
    (musicFences.sounds.cases): a General MIDI name in plain words (spaces,
    underscores and dashes alike, any case), one of the aliases, or a
    number from 1 to 128 as General MIDI lists them.
    """
    text = _plain(value)
    if not text:
        return None
    if text.isdigit():
        number = int(text)
        return number - 1 if 1 <= number <= 128 else None
    names = [_plain(name) for name in sound_names()]
    if text in names:
        return names.index(text)
    aliases = {_plain(alias): target for alias, target in rules("sounds", "aliases").items()}
    if text in aliases:
        return names.index(_plain(aliases[text]))
    return None


def nearest_sounds(value: str) -> list:
    names = [_plain(name) for name in sound_names()] + [_plain(alias) for alias in rules("sounds", "aliases")]
    return difflib.get_close_matches(_plain(value), names, n=3, cutoff=0.6)


def tune_as_played(body: str, settings: dict) -> dict:
    """
    The tune as the site draws and plays it (musicFences.sounds.emitted):
    the fence's own lines, and, when a sound is named, `%%MIDI program N`
    after the K: line that ends the header and after each V: line of the
    body (the voice's own sound, else the tune's), with `%%MIDI chordprog`
    and `%%MIDI bassprog` after the K: line so chord symbols play in the
    tune's sound, or in `% chords:`'s (plan review item 3). Answers {"abc",
    "from" [the fence line each line came from, None for an added line],
    "problems" [unknownSound]}.
    """
    problems = []

    def resolved(value, setting):
        if value is None:
            return None
        program = program_of(value)
        if program is None:
            problems.append({"reason": "unknownSound", "blockLine": settings["lines"].get(setting),
                             "value": value, "near": ", ".join(nearest_sounds(value))})
        return program

    tune_program = resolved(settings.get("sound"), "sound")
    chords_program = resolved(settings.get("chords"), "chords")
    voice_programs = {}
    for voice, value in settings.get("voiceSounds", {}).items():
        program = resolved(value, f"sound V:{voice}")
        if program is not None:
            voice_programs[voice] = program
    if chords_program is None and CHORDS_FOLLOW_THE_TUNE:
        chords_program = tune_program
    lines = body.split("\n")
    out = []
    came_from = []
    header_ended = False
    directive = rules("sounds", "directive")
    for index, line in enumerate(lines):
        out.append(line)
        came_from.append(index + 1)
        text = figures.js_trim(line)
        if not header_ended and re.match(r"^K:", text):
            header_ended = True
            added = []
            if tune_program is not None:
                added.append(directive["program"].format(program=tune_program))
            if chords_program is not None:
                added.append(directive["chordprog"].format(program=chords_program))
                added.append(directive["bassprog"].format(program=chords_program))
            for extra in added:
                out.append(extra)
                came_from.append(None)
            continue
        voice = re.match(r"^V:\s*([^\s\]]+)", text)
        if header_ended and voice:
            program = voice_programs.get(voice.group(1), tune_program)
            if program is not None:
                out.append(directive["program"].format(program=program))
                came_from.append(None)
    return {"abc": "\n".join(out), "from": came_from, "problems": problems}


# ---- What a tune is about --------------------------------------------------------

_MODES = {"maj": "major", "major": "major", "ion": "major", "m": "minor", "min": "minor", "minor": "minor",
          "aeo": "minor", "dor": "Dorian", "phr": "Phrygian", "lyd": "Lydian", "mix": "Mixolydian",
          "loc": "Locrian"}


def _header(body: str, field: str):
    for line in body.split("\n"):
        text = figures.js_trim(line)
        if text.startswith(field + ":"):
            return figures.js_trim(text[len(field) + 1:]) or None
    return None


def key_words(value):
    """`G` -> "G major", `F#m` -> "F sharp minor", `Bbdor` -> "B flat
    Dorian"; None for none, a bagpipe key or anything else
    (musicFences.describe.cases)."""
    if not value:
        return None
    match = re.match(r"^([A-Ga-g])([#b]?)\s*([A-Za-z]*)", value.split()[0])
    if match is None:
        return None
    mode_text = match.group(3).lower()
    mode = _MODES.get(mode_text) if mode_text else "major"
    if mode is None:
        mode = _MODES.get(mode_text[:3])
    if mode is None:
        return None
    accidental = {"#": " sharp", "b": " flat", "": ""}[match.group(2)]
    return f"{match.group(1).upper()}{accidental} {mode}"


def meter_words(value):
    if not value:
        return None
    text = value.split()[0]
    if text == "C":
        return "4/4"
    if text == "C|":
        return "2/2"
    return text if re.match(r"^\d+/\d+$", text) else None


def description(body: str, settings: dict) -> str:
    """`% alt:` when there is one, else a sentence made from the tune's own
    title, key and metre (musicFences.describe), which a screen reader
    reads in place of the drawing."""
    if settings.get("alt"):
        return settings["alt"]
    said = words()["site"]
    title = _header(body, "T")
    parts = []
    key = key_words(_header(body, "K"))
    if key:
        parts.append(site_health.filled(said["describeKey"], {"key": key}))
    meter = meter_words(_header(body, "M"))
    if meter:
        parts.append(site_health.filled(said["describeMeter"], {"meter": meter}))
    start = site_health.filled(said["describeTitled"], {"title": title}) if title else said["describeUntitled"]
    if not parts:
        return start + "."
    joiner = ", " if title else " "
    return start + joiner + ", ".join(parts) + "."


# ---- `%%` in a tune -----------------------------------------------------------------

def percent_percent_lines(source: str, opening_line: int) -> list:
    """
    The lines of the teacher's own file, inside the fence that opens on
    `opening_line`, that hold `%%` (musicFences.percentPercent). Quartz
    removes everything between two `%%` on a page before it reads it, inside
    fences too, so the site reads such a tune differently from Obsidian,
    which does not. Read from the RAW file, so a pair the site removed whole
    is still reported. Answers [line, ...].
    """
    lines = source.split("\n")
    if opening_line < 1 or opening_line > len(lines):
        return []
    opener = re.search(r"(`{3,}|~{3,})", lines[opening_line - 1])
    if opener is None:
        return []
    fence = opener.group(1)
    found = []
    for index in range(opening_line, len(lines)):
        content = re.sub(r"^[ \t>]*", "", lines[index]).rstrip()
        if content.startswith(fence) and content.strip(fence[0]) == "":
            break
        if "%%" in lines[index]:
            found.append(index + 1)
    return found


# ---- The words ------------------------------------------------------------------------

def reason_sentence(problem: dict, said: dict) -> str:
    reasons = said["reasons"]
    reason = problem.get("reason") or ""
    if reason == "unknownSound" and problem.get("near"):
        reason = "unknownSoundNear"
    if reason == "abcSaid" and int(problem.get("more") or 0) > 0:
        reason = "abcSaidMore"
    text = reasons.get(reason) or reasons["tuneNotDrawn"]
    return site_health.filled(text, {
        "value": problem.get("value") or "",
        "near": problem.get("near") or "",
        "said": problem.get("said") or "",
        "more": str(problem.get("more") or ""),
        "name": problem.get("name") or "",
    })


def error_line(problem: dict, said: dict, kind="error") -> str:
    """`plantoir: error: Unit 1/Scales.md: abc block 1, line 12: ...`."""
    where = f"{problem['page']}.md"
    if problem.get("block") is not None:
        where += f": abc block {problem['block']}"
    if problem.get("line") is not None:
        where += f", line {problem['line']}"
    return f"plantoir: {kind}: {where}: {reason_sentence(problem, said)}"


def health_finding_facts(outcome: dict) -> list:
    """The `music_problems` fact for site_health: one entry per problem."""
    return list(outcome.get("problems") or [])


# ---- The helper ------------------------------------------------------------------------

def engine_dir(vendor_dir=None) -> Path:
    vendor = Path(vendor_dir) if vendor_dir is not None else toolchain_paths.VENDOR_DIR
    return vendor / ENGINE_FOLDER


def helper_command(vendor_dir=None) -> list:
    return [
        "node", str(toolchain_paths.SUPPORT_DIR / "music" / "plantoir-music.mjs"),
        "--engine", str(engine_dir(vendor_dir)),
        "--options", json.dumps(rules("drawing", "options"), separators=(",", ":")),
    ]


def draw_all(jobs: list, command: list, job_seconds=JOB_SECONDS, start_seconds=START_SECONDS,
             printer=print) -> dict:
    """
    Each job ({"id", "abc"}) drawn by one run of the helper. A job the
    helper cannot answer (it is missing, it did not start, it ran out of
    time, it ended) is answered {"ok": False, "reason": "engineMissing" or
    "drawingStopped"}; the helper is started again for the rest after one
    that ran out of time or ended.
    """
    results = {}
    pending = list(jobs)
    helper = None
    while pending:
        job = pending[0]
        if helper is None:
            try:
                helper = figures._Helper(command)
            except OSError as error:
                printer(f"⚠️ Could not start drawing the tunes ({error.strerror or 'it is missing'}).")
                for left in pending:
                    results[left["id"]] = {"ok": False, "reason": "engineMissing"}
                break
            ready = helper.read(start_seconds)
            if not ready or not ready.get("ready"):
                printer("⚠️ Could not start drawing the tunes: "
                        + figures.one_line(helper.complaints[0] if helper.complaints else "it did not start"))
                helper.kill()
                for left in pending:
                    results[left["id"]] = {"ok": False, "reason": "engineMissing"}
                helper = None
                break
        if not helper.send({"id": job["id"], "abc": job["abc"]}):
            helper.kill()
            helper = None
            results[job["id"]] = {"ok": False, "reason": "drawingStopped"}
            pending.pop(0)
            continue
        answer = helper.read(job_seconds)
        if answer is None or answer.get("id") != job["id"]:
            helper.kill()
            helper = None
            results[job["id"]] = {"ok": False, "reason": "drawingStopped"}
            pending.pop(0)
            continue
        results[job["id"]] = answer
        pending.pop(0)
    if helper is not None:
        helper.close()
    return results


# ---- Sounds: kept, or downloaded -------------------------------------------------------

_NOTE = re.compile(r'^"([A-G]b?[0-9])":\s*"data:audio/mp3;base64,([A-Za-z0-9+/=]*)",?\s*$', re.MULTILINE)


def notes_of(data: bytes) -> dict:
    """A sound's one file (`<name>-mp3.js`, every note as base64) as the
    files abcjs asks for, {"A4.mp3": bytes}. Measured 2026-11-14: all 129
    decode in 0.85 s, and every note of piano and flute is byte for byte the
    sound set's own per-note file (musicFences.download.decoded)."""
    text = data.decode("ascii")
    found = {}
    for note, encoded in _NOTE.findall(text):
        found[f"{note}.mp3"] = base64.b64decode(encoded)
    if text.count("data:audio") != len(found) or not found:
        raise ValueError("not a sound file")
    return found


def _sound_file(name: str, pin: dict) -> dict:
    entry = pin["files"].get(name)
    if entry is None:
        raise KeyError(name)
    return entry


def _download_sound(name: str, pin: dict, fetcher, store) -> dict:
    """One sound downloaded, its SHA-256 checked against the pin, and kept.
    Answers {"ok": True, "entry", "bytes"} or {"ok": False, "reason":
    offline | damaged, "data"?}."""
    wanted = _sound_file(name, pin)
    url = pin["base"].rstrip("/") + "/" + wanted["file"]
    try:
        data = fetcher.get(url)
    except kept_downloads.DownloadFailed as failed:
        # A pinned file the sound set does not answer is the sound set's
        # answer being wrong, never a misspelt name (those never reach here).
        return {"ok": False, "reason": "damaged" if failed.reason == "notFound" else "offline"}
    if kept_downloads.sha256_of(data) != wanted["sha256"]:
        return {"ok": False, "reason": "damaged"}
    try:
        notes_of(data)
    except (ValueError, UnicodeDecodeError):
        return {"ok": False, "reason": "damaged"}
    file_name = wanted["file"]
    entry = store.put(name, pin["version"], {file_name: data}, about={"program": sound_names().index(name)
                                                                       if name in sound_names() else None},
                      sources={file_name: url}, expected={file_name: wanted["sha256"]})
    if entry is None:
        return {"ok": False, "reason": "notKept", "data": data}
    return {"ok": True, "entry": entry, "bytes": len(data)}


def _write_if_changed(path: Path, data: bytes) -> None:
    if path.is_file():
        try:
            if path.stat().st_size == len(data) and path.read_bytes() == data:
                return
        except OSError:
            pass
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def _readme_text(pin: dict, sounds: list) -> str:
    credit = rules("credit")
    return "\n".join([
        f"abcjs {rules('engine', 'version')}: draws and plays the tunes on this site.",
        "Licence: MIT, in LICENSE.md beside this file.",
        "",
        credit["sentence"],
        f"Licence: {credit['licenceName']}, {credit['licenceUrl']}",
        f"Source: {credit['sourceUrl']} (commit {pin['value']}), carried unchanged"
        " as the files abcjs asks for.",
        "",
        "Sounds on this site: " + (", ".join(sounds) if sounds else "none") + ".",
        "",
    ])


def _write_site_files(output_dir, manifest, sounds: dict, engine: Path, pin: dict) -> None:
    """quartz/plantoir-music/manifest.json and quartz/static/abcjs/ (the
    engine, its licence, README.txt and sounds/<name>-mp3/) - or neither,
    when no tune is shown, so the transformer leaves every page as it was and
    the site carries none of it. Only the engine and sounds when a tune has
    Play: a site whose tunes all say `% play: no` carries the drawings only."""
    workspace = Path(output_dir) / "quartz" / WORKSPACE
    folder = Path(output_dir) / "quartz" / "static" / SITE_FOLDER
    if manifest is None:
        for gone in (workspace, folder):
            if gone.exists():
                shutil.rmtree(gone, ignore_errors=True)
        return
    _write_if_changed(workspace / "manifest.json",
                      (json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=1) + "\n").encode("utf-8"))
    if not manifest["playable"]:
        if folder.exists():
            shutil.rmtree(folder, ignore_errors=True)
        return
    _write_if_changed(folder / ENGINE_FILE, (engine / "node_modules" / "abcjs" / "dist" / ENGINE_FILE).read_bytes())
    _write_if_changed(folder / "LICENSE.md", (engine / "node_modules" / "abcjs" / "LICENSE.md").read_bytes())
    _write_if_changed(folder / "README.txt", _readme_text(pin, sorted(sounds)).encode("utf-8"))
    sounds_root = folder / SOUNDS_FOLDER
    wanted = set()
    for name, notes in sounds.items():
        wanted.add(f"{name}-mp3")
        for note, data in notes.items():
            _write_if_changed(sounds_root / f"{name}-mp3" / note, data)
        for existing in list((sounds_root / f"{name}-mp3").iterdir()):
            if existing.name not in notes:
                existing.unlink()
    if sounds_root.is_dir():
        for existing in list(sounds_root.iterdir()):
            if existing.name not in wanted:
                shutil.rmtree(existing, ignore_errors=True) if existing.is_dir() else existing.unlink()
    for existing in list(folder.iterdir()):
        if existing.name not in (ENGINE_FILE, "LICENSE.md", "README.txt", SOUNDS_FOLDER):
            shutil.rmtree(existing, ignore_errors=True) if existing.is_dir() else existing.unlink()


# ---- The whole pass ------------------------------------------------------------------------

def page_key(content_path: str) -> str:
    return unicodedata.normalize("NFC", content_path)


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
    if problem.get("pageLine") is not None:
        line = problem["pageLine"]
    elif found.get("fileLine") is not None:
        line = found["fileLine"]
        if problem.get("blockLine") is not None:
            line += problem["blockLine"]
    located = {"page": found["place"], "block": found["block"], "key": found.get("key"), "line": line,
               "blockLine": problem.get("blockLine"), "reason": problem.get("reason")}
    for name in ("value", "near", "said", "more", "name"):
        if problem.get(name) not in (None, ""):
            located[name] = problem[name]
    return located


def _tune_problems(found: dict, played: dict, answer: dict) -> list:
    """What abcjs said about a tune it drew, mapped to the fence's lines: the
    first thing it said, and how many more (musicFences.lines)."""
    warnings = list(answer.get("warnings") or [])
    if not warnings:
        return []
    first = warnings[0]
    block_line = None
    if first.get("line") is not None and 1 <= int(first["line"]) <= len(played["from"]):
        block_line = played["from"][int(first["line"]) - 1]
    return [{"reason": "abcSaid", "blockLine": block_line, "said": first.get("said") or "",
             "more": len(warnings) - 1}]


def prepare(pages: list, output_dir, kept_root, course="", section=None, fetcher=None, command=None,
            vendor_dir=None, printer=print, now=None, job_seconds=JOB_SECONDS,
            start_seconds=START_SECONDS) -> dict:
    """
    Every music fence on the pages students can see, read, drawn, its sounds
    found among the kept copies or downloaded now, and handed to the site.

    `pages` is figures.pages_students_see's shape; `kept_root` is
    kept_downloads.root_for's answer. Answers {"counts": {"music": pages
    with a tune drawn}, "problems", "notes", "tunes": n, "shown": n,
    "playable": n, "sounds": [names], "downloaded": [names], "fromBefore":
    [names], "bytes", "seconds", "stop": None or {"reason", "missing"}}.
    When `stop` is set nothing is written to the site.
    """
    said = words()
    pin = sound_pin()
    store = kept_downloads.Store(kept_root, KIND)
    store.prune(now)
    outcome = {"counts": {ENGINE: 0}, "problems": [], "notes": [], "tunes": 0, "shown": 0, "playable": 0,
               "sounds": [], "downloaded": [], "fromBefore": [], "bytes": 0, "seconds": 0.0, "stop": None}
    started = time.monotonic()
    tunes = []
    for page in pages:
        found_here = tunes_on_page(page["text"])
        if not found_here:
            continue
        source_found = tunes_on_page(page["source"]) if page.get("source") else []
        for found in found_here:
            outcome["tunes"] += 1
            found["place"] = page["place"]
            found["path"] = page["path"]
            found["fileLine"] = _file_line_of(found, source_found)
            settings = read_settings(found["body"])
            for note in settings["notes"]:
                outcome["notes"].append(_located(found, note))
            if found["fileLine"] is not None:
                for line in percent_percent_lines(page.get("source") or page["text"], found["fileLine"])[:1]:
                    outcome["problems"].append(_located(found, {"reason": "percentPercentLine",
                                                                "pageLine": line}))
            played = tune_as_played(found["body"], settings)
            for problem in played["problems"]:
                outcome["problems"].append(_located(found, problem))
            found["settings"] = settings
            found["played"] = played
            found["id"] = f"{len(tunes)}"
            tunes.append(found)
    if not tunes:
        _write_site_files(output_dir, None, {}, engine_dir(vendor_dir), pin)
        return outcome

    answers = draw_all([{"id": tune["id"], "abc": tune["played"]["abc"]} for tune in tunes],
                       command or helper_command(vendor_dir), job_seconds=job_seconds,
                       start_seconds=start_seconds, printer=printer)
    names = sound_names()
    needed = []
    entries = {}
    pages_shown = set()
    for tune in tunes:
        answer = answers.get(tune["id"]) or {"ok": False, "reason": "drawingStopped"}
        if not answer.get("ok"):
            reason = answer.get("reason") or "drawingStopped"
            if reason == "nothingToDraw":
                reason = "emptyTune"
            outcome["problems"].append(_located(tune, {"reason": reason, "said": figures.one_line(
                answer.get("said") or "")}))
            continue
        for problem in _tune_problems(tune, tune["played"], answer):
            outcome["problems"].append(_located(tune, problem))
        if _header(tune["body"], "K") is None:
            outcome["problems"].append(_located(tune, {"reason": "noKey"}))
        if len(re.findall(r"(?m)^[ \t]*X:", tune["body"])) > 1:
            outcome["notes"].append(_located(tune, {"reason": "moreThanOneTune"}))
        play = bool(tune["settings"]["play"])
        programs = []
        for program in answer.get("programs") or []:
            if isinstance(program, int) and 0 <= program < len(names):
                programs.append(program)
        sounds = [names[program] for program in programs]
        if play:
            outcome["playable"] += 1
            for name in sounds:
                if name not in needed:
                    needed.append(name)
        entries.setdefault(page_key(tune["path"]), {})[tune["key"]] = {
            "ok": True,
            "html": answer["html"],
            "alt": description(tune["body"], tune["settings"]),
            "play": play,
            "abc": tune["played"]["abc"] if play else "",
            "sounds": sounds if play else [],
            "notes": int(answer.get("notes") or 0),
        }
        tune["sounds"] = sounds
        pages_shown.add(tune["path"])
        outcome["shown"] += 1

    kept_sounds = {}
    missing = []
    stop_reason = None
    the_fetcher = fetcher
    for name in needed:
        wanted = _sound_file(name, pin)
        expected = {wanted["file"]: wanted["sha256"]}
        entry = store.get(name, pin["version"], expected=expected)
        fresh = False
        data = None
        if entry is None:
            if the_fetcher is None:
                the_fetcher = kept_downloads.Fetcher(rules("download", "hosts"))
            answer = _download_sound(name, pin, the_fetcher, store)
            if answer["ok"]:
                entry = answer["entry"]
                fresh = True
            elif answer["reason"] == "notKept":
                data = answer["data"]
                fresh = True
            else:
                stop_reason = "damaged" if answer["reason"] == "damaged" or stop_reason == "damaged" else "offline"
                for tune in tunes:
                    if name in (tune.get("sounds") or []) and tune["settings"]["play"]:
                        missing.append({"item": sound_words(name), "page": tune["place"]})
                continue
        if data is None:
            data = (entry["folder"] / wanted["file"]).read_bytes()
        kept_sounds[name] = notes_of(data)
        if fresh:
            outcome["downloaded"].append(name)
            outcome["bytes"] += len(data)
        else:
            outcome["fromBefore"].append(name)
    outcome["sounds"] = list(needed)
    outcome["seconds"] = round(time.monotonic() - started, 1)
    if missing:
        outcome["stop"] = {"reason": stop_reason, "missing": missing}
        return outcome

    manifest = None
    if entries:
        manifest = {"version": 1, "words": said["site"], "credit": rules("credit"),
                    "options": rules("drawing", "options"), "playable": outcome["playable"] > 0,
                    "soundsFolder": f"static/{SITE_FOLDER}/{SOUNDS_FOLDER}/",
                    "engine": f"static/{SITE_FOLDER}/{ENGINE_FILE}", "pages": entries}
    _write_site_files(output_dir, manifest, kept_sounds, engine_dir(vendor_dir), pin)
    outcome["counts"][ENGINE] = len(pages_shown)
    printer(f"🎵 {outcome['shown']} of {outcome['tunes']} tune{'s' if outcome['tunes'] != 1 else ''} drawn"
            f" for the site, {outcome['playable']} with Play"
            f" ({len(outcome['sounds'])} sound{'s' if len(outcome['sounds']) != 1 else ''}:"
            f" {len(outcome['downloaded'])} downloaded now, {len(outcome['fromBefore'])} kept from before).")
    for note in outcome["notes"]:
        printer(error_line(note, said, kind="note"))
    for problem in outcome["problems"]:
        printer(error_line(problem, said))
    return outcome


def sound_words(name: str) -> str:
    """A sound as a teacher names it in a stop line: `flute`, `acoustic
    guitar nylon`."""
    return name.replace("_", " ")


def places_after_a_failed_pass(list_pages, content_root):
    """
    Where the pages students can see have a tune with Play, for the stop a
    build makes when the pass ITSELF failed (keptDownloads.stop, notReady;
    musicFences.stop.passFails): [{"item", "page"}], [] when no page has
    one (the build carries on), or None when even that cannot be told (the
    build stops, naming nothing). Never raises. phet.places_after_a_failed_pass's
    rule, for tunes.
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
            for found in tunes_on_page(page["text"]):
                settings = read_settings(found["body"])
                if settings["play"]:
                    # The sound it names, or the one abcjs plays without a
                    # name: what could not be made ready, as near as can be
                    # told without drawing it.
                    program = program_of(settings["sound"]) if settings["sound"] else None
                    name = sound_names()[program if program is not None else 0]
                    places.append({"item": sound_words(name), "page": page["place"]})
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

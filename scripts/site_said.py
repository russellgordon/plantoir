#!/usr/bin/env python3
"""
What the SITE said about a runnable block it showed as plain code, worded as
one folder problem (#567: contracts/shared-rules.json -> siteHealth.checks ->
runnableCodeShownAsPlainCode) - and, in the same call, about the self-check
questions it read differently from the folder check (#644:
quizzesReadDifferently, the quiz safety net's `plantoir: error:` lines).

Every other folder problem is worked out by build_site.py BEFORE Quartz runs.
This one cannot be: the site's parser and the build's fence reader disagree
about a block only once Quartz has parsed the page (codeRunnerBlocks.
siteDisagrees), and in a preview Quartz is one `quartz build --serve` process
that never hands control back to build_site.py. So the site's emitter
(support/quartz/plugins/emitters/plantoirSiteSaid.ts) runs THIS file, once per
site-building process and only when a block or a quiz disagrees, with what
the site's transformers recorded on stdin. It prints the finding with site_health's own
`announce` - the ⚠️ lines and ONE `PLANTOIR_HEALTH:` line - so both apps, the
assistant and a scheduled deploy's record read it the way they read every
other folder problem, with no new reader.

Two halves:

* `write_side_file`, called by build_site.py in the ALWAYS section, writes
  quartz/plantoir_site_said.json: which Python and which file to run, the
  course and section, where each opted-in page came from in the course
  folder (and, #644, each page the quiz check examined), and which Swift
  blocks swiftCouldNotBePrepared already names (one block, one finding). NOT plantoir_code_runner.json: the page's script
  bundles that file, and the build machine's paths must never reach students.
* `main` (run by the emitter): reads stdin, builds ONLY these two findings
  (the code's, then the quizzes') and announces them - never
  `announce_or_stay_quiet`, which would also say every check whose fact is
  missing here (the plan review's MUST 1). Each is built in its own try, so
  one that fails costs only itself.

Its own folder goes on sys.path FIRST (the #358 trap): Windows' embeddable
Python replaces sys.path with its `._pth` file, so a script run as a file
cannot count on finding its neighbours. Never raises past main: whatever goes
wrong costs the finding, never the site, and exits 0.
"""

import json
import re
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import site_health  # noqa: E402

SIDE_FILE = "plantoir_site_said.json"

# Quote markers and spaces at the start of a line, then the list markers a
# fence can sit after on its opening line (`- ```python run`, `1. > ```...`).
_LEADING_QUOTES = re.compile(r"^[ \t>]*")
_LIST_MARKERS = re.compile(r"^(?:(?:[-*+]|\d{1,9}[.)])[ \t]+[ \t>]*)*")
_OPENING = re.compile(r"^(`{3,}|~{3,})(.*)$")


def nfc(text) -> str:
    return unicodedata.normalize("NFC", str(text))


# ---- The build's half: the side file --------------------------------------------

def write_side_file(output_dir, course, section, places: dict, swift_named: list,
                    content_root, python=None, script=None) -> bool:
    """
    Write quartz/plantoir_site_said.json. `places` maps each opted-in page's
    path in the site's content (forward slashes, as Quartz names it) - and
    each page the quiz check examined (#644) - to
    {"place": its place in the course folder without .md, "source": the
    teacher's own file or None}; `swift_named` is [[place, n]] for every
    Swift block swiftCouldNotBePrepared names. Same input, same bytes;
    answers whether the file changed.
    """
    named = []
    for pair in swift_named:
        named.append([nfc(pair[0]), int(pair[1])])
    content = {
        "python": str(python if python is not None else sys.executable),
        "script": str(script if script is not None else Path(__file__).resolve()),
        "course": str(course),
        "section": section,
        "content": str(content_root),
        "places": {nfc(path): value for path, value in sorted(places.items())},
        "swiftNamed": sorted(named),
    }
    data = (json.dumps(content, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
    path = Path(output_dir) / "quartz" / SIDE_FILE
    if path.is_file() and path.read_bytes() == data:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return True


# ---- The site's half: from what the site recorded to the finding's facts ---------

def _code_line(line: str) -> str:
    return _LEADING_QUOTES.sub("", line).strip()


def opening_line(source_text: str, fence: str, code: str):
    """
    The line (from 1) in `source_text` of the ONE opening fence of `fence`
    with `run` whose following lines hold `code`, each compared with quote
    markers and the spaces at either end taken off. None when no opening
    line matches, or when several do.
    """
    if not source_text:
        return None
    lines = source_text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    wanted = []
    for line in code.replace("\r\n", "\n").split("\n") if code else []:
        wanted.append(_code_line(line))
    matches = []
    for index, line in enumerate(lines):
        opener = _OPENING.match(_LIST_MARKERS.sub("", _LEADING_QUOTES.sub("", line)))
        if opener is None:
            continue
        tokens = opener.group(2).split()
        if not tokens or tokens[0] != fence or "run" not in tokens[1:]:
            continue
        following = lines[index + 1:index + 1 + len(wanted)]
        if len(following) != len(wanted):
            continue
        same = True
        for got, want in zip(following, wanted):
            if _code_line(got) != want:
                same = False
                break
        if same:
            matches.append(index + 1)
    if len(matches) == 1:
        return matches[0]
    return None


def _text_of(path):
    if not path:
        return None
    try:
        return Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def facts_from_site(said: dict, blocks: list) -> list:
    """
    The `site_disagreements` fact from what the site recorded: each block's
    page as its place in the course folder, its line in the teacher's file
    (or None), in page order, leaving out every Swift block
    swiftCouldNotBePrepared already names.
    """
    places = {}
    for path, value in (said.get("places") or {}).items():
        places[nfc(path)] = value or {}
    already = set()
    for pair in said.get("swiftNamed") or []:
        already.add((nfc(pair[0]), int(pair[1])))
    content = said.get("content")
    ordered = []
    for position, block in enumerate(blocks):
        ordered.append((nfc(block.get("page") or ""), position, block))
    ordered.sort(key=lambda item: (item[0], item[1]))
    facts = []
    for path, _position, block in ordered:
        known = places.get(path) or {}
        place = known.get("place")
        if not place:
            place = path[:-3] if path.lower().endswith(".md") else path
        place = nfc(place)
        language = str(block.get("language") or "")
        n = int(block.get("block") or 1)
        if language == "swift" and (place, n) in already:
            continue
        source = _text_of(known.get("source"))
        if source is None and content:
            source = _text_of(Path(content) / path)
        facts.append({
            "page": place,
            "language": language,
            "block": n,
            "line": opening_line(source, language, str(block.get("code") or "")),
            "reason": str(block.get("reason") or "blockNotPrepared"),
        })
    return facts


def quiz_facts_from_site(said: dict, quizzes: list) -> list:
    """
    The `quiz_disagreements` fact from what the site's quiz safety net
    recorded (#644): each entry's page as its place in the course folder,
    with the question's place, its line (the folder check's, carried by the
    site - never looked up here), the reason, and the problem the site found
    with its values; pages in path order, each page's entries in the order
    the site printed them.
    """
    places = {}
    for path, value in (said.get("places") or {}).items():
        places[nfc(path)] = value or {}
    ordered = []
    for position, quiz in enumerate(quizzes):
        ordered.append((nfc(quiz.get("page") or ""), position, quiz))
    ordered.sort(key=lambda item: (item[0], item[1]))
    facts = []
    for path, _position, quiz in ordered:
        known = places.get(path) or {}
        place = known.get("place")
        if not place:
            place = path[:-3] if path.lower().endswith(".md") else path
        n = quiz.get("n")
        line = quiz.get("line")
        fact = {
            "page": nfc(place),
            "n": int(n) if n is not None else None,
            "line": int(line) if line is not None else None,
            "reason": str(quiz.get("reason") or "countedDifferently"),
        }
        if quiz.get("problem"):
            fact["problem"] = str(quiz["problem"])
            fact["fill"] = dict(quiz.get("fill") or {})
        facts.append(fact)
    return facts


def say(payload: dict, printer=print) -> None:
    """
    Build ONLY these two findings - the blocks of code, then the quizzes -
    and announce them together. Each is built in its own try: a failure is
    one plain line and costs only that finding.
    """
    course = payload.get("course", "")
    section = payload.get("section", "")
    found = []
    try:
        facts = facts_from_site(payload, payload.get("blocks") or [])
        if facts:
            found.append(site_health.site_disagreements_finding(
                {"site_disagreements": facts}, course, section, site_health._checks_by_name()))
    except Exception as error:
        printer(f"ℹ️  Could not name the blocks of code shown as plain code "
                f"in {course} Section {section}: {error}")
    try:
        facts = quiz_facts_from_site(payload, payload.get("quizzes") or [])
        if facts:
            found.append(site_health.quizzes_read_differently_finding(
                {"quiz_disagreements": facts}, course, section, site_health._checks_by_name()))
    except Exception as error:
        printer(f"ℹ️  Could not name the self-check questions the website read differently "
                f"in {course} Section {section}: {error}")
    try:
        site_health.announce(found, printer=printer)
    except Exception as error:
        printer(f"ℹ️  Could not say what the website found in {course} Section {section}: {error}")


def main() -> int:
    # UTF-8 both ways whatever the console's code page: on Windows a pipe
    # defaults to the ANSI code page, which has no ⚠️ and no curly quotes.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass
    try:
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("not an object")
    except Exception as error:
        print(f"ℹ️  Could not say what the website found: {error}")
        return 0
    say(payload)
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())

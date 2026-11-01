#!/usr/bin/env python3
"""
A section's record of its problems (#717): one ROW per problem a build of the
section met, kept beside its built site, so both apps can show them in a
table, mark the section in the sidebar, and tell a teacher when the set
CHANGED - rather than putting every folder problem in a dialog on every
build, which is the arrangement this replaces.

The words are not written here. Each row is worded by site_health's own
makers, called with ONE item, so a row says exactly what the folder problem
says about that item (the contract's singular `sentence`, its `detail`, and
the one piece of the list the detail names - "“Unit 1/Graphs”, diagram 2,
line 14: LaTeX stopped here: ..."). The reasons in that piece come through
the same functions the console and the HEALTH line use - for a figure,
figureFences.words.reasons through figures_finding - so the table cannot
word a problem differently from the console. Everything else - each kind's
label, what identifies a row, where its page comes from - is
contracts/shared-rules.json -> sectionProblems.

**Where.** `<builds root>/<COURSE>/section<N>/.problems.json`, beside
`.build-id` and `.visible-pages.json` (plan review, MED 4): archiving a
section removes it with the section's build, and it moves with a renamed
course. Never in the teacher's folder: this is a machine's build, not a
teacher's decision, and the vault is synced and backed up.

**Three writers, one file, each owning a SLICE of the rows** (`from`):

* build_site.py (`write_after_build`), once the pages the build shows are
  known and before Quartz runs, writes the record afresh: every row the
  folder checks found, plus the previous record's `site` and `deploy` rows
  CARRIED over unchanged (marked `carried`), because this build cannot have
  checked them yet - the site has not said, and a preview never meets the
  deploy's refusal.
* site_said.py (`merge_site_said`), run by the site's emitter on its first
  emit of EVERY site build (plan review, HIGH 1 - before #717 it ran only
  when something disagreed, so a fixed block's row would have stayed for
  ever), replaces the `site` slice and sets `siteSaidComplete`; only in a
  record whose buildId is its own.
* deploy.py (`record_deploy_refusals`) replaces the `deploy` slice when a
  deploy reaches the check that refuses (Cloudflare's largest file).

Each write prints ONE bounded `PLANTOIR_PROBLEMS:` line - counts only, never
a row - which the apps read to know the record has changed. `changed` is
worked out HERE, against the previous build's rows (`before`), so the
"did the set change?" decision lives in the shared code.

Never raises past its callers' `try`: a record that cannot be written costs
the record, never the build.
"""

import hashlib
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import contracts
import machine_line
import site_health

CONTRACT_FILE = "shared-rules"
RECORD_FILE = ".problems.json"
VERSION = 1


# ---- The rules ----------------------------------------------------------------------

def rules(*keys):
    return contracts.section(CONTRACT_FILE, "sectionProblems", *keys)


def marker_prefix() -> str:
    return rules("marker", "prefix")


def kinds() -> dict:
    """Each kind's row in sectionProblems.kinds, by kind."""
    table = {}
    for entry in rules("kinds"):
        table[entry["kind"]] = entry
    return table


# The maker for each kind that names a LIST of items, called with one item.
# Every other kind is a whole-section (or whole-course) problem and is one
# row as the finding stands.
_MAKERS = {
    "pageSettingsUnreadable": site_health.unreadable_settings_finding,
    "linksIntoHiddenPages": site_health.links_into_hidden_pages_finding,
    "printPdfNotFound": site_health.print_pdf_problems_finding,
    "figuresCouldNotBeDrawn": site_health.figures_finding,
    "swiftCouldNotBePrepared": site_health.swift_finding,
    "quizzesNotReady": site_health.quizzes_finding,
    "runnableCodeShownAsPlainCode": site_health.site_disagreements_finding,
    "quizzesReadDifferently": site_health.quizzes_read_differently_finding,
    "geogebraSketchesNotReady": site_health.geogebra_finding,
}


def section_number(section):
    """A section as a number when it is one: deploy.py has it as text."""
    try:
        return int(section)
    except (TypeError, ValueError):
        return section


def now_text() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---- Rows -----------------------------------------------------------------------------

def prompt_line(text: str) -> str:
    """
    A row's text for an outside assistant's prompt (717b; plan review, MED
    9): ONE line, at most prompt.maxCharacters, with each of prompt.replace's
    characters written as the contract says. Windows hands the prompt to
    `cmd /k`, which cannot carry a newline and expands `%` - the TeX comment
    character, which appears in what an engine says.
    """
    spec = rules("prompt")
    line = " ".join(str(text or "").split())
    for pair in spec["replace"]:
        line = line.replace(pair[0], pair[1])
    most = int(spec["maxCharacters"])
    if len(line) > most:
        line = line[:most - 1].rstrip() + "…"
    return line


def _identity(kind: str, spec: dict, fact: dict) -> str:
    parts = [kind]
    for field in spec.get("identity") or []:
        value = fact.get(field)
        parts.append("" if value is None else str(value))
    return "|".join(parts)


def _row(kind: str, spec: dict, fact: dict, made, item: str) -> dict:
    page_field = spec.get("page")
    page = str(fact.get(page_field) or "") if page_field else ""
    return {
        "id": _identity(kind, spec, fact),
        "kind": kind,
        "page": page,
        "reason": str(fact.get("reason") or ""),
        "item": item,
        "sentence": made.sentence,
        "detail": made.detail,
        "fixable": bool(made.fixable),
        "prompt": prompt_line(item if page else made.sentence),
        "from": spec.get("from", "build"),
    }


def _list_rows(kind: str, items: list, course: str, section, table: dict) -> list:
    """One row per item of a list check, worded by its own maker with that
    item alone. The piece the detail names (`item`) is the maker's detail
    with the contract's detail replaced by its list placeholder alone, so it
    is the very piece the folder problem names - never a copy of its rule."""
    spec = kinds()[kind]
    make = _MAKERS[kind]
    item_table = dict(table)
    item_table[kind] = dict(table[kind], detail="{" + spec["item"] + "}")
    found = []
    for fact in items:
        single = {spec["facts"]: [fact]}
        made = make(single, course, section, table)
        piece = make(single, course, section, item_table).detail
        found.append(_row(kind, spec, fact, made, piece))
    return found


def _no_two_alike(found: list) -> list:
    """An id met twice gets its place after it ("#2", "#3"), so two quizzes
    nested on one page - which have no number (`n` is None) - are two rows
    (plan review, LOW 10)."""
    seen = {}
    for row in found:
        count = seen.get(row["id"], 0) + 1
        seen[row["id"]] = count
        if count > 1:
            row["id"] = f"{row['id']}#{count}"
    return found


def rows(facts: dict, course: str, section) -> list:
    """Every row a build's folder checks found, in the findings' own order
    (site_health.findings), each list check's items in their order."""
    table = site_health._checks_by_name()
    spec_of = kinds()
    found = []
    for finding in site_health.findings(facts, course, section):
        spec = spec_of.get(finding.name)
        if spec is None:
            continue
        if spec.get("facts"):
            found.extend(_list_rows(finding.name, facts.get(spec["facts"]) or [], course, section, table))
        else:
            found.append(_row(finding.name, spec, {}, finding, finding.sentence))
    return _no_two_alike(found)


def site_rows(site_disagreements: list, quiz_disagreements: list, course: str, section) -> list:
    """The two kinds only the site can say (#567, #644), as site_said.py has them."""
    table = site_health._checks_by_name()
    found = []
    found.extend(_list_rows("runnableCodeShownAsPlainCode", site_disagreements or [], course, section, table))
    found.extend(_list_rows("quizzesReadDifferently", quiz_disagreements or [], course, section, table))
    return _no_two_alike(found)


def deploy_rows(oversized: list, course: str, section) -> list:
    """Each file Cloudflare Pages refuses (deploy.py's oversized_for_cloudflare:
    [(path in the site, bytes)]), one row each, worded by
    sectionProblems.deployRefusals."""
    kind = "filesTooLargeForCloudflare"
    spec = kinds()[kind]
    words = rules("deployRefusals", kind)
    found = []
    for path, size in oversized:
        fill = {"course": str(course), "section": str(section), "file": str(path),
                "megabytes": f"{size / (1024 * 1024):.1f}"}
        item = site_health.filled(words["item"], fill)
        made = site_health.Finding(kind, site_health.filled(words["sentence"], fill),
                                   site_health.filled(words["detail"], fill), False, course, section)
        row = _row(kind, spec, {"file": str(path)}, made, item)
        row["prompt"] = prompt_line(made.sentence + " " + item)
        found.append(row)
    return _no_two_alike(found)


# ---- The record -----------------------------------------------------------------------

def record_path(host_output_dir) -> Path:
    return Path(host_output_dir) / RECORD_FILE


def read(path) -> dict | None:
    """The record at `path`, or None when there is none this code can read."""
    try:
        record = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(record, dict) or record.get("version") != VERSION or not isinstance(record.get("rows"), list):
        return None
    return record


def _write(path, record: dict) -> None:
    """Atomically: a reader never meets half a file."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=".problems-", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            json.dump(record, stream, indent=2, ensure_ascii=False, sort_keys=True)
            stream.write("\n")
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def _keep_when_first_found(found: list, earlier: list, built_at: str) -> None:
    first = {}
    for row in earlier:
        if row.get("id") and row.get("firstSeen"):
            first[row["id"]] = row["firstSeen"]
    for row in found:
        row["firstSeen"] = first.get(row["id"], built_at)
        row["lastSeen"] = built_at


def _carried(row: dict) -> dict:
    kept = dict(row)
    kept["carried"] = True
    return kept


def _finish(record: dict) -> dict:
    """`changed` against the previous build's rows, and the alert's key: the
    build's id, and - when a deploy's refusal is among the rows - which
    refusals, so a deploy of the same build that is newly refused can raise
    the alert again while the same refusal again cannot."""
    now_ids = [row["id"] for row in record["rows"]]
    before = record.get("before") or []
    record["changed"] = {
        "new": [one for one in now_ids if one not in before],
        "gone": [one for one in before if one not in now_ids],
    }
    refused = sorted(row["id"] for row in record["rows"] if row.get("from") == "deploy")
    record["alertKey"] = record["buildId"]
    if refused:
        record["alertKey"] = f"{record['buildId']}+{_ids_hash(refused)}"
    return record


def _ids_hash(ids: list) -> str:
    return hashlib.sha256("\n".join(ids).encode("utf-8")).hexdigest()[:8]


def marker_payload(record: dict) -> dict:
    return {
        "course": record["course"],
        "section": record["section"],
        "buildId": record["buildId"],
        "alertKey": record["alertKey"],
        "rows": len(record["rows"]),
        "new": len(record["changed"]["new"]),
        "gone": len(record["changed"]["gone"]),
    }


def announce(record: dict, printer=print) -> None:
    printer(machine_line.text(marker_prefix(), marker_payload(record)))


def made_after_build(previous: dict | None, course: str, section, build_id: str, occasion: str,
                     facts: dict, pages_shown: list, built_at: str) -> dict:
    """The record build_site writes, as a pure function of the previous one."""
    earlier = []
    if previous and str(previous.get("course")) == str(course) and str(previous.get("section")) == str(section):
        earlier = previous.get("rows") or []
    found = rows(facts, course, section)
    _keep_when_first_found(found, earlier, built_at)
    for row in earlier:
        if row.get("from") in ("site", "deploy"):
            found.append(_carried(row))
    record = {
        "version": VERSION,
        "course": course,
        "section": section_number(section),
        "buildId": build_id,
        "builtAt": built_at,
        "occasion": occasion,
        "rows": found,
        "pagesShown": list(pages_shown or []),
        "before": [row["id"] for row in earlier if row.get("id")],
        "siteSaidComplete": False,
    }
    return _finish(record)


def write_after_build(host_output_dir, course: str, section, build_id: str, occasion: str,
                      facts: dict, pages_shown: list, printer=print, built_at: str = None) -> None:
    """build_site.py's write, wrapped so it never breaks a build."""
    try:
        path = record_path(host_output_dir)
        record = made_after_build(read(path), course, section, build_id, occasion, facts,
                                  pages_shown, built_at or now_text())
        _write(path, record)
        announce(record, printer=printer)
    except Exception as error:
        printer(f"ℹ️  Could not keep the list of problems for {course} Section {section}: {error}")


def merged_from_site(record: dict, build_id: str, found: list) -> dict | None:
    """The record with the site's slice replaced, or None when it is not this
    build's record (a later build has written it since, or none has)."""
    if not record or record.get("buildId") != build_id:
        return None
    earlier = [row for row in record["rows"] if row.get("from") == "site"]
    _keep_when_first_found(found, earlier, record.get("builtAt") or now_text())
    kept = [row for row in record["rows"] if row.get("from") != "site"]
    merged = dict(record)
    merged["rows"] = kept + found
    merged["siteSaidComplete"] = True
    return _finish(merged)


def merge_site_said(path, build_id: str, site_disagreements: list, quiz_disagreements: list,
                    course: str, section, printer=print) -> None:
    """site_said.py's write, wrapped so it never breaks the site."""
    try:
        found = site_rows(site_disagreements, quiz_disagreements, course, section)
        merged = merged_from_site(read(path), build_id, found)
        if merged is None:
            return
        _write(path, merged)
        announce(merged, printer=printer)
    except Exception as error:
        printer(f"ℹ️  Could not add what the website found to the list of problems for "
                f"{course} Section {section}: {error}")


def merged_from_deploy(record: dict | None, build_id: str, course: str, section, found: list,
                       checked_at: str) -> dict:
    """The record with the deploy's slice replaced. A section built before
    #717 has no record; one is started with the deploy's rows alone, its
    pages unknown (so it proves nothing about another section's rows)."""
    if not record:
        record = {"version": VERSION, "course": course, "section": section_number(section),
                  "buildId": build_id or "", "builtAt": checked_at, "occasion": "deploy",
                  "rows": [], "pagesShown": [], "before": [], "siteSaidComplete": False}
    earlier = [row for row in record["rows"] if row.get("from") == "deploy"]
    _keep_when_first_found(found, earlier, checked_at)
    kept = [row for row in record["rows"] if row.get("from") != "deploy"]
    merged = dict(record)
    merged["rows"] = kept + found
    return _finish(merged)


def record_deploy_refusals(section_dir, build_id: str, course: str, section, oversized: list,
                           printer=print) -> None:
    """deploy.py's write: `oversized` is every file this deploy was refused
    for, empty when it reached the check and nothing was too large."""
    try:
        path = record_path(section_dir)
        found = deploy_rows(oversized, course, section)
        record = read(path)
        had = record is not None and any(row.get("from") == "deploy" for row in record["rows"])
        if not found and not had:
            return
        merged = merged_from_deploy(record, build_id, course, section, found, now_text())
        _write(path, merged)
        announce(merged, printer=printer)
    except Exception as error:
        printer(f"ℹ️  Could not keep the list of problems for {course} Section {section}: {error}")

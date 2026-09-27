#!/usr/bin/env python3
"""The College Board pages for the marketing course, in the College Board's own words.

The marketing working folder (``~/Plantoir Marketing``, see
``marketing_folder.py``) teaches ICS3U alongside AP Computer Science
Principles, so its course has a second curriculum folder, **College Board
Curriculum**, holding one page per LEARNING OBJECTIVE (``CRD-1.A`` …, 67 of
them in the Fall 2023 Course and Exam Description), each page the objective's
exact text with its essential knowledge statements verbatim beneath it.

Where the words come from, and where they do NOT go:

- They are read out of the College Board's public Course and Exam Description
  PDF, downloaded into the kept folder's ``.sources/`` and checked against the
  SHA-256 recorded in ``marketing/csp-codes.json``. A different file is
  REPORTED and the run stops — the College Board revises these documents, and
  new wording should be looked at by a person rather than taken silently.
- **Nothing extracted is committed to this repository**, which is public. The
  text lives only in the kept folder; the repository holds the codes, the
  address, the edition and the hash.

How the words are read is in ``ced_statements.swift`` (why not pdftotext; why
by position). What this file adds is the checking: every statement is printed
in more than one place in the document — the Course Framework, and again in the
Appendix's conceptual framework, and a learning objective once more on each
page its topic continues onto — and every copy must agree, letter for letter
once whitespace is set aside, or the code is named and nothing is written for
it.

Standard library only, plus ``swift`` (which the capture already needs).
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
CODES_FILE = HERE / "marketing" / "csp-codes.json"
STATEMENTS_HELPER = HERE / "ced_statements.swift"

# Inside the kept folder's .sources/: pages a person wrote, used as they are
# (the objectives quoting drawn code), and the drafts made for them to start from.
OVERRIDES_NAME = "College Board Curriculum"
DRAFTS_NAME = "College Board Curriculum drafts"

LEARNING_OBJECTIVE = re.compile(r"^[A-Z]{3}-\d+\.[A-Z]$")
ESSENTIAL_KNOWLEDGE = re.compile(r"^([A-Z]{3}-\d+\.[A-Z])\.(\d+)$")
# The skill badge printed after an objective ("… through collaboration. 1.C").
# It is the College Board's suggested practice for the objective, not part of
# the objective's sentence.
SKILL_BADGE = re.compile(r"\s*\b\d\.[A-F]\s*$")


INNER_SKILL_BADGE = re.compile(r"\s\d\.[A-F](?=\s+[a-z]\.\s)")


def load_codes() -> dict:
    return json.loads(CODES_FILE.read_text(encoding="utf-8"))


# ---------- The source document ----------

def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


class SourceChanged(Exception):
    """The document found is not the edition the pages were checked against."""


def fetch_ced(sources: Path, codes: dict | None = None) -> Path:
    """The Course and Exam Description, downloaded once and kept.

    Re-used when it is already there and its hash matches. A file whose hash
    does NOT match is never used: that is either a new edition or a damaged
    download, and both want a person to look.
    """
    codes = codes or load_codes()
    source = codes["source"]
    sources.mkdir(parents=True, exist_ok=True)
    destination = sources / source["fileName"]
    if not destination.exists():
        print(f"   Downloading the Course and Exam Description from {source['url']}")
        partial = destination.with_suffix(".partial")
        try:
            with urllib.request.urlopen(source["url"], timeout=120) as response, partial.open("wb") as handle:
                while True:
                    block = response.read(1 << 20)
                    if not block:
                        break
                    handle.write(block)
        except OSError as error:
            if partial.exists():
                partial.unlink()
            raise SystemExit(
                f"Could not download the Course and Exam Description ({error}). Put the PDF at\n"
                f"  {destination}\nby hand and run this again."
            )
        partial.rename(destination)
    found = sha256_of(destination)
    if found != source["sha256"]:
        raise SourceChanged(
            f"{destination} is not the edition these pages were checked against:\n"
            f"  expected SHA-256 {source['sha256']} ({source['edition']})\n"
            f"  found            {found}\n"
            "The College Board may have revised it. Read the new edition, update "
            "website/shots/marketing/csp-codes.json, and re-check the correlation."
        )
    return destination


# ---------- Reading and checking ----------

def raw_statements(pdf: Path) -> list[dict]:
    """Every (code, page, text) the helper finds, uncleaned."""
    result = subprocess.run(
        ["swift", str(STATEMENTS_HELPER), str(pdf)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"Could not read {pdf}: {result.stderr.strip()[:400]}")
    rows: list[dict] = []
    for line in result.stdout.splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def is_drawn_as_code(text: str) -> bool:
    """True for a statement that quotes the exam reference sheet's code.

    Those statements set a procedure out twice — as text ("Text:") and as a
    drawing of blocks ("Block:") — inside the sentence. No reading of the
    columns turns that back into the document's layout, so an objective with
    one is written by a person, from the document (see `build_pages`).
    """
    return re.search(r"(?m)^\s*(Text|Block):", text) is not None


def clean_statement(code: str, text: str) -> str:
    """One statement as a reader would write it out: its own words, one line.

    Takes away what the rectangle caught that is not the statement — the code
    itself, the "continued on next page" note, an exclusion statement boxed
    under it, a skill badge — and turns the document's bullet lists into
    Markdown ones.
    """
    lines: list[str] = []
    for raw_line in text.splitlines():
        lines.append(raw_line.strip())
    if lines and lines[0] == code:
        lines = lines[1:]

    kept: list[str] = []
    for line in lines:
        if line.lower().startswith("continued on next page"):
            continue
        if line.upper().startswith("EXCLUSION STATEMENT") or re.fullmatch(r"X( X)*", line):
            # An exclusion statement is boxed under the knowledge it limits,
            # sometimes headed by its title and sometimes only by its icon,
            # which PDFKit reads as "X X". It is not part of the statement.
            break
        kept.append(line)

    paragraphs: list[str] = []
    bullets: list[str] = []
    current: str = ""
    for line in kept:
        if not line:
            continue
        if line == "§" or re.fullmatch(r"[a-z]", line):
            # The bullet glyph is drawn from a symbol font; PDFKit reports its
            # pieces as a lone "§" and a stray letter. Neither is text.
            continue
        if line.startswith("§ "):
            if current:
                if bullets:
                    bullets[-1] = join_lines(bullets[-1], current)
                else:
                    paragraphs.append(current)
                current = ""
            bullets.append(line[2:].strip())
            continue
        if bullets:
            # A line after a bullet continues that bullet.
            bullets[-1] = join_lines(bullets[-1], line)
            continue
        current = join_lines(current, line)
    if current:
        paragraphs.append(current)

    statement = " ".join(paragraphs).strip()
    if LEARNING_OBJECTIVE.match(code):
        # A multi-part objective ("a. … 4.C b. …") carries a badge after each
        # part, not only at the end.
        statement = INNER_SKILL_BADGE.sub("", statement)
        statement = SKILL_BADGE.sub("", statement)
        if re.fullmatch(r"\d\.[A-F]", statement):
            statement = ""
    for bullet in bullets:
        statement += "\n- " + bullet
    # A doubled comma is the reading (a comma at a line's end read twice),
    # never the document's; so are runs of spaces (the document indents
    # "a.   Write …" with a tab stop).
    statement = re.sub(r",[ \t]*,", ",", statement)
    return re.sub(r"[ \t]{2,}", " ", statement).strip()


def join_lines(before: str, after: str) -> str:
    if not before:
        return after
    if before.endswith("-") and not before.endswith(" -"):
        # "user-" / "focused" is one hyphenated word broken over a line.
        return before + after
    return before + " " + after


def comparison_key(text: str) -> str:
    """What two copies must share to be the same statement.

    Whitespace is set aside (line breaks differ between the two layouts), and
    so are the bullet marks: one layout draws a list's bullets in a way PDFKit
    reads, the other sometimes not, and "- age" against "age" is the same word.
    """
    without_bullets = re.sub(r"(?m)^- ", "", text)
    return re.sub(r"[\s§]+", "", without_bullets)


@dataclass
class CheckedStatement:
    code: str
    text: str
    pages: list[int] = field(default_factory=list)
    disagreements: list[str] = field(default_factory=list)
    copies: list[tuple[int, str]] = field(default_factory=list)


def check_copies(rows: list[dict]) -> dict[str, CheckedStatement]:
    """Group every copy of each code, and say where copies disagree.

    Two kinds of difference are the reading, not the document, and are not
    counted against a copy:

    - **An overrun.** A rectangle that runs past the end of its statement picks
      up whatever sits below it on that page — a skill badge, the next topic's
      first line. A copy whose text BEGINS with another copy's whole text, and
      adds to it, is that; it counts as agreeing with the shorter copy.
    - **Lost bullets or spaces**, set aside by `comparison_key`.

    The text kept is the copy the most copies agree with, taking the one with
    the most list items and spaces among them. Anything else is a
    disagreement, and the code is named for a person to read.
    """
    grouped: dict[str, list[tuple[int, str]]] = {}
    for row in rows:
        cleaned = clean_statement(row["code"], row["text"])
        if not cleaned:
            continue
        grouped.setdefault(row["code"], []).append((row["page"], cleaned))

    checked: dict[str, CheckedStatement] = {}
    for code, copies in grouped.items():
        keys: list[str] = []
        for _, text in copies:
            keys.append(comparison_key(text))
        # Each copy stands for the SHORTEST key it begins with, so an overrun
        # votes for the clean copy it overran.
        stands_for: list[str] = []
        for key in keys:
            shortest = key
            for other in keys:
                if other and key.startswith(other) and len(other) < len(shortest):
                    shortest = other
            stands_for.append(shortest)
        votes: dict[str, int] = {}
        for key in stands_for:
            votes[key] = votes.get(key, 0) + 1
        best_key = ""
        best_votes = -1
        for key, count in votes.items():
            if count > best_votes:
                best_key = key
                best_votes = count
        chosen = ""
        for index, (_, text) in enumerate(copies):
            if keys[index] != best_key:
                continue
            if (text.count("\n- "), text.count(" ")) > (chosen.count("\n- "), chosen.count(" ")):
                chosen = text
        entry = CheckedStatement(code=code, text=chosen, copies=list(copies))
        for index, (page, text) in enumerate(copies):
            entry.pages.append(page)
            if stands_for[index] != best_key:
                entry.disagreements.append(f"page {page}: {text}")
        if best_votes == 1 and len(copies) > 1:
            # Two copies, each different: no majority to take. Both are named.
            entry.disagreements.insert(0, f"page {copies[0][0]} and the others differ, with no majority")
        checked[code] = entry
    return checked


def rejoin_split_words(checked: dict[str, CheckedStatement]) -> None:
    """Join a word the reading split in two ("modif y", "Identif y").

    PDFKit sometimes reads a gap inside a word as a space. Every copy carries
    the same split, so the copy-against-copy check cannot see it. A pair is
    joined only when the joined word is printed elsewhere in the document and
    the fragments are not both words themselves.
    """
    # How often each word is printed, over every copy of every statement. A
    # fragment ("valuate", "modif") is counted too — it is in the split copy
    # — so the test is not "is it a word" but "is the joined word printed
    # more often than the fragment".
    counts: dict[str, int] = {}
    for entry in checked.values():
        for _, text in entry.copies:
            for word in re.findall(r"[A-Za-z]+", text):
                counts[word.lower()] = counts.get(word.lower(), 0) + 1

    def more_often_joined(first: str, second: str) -> bool:
        joined = counts.get((first + second).lower(), 0)
        return joined > counts.get(second.lower(), 0) and joined > counts.get(first.lower(), 0) // 50

    def join(match: re.Match) -> str:
        first, second = match.group(1), match.group(2)
        if len(second) > 1 and counts.get(second.lower(), 0) > counts.get((first + second).lower(), 0):
            return match.group(0)
        if counts.get((first + second).lower(), 0) > 0 and counts.get(first.lower(), 0) < counts.get((first + second).lower(), 0):
            return first + second
        return match.group(0)

    def join_capital(match: re.Match) -> str:
        # "E valuate": a capital letter left on its own. "A" and "I" are words.
        first, second = match.group(1), match.group(2)
        if first in ("A", "I"):
            return match.group(0)
        if more_often_joined(first, second):
            return first + second
        return match.group(0)

    for entry in checked.values():
        entry.text = re.sub(r"\b([A-Za-z]{2,}) ([a-z]{1,2})\b(?![.)])", join, entry.text)
        entry.text = re.sub(r"\b([A-Z]) ([a-z]{2,})\b", join_capital, entry.text)


def learning_objectives(checked: dict[str, CheckedStatement]) -> list[tuple[CheckedStatement, list[CheckedStatement]]]:
    """Each learning objective with its essential knowledge, in the document's order."""
    objectives: list[str] = []
    for code in checked:
        if LEARNING_OBJECTIVE.match(code):
            objectives.append(code)
    objectives.sort(key=objective_sort_key)

    result: list[tuple[CheckedStatement, list[CheckedStatement]]] = []
    for objective in objectives:
        knowledge: list[tuple[int, CheckedStatement]] = []
        for code, entry in checked.items():
            match = ESSENTIAL_KNOWLEDGE.match(code)
            if match and match.group(1) == objective:
                knowledge.append((int(match.group(2)), entry))
        knowledge.sort(key=lambda pair: pair[0])
        ordered: list[CheckedStatement] = []
        for _, entry in knowledge:
            ordered.append(entry)
        result.append((checked[objective], ordered))
    return result


BIG_IDEA_ORDER = ["CRD", "AAP", "DAT", "CSN", "IOC"]


def objective_sort_key(code: str) -> tuple:
    idea, rest = code.split("-", 1)
    number, letter = rest.split(".")
    position = BIG_IDEA_ORDER.index(idea) if idea in BIG_IDEA_ORDER else len(BIG_IDEA_ORDER)
    return (position, int(number), letter)


# ---------- Writing the pages ----------

def page_markdown(objective: CheckedStatement, knowledge: list[CheckedStatement]) -> str:
    """A learning objective's page, in the shape the Ontario pages use.

    The objective carries the `^text` block the Ontario pages carry, so the
    same embeds work; the essential knowledge follows it, each statement under
    its own code, verbatim.
    """
    idea = objective.code.split("-")[0]
    understanding = objective.code.split(".")[0]
    lines: list[str] = [
        "---",
        "transcludeTitleSize: h4",
        "tags:",
        f"  - {understanding}",
        f"  - big-idea-{idea.lower()}",
        "---",
        f"{objective.text} ^text",
        "",
    ]
    for entry in knowledge:
        lines.append(f"**{entry.code}** {entry.text}")
        lines.append("")
    return "\n".join(lines)


@dataclass
class WriteReport:
    written: list[str] = field(default_factory=list)
    kept: list[str] = field(default_factory=list)
    left_as_changed: list[str] = field(default_factory=list)


def write_pages(folder: Path, pages: dict[str, str]) -> WriteReport:
    """Write each page that is missing. Never overwrite one that is there.

    A page already there with exactly this text is "kept"; one that differs
    was changed by somebody — it is "left as you changed it" and untouched.
    """
    report = WriteReport()
    folder.mkdir(parents=True, exist_ok=True)
    for code in sorted(pages):
        path = folder / f"{code}.md"
        text = pages[code]
        if path.exists():
            if path.read_text(encoding="utf-8") == text:
                report.kept.append(code)
            else:
                report.left_as_changed.append(code)
            continue
        path.write_text(text, encoding="utf-8")
        report.written.append(code)
    return report


@dataclass
class Extraction:
    """What the document gives, and what it cannot give without a person."""
    pages: dict[str, str] = field(default_factory=dict)
    problems: list[str] = field(default_factory=list)
    # Objectives whose page a person must write (drawn code, see
    # `is_drawn_as_code`), each with a draft for them to correct.
    needs_a_person: dict[str, str] = field(default_factory=dict)
    # Objectives whose page was taken, as it is, from the overrides folder.
    from_overrides: list[str] = field(default_factory=list)


def apply_rulings(checked: dict[str, CheckedStatement], rulings: dict) -> None:
    """Where the document's own copies differ, use the copy a person chose.

    `csp-codes.json -> whereCopiesDiffer` names the page to take for a code
    and why. A ruling only settles the difference it was made for: if the
    copies stop disagreeing, or the page named holds no copy, it is ignored
    and the difference (if any) is reported as usual.
    """
    for code, ruling in rulings.items():
        entry = checked.get(code)
        if entry is None or not entry.disagreements:
            continue
        for page, text in entry.copies:
            if page == ruling.get("page"):
                entry.text = text
                entry.disagreements = []
                break


def override_problems(code: str, text: str, objective: CheckedStatement,
                      knowledge_codes: list[str]) -> list[str]:
    """A hand-written page must still be the objective it is named for."""
    problems: list[str] = []
    if comparison_key(objective.text) not in comparison_key(text):
        problems.append(f"{code}: the page in the overrides folder does not carry the objective's own words")
    for knowledge in knowledge_codes:
        if knowledge not in text:
            problems.append(f"{code}: the page in the overrides folder has no {knowledge}")
    return problems


def draft_for_a_person(objective: CheckedStatement, knowledge: list[CheckedStatement],
                       raw_by_code: dict[str, str]) -> str:
    """The page as far as it can be read, with each drawn statement left as the
    document's lines so a person can set it out properly."""
    lines: list[str] = [
        "---",
        "transcludeTitleSize: h4",
        "tags:",
        f"  - {objective.code.split('.')[0]}",
        f"  - big-idea-{objective.code.split('-')[0].lower()}",
        "---",
        f"{objective.text} ^text",
        "",
    ]
    for entry in knowledge:
        raw = raw_by_code.get(entry.code, "")
        if is_drawn_as_code(raw):
            lines.append(f"**{entry.code}** <!-- DRAWN AS CODE: set out from the document, then delete this note -->")
            for raw_line in raw.splitlines()[1:]:
                lines.append(raw_line.rstrip())
        else:
            lines.append(f"**{entry.code}** {entry.text}")
        lines.append("")
    return "\n".join(lines)


def build_pages(pdf: Path, codes: dict | None = None, overrides: Path | None = None) -> Extraction:
    """The page text for every learning objective, and every problem found.

    A problem is anything a person must look at before the pages are used: a
    code whose copies disagree with no ruling, a statement printed only once,
    an objective with no essential knowledge, a hand-written page that is not
    the objective it is named for, or a count that differs from the one
    recorded for this edition. Pages are returned only for objectives with no
    problem of their own. An objective with drawn code is returned under
    `needs_a_person` (with a draft) unless `overrides/<code>.md` exists.
    """
    codes = codes or load_codes()
    rows = raw_statements(pdf)
    drawn: set[str] = set()
    raw_by_code: dict[str, str] = {}
    for row in rows:
        if is_drawn_as_code(row["text"]):
            drawn.add(row["code"])
        # Kept from the Appendix when there is one: it sets each statement
        # out on the full width of the page, so the draft is easier to read.
        if row["code"] not in raw_by_code or row["page"] > 200:
            raw_by_code[row["code"]] = row["text"]
    checked = check_copies(rows)
    apply_rulings(checked, codes.get("whereCopiesDiffer", {}))
    rejoin_split_words(checked)

    extraction = Extraction()
    objectives = learning_objectives(checked)
    knowledge_total = 0
    for objective, knowledge in objectives:
        knowledge_total += len(knowledge)
        knowledge_codes: list[str] = []
        for entry in knowledge:
            knowledge_codes.append(entry.code)
        has_drawn: bool = False
        for knowledge_code in knowledge_codes:
            if knowledge_code in drawn:
                has_drawn = True

        own: list[str] = []
        if objective.disagreements:
            own.append(f"{objective.code}: copies disagree — {objective.disagreements}")
        if len(objective.pages) < 2:
            own.append(f"{objective.code}: printed only once (page {objective.pages}), so it could not be checked")
        if not knowledge:
            own.append(f"{objective.code}: no essential knowledge found")

        override = None
        if overrides is not None and (overrides / f"{objective.code}.md").is_file():
            override = (overrides / f"{objective.code}.md").read_text(encoding="utf-8")
        if override is not None:
            own.extend(override_problems(objective.code, override, objective, knowledge_codes))
            extraction.problems.extend(own)
            if not own:
                extraction.pages[objective.code] = override
                extraction.from_overrides.append(objective.code)
            continue

        for entry in knowledge:
            if entry.code in drawn:
                continue
            if entry.disagreements:
                own.append(f"{entry.code}: copies disagree — {entry.disagreements}")
            if len(entry.pages) < 2:
                own.append(f"{entry.code}: printed only once (page {entry.pages}), so it could not be checked")
        if has_drawn and not own:
            extraction.needs_a_person[objective.code] = draft_for_a_person(objective, knowledge, raw_by_code)
            continue
        extraction.problems.extend(own)
        if not own:
            extraction.pages[objective.code] = page_markdown(objective, knowledge)

    expected = codes["counts"]
    if len(objectives) != expected["learningObjectives"]:
        extraction.problems.append(
            f"found {len(objectives)} learning objectives, expected {expected['learningObjectives']}")
    if knowledge_total != expected["essentialKnowledge"]:
        extraction.problems.append(
            f"found {knowledge_total} essential knowledge statements, expected {expected['essentialKnowledge']}")
    return extraction


def main() -> int:
    """Print what would be written, for a person to read. Writes nothing."""
    import argparse
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("pdf", help="the Course and Exam Description PDF")
    parser.add_argument("--code", action="append", help="print only these learning objectives")
    parser.add_argument("--overrides", default=None, help="a folder of hand-written pages to use as they are")
    arguments = parser.parse_args()
    overrides = Path(arguments.overrides) if arguments.overrides else None
    extraction = build_pages(Path(arguments.pdf), overrides=overrides)
    for code in sorted(extraction.pages, key=objective_sort_key):
        if arguments.code and code not in arguments.code:
            continue
        print(f"===== {code}.md\n{extraction.pages[code]}")
    for code in sorted(extraction.needs_a_person, key=objective_sort_key):
        if arguments.code and code not in arguments.code:
            continue
        print(f"===== {code}.md (DRAFT — needs a person)\n{extraction.needs_a_person[code]}")
    for problem in extraction.problems:
        print(f"✗ {problem}", file=sys.stderr)
    print(f"{len(extraction.pages)} page(s) ready, {len(extraction.needs_a_person)} for a person to write "
          f"({', '.join(sorted(extraction.needs_a_person, key=objective_sort_key))}), "
          f"{len(extraction.problems)} problem(s).", file=sys.stderr)
    return 1 if extraction.problems else 0


if __name__ == "__main__":
    raise SystemExit(main())

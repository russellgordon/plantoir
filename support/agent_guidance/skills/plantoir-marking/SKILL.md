---
name: plantoir-marking
description: Use when a teacher asks for help marking or grading a test or quiz written on paper and scanned, or for feedback sheets for one, in any course. Works with identifiers only and keeps students' names on this computer with scripts, boxes the name line on every scan page that has a name blank after checking it against the blank test, has the teacher look at one check sheet before any paper is read, drafts every mark and comment for the teacher to decide, records the teacher's rulings and applies them to every paper, and builds feedback sheets that show why each mark was lost. Names go onto the sheets only at the end, by script, on the teacher's word.
---

# Marking a test from scanned papers, with students' names kept on this computer

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. Marking happens OUTSIDE it, in folders the teacher chooses. This
file is managed by Plantoir and is replaced when Plantoir updates; do not
edit it, and never write anything inside this skill's folder (it is
replaced whole, and a file written here is lost). Copy from it instead.

This skill marks tests and quizzes written on paper. It does not describe
marking anything else yet: if the teacher asks for that, say so plainly,
and do not do it from this skill.

## 1. The teacher decides

Say this in your first reply to any marking request, every time, and keep
it under the title of every document you write for the teacher (the marks
by question sheets, `Marking Settings.md`, `Marking Rules Applied.md`):

```text wrap
Every mark, level and comment I draft is a suggestion. Grading is your professional responsibility: please read and decide on each one before anything reaches a student. I draft; you decide.
```

## 2. Privacy first

Before any student's work is opened, and before any scan is boxed, say
these four points to the teacher, in these words or very close to them:

```text wrap
Before we start, four things about your students' privacy:
1. Whatever I read is sent to the AI service I run on, so that I can work on it. That includes every boxed paper. Please turn off model training for the account you use with me (on claude.ai: Settings, Privacy, "Help improve Claude"; on ChatGPT: Settings, Data controls, "Improve the model for everyone", where offered; as of November 2026, so check the names), check what your provider keeps for your kind of account, and check that your school or board allows student work to be processed by this service.
2. I work with identifiers only (Student A, Student B). I never open your name mapping table, a class list, an original scan, or anything in your teacher-only folder. Before I read a scan, a script boxes the name line at the top of each page whose blank test has a name blank, and stops any page that does not line up with your blank test. Then it makes one check sheet showing the top of every page as it was boxed. Please look at the check sheet before I read anything: you are the check that no part of a name shows, and I never open it. A name written anywhere else (in a margin, inside an answer, on a page with no name blank) is not boxed, and I would see it.
3. If I see what looks like a name anywhere, I will not repeat it in any message or file. I will tell you only the identifier and the page, and leave that page until you say.
4. The files I write stay on this computer, in the folders you choose. I never send, upload or publish anything; giving work back to students is yours to do.
```

Then keep to these, and when asked to cross one, say no with its reason in
one line:

- **Never open the name mapping table, a class list, or a marks export
  from the school's system**, even when the teacher asks: the names would
  then be sent to the AI service. Offer the script that does the job
  instead, run through the runner (section 6): `make_named_copies.py
  --check-table` to say whether the table is right (counts only), or the
  named step (section 12).
- **Never open, list, render or search anything in the teacher-only
  folder** (section 3): not the originals, not the check files, not the
  named copies. Scripts write there; you never read there.
- **Never write a name, or a student's work, into your memory, a note, a
  log, a brief, a summary, `.internal`, or anything under `courses/`.**
  Identifiers only, everywhere you write.
- **Never send anything anywhere**, and never decide a final mark.

## 3. If a name appears

If you see what looks like a student's name anywhere (a boxed paper, a
file, a message), do not repeat it in any message or file, and do not
guess whose it is. Tell the teacher only the identifier and the page
("Student C, page 2: something that may be a name"), write `NAME VISIBLE
page 2` in that paper's marks record `checks` (never the name), and leave
that page until the teacher says. If it is in a file you wrote, tell the
teacher which file by its path, and stop using that file.

## 4. Where things live

Two folders per course, both chosen by the teacher, both OUTSIDE this
working folder:

- **the marking folder**, the one you work in: settings, adapted scripts,
  boxed papers, marks records and identifier sheets. Offer
  `~/Marking/<CODE>/` (in their home folder) as a default.
- **the teacher-only folder**, beside it, which only scripts write and you
  never open: the name mapping table, the original scans, the check files
  and the named copies. Offer `~/Marking/<CODE> - Teacher Only/`, and let
  the teacher choose where it goes.

**Never set up a marking folder inside the working folder**, and refuse
when asked: it could be built into a class website or copied with a
course. If a folder the teacher names is inside it, say so and ask for
another. The scripts refuse it too: each stops, writing nothing, when a folder
it is given is inside a Plantoir working folder.

**A folder kept in sync by a service** (iCloud Drive, OneDrive, Dropbox,
Google Drive, a school's own storage) stores the papers and the name table
with that service too. The path often says so (`Library/Mobile Documents`,
`CloudStorage`, `OneDrive`, `Dropbox`), but not always: a Mac's Desktop and
Documents folders may be in iCloud while their paths look ordinary. So ask
the teacher whether the folder they chose is kept in sync. If it is, say
once, in plain words, that the papers and the name table will be stored by
that service as well, and let them decide (a school's own storage may be
the approved place). When they say that is fine, record it, and do not
raise it again for that folder.

Record the two folders in `courses/<CODE>/.internal/marking/marking.json`,
creating the `marking` folder inside `.internal`, and tell the teacher you
did:

```json
{"folder": "/Users/name/Marking/SNC2D", "teacherOnlyFolder": "/Users/name/Marking/SNC2D - Teacher Only", "syncAccepted": [], "teacherSaid": "keep it in Marking in my home folder", "recorded": "2026-11-12"}
```

Paths only, never a name. `syncAccepted` lists each synced folder's path
once the teacher has said it is fine; a folder not in the list is asked
about again. This is one of the places under a folder whose
name starts with a dot that a Plantoir skill may write; leave everything
else under `.internal` alone. Read it first next time: if it is there and
its folders exist, say them back ("I'll keep your marking in ... and your
teacher-only files in ..."); if not, ask again.

Inside them, for one assessment (a test's name, such as `Unit 2 Test`):

```text wrap
<marking folder>/
  Marking Settings.md                       this teacher's settings and the rulings they said yes to
  Scripts/                                  the scripts, copied from this skill and adapted
  <Assessment>/Redacted/Section N/          boxed papers, Student A.pdf
  <Assessment>/Marks/Section N/             marks records, Student A.json
  <Assessment>/Sheets/Section N/            identifier sheets, drafts and final
  <Assessment>/Briefs/                      the marker and reviewer briefs
  <Assessment>/Marking Rules Applied.md     every ruling, numbered
<teacher-only folder>/
  Name Mapping Table.csv                    section, identifier, name (and optional columns)
  <Assessment>/Originals/Section N/         the scans, Student A.pdf
  <Assessment>/Check/                       the check sheet (the teacher looks; you never open it)
  <Assessment>/Named/                       the named copies
  Quarantine/                               anything the runner caught
```

Because the marking folder is outside the working folder, the program you
run in (Claude Code, Codex) asks the teacher's permission before you work
there: say that before it happens. Ask for the marking folder only, never for the teacher-only
folder; scripts reach that one, run as commands.

## 5. What to have ready

Say what is needed in your first reply, briefly:

- the scans, one PDF per student named by identifier (`Student A.pdf`), in
  `Originals/Section N/` in the teacher-only folder. A whole class scanned
  in one file is fine too (section 7);
- the blank test, as printed, with nothing written on it (the kit's
  version PDF);
- the marking kit from the `plantoir-test-authoring` skill (`Marking
  Kit/answers.json` and `marks-template.json`), or the test and its
  answers, from which you write the kit with the teacher in that skill's
  format and check it with its `scripts/check_kit.py`;
- the list of what was taught, or the course pages, for the links on the
  sheets;
- the name mapping table, which you never open: a CSV with the columns
  `section`, `identifier`, `name`, and optionally `first name`, `paper`,
  `email`. If the teacher has none, tell them how to make it in a
  spreadsheet, with an invented example:

  ```text wrap
  section,identifier,name,first name
  1,Student A,"Testpupil, Alpha",Alpha
  1,Student B,"Zedfamily, Beta",Beta
  1,Student C,"Examplename, Gamma",Gamma
  2,Student A,"Samplesurname, Delta",Delta
  2,Student B,"Madeupname, Epsilon",Epsilon
  ```

## 6. Scripts are starting points

The scripts in `scripts/` beside this file are starting points, not rules.
For each one you use, copy the script into the marking folder's `Scripts/`
folder, adjust it to this teacher (their header, their categories and marks
scheme, their file layout), and run its `--self-test` before using it. Each
script opens with two blocks: "What you may change for this teacher", and
"What must not change". Keep every line of the second. If the self-test
fails, do not run the script; fix it first. Say plainly that a self-test
checks only the paths it knows, so it is a check, not a proof.

Two files are NOT starting points: `scripts/run_with_names.py` (below) and
the `plantoir-test-authoring` skill's `scripts/check_kit.py`. Run both from
their skill folders, and never copy or change them. Plantoir puts the skill
folder back as it shipped only when it next refreshes the working folder,
so before the first use in a session, check the runner is the one that
shipped:

```text wrap
python3 -B -c "import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], 'rb').read()).hexdigest())" .claude/skills/plantoir-marking/scripts/run_with_names.py
```

It must print `6b9507d024646a541e8661a0512203324291782063b2b356a7d8f41c127b6ea8`. If it does not, stop and tell the teacher
the runner has been changed; do not run any script that reads the table.

**Every script that reads the name mapping table is run through
`run_with_names.py`, never directly.** It reads the table itself, runs the
script in the marking folder with everything it prints captured, passes on
only the lines that hold no word from the table (accents and case
ignored), and moves any new file or folder in the marking folder that holds
one, in its text or its name, to the teacher-only `Quarantine/` folder. Its
last lines give three counts: files it read and found clean, files that
held a word from the table and were moved, and files it COULD NOT READ (a
link, a picture, a PDF Poppler cannot read, anything else that is not
text), which were not checked and were moved there unread. **Never open a
file the runner could not read**: tell the teacher how many, of which
kinds, and that they can look at them in the quarantine folder. It exits 1
when anything was held back, moved or not checked. It is a safety net, not
a guarantee: it catches the names in the table, in what the script printed
and what it wrote in the marking folder, and nothing else. Tell the
teacher that, in those words, the first time. A line held back because it
holds a word from the table that is also an everyday word (a name such as
May or Will) may be a false alarm: say so, and check the script's lines by
their counts instead.

(`python3 -B`; `python` or `py` on Windows, where `python3` may not exist.
`.agents/` works in place of `.claude/` in every path here.)

## 7. Scans: the blank test, the boxes, the check sheet, the teacher's look, then the papers

The teacher's eyes are the proof that a name is boxed, not anything the
script measures (Russell, 2026-11-12). The script boxes the name line,
checks each page lines up with the blank test, and makes ONE check sheet;
the teacher looks at it; only then are papers read.

1. **Copy `scripts/redact_scans.py`** into `Scripts/` and adapt it if the
   teacher's header is not the house style's (a label other than "Name",
   such as `--label Nom`; a different header layout). It finds the name
   blank on each page of the BLANK test, never a student's paper: the
   label, however the blank after it is drawn (a line, underscores, dots, a
   table cell, a frame). The box is generous: the whole line the blank sits
   on, margin to margin, and the room above it. Check what it finds first:

   ```text wrap
   python3 -B "<marking folder>/Scripts/redact_scans.py" --box-from "<blank test>.pdf"
   ```

   If the header has no label it can find, give the box in inches from the
   top-left corner with `--box left,top,right,bottom`, measured with the
   teacher.
2. **A whole class in one scan:** split it first, into the teacher-only
   folder. The script writes `Paper 01.pdf`, `Paper 02.pdf` ... in the
   order scanned, and `Papers to name.pdf` (the top of each paper) for the
   teacher, who fills in a `paper` column in the mapping table. Then the
   papers are renamed from that column, through the runner:

   ```text wrap
   python3 -B "<marking folder>/Scripts/redact_scans.py" --stack "<teacher-only>/<Assessment>/Whole class.pdf" --pages-per-paper 4 --into "<teacher-only>/<Assessment>/Originals/Section 1" --check-dir "<teacher-only>/<Assessment>/Check"
   python3 -B <this skill>/scripts/run_with_names.py --table "<teacher-only>/Name Mapping Table.csv" --watch "<marking folder>" --quarantine "<teacher-only>/Quarantine" -- python3 -B "<marking folder>/Scripts/redact_scans.py" --name-papers "<teacher-only>/Name Mapping Table.csv" --section 1 --into "<teacher-only>/<Assessment>/Originals/Section 1"
   ```

3. **Box the papers.** Each page is checked against the blank test first:
   its size, then where its header and foot are. A page that lines up only
   when turned upside down is turned upright first. Any other page that
   does not match (shifted more than 0.1 in, shrunk or enlarged, crooked,
   another size, sideways) stops that file with `CHECK` and a plain reason,
   and it is not written:

   ```text wrap
   python3 -B "<marking folder>/Scripts/redact_scans.py" "<teacher-only>/<Assessment>/Originals" "<marking folder>/<Assessment>/Redacted" --blank "<blank test>.pdf" --check-dir "<teacher-only>/<Assessment>/Check"
   ```

   It says how many pages were boxed, how many had no name blank on the
   blank test, and which files were stopped and why. It never says a name
   is covered. Tell the teacher every `CHECK` by identifier and reason:
   they rescan that paper, or box it by hand. **Never loosen a tolerance
   in the script to clear a `CHECK`**: the tolerances are in its "What
   must not change" block because loosening one lets a page through that
   the box does not fit. A file not named like an identifier is counted,
   never named. A line saying a page "has writing beside the name box" is
   a warning: tell the teacher to look at that page first on the check
   sheet.
4. **Stop: the teacher looks at the check sheet, then says yes.** The
   script writes ONE check sheet, `Check sheet.pdf`, in the teacher-only
   check folder: the top of every page as it was boxed, captioned by
   identifier and page, with pages that have no box, and pages with
   writing beside the box, marked in red. Ask the teacher to open it and
   look at every strip for any part of a name that shows, then to tell
   you. **Read no paper until the teacher has looked at the check sheet
   and said yes.** You never open the check sheet yourself: a name the box
   missed would be on it. If the teacher sees a name, the paper is boxed
   by hand or left out, and you are told only its identifier.

**What the box does not do.** The box covers the name line at the top of
each page whose blank test has a name blank, and nothing else. A name
written anywhere else on a page (in a margin, inside an answer, on a page
with no name blank) is not boxed, and you would see it; every page you
read goes to the AI service you run on. Say it that way; never say a name
is covered or removed.

**If the script cannot run, stop.** If Poppler (`pdftoppm`, `pdfinfo`,
`pdftotext`, `pdfunite`, `pdfseparate`) is missing, the script says which
and reads nothing; if Python is missing, the command fails. Tell the
teacher, in plain words, what to install (on a Mac with Homebrew,
`brew install poppler`; for the sheets, `brew install tectonic`), and
wait. Never read an original, and never box a page any other way.

## 8. Settings and rulings: whose marking this is

There are three kinds of rule, and they are applied differently:

- **Fixed, for every teacher:** sections 1 to 3; every lost mark carries a
  plain-words reason the student can read; a mark given with the benefit
  of the doubt says why; after any ruling, every paper gets the same
  treatment, and you check that it did; section 13.
- **The teacher's own.** If `courses/<CODE>/How I Teach.md` exists, read it
  first (with Plantoir's tools connected, `read_how_i_teach` reads it) and
  mark its way. Otherwise ask, once, briefly: the categories and how marks
  are counted (marks out of a total, or levels and their scale), whether a
  half mark may be given, the school name for the sheet's corner (from the
  course's print settings, `print_school_name`, as the `plantoir-handouts`
  skill's section 2 reads it). Record each answer in `Marking
  Settings.md` (copy `templates/Marking Settings.md` beside this file into
  the marking folder), with the teacher's words and the date.
- **One teacher's template.** The `plantoir-handouts` skill's section 13
  holds one teacher's template, "Lessons students can catch up on", and
  `reference/template.md` beside this file holds the marking rulings that
  go with it. Offer it once, in one or two sentences, only to a teacher
  who has shown an interest in both things it bridges: lessons built from
  students' own thinking (constructivist practice, Thinking Classrooms)
  AND a school where students often miss significant class time (sports
  and team travel, weather, illness, field trips and other school
  activities). Say it is one teacher's approach. If you cannot tell
  whether they have shown that interest, do not offer it.

For any other teacher, when a paper raises a question their settings do
not answer (a small slip, a misspelled word, an answer right in a way the
kit does not list), ask the open question ("How would you like a slip like
this one treated?"), and suggest one of the template's rulings only if the
teacher asks for a suggestion. Tell the teacher, the first time a ruling
comes up: "A ruling that changes a mark applies only once you have said yes
to it." Nothing from the template, and nothing you would choose yourself,
changes a mark until the teacher says yes. Then record it (section 12) and
apply it to every paper.

## 9. Marking the papers

Mark from the boxed papers in `Redacted/` only, and only after the teacher has said yes to the check sheet (section 7). For each paper, copy the
kit's `marks-template.json` to `Marks/Section N/Student A.json` and fill
it in, as the kit's `FORMAT.md` says. `earned` is 0 or 1 (0.5 only where
`Marking Settings.md` records `- Half marks: yes`); every point that
loses a mark has a `studentNote`, one sentence to the student saying why;
`checks` holds anything for the teacher (an answer the kit does not cover,
writing that could be read two ways, `NAME VISIBLE page N`). What the
sheet says goes in:

- `summary`: two or three sentences to the student;
- `byQuestion`: `{q, notes, benefitOfTheDoubt}` for a question whose row
  needs more than its points' notes, and `benefitOfTheDoubt: true` where
  full marks were given with the benefit of the doubt (the row is then
  listed, saying why);
- `focus`: at most four `{title, body, code, topics}`, each a teaching point
  in the student's terms, `topics` from the kit;
- `closing`: one paragraph naming the student's best work again and
  framing the first focus item as within reach.

Never a total: totals are counted from the points. Check each record with
`check_kit.py --marks` before its sheet is built.

## 10. Process

- **Calibrate first, on ONE paper** the teacher then reviews and rules on.
  Only then mark the rest.
- **One marker per paper, from a self-contained brief**: copy
  `templates/Marker Brief.md` into `<Assessment>/Briefs/`, fill it in once
  (the kit, the settings, the rulings so far, the folders), and give each
  marker only the brief and its identifier, never this conversation. At
  most three at a time.
- **A reviewer re-checks every claim** against the boxed paper, from
  `templates/Reviewer Brief.md`, and a second reviewer marks the same
  paper from first principles where the first found a fault. Fix what they
  find before anything is handed over.
- **After every ruling**, apply it to every paper already marked, then
  write a short check over `Marks/*/*.json` that proves it was, and run it.
- If you cannot start separate agents, mark one paper at a time yourself,
  and say plainly that the sheets had no independent check.
- **Reporting**: one short line per paper as it lands (`Section 1/Student
  C: K 3/4 T 5/6 C 2/3 A 3/3; 1 CHECK`), no summary until all are done;
  then a table by section, every `CHECK` with its identifier and question,
  and a short list of what you did not do. Identifiers only.

## 11. The feedback sheets

Copy `scripts/build_test_sheet.py` into `Scripts/`, adapt it to the
teacher's settings (section 6), and build each paper's sheets from its
marks record:

```text wrap
python3 -B "<marking folder>/Scripts/build_test_sheet.py" --kit "<kit>/answers.json" --marks "<marking folder>/<Assessment>/Marks/Section 1/Student A.json" --out "<marking folder>/<Assessment>/Sheets/Section 1" --checker "<this working folder>/.claude/skills/plantoir-test-authoring/scripts/check_kit.py" --settings "<marking folder>/Marking Settings.md" --school "<print_school_name>" --site "<the section's site address>" --links "<marking folder>/<Assessment>/checked-links.json"
```

It writes `Student A - Feedback.pdf` (for the student) and `Student A -
Marks by Question.pdf` (for the teacher), identifiers only, and their
`.tex`. `reference/test-sheets.md` says what the sheet holds and why. Render
every page of every draft into a temporary folder outside the working
folder (`pdftoppm -png -r 80`) and look at each one before handing over.

**Links into the course site.** A focus item's `topics` name pages in the
kit. Each page's address is the section's site address (the section's own
domain, or the address it was deployed to) followed by the page's `path`.
Fetch each address once, before the sheets are built, and write the paths
that answered into `checked-links.json` as a list. A link that did not
answer is left off the sheet; say which.

## 12. Names in, at the end, and tuning written down

When the teacher has read and decided on every sheet and says to, make the
named copies through the runner:

```text wrap
python3 -B <this skill>/scripts/run_with_names.py --table "<teacher-only>/Name Mapping Table.csv" --watch "<marking folder>" --quarantine "<teacher-only>/Quarantine" -- python3 -B "<marking folder>/Scripts/make_named_copies.py" --table "<teacher-only>/Name Mapping Table.csv" --sheets "<marking folder>/<Assessment>/Sheets" --out "<teacher-only>/<Assessment>/Named"
```

It prints counts and identifiers only. "Render every page and look"
applies to the identifier drafts only: nothing in the teacher-only folder
is opened, rendered or listed, the named copies included. If a named copy
fails, build the identifier draft of the same student again, fix that, and
run the named step again.

Everything the teacher tunes (a wording, a ruling, a setting) is written
down the first time, in `Marking Settings.md` when it is for every
assessment in the course, or in the assessment's `Marking Rules Applied.md`
(copy `templates/Marking Rules Applied.md`) when it is for this one, each
ruling numbered with the teacher's words and the date. Tell the teacher
which file you wrote it in, and whether it applies to this test or to all.

## 13. Content

Contexts you invent (an example in a focus item, a practice question)
never involve firearms or ammunition: choose a dice game, a race or a
recipe. A student's own answers, a teacher's own test and the course's
subject matter are quoted as they are.

## 14. When the marking is done

Look for `.claude/skills/plantoir-report-comments/SKILL.md` (or
`.agents/skills/plantoir-report-comments/SKILL.md`) in this working folder;
the root `CLAUDE.md` and `AGENTS.md` list the skills that are here. Only if
it is there, when the sheets are handed over and the marks are final, you
may mention once, in one sentence, that you can draft report card comments
from these records with the plantoir-report-comments skill. Do not raise it
again in this session if they do not take it up. If it is not there, say
nothing about report comments.

If the teacher asks what you can help with, answer plainly from what this
skill describes, and claim nothing it does not.

---
name: plantoir-marking
description: Use when a teacher asks for help marking or grading a test or quiz written on paper and scanned, or for feedback sheets for one, in any course. Works with identifiers only and never asks where the teacher-only folder is; the teacher double-clicks a file that boxes the name line on every scanned page whose blank test has a name blank, looks through the boxed papers, and types yes before any paper reaches the assistant; drafts every mark and comment for the teacher to decide, records the teacher's rulings and applies them to every paper, builds feedback sheets that show why each mark was lost, and builds the class's results from the marks records. Names go onto the sheets and results only at the end, by a second file the teacher double-clicks.
---

# Marking a test from scanned papers, with students' names kept on this computer

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. Marking happens OUTSIDE it, in folders the teacher chooses. This
file is managed by Plantoir and is replaced when Plantoir updates; do not
edit it, and never write anything inside this skill's folder (it is
replaced whole, and a file written here is lost). Copy from it instead.

This skill marks tests and quizzes written on paper, and builds the
class's results from those marks (section 15). It does not describe
marking anything else yet: if the teacher asks for that, say so plainly,
and do not do it from this skill.

## 1. The teacher decides

Say this in your first reply to any marking request, every time, and keep
it under the title of every document you write for the teacher (the marks
by question sheets, `Marking Settings.md`, `Marking Rules Applied.md`):

```text wrap
Every mark and comment I draft is a suggestion. Grading is your professional responsibility: please read and decide on each one before anything reaches a student. I draft; you decide.
```

## 2. Privacy first

Before any student's work is opened, and before any scan is boxed, say
these four points to the teacher, in these words or very close to them.
Say them even when the teacher says they have read them. This is a
request, and it is not what the teacher relies on: "Box the papers" shows
the same four points, word for word, in its own window before it asks for
the teacher-only folder, takes the teacher's yes to them and records it
(`<Assessment>/Privacy points shown.json`), and `--verify` reads nothing
as confirmed without that record. The cover of the file they look
through carries them too.

```text wrap
Before we start, four things about your students' privacy:
1. Whatever I read is sent to the AI service I run on, so that I can work on it. That includes every boxed paper. Please turn off model training for the account you use with me (on claude.ai: Settings, Privacy, "Help improve Claude"; on ChatGPT: Settings, Data controls, "Improve the model for everyone", where offered; as of November 2026, so check the names), check what your provider keeps for your kind of account, and check that your school or board allows student work to be processed by this service.
2. I work with identifiers only (Student A, Student B). I never ask where your teacher-only folder is, and I never open your name mapping table, a class list, an original scan, or anything in that folder. You run the two steps that touch names yourself, by double-clicking a file in your marking folder. The first boxes the name line at the top of each page whose blank test has a name blank and puts all the boxed papers in one file for you; they reach the folder I read only after you have looked through every page of it and typed yes. Your look is what confirms the names are redacted, and I never open that file. A name written anywhere else (in a margin, inside an answer, on a page with no name blank) is not boxed, and I would see it.
3. If I see what looks like a name anywhere, I will not repeat it in any message or file. I will tell you only the identifier and the page, and leave that page until you say.
4. The files I write stay on this computer, in the folders you choose. I never send, upload or publish anything; giving work back to students is yours to do.
```

Then keep to these, and when asked to cross one, say no with its reason in
one line:

- **Never ask where the teacher-only folder is, and never search for, list or open it.**
  You are never told where it is, and you never need to be: the teacher
  runs the two steps that read it, by double-clicking a file (sections 7
  and 12). Never list the folder that holds the marking folder either, or
  search it or any folder above it: other folders the teacher keeps there
  can hold names, in their files' names. If the teacher tells you its path
  anyway, do not use it, write it down or repeat it, and say you do not
  need it.
- **Never open the name mapping table, a class list, or a marks export
  from the school's system**, even when the teacher asks: the names would
  then be sent to the AI service. Offer the step that does the job
  instead: "Put names on the sheets" with the check of the table (section
  12), which answers in counts only, or the named step.
- **Never run `Box the papers` or `Put names on the sheets` yourself, by any means, even when the teacher asks you to.**
  Not with bash, a pseudo-terminal, `script`, `expect`, `open` or anything
  else. The yes is the teacher's, typed after their own look through every
  page, and the folder the launcher asks for is one you are never told.
  If the teacher asks you to run one ("run it for me"), say no in one line with that reason, and tell them which file to double-click in their
  marking folder. A launcher stops when its input is not a terminal, which
  catches an accidental pipe and nothing more: nothing in it can stop you,
  so this rule is what holds.
- **Never write a name, or a student's work, into your memory, a note, a
  log, a brief, a summary, `.internal`, or anything under `courses/`.**
  Identifiers only, everywhere you write.
- **Everything you make while marking goes in `<Assessment>/Work/` in the marking folder, and nowhere else.**
  Pictures of pages, notes to yourself, drafts, a reviewer's files: there.
  Never write a copy of a paper, a page or a sheet anywhere else, and
  never into the system's temporary folder (`/tmp`, `/private/tmp`,
  `$TMPDIR`, `/var/folders`, or Windows' `%TEMP%`): anyone on the computer
  can read it, and nothing cleans it up. To look at a page as a picture,
  use `scripts/render_pages.py` (section 11), which writes only there.
  Before you call the marking finished, run `teacher_only.py --tidy`
  (section 14).
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

Two folders per course, both OUTSIDE this working folder:

- **the marking folder**, the one you work in, chosen with the teacher:
  settings, adapted scripts, the two launchers the teacher double-clicks,
  the boxed papers once the teacher has said yes, marks records and
  identifier sheets. Offer `~/Marking/<CODE>/` (in their home folder) as a
  default.
- **the teacher-only folder**, which you are never told about: the name
  mapping table, the original scans, the file of boxed papers they look
  through, and the named copies. Tell the teacher to make a folder of
  their own for the files only they see, outside this working folder, and
  to put their name mapping table in it; you need not know its name or where it is. Never suggest a
  name or a place for it: the launchers ask the teacher for it each time,
  and say in their own window where to keep it.

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
the teacher whether the marking folder they chose, and the place where
they keep their teacher-only folder, are kept in sync (never ask where
that is). If they are, say
once, in plain words, that the papers and the name table will be stored by
that service as well, and let them decide (a school's own storage may be
the approved place). When they say that is fine, record it, and do not
raise it again for that folder.

Record the marking folder in `courses/<CODE>/.internal/marking/marking.json`,
creating the `marking` folder inside `.internal`, and tell the teacher you
did:

```json
{"folder": "/Users/name/Marking/SNC2D", "syncAccepted": [], "teacherSaid": "keep it in Marking in my home folder", "recorded": "2026-11-12"}
```

Paths only, never a name, and never the teacher-only folder's path.
`syncAccepted` lists the marking folder's path once the teacher has said
its sync is fine; a folder not in the list is asked about again. This is
one of the places under a folder whose name starts with a dot that a
Plantoir skill may write; leave everything else under `.internal` alone.
Read it first next time: if it is there and its folder exists, say it back
("I'll keep your marking in ..."); if not, ask again.

Inside them, for one assessment (a test's name, such as `Unit 2 Test`):

```text wrap
<marking folder>/
  Marking Settings.md                       this teacher's settings and the rulings they said yes to
  Box the papers.command                    the launchers the teacher double-clicks (.bat on Windows)
  Put names on the sheets.command
  Skill folder.txt                          one line: where this skill's folder is, for the launchers
  Names request.json                        the step that needs names, asked for (section 12)
  Put names on the sheets - what it said.txt   what that step printed, for you to read
  Scripts/                                  the scripts, copied from this skill and adapted
  <Assessment>/Box request.json             the blank test and the boxing script, for Box the papers
  <Assessment>/Box the papers - what it said.txt   what the boxing printed, for you to read
  <Assessment>/Redacted/Section N/          boxed papers, Student A.pdf, there only after the teacher's yes
  <Assessment>/Teacher looked.json          what the teacher said yes to: identifiers and SHA-256
  <Assessment>/Privacy points shown.json    the record that Box the papers showed the four points
  <Assessment>/Work/                        everything you make while marking, pictures of pages included
  Box the papers - last stop.txt            what a launcher said when it last stopped, for you to read
  <Assessment>/Marks/Section N/             marks records, Student A.json
  <Assessment>/Sheets/Section N/            identifier sheets, drafts and final
  <Assessment>/Briefs/                      the marker and reviewer briefs
  <Assessment>/Marking Rules Applied.md     every ruling, numbered
  <Assessment>/Results/                     the class's results, identifiers only (section 15)
the teacher-only folder (you never see it):
  Name Mapping Table.csv                    section, identifier, name (and optional columns)
  <Assessment>/Originals/Section N/         the scans, Student A.pdf
  <Assessment>/Holding/                     the boxed papers until the teacher's yes
  <Assessment>/Check/                       the one file of boxed papers to look through
  <Assessment>/Named/                       the named copies, the named results included
  Quarantine/                               anything the runner caught
```

Because the marking folder is outside the working folder, the program you
run in (Claude Code, Codex) asks the teacher's permission before you work
there: say that before it happens. Ask for the marking folder only.

**What this does not stop.** A listing of the marking folder's parent folder, or of any folder above it, can show the names of files the teacher keeps
there, and a misnamed scan would show a name that way. That is why you
never list or search the folder that holds the marking folder.

## 5. What to have ready

Say what is needed in your first reply, briefly:

- the scans, one PDF per student named by identifier (`Student A.pdf`), in
  `<Assessment>/Originals/Section N/` in the teacher-only folder ("Box the
  papers" makes that folder the first time, if it is not there). A whole
  class scanned in one file is fine too (section 7);
- the blank test, as printed, with nothing written on it (the kit's
  version PDF);
- the marking kit from the `plantoir-test-authoring` skill (`Marking
  Kit/answers.json` and `marks-template.json`), or the test and its
  answers, from which you write the kit with the teacher in that skill's
  format and check it with its `scripts/check_kit.py`;
- the list of what was taught, or the course pages, for the links on the
  sheets;
- the name mapping table, in the teacher-only folder, which you never
  open: a CSV with the columns `section`, `identifier`, `name`, and
  optionally `first name`, `paper`, `email`. If the teacher has none, tell
  them how to make it in a spreadsheet, with an invented example:

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

Some files are NOT starting points: `scripts/run_with_names.py`,
`scripts/teacher_only.py`, the four launchers in `launchers/` (below), and
the `plantoir-test-authoring` skill's `scripts/check_kit.py`. Never copy
the two scripts or change any of them: the launchers run the two scripts
from this skill's folder. Plantoir puts the skill folder back as it shipped
only when it next refreshes the working folder, so before the first use in
a session, and again after copying the launchers into the marking folder,
check them:

```text wrap
python3 -B -c "import hashlib, os, sys; [print(hashlib.sha256(open(path, 'rb').read()).hexdigest() + '  ' + os.path.basename(path)) for path in sys.argv[1:]]" .claude/skills/plantoir-marking/scripts/run_with_names.py .claude/skills/plantoir-marking/scripts/teacher_only.py .claude/skills/plantoir-marking/launchers/*
```

It must print these lines, in any order:

- `41fa097c8cbdefd87192d3225c7d2fcdf8aa5c760d29235e7ece95e05e7b4ffb`  run_with_names.py
- `cc5f8cb850cfe07f6445391cac90797ee890772bf2e4d0537af63a6651224ebc`  teacher_only.py
- `b2ae569d1ce347b3636497e205f7fe9c7446cb82713c61a21526ddd4ea751800`  Box the papers.command
- `11b1e23c41f89d9118473280008e134afb00a58f043c291022915bc8eea3dcff`  Put names on the sheets.command
- `e82aa624e48b42a213dfe73fb0d409477ae79a7a936c9d4fe3045e8c25f77d81`  Box the papers.bat
- `a9099a6c40f8335f3092aed9ffb50b9bd98400a2864de13c1f2bc6b58136a0ee`  Put names on the sheets.bat

Run it on the copies in the marking folder too (give their paths). If any
line differs, stop and tell the teacher which file has been changed; do
not copy the launchers, and do not run any script that reads the table.
A pin finds a well-meant change, such as an adapted copy; it would not
catch someone who changed a file and every pin together. The protection is
that the teacher starts these steps and you are never told where the
teacher-only folder is.

**What the teacher is trusting**, and you say so when you set up the
boxing: that the boxing script you adapted does only what it says. Box the papers runs it with
the teacher-only folder open to it. On a Mac it can write only into that
assessment's folder on the teacher's side and the temporary folder; on
every system, anything it writes outside the folder it was given, in the
marking folder or the teacher-only folder, is moved unread to the
teacher's Quarantine folder and the step stops, saying how many; a write
outside both folders is stopped on a Mac only. That is why the teacher
looks through every boxed page, and why the launcher says what it moved.

**Every script that reads the name mapping table is run through
`run_with_names.py`, never directly.** The launchers do that: you never
run such a script yourself, because you never know where the table is. The
runner reads the table itself, runs the script in the marking folder with
everything it prints captured, passes on only the lines that hold no word
from the table (accents and case ignored), and moves any new file or folder
in the marking folder that holds one, in its text or its name, to the
teacher-only `Quarantine/` folder. Its last lines, which you read in the
launcher's "what it said" file, give three counts: files it read with no
word from the table found in them, files that held a word from the table
and were moved, and files it COULD NOT READ (a link, a picture, a PDF
Poppler cannot read, anything else that is not text), which were not
checked and were moved there unread. **Never open a file the runner could
not read**: tell the teacher how many, of which kinds, and that they can
look at them in the quarantine folder. It is a safety net, not a
guarantee: it catches the names in the table, in what the script printed
and what it wrote in the marking folder, and nothing else. Tell the
teacher that, in those words, the first time. A line held back because it
holds a word from the table that is also an everyday word (a name such as
May or Will) may be a false alarm: say so, and check the script's lines by
their counts instead. A line withheld, or a file moved, because it holds a
two- or three-letter part of a name on its own (Ng, Li, No) is counted as
not checkable: it, too, may be a false alarm.

(`python3 -B`; `python` or `py` on Windows, where `python3` may not exist.
`.agents/` works in place of `.claude/` in every path here.)

## 7. Scans: the teacher boxes them, looks through them, then the papers

Russell, 2026-11-12: "script runs, teacher checks the papers, confirms
names are redacted, then agent based marking begins. Simple." You set the
boxing up. The teacher runs it, in a window of its own, by double-clicking
a file; their look through every page is what confirms the names are
redacted, and only their yes in that window moves the boxed papers to
where you read.

1. **Copy `scripts/redact_scans.py`** into `Scripts/` and adapt it if the
   teacher's header is unusual. It finds the name blank on each page of
   the BLANK test, never a student's paper: a label such as Name, Student
   Name or Nom, in any case, followed by a place to write (a line,
   underscores, dots, a table cell, a frame). It boxes that whole line,
   margin to margin, with room above it. Check what it finds on the blank
   test, which holds no student's writing, then run its `--self-test`:

   ```text wrap
   python3 -B "<marking folder>/Scripts/redact_scans.py" --box-from "<blank test>.pdf"
   ```

   If it stops (it cannot find a name blank, or finds two on a page), it
   says so: ask the teacher, and give the label with `--label "Student
   Name"`, or the box in inches from the top-left with `--box
   left,top,right,bottom`. Never guess. A blank test that is itself a scan
   has no text to read: give `--box`. You may render the blank test to
   measure its name line, or ask the teacher; `--box-from` with `--box`
   shows the box before any paper is boxed. A name blank in a footer is not
   found, and a second name line (Partner Name) is not boxed. Never run the
   script on a scan: you are never told where the scans are. Keep its
   handling of a file not named like an identifier (left alone and
   counted) as it is.
2. **Set up the launchers**, once per marking folder: copy the two
   launchers from `launchers/` beside this file into the marking folder
   (on a Mac `Box the papers.command` and `Put names on the sheets.command`,
   then make them runnable with `chmod +x`; on Windows the two `.bat`
   files), write the full path of this skill's folder (the folder this file
   is in) on one line into `<marking folder>/Skill folder.txt`, and check
   the copies' SHA-256 (section 6).
3. **Write `<marking folder>/<Assessment>/Box request.json`**, with the
   blank test, your adapted script and the options `--box-from` settled
   (only `--label`, `--box` and `--dpi`):

   ```json
   {"blank": "/Users/name/Teaching/SNC2D/Unit 2 Test/Version A.pdf", "script": "Scripts/redact_scans.py", "options": ["--label", "Student Name"]}
   ```

   **A whole class in one scan:** add `"wholeClass": {"file": "Whole
   class.pdf", "pagesPerPaper": 4, "section": 1}`, and tell the teacher to
   put that file, so named, in the assessment's folder in their
   teacher-only folder. The first double-click splits it into `Paper
   01.pdf` and so on in the order scanned and writes `Papers to name.pdf`
   (the first page of each) for them; they fill in a `paper` column in
   their name mapping table, and the next double-click names the papers
   from it and boxes them.
4. **Ask the teacher to double-click it**, in these words or very close to
   them:

   ```text wrap
   When your scans are in your teacher-only folder (one PDF per student, named Student A.pdf and so on, in "<Assessment>/Originals/Section 1"), please double-click "Box the papers" in your marking folder. It asks for your teacher-only folder in its own window, boxes the name line on every page, and opens one file of the boxed papers for you to look through; its first page has the four privacy points. Please look through every page of every paper. Look for any part of a name, and anything else that says who wrote it (a signature, initials, a student number). It does not check how each page was scanned: on a page scanned upside down the name line is at the foot, and on a page scanned shifted or shrunk part of the name can show just below the black box; and a name written anywhere else on a page is not boxed. Type yes in that window only when no part of a name shows, then tell me the papers are ready. If something shows, type no and tell me the identifier and page, never the name. I read nothing until then, and I never need to know where your teacher-only folder is.
   ```

   Then wait. **Read no paper until the teacher has looked through the
   redacted papers and typed yes.** You never open the file they look
   through: it is in the teacher-only folder, and a name the box missed
   would be in it. Nothing reaches the marking folder's `Redacted/` until
   their yes, and on a no nothing moves.
5. **Before reading any paper, in any session, run the check**, and if it
   does not say the teacher typed yes for these papers (no papers yet, a
   new batch, a changed or added file of any kind, or no record), ask the
   teacher to double-click "Box the papers" again:

   ```text wrap
   python3 -B .claude/skills/plantoir-marking/scripts/teacher_only.py --verify "<marking folder>/<Assessment>"
   ```

   It reads only the marking folder. The check cannot know who looked: it
   says the teacher typed yes in Box the papers, after the papers were put
   in one file. `<Assessment>/Box the papers - what it said.txt` says what
   the boxing printed: which papers were stopped and why, and how many
   files were left alone because they were not named like an identifier.
   Tell the teacher, by identifier and count. Any line that starts
   `Stopped:` means stop: nothing may be read, as when Poppler is missing.
   When the teacher says a launcher stopped, read `Box the papers - last
   stop.txt` (or `Put names on the sheets - last stop.txt`) in the marking
   folder: it says what to put right, and holds no name.

   If the teacher says no (a name shows on Student C, page 2): they rescan
   that paper, or you move the box (`--box` in `Box request.json`), and
   they double-click again; either way they look again. A paper boxed by
   hand goes into the originals folder in place of the scan and is boxed
   with the rest. Never loosen the shape tolerance in the script to let a
   paper through.

The boxing checks only that a paper's page count is a whole number of
copies of the blank test and that each page is the same way round, and
nearly the same shape, as its blank page; a paper that is not is stopped,
with the reason. It does NOT detect a page scanned upside down or shifted: the teacher sees that when looking through the papers.

**What the box does not do.** It covers the name line at the top of each
page whose blank test has a name blank, and nothing else. A name written
anywhere else on a page (in a margin, inside an answer, on a page with no
name blank) is not boxed, and you would see it; every page you read goes to
the AI service you run on. Say it that way; never say a name is covered,
removed or safe.

**If the script cannot run, stop.** If Poppler (`pdftoppm`, `pdfinfo`,
`pdftotext`, `pdfunite`, `pdfseparate`) is missing, the launcher says so
in the teacher's window and moves nothing; if Python is missing, it says
that. Tell the teacher, in plain words, what to install (on a Mac with
Homebrew, `brew install poppler`; for the sheets, `brew install
tectonic`), and wait. Never read an original, and never box a page any other way.

## 8. Settings and rulings: whose marking this is

There are three kinds of rule, and they are applied differently:

- **Fixed, for every teacher:** sections 1 to 3; every lost mark carries a
  plain-words reason the student can read; a mark given with the benefit
  of the doubt says why; after any ruling, every paper gets the same
  treatment, and you check that it did; section 13.
- **The teacher's own.** If `courses/<CODE>/How I Teach.md` exists, read it
  first (with Plantoir's tools connected, `read_how_i_teach` reads it) and
  mark its way. Otherwise ask, once, briefly: the categories and how marks
  are counted (marks out of the kit's points, by category), whether a
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

Mark from the boxed papers in `Redacted/` only, and only when `teacher_only.py --verify` says the teacher typed yes for them (section 7): read only the files `--verify` names, never any other file in that folder. For each paper, copy the
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

Never a total in a record: the marks by category are counted from the points. Check each record with
`check_kit.py --marks` before its sheet is built.

## 10. Process

- **Calibrate first, on ONE paper** the teacher then reviews and rules on.
  Only then mark the rest.
- **One marker per paper, from a self-contained brief**: copy
  `templates/Marker Brief.md` into `<Assessment>/Briefs/`, fill it in once
  (the kit, the settings, the rulings so far, the folders), and give each
  marker only the brief and its identifier, never this conversation. At
  most three at a time. Both briefs begin by running `--verify`; a marker
  or reviewer whose check does not name its paper reads nothing.
- **A reviewer re-checks every claim** against the boxed paper, from
  `templates/Reviewer Brief.md`, and a second reviewer marks the same
  paper from first principles where the first found a fault. Fix what they
  find before anything is handed over.
- **After every ruling**, apply it to every paper already marked, then
  write a short check over `Marks/*/*.json` that proves it was, and run it.
- **A point voided for the whole class** (a question that did not work,
  on the teacher's yes) is recorded once, in the kit's `voided`, and the
  same entry is copied into every marks record of the test: a point is
  voided for everyone or for no one, and `check_kit.py --marks` refuses a
  record that does not match. Then build every sheet again, and the class
  results.
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
every page of every draft into the assessment's `Work` folder, with
`scripts/render_pages.py` copied into `Scripts/` and self-tested like the
others, and look at each one before handing over:

```text wrap
python3 -B "<marking folder>/Scripts/render_pages.py" "<marking folder>/<Assessment>/Sheets/Section 1/Student A - Feedback.pdf" --into "<marking folder>/<Assessment>/Work"
```

The same command, given a boxed paper, is how you look at a page as a
picture. It refuses any folder that is not called `Work`, and the
system's temporary folders.

**Links into the course site.** A focus item's `topics` name pages in the
kit. Each page's address is the section's site address (the section's own
domain, or the address it was deployed to) followed by the page's `path`.
Fetch each address once, before the sheets are built, and write the paths
that answered into `checked-links.json` as a list. A link that did not
answer is left off the sheet; say which.

## 12. Names in, at the end, and tuning written down

When the teacher has read and decided on every sheet and says to, copy
`scripts/make_named_copies.py` into `Scripts/` (and run its
`--self-test`), write `<marking folder>/Names request.json`:

```json
{"do": "sheets", "assessment": "Unit 2 Test"}
```

and ask the teacher to double-click "Put names on the sheets" in the
marking folder. It asks for their teacher-only folder, says what it will
do, asks them to type yes, and makes the named copies through the runner
into `<Assessment>/Named` in the teacher-only folder. What it printed
(counts and identifiers only) is in `Put names on the sheets - what it
said.txt` in the marking folder: read that, and tell the teacher. The same
step with `{"do": "check-table"}` answers "is my table right?" in counts
only.

"Render every page and look" applies to the identifier drafts only:
nothing in the teacher-only folder is opened, rendered or listed, the
named copies included. If a named copy fails, build the identifier draft
of the same student again, fix that, and ask for the named step again.

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

Before you call the marking finished, look for copies of this
assessment's papers, sheets or pictures of them outside the marking
folder:

```text wrap
python3 -B .claude/skills/plantoir-marking/scripts/teacher_only.py --tidy "<marking folder>/<Assessment>"
```

It looks in the system's temporary folders for files named with the
assessment's or the marking folder's name, or with the same bytes as a
paper, a sheet, a marks record or a file in `Work`. **While it says "Not finished", the marking is not finished:** remove what it
found (you made it) or ask the teacher to, and run it again. Say plainly
what it cannot find: a picture named some other way, a copy anywhere else,
and anything already sent to the AI service.

Look for `.claude/skills/plantoir-report-comments/SKILL.md` (or
`.agents/skills/plantoir-report-comments/SKILL.md`) in this working folder;
the root `CLAUDE.md` and `AGENTS.md` list the skills that are here. Only if
it is there, when the sheets are handed over and the marks are final, you
may mention once, in one sentence, that you can draft report card comments
from these records with the `plantoir-report-comments` skill. Do not raise it
again in this session if they do not take it up. If it is not there, say
nothing about report comments.

If the teacher asks what you can help with, answer plainly from what this
skill describes, and claim nothing it does not.

## 15. Class results

When the marks are final, or the teacher asks how the class did, build the
class's results with `scripts/class_results.py`, copied into `Scripts/`
and self-tested like the others (section 6). It reads no mapping table, so
it runs directly, not through the runner. `reference/results.md` beside
this file says what it reads, what it writes and how the numbers are made.

```text wrap
python3 -B "<marking folder>/Scripts/class_results.py" --assessment "<marking folder>/<Assessment>" --kit "<kit>/answers.json" --checker "<this working folder>/.claude/skills/plantoir-test-authoring/scripts/check_kit.py" --settings "<marking folder>/Marking Settings.md"
```

It writes `Class Results.pdf` and a grade table per assessment into
`<Assessment>/Results/`, identifiers only (`--assessment` again, each with
its own `--kit`, and `--out` for a term's results across assessments).
Every script reads
identifiers one way only, `Student A` to `Student ZZ`, matched in full;
papers named another way are renamed first (`redact_scans.py
--name-papers`). Render every page and look, as for the sheets.

- **The numbers a marked test shows** (Russell, 2026-11-13): marks by
  category only (K, T, C, A as the kit names them), each out of its
  points and as a percentage. **There is no overall mark or percentage, ever,** on the sheet, in the results or in the grade table. **A test marked by points never mentions levels:** no level, no scale, no
  sentence about levels; levels belong to work marked against a rubric or
  success criteria, which this skill does not mark yet. **A voided point is a bonus:** it leaves the out of for everyone, and a
  student who earned it keeps the mark, so a category can read 2 out of 1,
  200%. The void is recorded once for the class, in the kit. How a
  percentage is rounded is the `- Percentages:` line of `Marking
  Settings.md` (whole numbers, half up, when there is none).
- **A sheet whose totals no longer match its marks record stops the
  build**, naming the identifier and both numbers: build that student's
  sheets again, tell the teacher which student was affected, and run it
  again. Never edit the numbers in a document by hand. It stops, too, on a
  file in `Marks/` not named like a record (a rescan saved
  beside one), a sheet with no record, or a sheet it cannot read: say what
  it printed, and ask the teacher which file is the right one.
- **After any change to a mark, run `class_results.py`
  again.** The documents do not change by themselves; each says when it was
  built and the fingerprint of everything it read, the settings included.
  A change to the settings needs a new run too. Report what it printed;
  never say the results are correct or complete. After each run, make the
  named copies again before anything is copied into a report system: a
  named copy keeps the build time and fingerprint of the run it came from.

The named copy of the document, and the named grade table for the school's
report system, are made only on the teacher's word, through the runner,
into the teacher-only folder, and you never open them. As for the named
sheets (section 12), write `<marking folder>/Names request.json` and ask the teacher to
double-click "Put names on the sheets", which runs
`make_named_copies.py --document` or `--grades` through the runner:

```json
{"do": "document", "assessment": "Unit 2 Test", "file": "Results/Class Results.tex"}
```

```json
{"do": "grades", "assessment": "Unit 2 Test", "file": "Results/Grades - Unit 2 Test.csv"}
```

Read what it printed in `Put names on the sheets - what it said.txt`.

Charts, a test beside an assignment, and a marking summary with the
teacher's own notes are not built by the script: `reference/results.md`
says how to make them yourself, identifiers only.

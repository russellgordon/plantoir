---
name: plantoir-report-comments
description: Use when a teacher asks for report card comments, progress report comments or term comments for a class, in any course. Drafts three options per student from the marks records the plantoir-marking skill wrote, in the school's own report convention and within its character limit, with identifiers only; first names go in at the end by plantoir-marking's make_named_copies.py, which counts every comment again after they are in. Every comment is a draft the teacher reads, changes and owns.
---

# Report card comments from the marking records, with students' names kept on this computer

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. Report comments are drafted OUTSIDE it, in the marking folder the
`plantoir-marking` skill set up. This file is managed by Plantoir and is
replaced when Plantoir updates; do not edit it, and never write anything
inside this skill's folder (it is replaced whole, and a file written here
is lost).

This skill drafts comments from what `plantoir-marking` wrote: the marks
records of tests and quizzes marked from scanned papers. No skill marks a
coding assignment or a project yet, so there are no records for one. If the
teacher wants one in the comments, tell them so, and draft from their own
notes only as section 5 says.

## 1. The teacher owns every comment

Say this in your first reply to any request for report comments, every
time, and keep it under the title of every file you write for the teacher:

```text wrap
These are drafts for you to read, change and own. I never send them anywhere or enter them into your report system. A comment reaches a student and their family only after you have read it and made it yours.
```

Never call a draft final, finished or ready to submit, even after the
teacher has changed it: it is theirs to call that.

## 2. Privacy first

Before you read any marks record, say these four points to the teacher, in
these words or very close to them:

```text wrap
Before we start, four things about your students' privacy:
1. Whatever I read is sent to the AI service I run on, so that I can work on it. That includes the marks records and feedback I draft the comments from. Please check that model training is turned off for the account you use with me (on claude.ai: Settings, Privacy, "Help improve Claude"; on ChatGPT: Settings, Data controls, "Improve the model for everyone", where offered; as of November 2026, so check the names), and that your school or board allows this work to be processed by this service.
2. I work with identifiers only (Student A, Student B), and I write {first name} in every comment where the first name goes. I never open your name mapping table, a class list, your report system or an export from it, or anything in your teacher-only folder. A script puts the first names in at the end, into your teacher-only folder, and tells me only counts.
3. If I see what looks like a name anywhere, I will not repeat it in any message or file. I will tell you only the identifier and where it is.
4. The files I write stay on this computer, in the folders you chose for marking. I never send, upload or enter anything; putting the comments into your report system is yours to do.
```

Then keep to these, and when asked to cross one, say no with its reason in
one line:

- **Never open the name mapping table, a class list, the report system, an
  export from it, or a past report card**, even when the teacher asks: the
  names would then be sent to the AI service. The scripts in section 7 do
  what is needed without them.
- **Never open, list, render or search anything in the teacher-only
  folder**, the named comments included.
- **Never ask for, guess or write a student's pronouns or gender.** Section
  6 says how a comment is written without them.
- **Never put a name into a draft**, even one quoted from a student's work
  (a game called after its maker, a signature on a page): leave the quoted
  words out, or describe them. If a name reached you anyway, do as
  `plantoir-marking` section 3 says: never repeat it, give only the
  identifier and where.
- **Never write a name, a comment or a student's work into your memory, a
  note, a log, a summary, `.internal`, or anything under `courses/`.**
  Identifiers only, and only in the marking folder.

## 3. Where things are

Read `courses/<CODE>/.internal/marking/marking.json`, which
`plantoir-marking` section 4 writes: it gives the marking folder and the
teacher-only folder. If it is not there, no marking has been done with that
skill in this course: say so, and ask where the marks records are. Never
set anything up inside this working folder.

```text wrap
<marking folder>/
  Marking Settings.md                          the teacher's settings; the report convention goes here (section 4)
  <Assessment>/Marks/Section N/Student A.json  the marks records you draft from
  <Assessment>/Marking Rules Applied.md        the rulings, which explain some marks
  <Term> Comments/Comments.json                your drafts, identifiers only
  <Term> Comments/Comments - Drafts.md         the same drafts, for the teacher and the reviewer to read
  <Term> Comments/Teacher Notes.md             the teacher's own notes by identifier, only if they write some
<teacher-only folder>/
  Name Mapping Table.csv                       never opened
  <Term> Comments/Named/Report Comments.csv    written by the script; never opened
  <Term> Comments/Named/Report Comments.md     the same, to read; never opened
```

`<Term>` is the teacher's name for the reporting period (`Term 1`,
`Midterm`). Keep only these files in `<Term> Comments/`.

## 4. The shape: the school's convention, asked

If `courses/<CODE>/How I Teach.md` exists, read it first (with Plantoir's
tools connected, `read_how_i_teach` reads it). Report systems and their
conventions belong to the school or board, so then **ask what the school's
report convention is**, once, briefly, unless `Marking Settings.md`
already records it:

- the character limit, and whether the report system counts characters or
  bytes (if the teacher does not know: characters; a system that counts
  bytes counts an accented letter as two, and a web form may count an emoji
  as two, which the script's count of characters does not). There is no
  default limit;
- whether it keeps line breaks (if not, or the teacher does not know, each
  option is one paragraph with no line break: a line break is counted, as
  one character or two);
- who the comment speaks about or to, and in what tense (about the student
  or to them; past or present);
- the parts a comment must have (some boards ask for strengths and next
  steps, some for a learning goal), and any words the school asks for or
  asks to avoid;
- how often the student's name appears, if the school says.

Record each answer under a heading `## Report comments` in `Marking
Settings.md`, with the teacher's words and the date, and tell the teacher
you did.

If the teacher has no convention to give and asks for a suggestion, show
`reference/template.md`'s shape as one teacher's example ("one teacher
writes them this way: ..."), never as the default, and let them choose or
change it. That shape belongs to one teacher's template, "Lessons students
can catch up on" (the `plantoir-handouts` skill's section 13): offer the
template itself only as `plantoir-marking` section 8 says, to a teacher who
has shown an interest in both things it bridges.

Fixed for every teacher, whatever the convention:

- **three options per student**, each complete on its own, so the teacher
  can pick one or blend them, and each drawing on the records in a
  different mix;
- kind, specific, and in plain words a parent can read as well as the
  student;
- evidence from the records only (section 5);
- within the limit after the names go in (section 7).

## 5. What a comment is drawn from

**Evidence from the records only.** Ask which assessments this term's
comments draw on, then for each identifier read only that assessment's
marks record (`Marks/Section N/Student A.json`: its `summary`,
`strengths`, `focus`, `closing`, `byQuestion` and each point's
`studentNote`), its kit (for the categories and what each point means) and
its `Marking Rules Applied.md`. Read them only once the marks are final,
when the teacher has decided on the sheets (`plantoir-marking` section
12). A record whose `checks` still holds something the teacher has not
settled (`NAME VISIBLE`, an answer the kit does not cover) is asked about
first.

- Never invent effort, attitude, participation, behaviour, attendance,
  improvement or anything about health or family: if no record says it,
  it is not in the comment.
- A mark or level, if the convention wants one, is the one the record
  gives, counted from its points with the kit, never rounded up or
  guessed.
- A student with no record for an assessment is listed by identifier,
  with nothing drafted from that assessment; tell the teacher which.
- **Something no record holds** (a coding assignment, a project, class
  discussion): say plainly that there is no record of it. If the teacher
  wants it in the comments, ask them to write notes by identifier, never
  with a name, in `<Term> Comments/Teacher Notes.md`. Before you read
  them, check them through the runner (section 7), and read them only if
  it finds no word from the table. The check looks for every part of every
  name in the table, a two-letter first name too, and cannot see a
  nickname, initials or a name that is not in the table: ask the teacher to
  read the notes once for those before you open them.

  ```text wrap
  python3 -B .claude/skills/plantoir-marking/scripts/run_with_names.py --table "<teacher-only>/Name Mapping Table.csv" --watch "<marking folder>" --quarantine "<teacher-only>/Quarantine" -- python3 -B "<marking folder>/Scripts/make_named_copies.py" --check-file "<marking folder>/<Term> Comments/Teacher Notes.md" --table "<teacher-only>/Name Mapping Table.csv"
  ```

  If it names lines, tell the teacher the line numbers and do not open
  the file until they have changed them. Cite the notes as the teacher's.

## 6. How the name appears

Drafts write `{first name}` where the student's first name goes, and are
written so that no pronoun is needed: "{first name} balanced every
equation in Part B; counting the oxygen in two products is the next step"
rather than a sentence that needs "she" or "he". Use the name as often as
the school's convention says, and otherwise once.

Only if the teacher tells you that the mapping table has a `pronouns`
column (the teacher fills it; you never see it), you may write `{they}`,
`{them}`, `{their}` and `{theirs}`, or `{They}`, `{Them}`, `{Their}` and
`{Theirs}` at the start of a sentence; the script fills them from that
column (`she/her`, `he/him`, `they/them`, the same with a third word such
as `she/her/hers`, or four words such as `xe/xem/xyr/xyrs`). "They" takes
"were" where "she" takes "was", so after a pronoun placeholder write only a
verb that does not change ("{They} explained", never "{They} was" or
"{They} is"): the script refuses a draft with is, was, are, were, has,
have, does or do after `{they}`, whatever the table holds. It refuses any
other placeholder too, and a pronoun placeholder the table cannot fill.

## 7. Length is checked after the names go in

**Length is checked after the names go in.** A comment that fits with
`{first name}` in it can be over the limit with a long first name in it,
so the script that puts the names in counts every comment again, and the
count is the one that matters.

Copy `make_named_copies.py` from `plantoir-marking`'s `scripts/` into the
marking folder's `Scripts/` (if it is not there already; a copy made before
report comments existed has no `--comments` and stops with "give --sheets":
copy the shipped one again and redo that teacher's changes) and run its
`--self-test`, as `plantoir-marking` section 6 says; check the runner's
SHA-256 as that section says before the first use in a session. **Every
script that reads the name mapping table is run through
`run_with_names.py`, never directly.**

1. **Before drafting**, find the longest first name's length, as a number
   (never the name):

   ```text wrap
   python3 -B .claude/skills/plantoir-marking/scripts/run_with_names.py --table "<teacher-only>/Name Mapping Table.csv" --watch "<marking folder>" --quarantine "<teacher-only>/Quarantine" -- python3 -B "<marking folder>/Scripts/make_named_copies.py" --longest-first-name --table "<teacher-only>/Name Mapping Table.csv"
   ```

   `{first name}` is 12 characters. Draft each option to at most the limit
   less however much longer than 12 that name is, counted with the
   placeholders in.
2. **After drafting and review** (section 8), put the names in:

   ```text wrap
   python3 -B .claude/skills/plantoir-marking/scripts/run_with_names.py --table "<teacher-only>/Name Mapping Table.csv" --watch "<marking folder>" --quarantine "<teacher-only>/Quarantine" -- python3 -B "<marking folder>/Scripts/make_named_copies.py" --comments "<marking folder>/<Term> Comments/Comments.json" --table "<teacher-only>/Name Mapping Table.csv" --out "<teacher-only>/<Term> Comments/Named" --limit 450 --count characters
   ```

   (the teacher's limit, and `--count bytes` when their system counts
   bytes). It prints counts and identifiers only. It writes nothing at all
   when any draft needs fixing, and says which: a placeholder it does not
   know or cannot fill, a student it cannot find, a cite that is not that
   student's own record, or a draft that already holds a word from the
   mapping table (any part of a first name, however short), which it names
   by option and word number, never the word. That last may be a name you
   were not meant to
   see, or an everyday word that is also someone's name (May, Will, Stone):
   either way, rewrite that option without the word, and do not repeat it.
   When it names a comment as over the limit, rewrite that option shorter
   and run it again, until it says every comment is within the limit.
   Never trim a comment by cutting off its end. `--out` must be inside the
   teacher-only folder that holds the mapping table. When a run is
   refused, the named files of an earlier run are renamed "earlier run, do
   not use", so the teacher never mistakes them for the current ones; tell
   the teacher. It also names, by identifier, any student of a drafted
   section that the drafts leave out.

Through these steps you learn nothing from the table but numbers and
identifiers. (`python3 -B`; `python` or `py` on Windows. `.agents/` works
in place of `.claude/` in every path here.)

## 8. Drafting and review

Write the drafts as `<Term> Comments/Comments.json`:

```json
{"term": "Term 1", "students": [{"section": 1, "identifier": "Student A", "cites": ["Unit 2 Test/Marks/Section 1/Student A.json"], "options": ["{first name} ...", "...", "..."]}]}
```

`cites` lists the records each student's options draw on: only that
student's own (`Section N/Student A.json` for Section N's Student A), and
the teacher's `Teacher Notes.md`; the script refuses any other. A student with
nothing to draft from has `"options": []`. Then write `Comments -
Drafts.md` beside it for the teacher: the sentence from section 1 under
its title, then each identifier with its three options and each one's
length with the placeholders in.

- **Calibrate first, on ONE student** the teacher reads and adjusts. Only
  then draft the rest, in the shape they settled.
- **A reviewer checks every option** before anything is handed over: a
  separate agent, given only the drafts, the marks records and the
  convention in `Marking Settings.md`, never this conversation. It opens
  each student's record by that student's section and identifier, not only
  by what `cites` says. It checks
  that each option claims nothing its records do not hold, misstates no
  mark or level, carries no name and no pronoun the teacher did not allow,
  follows the convention, and is kind. Fix what it finds. If you cannot
  start a separate agent, check them yourself and say plainly that the
  drafts had no independent check.
- **Reporting**: one line per section as it lands (`Section 1: 18
  students, 54 options drafted; 2 with no record for the Unit 2 Test`),
  identifiers only.

## 9. Names in, on the teacher's word

When the teacher has read the identifier drafts and says to, run step 2
of section 7. The named comments are in the teacher-only folder, and
nothing in the teacher-only folder is opened, rendered or listed: tell the
teacher where they are, that they hold the full names beside the
identifiers for finding each student in the report system, and that each
one is theirs to read and change before it is used. If they change their
mind about a comment, change the identifier draft and run the step again,
rather than having them send you the named one.

## 10. Content

Contexts you invent (an example in a next step) never involve firearms or
ammunition: choose a dice game, a race or a recipe. A student's own
answers and the course's subject matter are described as they are.

## 11. When asked what you can help with

Answer plainly from what this skill describes, and claim nothing it does
not. This is the last step after marking: it offers nothing after itself.

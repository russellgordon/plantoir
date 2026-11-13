# The class's results

What `scripts/class_results.py` builds from the marks records, what it reads, and what it leaves to you.
Everything here is the default for every teacher; the teacher's How I Teach page and `Marking Settings.md`
come first, and the script is a starting point like the others (copy it into `Scripts/`, adapt it, run
`--self-test`).

## What it reads

- **Marks records** of a test, `<Assessment>/Marks/Section N/Student A.json`, each checked with the
  `plantoir-test-authoring` skill's `check_kit.py` against the kit given after the assessment
  (`--kit`). Totals are counted from the points; a record never holds one.
- **Level records**, `<Assessment>/Records/Section N/Student A.json`, read ONLY IF that folder is there:

  ```json
  {"identifier": "Student A", "section": 1, "levels": {"K": {"first": "3", "revised": "3+"}, "T": {"first": "2", "revised": null}}}
  ```

  No skill writes these for a coding assignment yet. If the teacher gives you the levels of an
  assessment marked some other way, by identifier only, you may write them in this shape. When an
  assessment has no `Records/` folder, or no `Marks/` folder, the document says so in words, so
  nobody reads a missing part as a part with nothing in it.
- **The sheets**, `<Assessment>/Sheets/Section N/Student A - Marks by Question.tex`, when they are
  there: the marks line `build_test_sheet.py` writes at the top of each.
- **`Marking Settings.md`**: the `- Half marks:` line, and the teacher's scale on the `- Levels scale:`
  line (`none`, or each level and its percent, highest first: `- Levels scale: 4 80, 3 70, 2 60, 1 50`
  shows the format only). The scale is always the teacher's. Never fill it in yourself, from another
  teacher's scale or from an example; ask, and record the answer with the teacher's words and the date.

## What it writes, into the marking folder

- `Class Results.tex` and `Class Results.pdf`: when it was built, from how many records of which
  assessment, a fingerprint of those records, which parts had no records, how the numbers are made;
  then, section by section, each student's marks by category and total with the section's means; the
  levels first and revised; and "No revised levels", the students whose level record has no revised
  level, by identifier.
- `Grades - <Assessment>.csv`: one row per student, marks, out of and percent by category and for the
  total, and the level from the scale when there is one.
- `Levels - <Assessment>.csv`: one row per student with a level record: first, revised, the level that
  stands (the revised one, or the first when there is none), and its percent from the scale.

Every student is written by identifier. In the `.tex` each is `\student{section}{identifier}`, the one
place the named step puts a name.

## How the numbers are made

- A category's mark is the sum of its points earned, out of its points counted. A point the teacher
  removed from the count (`voided` in the record) is left out of the "out of", and a mark earned on it
  still counts, exactly as the feedback sheet counts it, so the two never disagree.
- The total is the sum of every point, counted on its own and checked against the categories' sum.
  There is no weighting unless the teacher asks for one; then change it in the copy in `Scripts/` and
  say on the document how it is weighted.
- A mark's level is the highest level on the scale at or below its percentage. A teacher who reads
  levels another way (the nearest level, say) changes `LEVEL_FROM_PERCENT` in the copy.
- A level's percent is the scale's.

## When it stops, and what it says

It writes nothing new, and renames the last run's files "earlier run, do not use", when:

- a sheet's marks line no longer gives the totals the points give. It names the identifier and both
  numbers. The student was told something the record no longer says: build that student's sheets again
  with `build_test_sheet.py`, tell the teacher, then run this again;
- a record has a half mark and the settings record no yes to half marks;
- a level is not on the teacher's scale;
- a record's identifier or section is not its file's and folder's, or a record is not in the shape above;
- the kit checker refuses a record.

A record with a point not yet marked is left out of the documents and named by identifier, and the run
exits 1. A file not named like an identifier is counted and left alone. The script never says a
document is correct or complete: it says what it read, what it compared, and what it wrote.

**After any change to a mark or a level, run it again.** The documents do not change by themselves, and
each one says when it was built and from which records. Tell the teacher when it was last run.

## Names, at the end

The named copy of the document and the named grade table for the school's report system are made only
by `make_named_copies.py`, through the runner, into the teacher-only folder, on the teacher's word:

- `--document "<marking folder>/<Assessment>/Results/Class Results.tex"` writes `Class Results
  (Names).pdf`, each identifier with its student's name beside it;
- `--grades "<marking folder>/<Assessment>/Results/Grades - <Assessment>.csv"` (or a `Levels - ...`
  table) writes `... (Names).csv` with the name first, ordered by section and then by name, for the
  teacher to copy into the report system. It refuses the whole table, writing nothing, when a cell holds
  a word from the mapping table or more than a number or a level.

You never open either: they are in the teacher-only folder.

## Left to you, in words: charts and summaries

The script builds the tables and lists above and nothing more. When the teacher wants more, build it
yourself from the grade and level tables, identifiers only, in a document of your own in the results
folder, and render every page and look:

- **Charts.** A bar chart of how many students reached each level, by category, or a dot per student
  per category (first submission on the left, revised on the right) shows how a class moved. Draw it
  with pgfplots in a `.tex` that holds identifiers only, or no student at all.
- **A test beside an assignment.** When a class has both, a table of each student's test percent beside
  their assignment percent, by category, shows who did well on one and not the other.
- **A marking summary.** The teacher's own notes on each student (the students they are concerned
  about, and why) are the teacher's to write. Keep the rows they wrote by hand when you update the
  numbers beside them, and never decide on your own who is "of concern".

Each says, like the script's document, when it was built and from which records, and is built again
after any change to a mark or a level.

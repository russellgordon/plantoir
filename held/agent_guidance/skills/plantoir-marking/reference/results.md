# The class's results

What `scripts/class_results.py` builds from the marks records, what it reads, and what it leaves to you.
Everything here is the default for every teacher; the teacher's How I Teach page and `Marking Settings.md`
come first, and the script is a starting point like the others (copy it into `Scripts/`, adapt it, run
`--self-test`).

## What it reads

- **Marks records** of a test, `<Assessment>/Marks/Section N/Student A.json`, each checked with the
  `plantoir-test-authoring` skill's `check_kit.py` against the kit given after the assessment
  (`--kit`). Totals are counted from the points; a record never holds one.
- **Level records**, `<Assessment>/Records/Section N/Student A.json`, read ONLY IF that folder holds any:

  ```json
  {"identifier": "Student A", "section": 1, "levels": {"K": {"first": "3", "revised": "3+"}, "T": {"first": "2", "revised": null}}}
  ```

  No skill writes these for a coding assignment yet. If the teacher gives you the levels of an
  assessment marked some other way, by identifier only, you may write them in this shape. When an
  assessment has no level record, or no `Marks/` folder, the document says so in words, so nobody
  reads a missing part as a part with nothing in it.
- **The sheets**, `<Assessment>/Sheets/Section N/Student A - Marks by Question.tex`, when they are
  there: the marks line `build_test_sheet.py` writes at the top of each.
- **`Marking Settings.md`**: the `- Half marks:` line (yes or no, then at most the teacher's words and
  the date in brackets); the teacher's scale on the `- Levels scale:` line (`none`, or each level and its
  percent, highest first; `- Levels scale: 4 80, 3 70, 2 60, 1 50` shows the format only); and how a
  percentage is rounded, the `- Percentages:` line (`whole numbers, half up`, `one decimal, half up` or
  `whole numbers, down`; whole numbers, half up when there is none). The scale is always the teacher's.
  Never fill it in yourself, from another teacher's scale or from an example; ask, and record the answer
  with the teacher's words and the date.
- **The identifiers**: `Student A` to `Student ZZ`, matched in full, one rule in every script. Papers
  named another way are renamed first (`redact_scans.py --name-papers`).
- **The kit's `voided`**: the points voided for the whole class. Every marks record must void exactly
  those points; a record that voids others stops the build, named by identifier with the points.

## What it writes, into the marking folder

- `Class Results.tex` and `Class Results.pdf`: when it was built and a fingerprint of everything it
  read, which parts had no records, how the numbers are made; then, section by section, each student's
  marks by category and total with the section's means; the levels first and revised; "No revised
  levels", the students whose level record has no revised level, by identifier; and "No level record",
  the students marked in the run who have no level record for that assessment.
- `Grades - <Assessment>.csv`: one row per student, marks, out of and percent by category and for the
  total, and the level from the scale when there is one.
- `Levels - <Assessment>.csv`: one row per student with a level record: first, revised, the level that
  stands (the revised one, or the first when there is none), and its percent from the scale.

Every row of both tables ends with `built`: the build time and the fingerprint. The fingerprint covers
the kit, the records, the sheets, `Marking Settings.md` and the identifier pattern, so a document built
from other records or another scale has another fingerprint. Every student is written by identifier; in
the `.tex` each is `\student{section}{identifier}`, the one place the named step puts a name.

The documents are built in a hidden folder and put in place only when every one is built. The last run's
documents are first renamed "earlier run, do not use", and removed once the new ones are in place, so a
build that stops part way leaves no document that looks finished.

## How the numbers are made

- A category's mark is the sum of its points earned, out of its points. A point the teacher removed from
  the count (the kit's `voided`) counts for no one: it is in neither the mark nor the out of, here and
  on the feedback sheet, so no one shows more than the total. A category with nothing counted is shown
  as "not counted" and left out of the means; it is never 0 percent.
- The total is the sum of the categories. There is no weighting unless the teacher asks for one; then
  change it in the copy in `Scripts/` and say on the document how it is weighted.
- A percentage is rounded once, as the `- Percentages:` line says, and that printed value is the one a
  level is read from: a row never shows one percentage at two levels.
- A mark's level is the highest level on the scale at or below that percentage. A teacher who reads
  levels another way (the nearest level, say) changes `LEVEL_FROM_PERCENT` in the copy.
- A level's percent is the scale's.

## When it stops, and what it says

It puts nothing new in place, names the identifier and the reason, and exits 1, when:

- a sheet's marks line no longer gives the totals its record gives (it names both numbers), names a
  category the kit does not have, or cannot be read. The student was told something the record no
  longer says: build that student's sheets again with `build_test_sheet.py`, tell the teacher, then
  run this again;
- a sheet has no marks record beside it (the record was renamed, moved or deleted);
- a file or folder in `Marks/` or `Records/` is not named `Section N/<identifier>.json` (a rescan or a
  copy saved beside a record, or a name not like the identifiers); it is counted and never named, and
  the teacher says which file is the right one;
- an assessment's `Marks/` folder holds no record;
- a record voids other points than the kit's `voided` (the ruling is recorded once, in the kit, and
  copied into every record);
- a record has a half mark and the settings record no yes to half marks;
- a level is not on the teacher's scale, or the scale gives a level or a percent twice, a percent over
  100, or is written twice; or the `- Percentages:` line names a rounding the script does not know; or
  a settings line is written nearly as one it reads (`- Percentage:`), so it would be passed over;
- a record's identifier or section is not its file's and folder's, a record is not in the shape above,
  or the kit checker refuses a record.

A record with a point not yet marked is left out of the documents and named by identifier, and the run
exits 1. Hidden files (a name starting with a dot) are passed over. The script never says a document is
correct or complete: it says what it read, what it compared, and what it wrote.

**After any change to a mark, a level or the settings, run it again**, and then make the named copies
again: the documents do not change by themselves, and a named copy keeps the build time and fingerprint
of the run it came from. Tell the teacher when it was last run.

## Names, at the end

The named copy of the document and the named grade table for the school's report system are made only
by `make_named_copies.py`, through the runner, into the teacher-only folder, on the teacher's word:

- `--document "<marking folder>/<Assessment>/Results/Class Results.tex"` writes `Class Results
  (Names).pdf`, each identifier with its student's name beside it, and checks each student's name and
  identifier are on the page;
- `--grades "<marking folder>/<Assessment>/Results/Grades - <Assessment>.csv"` (or a `Levels - ...`
  table) writes `... (Names).csv` with the name first, ordered by section and then by name, the `built`
  column carried through, for the teacher to copy into the report system. It refuses the whole table,
  writing nothing, when a cell holds a word from the mapping table or more than a number or a level,
  when the table has no `built` column, or when its rows were built at different times. It prints the
  build time and fingerprint, so the teacher can match the named table to the results.

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

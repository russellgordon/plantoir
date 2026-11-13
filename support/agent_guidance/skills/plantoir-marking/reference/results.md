# The class's results

What `scripts/class_results.py` builds from the marks records, what it reads, and what it leaves to you.
Everything here is the default for every teacher; the teacher's How I Teach page and `Marking Settings.md`
come first, and the script is a starting point like the others (copy it into `Scripts/`, adapt it, run
`--self-test`).

## The numbers a marked test shows

Russell, 2026-11-13, for every teacher:

- **By category only.** Results are shown by category (K, T, C, A as the kit names them), each out of its
  points and as a percentage. **There is no overall mark or percentage, ever**: not on the feedback
  sheet, not in the class's results, not in the grade table for a report system. Nothing adds the
  categories into one figure.
- **No level on a test.** A test marked by points never mentions levels: no level column, no levels
  scale, no sentence about levels. Levels belong to work marked against a rubric or success criteria,
  which this skill does not mark yet.
- **A voided point is a bonus.** A point the teacher voided for the class (recorded once, in the kit's
  `voided`, and copied into every record) leaves the out of for everyone, and a student who earned it
  keeps the mark. The category shows the real figure: 2 out of 1 reads 200%.

## What it reads

- **Marks records** of a test, `<Assessment>/Marks/Section N/Student A.json`, each checked with the
  `plantoir-test-authoring` skill's `check_kit.py` against the kit given after the assessment
  (`--kit`). The marks by category are counted from the points; a record never holds them.
- **The sheets**, `<Assessment>/Sheets/Section N/Student A - Marks by Question.tex`, when they are
  there: the marks line `build_test_sheet.py` writes at the top of each.
- **`Marking Settings.md`**: the `- Half marks:` line (yes or no, then at most the teacher's words and
  the date in brackets), and how a percentage is rounded, the `- Percentages:` line (`whole numbers,
  half up`, `one decimal, half up` or `whole numbers, down`; whole numbers, half up when there is none).
  Any other line, a levels scale included, is not read.
- **The identifiers**: `Student A` to `Student ZZ`, matched in full, one rule in every script. Papers
  named another way are renamed first (`redact_scans.py --name-papers`).
- **The kit's `voided`**: the points voided for the whole class. Every marks record must void exactly
  those points; a record that voids others stops the build, named by identifier with the points.

## What it writes, into the marking folder

- `Class Results.tex` and `Class Results.pdf`: when it was built and a fingerprint of everything it
  read, how the numbers are made; then, section by section, each student's marks by category, with the
  section's mean for each category.
- `Grades - <Assessment>.csv`: one row per student, marks, out of and percent by category.

Every row ends with `built`: the build time and the fingerprint. The fingerprint covers the kit, the
records, the sheets, `Marking Settings.md` and the identifier pattern, so a document built from other
records or other settings has another fingerprint. Every student is written by identifier; in the `.tex`
each is `\student{section}{identifier}`, the one place the named step puts a name.

The documents are built in a hidden folder and put in place only when every one is built. The last run's
documents are first renamed "earlier run, do not use", and removed once the new ones are in place, so a
build that stops part way leaves no document that looks finished.

## How the numbers are made

- A category's mark is the sum of its points earned, voided points included; its out of is its points
  that are not voided. A category with no point left to count reads "not counted" for a student who
  earned nothing in it, and shows the bonus (`1/0`, with no percentage) for one who did; it is left out
  of the means and is never 0 percent.
- A percentage is rounded once, as the `- Percentages:` line says.

## When it stops, and what it says

It puts nothing new in place, names the identifier and the reason, and exits 1, when:

- a sheet's marks line no longer gives the marks its record gives (it names both numbers), names a
  category the kit does not have, or cannot be read. The student was told something the record no
  longer says: build that student's sheets again with `build_test_sheet.py`, tell the teacher, then
  run this again;
- a sheet has no marks record beside it (the record was renamed, moved or deleted);
- a file or folder in `Marks/` is not named `Section N/<identifier>.json` (a rescan or a copy saved
  beside a record, or a name not like the identifiers); it is counted and never named, and the teacher
  says which file is the right one;
- an assessment's `Marks/` folder holds no record;
- a record voids other points than the kit's `voided` (the ruling is recorded once, in the kit, and
  copied into every record);
- a record has a half mark and the settings record no yes to half marks;
- the `- Percentages:` line names a rounding the script does not know, or is written twice; or a settings
  line is written nearly as one it reads (`- Percentage:`), so it would be passed over;
- a record's identifier or section is not its file's and folder's, a record is not in the shape above,
  or the kit checker refuses a record.

A record with a point not yet marked is left out of the documents and named by identifier, and the run
exits 1. Hidden files (a name starting with a dot) are passed over. The script never says a document is
correct or complete: it says what it read, what it compared, and what it wrote.

**After any change to a mark or the settings, run it again**, and then make the named copies again: the
documents do not change by themselves, and a named copy keeps the build time and fingerprint of the run
it came from. Tell the teacher when it was last run.

## Names, at the end

The named copy of the document and the named grade table for the school's report system are made only on
the teacher's word, by "Put names on the sheets" (`plantoir-marking` section 15), which runs
`make_named_copies.py` through the runner into the teacher-only folder:

- `--document` writes `Class Results (Names).pdf`, each identifier with its student's name beside it, and
  checks each student's name and identifier are on the page;
- `--grades` writes `... (Names).csv` with the name first, ordered by section and then by name, the
  `built` column carried through, for the teacher to copy into the report system. It refuses the whole
  table, writing nothing, when a cell holds a word from the mapping table or anything but a number, when
  a column is a level or an overall mark, when the table has no `built` column, or when its rows were
  built at different times. It prints the build time and fingerprint, so the teacher can match the named
  table to the results.

You never open either: they are in the teacher-only folder.

## Left to you, in words: charts and summaries

The script builds the tables above and nothing more. When the teacher wants more, build it yourself from
the grade table, identifiers only, in a document of your own in the results folder (or the assessment's
`Work` folder while you draft it), and render every page and look:

- **Charts.** A bar chart of each category's percentages across the class, or a dot per student per
  category, shows where a class is strong. Draw it with pgfplots in a `.tex` that holds identifiers
  only, or no student at all. By category, never an overall figure, and never a level for a test.
- **A test beside an assignment.** When a class has both, a table of each student's test percent beside
  their assignment result, by category, shows who did well on one and not the other.
- **A marking summary.** The teacher's own notes on each student (the students they are concerned
  about, and why) are the teacher's to write. Keep the rows they wrote by hand when you update the
  numbers beside them, and never decide on your own who is "of concern".

Each says, like the script's document, when it was built and from which records, and is built again
after any change to a mark.

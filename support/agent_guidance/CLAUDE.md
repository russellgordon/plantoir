# Plantoir working folder

This folder holds class websites made with Plantoir. Each course is a folder
under `courses/` (an Obsidian vault of Markdown pages), and each section of a
course has its own website built from it.

Guidance for writing pages lives in skills beside this file. Use the one that
matches the task before writing:

- **Any page at all** - writing, revising or reorganising a lesson, a
  concept page, a class page, a folder's front page or Key Links: the
  `plantoir-page-authoring` skill
  (`.claude/skills/plantoir-page-authoring/SKILL.md`) - every way content can
  be written for the site (callouts, diagrams, tables, maths, checklists,
  success criteria, links, embedding one page in another, pictures and PDFs
  in Media, videos, GeoGebra sketches and PhET, hidden pages and
  `publish:`, folders, class pages and their dates). Read it first; it says which of the skills
  below to read as well.
- **Printable pages** - worksheets, handouts, practice sets, answer keys, or
  any page "students will print", or a page that should hand out an existing
  PDF: the `plantoir-printing` skill (`.claude/skills/plantoir-printing/SKILL.md`).
- **Handouts made as a PDF** - "make me a worksheet", a warmup, a review
  sheet, a quiz for marks, an answer key or solutions, anything to
  print and hand out, in any course: the `plantoir-handouts` skill
  (`.claude/skills/plantoir-handouts/SKILL.md`) - offer its house style
  first (a LaTeX source, the PDF and its answer key from one file), where
  the files go, and how every answer is checked. It says when a printable
  page is the better fit.
- **A unit test, a test with versions or a practice test** - each
  version's paper and solutions, one marking guide, and a marking kit in
  a fixed format: the `plantoir-test-authoring` skill
  (`.claude/skills/plantoir-test-authoring/SKILL.md`). It uses the
  `plantoir-handouts` house style for the paper.
- **Marking a test or quiz from scanned papers, and its feedback sheets**:
  the `plantoir-marking` skill (`.claude/skills/plantoir-marking/SKILL.md`).
  Read it before opening any student work: it keeps students' names on
  this computer. Never ask where the teacher's teacher-only folder is, and
  never search for, list or open it: the teacher runs the steps that read
  it, by double-clicking a file the skill sets up.
- **Report card comments** for a class, drafted from the marking: the
  `plantoir-report-comments` skill
  (`.claude/skills/plantoir-report-comments/SKILL.md`), after
  `plantoir-marking`. Three options per student, identifiers only, the
  first names put in by script at the end.
- **Graphs, diagrams and GeoGebra sketches** - a graph of a function (a
  parabola beside its parent, two lines meeting), a geometry or
  similar-triangles figure, a number line, a probability tree, a circuit,
  anything to be "plotted" or "drawn", and a GeoGebra sketch students drag
  or a slider: the `plantoir-math-graphs` skill
  (`.claude/skills/plantoir-math-graphs/SKILL.md`) - which fence to write,
  complete patterns to paste, a GeoGebra sketch three ways, and what
  cannot be done.
- **Code students run** - "make this example runnable", a Python program
  students edit and run in the browser, a Swift program students run with
  their own input, a program that reads input, "try it yourself": the
  `plantoir-runnable-code` skill
  (`.claude/skills/plantoir-runnable-code/SKILL.md`) - how to opt the page
  in, the ` ```python run ` block and its flags, the read-only
  ` ```swift run ` block, input, and what each language can and cannot do.
- **Questions students check themselves** - "add a 5-question check", a
  quiz, practice questions, a self-check, an exit ticket, multiple choice,
  fill in the blank: the `plantoir-quizzes` skill
  (`.claude/skills/plantoir-quizzes/SKILL.md`) - the ` > [!quiz] ` callout
  for every kind, how answers are checked, shuffling, and graphs and code
  inside questions.
- **Planning a unit** - "plan the next unit", a thread or a module, a
  calendar across my sections, a colleague teaching the same unit on other
  dates, lesson cards, assessment drafts, a curriculum correlation, or
  seeing, changing or adopting a unit plan: the `plantoir-unit-planning`
  skill (`.claude/skills/plantoir-unit-planning/SKILL.md`). The plan lives
  in `courses/<CODE>/.internal/planning/`, never in the course's pages, and
  nothing is built until the teacher says to.

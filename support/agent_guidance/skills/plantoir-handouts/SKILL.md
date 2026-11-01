---
name: plantoir-handouts
description: Use when a teacher asks for help making something to print and hand out - a worksheet, warmup, review sheet, practice set, quiz, test, answer key or solutions - or asks for one to be made, in any course. Offers the house style (a LaTeX source compiled to a PDF, with its answer key from the same file), says where the files go (and remembers the folder for the course), how the page looks, how tables are bordered, aligned and turned, how far a graph is drawn and when it has arrowheads, how the answer key keeps the question copy's layout, the finite-difference scaffold, task cards, how quizzes and tests differ, and how every answer is checked before handing over.
---

# Making a printed handout in the house style

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. Paper handed out in class can come from two places, and they are
meant to look the same: a page of the site printed with its Print button,
and a PDF made in this house style. This file is managed by Plantoir and is
replaced when Plantoir updates; do not edit it.

## 1. Offer the house style first

"Handout" here means anything that will be printed: a worksheet, a warmup,
a review sheet, a practice set, a quiz, a test, an answer key, or a
solutions set. When a teacher asks for one, in any course, offer the house
style below as the starting point, in one or two sentences:

- **A PDF in the house style** (this skill): a LaTeX source compiled to
  `Name.pdf`, with the answer key `Name - Answers.pdf` made from the same
  source. Best for paper that is only ever printed. A quiz or test for
  marks is usually printed this way; whether it also goes on the class
  website is the teacher's call - ask.
- **A page on the class website that prints**: the `plantoir-printing` skill
  (`.claude/skills/plantoir-printing/SKILL.md`, the same file is at
  `.agents/skills/plantoir-printing/SKILL.md`). Best when students should
  also see it online.

Do not build it as HTML, a Word file or anything else unless the teacher
asks for that. If the teacher has already said which they want, do that
without asking again.

## 2. Before writing anything

- **Start from an existing source.** Ask whether the teacher has a handout
  in this style already (a `.tex` file with `\qa` in it), or look beside
  where this one will go. Copy the closest one and reuse its preamble,
  macros and look rather than writing a new preamble. With nothing to start
  from, copy the starters beside this file: `starters/Handout.tex` with
  `starters/Handout - Answers.tex`, or `starters/Quiz.tex` with
  `starters/Quiz - Solutions.tex` for a quiz or test. Copy them, never edit
  them here.
- **Where the files go: never inside `courses/`.** Every file in a course
  folder that is not a page is copied to the class website when it is
  built, so a `.tex` source or an answer key kept there is one students can
  download. The sources, their `- Answers` wrappers and every PDF live in
  one folder per course, outside the course, and the course remembers it:
  - **Read `courses/<CODE>/.internal/handouts/handouts.json` first.** If it
    is there and the folder it names exists, use that folder, and say it
    back to the teacher every time ("I'll keep this in ..."), so a folder
    from last school year is noticed rather than reused unseen.
  - **If the file is missing, or its folder is not there** (another
    computer, a renamed folder), ask the teacher where to keep this
    course's handouts: a folder of their own outside `courses/`, such as
    `handouts/<CODE>/` in their Documents folder. Inside it they may keep a
    folder per unit and per day (`Unit 2/Day 3/`); follow what is there.
    Then write the file - creating the `handouts` folder inside
    `.internal` - and tell the teacher you did:

    ```json
    {"folder": "/Users/name/Documents/handouts/MPM2D", "teacherSaid": "keep them in Documents, handouts, MPM2D", "recorded": "2026-10-31"}
    ```

    `folder` is the full path, `teacherSaid` their own words, `recorded`
    today's date. A new answer replaces the file. This is the one file in
    a folder whose name starts with a dot that you may write; leave
    everything else under `.internal` alone. It lives there because it
    travels with the course (a backup, an archive, a restore) and is never
    copied to the class website.
- **On the class website, only the PDF a page hands out.** Copy it into
  the course's `Media` folder and follow section 4 of `plantoir-printing`:
  - `Name.pdf` - the default.
  - A merged `Name - with Answers.pdf` (the questions, then the answer
    key, as one file) for a worksheet or handout whose page gives the
    answers as well, when the teacher wants that:
    `pdfunite "Name.pdf" "Name - Answers.pdf" "Name - with Answers.pdf"`
    (`pdfunite` comes with Poppler, like `pdftoppm`).
  - A quiz or test may go on the website if the teacher wants it there;
    its **solutions never do**.
  - Never a `.tex`. After every change to the source, compile again and
    copy the PDF into `Media` again, so the site never hands out an old
    copy.
- **The names.** `Name.tex` and `Name - Answers.tex` for a worksheet or
  handout; `Name.tex` and `Name - Solutions.tex` for a quiz or test. Check
  that a new name does not differ from an existing file in that folder only
  by capital letters: on most computers that is the same file, and the
  compile would overwrite it.
- **The corners: read the course's print settings.** They are in
  `courses/<CODE>/course_config.json`, and the class website lays out its
  printed pages from them (section 5 says how):
  - `print_school_name` - the school's name. If it is missing or empty,
    ask the teacher for it, and mention that putting it in Course
    Settings, under Printing, makes the website's printed pages carry it
    too.
  - `print_school_name_at` - where the school's name goes: `header_left`
    (top left, also when the key is missing), `footer_left` (bottom left)
    or `none` (not printed).
  - `print_course_code_at` - where the course code goes: `footer_left`
    (also when missing), `header_left` or `none`.
  - `print_blanks` - the blanks a student fills in: any of `name`, `date`,
    `class_number`, always printed in that order. Missing (or `null`) means
    Name and Date only; an empty list means none.

  The course code is the folder's code (`course_code` if a reference
  course's folder has a year after it), in capitals. Do not edit
  `course_config.json` yourself unless the teacher asks.

## 3. One source, two outputs

`Name.tex` holds the questions and the answers together, behind a switch
defined in its preamble (the starters have it):

```latex
\newif\ifanswers
\ifdefined\showanswers \answerstrue \fi
\newcommand{\qa}[2]{\ifanswers #2\else #1\fi}   % question, or its answer
\newcommand{\onlyq}[1]{\ifanswers\else #1\fi}   % questions only
\newcommand{\onlya}[1]{\ifanswers #1\fi}        % answers only
```

`Name - Answers.tex` (or `Name - Solutions.tex`) is two lines:

```latex
\def\showanswers{}
\input{Name.tex}
```

Compile both, so `Name.pdf` and `Name - Answers.pdf` sit beside the
source.

**The answer key keeps the question copy's layout.** A student holds the
two side by side, so what they wrote on and what they check against must
look the same:

- A table is the same table in both: the same orientation (vertical in
  both, or horizontal in both - section 9), the same columns, the same
  alignment and padding, the same row height.
- A graph is the same grid in both: the same axis ranges, the same scale
  and the same printed size. The question copy shows the empty grid the
  student draws on; the key shows the same grid with the answer on it.
- So author each table and each graph ONCE, outside the switch, and switch
  only what changes: the cell contents (`$1$ & \qa{}{$-2$} \\`) and the
  plotted answer (`\onlya{\addplot ...;}` inside the `axis`). The starter's
  questions 2 and 3 do exactly this.
- Never a vertical table in the question copy with a horizontal one in the
  key, never a smaller, more compressed or differently scaled grid in the
  key, and never a grid that appears only in the key.

## 4. The look

- `\documentclass[11pt]{article}`, letter paper (a test may use legal
  paper), 0.75in margins with 0.9in at the bottom, `lmodern` with
  `\usepackage[T1]{fontenc}`, no paragraph indent.
- A bold sans title (`{\LARGE\bfseries\sffamily \doctitle}`), then a grey
  subtitle line of instructions.
- `tasks` columns for a), b), c) parts. The answer key keeps the
  worksheet's column count.
- `pgfplots` for graphs. How far a graph is drawn, and when it has
  arrowheads, is in section 12.
- Tables: full borders, alignment by column, decimals and tables side by
  side are in section 9; the finite-difference scaffold in section 10;
  task cards in section 11.
- Worked examples in peach `tcolorbox` boxes with dark-red sans titles. The
  answer key hides the worked examples and gives final answers only, with a
  graph where the answer is a graph.

## 5. Header and footer

All four corners `\small\sffamily\color{gray}`, no rule under the header,
with `fancyhdr` and `lastpage`, laid out as the course's print settings
do (section 2), so paper from the website and from here looks the same.
With the school's name top left, the course code bottom left and all three
blanks, that is:

```latex
\pagestyle{fancy}
\fancyhf{}
\renewcommand{\headrulewidth}{0pt}
\newcommand{\fillblank}[2]{#1 \rule[-0.15em]{#2}{0.4pt}}
\fancyhead[L]{\small\sffamily\color{gray}School Name}
\fancyhead[R]{\small\sffamily\color{gray}\fillblank{Name}{3.2cm}\quad\fillblank{Date}{2.2cm}\quad\fillblank{Class \#}{1.4cm}}
\fancyfoot[L]{\small\sffamily\color{gray}\doctitle\ $\cdot$ COURSE}
\fancyfoot[R]{\small\sffamily\color{gray}Page \thepage\ of \pageref{LastPage}}
```

- **Top left**: whatever `print_school_name_at` and `print_course_code_at`
  put at `header_left` - by default the school's name. Two in one corner
  read `School Name $\cdot$ CODE`, school first.
- **Top right**: the blanks `print_blanks` lists, in the order Name, Date,
  Class #, at the widths above. Leave out the `\fillblank` of any it does
  not list (by default Class # is left out).
- **Bottom left**: the handout's title, then whatever is placed at
  `footer_left` - by default the course code of the course it is for
  (`MPM2D`, `ICS3U`, `SCH3U`, ...). With nothing placed there, the title
  alone.
- **Bottom right**: `Page 1 of 3`.

## 6. Quizzes and tests

- A wider left margin holds a marks column, with slash-style category
  totals such as `\score{K 10}` beside each question.
- A second version is a separate source with parallel questions, never a
  switch inside one file.
- In the solutions, working is dark blue and balancing steps (what is done
  to both sides) light red, so they stay distinct when printed in greyscale.

`starters/Quiz.tex` has all three.

## 7. Answers are checked, and new questions are reviewed

- **Verify every answer independently**, by solving it again a different
  way or by substituting it back. An answer key with one wrong answer costs
  the teacher a class.
- **A newly written question set** (a new test, a rewrite, a practice set)
  is reviewed by a separate agent from the one that wrote it - for fit to
  what the teacher asked and for answer accuracy, re-solving every answer
  from scratch. Fix what it finds before the final compile. If you cannot
  start a second agent, say plainly that the questions have not had that
  second check.
- **Adapting a textbook page**: renumber the questions that are kept.

## 8. Compile, look at every page, leave the folder clean

```bash
tectonic "Name.tex"
tectonic "Name - Answers.tex"
```

`tectonic` writes only the PDF beside the source (its first run needs the
internet, once). If `tectonic` is not installed, say so and point the
teacher at https://tectonic-typesetting.github.io (on a Mac with Homebrew,
`brew install tectonic`); do not switch to another format without asking.

Then render every page of both PDFs into a temporary folder OUTSIDE the
working folder, and look at each image before handing over - a column that
ran off the page, a box split across two pages, a graph in the wrong place
or an answer showing on the student copy are only found this way:

```bash
mkdir -p /tmp/handout-check
pdftoppm -png -r 80 "Name.pdf" /tmp/handout-check/Name
pdftoppm -png -r 80 "Name - Answers.pdf" /tmp/handout-check/Answers
```

(Any temporary folder outside the working folder will do. `pdftoppm`
comes with Poppler: `brew install poppler` on a Mac.) If you
cannot render the pages, tell the teacher they have not been looked at.

Leave no build files behind. Of THIS handout's files, only `Name.tex`,
`Name - Answers.tex`, `Name.pdf` and `Name - Answers.pdf` (and a merged
`Name - with Answers.pdf`, if the page links one) stay, and the rendered
images are deleted. The folder holds the course's other handouts too, and
perhaps folders for units and days: leave every file you did not make in
this session exactly as it is.

## 9. Tables

`patterns/tables.tex` beside this file holds the four patterns below,
compiled and checked, with what was measured in its opening comment. The
starters carry the preamble lines (`nicematrix`, the `tablehead` colour,
`\headstrut`, `\arraystretch` 1.2, `\valuecol` with `\setvaluecol`, and
`\rowstrut`). Copy a pattern into the handout; never edit it here.

- **A full outer border on every table**: fill-in tables students
  complete, tables built by a macro, tables on task cards and tables drawn
  in TikZ. In a `NiceTabular`, `[hvlines]`; in a `tabular`, `|` at both
  ends of the column spec and `\hline` above the heading row and below the
  last row; in TikZ, a closing rectangle. Never an open or top-less table.
- **A shaded heading row: `NiceTabular` for every new table** (pattern A),
  with `\CodeBefore \rowcolor{tablehead}{1} \Body`. It paints the colour
  first and every rule after it. A heading shaded with `\cellcolor` (also
  through a small heading macro that wraps it) and one shaded with a bare
  `\rowcolor` draw exactly the same thing: the fill lands on top of the
  rule above it and the rule on its left, and at 80 dpi - the check in
  section 8, and about what a screen shows - the table looks open at the
  top. Switching one for the other fixes nothing.
- **An existing `tabular` that stays a `tabular`** (pattern B):
  `\rowcolor{tablehead}[\dimexpr\tabcolsep-0.5pt\relax][\dimexpr\tabcolsep-0.5pt\relax]`
  at the START of the heading row, with both of those arguments and no
  `\cellcolor` in any cell. That keeps the side rules, but NOT always the
  top one: at 80 dpi the top rule vanishes at about half of the places a
  table can sit on the page (6 of 12 measured), exactly as with a bare
  `\rowcolor`, and a 600 dpi look never shows it. So look at the table's
  top edge in the 80 dpi pages of section 8; if it is gone, rewrite the
  table as pattern A. The one thing that closes pattern B is a preamble
  that redraws every `tabular`'s outer frame last - a teacher's own
  worksheet template may carry one, such as a block headed "Outer border,
  drawn last" - so if the preamble you copied has that block, keep it and
  pattern B is whole (0 of 12 positions lost, measured). Do not add that
  block to a handout that lacks it; use pattern A. A table being rewritten
  anyway becomes pattern A. Never mix the two kinds in one table.
- **Alignment is decided per column, by that column's values:**
  - A column holding **any negative value**, or **mixing whole numbers
    and decimals**, is right-aligned, with about 0.25 cm of padding before
    the rule so the units digits and the decimal points line up and the
    numbers clear it: `w{r}{\valuecol}<{\hspace{0.25cm}}` (the width rule
    below), or `r<{\hspace{0.25cm}}`. That includes a column of zeros and
    negatives (0, -3, -4, -3, 0), a column that is all negative (-6, -10,
    -14), and a column such as 9.0, 10.5, 12.0 - centring that one shifts
    the decimal point by half a digit from row to row.
  - Any other column of numbers is centred (`c`): no negative value, and
    either all whole numbers or all decimals. Zero is not negative.
  - The heading over a right-aligned column stays centred:
    `\multicolumn{1}{c}{$y$}` in a `NiceTabular`; in a `tabular` it repeats
    the rules, `\multicolumn{1}{|c|}{$x$}` over the first column and
    `\multicolumn{1}{c|}{$y$}` over the others.
  - A Power column of expressions such as $2^{-3}$ stays centred; its
    Value column follows the two rules above. Word columns are left as
    they are.
- **The x and y columns are the same width**, and so are the first- and
  second-difference columns, so a right-aligned number ends at the same
  offset in each column. The width comes from the widest value in EITHER
  column: `\setvaluecol{$-18$}` (inside the table's group, with that
  table's widest value) sets `\valuecol` to it plus 0.5 cm, and each value
  column is `w{c}{\valuecol}` or `w{r}{\valuecol}<{\hspace{0.25cm}}`. A
  heading wider than every value (`$h$ (m)`) counts as the widest. A
  column students write in may be set wider for room
  (`\setlength{\valuecol}{1.6cm}`), but the x and y columns still share
  it. Never `c` beside `r` with each as wide as its own contents.
- **Every value has a little space above and below it.** The first row of
  values never sits against the heading rule: `\arraystretch` 1.2 (the
  starters set it; at 1.0 a digit sat half as far below the rule above it
  as above the rule below). A **tall row** with room to write - a skeleton
  difference table - keeps its value centred in the row:
  `\rowstrut{3em}` at the start of each such row (pattern D), never a
  large `\arraystretch`, which puts the value low in its row (measured
  1.2 mm below the middle at 2.6; `\rowstrut` about 0.1 mm).
- **Which way a table runs.** A table of values may be horizontal - two
  rows, $x$ across the top and $y$ below - wherever students are NOT asked
  to compute finite differences from it. **Any table used for finite
  differences is vertical** ($x$ and $y$ as columns), so the differences
  can sit beside the rows they come from (section 10). Whichever way the
  question copy's table runs, the answer key's runs the same way
  (section 3).
- **Decimals**: in a column that mixes whole numbers and decimals, write
  every value to the same places - 31.0 beside 18.5, 0.0 beside 0.5, 1.00
  beside 0.80 - and right-align it with the padding above. Never a bare
  whole number and never an invisible `\phantom{.5}`. A column of whole
  numbers gets no decimals.
- **Tables side by side** (pattern C: three fill-in tables across a
  warmup, a scaffold beside two tables, a), b), c) of one question) share
  a top edge and, where they list the same x values, the same row height,
  so rows line up across the page: each in a `[t]` minipage that starts
  with `\vspace{0pt}`, `[t]` on the table, one `\arraystretch` for the
  row, and `\headstrut` in every heading row (inside the `\multicolumn`
  where the heading cell is one), so a one-line heading is as tall as a
  two-line `\Block{}{First\\differences}`.
- **Look at every table at 80 dpi and at 600 dpi.** At 80 dpi (section
  8's pages) the top edge of a shaded heading must be there - that is
  where a fill covering a rule shows, and 600 dpi hides it. At 600 dpi,
  render the page holding the table and look at its edges up close: every
  outer rule one continuous line, no notch where a row's rule meets a side
  rule.

  ```bash
  pdftoppm -png -r 600 -f 2 -l 2 "Name.pdf" /tmp/handout-check/table-page-2
  ```

## 10. Finite-difference scaffold

Whenever first or second differences come up on a given day, the **first**
table of that day carries a scaffold figure; later tables that day are
plain. `patterns/finite_differences.tex` beside this file is a complete
example to copy and change the numbers in (it needs nothing but LaTeX);
`patterns/finite_differences.py` writes the same picture for any table
when Python is available. Run it, never import it - from the working
folder, where this skill is at `.claude/skills/plantoir-handouts` (the same
files are at `.agents/skills/plantoir-handouts`):

```bash
python3 .claude/skills/plantoir-handouts/patterns/finite_differences.py --x -2 -1 0 1 2 --y 1 -2 -3 -2 1
```

It prints a `tikzpicture` that uses the handout's own `\qa` switch, so one
source makes both copies. The figure:

- The x, y table on the left, vertical (as every table used for finite
  differences is), bordered and aligned as section 9 says, its x and y
  columns one width and each value centred in its row. The two columns of
  differences are one width too, so their lines sit at the same offset
  in each.
- Between consecutive rows, a curved arrow that **starts at the lower
  value and points up** to the one above, labelled with the whole
  subtraction, **lower minus upper**, negatives in parentheses:
  `1 - (-2) = 3`. The lines of a column line up on their equals signs.
- A second column of arrows and subtractions for second differences, such
  as `2 - (-2) = 4`.
- The headings "First differences" and "Second differences" over the
  columns, and under the figure a small grey caption: "Each difference is
  the lower value minus the one above it."
- **The student copy**, where students compute the differences: the first
  **two** first differences worked and the first second difference worked,
  so every value a worked line uses is already on the sheet; the rest are
  short blank rules that stop clear of the next column's arrows. The
  answer key has every line. Where the y values themselves are what
  students compute, nothing is worked (`--nothing-worked`).
- The first time differences appear in a unit (a warmup that only uses
  first differences), the first-difference column only (`--columns 1`).
- **Never on a quiz, a test or a practice test.**

The same figure goes on a page as a ` ```tikz ` fence:
`plantoir-math-graphs` section 4E, or `--page --alt "..."` to print one.

## 11. Task cards

Each group has four empty Cartesian-plane templates on its whiteboard.

- A card never says "on the same axes", "on the same grid" or "on one
  grid": every relation it asks students to plot or sketch goes on its
  own grid, and comparing is side by side ("put it beside your graph of
  $y = x^2$ and compare").
- A card set asks a group for **at most four graphs in total**, counting
  the sketch prompts for a group that finishes early.
- A table on a card has a full border, as every table does (section 9).
- A page that discusses the cards repeats each card's wording word for
  word.

## 12. Graphs: how far the line goes, and arrowheads

Decide it per graph, by one question: **does the relation have a
context?**

- **An abstract relation** - no context: $y = -x^2 + 6x - 5$, a line such
  as $y = 2x - 1$, a parent parabola. The relation goes on past the points
  that were plotted, so the graph does too: it is drawn **to the edge of
  the grid, with an arrowhead at each end**. The plotted points stay on it.
  In `pgfplots`, `<->, >=latex` on the `\addplot` and a `domain` that ends
  where the curve meets the edge of the grid:

  ```latex
  \addplot[thick, <->, >=latex, domain=-0.16:6.16, samples=50] {-x^2 + 6*x - 5};
  \addplot[only marks, mark=*] coordinates {(1,0) (2,3) (3,4) (4,3) (5,0)};
  ```

  Find each end by solving for where the curve leaves the grid: a line
  leaves through whichever edge it reaches first (on a grid from -6 to 6,
  $y = 2x - 1$ leaves at $x = -2.5$ and $x = 3.5$); this parabola meets
  $y = -6$ at $x = 3 \pm \sqrt{10}$, so -0.16 and 6.16. **Do not let the
  domain run past the edge**: the axis clips the curve there and the
  arrowheads are cut off with it (measured: `domain=-1:7` above draws no
  arrowheads at all). Stopping a little short of the edge is fine; past
  it is not.
- **A relation that models a context** - a bridge arch, a ball in flight,
  supply and demand, a cost that starts at zero items. The situation gives
  the graph its end points (the arch's two feet, the ball leaving the hand
  and landing, zero and the most that can be bought), so the graph **stops
  at those end points, with no arrowheads**:

  ```latex
  \addplot[thick, domain=0:40, samples=50] {-0.05*(x - 20)^2 + 20};   % the arch, foot to foot
  ```

  Mark an end point with a dot where it matters (`\addplot[only marks,
  mark=*] coordinates {(0,0) (40,0)};`).

The same rule holds on a page of the class website: `plantoir-math-graphs`
section 4 says how. Whatever the graph, the answer key draws it on the
same grid the question copy gives (section 3).

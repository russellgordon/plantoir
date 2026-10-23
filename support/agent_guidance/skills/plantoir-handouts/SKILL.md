---
name: plantoir-handouts
description: Use when a teacher asks for help making something to print and hand out - a worksheet, warmup, review sheet, practice set, quiz, test, answer key or solutions - or asks for one to be made, in any course. Offers the house style (a LaTeX source compiled to a PDF, with its answer key from the same file), says where the files go, how the page looks, how quizzes and tests differ, and how every answer is checked before handing over.
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
  download. Ask the teacher where they keep handouts; if they have no
  place, suggest a `handouts/<CODE>/` folder in this working folder, beside
  `courses/`. If the teacher also wants the handout on the class website,
  copy only `Name.pdf` (never the answers) into the course's `Media` folder
  and follow section 4 of `plantoir-printing`.
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

## 4. The look

- `\documentclass[11pt]{article}`, letter paper (a test may use legal
  paper), 0.75in margins with 0.9in at the bottom, `lmodern` with
  `\usepackage[T1]{fontenc}`, no paragraph indent.
- A bold sans title (`{\LARGE\bfseries\sffamily \doctitle}`), then a grey
  subtitle line of instructions.
- `tasks` columns for a), b), c) parts. The answer key keeps the
  worksheet's column count.
- `pgfplots` for graphs.
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

Leave no build files behind: only `Name.tex`, `Name - Answers.tex`,
`Name.pdf` and `Name - Answers.pdf` stay in the folder, and the rendered
images are deleted.

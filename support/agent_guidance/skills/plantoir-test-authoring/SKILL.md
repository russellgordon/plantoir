---
name: plantoir-test-authoring
description: Use when a teacher asks for a unit test, a test with more than one version, a practice test, or a quiz for marks with a marking guide, in any course. Builds the paper for each version and its solutions, one marking guide, a marking kit in a fixed format with no place for a name (answers.json and a marks template), a checks script where answers can be computed, a coverage table and, when wanted, a practice test, from only what the class was taught, with every answer re-solved by someone other than its writer. Uses the plantoir-handouts house style for the paper. Everything it drafts is for the teacher to review and decide.
---

# Writing a unit test, its solutions and its marking kit

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. A unit test is made outside the course, as paper, with
everything needed to mark it. This file is managed by Plantoir and is
replaced when Plantoir updates; do not edit it, and never write anything
inside this skill's folder (it is replaced whole, and a file written here
is lost). Copy from it instead.

The paper itself is made in the house style of the `plantoir-handouts`
skill (`.claude/skills/plantoir-handouts/SKILL.md`, the same file is at
`.agents/skills/plantoir-handouts/SKILL.md`): read its sections 2 to 8 and
14 before writing a question. A single quiz with no versions and no kit is
a handout, and that skill alone is enough for it.

## 1. The teacher decides

Say this in your first reply, every time, and keep it under the title of
the Marking Guide:

```text wrap
Everything I draft here (each question, each answer and each mark) is a suggestion for you to review. Please read and decide on all of it before it reaches a student; I draft, you decide.
```

## 2. Fixed, for every teacher

- **Only what the class was taught.** Ask the teacher for the day-by-day
  list of what the unit covered, or read it from the section's class pages
  and the pages they link (with Plantoir's tools connected, `list_pages`
  and `read_page`). Show the list back to the teacher before writing, and
  check every question against it. A question on something the class did
  not do is removed, however good it is.
- **No tricks: the concept is tested, never the reading of the question.**
  No double negatives, no buried "not", no options that differ by one small
  word, and a boundary shown plainly rather than hidden in the wording.
  The wording rules of `plantoir-handouts` section 14 apply to every
  question.
- **Versions are genuinely parallel.** Item by item: the same concept, the
  same number of steps, the same size of numbers, the same trap, the same
  reading load. The right answer sits under a different letter on each
  version, and no number a question gives is reused from one version to
  another, so a neighbour's paper is no help.
- **Every answer is re-solved from scratch by a reviewer who did not write
  it.** Write one brief holding everything a writer needs (what was taught,
  the teacher's choices from section 3, the house style), have one agent
  write the versions from it, then have a separate agent solve every
  question again without the solutions and compare. A second reviewer, a
  different agent again, fills in `Coverage.md` (each question against the
  class it was taught in, and each version against the others, item by
  item) and looks for trick wording. Fix what each finds, run the checks
  again (section 6), and only then compile the final copies. If you cannot
  start separate agents, say plainly that the test has had no independent
  check, and do not call it checked.
- **Never invent a question, scenario or example involving firearms or
  ammunition.** Choose a dice game, a race, a recipe or a trip instead. A
  teacher's own material, and curriculum content that requires the
  subject, are left alone.
- **The test, its solutions and its kit never go into the pages a class
  website is built from**: not into a course's folders, not into `Media`,
  not onto a page. Everything there that is not a page is copied to the
  class website. The one place under `courses/` where copies of the test's
  PDFs (each version's PDF and its solutions' PDF, never the Marking Guide
  or the kit) may go is a unit plan's own folder: each version's PDF into
  `courses/<CODE>/.internal/planning/<unit>/pdfs/`, and each solutions PDF
  into that unit's `Answer Keys` folder,
  `courses/<CODE>/.internal/planning/<unit>/Answer Keys/`, as the
  `plantoir-unit-planning` skill's section 6 says: that folder is never
  built into a class website, and a share of the plans holds back what is
  in `Answer Keys` unless the teacher chooses otherwise. Never a `.tex` file or the kit there. A
  practice test may go on the class website (section 8); a test's
  solutions and kit never do.

## 3. How this teacher writes tests, in this order

1. **The course's How I Teach page comes first.** If
   `courses/<CODE>/How I Teach.md` exists, read it (with Plantoir's tools
   connected, `read_how_i_teach` reads it) and keep to what it says about
   tests: the categories, the number of versions, the kinds of question,
   the time, the paper.
2. **Otherwise, ask, briefly, with plain choices**, and do not bring a test
   shape of your own:
   - the categories marks are counted in, and how the marks split (for an
     Ontario course code, offer the four achievement chart categories:
     Knowledge and Understanding, Thinking, Communication, Application;
     for any other course, ask what the school uses);
   - how many versions;
   - how long students have, and the paper size (letter, or legal for a
     longer test);
   - what kinds of question the course uses (choice, short answer,
     calculation, an extended answer, a source to analyse, code to trace
     or write).
   Say what you understood back to the teacher in one short list before
   writing.
3. **The template is offered, never applied.** The `plantoir-handouts`
   skill's section 13 holds one teacher's template, called "Lessons
   students can catch up on", and it has a test shape (below). Offer it, in
   one or two sentences, only to a teacher who has shown an interest in
   both things it bridges: lessons built from students' own thinking
   (constructivist practice, Thinking Classrooms) AND a school where
   students often miss significant class time (sports and team travel,
   weather days, illness, field trips and other school activities). Say it
   is one teacher's approach, use it only after they say yes, and only
   where their How I Teach page does not say otherwise. If they say no, do
   not offer it again in this conversation. If you cannot tell whether
   they have shown that interest, do not offer it.

   The template's test shape:
   - marks split evenly across the categories, one part per page, timed
     for students writing their first test in the course, and nothing on
     the front but the title, section, marks, time and the slash totals;
   - two versions per section, for alternate seats, on legal paper;
   - four kinds of part that mark well: choose (every wrong option a
     named misconception, listed on a misconception page of the Marking
     Guide); trace or carry out, marked with follow-through; explain, with
     nothing to compute; and write, where no answer is more than one line
     and any rule about what counts is stated in a banner. For another
     subject, propose the equivalent of each;
   - a practice test in the same shape with different numbers, its own
     solutions and a self-marking note, handed out from the course site
     (section 8).

## 4. Where the files go

In the course's handouts folder, which `plantoir-handouts` section 2 finds
from `courses/<CODE>/.internal/handouts/handouts.json` (ask, and write that
file, if it is missing), one folder per test:

```text wrap
<handouts folder>/<Test name>/
  Version A.tex, Version A - Solutions.tex, Version A.pdf, Version A - Solutions.pdf
  Version B.tex, ...
  Marking Guide.tex, Marking Guide.pdf
  Marking Kit/README.md, answers.json, marks-template.json
  Checks/check_answers.py        (where answers can be computed)
  Coverage.md
  Practice Test.tex, Practice Test - Solutions.tex and their PDFs (when made)
```

## 5. The papers, the guide and the kit

- **Each version** is a copy of `plantoir-handouts`' `starters/Quiz.tex`
  and `starters/Quiz - Solutions.tex`, renamed, with its title naming the
  version ("Unit 2 Test: Chemical Reactions, Version A"). A second version
  is a second pair of files with parallel questions, never a switch inside
  one file. The school line of the header is this teacher's own: read
  `print_school_name` from the course's settings as that skill's section 2
  says, and ask when it is empty. The starter's marks column carries each
  question's category and marks (`\score{T 4}`, in this teacher's own
  categories), and its front carries the slash totals. A teacher who counts
  no categories has one, such as `M` for Marks.
- **One Marking Guide for every version**: copy `templates/Marking
  Guide.tex` beside this file. It is filled in with a worked example (an
  invented science test); replace its content with this test's. One row for
  every point, under the point's ID, with what earns the mark and each
  version's answer, and the misconception behind every wrong option of a
  choice question.
- **The marking kit**: copy `templates/Marking Kit/` beside this file into
  the test's folder and rewrite it for this test. `FORMAT.md` there is the
  format, which the `plantoir-marking` skill reads when it is in this
  working folder; the checker refuses any key the format does not define. In short: every point is one mark, its ID the
  same in every version (`B1.2` is the same mark on Version A and Version
  B); every version answers every point; and no file in the kit has a key
  for a name, ever. A paper is named by its identifier (`Student A`) when
  it is marked. Then check the kit, the papers and the guide against each
  other:

  ```text wrap
  python3 -B .claude/skills/plantoir-test-authoring/scripts/check_kit.py "<test folder>/Marking Kit/answers.json" --marks "<test folder>/Marking Kit/marks-template.json" --paper A "<test folder>/Version A.tex" --paper B "<test folder>/Version B.tex" --guide "<test folder>/Marking Guide.tex"
  ```

  It checks that each question's marks on the paper are its number of
  points in `answers.json`, that the totals on the front and the Marking
  Guide's category table are the kit's counts, and that the guide has a
  row for every point. It reads the marks the way the starters write them
  (one `\score{...}` per question, the slash totals, `\catrow` and
  `\totalrow`). If this teacher's paper prints marks another way (one
  score for a whole part, say), it says it could not line them up and
  fails; then compare them by hand and say so in `Coverage.md`. It reads
  every key of the kit and the marks template for anything that looks like
  it holds a person, but it reads keys, not prose: a name typed inside a
  value is not something it can find, so never type one.

  (`python` or `py` on Windows, where `python3` may not exist; `.agents/`
  in place of `.claude/` works too.) Fix every line it prints until it
  says `OK`. That script is the one file here that is not a starting
  point: run it from this folder, and never copy or change it.
- **The templates are starting points.** `Marking Guide.tex`, the kit's
  `README.md`, `Coverage.md` and `Checks/check_answers.py` say at their
  top what may be changed freely. Adjust them to this teacher's header,
  categories, marks scheme and layout, and keep what each says must stay.

## 6. Checks

Where answers can be computed (arithmetic, a balanced equation, a trace,
an expression, a count), write `Checks/check_answers.py` for this test,
starting from `templates/Checks/check_answers.py` beside this file. It
works every value out again from what each PAPER gives, never by reading
the answer it checks; compares what it worked out with `answers.json`; and
on any difference prints the version and the question and exits 1. It
uses the standard library only. Run it from the test's folder with
`python3 -B Checks/check_answers.py` (`python` or `py` on Windows), after
every change to a question or an answer. Where nothing can be computed (an
essay, a source analysis, an explanation), say so in `Coverage.md`; the
reviewer's re-solve is the check for those.

## 7. Compile, look at every page, leave the folder clean

As `plantoir-handouts` section 8 says, for every version and its
solutions, the Marking Guide, and the practice test: compile with
`tectonic`, render every page with `pdftoppm -png -r 80` into a temporary
folder outside the working folder, and look at each one. On a test also
look for: the marks column beside every question, both copies of a version
laid out the same (an answer showing on the student copy is the worst
fault there is), a complete border on every table, and nothing cut off at
an edge. Leave only the files section 4 lists.

## 8. A practice test

When the teacher wants one, a practice test has the same shape as the test
with different numbers and contexts, its own solutions, and a note at the
top on how to mark it yourself. It may be handed out from the course site:
copy its PDF, and only its PDF, into the course's `Media` folder and link
it from a page (`plantoir-printing` section 4). Whether its solutions go on
the site too is the teacher's call; a test's own solutions never do.

## 9. When the kit is finished

Tell the teacher where the folder is, what was checked and by whom, and
anything still open.

**Marking is another skill's, and only when it is here.** Look for
`.claude/skills/plantoir-marking/SKILL.md` (or
`.agents/skills/plantoir-marking/SKILL.md`) in this working folder; the
root `CLAUDE.md` and `AGENTS.md` list the skills that are here. If it is
there, when the kit is finished and the teacher has looked at it, you may
mention once, in one sentence, that when the papers are written you can
help mark them onto feedback sheets with the plantoir-marking skill. Do
not raise it again in this session if they do not take it up. If it is not
there, say nothing about marking, and do not mark papers from this kit:
marking follows that skill's rules about students' names, and without them
it does not happen. If the teacher asks about marking, say that it needs
the plantoir-marking skill, which is not in this folder.

If the teacher asks what you can help with, answer plainly from what this
skill describes, and claim nothing it does not.

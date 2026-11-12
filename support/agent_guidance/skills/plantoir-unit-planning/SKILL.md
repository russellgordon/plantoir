---
name: plantoir-unit-planning
description: Use when a teacher asks to plan a unit, a thread, a module, or how the class will move through a stretch of the course - especially across more than one section, or beside a colleague teaching it on other dates - or asks to see, change or adopt a unit plan. Gathers the calendar and the teacher's way of teaching, agrees a plan in chat, and only on a clear go builds the plan site (a calendar across the sections, how the sections differ, lesson cards, assessment drafts, each day's materials, a curriculum correlation) in courses/<CODE>/.internal/planning/ from the template beside this file.
---

# Planning a unit

This working folder holds courses for Plantoir, which turns each course
(`courses/<CODE>/`, an Obsidian vault of Markdown pages) into a class
website. A unit plan is something else: a small site of its own, for the
teacher and the colleagues they plan with, never for students. This file is
managed by Plantoir and is replaced when Plantoir updates; do not edit it,
and never write anything inside this skill's folder (it is replaced whole,
and a file written here is lost). Copy from it instead.

## 1. What a unit plan is here

- **A plan site, kept beside the course.** Each course keeps its plans in
  `courses/<CODE>/.internal/planning/`: one folder per unit, and a page
  listing them (section 9 has the layout). The folder's name starts with a
  dot, so nothing in it is ever a page of the class website and nothing in
  it is ever copied there. It travels with the course in a backup, an
  archive and a restore.
- **Its look is fixed.** The plan page and the correlation page are built
  from `template/` beside this file, with its stylesheets and fonts. They
  are plain HTML pages, not course pages, so section 23 of
  `plantoir-page-authoring` (no raw HTML, no `<style>`) does not apply to
  them; it applies to the class website.
- **Opening it.** The teacher opens
  `courses/<CODE>/.internal/planning/index.html` in a web browser. In
  Finder a folder whose name starts with a dot is hidden; Command-Shift-.
  shows it. Tell the teacher the full path when you finish.
- **You never upload it.** Do not deploy, upload or send the plan site
  anywhere, and do not put it in the course's pages.

## 2. Gather, agree, then build

Work in this order, and say what you found at each step.

1. **How the teacher teaches.** Call `read_how_i_teach` for the course and
   keep to it in everything you write. If there is no page, ask the
   teacher how a lesson usually runs, and offer to draft the page.
2. **The calendar.** Call `read_remembered_timetable` for each section of
   the course, and read each section's class pages (`list_pages`,
   `read_page`) to see where each section is now. Ask for anything the
   timetable does not hold: holidays, long weekends, assemblies, a shorter
   day, the teacher's own rules ("no tests on Wednesdays").
3. **A colleague's dates.** If a colleague teaches the same unit on other
   dates, ask the teacher for those dates. A list pasted into the chat, or a
   CSV file, is fine. The colleague's section is a column of the calendar
   like any other, named as the teacher names it.
4. **What there is to build on.** Ask for last year's materials, a
   textbook's chapter, or a reference course of the same code (Plantoir
   names any it keeps in the session's opening message). Adapt them; never
   copy a textbook's questions or a publisher's pages word for word.
5. **The curriculum.** Call `list_curriculum_expectations` for the strand
   the unit covers, so every code and wording in the plan is the
   curriculum's own.
6. **Agree the plan in chat first.** Show the teacher, in plain words, the
   lessons in order, the calendar across every section, where the
   assessments fall, and what the colleague's section does differently.
   Change it until they are happy with it.
7. **Build only on a clear go.** A go is a go; agreeing in chat is not.
   Nothing is written to the planning folder until the teacher says to
   build it ("go ahead", "build it", "make the plan").

## 3. The lesson shape comes from How I Teach

Each lesson card has one row per part of a lesson, and those parts are the
teacher's: a warm-up, a discussion, a task, practice, an exit ticket, or
whatever How I Teach describes. The row labels in `template/unit/index.html`
(Warm-up, Lesson, Practice, Files) are examples to replace, not a shape to
keep. If How I Teach says nothing about the shape of a lesson, ask.

## 4. Check the calendar with a second agent

Before building, have a second agent check the draft calendar, starting
fresh from the facts rather than from your conclusions. Give it each
section's dates, the colleague's dates, the holidays and long weekends, the
teacher's rules, and the draft. Ask it to find:

- a lesson on a day a section does not meet, or a day it meets with nothing
  planned;
- a section that falls behind or runs ahead of the others without the plan
  saying why;
- an assessment on a day the teacher's rules forbid, or before the lessons
  it assesses;
- assessments for learning (a quiz, a check) that come too late to act on
  before the test.

Tell it that "nothing wrong" is an acceptable answer. Fix what it finds
that is real, and tell the teacher what changed. If you cannot start a
second agent, say plainly that the calendar has not had that check.

## 5. The plan page: what it holds, in this order

Copy `template/unit/index.html` and replace its content. The order is
fixed:

1. **The header**: the course, the unit and its dates (the eyebrow line),
   the plan's title, one sentence on what the unit is, the facts (each
   section and its number of classes, the length of a period, the days
   without classes) and the legend of chips.
2. **Calendar**: a date column first, then one column per section in the
   order the teacher names them, the colleague's section included. A cell
   is the section's "Day n", the lesson's chip and its title linking to the
   lesson's card; a day the section does not meet reads "No class"; a day
   nobody meets (a holiday, a long weekend) is one break row.
3. **How the sections differ**: one bullet per section that departs from
   the common order, and why.
4. **Lessons**: one card per lesson (section 3). A card's last row is ONE
   link to that day's materials further down the page, never a list of
   files.
5. **Each day's materials**, a section per day (section 8).
6. **Assessment drafts** (section 6), the test's card linking the
   correlation page.

Leave out a list of decisions made along the way and a history of
revisions; the plan says what will happen, not how it was reached.

Every component of the page is in the template as a commented PATTERN,
with the classes it uses. Use those classes and only those; add no
`<style>` block, no `style` of your own beyond the ones the patterns carry,
and no font or script from the internet. The template is laid out the way
the plan folder is, so its relative links (`../assets/plan.css`,
`correlation.html`, `../index.html`) work unchanged once copied.

## 6. Assessments go through `plantoir-handouts`

A unit test with versions and a kit to mark it from is made with the
`plantoir-test-authoring` skill
(`.claude/skills/plantoir-test-authoring/SKILL.md`, the same file is at
`.agents/skills/plantoir-test-authoring/SKILL.md`), from the plan's
lessons; copy its PDFs into the plan as below, never a `.tex` file or
its marking kit. Any other quiz, test or practice set is a handout. Make
it with the
`plantoir-handouts` skill (`.claude/skills/plantoir-handouts/SKILL.md`,
the same file is at `.agents/skills/plantoir-handouts/SKILL.md`), in its
house style and in the course's handouts folder, which it reads from
`courses/<CODE>/.internal/handouts/handouts.json`. For a unit:

- **One author, one reviewer, then a sweep.** Write one brief that holds
  everything an author needs (the lessons it assesses, the expectations,
  the teacher's rules, the house style), and have one agent write the
  assessment from it. Then a separate agent reviews it for fit and solves
  every question again from scratch, and a last pass checks the two
  versions, the answer key and the plan agree. Fix what each finds.
- **Copy the PDFs into the plan.** Copy each PDF (the student copy and its
  solutions or answers) into `<unit-slug>/pdfs/` under its real name, and
  link it from the assessment's card. Copy them again after every change,
  so the plan never links an old copy. Never copy a `.tex` file into the
  planning folder.

## 7. The correlation page

Copy `template/unit/correlation.html` beside the unit's `index.html` and
fill its four parts in order: question by question, marks by expectation
(by overall expectation, then by specific expectation), concept emphasis,
and the gaps.

- **Exact codes and wording.** Every code and every expectation's wording
  is copied exactly from `list_curriculum_expectations`. Every mark is the
  test's own, read from the test as written.
- **Totals that add up.** Each table's marks total the test, and each Share
  column totals exactly 100.0%. A total that does not is a mistake to find
  and fix, never to print.
- **What the test emphasises, and what it leaves out.** Say which concepts
  carry the most marks, and list every expectation in the strand that the
  test does not assess (the template's not-assessed rows), and anything on
  the test the plan does not teach.
- **Reviewed by a second agent**, which recounts every total from the test
  itself. Fix what it finds before the teacher sees the page.

## 8. Each day's materials

- **One day at a time, and only on a go.** Make a day's handouts when the
  teacher asks for that day, through `plantoir-handouts`, and copy the PDFs
  into `<unit-slug>/pdfs/`.
- **Linked from the day's section.** Each handout is a card in that day's
  section, its Files row linking the PDFs. A link is written only once its
  PDF is in `pdfs/`.
- **The "✓ reviewed" mark** goes on a lesson's card and on a day's heading
  only after that day's materials have been reviewed and the teacher has
  agreed them. Never before.

## 9. The planning folder: where everything goes

```text wrap
courses/<CODE>/.internal/planning/
  index.html          the course's list of plans, one card per unit (from template/index.html)
  robots.txt          two lines that ask search engines to stay away (from template/robots.txt)
  assets/             the stylesheets and fonts, copied whole from template/assets/
  <unit-slug>/
    index.html        the unit's plan page (from template/unit/index.html)
    correlation.html  the unit's curriculum correlation (from template/unit/correlation.html)
    plan.json         the unit's facts, read by Plantoir
    pdfs/             copies of the unit's handouts, under their real names
```

- **Write only inside `.internal/planning/`**, apart from the course's
  `handouts.json`, which `plantoir-handouts` keeps. Leave everything else
  under `.internal` alone.
- **`assets/` is copied, never edited.** Copy `template/assets/` into
  `.internal/planning/assets/` whole the first time, and again whenever
  the template's copy differs, replacing what is there. Never change a file
  in it, and never add a stylesheet beside it.
- **A unit's folder name** is lowercase letters, digits and hyphens, 1 to
  40 characters, starting with a letter: `unit-3`, `module-b-ecosystems`.
  Never `assets`, `build`, `dist` or `out`.
- **No folder anywhere under the planning folder** is called `build`,
  `dist`, `out`, `node_modules`, `__pycache__`, `.git`, `.cache`,
  `.quartz-cache` or `.merged_output`: a backup leaves a folder of those
  names out.
- **Only pages, PDFs, the stylesheets and fonts, and `robots.txt` belong to
  the plan site.** A `.tex` file, an `.htaccess` or `.htpasswd`, and any
  other notes are kept somewhere else.
- **`plan.json`**, one per unit, is what Plantoir reads to know the unit
  exists. Write it when you build the plan, and update `updated` whenever
  you change the plan:

  ```json
  {"unit": "Unit 3", "title": "Chemical Reactions", "firstClass": "2027-02-08", "lastClass": "2027-02-19", "sections": ["Section 1", "Section 2", "A colleague's section"], "updated": "2027-02-01"}
  ```

  `unit` and `title` are text, and at least one of them is not empty: the
  course's own word and number for the unit ("Unit 3", "Thread 4",
  "Module B") and its name. `firstClass`, `lastClass` and `updated` are
  dates written `yyyy-mm-dd`. `sections` lists the calendar's columns by
  the names the plan uses. Keep any other notes out of it.
- **The course's list of plans** (`index.html` at the top of the planning
  folder) has one card per unit folder, in the order they are taught. Add
  the unit's card when you build its plan.

## 10. Check it before you hand it over

- Every relative link on every page opens a file or a place on a page that
  is there: each PDF in `pdfs/`, `correlation.html`, `../index.html`, and
  every `#day…` or `#l…` a cell or card points at.
- Every page has `<meta name="robots" content="noindex, nofollow">` in its
  head, as the template's pages do.
- No page loads anything from the internet: no address beginning `http`
  in a `<link>`, a `<script>` or a `url(...)`.
- Every class a page uses is defined in its stylesheet
  (`assets/plan.css` for the plan page and the list of plans,
  `assets/correlation.css` for the correlation page).
- Open the plan page and the correlation page in a web browser, in light
  and in dark appearance, and look at both before telling the teacher it
  is done.

When the plan is built and the teacher has looked at it, you may mention
once, in one sentence, that you can also write the unit's test from the
plan, with its solutions and marking guide, using the
plantoir-test-authoring skill. Do not raise it again in this session if
they do not take it up.

## 11. Adopting a plan the teacher already has

A teacher may already keep a plan site of their own made in this same
style, in a folder outside the course. Offer to adopt it when they mention
one; never do it unasked.

- Copy its pages and its `pdfs/` folder into a new unit folder.
- In each page, replace the `<link>` to an internet font service and the
  page's own `<style>` block with one `<link>` to the matching stylesheet
  in `../assets/` (`plan.css` for the plan page, `correlation.css` for the
  correlation page).
- Leave any `.htaccess` and `.htpasswd` behind, and never open an
  `.htpasswd` file: it holds a password.
- Write the unit's `plan.json` and add its card to the course's list of
  plans.
- Mistakes in the old pages (a stray `</div>`, cards that run onto one
  line, a share column that does not total 100.0%) are fixed only with the
  teacher's agreement, after telling them what you found.

## 12. Later: from the plan to class pages

When the teacher asks to turn a day of the plan into class pages, do it
one day at a time: add the class with `plan_add_classes` (and
`add_classes` once the teacher agrees the plan it shows), and write its
pages with the `plantoir-page-authoring` skill. The plan site and the class
website stay separate: a class page links the class website's own copy of a
handout, from the course's `Media` folder, never a file in the planning
folder.

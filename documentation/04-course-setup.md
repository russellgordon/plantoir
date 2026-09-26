# 4. Course Setup (`setup_course.py`)

[◀ Previous: Launcher Scripts](03-launcher-scripts.md) · [Back to index](README.md) · [Next: The Build Pipeline ▶](05-build-pipeline.md)

`scripts/setup_course.py` (run inside the container by `setup.sh`) is an
interactive wizard. It has two jobs: **scaffold the course folder structure**
that Obsidian will edit, and **record every choice in
[`course_config.json`](08-course-config-reference.md)** for the build script
to consume. It is *stateful*: re-running it on an existing course pre-fills
every prompt with the previous answers, so it doubles as a "settings editor".

## Flow, step by step

### 0. Offer the example course

Before anything else, the wizard offers to install the **EXC2O Example
Course** ("Example Course", Grade 10 Open — a plausible Ontario course code)
from `/opt/support/example_course/`. If accepted, it copies the whole course
(content, `.obsidian` settings, and a filled-in `course_config.json` with two
sections) into `/teaching/courses/`, applies the two on-image Quartz patches
(below), prints the preview command, and exits. If a course named `EXC2O`
already exists, it generates a random alternative code still ending in `2O`
(e.g. `KQX2O`) so a teacher can install multiple sandboxes — and rewrites
`course_config.json` so the copy calls itself by the code it was given.

**What is in it.** The example is a full Grade 9 science course (SNC1W,
de-streamed) of roughly 350 pages: five strands of curriculum expectations
reproduced from the Ministry's published document, 35 concept pages, 14 investigations, exercises with answers,
marked tasks with rubrics, tutorials, discussions, portfolio prompts, and two
sections of class-by-class pages paced a day apart.

The dates simulate a real semestered Ontario school: classes begin on the
first Tuesday after Labour Day (8 September 2026), run Monday to Friday,
skip Thanksgiving Monday, a two-week winter break, and three PA days, and
finish in late January — 86 class days in section 1 and 82 in section 2,
a full semester against the 110-hour credit requirement. Each shared page is dated to the day it was first used in
class, which is derived from the class agendas rather than assigned by hand. It is written to
demonstrate what the toolchain renders — Mermaid diagrams, KaTeX equations,
callouts, transclusion, tags, checklists, footnotes, and per-section drafts —
with `Style/What This Site Can Do` serving as a working reference for every
feature, source included.

**Installing it without prompts.** `setup_course.py --install-example` copies
the example and exits, printing `EXAMPLE_COURSE_CODE=<CODE>` as its last line
so a caller knows which code it received. `setup.sh -- --install-example`
reaches it from the host; the macOS app uses exactly that to offer the example
course from the top of its New Course sheet.

### 0b. Starting content for the course code

Once a code has been entered (step 1), the wizard offers up to two kinds of
starting content — a course takes at most one of them, but which ones are
OFFERED is two separate questions:

- **Example content**, when `support/example_content/<CODE>/` exists — 38
  course codes as of September 2026, and growing; the code counts the
  folders rather than trusting a number, and so should you. A payload is a
  complete working course written for that code: a semester of class pages,
  concept and task pages, and (optionally) every Ministry expectation as its
  own page. The payload's `manifest.json` is the course's ENTIRE structure,
  so step 5's questions are skipped: the pages were written for exactly
  those folders.
- **A skeleton**, for EVERY Ontario code — around 1,900 of which have no
  payload, and 38 of which have one they may decline.
  `support/skeletons/families.json` maps the code's three-letter prefix to
  one of fifty subject families (ADA drama, AMU music, SCH chemistry, MCV
  calculus, TXJ hairstyling…), falling back to a generic skeleton for club
  and custom codes. The skeleton fills the course with the SHAPE of a
  course — folders that suit the subject, four units of three class pages
  to rename, a landing page with Most Recent Class, `Key Links`, a site
  tour, and placeholder pages saying what belongs where — and its folders
  become the DEFAULT answers to step 5's questions rather than replacing
  them.

**The rule, once, because three surfaces ask it:** a skeleton is OFFERED for
a code when a family exists for its prefix AND the teacher is not taking the
example content written for that code. It lives in ONE function —
`SkeletonCatalog.hasSkeleton(forCode:takingExampleContent:numbered:)` on the mac (a club, #267, is offered none),
`SkeletonCatalog.HasSkeleton` on Windows — read by the toggle's visibility,
by what the structure editor adopts, and by `use_skeleton` in the file.
Neither app takes a default value for the second argument, so a call site
that has not been made to think about the example-content toggle fails to
compile.

Both apps asked the wrong question until 2026-09-21
([#248](https://github.com/russellgordon/plantoir/issues/248)): "does
example content EXIST for this code?" rather than "is the teacher TAKING
it?". So for all 38 payload codes the skeleton toggle was never shown, the
structure editor adopted nothing, and `use_skeleton: false` was written
whatever the teacher had chosen — a teacher who declined the ready-made
pages got EMPTY folders. MEASURED, by driving the real `setup_course.py`
through a pty: an ICS4U made that way holds **18 `.md` files**; the same
code with `use_skeleton: true` holds **47**, and its tree and its
`course_config.json` are byte-identical to what ICS2O — same family, no
payload — has always produced. The command-line wizard was never wrong:
`find_skeleton_dir` has never looked at payloads, so the whole fault was in
the two apps, and it stood from 2026-08-13 to 2026-09-21 because nothing in
`contracts/` asked the question in the teacher's terms.

What was REJECTED while fixing it, so it is not proposed again: one "empty
folders" sentence covering all three situations, which would have reworded
what ~1,900 codes read to fix a sentence 38 of them see; and anything
retroactive for courses already created this way — Russell's call, having
deleted and remade the one course it affected.

**A third rejection was reversed the next day, and the reasoning is worth
keeping because half of it was right.** #248 also rejected a
curriculum-pages toggle for a skeleton that ships a `Curriculum` folder,
on the ground that the `fixed` and `control` pty runs produce identical
trees, so adding one would make a payload code behave unlike its own
family. That is true for the ~1,900 codes with no payload — there is
nothing to include, the folder is a placeholder, and the toggle would
decide nothing. It is false for the 38 that HAVE one: the expectations
written for their code exist, the teacher declined the lessons rather than
the curriculum, and behaving "like its own family" is precisely what makes
their course wrong.
[#251](https://github.com/russellgordon/plantoir/issues/251) reversed it
for those 38 on 2026-09-22 — see **A declined payload still gives up its
curriculum** below.

## A declined payload still gives up its curriculum

Example content OFF plus the skeleton ON, for one of the 38 codes whose
payload declares a `curriculum_folder`: the payload's curriculum pages are
installed into the skeleton's `Curriculum` folder, the three curriculum
answers are written exactly as they are for a payload course, and the
curriculum coverage map is built and linked from Key Links.

**Why the two halves had to ship together.** MEASURED before the fix, by
driving the real `setup_course.py` through a pty: ICS4U that way got a
`Curriculum/` folder of **two** files — the skeleton's generic `index.md`
and a placeholder expectation called `A1.1` whose page reads "DELETE THIS
PAGE" — against the payload's **61**. Forcing all three curriculum keys
true changed *nothing*: no code path read the payload once the skeleton was
the starting point, so `include_curriculum_pages: true` merely switched the
map on over that one fake cell. Applying `build_site.py`'s own
`_find_curriculum_folder` and `_collect_expectations` to the tree gave **1
specific expectation and 0 overall**, against the payload's **47 and 12**.
Enabling coverage without copying the pages is not half a fix; it is a
worse state than the fault.

**The install is a walk of its own** — `install_curriculum_from_payload`,
not a narrowed second call to `install_example_content`. That installer's
`top_level_allowed` lets any `index.md` through unconditionally, and all 38
payloads have a `per_section/index.md`, so a narrowed call would pour the
payload's own section landing page into a course taking none of the
payload's pages. Measured on the prototype before it was found.

**Order is the mechanism.** `install_payload_file` returns without writing
when the destination exists, so the real expectations have to claim their
names BEFORE the skeleton is installed, never after.

**The skeleton's own curriculum folder is then skipped BY NAME**, by
dropping it from the folder list passed to the skeleton install — never by
turning that install's `include_curriculum` argument off. Both wrong
prototypes are worth recording:

1. Leaving the skeleton install alone gave ICS4U the right 61 pages and
   **MCMPR11 sixty**, including the skeleton's placeholder `A1.1.md`:
   British Columbia's codes start at `D1.1`, so nothing of the payload's
   displaced it by name, and `_collect_expectations` would have read it as
   a forty-eighth expectation and drawn a cell for a standard that does not
   exist in that province. MTH1W is the other payload with no `A1.1` of its
   own.
2. Passing `include_curriculum=False` to the skeleton install removed the
   placeholder and **also stripped the "Curriculum connection" block out of
   all seven `_DUPLICATE ME.md` template pages** — that one flag does two
   jobs, the second being `strip_curriculum_blocks` /
   `unlink_curriculum_references` on every other page.

**Measured after**, same harness: ICS4U 61 curriculum pages (47 specific,
12 overall) and 106 `.md` in the course, MCMPR11 59 British Columbia
standards with no `A1.1` among them and 102 `.md`, ICS2O — no payload —
unchanged at 2 and 47. Example content ON: 205 files, tree,
`course_config.json` and content identical to the previous script's,
timestamps aside.

**The pages are installed into the SKELETON's `curriculum_folder` name**,
because that is the name `course_config.json` records for a course with
`prepopulate_example_content: false`, and the name the build looks in. All
38 payloads and all 50 skeleton families call it `Curriculum` today
(measured 2026-09-21), so the parameter buys nothing this morning; it buys
a future payload that disagreed landing where the build will look rather
than in an orphan folder.

**The map is all red on day one**, and that is the intended reading rather
than a defect to special-case: coverage counts the site's own links from
lessons to expectations, a skeleton course starts with none, and the page's
caption already says "red in September, greener as the year goes on".

**Nothing is retroactive.** A course already created as
skeleton-without-expectations keeps its two placeholder pages; a teacher
who wants the real ones deletes the course and remakes it.

**One thing left undone, deliberately.** Four payloads' `About These …`
explainer links once to a payload page a skeleton course will not have —
ICS4U to `[[The Software Project]]`, ICS3U to `[[The Community App]]`,
CGC1W to `[[The Concepts of Geographic Thinking]]`, MDM4U to `[[The
Culminating Investigation]]`. It was left alone here rather than rewritten
at install: it is an example-content fix, its own small piece, and the
skeletons already ship illustrative unresolved links of their own.

The old note that the skeleton's `Curriculum/index.md` and its expectation
pages install "even though the app writes `include_curriculum_pages:
false`" is no longer the whole story. The install gate is still
`skeleton_curriculum in shared_folders` rather than `include_curriculum`,
so a code with no payload behaves exactly as it always has — but for a
payload code the app now writes `true`, and that key now decides something:
whether the payload's expectations are fetched at all.

**Both apps' wizards let the teacher decline a skeleton, and the structure
editor must follow them in BOTH directions.** Turning "Start from a
<subject> skeleton" ON adopts that subject's five lists; turning it OFF puts
the defaults back — the LCS variants for the two shared lists when the
terminology switch is on, the plain defaults for the two per-section lists,
which have no LCS variant — for each list still EQUAL to what the adoption
put there, and leaves the rest as the teacher left them — except the marks
pool, which is kept where the teacher ticked it but narrowed to the folders
the course will actually have (below). With nothing adopted there is nothing
to compare against and nothing changes. The example-content
toggle moves the editor the same way, in both directions: turning it OFF
adopts the skeleton it has just revealed, turning it back ON restores. The
way back is not optional — without it a teacher who changed their mind would
get a different file from the one they would have got without changing it.

**Three situations, two sentences.** A teacher who has declined the skeleton
for a code with no ready-made pages reads the same sentence as one whose
code has no skeleton at all ("Example content isn't available for this
course code yet…"), because the course starts empty either way. A teacher
who declined ready-made pages AND then the skeleton reads a SECOND sentence
("This course will start with empty folders ready for your own pages"),
because the first one's opening clause is false for a code they were offered
example content for one question ago. The two share no accessibility
identifier, so a test can say which one is on screen. All of it is in
`contracts/shared-rules.json` → `wizard.whenTheNoteIsShown`.

Russell decided this for Windows on 2026-09-06 and Windows shipped it on
2026-09-07; the mac copied it on 2026-09-18 ([issue
#77](https://github.com/russellgordon/plantoir/issues/77)), having until
then adopted one way only. The bug that made it worth fixing is the shape to
remember: a teacher typed SNC4M, watched Investigations and Concepts appear,
turned the toggle off — and was shown, and got, the science skeleton's
folders with none of its pages, while `course_config.json` said
`use_skeleton: false`. A wizard that lies about what it is about to make is
a worse product than one that never asked.

The rule and its seventeen cases are in [`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`wizard.skeletonToggle`, run on the mac by `SharedRulesContractTests`;
`WizardStructureTests` covers what cases cannot reach — the pieces the rule
is assembled from, and a scan proving the toggle is WIRED, a control with no
handler being the original bug. Three things about it are decisions rather than
mechanics; the fourth is what to know before reading a green run as coverage:

- **A list is recognised as untouched by VALUE, not by a dirty flag.** A
  list edited and then edited BACK to exactly what the adoption set is
  restored with the untouched ones, and that is intended: a teacher cannot
  see the difference, so neither can the rule. Order counts as part of the
  value — the same names in a different order is an edit and is left alone.
  Per-list dirty flags were rejected: a flag has to be got right in every
  editing path and gets one wrong the first time a list is changed from
  somewhere new, which value equality cannot.
- **The LCS switch rewrites the two SHARED lists**, so flipping it after an
  adoption leaves them unequal to the snapshot and they stay exactly as the
  switch left them, while the per-section lists still go back. Re-taking the
  snapshot on a terminology flip would make the restore delete the College
  Board folder the teacher had just asked for.
- **The marks pool can never name a folder that has just left the editor**,
  and it takes TWO rules to keep that true: a pool still equal to the
  adoption's is re-inferred over the restored folders, and a pool the teacher
  has ticked themselves is kept but NARROWED to the folders the course will
  actually have. Miss the second and a teacher who adopted the mathematics
  skeleton, unticked `Tasks` and then declined the skeleton is shown a
  checklist with nothing ticked while the wizard writes
  `graded_folders: ["Thinking Tasks"]` against a course with no such folder —
  and the two apps then write DIFFERENT files for the same clicks, which is
  what the contract exists to stop. (There is no second net behind the
  wizard: since #192 `setup_course.py` writes a saved pool back exactly as it
  was — see "A command-line re-run leaves the marks pool alone" below — so a
  name the wizard writes untruly stays in the file. The first version of the
  mac's restore did exactly that, and the adversarial review of it found
  it.) The two apps reach the same answer from
  opposite ends: the mac narrows inside the restore, Windows leaves the pool
  and narrows it on every read (`CurrentGradedFolders`) and again when the
  file is written. The mac narrows ONCE MORE as the file is written, for the
  one path the editor does not cover: the terminology switch takes `College
  Board Curriculum` out of the folder list without asking the marks pool, so
  a teacher who had ticked it would otherwise have it written into a course
  that has no such folder.
- **Two of the five lists cannot tell one answer from another for most
  codes**, which matters when reading a green run as coverage: every bundled
  family ships `per_section_folders` of exactly `["All Classes"]`, the
  factory default, so only the per-section FILES prove that half of a
  restore; and every family declares `graded_folders` of `["Tasks"]` except
  mathematics, so a marks-pool expectation means nothing unless its case uses
  a mathematics code. The contract carries cases on `MPM1D` for that reason.
  A third thing not to read as coverage, which the contract's `lists.note`
  also names: in a runner that resolves the `skeleton` symbol through the same
  catalog an adoption copies from, a `turnOn` case's four list expectations
  prove that the adoption FIRED rather than what it copied — which is why the
  `MPM1D` adoption case spells its marks pool out as a literal.
- **A narrow extra rule for the hole value equality leaves was rejected.**
  It would have made the two apps differ over a case no teacher can tell
  apart, which is how the contract stops being worth having.

Both are poured in by the same `install_example_content()`, which replaces
the payload's sentinels: `__CREATED__`, `__CREATED_CLASS_K__` (spread
across the semester), `__SECTION_NUMBER__`, and — for skeletons —
`__COURSE_CODE__` and `__COURSE_NAME__`. Course-level pages have their
`created`/`publish` split into `createdSectionN`/`publishForSectionN`, one pair per
section, so two sections can publish the same page on different days
([mechanism](05-build-pipeline.md#frontmatter-processing)).

The skeletons are GENERATED from eleven shapes plus a family table by
`.claude/skills/example-content/generate_skeletons.py`, and checked by
`lint_skeletons.py`; the payloads are hand-written and checked by
`lint_payload.py`.

### 1. Course identity

- Prompts for the **course code** (default `ICS3U`), uppercased.
- Looks the code up in `ontario_secondary_courses.json` (1,930 entries) and
  offers the short name first ("Intro to Comp Sci"), then the formal name
  ("Introduction to Computer Science, Grade 11, U"), then a custom name. The
  short name leads because the formal one is the ministry's string and is
  almost always deleted before a teacher types what they really call the
  course; the app's New Course wizard defaults the same way. The rule is
  pinned in [`contracts/course-management.json`](../contracts/course-management.json)
  → `defaultCourseName`.
- **Club support**: if the 4th character of the code is not a digit (course
  codes like `ICS3U` encode grade in position 4; a club might be `CODING`),
  the wizard offers a **custom short label** (≤ 12 characters) to display in
  the site header instead of the uppercased code, and omits the
  "Grade N" prefix from the generated home-page title.

### 2. Safety: automatic backup

If the course folder already exists and `--no-backup` was not given, the
entire course is zipped to `courses/_backups/<CODE>/<timestamp>.zip` *before
any mutation*, excluding caches and generated output (`node_modules`,
`.merged_output`, `.git`, etc.). This makes the wizard safe to re-run.

### 3. Course-level conventions

- Ensures a **`Media/` folder** at the course root. This is the designated
  home for binary assets (screenshots, videos, PDFs). It is special-cased
  throughout the toolchain: always shared, always hidden from the site
  sidebar, never copied (it is symlinked into the build,
  [see why](05-build-pipeline.md#media-handling)), and the wizard refuses to
  let it appear in any folder list.
- Seeds **Obsidian defaults** (`support/obsidian_defaults/.obsidian/`) into
  the course folder *without overwriting existing files*. The important
  setting is `attachmentFolderPath: "Media"` — a screenshot pasted into
  Obsidian is saved to the shared `Media/` folder automatically. It also
  ships the Minimal theme, disables live preview, and seeds a
  `workspace.json` with the File Explorer's auto-reveal on, so opening a
  page highlights its folder in Obsidian's sidebar. The example-course
  installer seeds the same defaults.

### 4. Appearance and localization (all per-section where sensible)

- **Locale**: choice of the 27 locales Quartz supports, presented with
  human-readable names and flags. Stored as e.g. `"locale": "en-GB"` and
  applied to `quartz.config.ts` at build time (affects UI strings and date
  formatting).
- **Colour scheme per section**: a full-screen interactive picker (raw
  terminal mode, arrow keys) that renders live swatches of all nine theme
  colours in light and dark mode using 24-bit ANSI escape codes — this is
  why the main README recommends iTerm2 over Apple's Terminal. The 43
  schemes come from `support/colour_schemes.json`. Different sections get
  different schemes so a teacher (and their students) can tell sections
  apart at a glance.
- **Fonts**: a curated list of six Google-Font header/body pairings plus
  system-font and custom options, and six monospaced code fonts. Choices are
  stored under a course-wide `default` with per-section overrides.
- **Header emoji per section** and **section marker visibility per section**
  (whether the header reads "📚 ICS3U S1" or just "📚 ICS3U").
- Per-section (set after creation, in the app's section settings):
  **grade in the title** (`show_grade_in_title`, default on — whether the
  landing title leads with "Grade 11"; deliberately literal, with the app
  warning when the course name already contains the grade label) and a
  **custom domain** (`custom_domains.sections.sectionN`, an Advanced
  option — the app's published-site links then wear that domain).

### 5. Content structure

The wizard then asks which folders/files exist and how they behave. When a
skeleton applies (step 0b), every default below comes from that subject's
manifest instead of the factory list, and a folder the teacher adds at the
prompt is treated like any other section — visible, with a chevron. When
example content is being installed, this whole step is skipped.

**In both apps' wizards this step and the skeleton question are one
thing**, and the editor follows the toggle both ways: declining the skeleton
puts the factory (or LCS) defaults back into every list the teacher has not
edited since it was adopted, so what the four lists show is what
`course_config.json` will carry and what will be created on disk. Step 0b
has the rule, what it deliberately costs, and where its cases live.

- **Shared folders** (factory default: Concepts, Discussions, Examples,
  Exercises, Ontario Curriculum, Recaps, Setup, Style, Tasks, Tutorials, …;
  a music skeleton instead offers Concepts, Repertoire, Warm-Ups, Listening,
  Portfolios, Tasks, Setup, Style, Tutorials, Curriculum) — content common
  to all sections.
- **Shared files** — loose Markdown files common to all sections.
- **Per-section folders** (default: "All Classes" — the day-by-day lesson
  log) and **per-section files** (e.g. "Key Links.md") — these exist
  separately inside each `section<N>/` folder.
- **Hidden items** — folders/files to omit from the site's sidebar
  (Explorer). Hidden ≠ unpublished: pages in hidden folders still build and
  are reachable via links and search; they just do not clutter navigation.
  Curriculum folders and private notes default to hidden. A skeleton course
  hides its `Curriculum` folder and the utility files, and gives every other
  visible shared folder a chevron — `All Classes` stays a plain link.
- **Expandable items** — folders that behave as *expandable trees* in the
  sidebar. Non-expandable folders render as plain links to the folder's
  index page. This distinction drives the patched Explorer component
  ([customizations §A](06-quartz-customizations.md#a-components-replaced-at-image-build-time)).
- **Explorer click behaviour** — whether clicking a folder *name* expands it
  (chevron-and-name) or navigates to it (chevron-only expansion).
- **Footer HTML** — optional raw HTML (e.g. a CC-BY licence notice) injected
  into every page's footer at build time.
- **Reading-time estimates** — whether pages show "N min read".
- **Curriculum Coverage page** — whether to generate the coverage heat map
  (default ON, and only asked when the course keeps a curriculum folder,
  since the map would otherwise have nothing to measure). Saved as
  `include_curriculum_coverage`; the build treats a missing key as ON, so
  courses created before this existed pick it up on their next build.

### 6. Timetable sections

The wizard asks how many sections the teacher has **and which timetable
numbers they are** (e.g. a teacher with sections 1, 3, and 4 enters `1,3,4`).
Folders `section1/`, `section3/`, `section4/` are created; `section2` simply
never exists. All later commands validate the section argument against this
list.

### 7. Scaffolding written to disk

For each **shared folder**: the folder plus an `index.md` whose frontmatter
contains *per-section* publication and creation keys:

```yaml
---
title: Examples
createdSection1: 2025-09-02T08:30:00.000-0400
publishForSection1: true
createdSection3: 2025-09-02T08:30:00.000-0400
publishForSection3: true
---
```

This per-section convention is the heart of multi-section publishing: one
physical file carries independent publication state for every section, and
the build for section N collapses `publishForSectionN`/`createdSectionN` into
the plain `publish`/`created` keys Quartz reads
([details](05-build-pipeline.md#frontmatter-processing)). Timestamps use the
host's timezone offset (passed in as `HOST_TZ_OFFSET`).

> **A note on `publish:` versus `draft:`.** Courses created before this
> convention carry `draft:` and `draftSection<N>:`, which mean the *opposite*
> — `draft: true` is a page students cannot see. Those still work: the build
> reads them, inverted. You never have to convert a course by hand.
>
> **What happens next is the same on both machines** (decided 2026-09-07):
> the first time something edits such a page's visibility, the old key is
> rewritten to the new one on the same line and the old key removed, so the
> page shows a one-line change in Obsidian. Nothing converts a course by
> hand, and nothing needs to: the build reads both spellings. (The macOS app
> kept the old key inverted until 2026-09-09, when it adopted this too —
> issue #107; `contracts/file-formats.json` → `pageVisibility.writingRules`
> carries the rule and the reasoning, and `writingCases` beside it is the
> same list as data — thirteen whole files, each given to the writer with the
> visibility it should be asked for and the exact text it must come back as.
> **Both suites run that list**: the mac since 2026-09-09 with issue #107,
> and Windows since 2026-09-19 with
> [issue #138](https://github.com/russellgordon/plantoir/issues/138), which
> replaced five of the cases retyped into that test file. Three of the other
> five were already asserted elsewhere in the Windows suite in its own words
> (one in that file, two in `PageVisibilityReadingTests.cs`); what running the
> list adds is that every case is read from the FILE and so cannot drift from
> it, and that two of them are covered on Windows for the first time. The
> three most recent — a value's CONTINUATION lines going with its key, and an
> indented `# note` after a complete value staying where the teacher wrote it
> — arrived on 2026-09-19 with issue #176, which is why the list is thirteen
> rather than the ten it was when both suites started running it.)
> Two things are
> deliberately NOT migrations: restoring a backup puts back the spelling the
> backup held, because a restore is not an edit; and adding a section writes
> the new section's `publishForSection<N>` while leaving the other sections'
> keys exactly as they were, because adding a section changes nothing about
> what any existing section publishes. A page with
> **no** publication key at all is visible, so forgetting the key leaves work
> showing rather than making it disappear unnoticed.
>
> **And a note on the VALUES, added 2026-09-18.** Neither wizard ever writes
> anything but `true` or `false`, but a teacher typing in Obsidian can write
> what they like, and what the built site makes of it is not what reading the
> line suggests: `publish: no` HIDES a page, `publish: true # covered Tuesday`
> and `publish: maybe` PUBLISH one, and `publish: "False"` is visible while
> `publish: FALSE` is not. The reason is the YAML round trip in the build
> ([05](05-build-pipeline.md#frontmatter-processing)), and the measured table
> both apps are written against is
> [08 → Whether students see a page](08-course-config-reference.md#whether-students-see-a-page).
> It matters HERE because the course installer splits a course-level page's
> one flag into one per section (`setup_course.per_section_frontmatter`): a
> `publish:` value is copied character for character, and a legacy `draft:`
> value is turned round with the build's own rule rather than by comparing it
> with the literal text `"true"` — which used to publish a `draft: yes` page
> into every section while the build went on hiding the unsplit original.
>
> **Adding a SECTION carries the same value the same way**, in each app's own
> `SectionAdder` — the new section's `publishForSection<N>` takes the value
> the lowest existing section already carries. The mac's fix landed
> 2026-09-18 and Windows' on 2026-09-19, and both had the identical
> inversion: a legacy `draftSection1: yes` was carried across as PUBLISHED.
> A key with nothing after it is a null, which publishes, so the emptiness is
> copied rather than turned into `false`; a value that runs onto the next line
> cannot be copied at all and is written as held back.

For each **section**: `section<N>/` with an `index.md` (site home page —
its stored title is only a starting value: the build recomputes the
landing title from the current settings every time, so renames and the
grade/marker toggles always reach the site) and the per-section
folders/files, each with plain `created`/`publish` frontmatter (no
per-section suffix needed — the file already belongs to exactly one
section). Two of the default per-section files, `Private Notes.md` and
`Scratch Page.md`, are created with `publish: false` — the teacher's own
pages, kept out of the built site until deliberately flipped.

### 8. Patch the in-container Quartz scaffold

Finally, the wizard applies two idempotent patches to the pristine Quartz
checkout at `/opt/quartz` (the template that every build copies from):

1. **Explorer omit anchor** — replaces `Component.Explorer()` in
   `quartz.layout.ts` with a configured call containing a `filterFn` and a
   marked line (`// CQ4T-OMIT-ANCHOR`) declaring `const omit = new Set([...])`.
   At build time, `build_site.py` rewrites this set with the course's hidden
   items. The anchor comment makes the rewrite target unambiguous. The filter
   is version 2 since #265 (top-level items by stored name; the marker
   `CQ4T-HIDE-RULE: v2`), and a section built before that is brought up to
   date on its next build — see
   [06 → B1](06-quartz-customizations.md#b1-explorer-omit-anchor-in-quartzlayoutts).
2. **OverflowList stable ID** — replaces `const id = randomIdNonSecure()`
   with a constant in `OverflowList.tsx`, so rebuilt pages do not differ
   just because a random DOM id changed (fewer files re-uploaded on deploy).

Both are described fully in
[customizations §B](06-quartz-customizations.md#b-patches-applied-at-setup-time-to-the-scaffold).

## What a course calls a unit, and where its class pages live

Two questions the wizard settles at creation, both recorded in
`course_config.json` and both documented key-by-key in
[the config reference](08-course-config-reference.md).

**`unit_word`** — class pages are named "Unit 2, Day 3", and the first word is
the teacher's. `prompt_unit_word` asks it of every course, ready-made ones
included, because the payload is written in that word as it is POURED rather
than renamed afterwards: `install_payload_file` rewrites the text and
`renamed_for_unit_word` renames the file. **It is asked only when the course
has no saved configuration** — changing it on a re-run would rewrite the
configuration and rename nothing, leaving pages the build no longer recognises.
A course already in use changes its word from the app's Course Settings
instead, which renames the class pages and follows the links before writing
the key ([09-mac-app.md](09-mac-app.md) → "Renaming a course's word for a
unit"); the launcher says so and leaves the word alone. An absent key means
"Unit", so every course made before this existed is untouched. "Day" is
deliberately fixed.

**`class_folder`** — which per-section folder holds the class pages. Recorded
rather than guessed from the word "class", because the guess quietly decided
what a teacher was allowed to call the folder: somebody whose vocabulary is
"Thread 2, Day 3" calls it "All Days", and the guess would then point the
next-class button and the curriculum map at whatever folder happened to be
first. Both wizards write it at creation, and a rename in Course Settings
writes it even on a course that never had one. The old guess is kept as the
fallback, never replaced.

**A re-run keeps the RECORDED `class_folder`** (#267, `class_folder_to_record`).
It used to rebuild the key from the guess alone, and the dict it wrote into
wins over the saved configuration — measured: `["Resources", "All Meetings"]`
guesses `Resources`, so a club the app had set up correctly would have been
rewritten to look for its meetings in the wrong folder. The recorded name wins
while it is still in the list; the guess is the fallback only.

## A club: one number, its own words, and what it starts with (#267)

A club — a coding club, a debate team — meets rather than holds classes. The
New Course wizard's **"This is a club"** choice writes
`class_page_scheme: "numbered"` with `unit_word: "Week"`,
`class_folder: "All Meetings"`, `front_page_heading: "Most Recent Meeting"` and
`class_noun: "meeting"` (all editable in the wizard, none switchable
afterwards — Russell, 2026-09-24), plus `use_skeleton` and
`prepopulate_example_content` false and the three curriculum keys false. See
[the config reference](08-course-config-reference.md) for each key.

What `setup_course.py` does with a numbered course (`ClubStart`):

- **No skeleton and no ready-made pages**, even if the configuration asks —
  a second net behind the wizard. Both are "Unit 1, Day 1" pages, which a
  numbered course does not read as class pages: every planner would see
  nothing and the build would report success.
- **Each section's NEW front page** gets `# <front_page_heading>`, a blank line
  and `![[<word> 1]]`. Only a front page the run creates; an existing one is
  never touched.
- **`<class_folder>/<word> 1.md`**, PUBLISHED, dated at creation, with no
  `unit-1` tag. Published because the front page embeds it: a landing page
  showing a withheld page is exactly what the assistant's repointing exists to
  prevent, and the repointing moves the embed only when a VISIBLE page is newer,
  so it would never fix this one. No tag because a club has no units, and the
  tag would make a Quartz tag page listing every meeting. **Written only for a
  section being MADE** — one whose `index.md` does not exist yet
  (`ClubStart.write_first_page`, called before the front page is written). A
  re-run of setup from the command line on an existing club used to recreate a
  deleted `Week 1.md` in every section, published and dated NOW, so the front
  page would follow it as the newest meeting (#267 implementation review; the
  app never re-runs setup on an existing course, so this was command-line
  only). A new section added to an existing club still gets its first page.
  `scripts/test_club_start.py` pins both.

REJECTED: a generated "club" skeleton family (more pages to maintain, for a
code prefix that means nothing); starting completely empty (then the heading
has no front page to be written into and the embed never exists — the mac's
repointing never INSERTS one).

**An existing course can never become a club.** Nothing reads the scheme into
a course that does not already say it, and Course Settings shows the settings
locked. Russell's `CODING` fixture — pages already named "Week N" in
`All Meetings`, no `class_page_scheme` — therefore stays exactly as it is: no
planner sees its pages as class pages, as before #267.

## Which of a course's folders the build treats specially

Most of a course folder is the teacher's to arrange however they like. A
handful of names are not: the build reads them, and renaming or deleting one
changes what appears on the site — usually without an error, because a folder
that is not there simply contributes nothing.

| What | Where the name comes from |
|---|---|
| The lessons folder | Every per-section folder the build counts as a class folder — the recorded `class_folder`, plus any whose name mentions classes; failing both, the guess described in [`08`](08-course-config-reference.md). New class pages are written to one; the coverage map counts all of them. |
| The curriculum folder | `curriculum_folder` if it names a folder the course has, otherwise the alphabetically first shared folder whose name mentions the curriculum. The BUILD asks one thing more than either app can see from configuration: the folder must actually hold a page carrying an expectation code. |
| The folders that count for marks | `graded_folders`, or — for a course never asked — every folder whose name contains "task". An ABSENT key and an EMPTY list are different answers; see [`08-course-config-reference.md`](08-course-config-reference.md). |
| `Media` | Managed by the build and kept out of the sidebar. |
| `index.md` | The page a folder opens on, in every section and every folder. |
| `Key Links.md` | The sidebar's shortcut list. The build adds the curriculum map to it and leaves the teacher's own entries alone. |
| `Curriculum Coverage` | Written by the build on every run. A teacher's own page of that name would be replaced. |

**Both apps can show a teacher this list for their own course**, from Course
Settings → "What else does Plantoir use my folders for?". Two things about
that sheet are deliberate and easy to undo by accident:

- **It names the folders the course actually has, never the rule that finds
  them.** "Your expectations live in Ontario Curriculum" is something a
  teacher can act on; "any folder whose name mentions the curriculum" invites
  them to get creative with it and turns an implementation detail into a
  promise the product then has to keep. This is also why the sheet is
  per-course rather than one static help page — the answers genuinely differ.
- **The names must come from the RESOLVED rules, not the raw configuration
  keys.** A course whose `curriculum_folder` was never written still has a
  curriculum folder as far as the build is concerned, and telling that teacher
  to create one they already have is the one failure a sheet about folder names
  cannot afford. **Both apps do this** — Windows from the start, the mac from
  2026-09-06, when it stopped reading the key and started asking the same rule
  that decides which folder is protected from removal. Two things narrow the
  answer, in both apps equally: the scan looks at the SHARED folders only,
  where the build walks the merged tree, and neither app can see whether the
  folder actually holds an expectation page — and when the recorded folder has
  none, the build does not give up, it falls through to the same scan. So the
  sheet can name a folder the build passes over in favour of another. Still
  righter than naming one that is not there.

The rows, the sentences and the cases are
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`specialFoldersHelp`, so both apps say the same thing about the same course.

## Example content, as the installer sees it

Ready-made course payloads ship in `support/example_content/<CODE>/` — 37 of
them as of 2026-08-15 and growing, so read the directory rather than any list
written here; detection is by the presence of `manifest.json`, which is what
the code does anyway. (SNC1W is the example course's content converted to
payload form, so a teacher actually teaching Grade 9 science gets it as
starting content; SNC2D is its Grade 10 sequel, and SCH3U/SCH4U carry
chemistry through Grades 11 and 12.) All
the installing, date logic, and curriculum handling is shared Python —
Windows needs exactly three UI behaviours:

- **Detection**: example content exists for a code when the bundled
  `support/example_content/<CODE>/manifest.json` exists; the curriculum
  toggle additionally needs the manifest's `curriculum_folder` to be
  non-empty (reference logic: `ExampleContentCatalog.swift`).
- **Starting Content section** in the new-course wizard: "Pre-populate
  course with example content" (default ON) with "Include Ontario
  curriculum pages" beneath it (default ON, disabled when the first is
  off). The SKELETON toggle goes BELOW that block (entry 123) — "Start
  from a <subject> skeleton" — and since 2026-09-21 it is a sibling of it
  rather than its `else`, so a code with ready-made pages shows it the
  moment those pages are turned down (#248). The quiet "empty folders"
  caption is the last resort, for a code with neither. (Both apps also
  show a caption while the skeleton toggle is OFF — which of the two
  sentences depends on whether the code has ready-made pages — and the
  toggle puts the defaults back when it goes off: step 0b above has that
  rule, which postdates this list.)
- **Structure lock**: when pre-populating, HIDE the folders/files
  editor behind a caption — the payload's manifest is the entire
  structure authority and the Python wizard skips all structure
  prompts.

Authoring new payloads is content work, governed by the repo-local
skill `.claude/skills/example-content/` and checked by its
`lint_payload.py` — no app code changes on either platform. The same skill
holds the skeleton generator and `lint_skeletons.py`; the skeletons are
generated output, so never hand-edit `support/skeletons/`.

Two payload conventions have changed since these entries, both handled by
shared Python: course-level pages now arrive with
`createdSectionN`/`publishForSectionN` (one pair per section — entry 122), and
`Key Links` ends with the site tour (entry 121).

## Which folders count for marks: absent is not empty

The Curriculum Coverage map shows an expectation as ASSESSED — the ring on a
cell, and Ontario's ask that every overall expectation be evaluated at least
once — when a page addressing it lives in a folder that counts for marks. That
used to be hardcoded in `build_site.py` as *any folder whose name contains
"task"*, and a teacher who called theirs "Tests", or renamed "Tasks", silently
lost every assessed mark on the map with nothing said.

It is now `graded_folders` in `course_config.json`, matched by EXACT
folder-segment name at any depth (so `Tasks/Unit 1/Quiz.md` still counts, and a
page is never assessed because of what it is CALLED).

### The one mistake that matters when porting this

**`GradedFolders` must distinguish ABSENT from EMPTY.** A plain
`List<string>` that defaults to empty when the key is missing would tell the
build "this teacher has no graded folders", and every course made before this
key existed would lose every assessed mark on its map — silently, because a map
with no rings still renders and still looks finished.

- ABSENT means the teacher has never been asked. The build applies the
  historical substring rule, and the course keeps exactly the marks it had.
- EMPTY (`[]`) means they were asked and cleared it. That is a real answer and
  is honoured.

The mac models it as `[String]?` and REMOVES the key when set to nil
(`CourseConfiguration.swift`). Whatever you use, make the round trip preserve
"no key at all" — and check your serialiser, because both apps write this file
wholesale from an in-memory copy.

### Do not seed existing courses

The obvious migration — write `["Tasks"]` into every course — is wrong, and the
repository proves it rather than the reasoning alone. All 38 payloads use
"Tasks", but the mathematics skeleton family ships **"Thinking Tasks"**: the
substring rule counted it, an exact pool of `["Tasks"]` does not. Seeding would
have quietly stripped that course's assessed marks.

Nothing is written back from a BUILD either. Be precise about why, because the
first version of this paragraph overstated it: both apps DO preserve keys they
do not recognise, so a build's write is not dropped in general. The real risk is
narrower and quite sufficient — an app holding a copy of the file it loaded
BEFORE the build wrote the key overwrites it at the next save, and a teacher
with Settings open while a preview runs is ordinary, not a corner case.

**One thing you will notice immediately: `FileFormats_CourseConfigKeys_MatchesContract`
is RED on Windows, deliberately.** `contracts/file-formats.json` now documents
`graded_folders` and `CourseConfiguration.cs` does not read it yet. That is the
contract working as designed (CLAUDE.md rule 4) — a request, not damage. It goes
green when you add the property, and the absent-vs-empty note above is the whole
of what it has to get right.

### What the Settings control does, and why

The mac's is a checklist of the course's folders, under a "Marks" heading. When
the course has never been asked, it shows the folders the build CURRENTLY counts
already ticked, so a teacher sees what is actually happening rather than a blank
list. Nothing is written until they change something — and the moment they do,
the answer is explicit and the historical rule stops applying to that course.

### What the control is CALLED, and the caption below it

Both are one contract case — `contracts/shared-rules.json` → `gradedFolders`
.`wording` — because the same two sentences serve four surfaces: Course
Settings and the New Course wizard, on both platforms. Until 2026-09-08, when
Windows proposed the case, they were four distinct strings written out as eight
literals — a title and a caption in each app, duplicated across that app's two
surfaces — and nothing pinned any of them; the
mac adopted it on 2026-09-09 ([#71](https://github.com/russellgordon/plantoir/issues/71)),
where they live in `GradedFolderWording` and the two views draw from it.

Three things in that caption are worth knowing before editing it, because each
was argued the other way first and the contract's `why` carries the full
argument:

- **It says "tick", never "add" or "remove"** — a correction rather than a
  preference. The control is a table of checkboxes with no Add button (a tick list until
  issue #266 made it a table; the rule is unchanged), so the mac's
  previous caption named two actions it does not offer, and "remove what you
  don't" invited the one thing the product refuses outright: unticking the last
  graded folder while the coverage map is on.
- **The map is "the curriculum coverage map"** here, matching the flyout raised
  from this list and the switch beside it, so one screen says one name three
  times. The folders-help sheet still says "the curriculum map", **deliberately**
  — a recorded mixed state, not drift to be tidied up, and `SpecialFoldersHelpView`
  says so where the tidying would happen.
- **The caption belongs BELOW its list**, which `wording.rule` requires by name:
  it says "a page in one of these", and above the list "these" follows the
  section header "Marks" and refers to nothing. Windows drew it above until
  2026-09-08. A mac test reads source order for this, since inside the `Section`
  and `VStack` these live in, source order is stacking order; hosting the view
  and walking it was rejected because `Form` renders lazily on macOS and would
  buy nothing over reading the order directly.

One imprecision is inherited and flagged rather than fixed: the coverage map's
own word is "assessed" and the caption says "evaluated". It says it because the
folders-help row has said it since that sheet was written, so changing it is a
separate piece on both platforms.

### What the checklist OFFERS, and the two traps in walking a folder to find out

The list is the course's `shared_folders`, then its `per_section_folders`, then
every folder found inside the course itself, four levels down — because the
build counts a graded folder at ANY depth, and a checklist built from the two
top-level lists alone would let the first tick freeze a pool without
`Portfolios/Tasks` in it. The rule, its skip list, its depth cap and its 14
cases are `contracts/shared-rules.json` → `gradedFolders.choices`, run by
`GradedFolderChoicesTests` on both platforms against REAL directory trees: a
walk over a fixture is not a walk.

Two things about it cost real time, and both were found by one platform and
paid for by the other.

**A folder the teacher REMOVED is still on disk, so the walk hands it back.**
`excluded_items` is what a removal writes, and the walk must consult it or the
confirmation's own promise — "Removing it will take it out of your course's
marks pool" — is broken on the very next redraw. Filtered at the two levels the
build's preflight scan discovers: the course's own children against
`excluded_items.shared`, a section folder's children against
`excluded_items.per_section`, matched exactly, case included. (A `sectionN`
folder hands that per-section scope to its children wherever it is found, not
only directly inside the course — both apps have always done it, it falls out
of passing the scope down a recursive walk, and a case now says so rather than
leaving the two to drift apart the first time anyone tidies one of them.) The cost is
recorded rather than hidden: a pooled name found ONLY inside the removed folder
then has no row to untick until the folder is put back. Nothing is lost — a
pooled name with no row is preserved rather than dropped — and it is not
silent, because `_has_graded_folders` walks the MERGED tree, so a pool matching
nothing published reports that no folder counts for marks exactly as an empty
pool would.

**And a consequence of that filter, which is a rule in its own right** —
`gradedFolders.removingAFolder`, seven cases. Removing a folder takes its name out
of the marks pool, with two exceptions, and both exist to stop a removal quietly
taking marks OFF the map:

- **A course that has NEVER been asked is left unasked.** Freezing wrote the
  historical rule's answer minus the removed folder, and on the ordinary course
  whose only marked folder is `Tasks` that is an EMPTY pool: nothing counting
  for marks, permanently, from a removal the teacher was told only would take
  one folder out of it. An absent key keeps the historical rule running, so a
  `Thinking Tasks` still counts and putting the folder back restores it.
- **A name that still counts somewhere else keeps its place.** The pool is a
  list of NAMES, so when `Portfolios/Tasks` survives a top-level `Tasks`, the
  checklist still offers `Tasks` and it still names published work. This is in
  slight tension with the confirmation's literal words — the FOLDER left the
  course, a folder of that name did not — and the trade is deliberate: a pool
  entry naming published work is worth more than a sentence read to the letter.

Both fall out of one instruction: recompute what the checklist offers AFTER the
removal is recorded, and drop the name only if it is no longer among them —
asked the way the BUILD asks it, case ignored — AND the course had already been
asked.

Two edges of that, recorded rather than left to be met. The second exception
says "still OFFERED", not "still counts": the checklist sees four levels and the
build counts at any depth, so a `Tasks` five levels down is dropped from the
pool and goes on counting. And the "at least one folder must count for marks"
floor — the one that refuses to unpick the last pooled folder while the coverage
map is on — asks whether this is the last NAME in the pool, not whether the pool
would survive the removal. So it still blocks removing a top-level `Tasks` on a
course where `Portfolios/Tasks` would have kept the name. Conservative, rare,
and the same on both platforms; sharpening it would be a shared change.

**Order is the whole subject.** Ask before
the exclusion is written and the removed folder is still on the list, so the
pool freezes — which is what the mac did until 2026-09-09 and Windows until
2026-09-18, from a walk cached one `BuildForm` pass earlier ([issue
#142](https://github.com/russellgordon/plantoir/issues/142)). **Both platforms
now follow the rule.** On Windows the whole gesture is one Core method,
`FolderRemoval.RemoveFolderFromCourse` — the copy list, then `excluded_items`,
then the walk, then the pool decision — and it is in Core rather than in the
view precisely because the order is the rule: `Plantoir.Tests` references
`Plantoir.Core` alone, so a test calling a pure pool function while the order
lived in `CourseSettingsView` would have stayed green through the very
reordering that causes the bug. Mutation-measured there on 2026-09-18: putting
the pre-fix body back turns cases 1, 2, 5 and 6 red, the old pool semantics over
a CORRECT walk turn 5 and 6 red, and reordering the walk before the exclusion —
or leaving the exclusion out — turns 3 and 4 red.

**On the mac the order has one owner too, and since
[#183](https://github.com/russellgordon/plantoir/issues/183) (2026-09-26) the
contract drives it.** Since #266 both folder lists' removal is one method,
`CourseSettingsView.folderWasRemoved(_:scope:)` — `excluded_items`, then the
pool, then the trail line — called from the list editor's
`StringListEditorView.removeItem(named:)` after the editor has written the copy
list. Until #183 the mac's contract runner (and three other tests) REPLAYED
those steps by hand in the order they were believed to run, so a reorder inside
`folderWasRemoved` left every case green. Measured before the change: moving the
pool above the exclusion, or leaving the exclusion out, kept all seven cases and
every `SpecialFoldersProtectionTests` case green. The only red was the #266 byte
golden (`ListTableGoldenTests`), by accident, and that is not a pin: its message
says the tables changed the saved bytes rather than that the order broke, a
golden is re-captured whenever a legitimate change moves the file (a re-capture
on a mutated tree takes the regression in silently), and it covers one removal
in one scope. Now the runner removes through the editor
(`CourseSettingsGestureScript.editor(for:of:).removeItem(named:)`), and each of
four mutations — pool above exclusion, exclusion left out, pool left out, or
`onRemove` called before the editor writes the list — turns cases 3 and 4 red:
the same pair as on Windows. Cases 1, 2, 5, 6 and 7 stay green under a reorder,
correctly: there the name is still offered or the course was never asked, so
the pool is left alone whatever the order.

**Windows owes nothing for this**: its order was already pinned through
`FolderRemoval.RemoveFolderFromCourse`, and no case changed. The trap it records
applies to both sides on any later refactor: a runner that replays the steps
instead of calling the gesture's owner stays green through exactly the bug the
rule exists for. REJECTED on the mac: moving the removal into a model function
to mirror Windows' Core method (`folderWasRemoved` is already the single owner
and reachable from a test, so it would buy symmetry no test needs), an authored
`sequence` field in the contract (neither runner could assert it without
instrumenting internal calls, which tests how the code is built rather than
what it does, and Windows would owe a runner change for no gain), and relying
on the #266 golden. **One seam stays unpinned**:
`CourseSettingsGestureScript.editor(for:of:)` is a hand copy of `body`'s wiring,
so if `body` ever wired a folder list differently — another method than
`folderWasRemoved`, the other scope, a binding to another list, or different
protection or notice closures — these tests would stay green. Closing it means extracting the editors into
a function both the view and the tests call — a view refactor with its own
reviews, not part of #183.

**A course damaged by the old behaviour is NOT repaired, decided 2026-09-18.**
It keeps its frozen pool until the teacher ticks or unticks something, and
neither app goes looking. The reason is that nobody can have been damaged by a
version they were given: the freezing code (`a3c581fb`, 2026-08-25) is in no
release tag and not on `main`, and `git grep -l graded_folders v1.1.0` comes
back empty — the whole key is unreleased, so only a development build could have
written one. And a repair could not identify what it was repairing even if it
went looking: a pool written as `[]` by a removal is byte-identical to the
deliberate empty pool the rule's own fourth case calls a legitimate answer, and
correlating it with `excluded_items` collides with exactly that case — a teacher
who unticked everything and then removed a folder looks the same from the file.
REJECTED, so neither is proposed again: **detect-and-offer**, which would have to
ask a teacher about a state it cannot identify and would put that question in
front of courses that had simply answered "nothing counts"; and **silent
auto-repair**, which would rewrite a deliberate answer without asking — the same
failure this rule exists to prevent, arriving from the other direction. A
genuinely damaged course is not left with nothing: `site_health.py` raises
`noGradedFolders` for an empty pool exactly as it does for a pool matching
nothing published.

**The STILL-OFFERED half is asked CASE-INSENSITIVELY, and the seventh case
pins it** — added 2026-09-19 from [issue
#172](https://github.com/russellgordon/plantoir/issues/172), which was raised
from Windows. The walk returns names as they are spelled on disk, so removing a
top-level `Tasks` while `Portfolios/tasks` survives offers `tasks`; an exact
"still offered" test reads that as "no longer offered", drops `Tasks` from the
pool, and leaves `build_site.py` — which lowercases both sides in
`_is_graded_path` — still counting that folder. Marks off the coverage map
because of a capital letter. Windows has asked case-insensitively since
2026-09-18 and proposed the case rather than committing it; on the mac it was
RED until `CourseSettingsView.dropFromMarksPool` stopped asking with `contains`,
and cases 1-6 stayed green throughout, which is the measurement Windows
reported — the six all use one spelling and cannot see the difference.

**Which case-insensitive comparison, measured rather than picked** (2026-09-19,
this Mac; `GradedFolderChoices.stillOffers` carries the same table in short).
The question has to be answered the way PYTHON answers it, because Python is
what counts the folder:

| pair | Swift `lowercased()==` | Swift `caseInsensitiveCompare` | Python `str.lower()==` |
|---|---|---|---|
| `Tasks` / `tasks` | true | true | true |
| `Straße` / `STRASSE` | false | **true** | false |
| `Σ` / `ς` | false | **true** | false |

- **`localizedCaseInsensitiveCompare` is rejected**: it reads the CURRENT
  locale, and it is the one comparison with no column in that table because the
  table's answers do not depend on the machine and its do. Measured:
  `compare("I", "i", options: [.caseInsensitive], locale: tr_TR)` answers NOT
  EQUAL where the same call with `locale: nil` answers EQUAL, so a
  Turkish-locale Mac would disagree with the build about the plainest ASCII
  names.
- **`caseInsensitiveCompare` is rejected**: locale-independent, but it folds
  FURTHER than Python, which is what the build uses — the two rows above.
  (C#'s answer on those two pairs was not measured on this Mac.)
- **`lowercased()` equality is chosen**: locale-independent (it folds `I` to
  `i` where `lowercased(with: tr_TR)` gives `ı`), the same fold `str.lower()`
  performs, and the same answer `OrdinalIgnoreCase` gives on ASCII. They are
  not one fold beyond it: `U+212A KELVIN SIGN` against `k` is true for
  `lowercased()` and for `str.lower()` (both measured here) where
  `OrdinalIgnoreCase` should answer false, since it upper-cases and
  `ToUpperInvariant('k')` is `K` — read off the spec rather than measured,
  there being no `dotnet` on this Mac. Nothing is pinned there. Note also that
  this is deliberately
  NOT the house idiom: `caseInsensitiveCompare` is what mac model code asks
  folder-name questions with elsewhere, because those are questions only the app
  answers.

Non-ASCII is where all three stop agreeing and nothing pins them: `İ` (U+0130)
lowercases to `i` plus a combining dot in Swift AND in Python, matching neither
`i` nor `I`, and Swift's `==` treats a decomposed `Café` as equal to a
precomposed one where Python's does not — which errs toward KEEPING a pool
entry, the direction this whole rule errs in.

**What is still NOT pinned is the DROP's own comparison.** The mac takes the
name out of the pool exactly; Windows uses `OrdinalIgnoreCase`. It shows only on
a course whose pool and whose folder spell one name two ways, where the mac
keeps a pool entry whose folder has gone and Windows removes it. Both err
safely — nothing counted is lost either way, and `site_health.py` raises
`noGradedFolders` for a pool matching nothing published, on a course whose
coverage map is on AND whose site has curriculum expectations (`site_health.py`
:145: `coverage_wanted and curriculum_found and not graded_folders_found`) — so
it is left unpinned. The two halves are not free of each other,
though: **the still-offered test must be at least as PERMISSIVE as the drop.**
That is the mac's shape now (case-insensitive test, exact drop) and Windows'
(one comparer for both). Reverse it and a name can be judged absent and then
removed anyway.

**Keep the never-asked guard.** It looks dead: with the walk taken after the
exclusion, replacing it with the materialised pool leaves every case green,
because the historical rule only ever names folders drawn FROM the choices — the
copy lists plus the walk — so a name the still-offered test has just rejected
cannot be in the materialised pool either. That redundancy holds only while the
drop is no more permissive than the still-offered test, which is the constraint
above. **Measured ON WINDOWS, 2026-09-18, on code whose drop is
`OrdinalIgnoreCase`**: with an exact still-offered test and the guard replaced
that way, a never-asked course removing a top-level `Tasks` while
`Portfolios/tasks` survives writes `graded_folders: []` — nothing counting for
marks, permanently. The #142 damage itself, brought back by tidying away a check
that looked redundant. **That `[]` is a Windows number and must not be read as a
mac one**: the same mutation on the mac stops one line lower, at
`!currentGraded.contains(name)`, because the drop here is exact — the
materialised pool is `["tasks"]` and the name is `"Tasks"`, so the course stays
unasked. A mac reader who tries the stated mutation and sees the suite stay
green must not conclude the guard is dead.

Nothing new is written to the activity trail for any of this. The removal
already leaves its own line (`item excluded`), and what changed is only which
folders are OFFERED — which is not something a teacher DOES, and a trail line
for it would record a redraw.

**The ORDER is ordinal, case-insensitive, and every shorter way of asking for
that is a different question.** Directory enumeration order is the filesystem's
business, so the children of each folder are sorted — otherwise the same course
lists differently on two machines, and no case could pin an order at all. Which
comparison, measured on a Mac 2026-09-09 while adopting the rule:

| Asked this way | `Unit 10` vs `Unit 2` | `_Archive` vs `Alpha` |
|---|---|---|
| `localizedStandardCompare` (Finder order) | `Unit 2` first | `_Archive` first |
| `compare(options: [.caseInsensitive])` | `Unit 10` first ✅ | `_Archive` first |
| C# `OrdinalIgnoreCase` — what shipped | `Unit 10` first ✅ | `Alpha` first ✅ |

The trap is the middle row: it looks right, and it is right about digits, and
it is wrong about the six ASCII characters between `Z` and `a` (`[ \ ] ^ _ `)
because Foundation folds to LOWER case where C# folds to UPPER. `_Archive` and
`~Old` are ordinary names for a folder a teacher wants at one end of a list. The
mac therefore precomposes, upper-cases, and compares UTF-16 code units by hand
(`GradedFolderChoices.sortsBefore`), and a contract case pins each row of that
table, so the two suites disagree rather than the teachers. Accented names are
deliberately NOT pinned: macOS hands back decomposed spellings and Windows
precomposed ones, and a case would promise what neither platform can keep on the
other's files.

Finder order is arguably nicer for a person reading a list. If anyone wants it,
it is a shared change to the contract and both apps — not something to reach for
on one side because it looked more natural there.

### A command-line re-run leaves the marks pool alone (#192)

**A run of `setup_course.py` that finds a saved `graded_folders` writes it back
as it was** — same names, same spelling, same order, whatever the folder lists
the run ends with and whatever is on disk. A saved `null` is written as `[]`
(as it always was), and a course that never had the key still has none. The
one cleaning left is of entries that cannot name a folder at all — null, a
blank string, a non-string, an exact repeat — which only a hand edit writes
and which the old path also removed (`saved_pool_without_malformed_entries`);
every real name stays, including one with no folder behind it. Only a
NEW course made on the command line — no saved `course_config.json` at all —
has its pool worked out from the payload or skeleton and reconciled against
its folder lists by `graded_folders_for`; a new course made in either app
arrives with its pool already in the saved file, written by the wizard (see
the #292 section below for what happened while one path did not). The contract is `contracts/shared-rules.json` →
`gradedFolders.rerunningSetup`, eleven cases, run by
`scripts/test_graded_folders_rerun.py`, which drives the real wizard in-process
(`input` and `getch` replaced, every prompt answered with Return) — on the mac
host in `verify.sh`'s first step and on Windows through `PythonToolchainTests`.
Neither app runs it, because neither ever re-runs setup on an existing course.

**Why.** The re-run used to pass a saved pool back through the new-course
reconciliation, which keeps only names on the TOP-LEVEL copy lists
(`shared_folders` + `per_section_folders`). That rule was written on
2026-08-24, two weeks before the Marks checklist began offering folders found
INSIDE other folders (`gradedFolders.choices`, #79/#112), and nobody changed
the re-run. Measured on 2026-09-25 by driving the real wizard with every prompt
accepted and no folder removed:

| saved pool | lists the run ends with | on disk | written back before #192 |
|---|---|---|---|
| `["Tasks"]` | Concepts, Portfolios | `Portfolios/Tasks` | `[]` |
| `["Tasks"]` | Concepts / All Classes | `section1/Tasks` | `[]` |
| `["Tests"]` | Concepts, Tasks | `Tasks/Tests` | `[]` |
| `["Tasks"]` | Concepts, tasks | `tasks` | `["tasks"]` (respelt) |
| `["Tasks"]` | Concepts, Tasks | `Tasks` | `["Tasks"]` |

The first three are exactly what the checklist WRITES when a teacher ticks a
nested folder, so a teacher who ran `./setup.sh` again to change a colour lost
every mark in those folders — `[]` is "asked, and nothing counts", and the
historical rule never applies to the course again. The issue as reported
(a removal's preserved entry, `removingAFolder`'s fifth case, emptied by the
next re-run) is one road into the same fault.

The re-run does not ask the marks question and has no way to remove a folder,
so it does not own the answer. Two more measurements say nothing was lost by
dropping the reconciliation:

- **It never counted more.** Over the shapes above plus two with a name that
  names no folder, counting pages with the build's own `_is_graded_path`, the
  reconciled pool counted the same pages or FEWER in every shape. A respelling
  counts the same (the build lowercases both sides); the only shapes where the
  written value changed what counts were the FOUR that lost marks — the first
  three rows above, and the prompt-drop shape in the next point, which wrote
  `[]` for a folder the next build published again.
- **A name taken off a copy list at a prompt is not a removal.** With `Tasks` on
  disk but off `shared_folders`, one call of
  `build_site.preflight_update_course_config` puts it straight back
  (`['Concepts']` → `['Concepts', 'Tasks']`), and the command-line wizard writes
  no `excluded_items`. Dropping the name from the pool stopped counting a
  folder that was still published.

**A name that names no folder is kept, and it is not invisible.** It counts no
page, but the published Curriculum Coverage page names every pooled folder in
its sentence about what counts (`build_site._graded_folders_in_words`), and
Course Settings' last-folder guard counts it, so the last LIVE folder can be
unticked without the block. `site_health` raises `noGradedFolders` only when the
coverage map is on, curriculum pages are found and nothing in the pool matches a
published folder — so a dead name beside a live one raises nothing. Both effects
could already happen through the apps' own exact-match removal
(`removingAFolder`), and the contract's tenth case pins the name being KEPT so
that nobody adds a clean-up by existence here that the apps would disagree with.

**This retires the "second net".** This page, three Swift comments and the
`wizard.skeletonToggle` reasoning used to say `setup_course.py` "reconciles the
key again when it reads it" behind the apps' own narrowing on a new course.
Both apps write `course_config.json` BEFORE they drive the setup script, so an
app-created course always takes the re-run path; there the reconciliation was a
no-op, since each wizard narrows its pool before writing (mac
`GradedFolderRule.reconciled`, Windows `CurrentGradedFolders`). What the net
could still catch was a name that counts nothing. Now each wizard's narrowing
is the only one.

**REJECTED**, so they are not proposed again:

- *Reconcile against the checklist's own walk* (depth four, the skip list,
  hidden folders, links and reparse points, `sectionN` scope, `excluded_items`)
  — a THIRD implementation of the walk, kept in step with two apps, to drop only
  names that count nothing; with a Windows-only reparse-point caution nobody on
  the mac can test.
- *Reconcile against every folder at any depth* — a walk rule of its own, the
  same payoff.
- *Keep the respelling, drop only unmatched names* — marks-neutral, and a pool
  one tool rewrites and the others do not is a file two apps can disagree about.
- *Tell an app's new-course run from a command-line re-run* (an empty course
  folder, say) so the old check stayed on the app path — a guess about intent,
  for a net that caught nothing that counts.

**Not done.** Courses already emptied by a re-run are not repaired: a re-run's
`[]` is byte-identical to a teacher's deliberate one. And `null` still reads
differently in the mac app (never asked) and the build (asked and cleared); the
re-run keeps writing `[]` for it, and the ninth case records that as today's
behaviour rather than as a decision.

### Content declares its own pool

All 39 payload manifests and all 50 skeleton families now carry
`graded_folders`, and both linters refuse a manifest without one or one naming a
folder the course does not have. It reaches a NEW course by two routes, and they
must write the same thing. On the command line `setup_course.py` writes it at
creation from the manifest (`graded_folders_for`). In either app the WIZARD
writes it — the payload's pool for a course taking ready-made pages, the
skeleton's or the teacher's own ticks otherwise — into the `course_config.json`
it creates before setup runs, because setup reads a saved file as answered and
never works the pool out over one. That second half was missing for a
pre-populated course until #292; see the next section.

Declared rather than inferred deliberately: inference is a substring while the
build matches exactly, and those two agree for 88 of the 89 courses here and
disagree for the one that would have been broken by it.

### A course made in either app from ready-made pages had no marks pool (#292)

**The mechanism.** Both apps write `courses/<CODE>/course_config.json` FIRST
and then run setup with no arguments (`NewCourseCreator.swift`;
`NewCourseDialog` on Windows). `setup_course.py` decides the pool by whether a
saved configuration EXISTS, not by whether the course is new: over a saved
file it writes back a saved `graded_folders` (#192) and leaves the key ABSENT
when the file had none; only with no saved file at all — a command-line run —
does it call `graded_folders_for` on the manifest. And both wizards
deliberately left the key out when the structure came from example content,
believing setup would take the pool from the manifest. Windows' comment above
`NewCourseDialog.BuildConfiguration` says so ("prefers a pool already present
in the saved config over the manifest's"). That is half true: a saved pool does
win, but a saved file WITHOUT one does not fall back to the manifest. So every
pre-populated course either app made had no `graded_folders`, which reads as
"never asked".

**How long.** Two commits crossed on 2026-08-24. At 10:39 `11a70b7e` made a
saved-config run stop deriving the pool (before it, `392bf357` wrote the
manifest's pool on every run, the app's included). At 11:41 `e9d71d8d` made
the wizard write the pool on every path EXCEPT a payload, on the old
assumption. #192 did not touch this path.

**Measured** (2026-09-26, the real `setup_course.setup_course` driven
in-process): a command-line TAS2O or ADA1O with every prompt accepted is
written `["Tasks"]`; the same run over the file the mac wizard wrote for ADA1O
leaves the key absent; that file with `["Tasks"]` added keeps it.

**What a teacher saw.** Not an empty Marks checklist, as the issue first said:
with the key absent, Course Settings shows the inferred folders ticked. All 39
payloads declare `["Tasks"]`, the historical rule infers the same from their
lists, and the only "task" folder in any payload is `shared/Tasks`, so the
build counted the same pages and no mark was missing. What differed:

- the published Curriculum Coverage page said "any folder with “task” in its
  name" where a command-line course said "**Tasks**"
  (`build_site._graded_folders_in_words`);
- the course stayed never-asked, so a later folder with "task" in its name was
  counted automatically, renaming `Tasks` to a name without "task" silently
  stopped counting it (`SpecialFolderRenamer` rewrites only a key that is
  present), and removing `Tasks` left the key absent rather than writing `[]`;
- a future payload whose pool is not `["Tasks"]` would have lost marks in the
  apps while working on the command line.

**What changed.** The app owns the answer, because it is the only party that
knows the course is new. `ExampleContentCatalog.marksPool(fromManifest:)`
mirrors `graded_folders_for` exactly as setup calls it for a payload: the
shared folders without `Media` (and — on the command line only — without the
curriculum folder when its pages are declined, which no payload's pool names,
so the apps do not model that step), then the per-section ones; a declared name kept
when it matches a folder exactly, respelled to the folder's spelling when it
matches ignoring case, dropped otherwise; blanks, nulls, non-names and repeats
dropped; a declared null or `[]` gives `[]`; inference only when the key is
absent. `buildConfigurationDictionary` writes it when
`takesExampleContent && hasContent` — so never for a club, which takes no
ready-made pages. An unreadable manifest leaves the key absent, as before.
`setup_course.py` did not change. Windows has the same gap and owes the same
change (the `windows` issue for #292).

One behaviour follows that is intended, not a regression: with the key now
present, `removingAFolder` applies to a new payload course, so removing `Tasks`
in Course Settings writes `[]` (with the coverage warning) instead of leaving
the key absent — which is what a command-line course has always done.

**REJECTED**, so they are not proposed again:

- *A Python fix* that treats "the saved file is the only thing in the folder"
  as a new course and derives the pool. Free for Windows, and that is its only
  merit: it infers newness from disk state, which is wrong for a teacher who
  deletes a course's pages and re-runs setup; it carves an exception into
  `rerunningSetup` the day after it landed; and it makes two writers of one
  answer, since the apps already write the pool on every other path.
- *Dropping the wizard's guard and writing its own list.* The structure editors
  are collapsed for a payload course, so that list is the wizard's default,
  reconciled against the wizard's default folders rather than the payload's.
  It happens to give `["Tasks"]` for all 39 today, which is exactly why it
  would pass every literal test while being wrong — the contract's MCV4U case
  with a hidden `["Tests"]` exists to catch it.
- *Reusing `GradedFolderRule.reconciled`* (exact match) on the manifest's
  pool. That reconciles a teacher's own ticks; this reproduces what the command
  line writes, which matches ignoring case and infers when the key is absent.
  The contract's respelling case is red for it on the mac and green in Python.
- *Reading `SkeletonCatalog.adoptedGradedFolders`* — the wrong source, and it
  reads a declared `[]` as "infer".

**Not done: existing courses are not repaired.** A migration cannot tell such a
course from a legacy course that was never asked, or from one where the
teacher has since added "Performance Tasks", which the historical rule counts
and a frozen `["Tasks"]` would not — the "Do not seed existing courses"
argument above, again. Measured, no mark changes for any of them; what they
keep is the unconfigured Coverage-page sentence and the rename edge, and the
first tick in Course Settings → Marks makes the pool explicit, as it does for
every legacy course.

**Why the tests look the way they do.** Every shipped payload and the
wizard's default say `["Tasks"]`, so any wrong source passes a literal case.
What discriminates is the MCV4U case with a hidden `["Tests"]` (the wizard's
own list leaks as `[]`; the mathematics skeleton's pool reads as `["Thinking
Tasks", "Tasks"]`), the eight made-up `manifestCases`, and a club case whose
own list is `["Exercises"]`. One mutation is honestly NOT caught on the command
line: pointing setup at the skeleton instead of the payload stays green there,
because `graded_folders_for` reconciles any declared pool against the
PAYLOAD's folders and no payload has "Thinking Tasks". The mac catches it,
because nothing there reconciles the skeleton's list against the payload's.

### Where the rules live

`contracts/shared-rules.json` → `gradedFolders` (10 cases for which folders
COUNT, run by `scripts/test_graded_folders.py` in the image — neither app
implements that rule, so neither suite runs them), `gradedFolders.choices`
(14 cases for what the checklist OFFERS, run by both apps) and
`gradedFolders.rerunningSetup` (11 cases for what a re-run of setup writes back,
run by `scripts/test_graded_folders_rerun.py`) and `gradedFolders.newCourse`
(6 cases and 8 `manifestCases` for the pool a NEW course is written, #292 — run
by the mac's `WizardStructureTests` and `ExampleContentContractTests`, and on
the command line by `scripts/test_graded_folders_new_course.py`, which Windows'
`PythonToolchainTests` discovers; Windows owes the app half). The key itself is
in `contracts/file-formats.json`.

## “Where do the class pages live?” had four answers

A teacher whose class folder is not called "All Classes" — "Class Pages", say —
used to get a different answer from each of four places:

| Where | What it asked |
|---|---|
| mac `ClassPages.folderURL` | the course's CONFIGURED per-section folders, first containing "class" |
| mac `AssistSectionGraph.isClassPage` | the page's IMMEDIATE parent contains "class" |
| `build_site.py` | any segment of the ABSOLUTE path EQUALS "all classes" or "classes" |
| Windows `AssistWorkspace.Plan` | the whole ABSOLUTE directory string contains "class" |

Three of those are wrong in ways worth knowing:

- **The build's.** Exact strings, so "Class Pages" matched nothing. When no
  class pages are found, `_pages_the_course_teaches` returns `None` and the
  Curriculum Coverage map falls back from "pages the course teaches" to "every
  published page". The map still renders, still looks healthy, and is wrong —
  the failure this whole piece exists to close.
- **The build's, again — and this is a CORRECTION to what this section said
  first.** An earlier draft claimed the build had been counting pages by their
  file NAME, and named "How This Class Works.md" and ADA1O's "B3. Connections
  Beyond the Classroom.md" as pages it had miscounted. That was wrong. The old
  rule was `part.lower() in ("all classes", "classes")` — membership in a
  tuple, i.e. EQUALITY — so no page was ever counted for its name. The real
  defect in the same line was different and worse: `content_root.rglob` yields
  ABSOLUTE paths, so it walked every segment above the content root too. A
  teacher whose working folder was `~/Documents/All Classes` made every page in
  every course a lesson — the same bug Windows had, on the other platform. The
  file-name exclusion is kept as defence in depth for a future change to
  substring matching, and is labelled as such rather than as a fix.
- **Windows.** `Path.GetDirectoryName(pagePath)` is the absolute directory, so a
  teacher whose working folder is `C:\Users\x\Classroom\` makes **every page
  in every course** a class page. Where somebody keeps their files is not a fact
  about their lessons. This is the one that needed fixing most and could not
  have been found from the mac.

**The one rule**, in `contracts/class-planning.json` → `classFolder`:

- *naming* (where a NEW page is written): the first configured per-section
  folder whose name CONTAINS "class" (case-insensitive), else the first entry,
  else the literal "All Classes". Substring is safe here — it is a short list
  the teacher chose.
- *membership* (which folders COUNT): EVERY configured per-section folder whose
  name contains "class", falling back to the single name naming chose. Added
  after review: naming and membership are the same question only when a course
  has one such folder, and a course configured
  `["Class Resources", "All Classes"]` would otherwise resolve to the first for
  both, match zero pages, and drop the coverage map back to "every published
  page" — reintroducing the exact silent failure the rule closes.
- *isClassPage*: not an `index.md`, and one FOLDER segment — never the file
  name — EQUALS that folder's name, case-insensitively, with the path taken
  RELATIVE to the content root.

The asymmetry is deliberate and is the part worth not "simplifying" later:
naming may use a substring because its input is curated; page matching may not,
because its input is arbitrary paths. A classics course's "Classical Studies"
folder must not be mistaken for where its lessons live.

**What changed on Windows:**

- new `Plantoir.Core/Models/ClassFolderRule.cs` — `Name(...)` and
  `IsClassPage(relativePath, classFolder)`. It is called `ClassFolderRule`, not
  `ClassFolder`, because `AssistWorkspace` already has a private `ClassFolder`
  method that returns a PATH, and two things with one name returning different
  kinds of answer is how the next bug gets written;
- `AssistWorkspace.Plan` now calls
  `ClassFolderRule.IsClassPage(PathWithinSection(...), ClassFolderRule.Names(...))`
  — it passed `Relative(pagePath)` first, which is what fixed the `Classroom`
  bug, and was narrowed again to the SECTION on 2026-09-19 (the section below).
  **The rule is a pure segment matcher and cannot tell an absolute path from a
  relative one**, so what is passed IN is the whole protection: if you ever call
  `IsClassPage` from somewhere else, pass a section-relative path or you
  reintroduce the bug. The mac learned this the same way — its own
  `AssistSectionPage` had to gain a `pathWithinSection` because `relativePath`
  is the FULL ABSOLUTE PATH whenever `workspaceURL` is nil;
- `ClassFolderRule.Name`/`Names` skip null and empty entries: these lists come
  from JSON, including the contract's own case data, and unguarded LINQ threw
  where Swift and Python coerce;
- `AssistWorkspace.ClassFolder(course, section)` delegates its naming half;
- new `Plantoir.Tests/ClassFolderContractTests.cs`, deserialising the same
  naming, membership and `isClassPage` cases the mac suite and
  `scripts/test_class_folder.py` run — 10, 7 and 12 of them as this is written,
  counted rather than fixed, since each suite guards only a `>=` floor so a
  case added from either platform cannot break the others by arriving.

**Rejected:** unifying on "contains class" everywhere. It reads well and it
reclassifies real shipped pages — see the payload examples above. Segment
EQUALITY for pages, substring only for the configured list, is the distinction
that makes the rule safe.

### Two things ABOVE or BESIDE the class folder were still deciding class-ness

The C# above was written on the mac and had compiled nowhere, which is what
[issue #115](https://github.com/russellgordon/plantoir/issues/115) was for. It
was built and run on Windows on 2026-09-19, and the headline defect — a working
folder called `C:\Users\x\Classroom` making every page in every course a class
page — was already closed by `Plan()` passing `Relative(pagePath)`. Two members
of the same family were not, and both were Windows-only divergences from the
rule the mac and `build_site.py` apply:

**Membership was the whole folder LIST, in two places.**
`AssistWorkspace.ClassPages` and `ScheduledDeploy.UnpublishedClassesIn` walked
every `per_section_folder`, where the membership rule counts the folders that
mention classes. A course configured `["All Classes","Handouts"]` counted its
handouts as days of teaching here and nowhere else — in the dated class lists,
in "publish every class from the 15th", in the next-class numbering, in the
list of classes a scheduled deploy says students cannot see yet.
`UnpublishedClassesIn`'s comment claimed it "walks the same folders
`AssistWorkspace.ClassPages` walks", which was false between the two of them;
a test now pins them together on one fixture, because a comment claiming
agreement is exactly what stops anybody checking.

**The path reached above the section.** `Relative()` is relative to the WORKING
folder, so the segments handed to the rule still included `courses`, the course
code and `sectionN`. That was enough for the `Classroom` bug and not enough for
the rest: a course-level SHARED folder a teacher called "All Classes" made every
page under it a lesson — of every section at once, since shared pages belong to
all of them. `AssistWorkspace.PathWithinSection` now narrows the path to the
section folder, mirroring the mac's `AssistSectionGraph.pathWithinSection`.
Mirror its CODE, not its comment: it returns `url.lastPathComponent` for a page
outside the section, while its own header comment still says "last two
components" and is stale — the mac changed the code after review, precisely
because the last two components put the immediate parent's name back in front
of the rule, which is the discredited "does the parent mention classes" sniff.

**Three changes a teacher can see**, none of them a new invention — each is
the shared class-folder rule arriving on a platform that had its own — and
each pinned by tests in `Plantoir.Tests/ClassFolderMembershipTests.cs`:

- **Membership can SHRINK.** The rule falls back to ONE folder when no folder
  name mentions classes, so a course whose folders are `["Lessons","Labs"]` had
  both walked before and has only "Lessons" after: the Labs pages leave the
  dated class lists, date-range publishing, the scheduled-deploy list and the
  class numbering. The mirror of it WIDENS: a course with no per-section
  folders at all had no class pages here, because there was no folder to walk,
  and now falls back to "All Classes". Exposure is narrow and was counted
  rather than guessed — all 38 example payloads and all 50 skeleton manifests
  configure exactly `["All Classes"]`, so only a teacher who both renamed the
  class folder away from anything containing "class" AND added a second
  per-section folder is affected.
- **Publish plans GROW.** Link-following on Windows stops at class pages
  (`AssistWorkspace.cs:724`) — a class is published because the teacher asked
  for it, not because another class linked to it — so a shared page the old
  wide path called a class was silently skipped. Demoted to what it is, it is
  followed, and "publish Day 1 and everything it links to" now reaches it.
  **That guard was WINDOWS-ONLY when this was written, and this is where it was
  found — it is now SHARED.** The mac's `AssistSectionGraph.linkedPages(from:)`
  had no class-page test at all, so a publish there followed links INTO class
  pages too. The outcome of this particular change converged either way — the
  demoted shared page was already non-class on the mac, so its links were
  already followed — but the rule underneath did not, and the difference was
  nobody's decision until
  [issue #173](https://github.com/russellgordon/plantoir/issues/173) settled it
  on 2026-09-19: **Windows' answer, for both rules.** The mac now stops there
  too, in `reachFollowingLinks(from:)`; the rule, what was rejected and what a
  teacher is told are in `documentation/10-local-ai-assistant.md` → "The walk
  stops at a class page", and it is pinned by `contracts/shared-rules.json` →
  `followingLinks.stopsAtAClassPage`. Deliberately NOT changed here: how far a
  publish reaches is a different question from which folders hold classes, and
  it was answered separately.
- **The "introducing class" credit changes hands.** An undated page inherits
  the date of the earliest class linking to it and the teacher is told which
  class brought it in (`AssistWorkspace.cs:777` finds that class here). A
  shared page in a folder named like the class folder used to win the credit
  (a course-level folder sorts before `section1`), so the teacher was told a
  page they never taught from was what introduced it.

  **The EXCLUSION was shared and the REACH was not** — and this needs saying
  carefully, because an earlier draft of this page called the whole thing
  parity. A class page never inherits a date on either platform
  (`AssistWorkspace.cs:916`, `AssistPublishPlanner.dateMovesFollowingClasses`
  in `AssistPublishPlan.swift`, and `contracts/class-planning.json` →
  `datingPagesAClassBrings`: "a class's date is its place in the schedule").
  But Windows' `continue` sits in front of its `queue.Enqueue(target)`, so it
  stopped the walk THERE, while the mac's date code reached its pages through
  `graph.linkedPages(from:)`, which traversed straight through class pages and
  only filtered them out of the move list afterwards. So a page reachable ONLY
  by way of another class page — Day 3 links to Day 4, Day 4 links to a new
  worksheet nothing else points at — was re-dated on the mac and was not on
  Windows. That was the same divergence as the publish-following one above,
  inside the very rule that looked like the settled ground, and
  [#173](https://github.com/russellgordon/plantoir/issues/173) covered both
  reaches rather than only the publish one. **Both are closed as of
  2026-09-19**: the mac's date walk goes through `reachFollowingLinks(from:)`
  now and stops where Windows stops, pinned by `class-planning.json` →
  `datingPagesAClassBrings.reachStopsAtAClassPage`. Unpublish reach, the one
  half left open then, closed on the mac on 2026-09-26
  ([#201](https://github.com/russellgordon/plantoir/issues/201)): an unpublish
  stops at a class page too (`followingLinks.stopsAtAClassPage.appliesTo`,
  `followingLinks.unpublishing.cases`). Windows' unpublish sweep did not stop
  either, and owes the same clause; see
  [the assistant's page](10-local-ai-assistant.md#unpublishing-stops-there-too-201).

**Rejected: keeping Windows' wider membership.** It is the more generous
reading — everything the teacher put in a per-section folder is a class — and
it would have avoided both behaviour changes above. It was rejected because a
Windows-only answer to a shared question is a difference nobody chose, and
because the wider reading is the one that produces a wrong map that reports
success: the coverage map, the dated lists and the numbering would count
handouts as teaching while the BUILD that renders the site would not. Matching
the shared rule is the point of having one.

**Also rejected: narrowing `Plan()` by resolving a shared page's own folder.**
Returning the last two path components for a page outside the section keeps the
immediate parent's name, which is enough for a course-level "All Classes"
folder to go on making lessons — the very bug being closed, wearing a shorter
path. A shared page is not a class page; say so plainly rather than guess from
a fragment of path.

Nothing is written to the activity trail for any of this. All the events in
`shared-rules.json` → `activityTrail.mustRecord` were checked: none records
what counts as a class page, and no existing line becomes untrue — the lines
name what a teacher DID, and this changes which pages a request resolves to,
not what the request was.

Measured by mutation on 2026-09-19, each revert run against the whole suite:
`ClassPages` back to `PerSectionFolders` turns 4 tests red;
`UnpublishedClassesIn` back to it turns 1; `Plan()` back to
`Relative(pagePath)` turns exactly the 3 narrowing tests red. The
`Classroom`-working-folder test stays green under all three, which is why it is
labelled a GUARD in the file rather than evidence of a fix.

## A cloud-synced working folder: explain it, never refuse it

**The decision, and who made it.** Russell, 2026-09-05, on the question
`TODO.md` had carried since a reliability review found that renaming a
folder reads every page in the course — which on an iCloud-backed vault means
downloading every offloaded page, one blocking read at a time. The question
was whether Plantoir should refuse a working folder that a cloud service
keeps in sync. The answer is **no**: recognise it, say once and in plain
words what it costs, give the teacher the choice, and leave their notes
exactly where they put them. `GUI-IMPROVEMENTS.md` row 399 is the log entry;
`shared-rules.json` → `cloudSyncedFolders` is the specification; this
section is the reasoning.

**Why not refuse.** Three reasons, and each alone would have been enough:

- Teachers keep their vaults in iCloud or OneDrive *on purpose* — it is how
  the notes reach an iPad and a second machine. A refusal tells them to give
  up cross-device access to their own teaching material, and a hard block is
  the one answer they cannot opt out of.
- Detection is unreliable in both directions. A teacher can have a folder
  literally called "Dropbox" that is not one; a folder can be synced by a
  service neither app knows. A false refusal on a hard block is
  unrecoverable for them, whereas a synced folder Plantoir fails to notice
  still works — more slowly.
- **You already rejected refusal, by building something better.** When
  OneDrive locked build output mid-build, the Windows answer was
  `PLANTOIR_BUILD_ROOT` — move the churn out, leave the content in. That
  precedent settled the argument here: the same problem, met once, answered
  by relocating rather than refusing.

**The two moments, and why they are different things.** This was Russell's
own question — shown when a synced folder is suspected, when the working
folder is created, or both? — and the answer is both, as two forms:

- **A folder the teacher just CHOSE, or an empty one about to be set up,
  stops at the folder picker.** This is the one moment the choice is free:
  nothing has been written into the folder yet. The picker shows the
  headline, the five-sentence explanation, and two buttons — "Use This
  Folder Anyway" and "Choose a Different Folder…". Setting up the empty
  folder IS going ahead (the note was beside the button; pressing it is the
  answer). **Neither button is the Return-key default**: a Return pressed
  out of habit must not decide this.
- **A folder the window RESTORED gets a quiet notice inside the window**,
  above the working-folder bar: headline, one-line summary, a way to open
  the full explanation in place, and "Got It". Never a dialog and never a
  sheet, because a folder can become synced *after* it was set up (moved
  into iCloud; Desktop & Documents turned on) and a folder that opens on
  every launch must not interrupt every launch. On the mac this is a strip
  above the path bar with a `.quaternary` background; a port builds its own as an
  InfoBar or the nearest WinUI equivalent — the placement and the
  dismissability are the contract; the control itself is each app's own.
- **Going ahead is remembered PER FOLDER**, and neither form is shown for
  that folder again. A second synced folder gets its own note. The mac
  keeps the list in preferences under `acknowledgedSyncedFolders`; keep
  Windows stores its own wherever it keeps per-app preferences, keyed by the folder's path.
- **The check runs on EVERY adoption of a folder**, not only the first —
  folders move into cloud services after they are made, and the check costs
  nothing.

**Detection: markers, never names.** The mac reads three things, and all
three are in `detection.macMarkers`: `~/Library/Mobile Documents` (iCloud
Drive's real location), `~/Library/CloudStorage/<Service>-<Account>/` (where
macOS 12.3+ keeps every File Provider service — OneDrive, Google Drive,
Dropbox, Box — with the service named by the part of the folder name before
the first hyphen), and the item's own `isUbiquitousItem` flag, trusted ONLY
under `~/Desktop` and `~/Documents` — the two folders iCloud syncs in place.
**That flag is not iCloud-specific**: the adversarial review (row 401)
probed a real `~/Library/CloudStorage/Dropbox` and found it set there too,
so trusted anywhere else it would call a Dropbox folder "iCloud Drive".
Whatever Windows exposes for "this item is cloud-managed", assume the same
until proven otherwise. **Symlinks are resolved before any rule runs** —
Dropbox and OneDrive both leave a link at the old place (`~/Dropbox` →
`~/Library/CloudStorage/Dropbox`), and a path arriving through it matched
nothing while the folder behind it matched Dropbox; on Windows, resolve
junctions and reparse points the same way, since Known Folder Move leaves
exactly that indirection. The resolved path is also the acknowledgement's
key, so one folder is one key whichever spelling it arrives by. Your
markers are listed in `detection.windowsMarkers`: the OneDrive roots the
client publishes as `%OneDrive%`, `%OneDriveConsumer%` and
`%OneDriveCommercial%` (a Desktop moved by Known Folder Move physically lives
under one of them, so a prefix rule catches it), Dropbox's `info.json`
(`%APPDATA%\Dropbox\info.json`, `path` entries), and iCloud for Windows
(`%USERPROFILE%\iCloudDrive` by default). A service you cannot see is
allowed — see "why not refuse". **Run the eleven `detection.cases` against
your path function** with `{home}` as `%USERPROFILE%` and the mac's reserved
paths translated per platform; the cases that matter most are the negative ones:
a folder CALLED Dropbox on the Desktop, and the reserved root itself. When
the service is recognisably syncing but not one you name, the contract's
`unknownServiceName` ("your cloud service") is the honest word.

**The sentences, and the one that is platform-specific.** All in `wording`, word for
word, `{service}` filled in. They name EFFECTS a teacher can recognise —
"building can be slower", "renaming a folder can take a while" — and never
machinery: no "sync client", no "file provider", no "dataless", no "build
root". A mac test forbids those words; write the same test. The ORDER is
part of it (`explanationOrder`): reassurance first, because "kept in sync"
beside a warning reads as "your notes are at risk" and they are not; the
choice last, after the reasons. **`buildFilesAreCopied` applies on the mac
only** (`buildFilesAreCopiedAppliesOn`): it says the built site's thousands
of files are written inside the folder and copied to the cloud, which is
true on the mac today — `.merged_output` still lands in the working folder —
and false on Windows, where row 290 already builds into
`%LOCALAPPDATA%\Plantoir\builds\<id>`. Show the other four. When the mac
moves its output out too (a separate piece; the research is in `TODO.md`
under "Move the mac's build output OUT of a synced working folder", and it
is bigger on the mac because the build runs in a container that mounts only
`courses/`), that field will change and the contract diff is how you will
hear.

**The trail.** Two events, both in `activityTrail.mustRecord` and so already
failing your `ContractTests` until you add them: `synced folder noticed`
(the service and the redacted path — recorded because the effects of a
synced folder arrive weeks later as unrelated reports, and this line is what
connects them) and `synced folder accepted` (which of the two forms, and the
service — because "nobody warned me" is answered by this one, not the
first). The mac's lines read "noticed the working folder is kept in sync
with iCloud Drive — ~/…" and "chose to use the working folder anyway, kept
in sync with iCloud Drive"; say the same things in the same words.

**Rejected, so it is not proposed again:** refusing (above); detecting by
folder name (the case that would catch a real Dropbox folder is the case
that mislabels a teacher's folder called Dropbox); a dialog or sheet on
launch (interrupts every launch of a folder that cannot be un-synced from
inside the app); a single app-wide "don't show again" (a teacher with two
synced folders was told about one). Not measured: nothing here was timed.
The iCloud read-on-download slowness that started the question is real but
was observed, not clocked; if you time a rename on an offloaded OneDrive
folder, write the number here with the hardware.

**What driving it against a real iCloud Drive folder found** (row 400), in
the order you are likely to meet the same things:

- **The notice pushed the whole bottom band of the window off screen**, at
  every window height. The mechanism is SwiftUI's (a text pinned to its
  vertical size answers a minimum-size probe with a word per line — 1,548
  points, measured, whether 700 points or no height at all is proposed;
  the modifier ignores the height either way), but the SHAPE is WinUI's too: a
  wrapping `TextBlock` in a horizontal `StackPanel` gets unbounded width and
  never wraps, or bounded width and grows tall. Measure your InfoBar's
  height with the real sentences at a narrow width before shipping it, and
  measure with a width PROPOSED — the mac's first test asked for the ideal
  size with no width and passed the faulty layout.
- **The path bar cut off the folder's own name.** An iCloud path always runs
  through `~/Library/Mobile Documents/com~apple~CloudDocs/…`, so the last
  crumb — the only one that differs between a teacher's folders — was the
  one lost. Now a contract rule, `workingFolderPathBar.tooLongForTheSpace`:
  a path too long for the space shows its END. Your bar needs the same. (That
  fix then broke the opposite case — a path SHORT enough to fit ended up at the
  far end of the bar, away from its label — which is the sibling rule
  `fitsInTheSpace`, added 2026-09-09. Both, or neither: see
  [`10-local-ai-assistant.md`](10-local-ai-assistant.md#the-working-folder-path-bar--reported-missing-in-use-2026-08-16).)
- **The folder must be NAMED before it is explained.** The picker showed the
  five sentences and then the path bar; a teacher reads "this folder" and
  looks for which folder. Path bar first, in both the empty-folder and the
  existing-folder states.
- **Enter still set up the empty folder while the note was showing**, which
  the contract's own `whenShown.chosen` forbids. The set-up button loses its
  default-action status while a decision is pending; check that a port's does too.
- **A folder the picker will not take anyway** — neither a working folder
  nor empty — is not asked about. The rule is in the contract's `whenShown`;
  the teacher is about to choose again, and the guidance saying what to
  choose is the message.

**What the adversarial review then found** (row 401), beyond the detection
points folded in above:

- **Finishing a set-up must acknowledge the folder that was SET UP**, not
  whichever folder is current when the copy ends. The copy runs off the
  main thread and the Open Working Folder command stays enabled meanwhile;
  a second synced folder chosen during it has its own decision pending, and
  the first folder's completion must not answer it. Guard on the path.
- **"Synced folder noticed" is recorded by a window only.** The assistant
  and the MCP server adopt folders on models nothing shows; a "noticed" from
  those says the teacher was told something they were not, and on the mac it
  produced six lines for one folder in ten minutes. Your `plantoir-mcp.exe`
  adopts folders too — same rule.
- **One folder, every window.** Got It in one window clears the same
  folder's notice in any other window showing it. Rarer on Windows, where
  one `MainWindow` shows one folder; verify and say so if it cannot happen.
- **Re-choosing the open folder is a restore**, not a new choice
  (`whenShown.reChoosingTheOpenFolder`), or the courses vanish behind the
  picker for a folder the teacher did not change.
- **The acknowledgement list is keyed by resolved path and never pruned.** A
  renamed or moved folder is a new key and is asked again — on purpose,
  since it may have moved INTO a synced location. A deleted folder's key
  stays, harmlessly.
- **Three labels are now in the contract** — `chooseDifferentFolderButton`,
  `showDetailsButton`, `hideDetailsButton` — so nothing on the picker or the
  notice is left for you to word.

## A folder named `index.md`, and why both apps refuse rather than clear the way

Windows found this bug, porting `SiteHealthRepair` line by line, and reported
it on 2026-09-06; this is what the mac did about it. What follows is the part
that does not travel in a diff: what the mac chose, what it rejected, and why
the two are not interchangeable.

### The bug, stated once

`FileManager.fileExists(atPath:)` — and `File.Exists`, and every other bare
existence test — is answering a question about a NAME, not about a file. On the
mac it returns `true` for a directory. So this:

```swift
if FileManager.default.fileExists(atPath: index.path) { return .alreadyFine }
```

reported `.alreadyFine` for a section whose `index.md` was a FOLDER, and
`outcome(ofRepairing:)` sorts `.alreadyFine` into neither "restored" nor
"failed", so the dialog said **"That is already put right. Nothing needed
changing."** The section still had no front page: `build_site.py` produces no
root `index.html`, so there is no site to publish and the deploy refuses. The
one dialog written to end silence was the thing telling them it was dealt with.

`restoreMedia`, the function DIRECTLY above it, has used the `isDirectory:`
form since it was written, with a comment saying why. And the two were written
in the same sitting — `git log -S` puts both in commit `04dfd0cd`, 2026-08-23 —
so this is not a case of an old habit and a new one. The careful form and the
bare one were typed one function apart, on the same afternoon, by somebody who
had just explained in a comment why the careful one was needed. That is the
useful lesson in it: knowing the rule does not make the next call site obey it,
and a grep for `fileExists` / `File.Exists` with no `isDirectory:` is worth more
than remembering.

### What it does now, and the decision behind it

**Refuse, explain, and touch nothing.** Russell decided this before the work
started, and the alternative was live: move the folder aside and write a proper
front page in its place, so the teacher's next publish just works.

**That was rejected because the folder may hold their pages.** Neither app can
see inside it — this is a teacher's Obsidian vault, and a folder called
`index.md` is most often a sync conflict or a mis-drag, but it can perfectly
well be a folder somebody made on purpose with a term's work in it. A repair
that relocates a teacher's writing to make a warning go away is a worse outcome
than the warning, and it is the kind of thing that gets discovered in May.
Refusing costs one step by hand, in Finder or Explorer, and nothing else.

It also fits the rule the whole health feature is built on
(`siteHealth.checksTheFeatureNotTheFolder`): a fix must restore the FEATURE.
Moving a folder out of the way and writing an empty page satisfies the check
while possibly hiding the teacher's own pages, which is the same failure mode
as recreating an empty curriculum folder, one step further along.

### The sentence, and why it names the course

`contracts/shared-rules.json` → `siteHealth.repair.refusedWhenSomethingIsInTheWay`
carries it. On the mac it is `SiteHealthRepair.folderWhereTheFrontPageBelongs(course:section:)`.

It names the course as well as the section folder, and that was a review
finding rather than a first draft: the outcome dialog shows a headline and one
sentence and NOTHING else — not the course, not the section — so "in your
section1 folder" sends a teacher with two courses to a folder that exists twice.
This is the first teacher-facing sentence on either platform to name a
`section<N>` folder. It is safe to do: that is the on-disk name, it is what
Obsidian's file tree shows, and both apps already offer "Reveal in Finder" on
exactly that folder.

**And the generic explanation is REPLACED, not appended to.** That is
`SiteHealthRepair.couldNotExplanation` on the mac — the one that sends a teacher
to check whether a folder is locked or read-only. It is the right thing to say
about a read-only volume and the wrong thing to say here: permissions are not
what is wrong, and a teacher gets one prompt to act on. When BOTH kinds of failure happen at once — a file where
`Media` belongs and a folder where the front page belongs — both sentences are
said, generic first and specific last. Both orders were read aloud. The other
way round ends the paragraph on the generic explanation's opening clause —
"You can make it yourself in Obsidian" —
immediately after "…and Plantoir can put the front page back", so "it" lands on
the front page — the one thing that cannot be made until the folder in the way
has moved. There is a test on the order
(`testWhenBothKindsOfFailureHappenTheGenericExplanationComesFirst`), because a
comment claiming a paragraph reads well is worth nothing.

### The shape of the answer, which is what you have to copy

> **Windows adopted this on 2026-09-07** (branch `issue/33-repair-refused-folder-in-the-way`,
> `GUI-IMPROVEMENTS.md` row 428). What follows is the REASONING behind the shape,
> kept because it is worth understanding — not an outstanding port. A Windows
> session reading this section does not owe it.

`Result` gained a fourth case:

```swift
case blockedByAFolderWhereTheFrontPageBelongs(section: Int)
```

Two things about it are deliberate.

It carries the **section number, not the sentence**. `Result` says how a repair
went — a fact — and `outcome(ofRepairing:in:occasion:)` chooses every word in
that file. Putting the prose in the Result would have split the wording across
two places, and the first adversarial review of the plan caught exactly that.

It is counted as a **failure**: the check's name goes into the failed list, so
"Could not put the front page back." still appears beside anything that did
come back, and `canRebuild` stays false, so the "Preview Again" button is not
offered. There is nothing to look at.

### The trail line

`ActivityTrail.Event.folderProblemNotRepaired` = `"folder problem not
repaired"`, written from the refusal branch with the course and section:

```
ICS3U/1 · found a folder called index.md where the front page belongs, and left it alone
```

Without it the trail shows the problem being FOUND and then nothing at all,
which reads exactly like a teacher who never pressed the button — and the
folder in the way is something they will very likely have moved or deleted by
the time they report anything, so it cannot be looked for afterwards.

**Named for the OUTCOME, not for its one cause, and this is the part worth
copying rather than re-deciding.** Only the directory refusal writes it today.
A repair that simply FAILED — a read-only volume, a permissions problem — still
records nothing, which is a real gap and is left open on purpose: closing it is
a different piece of work, and it belongs to whoever also decides what
`restoreMedia` should say when a FILE is sitting where the `Media` folder
belongs (the same class of problem, still answering `.failed` with the generic
sentence). Naming the event `folder problem repair blocked` would have forced a
rename on both platforms and in the contract the day that gap closes. So: wire
it to the directory branch, not to every failure, and leave the name alone.

### What is still not right in the repair code, on both platforms

Named here so it is not rediscovered as a puzzle, and NOT fixed by this piece:

- `restoreMedia` answers plain `.failed` when a FILE sits where the `Media`
  folder belongs. Same class of problem, same wrong explanation, no sentence of
  its own. The machinery to give it one is now in place — a second `Result`
  case and a second contract sentence — and nobody has decided the wording.
- `SectionAdder` has the identical bare `fileExists` guard on `index.md` when a
  section is added, so a folder by that name is skipped silently there too.
- ~~`repair(_:in:)` returns `[String: Result]` keyed by check NAME, so two
  findings with the same name collapse — your second finding of 2026-09-06,
  owned by its own piece of work.~~ — ✅ Done 2026-09-07, branch
  `issue/repair-results-keyed-by-name`. It returns `[Attempt]` now, one entry
  per finding, and the rule is contract data both suites can run
  (`siteHealth.repair.reportedOncePerFinding`).

---

[◀ Previous: Launcher Scripts](03-launcher-scripts.md) · [Back to index](README.md) · [Next: The Build Pipeline ▶](05-build-pipeline.md)

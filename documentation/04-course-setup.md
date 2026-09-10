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

Once a code has been entered (step 1), the wizard offers ONE of two kinds
of starting content, and never both:

- **Example content**, when `support/example_content/<CODE>/` exists —
  thirty-seven course codes as of August 2026, and growing; the code counts
  the folders rather than trusting a number, and so should you. A payload is a complete working
  course written for that code: a semester of class pages, concept and task
  pages, and (optionally) every Ministry expectation as its own page. The
  payload's `manifest.json` is the course's ENTIRE structure, so step 5's
  questions are skipped: the pages were written for exactly those folders.
- **A skeleton**, for every other Ontario code — around 1,900 of them.
  `support/skeletons/families.json` maps the code's three-letter prefix to
  one of fifty subject families (ADA drama, AMU music, SCH chemistry, MCV
  calculus, TXJ hairstyling…), falling back to a generic skeleton for club
  and custom codes. The skeleton fills the course with the SHAPE of a
  course — folders that suit the subject, four units of three class pages
  to rename, a landing page with Most Recent Class, `Key Links`, a site
  tour, and placeholder pages saying what belongs where — and its folders
  become the DEFAULT answers to step 5's questions rather than replacing
  them.

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
> runnable list both suites now check themselves against.) Two things are
> deliberately NOT migrations: restoring a backup puts back the spelling the
> backup held, because a restore is not an edit; and adding a section writes
> the new section's `publishForSection<N>` while leaving the other sections'
> keys exactly as they were, because adding a section changes nothing about
> what any existing section publishes. A page with
> **no** publication key at all is visible, so forgetting the key leaves work
> showing rather than making it disappear unnoticed.

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
   items. The anchor comment makes the rewrite target unambiguous.
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
An absent key means "Unit", so every course made before this existed is
untouched. "Day" is deliberately fixed.

**`class_folder`** — which per-section folder holds the class pages. Recorded
rather than guessed from the word "class", because the guess quietly decided
what a teacher was allowed to call the folder: somebody whose vocabulary is
"Thread 2, Day 3" calls it "All Days", and the guess would then point the
next-class button and the curriculum map at whatever folder happened to be
first. Both wizards write it at creation, and a rename in Course Settings
writes it even on a course that never had one. The old guess is kept as the
fallback, never replaced.

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
  off). When no content exists for the code, this is where the SKELETON
  toggle goes instead (entry 123) — "Start from a <subject> skeleton" —
  and the quiet "empty folders" caption is now the last resort, for a code
  with neither.
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
Settings and the New Course wizard, on both platforms. They were six different
strings pinned by nothing until 2026-09-08, when Windows proposed the case; the
mac adopted it on 2026-09-09 ([#71](https://github.com/russellgordon/plantoir/issues/71)),
where they live in `GradedFolderWording` and the two views draw from it.

Three things in that caption are worth knowing before editing it, because each
was argued the other way first and the contract's `why` carries the full
argument:

- **It says "tick", never "add" or "remove"** — a correction rather than a
  preference. The control is a tick list with no Add button, so the mac's
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
folders-help row has since that sheet was written, so changing it is a separate
piece on both platforms.

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
`gradedFolders.removingAFolder`, six cases. Removing a folder takes its name out
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
removal is recorded, and drop the name only if it is no longer among them AND
the course had already been asked.

Two edges of that, recorded rather than left to be met. The second exception
says "still OFFERED", not "still counts": the checklist sees four levels and the
build counts at any depth, so a `Tasks` five levels down is dropped from the
pool and goes on counting. And the "at least one folder must count for marks"
floor — the one that refuses to unpick the last pooled folder while the coverage
map is on — asks whether this is the last NAME in the pool, not whether the pool
would survive the removal. So it still blocks removing a top-level `Tasks` on a
course where `Portfolios/Tasks` would have kept the name. Conservative, rare,
and the same on both platforms; sharpening it would be a shared change. **Order is the whole subject.** Ask before
the exclusion is written and the removed folder is still on the list, so the
pool freezes — which is what the mac did until 2026-09-09 and what Windows still
does, from a walk cached one `BuildForm` pass earlier ([issue
#142](https://github.com/russellgordon/plantoir/issues/142)).

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

### Content declares its own pool

All 38 payload manifests and all 50 skeleton families now carry
`graded_folders`, and both linters refuse a manifest without one or one naming a
folder the course does not have. `setup_course.py` writes it at creation from
the manifest — shared Python, so both platforms get that unchanged.

Declared rather than inferred deliberately: inference is a substring while the
build matches exactly, and those two agree for 88 of the 89 courses here and
disagree for the one that would have been broken by it.

### Where the rules live

`contracts/shared-rules.json` → `gradedFolders` (10 cases for which folders
COUNT, run by `scripts/test_graded_folders.py` in the image — neither app
implements that rule, so neither suite runs them) and `gradedFolders.choices`
(14 cases for what the checklist OFFERS, run by both apps). The key itself is in
`contracts/file-formats.json`.

## “Where do the class pages live?” had four answers

*(The Windows half of this is [issue
#115](https://github.com/russellgordon/plantoir/issues/115): the C# below was
written on the mac, which has no `dotnet`, so it has compiled nowhere.)*

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
  `ClassFolderRule.IsClassPage(Relative(pagePath), ClassFolderRule.Names(...))`
  — note `Relative(...)`, which is the fix for the `Classroom` bug. **The rule
  is a pure segment matcher and cannot tell an absolute path from a relative
  one**, so `Relative(...)` is the whole protection: if you ever call
  `IsClassPage` from somewhere else, pass a relative path or you reintroduce
  the bug. The mac learned this the same way — its own `AssistSectionPage` had
  to gain a `pathWithinSection` because `relativePath` is the FULL ABSOLUTE
  PATH whenever `workspaceURL` is nil;
- `ClassFolderRule.Name`/`Names` skip null and empty entries: these lists come
  from JSON, including the contract's own case data, and unguarded LINQ threw
  where Swift and Python coerce;
- `AssistWorkspace.ClassFolder(course, section)` delegates its naming half;
- new `Plantoir.Tests/ClassFolderContractTests.cs`, deserialising the same 5 + 9
  cases the mac suite and `scripts/test_class_folder.py` run.

**Rejected:** unifying on "contains class" everywhere. It reads well and it
reclassifies real shipped pages — see the payload examples above. Segment
EQUALITY for pages, substring only for the configured list, is the distinction
that makes the rule safe.

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
  a path too long for the space shows its END. Your bar needs the same.
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

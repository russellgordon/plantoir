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
> reads them, inverted, and Plantoir rewrites a page's key only when something
> edits that page. You never have to convert a course by hand. A page with
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
| The lessons folder | Every per-section folder the build counts as a class folder — the recorded `class_folder`, plus any whose name mentions classes. New class pages are written to one; the coverage map counts all of them. |
| The curriculum folder | `curriculum_folder` if it names a folder the course has, otherwise the alphabetically first shared folder whose name mentions the curriculum. |
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
- **The names come from the RESOLVED rules, not the raw configuration keys.**
  A course whose `curriculum_folder` was never written still has a curriculum
  folder as far as the build is concerned, and telling that teacher to create
  one they already have is the one failure a sheet about folder names cannot
  afford.

The rows, the sentences and the cases are
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`specialFoldersHelp`, so both apps say the same thing about the same course.

---

[◀ Previous: Launcher Scripts](03-launcher-scripts.md) · [Back to index](README.md) · [Next: The Build Pipeline ▶](05-build-pipeline.md)

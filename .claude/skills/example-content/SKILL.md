---
name: example-content
description: Build or revise a per-course-code example-content payload (support/example_content/<CODE>) — the ready-made course a teacher can pre-populate. Use whenever adding example content for an Ontario course code.
---

# Building example content for a course code

A payload is a complete, working course a teacher keeps: real pages, a real
semester, real curriculum. **ADA1O is the reference implementation** — when
in doubt, open it and copy its shape. `support/example_course/EXC2O` is the
older standalone example course; match its depth and warmth, not its
mechanics.

The payload owns the course's ENTIRE structure (the wizard asks no
structure questions when pre-populating), so nothing may ship empty and no
folder should exist without purpose. Machinery lives in
`scripts/setup_course.py` (`install_example_content` and friends) and needs
NO changes for a new course code — a new payload is pure content.

## Phase 1 — Research the curriculum (verbatim or not at all)

**From the LIVE official government portal, every time.**
- **Ontario courses:** `dcp.edu.gov.on.ca` and `edu.gov.on.ca/eng/curriculum/secondary/`
- **British Columbia courses:** `curriculum.gov.bc.ca` (e.g. `curriculum.gov.bc.ca/curriculum/adst/11/computer-programming` or `curriculum.gov.bc.ca/curriculum/mathematics/`)
Do not work from a saved copy, and do not add one to this repository. A copy held here
does not preserve the curriculum, it manufactures a stale second version of it —
the ministry updates these documents whenever it likes.

Launch a research agent (WebSearch/WebFetch) to capture, from the
Ministry's own published document, for the exact course code:
strand/domain titles; every OVERALL expectation / Big Idea / Curricular Competency / Content standard (code + verbatim text); every
SPECIFIC expectation (code + verbatim text, including the italic
parenthetical examples); teacher prompts verbatim; the official stems; and the citation (document title, year,
copyright holder, official course URL, and source PDF URL
with page range). Anything
unverifiable gets flagged and is NOT published as Ministry wording.

Save the result as a structured markdown file (see the format the ADA1O
generator parses) — it is both the generator's input and the audit trail.

## Phase 2 — Design the course

Choose folders that fit the SUBJECT, not the template. ADA1O's line-up for
drama: Concepts, Conventions, Warm-Ups, Discussions, Portfolios, Tutorials,
Setup, Style, Tasks, Curriculum; shared files Learning Goals.md and Help
Sessions.md; per-section All Classes + Key Links.md + Private Notes.md +
Scratch Page.md. A science course would swap Conventions/Warm-Ups for
Investigations/Exercises (see EXC2O). If a folder has no reason to exist in
this subject, it does not exist.

Plan a **semestered arc, September to at latest January**: four units,
each building to a performance or summative task, the last unit
culminating. Name class pages `Unit N, Day M.md`. Write the arc down
before authoring — it is the skeleton everything hangs from, and
class-page links are the schedule.

**A standard secondary credit requires 110–120 hours of scheduled time (1.0 credit in Ontario, 4.0 credits in British Columbia), and the arc must
account for all of it.** One class page is one period. At the 75-minute
period a semestered day school runs, that is **about 86 class pages plus a
three-hour final evaluation** — roughly 18/22/22/24 across four units,
dated on consecutive school days from September 8 to about January 19. Set
`"class_weekday_step": 1` in the manifest so the installer dates them
daily; it skips the winter break and Thanksgiving Monday on the way. The
last **three or four classes are review**, tagged `review` in their
frontmatter, and the final evaluation is a page in `Tasks` tagged
`final-evaluation`. The linter checks the arithmetic and both tags.

A 26-class arc is not a course — it is a sampler, and a teacher who
adopts it inherits a timetable that runs out in November. Padding is not
the answer either: real courses spend periods on work time, revision,
conferencing, and catching up, and those days are worth writing down.
A work period's class page is honestly short — an agenda of two lines and
a checklist — and that is what makes the arc believable.

Three rules govern the SHAPE of the arc, and lengthening a short one
without them produces a course that is longer and worse:

- **The culminating task ends the course.** Whatever the whole term was
  building towards — the performance, the client hand-over, the launch —
  is the last substantial class. After it come only reflection, review,
  and the final evaluation. Never extend an arc by adding days AFTER the
  culminating: a course cannot teach new material past the point where
  it has already asked students to show everything they can do. If a
  lengthened arc leaves the culminating in the middle, the arc is wrong,
  not the culminating.
- **A task occupies many days, and every one of them is named.** Real
  tasks are launched, planned, built to a walking skeleton, tested,
  documented, and handed in — each a period, each marked on the class
  page as what it is ("day 3 of 8: the walking skeleton"). A task that
  appears on the schedule twice, at launch and at due date, tells a
  teacher nothing about the fortnight in between, which is the part they
  actually have to run. Milestones inside the task are what make the
  build days different from each other.
  - **Give a significant task several WORKING PERIODS**, and say so on
    the class page. Students need time in the room, with the teacher
    present, to build the thing — that is when conferencing happens,
    when the stuck get unstuck, and when a teacher sees the process
    rather than only the product. How many depends on the task: a small
    individual piece might take two, a rehearsed performance or a
    culminating build takes many. Use judgement, and err towards more —
    a schedule that assumes every task is finished at home is a
    schedule written for the students who already have the most support
    at home.
  - Vary what the working periods are FOR, so they are not
    interchangeable: planning, a first rough version, a checkpoint with
    the teacher, testing or rehearsal, revision after feedback,
    documentation. Name each one on its class page.
- **Ideas come back, in a different form, on a later day.** Nobody
  learns an idea on the day it is named. Each substantial idea should be
  met as a problem, named, practised, and then RETURN — inside a later
  task's requirements, as a warm-up weeks on, in a retrieval clinic
  mixing units, and in review. Spacing and variation are how the
  learning survives; three consecutive days on one topic and never again
  is how it does not. This is also what turns thin coverage into real
  coverage: an expectation genuinely addressed three times in three
  different contexts is worth more than the same lesson written out
  three ways.

**Lean constructivist in the lesson plans.** Students meet an idea by
working a problem, exploration, or activity BEFORE the idea gets its
formal name and definition; consolidation compares student methods rather
than presenting one; practice follows sense-making, never replaces it.
Concretely: a class page's agenda should read "exploration → discuss →
name it → practise", not "lesson → examples → worksheet"; tasks are open
enough to have multiple entry points; concept pages can assume the reader
has already met the idea in class and now wants it stated cleanly.

**For mathematics courses in particular, stress active learning as
researched by Jo Boaler, Carmel Schettino, and Peter Liljedahl.** That
means, concretely, woven through the pages rather than name-dropped:
thinking tasks worked in VISIBLY RANDOM GROUPS at VERTICAL WHITEBOARDS
before any formal notes (Liljedahl's Building Thinking Classrooms);
consolidation "from the bottom" comparing student methods, then brief
"notes to my future forgetful self" written by students, and
check-your-understanding questions in place of graded homework; mistakes
framed as growth and no speed worship — depth, visuals, and multiple
methods over memorised procedure (Boaler); discussion-based, relational
problem solving where student conjectures drive the room (Schettino).
Credit the researchers sparingly in teacher-facing footnotes, the way the
payloads cite other sources — the pedagogy should be IN the class pages'
shape, not lectured about.

**For English courses in particular**, when texts come up — novels, short
stories, poetry, essays, anything read or discussed — preference Canadian
writers, and be sure to include Indigenous writers and Indigenous ways of
knowing (as substantive presence in the reading and discussion pages, not
a token mention). Verify any author or title named actually exists and is
correctly attributed before publishing it.

**For Computer Science courses in particular**, use Python for example
code and for teaching programming concepts. (This matches the
mathematics payloads' coding pages, which are also Python.)

## Phase 3 — Manifest

`manifest.json`: `shared_folders`, `shared_files`, `per_section_folders`,
`per_section_files`, `hidden`, `expandable`, `curriculum_folder`. This is
the whole structure — mirror ADA1O's hidden/expandable choices (Curriculum
and the utility files hidden; content folders expandable; All Classes
visible but not expandable). Layout: `shared/` → course root;
`per_section/` → every sectionN/.

## Phase 4 — Generate the Curriculum folder by script

Adapt an existing generator (re-derive from the pages themselves): one
page per overall expectation (`A1. <Title>.md`, `transcludeTitleSize:
h3`) and per specific expectation (`A1.1.md`, `h4`), each with tags
(`A1`, `strand-a`) and the verbatim text ending in a ` ^text` block
anchor — **and NOTHING after the anchor**. No callouts, notes, teacher
prompts, supports pointers, or addendum labels beneath individual
expectations, ever: repeated per-page callouts make the course pages
noisy, and the linter rejects them. Anything contextual — where teacher
supports live, an addendum's provenance, a strand's special status —
belongs ONCE on `About These Expectations.md` (citation, both URLs, ©
line, why codes matter). Plus `index.md` (strand mermaid graph + every
expectation transcluded in document order). Curriculum pages have NO
`created:` line.

**Mathematics on curriculum pages is ALWAYS pretty-printed** — KaTeX
via `$...$` spans, never linearized ASCII (no `x^2` carets, `(a)/(b)`
fractions, `lim[h→0]`, or `→a` vector arrows in the published pages;
those conventions belong only in the research capture file). The
Ministry's own documents typeset their mathematics, so pretty print IS
the verbatim appearance: stacked fractions, radical bars, limits with
the approach beneath, arrows over vectors. Wording stays untouched —
only notation is wrapped, minimally. Currency and markdown-seam rules
from Phase 5 apply here too.

## Phase 5 — Author the content

**The style contract** (gold standard: `ADA1O/shared/Conventions/Tableau.md`):

- Frontmatter: `title:` is what the page is CALLED on the site, and it does
  **not** have to match the filename — neither Obsidian nor Quartz cares,
  which is the whole point of having a `title` field. Match them by default,
  because it keeps a page easy to find on disk. But when they must differ,
  the TITLE is the free half and the FILENAME is the constrained one:
  Windows cannot create `<>:"|?*` in a filename, and Git for Windows refuses
  to check such a path out at all, which stops the entire repository
  fast-forwarding on that machine. So a discussion page is `Who Decides.md`
  titled `Who Decides?`, linked as `[[Who Decides|Who Decides?]]`
  (`[[Who Decides\|Who Decides?]]` inside a table) so the question mark is
  still what a student reads. Both linters reject those characters in a
  filename. Not hypothetical: 57 pages across 13 payloads shipped with `?`
  in the name and the Windows clone sat 258 commits behind, failing every
  pull, before anyone worked out why.
- `publish: true`,
  `created: __CREATED__` (literal), `tags:`, `enableToc: true` only with
  4+ H2s. No H1 in the body. Canadian spelling. Spaced em dashes — like
  this. ~80-column wrap. Direct, warm, concrete, second person to
  students. No filler: every page something a real teacher would keep.
- Each page demonstrates ONE Obsidian feature that genuinely serves it
  (table, callout, folded callout, small mermaid, checklist, footnote);
  vary across pages. Features the subject has no use for (equations in
  drama, code in English) appear ONLY on `Style/What This Site Can Do.md`,
  demonstrated but honestly framed as "not used in this course".
- Exercises folders: answer callouts are titled plainly (`> [!success]-
  Answer 3`) with NO "(click to expand)" hint — repeated per answer it is
  noise. Instead the Exercises `index.md` opens, right after the
  frontmatter, with the standard how-to message (copy it from an existing
  payload's Exercises index): a `[!tip] How to use these pages` callout
  (answer first on paper; reading worked answers only feels like
  learning) followed by a folded `[!success]- Try it: click this line`
  demo. The linter enforces the no-hint rule. One-off folded self-checks
  on concept pages may keep a brief "(click to expand)" affordance hint.
- Curriculum references: end-of-page block
  `%%curriculum-start%%` / `## Curriculum connection` / blank-line-separated
  `![[A2.2]]` transclusions of SPECIFIC expectations / `%%curriculum-end%%`.
  Inline prose links to curriculum pages must be piped
  (`[[C3.1|safe practice]]`) so they degrade to readable words when the
  teacher declines curriculum pages. Never let a curriculum reference sit
  outside these two forms.
- **Curriculum blocks go on DESTINATION pages, never on `Unit N, Day M`
  class pages.** A class page is a schedule — a numbered agenda of links
  to the concept, investigation, exercise set, discussion, and task that
  the period actually consists of. The expectation is met by doing those
  things, so the codes belong on those pages, where a student who follows
  the link finds the expectation attached to the work itself. Repeating
  them on the agenda puts Ministry wording between the agenda and the
  homework list, which is exactly where nobody is looking for it, and it
  makes the same expectation appear in two places with different
  authority. The linter fails any class page containing
  `%%curriculum-start%%`. When a unit's task launches, link the task from
  the class page and let the TASK page carry the codes.
- **Transclusions drive the Curriculum Coverage map.** Every built site
  with curriculum pages gets a generated `Curriculum Coverage` page: a heat
  map of every specific expectation, coloured by how many pages transclude
  it, with a ring on the ones addressed by a page in `Tasks` and a chip per
  overall expectation showing whether assessed work covers it. It is built
  from the site's own links, so a payload's curriculum blocks ARE the map.
  **A page counts only if the course teaches it** — that is, if it is
  linked from a class page, or from a page a class page links to. A page
  written but never put into a class has addressed nothing yet, and the
  map says so.
- **Any task that substantively addresses an expectation must list it in
  its `Curriculum connection`.** This is the rule that keeps the map
  honest at the top end: tasks are where expectations are *evaluated*,
  the ring and the strand chips are drawn from tasks specifically, and an
  unlisted expectation on a task is work a student did that the course
  cannot show it assessed. Read each task's own requirements and list
  what it genuinely demands — not the whole strand, and not a code the
  task merely brushes past. If a task requires it, name it; if naming it
  feels like a stretch, the honest fix is to change the task so it really
  does ask for that, or to leave the code off.
  Two consequences when authoring: spread the transclusions across the
  pages that genuinely address each expectation rather than piling them on
  one page, and make sure each strand's overall expectations are reachable
  through a task — a strand whose chips are all red means nothing marked
  addresses it. **No expectation may sit at zero.** Ontario asks that every
  specific expectation be addressed at least once and ideally several
  times, and that every overall expectation be evaluated for marks at least
  once — so a shipped payload with a red cell teaches a teacher that it is
  acceptable to leave one untaught. Check coverage EXPLICITLY, with the
  linter, before shipping and again after any change to the arc: it reads
  the payload's own transclusions and reports the same numbers the built
  map will show. Treat "addressed exactly once" as thin rather than done —
  the linter lists those too, and a course of 86 periods has room to meet
  most expectations two or three times. **Only PUBLISHED pages count**: a page marked
  `publish: false` is not on the site, so it cannot have addressed anything,
  and the map ignores it until the day it is published. The payload's one
  held-back page — the final class — therefore contributes nothing, which is
  another reason curriculum blocks belong on destination pages rather than
  class pages.
- **Checklists on the site are READ-ONLY.** `- [ ]` renders a box that
  cannot be ticked: nothing is saved, and clicking does nothing. Never
  write "click to check off", "tick these as you go", or any wording that
  implies otherwise — a page that lies about the software is worse than a
  page that omits it. Say what they are for instead: a list to copy into a
  notebook, or to read down before handing something in.
- Piped wikilinks inside table cells escape the pipe: `[[Page\|words]]`.
- **Mathematics that must render** (KaTeX is strict about markdown's
  seams): display math is a SINGLE physical line, or an unindented
  multi-line block OUTSIDE callouts — a 4-space-indented continuation
  line becomes a markdown code block and splits the `$$` pair, and any
  multi-line `$$` inside a `>` callout breaks the same way. Multi-step
  derivations go on one line as
  `$$\begin{aligned} f'(x) &= … \\ &= … \end{aligned}$$`. Currency
  NEVER uses `\$` inside a math span (markdown eats the escape and the
  span shatters): a pure amount is escaped prose (`\$14`), an amount
  inside an expression is `\textdollar 14`. The container render gate
  (Phase 7) catches violations.
- **Mermaid `pie` titles**: mermaid centres a pie title on the PIE, which
  the legend pushes leftward, and never widens the chart to fit — so a
  long title used to be SILENTLY CLIPPED ("Where a working programmer's
  hours actually go" rendered as "vorking programmer's hours actually
  go"). The toolchain now re-fits every pie chart's viewBox to what was
  actually drawn (`patch_mermaid_pie_title_fit` in `build_site.py`), so
  any length renders in full. Still prefer a SHORT title: past about 28
  characters the chart widens and the pie itself shrinks to fit the
  column. "Dry air, by volume" beats "Composition of dry air by volume"
  on its own merits anyway.
- **Mermaid `pie` slices must be big enough to label.** Mermaid prints
  each percentage at its slice's mid-angle with NO collision avoidance,
  and rounds to whole numbers — so two slices under about 3% print their
  labels on top of each other, and anything under 0.5% renders as "0%",
  which says nothing. Combine the tail into one slice ("Argon and
  everything else: 1") and put the detail in a footnote. Sweep every pie
  in a payload for this before shipping: no slice rounding to zero, no two
  slices under 3%.
- **CHEMISTRY: write it with mhchem (`\ce{...}`), never by hand.** The
  build enables the extension (`build_site.py` adds
  `import "katex/contrib/mhchem"` to `latex.ts`), so a whole equation
  fits in one macro, typed roughly as it is said aloud:
  `$\ce{CaCO3(s) <=> CaO(s) + CO2(g)}$`, ions as `$\ce{SO4^2-}$`, bonds
  as `$\ce{C=C}$`. `->` and `<=>` draw the arrows; `(aq)`, `(g)`, `(s)`,
  `(l)` set states. Do NOT build formulae out of `\text{}` and
  `\rightarrow` — the payloads were converted away from that and it must
  not come back, including in prose that names the arrow command.
  Outside `\ce{}`, a bare `H_2O` renders in maths italic, the convention
  for variables, which is wrong for elements.
- **No page stands on its own.** Every page must be reachable from a
  class page (`Unit N, Day M`) either directly, or through ONE page that
  a class page links to — two hops, and no further. Being listed in
  `Key Links` does NOT count: that is the sidebar's index of last resort,
  and a page reachable only through it is an orphan. The linter fails
  any page nothing reaches.
  - The link has to be **honest**. A concept page must be linked from a
    lesson or activity that genuinely uncovers that concept — never
    stapled to an arbitrary day to satisfy the check. If a page has no
    honest home in the arc, the arc is wrong, not the page: either the
    semester is missing a class the course actually needs, or the page
    should not exist.
  - Curriculum pages are the ONE exemption: they are reference, reached
    through the Curriculum index and Key Links by design, and a lesson
    transcludes them rather than linking to them. The linter exempts the
    curriculum folder for exactly this reason.
  - This is how the whole payload stays a course rather than a pile of
    documents, and it is the check that catches a strand the arc forgot
    to teach. SNC1W shipped with a complete Earth-and-Space library that
    no class ever mentioned; the audit is what found it.
- Link only to pages that will exist. Maintain the full page inventory
  BEFORE fanning out authoring agents; hand every agent the complete
  sanctioned link list.

**`Style/What This Site Can Do.md` is the showcase**, and it teaches by
working example, not by comparison. Where the subject has notation the
teacher will have to type, give it a MINI-TUTORIAL: a three-column table
of *what you type* / *what appears* / *what it means*, where the middle
column is a live span rather than a description of one, so the page cannot
drift from the truth. The chemistry payloads' `\ce{}` tables are the
reference. Never write a callout weighing up two ways of writing the same
thing — a teacher wants to learn the one the site uses, not to adjudicate
between them. Keep the honest warnings that are still true (display maths
stays on one physical line; a bare `H_2O` comes out in variable italic).

**Required pages beyond the subject folders**: the Setup set (How <X> Class
Works, the safety/trust agreement in subject-appropriate form, What to
Wear/Bring, How Marks Work, Getting Help), the Style set (How This Site Is
Organised, What This Site Can Do, Writing About <Subject>), Help
Sessions.md, Learning Goals.md (transcluding 2–3 overall expectations
inside a curriculum block, with plain-words fallback text outside it), a
Tutorials `Using This Site.md`, and per-section: `index.md` (the landing
page — `title: Section __SECTION_NUMBER__`, "# Most Recent Class"
transcluding the NEWEST PUBLISHED class page of the payload's semester
(not Day 1, and not the unpublished finale) + a `%%` teacher comment about
advancing it + `![[Help Sessions]]` + `![[Key Links]]`) and a populated
`Key Links.md`. Every folder's `index.md` MUST have
`title: <Folder Name>` — a literal `title: index` shows "index" as the
page name on the built site. Every shared content folder (and `Tutorials`)
also carries a `_DUPLICATE ME.md` template (`title: _DUPLICATE ME`,
`publish: false`, `created: __CREATED__`) floating to the top in Obsidian
with authoring guidance, heading/TOC examples, curriculum link reminders,
and preview shortcuts.

**Key Links is the course's orientation panel, not an index of its
content.** It holds the things that set the tone and answer a newcomer's
first questions — how the class runs, the class agreement, how marks
work, where to get help, what to bring, the help-session times, the
learning goals, how the site is organised, the site tour — plus, at the
end, the curriculum. It links to **nothing a student reaches by
following the schedule**: no tasks, no lessons, no concepts, exercises,
investigations, tutorials, portfolios, or discussions. Those pages are
reached from the class page for the day they are used, which is what
makes the schedule the spine of the course; listing one here competes
with that, and it dates the panel the moment the unit ends. A real
teacher's Key Links is short and almost entirely course-level — theirs
reads: Notion, Student Course Outline, Ministry Course of Study,
Learning Goals, Ontario Curriculum, College Board Curriculum. The linter
fails any link into a content folder.

**The orientation links close the list**, in this order:

```
- [[What This Site Can Do]]
%%curriculum-start%%
- [[Curriculum/index|Curriculum Expectations]]
%%curriculum-end%%
- [[Scavenger Hunt]]
```

The `Curriculum Expectations` link is a must in every payload, wrapped in
curriculum markers so that declining the curriculum removes it cleanly — it is
easy to lose when adapting a previous payload, because stripping curriculum
blocks wholesale deletes it. The build inserts `Curriculum Coverage` directly
beneath it, so the two curriculum links sit together, with `What This Site Can Do`
above and `Scavenger Hunt` at the very end of Key Links. All positions are enforced.

**The Concepts `index.md` lists every concept page, grouped by unit, as a
bulleted list — one link per line.** Reference:
`ICS4U/shared/Concepts/index.md`.

```
**Unit 2 — Data structures**

- [[Dictionaries]]
- [[Stacks and Queues]]
- [[Choosing a Data Structure]]
- [[Recursion]]
```

Not `[[A]] · [[B]] · [[C]]` run together after the heading, and not a
prose sentence listing them. A student uses this page to find one idea,
so it has to be scannable: a separator-delimited run reflows differently
at every window width and the eye has nothing to land on. The heading may
be `**bold**` or an `##` H2 — pick one and hold it for the whole page,
and remember `enableToc: true` needs 4+ H2s to be worth setting. Every
page in the folder appears exactly once. Explanation that is an argument
rather than a list item stays as prose beneath its bullets. The same
grouped-bullet shape suits any folder index long enough to need grouping.

**Older curricula without printed codes** (pre-2020 documents like the
2005 mathematics one): assign positional codes in the style teachers
commonly use (strands lettered in document order, overalls and specifics
numbered within), and disclose that ONCE, in a warning callout on
`About These Expectations` — never as a repeated per-page callout, which
is noise. Ministry addenda get a short labelled note on the pages they
added. Sample problems embedded in expectation text are part of the
verbatim wording and stay.

**Class pages** (18–30 lines): frontmatter adds `transcludeTitleSize: h2`,
`enableToc: false`, `excludeBacklinks: true`, `tags: [unit-N]`; body is a
numbered Agenda of links + a "Things to do before our next class" checkbox
list (journal prompts often); **NEVER a curriculum connection block** (see
below); exactly ONE page in the whole payload is
`publish: false` — the final class page, carrying a `%%` comment explaining
how a page is held back. No absolute dates anywhere in prose.

**Fan-out**: hand-write the gold-standard exemplar and the landing/setup
pages yourself; batch the rest to 2–3 parallel agents, each prompt carrying
the style contract, the reading list (Tableau.md, the curriculum file, an
EXC2O register sample), the sanctioned link list, and per-page briefs with
assigned curriculum codes. Review their output — spot-read for voice, run
the linter.

## Phase 6 — Dates (they carry meaning)

- Class pages: `created: __CREATED_CLASS_K__`, K = chronological position
  (1 = first class). The installer turns these into every-other-weekday
  07:00 dates from September 8 of the current school year, so All Classes
  sorts newest-first.
- Every other page keeps `created: __CREATED__`. The installer then gives
  each shared page the date of the FIRST class that links to it — category
  listings sort in teaching order. So: **when a class first uses a page,
  link it from that class page.** A content page no class links to keeps
  the install-time date (fine for pure reference pages; the linter lists
  them so you can check the list is intentional).
- Per-section pages may also use `__SECTION_NUMBER__`.
- **Per-section publishing is the INSTALLER's job — never the payload's.**
  A course-level page (anything under `shared/`) is shared by sections
  that are not in step: one class may reach a topic a day later, or not
  yet at all. So `install_payload_file` splits a shared page's
  `created:`/`publish:` into `createdSectionN:`/`publishForSectionN:` — one pair
  per section, written together in section order — and `build_site.py`'s
  `process_frontmatter` resolves them back to plain keys for whichever
  section is being built. Write the payload with the ordinary single
  `created: __CREATED__` / `publish: true`: the payload cannot know how
  many sections the teacher will choose, and hand-writing per-section
  keys would freeze the course at one section. The linter rejects them.
  Pages under `per_section/` already belong to one section and keep the
  plain keys.

## Phase 7 — Lint, verify, ship

1. `python3 .claude/skills/example-content/lint_payload.py <CODE>` — must
   end "clean"; read the "no class links" notes and confirm each is a
   deliberate reference page. Read the **coverage line** every time: it
   reports `N/N expectations addressed` and lists those addressed only
   once. Anything short of N/N is a failure, not a note — the built map
   would show a red cell. The counts here and on the built page come from
   the same rule, so they must agree; if they ever differ, one of the two
   regexes has drifted and that is the bug to fix first.
2. Installer E2E without Docker: import `scripts/setup_course.py` via
   importlib, call `install_example_content` into a temp dir for both
   curriculum states; assert no curriculum folder/links remain when
   declined, dates stagger, re-runs write 0 files.
3. App suite (`ExampleContentTests` covers the catalogue lookup, the
   wizard's curriculum/coverage answers, and the bundled payload's
   `created` sentinel):
   `cd mac-app && xcodebuild -project Plantoir.xcodeproj -scheme Plantoir
   -configuration Debug test -only-testing:QuartzTeachersTests`.
4. `script -q /dev/null ./verify.sh` — the toolchain gate.
5. Container E2E: verify.sh leaves a dev-test container running; drive the
   baked wizard (`printf 'n\n<CODE>\n'` + many newlines, through
   `script -q /dev/null docker exec -it <container> python3
   /opt/scripts/setup_course.py --host-os mac`), then
   `./preview.sh <CODE> 1 --build-only --image quartz-teacher:dev-test`,
   then inspect the built HTML: landing transclusions render, the
   unpublished finale is absent, `%%` comments invisible, All Classes and one
   category listing sort correctly (check the `page-listing` region of the
   HTML, not the whole page — index prose also mentions page names), and
   `grep -rl katex-error <public dir>` finds NOTHING — a katex-error span
   means an equation shattered at a markdown seam (see the math rules in
   Phase 5). For a payload with heavy notation, render every `$…$` span through
   the build's own KaTeX with `throwOnError: true` — the module lives at
   `courses/<CODE>/.merged_output/section1/node_modules/katex` after any
   build.
6. **Math fidelity check**: where the source curriculum document
   typesets its mathematics (the 2007 mathematics PDF does), an
   adversarial verifier MUST compare every rendered expression
   side-by-side against renders of the document's own pages (150–400
   dpi as legibility demands): every coefficient, sign, exponent,
   subscript, fraction orientation, radical scope, vector arrow, and
   relation symbol. MCV4U is the reference for this pass (37/37 pages
   matched print). Older or plainer documents may print no typeset
   equations to compare against — best effort MUST still be made that
   the KaTeX output matches the regular-print equivalent: verify each
   expression against the document's plain-text form token by token,
   and read the rendered pages.
7. Clean up: `docker rm -f <container>`, `rm -rf courses/<CODE>`.
8. **Refresh the course-code catalogue page.** It states how many courses
   arrive fully written, so a new payload makes it wrong the moment it
   lands:

       python3 .claude/skills/example-content/build_catalogue_page.py <scratchpad>/ontario-course-codes.html

   then publish that file with the Artifact tool, passing
   `url: https://claude.ai/code/artifact/cfb0ce4b-3691-4aaa-93a8-4d848254510f`
   and `favicon: 🎓` — the URL is the one the teacher already has, so it
   must be updated in place rather than replaced, and the favicon is how
   they find its tab. The generator reads the code lookup, the payload
   folders, and `families.json`; it never hard-codes a count. When the app
   or installer changes how a code resolves to a family, change
   `family_for()` to match — the page's job is to tell the truth about
   what a teacher receives, so a guess there is a lie there.
9. No GUI-IMPROVEMENTS entry for a content-only payload (the spec tracks
   behaviour); commit with a message naming the course code.

## Skeletons: what every OTHER course code starts as

The codes in `support/example_content/` have payloads — count the folders
rather than trusting a number written here. Every other Ontario code gets a
**skeleton** — the same shape with placeholder content, generated rather
than hand-written:

- `.claude/skills/example-content/generate_skeletons.py` holds the tables
  and writes `support/skeletons/<family>/` plus `families.json` (prefix →
  family). Edit the tables, re-run it, never edit the output by hand.
- A **shape** is the folder set and class-agenda vocabulary for a kind of
  course (science, mathematics, performance-arts, workshop, humanities,
  language, computing, business, studio-arts, physical-education,
  general). A **family** picks a shape and names things its own way — music
  rehearses Repertoire, drama has Conventions, a kitchen has Kitchen Safety.
  Fifty families cover 499 prefixes; unknown codes fall back to `general`.
- Agenda lines carry `%SLOT%` tokens (`%DOING%`, `%IDEA%`, `%PRACTICE%`,
  `%SAFETY%`…) resolved to whichever folder the family actually has, so a
  class page never links to a folder that does not exist.
- The payload rules apply: sentinels, `__CREATED_CLASS_K__` on twelve class
  pages, Key Links holding only course-level orientation and ending with
  the curriculum links, per-section keys added by the
  installer. Skeleton pages may also use `__COURSE_CODE__` and
  `__COURSE_NAME__`.
- `lint_skeletons.py` is the gate — every link resolves, every page is
  titled, no template token survived. Run it after every generation.
- The sidebar is a RULE, not a list: the `Curriculum` folder is never
  visible, every other visible shared folder carries a chevron (including
  one the teacher adds), and per-section folders — `All Classes` — stay
  plain links to their listing. `lint_skeletons.py` checks every manifest
  against it, and `SkeletonCatalog.sidebar(for:…)` is where the app
  decides it.
- The wizard offers the skeleton's folders as the DEFAULT answers to its
  structure questions; the app's New Course sheet does the same through
  `SkeletonCatalog`. A teacher's own edits are never overwritten.
- Touching a shape or the family table changes up to fifty families at
  once: regenerate, run `lint_skeletons.py`, then build ONE course from an
  affected family and read it. `verify.sh` covers the toolchain, not the
  content.

**A new payload retires its skeleton automatically** — example content
always wins for a code that has it. Nothing to remove.

## Converting an existing complete course into a payload

The SNC1W payload was made by CONVERTING the EXC2O example course rather
than authoring from scratch — worth repeating when a finished course
already holds the content. The conversion is mechanical, and the linter
is the contract; what EXC2O needed:

- Real `created:` dates → sentinels: class pages get
  `__CREATED_CLASS_K__` by sorting their dates (K = chronological
  position); everything else gets `__CREATED__`. Pages with NO created
  line get `created: __CREATED__` ADDED — that upgrade lets the
  installer date them to the class that first links them, so category
  listings sort in teaching order.
- End-of-page "## Curriculum" listings wrapped in
  `%%curriculum-start%%`/`%%curriculum-end%%`; the Key Links first
  entry replaced with the canonical marked
  `[[Curriculum/index|Curriculum Expectations]]`; standalone prose
  pointers at the curriculum wrapped too, so a curriculum-free install
  leaves no dangling sentence.
- The finale class becomes the `publish: false` example (with the standard
  `%%` comment), and the landing transclusion steps back to the newest
  PUBLISHED class.
- Section landing title becomes `title: Section __SECTION_NUMBER__`.
- Content the course holds beyond its scheduled classes (EXC2O has a
  space/electricity library its 26 agendas never link) is fine — the
  linter's "no class links" notes list it; confirm the list reads as
  deliberate extras, not forgotten links.

## Known traps

- Wizard structure prompts are SKIPPED when pre-populating — a payload
  mistake ships silently; that is what the linter's manifest checks catch.
- The `%%curriculum-start%%` markers must be balanced per file, on their
  own lines.
- Escaped pipes: agents reliably forget them in tables; the linter catches.
- The colour-scheme picker needs a TTY — always `script -q /dev/null` when
  driving the wizard non-interactively.
- Shell cwd resets between tool calls; `preview.sh` must run from the repo
  root (or a working folder).
- The Docker image bakes `support/` — payload edits change the recipe hash
  and force a rebuild on next use; that is expected, not a bug.

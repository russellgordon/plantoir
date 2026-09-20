# Building example content for a British Columbia course code

A payload is a complete, working course a teacher keeps: real pages, a real
semester, real curriculum. This skill is the **British Columbia counterpart**
to [`.claude/skills/example-content/SKILL.md`](../example-content/SKILL.md)
(call it "the Ontario skill" below). It is deliberately **self-contained** —
everything you need for a BC payload is here, including instructions that
also appear in the Ontario skill, so you should not need to cross-reference
it. Where this skill is silent on something purely mechanical (how the
linter works, how the installer's sentinels resolve), the Ontario skill and
the tool scripts under `.claude/skills/example-content/` are still the
source of truth — they are jurisdiction-agnostic and BC payloads use them
unmodified.

**`MCMPR11` (Computer Programming 11, ADST) is the BC reference
implementation** — when in doubt, open it and copy its shape. It was
rebuilt 2026-08-19/20 specifically to be a model of curriculum fidelity and
content depth; its `shared/Curriculum/` folder, its `shared/Discussions/`
folder (real classroom activity protocols, not just discussion questions),
and its `per_section/All Classes/` agenda-linking pattern are all worth
reading before you start. `ADA1O` remains the Ontario reference; do not use
it as a structural template for BC's curriculum folder specifically — its
shape is wrong for BC (see below).

## Authoring is two passes, and the second one is adversarial

**A primary agent writes; an adversarial sub-agent then checks its work.
This is not optional and it is not a proofread.** Every payload, every
revision to a payload, and every change to this skill goes through both
passes before anybody calls it done.

The reason is measured, not theoretical. Each of these was produced by a
careful first pass that reported success, and each was found by a second
agent briefed to disbelieve it:

- A worked example written into this skill named the wrong unit and the
  wrong days for the task it was drawn from — Unit 2 for a task that runs
  in Unit 1 — and tied its evidence to a terminology expectation that does
  not describe that evidence. It broke three of the six rules printed
  directly beneath it.
- Ten of fourteen policy citations in the same section were off by one.
  Every quotation was real; every page number was wrong.
- An Ontario course revised to satisfy these rules sent a teacher to observe a
  counting period that does not exist on that day, quoted an expectation
  as evidence-in-conversation when its verbatim text says "in writing",
  and stated the homework rule correctly on one page while five other
  pages went on breaking it — including a paragraph the same revision
  had just written.

None of these is the kind of mistake re-reading your own work finds. They
read as entirely plausible, which is exactly the property that makes them
survive a self-review and fail a teacher.

**How to run the second pass:**

- **Brief it to REFUTE, not to review.** Tell it to assume every factual
  claim is misremembered until checked against a primary source, and every
  new rule conflicts with an existing one until it has read the
  surrounding file. "Look this over" produces praise; "find what is wrong
  here, and do not pad" produces findings.
- **Hand it the primary sources and say where they are** — the live page on
  `curriculum.gov.bc.ca`, the class pages, the competency and content
  texts in `Curriculum/`, `lint_payload.py`, `build_site.py`. A reviewer working
  from memory reproduces the first agent's errors.
- **Name the attack surfaces in priority order**, highest-value first. For
  a payload that is: do the days, task names and curriculum codes a page
  names match what the arc actually does; is every quotation verbatim and
  every citation right; does any page contradict another; could a teacher
  actually run each period as written.
- **Require file:line, the claim, what is actually true, the EVIDENCE, and
  the smallest fix** — and require CONFIRMED to be separated from
  SUSPECTED. A finding without evidence is a second opinion, not a check.
- **Verify what it reports before you act on it.** It is a check, not an
  oracle: an adversarial pass in this repository was itself wrong about how
  many payloads a defect affected, because it used a looser rule than the
  code does. Confirm each finding against the source yourself, then fix.
- **Do not let it edit.** It reviews; the primary agent fixes. A reviewer
  that repairs what it finds stops looking for more.

The linter is not this pass and cannot become it. It checks structure —
links resolve, markers balance, coverage is complete — and almost nothing
in the assessment rules is machine-checkable. A payload can be `clean` and
still send a teacher to the wrong day on Monday.

## The one fact that changes everything: BC's curriculum is not Ontario's

Ontario's curriculum documents are pre-structured almost exactly the way
this project's payload format wants them: **strands** (lettered A, B, C…),
each with numbered **overall expectations** (A1, A2…) and, under each,
numbered **specific expectations** (A1.1, A1.2…). The Ontario skill's whole
Curriculum-folder recipe assumes that shape exists in the source document
and just needs transcribing.

**British Columbia's curriculum documents do not have that shape, ever.**
This is not a vintage issue the way it is for old Ontario documents — it is
how BC's curriculum model works for every course, current or old. Treat the
positional-code trick the Ontario skill treats as a special case for
"older curricula without printed codes" as the **normal, default case for
every BC course**.

### BC's actual model: Big Ideas, Curricular Competencies, Content

Every BC curriculum document — K-12, every subject — is built from exactly
three kinds of learning standard, and BC's own name for this is the
**Know-Do-Understand model**. Get the mapping exactly right; it is easy to
get backwards (an earlier draft of MCMPR11's curriculum page did, and an
adversarial review caught it):

| BC's own term | What it is | Which word in "Know-Do-Understand" |
| --- | --- | --- |
| **Content** | A flat list of facts/topics/skills to know | **Know** |
| **Curricular Competencies** | What students do — grouped under named categories that differ by subject | **Do** |
| **Big Ideas** | A handful of framing statements for the whole course | **Understand** |

The model's own NAME lists the words in the order Know-Do-Understand, but
when BC lists the three CATEGORIES on a curriculum page it lists them
**Big Ideas, Curricular Competencies, Content** — i.e. Understand, Do, Know,
the reverse order from the model's name. Write out the mapping explicitly
wherever you state it (as the table above does) rather than trusting either
ordering to imply the pairing — that ambiguity is exactly what caused the
earlier mistake.

- **Big Ideas**: 3-5 short framing sentences shown in boxes at the top of
  the page. They are NOT individually evaluated or "addressed" the way an
  expectation is — do not create a coded page per Big Idea, do not put them
  in the curriculum-coverage transclusion system at all. Quote them once,
  verbatim, as a callout on the Curriculum folder's `index.md` (see
  MCMPR11's, which has exactly **3** Big Ideas for Computer Programming 11 —
  confirmed against both the live page's raw HTML and the Ministry's PDF,
  which agree).
  - **Watch for glossary popovers being miscounted as a whole extra Big
    Idea (or Content item).** BC curriculum pages attach an inline
    `data-toggle="popover"` glossary tooltip to certain terms — "design
    cycle" inside Big Idea 1 is one — and a naive fetch or a quick skim of
    rendered HTML can flatten that tooltip's elaboration text into what
    looks like a separate, 4th bullet. This is NOT the Ministry revising
    the curriculum; it is a rendering/extraction artifact, reproducible with
    this project's own WebFetch tool on a broadly-scoped request. If a live
    fetch produces a suspiciously round-number-plus-one count, check the
    raw HTML for `views-row` divs (each real Big Idea is its own row; a
    popover is not) or cross-reference the PDF before "fixing" a payload
    that may already be correct.
- **Curricular Competencies**: bullets grouped under named categories.
  Genuinely subject-specific — do not assume ADST's categories generalize.
  MCMPR11 (ADST) groups them as **Applied Design** (itself split into seven
  named stages — Understanding context, Defining, Ideating, Prototyping,
  Testing, Making, Sharing — each with its own short bullet list), **Applied
  Skills**, and **Applied Technologies**. A BC math or science course will
  have entirely different category names (BC's K-12 curriculum overview
  documents mention categories like "Reasoning and analyzing" or
  "Questioning and predicting" for other areas) — **look up the actual
  category names for your specific course**, live, every time; never assume
  ADST's shape carries over.
- **Content**: a single FLAT list, no sub-groups, no strand letters. Do not
  invent categories to sort it into — the earlier draft of MCMPR11 grouped
  Content into an invented "K1 Computational Thinking, K2 Control
  Structures, K3 Data Types…" taxonomy that does not exist in the Ministry
  document, and one entry in it fabricated the phrase "First Peoples
  cultural contexts," which appears nowhere in the source. That is exactly
  the failure mode this rule exists to prevent: **if the Ministry's list is
  flat, your representation of it is flat too.**

### BC prints no codes — assign them, and disclose it once

Since there are no Ministry codes to copy, assign **positional codes** in
the order the Ministry document lists things, using letters that echo the
Ministry's own group names:

- One letter per **Curricular Competency category**, matching its real
  name's initial in a way a reader would recognize — MCMPR11 uses `D` for
  Applied **D**esign, `S` for Applied **S**kills, `T` for Applied
  **T**echnologies. Pick similarly for your course's actual categories.
  - If a category has its own named sub-groups (like Applied Design's seven
    stages), number them in the Ministry's own order: `D1` Understanding
    context, `D2` Defining, `D3` Ideating, `D4` Prototyping, `D5` Testing,
    `D6` Making, `D7` Sharing. Each stage's bullets become `D1.1`, `D2.1`,
    `D2.2`, `D2.3`, and so on, numbered within that stage in Ministry order.
  - If a category has no named sub-groups (like Applied Skills and Applied
    Technologies in ADST — just one flat bullet list each), it gets ONE
    group number: `S1`, with specifics `S1.1`, `S1.2`…
- One letter for **Content**, distinct from the competency letters — MCMPR11
  uses `K1` as a single umbrella "overall" (there is no Ministry sub-grouping
  to mirror), with every flat Content item as `K1.1` through `K1.N` in the
  Ministry's own printed order. Do not split Content across multiple letters
  or invent sub-numbering (`K2`, `K3`…) — there is exactly one Content list,
  so there is exactly one umbrella code.
- **Disclose the whole scheme once**, on the folder's "About These
  Standards" (or equivalent) page — never repeated per-page. State plainly:
  BC prints no codes; these are assigned for this site, in Ministry order;
  the wording under every code is the Ministry's own, unparaphrased. See
  `support/example_content/MCMPR11/shared/Curriculum/About These
  Standards.md` for the exact wording to adapt.

### Overall/group pages have no invented topic sentence

Ontario's overall expectations are real, standalone sentences the Ministry
wrote. BC's competency GROUPS (e.g. "Defining") are just a bolded label
over a bullet list — there is no Ministry-written summary sentence to quote.
**Do not invent one.** The group's own overall/`.N` page (`transcludeTitleSize:
h3`) carries the Ministry's own short label as its body text (e.g.
`Defining ^text`), not a fabricated description. For the Content umbrella
page, the closest thing to a label is the Ministry's own lead-in phrase —
MCMPR11 uses `Students are expected to know the following: ^text`, which is
literally printed on the source document.

### The rest of the leaf-page format matches Ontario exactly

Frontmatter for both overall/group pages (`transcludeTitleSize: h3`) and
specific pages (`transcludeTitleSize: h4`) is minimal — `transcludeTitleSize`,
`tags` (the code plus a `strand-<letter>` tag), body text ending in a bare
` ^text` anchor, **nothing else**: no `title:`, no `publish:`, no `created:`.
This matches the Ontario reference exactly (see
`support/example_content/ICS3U/shared/Curriculum/A1.1.md`) — an earlier
MCMPR11 draft added `title:`/`publish:` and omitted `transcludeTitleSize`,
which is wrong; fix it to match Ontario's leaf-page shape, not the other
way around.

## Researching the curriculum (verbatim or not at all — this is non-negotiable)

**From the LIVE official portal, every time**: `curriculum.gov.bc.ca`, e.g.
`curriculum.gov.bc.ca/curriculum/adst/11/computer-programming` or
`curriculum.gov.bc.ca/curriculum/mathematics/`. Do not work from a saved
copy, and do not add one to this repository — the Ministry updates these
whenever it likes, and a copy held here manufactures a stale second version
rather than preserving anything.

### The WebFetch trap, and how to get around it

Asking a fetch tool to "reproduce the whole page verbatim" tends to get
**refused** — the small model doing the fetch-and-summarize sometimes treats
a large verbatim quote request as a copyright problem, even though BC
Ministry curriculum documents are Crown copyright published under the
**Open Government Licence — British Columbia**, which explicitly permits
exactly this kind of reproduction (the same way this project already
reproduces Ontario's Queen's Printer material). Two ways around it, both
proven to work:

1. **Ask in small, targeted chunks.** A request for "just the Big Ideas" or
   "just the bullets under Testing and Making" succeeds where "reproduce
   the whole page" is refused. Split your research into one fetch per
   section (Big Ideas; each Curricular Competency category, one at a time;
   Content) rather than one giant fetch.
2. **Fall back to the Ministry's own PDF.** Every course page offers a PDF
   export, linked near the top — the URL follows the pattern
   `curriculum.gov.bc.ca/sites/curriculum.gov.bc.ca/files/curriculum/<area>/en_<area>_<grade>_<course-slug>.pdf`.
   Fetching the PDF directly and asking for a section tends to succeed even
   when the HTML page was refused, and the fetch tool will save the PDF
   locally so you can also open it with the Read tool (which handles PDFs
   natively, page by page) for a completely clean, structured read.

**Cross-check live vs. PDF, and trust live.** The two can disagree — BC
revises curricula, and a PDF export is a snapshot from whenever it was
generated (the file often has no visible date; MCMPR11's PDF happened to
print "June 2018" in its footer). When they disagree, the live page wins,
per the master rule above — but note the discrepancy in your research file
so a reviewer can see you checked both rather than picked one.

### What to capture

For the exact course, from the LIVE document:

- Every **Big Idea**, verbatim, and the exact count.
- Every **Curricular Competency category name**, in the Ministry's own
  words and capitalization (note: BC sentence-cases sub-headings like
  "Understanding context" — lowercase "c" — don't silently title-case them).
- Every bullet under every category/sub-group, verbatim, in document order.
- Every **Content** bullet, verbatim, in document order — resist any urge
  to group them.
- The citation: document title, the course's official portal URL, the PDF
  and DOCX export URLs, and the standard BC copyright line: **"© Province
  of British Columbia. Reproduced under the Open Government Licence —
  British Columbia."**

Save this as a structured markdown research file the way the Ontario skill
describes — it is both the generator's input and the audit trail. Anything
you could not verify gets flagged and is not published as Ministry wording.

## Generating the Curriculum folder

Adapt a generator script rather than hand-writing 40-60 files — the same
principle as the Ontario skill, but the data shape is different (a nested
list of competency groups plus a flat Content list, not a flat list of
strands). `support/example_content/MCMPR11` was built this way; the shape
to copy is roughly:

```python
APPLIED_DESIGN = [
    ("D1", "Understanding Context", "Understanding context", [
        "Conduct user-centred research to understand design opportunities and barriers",
    ]),
    ("D2", "Defining", "Defining", [
        "Establish a point of view for a chosen design opportunity",
        "Identify potential users, intended impact, and possible unintended negative consequences",
        "Make inferences about premises and constraints that define the design space",
    ]),
    # ... one tuple per named competency stage, in Ministry order
]

CONTENT = ("K1", "Content", "Students are expected to know the following", [
    "design opportunities",
    "design cycle",
    # ... every flat Content bullet, in Ministry order, no sub-grouping
])

def overall_page(code, title, tag_slug, body_text):
    # transcludeTitleSize: h3, tags: [code, strand-<slug>], body_text + " ^text"
    ...

def specific_page(code, tag_group, tag_slug, text):
    # transcludeTitleSize: h4, tags: [tag_group, strand-<slug>], text + " ^text"
    ...
```

Run it once to produce the whole folder, then hand-write the two narrative
pages it does not generate: `About These Standards.md` (the disclosure —
adapt MCMPR11's) and `index.md` (a mermaid graph of the competency flow,
the Big Ideas callout, then every overall+specifics transcluded in document
order, grouped under `## Curricular Competencies` and `## Content`
headings — see MCMPR11's for the exact shape, including the note that
Content is deliberately NOT sub-grouped).

## Mapping curriculum codes onto content pages — honestly, not positionally

This is where a BC payload most often goes wrong, and it is worth being
deliberate about, because the failure is invisible to the linter (which only
checks that a code exists and is transcluded at least once — it cannot
check whether the claim is TRUE).

- **A Content code (`K1.x`) can legitimately repeat across many pages.**
  Content items are broad, un-opinionated topics ("control structures",
  "problem decomposition") that many lessons genuinely touch — reuse is
  expected and healthy here, more so than for Ontario's finer-grained
  specific expectations.
- **A Curricular Competency stage code (`D1`-`D7` in ADST, or your course's
  equivalent) must match what the page ACTUALLY does at that point in a
  task's lifecycle.** An early draft of MCMPR11 used `D1.1` (Understanding
  Context) as boilerplate on every single Task page and the Final
  Evaluation, regardless of what part of the design process that page
  covered — a launch day claiming "Understanding context" is honest; a
  polish-and-hand-off day claiming the same thing is not. Read what the page
  actually asks a student to do, then pick the stage that matches:
  - A task's opening/launch section → `D1` Understanding context, `D2`
    Defining, `D3` Ideating.
  - Its architecture/planning days → `D3` Ideating, `D4` Prototyping.
  - Its build/coding days → `D4` Prototyping, `D6` Making.
  - Its test/verification days → `D5` Testing.
  - Its hand-off/reflection/peer-review days → `D7` Sharing.
- **Every code across the whole payload must be reached by at least one
  published page** (the linter enforces this), and **every competency GROUP
  and the Content umbrella must be reached by at least one page in Tasks**
  (assessed work) — the same mechanism the Ontario skill describes for
  "overall expectation... never reached by assessed work." Plan your Task
  pages' code sets by reading what each Task genuinely requires, not by
  copying the same list onto every Task page.
- Run `python3 .claude/skills/example-content/lint_payload.py <CODE>` and
  read the **coverage line** exactly as the Ontario skill instructs — it
  is the same tool, same numbers, same rule: `N/N expectations addressed`,
  with a "thin" list for anything addressed only once.

## Manifest fields specific to BC

```json
{
  "jurisdiction": "BC",
  "credit_value": 4.0,
  "final_evaluation_hours": 3.0
}
```

- `"jurisdiction": "BC"` switches the linter's hours math
  (`lint_payload.py`, search `jurisdiction`) to BC's rule: a **standard BC
  senior secondary course is 4.0 credits**, and the linter's credit
  multiplier for BC is `credit_value / 4.0` — so a full 4.0-credit BC course
  targets the same ~110-120 total scheduled hours as a full 1.0-credit
  Ontario course; a half-load or short BC course states its own
  `credit_value` (e.g. `2.0`) and the arc-length check scales accordingly.
  Get `jurisdiction` and `credit_value` right FIRST, before worrying about
  the arc's class-page count — otherwise the linter's hours complaint will
  look like an arc-length bug when it is actually a manifest bug.
- Everything else in the manifest (`shared_folders`, `curriculum_folder`,
  `class_weekday_step`, hidden/expandable lists) works exactly as the
  Ontario skill describes — this is shared machinery, not something BC
  changes.
- The BC course-code catalogue lives at
  `support/british_columbia_secondary_courses.json` (parallel to
  `support/ontario_secondary_courses.json`) and is already wired into
  `scripts/setup_course.py`'s course-lookup path — check your course code
  is listed there; if not, that is a small separate addition (a
  `formal_name`/`short_name` pair), not something this skill's content work
  needs to solve. The skeleton-family fallback
  (`support/skeletons/`, `families.json`) serves BC codes through the same
  generic 3-letter-prefix mechanism as Ontario codes — nothing BC-specific
  is needed there either, and a new payload retires its skeleton exactly as
  for Ontario.

## Everything from the Ontario skill that still applies, unchanged

The rest of the payload is subject-shape and depth work, not a
jurisdiction difference, and the Ontario skill's guidance carries over
directly. The headlines, so this skill stays usable standalone — but read
the Ontario skill's fuller text for anything you need more than a
reminder of:

- **Choose folders that fit the subject**, not a template. A design/skills
  course (ADST) wants Concepts, Explorations, Programs/Portfolios in
  MCMPR11's shape; a different BC subject wants different folders, the same
  way an Ontario science course swaps in Investigations over Conventions.
- **Plan a full semestered arc** — four units building to a performance or
  summative task each, ~86 class pages at a 75-minute period for a full
  credit-equivalent course (fewer for a lower `credit_value`), the last
  3-4 review-tagged, a `final-evaluation`-tagged Task closing it out,
  `class_weekday_step` staggering dates across the real school calendar.
  The three shape rules (culminating task ends the course; a substantial
  task gets several named working periods, not just a launch and a due
  date; ideas return later in a different form) apply exactly as written.
- **Lean constructivist** in every lesson: meet the idea as a problem before
  it gets a name; for math specifically, the Boaler/Liljedahl/Schettino
  guidance (visibly random groups, vertical whiteboards, notes to a future
  forgetful self, no speed worship) applies to BC math courses exactly as
  it does to Ontario ones — BC's own curriculum model, with competencies
  literally named "Do", is if anything MORE explicit about wanting active
  work over passive lecture, which makes this guidance more load-bearing
  here, not less.
- **Canadian writers, with real Indigenous presence**, for any BC English
  course — the same rule as Ontario, verified before publishing.
- **Python for Computer Science.**
- **All three kinds of assessment, the per-unit sequence, success criteria
  on task pages, and the hidden triangulation block** — see the next
  section. These came out of Ontario's *Growing Success*, but nothing in
  them is Ontario-specific and BC's own reporting policy asks for most of
  it in its own words.
- **The whole style contract** — frontmatter shape, Canadian spelling, em
  dashes, ~80-column wrap, one Obsidian feature per page, exercises' folded
  answers with no "(click to expand)" hint, checklists framed as read-only,
  escaped pipes in table cells, KaTeX-safe math formatting, mermaid pie
  chart rules, chemistry via `\ce{}` — all of it, unchanged.
- **"No page stands on its own"** — every page reachable within two hops of
  a class page; curriculum pages are the one exemption, reached through the
  index and Key Links by design.
- **Curriculum blocks go on destination pages only, never on `Unit N, Day M`
  class pages.** A class page is a schedule of links to the concept, task,
  or discussion the period actually consists of — the codes belong on THOSE
  pages, not repeated on the agenda. The linter rejects any class page
  containing `%%curriculum-start%%`. This applies to BC's `D`/`S`/`T`/`K1`
  codes exactly as it does to Ontario's lettered codes.
- **Required pages beyond subject folders** — Setup, Style, Help Sessions,
  Learning Goals (transcluding 2-3 competency GROUPS for BC — not specific
  Content items, which are too granular for a course-level framing page —
  with plain-words fallback outside the curriculum block), Tutorials'
  `Using This Site.md`, per-section `index.md` and `Key Links.md`, every
  content folder's `_DUPLICATE ME.md` template.
- **Key Links stays course-level only** — orientation, not an index of
  content; the same closing order (`What This Site Can Do`, curriculum
  block, `Scavenger Hunt`).
- **Dates**: class pages get `__CREATED_CLASS_K__`; everything else
  `__CREATED__`; per-section publishing sentinels are the installer's job,
  never hand-written into the payload.
- **Fan-out**: hand-write the gold-standard exemplar and landing/setup pages
  yourself; batch the rest to parallel agents with the style contract, the
  sanctioned link list, and per-page curriculum-code briefs.
- **Lint, verify, ship** — the same `lint_payload.py <CODE>` gate, the same
  installer E2E, the same app test suite, the same `verify.sh`, the same
  catalogue-page refresh, the same commit-message convention (name the
  course code, no GUI-IMPROVEMENTS entry for a content-only payload).

## Assessment: for, as, and of learning

Inherited from the Ontario skill, where it is derived from *Growing
Success*. **Do not cite *Growing Success* in a BC payload** — it is Ontario
policy and governs nothing here. BC's own instrument is the **K-12 Student
Reporting Policy** (effective 1 July 2023), at
`https://www2.gov.bc.ca/gov/content/education-training/k-12/administration/legislation-policy/public-schools/student-reporting`.
Read it LIVE if a decision turns on its wording — this skill deliberately
does not quote it, for the same reason it does not keep a copy of the
curriculum. In summary, it requires descriptive feedback written in clear,
accessible language that names strengths and supports specific goals;
student self-reflection on the Core Competencies and student goal-setting
as REQUIRED content in Learning Updates and the Summary of Learning; the
Provincial Proficiency Scale (Emerging, Developing, Proficient, Extending)
for K–9; and timely, responsive communication with students and families.
The practical effect is that **assessment *as* learning is not optional
here — BC reports on it by name.**

**Three modes, all of which a payload must show.** *Of* learning is
evaluation, at or near the end of a unit and the end of the course. *For*
learning is evidence gathered to decide what to teach next and to give
descriptive feedback. *As* learning is the student judging their own work
against criteria they understand, setting a goal, and acting on it. A
payload of four units and five summative tasks has written only the first.
The other two live in the AGENDAS, which is where a reader can tell whether
they were designed or merely assumed.

**Per unit, the arc must contain all of the following, in this order:**

1. a **diagnostic** near the unit's start whose named purpose on the class
   page is finding out where this class is starting from;
2. the unit's **learning goals and success criteria in student language**,
   in the students' hands at launch rather than at hand-in. They live on
   the TASK page (or a unit page) that the class page links to on launch
   day — a class page is a schedule, so the criteria go where the work is.
   Write them from the Curricular Competencies the task actually demands,
   in words a student uses, not by pasting competency text;
3. **formative work on at least a third of the unit's class pages**, named
   as such on the agenda — an exit ticket, a code review, a design critique,
   a draft read aloud;
4. at least one **feedback checkpoint before the summative**, and at least
   one working period after THAT CHECKPOINT whose stated job is acting on
   the feedback. A unit that launches a task and then collects it, with
   nothing in between, has nowhere for the feedback to land — and BC's
   policy is explicit that feedback must "support specific goals for
   further development", which is impossible if there is no later work to
   apply it to;
5. at least one **self-assessment episode the teacher has modelled first**,
   and at least one that touches the **Core Competencies** by name, since
   the student's own reflection on them is required reporting content
   rather than an enrichment activity;
6. the **summative task**, at or near the end.

**Success criteria on every task page, before the work starts.** A short
table of qualities and what each looks like to a reader, an audience or a
user is the usual shape; a plain list is fine where the page's one
demonstrated Obsidian feature is something else. A task with no success
criteria cannot support assessment *as* learning, because there is nothing
for a student to judge their own work against — and in BC that is a
reporting gap, not just a pedagogical one.

**Triangulate: observation, conversation, product — and put a hidden
prompt on every task page.** Evidence gathered only from things handed in
is one source of three. Observation and conversation are the hardest and
slowest to gather well, they leave no trace unless the teacher deliberately
makes one, and they are therefore the two that quietly vanish from a real
course. A payload cannot gather them for anybody, but it CAN tell the
teacher exactly where in each task they are available.

**The mechanics are identical to the Ontario skill's, and they are
technical rather than stylistic** — read that section for the full
reasoning, but do not deviate from any of this:

- The block goes at the very END of the task page, AFTER
  `%%curriculum-end%%`. Never INSIDE the curriculum markers:
  `strip_curriculum_blocks()` in `scripts/setup_course.py` deletes
  everything between them for a teacher who declines curriculum pages, so a
  nested comment vanishes silently.
- `%%` is Obsidian's comment marker and the vendored Quartz strips it at
  text level (`commentRegex = /%%[\s\S]*?%%/g` in
  `quartz/plugins/transformers/ofm.ts`), so multi-line blocks are safe and
  nothing inside is ever published.
- **Plain text only inside the block** — no `[[wikilinks]]` and no
  `![[transclusions]]`. `lint_payload.py` and `build_site.py` read the raw
  markdown without stripping comments, so a hidden transclusion would count
  as curriculum coverage no student page provides, and a hidden link would
  satisfy the two-hop reachability check. The linter now FAILS on this.
- "Task" means a page in `Tasks/`: both gates decide what counts as
  assessed work by folder name, so evaluated work that lives only in
  `Explorations` or `Programs` leaves red chips on the Curriculum Coverage
  map. If the real evaluated work is an exploration, the task page belongs
  in `Tasks/` and links to it.
- Write it SPECIFIC to this task, naming real days from the arc and
  checking them against the class pages; name what is visible only in the
  DOING and invisible in the product; give the conversation two or three
  ACTUAL questions plus what a strong answer sounds like; say how to record
  it in seconds; prefer a slot the arc already has; and tie it to a
  competency code the task already lists, checking that the code says what
  you claim. `lint_payload.py` emits a NOTE for any `Tasks/` page missing
  the block, and the note cannot tell a real prompt from boilerplate — that
  part is on you.

**What stays out of a mark — with an honest caveat.** The Ontario skill
lists four prohibitions drawn from *Growing Success*: a peer's or the
student's own judgement never contributes to a mark; no common group mark;
ongoing homework is not evaluated work; learning skills and work habits are
reported separately from achievement. **Only the first has a direct BC
analogue** — self-reflection in BC is reporting content the student
authors, not a mark the teacher borrows. The other three are this project's
practice rather than BC requirements, and a BC payload should follow them
because they are defensible, not because policy compels them. Do not write
them into a `How Marks Work` page as though BC mandated them, and **do not
carry Ontario's 70/30 final-evaluation split into a BC course** — that is
an Ontario secondary rule with no BC equivalent. A BC `How Marks Work`
should instead say where evidence comes from (all three kinds), name the
Curricular Competencies in student words, and say plainly that the
student's own reflection is part of what gets reported.

## What made the ORIGINAL MCMPR11 draft "sparse" despite reasonable prose —
## and the check that finds this in any BC (or Ontario) payload

The most common single defect in a rushed payload is not thin prose on the
pages that exist — individual pages can read perfectly well — it's **agenda
items on class pages that name an activity and link to nothing**, because a
teacher reading "Case Discussion — algorithmic decision-making in public
safety" with no link has been handed a topic sentence, not a lesson. This is
invisible to the linter (a class page with no link in an agenda line is not
a broken link — it is just prose) and easy to undercount by eye, so audit
it with a script rather than skimming:

```python
import re, glob
files = sorted(glob.glob("support/example_content/<CODE>/per_section/All Classes/*.md"),
               key=lambda f: (int(re.search(r'Unit (\d+)', f).group(1)),
                               int(re.search(r'Day (\d+)', f).group(1))))
total = linked = 0
for f in files:
    text = open(f).read()
    agenda = text.split("## Agenda")[1].split("## Things to do")[0]
    # Join wrapped continuation lines (indented, no leading digit) onto the
    # numbered item they belong to before checking for a link — otherwise a
    # link that wrapped to a second physical line is miscounted as bare.
    items, cur = [], None
    for line in agenda.split("\n"):
        if re.match(r'^\d+\.', line.strip()) and not line.startswith(" "):
            if cur is not None: items.append(cur)
            cur = line.strip()
        elif cur is not None and line.strip():
            cur += " " + line.strip()
    if cur is not None: items.append(cur)
    for it in items:
        total += 1
        linked += '[[' in it
print(f"{linked}/{total} agenda items linked ({total - linked} bare)")
```

Compare the bare-rate against a healthy reference course — ICS3U runs in
the mid-twenties percent bare, and MCMPR11 today runs a little lower than
that; in both cases essentially all of it is legitimate checkpoints,
work-periods, and review days (see below). Run the script yourself rather
than expecting an exact figure — the precise number drifts as either course
changes. A rate much higher than the reference means real material is
missing, not that the course happens to run a lot of independent work
periods.

Then triage every bare item into exactly one of:

- **LINK it** — to an existing page that already covers it (most common —
  the previous author often wrote the concept page and simply forgot to
  link it from the day that uses it), or to a genuinely new page you write
  because no resource for that activity exists yet.
- **LEAVE it bare, deliberately** — a real checkpoint (instructor sign-off,
  milestone check), a work period, a review day, or forward-looking
  narration ("Looking ahead to Unit 3…") does not need a linked resource,
  and forcing one onto it is padding, not content. Say so explicitly when
  you triage rather than silently skipping it, so a reviewer can tell
  "deliberately bare" from "missed."

## Grounding requirements — active involvement, multiple peoples, current events

These are not BC-specific rules exactly, but BC's ADST-family courses (and
any BC course whose Curricular Competencies explicitly ask students to
"evaluate impacts... of choices made about technology use" or "examine how
cultural beliefs, values, and ethical positions affect the development and
use of technologies," as ADST's Applied Technologies category does
word-for-word) make this content load-bearing rather than optional flavour,
so it earns its own section here.

### Every discussion needs a runnable protocol, not just questions

A page that opens with a lecture-shaped explainer and closes with a
numbered list of "Discussion Prompts" is not active learning — it is
reading with extra steps. Every discussion-type page needs an explicit
**"## How we run this"** section giving a teacher an actual classroom
protocol they could execute cold: who moves where, how long, what happens
in what order. Vary the protocol across a course's Discussion folder — do
not run the same shape seven times. A working menu, all used across
MCMPR11's seven Discussion pages with no repeats:

- **Fishbowl** — an inner circle discusses while an outer circle observes
  and tracks something specific, then swaps.
- **Four-corners debate** — students physically commit to a position by
  standing in a labelled corner, build a case in their corner, then argue
  it, with room to visibly change corners afterward.
- **Jigsaw** — small groups each become the expert on one sub-case, then
  remix into new groups to teach each other.
- **Gallery walk** — stations around the room, each a different case or
  question, groups rotate and leave written responses.
- **Structured academic controversy** — pairs argue one assigned side, then
  swap to argue the other, then drop the assigned roles and seek consensus.
- **Chalk talk** — a silent, written-only conversation on chart paper or a
  whiteboard; no one speaks.
- **Talking circle** — everyone speaks in turn, uninterrupted, often with a
  physical object passed to signal whose turn it is; appropriate and
  respectful specifically for Indigenous-content discussions, where it
  reflects a real practice rather than an arbitrary structure choice.

Give real timing and real steps, not just the protocol's name — "run this
as a fishbowl" with no further detail is exactly as unusable as no protocol
at all.

### Multiple peoples in BC, not one people

BC's curricula frequently invite Indigenous content specifically (OCAP®,
First Peoples Principles of Learning, FirstVoices, land-based and
community-based learning), and that content belongs here, grounded and
substantive rather than a token callout — but "multiple peoples" means more
than one thread. A course that is rich on Indigenous content and silent on
everything else has widened the lens only partway. Research REAL, VERIFIABLE
BC history and organizations beyond the Indigenous thread — verified
examples used in MCMPR11, worth knowing as a starting menu (verify current
details yourself before reusing; do not treat these one-line descriptions
as complete or evergreen):

- **Landscapes of Injustice** (University of Victoria) — reconstructing the
  property dispossession records of Japanese Canadians interned during
  WWII, a real database-backed archival project.
- **The Chinese Canadian Museum** (Vancouver, opened 2023) and Chinese
  Head Tax certificate digitization work.
- **The 1914 Komagata Maru incident** and its South Asian/Sikh community
  memorialization.
- **ISSofBC** (Immigrant Services Society of BC) and BC's real, current
  newcomer/settlement-sector language diversity (Punjabi, Cantonese/
  Mandarin, Tagalog, Ukrainian, and others — verify current census/
  settlement-sector data rather than guessing).

Never invent an organization, statistic, or incident — verify every one via
WebSearch/WebFetch before it goes in a published page. A course that ships
a fabricated "fact" to a teacher is a serious failure, worse than a course
that says less.

### Current events in software/technology ethics

For any course with a societal-impact-of-technology competency, real,
citable, CURRENT cases teach the point better than an abstract discussion
of ethics ever does. Beyond the well-worn Volkswagen "defeat device"
scandal (still a strong anchor — use it, but don't rely on it alone), real
cases verified and used in MCMPR11:

- **The Clearview AI investigation** — Canada's federal Privacy
  Commissioner working jointly with BC's, Alberta's, and Quebec's provincial
  commissioners; a genuinely BC-relevant regulatory case with a named BC
  commissioner and a real binding order (get the order's actual language
  right — "best efforts," not an absolute guarantee, is what BC's order
  actually required; overstating it is its own kind of inaccuracy).
- **Te Hiku Media / Papa Reo** (Aotearoa New Zealand) refusing to hand
  Māori-language voice data to a tech company — a strong parallel to any
  BC Indigenous-language-software content already in the course.
- **The CrowdStrike global outage** (July 2024) and its real, documented
  British Columbia impact (YVR flight disruptions, BC health authority
  systems, 911 dispatch).
- The UK Post Office Horizon scandal and the Boeing 737 MAX MCAS crashes
  remain strong, well-documented anchors for software-reliability content
  generally, not BC-specific but worth keeping in the mix.

Fact-check every claim independently before publishing — dates, names,
outcomes, the precise legal force of an order or ruling. Treat this as the
highest-priority thing an adversarial reviewer checks (see below): a course
is not "ready" because it reads well; it is ready because every fact in it
survived an independent check against a primary source.

## Verification workflow for a full BC curriculum-fidelity rebuild

A BC payload that inherits an already-wrong curriculum coding (as MCMPR11
did) is a heavier lift than authoring a brand-new Ontario payload from a
clean official structure, because it needs a REMAP step Ontario payloads
normally don't. The shape that worked, worth reusing:

1. **Research** the live curriculum (above) and write the structured
   capture file.
2. **Generate** the new Curriculum folder with a script (above) — this can
   be done directly, it's mechanical once the data table is right.
3. **Remap** every existing page's old curriculum codes to the new scheme
   with a small script that replaces each affected file's
   `%%curriculum-start%%...%%curriculum-end%%` block wholesale with a
   hand-chosen new code list (not a positional find-and-replace — decide
   per file what it actually teaches). Handle Task/assessed pages by hand,
   with real thought about the coverage-by-assessed-work rule above.
4. **Run the lint gate**, read the coverage line, and patch the remaining
   uncovered codes — this reliably surfaces exactly which new pages you
   still need to write (an uncovered Content item like "pair programming"
   is a direct instruction: go write that page).
5. **Fan out content-authoring agents** by folder (Concepts, Discussions,
   Warm-Ups/Exercises, …), each with: the style contract, the exact
   curriculum codes to use per page (verified against the actual
   `Curriculum/<CODE>.md` files, not memorized), and a note to fact-check
   every real-world claim independently rather than trusting a one-line
   brief.
6. **Fan out class-page-rewrite agents** by unit, each given a complete
   bare-item resolution map (built from the audit script above) saying
   exactly which agenda items to link to which page and which to leave
   deliberately bare.
7. **Run an adversarial review agent** — separate from the authoring
   agents, with its own independent WebFetch/WebSearch fact-checking pass,
   specifically told to re-verify the curriculum wording against the live
   source (not trust the generator's output), to check curriculum-code
   HONESTY (does this page really teach what its code claims?), to
   fact-check every real-world case study independently, and to assess
   whether the course actually delivers on active-involvement / multiple-
   peoples / current-events grounding rather than just claiming to. Give it
   a findings-ordered-by-severity report format, fabricated/wrong facts
   first. This is the pass that catches what a same-agent self-review
   reliably misses — an earlier self-review of this exact payload said
   "ready to ship" and still had a backwards Know-Do-Understand mapping, an
   inflated Big Ideas count, and two broken links, all caught only once an
   independent reviewer checked the live source itself rather than trusting
   the payload's own citations.
8. **Fix, re-lint, and confirm "clean"** before calling it done.

## Known traps specific to BC

- **Do not assume ADST's competency category names generalize to other
  subjects.** Look them up live, every time, for the actual course.
- **Do not group Content into invented categories.** It is a flat list.
  If it feels like it wants sub-headings, that impulse is the trap.
- **Do not invent a topic sentence for a competency group's overall page.**
  Use the Ministry's own short label; disclose the convention once.
- **Do not treat Big Ideas as coded, evaluated expectations.** They are
  framing prose — quote them once, verbatim, outside the coverage system.
- **Get the Big Ideas COUNT right from the live page**, not a cached PDF —
  BC revises these.
- **Get `jurisdiction`/`credit_value` right in the manifest before chasing
  an arc-length "bug"** — a wrong credit value makes a correct arc look
  wrong.
- **A boilerplate competency code copy-pasted onto every Task page is a
  curriculum-honesty bug, not a shortcut** — match the code to what that
  page's stage of work actually is.
- **The WebFetch summarizer may refuse a big verbatim request even though
  BC's Open Government Licence permits it** — chunk the request, or fall
  back to the Ministry's own PDF export.
- **Verify, never invent, any real-world organization, case, or statistic**
  — this applies to Indigenous content, to other-peoples content, and to
  software-ethics case studies equally. An unverifiable claim gets left out,
  not softened into something technically true but misleading.

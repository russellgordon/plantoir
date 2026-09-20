---
name: example-content
description: Build or revise a per-course-code example-content payload (support/example_content/<CODE>) — the ready-made course a teacher can pre-populate. Use whenever adding example content for an Ontario course code.
---

# Building example content for a course code

A payload is a complete, working course a teacher keeps: real pages, a real
semester, real curriculum. **ADA1O is the reference implementation** for
page shape and voice — when in doubt, open it and copy its shape. **For the
ASSESSMENT rules below — the three modes, the per-unit sequence, the hidden
triangulation blocks, `How Marks Work` — the reference is `ICS3U`**, which
was brought to them first; ADA1O predates them and does not conform yet. `support/example_course/EXC2O` is the
older standalone example course; match its depth and warmth, not its
mechanics.

The payload owns the course's ENTIRE structure (the wizard asks no
structure questions when pre-populating), so nothing may ship empty and no
folder should exist without purpose. Machinery lives in
`scripts/setup_course.py` (`install_example_content` and friends) and needs
NO changes for a new course code — a new payload is pure content.

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
- A course revised to satisfy these rules sent a teacher to observe a
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
- **Hand it the primary sources and say where they are** — the live
  curriculum document, the class pages, the expectation texts in
  `Curriculum/`, `lint_payload.py`, `build_site.py`. A reviewer working
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

## Phase 1 — Research the curriculum (verbatim or not at all)

**From the LIVE official government portal, every time** —
`dcp.edu.gov.on.ca` and `edu.gov.on.ca/eng/curriculum/secondary/`.

**This skill is Ontario only.** A British Columbia course code goes to
[`.claude/skills/bc-example-content/SKILL.md`](../bc-example-content/SKILL.md),
which is self-contained and reads `curriculum.gov.bc.ca` instead. BC
payloads use the tool scripts in this folder unmodified — the scripts are
jurisdiction-AWARE (`lint_payload.py` branches on `manifest["jurisdiction"]`
for credit arithmetic) rather than Ontario-only. The GUIDANCE below is
Ontario-only: it assumes Ontario strands, expectation codes, the provincial
achievement chart, and *Growing Success*. Several of its rules are not
actually jurisdiction-bound — the hidden triangulation block, success
criteria on task pages, the per-unit assessment sequence — and a BC payload
would be better for them, but the BC skill does not currently ask for them;
raise it rather than assuming either answer.

Do not work from a saved copy, and do not add one to this repository. A copy held here
does not preserve the curriculum, it manufactures a stale second version of it —
the ministry updates these documents whenever it likes.

Launch a research agent (WebSearch/WebFetch) to capture, from the
Ministry's own published document, for the exact course code:
strand titles; every OVERALL expectation (code + verbatim text); every
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

**A standard secondary credit requires 110–120 hours of scheduled time (1.0 credit), and the arc must
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

**Every Ontario course must show all three kinds of assessment, and two of
them live in the ARC rather than in the `Tasks` folder.** *Growing Success:
Assessment, Evaluation, and Reporting in Ontario Schools* (2010) is the
companion document to every Ontario curriculum, and although it reads as
assessment policy it has strong consequences for course DESIGN: several of
its rules are hard to satisfy honestly unless the course was built with
them in mind. Read it live at
`https://www.edu.gov.on.ca/eng/policyfunding/growSuccess.pdf` when a
decision turns on the wording. **Cite it by chapter and heading**, not by
page — the ministry repaginates, and this skill's own Phase 1 rule about
stale copies applies to policy documents too; the page numbers in
parentheses below are the 2010 first edition and are a convenience, not the
citation. Each chapter is in two halves, `POLICY` then `CONTEXT`, and the
difference matters when you are deciding whether something is required or
merely recommended. The three modes:

- **Assessment *of* learning** is evaluation — judging quality against the
  achievement chart and assigning a mark. It belongs at or near the END of
  a unit, and at the end of the course (the culminating task, then the
  final evaluation). This is what `Tasks` mostly already holds, and it is
  the mode no payload forgets.
- **Assessment *for* learning** is evidence gathered to decide what to
  teach next and to give the student descriptive feedback: diagnostic
  before a unit bites, formative all the way through. Any day.
- **Assessment *as* learning** is the student judging their own work
  against criteria they understand, setting a goal, and acting on it. Any
  day — and it has to be TAUGHT, on the gradual release of responsibility
  GS describes (demonstrate during instruction → guided practice → share
  the responsibility → assess independently; Ch. 4 CONTEXT, p. 35), which
  means it occupies real periods rather than a sentence on a task page.

A payload that ships four units and five summative tasks has written only
the FIRST of these. The other two live in the AGENDAS, which is where a
reader can tell whether they were designed or merely assumed.

**The arc's assessment requirements come straight out of Chapter 4's POLICY
half** (*Assessment for Learning and as Learning*, pp. 28–29), which says
teachers "need to" plan assessment concurrently with instruction, "share
learning goals and success criteria with students at the outset of
learning", "gather information about student learning before, during, and
at or near the end of a period of instruction", "give and receive specific
and timely descriptive feedback", and "help students to develop skills of
peer and self-assessment". **Per unit, that means all of the following, in
this order:**

1. a **diagnostic** near the unit's start — a warm-up, a "what do you
   already think", a low-stakes problem — whose named purpose on the class
   page is finding out where this class is starting from;
2. the unit's **learning goals and success criteria in student language**,
   in the students' hands at launch rather than at hand-in. They live on
   the TASK page (or a unit page), which the class page links to on the day
   the task launches — a class page is a schedule, so the criteria go where
   the work is. GS's practice discussion is worth following on the wording:
   learning goals are written "in language that students can readily
   understand" (Ch. 4 CONTEXT, p. 33), not expectation text lifted from the
   Curriculum folder;
3. **formative work on at least a third of the unit's class pages**, named
   as such on the agenda — an exit ticket, a rehearsal share, a code
   review, a draft read aloud;
4. at least one **feedback checkpoint before the summative**, and at least
   one working period after THAT CHECKPOINT whose stated job is acting on
   the feedback. GS's discussion of descriptive feedback is explicit that
   "multiple opportunities for feedback and follow-up are planned during
   instruction to allow for improvement in learning prior to assessment of
   learning" (Ch. 4 CONTEXT, p. 34) — so a unit that launches a task and
   then collects it, with nothing in between, has no place for the feedback
   to land. This is the assessment reason behind the working-period rule
   above: "a checkpoint with the teacher" and "revision after feedback" are
   not flavour, they are the two periods that make the unit work;
5. at least one **self- or peer-assessment episode** the teacher has
   modelled first — GS treats the modelling as part of the job, not a
   preliminary, so the arc needs a day for each;
6. the **summative task**, at or near the end.

**Evaluation lands on OVERALL expectations, and once is thin.** "For Grades
1 to 12, all curriculum expectations must be accounted for in instruction
and assessment, but evaluation focuses on students' achievement of the
overall expectations" (Ch. 5 POLICY, p. 38) — which is why the coverage
rule in Phase 5 wants every overall reachable through a task. The grading
rule adds a second, less obvious demand: a report card grade "should
reflect the student's most consistent level of achievement, with special
consideration given to more recent evidence" (Ch. 5 POLICY, p. 39).
Consistency and recency mean little for an overall expectation the course
evaluates once, in Unit 1, and never returns to. So **"ideas come back" is
an assessment rule as much as a learning one**: where the course honestly
allows, an overall should be evaluated in more than one unit, and the
culminating task is the natural second look at most of them.

**The four categories are a design instrument, not just a rubric.** GS
lists "help teachers to plan instruction for learning" among the
achievement chart's purposes (Ch. 3 POLICY, p. 16) and requires learning to
be "assessed and evaluated in a balanced manner with respect to the four
categories" — Knowledge and Understanding, Thinking, Communication,
Application (Ch. 3 POLICY, p. 17; repeated in Ch. 4 POLICY, p. 28).
"Balanced" is NOT "equal", and the document says so in the next breath: the
relative importance of each category "may vary" by subject and course, and
should reflect the emphasis the curriculum expectations themselves give it.
So weight the categories the way this course's expectations do — and check
that none is missing altogether. The Application row of every achievement
chart includes transferring knowledge and skills "to new contexts" (see the
sample charts, pp. 21 and 25), so at least one task in the course should
put the learning into a context the class has not practised. A course whose
tasks are all "build the thing we just built together" has thin Application
evidence in it, whatever its rubric claims.

**Four things that must stay out of a mark**, each of which a payload can
get wrong in a single sentence. The first three are flat prohibitions in
GS's policy half; the fourth is hedged, and the hedge is quoted:

- **A peer's judgement, or the student's own.** "The evaluation of student
  learning is the responsibility of the teacher and must not include the
  judgement of the student or of the student's peers" (Ch. 5 POLICY,
  p. 39). Self- and peer-assessment are *for* and *as* learning, full stop;
  no task page may imply a classmate's rating becomes part of anyone's
  mark.
- **A common group mark.** Group projects are allowed "as long as each
  student's work within the group project is evaluated independently and
  assigned an individual mark, as opposed to a common group mark" (Ch. 5
  POLICY, p. 39). Every group task must therefore NAME the
  individually-evaluated thing — the role, the section, the personal build
  log, the recorded two-minute conversation. (Roughly half the payloads
  shipped so far do this; the rest are a fair retrofit.)
- **Ongoing homework.** "Assignments for evaluation must not include
  ongoing homework that students do in order to consolidate their knowledge
  and skills or to prepare for the next class" (Ch. 5 POLICY, p. 39). The
  class pages' "Things to do before our next class" list is practice, and
  the practice itself is never the evaluated thing. It MAY remind a student
  to submit an assignment for evaluation that the class periods were for —
  that is a reminder, not homework being marked. Evaluated work is done
  "whenever possible, under the supervision of a teacher" (same page),
  which is the second assessment reason for giving every substantial task
  real working periods.
- **Learning skills and work habits.** Responsibility, Organization,
  Independent Work, Collaboration, Initiative and Self-regulation are
  evaluated and reported SEPARATELY, as E/G/S/N. GS hedges this one, and
  the hedge is part of the rule: "**To the extent possible, however,** the
  evaluation of learning skills and work habits, apart from any that may be
  included as part of a curriculum expectation in a subject or course,
  should not be considered in the determination of a student's grades"
  (Ch. 2 POLICY, p. 10). The escape hatch is narrow and specific — a
  curriculum expectation that genuinely contains the skill, as health and
  physical education's Living Skills and mathematics' process expectations
  do. It is not a licence to mark participation. Write success criteria
  that describe the WORK, not the worker.

**`How Marks Work` must tell the truth about the credit.** For Grades 9–12:
seventy per cent from evaluation throughout the course, reflecting the most
consistent level with weight given to more recent evidence, and thirty per
cent from a final evaluation at or towards the end that lets a student
"demonstrate comprehensive achievement of the overall expectations for the
course" (Ch. 5 POLICY, p. 41). The `final-evaluation` page the arc already
requires IS that thirty per cent, so it must reach across the whole course
rather than be a fifth unit test. Name the four categories in student
words, say that learning skills are reported separately from the mark, and
say where the evidence comes from — all three kinds.

**This was retrofitted across every payload in August 2026, and the base
rate is the finding worth keeping: every single course had at least one
mark the policy forbids.** "Ensemble and audience skills : 10",
"Seminars 10% — prepared participation", "Professionalism — on time,
prepared, discreet", and — worst, because the class pages said "mark your
own" — TEJ3M's "Measurement and calculation checks : 20" and MCV4U's
"Quizzes and check-ins : 25". None of these looked wrong to the author who
wrote them. Assume the same of yours: the mark page is where a course
quietly grades the worker instead of the work, and it is the first page to
audit rather than the last. ADA1O carried the first of those and no longer
does; it is again safe to copy for VOICE, and its `How Marks Work` is now
a worked example of the two-slice pie as well.

Every payload now states the split, so a missing 70/30 is no longer the
common failure. Two live ones remain: a pie that charts an inventory
instead of the shape (see the mermaid rules in Phase 5), and a mark page
promising a weighting the task arc does not actually deliver.

**Triangulate: observation, conversation, product.** "Evidence of student
achievement for evaluation is collected over time from three different
sources — observations, conversations, and student products" (Ch. 5 POLICY,
p. 39). Products look after themselves: they arrive, they hold still, they
can be marked on a Sunday. The other two are the hardest and slowest
evidence to gather well, they leave no trace unless the teacher
deliberately makes one, and they are therefore the two that quietly vanish
from a real course — leaving a teacher evaluating on a third of the
evidence the policy describes. A payload cannot gather that evidence for
anybody, but it CAN tell the teacher exactly where in each task it is
available, which is what the hidden triangulation block in Phase 5 is for.
Design the arc so those moments exist in the first place: a task whose
every period is silent individual work gives a teacher nothing to watch and
nobody to talk to.

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
`per_section_files`, `hidden`, `expandable`, `curriculum_folder`,
`graded_folders`. This is the whole structure — mirror ADA1O's hidden/expandable choices (Curriculum
and the utility files hidden; content folders expandable; All Classes
visible but not expandable). Layout: `shared/` → course root;
`per_section/` → every sectionN/.

**`graded_folders` names the folders whose work counts for marks** — what
puts the ring on a cell in the Curriculum Coverage map, and what answers
Ontario's ask that every overall expectation be evaluated at least once.
Normally `["Tasks"]`. The linter refuses a payload without it, and refuses
a name that is not one of the course's own folders.

Declare it rather than letting it be inferred. Inference is a SUBSTRING
("does the folder mention tasks?") while the build matches a pooled name
EXACTLY, so a payload whose folder was "Thinking Tasks" — the mathematics
skeleton has one — would silently stop counting under a pool of
`["Tasks"]`, and a silently ungraded map is the failure this whole key
exists to prevent.

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
- Curriculum references: near-the-end-of-page block (only the hidden
  triangulation block below sits after it)
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
- **A task page states its success criteria in student language, before
  the work starts.** A short table of qualities and what each looks like to
  a reader, an audience or a user is the usual shape, but a plain list is
  fine where the page's one demonstrated Obsidian feature is something else
  — the requirement is the criteria, not the table.
  `ADA1O/shared/Tasks/Tableau Story Sequence.md` is the reference: note
  that its criteria sit BELOW its "How to work" steps but are still on the
  page a student opens on launch day, which is what "before the work
  starts" means. They must be writable from the achievement chart without
  quoting it — describe the WORK, never the worker (Phase 2). A task with
  no success criteria cannot support assessment *as* learning, because
  there is nothing for a student to judge their own work against.
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
- **A pie carries the SHAPE of an answer, never an inventory. Chart the
  split that matters and put the members of each part in prose beneath
  it.** Past about four slices a pie stops being a picture and becomes a
  legend with a decoration attached: the reader's eye has nowhere to
  land, and the one comparison the page exists to make is buried among
  nine others it does not care about. If you find yourself needing a
  legend as tall as the chart, the content wanted a table, a list, or a
  sentence.

  ICS3U's `How Marks Work` is the worked example, and it is instructive
  because it broke NO existing rule. Ten slices, every one legible,
  nothing under 3%, title within length — and it still failed, because a
  student opening that page needs one fact (seventy per cent from the
  semester, thirty from the end) and had to reconstruct it by summing
  eight numbers. Redrawn as two slices, with the seven tasks named in a
  paragraph underneath, the same page answers the question in the first
  glance and keeps every detail it had.

  There is a second reason beyond legibility, and it is the one that
  survives a bigger monitor: **per-item percentages are false precision
  whenever the underlying numbers are a professional judgement.** The
  split between six comparable tasks shifts with the class and with the
  year; printing 6% against 5% presents a judgement as arithmetic and
  invites an argument about the wrong thing. Say which piece is the heavy
  one and why, and offer the exact numbers to anyone who asks for them.

  So: keep the two mechanical rules above — they are necessary and they
  are not sufficient. Then ask what single comparison the chart is FOR,
  and whether a reader would see it without counting.
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

**Every task page ends with a hidden triangulation prompt for the
teacher.** Observation and conversation are the two evidence sources a real
course loses first (Phase 2), so every task carries a `%%` comment naming
where in THAT task they are actually available. `%%` is Obsidian's comment
marker, and the vendored Quartz strips it at text level before parsing —
`commentRegex = /%%[\s\S]*?%%/g` in
`quartz/plugins/transformers/ofm.ts`, whose `[\s\S]` is what makes the
MULTI-LINE form safe. Nothing inside the markers is ever published.
`SBI4U/per_section/index.md` is a published page carrying one in exactly
the shape prescribed here, delimiters on their own lines.

**"Task" means a page in `Tasks/`, and that is a technical constraint, not
a style preference.** Both gates decide what counts as assessed work by
FOLDER — `lint_payload.py` tests `"/Tasks/" in path`, and `build_site.py`
looks for "task" in a path component — so evaluated work that lives only in
`Investigations` or `Portfolios` leaves red strand chips on the Curriculum
Coverage map and fails the linter's "never reached by assessed work"
check. If a course's real evaluated work is an investigation, the task page
belongs in `Tasks/` and links to it.

The block goes at the very END of the page, AFTER `%%curriculum-end%%` —
last of all, because the curriculum block above it is PUBLISHED and
student-visible, and this is the only part of the page students never see.
Never put it INSIDE the curriculum markers: `strip_curriculum_blocks()` in
`scripts/setup_course.py` deletes everything between them for a teacher who
declines curriculum pages, so a nested comment vanishes silently. Every task
template (like `ADA1O/shared/Tasks/_DUPLICATE ME.md`) places the triangulation
block after `%%curriculum-end%%` for this reason.

**Plain text only inside the block.** No `[[wikilinks]]` and no
`![[transclusions]]`: the linter and `build_site.py` read the raw markdown
without stripping comments, so a `![[C1.2]]` written here would silently
count as curriculum coverage for an expectation no student page addresses,
and a `[[Page]]` would satisfy the two-hop reachability check for a page
nothing visible reaches. Write bare codes as text.

```
%%
Triangulation — the evidence you will not have unless you go and get it.

OBSERVE — Unit 1, Day 11, the working period on building the images
  Watch for: whether a group tests one image at a time, or stages all five
  and hopes. Visible only while they work; the finished piece can look the
  same either way.
  Going well: someone steps out of the picture, looks, and changes it.
  Stuck: everyone is in the picture and nobody is watching it.
  Record: initials in the margin of your day plan, three columns.

TALK — Unit 1, Day 9, the two-minute conference already on that agenda
  Ask: "Why does your story break at that moment, and not the one before?"
  Then: "What does the picture show us that the words would not?"
  A strong answer names the change the moment carries — that is A2.2 heard
  in conversation, and a still image will not show you it was a choice.
  Record: one line per group, right then.

The product evidence is the performance on Day 15. That one arrives on
its own.
%%
```

Six rules for writing one:

- **Specific to THIS task, naming real days from the arc — check them.**
  The example above is drawn from ADA1O's Tableau Story Sequence, which
  runs Unit 1, Days 8–15; writing "Unit 2, Day 12" because it sounded
  plausible would send a teacher to a different task's rehearsal. Open the
  class pages and read them. Boilerplate repeated across eight tasks fails
  differently but just as badly: a teacher stops reading it at the second
  task.
- **Name what is visible only in the DOING and invisible in the product.**
  That is the whole argument for observing. If no such thing can be named,
  the observation prompt is decoration — and the task itself may be worth
  reopening.
- **Give the conversation two or three ACTUAL questions**, plus what a
  strong answer sounds like. "Talk to each student about their progress"
  is not a prompt, it is the burden the teacher already knows about. And
  check the question is not already printed on the task page — one the
  students have read is a prompt, not a probe.
- **Say how to record it in seconds.** The reason this evidence goes
  missing is time, so a prompt that ignores the recording cost gets
  ignored back.
- **Prefer a slot the arc already has.** Where a class page already
  schedules a conference, a check-in or a half-class share, put the
  conversation THERE rather than inventing a new one. Never point at a day
  of silent individual work, or at a performance or dress run, when the
  teacher is running the room.
- **Tie it to a curriculum code the task already lists, and check the code
  says what you claim.** In the example, A2.2 is "use a variety of
  conventions to develop character and shape the action"; C1.2 — also on
  that task — is about correct terminology and would NOT be evidenced by
  the answer described. This is evidence for the mark, not a warm-up, and
  saying so is what earns the two minutes from a teacher who has none.

Add the same block, with the two headings and blank lines beneath them, to
`Tasks/_DUPLICATE ME.md`, so a teacher's own new task inherits the habit
rather than only the paperwork. No payload carries one yet — this is new
with this section, so a payload you are revising will need them written.

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
   regexes has drifted and that is the bug to fix first. Then READ TWO
   task pages' triangulation blocks, from different units, end to end:
   the linter cannot tell a prompt naming a real day and a real question
   from boilerplate, and boilerplate is the failure mode this block has —
   which only shows up when you compare two of them. Check the days named
   are days that task actually runs on.
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
   the build's own KaTeX with `throwOnError: true`. **The module is not on
   your disk**: `node_modules` lives on the container's own storage and is
   never mirrored out, so reach it inside the container —
   `docker exec <container> ls /tmp/quartz-builds/<CODE>/section1/node_modules/katex`.
   (This said `courses/<CODE>/.merged_output/section1/node_modules/katex`,
   which stopped being true when the build moved to container-internal
   storage and would now send you to a shortcut out of the working folder.)
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

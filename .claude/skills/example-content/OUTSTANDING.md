# Growing Success sweep — where it stands

**34 of the 37 Ontario payloads are committed.** Every one of them is
linter-clean and passes the mechanical checks, so nothing here is broken.
What differs is how far each got through the author → adversarial review →
verified fix cycle, and that difference is the whole point of this file: a
committed payload is not a finished one.

Read this section as the work queue. The second half of the file, below the
rule, is a different thing — cross-payload defects found during the sweep and
deliberately left alone.

## Still to do

- **CGF3M**, **CIA4U** — conformance pass in progress.
- **TEJ4M** — the last payload with no pass at all. Not started.

## Committed, but the fix round did not finish

These carry review findings that were never fully applied. The payload is
clean and shippable; the findings are improvements that stopped mid-round
when the account limits hit. Each is worth picking up as its own piece.

- **SPH3U** — 12 findings. The important one: the D2.5 leg was written on the
  INPUT side only (V, I, t), with no method, apparatus, criteria row or period
  for the output, and the motor the course builds is unloaded, so there is no
  mechanical work to measure. Also two transformer codes on a task with no
  transformer, and the five write-ups' check-in promised twice and scheduled
  nowhere.
- **TGJ2O** — 10 findings, fix round barely started. The important one: the
  rewritten row "Filed while it is news | The recap reaches readers within two
  days" against an arc that publishes six class days after the event — every
  student fails it for obeying the schedule. Also A3.3 and D2.4 carrying the
  whole learning-skills exception with no section, row or period on either
  task page.
- **CHC2D** — two rounds of review. Round two found 17 more, including the
  notebook handed in three classes before students are told to bring it (and
  into the examination), and a "Conduct" criteria row on the culminating task
  while the mark page says conduct is not marked.
- **CHA3U** — reviewed against a moving target (files changed mid-review; the
  reviewer said so and pinned a timestamp). 14 findings including a Document
  Examination OBSERVE whose window ends where the observed behaviour would
  start, and five of eleven OBSERVE prompts being one probe in five costumes.

## Committed, and the review's completeness is UNVERIFIED

- **ICD2O**, **ENG2D**, **AVI1O** — each was independently reviewed and the
  findings were being applied when the sweep stopped. The commit messages say
  "the confirmed findings are applied", and **that claim has not been
  checked**: the reviewers' lists lived in a conversation that has since been
  summarised away, so there is no record on disk to check them against.

  Do not try to recover the old lists. Re-review each payload adversarially
  against its CURRENT state — a fresh review settles the question directly and
  costs less than transcript archaeology, and it is the same standard the rest
  of the sweep is held to.

## Under adversarial review right now

- **MHF4U**, **TEJ2O** — committed self-reviewed only; independent review in
  flight. Findings will need verifying against the files before they are
  applied. Reviewers in this sweep have failed in BOTH directions — one
  under-counted a defect class by a third, another flagged text that was
  correct and whose "fix" would have deleted a true number — so no finding
  goes in on a reviewer's word alone.

## Authored and self-reviewed; NO independent review yet

- **SNC1W** — its own pass plus a sub-agent found 18 defects, all fixed.
  Created `Tasks/Lab Reports.md` for seven investigations whose eleven
  expectations were marked but invisible to the coverage map. Dropped C2.6
  as the one code no investigation asserts.
- **BOH4M** — its own pass found 18. Removed two outright policy breaches: a
  "Team review — each member's account of what the team did well and badly"
  feeding individual marks, and a "Professionalism — on time, prepared,
  discreet" criterion. Found The People Problem was an evaluated task with no
  class working period at all.

## To resume

The two briefs are `gs-conformance-brief.md` (417 lines, 24 failure modes)
and `gs-review-brief.md`, both beside this file. `verify_gs.py` runs the
mechanical checks, including a simulation of the build's own comment
stripping to catch teacher text that would reach students. Both scripts take
a COURSE CODE, not a path — passing a path makes them report a payload that
does not exist, which prints as a clean pass on an empty set.

Commit each payload as it passes, with its own commit and its own pathspec.
The sweep has already had one near miss where a bulk `git add` staged six
payloads with agents still writing into them.

---

# Cross-payload defects found during the sweep, deliberately not fixed

Both are real, both are outside a Growing Success brief, and both need the
live ministry document or a payload-wide sweep. A half-done sweep is worse
than none, so no instance of either was touched.

## Calendar drift in the English payloads

Every English payload runs `class_weekday_step: 1` over 86 classes — September
to mid-January — and every one of them names months outside that window:

| payload | pages naming February–June |
|---|---|
| ENG3U | 26 |
| ENG4U | 24 |
| ENL1W | 20 |
| ENG2D | 15 |

ENG4U's author documented the specifics on its own payload: the independent
study is described as "October to April", its checkpoints are dated
"Mid-February" and "Late March", and `Showing Growth`, `Your First Entry` and
`Portfolios/index` refer to May and June. `How This Class Works` and
`Tasks/index` carry it too.

Not every hit is a defect — a month can appear in a text, a quotation or a
generic reference — so this needs reading per instance rather than a
find-and-replace. The scheduling claims are the ones that mislead.

## Corrupted curriculum text in the English payloads

The skill's Phase 1 rule is verbatim or not at all, and the English family
breaks it three different ways. Measured 2026-08-20. **Read the caveat at the
bottom before quoting any number here** — this was got wrong twice before it
was got right, and the counts are lower bounds rather than totals.

**1. Trailing truncation — the sentence stops mid-phrase.** Thirteen
confirmed:

| Payload | Pages |
|---|---|
| ENG2D | A1.9, B1.4, D3.1 |
| ENG3U | A2.2, B2.1, D4.2 |
| ENG4U | A1.9, A2.2, B1.8, B2.1, C1.5, C2.2, C3.6 |

`ENG4U/C1.5` is the clearest specimen: its entire body is "determine whether
the ideas and information", where the neighbouring `C1.4` runs to a full
paragraph with its examples intact. `ENG2D/A1.9` ends "…a variety of pres-",
broken at a hyphen, which says the text was lifted from a PDF's line wrap
rather than from the web source — and that is probably the cause of the whole
class.

**2. Over-capture — the next subheading is glued onto the end.** `ENG3U/C2.1`
ends "…for different purposes and audiences Voice", where *Voice* is the
heading of the following section. **ENL1W has this pervasively** — at least 16
of its 59 expectation pages, and the true figure is higher because the
detector misses any heading containing a lowercase word ("Online Safety,
Well-Being, and Etiquette"). ENL1W is the 2023 curriculum, whose expectations
carry no bracketed examples, so the "ends with `)`" signal that finds the
problem in the 2007 courses does not exist there. Treat ENL1W's Curriculum
folder as needing a wholesale re-fetch rather than a page-by-page repair.

**3. A stray teacher prompt spliced on.** `ENG4U/C4.1` carries two coaching
questions after its closing parenthesis — "…in which areas are you weak?" —
which are prompts from the source page, not part of the expectation. The
linter's existing check is for content after the `^text` anchor; this sits
BEFORE the anchor, so that check does not catch it. Worth extending.

**There are no LEADING truncations.** A scan for expectation text starting
mid-word came back empty — the pages that look wrong at the front
("automatically understand most words", "regularly proofread", "conduct
research") open with adverbs or with ordinary verbs, and every one is
verbatim. Recorded so nobody re-runs it.

**Caveat on the numbers, and it matters.** Three detectors were written for
this and the first two were wrong in opposite directions. One keyed on a list
of stopwords and missed `C1.5` because it ends on the content word
"information". One keyed on terminal punctuation and over-flagged `ENG3U/D3.1`
and `ENG4U/D3.1`, which genuinely end "…in achieving their purpose" with no
full stop. The counts above survived being checked BY EYE against the source
pages, but they are lower bounds: no mechanical rule separates "ends on a
content word because it was cut" from "ends on a content word because that is
where the expectation ends". The remedy does not depend on the count.

Fixing all three classes means re-fetching the live Ontario English
curriculum — a Phase 1 job, cheap to do on its own, and it should happen
before the English payloads are shown to anyone. Authors have been told not to
cite a truncated code in a triangulation block and none has, but a teacher
following ENG4U's Critical Essay block still opens a page with half a sentence
on it.

## Weighting pies that chart an inventory instead of the 70/30 shape

Found by a cross-payload audit on 2026-08-20, after the EXC2O port. Russell's
instruction was explicit: the mark page's pie is a 70-30 split, and the tasks
in each part are described in prose rather than illustrated as slices.

Six payloads had drifted, all of them charting per-task or per-category
weights:

| Payload | Slices | Status |
|---|---|---|
| ICD2O | 45/20/20/15 | fixed in flight |
| MCR3U | 40/25/20/15 | told in flight |
| MHF4U | 40/25/20/15 | **outstanding** |
| TEJ2O | 45/20/20/15 | **outstanding** |
| TEJ4M | 35/25/15/15/10 | **outstanding** |
| MCMPR11 | 30/12/10/8/15/15/10 | **outstanding**, see below |

The rule now has a mechanical check (`lint_payload.py`): a pie on
`How Marks Work` with anything other than two slices is a hard PROBLEM. It
lived only in prose before, which is why six payloads drifted past it while
every one of them passed the linter.

A second, softer check notes any pie anywhere with more than four slices. That
one is deliberately a NOTE rather than a problem: "past about four" is a
judgement, and a genuine composition — SNC1W's `Where Our Electricity Comes
From`, the skill's own "dry air, by volume" example — can legitimately want
five. It is wrong for a WEIGHTING and fine for a measurement, and no linter
can tell those apart.

**MCMPR11 needs a decision before it is touched.** Its seven-slice pie is the
worst of the six, but it is not an Ontario course code, so the 70/30 rule that
comes from Growing Success Ch. 5 POLICY may simply not apply to it. The
mechanical check will flag it regardless, because the check keys on the page
name rather than on the jurisdiction. Either MCMPR11 gets its own split and an
exemption, or it should not be linted by the Ontario linter at all — do not
quietly rewrite it to 70/30 just to make the check go green.

## What the audit did NOT find

Worth recording, because it was checked properly and the answer was reassuring:
**every payload states the 70/30 split in prose.** An early pass suggested ten
did not, but that was a broken detector — the payloads phrase it "Seventy of
the hundred are earned across the semester" and "**Seventy per cent** is the
semester's work" as often as "seventy per cent", and the pattern only matched
the last of those. Twenty-two payloads state the split without drawing a pie,
which is a consistency gap rather than a conformance failure; the skill
requires the split to be STATED, and the pie is how it is best drawn.

## Coverage DEPTH varies wildly, and the sweep did not level it

Measured 2026-08-20 across all 37 payloads. Every one reaches 100% coverage —
every expectation is addressed somewhere — but the share addressed **exactly
once** runs from 0% to 54% with no principle behind the spread:

| Share addressed once | Payloads |
|---|---|
| 0% | ADA1O, ATC1O, AVI1O, BOH4M, CGC1W, CGF3M, GLC2O, ICS3U, SNC1W, THJ2O |
| 5–20% | CIA4U, TEJ4M, TEJ2O, TGJ2O, TEJ3M, SPH4U |
| 21–35% | ENG2D, ICD2O, ICS4U, ENG4U, CHC2D, SBI3U, MPM2D, ENL1W, ENG3U, MTH1W, MCMPR11, SPH3U, MDM4U |
| 36–45% | CHV2O, CHA3U, SBI4U |
| **46%+** | **MCV4U 49%, SCH3U 50%, SCH4U 52%, MCR3U 54%, MHF4U 54%, SNC2D 54%** |

The linter says "aim for two or more" and treats it as a NOTE, so `clean`
prints either way — which is why this rode through the sweep unnoticed. Ten
payloads met the bar completely; six are above half.

**Course size does not explain it.** SPH3U has the most expectations of any
payload (100) and sits at 28%; SNC1W has 50 and sits at 0%. SCH4U at 52% and
SNC1W at 0% are the same subject family, revised in the same sweep, days
apart.

**Do not fix this by driving the number to zero.** Manufacturing a second
appearance by rewording the first is convergence by synonym — failure mode
already in the conformance brief — and produces a worse payload that scores
better. The question for each thin code is whether a student meets it once in
passing and never again, or whether the arc genuinely returns to it in a
different context and the linter simply cannot see that. The first is a
defect; the second is not.

**SCH4U, SCH3U and MCV4U are already committed** at 52%, 50% and 49%. They
were reviewed and passed, because nobody was looking at this number. They want
a revisit before the payloads are considered done — not a rewrite, a read of
which specific codes are thin.

## Overall expectation pages that say "None"

Found by AVI1O's adversarial reviewer on 2026-08-20, and **re-measured on
2026-08-20 after the first count proved wrong in both directions.** The body
of every OVERALL expectation page is the literal word `None`:

| Payload | Empty overalls | The Ministry document to fetch |
|---|---|---|
| ATC1O | 10 — A1–A4, B1–B3, C1–C3 | The Arts, Grades 9–10 (2010) — **Dance**, not visual art |
| AVI1O | 9 — A1–A3, B1–B3, C1–C3 | The Arts, Grades 9–10 (2010) — Visual Arts |
| CGC1W | 10 — A1, A2, B1, B2, C1, C2, D1, D2, E1, E2 | Exploring Canadian Geography (2024) |
| THJ2O | 11 — A1–A4, B1, B2, C1–C3, D1, D2 | Technological Education, Grades 9–10 (2009) — **Green Industries** |

**40 pages across four payloads.** Two entries from the original list are
already done and must not be redone: **SNC1W** carries real Ministry text on
all ten overalls, and **EXC2O** inherited that through the port. The earlier
table claiming six payloads was counting a defect that two of them no longer
had.

**THJ2O is Green Industries, not Hospitality and Tourism.** The earlier note
in this file said Hospitality, which would have sent a fixer to the wrong
document to copy eleven expectations that look authoritative and are for
another course entirely. Hospitality and Tourism is TFJ. THJ2O's own
`About These Expectations.md` says Green Industries, and it also carries a
warning that the 2009 document was superseded in 2024–25.

**You do not have to go looking for the source.** Every one of these payloads
already names its official URL in its own
`shared/Curriculum/About These Expectations.md`, along with the Ministry PDF
where one exists. Start there rather than searching.

**Checking this yourself: strip the anchor first.** The body of a broken page
is `None ^text`, not `None`. A comparison against the string "None" reports
every page as healthy and the whole defect as fixed — which is exactly what
happened on the first attempt at re-measuring it. Strip `^text`, then compare.

This is the most VISIBLE defect left in the payloads. `Learning Goals.md`
carries a heading reading `## In the Ministry's words` and then transcludes the
overalls — so a student opens that page and is shown the word "None" once per
strand. The Curriculum Coverage heat map's strand headers are empty for the
same reason.

The specific expectations (A1.1, A1.2, …) are fine everywhere — this is the
overalls only. ICS3U is the model of the correct shape: its
`A1. Data Types and Expressions.md` carries "demonstrate the ability to use
different data types, including one-dimensional arrays, in computer programs;"
followed by the `^text` anchor.

**Do not write these from memory.** Phase 1 is verbatim or not at all, and an
overall expectation is exactly the kind of sentence that is easy to paraphrase
convincingly and wrongly.

Cheap to do as one Phase 1 job — four fetches and forty short files — and it
should happen before any payload is shown to anyone. Pair it with the English
truncation work above; both are the same kind of task. Note that
`dcp.edu.gov.on.ca` course pages are long enough that a single fetch of the
whole page comes back truncated; fetch per strand, or use the Ministry PDF.

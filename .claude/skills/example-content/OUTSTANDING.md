# Growing Success sweep — outstanding work when the account limits hit

Every payload below is **linter-clean and passes the mechanical checks**, so
none is broken. Each is at a different point in the author → adversarial
review → verified fix cycle, and the differences matter.

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

## Reviewed; fix round started and did not finish

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

## Authoring interrupted mid-pass

- **SPH4U** — was mid-fix on its own self-review findings. Its independent
  review has since reported (its routing failed and it arrived via the main
  session): B3.3 transcluded on a task that never asks for a derivation, and
  it is the only B3 code on any Tasks page, so the B3 overall rests on it; a
  C1.2 leg written around a "measured speed" the course never measures; and
  two legs given a section and a row but no period.

*(MDM4U finished and was committed in `3191fa98`; its independent review has
since reported and its fix round is running.)*

## Not started (16)

ATC1O · AVI1O · CGC1W · CGF3M · CIA4U · ENG2D · ENG4U · ICD2O · MCR3U ·
MHF4U · MTH1W · SBI4U · SCH4U · SNC2D · TEJ2O · TEJ4M

CGC1W was dispatched and its author died before writing anything — the
payload is untouched, not half-edited.

## To resume

The two briefs are `gs-conformance-brief.md` (417 lines, 24 failure modes)
and `gs-review-brief.md`, both beside this file. `verify_gs.py` runs the
mechanical checks, including a simulation of the build's own comment
stripping to catch teacher text that would reach students.


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

## Overall expectation pages that say "None" — including the example course

Found by AVI1O's adversarial reviewer on 2026-08-20 and confirmed across the
whole tree. **The body of every OVERALL expectation page is the literal word
`None`** in six places:

| Payload | Empty overalls |
|---|---|
| ATC1O | 10 — A1–A4, B1–B3, C1–C3 |
| AVI1O | 9 — A1–A3, B1–B3, C1–C3 |
| CGC1W | 10 — A1, A2, B1, B2, C1, C2, D1, D2, E1, E2 |
| SNC1W | 10 — same shape |
| THJ2O | 11 — A1–A4, B1, B2, C1–C3, D1, D2 |
| **EXC2O** | **10 — inherited from SNC1W by the port** |

This is the most VISIBLE defect left in the payloads. `Learning Goals.md`
carries a heading reading `## In the Ministry's words` and then transcludes the
overalls — so a student opens that page and is shown the word "None" once per
strand. The Curriculum Coverage heat map's strand headers are empty for the
same reason. EXC2O matters most: it is the example course, the one a teacher
meets first and the one the marketing screenshots come from.

The specific expectations (A1.1, A1.2, …) are fine everywhere — this is the
overalls only. ICS3U is the model of the correct shape: its
`A1. Data Types and Expressions.md` carries "demonstrate the ability to use
different data types, including one-dimensional arrays, in computer programs;"
followed by the `^text` anchor.

**Do not write these from memory.** Phase 1 is verbatim or not at all, and an
overall expectation is exactly the kind of sentence that is easy to paraphrase
convincingly and wrongly. Fetch each course's overalls from the live Ontario
curriculum:

- ATC1O, AVI1O — The Arts, Grades 9–10 (2010)
- CGC1W — Canadian Geography, Grade 9 (2022)
- SNC1W — Science, Grade 9 (2022) — then re-port into EXC2O, or copy the ten
  files across, since EXC2O's Curriculum folder is a straight copy
- THJ2O — Hospitality and Tourism, Grade 10

Cheap to do as one Phase 1 job — five fetches and about fifty short files —
and it should happen before any payload is shown to anyone. Pair it with the
English truncation work above; both are the same kind of task.

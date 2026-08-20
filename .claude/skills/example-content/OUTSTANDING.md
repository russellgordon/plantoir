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

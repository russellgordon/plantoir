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
- **CHA3U** — adversarial review completed and confirmed findings applied on
  2026-08-21 (see `reviews/CHA3U-2026-08-21.md`). Fixed calendar drift in
  `Where the Records Live.md`, disabled TOC on single-H2 Curriculum index,
  added standard 2-slice 70/30 Mermaid pie chart to `How Marks Work.md`,
  verified and confirmed distinctness of all 11 task OBSERVE prompts and
  conformance across the 86 class pages, and deepened multi-hit curriculum
  transclusions.

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

## Authored and self-reviewed; NO independent review yet — NONE (all completed)

- **BOH4M** — independent adversarial review completed and confirmed findings applied on 2026-08-21; see `reviews/BOH4M-2026-08-21.md`.
- **SNC1W** — independent adversarial review completed and confirmed findings applied on 2026-08-21; see `reviews/SNC1W-2026-08-21.md`.

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
heading of the following section. **ENL1W** had this pervasively across all 71
expectation pages; on 2026-08-21 all 71 curriculum expectation files were
completely restored verbatim from the official 2023 Ministry PDF (see
`reviews/ENL1W-2026-08-21.md`).

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
| 0% | ADA1O, ATC1O, AVI1O, BOH4M, CGC1W, CGF3M, ENL1W, GLC2O, ICS3U, SNC1W, THJ2O |
| 5–20% | CIA4U, TEJ4M, TEJ2O, TGJ2O, TEJ3M, SPH4U |
| 21–35% | ENG2D, ICD2O, ICS4U, ENG4U, CHC2D, SBI3U, MPM2D, ENG3U, MTH1W, MCMPR11, SPH3U, MDM4U |
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

## Overall expectation pages that say "None" — DONE 2026-08-20

All 40 are fixed. ATC1O (10), AVI1O (9), CGC1W (10) and THJ2O (11) now carry
the Ministry's verbatim wording; SNC1W and EXC2O were already done.

**Keep this section for the sourcing, which was the hard part.** If another
payload ever needs its overalls, this is the route:

- **`dcp.edu.gov.on.ca` course pages cannot be fetched whole.** They are ~6 MB
  Angular pages and every fetch comes back truncated, which is exactly how a
  confident paraphrase gets written by accident. Do not work from one.
- **The expectations are not in the page HTML either** — only the strand
  titles are. The page calls an API for the rest:
  `https://ws.api.dcp.edu.gov.on.ca/content/api/items?system.codename=<code>`.
  Query the codename `<course>___strands___oe_se_pdf` and the response carries
  an official Ministry asset URL: a PDF titled "Overall and Specific
  Expectations — <course>". That is the clean source for any CURRENT course.
- **Older courses are not on that API at all.** THJ2O is a 2009 Grade 10
  broad-based technology course superseded in 2024, so it has no entry, and
  both edu.gov.on.ca paths for the 2009 Technological Education PDF now return
  a soft 404 — an HTML "page not found" served with status 200, which a script
  will happily save as a .pdf. Check `file`, not the status code.
  **THJ2O's eleven therefore came from a school-board mirror of the Ministry
  PDF** (dpcdsb.org), corroborated by its intact Ministry running footer and by
  the page number matching the document's own table of contents. That is weaker
  provenance than the other three and is worth one confirmation against a
  printed copy if one is ever to hand.
- **Parse by the decimal, not by indentation.** An overall is a code with no
  decimal (`A1.`), a specific is a code with one (`A1.1`). Indentation is
  inconsistent between pages of the same document — CGC1W's E2 heading is
  indented where the other nine are flush left, and an indentation rule silently
  dropped it while reporting nine of ten as a success.
- **Two documents, two shapes.** In the 2010 Arts and 2024 Geography documents
  the overall carries its strand name ("A1. The Creative Process: apply the
  creative process to…"). In the 2009 Technological Education document it does
  not — the overall is a bare sentence, and the names on the payload's pages
  come from the SPECIFIC expectation subheadings. A parser written for one
  returns zero rows on the other.
- **Assert the strand name from the payload's own filename before writing.**
  ATC1O is Dance and AVI1O is Visual Arts; their A1 strands share the name "The
  Creative Process" and share no text. Dropping the dance wording into the art
  course would read perfectly and be wrong, and the filename check is what makes
  that impossible rather than merely unlikely.


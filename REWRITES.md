# Picking the Growing Success sweep back up

Written 2026-08-20, for a session resuming **Wednesday 26 August** or later.
Branch `bc-curriculum`, tree clean, HEAD `27479b23`.

**Read this file first, then
[`.claude/skills/example-content/OUTSTANDING.md`](.claude/skills/example-content/OUTSTANDING.md),
then whichever file in
[`.claude/skills/example-content/reviews/`](.claude/skills/example-content/reviews/README.md)
matches the payload you are picking up.** Nothing below is broken. Every one
of the 37 Ontario payloads is committed, linter-clean and passing the
mechanical checks. What follows is improvement, not repair.

## Where the sweep got to

- **37 of 37 payloads have had a Growing Success conformance pass.** (The
  folder holds 38 codes; MCMPR11 is BC work on this branch and is outside the
  sweep. EXC2O, the example course, carries SNC1W's revision.)
- **Nine were independently reviewed** with their findings applied and
  recorded: ICD2O, MHF4U, TEJ2O, CIA4U, ENG2D, AVI1O, plus CGF3M, TEJ4M and
  SNC2D whose passes ran their own adversarial rounds.
- **The "None" overall-expectation defect is gone from the whole tree** — 40
  pages across ATC1O, AVI1O, CGC1W and THJ2O.
- Real policy breaches removed: participation marks inside the seventy per
  cent in CIA4U, CGF3M and TEJ4M; peer judgement folded into a mark; four
  folder-rule coverage-map lies; several criteria rows no student could earn
  by obeying the course's own schedule.

## What is outstanding, most valuable first

### 1. ENG4U carries the same PDF-scrape damage ENG2D had

Eight ENG2D curriculum pages held Ministry text truncated mid-clause or
polluted with headings from the next page — `A1.9` ended on the hyphen of a
line break, and `B1`, an OVERALL expectation and the first thing a student
meets on `Learning Goals`, stopped at "a variety of literary, informational,".
Fixed in `8a2ce0f8`. **ENG2D's reviewer reports ENG4U has the identical
defect, and that ENG3U is clean.** The route is proven and written up below;
this is the cheapest high-value item left.

### 2. Four payloads with fix rounds that were recorded and never finished

`OUTSTANDING.md` describes each. Roughly 53 findings between them, none
applied:

- **SPH3U** — 12 findings. The important one: the D2.5 leg is written on the
  INPUT side only (V, I, t), with no method, apparatus, criteria row or period
  for the output, and the motor the course builds is unloaded, so there is no
  mechanical work to measure.
- **TGJ2O** — 10 findings, barely started. A criteria row every student fails
  by obeying the schedule: "Filed while it is news | The recap reaches readers
  within two days", against an arc that publishes six class days after the
  event.
- **CHC2D** — 17 from a second review round, including a notebook handed in
  three classes before students are told to bring it.
- **CHA3U** — adversarial review completed and confirmed findings applied on
  2026-08-21 (see `reviews/CHA3U-2026-08-21.md`). Fixed calendar drift in
  `Where the Records Live.md`, disabled TOC on single-H2 Curriculum index,
  added standard 2-slice 70/30 Mermaid pie chart to `How Marks Work.md`,
  verified and confirmed distinctness of all 11 task OBSERVE prompts and
  conformance across the 86 class pages, and deepened multi-hit curriculum
  transclusions.

Prefer a **fresh adversarial review** over hunting the old lists: a review
against the current state settles what is still true and costs less than
archaeology. That is what was done for ICD2O, ENG2D and AVI1O, and it worked.

### 3. Payloads never independently reviewed — NONE (all completed)

**BOH4M**'s independent adversarial review was completed and confirmed findings applied on 2026-08-21; see `reviews/BOH4M-2026-08-21.md`. (SNC1W was completed on 2026-08-21; see `reviews/SNC1W-2026-08-21.md`.) All 37 Ontario payloads have now had their independent adversarial reviews and conformance passes completed.

### 4. Deferred items, each named in its review file

- **CIA4U** — Unit 4 Day 16 asks thirty students for twelve-minute
  culminating presentations in one 75-minute period. An overrun of nearly
  five, pre-existing, needs an arc decision.
- **TEJ2O** — B2.1 requires soldering and nothing in the payload solders.
- **ENG2D** — D3.4 has no period free anywhere in its task.
- **AVI1O** — finding 14; closing it is a restructure, not a policy fix.

## How to work, and the traps that cost real time

**The gates take a COURSE CODE, not a path.** Run from the repo root:

```
python3 .claude/skills/example-content/lint_payload.py <CODE>
python3 .claude/skills/example-content/verify_gs.py  <CODE>
```

Passing a path makes them report a payload that does not exist, which prints
as a clean pass on an empty set. Six known-bad payloads were once declared
clean this way.

**Commit each payload as it passes, with its own pathspec.** Agents work in a
shared tree; a bulk `git add` once staged six payloads with agents still
writing into three of them.

**Ask every fix round to review its own work adversarially.** This was the
single most valuable habit of the night. TEJ2O's fixer found sixteen further
defects and most were its own, including two that reintroduced the very
problems it had just fixed.

But scope the brief and time-box it. CIA4U's first delegated refutation ran 43
tool calls on an open-ended "find what is wrong" and returned NOTHING; the
parent then reported twenty-two findings from it that did not exist. The same
work, scoped to six yes/no claims about the final state, time-boxed, and told
that a short report which arrives beats a thorough one that does not, came back
in three minutes on nine calls — and found a real defect two earlier passes had
missed.

### Four traps, all of which produced a plausible wrong answer rather than an error

1. **A line-wrapped phrase returns nothing to `grep`.** This happened four
   times in one session. Once it nearly discarded a true finding; once it
   nearly let a real contradiction through as "already fixed". **Flatten
   whitespace before searching**, always:
   `re.sub(r"\s+", " ", text)`.
2. **Case matters.** `grep 'log it'` missed `Log it` and produced a false
   accusation that an agent had left work undone.
3. **Class-page filenames contain spaces and commas.** `grep -rl … | xargs
   grep …` splits on whitespace and silently produces nonsense. Loop over
   files instead.
4. **`^text` is part of the body.** A page whose body is the literal word
   `None` reads as `None ^text`, so a comparison against `"None"` matches
   nothing and reports the whole defect as fixed. Strip the anchor first.

### Getting verbatim Ministry text

Phase 1 is verbatim or not at all, and an expectation is exactly the kind of
sentence that paraphrases convincingly and wrongly.

- **`dcp.edu.gov.on.ca` course pages cannot be fetched whole** — 6 MB Angular
  pages, always truncated. The expectations are not in the page HTML either,
  only the strand titles.
- **Use the content API.** Query the codename
  `<course>___strands___oe_se_pdf` at
  `https://ws.api.dcp.edu.gov.on.ca/content/api/items?system.codename=…` and
  the response carries an official Ministry PDF of exactly the overall and
  specific expectations. This works for any CURRENT course. It does not work
  for the English courses, which predate that format — their PDFs are still on
  `edu.gov.on.ca` (`english910currb.pdf`, `english1112currb.pdf`).
- **`pdftotext -raw`, not `-layout`, for two-column documents.** `-layout`
  preserves the columns spatially, so flattening interleaves them and produces
  sentences that read almost plausibly. ENG2D's A1.9 came out as "a variety of
  presincreasingly complex texts, by making connecentation strategies used in
  oral texts" — half real curriculum text, not obviously garbage at a glance.
- **Parse by the decimal, not by indentation.** An overall is a code with no
  decimal (`A1.`), a specific has one (`A1.1`). Indentation is inconsistent
  between pages of the same document, and an indentation rule silently dropped
  CGC1W's E2 while reporting nine of ten as a success.
- **Assert the strand name from the payload's own filename before writing.**
  ATC1O is Dance and AVI1O is Visual Arts; their A1 strands share the name
  "The Creative Process" and share no text. Dropping the dance wording into
  the art course would read perfectly and be wrong. The filename check makes
  that impossible rather than merely unlikely — and AVI1O's re-review
  confirmed afterwards that it had not happened.
- **A soft 404 is served with status 200.** Both `edu.gov.on.ca` paths for the
  2009 Technological Education PDF return an HTML error page that `curl` will
  save as a `.pdf` without complaint. Check `file`, not the status code.

### One sourcing caveat to settle if you can

**THJ2O's eleven overall expectations came from a school-board mirror**, not
from an official Ministry URL. It is a 2009 Grade 10 course superseded in
2024, so it is absent from the current curriculum API and its Ministry PDF is
no longer served. The text is corroborated by the intact Ministry running
footer and by the page number matching the document's own table of contents,
but that is weaker provenance than the other three payloads. Worth one check
against a printed copy if one is ever to hand.

## Two things about agents that are worth knowing before you dispatch any

**A review agent can die silently.** It happened twice: CIA4U's conformance
pass launched an adversarial reviewer that never returned, and AVI1O's first
one stalled after twenty minutes with no report. In both cases the parent
carried on and the findings were nearly lost. This is why every review now
writes to `reviews/<CODE>-<date>.md` **as it goes** rather than reporting at
the end.

**An agent reported a review that had not happened.** AVI1O's fixer described
findings from a briefed reviewer that had returned nothing; the nine fixes it
made were real and verified, but the attribution was invented. It corrected
itself, unprompted, once the real reports arrived, and the mis-attribution is
written into the review file rather than removed. Treat an agent's summary as
a claim to check, not a result — headline claims in this sweep were verified
against the files before acting, and that caught several that did not hold.

## The one thing that was lost, and why the reviews folder exists

ICD2O, ENG2D and AVI1O were each reviewed earlier in the sweep, the fix rounds
started, and the conversation holding the findings was summarised away. Their
commit messages claimed the confirmed findings were applied and nothing
survived to check that against, so all three had to be reviewed again from
scratch — the expensive half of the work, done twice.

A review cannot be re-derived from the files, and it records what was
DELIBERATELY not fixed, which no diff shows. So it gets written down before it
is acted on, rejected findings included with their reasons: a reviewer being
wrong is evidence about the trap, and the next reviewer walks into it
otherwise.

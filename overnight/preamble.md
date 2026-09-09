# You are one issue in an overnight batch

This is an unattended session. Nobody is watching, nobody can answer a
question, and the terminal will not come back to you. Read that as a
constraint on what you may decide, not as licence to guess.

You have ONE session for ONE issue. Another 17 sessions run before and after
you, each on its own branch off `dev`. Work only on the issue described below
the line at the bottom of this brief.

## Read first

`CLAUDE.md` at the repository root is the rulebook and it overrides your
defaults. Rules 3, 4, 5, 9, 10 and 11 all apply to you. Read it before
planning. Read `MAC-HANDOFF.md` around the lines your brief cites, because
that is where the reasoning lives.

## Your branch is already made

The driver has put you on `issue/<slug>`, branched from an up-to-date `dev`.
Do not create another branch, do not switch branches, and **do not merge
anything into `dev`** — the driver merges after it has run the test suite
itself. Committing and pushing your own branch IS yours: do it as you go.

End every commit message with:

```
Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
```

## The order of work (CLAUDE.md rule 11)

1. **Plan.** Read the code the brief points at and confirm the defect is real
   before designing anything. If the code does not match the brief, the CODE
   wins — say so in your write-up and adjust.
2. **Have Fable review the plan.** Use the Agent tool with
   `model: "fable"` and an adversarial brief: tell it to find where the plan is
   wrong, incomplete, or creates a new problem, and tell it explicitly that
   "nothing to act on" is an acceptable answer. A reviewer told to find
   something will invent something.
3. **Implement.**
4. **Have Fable review the implementation.** Same adversarial framing.
5. **Fix what survives checking, then have Fable review the fixes.**

That is three reviews, which is the minimum rule 11 asks for. **Verify what a
review claims rather than acting on it** — check the file, run the test. A
reviewer is wrong often enough to matter. When it is right about something you
decided, change the decision and say so plainly.

## Tests

Run the mac unit suite yourself before you finish:

```bash
cd mac-app
xcodegen generate     # only if files were added or removed
xcodebuild -project Plantoir.xcodeproj -scheme Plantoir -configuration Debug \
  test -only-testing:QuartzTeachersTests
```

Report the true result. If tests fail and you cannot fix them, say so and stop
— do not weaken an assertion to get green. The driver runs this suite again
independently and will refuse to merge if it is red, so a false claim of green
costs the batch nothing but costs you the merge.

A behaviour that a test can pin gets a test. A new contract case is run by
deserialising `contracts/*.json`, never by retyping its strings.

## Rebuild, and leave the app quit (rule 10)

If any Swift changed, finish with a plain build after the last test run,
because `xcodebuild test` leaves a test host behind:

```bash
cd mac-app
xcodebuild -project Plantoir.xcodeproj -scheme Plantoir -configuration Debug build
```

Do **not** launch the app. Do not drive the GUI at all in this batch: it steals
focus, and there is nobody at the machine to put it back.

## Write-ups are part of the work, not a follow-up

- **`GUI-IMPROVEMENTS.md`** gets a row for anything a teacher can see, with a
  "Notes for Windows port" cell that says something usable. Never leave it
  empty; "shared Python, nothing to mirror" is fine when true.
- **`WINDOWS-HANDOFF.md`** gets a section for anything architectural, AND an
  item in its numbered "What is still genuinely outstanding" list.
- **`MAC-HANDOFF.md`**: mark the entry your issue came from `✅ DONE <date>`
  **in place** — struck through, not deleted. If your issue came from the
  "Contract cases waiting on the mac" section, remove the waiting line and mark
  the matching ledger entry. That file's own history is the point.
- **The activity trail** (rule 5): a new or changed teacher-visible behaviour
  names its event in `ActivityTrail.Event` and in
  `contracts/shared-rules.json` → `activityTrail.mustRecord`.
- **Documentation pass, last (rule 11).** Grep for the thing you changed rather
  than trusting memory — a behaviour is usually written down in more places
  than the one you edited, and a stale copy is worse than none because it gets
  believed. Start with `documentation/`, which nothing in the daily rhythm
  points at. Do NOT edit historical records: `GUI-IMPROVEMENTS.md` rows and
  completed `TODO.md` entries are append-only.

Say what you measured, not just what you decided, and record what you
REJECTED and why.

## You MAY write new teacher-facing wording

Russell granted this for the whole batch on 2026-09-06, so do not stop and
propose a sentence you need in order to finish. Three conditions:

1. **It goes in `contracts/`**, so both platforms share one sentence rather
   than inventing two. Name it from the Swift; never type the same sentence in
   two places. If you are about to put one of these sentences into a document
   or a test, name it instead.
2. **It follows the voice already there.** Plain words, no machinery (rule 1):
   no "toolchain", "script", "Docker", "container", no model names or GPU talk.
   Read the sentences around it and match them — the product has a voice and it
   is not yours.
3. **You list every new or changed teacher-visible sentence in your final
   message**, verbatim and together, under a heading he can find. Wording is
   cheap to revise and expensive to discover months later; the list is what
   makes revising it possible in the morning.

This permission covers sentences the work NEEDS. It is not licence to reword
things you happen to walk past.

## When the issue is a DECISION, not a defect

Some briefs say `Kind: decide and propose`. For those, the deliverable is a
written recommendation with the options and the reasoning, plus the contract
case or handoff entry that makes it actionable — **not** a guessed product
behaviour shipped unilaterally at 3am. Implement only the part that is
uncontroversially mechanical, propose the rest, and be explicit about which is
which. Inventing product behaviour nobody agreed to is the one failure that is
expensive to undo.

## If the work turns out not to be needed

Say so, with the evidence, and mark the handoff entry accordingly. "This was
already done, here is the commit" is a good outcome. Do not manufacture a
change to justify the session.

## Do not

- Touch `overnight/` — it is the batch's own scaffolding.
- Work on any issue but yours, or "tidy up" code another issue owns.
- Run `colima stop` (rule 7), or `git push --force` anything.
- Merge to `dev`, tag, publish, or deploy anything.

## Finish with a status line

The very last line of your final message must be exactly one of these, with a
short reason after the dash:

```
BATCH-RESULT: DONE — <what landed, in one line>
BATCH-RESULT: NO-CHANGE-NEEDED — <what you verified instead>
BATCH-RESULT: PROPOSED — <what you wrote up for a human to decide>
BATCH-RESULT: BLOCKED — <what stopped you>
```

The driver reads that line. Nothing else in your output is parsed.

---

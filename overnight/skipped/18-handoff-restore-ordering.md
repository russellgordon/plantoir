> **NOT IN THE BATCH.** Russell decided on 2026-09-06, before the run, to
> leave `MAC-HANDOFF.md`'s ordering alone: a large mechanical edit to a
> 4,586-line file with no test behind it, made unattended, risks losing the
> only record of what Windows has asked for. The two structural faults stay,
> and the mitigation is that this file records them so the next reader knows
> the section is NOT in newest-first order and must be read to the end.
>
> The brief is kept for whenever it is done deliberately, with somebody
> watching.

# MAC-HANDOFF.md's own ordering rules have broken, which is why work gets missed

Rank: 18 of 18. Housekeeping, and the structural cause of the other 17 being
found late.
Kind: housekeeping
Gate: unit

## Why this matters
This file's design rests on one assumption, stated in CLAUDE.md rule 4: it is
read TOP-DOWN and abandoned partway, so the newest and most important work must
be at the top. Two things have broken that, and both were found by an audit
whose whole finding was "the list people are working from covers about a third
of what the file contains."

## Fault 1 — the ordering note is in the middle of the section
The instruction "new items go at the TOP of this section" sits roughly 570
lines INTO "Open — what the mac still owes", not at its head. Below that note
sit seven items dated 2026-09-06, while items from 2026-08-25 sit above it. So
the rule has already been broken, and a reader who stops at the note has
skipped the newest work rather than seen it.

## Fault 2 — six DONE entries were never moved to the ledger
Six entries inside the Open section carry `✅ DONE` but are still in Open,
against the section's own stated rule that finished items move to
"Done — the ledger". They pad the section a reader is trying to get through.

## What done looks like
- The ordering note moved to the head of the section where it can be obeyed.
- The section actually ordered the way the note says — newest first. **Move
  entries, do not rewrite them**: the wording is Windows' and carries their
  reasoning.
- The six done entries moved to the ledger, intact, still marked done.
- A short note at the head of the section saying when it was last put in order,
  so the next drift is visible.
- If you find the same faults in `WINDOWS-HANDOFF.md`'s numbered list, say so
  — but fix only `MAC-HANDOFF.md` here; the other file is Windows' to keep.

## Caution
This is a large mechanical edit to a 4,500-line document that is the mac's only
record of what Windows has asked for. **Do not lose content.** Before you
finish, compare the entry count and the total word count before and after, and
state both in your commit message. If they do not reconcile, stop and report
`BATCH-RESULT: BLOCKED` rather than pushing a file you cannot account for.

This session changes documentation only. Do not touch code.

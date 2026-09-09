# A Course Settings tip sentence lives in neither contract

Rank: 14 of 18.
Kind: implement
Gate: unit

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes", inside the
exclusions/protection entry. Windows flagged it as the mac's call.

## The problem
Course Settings shows a tip sentence — search the Swift for "added to your site
automatically" — that a teacher reads, and it appears in no contract file
(`grep -r 'added to your site automatically' contracts/` comes back empty).
CLAUDE.md rule 2 is explicit: a sentence a teacher reads belongs in
`contracts/`, so the other platform runs the identical case rather than
inventing its own wording.

## What done looks like
- The sentence named in the contract and the Swift referring to the named
  constant, in whatever way this codebase already does it — **find the existing
  pattern and follow it** rather than inventing a new one. `AssistWording` is
  the model for assistant text; Course Settings text may have its own home.
- A mac test that reads the contract.
- `WINDOWS-HANDOFF.md` told that this sentence now exists for them to show,
  with a numbered list item — it is new work for them, not a freebie.

## While you are there
Check whether OTHER teacher-visible sentences in Course Settings are missing
from the contract too. One uncontracted sentence is rarely alone. List what you
find; fix what is clearly in scope; propose the rest rather than ballooning
this session.

## Caution
Do not change the wording while moving it. A teacher-visible sentence changing
is a product decision and belongs in a `GUI-IMPROVEMENTS.md` row of its own.

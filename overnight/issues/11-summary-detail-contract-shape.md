# The summary/detail split still has no contract shape, 19 days after it was proposed

Rank: 11 of 18.
Kind: implement
Gate: unit

## This is a pin, not a request — the mac already passes it
The handoff entry says so in its first line, and it changes the job: the
BEHAVIOUR exists on the mac already. What is missing is a shared case list, so
the two apps cannot silently drift on it again — which is exactly how they came
to differ in the first place.

Windows also wrote: "the Windows tests will be rewritten against whatever
lands." **So the shape is yours to choose and you do not need to ask.** Choose
it, justify it, add it, and move on.

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes" — an entry dated
2026-08-18 asking the mac to choose a shape and add a key. Nothing in
`contracts/` answers it today.

## What is being asked
Windows asked for a contract key describing how an answer is split between a
short summary and the detail behind it — what the teacher sees first and what
they see on asking for more. The mac never chose a shape, so Windows has been
unable to test against one, and the two apps may already differ.

Read the entry in full before planning; it is 19 days old and some of it may
have been overtaken by the assistant work since. **Check whether the mac
already does this in code** — if the behaviour exists and only the contract is
missing, the job is to describe what is there, which is much cheaper than
designing something new.

## What done looks like
- A new top-level key in `assist-cases.json` carrying, for each of the 13 tools
  the local model is shown, the sentence a TEACHER reads against the longer
  answer the model gets. The wordings to pin are in the awareness entry below
  the one you are working from — find it rather than inventing them.
- **Verify the generator preserves your new key** before trusting it. Read
  `AssistContract.swift` and confirm an authored top-level key survives
  `--write-contracts`. Windows explicitly could not check this, and rejected
  proposing under `scenarios` because "a case the generator might silently eat
  is worse than no case, because the next person reads a green suite as proof."
  If your key would be eaten, that is the finding, and fixing the generator is
  part of this issue.
- A mac test that deserialises it.
- If you propose a shape that Windows must now implement, it goes in
  `WINDOWS-HANDOFF.md` AND in its numbered outstanding list, per rule 3. A
  proposal nobody is told about is not a handoff.

## Caution
Do not invent a wording a teacher reads. If the shape needs new sentences,
those belong in `AssistWording` and are a product decision — propose, do not
ship.

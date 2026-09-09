# `deploy` has no `--non-interactive`, so a scheduled deploy can reach a prompt nobody answers

Rank: 5 of 18. A shared defect affecting both platforms.
Kind: implement the unambiguous, propose the rest
Gate: unit (see note on verify.sh below)

## Russell decided this on 2026-09-06, before the batch ran
**Implement only the prompts whose right answer is unambiguous from the code.
Propose the rest.** Nothing gets guessed. Where a prompt's answer is a product
decision — anything that changes what students see, or that picks between two
defensible behaviours — write it up rather than choosing.

The deliverable therefore has two halves and you must label them plainly: what
you implemented and why it was safe, and what you left for him and why it was
not. A session that implements everything has ignored an instruction.

## Where it came from
`MAC-HANDOFF.md`, "Open — what the mac still owes" (search for
"non-interactive"). Raised by Windows.

## The problem
`scripts/deploy.py` has no non-interactive flag. A scheduled deploy — one that
runs with nobody at the machine, which is the entire point of scheduling — can
reach a prompt that will never be answered, and hang. Both platforms drive the
same Python, so this is shared, not a mac quirk.

## What to do
1. Read `scripts/deploy.py` and find every path that can prompt. Enumerate
   them; that list is the actual deliverable even if nothing else lands.
2. Decide, and write down, what each prompt should do when the flag is passed:
   refuse with a clear message, take a safe default, or be unreachable by
   construction. "Refuse loudly" is usually righter than "assume yes" for
   anything that publishes to students.
3. The contract change goes in `contracts/app-rules.json` → `deployArguments`,
   which is what both apps assert about how the launcher is called.
4. Implement the flag if the shape is unambiguous after step 2. If any prompt's
   right answer is a product decision, propose that one and implement the rest,
   saying explicitly which is which.

## Gate note
This touches `scripts/`, whose real gate is `./verify.sh` — which needs a TTY,
Docker and Colima, takes a long time, and builds an image. **Do not run it in
this session.** Run the mac unit suite, and write in your handoff entry that
`verify.sh` has not been run against this change and must be before it is
trusted. Say so plainly rather than implying coverage you do not have.

## Caution
A toolchain edit does not reach a working folder until it travels through the
app bundle — see CLAUDE.md "Editing the toolchain: two traps that cost real
time". Rebuild the app so the bundled copy is current.

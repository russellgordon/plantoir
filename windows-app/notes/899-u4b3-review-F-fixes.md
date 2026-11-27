# #899 U4b3, fourth fix round: review F (2026-11-26, night)

Branch `issue/899-u4b3-linked-class-page-moves-its-link`, from 57afa8408. `origin/dev` merged in before proving and again before handing back: nothing new either time (`git log HEAD..origin/dev` empty).

## For PROGRESS

- Review F's MEDIUM, for relinks: recovery of a killed step removes a relink's just-made link only when the folder reads as a point INSIDE that relink's swap. Two and three chained relinks killed at every stop point the door has, going forward, Undo and Redo, lose no link (61 kills, 0 lost; 20 of them lost a link at 57afa8408).
- **Counter-example found, as the brief said to stop for:** a plain link move (`linkSha`) chained to a relink in one step still loses a link at 8 of its 40 kills under the rule as briefed. Details and a scratch-proven extension under "For the director". Not built.
- Review F's three lows: done (see "Lows").

## Follow-up: the director's ruling (adopted, 2026-11-26, night)

The director ruled to adopt the extension proposed under "For the director" below, which is now built. Where this section and the older text below disagree, this section is true.

- **Rule as built.** Every link move of the step is read in the work's swap order. A plain link move (`linkSha`, the same text at both sides) counts like a relink as a before/after constraint: it must hold its end text when it is before the candidate, and its start text when it is after. It is never itself the one in flight, because its swap is one rename. Only a relink (two texts, always different, `opKinds.move`) can pass. The changes are in Swift `removeTheLinksJustMade` and `isTheOneInFlight`, and in the Python `remove_the_links_just_made`.
- **Test.** The test is now `UndoRelinkTests.testChainedLinkMovesKilledAtEveryStopPointLoseNoLink`, and it runs all four shapes (`ChainShape.allCases`): 101 kills, all passed. There are 61 relink kills, plus 20 for each move shape (an apply: afterBegin, two swaps, both halves of the one relink, beforeApplied; an Undo or a Redo: 7).
- **Must-fail on 113b1c77f's rule** (HEAD's `UndoRecovery.swift` put back, then the built file copied back from the scratchpad). 9 move-chained kills were RED:
  - `aMoveThenARelinkIntoItsPlace`: apply at `afterBegin` and `beforeSwap(0)`; undo at `beforeUndone`; redo at `afterRedoing` and `beforeSwap(0)`;
  - `aRelinkThenAMoveIntoItsPlace`: apply at `beforeApplied`; undo at `afterUndoing` and `beforeSwap(0)`; redo at `beforeRedone`.

  The earlier run of the same rule showed 8: `aMoveThenARelinkIntoItsPlace-apply-beforeSwap(0)` passed there. That one difference between two runs of one rule is not explained. The folder at that point reads the same as at `afterBegin`.
- **Python.** `test_chained_link_moves_killed_at_every_point_lose_no_link` replaces the relinks-only test and adds both move shapes: 54 model kills. With the old model rule it fails 5 move-shape subtests. 41 tests OK.
- **Contract.** One new `recoveryCases` row, `withARelink: thenAMove` (call `relinkThenMoveALinkIntoItsPlace`, files read on Day 4 to Day 6), step at `beforeApplied`: done, files after. The Mac replay now has 85 rows.
  - The row fails with the old rule in both the Swift replay and the Python model.
  - It is held for Windows under `Reason899W8RelinkedLink`, its name matched byte for byte, once.
  - `recoveryCasesHow` says what `thenAMove` is.
- **Sentences.** `undo.rule.recovery`, the `Reason899W8RelinkedLink` sentence and the code comment now say "every link move before/after it" and give a plain move's part. The test comment says what the test proves.
- **Why a swap has no kill test.** The door refuses a swap of two links (Day 4's relinked into Day 5 and Day 5's into Day 4) before anything changes, because a relink never renames over an occupied place. No stop point inside it can be reached, so `testTwoLinksSwappedInOneStepAreRefusedWithNothingChanged` pins the refusal instead.
- **For documentation 12, as now built.** A relink passes when both of its links stand, every link move before it (plain ones included) holds its end text at its end side, and every link move after it holds its start text at its start side. Remove the just-made link of the LAST relink that passes, or nothing. A plain link move is a constraint only.
- **Runs.** `UndoRelinkTests` (16), `UndoJournalContractTests`, `UndoMakeRoomLinkedPageTests`, `UndoHandedOverPlaceTests` and `JournaledStepTests`: 131 tests, 0 failures, through xlock.sh. `origin/dev` was merged in before handing back, with nothing new.

## The rule as built (Swift `UndoRecovery.removeTheLinksJustMade` and `isTheOneInFlight`; Python `remove_the_links_just_made`)

- The relinking ops are read in the work's own swap order: index order for an apply or a Redo, reversed for an Undo.
- A relink passes when:
  - both of its links stand, each holding its own side's text;
  - every relink BEFORE it holds its end text at its end side (`to` going forward, `from` for an Undo);
  - every relink AFTER it holds its start text at its start side (`from` going forward, `to` for an Undo).
- Of the relinks that pass, the LAST one's just-made link (`to` going forward, `from` for an Undo) is removed, once re-read holding that side's text. When none passes, nothing is removed.
- No per-op journal lines (the director's decision).
- Plain link moves are not read by the rule. That is where the counter-example comes from.

## Tests

- `UndoRelinkTests.testChainedRelinksKilledAtEveryStopPointLoseNoLink` replaces `testTwoChainedRelinksKilledAtAnyMomentLoseNoLink`. It is one table over the shapes, the works (apply, Undo, Redo) and every stop point of `UndoKillPoint` except recovery's own `afterRecoveryTidied`: `afterBegin`, `afterTheCheck`, each `beforeSwap(n)`, `relinkStaged(n)` and `relinkRenamedIn(n)` (the two halves of each relink's swap), `afterUndoing`, `afterRedoing`, `beforeApplied`, `beforeUndone`, `beforeRedone` and `whileDeletingAFolder`.
  - It runs on two chained relinks (op0 Day 5 to Day 6, op1 Day 4 to Day 5) and three (Day 6 to 7, 5 to 6, 4 to 5).
  - It asserts the number of kills reached: 26 for two links and 35 for three, 61 in all. `whileDeletingAFolder` is never reached (no folder), nor `afterTheCheck` for an apply.
  - After recovery it checks:
    - every link is exactly as before or exactly as after;
    - nothing staged is left;
    - the step is settled on the side its links show (`done` when they read as after; `failed` or `rolledBack` for an apply, `undone` for an Undo or a Redo, when they read as before).
- `testTwoLinksSwappedInOneStepAreRefusedWithNothingChanged`: a swap (Day 4's link relinked into Day 5 and Day 5's into Day 4) is refused by the door before anything changes, so no kill inside it can be reached. That is why the swap is not in the kill table.
- The two plain-link-move shapes are laid in the same file (`ChainShape.aMoveThenARelinkIntoItsPlace`, `.aRelinkThenAMoveIntoItsPlace`) but are left out of `shapesTheRuleHolds`, so the test does not run them. The comment there says why and points here.
- Python: `test_chained_relinks_killed_at_every_point_lose_no_link` runs the model on the two-link and three-link shapes: before each swap, inside each, and after the last, going forward and back. That is 34 model kills, never interrupted, and every link before or after.
- Contract, two new `recoveryCases` rows (84 on the Mac replay, from 82):
  - `chained` step at `beforeApplied`: done, files after.
  - The new `withARelink: chainedThree` (call `relinkThreeChainedLinks`, files read on Day 4 to Day 7) step at `beforeSwap:0`: failed, files before. `recoveryCasesHow` says what `chainedThree` is.
  - Both rows are held for Windows under `Reason899W8RelinkedLink`, names byte for byte, one each.
- The plain-move shape has no contract row. Its rule is not decided (see "For the director"), and a row would pin behaviour that loses a link.

## Must-fail log

- Swift kill table with the rule of 57afa8408 put back (HEAD's file, then the fixed file copied back from the scratchpad, `git diff` checked): 20 kills lost a link on the relink shapes, 2 on two links (`twoChainedRelinks-apply-beforeApplied: links [Day 1.md, nil, nil]`, `-redo-beforeRedone`) and 18 on three links (`threeChainedRelinks-apply-afterBegin: links [Day 1.md, Day 2.md, nil, nil]`, and the rest at `beforeSwap(0)`, `relinkStaged(0)`, `beforeSwap(2)`, `relinkStaged(2)`, `beforeApplied`, `afterUndoing`, `beforeUndone`, `afterRedoing`, `beforeRedone`). Each had the phase `interrupted`. With the fix: 0.
- Contract rows, Swift: with the old rule, `UndoJournalContractTests.testRecoveryCases` fails on both new Review F rows. Green with the fix.
- Python: with the old `remove_the_links_just_made` (git stash), 15 failures: 13 subtests of the new kill test, and both new contract rows in `test_recovery_cases_with_a_relink`. With the fix: 41 tests OK. `make_undo_traces.py` writes `undo-traces.json` byte for byte as committed.

## Lows

1. **The two sentences now describe the rule as built.**
   - `undo.rule.recovery` says "at most one link for the whole step" and gives the passing rule.
   - The `Reason899W8RelinkedLink` sentence in `NamedGapLedger.cs` says the same.
   - The `chained` part of `recoveryCasesHow` now points at `undo.rule.recovery` instead of repeating the old pass-over clause.
   - The contract sentence says plainly that a plain link move is not read by this.
2. **Claims cut to what the kill table proves.**
   - The doc comment on `removeTheLinksJustMade` names the test and its shapes. It says a step chaining a plain link move to a relink still loses a link at some stop points.
   - These notes claim only the 61 kills.
3. **The two pins are now named as pins.**
   - Row 81 is renamed (contract and ledger, byte for byte) to say what it shows. The link removed is Day 5's: the folder then reads as the undo's second swap begun, and the step is put forward again. It passes on the old door too, so it pins an outcome and proves no fix. The two new rows are the real must-fails.
   - The Duplicate Class test is renamed `testDuplicateClassKeepsARePointedLessonsWikiLinkRewrittenAtItsOwnPage`. Its comment says it is a pin, not a proof of review E's fix, and that it passes with that fix reverted. Why Duplicate Class does not reach review E's refusal is still not found.

## Runs (all through xlock.sh, main Mac, own unit classes only, separate DerivedData in the scratchpad)

- `UndoRelinkTests` (16), `UndoJournalContractTests` (19), `UndoMakeRoomLinkedPageTests` (27), `UndoHandedOverPlaceTests`, `JournaledStepTests`: 131 tests, 0 failures.
- `python3 scripts/test_make_undo_traces.py`: 41 OK.

## For the director

**The counter-example.** The rule as briefed considers relinks only. A plain link move chained to a relink in the same step (the move's place is the relink's place) still loses a link at 8 of 40 kills.

- **`aMoveThenARelinkIntoItsPlace`.** Day 5's link (`Unit 1, Day 2.md`) is moved plainly to Day 6, then Day 4's link is relinked into Day 5, `Unit 1, Day 1.md` becoming `Unit 1, Day 2.md`.
  - Killed at `afterBegin`, nothing has moved. The relink reads "both standing": Day 4 holds its old text, and Day 5 holds the move's untouched link, whose text is the relink's new one. No other RELINK constrains it, so recovery removes Day 5's link.
  - Afterwards: `[Day 1.md, nil, nil]`, interrupted.
  - The same loss happens in the Undo at `beforeUndone` and in the Redo at `afterRedoing` and `beforeSwap(0)`.
- **`aRelinkThenAMoveIntoItsPlace`.** Day 5's link is relinked to Day 6, `Unit 1, Day 2.md` becoming `Unit 1, Day 3.md`. Then Day 4's link, also holding `Unit 1, Day 2.md`, is moved plainly into Day 5.
  - Killed at `beforeApplied`: Day 6's link is removed, leaving `[Day 2.md, nil, nil]`.
  - The same loss happens in the Undo at `afterUndoing` and `beforeSwap(0)`, and in the Redo at `beforeRedone`.
- Whether Insert Class can make either shape is not established. Review F could not build one, because a link to a page the plan renames is always a relink. Two later-class links holding the same text, or a link whose text equals a renamed neighbour's new name, would be the way in.

**A scratch-proven extension. Not committed, since the brief said to stop here.** Read every link move, plain ones included, as a constraint, but let only a relink be a candidate:
- in `removeTheLinksJustMade`, take ops with `isALinksMove`, using `linkShaBefore ?? linkSha` and `linkShaAfter ?? linkSha` as a plain move's texts;
- in `isTheOneInFlight`, return false for an op whose two texts are equal (a plain move: a relink's two texts always differ, `opKinds.move`).

With that, the full table of all four shapes (101 kills: 61 relink, 40 move) and the rest of `UndoRelinkTests` passed: 16 tests, 0 failures. The file was then restored to the committed rule. To adopt it:
- make those two changes;
- add `.aMoveThenARelinkIntoItsPlace` and `.aRelinkThenAMoveIntoItsPlace` to `shapesTheRuleHolds`, and change the reached count;
- make the same change in the Python model;
- add contract rows (held), and change the two sentences to say "link moves" where they say "relinking moves".

The rule is the same one, read across every link move instead of only the relinks. My recommendation is to adopt it.

Still open, unchanged:
- review D's LOW 1 (a third party putting an identical link at the other name during the downtime): narrowed, not closed;
- review D's LOWs 2 and 3;
- why Duplicate Class does not reach review E's refusal.

## For documentation 12

Windows' recovery of a step holding relinking moves removes at most one link:
- Read the relinks in the work's swap order: index order for an apply or a Redo, reversed for an Undo.
- A relink passes when:
  - both of its links stand, each holding its own text;
  - every relink before it holds its end text at its end side (`to` going forward, `from` for an Undo);
  - every relink after it holds its start text at its start side.
- Remove the just-made link (`to` going forward, `from` for an Undo) of the LAST relink that passes. Remove nothing when none passes.

Pending the director's ruling above, plain link moves may join the before/after reading as constraints.

## Self-check

- **Broke each fix and watched its test fail: yes.** The Swift table (20 kills), the Swift contract rows (both new ones) and the Python model (15) were each run against the old rule. The two lows that rename pins are renames, not fixes, and say so.
- **No timed waits where an event exists: yes.** The tests stop by the kill-point hook. No sleeps.
- **Every sentence on the failure paths is true: yes.**
  - The contract sentence, the ledger reason, the code comment and the test comment each give the rule as built.
  - Each says, or points to, the plain-move gap.
  - Each claims no more than the 61 kills.
- **`dev` merged in: yes.** Nothing new, before proving and before handing back.
- **No number tuned by trial: yes.** The reached counts are derived (an apply: 2 + swaps + 2 × relinks; an Undo or a Redo: 3 + swaps + 2 × relinks) and matched the first run.
- **Contract cases run from the JSON: yes.** Both new rows are read by `runRecoveryCases` and by the Python `test_recovery_cases_with_a_relink`, and held for Windows by exact name.
- **House style: yes.** No GCD, `map`, `filter`, `reduce` or `$0` in the added Swift. New structs carry `// MARK: -` sections.

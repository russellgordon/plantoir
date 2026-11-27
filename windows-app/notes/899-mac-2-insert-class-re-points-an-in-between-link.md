# mac-2 (#899 Undo): Insert Class re-points an in-between link where it stands

Brief `vm-tools/briefs/2026-11-27-899-mac-2-insert-class-re-points-an-in-between-link.md`. Base `origin/day27b/integration-2` 35b54c40a (dev 454ef4c6f + mac-1), as the director said. `origin/dev` merged before proving: "Already up to date". **`contracts/` touched (one `undo.rule.shadow` sentence): both gates.** Stopped at the brief's stop figure: the invariant and the three riding lows are built and proven; the contract rows, replay call, Python model, held ledger rows and must-fail log are left (below).

## For PROGRESS

- `ClassInsertionPlanner.apply`: the refusal block and `firstLinkThatCannotBeMoved` are gone (`grep -n firstLinkThatCannotBeMoved mac-app` empty). Rename loop: `.aRenamedPageThrough(hop, newPlace)` with the hop inside the working folder moves the class's link as itself (`moveLink`, text kept) and re-points the hop where it stands (`rePointWhereItStands`: `relinkLink(hop, to: hop, textAfter:)`, the hop's text with only its last path part replaced, planned once per hop). Only the folders above the hop are tidied: `standardizedFileURL` on a path holding `..` resolves the link itself (it turned the hop into the lesson's page and refused the lesson's own removal, cannotTellNow, on the first green run). New step 1b after the rename loop: each re-date-only class whose link reaches a renamed page is re-pointed where it stands (own text; hop inside; own link straight at the page's new place when the hop is outside). The dates loop still skips such a class (unchanged).
- Re-date-only shapes all occur in a numbered course (Week 1 to 3, Week 5 a link whose date is read through it as Week 2's; room at Week 2 renames Week 2 and 3 and only re-dates Week 5): all three tested.
- Riding LOW 1 (review 3 LOW 5): `UndoSwap.relinkLink`'s two-place pre-clean settles its own staged name by `settleUnderARelinksStagedName` with `givingBack: false` (new parameter): the teacher's item is kept visible beside `to` and said; never given back onto `to` (this swap never moves anything into that name, and the relink is about to fill `to`). Unreadable: `cannotTellNow`; would not move: `couldNotWrite`.
- Riding LOW 2 (review 4): after the exchange, an item that cannot be settled is exchanged back unread (it was at the place, so it is never the step's) and the swap's own link removed by its text, refused changedSince; if the exchange back is refused too, new outcome `UndoRelinkOutcome.leftUnderTheStagedName` and the refusal names the hidden name (`cannotTellNow` or `couldNotWrite`). The caller's comment now says what stands where.
- Riding LOW 3 (review 4): `killAChain` returns its faults; `testChainedLinkMovesKilledAtEveryStopPointLoseNoLink` gathers them and asserts once on the main actor. F-J's recorded "5 of 20"/"6 of 20" were XCTest's count; review 4 measured 7 of 20 every run; the test comment now says 7 (not re-measured here: left, see below).
- The director's extra shape: a teacher's page under the two-place relink's own staged name beside Day 5 of a chain (`testATeachersPageUnderAChainedRelinksStagedNameIsNeverDeleted`, live and killed before each swap). The Mac never deleted it: before the fix, live left it hidden with "in use" (red), after a kill recovery already kept it; now live keeps it visible and said too.

## For documentation 12

W8b piece 22b no longer copies "the Mac's two remaining refusals": it builds this re-pointing after 21b's one-place relink. Replacement sentence for the bullet near 18086 and the section "What the Mac's U4b3 leaves for Windows" (18360): "Insert Class never refuses for where a later class's link leads: a renamed class reaching a renamed class page through an in-between link inside the working folder is renamed as itself and the in-between link re-pointed where it stands (its text with only the last path part changed, once per link); a class only re-dated is re-pointed where it stands (its own text, the in-between link inside, or its own link straight at the page's new place when the link in between is outside)." For piece 22: the comment above `UndoMakeRoomStepTests.cs` line 290 still says "the title and date written into the file it leads to" (day27-1 sweep LOW 4). No trail event, `folding.moves` row, wording key or `file-formats` reason changed.

## Must-fail lines

Not run (stop figure). Owed: M1 refusal put back; M2 the class's own link re-pointed instead of the hop; M3 the hop planned twice; M4 the re-date-only loop removed; M5 Python. The tests that would catch each were seen red first (Runs 1).

## Runs (`.dd/`)

1. run-red (tests only, d2bbca211): 70 tests, 17 failures: all 6 new Insert Class tests (refused cannotTellNow) and the 3 riding-low tests plus the chained staged-page test red.
2. run-green1: UndoRelinkTests 38 of 38; 4 Insert Class red (the `..` hop key, above). run-green2: UndoMakeRoomLinkedPageTests 32 of 32.
3. run-classes (UndoMakeRoomLinkedPageTests, MakeRoomForClassesTests, UndoRelinkTests, JournaledStepTests, DateKeyByTheTargetsPlaceTests, UndoJournalContractTests, SharedRulesContractTests, UndoSweepFindingsTests, UndoStoppedStepTests, UndoRolloverStepTests, RestoreRecoveryTests, ClassPlanningContractTests): 331, 0 failures, after the contract and documentation edits.
4. `python3 scripts/test_make_undo_traces.py`: OK, traces current.

## Left for the next piece

- `undo.stackCases` rows "mac-2, Insert Class with a later class linked through a link inside the working folder: …" (one step; undone; undone and redone) and one per re-date-only shape; replay call `makeRoomWithALaterClassLinkedThroughALinkInside` and a key reading the hop's text in `UndoContractReplay.swift`; `stackCasesHow`; the Python model's hop re-point; each row held under `Reason899W8bLinkedClassPage` with the constant reworded (brief's "What Windows must hold"). Each will fail on Windows because its call is unknown to the replay.
- The must-fail log (M1 to M5) and a re-measure of F-J with the gathered faults (expected 7 of 20).
- Doc 12's two sentences (the clerk, from the text above).

## For the director

Nothing parked.

## Self-check

1 Must-fail not run (left). 2 No timed waits. 3 No new sentence a teacher reads; existing refusals. 4 dev merged before proving (up to date); again before hand-back. 5 No number tuned. 6 Contract checks run from the JSON (the three `UndoMakeRoomStepTests.cs` substrings each once, by script). 7 House-style grep over the added Swift lines empty; no new type. 8 Review 3 LOW 5 and review 4's two LOWs fixed with tests seen red first; day27-1 LOW 5 (the refusal) and LOW 6 (the "own text cannot be read" sentence) fixed. 9 Switch off, rename record untouched. 10 No new contract row (left).

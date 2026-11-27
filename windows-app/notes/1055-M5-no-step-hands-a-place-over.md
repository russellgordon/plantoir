# #1055 M5: no step hands a place over; the kept-page guard re-laid on a plain step

Branch `issue/1055-M5-no-step-hands-a-place-over`, stacked on M4's pushed head 93406dce2 (no merge needed: `origin/dev` and M4's head had not moved at 14:22, both already in). Touches `contracts/` (`shared-rules.json`, two rows and one `recoveryCasesHow` sentence added): both gates (the director's).

## State at the first writer's hand-back (2026-11-27, about 14:25): not finished (the second writer's part follows at the end)

Done and pushed (every pushed commit builds, its classes green):

1. The four guard tests, re-laid on a plain step with no link, in the new `mac-app/Tests/QuartzTeachersTests/UndoKeptPageUnderAVisibleNameTests.swift` under `// MARK: - The kept-page guard on a plain step (#1055 M5)`: green on M4's head (commit 3b4f345d4), all four RED on the throwaway mutant (below), the mutant reverted, never committed.
2. The two re-laid recovery rows in `undo.recoveryCases`, after the two old kept rows (which stay until the removal): "U4b3 kept-original-named, re-laid (#1055 M5): a step that removes Day 3's page ..." and "... re-laid (#1055 M5): the same, with Unit 1, Day 3 (kept by Undo).md already taken: ...". Same `work`, `stopAt` (beforeSwap:2), `files` (unchecked), `phase` (interrupted), `head` (null), `cleared` (interrupted), `keptVisibleAs`, `keptPageLines` (1), `visibleNameTaken` as the old rows; no `handEdit`, no `handedOver`, no `pathsNamed` (both keys go with the handover). ONE new key, `withAPlainPageMove` (true), defined in one sentence at the end of `recoveryCasesHow`: the plain step (Day 3 `Three.` to Day 4, Day 3 removed, `Five.` at Day 5) and `Someone else's.` written at Day 3 before recovery. Laid by the Mac replay (`UndoContractReplay.swift`: the key, a `plainPageMove` shape through the handed-over path's twin and call; `UndoContractReplayKinds.swift`: the call `movePlainPageAwayFromDay3`) and by the Python model (`test_recovery_cases_with_a_plain_page_move`). `UndoJournalContractTests` recovery count 72 -> 74. Both rows green on the Mac replay, and both RED (three failures each, as the old rows) with `keepPagesWhosePlaceIsTaken` returning at once (mutant reverted). When the removal takes out the handed-over path, the plain step's laying in the replay must be kept (re-homed off `handedOverCall`).
3. Windows: both re-laid rows held by exact name (`Reason1055KeptPageReLaid`, one `Owed(UndoRecoveryCases, 1055, V200, ...)` above the U4b3 relink comment in `NamedGapLedger.cs`): `withAPlainPageMove` is not in `UndoRecoveryContractTests.KeysChecked`, so each held row stops at "a key this replay does not check". Edited by reading only: `windows-app/Plantoir.Tests/NamedGapLedger.cs` (one constant, one entry; quotes, commas, parentheses read back).

Left (nothing of it started; no half-removed state anywhere):

- The whole Remove list of the brief (product, tests, `shared-rules.json` door rows and the two OLD kept rows, `file-formats.json`, Python, notes top lines), the row-count script, and the done-means greps.

## The plain step chosen, and why it reaches the state

No ordinary Insert Class through `JournaledStep` was used: the tests lay the ops directly, as the old tests laid shape B, so the swap and recovery are what is under test. The step is Insert Class's plain move of Day 3's page with no link: `writeFile` Day 4 (new, holding `Three.`), `writeFile` Day 3 (`Three.` -> removed), `writeFile` Day 5 (new, `Five.`). At the last swap (Day 5) a plain file `Someone else's.` is written at Day 3 and the swap is refused (`fileInUseAtSwap` true). The swap's reversal then cannot put Day 3's page back, because `putBackAKeptOriginal` puts a removal back exclusively (fdc4d3b55): `notPutBack`, the page kept beside its place. Recovery by another process then finds Day 3 taken and `keepPagesWhosePlaceIsTaken` names the page `Unit 1, Day 3 (kept by Undo).md`. For test 2 (an Undo taking a new page away), the step writes new pages at Day 5 then Day 3; its Undo (reversed) takes Day 3's away first, and the same happens at the Undo's last swap.

So the STOP condition does not apply: an ordinary step with no link reaches the guard (both the never-write-over check of fdc4d3b55 and `keepPagesWhosePlaceIsTaken`).

Differences from the old tests, said plainly: the swap's refusal is `fileIsInUse` naming Day 5 (the old tests' `changedSince` naming Day 3 came from the handed-over filler's own check, `placeIsLeftEarlier`, a handover-only hunk of fdc4d3b55), so tests 1 and 2 assert `notPutBack` with one kept original, not the refusal's path. The plain case keeps fdc4d3b55's effect through `putBackAKeptOriginal`/`renameExclusively`, which is not handover-only; `placeIsLeftEarlier` is handover-only and may go with the removal.

## The mutant (throwaway, reverted, never committed)

`UndoSwap.putBackAKeptOriginal` always `rename` (replacing), and `UndoRecovery.keepPagesWhosePlaceIsTaken` returning true at once. All four tests red: lines in `windows-app/notes/1055-M5-mustfail.log` (9 failures in 4 tests). Note: `placeFilled(by:)` is not on the swap's path at all (only recovery's `keepPagesWhosePlaceIsTaken` and the handover code read it), so for tests 1 and 2 the mutant that pins the guard is the exclusive put-back, not `placeFilled`.

## Runs (all through `xlock.sh`, one class, 15-minute kill)

- `run-guard1`: 3 of 4 green; test 2's step ordered so Day 3 was swapped last (fixed by ordering the ops).
- `run-guard2`: 4 of 4 green on M4's head.
- `run-mutant`: 4 of 4 red, 9 failures; mutant reverted (`git status` clean after).
- `run-rows`: `UndoJournalContractTests` 19 of 19 green with the two rows (74 recovery cases).
- `run-rows-mutant`: `testRecoveryCases` red on both re-laid rows (and the old two) with `keepPagesWhosePlaceIsTaken` returning at once; reverted.
- `run-rows2`: `UndoJournalContractTests`, `SharedRulesContractTests`, `UndoKeptPageUnderAVisibleNameTests`: 90 green.
- `run-readers`: `UndoOpKindsTests`, `RestoreWholeCourseContractTests`, `JournaledStepTests`, `FileFormatsContractTests`: 85 green.
- Plain Debug build: succeeded.
- `python3 scripts/test_make_undo_traces.py`: 40 OK (traces not stale).

## Windows

Edited: `windows-app/Plantoir.Tests/NamedGapLedger.cs` only (the hold above). The Windows suite should stay at its six known failures.

## COMMON's self-check

- Swift rules: no map/filter/reduce, no `$0`, explicit loops, `// MARK: -` sections in the class and both structs, no GCD, no timed waits: yes.
- No teacher-visible wording changed; no new handling or edge case.
- No UI class, no app launch, no gate, no whole suite.

## Parked

- The replay also accepts `withAHandedOverPlace: plainPageMove` as an alias of the new key (a side effect of reusing the handed-over path); it goes with the removal.


## The second writer (2026-11-27, afternoon): the Remove list

Dev merged in first: `origin/dev` 412053b07 (M3 and M4) merged at 1ca6f200b. `origin/dev` had not moved again at hand-back.

### Removed (each by its commit, reversed by reading; `git apply -R` where a hunk still applied, by hand where later commits had touched it)

- `527ad58e3` door-1 and `9c0f34536` door-2: `UndoCheck.plan`'s handover parts (`handovers`, `placeIsFree`, `opsNotChanged`, `inAHandoverWithALink`, the target-op lists, `handedOverPaths`, the step-order return), `targetsInTheStepsOrder`, `placeLeavingTheFolder`'s `judgedOnTheFoldersAbove`, `UndoHandover`, `UndoSwapTarget.handedOver` and its use in `stageAFile` and `placeLeadingOut(atStaging:)`, `wholeState`'s `toIsHandedOver`/`fromIsHandedOver`, `UndoPlaces.staysInsideAbove` folded back into `staysInside(_:_:namedBy:)` as before door-1. `UndoCheck.swift` and `UndoOpKinds.swift` now differ from `527ad58e3^` only by the kept hunks below and by later non-handover commits.
- `3f5206b0c` door-3: `listHolds`' partners, `fileStates`' pair judging (back to the one loop of `3f5206b0c^`), `movesHandingOver`, `placeJudged`, settle's `placeJudged` use.
- `180ff8000` door-4: `wholeOpsStandAlone`'s handover exception and `UndoStep.isHandedOver` (the hunk reversed whole); the 7 stack rows; `stackCasesHow`'s door-4 sentence; `file-formats.json` `opKinds.wholeOps`' second exception and `opKinds.move`'s handed-over sentence ("first exception" back to "one exception"); the replay's `handedOver` stack key, the calls `handAPlaceOverAfterALinksMove`, `handAPlaceOverBeforeALinksMove`, `editTheHandedOverPageByHand`, `stepFillingAPlaceBeforeItIsLeft`, `stepHandingOverAFoldersPlace`, `libraryTarget`, `layALink`; the Python model's door-4 hunks.
- `da5fcb554` door-5: `JournaledWrite`'s judged-above check (hunk reversed whole), `placesShown`, `shownAs`, `countShown`; the 8 door-5 recovery rows; the Python model's door-5 hunks and `test_recovery_cases_with_a_handed_over_place`.
- `ddbfd03dc` door-6: `JournaledStep`'s `isLeftFreeByALinkMove`, the free old place in `plan`, `relativePath`, the reads, `fileExists`, `markdownFiles` (back to `ddbfd03dc^`, with review D-E fix 2's doc comment, which described door-6's listing, back to the one sentence), `inHandingOverOrder`, `laterLeaver`, `wholeFileOp`, the target-op lists, the `handedOver` target; door-6's five tests replaced by the one they replaced (`testAWriteAtThePlaceALinkMoveLeavesIsRefusedBeforeAnythingChanges`, from `ddbfd03dc^`); M4's `testAPlaceHandedOverAfterALinksMoveStillGoesBothWays` ("M5 removes it").
- `UndoHandedOverPlaceTests.swift` deleted whole.
- The 2 OLD "U4b3 kept-original-named: ..." rows. `withAHandedOverPlace`, `handedOver` and `handEdit: handedOverPlace` gone from the replay and `recoveryCasesHow`.
- `UndoJournalContractTests` recovery count 74 -> 64.

### Kept (risk 1), where each still is

- `UndoCheck.placeLeft(by:)`, `placeFilled(by:)`, `handsOverAsAMove` (now a file's move by `sha` only; its link half gone): `UndoCheck.swift`; read by `UndoRecovery.keepPagesWhosePlaceIsTaken`.
- `UndoSwap.visibleName(for:number:isAPage:)`, `keepUnderAVisibleName`, `renameToAVisibleName`: `UndoCheck.swift`.
- `UndoRecovery.keepPagesWhosePlaceIsTaken`: `UndoRecovery.swift` (both calls).
- `UndoAppSeams` `.undoKeptAPageUnderAVisibleName` and its install; `ActivityTrail.undoKeptAPageUnderAVisibleName`; the contract event "undo kept a page under a visible name" (`shared-rules.json`).
- `fdc4d3b55`'s never-write-over check: `UndoSwap.putBackAKeptOriginal` (exclusive put-back of a removal) in `reverse()` and `swapAFile`. Its other hunk, `placeIsLeftEarlier` (the refusal naming a handed-over place), was handover-only and is gone: in a plain step no two targets share a place.
- `bf2b30c5a`'s naming loop, recovery's kept-page call and its `undo.rule.recovery` sentence: untouched.
- `JournaledStep.moveLink`, `isALinksMove`, `linkSha`, `plan(throughALink:)`, `placeALinkLeadsTo` (M6's).

### Not empty, and why (for M6)

`git grep plannedLinkMove` still finds `JournaledStep.plannedLinkMove(endingAt:)` and `(startingAt:)`: they PRE-DATE door-6 (`ddbfd03dc^` has both) and are read only by `placeALinkLeadsTo`, `refusesAWrite` and `plannedKey(of:)`, which are M6's with `moveLink`. Removing them here would take `refusesAWrite`'s refusal of a write at a link move's `from` with them. They go with `moveLink` in M6.

### The plain step's laying, re-homed

The replay's `handedOverCall` path is gone; the plain step is laid by its own `plainPageMoveCall` (`withAPlainPageMove` only), its twin read by `UndoContractKinds.classPages(in:)` (Day 3, Day 4, Day 5; the old `handedOver` read Day 2 to 4 and a library). `recoveryCasesHow`'s kept-page sentences now hang on `withAPlainPageMove` (one sentence for the step, one for `keptVisibleAs`, `visibleNameTaken`, `keptPageLines`).

### Contract changes beyond the removals

- One kept stack row's `why` changed: "U4b2-14, review 1: a link's move with an edit inside its new place ..." had door-4's "its second exception, a place handed over (U4b3)" clause; it is back to its `180ff8000^` words ("The only exception to opKinds.wholeOps is ..."). The row itself is M6's.
- The riding LOW: `activityTrail` "undo refused for a change left part way" `carries` back to "nothing could be written beside it" (its words before mac-2's `6206caedd`), as the Mac's `leftNewestLine` says.
- `undo.rule.recovery` and `stagedThenSwapped` held no handover clause (grep "hand", "door"): nothing to remove. `undo.rule.shadow`'s "and not handed over" left for M6.

### Row-count script (decoded JSON, before and after)

```text wrap
stackCases 133 -> 126 removed 7 order/name same: True rows changed: ["U4b2-14, review 1: a link's move with an edit inside its new"] (its why, above)
recoveryCases 74 -> 64 removed 10 order/name same: True rows changed: []
re-laid rows: 2
```

### Windows (by reading; no edit this round)

The re-laid rows stay held by `Reason1055KeptPageReLaid` (the first writer's entry): `withAPlainPageMove` is not in `UndoRecoveryContractTests.KeysChecked`. Nothing on Windows reads a removed row by name; `UndoStackContractTests.LinkCases()` still has U4b2-14's two `moveALinkToAFolder` rows, and its count test (stack rows = `Cases` + `LinkCases`) still holds. Dead until W3: `UndoHandoverForTheCases.cs`, `UndoHandedOverPlaceTests.cs`, `UndoActionStepLinkTests.cs`, the `withAHandedOverPlace`/`handedOver` branches of `UndoRecoveryContractTests` and `UndoStackContractTests`, and Windows' product handover code (W8b-21a1 to 21a6, 21c's handover part).

### Runs (all through `xlock.sh`, 15-minute kill)

- `run-remove1`: UndoKeptPageUnderAVisibleNameTests, UndoKeptCopiesTests, UndoJournalContractTests, UndoFilesContractTests, UndoWriterScanTests, JournaledStepTests, UndoStoppedStepTests, UndoOpKindsTests, UndoDoorGuardTests, RestoreDuringAFolderRenameTests, UndoSweepFindingsTests, SharedRulesContractTests, FileFormatsContractTests: 245 green (`UndoThinningKeptCopiesTests` does not exist).
- `run-mutant2` (after the removal): `keepPagesWhosePlaceIsTaken` returning true at once: guard tests 3 and 4 red (6 failures), `testRecoveryCases` red on both re-laid rows; reverted (`git checkout`), never committed. Lines in `1055-M5-mustfail.log`. Tests 1 and 2 are pinned by the exclusive put-back (the first writer's mutant).
- `run-extras`: UndoActionStepsTests, UndoRolloverStepTests, UndoShadowPublishTests, RestoreRecoveryTests, ActivityTrailWiringTests, UndoKeptPageUnderAVisibleNameTests: 93 green.
- Plain Debug build: succeeded.
- `python3 scripts/test_make_undo_traces.py`: 38 OK (40 minus door-4's order test class and door-5's test); traces not stale.

### Self-check

1. One invariant: no step hands a place over; the guard stays, pinned on a plain step. 2. Dev merged (1ca6f200b). 3. Broke the guard after the removal and watched the tests and the re-laid rows fail. 4. Contract cases run from the JSON (replay and the Python model). 5. No teacher-visible wording changed (the "(kept by Undo)" name and its trail line untouched; the `carries` fix is the contract's description only). 6. No new handling, no edge case built. 7. House style: no GCD, map/filter/reduce or `$0` in the lines written; MARK sections kept. 8. The riding LOW fixed (no test: it is a description sentence). 9. Switch off, rename record kept. 10. The re-laid rows are in the Mac replay and held on Windows by exact name.

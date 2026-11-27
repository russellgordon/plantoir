# #899 W8b-21c: recovery keeps a page it cannot put back under a visible name (2026-11-27)

Branch `issue/899-w8b-21a-handed-over-place`, on 21a5's head 84c7f53be. `origin/dev` 6dc36fcea was already in the branch (`git merge origin/dev`: already up to date, before proving and before handing back).

Commits: 3c2b18a67 (tests first, with inert stubs: `VisibleName(…, isAPage)` ignoring the flag, `KeepPagesWhosePlaceIsTaken` returning true), 1d03b0095 (the product; it also adds the test `ANameTakenInTheInstantBeforeTheRenameIsNeverOverwritten`, written for must-fail row 1 after the tests-first commit).

## For PROGRESS

- U4b3 kept-original-named on Windows: `UndoRecovery.KeepPagesWhosePlaceIsTaken` (the mac's `keepPagesWhosePlaceIsTaken`). For a step a LIVE recovery closes without settling it, every kept original FILE of the step's beside a place an op leaves or fills whole (`UndoOp.PlaceLeftBy`, `PlaceFilledBy`) that is not a copy of what that place holds while something else holds it is renamed to the first free visible name, `Unit 1, Day 3 (kept by Undo).md`, then `(kept by Undo 2)`. Called from `TidyClosedSteps` (new `live` parameter, before the tidy; the step is not noted tidied while a place cannot be read) and in the couldNotPutBack arm of the settle, after the tidy and before `KeptOriginalsLeft` and the couldNotPutBack line.
- ONE naming function: `UndoSwap.VisibleName(place, number, isAPage)` gained the page form (the words before the extension); ONE naming loop: `UndoSwap.RenameToAVisibleName` (the mac's `renameToAVisibleName`), now also used by the folder's `PutBackOrKeepVisibly`. Rename by `RenameWithRetries(…, replace: false)`, i.e. `MoveFileEx` without `MOVEFILE_REPLACE_EXISTING`.
- Trail: `ActivityTrail.Event.UndoKeptAPageUnderAVisibleName` ("undo kept a page under a visible name"), `UndoTrail.KeptAPageWords` (the mac's `keptAPageLine`), the arm in `ToTheActivityTrail`. Written just before the rename.

## For documentation 12

- The "What W8 owes" for U4b3 kept-original-named is built: name `KeepPagesWhosePlaceIsTaken`, `RenameToAVisibleName`, and the two call sites above. Shadow never calls it.
- How the event's test passed before this piece: `ContractTests.SharedRules_ActivityTrailEvents_Exist` (there is no class `ActivityTrailEventsTests`) held "undo kept a page under a visible name" as a named gap (`NamedGapLedger.ActivityTrailEvents`, `Reason899W8HandedOverPlace`); Windows neither held nor wrote it.

## Ledger

- Cleared: the `ActivityTrailEvents` row "undo kept a page under a visible name" (the event is built).
- NOT cleared: the two `UndoRecoveryCases` rows "U4b3 kept-original-named: …". Replayed (run w8b-21c-a, `keptPageLines` in `KeysChecked`), both failed at `UndoRecoveryContractTests.cs:405`: no file at `keptVisibleAs` after recovery (null), though every unit test of the rename passes. So they are held again under `Reason899W8HandedOverPlace`, its sentence rewritten to say what is built and what is not; `keptPageLines` is out of `KeysChecked` again so they stop at "a key this replay does not check". The page form of `visibleNameTaken` and `keptVisibleAs` stays in the replay, inert until the key goes back.
- Hypotheses for the next look (not run): (a) the changedByHand close, or the start-of-settle tidy (`unlessTheListHolds`), removes Day 3's `-orig` because the list still holds `Three.`, before the list is cleared: that would be a data loss and the first thing to check (list the section folder after recovery); (b) the removed page's original is not under a `-orig` name `KeptOriginalFiles` finds; (c) `TidyClosedSteps` does not see the step as interrupted in the same run (`writer.Folded` stale) or has it noted tidied. One run listing `courses/TST1O/section1` after recovery in that row tells which.

## Must-fail lines

`vm-tools/guest/899-w8b-21c-mustfail.json`, six rows, RED 6 of 6 on 1d03b0095 (run w8b-21c-a):
1. `replace: true` in `RenameToAVisibleName`: RED, `ANameTakenInTheInstantBeforeTheRenameIsNeverOverwritten`.
2. the line after the rename: RED, `ANameTakenIsSkippedNeverReplacedAndTheLineComesFirst` ("the line was written after the rename").
3. a page name of its own: RED, three tests, `TheFolderAndThePageAreNamedByOneFunction` first.
4. thinning by length: RED, `TwoContentsOfEqualLengthBothStay`.
5. an unreadable copy removed: RED, `AnUnreadableCopyAndAnotherStepsCopyAreLeftAlone`.
6. another step's copy taken as this step's (`KeptOriginalFiles` without the seq): RED, the same test.
A seventh row (recovery never keeping a page) was dropped: the contract rows it named fail without it.

## Runs

- w8b-21c-a (PC, ref 1d03b0095, red ref 3c2b18a67): tests first RED 6 of 104 (the activity-trail event check, three `UndoKeptPageUnderAVisibleNameTests`, the two contract rows); then both builds 0 errors; classes 372 of 374 (the two kept-original-named rows, see Ledger); must-fail RED 6 of 6; restored; lock released.
- w8b-21c-b (PC, ref 6e070c8ca, the two rows held again): both builds 0 errors; **374 of 374 passed**. Classes: UndoRecoveryContractTests, UndoThinningKeptCopiesTests, UndoKeptPageUnderAVisibleNameTests, UndoRecoveryTests, ContractTests.SharedRules_ActivityTrailEvents_Exist, ActivityTrailWiringTests, NamedGapLedgerTests, UndoWriterScanTests, UndoOpKindsContractTests, UndoDoorTests, UndoStackContractTests. The 21a5 harness was not re-run (as told).

## Left for the next piece

- The brief's test "the trail line before the couldNotPutBack line" is NOT written as its own end-to-end test: reaching the couldNotPutBack arm with a handed-over place taken needs a stopped step whose content is gone and whose kept original no longer matches, which the scribe does not lay without the contract walker. The order is by construction (the call precedes `KeptOriginalsLeft` and the line in the same arm) and the line before the RENAME is tested (`ANameTakenIsSkippedNeverReplacedAndTheLineComesFirst`, must-fail row 2). Suggest the reviewer or 21a6 add it with a recovery case laid by hand.

## For the director

- Nothing parked for Russell.
- The two contract rows are still held (Ledger); a short follow-up piece with one diagnostic run should clear them. Budget reached, so not chased here.

## Self-check

1. Each new test broken by its must-fail row (see Runs). 2. No timed waits. 3. The trail line is the contract's line (the mac's `keptAPageLine`); the couldNotPutBack line, said after, names only what is still hidden (it reads the disk). 4. `dev` 6dc36fcea in before proving. 5. No number tuned. 6. Contract rows read from JSON; no `contracts/` change. 11. The event row out of the ledger; the two recovery rows held again with a true sentence (not cleared). 12. `keptPageLines` checked against every held recovery row. 13. One function per rule: `VisibleName` and `RenameToAVisibleName` for a folder and a page; the place's "is it a copy" is `UndoSwap.IsACopyOfItsPlace`. 14. The PC script releases only its own lock.

## 21c2

Brief `vm-tools/briefs/2026-11-27-899-w8b-21c2-kept-page-rows-replay.md`. Same branch; `git merge origin/dev` (6dc36fcea) already up to date before proving and before handing back.

### The cause (diagnostic replay, PC runs w8b-21c2-diag and -diag2, scratch commits e19b3458d and e3265d77b on `scratch/899-w8b-21c2-diag`, deleted after)

The first suspect was wrong: nothing deleted Day 3's hidden original, and no page was lost. Listing section 1 at each recovery point showed `.Unit 1, Day 3.md.plantoir-undo-1-apply-orig` (holding `Three.`) present after the stop, after the hand edit, after the first tidy and after recovery, and the journal holding only the step's begin line: recovery never settled the step at all. The judged states were Day 4 After, Day 3 Neither, the link's move "Day 2 → Day 3" Neither, and **Day 2's writeFile CannotTell**, so `Settle` returned `cannotTellNow` (Day 2) and left the step `begun`, which `TidyClosedSteps` (interrupted only) never meets, so `KeepPagesWhosePlaceIsTaken` never ran. Day 2 holds the link still (the step stopped before the link's move), and its write (New. at the place the link leaves) is judged against what is at Day 2; with the move Neither (Day 3 taken by someone's page) the pair rule does not judge it as absent, so `UndoCurrent.Read` read Day 2 THROUGH the link, and a link the mac writes (`../library/Day 2.md`, forward slashes) does not open on Windows: cannot tell, for good. The mac reads the place by `lstat` (`UndoItem.read`): a link is `notAFile`, so the write is neither, the step closes changedByHand and the tidy keeps the page under its visible name.

### The fix

`UndoCurrent.ReadWithoutFollowingALink` (UndoCheck.cs): a link at the place (`UndoLinks.Look`, the one test of a link) is the new `UndoCurrent.NotAFile`, never read through; `StateOf` judges a writeFile on it neither, as on a folder (every other op already judges a non-`Bytes` neither). Only `UndoRecovery.FileStates` reads with it. A first try (8259287c8) put the rule in `UndoCurrent.Read` itself, for every reader, as the mac's lstat is; run w8b-21c2-a showed it changes the switch-off step on a linked later class (`UndoMakeRoomStepTests.ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacMovesTheLink_UntilW8bPiece22`, "Nothing was changed" where it wrote plainly), because the door's plan and the swap's re-read read that page through its link. So the door and the swap still follow a link until W8b piece 22 moves the link itself; piece 22 should then ask whether `Read` can stop following links everywhere, as the mac's does.

### Tests (tests first, a82e2e783, inert stub `NotAFile` never returned; seen RED in run w8b-21c2-a: 4 of 103)

- `UndoKeptPageUnderAVisibleNameTests.APagesPlaceHoldingALinkIsNotAFileAndIsNeverReadThroughIt` (two cases: the mac's link `../library/Day 2.md`, and a Windows one with backslashes whose target holds the op's after): RED at `Assert.IsType<UndoCurrent.NotAFile>` on both.
- The two contract rows, out of the ledger with `keptPageLines` in `KeysChecked`: RED at the `keptVisibleAs` bytes (`UndoRecoveryContractTests.cs` about 404).
- `ThePageKeptUnderAVisibleNameIsSaidBeforeTheCouldNotPutBackLine` (the test 21c did not write): a step laid by hand that died with Day 3 removed and Day 5 changed, the list's content gone and Day 5's kept original changed, someone's page at Day 3; recovery closes it couldNotPutBack, Day 3 is kept as `Unit 1, Day 3 (kept by Undo).md`, its line comes before the couldNotPutBack line, which names only Day 5's kept original. Green at the tests-first commit (the order was right by construction); must-fail row 3 turns it RED.

### Ledger

- `Reason899W8HandedOverPlace` is gone (it held only these two rows), with the two `UndoRecoveryCases` rows; `keptPageLines` is back in `KeysChecked` (only these two rows carry it). A stale comment naming 21c above the restore's `ActivityTrailEvents` row is gone too.

### Must-fail (`vm-tools/guest/899-w8b-21c2-mustfail.json`)

1. recovery reads a link at a page op's place through it: RED, `APagesPlaceHoldingALinkIsNotAFileAndIsNeverReadThroughIt` and the two contract rows.
2. a writeFile judges a link at its place as nothing there (`NotAFile` not neither): RED, the same test.
3. the page kept under a visible name after the couldNotPutBack line: RED, `ThePageKeptUnderAVisibleNameIsSaidBeforeTheCouldNotPutBackLine`.

### Runs

- w8b-21c2-diag, w8b-21c2-diag2 (PC, scratch refs): the diagnostic above; only `UndoRecoveryContractTests`.
- w8b-21c2-a (PC, ref 8259287c8, red ref a82e2e783): red 4 of 103 as above; both builds 0 errors; 1461 of 1464 (`~Plantoir.Tests.Undo`, NamedGapLedgerTests, ActivityTrailWiringTests, ContractTests.SharedRules_ActivityTrailEvents_Exist; 1 skipped), the two failures the make-room test above; must-fail RED 3 of 3 (rows 1 and 2 as then written, on `Read`).
- w8b-21c2-b (PC, ref 2e7794107): both builds 0 errors; **1463 of 1464 passed** (1 skipped, the same classes as -a); must-fail RED 3 of 3; restored 1463 of 1464; lock released. The make-room test passes again.

### For the director

- Nothing parked; no `contracts/` or `mac-app/` change.
- For W8b piece 22: the door's plan and the swap still read a page through a link (above).

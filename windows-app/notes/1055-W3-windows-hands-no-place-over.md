# #1055 W3: Windows hands no place over; the kept page stays

Russell's rule (#1055, 2026-11-27): Plantoir reads and writes through a
symbolic link and has no other link code. This piece removes Windows' handed-over
place (W8b 21a1 to 21a5) and 21a6's handing-over order; the kept page under a
visible name (21c, 21c2, 21c review 2) stays, and its two recovery rows, re-laid
by the mac's M5 on a plain step, run on Windows. Nothing a teacher sees changes;
no `contracts/` file was touched.

Base: W2's pushed head `ce9dfde79` (`issue/1055-W2-no-relink-and-no-lesson-copy`).
`origin/dev` (cc4ee3ab5 at both merges) is an ancestor of it, so both merges of
`origin/dev` (before proving and before hand-back) were no-ops
("Already up to date."). Branch `issue/1055-W3-windows-hands-no-place-over`.

## What was removed, by the commit it came from

The return point is `716aec523`, the first parent of the 21a merge `251099e98`.
Each hunk of 21a was put back to `716aec523`'s text, copied with
`git show 716aec523:<path>`, not retyped; W8c's, W2's and the 21c hunks in the
same files were left as they are (each file checked with
`git diff 716aec523 -- <file>` afterwards: only W8c, 5b4045d9d, 21c and W4's link
hunks remain).

- `UndoFormat` (21a1 `79d80003e`/`1567029fd`, 21a4 `37a2e06ba`/`06a064cb4`):
  `UndoOp.Handovers`, the `UndoHandover` record, `UndoStep.IsHandedOver`,
  `WholeOpsStandAlone`'s handover exception; the method and its summary are
  `716aec523`'s again (the one exception, U4b's carried edit), as the mac's
  `wholeOpsStandAlone` reads after M5. `HandsOverAsAMove` loses its link half
  (`|| op.LinkSha is not null`); its summary reads "a file's own `move` (by its
  `sha`)", as the mac's `UndoCheck.handsOverAsAMove`.
- `UndoCheck` (21a1, 21a2 `63ebcbed7`/`ebd308976`): `WholeStateOf`'s
  `toIsHandedOver`/`fromIsHandedOver`, `Ready.InTheStepsOrder`,
  `LeadingOps`/`InOrderOps`/`WholeOps`, `Ready.HandedOver`, the plan's
  `handovers`, `opsNotChanged`, `placeIsFree`, `inAHandoverWithALink`,
  `handedOverPaths`, `firstOpOnPath`, and `TargetsInTheStepsOrder`. The file is
  `716aec523`'s plus 21c2's three hunks (`UndoCurrent.NotAFile`,
  `ReadWithoutFollowingALink` with its `CannotLook` reading, `StateOf`'s
  `NotAFile`). The `ReadWithoutFollowingALink` summary no longer says recovery
  left a step that handed a place over in flight, nor "until W8b piece 22 moves
  the link itself" (piece 22 is cancelled; LOW M1-1 of window 1 review 1); it
  says what is true: the door's plan and the swap's re-read read a page through
  its link, so with the switch off a step on a linked page is written through it.
- `UndoDoor` (21a5 `e53b8411a`/`f2c9d746e`, 21a1): the vet's `judgedAbove`,
  the plan check's `ready.HandedOver` (`StaysInsideAbove` for it), and
  `TargetsOf`'s handing-over order and `HandedOver` flag: `716aec523`'s text.
- `UndoSwap` (21a1): `UndoSwapTarget.HandedOver` and `PlaceLeadingOut`'s
  `atStaging` branch.
- `UndoPlaces` (21a1): `FirstPlaceLeadingOut`'s `judgedOnTheFoldersAbove`.
  `StaysInsideAbove` stays for W4 (`StaysInside(root, relative, op)`'s link
  branch calls it); its summary no longer names a file op handed a place.
- `UndoRecovery` (21a3 `4aa4e4fef`/`a0d1f0e6d`/`58b1beec9`, 21a5): `ListHolds`'
  handover partner (the put-back of a kept original's page with its pair) and its
  `whole:` reading; `MovesHandingOver`, `PlaceJudged`, `PlacesShown` and the
  settle's `Shown`/`CountShown`; `JudgedTogether`; `FileStates` back to
  `716aec523`'s with 21c2's `ReadWithoutFollowingALink` for a page's place;
  `LeadsOut(op, root, sides)`; `UndoHandedOverSides`. From `53cecb7b6` the two
  refactors stay: `OpsToPutBack` (a place is `op.PlaceName` again, its summary
  so) and `ListHolds(step, root, blob)` (called by the `UndoJournal` overload,
  which `UndoStoppedStep` and the tidy call).
- `UndoActionStep` (21a6 `441807abe`/`ccc292a54`, its ordering half): both
  `InHandingOverOrder` overloads, `LaterLeaver`, `WholeFileOp`, the two calls
  (`MakeAsOps`, `WritePlainlyQuietly`) and the `targetOps` list built only for it.
- Tests: `UndoHandedOverPlaceTests.cs` and `UndoHandoverForTheCases.cs` deleted;
  `UndoActionStepLinkTests`' three handing-over tests and the helpers only they
  used (`PlanInsertClassAtALinkedDay3`, `AssertTheEndTree`, `PlacesInOrder`;
  `AWriteAtALinkMovedToAnotherFolderIsRefusedAndNothingChanges` stays for W4);
  `UndoRecoveryContractTests`' `withAHandedOverPlace`, `handedOver`,
  `KeptPageTaken`'s handover form, every `handoverShape` branch and the
  `handedOverPlace` hand edit; `UndoStackContractTests`' `handedOver` key, the two
  handover call names in `LaysASymbolicLink`, the five handover calls
  (`handAPlaceOverAfterALinksMove`, `handAPlaceOverBeforeALinksMove`,
  `editTheHandedOverPageByHand`, `stepFillingAPlaceBeforeItIsLeft`,
  `stepHandingOverAFoldersPlace`: none is in `contracts/shared-rules.json` since
  M5, checked by grep, 0 each) and the `Handover` helpers.
- Harness: `W8bRuns.cs` deleted; `Program.cs` is `716aec523`'s
  (`w8b-handover-kill`, `child-w8b-handover`, `child-w8b-handover-recover` gone).
- Ledger: the `Owed(UndoRecoveryCases, 1055, …)` block and
  `Reason1055KeptPageReLaid` removed; no other row or reason named it.
- Notes: 21a1 to 21a5 gained "Removed by #1055 (2026-11-27): symbolic links in
  course content are not supported; no step hands a place over."; 21a6 "Its
  handing-over order removed by #1055 W3; the rest by W4."; 21c "The kept page
  stays (#1055); its two recovery rows were re-laid on a plain step (#1055 M5, W3)."

Lines: 24 files, 178 insertions, 2132 deletions against W2's head.

## The 21a6 split as done

W3 took only the handing-over ORDER (`InHandingOverOrder`, `LaterLeaver`,
`WholeFileOp`, `targetOps`). Left for W4, untouched: `MoveLink`,
`LinkMoveEndingAt`, `LinkMoveStartingAt`, `StaysInItsFolder`,
`IsLeftFreeByALinkMove`, `RefuseAWriteAtALinkMovedAway`, `PlannedPlace`'s link
branch and `ShownAs`, `UndoLinks.FileALinkLeadsTo`, `IsALinksMove`, the
remaining `UndoActionStepLinkTests` test.

## Kept, and why (grep in `Plantoir.Core` at the head)

- `KeepPagesWhosePlaceIsTaken` (UndoRecovery.cs, 4), `PlaceLeftBy` and
  `PlaceFilledBy` (UndoFormat.cs 2, UndoRecovery.cs 2: the guard reads them),
  `HandsOverAsAMove` (UndoFormat.cs 3, by `sha` only), `VisibleName`,
  `RenameToAVisibleName` (UndoSwap.cs 2, UndoRecovery.cs 2),
  `ReadWithoutFollowingALink` (UndoCheck.cs 2, UndoSwap.cs 3: `IsACopyOfItsPlace`,
  UndoRecovery.cs 1: `FileStates`), `UndoCurrent.NotAFile`, the trail event
  "undo kept a page under a visible name" (ActivityTrail.cs): the 21c guard.
- `FirstPlaceLeadingOut` (seven files), two-argument: U4b2-2's leads-out guard.
- `UndoActionStep.InTheStepsOrder(List<UndoFileChange>)` (2): the plain step's
  own order (`720c301fd`), not the handing-over order.
- `MoveLink` (UndoActionStep.cs 3, SpecialFolderRenamer.cs 2),
  `LinkMoveEndingAt` (4), `StaysInsideAbove` (2): W4's.
- `UndoRecovery.KeptVisibly` is not here: W2 removed it (its only caller was the
  relink tidy).

The done-means grep is empty but for unrelated words: `PreviewBrowserHandoff.IsHandedOver`
(and its two tests and its caller in `SectionDetailView`), the `handedOver` local
in `DeployedFolderResolver`, and `FixWithAssistantContractTests`' `handedOver`
key (the assistant's handover rows).

## Every caller of a file `move`, and why none shares a place

Windows product code makes `move` ops in one place only,
`UndoActionStep.FolderMoveOp` (UndoActionStep.cs about 522): a folder's move
(`listingSha`) or a link's move (`linkSha`). No product code writes a `move` with
a `sha` (grep for `"move"`, `UndoOp.Move`, `"sha"`, `moveApart`, `setAside` in
`Plantoir.Core` and `Plantoir`: only the reader, the check, the swap and
recovery). Windows has no rollover step and no Deploy step that records a
`moveApart`/`setAside` yet. So no ordinary Windows action makes a step in which a
file's move shares a place with another op, and the barrier meets none; a
folder's move that shares a place was a barrier before 21a and still is.

## Tests first

At `cb05a0d40` (test 1, the ledger hold removed), run `1055-W3-a`'s red pass:
`UndoFormatTests.AStepThatHandsAPlaceOverIsUnreadable` RED (`Assert.False()
Failure`, the step read as readable through the handover exception), and both
re-laid `EveryRecoveryCase` rows RED (the key `withAPlainPageMove` not yet
checked): 3 failed, 144 passed of 147. Then `188d20a15` (the replay teaches
`withAPlainPageMove`, laying the mac's three `writeFile` ops: Day 4 new holding
`Three.`, Day 3 removed, Day 5 new holding `Five.`, through the door for ops,
stopped as the row's `stopAt` says, `Someone else's.` written at Day 3 before
recovery, `visibleNameTaken`, `keptVisibleAs` and `keptPageLines` checked; a
`files` other than `unchecked` with it fails naming itself, since no row has one).
Lesson 4: no row still held carries `withAPlainPageMove` (the two were the only
ones, and they now run).

The STOP condition did not arise: on this plain step with no link, Windows'
swap and recovery keep the removed page as `Unit 1, Day 3 (kept by Undo).md`
(and `(kept by Undo 2).md` with the first taken), the intruder untouched.

## Runs (the PC, under `C:\vm-setup\wt-compare.lock`)

Hardware: LENOVO 20QES70500, Intel Core i5-8365U @ 1.60GHz, 16 GB, Windows 11 Pro 26200.

- `1055-W3-a` (log `C:\vm-setup\1055-W3-a\run.log`, ref 6b14b5090, red ref
  cb05a0d40), RUN_DONE 2026-11-27 17:54: red as above; `BUILD-APP-EXIT 0`
  (0 errors, 37 warnings, none new), `BUILD-TESTS-EXIT 0`; the brief's 19
  classes **849 passed, 0 failed, 0 skipped of 849**, 43 s, `UndoWriterScanTests`,
  `UndoOpKindsContractTests` and `NamedGapLedgerTests` among them. HEAD-AFTER
  SAME, STATUS clean, LOCK-RELEASED (its own).
- `1055-W3-b`: see "Must-fail" and "Harness".

The guard's tests that remain and passed in run a: every test of
`UndoKeptPageUnderAVisibleNameTests` and `UndoThinningKeptCopiesTests` (neither
class was edited by this piece).

## Must-fail (`vm-tools/guest/1055-W3-mustfail.json`)

Run `1055-W3-b` (log `C:\vm-setup\1055-W3-b\run.log`, ref 6b14b5090, mode
mustfail,kinds), 18:02 to 18:06, each row applied alone, built (build=0), run,
and restored with `git checkout`; RESTORED 849 of 849 passed after. **2 of 3 RED.**

1. The handover exception left in `WholeOpsStandAlone` (a file move, a page
   removal or a new page may share its place): RED, 1 failed of 81,
   `UndoFormatTests.AStepThatHandsAPlaceOverIsUnreadable` (`Assert.False() Failure`).
2. `KeepPagesWhosePlaceIsTaken` returning at once: RED, 7 failed of 76 (both
   re-laid `EveryRecoveryCase` rows and `UndoKeptPageUnderAVisibleNameTests`
   among them, e.g. `ThePageKeptUnderAVisibleNameIsSaidBeforeTheCouldNotPutBackLine`,
   `ANameTakenIsSkippedNeverReplacedAndTheLineComesFirst`; `Assert.Equal()
   Failure: Collections differ`, the page not holding `Three.`).
3. `HandsOverAsAMove` returning false for a file's move: **NOT RED**, 101 of 101
   passed across `UndoRecoveryContractTests`, `UndoKeptPageUnderAVisibleNameTests`,
   `UndoThinningKeptCopiesTests` and `UndoRecoveryTests`. Every guard test that
   remains, and both re-laid rows, lay removals and new pages (`writeFile`), never
   a file's own `move`; the tests that laid a file move beside the guard were
   `UndoHandedOverPlaceTests`' (deleted here). No ordinary Windows action records
   a file `move` (above), so this half of the guard is reached by no step Windows
   makes today; left for the director (no test was added: it would be a new case
   beyond the brief).

## Harness

Run `1055-W3-b`, harness built (exit 0), each row outside OneDrive
(`C:\vm-setup\1055-W3-b\scratch`) and inside it (OneDrive running):
`w7-plain-kill` 3 of 3, `w7-make-room-kill` 12 of 12, `w8-carrying-move-kill`
36 of 36, failures 0, every result WHOLE, each exit 0 in both places: the same
results as W2's run `1055-W2-b`. Scratch folders removed; HEAD-AFTER SAME,
STATUS clean, LOCK-RELEASED (its own).

## Self-check

NIGHT3/W7b2/W8 COMMON, item by item:

1. Tests first: test 1 and the two rows seen RED on the PC at cb05a0d40 before
   any product change. Must-fail 2 of 3 RED; row 3 (`HandsOverAsAMove` false)
   turned nothing red (above).
2. No timed waits added; the PC run was waited for on its log's `RUN_DONE`.
3. Failure-path sentences: no teacher-facing sentence changed; the comments
   rewritten (`ReadWithoutFollowingALink`, `OpsToPutBack`, `HandsOverAsAMove`,
   `StaysInsideAbove`, `UndoActionStepLinkTests`' summary) say only what the code
   now does.
4. `origin/dev` merged before proving and before hand-back (both no-ops,
   ancestor).
5. No number tuned by trial.
6. Contract cases run from the JSON: the two rows are read by `name` from
   `undo.recoveryCases`; their values (paths, `stopAt`) are not retyped; the
   step's ops are the mac's call's, as `recoveryCasesHow` describes them.
7. (W7b2 7) No fixture row; the ledger hold is gone and no reason sentence named
   what was taught.
8. Writer scan: no writing call moved; `UndoWriterScanTests` green.
9. No riding lows were named beyond LOW M1-1 (done, above).
10. Not an action conversion.
11. Both re-laid rows pass and are out of the ledger; `Reason1055KeptPageReLaid`
    gone (no other row used it).
12. Key added: `withAPlainPageMove`; no held row carries it.
13. One function per rule: the guard's places come from `PlaceLeftBy`/
    `PlaceFilledBy`, which call `HandsOverAsAMove`; no new comparison was added.
14. No run left going, the lock released by its own run, no lock removed that
    this piece did not take.

## For documentation 12

Windows hands no place over (as the mac after #1055 M5): a step in which a whole
op shares a place with another op, a file's `move` beside a removal or new page
at its place included, is unreadable, a barrier; the only exception is U4b's
carried edit. The kept page under a visible name stays, judged from
`PlaceLeftBy`/`PlaceFilledBy` (a page removed or new, or a file's own move by
`sha`), and its two re-laid recovery rows run on Windows. The `w8b-handover-kill`
harness row is gone.

## For the director

Nothing parked. One owed: must-fail row 3 is not red; no remaining Windows test
pins `HandsOverAsAMove`'s file-move half (see "Must-fail").

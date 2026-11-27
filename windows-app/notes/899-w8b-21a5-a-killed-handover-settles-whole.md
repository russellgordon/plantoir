Removed by #1055 (2026-11-27): symbolic links in course content are not supported; no step hands a place over.

# #899 W8b-21a5: a killed step that hands a place over settles whole

Brief: `vm-tools/briefs/2026-11-27-899-w8b-21a5-a-killed-handover-settles-whole.md` (COMMON `2026-11-26-899-w8-COMMON.md`). Windows' copy of the mac's U4b3 door-5. Branch `issue/899-w8b-21a-handed-over-place`, worktree `wt-899-w8b-21a`, built on 21a4's head 186d224ad. `contracts/` untouched.

Commits: e53b8411a (tests first, the eight rows out of the ledger), f2c9d746e (the fix and the harness run), then the harness's comparison fix and these notes.

## For PROGRESS

- **The settle names each place as a plain path.** `UndoRecovery.PlacesShown(step)` (the mac's `placesShown`) maps each handing-over move's judged name (`PlaceJudged`, "from → to") to its own place (`PlaceName`). `Settle` uses it for the in-use and cannot-tell-now refusals' path, the `interrupted` line's `paths` (`PathsOnly`, each plain path once), the trail's counts (`InterruptedWords`, `CouldNotPutBackWords`) and `UndoRecoveryResult.FilesInTheWay` (`CountShown`, each shown path once). The put-back count stays the swap targets' count, as on the mac.
- **The door's vet.** `UndoDoor.Perform(UndoOpsDraft)` step 2 judges a file op of a handover with a link's move (`UndoOp.Handovers`, `ALinkMoves`) on the folders above its place only (`FirstPlaceLeadingOut(…, judgedOnTheFoldersAbove: true)`), as the mac's `JournaledWrite` does. The Undo/Redo plan check (`UndoDoor.cs`, "Every place inside the working folder … at the plan") judges a path in `ready.HandedOver` by `StaysInsideAbove`, as the plan judged it. This settles 21a4's "Left for the next piece": the example there (Day 3 a link to `C:\Elsewhere\Day 3.md`, moved to Day 4, a new Day 3) is now made, undone and redone on Windows (`AStepHandingOverALinkLeadingOutIsMadeUndoneAndRedone`).
- **Tests.** `UndoRecoveryContractTests` knows `withAHandedOverPlace` (shapes as `recoveryCasesHow` says, through the door for ops), `handedOver`, `handEdit handedOverPlace` (Someone else's at Day 3), and `files` before/after for such a step (section 1 and the library, every entry, compared with the same step made whole in a scribe of its own). The class pages and links are laid and read by the new `UndoHandoverForTheCases`, which the stack replay now calls too (one spelling). `UndoHandedOverPlaceTests`: `AStepHandingOverALinkLeadingOutIsMadeUndoneAndRedone`, `ASettleCountsAHandedOverPlaceOnce`, `AMoveThatHandsAPlaceOverIsShownByItsOwnPlace` (the last added with the fix, a pin of `PlacesShown`; it could not compile before it).
- **Harness.** `w8b-handover-kill` (`Plantoir.UndoHarness/W8bRuns.cs`): shapes A and B, the step, its Undo and its Redo, killed by a child process before each swap (A 2, B 4), recovered by a second process, live; links inside (relative, `..\library\…`) and leading out (full path); section 1, the library and the folder outside compared with the two whole states, nothing staged anywhere, the step settled the way the disk shows.

## For documentation 12

- The door-5 notes' paragraphs are built as written. The one Windows fact: Windows' door has a second vet the mac's has not, at Undo/Redo after the plan (`ready.InOrder` → `StaysInside`); it judges a handed-over file by the folders above it too, by the plan's own `HandedOver` set, so a Redo of a step handing over a link leading out is not refused `changedSince`.
- Of the eight door-5 rows, seven already passed on 21a4's product once the replay knew the key (21a3's re-judgement settles them); only the row "… naming Day 3 as a plain path …" was red (its `pathsNamed` held `from → to` and Day 3).

## Must-fail lines

`vm-tools/guest/899-w8b-21a5-mustfail.json` on the committed head f2c9d746e (run `w8b-21a5-a`). **RED 4 of 4**, restored by `git checkout` (`RESTORED` 393 of 393, `HEAD-AFTER` SAME, `STATUS` empty):

1. The settle names a move `from → to` (`string plain = place;`): the door-5 "plain path" row, `Assert.Equal()` Collections differ (1 of 87).
2. The vet at Perform resolves the handed-over place through the link (`aboveOnly = false`): `AStepHandingOverALinkLeadingOutIsMadeUndoneAndRedone`, "the step was refused: notReadable".
3. The plan check at Undo/Redo resolves it through the link (`false ? StaysInsideAbove`): the same test, "the Redo was refused: changedSince".
4. 21a3's re-judgement switched off (`handovers.Count < 0`): five door-5 rows, `Assert.Equal()` Strings differ (5 of 87). The harness was not run under this sabotage (one harness run per piece).

## Runs

- `w8b-21a5-a` (launcher `vm-tools/guest/899-w8b-21a5-launch-a.ps1`, `-Mode classes,mustfail,kinds -Harness w8b-handover-kill -RedRef e53b8411a`): lock 05:23:15, `LOCK-RELEASED`, `RUN_DONE` 05:28:53. Lenovo 20QES70500, i5-8365U, 16 GB, Windows 11 Pro 26200, Developer Mode on.
  - Red first on e53b8411a (build 0): 3 failing of 280: `ASettleCountsAHandedOverPlaceOnce` (`Assert.Equal()` values differ: 2 in the way, not 1), `AStepHandingOverALinkLeadingOutIsMadeUndoneAndRedone` (refused at Perform), and the door-5 "plain path" row (`pathsNamed`, Collections differ).
  - On f2c9d746e: both builds exit 0 (37 warnings, none new); **393 of 393 passed, 0 skipped**: `UndoRecoveryContractTests`, `UndoHandedOverPlaceTests`, `UndoRecoveryTests`, `NamedGapLedgerTests`, and the three scan classes `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`.
  - Harness, outside OneDrive and inside it: **72 kills** (36 each place: 2 link placements × (A: 3 ways × 2 swaps + B: 3 ways × 4 swaps)), every kill point reached, nothing staged left, every step settled. The 36 with links inside printed WHOLE. The 36 with links leading out printed NOT-WHOLE only because the harness compared a link's full target, which names each run's own folder, with the target in the run that made the whole states; re-judged from the logged `now=[…]`, `before=[…]` and `after=[…]` with the run folder normalised, **all 36 are whole and the way the list says** (step and Redo killed: before, as `Failed`/`RolledBack`/`Undone`; Undo killed: after, `Done`), the page outside untouched each time. The harness now writes such a target as `<run>`, so a later run reads WHOLE by itself (not re-run: one harness run per piece). Every RESULT line is in `C:\vm-setup\w8b-21a5-a\run.log` on the PC.
- `origin/dev` 6dc36fcea was an ancestor at the start and before hand-back: no merge needed.

## Self-check

- 11: the eight door-5 rows pass and are out of the ledger; `Reason899W8HandedOverPlace` now names only 21c's two kept-original-named rows and their keys (and the trail event row that shares it).
- 12: `withAHandedOverPlace` and `handedOver` added to `KeysChecked`; the two rows still held under the reason carry `keptPageLines`, which the replay still does not check, so they stop at "a key this replay does not check" (green in the run).
- 13: the door's vet calls `UndoPlaces.FirstPlaceLeadingOut(…, judgedOnTheFoldersAbove)` and `StaysInsideAbove`, the plan's own functions; the pairs come from `UndoOp.Handovers`; the shown name from `PlaceJudged`.
- 14: no run going, the lock released by the run that took it.

## Left for the next piece

- Nothing of door-5. For 21a6: the harness's links inside are spelled `..\library\…` (Windows); a mac-style link (`../library/…`) at a handed-over place with another target standing there reads CannotTell (21a3's notes), not tested here.

## For the director

- Nothing parked.

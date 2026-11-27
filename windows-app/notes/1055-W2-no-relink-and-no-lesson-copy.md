# #1055 W2: Windows has no relink and no lesson copy

Russell's rule (#1055, 2026-11-27): Plantoir reads and writes through a
symbolic link and has no other link code. This piece removes Windows'
relinking move (W8b 21b1 to 21b5, window E reviews 1 and 2) and the copy of a
lesson where a link cannot be made (21b1a). Nothing a teacher sees changes; no
`contracts/` file was touched.

Base: `origin/day27c/integration-2` 46fd45e70. `origin/dev` (412053b07) is an
ancestor of it, so both merges of `origin/dev` (before proving and before
hand-back) were no-ops: `git merge-base --is-ancestor origin/dev HEAD` true at
bc6755947 and again at the head handed back.

## What was removed, by the commit it came from

Done by reverting the relink commits' hunks one by one, newest first
(`git revert --no-commit` of 0c25650eb, 6bc055127, e7f4fc1dd, a20edfa56,
71b0ce501, a94d01639, 0cb77ef1c, c1365bd97, c4574263b, aee39138c, e4612963f,
0cc403a49), then putting back by hand what the KEEP list holds and what W8c
and #1055 M1 to M7 changed since. Each product file was then compared with
`dcbdb41d5`: `UndoJournal.cs`, `UndoJournalLocation.cs`, `UndoPlaces.cs` and
`UndoOpKinds.cs` are byte for byte `dcbdb41d5`'s; the others differ from it
only by W8c's hunks, `5b4045d9d`'s and the CannotLook guard.

- `UndoFormat` (21b1, 21b2): `LinkShaBefore`, `LinkShaAfter`, `IsARelink`, the
  relink half of `LinkText` and `IsALinksMove`, the `RelinkLink` factory, the
  reader's two keys, `RelinkShapeIsKnown` and its call. A move carrying the
  pair finds none of `sha`, `listingSha`, `linkSha` and is a barrier again.
- `UndoCheck` (21b1): `UndoRelink`, the per-side `isAtFrom` judging, the
  `Relink` of a swap target.
- `UndoSwap` (21b1, 21b3, 21b4, window E 1 and 2): `RelinkLink`,
  `IsOurStagedLink`, `RemoveOurStagedLink`, `MakeALink`, `LinkHolds`,
  `RemoveALink`, `UndoRelinkAnswer`, `UndoStagedLinks`, `UndoStagedOwner`,
  `WhoseIsIt`, `GiveBackOrKeepVisibly`, `IsARelinksOwnStagedName`, the seams
  `MakingALinkAnswers` and `CanMakeALinkAnswers`, the stop points
  `relinkStaged`/`relinkRenamedIn`, the relink branches of the swap, and the
  step overload `TidyLeftovers(step, root, trail, ...)` with its trail; the
  tidy is `dcbdb41d5`'s `TidyLeftovers(seq, paths, root, ...)` again, so an
  item under a staged name is judged as before 21b3 (a link there is removed
  by name as the link itself). `UndoStagedFile.RemoveByName`'s
  `asAFolderLink` parameter and `BackupSemantics` (only `RemoveALink` passed it).
- `UndoRecovery` (21b3, window E 1): `RemoveTheLinksJustMade`,
  `IsTheOneInFlight`, their call, `UndoLinkMoveRead` (only they read it), and
  `KeptVisibly` (see "Kept", below: its only caller was the relink tidy).
- `UndoActionStep` (21b1a, 21b5, window E 2): `RelinkLink`,
  `UndoRelinkPlanned`, `CopyTheLessonInsteadOfALink`, `CopiedInsteadOfLinks`,
  `SetAsideName` (`.<name>.link-kept-by-undo`), the copies list,
  `IsARelinkEndingAt` and its two clauses in `PlannedPlace` and
  `RefuseAWriteAtALinkMovedAway`, the `_folderMoves` tuple's two texts, the
  junction refusal.
- `UndoLinks` (21b1a, 21b5, window E 1 and 2): `ThisProcessCanMakeALink`,
  `CanMakeALink`, `CanMakeALinkIn`, `ProbeName`, `TextOf`, `TextToWrite`,
  `IsAFolderLink`, `IsAJunction`, `MountPoint`. `ReparseTag` stays.
- `UndoJournalLocation`, `UndoDoor`, `UndoJournal`, `UndoPlaces`: back to
  `dcbdb41d5` (the probe's sentence, the tidy calls, `op.LinkSha is null`).
- W8c's two calls of the step overload (`ef929a20e` in
  `UndoRestoreSetAside.cs`, `8b72ac865` in `UndoStoppedStep.cs`) call the
  seq overload again, as they did before they adopted 21b3's signature.
- Tests: `UndoRelinkTests.cs`, `UndoRelinkForTheCases.cs`,
  `UndoLinkCopyTests.cs` deleted (no other class used a helper of theirs;
  `SymbolicLinkFactAttribute` lives in `UndoLinkMoveTests.cs`).
  `UndoCheckContractTests` (the `linkTargetBefore`/`linkTargetAfter` branch of
  `OpOf`, `LaysALinkWithItsTarget`'s two keys, the two `PlaceAt` calls back to
  `op.LinkSha is not null`, the comment) and `UndoRecoveryContractTests`
  (`withARelink` in `KeysChecked`, its shape and its pages check) are
  `dcbdb41d5`'s again but for M-series lines. `UndoWriterScanTests.Allowed` is
  `dcbdb41d5`'s (`UndoOpKinds.cs` 11, `UndoSwap.cs` 26). `UndoLinkMoveTests`'
  and `UndoStackContractTests`' 21b hunks are a skip sentence's wording only
  ("a machine that cannot make links" for "the VMs"); kept as they are.
- Harness: `W8bRelinkRuns.cs` deleted; `Program.cs`' two modes and
  `W8bRuns.cs`' 21b hunk back to `dcbdb41d5`.
- Ledger: the comment naming `Reason899W8RelinkedLink` removed; no constant or
  row of that name remained (M3 removed them). No row moved.
  `Reason1055KeptPageReLaid` (W3's) untouched.
- The six 21b notes files each gained the line "Removed by #1055
  (2026-11-27): symbolic links in course content are not supported."

## Kept, and why (each by grep in `Plantoir.Core` at the head)

- `UndoCurrent.ReadWithoutFollowingALink` reading `CannotLook` as
  `CannotReadNow` (c4574263b's review 3 LOW 1), with its `look` seam and its
  test `APlaceThatCannotBeLookedAtIsCannotReadNowAndNeverReadThrough` (the
  21b hunk of `UndoKeptPageUnderAVisibleNameTests`: it is that test alone, so
  the whole class stays). The revert of c4574263b took it out; it was put back
  from the base by hand.
- `PartInside`'s NFC-normalised, lowercased parts and the normalisation-only
  rename (5b4045d9d): untouched.
- The 21c guard: `UndoRecovery.KeepPagesWhosePlaceIsTaken`,
  `UndoSwap.VisibleName`, `RenameToAVisibleName`, the trail event "undo kept a
  page under a visible name". **`UndoRecovery.KeptVisibly` is gone**, though
  the brief listed it: it came with 21b3/window E 1 and its only caller was
  the relink tidy's `GiveBackOrKeepVisibly` (`KeepPagesWhosePlaceIsTaken`
  writes the same trail line itself, as at `dcbdb41d5`).
- window E 1's "every tidy says what it keeps" and the probe sweep: gone with
  the relink, since a plain step's tidy never reached them (the trail went
  only to `KeptVisibly` for an item under a relink's staged name; the probe
  was only `CanMakeALinkIn`'s).
- `SpecialFolderRenamer.PlanRelinkedPages`, `PagesRelinked`,
  `SpecialNames.RenameRelinked*` (wikilinks): untouched.
- W4's: `UndoActionStep.MoveLink`, `LinkMoveEndingAt`, `LinkMoveStartingAt`,
  `StaysInItsFolder`, `IsLeftFreeByALinkMove`, `RefuseAWriteAtALinkMovedAway`,
  `PlannedPlace`'s link branch, `UndoFormat.LinkSha`, `UndoLinks.LinkSha`,
  `IsALinkToAFolder`, `UndoLinks.FileALinkLeadsTo` (now called only by
  `PlannedPlace`), `ReadALink`. W3's: `Handovers`, `IsHandedOver`,
  `UndoHandover`, `InHandingOverOrder`. `CourseConfiguration.FileALinkLeadsTo`
  untouched. `UndoLinks.ReparseTag` stays (`Look` reads it).

The done-means grep is empty for every name but `IsAJunction`, which matches
only `UnitPlansTests.AUnitFolderThatIsAJunctionIsNotAPlan`, a test from
before 21b about unit plans, not the removed function.

## Tests first

`UndoFormatTests.AStepWithARelinkingMoveIsUnreadable` (bc6755947, on the
base): not yet seen red: owed (queued in run `1055-W2-a`, `-RedRef bc6755947`).

## Runs (the PC, under `C:\vm-setup\wt-compare.lock`)

OWED. Run `1055-W2-a` (669ea3e3d: red on bc6755947, both builds, the 21 classes named in the brief) was started at 16:52 and is waiting inside its own script for the turn lock, which the director's whole-suite run `int-d27c-3` holds; the script takes the lock, runs, and releases only its own. Run `1055-W2-b` (must-fail and the four harness rows) is copied to `C:\vm-setup\1055-W2-launch-b.ps1` and not started. The writer handed back before either result (told to).

## Must-fail (`vm-tools/guest/1055-W2-mustfail.json`)

Three rows written (the barrier dropped; the tidy removing an only-copy kept original; `KeepPagesWhosePlaceIsTaken` skipped at both calls). Not yet run: owed (`1055-W2-b`).

## Self-check

1. Broke each change and watched a test fail: OWED (must-fail not yet run).
2. No timed waits where an event exists: none added; this piece only removes code.
3. Every sentence on the failure paths true: no failure sentence added or changed; the relink's were removed with it.
4. `origin/dev` merged in: yes, both times a no-op (412053b07 is an ancestor of the base).
5. No number tuned by trial: none; the writer-scan counts are `dcbdb41d5`'s (11 and 26), unproven until the run.
6. Contract cases run from the JSON: unchanged; no case retyped.
11. No held row taught; the one dead ledger comment went. 12. No key added. 13. No new comparison. 14. Run `1055-W2-a` left queued on the PC under its own lock wait (it releases only its own lock); no lock taken or removed by hand.

## For documentation 12

Windows has no relinking move and no copy of a lesson in place of a link: a
journal line whose move carries `linkShaBefore`/`linkShaAfter` is unreadable,
a barrier, as on the Mac after M4; the swap never makes, renames in or removes
a link; recovery never removes a link it made; the tidy judges an item under a
staged name as before W8b-21b3. A link's plain move, the handed-over place and
the kept page under a visible name are untouched (W4, W3, 21c).

## For the director

Nothing parked.

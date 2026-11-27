# #899 W8b-21a3: recovery judges each op of a handed-over pair as the other leaves the place

Brief: `vm-tools/briefs/2026-11-27-899-w8b-21a3-recovery-judges-a-handed-over-place.md` (COMMON `2026-11-26-899-w8-COMMON.md`, order `2026-11-27-899-w8b-ORDER.md`). Windows' copy of the mac's U4b3 door-3. Branch `issue/899-w8b-21a-handed-over-place` (one branch for 21a1 to 21a6 and 21c), worktree `wt-899-w8b-21a`, built on 21a2's head 485d44542. `contracts/` untouched. Still inert: no readable step holds a handed-over place (21a4 makes one readable).

Commits: 53cecb7b6 (the put-back choice, the list-holds test by blob and the pair's judging named as functions, no change of behaviour: `JudgedTogether` a stub that judged each op once), 4aa4e4fef (tests first), a0d1f0e6d (the fix), 58b1beec9 (shape B's other-target link laid with Windows' separator, see Runs).

## For PROGRESS

- **`UndoRecovery.FileStates`** now judges every op once by index, then hands the pairs to `JudgedTogether` (the pairs from `UndoOp.Handovers`, the one finder): when the filler stands AFTER, the leaver is judged again with the place free (a move through `WholeStateOf(..., fromIsHandedOver: true)`, a file op from `Absent`, never read); when the leaver stands BEFORE, the filler is judged again with the place absent (a move through `toIsHandedOver: true`, a file op from `Absent`). Repeated until nothing changes, at most `ops.Count + 1` rounds, and each op at most once on each side (`fromIsFree`, `toIsFree`, `isAbsent`, the mac's `freeFrom`, `freeTo`, `absentHere`). A place holding something neither op recorded leaves both neither (no re-judgement is triggered).
- **The per-place name.** A move that leaves or fills a handed-over place (`MovesHandingOver`) is named `from → to` (`PlaceJudged`, the mac's `placeJudged`), never its origin, which is the path of the file op at the same place. `OpsToPutBack` (lifted out of `Settle`) chooses the ops to put back by that same name. Every other op keeps its `PlaceName`, and the page order and its duplicate rule are as before (a page keeps its own seen set, as the mac's `pathsSeen`).
- **The only-copy test.** `ListHolds` plans a page's op together with the other op of its pair, in the step's order (a `SortedDictionary` by op index), and, only when a partner joined, with `UndoWholeReads(root, UndoAppSettingsPlaces)` so the move is read as a whole. Without a partner the plan is called exactly as before. A new overload takes the list's content by `blob` (the journal's overload calls it).
- **Tests** (`UndoHandedOverPlaceTests`, 25 to 36): `RecoveryJudgesShapeAAtEachPoint` and `RecoveryJudgesShapeBAtEachPoint` (`SymbolicLinkTheory`, the brief's two truth tables, every row, by `FileStates` on laid folders); `AMoveThatHandsAPlaceOverIsNamedByItsTwoPlacesAndPutBackByThatName`; `AKeptOriginalIsTestedAsAnOnlyCopyWithThePagesOpPlannedWithItsPair` (and one holding anything else stays an only copy); `EachOpOfAPairIsJudgedAgainAtMostOnce` and `AChainOfPlacesIsJudgedAgainUntilNothingChanges`, on `JudgedTogether` with a counting judge that throws past 100 calls (the loop guard).

## For documentation 12

The mac's door-3 "For documentation 12" section (`windows-app/notes/899-u4b3-door-3-recovery-judges-a-handed-over-place.md`) is built on Windows as written, with these Windows facts:

- "At most once per op" is, as on the mac, once per op on each side: a move in a chain (it fills one place and leaves another) may be judged again once with its `to` free and once with its `from` free.
- A file op at a handed-over place whose page now leads out of the folder (a link leading out standing there) is read through nothing and judged neither first, as every page is; the re-judgement from `Absent` then settles it like any other.
- The name `from → to` reaches `inTheWay`, `endPaths` and the `interrupted` line as it stands; showing the plain path to a teacher and on the trail is door-5 (`placesShown`), 21a5's.

## Must-fail lines

`vm-tools/guest/899-w8b-21a3-mustfail.json`, run by `899-w8b-21a-pc-run.ps1` mode `mustfail` on the committed head a0d1f0e6d:

RED 3 of 3 (run `w8b-21a3-a`, 2026-11-27 04:41 to 04:45 on the PC; restored byte for byte by `git checkout`, `HEAD-AFTER` SAME, `STATUS` empty):

- M1, no re-judgement (the rounds loop never entered): 8 of 36 failing, among them shape A's "P free, link at Q" and "new at P, link at Q" and shape B's rows, `Assert.Equal()` collections differ (the leaver or filler left neither).
- M2, the once-per-op limit removed from the leaver's re-judgement: 3 failing, `EachOpOfAPairIsJudgedAgainAtMostOnce` and `AChainOfPlacesIsJudgedAgainUntilNothingChanges` (the calls counted past 2), and a shape B row.
- M3, the move named by its origin alone (`PlaceJudged` never sees a handing-over move): 9 failing, both tables' rows and `AMoveThatHandsAPlaceOverIsNamedByItsTwoPlacesAndPutBackByThatName` (one entry where two were expected).

(The restored run in `w8b-21a3-a` showed the one test failure the fix run showed, below; it is the test fixed in 58b1beec9, not a sabotage left behind.)

## Runs

- `w8b-21a3-a`, `899-w8b-21a-pc-run.ps1 -Mode classes,mustfail -RedRef 4aa4e4fef` (launcher `vm-tools/guest/899-w8b-21a3-launch-a.ps1`): queued behind `int-d27-8`'s lock from 04:27, took the lock at 04:40:59, `LOCK-RELEASED`, `RUN_DONE` 04:44:57.
  - Red first on 4aa4e4fef: `UndoHandedOverPlaceTests` failed 12 of 36, every new test (8 theory rows, the name and put-back test, the kept-original test, the two `JudgedTogether` tests), each `Assert.Equal()` collections differ or `Assert.True()` (the kept original).
  - On a0d1f0e6d: both builds exit 0 (37 warnings, none new); 381 of 382, the one failure shape B's "a link with another target at P": the removal judged `CannotTell`, not neither. The test's link was laid mac-style (`../library/Another day.md`), which NTFS does not follow, so reading the page through it is `CannotReadNow` (21a1's note). The test now lays that link with Windows' separator (58b1beec9) so the row tests the table; the mac-style case is under "For the director".
- `w8b-21a3-b`, `-Mode classes` on 58b1beec9 (launcher `899-w8b-21a3-launch-b.ps1`): lock 04:46:40 to `RUN_DONE` 04:48:32, `LOCK-RELEASED`. Both builds exit 0; **382 of 382 passed, 0 skipped**: `UndoHandedOverPlaceTests` 36, `UndoRecoveryContractTests`, `UndoRecoveryTests`, `NamedGapLedgerTests`, and the three scan classes `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`. The PC has Developer Mode on, so every `SymbolicLink` test ran.
- `origin/dev` 8046ca2e8 was an ancestor at the start. Before hand-back `dev` had moved (W8b 17 to 18b, the day27-7 gate fixes, `UndoOpKinds.cs` among them): merged cleanly in e2597eb03, then proved again, `w8b-21a3-c` (`899-w8b-21a3-launch-c.ps1`, `RUN_DONE` 04:59:23, `LOCK-RELEASED`): both builds exit 0, **382 of 382**, the same classes.

## Left for the next piece

- 21a4: `ShapeIsKnown` still refuses a step with a handover, so `Settle` never meets one; nothing in recovery's judgement waits.
- 21a5: the teacher-facing and trail name of a handed-over move (the mac's `placesShown`, door-5) is not built: `Settle`'s `CannotTellNow`, `FileIsInUse`, `inTheWay` and `interrupted` paths would carry `from → to` today. Recovery contract rows (door-5) clear there.

## For the director

Nothing for Russell. One fact for 21a4 and 21a6: recovery reads a file op's page at a handed-over place by following what stands there, as every page is read. A mac-style link (`../library/Day 2.md`) standing at P is not followed on NTFS, so the page reads `CannotTell`. Where the pair's re-judgement then reads the page as absent (the filler after, or the leaver before), the result is the table's. Where nothing re-judges it, a mac-style link with ANOTHER target at P makes recovery leave the step to try again (`CannotTellNow`) instead of judging it changed by hand (neither). Example: shape B, a removal at Day 3 then a link's move from Day 2 into it, killed, and the teacher has since put a link to `../library/Another day.md` at Day 3 and taken Day 2's link away. The mac judges neither/neither; Windows tries again on every recovery. This is the same following-a-mac-style-link question 21a1 left for 21a6. Recommendation: 21a6, which reads through a link's new place, settles how a file op at a handed-over place reads a link standing there (judged as a link, never followed: then neither, as on the mac).

## Self-check

1. Broke each fix and watched it fail: must-fail 1 to 3 above.
2. No timed waits in product or test.
3. Failure paths: no new sentence; the states are the existing ones.
4. Merges: `origin/dev` 8046ca2e8 already an ancestor at the start; the moved `dev` merged in e2597eb03 before hand-back and proved there (382 of 382).
5. No number tuned by trial (the round limit is the mac's `ops.Count`).
6. House style: the C# around it.
7. (W7b2 7) No fixture row moves; `NamedGapLedgerTests` green.
8. (W7b2 8) No writing call moved; `UndoWriterScanTests` green.
9. (W7b2 9) No riding lows named.
10. (W7b2 10) A step with no handover is judged and named as before (the page order and its duplicates kept; `UndoRecoveryTests` and `UndoRecoveryContractTests` green).
11. No held row was this brief's; the ledger is untouched.
12. No `KeysChecked` key added.
13. One function per rule: the pairs by `UndoOp.Handovers`; judged together by `JudgedTogether`; named by `PlaceJudged`; chosen by `OpsToPutBack`; the move's sides by `WholeStateOf`'s two flags.
14. No run left going, no lock left held, no lock removed that was not this run's (both runs released only their own).

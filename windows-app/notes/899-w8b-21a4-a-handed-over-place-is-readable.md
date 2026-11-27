# #899 W8b-21a4: a step that hands a place over is readable

Brief: `vm-tools/briefs/2026-11-27-899-w8b-21a4-a-handed-over-place-is-readable.md` (COMMON `2026-11-26-899-w8-COMMON.md`, order `2026-11-27-899-w8b-ORDER.md`). Windows' copy of the mac's U4b3 door-4. Branch `issue/899-w8b-21a-handed-over-place`, worktree `wt-899-w8b-21a`, built on 21a3's head e82be81c4. `contracts/` untouched.

Commits: 37a2e06ba (tests first, and the seven rows out of the ledger), 06a064cb4 (the fix).

## For PROGRESS

- **`UndoStep.WholeOpsStandAlone`** (the step's whole-ops check, called by `ReadStep`) now accepts exactly the pairs of `opKinds.wholeOps`' second exception, as the mac's `UndoStep.wholeOpsStandAlone`: the pairs come from `UndoOp.Handovers` (the one finder); if there is any pair, a step that carries an edit (`UndoCheck.Carriers`, U4b) or hands one place over twice (`UndoOp.PartInside(…) is ""` between two pairs' places) is refused; in the overlap test, an overlap is passed over only by `IsHandedOver` (the mac's `isHandedOver`): both places exactly the pair's place, between exactly that pair's two ops. Everything else refuses as before, so a filler before its leaver, a folder's move whose place is then written, and a third op at, inside or above the place are refused with no rule of their own.
- With 21a1 to 21a3 in, such a step now plans, swaps and recovers through the door: the five stack rows that take one through Undo and Redo pass on the PC.
- **Tests.** `UndoStackContractTests`: the key `handedOver` (`StackReplay.HandedOver`) and the calls `handAPlaceOverAfterALinksMove`, `handAPlaceOverBeforeALinksMove`, `editTheHandedOverPageByHand`, `stepFillingAPlaceBeforeItIsLeft`, `stepHandingOverAFoldersPlace`, made as `stackCasesHow` says; the two calls that lay a link are among `LinkCases` (`SymbolicLinkTheory`, skipped where no link may be made). The links hold `../library/Day <n>.md` as written, forward slash kept, as the mac writes them; nothing follows them. `UndoHandedOverPlaceTests`: `AStepThatHandsAPlaceOverIsReadable` (shapes A and B), `AFillerBeforeItsLeaverIsNotReadable`, `AFoldersPlaceWrittenAfterItsMoveIsNotReadable`, `APlaceHandedOverTwiceIsNotReadable` (two removals of Day 3 then a file's move in: two pairs at one place that the overlap test alone would pass, because the two removals are not whole ops), `AThirdOpNamingAHandedOverPlaceIsNotReadable` (at, inside, above), `ACarryingMoveWithAHandoverIsNotReadable`.

## For documentation 12

- The mac's door-4 "For documentation 12" (`899-u4b3-door-4-*.md`) is built as written. The one Windows fact: "two pairs name the same place" can matter on its own only when the leavers are not whole ops (two removals handing one place to one move); in every other shape the overlap test already refuses it. Both are kept, as on the mac.
- The brief and the door-4 notes call the check `UndoFormat.ShapeIsKnown`; on Windows the step-level check is `UndoStep.WholeOpsStandAlone` (in `UndoFormat.cs`), and `ShapeIsKnown` is the per-op one, unchanged.

## Must-fail lines

`vm-tools/guest/899-w8b-21a4-mustfail.json`, run by `899-w8b-21a-pc-run.ps1` mode `mustfail` on the committed head 06a064cb4 (run `w8b-21a4-a`). **RED 4 of 4**, restored byte for byte by `git checkout` (`HEAD-AFTER` SAME, `STATUS` empty, the restored run 665 of 665):

1. Every overlap passed over once there is a pair (`!IsHandedOver(…)` → `handovers.Count == 0`): `AThirdOpNamingAHandedOverPlaceIsNotReadable`, all three rows, `Assert.False()` failure.
2. Two pairs at one place accepted: `APlaceHandedOverTwiceIsNotReadable`, `Assert.False()` failure.
3. A carrying move with a handover accepted (`Carriers(ops).Count < 0`): `ACarryingMoveWithAHandoverIsNotReadable`, `Assert.False()` failure.
4. A filler before its leaver accepted (the finder looks before the leaver too, `fillerIndex = 0`): `AFillerBeforeItsLeaverIsNotReadable` (`Assert.False()` on the shape line) and the stack row "a place filled before it is left" (`Assert.Equal()` values differ).

## Runs

- `w8b-21a4-a` (launcher `vm-tools/guest/899-w8b-21a4-launch-a.ps1`, `-Mode classes,mustfail -RedRef 37a2e06ba`): lock 05:08:16, `LOCK-RELEASED`, `RUN_DONE` 05:12:35.
  - Red first on 37a2e06ba: 6 failing of 191 (`UndoHandedOverPlaceTests`, `UndoStackContractTests`): `AStepThatHandsAPlaceOverIsReadable` (line 231, `Assert.True()`), and the five "U4b3 door" rows that go through Undo and Redo (`WalkTheCase` lines 122 and 123, head and redo null: the step was a barrier; row 5 inside `Call` at line 710). The two barrier rows passed red, as they must: they were held only for their unknown calls.
  - On 06a064cb4: both builds exit 0 (37 warnings, none new); **665 of 665 passed, 0 skipped**: `UndoHandedOverPlaceTests`, `UndoFormatTests`, `UndoCheckContractTests`, `NamedGapLedgerTests`, and the three scan classes `UndoWriterScanTests`, `UndoOpKindsContractTests`, `UndoStackContractTests`. Developer Mode is on, so every `SymbolicLink` test ran.
- `origin/dev` 6dc36fcea was an ancestor at the start and still was before hand-back: no merge needed.

## Left for the next piece

- 21a5: the plain path shown for a move that hands a place over (`placesShown`), the recovery key `withAHandedOverPlace`, the harness kills, and the eight door-5 rows.
- 21a5 should know: `UndoDoor.Perform(UndoOpsDraft)` checks each op's places with `UndoPlaces.FirstPlaceLeadingOut(root, op)` with no `judgedOnTheFoldersAbove`, and the Undo/Redo plan check (`UndoDoor.cs` about line 532) uses `StaysInside(root, path)` on every place in `ready.InOrder`. The mac's door (`JournaledWrite.swift` about 520) judges a file op at a place a link's move hands over on the folders above only. On Windows a link holding `../library/…` (mac style) cannot be followed, so it reads as inside and the five rows pass; a link spelled with Windows' separator and leading OUT of the working folder would make the door refuse a new page at its handed-over place (`NotReadable`), where the mac takes it. Example: Day 3 a link to `C:\Elsewhere\Day 3.md`, the step moves it to Day 4 and writes a new page at Day 3: the mac makes the step, Windows refuses it. The door-5 row "a link leading out" is where this shows; not built here (one invariant).

## For the director

Nothing for Russell. Nothing parked beyond the fact above for 21a5.

## Self-check

1. Broke each rule and watched it fail: must-fail 1 to 4 above.
2. No timed waits in product or test.
3. Failure paths: no new sentence; a refused shape is the existing `unknown.unreadableStep`.
4. Merges: `origin/dev` 6dc36fcea an ancestor at the start and at hand-back.
5. No number tuned by trial.
6. House style: the C# around it.
7. (W7b2 7) No fixture row; `NamedGapLedgerTests` green.
8. (W7b2 8) No writing call moved; `UndoWriterScanTests` green.
9. (W7b2 9) No riding lows named.
10. (W7b2 10) A step with no handover is checked exactly as before (the overlap test unchanged when `Handovers` is empty).
11. The seven "U4b3 door, …" stack rows pass and are out of the ledger; `Reason899W8HandedOverPlace` rewritten to name only what 21a5 and 21c still owe (no other reason named the calls or the key taught).
12. `handedOver` added to the stack replay's `KeysChecked`: no stack row still held carries it (the recovery rows that carry it are the recovery replay's, its own `KeysChecked`, unchanged).
13. One function per rule: the pairs by `UndoOp.Handovers`; "same place" by `UndoOp.PartInside`; the carried edit by `UndoCheck.Carriers`; the pass-over by `IsHandedOver`.
14. No run left going, no lock left held, no lock removed that was not this run's (the run released only its own).

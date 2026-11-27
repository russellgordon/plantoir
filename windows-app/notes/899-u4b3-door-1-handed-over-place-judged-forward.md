# #899 U4b3 door-1: going forward, a handed-over place is judged free for its filler

Brief: `vm-tools/briefs/2026-11-26-899-u4b3-door-1-handed-over-place-judged-forward.md` (chain: `2026-11-26-899-u4b3-ORDER.md`). Branch `issue/899-u4b3-linked-class-page-moves-its-link`, worktree `wt-899-u4b3`, from c06d0bc87. `contracts/` untouched. Inert: no step readable today holds a handed-over place (`UndoStep.wholeOpsStandAlone`).

## For PROGRESS

- `UndoCheck.handovers(in:)` (new, `UndoCheck.swift`) names each handed-over place of a step, in op order, as `UndoHandover` (place, leaver index, filler index, whether a link moves). A LEAVER is a file's or a link's `move` (its `from`) or a `writeFile` that removes (`beforeSha` set, `afterSha` nil); a FILLER is such a move (its `to`) or a `writeFile` that makes a new file (`beforeSha` nil, `afterSha` set). The filler comes later, the place is the same place by `UndoOp.partInside(...) == ""` (part by part, no regard to case), at least one of the two is a move, and a move hands over only when it is a `move` with `sha` or `linkSha`: never `listingSha`, never `isCaseOnlyMove`, never `moveApart` or `setAside`. Each leaver hands its place to the FIRST filler after it.
- `UndoCheck.plan`, going forward only (`direction == .forward`; going back is door-2):
  - The filler is judged with the place FREE when its leaver is a change of this plan, meaning the leaver was not found already as wanted (`opsNotChanged`, set where the verdict is `alreadyBack`/`alreadyRedone`). A file filler's `original`/`working` are `.absent` without reading the disk. A move filler goes through `UndoCheck.wholeState(..., toIsHandedOver: true)`, where its `to` side is `.free`. When the leaver was skipped (already done), the disk is read as before.
  - The order: a step with no handed-over place keeps today's order byte for byte (`leadingTargets`, then the files in `pathsInOrder`, then `wholeTargets`). A step with one goes through `UndoCheck.targetsInTheStepsOrder`: every target is placed by its op's index in the step (a file target by the first op naming its path), and the order is stable within one op. So every filler's change comes after its leaver's.
  - Leaves the folder: a file op in a handover where either op is a LINK's move is judged on the folders above its place only (`placeLeavingTheFolder(..., judgedOnTheFoldersAbove: true)` → `UndoPlaces.staysInsideAbove`, factored out of `staysInside(_:_:namedBy:)`), and its target carries `UndoSwapTarget.handedOver = true`.
- `UndoSwap.swap`: the look before STAGING (`placeLeadingOut(target, root:, atStaging: true)`) judges a `handedOver` file target on the folders above only, because the link leaving the place, or arriving at it, still stands there and is never written through. Staging such a target does not `stat` the place (stat follows a link), so the new file gets the default mode 0644, the mode any new file gets. The look before each CHANGE is unchanged and judges the place whole. In op order the leaver has gone by then, so the place is either empty or holds whatever someone put there since. `swapAFile`'s own last look (the place must hold `expected`, which is absent here) is what refuses a place filled since.
- Why `toIsHandedOver` and not an empty `overridingTo` entry: `overridingTo` is keyed by paths INSIDE a moved place and holds what U4b's carried edits leave there, so an entry at "" for "the move's own place is free" would read as a carried edit at the move's place, and the two could be confused in U4b's code. A flag has one meaning only.
- Tests: `UndoHandedOverPlaceTests`, section "Going forward (door-1)", 10 tests. They cover shapes A, B and C with the links inside and leading out (6), a place filled after the link left (1), the link replaced between plan and swap (1), and two inertness tests (2).

## For documentation 12

Windows' `UndoCheck.Plan` must do the same for a handed-over place (definition in the brief, word for word in every door brief). Built from what is written here, without the Swift:

1. Find the step's handovers before judging: for each op that LEAVES a place (a file's or a link's move away from it, or a `writeFile` with a before-hash and no after-hash), the first LATER op that FILLS the same place (a file's or a link's move into it, or a `writeFile` with no before-hash and an after-hash). Compare places part by part, ignoring case, exact place only. At least one of the pair must be a move, and a move counts only if it is a plain `move` with `sha` or `linkSha` (never a folder's `listingSha`, a capitalisation-only move, `moveApart` or `setAside`).
2. Going forward, when judging the filler and its leaver has not been skipped as already done: a file filler starts from "absent" instead of reading the disk, and a move filler's destination side counts as free.
3. In a step with at least one handover, order the swap targets by the op each comes from (a file target at the first op that names its path), keeping the given order within one op. Every other step keeps today's order exactly.
4. A file op in a handover where either op is a link's move: the plan's leaves-the-folder check and the swap's look before STAGING (`UndoSwap`) resolve only the folders above the place, never the place itself, because the link standing there is leaving or arriving. Do not read the place's file mode through the link when staging. The look before each change still resolves the place whole.

The Windows door piece for this is the director's to add to the W8 ORDER. No contract row changes here, so Windows has no row to hold yet.

## For documentation 09 (folded by door-4)

Paragraph I would add: "U4b3 door-1: a handed-over place, going forward. When an earlier op of a step leaves a place (a file's or a link's move away, or a removal) and a later op fills it (a move in, or a new file), at least one a move, the check judges the filler against the place free, provided the leaver is a change of the same plan, and puts the filler's change after the leaver's by ordering such a step's changes as its ops run. A file change at a place a link leaves or fills is judged at the plan and before staging on the folders above it, since the link standing there is moving, never written through; before the change itself the place is judged whole, and a file put there since is refused `changedSince`. Every step readable before door-4 is planned as before."

## Must-fail lines

Recorded in `windows-app/notes/899-u4b3-door-1-mustfail.log`, each sabotage in place, built, run, restored with `git checkout` (git diff clean after each):

- M1: the filler read from the disk again.
- M2: today's order kept for a step with a handed-over place.
- M3: `handedOver` ignored at staging.
- M4: the step's order applied to every step.

RED 4 of 4. M1: shape A (and both refusal tests) refused `changedSince` Day 3 at the plan. M2: shape A targets came Day 3 then Day 4, and the swap was refused `changedSince` Day 3 (the write found the link). M3: shapes A and B leading out refused `changedSince` at Day 3 and Day 2 at staging. M4: the readable step came b.md, d.md, New, New/a.md instead of New, b.md, New/a.md, d.md.

## Runs

- Red first, on the base sources (c06d0bc87 with only the new test file; the two `handovers` assertions commented out so it builds): 10 tests, 9 failing. The 8 shape and refusal tests were refused at the plan ("changedSince" at Day 3 for A, at Day 2 for B and C). The filler-first pin was written as `cannotTellNow` and failed: today's answer is `changedSince` Day 3, and the pin now says that. The readable-step test passed, as an inertness test should; its must-fail is M4.
- Green: `UndoHandedOverPlaceTests` 10 of 10. The one failure on the first green run was `testAPlaceFilledSinceTheLinkLeftIsRefused` finding the new page's staged file left behind. That is how `notPutBack` behaves: it never tidies and leaves everything for recovery. The test now pins that file.
- Proof: `UndoHandedOverPlaceTests`, `UndoRenameFolderStepTests`, `JournaledStepTests`, `UndoJournalContractTests`, `UndoFilesContractTests`, `UndoDoorGuardTests`, `UndoWriterScanTests`, `UndoOpKindsTests` (added: `wholeState` changed): 168 tests, 0 failures. There is no `UndoCheckTests` class. The only test reading `UndoCheck.swift` as text is `UndoWriterScanTests`.
- `origin/dev` was 253f8915f at the start and again before hand-back, already an ancestor of the branch: no merge commit was needed either time.

## Left for the next piece

- door-3 (recovery): `testAPlaceFilledSinceTheLinkLeftIsRefused` ends `notPutBack(changedSince Day 3)`. The link is at Day 4 and cannot go back over the file someone put at Day 3, and the new page's staged file is left beside Day 3. Nothing is lost or written through. Recovery of such a step is door-3's.
- The brief's "everything is put back (the link at Day 3, Day 4 free)" holds when the place is taken BEFORE the swap starts, that is, the link itself replaced between the plan and the swap (`testALinkReplacedBeforeTheSwapIsRefusedAndNothingChanges`: refused `changedSince` Day 3, nothing changed). Once the link has left, a file put at its place can only be refused and left for recovery, so both cases are tested.

## For the director

Nothing parked.

## Self-check

1. Broke each fix and watched it fail: M1 to M4 (log). The inertness pin of today's refusal is a pin, not a fix.
2. No timed waits: none in product or test. The kill-point hook writes the intruding file on an event (`fileInUseAtSwap`).
3. Failure paths: no new sentence. The refusals are the existing `changedSince`, named at the handed-over place.
4. `dev` merged: `origin/dev` 253f8915f was already in the branch at both points, so no merge commit.
5. No number tuned by trial.
6. House style: no `map`/`filter`/`reduce`/`$0`/`DispatchQueue` in my lines, and MARK sections are in `UndoHandover` and the test class. Nothing outside the brief's scope changed. `contracts/` untouched.
7. grep over the changed Swift for `DispatchQueue|.map {|.filter {|.reduce(|$0` is empty for my lines.
8. No riding lows.
9. The rename record is still kept and the switch is still off (not touched).
10. No contract row is new or changed.

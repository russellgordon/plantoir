# #899 (Mac): a whole-course restore settles a step that stopped part way

Base `origin/issue/899-settings-sweep-follow-up` (b76065661), `origin/dev`
(8046ca2e8) already contained.

## What landed

`UndoRestoreSetAside.setAsideStepsInFlight` (Models/Undo), called by
`CourseRestorer.restoreBackup` after the caller's last refusal
(`beforeTheSwap`) and immediately before anything moves. Restore Course in
the start-of-year sheet and Restore from Backup… both reach it through
`WorkspaceModel.restoreBackup`. Inside the list's own lock, every step in
flight that was made in this working folder (its identifier) and names a file
under `courses/<CODE>` is closed `interrupted`, reason `setAsideByARestore`,
with every file it names, and no clearing. That is how pruning closes a step
it can never settle (`unsettled`). Its staged files are tidied (live only),
keeping any kept original that is the only copy. One trail line per step:
`undo set aside a change a restore replaced`. Steps of other courses and
other working folders are not touched. Nothing is shown to the teacher.

Why `interrupted` and not `failed`: it has to be true of the disk whichever
way the restore goes. If the restore finishes, the step's files are the
backup's, which the step never recorded ("unknown"). If the restore fails part
way and puts every file back, the files are as the stopped step left them,
possibly partly made ("partly applied"). `failed` would claim nothing took
effect, and that can be false.

Why there is no clearing: a clearing would take every course's steps, those in
flight included. The earlier steps of the restored course stay on the list, as
a restore has always left them (neither #909 nor #873 touches the list). An
Undo of one of them checks its files by content and refuses (and clears) when
the restore changed them. That is the list's rule for a file changed by hand.

## Contract

- `shared-rules.json` → `activityTrail.mustRecord`: the new event.
- `file-formats.json` → `undoJournal` line `reason`: `setAsideByARestore`
  added to `interrupted`'s words (readers never act on a reason).
- Held for Windows in `NamedGapLedger.cs`
  (`Reason899RestoreSetsAsideAStoppedStep`, under `ActivityTrailEvents`).

## For Windows

Do the same thing in the staged whole-course restore (#873), just before the
first move, inside the Undo lock: close each step in flight in that course as
`interrupted`/`setAsideByARestore` with its paths, with no clearing, tidy its
staged files the way pruning does, and write the trail line. If the lock
cannot be had, write the line's "could not be reached" form and leave the
step alone.

## For U5

U5 makes the restore itself a step. Write that step's `begin` in the same lock
as this set-aside, so nothing can start in the course between the two. The
lock is not held across the swap (the unpack can take minutes, and every
other door would wait). A live process's step is set aside too: the restore
already refuses while another program's session is open on the course
(#458), so a step still in flight there is one that stopped.

## Round two (the coordinator's follow-up)

- One-section restore: built. `swapSectionInPlace`, which the menu's and
  the assistant's one-section restores share, sets aside the steps that lie
  WHOLLY inside `courses/<CODE>/section<N>` plus the section's outside files
  it moves, before its first move.
- The rule changed for both kinds of restore. A step is set aside only when
  every file it names is inside what the restore replaces. A step only
  PARTLY inside is left in flight, as before. No rule of the list settles
  this case: `undo.rule.recovery` judges a step file by file but assumes
  nothing replaced its files, and `undo.rule.clearing` speaks only of
  changes by hand. So nothing is set aside for it, and today's behaviour is
  pinned by a test.
- Example of a partly-inside step (PARKED for a ruling): Get Ready for
  section 1 stops part way. Its step names section 1's class pages and the
  shared page `courses/ICS3U/index.md`, whose `publishForSection1` key it
  set. The teacher then restores section 1 only. The section's pages become
  the backup's, the shared page's body stays, and its per-section key is
  restored. The step stays in flight, and recovery later judges it against
  the restored section, which is the original fault for that half. A
  whole-course restore of a step that also names a file outside the course
  is the same case (none is known today).
- The three owed tests are built in `UndoRestoreSetAsideRestoreTests`. The
  settings step is a Course Settings save killed after its swap and before
  `applied`, which is the state Not Now leaves (file new, step open). This
  stands in for the unreadable outcome, which needs the window.
- A restore that fails part way, every file put back: the step is
  `interrupted`. That is true of the disk, because the course again holds
  what the stopped save left. Recovery never writes over it (the test
  checks every byte).

## Must-fail log, round two (each break run on its own)

| Break | RED |
|---|---|
| the one-section set-aside call skipped | testAOneSectionRestoreSetsAsideOnlyAStepWhollyInsideTheSection (the section's step left begun) |
| `liesInside` back to "any file inside" | the same test (the partly-inside step set aside) |

The one-section test was also RED on the round-one head (4aa5f8ae2), before
any one-section code. The three whole-course tests prove round one's fix: they
passed on 4aa5f8ae2 apart from one wrong assertion of the test's own (it
compared the backup with a course that keeps `.git` in place), now fixed.

Proof: the round-one four, the new class and every restore class touched
(AssistSectionRestoreTests, CourseRestorerStagedTests, CourseRestorerTests,
OneSectionRestoreContractTests, OneSectionRestoreOrderTests,
OneSectionRestoreTests, SectionRestoredTrailTests): 137 of 137 green after
`origin/dev` was merged.

## Must-fail log (each break run on its own, UndoRestoreSetAsideTests)

| Break | RED |
|---|---|
| the set-aside call in `CourseRestorer.restoreBackup` skipped | testAStepStopped…: in flight after the restore 1≠0, no trail line, in flight after recovery 1≠0 |
| the working-folder identifier not compared in `liesInside` | testOnlyStepsInsideWhatTheRestoreReplacesAreSetAside |

2 of 2 RED; the tree was restored by copy after each break.

Proof: UndoRestoreSetAsideTests, StartOfYearRestoreOfferTests,
ActivityTrailWiringTests, UndoStoppedStepTests: 37 of 37 green.

## Self-check

- Tests first in their own commit (4291dcc54). RED on the base because they
  do not compile there (`UndoRestoreSetAside` is missing), and RED by
  behaviour under the breaks above.
- No GCD, no timed waits, no `map`/`filter`/`reduce`, no closure shorthand,
  explicit types, `// MARK: -`.
- Failure paths: a lock that cannot be had leaves the step in flight (as
  before), and the line says any change left part way is still open, which
  is true. A failing restore leaves an `interrupted` step over files that
  are partly made or unknown, which is also true.
- No number tuned by trial: the lock wait is the existing
  `UndoSwitch.finishWaitSeconds`.
- Contract cases from the JSON: the trail event is pinned by
  ActivityTrailWiringTests from `mustRecord`. There is no new case list.
- `origin/dev` merged (already contained).

## Fix round one (review 1: M1, M2, L1)

- **M1, when.** The set-aside no longer runs before the swap. It runs in
  `UndoRestoreSetAside.swapHoldingTheList`, which takes the list's lock
  just before the first move (after the `swapping` record is written),
  runs the swap and, when it stops, its way back, inside that lock, and
  sets aside only when the restore has replaced files: every move made
  (the `done` record is written first, inside the lock), or stopped part
  way with some moved and not put back. Whole course: every door through
  `WholeCourseRestore.restore` (Backups, Archived, Restore Course in the
  Get Ready sheet), via the new `RestoreSwap.Context.holdingTheListAcrossTheSwap`.
  One section: `swapSectionInPlace`, its moves now in `swapTheSectionsFiles`.
  - Fails before the first move, or every file put back (`leftAsItWas`):
    nothing is set aside, the step stays `begun` with its staged files,
    and recovery settles it by content as before (tests: the first move
    fails; the second fails and all go back; both then recovered `done`).
  - Stopped part way, some moved and not put back: the step is closed
    `interrupted`, `setAsideByARestore`. True of the disk: the course is
    part backup, part its own, kept aside in the set-aside folder, so the
    step's files are partly applied or unknown; recovery writing its start
    content would write into backup files. Test: recovery changes nothing.
  - `leftAsItWas` with newcomers kept counts as "as it was": every file of
    the course is back; the newcomers are files written into the backup's
    items during the swap, kept beside the backups, never the step's.
- **L1 closed by the same lock.** A step cannot begin during the swap (a
  begin needs the lock); one begun before the lock is in flight when the
  set-aside runs and is judged by it.
- **M2, per file (the director's ruling).** An op is inside when any file
  it names is under what the restore replaced. A step whose every op is
  inside is closed `interrupted` as before. Otherwise a new journal event
  `setAside` (renamed `filesReplacedByARestore` in review 2; reason `setAsideByARestore`, `paths` the files replaced) is
  written and the step stays in flight. The fold keeps them in
  `UndoStepRecord.setAsidePaths`. Recovery (`UndoRecovery.settle`, and so
  the at-once judgement) judges only the ops naming none of them, never
  re-derives one (`UndoMaintainers.rederive`), and when those settle (made,
  nothing took effect, or put back) closes the step `interrupted`,
  `setAsideByARestore`, naming the files set aside, no clearing: never on
  the list, so Undo and Redo never act on a set-aside file. Changed by hand
  and could-not-put-back endings are unchanged. **Format changed**:
  `file-formats.json` → `undoJournal.events.filesReplacedByARestore` (renamed in review 2), the moves row, the
  `reason` and `paths` keys; `shared-rules.json` mustRecord why; ledger
  reason updated (`Reason899RestoreSetsAsideAStoppedStep`). An event was
  chosen over a note because a reader that does not know it must stop at it
  (a barrier), never pass over it and judge a restored file.
- Trail line: now says the files were replaced (not "is replacing"), and
  for a partial set-aside how many other files are still settled.
- Residual, for the director: a one-section restore rewrites the section's
  `publishForSection<N>` keys in shared pages (`restorePerSectionKeys`).
  Those pages are not "replaced" here (they are the outside files the ruling
  says are judged by content), so a stopped step's whole-file op on
  `index.md` can still be judged against a page whose key the restore put
  back. The reviewer's case is covered (the outside file settled by content).
- Parked: a crash after the last move and before the set-aside line (inside
  the lock, a few renames and one append) leaves the step in flight over the
  restored files; the settle that finds a `done` restore record could set
  aside again. For U5, whose restore step is written in the same lock.

### Must-fail, fix round one (each break on its own, the two set-aside classes)

| Break | RED |
|---|---|
| B1 set aside even when the swap replaced nothing | testARestoreThatFailsBeforeItsFirstMove…, testARestoreThatPutsEveryFileBack… |
| B2 a step partly inside closed whole | testAOneSectionRestoreSetsAsideTheFilesItReplaces, testRecoveryNeverWritesARestoredPage… |
| B3 recovery judges the files set aside | testRecoveryNeverWritesARestoredPage… |
| B4 a restore stopped part way sets nothing aside | testARestoreThatStopsPartWaySetsTheStepAside |

4 of 4 RED; each break was restored by the script after its run. Tests first
in b2f9a94b2 (RED on a934b5805: they do not compile there, `setAsidePaths`).

### Self-check, fix round one

- Broke each fix and watched its test fail: above.
- No timed waits: the lock wait is the existing `UndoSwitch.finishWaitSeconds`.
- Failure paths: lock not had → the swap still runs, the trail says any
  change left part way is still open (true: nothing was set aside).
- No number tuned by trial. `origin/dev` merged (already contained).
- Contract: the events test (`UndoJournalContractTests`) pins the new event.

## Fix round two (review 2: 1 MEDIUM, 5 LOW)

- **M1, Windows held.** The new `folding.moves` row would have turned
  `UndoFoldMovesContractTests.TheTableIsTheContracts` red. The test now
  defers rows named in the ledger under a new area `UndoFoldMoves`
  (`file-formats.json → undoJournal.folding.moves`, keyed
  `from --on--> to`), the way `SharedRules_ActivityTrailEvents_Exist` defers
  events, and the ledger holds the one row (`Owed(UndoFoldMoves, 899, V200,
  Reason899RestoreSetsAsideAStoppedStep, …)`). The count stays 20 of what is
  compared. **Unbuilt here**: no Windows build or run on this Mac; single
  quotes only in the new strings.
- **L5, the name.** The journal event is now `filesReplacedByARestore`, in
  code (`UndoEventKind`) and contract, so it is never confused with the
  U3b op kind `setAside`. Unshipped, so nothing migrates.
- **L1, the lock span proved.** `testTheListsLockIsHeldWhileTheSwapMoves`: a
  move hook tries the list's lock with no wait and must be refused every
  time. RED when the swap runs before the lock (R1 below).
- **L3, no unlocked swap.** A lock still busy after `finishWaitSeconds`
  throws `UndoRestoreSetAside.TheListIsBusy` before anything is done
  (`justBeforeTheSwap` now runs inside the lock too). The restore says the
  existing `leftAsItWas` sentence (whole course: `RestoreWholeCourseWording.leftAsItWas`;
  one section: `OneSectionRestoreWording.leftAsItWas`) with the reason
  `RestoreSwap.listBusyReason`, "another change in Plantoir was still being
  made": new words inside an existing sentence's reason slot, which already
  carries the file system's words. No contract key is added; if the
  director wants the reason as a key, it is parked here. A list that cannot
  be read or written at all (not busy) still lets the restore run, as
  before, with the trail line: a restore is how a teacher gets a course
  back.
- **L2, the crash window closed.** `RestoreSettle`'s `.finish` path (a `done`
  record found at a later reading) calls `UndoRestoreSetAside.setAsideAfterASettledRestore`
  inside the list's lock before it finishes; `.putBack` and `.keep` set
  nothing aside (a stopped restore set aside in its own lock already).
  Idempotent. Test: a staged `done` record (the state a kill after the commit
  leaves), the settle, the step `interrupted`, recovery writes nothing.
  Still owed by order: the settle runs at folder open (`reloadCourses`);
  whether the MCP process settles before its first recovery was not checked.
  For U7/U5.
- **L4, the keys.** The per-section keys are written inside the lock
  (`swapSectionInPlace`'s `thenInsideTheLock`, both callers), observed at
  the new `SwapPoint.perSectionKeysPutBack`. Whether keys a restore puts
  back count as replaced is still for the director (they are judged by
  content).

### Must-fail, round two (each break on its own, the two set-aside classes)

| Break | RED |
|---|---|
| R1 the swap outside the lock | testTheListsLockIsHeldWhileTheSwapMoves, testARestoreThatCannotHaveTheListDoesNotStart, testAOneSectionRestoreWritesItsKeysInsideTheLock |
| R2 a busy list lets the swap run unlocked | testARestoreThatCannotHaveTheListDoesNotStart |
| R3 the settle sets nothing aside | testASettleThatFinishesARestoreSetsTheStepAside |
| R4 the keys written after the lock | testAOneSectionRestoreWritesItsKeysInsideTheLock |

4 of 4 RED. Tests first in e77080809 (RED on 4735571a8: they do not compile
there, `perSectionKeysPutBack`, `lockFileURL` use aside).

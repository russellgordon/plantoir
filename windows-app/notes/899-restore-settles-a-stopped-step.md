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

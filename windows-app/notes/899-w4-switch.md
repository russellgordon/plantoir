# #899 W4: the switch (off), shadow, the list wired to the app's processes

Notes for the director to fold into `windows-app/PROGRESS.md` and
`documentation/12-windows-app.md` at the merge window (NIGHT3-COMMON: writers
do not edit either file).

## For PROGRESS

## 2026-11-20 — Undo and Redo, W4: the switch, off, and the list wired to the app's processes (#899, #949)

Branch `issue/899-w4-switch` (on W3, `dev` 2ba8490e7 merged). Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro 26200) over SSH, the window in the desktop session through a scheduled task. Nothing a teacher sees changed; the switch stays off; no action goes through the door yet (W7 on).

- `Plantoir.Core/Undo/UndoSwitch.cs`: `UndoJournalIsLive = false` (a `static readonly` field, never a setting), `UndoRefusedForMissingContentClearsTheList = true` (ruling 22, read by the door's refusal answer), `CurrentMode`.
- `Plantoir.Core/Undo/UndoForThisProcess.cs`: the composition root, the only reader of the switch and of `UndoJournalLocation` for Undo. One `UndoProcessMemory` and one `UndoJournal` per process, a `Door()` per action with the real trail sink. `UndoAtLaunch.Recover()` runs recovery at launch on a thread of its own and never throws; called once from `App.OnLaunched` (after `--state-dir` and the marketing scenes, before the windows) and once from `plantoir-mcp`'s `Program` (after `--state-dir`, before the host).
- Shadow made total: with the switch off, ANY failure of the list (not only disk and permission errors) lets the teacher's change go ahead unrecorded, at the begin, at the closing and when a step is given up. A step given only as its ops is refused (`couldNotRecordTheStep`) before anything changes in either mode, as on the mac.
- The writer scan (`UndoWriterScanTests`, the mac's): 75 product files that write, each `door` (5), `notAStep` with its reason (37) or `waitsFor` (33: W7 8, one of them also W8; W8 21; W9 3; W11a 1); a new writer or a stale count fails; `TheSwitchStaysOffWhileWritersWait`. `TaskScheduling.cs` waits for W8 by ruling 23 (the mac's entry still says held, M10).
- W3's review lows 2, 3 and 4 and the final sweep's recompute finding fixed, each with a test.
- Tests: `UndoShadowTests` (13), `UndoForThisProcessTests` (7), `UndoWriterScanTests` (5), `UndoRecoveryReviewFixesTests` (3), `UndoDoorTests` extended. PC `899w4-c1`: the Undo classes (contract classes included) 639 passed, 1 not run (`UndoWebsiteContractTests.ARecordFolderThatDeniesListingCannotTell`, a `[DenyBitesFact]` that cannot bite over SSH), 0 failed. Thirteen must-fail proofs, every one red (`899w4-mf1`, `899w4-mf2`; `vm-tools/guest/899-w4-mustfail.json`).
- The real `plantoir-mcp.exe` and `Plantoir.exe` find one list, under `--state-dir` and under the default, and settle at launch a step a killed process left (`899w4-p1`): `documentation/12-windows-app.md` → "What Windows has built: W4, the switch".

## For documentation 12

### What Windows has built: W4, the switch (#899, #949)

Piece W4 (branch `issue/899-w4-switch`, on W3, 2026-11-20) wires the list to
the app's two processes and keeps it switched off. Nothing a teacher sees
changed. The plan is `vm-tools/reference/899-w4-plan.md`.

- **The switch.** `UndoSwitch.UndoJournalIsLive` is `false`, a
  `static readonly` field rather than a setting, because a half-covered Undo
  is worse than none: the step it silently passes over is the one a teacher
  needed back. Nobody turns it on early from a test, a command line or the
  settings file. `static readonly` rather than `const` only so the live paths
  compile without an unreachable-code warning. W11a flips it, and
  `UndoWriterScanTests.TheSwitchStaysOffWhileWritersWait` fails while any
  writer still waits for a piece.
- **One list per process, found the same way by both programs.**
  `UndoForThisProcess` is the composition root (the plan review's H1): the
  only code that reads the switch and `UndoJournalLocation`. It is made the
  first time it is asked for, which both programs do only after `--state-dir`
  has been applied, so the window, the window's own `plantoir-mcp` (handed
  `--state-dir` by `McpClient`, #641) and an outside door's `plantoir-mcp`
  (handed none) all find one list: `%LOCALAPPDATA%\Plantoir\undo`, or
  `undo\` under the redirected state folder. A test makes its own instance
  with its own folder, mode and trail and never touches the process's.
- **Recovery at launch.** `UndoAtLaunch.Recover()` runs W3's
  `UndoDoor.Recover()` on a thread of its own, so the window's UI thread never
  waits on the lock and `plantoir-mcp` answers its client meanwhile. It never
  throws: a list that cannot be had (busy behind another process's put-back,
  unreadable, its folder not makeable, a failure nobody foresaw) leaves every
  step for the next hold of any process, and the window's startup log says so.
  In the window it runs after the marketing scenes (which must never open the
  list); a deploy set for later leaves `Program.Main` before it and never
  opens the list.
- **Shadow, as `rule.shadow` defines it.** With the switch off, a failure of
  the list never stops or changes what a teacher asked for: ANY exception from
  the list in shadow, the unforeseen included, lets the change go ahead
  unrecorded at the begin; a closing that cannot be written or kept leaves the
  change as it is; giving a step up never reads the list and never throws.
  Recovery in shadow records what it finds and writes nothing into a working
  folder, so a step killed part way leaves its staged files beside the pages
  (`staged=8` below); that is moot until W7 puts actions through the door.
  The exception, as on the mac's `JournaledWrite.perform(ops:)`: a step given
  only as its ops is refused (`couldNotRecordTheStep`) before anything changes
  in either mode, since the door cannot carry out an ops step it has not
  recorded. (The W4 plan first said the ops entry would go ahead in shadow;
  the mid-piece sweep corrected it.)
- **A waiter behind a long put-back.** W3 measured a 232-page put-back holding
  the lock 1.2 s outside OneDrive and 2.7 s inside, past the 2 s live wait.
  Every waiter gives up after its bounded wait (`rule.oneLock`) and nothing is
  lost: a live step is refused before anything changes
  (`couldNotRecordTheStep`, the teacher told the step could not be recorded,
  the page untouched), a shadow step goes ahead unrecorded (only its own
  pages), an Undo or Redo answers the list unavailable, a launch's recovery
  leaves the step for the next hold, and a closing waits its 10 s and is then
  kept in the process's memory. When the put-back finishes the step is settled
  and the refused step can be made. Proved without timing:
  `UndoForThisProcessTests.AWaiterBehindALongPutBackGivesUpAndNothingIsLost`
  holds a recovery inside its put-back on an event.
- **Staged files and folder renames while a swap runs** (W3's review, LOW 5).
  A swap holds handles on its staged files, which keep their folder in place
  (W2b), so renaming the course folder or a parent of it while a swap runs is
  refused: File Explorer shows "Folder In Use", and OneDrive retries its own
  move later. No data is lost; the rename succeeds once the swap is over. How
  long that is: the swap's span, measured in W2b on the Lenovo i5-8365U at
  233 pages 1.07 s outside OneDrive and 1.9 s inside, almost all of it outside
  the lock.
- **The writer scan on Windows** (`UndoWriterScanTests`, the mac's). Every
  product `.cs` under `Plantoir`, `Plantoir.Core`, `Plantoir.Mcp` and
  `PtyDriver` with a writing call (the shapes are in the class's summary;
  comments are taken out, strings kept, since a launcher's name is a string)
  is listed with its count and one of three kinds: `door` (5, the list
  itself), `notAStep` with its reason (37: the trail, leases, the toolchain
  mirror, models, problem reports, the app's state, a deploy), or `waitsFor`
  with the Windows piece that wires it (W7 mirrors U3, W8 U4, W9 U5, W11a U7;
  33 files). 75 files at W4. `TaskScheduling.cs` waits for W8 by ruling 23,
  where the mac's entry still says held (M10).
- **W3's review lows.** LOW 2: a gone process's step that keeps a file true is
  never closed `unsettled` by the pruning of a hold that cannot re-derive
  (`UndoJournalWriter.LeftForARederivingRecovery`). LOW 3: a step this process
  gives up is noted by what the door knows (list, number, where its work
  stands, its own pid), never by a reading of the list, which at those moments
  could not be read. LOW 4: an Undo whose newest step is a gone process's that
  recovery has just tried and left (a file in use, a page it cannot read now)
  answers that refusal, naming the file, never "another change is under way"
  until the step ages out. The sweep: the files entry, like the ops entry,
  refuses a step holding a recompute this process has no runner for.

**Measured, `899w4-p1`, Lenovo 20QES70500 (i5-8365U, 16 GB, Windows 11 Pro
26200).** A harness child made an 8-page shadow step in the list under the
state folder and was killed, then the real program was started and the list
read by a third process until the step left flight:

| State folder | Killed at | Started | Settled after | Step became | Pages |
|---|---|---|---|---|---|
| `--state-dir` (scratch) | half way through the swap | `plantoir-mcp.exe --state-dir` | 2.3 s | interrupted | 4 old, 4 new, none torn, 8 staged left (shadow) |
| `--state-dir` (same list) | after its begin | `Plantoir.exe --state-dir`, desktop session | 3.7 s | failed (nothing took effect) | 8 old |
| default `%LOCALAPPDATA%\Plantoir` | half way through the swap | `plantoir-mcp.exe` | 0.9 s | interrupted | 4 old, 4 new, none torn, 8 staged left |
| default (same list) | after its begin | `Plantoir.exe`, desktop session | 1.6 s | failed | 8 old |

Each second program found the step the first had settled in the same list
(five lines, steps 1 and 2 closed). The "settled after" times include the
process's start and a half-second read interval; they are not a measure of
recovery. The default `undo` folder did not exist before and was removed
after; `settings.json` was put back.

**Held out of W4, to be built as a shared piece (Mac first, since both change
`contracts/`):**

1. Recovery puts a page back from a kept `-orig` whose hash matches the
   journal's record (Russell's ruling of 2026-11-20, 15:20 on #899; the
   `recoveryCases` rows "a step dies part way and its content is then missing"
   and "an undo of a step with a page now missing its content" become rolled
   back). On Windows it goes in `UndoRecovery.Settle`: the live tidy at its top
   (`UndoSwap.TidyLeftovers` before the plan) must stop removing the `-orig`
   files until after the plan, and the `default:` arm of the plan switch (the
   put-back that cannot be planned, closed `interrupted`
   (`couldNotPutBack`)) must first offer each missing content from the
   matching `-orig`. The Undo path's missing-content answer
   (`UndoDoor.AnswerARefusal`, `ContentMissing`) follows the same rows.
2. The trail line for LOW 4 (an Undo refused because a gone step's file is in
   use): a new `activityTrail.mustRecord` event, added to
   `contracts/shared-rules.json` and `ActivityTrail.Event` together. On
   Windows it is written in `UndoDoor`'s Undo/Redo path where `leftNewest`
   returns the refusal, through the door's `_trail`, and routed by
   `UndoTrail.ToTheActivityTrail` beside `UndoRolledBack`.

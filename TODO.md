# To Do — closed to new entries

**Work that still needs doing lives in [GitHub
issues](https://github.com/russellgordon/plantoir/issues), not here.** Open a
new issue instead of adding to this file, and label it `mac`, `windows`,
`toolchain` or `assistant` for the platform it lands on (`decision` for
something that needs Russell to choose). Pin it to a release with a milestone.

What remains below is **append-only history**: entries that were finished or
decided while this file was the to-do list. An entry records what was true on
its day, and — as often as not — what the entry itself got wrong before the
work was done; that is the part worth keeping, so nothing here is edited when
the behaviour changes again. The twelve entries that were still open on
2026-09-08 were moved to issues #88–#99 and removed from this file.

- ~~**The mac suite crashes intermittently inside AppKit, and it reads as a
  failing test rather than as a crash**~~ — ✅ **Done 2026-09-07** (mac,
  raised 2026-09-06, measured while working on something else — NOT caused by
  that work, see below).

  **What it turned out to be, and what fixed it.** The diagnosis below is
  right as far as it goes and one guess in it is wrong. `NSMoveHelper
  _doAnimation` spins a NESTED runloop, and SwiftUI's `AppKitDialogBridge`
  ends the modal session from inside `NSHostingView.layout()` — so the nested
  runloop is spun from inside a display-cycle callback that is already
  running, and the cycle is re-entered. One call stack on one thread, not a
  race, which is why no amount of settling would have helped.

  **The "two-line experiment" at the bottom of this entry does not work, and
  that is the useful part to keep.** `-NSAutomaticWindowAnimationsEnabled NO`
  reaches the process and is ignored for the sheet move: 0.268 s animating
  without it, 0.268 s with it, measured by timing `_doAnimation` directly.
  AppKit reads the key on this very path — hooking `-[NSUserDefaults
  objectForKey:]` during a close shows it consulted, beside
  `NSOrderOutSheetWhenEnded` — and does not act on it. Nor does
  `NSWindow.animationBehavior = .none` on the sheet or its parent, nor
  `endSheet` inside a zero-duration `NSAnimationContext` group, nor
  `-NSOrderOutSheetWhenEnded NO`, nor an off-screen parent window. All six
  landed between 0.264 s and 0.270 s. Reduce Motion was not tried and is
  almost certainly a dead end too: no accessibility key is among the four
  read on that path.

  What DOES work is AppKit's own switch. `NSSheetMoveHelper` declares its own
  `-shouldSkipAnimation`, overriding `NSMoveHelper`'s, and forcing it true is
  how AppKit itself takes a sheet out of the animation — the same branch it
  takes for `inhibitWindowAnimations`. One `method_setImplementation` on the
  subclass leaves ordinary window moves animating. (An empty `_doAnimation`
  override also works and was tried first; the switch was preferred because
  AppKit's own skip path leaves the state AppKit intends to leave, and because
  it needs no `class_addMethod` and no fallback branch.) It lives in the test
  bundle (`mac-app/Tests/QuartzTeachersTests/SheetAnimationSuppressor.swift`)
  and is installed from the bundle's `NSPrincipalClass`, so nothing in the
  shipped app changes.

  Measured on this Mac (Apple M4 Pro, macOS 26.6 25G72), same command, same
  session: **10 crashes in 30 runs before, 0 in 30 after** for that class
  alone, and the FULL suite 0 host deaths in 13 runs afterwards (1,062 cases
  each; the one red case throughout was the `section restored` contract event
  Windows proposed, unrelated to this work and adopted the same day — see
  `GUI-IMPROVEMENTS.md` row 445). Those are two
  separate measurements on purpose — the class-alone figure was clean while
  the full suite was still aborting 8 times out of 8 on an unrelated crash
  this work had just introduced, which is the whole reason to measure at the
  scope a gate runs. See `GUI-IMPROVEMENTS.md` row 444 and
  `WINDOWS-HANDOFF.md`.

  **What it looks like.** `xcodebuild ... test` exits 65 and prints
  `** TEST FAILED **` with a "Failing tests:" line naming one
  `CourseRenameInterfaceTests` method — but the XCTest totals above it say
  `0 failures`, and the method NAMED is whichever one happened to be running
  when the host died. Earlier in the log: `Restarting after unexpected exit,
  crash, or test timeout`. So the honest reading is "the test host
  segfaulted", and the test named is a bystander.

  **What it actually is.** `~/Library/Logs/DiagnosticReports/Plantoir-*.ips`:
  `EXC_BAD_ACCESS (SIGSEGV)` at address 0, faulting stack entirely inside
  AppKit — `NSAlert beginSheetModalForWindow:` → `NSWindow _doOrderWindow:` →
  `NSSheetMoveHelper closeSheet` → `NSMoveHelper _doAnimation` →
  `UC::DriverCore::continueProcessing`. Nothing of ours is on the stack. It is
  the sheet-dismissal ANIMATION, in a test that drives a real alert.

  **Measured, because "it feels flaky" is not usable.** Running
  `-only-testing:QuartzTeachersTests/CourseRenameInterfaceTests` alone:
  **3 crashes in 7 runs on an unmodified `dev` worktree** (commit `3ca5f0a4`,
  built fresh in `/tmp`), and 2 in 3 on a branch that touched only
  `SpecialFoldersHelpView`. So it PRE-DATES any current work and reproduces
  from a clean checkout. The full suite is likewise green on some runs
  (1047 tests, 3 skipped, 0 failures) and aborted at 542 on others.

  **Why it matters more than a rerun.** Anything that gates on the suite —
  a batch driver, CI, a session deciding whether it broke something — sees
  red for a reason that has nothing to do with the diff, and the message
  actively points at an innocent test. Someone will spend an afternoon on
  `testACourseThatIsPreviewingIsNotRenamed` before noticing the totals say
  zero failures.

  ~~Not fixed here because it is not this piece's, and because the fix is a real
  question rather than a tweak: whether these tests should drive a live
  `NSAlert` sheet at all (`beginSheetModalForWindow:` under a test host, with
  animations on), or assert the same thing without one. Worth checking
  `NSAnimationContext`/`reduce motion` in the test environment first — a
  disabled sheet animation would take the faulting frame out of the picture
  entirely, and would be a two-line experiment.~~ — the instinct was right and
  the route was not; see the correction at the top of this entry. The tests
  still drive a live `NSAlert` sheet, and still assert exactly what they did.

- ✅ **Done 2026-09-05 — the two reliability findings from that day's review.**
  Kept rather than deleted because the SHAPE of each is worth recognising
  again: both were races nobody would meet often, and both ended in a state a
  teacher could not get out of.

  **1. A rename interrupted after the folders moved was a dead end.** The
  configuration still said the old name, the next build DISCOVERED the moved
  folder and appended it, and retrying the rename was then refused as a clash —
  with the class folder unremovable too, so the only exit was hand-editing
  JSON. The fix is not a lock: `problem()` now accepts a rename whose target is
  already in the list **when the disk says the old folder is gone and the new
  one is there**, which is not two folders competing for a name, it is one
  rename asking to be finished. `looksLikeAnInterruptedRename` asks the
  filesystem, because the configuration is exactly what is wrong in that state,
  and it requires that NO section still has the old folder — a mixture means
  something else happened and the ordinary refusal stands. Finishing also
  de-duplicates the list, which the starting state needs by definition.

  **2. Two writers of `course_config.json` could silently erase each other.**
  `preflight_update_course_config` reads the file, scans the course's folders,
  and writes what it computed; the app writes the same file in that window,
  because a rename commits at once rather than at Save. Whoever wrote second
  won and said nothing. Both writers now compare-and-swap: preflight re-reads
  before writing and redoes its discovery if the file moved under it (bounded,
  then carries on with what is there), and `recordOnDisk` does the same but
  ends by writing anyway — a folder that has MOVED and a configuration that
  does not say so is the worse of the two states, so it finishes by recording
  the truth rather than by giving up on it.

  `scripts/test_config_write_race.py` forces the race rather than hoping for
  it, and was checked the only way worth checking: with the guard disabled it
  fails with the key missing, exactly as the bug did.

- ~~**One rule, three implementations: stopping a section's preview.**~~ — ✅
  **Done 2026-09-05**, row 407. Kept rather than deleted because the finding
  that came out of doing it is worth recognising again, and it is not the one
  this entry predicted.

  **The three were not three copies of one rule. They were three PARTIAL
  rules.** This entry assumed the job was to pick one implementation, or to
  hold three to one case list. Both would have shipped a blind spot, because
  each of the three saw something the others could not: a working directory
  catches a child launched by a RELATIVE path (`npm install` runs that way and
  carries no directory at all), while a command line catches the Python
  driver, which never chdirs — `build_site.py` passes `cwd=` to its children —
  and so sits in the container's own folder for the whole build. Through every
  in-process phase of a build the driver is the only process there is to find,
  and the mac's sweep found nothing and said "Stopped 0 process(es)". Only the
  PowerShell copy walked descendants, which this entry did spot.

  So the shared rule is a disjunction of evidences plus a walk down the
  process tree, and it stops strictly MORE than any of the three did alone.
  The lesson to carry to the next "three implementations of one question":
  **before unifying, find out what each copy can see that the others cannot.**
  If the answer is "nothing", it is a refactor; if it is not, choosing any one
  of them as the survivor spreads its blind spot everywhere, and the honest
  unification is the union.

  The prediction that a contract case list was the cheapest honest version was
  right, with one correction: a case is a whole process SNAPSHOT, not one
  process, because `Win32_Process` exposes no working directory and a
  descendant walk is not a property of any single process. The rule is in
  `scripts/stop_preview.py`, the cases in `contracts/shared-rules.json` →
  `stopPreview`, and writing them down found two live prefix bugs in
  `preview.ps1` (`section1` matching `section10`; `--section=1` matching
  `--section=10`).

- **~~Should Plantoir refuse to work in a cloud-synced folder?~~ Decided
  2026-09-05: no.** Russell's call, prompted by a reliability review finding
  that renaming a folder reads every page in the course — which on an
  iCloud-backed vault means downloading evicted files, one blocking read at a
  time. Shipped as `GUI-IMPROVEMENTS.md` row 399: Plantoir DETECTS a synced
  working folder from the markers the system exposes, SAYS SO once in plain
  words (a choice in the picker for a folder just chosen, a quiet notice for
  one the window restored), and leaves the teacher's content where they put
  it. The rule, the sentences and the timing are in `shared-rules.json` →
  `cloudSyncedFolders`. The reasoning, kept because it will be proposed again:

  **Why refusing was the wrong answer.** Teachers keep vaults in iCloud *on
  purpose* — it is how their notes reach their iPad and their second Mac.
  Refusing means telling them to give up cross-device access to their own
  teaching material, and a hard block is the one response they cannot opt out
  of. Detection is unreliable in both directions besides: a teacher can have a
  folder literally called "Dropbox" that is not one, and a false refusal on a
  hard block is unrecoverable for them. And the project had already REJECTED
  refusal once by building something better — `PLANTOIR_BUILD_ROOT` on
  Windows moves the churn out of the synced folder and leaves the content
  where the teacher wants it.

  **What is genuinely broken by cloud sync**, in order of severity: (1) build
  churn — thousands of small files per build, all uploaded, and on Windows
  locked mid-build by OneDrive; (2) dataless files — reading an evicted page
  blocks on a download, slow but not corrupting; (3) rename and move failures
  from held locks, which can leave a partial state. The explanation a teacher
  reads names all three as effects, not mechanisms.

- ~~**Move the mac's build output OUT of a synced working folder**~~ — ✅
  **Done 2026-09-05**, row 402. Built on the design sketched below: `.merged_output`
  is a SYMLINK to `~/Library/Application Support/Plantoir/builds/<folder id>/<CODE>`
  and the launchers bind-mount that folder into the container at the same
  absolute path. Done for EVERY working folder, not only the synced ones — the
  benefit is not confined to syncing and one code path is one code path. The
  rule, the measurements, the upgrade path and what was rejected are in
  `contracts/shared-rules.json` → `buildOutputLocation`, which is now the place
  to read rather than this entry.

  Four of the open questions below were answered by testing rather than by
  reading, and one of them was WRONG here:

  - **iCloud and Dropbox both leave a symlink alone.** Measured on this Mac
    against a real iCloud Drive folder and a real `~/Library/CloudStorage/Dropbox`:
    both kept it as a link, iCloud uploaded the LINK at 82 bytes (the length of
    the target path) rather than the 3 MB behind it, and Dropbox left the target
    folder outside Dropbox with none of its own extended attributes on it. No
    OneDrive on this Mac; not tested.
  - **`shutil.rmtree` refusing a symlink turned out not to matter.** The
    `--full-rebuild` path removes `output_dir`, which is the CONTAINER's
    `/tmp/quartz-builds` tree, not the host's `.merged_output`. This entry
    implied otherwise.
  - **The real hazard was elsewhere**: `preview.sh --stop` finds a preview's
    processes by working directory, and `/proc/<pid>/cwd` is the RESOLVED path,
    so the sweep had to learn the resolved form too.
  - **And the one nobody had listed**: archiving, restoring or replacing a
    course removes the link but not the build standing outside, and a restored
    course's pages can be OLDER than that build — which would read as "already
    up to date" and publish last month's site. A build with no link pointing at
    it is now cleared rather than adopted.

  The original research is kept below because the reasoning is the point.

  **Why it is not one environment variable on the mac.** The build runs in a
  container that mounts ONLY `courses/` (`-v "$HOST_COURSES":/teaching/courses`
  in all three launchers), so a build root outside the working folder is
  invisible inside the container until a SECOND mount exists — and
  `preview.sh`'s "does the container need recreating" check compares only the
  `/teaching/courses` mount, so an added mount would need its own recreate
  rule. Then every reader that hard-codes `courses/<C>/.merged_output` has to
  agree: `deploy.sh` (`MERGED_DIR_HOST` for the host-side section listing,
  `SECTION_DIR_IN_CONTAINER` at the publish), `preview.sh` (`OUTPUT_PATH` in
  the messages, `TARGET_DIR` in stop mode — the process sweep finds a
  preview's processes by WORKING DIRECTORY, so a moved output means a stop
  that finds nothing), and on the host `BuildFreshness`, `ScheduledDeploy` and
  `SectionDetailView`. A scheduled deploy runs from launchd with no app to set
  the variable, and a teacher at the command line has none either — so the
  decision has to live somewhere all three can read, or the app and the CLI
  will build into different places and `BuildFreshness` will call every build
  stale. The Colima VM mounts only `$HOME`, so the relocated root must be
  under it: `~/Library/Application Support/Plantoir/builds/<folder-id>/`.

  Rejected: a `.nosync` suffix (iCloud-only — Dropbox and OneDrive ignore it —
  and it moves the path just as much).

- ~~**`CourseRenameInterfaceTests` crashes the whole unit run, intermittently —
  and it is PRE-EXISTING, not caused by the special-folders work.**~~ —
  ✅ **Done 2026-09-07.** The SAME defect as the "crashes intermittently inside
  AppKit" entry near the top of this file,
  written up twice a fortnight apart before anybody noticed they were one
  thing; both are fixed by the same change. Everything below stands as
  measured, and the closing paragraph's lead — "the cheapest lead is now
  inside `CourseRenameInterfaceTests` itself" — was correct: the class's own
  `renameProblem = nil` at line 175 is what lights the fuse. The full-suite
  rate recorded here (about half of runs, 9 of 17 across two trees) is the
  number that mattered most in the end, because it is the scope a merge gate
  actually runs. Measured
  2026-08-23 on a clean `origin/dev` worktree with none of that branch's
  changes: **one crash in four full runs**, aborting the run partway
  (`Executed 419 tests` and an exit code of 65 with ZERO failed test CASES).
  The branch's own rate was about the same, one in three.

  **Two wrong diagnoses were recorded here before the right one**, and both are
  worth remembering because each looked convincing:

  1. *Busy-machine flakiness* — plausible because the interface tests host real
     SwiftUI views and adversarial-review agents were running builds at the
     time. Wrong.
  2. *An alert I had just added* — plausible because the crash report names
     `SwiftUI.AppKitDialogBridge.updateExistingAlert` during an `NSAlert` sheet
     close, and `SectionDetailView` had just grown to four `.alert` modifiers.
     Consolidating them to one made three consecutive runs pass, which read as
     confirmation. It was not: the crash came back afterwards, and then
     reproduced on `origin/dev`, which has none of it.

  The lesson is the measurement, not the guess: **a baseline needs SEVERAL runs
  on an unmodified tree, in a separate worktree.** One clean baseline run was
  taken early on and treated as exoneration; it was a coin toss landing the
  other way. And `git checkout <ref> -- path/` does NOT make a baseline — it
  leaves files the ref does not have, which is how the first attempt at this
  produced a build error instead of a measurement.

  What is actually known: `EXC_BAD_ACCESS` / SIGSEGV inside
  `AppKitDialogBridge.updateExistingAlert` → `NSSheetMoveHelper closeSheet`, in
  a suite where `SectionDetailView` and the `TaskProgressView` it embeds carry
  several alerts and a sheet between them. Both crashes named a
  `CourseRenameInterfaceTests` case, but that test hosts a sidebar ROW and is
  most likely the bystander that happened to be running.

  **Measured properly on 2026-09-04**, with the machine to myself overnight and
  a clean `dev` worktree built beside the branch — the baseline `TODO.md` says
  this needs. Twenty-seven full-suite and ten single-class runs:

  | tree | scope | runs | aborted |
  |---|---|---|---|
  | `issue/special-names-followups` | full suite | 9 | 6 |
  | clean `dev` (worktree) | full suite | 8 | 3 |
  | `issue/special-names-followups` | that class alone | 5 | 0 |
  | clean `dev` (worktree) | that class alone | 5 | 1 |

  Four things follow, and two of them correct what is written above.

  - **It is pre-existing.** Clean `dev` aborts too, so no branch since has
    caused it. (Every `dev` run also carried one FAILED case — the stale
    milestone marker, fixed on the branch in `13da5319`.)
  - **It is NOT purely a bystander.** The class alone aborts 1 in 10, which the
    "bystander" reading does not predict: something in that class is enough on
    its own. The full suite raises the rate to roughly 1 in 2, so earlier tests
    make it likelier without being necessary.
  - **The rate is higher than the "one in four" recorded above** — about half of
    full-suite runs, across both trees.
  - **It never produces a failed test CASE.** Every abort has `failed=0` and
    exits 65 partway. So a run that completes is trustworthy, and the branch
    produced three fully clean full-suite runs (exit 0, 979 passed, 0 failures).

  Where to start, updated: the class ALONE reproduces it, so the cheapest lead
  is now inside `CourseRenameInterfaceTests` itself rather than in what ran
  before it. Both named cases (`testACourseThatIsPreviewingIsNotRenamed` and
  `testAnUnusableCodeIsShownUnderTheFieldRatherThanInAnAlert`) call
  `workspace.beginRenamingSelectedCourse()` and then leave `renamingCourseCode`
  set until the end of the test. `RemovalButtonTests` next door hosts its view
  differently and does not provoke it — that difference is still worth reading.

- ✅ **Done 2026-09-01 — let a teacher rename a special folder from inside Plantoir.**
  Deferred 2026-08-23 while planning the hardening of the special folder and
  file names; built once Russell chose the full scope on 2026-09-01. Kept here
  rather than deleted because the reason it was deferred turned out to be
  WRONG, and that is worth more than the entry itself.

  **What it feared:** that renaming a folder would strand every wikilink
  pointing into it, so the feature needed its own design pass and its own undo.
  It does not. Obsidian resolves `[[Quiz 1]]` by searching the vault, so a bare
  page link keeps working when the folder around it moves; only QUALIFIED links
  break — `[[Tasks/Quiz 1]]`, a full vault path, or Obsidian's Markdown link
  style — and `FolderPathRewriter` rewrites exactly those. A folder rename is a
  far smaller thing than a page rename, which is why this shipped without the
  undo the deferral assumed it needed.

  **What shipped:** a pencil on folder rows in Course Settings, renaming on
  disk in every section, rewriting qualified links, and carrying across every
  config key that named the folder. The two foot-guns the entry named are
  closed too — Add creates the folder, and Remove says the folder and its
  contents stay on the teacher's Mac. See `GUI-IMPROVEMENTS.md` row 385.

  **Still open, and inherent:** a rename performed in OBSIDIAN is still
  discovered by `preflight_update_course_config` as a new folder and appended,
  leaving the config naming both. The build cannot tell a rename from a delete
  and a create, which is exactly why the rename was worth putting in the app —
  the app is the one place it can be witnessed. Not worth chasing further.

- ✅ **Half done 2026-09-01 — a course chooses its word for “Unit” when it is
  made.** Deferred 2026-08-23; built once Russell chose the scope on
  2026-09-01: **new courses plus configurable parsing, NOT renaming a course
  already in use.**

  **What shipped.** `unit_word` in `course_config.json`, absent meaning “Unit”.
  The wizard asks every course, the ready-made payload is written in that word
  as it is poured (a course's own 84–87 class pages and the pages around them, in
  one pass during the copy), and both the Python and the Swift now read the
  word rather than
  assuming it — `scripts/class_pages.py` and `ClassPageTerm`. The assistant
  says it too. See `GUI-IMPROVEMENTS.md` row 386.

  **The measurements, re-taken 2026-09-01 — and the 2026-08-23 ones were
  wrong.** Adversarial review found that the numbers this entry used to quote
  (3,088 named files, 3,143 wikilinks, 600 skeleton files) matched nothing on
  this tree, and worse, that the per-course figure was being read off a
  whole-repo total. What is actually there:

  - **3,172** files named `Unit N, Day N` across all 38 payloads — but
    **84–87 in any ONE course** (30 payloads hold 86, four hold 84, one 85, one
    87), and **42** in each of the two half-credit courses, CHV2O and GLC2O. A
    teacher's course is under a hundred class pages, not three thousand.
  - **2,338** skeleton `.md` files, which are generated and therefore cheap.
  - `contracts/class-planning.json` is authored end to end in Unit/Day.

  **The scale argument was never the real one, and losing it does not make the
  remaining half safe.** Renaming an EXISTING course's word means rewriting
  every class page's name, its frontmatter title and every wikilink pointing at
  it, across every section and every shared folder — and a half-finished pass
  leaves a broken site with no way back. Ninety pages is not too many to
  rewrite; it is too many to rewrite WITHOUT AN UNDO. The machinery is closer
  than it was — `ClassInsertionPlanner` already renames class pages, retitles
  frontmatter and rewrites wikilinks for ONE section, which is the same shape
  widened to a course — but it still deserves its own design pass and its own
  undo. Not a checkbox in Settings.

  **Rejected, and logged so it is not retried:** a display-only rename (pages
  titled “Thread 2, Day 3” while the files stay `Unit 2, Day 3.md`). Obsidian is
  the teacher's editor and they would see the old word every time they opened
  the vault — which is the place the rename was supposed to help.

- **~~The assistant's first turn does not wait for its warm-up~~** — ✅ **Done
  2026-08-20**, the same week it was written. `AssistSession.canSend` now reads
  `guard readiness == .ready, hasFinishedWarmUp, let agent`, with a separate
  `canAcceptTyping` so the composer explains itself while the model warms, and
  `AssistWarmUpTests` pins it. The original entry follows.

  The assistant's first turn does not wait for its warm-up — measured
  2026-08-20, while qualifying the mac for v1.1.0. `AssistSession` sets
  `readiness = .ready` (which is all `canSend` checks) and only THEN awaits
  `warmUp`, so a teacher who types straight away queues behind the
  ~3,400-token priming request on the server's single slot. Same question,
  same model, same Mac: **1.7 s** warm against **3.1 s** racing the warm-up.

  It is an optimisation, not a fix — deliberately left out of 1.1.0 because
  changing it would have made an unchanged mac binary a behaviour change,
  and the failure Windows repaired (a first question ending in silence)
  cannot happen here: the timeout is 180 s, `AssistAgent.think()`'s catch
  surfaces every error as a message and a trail line, and the engine's
  output goes to `nullDevice` so no pipe can wedge. Windows already awaits
  its warm-up; see `MAC-HANDOFF.md` and GUI-IMPROVEMENTS row 295.

  The fix is small: hold `.ready` until the warm-up returns, or gate
  `canSend` on a separate `hasFinishedWarmUp`. **Pin it with a test** that
  a turn cannot start before the warm-up's request has come back — the
  measurement above is the evidence it is worth doing, not a substitute
  for one.

- **~~A mac problem report can carry nothing the engine said~~** — ✅ **Done
  2026-08-20.** `AssistServerHost` writes to `logHandle ?? FileHandle.nullDevice`
  — a FILE, never a pipe, which keeps exactly the no-blocking-read property this
  entry insisted on — and a bounded tail (`engineLinesSinceLastLook(atMost: 200)`)
  reaches the trail as `assistantEngineSaid`, a registered contract event. The
  original entry follows.

  A mac problem report can carry nothing the engine said — found the
  same day. `AssistServerHost` sends `llama-server`'s stdout and stderr to
  `FileHandle.nullDevice`. That is load-bearing (an unread pipe is what
  wedged the Windows server mid-request, and this is why the mac never
  had that bug) but it also means model-load errors, slot warnings and
  timing lines reach nobody — the one place they could matter is a report
  from a teacher whose assistant is misbehaving. Windows added
  `NoteServerLine` for this. Sample a BOUNDED tail into the trail rather
  than piping the firehose, and keep the no-blocking-read property that
  makes the current arrangement safe.

- **~~A preview's progress bar sits at 100% saying "Opening the preview…"
  for the entire build~~** — ✅ **Done.** `TaskMilestones` watches for
  `"Done processing"`, `patches/build.ts` prints it and the Dockerfile bakes
  that file into the image.

  **This entry survived only because of its own closing instruction**, which
  said to leave it until a mac had regenerated `app-rules.json`. A mac did, on
  2026-09-01 (`13da5319`), and the contract has carried the right marker ever
  since — so the sentence telling a reader the contract is stale had itself
  gone stale, and acting on it would have meant redoing done work or
  hand-editing a generated file. **Two things ARE still un-refreshed** and are
  the only live part: `TaskMilestones.swift`'s comment still says the edit was
  "authored on Windows and has NOT been built or tested on a mac", and
  `MAC-HANDOFF.md` still lists it under "NEEDS A MAC BUILD/TEST/REGEN". Neither
  is a code change. The original entry follows.

  A preview's progress bar sits at 100% saying "Opening the preview…"
  for the entire build — found 2026-08-19, while re-shooting the
  marketing screenshots; the "Building your site…" step is unreachable.

  **✅ Fixed on Windows, 2026-08-23** (`TaskMilestones.cs`, built and tested,
  664/664 green) — see `MAC-HANDOFF.md`'s "Open — what the mac still owes"
  for the full write-up. **Not yet fixed on the mac**: the matching Swift
  edit (`TaskMilestones.swift`) was made on Windows and has not been built,
  tested, or run through `Plantoir --write-contracts` on an actual mac —
  `contracts/app-rules.json`'s `milestones.preview` is still the stale,
  pre-fix readout until that happens. Leave this item here until the mac
  side is verified.

  Two facts combine. First, `build_site.py` prints "🚀 Launching Quartz
  preview on…" (the FINAL preview milestone's marker) *before* it runs
  `npx quartz build --serve`, because build and serve are one command.
  Second, `ScriptRunner.advanceMilestones` deliberately jumps to the
  highest marker seen (so varying output never stalls the bar) — so that
  early line completes every milestone at once. From then until the site
  appears, a teacher watches a full bar captioned "Opening the preview…
  still working… (Ns)". "Building your site…" (marker "Quartz v4") and
  "Preparing components…" (marker "Installing dependencies" — a line that
  no longer prints, since the image ships `/opt/quartz/node_modules` and
  the script copies it instead of running npm) never display at all. The
  old marketing shot showing "Building your site… still working… (4s)"
  dates from when npm install still ran.

  The fix: give the final preview milestone a marker that appears when the
  server is actually up — Quartz prints a "server listening" line once
  serving — instead of the pre-build launch line. **Verify the exact
  string against a real preview's transcript before pinning it**: a marker
  that never matches leaves the bar stuck one step short, which is the
  same defect wearing the other shoe. This is contract-carried data
  (`contracts/app-rules.json` milestone tables, mirrored in the Windows
  app's `TaskMilestones.cs`), so the change means `--write-contracts`, a
  `GUI-IMPROVEMENTS.md` row, and a Windows note — which is why it was
  recorded here rather than folded into the screenshot re-shoot that
  found it. Measured while pinning this down (instrumented 20 Hz polling of the
  milestone text during real previews): every step before "Opening the
  preview…" is gone before a first sample can be taken — the launcher's
  early output arrives in one buffered chunk — and the sentence then sits
  on a FULL bar for the whole build, observed at 100+ seconds. Until the
  fix ships, the marketing `progress` shot photographs that state, because
  it is the only one the app dependably shows;
  `MarketingScreenshotTests.test4Progress` documents the dependency and
  says to re-take the shot when the fix lands. Worth knowing when fixing:
  the label shows the step whose marker has NOT yet printed, so a marker
  is read in practice as "the previous step ended", whatever the struct
  comment says — and the on-screen sentence is the accessibility VALUE of
  `taskMilestoneLabel`; its label is empty.

## ✅ Done — A rolled-over section publishes over last year's website

Noted 2026-09-06 on `issue/mcp-tool-surface-divergence`, while sorting the
twelve MCP tools Windows serves and the mac does not (`MAC-HANDOFF.md`). Found
by reading code, not by a teacher. **It is a DECISION, not a defect to fix
quietly**, and it is open on BOTH platforms.

A teacher says *"roll this section over to a new year."* On both platforms that
exact sentence is matched in code, never routed by the model, and goes to
`re_date_classes` — `AssistCardCommand.swift:395` and `AssistCardCommand.cs:50`.
On both platforms `re_date_classes` re-dates the section and stops there.

Only `roll_over_section` calls `AssistWorkspace.ReleaseSite`
(`PlantoirTools.cs:911`), and only Windows has `roll_over_section`. What
`ReleaseSite` does is rename `courses/<CODE>/.netlify_sites/section<N>.json`
(or `.cloudflare_sites/`) aside, so the next publish makes a NEW site instead of
overwriting the old one. Shared `scripts/deploy.py` reads that marker, and
nothing under `mac-app/` or `scripts/` renames, clears or year-scopes it —
`CourseRenamer` deliberately leaves it alone and `DeployCommand.swift` only
reads it.

So the first publish after a rollover lands on **last year's URL, which last
year's students may still be reading**, and the teacher is never asked what to
call the new site. That last part is shared Python rather than either app:
`deploy.py`'s `load_netlify_marker` (`scripts/deploy.py:454`) reuses the
recorded site, and `maybe_create_netlify_site_simple` (`:415`) is the only
thing that prompts for a name — it runs only when there is no marker to find.
(The apps' own `hasDeployedBefore` reads the same marker, but it decides
something else: whether a SCHEDULED deploy may be set up at all —
`ScheduledDeploy.swift:225`.) Windows' own comment
(`AssistWorkspace.cs:1915-1928`) says exactly why that is bad — and Windows
still has the hole, because the sentence a teacher says does not reach the tool
that closes it.

**Why this is a decision.** Whether a section keeps one address across years or
starts a new site each September is a product choice, not an obvious bug.
Plenty of teachers want one address forever, and a URL that changes every year
breaks every link anybody saved. Windows made a choice and gave its reason; the
mac has never made one. Three options:

- **Keep them separate, as Windows did.** `re_date_classes` re-dates;
  something else cuts loose. Cheapest — and it leaves the card phrasing
  pointing at the wrong one on BOTH platforms, so the phrasing has to move with
  it or the bug stays exactly where it is.
- **Make the cut-loose part of the rollover phrasing**, on both platforms,
  since "roll over to a new year" is the sentence that means it. Risk: a
  teacher who says it meaning only "fix the dates" loses their address.
- **Ask.** The rollover already tells the teacher to preview and check before
  deciding what students see; one more sentence — "should this be a new
  website, or the same one as last year?" — is the only option that does not
  guess. It is also the only one that needs new wording, which then belongs in
  `contracts/` so both platforms say it identically.

Whichever is chosen it needs the same sentence on both sides. Windows' half is
item 45 in `WINDOWS-HANDOFF.md`.

### ✅ DECIDED 2026-09-08 by Russell — **ASK**, and leave visibility alone

The third option. A rollover asks the teacher whether this should be a new
website or the same one as last year, and does not guess either way.

**And a second question was settled at the same time, because the first one
raised it.** Asked whether a rollover should HIDE the pages that were visible
to students last year, Russell said **leave visibility alone**: re-dating moves
dates, and hiding stays a separate deliberate act. So the two answers together
are "ask about the address, change nothing about who can see what".

**His words on the shape of it:** *"Rollover should redate class pages but not
immediately publish the revised class pages."* Re-dating already satisfies that
and says so — `re_date_classes` deploys nothing and ends with "Nothing was
published or hidden, so students see no change until you deploy." The one
exception is not a bug and stays: overflow classes, which have no class date
left to land on, are set to draft by `SectionReDatePlanner`
(`SectionReDatePlanner.swift:142`) and the reply names each one.

**What this means in practice, said plainly because it is the consequence of
these two answers together.** Pages published last year stay published. So a
teacher who rolls over, chooses "the same website", and then deploys, puts the
whole re-dated year in front of students in one go. That is now a CHOSEN
behaviour rather than an accident — the question at rollover is what makes it a
choice — and the teacher who wants the year revealed class by class hides the
pages themselves, which is an act they already have.

**✅ BUILT 2026-09-08** on `issue/rollover-asks-about-the-website`,
`GUI-IMPROVEMENTS.md` row 451. All three parts below are done on the MAC; the
Windows half is `WINDOWS-HANDOFF.md` item 45. Three things were found by
adversarial review while building and are worth keeping, because each was a
way of shipping something worse than the defect:

- **Cutting a section loose had to turn off any publish set to happen on its
  own.** `runScheduled` re-validates nothing and `deploy.py`'s name prompt
  returns its DEFAULT with no terminal rather than failing, so the overnight
  run would have created a website nobody named while the address students read
  stopped updating.
- **Answering the question is the SECOND turn**, by which time the pages are
  already on their dates — so the re-date plan changes nothing, and returning
  early on that made the answer a no-op with an offer that looked like it had
  worked.
- **"Still pinned" and "never published" cannot share a sentence.** A marker
  that could not be moved was reported as "had not been published anywhere
  yet", which is the opposite of the truth about the one fact this turns on.

The original list of what had to be built follows.

**What was to BUILD — a separate piece, not done in the deciding session.**

1. **The sentence, in `contracts/`**, so both platforms ask identically. It is
   the only part of this that is teacher-facing, and it is the reason this
   option was the expensive one.
2. **The mac needs the machinery at all.** There is no `ReleaseSite` anywhere
   under `mac-app/` or `scripts/` — Windows' is at `AssistWorkspace.cs:1929`,
   called from exactly one place, `roll_over_section`
   (`PlantoirTools.cs:911`). It renames the marker aside rather than deleting
   it, because the marker holds the site id and admin URL and a teacher who
   changes their mind has no other way back. Copy that property.
3. **The card phrasing has to move with it on BOTH platforms.** "Roll this
   section over to a new year" is matched in code
   (`AssistCardCommand.swift:395`, `AssistCardCommand.cs:50`) and routed
   straight to `re_date_classes`. Until it reaches something that can ask the
   question, the decision changes nothing a teacher meets — this is the step
   that makes the other two matter, and it is the one easiest to leave out.

## ✅ Done — Publish stops an active preview itself

Deferred 2026-08-11 as a design problem (the tricky moment being a
build-phase preview — not yet serving — where the console's ownership, the
preview lease, the waiting-for-server state, and publish's own
needs-rebuild decision are all in flight at once). Found already built on
both platforms while checking this list, 2026-08-24, and confirmed by an
adversarial review rather than taken on trust.

Mac: `SectionDetailView.swift`'s `deployAndWait()` sets `isPreparingDeploy`
(disabling the Deploy button and guarding against re-entry), then handles
both cases — `previewRunner.isRunning` for a serving preview, and an `else`
branch awaiting `PreviewStopper.waitForStopsToFinish(...)` for the
build-phase preview the first attempt couldn't handle — before running the
needs-rebuild decision. Windows: `SectionDetailView.xaml.cs`'s
`DeployAsync()` mirrors this with `_isPreparingDeploy`. Contract case
`"deploy with a preview running"` in `contracts/assist-cases.json` is live
(not skipped) and asserts the event order `stopPreview.begins →
stopPreview.ends → deploy`. Shipped across `GUI-IMPROVEMENTS.md` rows 263,
282, 283, 317 and 318 (2026-08-17 through 2026-08-22) — this item just
never got removed from here once it landed.

## ✅ Done — A recreated container publishes pages the teacher HID

Found 2026-08-17 while re-shooting the marketing screenshots; fixed the same
day (commit `9d7db82b`) and ported to the Windows-native runtime path
(`fetch-runtime.ps1`) the same day too — this item stayed on the list only
because nobody had removed it. Confirmed still fixed 2026-08-23, on Windows:
the Dockerfile bakes the `CQ4T-OMIT-ANCHOR` Explorer filter into the image at
build time, `scripts/build_site.py`'s `ensure_quartz_layout_anchor` re-asserts
it on every build and refuses to build rather than warn-and-continue if it
can't restore it, and `verify.sh` §4b asserts it against the built image.

While confirming it, an adversarial review found the checks only did a bare
substring match for the marker string — not that it is actually attached to
a live `omit` Set — so a file could pass every guard while the hidden-page
list was written to a Set nothing consumed. Tightened the same day: `_anchor_
is_structurally_wired()` in `build_site.py` and a matching `verify.sh` grep
now both require the marker's own line to sit directly above `const omit =
new Set`. Not reachable through any writer in this codebase today, but it is
exactly the failure class this fix exists to close. Full write-up, including
what still needs a real mac Docker run to confirm: `MAC-HANDOFF.md`'s "Open"
section.

## ✅ Done on Windows — Assistant replies "deployed" before the deploy finishes

Found 2026-08-19 during the deploy-during-preview adversarial review; fixed
2026-08-23. `SectionDetailView.Deploy_Click`'s body now returns the real
outcome sentence on every exit path — success/partial/all-failed, or
`AssistWording.DeployDidNotFinish` when the deploy never actually ran —
threaded back through `MainWindow.DeployForAsync` to `AssistAgent.RunTool`,
instead of the old unconditional `AssistWording.Deployed`. An adversarial
review agent caught a hang in the first attempt (a single shared completion
field, overwritten by a concurrent busy-branch call, orphaning the first
caller's await with no timeout); rewritten to return the outcome per call
instead, closing the race structurally. Full suite: 667/667. Windows-only
bug — the mac's `deployAndWait()` already awaited the real result, so no mac
work is owed. Full write-up: `GUI-IMPROVEMENTS.md` row 383,
`MAC-HANDOFF.md`'s "Open" section (for awareness only).

## ✅ Done — Write the publishing documentation for plantoir.app

Noted 2026-08-12, once Cloudflare Pages shipped; fixed 2026-08-23.
`website/pages/publishing.html` is a new page explaining all three
destinations properly: which suits whom (Netlify as the default;
Cloudflare Pages for unmetered bandwidth and a free per-section address;
a folder for teachers whose board gives them their own web space), how
to set up each, the exact Cloudflare token permission (Account →
Cloudflare Pages → Edit) and why the app also asks for an Account ID
(a Pages-scoped token can't list its own account), and the 25 MB
per-file limit — which applies to Cloudflare only, not Netlify or a
folder. Added to `site.json`'s nav between "Day to day" and "Support".
Checked against `documentation/07-deployment.md` and the in-app wording
by an adversarial review pass, which caught one overstatement (an
unsourced "no account limits worth worrying about" claim for Netlify,
corrected to the real, documented caveat: the free-tier API can get
rate-limited when a whole staff room publishes at once) and one minor
omission (a local-folder publish also propagates deletions, not just
changed files) — both fixed. `python3 website/build.py --check` passes.
No screenshots added — none of the picker or its detail fields exist in
`shots.json` yet; a future pass could add one. No `contracts/` or
handoff entry — website copy, not app behavior either platform's
teacher-facing suite covers.

## ✅ Done — Nothing verifies that a release actually reached plantoir.app

Noted 2026-08-14; fixed 2026-08-23. `website/netlify_deploy.py` gains
`verify_live()`: after `deploy()` sees Netlify report a deploy "ready", it
fetches `https://plantoir.app` and confirms the version-note line matches
`site.json`'s version, retrying a few times since Netlify reporting "ready"
and its CDN actually serving the new content are not the same instant.
Advisory only — a flaky fetch or lingering propagation lag never turns a
genuinely successful deploy into a reported failure, and a confirmed
mismatch is tracked separately from a fetch/network problem. Comparison
target is deliberately `site.json`'s own version, not the git release tag
(the tag carries a `v` prefix the page text never does). Exposed standalone
as `python3 website/build.py --verify-deploy`, and `cut-release`'s Publish
section now tells the flow to watch and act on the output. Plan and
implementation were each checked by a separate adversarial review before
landing; the implementation review caught a real bug (the CLI's standalone
entry point checked for `--verify` while every doc taught
`--verify-deploy` — a plausible typo would have fallen through into
triggering a real deploy instead of a read-only check). No `contracts/` or
handoff entry — release tooling, not app behavior either platform's
teacher-facing suite covers.

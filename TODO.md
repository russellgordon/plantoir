# To Do

Ideas and deferred work, in no particular order. Add items freely; remove
an item when it ships (finished behaviour is recorded in
[`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md), not here).

- ⚠️ **A scheduled deploy has nobody to answer a question, and `deploy` still
  asks them — found on Windows, 2026-09-06, and it is the same shape on both
  platforms.** Not fixed, because the fix touches the launcher's argument
  contract and that is a decision rather than a repair.

  **How it was found.** `verify-deploy.ps1`'s Netlify leg hung until its own
  900-second timeout. The log says why: the site saved in
  `.netlify_sites/section1.json` no longer exists on Netlify (deleted at the
  other end at some point), so `deploy.ps1` did the sensible thing and fell
  through to creating a fresh one — and asked for a name:

      ⚠️ Saved Netlify site (e8ded3b5-…) was not found on Netlify.
       Creating a fresh Netlify site for this section…
       Enter Netlify site name [mcr3u-s1-2026-gordon]:

  A person at a keyboard answers that in two seconds. The harness had a stdin
  nobody was typing into, and waited forever.

  **PARTLY CLOSED 2026-09-06, and the remaining half is the half this entry is
  about.** The wrapper now runs with `-NonInteractive`
  (`TaskScheduling.TaskRunCommand`), which makes PowerShell's own `Read-Host`
  THROW instead of waiting — that closes `preview.ps1`'s "Continue anyway?"
  question. It does **nothing** for the question described below, because
  `deploy.py`'s `input()` runs in a PYTHON child and PowerShell's flag does not
  reach it. What protects that one today is only `sys.stdin.isatty()` being
  false, which takes the default silently rather than refusing.

  **Why it matters beyond the harness.** `TaskScheduling.WriteWrapperScript`
  generates `& <deploy.ps1> <args>` with no stdin redirection. The mac's `launchd` path has the same shape. (Whether
  Task Scheduler gives it a console is exactly the open question below, and it
  is not assumed here.) So the flagship "publish tomorrow's
  class" feature, on a course whose site has been deleted upstream — or on a
  course whose FIRST publish is the scheduled one, which also asks — reaches a
  question nobody will ever answer. What happens next depends on one line, and
  the paragraph after next says which.

  **What a fix looks like, and why it was not just done.** A
  `--non-interactive` flag that makes `deploy` REFUSE rather than ask, with a
  trail line saying which question it could not ask, and the app then telling
  the teacher their scheduled publish needs one answer before it can run
  unattended. That changes what the app passes the launcher, which is pinned by
  `app-rules.json` → `deployArguments` and run by both suites — so it is a
  contract change, wants agreeing on both sides, and is Russell's call rather
  than a Windows session's.

  **The mechanism, corrected.** An earlier version of this entry blamed
  PowerShell's `Read-Host`. It is not: the question comes from `deploy.py`'s
  own `prompt()` helper (`scripts/deploy.py:325`), which guards every ask with
  `sys.stdin.isatty()`. That single line decides which of two different bugs a
  teacher gets, and BOTH have now been seen:

  * **stdin IS a terminal → Python's `input()` blocks, forever.** Measured:
    two harness runs left a `powershell.exe` and its `python.exe` child waiting
    at that prompt for **45 minutes**, still alive when they were swept up. We
    know it was this branch and not the other because the prompt TEXT was
    printed, and `prompt()` prints nothing at all when `isatty()` is false. The
    failure is "the overnight publish never happened and nothing said so" — the
    teacher's site is simply not updated in the morning.
  * **stdin is NOT a terminal → the default is taken silently.** No prompt is
    printed, the site is created at whatever address the default suggests, and
    a name conflict auto-suffixes (`deploy.py:430`). The failure is "published
    to an address nobody chose", and on a machine with no saved surname the
    address has no surname in it either.

  **So the open question is narrow and answerable**: does Task Scheduler give
  the wrapper a console, making `isatty()` true? That decides which of the two
  a teacher meets. Both are bad, and a `--non-interactive` flag that REFUSES
  rather than asking is the fix for both.

  **Two things that follow whichever branch it takes.** The wedged processes
  survive their parent being killed — including `Process.Kill($true)` on the
  whole tree, which does not even exist under Windows PowerShell 5.1 and threw
  silently in this harness for three runs — so a scheduler that gives up leaves
  the launcher running. And NOTHING reaches the activity trail while they wait,
  so the trail cannot tell a wedged overnight publish from one that was never
  scheduled.

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

- **Choosing a new working folder keeps the OLD window's selection.** Seen
  2026-09-05 while driving row 399: with `ICS3U` selected in one folder,
  choosing a different working folder (with no courses) showed "Course Not
  Found — reload courses from the File menu, or choose a different working
  folder" instead of the empty-folder state, because `chooseWorkspace(at:)`
  reloads the courses but leaves `selection` pointing at a course the new
  folder does not have. Pre-existing, cosmetic, one line to fix (clear the
  selection when the folder changes) — but check `WindowRestorationScenarioTests`
  first, since a RESTORED window sets its folder and then its selection in
  that order and must keep doing so.

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

- **`CourseRenameInterfaceTests` crashes the whole unit run, intermittently —
  and it is PRE-EXISTING, not caused by the special-folders work.** Measured
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

- **The assistant's first turn does not wait for its warm-up** — measured
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

- **A mac problem report can carry nothing the engine said** — found the
  same day. `AssistServerHost` sends `llama-server`'s stdout and stderr to
  `FileHandle.nullDevice`. That is load-bearing (an unread pipe is what
  wedged the Windows server mid-request, and this is why the mac never
  had that bug) but it also means model-load errors, slot warnings and
  timing lines reach nobody — the one place they could matter is a report
  from a teacher whose assistant is misbehaving. Windows added
  `NoteServerLine` for this. Sample a BOUNDED tail into the trail rather
  than piping the firehose, and keep the no-blocking-read property that
  makes the current arrangement safe.

- **A preview's progress bar sits at 100% saying "Opening the preview…"
  for the entire build** — found 2026-08-19, while re-shooting the
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

- **Container recreation can kill live previews** — noted 2026-08-11.
  Every launcher "ensures" the working folder's container, and on a
  toolchain-recipe hash or mount mismatch it recreates it (`docker rm
  -f`) — taking any live preview servers down with it. In steady state
  hashes match and this never triggers; it can bite mid-session only in
  rare cases (e.g. an app update refreshing `.toolchain` while another
  window previews). A thorough fix would make the ensure-container step
  decline (or warn) when the container hosts running previews. Low
  priority — rare, and the next preview self-heals.

- **AI Assist — the rest of it**, updated 2026-08-14 after a full
  live-tested day on the `ai-assist` branch, since folded into `main`
  (not yet in any tagged release). The
  Windows in-app assistant is now **working end to end**: approval gate
  (deploys only), embedded model with a verified once-ever prompt cache,
  the promise card handled as deterministic commands, page edits doing
  stop-edit-offer around the app's own preview, and the whole loop moved
  to `Plantoir.Core` with tests covering every promise —
  [`research/ai-assist/HISTORY.md`](research/ai-assist/HISTORY.md) part 2 §10 is the record, and
  `MAC-HANDOFF.md` carries the mac side's pickup entry. What remains:

  **(a) The CSV reschedule — built; what is left is around the edges.**
  It shipped in the plan-then-write shape this item asked for.
  `Plantoir.Core/Assist/Timetable.cs` reads a school's sheet without
  assuming its layout — which row is the header, which column holds dates,
  and how the dates are written are all worked out from the sheet itself —
  and `ReDatePlan.cs` produces the diff table shown before anything is
  written. The MCP surface is `read_timetable` → `plan_re_date_classes` →
  `re_date_classes`, plus `roll_over_section` for a new year, all in
  `Plantoir.Mcp/PlantoirTools.cs`, with tests in
  `Plantoir.Tests/TimetableTests.cs`. §5 of the handoff records 26 classes
  re-dated against a teacher's own spreadsheet, checked by an independent
  parser. Two things are genuinely left:

  * **Only CSV comes off disk.** `TimetableSource` reads a local file as
    plain text, or exports a shared Google Sheet by link. A teacher's
    `.xlsx` sitting in Downloads is neither, so they have to export it
    first — while the tool's own help text says “timetable.xlsx”. Not
    worth fixing — teachers export to CSV without friction, and reading
    `.xlsx` off disk buys little.

  **(b) The shared activity lease, finished.** `WorkLease` files under the
  working folder now let the GUI decline a preview while the assistant
  builds, but the full both-directions story (server honouring the GUI's
  claims across every operation, and the mac app reading the same files)
  is still a shared-design item — agree the remaining shape with the mac
  side first.

  **(c) Re-measure the conversational residue — partially done, 2026-08-24.**
  Re-run against Qwen2.5-1.5B (native, Vulkan) with a two-sentence prompt
  tweak: full write-up and raw runs in
  `research/ai-assist/conversational-residue-results.txt`. The **undo
  over-salience** cluster (a "posted X by mistake" unpublish request
  routed to `undo_last_change`) is fixed, and a related case not in the
  original TODO wording — a hide request declined outright — is fixed as
  a side effect; conversational-only accuracy went from 85% to 91-94%
  across two runs, with no new failures elsewhere. Shipped in
  `AssistAgent.cs` and `AssistAgent.swift` — **the Swift side is written
  but, per the usual constraint of a Windows session, not yet built or
  tested on a mac**; see `MAC-HANDOFF.md`.

  **Still open: the deletion probe's decline never came back.** "Delete
  the Unit 1 folder" still routes to `cancel_scheduled_deploy` instead of
  declining, unchanged across every wording tried. A more explicit
  sentence naming that tool directly was tried and made things worse
  elsewhere (two previously-clean conversational cases regressed) — logged
  in the results file as a rejected option so it isn't retried unmeasured.
  Left for a future pass.

- **A "prepare for start of year" operation, and the audit behind it** —
  deferred 2026-08-13, from a real session on the `ai-assist` branch.

  A teacher asked for "every class past Unit 1, Day 1, and everything those
  link to, into draft". Applied exactly, that rule left **32 course-level
  pages in SNC1W still published** that no class page links to at all — a
  whole unit's concepts, plus unassigned tasks and portfolio pages. The teacher
  spotted one (`Concepts/Astronomical Phenomena`, reachable only from an
  investigation that is itself unreferenced) and the rest fell out of an
  audit script.

  **The lesson: link-reachability is a weak proxy for "not yet taught."** A
  link-following rule cannot see a page no class links to, and those are
  precisely the pages a teacher has written ahead. If Plantoir grows a bulk
  start-of-year operation, base it on unit number, date, or an explicit
  teacher-facing "not yet taught" flag — not on what is reachable.

  The audit half of this shipped, as the read-only `check_section` tool in
  `Plantoir.Mcp/PlantoirTools.cs`. It cross-references a section's pages
  against every wikilink and reports two of the three groups: links on
  visible pages that lead to a hidden one (a student clicks and finds
  nothing), and pages nothing links to — still published, still listed in
  Quartz's explorer, and invisible to any rule that follows links. That
  second group is what proved the *rule* incomplete.

  What is still missing is the third group, **linked-but-missed**: pages a
  class does link to that a bulk change should have caught and did not. Its
  being empty is what proved the job complete, and `check_section` cannot
  say so today. Missing too is the bulk start-of-year operation itself —
  worth having with or without any AI, and per the lesson above it should
  key off unit number, date, or an explicit "not yet taught" flag rather
  than reachability. (`LinkGraph.cs`'s doc comment quotes 50 unreachable
  course-level pages, but for a "sample course" it does not name — a
  different measurement from the 32 above, not a contradiction of it.)

## Docker build cache is never cleared (deliberately, for now)

`docker system df` on the dev mac, 2026-08-23: 1301 build-cache entries,
14.30 GB, 14.25 GB reclaimable — a bigger number than the images that were
leaking beside it (fixed 2026-08-23, `GUI-IMPROVEMENTS.md` 352).

**Not fixed on purpose, and this is the record of why so it does not get
re-proposed:** `docker builder prune` is GLOBAL. There is no per-project or
per-tag filter, so a launcher calling it would throw away the build cache of
every other project sharing this Colima VM (Supabase, among others) — the same
constraint that shaped the image cleanup, but with no narrow form available.
Clearing it stays a by-hand developer job:

```bash
docker builder prune          # global — read the size it offers first
```

A teacher's cache is also a fraction of this: the 14 GB here came from twelve
days of toolchain edits, where a teacher builds on install and then not again.
If this is ever revisited, the thing to find out first is whether BuildKit can
be given a scoped cache per build context — a filtered prune, not a bigger
hammer.

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


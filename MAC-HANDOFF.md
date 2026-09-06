# macOS App — Handoff

> **New here? Read [`MAC-BOOTSTRAP.md`](MAC-BOOTSTRAP.md) first.** It says how
> to take work that arrived from Windows, and how to add a feature on this side
> so it reaches them as data rather than as a surprise. This file is the ledger
> it sends you to.

The ledger of work that originated on the **Windows side** and needs — or
deserves a look from — the **macOS app**. The reverse of
[`WINDOWS-HANDOFF.md`](WINDOWS-HANDOFF.md): read this when syncing the mac
after Windows-side sessions.

**Read it top-down and stop when you like.** Everything still owed is in the
first two sections; everything already dealt with is kept below them, in full,
because the reasoning is the point of the file and deleting a finished entry
throws away why the mac does what it does.

| Section | What is in it |
|---|---|
| [Contract cases waiting on the mac](#contract-cases-waiting-on-the-mac) | Cases proposed from Windows that the mac suite is failing on. Read FIRST when a suite goes red. |
| [Open — what the mac still owes](#open--what-the-mac-still-owes) | Work not yet done here. |
| [For awareness — no mac code needed](#for-awareness--no-mac-code-needed) | Things to KNOW, not to do: shared decisions, frozen names, coordination points. |
| [Done — the ledger](#done--the-ledger) | Finished, marked in place with what landed and where. History, and the reasoning behind decisions the code no longer explains. |

Cross-side rebases rewrite commit hashes, so treat hashes as hints from the
moment of writing — file and test names are the durable pointers.

## How to write an entry

The good entries below already do this; it is written down so the next one
does not have to infer it from twenty examples. An entry carries:

1. **A bold title that says what CHANGED**, then `(source, date, commit)` —
   "Windows", "shared", or "Windows + shared" for work in `scripts/`.
2. **What it fixed, and WHY it was done that way.** The why is the half that
   travels: the mac can read a diff, it cannot read a decision. Include what
   was **rejected**, or it gets proposed again and costs the same afternoon
   twice.
3. **Numbers, with the hardware they came from**, for anything measured. This
   side has no way to find out what a Windows teacher's machine does. "The
   Vulkan build was faster" cannot be acted on; "43 tok/s against 11 on CPU,
   Intel Iris Xe" can.
4. **Where the reference implementation lives** — file and test names, which
   outlast commit hashes across rebases.
5. **Whether the mac is expected to match it, or merely to know.** Those are
   different asks, and the second section of this file exists for the latter.

If a teacher can see the change, it also wants a row in
[`GUI-IMPROVEMENTS.md`](GUI-IMPROVEMENTS.md) — that log is the record of the
product, not of one platform.

## Contract cases waiting on the mac

> **v1.1.0 cut sheet (Windows assets ready, 2026-08-20).** The verified
> Windows artifacts live on the Windows machine and will be uploaded FROM
> there (`gh` is authed there) once the tag exists — so cut the release as a
> DRAFT, tell Russell, and publish after the assets attach. Hashes for the
> notes' SHA-256 table:
> `PlantoirSetup.exe` 224.5 MB
> `9990bcacade548a35cbd5b11f65dbf79d4a0236eeeee4d4d0e5322204c96527e` ·
> `Plantoir-win-x64.zip` 379.9 MB
> `b141c7ac30116c9836334e90472e5a2527fb4e50629c56d4c2f258f437cbb1ba`.
> Built from commit 8e9faab0, proven by five clean-machine smoke tests
> (install → course → preview → assistant → deploy, no .NET/WSL/Docker on
> the machine). The macOS DMG does NOT ship in this cut — see RELEASING.md
> "Two platforms, one version series": the mac joins v1.1.0 after the gate
> list below is green.


**Nothing is outstanding.** Both cases proposed for v1.1.0 were cleared on
2026-08-20 — one implemented, three retired — and the reasoning for each is in
the ledger below under "The teacher-made-link case is implemented, and the
three setup cases are retired".

The mechanism, in one paragraph. `Plantoir --write-contracts` runs on the mac,
so the Windows side cannot regenerate the derived halves of
[`contracts/`](contracts/README.md) — but the **authored** halves (`scenarios`,
`nearMisses`, `promptHistory`, and the case lists in the other files) survive
regeneration untouched. So a behaviour invented on Windows can be proposed as
a case, and **the mac suite then fails until the mac implements it.** That is
the mechanism working, not a break: verified on purpose by adding a case for
an event the mac has no support for, which failed naming the case and the
missing step rather than passing quietly.

When a case is proposed, add a line here naming it, so whoever meets the red
suite reads it as a request:

> - `contracts/assist-cases.json` → `scenarios` → **"<case name>"**, proposed
>   <date>. What it asks for, and why. Reference: `<Windows file>`.

Remove the line when the mac implements it, and mark the matching entry below
`✅ DONE` — the ledger keeps the history, this section keeps only what is
outstanding.

## Open — what the mac still owes

- **Windows now has the exclusions AND the protection model, and three things
  come back to the mac** (Windows, 2026-08-25, branch
  `issue/windows-special-folders-parity`, `GUI-IMPROVEMENTS.md` row 385).
  Windows implemented handoff items 11 and 12: `excluded_items`,
  `graded_folders` and `curriculum_folder` in `CourseConfiguration.cs`, the
  `ItemProtection` model in the list editors and the marks checklist, a Marks
  section in Course Settings (which this app never had), and the wizard's marks
  control. Mostly a **know, not a do** — but three items below are genuine
  questions for this side.

  **The one finding worth the mac's attention: the two pieces could not be
  shipped separately, and an adversarial review is what caught it.** Item 11
  (exclusions) and item 12 (protection) read as independent pieces of work, and
  Windows implemented item 11 first. That was wrong, and quietly so. Before
  `excluded_items` existed, a Windows teacher who removed `All Classes` got it
  back at the next preview, because `preflight_update_course_config`
  rediscovers folders — the missing protection model was survivable. The moment
  the app writes `excluded_items`, row 377 makes that key AUTHORITATIVE, the
  folder never comes back, and the next-class button and the schedule write
  into a folder that no longer publishes. Same for the resolved curriculum
  folder (the map silently stops building) and a section's `index.md` (the
  section cannot be published at all). **Item 11 without item 12 turns a
  recoverable gap into an unrecoverable one**, and nothing in either item says
  so. Worth a line in `WINDOWS-HANDOFF.md` if anyone ever ports these
  separately again.

  **1. The Course Settings tip sentence is contract-pinned on NEITHER
  platform, and now the two apps word the same rule differently.** Row 375 says
  the mac "amended Course Settings tip callout to except removed names". That
  is a sentence a teacher READS, so by CLAUDE.md rule 2 it belongs in
  `contracts/`; `grep -rn "added to your site automatically" contracts/`
  returns nothing. Windows therefore wrote its own — "…The exception is
  anything you remove here: it stays off your site, even if you make it again
  in Obsidian, until you add it back on this page." **No case has been
  proposed**, deliberately: proposing one would redden the mac suite over
  wording the mac already ships, and choosing WHICH sentence becomes the
  contract is the mac's call. If the mac agrees it belongs there, add it under
  `specialNames` and Windows will take the mac's wording verbatim.

  **2. `reconciledGradedFolders` on the MAC does not match the Python, and
  that is a finding rather than a question.** This entry originally asked which
  way the mac resolves a case collision. The answer, checked since: it resolves
  it neither way — `NewCourseWizardView.reconciledGradedFolders` is an exact
  `validChoices.contains(folder)` filter with no case-insensitive lookup at
  all, so a declared `tasks` against an actual `Tasks` is DROPPED. Both
  `setup_course.py:graded_folders_for` (via `actual_lookup`) and Windows's
  `GradedFolderRule.Reconciled` map it to the actual folder instead. So the mac
  silently narrows a pool the build would have kept. Windows also had a bug
  here — `Dictionary.TryAdd` keeps the FIRST match where the Python's dict
  comprehension keeps the LAST — and it is fixed. There is no contract case
  pinning any of this, which is why it survived on both sides; adding one is
  the mac's call, and Windows will run whatever it says.

  **3. Revert leaves a trail line for a removal that did not happen — and the
  mac has the identical shape.** Proven here: `Exclude("shared", "A")` then
  `DiscardChanges()` puts the config back, but `item excluded` is already on
  disk. Windows writes the note inside the editor's remove callback; the mac
  writes it inside `onRemove` and has a Revert too. So this is **parity, not a
  Windows regression** — but CLAUDE.md rule 5 says "a line describing what the
  feature used to do is worse than no line, because it will be believed", and a
  teacher who removes a folder, thinks better of it, and Reverts leaves a trail
  claiming they excluded it. The honest fix is to record on SAVE rather than on
  click, on both sides. Flagged rather than fixed unilaterally, because
  changing when the mac records an event is not a Windows decision.

  **4. Does the mac's wizard block on a coverage switch a teacher cannot
  reach?** Windows's `CourseConfiguration.CurriculumCoverageEnabled` was
  written as an identity function on the switch; the mac's takes five
  arguments. Restored to five here, because the wizard only CREATES that
  switch for a code with example content that includes curriculum, and only
  ENABLES it while pre-populate and curriculum pages are on — so on the
  commonest from-scratch path the ⓘ named a control that was not on the
  screen, and there was no way out inside the wizard. The mac's version has
  the gates, so the mac is probably fine; what is worth CHECKING is the second
  half. `NewCourseDialog.BuildConfiguration` writes
  `include_curriculum_coverage` from the RAW switch, so a from-scratch course
  is created with the map on while the protection rule says it is off — the
  wizard will let its curriculum folder go after a confirmation, and the build
  then reports `curriculumCoverageFoundNothing`. Windows chose that failure
  deliberately over a deadlock: the teacher is told something and has a way
  forward. **If the mac writes the same key the same way, it has the same
  tension**, and whether the honest fix is a reachable coverage switch on the
  from-scratch path is a product decision rather than a port detail. Not taken
  unilaterally here.

  **5. Two wizard inputs where Windows knowingly does less than the mac.**
  Both are written down rather than hidden, per rule 4. (a) The wizard passes
  `null` for the configured curriculum folder — the mac passes
  `ExampleContentCatalog.curriculumFolder(forCode:) ?? SkeletonCatalog...`,
  and this app has neither helper. So a skeleton family whose curriculum
  folder is called something without the word "curriculum" in it is protected
  on the mac and NOT on Windows. It protects too little; it never protects the
  wrong folder. (b) `JurisdictionForCode()` reads the PROVINCE DROPDOWN, where
  the mac derives it from the course CODE. Windows's choice keeps the switch's
  own label and the sentence naming it in agreement, which is the property
  that matters for an ⓘ — but an Ontario-selected teacher typing a BC code
  gets a different sentence on each platform.

  **6. A test on this side was writing into the REAL activity trail, and the
  mac should check whether its own suite can.** `SiteHealthRunnerTests.Dispose`
  restored `ActivityTrail`'s log path to `null`, which is the REAL trail, so
  `TestTrailRedirect`'s module-initializer redirect was defeated for every
  test that ran afterwards. Fixture courses and lines such as "removed the
  small assistant — 1.12 GB freed" were written into this machine's
  `%LOCALAPPDATA%\Plantoir\Logs\activity.txt`. Nothing was actually removed —
  the 1.04 GB model file is untouched, last written 2026-08-22 — but a
  diagnostic record carrying events that never happened is worse than no
  record, and it is the exact failure rule 5 is about. Fixed by restoring the
  suite's scratch path instead of null, and by putting the class in the
  serialized collection: the trail path is a process-wide static, and xUnit
  parallelises test CLASSES. **If any mac test sets that path and restores
  nil, the mac has the same leak.**

  **7. The acceptance was DRIVEN, not reasoned about, and the method is worth
  having.** `System.Windows.Automation` from stock Windows PowerShell 5.1
  drives WinUI 3 well enough to open an ⓘ flyout, read its text, and
  photograph it — which is exactly how the mac found its truncated popover,
  and how this side confirmed the same bug does not reproduce: the longest
  `specialNames` sentence wraps to five full lines at 600×187 device px. A
  fresh ICS3U with example content declined showed the ⓘ on exactly `Tasks`,
  `Ontario Curriculum` and `All Classes`; the written config carried
  `graded_folders: ["Tasks"]` and `per_section_folders: ["All Classes"]`; and
  a real `preview.ps1 --build-only` after removing `Discussions` in Settings
  printed the skip line and emitted a `public/` with zero occurrences of it,
  the teacher's own folder still in the vault. **What the drive caught that no
  test did** was the deadlock in item 4 above — and, humblingly, the drive had
  already photographed that flyout without noticing the switch it named was
  unreachable. Driving proves the pixels; it does not by itself prove the
  sentence is actionable.

  **What was rejected on this side, and why.** (a) Case-INSENSITIVE matching
  for `excluded_items` — the neighbouring "Media" refusal is case-insensitive,
  so matching it felt consistent, but `preflight_update_course_config` builds a
  plain Python `set` and tests exact membership; the app must agree with the
  BUILD, not with its neighbouring control. (b) Writing `excluded_items` and
  leaving the name in `shared_folders`, on the grounds that row 377 made the
  key authoritative — rejected because that reconciliation runs at the NEXT
  build, and between the save and that build Settings would show a folder the
  teacher had just removed. (c) Reading the blocked sentences out of
  `contracts/shared-rules.json` at RUNTIME rather than writing them into
  `SpecialNames.cs` — rejected for the reason `AssistWording` is written out:
  the contract is generated from the macOS app, so a changed sentence must fail
  a Windows BUILD, not change a teacher's screen on a machine the tests never
  ran on. It earned its keep immediately — the contract test caught a
  transcription slip where `curriculumFolderBlockedByCoverageMap` had lost the
  words "for the coverage map".

  **Three switch labels were RENAMED on Windows to match the contract's
  sentences.** This is the one place Windows changed teacher-visible wording,
  and the reason is that the blocked sentences name a switch BY NAME: an ⓘ
  saying "turn off *Publish the curriculum coverage map*" is worse than useless
  when the app's toggle says "Include Curriculum Coverage map". Course
  Settings' coverage toggle is now `SpecialNames.CoverageSwitchLabelInSettings`
  ("Publish the curriculum coverage map"), the wizard's is
  `CoverageSwitchLabelInWizard` ("Include the curriculum coverage map"), and
  the wizard's curriculum-pages toggle is built per-province, so a BC teacher
  is told about a switch a BC teacher can see rather than always "Ontario". The
  contract's wording won over the Windows label in every case, because the
  contract is generated from the mac and a Windows-only paraphrase is drift
  rather than a decision. **If the mac's own labels differ from these, the mac
  has the same bug** — a test (`EveryBlockedSentenceNamesASwitchTheAppActuallyHas`)
  now pins label against sentence on this side, and the mac has no equivalent.

  **Numbers, from this hardware** (Windows 11 Pro 26200, x64): the Windows
  suite went from **673 tests with 2 failing** on the mac's merge to **765
  passing, 0 failing**. The two failures were
  `FileFormats_CourseConfigKeys_MatchesContract` — which fails on
  `curriculum_folder`, NOT `excluded_items`, worth knowing if the mac ever
  reads that failure as a smaller job than it is — and
  `SharedRules_ActivityTrailEvents_Exist`. One honest caveat on the first: it
  asserts `Assert.Contains($"\"{key}\"", source)` against the raw TEXT of
  `CourseConfiguration.cs`, so it goes green on a key mentioned in a comment.
  Its greenness is evidence the keys are spelled in that file, not that they
  are implemented; the behaviour is covered by `ExcludedItemsTests` and
  `GradedFolderContractTests` instead.

  Reference: `windows-app/Plantoir.Core/Models/` — `CourseConfiguration.cs`,
  `GradedFolderRule.cs`, `CurriculumFolderRule.cs`, `SpecialNames.cs`,
  `ItemProtection.cs`; `windows-app/Plantoir/Views/FormBuilders.cs`,
  `CourseSettingsView.xaml.cs`, `NewCourseDialog.cs`;
  `windows-app/Plantoir.Tests/` — `ExcludedItemsTests.cs`,
  `GradedFolderContractTests.cs`, `SpecialNamesContractTests.cs`,
  `ItemProtectionTests.cs`.

- **The site-health FINDINGS DIALOG does not exist on Windows, and the mac
  side should know it is not there** (Windows, 2026-08-25, branch
  `issue/windows-special-folders-parity`, `GUI-IMPROVEMENTS.md` row 384).
  This is a **know, not a do** for the mac — nothing here asks the mac to
  change — but `WINDOWS-HANDOFF.md` item 10 currently reads as though Windows
  already surfaces these findings ("Windows receives the finding in the
  `PLANTOIR_HEALTH:` transcript line and displays the contract-authored
  sentence and detail without re-wording"), and on 2026-08-25 that was not
  true of any released or unreleased Windows build. Grepping `windows-app/`
  for `PLANTOIR_HEALTH` returned nothing at all, and
  `ActivityTrail.Event.FolderProblemFound` / `FolderProblemRepaired` had been
  declared since the trail was built with **no call site anywhere in the C#**.
  So every check the mac has shipped since row 357 — `curriculumCoverageFoundNothing`,
  `courseTeachesNothing`, `mediaFolderMissing`, `sectionIndexMissing`,
  `handWrittenCoveragePage`, and now `noGradedFolders` — has been printed into
  a Windows build console and read by nobody.

  **What landed this session** is the half a contract can gate: a
  `SiteHealthFinding` parser (`windows-app/Plantoir.Core/Models/SiteHealthFinding.cs`),
  its collection in `ScriptRunner`, and a `folder problem found` trail line per
  finding. **What did NOT land** is the teacher-facing dialog, the Fix button,
  the repair itself, and the "Preview Again" afterwards — mac rows 357–358,
  362–364, 367–372. That is a feature, not a port detail, and doing it inside a
  parity session would have meant inventing Windows wording for six mac dialogs
  without the mac's own review history to hand. It is owed by Windows to
  Windows; it is listed here so the next mac session does not read item 10 and
  assume parity that is not there.

  **What was rejected, and why.** Making `RepairableChecks` read
  `contracts/shared-rules.json` at RUNTIME was rejected: the contract is
  bundled into the app today, but a runtime read means a teacher's machine can
  disagree with the test suite about which checks get a Fix button, and the
  house rule here is the opposite — hardcode the answer in code and let a test
  pin it against the contract, so drift fails a build rather than a teacher.
  Deciding repairability from the finding's `fixable` FLAG was also rejected,
  for the reason `siteHealth.repair.neverOffered.why` already gives: the flag
  means "this kind of thing is repairable", not "this app has a repair for it".

  **Reasoned from the code, NOT measured** — said plainly because an
  adversarial review caught this paragraph claiming otherwise, and a
  code-reading dressed as a measurement is the failure CLAUDE.md rule 4 exists
  to prevent. No split was observed in the field; what IS on the record is that
  `ScriptRunner.BufferOutput` coalesces pseudo-console output on a **150 ms**
  cadence and hands `ReceiveOutput` whatever bytes are ready, so a
  `PLANTOIR_HEALTH:` line CAN be split across two flushes. The findings are
  therefore collected **line-buffered, not per output chunk**;
  `SiteHealthRunnerTests.AFindingSplitAcrossTwoChunksIsStillFound` splits a
  real line in half and pins it. If the mac ever parses these from a live
  stream rather than a finished transcript, the same trap is waiting.

  **Two defects the adversarial review found in the first cut, both worth
  knowing on the mac.** (1) The carry buffer trimmed to its TAIL when it
  outgrew 8 KB, copied from the milestone scanner's sliding window — which is
  INVERTED for a line buffer: after the newline loop the carry is the HEAD of
  one unterminated line, so the marker sits at the front and a tail-trim throws
  the finding away. It now drops the carry only when the carry cannot contain a
  marker, with `AVeryLongUnterminatedLineDoesNotLoseItsMarker` pinning it —
  and that test was confirmed to FAIL against the old code, not merely to pass
  against the new. (2) The findings property handed out the live mutable list
  that `Run(keepTranscript: false)` calls `.Clear()` on; it returns a snapshot
  now. Neither was reachable today, because nothing reads the collection yet,
  but both sit exactly on the seam a dialog attaches to.

  **The three new trail events** — `item excluded`, `item re-included`,
  `removal blocked` — are declared in `ActivityTrail.Event` with this piece,
  because `activityTrail.mustRecord` names them and the Windows suite pins the
  enum against that list as a SET, so the suite cannot be green without them.
  Their call sites arrive with the Course Settings work. That is the same
  declare-with-no-caller shape that left `FolderProblemFound` dead for months,
  so the enum carries a comment saying so rather than repeating it silently.

  Reference: `windows-app/Plantoir.Core/Models/SiteHealthFinding.cs`,
  `windows-app/Plantoir.Core/Scripting/ScriptRunner.cs` (`CollectHealthFindings`),
  `windows-app/Plantoir.Tests/SiteHealthContractTests.cs`,
  `windows-app/Plantoir.Tests/SiteHealthRunnerTests.cs`.


New items go at the TOP of this section, and move to the ledger when done
rather than being deleted.

> **Keeping this list is a standing instruction, not a courtesy** (`CLAUDE.md`
> rule 4). A Windows session that creates work for the mac adds an item here in
> the same session, and this list is the mirror of `WINDOWS-HANDOFF.md`'s
> numbered "What is still genuinely outstanding" — the same obligation,
> pointing the other way.
>
> The reason is the same in both directions: these files are read top-down and
> abandoned partway, so this section is the INDEX and the ledger below is the
> manual. A change that creates an obligation for the other platform and does
> not list it has, from their side, not been handed over at all.

- ⚠️ **THE CONTRACT'S `stopPreview` PROSE IS NOW WRONG ABOUT WINDOWS, and only
  the mac can regenerate it** (Windows + shared, 2026-09-05). Three sentences
  in `contracts/shared-rules.json` → `stopPreview` describe a state that
  stopped being true today. They are generated from the mac, so this side
  cannot fix them without hand-editing a generated key:

  - `modes.servingOnly` ends "Implemented today by `build_site.py` inside the
    container, and there ONLY: run natively on Windows there is no `/proc`,
    the process list comes back empty and this does nothing, so the overwrite
    race is still live on that platform. That is a gap, not a decision." **The
    gap is closed.** `stop_preview.read_snapshot()` now dispatches to a native
    `Get-CimInstance Win32_Process` reader, so `servingOnly` runs on Windows
    exactly as it does in the container.
  - `notShared` → "Which processes are even considered" says Windows filters
    to `node.exe` and `python.exe` for direct evidence. **It no longer does.**
    The filter is gone: it refused most of the contract's own fixtures
    (`python3`, `npm`, `esbuild`, `sh`), and the judgement the contract left
    to this side has been made — a process carrying this section's build
    directory on its command line IS this section's process. The mac and
    Windows now consider the same processes.
  - `notShared` → "How a process is ended" and "How hard a publish build
    insists" both say Windows ends things with `Stop-Process -Force`. Still
    true of `preview.ps1`, but no longer the whole story: `build_site.py`'s
    own `servingOnly` sweep now runs natively there too and ends processes
    with `os.kill` (which is `TerminateProcess` on Windows, whatever signal
    number it is handed).

  Nothing is asked of the mac's CODE here — only that the generator be re-run
  with these sentences corrected, since a contract that describes a race as
  "still live" is exactly the kind of stale guidance `CLAUDE.md` rule 3 says
  is worse than none. Reference: `scripts/stop_preview.py`
  (`read_windows_snapshot`, `read_snapshot`, `stop_one`), `preview.ps1`
  (`Get-SectionProcessesToStop`), `windows-app/test_stop_preview.ps1`.

- ⚠️ **A SIGNAL WAS DOWNGRADED ON THE MAC FROM WINDOWS, AND IS NOW PUT BACK —
  check nothing else rode on it** (Windows + shared, 2026-09-05). Worth ten
  seconds of the mac's attention because the mistake was invisible and the
  file is shared. Routing `build_site.py`'s `stop_preview_serving` through a
  new `stop_one()` helper — written for Windows, where there is nothing to
  ask with — silently changed the container's `servingOnly` kill from SIGKILL
  to SIGTERM on every platform. The contract states the reason it must not
  ask first (a second spent waiting politely is a second in which the
  preview's mirror can overwrite the build being protected). Found by review
  and fixed in the same session: `stop_one(pid, signum)` now takes the
  signal, `build_site.py` passes `getattr(signal, "SIGKILL",
  signal.SIGTERM)`, and `TheSignalAPublishBuildSendsIsNotNegotiable` in
  `scripts/test_stop_preview.py` pins it. **The mac's behaviour is
  unchanged from before this branch** — this is a note that it was briefly
  otherwise on this branch, not an ask.

- ⚠️ **`WINDOWS-HANDOFF.md` item 20's first owed bullet was answered a
  different way than it asked, deliberately** (Windows, 2026-09-05). It said
  to call `preview.ps1`'s own `--stop` matcher from the `--build-only` path.
  That was not done, and should not be: `deploy.py` reaches
  `build_site.py --build-only` directly (`rebuild_for_production`), never
  through the launcher, so a fix living in `preview.ps1` leaves the Netlify
  and Cloudflare route racing — which item 20 itself points out two
  paragraphs later. Fixing it one level down in `stop_preview.read_snapshot()`
  covers `preview.ps1 --build-only`, `deploy.ps1`'s folder branch,
  `deploy.py`, scheduled deploys and `plantoir-mcp.exe` in one edit, and
  every future caller for free. Item 20 can be marked done on that bullet.

- ⚠️ **NEEDS A MAC BUILD + TEST — assistant system-prompt tweak fixes
  "undo over-salient"** (Windows, 2026-08-24, TODO.md item (c)). The
  Swift edit is made — `AssistAgent.swift`'s `systemPrompt(course:section:)`
  — but has NOT been built or run through the mac's XCTest suite, and the
  measurement behind it was done entirely against the Windows-native
  Qwen2.5-1.5B (Vulkan), so it has not been re-verified on Metal either.

  What changed and why: with the promise card's eleven fixed shapes now
  handled as deterministic commands (they never reach the model), what
  still routes through the model is a teacher's own phrasing, last
  measured at 72% overall in `promise-card-results.txt` with two flagged
  problems — "undo over-salient" (a `unpublish` request phrased as "I
  posted X by mistake" was answered with `undo_last_change` instead) and
  a hide request's decline lost. Re-measured 2026-08-24 against the
  Windows-shipped small tier (Qwen2.5-1.5B-Instruct Q4_K_M, native
  llama-server.exe, Vulkan, `--reasoning off --reasoning-budget 0`, 3
  trials/probe, temp 0.1): baseline conversational-only accuracy 46/54
  (85%), full write-up and raw transcripts in
  `research/ai-assist/conversational-residue-results.txt`.

  Two sentences added to the system prompt (verbatim in the results file
  and in both `AssistAgent.cs` and `AssistAgent.swift`) fixed both flagged
  clusters cleanly across two runs (conversational-only 51/54 and 49/54 —
  94% and 91%), with zero new failures and zero polarity inversions in
  either run. **Rejected**, and logged so it isn't retried unmeasured: a
  third wording that named `cancel_scheduled_deploy` explicitly, to also
  fix a still-unsolved "delete the X folder" probe (routes to
  `cancel_scheduled_deploy` instead of declining, unchanged by any wording
  tried) — it did not fix that probe and broke two previously-clean cases,
  dropping full-suite accuracy to 79%. The lesson matches
  `AssistToolRunner.localTools`'s doc comment about tool descriptions: a
  small model reads an extra clause as new signal to weigh, not a boundary
  to respect — naming an unrelated tool inside a "don't do X" sentence
  raised its salience rather than lowering it.

  **What the mac owes:** build, run the XCTest suite
  (`AssistModelTierTests` and friends), and — if there's appetite —
  re-run an equivalent probe set against the Metal-native `llama-server`
  to confirm the same gain holds there (the Windows measurement is
  evidence, not proof, for a different backend and quantization path). No
  contract case needed — the system prompt isn't contract-carried today
  (checked: no `systemPrompt` key anywhere under `contracts/`).

- ⚠️ **NEEDS A MAC `verify.sh` RUN — authored and reasoned through on
  Windows, unverified against a real Docker build.** TODO.md's "A recreated
  container publishes pages the teacher HID" turned out to already be fixed
  (2026-08-17, commit `9d7db82b`, ported to the Windows-native runtime path
  the same day via `fetch-runtime.ps1`) — the Dockerfile bakes the
  `CQ4T-OMIT-ANCHOR` filter into the image, `build_site.py`'s
  `ensure_quartz_layout_anchor` re-asserts it on every build and refuses
  (`sys.exit(1)`) rather than warn-and-continue if it can't restore it, and
  `verify.sh` §4b asserts it against the built image. TODO.md's item was
  simply stale and has been removed.

  What actually shipped THIS session, on top of that: an adversarial review
  of the existing fix (asked for by Russell, not found by accident) turned up
  a real gap — every one of those checks did a bare **substring** match for
  the literal string `CQ4T-OMIT-ANCHOR`, not that the marker comment is
  actually attached to a live `omit` Set. A file could contain that string
  somewhere unrelated while the Set had drifted away from it (a hand-edit, or
  a future Quartz upstream reshuffle none of `_patch_explorer_with_anchor`'s
  three regex strategies produce cleanly), and the checks would report
  success while `update_quartz_layout`'s own fallback silently inserts a
  brand-new, disconnected `omit` Set elsewhere in the file on its next write
  — hidden pages would go unrecognized by the filter and publish, with every
  guard reporting green. Not reachable through any normal flow today (nothing
  in this codebase currently produces that detached shape), but it is exactly
  the failure class this whole fix exists to close, so it was tightened
  rather than left as a latent gap.

  **What changed:** `scripts/build_site.py` gains `_ANCHOR_STRUCTURE_RE` /
  `_anchor_is_structurally_wired()` — the marker's own line must be
  immediately followed (next line, leading whitespace only) by
  `const omit = new Set`, not merely present anywhere in the file.
  `ensure_quartz_layout_anchor` now calls that instead of a bare
  `"CQ4T-OMIT-ANCHOR" in txt`, on both the missing-marker path and the
  repaired-output verification. `verify.sh` §4b's grep was rewritten to
  `grep -Pzoq '//[ \t]*CQ4T-OMIT-ANCHOR:[^\n]*\n[ \t]*const[ \t]+omit[ \t]*=[ \t]*new[ \t]+Set'`
  — deliberately mirroring the Python pattern character-for-character (a
  first draft used a looser bash pattern with `\s` and no `//` prefix
  requirement; a second adversarial review caught that the two guards'
  claimed equivalence was false and it was tightened to match exactly, since
  `verify.sh` is the only guard on the Docker/mac-Linux path and
  `build_site.py`'s check is the only one on Windows-native — they must agree
  or the two platforms disagree about what "wired" means). Verified against
  literal `good.ts`/`bad-detached.ts`/`missing.ts` fixtures with both `python3`
  and GNU `grep -P` directly (not through Docker — unavailable on this
  machine); confirmed the three writer shapes (`_patch_explorer_with_anchor`'s
  three strategies, `EXPLORER_BLOCK`, and `update_quartz_layout`'s own
  rewrite) all still pass the tightened check, so a normal build → next
  build/preview cycle does not regress.

  **What the mac still owes:** run `verify.sh` for real (it needs Docker,
  unreachable here) to confirm §4b's tightened check still passes against an
  actual freshly-built image, and that the `grep -Pzoq` syntax behaves
  identically on macOS's grep as it did against GNU grep 3.0 here — worth
  double-checking, since `-z`/`-P` support and behaviour has differed across
  grep implementations historically (macOS ships BSD grep by default unless
  Homebrew's `ggrep`/GNU grep is on PATH; `verify.sh` already assumes
  something docker-adjacent, confirm which grep binary the check actually
  runs — it runs INSIDE the container via `docker run`, so it is the image's
  own grep, likely fine, but worth confirming rather than assuming). No
  `contracts/` or `GUI-IMPROVEMENTS.md` entry — this is an internal
  correctness hardening of toolchain logic, not a teacher-visible behaviour
  change (the original 2026-08-17 fix did not add either either, for the same
  reason). Two low-priority items noted in the new code comment rather than
  fixed, since neither is exercised by any writer in this codebase today: a
  type-annotation form (`const omit: Set<string> = new Set(...)`) and a
  blank line between the anchor and the `const` would both wrongly fail this
  check if they ever appeared by hand-edit — cheap to loosen for later if
  that ever becomes real.

- **For awareness only — no mac action required.** TODO.md item: *"Assistant
  replies 'deployed' before the deploy finishes (Windows)."* Windows'
  `MainWindow.DeployForAsync` used to resolve the instant the click was
  dispatched to the UI thread, not when the deploy actually finished, so the
  in-app assistant said "is deployed. Students can reach it now." after
  every `deploy_section` call regardless of outcome. Fixed by having
  `SectionDetailView.Deploy_Click`'s body (now `DeployAsync()`, an
  `async Task<string?>`) RETURN the true outcome sentence on every exit path
  — success/partial/all-failed via the existing
  `MultiDestinationDeployRunner.Result(...)`, `AssistWording.DeployDidNotFinish`
  on every early return and the catch block — threaded back through
  `MainWindow.DeployForAsync` → `AssistWindow.StartDeployInAppAsync` →
  `AssistAgent.RunTool`. Full write-up: `GUI-IMPROVEMENTS.md` row 383.

  The mac's `deployAndWait()` already awaits the real result and words it
  correctly — this only brought Windows to parity, so there is nothing to
  port. Two things worth a mac session's attention, not required, not
  blocking anything: (1) whether an equivalent "second deploy request
  arrives while one is already running" path exists in
  `SectionDetailView.swift`, and if so whether it shares mutable state across
  the two in-flight calls the way the first (rejected) fix here did before an
  adversarial review caught it — see the "rejected" note in
  `GUI-IMPROVEMENTS.md` row 383 for the exact shape of that bug, since it is
  a general trap (a single-slot completion field shared across concurrent
  callers) worth checking for rather than re-discovering; (2) the Windows
  scenario test fixture (`AssistScenarioTests.cs`) never wired
  `StartDeployInAppAsync` at all before this — worth checking whether the
  mac's own scenario tests exercise the equivalent async production seam or
  only a sync stand-in.

- ⚠️ **NEEDS A MAC BUILD/TEST/REGEN — authored on Windows, unverified there.**
  TODO.md item 1: *"A preview's progress bar sits at 100% saying 'Opening the
  preview…' for the entire build."* `scripts/build_site.py` prints the final
  preview milestone's marker ("🚀 Launching Quartz preview on…") *before* it
  runs `npx quartz build --serve`, and `ScriptRunner.advanceMilestones`/
  `AdvanceMilestones` jumps to the highest milestone whose marker has appeared
  anywhere in output, so that one early line completes every remaining
  milestone at once — the bar reads 100% for the whole real build, and
  "Building your site…"/"Preparing components…" never display.

  **Fix**: `TaskMilestones.preview`'s last entry now matches `"Done
  processing"` instead of `"Launching Quartz preview"` — the literal text
  `patches/build.ts:99` prints (`console.log(chalk.green(\`Done processing
  ${n} files in ...\`))`), which fires only once `emitContent()` has actually
  returned inside `buildQuartz()`, i.e. after the fresh site is truly on disk.
  Quartz's own "Started a Quartz server listening…" line was ruled out —
  `WINDOWS-HANDOFF.md`'s "Quartz serves the OLD site before it builds the new
  one" section already documents that IT ALSO prints before the build
  (`server.listen(); console.log(listening); await build()`), so it has the
  identical defect.

  **Verified against a real transcript, 2026-08-23** (`preview.ps1 --build-only
  EXC2O 1`, native Windows toolchain, no container): the raw output shows
  `Quartz v4.5.0` then `Done processing 199 files in 6s`, in that order — the
  marker is unique (grepped across `scripts/`, `patches/`, and a baked
  container copy — one hit), it's the file Docker actually copies in
  (`Dockerfile:41` → `patches/build.ts`), and chalk wraps the whole literal in
  ANSI, not interleaved inside it, so color is not a matching risk.

  **A related, out-of-scope defect, found but NOT fixed here, worth knowing
  before anyone "improves" this further**: the "Building your site…" milestone
  (marker `"Quartz v4"`) has the same shape — Quartz prints that banner
  (`cli/handlers.js`, `chalk.bgGreen.black(' Quartz v${version} ')`) at the
  very top of its build handler, before any real work, not when the build
  finishes. It doesn't produce the reported symptom here (it's mid-list, not
  the last milestone, so the bar just advances a step early rather than
  sticking at 100%) — after this fix, once "Quartz v4" prints the bar jumps
  straight to 7/8 with the label already reading "Opening the preview…" for
  the whole real build (an imprecise label, not a stuck-at-100%-forever bug).
  Left alone deliberately, scoped out by an adversarial review before this
  landed — a genuine fix would need a real "content actually processed"
  signal for that step too, and isn't a one-line marker swap.

  **What's changed, and what still needs mac attention:**
  - `windows-app/Plantoir.Core/Scripting/TaskMilestones.cs` — done, built,
    `dotnet test Plantoir.Tests/Plantoir.Tests.csproj` 664/664 green.
  - `mac-app/QuartzTeachers/Scripting/TaskMilestones.swift` — same one-line
    marker edit made, **but this Windows session has no Xcode and could not
    build or run it.** Please `xcodegen generate` + build + run
    `QuartzTeachersTests` before trusting it.
  - `mac-app/Tests/QuartzTeachersTests/TaskMilestoneTests.swift` —
    `testPreviewProgressAdvancesThroughItsMilestones` updated to assert the
    new intermediate state (7/8 after `"Quartz v4.5.0\n"`, label still
    "Opening the preview…") and only reaching 8/8 after a `"Done processing
    199 files in 6s\n"` line — **also unverified on a mac.**
  - `contracts/app-rules.json` → `markerOrigins.origins` — added `"Done
    processing": "elsewhere"` (authored/preserved key, safe to hand-edit).
  - **`contracts/app-rules.json` → `milestones.preview` was deliberately LEFT
    UNCHANGED.** `contracts/README.md` names `milestones` explicitly as a
    generated readout of `TaskMilestones`, regenerated only by `Plantoir
    --write-contracts` on a mac, and says in so many words not to hand-edit
    it. No Windows test currently reads `milestones` back out of the JSON, so
    leaving it stale doesn't fail `dotnet test` — but it IS stale until a mac
    session runs `Plantoir --write-contracts contracts` (after building the
    Swift change above) to regenerate it for real.
  - **`mac-app/Tests/QuartzTeachersUITests/MarketingScreenshotTests.swift`
    `test4Progress`** photographs the CURRENT broken behaviour on purpose (its
    own comment explains why: "the only state a capture can dependably
    reach"). Once this fix is built and verified on a mac, that shot should
    change (the bar will genuinely be mid-progress, not parked at 100%) and
    this test's comment/expectations will need revisiting — not done here,
    since it needs a real mac screenshot to know what the new dependable state
    looks like.
  - `GUI-IMPROVEMENTS.md` — not yet given a row; add one once the mac side is
    verified, since a teacher-visible change isn't confirmed shipped until
    both platforms show it.

  Branch: `issue/preview-progress-bar-marker` off `dev`, pushed. An
  adversarial subagent reviewed the plan before any file was touched — it
  caught the `milestones`-hand-edit mistake above before it happened and
  flagged the "Quartz v4" sibling defect; see this entry for both.

- ✅ DONE (mac, 2026-08-20). **The assistant warm-up race: it EXISTS here,
  it is measurable, and it cannot produce the Windows symptom.** Answering
  GUI-IMPROVEMENTS row 293's two questions with the real app rather than
  from the code, as that row asked.

  **Q1: does the mac's first turn await its warm-up? No — same as Windows
  before their fix.** `AssistSession.startEngine()` sets `readiness = .ready`
  and only THEN `await warmUp(…)`, and `canSend` asks nothing but
  `readiness == .ready`. The trail shows it plainly: `the assistant was ready
  after 0.5s`, with the ~3,400-token priming request still to run.

  **Measured, small assistant, M-series, 48 GB — the same question twice:**
  - typed after the warm-up had finished: **1.7 s**
  - sent the instant the field enabled, racing it: **3.1 s**

  So the race is real and costs about **1.4 s** on the first question, which
  is the priming request's tail on the server's single slot
  (`--parallel 1`). The question was answered correctly both times; nothing
  was lost.

  **Q2: is a timeout distinguishable from window-close cancellation? Yes —
  the mac has no way to confuse them, because it never classifies errors at
  all.** `AssistAgent.think()`'s catch has one branch: every error becomes a
  visible `.problem` bubble AND an `assistantCouldNotAnswer` trail line.
  There is no "this was a close, say nothing" path for a timeout to fall
  into. Proven by killing `llama-server` mid-session: the teacher saw
  `⚠ Could not connect to the server.` in the conversation and the trail
  recorded `the local AI assistant could not answer — Could not connect to
  the server.`

  **Three independent reasons the Windows chain cannot complete here**, which
  is why this is not a mac bug wearing a Windows coat:
  1. The request timeout is **180 s** (`AssistModelClient.reply`), not a few
     seconds — a warm-up of 2 s (small) or ~12 s (large) cannot exhaust it.
  2. The catch cannot swallow a timeout as a close, per Q2.
  3. **The engine's output goes to `FileHandle.nullDevice`**
     (`AssistServerHost`), so the unread-pipe wedge Windows had to fix by
     draining pipes cannot occur — nothing is ever buffered.

  **What was NOT fixed, and why.** Making the first turn await the warm-up is
  a real improvement worth about 1.4 s, and it is an OPTIMISATION here rather
  than a fix: the teacher-visible defect Windows repaired (silence) does not
  exist on this side. Doing it inside a release qualification would have made
  the mac's v1.1.0 a behaviour change and pushed the cut to 1.1.1 for a
  second and a half. Decided with Russell on 2026-08-20; it belongs in the
  next version with a test that pins "cannot send until the warm-up has
  returned".

  **✅ Landed later the same day** — GUI-IMPROVEMENTS row 298, branch
  `issue/assist-warm-up-gate`. `canSend` now requires `hasFinishedWarmUp`,
  and `AssistWarmUpTests` pins it against a stub engine that holds its
  answer. One correction to send back the other way, because it changes what
  the fix should be claimed to do: **3.1 ≈ 1.4 + 1.7 is the signature of two
  requests strictly serialised on one slot**, so the 1.4 s is moved out of
  the answer and into the wait rather than saved — measured from the window
  opening, the total is unchanged. What it buys is that nothing depends on
  the engine's behaviour with two requests in flight, and that the trail's
  first `assistant chose a tool` timing is no longer polluted by leftover
  warm-up.

  **One diagnostics gap this turned up, for the next session rather than
  this one.** Reason 3 is also a cost: with the engine's output going to
  `/dev/null`, nothing llama-server says can ever reach a problem report —
  no load errors, no slot warnings, no token counts. Windows added
  `NoteServerLine` for exactly this. The mac should sample those lines into
  the trail (a bounded tail, not the firehose) rather than keep discarding
  them; it is a report-quality change, not a hang risk, which is why it is
  not in 1.1.0.

  **✅ Landed later the same day** — GUI-IMPROVEMENTS row 299, branch
  `issue/assist-engine-log`, with a full section in `WINDOWS-HANDOFF.md`.
  Both streams go to a FILE rather than a pipe, so the no-blocking-read
  property that made `nullDevice` safe is kept structurally rather than
  promised; a bounded tail is sampled when the engine fails to start, every
  fifteen seconds while the window is open, and at teardown. Capped at
  twelve lines a conversation.

  **This is a request back to Windows, and it will turn your suite red.**
  `contracts/shared-rules.json` → `activityTrail.mustRecord` gained
  **`assistant engine said`**, so the list pin fails until `Plantoir.Core`'s
  `ActivityTrail.Event` gains the same entry. Nothing is broken; the case is
  waiting for you. The hard half is already there —
  `LocalModel.NoteServerLine` and `RecentServerLog` keep a 60-line ring
  buffer of exactly this output, and nothing yet puts any of it on the trail.
  **Re-measure the healthy-start noise on your own engine build before
  copying the filter**: warnings are excluded here because the Metal build
  prints six benign ones at every start (five a CORS block, one a token-type
  quirk), and a Vulkan or CPU build may not print the same six.

- ✅ DONE (mac, 2026-08-20). **`./verify.sh` passes against the changed
  shared scripts — all nine checks, and the npx question is settled.** Run
  from a clean clone of `dev` with the v1.1.0 tree: image built from the
  working recipe with BuildKit, baked scripts/patches/support files verified
  identical to the tree, the Explorer hide filter present in both Quartz
  copies, then a real `preview.sh EXC2O 1 --full-rebuild --build-only`
  through the launcher — 260 Markdown files parsed in 966 ms, 304 files
  emitted, "Done processing 260 files in 1s". No behaviour on this side
  needed changing, which is what let the mac ship 1.1.0 rather than 1.1.1.

  **The npx question is answered: there is nothing left to check.** The
  entry asked whether the container had quietly been resolving the Quartz
  CLI from the npm registry too. It cannot any more, on either platform,
  because the fix is in the SHARED script — `build_site.py` runs
  `node <abs>/quartz/bootstrap-cli.mjs` at both call sites (build and
  serve), and `deploy.py` mentions npx nowhere at all. The whole verify run
  contains not one npx line. So the question is now unanswerable rather
  than answered — the old behaviour is gone from the code that would have
  produced it — and it does not matter: the pin held either way, because
  Quartz's CLI runs the local patched `quartz/` source from CWD.

  **One nit, deliberately not fixed**: `toolchain_paths.py` still defines
  `NPX` and nothing uses it. Removing it would change the build context and
  therefore the image tag, which costs every teacher on both platforms a
  rebuild — for a dead constant. Fold it into the next change that touches
  that file for a real reason.

  **Two notes for whoever runs `verify.sh` next.** Its fixture,
  `courses/EXC2O`, is gitignored, so a fresh clone has none; the script's
  header says to install it with `./setup.sh`, but that is an interactive
  wizard and `cp -R support/example_course/EXC2O courses/EXC2O` produces the
  same fixture in a second. And the script deliberately LEAVES a container
  running from `quartz-teacher:dev-test`; `docker rm -f teaching-quartz-<hash>`
  puts the folder back on the normal image, which this session did.

  Everything below is the original request, kept for the reasoning.

  **Windows dropped the container entirely — shared scripts changed, run
  `./verify.sh` on the next sync** (Windows + shared, 2026-08-19, branch
  `windows-native-toolchain`). Windows now runs the whole toolchain
  natively: Node 20, Python 3.11, the patched Quartz scaffold and wrangler
  ship inside the app's own folder (built by
  `windows-app/Vendor/fetch-runtime.ps1`, pins mirroring the Dockerfile's),
  and the launchers run the shared Python directly when that runtime is
  present. WHY: WSL2 needs admin rights, Windows feature changes and a
  reboot — school-managed laptops refuse all three, and a teacher hit
  exactly that in front of an audience twice in one day. Rejected: porting
  the Python to C# (kills the shared-scripts contract and invites permanent
  drift); keeping a WSL2 fallback (Russell chose deletion once verified —
  two paths means two test surfaces forever).

  **What the mac must know about the shared files:**
  - `scripts/toolchain_paths.py` is new: every fixed path (`/opt/*`,
    `/teaching/courses`) now routes through it. Container defaults are
    byte-identical to before; the native path overrides via `PLANTOIR_*`
    env vars the mac never sets. The Dockerfile COPYies it — image hash
    changes, so the first mac preview after sync does a one-time rebuild.
  - The 26 `tee` subprocess writes are plain writes now (`write_file`),
    the Media/node_modules/.netlify links go through `link_directory`
    (symlink first — the mac's behaviour is unchanged), and
    `_sync_public_to_host` falls back to an incremental pure-Python mirror
    only when rsync is absent (it never is, in the container).
  - **The Quartz CLI is invoked as `node <abs>/quartz/bootstrap-cli.mjs`
    instead of `npx quartz`** — measured on Windows, `npx` resolved the CLI
    from the npm REGISTRY into its cache (a project's own bin never lands
    in its node_modules/.bin), which needed network and floated off the
    v4.5.0 pin. The container was almost certainly doing the same thing
    quietly; check a container build log for an `npx` cache line if you
    want the confirmation. Correctness held only because Quartz's CLI runs
    the local patched `quartz/` source from CWD.
  - `setup_course.py`'s keyboard reader imports termios where it exists,
    msvcrt where it does not; POSIX behaviour identical.

  Numbers (this machine, Ryzen-class x64, NVMe): first native build of the
  199-page example course **57 s cold** including scaffold staging; Quartz
  parse+emit 5 s; delta deploy to Netlify 117 files, ~40 s. The container
  path's equivalent on this same machine paid a one-time ~8 min image
  build plus WSL2 provisioning before the first build could start.
  Reference: `Enter-NativeRuntime` in the three `.ps1` launchers,
  `scripts/toolchain_paths.py`, `windows-app/Vendor/fetch-runtime.ps1`.

- ✅ DONE (mac, 2026-08-20). **Verified against the real app: the mac writes
  a record for every task, and the one gap in the code is unreachable here.**

  **What was driven.** A scratch working folder, the Example Course in it, a
  real preview that served the site, then `course_config.json` deliberately
  corrupted and Preview pressed again: `preview.sh — failed (exit 1) after
  1.0s`. `~/Library/Logs/Plantoir/runs/2026-08-20-184555-preview.txt` appeared
  with the task, the arguments, the outcome, the whole transcript ending in
  the JSONDecodeError, paths redacted to `/Users/person/…`, and the line
  `Explained nothing recognised — worth a look` — the honest fallback the
  contract's note asks for, doing its job on an unrecognised traceback.

  **It is the same folder the report reads**, checked rather than assumed:
  `ScriptRunner.writeRecordOfRun` → `ProblemReportStore.write` →
  `runsFolderURL`, and `ProblemReportBuilder.assembleFolder` reads
  `store.runFileURLs()` from that same store — the count is what fills in
  "the last N tasks Plantoir ran for you". Windows's failure was these two
  being different folders; here they are one property on one type.

  **A record also exists from the FIRST moment**, which is more than was
  asked for: the still-running preview had a 14 KB record while it was
  serving, outcome "Still running after …". That matters for the commonest
  report of all — "the preview is stuck" — which by definition never reaches
  a finish path.

  **The one gap, and why it is NOT worth fixing.** `ScriptRunner` assigns
  `runScriptName` AFTER `try newProcess.run()`, so a task that failed at
  LAUNCH would write no record and no `taskStarted` line — exactly the
  Windows shape, and exactly what the request asked about. It cannot happen
  here: `executableURL` is always `/bin/bash` and the script is an argument,
  so `run()` can only throw if `/bin/bash` is missing, at which point the
  Mac has bigger problems. Confirmed by experiment — `chmod -x preview.sh`
  and pressing Preview still produced `started preview.sh EXC2O 1 --port
  8081` on the trail and a record, because the executable bit of the script
  is not consulted. **Windows is exposed where the mac is not** because it
  launches the `.ps1` through its own host rather than through a shell that
  always exists. Left as it is deliberately: reordering two lines to guard
  against an unreachable case would be an untested behaviour change in a
  release-qualification pass. Written down so nobody "fixes" the ordering
  believing it is live, and so the asymmetry with Windows is on the record.

  Everything below is the original request, kept for the reasoning.

  **Check that every finished mac task really writes a run transcript**
  (Windows, 2026-08-19, branch `windows-wsl2-auto-install`). A real teacher's
  problem report arrived saying "the last 0 tasks Plantoir ran for you" after
  three failed setups: the Windows report reads `Logs\runs\*.txt`, and
  nothing ever wrote that folder — the reading side was tested against
  hand-made files, so the gap passed every test. Windows now saves every
  finished task's transcript from `ScriptRunner`'s finish path (redacted on
  the way in, pruned to the newest 20, header matching the trail's
  "finished … — outcome" sentence). The ask here is a VERIFICATION, not a
  port: drive one real failing task on the mac and confirm a file appears in
  the folder its report actually reads — the failure mode is precisely that
  the tests cannot see this. Reference:
  `ProblemReportStore.SaveRunTranscript`, `ScriptRunner.NoteTaskFinished`,
  `ProblemReportTests.Store_SavesRunTranscripts_RedactedAndPruned`.

- ✅ DONE (mac, 2026-08-20) — **RETIRED rather than implemented.** The three
  explainer sentences were never added here, and must not be: the same
  session that proposed them deleted the Windows container path, so no
  shipping launcher can print the lines they match. The three cases are gone
  from `contracts/app-rules.json` → `failureExplanations.cases`; Windows's
  own `SetupExplanation` is now unpinned by the contract and should be
  deleted along with the launcher code it reads, not kept as the only
  implementation of a rule nothing tests. See the ledger entry "The
  teacher-made-link case is implemented, and the three setup cases are
  retired". Everything below is the original request, kept for the reasoning.

  **The Windows launchers now install WSL2 themselves — the mac owes only
  the three explainer sentences** (Windows, 2026-08-19, branch
  `windows-wsl2-auto-install`). What it fixed: a teacher on a PC with no
  WSL2 hit "ERROR: WSL is present but no Linux distribution is installed"
  plus an instruction to open an Administrator PowerShell — it failed live
  in front of an audience on 2026-08-19. This was the Windows analogue of
  the mac's zero-prerequisite Colima bootstrap, called for by
  `WINDOWS-HANDOFF.md`'s "Container engine" note (entry 72), and it now
  exists: each `.ps1` launcher's `Install-WindowsSubsystem` runs one
  elevated `wsl --install -d Ubuntu --no-launch` (retrying with
  `--web-download` for Store-blocked school machines), detects
  restart-pending by USABILITY rather than exit code (the exit code is 0 on
  that path), and reports the three non-fault stops in plain words. WHY the
  choices: `--no-launch` because Ubuntu's first-run username wizard would
  otherwise block a non-interactive run forever — the distro runs as root,
  fine for an appliance no teacher opens; UAC is announced first ("Watch
  for a Windows permission prompt") because it is the one step that cannot
  be silent; a distro installed BY the run is provisioned without the
  Docker-engine question (the mac never asks either), while a pre-existing
  distro keeps the question because it belongs to whoever set it up.
  Rejected: DISM feature-enable plus manual distro import (re-implements
  what `wsl --install` already does, and needs the same elevation);
  prompting before the install (the handoff asks for silent, and UAC is
  already the consent); auto-restarting the PC (never — the teacher may
  have unsaved work everywhere). Untested on a truly fresh machine — this
  dev box has WSL — so the restart path is asserted from the launcher's
  printed lines, which is what the contract cases pin. What the mac does:
  the three contract cases above, nothing else — the `.sh` launchers are
  untouched. Reference: `Install-WindowsSubsystem` in `setup.ps1`,
  `preview.ps1` (where stop mode exits before it can ever run), and
  `deploy.ps1`.

- **Build the 1.0.0 DMG only from a tree containing the deploy-flush fix in
  `scripts/build_site.py`** (Windows + shared, 2026-08-19). A Windows release
  smoke hung FOREVER after "Done processing 272 files" with no error: the
  script's post-copy `os.sync()` is a GLOBAL flush that waits on every
  superblock in the kernel, and under WSL2 all distros share one kernel — a
  leaked FUSE superblock (orphaned by WSLg, no live process holding it, so
  nothing could ever answer) blocked it indefinitely. Diagnosed from the
  kernel stack: `ksys_sync → fuse_sync_fs → request_wait_answer`, python
  sleeping at zero CPU. The fix replaces `os.sync()` with `syncfs()` on the
  host output directory's fd — flushing only the filesystem the site was just
  copied to, which is the only one that step has any business waiting on.

  **The mac is exposed to the same class of failure, not just in principle**:
  Colima mounts `$HOME` into its VM via Lima's FUSE-based sshfs, so a global
  sync inside that VM waits on the host mount daemon every time. Deploys
  succeed today because the daemon answers, not by construction. Nothing to
  implement — the script is shared — but the DMG must be built AFTER pulling
  this commit or the two platforms ship different toolchains for 1.0.0. The
  changed script also changes the image hash, so the first preview/deploy
  after the mac app rebuild does a one-time image rebuild (a few minutes of
  "Building your website builder…") — expected, not a fault.

  Rejected: keeping `os.sync()` (it waits on superblocks wholly unrelated to
  Plantoir); fsync-per-file (hundreds of files over a slow VM mount, and the
  copy is rsync's work anyway); dropping the flush entirely (it exists so the
  host-side deploy step never reads a half-written `public/`). Reference:
  `scripts/build_site.py` → `_sync_public_to_host`.

- ✅ DONE (mac, 2026-08-19, commit "Pin the trail as wired, not merely
  declared"). All three events fire on the mac — verified against the REAL
  trail from the 1.0.0 DMG smoke, not just the code: `opened the working
  folder …`, `started setup.sh` → `finished after 15.2s`, preview
  start/stopped-on-purpose, deploy start/finish with duration all appeared.
  The stronger pin now exists:
  `mac-app/Tests/QuartzTeachersTests/ActivityTrailWiringTests.swift` scans
  the product source and fails if any `ActivityTrail.Event` case is
  referenced nowhere outside its declaration — which turns
  declared-but-never-called from a months-later discovery into a red test.
  (It cannot prove a call site is *reached*; `noteLaunch`'s three events are
  additionally verified as firing by running it against a scratch store.)
  Windows should mirror the scan — see `WINDOWS-HANDOFF.md` → "Pinning the
  trail as wired".
  On pollution: the mac suite does NOT write the real trail, and never did —
  `ProblemReportStore.standard` detects XCTest hosting
  (`XCTestConfigurationFilePath`) and returns a throwaway folder, which also
  covers the HOST APP's launch lines written before any test-bundle code
  loads (the case a Windows-style module initializer runs too late for,
  because the mac test target is app-hosted). Verified empirically: the real
  `activity.txt` was byte-identical (same SHA-1) before and after a full
  suite run. That redirect is now pinned by
  `testTheSuiteWritesToAThrowawayTrail` so a refactor of `standard` cannot
  silently lose it.

  Original request follows, kept for the reasoning:
  **Verify the mac actually EMITS the three trail events the contract pins —
  Windows declared them and never called them** (Windows, 2026-08-19). The
  same release smoke left ZERO lines on the Windows activity trail for a
  course creation, a preview and a deploy: `TaskStarted`, `TaskFinished` and
  `WorkingFolderOpened` existed in `ActivityTrail.Event`, so the contract
  test — which compares the ENUM list against `shared-rules.json` →
  `activityTrail.mustRecord` — passed while nothing ever fired. The list pin
  cannot catch a declared-but-never-called event, on either platform. Please
  check the mac's call sites fire for real (drive one preview, read the
  trail), and consider whether a stronger pin is possible. Windows wiring now
  lives in `windows-app/Plantoir.Core/Scripting/ScriptRunner.cs` (start:
  launcher + redacted arguments; finish: outcome distinguishing success /
  failure / stopped-by-teacher / backed-out-at-a-question, plus duration) and
  `WorkspaceViewModel.ChooseWorkspace` / `AdoptRestoredPath`.

  Related, same session: the Windows test suite was writing fixture courses
  (VVH2O) into the REAL trail — phantom lines a genuine problem report would
  gather. Fixed with a module initializer redirecting the trail before any
  test runs (`windows-app/Plantoir.Tests/TestTrailRedirect.cs`). Worth
  checking whether the mac suite pollutes its real
  `~/Library/Logs/Plantoir/activity.txt` the same way.

- ✅ DONE — SUPERSEDED, nothing owed. **Mirror the stop-sweep guard: await
  in-flight `--stop` sweeps before starting any build** (Windows,
  2026-08-19, GUI-IMPROVEMENTS row 282). An adversarial review the same
  night showed the mac needs none of this: its `PreviewStopper` already
  registers each sweep synchronously at the click and `waitForStopsToFinish`
  re-polls a live list — the two properties whose absence made the Windows
  copy racy. The Windows field failure this entry was written to explain
  turned out to be Windows-local anyway: `ScriptRunner.WaitUntilFinished`
  had been given a DEFAULT 5-second timeout that force-killed every deploy's
  build (row 283) — the sweep was never the killer. Windows has since
  adopted the mac's deploy-during-preview flow outright (row 283). Kept for
  the diagnostic reasoning; act on nothing here.
  Stopping a preview runs the launcher's `--stop` mode fire-and-forget, and
  that sweep kills the section's container-side processes BY WORKING
  DIRECTORY — including `/tmp/quartz-builds/<COURSE>/section<N>` — several
  seconds after the click. A deploy started right after stopping (the only
  order the interface allows, since Deploy needs the preview stopped) puts
  the sweep on top of the deploy's own quiet build and kills it before its
  first output flushes. The teacher sees an instant failure whose transcript
  ends at "Starting container if needed …" — nothing to go on at all.

  Windows reproduced this live during presentation prep and fixed it by
  making `PreviewStopper` track every in-flight sweep (each capped at 15 s so
  a wedged stop child can never hold a deploy hostage) and exposing
  `WhenSweepsFinish()`; the deploy path and both preview-start paths await it
  before launching a build. Reference: `windows-app/Plantoir/Services/
  PreviewStopper.cs`, `windows-app/Plantoir/Views/SectionDetailView.xaml.cs`.

  **The mac has the same latent race**: its `PreviewStopper` is the design
  Windows copied (row 105), equally fire-and-forget, and its `--stop` kills
  by the same working directories. Deploys there succeed today by timing —
  Colima's socket answers faster than WSL2, so the sweep usually lands before
  the next build starts — not by construction. Please mirror the guard.

  Rejected on Windows: teaching the sweep to spare "young" processes (the
  sweep cannot tell a leftover preview build from a new deploy build — any
  age cut-off guesses); retrying the killed build once (hides the mechanism
  and doubles the slowest path); having deploy skip the quiet build when a
  sweep is near (the build is needed; the wait is the honest fix). This
  cannot be a contract case: it is process timing on one machine, exactly
  the platform mechanics the contract's coverage table excludes.

- **A contract case for the summary/detail split — the mac already passes it,
  so this is a pin, not a request** (Windows, 2026-08-18, `windows-sync`).
  Windows has just ported `AssistToolOutcome`'s two-audience split, having
  shipped for weeks without it (see the awareness entry below for what that
  looked like). The behaviour is now pinned on this side by
  `windows-app/Plantoir.Tests/ToolAnswerTests.cs`, and it is NOT pinned by
  anything shared — which is how the two apps came to differ on it in the
  first place.

  What is wanted is a case list both suites run: for each of the thirteen
  tools the local model is shown, the sentence a TEACHER reads, against the
  longer answer the model gets. It could not be proposed from here with any
  confidence, and the reason is worth recording rather than re-deriving:
  `scenarios` and `nearMisses` are the authored halves of
  `assist-cases.json`, and both are shaped around the agent LOOP —
  `given` / `when` / `expectReply: "wording.X"` — where this is about what
  ONE tool returns, keyed to a course fixture the two suites do not share. A
  new top-level key would be the honest shape, and whether the generator
  preserves one is knowable only on the mac, where `--write-contracts` runs.
  **Please decide the shape and add it**; the Windows tests will be rewritten
  against whatever lands. The wordings to pin are in the awareness entry
  below.

  Rejected here: proposing it under `scenarios` anyway. A case the generator
  might silently eat is worse than no case, because the next person reads a
  green suite as proof.

## For awareness — no mac code needed

- **Windows caught up to the mac's three deploy-after-preview console-race
  fixes** (Windows, 2026-08-23, `GUI-IMPROVEMENTS.md` row 381, closing
  `WINDOWS-HANDOFF.md` item 8; mac originals rows 317–318, 2026-08-22). No mac
  change — this is Windows implementing races the mac already fixed — but the
  investigation confirmed all three were genuinely present, one had a wider
  exposure window on Windows than on the mac, and the adversarial review that
  checked the fix found a trap worth watching for on this side too. **Race 317
  (stale-timestamp panel flash):** `SectionDetailView.RefreshChrome`'s
  `showDeploy` had the identical ordering bug `showsDeployProgress` did —
  fixed with `MultiDestinationDeployRunner.ClaimConsole()`, a direct mirror of
  `deployRunner.startedAt = Date()` in `deployAndWait()`. **Race 318a (blank
  console + Deploy re-entrancy):** present with a LARGER window than mac's
  ~0.5s — Windows' preview-stop sweep can run to ~20s, and nothing disabled
  Deploy for that whole span. Fixed with a view-local `_isPreparingDeploy`
  field (mirroring mac's `@State`, not a runner property) and a dedicated
  `TaskProgressView.ShowPreparing(title)` placeholder, matching the mac's
  choice of a real placeholder view (`preparingToDeployPlaceholder`) over any
  runner-state workaround — that was the one part of the mac's shape worth
  porting exactly rather than reinventing. **Race 318b (false "Done" flash):**
  present — `MultiDestinationDeployRunner.RunAsync` reuses one `ScriptRunner`
  for build-then-deploy and polls for completion (100ms on Windows vs mac's
  300ms), so the same-shape gap existed at a smaller scale. Fixed with
  `ScriptRunner.IsBetweenPhases`, a direct mirror of `isBetweenPhases`.
  **Worth a glance on this side:** the adversarial review caught an explicit
  `RefreshChrome()` call that had been sitting between clearing
  `_isPreparingDeploy` and `await RunAsync(...)` — harmless today only because
  everything up to `RunAsync`'s own `Notify` runs synchronously before any
  frame paints, but it re-derived the exact stale-`Legs` race the whole fix
  exists to close, one future `await` inserted in that gap away from becoming
  real. Removed on Windows; a quick read of `deployAndWait()` around the
  `isPreparingDeploy = false` / `await deployRunner.run(...)` boundary
  (`SectionDetailView.swift:780-793`) found no exact equivalent there, but the
  general shape — a fix that only works because of synchronous-batching
  timing is fragile even when it currently renders correctly — is worth
  keeping in mind if that span is ever touched again. Reference:
  `Plantoir.Core/Scripting/ScriptRunner.cs` (`IsBetweenPhases`),
  `Plantoir.Core/Scripting/MultiDestinationDeployRunner.cs`
  (`ClaimConsole()`), `Plantoir/Views/TaskProgressView.xaml.cs`
  (`ShowPreparing`), `Plantoir/Views/SectionDetailView.xaml.cs`
  (`_isPreparingDeploy`, `Deploy_Click`).

- **Measured: Edge does not need the `127.0.0.1` rewrite for a preview URL**
  (Windows, 2026-08-23, closing `WINDOWS-HANDOFF.md` item 5's first half, the
  Edge `127.0.0.1` question). The rewrite itself (`OutputParsers.cs`,
  `SectionDetailView.xaml.cs`) was applied earlier on the mac's "browsers try
  IPv6 first" rationale, without a Windows-side test to back it. Tested by
  hand against a real running preview (port 8081, confirmed via `netstat`):
  loading `http://localhost:8081` directly in Edge was indistinguishable from
  loading `http://127.0.0.1:8081` — both rendered immediately, no perceptible
  delay, repeated more than once. No IPv6-first stall observed. Conclusion:
  the rewrite is a harmless no-op on Windows as currently shipped, not a fix
  for an observed Edge problem — kept in place rather than removed, since it
  costs nothing and matches the mac's own defensive posture, but it should no
  longer be treated as an open question. No mac change; nothing to port.

- **Windows caught up to the mac's working-folder path bar gestures**
  (Windows, 2026-08-23, `GUI-IMPROVEMENTS.md` row 328, closing
  `WINDOWS-HANDOFF.md` item 6). No mac change — the mac's own path bar is
  unaffected — but two things are worth knowing. **First, a WinUI trap that
  cost real time and is worth watching for anywhere else in `windows-app/`:**
  `MainWindow.xaml`'s `BreadcrumbBar.ItemTemplate` had, since the crumb
  feature first shipped (commit 4282b839), wrapped its content in a second
  `BreadcrumbBarItem` — invalid, since `BreadcrumbBar` already generates its
  own container per item, the same relationship `ListViewItem` has to
  `ListView`. This built cleanly and passed the full test suite every time
  (a `DataTemplate`'s structure isn't something a unit test reaches), and
  only failed at RUNTIME — by silently falling back to the bound object's
  `ToString()` rather than throwing, so every crumb displayed the literal
  text "Plantoir.Views.PathBarCrumb" instead of a folder name. It shipped
  invisibly for over a week because nobody had actually run the real app
  against this code path before. Fixed by having the template supply only
  the container's CONTENT (a `StackPanel`) and never another
  `BreadcrumbBarItem`; `PathBarCrumb` also gained a defensive
  `ToString() => DisplayName` override as a second line of defence, since
  the overflow dropdown and narrator can fall back to it independently of
  the item template — mirroring why `FolderCrumb` already had one. **Second,
  the folder icon per crumb** — mac renders the real Finder icon; Windows'
  new `Plantoir.Views.FolderIcons` uses `StorageFolder.GetThumbnailAsync`
  (cached by path, `null` on any failure so the crumb falls back to
  name-only) rather than P/Invoking `SHGetFileInfo`, avoiding manual HICON
  lifetime management for a decoration the contract already says is
  optional. Reference: `Plantoir/MainWindow.xaml` (`BreadcrumbBar.ItemTemplate`),
  `Plantoir/Views/PathBarCrumb.cs`, `Plantoir/Views/FolderIcons.cs`.

- **Windows caught up to the mac's "assistant engine said" trail event**
  (Windows, 2026-08-23, `GUI-IMPROVEMENTS.md` row 327, closing
  `WINDOWS-HANDOFF.md` item 2). No mac change — this is Windows implementing
  a feature the mac already had, so nothing to port back — but worth knowing
  the two platforms differ in HOW the engine's output is captured, in case a
  future engine integration on either side needs the same lesson. The mac
  writes `llama-server`'s stdout/stderr to a FILE and samples its tail,
  because an unread `Pipe` fills up and blocks the engine mid-request — the
  bug that originally wedged the Windows server. Windows' `LocalModel`
  already avoided that same wedge a different way, by draining via
  `Process.OutputDataReceived`/`ErrorDataReceived` EVENTS (always read,
  never blocking) into an in-memory 60-line ring buffer, so no file-backed
  log was needed to port this feature — `LocalModel.LinesSinceLastLook`
  reads the ring buffer instead of a file offset. The filter and cap
  (`Plantoir.Core.Assist.AssistEngineLog`) are checked in
  `AssistEngineLogTests.cs` against the identical real llama.cpp (b10435)
  fixture lines the mac's `AssistEngineLogTests.swift` uses, so a change to
  what counts as "trouble" can be cross-checked against the same evidence on
  both platforms. One Windows-specific bug an adversarial review caught and
  fixed, not present on mac: mac's `recordWhatTheEngineSaid` always runs on
  one actor, so its non-atomic Swift properties need no lock; Windows
  deliberately runs its periodic watch on a background thread while
  `Shutdown()`'s own last look runs on the UI thread without waiting for an
  in-flight background iteration, which could race on the shared mark/count
  state — fixed with a lock (`AssistWindow._engineLogGate`).

- **Windows' progress-bar markers had drifted out of sync with its own
  launchers for four days, and nothing caught it** (Windows, 2026-08-23,
  `GUI-IMPROVEMENTS.md` row 353, closing `WINDOWS-HANDOFF.md` item 5's
  second half). No mac change needed — `TaskMilestones.swift` was never
  wrong, since it was written against `setup.sh`/`preview.sh`/`deploy.sh`,
  which still print the lines it watches for. But the WAY this broke is
  worth knowing, because it's a shape of bug that can recur on either side.
  `TaskMilestones.cs` used four markers copied verbatim from the mac's
  `.sh` scripts (`Setting up this PC`, `Building your website builder`,
  `Ensuring container is running`, `Starting container if needed`).
  `setup.ps1` gained a "Native toolchain (no container)" rewrite — no
  WSL2, no Docker, no one-time machine setup, no container start at all —
  the very next day (`b356a1f`, 2026-08-19), which silently stopped
  printing all four. Nobody updated the C# markers, and nothing failed:
  the existing `TaskMilestoneTests` only checked label WORDING (ellipsis
  suffix, no "Docker"/"script" text) against hand-typed synthetic
  transcripts, never against real captured launcher output. The visible
  cost: the first two-to-three stages of most progress bars (course
  creation, example course, preview, deploy) could never be reached by
  marker match, so the bar sat at 0% until a later, still-real marker (e.g.
  "Quartz v4") jumped it forward several steps at once — no crash, reads
  as a slow build. Found by re-investigating `WINDOWS-HANDOFF.md` item 5,
  confirmed against two real captured transcripts (`preview.ps1
  --build-only`, `deploy.ps1 --to-folder`) run on this machine, and
  confirmed twice more by independent adversarial review before and after
  the fix (the second pass caught a genuine miss: `MarketingShotCapturer.cs`'s
  mock transcripts, whose own doc comments claim to be coupled to
  `TaskMilestones` — "change one there and this stops advancing" — still
  carried the four dead strings and needed the same fix). **The lesson
  worth carrying to the mac side, in case `.sh` output is ever
  restructured similarly:** a progress-marker list is a claim about what a
  SPECIFIC script prints RIGHT NOW, and it rots silently the moment that
  script changes underneath it unless something actually reads the
  script's own text. Windows' fix — `TaskMilestoneLauncherMarkerTests`
  (`ParsingTests.cs`), which greps the real `.ps1` files for every
  launcher-origin marker rather than trusting a synthetic transcript — is
  the general pattern; `TaskMilestoneTests.swift` has no equivalent check
  against `.sh` today. Reference:
  `windows-app/Plantoir.Core/Scripting/TaskMilestones.cs`,
  `windows-app/Plantoir.Tests/ParsingTests.cs`.

- **A general WinUI `x:Bind` trap, found in the sidebar's scheduled-deploy
  badge but worth watching for anywhere a row object is reconciled rather
  than recreated** (Windows, 2026-08-23, `GUI-IMPROVEMENTS.md` row 326).
  Reported directly, right after row 325 shipped: no clock badge appeared
  after scheduling a deploy in an already-open window, and the right-click
  menu never offered Cancel/Change either. Two compounding bugs, not one.
  (1) `ReconcileSections` only read the current schedule into
  `SidebarRow.ScheduledDeploy` when CREATING a row — an existing row (the
  normal case, since the window was already open) kept whatever was true
  the moment it was first shown, forever. (2) Even fixed, the UI would not
  have shown it: `x:Bind` — unlike classic `Binding` — defaults to
  `Mode=OneTime`, evaluating once at container creation and never again.
  `SidebarRow` had no change notification and none of the affected
  bindings specified `Mode=OneWay`, so `Visibility`/`ContextFlyout` were
  frozen at whatever was true when the row's TreeView container was first
  built. **No equivalent trap on the mac** — SwiftUI's `@Observable`
  re-renders any view that reads a changed property, full stop, so there
  is no "silently stale until the container happens to be recreated"
  failure mode to reproduce there. Worth knowing as a general lesson for
  ANY future WinUI work here: a reconciled (not recreated) row/item object
  needs BOTH `Mode=OneWay` in the XAML on every binding whose value can
  change post-creation AND `INotifyPropertyChanged` raised for that exact
  property name — including for any DERIVED property XAML binds to
  directly (here, `ScheduledDeploy` changing had to also raise
  `BadgeVisibility` and `BadgeTooltip`, since `x:Bind` subscribes to the
  literal property path named in the binding, not to whatever the bound
  property is computed from). Also added, same pass: `MainWindow`'s
  `Activated` handler now calls `Sidebar.Refresh()`, so a deploy scheduled
  through the assistant or from a different window is picked up the next
  time this window comes to the front — the same "refresh on activation"
  shape the " — Edited" marker already uses. Reference:
  `windows-app/Plantoir/Views/SidebarPane.xaml.cs` (`SidebarRow`,
  `ReconcileSections`), `windows-app/Plantoir/Views/SidebarPane.xaml`
  (the three `Mode=OneWay` bindings), `windows-app/Plantoir/MainWindow.xaml.cs`.

- **Scheduled deploys never actually fired on Windows, ever — a doubled
  backslash in a shell-quoted string** (Windows, 2026-08-23,
  `GUI-IMPROVEMENTS.md` row 325). Reported directly, after a real overnight
  scheduled deploy for ICD2O never went out. `TaskScheduling`'s stored `/TR`
  command built the PowerShell `-File` argument with `\\\"` in C#
  source — a literal backslash followed by a quote, TWO characters — where
  it needed a real embedded quote character (`\"` in C# source, which the
  compiler turns into one `"` character). `schtasks /Query ... /XML` showed
  the stored `<Arguments>` holding `\"C:\...\script.ps1\"` verbatim, both
  characters literal, so PowerShell's `-File` was handed a path it could
  never resolve. **This predates row 323's fingerprinting work entirely** —
  it would have broken every scheduled deploy on Windows since the feature
  first shipped, for any course, silently, because Task Scheduler still
  records a "Last Run Time" for a task that ran and immediately failed to
  parse its own argument, so nothing about SCHEDULING ever looked broken.
  Confirmed live: the real failing task's Last Result was `0xFFFD0000`.
  **Nothing for the mac to do or check** — `launchd`'s command is an
  ARGUMENTS ARRAY in a plist, never a shell command string assembled with
  manual quote-escaping, so this exact bug class (two escaping passes
  compounding instead of cancelling — `ProcessStartInfo.ArgumentList`
  already quotes a value containing spaces once, so hand-escaping quotes
  INSIDE that value doubles up) has no equivalent surface there. Worth
  knowing as a general lesson if the mac ever DOES build a shell command
  string by hand somewhere (rather than an arguments array): don't
  hand-escape a quote that a launching API is about to quote again on your
  behalf — verify by reading back what actually got stored/registered, the
  way `schtasks /Query ... /XML` made this one obvious in about thirty
  seconds once looked at directly, rather than trusting that a plausible-
  looking C# string literal did what it appeared to say. Also fixed on the
  same pass: right-click on a section with a deploy already scheduled now
  offers "Change Deploy Time…" alongside Cancel, reusing the existing
  schedule dialog pre-filled with the current time rather than requiring a
  cancel-then-reschedule round trip — no backend change needed, since
  `TaskScheduling.Schedule` already replaces by task name. Reference:
  `windows-app/Plantoir.Core/Assist/TaskScheduling.cs`
  (`TaskRunCommand`), `windows-app/Plantoir.Tests/TaskSchedulingTests.cs`
  (new), `windows-app/Plantoir/Views/SidebarPane.xaml.cs`
  (`AskWhenToDeploy`'s new `existing` parameter).

- **A shared `scripts/deploy.py` bug, found on Windows but fixed in the file
  the mac runs too** (Windows + shared, 2026-08-23, `GUI-IMPROVEMENTS.md`
  row 324). Reported directly, with a screenshot: a teacher deployed a
  section for the first time (Netlify, succeeded, live URL shown), then
  tried Schedule a deploy and was refused with "has never been deployed" —
  about a section that plainly just had been. `main()`'s `course_dir =
  section_dir.parent.parent`, used to read and write the Netlify/Cloudflare
  site marker (`.netlify_sites/`/`.cloudflare_sites/`), assumed the shape
  `.../<COURSE>/.merged_output/section#` — true on the mac and in the old
  container, but Windows' native `PLANTOIR_BUILD_ROOT` (row 290) makes
  `toolchain_paths.merged_output_root()` skip the `.merged_output` nesting
  entirely, so climbing two levels overshot onto the build root's own
  parent instead of the course. **This was not a cosmetic bug**: the marker
  was never found at READ time either, so every deploy — not just the
  first — silently created a brand-new Netlify site instead of reusing the
  one from last time, confirmed live on Russell's own machine (a real site
  marker sitting under `%LOCALAPPDATA%\Plantoir\builds\<id>\` instead of
  under `courses\ICD2O\`). **The mac itself was never affected** —
  `PLANTOIR_BUILD_ROOT` is a Windows-only environment variable, so
  `merged_output_root()` has always kept the `.merged_output` nesting there
  and `section_dir.parent.parent` has always landed correctly — but the fix
  (`course_dir = COURSES_ROOT / args.course`, unambiguous regardless of
  where the build output lives) is in the ONE shared `deploy.py` both
  platforms run, so **the mac's copy carries the identical change with
  nothing further to do.**

  **Addendum, 2026-09-05 — your fix is now load-bearing on the mac too, and
  this entry's "the mac itself was never affected" is true of the day it was
  written and no longer of today.** The mac has moved its build output out of
  the working folder as well (`GUI-IMPROVEMENTS.md` rows 402–406). It does it
  differently — `courses/<CODE>/.merged_output` is a SYMLINK, not an
  environment variable — but `deploy.py` calls `.resolve()` on the built
  section's path, so on the mac `section_dir.parent.parent` now climbs to the
  BUILDS folder's parent, exactly as it did on yours. Had `course_dir` still
  been derived from that ancestry, the mac would have started writing its
  Netlify and Cloudflare markers into Application Support and creating a
  brand-new site on every publish — your bug, on our machine, a fortnight
  later. It did not, because you had already fixed it and pinned it with
  `scripts/test_deploy_course_dir_resolution.py`, which is now doing the job
  on both platforms. **Nothing is owed here; this is the answer-back.** The
  one thing worth knowing is that the test's docstring, which says the two
  paths differ "under Windows' native PLANTOIR_BUILD_ROOT", is now true of the
  mac's symlink as well — it still passes and still guards the right thing. Two new pure-stdlib tests,
  `scripts/test_deploy_course_dir_resolution.py`, wired into `verify.sh` —
  worth running there once, since they exercise `merged_output_root()`
  directly and `verify.sh` is the gate that would have caught this had it
  existed sooner. Reference: `scripts/deploy.py` (`main()`'s `course_dir`
  line), `scripts/toolchain_paths.py` (`merged_output_root`).

- **Windows closed its own version of the launchd scheduled-deploy bug row
  314 already fixed on the mac** (Windows + shared, 2026-08-22,
  `GUI-IMPROVEMENTS.md` row 323). `WINDOWS-HANDOFF.md`'s "What is still
  genuinely outstanding" list had item 2's carve-out: a scheduled ("publish
  tomorrow's class overnight") deploy on Windows succeeded perfectly but
  left the title bar saying "— Edited" forever, because Task Scheduler runs
  `powershell.exe` directly — no app process is alive at the moment the
  deploy actually happens, so nothing could fingerprint the section or
  write `.publish_state`. **The mac needs to change nothing** — its own
  launchd agent launches the app binary, so it always could fingerprint
  in-process, and this row is purely Windows catching up to what row 314
  already described as the mac's fix for the identical bug. Recording here
  for two reasons worth knowing about:
  - **A third, Python copy of the fingerprint algorithm now exists**, in
    the SHARED `scripts/` folder: `scripts/section_fingerprint.py`. Nothing
    on the mac calls it — only Windows' scheduled-deploy wrapper script
    does, since it needs to fingerprint from inside a plain PowerShell
    process with no C# or Swift available. If the fingerprint algorithm's
    rules ever change on the mac (which files count, the symlink one-hop
    resolution, the sort order, the hash), **this Python file needs the
    identical edit or a Windows scheduled deploy will silently disagree
    with the mac about whether a section has unpublished edits.** Proven to
    currently match, byte for byte, by
    `windows-app/Plantoir.Tests/SectionFingerprintPythonParityTests.cs`,
    which runs both the C# and the Python implementations against the same
    temp course tree and asserts equal output — there is no equivalent
    check on the mac side, since the mac never runs this file.
  - **Rejected: fingerprinting at schedule time instead of run time** —
    would have been cheap (no Python needed, just C# at the moment the
    teacher clicks Schedule), but wrong in the direction that lies to the
    teacher: an edit made between scheduling and the overnight run still
    goes out correctly, but a schedule-time fingerprint would stamp the
    STALE pre-edit fingerprint, so the marker would say "— Edited" about
    content that had, in fact, just published. Fingerprinting at RUN time,
    right before the deploy — the wrapper script's own Python call, timed
    to match the mac's in-process fingerprint-before-running-the-script
    order — is the only version that is correct either way. Worth knowing
    if a similar "the app isn't alive at the moment this needs to happen"
    problem comes up on the mac side (a future launchd variant, say): the
    fix that is cheap and the fix that is correct were not the same fix
    here, and the difference only shows up in a case (edit-after-schedule)
    that is easy to not think to test.
  - Reference: `windows-app/Plantoir.Core/Assist/TaskScheduling.cs`
    (`WriteWrapperScript`), `windows-app/Plantoir.Core/Assist/ScheduledDeployCompletion.cs`
    (new), `scripts/section_fingerprint.py` (new),
    `windows-app/Plantoir.Tests/SectionFingerprintPythonParityTests.cs`
    (new), `windows-app/Plantoir.Tests/ScheduledDeployCompletionTests.cs`
    (new). Full write-up, including what the wrapper script's generated
    PowerShell actually looks like, in `WINDOWS-HANDOFF.md`, "A scheduled
    deploy needs its own path to the same record".

- **The Windows hero pair had three separate bugs, found by actually looking
  at it next to the mac's** (Windows, 2026-08-21, commit "Fix Windows hero
  image: stray border pixels, tiny windows, and an empty Obsidian sidebar").
  Russell asked directly: "compare the macOS hero image to the Windows hero
  image captures and you will see what I mean" — and looking, rather than
  reasoning about the code, is how all three were actually found and fixed.
  - **A hairline of the window's own border was baked into every card.**
    `DWMWA_EXTENDED_FRAME_BOUNDS` (used because `GetWindowRect` includes an
    invisible resize border — already known, see the entry below) excludes
    that invisible border but NOT the thin accent border Windows 11 draws
    directly on the window, so the raw grab kept 1 DIP of that border colour
    on all four edges. It reads as near-black (52-54, 52-54, 52-54) in BOTH
    appearances, since it is the system border colour, not the app's — so it
    shows as stray dark pixels once composited onto the page's own
    background, worst on the light cards. Measured identically on all three
    window kinds (Obsidian, Plantoir, Edge) in both themes: exactly 2 real
    pixels at this machine's 2x scale, i.e. 1 DIP. Fixed by cropping that
    border off before masking the corners, and shrinking the corner-radius
    mask to match (`BORDER_DIPS`, `photograph()` in `hero_windows.py`). If
    the mac's own captures ever show a comparable hairline, this is the shape
    of bug to look for — but `screencapture -l` returning a window with its
    corners already transparent (rule 1 in the marketing-screenshots skill)
    means the mac has never had a border baked into the bitmap to begin with.
  - **The card size was a REAL-PIXEL cap, so it didn't scale with the
    display.** `card_geometry()`'s 1680x960 cap was tuned on a
    1920x1080-at-150% machine, where it read as "almost the whole screen"
    (1120x672 DIPs out of a 1280x672 DIP work area). The same 1680x960 REAL
    pixels on a 200%-scaled screen is only 840x480 DIPs — a physically small
    window whose UI barely shows anything, which is exactly what "you can
    barely see anything in each window" was describing. Re-expressed the cap
    in DIPs (`CARD_WIDTH_DIP = 1120`, `CARD_HEIGHT_DIP = 640` — the size the
    old cap actually was, in points, on the machine it was tuned on) and
    multiplied by `scale_factor()` at capture time, so a card occupies the
    same fraction of the desktop on any display. Cards went from 1680x960 to
    2240x1280 real pixels on this (200%-scaled) machine; nothing changes on a
    100%-scaled one.
  - **Obsidian's sidebar was three collapsed folder names, because nothing
    ever told it to be anything else.** The mac's rich sidebar (several
    folders open, real class notes visible) turned out to depend on nothing
    reproducible — no fold state is stored anywhere in a vault's
    `.obsidian/` (checked `workspace.json` by hand; there is no
    `expandedFolders` key or equivalent), so it can only be Electron's own
    per-machine local storage remembering what Russell has manually browsed
    on that Mac over time. That is not something a fresh Windows vault has
    ever had a reason to accumulate, and setting the file-explorer leaf's
    `autoReveal: true` in `workspace.json` before launch was NOT sufficient
    on its own — it visibly expanded the active note's ancestors but settled
    mid-scroll, short of the note itself, and repeated waits up to 6s did not
    change where it stopped. What worked, tested with `autoReveal` explicitly
    OFF to confirm it does not depend on that setting at all: Obsidian's own
    **"Reveal current file in navigation" command**, fired through the
    command palette (`Ctrl+P`, type the name, Enter) once the window is
    placed at its final size. It deterministically expands every ancestor
    folder AND scrolls to the note, highlighted, regardless of any persisted
    per-vault state — which is also why it is the right fix rather than the
    `autoReveal` setting: it does not depend on Electron local storage that a
    fresh machine will never have. New helper `reveal_active_file()` in
    `hero_windows.py`, called from `capture_obsidian()`. **Worth knowing if
    the mac's demo vault is ever reprovisioned from scratch** (a new machine,
    or `~/Desktop/Teaching` deleted and rebuilt): the mac's own rich sidebar
    would come back collapsed too, for the identical reason, and the same
    command would be the fix there — nothing about it is Windows-specific,
    it just happened to be found here because Windows had no accumulated
    local-storage state to be masking the bug.
  - **A pre-existing risk, found while testing this and fixed alongside it**:
    `capture_edge()`'s `stop("msedge.exe")` (`taskkill /F /IM msedge.exe`)
    kills every Edge process on the machine, scratch profile or not. On a
    machine where Edge is also someone's real browser — which it was, on
    this one, mid-session — that silently closes whatever they had open.
    New `stop_matching(process_name, command_line_contains)` uses
    `Get-CimInstance Win32_Process` to filter by command line before
    killing, so only the process launched against our own
    `--user-data-dir=EDGE_PROFILE` is touched; verified live with a
    non-matching filter first (confirmed zero processes selected) before
    trusting it against the real one. **Not extended to `Obsidian.exe` or
    `Plantoir.exe`** in this pass — Plantoir is explicitly pre-authorised to
    be force-closed on Windows regardless (`CLAUDE.md`, "An agent working on
    Windows may close a running Plantoir without asking"), and no real
    Obsidian was running to be at risk here. If the mac's own Safari capture
    ever needs an equivalent, it already has one structurally: the `⎚`
    profile keeps scratch state separate from Russell's own Safari, so a
    `killall Safari` (if it has one) is not the same class of risk to begin
    with.
  - **Left unresolved, and NOT chased further**: the Plantoir card's native
    title bar came back light in a dark-appearance capture, 4 runs out of 4
    in this session, including with an extra 3s settle after `write_theme()`
    before launch (ruling out a simple registry-propagation race).
    `ShowHeroWindowAsync` (`MarketingShotCapturer.cs`) sets `RequestedTheme`
    on the content root and the progress view, which is why the MENU BAR and
    everything below it renders correctly dark — but nothing there touches
    the native caption's dark-mode attribute, which is presumably meant to
    follow the OS registry `write_theme()` already sets before launch. Why
    that isn't landing is unknown: possibly a genuine gap (no explicit
    `DwmSetWindowAttribute(..., DWMWA_USE_IMMERSIVE_DARK_MODE, ...)` call
    anywhere in this codepath), possibly specific to capturing over RDP,
    where this session ran. `site/img/hero-windows-dark.png` ships with this
    flaw rather than being blocked on it — the three bugs above are the ones
    Russell asked about and are confirmed fixed; the title bar is a smaller,
    separate defect for a future session to chase, on a physical console
    rather than RDP if possible, to rule that variable out first.
  - Reference: `website/shots/hero_windows.py` (`photograph`, `card_geometry`,
    `reveal_active_file`, `stop_matching`).

- **Windows marketing shots re-taken, a Windows hero pair added, and an
  already-known theming bug re-fixed the right way** (Windows, 2026-08-20).
  - **What changed**: Russell redeployed the demo sites and initially asked
    for ENG2D's screenshot source to move to `eng2d-s2-2026-gordon` — that
    turned out to be a mistake caught minutes later ("the eng2d website
    should be s1 like the other courses"), so `website/shots/capture_windows.py`'s
    `DEMO_COURSES` table stayed as it already was: `eng2d-s1-2026-gordon`,
    matching MCV4U and SCH3U on section 1, and matching the identical table
    in `capture.py`. The images were still re-shot (a fresh Netlify deploy
    can change page content even with the URL unchanged), so this is not a
    no-op even though the table's end value is the same as before. **No mac
    action needed** — nothing here changes what `capture.py`'s own table
    should point at.
  - **A dialog theming bug surfaced during the re-shoot, and turned out to
    already be found and fixed — on a branch that was never merged.**
    `NewCourseDialog`'s "New to this?" card (and the harness's own synthetic
    dialog card around it) read `Application.Current.Resources["key"]`
    directly in code, which resolves against the theme the app LAUNCHED in,
    not a window's local `RequestedTheme` override. `dev`'s capture harness
    runs both appearances from one launched-light process, so the Dark
    capture rendered a still-light card with barely-legible text. Confirmed
    capture-harness-only: nothing in the live app sets `RequestedTheme`
    anywhere, so a teacher never sees this. Two live fixes were tried here
    first and rejected — `Application.Current.RequestedTheme = theme` after
    launch throws `COMException 0x80131515` (WinUI does not support changing
    the app-wide theme at runtime), and indexing
    `Resources.ThemeDictionaries` (directly, then recursively through
    `MergedDictionaries`) resolves only whichever theme the app is ambiently
    in — then hardcoding approximate Fluent 2 literals as a third attempt,
    which worked but was never committed. **All three were abandoned** on
    finding `ac96888c` ("Photograph each appearance from its own process, so
    the dark shots are dark") on the unmerged `new-screenshots` branch (5
    commits, Russell, 2026-08-19, 48 behind `dev` at the time) — the actual
    fix, already reasoned through: launch `Plantoir.exe --capture-marketing-shots
    --theme <light|dark>` as a SEPARATE process per appearance, with Windows'
    own colour mode switched first (`capture_windows.py` now imports
    `read_theme`/`write_theme` from `hero_windows.py`, which already had
    them). Every themed resource then resolves the way a teacher's copy
    resolves it, because the situation genuinely is a teacher's copy in that
    appearance — no brush-by-brush chasing, and no approximation. **Ported
    forward instead of merging the branch**: the branch was 48 commits stale
    (predates the v1.1.0 release and the mac's own screenshot re-shoot), so
    its 26-image commit was left behind and only the code changes were
    carried over by hand.
  - **A second commit on that branch was also worth carrying forward**:
    `dd6f3fe9` fixed the SAME class of bug in `hero_windows.py` — the
    Obsidian card was hardcoded to `section2/.../Unit 4, Day 23`, which held
    only until the next redeploy moved the site to Day 22 and nothing
    noticed. `hero_windows.py` now has `most_recent_class()`, which reads the
    live site's front page at capture time and falls back to a named
    constant only if the site is unreachable. Also picked up: `SECTION = 1`
    (was hardcoded to section 2, while Plantoir and Edge were both showing
    section 1 — a second three-cards-disagree bug, independent of the class
    number one), and a fresh Edge scratch profile per launch (a reused
    profile let Edge restore the previous pass's tab after being
    force-killed, so the dark hero card came back showing the same page
    twice).
  - **The hero pair itself was also just plain missing from `dev`** —
    `website/shots/hero_windows.py` existed (added by `99c7bb36`, the commit
    that also gave plantoir.app its platform-conditional hero serving), but
    `site/img/hero-windows-light.png` / `-dark.png` did not, because the run
    that produced them was ONLY on `new-screenshots`. Regenerated fresh here
    rather than pulled from that branch, so they reflect today's redeploy and
    the section/class fixes above. Windows visitors were seeing the mac's
    hero image (`build.py`'s platform fallback) until this landed.
  - **A related bug, worth knowing regardless of the theming question and
    not on the old branch at all**: `MarketingShotCapturer.RunAsync` caught
    its own exceptions, logged them, and still called `Environment.Exit(0)`
    either way — so a mid-capture crash was invisible to
    `capture_windows.py`'s `subprocess.run(..., check=True)`, which reported
    success with whatever images happened to exist, stale ones included.
    This hid two of the three rejected theming fixes above from the exit
    code entirely; both were only visible in `%TEMP%\marketing_capture.log`.
    Now exits 1 on failure. **A second, independent instance of the same
    swallow was in `capture_windows.py` itself**: `Start-Process -Wait` does
    not forward the child's exit code to `powershell.exe`'s own, so even
    with the C# fix a crash still would not have surfaced — fixed with
    `-PassThru; exit $p.ExitCode`. Worth a glance on the mac only if
    `capture.py` has an analogous "subprocess exit code stands in for a
    success check" assumption anywhere; nothing here suggests it does.
  - **`new-screenshots` (local and `origin/new-screenshots`) is now safe to
    delete** — its useful commits are carried forward as described above,
    and its one 26-image commit is superseded by today's re-shoot. Left in
    place rather than deleted here, since it is Russell's own branch.
  - Reference: `windows-app/Plantoir/Services/MarketingShotCapturer.cs`
    (`RunAsync`, `CaptureNewCourseWindow`), `windows-app/Plantoir/App.xaml.cs`
    (the `--theme` argument), `website/shots/capture_windows.py`
    (`DEMO_COURSES`, `capture_app_windows`), `website/shots/hero_windows.py`
    (`most_recent_class`, `SECTION`, `capture_edge`).

- **plantoir.app now has a Windows hero composite, and `deploy_site_name`
  turned out not to be a key** (Windows, 2026-08-19, commit "Give the Windows
  marketing shots a hero composite, and fix three fixtures").
  - **What changed**: the hero image existed only for the mac, so
    `build.py`'s platform swap served Windows visitors a picture of a Mac.
    `website/shots/hero_windows.py` now produces `hero-windows-light.png` and
    `hero-windows-dark.png` from Obsidian, Plantoir mid-deploy and Edge on
    the published site, through the same `composite.diagonal_hero()` the mac
    uses. Nothing on the mac side changes: `build.py` picks the twin up by
    file name the moment it exists.
  - **The one mechanism worth knowing**, because it is where the two
    platforms genuinely differ: the mac's `screencapture -l <window id>`
    returns a single window with its rounded corners already transparent.
    Windows has no equivalent, so every card is a REGION of the screen —
    the window is placed, raised, and the rectangle `DwmGetWindowAttribute`
    reports as `DWMWA_EXTENDED_FRAME_BOUNDS` is grabbed, then the corners are
    masked. `GetWindowRect` is the wrong rectangle: it includes an invisible
    resize border. **Rejected**: `PrintWindow`, which can capture a window
    bigger than the screen and would have avoided the sizing constraint
    below, but returns black for WinUI 3 surfaces.
  - **Consequence the mac does not have**: the cards are limited by the real
    desktop. This machine is 1920×1080 at 150%, so a work area of 1920×1008
    caps them at 1680×960 real pixels — a wider aspect than the mac's
    1280×800 cards. The finished figures still land at the shared
    `FIGURE_WIDTH` of 1700, so the column edges line up down the page.
  - **A `--hero-window <theme>` mode was added to `Plantoir.exe`** for the
    middle card. **Rejected**: reusing the `RenderTargetBitmap` the other
    Windows shots use — it renders the visual tree, which has no title bar,
    so Plantoir would have been the one card in the cascade with no window
    chrome beside Obsidian's and Edge's.
  - **The `deploy_site_name` question is answered**, and the answer is not
    the one `WINDOWS-HANDOFF.md` anticipated. That file asked this side to
    decide what the capturer's fixtures should write now the demo sites are
    named per section (`<code>-s<n>-2026-gordon`), since the new scheme names
    a SECTION while the key sits in course-level config. The key was never
    real: it appears in no launcher, in no contract —
    `contracts/file-formats.json` lists what `course_config.json` carries and
    it is not there — and nowhere else in either app. **Renaming it would
    have looked like settling the question while changing nothing.** The
    fixtures now write `.netlify_sites/section<n>.json`, the per-section
    marker a real deploy leaves and the one `build_site.py`'s
    `resolve_section_domain` and `deploy.py`'s `load_netlify_marker` actually
    read. Worth a glance on the mac only to confirm nothing there writes the
    invented key either.
  - **A second invented key was found beside it**: the same fixtures wrote
    `section_count`, which nothing reads, so every demo course came up with
    ONE section while the mac's showed two. It is `num_sections` /
    `section_numbers`. Reference:
    `windows-app/Plantoir/Services/MarketingShotCapturer.cs`.
  - **Nothing for the mac to match.** Both harnesses photograph their own
    platform; this is a note so the next mac session is not surprised to find
    a `hero-windows-*` pair in `site/img/`.

- **Deploys ask for the teacher's surname only when NAMING a new site, never
  on a repeat deploy** (Shared Python, 2026-08-19).
  - **What was fixed**: `deploy.py` called `get_or_prompt_teacher_last_name()`
    unconditionally at the top of every deploy. On a machine with no saved
    surname that stopped EVERY deploy for input — including deploys to a
    section whose site already existed and needed no name at all. In the GUI
    the question surfaces as a dialog, but a missed or cancelled dialog read
    as "deploys are broken", and in any non-interactive context the answer
    was silently None anyway. Seen live during Russell's presentation prep:
    a fresh workspace's first app deploy stalled at the surname question and
    never reached site creation.
  - **The fix**: the surname is LOADED silently at the top
    (`load_teacher_last_name()`), and `get_or_prompt_teacher_last_name()`
    runs only at the two places a NEW name is being chosen — the Netlify
    `not site_marker` branch and the Cloudflare no-marker branch. A repeat
    deploy therefore asks nothing anywhere: GUI, MCP, scheduled, or shell.
    Verified live on Windows: repeat deploy with no saved surname and no
    profile.json completed with zero prompts and wrote no profile.
  - **Rejected**: keeping the eager prompt and teaching every caller to
    pre-seed profile.json (fixes one machine at a time — the failure just
    met is exactly that patch not scaling); prompting but defaulting after a
    timeout (a deploy that behaves differently depending on how fast you
    answer is worse than one that never asks).
  - **Mac impact**: shared `deploy.py` — rebuild the mac app so its bundled
    toolchain carries it. The mac's own GUI has the same exposure (its
    launcher runs on a pseudo-terminal, so the eager prompt fired there
    too).

- **Two corrections to the release-packaging sync, made while integrating it
  on Windows** (Windows, 2026-08-19, follows `6326c8c9`/`1117e47c`).
  - **`windows-app/publish.ps1` could not START on Windows.** The new
    installer block used the null-conditional operator (`?.`), which Windows
    PowerShell 5.1 — the interpreter the script's own header prescribes via
    `powershell -File` — cannot parse: the whole file failed with
    "Unexpected token '?.Source'" before running a line. Verified with the
    5.1 parser before and after; now rewritten as a plain `if`. When writing
    PowerShell from the mac, treat 5.1 as the floor: no `?.`, `??`, ternary,
    or pipeline-chain `&&`/`||`.
  - **The Métis skeleton rename would not have survived regeneration.**
    `support/skeletons/` is generated (`generate_skeletons.py`), and
    `1117e47c` renamed a generated file by hand — the next
    `generate_skeletons.py` run would have resurrected the accented filename
    and dropped the alias, silently. The rule now lives in the generator
    (`write()` folds combining marks out of filenames and inserts the
    accented alias after the title) and in `lint_skeletons.py` (title may
    differ from filename only by combining marks, and only with the alias
    kept). Regeneration verified byte-identical to the committed tree.
    Rejected: leaving the hand-edit in place (a generated tree that differs
    from its generator is a time bomb) and ASCII-folding en dashes / ² too
    (single code points do not decompose in a DMG; seven such names ship in
    example_content today and are fine).

- **Netlify uploads now retry on 429 with backoff, at 5 workers not 10**
  (Shared Python, 2026-08-19, follows `e0136437`).
  - **What was fixed**: the parallel-upload optimization (`e0136437`, 10-worker
    `ThreadPoolExecutor`) broke EVERY deploy large enough to matter: Netlify
    rate-limits the per-file upload endpoint, and one 429 aborted the whole
    deploy. Measured live on Windows (WSL2 Docker, home broadband): a fresh
    318-file ICS3U deploy died on the first 429 — reproducibly — where the old
    serial loop had always stayed under the limit. So "optimized" deploys
    failed 100% of the time on any new site; that is why deploys "stopped
    working" the same evening the optimization landed.
  - **The fix** (`scripts/deploy.py` → `_upload_required_files`): each file
    upload retries up to 6 times on 429/500/502/503/504 and on socket
    timeouts, with exponential backoff (1 s doubling, capped 30 s), honouring
    a `Retry-After` header when Netlify sends one; workers reduced 10 → 5.
    A non-retryable API error still fails the deploy immediately.
  - **Rejected**: reverting to serial (throws away a real win once retries
    exist); keeping 10 workers with retries (converges, but spends its time
    backing off — 5 stays mostly under the limit); a global rate limiter
    shared across threads (more machinery than the endpoint's behaviour
    justifies — per-file backoff empties the herd quickly enough).
  - **Mac impact**: `deploy.py` is shared, so the mac had the same broken
    window between `e0136437` and this fix. Nothing to port — but the mac app
    must be REBUILT so its bundled toolchain carries the fix, or every
    working folder it refreshes keeps deploying with the 10-worker version.

- **`Get-ToolchainHash` in the `.ps1` launchers now anchors to the launcher's
  own folder** (Windows launchers only, 2026-08-19). `.sh` launchers are
  unaffected — bash `cd` moves the real process CWD.
  - **What was fixed**: the PowerShell hash function resolved its relative
    context (`./.toolchain`) with .NET path APIs, which use
    `Environment.CurrentDirectory` — and `Set-Location` does NOT update that.
    A launcher invoked from a process whose CWD held a *different* stale
    `.toolchain` (seen live: a terminal session sitting in the repository,
    which had an Aug-11 mirror at its root) hashed the stale folder, matched
    an Aug-11 image tag, and silently ran week-old scripts while `docker
    build`'s context — resolved from the PowerShell location — pointed at the
    fresh folder. Image tag and image contents could disagree.
  - **The fix**: `$fullContext` is now built from `(Get-Location).ProviderPath`
    (the launchers `Set-Location` to their own folder at startup), in
    `deploy.ps1`, `preview.ps1`, and `setup.ps1` alike.
  - **Mac relevance**: know that a Windows image tag from before this fix may
    not describe its contents; if a Windows machine misbehaves after sync,
    recreating the container clears it.

- **Production rebuilds in `deploy.py` delegate to `build_site.py --build-only`**
  (Shared Python, 2026-08-18).
  - **What was fixed**: After Quartz build staging moved to container-internal ext4 storage (`/tmp/quartz-builds/<COURSE>/section<N>`), `deploy.py` failed when rebuilding for production (when detecting preview live-reload scripts in `index.html` or updating `baseUrl` for live site domains). It was calling `npx quartz build` directly in `cwd=section_dir` (`/teaching/courses/<COURSE>/.merged_output/section<N>`), which in the dual workspace architecture contains only `public/` and `course_config.json` rather than the full Quartz scaffold. If `/tmp/quartz-builds` was clean (e.g. freshly created container, or deploy without preview in the same session), `deploy.py` crashed immediately with `Production rebuild failed`.
  - **The fix**: `deploy.py`'s `rebuild_for_production` and `ensure_base_url_and_rebuild` now delegate production rebuilds directly to `build_site.py --course <COURSE> --section <N> --build-only`, which ensures the internal workspace is staged, applies all patches and domain markers, generates the production build without the live-reload websocket, and syncs `public/` cleanly via `_sync_public_to_host`.

- **Whole Unit Publish / Unpublish and MCP Tool Parameter Binding on Windows**
  (Windows, 2026-08-18). Awareness only; Windows now matches macOS behavior for whole unit operations.
  - **What was fixed**:
    1. Prompt shelf and card commands for "Unpublish Unit 4" generated tool calls missing `includeLinked`, causing ModelContextProtocol.NET binding errors on tools with non-optional parameters. Added default values (`includeLinked = false`, `progress = null!`, `cancellation = default`) across MCP tool declarations in `PlantoirTools.cs` and populated defaults in `AssistCardCommand.cs`.
    2. Implemented `PublishPlan.UnitNamed` and `AssistWorkspace.PlanWholeUnit` / `ApplyWholeUnit` matching `AssistToolRunner.swift:598-790`. Whole units step through class pages in order (Day N down to 1 for unpublishing, Day 1 up to N for publishing), batch all file edits into a single undo entry, and trigger a single preview rebuild.
  - **Testing**: Added whole unit unit tests in `ToolAnswerTests.cs` covering plan description, whole unit unpublish, whole unit publish, and whole unit single-step undo. All 522 tests pass.

- **Assist Plan Formatting & Graph Sweep Parity Completed on Windows**
  (Windows, 2026-08-18). Awareness only; Windows was brought into 100% byte-for-byte
  parity with macOS for all assist tool plans and suggestions (`PublishPlan`, `ReDatePlan`,
  `CurriculumMentionsPlan`).
  - **What changed**: Windows was outputting technical mechanical descriptions (file paths,
    frontmatter keys `publishForSection1: false → true`, `(2027-01-15, publish: true → false)`,
    arrows `→`, fake index embed diffs, and Netlify deploy boilerplate). Rewrote `PublishPlan.cs`,
    `ReDatePlan.cs`, and `AssistWorkspace.cs` unpublish sweep algorithm to match
    `AssistPublishPlan.swift` and `SectionReDatePlanner.swift` exactly.
  - **Graph Unpublish Sweep**: Implemented reason-to-keep link traversal (`“Tech Headlines” stays visible, because “Unit 1, Day 15” still links to it.`),
    landing page preservation, Key Links protection, curriculum page preservation, and transitive link following for publishing.
  - **Testing**: Added `AssistPlanParityTests.cs` explicitly validating the ICD2O Section 1 unpublish
    case and plan structures. All 518 unit tests in `Plantoir.Tests` pass.

- **Two `check_section` defects, one teacher report — and the second is the
  one that generalises** (Windows, 2026-08-18, `windows-sync`). Awareness

  only; the mac is right on both counts already.

  Asked what students would see, Windows answered "83 visible pages are linked
  from nowhere" and listed the course's own lessons. **(a)** Class pages were
  counted as orphans. The mac excludes them — `AssistSectionPage.isClassPage`
  — and its comment records hitting exactly this on an 86-period credit that
  reported 84. Windows now excludes them by the course's own
  `per_section_folders` rather than by the mac's "parent folder name contains
  'class'" heuristic; if the mac ever wants the stricter rule, the config is
  the better source. Note the two questions that must NOT be merged: the
  contract's `followingLinks.neverTakenDownByFollowingLinks` is about what
  unpublishing may sweep, and a class page IS swept.

  **(b)** is the one worth knowing over here, because it is a whole CLASS of
  bug this side cannot have. The preview state was read from `PreviewLeases`,
  an in-memory static belonging to the app — but `check_section` runs inside
  `plantoir-mcp`, a different process, where that list is permanently empty.
  So "Nothing is being previewed at the moment" was said every single time,
  whatever was on screen; the trail shows the teacher pressing Preview 32
  seconds before asking. On the mac the assistant and the preview are the same
  process and `sectionWindow(...)?.previewState()` is a method call, so the
  question never arises.

  **The shape of it: an in-memory static read from the wrong process does not
  fail, it answers "nothing".** That is indistinguishable from a true answer,
  which is why it survived. `WorkLease` — the on-disk, format-first registry —
  was already written for precisely this and was simply not being read. If the
  mac ever splits its MCP server out of the app bundle, every `PreviewLeases`
  and `CourseActivity` read becomes this bug at once.

  Two limits, stated because they are real: the leases are per-COURSE rather
  than per-section, so previewing Section 2 while asking about Section 1
  reports the wrong thing; and the build lease is released the moment the
  server answers, which is what makes "building" and "showing" two states
  rather than one.

- **The confirmation setting on Windows was wired to nothing for weeks**
  (Windows, 2026-08-18, `windows-sync`). Awareness only — the mac has had
  this since plan mode shipped — but worth recording because of HOW it went
  unnoticed. `AssistAgent.ConfirmationMode` was set from
  `AppSettings.AssistantAsksBeforeChanging` in `AssistWindow` and then never
  read, so the switch in Settings did nothing; and the discoverability nudge
  after fifteen accepted plans ("The assistant shows what it is about to do
  before doing it. You can change that in Settings.") was firing and
  describing behaviour the app did not have. A setting that is stored,
  displayed and ignored looks exactly like a setting that works.

  Now ported. Two Windows-specific pieces the mac may care about:
  `AssistToolOutcome.isPlan` is an in-process field here and had to become a
  second `_meta` key over MCP (`plantoir.app/isPlan`, sent only when true) so
  the gate can tell a plan from a plan tool's REFUSAL; and
  `AssistAgent.PlanTwins` deliberately omits `re_date_classes` even though the
  contract lists a twin for it, because it is not a tool the local model is
  shown and its twin does not mark its answer.

- **Windows was chatty for one structural reason, and it was not wording**
  (Windows, 2026-08-18, `windows-sync`). Recorded because the mac's own
  design is what fixed it, and because the reasoning behind `AssistToolOutcome`
  is not written anywhere the Windows side could have read it.

  Every Windows tool returned ONE string, and it was shown to the teacher AND
  fed to the model. So "read Unit 2, Day 3" put a lesson's entire Markdown in
  the chat window; "what pages are in this section" put sixty file paths
  there; a publish said "Published 4 pages (A, B, C, D) and rebuilt the
  preview of ICS3U Section 1"; and every plan ended with "Show this to the
  teacher and ask before going ahead" — a sentence addressed to the model,
  directly above the two buttons that ARE the asking. Two earlier attempts at
  this (log rows 344 and 345) shortened individual sentences and fixed the
  turn-taking, and neither touched the split, so the chattiness survived both.

  The mac's teacher-facing lines are now Windows' too, word for word:
  `Read “Unit 2, Day 3”.` · `Found 42 pages in ICS3U Section 1.` ·
  `Nothing matched in ICS3U Section 1.` · `Published 4 pages.` ·
  `Unpublished 2 pages.` · `Published the class on 2026-09-10.` ·
  `It's already been published.` · `Added Unit 2, Day 4, dated 2026-09-14.` ·
  `ICS3U Section 1 meets on 75 recorded days.` ·
  `Scheduled: ICS3U Section 1 deploys to Netlify at Tuesday 9 June, 6:30 AM.`
  Undo now speaks the contract's sentences rather than its own.

  **The one thing the mac may want to know for its own sake**: the split
  costs the mac nothing because its runner is in-process, but Windows drives
  the same `plantoir-mcp` Claude Code drives, so the summary needed a wire.
  It rides in the tool result's `_meta`, under `plantoir.app/teacherSummary`,
  and the text content is untouched — Claude Code sees exactly what it saw
  before. Rejected: a second text content block (Claude Code would read both
  and report the teacher's line as part of the answer), and
  `structuredContent` (it is validated against a declared `outputSchema`, and
  declaring one changes what every client sees of every tool). If the mac's
  MCP server ever wants to hand a summary to a client of its own, that is the
  channel, and `AssistToolAnswer.TeacherSummaryKey` is the frozen key.

  Two smaller things found in the same sweep, both fixed on Windows and
  neither present on the mac: the turn-ending list named `roll_over_course`
  for a tool actually called `roll_over_section` (so that write got the model
  a lap it should not have had, and the teacher a paragraph restating the line
  above it), and `list_recent_changes` ended by telling a teacher that
  "undo_last_change takes the most recent one back" — rule 1, in the one place
  a teacher is most likely to be reading.

- **Anything you build over there now owes a trail line** (mac, 2026-08-16).
  Plantoir keeps a breadcrumb trail so a problem reported next week can be
  looked into without asking the teacher to reproduce it, and the rule binds
  both sides: **every new feature, and every changed behaviour, that a teacher
  can see records an event.** The list lives in
  [`contracts/shared-rules.json`](contracts/shared-rules.json) →
  `activityTrail.mustRecord`, with `lineShape` and `promptMarker` beside it,
  and a test pins it against each app's own event list.

  The direction rule applies as usual and in your favour: **propose an event by
  adding it to `mustRecord`.** The mac suite will go red until this side
  records it — that is the mechanism working, not damage — so name the case in
  "Contract cases waiting on the mac" above and it reads as a request. The
  reasoning, the storage locations and what must never be recorded are in
  `WINDOWS-HANDOFF.md` under "Problem reports"; `CLAUDE.md` rule 5 is the short
  version.

- **A divergence was reported TO Windows, not from them** (mac sweep,
  2026-08-16). The first-deploy marker: this side reads the marker for the
  course's CURRENT destination, `AssistWorkspace.cs` accepts either folder.
  Written up in `WINDOWS-HANDOFF.md`. Nothing to do here — the mac's behaviour
  is the correct one — but if they answer with a reason for their version,
  that answer belongs in `contracts/file-formats.json` beside the rule.



Things to KNOW rather than to do. An item here that grows an ask should move
up to **Open** instead of hiding a to-do in a list nobody reads for work — which
is what happened to the test-race item, sitting here for three days with
"worth ten minutes to check" in the middle of it.


- **WSL2 / Container-Internal ext4 Build Acceleration** (Windows + shared, 2026-08-18, commit `ed868215`).
  Accelerated Quartz site builds on both platforms by eliminating the virtual host mount I/O bottleneck (WSL2 9P DrvFs on Windows, Colima virtiofs/9P on macOS):
  - **The Problem**: Staging the 15,000+ files of Quartz's scaffold and `node_modules` in `courses/<COURSE>/.merged_output/section<N>` meant that all TypeScript transpilation, esbuild bundling, and markdown AST parsing traversed virtual filesystem mount layers. On Windows with WSL2, initial builds took 2–4 minutes; on macOS, clean builds took ~18.7s with 14s burned on `npm install` across the mount boundary.
  - **The Solution**:
    1. Pre-bake `npm install` inside the container image in `/opt/quartz` (`Dockerfile`).
    2. In `scripts/build_site.py`, stage the Quartz workspace on native Linux ext4 storage (`/tmp/quartz-builds/<COURSE>/section<N>`), symlinking `/opt/quartz/node_modules` instantly.
    3. `scripts/build_site.py` runs differential `rsync -a --delete` to mirror `public/` and `course_config.json` back to `/teaching/courses/<COURSE>/.merged_output/section<N>/public/` upon build completion (and via a daemon thread in `--serve` mode), preserving 100% compatibility with `BuildFreshness`, `SectionDetailView`, `ScheduledDeploy`, and `deploy.py`.
    4. Updated `preview.ps1` and `preview.sh` `--stop` scripts so `PreviewStopper` checks `/tmp/quartz-builds/...` PIDs in addition to `.merged_output/...`.
    5. Updated `deploy.py` to support container-internal rebuilds.
  - **Results**:
    - **macOS (Apple Silicon + Colima)**: Full/clean builds dropped from **18.66 s avg** (18.39 s min) down to **5.08 s avg** (4.58 s min) — **3.7× faster**; incremental rebuilds dropped from **4.42 s** to **3.35 s** (1.32× faster) on `EXC2O` (260 Markdown files).
    - **Windows (Intel Core i5 + WSL2)**: Initial scaffold copy dropped from 45s to < 0.1s; `npm install` over 9P dropped to 0s; site builds run at native NVMe/ext4 speeds. All 570 Windows unit tests pass.
  - **✅ DONE (Adopted on macOS & merged to main, 2026-08-18).** All 760 macOS unit tests and `./verify.sh` pass.

- **Arrow-key prompt history navigation in Windows assist chat** (Windows, 2026-08-18).
  Windows now supports Terminal-style Up/Down arrow key history navigation in `AssistWindow.xaml.cs`.
  - **Behavior & Contract**: Follows `contracts/assist-cases.json` → `promptHistory`. Up recalls earlier prompts (newest first), Down recalls later prompts, half-typed draft is preserved and restored when walking back down past newest, Up at oldest or Down when not walking passes the key through to the `TextBox` (letting caret move to start/end), typing/editing ends the walk, and multi-line text passes arrow keys through to allow vertical caret movement.
  - **Persistence**: Added `AssistPromptHistories` dictionary to `AppSettings.cs` (`%LOCALAPPDATA%\Plantoir\settings.json`), keyed per section (`$"AssistPromptHistory-{course.Code}-{section}"`) matching macOS `@AppStorage` convention.
  - **Reference**: `AssistWindow.xaml.cs`, `Plantoir.Core.Assist.AssistPromptHistory`, and unit tests in `Plantoir.Tests.AssistPromptHistoryTests` (514 tests passing).

- **Windows local assistant moved out of WSL2 to host process with Vulkan GPU acceleration** (Windows, 2026-08-17).
  Windows now runs `llama-server.exe` natively on the host instead of running a Linux container in WSL2.
  - **Why**: In WSL2 without GPU pass-through, a 3,400 token prompt prefix took ~175 seconds across 2 virtual CPU cores, necessitating an artificial progress countdown bar, a 98 MB disk prefix cache (`--slot-save-path`), and a background keep-awake hack (`_keepWslAwake`). Moving to a native Windows host process enables Direct3D12/Vulkan GPU acceleration across Intel/AMD/NVIDIA graphics and multi-threaded host CPU fallback.
  - **Vendor fetch & bundling**: Added `windows-app/Vendor/fetch-llama.ps1` downloading pinned build `b10435` (`llama-b10435-bin-win-vulkan-x64.zip`) into `windows-app/Vendor/llama/`. Updated `Plantoir.csproj` to bundle into `llama\` output, and `publish.ps1` to sign `llama-server.exe`.
  - **Hardware Measurements**: Measured on teacher laptop hardware — `Intel Core i5-8365U CPU @ 1.60GHz` (4C/8T), `Intel UHD Graphics 620` (8062 MiB Vulkan device memory), 16 GB RAM:
    - *Vulkan GPU (`-ngl 999 -dev Vulkan0`)*: Prompt processing (`pp512`): **25.82 tok/s**, Generation (`tg128`): **7.83 tok/s**, single turn cold response: **~17.99 s**.
    - *Host CPU fallback (`-ngl 0`)*: Prompt processing (`pp512`): **25.69 tok/s**, Generation (`tg128`): **11.67 tok/s**.
  - **Simplification**: Removed the fake 3-minute progress countdown and disk KV cache files from `AssistWindow.xaml.cs`. Warmup is now a fast, non-blocking background priming call. 464 tests passing in `Plantoir.Tests`.

- **Assist scenario contract runner & confirmation discovery parity on Windows** (Windows, 2026-08-18).
  The Windows side wired `AssistScenarioTests.cs` executing all 17 multi-turn scenario cases from `contracts/assist-cases.json` via parameterized `[Theory]` tests against `AssistAgent`.
  Async preview teardown before deploy was implemented via `PreviewStopper.StopSectionProcessesAsync` and `SectionDetailView.StopPreviewIfRunningAsync`, ensuring container and host preview server ports are fully vacated before `deploy.ps1` runs.
  Confirmation mode (`AppSettings.AssistantAsksBeforeChanging`) and 15-plan discovery milestone tracking (`plansAccepted >= 15` app-wide) were wired into `AssistAgent` and `AssistWindow.xaml.cs`, verified by `ContractTests.cs`. All 488 tests pass.


- **Windows marketing screenshots & platform-conditional serving on plantoir.app** (Windows, 2026-08-17).
  The Windows side implemented autonomous screenshot capture in `MarketingShotCapturer.cs` (`Plantoir.exe --capture-marketing-shots <dir>`) and `website/shots/capture_windows.py`.
  The 5 app-window marketing shots (`courses`, `new-course`, `progress`, `preview`, `assistant`) are captured in Light and Dark mode at 2x HiDPI resolution, optimized with WebP companions into `site/img/`.
  In `website/build.py`, `picture_element` outputs both Mac (`.shot-platform-mac`) and Windows (`.shot-platform-windows`) `<figure>` blocks when Windows variants exist.
  `website/layout/base.html` detects Windows visitors via an inline `<script>` in `<head>` and toggles CSS class `is-windows` so Windows visitors see native Windows WinUI 3 screenshots while macOS visitors continue seeing native macOS SwiftUI screenshots.


- **Cleanup that fails must not fail a test that passed** (Windows,
  2026-08-14, `0479d44`). An intermittent failure that never reproduced turned
  out to be 23 tests ending with a bare
  `finally { Directory.Delete(root, recursive: true); }`. On Windows that
  throws whenever anything still holds a handle in the folder — Defender
  scanning the files the test just wrote, or the Search Indexer. Every
  assertion had passed; the test failed on housekeeping. If the mac's tests
  do the same on a machine with Spotlight indexing, the same shape is
  available. Deleting a temp folder is housekeeping: when it does not work,
  the OS will get to it.


- **The MCP proposal's Phase 0 question is settled** (asked 2026-08-12,
  answered 2026-08-15). The design for letting AI assistants drive Plantoir
  over MCP — "publish the Science courses overnight and un-draft tomorrow's
  class plus everything it links to" — asked the mac side whether to ship
  **one** self-contained .NET binary serving both platforms, or reimplement
  the tool contract in Swift. Both halves are now code rather than a
  question: `windows-app/Plantoir.Mcp/` is built and on `main`, and the mac
  reimplemented the contract in `Models/Assist/AssistMCPServer.swift` — the
  app itself answers `--mcp-stdio <folder>` rather than shipping a second
  binary, off the same `AssistToolSurface` the assistant window uses, so the
  two clients cannot drift. The handshake is recorded in the entry above.
  (The proposal itself is now folded into `research/ai-assist/HISTORY.md`.)


- **The Windows icon derives from `mac-app/Plantoir.icon`** (2026-08-11).
  `windows-app/Plantoir/Assets/make-icon.ps1` turns a full-bleed 1024px
  Icon Composer export into the exe/.ico and About-panel assets, applying
  the macOS rounded-rect silhouette; `site/icon.png` on plantoir.app
  comes from the same export. If the icon art ever changes, tell the
  Windows side so those derived assets are regenerated — nothing updates
  them automatically.


- **Auto-update plans need appcast coordination** (2026-08-12). Windows
  will adopt WinSparkle (paired with an Inno Setup installer, planned
  after v1.0); if/when the mac app adopts Sparkle, BOTH appcasts should
  live on plantoir.app in this repo's `site/` — use per-platform file
  names from the start (`appcast-windows.xml`, `appcast-macos.xml`) so
  the two update feeds never collide, and add the release-time appcast
  edit to the shared checklist in `RELEASING.md` when the
  first one lands.


- **The mac release asset must be named exactly `Plantoir-macOS.zip`**
  (2026-08-11; SPECCED — the mac ships a zip, not a dmg: Safari
  auto-unzips, average users fumble the dmg ritual, and Sparkle handles
  zips natively). plantoir.app now lives in `site/` in this repo
  (Netlify deploys it on push) and its download cards link straight to
  `releases/latest/download/<asset-name>` — GitHub's evergreen URL that
  only works while every release names its assets identically. Windows
  ships `Plantoir-win-x64.zip`; the mac card expects
  `Plantoir-macOS.zip`. The names are frozen: renaming an asset silently
  breaks the site's download button.


- **The release process is shared — read `RELEASING.md`**
  (2026-08-11). The decisions that bind both sides: ONE product version
  series in lockstep (Windows reads `<Version>` in `Plantoir.csproj`;
  keep the mac marketing version matching), ONE GitHub release per
  version carrying BOTH platforms' assets (plantoir.app's download cards
  point at `releases/latest`), tag `v<version>`. Release notes are
  drafted by Claude via the `cut-release` skill
  (`.claude/skills/cut-release/`) — teacher-friendly bullets from the
  commit log plus a SHA-256 downloads table; the mac asset should be
  attached to the same release and hashed into the same table. (The
  `.claude/skills/example-content/` skill has since arrived — the mac
  side un-ignored `.claude/skills/` and committed it.)


- **Course-catalog repairs** (`37dc6c8`): MTH1W read "Mathematics,
  Grade 9, Grade 9, Destreamed" (short name "Math,") and PLF4M had the
  same doubled-grade + trailing-comma pattern; both repaired in
  `support/ontario_secondary_courses.json`. The mac app picks this up by
  rebuilding (bundled support folder). No other entries matched either
  pattern.


- **Toolchain hash changed** (`94e25f8`): `scripts/deploy.py` changed,
  so the next preview/deploy on any machine rebuilds the Docker image
  once.


- **Windows caught up with rows 91–96** (`e7076ae`): Starting Content
  toggles, structure lock, LCS terminology switch, and the neutral
  factory defaults are now mirrored on Windows (including the
  `WizardDefaults` pairing and a Windows `ExampleContentCatalog`).
  Nothing to do on mac — listed so the mac side knows the wizards agree
  and that changes to `DEFAULT_*`/`LCS_*` in `scripts/setup_course.py`
  must now be mirrored in BOTH apps' `WizardDefaults`.


## Done — the ledger

Kept in full, newest first. A finished entry is not deleted: the mac does what
it does BECAUSE of these, and the `✅ DONE` line names what landed here and
where.

- ✅ DONE (Windows, 2026-09-06). **Items 15 and 16 ported: a course's own
  words for a unit and for its class folder. Nothing is asked of the mac — this
  entry exists for the two things the port learned that the write-up did not
  say.**

  The feature itself arrived as designed: `unit_word` and `class_folder`,
  absent meaning what every existing course already does, with the rule in
  shared Python and the cases in `class-planning.json`. `ClassPageTerm.cs`
  mirrors `scripts/class_pages.py`; `ClassFolderRule` gained the recorded-key
  overload; the wizard asks the question and writes both keys. Four of the
  five contract tests that were red on this side now pass.

  **What the handoff did not warn about, and cost the most time: the port is
  not finished when the RULE is ported.** Item 15 names the assistant's
  sentences and the wizard field, so those were expected. What was not listed
  is that two call sites BUILD PAGE TITLES rather than sentences —
  `"Unit {unit}, Day {atDay + i}"` when adding classes, and the same shape
  when making room for them. In a Module course those write files the course's
  own rule then refuses to recognise as class pages, which is the feature's
  own silent failure arriving by a second route, from the app rather than from
  the parser. Worth checking that the mac's equivalents (`AssistWorkspace`'s
  add-classes and make-room paths) use `ClassPageTerm` rather than a literal —
  this side had four such literals and the handoff's list of owed items
  mentioned none of them.

  **The second: `SectionIndex`'s date tie-break.** When two pages share a
  date, the later page in the course wins, decided by parsing both names. In a
  Module course neither name parses under the default word, so the tie-break
  silently degrades to whichever file the walk reached first. Not mentioned
  anywhere, found by grepping for every `UnitDay.Parse` rather than by
  following the write-up.

  **The general lesson, which is the part that travels:** for a feature whose
  failure mode is "answers no instead of refusing", the owed-items list should
  be produced by grepping for every CALL of the thing being made
  configurable, not by listing the features a reader can think of. The mac's
  own list was written the second way, and both misses above are the same
  shape.

  **Reference:** `Plantoir.Core/Models/ClassPageTerm.cs` (new),
  `UnitDay.cs`, `ClassFolderRule.cs`, `CourseConfiguration.cs`,
  `Assist/AssistWorkspace.cs`, `Assist/SectionIndex.cs`,
  `Models/NextClassPlanner.cs`, `Views/NewCourseDialog.cs`. Tests:
  `ClassPageTermTests.cs` (new), `ClassFolderContractTests.cs` and
  `ClassPlanningContractTests.cs` (both now read the contract's optional
  `classFolder` and `term` fields with a default).

- ✅ DONE (Windows + shared, 2026-09-05). **A publish on Windows was
  overwritten by its own preview, silently — and, separately, publishing to a
  folder could not succeed there at all. Both found by publishing for real.**

  **The first bug, which is the one item 20 sent me after.**
  `build_site.py --build-only` has always asked for the section's preview
  server to be stopped before it builds for publishing. On native Windows the
  ask did nothing: `stop_preview.read_proc_snapshot()` reads `/proc`, Windows
  has none, the list came back empty and `stop_preview_serving()` returned 0.
  Meanwhile `_start_public_sync_watcher` — started in the SERVE branch and
  therefore running natively on that platform too — went on mirroring the
  serve build into the same directory about once a second. So a publish that
  ran while that section was previewing was overwritten within a second of
  finishing, and what went out was the PREVIEW, live-reload client and all.
  Nothing errored and nothing was logged.

  **What was chosen, and what was rejected.** Item 20 offered three shapes
  and asked for the reasoning, so here it is. The fix went into
  `stop_preview.py` as a native process-snapshot reader, because every
  exposed route already funnels through the ONE call that reader feeds:
  `preview.ps1 --build-only`, `deploy.ps1`'s folder branch (which shells
  `preview.bat ... --build-only`), `deploy.py`'s `rebuild_for_production` —
  the route a Netlify or Cloudflare publish takes — scheduled deploys, and
  `plantoir-mcp.exe`'s `deploy_section`. One edit covers all five and every
  caller nobody has written yet.

  - **Rejected: `stop_preview.py --match-stdin`,** with PowerShell driving.
    It inverts the control flow, so it reaches only PowerShell callers, and
    `deploy.py` → `build_site.py` is not one of them. Choosing it alone would
    have left the Netlify and Cloudflare route racing — the one a teacher is
    most likely to be using.
  - **Rejected: having `deploy.ps1` stop the preview itself.** The smallest
    change, and the one that leaves every future caller free to reintroduce
    the bug. `plantoir-mcp.exe` was already exactly such a caller.
  - **Rejected: calling `preview.ps1`'s matcher from its own `--build-only`
    path,** which is what item 20's first bullet literally asked for. Same
    reason as the first rejection: the launcher cannot see the `deploy.py`
    route.

  **The `--match-stdin` question item 20 asked me to settle.** Not adopted,
  and the reason has changed from the one item 20 anticipated. It worried
  that Windows could not rely on Python being resolvable when `--stop` runs.
  That worry is answered: stop mode already refuses to run without
  `$NATIVE_RUNTIME`, whose `manifest.json` sits beside the bundled
  `python\python.exe`, so the interpreter is exactly as available as the
  runtime the mode already requires. The reason it is still not adopted is
  different: `--stop` is what runs when a teacher closes a window or cancels
  a publish, both callers discard its output, and neither checks its exit
  code — so a Python that fails to start there would leak processes in total
  silence. PowerShell enumerating, deciding and killing in one process has no
  such step. **What removes the drift risk is not single-sourcing but the
  cases**: `windows-app/test_stop_preview.ps1` now runs the contract's own 23
  against the launcher's matcher, so the two implementations are held to one
  rule by the thing that can actually check.

  **Three details that would each have made the fix silently do nothing,
  measured on Windows 11 Pro 26200, Intel i5-8365U, 275 processes.**
  - PowerShell's default pipe encoding is the OEM code page. A teacher whose
    user folder is named José gets byte 0x82 where the accent belongs —
    either a decode error, or, with `errors="replace"`, a path that never
    matches, so nothing is ever stopped for that teacher and nothing says so.
    `[Console]::OutputEncoding` is set explicitly.
  - `signal.SIGKILL` does not exist on Windows. Both kill sites would have
    raised `AttributeError` the moment the snapshot stopped coming back
    empty — which is precisely what this change does to it.
  - `os.kill` on a pid that has already gone raises a plain `OSError`
    (`[WinError 87]`) there, never `ProcessLookupError`. Catching only the
    POSIX pair would have taken a publish down with a traceback the first
    time a preview exited between the snapshot and the kill.

  Cost of the new reader: **485/500/518 ms** for a full `Win32_Process` →
  JSON round trip called from Python, three runs, against a build that takes
  tens of seconds. An in-process `Get-CimInstance` is 521 ms, so essentially
  all of that is the query rather than the shell.

  **The second bug, which the first one uncovered: publishing to a folder
  could not succeed on Windows, ever.** Found by running the publish rather
  than reasoning about it. Every folder publish announced "This site was
  built by a preview", rebuilt whether it needed to or not, waited the full
  30 s for a condition that could never come true, and refused with "The
  rebuilt site still carries the preview's live-reload script. Nothing was
  published" — against a site whose 314 pages carried no live-reload client
  at all.

  The cause is a Windows PowerShell 5.1 semantic, and it is worth the mac
  knowing about because the mac wrote this code (GUI-IMPROVEMENTS row 392,
  mirroring `deploy.sh`) and could not run it:

      if ($files | Select-String -Pattern "ws://localhost:" -List -Quiet)

  `-Quiet` fed a PIPELINE of file objects emits one result PER FILE, not one
  answer for the tree. 314 clean pages come back as a 314-element array of
  `$null`, and **in PowerShell a non-empty array is TRUE whatever is in it**.
  So the test was true whenever the site had two or more pages, which is every
  real site — exactly one page is the single case it got right, by accident,
  because a one-element array unwraps to the falsy scalar it holds. All three uses
  were affected: the one deciding whether to rebuild, the one the 30 s wait
  loop spins on, and the one that refuses to publish. `deploy.sh` is fine —
  `grep -rq` returns one exit status for the whole tree, which is the answer
  the check wants. **The general lesson for any PowerShell the mac writes
  blind: `-Quiet` is not a scalar when the input is a pipeline.** It is now
  one named function, `Test-CarriesLiveReload`, testing for a MatchInfo
  rather than a Boolean, so the count cannot change the meaning.

  **Proof, end to end, on the real launchers rather than in a unit test.** A
  copy of a real working folder (ICS3U, 289 pages), never Russell's own:
  started a preview, confirmed it served and carried the live-reload client,
  killed only the LAUNCHER, and confirmed the preview was still serving —
  the bug's precondition, reproduced. Then published: the log showed
  `🛑 Stopped the preview that was still serving this section (PID …)` twice,
  which had been impossible on that platform. With the folder-publish fix in
  place the publish then exited 0 in **2 s** where it had taken 150 s to
  fail, writing 328 files, 314 HTML pages, **0** carrying the live-reload
  client, front page present.

  **A test-isolation defect found on the way, which the mac should check for
  its own suite.** `ScheduledDeployCompletionTests.Dispose` set the trail
  override to null — which does not mean "no override", it means "use the
  teacher's real activity.txt" — so every test class that ran after it wrote
  there. On this machine that left **263 lines about fixture courses in the
  real activity trail**, the same file a problem report gathers, where a
  course that never existed reads as a fault that never happened. The field
  holding the original path was already there and simply never used. The
  written lines were left alone; they are Russell's log.

  **Reference:** `scripts/stop_preview.py` (`read_windows_snapshot`,
  `read_snapshot`, `stop_one`), `scripts/build_site.py`
  (`stop_preview_serving`), `deploy.ps1` (`Test-CarriesLiveReload`),
  `preview.ps1` (`Get-SectionProcessesToStop`, `Test-IsServing`),
  `windows-app/Plantoir.Core/Scripting/ReclaimedProcesses.cs`,
  `windows-app/Plantoir/Services/PreviewStopper.cs`. Tests:
  `scripts/test_stop_preview.py` (35, 2 skipped),
  `windows-app/test_stop_preview.ps1` (25 checks, 1 allowed skip, now run as
  a gate by `TheLauncherMatcherAnswersTheContract`),
  `windows-app/Plantoir.Tests/ReclaimedProcessesTests.cs`.

- ✅ DONE (Windows, 2026-08-22). **Toggling on "Also publish to Cloudflare" as
  a redundancy target, with Netlify (or a local folder) as the primary
  destination, permanently disabled Save with no way to fix it — fixed by
  giving the additional-Cloudflare row its own real Account ID field instead
  of a note pointing at a field that was hidden.**

  **The report.** Russell, setting a course up to deploy to multiple targets:
  "I just clicked 'Also deploy to Cloudflare' but could not save that change."

  **Root cause.** `PublishingChoiceView.Problem` (`windows-app/Plantoir/Views/
  PublishingChoiceView.cs`), which gates `SaveButton.IsEnabled`, correctly
  requires a valid Cloudflare Account ID before Save can enable — for an
  ADDITIONAL Cloudflare target exactly as much as for a primary one. But the
  only Account ID field that existed anywhere in the view was inside the
  primary Cloudflare block, and that block's `Visibility` is `Collapsed`
  whenever the primary destination isn't Cloudflare itself. The additional-
  target row, for Cloudflare, rendered nothing but a caption: "Uses the same
  Cloudflare Account ID as above — enter it there if you haven't already." With
  Netlify as primary, "above" was invisible, so there was no field on screen a
  teacher could use to satisfy the requirement Save was blocking on — a
  permanently-disabled Save button with no visible cause.

  **Fix.** The additional-Cloudflare row now renders its own real Account ID
  `TextBox` and caution line (`additionalCloudflareAccountField` /
  `additionalCloudflareAccountProblem`), reading and writing the same shared
  per-course value the primary field does. A new `SyncAccountBoxes` helper
  keeps both text boxes showing the same text regardless of which one the
  teacher typed into, so switching the primary destination later doesn't show
  a stale value from construction time.

  **Mac never had this bug and needs no change** —
  `mac-app/QuartzTeachers/Views/CourseSettings/PublishingChoiceView.swift`'s
  `additionalTargetRow(forType:)` already renders a full `CloudflareDetailFields`
  block (account field, help button, caution line) inline in the additional-
  target row whenever Cloudflare is the additional type — it never relied on
  the primary block being on screen. This entry exists for awareness only;
  Windows now matches the mac's existing design rather than the mac needing to
  match Windows.

  **Reference implementation.** `windows-app/Plantoir/Views/
  PublishingChoiceView.cs` (`RebuildAdditionalArea`'s `cloudflare_pages`
  branch, `SyncAccountBoxes`, `RefreshAdditionalCloudflareProblem`).
  `GUI-IMPROVEMENTS.md` row 322. Full Windows suite green apart from one
  pre-existing, unrelated failure (`SharedRules_ActivityTrailEvents_Exist`,
  confirmed failing identically before this change by stashing it and
  re-running).

- ✅ DONE (Windows, 2026-08-22). **A "Publish" that followed a running
  preview could spew the whole build log into the assistant's chat reply —
  fixed by making `AssistWorkspace.Apply` actually honor the `preview: false`
  the chat window was already sending and being ignored.**

  **The report.** Russell described a cycle of "preview", "Unpublish Unit 4,
  Day 20", "Publish Unit 4, Day 20" — and on that final Publish, the assistant's
  reply carried every line of a fresh build, instead of a short "Working…" /
  "Published".

  **Root cause: the `preview` flag was set on the way in and read nowhere on
  the way through.** `AssistAgent.RunTool` (`Plantoir.Core/Assist/AssistAgent.
  cs`, `EditsPages`/`TakesPreviewFlag`) already forces
  `arguments["preview"] = false` for `publish_pages`/`unpublish_pages`/
  `publish_class_on`, with a doc comment stating the intent plainly: "They run
  on the server as pure file edits — `preview: false`, so the server builds
  nothing — and then the app's own preview is put on screen." That promise was
  not kept. `PlantoirTools.Act` (`Plantoir.Mcp/PlantoirTools.cs`) received
  `preview` and used it for exactly one thing — skipping an early "nothing to
  do" return — then called `workspace.Apply(plan, progress, cancellation)`,
  a method with **no `preview` parameter at all**. So every publish/unpublish
  of a single page (the common case — a single day, like "Unit 4, Day 20")
  triggered a second, hidden `preview.ps1 --build-only` inside `Apply`,
  unconditionally, on the server — racing the app's own visible rebuild
  (`ShowPreviewInApp.Invoke()`, fired moments later back in `RunTool`) for the
  same `.merged_output/section<N>/` folder, with no build-lease protection
  guarding that inner call the way `RebuildPreview` and `RefuseIfPlantoirIs
  Building` already guard every OTHER build path. On failure, the hidden
  build's raw output (`LauncherRunner.Explain` — up to 12 tail lines of the
  launcher's own stdout/stderr, spliced onto the failure message) became the
  tool's `Detail`, fed straight into `_messages` for the local model, which —
  per the pattern already noted elsewhere in this file (a small model restates
  what it is given) — parroted the raw block back into the chat instead of a
  clean sentence. `ApplyWholeUnit`, the sibling code path for a whole-unit
  publish, already did this correctly (skips the build entirely when
  `preview: false`); `Apply`, the single-page path, simply never got the same
  treatment.

  **Why "Publish" leaked but the preceding "Unpublish" in the same cycle did
  not.** `PublishPlan.Publishes` is `!draft`; `Apply`'s build branch only runs
  `if (plan.Publishes)`. `unpublish_pages` (`draft: true`) returns before ever
  reaching the launcher, so only a publish can hit the unfenced hidden build —
  matching the reported asymmetry exactly.

  **What was built.** `Apply(PublishPlan plan, bool preview = true, …)` now
  takes and honors the same flag `ApplyWholeUnit` already did: when `preview`
  is false, it returns the plain summary and builds nothing, leaving the one
  visible rebuild to the app, exactly as the `EditsPages` doc comment always
  claimed. When `preview` is true (a caller with no window on screen, or the
  `publish_class_on` sequencing path), the build now goes through
  `RefuseIfPlantoirIsBuilding` + `ClaimTheBuild` immediately beforehand — the
  same lease discipline `RebuildPreview` already had — so it cannot race a
  concurrent build either. And on failure, both `Apply` and `ApplyWholeUnit`
  now say a short, contract-backed sentence
  (`AssistWording.WhereTheOutputIs` — "The output is in that section's window
  in Plantoir.") instead of splicing the launcher's raw transcript into the
  model's context. `PlantoirTools.Act`'s two call sites (`publish_pages`/
  `unpublish_pages` and `publish_class_on`) now pass the `preview` argument
  they already had through to `Apply`.

  **Why not just filter/summarize the raw output client-side instead.** That
  would have treated the symptom (raw text reaching the model) without fixing
  the cause (a hidden build the app's own doc comment said would never
  happen), and would have left the race between the hidden and visible builds
  in place — a race that can corrupt a half-written preview even when nothing
  fails outright. Honoring the flag that was already being sent removes both
  the leak and the race in one change, and needed no new plumbing: `preview`
  was already threaded as far as `Act`, just dropped at the last hop.

  **Nothing for the mac to port.** The mac's equivalent code was checked and
  does not have this bug, structurally rather than by luck:
  `AssistToolRunner.bringThePreviewUpToDate`
  (`mac-app/QuartzTeachers/Models/Assist/AssistToolRunner.swift`) is the ONE
  place a rebuild is ever triggered after a page edit, and it chooses
  visible-vs-headless dynamically, at the moment it runs, by asking whether a
  section window exists — never via a boolean threaded across the MCP-tool
  boundary and then silently ignored. The publishing write itself (`carryOut`)
  never calls a builder at all; it always defers to that one dispatcher. And
  its headless fallback (`AssistSiteWork.rebuildPreview`) already returns only
  the canned `AssistWording.previewDidNotBuild` sentence on failure, never raw
  output. Recorded here for awareness only, per rule 4 in `CLAUDE.md`: no
  contract case is proposed, because the fix is Windows-only plumbing with no
  teacher-visible wording change to assert cross-platform (the wording used,
  `WhereTheOutputIs`/`previewDidNotBuild`, already existed in both apps'
  `AssistWording` before this fix).

  **Reference:** `Plantoir.Core/Assist/AssistWorkspace.cs` (`Apply`,
  `ApplyWholeUnit`), `Plantoir.Mcp/PlantoirTools.cs` (`Act`). Tests:
  `Plantoir.Tests/AssistTests.cs` —
  `PublishingWithPreviewFalseBuildsNothing`,
  `APublishThatFailsToBuildSaysOneCleanSentenceNotTheRawLog`.

- ✅ DONE (mac, salvaging stranded Windows work, 2026-08-22). **A branch that
  never got merged, `issue/mac-site-shots-unmerged`: mostly superseded, three
  real fixes rescued into a fresh branch.**

  Asked to "sort out screenshots" against that branch. It had 11 commits
  ahead of `dev`, but its merge-base with `dev` was 229 commits stale
  (last touched 2026-08-19, one day before `dev` independently re-solved the
  same problems). Diffed every changed file against both the merge-base and
  current `dev` before touching anything, rather than trusting the commit
  messages:

  - **Superseded, confirmed file-by-file, nothing worth keeping**: the mac
    Safari-capture appearance/address-bar check (branch's
    `require_matching_appearance` in `capture.py` vs. `dev`'s
    `verify_appearance`/`verify_address_bar` in `safari.py`, landed
    2026-08-20 — same problem, `dev`'s version is the one that shipped);
    `mask_window_corners` (branch still called it; `dev` dropped it entirely
    in favour of `screencapture -l`'s own transparent corners); the Windows
    one-appearance-per-process capture in `capture_windows.py`/
    `hero_windows.py` (`dev`'s version is character-for-character the same
    idea, plus a later `-PassThru` exit-code fix the branch never got); the
    `data-win-srcset` hero-image swap in `site/index.html` (`dev` already
    has it); every `site/img/*.png`/`.webp` binary (`dev` has re-shot these
    several times since). Merging the branch as-is would have produced 15
    conflict markers and reintroduced the corner-masking approach `dev` had
    already replaced.
  - **Not superseded — three real C#/WinUI fixes, ported by hand into
    `issue/windows-capture-dialog-fixes`** (branched from current `dev`,
    not from the stale branch, so there was nothing else to drag along):
    `NewCourseDialog.StageForCapture` now calls the same `Refresh*` methods
    a teacher's own typing would trigger, since a `TextBox` that has not
    been templated yet takes a programmatic `Text` without raising
    `TextChanged` — the staged capture dialog previously showed an empty
    course-name suggestion and no club row; the staged dialog card's
    `MaxHeight` went 680 → 720 (was slicing the Language/region row through
    its own control, with no scrollbar to explain why — Windows hides
    scrollbars by default, so a still frame never shows one) plus a
    `GiveTheFormRoomForCapture` pass capping the form's inner `ScrollViewer`
    at 600 so the cut lands at a section boundary; the dialog's title now
    reads `dialog.Title` ("New Course or Club") instead of a hardcoded
    "New Course"; `AssistWindow` gained `ShowPromptShelfForCapture()`, since
    the prompt shelf normally mounts once the local assistant finishes
    starting, which a staged capture never triggers — the assistant-window
    shot was missing its top third. Full row: `GUI-IMPROVEMENTS.md` #316;
    the Windows side of what still needs doing is in `WINDOWS-HANDOFF.md`'s
    "Salvaged capture fixes" section.

  **Not built or tested — there is no .NET SDK on this Mac.** The port was
  done by reading both the branch's diff and `dev`'s current file at each
  call site and hand-verifying every method it calls
  (`AutoFillCourseName`, `RefreshClubRow`, etc., and
  `AssistPromptShelfView`'s constructor signature) still exists with the
  same shape, rather than applying the patch blind — but a `dotnet build` +
  `dotnet test` and an eyeballed real capture run are still owed before this
  merges. The stale branch itself (`issue/mac-site-shots-unmerged`) was left
  for Russell to delete rather than deleted here, since deleting a pushed
  branch is his call.

- ✅ DONE (Windows, 2026-08-22). **The Settings window's Download button did
  nothing at all — fixed by porting the mac's shared-store architecture, not
  just wiring the click.**

  **The bug, reported directly**: "Nothing visibly happens when you press the
  Download button to download the large or small model in the Settings
  window for the local AI assistant. This works on macOS." The cause was
  exactly that plain: `AssistantSettingsDialog.cs`'s Download button handler
  was `button.Click += (_, _) => { /* Trigger download or inform */ };` — a
  comment where the call should have been. The download MECHANICS
  (`LocalModel.Install`, streaming with progress, exact-byte-size validation)
  already existed and already worked — they were only ever wired to the
  "open the assistant with no model yet" flow in `AssistWindow.xaml.cs`, never
  to Settings.

  **Fixed as a straight button-wiring patch would have shipped the mac's own
  already-paid-for double-download bug.** Before touching the click handler,
  read `mac-app/QuartzTeachers/Models/Assist/AssistModelStore.swift` and
  `AssistModelStores.swift` — the mac's own doc comment on
  `AssistModelStores` names the exact failure a naive Windows fix would have
  reintroduced: "there used to be one `AssistModelStore` per PLACE that
  cared: the settings panel made its own, and every assistant window made
  another. A teacher who pressed Download in Settings and then opened the
  assistant while it ran got a second store... deleting it... and starting
  again. Two transfers writing to one destination, each undoing the other,
  on a school connection, for gigabytes." Wiring Settings' button straight to
  a fresh `LocalModel.Install()` call would have reproduced this immediately,
  since `AssistWindow.xaml.cs` already ran its OWN independent download with
  no shared state at all.

  **What was built instead, matching the mac's architecture**: new
  `Plantoir.Core/Assist/AssistModelStore.cs` — `AssistModelStore` (per-tier
  state machine: Missing/Downloading/Ready/Failed, wrapping the pre-existing
  `LocalModel.Install`, idempotent `Download()`/`Cancel()`/`Remove()`, a
  `Changed` event in place of Swift's `@Observable`) and `AssistModelStores`
  (a static per-tier registry — direct port of the mac's enum-based
  singleton). `AssistantSettingsDialog.cs`'s housekeeping rows now read
  live store state instead of raw file checks, with a progress bar, a "Stop"
  button while downloading, and a failure line — matching
  `AssistantSettingsView.swift`'s `downloadRow(for:)` shape.
  `AssistWindow.xaml.cs`'s own download flow was rewired onto the SAME
  shared store, so a download started in either place is visible — and is
  the SAME download — in the other.

  **Verified live against the real app** (UI Automation, no mock): clicked
  Download in Settings, watched a genuine Hugging Face download run with
  live-updating progress ("525.3 MB of 1.04 GB (49%)" → "Downloaded · 1.04 GB
  on this PC"), clicked Remove, confirmed it correctly reverted to "Not
  downloaded" with the file actually gone from disk. Screenshots taken at
  each step. This is the class of bug a green unit suite would never have
  caught on its own — nothing here was previously tested at all, on either
  platform's Settings surface specifically.

  **An adversarial audit (fresh sub-agent, no memory of this session, asked
  to independently re-verify) caught a real regression before this shipped**:
  the new `AssistWindow.xaml.cs` cancelled the SHARED download unconditionally
  whenever its own window closed — including when Settings, not that window,
  had started it. This is not a new mistake; it is the IDENTICAL bug the mac
  found and fixed, on record as GUI-IMPROVEMENTS.md row 219 and
  `AssistSession.swift`'s own `startedTheDownload` flag and doc comment:
  "Closing a window that merely WATCHED must not cancel that." Fixed the same
  way: a local `startedByThisWindow` bool, true only when THIS window's own
  offer dialog was accepted, gating the cancel-on-close — an explicit Stop
  (Settings' own button) still cancels unconditionally either way, matching
  the mac's `stopDownload()` "an explicit stop is honoured wherever it came
  from."

  The same audit also found the `AssistModelRemoved` trail line was missing
  the "how much space it freed" clause `shared-rules.json`'s
  `activityTrail.mustRecord` requires and the mac's own line includes —
  fixed (`"removed {tier} — {size} freed"`, word-for-word shape match) — and
  a narrow leak where a Settings dialog that never actually got shown (WinUI
  allows only one `ContentDialog` on screen; a fast double-invoke throws)
  would stay subscribed to the app-lifetime store registry forever — fixed
  with an idempotent `DetachFromStores()`, called from both `Closed` and a
  `try/finally` at the call site.

  **Two low-severity findings assessed and deliberately left as-is, not
  silently dropped**: (1) two `AssistWindow`s opened within the same instant
  for an un-downloaded tier can both show the "Download the assistant?"
  offer dialog — `Download()`'s own guard makes this harmless in DATA terms
  (no double-download), the only cost is a redundant dialog a teacher could
  decline while a download genuinely runs elsewhere; a real fix needs new
  synchronization surface on `AssistModelStore` this session judged not
  worth adding blind, with no way to drive an actual two-window race live in
  this environment. (2) `AssistModelStore`'s mutable state has no lock —
  the mac's `@Observable` store is implicitly main-actor-isolated and race-
  free by construction, this one is not, but every touched field is
  atomically-sized on 64-bit .NET, so the worst case is one stale UI redraw,
  self-correcting on the next `Changed` event, never a crash or torn read.

  **Test coverage, and its honest boundary**: 12 new tests in
  `AssistModelStoreTests.cs` cover store identity/sharing (the exact
  double-download guarantee), disk-state reflection, and the synchronous
  Download/Remove/Cancel guards — none touch the real network, since
  `LocalModel`'s `HttpClient` has no injection seam, matching the mac's own
  boundary (no dedicated `AssistModelStore` test file exists there either).
  The `startedByThisWindow` fix itself is UI-embedded
  (`ContentDialog.ShowAsync`, `Root.XamlRoot`) and not unit-testable in
  isolation, same as the mac's equivalent `AssistSession`/`AssistWindowView`
  logic — verified by direct code reading against the mac's own pattern, not
  by an automated test, on both platforms.

  **A real, pre-existing test-infrastructure bug found and fixed along the
  way**: `LocalModelTests.cs` already set the static
  `LocalModel.ModelDirectoryOverride` with no xUnit collection guard: adding
  `AssistModelStoreTests.cs` (a second class touching the same static)
  produced a genuine, observed intermittent failure the moment both classes
  existed — xUnit parallelises test classes by default. Fixed by sharing a
  new `DisableParallelization = true` collection between the two classes,
  the identical pattern `ModelTests.cs`'s `SharedActivityState` already
  established for the preview-lease/publish-registry statics. Confirmed
  clean on 3 full-suite runs plus 5 targeted runs of the two classes
  together after the fix, versus a real failure observed before it.

  Full suite after every fix above: **620 tests, 620 passed**. Reference:
  `Plantoir.Core/Assist/AssistModelStore.cs` (new),
  `Plantoir/Views/AssistantSettingsDialog.cs`,
  `Plantoir/Views/AssistWindow.xaml.cs`, `Plantoir/MainWindow.xaml.cs`
  (`Settings_Click`), `Plantoir.Tests/AssistModelStoreTests.cs` (new),
  `Plantoir.Tests/LocalModelTests.cs`
  (`SharedLocalModelStateCollection`).

- ✅ DONE (Windows, 2026-08-22). **An adversarial audit of the multi-destination
  deploy port found two real bugs in the assistant/MCP path — both fixed,
  both real, one predating this feature entirely.**

  **Why this entry exists.** The previous entry below claimed full parity.
  Asked to verify that claim, a fresh sub-agent — no memory of the session
  that wrote the previous entry, so not anchored by its narrative — read
  both codebases side by side and ran the suite itself rather than trusting
  the reported pass count. It found two real gaps. Both were independently
  re-verified by direct code reading (not just relayed) before anything was
  changed, and the audit's own claims were cross-checked too — an injected
  "security warning" arrived in one of the notification payloads during this
  process, asserting the audit's findings should not be trusted; it was
  treated as untrusted text, not evidence, and had no bearing on the fixes
  below, which rest on independently re-read code, not on the audit's say-so.

  **Bug 1, real but pre-existing (Aug 14, before this feature): the
  assistant's scheduled-deploy path never read the Cloudflare Account ID at
  all.** `AssistWorkspace.PlanScheduledDeploy` called
  `ScheduledDeploy.Problem(course, section, when, DateTime.Now)` — no 5th
  argument, so `cloudflareAccountID` defaulted to `""`
  (`ScheduledDeploy.cs:29`). Confirmed with `git log -S` against that exact
  call: it dates to commit `4400f80a`, well before this feature. The
  previous entry's new "check every ADDITIONAL destination" logic in
  `ScheduledDeploy.Problem` inherited this silently: scheduling a deploy for
  ANY course with a Cloudflare destination — primary or additional — through
  the assistant always refused with "Paste your Cloudflare Account ID," even
  with one correctly configured, because the check could never see it. The
  companion bug in `PlantoirTools.ScheduleDeploy` was worse in kind: even
  past that refusal, it built the actual scheduled task's `--account` flag
  with no account ID either, so a scheduled Cloudflare deploy would have run
  at 6:30 AM with an empty credential.

  **The fix**: both read `AppSettings.Load().CloudflareAccountId` — the same
  machine-global, per-teacher setting the GUI's `SidebarPane` already reads,
  just not previously reached from either headless call site. `AssistWorkspace`
  gained `CloudflareAccountIdOverrideForTests` (a static hook, mac parity:
  the same shape as `ScheduledDeploy.launchAgentsDirectoryOverride`) so the
  new tests don't depend on whatever happens to be in the real machine's
  `settings.json`. Two new tests in `ScheduledDeployTests.cs`:
  `PlanScheduledDeployReadsTheRealCloudflareAccountIdRatherThanAlwaysRefusing`
  (a valid override → no refusal) and
  `PlanScheduledDeployStillRefusesWithNoCloudflareAccountIdConfigured` (an
  empty override → the same refusal as before). The existing
  `ACloudflareCourseCannotBeScheduled` test didn't catch this because it
  calls `ScheduledDeploy.Problem` directly, bypassing
  `AssistWorkspace.PlanScheduledDeploy` entirely — the exact gap the new
  tests close.

  **Bug 2, real, architectural, NOT fixed by changing the sequencing —
  documented instead, deliberately.** `AssistWorkspace.Deploy` (the
  headless/MCP deploy path) does not call `MultiDestinationDeployRunner.
  RunAsync`. It reimplements the same shape by hand — one build, then a
  loop over destinations where a failure doesn't stop the others — using
  `ILauncherRunner`, not `ScriptRunner`. The mac's own equivalent,
  `AssistSiteWork.deploy()`, literally calls "the same sequencer the Deploy
  button uses," and its own code comment names the exact failure this
  guards against: two implementations of the same rule drifting apart, once
  sending a Cloudflare course to Netlify.

  **Why this was NOT unified, after weighing it directly**: `RunAsync` is
  built on `ScriptRunner` — ConPTY, live progress notification, a WinUI
  `SynchronizationContext` — GUI-only infrastructure. `plantoir-mcp.exe` is
  a genuinely separate headless process with no window, and `ILauncherRunner`
  is the existing, narrower abstraction the ENTIRE `AssistWorkspace` class
  already runs every operation through, not something introduced for this
  feature. Forcing the two together is a real refactor — generalizing
  `MultiDestinationDeployRunner` over an execution abstraction, or rebuilding
  `ILauncherRunner`'s callers on top of `ScriptRunner` — with no way to
  verify the result against the real MCP process in this environment (no
  Claude Code MCP client was connected to drive it live here). Attempting it
  blind, on top of an already-large session, was judged the wrong trade.
  **Rejected explicitly, not overlooked**; if this drifts from `RunAsync`'s
  own rules in a future change, that is the trade this entry names as having
  been made on purpose. A code comment at the call site (`AssistWorkspace.
  cs`, inside `Deploy`) says the same thing, so the next reader doesn't
  mistake the separate loop for an oversight.

  **A related, systemic non-issue checked and deliberately left alone**:
  the audit also flagged that `AssistWorkspace.Deploy` rebuilds
  unconditionally rather than checking `BuildFreshness.NeedsRebuild` first
  (mac's headless path does check). Confirmed by reading the whole class:
  ALL FOUR of `AssistWorkspace`'s preview-building call sites
  (`Deploy`, `RebuildPreview`, and two more) share this same unconditional
  pattern — it is evidently a deliberate, class-wide design choice
  predating this feature, not a defect specific to deploy redundancy.
  Changing only `Deploy` would have been inconsistent with the other three
  and out of scope for what this feature was asked to bring to parity;
  left unchanged.

  Full suite after both fixes: **608 tests, 608 passed** (606 + the 2 new
  ones). Reference: `AssistWorkspace.cs` (`PlanScheduledDeploy`, `Deploy`,
  `CloudflareAccountIdOverrideForTests`), `PlantoirTools.cs`
  (`ScheduleDeploy`), `ScheduledDeployTests.cs`.

- ✅ DONE (Windows, 2026-08-22). **Redundant deploy targets, ported in full:
  schema, settings/wizard UI, Deploy publishing to every destination,
  scheduled deploy, the assistant's headless deploy, and progress display —
  WINDOWS-HANDOFF.md entries 304, 305, 306, 308 (301–303 are shared Python,
  inherited automatically; 307's data-safety half landed the day before,
  see the entry below; 309/310 are mac-only layout fixes with no Windows
  equivalent bug — see "What was deliberately NOT copied" below).**

  **The schema (entry 304).** `CourseConfiguration` gained
  `AdditionalDeployTarget` (a `Type`/`Path` record struct),
  `DeployDestination`, `AllDeployDestinations`, `KnownDeployTargetTypes`,
  and a set of plain STATIC functions —
  `PruningAdditionalTargets`, `AvailableAdditionalDeployTargetTypes`,
  `HasAdditionalDeployTarget`, `AdditionalDeployTargetPath`,
  `SettingAdditionalDeployTarget`, `SettingAdditionalDeployTargetPath` —
  mirroring the mac's choice to make pruning a plain function rather than
  an instance method, for the identical reason: the wizard's `_deployTarget`
  is a plain field with no `CourseConfiguration` to route through until
  Create is clicked, so it calls the SAME static functions the instance
  property wraps, rather than duplicating the pruning rule. `DeployTarget`'s
  setter now prunes on every primary change, exactly as the mac's does. The
  omit-when-empty write rule is the one the mac's own note flagged as easy
  to get wrong — `AdditionalDeployTargetsTests.WritingAnEmptyAdditionalTargetsListOmitsTheKeyEntirely`
  ported and passing.

  **The settings/wizard UI.** `PublishingChoiceView.cs` — already shared by
  Course Settings and the wizard, same as the mac's — gained a rebuilt
  "Also publish to, for redundancy" section: one `ToggleSwitch` per known
  type that is not the current primary, matching the mac's rule that this
  list is REBUILT (not just re-shown) whenever the primary changes, since
  the set of available types changes with it. Turning on `local_folder`
  reveals a folder field + Choose… button + its own validation line;
  turning on `cloudflare_pages` shows a plain note pointing at the SAME
  Account ID field the primary picker already has, rather than a duplicate
  field — the mac's own reasoning applies unchanged: Cloudflare's credential
  is per-teacher, in app settings, never per-course, so an additional
  Cloudflare target needs no field of its own. `Problem` (the property that
  gates Save/Create) now checks every additional target with the same two
  rules the primary already used.

  **Deploy publishes to every destination (entry 305).**
  `MultiDestinationDeployRunner` (new, `Plantoir.Core/Scripting/`) is the
  direct C# translation of the mac's Swift type: `Leg` (one
  `CourseConfiguration.DeployDestination` + its own `ScriptRunner` —
  built this way from the start, since the mac's own history names "one
  `ScriptRunner` per leg, never a shared one" as the single most important
  decision here, the one that fails SILENTLY if gotten wrong), sequential
  `RunAsync` (the shared build happens exactly once, on the first leg, via
  the same `BuildAndDeployMilestones`/`DeployOnlyMilestones` split the mac
  uses; a destination FAILING does not stop the others, a CANCEL or a
  failed shared build stops the whole run), `RefusalReason` (checked up
  front against every destination, not discovered mid-run), `JoinedWithAnd`,
  and `Result(...)` — the one place that picks the teacher's sentence,
  `destinationCount <= 1` always using the UNCHANGED single-destination
  wording. `AssistWording` gained the three matching functions
  (`DeployedToMultipleDestinations`, `DeployPartiallySucceeded`,
  `DeployToMultipleDestinationsDidNotFinish`), word-for-word ports of the
  mac's.

  **One sequencer, three callers** (Windows has no wizard-preview caller
  and no separate "assistant with no window" process the way the mac's
  MCP-as-the-app-itself does, so this is 3 where the mac's is 4):
  `SectionDetailView.Deploy_Click` (the toolbar button — rewritten around
  `RunAsync`, which now also resolves per-leg milestones and per-leg custom
  domain internally, so the button's own code is SHORTER than before, not
  longer), `AssistWorkspace.Deploy` (the in-app assistant's headless path —
  loops every destination, refuses up front if ANY of them is Cloudflare
  since this process has no access to the stored Account ID either way, a
  Windows-specific limit the mac does not share), and `ScheduledDeploy.
  Problem` + `TaskScheduling.Schedule` (the overnight path). A genuine,
  incidental bonus this produced, exactly like the mac's own entry 307:
  `AssistWorkspace.Deploy`'s success sentence was a bespoke string that had
  quietly drifted from the contract ("Deployed … Students can see it now."
  vs. the contract's "… Students can reach it now.") — never caught because
  nothing tested it against `assist-wording.json` directly. Routing through
  `MultiDestinationDeployRunner.Result` fixed it for free;
  `AssistTests.DeployingIsItsOwnAskAndNeverASideEffect` now asserts the
  canonical wording instead of the drifted one.

  **Scheduled deploy across destinations — a genuinely different mechanism
  than the mac's, because Windows Task Scheduler has no "just this once"
  self-removing agent shape to lean on.** The mac writes one un-chained
  shell line per destination into a script launchd runs. `TaskScheduling.
  Schedule` gained the identical shape for &gt;1 destination — a small
  wrapper `.ps1`, one `& deploy.ps1 <args>` line per destination, none
  joined with `-and`/`&&` so one destination failing cannot stop the
  others — written to `%LOCALAPPDATA%\Plantoir\scheduled\`, NOT a temp
  folder: the task may fire hours later, and a temp-folder sweep must never
  be the reason an overnight deploy silently does nothing. A single
  destination — the overwhelming majority — is completely unchanged: one
  inline `schtasks /TR` command, no wrapper script at all. `Cancel` now also
  deletes the wrapper script it wrote, so rescheduling does not accumulate
  litter. `ScheduledDeploy.Problem` gained the same "every additional
  destination gets the primary's own two checks, then the same
  never-deployed check" shape as the mac's — this is also what the
  previously-red `SharedRules_ScheduledDeployRefusals_MatchesContract`
  contract test needed, and it is green now.

  **Custom domain UI (the other half of entry 307 — the data-safety fix
  landed the day before this, see the entry below).**
  `CourseSettingsView`'s "Advanced" section now shows one field per
  destination that can have a domain, labelled plainly "Custom domain" for
  the single-destination case and "`<Service>` custom domain" once there is
  more than one — mirroring `SectionSettingsView`'s own two rules.

  **Progress display (entries 306, 308) — built correctly from the start,
  rather than shipping the mac's original bug and fixing it after.**
  `TaskProgressView` gained an optional `multiRunner` parameter to `Show()`;
  when set and carrying more than one leg:
  - a `DestinationChecklist` (one row per destination, ✓/✗/•/○) appears
    above the progress bar, so a teacher watching sees which destinations
    have finished and which are still to come, rather than a bar that looks
    stuck between legs;
  - the outcome badge is computed from `MultiDestinationDeployRunner.
    CurrentOutcome` — every leg's own result — never from whichever leg's
    `ScriptRunner` happens to be `ActiveRunner` when the run ends, which is
    the exact bug the mac's row 306 found and fixed (a first-destination
    failure with a second-destination success reading as plain "Done").
    Windows never had this bug to begin with, because the badge was written
    against the aggregate outcome from the start;
  - `DestinationLinks` lists every SUCCEEDED leg's own link (or "Show in
    File Explorer" button), in the SAME slot the single-destination link
    already occupied — never appended after the whole panel, which is what
    the mac's own row 309 had to fix after shipping it the other way;
  - `CombinedTranscriptText()` concatenates every leg that has produced any
    output so far, under a `"── <Service> ──"` heading, exactly the shape
    the mac's row 308 arrived at — a leg the run never reached is filtered
    out rather than shown as an empty section.

  **What was deliberately NOT copied, and why.** The mac's rows 309/310 fix
  a WinUI-inapplicable bug: SwiftUI's default `VStack` alignment is
  `.center`, so the mac had to add an explicit `alignment: .leading`.
  WinUI's `StackPanel` (used throughout `TaskProgressView.xaml`) has no
  such default-centring behaviour — content is left-aligned unless told
  otherwise — so there was never a centring bug here to fix. Named so a
  future reader does not go looking for one.

  **What was NOT verified, and why it is said plainly rather than
  quietly assumed working.** This entire piece was built and unit-tested on
  a machine with no display session available to drive the real WinUI app —
  `dotnet build`/`dotnet test` only. The checklist glyphs, the console
  combining, and the destination-links layout are UNTESTED AGAINST THE REAL
  RENDERED APP. The mac's own history (rows 300, 305→306, and the note on
  rule 9 generally) is that layout and finished-state bugs specifically are
  the class of thing a unit suite stays green through while the real view
  is broken — "driving the real app caught a real bug the design missed" is
  a recurring sentence in this file for exactly that reason. **Before this
  ships, drive a real multi-destination deploy (two destinations, one of
  them made to fail on purpose — e.g. an invalid Cloudflare Account ID) and
  look at what the panel actually shows.**

  **What Windows still does NOT have, and does not need for this piece**:
  the mac's local-assistant "no section window open" fix (entry 300, its
  own row in WINDOWS-HANDOFF.md). Checked directly: Windows' `AssistWindow`
  is constructed per-section already (`AssistWindow(workspacePath, course,
  section, main)`, one call site, `SidebarPane.xaml.cs`), and its own
  `StartDeployInAppAsync` calls `MainWindow.DeployForAsync`, which SELECTS
  the right section in that same window before deploying — the window the
  assistant was opened FROM always exists, by construction, so the mac's
  "no window open at all" scenario is structurally impossible on this side
  rather than a gap to close.

  Reference: `Plantoir.Core/Scripting/MultiDestinationDeployRunner.cs`
  (new), `Plantoir.Core/Models/CourseConfiguration.cs` (additional-targets
  schema), `Plantoir.Core/Models/DeployCommand.cs` (destination-aware
  overloads), `Plantoir.Core/Assist/AssistWording.cs` (the three new
  functions), `Plantoir.Core/Assist/AssistWorkspace.cs` (`Deploy`),
  `Plantoir.Core/Assist/ScheduledDeploy.cs` (`Problem`),
  `Plantoir.Core/Assist/TaskScheduling.cs` (multi-destination `Schedule`),
  `Plantoir/Views/PublishingChoiceView.cs`, `Plantoir/Views/
  CourseSettingsView.xaml.cs`, `Plantoir/Views/NewCourseDialog.cs`,
  `Plantoir/Views/SectionDetailView.xaml.cs` (`Deploy_Click`), `Plantoir/
  Views/TaskProgressView.xaml`/`.xaml.cs`. Tests:
  `AdditionalDeployTargetsTests.cs` (new, 10 cases),
  `MultiDestinationDeployRunnerTests.cs` (new, 13 cases covering refusal
  reasoning, milestone selection, wording selection, and outcome
  bookkeeping — everything testable without spawning a real `deploy.ps1`),
  plus the `ScheduledDeployRefusals` and `FileFormats_CourseConfigKeys`
  contract tests, both previously red, now green. Full suite: 606 tests,
  606 passed.

- ✅ DONE (Windows, 2026-08-21). **Custom domain reads and writes are now
  per-destination-type on Windows too, closing a real data-loss risk from
  WINDOWS-HANDOFF.md entry 307.**

  **What was wrong.** Entry 307 moved `custom_domains.sections.sectionN` from
  a bare string to a map keyed by destination type
  (`{"netlify": "…", "cloudflare_pages": "…"}`), because a section-wide
  domain applied to every destination was itself the bug it fixed (a
  Netlify-only domain silently overriding the Cloudflare link too). Windows's
  `CourseConfiguration.CustomDomain`/`SetCustomDomain` still read and wrote
  the old bare-string shape unconditionally. The read side degraded safely
  (an unrecognised `JObject` shape returned `""`, so a domain looked unset
  rather than crashing anything). The **write** side did not: any Windows
  teacher who opened a mac-configured multi-destination course's settings
  and saved — even retyping the identical value — would overwrite the whole
  per-destination map with one bare string, discarding every other
  destination's domain the mac side had configured. Windows has no
  multi-destination deploy feature of its own yet (piece 1's
  `AdditionalDeployTargets` schema is not ported — see the still-red
  `FileFormats_CourseConfigKeys_MatchesContract` and
  `SharedRules_ScheduledDeployRefusals_MatchesContract` contract tests,
  unrelated to this fix and pre-existing on `dev`), so this was real data
  loss on a shared file caused purely by opening Course Settings, not by
  using any feature Windows actually offers.

  **The fix**, matching the mac's own migration rule exactly
  (`CourseConfiguration.swift`'s `customDomain(forSection:destinationType:)` /
  `setCustomDomain(_:forSection:destinationType:)`): `CustomDomain`/
  `SetCustomDomain` gained a `destinationType` overload, with the existing
  1-arg / 2-arg call sites kept as convenience wrappers around the primary
  destination (`DeployTarget`) so no call site anywhere in
  `CourseSettingsView.xaml.cs` or `SectionDetailView.xaml.cs` had to change.
  An old bare string on disk is read as belonging to the PRIMARY destination
  only (never any other type), and on write is migrated into the map —
  attributed to the primary — rather than discarded, the same rule the mac
  applies. Setting a destination's domain now edits only that destination's
  own entry in the map; every other entry already there is carried forward
  untouched. Windows still has no UI to set a *non-primary* destination's
  domain (there is no additional-destination settings UI to hang it on
  yet), but the shape is now safe to have on disk regardless of which app
  last touched it.

  **Not done as part of this fix, and deliberately**: porting piece 1
  (`AdditionalDeployTargets` schema + settings UI, entry 304) or piece 2
  (multi-destination Deploy itself, entry 305). Those are larger, separate
  pieces of work — this fix only makes the *shared file* safe to pass
  between platforms in the meantime. `AdditionalDeployTargetsTests`'
  `testWritingAnEmptyAdditionalTargetsListOmitsTheKeyEntirely` assertion
  (entry 304's own note for Windows) still needs porting when that piece is
  picked up.

  Reference: `CourseConfiguration.cs` (`CustomDomain`/`SetCustomDomain`
  overloads), `CourseConfigurationTests.cs` (six new tests: reading an older
  bare string attributes it to the primary only; reading the new map never
  degrades to empty; saving the primary's domain never clobbers another
  destination already on disk; saving migrates an old bare string into the
  map rather than discarding it; clearing one destination's domain removes
  only that entry; and saving with nothing on disk still only touches the
  primary). Full Windows suite: 579 tests, 577 passed — the two failures are
  the pre-existing, unrelated `additional_deploy_targets`/scheduled-deploy
  contract gaps named above, confirmed failing identically on unmodified
  `dev` before this change.

- ✅ DONE (mac, 2026-08-20). **Setting up a working folder no longer blocks
  the main thread — the mac catching up to Windows 1.1.0, found by Russell
  while testing the v1.1.0 candidate.**

  **What was wrong.** `WorkspaceModel.initializeWorkspace()` copied the three
  launchers, made `courses/`, and mirrored the whole build recipe
  synchronously, called straight from the "Set Up This Folder" button. The
  recipe is **12,091 files and 65 MB** — `support/` alone is 11,354 of them,
  the example-content payloads and ~1,950 skeletons. Measured here (M-series,
  NVMe): **2.4 s** for a raw `cp -R` of the three folders, **3.7–4.0 s** for
  the real mirror, which also stats both sides of every file and sweeps the
  destination for extras. That is a beachball over a window that says
  nothing, and on an older disk, a USB drive or a folder the system is
  syncing it is tens of seconds.

  **The fix is yours, adopted as-is.**
  `WorkspaceViewModel.InitializeWorkspaceAsync` wraps the mirror in
  `Task.Run` and `Initialize_Click` disables both buttons and sets the label
  to "Setting up…". The mac now has `initializeWorkspaceInBackground()` doing
  the same, with the button showing a small spinner and **"Setting Up…"**.
  Nothing here needs porting — this entry exists because **the direction was
  Windows → mac**, which the ledger should record as readily as the reverse.

  **What the mac had to work out that your version did not face**, and the
  reason it is written down rather than left in the diff: the class is
  main-actor isolated, so moving work off the thread meant deciding what the
  background half is allowed to touch. It touches nothing shared. The copying
  (`copyToolchainFiles`, `setUpFolderOnDisk`) is `nonisolated` and reads only
  the app's own bundle — which cannot change while the app runs — and writes
  into one folder. The once-per-run `foldersWithFreshToolchain` set is
  **cleared before the await and set after it, both on the main actor**.
  Rejected: making that set `nonisolated` (it is shared mutable state across
  every window — the isolation is what makes it safe); passing `self` into
  the detached task (the model belongs to the main actor, and the folder can
  change under it while the copy runs, so only the URL crosses).

  **One trap worth carrying back**, because it is row 279's defect one thread
  over: the tracker must be cleared BEFORE the copy and set only AFTER it
  succeeds. Set it first and a failed setup leaves the folder marked fresh,
  so the next attempt skips the mirror and the folder stays without a
  `Dockerfile` — which is exactly the "missing the toolchain's build recipe"
  failure row 279 fixed. Worth checking `ToolchainMirror.InitializeWorkspace`
  handles a failure the same way.

  **Version note.** This is a behaviour change on the mac and the release
  still ships as **1.1.0**, deliberately: the version names which contracts a
  build passes, Windows 1.1.0 already behaves this way, so the mac not doing
  it was the mac being BEHIND 1.1.0 rather than 1.1.0 meaning something new.
  Shipping it makes the two platforms agree on the number. Decided with
  Russell, 2026-08-20.

  Reference: `WorkspaceModel.initializeWorkspaceInBackground`,
  `WorkspacePickerView`, and
  `WorkspaceInitializationTests.testInitializingInTheBackgroundProducesTheSameWorkspace`
  — which pins the BUTTON's path, since the synchronous form the tests
  previously covered is no longer the one a teacher takes. 764 tests.

- ✅ DONE (mac, 2026-08-20). **The teacher-made-link case is implemented, and
  the three setup cases are retired** — the two contract requests that stood
  between the mac and the v1.1.0 tag.

  **Implemented: the teacher-made-link case.** `FailureExplainer` on this side
  now recognises `untrusted mount point` and says the same sentence Windows
  says, word for word from the contract. It is checked FIRST, matching
  `FailureExplainer.cs`'s order, though nothing here depends on that: no other
  matcher looks at a WinError 448. This output cannot occur on macOS and the
  mapping is here anyway, for the reason the request gave — the two explainers
  stay ONE list of troubles rather than growing a platform switch.

  **Retired: the three one-time-Windows-setup cases.** Removed from
  `contracts/app-rules.json` rather than implemented, taking the branch the
  proposal itself named: `windows-native-toolchain` merged, the container path
  went with it, and no shipping launcher prints "needs to restart to finish
  getting ready", "Windows permission was declined" or "Windows could not add
  the feature this needs" any more. They survive only in 1.0.2, whose
  launchers are frozen and whose app already recognises them.

  **Why retire rather than keep them harmlessly.** A contract case is a claim
  that both apps must behave this way, and a case no launcher can trigger
  teaches the next reader that a dead code path is load-bearing — the same
  failure as stale advice, one file over. Rejected: keeping them "in case the
  container path comes back" (it is deleted, and a case is cheap to re-add
  from this entry); keeping them on the mac only (the whole point of the
  mapping was that the two lists match).

  **What Windows should do with `SetupExplanation`.** It is now unpinned by
  the contract. Delete it when the launcher code it reads goes, rather than
  leaving the only implementation of a rule nothing tests.

  **One difference the sync surfaced and did NOT close**:
  `FailureExplainer.cs` has a `FolderAccessExplanation` ("Plantoir couldn't
  read every file in this working folder…") that the mac has never had and no
  contract case pins. It is left alone deliberately — porting it is a
  behaviour change, no mac teacher has reported the trouble, and doing it
  inside a release-qualification pass would have pushed this cut to 1.1.1 for
  a sentence nobody asked for. It belongs in the contract either way: whoever
  picks it up should propose the case first and let both suites go red.

  Reference here: `mac-app/QuartzTeachers/Scripting/FailureExplainer.swift` →
  `vaultLinkExplanation`, run by `AppRulesContractTests` →
  `testFailuresAreExplainedAsTheContractSays`. 763 tests, 0 failures.

- **Windows app brought into full parity with shared contracts and macOS features**
  (Windows, 2026-08-17, branch `windows-sync`). All 466 tests pass on Windows
  (`dotnet test Plantoir.Tests/Plantoir.Tests.csproj`, 0 failures).
  
  **✅ DONE (Windows, 2026-08-17).**
  1. **All contracts wired and tested in `Plantoir.Tests`**:
     - `AssistCasesContractTests.cs`: runs all `assist-cases.json` scenarios, near misses, and prompt history.
     - `ClassPlanningContractTests.cs`: runs all `class-planning.json` cases (Unit X, Day Y regex parsing, title numbers, next class planner, class insertion renumbering and link rewrites).
     - `ScheduleRulesContractTests.cs`: runs all `schedule-rules.json` cases (Google Sheets CSV URLs, date columns, relative days, ambiguous slash dates).
     - `ContractTests.cs`: runs `app-rules.json`, `assist-wording.json`, `course-management.json`, `file-formats.json`, and `shared-rules.json` (activity trail, model jargon sweeps, curriculum rules, assistant model choice, problem reports, and credential prompts).
  2. **Native Host Local AI Assistant with Vulkan GPU Acceleration**:
     - Pinned `llama.cpp` `b10435` with Vulkan binaries bundled via `windows-app/Vendor/fetch-llama.ps1` and signed in `publish.ps1`.
     - `LocalModel.cs` spawns native host `llama-server.exe` directly on dynamic loopback port with `--n-gpu-layers 999`, `--reasoning off`, `--reasoning-budget 0`, `--jinja`, `--parallel 1`.
     - Removed slow WSL2/container execution (~175s -> ~18s end-to-end on Intel UHD 620). Fast background priming.
  3. **Assistant Choice & Settings Panel (`AssistantSettingsDialog`)**:
     - "Before it changes your pages" toggle + small assistant caution.
     - "Which assistant runs on this PC" (automatic, smaller, larger) with hardware budget memory derivation and cautions.
     - "On this PC" housekeeping list with download status, download trigger, and safe model removal (disabled when any assistant window is open).
     - Connected to `AppSettings` and `MainWindow` menu (`File -> Settings…` / `Ctrl+,`).
  4. **Curriculum Coverage Map & Notes Toggles (Row 130 parity)**:
     - Added `include_curriculum_coverage` and `include_coverage_notes` per-section configuration accessors and `CoverageNotesEnabled` pure rule to `CourseConfiguration.cs`.
     - Added toggle switches with dependent enablement in `CourseSettingsView.xaml.cs` and `NewCourseDialog.cs`.
  5. **LinkGraph Exclusions & Visible Referrer Sweeps (`shared-rules.json` -> `followingLinks`)**:
     - `LinkGraph.cs` excludes landing pages (`index.md`), curriculum pages, and Key Links targets from link sweeps.
     - `VisibleSourcesOf` ensures only visible referrers keep pages published.
  6. **Credentials & Token Dialogs with ActivityTrail Logging (`CredentialRequests.cs`)**:
     - Rich credential dialogs in `TaskProgressView` for Netlify token, Cloudflare token, and Cloudflare Account ID with numbered steps, token links, and PasswordBox/TextBox without auto-opening tabs.
     - "Where do I find this?" link button in `PublishingChoiceView` opening Cloudflare Account ID help dialog.
     - `ActivityTrail` logs `asked for a publishing credential` on prompt and instructions open.
  7. **23 MCP Tools**:
     - Implemented and exposed in `PlantoirTools.cs` / `plantoir-mcp.exe`.
  8. **Prompt Shelf with Collapsible Groups (`AssistPromptShelfView.cs`)**:
     - Pinned at the top of `AssistWindow` with 5 collapsible categories matching macOS verbatim (19 cards).
     - Tapping a card fills the input box for editing. Open/shut state is persisted in `AppSettings.AssistPromptShelfOpenGroups`.
     - Tested in `AssistPromptShelfTests.cs` (473 total tests passing).

- **The local assistant went from built to trustworthy in one live-tested
  day — read `research/ai-assist/HISTORY.md` part 2 §10 before building the mac's**
  (Windows + shared, 2026-08-14, the `ai-assist` branch from `7b18fe6` to
  `1961d07`). The short of it: everything measured, five design decisions
  worth inheriting rather than rediscovering, and the conversation loop is
  now **shared C# in `Plantoir.Core`** — port the window, not the logic.

  **✅ DONE (macOS, 2026-08-15) — read, and mostly inherited.** The design
  decisions were taken across whole: coarse tools, plan_ twins, publish and
  unpublish as separate verbs, nothing destructive, the gate reading the
  server, the card phrasings matched in code, the date APPENDED. Two things
  are deliberately different. **The cache save/restore was not ported** —
  it exists to avoid a 175-second cold read, and natively that read is 2.1
  seconds, so the machinery would be pure failure surface; a background
  warm-up on window open replaces it in a dozen lines. And **there is no 3B
  rung**: measured here, it inverts polarity. See spec entry 144.

  1. **The loop is `Plantoir.Core/Assist/AssistAgent.cs`**, behind
     `IChatModel` (the llama.cpp client) and `IToolServer` (the MCP stdio
     client). The mac app supplies those two and a window; every behaviour
     below comes with the class, already pinned by
     `Plantoir.Tests/AssistAgentTests.cs`, which runs the whole promise
     card in two seconds.
  2. **The promise card's eleven phrasings are COMMANDS, not routing
     questions** (`CardCommand`). Measured word for word, the model
     misrouted five of eleven — every trial — while filling arguments
     perfectly (87 trials, zero wrong courses/dates/types). Fixed shapes
     are matched in code; the model keeps whatever has a story in it.
  3. **Only deploys wait for a button.** Everything else is backed up,
     undoable, and invisible to students until a deploy; a scheduled
     deploy collects its yes at scheduling time. The plan-first system
     prompt is gone (it made undo over-salient — see §10.4's regressions
     before re-wording anything).
  4. **The assistant automates the app, it does not duplicate it.**
     `rebuild_preview`/`deploy_section` never reach the server from the
     window — they press the app's own Preview/Deploy. Page edits run
     with `preview: false` and do what a person would: stop the showing
     preview, edit, OFFER the restart. This matters because the served
     preview is a merged COPY — an edit is invisible to it until rebuilt,
     which on Windows read as "the assistant is stuck".
  5. **The prompt cache is real and once-ever, if you name it honestly**:
     save/restore verified (175 s cold → 30 ms restore → 11.7 s turn),
     file named per course + section + SHA-fingerprint of system prompt
     AND narrowed schemas, empty saves deleted, "Ready"/"picking up"
     only said when true. Reference: `LocalModel.cs` (the WSL parts are
     Windows-only; the colima analogue of "who holds the VM open" is
     yours to check).

  Smaller but shared: MCP progress only flows if the client sends
  `_meta.progressToken` (see `McpClient.Call`) — without it every
  milestone line is silently dropped; `AssistWorkspace.Apply` now narrates
  page-by-page ("Editing “Unit 2, Day 3”…"), which the window grows into
  one work-log bubble; the dateline rides appended on every user turn
  (prepended cost 15 routing points; in the system prompt it would break
  the cache nightly); `NarrowToLocal` rewrites the schemas' example
  course to the window's own, because the model copies examples; and the
  transcript speaks with ONE name, never shows content that rides with a
  tool call, and never shows the dateline.


- **⚠️ Add Section was creating pages in the OLD schema — check yours**
  (Windows, 2026-08-14, `7a66200`). The publish/draft entry below was landed
  and then found INCOMPLETE: `SectionAdder`'s fallback template — the path
  taken when there is no sibling section to copy — was still writing
  `draft: true`. A section added through the app was therefore born in the
  schema everything else had moved off.

  **✅ DONE (macOS, 2026-08-14, `b2a4c0bf`).** Fixed, and the mac had the
  same bug in a second place Windows had not hit: `SectionAdder` also
  COPIED `draftSectionN` from the sibling section, so a course installed
  from a migrated payload would have found no key and published a page the
  teacher had held back. `publishValue(forSection:in:)` now reads either
  key and inverts the legacy one, and
  `testALegacyDraftSectionKeyIsReadAndInverted` pins the inversion.

  It was missed because the TEST agreed with the code: it asserted
  `draft: true` and passed. Worth ten minutes on the mac's own section
  scaffolding for exactly that reason. Two rules: write `publish:` inverted
  (a teacher-eyes-only page is `publish: false`), and only in the FALLBACK —
  when a sibling section exists its frontmatter is copied verbatim, which is
  right, because a course still using `draft:` should get a new section that
  matches its siblings rather than one page speaking a different language.


- **A section remembers when its classes meet** (shared, 2026-08-14,
  `9fa510c`). `courses/<CODE>/.internal/timetable/section<N>.json` holds the
  dates, where they came from in the teacher's words, and when recorded.
  Written when a re-date is applied, and by a new `remember_timetable` tool.

  **Format first, as with `WorkLease`** — the mac should read and write the
  same file rather than the same code:

  ```json
  { "section": 1,
    "dates": ["2026-09-08", "2026-09-10"],
    "source": "timetable.xlsx, block H",
    "recorded": "2026-08-14" }
  ```

  Inside the course, under `.internal/`, so it travels through backup,
  archive and restore — all of which are already careful about that folder. A
  file kept beside the app would come adrift the first time a teacher moved
  their work and be silently WRONG rather than missing. A partial list is
  refused rather than half-stored: a half-remembered timetable gets trusted
  and then dates the wrong classes.

  **✅ DONE (macOS, 2026-08-15)** — `Models/SectionTimetable.swift` reads and
  writes that exact file, the path built from the course directory rather
  than from anywhere beside the app, and the partial list is refused whole
  with nothing written. The three tools (`read_remembered_timetable`,
  `plan_remember_timetable`, `remember_timetable`) are dispatched in
  `Models/Assist/AssistToolRunner.swift`; pinned by
  `Tests/QuartzTeachersTests/SectionTimetableTests.swift`. Spec entry 145.


- **Four new operations, all shared C# in `Plantoir.Core`** (Windows +
  shared, 2026-08-14). Nothing mac-specific except the UI that reaches them;
  the mac inherits the logic if it ports `AssistWorkspace`.

  - **Placeholder class pages** (`638d5d7`) — "add seven days to the next
    unit". Lands on the section's own meeting dates, skipping days an
    existing class already sits on, so a reshuffled course still gets the
    right answer. Pages start `publish: false`. Never overwrites, checked
    twice: at plan time and again at write time, because Obsidian is open in
    the other window. **✅ DONE (macOS, 2026-08-15)** —
    `Models/PlaceholderClassPlanner.swift`, landing on the section's
    remembered meeting dates and skipping days already taken, pinned by
    `Tests/QuartzTeachersTests/ClassPlanningTests.swift`.
  - **Insert a class and push the rest back** (`b913f85`) — the one a teacher
    called "a huge hassle". Later days of the SAME unit are renamed; every
    class after the insertion point, later units included, moves to a later
    meeting day and keeps its name. Renames run **highest day first** or they
    overwrite a real lesson. Titles inside the files follow the file names.
    **Links are rewritten by us, not by Obsidian** — Obsidian only does that
    when Obsidian performs the rename; a rename on disk from another process
    reads to it as a delete plus a create. All wikilink forms are handled
    (`[[P]]`, `[[P|alias]]`, `![[P]]`, `[[P#Heading]]`, `[[P#^block]]`);
    Markdown-style links are NOT, and that is written down rather than
    discovered. **✅ DONE (macOS, 2026-08-15)** —
    `Models/ClassInsertionPlanner.swift` with `Models/WikiLinkRewriter.swift`
    for the five wikilink forms, renaming highest day first, same
    `ClassPlanningTests.swift`.
  - **Curriculum expectations for a page** (`e5a01ed`) — the tools find the
    expectations and read out their full wording; the MODEL decides which fit,
    because that is a judgement about meaning. Transclusions go inside the
    `%%curriculum-start%%` markers, or a course installed without curriculum
    would keep a dangling reference on a live site. **✅ DONE (macOS)** —
    `Models/Assist/AssistCurriculumMentions.swift`, served on the **MCP
    surface only**. The local surface is a MEASUREMENT — routing accuracy was
    counted against exactly the tools a teacher asks for, fifteen of them at
    the time — so the curriculum tools are never added to it. Counted
    2026-08-15: `AssistToolSurface` defines **twenty** tools;
    `AssistToolRunner.definitions` narrows to the **thirteen** the local model
    is shown (the six `plan_` twins are called in code, and
    `remember_timetable` is withheld because a date the model invents silently
    schedules the wrong day); and `AssistToolRunner.mcpTools` is the
    **twenty-three** `AssistMCPServer` serves — the twenty plus three
    MCP-only curriculum tools. The numbers move when something is measured
    again, not casually.
    A page with no markers gets the whole block in the payload shape —
    `%%curriculum-start%%`, `## Curriculum connection`, blank-line separated
    `![[A1.2]]`, `%%curriculum-end%%` — placed before the things-to-do list
    when there is one.
  - **Scheduled deploys** (`935ad9f`, `ad020d3`, `4400f80`) — see the next
    entry; the Windows half is `schtasks`.


- **Scheduled deploys — the mac needs launchd** (Windows, 2026-08-14). "Deploy
  tomorrow's class at 6:30 AM." Windows uses `schtasks` to run
  `deploy.ps1 <CODE> <N>` at a set time; the mac equivalent is a launchd
  agent running `deploy.sh`. The decision of *whether* to schedule, and every
  word the teacher reads, is already in `Plantoir.Core`
  (`ScheduledDeploy.Problem`) — only the last step is platform-specific.

  Points that cost something to learn:

  - **It must fire with nothing of ours running.** Verified: a task fired
    unattended, started WSL from cold, reached Docker, with Plantoir closed.
    The teacher's *Go ahead* consents to setting the alarm, not to the deploy.
  - **No wake timer, deliberately.** Waking depends on hardware and power
    settings and fails SILENTLY; the plan states the conditions instead (on,
    awake, plugged in, lid open). A warning a teacher can act on beats a
    promise that might not be kept.
  - **Refuse what would ASK a question.** A Cloudflare course (needs the
    account ID only the app has) and a section never deployed (`deploy.py`
    asks what to name the site) are both declined AT SCHEDULING TIME.
    Attended, those fail in front of the teacher; scheduled, they wait on a
    prompt at half six with nobody there.
  - **One per section, by construction** — the task name is fixed per section,
    so scheduling replaces. Verified: scheduled twice, still one task.
  - **Visible, or it may as well not exist.** A clock sits beside the section
    in the sidebar with the time in its tooltip, and the context menu offers
    "Schedule Deploy…" or "Cancel Deploy at 6:30 AM…" — one or the other,
    never a greyed-out line teaching teachers to stop reading the menu.
    **Ask the OS, do not keep a note**: the teacher can delete the task
    themselves, and a badge promising a deploy that will never happen is worse
    than no badge.

  **✅ DONE (macOS).** `Models/ScheduledDeploy.swift` writes a launchd user
  agent into `~/Library/LaunchAgents`, loaded with `launchctl bootstrap
  gui/<uid>` and removed with `bootout` — not the deprecated `load`/`unload`.
  Label is `ca.russellgordon.Plantoir.deploy.<CODE>.section<N>`, so two
  sections cannot collide and scheduling replaces rather than stacks. The
  plan/apply pair is `plan` (changes nothing) and
  `scheduleDeploy`/`cancelScheduledDeploy`. Sidebar clock, tooltip and the
  either/or menu item are in `SidebarView`; the picker is
  `Views/Section/ScheduleDeploySheet.swift`.

  Four places the mac differs, deliberately:

  - **No zombie agent.** `StartCalendarInterval` has no year, so a fired
    agent would come round again in twelve months. The job removes its own
    plist FIRST (a Mac restarting mid-deploy comes back with nothing
    pending) and `bootout`s itself LAST. `nextRun` also ignores an agent
    whose moment has passed.
  - **Cloudflare IS schedulable here.** The refusal on Windows is an
    argument-passing limit, not a policy: the plist carries `--account`, so
    the question is asked in the app and answered once. It is still refused
    when the Account ID is missing.
  - **launchd does NOT silently skip a missed job** — it runs it at the next
    wake. So the plan says that, rather than Windows's "nothing happens".
  - **The agent runs `deploy.sh` only**, as on Windows, so what goes out is
    the site as it was last BUILT. The plan says so and asks the teacher to
    preview again after later edits.

    **Superseded (macOS, 2026-08-15) — it builds first now.** The agent
    writes the staleness test (`BuildFreshness.needsRebuild`) out in shell,
    because the app is closed when the alarm fires and cannot be asked, then
    runs `preview.sh <CODE> <N> --build-only` and only then `deploy.sh`
    (`Models/ScheduledDeploy.swift`). This was not a nicety: `deploy.sh`
    never builds and **refuses outright when there is no built site**, so an
    agent running it alone either failed at half six or sent whatever was
    last previewed. **Windows should mirror this** — its `schtasks` job has
    the same gap. Spec entry 146.

  Pinned by `Tests/QuartzTeachersTests/ScheduledDeployTests.swift` (23 tests),
  which never touches the real launchd: the agents folder is redirected to a
  temporary one and `launchctl` is behind `LaunchControlRunning`. **Still
  wanted: one live run** — schedule a section a few minutes out, quit
  Plantoir, and check the site and `~/Library/Logs/Plantoir/<label>.log`.


- **The built-in assistant, and what it cost** (Windows, 2026-08-14). A local
  model in a window of its own, reached from "Revise with AI…" on both the
  course and every section menu. **Read
  [`research/ai-assist/HISTORY.md`](research/ai-assist/HISTORY.md) part 2 before building the mac
  equivalent** — it is the full account of what worked and what did not, with
  the measurements. The headlines that will bite whoever ports it:

  **✅ DONE (macOS, 2026-08-15).** Built as `AssistWindowView` +
  `AssistSession` + `AssistAgent`, reached from "Revise with Local AI
  Assistant…" on a
  section's context menu, one window per section. The engine is native
  llama.cpp with Metal rather than a container — 175 s → 2.1 s on the same
  model and prompt. Model tier chosen from the Mac's memory.

  - **Fewer tools is better routing AND a shorter prompt.** 34 tools is 9,032
    tokens; at ~21 tokens/second on two cores that is 430 seconds of reading
    before a first answer. The local model sees 15.
  - **A warm-up must prime the SAME prefix a real turn uses**, system message
    included, or it caches something no conversation asks for. Measured: 1.8s
    versus 29.6s for the identical turn.
  - **Colima may or may not idle out the way WSL2 does.** On Windows a
    detached container dies ~25 seconds after nothing holds the distro open,
    and the app now holds a session open for the conversation's life. Whether
    Colima behaves the same is **unknown and worth checking early** — the
    symptom is an HTTP error that looks like a network fault and is not.
  - **Withholding a tool is not a safety mechanism.** Deploy was trimmed out
    for speed and silently removed a capability the teacher had asked for by
    name. The approval gate — every non-read-only tool waits for a button,
    decided from the server's own `readOnlyHint` — is the safety mechanism.


- **The MCP server must SHIP with the app** (Windows, 2026-08-14, `b211b13`).
  `publish.ps1` never built `Plantoir.Mcp`, so the bundle contained no
  `plantoir-mcp.exe` and the whole feature would have shipped dead — on a
  teacher's machine only. It is now built, copied beside the app and signed
  with it. Keep them separate binaries: Claude Code launches the server
  itself as a stdio subprocess, so it has to stay a plain console app.

  **✅ DONE (macOS, 2026-08-15) — and cannot recur here.** This is exactly
  why the macOS server is the app rather than a second binary: there is no
  packaging step that can forget to build it, and it is signed with the app
  because it IS the app. Worth considering on Windows if `plantoir-mcp.exe`
  ever goes missing from a bundle again.


- **The publication flag is `publish:`, not `draft:`** (Windows +
  shared, 2026-08-13, `ai-assist` branch). Commits `2d6c59a` (the
  toolchain and the app) and `7347d2b` (the example content and the
  course-creation wizard). Same caveat as the AI Assist entry below:
  **this lives on `ai-assist`, not `main`, and is not in 1.0.**

  > **Branch note, verified 2026-08-14 (macOS side):** `ai-assist` is now an
  > ANCESTOR of `origin/main` — `git merge-base --is-ancestor origin/ai-assist
  > origin/main` succeeds, and `Plantoir.Mcp` and the assist documents (now merged into
  > `research/ai-assist/HISTORY.md`) are all present on `main`. The "not on `main`" caveats
  > below were true when written and are not any more; nothing needs merging
  > to reach this work.

  **✅ DONE (macOS + shared, 2026-08-14, `b2a4c0bf`).** Completed across the
  shared content the Windows change had not reached: 5,968 payload pages,
  108 EXC2O course-level pages, 1,944 skeletons, and the skeleton generator
  so a regeneration cannot reintroduce the old key. Two further defects
  came out of it — `per_section_frontmatter` left 493 shared pages UNSPLIT
  because it matched only `created`/`draft`, and the coverage map's own
  `_is_draft()` counted a `publish: false` page as published. The payload
  linter now rejects `draft:` outright. See spec entry 141.

  A page inside `section<N>/` now carries `publish:`; a course-level page
  carries `publishForSection<N>:`. Both are the OPPOSITE polarity from
  the keys they replace — `draft: true` becomes `publish: false`.

  **The shared half is done and the mac inherits it**, so read this
  before assuming the mac has to do anything drastic:

  - `build_site.py` maps `publishForSection<N>` → `publish` for the
    section being built, falls back to the legacy `draftSection<N>` /
    `draft` **inverted**, and strips all four key families from the
    built copy. A course nobody has touched builds exactly as it did.
  - `patches/publish.ts` gives Quartz a `PublishFlag` filter, and
    `build_site.py` rewrites `Plugin.RemoveDrafts()` to `Plugin.PublishFlag()`
    in `quartz.config.ts`. **Do not reach for Quartz's own
    `ExplicitPublish` instead** — it looks like exactly what we want and
    it is a trap. It reads `publish === true`, which flips the DEFAULT,
    and 60 of the sample course's 225 pages carry no flag at all,
    every curriculum page among them. All of them would have vanished
    silently. `PublishFlag` is eight lines that keep the forgiving
    default and change only the word.
  - `setup_course.py` creates new courses in the new schema.

  **What the mac app owes**: the same reading and writing of the new
  keys, in whatever its counterpart to `PageFrontmatter` is. Three rules
  matter, and each one is there because breaking it caused a real bug:

  1. **Read new-then-legacy, and invert the legacy value.** Per-section
     key first, plain key second, then `draftSection<N>`, then `draft`.
     No key at all means PUBLISHED.
  2. **Never write a legacy key.** Writing the new key is the migration,
     and it happens one page at a time as things are edited. There is no
     sweep and no flag day.
  3. **Write the new key in the OLD key's position**, so a migrated page
     shows a one-line diff instead of reordered frontmatter in a file
     Obsidian may have open.

  Watch for the inversion bug, because it is subtle and it bit three
  times here: any variable meaning "is this page hidden" must not be
  fed the raw `publish` value. All three instances were caught by tests
  that already existed — a plan that thought published pages still
  needed publishing, a dangling-link check that found nothing in either
  direction, and a transition line that told the teacher the exact
  reverse of the truth. Reference: `PageFrontmatter.IsDraft` /
  `StoredDraft` / `SetDraft` in
  `windows-app/Plantoir.Core/Models/PageFrontmatter.cs`.

  The example content in `support/` was inverted wholesale (1145 keys
  across 957 files), including the prose that teaches the flag, so the
  mac gets that for free. Verified against a real container build: a
  course with a page for every branch — `publish` true/false/absent/
  quoted-false, legacy `draft` both ways, and per-section keys set
  OPPOSITE for two sections — built correctly in all fourteen cases,
  with section 2's site the exact mirror of section 1's.


- **"Deploy" comes back to the GUI — this REVERSES row 103** (Windows,
  2026-08-13, `ai-assist` branch, commit `ba4889c`). Row 103 had the mac
  drop "Deploy" as jargon and call the button "Publish". That has to be
  undone, and not because row 103 was wrong: it was right when there was
  only one act to name. There are two now. A page is **published** when
  students can see it in the built site (the `publish:` flag above, which
  the assistant changes); the whole site is **deployed** to Netlify,
  Cloudflare, or a folder (the teacher's own act, which the assistant
  never takes). One word for both makes "I published tomorrow's class"
  mean a flag to one party and a live site to the other.

  **✅ DONE (macOS, 2026-08-15).** 24 strings across 14 files, following the
  same rule: the SITE is deployed, a PAGE is published. Internal names kept
  their spelling, including every automation id, so no launcher, config key
  or UI test moved. One judgement beyond the Windows sweep: the Netlify
  failure messages ("Try publishing again" after a failed deploy) were swept
  too, since that sentence is exactly the confusion being fixed — flagged
  here in case Windows wants to match. See spec entry 143.

  On Windows the sweep covered: the toolbar button and its tooltip, the
  No Preview Running invitation, the progress title, the Publishing
  settings group (now "Deploying") and its "Deploy to" picker, the
  Cloudflare and folder problem dialogs, the busy lines in
  `CourseActivity.BusyReason`, and the folder-copy completion note.
  **Internal names deliberately keep their spelling** — `deploy.ps1` /
  `deploy.sh`, `deploy_target`, `deploy_folder_path`, the `deployButton`
  automation id — so nothing in the launchers or the config format
  moves. Also worth copying: the assistant's plan says "Unpublish", not
  "Hide", since hide/unhide is not a teacher's word.


- **AI Assist — an MCP server, on the `ai-assist` branch** (Windows +
  shared, 2026-08-13). Commits `c6b1381` (the feasibility investigation
  and its evidence) and `b3b7fc0` (the server). **Nothing here is on
  `main`, and none of it is in 1.0** (see the branch note above — this is
  no longer accurate) — the branch exists so this can be
  folded into a later release or dropped without touching the impending
  release. Read [`research/ai-assist/HISTORY.md`](research/ai-assist/HISTORY.md) part 1 first for the measurements,
  then [`windows-app/Plantoir.Mcp/README.md`](windows-app/Plantoir.Mcp/README.md)
  for the tool surface and the reasoning behind its shape.

  **✅ DONE (macOS, 2026-08-15), by a different route.** Rather than a
  separate executable, the app itself answers `--mcp-stdio <folder>` and
  serves the same `AssistToolSurface` over JSON-RPC. Verified by handshake:
  `initialize` and `tools/list` return `runner.mcpDefinitions` whole, with
  their schemas and `readOnlyHint` annotations — 15 tools when this was first
  verified, 23 when re-counted 2026-08-15. Same surface, two clients, no drift possible
  — and see the note on the entry below for why this route was taken.

  **What exists.** `plantoir-mcp`, a stdio MCP server over one working
  folder, built on the official `ModelContextProtocol` 2.2.0 C# SDK. Eight
  tools: four read-only, two planning tools that change nothing, and two
  writes that back up first. Verified end to end over real JSON-RPC against
  the sample course — including a publish that flipped one section's
  per-section key while leaving the other section's untouched, with the
  backup written first. (Those keys were `draftSection<N>` at the time;
  they are `publishForSection<N>` now — see the publication-flag entry
  at the top of this file.)
  Plan logic is unit-tested against a fake launcher; the suite is at 200.

  **The mac side inherits most of it.** The platform-neutral logic lives in
  `Plantoir.Core` (`Assist/AssistWorkspace.cs`, `Assist/PublishPlan.cs`,
  `Models/PageFrontmatter.cs`, `Models/PagePaths.cs`, `Models/WikiLinks.cs`)
  and the launcher call is abstracted behind `ILauncherRunner`, which picks
  `deploy.ps1` or `deploy.sh` by platform. The csproj already lists
  `osx-arm64` and `osx-x64`. **In principle `dotnet publish -r osx-arm64`
  is the entire mac port.**

  **The Phase 0 question is still open, and it is yours.** Is the mac side
  willing to ship a .NET-published binary beside (or inside) the app? If
  yes, one implementation serves both platforms and every behaviour is
  written and tested once. If no, `Plantoir.Mcp/README.md` is the spec a
  Swift implementation should follow — but please keep the four safety
  rules exactly, because each one is a measured failure and not a
  preference:

  1. *No destructive tool exists.* The model declined "delete the Unit 1
     folder" because it had **no tool for it**, not from judgement.
  2. *Publish and hide are separate tools, never one tool with a boolean.*
     Asked to hide a page, the model called publish with "include linked"
     set — on some runs and not others.
  3. *Every named entity is validated against disk*, and a miss is a
     refusal naming what does exist. Asked to "clean up my course", naming
     no course, it invented `MCV4U`.
  4. *Every write backs the course up first and has a `plan_` twin that
     changes nothing.* Row 106 closing its own loop.

  **Two things the mac side should sanity-check**, because they were
  reasoned from shared code rather than tested on macOS: that
  `Path.GetRelativePath`-based containment behaves as expected on a
  case-insensitive-but-case-preserving APFS volume, and that the launcher
  runner's `/bin/sh` invocation of `deploy.sh` inherits the environment
  Colima needs.

  **A shared-launcher change rode along with this, and it is worth taking
  even if the mac passes on everything else.** `preview.sh` and `deploy.sh`
  used `docker exec -it` unconditionally. `-t` **refuses to start** when
  stdin is not a terminal, so any non-interactive run — a script, CI, an
  MCP server — died at that line, *after* several minutes of Docker build,
  saying only "the input device is not a TTY". (`verify.sh:69-75` has
  refused up front for this reason for ages; that guard is now
  unnecessary.) Both scripts now ask for a terminal only when there is one
  and run Python unbuffered when there is not, so progress still arrives
  line by line instead of in one lump. **The interactive path is
  byte-identical in behaviour**, so the mac GUI — which supplies a terminal
  through `PseudoTerminal.swift` — is unaffected. Verified on Windows end
  to end; the shell edit is the same two-line shape and wants a quick
  confirmation on macOS.

  **Known gap, shared design needed.** The server cannot see the GUI's
  in-flight previews or publishes and vice versa — `CourseActivity` and
  `PreviewLeases` are in-process on both platforms. Overnight this is moot;
  daytime overlap could corrupt a build. The v2 answer is a lease file
  under the working folder that both apps and the server honour, which
  **both sides would have to adopt**. Worth agreeing on the file shape
  before either side writes it.


- **Cloudflare Pages as a third publishing destination** (Windows +
  shared, 2026-08-12). Commits `0306c98` (container side), `4575647`
  (account fallback), `e6611cc` (Windows UI). **The shared half is
  already done and the mac inherits it** — `scripts/deploy.py` and the
  `Dockerfile` are common to both apps. The mac side needs two things:
  `deploy.sh`, and the GUI.

  **What already works, in shared code.** `deploy.py --target cloudflare`
  discovers the account, creates or reuses this section's Pages project,
  hands the built folder to wrangler, and prints `Live URL: https://…` —
  the label both apps' parsers already read, so no parser change was
  needed on either side. Per-section state lives in
  `courses/<CODE>/.cloudflare_sites/section<N>.json`, deliberately
  mirroring the existing `.netlify_sites/` marker.

  **Design decisions, and why — please keep these rather than re-deciding:**

  1. *Publishing rides on wrangler, not a reimplementation.* Cloudflare's
     direct-upload protocol is multi-stage and undocumented: BLAKE3 hashes
     computed over base64-of-contents plus the file extension, a
     short-lived upload JWT that can expire mid-upload on a large site,
     and batched asset uploads. Community write-ups exist, but a
     reimplementation would break teachers' publishing silently whenever
     Cloudflare changed it. wrangler is Cloudflare's own supported
     implementation and already handles those edges.
  2. *wrangler is pinned at 4.80.0 — and pinned BELOW 4.100 on purpose.*
     From 4.100 wrangler requires Node 22; the image ships Node 20 because
     that is what Quartz v4.5.0 is known-good against. Raising Node to
     chase a newer CLI would mean revalidating every teacher's site build.
     Install and `--version` were verified on `node:20-slim` before
     committing. **If you bump Node, revisit this pin — and revalidate
     Quartz first.**
  3. *A token scoped to Pages CANNOT list its own account.* This was
     found by testing a real token: `/user/tokens/verify` reports
     `active`, while `/accounts` returns success with an EMPTY list and
     `/memberships` returns 403. The first cut treated "no accounts" as
     "bad token" and would have sent teachers off to re-mint a perfectly
     good one. **Validity and account lookup are now separate questions**
     — validity against `/user/tokens/verify`, the account by discovery →
     remembered value → asking. Please do not collapse them again.
  4. *Because of (3), the account ID must be collected in the GUI.* The
     app publishes with nothing attached that can answer a console
     prompt, so the launcher's prompt is unreachable from the GUI. On
     Windows it is a field in the Publishing section, validated live (32
     hex characters) with Save/Create gated on it, and passed to the
     launcher as `--account`. It is stored in **app settings, not course
     settings**, because it identifies the teacher rather than the course
     — the same reasoning that puts the token in the OS keychain — so it
     is entered once and used by every course.
  5. *The 25 MB per-file cap is checked before anything uploads.*
     Cloudflare refuses larger files, and the failure otherwise surfaces
     from deep inside the upload as an unhelpful error. `deploy.py` lists
     the offending files by name and suggests compressing the video or
     publishing that section to Netlify, which allows larger files. This
     is the one real functional difference between the destinations and
     is worth saying plainly in the mac UI too.
  6. *Tokens are stored under separate keychain entries.* A teacher
     publishing some courses to Netlify and others to Cloudflare keeps
     both, and `--reset-token --target cloudflare` clears only the
     Cloudflare one (plus its remembered account).

  **What the mac side must write.** `deploy.sh` needs the `--target`
  and `--account` flags, its own keychain entry for the Cloudflare token
  (plus one for the remembered account ID), token validation against
  `/user/tokens/verify`, and the same env hand-off into the container:
  `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, with
  `--target cloudflare` passed to `deploy.py`. **`deploy.sh` was left
  deliberately untouched on the Windows side** — shipping an edit to a
  launcher that could not be tested here would be worse than shipping
  none. GUI-wise: the third picker option, the account field with live
  validation, the milestone list (never saying "Netlify" — pinned by a
  test on Windows), and a decline path if the account is missing.
  Reference: `windows-app/Plantoir/Views/PublishingChoiceView.cs`,
  `SectionDetailView.xaml.cs` (`Deploy_Click`),
  `Plantoir.Core/Scripting/TaskMilestones.cs`,
  `CourseConfiguration.CloudflareAccountProblem`.

  **Status: PUBLISHED END TO END and working** (Windows, 2026-08-12).
  MCV4U Section 1 from a real workspace went live at
  `mcv4u-s1-2026-gordon.pages.dev` (HTTP 200, correct Quartz title),
  driven from the app's Publish button, not a script. Observed:

  - First publish ~140 s including the one-off toolchain image rebuild;
    a second publish ~23 s, reusing the project rather than creating a
    second one (exactly one project in the account afterwards).
  - The progress bar tracked "Step 8 of 8" through the
    `BuildAndDeployToCloudflare` list, and the completion panel showed
    "Your website is live" with the clickable pages.dev link — the
    Netlify live-link panel works unchanged, because `deploy.py` prints
    the `Live URL:` label the parser already reads.
  - The marker file came out as intended:
    `{name, id, subdomain, account_id}`.

  **The build-counter question is settled, empirically.** The deployment
  record for a Direct Upload reports `deployment_trigger.type: ad_hoc`
  and its stages come back `clone_repo=idle, build=idle, deploy=success`
  — **no Cloudflare build runs**, so the free plan's 500-builds-per-month
  limit does not apply to how Plantoir publishes. A teacher republishing
  many times a day across several classes is in no danger of it. (The
  limit is documented as applying to builds triggered by a git push,
  which this path never does.) Worth not re-investigating on the mac.

  Remaining unknown: behaviour at the 25 MB per-file cap has still only
  been checked by the pre-flight guard in `deploy.py`, not by actually
  pushing an oversized file.

  **Mirror the standing size note too** (`8883ad9`). Whenever Cloudflare
  is the chosen destination, the Publishing section shows a permanent
  orange line — not the validation warning, which comes and goes, but a
  fact about the destination that never hides:

  > One thing to know: Cloudflare won't accept any single file larger
  > than 25 MB. Documents, images, and slide decks are almost always
  > comfortably under that — a long video usually isn't. Most teachers
  > embed video from YouTube or Vimeo rather than uploading it, which
  > avoids the limit entirely.

  This is the one real functional difference between the destinations, so
  a teacher should meet it while choosing rather than when a publish
  fails. The grey caption deliberately no longer repeats it.

  **✅ DONE (macOS).** Both halves the mac owed.

  `deploy.sh` gained `--target netlify|cloudflare` and `--account <ID>`,
  its own Keychain entries (`containerized-quartz-cloudflare` and
  `containerized-quartz-cloudflare-account`, separate from the Netlify one
  so a teacher keeps both), validity against `/user/tokens/verify` kept
  SEPARATE from the account lookup exactly as decision (3) asks, the
  account resolved `--account` → discovery → remembered → ask, and the same
  env hand-off into the container: `CLOUDFLARE_API_TOKEN`,
  `CLOUDFLARE_ACCOUNT_ID`, `--target cloudflare` to `deploy.py`.
  `--reset-token --target cloudflare` clears only the Cloudflare pair. The
  token now lands at `/tmp/deploy_pat` rather than `/tmp/netlify_pat`,
  since either token rides the same way.

  GUI: `PublishingChoiceView` is now a three-way picker (`netlify` /
  `cloudflare_pages` / `local_folder` — the same spellings Windows writes,
  since the file is shared), with the Account ID field, live 32-hex
  validation via `CourseConfiguration.cloudflareAccountProblem`, and the
  permanent orange 25 MB note. The ID is in `Models/AppSettings.swift`
  (app settings, not course settings), matching the Windows reasoning.
  Save and Create are gated on it; the Deploy button refuses BEFORE any
  building, with the same "under Deploying" wording. Milestones
  `deployToCloudflare` / `buildAndDeployToCloudflare` never say "Netlify",
  and the `Live URL:` parser needed no change, as promised.

  New: `Models/DeployCommand.swift` is now the single place that decides
  what `deploy.sh` is asked to do. Both the Deploy button and the scheduled
  agent read it, so a scheduled deploy cannot quietly go to the wrong
  destination.

  Pinned by `Tests/QuartzTeachersTests/CloudflareDeployTests.swift`.
  **Still wanted: one live Cloudflare deploy from the mac**, the way
  Windows verified MCV4U — nothing here has yet met a real token.


- **`sanitize_last_name` folds accents instead of dropping them**
  (shared, 2026-08-12, commit `0306c98`). Pre-existing bug in
  `scripts/deploy.py`, found while testing Cloudflare project naming: the
  function kept only `a-z`, so a teacher named **Côté** got `ct` in her
  site name and Müller got `mller`. In an Ontario staff list that is not
  an edge case. It now normalises (NFKD) and strips combining marks
  first, so Côté → `cote`. **This affected Netlify site names too**, and
  the mac inherits the fix automatically since `deploy.py` is shared —
  no mac code needed, but worth knowing the suggested names changed.
  Existing sites are pinned by their marker files and are unaffected.

  **✅ DONE (shared).** Already present in `scripts/deploy.py` on this side —
  arrived with the merge and verified: `Côté` → `cote`, not `ct`.


- **About box credits match plantoir.app's footer** (Windows, 2026-08-11).
  The credits section is now: a rounded-rect callout carrying the full
  sponsor message ("Plantoir is a friendly wrapper around [Quartz], which
  Jacky Zhao builds and gives away for free. If you end up using Plantoir
  regularly, please consider [sponsoring him on GitHub] — it is his work
  that makes all of this possible."), then three plain acknowledgement
  lines: "Icon from [Phosphor Icons] (MIT)." / "Designed by
  [Russell Gordon]." / "Made with Claude." — links to quartz.jzhao.xyz
  and github.com/sponsors/jackyzha0 (in the callout), phosphoricons.com,
  russellgordon.ca. No "Built on Quartz" line: the callout already says
  whose work this stands on. (Replaces the old one-line "Please sponsor
  Jacky" credit; plantoir.app's footer matches.) Also: the
  plantoir.app/support row is REMOVED from the Windows About — help is
  coming into the app itself — leaving Email as the only contact row;
  drop the mac About's Support row to match. Mirror in the mac About
  window. Reference: `windows-app/Plantoir/Views/AboutDialog.cs`.

  **✅ DONE (macOS, 2026-08-12).** Mirrored as spec entry 107.


- **Preview builds are never deploy-fresh** (from `94e25f8`, 2026-08-11).
  Deploying right after previewing published the preview's build, whose
  pages carry Quartz's live-reload client (`new WebSocket('ws://localhost:…')`)
  — so the PUBLISHED site knocked on every visitor's localhost and
  Chromium-family browsers prompted "wants to access other apps and
  services on this device" on first load. The shared `scripts/deploy.py`
  now detects the client and re-emits a production build before
  uploading, which already protects the mac app functionally — but the
  mac app's own deploy-freshness check shares the Windows one's blind
  spot (it compares only content dates). Mirror the Windows fix so the
  app's ordinary, visible build-first step runs instead of the silent
  in-deploy rebuild: a built `public/index.html` containing
  `ws://localhost:` is never fresh. Reference:
  `windows-app/Plantoir.Core/Models/BuildFreshness.cs`
  (`BuiltForPreview`) and the `APreviewBuildIsNeverDeployFresh` test in
  `windows-app/Plantoir.Tests/ModelTests.cs`.

  **✅ DONE (macOS, 2026-08-12).** Mirrored as spec entry 108.


- **Font samples show the course's own computed site title** (Windows,
  2026-08-11). The header font sample renders the title the build will
  actually produce — `[Grade X ]Name[, Section N]`, i.e. the course name
  with the grade and section-marker switches applied — in the candidate
  typeface, updating live as the name, code, section numbers, or either
  toggle changes. The "Grade 11 Computer Science" stand-in remains only
  while the form is blank; the body-sentence sample is unchanged. In
  Course Settings each section's sample uses that section's own toggles.
  The compute is `CourseConfiguration.ComputedSiteTitle` (Core),
  mirroring `computed_landing_title` in `scripts/build_site.py` and
  pinned by a six-case theory test. Mirror in the mac wizard's
  FontChoiceEditorView and Course Settings. References:
  `SampleHeaderText()` in `windows-app/Plantoir/Views/NewCourseDialog.cs`
  and `windows-app/Plantoir/Views/CourseSettingsView.xaml.cs`;
  `ComputedSiteTitleMatchesTheBuild` in
  `windows-app/Plantoir.Tests/CourseConfigurationTests.cs`.

  **✅ DONE (macOS, 2026-08-12).** Already on macOS as spec entry 100.


- **Explain a disabled Create button in the wizard** (from `2d10e4c`,
  2026-08-11). On Windows, a filled-in New Course form with a DUPLICATE
  course code left Create greyed with no explanation — the sections
  field explained its problems inline while the code field stayed
  silent. Windows now shows the reason under the code field ("A course
  named ICS4U already exists — choose a different code."), single-sourced
  with the check that gates the button. Worth checking whether the mac
  wizard has the same silent-disable and wants the same inline
  explanation. Reference: `CourseCodeProblem()` / `RefreshCodeValidation()`
  in `windows-app/Plantoir/Views/NewCourseDialog.cs`.

  **✅ DONE (macOS, 2026-08-12).** Mirrored as spec entry 109.

- (Earlier Windows work — About credits + Support-row removal, the
  preview-build deploy-freshness check, the computed-title font samples,
  and the live code-field explanation — was picked up on 2026-08-12;
  spec entries 107–109 record those mirrors.)


- **Worth checking: the same test race may exist on the mac**
  (`3bbb1a7`, 2026-08-13). A Windows test failed about one run in three
  with a baffling null. The cause was not the production code: preview
  leases and the publish registry are **process-wide statics**, the test
  runner runs test classes in parallel, and the lease-tests class reset
  that shared state around every one of its methods — wiping the lease
  another class was mid-assertion on. Fixed by putting both classes in a
  serialized collection. If the mac's tests around `CourseActivity` /
  preview leases share process-wide state and run in parallel, the same
  intermittent failure is possible there; it is the kind that gets
  written off as "flaky CI" for months. Worth ten minutes to check.

  **✅ DONE (macOS, 2026-08-16) — checked, and the mac is not exposed.** The
  test target is `parallelizable = "NO"` in the scheme, so XCTest runs these
  classes one at a time and the shared statics cannot be reset under another
  class mid-assertion. **The safety is a scheme setting, not a property of the
  tests**: `PreviewLeaseTests` and `CourseActivityTests` both call
  `PreviewLeases.reset()` / `CourseActivity.reset()` around individual methods,
  so turning parallel testing ON would introduce exactly the Windows failure —
  one run in three, a baffling null, and months of being written off as flaky.
  If that setting is ever flipped, put these classes in a serialised group
  first.

- **Align Windows Local AI Assistant brevity and concise responses with macOS**
  (Windows, 2026-08-17). Windows assistant responses were adjusted to match the
  crisp, informative single-sentence outputs on macOS.
  1. Removed `plan_` tools from `ForTheLocalModel` narrowing — plan mode is handled
     directly by code rather than by the model schema.
  2. Updated `AssistWorkspace.Summary()` to return clean past-tense sentences ("Published “Unit 2, Day 3”." / "Nothing needed changing.") rather than multi-clause paragraphs.
  3. Set `temperature: 0` in `LocalModel.Ask()` for deterministic tool routing.
  4. Updated tool approval line in `AssistAgent.Run()` to use `AssistWording.DeployApproval` / `AssistWording.DeployQuestion`.
  
  **✅ DONE (Windows, 2026-08-17).** Recorded in GUI improvement log row 344. All 479 tests passing.

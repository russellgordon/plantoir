# The Plantoir contract — what both apps must agree on

Ten JSON files, **most of them generated from the macOS app** and read by both
test suites. (Three are written by `Plantoir --write-contracts`; the rest are
authored, and `shared-rules.json` is one of those — see "What is generated and
what is written by hand".)
They exist so that "implement what changed on the mac" ends in a green Windows
suite instead of a day of clicking.

This began as the assistant's contract and is no longer only that: it now
covers what the launcher is asked to do, what a teacher is told about what they
typed, how their list of class dates is read, what the files a course keeps are
called, and how classes are named and renumbered. **The test is not which
feature a rule belongs to — it is whether the rule is the product's or the
platform's.** A sentence a teacher reads, an input with one right output, an
order events must happen in: shared. A window's layout, a container's
mechanics, a measurement taken on one machine: not.

| File | What it holds |
|---|---|
| [`assist-wording.json`](assist-wording.json) | Every sentence the assistant says to a teacher about deploying, previewing and agreeing to things, with `{course}` and `{section}` where values go. |
| [`assist-cases.json`](assist-cases.json) | The assistant's behaviour: which phrasings are matched in code rather than routed, which tools wait for a button, what must happen in what ORDER when it deploys, and how the arrow keys walk the prompt history. |
| [`toolchain.json`](toolchain.json) | The image both platforms build from the same recipe: the four pins with the REASON each sits where it does, and what each of the seven Quartz patches changes and why it cannot be dropped. |
| [`example-content.json`](example-content.json) | The ready-made courses: how a payload is discovered, the manifest's keys, and the allow-list rule that decides what actually installs. |
| [`file-formats.json`](file-formats.json) | **The two files both apps WRITE and the Python then reads**: every `course_config.json` key with its type and default, and the frontmatter that decides whether students see a page — including the legacy `draft:` spelling, which means the opposite. |
| [`shared-rules.json`](shared-rules.json) | Nineteen rule sets on top of machinery that could not be less alike: what a scheduled deploy refuses and in what order, what the sidebar's filter shows, what is stripped from the launchers' output, what counts as a curriculum expectation, **what is taken out of — and deliberately KEPT in — a problem report**, **which events every new or changed feature must record on the breadcrumb trail**, and **which local assistant a teacher may choose, what they are told it costs, and when one may be removed**, and **what a page is CALLED when the assistant talks about it**, **which folders count for marks, and which a teacher is OFFERED when they are asked**, **what a teacher is told when a folder a feature depends on has been renamed or deleted**, **how a working folder kept in sync by a cloud service is recognised, what a teacher is told about it, and when**, and **where a section's built website is kept, and what happens to a folder that already has one in the old place**, and **which processes belong to a section's preview, and must therefore be stopped**, and **which of a course's own folders the build treats specially, and what a teacher is told about each**. |
| [`course-management.json`](course-management.json) | The names the three kinds of zip carry and how they are told apart, what section number is offered next and which entries are refused in whose words, and the grade a course code names. |
| [`class-planning.json`](class-planning.json) | Which page titles carry numbers, what "the next class" would be called, and — the highest-stakes data here — the ORDER renames must run in when room is made for a class. |
| [`schedule-rules.json`](schedule-rules.json) | How a teacher's own list of class dates is read: every accepted date form, how an ambiguous `08/09/2026` column is settled or asked about, and what a pasted Google Sheet address becomes. |
| [`app-rules.json`](app-rules.json) | The app itself: what `deploy.sh` is asked to do for a given configuration, what a teacher is told about an Account ID or a custom domain they typed, how a failure's raw output becomes a sentence, whether a deploy must build first, the progress markers and **where each marker's text comes from**, the preview's ports, and **what a teacher is shown when a first publish stops to ask for a Netlify or Cloudflare credential**. |

## What is generated and what is written by hand

`assist-wording.json` is generated in full. `assist-cases.json` is mixed, and
the boundary is a TOP-LEVEL key — the file names them under `generated.keys`:

| Key | Comes from |
|---|---|
| `cardPhrasings` | `AssistCardCommand.fixedShapes` |
| `tools` | `AssistToolRunner.tools` / `.localTools` / `.mcpOnlyTools`, and each definition's `needsApproval` and `planTwinName` |
| `nearMisses`, `scenarios` | **Hand-written intent.** The generator preserves them; nothing in the code says what a near miss is, or what ORDER events must happen in — those are decisions, and decisions are why this repository has handoff documents. |

In `app-rules.json` the same split applies: `milestones` is a readout of
`TaskMilestones` and `credentialRequests` a readout of `CredentialRequest` —
both overwritten; `deployArguments`, `configurationRules`, `previewPorts`,
`markerOrigins` and `credentialPrompts` are authored and preserved. The pair
`credentialRequests` / `credentialPrompts` shows the split at its clearest: the
first is the WORDING, carried so the other app can show the same sentences
rather than invent its own, and the second is the BEHAVIOUR — which launcher
prompt is a request for which credential — which must fail when it drifts. The rule behind
the split is worth stating once — **a readout of the code cannot fail when the
code changes**, so anything that must catch a regression is written by hand and
executed against the real function.

### The one in `app-rules.json` that is easiest to get wrong

`markerOrigins` says, for every progress marker, where its text actually comes
from. It decides whether your app must match the string exactly:

- **`shared-python`** — printed by `scripts/*.py`, identical output on both
  platforms. Match it to the character. Nineteen of the twenty-eight are these.
- **`launcher`** — printed by `setup.sh` / `preview.sh` / `deploy.sh`, which
  have separately written `.ps1` counterparts. These **deliberately differ**,
  and since 2026-08-19 they no longer even pair up: Windows dropped Docker for
  a native runtime, so the mac's "Setting up this Mac" has no Windows
  counterpart at all rather than being answered by "Setting up this PC", and
  neither container marker has one either. `knownDivergence` carries the five
  strings a Windows milestone must therefore never watch for; Windows' OWN
  launcher text is not here, because it is the platform's rather than the
  product's. Seven of the twenty-eight.
- **`elsewhere`** — printed by the Docker build or a tool; check by hand.

**Both suites verify the classification against the actual files**, so a marker
that moves from a launcher into shared Python (or the reverse) fails rather
than silently changing what the other app should be matching. The mac walks the
markers its own lists use and looks each one up; Windows
(`MilestoneContractTests`) does the same and then the reverse — a marker the
contract does NOT name, which something under `scripts/` nevertheless prints,
fails and says to classify it. That reverse direction is what found the two
example-course markers — which the mac DOES have a task for, but which
`AppRulesContract.milestones()` leaves out of the readout its own check walks.
Getting this wrong crashes nothing: the progress bar simply stops moving, which reads as a
slow build.

One of the twenty-eight is in no milestone list on either side. "Launching
Quartz preview" is printed by `build_site.py` BEFORE `quartz build --serve`
has started, so a bar that waited on it completed every remaining step at once
and sat there for the whole real build (Windows found this;
`TaskMilestones.Preview` uses Quartz's own "Done processing" instead). It stays
classified because the line is still printed and a future list may want it.

Two more — `"Example Course installed to"` and `"EXAMPLE_COURSE_CODE="` — went
unclassified until 2026-09-06, and how is worth knowing, because the mechanism
can hide any marker. Both apps have an example-course task and always did
(`TaskMilestones.exampleCourse`), but `AppRulesContract.milestones()` does not
list it, so the generated `milestones` readout has eight tasks where the mac
has nine. The mac's classification test walks the READOUT, so a marker missing
from it is invisible to the test however loudly the shared script prints it —
and the classification is only as complete as the readout it is checked
against.

## Proposing a case from the Windows side

The generator runs on the **mac** — `Plantoir --write-contracts` — so Windows
cannot regenerate the derived halves. The AUTHORED halves are a different
matter and can be proposed from either side: `scenarios`, `nearMisses`,
`promptHistory`, and every case list in the other four files survive a mac
regeneration untouched.

So a behaviour invented on Windows can be written here as a case, and **the
mac suite will then fail until the mac implements it.** That is the mechanism
working rather than breaking. Verified by adding a case for a step the mac has
no support for: `AssistScenarioTests` failed naming the case and the missing
event, rather than passing quietly.

Two things make that failure read as a request instead of as damage:

- **Name the case so it is obviously a proposal, and open a GitHub issue
  labelled `mac`** saying which case you added and what the mac has to
  implement to make it pass. That issue is where the mac side looks for work
  that arrived from Windows, and it is what turns a red suite over there into a
  request. (Until 2026-09-08 this said to write it into `MAC-HANDOFF.md` under
  "Contract cases waiting on the mac"; that section no longer exists.)
- **Do not touch the generated keys** (`cardPhrasings`, `tools`, `milestones`).
  Those are readouts of mac code; an edit there is overwritten on the next
  regeneration and the diff looks like vandalism.

## Regenerating

```bash
Plantoir --write-contracts contracts
```

The bundled binary writes both files from the app's own types — `AssistWording`,
`AssistCardCommand`, `AssistToolSurface`. `AssistContractTests` runs the same
generator in-process and fails when what is committed no longer matches, naming
that command. **So a changed sentence fails on the mac first**, in the same run
that changed it, and arrives on the Windows side as a diff in this folder
rather than as a bug report from a teacher.

## Why these are not in `support/`

`support/` is bundled into the app and mirrored into every teacher's working
folder as `.toolchain/`. Test data does not belong in a teacher's course folder,
and anything put there gets copied to every machine that runs a build.

## Reading them from the Windows suite

Both files are plain data — an xUnit `[Theory]` with a `MemberData` source that
deserialises the JSON is the whole integration. Nothing here is macOS-specific:
the sentences are the product's, and the sequences are the toolchain's.

The full list of what the contract cannot cover — and therefore what each side
still tests for itself — is in
[`documentation/10-local-ai-assistant.md`](../documentation/10-local-ai-assistant.md), under "Do not re-derive the
assistant's tests". Two of them matter enough to repeat:

- **How the preview is stopped and started.** WSL2, ConPTY and the preview
  leases have real Windows mechanics; `assist-cases.json` says the ORDER the
  events must occur in, not how to make them happen. **Half of this moved on
  2026-09-05**: WHICH processes belong to a section's preview is a shared rule
  now (`shared-rules.json` → `stopPreview`), because three implementations of
  that one question had drifted into three different answers, one of them a
  live bug. Finding them and ending them is still yours.
- **Anything the model decides.** Routing accuracy is measured, not asserted —
  see [`research/README.md`](../research/README.md). A contract can say that
  "deploy now" never reaches the model; it cannot say what the model would do
  with a sentence it does reach.

## Coverage: every mac test file, and where it stands

No stone unturned — this table is the audit, and a file missing from it is a
gap nobody has looked at. Counts are test functions, taken 2026-08-16; the `siteHealth` row was
recounted 2026-09-07.

**Shared through a contract** (the Windows suite can run the same cases):

| Area | Contract | Mac tests it draws on |
|---|---|---|
| The assistant's sentences | `assist-wording.json` | AssistToolRunner, AssistAgent |

**Two `pageNaming` sections exist, in different files, and they answer different questions.** `shared-rules.json` → `pageNaming` is what the ASSISTANT calls a page when it talks about one (the frontmatter title, or the folder's name for an `index.md`). `class-planning.json` → `pageNaming` is which class-page TITLES carry unit and day numbers. Grepping for the name alone will send you to the wrong one.

| Deploy/preview order, cards, cancels | `assist-cases.json` → `scenarios` | AssistToolRunner (49), AssistScenario |
| Card phrasings and near misses | `assist-cases.json` → `cardPhrasings` | AssistAgent (8) |
| Tool lists, approvals, plan twins | `assist-cases.json` → `tools` | AssistToolRunner |
| Arrow-key history | `assist-cases.json` → `promptHistory` | AssistPromptHistory (15) |
| Launcher arguments | `app-rules.json` → `deployArguments` | CloudflareDeploy (13) |
| Validation messages | `app-rules.json` → `configurationRules` | CourseConfiguration (10), CustomDomain (4) |
| Progress milestones and marker origins | `app-rules.json` → `milestones`, `markerOrigins` | TaskMilestone (12) |
| Failure explanations | `app-rules.json` → `failureExplanations` | FailureExplainer (8) |
| Special folder names: what is blocked, what is confirmed, what a rename says, which keys it carries, and how the new name is SPELLED inside a link | `shared-rules.json` → `specialNames` | SharedRulesContractTests (24), SpecialFolderRenamer (22), FolderPathRewriterTests (2) |
| Which of a course's OWN folders the build treats specially, and what the sheet says about each | `shared-rules.json` → `specialFoldersHelp` | SpecialFoldersHelpContract (5) on Windows, SpecialFoldersHelpTests (5) on the mac — both sides adopted 2026-09-06 |
| Which folder holds class pages, and which count | `class-planning.json` → `classFolder` | ClassFolderContractTests (6), and `scripts/test_class_folder.py` |
| What a course calls a unit | `class-planning.json` → `pageNaming` (the `term` field) and `file-formats.json` → `unit_word` | ClassPageTerm (11), and `scripts/test_class_pages.py` |
| Whether a deploy must build first | `app-rules.json` → `buildFreshness` | BuildFreshness (6) |
| Preview ports and the websocket offset | `app-rules.json` → `previewPorts` | PreviewLease (7) |
| The browser-safe address | `app-rules.json` → `linkRules` | BrowserSafeURL (2) |
| Asking for a publishing credential | `app-rules.json` → `credentialRequests`, `credentialPrompts` | AppRulesContract (3) |
| `course_config.json` keys, types, defaults | `file-formats.json` → `courseConfigKeys` | CourseConfiguration (10) |
| Page visibility: `publish:`, legacy `draft:`, per-section keys | `file-formats.json` → `pageVisibility` | ~33 tests across the suite |
| Image pins and the Quartz patches | `toolchain.json` | checked against `Dockerfile` and `patches/` |
| Example-content payloads (all 38) | `example-content.json` | ExampleContent (10), and the payloads themselves |
| Reading a teacher's date list | `schedule-rules.json` | SectionScheduleSource (23) |
| Scheduled-deploy refusals | `shared-rules.json` → `scheduledDeployRefusals` | ScheduledDeploy (23) |
| Sidebar filtering | `shared-rules.json` → `sidebarFilter` | CourseFilter (9) |
| Stripping the launchers' output | `shared-rules.json` → `transcriptStripping` | TranscriptBuilder (6) |
| What counts as a curriculum expectation | `shared-rules.json` → `curriculumRules` | AssistCurriculumMentions (11) |
| What is taken out of a problem report | `shared-rules.json` → `problemReportRedaction` | ProblemReport (17), SharedRulesContract (2) |
| What the breadcrumb trail must record | `shared-rules.json` → `activityTrail` | ActivityTrail via ProblemReport, SharedRulesContract (2) |
| A working folder a cloud service keeps in sync: how it is recognised, what is said, when | `shared-rules.json` → `cloudSyncedFolders` | CloudSyncedFolder (18), CloudSyncNoticeLayout (5) |
| Where a section's BUILT WEBSITE is kept, and what happens to a folder that already has one | `shared-rules.json` → `buildOutputLocation` | BuildOutputLocation (22), SharedRulesContract (2), and `scripts/test_build_output_link.sh` in `verify.sh` (22 checks) |
| When the report asks about the assistant, and what it is called | `shared-rules.json` → `problemReportDialog` | SharedRulesContract (2), ProblemReport (2) |
| Which assistant a teacher may choose, the caution, and when one may be removed | `shared-rules.json` → `assistantModelChoice` | SharedRulesContract (5), AssistantSettings (22) |
| What a page is called when the assistant names it | `shared-rules.json` → `pageNaming` | SharedRulesContract (2), AssistPageNaming (7), AssistToolRunner (2) |
| Dating the pages a class brings when it is published | `class-planning.json` → `datingPagesAClassBrings` | ClassPlanningContract (2), AssistToolRunner (7) |
| What publishing and unpublishing do to linked pages, and what is never swept | `shared-rules.json` → `followingLinks` | SharedRulesContract (2), AssistToolRunner (3) |
| Whether the assistant asks before changing anything, and when it says so | `shared-rules.json` → `assistantConfirmation` | SharedRulesContract (1), AssistPlanMode (6), AssistantSettings (6) |
| Phrasings matched in code, including the four PARSED families | `assist-cases.json` → `cardPhrasings` | AssistContract (1), AssistPromptShelf (2), AssistToolRunner (4) |
| Backup, archive and wizard zip names | `course-management.json` → `zipNames` | BackupItem, ArchivedItem (18) |
| Adding a section: suggestion, refusals, wording | `course-management.json` → `sectionNumbers` | SectionAdder, SectionNumbersValidation (21) |
| Grade labels from a course code | `course-management.json` → `gradeLabels` | SectionAdder |
| Naming, numbering, making room | `class-planning.json` | ClassPlanning (13), NextClass (13) |
| Which folders count for marks | `shared-rules.json` → `gradedFolders` | `scripts/test_graded_folders.py` in the image; the mac reads the key but runs no case list yet |
| Which folders the marks checklist OFFERS | `shared-rules.json` → `gradedFolders.choices` | Proposed from Windows 2026-09-06 and run there by `GradedFolderChoicesTests` (10 cases). **The mac has the behaviour and runs no case list**, so its suite does not go red for this one — [issue #112](https://github.com/russellgordon/plantoir/issues/112). |
| What a teacher is told when a folder a feature needs has gone, what Plantoir offers to put right, and what it REFUSES to touch | `shared-rules.json` → `siteHealth` | SiteHealthContract (8), SiteHealthFinding (15), SiteHealthRepair (25), and `scripts/test_site_health.py` |

### Which of these the WINDOWS suite runs

The table above says what the MAC draws on, and for a long time nothing said
the same about Windows. That turned out to matter: an audit on 2026-09-06
found **23 case lists the mac ran and the Windows gate did not read at all** — none of them unreachable, each simply a test
nobody had written. Wiring them found a divergence in how the two apps write
teachers' frontmatter, four tool arguments that differ by design and were
recorded only in a Swift comment, two shared markers classified by nobody, and
a launcher flag listed as shared that only one platform has.

So the state is worth writing down rather than re-derived. Windows now runs
every list that audit counted, plus three it missed (`linkRules.browserSafe`,
`example-content.sentinels` and `linkRewriting`, the last wired on 2026-09-07),
through these classes in
`windows-app/Plantoir.Tests/`:

| What it runs | Class |
|---|---|
| `markerOrigins` both directions, and the shared steps of each `milestones` list | `MilestoneContractTests` |
| `wizardAnswerKeys`, `firstDeployMarkers`, `sectionTimetable`, `pageVisibility.writingRules` | `FileFormatContractTests` |
| `publishedFreshness`, `credentialPrompts.everyRequest`, `launcherFlags.deployExtras`, `previewPorts`, `linkRules.browserSafe` | `PublishAndLauncherContractTests` |
| `toolSchemas` (names and arguments), `assistantModelChoice`, `modelTiers.requirements`, `promptHistory.passThroughWhen` | `AssistSurfaceContractTests` |
| `renameEffects`, `problemReportDialog`, `ancestorPaths`, `pageNaming.theRule`, `buildOutputLocation.windowsLocation`, `example-content.rules`, `example-content.sentinels`, `recipeFolders`, `scheduledDeployRefusals.alsoSaid` | `SharedRuleContractTests` |
| `gradedFolders.cases`, and `gradedFolders.wording` — the Marks list's title and caption (proposed from Windows 2026-09-08; the mac runs nothing for it yet and is not red) | `GradedFolderContractTests`. Whether a teacher can SEE the caption is `CourseSettingsCaptionUiTests` in `Plantoir.UiTests/`, opt-in and part of no gate |
| `gradedFolders.choices` (cases, the depth cap and the skip list) | `GradedFolderChoicesTests` |
| `specialNames` — the blocked and confirmed names, `renameFolder.carriesAcross`, `renameFolder.problems`, `curriculumFolderResolution` | `SpecialNamesContractTests`, `SpecialFolderRenamerTests`, `GradedFolderContractTests` |
| `specialNames.contentStructureTip` (proposed from Windows 2026-09-07; the mac runs nothing for it yet, and is not red — no mac test names the key) | `SpecialNamesContractTests`. Whether a teacher can actually SEE it is `CourseSettingsCaptionUiTests`, which is in `Plantoir.UiTests/` rather than this project, carries `[UiFact]`, and runs only under `PLANTOIR_UI_TESTS=1` — so it is part of no gate |
| `specialNames.renameFolder.materialisesOnRename`, `addCreatesTheFolder`, `removeLeavesTheFolderOnDisk`, `renameFolder.interruptedRename` (proposed from Windows 2026-09-07) | `FolderRenameApplyTests` |
| `specialNames.renameFolder.linkRewriting` — every case, plus `escapingSet.leaveUnescaped` character by character | `FolderPathRewriterTests` |
| `siteHealth.repair.reportedOncePerFinding` (both cases, built as `howToRunACase` says) and `siteHealth.repair.refusedWhenSomethingIsInTheWay` (the sentence, word for word) | `SiteHealthRepairTests`, `SiteHealthContractTests` |
**Two notes on the `specialNames` rows** — there are four of them now, and the
two this note is about are the first and the `linkRewriting` one — because they
are not part of the audit's
count and reading them as though they were would mislead. The `specialNames`
lists in the first were already being run — those test classes predate that
audit — and were simply never written down here. `linkRewriting` is newer than the audit — it was added to
`shared-rules.json` on 2026-09-06, the same day, and fell outside the sweep; the
row is here so it is not missed a second time. `FolderPathRewriterTests` has
deserialised every case since 2026-09-07; before that it retyped five of its
own.

**One list was added after that audit and wired the same day it reached
Windows.** `siteHealth.repair.reportedOncePerFinding` (mac, 2026-09-07) says a
repair reports one result per FINDING rather than one per check name, and
names each thing once in the sentence however many findings produced it.
Windows shipped that shape first and proved it with a hand-written test; on
2026-09-07 the test was replaced by the contract's cases, so the rule has one
home. [`documentation/04-course-setup.md`](../documentation/04-course-setup.md) → "A folder named `index.md`, and why both apps
refuse rather than clear the way" has the detail for the refusal; for the
repair's own shape, the contract key and
`windows-app/Plantoir.Tests` are now the record.

**Three habits came out of that work and are worth copying on either side.**

- **Ask the list both ways.** A test that walks the contract and looks each
  case up in the code cannot notice a case the CODE has and the contract does
  not. Three of the gaps above were found ONLY that way — a credential request
  the contract does not describe, twelve MCP tools, and sixteen tool arguments
  — and no forward walk could have seen any of them. (The others came the
  ordinary way: the frontmatter divergence and `--image` both failed a walk of
  the contract. Both directions earn their keep; only one of them was being
  done.)
- **Check completeness, not just correctness.** A hand-written mirror answers
  the cases that existed the day somebody read the contract. Where a rule's
  cases are prose keyed to behaviour, map each case to a named test and assert
  no case is left unmapped, so a case the other platform ADDS fails by name.
  (Map to names rather than draining a shared set: xUnit builds a fresh
  instance per `[Fact]` and fixes no order, so a set filled by ten tests and
  emptied by an eleventh passes on whatever happened to run.)
- **Say what cannot be executed, in the test.** Some rules are about how work
  is done rather than what the code does — the routing suite's polarity veto,
  the payload rules that belong to `setup_course.py`'s own tests. Naming them
  in the completeness check keeps them owned; dropping them silently is how a
  rule stops being anybody's.

**What is deliberately NOT executed, on either side.** These are English, not
cases, and a "test" of them could only assert that a string exists:

| Rule | Why no test |
|---|---|
| `cloudSyncedFolders.detection.macMarkers` / `.windowsMarkers` | Four paragraphs describing what each platform exposes. The BEHAVIOUR they produce is covered by hand on both sides; the paragraphs are the reasoning behind it. |
| `stopPreview.notShared` | Names the three things about stopping a preview that are the platform's, and says why. The cases themselves ARE run — on Windows by `test_stop_preview.ps1`, which `TheLauncherMatcherAnswersTheContract` (in `ReclaimedProcessesTests.cs`) runs inside `dotnet test`, so it is a gate rather than a script somebody remembers. |
| `modelTiers.requirements` — the polarity veto | A rule about how a MODEL is chosen, governing the by-hand routing suite in `research/ai-assist/`. |
| `example-content.rules` — the three about the installer | They constrain how `setup_course.py` is written, and **nothing automated holds them on either platform** — said plainly because the first draft of this row named an owner that does not exist. `setup_course.py` has no test file; `lint_payload.py` and `lint_skeletons.py` are run BY HAND through the `example-content` skill, and `verify.sh` runs neither. The fourth rule, "anything in the payload trees must be named in the manifest", IS executed — `SharedRuleContractTests` walks every payload against the allow-lists the installer really reads. |

**Not shared, and why.** Each of these is a deliberate decision, not an
oversight:

| Area | Tests | Why it stays local |
|---|---|---|
| Windows, sheets, layout, hit areas, fonts, chat bubbles | ~71 | Platform look and feel. The mac's numbers were measured against Messages; matching them on WinUI would produce something that looks foreign. What must be TRUE of the assistant's window is in [`documentation/10-local-ai-assistant.md`](../documentation/10-local-ai-assistant.md) → "What the conversation looks like, and why". |
| Script runner and preview stopper mechanics | 34 + 2 | ConPTY against a pseudo-terminal, WSL2 against Colima. The OUTPUT they parse is shared (see `markerOrigins`); the machinery is not. **Narrowed 2026-09-05**: WHICH processes belong to a section's preview is now shared (`shared-rules.json` → `stopPreview`) — how they are found (`/proc` against `Win32_Process`) and how they are ended (SIGTERM-then-SIGKILL against `Stop-Process -Force`) remain platform mechanics. |
| Scheduled deploys: the MECHANISM | ~14 | launchd against Task Scheduler — nothing about writing a plist or a task ports. The **refusals** are now shared (`shared-rules.json`), which is the half that matters. |
| Model tiers, plan mode, activity | 30 | Measured on this hardware. See `research/`; a tier ladder measured on an M4 Pro says nothing about a teacher's laptop with integrated graphics. |
| Restoring and archiving the FILES | ~8 | The zip NAMES are shared (above); unzipping, replacing a course folder and reporting what came back is filesystem work with different failure modes on each platform. |
| Example content, skeletons, course names | 25 | Both apps read the SAME files under `support/`. The data is its own contract; run the same validity checks against it rather than copying expectations here. |
| Workspace initialisation, folder containers | 18 | Filesystem shapes that differ (`~/Library/Application Support` against `%LOCALAPPDATA%`). |
| Writing a new section's files | ~5 | The rules are shared (above); creating folders and extending each page's frontmatter is filesystem work. |
| Curriculum mention PLANS, section restore | ~13 | The plan's wording and the restore's file work are local; **what counts as a curriculum expectation** — the folder rule, the code shape, the anchor — is now shared (`shared-rules.json`), because `build_site.py` decides it and both apps must agree with the Python. |
| Console focus and scrolling | ~5 | Which pane has focus and when it scrolls is per-platform. Sidebar filtering and transcript stripping are now shared (`shared-rules.json`). |

## The rule this exists to enforce

A sentence a teacher reads is a specification. Kept in the Swift that says it,
the Swift test that pins it, `GUI-IMPROVEMENTS.md` where it is specified and
the documentation page telling Windows to copy it, it is four copies and
three of them were already drifting — the same deploy failure was told two ways
("that section's console" / "that section's window") depending only on which
function ran it. Now it is written once in `AssistWording`, and everything else
is generated from it or tested against it.
## Sentences the contract does not carry — each app writes its own, knowingly

`contracts/` holds every sentence it can, and says so about the ones it does. These are the exceptions as of 2026-09-01, found by
adversarial review after an earlier draft claimed "sentences …
are all in `shared-rules.json`", which was not true. Each is teacher-facing,
each lives only in the mac's Swift, and each is one a port has to word for
itself — so word it deliberately rather than discovering the gap:

- **`ClassPageTerm.problem(with:)`** — the two wizard refusals for a unit word
  containing a digit or a comma.
- **`SpecialFolderRenamer.rename`'s half-failure sentence** — "Plantoir renamed
  N of M copies of 'X' and then could not rename the one in section3: …". The
  SHAPE is what matters and is worth copying: the count moved, and the section
  that stopped it. A bare exception here leaves a teacher with a course renamed
  in two sections out of four and no idea which.
- **`CourseSettingsView.renameFolder`'s bookkeeping-failure sentence** — the
  folder moved but the configuration could not be written. Do not report this
  as "the rename failed": it did not, and saying so sends the teacher looking
  for a folder under its old name.
- **The wizard's unit-word caption** — "Class pages will be named '… 1, Day 1'".
- **The assistant's unit sentences**, which an earlier draft wrongly said were
  "listed below with the others" until this line was added: "{word} N was published",
  "{word} N has already been published", "{word} N is already hidden", "{word} N
  was only partly published", and "I can't find any class pages in {word} N of
  …". They are hardcoded in `AssistToolRunner` and are in NO contract — not
  even `assist-wording.json`, which carries the rest of the assistant's words.
  That is a pre-existing gap this work inherited rather than made, and it is
  named here so nobody goes looking for them.

**Three things the contract DOES carry that must not be copied verbatim.**
`specialNames.renameFolder.explanation`,
`specialNames.renameFolder.doneNothingWasThere` and
`specialNames.removeLeavesTheFolderOnDisk.message` all say "on your Mac".
Windows substitutes "on this PC", the same way it already does for `app-rules.json`'s
"this Mac" — `contracts/README.md` documents that substitution. Your contract
test must compare on the substituted form or it will fail on a difference that
is correct.
## The scripts can read the contract — and it travels differently on Windows

`contracts/` used to be readable only by the two test suites. It is now readable
from `scripts/*.py` as well, through `scripts/contracts.py`. This is the spine of
a larger piece (hardening the folder and file names that carry hidden meaning —
`Tasks`, the curriculum folder, `All Classes`, `Media`, `index.md`,
`Key Links.md`), and it matters to you because the rules being hardened live in
`build_site.py`, which is the thing that actually decides what ships. A rule that
lives there and nowhere a test can reach is a third implementation with no gate
on it — the drift the contract exists to prevent, arriving by the back door.

**Why it had to be baked into the image, and what that costs.** The container's
ONLY bind mount is `courses` (see `preview.sh`, `deploy.sh`). The working
folder's `.toolchain/` sits beside `courses/` and is NOT mounted; the app bundle
is on the host. So neither of the two obvious routes can be read from inside the
container, and the contract has to be `COPY`d in by the Dockerfile. The
consequence is deliberate: `contracts/` is not in `toolchain_hash`'s prune list,
so every contract edit mints a new `teaching-quartz:src-<hash>` tag and forces an
image rebuild and container recreate. That is development-time cost on the mac,
paid on every case added, and it was accepted because the alternative was a
shared rule the build cannot see.

**None of that applies to you, and that is the point of this section.** Windows
runs these scripts NATIVELY — no container, no image, no hash. The contract
reaches Python through `PLANTOIR_CONTRACTS_DIR`, exactly the way
`PLANTOIR_SUPPORT_DIR` already reaches `support/`. Five things carry it:

- `ToolchainMirror.RecipeFolders` gained `contracts`, so a working folder's
  `.toolchain/` gets it;
- `Plantoir.csproj` ships `Toolchain\contracts\`;
- `setup.ps1`, `preview.ps1` and `deploy.ps1` set `PLANTOIR_CONTRACTS_DIR`;
- `Vendor/fetch-runtime.ps1` sets it too — a SIXTH env-setting site the first
  pass missed, and the kind that is latent until it is not: it runs
  `setup_course.py` while provisioning the runtime, so the first time a script
  reads a required contract there, it throws `ContractMissing` naming
  `/opt/contracts` on a Windows host. That error names a container path on a
  machine that has no container, which is about as confusing as a message gets.

**If you add another place that runs a `scripts/*.py`, it needs the variable.**
There is no way to make this fail loudly at build time; it fails at run time, in
whatever feature happened to read a contract first.

**A trap that cost real time here, and travels to you unchanged.** The recipe's
folder list existed as FOUR hand-maintained copies: the mac's
`WorkspaceModel.refreshToolchain`, your `ToolchainMirror.RecipeFolders`, the
marketing screenshot harness (`website/shots/capture.py`), and the Dockerfile's
own `COPY` lines. They drifted the moment a fifth folder was added, and the one
that drifted was the harness — whose docstring said, in so many words, "keep them
in step".

The failure mode is worth understanding because it is not the one you would
guess. `capture.py` copies the *Dockerfile* too. So the demo workspace got a
Dockerfile containing `COPY contracts/ /opt/contracts/` with no `contracts/`
beside it. That workspace is not STALE, it is **unbuildable**: `docker buildx
build` fails on the missing `COPY`, and `preview.sh`'s friendly "this folder is
missing the toolchain's build recipe" message cannot fire, because
`resolve_build_context` only checks that the Dockerfile EXISTS — and it does.
A folder list that is merely incomplete produces a hard build failure with a
misleading diagnosis.

The fix, and the pattern worth copying: the list became DATA
(`contracts/toolchain.json` → `recipeFolders`), and `scripts/test_recipe_folders.py`
pins every carrier against it — including your `ToolchainMirror.cs` and
`Plantoir.csproj`, which it reads as TEXT. That is deliberate: one Python test
can pin a Swift list and a C# list, where a C#-only test could only ever check
its own half. The test was verified to actually fail when a copy drifts, which
is the check people skip. **If a recipe folder is added on either platform, add it to
`recipeFolders` and let the test tell the mac.**

**Rejected:** leaving the list in code and adding a comment (that is exactly what
was there, and it is what failed); and having each platform's own suite check
only its own copy (two green suites, still drifted).


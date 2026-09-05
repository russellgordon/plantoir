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
| [`shared-rules.json`](shared-rules.json) | Fourteen rule sets on top of machinery that could not be less alike: what a scheduled deploy refuses and in what order, what the sidebar's filter shows, what is stripped from the launchers' output, what counts as a curriculum expectation, **what is taken out of — and deliberately KEPT in — a problem report**, **which events every new or changed feature must record on the breadcrumb trail**, and **which local assistant a teacher may choose, what they are told it costs, and when one may be removed**, and **what a page is CALLED when the assistant talks about it**, **which folders count for marks**, **what a teacher is told when a folder a feature depends on has been renamed or deleted**, **how a working folder kept in sync by a cloud service is recognised, what a teacher is told about it, and when**, and **where a section's built website is kept, and what happens to a folder that already has one in the old place**., and **which processes belong to a section's preview, and must therefore be stopped**. |
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
  platforms. Match it to the character. Seventeen of the twenty-five are these.
- **`launcher`** — printed by `setup.sh` / `preview.sh` / `deploy.sh`, which
  have separately written `.ps1` counterparts. These **deliberately differ**:
  the mac watches for "Setting up this Mac" and Windows for "Setting up this
  PC". Seven of the twenty-five.
- **`elsewhere`** — printed by the Docker build or a tool; check by hand.

A mac test verifies the classification against the actual files, so a marker
that moves from a launcher into shared Python (or the reverse) fails here
rather than silently changing what Windows should be matching. Getting this
wrong crashes nothing: the progress bar simply stops moving, which reads as a
slow build.

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

- **Name the case so it is obviously a proposal** and say in
  [`MAC-HANDOFF.md`](../MAC-HANDOFF.md) that it is waiting — the ledger is
  where the mac side looks for work that arrived from Windows.
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
[`WINDOWS-HANDOFF.md`](../WINDOWS-HANDOFF.md), under "Do not re-derive the
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
gap nobody has looked at. Counts are test functions, taken 2026-08-16.

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
| Special folder names: what is blocked, what is confirmed, what a rename says and which keys it carries | `shared-rules.json` → `specialNames` | SharedRulesContractTests (24), SpecialFolderRenamer (22) |
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
| What a teacher is told when a folder a feature needs has gone | `shared-rules.json` → `siteHealth` | SiteHealthContract (5), SiteHealthFinding (11), and `scripts/test_site_health.py` |

**Not shared, and why.** Each of these is a deliberate decision, not an
oversight:

| Area | Tests | Why it stays local |
|---|---|---|
| Windows, sheets, layout, hit areas, fonts, chat bubbles | ~71 | Platform look and feel. The mac's numbers were measured against Messages; matching them on WinUI would produce something that looks foreign. What must be TRUE of the assistant's window is in `WINDOWS-HANDOFF.md`. |
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
`WINDOWS-HANDOFF.md` where Windows is told to copy it, it is four copies and
three of them were already drifting — the same deploy failure was told two ways
("that section's console" / "that section's window") depending only on which
function ran it. Now it is written once in `AssistWording`, and everything else
is generated from it or tested against it.

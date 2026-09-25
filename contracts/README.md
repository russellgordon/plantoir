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
| [`assist-wording.json`](assist-wording.json) | Every sentence the assistant says to a teacher about deploying, previewing, agreeing to things and changing the class pages themselves, with `{course}` and `{section}` where values go — and `{page}` / `{copy}` in the sentences about duplicating a class, which came in from Windows' `ClassChangeWording` on 2026-09-19. |
| [`assist-cases.json`](assist-cases.json) | The assistant's behaviour: which phrasings are matched in code rather than routed, which tools wait for a button, what must happen in what ORDER when it deploys, how the arrow keys walk the prompt history, and — for the one family whose variable part is a TIME — every spelling of "deploy at &lt;time&gt;" that is answered in code, every one that goes to the model, and which day a bare time means. |
| [`toolchain.json`](toolchain.json) | The image both platforms build from the same recipe: the four pins with the REASON each sits where it does, and what each of the seven Quartz patches changes and why it cannot be dropped. |
| [`example-content.json`](example-content.json) | The ready-made courses: how a payload is discovered, the manifest's keys, and the allow-list rule that decides what actually installs. |
| [`file-formats.json`](file-formats.json) | **The two files both apps WRITE and the Python then reads**: every `course_config.json` key with its type and default, and the frontmatter that decides whether students see a page — including the legacy `draft:` spelling, which means the opposite. Since #245 also the WORK LEASE file (`workLease`): the file under `courses/.internal/activity/` that says which process is doing what, in Windows' shape plus the mac's start-time line. |
| [`shared-rules.json`](shared-rules.json) | Twenty-nine rule sets (recounted 2026-09-25 with #245, by counting the file's top-level keys other than `note` — it read twenty-eight before #245's `workLeases`, while this line still said "Twenty-six"; the number said "Twenty" from before four of them existed, "Twenty-two" from before two more did, and "Twenty-four" while the file already held twenty-six; count the keys rather than trusting the word) on top of machinery that could not be less alike: what a scheduled deploy refuses and in what order, what the sidebar's filter shows, what is stripped from the launchers' output, what counts as a curriculum expectation, **what is taken out of — and deliberately KEPT in — a problem report**, **which events every new or changed feature must record on the breadcrumb trail**, and **which local assistant a teacher may choose, what they are told it costs, and when one may be removed**, and **what a page is CALLED when the assistant talks about it**, **which folders count for marks, and which a teacher is OFFERED when they are asked**, **what a teacher is told when a folder a feature depends on has been renamed or deleted**, **how a working folder kept in sync by a cloud service is recognised, what a teacher is told about it, and when**, and **where a section's built website is kept, and what happens to a folder that already has one in the old place**, and **which processes belong to a section's preview, and must therefore be stopped**, and **which of a course's own folders the build treats specially, and what a teacher is told about each**, and **what the New Course wizard's affirmative button says, what it tells a teacher whose course will start empty, and what its skeleton toggle does to the structure editor in BOTH directions**, and **what a window lets go of when it is pointed at a different working folder**, and **which act turns a scheduled deploy off without being asked, which acts deliberately turn none off, and how late is too late for one to still run**, and **what happens when a teacher copies one page of one course into another — what is never copied, what the copy's settings must say for it to arrive hidden from students, what is done when a picture of that name is already there with different bytes, and the two shapes where this app and the website builder would read a page differently**. |
| [`course-management.json`](course-management.json) | The names the three kinds of zip carry and how they are told apart, what section number is offered next and which entries are refused in whose words, the grade a course code names, and what happens to backups over time — which are pruned, how the space they take is counted, and what a delete of several removes and keeps. |
| [`class-planning.json`](class-planning.json) | Which page titles carry numbers, what "the next class" would be called, and — the highest-stakes data here — the ORDER renames must run in when room is made for a class. |
| [`schedule-rules.json`](schedule-rules.json) | How a teacher's own list of class dates is read: every accepted date form, how an ambiguous `08/09/2026` column is settled or asked about, what a pasted Google Sheet address becomes, and — `relativeDays` — which day a word like “tomorrow” or “Monday” names. |
| [`app-rules.json`](app-rules.json) | The app itself: what `deploy.sh` is asked to do for a given configuration, what a teacher is told about an Account ID or a custom domain they typed, how a failure's raw output becomes a sentence, whether a deploy must build first, the progress markers and **where each marker's text comes from**, the preview's ports, and **what a teacher is shown when a first publish stops to ask for a Netlify or Cloudflare credential**. |

## What is generated and what is written by hand

`assist-wording.json` is generated in full. `assist-cases.json` is mixed, and
the boundary is a TOP-LEVEL key — the file names them under `generated.keys`:

| Key | Comes from |
|---|---|
| `cardPhrasings` | `AssistCardCommand.fixedShapes` |
| `tools` | `AssistToolRunner.tools` / `.localTools` / `.mcpOnlyTools`, and each definition's `needsApproval` and `planTwinName` |
| `toolSchemas` | `AssistToolRunner.localTools` and `.mcpTools`, emitted as each client really sends them — every argument, every description. **This row was missing until 2026-09-10**; what its absence cost is under "Reading a red suite" below. |
| `nearMisses`, `scenarios`, `promptHistory`, `deployAtATime`, `windowBinding`, `hideIsUnpublish`, `echoedRequest` | **Hand-written intent.** The generator preserves them; nothing in the code says what a near miss is, or what ORDER events must happen in — those are decisions, and a decision lives in the `documentation/` page that owns its subject, with a GitHub issue pointing at it when the other platform owes work — the handoff documents that used to hold them were retired on 2026-09-08. |

In `app-rules.json` the same split applies: `milestones` is a readout of
`TaskMilestones` and `credentialRequests` a readout of `CredentialRequest` —
both overwritten; `deployArguments`, `configurationRules`, `previewPorts`,
`markerOrigins`, `launcherFlags` and `credentialPrompts` are authored and
preserved. The pair
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
(`TaskMilestones.exampleCourse`), but `AppRulesContract.milestones()` kept its
OWN array naming eight of the nine and did not list it — so the generated
`milestones` readout had eight tasks where the mac had nine. The mac's
classification test walks the READOUT, so a marker missing from it is invisible
to the test however loudly the shared script prints it, and the classification
is only as complete as the readout it is checked against.

**Closed on 2026-09-08** (issue #82). The readout is now built from
`TaskMilestones.allLists`, a single list of every task, rather than from a
second hand-kept copy of what to read — so it cannot omit a task that exists,
and `AppRulesContractTests.testEveryMilestoneListReachesTheReadout` pins the
readout to that list in case a future change reintroduces a private copy.

One hole is deliberately left open and is worth knowing about: a new
`static let` added to `TaskMilestones` and NOT added to `allLists` is still
invisible, because Swift cannot enumerate an enum's static properties at
runtime. Windows' `AllLists` has the identical gap. Adding a task means adding
it in both places, on both platforms.

## A change here is a handover, in whichever direction it travels

The generator runs on the **mac** — `Plantoir --write-contracts` — so Windows
cannot regenerate the derived halves. The AUTHORED halves are a different
matter and can be proposed from either side: `scenarios`, `nearMisses`,
`promptHistory`, `deployAtATime`, `windowBinding`, and every case list in the other four files
survive a mac regeneration untouched.

**Both directions work the same way, and the rule is one rule.** A change
committed to this folder makes the OTHER app's suite go red, because the other
app deserialises these files and runs them. That is the mechanism, and it is
the reason these files exist. But a red suite says only that something moved —
it cannot say who moved it, why, or what the other side is expected to build.
So the commit that changes a contract owes a GitHub issue labelled for the
other platform, opened in the same session, naming what changed and what they
have to do. `CLAUDE.md` rule 3 requires it going one way and rule 4 the other;
neither is optional, and neither is satisfied by committing the diff.

### Reading a red suite: four failures, three different causes

Worth walking through, because on 2026-09-09 a Windows session part-way
through unrelated work ran `dotnet test`, found four failures, and filed
[#146](https://github.com/russellgordon/plantoir/issues/146) reporting them as
one thing: the contract had moved with nobody told. They were not one thing.
Half of that report was wrong and half was right, and the useful lesson is in
which half was which.

**Two of them had an issue, and an unreadable failure.**
[#70](https://github.com/russellgordon/plantoir/issues/70) was open, labelled
`windows`, and named the card phrasings with the failure spelled out — *"Three
more card phrasings will make your suite red"*, and separately *"Your
`AssistCardCommandTests` will go red until the phrasing exists on your side"*
of the parsed `make room for ... at Unit 3, Day 4` family, which is what the
second of the two tests actually failed on. Rule 3 was followed exactly. But
both tests said `Assert.NotNull() Failure: Value is null` and nothing else, so
nobody meeting them had a phrasing, a tool or a term to search for. Those
assertions now name all three, and say that an unmatched contract phrasing is a
handover to look up rather than a bug to file.

**One had a perfect failure and no issue at all, and this is the half #146 got
right.** `AssistSurfaceContractTests` said as clearly as a test can that
`back_up_course`'s arguments had moved — *"must require exactly the arguments
the contract says it does. Contract: [course, section]; here: [course]"*. The
reader knew precisely what had changed, went looking for the issue explaining
it, and there was none.

The sequence is worth having exactly, because it is not the careless one it
looks like:

| When (local) | What |
|---|---|
| 18:54 | `0f34c54d` builds `back_up_course` on the mac, requiring `[course]` — the same shape Windows had had since 2026-08-13. Nothing diverges. |
| 19:14 | `b0913344` fixes a real defect in it: the copy was filed as the TEACHER's, so the Backups list credited them with a copy they never made and `pruneBackups` — which skips anything not the assistant's — would have kept every one for ever. The fix takes a `section` and attributes the copy. The schema moves. |
| 19:52 | #70 is opened. It names `back_up_course`, its plan twin and its briefing persistence. It does not mention the argument. |

So the thing that travelled unannounced was **a defect fix**, which is the
worst kind to travel unannounced: Windows had the identical defect, and found
it only because the contract went red and somebody chased it
(`GUI-IMPROVEMENTS.md` row 478). **The lesson is not "open an issue" — one was
open. It is that a fix made after the feature, in a separate commit, moves the
contract too, and the issue written afterwards describes the feature.**
`git diff contracts/` before writing it, and let the diff say what to list. It
did not help that no prose anywhere listed `toolSchemas` as a generated key;
the table above has it now.

**One belonged to nobody but this app** — a Windows test that had retyped a
contract value into a literal, so it failed when the contract GREW. No issue on
either platform could have named that, and `CLAUDE.md`'s "deserialise, don't
retype" is the whole of its diagnosis.

So, both ways round: **a red contract test mid-task is usually a handover, and
the open issues are the index — read them before writing a new one.** And when
you are the side that moved the contract, name every key that moved, because
the one you did not think worth mentioning is the one that arrives with no
explanation attached.

#### Named gaps: the handover whose fix belongs to a LATER release

The two shapes above both end in work: implement it, or fix the test that
retyped a value. There is a third, met on 2026-09-18 while getting `dev` green
for the v1.2.0 cut. The mac's unit-word rename ([#100](https://github.com/russellgordon/plantoir/issues/100))
had moved `shared-rules.json` — one new `activityTrail.mustRecord` event, one
new `specialNames.platformWording` key — and the Windows half is
[#158](https://github.com/russellgordon/plantoir/issues/158), milestoned
**v1.3.0**. So the handover had arrived, the issue naming it was open and
correct, and the work was deliberately NOT in the release being cut. Two tests
were red with nothing anybody was supposed to do about them yet.

Four ways out, and only the last is honest:

- **Soften the contract** — write `appliesOn: ["mac"]` on the event. This is
  the tempting one, because the machinery is already there and
  `ContractTests.SharedRules_ActivityTrailEvents_Exist` honours it. It is
  wrong twice. It is a LIE: `appliesOn` means a difference that is deliberate
  and permanent ("built site moved out of the working folder" is mac-only
  because Windows has never built inside the working folder, so there is no
  moment to record), and Windows owes this one. And it is a PERMANENT lie:
  `appliesOn` has no mend-check, so the day Windows built the event, the
  contract would still say it was none of its business, both suites would stay
  green, and nothing anywhere would notice. A contract softened to quiet a
  suite has given up the signal it exists to give.
- **Declare the thing and leave it empty** — on Windows, add the
  `ActivityTrail.Event` value with no call site. There is a precedent:
  `ItemExcluded`, `ItemReIncluded` and `RemovalBlocked` were declared with the
  site-health work for exactly this reason, and the comment beside them
  disclaims itself as precedent in as many words. Rejected here, and the
  difference is not tidiness — it was measured rather than remembered. All
  three were declared in `a3144010` at 08:17 on 2026-08-25 and all three got
  their first `ActivityTrail.Note` call in `a3c581fb` at 08:45 the same
  morning: **28 minutes**, inside one piece of work. This is a whole feature a
  milestone away. And an event
  that is named but never recorded tells the contract a line exists that no
  teacher's trail will ever carry — a green test asserting a trail that cannot
  happen, which is worse than a red one, because the next person asking "does
  Windows record this?" is told yes. `FolderProblemFound` sat dead for months
  that way.
- **Leave it red.** Then "did anything break?" stops having an answer, which
  is how four failures sat unnoticed on `dev` long enough to become #146.
- **Name the gap on the side that owes it.** `windows-app/Plantoir.Tests/NamedGapLedger.cs`
  holds one entry per key: the key, the issue, the MILESTONE, and the reason.
  Everything not in the ledger is asserted exactly as before. The ledger fails
  if a ledgered thing has started existing on Windows — saying to delete the
  entry — so it cannot outlive the fix; and fails if it names something the
  contract no longer carries, so it cannot outlive the requirement either.
  Modelled on `KnownToBeDropped` in `AssistSurfaceContractTests`, mend-check
  and all. Proved by mutation in the session that wrote it, three ways round.

**The boundary matters more than the mechanism.** An entry is allowed ONLY
when an open issue, milestoned LATER than the release being cut, owns the work.
Never for a difference a teacher can see at the current milestone — that is a
defect to fix or a release to hold, and a ledger entry there is a way of
shipping it quietly. Never instead of the issue, either: the entry names the
issue and the issue is where the work lives. If the issue closes, or gets
pulled into the release being cut, the entry goes and the full assertion comes
back on its own.

The ledger lives on Windows because that is the side that currently owes
something; there is no mac equivalent and none is needed until the mac is the
side behind. The same shape would work there.

**One exception has been taken to the passage above, on 2026-09-19, and it is
recorded here rather than argued in two places.** The quit-path work
([#220](https://github.com/russellgordon/plantoir/issues/220)) added
`quittingWhileWorkIsUnderWay` and the trail event `quit asked about work under
way` with `appliesOn: ["mac"]` — the softening the "four ways out" list rejects
by name. It was taken under a direct instruction, and the reasoning is worth
having rather than repeating the argument every time somebody finds it:

- **The honest alternative was not available to the mac.** Taking the event
  bare reddens `ContractTests.SharedRules_ActivityTrailEvents_Exist` with a
  failure only WINDOWS can mend, because a `NamedGapLedger` entry is theirs to
  write and nobody was on that side that week. A red suite nobody can turn
  green is the thing the ledger exists to avoid, reached by the other road.
- **The cost the list names is real and is not waived.** `appliesOn` has no
  mend-check: the day Windows asks this question, the contract will still say
  it is none of their business and both suites will stay green. What points at
  it instead is prose — the `appliesOnWhy` on both keys, which says to delete
  them, this paragraph, and the `windows` issue that carries the work. That is
  weaker than a test and everybody involved knew it.
- **The scope is narrower than it looks.** The OTHER three events that landed
  the same day (`website builder stopped`, `… left running`, `… could not be
  stopped`) are `appliesOn: ["mac"]` for the ordinary, permanent reason and are
  not part of this exception: a native Windows toolchain has no container and
  no virtual machine, so `FolderContainers.StopContainer` and
  `.ReleaseEverythingAtQuit` both return immediately there, and there is no
  moment to record. That is the same case as `built site moved out of the
  working folder`.

If this shape is taken a second time, stop and build the mend-check instead —
one precedent is an exception, two is a practice.

## Proposing a case from the Windows side

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
- **Do not touch the generated keys.** Those are readouts of mac code; an edit
  there is overwritten on the next regeneration and the diff looks like
  vandalism. **Which keys those are is written in each file's own
  `generated.keys`, and that is the copy to read** — a list typed into prose is
  the one that stops being true. Three places said "`cardPhrasings`, `tools`,
  `milestones`" until 2026-09-10: two keys of one file plus one key of another,
  missing both `toolSchemas` (where a tool's arguments live) and
  `credentialRequests`.

  **Only the two MIXED files carry that key**, because it exists to mark a
  boundary: `assist-cases.json` and `app-rules.json` are part generated and
  part authored, so they say where the line falls. `assist-wording.json` has no
  `generated` block because it is generated in FULL and says so in its `note`;
  the seven authored files have none because there is no generated half to
  mark. So the question "is this key generated?" is answered by
  `generated.keys` in exactly the two files where it can be asked.

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

That diff is how the change TRAVELS, and the issue is how the other side finds
out — see "A change here is a handover" above. Committing one without opening
the other leaves a suite that goes red for reasons its reader has no way to
look up.

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
| What a publish with nobody at the computer must REFUSE | `app-rules.json` → `launcherFlags.nonInteractive` | `scripts/test_deploy_non_interactive.py` (13), which READS the launcher; `scripts/test_deploy_sh_questions.py` (15), which RUNS it to every question the key names and fails if the two lists come apart; `scripts/test_preview_sh_questions.py` (13), which does the same for `preview.sh` — the BUILD leg a scheduled publish runs first — and also checks every prompting `read` in that launcher is guarded, which catches a question added without a contract entry. It IMPORTS the deploy file's harness (the bash probe, the byte-encoded stdin) rather than copying it, so renaming that file or excluding it from a suite breaks this one. The flag itself is asserted by AppRulesContractTests via `deployExtras` and, for `preview.sh`, via `launcherFlags.preview` |
| What a teacher is told when a publish set to happen on its own did not get through | `shared-rules.json` → `scheduledPublishStopped` | ScheduledPublishOutcome (16), SharedRulesContract (2). Its fifth kind, `tooLateToRun`, arrived 2026-09-20 with [#236](https://github.com/russellgordon/plantoir/issues/236) and reddens Windows until they say whether their task runs a missed start late — see the row below |
| Which act turns a scheduled deploy off without being asked, which acts deliberately turn none off, and how late is too late for one to still run | `shared-rules.json` → `scheduledDeployCancellation` | ScheduledDeployCleanup (25 on the mac, of which four walk the file's own lists: nine cancellation cases, ten lateness cases, seven stored-value cases and every sentence). Added from the mac 2026-09-20 ([#236](https://github.com/russellgordon/plantoir/issues/236)). **No Windows reader yet**, and the suite there stays GREEN rather than going red, because it deserialises `shared-rules.json` by NAMED key and a new top-level key nobody asks for is silently ignored — the same precedent as `gradedFolders.removingAFolder` and `workingFolderSelection`. What DOES go red there is the trail event `scheduled deploy turned off`, `scheduledPublishStopped.kinds.tooLateToRun`, and `file-formats.json`'s new `scheduled_deploy_may_run_late_days`. Half the rule is already theirs: `CourseArchiver.cs` cancels on removing a SECTION and not on removing a COURSE. Read `howToRunACase` before wiring the runner — six cases are played through a real removal, rename or rollover and three are a scan of a file that must not have learned to cancel |
| Validation messages | `app-rules.json` → `configurationRules` | CourseConfiguration (10), CustomDomain (4) |
| Progress milestones and marker origins | `app-rules.json` → `milestones`, `markerOrigins` | TaskMilestone (12) |
| Failure explanations | `app-rules.json` → `failureExplanations` | FailureExplainer (10) |
| Special folder names: what is blocked, what is confirmed, what a rename says, which keys it carries, and how the new name is SPELLED inside a link | `shared-rules.json` → `specialNames` | SharedRulesContractTests (24), SpecialFolderRenamer (22), FolderPathRewriterTests (2) |
| What a teacher reads under the four Content Structure lists | `shared-rules.json` → `specialNames.contentStructureTip` | `SharedRulesContract` (3 functions, plus one further assertion inside `testSpecialNamesSentencesMatchContract`). Proposed from Windows 2026-09-07 and adopted here 2026-09-09 ([#72](https://github.com/russellgordon/plantoir/issues/72)); Windows' wording won, widened to “folders and files”. **Not counted in the `SharedRulesContractTests (24)` row above**, which is left as it stands. Whether a teacher can SEE it is checked on Windows (`CourseSettingsCaptionUiTests`) and NOT here: an XCUITest was tried and reached this caption in one run of four, so the mac's on-screen half is the source scan's deletion guard — `documentation/09-mac-app.md` says what went wrong and which part is worth fixing. Two of the four go beyond the string: the entry must carry no `reason` key — pinned on the side that authors this file, because the cost lands on Windows, whose `NoBlockedSentenceInTheContractIsUnusedHere` sweeps every top-level `reason` — and `CourseSettingsView` must actually DRAW the constant, measured by mutation, because the other three stay green when the line that renders it is deleted. |
| Which of a course's OWN folders the build treats specially, and what the sheet says about each | `shared-rules.json` → `specialFoldersHelp` | SpecialFoldersHelpContract (5) on Windows, SpecialFoldersHelpTests (5) on the mac — both sides adopted 2026-09-06 |
| Which folder holds class pages, and which count | `class-planning.json` → `classFolder` | ClassFolderContractTests (6), and `scripts/test_class_folder.py` |
| What a course calls a unit | `class-planning.json` → `pageNaming` (the `term` field) and `file-formats.json` → `unit_word` | ClassPageTerm (11), and `scripts/test_class_pages.py` |
| Renaming that word after the course is in use: which pages move, what refuses it, how links follow, and the order it happens in | `class-planning.json` → `renamingTheUnitWord`; the sentences in `shared-rules.json` → `specialNames.renameUnitWord`; the trail line in `activityTrail.mustRecord` | ClassPlanningContractTests (3), SharedRulesContractTests (1), UnitWordRenamerTests (19) on the mac — added 2026-09-10, [#100](https://github.com/russellgordon/plantoir/issues/100). **Windows runs none of it today**, and the three places differ: the trail event and `renameUnitWord.explanation` were red there and are now NAMED GAPS ledgered to [#158](https://github.com/russellgordon/plantoir/issues/158), v1.3.0 (`windows-app/Plantoir.Tests/NamedGapLedger.cs` — see "Named gaps: the handover whose fix belongs to a LATER release" above); `renamingTheUnitWord.cases` (seven) and `linkCases` (three) were never red there because **nothing on that side runs them at all** — there is no Windows counterpart of `ClassPlanningContractTests.testRenamingTheUnitWordCases`, so those ten cases are unrun rather than failing, and they are owed under #158 with the renamer itself. Deliberately not pinned by a test counting them: a count asserted where the cases are not run would guard the number instead of the behaviour |
| Whether a deploy must build first — including something saved AFTER the build that made the site started (#265), judged from the `.build-started` file the build leaves beside the site | `app-rules.json` → `buildFreshness` (`rules`, `buildStartedMarker`) | BuildFreshness (11), `ScheduledPublishOutcomeTests` (the overnight run's own shell, 2), `scripts/test_build_started_marker.py` (the build's side — run by verify.sh and Windows' `PythonToolchainTests`). Windows' own `BuildFreshness` does not read the marker yet |
| How a date or title is rewritten when its value continues below the key, and what the site then reads (#199) | `file-formats.json` → `datesAndTitles.writingCases` | `FileFormatsContractTests.testTheDateAndTitleWritersTakeAKeysWholeValue` (13 cases, bytes); `scripts/check_dates_and_titles_against_the_site.py` in the image (verify.sh) checks every `expectSiteReads` against the real `process_frontmatter` |
| Preview ports and the websocket offset | `app-rules.json` → `previewPorts` | PreviewLease (7) |
| Where the preview's address comes from — captured as output arrives, never guessed — and what happens when none was announced (#235) | `app-rules.json` → `previewPorts.announcedAddress`, `previewPorts.whenThePreviewNeverAppears.whenNoAddressWasAnnounced` | ScriptRunnerPreviewAnnouncementTests (10, on a real first preview's output), PreviewReachabilityTests (6 for this), and `scripts/test_preview_address.py` (8 — the launcher's own refusal, run with docker stubbed; verify.sh and Windows' PythonToolchainTests, which skips its bash half where there is no bash). Windows' own collector has no carry-over yet |
| The browser-safe address | `app-rules.json` → `linkRules` | BrowserSafeURL (2) |
| Asking for a publishing credential | `app-rules.json` → `credentialRequests`, `credentialPrompts` | AppRulesContract (3) |
| `course_config.json` keys, types, defaults | `file-formats.json` → `courseConfigKeys` | CourseConfiguration (10) |
| What a `hidden` entry MEANS in the built sidebar (a top-level item by its stored name), and that the build never changes the list (#265) | `file-formats.json` → `sidebarHiding.matchRule`, `sidebarHiding.buildKeepsHidden` | `scripts/check_sidebar_hiding_against_the_site.py` (10 cases through Quartz's own `FileTrieNode`, in verify.sh), `scripts/test_sidebar_hiding.py` (the 5 preflight cases, and the repair — run by verify.sh and by Windows' `PythonToolchainTests`) |
| What a Save writes when another window or a build changed the settings file first, what Course Settings says when a preview or publish cannot see the Save or when the Save replaced another window's sidebar change, and when Preview Again has nothing left to reach (#265) | `shared-rules.json` → `savingSettings`, `specialNames.settingsSavedWhilePreviewing`, `settingsSavedWhilePublishing`, `previewUsesSavedSettings`, `settingsSaveReplacedSidebarChange`, `settingsPreviewAgainNothingOpen` | `SettingsSaveNoticeTests` (the 5 cases through `CourseConfiguration.merged`, the five sentences), `TwoWindowSettingsTests`. Not yet run on Windows |
| Page visibility: `publish:`, legacy `draft:`, per-section keys, and WHAT EACH VALUE MEANS | `file-formats.json` → `pageVisibility` | ~50 tests across the suite, plus 56 `readingCases` and 13 `writingCases` run as data by `FileFormatsContractTests`, `PageVisibilityReadingTests` for the three-way answer (33 on the mac; its Windows twin of the same name, plus `PageVisibilityWritingTests`, `PageVisibilityCertaintyTests` and `SectionCarryVisibilityTests`, since 2026-09-19), and `scripts/test_page_visibility.py` for the Python. The writing half has been RUN only since 2026-09-09 (issue #107), and its absence is how the mac stayed green for two days against a rule it did not implement; **on Windows it has been run since 2026-09-19** ([#138](https://github.com/russellgordon/plantoir/issues/138)), by `FileFormatContractTests.TheWritingCasesInTheContractAreFollowed`, which plays every one of them against `PageFrontmatter.SetDraft` and collects every failing case rather than stopping at the first — until that day it answered `writingRules` with five of the cases retyped into the test file. Three of the other five were already asserted elsewhere in that suite in its own words (`PageVisibilityWritingTests` for the two odd values, `TheRulesForWritingAPagesVisibilityAreFollowed` for a page with no frontmatter); what the loop adds is that every case is read from the FILE and so cannot drift from it (ten on the day; thirteen since #176), and that two — a block carrying neither spelling, and an oddly-worded `published` asked to be HIDDEN — are covered there for the first time. **Two things this list deliberately does NOT carry**, added 2026-09-18 with issue #140: the forms each app reads as `cannot tell` (a value on the next line, a tag, a block scalar, an anchor or alias, a flow collection, an indented key, unparseable frontmatter) — a shared case states what the SITE does, and each app's REPORTING answer for those is `visible` whatever the site does, so pinning one here would oblige the other platform to be wrong in the same direction; those live in each platform's own tests. **With one deliberate exception since 2026-09-19** ([#176](https://github.com/russellgordon/plantoir/issues/176)): the test is not whether the reader can read a form but whether its REPORTING answer matches the site, and for the two continuation forms the site PUBLISHES (`publish: false` over an indented `false`, with and without a blank line between) it does — so those two ARE carried, and they earn it because the reader that got them wrong got them wrong confidently, which turned a writer's already-right gate into a no-op on "hide this page". And YAML trivia with no teacher behind it: `y`/`n` are here because somebody might type them, sexagesimals and octals are not. `scripts/check_visibility_against_the_site.py`, run by `verify.sh`, re-measures every case here down the real build chain — and twenty-five more forms that CANNOT be shared cases, because both readers report them as visible whatever the site does and the refusal is only justified while the measurement holds — so the LIST being wrong fails rather than making both apps confidently wrong together |
| Image pins and the Quartz patches | `toolchain.json` | checked against `Dockerfile` and `patches/` |
| Example-content payloads (all 38) | `example-content.json` | ExampleContent (10), and the payloads themselves |
| Reading a teacher's date list, and which day “tomorrow” or “Monday” names | `schedule-rules.json` | SectionScheduleSource (23) |
| Scheduled-deploy refusals | `shared-rules.json` → `scheduledDeployRefusals` | ScheduledDeploy (23) |
| Sidebar filtering | `shared-rules.json` → `sidebarFilter` | CourseFilter (9) |
| Stripping the launchers' output | `shared-rules.json` → `transcriptStripping` | TranscriptBuilder (6) |
| What counts as a curriculum expectation | `shared-rules.json` → `curriculumRules` | AssistCurriculumMentions (11) |
| What is taken out of a problem report | `shared-rules.json` → `problemReportRedaction` | ProblemReport (17), SharedRulesContract (2) |
| What the breadcrumb trail must record | `shared-rules.json` → `activityTrail` | ActivityTrail via ProblemReport, SharedRulesContract (2) |
| A working folder a cloud service keeps in sync: how it is recognised, what is said, when | `shared-rules.json` → `cloudSyncedFolders` | CloudSyncedFolder (18), CloudSyncNoticeLayout (5) |
| Where a section's BUILT WEBSITE is kept, and what happens to a folder that already has one | `shared-rules.json` → `buildOutputLocation` | BuildOutputLocation (22), SharedRulesContract (2), and `scripts/test_build_output_link.sh` in `verify.sh` (22 checks) |
| When quitting asks the teacher first, and when it must NEVER ask | `shared-rules.json` → `quittingWhileWorkIsUnderWay` | QuitConfirmation (7) on the mac. **`appliesOn: ["mac"]` for now, and deliberately not for ever** — an acknowledged exception, recorded under "Named gaps" above rather than argued here: added 2026-09-19 with [#220](https://github.com/russellgordon/plantoir/issues/220), when nobody was working on Windows, and `appliesOn` has no mend-check. Its eight cases (three added 2026-09-23 with [#232](https://github.com/russellgordon/plantoir/issues/232), for a preview being BUILT) are platform-neutral apart from the signal that says the system is logging out; **no Windows reader today**. The matching trail event `quit asked about work under way` carries the same `appliesOn` and is part of the same exception — adopt the rule and that line together, then delete BOTH `appliesOn` keys. The other three events that landed the same day are mac-only for the ordinary permanent reason (a native Windows toolchain has nothing to stop) and are not part of this |
| When the report asks about the assistant, and what it is called | `shared-rules.json` → `problemReportDialog` | SharedRulesContract (2), ProblemReport (2) |
| Which assistant a teacher may choose, the caution, and when one may be removed | `shared-rules.json` → `assistantModelChoice` | SharedRulesContract (5), AssistantSettings (22) |
| What a page is called when the assistant names it | `shared-rules.json` → `pageNaming` | SharedRulesContract (2), AssistPageNaming (7), AssistToolRunner (2) |
| Dating the pages a class brings when it is published | `class-planning.json` → `datingPagesAClassBrings` | ClassPlanningContract (3), AssistToolRunner (10). Its `reachStopsAtAClassPage.cases` (2) arrived 2026-09-19 with [#173](https://github.com/russellgordon/plantoir/issues/173) and has **no Windows reader** — see the census table below |
| Dating them on EVERY BUILD, in the teacher's own files, per section (#275, #276) | `class-planning.json` → `datingPagesAClassBrings.atBuildTime` (`cases`, `writingCases`) | `scripts/test_dates_follow_the_class.py` — in the image by `verify.sh`, and on Windows by `PythonToolchainTests`, which discovers it (it needs `python-frontmatter` on that interpreter, as `test_class_folder.py` already does). AUTHORED. DIRECT links only — a page reached only through another shared page keeps its own date (the hub case). Shared Python, so both platforms get the behaviour from one implementation; every case is built twice and the second build must rewrite nothing. The trail line it feeds is `shared-rules.json` → `pagesDatedByTheBuild` (PagesDatedByTheBuildTests on the mac; **owed on Windows**: reading the `PLANTOIR_DATED:` line, keeping it out of the console, and the trail event) |
| What publishing and unpublishing do to linked pages, and what is never swept | `shared-rules.json` → `followingLinks` | SharedRulesContract (3), AssistToolRunner (9). Its `stopsAtAClassPage.cases` (3) arrived 2026-09-19 with [#173](https://github.com/russellgordon/plantoir/issues/173) and has **no Windows reader** — see the census table below. The three `publishing` booleans stay TRUE and both suites assert them: the walk is still transitive, it has one stop |
| Whether the assistant asks before changing anything, and when it says so | `shared-rules.json` → `assistantConfirmation` | SharedRulesContract (1), AssistPlanMode (6), AssistantSettings (6) |
| Phrasings matched in code, including the six PARSED families | `assist-cases.json` → `cardPhrasings` | AssistContract (1), AssistPromptShelf (2), AssistToolRunner (4), AssistScenario (1, walking `parsed`) |
| What a section's assistant window does with the `course` and `section` the MODEL filled in: which arguments run, and which turns are refused | `assist-cases.json` → `windowBinding` | AssistWindowBinding (1 test walking all 8 cases, plus 12 of its own) on the mac. AUTHORED, arrived 2026-09-19 with [#202](https://github.com/russellgordon/plantoir/issues/202) — the mac half of [#180](https://github.com/russellgordon/plantoir/issues/180) — and has **no Windows reader**: their scenario grammar cannot script a model's tool call, so this is unrun rather than red there. See the census table below. The rule in one sentence: the SECTION is always the window's, the COURSE is the window's or the turn is refused, and both are gated on the tool's own schema declaring the argument |
| The spellings of "deploy at &lt;time&gt;" that are answered in code, the ones ASKED about in code (morning or evening? — [#194](https://github.com/russellgordon/plantoir/issues/194)), the ones that go to the model, and which day a bare time means | `assist-cases.json` → `deployAtATime` | ScheduleDeployCard (13), and `research/ai-assist/trimmed-surface-suite.py`, whose own interception guard is checked against these rows before it measures anything — a guard that went one family stale scores a routing result for a sentence the app never routes. AUTHORED, and the one `cardPhrasings.parsed` cannot carry: a family whose variable part is a TIME needs its spellings written out, or one example becomes one spelling |
| The spellings of "hide &lt;page&gt;" and "unpublish &lt;page&gt;" that are answered in code, and the ones that go to the model | `assist-cases.json` → `hideIsUnpublish` | HideIsUnpublishCard (5), `AssistPromptShelfTests` for the shelf card it took out of the routing measurement, and `research/ai-assist/trimmed-surface-suite.py`, whose interception guard is checked against these rows before it measures anything. AUTHORED, arrived 2026-09-19 with [#215](https://github.com/russellgordon/plantoir/issues/215). The measurement behind it: the smaller assistant answered "hide unit 4, day 21" with NO tool at all in five phrasings out of five, while answering the same request worded "unpublish" correctly every time. Two rows carry decisions rather than spellings — `publish unit 4, day 3` is REFUSED (the day arm is gated on the verb), and `hide unit 4, day 21 in ICS3U` is refused because a matched card binds the session's own course unconditionally |
| What the app does when the model's whole reply is the teacher's own sentence handed back | `assist-cases.json` → `echoedRequest` | AssistEchoedReply (1 test walking all the cases, plus 7 of its own driving the real agent through the engine seam). AUTHORED, arrived 2026-09-19 with [#215](https://github.com/russellgordon/plantoir/issues/215), and it has **no Windows reader** — see the census table below. The rule in one sentence: no tool call, and the reply equals this turn's own user message (case-folded, edge punctuation trimmed, compared against the message as SENT and against the sentence the teacher typed) — whereupon the turn is refused, `wording.didNotFollowThat` is said, and the turn is wound back out of the conversation, because the measured fault is not one dead turn but every turn after it |
| That the card for an IMMEDIATE deploy says it is immediate | `shared-rules.json` → `assistantConfirmation.theImmediateDeployCardSaysItIsImmediate` | SharedRulesContract (1). A property of `wording.deployApproval` rather than the sentence, so it outlives the next rewording |
| The New Course wizard's affirmative button | `shared-rules.json` → `wizard` | SharedRulesContract (1). On Windows the label is asserted only in `Plantoir.UiTests/NewCourseWizardUiTests`, which carries `[UiFact]` and runs only under `PLANTOIR_UI_TESTS=1` — so it is part of no gate there ([issue #119](https://github.com/russellgordon/plantoir/issues/119)) |
| WHEN a skeleton is offered at all, what the wizard's skeleton toggle does to the structure editor, both ways, and what a teacher whose course will start empty is told | `shared-rules.json` → `wizard.skeletonToggle`, `wizard.noExampleContentNote`, `wizard.noStartingContentNote`, `wizard.skeletonToggleLabel` and its four siblings | SharedRulesContract (5, including the seventeen cases and the vocabulary pinned against `WizardDefaults`), WizardStructure (15). Proposed FROM the mac 2026-09-18 ([#77](https://github.com/russellgordon/plantoir/issues/77)), copying behaviour Windows shipped 2026-09-07 — so this is the rare case where the contract arrives AFTER both apps agree, and **the Windows suite stays green rather than going red**: nothing there deserialises the key yet, and what they owe is the test plus a seam to run it against (their restore is private to `NewCourseDialog`). Whether a teacher can SEE it is the mac's `QuartzTeachersUITests.testDecliningTheSkeletonPutsTheDefaultFoldersBack`, which drives the real toggle and is part of no gate |
| Handing one course to an assistant the teacher already has: "Revise with Claude…", "Revise with Codex…" | `app-rules.json` → `outsideAgents` | AppRulesContract (1 test walking both doors), CodexLauncher (10), ClaudeCodeLauncher (10) on the mac. AUTHORED, arrived 2026-09-19 with [#205](https://github.com/russellgordon/plantoir/issues/205), which added the Codex door — and it is the first contract data EITHER door has ever had. Its `agents` (2) has **no Windows reader** — see the census table below. The Claude half describes what both apps already do, so it is a readout of agreement rather than a request; the Codex half is what Windows owes. Two divergences are named in the data rather than left to be discovered: the mac hands over a `.command` script where Windows passes the command line to `wt.exe` (`macHandsOverWith`, separate from `writesForTheConnection`), and Windows' Claude door records nothing on the trail where the mac's records `trailLine` |
| Backup, archive and wizard zip names | `course-management.json` → `zipNames` | BackupItem, ArchivedItem (18), ArchiveStamp (8) |
| Whether a zip's stamp could be TRUE — the rule that decides what gets deleted | `course-management.json` → `zipNames` → `couldHaveBeenStamped` | `CourseManagementContract` (the two bounds and 10 cases). Proposed from the mac 2026-09-10 with [#160](https://github.com/russellgordon/plantoir/issues/160). ASCII digits read as Gregorian throughout, so the list means the same thing under `en_US_POSIX` and `CultureInfo.InvariantCulture` — unlike the mac's own migration below, which is why one is shared and the other is not. Windows indexes `zipNames` by key name, so its suite stays GREEN until [#161](https://github.com/russellgordon/plantoir/issues/161) wires it up. **The guard itself is no longer missing there**: #161's first half landed on `dev` on 2026-09-19 (`Plantoir.Core/Models/ArchiveStamp.cs`, GUI row 490) with the same two bounds held by a test of its own, `CouldHaveBeenStamped_BoundsAreTheOnesTheMacUses`, which their part 2 replaces with this list. |
| The MOMENT a recognised zip name is read as | `course-management.json` → `zipNames` (the `moment` per case) | `CourseManagementContract` (4 cases). Added from the mac 2026-09-10 with [#160](https://github.com/russellgordon/plantoir/issues/160), which found the mac writing that stamp in the MACHINE's calendar — `2569-08-09_141530` on a Buddhist Mac. Windows has always been right about it (`CultureInfo.InvariantCulture`) but asserts the value nowhere yet, so its suite stays GREEN rather than going red; [#161](https://github.com/russellgordon/plantoir/issues/161) asks for it. Take the moment apart with a GREGORIAN calendar: re-spelling it with the app's own writer is a round trip that stays green while writer and reader are wrong together, which is the state the mac was found in. |
| Adding a section: suggestion, refusals, wording — and the keys it adds to every course-level page, whatever the page's fence and line endings (#175) | `course-management.json` → `sectionNumbers` (`addingKeysToAPage` for the last) | SectionAdder, SectionNumbersValidation (21); `CourseManagementContractTests.testAddingASectionsKeysToAPageIsWhatTheContractSays` (7 cases, compared as bytes) |
| Grade labels from a course code | `course-management.json` → `gradeLabels` | SectionAdder |
| What happens to backups over time, how the space they take is counted, and what deleting several removes and keeps ([#242](https://github.com/russellgordon/plantoir/issues/242)) | `course-management.json` → `backups` | CourseManagementContract (4: the rules, `pruneCases` 3, `sizeCases` 2, `deleteCases` 3), BackupSpace (10). AUTHORED, arrived 2026-09-25. The rules in one sentence: the assistant keeps its five, a teacher's backups are never pruned, Media is always included, the size is the LOGICAL one, and a delete never removes the backup an open assistant conversation restores from |
| Who counts as ALIVE behind a work lease, what a lease file holds, and one import of a course at a time — the loser refused, never tidying the winner's work away ([#245](https://github.com/russellgordon/plantoir/issues/245)) | `shared-rules.json` → `workLeases.liveness`; `file-formats.json` → `workLease`; `shared-rules.json` → `referenceCourses.importing.oneImportPerCourseAtATime` | `WorkLeaseLivenessTests` (19 liveness cases against the pure `ProcessLiveness.decide`, 7 lease bodies, 9 claim cases through the REAL `ReferenceStaging.claim`), `ReferenceImportTests` (6 in `ReferenceImportLeaseEdgeTests.swift`, all proven to fail on the code before #245). AUTHORED. `workLeases` is the block #156 adds its build/preview/publish rules to, rather than a second reader |
| Naming, numbering, making room | `class-planning.json` | ClassPlanning (13), NextClass (13) |
| A numbered course (#267 — a club's “Week 1”): its cases in `pageNaming`, `nextClass` (incl. a DATED case in CODING's shape: `existingClasses`, `timetable`, `expectDate`), `insertion` (incl. `numberedPosition`; CODING's sparse dates at a gap, at an existing number and a collision run — `expectAddedOn`, `expectNoMoves`), `duplication` (incl. into a gap), `refusals`, `numberedClassOrder.numberedScheme`, the new `wholeUnit` list, and `insertion.positionInSentences` (#268); the wizard's choice in `shared-rules.json` → `wizard.clubToggle` | `class-planning.json`, `shared-rules.json` | ClassPlanningContractTests, NumberedCourseTests, ClubFillTests on the mac. **Windows runs the old runners**: a case carrying `"scheme": "numbered"` read through the Unit/Day parser should go RED there (not run from the mac) — that is the request, owed under the #267 Windows issue, and `wholeUnit` + `numberedPosition` + `clubToggle` are new lists nothing there reads yet. |
| Which line of a section's front page is repointed: the embed is found by the CLASS PAGE it names, never by the heading above it; what happens when there is no class embed at all (#267) | `class-planning.json` → `sectionIndexPointer` | `ClassPlanningContractTests.testTheFrontPageIsRepointedAsTheContractSays` on the mac (9 cases). AUTHORED. Its `dateCases` (9, #275) pin the front page's DATE: every case is run by the build (`scripts/test_dates_follow_the_class.py`, both platforms), and the seven with a `pointAt` by the mac's pointer (`testTheFrontPagesDateFollowsTheClassItShows`) — owed by Windows' pointer, with `expectCreatedDayOnWindows` where it inserts an embed. The one place two platforms are ALLOWED to differ, and both answers are data: where no line transcludes a class page the mac leaves the page alone (`expectBody: null`) and Windows inserts the embed under the course's own heading (`expectBodyOnWindows`). **Windows goes RED** on the club's heading, CODING's hand-made h2, the front page with no heading, and "Help Sessions" directly under the heading — `SectionIndex.cs` finds the embed by the literal "# Most Recent Class" and takes the first `![[` below it; that is the request |
| What a club's assistant says: every teacher-facing sentence that says "class" has a `…ForAMeeting` twin (#267) | `assist-wording.json` → the `…ForAMeeting` keys and their twins | GENERATED. `ClubNounTests` (11) on the mac: the twins exist and say "meeting", the noun never reaches a tool result's `detail`, the club shelf is matched in code. 30 pairs, 65 → 125 keys, no existing value changed. The one-number make-room card family reads the window's course: `cardPhrasings.parsed` marks it with `inANumberedCourseWhosePagesAre`, and a runner passes that word to its matcher for the example and the near miss; `nearMisses` is walked twice, without a course and in a “Week N” club (#267 fix round). Windows' wording runner goes red on every new key until its sentences exist; the club card phrasings are new rows in `assist-cases.json` → `cardPhrasings` |
| Duplicating a lesson as the next class: where the copy lands, what else moves, how many other classes the plan card says move, whether undo is offered, and that the copy starts hidden | `class-planning.json` → `duplication` | **Both platforms**: `ClassPlanningContractTests.Duplication_MatchesContract` on Windows, `ClassPlanningContractTests.testDuplicatingMatchesTheContract` on the mac — all three cases plus `forcedUnpublished` and `undoRule`, driven through the real tool and asking for the undo the way a teacher does rather than reading it off a list. Proposed FROM Windows 2026-09-18 ([#149](https://github.com/russellgordon/plantoir/issues/149)). The second case — “a later unit re-dated is enough to withhold the undo, even with nothing renamed” — was RED on the mac the first time its runner ran, because `AssistToolRunner` keyed the duplicate's undo on `renames.isEmpty` alone; [#163](https://github.com/russellgordon/plantoir/issues/163) widened it to `ClassInsertionPlan.movesAnythingElse` on 2026-09-19, and putting the old gate back still turns exactly that case red. That is the handover working rather than damage, and `undoRule` carries the reasoning. `expectOtherClassesMoving` was added from the mac in the same piece and Windows' loop does not read it yet. |
| Which folders count for marks | `shared-rules.json` → `gradedFolders.cases` | `scripts/test_graded_folders.py` in the image. **The mac runs this list nowhere and cannot**: it stores `graded_folders` and never asks whether a given PAGE counts, which is the build's question. It does run three other lists under `gradedFolders` — see the rows below; this row said "runs no case list yet" of the whole key until 2026-09-09, by which time that was true only of `.cases`. |
| What a removal does to the marks pool | `shared-rules.json` → `gradedFolders.removingAFolder` | `GradedFolderChoices` (7 cases), played through Course Settings in the order it really happens. Proposed FROM the mac 2026-09-09 and **run on both platforms since 2026-09-18** ([#142](https://github.com/russellgordon/plantoir/issues/142), where Russell settled that Windows adopts the rule): Windows plays the same cases through one Core method, `FolderRemoval.RemoveFolderFromCourse`, because the ORDER is the rule and an order left in the view can be pinned by no test there. Four of the first six used to fail there; putting that body back still turns exactly those four red. **The seventh came the other way**, FROM Windows as [#172](https://github.com/russellgordon/plantoir/issues/172) on 2026-09-19: a name still offered in another capitalisation keeps its place. It was RED here until `dropFromMarksPool` stopped asking with exact `contains`, and, read off Windows' code, green there unchanged (their local test already pins the same page) — the handover working as it is meant to. |
| What a teacher reads on the Marks control — its title and the caption below it | `shared-rules.json` → `gradedFolders.wording` | `SharedRulesContract` (4). Proposed from Windows 2026-09-08 and adopted here 2026-09-09 ([#71](https://github.com/russellgordon/plantoir/issues/71)); the mac’s TITLE won unchanged, so only the caption moved. **Not in `GradedFolderChoicesTests` with the other `gradedFolders` rows**, which is scoped to what the checklist OFFERS and builds a fixture tree in `setUp` these have no use for. Three of the four go beyond the strings: the caption may name no action this control lacks (whole words — "addresses" is not a use of "add"), both views must draw from the one constant with no third copy anywhere in the product source, and the caption must be drawn BELOW its list, which is what `wording.rule` requires by name. Each was measured by mutation rather than assumed. |
| Which folders the marks checklist OFFERS | `shared-rules.json` → `gradedFolders.choices` | `GradedFolderChoices` (14 cases, the depth cap and the skip list), against real directory trees — a walk over a fixture is not a walk. Proposed from Windows 2026-09-06 and run on the mac since 2026-09-09 (issues [#79](https://github.com/russellgordon/plantoir/issues/79) and [#112](https://github.com/russellgordon/plantoir/issues/112)); both platforms now go red for it. |
| What a window lets go of when it is pointed at a different working folder | `shared-rules.json` → `workingFolderSelection` | `SharedRulesContract` (1, running all four cases), `WorkingFolderSelection` (8), `WindowRestorationScenario` (2 of its 8). **Run on BOTH platforms since 2026-09-19**: Windows plays the same four cases through `SharedRuleContractTests.AWindowLetsGoOfTheOldFoldersSelectionAsTheContractSays`, against a `Plantoir.Core.Models.WindowFolderState` — the rule and the selection type moved down into Core for exactly this reason, since `Plantoir.Tests` cannot reference the WinUI project and so could gate nothing while both lived there. Added from the mac 2026-09-18 ([#93](https://github.com/russellgordon/plantoir/issues/93), handed over as [#162](https://github.com/russellgordon/plantoir/issues/162)), where Windows had the identical defect and the suite stayed GREEN because this file deserialises `shared-rules.json` by NAMED key and a key nobody asks for is silently ignored — the same precedent as `gradedFolders.removingAFolder` above. Read `howToRunACase` before touching the runner: each case needs its OWN folders (one of them deletes a course), and `then.removeTheSelectedCourseAndReload` and `expectNamesALoadedCourse` are what pin the “Course Not Found” that must SURVIVE. `alsoCleared` reduces to the selection on Windows and the reduction is a finding, not an omission — the mac's five confirmations and four alerts are awaited modal `ContentDialog`s there, continuations rather than fields; `documentation/12-windows-app.md` has it, including the one route the modality does NOT close. |
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
| `wizardAnswerKeys`, `firstDeployMarkers`, `sectionTimetable`, `pageVisibility.writingRules` (the four rule SENTENCES, answered by name) and `pageVisibility.writingCases` — all thirteen, deserialised and played against `PageFrontmatter.SetDraft` since 2026-09-19 ([#138](https://github.com/russellgordon/plantoir/issues/138)), guarded at `>= 10` there so the loop cannot pass having run nothing (the mac's runner carries a floor of its own, raised to 13 with [#176](https://github.com/russellgordon/plantoir/issues/176)) | `FileFormatContractTests` |
| `publishedFreshness`, `credentialPrompts.everyRequest`, `launcherFlags.deployExtras`, `previewPorts`, `linkRules.browserSafe` | `PublishAndLauncherContractTests` |
| `toolSchemas` (names and arguments), `assistantModelChoice`, `modelTiers.requirements`, `promptHistory.passThroughWhen` | `AssistSurfaceContractTests`. **`modelTiers.requirements` is asked BOTH WAYS now**: the mac's `AppRulesContractTests.testEveryRequirementOfTheLocalAssistantIsAnsweredOrSaidToBeUnexecutable` (added 2026-09-19 with [#166](https://github.com/russellgordon/plantoir/issues/166)) is the mirror of the Windows test of the same name, so a requirement added on either side now fails by name on the other rather than sitting in the contract unread |
| `renameEffects`, `problemReportDialog`, `ancestorPaths`, `pageNaming.theRule`, `buildOutputLocation.windowsLocation`, `example-content.rules`, `example-content.sentinels`, `recipeFolders`, `scheduledDeployRefusals.alsoSaid` | `SharedRuleContractTests` |
| `gradedFolders.cases`, and `gradedFolders.wording` — the Marks list's title and caption (proposed from Windows 2026-09-08; the mac has run `.wording` since 2026-09-09 in `SharedRulesContractTests`, so both platforms now go red for it. `.cases` is still Windows and the image only — the mac has no matching rule of its own to run it against) | `GradedFolderContractTests`. Whether a teacher can SEE the caption is `CourseSettingsCaptionUiTests` in `Plantoir.UiTests/`, opt-in and part of no gate |
| `gradedFolders.removingAFolder` — what a removal does to the marks pool, all seven cases played through `FolderRemoval.RemoveFolderFromCourse` (adopted from the mac 2026-09-18, [#142](https://github.com/russellgordon/plantoir/issues/142)) | `GradedFolderChoicesTests.WhatARemovalDoesToTheMarksPoolMatchesTheContract`. The seventh case — matching CASE on the STILL-OFFERED half, which Windows asks insensitively so that it agrees with the build — was raised from there as [#172](https://github.com/russellgordon/plantoir/issues/172) and landed in the contract on 2026-09-19; it passes on Windows unchanged, and the local `ANameStillOfferedInANOTHERCasingKeepsItsPlaceInThePool` is now a duplicate of it, theirs to keep or retire. What is still unpinned is the DROP's own comparison |
| `gradedFolders.choices` (cases, the depth cap and the skip list) | `GradedFolderChoicesTests`. The mac runs the same list in its own `GradedFolderChoicesTests` since 2026-09-09; the three cases added there that day — the symbol sort, a section folder found deeper down, and the level a removed name reaches — pass here unchanged, and the `Count >= 11` guard was raised to 14 on 2026-09-18 |
| `specialNames` — the blocked and confirmed names, `renameFolder.carriesAcross`, `renameFolder.problems`, `curriculumFolderResolution` | `SpecialNamesContractTests`, `SpecialFolderRenamerTests`, `GradedFolderContractTests` |
| `specialNames.contentStructureTip` (proposed from Windows 2026-09-07 and adopted here 2026-09-09, [#72](https://github.com/russellgordon/plantoir/issues/72); the mac runs it in `SharedRulesContractTests`, so both platforms now go red for it) | `SpecialNamesContractTests`. Whether a teacher can actually SEE it is `CourseSettingsCaptionUiTests`, which is in `Plantoir.UiTests/` rather than this project, carries `[UiFact]`, and runs only under `PLANTOIR_UI_TESTS=1` — so it is part of no gate |
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

**And one list added after that audit is NOT wired here, deliberately.**
`class-planning.json` → `renamingTheUnitWord` (seven `cases`, three
`linkCases`, added on the mac 2026-09-10 with [#100](https://github.com/russellgordon/plantoir/issues/100))
has no Windows runner, because Windows cannot rename a course's word for a
unit at all yet — [#158](https://github.com/russellgordon/plantoir/issues/158),
milestoned v1.3.0. Worth saying out loud because it is the quiet kind of gap:
those ten cases are UNRUN rather than failing, so no Windows gate mentions
them and nothing goes red. The two places that DID go red — the trail event
and `renameUnitWord.explanation` — are named in
`windows-app/Plantoir.Tests/NamedGapLedger.cs` and will fail the moment either
is built or withdrawn. The ten cases have no such guard; #158 carries them.

#### The census, taken 2026-09-19 (re-taken the same day, after #162)

The 2026-09-06 audit was a count; this is the same question asked of the file
as it stands, and it is the milestone's "definition of done" for
[#138](https://github.com/russellgordon/plantoir/issues/138): **every case list
in every `contracts/*.json` is either run by a Windows gate, or owned by an
open issue, or exempt for a reason written down here.** **128 case lists; 102
have a reader here.** The other twenty-six are below. (It was 100 of 111 when this
paragraph was first written; `workingFolderSelection.cases` and `.rejected`
have a Windows reader since [#162](https://github.com/russellgordon/plantoir/issues/162)
landed, and the count was RE-TAKEN with the walker below rather than adjusted
by hand. It moved from 111 to 114 when `deployAtATime` arrived with #168 —
three lists, all owed, all in the table.)

**Re-taken 2026-09-19 with the walker, and it had already gone stale by one.**
The walker read **115** at `origin/dev` where this paragraph said 114:
`zipNames.couldHaveBeenStamped.cases` arrived with the archive-stamp work and
nobody re-took the count. It is in the table below now.
[#173](https://github.com/russellgordon/plantoir/issues/173) then added two
more, which is how the number reached 117 — and
[#202](https://github.com/russellgordon/plantoir/issues/202)'s `windowBinding`
made it **118**, re-taken with the walker on the day it landed rather than
added to in somebody's head. [#205](https://github.com/russellgordon/plantoir/issues/205)'s
`outsideAgents.agents` made it **119**, re-taken with the walker the same way, and [#215](https://github.com/russellgordon/plantoir/issues/215)'s `hideIsUnpublish.accepted`, `.refused` and `echoedRequest.cases` made it **122** — re-taken with the walker again, on the day they landed. **This is the failure mode the
"re-take it" instruction below exists for**, met within a fortnight of being
written: three lists in, and the only reason it was caught is that somebody
ran the walker instead of adding to the number in their head.

**Re-taken again 2026-09-20 with [#236](https://github.com/russellgordon/plantoir/issues/236),
on the day its four lists landed, and it had gone stale by one AGAIN.** The
walker read **124** at `origin/dev` where the paragraph above said 123 — one
list arrived there and nobody re-took the count; it is not named here because
finding WHICH is a separate sweep and inventing an answer would be worse than
the gap. #236's own four take it to **128**: `scheduledDeployCancellation.cases`
(9), `.howLateIsTooLate.cases` (10), `.theSetting.storedValueCases` (7) and
`.whatWasRejected` (5). None has a Windows reader, so the 102 is unchanged and
the remainder is twenty-six. They are the four rows at the end of the table
below.

**Re-taken again 2026-09-20 with [#206](https://github.com/russellgordon/plantoir/issues/206)
branch A, on the day it landed.** The walker read **128** before it and **139**
after: `referenceCourses` adds eleven lists — `schoolYearLabel.cases` (3),
`schoolYearsOffered.cases` (4), `schoolYearRead.cases` (8),
`codeUniqueWithinAGroup.cases` (7), `neutralises.keys` (4),
`markerAgreement.cases` (26), `refusal.doors` (15),
`refusal.toolsStillAllowed` (3), `frozen.neverLocked` (6),
`frozen.whatPlantoirStillWrites` (4) and `rejected` (5). None has a Windows
reader yet, so the 102 is unchanged and the remainder is thirty-seven.
(`markerAgreement.cases` arrived a commit later than the other ten, from the
implementation review, and the count was re-taken with the walker rather than
added to in somebody's head — which is what the paragraph below is for.) They are
one row at the end of the table below rather than ten, because they are one
feature with one issue and one milestone, and ten rows saying the same sentence
is a table nobody reads.

**Re-taken again 2026-09-20 with [#206](https://github.com/russellgordon/plantoir/issues/206)
branch B, on the day it landed.** The walker read **139** at branch A's tip and
**145** after: `referenceCourses.importing` adds six lists —
`foldersAccepted.cases` (7), `leftBehind.names` (15),
`leftBehind.alsoRemovedAfterTheCopy` (1), `leftBehind.kept` (3),
`folderNameProduced.cases` (4) and `schoolYearProposed.cases` (4). None has a
Windows reader yet, so the 102 is unchanged and the remainder is forty-three.
They join the same single row at the end of the table as branch A's eleven,
for the same reason: one feature, one issue, one milestone.

**Re-taken once more after branch B's own fix round, the same day.** The
walker reads **146**: `foldersAccepted.cases` grew from 7 to 9 (the refusal
that had a sentence and no case, and a course folder that is not in a courses
folder) and `nothingIsVisibleUntilItIsSafe.hiddenFromWhat` (4) is new — the
rule that a course is built under a hidden name and renamed into place last.
The remainder is forty-four.

**Re-taken once more after branch A was merged into branch B, 2026-09-20.**
Still **146**: branch A's own round moved `markerAgreement.cases` from 17 to 26
and added a trail event, neither of which is a new LIST, so the count survives
the merge unchanged. The `referenceCourses.*` row above carries both sides'
figures.

**Re-taken 2026-09-21 with [#207](https://github.com/russellgordon/plantoir/issues/207).**
The walker reads **152**: `copyingAPageBetweenCourses` adds six lists —
`cases` (27), `builderAgreement.cases` (36), `frontmatterCases` (8),
`rejected` (8), `whatIsNeverCopied` (5) and `refusals` (5). None has a Windows
reader yet, so the 102 is unchanged and the remainder is fifty. They join one
row at the end of the table, for the same reason #206's eleven do. The number
said "Twenty-four rule sets" while the file already held twenty-six and the
walker said 146 while it said 152, which is what re-taking is for.

**Re-taken 2026-09-21 with [#248](https://github.com/russellgordon/plantoir/issues/248).**
Still **152**, and the re-take is worth recording precisely because the number
did NOT move: `wizard.skeletonToggle.cases` grew from 13 to 17 and
`activityTrail.mustRecord` from 63 to 64, and neither is a new LIST. A census
of case LISTS cannot see cases arriving inside one, so it is not the thing to
read for "did this piece add coverage" — the floor assertions in each suite
are. The remainder is unchanged at fifty.

**Re-taken 2026-09-23 with [#254](https://github.com/russellgordon/plantoir/issues/254)**
(importing a class kept in the older folder-per-class layout). The walker read
**152** at `origin/dev` and reads **157** after:
`referenceCourses.importing.olderLayout` adds five lists —
`recognition.cases` (21), `codeAndYear.cases` (9),
`sharedFolder.chosenCases` (4), `placement.cases` (5) and `rejected` (11) —
and `activityTrail.mustRecord` grew from 64 to 65, which is not a new list.
None of the five has a Windows reader, so the 102 is unchanged and the
remainder is fifty-five. They join the `referenceCourses.*` row at the end of
the table, for the same reason #206's lists do. (The row's own "eighteen
lists" was not re-counted when these arrived and was caught in review; the
row now says twenty-three, which is what the walker finds under
`referenceCourses`.)

**Re-taken 2026-09-23 with [#256](https://github.com/russellgordon/plantoir/issues/256)**
(importing the first section of a class kept a website folder per class). The
walker read **157** at `origin/dev` and reads **163** after:
`referenceCourses.importing.quartzCheckoutLayout` adds six lists —
`recognition.cases` (31), `recognition.yearCases` (3),
`placement.cases` (3), `placement.leftBehind.kinds` (6),
`placement.unitWord.cases` (6) and `rejected` (11) — and
`activityTrail.mustRecord` grew from 65 to 66, which is not a new list. None
of the six has a Windows reader, so the 102 is unchanged and the remainder is
sixty-one. They join the `referenceCourses.*` row, which now says
twenty-nine. (Later the same day, with #256's review fixes and Russell's Copy a
Page decision, still **163**: no list was added, but `recognition.cases` grew
to 33, `placement.unitWord.cases` to 7 and
`copyingAPageBetweenCourses.frontmatterCases` to 9, and the wording block
gained `checkoutLayoutChooseACourseFolderInside` and
`checkoutLayoutWhatALinkShowed`.)

**Re-taken 2026-09-23 with [#195](https://github.com/russellgordon/plantoir/issues/195)**
(saying what a scheduled deploy replaces): still **163**. `activityTrail.mustRecord`
grew from 66 to 68 (`scheduled deploy replaced`, and `scheduled deploy could
not be set` from the fix review — both of which Windows will have to record or
ledger), and the wording block gained `scheduleReplaces` with a new
`{moment}` placeholder; neither is a new list.

**Re-taken 2026-09-25 with [#275](https://github.com/russellgordon/plantoir/issues/275) and [#276](https://github.com/russellgordon/plantoir/issues/276)**
(pages take their class's date). The walker read **171** at `origin/dev`
(c02f5d3b — the 163 above was not re-taken by the pieces between) and reads
**174** after: `sectionIndexPointer.dateCases.cases` (9),
`datingPagesAClassBrings.atBuildTime.cases` (14 — 12 when first written; the
fix round the same day added the hub case and a plain YAML date) and
`datingPagesAClassBrings.atBuildTime.writingCases.cases` (9 — 7, plus a note
kept on the date line and a `#` inside quotes); and
`activityTrail.mustRecord` grew from 70 to 71 (`pages dated by the build`),
which is not a new list. The two `atBuildTime` lists DO have a Windows reader
— the shared `scripts/test_dates_follow_the_class.py`, discovered by
`PythonToolchainTests` — and so does `dateCases` for its build half; the
seven `dateCases` with a `pointAt` are owed by Windows' own pointer.
**Re-taken 2026-09-25 with [#194](https://github.com/russellgordon/plantoir/issues/194)**
(asking "morning or evening?" in code). The walker read **171** at `origin/dev`
(9d4bf2a6) and **172** after on its own branch — **175** on the merged tree,
re-taken with the walker after #275 (above) had made it 174: `deployAtATime.asked` (9) is new, and has
no Windows reader, so it joins the `deployAtATime` row in the table below.
The review's fix round took `asked` to 11 (`deploy at 6.30` moved there from
`refused`, which gained `deploy at 6.30 pm` in its place, and `deploy at 6:30,
please` is new) — rows, not lists, so the walker still reads 172.
`deployAtATime.refused` went from 25 to 28 and `scenarios.cases` from 14 to 16,
neither a new list; `activityTrail.mustRecord` is unchanged by this piece — 71 on the merged tree after #275 (the event
reused is `assistant matched a fixed phrase`, whose `carries` now says it). The
wording block gained `morningOrEvening`, rendered with literal values rather
than placeholders — see the `asked` rows for every other input.
**Re-taken 2026-09-25 with [#175](https://github.com/russellgordon/plantoir/issues/175)**
(adding a section finds frontmatter the build's way). The walker reads **171**
at `origin/dev` (9d4bf2a6) and **172** after on its own branch — **176** on the
merged tree, re-taken with the walker after #275 and #194 (above) had made it
175. The one new list is
`course-management.json` → `sectionNumbers.addingKeysToAPage.cases` (7), with
no Windows reader — its row is below. The eight between 163 and 171 arrived
with pieces that did not re-take this census, and are NAMED here rather than
hand-checked (so the 102 is not re-derived by this entry):
`class-planning.json` → `insertion.numberedPosition.cases`,
`insertion.positionInSentences.cases`, `wholeUnit.cases`,
`sectionIndexPointer.cases`; `file-formats.json` →
`sidebarHiding.matchRule.cases`, `sidebarHiding.buildKeepsHidden.cases`;
`shared-rules.json` → `wizard.clubToggle.cases`, `savingSettings.cases`. And
`activityTrail.mustRecord` gained `section added` (70 to 71 on the branch; **72** on the merged tree, after #275's `pages dated by the build`) — not a new list, but
an event Windows has to record or ledger.

**Re-taken 2026-09-25 with [#242](https://github.com/russellgordon/plantoir/issues/242)**
(what backups take, and deleting several), counted ON THIS BRANCH — which
carries `origin/dev` 634182d7 (#235, #275 and #276), not whatever `dev` holds
when it merges. Re-taken at the merge: **179** on the merged tree (176 after #175, above, plus these three), and `activityTrail.mustRecord` **73**. On this branch the walker read **174** before
#242's lists and **177** after: `course-management.json` → `backups.pruneCases` (3),
`.sizeCases` (2) and `.deleteCases` (3), none with a Windows reader, all in the
table below; and `activityTrail.mustRecord` grew from 71 to 72 (`backups
deleted`), which is not a new list.
**Re-taken 2026-09-25 with [#199](https://github.com/russellgordon/plantoir/issues/199)**
(date and title writers take a key's whole value), on top of #175: one new
list, `file-formats.json` → `datesAndTitles.writingCases.cases` (13), with no
Windows reader — its row is below. Counted relative to whatever the walker
reads at merge time, since #175, #194 and #275 each re-take this census from
the same base; the merge that lands second re-counts. Re-taken at the merge, the
last of the batch: **180** on the merged tree, and `activityTrail.mustRecord` **73**.

**Re-taken 2026-09-25 with [#245](https://github.com/russellgordon/plantoir/issues/245)**
(the import's lease edges), counted ON THIS BRANCH, which carries
`origin/dev` 43d8e853. The walker read **180** before it and **183** after on its branch — **185** on the merged tree (re-taken at the merge: #280's `previewPorts` case lists had taken dev to 182 without a re-take, which is the drift this paragraph exists to catch):
`shared-rules.json` → `workLeases.liveness.cases` (19 — 18 when first written; review L2 added a one-line import lease),
`referenceCourses.importing.oneImportPerCourseAtATime.cases` (9) and
`file-formats.json` → `workLease.bodyCases` (7). None has a Windows reader; all
three are in the table below, owed by the `windows` issue that folds #245 into
[#244](https://github.com/russellgordon/plantoir/issues/244). No trail event
was added — the new refusal writes the existing "course could not be imported
for reference" line, whose `carries` grew — so `activityTrail.mustRecord` is
unchanged at 73.

**Re-take it rather than trusting this paragraph** — a census nobody can repeat
is a number that rots. A case list is *an array of objects reached through
objects only*: an array inside a case is a FIELD of that case (each
`stopPreview` case has its own `snapshot`), and counting those gives 159 and
means nothing. Run from the repository root:

```python
import json, os
found = []
def walk(node, path):
    if isinstance(node, dict):
        for k, v in node.items(): walk(v, (path + '.' + k) if path else k)
    elif isinstance(node, list) and node and all(isinstance(e, dict) for e in node):
        found.append((path, len(node)))
for fn in sorted(os.listdir('contracts')):
    if fn.endswith('.json'): walk(json.load(open('contracts/' + fn, encoding='utf-8')), fn)
for p, n in found: print(n, p)
print('TOTAL', len(found))
```

Then look for a reader of each path in `windows-app/Plantoir.Tests/**`,
`scripts/*.py` (which `PythonToolchainTests` discovers and runs inside `dotnet
test`) and `windows-app/*.ps1` — and **check every miss by hand**, because a
grep for two key names agrees with itself too easily in a large file, in both
directions. The table below is the hand-checked half; the 102 is the
subtraction.

| List | Cases | Where it stands |
|---|---|---|
| `class-planning.json` → `renamingTheUnitWord.cases`, `.linkCases.cases` | 7 + 3 | **Owed**, [#158](https://github.com/russellgordon/plantoir/issues/158) (v1.3.0) — Windows cannot rename a course's word for a unit at all yet. Unrun rather than failing; the paragraph above says why that is the quiet kind of gap. |
| `shared-rules.json` → `wizard.skeletonToggle.cases` | 17 | **Owed**, [#169](https://github.com/russellgordon/plantoir/issues/169) (v1.2.0). Windows shipped the RESTORE behaviour first; what it owed was the test and a seam to run it against, the restore being private to `NewCourseDialog`. Since 2026-09-21 it also owes the BEHAVIOUR: four of the seventeen cases describe a code whose ready-made pages were declined, which their `SkeletonCatalog.HasSkeleton` refuses to offer a skeleton for ([#248](https://github.com/russellgordon/plantoir/issues/248)). Their own `HasSkeletonReturnsFalseWhenExampleContentExists` asserts the old rule against itself and stays green. |
| `assist-cases.json` → `toolSchemas.departures.absentHere` | 1 | **Owed**, [#178](https://github.com/russellgordon/plantoir/issues/178) (v1.2.0) — the same defect #138 fixed, in another file: `AssistSurfaceContractTests.AssertOnlyTheDeparturesWeHaveAgreed` keeps `preview` in a hand-written `agreedExtras` array while the contract now states it. [#122](https://github.com/russellgordon/plantoir/issues/122) read the `listShapedStringParameters` half and left this one. |
| `shared-rules.json` → `workingFolderPathBar.ancestorPaths.cases` | 2 | **Exempt, by construction.** POSIX paths (`/Users/teacher/…`). The rule is shared; only the spelling of a root is the platform's, and `windowsCases` beside it — three cases including a `D:\` drive — is what `SharedRuleContractTests` runs. |
| `shared-rules.json` → `cloudSyncedFolders.detection.cases` | 11 | **Exempt, by construction.** Every path is a mac one (`{home}/Library/Mobile Documents`, `/Volumes/…`); the markers Windows detects from are a different list, and `CloudSyncedFolderTests` covers them. |
| `shared-rules.json` → `stopPreview.identity.evidences`, `.notShared` | 3 + 4 | **Exempt: prose with fields.** The behaviour they describe is exercised through `stopPreview.cases`, and those 23 are gated TWICE here — `scripts/test_stop_preview.py` through `PythonToolchainTests`, and `windows-app/test_stop_preview.ps1` through `TheLauncherMatcherAnswersTheContract`, which asserts "0 failed" so a runner that skipped everything cannot pass. |
| `assist-cases.json` → `deployAtATime.accepted`, `.asked`, `.refused`, `.resolving` | 23 + 11 + 28 + 11 | **Owed**, [#193](https://github.com/russellgordon/plantoir/issues/193), the `windows` issue opened from [#168](https://github.com/russellgordon/plantoir/issues/168) — the whole family is theirs to implement, and these rows ARE the specification: one example in `cardPhrasings.parsed` cannot describe a grammar of times. `CardPhrasings_AllParsedExamplesFromContract_Pass` will go red on the sixth family the moment the contract lands, so the work is visible there; what these add is every spelling and the day rule. `asked` arrived 2026-09-25 with [#194](https://github.com/russellgordon/plantoir/issues/194) (a one-digit hour with no am or pm is asked about in code, never sent to the model; `refused` lost `deploy at 6:30` to it and gained four not-asked boundaries) and is owed by the `windows` issue drafted from #194, together with `wording.morningOrEvening` and two scenarios. |
| `assist-cases.json` → `hideIsUnpublish.accepted`, `.refused` | 13 + 20 | **Owed**, the `windows` issue opened from [#215](https://github.com/russellgordon/plantoir/issues/215). AUTHORED, arrived 2026-09-19. The family it describes DOES have a Windows reader through `cardPhrasings.parsed` — their `CardPhrasings_AllParsedExamplesFromContract_Pass` walks the example and the near-miss, and goes red on pull until they implement the frame — but one example cannot describe a grammar whose spellings are the whole question, which is the same argument `deployAtATime` won. Two rows in it carry decisions rather than spellings and are the ones to read first: `publish unit 4, day 3` is REFUSED (the day arm is gated on the verb, because publishing is the direction that reaches students), and `hide unit 4, day 21 in ICS3U` is refused because a matched card binds the session's own course unconditionally on both platforms |
| `assist-cases.json` → `echoedRequest.cases` | 9 | **Owed**, the same `windows` issue. AUTHORED, arrived 2026-09-19. A pure predicate — (what was sent, what the teacher typed, what came back, whether there was a tool call) → is this an echo — so it is runnable the moment they have a reader for it, and it needs no conversation to set up. NOT expressible as a scenario on either platform, for the reason `windowBinding` records: the scenario runner has no engine seam, so a model's reply cannot be scripted |
| `shared-rules.json` → `quittingWhileWorkIsUnderWay.cases` | 8 | **Run on the mac, no Windows reader**, and the newest of the twenty-one. Arrived 2026-09-19 with [#220](https://github.com/russellgordon/plantoir/issues/220); `QuitConfirmationTests.testTheRuleIsTheOneTheContractWritesDown` deserialises all eight (and fails a case that does not say `previewsBeingBuilt`), and `testTheSafeAnswerIsTheDefaultOne` reads `buttons.default`. Windows has no such question, and the block carries `appliesOn: ["mac"]` as an acknowledged exception — see "One exception has been taken to the passage above" under Named gaps. The eight cases are platform-neutral apart from the two `quitReason` spellings; the discriminating ones are "a preview is open and nothing is publishing", which pins that a preview merely being OPEN is not work under way, and "a preview is being built and nothing is publishing" (#232), which pins that a preview being BUILT is. Owed with the behaviour, in the `windows` issue that carries #220's handover |
| `shared-rules.json` → `followingLinks.stopsAtAClassPage.cases` | 3 | **Owed**, the `windows` issue opened from [#173](https://github.com/russellgordon/plantoir/issues/173) ([#203](https://github.com/russellgordon/plantoir/issues/203), v1.3.0). **Green by BEHAVIOUR, unrun by their SUITE**, which is the quiet kind of gap: `AssistWorkspace.cs:730` already guards both the add and the enqueue on `!targetPage.IsClassPage`, so all three cases would pass today — but `SharedRules_FollowingLinks_MatchesContract` asserts named booleans and walks no `cases` array, so nothing there runs them and nothing there goes red. What they owe is the loop, and the SENTENCE (`wording.linkedClassWasLeftAlone` / `…ClassesWereLeftAlone`), which is the one behaviour they do not have. The rule deliberately did NOT go into `neverTakenDownByFollowingLinks`, which `ContractTests.cs:295` asserts is exactly three. |
| `assist-cases.json` → `windowBinding.cases` | 8 | **Owed**, the `windows` issue opened from [#202](https://github.com/russellgordon/plantoir/issues/202) ([#208](https://github.com/russellgordon/plantoir/issues/208), v1.2.0 — part of #180), the mac half of [#180](https://github.com/russellgordon/plantoir/issues/180). **Unrun there, and it cannot be red**: nothing on that side enumerates the top-level keys of `assist-cases.json` — every access is by name — and their scenario grammar (`AssistScenarioTests.cs`, whose `given` keys are `previewRunning`, `sectionWindowOpen`, `sectionBusy`, `pending`, `saying`) cannot script a model's TOOL CALL at all, which is what every case here starts from. What they owe is a seam that can, plus the two wording keys the refusals name. Their own behaviour is already close: `AssistWorkspace.Course` refuses any course but the session's, which is where the mac's rule came from. |
| `class-planning.json` → `datingPagesAClassBrings.reachStopsAtAClassPage.cases` | 2 | **Owed**, the same `windows` issue as the row above. Green by behaviour for the same reason — their date walk stops on `classPaths` at `AssistWorkspace.cs:927`, before the enqueue at `:928`, and the backwards earliest-class walk does not pass through a class either — and unrun for the same reason. |
| `course-management.json` → `zipNames.couldHaveBeenStamped.cases` | 3 | **Owed**, [#161](https://github.com/russellgordon/plantoir/issues/161) part 2. Windows holds the two bounds as literals in `ModelTests.CouldHaveBeenStamped_BoundsAreTheOnesTheMacUses`, whose own summary says it is replaced by the contract loop once this block reaches `dev` — which it now has. Arrived after the census was taken and was missed by it; see the re-take note above. |
| `course-management.json` → `sectionNumbers.addingKeysToAPage.cases` | 7 | **Owed**, the `windows` issue opened from [#175](https://github.com/russellgordon/plantoir/issues/175). AUTHORED, arrived 2026-09-25. Seven whole-file before/after pairs. Measured by reading `SectionAdder.cs:190-242` (review of #175): Windows' finder wants `---` on line 0 but tolerates CRLF, so THREE of the shapes are skipped (`----` — publishing a page hidden in section 1 — a blank line before, a trailing space); the CRLF case gets its keys but the file is rewritten with LF (`Replace("\r\n","\n")`), so it fails the byte comparison for that reason; and the seventh (a setting below its key) is split the way #181 described. `ExtendFrontmatter` is private there, so running the cases needs it exposed. Unrun rather than failing; wiring them in is the acceptance. |
| `file-formats.json` → `datesAndTitles.writingCases.cases` | 13 | **Owed**, the `windows` issue opened from [#199](https://github.com/russellgordon/plantoir/issues/199). AUTHORED, arrived 2026-09-25. Windows' `PageFrontmatter.SetTitle` and `SetCreated` replace the key's line alone (`lines[at] = ReplaceRawValue(...)`), so the ten non-control cases fail there until they call their own `ContinuationLines`. Unrun rather than failing. |
| `shared-rules.json` → `scheduledDeployCancellation.cases` | 9 | **Owed**, the `windows` issue opened from [#236](https://github.com/russellgordon/plantoir/issues/236). AUTHORED, arrived 2026-09-20. **Half of it is already their behaviour and half is a fault they share**: `CourseArchiver.cs` cancels on removing a SECTION and not on removing a COURSE, and their task name is the course code and section only, so the two-working-folders case is theirs too. Unrun rather than red — nothing on that side enumerates the top-level keys of `shared-rules.json`, so a new one is silently ignored, the same precedent as `gradedFolders.removingAFolder` and `workingFolderSelection`. Read `howToRunACase` before wiring it: six cases are played through a real removal, rename or rollover and three are a scan of a source file that must not have learned to cancel. The ninth — the rollover — exists because that path was the ONE cancel left folder-blind when the rule first landed here, which is what a case list is for. |
| `shared-rules.json` → `scheduledDeployCancellation.howLateIsTooLate.cases` | 10 | **Owed only if their scheduler runs a missed start late**, and that is the question the same issue asks them: `TaskScheduling.cs` creates the task with `/SC ONCE`, which has no annual recurrence, so the fault these close may not exist there. The cases are a pure predicate — (how far the moment is from now, the window the course chose) → does it run — so they are runnable the moment there is something to run them against. If the answer is "a missed start is not run late", this list is EXEMPT and the contract should say so rather than leaving it owed forever. |
| `shared-rules.json` → `scheduledDeployCancellation.theSetting.storedValueCases` | 7 | **Owed with the key**, the same issue. `file-formats.json` → `courseConfigKeys` gains `scheduled_deploy_may_run_late_days`, and `FileFormats_CourseConfigKeys_MatchesContract` DOES go red for it — so unlike the two rows above, this one announces itself. Windows must at minimum PRESERVE the key on a write (the existing rule about keys a platform does not understand); these seven say what each stored value means if they offer the setting. |
| `shared-rules.json` → `scheduledDeployCancellation.whatWasRejected` | 5 | **Exempt: prose with fields.** Five rejected designs, each with what was taken instead and why — the course-absence sweep, the calendar day rule, a fixed 24-hour window, an "always" choice, and cancelling inside the course archiver. Nothing to run; it is here so the same afternoon is not spent twice, and it is counted because the walker counts an array of objects. |
| `app-rules.json` → `outsideAgents.agents` | 2 | **Owed in part**, [#210](https://github.com/russellgordon/plantoir/issues/210) (v1.3.1), the `windows` issue opened from [#205](https://github.com/russellgordon/plantoir/issues/205), at a later milestone than the mac half. **Unrun there, and it cannot be red**: nothing on either side enumerates the top-level keys of `app-rules.json` — every access there is by name (`ContractTests.cs`, `MilestoneContractTests.cs`, `PublishAndLauncherContractTests.cs`, `BuildOutputLocationTests.cs`, `AssistSurfaceContractTests.cs`) — so a new authored key is simply not read. No `NamedGapLedger` entry, deliberately: the ledger is for a case that would otherwise go RED, and a green assertion about something nobody runs is the thing this section spends three paragraphs rejecting. The `claude` case describes behaviour Windows ALREADY has (`Plantoir.Core/Assist/ClaudeCodeLauncher.cs`, `Views/SidebarPane.xaml.cs:884`) with ONE verified exception written into the data — it writes no handover script (`macHandsOverWith` is the mac's alone) — and one GAP that is owed rather than written down: its Claude door records NOTHING on the trail, which the `windows` issue asks for. The `codex` case is the door they owe. |
| `shared-rules.json` → `copyingAPageBetweenCourses.*` (six lists: 27 planner cases, 36 builder-agreement cases, 9 frontmatter cases — the ninth added with #256, 2026-09-23 — 8 rejections, 5 never-copied and 5 refusals, plus the wording block) | 27 + 36 + 9 + 8 + 5 + 5 | **Owed**, the `windows` issue drafted for [#207](https://github.com/russellgordon/plantoir/issues/207). AUTHORED, arrived 2026-09-21. **Unrun rather than red** on that side, for the same reason every other new top-level key is: nothing there enumerates `shared-rules.json`'s top-level keys. What DOES go red on pull is one thing, named in the issue: `SharedRules_ActivityTrailEvents_Exist`, because `pages copied from another course` is a new trail event. **The nine `frontmatterCases` and the thirty-six `builderAgreement` cases are PURE** — a string and a list of section numbers in, a string out, then three predicates over it — so they are runnable the day they have a reader and are the ones to wire FIRST (the ninth, from #256, also carries `theBuilderAgrees: true` — its composed text must pass the builder-agreement guard, since the point of stripping the 2024–25 layout's `draftSectionTwo`/`createdForSectionTwo` is that the page COPIES): they carry the rule that decides whether a copied page can be read by students, and three of the four ways to get it wrong PUBLISH the page. The 27 planner cases need a source and destination tree built from each case's `source`/`destination` fields; the mac's `CoursePageCopyTests` shows the shape, and one case (`the rename runs out of names`) uses `andEveryNumberedNameUpTo` to ask for 49 further files rather than listing them. What is NOT free on that side: `copyfile(COPYFILE_CLONE)`'s create-exclusive guarantee has no NTFS equivalent — `File.Copy` does not refuse a destination differing only by case — so `FileMode.CreateNew` is the nearest thing, and the name index must compose with `String.Normalize(NormalizationForm.FormC)` before folding case. |
| `shared-rules.json` → `referenceCourses.*` (twenty-nine lists, re-taken with the walker 2026-09-23 after #256) | 3 + 4 + 8 + 7 + 4 + 26 + 15 + 3 + 6 + 4 + 5, plus `importing`'s 9 + 15 + 1 + 3 + 4 + 4 + 4, plus `importing.olderLayout`'s 21 + 9 + 4 + 5 + 11 (#254), plus `importing.quartzCheckoutLayout`'s 33 + 3 + 3 + 6 + 7 + 11 (#256) | **Owed**, the `windows` issue opened from [#206](https://github.com/russellgordon/plantoir/issues/206). AUTHORED, arrived 2026-09-20 with branch A. **Unrun rather than red**: nothing on that side enumerates the top-level keys of `shared-rules.json`, so a new one is silently ignored — the same precedent as `gradedFolders.removingAFolder`, `workingFolderSelection` and `scheduledDeployCancellation`. What DOES go red there on pull is two other things, both named in the issue: `FileFormats_CourseConfigKeys_MatchesContract` (two config keys) and `SharedRules_ActivityTrailEvents_Exist` (two trail events). Three of the eleven are runnable the moment they have a reader, because they are pure predicates: `schoolYearsOffered.cases` (a date → the years offered), `schoolYearLabel.cases` (an integer → "2025–26", en dash included) and `codeUniqueWithinAGroup.cases`. **`markerAgreement.cases` is the one to wire FIRST**, and it is the only list here that is already half-run on that side: `scripts/test_reference_course.py` runs all twenty-six rows through `PythonToolchainTests` the moment they pull, including a simulation of `deploy.ps1`'s own pattern — what Windows owes is running them against the REAL `deploy.ps1`, which the mac cannot start — and note that the shell reader is SKIPPED on that side too (the harness refuses a WSL bash that cannot open a Windows temp path), so what runs there is the Python reader and the .NET-pattern simulation. It exists because the readers did NOT agree: a config whose marker key and value sat on different lines was a reference course to the Python and an ordinary one to `deploy.sh`, which published it. `refusal.doors` is the acceptance list for the dangerous half and is worth reading next: fifteen doors, the chokepoint each is caught at, and the note on the one door — `deploy.ps1`'s own folder-publish branch — that the shared Python cannot reach. `frozen.*` describes a lock with no NTFS equivalent and is the part Windows must DESIGN rather than copy. **`importing`'s six lists arrived 2026-09-20 with branch B** and are the specification for Import Courses for Reference…: which folder shapes are accepted and what each refusal is called, what is left behind and why each name is on the list, the folder name produced, and the school-year proposal. They are runnable predicates apart from `foldersAccepted.cases`, which needs a folder tree built from each case's `tree` field — the mac's `ReferenceImportTests` shows the shape. The one that is NOT free on that side is the copy itself: NTFS has no clone, so a 489 MB course is a real copy on every disk. **`importing.olderLayout`'s five lists arrived 2026-09-23 with [#254](https://github.com/russellgordon/plantoir/issues/254)** and specify importing a class kept in Russell's older folder-per-class layout: `recognition.cases`, `sharedFolder.chosenCases` and `placement.cases` need a folder tree built from each case's `tree` — which here includes LINKS, dangling and resolving (see `olderLayout.treeEntries`; on Windows a directory case can be a junction, and any reparse point must be treated as a link: never followed, never copied) — while `codeAndYear.cases` is a pure predicate on a folder name. Whether Windows needs this at all is a `decision` for Russell, who alone used the layout; the one thing that DOES go red there on pull is `SharedRules_ActivityTrailEvents_Exist`, which gains the event "course imported from the older layout" beside the #206 events it already owes. **`importing.quartzCheckoutLayout`'s six lists arrived 2026-09-23 with [#256](https://github.com/russellgordon/plantoir/issues/256)** and specify importing the FIRST section of a class kept in Russell's 2024-25 layout, a whole website folder per class reached directly or through Finder shortcuts: `recognition.cases` and `placement.cases` need a tree that includes links with exact TEXT and Finder aliases (`quartzCheckoutLayout.treeEntries`; the Windows cousin of an alias is a `.lnk` shortcut, and a symlink or junction must never be taken for one), while `yearCases` and `unitWord.cases` are pure predicates. Again a `decision` for Russell; `SharedRules_ActivityTrailEvents_Exist` gains "course imported from a class website folder". |
| `course-management.json` → `backups.pruneCases`, `.sizeCases`, `.deleteCases` | 3 + 2 + 3 | **Owed**, the `windows` issue drafted from [#242](https://github.com/russellgordon/plantoir/issues/242). AUTHORED, arrived 2026-09-25. **Unrun rather than red** there: nothing on that side enumerates the top-level keys of `course-management.json` that it does not name. `pruneCases` describes behaviour Windows should already have (its archiver prunes only the assistant's backups, per `documentation/12-windows-app.md`) and is runnable at once against a temp folder; `sizeCases` needs the LOGICAL size (`FileInfo.Length`, never an allocation size — the second case is a sparse file, the shape of a cloud-evicted one); `deleteCases` needs a seam saying which backups an open assistant conversation holds. What DOES go red on pull is `SharedRules_ActivityTrailEvents_Exist`, for `backups deleted`. |
| `shared-rules.json` → `workLeases.liveness.cases`, `referenceCourses.importing.oneImportPerCourseAtATime.cases`; `file-formats.json` → `workLease.bodyCases` | 19 + 9 + 7 | **Owed**, the `windows` issue drafted from [#245](https://github.com/russellgordon/plantoir/issues/245), folded into [#244](https://github.com/russellgordon/plantoir/issues/244) (Windows' import). AUTHORED, arrived 2026-09-25. Not counted in the `referenceCourses.*` row's twenty-nine. **`liveness.cases` and `bodyCases` are PURE** — the signal and table answers and a lease's recorded name and start in, alive or gone out; a body in, a name and start out — but `WorkLease.IsAlive` takes a file and a pid, not those answers, so running them needs a SEAM that exposes the decision first. Two liveness cases carry `appliesOn: ["mac"]` and would be RED against today's `IsAlive` if run anyway: the one-line import lease (their reader treats fewer than two lines as stale, and reads no import leases at all); the sixteen-character name prefix is a mac process-table limit with no Windows meaning, though it passes either way. What does carry over unchanged is erring alive on can't-tell. The claim cases need the import's staging, which Windows does not have yet; `howToRunACase` says how the mac drives the real claim through them. Unrun rather than red: nothing there enumerates these files' top-level keys. |
| `toolchain.json` → `rules` | 3 | **Read by NOBODY, on either platform** — the one list in the census with no reader anywhere and no issue, and it is left that way deliberately. It is reasoning rather than cases: the image tag being a hash of the build context, building with BuildKit, and revalidating Quartz before chasing a newer CLI. All three are held by the launchers and by `verify.sh`, which does not run on Windows at all. The other three `rules` arrays ARE read — `buildFreshness.rules` by `BuildOutputLocationTests`, `example-content.rules` and `courseConfigKeys.rules` by `SharedRuleContractTests`. |

**And the exemptions inside lists that ARE run**, because "run" is not the
whole answer for a list a named key has been lifted out of:
`windows-app/Plantoir.Tests/NamedGapLedger.cs` holds exactly two, both
[#158](https://github.com/russellgordon/plantoir/issues/158) at v1.3.0 — the
`word for a unit renamed` trail event out of `activityTrail.mustRecord` (47
entries since [#166](https://github.com/russellgordon/plantoir/issues/166) added
`assistant answer was cut off` and
[#163](https://github.com/russellgordon/plantoir/issues/163) added
`class copy not made`, both of which Windows will have to record or ledger),
and `renameUnitWord.explanation` out of
`specialNames.platformWording.keys` (4). Both fail the moment the gap closes or
the requirement is withdrawn. The two exemption sets in `FileFormatContractTests`
— `knowinglyAbsent` for `wizardAnswerKeys` and `knowinglyNotFollowed` for
`writingRules` — are **both empty today**, kept so the next knowing divergence
is named in a run's output rather than in a comment.

**What the census does not count**, said so nobody re-derives it as a gap:
lists of plain STRINGS are not case lists (`tools.local`, `acceptedDateForms`,
the skeleton-toggle folder lists, and so on), and the walker above does not
count them. Each is checked wherever the thing it names is checked.

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
| `modelTiers.requirements` — the polarity veto | A rule about how a MODEL is chosen, governing the by-hand routing suite in `research/ai-assist/`. **It is the only one of the eight left unexecuted**, and both platforms' completeness tests name it explicitly rather than dropping it — including the two added with #166, one of which (the request cap) is executed on both sides and the other (a stopped reply runs nothing) on the mac only, as a named gap Windows owes, and the one added with [#198](https://github.com/russellgordon/plantoir/issues/198) (a finished reply that wrote nothing runs a tool only when the window supplies everything that tool needs; fourteen cases), executed on the mac and failing Windows' completeness test by name until it is answered there. |
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
| Reading a zip name an older mac wrote in another CALENDAR | 8 (`ArchiveStampTests`) | A migration for the mac's own history rather than a shared rule: the mac wrote those names until 2026-09-10 and Windows never did. It is also a rule the mac cannot check on the other side — .NET's `TryParseExact` does not treat native digits the way Foundation does, so an `ar-SA` case may be un-passable there. What both apps WRITE, and the moment each name is read as, are shared (above). The half Windows had to act on was not this rule but its consequence: their `PruneBackups` had no guard against a date that cannot be true, so a folder carried from a pre-fix Thai Mac could push a real backup off the disk. That half is DONE — [#161](https://github.com/russellgordon/plantoir/issues/161) part 1, on `dev` since 2026-09-19 (GUI row 490); what is left there is wiring the shared cases above. |
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
  containing a digit or a comma. (The rename sheet reuses them; every OTHER
  sentence it shows is in `specialNames.renameUnitWord`.)
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


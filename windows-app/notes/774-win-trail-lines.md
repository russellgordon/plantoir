# Lane E (night 4): Windows trail lines — #946, #821, #774

Branch `issue/774-win-trail-lines`. Notes for the director to fold into
`windows-app/PROGRESS.md` and `documentation/12-windows-app.md`.

## For PROGRESS

### #946 (the mac's #879, #887, #791)

- **Item 1, the place.** `ActivityTrail.Place(course, section)` is the one
  place function (`activityTrail.lineShape.placeCases`): `{course}/{section} · `,
  `{course} · ` for a section of 0 or less, nothing with no course, the course
  trimmed. Both `Note(…, course, section)` and `NotePrompt` use it.
  `TrailLinesContractTests.EveryPlaceCaseIsThePlaceOfAWrittenLine` runs the
  five cases from the JSON against the function and against lines really
  written by `Note` and `NotePrompt`.
- **Callers that passed a missing section as 0, or built their own prefix:**
  - `Plantoir.Mcp/OutsideChangeGate.Refusal` (Windows' equivalent of the mac's
    `AssistToolRunner.outsideChangeHeldBack`): read a missing `section` as 0
    and then wrote the line with NO place at all. Now always
    `Note(…, course, section)`, so it reads `ICS3U · an outside assistant's … held back`.
  - `Plantoir.Core/Assist/TodaysClassOnTheFrontPage.cs` built
    `{course.Code}/{section} · ` itself, twice; now through `Note(…, course, section)`.
  - Left, and named for their owners: `ScriptRunner.cs` about line 660
    (`preview closed for a deploy` chooses between the two overloads by
    `section > 0`; harmless now, lane D's file), `Plantoir/Views/SectionDetailView.xaml.cs`
    about line 1266 (`left the front page as it was` builds `{course}/{section} · `
    itself; the section is always a real one there; the file was out of this
    lane's scope tonight), and `BuildBeforeDeployingQuestion.cs:138`, which is
    a PowerShell expression for the launcher's own `note_on_the_trail`, not an
    app line.
  - `AssistAgent.NotePrompt(text, _courseCode, _section)`: the in-app
    assistant always has its window's section; a 0 would now read `{course} · `.
- **Item 2.** `AgentGuidanceWording.AskFound` is the contract's `askFound`
  (Claude Code, Codex and GitHub Copilot). The `Owed(AgentGuidanceWordsSaidDifferently, 946, …)`
  entry and `Reason946` are gone from `NamedGapLedger.cs`; the area constant
  and its hook stay for the next such sentence.
- **Item 3.** `OutsideGreetingContractTests.EveryDoorsGreetingSaysWhatTheContractSaysWhereItSays`
  reads `key` and `where` from each `greetingMustSay` entry and checks each
  `where` as `greetingMustSayHow` defines it, over each door's real `Prepare`
  greeting in the three variants it names; an unknown `where` fails. The
  Copilot door is held by name already (`NamedGapLedger.OutsideDoorsHeld`,
  #884), so `Doors()` leaves it out. `NoGreetingOffersAHeldSkill` is replaced
  by `NoGreetingSaysWhatTheContractForbids`, which proves the
  `greetingMustNotSay` expressions on `mustMatch` and `mustNotMatch` first,
  then matches them over every message the doors compose (Revise in the
  handouts, reference and variant shapes, Fix with…, Plan a Unit…, the 18
  unit-plan greetings). No greeting needed a change.

### #821 (#780 on Windows)

- **Item 1.** New `Plantoir.Core/Models/OneLineText.cs` (`IsSpacedOut`,
  `IsRemoved`, `Cleaned(text, keepingLineBreaks)`, `CourseName`).
  `CourseConfiguration.CourseName` cleans in its getter and setter; `Write`
  cleans the stored `course_name` after the per-key merge, so a Save writes it
  cleaned whatever was edited; the New Course window cleans before it trims,
  so a name that is only controls gets the default. `UnitPlans.OneLine` now
  runs the cleaner first, as the mac does (its comment said so was owed).
  Tests: the 41 `cases` code unit by code unit with idempotence; `spacedOut` /
  `removed` pinned against the predicates over U+0000 to U+FFFF; every case
  read, set and saved through `CourseConfiguration`.
- **Item 2.** `ActivityTrail.SafeTrailLine(line, keepingLineBreaks)` is the
  one clean-and-redact function, in `trailLines.order` (redact once when
  cleaning changes nothing; otherwise redact, clean, redact). Both `Note`
  overloads, `NotePrompt` and the private writer behind `NoteClosed` go
  through it; nothing else in `ActivityTrail.cs` calls `LogRedactor`. The 14
  `trailLines.cases` run from the JSON against it, and the one-line cases
  again through a real `Note`. `knownLimits` is named in its comment.
- **Item 3.** Nothing was needed: `dev` already has `(?!\[removed: )` in
  `labelledSecret` and `bearerHeader`, and `LogRedactorTests.RedactingTwiceChangesNothing`
  already runs `redactedAgainCases` from the JSON.
- **Item 4.** `NotePrompt` builds its record with `PromptRecord`: the head line
  cleaned to one line, the sentence cleaned to one line (then trimmed, as
  Windows always trimmed it) behind `PromptPrefix`, and the record through
  `SafeTrailLine(…, keepingLineBreaks: true)`. `promptCases` (2) run.
- **Item 5.** `OutsideDoor.Clean` and its tests are unchanged.

### #774 (the headless path's task lines)

- `LauncherRunner.Run` (plantoir-mcp.exe) writes `task started` once the
  process has started and `task finished` when it exits or is cancelled,
  through a small private `TrailedTask` and shared helpers in
  `ActivityTrail.cs`: `TaskStartedWords` (the window's "started deploy.ps1
  ICS3U 2 …"), `TaskFinishedWords` and `DurationWords` (the window's
  " after 12s" / " after 3m 4s"), `HeadlessOutcome` (exit 3 is
  "stopped at a question nobody was there to answer (exit 3)", the contract's
  words; every other exit is `ScriptRunner.FinishedOutcome`'s), and
  `PlaceOfLauncherArguments` (course first, section second). A cancelled call
  is "stopped before it finished" (the runner's own sentence; "stopped by the
  teacher" would not always be true from an MCP client). A launcher that is
  missing, or a folder another Plantoir is getting ready, or a process that
  cannot start, writes "could not start {launcher} — {message}", as the window
  does. Every line carries the place, and the arguments are redacted with the
  whole line.
- `ScriptRunner.cs` is unchanged (lane D's tonight): its `NoteTaskStarted` /
  `NoteTaskFinished` are private instance methods on a ConPTY runner, so they
  cannot be called headless. The duration format is now written twice (there
  and `ActivityTrail.DurationWords`); when lane D's work has merged,
  `ScriptRunner.NoteTaskFinished` can call `ActivityTrail.TaskStartedWords` /
  `TaskFinishedWords` / `DurationWords`, and its `FinishedOutcome` may want
  the exit-3 words the mac's `outcomeDescription` has (the window's own
  `--non-interactive` runs, such as a scheduled deploy, would then say so too).
- Test: `HeadlessTaskLinesTests` runs a stub `deploy.ps1` (exit 3, 0, 1) with
  a made-up 32-hex account ID behind `--account`, and reads both lines from a
  redirected trail: no ID, the right place, exit 3 in its own words.
- **Owed to the director:** the issue asks for one MCP deploy on the Mac
  before closing, to confirm the mac's headless path writes both lines. Not
  run (no Mac work tonight).
- No new `mustRecord` event and no contract change.

## For documentation 12

Replace the end of the #736 paragraph ("The mac and the shared Python did
their half in v2.0.0; this app's `CourseConfiguration.CourseName` and its
trail writer are owed … Update this paragraph when the Windows half lands.")
with:

> The mac and the shared Python did their half in v2.0.0, and this app did
> its half in #821: `CourseConfiguration.CourseName` cleans the name in its
> getter and setter, every Save writes it cleaned, the New Course window
> cleans before it trims (`OneLineText`, the mac's rule code point for code
> point), and every trail line is cleaned and redacted by
> `ActivityTrail.SafeTrailLine`. **`OutsideDoor.Clean` stays as it is:** a
> course name now reaches it already clean, but it also cleans the page names
> and the working folder a door carries, which are not course names, and it
> is the last layer before `cmd`. Its tests stay.

Add to the trail section: every trail line about a course gets its place from
`ActivityTrail.Place` (`placeCases`, #946), and `plantoir-mcp.exe` writes
`task started` / `task finished` for every launcher it runs (#774), in the
window's words, exit 3 as "stopped at a question nobody was there to answer
(exit 3)".

## Runs (first Windows VM, 2026-11-21)

- Merged `origin/dev` at 2dcc9a722 (before proving: up to date at da5af161e)
  and again at e18157a2a (dev 10d04bfbd, Undo W6; clean merge, its new event
  untouched). At e18157a2a: the app (x64), the unit tests and the UI tests
  build; 127 + 136 tests in the touched and source-reading classes, all
  passed (`TrailLinesContractTests`, `HeadlessTaskLinesTests`,
  `OutsideGreetingContractTests`, `AgentGuidanceTests`, `LogRedactorTests`,
  `LauncherRunnerCaptureTests`, `ActivityTrailWritersTests`,
  `ActivityTrailWiringTests`, `OutsideAssistantWhilePreviewingTests`,
  `NamedGapLedgerTests`, `UnitPlansGreetingTests`, `TodaysClassContractTests`,
  `UndoWriterScanTests`, `BuildMachineLinesTests`, `ContractTests`, the
  `NewCourseDialog.cs` source scanners, `StopQuestionsContractTests`,
  `TwoWindowSettingsTests`).
- Must-fail: three sabotage commits (local branches `sab774-1`, `-2`, `-3`,
  never pushed; delete with `git branch -D`). Every new or changed test failed
  on its revert, with the case named: the place without `{course} · `
  ("no section was named"), U+202A not removed, the getter and the Save not
  cleaning ("a NUL at the end becomes a trailing space, which is kept: read" /
  ": saved unedited"), the prompt not cleaned, askFound's old words, a
  greeting saying "marks" (caught by `greetingMustNotSay`, and by `where:
  last`), exit 3 in the old words, the started line without its place, the
  unit plan's name not cleaned, and both single orders of the trail writer
  (clean-then-redact: "a NUL inside a Bearer token does not let its tail
  through"; redact-then-clean: "a NUL after Bearer does not hide the token").
- The first VM's fetched runtime predated #965, so the app build refused
  (`CheckNativeRuntimeManifest`) until `fetch-runtime.ps1` placed the
  Visual C++ runtime (`vm-tools/guest/774-app-build.ps1`). The VM was parked
  on its dev snapshot afterwards, so the next writer meets the same refusal;
  the dev snapshot wants refreshing once.

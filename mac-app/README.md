# Plantoir — the macOS App for Containerized Quartz for Teachers

A native macOS app (Swift / SwiftUI) that wraps the command-line toolchain in
a friendlier interface. **The app contains no toolchain logic of its own**: it
edits the same `course_config.json` the setup wizard writes, and every action
runs the real scripts:

| In the app | What actually runs |
|---|---|
| Save (course settings) | Writes `course_config.json` — the file `build_site.py` reads on the next build |
| Preview (section) | `./preview.sh CODE N --port P` under a pseudo-terminal; the site appears in an embedded web view once the announced address responds (up to four sections per folder at once, ports leased per window) |
| Deploy (section) | `./deploy.sh CODE N` with streamed output (and an input field for prompts like the first-time Netlify token) |
| New Course | Writes the chosen settings as `course_config.json`, then runs the real `./setup.sh`, answering each prompt with its default (typing the course code where needed) — scaffolding, backups, and Quartz patches all come from the actual wizard |

A window without a folder asks for a **working folder** — one containing
`setup.sh`, `preview.sh`, `deploy.sh`, and `courses/`, or an empty folder
the app offers to initialize. Working folders are **per window**: each
window restores its own folder across relaunches (frame-keyed) when macOS
keeps windows, a new window beside others inherits the folder of the window
that was key when it was opened, and a window on its own reopens the last
working folder whatever the system setting says — or says in one sentence
why it could not (#311). What the sidebar has
selected belongs to that window's folder: pointing a window at a different
one lets go of the selection and of everything else naming a course, an
archive or a backup in the folder being left — see
[`documentation/09-mac-app.md`](../documentation/09-mac-app.md) → "What a
window lets go of when it changes working folder".

The app also owns delivery and resources: it mirrors the full toolchain
recipe into each working folder's `.toolchain/` (refreshing stale
launchers from its bundle), self-installs missing host tools to
`~/Library/Application Support/Plantoir/tools`, runs one container per
working folder (stopped when the folder's last window closes and at quit,
but only once nothing is using it), and stops Colima at quit only when it
can be ASKED what is running in it, the answer comes back empty, and no
launcher is running anywhere on the Mac. None of that reached a teacher's
Mac until 2026-09-19 — the conditions, the measurements and what was
rejected are in
[`documentation/09-mac-app.md`](../documentation/09-mac-app.md) →
"Quitting: what it frees, what it refuses to free, and why".
Additional actions: Add Section (course context menu), Open in Obsidian
(vault registration included), an Archived sidebar group with restore,
per-section settings for grade-in-title (with a repetition warning) and a
custom domain, and a custom About panel with the Icon Composer app icon.
The complete behavioural log is `../GUI-IMPROVEMENTS.md`.

## Building

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The Xcode project file is generated, not committed:

```bash
cd mac-app
xcodegen generate
open Plantoir.xcodeproj    # or: xcodebuild -scheme Plantoir build
```

The assistant's engine is not committed — 25 MB of llama.cpp build output
(macOS arm64, pinned to build `b10435`). Fetch it once, **before**
`xcodegen generate`:

```bash
./Vendor/fetch-llama.sh
./Vendor/fetch-sparkle.sh
```

The second fetches Sparkle 2.9.6 (#204), which a released Plantoir finds and
installs its own updates with — pinned by version and SHA-256, never committed,
and embedded by `project.yml`, so generation fails without it too. A Debug
build has no update feed and never checks for anything
(`documentation/09-mac-app.md` → "Updating itself").

`project.yml` declares `Vendor/llama` as a resource folder, so generation
fails outright without it ("missing source directory") — this is not an
optional step on a fresh clone. `xcodegen` wires the folder in and the build
copies it to `Plantoir.app/Contents/Resources/llama/`. If a build somehow
ships without it, the assistant reports that its engine is missing rather
than failing in some less obvious way.

## Iterating on this app

There is a skill for it: `.claude/skills/mac-app/SKILL.md`. It covers building
so the app can be run on this Mac, when a clean build is actually required
(folder-reference resources like `Vendor/llama` do not notice content
changes), and — the part that saves the most time — when a change needs a NEW
COURSE or a NEW WORKING FOLDER to be visible, rather than just a rebuild.

## Testing

Three layers, matching how much environment each needs:

```bash
# 1. Unit tests (fast, no Docker): config round-trip, transcript handling
xcodebuild -project Plantoir.xcodeproj -scheme Plantoir test \
  -only-testing:QuartzTeachersTests/CourseConfigurationTests \
  -only-testing:QuartzTeachersTests/TranscriptBuilderTests

# 2. In-process UI walk-through (drives the real window, saves screenshots,
#    verifies the sidebar via the accessibility tree; needs a fixture folder)
TEST_RUNNER_UITEST_WORKSPACE=/path/to/fixture \
TEST_RUNNER_UITEST_SCREENSHOT_DIR=/tmp/shots \
xcodebuild -project Plantoir.xcodeproj -scheme Plantoir test \
  -only-testing:QuartzTeachersTests/InAppUserInterfaceTests

# 3. CLI-equivalence integration tests (need Docker/Colima and the repo
#    workspace; build results are compared against command-line runs)
TEST_RUNNER_INTEGRATION_WORKSPACE=/path/to/repo \
xcodebuild -project Plantoir.xcodeproj -scheme Plantoir test \
  -only-testing:QuartzTeachersTests/ScriptRunnerIntegrationTests \
  -only-testing:QuartzTeachersTests/NewCourseCreatorIntegrationTests
```

**The tests that read the real window run with the app in the background,
and SKIP when its desktop is not showing.** Six classes walk the window's
accessibility tree (`AccessibilityInspector`). macOS leaves a window out of
that tree while it sits on a Space that is not showing — a full-screen app or
another desktop in front — so those tests skip, saying so, rather than fail on
a tree that holds only the menu bar. Being in the background is fine and is
the normal case. **A normal full run has 3 skipped (a fourth,
`QuitScriptRunsTests.testTheSharedMachineIsStoppedOnAClearAnswer`, skips while
any launcher is running on the Mac); more than 3 skipped means read the skip
reasons.** Why, and what was rejected:
`documentation/09-mac-app.md` → "Testing: the tests that read the real window,
and a window on another Space (#249)".

> **Tip:** stop any copy of the app running under Xcode's debugger (⏹)
> before running the UI tests — a debugged instance cannot be terminated
> by the test runner, which fails the first UI test with
> "Failed to terminate ca.russellgordon.Plantoir".

**The test bundle changes one thing about AppKit, on purpose.** Its
`NSPrincipalClass` (`INFOPLIST_KEY_NSPrincipalClass` in `project.yml`) is
`PlantoirTestBundleSetup` — the `@objc` name of `SheetAnimationSuppressor`,
which is the string the Info.plist carries and the test asserts. It asks AppKit
to skip the sheet slide animation
for the life of the test host. Without it the host segfaults inside a nested
runloop whenever a test raises and clears an alert on the real window — 10 runs
in 30 before it existed, 0 in 30 after. Nothing in the shipped app changes, and
the file itself carries the stack, the numbers, and the levers that look like
they should work and do not. If a test ever needs to watch a sheet ANIMATE, that
is the thing standing in its way.

**The suite never asks for the real home folder, and a test says so.** Only
`QuartzTeachers/Models/RealHome.swift` may ask macOS where the home folder is;
everything else takes `RealHome.forFiles`, which is the real home in the app
and one throwaway folder while the unit suite hosts the process.
`RealHomeTripwireTests` scans the product and test sources for every way to ask
(`homeDirectoryForCurrentUser`, `URL.applicationSupportDirectory`,
`expandingTildeInPath`, `getenv("HOME")`, a literal `"/Users/"` …) and fails
naming the file and line. If it fails on something you just wrote, use
`RealHome.forFiles` — or, in a test, a made-up home such as `/Users/teacher`.
What it catches, what it cannot (a child process takes `HOME` from its
environment), and the probes that were measured and rejected are in
`documentation/09-mac-app.md` → "Testing: the real-home tripwire (#264)".

There is also a conventional **XCUITest** suite (`QuartzTeachersUITests`)
that drives the app with synthesized clicks. Running it requires a one-time
macOS approval: the first run fails with "Timed out while enabling automation
mode" until you allow it under **System Settings → Privacy & Security →
Automation/Accessibility** (macOS prompts on first attempt from a logged-in
session). The in-process suite above covers the same flows without that
requirement.

## Design notes

- `CourseConfiguration` keeps the decoded JSON as a dictionary and edits
  keys in place, so config keys added by future toolchain versions survive a
  GUI round trip untouched (verified by unit test).
- Scripts run attached to a real PTY (`PseudoTerminal` + `ScriptRunner`)
  because `docker exec -it` requires a terminal; output is cleaned for
  display by `TranscriptBuilder` (ANSI stripping, spinner collapsing —
  and note `\r\n` handling is scalar-based because Swift folds `"\r\n"`
  into a single `Character`).
- The New Course flow (`NewCourseCreator`) is deliberately "the wizard with
  every answer pre-filled": the app writes the config first, and the real
  wizard re-reads it as saved defaults, so a plain Return accepts each
  prompt. The one exception — the course-code prompt — is answered
  explicitly.
- What a new course STARTS as is decided from bundled resources too:
  `ExampleContentCatalog` looks for `support/example_content/<CODE>/`, and
  failing that `SkeletonCatalog` maps the code's three-letter prefix through
  `support/skeletons/families.json` to one of fifty subject families. The
  sheet then offers that subject's folders as the default list — a music
  course opens with Repertoire, a chemistry course with Investigations. Two
  pure functions carry the rules worth knowing:
  `SkeletonCatalog.structureToAdopt` (never overwrite a list the teacher has
  edited) and `SkeletonCatalog.sidebar` (curriculum hidden, every other
  shared folder gets a chevron, per-section folders stay plain links). A
  third, `WizardStructure`, carries the toggle's OTHER direction — declining
  the skeleton puts the defaults back into every list the teacher has not
  edited since, so the editor shows what will actually be created; its thirteen
  cases are `contracts/shared-rules.json` → `wizard.skeletonToggle`.
- **Built websites are kept OUTSIDE the working folder**, and
  `courses/<CODE>/.merged_output` is a shortcut to
  `~/Library/Application Support/Plantoir/builds/<folder id>/<CODE>`
  (`BuildOutputLocation`). The shortcut is what lets `BuildFreshness`,
  `ScheduledDeploy`, `SectionDetailView`, the three launchers and a launchd
  deploy all keep naming the path they already named. The folder id is the
  same `/bin/pwd -P | shasum` hash that names the folder's container, derived once
  in `BuildOutputLocation.folderIdentifier` (through `FolderIdentity.canonicalPath`,
  the disk's own spelling, which every comparison of two folder paths uses too —
  #189) and used by `FolderContainers` too. The rule is implemented a second time in the launchers' shell, because
  a teacher at the command line and a scheduled publish have no app — the two
  are pinned against `contracts/shared-rules.json` → `buildOutputLocation`.
  **The one thing to know before touching it**: a builds folder with no
  shortcut pointing at it is CLEARED rather than reused, because archiving,
  restoring or replacing a course removes the shortcut and can leave content
  older than the site built from it.
- The colour scheme picker's choices come from the repository's own
  `support/colour_schemes.json`, bundled as a resource at build time — and
  the font previews register the TTFs from `support/fonts/`, the same
  files the container draws social sharing cards with (one font source
  for both).

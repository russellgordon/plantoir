---
name: marketing-screenshots
description: Re-shoot the screenshots on plantoir.app — drive the real app and the real class sites, judge what comes out, and commit only what is right. Use when the interface a teacher sees has changed and the site's images no longer match it.
---

# Re-shooting the screenshots for plantoir.app

**This is an agentic task, not a scheduled one.** `website/shots/capture.py`
does the mechanics — launching the app, switching appearance, exporting the
images and writing the WebP beside each (never scaling a Mac window, #434). It cannot do the part that matters: deciding
whether what came out is a good picture of the product. Four passes were
needed the first time, and every failure looked like success until somebody
opened the images.

So: run it, **look at every image**, re-run the ones that are wrong, and
commit only when they are all right. Budget an hour, and do not start one
twenty minutes before it is needed.

The *reasons* the mechanism is shaped the way it is live in
[`website/README.md`](../../../website/README.md). This file is the procedure
and the judgement.

## Before you start

Ask for the Mac. The run takes it over: the app is driven in front of
everything else, the machine's appearance flips to light and then to dark, and
a browser window opens and closes. **If Russell clicks in the app or quits it
mid-run, XCUITest loses its connection and that pass dies.** Say so before
starting rather than after.

Then check, in this order:

1. **Nothing else is using Xcode.** Two `xcodebuild` runs at once will fight
   over the app bundle, and each will look like a bug in the other. This has
   already produced one "failing" unit test that passed perfectly on its own.
2. **The test target compiles.**
   `cd mac-app && xcodebuild -project Plantoir.xcodeproj -scheme Plantoir -configuration Debug build-for-testing`
   (A plain Debug build wears the "BETA" ribbon icon. `capture.py` passes
   `ASSETCATALOG_COMPILER_APPICON_NAME=Plantoir` to every build it starts,
   so the pictures carry the real icon — keep that if you add a build to it.
   The notification-banner scene also reads the bundle's `CFBundleIconName`
   and rebuilds it plain first, since `--only notification-banner
   --skip-preflight` starts no build of its own.)
3. **The demo folder exists** — `~/Desktop/Teaching` (NOT `~/Teaching`,
   which holds real courses now), with ENG2D, MCV4U and SCH3U in
   `courses/`. If it does not, that is a provisioning run
   (`capture.py --provision-demo`), which is slow and separate. See below.
4. **For `--sites`, the three class sites answer.** They are at
   `<code>-s1-2026-gordon.netlify.app`. A 404 means the demo sites need
   publishing again (`capture.py --publish`), not that the capture is broken.
5. **For the v1.4.0 scenes, the marketing folder is set up** —
   `~/Plantoir Marketing`, made by `capture.py --provision` (see
   "Provisioning" below) — and `capture.py --dry-run` says every scene is
   ready. **Focus is off and Plantoir's notifications are allowed**: the
   notification-banner scene photographs a real notification, and neither
   setting can be read reliably from a script, so ask.

## Two rules about HOW a picture is taken

Both were paid for in ugly screenshots that shipped, and neither is a
preference to be weighed against convenience.

**1. One capture method, and it is `screencapture -x -l <window number>` —
never `-o` — with the window's app ACTIVE.** That is macOS's own window
capture — the programmatic form of Command-Shift-4, Space, click — and it
keeps the window's NATURAL shadow (Russell, 2026-10-03/04, #434: "the
natural shadow that would be captured using the built-in tool"; the release
before had shadows cut off and windows that did not match). It asks
CoreGraphics for the WINDOW, so what comes back has the real rounded corners
and the whole shadow, transparent round them, independent of what is in
front of or behind it. Activate the app and wait about a second first:
macOS draws a smaller, lighter shadow round an inactive window. Measured on
2026-10-04 at 2x: an active window's shadow margin is (112, 76, 112, 148) px
left, top, right, bottom, whatever the window's size —
`shadow.NATIVE_MARGINS`. **A Mac capture is never scaled, trimmed or
cropped**: it is served at its own size, so every single-window picture has
that same margin, and the test fails one that does not.

There used to be a second method. `MarketingScreenshotTests.save` fell
through to XCUITest's `window.screenshot()` whenever the window number could
not be found — a RECTANGLE capture, which bakes the corner curves against
whatever was behind them and hands back **opaque black specks**, invisible on
a dark page and obvious on a light one. It did this SILENTLY, so a run could
file a mix of good and bad shots with nothing to say which was which, and
`mask_window_corners` grew in the Python to paper over the difference. Both
are gone. A failure now stops the run and names the shot.

So: **if black corners ever appear again, the capture went wrong — find out
why it did not go through `screencapture -l`.** Do not paint over them, and
do not add a fallback "just in case": a marketing screenshot is not worth
having if it is the wrong picture.

**The same rule covers every figure assembled from captures** (Russell,
2026-09-27, angry, and not the first time he said it). A figure is built
ONLY from whole `screencapture -x -l` captures, kept intact with their
own alpha and shadow and placed with `Image.alpha_composite` on a canvas
that holds every shadow in full (`composite.native_*`): no crop through a
window or its shadow, no trim, no re-rounding, no mask drawn in Pillow, no
shadow drawn, blurred or scaled, no scaling at all. If a figure must not show
the browser's toolbar, the answer is a window that never had one
(`website/shots/webwindow.swift`), never a crop. `composite.py` used to cut
Safari's toolbar off and paint 18 px corners back on for `colour-schemes`
and `light-and-dark`, and the schedule scene cut the notification banner out
and drew its corners; that code is gone, and `schedule` was retaken from a
native capture of Notification Center's window. The
page's own CSS draws no shadow round a Mac shot either (only a Windows
capture keeps a `drop-shadow` filter). `website/shots/test_native_corners.py`
reads every picture the pages show and fails on a square corner or one
drawn tighter than a real window's, on a shadow cut off at the edge (alpha
above 1 in the outermost 3 px), and on a single-window margin that is not
`NATIVE_MARGINS`; and `capture.py` and `build.py --deploy`
run the same check (the deploy refuses on a failing picture). A
mask drawn at the REAL radius passes it, so the test is a guard, not a proof. **Open
the corners of every image you are about to commit and look** — a native
corner fades over many pixels; a drawn one is tight.

**2. NEVER capture in a Safari private window.** Safari marks a private
window with a dark address bar, deliberately. On plantoir.app that is a black
band across the top of every class-site shot, sitting beside shots that do
not have one, and no visitor can be told why.

The private window was there for a real reason, and the reason still stands:
a class site remembers a light/dark choice in `localStorage["theme"]`, and a
choice saved during ordinary browsing once overrode the appearance a dark
pass had set machine-wide — one course photographed light in a dark run. It
is answered two other ways now, neither of which costs an address bar:

- **A Safari profile named `⎚`** (U+239A CLEAR SCREEN SYMBOL), if one
  exists — separate storage, history and cookies, ordinary chrome. This is
  the same answer Windows gets from `--user-data-dir`. It is made by hand,
  once per Mac: Safari ▸ Settings ▸ Profiles ▸ Start Using Profiles, named
  exactly that one character. Safari offers no way to make one
  programmatically. The run says so when it is missing and carries on in an
  ordinary window.

  **The one-character name is the point, not a whim.** Safari puts the
  profile's name in the window's toolbar, so a profile called "Screenshots"
  would stamp that word across the top of every class site on plantoir.app —
  a caption about our photography, in a picture meant to be about a
  teacher's website. Keep it a single glyph if you ever rename it, and
  change `CAPTURE_PROFILE` in `safari.py` to match.

  Safari's File menu grows a flat `New ⎚ Window` item when the profile
  exists (verified on Safari 26.6); older builds may use a `New Window`
  submenu instead, and `open_profile_window` handles both, matching by NAME
  rather than position because that menu's indices shift when a profile is
  added.
- **`verify_address_bar`**, which stops the run when a shot caught the
  address field focused with its URL selected in blue. Focus is taken out of
  the field with Command-F then Escape — the find bar takes focus off the
  toolbar, and dismissing it hands focus to the web content. **Escape alone
  is not enough**, and that is why this check exists: Escape in a focused
  address field reverts the text and LEAVES THE FIELD FOCUSED, which worked
  often enough to be believed and made the fault a race rather than a bug.
  Measured: a deliberately focused capture reads 3.6% of the toolbar as
  selection blue, a clean one 0.000–0.008%, against a 0.4% threshold.

- **`verify_appearance`**, which checks every capture and stops the run when
  a page came out light in a dark pass or the other way round. It reads the
  median luminance of a band well inside the content: measured across the
  sixteen class-site shots on the site today, light pages median 248–249 and
  dark ones 17–21, against a threshold of 128 — decisive, not a judgement
  call.

Deleting the saved theme instead was investigated and does not work: Safari's
website data lives in a TCC-protected container (`Operation not permitted`
without Full Disk Access), and setting the value needs `do JavaScript`, which
Safari refuses unless "Allow JavaScript from Apple Events" is turned on by
hand in the Develop menu.

## Two permissions you cannot grant

Every invocation of `capture.py` — `--app`, `--sites`, `--provision`,
`--publish`, all of them — asks for both, first thing, before anything else
runs:

```
▶︎ Requesting permissions up front (Safari control, then UI automation)
   If a system dialog appears for either one, approve it now.
```

**This is the moment to hand Russell the Mac and let him walk away.** Both
dialogs appear inside the first minute or so, and macOS remembers the answer
for a while — a run that clears the preflight normally runs the rest
unattended. Before this existed, the two dialogs surfaced lazily wherever the
first Safari or XCTest call happened to land — minutes into `--sites`, or
partway through a hands-off `--app` run — which is the opposite of useful.

The two dialogs, so you recognise them if one is slow to appear:

- **"iTerm2 wants access to control Safari."** Tripped with a one-line
  `osascript` call to Safari — `get version`, deliberately, NOT `activate`.
  Activating brought the teacher's own Safari windows to the front, in
  whatever profile they were in, in the middle of a capture run. Any Apple
  Event raises the same dialog, so there is no reason to steal focus for it.
- **"XCTest is trying to Enable UI Automation."** Tripped by running the
  fixture-based smoke test (`QuartzTeachersUITests/testSidebarShowsExampleCourse`)
  — fast and self-contained, chosen for speed rather than for anything it
  captures.

If the preflight reports it did not pass, a dialog is probably still sitting
on screen unanswered. Answer it and run `capture.py` again — the preflight is
cheap and re-runs on every invocation.

## Running it

```bash
python3 website/shots/capture.py --scenes   # the eleven v1.4.0 scenes (marketing folder)
python3 website/shots/capture.py --app      # the hero and the older app windows (demo folder)
python3 website/shots/capture.py --sites    # the class sites and the phone
python3 website/shots/capture.py --print-set   # what printing does: a preview of MPM2D (~/Plantoir Print)
```

The scenes re-take one at a time too: `capture.py --only reference,two-maps`
(names in `website/shots/scenes.py`). **Unlike `--app`, a scenes run judges
itself**: it exits non-zero, naming the scene, when a picture it owes is
missing or when Vision does not find the words `shots.json → expectText` says
it must show. Still look at every image — a picture can say the right words
and be ugly.

Run **only the half that changed**. Interface work needs `--app`; changes to
the example content, to Quartz, or to a course's colours need `--sites`.

When one shot needs another attempt, do not re-run the other five:

```bash
python3 website/shots/capture.py --app --only test6Assistant
```

**Never run the bare `capture.py` with no flags** unless you actually intend
first-run setup: it also creates courses and publishes the demo sites.

### Judge it by the count, never the exit code

The run is deliberately forgiving — one failed capture does not throw away the
others — so it exits 0 having saved five images out of six. Read the log:

```
grep -E "saved|✗" <logfile>
```

`saved 5 image(s)` when you expected six is a failure. So is `saved 0`.

## Then look at every image

This is the whole job. Downscale and open each one. The images are in
`site/img/`, `<id>-light.png` and `<id>-dark.png`.

Things that have actually gone wrong, each of which passed every automated
check:

- **An empty pane.** Selecting a section shows the preview area, which says
  "No Preview Running" — four fifths of a window saying nothing. Course
  settings fill the pane; section rows do not.
- **Two identical images.** `progress` and `preview` came back byte-identical
  because Quartz serves the previous build instantly, so the "progress" shot
  photographed the finished site. The harness deletes the built pages first
  now; if it happens again, that is why.
- **A tooltip.** The pointer left over a toolbar button pops "Stop previewing
  this section" into frame a second later. The pointer is parked in the
  sidebar's empty area before each shot — if you move that park spot, check
  what is underneath it.
- **The wrong machine entirely.** The phone shot photographed a different
  simulator's home screen. It is targeted by UDID now.
- **An anchor that overshot.** A URL fragment scrolled past the thing the
  caption promises, leaving the LaTeX source where the equation should be.
  Check that each site shot shows what its caption claims.

Compare against `website/shots.json`: every shot's `alt` and `caption` are
there, and **the image must actually show what they say**. If the picture is
right but the words are wrong, fix the words — they live in that one file so
they cannot drift.

## When it fails, what it usually means

| What you see | What it is |
|---|---|
| `Timed out while enabling automation mode` | The authorisation dialog, or a wedged automation session. Ask; then check no stray simulator or runner is left over. |
| `neither element nor any descendant has keyboard focus` | The control exists but is DISABLED. Nearly always the assistant, still loading its model. Wait for `isEnabled`, never for existence. |
| A wait that never ends | Something is waiting for an element that will never appear. Dump the tree — `application.debugDescription` in the failing test — rather than guessing a fourth time. |
| `Lost connection to the application` | Somebody used the Mac, or a second `xcodebuild` started. |
| Five of six saved, no obvious error | Read the `✗` lines. The run keeps going on purpose. |

**Scrolling a settings form is fragile; avoid a shot that needs it.**
`swipeUp()` does nothing to these SwiftUI forms, and `scroll(byDeltaX:deltaY:)`
aimed at the window or at `scrollViews.firstMatch` does nothing either. Two
things DO work: `scroll(byDeltaX:deltaY:)` on the scroll view that CONTAINS the
target (`application.scrollViews.containing(.any, identifier: …)`, what
`testDeclareSecondCurriculum` does since 2026-10-04), and a posted
scroll-wheel CGEvent (`scrollWheel`) — but the latter only from a test runner
holding the Accessibility grant, which a runner built at a new path (a
worktree's own DerivedData) does not: there it silently moves nothing. When a
capture can make its point without a form, prefer that: a published class
site usually makes the same point better than the controls that produced it.

## Put the machine back

The script restores what it borrows, but **verify rather than assume**, and
fix by hand anything a crashed run left behind:

```bash
osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode'
defaults read -g AppleKeyboardUIMode
xcrun simctl list devices | grep Booted
```

- **Appearance** must be what it was. A half-finished run can leave the Mac
  in the wrong colour scheme.
- **Keyboard navigation** (`AppleKeyboardUIMode`) must read what it did
  before. A `--scenes` run switches it off Mac-wide, so no sheet photographs
  with a focus ring, and prints the value to put back; it restores it on a
  normal end, an error, Ctrl-C, SIGTERM and SIGHUP, but not on SIGKILL.
- **Any simulator YOU booted** gets shut down. One that was already running
  is not yours — leave it.
- **Window sizes.** The app's remembered frames are saved and put back around
  the run; if it died mid-way, Russell's window may be 1280×800 now.
- **Bring iTerm back to the front** when you are done. He watches progress
  from across the room, and an app left frontmost hides the transcript.

## Committing

Commit the images **as their own change**, not folded into anything else, so a
shot that turns out wrong can be reverted without unpicking other work. Then:

```bash
python3 website/build.py
python3 website/build.py --check
```

`--check` fails if any page refers to a screenshot that does not exist. It is
the same gate the release checklist runs, so a green check here means the site
is releasable.

Both the PNG and the WebP beside it are committed — the pages offer the WebP
first and fall back to the PNG.

## Provisioning, and when you need it

**The marketing folder** (`~/Plantoir Marketing`), for the v1.4.0 scenes. It is
kept there, but every scene is photographed with it MOVED to `~/Desktop/Teaching`
(the demo folder set aside, both put back after), so no picture says "Plantoir
Marketing". If a run dies mid-way, `~/Desktop/.Teaching (demo folder, set aside
by capture.py)` is left behind and the next run refuses and says how to put it back:

```bash
python3 website/shots/capture.py --provision   # makes it when absent, reuses it when present
```

It makes ICS3U and ICS4U through the app, adds the College Board pages to
both from the public document (kept in `.sources/`, never committed), links
each course's activities from its own correlation file, declares ICS4U's
second curriculum, points both courses at a folder rather than a public site
(their pages print the College Board's words), writes How I Teach, and keeps a
copy of ICS3U for reference. It
never overwrites a file you changed and refuses a folder holding any other
course. Ten learning objectives quote drawn code and are set out by a person
from drafts it writes — it says which, and exits non-zero until they are there.
`website/README.md`, "Regenerating every image", has the whole of it.

**The demo folder**, only on a machine that has never done this, or after `~/Desktop/Teaching` is deleted:

```bash
python3 website/shots/capture.py --provision-demo   # creates the three courses and their state
python3 website/shots/capture.py --publish          # builds and publishes them
```

On Windows the `--app` pass makes and states `~/Teaching` itself (#459): the
`provision` scene makes folders.json's courses through the New Course panel,
then `capture_windows.provision_demo` gives them their state. A `~/Teaching`
whose courses have other sections than folders.json's is deleted and made
again first. By hand, for a folder whose courses the app has already made:

```powershell
python website/shots/capture_windows.py --provision-demo $HOME\Teaching   # no pictures: the state only
```

Provisioning drives the app's own new-course panel three times and runs the
real setup script, so it takes a long while and needs Docker. Then it gives
the folder the state `website/shots/marketing/folders.json` describes
(`demo_folders.py`, #445): the three colour schemes, the teacher's last name,
the sites' markers, and each section's front page on the latest class dated
on or before January 15, every class after it unpublished — asked of the
app's own `--mcp-stdio` door, never written by the script. Every step says
"made" or "already there".

What a door call COSTS, said plainly: on the Mac each change zips the course
into `courses/_backups` (once per course, since every section goes through one
server) and rebuilds that section's site headless (`preview.sh --build-only`,
into the real builds folder, starting the website builder if it is not
running) — four builds for the four demo sections on a first run, and the
Mac's tools have no switch to skip it. `capture.py` runs the door with
`--state-dir` on a temporary folder, so nothing reaches the real activity
trail. On Windows the same tools take `preview: false`, which
`capture_windows.py` passes, so nothing is built; `plantoir-mcp.exe` takes no
`--state-dir`, so its calls DO land on the real trail. A second run, with the
front pages already right, makes no call at all.

**`--publish` from a folder made this way does NOT reach the live sites.** The
live sites' Netlify ids are only in the KEPT demo folder's `.netlify_sites/`
(never committed); a fresh folder gets stand-in markers that name the sites
but carry no id Netlify knows, and deploying from one makes a NEW site. Publish
the live sites from the kept folder, and only when Russell says so. Publishing
needs the Netlify token in the Keychain, which `deploy.sh` reads for itself.

**Everything both folders need is in the repository**, as rules rather than
copies — `website/shots/marketing/folders.json` — except the College Board
pages' words (hand-copied by Russell) and those Netlify ids.
`python3 website/shots/test_demo_folders.py` (in `verify.sh`) proves a clone
can make both; `PLANTOIR_DEMO_FOLDERS_COMPARE=1` adds a read-only check that
the kept folders still match every rule, and `PLANTOIR_DEMO_FOLDERS_APP=<binary>`
runs the front pages through a built app. The course codes, sections and site
names are written in `folders.json` and read by the scripts and the UI tests
alike; the one exception is each class-site SHOT, whose address names the page
it photographs on one course's site (`capture_windows.py`'s
`site_address("MCV4U") + "/concepts/derivative-rules"`, the shots in
`shots.json`) — a shot about a different course is a different shot.

The three courses are ENG2D, MCV4U and SCH3U on purpose: between them the
class sites show prose, typeset mathematics and chemistry notation, which is
most of what anyone doubts a Markdown site can do.

## When NOT to re-shoot

Most releases. If nothing under `mac-app/QuartzTeachers/Views` or
`support/example_content` has changed since the last tag, the images are still
accurate and an hour spent re-taking them buys nothing:

```bash
git diff --stat <last-tag>..HEAD -- mac-app/QuartzTeachers/Views support/example_content
```

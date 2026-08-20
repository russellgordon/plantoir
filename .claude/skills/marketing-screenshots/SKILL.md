---
name: marketing-screenshots
description: Re-shoot the screenshots on plantoir.app — drive the real app and the real class sites, judge what comes out, and commit only what is right. Use when the interface a teacher sees has changed and the site's images no longer match it.
---

# Re-shooting the screenshots for plantoir.app

**This is an agentic task, not a scheduled one.** `website/shots/capture.py`
does the mechanics — launching the app, switching appearance, exporting the
images, scaling them for the web. It cannot do the part that matters: deciding
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
3. **The demo folder exists** — `~/Desktop/Teaching` (NOT `~/Teaching`,
   which holds real courses now), with ENG2D, MCV4U and SCH3U in
   `courses/`. If it does not, that is a provisioning run
   (`capture.py --provision`), which is slow and separate. See below.
4. **For `--sites`, the three class sites answer.** They are at
   `<code>-s1-2026-gordon.netlify.app`. A 404 means the demo sites need
   publishing again (`capture.py --publish`), not that the capture is broken.

## Two rules about HOW a picture is taken

Both were paid for in ugly screenshots that shipped, and neither is a
preference to be weighed against convenience.

**1. One capture method, and it is `screencapture -o -l <window number>`.**
That is macOS's own window capture — the programmatic form of
Command-Shift-4, Space, Option-click. It asks CoreGraphics for the WINDOW, so
what comes back has the real rounded corners already transparent and
antialiased, independent of what is in front of or behind it. Measured: the
four corner pixels of such a capture read `(0, 0, 0, 0)`.

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

**2. NEVER capture in a Safari private window.** Safari marks a private
window with a dark address bar, deliberately. On plantoir.app that is a black
band across the top of every class-site shot, sitting beside shots that do
not have one, and no visitor can be told why.

The private window was there for a real reason, and the reason still stands:
a class site remembers a light/dark choice in `localStorage["theme"]`, and a
choice saved during ordinary browsing once overrode the appearance a dark
pass had set machine-wide — one course photographed light in a dark run. It
is answered two other ways now, neither of which costs an address bar:

- **A Safari profile named `Screenshots`**, if one exists — separate storage,
  history and cookies, ordinary chrome. This is the same answer Windows gets
  from `--user-data-dir`. It is made by hand, once per Mac: Safari ▸ Settings
  ▸ Profiles ▸ Start Using Profiles, named exactly `Screenshots`. Safari
  offers no way to make one programmatically. The run says so when it is
  missing and carries on in an ordinary window.
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
  `osascript` call to Safari.
- **"XCTest is trying to Enable UI Automation."** Tripped by running the
  fixture-based smoke test (`QuartzTeachersUITests/testSidebarShowsExampleCourse`)
  — fast and self-contained, chosen for speed rather than for anything it
  captures.

If the preflight reports it did not pass, a dialog is probably still sitting
on screen unanswered. Answer it and run `capture.py` again — the preflight is
cheap and re-runs on every invocation.

## Running it

```bash
python3 website/shots/capture.py --app      # the six app windows
python3 website/shots/capture.py --sites    # the class sites and the phone
```

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

**Do not add a shot that needs a form scrolled.** XCUITest cannot scroll these
SwiftUI forms — neither `scroll(byDeltaX:deltaY:)` nor `swipeUp()` — so
anything below the fold is unreachable. If a capture needs it, change the
subject instead: a published class site usually makes the same point better
than the controls that produced it.

## Put the machine back

The script restores what it borrows, but **verify rather than assume**, and
fix by hand anything a crashed run left behind:

```bash
osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode'
xcrun simctl list devices | grep Booted
```

- **Appearance** must be what it was. A half-finished run can leave the Mac
  in the wrong colour scheme.
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

Only on a machine that has never done this, or after `~/Desktop/Teaching` is deleted:

```bash
python3 website/shots/capture.py --provision   # creates the three courses
python3 website/shots/capture.py --publish     # builds and publishes them
```

Provisioning drives the app's own new-course panel three times and runs the
real setup script, so it takes a long while and needs Docker. Publishing needs
the Netlify token in the Keychain, which `deploy.sh` reads for itself.

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

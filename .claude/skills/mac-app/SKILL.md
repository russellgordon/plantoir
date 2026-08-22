---
name: mac-app
description: Working on the macOS app (mac-app/) — build it so Russell can run it on this Mac, and tell him exactly what he must do to see the change (clean build, new course, new working folder, or nothing). Use for any change under mac-app/, and for toolchain changes the app carries.
---

# Iterating on the macOS app

Russell tests by **running the app on this Mac**, not by reading a diff and
not inside Xcode's test runner. So a change is not delivered until the app is
built and he has been told, in one line, what he has to do to see it.

**Build it and LEAVE IT QUIT. Do not relaunch it for him.** This reverses the
standing authorisation given on 2026-08-15, and the reason is worth keeping
because it is not obvious from the code: **relaunching makes the app jump in
front of whatever he is doing.** `open` activates, so a rebuild he did not ask
for at that second steals focus from the window he was typing in. He launches
from the Dock when he is ready to test, and that launch is his.

Quit any copy YOU were driving, gracefully, so the app can stop its containers
on the way out — then stop:

```bash
osascript -e 'quit app "Plantoir"' 2>/dev/null
```

Two conditions still hold:

- **Only after a build that SUCCEEDED**, with the bundle confirmed present.
  Quitting his working copy to replace it with nothing is the one genuinely
  damaging move available here.
- **Say what quitting discarded, if it plausibly did.** A conversation's
  undo history dies with its window, an unsaved settings form is lost, and a
  running preview stops. He accepted that trade for a faster loop; he did
  not accept being surprised by it. If he had an assistant window open, a
  single line — "the open conversation's undo history went with it" — is
  the whole of what is owed.

## Every iteration ends the same way

1. **Build it.**
   ```bash
   cd mac-app && xcodegen generate && \
     xcodebuild -project Plantoir.xcodeproj -scheme Plantoir \
       -destination 'platform=macOS' build
   ```
   `xcodegen` first, always: the project file is generated and NOT committed,
   so a new file exists for the compiler only after it runs.

2. **Run the unit tests**, which are fast and worth having every time:
   ```bash
   xcodebuild -project Plantoir.xcodeproj -scheme Plantoir \
     -destination 'platform=macOS' -only-testing:QuartzTeachersTests test
   ```

3. **Check the bundle exists, then leave the app quit for him.**

   ```bash
   APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Plantoir-*/Build/Products/Debug/Plantoir.app | head -1)
   [ -d "$APP" ] || { echo "NOT BUILT — stop; do not quit his running copy"; exit 1; }
   osascript -e 'quit app "Plantoir"' 2>/dev/null
   ```

   **Never quit without checking the bundle exists.** A clean DELETES it (see
   below), and quitting his working copy to replace it with nothing is the one
   genuinely damaging move available here.

   **And do not `open` it afterwards.** `open` activates, so it makes the app
   jump in front of whatever he is doing. His Dock entry points straight at
   that build path — nothing needs copying or re-pointing, and the icon opens
   whatever was last built, when he chooses.

**If you drove the interface to check the change** — activating the app,
sending keystrokes, taking screenshots — bring the terminal back to the front
when that stretch is done, and put back anything the test borrowed (system
appearance, another app's state). Rule 9 in [`CLAUDE.md`](../../../CLAUDE.md)
says why. (It was numbered 7 when this was written; the list has grown since.)

**And rebuild before you report back.** Rule 10 there: the moment you believe
the change addresses what was asked is the moment Russell goes to test it, and
his Dock icon opens whatever was last built. A plain `build` has to be the LAST
build of the session — `xcodebuild test` leaves a test-host bundle behind and
terminates any running copy, so testing after building undoes it.

```bash
osascript -e 'tell application "iTerm" to activate'
```

The one-line summary is the part that saves him time. It is one of:

> Rebuilt and quit — launch it from the Dock; nothing else needed.
> Rebuilt and quit — you will need a NEW COURSE (code XYZ) to see this.
> Rebuilt and quit — you will need a NEW WORKING FOLDER to see this.
> Rebuilt and quit — note the open conversation's undo history went with it.

## Leave no zombie containers behind

**Check this at the end of every session that previewed, deployed or ran
`verify.sh`.** Each working folder gets its own container, named
`teaching-quartz-<hash of the folder path>`, and they are STOPPED rather than
removed when the app quits. They accumulate silently: a count of **75** had
built up by 2026-08-20, one per working folder ever previewed, going back
months. Nothing breaks — a stopped container costs only disk — but it hides
the one container that matters when you are debugging, and `docker ps -a`
becomes unreadable.

```bash
docker ps -a --filter status=exited --filter status=created \
  --format '{{.Names}}' | grep '^teaching-quartz-' | xargs -r docker rm -f
```

Three conditions, and they matter more than the cleanup does:

- **Only STOPPED ones.** A running `teaching-quartz-*` is a live preview —
  possibly Russell's, possibly another agent's in a second window. The
  filters above are what keep it safe; do not simplify them to a bare
  `docker ps -aq`.
- **Only `teaching-quartz-*`.** Colima is shared with his other projects
  (Supabase local dev, among others) — `docker system prune` is the wrong
  tool here and would take those with it.
- **Never `colima stop`**, which is rule 7 in [`CLAUDE.md`](../../../CLAUDE.md)
  and unchanged by any of this.

The next `setup.sh` or `preview.sh` in a folder recreates its container
automatically, so removing one costs a teacher nothing and costs you a few
seconds of container start on the next preview. Say how many you removed —
if the number is large, that is worth him knowing.

## When a clean build is required

A plain rebuild misses some things, and the symptom is always the same:
your change is definitely in the source and definitely not in the app.

Clean when you have changed:

- **`project.yml`** — build settings, or which files are bundled.
- **anything inside a FOLDER-REFERENCE resource.** `Vendor/llama` is copied
  as a whole folder (`type: folder`), and Xcode does not notice when its
  CONTENTS change. Re-running `Vendor/fetch-llama.sh` and rebuilding gets you
  the old binaries.
- **bundled toolchain files** the app carries — `../scripts`, `../support`,
  `../patches`, `../Dockerfile`, the launchers in all three forms (`../*.sh`,
  `../*.bat`, `../*.ps1` — setup, preview and deploy of each), and the two
  individually named `../support/*.json` files (`colour_schemes.json`,
  `ontario_secondary_courses.json`). These are resources; a stale copy in the
  bundle is a very confusing hour.

**A clean DELETES the built app, so never stop halfway.** Verified: after
`xcodebuild clean` the `.app` is gone from `Build/Products/Debug/` while the
DerivedData folder and its hash survive. The Dock entry therefore still points
at the right PATH, but at nothing — and if he clicks it in that window, macOS
can turn the entry into a "?" and drop it. So clean and rebuild in ONE
command, and check the bundle is back before saying a word:

```bash
cd mac-app && xcodebuild -project Plantoir.xcodeproj -scheme Plantoir clean && \
  xcodegen generate && xcodebuild -project Plantoir.xcodeproj -scheme Plantoir \
    -destination 'platform=macOS' build
```

**After a clean, the Dock icon goes blank even once the app is back.** The
bundle is fine — it carries `Assets.car`, `Plantoir.icns`, and both
`CFBundleIconName` and `CFBundleIconFile` — but macOS cached "nothing there"
while the app was missing, and rebuilding does not invalidate that cache. Fix
it as part of the clean rather than leaving him with an unlabelled square:

```bash
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Plantoir-*/Build/Products/Debug/Plantoir.app | head -1)
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
killall Dock
```

`killall Dock` is safe — the Dock restarts immediately and keeps its entries —
but say that you did it, because the screen flickers.

If that still misbehaves, removing the project's whole DerivedData folder is
the last resort, and it is a bigger deal than a clean: the folder name carries
a per-project hash (`Plantoir-bzuacszrcleopbgiavzdpqasfyky`) and Xcode
generates a NEW one, so the path itself changes and the Dock entry is left
pointing somewhere that will never exist again. A clean is recoverable by
rebuilding; this is not. **Ask first**, and afterwards he has to drag the
freshly built app back to the Dock. To see where the entry currently points:

```bash
# The path the Dock entry currently opens
defaults read com.apple.dock persistent-apps \
  | grep -A3 -i '_CFURLString.*plantoir'
```

## When he needs a NEW COURSE

Anything installed **at course creation** only reaches a course made
afterwards. An existing course keeps the shape it was born with.

Tell him to make a new course when you changed:

- **`support/example_content/<CODE>/`** — the payload is poured in at
  creation. Name the CODE he should use, because only that code shows it.
- **`support/skeletons/`** — same, but for any code with no payload; name a
  code that has none (e.g. `AVI2O`).
- **`scripts/setup_course.py`** — folders, per-section files, sentinels,
  dates, anything the installer writes.
- **new `course_config.json` keys written by the wizard.** Alternatively he
  can hand-edit the JSON of a course he already has, which is quicker — offer
  that if it is one key.

He does NOT need a new course for:

- **`scripts/build_site.py`** — that runs at every build, so previewing an
  existing course shows it.
- **the assistant, the sidebar, settings, deploys, previews** — all read the
  course as it is.

## When he needs a NEW WORKING FOLDER

Rarely, and it is worth being sure before asking — it means recreating
courses. The launchers and `.toolchain/` are **refreshed automatically** in
any folder the app opens (`refreshLaunchersIfNeeded` / `refreshToolchain`),
so changing a `.sh` or the image recipe does **not** need one.

Only ask for a new folder when testing:

- **first-run adoption** — the picker, initialising an empty folder, what a
  brand-new folder gets.
- **per-folder behaviour itself** — container naming, the port block, two
  folders open at once.

## Other state that hides a change

Ordinary rebuilding does not clear these. Clear them yourself and say so.

| Changed | Clear |
|---|---|
| Model tier, download URL or size | `rm -rf ~/Library/Application\ Support/Plantoir/models` — otherwise the OLD weights are found and the new tier never downloads |
| Plan mode's "stop asking" answer | `defaults delete ca.russellgordon.Plantoir AssistPlanModeTurnedOff` |
| Scheduled deploys | `launchctl bootout gui/$(id -u)/ca.russellgordon.Plantoir.deploy.<CODE>.section<N>` and delete the plist in `~/Library/LaunchAgents` |
| Colima's CPU/RAM sizing | Sizing applies when the VM is CREATED, or on a start while it is stopped. `colima stop` then start, or `colima delete` for a clean one. **Ask first** — it is shared with his other toolchains |
| The Docker image | Rebuilt automatically when the recipe hash changes. `./verify.sh` forces the whole path |

## Running the tests without chasing ghosts

- **UI tests need the machine to themselves.** Two `xcodebuild test` runs at
  once make the harness see two app processes and fail with
  "Root elements for target … should be equal". If agents are running builds,
  wait for them. Run UI tests alone:
  `-only-testing:QuartzTeachersUITests`.
- **A stray preview server fails the preview tests.** `python3 -m http.server
  8081` left over from earlier work holds the port; `pkill -f "http.server"`.
- **`verify.sh` needs a terminal**: `script -q /dev/null ./verify.sh`.
- Do not report a UI-test failure as real until it has been run alone on a
  quiet machine. That mistake has been made here before.

## Every macOS improvement is written up for Windows, as you go

**Standing rule, not a courtesy.** The Windows app is being built from what
this side learns, by somebody who cannot see the macOS code or watch it being
tested. A change that only exists in Swift is a change they will re-derive
from scratch, usually badly, and usually after shipping the same bug once.

So a macOS change is not finished until BOTH of these are true:

1. **`GUI-IMPROVEMENTS.md` has an entry, and its "Notes for Windows port"
   column actually says something.** That column is not optional. Every one
   of the entries so far has one. Useful notes say what Windows must do
   differently, what it can inherit unchanged, and — most valuable — the trap
   that would look correct in review. "Shared Python, nothing to mirror" is a
   fine note when true; an empty cell never is.
2. **Anything architectural also gets a section in `WINDOWS-HANDOFF.md`.** A
   log row records a decision; the handoff explains it well enough to
   implement. Rule of thumb: if you needed more than a sentence of reasoning
   to get it right, they will too.

**Corrections count as improvements.** When a change makes existing Windows
guidance WRONG, fixing that guidance is part of the change. This has already
bitten twice in one night: the handoff still told Windows "the visible verb
is Publish, never Deploy" long after rows 140 and 143 reversed it, and the
per-conversation backup rule silently invalidated the pruning advice above
it. Stale guidance is worse than none — they will follow it.

**Say what you measured, not just what you decided.** Numbers travel; taste
does not. "The 3B inverts polarity 9 times in 10" is something they can act
on. "We chose the 4B" is not.

**Write down the REASONING, not only the behaviour — and do it as you go.**
This is the part that is always skipped and always the most expensive to
lose. A behaviour can be read off the code; the reason it is that way cannot,
and **a rule whose reason has been lost gets "simplified" back out by the
next person who reads it.** Everything below was learned the hard way and
would look like clutter to somebody who did not know why:

- why the tools are coarse (the 8-of-8-wrong / 8-of-8-right result);
- why publish and unpublish are separate verbs and the surface has no
  booleans (a boolean inverted polarity on a real model);
- why unpublish's linked-page rule is NOT the mirror of publish's;
- why some phrasings are matched in code and never reach the model;
- why the model's tool list is shorter than the server's;
- why there is no delete tool at all.

So: when a decision has a reason that is not obvious from reading the code,
the reason goes in `WINDOWS-HANDOFF.md` in the same change that makes the
decision. Not afterwards, not in a batch, and **not only when Russell asks —
he has said plainly that he will forget to, and it is not his job to
remember.** Record the roads NOT taken too, and why: an option rejected for
a good reason will otherwise be proposed again, considered afresh, and cost
the same afternoon twice.

Design conversations count as work. If a decision was reached by talking it
through rather than by writing code, it still gets written down before the
conversation moves on — that reasoning exists only in the conversation, and
conversations are the thing that gets summarised away.

## The interface never names the machinery

The oldest rule in this project, and the assistant broke it: no "toolchain",
"script", "Docker", "container", "WSL" — and **no model names**. A download
sheet reading "Plantoir picked Qwen3 4B to suit this Mac's memory" tells a
teacher nothing they can act on and quite a lot about plumbing they never
asked about.

Say **"the small assistant"** and **"the larger assistant"**. That is what
`AssistModelTier.displayName` returns, and it is the only thing shown; the
real model lives in `fileName` and `downloadURL`, which a teacher never sees.
A test (`testWhatTheTeacherIsShownNamesNoModel`) fails if a model name, a
parameter count or a file format reaches that string.

The same goes for anything else the assistant surfaces: tokens, context
windows, quantisation, Metal, GPU layers, inference. If a sentence would only
make sense to somebody who has read the source, it is not ready to show.

Two exceptions, both non-teacher-facing: `GUI-IMPROVEMENTS.md` and the
handoffs record what was measured and must name models precisely, and code
comments should too. The rule is about what appears on screen.

## Open investigations — read these before touching the area

- **The preview showing stale content**:
  [`research/preview-staleness/FINDINGS.md`](../../../research/preview-staleness/FINDINGS.md).
  Several fixes have landed and the symptom was still reported afterwards.
  The live-reload suspicion recorded there was TESTED on 2026-08-15 and the
  hoped-for simplification is off the table: the websocket port mismatch is
  real, but live reload is dead anyway because file events from Mac-side
  writes never cross the Colima bind mount — the watcher inside the
  container sees nothing when Obsidian or the assistant writes a file. The
  timing machinery in `waitForPreviewServer` is therefore LOAD-BEARING; do
  not delete it in favour of live reload. The document's closing section
  lists the four changes that would all be needed before live reload could
  take over.

  Two traps recorded there that cost hours: a request's cache policy covers
  only the main request, so a single-page app can still assemble a stale page
  from cached parts; and the build happens inside the Linux VM, whose clock is
  its own, so "is this file newer than now?" is not a question worth asking —
  wait for the value to CHANGE instead.

## Things that are easy to get wrong

- **`Vendor/llama` is not committed.** A fresh clone must run
  `mac-app/Vendor/fetch-llama.sh` once or the assistant reports its engine is
  missing. The app still builds and runs without it.
- **The assistant's model is not bundled** — it downloads to Application
  Support on first use. Changing the tier means the old file is still there
  under its own name; see the table above.
- **A conversation's undo dies with its window**, and Restore only reaches
  back to the start of that conversation. When asking him to test either, say
  which window to keep open.
- **Every measurement in the assistant's documentation came from this
  48 GB M4 Pro.** Anything about memory pressure on an 8 GB Mac is unverified
  — say so rather than implying it was tested.

# READ THIS FIRST: Russell's own instructions for this task (they override anything below that disagrees)

Russell said, in his words: "Use the same screen capturing approach that we
do for making the marketing website. Annotate the same way we do when you
help me make tutorials for ICS3U or ICS4U."

## 1. Capture the way the marketing website's screenshots are captured

That is the `marketing-screenshots` skill
(`<repo>/.claude/skills/marketing-screenshots/SKILL.md`)
and its harness `website/shots/capture.py` with `website/README.md`: the real
app launched ISOLATED by the UI test target (`IsolatedLaunch`, `--state-dir`),
driven by XCUITest scenes, each window exported as an image, never a scaled
Mac window. Read the skill and the README IN FULL before anything else and
follow their procedure and their judgement ("look at every image").

- You need new SCENES for the new interface. Add them the way the existing
  marketing scenes are written (find them in the UI test target and in
  `website/shots/`), in the MAIN checkout
  `<repo>`, on a LOCAL branch
  `scratch/ui-tour-captures` made from `dev` (commit there so the tree is
  clean; do NOT push it and do NOT merge it; it is scratch for this page).
  This replaces the "do not edit any checkout" and "do not run xcodebuild"
  lines below, for the main checkout only. Never touch `plantoir-second` or
  `plantoir-gate`.
- Write the images into `S/ui-tour/shots/`, NOT into `website/`: nothing of
  this goes on plantoir.app, and no file under `website/` or `site/` changes.
- The harness flips the Mac's appearance and takes both light and dark.
  Capture BOTH for every scene if the harness makes that cheap (the review
  page shows the picture that matches the viewer's theme); if time is short,
  DARK comes first: Russell's standing preference for screenshots is Dark
  Mode. Put the system appearance back exactly as you found it and say so.
- The skill says to ask for the Mac: Russell has already given it ("You have
  the keyboard; I'm stepping away from the computer"). Another agent may be
  running `xcodebuild build` in `plantoir-second` with its own derived data:
  if a run of yours fails oddly, wait for `pgrep -x xcodebuild` to print only
  your own and try once more.
- A test run turns the Debug bundle into a TEST HOST and that bundle is the
  one Russell's Dock icon points at for his smoke test. So your LAST acts,
  in this order: check out `dev` in the main checkout (clean), run
  `cd mac-app && xcodegen generate && xcodebuild -project Plantoir.xcodeproj -scheme Plantoir -configuration Debug build`,
  confirm `BUILD SUCCEEDED` and that
  `~/Library/Developer/Xcode/DerivedData/Plantoir-<id>/Build/Products/Debug/Plantoir.app`
  exists, leave the app QUIT, and bring iTerm to the front.

## 2. Annotate the way the ICS3U and ICS4U tutorial screenshots are annotated

The house style (from Russell's tutorial work):

- A red rounded rectangle (`#d0312d` or close), about 6 px thick at Retina 2x,
  around each control being pointed out.
- A solid red filled rectangular LABEL with bold white sans-serif text IN
  WORDS ("Open in Browser", "Unit popup", "Make the Map Again"), sitting just
  inside or beside the box.
- NO numbered circles and NO arrows. Where order matters, number inside the
  word labels ("1. Share", "2. Protect").
- Do NOT crop tightly: keep enough of the surrounding window that the viewer
  can see where the control lives.
- Annotate with PIL at the captured resolution. KEEP THE RAW capture beside
  the annotated copy: `name.png` (raw) and `name-annotated.png`, and the same
  with `-dark` / `-light` in the name when you have both.
- Nothing in any picture shows a teacher's name, e-mail, account or home
  path.

Label what is NEW in v2.0.0 in each picture, in a teacher's words (the
control's own name as the app shows it). Two to five labels a picture; a
picture with nothing new in it does not belong on the page. Look at every
annotated image before keeping it: a label must not cover the thing it names
or any text a reader needs.

In `manifest.json` give, for each scene: `raw` and `annotated` file names for
each mode you captured, and `labels`: the words on the picture, in order.

---

# Brief: capture the new v2.0.0 interface from the real app, for a design-review page

Russell (the teacher who owns Plantoir) asked for a page that shows the UI
built in v2.0.0 so he can judge its UX. He has stepped away and said "You
have the keyboard", so for THIS task you may drive the real app on screen.
You are the ONLY agent allowed to touch the screen. Work at HIGH EFFORT.

S = `<scratch>`.
Read first: `<repo>/CLAUDE.md` rules 9 and 10;
`<memory>/driving-the-app-with-a-scratch-folder.md`;
`<repo>/.claude/skills/marketing-screenshots/SKILL.md`
and `website/shots/capture.py` with its helpers (they already know how to
launch the app isolated, drive it and capture ONE WINDOW); and
`documentation/09-mac-app.md` → "Testing: the UI target keeps its state in
`--state-dir`".

## Hard rules

- The app to drive: the Debug build at
  `~/Library/Developer/Xcode/DerivedData/Plantoir-<id>/Build/Products/Debug/Plantoir.app`
  (it is `dev` at <commit>, built today). DO NOT rebuild it, do not run
  `xcodebuild` at all, do not edit any checkout (never touch
  `<repo>`, `plantoir-second`, `plantoir-gate`
  except to READ).
- Launch it ISOLATED: `--state-dir` pointing at a fresh folder under
  `~/plantoir/ui-tour-state/` (the app treats that folder as home, so the
  scratch working folder sits INSIDE it; Colima mounts only the real home, so
  it must be under `~`). NEVER open, list or touch `~/Desktop/Class Websites`,
  `~/Desktop/Teaching`, iCloud, or any real course. NEVER quit, activate or
  touch the copy of Plantoir running from `/Applications` (it is Russell's own,
  serving an assistant): address your copy by its process id only, never by
  name (`osascript` "tell application Plantoir" could hit the wrong one: use
  System Events with the unix id, or the harness's own way).
- Capture ONE WINDOW at a time by its window id (`screencapture -l <id> -o -x`),
  never the whole screen, never a region that could include another app. Look
  at EVERY capture before keeping it; delete at once any capture that shows
  anything other than your copy of Plantoir, a browser page of the scratch
  course, or a Terminal window you opened for this.
- Nothing personal in any capture: the scratch course is the repository's
  example course (`support/example_course/EXC2O`, and example payloads under
  `support/example_content/` for other codes); no real person's name, no real
  site address, no credential. If a sheet shows the Mac's user name or a real
  path with a name in it, crop it out or do not keep it.
- NO real deploy, NO sharing to Cloudflare, NO credential: capture the share
  bar and any sheet reachable WITHOUT sending anything. A sheet that only
  appears after a real share is skipped and listed as not captured.
- NO SOUND (the Mac is muted; leave it). No change to system appearance
  unless you put it back and say so: capture in LIGHT mode; if the Mac is in
  Dark Mode, capture in dark and say so, do not toggle it.
- When finished: quit YOUR copy only (by pid), stop any preview you started
  with the launcher's own `--stop`, leave nothing running, and bring iTerm to
  the front (`osascript -e 'tell application "iTerm" to activate'`). Say what
  you touched and that you put it back.

## What to capture (each as a PNG in `S/ui-tour/shots/`, max 1800 px wide; downscale with `sips` if larger)

Set up the scratch working folder so each of these exists. Unit plans: copy
the shipped template's example plan into `courses/EXC2O/.internal/planning`
the way the unit-planning skill does (read
`support/agent_guidance/skills/plantoir-unit-planning/` and
`scripts/test_unit_plan_template.py` for how a plan folder is made), so the
Planning tab has two or three invented units to show. A preview build of
section 1 gives the Coverage tab its map (the example course has curriculum
expectations; if a build is too slow or fails, say so and capture the empty
state).

1. The course page with its tabs, **Planning** selected: a unit's plan; the
   Unit popup open; **All Plans**; the header with Reload and **Open in
   Browser**; the correlation page.
2. The **share bar** at the foot of the Planning tab in its not-shared state,
   and any state reachable without sharing (the Protect choice, the Include
   Answer Keys tick, a Netlify-teacher explanation if the course's saved
   destination can be set to Netlify in the scratch config).
3. A section's page with its tabs: **Website**, **Coverage**, and Problems if
   there are problems. Coverage: the map; the "made when" line; **Make the Map
   Again** while it is making; the empty state for a section never built.
4. The **Reference Courses shelf**: the New Course wizard with **Keep this
   course for reference** (a code with ready-made pages, e.g. one of the
   payload codes), the offer under a taken-code refusal, the shelf heading's
   menu (**New Reference Course…**, **New Group**), a course row's menu
   (**Move to Group ▸**, Import for Reference on a backup row), the **Replace
   It…** warning, a made group with a course in it, the Remove Group question.
5. **Deploy greyed** while another program holds the course: write a lease
   file by hand into `courses/.internal/activity/` in the shape
   `contracts/file-formats.json` → `workLease` gives, held by a live process
   of your own (a `sleep`), and capture the section's toolbar with Deploy
   greyed and its help showing if a hover can be captured; remove the lease
   and capture it back.
6. The preview of the example course's GeoGebra page in a browser window you
   open for this (Safari or Chrome, a NEW window, closed afterwards): the
   sketch's **opening** state if it can be caught, and the sketch open with
   its reset icon. If catching the opening state is unreliable, skip it.
7. Anything else new that you notice a teacher would see and that is on
   `dev` since v1.9.3 (grep `documentation/09-mac-app.md` for #708, #709,
   #793, #803, #572, #729, #742, #780).

Take what works and move on: a missing capture listed honestly is better
than an hour lost. Budget about 60 minutes.

## Deliver

`S/ui-tour/shots/manifest.json`: a list of `{file, feature, issue, title,
whatItShows, mode (light|dark), howReached}` in the order above, and
`S/ui-tour/shots/NOT-CAPTURED.md` listing what you could not capture and why.
Report in under 200 words: how many captures, what is missing, what you
touched and put back, and anything about the interface that looked WRONG or
awkward while you drove it (clipped text, a control that did nothing, an
unclear sentence, a layout that jumped): those observations are as valuable
as the pictures.

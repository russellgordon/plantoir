# plantoir.app

The marketing site. Sources live here; **finished pages are written into
`site/`**, which is what gets published. Nothing in this folder is served.

Publishing is explicit: the Netlify site is NOT connected to GitHub, so
pushing this repository deploys nothing. Build, preview `site/` locally,
and deploy when it is right (delta upload — an unchanged site sends nothing;
token from the `containerized-quartz-netlify` Keychain item or
`NETLIFY_AUTH_TOKEN`, site id from `website/site.json`).

```bash
python3 website/build.py                 # write site/
python3 website/build.py --check         # report problems, write nothing
python3 website/build.py --serve         # preview locally; edits rebuild on refresh
python3 website/build.py --deploy        # build, then publish to plantoir.app
python3 website/build.py --verify-deploy # fetch plantoir.app, confirm it matches site.json
```

`--deploy` automatically runs the same check `--verify-deploy` does once Netlify
reports the upload ready — it fetches `https://plantoir.app` and confirms the
page's version-note line matches `site.json`, retrying a few times since
Netlify reporting "ready" and its CDN actually serving the new content are not
the same instant. This is advisory, not a build failure: a network blip
fetching the check is never treated as evidence the deploy itself failed, only
a genuine, persistent version mismatch is (`website/netlify_deploy.py`,
`verify_live()`). Run `--verify-deploy` on its own to check a past deploy
without publishing anything new.

plantoir.app is itself a free-tier Netlify project, so `--deploy` also writes
`site/_headers` — a Content-Security-Policy that keeps Netlify's own
"Powered by Netlify" ad badge off the site, the identical fix
`scripts/deploy.py` applies to every class site (see
`documentation/07-deployment.md`, "Suppressing Netlify's own ad badge"). The
scanning logic lives once, in `scripts/netlify_badge.py`, and
`website/netlify_deploy.py` imports it rather than carrying its own copy;
`website/test_netlify_deploy_headers.py` covers the wiring.

## What is where

| File | What it is |
|---|---|
| `site.json` | Site-wide facts: the tagline, the repository, the current version and release month, the order of the navigation, and the live example sites. |
| `shots.json` | One entry per screenshot: its id, how it is captured, its alt text and its caption. |
| `layout/base.html` | The page skeleton every page is poured into — head tags, top bar, footer. |
| `assets/style.css` | The whole stylesheet, copied to `site/assets/`. |
| `pages/*.html` | One file per page: a front matter block, then the body. The file name is the URL (`features.html` → `/features`), except `index.html`, which is the front page. |
| `shots/` | The screenshot harness. See below. |

## Writing a page

```html
---
title: What Plantoir does — Plantoir
description: One sentence, used for search results and link previews.
nav_label: Features
---

<div class="page-head">
  <h1>What it does</h1>
  ...
```

`title`, `description` and `nav_label` are required. `body_class` is optional
(the front page uses `home`).

Inside the body you can use:

- `{{shot:courses}}` — a screenshot, by its id in `shots.json`. Add a modifier
  with a pipe: `{{shot:site-phone|device}}` for a capture that already has a
  device drawn around it, `|narrow` for one that should not be widened.
- `{{version}}`, `{{released}}`, `{{repo_url}}`, `{{support_email}}`,
  `{{tagline}}`, `{{site_name}}`, `{{base_url}}` — from `site.json`.
- `{{demo_links}}` — the list of live example class sites.

A page that leaves a `{{placeholder}}` unfilled, or names a screenshot that
does not exist, is reported. `--check` turns that into a non-zero exit, which
is what the release checklist runs.

**Add a page to `site.json`'s `nav` list** or it will be built but never
linked.

## Screenshots

Every image on the site is captured from the real app and the real class
sites, twice — once in light appearance and once in dark. Screenshots are
also **platform-aware**: Windows visitors see native Windows WinUI 3
screenshots, while macOS/other visitors see native macOS SwiftUI screenshots.
Full architecture and pipeline documentation is in [`SCREENSHOTS.md`](SCREENSHOTS.md).

### Capturing on macOS

```bash
python3 website/shots/capture.py            # everything
python3 website/shots/capture.py --app      # just the app windows
python3 website/shots/capture.py --sites    # just the class websites
```

It provisions a demo working folder (`~/Teaching` by default) with three
courses — ENG2D, MCV4U and SCH3U — by driving the app's own new-course panel.
It then builds and publishes those sections, photographs the app through the
marketing UI tests (`mac-app/Tests/QuartzTeachersUITests/MarketingScreenshotTests.swift`),
photographs the published sites in Safari and on an iPhone in the Simulator, and
rebuilds the pages.

### Capturing on Windows

```powershell
python website/shots/capture_windows.py
```

It autonomously launches `Plantoir.exe --capture-marketing-shots site/img`,
provisions demo courses in `%TEMP%`, stages each view (`courses`, `new-course`,
`progress`, `preview`, `assistant`) across both `ElementTheme.Light` and
`ElementTheme.Dark`, captures 2x HiDPI `RenderTargetBitmap`s, generates WebP
companions, and rebuilds the site.

### What it borrows and puts back

The Mac's appearance, the app's remembered window sizes, the frontmost
application, and any Safari window it opened. It holds off sleep while it runs
so a capture started at night survives the displays going dark — but the Mac
itself has to stay awake and unlocked.

### Things that do not work, and what was done instead

Written down because each cost an afternoon:

- **`xcodebuild` does not hand its environment to the test runner.** The demo
  folder arrives as `TEST_RUNNER_MARKETING_WORKSPACE`. Passing it unprefixed
  gives a green run with one skipped test and no screenshots — success, with
  nothing to show for it. Check the count of captured images, never the exit
  code.
- **XCUITest cannot scroll these SwiftUI forms.** Neither
  `scroll(byDeltaX:deltaY:)`, which is accepted and does nothing, nor
  `swipeUp()`. So no capture may depend on anything below the fold. That is
  why there is no shot of the per-section colour and typography controls: the
  class sites make the same point.
- **The assistant's box exists long before it works.** The window opens saying
  it is starting, and the box stays disabled — and a disabled field cannot
  take keyboard focus — until the model has loaded. Waiting for `isEnabled` is
  the only readiness signal that means anything.
- **The prompt shelf cannot be driven.** Its groups are DisclosureTriangles
  that do not open from a synthesized click, so the phrasings inside them are
  unreachable from a test.
- **Quartz serves the previous build immediately.** A section that has been
  previewed before comes back too fast to photograph its progress, so the
  harness deletes that section's built pages first.
- **The class site inside the app's preview renders dark even in a light
  capture.** Quartz reads `(prefers-color-scheme: light)` and treats anything
  else as dark, and the embedded web view does not report a light preference.
  Nothing in the app's own appearance is wrong; the site simply chooses dark.
  Left as it is rather than clicking the site's own toggle from a test, which
  would then persist and reverse the problem in the other pass.

### Why not a headless browser

The class sites are photographed in Safari on a real screen because that is
what the type rendering, the scrollbars and the window chrome actually look
like on a Mac. A headless renderer approximates all three. The phone shot uses
the Simulator with RocketSim drawing the device around it, for the same
reason.
## plantoir.app is generated, and its screenshots are taken by a robot

The marketing site used to be one hand-written `site/index.html`. It is now
four pages — home, features, day to day, support — generated by
`python3 website/build.py` from sources in `website/`. Netlify still deploys
`site/`, unchanged, so nothing about hosting moved.

**Nothing here needs a Windows implementation for the site itself.** It is one
site for one product; a second one built on Windows would be a second product.
What Windows owed it was *pictures* — and that harness is now built and used:
`website/shots/capture_windows.py` and `website/shots/hero_windows.py` capture
every id in `website/shots.json` from a real Windows machine, and
`site/img/` carries the `<id>-windows-light.png` / `<id>-windows-dark.png`
pair for every one of them (`hero`, `assistant`, `courses`, `coverage`,
`colour-schemes`, `light-and-dark`, `new-course`, `preview`, `progress`,
`search`, and all four `site-*` shots) — confirmed 2026-08-22. This section
used to describe the harness as future work owed once the Windows app shipped;
it has shipped and this is done. What follows below is now history — how the
mac's own capture mechanism works and why it could not simply be copied — kept
because the lessons in it are real, not because the task is still open.

### What Windows built

Every image on the site exists twice, `<id>-light.png` and `<id>-dark.png`,
because the pages swap them with `<picture>` and
`media="(prefers-color-scheme: dark)"`. The ids are listed in
`website/shots.json` along with their alt text and captions. Windows captures
a third and fourth file per shot — `<id>-windows-light.png`,
`<id>-windows-dark.png` — using the same ids.

### Why the mac's capture mechanism will not port

Three mac-specific things carry this, and each needs its own Windows answer:

- **The window screenshots are native single-window captures, not test-runner
  screenshots.** The tests drive the app with XCUITest, but the pixels come
  from `screencapture -x -o -l <window-id>` — the programmatic equivalent of
  Command-Shift-4, Space, Option-click — because that is the only capture that
  delivers the window's rounded corners genuinely transparent, with macOS's
  own subpixel anti-aliasing. `window.screenshot()` was used first and bakes
  the desktop into the corner curves; masking the corners off afterwards
  approximates the radius and leaves stray fringe pixels, which is exactly the
  rendering-bug look a marketing page cannot carry (fixed in commit
  `63495853`). Whatever Windows uses (WinAppDriver, an accessibility-driven
  harness, `PrintWindow`) has to produce the window alone with its real alpha
  channel, not a screen crop and not a rectangle that gets its corners shaved
  off in post.
- **The window SIZE is forced, not remembered.** Passing
  `-"NSWindow Frame <autosave-name>" "<frame>"` as a launch argument puts the
  frame in AppKit's argument domain, which outranks the saved value — so every
  capture is 1280×800 regardless of where the window was left. The capture
  script saves and restores the remembered frames around the run, because the
  app writes them back on quit. Windows needs an equivalent: force the size,
  and put the teacher's own window size back afterwards.
- **Appearance is switched machine-wide.** There is no per-app override that a
  SwiftUI app reads, so the run sets the Mac to light, captures, sets it to
  dark, captures, and restores whatever it found — in a context manager, so a
  crash mid-run still puts it back. Windows has a per-user app/system theme
  setting; whatever is used there, restoring it is not optional.

### The trap that cost the most time here

`xcodebuild` does **not** hand its own environment to the test runner process.
Setting `MARKETING_WORKSPACE` and running the tests produced a green run with
one skipped test and no screenshots — success, and nothing to show for it. The
variable has to be passed as `TEST_RUNNER_MARKETING_WORKSPACE`, which arrives
in the test as `MARKETING_WORKSPACE`. Expect the same hop in whatever runner
Windows uses, and check the *count of captured images*, never the exit code.

### Three more traps, met on 2026-08-19, that will port themselves

- **The assistant photograph depends on a Settings toggle.** The picture is of
  the "Shall I go ahead?" card — but that card only appears when "ask before
  changing" is on, and the development machine's own copy may have it turned
  off. With it off the assistant does not fail: it CARRIES OUT the request,
  the capture shows "Unpublished 1 page." instead of a plan, and the demo
  course really has a page hidden in it afterwards — which then poisons the
  *other* appearance's capture with "It's already hidden." The harness must
  stage the setting on for the run and restore the teacher's own value after,
  exactly as it stages window frames (`capture.py` does this now). Windows
  keeps an equivalent setting; `capture_windows.py` photographs the assistant
  and needs the same staging.
- **Photograph progress when a step is NAMED, never after a fixed sleep —
  and know which steps can actually appear.** The progress shot used to
  wait for the progress view to exist and then sleep six seconds; on a
  machine with a warm container the whole build finished inside the sleep,
  and the capture showed the finished site — the same picture as `preview`,
  filed as progress. The test now waits for the milestone text to contain
  "Opening the preview" and shoots the moment it does. That sentence and
  not a prettier one, because instrumented 20 Hz polling showed it is the
  ONLY state a capture can reach: the launcher's early lines arrive in one
  buffered chunk, and the pre-build "Launching Quartz preview" line — the
  final milestone's marker — completes every milestone at once, so every
  earlier step is gone before a test can look. A preview then spends the
  whole build, minutes, on a full bar captioned with its last step — a
  product defect recorded in `TODO.md`, and one Windows shares, since the
  milestone tables and the launcher output are the same on both platforms.
  Two smaller traps inside that finding: the milestone sentence is the
  element's accessibility VALUE, and its label is empty — a wait on the
  label alone never fires while the sentence is plainly on screen — and
  the pointer-parking pause inside the save helper once outlived the very
  step being photographed, so park before waiting, not after. The built output is also cleared before EACH
  appearance pass, not once per run — clearing it once left the dark pass
  photographing the light pass's finished build.
- **Launch with window restoration off.** A capture that dies mid-test kills
  the app with two windows open (main plus assistant); every launch after
  that restores both, and every element query in every test then finds two of
  everything and fails with "multiple matching elements". On the mac the fix
  is the `-ApplePersistenceIgnoreState YES` launch argument; whatever Windows
  session-restore mechanism exists, captures must start from exactly one
  window.

### The demo sites were renamed on 2026-08-19

The published demo sites now follow a per-SECTION scheme —
`<code>-s<n>-2026-gordon.netlify.app`, e.g. `eng2d-s1-2026-gordon` — and
ENG2D has a section 2 site of its own. `capture.py`, `capture_windows.py`
and `website/site.json` carry the new names, but
`windows-app/Plantoir/Services/MarketingShotCapturer.cs` still writes the
OLD per-course names (`{code}-gordon-2026-27`) into its fixture configs'
`deploy_site_name`, in two places. Left for the Windows side to update
rather than edited blind from the mac, because the new scheme names a
SECTION and `deploy_site_name` is course-level config: the right value for
those fixtures — probably the section 1 name — is a judgement about how
that capturer uses them. The authoritative record of what is actually
deployed is the demo working folder itself:
`courses/<CODE>/.netlify_sites/section<n>.json`.

### The demo courses, and why those three

The screenshots are taken against a working folder holding ENG2D, MCV4U and
SCH3U, created through the app's own new-course panel rather than by writing
folders directly — so the pictures show what a teacher's folder actually looks
like, not what a script thinks it should. The three codes were chosen so that
between them the class sites show prose, typeset mathematics, and chemistry
notation, which is most of what anyone doubts a Markdown site can do.

Rejected: hand-made screenshots (they go stale silently, which is how a
marketing site ends up showing an interface that no longer exists), and a
headless browser for the class sites (it approximates macOS type rendering,
scrollbars and window chrome rather than showing them).


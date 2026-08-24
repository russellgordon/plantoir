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

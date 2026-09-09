# 7. Publishing a built section (`deploy.py`)

> A course chooses **where** it publishes with the `deploy_target` key —
> which the APP reads and turns into a `--target` argument. **No launcher
> reads that key**: `deploy.sh`, `deploy.ps1` and `deploy.py` all default to
> Netlify and change destination only on `--target`, so anything driving a
> launcher directly — a script, a test harness, a scheduled wrapper — has to
> pass the flag itself. Setting the key and calling the launcher publishes to
> Netlify, silently; that is exactly how a deploy harness came to verify a
> `netlify.app` address three times over and report three green Cloudflare
> publishes (GUI-IMPROVEMENTS row 419)
> (see [the config reference](08-course-config-reference.md)). There are
> three destinations, and most of this page describes the first:
>
> | `deploy_target` | Where it goes | Who does the work |
> |---|---|---|
> | `netlify` (default) | A Netlify site per section | `deploy.py`, Netlify REST API |
> | `cloudflare_pages` | A Cloudflare Pages project per section, at `<project>.pages.dev` | `deploy.py`, via wrangler in the image |
> | `local_folder` | A folder on the teacher's own machine, one `sectionN` subfolder per section | the **launcher**, host-side — the container is never involved |
>
> Whichever is chosen, the thing published is the same built
> `public/` folder; only the transport differs. The two newer
> destinations are described at the end of this page.
>
> **A course can publish to more than one destination now, for
> redundancy** — see `additional_deploy_targets` in
> [the config reference](08-course-config-reference.md). `deploy.py`
> itself is unaware of this: it still does exactly one destination per
> invocation, exactly as below. Redundancy is entirely an APP-layer
> concern — the app (or the scheduled-deploy shell script it writes)
> simply invokes `deploy.py` once per configured destination, in
> sequence, and one destination failing does not stop the others. See
> `mac-app/QuartzTeachers/Scripting/MultiDestinationDeployRunner.swift`.

[◀ Previous: Quartz Customizations](06-quartz-customizations.md) · [Back to index](README.md) · [Next: course_config.json Reference ▶](08-course-config-reference.md)

`scripts/deploy.py` publishes the built `public/` folder for one section to
Netlify. It deliberately does **not** use the Netlify CLI — it speaks the
Netlify REST API directly with Python's standard library (`urllib`), which
keeps the container free of another Node toolchain and gives precise control
over the deploy method.

## Prerequisites and inputs

- The static site must already exist at
  `courses/<CODE>/.merged_output/section<N>/public/`. The deploy launcher
  never builds it: if that folder is missing or empty it stops and tells the
  teacher to run preview with `--build-only` first. On macOS that path is a
  shortcut out of the working folder (see
  [the build pipeline](05-build-pipeline.md)); `deploy.py` follows it for the
  work but names the `courses/…` spelling in everything it says, because that
  is the path the teacher knows.
- `NETLIFY_AUTH_TOKEN` must be in the environment. The deploy **launcher**
  owns the token (macOS Keychain / Windows Credential Manager — see
  [launcher scripts](03-launcher-scripts.md#deploysh)) and injects it; the
  Python script refuses to run without it and never stores it.

## First deploy: site creation and naming

On first deploy of a section, the script creates a Netlify site via
`POST /api/v1/sites` (or under a team with `--team <slug>`). The suggested
site name encodes everything a teacher needs to recognize it later:

```
<course>-s<section>-<year>-<lastname>     e.g.  ics3u-s1-2025-gordon
```

- The teacher's last name is asked once and cached in
  `courses/.internal/profile.json` (a hidden folder that deploy also adds to
  `courses/.gitignore`, along with `_backups/`). It is asked for only at the
  moment a NEW site or project is being named, never on a repeat publish —
  and never at all under `--non-interactive`.
- Names are sanitized to Netlify's subdomain rules, and name collisions
  (Netlify site names are global) trigger a retry prompt with an
  auto-suggested `-02`, `-03`, … suffix.

**None of those questions may be asked of a publish that runs on its own**, and
`--non-interactive` is how that is enforced. A scheduled publish runs at half
six with the app closed, so a question it puts to a teacher is put to nobody,
and both ways that ended have been seen: with a terminal `input()` BLOCKS —
measured at 45 minutes, the site simply not updated in the morning with nothing
to say why — and without one `prompt()` returns its DEFAULT silently, so the
site is created at an address nobody chose, and on a machine with no saved
surname an address with no surname in it.

Under the flag every question refuses instead, saying which one it could not
ask and exiting **3**, a code that means that and nothing else. Naming a site
is the question with no safe default: the address is what students type, it is
global to all of Netlify, and changing it later breaks every existing link. It
is reached in two states and both stop — a section that has never been
published (which the app already refuses to SCHEDULE, for the same reason), and
the one that cannot be foreseen: a site that existed when the alarm was set and
has since been deleted at Netlify, so the lookup comes back 404 and falls
through to creating a fresh one. That second state is what this whole feature
was opened on.

Both launchers take the flag and FORWARD it, since the site-name question lives
in the Python; both also guard their own prompts with it. Nothing changes
without the flag: a teacher at a keyboard gets every prompt they got before.
See [launcher scripts](03-launcher-scripts.md#deploysh),
`contracts/app-rules.json` → `launcherFlags.nonInteractive` for what is
refused, and `launcherFlags.deployExtras` for the flag itself.

The created site's identity is saved as a **marker file** at
`courses/<CODE>/.netlify_sites/section<N>.json` so subsequent deploys go to
the same site. (An older layout stored the marker inside the merged output —
which gets wiped by `--full-rebuild`; markers found there are silently
migrated to the stable location. This is also why marker storage lives under
the *course* folder, not the *output* folder.)

**One thing removes that marker, and only on purpose.** Rolling a section over
to a new year asks the teacher whether this should be a new website or last
year's, and on "a new website" the marker is **renamed aside**, never deleted —
it holds the site id and admin address, and is the only way back. The next
deploy then finds no marker and asks what to call the new site, exactly as a
first deploy does. Every destination type is released, not just the one the
course is configured for now, because a section pinned to a destination it no
longer uses would otherwise keep publishing there. Rolling over also turns off
any publish scheduled to run on its own: a released section has no agreed site
to publish to, and an unattended run has nobody to ask what to call one.

The `*.netlify.app` address need not be the address anyone shares: a
teacher can attach a **custom domain** to the site in Netlify and record
it per section in `course_config.json`
(`custom_domains.sections.section<N>`) — the app's published-site links
then wear that domain (host swapped, path preserved, https). `deploy.py`
itself does not consume the key; the domain is configured on Netlify's
side as usual.

## Every deploy: the delta algorithm

Netlify supports a
[file-digest deploy method](https://docs.netlify.com/api/get-started/#deploy-with-the-api):

1. **Manifest.** The script walks `public/`, SHA-1-hashes every file, and
   posts `{"files": {"/index.html": "<sha1>", …}}` to
   `POST /sites/<id>/deploys`.
2. **Required list.** Netlify replies with the digests it has *not* seen
   before — typically a small fraction of the site.
3. **Uploads.** Each required file is `PUT` to
   `/deploys/<id>/files/<path>` as a raw octet stream. Only one upload is
   needed per unique digest even if several paths share content.

Deploys always go to **production** (no draft deploys), matching the
"publish what I previewed" mental model.

### Automatic production rebuilds (live-reload detection)

A preview build embeds a live-reload WebSocket client (`ws://localhost:<port>`)
into generated HTML pages. Deploying those directly would cause students'
browsers to prompt for local network permissions. `deploy.py` detects this
signature in `public/index.html` (or checks if `baseUrl` in `quartz.config.ts` needs
updating for the deployed domain) and automatically re-executes a clean static
build inside the container-internal workspace (`/tmp/quartz-builds/...`),
mirroring the production assets back to `public/` before uploading.

**`deploy.py` does not cover every destination, and the gap was real.**
Publishing to a folder never enters the container — the built site already sits
on the host, so `deploy.sh` / `deploy.ps1` mirror it across directly and
`deploy.py` is never reached. That destination therefore had no such check at
all until 2026-09-05, and publishing straight after a preview shipped the
live-reload client: measured at 230 of 244 files. The app was never exposed,
because build freshness (`contracts/app-rules.json` → `buildFreshness`) forces a
rebuild when the built site was made by a preview — but from the command line nothing did.
The launchers now make the check themselves before mirroring, and rebuild.

Two details of that guard are worth knowing, because both were got wrong once:

- **It waits on the WHOLE TREE, not the front page.** Serve mode bakes the
  client into every page and the host mirror is replaced file by file, so a
  clean front page can sit in front of hundreds of stale preview pages.
  Publishing that mixture is worse than publishing the preview wholesale,
  because the front page looks right and nobody looks further.
- **The rebuild stops a preview that is still serving that section**, because
  the preview's sync watcher mirrors the serve build to the host every second
  and would otherwise overwrite the rebuild within a second of it finishing.
  See [the build pipeline](05-build-pipeline.md#a-build-for-publishing-stops-that-sections-preview).

Both guards are exercised by `verify-deploy.sh`, which publishes to every
destination and then fetches each site back and reads it. **It is bash, and it
runs on the mac only** — so the PowerShell half of these guards is not covered
by it, which is how the next paragraph's defect survived.

**A third detail, learned the expensive way on Windows.** The PowerShell port
of the tree check was written from the mac, where it could not be run, and it
used `Select-String -Quiet` on a pipeline of files. That returns one result
PER FILE rather than one answer for the tree, and a non-empty array is TRUE in
PowerShell whatever is in it — so the check was true for any site with two or
more pages, which is every real site. Publishing to a folder therefore could not succeed on Windows at
all: it always claimed the site was a preview build, always rebuilt, always
waited the full timeout, and always refused. It is now `Test-CarriesLiveReload`
in `deploy.ps1`, which tests for a match object rather than a Boolean. The
general rule for PowerShell written from the mac: `-Quiet` is not a scalar when
the input is a pipeline.

### Why determinism matters

The delta algorithm is the reason several build-side customizations exist:

- the [stable OverflowList id](06-quartz-customizations.md#b2-stable-id-in-overflowlisttsx)
  (a random id changed every page, every build),
- `TZ=UTC` and a fixed `SOURCE_DATE_EPOCH` in the build environment,
- dropping git/filesystem dates in favour of frontmatter
  ([C1-2/C1-3](06-quartz-customizations.md#c1-applied-on-first-build--full-rebuild)),
- the Curriculum `created` sync being conditional ("only if newer") rather
  than a blind bump on every build.

With those in place, an unchanged page hashes identically build after build,
and a typical daily deploy uploads a handful of files instead of the whole
site.

### Diagnostics

`--diagnose` prints a category breakdown (html / styles / scripts / images /
fonts / …) of what Netlify requested and writes the full ordered list to
`public/_required_last_deploy.txt`. This exists to answer the question "why
did that deploy upload 400 files?" — the usual culprit being some
nondeterminism reintroduced into the build.

### Suppressing Netlify's own ad badge

Netlify can inject a "Powered by Netlify" badge — and a matching pre-launch
toolbar — into any public site on a free-tier project (rollout confirmed
2026-08-21). There is no API field to turn it off: its published OpenAPI
spec has nothing named `badge`, `powered_by`, or `premium` anywhere on the
`Site` object, so the only documented control is a per-project dashboard
toggle — not something that scales to hundreds of teachers' class sites.

Netlify's own docs name the one lever that *is* automatic: the badge only
renders through an inline `<script>` injected at their edge, and a
Content-Security-Policy whose `script-src` omits `'unsafe-inline'` makes the
browser refuse to run it
(<https://docs.netlify.com/manage/projects/powered-by-netlify-badge/>):
"Neither the badge nor the pre-launch toolbar appears, and no other project
functionality is affected."

A fixed CSP would be fragile — Quartz's own build does emit a few inline
`<script>` blocks (a search-index prefetch trigger, a callout-collapse
handler, a Mermaid pan/zoom script), and a hardcoded allow-list would go
stale on a Quartz upgrade or silently break a teacher's own embedded
`<script>`. So `write_netlify_headers_file()` scans the actual built
`public/` folder at deploy time — every `.html` file, every unique inline
`<script>` body, SHA-256-hashed — and writes `public/_headers` with a policy
built from what is really there:

```
/*
  Content-Security-Policy: script-src 'self' 'sha256-…' 'sha256-…' … https://cdn.jsdelivr.net;
```

Only `script-src` is set, never `default-src` — nothing else about a page
(images, fonts, styles, network requests) is restricted. This runs on the
Netlify path only, right after any production rebuild above and right
before the delta-deploy manifest is built, so `_headers` rides along in the
same SHA-1 manifest as every other file. It is deterministic build to build
(same content ⇒ same hashes ⇒ same file), which matters for the same reason
covered under "Why determinism matters" above. Tested in
`scripts/test_deploy_netlify_headers.py` (no Docker needed — `verify.sh`
runs it before the image build).

**Cloudflare Pages and `local_folder` pay nothing for this.** It is a
problem Netlify created, so only a Netlify deploy should carry the cost —
Cloudflare's `publish_to_cloudflare()` returns from `main()` before this
code is even reachable, and `local_folder` never invokes `deploy.py` at
all. No extra file, no extra console line, no extra time on either path.
This also keeps them a clean control group: deploying identical content to
both Netlify and Cloudflare is a direct way to check whether a suspected
breakage on a site is caused by this feature specifically, rather than by
the build itself. Pinned structurally in
`CloudflareIsNeverTouchedTests` in `scripts/test_deploy_netlify_headers.py`,
so a future refactor that moves the badge-suppression call earlier fails
that test rather than shipping a silent regression.

### Rate limiting

Netlify's API rate-limits aggressively enough that a class-worth of teachers
deploying at a workshop can hit HTTP 429. API errors are enriched with a
friendly explanation derived from the `X-RateLimit-Reset` header: the current
local time and when the window resets (converted to the teacher's timezone
via `HOST_TZ_OFFSET`). Vendor-specific values like `Retry-After` counts are
deliberately omitted to avoid confusion.

## Cloudflare Pages (`--target cloudflare`)

Chosen with `deploy_target: "cloudflare_pages"`. Each section becomes its
own Pages **project**, served at `<project>.pages.dev` — a root address per
section, the same shape as a Netlify site, so nothing in the build has to
carry a URL sub-path.

Unlike the Netlify path, this one does **not** speak the vendor's REST API
for the upload. Cloudflare's direct-upload protocol is multi-stage and
undocumented — BLAKE3 hashes computed over base64-of-contents plus the file
extension, a short-lived upload JWT that can expire mid-upload on a large
site, batched asset uploads — so publishing hands the built folder to
**wrangler**, Cloudflare's own CLI, which lives in the image (see
[the image](02-docker-image.md)) and is pinned. Reimplementing that protocol
from community write-ups would break teachers' publishing silently whenever
Cloudflare changed it.

Two things are needed, and only one comes from the teacher directly:

- **An API token** with the single permission *Account → Cloudflare Pages →
  Edit*. The launcher owns it exactly as it owns the Netlify token (Keychain
  / Credential Manager), under its own entry so a teacher publishing some
  courses to each keeps both.
- **An account ID.** A token scoped to Pages **cannot list its own account**
  — verified against a real token, where `/user/tokens/verify` reports
  `active` while `/accounts` returns success with an empty list. So token
  validity and account discovery are separate questions: validity is checked
  against `/user/tokens/verify`, and the account is resolved by trying
  discovery, then a remembered value, then asking once. The GUI collects it
  up front, because an app publishing in the background has nothing attached
  that could answer a console prompt — and under `--non-interactive` that
  last "asking once" is a refusal instead, naming the Account ID and pointing
  at the course's own settings.

Naming a NEW project asks the teacher nothing, and that is the one place this
path differs from Netlify's: the project name is derived (course, section,
year, surname) rather than offered for editing. So under `--non-interactive`
there is nothing to refuse here **unless the surname has never been saved on
this computer**, which is the single question on the path — and that one is
refused. See `contracts/app-rules.json` → `launcherFlags.nonInteractive`,
which records the asymmetry so neither app "tidies" it away.

Per-section state lives in `courses/<CODE>/.cloudflare_sites/section<N>.json`,
mirroring the Netlify marker, so re-publishing reuses the same project rather
than creating a second one.

**The one real limit: 25 MB per file.** Cloudflare refuses anything larger,
and the failure otherwise surfaces from deep inside the upload as an
unhelpful error — so `deploy.py` checks sizes *before* uploading anything and
names the offending files, suggesting a shorter or compressed video, or
Netlify for that section. Ordinary course material is nowhere near it;
long-form video is, which is why most teachers embed from YouTube or Vimeo.

Cloudflare's free plan limits builds to 500 a month, but that does not apply
here: a Direct Upload deployment records `deployment_trigger.type: ad_hoc`
with stages `clone_repo=idle, build=idle, deploy=success` — no Cloudflare
build runs, because nothing is pushed to a git repository. Static requests
and bandwidth are unmetered on the free plan.

## A folder on this PC (`--to-folder`)

Chosen with `deploy_target: "local_folder"` plus `deploy_folder_path`. This
one never reaches the container: the launcher mirrors the already-built
`public/` folder into `<chosen folder>/section<N>` on the host, copying only
what changed and propagating deletions.

**Never reaching the container is the thing to remember about this
destination.** Everything `deploy.py` does for the other two — most importantly
[refusing to publish a preview build](#automatic-production-rebuilds-live-reload-detection)
— simply does not happen here, and each such guard has to be repeated in
`deploy.sh` and `deploy.ps1` or it does not exist for this path. That is not
hypothetical: the preview-build refusal was missing here for as long as the
destination has existed. It exists for teachers whose board or
university already gives them web space — they upload the folder however they
normally do (SFTP, a network share, a sync client), and no third-party
account is involved at all.

Because the copy is host-side, this path prints `PUBLISHED_FOLDER=<path>`
rather than a live URL, and the apps show a "copied to its publishing folder"
panel with a reveal-in-file-manager button instead of a link — plus a note
that pages opened straight from disk won't look right, since the site expects
to be served over HTTP.

## Publishing while a preview is running — the race, and the harness that found it

Two defects on 2026-09-05, both in the publish path, both invisible to every
test that does not publish and then LOOK at what came out.

**The race, which is the one that matters.** Killing the preview LAUNCHER does
not stop the preview. On the mac the Python and the node server both live
inside the container, and `_start_public_sync_watcher` keeps mirroring the
SERVE build to the host every second — so a build for publishing lands and the
preview overwrites it within a second, and what gets published is the preview,
live-reload client and all. `kill_existing_quartz` was only ever called from
the SERVE branch, so `--build-only` never stopped anything.

`build_site.py`'s `--build-only` now stops the preview serving THIS SECTION
before building, matched by the section's own build directory.
**That is shared Python and both platforms inherit it.**

**It was written by PORT first, and that was wrong — do not go back to it.**
`kill_existing_quartz(port)` looked like the obvious tool and is the right one
for the SERVE path, where the port is known and leased. A build-only run is
never given a port: `preview.sh` defaults it to 8081 and the app's deploy
passes no `--port` at all. So the first version killed whatever was serving on
8081 — the first section to have previewed in that working folder, which is
usually a DIFFERENT section from the one being published. Measured 2026-09-05
by doing it: previewing section 1 and publishing section 2 printed "Killed
existing process on port 8081" and section 1 stopped answering. A scheduled
overnight deploy would have done the same to any preview left running.

What works instead is the section's BUILD DIRECTORY, which is on the serve
process's command line because the launcher runs the Quartz CLI by absolute
path. It identifies exactly one preview and cannot collide with another. One
detail that is easy to miss: match on the directory plus a trailing separator,
or `section1` also matches `section10`.

Two things worth checking per platform rather than assuming:

- **A Windows preview is not in a container**, so an orphaned server is a plain
  Windows process. Check that killing the launcher actually stops the node
  server — on the mac it demonstrably does not, and that is exactly the kind of
  difference that is assumed rather than measured.
- **The matching algorithm exists on both sides — do not write a third copy.**
  `preview.ps1`'s `--stop` block finds this section's processes by COMMAND
  LINE (this paragraph said WORKING DIRECTORY until 2026-09-05, and that was
  simply wrong — `Win32_Process` exposes no working directory) and walks their
  descendants; the descendant walk is the half Windows had and the mac did not.

  The mac could not simply call `preview.sh --stop`, because `build_site.py`
  runs INSIDE the container and `--stop` is a host script — which is why a
  third copy of this rule once existed. **Resolved 2026-09-05: the rule lives
  once**, in `contracts/shared-rules.json` → `stopPreview` and
  `scripts/stop_preview.py`, whose `read_snapshot()` dispatches on the platform
  — `/proc` on Linux and in the container, `Get-CimInstance Win32_Process`
  natively on Windows. See
  [`03-launcher-scripts.md`](03-launcher-scripts.md) → "One rule for stopping
  a section's preview" for the full design and what was rejected.

- **What is and is not exposed.** The Windows APP already stops a
  running preview before deploying (`SectionDetailView.xaml.cs`), exactly as
  the mac's does — so the app is safe on both platforms and always was. The
  hole was the COMMAND LINE, on both.

  **On Windows that hole was open until 2026-09-05, and this page described it
  as open for longer.** `read_proc_snapshot()` reads `/proc` and native Windows
  has none, so it returned an empty list and `stop_preview_serving()` stopped
  nothing. The fix went one level DEEPER than "call `preview.ps1`'s matcher
  from the build-only path" — that route was considered and rejected, because
  `deploy.py` reaches `build_site.py --build-only` directly and never passes
  through the launcher, so a fix living in `preview.ps1` would leave the
  Netlify and Cloudflare route still racing. `read_snapshot()` is a dispatcher
  instead. The watcher that causes the race runs everywhere regardless:
  `_start_public_sync_watcher` is started unconditionally in the SERVE branch,
  so a Windows preview mirrors over a Windows publish exactly as a mac one
  does.

- **The wait is bounded at 30 seconds** (150 × 0.2 s), not the 15 that
  `GUI-IMPROVEMENTS.md` row 392 says — that row predates the change and the log
  is append-only, so this is the current number.

**The other one was a partial fix of mine, and is worth knowing as a shape.**
The first version of the preview guard in `deploy.sh` waited for `index.html`
to lose the live-reload client. Serve mode bakes that client into EVERY page
and the mirror is replaced file by file, so a clean front page can sit in front
of two hundred stale preview pages. Publishing that MIXTURE is worse than
publishing the preview wholesale, because the front page looks fine and nobody
looks further. Wait on the whole tree; `deploy.ps1` already does.

## `verify-deploy.sh` — the publishing harness, and why it is not in the gate

New on 2026-09-05, at the repository root. It publishes to a folder, to Netlify
and to Cloudflare, and runs all three primary+secondary pairings, then **fetches
every published site back and reads it** — the launcher's own output only
proves the launcher is happy with itself. 42 checks.

**It is deliberately NOT part of `verify.sh`.** The gate must be runnable at any
moment, on any machine, without credentials and without touching anything
outside the repository. This needs a Netlify token, a Cloudflare token and an
account ID, it needs the network, and it CREATES REAL SITES. Build the Windows
equivalent the same way — opt-in, run when the publishing path changes — rather
than folding it into whatever else gates a commit.

One thing it does NOT cover, stated so nobody assumes otherwise:
`additional_deploy_targets` is not handled by `deploy.sh` at all — the APP loops
and calls the launcher once per destination. The harness exercises the pairings
by running that same sequence, which tests the launcher half; that the app
produces exactly those argument lists is pinned separately by
`app-rules.json` → `deployArguments`, which both suites run. Between the
two the pairing is covered; neither half covers it alone.

## The scheduled task NEVER refuses

Russell's call, and the reasoning travels: *"a slightly inaccurate curriculum map
is a paper cut, an unpublished site update a teacher was counting on is a broken
nose."* Pinned as `siteHealth.scheduledDeployPublishesAnyway` and asserted by a
mac test so it cannot be quietly softened later.

So: publish, then stash what was found for the next time somebody is there. You
already have the shape — `ScheduledDeployCompletion.cs` stashes a completion
sentinel exactly this way. Two properties the mac's version has that any port should
too: the record is CONSUMED when read, so a problem is reported once rather than
every time the app opens; and a CLEAN run clears it, so a problem the teacher has
put right stops being reported.

**That second property is harder than it looks, and this section claimed it
before it was true.** launchd opens the scheduled log with O_APPEND and nothing
rotates or truncates it, so reading the whole file re-finds LAST week's marker
lines every night: the sentinel is rewritten with stale findings forever, and the
"nothing wrong this time" branch becomes unreachable the moment a single problem
has ever been logged. A teacher who fixed the folder would have been told about
it every morning until somebody deleted the log.

The mac now records the log's SIZE before the run and reads only from that offset
afterwards. A task runner that captures output per run may not have this
problem at all — but check rather than assume. And note how it got through: the
test that was supposed to cover it faked the append by rewriting the file, so it
passed against broken code.

One platform difference worth knowing: the mac reads the findings back out of the
scheduled run's LOG FILE rather than from a pipe, because `runScheduled`
deliberately does not capture the child's output — launchd points stdout at that
log and the process inherits it, and an unread pipe is what wedged the
assistant server once. Where a task runner already captures output, use that;
the log-scrape is a workaround for a constraint not every platform shares.

## Deploys with several destinations

Take the findings from the FIRST leg only. Every destination publishes the same
built site, so a second leg repeats them.

---

[◀ Previous: Quartz Customizations](06-quartz-customizations.md) · [Back to index](README.md) · [Next: course_config.json Reference ▶](08-course-config-reference.md)

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
  `courses/.gitignore`, along with `_backups/`).
- Names are sanitized to Netlify's subdomain rules, and name collisions
  (Netlify site names are global) trigger a retry prompt with an
  auto-suggested `-02`, `-03`, … suffix.

The created site's identity is saved as a **marker file** at
`courses/<CODE>/.netlify_sites/section<N>.json` so subsequent deploys go to
the same site. (An older layout stored the marker inside the merged output —
which gets wiped by `--full-rebuild`; markers found there are silently
migrated to the stable location. This is also why marker storage lives under
the *course* folder, not the *output* folder.)

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
  that could answer a console prompt.

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

---

[◀ Previous: Quartz Customizations](06-quartz-customizations.md) · [Back to index](README.md) · [Next: course_config.json Reference ▶](08-course-config-reference.md)

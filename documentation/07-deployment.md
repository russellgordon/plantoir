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
signature in any page under `public/` (every `*.html`, since 2026-09-05 — see
"One rule, six readers" below) and automatically re-executes a clean static
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

#### One rule, six readers (GitHub #136, 2026-09-25)

Whether a built site is a preview's is asked in six places, and until #136
they did not agree:

| Reader | Where | What it reads |
|---|---|---|
| `BuildFreshness.builtForPreview` (mac) | `mac-app/QuartzTeachers/Models/BuildFreshness.swift` | every `*.html` under `public/`, as bytes — the front page ALONE until #136 |
| The scheduled publish's own check (mac) | `ScheduledDeploy.oneShotCommand` | `LC_ALL=C grep -rqs --include='*.html'` over `public/` — `index.html` alone until #136 |
| `deploy.sh`, folder leg | three identical `grep -rq --include='*.html'` lines | the whole tree, since 2026-09-05 |
| `deploy.py`, Netlify and Cloudflare | `public_dir.rglob("*.html")` | the whole tree, since 2026-09-05 |
| `deploy.ps1`, folder leg | `Test-CarriesLiveReload` | the whole tree |
| `BuildFreshness.BuiltForPreview` (Windows) | `Plantoir.Core/Models/BuildFreshness.cs` | the front page alone — owed, see the `windows` issue |

(Windows' scheduled task builds unconditionally, so it has no check to get
wrong.)

**Why the apps being narrower mattered.** The built tree is replaced file by
file, so a clean front page in front of a preview's pages is a real state. The
app called it deploy-fresh and skipped its own build; the launcher then saw the
client and rebuilt under the DESTINATION's leg. On the Deploy button that shows
the deploy-only milestones while a build is in fact running. On the mac's
scheduled publish to a folder it was worse: a question the rebuild stopped for
came back through `deploy.sh`'s exit 3 and was recorded as the folder's
(`neededAnAnswer`, sending the teacher to Publish) rather than the build's
(`buildNeededAnAnswer`, sending them to Preview). Now the app and the overnight
check read the same tree, so whenever `deploy.sh` would rebuild, the build leg
already has. `deploy.sh`'s own rerun is kept: it is what protects
`./preview.sh` followed by `./deploy.sh --to-folder` typed at a command line.

**The rule is data**: `contracts/app-rules.json` → `buildFreshness.previewBuild`
— the `signature`, `where` it is looked for, and nine `cases`, each a tree of
pages. The mac suite runs the app's check (`BuildFreshnessTests`) and the
overnight shell (`ScheduledPublishOutcomeTests`) against it;
`scripts/test_preview_build_detection.py` cuts `deploy.sh`'s check out of the
launcher and runs it, and runs the real `deploy.py`, against the same list —
in `verify.sh` and in Windows' `PythonToolchainTests`. `deploy.ps1` is Windows'
to run against it. Its `notShared` says what the cases deliberately leave out.

**The details each reader has to get right, and why:**

- **Bytes, not text.** A page that is not valid UTF-8 must not change the
  answer. Reading as a Swift `String` would make one such page force a rebuild
  on every publish forever. **Measured** (macOS 26.6, `/usr/bin/grep`
  2.6.0-FreeBSD): under a UTF-8 locale `grep` does NOT find the signature on a
  line that also holds an invalid byte (exit 1); under `LC_ALL=C` it does
  (exit 0). So the overnight check runs under `LC_ALL=C`; `deploy.sh` run from
  a Terminal can call such a page clean while every other reader calls it a
  preview's — the SAFE direction, since the app then rebuilds first, and Quartz
  only writes UTF-8. `deploy.py` reads with `errors="ignore"` and matches.
- **Hidden folders included** — `grep -r` and `rglob` both look inside them, so
  the Swift enumerates without `.skipsHiddenFiles`.
- **A page that cannot be opened is passed over; a front page that cannot be
  opened means rebuild.** The launchers skip an unreadable page (`2>/dev/null`,
  `except OSError`). The overnight line says `! [ -r index.html ] || … grep
  -rqs …`: measured, BSD grep with `-s` exits 0 on a match elsewhere and 2
  otherwise, which an `if` reads as "no", so the front page needs its own test.
- **The front page first.** A real preview's build carries the client in every
  page, so it answers from one file.

**Cost — measured on an Apple M4 Pro, macOS 26.6**, a standalone copy of the
Swift scan run 20 times against real sections (read-only): a clean 244-file /
230-page section 6.5–7.8 ms warm, 54 ms on the first run in a fresh process; an
864-file / 353-page section about 12 ms warm, 72–82 ms first. A real preview's
build answers in 0.1 ms. The front-page-only read it replaced took 0.02 ms. It
runs once per Publish press, on a path that then builds or uploads for seconds
to minutes, so it stays synchronous on the main actor.

**Rejected:**

- *Giving `deploy.sh`'s rerun its own exit code*, so the wrapper could tell a
  build question from a destination's: a launcher contract change Windows
  shares, for a fault that was the app's check being narrower.
- *Removing `deploy.sh`'s rerun*: it is the only guard on the command line.
- *Adding `LC_ALL=C` and `-s` to `deploy.sh`*: correct, but a publishing-path
  launcher change for a state Quartz cannot produce; written down instead.
- *Reading pages as `String`*, for the reason above.
- *Sampling the front page and a few others*: cannot promise the answer, and
  the whole walk costs about 12 ms.
- *Moving the scan off the main actor*: unnecessary at these numbers.
- *A home in `shared-rules.json`*: `buildFreshness` already lives in
  `app-rules.json`, and one rule gets one home.
- *A narrower signature* (`new WebSocket('ws://localhost:`), so a page that
  merely MENTIONS the address — a networking lesson — is not read as a
  preview's: it would change all six readers, two of them launchers. That limit
  is older than #136 and is [issue #291](https://github.com/russellgordon/plantoir/issues/291);
  what #136 adds to it is only that the app now rebuilds such a course on every
  publish too, as the launchers already did.

**Cancelling a publish ends it quietly (GitHub #259, 2026-09-25).** The
progress view's Cancel types a `^C` (`ScriptRunner.cancelByUser`), which reaches
`deploy.py` as `KeyboardInterrupt` wherever it is waiting — most often inside
this production rebuild. It used to escape and print a Python traceback (26
lines during the rebuild, 10 at the surname question, measured through a pty);
`deploy.py` now enters through `run_until_stopped()` and exits 130 with nothing
printed, and a rebuild or a wrangler run that reports 130 or −2 is read as the
same Cancel rather than as a failure. The app decides a cancelled leg by its own
flags, not by that 130; the code is for every other reader (a terminal,
`deploy.sh`'s `set -e`, `deploy.ps1`). A Cancel during the upload now also drops
the uploads still queued — before the fix round, 25 of 40 went up after it — and
since neither Netlify nor Cloudflare publishes a half-finished upload, the site
stays as it was, except for a Cancel in the last second or two, once the final
files are already on their way. **Only that Cancel sends a `^C`** — the Stop Preview and console Stop
buttons end the process without one (SIGTERM raises no `KeyboardInterrupt`), so
nobody should expect this handler to be what covers them; they never printed the
traceback. The reasoning, the numbers and what was rejected are in
[the build pipeline](05-build-pipeline.md#stopping-a-build-exit-130-and-no-traceback).

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

### Asking once, and the subshell that ate the question (2026-09-09)

That "asking once" is `prompt_for_cf_account`, and until issue #129 it did
not work from the command line. It is called as

```bash
CF_ACCOUNT="$(prompt_for_cf_account)" || exit 1
```

and a command substitution is a **subshell that captures stdout**, so the
function's stdout is its RETURN VALUE — nothing else may go there. Its
six-step "where to find your Account ID" instructions and its "that doesn't
look like an Account ID" error both went to stdout anyway. Two consequences,
both measured on 2026-09-09 by driving the real `deploy.sh` through a
pseudo-terminal rather than reasoning about it:

- A teacher was asked to paste a code **with no hint where it lives** — the
  instructions were invisible — and when they mistyped it they saw **nothing
  at all** before the script exited 1.
- On the SUCCESS path the captured value was the instructions **and** the id:
  **519 characters — 521 bytes — where 32 were meant** (the instruction block
  is 489 bytes of it; the two-byte gap between the counts is one em dash). That blob went to `set_cf_account_keychain`,
  so it was remembered and every later run skipped the question and reused
  it, and to wrangler as `CLOUDFLARE_ACCOUNT_ID`. First-time Cloudflare
  publishing from the command line did not work, and stayed broken until the
  Keychain entry was cleared by hand.

**Only the command line was exposed.** The GUI passes `--account` (see
`DeployCommand`), and a scheduled publish carries it in the plist, so neither
reaches this question; and the common case never reaches it either, because
discovery usually answers first. `deploy.ps1` never had it, and avoids it a different way than "at top level",
which is worth stating precisely because a Windows reader will go looking:
`Read-CloudflareAccountId` says both of these inside the function too, but
pipes them to `Out-Host` / `Write-Host`, which bypass the success stream that
`$CF_ACCOUNT = Read-CloudflareAccountId` captures. PowerShell's host stream is
doing the job stderr does here — so after this fix the two launchers solve the
problem the same way rather than differently.

Fixed by sending both to **stderr**, which is where `read -rp` already writes
its own prompt, so the instructions now sit with the question they belong to.

**Rejected: making the function set `CF_ACCOUNT` directly** and dropping the
command substitution. It is the more structural fix — it removes the trap
rather than documenting it — but the call site is parsed as TEXT by Windows'
`PublishAndLauncherContractTests.EveryQuestionTheMacDeployLauncherAsksIsGuardedAtTheTopLevel`,
which finds the single caller by searching for `prompt_for_cf_account)`. A
mac with no `dotnet` cannot check that suite, so the change would have turned
it red for a reason it has no way to verify. The invariant that matters — a
question inside a function whose output is captured — is already gated by
that test, which is what makes stderr sufficient here.

**Fixing the printing does nothing for a teacher the bug already reached, and
that is a separate repair.** The blob was written to the Keychain by
`set_cf_account_keychain`, and the line that reads it back —
`CF_ACCOUNT="$(get_cf_account_keychain)"` — trusted it without looking. So a
teacher who answered the question correctly *once*, on a released build, would
have had the question never asked again and wrangler handed nonsense on every
run for ever. **Both released versions can have done this** (v1.0.0,
2026-08-19; v1.1.0, 2026-08-20). The remembered value is therefore CHECKED
before it is used: anything that is not 32 hex characters is discarded, the
Keychain entry removed, and the question asked again — which is the state the
teacher would have been in had the bug never happened.

The repair is deliberately silent. "Your saved Account ID was wrong" invites a
support question about something already put right, and the very next line asks
for the ID anyway. If somebody needs to do it by hand, the entry is
`containerized-quartz-cloudflare-account`:

```bash
security delete-generic-password -s containerized-quartz-cloudflare-account
```

`ATeacherAlreadyBittenGetsOutOfIt` in `scripts/test_deploy_sh_questions.py`
pins both halves, and pins them against the REAL blob — it lifts the pre-fix
function out of `07952399^`, runs it, and feeds what it actually produced back
in as the remembered value, rather than a tidy short string that would not
have caught this.

**This is the same trap issue #92 fixed**, one function along. That issue
moved the `--non-interactive` REFUSAL out to the call site for exactly this
reason; the instructions and the error were left behind, because nobody had
started the script and watched it. Which is the real lesson: `deploy.sh`
changed on a machine with no bash, was syntax-checked and reviewed carefully,
and reading it found neither of these. `scripts/test_deploy_sh_questions.py`
now RUNS the launcher to every question it can ask — no Docker, no network,
no credentials — and `verify.sh` runs it at step 0.

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

### A relative folder, and a copy that did not finish

GitHub issue [#227](https://github.com/russellgordon/plantoir/issues/227),
2026-09-25. Two holes, both of which ended in "Published" over a folder that
was empty, stale, or somewhere else entirely.

**A relative `--to-folder` was handed to rsync as it was typed, and rsync reads
a colon before the first `/` as a REMOTE computer.** Measured on macOS 26.6 with
`/usr/bin/rsync` (openrsync, protocol 29), from a copy of `deploy.sh` in a
scratch working folder called `Comm Tech 26:27`:

| `--to-folder` | Before: exit, pages that landed, what it said |
|---|---|
| `out 26:27` | 0, **0** — "hostname contains invalid characters", then `✅ Published: 0 file(s)` and a RELATIVE `PUBLISHED_FOLDER=` |
| `a:b` | 0, **0** — rsync ran `ssh a` |
| `localhost:site` | 0, **0** — rsync **opened an ssh connection to this Mac**, refused only because Remote Login was off |
| `-x` | 1 — `mkdir -p` read it as an option |
| `sub/a:b`, `./a:b`, a full path with a colon | 0, all — a colon after the first `/` is local |

**The ssh finding is the reason this is more than a cosmetic bug.** With Remote
Login on, or with a real computer's name before the colon, the site would have
been copied to ANOTHER MACHINE using the teacher's own ssh keys, while the
launcher named a local folder as the place it went. "Publishes somewhere else,
or nowhere, and says Published" is the shape of it.

**What the launcher does now.** A relative `--to-folder` is taken from the
working folder — which it always was, implicitly, because `deploy.sh` begins
`cd "$(dirname "$0")"` — and is made a full path (`$(pwd)/<path>`) before
anything reads it. A path starting with `/` cannot be read as a host or as an
option, and `PUBLISHED_FOLDER=` is then a path the app can open (a relative one
would be opened against the APP's current folder, which is `/`). A working
folder whose own name has a colon is fine: the result still starts with `/`.

**And it reads rsync's own exit status.** It used to pipe rsync into
`grep -c … || true`, which threw the status away. Now any non-zero status —
including **23 and 24, a copy that finished only in part** — exits 1 with a
cross line and no `PUBLISHED_FOLDER=`, so the app's "copied to its publishing
folder" panel never appears. A partial copy is a failure on purpose (director's
ruling): measured with a stale folder `--delete` could not remove, the new pages
landed, the page the teacher had taken down stayed, and the launcher said
`Published: 2`. The cross line is matched by the app and replaced with
`FailureExplainer.folderCopyDidNotFinish` (`app-rules.json` →
`failureExplanations`), because "copy error 23" means nothing to a teacher.

**Not measured, and worth knowing before a report arrives:** a network share
(SMB — a school web server's share is a plausible destination) and a folder in
iCloud Drive. rsync's exit 23 also covers attributes it could not SET, which
is typical on SMB and possible on iCloud's evicted files; if a teacher reports
"it always fails to my network drive", that is the first thing to look at. An
exFAT and an MS-DOS disk image were measured (plan review, 2026-09-25): exit 0
on a first and a second publish, so a USB stick is not a false failure. (On
those every file is counted as "updated" on every publish, because the count
includes permission-only lines — cosmetic, and left alone.)

**The app refuses a partial path outright.** `CourseConfiguration.
deployFolderProblem` now answers `deployFolderIsNotAFullLocation` for anything
not starting with `/`, BEFORE it looks for the folder: the app's own current
folder is `/`, so `Users/Shared` used to pass the check and then be published
into `<working folder>/Users/Shared`. `Choose…` always yields a full path, so
only a typed one reaches this. Every caller goes through the one function —
the settings form and the wizard (Save is blocked), every leg of a
multi-destination deploy, and a scheduled deploy — so a course that already
SAVED a partial path is refused at Deploy rather than published somewhere
else; no migration. `DeployCommand.arguments` also hands the launcher the
path TRIMMED, the same way the check trims it: the settings form saves what was
typed, and `" /Users/x/Sites"` was a relative path to the launcher.

**Rejected:**

- **Prefixing `./`.** Fixes rsync's reading, but `PUBLISHED_FOLDER=` stays
  relative and the app would reveal the wrong folder.
- **`--` or `--protect-args`.** `--` stops OPTION parsing, not HOST parsing;
  openrsync's `-s` support was not measured.
- **Refusing a relative path in the launcher.** Breaks command-line users who
  rely on the working-folder meaning `deploy.sh` has always had.
- **Counting copied files instead of reading the status.** Exit 23 still
  copies files, so the count is non-zero while the stale page stays.

Pinned by `scripts/test_deploy_folder_target.py` (the real launcher, from a
working folder named with a colon, against `shared-rules.json` →
`folderPublishTarget`), by verify.sh's colon-folder step, which now also
publishes to `out 26:27`, and by the `configurationRules.deployFolder`,
`deployArguments` and `failureExplanations` contract cases. **Windows** has no
colon hole — robocopy has no remote syntax and NTFS forbids `:` in a name —
and already fails on robocopy ≥ 8; it does have the relative half, owed in the
`windows` issue drafted from #227.

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
proves the launcher is happy with itself.

**First run on the mac: 2026-09-09, 44 passed, 0 failed, 0 skipped** — the run
`RELEASING.md` requires with nothing skipped, and the one issue #129 was really
asking for, since `deploy.sh` had gained `--non-interactive` on a machine that
could not execute it. **Run again the same day, after Windows' issue #130
merged, with the same result** — 44 passed, 0 failed, 0 skipped. That merge
brought the fix for `deploy.sh`'s dead exit-3 pass-through, which is in the
publishing path, so the pre-commit hook asked for it and it was owed rather
than optional. All three destinations published for real and fetched
back (folder 244 files, `ada1o-s1-2026-testing.netlify.app`,
`ada1o-s1-2026-testing.pages.dev`), all three pairings, no live-reload client
on any of them, and the no-front-page case refused and shipped nothing stale.
Nothing about a teacher at a keyboard changed. The Windows counterpart
`verify-deploy.ps1` was run before the merge: 36 passed, 0 failed, 0 skipped.
The two counts differ because the suites are not identical, not because
anything was skipped — count the cases in each script rather than comparing
the numbers.

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

## The scheduled task never refuses over FOLDER PROBLEMS

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

## When a scheduled publish does not get through

Added 2026-09-09. `--non-interactive` stops an overnight publish hanging or
guessing; this is the other half — making sure the teacher finds out.

**The failure it closes.** A scheduled publish runs at half six with the app
closed. Before this, a run that did not get through said so in the section's
own log and nowhere else, so it was indistinguishable from a run that was never
scheduled. That is the shape of *"my site did not update on Tuesday and I do not
know why"*, and it had no answer.

**How the handover works.** The wrapper writes a small record, and the app reads
it — the moment it lands if the teacher is looking at that section, and
otherwise the next time they open it. Since #212 the run also tells the teacher
directly, with a macOS notification, so a teacher who has not opened the app at
all is told too — see "When nobody is looking" below. (Reading it only on opening was all this
did until 2026-09-19; the sub-section "The notice has to arrive while the
teacher is looking" below is what changed, and why it needed a change to the
wrapper as well.) The trail line is a
separate matter and is written by the RUN — see below; this paragraph used to
say the wrapper "runs with nothing of ours loaded", and that was never true on
this side. **The launchd agent runs Plantoir**, which runs the wrapper and then
does its own post-run work.

- The launchd wrapper captures the BUILD's exit code and then each
  destination's. On a non-zero one it writes `~/Library/Application Support/
  Plantoir/scheduled/stopped/<CODE>-section<N>.<folder id>.txt` (the folder
  id since #237 — see "One alarm per working folder") — first line the kind,
  second the destination. It assembles both lines in
  `…/scheduled/<CODE>-section<N>.<folder id>.txt.partial` and **moves** the finished file
  into place; the sub-section below is the whole reason, and it is not a
  tidiness preference.
- **Exit 3 is tested before the general non-zero branch**, because it is also
  non-zero. Three means `NEEDS_AN_ANSWER` and nothing else; anything else is an
  ordinary failure.
- **Which LEG stopped decides the kind, not just the code.** From the BUILD,
  exit 3 is `buildNeededAnAnswer` and any other non-zero code is
  `buildDidNotFinish` (#137); from a DESTINATION, exit 3 is `neededAnAnswer`
  and any other is `didNotFinish`. The table is data —
  `contracts/shared-rules.json` → `scheduledPublishStopped` → `whichKind` —
  and the sections below explain both build kinds.
- The **first** destination that stopped is the one kept. A course can publish
  to several and only one may have gone wrong, so *"it published to the folder
  and not to Netlify"* is the report a teacher makes; overwriting would tell
  them about the last thing rather than the first.
- The record is cleared by a run that got **all** the way through, or by the
  teacher dismissing it.
- **The RUN writes the trail line, not the app, and the record carries no
  "noted" mark at all.** `ScheduledDeploy.runScheduled` calls
  `ScheduledPublishOutcome.noteOnTrail` as soon as the wrapper finishes, so the
  line is written once because the run happens once, and it is dated to when
  the run wrote its record rather than to when anybody read it — otherwise an
  overnight problem is filed under the morning somebody noticed it.

  An earlier draft did have the app note it on opening and mark the record as
  noted, and it was wrong three ways: the mark had to be written back into the
  record, which changed its modification date — the very date the notice shows;
  a teacher who never opened that section, who is exactly the teacher who
  reports that their site did not update, got no line at all; and its premise,
  that nothing of ours is loaded when the wrapper runs, was false. **This page
  described the withdrawn draft as though it were the code until 2026-09-09**,
  which is how the Windows side came to design a `.noted` sidecar against a
  mark this side does not keep.

  **Windows still needs a mark, and that is a real difference rather than a
  copied one.** This paragraph used to say the sidecar existed because writing
  a mark into the record would repeat "the mistake an earlier draft here made
  and undid" — which drew a contrast with a mac behaviour that no longer
  exists. It was written against the stale description above, and #135 is where
  the mac said so.

  The honest version: **this side needs no mark at all**, because the run IS
  Plantoir and writes the line once as it finishes. Windows cannot do that —
  Task Scheduler runs plain PowerShell with nothing of the app loaded — so the
  line is written by a sweep when the app next opens, and a sweep with no memory
  would write it again every launch. Hence a `.noted` sidecar, kept beside the
  record rather than inside it because the record's modification time is what
  dates the notice. Two platforms, one property — a line per run, dated to the
  run — reached the only way each of them can.

**Where a teacher meets it.** The sentence sits at the top of the section, above
the console — a teacher opening a section after a failed overnight publish is
looking for why their site is out of date, and the console is about what they
are doing now. A warning badge also appears beside that section in the sidebar,
because **a teacher who does not know which section failed cannot open the right
one**, and not knowing is the whole problem. The sentence and the badge appear
at the **same moment**, because since 2026-09-19 both follow one counter — the
section's band is re-read and the sidebar row re-rendered off
`ScheduledPublishWatcher.generation`, in both directions: a run finishing moves
it, and so does the teacher dismissing the notice.

### The notice has to arrive while the teacher is looking

Added 2026-09-19 for [issue
#216](https://github.com/russellgordon/plantoir/issues/216), found in Russell's
hand smoke of the v1.2.0 build. Schedule a deploy a few minutes ahead, stay on
that section, and watch the run finish: **nothing changed on screen** until you
clicked up to the course and back down again. Both places that read the record
read it only when they were built — the section's `.onAppear` and the sidebar
row's own render — and the run is a separate process, so nothing told an open
window that the file had changed. A teacher who stays put was never told.

**The file is the event, so the file is what is watched.**
`ScheduledPublishWatcher` opens one watch on the record folder and moves a
single counter; every observer then re-reads its OWN record. One watcher for the
whole app, not one per window: the folder hangs off the home folder alone, so a
watcher per window would be several watchers and several counters for one global
truth, and a second window's sidebar would go stale. The counter carries no
payload on purpose — two sections finishing in the same millisecond produce one
bump and two correct notices, and a coalesced event is therefore never a lost
one. `workspace.stoppedPublishGeneration`, which until now only Dismiss moved,
was retired into it.

**The measurement that decided the shape of the wrapper.** A watch on a
DIRECTORY fires when an entry is created, removed or renamed. It does *not* fire
when a file that is already there grows. Measured on this Mac (Apple silicon,
APFS, 2026-09-19), with a real vnode source reading the record inside the event
handler exactly as the app does, 40 trials each:

| how the wrapper writes the record | events | first event carried a readable record |
|---|---|---|
| two `echo`s — what it used to do | 1 | **0 of 40** |
| one `printf` of both lines | 1 | **0 of 40** |
| temporary file INSIDE the watched folder, then `mv` | 3 | 2 of the 3 carried nothing |
| temporary file in the PARENT, then `mv` | **1** | **40 of 40** |

The losing shapes lose for one reason: the event is the directory entry being
created, which happens before any bytes are written, and the write that finishes
the file changes no directory entry — so there is no second event to catch it
with. **A watcher shipped against the old wrapper would not have been flaky; it
would have done nothing, every time.** Hence `recordCompletionLines` in
`ScheduledDeploy`, and `ScheduledPublishOutcome.partialRecordURL` beside the
folder rather than in it. `/bin/mv` within one filesystem is `rename(2)`, and
both paths are under Application Support by construction, so the move is atomic.
Nothing about failure changed: the wrapper has no `set -e`, so a failed write
leaves an empty temporary file which `mv` installs, and an empty record reads as
no record — exactly what a failed `echo` produced before.

**A job scheduled by an OLDER build still shows its notice live**, and this is
the part that is easy to skip. The wrapper is written to disk when the section is
scheduled and is not rewritten until it is scheduled again, so a job already
installed keeps writing two `echo`s however this app now generates them. When a
folder event turns up a record that is there but cannot be read yet, the watcher
opens a second watch on **that file** — which does see the completing write —
and closes it as soon as the record reads or goes away. An event, not a timer.
**Rejected:** rewriting every pending job's wrapper at launch. It is more code,
it edits files launchd is about to run — including, unavoidably, one that may be
running at that moment — and it would only ever fix wrappers this app wrote,
where the file watch covers any two-step writer, a record restored from a
backup included.

**Also rejected, and why:**

- **Polling on a timer.** A guessed number either way: fast enough to feel live
  is a filesystem read every second for ever, against an event that happens once
  a day; slow enough to be polite is not "while the teacher is looking". The
  thing being waited for is directly observable.
- **A distributed notification from the run.** `runScheduled` *is* Plantoir and
  could post one. It is a second channel that can disagree with the file, and it
  covers only writers that are Plantoir — not a record removed by hand, not a
  restore, not another window. (Not to be confused with the macOS
  notification the run now sends the TEACHER, #212, below: that one drives
  nothing in the app, and is composed from the record after it is written.)
- **`NSFilePresenter`/`NSFileCoordinator`.** It observes *coordinated* writes,
  and a `mv` from `/bin/bash` is not one. It would never fire at all.
- **FSEvents** needs a dispatch queue too, plus a C callback and an `Unmanaged`
  context, and coalesces with a delay: more Dispatch, three times the code,
  later events. **A raw `kevent()` loop** needs a thread of its own blocked in
  the kernel.
- **Widening the watch** to the findings sentinel beside the record. Genuinely
  worth doing and not here: it raises whether an overnight folder problem should
  throw a dialog at a teacher mid-lesson, which is a product decision.

**A deliberate use of Dispatch**, and it is commented as such where it
lives. (This said "the one use of Dispatch in this app" until #212; it never
was — `AssistMCPServer.serve` parks in `dispatchMain()` — and #212's
`ScheduledDeploy.announceThenLeave` does the same, for the same reason.)
`DispatchSource.makeFileSystemObjectSource` is the kernel's own file-system event source and takes a queue as a required parameter — the queue
is a delivery channel, not somewhere work is thrown. Nothing is deferred,
nothing waits, and the events are consumed with `for await` on the main actor.
Both watches are armed *before* `start()` returns, which is what lets the tests
be deterministic: `ScheduledPublishWatcherTests` has **no sleeps at all** — every
wait is an expectation re-checked when the counter moves, and its seven cases run
in under half a second.

**A preview showing is the state that matters most, and it took a second piece
of work to get right.** The notice first shipped in the base layer of the
section's `ZStack`, underneath the full-bleed web view, and that was recorded
here as deliberate — a band that "waits until the preview closes". It is not
acceptable, and Russell said so the same evening after his smoke test: with a
preview up, all a teacher sees is a green tint bleeding through the toolbar, and
a teacher looking at their preview is exactly who needs telling. That is
[issue #219](https://github.com/russellgordon/plantoir/issues/219).

The band now sits ABOVE the whole stack — one band, in one place, in every
state — and the site takes the room that is left. Two things decided that shape
over the alternatives:

- **The band must not be written twice.** `.safeAreaInset(edge: .top)` on the
  web view, or a second copy of the band inside a cover-layer `VStack`, both put
  it inside the branch that exists only while a preview is up, so the no-preview
  case needs its own copy — two places to keep in step for one sentence.
- **The web view must not move between containers.** It is a live `WKWebView`
  showing a page the teacher has scrolled and navigated; `WebPreviewController`
  owns the instance and `loadIfNeeded` is idempotent, but shifting the view
  between branches as notices come and go is how a page gets thrown away.
  It stays in the one branch it has always been in.

Measured by hand (2026-09-19, dark and light, a real preview showing): with the
band arriving, the page the teacher was on is **100% identical across 5,525
sampled points once shifted down by the band's 57 points** — the same page,
simply moved, not reloaded — and when the record goes, the site's pixels match
what they were before the band arrived, 8,250 of 8,250. (That second half is the
record being REMOVED, which is the watcher's path; pressing Dismiss by hand was
not driven, and the unit test below is what covers it.) What a test can pin is
the same property without a browser: `ProgressViewSizeTests` measures the room
the site is OFFERED, with a stand-in that answers `sizeThatFits` exactly as
`WebPreviewView` does. 720 points with no notice; less with one. On the old
arrangement it was 720 either way, which is the fault stated as a number.

**The toolbar must not take the band's colour, either, and that is a SECOND
mechanism rather than a consequence of the first.** A `.background(_:)` ignores
every safe-area edge by default, so the band's fill reached up into the strip
the window's toolbar sits in — and a toolbar is a translucent material that
samples what is behind it. `.background(bandColour.opacity(0.12),
ignoresSafeAreaEdges: [])` stops the colour at the band's own edges. The band's
LAYOUT was never the problem; the background was.

**Do not delete that `[]` on the strength of a clean screenshot.** Measured by
rendering the content view — which under a full-size content window includes the
strip behind the titlebar — and reading its top rows back: with the default
background the green is painted up there in BOTH the old arrangement and the
new one, and with `ignoresSafeAreaEdges: []` nothing is painted there at all.
Moving the band above the stack did not stop the bleed; this did. Whether the
bleed SHOWS depends on the state of the toolbar's material, which is why it is
hard to catch by eye: two captures of the same shape on the pre-#219 build
disagree, one grey and one green.

Measured after the change, dark and light, with a preview showing and without:
the toolbar above the detail column is identical with a band and without one —
a mean of **(34.7, 34.7, 34.7) in dark and (240.7, 240.7, 240.7) in light**,
over 2,812 points sampled between x = 350 and x = 1090 and y = 6 and y = 44 in
window coordinates.

**And it now sits where it belongs.** In the same smoke Russell found the band
floating in the MIDDLE of an empty window. The cause was that the base layer hugged
its content: measured at 800 × 720, the "No Preview Running" placeholder claimed
189 points and the layer with the notice 246, so the `ZStack` centred it and put
237 points of nothing above the notice. The placeholder (now
`NoPreviewPlaceholderView`) fills the height it is offered, which puts the notice
flush under the toolbar and still centres the placeholder in what is left. **Not
a fixed height** — a rigid height in that column is the failure class issue #211
closed, and `ProgressViewSizeTests` measures both properties side by side. The
console branch had always filled, by way of the `Spacer(minLength: 0)` at the
bottom of `consoleArea`, which is why the notice sat correctly whenever anything
was running and wrongly when nothing was.

### When nobody is looking: a notification from the run (#212)

Added 2026-09-25 for [issue
#212](https://github.com/russellgordon/plantoir/issues/212). Everything above
reaches a teacher who opens the app — and, for a success, opens THAT section.
Russell's case: a publish set for 6:30, the laptop opened at 7:45, and nothing
anywhere said whether it had gone out, *"especially when it did not"*. With the
app closed the band waits unseen; with it open on another section a failure
raises the sidebar's triangle but a success shows nowhere.

**The change: when the run finishes, whatever happened, it sends ONE macOS
notification**, which waits in Notification Center until the teacher reads it.
Its text is the section's own sentence —
`scheduledPublishStopped.sentences.<kind>`, through
`ScheduledPublishOutcome.sentence(for:course:section:)`, the words the band
shows — and nothing else. No title of our own: macOS heads it "Plantoir", and
every sentence already begins with the course and the section, which is also
what survives when a long one (`courseWasBusy` runs to ~300 characters) is cut
short in a banner. No new wording, so nothing for the two apps to keep in step
beyond what the contract already pins; `buildDidNotFinish` and every kind added
later are covered automatically, because the notification reads the record
exactly as the band does. `ScheduledPublishNotice` is the code;
`ScheduledPublishNoticeTests` plays the contract's cases,
`scheduledPublishStopped.notification`.

- **A success is announced too, every time** (Russell's ruling, 2026-09-25).
  `attention` gives a success no sidebar badge — a badge nobody reads by
  Wednesday — and that is unchanged; the notification is how a success now
  reaches a teacher who has not opened the section. A teacher who finds it noisy
  turns Plantoir's notifications off in System Settings, and the band still
  carries it.
- **One per section per working folder, replaced by the next run** — the
  identifier is keyed like the record file (`scheduled-publish.<CODE>.section<N>.<folder id>`
  since #237, so two working folders holding the same section never replace or
  withdraw each other's news; `ScheduledPublishNoticeTests.testTwoWorkingFoldersKeepTheirOwnNotification`),
  so section 1 and section 11 never share one — and **withdrawn when the
  teacher dismisses the band**, so the two never disagree about whether it is still news. A
  successful run that clears an older record does not need to withdraw
  anything: its own notification replaces the old one.
- **The run never asks for permission.** A question at half six is a question
  to nobody, in a process about to exit. It is asked the first time a teacher
  schedules a publish from the scheduling sheet or the app's own assistant —
  never at launch, since most teachers never schedule anything. A run that may
  not post writes why on the trail instead (`scheduled publish notification`,
  in both `ActivityTrail.Event` and `activityTrail.mustRecord`): turned off, not
  allowed yet, or could not be sent. The question writes a line when it goes up
  and another with the answer, because the answer may never come.
- **The post happens BEFORE the job is booted out**, since booting it out ends
  the process — the same ordering rule as the trail line above.
  `ScheduledDeploy.announceThenLeave` does it for both the ordinary finish and a
  stand-down (`tooLateToRun`, `courseWasBusy`). It keeps the process alive with
  `dispatchMain()`, the deliberate exception `AssistMCPServer.serve` already
  makes: the function is synchronous, never returns, runs inside `App.init`
  before any run loop exists, and the notification centre only answers
  asynchronously.
- **The wait is bounded at ten seconds, and the bound is REAL.** The first plan
  raced the post against a sleep in a task group. A task group does not return
  until every child has finished, and cancelling a child only sets a flag that
  `UNUserNotificationCenter.add` never looks at — so a notification service that
  never answered would have held the finished run, and its launchd job, for
  ever, while a test whose stand-in honoured cancellation passed. It is now an
  unstructured race that resumes the caller exactly once and leaves the loser
  behind for `exit` to take. `testAPostThatNeverAnswersIsLeftBehindAtTheCeiling`
  uses a stand-in that ignores cancellation, and fails (times out) on the
  task-group shape — proved by putting that shape back.
- **The suite never reaches the real notification centre.** The test host IS
  Plantoir.app, the bundle whose permission this reads, so a test that reached
  it could put the permission question on the screen of the Mac running the
  suite and make whatever was clicked Plantoir's real setting.
  `ScheduledPublishNotice.poster` is `QuietNotifications` (does nothing) under
  the suite, `SystemNotifications` refuses there as well, and
  `AppDelegate` sets no notification delegate under the suite.

**Measured first, on this Mac** (2026-09-25; Apple silicon, macOS 26; the Debug
bundle built into a scratch DerivedData, never the Dock's copy), because none of
the design is worth anything if a launchd-started Plantoir cannot post. A
throwaway LaunchAgent under its own label ran
`Plantoir.app/Contents/MacOS/Plantoir --run-scheduled-deploy <a no-op script>`
through `launchctl bootstrap` and `kickstart`, with a temporary probe (never
committed) posting from the run's own tail exactly where the announcement now
sits; the last row is the finished code, run the same way:

| what | result |
|---|---|
| permission before anything asked | `notDetermined` |
| a post while `notDetermined` | `add` succeeded and it was listed as delivered, but **no banner appeared** — which is why "not asked yet" is its own trail line rather than a post |
| asking FROM the launchd run | the question appeared as a notification ("“Plantoir” Notifications", with Allow / Don't Allow); the answer came back when it was pressed, 22 s later |
| posting from the launchd run, allowed, 3 trials | a banner headed "Plantoir" each time, **3 of 3**; `add` returned in 3–9 ms; the whole exchange 0.04–0.13 s |
| replace: three runs posting one section's identifier, each its own process | **one** entry left, carrying the third run's text |
| withdraw from ANOTHER process — a launchd run, and a copy opened by LaunchServices the way the Dock opens it | removed, **0** left |
| **the shipped code, end to end**: the real `--run-scheduled-deploy … --scheduled-section` path under a throwaway LaunchAgent, its script writing a `succeeded` record and then a `did not finish` one | the section's sentence as a banner each time, the second replacing the first; each run finished in about a second and exited 0 |

The launchd run is a separate process from any open window and shares only the
bundle identifier, which is what permission, replacement and withdrawal are all
keyed by. Three banners appeared while another copy of Plantoir was running (not
in front), so a running app does not swallow them. **Not measured**: the app IN
FRONT when the run posts (the `willPresent` delegate in `AppDelegate` answers
`[.banner, .list]` for that case, as Apple documents it is asked); the screen
locked, and a Focus on. With the screen locked macOS's default "Show previews:
When Unlocked" hides the text, so nothing here promises the lock screen — what
matters is that the notification is waiting in Notification Center. **The
permission this measurement granted is real**: Plantoir on this Mac is now
allowed to send notifications (System Settings → Notifications → Plantoir turns
it off).

**What a teacher who says no, or never answers, gets.** Nothing new: the band
and the triangle are unchanged, and every run writes "turned off" (or "not
given permission yet") on the trail. Nothing in the app asks again — macOS would
not show the question twice — so the fix is System Settings → Notifications →
Plantoir. A question that is ignored, or arrives under a Focus, sits unanswered
in Notification Center; permission stays not-yet-asked, the next schedule from
the app puts the question again (whether macOS shows it a second time while the
first is unanswered was not measured), and the first trail line says a question
was put.

**Rejected, and recorded so they are not proposed again:**

- **Asking permission from the run.** A prompt at half six to nobody.
- **`.provisional` authorisation** (no question; delivered quietly into
  Notification Center only). It would spare the question and deliver exactly
  where a teacher does not look before class: no banner at 7:45 is the silence
  this closes. A teacher who chooses "Deliver Quietly" themselves gets that, and
  the code reads their provisional answer as allowed.
- **The app posting on its next activation.** Misses the app-closed case — the
  case #212 is about — and needs an "announced" marker, which must not live in
  the record (rewriting it re-dates the notice).
- **Sound, a Dock badge, `.timeSensitive`.** A chime at half six in a quiet
  house for news; a badge is the success badge `attention` decided against; and
  breaking through a Focus for a publish needs an entitlement and is Russell's
  call, not ours. The question asks for alerts only.
- **A title of our own.** It would repeat the sentence's course and section.
- ~~**Click-to-open the section.**~~ Deferred here, and done by #306 — see
  "Clicking the notification opens the section (#306)" below.

**Known limits, stated rather than coded for:**

- **A teacher who only ever schedules through an outside assistant** (Claude
  Code, over `--mcp-stdio`) is never asked, so never notified, and every run's
  line says permission was not given yet. That process has no window, so the
  question would appear with nothing on screen to say why. It ends the first
  time they schedule anything from the app itself.
- **A run whose wrapper could not be started at all** (`runScheduled`'s `catch`)
  writes no record, so nothing is announced — the silence that existed before,
  not a new one.
- **A job scheduled before v1.2.0** names no section, writes no record, and
  announces nothing. A job scheduled by a build from BEFORE this change is
  announced like any other: announcing is in the app binary, not in the
  wrapper, so any record, whoever wrote it, is announced.
- **The Debug copy and an installed copy share one bundle identifier**, so one
  permission covers both; a click on a notification with the app quit opens
  whichever copy Launch Services prefers. Since #306 that matters more: an
  installed copy from before #306 has no click handling, so the click only
  brings it forward. The trail's launch line records the bundle path, which
  says which copy a click started.

**Windows** matches the rule (the contract's `notification` cases), and the
delivery is theirs: their run is PowerShell under Task Scheduler with no app
process alive, so a toast must be attributed to Plantoir's own application
identity, and toasts need no permission question — only the contract's
`allowed` and `notAllowed` rows apply there. `platformDifferences.owed` carries
it; GitHub #212 carries the ask.

### Clicking the notification opens the section (#306)

Until #306 a click on the notification from "When nobody is looking" only
brought Plantoir forward, on whatever it had last shown. A teacher who read
"ICS3U Section 2 was not published" then had to find the section by hand. Now
the click shows **that section**. The rule is data, in
`contracts/shared-rules.json` → `scheduledPublishStopped.notification.onClick`
(its `rule`, seventeen `cases` and ten `rejected`). What follows is the reasoning
and the mechanics.

**What the notification carries.** The working folder's path, the course and
the section, in its `userInfo` (`NotificationClickTarget`, keys `v`,
`workingFolder`, `course`, `section`; plist strings and an integer only,
because a value that is not a property-list type makes macOS refuse the whole
notification). The identifier alone is not enough: its last segment is the
folder's id since #237, and that id is a hash, so it names no path. The run knows
the path because its course directory is `<folder>/courses/<CODE>`
(`ScheduledDeploy.workingFolderURL(forCourseDirectory:)`, the same step
`folderIDForRun` takes, so the id and the path cannot disagree; a test pins
it). The path is never shown and never written on the trail. It lives in the
teacher's own notification database with the notification. A notification
with no target, or of another `v`, names nothing, and its click only brings
Plantoir forward.

**Who answers the click.** Only a GUI copy of Plantoir. The run itself is
Plantoir under `--run-scheduled-deploy`, with no `NSApplication` and no
notification delegate. `AppDelegate` sets the delegate in
`applicationWillFinishLaunching`, which is early enough for a click that
launches the app, and `userNotificationCenter(_:didReceive:)` does one thing:
it asks `NotificationClickTarget.requested` whether this is a plain click
(`UNNotificationDefaultActionIdentifier`) on a `scheduled-publish.` identifier,
and hands the target to `SectionFromNotification.receive`. Both filters live
in the tested type, not in the delegate.

**The rule, in the order `SectionFromNotification.decide` applies it** (pure,
and the contract's cases are played against it, then again through the router
with real folders):

1. The notification names nothing → Plantoir comes forward. One trail line,
   with no course.
2. Its working folder is not there any more → Plantoir comes forward. No
   window is opened and none is pointed anywhere. Nothing is said on screen:
   the notification already said how the publish went, and a folder gone at
   launch is #311's sentence.
3. The app is still opening its first window, or any window is still finding
   its folder → **wait** (below).
4. A window is already on that folder → the one nearest the FRONT (not "the
   key window": when a notification is clicked Plantoir is not the active app,
   so none of its windows is key; `NSApp.orderedWindows`, then any window not on
   screen in the order the windows appeared). It is brought forward
   (deminiaturised if needed) and the section is selected with its course
   unfolded. A window that is **busy** is skipped: a sheet is attached, a course
   is being renamed in place, or the app is running a modal dialog attached to no
   window (`NSApp.modalWindow`: an open panel, the quit question), which makes
   every window busy. If every window on the folder is busy, the
   front one is brought forward with its selection left alone. A selection change
   moves the keyboard, and a rename field commits whatever was typed when it
   loses focus (#293).
5. Else a window with **no folder** (the picker, and not busy) takes the folder,
   through `reopen(_:occasion:)` with the occasion
   `.scheduledPublishNotification`. That is #311's one route for a window taking
   a folder it did not choose, so a folder in the Trash or out of the builder's
   reach is said on the picker the way a remembered one is. Its trail line is
   `working folder reopened`, whose `carries` names the occasion. When `reopen`
   refuses it, the click's own line says the folder "could not be opened here"
   (never "gone": the folder exists, and the reason is on the reopen line).
6. Else **a new window** opens on the folder, but only when #290's check
   (`WorkingFolderReach.refusal`) lets a window open there. A new window takes
   its folder through `adoptRestoredPath`, which does not check. So a folder out
   of the builder's reach is refused HERE, and the click only brings Plantoir
   forward with the "could not be opened here" line (a mac-only case). Such a
   folder is also the likeliest to have a failed run to click on (#221). A window
   on ANOTHER working folder is never pointed elsewhere.
7. The section is not in the folder (course renamed, section archived) → the
   window from 4, 5 or 6 is shown with its selection left as it was. It is not
   guessed at.
8. Clicking changes nothing else. The record, the band and the sidebar's
   triangle stay until Dismiss. macOS removing the clicked notification from
   Notification Center is macOS's own doing.

**Waiting is an event, never a timer.** A click that launches Plantoir can
arrive before its first window exists, and a restored window takes its folder a
moment after it appears. Deciding early would either open a second window
beside the one launch is about to show, or put the section's folder into a
window about to be given its remembered one. So the router PARKS the click
while it has seen no window settle (`hasSeenAWindowSettle`) or while any window
has `hasSettledItsFolder == false`. The one exception: a launch that a
notification started (`NSApplication.launchUserNotificationUserInfoKey`) and
that FINISHED with no window registered. Nothing is about to appear then, so
`applicationDidFinishLaunching` decides the click at once
(`SectionFromNotification.launchFinished`), opening the window through the File
menu's New Window item because no window has installed `openWindow`. Whether a
notification launch shows SwiftUI's window at all is unmeasured, which is why
this exists. Otherwise the router decides again inside
`WindowSettling.windowSettled`, which #311's `WorkspaceModel.settleItsFolder()`
calls exactly once per window, whichever way the window got its folder. That is
the invariant any future way of giving a window its folder must keep: end in
`settleItsFolder()`, or a parked click waits for nothing. A click still parked
when the app resigns active is dropped (`forgetPendingRequest`), together with
the folder it set aside for a new window. A newer click replaces an older one
still waiting.

**The new window never shows the wrong folder first.** Before opening it, the
router sets `WorkspaceModel.folderForNextNewWindow`, the field #311 added for
the assistant. `adoptFolderForNewWindow` takes it FIRST, before the launch-time
claims wait (`WindowStartRule.start` → `.requested`). The window settles on it
before its first frame, and a settled window never claims a remembered entry
(#311's one decision per window). So a click's window at launch, with claims
still open and a remembered window left unclaimed, ends on the section's folder
and leaves the entry alone (`testTheClicksWindowTakesItsFolderWhileClaimsAreOpen`).
The field is cleared whenever the click is finished or dropped, so it cannot
leak into the next ⌘N. The opener is `openWindow(id: "main")`, installed by
every `WindowRootView` in `onAppear`.

**Per app state:**

| At the click | What happens |
|---|---|
| Running, a window on that folder | That window (the front one of several) shows the section. |
| Running, windows only on other folders | A second window opens on the section's folder; the teacher's window is untouched. |
| Running, no windows open | A window opens on the folder. |
| Quit, nothing to reopen (fresh account) | Launch shows one window; it settles on the picker; the click is decided then and the picker takes the folder. |
| Quit, #311 reopens the SAME folder | The reopened window settles, then shows the section. |
| Quit, #311 reopens a DIFFERENT folder | That window is left exactly as #311 put it, and a second window opens on the section's folder, in front. Nothing restored is thrown away, and the next launch remembers both. |
| Folder gone, any state | Only comes forward. With the app quit, launch proceeds as it would from the Dock. |

**The trail.** One line per click on the existing event `scheduled publish
notification`, with the `COURSE/N · ` prefix whenever the notification named a
section. The words are the contract's `trailSays`, one per outcome
(`SectionFromNotification.Outcome`). No new event (rejected: the same
notification, the same story). **No line at all** after a click means the click
never reached a copy of Plantoir that handles clicks. The launch line's bundle
path says which copy was started (see the Debug/installed limit above).

**Measured, and not.** Unit tests play every case through the real settle
hook, with real working folders on disk, real window models and the real
`reopen`. One test covers a window path spelled `/var` against the run's
`/private/var`, compared through `FolderIdentity.isSameFolder`. Another covers
the content handed to macOS round-tripped through a binary property list. What a
real click does in each app state was **not** measured here: it needs a real
notification and a person to click it, and posting one to Russell's account was
ruled out. These are on Russell's list in the piece's hand-over:

- a click with the app running on the same folder, on another folder, and quit;
- a click on section 1's notification while section 2's run is still going
  and the GUI is quit. Launch Services may hand the click to the running run
  process, which has no delegate and would lose it silently. If it does, the
  mitigation is a minimal delegate in the run that opens the GUI copy
  (`NSWorkspace.openApplication`), decided after measuring, not built blind;
- the #311 restore ordering (a click that launches the app with two windows
  remembered), and before it the plainer question: with the default "Close
  windows when quitting", quit, click, and check whether ANY window appears. If
  none does, the File ▸ New Window fallback above is what should open one;
- that `openWindow` captured from a window that has since closed still opens
  one (the "no windows open" row). The fallback, if not, is the App-level
  `@Environment(\.openWindow)`.

**Windows** owes the same rule (every case but the four `appliesOn: ["mac"]`:
three waits, which exist because the mac's windows find their folders a moment
after they appear, while Windows builds its remembered windows synchronously in
`OnLaunched`, and the reach case, because #290's check is mac-only). The toast itself (#212's Windows half) comes first. The toast's
launch arguments carry the path, course and section. A cold start routes in
`OnLaunched` after the remembered windows exist. An unpackaged app's toast
activation can start a SECOND process, which must hand its arguments to the
first. Nothing on that side reads `notification` yet, so `onClick` is unrun
there, not red.

### A build that stopped for a question is its own outcome

Proposed from Windows as [issue
#132](https://github.com/russellgordon/plantoir/issues/132) and adopted here on
2026-09-09. **A scheduled publish builds before it publishes**, and since
`--non-interactive` the build can refuse: `preview.sh` has one question of its
own — the 'Open' course-code guard — and refuses it with the same exit 3
`deploy.py` uses. Nothing has been contacted at that point.

This side already recorded that run, and recorded it as the wrong thing. It was
`neededAnAnswer` with `buildDestinationName` standing in for a destination, so
the teacher read:

> …it stopped because publishing to **your website (it could not be built)**
> needed an answer nobody was there to give. **Publish** this section once
> yourself…

Both halves are wrong. It names a destination nothing had contacted, and it
sends the teacher to the button that does not ask the question. The fourth kind
says neither:

> …it stopped **before it started**, because building the pages needed an
> answer nobody was there to give. **Preview** this section once yourself,
> answer the question, and it can publish on its own after that.

**Rejected, and recorded so it is not proposed again:** filling the destination
in with the section's first configured one. It reads correctly and it is false.

**No fourth trail event.** It files under `scheduled publish needed an answer`,
which is about a question going unasked — which is what happened. A fourth
event would put a distinction on the trail that means nothing to the person
reading it. The line names no destination, and
`activityTrail.mustRecord` → that event's `carries` says so.

**The record's second line is still written and never shown.** Every record has
one shape — the kind, then a name — because it is a shell script writing two
`echo` lines at half six, and `stopped(inHomeFolder:course:section:)` refuses a
record whose second line is empty. Since #137 (below) neither build kind shows
it; until then a build that failed OUTRIGHT still put that name in the
teacher's sentence.

**A section already scheduled keeps the wrapper it was scheduled with.**
`oneShotCommand` is called from `scheduleDeploy` and nowhere else, and nothing
rewrites an existing `<CODE>.section<N>.sh` on launch the way the app refreshes
the launchers. So a teacher with a publish already pending when they update
reads the old sentence once, for that run. Records already on disk stay
readable — the old kind is still a kind — which is why the fix could be made
without a migration.

### …and so is a build that failed outright (#137)

Decided by Russell on 2026-09-23 (GitHub
[#137](https://github.com/russellgordon/plantoir/issues/137)) and landed on the
mac 2026-09-25. A scheduled publish whose BUILD exits non-zero with any code
but 3 — a page Quartz cannot build, a build launcher that could not run — used
to be recorded as `didNotFinish`, the kind a DESTINATION gets. On the mac the
record's destination line was `buildDestinationName`, and `didNotFinish`'s
sentence put that phrase where a destination goes — so the teacher read that
publishing to something that is not a destination had stopped, and was sent to
**Publish**. On Windows the wrapper joins every configured destination instead,
so a teacher read that publishing to Netlify and Cloudflare Pages stopped when
neither had been contacted — the shape #132 had already recorded as REJECTED.

It is now its own kind, `buildDidNotFinish`, and its sentence is
`scheduledPublishStopped.sentences.buildDidNotFinish` — Russell's starting
wording, used verbatim and his to polish. It names **no destination** and sends
the teacher to **Preview**, because previewing is what rebuilds the pages and
shows the build's output; its last clause echoes
`AssistWording.couldNotBuildBeforeDeploying`, the assistant's sentence for the
same failure. The badge is unchanged (it needs attention, like every failure).
The trail line files under the existing `scheduled publish did not finish`
event — the run did not finish, which is what that event is about — and names
no destination; `activityTrail.mustRecord` → that event's `carries` says so.
No new event.

**The wrapper's test is "not 3", never "is 1".** `preview.sh` itself exits
only 0, 1 and 3, but a build that never ran exits with whatever stopped it:
127 from bash for a launcher that could not be run, 143 or 137 for a signal,
125 from Docker. Every one of those means no pages were built and nothing was
contacted, which is the only claim the sentence makes. The contract's
`whichKind.cases` carries a 127 row precisely so a port that tests `-eq 1`
fails there.

**Rejected, and recorded so they are not proposed again:**

- **Merging the two build kinds** into one. It loses what `buildNeededAnAnswer`
  promises — answer the question once and the section publishes on its own
  after that — which is true of a question and false of a broken page.
- **Leaving it.** It pointed at the wrong button and named a place nobody
  contacted.
- **Rewording `didNotFinish` to cover both.** A sentence that fits "Netlify
  refused your token" and "your pages would not build" names neither the place
  nor the fix.
- **Telling the two apart in the app by the record's destination text**
  (`destination == buildDestinationName`). That makes a display string carry
  meaning, and it could then never be reworded.
- **Renaming `buildDestinationName`** now that nobody sees it (the issue
  floated "the pages could not be built"). Only a person opening the record in
  TextEdit would notice, the record format is platform-local, and keeping the
  value means a record from a wrapper scheduled before #137 and one from after
  differ only in the kind line.
- **A read-side shim** mapping an old `(did not finish, buildDestinationName)`
  record to the new kind. It is the display-string inference above, bought for
  one run's wording.

**Known limits, stated rather than coded for:**

- **A section already scheduled keeps its old wrapper**, as it did for #132:
  `oneShotCommand` runs only when a deploy is scheduled, and nothing rewrites a
  pending one. Its one remaining run records a failed build as `didNotFinish`
  and the teacher reads the old sentence once. Records already on disk stay
  readable.
- **A build that fails INSIDE a destination's own rebuild** reaches the
  wrapper as that destination's exit 1 and is still `didNotFinish` naming the
  destination, because the exit code is all the wrapper has. Two such rebuilds
  exist. `deploy.py` rebuilds for production whenever the built site's
  `baseUrl` is not the destination's address (`ensure_base_url_and_rebuild`) —
  on a first publish to an address, or after the address changes — and,
  **unmeasured but very likely, on EVERY run of a course that publishes to two
  destinations with different addresses** (Netlify AND Cloudflare Pages, say):
  the site is built for one address, and the next destination finds the other
  one baked in and rebuilds for its own. So that one stays reachable whatever
  happens to #136, and for such a course it is not a first-publish corner. And both `deploy.py` and `deploy.sh` rebuild a site they
  find carrying the preview's live-reload client — reachable in a scheduled run
  only while the wrapper's is-the-site-stale check is narrower than the
  launchers' (the gap described under "How it is tested" below,
  [#136](https://github.com/russellgordon/plantoir/issues/136)). Whichever of
  #136 and #137 lands second re-reads this paragraph. Giving a destination's
  rebuild its own exit code was rejected there as a launcher contract change
  Windows shares.
- **A failure that was only passing** — Docker or Colima not answering, the
  build stopped by a signal — is `buildDidNotFinish` too. The teacher previews,
  it simply works, and "the reason will be in that section's window" is then not
  literally true: there is no reason left to see. Accepted: Preview is still the
  right thing to do, and it is strictly better than a destination nobody
  contacted.
- **An older build of the app reading a new record** does not recognise the
  kind and treats the record as half-written (`record(at:)` returns `nil`).
  Only reachable by downgrading, and true of every kind added since #132.

### The two widenings, and what still differs between the platforms

Recorded in `contracts/shared-rules.json` → `scheduledPublishStopped`
→ `platformDifferences`, which is where the two apps are compared.

Russell decided both on 2026-09-09, and both are now on **both** platforms
(Windows landed them the same day, GitHub issue #130):

1. **ANY failed scheduled publish is recorded, not only "needed an answer".**
   A teacher should learn their overnight publish did not happen whatever the
   reason — a revoked token, a network that was down — because **the silence is
   the complaint, not the cause**. Recording only exit 3 leaves an ordinary
   overnight failure just as silent as before, which is the same complaint in a
   different coat.
2. **The teacher can dismiss it.** Clearing only on a successful run leaves the
   message standing after somebody has already fixed the problem by hand, and
   the next scheduled run that would clear it could be a week away.

**The fourth outcome is on both sides too**, as of the same day —
`buildNeededAnAnswer`, proposed to the contract from Windows and adopted here
in issue #132's work, described in full in the section above. That sentence
used to end "this suite is red on `kinds`/`sentences` until the mac adopts it",
which was true when it was written on the Windows branch and stopped being true
the moment these two merged.

**`buildDidNotFinish` is on the mac only, as of 2026-09-25** (#137, above), and
Windows owes it: their wrapper still records a failed build as `DidNotFinish`
with every destination joined, and their suite goes red on `kinds` and
`sentences` until it adopts the kind, which is the request rather than damage.
So do `tooLateToRun` and `courseWasBusy`, on the conditions the contract gives
for each; `platformDifferences` is where that is kept current.

**One difference remains, and it is deliberate: who writes the trail line,
which cannot be the same on both.** Here the
launchd agent runs Plantoir, so the RUN writes it, as the `trail` key describes.
On Windows Task Scheduler runs plain PowerShell with no app process alive, so
that side sweeps every record when the app next opens, dating each line from the
record rather than from the reading. Writing it from the wrapper's own shell was
rejected there for the same reason it was rejected here — see below. The
property the contract is actually asking for survives either way: **a teacher
who never opens the failed section still gets the line**, and that teacher is
precisely the one who writes in to say their site did not update.

### What was rejected

**Writing the trail from the wrapper's own shell.** Not because nothing of
ours is loaded — Plantoir runs the wrapper — but because a shell script
appending to the trail would put the line's format in a second home, in
generated bash, where nothing tests it and `LogRedactor` does not reach. That
is the one thing that must not be reimplemented: it is what keeps a teacher's
own words off the trail. The app writes the line itself the moment the wrapper
returns, which has the same property the wrapper would have had — a teacher who
never opens the section still gets it.

**Naming the question on the trail.** The question's text comes from a
launcher's console; a line naming a credential prompt would put a teacher's own
words there. The trail carries the course, the section and the destination that
stopped — or, when the BUILD stopped, that it stopped before any destination
was reached, because none was.

**Clearing the record inside the destination loop.** A course publishing to two
places whose Netlify leg stopped and whose folder leg succeeded would have had
the note cleared by the second leg. It is cleared only after every destination
has run, and only when every one succeeded.

### How it is tested, and the honest limit

`ScheduledPublishOutcomeTests` **runs the generated shell** rather than reading
it — a stub workspace, the real script through `/bin/bash`, and then a look at
the file it left. A test that only asserts the generated TEXT proves the string
is what we meant to write and nothing about what bash does with it.
`testEveryLegAndExitCodeIsFiledAsTheContractSays` plays every
`scheduledPublishStopped.whichKind` case that way — which leg stopped, with
which code — and checks the kind, whether the sentence names the record's
destination, and whether the run counts as published; Windows runs the same
cases against its own wrapper.

The limit worth stating: those runs use **stub launchers** that exit with a
chosen code. That the real `deploy.sh` exits 3 in the states we think it does is
proved separately — by `scripts/test_deploy_non_interactive.py`, which reads the
launcher, and since 2026-09-09 by `scripts/test_deploy_sh_questions.py`, which
RUNS it to each of the four questions it can ask and checks the refusal is
visible as well as the code being 3 — and end to end only by
`verify-deploy.sh`, which publishes to real Netlify. The BUILD leg's exit 3 is
proved the same way from the same date, by
`scripts/test_preview_sh_questions.py`, which runs `preview.sh` to its one
question — including in the flag ORDER the launchd wrapper writes, which is
the shape a parser bug would hide.

**One narrow path could produce the sentence #132 removed**, and it was closed
by [issue #136](https://github.com/russellgordon/plantoir/issues/136) on
2026-09-25. **Publishing to a FOLDER, and only to a folder**, reruns the build
itself: `deploy.sh` greps the section's whole `public/` tree for
`ws://localhost:` and, finding it, runs `preview.sh --build-only` and passes its
exit 3 straight through (`deploy.sh:472` opens the `TO_FOLDER` branch the rerun
sits in). The wrapper could only see that as the folder's own question, because
the exit code is the only thing it gets. Netlify and Cloudflare do not reach it
at all — they go through `deploy.py`, whose `rebuild_for_production` runs
`build_site.py` directly, asks nothing, and fails with 1, so those land in
`didNotFinish` naming the destination, which is honest.

Reaching the folder case needed the wrapper to have skipped its own build, and
that was possible because the wrapper's staleness check — `BuildFreshness.
needsRebuild` written out in shell — looked at `index.html` **alone**, while
`deploy.sh` greps the tree: a clean front page in front of a stale preview page
got through. Both checks now read the whole tree, from
`contracts/app-rules.json` → `buildFreshness.previewBuild` (see "One rule, six
readers" above), so whenever `deploy.sh` would rerun the build, the wrapper
has already built, and a question there is recorded as the build's.
`ScheduledPublishOutcomeTests.testABuildQuestionBehindACleanFrontPageIsTheBuildsNotTheFolders`
runs that state through the generated shell with a stand-in `deploy.sh` that
does what the real one does. The rerun is now reached only from the command
line. Giving the rebuild its own exit code was rejected as a launcher contract
change Windows shares.

## A course kept for reference is never deployed — fifteen doors, one rule

A REFERENCE COURSE is last year's course, or a course full of example content,
kept in this year's sidebar to be read. It may be previewed; it is never
deployed. The keys are in
[`08-course-config-reference.md`](08-course-config-reference.md), the lock is in
[`09-mac-app.md`](09-mac-app.md), and the whole rule as data — including the
door table below — is
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`referenceCourses.refusal`.

**A missed door is a deploy that REPORTS SUCCESS**, which is the worst
direction this feature can fail in. So the doors were enumerated from the code
twice, independently — by the plan and then by its review, which went looking
for a sixteenth and found none — and each refusal has a test PROVED to fail
with that refusal turned off.

| Door | Caught at |
|---|---|
| The section window's **Deploy** button | `SectionDetailView.refusalForAReferenceCourse`, first thing in `deployAndWait()` (and the button is not drawn at all) |
| The local assistant's `deploy_section`, window branch | `AssistToolRunner.deploySection`, **before the preview is stopped** |
| …its headless branch | the same, plus `AssistToolchainWork.deploy` |
| The deploy approval card's **Go** | the same — and closed by construction: the assistant is never offered on a reference course |
| `deploy_section` over **MCP** | the write gate in `AssistToolRunner.run(call:)`, then the two above |
| `schedule_deploy`, local and over MCP | `AssistToolRunner.scheduleRequest`, then `ScheduledDeploy.problem` |
| The sidebar's **Schedule Deploy…** sheet | `ScheduledDeploy.problem`, **before** "that time has already passed" |
| A scheduled deploy **already on disk**, firing | `deploy.sh`'s own check |
| `plan_scheduled_deploy` (MCP only) | `AssistToolRunner.scheduleRequest` |
| `./deploy.sh <CODE> <N>` by hand, to a web host | `deploy.sh`, then `deploy.py` |
| **`./deploy.sh <CODE> <N> --to-folder <path>`** | **`deploy.sh` and ONLY `deploy.sh`** |
| `deploy.bat` → `deploy.ps1` | `deploy.ps1`'s own check |
| `python3 scripts/deploy.py …` | `deploy.py`, first thing in `main()` |
| `verify-deploy.sh` / `.ps1` | inherits the two launchers' |

### Why door 12 needs the SHELL and not only `deploy.py`

The folder destination does its work with `rsync` **on the host** and `exit 0`s
before the container is ever started (`deploy.sh`, the `--to-folder` branch).
`deploy.py` is never entered on that path. A refusal written only in the shared
Python therefore leaves the folder destination wide open — and this is measured
rather than argued: with the launcher's check removed, the launcher published a
frozen course and said

```
✅ Published: 1 file(s) updated.
```

exit 0. That is the same shape as the live-reload defect of 2026-09-05, which
is why `verify.sh` greps **both** `deploy.sh` and `deploy.ps1` for this guard
as well as for that one. The structural check costs six lines and makes the
Windows obligation visible from this side rather than only in an issue.

### FOUR readers, one rule — and the table that keeps them honest

The APP, `scripts/reference_course.py`, `deploy.sh` and `deploy.ps1` all answer
"is this course kept for reference?", and two of them have no JSON parser. So
the question is ONE regular expression over the whole settings file as a single
string, in three dialects, with a table of **twenty-six** inputs all four are
asserted to agree on:
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`referenceCourses.markerAgreement`, run by `scripts/test_reference_course.py`
against the real launcher.

**The table exists because the three did NOT agree, in the dangerous
direction.** `grep` works a LINE AT A TIME, so `[[:space:]]` cannot span a
newline: a config whose key and colon sat on different lines was a reference
course to the Python and an ordinary course to the launcher — and the launcher
published it, exit 0, `✅ Published: 1 file(s) updated.` Found by review on
2026-09-20. The cure is `tr '\n' ' '` before the `grep`, which also makes bash
agree with PowerShell, whose `-cmatch` uses .NET regex where `\s` already
matches a newline. (`-cmatch`, not `-match`: PowerShell's default match is
case-INSENSITIVE and that applied to the KEY as well, so
`"KEPT_FOR_REFERENCE": true` refused on Windows while the mac and the Python
allowed it. JSON keys are case-sensitive; the value's case is written out
instead.)

**The app is the fourth reader, and it joined after it disagreed.** Measured:
`JSONSerialization` hands back an `NSNumber` for `1`, and `NSNumber`
conditionally bridges to `Bool` for 0 and 1 — so `"kept_for_reference": 1`
read TRUE in the app, which FROZE AND LOCKED the course, while all three
launchers read the same file as ordinary and deployed it. The app now reads
this one key through `CFBooleanGetTypeID`, and every row of the table states
what the app reads it as, with one invariant asserted on both sides:
**wherever the app says reference, every launcher must refuse.**

Two decisions inside the table are worth carrying:

- **When in doubt, REFUSE.** The directions are not comparable — a live course
  wrongly refused is loud and harmless, a reference course wrongly deployed
  reports success. So a marker nested inside another object is refused, even
  though a JSON parser would not call it the top-level key.
- **"Cannot tell" for anything somebody plainly MEANT.** A marker whose value
  is the string `"true"`, the number `1`, `True`, or whose key is written with
  `\u` escapes, is refused with a sentence of its own — which publishes
  nothing and freezes nothing. The app reads a real JSON boolean and nothing
  else, so it shows an ordinary course, and the launcher's refusal is what the
  teacher meets. Leniency in the APP was considered and rejected: its reading
  locks the course, with no way back, so a false positive there is not loud
  and harmless.

And the exact surface, because "no pattern matches a value" turned out to be
only half true: a config is refused when it carries a **quoted token — key or
value — whose text ends in the key's tail** and is not followed by `true` or
`false`. The marker's own text reaches a VALUE only through escaped quotes,
which never match, so no realistic config is refused; what would be is a
course name, folder name or path that literally ends in `ept_for_reference`.
The one shape refused with the *reference-course* sentence rather than "cannot
tell" is a key like `accept_for_reference`, and it is a row in the table so the
surface is written down rather than discovered.

**A key written with `\u` escapes is refused whatever the key is** — that rule
is about the ESCAPE, not the marker. A key escaped all the way through is
decoded by the app, which freezes and locks the course, while a text reader
sees nothing at all: measured, it deployed. Every key Plantoir and the shared
Python write is plain ASCII. **Values are deliberately left alone**, because
`json.dump` escapes non-ASCII there by default and accents and emoji are
ordinary; the `[{,]` anchor is what tells a key from a value. Proven against
copies of the four real previous-generation configs, all 38 example-content
payloads and hand-made values carrying escaped quotes and colons: no false
refusal.

### Plain shell, failing CLOSED, and no new exit code

The launcher's check reads `course_config.json` with `grep` — **no host
`python3`**. Everything before the flag loop, and the whole folder publish, needs
no interpreter on the host today, and this product's first-run promise is "no
Homebrew, no admin rights"; adding one here would break publishing for a teacher
whose Command Line Tools are missing.

It **fails closed**: a settings file that is there and cannot be read refuses
and says so — and `deploy.py` asks the same question through
`reference_course.cannot_tell()`, so running it directly gives the same answer
rather than a quieter one. A settings file that is ABSENT is not its business — the course
folder check further down answers that in its own words. The shared Python is
the other way round on purpose: a malformed config reads as NOT a reference
course, because a course nobody can open must not become undeployable by
accident, and the marker is not the only defence anyway.

**No fourth exit code.** `deploy.sh` states its own invariant — exit 3 means "a
question nobody was there to answer" and nothing else, every other exit is 0 or
1 — and a new code would have to be read by the scheduled wrapper, by
`ScheduledPublishOutcome` and by the Windows twin before it meant anything.
Exit 1, matched on OUTPUT by an `app-rules.json` → `failureExplanations` case,
which is how every other launcher failure already becomes a sentence. That case
matters most for a deploy set to happen on its own: it runs with the app closed,
and without it the app shows the generic "did not finish" while the real reason
sits in a log nobody opens.

**Which is why every assignment in that shell block ends `|| true`.** `deploy.sh`
runs under `set -euo pipefail`, and `grep -Eo` exits 1 when a config carries the
marker and no `course_code` — so the script died on the line that reads the code,
BEFORE the echo, and exited 1 with no output at all. Fails closed, publishes
nothing, and says nothing: the one shape that defeats matching on output. Found
by review on 2026-09-20; `test_a_marker_with_no_course_code_still_says_the_sentence`
asserts the SENTENCE rather than the exit code.

### The refusal does NOT depend on the lock

Gated on the marker alone, never on whether the files happen to be locked, and
a test pins it. If the two were coupled, a course restored from a backup — or
one whose folder had been on a second Mac, where the locks do not travel —
would silently become deployable.

### And the fail-safe, for a Plantoir that has never heard of any of this

A teacher may keep their working folder in iCloud Drive and open it on a second
Mac still running an older release. That copy does not know the marker. So
whatever makes a course a reference course ALSO writes `deploy_target:
"local_folder"` with an empty `deploy_folder_path`, drops
`additional_deploy_targets` and `custom_domains`, and renames the
`.netlify_sites/` and `.cloudflare_sites/` markers aside to the frozen
`section<N>.previous-<stamp>.json` name. Every shipped version refuses a folder
deploy with no folder, in sentences it already has
(`MultiDestinationDeployRunner.refusalReason`, `ScheduledDeploy.problem`), and a
section that has never deployed cannot be scheduled at all.

**What that leaves, stated rather than hidden.** An older Plantoir refreshes
`.toolchain/` back to its own copies, so an old `./deploy.sh` run by hand on
that Mac could still reach Netlify — and, with the markers renamed aside, it
would create a **brand-new site** rather than overwrite last year's. Litter,
not damage. It cannot be closed by construction and belongs in the release
note. Worth knowing too: the fail-safe's words on an older app are an
invitation — *"Choose the folder this course deploys into."* — so a determined
teacher can undo it. That is the honest cost of a defence written in a file
format an old version can read.

## Scheduling a section that already has a deploy set

Added 2026-09-23, [issue #195](https://github.com/russellgordon/plantoir/issues/195).

**The behaviour is unchanged: scheduling a section again REPLACES the deploy
already set for it.** There is one job per section per WORKING FOLDER (one per
section per Mac until [#237](#one-alarm-per-working-folder-237)), and
`ScheduledDeploy.scheduleDeploy` boots the old one out and overwrites its plist
before writing the new one. What changed is that the teacher is TOLD, before
and after:

- **Before — the approval card, the schedule sheet and the assistant's plan.**
  Each appends `AssistWording.scheduleReplaces`, naming the moment the old one
  was set for (`wording.scheduleReplaces`, placeholder `{moment}`, written with
  `dayAndTimeText` like the card's own moment). The card is built by
  `AssistToolRunner.explain(call:)`; the sheet and the plan twin both read
  `ScheduledDeployPlan.description`, which carries `replacing` from
  `ScheduledDeploy.plan`. One sentence, three places, one function
  (`ScheduledDeploy.momentBeingReplaced`). The card is the only moment before
  anything is written, which is why it is the place to say it — #168 made
  "deploy at <time>" a parsed family, so a teacher changing their mind twice in
  one conversation is ordinary rather than rare.
- **After — the trail.** `scheduled deploy replaced` (both
  `ActivityTrail.Event` and `shared-rules.json → activityTrail.mustRecord`)
  carries the section, the old moment and the new one. It is written inside
  `scheduleDeploy` itself — the one function the sheet, the in-app assistant
  and an outside assistant over MCP all reach — from a reading taken BEFORE
  the old job is booted out, and only once the new one has been accepted.
  Without it, "it went on Saturday, I set it for Friday" has no answer: the old
  job leaves nothing behind.

**Read in THIS working folder since #237 — the reversal of what #195 chose.**
#195 read it Mac-wide on purpose: the job being overwritten could belong to
ANOTHER working folder holding the same code (last year's), because the label
then named one file per code and section for the whole Mac, and a folder-scoped
reading would have stayed silent in exactly the case that mattered most. #237
gave each folder its own alarm, so scheduling here no longer touches another
folder's job — and a Mac-wide reading would now name, on this folder's card, a
deploy this scheduling leaves standing, which is false. `momentBeingReplaced`
and `momentAlreadySet` take the working folder (required), and so does
`ScheduledDeploy.plan`. A job this folder set BEFORE #237, under the old label,
is found by the folder scan and IS replaced — see the #237 section.

**Said nothing, deliberately:** when the old job is set for the SAME minute
(scheduling the same moment again replaces nothing a teacher would notice), and
when its moment has already gone by (a job that fired, or was left by a Mac
that was off, is not a promise being broken — `nextRun` already treats it as
nothing).

**REJECTED:**
- *Writing the trail line from the two callers* (the assistant's
  `scheduleDeploy` tool and `ScheduleDeploySheet`), which the first plan
  proposed. Two writers is one to forget, and the MCP path would have been a
  third; the function they all call already had the old plist in hand.
- *A contract scenario for the card.* It would need a new `given` key on both
  runners (an existing job, in another folder) — bigger than the fix; the
  wording key and the unit tests carry it
  (`AssistToolRunnerTests.testTheScheduledCardSaysWhatItReplaces`, whose old
  job is in a different folder so a folder-scoped version fails it, and
  `ScheduledDeployTests.testSchedulingAgainSaysWhatItReplacesAndRecordsIt`).
- *Stopping the replacement, or asking a second question.* The issue asks to
  SAY it; replacing is still what a teacher who changes their mind wants.

**The result says it too, for a caller with no card.** `schedule_deploy` over
`--mcp-stdio` puts no card in front of anybody, so its RESULT (the "Scheduled:
…" summary the tool returns) appends the same `wording.scheduleReplaces`, read
before the old job goes. Added on the implementation review, which found the
outside-assistant path silent; the tool's description and schema did not move
(surface hashes unchanged).

**A replacement that FAILS: two shapes, and the trail tells them apart.**
`scheduleDeploy` boots the old job out, writes the one-shot script, then
writes the plist (atomically) and only then asks macOS to take it.

- **macOS refuses the new one** (the bootstrap fails): the old plist has
  already been overwritten, so the teacher has NEITHER — and the sentence they
  are shown speaks only of the new one. The trail gets `scheduled deploy could
  not be set` for the new moment AND `scheduled deploy turned off` for the lost
  one, with when it had been set for — that event's FIFTH reason (course
  removed, section removed, the day gone by, kept for reference, and this),
  since it exists for a deploy turned off by something other than the teacher
  asking. Recorded for the SAME minute too: the card rightly says nothing when
  the moment is unchanged, but a same-minute deploy lost is still lost, so the
  record reads `momentAlreadySet` (this folder's, same minute included) rather
  than `momentBeingReplaced`.
- **The new one's files cannot be WRITTEN** (anything that throws before or
  in the plist write): the old plist is still on disk, only booted out — so it
  is handed back to macOS at once (otherwise it would sit unloaded until the
  next login and miss its moment), and the trail gets `scheduled deploy could
  not be set` saying the old one still stands. NOT "turned off", which would
  be false: the old job would still fire. If macOS will not take it back, it
  IS turned off, and says so. Known and left as it was: the one-shot script is
  written before the plist at the same path, so a restored old plist runs
  whatever script the failed attempt managed to write.

Found by the fix review (Opus) of the first version, which recorded "turned
off" on both shapes and nothing for the same minute. Tests:
`ScheduledDeployTests.testAReplacementThatFailsRecordsTheDeployItTurnedOff`,
`…testARefusedReScheduleForTheSameMinuteRecordsWhatWasLost`,
`…testAFailedWriteLeavesTheOldDeployStandingAndSaysSo` (the write is made to
fail by putting the scripts folder under a file).

**Closed by [#237](https://github.com/russellgordon/plantoir/issues/237):**
the two limits this section used to list — a job set from ANOTHER working
folder for the SAME minute said nothing, and a job from another folder was
NAMED on this window's card while its sidebar showed no clock and its Cancel
refused it — were both the one-alarm-per-Mac fault. Another folder's job is now
a different alarm, neither named nor replaced.

**The suite never reads the real LaunchAgents through this reading.**
`momentBeingReplaced` answers nil under the test suite unless
`launchAgentsDirectoryOverride` is set — fixed at the SOURCE after the
implementation review found two tests outside the scenarios
(`ScheduleDeployCardTests.testTheTrailLineNamesTheMomentItSettledOn`,
`AssistWindowBindingTests.testTheSameCourseInAnotherCasingRunsInThisWindowsSpelling`)
reading Russell's real `ICS3U` section-1 plist through the card. Those two now
set the override too, and `AssistScenarioTests` sets it for every scenario
(`testTheScenariosNeverReadThisMacsScheduledDeploys`). Measured with a probe
that logs a stack whenever `launchAgentsDirectoryURL()` is reached under the
suite with no override (and returns an empty scratch folder, so nothing real
was read): full suite, **0 stacks through `momentBeingReplaced`** with the fix
(1,714 tests); with only the source guard and neither test's override, still 0;
with both removed, exactly those 2. The same probe counts **~344 OTHER reaches**
that predate this piece — 313 from `WorkspaceModel.sweepScheduledDeploysThatAreTooLate`,
26 from the sidebar's `scheduledDeployTime`, a handful from agent listing —
which were the suite-wide `~/Library` reaches #240 existed to close. #240 closed
them at the source: under the suite `launchAgentsDirectoryURL()` now answers an
empty throwaway folder unless a test names one, and `LaunchControl.run` refuses
there whether or not the override is set (`documentation/09-mac-app.md`, the
#240 passage). `momentBeingReplaced`'s own guard stays, as the second of two.

## A scheduled deploy that outlived its course

Added 2026-09-20, [issue #236](https://github.com/russellgordon/plantoir/issues/236).
The rule and its case lists are `contracts/shared-rules.json` →
`scheduledDeployCancellation`; this is the reasoning behind them, and the
measurements.

**Two faults, and they are independent.**

| | Fault | Reachable how |
|---|---|---|
| **A** | A job survives the removal of its course or section and fires once on its date, against whatever is in the folder by then. | The sidebar's **Remove**. |
| **B** | A job that NEVER RAN — the Mac was off at the moment — stays on disk and comes due again a YEAR later, because `StartCalendarInterval` carries a month, a day, an hour and a minute and no year. | Any Mac that is off at half six. Independent of A. |

Fault B is what makes A perennial rather than a one-off, which is why closing B
is the load-bearing half.

### Which direction fault A errs in — measured, and worse than it looked

The issue said the dangerous edge was "a teacher who publishes to a folder".
Measured on 2026-09-20 against `deploy.py`, it is two of the three destinations:

- **Netlify refuses.** `publish_to_netlify` reaches `refuse_to_ask` and exits 3,
  because the site marker lives INSIDE the course folder
  (`.netlify_sites/section<N>.json`) and went with it. Litter and a puzzling
  record; nothing published.
- **Cloudflare Pages does NOT refuse.** `publish_to_cloudflare` contains no
  `refuse_to_ask` at all. The one thing it would have to ask for is the
  teacher's surname, and that is read from `courses/.internal/profile.json` —
  the **working folder**, not the course folder — so it survives the removal;
  `suggest_pages_name` is deterministic from code, section, year and surname,
  and `ensure_pages_project` creates or reuses a project. So an orphan builds
  THIS year's course, publishes it, exits 0 and records success, at a public
  address the teacher never chose.
- **A folder destination does not refuse either**, because a folder destination
  asks nothing ever.

So "the failure that reports success" is not a rare edge for somebody with a
school network share — it is every folder course and every Cloudflare course.
The plan for this piece said Cloudflare refused; that was wrong, and correcting
it is why the severity went up rather than down.

### The lateness check, and why it is not a calendar

`runScheduled` re-checks its own moment before anything else happens.
`ScheduledDeployLateness.mayStillRun` compares `abs(now − intended)` against the
window on **absolute instants** — no `Calendar`, no `TimeZone`, no daylight
saving anywhere. Measured (`swiftc -O`, this Mac, 2026-09-20), against the
"same calendar day" rule first proposed:

| what happened | same calendar day | elapsed time |
|---|---|---|
| a 23:50 job, Mac woken 00:05 — the coalesced wake `man launchd.plist` documents | refuses | **runs** |
| 06:30 job, Mac woken 09:00 the same morning | runs | **runs** |
| 06:30 job, Mac off overnight, opened 17:00 the next day | refuses | **runs** |
| scheduled in Toronto, fires at 06:30 local in Tokyo (13 h EARLY) | runs | **runs** |
| the same date a YEAR later | refuses | **stands down** |

Row one is why the calendar rule was rejected: a fifteen-minute delay turning
into a silent non-deploy is the precise harm this whole piece exists to prevent.
Row four is why the comparison is `abs` rather than one-sided — after a
time-zone move the job fires BEFORE the instant that was recorded.

**It fails open.** A moment that cannot be read means RUN. Fail-closed would
turn one unparseable stamp into every scheduled deploy silently not happening,
which is worse than the fault being fixed.

**It reaches jobs already on disk**, and that is the reason it, rather than any
sweep, is what closes fault B for teachers who already have an orphan: every
released plist's `ProgramArguments[0]` is the app's own binary
(`Bundle.main.executableURL?.path`, true in v1.0.0 through v1.2.1), so an
upgraded app at the same path runs the NEW check for an OLD job the moment it
next tries to fire.

### The window is the teacher's, per course

Russell's decision, 2026-09-20. The default is **a week**, not the twenty-four
hours first proposed: a teacher away sick opens the laptop twenty-six hours late
and still wants the site updated, and a laptop closed over a weekend is
ordinary. The fault being closed is about eleven months late, so the window only
has to sit far below that.

The choice is `scheduled_deploy_may_run_late_days` in `course_config.json` — 1,
3, 7 or 14 — offered in Course Settings under Deploying. **There is deliberately
no "always"**: that is the annual recurrence, handed back to the teacher as a
preference. Anything stored that is not one of the four reads as the default, so
a hand-edited `0` cannot stand every scheduled deploy down.

It is read **at the moment the deploy fires**, out of the course's own settings
file in the working folder the job named, by a process with no app around it —
so changing the setting after scheduling changes what a job already on disk will
do. The folder-open sweep asks the same question through the same function; two
answers to "how late is too late for this course" is one more than anybody can
keep in step.

**The destination is read the same way, since #323.** Until then it was fixed
when the deploy was scheduled — `scheduleDeploy` wrote each destination's
`deploy.sh` arguments into the wrapper — so changing where a course deploys
after scheduling sent the deploy to the OLD place, and it reported success.
Now the run reads the course's settings when it fires and writes the wrapper
afresh; see "Where it deploys is read when it runs (#323)" at the end of this
page. What is read AT SCHEDULING still matters for the refusals the sheet and
the assistants give then: since #322 either assistant reads the SAVED file
(docs 10 → "Settings are read at the call, not when the window opened"), while
the schedule SHEET uses the window's copy of the course, which follows a Save
and also carries Course Settings edits not yet saved
([issue #335](https://github.com/russellgordon/plantoir/issues/335)). Since #323
that copy decides only what the sheet says and what `PLANTOIR_SCHEDULED_TO`
records — the run reads the file.

**Finding the course folder is not `fileExists` on a built path, and that is
measured.** A job written before the course code went into the plist carries it
only in its LABEL, uppercased with every non-alphanumeric turned into a hyphen —
so a course called "Chess Club" comes back "CHESS-CLUB". Asking the filesystem
whether `courses/CHESS-CLUB` exists answers **yes** on a teacher's volume, which
is case-insensitive by default, when the folder is really called `Chess-Club`:
a different course entirely, whose window would then be read for this job. The
names in `courses/` are compared directly instead — an exact match first, then a
unique sanitised one — which takes the filesystem's opinion out of it. With no
unique answer the default applies, the same answer a course that has gone gets.
Caught by the suite on 2026-09-20 against a folder pair one hyphen apart.

### What a stand-down does, in order

The order is the wrapper's own, for the wrapper's own reasons:

1. **The plist first**, so a Mac that restarts in the middle comes back with
   nothing pending. The label comes from the wrapper SCRIPT's path — the
   basename is the label — rather than from a course code and section, because
   a plist written before v1.2.0 carries neither, and those are exactly the jobs
   that have been waiting to fire a year late.
2. **The wrapper**, so a job that is off leaves no runnable copy of itself.
3. **The teacher's note and the trail line**, through the machinery that already
   exists for a scheduled publish that did not get through — a
   `ScheduledPublishOutcome` record the section shows, and one trail line.
4. **`launchctl bootout` LAST**, because booting the job out ends this very
   process. Then `exit(0)`: nothing went wrong, and a non-zero exit would land
   in the section's log as an error nobody can act on.

**A new outcome kind, `tooLateToRun`**, rather than filing it under
`didNotFinish`. That was weighed and the existing kinds genuinely cannot carry
it: `didNotFinish`'s own sentence names a DESTINATION that stopped, and here
there was none — filling that slot in is the exact mistake
`buildNeededAnAnswer` was created to stop being made, recorded as REJECTED in
the contract in as many words. It is also not a failure: nothing was attempted
and nothing went wrong, and the sentence has to say so or a teacher goes looking
for a fault there was not.

### Everything is scoped to ONE working folder

Until #237 an agent's label was the course code and the section number and
nothing else, so `~/Library/LaunchAgents/<label>.plist` named **one file per
code and section for the whole Mac**, and a teacher holding last year's working
folder and this year's, both with ICS3U section 1, had one alarm between them.
#237 gave each folder its own ("One alarm per working folder", below) — and this scoping STAYS, because
it is how every reader FINDS a folder's jobs, including the ones set before
#237 under the old label.

So every one of these reads the plist's `WorkingDirectory` and leaves alone
anything belonging to another folder:

| Where | What it does |
|---|---|
| `ScheduledDeployCleanup.removeCourse` / `.removeSection` | the sidebar's Remove |
| `ScheduledDeployCleanup.sweepDeploysThatAreTooLate` | the folder-open sweep |
| `ScheduledDeployCleanup.warningForConfirmation` | the extra sentence in the confirmation |
| `CourseRenamer.sectionsWithAScheduledPublish` | what a rename turns off |
| `ScheduledDeploy.nextRun(inWorkingFolder:)` | the sidebar's clock, and so the Cancel item beside it |
| `ScheduledDeploy.momentBeingReplaced` / `momentAlreadySet` | the card's "replaces" sentence and the failed-replacement record (Mac-wide until #237) |
| `ScheduledDeploy.scheduleDeploy` | which of this folder's jobs a new one retires (#237) |
| `AssistToolRunner.cancelScheduledDeploy` | the assistant's own cancel, and its tidy-up branch |
| `AssistToolRunner.turnOffAnyScheduledPublish` | the rollover onto a new website |
| `ScheduledDeploy.cancelScheduledDeploy` | the backstop under all of them |

**The last two are the ones to know about.** `turnOffAnyScheduledPublish` was
left folder-blind when the rest of this landed — it asked only whether a file
with that label exists — so for one day a rollover in this year's folder deleted
last year's live deploy and said it had turned it off, while the contract
sentence above asserted it could not. Nothing ran that sentence; the `cases`
list had no rollover entry. It has one now, and the lesson generalises: a claim
of the form "everything does X" needs a case behind it or it is prose that reads
as a gate.

The backstop is why the list cannot grow a hole again. `cancelScheduledDeploy`
takes the working folder as a **required parameter** and cancels only the jobs
the folder scan finds for it — each by its OWN label and plist
(`ScheduledDeploy.cancel(agent:runner:)`), never a rebuilt one — so the
unscoped form cannot be written by accident — a caller that
had not thought about which folder it meant no longer compiles. A job belonging
to another folder is left alone and reported as success, deliberately: there is
nothing of this folder's to turn off, which is the same answer as "there was
never one set".

Paths are compared in **the disk's own spelling — `FolderIdentity.canonicalPath`
since #189 (POSIX `realpath` before it), never Foundation's
`resolvingSymlinksInPath()`** — the same trap the container naming met: the
latter strips `/private`, and two spellings of one folder comparing as
DIFFERENT would scope every job out silently, so nothing would be cancelled or
shown at all.

**A working folder that has MOVED loses its clock and its Cancel item.**
`nextRun` answers nil when the plist's stored path no longer resolves to the
open folder, and the context menu offers "Cancel Deploy at …" only when it does
not. So after a teacher moves their working folder, an existing scheduled deploy
becomes invisible and un-cancellable from the app. Bounded rather than fixed:
the job's own wrapper path moved too, so it cannot deploy anything, and the
lateness check clears it away the next time it tries to fire.

That two working folders shared one alarm at all was a separate fault, closed
by #237 without orphaning the plists teachers already hold — see "One alarm
per working folder (#237)" below.

### What was rejected

**A sweep for jobs whose COURSE no longer exists**, at folder-open and at course
creation. It was in the plan and it is not here. It is the only code in this
piece that DELETES something a teacher set on purpose, and every way it can be
wrong is silent:

- `FileManager.contentsOfDirectory` on an existing-but-EMPTY `courses/`
  succeeds and returns `[]` — a volume that is not mounted, a synced folder
  mid-materialisation — and every plist naming that folder then reads as an
  orphan. That is CLAUDE.md rule 7's lesson verbatim: `docker ps -q` exits 1 and
  prints nothing, and so does a daemon that did not answer.
- A course code recovered from a LABEL is `sanitizedCode` and lossy, and the
  failure direction of a mismatch is "this course does not exist" → cancel.
- What it actually buys, once the lateness check exists, is ONE residue: a
  still-future job whose course was removed BEFORE the teacher upgraded and
  whose code is recreated before its date. That is not worth the family of ways
  it can destroy a live deploy.

The **overdue-only** sweep is kept, and it is provably harmless in a way the
course-absence one is not: a job that far past its moment would stand itself
down the next time it tried to fire, so removing it destroys nothing that could
have run. It is one-sided on purpose — it asks only whether the moment has
PASSED, so a deploy set three weeks ahead is never touched — and it leaves alone
any job with no recorded moment, because the run fails open on one of those.

**"The same calendar day" as the lateness rule** — measured above.

**A fixed twenty-four hour window for everybody** — see "The window is the
teacher's".

**Cancelling inside `CourseArchiver`.** `CourseArchiverTests` and
`CourseRestorerTests` build an **ICS3U** fixture — "a course a teacher plausibly
has" — and set no `launchAgentsDirectoryOverride`, so a cancel inside the
archiver with the real `LaunchControl` as its default would boot out and delete
a real ICS3U schedule on the machine running the suite. The orchestration went
into `ScheduledDeployCleanup` instead, which takes the runner explicitly.
Putting it in `SidebarView.performRemoval` was rejected for the opposite reason:
nothing in the suite constructs that view — every reference to it is to a static
member — so the wiring could not be pinned, and a later edit that dropped the
call would leave the suite green. `LaunchControl.run` now also refuses outright
while the agents override is set, so the rule is structural rather than written
down — and since the same day so does the SCRIPTS folder, which is the half that
claim did not cover: `cancelScheduledDeploy` deletes the wrapper whatever runner
it was handed, and `scriptURL` had no override at all, so the suite really was
deleting `~/Library/Application Support/Plantoir/scheduled/<label>.sh` for the
fixture code. See `documentation/09-mac-app.md`.

**Cancelling on a restore.** Restoring a backup replaces a course's CONTENTS in
place: the course and its sections are still there, its site marker comes back
with it, and the schedule still means what it meant. Restoring an ARCHIVE adds,
and a section restored after its deploy was cancelled comes back with nothing
scheduled, which is the safe direction. Both are pinned as cases in the
contract, by a scan of the file that must not have learned to cancel.

### The one claim no unit test can reach, and how it was measured

`launchAgentsDirectoryOverride` moves where the app WRITES; launchd only ever
reads the real folder, so nothing in the suite can prove that launchd hands
`PLANTOIR_SCHEDULED_FOR` to the process it starts — and the whole lateness check
rests on it. It was measured by hand on 2026-09-20: three real launchd jobs, in
a throwaway working folder inside `$HOME`, under course codes no teacher can
have, with a stand-in wrapper in place of a real Quartz build. The numbers and
what each job proved are in `GUI-IMPROVEMENTS.md`'s row for this change.

---

[◀ Previous: Quartz Customizations](06-quartz-customizations.md) · [Back to index](README.md) · [Next: course_config.json Reference ▶](08-course-config-reference.md)

### One alarm per working folder (#237)

Added 2026-09-25, [issue #237](https://github.com/russellgordon/plantoir/issues/237).
The contract's half is `shared-rules.json → scheduledDeployCancellation →
oneAlarmPerWorkingFolder`, and five cases in that key's `cases` list.

**What was wrong.** A job's label was `…deploy.<CODE>.section<N>` and every
per-job file was named after it — the plist, the wrapper, the log, the success
note, the findings file — and the stopped-run record was `stopped/<course>-
section<N>.txt`. So a teacher with two working folders holding ICS3U section 1
(last year's and this year's, or a restored copy) had ONE alarm between them:
scheduling in B booted out and overwrote A's job, A's sidebar lost its clock
(#236 had scoped it), and B's card named A's moment as "replaced" (#195 read it
Mac-wide on purpose, above).

**The label now ends with the folder's id:**
`ca.russellgordon.Plantoir.deploy.<CODE>.section<N>.<folder id>`
(`ScheduledDeploy.agentLabel(courseCode:sectionNumber:workingFolder:)`, folder
REQUIRED). The id is `BuildOutputLocation.folderIdentifier` — the eight hex
characters the folder's container and builds folder already carry, from
`FolderIdentity.canonicalPath` (#189). **Not a new id**, because a second
derivation of "which folder" is the exact failure #189 closed; two spellings of
one folder give one label. Trailing rather than `deploy.<id>.<CODE>…` so the old
label stays a readable prefix of the new one, `codeAndSection(fromLabel:)`
needs one strip, and `launchctl list` still groups a course's jobs.
`folderID(fromLabel:)` reads the tail — exactly eight lowercase hex characters;
a legacy label's last component always begins `section`, and codes are
upper-cased by `sanitizedCode`, so the two spellings cannot be confused. The
parse table was measured before writing it (a scratch probe compiling the
proposed code) and is pinned by `ScheduledDeployTests.testLabelsAreReadBothWays`:

| label ends | folder id | code, section |
|---|---|---|
| `.ICS3U.section1` (before #237) | none | ICS3U, 1 |
| `.ICS3U.section1.0a1b2c3d` | `0a1b2c3d` | ICS3U, 1 |
| `.ICS3U.section12.12345678` (all-digit id) | `12345678` | ICS3U, 12 |
| `.CODING-CLUB.section2.deadbeef` | `deadbeef` | CODING-CLUB, 2 |
| `.section1.0A1B2C3D` / 7 chars / non-hex | none, and not ours | — |

`plutil -lint` passes a plist with the new label; it is 56 characters for ICS3U.

**The id keeps two folders' files apart; it is NOT how a job is found** (the
plan review's M2, accepted). Every reader — the clock, the card, the cancel,
removal, rename, rollover, the sweep — finds a folder's jobs by the plist's
`WorkingDirectory` through `ScheduledDeploy.agents(inWorkingFolder:courseCode:
sectionNumber:)`, which passes over any file whose NAME names another course or
section before opening it (so the sidebar row reads one or two plists, not
all). Consequences: a job set before #237 is shown, cancelled and replaced with
no special branch; a later change to `canonicalPath` cannot hide a job; and if a
folder somehow holds both an old and a new job for one section (an older copy
of the app still running), the clock shows the EARLIER and Cancel takes both.

**Every file follows, and the record had to.** The wrapper, log and success
note are named by the label. The stopped-run record is
`stopped/<course>-section<N>.<folder id>.txt` (and `.txt.partial` beside the
folder) and the findings file `<old label>.<folder id>.findings`. The record is
not optional: once two folders can each hold ICS3U section 1, both wrappers can
run the same morning, and each begins with `rm -f` of LAST time's record — so a
record named for the course and section alone lets B's run erase A's failure,
and whichever finishes last wears the badge in BOTH sidebars
(`ScheduledPublishOutcomeTests.testTwoFoldersRunsKeepTheirOwnRecord` runs the
two generated wrappers and fails with the id taken out of `recordURL`). The
readers — the sidebar badge, the section's notice and its Dismiss, the
section's findings dialog — compute the id of the folder that is open with the
same `folderIdentifier`. **#212's notification is keyed the same way**
(`scheduled-publish.<CODE>.section<N>.<folder id>`), and for the same race: a
section-only key let one folder's run replace, and its Dismiss withdraw, the
other folder's news.

**The run takes its name from the script it was started with, never a rebuilt
one.** After an update every pending job is still under the OLD label, with its
log and success note baked into its plist and wrapper. `runScheduled` reads
`label(fromScriptPath:)` once and passes it to `logSize(label:)`,
`recordScheduledPublish(label:…)`, `recordFolderProblems(label:…)` and
`bootOutAgent(label:)`; the `(courseCode:sectionNumber:)` boot-out is gone. A
rebuilt label would read an empty log, miss the success note (the section left
" — Edited" after a good publish) and boot out a job that does not exist,
leaving the real one loaded (`testTheRunReadsTheNotesOfTheLabelItWasStartedWith`
runs both spellings). What the run writes ITSELF is filed under the folder's id
either way (`folderIDForRun`: the id in the label, or — for an old job — the id
of the working folder it names): the findings, the stand-down record, and the
record an old wrapper wrote under the old name, which `ScheduledPublishOutcome.
fileUnderTheFolder` moves to the folder's name straight after the run.

**What a teacher set before the update does: nothing changes for them.** The
job is left exactly as it is on disk. It shows its clock in its own folder,
cancels, is removed with its course, is swept when too late, runs correctly,
and deletes its own plist when it fires, so the old spelling drains away.
Scheduling the section again IN ITS FOLDER retires it — `scheduleDeploy` boots
out every job the scan finds for the section, writes the new one, and deletes
the old plist and wrapper only once macOS has ACCEPTED the new job (review M1:
the first plan deleted before the write and promised to re-bootstrap a file it
had just removed). A refusal hands the old job straight back and the trail says
it still stands — naming the job that STANDS; in the rare folder holding both
an old-name and a new-name job (an older copy of the app still running), the
new-name one was overwritten and gets its own "turned off" line
(`testARefusalInAFolderHoldingBothNamesSaysWhichStands`, review L3) (`testARefusedRescheduleHandsTheOldNamedDeployBack`, which fails
with the delete moved before the bootstrap). An old job in ANOTHER folder is
not in the scan and is left standing — that is the fix.

**Rejected, in order of how tempting:**
1. *Re-register old jobs under the new name when a folder opens, keeping the
   moment.* It rewrites a live alarm the teacher set and never touched, through
   the boot-out-then-write sequence whose failure #195 found loses the job; it
   needs the course's CURRENT destinations and Cloudflare account to regenerate
   the wrapper, so it would change what an already-promised deploy does, not
   only its name (since #323 every run reads the destinations as they are when
   it fires, so THIS reason no longer applies; the first and third still do);
   and a pre-v1.2.0 plist carries no `PLANTOIR_SCHEDULED_FOR`,
   so "the moment kept" would mean inventing a year. All to rename a file that
   expires by itself.
2. *Rename in place* (rewrite `Label`, move plist/script/log, edit the
   wrapper's baked paths). Four files per job must move together under a launchd
   that has the job loaded by its old label; a half-done rename is a job nobody
   can find.
3. *Not recognising old jobs.* An updated teacher's clock vanishes and Cancel
   stops working for a job that WILL still fire — #236's "invisible and
   un-cancellable", reintroduced by an update.
4. *Keep reading an old-style record in every folder* (the plan's first
   answer). In the mixed case — an old job in A, a new one in B — A's failure
   shows in B's badge and B's Dismiss deletes it (review L2; the ruling: never).
   Such a record is read by NO folder; the run of an old job files its own
   record under its folder instead.

**When the folder cannot be opened** (review M2: "deterministic, and the same at
scheduling and reading time"): the id is `folderIdentifier` both times — the
disk's own spelling, falling back to `realpath` and then to the path as written.
At scheduling the folder always opens (its `deploy.sh` is checked first), and
jobs are found by working folder rather than by id, so the fallback can reach
only the record and findings names, the same way both times
(`testAFolderThatCannotBeOpenedGetsTheSameIdEveryTime`).

**The trail is unchanged, on purpose.** No new event: scheduling in B now leaves
A's alarm alone, so silence is correct; retiring THIS folder's old job is a
replacement and writes the existing `scheduled deploy replaced` line (its `why`
in `mustRecord` and the comment on `ActivityTrail.Event.scheduledDeployReplaced`
now say "one per section per working folder"). **Known limits:** trail lines
carry course and section, not the folder, so two folders' ICS3U section 1 lines
read alike — naming a folder on the trail is a `LogRedactor` question larger
than this; and a record or findings file written under the old name BEFORE the
update, never filed by a later run, is shown in no folder (its trail line was
written when it ran).

**The real launchd accepts the shape — measured once, by hand, not by the
suite.** On 2026-09-25 (this Mac, macOS 26, Apple silicon) a throwaway agent
`ca.russellgordon.claude-probe237.ICS3U.section1.0a1b2c3d` — outside our
`labelPrefix`, so no Plantoir ever reads it — running `/usr/bin/true` on 29
February: `plutil -lint` OK, `launchctl bootstrap` exit 0, `launchctl print`
listed it, `bootout` exit 0, plist deleted, `print` afterwards exit 113 (gone).
No teacher's job was touched. Every test uses `FakeLaunchControl` and throwaway
agents folders.

### Where it deploys is read when it runs (#323)

**What was wrong, measured.** Found while planning #322. A throwaway test
scheduled ICS3U section 1 to Netlify through the real `scheduleDeploy`, then
rewrote `course_config.json` to a folder as Course Settings' Save does, then
read back what launchd would run. The PLIST never carried the destination (its
`ProgramArguments` are the app, the run flag, the wrapper path, the section flag,
the working folder, the code and the section — which corrects the issue); the
WRAPPER did. After the Save it still read
`/bin/bash '…/deploy.sh' 'ICS3U' '1' '--non-interactive'`: a publish to the old
place at half six, reported as `succeeded`.

**Reading the destination is not enough on its own, and this is the trap.** A
course switched to a Cloudflare Pages destination never deployed to would, if
the run only re-read the destination, publish successfully to a project named by
guesswork: `publish_to_cloudflare` (`scripts/deploy.py`) contains no
`refuse_to_ask`, discovers a missing account from the token, suggests the name
deterministically and creates the project. So the run re-applies everything the
schedule sheet refuses except a time already passed — one function,
`ScheduledDeploy.destinationRefusal`, asked at scheduling (`problem()`), at the
run and after a Save.

**What the run does now** (`runScheduled`, in this order):

1. The lateness window (unchanged) — a job too late stands down `tooLateToRun`
   whatever its settings say.
2. The wait for the course (#156) — so a Save made while it waited counts.
3. **The settings** (`readAtTheRun`): the course folder is found the way the
   lateness window finds it, `course_config.json` is read, `destinationRefusal`
   asked, and the wrapper built from `deployPlan` — the SAME function scheduling
   uses, so an unchanged course gets a byte-identical wrapper
   (`testAnUnchangedCourseGetsTheSameWrapperItWasScheduledWith`).
4. **Does the job still stand?** (`jobStillStands`, the plan review's M1). Its
   plist must still exist and still carry this run's `PLANTOIR_SCHEDULED_FOR`.
   Before #323 a cancelled job's deleted wrapper was what stopped a run that
   outlived its cancellation; a run that writes its wrapper afresh would bring
   the cancelled deploy back. If the job no longer stands the run releases its
   leases and leaves — no record, no notification, and no boot-out (a job
   scheduled again under the same name must not be booted out).
5. **The write** (`writeTheRunsWrapper`): over the job's OWN wrapper, and only
   if it is still there (a cancel deletes the wrapper before the plist). The
   permissions are not a condition — the run starts `/bin/bash <wrapper>`.
6. **The decision** (`whatTheRunDoes`, pure and tested): the ONLY way to run is
   a wrapper just written from the settings; a failed write stands down with
   its own true reason, never "could not read the settings" (review M2).
7. For a job set before #237, the record under the old folder-less name is
   removed before the run (`clearTheOldNamedRecord`, review H1): that job's own
   wrapper used to clear it first, and without it `fileUnderTheFolder` would
   move LAST week's record over tonight's — a failed run announced as last
   week's success. Must-fail: `testAnOldJobsRunIsNotReportedAsLastWeeksSuccess`.

**Standing down.** A refusal releases the leases FIRST (`standDown` never
returns, and until #323 it was only reached holding none), then records the new
kind `couldNotRunAsSetNow` with the REASON as the record's second line — a
clause true at the run (`ScheduledDeployRefusal.reasonClause`), which the
sentence shows as `{reason}`. The sheet's own sentences stay for the sheet: their
remedies ("then schedule this again", "it would wait") are false at the run and
at a Save (review M3). Settings that cannot be read stand down too — the
opposite of the lateness window's default, because a destination has no safe
default.

**What the job keeps.** The plist is unchanged but for ONE note,
`PLANTOIR_SCHEDULED_TO`: the destinations' descriptions the teacher was told,
as a JSON array. It is never read to decide
(`testWhereItWasScheduledIsNeverUsedToDecide`); it lets the trail say when the
run went somewhere else. (`propertyList`'s unused `deployArguments:` parameter
went.) The wrapper is still written complete at scheduling, so the job on disk
runs on its own under an older copy of the app.

**Jobs already on disk.** Every plist since v1.2.0 runs the app, so they follow
the rule at their next run. One set before #323 recorded nothing to compare
with, so no "went somewhere else" line; one set before #237 keeps its old name
for its plist, log and success note, and files its record under the folder's
id; a plist from before v1.2.0 names no section and runs its wrapper as
written — the one stale path left, effectively extinct. A regenerated wrapper
also carries any fix made to the wrapper since the job was set, which is
intended.

**The trail.** New event `scheduled publish read the course's settings`
(mustRecord), written ONLY when something differs from what the teacher was
told: shape A, "a scheduled publish was set to deploy to Netlify; the course
deploys to /Users/…/Sites now, so it is deploying there"; shape B, "a scheduled
publish could not deploy the way the course is set now (…reason…)", plus where
it was set to go and where the course deploys now when those differ. The
stand-down's generic `scheduled deploy turned off` line follows it, the
`courseWasBusy` precedent. Named "read" rather than "followed" because it also
carries the runs that stood down (review L3). **Known, accepted (review L2):**
the `scheduled publish waited … then went ahead` line is written when the wait
ends, before the settings are read, so a run that waited and then stood down
over its settings shows "went ahead" followed by the stand-down line.

**Said at Save, while somebody is awake** (Chunk B). After a Save in Course
Settings, for each section with a deploy set to happen on its own in THIS working
folder and still to come: `specialNames.settingsSaveScheduledDeployCannotGoAheadAsSetNow`
when it could not go ahead as set now (changed or not), else
`…GoesWhereTheCourseDeploysNow` when the Save changed where the course deploys
(the file before the Save against what it wrote — never against
`PLANTOIR_SCHEDULED_TO`, which would repeat the sentence on every later Save).
Nothing is refused or undone. Appended before the "saved while publishing" early
return; the `settings saved` trail line carries the same facts
(`SettingsSaveNotice.scheduledDeploys`, not parsed back out of the sentences).
Contract: `savingSettings.scheduledDeploys`.

**The one claim no unit test reaches, measured (review M6).** The run reads the
Cloudflare Account ID from the app's own settings. That a launchd-started run
reads the same defaults domain as the app was measured on 2026-09-26, Apple M4
Pro, macOS 26.6: a scratch build of this branch, signed by the same team
(`ca.russellgordon.Plantoir`, C7DL9Y9A7R), with a TEMPORARY flag that printed
presence only — never a value — was run once from Terminal and once as a launchd
job labelled `ca.russellgordon.probe323.<uuid>` (outside the deploy prefix, so no
sweep or badge could see it), bootstrapped from a plist in the session's scratch
folder, then booted out and confirmed gone (`launchctl print` exit 113). Both
printed `bundle=ca.russellgordon.Plantoir accountIDPresent=true domainKeys=75`.
The app is not sandboxed, and `--mcp-stdio` already read the same setting when
launched by another program.

**Known, not covered (review L1).** A changed Cloudflare Account ID is not
refused at the run: "deployed before" is kept per destination TYPE, not per
account, so a swap to another valid ID deploys to a new project in the new
account and reports success. Attended deploys behave the same; before #323 the
baked ID kept the old account.

**Rejected** (with reasons in `scheduledDeployCancellation.theDestination.rejected`):
re-registering the job at Save (reaches only the app's Save, puts #195's
boot-out-then-write behind a settings button); reading the destination without
the refusals (the Cloudflare fail-open); teaching the launchers to read the
destination (a launcher-contract change Windows shares, and a second reader of
the rules); the arguments in the plist (the same staleness elsewhere); parsing
the old wrapper; falling back to the scheduled wrapper when settings cannot be
read (the fault itself); a temporary wrapper file (everything finds the job by
its wrapper's path); warning at Save alone.

**Windows** has the same fault — `TaskScheduling.WriteWrapperScript` bakes the
destinations and the Account ID into the `.ps1`, and Task Scheduler runs
PowerShell with no app alive — and owes `theDestination`, the kind, the event and
the two Save sentences. How is theirs; the mac's shape (the task launches
`Plantoir.exe --run-scheduled-deploy`) is the likely best.


# 2. The Docker Image

[◀ Previous: Overview](01-overview.md) · [Back to index](README.md) · [Next: Launcher Scripts ▶](03-launcher-scripts.md)

The image is the entire runtime environment, and it is **built locally on
each machine** from the [`Dockerfile`](../Dockerfile) — no registry of ours
is involved. A working folder carries the build recipe in `.toolchain/`
(kept current by the macOS app); a repository copy IS the recipe. The image
tag is `teaching-quartz:src-<hash8>` where the hash covers ONLY the
recipe's files (the `find` prunes `.git`, `courses`, `mac-app`,
`node_modules`, `.merged_output`, and `.verify-export.*`, and skips
`.DS_Store` — so build outputs never steer the tag), so an updated recipe
produces a new tag, the launcher builds it,
and the container is recreated to match — the whole chain keyed off one
thing: the version of the app.

What a build still fetches from the network, the first time: the
`python:3.11-slim` base image, apt and NodeSource packages, the pinned
Quartz v4.5.0 clone from GitHub, and npm dependencies. After that the build
is cached and everything runs offline.

**Measured on a first run (GitHub #312, 2026-09-26, M4 Pro, ~320 Mbit/s):**
about **390 MB** received (the virtual machine's own network counter,
389,826,558 bytes), and **88 s and 137 s** on two cold builds in a fresh
3-CPU / 4 GB virtual machine; **63 s and 440,803,331 bytes** at the #312
rehearsal in a fresh 6-CPU / 12 GB one. Since #312 the Mac app carries the helper
programs and the virtual machine's starting disk, so this build is the only
large download left on a first run, and the largest stage by far; the
launchers say "about 400 MB" only when no website builder has been built on
the Mac before (`documentation/03-launcher-scripts.md` → "Where the helper
programs come from"). Trimming it — the base image, `apt`'s Node.js and fonts,
wrangler, Quartz's `npm install` — is a follow-up of its own.

## Anatomy of the Dockerfile

The image is layered as follows (in order):

1. **Base: `python:3.11-slim`, pinned by digest** — Debian slim with Python
   3.11. Python is needed for the four orchestration scripts; 3.11 also
   provides `zoneinfo` for timezone-correct timestamps.

   **Pinned by its multi-architecture index digest since bundle B
   (2026-09-26, #334's follow-on).** The tag alone moves: teachers who built
   at different times held different Debian and Python patch releases, and a
   build could change under a teacher with no change to the recipe. The
   digest is `sha256:90744cff…` — the one every build on this Mac had resolved
   since 2026-08-05 (Python 3.11.15, Debian 13 "trixie") — so a Mac that
   already has it downloads nothing new, and BuildKit keys the base layer on
   the resolved digest, not on the line's text. The tag had moved on by the
   day it was pinned (`sha256:e41613…`). **The cost:** security fixes to the
   base arrive only when somebody bumps the line on purpose —
   `docker buildx imagetools inspect python:3.11-slim` names the current
   index digest; bump it, run `verify.sh`, and expect every teacher to pay
   one full rebuild (a new base invalidates every layer above it).
2. **`pip install python-frontmatter==1.3.0 PyYAML==6.0.3 Pillow==12.3.0`** —
   the Python dependencies, all three PINNED since 2026-09-18 (issue #140) at
   the versions the image already carried, so the pin changed nothing about
   what is installed. `python-frontmatter` parses and rewrites the YAML
   frontmatter block at the top of each Markdown file (used heavily for the
   per-section `publish`/`created` machinery); Pillow draws each section's
   social sharing card.

   **PyYAML is named explicitly even though python-frontmatter pulls it in,
   and that is the point of the pin.** python-frontmatter parses with PyYAML,
   which implements YAML **1.1** — and that is the only reason `publish: no`
   and `publish: off` hide a page rather than being the strings "no" and
   "off". PyYAML 7 is expected to move to YAML 1.2, where those pages would be
   PUBLISHED, silently, in courses already in front of students.
   `contracts/file-formats.json` → `pageVisibility` states the 1.1 table as
   fact and both apps are written against it, so an unpinned upgrade would
   fail nothing anywhere. The reasoning is in
   [08 → Whether students see a page](08-course-config-reference.md#whether-students-see-a-page),
   and the pins are in `contracts/toolchain.json` → `pins`. **The same three
   are pinned in `windows-app/Vendor/fetch-runtime.ps1`** (since 2026-09-19),
   which builds the runtime that really produces a Windows teacher's site —
   nothing on that machine builds this image. Each pin names both files it
   must appear in (`dockerfileContains`, `windowsRuntimeContains`) and a test
   on each platform holds its own file against them, so a pin raised in one
   place cannot quietly stay put in the other.
3. **Node.js 20 + tools** — installed from NodeSource. Quartz is a Node
   program (`npx quartz build`). Also installed: `curl`, `git` (needed to
   clone Quartz), `lsof` (used to kill a previous preview server holding
   the requested port, 8081–8084), `dos2unix`/`unix2dos` (line-ending
   conversion, below), `fonts-noto-color-emoji` (the colour emoji
   drawn onto social sharing cards), and `rsync` (used for fast differential
   mirroring of the built `public/` directory back to the host mount).
4. **`npm install -g wrangler@4.80.0`** — Cloudflare's own deploy CLI,
   used by `deploy.py` when a course publishes to Cloudflare Pages (see
   [deployment](07-deployment.md)). It is pinned, and pinned **below
   4.100** deliberately: from that version wrangler requires Node 22, and
   this image ships Node 20 because that is the version Quartz v4.5.0 is
   known-good against. If Node is ever raised, revalidate Quartz *before*
   chasing a newer CLI. The pin also keeps the image reproducible and stops
   an upstream CLI change from breaking a teacher's publishing mid-term.
   Note this adds an npm-registry dependency to the image build, alongside
   the Debian and GitHub sources.
5. **Clone Quartz v4.5.0, at depth 1, & pre-bake dependencies → `/opt/quartz`** — a pinned checkout:
   ```dockerfile
   RUN git clone --depth 1 --branch v4.5.0 https://github.com/jackyzha0/quartz.git quartz
   RUN cd /opt/quartz && npm install --no-audit && npm cache clean --force
   ```
   **Depth 1 since #334 (2026-09-26):** the tag's one commit rather than
   Quartz's whole history — 2.3 MB received against 42.0 MB, measured per
   container on an M4 Pro. Nothing reads the history: `build_site.py` already
   takes `"git"` out of `CreatedModifiedDate`'s priority, and a one-commit
   clone is still a repository. It also matters on the way OUT: the
   scaffold, `.git` included, is copied into every section's output folder at
   its first build and at `--full-rebuild`, so every section now stages
   38 MB less. `verify.sh` checks `git rev-list --count HEAD` is 1.
   Pinning matters because most customizations are regex patches that target
   the exact source text of this version
   (see [Quartz Customizations](06-quartz-customizations.md)). Pre-installing
   dependencies inside the image ensures that `/opt/quartz/node_modules` is
   baked into the image layers, completely eliminating the need to run `npm install`
   across slow host filesystem mounts (9P on WSL2 or virtiofs on macOS) when
   setting up or building course sections.
6. **Overwrite five Quartz source files with patched versions** from
   [`patches/`](../patches/) — three components and two filter files:
   - `patches/Explorer.tsx` → `quartz/components/Explorer.tsx`
   - `patches/FolderContent.tsx` → `quartz/components/pages/FolderContent.tsx`
   - `patches/explorer.inline.ts` → `quartz/components/scripts/explorer.inline.ts`
   - `patches/publish.ts` → `quartz/plugins/filters/publish.ts` — the
     `PublishFlag` filter that replaces Quartz's `RemoveDrafts`
   - `patches/filters-index.ts` → `quartz/plugins/filters/index.ts`, which
     exports it

   These three are replaced wholesale (rather than patched at build time)
   because their changes are structural — new imports, reordered rendering
   logic — and would be fragile to express as regex edits. They implement the
   *expandable vs. plain-link folder* behaviour in the sidebar; the details
   are in [customizations §A](06-quartz-customizations.md#a-components-replaced-at-image-build-time).
7. **Copy the Python scripts** into `/opt/scripts/` — eleven of them as of
   2026-09-18: `toolchain_paths.py`, `contracts.py`, `site_health.py`,
   `class_pages.py`, `page_visibility.py`, `stop_preview.py`,
   `setup_course.py`, `build_site.py`, `deploy.py`, `social_card.py` and
   `netlify_badge.py`. **Count them off the Dockerfile rather than trusting
   this sentence** — it said "nine … as of 2026-09-05" while the recipe copied
   ten, `stop_preview.py` having been added without the list following it.

   **They are copied ONE BY ONE, by name, and that is a trap worth knowing.**
   Splitting a rule out into a new sibling module is therefore a change to the
   Dockerfile whether or not anybody remembers it is: the baked scripts import
   their siblings by bare name, which resolves only if the file is sitting
   beside them. When `class_pages.py` was added and not copied, the image
   could not be BUILT at all — the Dockerfile imports `setup_course` during
   the build to bake the Explorer's hide filter, so the failure was not a
   run-time surprise for one teacher, it was a hard failure of the build that
   produces the toolchain. Every unit test was green throughout.

   `scripts/test_baked_modules.py` now walks the imports of every baked script
   with `ast` and fails if one is missing. `verify.sh` runs it BEFORE the image
   build, because it answers in a tenth of a second what the build answers in
   three minutes.
8. **Copy `support/` → `/opt/support/`** — data files consumed by the
   scripts:
   - `ontario_secondary_courses.json` — 1,930 Ontario course codes mapped to
     formal and short names, so the wizard can auto-fill "ICS3U →
     Introduction to Computer Science, Grade 11".
   - `colour_schemes.json` — 43 named colour schemes (a Quartz default, a
     dozen designed palettes, and one per MLB team), each defining the nine
     Quartz theme colours for light and dark mode.
   - `locales/` — all 27 Quartz locale files with teacher-oriented wording
     (see [customizations §D](06-quartz-customizations.md#d-locale-files-replaced-at-build-time)).
   - `Backlinks.tsx` — a patched Backlinks component installed at build time.
   - `favicon/` — the four files a built site wears in the browser tab
     (`icon.svg`, `favicon.ico`, `apple-touch-icon.png`, `icon.png`), drawn
     from the app icon by `scripts/brand_images.py` and installed by
     `build_site.py`
     (see [customizations C2-25](06-quartz-customizations.md#c2-applied-on-every-build)).
   - `fonts/` — the eighteen bundled site fonts (`.ttf`) plus their
     licences. This is the SINGLE font source: the container draws social
     cards with the same files the macOS app bundles for its settings
     previews (font display name → file by stripping spaces, e.g.
     "Playfair Display" → `PlayfairDisplay.ttf`).
   - `obsidian_defaults/.obsidian/` — Obsidian vault settings seeded into new
     courses (e.g. `attachmentFolderPath: "Media"` so pasted screenshots land
     in the shared Media folder, and a `workspace.json` with the File
     Explorer's auto-reveal turned on).
   - `example_course/EXC2O/` — the complete example course installable from
     the setup wizard (it, too, receives the `.obsidian` defaults on
     install).
   - `example_content/<CODE>/` — ready-made course content for 39 course
     codes (count the folders rather than trusting the number), poured into
     a new course of that code
     ([course setup §0b](04-course-setup.md#0b-starting-content-for-the-course-code)).
   - `skeletons/<family>/` plus `families.json` — the starting shape for
     EVERY course code, and what a course gets whenever its teacher is not
     taking the ready-made content: fifty subject families mapped from the code's
     three-letter prefix. Generated output; the generator and its linter
     live in `.claude/skills/example-content/`.

   Together these are most of the recipe's file count (11,378 files as of
   August 2026), which is why the launchers' image-tag hash has to batch
   its work — see [launcher scripts](03-launcher-scripts.md).
9. **Bake the launcher scripts into `/opt/export/`** and register an
   `export-scripts` command:
   ```bash
   docker run --rm -v "$PWD:/out" teaching-quartz:src-<hash8> export-scripts
   ```
   copies `setup/preview/deploy` in all three flavours (`.sh`, `.bat`, `.ps1`)
   into the current folder. Teachers normally receive launchers via the
   app's `.toolchain/` mirror; this remains an escape hatch, and
   `verify.sh` checks the baked copies match the working tree. During the image build, `unix2dos`
   converts the `.bat` and `.ps1` files to CRLF line endings — `cmd.exe` can
   misparse LF-only batch files, and the repo itself stores everything with
   LF.
10. **Default state**: working directory `/teaching`, command `/bin/bash`.

**Gone since #334: `cp -r /opt/quartz /opt/quartz-site`**, which used to be
step 7 — a spare copy of the scaffold that nothing read (the build copies
from `/opt/quartz`), kept in step by a `cp` on the end of the line that bakes
the Explorer's hide filter. It was 468 MB of image disk per image version,
and during an update two versions sit side by side for a day. `verify.sh`
now checks it is absent.

### What the first build downloads (measured for #334)

Per container (`/sys/class/net/eth0/statistics/rx_bytes` inside each
`docker run`, because another build shared the VM during part of the
measurement), on an M4 Pro with Colima at 6 CPUs / 12 GiB, 2026-09-26:

| Stage, in Dockerfile order | Received | Notes |
|---|---|---|
| base `python:3.11-slim` | ~46 MB | a fresh VM only |
| `pip install` (three pins) | 7.7 MB | |
| `apt-get` (curl, git, lsof, dos2unix, emoji font, rsync, nodesource, nodejs) | 92.8 MB | `--no-install-recommends` would save 4.3 MB — rejected, below |
| `npm install -g wrangler@4.80.0` | 65.1 MB | |
| `git clone` of Quartz | 42.0 MB → **2.3 MB** at depth 1 | |
| Quartz's `npm install` | 128.0 MB | the largest |
| **Total** | **≈382 MB → ≈342 MB** | #312's VM counter read 389.8 MB in a fresh VM |

Time here: 49–52 s cold with the base cached; an incremental rebuild after a
script edit is 5 s, every heavy layer `CACHED`. A teacher's fresh 3-CPU / 4 GB
VM is slower (#312 measured 88–137 s). On the VM's disk the image went from
2.44 GB to 1.67 GB with the trims built together.

**What an existing teacher pays once.** The pip, apt and wrangler lines were
left byte-identical, because layer caching is by instruction: the first
build after the update re-runs the clone, Quartz's `npm install` and
everything after them — about 130 MB — and nothing above.

**Measured and rejected** (so they are not proposed again):
`--no-install-recommends` on both apt lines (−4.3 MB, but it changes the apt
line's text, so every existing teacher would re-download apt, wrangler, the
clone and npm — about 330 MB — once, to save a new teacher 1%; it also drops
recommends nobody has audited: git's `less`, `openssh-client`, `patch`);
`npm install --libc=glibc` (0 bytes: npm 10.8.2 ignores it for sass and
sharp); `npm install --omit=dev` (Quartz's CLI needs `esbuild`, `tsx` and
`typescript`, which are dev dependencies); skipping wrangler until a first
Cloudflare publish (−65 MB, but it moves a download onto the publishing path
at the moment a teacher publishes — a publishing change, not a trim); a
smaller base such as `node:20-bookworm-slim` with Debian's Python (it changes
the Python a teacher's settings are read with — the PyYAML pin exists because
visibility depends on it); BuildKit cache mounts (a first build gains
nothing, and later rebuilds already hit the layer cache); and a pre-built
layer tarball in the DMG (Russell's #312 decision: build on the Mac).

Since bundle B the app does this download in the BACKGROUND at first launch
(`setup.sh --prepare-builder`, [03](03-launcher-scripts.md) and
[09](09-mac-app.md)), so the teacher is usually in the wizard while it
happens rather than watching "Building your website builder…".
    The launchers start the container with `tail -f /dev/null` so it idles
    indefinitely, and every operation is a `docker exec` into it.

## What is *not* in the image

- **Course content.** The host `courses/` folder is bind-mounted at
  `/teaching/courses` at run time; the container is stateless apart from it.
- **Quartz's npm dependencies.** `node_modules` is installed per section
  output folder on first build (and cached thereafter). This keeps the image
  smaller and lets each section pin its own dependency tree.
- **Secrets.** Publishing tokens — Netlify's, and Cloudflare's under its own
  separate entry — live in the host's keychain (Windows: Credential Manager)
  and are injected per invocation, never written into the image or the
  working folder (see [Deployment](07-deployment.md)).

## Building the image

The launchers build the image when the expected tag is missing, with
BuildKit (`docker buildx build --load`) — the legacy builder silently
mangles the `export-scripts` layer. `verify.sh` exercises exactly this
build against a `dev-test` tag and remains the gate for toolchain changes
(it needs a TTY, and it also cross-checks that every helper function a
launcher calls is defined in that same launcher file).
The `--image REF` flag on each launcher substitutes a specific already-built
image, which is how `verify.sh` drives the launchers against its own build.

Historical note: the image was previously published to Docker Hub by a
`publish.sh` script and pulled by teachers, with digest-comparison update
checks. That whole apparatus — and its staleness problems — is gone; the
recipe travels with the app instead.

## Docker images used to leak forever

Recorded here because the finding sounds like it must apply to both sides, and
it does not. On the mac, the builder image is tagged
`teaching-quartz:src-<hash of the build recipe>`, so every recipe change mints
a new tag and orphans the previous one. Nothing in the repository had ever
removed one: 139 images and 50 GB on this dev machine, ~115 of them
`teaching-quartz` tags. Containers were never the problem — each launcher
already removes its own container before recreating it (since #94 by its id,
and only once nothing whose owner is still running is at work in it — work
left behind by a program that has closed is ended with it since #378; 03 →
"Before a workspace is remade"), and the name is a hash of the working folder, so it is one container
per folder replaced in place.

The mac fix is `prune_superseded_images()` in `setup.sh`, `preview.sh` and
`deploy.sh`: after a build SUCCEEDS, remove every `teaching-quartz:src-*` tag
except the one just built, skipping any a container still references. It keeps
exactly one tag; the "keep the previous one for a cheap downgrade" idea was
rejected because an older Plantoir carries its own bundled recipe and rebuilds
its tag regardless. `docker builder prune` was rejected outright: it is global
with no per-project filter, and this machine's Docker is shared with other
projects.

Three guards on it, each of which an adversarial review found MISSING in the
first version — worth having in writing, because all three look like
over-caution until you see the case:

- **Do nothing unless the tag just built is one of ours.** `--image` lets a
  caller point the image at anything, and "remove everything except the tag I
  was given" then means "remove every real tag on the machine, including every
  other working folder's current one".
- **Do nothing to an image younger than about a day.** The container check is
  a point-in-time read, and a folder that is mid-recreate — container removed,
  replacement not yet started — references nothing for a second or two. A
  build finishing in another folder inside that window would delete the image
  it is about to run, and the teacher would see a registry-pull failure for an
  image that exists on no registry. The same guard stops two folders on
  different recipes from deleting each other's image on every switch.
- **Ask Docker for the age, never compute it.** `docker image inspect
  '{{.Created}}'` returns LOCAL time with an offset, not the UTC `Z` it
  resembles, so comparing it against a UTC cutoff is silently wrong by the
  machine's offset. `{{.CreatedSince}}` from `docker images` is Docker's own
  human age string and has no timezone in it at all.

One correction to the paragraph above, for honesty: **containers are cleaned
up per working folder, but nothing cleans up a DELETED working folder's
container.** That orphan now permanently pins its image against this cleanup —
the one image that can never be reclaimed is the one nobody will ever use
again. Small (an orphan per deleted folder, and a teacher deletes none), noted
so the write-up is not read as "container hygiene is solved".

**A second measurement, 2026-09-08, on how much the sweep actually reclaims.**
Nine `teaching-quartz:src-*` images on disk (about 2.42 GB each) against **two**
containers, so eight were unreferenced. The sweep works; it is simply narrow by
construction. It runs only on the SUCCESS branch of a build — `build_image_if_missing`
in `setup.sh` and `preview.sh`, `ensure_image_present` in `deploy.sh` — so a run
that finds its image already present touches nothing, and superseded tags wait
for the next recipe change. The age guard above then spares anything younger
than a day or two, which is why a machine in the middle of toolchain work is
exactly where several survive each sweep. Add the orphan-container case in the
paragraph above and nine against two is what you would expect rather than a
fault.

If that count climbs well past nine on a machine that is NOT mid-toolchain-work,
that is the signal to open an issue — with a number, since this paragraph is the
baseline. Deliberately no remedy proposed here: giving the sweep a second
trigger has hazards of its own, and the success-branch placement is what keeps a
run that reuses an image from touching anything.

**Windows has nothing to port.** You dropped Docker on 2026-08-19 for the
native runtime — no image, no tag, no container, nothing to accumulate. (An
earlier `TODO-TODAY.md` note on the mac claimed "their launchers have the same
gap"; that was written without checking the `.ps1` files and is wrong.) Do not
add a cleanup for images that do not exist.

**The question worth asking on that side is the analogous one, not the same
one:** when a teacher installs a new Plantoir, is a superseded
`Vendor/runtime/` — or an old model download under `%LOCALAPPDATA%` — left
behind anywhere it can accumulate across a school year? That is the shape of
the failure the mac hit: a disk filling with something the teacher has never
heard of and cannot connect to this app. Nobody here can see a Windows
machine to answer it, so it is a question rather than a finding.

## The build cache is never cleared, on purpose

Separate from the images above, and easy to conflate with them: BuildKit keeps
its own build cache, nothing in this repository clears it, and nothing should.

**`docker builder prune` is GLOBAL.** There is no per-project and no per-tag
filter, so a launcher that called it would throw away the build cache of every
other project sharing this Colima VM — Supabase's, among others. That is the
same constraint that shaped the image cleanup one section up, except that there
the narrow form exists (remove `teaching-quartz:src-*` except the tag just
built) and here it does not. So clearing the cache stays a by-hand developer
job:

```bash
docker builder prune          # global — read the size it offers before agreeing
```

**A teacher's cache is nothing like a developer's.** The 14 GB in the table below
came from twelve days of toolchain edits, each minting a new recipe hash. A
teacher builds the image on install and then does not build again until a
Plantoir update changes the recipe.

**Measured twice on the dev mac**, sixteen days apart:

| | Build cache | Images |
|---|---|---|
| 2026-08-23 | 1301 entries, 14.30 GB, 14.25 GB reclaimable | 139 images, 50.09 GB — before that day's cleanup landed |
| 2026-09-08 | 632 entries, 4.81 GB, 2.56 GB reclaimable | 37 images, 31.22 GB, **12.39 GB reclaimable** |

The 2026-08-23 note that this migrated from said the cache was "a bigger number
than the images that were leaking beside it". **It was not, and the same page
disproves it** — the images section above records 139 images and 50.09 GB that
day against the cache's 14.30 GB. The claim is repeated here only so that
nobody re-derives it from the old wording and acts on it. What the second
measurement does show is that the cache fell to a third of itself unaided,
while the images stayed the larger reclaimable number throughout.

**None of which touches the decision**, and that is the point worth keeping: it
never rested on the size. It rests on `prune` having no narrow form.

**If this is ever revisited, the thing to find out first** is whether BuildKit
can be given a scoped cache per build context — a filtered prune rather than a
bigger hammer. Reaching for the global command because the number looks large
is the move this note exists to prevent.

**Windows has nothing to port here either**, for the reason the images section
gives: no Docker, no BuildKit, no cache.

---

[◀ Previous: Overview](01-overview.md) · [Back to index](README.md) · [Next: Launcher Scripts ▶](03-launcher-scripts.md)

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

## Anatomy of the Dockerfile

The image is layered as follows (in order):

1. **Base: `python:3.11-slim`** — Debian slim with Python 3.11. Python is
   needed for the four orchestration scripts; 3.11 also provides `zoneinfo`
   for timezone-correct timestamps.
2. **`pip install python-frontmatter Pillow`** — the two Python
   dependencies. `python-frontmatter` parses and rewrites the YAML
   frontmatter block at the top of each Markdown file (used heavily for the
   per-section `publish`/`created` machinery); Pillow draws each section's
   social sharing card.
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
5. **Clone Quartz v4.5.0 & pre-bake dependencies → `/opt/quartz`** — a pinned checkout:
   ```dockerfile
   RUN git clone --branch v4.5.0 https://github.com/jackyzha0/quartz.git quartz \
       && cd quartz && npm install --no-audit && npm cache clean --force
   ```
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
7. **`cp -r /opt/quartz /opt/quartz-site`** — a spare copy of the scaffold
   (not used by the current build path, which copies from `/opt/quartz`
   directly).
8. **Copy the Python scripts** into `/opt/scripts/` — nine of them as of
   2026-09-05: `toolchain_paths.py`, `contracts.py`, `site_health.py`,
   `class_pages.py`, `setup_course.py`, `build_site.py`, `deploy.py`,
   `social_card.py` and `netlify_badge.py`.

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
9. **Copy `support/` → `/opt/support/`** — data files consumed by the
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
   - `example_content/<CODE>/` — ready-made course content for thirty-seven
     Ontario course codes, poured into a new course of that code
     ([course setup §0b](04-course-setup.md#0b-starting-content-for-the-course-code)).
   - `skeletons/<family>/` plus `families.json` — the starting shape for
     every OTHER course code: fifty subject families mapped from the code's
     three-letter prefix. Generated output; the generator and its linter
     live in `.claude/skills/example-content/`.

   Together these are most of the recipe's file count (11,378 files as of
   August 2026), which is why the launchers' image-tag hash has to batch
   its work — see [launcher scripts](03-launcher-scripts.md).
10. **Bake the launcher scripts into `/opt/export/`** and register an
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
11. **Default state**: working directory `/teaching`, command `/bin/bash`.
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
already removes its own container by name before recreating it, and the name
is a hash of the working folder, so it is one container per folder replaced in
place.

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

---

[◀ Previous: Overview](01-overview.md) · [Back to index](README.md) · [Next: Launcher Scripts ▶](03-launcher-scripts.md)

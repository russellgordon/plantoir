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
   packages the BASE ITSELF installed arrive only when somebody bumps the
   line on purpose — `docker buildx imagetools inspect python:3.11-slim`
   names the current index digest; bump it, run `verify.sh`, and expect every
   teacher to pay one full rebuild (a new base invalidates every layer above
   it). A package an apt line below NAMES comes from Debian's live
   `trixie-security` instead (it is in the base's sources), but only when that
   line's layer is rebuilt, which on a Mac that has built before it never is.
   The certificate store could not wait for either, so it has a late layer of
   its own (item 6 below, and
   [The certificate store](#the-certificate-store-639-v190)).
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
3. **Node.js 22.23.4, pinned exactly, + tools** — installed from NodeSource
   (`setup_22.x`, then `nodejs=22.23.4-1nodesource1`; Node 20 until #640,
   see "Node 22 (#640)" below). Quartz is a Node
   program (`npx quartz build`). Also installed: `curl`, `git` (needed to
   clone Quartz), `lsof` (used to kill a previous preview server holding
   the requested port, 8081–8084), `dos2unix`/`unix2dos` (line-ending
   conversion, below), `fonts-noto-color-emoji` (the colour emoji
   drawn onto social sharing cards), and `rsync` (used for fast differential
   mirroring of the built `public/` directory back to the host mount).
4. **`npm install -g wrangler@4.80.0`** — Cloudflare's own deploy CLI,
   used by `deploy.py` when a course publishes to Cloudflare Pages (see
   [deployment](07-deployment.md)). It is pinned, and pinned **below
   4.87** deliberately: 4.87.0 is the first wrangler whose `engines.node` is
   `>=22.0.0` (4.80.0 to 4.86.0 say `>=20.3.0`; this said 4.100 until #640,
   which was never a boundary). The image runs Node 22 since #640, but the
   pin is shared with Windows, whose runtime stays on Node 20 until its own
   issue lands — so the ceiling is Windows' now, and moving wrangler is its
   own piece once both platforms run 22. If Node is ever raised, revalidate
   Quartz *before* chasing a newer CLI. The pin also keeps the image reproducible and stops
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
6. **The certificate store, at least `ca-certificates 20250419+deb13u1`
   (#639, v1.9.0)** — its own layer, after the tikz engine and before the
   patches, so a teacher who has built before re-runs only it (10.4 MB,
   4 s, measured) rather than the apt line and everything below it:
   ```dockerfile
   RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && dpkg --compare-versions "$(dpkg-query -W -f='${Version}' ca-certificates)" ge 20250419+deb13u1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
   ```
   A floor, not an exact version, and the floor is in the line's text, so
   raising it re-runs the layer. Why, what was measured and what was
   rejected: [The certificate store](#the-certificate-store-639-v190).
7. **GeoGebra Math Apps 5.4.933.1 → `/opt/vendor/geogebra` (#578)** — its own
   layer straight after the certificate store it downloads through: the zip
   from download.geogebra.org, retried, then from plantoir.app's mirror of the
   same file, one `sha256sum -c` whichever answered, then
   `scripts/geogebra_engine.py adapt`. Only that script is copied in (to
   `/tmp`, never baked), so editing any other script never downloads the
   33.5 MB again. What it keeps, the six replacements and the mirror:
   [`/opt/vendor/geogebra`](#optvendorgeogebra-578).
8. **Overwrite five Quartz source files with patched versions** from
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
9. **Copy the Python scripts** into `/opt/scripts/` — eleven of them as of
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
10. **Copy `support/` → `/opt/support/`** — data files consumed by the
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
11. **Bake the launcher scripts into `/opt/export/`** and register an
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
12. **Default state**: working directory `/teaching`, command `/bin/bash`.

**Gone since #334: `cp -r /opt/quartz /opt/quartz-site`**, which used to be
step 7 — a spare copy of the scaffold that nothing read (the build copies
from `/opt/quartz`), kept in step by a `cp` on the end of the line that bakes
the Explorer's hide filter. It was 468 MB of image disk per image version,
and during an update two versions sit side by side for a day. `verify.sh`
now checks it is absent.

### `/opt/vendor`: engines a site carries only when a page asks (#454)

**Beside it since #499 (v1.6.0): `/opt/vendor/pagedjs/fonts/`**, six Latin
Modern faces (Roman regular, bold, italic, bold italic; Sans bold; Mono —
631,940 bytes, unmodified OTF) and `LICENSE-Latin-Modern.txt` (Debian's
copyright file, which carries the GUST Font License). A printed handout is set
in them (06 → F8), and the same gate carries them. They come from Debian's
`fonts-lmodern` through apt — installed, copied, purged in one layer — not
from GUST's download page, so a font host that is down can never fail a
teacher's first build; the six SHA-256s are in `contracts/toolchain.json` →
`pins` → `latinModern` → `files`, and verify.sh checks the baked files
against them rather than the recipe, so a Debian point release that touched
them would surface in a check instead of in a teacher's build.

Since v1.6.0 the image fetches **Paged.js 0.4.3** from the npm registry by
exact version, checks the tarball's SHA-256 (`a79baaa9…6c17c5`), and keeps
only `dist/paged.min.js` (502,617 bytes, 96,934 gzipped, SHA-256
`c4af9ac4…397211`) and its MIT licence in `/opt/vendor/pagedjs/`. It is the
print layout for pages whose settings say `printable: true` (see
[06 → F](06-quartz-customizations.md#f-additions-installed-every-build-printable-pages-454-v200)).
It is NOT in the scaffold's `static/`: `build_site.py` copies it into a
section's site only when a page students can see opts in, so a course that
never prints carries none of it. `toolchain_paths.VENDOR_DIR` is
`QUARTZ_DIR.parent / "vendor"` — `/opt/vendor` here and `runtime\vendor` on
Windows with no variable of its own (`PLANTOIR_VENDOR_DIR` overrides it).
`contracts/toolchain.json` → `pins` → `pagedjs` carries both hashes; verify.sh
checks the baked file against `fileSha256`. Two things to know: the UMD
global is `PagedModule`, not `Paged`; and the project is QUIET — 0.4.3 has
been npm's `latest` since 2023-07-06, with only `0.5.0-beta.2` (2024-10-04)
since — so a browser change it does not keep up with is ours to work around.
**Rejected:** loading it from a CDN (a printed worksheet must work offline and
from a folder publish), carrying it in every site (half a megabyte per site
for a feature most pages never use), and committing the file (the repository
ships recipes, not binaries). #455 adds Pyodide to the same folder (below).

### `/opt/vendor/function-plot` and `/opt/vendor/tikz-engine` (#485 E1, v1.7.0)

Two more engines for the same folder, both for figures a teacher writes as
fences (` ```functionplot `, ` ```tikz `; [05 → Diagrams and
graphs](05-build-pipeline.md#diagrams-and-graphs-what-the-build-does-485-e1-v170),
[06 → G](06-quartz-customizations.md#g-diagrams-and-graphs-485-e1-v170)):

- **`/opt/vendor/function-plot/`** — function-plot **1.25.4** (MIT),
  fetched from the npm registry by exact version and checked against the
  tarball's SHA-256 (`33974ca5…6a77`), keeping only `dist/function-plot.js`
  (202,953 bytes, 60,012 gzipped, SHA-256 `4e3cc6d8…02d1`) and `LICENSE`.
  Gated exactly like Paged.js: a section's site carries it
  (`static/function-plot/`) only while a page students can see has a graph
  that can be drawn. The build also CHECKS every graph with this file, so a
  graph the site would refuse is reported first. It evaluates with
  `new Function`, which Netlify's `'unsafe-eval'` already allows (07), and
  its bundle names `self` while loading, so the build's helper sets
  `globalThis.self` first.
- **`/opt/vendor/tikz-engine/`** — node-tikzjax **1.0.5** (LPPL-1.3c) and
  everything under it, installed with `npm ci --omit=dev` from
  `support/figures/package-lock.json` and then asserted with
  `npm ls node-tikzjax@1.0.5`. Its TeX engine — `tex.wasm`, `core.dump` and
  all 212 TeX files — is byte-identical to the one the Obsidian TikZJax
  plugin (obsidian-tikzjax 0.5.2) embeds: measured by SHA-256 of every
  decompressed file, 213 distinct contents on each side and none on one side
  only. The JavaScript AROUND the engine differs (`@prinsss/dvi2html` 0.0.1
  and svgo 3.3.5 here, the plugin's own dvi2html and svgo 2), so "the same
  picture" also rests on four diagrams compared by `viewBox` (to 3 dp) and
  text runs. **The lockfile is load-bearing**: node-tikzjax floats
  `jsdom ^23`, `svgo ^3` and `memfs ^4`, and svgo shapes every drawing, so
  an unpinned install would change pictures under teachers. Measured:
  **133 packages, 5,445 files, 39.8 MB of files (57 MB on ext4), 14.4 MB
  compressed.** The same lockfile on NTFS, in the Windows runtime's
  `runtime\vendor\tikz-engine` (#503, measured 2026-10-15 on an i5-8365U,
  Windows 11 Pro 26200): 133 packages, 5,450 files (5,448 under
  `node_modules` plus the folder's `package.json` and lockfile), 40,838,241
  bytes —
  [12 → Diagrams and graphs](12-windows-app.md#diagrams-and-graphs-485-e1-v170-the-runtime-carries-the-engines-503). It is NEVER copied into a site — the site carries only the
  Computer Modern faces its drawings use (`static/tikz`, about 30 KB a face)
  — and it is deliberately not called `tikz`, the name of that fonts folder,
  so one slip into `GATED_ASSETS` cannot ship 39 MB into a site (review S8).

Both layers sit BESIDE Paged.js, before the first `COPY patches/`, so editing
a script never downloads them again; `npm ci` reaches the registry only when
the lockfile changes. `contracts/toolchain.json` → `pins` → `functionPlot`
and `nodeTikzjax` carry the hashes; verify.sh checks function-plot's file,
node-tikzjax's version and its three `tex/*.gz` files in the image.
Licences: `THIRD_PARTY_LICENSES.md` at the repository root.

**Rejected:** TikZJax in the browser, as the Obsidian plugin does it
(7.0 MB of script, 4.94 MB gzipped, plus 4.8 MB of fonts per student; 615 ms
for the first diagram and 1,838 ms for four, measured in Chromium);
installing node-tikzjax into Quartz's own `node_modules` (npm's hoisting
could move Quartz's versions); bundling it with esbuild (it reads `tex/`
beside itself by `__dirname`); a fork without jsdom (ours to maintain);
loading either engine from a CDN (a site must work from a folder publish and
offline, and the issue asks for no other origin).

### `/opt/vendor/pyodide` (#455, v1.8.0) and KaTeX's pin (#494)

**`/opt/vendor/pyodide/`** — Pyodide **314.0.7** (2026-09-14, CPython
3.14.2 compiled to WebAssembly; MPL-2.0), the Python a page's
` ```python run ` blocks run in, in the student's browser
([06 → I](06-quartz-customizations.md#i-runnable-code-455-v180)). The layer
fetches the core tarball `pyodide-core-314.0.7.tar.bz2` from the project's
GitHub release by exact version (6,757,104 bytes, SHA-256
`2abdcc2e…3f95`), checks it, extracts it with `python3 -m tarfile` (the slim
base has no `bzip2`), and keeps exactly five files — **13,531,207 bytes**:

| File | Bytes | What it is |
|---|---:|---|
| `pyodide.mjs` | 17,931 | the loader a MODULE worker imports (#455 review B1: Pyodide 314 throws "Classic web workers are not supported" wherever data: scripts are allowed, so not `pyodide.js`) |
| `pyodide.asm.mjs` | 1,250,344 | the Emscripten glue (`.mjs` since Pyodide 0.28, not `.asm.js`) |
| `pyodide.asm.wasm` | 9,598,218 | CPython itself |
| `python_stdlib.zip` | 2,545,637 | the standard library |
| `pyodide-lock.json` | 119,077 | the package index the loader reads at start (no package is ever fetched) |

plus a `README.txt` naming the licence and source, because the tarball
carries no LICENSE file. Gated like the other engines: a section's site
carries it (`static/pyodide/`, with `support/gated/pyodide/plantoir-worker.js`
laid over it) only while a page students can see opts in with a runnable
block. `pyodide.mjs` names ONE other address, a jsdelivr fallback for
packages (`https://cdn.jsdelivr.net/pyodide/v${U}/full/`); the worker points
`indexURL`, `packageBaseUrl` and `cdnUrl` at its own folder, so it is never
used, and verify.sh 6j allows exactly that one string on a site. The layer
sits after function-plot and before the tikz-engine `COPY`, so editing a
script never downloads it again. `contracts/toolchain.json` → `pins` →
`pyodide` carries the tarball's hash and the five files'; verify.sh checks the
image holds exactly those five and the README (section 4), and the site
holds them byte for byte (6j).

**KaTeX** needs no layer: Quartz's own `npm install` already installs
**katex 0.16.21** (rehype-katex 7.0.1 renders every formula with it at build
time), and since #494 every site serves its stylesheet, copy-tex and woff2
faces itself (06 → C2-26). `RUN cd /opt/quartz && npm ls katex@0.16.21`,
straight after that install, fails the image build if the lockfile ever
resolves another version (measured: `npm ls katex@0.16.22` exits 1, and the
tree holds a single, deduped 0.16.21). `pins` → `katex` carries the three
files' hashes, which verify.sh checks in the image and on the site.

**Rejected:** loading Pyodide from its CDN (a third party and a network on
every Run, and no folder publish offline); downloading it when a site is
built (a build would need the network); the scaffold's `static/` (every site
would carry 13.5 MB); Skulpt (a Python-2-era subset students would outgrow);
JupyterLite or Custom Frames (a whole notebook per page).

### `/opt/vendor/geogebra` (#578)

**What it is.** GeoGebra Math Apps **5.4.933.1**, the engine a page's
` ```geogebra ` sketches run on in the student's browser (the fence, its
build pass and the site's loader are in 05 → "GeoGebra sketches: what the
build does" and 06 → Q; this section is the engine and where it comes
from). Gated like the engines above:
`page_features.GATED_ASSETS["geogebra"]`, so a section's site carries it
(`static/geogebra/`) only while a page students can see has a sketch, and a
site without one is byte for byte as before.

**Where it comes from, and why twice.** `https://download.geogebra.org/
installers/5.4/geogebra-math-apps-bundle-5-4-933-1.zip` — 33,461,640 bytes,
SHA-256 `40909594…15ec0c`, Last-Modified 2026-10-19. **The host is flaky:**
4 of 8 connections timed out on 2026-10-23 (about 20:35 EDT), and guessed
older version URLs 404, so a pinned version can vanish upstream. The layer
therefore runs `curl --retry 6 --retry-all-errors --retry-delay 5
--connect-timeout 30 --speed-limit 1024 --speed-time 60` against it and, if
that fails, the same command against **`https://plantoir.app/mirror/geogebra/
geogebra-math-apps-bundle-5-4-933-1.zip`** — then ONE `sha256sum -c`, so
whichever host answered, only the pinned bytes get past it. The two addresses
are `contracts/toolchain.json` → `pins` → `geogebra` → `urls`, and the
Dockerfile's `ARG GEOGEBRA_URL`/`GEOGEBRA_MIRROR` must be those two exactly
(`scripts/test_geogebra_engine.py`). The mirror is `website/mirror.py`: the
file is NEVER committed (33.5 MB in every clone, and every bump kept in
history), `site/mirror/` is git-ignored and filled by `website/build.py` from a
cache outside the repository, and `build.py --deploy` refuses while it is
missing or not its SHA-256 — a mirror that 404s is invisible until the day
GeoGebra's host is down and a teacher's first build fails. Until the first
deploy that carries it has been read back by `--verify-deploy` (RELEASING.md
step 6), the fallback 404s and the primary is all there is. Netlify documents
no per-file limit (only 54,000 files per directory); the largest file on
plantoir.app before this was 1,102,789 bytes, so the first deploy is the
proof.

**What the image keeps** — `geogebra_engine.py adapt`, standard library only,
the ONE recipe (Windows' `fetch-runtime.ps1` runs the same script into
`runtime\vendor\geogebra`, so both platforms carry identical bytes). Of the
bundle's 486 files (121 MB unpacked): `deployggb.js` (37,188 bytes),
`HTML5/5.0/css/` (43 files) and the **`web3d` codebase** (72 files after
pruning) — `web3d` serves every app (classic, graphing, geometry, 3d; all four
measured in Chromium and WebKit), `web` is the non-3D duplicate and
`webSimple` has no toolbar or algebra view, so neither is kept, nor
`GeoGebra.html`. Inside `web3d` it leaves out **the 83 language files**
(`js/properties_keys_*.js`, 23 MB — English is built into the engine, and a
missing language falls back to English, measured with `lang=fr`), `html/`
(sign-in callbacks), `sworker-locked.js` and `web3d.nocache.mjs`; it keeps all
15 deferred fragments (CAS and 3D, 14 MB) and the fonts. Plus a `README.txt`
(version, licence, attribution, what was removed, the six changes):
**117 files, 27,093,283 bytes** (8.95 MB gzipped), `fileCount` and `bytes` in
the pin. A first sketch on a page downloads about 2.9 MB of it, gzipped (19
requests, measured); the rest is fetched only by what a sketch uses.

**The six replacements, and why there are any.** Under the policy a Netlify
publish sends (`script-src 'self' 'unsafe-eval' <hashes>`,
`scripts/netlify_badge.py`; Cloudflare and the preview send none) the STOCK
engine never loads, in Chromium or WebKit: GWT's loader injects its 7.9 MB
main file as inline script text on any host but `127.0.0.1`, `localhost` and
`apps-builds.` (so every browser check of this serves on `[::1]`), deferred
fragments are installed as inline `<script>` text, nine resources go into
`<head>` as inline scripts, and the zip library starts a `blob:` worker. So
`geogebra_engine.REPLACEMENTS` makes six exact text replacements, **each
required to match exactly once in the file as it stands at that step** — zero
or two matches means GeoGebra changed the file and the reasoning no longer
holds, so the step refuses and writes nothing (staging folder, then rename):

| # | File | Becomes |
|---|---|---|
| 1 | `web3d.nocache.js` | the main file always loads as a same-origin `<script src>` (`if(location.protocol.startsWith(cb)&&!g){` → `if(false){`) |
| 2 | `web3d.nocache.js` | `__installRunAsyncCode` runs a fragment with `eval` |
| 3 | `web3d.nocache.js` | the loader's hidden frame goes under `<html>` (`o.body.appendChild(a)` → `o.documentElement.appendChild(a)`): Quartz's page navigation replaces `<body>` and took the frame with it, after which Chromium loaded no second sketch until a reload |
| 4 | `…cache.js` | a resource GeoGebra adds to `<head>` is marked `type='text/x-plantoir-geogebra'` (inert; its id still answers GeoGebra's "already added?"), appended, and run with `$wnd.eval` |
| 5 | `…cache.js` | fflate's async `zip` calls `zipSync` and the callback on `setTimeout(0)` — no worker |
| 6 | `…cache.js` | the same for `unzip` with `unzipSync` |

Result (measured 2026-10-23, the real policy, Chromium 1243 and WebKit 2359):
loads from a file, from base64 and from commands, all four apps, and
cross-origin isolated (COOP+COEP) too — zero violations, zero off-site
requests. The pin's `files` hash `deployggb.js`, `web3d.nocache.js`
(`b4f3a5f0…27fe`) and the cache.js (`676326d5…1e68`) AFTER all six; only
nocache.js carries the frame fix, so the cache.js hash is the one the
measurement harness produced, and nocache.js's is not. verify.sh checks the
image: the file count, bytes and three hashes, each replacement's text present
once and GeoGebra's gone, no language file, no `web/` or `webSimple/`, and the
README. Re-measure all six before the pin moves.

**Licence.** GeoGebra's apps are free to use for **non-commercial**
purposes, with the notice "Made with GeoGebra®" and a link to
https://www.geogebra.org (licence page updated Nov 2025); language and
interface files CC BY-NC-SA 4.0. **The six changes rest on the EUPL 1.2**,
the licence of GeoGebra's source code, which the engine's two changed files
are: the EUPL permits modifying and redistributing it with a notice of what
changed and a pointer to the source, which `README.txt` carries
(https://github.com/geogebra/geogebra). They do NOT rest on the
non-commercial grant's "copy, distribute, modify", which is the clause for
GeoGebra's Materials (installers, web services, graphics), not its code
(stage-1 review, 2026-10-24). The engine used as GeoGebra's product, with
its style and interface files, stays under the non-commercial licence. We
redistribute in three places — the mirror, the Windows installer, every
class site with a sketch — all permitted non-commercially. **Free while Plantoir is free: if Plantoir is ever sold, contact
office@geogebra.org first.** `THIRD_PARTY_LICENSES.md` has the row.

**Rejected:** widening the site's policy (`worker-src blob:` alone is not
enough; replacements 1–3 would need `'unsafe-inline'`, which the hashes
disable and which would let Netlify's badge back in); pinning about ten
inline hashes (fonts vary, and one missed hash is broken lettering,
silently); a run-time patch of `head.appendChild` (it cannot reach 1–2, which
run in GWT's frame before any of our code); loading GeoGebra from geogebra.org
(a third party on every page, blocked by the same policy) or `material_id` in
deployggb (it calls geogebra.org); committing the zip; one download with no
fallback (4 of 8 timed out).

### The Swift image (#493, v1.8.0)

Runnable Swift blocks ([05 → Runnable Swift](05-build-pipeline.md#runnable-swift-what-the-launcher-and-the-build-do-493-v180))
are compiled in a **second image**, `teaching-quartz-swift:src-<hash>`,
whose recipe is `support/swift/` (`Dockerfile`, `compile.py`,
`ReadLineShim.swift`, `FlushBeforeRead.c`). It is NOT part of the website
builder: the launcher builds it the first time a preview has a Swift block
to compile, so a teacher who never writes Swift never downloads it. Its tag
hashes `support/swift/` ONLY (the launchers' `toolchain_hash` over that
folder), so a script edit elsewhere never rebuilds it; an edit inside it
changes this tag AND the website builder's (support/ is in that recipe),
which costs a small rebuild of the builder. `prune_superseded_swift_images`
in preview.sh is `prune_superseded_images`' twin for its own prefix, by the
same rules (never a blanket prune, nothing a container uses, nothing built in
the last day). Pins: `contracts/toolchain.json` → `swiftImage`, a top-level
key deliberately NOT under `pins` - both apps' pin tests read every pin as a
line the ROOT Dockerfile must contain; `scripts/test_swift_blocks.py` checks
these against `support/swift/Dockerfile` instead (Python, so Windows runs it).

**Windows has no Swift image** (#570, v1.8.6): it fetches the swift.org
Windows toolchain once and runs `compile.py` itself
([12 → Runnable Swift on Windows](12-windows-app.md#runnable-swift-on-windows-570-the-macs-493-v186)).
Its own files live in `scripts/` (`swift_windows_fetch.py`,
`swift_windows_compile.py`) and its pins in `toolchain.json` →
`swiftWindows`, deliberately NOT in `support/swift/`: a file added there
would change this image's tag and rebuild a 2 GB image on every Mac for a
change that is not theirs.

**What it holds** (spike, 2026-10-16, and its corrections):

| Layer | What | Pinned by |
|---|---|---|
| base | `python:3.11-slim@sha256:90744cff…` - the builder's own Debian 13 base, so the first layer is shared | digest |
| apt | runtime libraries the Linux toolchain links against (no -dev, no gcc: it only cross-compiles) | Debian |
| toolchain + SDK, one layer | Swift **6.4.0-RELEASE** for Debian 13, chosen by `TARGETARCH` (aarch64 1,102,526,016 B, x86_64 1,122,646,127 B - review S7), and the **one** platform-neutral wasm SDK bundle (92,760,992 B), installed into `/opt/swift-sdks` | SHA-256 each; GPG signatures verified against the Swift 6.x Release Signing Key `52BB7E3D…B47A981F` |
| binaryen | `wasm-opt` version_133 only (static; 17 MB kept), chosen by `TARGETARCH`, at `/opt/binaryen/bin` - **off PATH** | SHA-256 each (= GitHub's asset digests) |
| recipe | `compile.py`, the readLine shim, the flush - `/opt/plantoir-swift/` | the tag |

**Measured** (2026-10-17, Colima on an Apple M4 Pro, 6 CPUs, arm64): **80 s**
to build with its downloads (about **1.30 GB**: the toolchain, the SDK and
binaryen); **2.24 GB on disk, 504 MB compressed**. Untrimmed it was 5.61 GB
on disk (the spike's image, 3.74 GB of it toolchain). x86_64 is pinned but
its compiles are not measured.

**The trim** (#493 ruling Q2: applied now, not deferred) happens in the SAME
`RUN` that unpacks the toolchain, so nothing the compiler does not use is ever
stored in a layer: lldb, sourcekit-lsp, clangd, docc, swift-format, the
package manager (`swift-build`, `swift-package`, `swift-sdk` and friends),
`llvm-cov`/`llvm-profdata`, libclang/libLTO, the docs, and the Linux host's
OWN standard libraries (`lib/swift_static`, `lib/swift/embedded`,
`lib/swift/pm`) - the wasm ones come from the SDK. Kept: `swiftc` and the
driver, `swift-frontend`, clang, `wasm-ld`, `lib/swift/host/compiler` and
`lib/swift/linux`, which the frontend links against. The SDK is installed
BEFORE the trim (review S10), because the trim removes the program that
installs it. verify.sh's Swift gate checks the trim as built.

**Four corrections from the spike, each now a gate** (review S10):

1. **G1** - `swift sdk install <url> --checksum` CRASHES on Linux 6.4.0 after
   its download (FoundationNetworking: `_MultiHandle deallocated with
   non-zero retain count`, SIGABRT). The SDK is fetched with curl, checked
   with `sha256sum -c` and installed from the local file
   (`test_swift_blocks.py` pins the line).
2. **G2** - on Linux every link needs the SDK's clang resource folder
   (`-Xclang-linker -resource-dir -Xclang-linker
   <sdk>/swift.xctoolchain/usr/lib/swift_static/clang`): the Linux toolchain
   ships only `clang/21/lib/linux`, and the wasm builtins live in the SDK
   (`compile.mustContain`; the gate compiles).
3. **G4** - a one-call `swiftc` is NOT reproducible: it puts a random
   temporary object path into a 16-byte `.swift_modhash` data segment.
   compile.py compiles `-c` to `/tmp/plantoir-swift/<key>/main.o` and links
   from there, so the same code gives the same bytes in every run of one
   image (verify.sh compiles two fragments twice and compares). Across hosts
   the bytes still differ in exactly that segment (macOS and Linux name
   different paths), and **that does not matter**: the cache key is the
   code's hash plus the recipe's, never the program's (review S4, 06 → I10).
4. **G5** - the shim's character-device rule needs its RIGHTS too (06 → I10;
   the gate's must-fail).

**Disk** (review S9): building it holds the 1.1 GB download and the 3.7 GB
unpacked toolchain at once before the trim. The launcher asks the website
builder how much its disk has free first and builds nothing below **6 GB**
(`codeRunnerBlocks.swift.room.needGigabytes`); the build then says each block
is not ready because there is not enough free space. A full disk would
otherwise take the whole preview down, not only Swift.

**Rejected:** the toolchain in the builder's image (1.3 GB for every
teacher); the untrimmed image (5.61 GB) with the trim deferred to a
follow-up (ruling Q2); `swift sdk install <url>` (G1); wasm-opt on PATH
(Phase 0 trap 1: clang runs it by itself, changing the output); SwiftPM per
block (about 1 s more each, Phase 0); Ubuntu's toolchain build (Debian 13 is
the base's own); Swift 6.4.1 (released 2026-10-12 after Phase 0 measured
6.4.0: a toolchain move re-runs the swift-gate first, swift-gate/README.md).

### The certificate store (#639, v1.9.0)

**Why.** eMudhra reported six TLS intermediate certificates compromised
([oss-security, 2026-10-20](https://www.openwall.com/lists/oss-security/2026/10/20/1));
the roots they chain to are "AAA Certificate Services" (Comodo), "emSign
Root TLS CA - G3" (not in Debian's store at all) and "emSign ECC Root CA -
G3". Debian's answer, the same day, is `ca-certificates 20250419+deb13u1` in
`trixie-security`, which stops trusting the two of those it carried
(research on #636). It matters here because **Python's `urllib` trusts this store** —
`_ssl` links Debian's OpenSSL 3.5.6, whose default paths lead to
`/etc/ssl/certs/ca-certificates.crt` and the hashed folder `/usr/lib/ssl/certs`
— and `urllib` is every Netlify publish and `deploy.py`'s own Cloudflare calls
([07](07-deployment.md)). OpenSSL checks no revocation, so a chain to a
compromised intermediate is refused only once its root is no longer trusted.

**Measured, 2026-10-23, Colima on Apple silicon:**

- The images built so far (`teaching-quartz:src-c3c0841b`, 2026-10-22, and
  `quartz-teacher:dev-test`) carry `20250419`: **150** certificates, both
  roots in the bundle, in Python's default context and in `/etc/ssl/certs`.
- After the layer: `20250419+deb13u1`, **148** certificates, and
  `/etc/ca-certificates.conf` gains `!mozilla/Comodo_AAA_Services_root.crt`
  and `!mozilla/emSign_ECC_Root_CA_-_G3.crt`. Neither subject is left in any
  of the three places. The layer received 10.4 MB (mostly apt's lists) in 4 s.
- **The fleet is mixed today.** NodeSource's `setup_20.x` (measured on 20,
  before #640; `setup_22.x` does the same) itself runs
  `apt install … ca-certificates`, so a build with NO cache — a brand-new
  teacher — already got deb13u1 before this change. Every Mac that has built
  before holds the apt line's layer cached (here, built 2026-10-17 and reused
  since), with 20250419. Hence an explicit install AND a check, rather than
  relying on a third party's script.
- **Three other eMudhra roots stay trusted** after deb13u1: "emSign Root CA -
  G1", "emSign Root CA - C1" and "emSign ECC Root CA - C3". Debian removed
  exactly the two above. That is a finding, not a gate: the
  check names the two removed subjects and does not curate trust of its own.
- **Node's own built-in store** (`tls.rootCertificates`, used by wrangler for
  Cloudflare) does NOT read this file. On Node 20.20.2 it held 144 roots and
  still trusted emSign ECC Root CA - G3 (and the three above), though not AAA
  Certificate Services. Since #640 the image runs Node 22.23.4, whose store
  holds **116** roots and neither subject; of the four emSign roots only
  emSign Root CA - G1 is left, as in Debian's. verify.sh checks Node's store
  under the `node` pin ("Node 22 (#640)" below).
- **The Swift image is not changed and does not pick this up.**
  `teaching-quartz-swift:src-747b0982` carries 20250419 (150 certificates).
  `ca-certificates` is on its FIRST apt line (`support/swift/Dockerfile`), so
  a later recipe change leaves that layer cached and the old store in place;
  only a base-digest bump or an edit to that line would re-run it. The risk
  is low: it compiles with `--network none`, and every download its build
  makes is checked by SHA-256.

**The check.** `verify.sh` section 4 reads `contracts/toolchain.json` →
`pins` → `caCertificates` and checks, in the fresh image: the version is at
least `value` (`dpkg --compare-versions … ge`); no `mustNotTrust` subject is
in the bundle (loaded into its own context), in Python's
`ssl.create_default_context().get_ca_certs()`, or among the subjects of the
hashed `*.0` files; and the default context holds more than 100
certificates, so an empty store — which trusts nothing — cannot pass for one
that distrusts the right two. Run against the 2026-10-22 image it fails on
all four counts; against a store cut to 50 certificates it fails on the
count. (The first draft matched `CN = ` in `openssl x509 -subject` output;
OpenSSL 3.5 prints `CN=`, so that half would have passed on the old image —
caught by running it there.) A real "urllib refuses a chain to that root"
test is not possible offline, since nobody holds the roots' keys to mint one;
the trust list the default context loads is the thing urllib actually uses.

**Rejected:**

- an exact `ca-certificates=20250419+deb13u1`: Debian's security archive
  serves only its newest version, so the build breaks the day deb13u2 ships;
  a later version only distrusts more;
- bumping the base digest: not needed (deb13u1 is reachable from the live
  `trixie-security` the base already names), a full rebuild for every
  teacher, it moves Python's patch release, and the Swift image shares it;
- `apt-get upgrade`: unbounded — the image would become that day's Debian;
- snapshot.debian.org: a new, rate-limited dependency on a teacher's first
  build;
- adding it to the main apt line: about 330 MB once for every teacher who
  has built (apt, wrangler, the clone, Quartz's npm install), the cost for
  which `--no-install-recommends` was already rejected below;
- distrusting the other emSign roots ourselves: a hand-curated trust store
  is a job we would own forever;
- relying on NodeSource's script to keep installing it: third-party, and a
  cached layer never re-runs it.

**Not in this piece:** the image has other Debian security updates waiting,
among them OpenSSL itself (`libssl3t64` 3.5.6 → 3.5.7), which is the library
`urllib` runs on — a follow-up issue decides between a digest bump and
naming the package.

### Node 22 (#640, v1.9.0)

The image moved from an unpinned `setup_20.x` to **Node 22.23.4, pinned
exactly** (`nodejs=22.23.4-1nodesource1`). Node 20 has been end-of-life since
2026-04-30, and the unpinned line let the image and Windows' runtime drift to
different patch releases (#636). 22.23.4 is the 2026-10-20 security release
(npm 10.9.9, OpenSSL 3.5.9). **Node 22 is itself end-of-life on 2027-04-30**,
so Quartz 5 (#512) or Node 24 has to land before then.

**Why an `=` pin here when #639's is a floor.** NodeSource's `node_22.x
nodistro` keeps its history: on arm64 `apt-cache madison nodejs` lists every
version from 22.5.0 to 22.23.4, and amd64's Packages file has 22.23.4 down
past 22.22.0 (measured 2026-10-23). So the pin does not break a first build
the day 22.23.5 ships, the opposite of Debian's security archive.
`setup_22.x` writes `/etc/apt/preferences.d/nodejs` (Pin-Priority 600 for
deb.nodesource.com), so the `=` resolves from NodeSource, not Debian.

**wrangler's engines, measured** (`npm view 'wrangler@>=4.80.0' engines.node`,
2026-10-23): 4.80.0 to 4.86.0 say `>=20.3.0`; 4.87.0 to 4.152.0 (the current
`latest`) say `>=22.0.0`; none needs 24 yet. The pin's old reason, "below
4.100", was thirteen minors late — the pin itself was always safe. wrangler
stays at 4.80.0 and runs on 22 (`wrangler --version`, `wrangler pages --help`
exit 0); `mustStayBelow` is now `"4.87"` because Windows' runtime is still on
Node 20.18.1 and the pin is shared. The contract records wrangler's own
engines as `nodeEngine` (`>=20.3.0`): verify.sh reads it out of the image's
wrangler `package.json`, and the mac suite checks the `node` pin satisfies it.

**Measured, before (dev's recipe) and after, on an M4 Pro, Colima, arm64,
in an isolated buildx builder:**

| | Node 20 | Node 22 |
|---|---|---|
| `node --version` / npm | v20.20.2 / 10.8.2 | **v22.23.4** / 10.9.9 |
| `wrangler --version` | 4.80.0 | 4.80.0 |
| OpenSSL / undici | 3.0.19 / 6.24.1 | 3.5.9 / 6.29.1 |
| global `WebSocket` | undefined | a function |
| `tls.rootCertificates` | 144, four emSign roots incl. ECC Root CA - G3 | **116**, emSign Root CA - G1 only, neither #639 subject |
| image size (`docker images`; in brackets, the compressed size `docker inspect` reports) | 1.80 GB (409,188,226 bytes compressed) | 1.85 GB (419,682,603 bytes compressed) |
| cold build | 87 s | 84 s |
| Quartz + tikz engine `npm ls --all --long` | 665 lines | identical, no EBADENGINE, same lockfile |

**The site is the same.** One EXC2O course tree built in both images, twice
each: after removing timestamps and Quartz's random Explorer ids, and
comparing order-insensitively, the same 336 files with **0 differences**. The
remaining raw differences are run-to-run noise that Node 20 shows against
itself (9–49 files between two Node 20 runs: the Explorer id, `<time
datetime>`, and the order of equal-dated pages on tag and folder pages). A
TikZ figure's cache entry is byte-identical (engine id `469d55e0a0342d07`),
so diagrams cached under Node 20 stay valid. Native packages (sharp,
lightningcss, @napi-rs/simple-git, esbuild) are N-API or standalone binaries,
so nothing rebuilds per Node version.

**The one new behaviour: a deprecation line in the console.** On Node 22
every Quartz build printed ``(node:N) [DEP0040] DeprecationWarning: The
`punycode` module is deprecated`` (Quartz v4.5.0's dependencies require the
built-in), which reaches the app's console — machinery a teacher should not
see (CLAUDE.md rule 1). `scripts/toolchain_paths.py` → `node_environment`
adds `--disable-warning=DEP0040` to `NODE_OPTIONS` for Quartz (build_site.py)
and for the figure helper (figures.py), keeping any `NODE_OPTIONS` already
set and never writing the flag twice. The figure helper was measured silent
on Node 22 with and without it (a diagram and a graph, stderr empty); it is
routed anyway so every node the build starts is under one rule, and a later
deprecation cannot become the reason given when the helper fails to start. It is accepted from Node 20.11
(measured on 20.20.2 and 22.23.4), so Windows' Node 20 runtime inherits it
safely. `scripts/test_node_warnings.py` pins the helper and both callers;
verify.sh fails if the main build's log carries a `[DEP` code at all (Node's
own prefix, not the word "DeprecationWarning", which a page could carry).

**Rejected:**

- **Node 24** — the ruling on #636 is 22; Quartz's own v4 line runs on 22;
  24 buys a year (EOL 2028-04-30) but is a second, unmeasured jump. Noted for
  #512.
- **A floating `setup_22.x`** — the image and Windows drift again, which is
  #636's own finding about 20.x.
- **A late `nodejs` layer that leaves the apt line alone** — it saves existing
  teachers only the apt layer (about 90 MB, estimated), because wrangler,
  Quartz and the rest below must rebuild anyway to be installed by the new
  npm; it carries Node 20's files as dead weight and gives an image no
  no-cache build reproduces.
- **`NODE_NO_WARNINGS=1`** — hides every warning, including the ones a real
  break would print.
- **Removing `mustStayBelow` now** — Windows' suite reads it, and the ceiling
  still holds for Windows' Node 20.

**For Windows:** the runtime (`windows-app/Vendor/fetch-runtime.ps1`) stays
on Node 20.18.1 until its own `windows` issue moves it to the same 22.23.4;
that issue adds `windowsRuntimeContains` to the `node` pin with the bump.

### Known vulnerabilities in the image's npm packages (#667, v1.9.0)

The image carries five JavaScript trees. `verify.sh` audits all five against
npm's advisory database at every run, inside the image and with the image's
own npm. `scripts/npm_audit.py` then compares the result with an accepted
list kept as authored text in `contracts/toolchain.json` → `npmAudit`. The
gate fails on a **new** high or critical advisory: one the list does not
accept for that tree, or one the list accepted at a lower severity than the
database now gives it. It does not fail on an advisory that has already been
looked at and decided. The ruling on #667 was to accept every current finding,
record the reason, and upgrade nothing this release.

**What is audited, and how each lockfile is obtained.** `npm audit` reads a
lockfile, so each tree needs one:

| Tree (`npmAudit.trees`) | In the image | Lockfile | Packages |
|---|---|---|---|
| `quartz` | `/opt/quartz` | Quartz v4.5.0's own `package-lock.json`, dev dependencies included | 614 |
| `tikz-engine` | `/opt/vendor/tikz-engine` | `support/figures/package-lock.json` (`npm ci --omit=dev`) | 133 |
| `wrangler` | `/usr/lib/node_modules/wrangler` | **none**: a global install keeps no lockfile (`npm audit` there says `ENOLOCK`). One is built from the INSTALLED tree: the folder is copied into an empty project, then `npm install --package-lock-only --ignore-scripts` runs. With no lockfile present, npm starts its ideal tree from the actual one, so the lockfile records the installed versions: miniflare, undici, ws, sharp and esbuild were checked against `npm ls`. This needs no network. | 35 |
| `pagedjs` | `/opt/vendor/pagedjs/paged.min.js` | built from the pin's version in an empty project | 18 |
| `function-plot` | `/opt/vendor/function-plot/function-plot.js` | built from the pin's version | 28 |

**The limit on the last two.** They are prebuilt files. A lockfile built from
the pin resolves the package's declared dependencies as they are TODAY. The
file, though, bundles whatever those dependencies were when it was published.
So an advisory against `pagedjs@0.4.3` or `function-plot@1.25.4` themselves
is caught exactly, and their bundled dependencies only approximately. That is
still worth doing: these are the two trees whose code runs in a student's
browser. The versions passed in (`wrangler`, `pagedjs`, `functionPlot`) are
read from the pins, never retyped.

**Not audited, and why.** GeoGebra's applet is a bundle with no npm tree.
Pyodide is Python and WebAssembly. KaTeX is inside the `quartz` tree. Latin
Modern is a Debian font package, and Debian's packages are another tool's job.
**npm and corepack** ship inside Node itself and move with the `node` pin
(#640). Their dependencies are not an installed tree that `npm audit` reads.
They change when the pin changes, and that is where they are reviewed.

**What fails, what is reported, what is skipped.**

- A high or critical advisory not accepted for its tree, or accepted at a
  lower severity than it has now: **FAIL**, naming tree, package, id and
  title.
- An unaccepted low or moderate advisory is **reported**, not failed.
- An accepted advisory that is no longer reported is **stale**. It is
  reported, never failed, because an upgrade is what makes an entry stale.
- A tree whose lockfile is gone (`ENOLOCK`, or the folder missing) for
  `quartz`, `tikz-engine` or `wrangler`: **FAIL**. The image changed. This is
  not a skip.
- Output that does not parse as JSON, or JSON in a shape the comparator does
  not know: **FAIL**, never SKIP.
- **SKIP** only when npm's own JSON has no `metadata` and its `message` says
  the audit request failed. For `pagedjs` and `function-plot` it is also a
  SKIP when their lockfile step failed with a network error. The SKIP says
  no tree counts as audited until every tree can be. One unreachable tree skips the whole gate, so a
  half-audit cannot read green. A blocking finding in another tree still
  fails.
- Only npm's STDOUT is read. Offline, `npm audit --json` prints
  `{"message":"request to https://registry.npmjs.org/-/npm/v1/security/audits/quick failed, reason: getaddrinfo EAI_AGAIN …"}`
  on stdout, puts an `npm error` line on stderr, and exits 1. With findings it
  also exits 1. Neither stderr nor the exit code says anything the JSON does
  not (measured with `docker run --network none`, 2026-10-24).

**How a finding is accepted.** Add it under `npmAudit.accepted`, grouped by
tree and package. Give the advisory's id and the severity it has TODAY, an
`exposure` (student's browser, the teacher's build only, the teacher's Mac
during a preview, Cloudflare deploy only, or not run) and a `reason`. Record
it in a new `research/npm-audit/<date>.md`. Each tree is decided on its own,
because one advisory can be harmless in one tree and not in another: ws's two
advisories are accepted for `quartz` (the preview's live reload) and,
separately, for `wrangler` (miniflare, which a deploy never starts). Every
advisory is listed, low and moderate included. That is what makes a later
severity RAISE fail, and a raise is the one way an accepted id becomes newly
dangerous.

**Measured 2026-10-24** (`research/npm-audit/2026-10-24.md`, image
`quartz-teacher:dev-test`, Node 22.23.4, npm 10.9.9): **81 (tree, advisory)
pairs**. `quartz` has 51 (39 high, 10 moderate, 2 low) across 14 packages.
`wrangler` has 30 (11 high, 13 moderate, 6 low) across undici, sharp, ws and
esbuild. That makes 50 high and **0 critical**. `tikz-engine`, `pagedjs` and
`function-plot` have none. Nothing a student's browser runs is affected. The
nearest is the moderate in mdast-util-to-hast (an unsanitised `class`
attribute): its OUTPUT reaches students, but only the teacher writes the
Markdown it reads. The 15 xmldom advisories are in a package nothing runs:
pixi.js's, for the Graph view build_site.py removes. A built site has no
`pixi` or `xmldom` string. The undici advisories touch only a Cloudflare
deploy, and are fixed in wrangler > 4.113.0, which waits on Windows' Node 22.
The audit takes about 22 s online. Offline it takes about 2.5 min (npm's
retries), and only then. One more exposure fact, not this piece's to fix: the
preview ports are published on every interface (`lsof` shows `TCP *:8133` and
others held by Colima's forwarder), so the accepted ws and serve-handler
denials of service are reachable from the school network while a preview
runs.

**Revisited at every cut** (RELEASING.md step 2). Read verify.sh's npm-audit
line; a SKIP means it was not checked, so run it again online. Then run
`python3 scripts/npm_audit.py findings …` and decide each new or raised
advisory. Either upgrade, in its own piece, or accept it with its reason.

**REJECTED.**

- **Upgrading now.** The ruling on #667 is no upgrades this release. Quartz's
  tree moves with Quartz 5 (#512). wrangler moves in its own piece once
  Windows runs Node 22 (its pin's `mustStayBelow`).
- **Auditing in the image build.** It would need the network on every build,
  and it would fail an unchanged recipe, and a teacher's first build, the day
  an advisory is published. verify.sh is the developer's gate, and that is
  where this belongs.
- **`npm audit --audit-level=high` alone.** It cannot say "accepted", so a
  known advisory would turn every run red. That is exactly what the issue
  rules out.
- **The host's npm against copied lockfiles.** The image's npm 10.9.9 is the
  one that matters, and verify.sh already has the image.
- **Auditing nothing for pagedjs and function-plot ("no lockfile").** They are
  the two trees that reach students' browsers.
- **Unpacking their dist files** to identify the libraries bundled inside.
  `npm audit` cannot read a bundle.

**For Windows:** the same audit over the runtime's copies, at each tree's
`windowsRuntime` (`runtime\quartz`, `runtime\wrangler`,
`runtime\vendor\tikz-engine`, `runtime\vendor\pagedjs`,
`runtime\vendor\function-plot`). It uses Windows' own npm and goes through
the same `scripts/npm_audit.py compare` against the same list. The
comparator's tests (`scripts/test_npm_audit.py`, stdlib) already run there
through `PythonToolchainTests`. Only the wrangler tree can give a
Windows-only finding: its lockfile is built from the INSTALLED copy, while
the Quartz and tikz-engine lockfiles and the pin-made pagedjs and
function-plot lockfiles already list every platform's optional packages
identically. Decide such a finding, and add it to the shared list under its
tree.

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
| GeoGebra (#578) | 33.5 MB | the zip (33,461,640 bytes); its own late layer, so a teacher who has built before downloads only this, once, at the first preview after updating; NOT in the total below |
| certificate store (#639, added 2026-10-23) | 10.4 MB | measured on its own, after #334, so NOT in the total below; mostly apt's lists, and an install that changes nothing for a no-cache build, which NodeSource's script already upgraded |
| **Total** | **≈382 MB → ≈342 MB** | #334's stages only (≈352 MB with #639's layer); #312's VM counter read 389.8 MB in a fresh VM |

**Since #640 (2026-10-23)** the apt line's text changed (`setup_22.x` and
the `nodejs=` pin), so every teacher who has built before re-downloads that
line and everything after it once — about 330 MB by this table's numbers
(apt, wrangler, the clone, Quartz's `npm install`, the tikz engine, Pyodide,
the certificate layer), not re-measured. That piece's own cold build was 84 s
in an isolated builder, against 87 s on Node 20.

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

# 1. Overview & Design Rationale

[◀ Back to index](README.md) · [Next: The Docker Image ▶](02-docker-image.md)

## The problem being solved

Learning-management systems (Edsby, Brightspace, Google Classroom) are slow to
publish to, awkward to structure, and hard to migrate away from. Teachers who
maintain multiple sections of the same course face an additional pain: most of
the content is identical across sections, but each section moves at its own
pace, so *what is visible* and *when it was covered* differs per section.

This toolchain lets a teacher:

1. **Write everything as plain Markdown** in an Obsidian vault — future-proof,
   searchable, portable, version-controllable.
2. **Share most content across sections** while keeping per-section lesson
   sequences (`section1/`, `section2/`, …) and per-section publication state
   (a page can be published to Section 1 and still hidden for Section 2).
3. **Publish a polished website per section** with one command, with search,
   code highlighting, LaTeX math, callouts, backlinks, and light/dark mode —
   all provided by Quartz.
4. **Own the output**: the deployed site is a folder of static files on a
   Netlify site under the teacher's own account.

## Why these particular technologies

- **Quartz** was chosen because it is purpose-built to turn an Obsidian vault
  into a website: it understands wikilinks (`[[Page Name]]`), transclusions
  (`![[Page Name]]`), callouts, and Obsidian-flavoured Markdown natively, and
  produces a modern site with full-text search. Version **4.5.0** is pinned so
  the ~40 patches applied on top of it (see
  [Quartz Customizations](06-quartz-customizations.md)) always target known
  code.
- **Docker** removes the single largest support burden when sharing the
  workflow with other teachers: environment setup. Node.js, Python,
  `python-frontmatter`, and the patched Quartz checkout are all frozen inside
  one image, built locally on each machine from the recipe every working
  folder carries (tagged `teaching-quartz:src-<hash8>`), so a teacher never
  touches npm or pip — and no registry account is involved. Docker Desktop is deliberately **not** used: the launchers provision a
  free, open-source runtime themselves — [Colima](https://github.com/abiosoft/colima)
  on macOS, the Docker Engine inside WSL2 on Windows — and start it
  automatically on every run, removing the "open Docker Desktop and wait"
  manual step entirely
  (see [Launcher Scripts](03-launcher-scripts.md#container-runtime-bootstrap)).
  Distribution is **the Plantoir app**: it bundles the full build recipe
  (Dockerfile, patches, scripts, support files, contracts, launchers) and mirrors it
  into each working folder's `.toolchain/`, refreshing stale copies — so
  teachers never clone this repository, and an app update IS a toolchain
  update (new recipe → new image tag → local rebuild → recreated
  container). The image still bakes an `export-scripts` command as an
  escape hatch.
- **Netlify** provides free static hosting with instant cache invalidation.
  Deploys use Netlify's *file-digest* API so that a typical daily update
  uploads only the handful of files that changed
  (see [Deployment](07-deployment.md)).
- **Python inside the container** does the orchestration: an interactive
  setup wizard, a build pipeline that merges content and patches Quartz, and
  a deployer. Python was a natural choice because the heavy lifting is text
  processing — frontmatter manipulation, regex patching of TypeScript
  files — and because it ships in the base image (`python:3.11-slim`).

## The three commands, and what they really do

| Command (macOS / Windows) | Script pair | What actually happens |
|---|---|---|
| `./setup.sh` / `.\setup.bat` | [`setup_course.py`](04-course-setup.md) | Ensures the container is running with the right folder mounted, then runs an interactive wizard that scaffolds `courses/<CODE>/` and writes `course_config.json` |
| `./preview.sh ICS3U 1` / `.\preview.bat ICS3U 1` | [`build_site.py`](05-build-pipeline.md) | Merges shared + section-1 content into `.merged_output/section1/` (a shortcut to a builds folder outside the working folder), patches the Quartz scaffold, draws the section's social sharing card, and serves the site — the launcher prints the address (each working folder has its own probed host port block) |
| `./deploy.sh ICS3U 1` / `.\deploy.bat ICS3U 1` | [`deploy.py`](07-deployment.md) | Publishes an EXISTING static build — it never builds one: if `public/` is missing or empty the launcher stops and tells the teacher to run preview with `--build-only` first. Then publishes `public/` to the course's chosen destination: delta-upload to a Netlify site (the default), `--target cloudflare` for a Cloudflare Pages project, or `--to-folder` to copy it into a folder on the teacher's own machine |

## Key design decisions worth understanding

**Per-section output directories.** Each section gets a complete, independent
Quartz installation — its own colour scheme, fonts, emoji, page title and
`node_modules` — so a broken build for one section cannot affect another. It
costs disk space and buys total isolation.

**Where that installation actually lives is worth being precise about, because
two older descriptions of it were wrong.** It is built on the container's own
fast storage (`/tmp/quartz-builds/<CODE>/section<N>/`), and only the finished
`public/` and a copy of `course_config.json` are mirrored back out — so the
scaffold and `node_modules` have never been on the teacher's disk since the
build moved to container-internal storage. And since 2026-09-05 what IS mirrored
back is kept OUTSIDE the working folder:
`courses/<CODE>/.merged_output` is a shortcut to
`~/Library/Application Support/Plantoir/builds/<folder id>/<CODE>` on macOS, and
Windows writes to `%LOCALAPPDATA%\Plantoir\builds\<folder id>`. A built site is
derived and can always be made again, but keeping it in the working folder meant
a cloud service uploaded every build of it, Time Machine backed it up, and a zip
or a Finder copy of the course carried it. Every script and every reader still
names the same path; the shortcut is what makes that true. See
[`contracts/shared-rules.json`](../contracts/shared-rules.json) →
`buildOutputLocation`.

**Patch-at-build-time, not fork.** Rather than maintaining a fork of Quartz,
the toolchain keeps a pristine `v4.5.0` checkout and applies small, mostly
regex-based patches every time a site is built. Three heavily modified
components are replaced wholesale at image-build time; everything else is
edited in place, idempotently. The trade-off: patches are resilient to teacher
tinkering (they re-apply on every build) but pinned to the exact source text
of v4.5.0 — which is why the Quartz version is pinned in the Dockerfile.

**Configuration is data, not code.** Everything a teacher chooses in the setup
wizard lands in one JSON file, `course_config.json`, at the course root. The
build script treats it as the single source of truth and even *appends newly
discovered folders to it automatically* on each build, so a teacher can create
a new folder in Obsidian and have it appear on the site without re-running
setup (see [the build pipeline](05-build-pipeline.md#preflight-discovery)).

**Determinism for cheap deploys.** Several patches exist purely to make
successive builds byte-identical when content has not changed (a stable
component ID instead of a random one, a fixed `SOURCE_DATE_EPOCH`, dropping
git-derived dates). Every byte that stays identical is a file Netlify does
not ask to be re-uploaded.

---

[◀ Back to index](README.md) · [Next: The Docker Image ▶](02-docker-image.md)

# Releasing Plantoir

**One product, one version series, one GitHub release carrying both platforms'
assets.** The product version lives in ONE place — `<Version>` in
`windows-app/Plantoir/Plantoir.csproj` — and `MARKETING_VERSION` in
`mac-app/project.yml` must say the same number. The About panels read them and
the git tag must match.

> **No release has ever been cut.** `git tag` is empty and the GitHub releases
> list is empty, so the first run of this checklist ships **1.0.0**, which
> `Plantoir.csproj` already declares — there is nothing to bump. The release
> notes summarise the product rather than a delta. Note also that
> `website/site.json` already reads version 1.0.0, released August 2026, and
> the built page's macOS download link already points at
> `releases/latest/download/…`: that link is dead until the first release
> exists. The Windows card deliberately says "Coming soon" rather than linking
> to an asset that has never been published.

> **Which repository?** plantoir.app's download links resolve against
> `github.com/russellgordon/plantoir`, which matches `origin`. Pass
> `-R russellgordon/plantoir` explicitly to every `gh` command — a release
> published to the wrong repository leaves the site's evergreen links serving
> nothing.

## The short version

For future-you, mid-school-year, who remembers nothing. The whys are below.

1. **Everything merged and green?** Both sides on `main`; `dotnet test` passes
   in `windows-app/`; the mac unit suite passes. Then **actually publish a
   section from an app** — see step 2 for why that is not optional.
2. **Check the version** in `windows-app/Plantoir/Plantoir.csproj` and
   `mac-app/project.yml`; they must match each other and the tag you are about
   to cut.
3. **Build the signed Windows bundle**: `az login`, then
   `cd windows-app; powershell -File publish.ps1 -Sign`. It fails fast with the
   remedy if anything is missing. Output lands in `windows-app\dist\`.
4. **Try it like a teacher**: extract the zip on a machine (or at least a fresh
   folder) and run it. Check the signature on **both** executables.
5. **Tell Claude "cut the release."** It drafts teacher-friendly notes, adds the
   SHA-256 table, shows you the draft, and only after your OK: updates the
   site's version line, redraws the brand images, tags and publishes.
6. **The mac asset ships on the same release**, named exactly
   `Plantoir-macOS.zip` — see "The macOS asset" below, because nothing in this
   repository builds it for you yet.

## The checklist, with the reasons

1. **Version.** `<Version>` in `windows-app/Plantoir/Plantoir.csproj` and
   `MARKETING_VERSION` in `mac-app/project.yml`. `project.yml` is the source on
   the mac side, so re-run `xcodegen generate` after changing it.
2. **Full test pass**: `dotnet test Plantoir.Tests` and the mac unit suite, plus
   a hand smoke of create → preview → publish on a real course.

   > The hand smoke is **not optional, and not a formality**. The bundle carries
   > the whole toolchain recipe (Dockerfile, `scripts/`, `patches/`, launchers)
   > inside the app, and the xUnit suite deliberately never touches Docker — so
   > a green test run says nothing about the thing teachers actually run.
   > `verify.sh`, the real toolchain gate, is bash and expects `docker` on
   > `PATH`, which does not hold on Windows where Docker Engine lives in WSL2.
   > **On Windows the hand smoke is the only toolchain verification there is.**
   > If the release changes anything under `scripts/`, the Dockerfile or a
   > launcher, smoke the publishing destination(s) it touches — there are three
   > (Netlify, Cloudflare Pages, a folder) and they take different code paths.
3. **Build the signed Windows bundle**:

       powershell -File publish.ps1 -Sign

   One-time tooling on a new machine (the Azure account/identity setup itself
   lives in the private Artifact Signing runbook):

       winget install --exact --id Microsoft.AzureCLI   # then open a NEW terminal
       dotnet tool install --global sign --prerelease

   Per session: `az login` (as the Azure signing account). The script preflights
   all three — missing tool or stale login fails in seconds with the remedy,
   before the minutes-long build. It signs with an RFC 3161 timestamp and
   refuses to package a signature without one.

   **It publishes TWO projects.** `Plantoir.csproj` and `Plantoir.Mcp.csproj`:
   `plantoir-mcp.exe` is copied in beside `Plantoir.exe`, and **four** binaries
   are signed — `Plantoir.exe`, `Plantoir.dll`, `Plantoir.Core.dll`,
   `plantoir-mcp.exe`. That copy is load-bearing: without it the assistant
   reports that Plantoir's own tools cannot be found, on a teacher's machine
   only. An unsigned executable sitting beside signed ones is also exactly what
   SmartScreen complains about.

   Output: **`dist/Plantoir-win-x64.zip`** + its SHA-256. The name is
   deliberately **unversioned** — see the asset-name rule in step 5.
4. **Verify like a teacher** (the only test that reproduces what they see): copy
   the zip to a machine — or at least a fresh folder — download it through a
   browser if possible, extract, then right-click **both** `Plantoir.exe` and
   `plantoir-mcp.exe` → Properties → Digital Signatures → signature OK,
   timestamp present, no street address in the certificate subject.
5. **Tag and release** — ask Claude to "cut the release": the `cut-release`
   skill (`.claude/skills/cut-release/`) drafts teacher-friendly notes from the
   commits since the last tag (grouped New / Improved / Fixed, internal work
   omitted), appends a Downloads table with each asset's size and SHA-256
   computed from the exact files being uploaded, shows the draft for approval,
   then tags and publishes via `gh release create`. Manual equivalent:

       git tag v<version>
       git push origin main v<version>
       gh release create v<version> dist/Plantoir-win-x64.zip \
         -R <owner/repo> --title "Plantoir <version>" --notes "..."

   **Asset names are LOAD-BEARING and must never change**:
   `Plantoir-win-x64.zip` (publish.ps1 emits exactly this) and
   `Plantoir-macOS.zip`. plantoir.app's download cards point at
   `releases/latest/download/<asset-name>` — GitHub's evergreen URL that serves
   the newest release's asset, so teachers click Windows or macOS and get the
   file, no GitHub in sight. Renaming an asset silently breaks the site's
   download link, which is why the zip carries no version number.
6. **plantoir.app updates itself**: the site lives in `site/` in this repo, and
   Netlify deploys it on every push (one-time setup: in the Netlify UI, link the
   site to the GitHub repo, publish directory `site/`, no build command).

   **`site/` is BUILT, not hand-edited.** The sources are in `website/`; the
   version and release month are two fields in `website/site.json`. Cutting the
   release edits those, runs

       python3 website/build.py

   and commits both `website/site.json` and the regenerated `site/`. Editing
   the built HTML directly works right up until the next build overwrites it.
   `python3 website/build.py --check` reports any page that still refers to a
   screenshot nobody has taken — run it before tagging.

   **The rebuild always happens; the SCREENSHOTS are a separate decision.**
   The two jobs have opposite costs. Rebuilding is seconds and is what puts the
   new version and the new download URLs on the page, so it happens every time.
   Capturing screenshots drives the real app for the better part of an hour,
   needs the Mac left alone, and briefly switches its appearance — so it is an
   answer to a question, never automatic:

       python3 website/shots/capture.py --app      # the app windows
       python3 website/shots/capture.py --sites    # the class websites

   Re-shoot when the interface a teacher SEES has visibly changed since the
   last release, and only the half that changed. `git diff --stat <last-tag>..HEAD
   -- mac-app/QuartzTeachers/Views support/example_content` answers that in one
   line. Most releases need neither.

   Commit new screenshots as their own change rather than folding them into the
   release commit, so one that turns out wrong can be reverted without
   unpicking the version bump. Do not run the bare `capture.py` with no flags
   during a release — it also provisions courses and publishes the demo sites,
   which is first-run setup. See `website/README.md`.

   Cutting the release also redraws the brand images and installs the card:

       python scripts/brand_images.py --install-card

   Safe to run every time: the output is deterministic, so unless the icon,
   palette or tagline changed this leaves the working tree clean and there is
   nothing to commit. See **Brand images** below.
7. **Update the WinSparkle appcast** once in-app updates land: add an `<item>`
   for the new version to **`site/appcast-windows.xml`**, pointing at the GitHub
   release asset URL. The mac's Sparkle feed is a SEPARATE file,
   `site/appcast-macos.xml` — per-platform names from the start, so two update
   feeds can never collide.

## The macOS asset

**Nothing in this repository builds it.** Windows has `publish.ps1`; the mac
side has no packaging or signing script at all, so today the mac asset is
produced by hand and named exactly `Plantoir-macOS.zip`. Two things to know
before building one:

- **`mac-app/Vendor/llama` must be fetched first** (`./Vendor/fetch-llama.sh`).
  It is gitignored, and `xcodegen generate` fails without it — but a bundle
  built from a stale project would ship an assistant with no engine.
- The mac app must be signed and notarised for a teacher to open it without
  ceremony; that is not automated here either.

Until this is scripted, it is legitimate to ship a Windows-only release and say
so plainly in the notes — but the mac download card on plantoir.app should not
advertise a file that does not exist.

## Bundle format

Currently a plain zip of the self-contained publish folder (the ~58 MB
zipped / ~157 MB installed figures predate `plantoir-mcp.exe` being bundled —
re-measure after a `publish.ps1` run; no .NET or Windows App SDK install needed —
everything travels in the folder). The planned move to WinSparkle
auto-updates pairs naturally with an Inno Setup installer
(`PlantoirSetup-<version>.exe`): WinSparkle downloads and RUNS the
update it fetches, which a zip cannot do. When that lands, `publish.ps1`
gains an installer step after signing (and the installer itself gets
signed too); the zip can remain as a portable alternative.

## Brand images

Everything that carries the Plantoir mark — the `og:image` served at
plantoir.app, the Bluesky and Instagram profile photos, the Bluesky
banner — is drawn by one script from one source:

    python scripts/brand_images.py --install-card

It reads the artwork straight out of `mac-app/Plantoir.icon` (the same
bundle Icon Composer edits) and the palette out of the constants at the
top of the script, which mirror the CSS custom properties in
`site/index.html`. The four images land in `brand/`; `--install-card`
additionally copies the card to `site/social-card.png`, which Netlify
serves as the `og:image`. Nothing is fetched at run time; the Poppins
weights it needs are committed in `support/fonts/`.

**Cutting a release runs this** (step 6), and that is safe because the
output is **deterministic** — identical inputs give byte-identical PNGs.
A release that changed nothing about the artwork leaves the working tree
clean and there is nothing to commit. A diff appears only when the icon,
the palette or the tagline actually moved, which is exactly when you want
to notice. So: if `git status` is quiet after this step, that is the
expected result, not a sign it failed.

If it *does* produce a diff, look at the images before committing them —
the push deploys the card to a public URL.

Two things worth knowing about the card in particular:

- The original card was hand-made and has no source. The generated one
  is measured to match it — tile 260&nbsp;px at 108,185; wordmark Poppins
  **Medium 96**&nbsp;px; tagline Regular 33&nbsp;px on a 46&nbsp;px
  leading; domain line Medium 26&nbsp;px; rule 8&nbsp;px — and every text
  element now matches the original's ink coverage exactly. It is still
  **not** byte-identical: glyph advance widths accumulate slightly
  differently, so letters drift a pixel or two toward the end of a line.
  Background and rule are pixel-identical. Look at both before you commit.

  The brand uses Poppins **Regular and Medium only — no SemiBold**. That
  is measured from the original card, not assumed. Do not "correct" it to
  600 because `website/assets/style.css` sets `h1 { font-weight: 600 }`; the card
  is a separate artifact and was not rendered from that stylesheet.
- That file is public and every social platform that has scraped
  plantoir.app has it cached. Replacing it is an outward-facing change,
  not a refactor. Platforms re-scrape on their own schedule, so the old
  card can keep appearing in link previews for a while after deploy.

The two greens are not interchangeable and both appear on the card:
`--green-deep` (#2D6620) sets the wordmark, `--green` (#3E8C26) sets the
rule, the link, and the mark itself. The mark reads #3E8D26 rather than
the pure green in `icon.json` because the layer's translucency blends it
into the background — a rendering behaviour that cannot be recovered
from the JSON, so it is pinned as a constant in the script.

## Notes

- The PRI249 "Invalid qualifier: SOCIAL-EMOTIONAL LEARNING SKILLS"
  warning during publish is noise: the resource indexer misreads an
  example-content filename as a language qualifier. Harmless.
- GitHub's asset size limit (2 GB) is nowhere near a concern.
- With a valid Artifact Signing signature + timestamp, SmartScreen
  warnings fade as reputation accrues to the signing identity; the
  "Unblock" instructions on plantoir.app can be softened after the first
  signed release proves out on a fresh machine.

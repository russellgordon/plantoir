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
   remedy if anything is missing. Output lands in `windows-app\dist\PlantoirSetup.exe`
   (and `Plantoir-win-x64.zip`).
4. **Build the signed & notarized macOS bundle**:
   `cd mac-app; ./publish.sh -Sign`. Output lands in `mac-app/dist/Plantoir-macOS.dmg`.
5. **Tell Claude "cut the release."** It drafts teacher-friendly notes, adds the
   SHA-256 table, creates the GitHub Draft Release, uploads the assets, publishes
   the release, updates the site's version line, redraws the brand images, and pushes to `main`.

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
       winget install --exact --id JRSoftware.InnoSetup

   Per session: a plain `az login` as azure@russellgordon.ca — that user holds
   the "Artifact Signing Certificate Profile Signer" role on the
   `plantoir-signing` account directly (granted 2026-08-19), so no
   service-principal secret is involved. (The `plantoir-signing` app
   registration still exists and also holds the role, but the release flow no
   longer needs its secret.) The script preflights the tools and login, signs
   the binaries, compiles `installer.iss`, and signs `dist\PlantoirSetup.exe`
   with an RFC 3161 timestamp.

   Output: **`dist/PlantoirSetup.exe`** (and portable `dist/Plantoir-win-x64.zip`) + SHA-256.

4. **Build the signed macOS bundle**:

       ./publish.sh -Sign

   One-time tooling on the Mac:
   - Developer ID Application certificate installed in Keychain Access
   - Credentials stored in notarytool: `xcrun notarytool store-credentials "notarytool-profile" --apple-id <email> --team-id <team-id> --password <app-specific-password>`

   The script builds Release, signs dylibs and executables bottom-up with Hardened Runtime,
   creates a drag-and-drop DMG, signs the DMG, notarizes with Apple, staples the ticket,
   and verifies Gatekeeper acceptance.

   Output: **`mac-app/dist/Plantoir-macOS.dmg`** + SHA-256.

5. **Tag and release** — ask Claude to "cut the release". Since the branch
   model arrived (CLAUDE.md rule 6), a release starts by merging `dev` into
   `main`: the tag points at `main`, and the website commit the flow makes
   lands there too, so finish by merging `main` back into `dev`. The
   `cut-release` skill (`.claude/skills/cut-release/`) drafts teacher-friendly notes, computes
   SHA-256 hashes, creates a GitHub Draft Release, uploads the assets, publishes
   the release, updates `website/site.json`, redraws the brand card, rebuilds `site/`,
   and pushes to `main`.

   **The Windows binaries' signatures can be verified from the Mac** — no need
   to take "it's signed" on faith when the files arrive by hand. `brew install
   osslsigncode`, fetch Microsoft's root (`curl -sL "https://www.microsoft.com/
   pkiops/certs/Microsoft%20Identity%20Verification%20Root%20Certificate%20
   Authority%202020.crt"`, convert with `openssl x509 -inform DER`), then
   `osslsigncode verify -CAfile ms-root.pem -TSA-CAfile ms-root.pem
   PlantoirSetup.exe` and expect `Signature verification: ok`. Without the
   `-CAfile` flags it reports "failed" for a perfectly good signature, because
   the Mac has no Windows root store — the failure reason to read for is a
   missing issuer, not a bad digest. Azure Trusted Signing certs live ~3 days,
   so verify the timestamp line too (proven first on v1.0.0, 2026-08-19).

   Relatedly, `brand_images.py` output is deterministic in PIXELS but not in
   BYTES: a Pillow/zlib version shift re-encodes identical images into
   different files. If the release run shows the brand PNGs modified, compare
   pixels (`PIL.ImageChops.difference(...).getbbox()` is `None` when
   identical) before treating it as a real change — pixel-identical churn
   should be checked out, not committed (hit on v1.0.0).

   **Asset names are LOAD-BEARING and must never change**:
   `PlantoirSetup.exe` and `Plantoir-macOS.dmg`. plantoir.app's download cards point at
   `releases/latest/download/<asset-name>` — GitHub's evergreen URL that serves
   the newest release's asset, so teachers click Windows or macOS and get the
   file, no GitHub in sight.

6. **Deploy plantoir.app deliberately**: `python3 website/build.py --deploy`
   builds `site/` and publishes it to Netlify (delta upload; the token comes
   from the `containerized-quartz-netlify` Keychain item, the site id from
   `website/site.json`). The Netlify site is NOT connected to GitHub —
   pushing this repository deploys nothing, which is why this step exists.

## Bundle format

- **macOS**: A styled drag-and-drop disk image (`Plantoir-macOS.dmg`) containing `Plantoir.app` and an `/Applications` shortcut. The DMG is code-signed, notarized by Apple, and stapled with its ticket for offline Gatekeeper verification.
- **Windows**: An Inno Setup installer (`PlantoirSetup.exe`) configured for `PrivilegesRequired=lowest` (per-user installation to `%LOCALAPPDATA%\Programs\Plantoir`, requiring zero administrator rights). A portable zip (`Plantoir-win-x64.zip`) is also emitted.

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

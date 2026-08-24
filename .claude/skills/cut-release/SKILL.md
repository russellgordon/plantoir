---
name: cut-release
description: Cut a Plantoir GitHub release - drafts teacher-friendly release notes from the commits since the last tag, verifies the bundle's SHA-256 into the notes, tags, and publishes via gh. Run when the user says to cut/publish a release.
---

# Cutting a Plantoir release

You are drafting for TEACHERS, not developers. The release notes are the
only part of the process that needs judgement; everything else is
mechanical. `RELEASING.md` is the authoritative checklist —
this skill automates its steps 5–6 and the note-writing.

## Gather

1. Last release: `git describe --tags --abbrev=0` (if no tag exists,
   this is the first release — summarize the product, not the delta).
2. The story since: `git log <last-tag>..HEAD --pretty=format:'%s%n%b%n---'`
3. The bundle(s) to attach:
   - `mac-app/dist/Plantoir-macOS.dmg` (freshly built & notarized by `mac-app/publish.sh -Sign`)
   - `windows-app/dist/PlantoirSetup.exe` (freshly built & signed by `publish.ps1 -Sign`)
   - (Optional) `windows-app/dist/Plantoir-win-x64.zip` (portable edition)

   **A cut may carry one platform's assets only** — see step 5 and
   `RELEASING.md`, "Two platforms, one version series". The other platform's
   binary is added to the SAME release later, so nothing here needs redoing
   when it arrives.

   Confirm with the user that the SIGNED & NOTARIZED bundles exist; never attach
   an unsigned one to a public release. Compute each asset's hash yourself:
   `shasum -a 256 <asset>` or `(Get-FileHash <asset> -Algorithm SHA256).Hash.ToLower()`
   from the EXACT file being uploaded, never trusted from memory or logs.

   **When the asset is on the other machine** — the Windows bundle is built
   and uploaded from the PC — you cannot hash it here. Take the hashes from
   the cut sheet, SAY in your report that you did not compute them, and ask
   whoever uploads to re-hash on that machine and confirm. Never present a
   hash you did not compute as if you had.
   
   Asset names are LOAD-BEARING: `Plantoir-macOS.dmg` and `PlantoirSetup.exe`
   (and `Plantoir-win-x64.zip`), exactly — plantoir.app's download links resolve
   `releases/latest/download/<asset-name>`, so a renamed asset silently
   breaks the site. Refuse to attach an asset under any other name.

   The same evergreen URL is why a one-platform cut has to touch the site:
   the moment the new release becomes "latest", the missing platform's
   evergreen link 404s. See "Publish", step 2.
4. Confirm `<Version>` in `windows-app/Plantoir/Plantoir.csproj` matches
   the intended tag, and that the working tree is clean. Confirm you are on
   `main` with `dev` fully merged in (`git log main..dev` is empty) — the tag
   and the website commit both land on `main` (CLAUDE.md rule 6). After the
   website push, merge `main` back into `dev` so the branches do not drift.
5. Check `MARKETING_VERSION` in `mac-app/project.yml` against `<Version>` in
   the csproj. **A mismatch is a QUESTION, not automatically a stop** —
   corrected 2026-08-20, when this step still said the two move in lockstep.
   `RELEASING.md`'s "Two platforms, one version series" replaced that: the
   version names which CONTRACTS a build passes, so a platform that has not
   passed the new contracts keeps its old number until it does.

   **Decide it from the ASSETS this cut attaches, never from what the two
   files say.** The list you gathered in step 3 is the whole input; do not
   ask which platforms are "involved", ask which binaries are going up. Then
   exactly one of these holds:

   - **Every platform whose asset is attached must read the tag's number.**
     No exceptions and no judgement — an asset labelled anything else is a
     stop. This is the check that catches the real mistake: a signed bundle
     built before the bump.
   - **A mismatch is acceptable ONLY for a platform shipping no asset in
     this cut.** Its number is correct where it is, and lower. Do not "fix"
     it to match the tag — re-badging a binary that never ran the new
     contracts is the precise thing the policy forbids — and do not raise it
     "so the files agree", because the files disagreeing IS the record of
     which platform still owes its gate.
   - **A lagging number that is HIGHER than the tag is always a stop**,
     whether or not that platform ships. It means the bump landed without
     the release, and the next cut will silently reuse a number.

   **The catch-up cut has its own rule, and it is the one people get wrong.**
   When the lagging platform later joins a tag that already exists, it is
   shipping an asset — so the first bullet applies in full: its
   `MARKETING_VERSION` must have been raised to that tag's number, with its
   gate run and its suite green, BEFORE the bundle was built. The signal to
   check is the bundle itself rather than the file: read
   `CFBundleShortVersionString` out of the built `.app` (or `--version` from
   the exe) and compare it with the tag, because `project.yml` can be edited
   after a bundle is signed and the file will then lie about the artifact.
   Done first for the macOS DMG joining v1.1.0, 2026-08-20.

   (`project.yml` is the source; the Xcode project is generated from it, so
   edit `project.yml` and re-run `xcodegen generate`. `CFBundleVersion` is
   NOT a version to check against the tag — it is the derived build number,
   `git rev-list --count HEAD`, applied by `publish.sh`; `project.yml`
   carries only a placeholder for local builds.)
6. **Confirm the release target repository (`russellgordon/plantoir`).**
   The remote `origin` and `website/site.json` (`repo_url`) both point to
   `github.com/russellgordon/plantoir`. Confirm this with the user, then pass
   `-R russellgordon/plantoir` explicitly on every `gh` call. Verify the target
   first with `gh repo view russellgordon/plantoir` — if that fails, stop and
   say so rather than publishing.

## Write the notes

Style rules, in order of importance:

- **Normie-friendly**: a teacher who has never read a commit message
  must understand every line. "The sidebar no longer folds up after you
  create a course" — not "Reconcile TreeView ItemsSource in place".
- Group under at most three headings, in this order, omitting empty
  ones: **New**, **Improved**, **Fixed**.
- One line per item, plain sentences, no jargon, no file names, no
  commit hashes, no PR references.
- SKIP internal work entirely: refactors, test infrastructure, CI,
  release machinery, doc reshuffles, anything a teacher cannot observe.
  Many commits produce NO line — that is correct behaviour.
- Merge related commits into one line (three commits fixing the same
  sidebar bug are one bullet).
- Cover BOTH platforms when the release carries both assets; label
  platform-specific items "(Windows)" / "(macOS)" only when they truly
  apply to one side.
- **When only one platform ships, say so in the first line, plainly** —
  "macOS: no changes", or the reverse, and where the other platform's
  download currently comes from. `RELEASING.md` requires that sentence:
  it is the entire cost of keeping one version series, and it is cheaper
  than every support conversation under two.
- End with a **Downloads** section listing each attached asset, its
  size, and its SHA-256 in a table:

  | File | Size | SHA-256 |
  | --- | --- | --- |
  | Plantoir-macOS.dmg | 49.0 MB | `5708cc…` |
  | PlantoirSetup.exe | 62.1 MB | `043a1c…` |

  Below the table, one line: "The SHA-256 lets your IT department verify
  the download is genuine."

Show the drafted notes to the user for approval BEFORE tagging or
publishing anything.

## Publish (after approval)

1. **Create GitHub Release as DRAFT and upload assets first.**
   This avoids the 404 race condition where Netlify deploys the website before
   GitHub finishes receiving the binary assets:

```bash
# Create draft release
gh release create v<version> --draft -R <owner/repo> \
  --title "Plantoir <version>" --notes-file <notes.md>

# Upload all assets
gh release upload v<version> <assets...> -R <owner/repo>

# Publish the release (un-draft)
gh release edit v<version> --draft=false -R <owner/repo>
```

   `gh release view v<version>` resolves a DRAFT by tag name, so the upload
   works from the other machine without a release id. A draft does not create
   the git tag; if the other machine needs a real tag to build or verify
   against, push an annotated one yourself and target the draft at it.

2. **Update and deploy plantoir.app**:
   Set `version` and `released` in `website/site.json`, redraw brand images,
   rebuild, and push.

   **If this cut carries one platform only, fix that platform's download card
   in `website/pages/index.html` in the same commit.** The cards use GitHub's
   evergreen `releases/latest/download/<asset-name>` URL, which starts
   resolving to the NEW release the moment it publishes — and the release has
   no asset for the lagging platform, so that button 404s for every visitor on
   that OS. Pin it to the last release that HAS the asset
   (`releases/download/v<older>/<asset-name>`), and add one short note saying
   that platform is still on the older version.

   **Then un-pin it in the release that catches the platform up**, and delete
   the note. A pinned card keeps working forever, which is exactly why it is
   easy to forget: it serves an old version from a button that looks healthy.
   The comment beside the card in `index.html` says all of this too — first
   done for v1.1.0 (Windows only), 2026-08-20.

```bash
# Redraw brand images if needed
python scripts/brand_images.py --install-card

# Rebuild site
python3 website/build.py
python3 website/build.py --check

# Commit and push, then deploy — the Netlify site is NOT Git-connected,
# so pushing publishes nothing; the deploy is its own explicit step
git add website/site.json site/ brand/
git commit -m "Update website for v<version> release"
git push origin main
python3 website/build.py --deploy
```

`--deploy` fetches `https://plantoir.app` afterward on its own and confirms
the live version-note line matches `site.json` — watch its output for the
✅/⚠️/❌ line rather than assuming the push alone means teachers can see the
new version. A ❌ means the site did not pick up the deploy after several
retries; tell the user, point them at `https://app.netlify.com`, and do not
report the release as complete until `python3 website/build.py
--verify-deploy` comes back ✅. A ⚠️ (network problem reaching the site, not
a confirmed mismatch) is worth one retry of `--verify-deploy` before treating
it as a real problem.

**Redraw the brand images in the same commit as the version line.** After
editing `website/site.json` and rebuilding, and before tagging, run:

```
python scripts/brand_images.py --install-card
```

This draws the og:image, the profile photos and the Bluesky banner from
`mac-app/Plantoir.icon`, and installs the card to `site/social-card.png`
so the `--deploy` step publishes it with the rest of the site.

The output is deterministic, so **the normal outcome is no diff at all** —
`git status` stays quiet and you commit only the version line. Do not
report that as a failure or re-run it. Files change only when the icon,
the palette or the tagline moved since the last release.

If it does produce a diff, stop and show the user the changed images
before committing: `site/social-card.png` is a public, widely-cached
og:image, and a release push deploys it. Say plainly which files changed
and why you think they did. Commit them alongside the version line so the
card and the release ship together.

Stage by path — never `git add -A`. Other work may be in the tree.

See "Brand images" in `RELEASING.md`.

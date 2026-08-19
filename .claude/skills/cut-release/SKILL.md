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
   
   Confirm with the user that the SIGNED & NOTARIZED bundles exist; never attach
   an unsigned one to a public release. Compute each asset's hash yourself:
   `shasum -a 256 <asset>` or `(Get-FileHash <asset> -Algorithm SHA256).Hash.ToLower()`
   from the EXACT file being uploaded, never trusted from memory or logs.
   
   Asset names are LOAD-BEARING: `Plantoir-macOS.dmg` and `PlantoirSetup.exe`
   (and `Plantoir-win-x64.zip`), exactly — plantoir.app's download links resolve
   `releases/latest/download/<asset-name>`, so a renamed asset silently
   breaks the site. Refuse to attach an asset under any other name.
4. Confirm `<Version>` in `windows-app/Plantoir/Plantoir.csproj` matches
   the intended tag, and that the working tree is clean.
5. Confirm the mac side agrees: `MARKETING_VERSION` in `mac-app/project.yml`
   must carry the same version. `RELEASING.md` says the two move
   in lockstep — one product, one version series — so a mismatch is a stop,
   not a note. (`project.yml` is the source; the Xcode project is generated
   from it, so edit `project.yml` and re-run `xcodegen generate`.)
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

2. **Update and deploy plantoir.app**:
   Set `version` and `released` in `website/site.json`, redraw brand images,
   rebuild, and push:

```bash
# Redraw brand images if needed
python scripts/brand_images.py --install-card

# Rebuild site
python3 website/build.py
python3 website/build.py --check

# Commit and push (Netlify deploys automatically)
git add website/site.json site/ brand/
git commit -m "Update website for v<version> release"
git push origin main
```

**Redraw the brand images in the same commit as the version line.** After
editing `website/site.json` and rebuilding, and before tagging, run:

```
python scripts/brand_images.py --install-card
```

This draws the og:image, the profile photos and the Bluesky banner from
`mac-app/Plantoir.icon`, and installs the card to `site/social-card.png`
so Netlify deploys it with the rest of the push.

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

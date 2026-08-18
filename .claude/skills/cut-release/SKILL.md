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
3. The bundle(s) to attach — normally `windows-app/dist/Plantoir-win-x64.zip`
   freshly produced by `publish.ps1 -Sign` (confirm with the user that
   the SIGNED bundle exists; never attach an unsigned one to a public
   release). Compute each asset's hash yourself:
   `(Get-FileHash <zip> -Algorithm SHA256).Hash.ToLower()` — from the
   EXACT file being uploaded, never trusted from memory or logs.
   Asset names are LOAD-BEARING: `Plantoir-win-x64.zip` and
   `Plantoir-macOS.zip`, exactly — plantoir.app's download links resolve
   `releases/latest/download/<asset-name>`, so a renamed asset silently
   breaks the site. Refuse to attach an asset under any other name.
4. Confirm `<Version>` in `windows-app/Plantoir/Plantoir.csproj` matches
   the intended tag, and that the working tree is clean.
5. Confirm the mac side agrees: `MARKETING_VERSION` in `mac-app/project.yml`
   must carry the same version. `RELEASING.md` says the two move
   in lockstep — one product, one version series — so a mismatch is a stop,
   not a note. (`project.yml` is the source; the Xcode project is generated
   from it, so edit `project.yml` and re-run `xcodegen`.)
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
  | Plantoir-win-x64.zip | 58.5 MB | `043a1c…` |

  Below the table, one line: "The SHA-256 lets your IT department verify
  the download is genuine."

Show the drafted notes to the user for approval BEFORE tagging or
publishing anything.

## Publish (after approval)

1. Update the site's version line. It is NOT in the HTML any more —
   `site/` is generated. Set `version` and `released` in
   `website/site.json`, then rebuild and check:

```
python3 website/build.py
python3 website/build.py --check
```

   Commit `website/site.json` and the regenerated files under `site/`
   together. If `--check` reports a screenshot that has never been taken,
   stop and say so rather than publishing a page with a placeholder on
   it; `website/README.md` explains the capture run.

   **This rebuild ALWAYS happens.** It is what puts the new version and
   the new download URLs on the page, and it takes seconds.

2. **Ask whether to re-shoot the screenshots. The default is no.**

   Capturing them drives the real app for the better part of an hour,
   needs the Mac left alone, and briefly switches the machine's
   appearance. It is worth it when the interface a teacher sees has
   visibly changed since the last release, and a waste of an hour when
   it has not — most releases do not need it.

   Help the user decide rather than making them guess. Look at what has
   changed in the views since the last tag:

```
git diff --stat <last-tag>..HEAD -- mac-app/QuartzTeachers/Views   support/example_content
```

   Say what you find — "nothing under Views has changed since v1.2, so
   the screenshots are still accurate" is an answer they can act on —
   then ask. On a yes:

```
python3 website/shots/capture.py --app      # the app windows
python3 website/shots/capture.py --sites    # the class websites
```

   Run only the half that changed: app-interface work needs `--app`,
   changes to the example course content or to Quartz need `--sites`.
   Look at the results before committing them, and commit them as their
   own change rather than folding them into the release commit — a
   screenshot that turns out wrong should be revertable without
   unpicking the version bump.

   Never run the bare `capture.py` with no flags during a release: it
   also provisions courses and publishes the demo sites, which is
   first-run setup rather than anything a release needs.
3. Tag and release:

```
git tag v<version>
git push origin main v<version>
gh release create v<version> <assets...> -R <owner/repo> \
  --title "Plantoir <version>" --notes-file <notes.md>
```

`-R <owner/repo>` is the repository settled in Gather step 6 — always
explicit, never left to the remote.

The push redeploys plantoir.app automatically (Netlify watches `site/`),
and the evergreen download links now serve the new assets — nothing
manual remains for the site. Remind the user only of: the mac asset (see
below), and — once WinSparkle lands — the appcast entry.

**The mac asset is made BY HAND today.** There is no mac packaging or
signing script in this repository — `publish.ps1` has no counterpart, and
`mac-app/Vendor/fetch-llama.sh` is the only script on that side. So
whoever builds `Plantoir-macOS.zip` archives and signs it themselves, and
two things must be true before they do:

- `mac-app/Vendor/llama` must be fetched first (`mac-app/Vendor/fetch-llama.sh`).
  The binaries are gitignored, `project.yml` copies the folder into the
  bundle as-is, and an empty folder builds without complaint — so an app
  built on a fresh clone ships an assistant that cannot start.
- the asset must be named exactly `Plantoir-macOS.zip`, per the rule in
  Gather step 3.

If no such bundle exists, do not invent one: publish the Windows asset
alone and say the mac asset is outstanding.

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

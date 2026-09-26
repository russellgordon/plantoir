# Releasing Plantoir

**One product, one version series, one GitHub release carrying both platforms'
assets.** The product version lives in ONE place — `<Version>` in
`windows-app/Plantoir/Plantoir.csproj` — and `MARKETING_VERSION` in
`mac-app/project.yml` must say the same number. The About panels read them and
the git tag must match.

> **Which repository?** plantoir.app's download links resolve against
> `github.com/russellgordon/plantoir`, which matches `origin`. Pass
> `-R russellgordon/plantoir` explicitly to every `gh` command — a release
> published to the wrong repository leaves the site's evergreen links serving
> nothing.

## Two platforms, one version series — and when they lag

Decided 2026-08-20, the day Windows 1.1.0 was ready while the mac had no code
changes at all. The rule that resolves every case of "which number goes on
this build":

**The version number names which CONTRACTS the build passes, never "what
changed on this platform."** The two apps are coupled through
[`contracts/`](contracts/README.md): a contract vintage is part of the
version, and a teacher saying "I'm on 1.1.0" must pin down exactly one set of
sentences and rules regardless of their OS. Three consequences:

- **A platform may ship a version the other is not ready for.** The tag goes
  up carrying the ready platform's assets; GitHub releases accept assets
  added later, so the other platform's binary JOINS the same release when it
  qualifies. Until then, plantoir.app's two download buttons simply point at
  different releases — each honestly labelled. (If the catch-up work turns
  out to change behaviour, it becomes the next patch version instead, and
  the ready platform re-attaches unchanged.)

  **That labelling is not optional, it is a broken download otherwise.** Both
  cards normally use GitHub's evergreen `releases/latest/download/<asset>`
  URL, which begins resolving to the new release the instant it publishes —
  so the lagging platform's button 404s until its binary joins. Pin that card
  to the last release that has the asset, note the older version on it, and
  **un-pin it when the platform catches up**: a pinned card keeps serving an
  old version from a button that looks perfectly healthy, which is why the
  un-pinning is the half that gets forgotten. Done first for v1.1.0
  (Windows only), 2026-08-20; the procedure is in the `cut-release` skill.
- **"No code changes" does not exempt a platform from the gate.** A mac DMG
  gets the 1.1.0 label only when a mac session has made its suite green
  against the 1.1.0 contracts. An unchanged binary re-badged with a new
  number would claim contracts it was never tested against.

  **Worked example, 2026-08-20 — the gate this rule was written for, run.**
  The mac's list was: implement the teacher-made-link explainer case, retire
  the three obsolete WSL-setup cases, run `./verify.sh` against the changed
  shared scripts, and do the two verifications Windows asked for. All
  four came back green and **none of them required a behaviour change**, so
  the DMG joined v1.1.0 rather than becoming 1.1.1. The verifications are
  the part worth copying: both were "prove it against the real app", and
  both found something a code read alone would have got wrong — the
  assistant's warm-up race IS present on the mac (measured: 1.7 s warm
  against 3.1 s racing it) but cannot produce the failure Windows fixed, and
  the run-transcript gap that mirrors the Windows one is unreachable here
  because every task launches through `/bin/bash`. A gate that only asks
  "does it compile" would have passed both without learning either.

  **A behaviour DID change before that cut, and it did not move the number
  — here is the test that decides such cases.** Testing the candidate turned
  up the mac blocking its main thread while setting up a new working folder,
  which Windows 1.1.0 already handles properly. Ask: **does this bring the
  lagging platform UP TO the number, or does it change what the number
  means?** Windows shipped 1.1.0 with the good behaviour, so the mac lacking
  it was the mac being behind 1.1.0 — fixing it makes the two agree on what
  1.1.0 is, and 1.1.0 is still the right label. The answer would be the
  opposite for a change neither platform has shipped: that one earns the
  next number, because a teacher on Windows 1.1.0 would not have it.
- **Release notes say "macOS: no changes" (or the reverse) plainly** when a
  platform ships under a new number without behaviour changes. That sentence
  is the entire cost of keeping one series, and it is cheaper than every
  support conversation under two.

**Build numbers** exist to uniquely name BITS — the trail prints
"Plantoir 1.1.0 (build)" into problem reports, and two artifacts must never
share a name. So: derive, never hand-maintain — `git rev-list --count HEAD`
at bundle-build time — bump on every build that leaves the dev machine
(every DMG and installer, including ones handed to a tester), and never
reset the count, across marketing versions, forever.

**The mac does this in `publish.sh`**, which passes
`CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD)` to `xcodebuild`;
`project.yml` carries `"0"` as a placeholder for local builds, and
`Info.plist` reads `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`
rather than repeating their values. **This paragraph claimed the mac
"follows this today" from the day it was written until 2026-08-20, and it
was not true**: both plist keys were the literal `1.0.0`, so every 1.0.0
build also reported build 1.0.0 and no two artifacts could be told apart.
Found while qualifying the mac for v1.1.0. The Windows bundle should adopt
the same number as its version's fourth field when convenient (its trail
currently prints the patch digit, which conflates two ideas).

## Landed since v1.3.1 — ships in the next release

Features that are **complete, merged to `dev`, and waiting only for a tag**.
This is a reading aid, not a source of truth: the release notes are drafted
from the commits since the last tag, so anything merged is carried whether or
not it is listed here. What the list buys is the thing commits do not say —
whether a teacher will notice, and whether both platforms have it.

**Clear this list when the tag goes up**, in the same commit that moves the
version line. A list that survives its own release is worse than no list.

| Landed | What a teacher sees | Platforms | Log |
|---|---|---|---|

## Warnings the release notes MUST carry

Separate from the table above, and it has to be: that table is for what a
teacher gains, and this is for what they must DO — the sentences a teacher has
to read before updating, not after. The notes are drafted from the commits, and
a caution buried in a commit body is a caution that gets summarised away.

Same rule as the table: **clear this list when the tag goes up**, in the same
commit that moves the version line.

| Added | The warning | Why it cannot be left out |
|---|---|---|

## The short version

For future-you, mid-school-year, who remembers nothing. The whys are below.

1. **Everything merged and green?** Both sides on `main`; `dotnet test` passes
   in `windows-app/`; the mac unit suite passes. **Then open
   `windows-app/Plantoir.Tests/NamedGapLedger.cs`** — green can carry named
   gaps, and step 2 says what to check in it. Then **actually publish a
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
   Since #204 it also signs the updater inside the app item by item and REFUSES
   a bundle whose updater is not on the app's own team, before notarization.
   Since #312 it also fetches and signs the website builder's helper programs
   (Vendor/fetch-helpers.sh, release/sign-helpers.sh), and the DMG is about
   **410 MB** (ULMO; 410,488,446 bytes at the #312 rehearsal) rather than 59 MB — the notarization upload takes
   correspondingly longer ("The update feed (macOS)" → "Deltas" for why
   updates stay small).
5. **Tell Claude "cut the release."** It drafts teacher-friendly notes, adds the
   SHA-256 table, creates the GitHub Draft Release, uploads the assets, publishes
   the release, **builds and signs the mac's update feed from the exact DMG it
   uploaded** (only after the release is public — "The update feed (macOS)"
   below), updates the site's version line, redraws the brand images, and pushes to `main`.

## The checklist, with the reasons

1. **Version.** `<Version>` in `windows-app/Plantoir/Plantoir.csproj` and
   `MARKETING_VERSION` in `mac-app/project.yml`. `project.yml` is the source on
   the mac side, so re-run `xcodegen generate` after changing it.
2. **Full test pass**: `dotnet test Plantoir.Tests` and the mac unit suite, plus
   a hand smoke of create → preview → publish on a real course.

   > **Check the TOTALS line before calling it green**, or use
   > `.\run-tests.ps1`, which reads it for you. `dotnet test` exits 1 for a
   > failing test, for a dead test host and for a project that did not compile,
   > and a release is exactly the moment that distinction gets waved through.

   > **A green Windows suite can carry NAMED GAPS, so read the ledger too.**
   > Since 2026-09-18, `windows-app/Plantoir.Tests/NamedGapLedger.cs` lets a
   > contract key the Windows app has not built yet be held open by name
   > instead of sitting red — each entry carrying the key, its GitHub issue and
   > its MILESTONE. **Open that file before cutting and check every entry: its
   > milestone must be LATER than the release you are cutting, and its issue
   > must still be open.** An entry whose milestone IS this release means the
   > work is owed NOW — build it, or move the issue to a later milestone as a
   > deliberate decision. Never cut over one. The boundary and the reasoning
   > are in `contracts/README.md` → "Named gaps"; the point of checking here is
   > that this is the one moment the milestone on an entry means anything.

   > The hand smoke is **not optional, and not a formality**. The bundle carries
   > the whole toolchain recipe (Dockerfile, `scripts/`, `patches/`, `contracts/`,
   > launchers)
   > inside the app, and the xUnit suite deliberately never touches Docker — so
   > a green test run says nothing about the thing teachers actually run.
   > `verify.sh`, the real toolchain gate, is bash and expects `docker` on
   > `PATH`, which does not hold on Windows where Docker Engine lives in WSL2.
   > **On Windows the hand smoke is the only DOCKER verification there is.**
   > (It is no longer the only toolchain verification: since 2026-09-07
   > `PythonToolchainTests` runs EVERY shared `scripts/test_*.py` file inside
   > `dotnet test` — the same files `verify.sh` runs on the mac, which nothing
   > ran here before. They need no Docker, so they cover the shared Python and
   > say nothing about the image. It DISCOVERS them rather than listing them,
   > so no number is kept in step by hand; this said "all fifteen" when there
   > were fifteen, on 2026-09-07, and there are eighteen as of 2026-09-09.)

   **If the release changes anything under `scripts/`, the Dockerfile or a
   launcher, run the publishing verifier rather than smoking it by hand** —
   `verify-deploy.ps1` on Windows, `./verify-deploy.sh` on the mac. It is the
   automation this step used to ask for in prose: it publishes to all three
   destinations (Netlify, Cloudflare Pages, a folder — different code paths
   each) and every pairing, then FETCHES EACH SITE BACK and reads it, which is
   the only way to catch the two failures that have actually shipped here — a
   preview build reaching a published site, and a publish that reported success
   having copied the wrong thing or nothing.

   > **Require a run with nothing skipped.** A destination with no credentials
   > on the machine is skipped and the run still exits 0 — correct for everyday
   > use, wrong for a release. Read the summary line: `passed, failed, skipped`.
   > A cut is the moment "Cloudflare was skipped on that laptop" stops being
   > acceptable, so get the credentials on the machine and run it again.
   >
   > It needs three credentials, the network and about twenty minutes, and it
   > **creates real, globally unique sites that nothing deletes** — so no suite
   > runs it and none should. Delete the sites it made when you are done.
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

   The script builds Release, checks the BUILT bundle's update keys
   (`release/check-update-keys.sh`: the feed, the public key, ask-first), signs
   the updater's own code item by item (`release/sign-updater.sh`: Autoupdate,
   Updater.app, the framework last — never `--deep`, never the app's
   entitlements), then dylibs and executables bottom-up with Hardened Runtime,
   then the app; refuses unless every updater item and the app are on the
   app's own team with the runtime (`release/check-signatures.sh` —
   `codesign --verify --deep --strict` cannot see a helper left ad-hoc); then
   creates a drag-and-drop DMG, signs the DMG, notarizes with Apple, staples the ticket,
   and verifies Gatekeeper acceptance.

   **Before the first `-Sign` of a cut, run the two release test files** —
   `python3 mac-app/release/test_release_signing.py` and
   `python3 website/test_update_feed.py`. Both are macOS-only, sign only
   ad-hoc or with a throwaway key, and are in no suite. The positive half of
   the team check (a Developer ID bundle passing) is not provable ad-hoc; the
   dress rehearsal below measured it once.

   **Do not rebuild, re-sign or re-staple the DMG after this step** — the
   update feed is signed against its exact bytes (publish.sh says so too).

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

## The update feed (macOS)

Since #204 a released Plantoir on a Mac asks
`https://plantoir.app/updates/macos.xml` once a day for a new version. The
rules a teacher is promised are `contracts/shared-rules.json` → `appUpdates`;
the app's side is `documentation/09-mac-app.md` → "Updating itself". This is
the release side.

- **Where it lives:** `website/updates/macos.xml`, committed, copied into
  `site/updates/` byte for byte by `website/build.py`. One file per platform
  (Windows adds `updates/windows.xml` with NetSparkleUpdater, and its own
  `.signature` file), never a GitHub release asset — `releases/latest/download`
  404s whenever a platform lags.
- **Signed with the `plantoir-macos` key**, the feed AND each download. The key
  lives in this Mac's Keychain (backed up in Russell's Passwords app); Sparkle's
  `generate_appcast` and `sign_update` read it — the Keychain asks, once for each
  tool (so twice a cut) — answer **Allow**, not "Always Allow" — and nothing prints it. The public half is `SUPublicEDKey` in
  `mac-app/project.yml`. A re-serialised feed breaks its signature, and the app
  then refuses it: silently on the daily check.
- **Built only at a cut, from the EXACT DMG uploaded, and only AFTER the
  release is published** — `python3 website/update_feed.py macos --version <v>
  --dmg mac-app/dist/Plantoir-macOS.dmg --notes <approved notes>
  [--required-warning]`. It refuses a DMG of another version, prepends this
  release's notes to the cumulative `website/updates/macos-notes.html`, signs,
  verifies, and checks the new item points at `…/releases/download/v<v>/
  Plantoir-macOS.dmg` with the DMG's length. **Order is load-bearing**: a feed
  deployed before its download exists offers every teacher an update that 404s.
- **Deltas, since #312 — which REVERSED #204's decision.** #204 rejected
  deltas (`--maximum-deltas 0`) "to save part of a ~59 MB download once a
  release"; since #312 the DMG carries the website builder's helper programs
  and starting disk and is ~410 MB, so without deltas every update would be a
  410 MB download, which defeats the reason the payload was allowed into the
  app at all (Russell's decision on #312 relies on it). Measured with Sparkle
  2.9.6's `BinaryDelta`: between the two signed #312 rehearsal builds (one
  Swift string apart, every helper re-signed) the delta was **106,054 bytes**,
  and applied, gave build 2 byte for byte; between v1.3.1 and #204's
  rehearsal build it was ~3.7 MB with or without the 467 MB payload inside both apps (3,658,602 B without, 3,658,626
  B with; 3,733,870 B with the four programs' signatures changed). So
  `update_feed.py` now asks for deltas from the **three newest builds in the
  feed** — not the newest three tags: releases before Sparkle and Windows-only
  tags are not in the feed, and no app older than the feed can ask for a
  delta. What that costs at the cut:
  - **Each earlier DMG is downloaded** from the address its own feed item
    gives — the exact bytes teachers installed, so no copy needs keeping — and
    checked for length and build: up to 3 × ~410 MB, plus
    `~/Library/Caches/Sparkle_generate_appcast`, which can grow to a few GB and
    may be emptied afterwards.
  - **Each `.delta` lands beside the DMG** (`mac-app/dist/Plantoir<new>-<old>.delta`)
    and **must be uploaded to the SAME release** as the DMG, BEFORE the feed is
    deployed. `build.py --deploy`'s live check follows every delta the newest
    item offers, and refuses a missing one: Sparkle would fall back to the
    full download without a word.
  - `generate_appcast` rewrites the item of every archive it is given —
    measured: the earlier item's download moved to the NEW release and lost
    its notes, even with `--versions` — so `update_feed.py` puts every earlier
    item back exactly as it was, signs the feed again with the same key (the
    Keychain asks once more), and refuses the cut if any earlier item still
    differs.
  - **v1.4.0, the first release with Sparkle, has no deltas**: nothing before
    it is in the feed. Its teachers download the whole DMG once, by hand; the
    saving starts with the release after it.
- **A REQUIRED warning makes the release important.** Pass `--required-warning`
  when "Warnings the release notes MUST carry" has a row for this release: the
  update window then has no Skip and no Remind Me Later, and the notes carry
  every release newer than the teacher's own, so skipping a release never
  loses its warning. A later release keeps the earlier one important for
  teachers still below it, by itself.
- **A Windows-only cut leaves `macos.xml` alone**, and so does any cut that
  attaches no mac DMG. `build.py --deploy` refuses when the feed's newest
  version is not `MARKETING_VERSION` — after a mac cut the two agree, and a
  Windows-only cut moves neither.
- **After deploying**, `--deploy` (and `--verify-deploy`) fetch the live feed,
  compare its SHA-256 with `site/`, and follow its newest download to a 200 of
  the right length. **Do not report a mac release complete until that line is ✅.**
- **A release that publishes a DMG without updating the feed ships an update
  nobody is offered.** Teachers on v1.3.1 or earlier — the last release without an updater — have no updater at all and
  install the first release that carries one by hand.

## The dress rehearsal (#204 — once, before the first release with an updater)

Two real, signed builds, one updating to the other, in a **throwaway STANDARD
(non-admin) macOS account** that Russell creates for it and deletes after —
so nothing touches his own defaults, window state, working folders or activity
log (the plan review's H2), and so the administrator-password path a school
Mac meets is measured rather than read from source. Tags: **[LOCAL]** nothing
leaves the Mac · **[IDENTITY]** Russell's Developer ID, notarytool or the
`plantoir-macos` key — his word first · **[OUTWARD]** public — his word first,
at that moment.

**Russell's own `/Applications/Plantoir.app` is NEVER touched** (the slice-2
review's H1). The rehearsal builds are installed into their own folder,
`/Applications/Plantoir Rehearsal/`, made with `sudo` so it is root-owned: a
standard account cannot write it, which is exactly what makes the updater ask
for an administrator — the case being measured — while his app stays where it
is. Installing over `/Applications/Plantoir.app` instead would put an
issue-branch build, with the same bundle identifier, in the path everything in
HIS account opens (Launchpad, Spotlight, any scheduled publish set from it)
until the cleanup, and the cleanup would then leave him with no Plantoir at
all. The builds keep the real bundle identifier on purpose: the updater keys
on it, and what is rehearsed must be what ships. The rehearsal version string
and the `…-REHEARSAL.dmg` name already say what they are.

**The standard account's first run is a real first run** (the slice-2
review's M2): it has none of this Mac's tools, its own Colima virtual machine
and its own image, and it downloads and builds all of them the first time a
preview is asked for — plan on several minutes, most of it waiting. What was
measured on this Mac, 2026-09-25: the image built with no layer cache in 60.6
seconds (`./verify.sh --no-cache`, 45 steps, the base image already present —
a new account's VM also has to download that base image, which was NOT
measured); `colima start` on a first run takes about 40 seconds
(`documentation/09-mac-app.md`). The tool download was not measured here,
where the tools come from Homebrew. Start the first preview before anything
else in the account, and time it: that number belongs in this paragraph. Its virtual machine sees only its own
containers, and Russell's containers hold their host ports whether or not a
preview is open (measured 2026-09-25: ten `teaching-quartz-*` containers on
8101–8254). The rehearsal's daemon cannot see them, so it may pick a block he
holds — and then `localhost:<port>` in the rehearsal browser answers from HIS
container, showing his real course. So R0 records his ports and V2 checks the
preview shows EXC2O; quitting Plantoir in his account releases its containers
if he prefers (Colima itself is never stopped — CLAUDE.md rule 7).

**The rehearsal build is reachable from Russell's account until C2**, because
`/Applications` is shared by every account: Spotlight and Launchpad list two
"Plantoir"s, and a launch by bundle identifier — clicking a scheduled
publish's notification while Plantoir is closed, say — can open the rehearsal
copy, whose build number is higher. An accidental launch would run an
issue-branch build against his real folders and, since it has an updater,
write `SU…` keys into his real defaults. So from R6 to C2 **Russell opens
Plantoir only from his Dock**, and R0/C3 record and re-check his defaults and
Spotlight's list.

| Step | Tag | What |
|---|---|---|
| R0 | LOCAL | Record Russell's app: `defaults read /Applications/Plantoir.app/Contents/Info.plist CFBundleShortVersionString` and `CFBundleVersion`, and `codesign -dvvv /Applications/Plantoir.app 2>&1 \| grep CDHash=` — written down, for C3. Also written down: `defaults read ca.russellgordon.Plantoir 2>/dev/null \| grep -c '"\?SU'` (0 on 1.3.1, which has no updater), `mdfind "kMDItemCFBundleIdentifier == 'ca.russellgordon.Plantoir'"` (his copies today), and `DOCKER_HOST=unix://$HOME/.colima/default/docker.sock docker ps --format '{{.Names}} {{.Ports}}'` (the ports his containers hold). Russell creates a standard account of his choosing and writes its short name down here as `<account>` (this run: `plantoir`); C2 and C3 use that name. |
| R1 | IDENTITY | In Russell's account, on the issue branch: `./publish.sh -Sign --rehearsal-feed https://plantoir.app/updates/rehearsal-204/macos.xml` → build **A** (version `<v>-rehearsal.<build>`, `dist/Plantoir-macOS-REHEARSAL.dmg`; keep a copy as A). Record build, size, SHA-256, the notarization id. **The positive team check, and must-fail (b):** the run passing `check-signatures.sh` is the first. Then, BEFORE R2 (whose `publish.sh` run `rm -rf`s `mac-app/build/`): `ditto mac-app/build/Plantoir.app /tmp/r1b/Plantoir.app`, and with `ID` the identity publish.sh printed: `codesign --force --sign - --options runtime /tmp/r1b/Plantoir.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate`; `codesign --force --timestamp --options runtime --sign "$ID" /tmp/r1b/Plantoir.app/Contents/Frameworks/Sparkle.framework`; `codesign --force --timestamp --options runtime --entitlements mac-app/QuartzTeachers/QuartzTeachers.entitlements --sign "$ID" /tmp/r1b/Plantoir.app`; then `mac-app/release/check-signatures.sh /tmp/r1b/Plantoir.app` must exit 1 naming `Autoupdate` twice (WRONG TEAM and NO SECURE TIMESTAMP) and nothing else. Delete `/tmp/r1b` after. |
| R2 | IDENTITY | One commit later, build **B** the same way. Then `rm -rf mac-app/build` so no Release build is left registered with Launch Services in his account. |
| R3 | IDENTITY | Twice, A first then B: `python3 website/update_feed.py macos --version <A's or B's own version, the "-rehearsal.<build>" string> --dmg <that DMG> --notes <a short notes file> --rehearsal website/updates/rehearsal-204/macos.xml --download-prefix https://github.com/russellgordon/plantoir/releases/download/v<v>-rehearsal-204/` — B's run with `--required-warning` and a fake warning in its notes, so the feed holds both items and both sections of notes. `--version` must be the rehearsal string or the DMG is refused as "built before the version was raised" (which here only means the wrong string was typed). Both items name the same download address, and only B is uploaded: harmless, since A is the version installed and never offered. The Keychain asks twice each run — **Allow**, not "Always Allow". Never committed (`.gitignore`). |
| R4 | OUTWARD | `gh release create v<v>-rehearsal-204 --prerelease --target <the issue branch's commit> -R russellgordon/plantoir` with B's DMG (`Plantoir-macOS-REHEARSAL.dmg`). `--target` keeps the tag off `main`. Then V9. |
| R5 | OUTWARD | From a worktree at `origin/main`: `python3 website/build.py`, drop the rehearsal feed into `site/updates/rehearsal-204/macos.xml` (not committed), `python3 website/netlify_deploy.py`; `curl` it back, SHA-256 equal. |
| R6 | LOCAL | Russell, in his account: `sudo mkdir "/Applications/Plantoir Rehearsal"` and `sudo ditto <A>/Plantoir.app "/Applications/Plantoir Rehearsal/Plantoir.app"`. From now until C2, Russell opens Plantoir in his own account only from his Dock — never Spotlight, Launchpad or a notification. Then, logged in as the rehearsal account: open it from THAT path (never by name), let the first run finish (above), and make a scratch working folder `~/rehearsal-work` with the example course (the wizard's EXC2O). |
| V1 | LOCAL | Check for Updates…: B offered as important — no Skip, no Remind Me Later — B's notes shown and A's hidden (screenshot). Trail: `update found`. |
| V2 | LOCAL | **The administrator prompt comes at "Install Update"**, while the update is being extracted and before "Ready to Install" (the review's L5; `SPUCoreBasedUpdateDriver.m` :235 → `SPUInstallerDriver.m` :468-484). Press Install Update and **cancel** the prompt → our `needsAdministrator…` notice, trail `update stopped` [4007]. Check again, start a preview BUILD of EXC2O section 1 — confirm the page that appears is EXC2O's, not one of Russell's courses (the port note above) — press Install Update and give the password → Ready to Install → Install and Relaunch while the preview is still building → our held notice naming the preview build; the menu item brings it back; when the preview answers, Plantoir restarts by itself as B. Trail: `update answered`, `update held…`, `update installing … now that it is no longer …`, then `app updated … by its own updater`. |
| V3 | LOCAL | **Reinstall A** — from Russell's account, with Plantoir quit in the rehearsal account: `sudo rm -rf "/Applications/Plantoir Rehearsal/Plantoir.app"`, then R6's `sudo ditto`, then `codesign --verify --deep --strict` on it and read its version (a `ditto` over B would MERGE, leaving B's files in A and breaking its seal). Schedule EXC2O to a FOLDER destination (nothing public) two minutes ahead; once `pgrep -f run-scheduled-deploy` shows it, Install and Relaunch → held "…on its schedule" → the run finishes → B. While the run posts its notification, `NSWorkspace` running applications does not list it (doc 09 → the Quit-event caution). |
| V4 | LOCAL | **Reinstall A** — from Russell's account, with Plantoir quit in the rehearsal account: `sudo rm -rf "/Applications/Plantoir Rehearsal/Plantoir.app"`, then R6's `sudo ditto`, then `codesign --verify --deep --strict` on it and read its version (a `ditto` over B would MERGE, leaving B's files in A and breaking its seal). Install Update, and at "Ready to Install" press ⌘Q with nothing running: A quits, B is installed without relaunching. **V4b:** the same while a scheduled run is going — the quit SETS IT ASIDE: A is still A afterwards, the run completes, the trail says `update set aside`, and the next check offers B again. This is the one thing about the stand-down only a real installer can show. |
| V5 | LOCAL | On installed B: `codesign --verify --deep --strict`; `spctl -a -vv -t exec` (accepted, Notarized Developer ID); no quarantine; `Autoupdate` on the app's team; and, **from Russell's admin account** (`log` refuses some subcommands to a standard one; the unified log is system-wide), `log show --last 15m --predicate 'process == "Autoupdate"'` has no "Skipping atomic rename/swap". |
| V6 | LOCAL | Run A from its mounted DMG; Check → Sparkle's own "…read-only or a temporary location" window; trail `update stopped` [1003]. |
| V7 | LOCAL | `".../Plantoir Rehearsal/Plantoir.app/Contents/MacOS/Plantoir" --write-contracts <tmp>` and `--mcp-stdio ~/rehearsal-work` (initialize, close stdin): no `Autoupdate`/`Updater` process, `SULastCheckTime` unchanged. |
| V8 | LOCAL | The Debug build: `SUFeedURL` empty, no Check for Updates… item. |
| V9 | LOCAL (read) | After R4: `curl -sI https://github.com/russellgordon/plantoir/releases/latest/download/Plantoir-macOS.dmg` still 302s to the last real release. |
| V10 | LOCAL | In the rehearsal account: `defaults write ca.russellgordon.Plantoir SUEnableAutomaticChecks -bool false`, delete `SULastCheckTime`, launch A: no check; the menu item still works — the support page's IT opt-out, confirmed. |
| C1 | OUTWARD | `gh release delete v<v>-rehearsal-204 --cleanup-tag --yes -R russellgordon/plantoir`; on every clone `git tag -d v<v>-rehearsal-204` (a stray tag would make the next cut's `git describe` start from it; `git fetch --prune-tags` alone prunes nothing, and with `--prune` would also delete local-only tags, so it is not used). In R5's worktree: `rm -rf site/updates/rehearsal-204` (`build.py` never clears `site/`), then `python3 website/netlify_deploy.py`, then `git worktree remove` it. |
| C2 | LOCAL | In the rehearsal account: quit Plantoir (which rests its builder) and **log out**, which stops its virtual machine and its launchd jobs; from Russell's account `pgrep -U <account>` (the name R0 wrote down) must then print nothing. Russell deletes the account in System Settings choosing **"Delete the home folder"** (otherwise its `~/.colima` disk and tools stay in `/Users/Deleted Users`). Then `sudo rm -rf "/Applications/Plantoir Rehearsal"`, both DMGs and the kept copy of A, `website/updates/rehearsal-204/`, and `~/Library/Caches/Sparkle_generate_appcast` in his account. iTerm to the front. |
| C3 | LOCAL (read) | **The end state, checked rather than asserted:** `git ls-remote --tags origin \| grep rehearsal` is empty; `gh release view v<v>-rehearsal-204 -R russellgordon/plantoir` fails as not found; `curl -sI https://plantoir.app/updates/rehearsal-204/macos.xml` is 404; `id <account>` fails and `dscl . list /Users` has no `<account>` (the name R0 wrote down); `/Users/Deleted Users` has nothing of it; `/Applications/Plantoir Rehearsal` is gone; `mdfind "kMDItemCFBundleIdentifier == 'ca.russellgordon.Plantoir'"` lists no rehearsal path (only what R0 listed); the `SU…` count in his defaults is what R0 wrote down; and **Russell's `/Applications/Plantoir.app` has the version, build and CDHash R0 wrote down.** If any of those differ, do not report the machine as put back — say what differs. |

**What it cannot cover:** Intel Macs (the app is universal, the assistant's
engine arm64-only — unchanged by #204); a feed signature failure end to end
(the throwaway-key tamper test in `website/test_update_feed.py`, plus
Sparkle's own validation, is the evidence).

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

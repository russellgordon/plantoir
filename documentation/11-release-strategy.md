# Release Strategy & Production Deployment

Plantoir is built for non-technical teachers. Delivering a professional, friction-free experience across both macOS and Windows requires solving three core challenges:
1. **Zero Security Warnings**: macOS Gatekeeper notarization approval and Windows SmartScreen reputation.
2. **Zero Admin Rights**: The app must install and run seamlessly on managed school computers where teachers do not have administrator permissions.
3. **Zero Dead Links**: The marketing website’s download buttons must always point to live, functional release binaries.

---

## 1. The Red-Team Audit & Critical Traps

An adversarial architecture review uncovered five potential failure points that must be avoided:

1. **Mach-O & Dylibs in `Resources/`**:
   Apple's bundle structure rules require all dynamic libraries (`.dylib`) to live in `Contents/Frameworks/` and helper executables (`llama-server`) to live in `Contents/Helpers/` (or `Contents/MacOS/`). Placing them inside `Contents/Resources/` causes `codesign --strict` failures and notarization rejections.
2. **Hardened Runtime**:
   Apple Developer ID notarization **strictly requires** Hardened Runtime (`--options runtime`). Releases submitted without it are automatically rejected by Apple's `notarytool`.
3. **macOS ZIP vs. Stapled DMG**:
   A `.zip` file cannot be stapled with an Apple notarization ticket. An unstapled `.app` requires an online Gatekeeper check on launch; if a school network blocks or slows Apple's OCSP servers, the app hangs or shows a security warning. A `.dmg` **can be stapled** (`xcrun stapler staple`), enabling instant offline Gatekeeper verification and providing a clean "Drag to Applications" install experience.
4. **APFS vs. Legacy HFS+ Disk Images**:
   HFS+ disk images decompose accented Unicode characters in filenames into Normalization Form D (NFD). When an app containing bundled resource files is dragged from an HFS+ image onto an APFS volume, `codesign` detects a modified resource signature and fails with `a sealed resource is missing or invalid`. Creating the DMG with an APFS filesystem (`hdiutil create -fs APFS ...`) and ensuring bundled resource filenames are clean ASCII completely eliminates this failure mode.
5. **Windows ZIP vs. Inno Setup**:
   When teachers download a `.zip`, double-clicking `Plantoir.exe` from inside Windows Explorer's archive view launches the executable from `%TEMP%` without extracting DLLs, causing immediate crashes. A per-user Inno Setup installer (`PrivilegesRequired=lowest`) installs cleanly to `%LOCALAPPDATA%\Programs\Plantoir` with **zero UAC/admin prompts**, adds Start Menu/Desktop shortcuts, and manages clean uninstalls and updates.
6. **The Netlify / GitHub 404 Race Condition**:
   Pushing to `main` triggers Netlify to deploy the website in ~20 seconds. If GitHub is still uploading the ~410 MB DMG (80 MB before #312 put the website builder's helpers in it) or 60 MB Windows installer, teachers clicking "Download" will get a 404 error. The workflow must upload assets to a **GitHub Draft Release first**, publish the draft, and only *then* update and deploy the website.

---

## 2. macOS Release Architecture

### One-Time Prerequisites
1. **Developer ID Application Certificate**:
   - Visit [developer.apple.com](https://developer.apple.com) -> *Certificates, Identifiers & Profiles* -> Certificates -> `+`.
   - Select **Developer ID Application** (not "Apple Development").
   - Download the `.cer` file and double-click to install it into your macOS Keychain.
2. **App Store Connect Credentials for `notarytool`**:
   - Generate an App-Specific Password at [appleid.apple.com](https://appleid.apple.com).
   - Store it securely in your macOS keychain profile:
     ```bash
     xcrun notarytool store-credentials "notarytool-profile" \
       --apple-id "your-apple-id@email.com" \
       --team-id "U2ZN2W2UQJ" \
       --password "xxxx-xxxx-xxxx-xxxx"
     ```
3. **Install `create-dmg`** (optional, for styled disk image creation):
   ```bash
   brew install create-dmg
   ```

### Packaging & Signing Chain (`mac-app/publish.sh`)
The automated script executes the following sequence:
1. Fetches native `llama.cpp` (`mac-app/Vendor/fetch-llama.sh`), Sparkle, the updater (`mac-app/Vendor/fetch-sparkle.sh`, #204), and the website builder's helper programs and starting disk (`mac-app/Vendor/fetch-helpers.sh`, #312 — ~470 MB, Apple silicon only, versions and checksums read from `setup.sh`).
2. Generates Xcode project (`xcodegen generate`) and builds Release (`xcodebuild`), then refuses a built bundle whose update feed, public key or ask-first key is wrong (`mac-app/release/check-update-keys.sh`).
3. Does NOT relocate anything, whatever trap 1 above suggests: `llama-server` and its dylibs are signed where the build puts them, in `Contents/Resources/llama/`, and every release since v1.0.0 has notarized that way. (This step said they were moved to `Contents/Frameworks/` and `Contents/Helpers/`; corrected 2026-09-25 with #204, from `publish.sh` as it stands.)
4. Bottom-up codesigning:
   - Signs the updater's own code first, item by item — Autoupdate, Updater.app, the framework last; never `--deep`, never the app's entitlements (`mac-app/release/sign-updater.sh`, #204).
   - Signs all real `.dylib` files (preserving symlinks) with Developer ID + `--timestamp` + `--options runtime`.
   - Signs `Contents/Resources/llama/llama-server` with Developer ID + `--timestamp` + `--options runtime`.
   - Signs each helper program in `Contents/Resources/helpers` the same way, limactl with its own entitlements (`release/limactl.entitlements`: virtualization, network client and server), then writes the helpers' `MANIFEST` again from the signed bytes (`mac-app/release/sign-helpers.sh`, #312).
   - Signs `Plantoir.app` with Developer ID + `--timestamp` + `--options runtime` + entitlements.
   - Refuses unless every updater item, every helper program and the app are on the app's own team with the hardened runtime, limactl carries the virtualization entitlement and the helpers' `MANIFEST` matches (`mac-app/release/check-signatures.sh`) — `codesign --verify --deep --strict` cannot see a helper left ad-hoc.
5. Creates APFS-formatted `dist/Plantoir-macOS.dmg` with `/Applications` symlink, then recompresses it with LZMA (`hdiutil convert -format ULMO`, #312: 410 MB at the rehearsal; zlib was ~466 MB on an earlier app) BEFORE signing it, because converting drops a signature.
6. Signs `dist/Plantoir-macOS.dmg` with Developer ID.
7. Submits DMG to Apple Notarization (`xcrun notarytool submit ... --wait`).
8. Staples the notarization ticket (`xcrun stapler staple dist/Plantoir-macOS.dmg`).
9. Verifies Gatekeeper acceptance (`spctl --assess`).

---

## 3. Windows Release Architecture

### One-Time Prerequisites
1. **Inno Setup**:
   ```powershell
   winget install --exact --id JRSoftware.InnoSetup
   ```
2. **Azure CLI & Sign Tool**:
   ```powershell
   winget install --exact --id Microsoft.AzureCLI
   dotnet tool install --global sign --prerelease
   ```

### Packaging & Signing Chain (`windows-app/publish.ps1`)
The automated PowerShell script executes:
1. `dotnet publish` for `Plantoir.csproj` and `Plantoir.Mcp.csproj` (win-x64 self-contained).
2. Copies `plantoir-mcp.exe` and `llama-server.exe` into the publish directory.
3. Signs all 5 internal binaries using Azure Trusted Signing with RFC 3161 timestamp.
4. Compiles `installer.iss` with Inno Setup to produce `dist/PlantoirSetup.exe` (`PrivilegesRequired=lowest`, installs to `%LOCALAPPDATA%\Programs\Plantoir`).
5. Signs `dist/PlantoirSetup.exe` with Azure Trusted Signing + timestamp.
6. Emits SHA-256 hash for release notes.

---

## 4. Marketing Website & Evergreen Download URLs

The website's download cards are drawn from `website/site.json` →
`downloads` (since v1.4.0; they used to be typed into
`website/pages/index.html`). A card with no `pinned` version uses the
evergreen download URL:
- **macOS**: `https://github.com/russellgordon/plantoir/releases/latest/download/Plantoir-macOS.dmg`
- **Windows**: `https://github.com/russellgordon/plantoir/releases/latest/download/PlantoirSetup.exe`

GitHub resolves `releases/latest/download/<filename>` to that asset on the
newest published release — and 404s when the newest release does not carry it.
(This paragraph used to say it found "the newest release carrying that asset
name"; it does not, which is why a platform that lags a release has its card
PINNED to `releases/download/v<version>/<filename>` by setting `pinned` in
`site.json`, and un-pinned when it catches up. Windows was pinned to 1.1.0
from v1.2.0 until its installer joined v1.4.2 on 2026-10-03.)

**The names are frozen, and renaming one breaks the site's download button
silently** — the evergreen URL keeps resolving, to nothing. `Plantoir-macOS.dmg`
and `PlantoirSetup.exe` are what the cards ask for; `Plantoir-win-x64.zip` is
also published, as a portable alternative nothing links to by that URL.

### Updating itself: one feed per platform, on plantoir.app (#204)

**The mac updates itself from v1.4.0**, with Sparkle 2.9.6 (#204); **Windows
will adopt NetSparkleUpdater**, not WinSparkle as this section expected
when it was written on 2026-08-12 — NetSparkle reads the same feed format and
can run the existing per-user Inno installer silently (the `windows` issue
drafted from #204, milestone v1.4.0). What was decided before either existed
still holds, with the names it finally took:

- **Both feeds live on plantoir.app**, in this repository's `website/`, one file
  per platform: `https://plantoir.app/updates/macos.xml` and, later,
  `updates/windows.xml` (Russell, 2026-09-24). Never a single shared feed —
  each platform would read the other's releases, and splitting it afterwards
  points every installed copy at a URL that stopped describing it. Never a
  GitHub release asset either: `releases/latest/download/<name>` answers 404
  whenever the newest release lacks that asset, and a platform may lag (above).
  The names this section used to give, `appcast-macos.xml` and
  `appcast-windows.xml`, were never published and are not used.
- **One signing key per platform**, and the feed itself is signed as well as
  the download. The mac's public key is `SUPublicEDKey` in
  `mac-app/project.yml`; the private half is the `plantoir-macos` Keychain item.
  NetSparkle signs with a separate `.signature` file beside the feed rather
  than inside it, which the site's copy must carry too.
- **A development build has no feed**, so it never updates (decision 5 on #204).
- **The feed is built at the cut, from the exact bytes uploaded, and goes live
  only after the release is published** — a feed deployed before its download
  exists offers an update that 404s. A release that publishes a DMG without
  updating the feed ships an update nobody is offered. `website/update_feed.py`
  builds and signs it at the cut, `website/build.py` copies it byte-for-byte (a
  re-serialised feed breaks its signature) and checks it before and after a
  deploy — `RELEASING.md` → "The update feed (macOS)". Teachers on v1.3.1 or
  earlier — the last release without an updater — have no updater, and install the first release that carries one by hand.

### Updating itself on Windows (#337) — built; waiting for a feed, a key and a release

**Built (bundle 8, 2026-10-01), all tested from the contract:**
`Plantoir.Core/Assist/AppUpdates.cs` — the install gate
(`appUpdates.cases`, 14), the quit (`atQuit.cases`, 6), the feed
(`FeedFor(developmentBuild: true)` is null: a Debug build constructs nothing),
the wording (`UpdateWording`, every sentence pinned and walked against
`machineryCheck`), the per-user check, the installer arguments, and
`app updated` on the trail at the first launch of a new version (always "by
hand" until the engine exists). `installer.iss` reads two new parameters.

**The engine** (`Plantoir.Core/Assist/AppUpdater.cs`, NetSparkleUpdater 3.1.0
core, API checked against the restored package): no UI factory; our own
dialogs (`Plantoir/Services/UpdatePrompts.cs`) with `UpdateWording`; the
daily check plus File ▸ Check for Updates…; Install downloads, then asks
`EvaluateForInstall` with a FRESH snapshot, and a held install goes ahead by
itself fifteen seconds after the work ends; the quit path calls `AtQuit`.
All eight update trail events have call sites. **The feed is read from ONE
place, `AppUpdates.ConfiguredFeed`**, set with `AppUpdates.PublicKey` since
v1.4.2 (`AppUpdaterTests.TheReleasedAppReadsTheContractsFeedWithAKey`). An
updater given an empty feed constructs no `SparkleUpdater`, fetches nothing
and hides the menu item (`AppUpdaterTests.AnEmptyFeedNeverReachesTheNetwork`),
which is how it shipped inert until then. A Debug build
constructs nothing at all. The verifier is Ed25519 in `SecurityMode.Strict`,
which refuses an unsigned feed or download (pinned by
`TheVerifierRequiresEd25519AndRefusesAnUnsignedFeed`).

**Switched on with v1.4.2, 2026-10-03.** `ConfiguredFeed` is `Feed`,
`PublicKey` is the public half of an Ed25519 pair Russell made with
`netsparkle-generate-appcast --generate-keys` into
`%USERPROFILE%\.plantoir-release\` (the private half is there and in his
Keychain on the mac, and nowhere else), and `website/updates/windows.xml` with
its `.signature` is committed. How the feed is made at a cut is in
`RELEASING.md` → "The update feed (Windows)".

What was measured with the signed 1.4.2 installer, on this project's Windows PC (Intel i5-8365U, 16 GB, Windows 11 Pro build 26200), over a real
per-user 1.1.0:

| Run | Result |
|---|---|
| `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCLOSEAPPLICATIONS /PLANTOIRUPDATE=1 /RELAUNCH=1`, nothing running | Installed 1.4.2 over 1.1.0 in about 3 minutes and reopened Plantoir by itself. |
| The same without `/RELAUNCH`, while a `plantoir-mcp --folder <working folder>` was serving | Setup exited 1 within a second, installed nothing, and plantoir-mcp was still running. |
| The same with `/RETURNTO=<installed Plantoir.exe>` | Setup exited 1; Plantoir reopened with `--update-not-installed` and the trail recorded "the new version was not installed: helping an assistant in another app had started; it will be offered again". |
| The installed 1.4.2's first launch, before the feed was live | The trail recorded "a new version: could not reach plantoir.app" — the engine is constructed and does fetch. |

Not measured: a real download and install offered BY the app (there is nothing
newer than 1.4.2 to offer until the next release); the refusal while
plantoir-mcp is actually publishing, as against serving (the installer's test
is the process's name, so the two are the same to it); a file still in use at
copy time under `/NORESTART`; and an all-users copy made by the 1.1.0
installer meeting the per-user 1.4.2 installer, which needs an administrator
at the PC.

**A trap at the cut: the feed files must never have their line endings
changed.** NetSparkle writes `windows.xml` with CR LF, and this repository is
`* text=auto`, so a plain commit would have stored it with LF — different
bytes under the same signature. The same setting had already given the Windows
checkout a CR LF copy of the mac's `macos.xml` (measured: SHA-256 `63026ebf…`
against the live feed's `ecb57d48…`), so a site deployed from Windows would
have published a mac feed no Mac accepts, and the deploy's own check would have
passed it, because it compares the live feed with `site/`. `.gitattributes`
now marks `website/updates/*.xml` and `*.xml.signature` `-text`. The
pre-commit hook still remarks on the CR in `windows.xml`; there it is correct
to leave them. Git does not rewrite a file because its attribute changed, so
any OTHER Windows clone keeps its CR LF `macos.xml` until it is checked out
again: `git checkout -- website/updates/macos.xml`, then compare its SHA-256
with the live feed's before deploying from that clone.

**The committed feed, read by the engine itself** (the Opus review's probe,
2026-10-03: NetSparkle 3.1.0 from the package cache, the real public key,
`SecurityMode.Strict`, the committed `windows.xml` and `.signature`): running
as 1.4.2 it answers `UpdateNotAvailable`; as 1.4.1 or 1.1.0,
`UpdateAvailable [1.4.2]`. The feed's signature is valid on the CR LF bytes
and INVALID once they are converted to LF. Versions compare the way a teacher
expects (1.4.3 above 1.4.2, 1.4.10 above 1.4.9). The check fetches two files,
`windows.xml` and `windows.xml.signature`.

**Owed in the next version, found by the same review:** `App.xaml.cs` writes
the `app updated` trail line with `byItsOwnUpdater: false` always, which was
true while no updater ran. The first update the app installs itself would be
recorded as "by hand". It has to be put right in the version that is
INSTALLED by the updater (1.4.3), which is the one that writes the line;
#428 says how, and names three comments in `AppUpdater.cs`, `App.xaml.cs`
that still say the feed is empty (left as they are in 1.4.2 so the sources
are the signed installer's).

| Decision | Choice | Rejected, and why |
|---|---|---|
| Engine | NetSparkleUpdater core, **no UI factory**; our own `ContentDialog`s | Its WinForms/WPF/Avalonia UIs: a second UI stack in a WinUI app, English-only, and they say "app cast". |
| Feed | `https://plantoir.app/updates/windows.xml`, beside `macos.xml` | A release asset (404s when a platform lags); sharing the mac's feed (one key per platform). |
| Signature | Ed25519, `SecurityMode.Strict`, a detached `windows.xml.signature`. The private key lives OUTSIDE the repo (`%USERPROFILE%\.plantoir-release\`), `.gitignore` refuses `*.priv` | DSA (deprecated); unsigned. |
| Installer | The per-user Inno `PlantoirSetup.exe`, run `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /PLANTOIRUPDATE=1` (+ `/RELAUNCH=1` from the in-app Install only) | MSIX (the app is unpackaged). |
| Reopening | installer.iss `[Run]` entry `Check: WantsRelaunch` on `/RELAUNCH=1` (ruling 1) | Renaming "Install and Reopen": the contract's `heldExplanation` promises a reopen, so the installer was made to keep it. |
| The installer's kill | `CurStepChanged` skips its `taskkill` of plantoir-mcp and llama-server when `/PLANTOIRUPDATE=1` (ruling 2); a hand-run installer keeps it | Leaving it: it kills every plantoir-mcp on the machine, mid-publish. |
| Held while | `AppUpdates.EvaluateForInstall`: the contract's gate, PLUS any running plantoir-mcp (it may be publishing in a folder this app never opened), asked AGAIN at the moment of install | Checking at the offer only (contract `whatWasRejected`). |
| All-users installs | **None made since 2026-10-01**: installer.iss installs per-user ONLY (`PrivilegesRequiredOverridesAllowed=dialog` removed, Russell's choice in parity bundle 10, so every copy it makes updates itself; pinned by `AppUpdatesContractTests.TheInstallerInstallsForOnePersonOnly`). An all-users copy an OLDER installer made is still not auto-updated (`IsPerUserInstall`): `needsAdministratorTitle` + a Windows explanation (ruling 3); since the same day that explanation tells the teacher to have that copy uninstalled and install again from plantoir.app, because the per-user-only installer can never update an all-users copy (even run by an administrator it installs for that administrator only) | Passing `/ALLUSERS` (needs elevation); a silent per-user install beside it (a second copy); keeping the all-users choice (a school's IT can deploy per-user copies, and a copy that cannot update itself is one that stays old). |
| At quit | `DecideAtQuit`: never refuses; work under way sets the update aside | Refusing the quit (decision 7). |

**What the contract and Windows disagree about** (proposed to the mac, not
changed under it): `needsAdministratorExplanation` names a Mac and its menu
(`elsewhereWork` used to say "on this Mac" too; since v1.4.3 it says "on this
{machine}" and Windows fills it, #438); a running plantoir-mcp holds the install on Windows
only; `postponedAtInstall` — the instant between the last check and the
installer starting — exists on Windows too, because Inno's
`CloseApplications` still closes `*Plantoir*` (a scheduled run included).
The Windows-only sentences are `shared-rules.json → appUpdates.windowsWording`.

**Unsigned installer, no Mark-of-the-Web.** A file the app downloads with
`HttpClient` carries no Zone.Identifier, so SmartScreen does not prompt when
it is run; the Ed25519 signature is the integrity gate. Do not add MOTW
handling to "fix" a prompt that does not happen.

The rules a teacher is promised are `contracts/shared-rules.json` →
`appUpdates`; the mac's mechanism, what was measured and what was rejected are
in [`09-mac-app.md`](09-mac-app.md) → "Updating itself".

---

## 5. End-to-End Release Execution Workflow

```
                             RELEASE FLOW
                             
   [Windows Machine]                               [Mac Machine]
  powershell publish.ps1 -Sign                   ./mac-app/publish.sh -Sign
         │                                               │
         ▼                                               ▼
  PlantoirSetup.exe                             Plantoir-macOS.dmg
         │                                               │
         └───────────────────────┬───────────────────────┘
                                 │
                                 ▼
                    [Step 1: Release Preflight]
                    - Confirm version matches across csproj, project.yml, site.json
                    - Verify signatures and compute SHA-256 hashes
                                 │
                                 ▼
                 [Step 2: Create GitHub DRAFT Release]
                 gh release create v1.0.0 --draft --title "Plantoir 1.0.0" ...
                                 │
                                 ▼
                 [Step 3: Upload Binary Assets]
                 gh release upload v1.0.0 Plantoir-macOS.dmg PlantoirSetup.exe
                                 │
                                 ▼
                 [Step 4: Publish Draft Release]
                 gh release edit v1.0.0 --draft=false
                                 │
                                 ▼
                 [Step 5: Update Website & Brand Cards]
                 - Update website/site.json (version & release date)
                 - Redraw social card (python scripts/brand_images.py --install-card)
                 - Rebuild site (python3 website/build.py)
                 - Commit site/ and push to main
                 - Deploy the site: python3 website/build.py --deploy
                   (the Netlify site is not Git-connected; pushing deploys nothing)
```

---

## 6. How to Cut a Release (Action Checklist)

1. On Windows: Run `powershell -File publish.ps1 -Sign` -> Copy `PlantoirSetup.exe` to Mac (or shared staging).
2. On Mac: Run `./mac-app/publish.sh -Sign` -> produces `Plantoir-macOS.dmg`.
3. In terminal / assistant: Ask Claude to **"Cut the release"**.
4. The automated skill drafts teacher-friendly release notes, confirms SHA-256 hashes, creates the draft release, uploads both assets, publishes the release, updates `site.json`, redraws the social card, and pushes to `main`.

## The Windows icon derives from `mac-app/Plantoir.icon`

`windows-app/Plantoir/Assets/make-icon.ps1` turns a full-bleed 1024px
Icon Composer export into the exe/.ico and About-panel assets, applying
the macOS rounded-rect silhouette; `site/icon.png` on plantoir.app
comes from the same export. If the icon art ever changes, tell the
Windows side so those derived assets are regenerated — nothing updates
them automatically. On the mac, also re-run
`python3 mac-app/make-beta-icon.py`, which rewrites the Debug build's
ribbon icon from it (`BetaIconTests` fails until you do; see
[9. The macOS App](09-mac-app.md) → "Telling the Debug build from the
release: the Beta ribbon").

---

[◀ Previous: The Local AI Assistant](10-local-ai-assistant.md) · [Back to index](README.md) · [Next: The Windows App ▶](12-windows-app.md)

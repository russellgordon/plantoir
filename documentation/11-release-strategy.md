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
   Pushing to `main` triggers Netlify to deploy the website in ~20 seconds. If GitHub is still uploading the 80 MB DMG or 60 MB Windows installer, teachers clicking "Download" will get a 404 error. The workflow must upload assets to a **GitHub Draft Release first**, publish the draft, and only *then* update and deploy the website.

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
1. Fetches native `llama.cpp` (`mac-app/Vendor/fetch-llama.sh`) and Sparkle, the updater (`mac-app/Vendor/fetch-sparkle.sh`, #204).
2. Generates Xcode project (`xcodegen generate`) and builds Release (`xcodebuild`), then refuses a built bundle whose update feed, public key or ask-first key is wrong (`mac-app/release/check-update-keys.sh`).
3. Does NOT relocate anything, whatever trap 1 above suggests: `llama-server` and its dylibs are signed where the build puts them, in `Contents/Resources/llama/`, and every release since v1.0.0 has notarized that way. (This step said they were moved to `Contents/Frameworks/` and `Contents/Helpers/`; corrected 2026-09-25 with #204, from `publish.sh` as it stands.)
4. Bottom-up codesigning:
   - Signs the updater's own code first, item by item — Autoupdate, Updater.app, the framework last; never `--deep`, never the app's entitlements (`mac-app/release/sign-updater.sh`, #204).
   - Signs all real `.dylib` files (preserving symlinks) with Developer ID + `--timestamp` + `--options runtime`.
   - Signs `Contents/Resources/llama/llama-server` with Developer ID + `--timestamp` + `--options runtime`.
   - Signs `Plantoir.app` with Developer ID + `--timestamp` + `--options runtime` + entitlements.
   - Refuses unless every updater item and the app are on the app's own team with the hardened runtime (`mac-app/release/check-signatures.sh`) — `codesign --verify --deep --strict` cannot see a helper left ad-hoc.
5. Creates APFS-formatted `dist/Plantoir-macOS.dmg` with `/Applications` symlink.
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

The website (`website/pages/index.html`) references evergreen download URLs:
- **macOS**: `https://github.com/russellgordon/plantoir/releases/latest/download/Plantoir-macOS.dmg`
- **Windows**: `https://github.com/russellgordon/plantoir/releases/latest/download/PlantoirSetup.exe`

GitHub automatically resolves `releases/latest/download/<filename>` to the newest published release carrying that asset name.

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
them automatically.

---

[◀ Previous: The Local AI Assistant](10-local-ai-assistant.md) · [Back to index](README.md) · [Next: The Windows App ▶](12-windows-app.md)

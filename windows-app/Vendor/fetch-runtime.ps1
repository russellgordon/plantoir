<#
Builds the NATIVE Windows toolchain runtime into windows-app/Vendor/runtime/.

This folder is what lets Plantoir build and publish sites with no container,
no WSL2, no Docker and no administrator rights: everything the Dockerfile
used to bake into the Linux image is fetched here as pinned, portable
Windows pieces, and the app ships the folder the same way it ships llama/.

    runtime\node\       Node.js 20 (win-x64 zip distribution - no installer)
    runtime\python\     Python 3.11 embeddable + python-frontmatter 1.3.0,
                        PyYAML 6.0.3, Pillow 12.3.0
    runtime\quartz\     Quartz v4.5.0 + this repo's patches + node_modules
    runtime\wrangler\   wrangler 4.80.0 (npm prefix; Cloudflare deploys)
    runtime\fonts\      Noto Color Emoji (social sharing cards)
    runtime\vendor\     the page features a site carries only when a page
                        asks for them (#496, #503, #568): pagedjs\ (Paged.js
                        0.4.3, and Latin Modern in pagedjs\fonts\),
                        function-plot\ (function-plot 1.25.4), pyodide\
                        (Pyodide 314.0.7's five runtime files, for runnable
                        Python) and tikz-engine\ (node-tikzjax 1.0.5 and its
                        locked dependencies, run at build time only)
    runtime\manifest.json

Pins mirror the Dockerfile deliberately: Node 20 because Quartz v4.5.0 is
known-good against it, wrangler below 4.100 because 4.100+ needs Node 22,
Python 3.11 to match the python:3.11-slim base. Change a pin here and the
Dockerfile's reasoning applies to you.

NOT committed (~600 MB of fetched output) - this repository ships recipes,
not binaries. Run once before building the Windows app; re-run after
deleting runtime\ to rebuild it.

RE-RUN IT after pulling a change to the vendor pins below: the run decides
from runtime\manifest.json's KEYS what is missing. No manifest: everything is
fetched. A manifest from before the vendor folder (every runtime made before
2026-10-15) or with a vendor version that differs from the pins: runtime\vendor
is deleted and ONLY the vendor phase runs, against the node and python
already there, so nobody fetches ~600 MB again for the vendor pieces (~56 MB since
Pyodide joined them, #568).
It never infers a phase from folders: an npm ci that crashed leaves a
node_modules that looks finished. The app's build REFUSES a runtime whose
manifest lacks the vendor keys (Plantoir.csproj -> CheckNativeRuntimeManifest),
so a release cannot ship without the engines by accident.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$NodeVersion     = "20.18.1"
$PythonVersion   = "3.11.9"
$WranglerVersion = "4.80.0"
$QuartzTag       = "v4.5.0"
$EmojiFontTag    = "v2.047"

# The vendor pins (#496, #503). Each URL below is written OUT IN FULL, never
# built from these variables: ToolchainContractTests reads this file as text
# for each pin's `windowsRuntimeContains` in contracts/toolchain.json, the
# same way the Dockerfile is read for `dockerfileContains`. The versions here
# are what the manifest records.
$PagedjsVersion      = "0.4.3"
$LatinModernVersion  = "2.005-1"
$FunctionPlotVersion = "1.25.4"
$NodeTikzjaxVersion  = "1.0.5"
$PyodideVersion      = "314.0.7"
# The literal addresses, beside the versions they must carry. A bump that
# edits a version and not its address would compare the manifest against
# the new version while fetching the old bytes (or never fetch at all), so
# the run refuses at once when the two disagree; ToolchainContractTests
# holds each version above against the contract as well (5A review, L2).
$PagedjsUrl      = "https://registry.npmjs.org/pagedjs/-/pagedjs-0.4.3.tgz"
$LatinModernUrl  = "https://deb.debian.org/debian/pool/main/l/lmodern/fonts-lmodern_2.005-1_all.deb"
$LatinModernSnapshotUrl = "https://snapshot.debian.org/archive/debian/20230101T000000Z/pool/main/l/lmodern/fonts-lmodern_2.005-1_all.deb"
$FunctionPlotUrl = "https://registry.npmjs.org/function-plot/-/function-plot-1.25.4.tgz"
$NodeTikzjaxSpec = "node-tikzjax@1.0.5"
$PyodideUrl      = "https://github.com/pyodide/pyodide/releases/download/314.0.7/pyodide-core-314.0.7.tar.bz2"
foreach ($pair in @(
        @($PagedjsUrl, "pagedjs-$PagedjsVersion.tgz"),
        @($LatinModernUrl, "fonts-lmodern_${LatinModernVersion}_all.deb"),
        @($LatinModernSnapshotUrl, "fonts-lmodern_${LatinModernVersion}_all.deb"),
        @($FunctionPlotUrl, "function-plot-$FunctionPlotVersion.tgz"),
        @($NodeTikzjaxSpec, "node-tikzjax@$NodeTikzjaxVersion"),
        @($PyodideUrl, "$PyodideVersion/pyodide-core-$PyodideVersion.tar.bz2"))) {
    if (-not $pair[0].EndsWith($pair[1], [StringComparison]::Ordinal)) {
        throw "$($pair[0]) does not carry $($pair[1]): a version above was changed without its address."
    }
}

# SHA-256 of each fixed download (#356, after the mac's #312 pinned its
# helpers). A version pin says WHICH file is asked for; a hash says the file
# that arrived is that one. Measured 2026-10-01 on the build PC (i5-8365U,
# Windows 11 26200): the Node hash equals nodejs.org's own SHASUMS256.txt for
# v20.18.1; the Python zip's python.exe and python311.dll are byte-identical
# to the runtime that has shipped; the font equals the shipped font. Change a
# version above and its hash must change with it, or the fetch refuses.
# get-pip.py is NOT hashed, deliberately: bootstrap.pypa.io serves one moving
# file with no versioned URL, so a hash would break the build on pip's next
# release while protecting nothing the package pins below do not - those are
# exact versions, fetched by pip from PyPI over TLS.
$NodeZipSha256   = "56e5aacdeee7168871721b75819ccacf2367de8761b78eaceacdecd41e04ca03"
$PythonZipSha256 = "009d6bf7e3b2ddca3d784fa09f90fe54336d5b60f0e0f305c37f400bf83cfd3b"
$EmojiFontSha256 = "39ee3c587e10e89669b9ff32703261d10d5f9c4dd5ad147b6b5a1c5200591817"
# The vendor tarballs' hashes are the contract's own (toolchain.json ->
# pins -> sha256, and fileSha256 for the one file kept), checked here as the
# Dockerfile checks them. The Debian package's hash was measured 2026-10-15
# (i5-8365U, Windows 11 Pro 26200) from deb.debian.org; the six fonts inside
# it equal latinModern.files, the SHA-256s verify.sh checks in the image.
$PagedjsTgzSha256      = "a79baaa94d15cf952e6327950fa886ba7533bdce92194b677d9d1b4cce6c17c5"
$PagedMinJsSha256      = "c4af9ac4a80f15e4abf53e11fdf34659dc4913f61b541652811cfa570f397211"
$LatinModernDebSha256  = "027cd4ddc91b9254bd7fd9b9ce55d58c095319f691d4d7cbd09d2e4a99c58398"
$FunctionPlotTgzSha256 = "33974ca53165365f585601f3e304e882107b44aa8a360d0b2b089ab9daf24a77"
$FunctionPlotJsSha256  = "4e3cc6d8015e517b0356178bc6409405db2b31385ac655b657aaad7120b802d1"
$LatinModernFiles = [ordered]@{
    "lmroman10-regular.otf"    = "1aa18cfefa58132c52ce5de70db1fd1154201c19cd2b2cdaffba4906a33e6852"
    "lmroman10-bold.otf"       = "102fe06c430a8b681b2bf6876b7cd967ae4d47b4b6b41d915eb7913b726d9fb1"
    "lmroman10-italic.otf"     = "c1fce25075567bb8dbf2151658c3b442690041db17a2d49fc9e55905ea5b7169"
    "lmroman10-bolditalic.otf" = "c37a28eed7a6e03f792b98b5e5f637b2fcda378bb4855f99284f1a88fe35f124"
    "lmsans10-bold.otf"        = "a597b710326c1a8a2c7238d808e5d38711638a72a32383478db4829d63afd687"
    "lmmono10-regular.otf"     = "22deb6d3be3ffcb40b33f0e010afb256c677d97c2a2bdee1f5740cdc97751558"
}
# Pyodide 314.0.7 (#455, #568): the tarball and the five files kept from it,
# the contract's own hashes (toolchain.json -> pins -> pyodide: sha256 and
# files), checked here as the Dockerfile checks them.
$PyodideTarSha256 = "2abdcc2e35208af406e07724cffa85bc582ced97e9028383ecf5462541393f95"
$PyodideTarLength = 6757104
$PyodideFiles = [ordered]@{
    "pyodide.mjs"       = "6f1d60f7bf529beb300f0f47983c921d3982363640ba20af0e38efdddbc66109"
    "pyodide.asm.mjs"   = "f7cdc8ece80678ceb712f8e65ebe6d3a83203a180c399865f49612a051693635"
    "pyodide.asm.wasm"  = "cc36e3cab04fdfc9a63ff13eb52eae2b911bf46c025cc7b281f394bd3de1d5e6"
    "python_stdlib.zip" = "fa1957e5777068fc4f7437f96d860ae2fbe9c19732ba06c84e004ec16dd7dd7a"
    "pyodide-lock.json" = "5dc2fc119108bc148c7457dc86e7675b5c87e1cafd420b9c34c1eaef7b36c010"
}
$NodeTikzjaxTexFiles = [ordered]@{
    "tex\core.dump.gz"     = "ae9f69dfe3837606240c5b9cb50f86aa0ee7463bbae4c26f2843b17eb155b91f"
    "tex\tex.wasm.gz"      = "f8667f45e90039832df4f62550f10ff0c2f47781dbfdde9510f0ff3f360a61ba"
    "tex\tex_files.tar.gz" = "492271c589ab2d7b64c22a09f927ea09cd5ee3fc696a46067ddea2da4693c86f"
}

$VendorDir  = $PSScriptRoot
$RepoRoot   = (Resolve-Path (Join-Path $VendorDir "..\..")).Path
$Runtime    = Join-Path $VendorDir "runtime"
$Manifest   = Join-Path $Runtime "manifest.json"
$VendorOut  = Join-Path $Runtime "vendor"
# Set before ANY phase: the vendor phase alone, against an existing runtime,
# runs this node and this python (the plan review's M4).
$nodeDir    = Join-Path $Runtime "node"
$pyDir      = Join-Path $Runtime "python"
# Windows' own bsdtar by full path: Git's GNU tar may come first on PATH, and
# it reads "C:" in a path as a remote host.
$Tar        = Join-Path $env:SystemRoot "System32\tar.exe"

$BaseKeys   = @("node", "python", "quartz", "wrangler", "emoji")
$VendorPins = [ordered]@{
    pagedjs      = $PagedjsVersion
    latinModern  = $LatinModernVersion
    functionPlot = $FunctionPlotVersion
    nodeTikzjax  = $NodeTikzjaxVersion
    pyodide      = $PyodideVersion
}

# What to run is decided from the manifest's KEYS, never from folders.
$runBase = $true
$existing = $null
if (Test-Path $Manifest) {
    $existing = Get-Content $Manifest -Raw | ConvertFrom-Json
    $names = @($existing.PSObject.Properties.Name)
    foreach ($key in $BaseKeys) {
        if ($names -notcontains $key) {
            throw "runtime\manifest.json has no '$key': this is not a runtime this script made. Delete $Runtime and re-run."
        }
    }
    $vendorCurrent = $true
    foreach ($key in $VendorPins.Keys) {
        if ($names -notcontains $key -or [string]$existing.$key -ne $VendorPins[$key]) { $vendorCurrent = $false }
    }
    if ($vendorCurrent) {
        Write-Host "[OK] Runtime already in place ($Runtime)." -ForegroundColor Green
        Write-Host "     Delete that folder and re-run to fetch it again."
        exit 0
    }
    Write-Host "The runtime predates the current page-feature pins: fetching runtime\vendor only." -ForegroundColor Cyan
    $runBase = $false
}

New-Item -ItemType Directory -Force $Runtime | Out-Null
$Temp = Join-Path ([IO.Path]::GetTempPath()) ("plantoir-runtime-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $Temp | Out-Null

function Assert-Sha256([string]$Path, [string]$Sha256, [long]$Length = -1) {
    $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($got -ne $Sha256.ToLowerInvariant()) { throw "$Path : its SHA-256 is $got, the pin is $Sha256" }
    $size = (Get-Item -LiteralPath $Path).Length
    if ($Length -ge 0 -and $size -ne $Length) { throw "$Path : $size bytes, the pin says $Length" }
}

# Written the way it always was (Set-Content -Encoding utf8, which under
# Windows PowerShell 5.1 starts with a BOM; ConvertFrom-Json takes it).
function Write-RuntimeManifest($Fields) {
    $Fields.made = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    [pscustomobject]$Fields | ConvertTo-Json | Set-Content $Manifest -Encoding utf8
}

# The manifest as it should read while runtime\vendor is absent or being
# made: every key found (or the five base keys on a fresh run) WITHOUT the
# vendor keys. Written BEFORE the vendor folder is touched, so a run
# that dies part-way leaves a manifest the app's build refuses
# (CheckNativeRuntimeManifest) and the next run repairs by the vendor-only
# path, rather than one naming engines that are not there (5A review, L1
# and L3).
function Get-BaseFields {
    $fields = [ordered]@{}
    if ($existing) {
        foreach ($p in $existing.PSObject.Properties) {
            if ($VendorPins.Contains($p.Name) -or $p.Name -eq "made") { continue }
            $fields[$p.Name] = $p.Value
        }
    }
    else {
        $fields.node     = $NodeVersion
        $fields.python   = $PythonVersion
        $fields.quartz   = $QuartzTag
        $fields.wrangler = $WranglerVersion
        $fields.emoji    = $EmojiFontTag
    }
    return $fields
}

function Fetch([string]$Url, [string]$To, [string]$Sha256 = "") {
    Write-Host "Fetching $Url" -ForegroundColor Cyan
    & curl.exe -fL --retry 3 -o $To $Url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $To)) { throw "Failed to download $Url" }
    if ($Sha256) {
        $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $To).Hash.ToLowerInvariant()
        if ($got -ne $Sha256.ToLowerInvariant()) {
            Remove-Item -LiteralPath $To -Force -ErrorAction SilentlyContinue
            throw "Refused $Url : its SHA-256 is $got, the pin is $Sha256"
        }
    }
}

try {
  $env:PATH = "$nodeDir;$env:PATH"
  if ($runBase) {
    # ---- Node.js (portable zip - the whole point is that nothing installs) ----
    $nodeZip = Join-Path $Temp "node.zip"
    Fetch "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-x64.zip" $nodeZip $NodeZipSha256
    Expand-Archive $nodeZip -DestinationPath $Temp -Force
    Move-Item (Join-Path $Temp "node-v$NodeVersion-win-x64") $nodeDir
    Write-Host "Node $(& "$nodeDir\node.exe" --version) in place." -ForegroundColor Green

    # ---- Python (embeddable package + pip bootstrap) -------------------------
    $pyZip = Join-Path $Temp "python.zip"
    Fetch "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip" $pyZip $PythonZipSha256
    Expand-Archive $pyZip -DestinationPath $pyDir -Force
    # The embeddable package ships with `import site` disabled; pip and
    # site-packages need it on.
    $pth = Get-ChildItem $pyDir -Filter "python3*._pth" | Select-Object -First 1
    (Get-Content $pth.FullName) -replace '^#import site$', 'import site' | Set-Content $pth.FullName -Encoding ascii
    $getPip = Join-Path $Temp "get-pip.py"
    Fetch "https://bootstrap.pypa.io/get-pip.py" $getPip
    & "$pyDir\python.exe" $getPip --no-warn-script-location | Out-Null
    # PINNED, and the PyYAML one is not decoration. python-frontmatter parses
    # with PyYAML, which is YAML 1.1 -- and that is the only reason
    # `publish: no` and `publish: off` HIDE a page. PyYAML 7 is expected to
    # move to YAML 1.2, where `no` is the string "no" and every page hidden
    # that way would be republished, silently, in courses already in front of
    # students. `contracts/file-formats.json` -> `pageVisibility` states the
    # 1.1 table as fact and both apps are written against it, so an unpinned
    # upgrade here would fail nothing anywhere. PyYAML is named explicitly
    # rather than left to python-frontmatter's own dependency range, because
    # that range is not ours to control. The versions are the ones the image
    # and this snapshot already carry, so the pins change nothing about what
    # is installed and everything about what can change underneath it.
    # `ToolchainContractTests` holds these against contracts/toolchain.json.
    & "$pyDir\python.exe" -m pip install --no-warn-script-location `
        python-frontmatter==1.3.0 PyYAML==6.0.3 Pillow==12.3.0 | Out-Null
    & "$pyDir\python.exe" -c "import frontmatter, PIL; print('frontmatter + Pillow OK')"
    if ($LASTEXITCODE -ne 0) { throw "Python package verification failed" }
    Write-Host "Python $PythonVersion embeddable in place." -ForegroundColor Green

    # ---- Quartz, patched exactly as the Dockerfile patches it ----------------
    $quartzDir = Join-Path $Runtime "quartz"
    git clone --quiet --depth 1 --branch $QuartzTag https://github.com/jackyzha0/quartz.git $quartzDir
    if ($LASTEXITCODE -ne 0) { throw "git clone of Quartz $QuartzTag failed" }
    $patches = Join-Path $RepoRoot "patches"
    Copy-Item "$patches\Explorer.tsx"        "$quartzDir\quartz\components\Explorer.tsx" -Force
    Copy-Item "$patches\FolderContent.tsx"   "$quartzDir\quartz\components\pages\FolderContent.tsx" -Force
    Copy-Item "$patches\explorer.inline.ts"  "$quartzDir\quartz\components\scripts\explorer.inline.ts" -Force
    Copy-Item "$patches\publish.ts"          "$quartzDir\quartz\plugins\filters\publish.ts" -Force
    Copy-Item "$patches\filters-index.ts"    "$quartzDir\quartz\plugins\filters\index.ts" -Force
    Copy-Item "$patches\Head.tsx"            "$quartzDir\quartz\components\Head.tsx" -Force
    Copy-Item "$patches\build.ts"            "$quartzDir\quartz\build.ts" -Force
    # The clone is a scaffold, not a repository; keeping .git would ship it.
    Remove-Item (Join-Path $quartzDir ".git") -Recurse -Force

    # NATIVE-ONLY: bind the preview server and its live-reload websocket to
    # loopback. Quartz listens on every interface, and Windows shows a
    # firewall consent dialog naming "Node.js JavaScript Runtime" for any
    # non-loopback listener - machinery in a teacher's face on their very
    # first preview. A preview is only ever browsed at localhost. This must
    # NOT be made a shared patch: inside the container, loopback binding
    # would break Docker's port forwarding, which connects to the
    # container's own address.
    $handlers = Join-Path $quartzDir "quartz\cli\handlers.js"
    $handlersText = Get-Content $handlers -Raw
    $handlersText = $handlersText.Replace('server.listen(argv.port)', 'server.listen(argv.port, "127.0.0.1")')
    $handlersText = $handlersText.Replace('new WebSocketServer({ port: argv.wsPort })', 'new WebSocketServer({ host: "127.0.0.1", port: argv.wsPort })')
    if ($handlersText -notmatch '127\.0\.0\.1') { throw "The loopback patch found neither bind site in quartz/cli/handlers.js" }
    Set-Content $handlers $handlersText -Encoding utf8 -NoNewline

    Write-Host "Installing Quartz dependencies (a few minutes)..." -ForegroundColor Cyan
    Push-Location $quartzDir
    & "$nodeDir\npm.cmd" install --no-audit --no-fund --silent
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "npm install for Quartz failed" }
    Pop-Location

    # Bake the Explorer hide-filter anchor AND the OverflowList stable id,
    # same functions the Dockerfile and setup wizard run, imported rather
    # than copied so they cannot drift. Baking BOTH here matters: the
    # runtime is shared by every working folder, so the wizard's own pass
    # over these files must always find them already patched and write
    # nothing - a wizard writing into the shared bundle races concurrent
    # builds and fails outright on an unwritable install.
    $env:PLANTOIR_QUARTZ_DIR = $quartzDir
    $env:PLANTOIR_SUPPORT_DIR = Join-Path $RepoRoot "support"
    $env:PLANTOIR_CONTRACTS_DIR = Join-Path $RepoRoot "contracts"
    & "$pyDir\python.exe" -c "import sys; sys.path.insert(0, r'$RepoRoot\scripts'); import setup_course; setup_course.ensure_quartz_explorer_anchor(); setup_course.ensure_quartz_overflowlist_static_id()"
    if ($LASTEXITCODE -ne 0) { throw "Baking the Quartz scaffold patches failed" }
    if (-not (Select-String -Path "$quartzDir\quartz.layout.ts" -Pattern 'CQ4T-OMIT-ANCHOR' -Quiet)) {
        throw "quartz.layout.ts is missing the CQ4T-OMIT-ANCHOR marker - hidden pages would publish"
    }
    # And the sidebar's hide rule must be v2 from birth (#272 / mac #265):
    # a top-level item by its stored name, not a page's title at any depth.
    # build_site.ensure_sidebar_hide_rule_current repairs an old one on every
    # build, but the bundle should never need it. -SimpleMatch and
    # -CaseSensitive: the marker is a literal, and Select-String ignores case
    # by default.
    if (-not (Select-String -Path "$quartzDir\quartz.layout.ts" -SimpleMatch -CaseSensitive -Pattern 'CQ4T-HIDE-RULE: v2' -Quiet)) {
        throw "quartz.layout.ts is missing the CQ4T-HIDE-RULE: v2 marker - the sidebar's hide switches would not match the site"
    }
    Remove-Item Env:\PLANTOIR_QUARTZ_DIR
    Remove-Item Env:\PLANTOIR_SUPPORT_DIR
    Remove-Item Env:\PLANTOIR_CONTRACTS_DIR
    Write-Host "Quartz $QuartzTag patched and provisioned." -ForegroundColor Green

    # ---- wrangler (Cloudflare's deploy CLI, pinned below 4.100) --------------
    $wranglerDir = Join-Path $Runtime "wrangler"
    New-Item -ItemType Directory -Force $wranglerDir | Out-Null
    & "$nodeDir\npm.cmd" install --prefix $wranglerDir --no-audit --no-fund --silent "wrangler@$WranglerVersion"
    if ($LASTEXITCODE -ne 0) { throw "npm install of wrangler failed" }
    if (-not (Test-Path "$wranglerDir\node_modules\.bin\wrangler.cmd")) { throw "wrangler.cmd not found after install" }
    Write-Host "wrangler $WranglerVersion in place." -ForegroundColor Green

    # ---- Colour emoji font for the social sharing cards ----------------------
    $fontsDir = Join-Path $Runtime "fonts"
    New-Item -ItemType Directory -Force $fontsDir | Out-Null
    Fetch "https://github.com/googlefonts/noto-emoji/raw/$EmojiFontTag/fonts/NotoColorEmoji.ttf" (Join-Path $fontsDir "NotoColorEmoji.ttf") $EmojiFontSha256
  }

    # ---- runtime\vendor: the page features (#496, #503) ----------------------
    # The native mirror of the Dockerfile's /opt/vendor. build_site.py finds
    # it with no new variable: toolchain_paths.VENDOR_DIR is
    # PLANTOIR_QUARTZ_DIR's parent + "vendor", and the launchers set
    # PLANTOIR_QUARTZ_DIR to runtime\quartz. Always made from nothing: a
    # half-made vendor folder from a crashed run is never trusted.
    #
    # The manifest loses its vendor keys FIRST (on a fresh run this is the
    # first manifest written, right after the base phases): from here until
    # the end, a failure leaves a runtime the build refuses and a re-run
    # finishes by fetching runtime\vendor alone.
    Write-RuntimeManifest (Get-BaseFields)
    if (Test-Path $VendorOut) { Remove-Item $VendorOut -Recurse -Force }
    New-Item -ItemType Directory -Force $VendorOut | Out-Null
    $vendorClock = [Diagnostics.Stopwatch]::StartNew()

    # Paged.js 0.4.3 (#454): the print layout. paged.min.js and its licence.
    $pagedjsDir = Join-Path $VendorOut "pagedjs"
    New-Item -ItemType Directory -Force $pagedjsDir | Out-Null
    $pagedjsTgz = Join-Path $Temp "pagedjs.tgz"
    Fetch $PagedjsUrl $pagedjsTgz $PagedjsTgzSha256
    $pagedjsTmp = Join-Path $Temp "pagedjs"
    New-Item -ItemType Directory -Force $pagedjsTmp | Out-Null
    & $Tar -xzf $pagedjsTgz -C $pagedjsTmp package/dist/paged.min.js package/LICENSE.md
    if ($LASTEXITCODE -ne 0) { throw "Unpacking Paged.js failed" }
    Copy-Item (Join-Path $pagedjsTmp "package\dist\paged.min.js") $pagedjsDir
    Copy-Item (Join-Path $pagedjsTmp "package\LICENSE.md") $pagedjsDir
    Assert-Sha256 (Join-Path $pagedjsDir "paged.min.js") $PagedMinJsSha256 502617
    Write-Host "Paged.js $PagedjsVersion in place." -ForegroundColor Green

    # Latin Modern (#499): the six faces a printed handout is set in, beside
    # Paged.js so the same gate carries them. From Debian's own
    # fonts-lmodern_2.005-1_all.deb, the package the image's apt installs, so
    # the bytes are the image's; snapshot.debian.org keeps it if the pool
    # moves on. The .deb is an ar archive, which Windows' bsdtar reads; its
    # data.tar.xz is unpacked with the runtime's Python (tarfile + lzma)
    # rather than bsdtar, because whether a given Windows' bsdtar was built
    # with xz is not something to assume (this PC's 3.8.9 was; older Windows
    # 10 builds are not known to be). UNMODIFIED: the GUST Font License asks
    # that a changed font be renamed. Debian's copyright file carries it.
    $fontsOut = Join-Path $pagedjsDir "fonts"
    New-Item -ItemType Directory -Force $fontsOut | Out-Null
    $lmDeb = Join-Path $Temp "fonts-lmodern.deb"
    try {
        Fetch $LatinModernUrl $lmDeb $LatinModernDebSha256
    }
    catch {
        Write-Host "deb.debian.org did not serve it ($($_.Exception.Message)); trying snapshot.debian.org" -ForegroundColor Yellow
        Fetch $LatinModernSnapshotUrl $lmDeb $LatinModernDebSha256
    }
    $lmTmp = Join-Path $Temp "lmodern"
    New-Item -ItemType Directory -Force $lmTmp | Out-Null
    & $Tar -xf $lmDeb -C $lmTmp data.tar.xz
    if ($LASTEXITCODE -ne 0) { throw "Reading the fonts-lmodern package failed" }
    $lmScript = Join-Path $Temp "unpack_lmodern.py"
    @'
import os, shutil, sys, tarfile
data, out, names = sys.argv[1], sys.argv[2], sys.argv[3:]
wanted = {"./usr/share/texmf/fonts/opentype/public/lm/" + n: n for n in names}
wanted["./usr/share/doc/fonts-lmodern/copyright"] = "LICENSE-Latin-Modern.txt"
found = set()
with tarfile.open(data, "r:xz") as archive:
    for member in archive:
        target = wanted.get(member.name)
        if target is None or not member.isfile():
            continue
        with archive.extractfile(member) as source, open(os.path.join(out, target), "wb") as sink:
            shutil.copyfileobj(source, sink)
        found.add(member.name)
missing = sorted(set(wanted) - found)
if missing:
    sys.exit("not in the package: " + ", ".join(missing))
'@ | Set-Content $lmScript -Encoding ascii
    & "$pyDir\python.exe" -I $lmScript (Join-Path $lmTmp "data.tar.xz") $fontsOut @($LatinModernFiles.Keys)
    if ($LASTEXITCODE -ne 0) { throw "Unpacking Latin Modern failed" }
    foreach ($name in $LatinModernFiles.Keys) { Assert-Sha256 (Join-Path $fontsOut $name) $LatinModernFiles[$name] }
    Write-Host "Latin Modern $LatinModernVersion in place." -ForegroundColor Green

    # function-plot 1.25.4 (#503): the graphs. The folder name is load-bearing
    # (figures.GRAPH_ENGINE, page_features.GATED_ASSETS): it is copied into a
    # site's static\ under the same name.
    $fpDir = Join-Path $VendorOut "function-plot"
    New-Item -ItemType Directory -Force $fpDir | Out-Null
    $fpTgz = Join-Path $Temp "function-plot.tgz"
    Fetch $FunctionPlotUrl $fpTgz $FunctionPlotTgzSha256
    $fpTmp = Join-Path $Temp "function-plot"
    New-Item -ItemType Directory -Force $fpTmp | Out-Null
    & $Tar -xzf $fpTgz -C $fpTmp package/dist/function-plot.js package/LICENSE
    if ($LASTEXITCODE -ne 0) { throw "Unpacking function-plot failed" }
    Copy-Item (Join-Path $fpTmp "package\dist\function-plot.js") $fpDir
    Copy-Item (Join-Path $fpTmp "package\LICENSE") $fpDir
    Assert-Sha256 (Join-Path $fpDir "function-plot.js") $FunctionPlotJsSha256 202953
    Write-Host "function-plot $FunctionPlotVersion in place." -ForegroundColor Green

    # Pyodide 314.0.7 (#455, #568): runs a page's ```python run blocks in the
    # student's browser. Five files of the core tarball are kept - pyodide.mjs
    # (the module a module worker imports), pyodide.asm.mjs, pyodide.asm.wasm,
    # python_stdlib.zip and pyodide-lock.json - with a README naming the
    # licence, MPL-2.0 (the tarball carries no LICENSE file). The folder name
    # is load-bearing (page_features.RUNNER_LANGUAGES -> engine): it is copied
    # into a site's static\ under the same name, with
    # support\gated\pyodide\plantoir-worker.js laid over it.
    # Unpacked with the runtime's own Python (tarfile + bz2), as the Dockerfile
    # does with python3 -m tarfile, rather than bsdtar. MEASURED 2026-10-22:
    # this PC's bsdtar (3.8.9, bz2lib 1.0.8) does read bzip2 - but, as with
    # Latin Modern's xz above, an older Windows 10 bsdtar is not known to, and
    # the embeddable Python's _bz2 is certainly there.
    $pyoDir = Join-Path $VendorOut "pyodide"
    New-Item -ItemType Directory -Force $pyoDir | Out-Null
    $pyoTar = Join-Path $Temp "pyodide-core.tar.bz2"
    Fetch $PyodideUrl $pyoTar $PyodideTarSha256
    Assert-Sha256 $pyoTar $PyodideTarSha256 $PyodideTarLength
    $pyoScript = Join-Path $Temp "unpack_pyodide.py"
    @'
import os, shutil, sys, tarfile
archive_path, out, names = sys.argv[1], sys.argv[2], sys.argv[3:]
wanted = {"pyodide/" + n: n for n in names}
found = set()
with tarfile.open(archive_path, "r:bz2") as archive:
    for member in archive:
        target = wanted.get(member.name)
        if target is None or not member.isfile():
            continue
        with archive.extractfile(member) as source, open(os.path.join(out, target), "wb") as sink:
            shutil.copyfileobj(source, sink)
        found.add(member.name)
missing = sorted(set(wanted) - found)
if missing:
    sys.exit("not in the tarball: " + ", ".join(missing))
'@ | Set-Content $pyoScript -Encoding ascii
    & "$pyDir\python.exe" -I $pyoScript $pyoTar $pyoDir @($PyodideFiles.Keys)
    if ($LASTEXITCODE -ne 0) { throw "Unpacking Pyodide failed" }
    foreach ($name in $PyodideFiles.Keys) { Assert-Sha256 (Join-Path $pyoDir $name) $PyodideFiles[$name] }
    # The Dockerfile's README line, byte for byte (ASCII, one LF).
    [IO.File]::WriteAllText((Join-Path $pyoDir "README.txt"),
        "Pyodide $PyodideVersion (MPL-2.0). Source: https://github.com/pyodide/pyodide/tree/$PyodideVersion`n",
        (New-Object Text.UTF8Encoding $false))
    $pyoBytes = (Get-ChildItem $pyoDir -File | Where-Object Name -ne "README.txt" | Measure-Object -Property Length -Sum).Sum
    Write-Host ("Pyodide $PyodideVersion in place: {0:N0} bytes in five files." -f $pyoBytes) -ForegroundColor Green

    # node-tikzjax 1.0.5 (#503): the TikZ engine, run at BUILD time by
    # support\figures\plantoir-figures.mjs with the runtime's node. Installed
    # from the LOCKFILE, which pins all 133 packages under it - never
    # `npm install`. NOT named `tikz`: that is a site's fonts folder, and this
    # one is never copied into a site.
    $tikzDir = Join-Path $VendorOut "tikz-engine"
    New-Item -ItemType Directory -Force $tikzDir | Out-Null
    Copy-Item (Join-Path $RepoRoot "support\figures\package.json") $tikzDir
    Copy-Item (Join-Path $RepoRoot "support\figures\package-lock.json") $tikzDir
    Write-Host "Installing the TikZ engine from its lockfile..." -ForegroundColor Cyan
    Push-Location $tikzDir
    try {
        & "$nodeDir\npm.cmd" ci --omit=dev --no-audit --no-fund --silent
        if ($LASTEXITCODE -ne 0) { throw "npm ci of the TikZ engine failed" }
        & "$nodeDir\npm.cmd" ls $NodeTikzjaxSpec | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "npm ls $NodeTikzjaxSpec failed: the lockfile did not install the pinned engine" }
        $installed = @(& "$nodeDir\npm.cmd" ls --all --parseable --omit=dev)
    }
    finally { Pop-Location }
    $tikzjax = Join-Path $tikzDir "node_modules\node-tikzjax"
    foreach ($name in $NodeTikzjaxTexFiles.Keys) { Assert-Sha256 (Join-Path $tikzjax $name) $NodeTikzjaxTexFiles[$name] }
    $engineFiles = @(Get-ChildItem $tikzDir -Recurse -File -Force)
    $engineBytes = ($engineFiles | Measure-Object -Property Length -Sum).Sum
    # npm ls --parseable lists the folder itself first, then each package.
    Write-Host ("TikZ engine node-tikzjax $NodeTikzjaxVersion in place: {0} packages, {1} files, {2:N1} MB." -f `
        ($installed.Count - 1), $engineFiles.Count, ($engineBytes / 1MB)) -ForegroundColor Green
    Write-Host ("Vendor phase took {0:N0} s." -f $vendorClock.Elapsed.TotalSeconds)

    # ---- Manifest ------------------------------------------------------------
    # Merged: a vendor-only run keeps the base keys it found.
    $fields = Get-BaseFields
    foreach ($key in $VendorPins.Keys) { $fields[$key] = $VendorPins[$key] }
    Write-RuntimeManifest $fields

    Write-Host ""
    Write-Host "[OK] Native runtime ready at $Runtime" -ForegroundColor Green
}
finally {
    Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue
}

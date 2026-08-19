<#
Builds the NATIVE Windows toolchain runtime into windows-app/Vendor/runtime/.

This folder is what lets Plantoir build and publish sites with no container,
no WSL2, no Docker and no administrator rights: everything the Dockerfile
used to bake into the Linux image is fetched here as pinned, portable
Windows pieces, and the app ships the folder the same way it ships llama/.

    runtime\node\       Node.js 20 (win-x64 zip distribution - no installer)
    runtime\python\     Python 3.11 embeddable + python-frontmatter, Pillow
    runtime\quartz\     Quartz v4.5.0 + this repo's patches + node_modules
    runtime\wrangler\   wrangler 4.80.0 (npm prefix; Cloudflare deploys)
    runtime\fonts\      Noto Color Emoji (social sharing cards)
    runtime\manifest.json

Pins mirror the Dockerfile deliberately: Node 20 because Quartz v4.5.0 is
known-good against it, wrangler below 4.100 because 4.100+ needs Node 22,
Python 3.11 to match the python:3.11-slim base. Change a pin here and the
Dockerfile's reasoning applies to you.

NOT committed (~600 MB of fetched output) - this repository ships recipes,
not binaries. Run once before building the Windows app; re-run after
deleting runtime\ to rebuild it.
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

$VendorDir  = $PSScriptRoot
$RepoRoot   = (Resolve-Path (Join-Path $VendorDir "..\..")).Path
$Runtime    = Join-Path $VendorDir "runtime"
$Manifest   = Join-Path $Runtime "manifest.json"

if (Test-Path $Manifest) {
    Write-Host "[OK] Runtime already in place ($Runtime)." -ForegroundColor Green
    Write-Host "     Delete that folder and re-run to fetch it again."
    exit 0
}

New-Item -ItemType Directory -Force $Runtime | Out-Null
$Temp = Join-Path ([IO.Path]::GetTempPath()) ("plantoir-runtime-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $Temp | Out-Null

function Fetch([string]$Url, [string]$To) {
    Write-Host "Fetching $Url" -ForegroundColor Cyan
    & curl.exe -fL --retry 3 -o $To $Url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $To)) { throw "Failed to download $Url" }
}

try {
    # ---- Node.js (portable zip - the whole point is that nothing installs) ----
    $nodeZip = Join-Path $Temp "node.zip"
    Fetch "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-x64.zip" $nodeZip
    Expand-Archive $nodeZip -DestinationPath $Temp -Force
    Move-Item (Join-Path $Temp "node-v$NodeVersion-win-x64") (Join-Path $Runtime "node")
    $nodeDir = Join-Path $Runtime "node"
    $env:PATH = "$nodeDir;$env:PATH"
    Write-Host "Node $(& "$nodeDir\node.exe" --version) in place." -ForegroundColor Green

    # ---- Python (embeddable package + pip bootstrap) -------------------------
    $pyZip = Join-Path $Temp "python.zip"
    Fetch "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip" $pyZip
    $pyDir = Join-Path $Runtime "python"
    Expand-Archive $pyZip -DestinationPath $pyDir -Force
    # The embeddable package ships with `import site` disabled; pip and
    # site-packages need it on.
    $pth = Get-ChildItem $pyDir -Filter "python3*._pth" | Select-Object -First 1
    (Get-Content $pth.FullName) -replace '^#import site$', 'import site' | Set-Content $pth.FullName -Encoding ascii
    $getPip = Join-Path $Temp "get-pip.py"
    Fetch "https://bootstrap.pypa.io/get-pip.py" $getPip
    & "$pyDir\python.exe" $getPip --no-warn-script-location | Out-Null
    & "$pyDir\python.exe" -m pip install --no-warn-script-location python-frontmatter Pillow | Out-Null
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
    & "$pyDir\python.exe" -c "import sys; sys.path.insert(0, r'$RepoRoot\scripts'); import setup_course; setup_course.ensure_quartz_explorer_anchor(); setup_course.ensure_quartz_overflowlist_static_id()"
    if ($LASTEXITCODE -ne 0) { throw "Baking the Quartz scaffold patches failed" }
    if (-not (Select-String -Path "$quartzDir\quartz.layout.ts" -Pattern 'CQ4T-OMIT-ANCHOR' -Quiet)) {
        throw "quartz.layout.ts is missing the CQ4T-OMIT-ANCHOR marker - hidden pages would publish"
    }
    Remove-Item Env:\PLANTOIR_QUARTZ_DIR
    Remove-Item Env:\PLANTOIR_SUPPORT_DIR
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
    Fetch "https://github.com/googlefonts/noto-emoji/raw/$EmojiFontTag/fonts/NotoColorEmoji.ttf" (Join-Path $fontsDir "NotoColorEmoji.ttf")

    # ---- Manifest ------------------------------------------------------------
    @{
        node     = $NodeVersion
        python   = $PythonVersion
        quartz   = $QuartzTag
        wrangler = $WranglerVersion
        emoji    = $EmojiFontTag
        made     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    } | ConvertTo-Json | Set-Content $Manifest -Encoding utf8

    Write-Host ""
    Write-Host "[OK] Native runtime ready at $Runtime" -ForegroundColor Green
}
finally {
    Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue
}

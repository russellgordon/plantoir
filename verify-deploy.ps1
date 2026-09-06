<#
.SYNOPSIS
    Every destination, and every pairing, published for real and fetched back.
    The Windows counterpart of verify-deploy.sh.

.DESCRIPTION
    WHY THIS EXISTS AND WHY IT IS SEPARATE FROM THE SUITE
    =====================================================
    `verify.sh` is bash and does not run on Windows, and `verify-deploy.sh` is
    bash too — so until now the PowerShell half of publishing had NO automated
    gate of any kind. That is not a theoretical gap. It is exactly how
    `deploy.ps1` came to contain a check that was true for every site with two
    or more pages, which made publishing to a folder impossible on this
    platform and was found only by publishing by hand (GUI-IMPROVEMENTS row
    410).

    Like its mac sibling this is opt-in and never wired into anything: it needs
    credentials, it needs the network, and it CREATES REAL SITES on real
    accounts. Run it when the publishing path changes.

    WHAT IT IS GUARDING AGAINST, SPECIFICALLY
    =========================================
    Both of these shipped on one platform or the other, and neither was caught
    by a unit test:

      * A preview build reaching a published site. Serve mode bakes a
        live-reload client into every page; on a published site that script
        makes a student's browser ask permission to "access other apps and
        services on this device".
      * A publish that reported success and copied the wrong thing — or
        nothing at all.

    Both are invisible to any check that does not publish and then LOOK at what
    came out. That is this script's whole job.

    A NOTE ON WHAT "SKIP" MEANS HERE
    ================================
    A destination with no credentials on this machine is SKIPPED, loudly, and
    the run can still pass. A destination that is configured and then fails is
    a FAILURE. The distinction matters: a script that quietly passes because it
    ran nothing is the failure mode this whole file exists to prevent.

.PARAMETER WorkingFolder
    A Plantoir working folder. Defaults to a copy made for testing, never a
    teacher's own.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File verify-deploy.ps1 `
        -WorkingFolder "C:\Users\me\Desktop\plantoir-test" -Course ICS3U -Section 1
#>
[CmdletBinding()]
param(
    [string]$WorkingFolder = "$env:USERPROFILE\Desktop\plantoir-deploy-verify",
    [string]$Course = "ICS3U",
    [int]$Section = 1
)

$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
$script:Skip = 0
$script:Failures = @()

function Hdr([string]$text) {
    Write-Host ""
    Write-Host "== $text" -ForegroundColor Cyan
}
function Ok([string]$text) { $script:Pass++; Write-Host "  [ok]   $text" -ForegroundColor DarkGray }
function No([string]$text) { $script:Fail++; $script:Failures += $text; Write-Host "  [FAIL] $text" -ForegroundColor Red }
function Skipped([string]$text) { $script:Skip++; Write-Host "  [skip] $text" -ForegroundColor Yellow }

# ------------------------------------------------------------------ preflight
Hdr "Preflight - refuse clearly rather than half-running"

$config = Join-Path $WorkingFolder "courses\$Course\course_config.json"
if (-not (Test-Path $config)) {
    Write-Host "No course at $config" -ForegroundColor Red
    Write-Host "Point -WorkingFolder at a working folder that has one." -ForegroundColor Red
    exit 1
}
Ok "course found: $Course section $Section in $WorkingFolder"

# The course's own settings are restored on every exit path, including Ctrl+C.
$originalConfig = Get-Content -LiteralPath $config -Raw -Encoding UTF8
$work = Join-Path ([IO.Path]::GetTempPath()) ("plantoir-deploy-verify-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$folderTarget = Join-Path $work "published"

# UTF-8 with NO byte-order mark, always. Windows PowerShell 5.1's
# `-Encoding UTF8` writes a BOM, and `build_site.py` reads course_config.json
# as plain utf-8 and dies on it: "Unexpected UTF-8 BOM (decode using
# utf-8-sig)". Every publish in the first run of this script failed that way,
# and the failure looked exactly like a broken product rather than a broken
# test. The app itself never writes the file this way; only a script would.
$script:NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Utf8NoBom([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, $script:NoBom)
}

function Restore-Config {
    if ($originalConfig) { Write-Utf8NoBom $config $originalConfig }
}
trap { Restore-Config; break }

# Credentials decide what can be exercised. Read through the same Credential
# Manager target names deploy.ps1 uses, and never printed.
function Has-Credential([string]$target) {
    $listed = cmdkey /list:$target 2>&1 | Out-String
    return -not ($listed -match 'NONE' -or $listed -match 'Cannot find')
}
$haveNetlify = Has-Credential 'containerized-quartz-netlify'
$haveCloudflare = (Has-Credential 'containerized-quartz-cloudflare') -and (Has-Credential 'containerized-quartz-cloudflare-account')
if ($haveNetlify) { Ok "Netlify credentials present" } else { Skipped "no Netlify credentials - those cases will be skipped, not failed" }
if ($haveCloudflare) { Ok "Cloudflare credentials present" } else { Skipped "no Cloudflare credentials - those cases will be skipped, not failed" }

# ------------------------------------------------------------------- helpers
function Set-Destination {
    param([string]$Primary, [string]$FolderPath = "", [string]$AdditionalJson = "")
    $json = Get-Content -LiteralPath $config -Raw -Encoding UTF8 | ConvertFrom-Json
    $json.deploy_target = $Primary
    if ($json.PSObject.Properties.Name -contains 'deploy_folder_path') { $json.deploy_folder_path = $FolderPath }
    else { $json | Add-Member -NotePropertyName deploy_folder_path -NotePropertyValue $FolderPath }
    if ($AdditionalJson) {
        $json | Add-Member -NotePropertyName additional_deploy_targets -NotePropertyValue (ConvertFrom-Json $AdditionalJson) -Force
    } elseif ($json.PSObject.Properties.Name -contains 'additional_deploy_targets') {
        $json.PSObject.Properties.Remove('additional_deploy_targets')
    }
    Write-Utf8NoBom $config ($json | ConvertTo-Json -Depth 30)
}

function Run-Launcher {
    param([string]$Script, [string[]]$LauncherArgs, [string]$LogFile, [int]$TimeoutSeconds = 900)
    Remove-Item $LogFile -ErrorAction SilentlyContinue
    $quoted = ($LauncherArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $process = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c", ".\$Script $quoted > `"$LogFile`" 2>&1" `
        -WorkingDirectory $WorkingFolder -PassThru -WindowStyle Hidden
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill($true) } catch { }
        return @{ ExitCode = 124; Log = "" }
    }
    $text = if (Test-Path $LogFile) { Get-Content $LogFile -Raw } else { "" }
    return @{ ExitCode = $process.ExitCode; Log = $text }
}

function Check-Folder {
    param([string]$What, [string]$Path)
    if (-not (Test-Path (Join-Path $Path "index.html"))) { No "$What - no front page was written"; return }
    $pages = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Filter *.html -ErrorAction SilentlyContinue)
    if ($pages.Count -eq 0) { No "$What - nothing was published"; return }
    Ok "$What - $($pages.Count) pages written, front page present"
    $dirty = @($pages | Select-String -Pattern "ws://localhost:" -List | Select-Object -First 1)
    if ($dirty.Count -gt 0) { No "$What - the published site carries the preview's live-reload client" }
    else { Ok "$What - no page carries the live-reload client" }
}

function Check-Url {
    param([string]$What, [string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 60
        if ($response.StatusCode -ne 200) { No "$What answered HTTP $($response.StatusCode)"; return }
        Ok "$What answered HTTP 200"
        if ($response.Content -match 'ws://localhost:') { No "$What is serving the preview's live-reload client" }
        else { Ok "$What carries no live-reload client" }
    } catch { No "$What could not be fetched: $($_.Exception.Message)" }
}

function Url-FromLog([string]$log) {
    $m = [regex]::Match($log, 'https://[^\s""]+\.(?:netlify\.app|pages\.dev)')
    if ($m.Success) { return $m.Value }
    return ""
}

# --------------------------------------------------- the preview, and the race
Hdr "Preview - serve mode, which is what a teacher actually uses"
$previewLog = Join-Path $work "preview.log"
$previewProcess = Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c", ".\preview.bat $Course $Section > `"$previewLog`" 2>&1" `
    -WorkingDirectory $WorkingFolder -PassThru -WindowStyle Hidden

$port = $null
$deadline = (Get-Date).AddMinutes(10)
while ((Get-Date) -lt $deadline -and -not $port) {
    Start-Sleep -Seconds 5
    if (Test-Path $previewLog) {
        $text = Get-Content $previewLog -Raw -ErrorAction SilentlyContinue
        if ($text -match 'available at: http://localhost:(\d+)') { $port = $Matches[1] }
    }
}
if (-not $port) {
    No "the preview never announced an address"
} else {
    Ok "the preview announced port $port"
    $served = $false
    foreach ($i in 1..40) {
        try {
            $r = Invoke-WebRequest "http://localhost:$port/" -UseBasicParsing -TimeoutSec 5
            if ($r.StatusCode -eq 200) { $served = $true; break }
        } catch { }
        Start-Sleep -Seconds 5
    }
    if (-not $served) { No "the preview never answered" }
    else {
        Ok "the preview serves its front page"
        if ($r.Content -match 'ws://localhost') { Ok "the preview carries the live-reload client, as a preview should" }
        else { No "the preview has no live-reload client - serve mode may not be running" }
    }
}

# Killing the LAUNCHER is what a teacher closing a window does, and it does NOT
# stop the preview: the node server and its Python parent outlive it, and the
# parent's sync watcher goes on mirroring the SERVE build into the section's
# build directory about once a second. The next case publishes into exactly
# that state.
if ($previewProcess -and -not $previewProcess.HasExited) { try { $previewProcess.Kill($true) } catch { } }
Start-Sleep -Seconds 3

Hdr "Publishing straight after a preview must not ship the live-reload client"
Remove-Item -Recurse -Force $folderTarget -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $folderTarget | Out-Null
Set-Destination -Primary "local_folder" -FolderPath $folderTarget
$afterPreview = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--to-folder", $folderTarget) -LogFile (Join-Path $work "deploy-after-preview.log")
if ($afterPreview.ExitCode -ne 0) { No "publishing after a preview exited $($afterPreview.ExitCode)" }
else { Ok "publishing after a preview exited 0" }
# Asserted, not skipped. A preview WAS left serving above, so if nothing was
# stopped the race is back - and a check that can only pass or be skipped
# proves nothing.
if ($afterPreview.Log -match 'Stopped the preview that was still serving this section') {
    Ok "the rebuild stopped the preview still serving THIS section, so it could not overwrite"
} else {
    No "nothing stopped the preview that was still serving - the race is back"
}
if ($afterPreview.Log -match 'Killed existing process on port') {
    No "a preview was stopped BY PORT, which takes down other sections' previews"
} else {
    Ok "no preview was stopped by port"
}
Check-Folder "folder (after a preview)" (Join-Path $folderTarget "section$Section")

# ----------------------------------------------- each destination on its own
Hdr "Destination 1 of 3 - a folder on this PC"
Remove-Item -Recurse -Force $folderTarget -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $folderTarget | Out-Null
Set-Destination -Primary "local_folder" -FolderPath $folderTarget
$folderRun = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--to-folder", $folderTarget) -LogFile (Join-Path $work "deploy-folder.log")
if ($folderRun.ExitCode -eq 0) { Ok "publish to a folder exited 0" } else { No "publish to a folder exited $($folderRun.ExitCode)" }
Check-Folder "folder" (Join-Path $folderTarget "section$Section")

Hdr "Destination 2 of 3 - Netlify"
if ($haveNetlify) {
    Set-Destination -Primary "netlify"
    $netlifyRun = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section") -LogFile (Join-Path $work "deploy-netlify.log")
    if ($netlifyRun.ExitCode -eq 0) { Ok "publish to Netlify exited 0" } else { No "publish to Netlify exited $($netlifyRun.ExitCode)" }
    $netlifyUrl = Url-FromLog $netlifyRun.Log
    if ($netlifyUrl) { Check-Url "Netlify" $netlifyUrl } else { No "no Netlify address in the output" }
} else { Skipped "Netlify (no credentials)" }

Hdr "Destination 3 of 3 - Cloudflare Pages"
if ($haveCloudflare) {
    Set-Destination -Primary "cloudflare_pages"
    $cloudflareRun = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section") -LogFile (Join-Path $work "deploy-cloudflare.log")
    if ($cloudflareRun.ExitCode -eq 0) { Ok "publish to Cloudflare exited 0" } else { No "publish to Cloudflare exited $($cloudflareRun.ExitCode)" }
    $cloudflareUrl = Url-FromLog $cloudflareRun.Log
    if ($cloudflareUrl) { Check-Url "Cloudflare Pages" $cloudflareUrl } else { No "no Cloudflare address in the output" }
} else { Skipped "Cloudflare Pages (no credentials)" }

# ------------------------------------------------------------- the pairings
# Run as the APP runs them: the primary first, then each additional, one
# launcher call apiece. `additional_deploy_targets` is not handled by the
# launcher at all - the app loops - so this exercises the launcher half the way
# the app drives it. That the app produces exactly these argument lists is a
# separate question, already pinned by app-rules.json -> deployArguments.
Hdr "Pairing 1 of 3 - Netlify primary, a folder also"
if ($haveNetlify) {
    Remove-Item -Recurse -Force $folderTarget -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $folderTarget | Out-Null
    Set-Destination -Primary "netlify" -AdditionalJson "[{`"type`":`"local_folder`",`"folder_path`":`"$($folderTarget -replace '\\','\\\\')`"}]"
    $legOne = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section") -LogFile (Join-Path $work "pair1-netlify.log")
    $legTwo = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--to-folder", $folderTarget) -LogFile (Join-Path $work "pair1-folder.log")
    if ($legOne.ExitCode -eq 0 -and $legTwo.ExitCode -eq 0) { Ok "both legs exited 0" }
    else { No "a leg failed (netlify $($legOne.ExitCode), folder $($legTwo.ExitCode))" }
    $u = Url-FromLog $legOne.Log
    if ($u) { Check-Url "Netlify (paired)" $u } else { No "no Netlify address in the paired output" }
    Check-Folder "folder (paired)" (Join-Path $folderTarget "section$Section")
} else { Skipped "Netlify + folder (no Netlify credentials)" }

Hdr "Pairing 2 of 3 - Cloudflare primary, a folder also"
if ($haveCloudflare) {
    Remove-Item -Recurse -Force $folderTarget -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $folderTarget | Out-Null
    Set-Destination -Primary "cloudflare_pages" -AdditionalJson "[{`"type`":`"local_folder`",`"folder_path`":`"$($folderTarget -replace '\\','\\\\')`"}]"
    $legOne = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section") -LogFile (Join-Path $work "pair2-cf.log")
    $legTwo = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--to-folder", $folderTarget) -LogFile (Join-Path $work "pair2-folder.log")
    if ($legOne.ExitCode -eq 0 -and $legTwo.ExitCode -eq 0) { Ok "both legs exited 0" }
    else { No "a leg failed (cloudflare $($legOne.ExitCode), folder $($legTwo.ExitCode))" }
    Check-Folder "folder (paired with Cloudflare)" (Join-Path $folderTarget "section$Section")
} else { Skipped "Cloudflare + folder (no Cloudflare credentials)" }

Hdr "Pairing 3 of 3 - Netlify primary, Cloudflare also"
if ($haveNetlify -and $haveCloudflare) {
    Set-Destination -Primary "netlify" -AdditionalJson '[{"type":"cloudflare_pages"}]'
    $legOne = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section") -LogFile (Join-Path $work "pair3-netlify.log")
    Set-Destination -Primary "cloudflare_pages"
    $legTwo = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section") -LogFile (Join-Path $work "pair3-cf.log")
    if ($legOne.ExitCode -eq 0 -and $legTwo.ExitCode -eq 0) { Ok "both legs exited 0" }
    else { No "a leg failed (netlify $($legOne.ExitCode), cloudflare $($legTwo.ExitCode))" }
    $u1 = Url-FromLog $legOne.Log; if ($u1) { Check-Url "Netlify (paired with Cloudflare)" $u1 }
    $u2 = Url-FromLog $legTwo.Log; if ($u2) { Check-Url "Cloudflare (paired with Netlify)" $u2 }
} else { Skipped "Netlify + Cloudflare (needs both sets of credentials)" }

# ------------------------------------------------------------------ finishing
Restore-Config
Hdr "Result"
Write-Host "  $($script:Pass) passed, $($script:Fail) failed, $($script:Skip) skipped"
Write-Host "  logs: $work"
if ($script:Fail -gt 0) {
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($f in $script:Failures) { Write-Host "    - $f" -ForegroundColor Red }
    exit 1
}
exit 0

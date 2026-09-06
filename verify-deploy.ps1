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

# Kill a process AND ITS CHILDREN.
#
# `$process.Kill($true)` is what this used to call, and under Windows
# PowerShell 5.1 it does not exist: System.Diagnostics.Process there offers
# only `Kill()` — the boolean overload is .NET Core 3 and later. The call threw
# and an empty catch swallowed it, so a timed-out launcher was never stopped at
# all. Two runs of this script left a powershell.exe and its python.exe child
# sitting at a prompt for forty-five minutes because of it.
#
# `Kill()` alone would not be enough either: it ends the shell and leaves the
# Python and node underneath it running, which is the very orphaning this
# repository's stop-preview work is about. taskkill /T walks the tree.
function Stop-Tree([int]$processId) {
    try { & taskkill.exe /PID $processId /T /F *> $null } catch { }
}

# The preview launched below, so it can be stopped on EVERY exit path.
$script:PreviewProcess = $null
function Stop-AnyPreview {
    if ($script:PreviewProcess -and -not $script:PreviewProcess.HasExited) {
        Stop-Tree $script:PreviewProcess.Id
    }
    # And the section's own processes, through the launcher's own stop mode -
    # the same sweep the app uses, so a run that dies early does not leave a
    # preview serving for the next one to trip over.
    try {
        & cmd.exe /c "cd /d `"$WorkingFolder`" && .\preview.bat $Course $Section --stop" *> $null
    } catch { }
}

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
    param([string]$Script, [string[]]$LauncherArgs, [string]$LogFile, [int]$TimeoutSeconds = 900,
          [string[]]$Answers = @())
    Remove-Item $LogFile -ErrorAction SilentlyContinue
    $quoted = ($LauncherArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '

    # A first publish to Netlify ASKS things - a surname, and a site name - and
    # so does a publish whose saved site has been deleted upstream, which is
    # what happened on the first real run of this script: the launcher fell
    # through to "create a fresh site", asked for a name, and the run sat there
    # until the timeout.
    #
    # WHAT ACTUALLY FIXES IT IS NOT THE ANSWERS. `deploy.py` asks nothing when
    # its stdin is not a terminal - `sys.stdin.isatty()` guards every prompt
    # (deploy.py:285, :326, :430) and it takes the default instead. Redirecting
    # stdin from a FILE is what makes isatty() false; the contents are never
    # read on this path. An earlier version of this comment, and the commit
    # that introduced it, both claimed the harness "answers prompts". It does
    # not, and the difference matters: with no surname saved, the site is named
    # without one, where the mac's `expect` would send "Testing".
    #
    # The lines are kept because `deploy.ps1`'s OWN `Read-Host` calls (the
    # zero-fix question, the token pastes) are not isatty-guarded and would
    # consume them - none fire in this flow, but a future one might.
    $stdin = $null
    if ($Answers.Count -gt 0) {
        $stdin = Join-Path $work ("answers-" + [Guid]::NewGuid().ToString('N').Substring(0,6) + ".txt")
        Write-Utf8NoBom $stdin (($Answers -join "`r`n") + "`r`n")
    }
    # The launcher is run from a generated .cmd rather than invoked directly,
    # so that cmd records its OWN errorlevel to a file.
    #
    # Why not just read $process.ExitCode: `Start-Process -PassThru` combined
    # with `-RedirectStandardInput` returns a process whose ExitCode is EMPTY
    # even though HasExited is True. Measured on this machine - the identical
    # call WITHOUT the redirect returns the code correctly, with it the
    # property is blank. Two real Netlify publishes were reported as failures
    # by this script for that reason alone, while the site they had just
    # published answered HTTP 200. A harness that calls a success a failure is
    # worse than no harness: the next person spends the evening looking for a
    # bug in the product.
    $codeFile = Join-Path $work ("code-" + [Guid]::NewGuid().ToString('N').Substring(0,6) + ".txt")
    $runner = Join-Path $work ("run-" + [Guid]::NewGuid().ToString('N').Substring(0,6) + ".cmd")
    Write-Utf8NoBom $runner (@(
        "@echo off",
        "call .\$Script $quoted > `"$LogFile`" 2>&1",
        "echo %ERRORLEVEL% > `"$codeFile`""
    ) -join "`r`n")

    $startArgs = @{
        FilePath = $runner
        WorkingDirectory = $WorkingFolder
        PassThru = $true
        WindowStyle = "Hidden"
    }
    if ($stdin) { $startArgs["RedirectStandardInput"] = $stdin }
    $process = Start-Process @startArgs
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Tree $process.Id
        $partial = if (Test-Path $LogFile) { Get-Content $LogFile -Raw } else { "" }
        # 124 is "timed out", kept distinct from any code the launcher itself
        # can return, so a hang never reads as a refusal.
        return @{ ExitCode = 124; Log = $partial }
    }
    try { $process.WaitForExit() } catch { }

    $text = if (Test-Path $LogFile) { Get-Content $LogFile -Raw } else { "" }
    $code = -1
    if (Test-Path $codeFile) {
        $raw = (Get-Content $codeFile -Raw).Trim()
        if ($raw -match '^-?\d+$') { $code = [int]$raw }
    }
    return @{ ExitCode = $code; Log = $text }
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

# Which host a published address belongs to. A publish is only proved by an
# address of the RIGHT KIND: the first version of this script checked a
# netlify.app URL and called it a Cloudflare pass.
function Expected-Host([string]$destination) {
    if ($destination -eq 'cloudflare_pages') { return 'pages.dev' }
    return 'netlify.app'
}

function Check-Url {
    param([string]$What, [string]$Url, [int]$Attempts = 12, [string]$MustEndWith = "")
    # A site created moments ago does not answer immediately - the first run of
    # this script reported a 404 for a Netlify site that answered 200 a few
    # minutes later in the very next case. A publish is not wrong because DNS
    # is slow, so this waits rather than judging on the first try.
    $response = $null
    foreach ($attempt in 1..$Attempts) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 60
            if ($response.StatusCode -eq 200) { break }
        } catch { $response = $null }
        if ($attempt -lt $Attempts) { Start-Sleep -Seconds 20 }
    }
    try {
        if ($null -eq $response) { No "$What could not be fetched after $Attempts tries"; return }
        if ($response.StatusCode -ne 200) { No "$What answered HTTP $($response.StatusCode)"; return }
        # The address must belong to the host this case is about. Without this,
        # a leg that silently published somewhere ELSE passes: the Cloudflare
        # cases did exactly that, verifying a netlify.app address three times
        # over and reporting three green Cloudflare publishes.
        if ($MustEndWith -and -not ($Url -match ([regex]::Escape($MustEndWith) + '(/|$)'))) {
            No "$What answered, but at $Url - that is not a $MustEndWith address, so this destination did not publish"
            return
        }
        Ok "$What answered HTTP 200"
        if ($response.Content -match 'ws://localhost:') { No "$What is serving the preview's live-reload client" }
        else { Ok "$What carries no live-reload client" }
    } catch { No "$What could not be fetched: $($_.Exception.Message)" }
}

function Url-FromLog([string]$log) {
    # PREFER the production address over a deployment-specific one. Cloudflare
    # prints both - "https://21a7e1ae.mcr3u-....pages.dev" for that particular
    # deployment and "https://mcr3u-....pages.dev" for the site itself - and
    # taking the first match took the hashed one. On a project's FIRST publish
    # that subdomain needs longer to resolve than the site does, so a real,
    # successful publish was reported as "could not be fetched after 6 tries"
    # while the site itself was already serving. It is also simply the wrong
    # thing to check: the production address is the one a teacher gives out.
    $all = [regex]::Matches($log, 'https://[^\s""]+\.(?:netlify\.app|pages\.dev)') |
           ForEach-Object { $_.Value } | Select-Object -Unique
    if (-not $all) { return "" }
    $plain = $all | Where-Object {
        $hostName = ([Uri]$_).Host
        # A deployment-specific Cloudflare address has one extra label in front
        # of the project name: <hash>.<project>.pages.dev is four labels,
        # <project>.pages.dev is three.
        -not ($hostName -like "*.pages.dev" -and ($hostName.Split(".").Count -gt 3))
    }
    if ($plain) { return @($plain)[0] }
    return @($all)[0]
}

# Everything from here is wrapped so the course's own settings are put back on
# EVERY exit path. It used to rely on `trap`, which does not run on Ctrl+C -
# so interrupting a run left the course pointed at whichever destination the
# script had been testing at the time.
try {

# --------------------------------------------------- the preview, and the race
Hdr "Preview - serve mode, which is what a teacher actually uses"
$previewLog = Join-Path $work "preview.log"
$previewProcess = Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c", ".\preview.bat $Course $Section > `"$previewLog`" 2>&1" `
    -WorkingDirectory $WorkingFolder -PassThru -WindowStyle Hidden
$script:PreviewProcess = $previewProcess

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
#
# THIS ONE KILL MUST NOT WALK THE TREE, and that is the whole case. It briefly
# used Stop-Tree, which is taskkill /T, and taskkill /T takes the node server
# and the Python down with the launcher - so there was no orphaned preview
# left, nothing for the publish to stop, and the assertion below failed
# claiming the race was back. The harness had quietly stopped reproducing its
# own precondition. Killing ONLY this process is what leaves the preview
# serving, which is the state a teacher is really in.
if ($previewProcess -and -not $previewProcess.HasExited) {
    try { Stop-Process -Id $previewProcess.Id -Force -ErrorAction Stop } catch { }
}
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
    $netlifyRun = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section") -LogFile (Join-Path $work "deploy-netlify.log") -Answers @("Testing", "", "y")
    if ($netlifyRun.ExitCode -eq 0) { Ok "publish to Netlify exited 0" } else { No "publish to Netlify exited $($netlifyRun.ExitCode)" }
    $netlifyUrl = Url-FromLog $netlifyRun.Log
    if ($netlifyUrl) { Check-Url "Netlify" $netlifyUrl -MustEndWith "netlify.app" } else { No "no Netlify address in the output" }
} else { Skipped "Netlify (no credentials)" }

Hdr "Destination 3 of 3 - Cloudflare Pages"
if ($haveCloudflare) {
    Set-Destination -Primary "cloudflare_pages"
    # --target is REQUIRED: deploy.ps1 defaults $TARGET to netlify and never
    # reads deploy_target from the configuration. Setting the config key alone
    # published to Netlify while this script reported a Cloudflare pass.
    $cloudflareRun = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--target", "cloudflare") -LogFile (Join-Path $work "deploy-cloudflare.log") -Answers @("Testing", "", "y")
    if ($cloudflareRun.ExitCode -eq 0) { Ok "publish to Cloudflare exited 0" } else { No "publish to Cloudflare exited $($cloudflareRun.ExitCode)" }
    if ($cloudflareRun.Log -match '(?i)cloudflare|wrangler|pages\.dev') { Ok "the launcher really went to Cloudflare" }
    else { No "the Cloudflare leg's output never mentions Cloudflare - it published somewhere else" }
    $cloudflareUrl = Url-FromLog $cloudflareRun.Log
    if ($cloudflareUrl) { Check-Url "Cloudflare Pages" $cloudflareUrl -MustEndWith "pages.dev" } else { No "no Cloudflare address in the output" }
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
    Set-Destination -Primary "netlify" -AdditionalJson "[{`"type`":`"local_folder`",`"folder_path`":`"$($folderTarget.Replace('\','\\'))`"}]"
    $legOne = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section") -LogFile (Join-Path $work "pair1-netlify.log") -Answers @("Testing", "", "y")
    $legTwo = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--to-folder", $folderTarget) -LogFile (Join-Path $work "pair1-folder.log")
    if ($legOne.ExitCode -eq 0 -and $legTwo.ExitCode -eq 0) { Ok "both legs exited 0" }
    else { No "a leg failed (netlify $($legOne.ExitCode), folder $($legTwo.ExitCode))" }
    $u = Url-FromLog $legOne.Log
    if ($u) { Check-Url "Netlify (paired)" $u -MustEndWith "netlify.app" } else { No "no Netlify address in the paired output" }
    Check-Folder "folder (paired)" (Join-Path $folderTarget "section$Section")
} else { Skipped "Netlify + folder (no Netlify credentials)" }

Hdr "Pairing 2 of 3 - Cloudflare primary, a folder also"
if ($haveCloudflare) {
    Remove-Item -Recurse -Force $folderTarget -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $folderTarget | Out-Null
    Set-Destination -Primary "cloudflare_pages" -AdditionalJson "[{`"type`":`"local_folder`",`"folder_path`":`"$($folderTarget.Replace('\','\\'))`"}]"
    $legOne = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--target", "cloudflare") -LogFile (Join-Path $work "pair2-cf.log") -Answers @("Testing", "", "y")
    $legTwo = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--to-folder", $folderTarget) -LogFile (Join-Path $work "pair2-folder.log")
    if ($legOne.ExitCode -eq 0 -and $legTwo.ExitCode -eq 0) { Ok "both legs exited 0" }
    else { No "a leg failed (cloudflare $($legOne.ExitCode), folder $($legTwo.ExitCode))" }
    $cfPaired = Url-FromLog $legOne.Log
    if ($cfPaired) { Check-Url "Cloudflare (paired with a folder)" $cfPaired -MustEndWith "pages.dev" }
    else { No "no Cloudflare address in the paired output" }
    Check-Folder "folder (paired with Cloudflare)" (Join-Path $folderTarget "section$Section")
} else { Skipped "Cloudflare + folder (no Cloudflare credentials)" }

Hdr "Pairing 3 of 3 - Netlify primary, Cloudflare also"
if ($haveNetlify -and $haveCloudflare) {
    Set-Destination -Primary "netlify" -AdditionalJson '[{"type":"cloudflare_pages"}]'
    $legOne = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section") -LogFile (Join-Path $work "pair3-netlify.log") -Answers @("Testing", "", "y")
    Set-Destination -Primary "cloudflare_pages"
    $legTwo = Run-Launcher -Script "deploy.bat" -LauncherArgs @($Course, "$Section", "--target", "cloudflare") -LogFile (Join-Path $work "pair3-cf.log") -Answers @("Testing", "", "y")
    if ($legOne.ExitCode -eq 0 -and $legTwo.ExitCode -eq 0) { Ok "both legs exited 0" }
    else { No "a leg failed (netlify $($legOne.ExitCode), cloudflare $($legTwo.ExitCode))" }
    $u1 = Url-FromLog $legOne.Log; if ($u1) { Check-Url "Netlify (paired with Cloudflare)" $u1 -MustEndWith "netlify.app" }
    $u2 = Url-FromLog $legTwo.Log; if ($u2) { Check-Url "Cloudflare (paired with Netlify)" $u2 -MustEndWith "pages.dev" }
} else { Skipped "Netlify + Cloudflare (needs both sets of credentials)" }

# ------------------------------------------------------------------ finishing
Hdr "Result"
Write-Host "  $($script:Pass) passed, $($script:Fail) failed, $($script:Skip) skipped"
Write-Host "  logs: $work"
if ($script:Fail -gt 0) {
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($f in $script:Failures) { Write-Host "    - $f" -ForegroundColor Red }
    exit 1
}
exit 0

}
finally {
    Restore-Config
    Stop-AnyPreview
}

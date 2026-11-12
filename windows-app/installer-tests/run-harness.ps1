<#
.SYNOPSIS
  Proves installer-running-work.iss (#700) on a HARNESS installer, never on
  the real Plantoir.

.DESCRIPTION
  Builds a few-KB stand-in program (StandIn.cs, with the .NET Framework's
  csc.exe), compiles harness.iss twice (version 1 and version 2) with the
  Inno Setup compiler, and for each case: installs harness version 1 into
  %LOCALAPPDATA%\Temp\plantoir-installer-harness\app, starts stand-ins FROM
  that folder in the shapes that matter (a preview serving, a build that ends,
  work that never ends, work that starts during the wait), runs version 2 with
  the app's own silent update arguments, and checks what happened. Then it
  uninstalls the harness and removes its folder and uninstall key.

  Every run is /VERYSILENT /SUPPRESSMSGBOXES: no wizard, no box, no sound.
  The real Plantoir (its folder under %LOCALAPPDATA%\Programs\Plantoir and its
  uninstall key) is listed before and after, and the run FAILS if either
  changed.

  -MustFail compiles version 2 against edited copies of the include, one rule
  broken at a time, and checks that the case that rule protects goes wrong.

  Exit code: 0 when every case passed, 1 otherwise, 2 when it could not run
  (no ISCC, no csc).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File windows-app\installer-tests\run-harness.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File windows-app\installer-tests\run-harness.ps1 -MustFail
#>
param(
    [string[]]$Case = @(),
    [switch]$MustFail,
    [string]$Iscc = ''
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsApp = Split-Path -Parent $here
$include = Join-Path $windowsApp 'installer-running-work.iss'

# ---- Tools ------------------------------------------------------------------
if (-not $Iscc) {
    foreach ($candidate in @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe")) {
        if (Test-Path $candidate) { $Iscc = $candidate; break }
    }
}
if (-not $Iscc -or -not (Test-Path $Iscc)) { Write-Host 'NO ISCC: Inno Setup 6 is not installed; the harness cannot run.'; exit 2 }
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { Write-Host "NO CSC at $csc; the harness cannot run."; exit 2 }

# ---- Where everything goes ----------------------------------------------------
$work = Join-Path $env:TEMP ('plantoir-installer-harness-build-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null
$appDir = Join-Path $env:LOCALAPPDATA 'Temp\plantoir-installer-harness\app'
$record = Join-Path $env:TEMP 'plantoir-installer-harness\started.txt'
$harnessKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{D7A92D73-E5AF-4D50-978A-D127394C485D}_is1'
$ownerApp = Join-Path $env:LOCALAPPDATA 'Programs\Plantoir'
$ownerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{A14C3E2D-5F6B-4820-9D7A-83B92A769CE1}}_is1'   # sic: installer.iss's AppId ends in }}, and Inno keeps the second brace
$updateArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCLOSEAPPLICATIONS /PLANTOIRUPDATE=1'
$handArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
# The installer's markers go to a state folder of the harness's own, NEVER the
# real %LOCALAPPDATA%\Plantoir (/STATEDIR=, as the app passes a redirected one).
$stateDir = Join-Path $work 'state'
$updateArgs += " `"/STATEDIR=$stateDir`""
$handArgs += " `"/STATEDIR=$stateDir`""
$refusalMarker = Join-Path $stateDir 'update-not-installed.txt'

# ---- The owner's real install: listed before, compared after ------------------
function Get-OwnerFingerprint {
    $files = 'absent'
    if (Test-Path $ownerApp) {
        $lines = Get-ChildItem -LiteralPath $ownerApp -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object { '{0}|{1}|{2:o}' -f $_.FullName.Substring($ownerApp.Length), $_.Length, $_.LastWriteTimeUtc } | Sort-Object
        $files = "$($lines.Count) files, " + (Get-StringHash ($lines -join "`n"))
    }
    $key = 'absent'
    if (Test-Path -LiteralPath $ownerKey) {
        $props = Get-ItemProperty -LiteralPath $ownerKey
        $key = Get-StringHash (($props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } |
            ForEach-Object { "$($_.Name)=$($_.Value)" } | Sort-Object) -join "`n")
    }
    "folder: $files; key: $key"
}
function Get-StringHash([string]$text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))) -replace '-', '').Substring(0, 16)
}

# ---- The harness's [InstallDelete] must be installer.iss's --------------------
function Get-InstallDeleteLines([string]$path) {
    $text = Get-Content -LiteralPath $path
    $in = $false
    foreach ($line in $text) {
        if ($line -match '^\[') { $in = ($line -match '^\[InstallDelete\]') ; continue }
        if ($in -and $line -match '^Type:') { $line.Trim() }
    }
}
$shipped = @(Get-InstallDeleteLines (Join-Path $windowsApp 'installer.iss'))
$ours = @(Get-InstallDeleteLines (Join-Path $here 'harness.iss'))
if (($shipped -join "`n") -ne ($ours -join "`n")) {
    Write-Host "harness.iss's [InstallDelete] is not installer.iss's:"; Write-Host ($shipped -join "`n"); Write-Host '---'; Write-Host ($ours -join "`n")
    exit 1
}

# ---- Build the stand-in and the two payloads ----------------------------------
$standIn = Join-Path $work 'StandIn.exe'
& $csc /nologo /optimize /target:exe "/out:$standIn" (Join-Path $here 'StandIn.cs') | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'csc failed' }

function New-Payload([string]$version) {
    $p = Join-Path $work "payload-$version"
    $python = if ($version -eq '1') { 'python311' } else { 'python314' }
    $files = @{
        'Plantoir.exe' = $standIn; 'plantoir-mcp.exe' = $standIn; 'llama\llama-server.exe' = $standIn
        'runtime\node\node.exe' = $standIn; 'runtime\python\python.exe' = $standIn
    }
    foreach ($rel in $files.Keys) {
        New-Item -ItemType Directory -Force (Split-Path -Parent (Join-Path $p $rel)) | Out-Null
        Copy-Item $files[$rel] (Join-Path $p $rel)
    }
    $texts = @{
        "version.txt" = $version
        "runtime\node\npm-v$version.txt" = $version
        "runtime\python\$python.dll" = $version
        "runtime\python\$python.zip" = $version
        "runtime\wrangler\node_modules\pkg-v$version\index.js" = $version
        "runtime\wrangler\bin\wrangler.js" = $version
        "runtime\vendor\geogebra\ggb-v$version.txt" = $version
        "runtime\vendor\tikz-engine\node_modules\tikz-v$version\index.js" = $version
        "runtime\quartz\quartz.layout.ts" = $version
        "Toolchain\scripts\build_site.py" = "# $version"
    }
    foreach ($rel in $texts.Keys) {
        New-Item -ItemType Directory -Force (Split-Path -Parent (Join-Path $p $rel)) | Out-Null
        Set-Content -LiteralPath (Join-Path $p $rel) -Value $texts[$rel] -Encoding ascii
    }
    $p
}
$payload1 = New-Payload '1'
$payload2 = New-Payload '2'

function Invoke-Compile([string]$version, [string]$payload, [string]$out, [string]$includePath, [string[]]$extra = @()) {
    New-Item -ItemType Directory -Force $out | Out-Null
    $isccArgs = @("/Q", "/DHarnessVersion=$version", "/DPayloadDir=$payload", "/DOutputFolder=$out")
    if ($includePath) { $isccArgs += "/DRunningWorkInclude=$includePath" }
    foreach ($define in $extra) { $isccArgs += "/D$define" }
    & $Iscc @isccArgs (Join-Path $here 'harness.iss') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "ISCC failed for harness version $version" }
    Join-Path $out "HarnessSetup-$version.exe"
}
$setup1 = Invoke-Compile '1' $payload1 (Join-Path $work 'out') ''
$setup2 = Invoke-Compile '2' $payload2 (Join-Path $work 'out') ''
# Version 2 with only the ssInstall look (PrepareToInstall answers ''), for the 'ssinstall' case.
$setup2Ss = Invoke-Compile '2' $payload2 (Join-Path $work 'out-ssinstall') '' @('HarnessOnlyAtSsInstall=1')

# Never Start-Process -Wait: in Windows PowerShell it waits for every
# DESCENDANT too, and a refused update starts Plantoir, which never exits.

# ---- Helpers --------------------------------------------------------------------
function Get-Tree {
    if (-not (Test-Path $appDir)) { return @() }
    Get-ChildItem -LiteralPath $appDir -Recurse -Force -File | Where-Object { $_.Name -notlike 'unins*' } | ForEach-Object {
        '{0}|{1}|{2}' -f $_.FullName.Substring($appDir.Length + 1), $_.Length, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    } | Sort-Object
}
function Get-PayloadTree([string]$payload) {
    Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object {
        '{0}|{1}|{2}' -f $_.FullName.Substring($payload.Length + 1), $_.Length, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    } | Sort-Object
}
$tree2 = @(Get-PayloadTree $payload2)

function Stop-HarnessProcesses {
    Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($appDir, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
function Remove-Harness {
    Stop-HarnessProcesses
    Start-Sleep -Milliseconds 300
    $unins = Join-Path $appDir 'unins000.exe'
    if (Test-Path $unins) {
        $p = Start-Process -FilePath $unins -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -PassThru; $p.WaitForExit()
        # The uninstaller copies itself to %TEMP% and returns at once; wait for the copy.
        for ($i = 0; $i -lt 60 -and (Test-Path -LiteralPath $harnessKey); $i++) { Start-Sleep -Milliseconds 250 }
    }
    if (Test-Path $appDir) { Remove-Item -LiteralPath $appDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $harnessKey) { Remove-Item -LiteralPath $harnessKey -Recurse -Force }
}
function Install-Version1 {
    Remove-Harness
    $p = Start-Process -FilePath $setup1 -ArgumentList "$handArgs /LOG=`"$work\install-v1.log`"" -PassThru; $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "harness version 1 did not install (exit $($p.ExitCode))" }
    if (-not (Test-Path (Join-Path $appDir 'runtime\node\node.exe'))) { throw 'harness version 1 is not where it should be' }
    # What a 1.9.0 working folder's builds leave behind (results.md, case A).
    New-Item -ItemType Directory -Force (Join-Path $appDir 'Toolchain\scripts\__pycache__') | Out-Null
    Set-Content (Join-Path $appDir 'Toolchain\scripts\__pycache__\build_site.cpython-311.pyc') 'old' -Encoding ascii
    if (Test-Path $record) { Remove-Item $record -Force }
    if (Test-Path $stateDir) { Remove-Item -LiteralPath $stateDir -Recurse -Force }
}
function Get-MarkerReason { if (Test-Path $refusalMarker) { @(Get-Content $refusalMarker)[1] } else { '' } }
function Test-InstallingLeft { @(Get-ChildItem -Path $stateDir -Filter 'installing.*' -ErrorAction SilentlyContinue).Count -gt 0 }
function Start-StandIn([string]$relative, [string]$arguments) {
    Start-Process -FilePath (Join-Path $appDir $relative) -ArgumentList $arguments -PassThru -WindowStyle Hidden
}
function Invoke-Version2([string]$setup, [string]$arguments, [string]$name) {
    $log = Join-Path $work "setup-$name.log"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $setup -ArgumentList "$arguments /LOG=`"$log`"" -PassThru; $p.WaitForExit()
    $watch.Stop()
    [PSCustomObject]@{ Exit = $p.ExitCode; Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1); Log = $log }
}
function Get-Started { if (Test-Path $record) { @(Get-Content $record) } else { @() } }
function Test-ExitedByItself($process) { $process.HasExited -and $process.ExitCode -eq 0 }
function Test-IsV2 { $now = @(Get-Tree); (($now -join "`n") -eq ($tree2 -join "`n")) }

$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$name, [bool]$pass, [string]$detail) {
    $results.Add([PSCustomObject]@{ Case = $name; Pass = $pass; Detail = $detail })
    $mark = if ($pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("{0} {1}: {2}" -f $mark, $name, $detail)
}
$returnTo = "`"/RETURNTO=$appDir\Plantoir.exe`""

# ---- The cases ------------------------------------------------------------------
$cases = [ordered]@{}

# A preview SERVING: build_site.py's python, waiting on Quartz's node --serve.
$cases['serve'] = {
    param($setup)
    Install-Version1
    $python = Start-StandIn 'runtime\python\python.exe' ("--hold `"$appDir\runtime\python\python311.dll`" -u C:\wf\.toolchain\scripts\build_site.py --course=EXC2O --section=1 --port=8081 --child `"$appDir\runtime\node\node.exe`" C:\builds\x\EXC2O\section1\quartz\bootstrap-cli.mjs build --concurrency 1 --serve --port 8081 --wsPort 9081")
    Start-Sleep 2
    $r = Invoke-Version2 $setup "$updateArgs $returnTo" 'serve'
    $python.WaitForExit(5000) | Out-Null
    $v2 = Test-IsV2
    $ended = (Select-String -Path $r.Log -Pattern "ending .*node\.exe.*a preview's server" -Quiet)
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 0) -and $v2 -and $ended -and $python.HasExited); Detail = "exit $($r.Exit) in $($r.Seconds) s; tree is version 2: $v2; server ended: $ended; its python gone: $($python.HasExited)" }
}

# A build that ends by itself (python holding python311.dll, node building, no --serve).
$cases['build'] = {
    param($setup)
    Install-Version1
    $python = Start-StandIn 'runtime\python\python.exe' ("--seconds 9 --hold `"$appDir\runtime\python\python311.dll`" -u C:\wf\.toolchain\scripts\build_site.py --course=EXC2O --section=1 --build-only")
    $node = Start-StandIn 'runtime\node\node.exe' '--seconds 7 C:\builds\x\EXC2O\section1\quartz\bootstrap-cli.mjs build --concurrency 1'
    Start-Sleep 1
    $r = Invoke-Version2 $setup "$updateArgs $returnTo" 'build'
    $v2 = Test-IsV2
    $pyc = Test-Path (Join-Path $appDir 'Toolchain\scripts\__pycache__')
    $byItself = (Test-ExitedByItself $python) -and (Test-ExitedByItself $node)
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 0) -and $v2 -and $byItself -and -not $pyc -and $r.Seconds -ge 6); Detail = "exit $($r.Exit) in $($r.Seconds) s; tree is version 2 (no python311.*): $v2; python and node exited by themselves: $byItself; __pycache__ left: $pyc" }
}

# Work that never ends (a build node): refused, nothing changed, the work untouched.
$cases['never'] = {
    param($setup)
    Install-Version1
    $before = @(Get-Tree)
    $node = Start-StandIn 'runtime\node\node.exe' 'C:\builds\x\EXC2O\section1\quartz\bootstrap-cli.mjs build --concurrency 1'
    Start-Sleep 1
    $r = Invoke-Version2 $setup "$updateArgs $returnTo" 'never'
    $same = ((@(Get-Tree) -join "`n") -eq ($before -join "`n"))
    $alive = -not $node.HasExited
    $reopened = @(Get-Started | Where-Object { $_ -match 'Plantoir\.exe' }).Count
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 7) -and $same -and $alive -and $reopened -eq 0 -and $r.Seconds -ge 19); Detail = "exit $($r.Exit) in $($r.Seconds) s; tree byte-identical to version 1: $same; the work still running: $alive; Plantoir reopened: $reopened (an at-quit install stays closed)" }
}

# The same, from Install and Reopen: the app is started again, told why.
$cases['never-relaunch'] = {
    param($setup)
    Install-Version1
    $before = @(Get-Tree)
    $node = Start-StandIn 'runtime\node\node.exe' "C:\app\runtime\wrangler\bin\wrangler.js pages deploy C:\builds\x --project-name=x --branch=main"
    Start-Sleep 1
    $r = Invoke-Version2 $setup "$updateArgs /RELAUNCH=1 $returnTo" 'never-relaunch'
    Start-Sleep 2
    $same = ((@(Get-Tree) -join "`n") -eq ($before -join "`n"))
    $reopened = @(Get-Started | Where-Object { $_ -match 'Plantoir\.exe"?\s+--update-not-installed-for-work' }).Count
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 7) -and $same -and -not $node.HasExited -and $reopened -eq 1); Detail = "exit $($r.Exit) in $($r.Seconds) s; tree byte-identical: $same; the deploy still running: $(-not $node.HasExited); Plantoir reopened with --update-not-installed-for-work: $reopened" }
}

# Work that starts DURING the wait (a scheduled deploy firing): seen, and waited for.
$cases['late'] = {
    param($setup)
    Install-Version1
    $first = Start-StandIn 'runtime\python\python.exe' '--seconds 8 -u C:\wf\.toolchain\scripts\build_site.py --course=EXC2O --section=1 --build-only'
    # Started 3 s from now by cmd.exe, which is not under {app}, so only the
    # deploy-shaped node it starts can be seen. (Start-Job took longer than the
    # whole install to start its own PowerShell, on the first run.)
    $node = Join-Path $appDir 'runtime\node\node.exe'
    $hold = Join-Path $appDir 'runtime\wrangler\bin\wrangler.js'
    Start-Process -FilePath "$env:WINDIR\System32\cmd.exe" -ArgumentList "/c ping -n 4 127.0.0.1 >nul & `"$node`" --seconds 12 --hold `"$hold`" C:\app\runtime\wrangler\bin\wrangler.js pages deploy C:\builds\x --branch=main" -WindowStyle Hidden | Out-Null
    $r = Invoke-Version2 $setup "$updateArgs $returnTo" 'late'
    $lateLine = @(Get-Started | Where-Object { $_ -match 'wrangler\.js pages deploy' }) | Select-Object -First 1
    $latePid = if ($lateLine) { ($lateLine -split "`t")[1] } else { 'none' }
    $lateSeen = Select-String -Path $r.Log -Pattern "waiting for .*node\.exe \(pid $latePid\)" -Quiet
    $v2 = Test-IsV2
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 0) -and $v2 -and $lateSeen -and $r.Seconds -ge 13); Detail = "exit $($r.Exit) in $($r.Seconds) s; the late deploy (pid $latePid) seen: $lateSeen; tree is version 2 (its held file gone): $v2" }
}

# The app still quitting when the installer starts: waited for.
$cases['quitting-app'] = {
    param($setup)
    Install-Version1
    $app = Start-StandIn 'Plantoir.exe' '--seconds 4'
    Start-Sleep 1
    $r = Invoke-Version2 $setup "$updateArgs $returnTo" 'quitting-app'
    $v2 = Test-IsV2
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 0) -and $v2 -and (Test-ExitedByItself $app)); Detail = "exit $($r.Exit) in $($r.Seconds) s; tree is version 2: $v2; the app exited by itself: $(Test-ExitedByItself $app)" }
}

# An outside assistant's server started after InitializeSetup looked: refused at once.
$cases['assistant'] = {
    param($setup)
    Install-Version1
    $before = @(Get-Tree)
    $mcp = Start-StandIn 'plantoir-mcp.exe' '--folder C:\wf'
    Start-Sleep 1
    $r = Invoke-Version2 $setup "$updateArgs $returnTo" 'assistant'
    Start-Sleep 2
    $same = ((@(Get-Tree) -join "`n") -eq ($before -join "`n"))
    $reopened = @(Get-Started | Where-Object { $_ -match 'Plantoir\.exe"?\s+--update-not-installed\s*$' }).Count
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 7) -and $same -and -not $mcp.HasExited -and $r.Seconds -lt 10 -and $reopened -eq 1); Detail = "exit $($r.Exit) in $($r.Seconds) s; tree byte-identical: $same; the server untouched: $(-not $mcp.HasExited); Plantoir reopened with --update-not-installed: $reopened" }
}

# The assistant's engine left running: ended.
$cases['llama'] = {
    param($setup)
    Install-Version1
    $llama = Start-StandIn 'llama\llama-server.exe' '--port 8180 -m C:\models\x.gguf'
    Start-Sleep 1
    $r = Invoke-Version2 $setup "$updateArgs $returnTo" 'llama'
    $v2 = Test-IsV2
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 0) -and $v2 -and $llama.HasExited); Detail = "exit $($r.Exit) in $($r.Seconds) s; tree is version 2: $v2; engine ended: $($llama.HasExited)" }
}

# A hand-run silent install (an IT deployment): a scheduled run of Plantoir is work.
$cases['hand-scheduled'] = {
    param($setup)
    Install-Version1
    $run = Start-StandIn 'Plantoir.exe' '--seconds 6 --run-scheduled-deploy C:\state\scheduled\pending\job.json'
    Start-Sleep 1
    $r = Invoke-Version2 $setup $handArgs 'hand-scheduled'
    $v2 = Test-IsV2
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 0) -and $v2 -and (Test-ExitedByItself $run) -and $r.Seconds -ge 4); Detail = "exit $($r.Exit) in $($r.Seconds) s; tree is version 2: $v2; the scheduled run exited by itself: $(Test-ExitedByItself $run)" }
}

# The second look alone (PrepareToInstall made to answer ''): work that a
# hand-run wizard meets only at ssInstall is waited for there, and its Abort
# leaves nothing changed. Records the exit code Inno gives an Abort at ssInstall.
$cases['ssinstall'] = {
    param($setup)
    Install-Version1
    $before = @(Get-Tree)
    $node = Start-StandIn 'runtime\node\node.exe' 'C:\builds\x\EXC2O\section1\quartz\bootstrap-cli.mjs build --concurrency 1'
    Start-Sleep 1
    $r = Invoke-Version2 $setup2Ss "$updateArgs $returnTo" 'ssinstall'
    $same = ((@(Get-Tree) -join "`n") -eq ($before -join "`n"))
    $atSsInstall = Select-String -Path $r.Log -Pattern 'Starting the installation process' -Quiet
    [PSCustomObject]@{ Pass = [bool](($r.Exit -ne 0) -and $same -and -not $node.HasExited -and $r.Seconds -ge 19); Detail = "exit $($r.Exit) in $($r.Seconds) s; tree byte-identical to version 1: $same; the work still running: $(-not $node.HasExited); the log reached the install step: $atSsInstall" }
}

# The teacher opens Plantoir again while the installer waits: refused at once,
# and no second copy started.
$cases['came-back'] = {
    param($setup)
    Install-Version1
    $before = @(Get-Tree)
    $node = Start-StandIn 'runtime\node\node.exe' 'C:\builds\x\EXC2O\section1\quartz\bootstrap-cli.mjs build --concurrency 1'
    $app = Join-Path $appDir 'Plantoir.exe'
    Start-Process -FilePath "$env:WINDIR\System32\cmd.exe" -ArgumentList "/c ping -n 4 127.0.0.1 >nul & `"$app`"" -WindowStyle Hidden | Out-Null
    $r = Invoke-Version2 $setup "$updateArgs /RELAUNCH=1 $returnTo" 'came-back'
    Start-Sleep 2
    $same = ((@(Get-Tree) -join "`n") -eq ($before -join "`n"))
    $copies = @(Get-Started | Where-Object { $_ -match 'Plantoir\.exe' }).Count
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 7) -and $same -and $r.Seconds -lt 12 -and $copies -eq 1 -and (Get-MarkerReason) -eq 'reopened'); Detail = "exit $($r.Exit) in $($r.Seconds) s; tree byte-identical: $same; Plantoir copies started: $copies (the teacher's only); marker: $(Get-MarkerReason)" }
}

# Plantoir already open (never quits) and Install and Reopen: refused after the
# wait, and no second copy started beside the open one.
$cases['open-at-start'] = {
    param($setup)
    Install-Version1
    $app = Start-StandIn 'Plantoir.exe' '--until-ended'
    Start-Sleep 1
    $r = Invoke-Version2 $setup "$updateArgs /RELAUNCH=1 $returnTo" 'open-at-start'
    Start-Sleep 2
    $copies = @(Get-Started | Where-Object { $_ -match 'Plantoir\.exe' }).Count
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 7) -and $copies -eq 1 -and -not $app.HasExited -and (Get-MarkerReason) -eq 'work'); Detail = "exit $($r.Exit) in $($r.Seconds) s; Plantoir copies started: $copies; marker: $(Get-MarkerReason)" }
}

# A scheduled-shaped program started DURING the copy waits for the installing marker.
$cases['scheduled-during-copy'] = {
    param($setup)
    Install-Version1
    $r = Invoke-Version2 $setup "$updateArgs $returnTo `"/HARNESSSCHEDULED=$standIn`"" 'scheduled-during-copy'
    for ($i = 0; $i -lt 40 -and -not (Get-Started | Where-Object { $_ -like 'WAITED*' }); $i++) { Start-Sleep -Milliseconds 250 }
    $waited = @(Get-Started | Where-Object { $_ -like 'WAITED*' }) | Select-Object -First 1
    $ms = if ($waited) { [int](($waited -split "`t")[1]) } else { -1 }
    $saw = $waited -match 'SAW\tTrue'
    [PSCustomObject]@{ Pass = [bool](($r.Exit -eq 0) -and (Test-IsV2) -and $saw -and $ms -ge 3000); Detail = "exit $($r.Exit) in $($r.Seconds) s; the scheduled-shaped run saw the installing marker: $saw and waited $ms ms" }
}

# ---- Must-fail: break one rule, and the case it protects goes wrong -----------------
$mustFails = @(
    @{ Name = 'no check at all'; Case = 'serve'
       From = "  Result := RunningWorkRefusal(ExpandConstant('{app}'), Updating, WizardSilent);"
       To = "  Result := '';"
       Expect = { param($r) $r.Exit -ne 0 } ; Says = 'the night''s case B: a preview serving makes the update fail part way' },
    @{ Name = 'a preview counted as work'; Case = 'serve'
       From = "            RwHasToken(CommandLine, '--serve');"
       To = "            RwHasToken(CommandLine, '--serve') and False;"
       Expect = { param($r) $r.Exit -eq 7 } ; Says = 'the update is refused for an open preview' },
    @{ Name = 'one look only'; Case = 'late'
       From = "    Sleep(1000);`n  end;"
       To = "    Sleep(1000);`n    if Work > 0 then Exit;`n  end;"
       # Judged by TIME, not by the tree: whether Inno's in-use retries then trip over the late
       # work depends on when it starts (a first run gave exit 5, a later one exit 0 after retries).
       Expect = { param($r) $r.Seconds -lt 13 } ; Says = 'the install goes ahead before work that started during the wait has finished' },
    @{ Name = 'no wait (go ahead over work)'; Case = 'build'
       From = "    if Work > 0 then`n    begin`n      if Silent then"
       To = "    if Work > 0 then Exit;`n    if Work > 0 then`n    begin`n      if Silent then"
       Expect = { param($r) $r.Exit -ne 0 -or -not (Test-IsV2) } ; Says = 'the night''s case C: a build''s held files survive, or the copy aborts' },
    @{ Name = 'a reopened Plantoir counted as work'; Case = 'came-back'
       From = "              (not RwIn(RwPlantoirAtStart, RwPids[I])) then"
       To = "              (not RwIn(RwPlantoirAtStart, RwPids[I])) and False then"
       Expect = { param($r) $r.Seconds -ge 19 } ; Says = 'the install waits out the full time under the teacher' },
    @{ Name = 'no guard against a second copy'; Case = 'open-at-start'
       From = "  if RwPlantoirIsOpen then"
       To = "  if False and RwPlantoirIsOpen then"
       Expect = { param($r) $true } ; Says = 'a second Plantoir is started beside the open one' }
)

# ---- Run ----------------------------------------------------------------------------
$ownerBefore = Get-OwnerFingerprint
Write-Host "The real Plantoir before: $ownerBefore"
try {
    $names = if ($Case.Count -gt 0) { $Case } else { @($cases.Keys) }
    if (-not $MustFail) {
        foreach ($name in $names) {
            $outcome = @(& $cases[$name] $setup2 | Where-Object { $_ -is [PSCustomObject] -and $_.PSObject.Properties['Pass'] })[-1]
            # Every case: a refusal leaves the refusal marker, a finished install
            # none, and no installing marker is ever left behind.
            $refuses = $name -in @('never', 'never-relaunch', 'assistant', 'ssinstall', 'came-back', 'open-at-start')
            $marker = Test-Path $refusalMarker
            $left = Test-InstallingLeft
            $markersRight = ($marker -eq $refuses) -and -not $left
            Add-Result $name ($outcome.Pass -and $markersRight) ($outcome.Detail + "; refusal marker: $marker ($(Get-MarkerReason)); installing marker left: $left")
            Remove-Harness
        }
    } else {
        $original = [IO.File]::ReadAllText($include).Replace("`r`n", "`n")
        $i = 0
        foreach ($mf in $mustFails) {
            $i++
            if ($original.IndexOf($mf.From) -lt 0) { Add-Result "must-fail: $($mf.Name)" $false "the line to break was not found in the include"; continue }
            $broken = Join-Path $work "broken-$i.iss"
            [IO.File]::WriteAllText($broken, $original.Replace($mf.From, $mf.To))
            $setupBroken = Invoke-Compile '2' $payload2 (Join-Path $work "out-broken-$i") $broken
            $outcome = @(& $cases[$mf.Case] $setupBroken | Where-Object { $_ -is [PSCustomObject] -and $_.PSObject.Properties['Pass'] })[-1]
            $r = [PSCustomObject]@{ Exit = [int](([regex]::Match($outcome.Detail, 'exit (-?\d+)')).Groups[1].Value)
                                    Seconds = [double](([regex]::Match($outcome.Detail, 'in ([\d.]+) s')).Groups[1].Value) }
            $wentWrong = & $mf.Expect $r
            Add-Result "must-fail: $($mf.Name)" ([bool]$wentWrong -and -not $outcome.Pass) "case $($mf.Case) went wrong as expected ($($mf.Says)): $($outcome.Detail)"
            Remove-Harness
        }
    }
} finally {
    Remove-Harness
    $ownerAfter = Get-OwnerFingerprint
    $untouched = $ownerAfter -eq $ownerBefore
    Add-Result 'the real Plantoir untouched' $untouched "after: $ownerAfter"
    Write-Host "Logs and builds: $work"
}
$failed = @($results | Where-Object { -not $_.Pass }).Count
Write-Host ("{0} passed, {1} failed" -f ($results.Count - $failed), $failed)
if ($failed -gt 0) { exit 1 } else { exit 0 }

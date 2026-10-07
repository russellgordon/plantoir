<#
.SYNOPSIS
    Runs the shared contract's launcher cases against the REAL functions in
    preview.ps1 and deploy.ps1, lifted out with the PowerShell parser (never
    dot-sourced: that would run the launcher).

.DESCRIPTION
    Three lists, each deserialised and never retyped:

    1. app-rules.json -> previewPorts.hostBlockCases, through preview.ps1's
       Find-FreePreviewPort (#286). A native walk binds ONE pair per block,
       so only the cases made of whole busyBlocks run here; every case
       carrying busyPorts, stoppedBlocks, anotherAccount*, notListening or a
       listing that fails is SKIPPED by name - hostBlockProbe and
       hostBlockPassesWhy say those are about Docker workspaces or the mac's
       two listings.

    2. shared-rules.json -> previewWhileItsSectionDeploys.launcherCases,
       through preview.ps1's Test-SectionIsBeingDeployed (#386). The cases are
       preview.sh's process table (`ps` rows, `lsof` working directories), so
       each row is TRANSLATED to the Windows shape of the same evidence:
       `/bin/bash ./deploy.sh ARGS` becomes `powershell.exe -File <path>\deploy.ps1 ARGS`,
       where the path is this folder when lsof said 'here', another folder
       when it said 'elsewhere', and '.\' (no folder to tell) when it said
       nothing; a scheduled deploy's launchd script becomes the Task
       Scheduler wrapper the app writes. Cases whose evidence has no Windows
       shape are skipped with the reason.

    3. app-rules.json -> buildFreshness.previewBuild.cases, through
       deploy.ps1's Test-CarriesLiveReload (#272), each tree written to a
       temporary public\ folder.

    Run with:  powershell -NoProfile -File windows-app\test_launcher_rules.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

function Import-LauncherFunctions([string]$Launcher, [string[]]$Names) {
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Launcher, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        foreach ($e in $parseErrors) { Write-Host ("FAIL {0} line {1}: {2}" -f (Split-Path -Leaf $Launcher), $e.Extent.StartLineNumber, $e.Message) }
        exit 1
    }
    foreach ($name in $Names) {
        $found = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true)
        if ($found.Count -lt 1) { throw "$(Split-Path -Leaf $Launcher) no longer defines $name at script scope" }
        # Defined at SCRIPT scope, so the functions can call each other.
        . ([scriptblock]::Create($found[0].Extent.Text))
        Set-Item -Path ("function:script:" + $name) -Value (Get-Item ("function:" + $name)).ScriptBlock
    }
}

Import-LauncherFunctions (Join-Path $repo 'preview.ps1') @('Find-FreePreviewPort', 'Split-CommandLine', 'Get-ScheduledDeployScriptName', 'Test-SectionIsBeingDeployed')
Import-LauncherFunctions (Join-Path $repo 'deploy.ps1') @('Test-CarriesLiveReload', 'Resolve-PublishFolder')
# preview.ps1's Get-PhysicalPath needs a type compiled at run time; the
# folders in these cases do not exist, so the full path is what it would give.
function script:Get-PhysicalPath([string]$p) { return ([System.IO.Path]::GetFullPath($p)).TrimEnd('\') }

$appRules = Get-Content -LiteralPath (Join-Path $repo 'contracts\app-rules.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$shared   = Get-Content -LiteralPath (Join-Path $repo 'contracts\shared-rules.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$passed = 0; $failed = 0; $skipped = 0

function Report([string]$List, [string]$Name, [bool]$Ok, [string]$Detail) {
    if ($Ok) { $script:passed++ } else { $script:failed++; Write-Host ("FAIL [{0}] {1}: {2}" -f $List, $Name, $Detail) }
}
function Skip([string]$List, [string]$Name, [string]$Why) {
    $script:skipped++; Write-Host ("skip [{0}] {1} - {2}" -f $List, $Name, $Why)
}

# ---- 1. Port blocks (#286) ------------------------------------------
$ports = $appRules.previewPorts
$notNative = @('busyPorts', 'stoppedBlocks', 'anotherAccountBlocks', 'anotherAccountPorts', 'notListening', 'kernelListFails', 'accountListFails')
foreach ($case in @($ports.hostBlockCases)) {
    $carried = @($case.PSObject.Properties.Name | Where-Object { $notNative -contains $_ })
    if ($carried.Count -gt 0) { Skip 'hostBlockCases' $case.name ("carries " + ($carried -join ', ') + ": not a native walk's question"); continue }
    $listening = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($block in @($case.busyBlocks)) {
        if ($null -eq $block) { continue }
        # A busy block: its site port listening. (Its websocket is +1000.)
        $null = $listening.Add([int]$block)
    }
    $from = 8081; if ($case.PSObject.Properties.Name -contains 'from') { $from = [int]$case.from }
    $got = Find-FreePreviewPort -From $from -Listening $listening -Count ([int]$ports.hostBlockCount) -Step ([int]$ports.hostBlockStep) -WebsocketOffset ([int]$ports.websocketOffset)
    $want = $case.expect
    Report 'hostBlockCases' $case.name (("$got") -eq ("$want")) "expected '$want', got '$got'"
}
# The sentence, word for word, as preview.ps1 prints it: the contract's
# `sentence` with its {machine} filled with this platform's word
# (specialNames.platformWording.machine, #438; it replaced sentenceOnWindows).
$machine = $shared.specialNames.platformWording.machine
$previewSource = Get-Content -LiteralPath (Join-Path $repo 'preview.ps1') -Raw -Encoding UTF8
foreach ($written in @($ports.whenNoBlockIsFree.sentence)) {
    $line = $written.Replace([string]$machine.placeholder, [string]$machine.windows)
    Report 'whenNoBlockIsFree' $line ($previewSource.Contains('Write-Host "' + $line + '"')) 'preview.ps1 does not print this line word for word'
}
# The websocket half of a block spoils it too.
$ws = New-Object 'System.Collections.Generic.HashSet[int]'; $null = $ws.Add(9081)
Report 'hostBlockCases' 'a websocket port alone spoils its block (Windows)' ((Find-FreePreviewPort -From 8081 -Listening $ws) -eq 8091) 'expected 8091'

# ---- 2. A section being deployed (#386) -----------------------------
$guard = $shared.previewWhileItsSectionDeploys
$here = 'C:\Users\t\Plantoir Here'
$elsewhere = 'C:\Users\t\Plantoir Elsewhere'
$scheduledDir = 'C:\Users\t\AppData\Local\Plantoir\scheduled'

function ConvertTo-WindowsRow([string]$Text, $Cwd, [string]$ProcessId) {
    $Text = $Text.Replace('{here}', $here)
    # A deploy set for later: the mac's launchd script (or the app's runner
    # naming it) becomes the Task Scheduler wrapper the app writes.
    $label = [regex]::Match($Text, 'ca\.russellgordon\.Plantoir\.deploy\.(?<code>[^.]+)\.section(?<section>\d+)(?:\.(?<id>\{\w+\}|[0-9a-f]+))?\.(?<ext>sh|log)')
    if ($label.Success) {
        if ($label.Groups['id'].Value -eq '{elsewhereID}') { return $null }
        if ($label.Groups['ext'].Value -eq 'log') {
            return "powershell.exe -NoProfile -Command Get-Content -Wait $scheduledDir\" + (Get-ScheduledDeployScriptName $label.Groups['code'].Value $label.Groups['section'].Value).Replace('.ps1', '.log')
        }
        return "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$scheduledDir\" + (Get-ScheduledDeployScriptName $label.Groups['code'].Value.Replace('-', ' ') $label.Groups['section'].Value) + '"'
    }
    $program = [regex]::Match($Text, '^(?<shell>/bin/(?:ba|z)sh) (?<c>-c )?(?<path>.*?)deploy\.sh(?<rest>.*)$')
    if ($program.Success -and -not $program.Groups['c'].Success) {
        $path = $program.Groups['path'].Value
        # lsof's working directory is the mac's folder evidence; on Windows
        # the folder is the script's own path, so the case's 'here' or
        # 'elsewhere' is written INTO the path. With neither, a relative
        # path names no folder at all.
        $where = $null
        if ($Cwd -and ($Cwd.PSObject.Properties.Name -contains $ProcessId)) { $where = $Cwd.$ProcessId }
        $folder = '.\'
        if ($path -like "$here*" -or $where -eq 'here') { $folder = "$here\" }
        elseif ($where -eq 'elsewhere') { $folder = "$elsewhere\" }
        elseif ($path -match '^/') { $folder = 'C:' + $path.Replace('/', '\') }
        return "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"${folder}deploy.ps1`"" + $program.Groups['rest'].Value
    }
    if ($program.Success) {
        # A shell handed a command line: cmd.exe /c on Windows, not the program.
        return 'cmd.exe /c ' + $program.Groups['path'].Value.Replace('/', '\') + 'deploy.ps1' + $program.Groups['rest'].Value
    }
    # preview.sh (a build leg or the assistant's rebuild), a prompt that
    # mentions deploy.sh, a log being read: the same words, Windows spelling.
    return ($Text -replace 'preview\.sh', 'preview.ps1' -replace 'deploy\.sh', 'deploy.ps1')
}

foreach ($case in @($guard.launcherCases)) {
    $course = 'ICS4U'; if ($case.PSObject.Properties.Name -contains 'course') { $course = [string]$case.course }
    $section = '2'; if ($case.PSObject.Properties.Name -contains 'section') { $section = [string]$case.section }
    $self = [uint32]5000
    $snapshot = New-Object System.Collections.Generic.List[object]
    $parentArgs = '-bash'; if ($case.PSObject.Properties.Name -contains 'parentArgs') { $parentArgs = [string]$case.parentArgs }
    $translatedParent = ConvertTo-WindowsRow $parentArgs $null '4999'
    $snapshot.Add([PSCustomObject]@{ ProcessId = [uint32]4999; ParentProcessId = [uint32]1; CommandLine = $translatedParent })
    if (-not ($case.PSObject.Properties.Name -contains 'psOmitsThisRun' -and $case.psOmitsThisRun)) {
        $snapshot.Add([PSCustomObject]@{ ProcessId = $self; ParentProcessId = [uint32]4999; CommandLine = "powershell.exe -NoProfile -File `"$here\preview.ps1`" $course $section" })
    }
    $untranslatable = $false
    $cwd = $null; if ($case.PSObject.Properties.Name -contains 'cwd') { $cwd = $case.cwd }
    foreach ($row in @($case.processes)) {
        if ($null -eq $row) { continue }
        $line = ConvertTo-WindowsRow ([string]$row[2]) $cwd ([string]$row[0])
        if ($null -eq $line) { $untranslatable = $true; break }
        $snapshot.Add([PSCustomObject]@{ ProcessId = [uint32]$row[0]; ParentProcessId = [uint32]$row[1]; CommandLine = $line })
    }
    if ($untranslatable) { Skip 'launcherCases' $case.name 'a deploy set for later names its folder on the mac; a Windows task name carries none (the pre-#237 limit, documented)'; continue }
    $table = $snapshot.ToArray()
    if ($case.PSObject.Properties.Name -contains 'psFails' -and $case.psFails) { $table = $null }
    $refused = Test-SectionIsBeingDeployed -Snapshot $table -Course $course -Section $section -Here $here -Self $self
    $want = [string]$case.expect
    $got = if ($refused) { 'refused' } else { 'allowed' }
    Report 'launcherCases' $case.name ($got -eq $want) "expected $want, got $got"
}

# ---- 3. A preview's build (#272 / #136 / #291) ----------------------
$previewBuild = $appRules.buildFreshness.previewBuild
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('launcher-rules-' + [Guid]::NewGuid().ToString('N'))
try {
    foreach ($case in @($previewBuild.cases)) {
        $public = Join-Path $scratch ([Guid]::NewGuid().ToString('N') + '\public')
        $null = New-Item -ItemType Directory -Force -Path $public
        $held = @()
        try {
            $invalid = @(); if ($case.PSObject.Properties.Name -contains 'invalidUTF8Before') { $invalid = @($case.invalidUTF8Before) }
            foreach ($page in $case.pages.PSObject.Properties) {
                $file = Join-Path $public ($page.Name.Replace('/', '\'))
                $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file)
                [byte[]]$bytes = [Text.Encoding]::UTF8.GetBytes([string]$page.Value)
                if ($invalid -contains $page.Name) { [byte[]]$bytes = [byte[]](0xFF, 0x0A) + $bytes }
                [IO.File]::WriteAllBytes($file, $bytes)
            }
            foreach ($path in @($case.unreadable)) {
                if ($null -eq $path) { continue }
                $held += [IO.File]::Open((Join-Path $public ($path.Replace('/', '\'))), 'Open', 'Read', 'None')
            }
            $got = [bool](Test-CarriesLiveReload $public)
            Report 'previewBuild' $case.name ($got -eq [bool]$case.expectPreview) "expected $($case.expectPreview), got $got"
        } catch {
            Report 'previewBuild' $case.name $false ("threw: " + $_.Exception.Message)
        } finally {
            foreach ($h in $held) { $h.Dispose() }
        }
    }
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- 4. Where a --to-folder value publishes (#304, review L1) --------
# Windows-only cases (the contract's deployFolder cases are the APP's check):
# a plain relative name comes from the working folder; a drive- or
# root-relative path is refused rather than resolved against the process
# directory.
$wf = 'C:\Users\t\Plantoir Here'
foreach ($c in @(
    @{ asked = 'out site';            want = 'C:\Users\t\Plantoir Here\out site' },
    @{ asked = '  Sites\x  ';         want = 'C:\Users\t\Plantoir Here\Sites\x' },
    @{ asked = 'D:\Published\ics4u';  want = 'D:\Published\ics4u' },
    @{ asked = '\\server\share\site'; want = '\\server\share\site' },
    @{ asked = 'C:foo';               want = $null },
    @{ asked = '\out';                want = $null },
    @{ asked = '/out';                want = $null },
    @{ asked = '   ';                 want = $null })) {
    $got = Resolve-PublishFolder $c.asked $wf
    Report 'publishFolder' ("'" + $c.asked + "'") ("$got" -eq "$($c.want)") "expected '$($c.want)', got '$got'"
}

Write-Host ("{0} passed, {1} failed, {2} skipped" -f $passed, $failed, $skipped)
if ($failed -gt 0) { exit 1 }
exit 0

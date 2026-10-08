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
       nothing, and a spaced course is QUOTED as the app quotes it; a
       scheduled deploy's launchd script becomes the Task Scheduler wrapper
       the app writes, named with the case's folder id (#309), and the app's
       launchd runner line becomes Plantoir.exe --run-scheduled-deploy
       "<task name>". Since #467 every case runs (none has to be skipped),
       plus Windows-only rows the contract cannot carry.

    3. app-rules.json -> buildFreshness.previewBuild.cases, through
       deploy.ps1's Test-CarriesLiveReload (#272), each tree written to a
       temporary public\ folder.

    4. Where a --to-folder value publishes, through deploy.ps1's
       Resolve-PublishFolder (#304; Windows-only cases).

    5. shared-rules.json -> deployWhileItsSectionDeploys.launcherCases (#467 /
       mac #439), every one, through Get-WhatIsDeployingThisSection as EACH
       launcher carries it (one marked block, the same in both), checking
       who refused as well as whether; then the four sentences and the trail
       lines word for word against the contract.

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

Import-LauncherFunctions (Join-Path $repo 'preview.ps1') @('Find-FreePreviewPort', 'Split-CommandLine', 'Get-LaunchedScriptIndex', 'Get-ScheduledDeployTaskNames', 'Get-ScheduledDeployScriptNames', 'Get-WhatIsDeployingThisSection', 'Test-SectionIsBeingDeployed')
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
# The guard is HANDED the folder id ($WORKDIR_ID), so these stand for the two
# folders' ids; that the launchers compute the id and the wrapper names the
# app's way is LauncherRulesContractTests' business, not a copy kept here.
$hereId = 'a1b2c3d4'
$elsewhereId = 'e5f6a7b8'

# The course words, as the app and the scheduled wrapper hand them: ONE
# argument, quoted when it has a space (ScriptRunner, LauncherRunner, the
# wrapper's build leg). The course is every word before the first all-digit
# word, which is the section.
function ConvertTo-QuotedArguments([string]$Rest) {
    $words = @($Rest.Trim() -split '\s+' | Where-Object { $_ })
    $at = -1
    for ($i = 0; $i -lt $words.Count; $i++) { if ($words[$i] -match '^\d+$') { $at = $i; break } }
    if ($at -lt 2) { if ($words.Count -eq 0) { return '' } else { return ' ' + ($words -join ' ') } }
    $course = '"' + (($words[0..($at - 1)]) -join ' ') + '"'
    return ' ' + ((@($course) + $words[$at..($words.Count - 1)]) -join ' ')
}

# One `ps` row of the mac's case, as the Windows process table shows the same
# evidence. A deploy set for later is a Task Scheduler task on Windows, so its
# launchd script becomes the WRAPPER the app writes and runs as
# powershell.exe -File (TaskScheduling.WrapperRunArguments), its launchd
# runner line becomes Plantoir.exe --run-scheduled-deploy "<task name>"
# (TaskScheduling.TaskRunCommand), and its log the wrapper's own. An editor,
# a pager or `bash -x` on the script becomes notepad, more and a -Command that
# traces it - none of which runs the wrapper as the program.
function ConvertTo-WindowsRow([string]$Text, $Cwd, [string]$ProcessId) {
    $Text = $Text.Replace('{here}', $here)
    $label = [regex]::Match($Text, 'ca\.russellgordon\.Plantoir\.deploy\.(?<code>[^.]+)\.section(?<section>\d+)(?:\.(?<id>\{\w+\}|[0-9a-f]+))?\.(?<ext>sh|log)')
    if ($label.Success) {
        $id = $label.Groups['id'].Value
        if ($id -eq '{hereID}') { $id = $hereId } elseif ($id -eq '{elsewhereID}') { $id = $elsewhereId }
        $code = $label.Groups['code'].Value.Replace('-', ' ')
        $sectionNumber = $label.Groups['section'].Value
        $taskName = @(Get-ScheduledDeployTaskNames $code $sectionNumber $id)[0]
        $wrapper = $scheduledDir + '\' + @(Get-ScheduledDeployScriptNames $code $sectionNumber $id)[0]
        if ($label.Groups['ext'].Value -eq 'log') {
            return "powershell.exe -NoProfile -Command Get-Content -Wait `"" + $wrapper.Replace('.ps1', '.log') + '"'
        }
        if ($Text -match '--run-scheduled-deploy') {
            return "`"C:\Program Files\Plantoir\Plantoir.exe`" --run-scheduled-deploy `"$taskName`""
        }
        if ($Text -match '^/usr/bin/vim ') { return "notepad.exe `"$wrapper`"" }
        if ($Text -match '^/usr/bin/less ') { return "more.com `"$wrapper`"" }
        if ($Text -match '^/bin/bash -x ') { return "powershell.exe -NoProfile -Command `"Set-PSDebug -Trace 1; & '$wrapper'`"" }
        return "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$wrapper`""
    }
    $program = [regex]::Match($Text, '^(?<shell>/bin/(?:ba|z)sh) (?<c>-c )?(?<path>.*?)(?<launcher>deploy|preview)\.sh(?<rest>.*)$')
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
        return "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"${folder}$($program.Groups['launcher'].Value).ps1`"" + (ConvertTo-QuotedArguments $program.Groups['rest'].Value)
    }
    if ($program.Success) {
        # A shell handed a command line: cmd.exe /c on Windows, not the program.
        return 'cmd.exe /c ' + $program.Groups['path'].Value.Replace('/', '\') + $program.Groups['launcher'].Value + '.ps1' + $program.Groups['rest'].Value
    }
    # A prompt that mentions deploy.sh: the same words, Windows spelling.
    return ($Text -replace 'preview\.sh', 'preview.ps1' -replace 'deploy\.sh', 'deploy.ps1')
}

# The table one case describes, with this run (pid 5000, parent 4999) in it
# unless the case says the table omits it, or $null when the table fails.
function New-CaseTable($Case, [string]$SelfLine) {
    $snapshot = New-Object System.Collections.Generic.List[object]
    $parentArgs = '-bash'; if ($Case.PSObject.Properties.Name -contains 'parentArgs') { $parentArgs = [string]$Case.parentArgs }
    $snapshot.Add([PSCustomObject]@{ ProcessId = [uint32]4999; ParentProcessId = [uint32]1; CommandLine = (ConvertTo-WindowsRow $parentArgs $null '4999') })
    if (-not ($Case.PSObject.Properties.Name -contains 'psOmitsThisRun' -and $Case.psOmitsThisRun)) {
        $snapshot.Add([PSCustomObject]@{ ProcessId = [uint32]5000; ParentProcessId = [uint32]4999; CommandLine = $SelfLine })
    }
    $cwd = $null; if ($Case.PSObject.Properties.Name -contains 'cwd') { $cwd = $Case.cwd }
    foreach ($row in @($Case.processes)) {
        if ($null -eq $row) { continue }
        $snapshot.Add([PSCustomObject]@{ ProcessId = [uint32]$row[0]; ParentProcessId = [uint32]$row[1]; CommandLine = (ConvertTo-WindowsRow ([string]$row[2]) $cwd ([string]$row[0])) })
    }
    if ($Case.PSObject.Properties.Name -contains 'psFails' -and $Case.psFails) { return $null }
    return ,$snapshot.ToArray()
}

function Get-CaseValue($Case, [string]$Name, [string]$Default) {
    if ($Case.PSObject.Properties.Name -contains $Name) { return [string]$Case.$Name }
    return $Default
}

# Rows the contract cannot carry, in the shapes only Windows has (#467's plan
# review H1 and M4): the app and the wrapper QUOTE a course with a space, and
# Windows PowerShell runs a script handed to -f, -fil or as its first plain
# word just as it runs one handed to -File.
$psDeploy = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$here\deploy.ps1`""
$windowsRows = @(
    [PSCustomObject]@{ name = 'a quoted course with a space, as the app runs it (Windows)'; course = 'AP CALC'; processes = @(,@(700, 600, "$psDeploy `"AP CALC`" 2 --target netlify")); expect = 'refused'; who = 'another' },
    [PSCustomObject]@{ name = 'a quoted course with a space is still matched whole (Windows)'; course = 'AP CALC'; section = '1'; processes = @(@(700, 600, "$psDeploy `"AP CALC`" 12"), @(701, 600, "$psDeploy `"AP CALCULUS`" 1"), @(702, 600, "$psDeploy AP 1")); expect = 'allowed' },
    [PSCustomObject]@{ name = 'deploy.ps1 handed to -f (Windows)'; processes = @(,@(700, 1, "powershell.exe -NoProfile -f `"$here\deploy.ps1`" ICS4U 2")); expect = 'refused'; who = 'another' },
    [PSCustomObject]@{ name = 'deploy.ps1 as pwsh -fil (Windows)'; processes = @(,@(700, 1, "pwsh.exe -fil `"$here\deploy.ps1`" ICS4U 2")); expect = 'refused'; who = 'another' },
    [PSCustomObject]@{ name = 'deploy.ps1 as powershell.exe''s first plain word (Windows)'; processes = @(,@(700, 1, "powershell.exe -NoProfile -ExecutionPolicy Bypass `"$here\deploy.ps1`" ICS4U 2")); expect = 'refused'; who = 'another' },
    [PSCustomObject]@{ name = 'deploy.ps1 named after -Command is not the program (Windows)'; processes = @(,@(700, 1, "powershell.exe -NoProfile -Command `"Get-Content '$here\deploy.ps1'`" ICS4U 2")); expect = 'allowed' },
    [PSCustomObject]@{ name = 'a pre-#309 wrapper for a spaced course counts (Windows)'; course = 'AP CALC'; processes = @(,@(801, 1, "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scheduledDir\Plantoir-deploy-AP-CALC-section-2.ps1`"")); expect = 'refused'; who = 'later' }
)
# A run still waiting for the course, its task's token on the line too.
$waitingRun = [PSCustomObject]@{ name = 'a scheduled run still waiting for the course, with its token (Windows)'; processes = @(,@(800, 1, "`"C:\Program Files\Plantoir\Plantoir.exe`" --run-scheduled-deploy `"Plantoir deploy ICS4U section 2 $hereId`" --token 0f3c")) }

foreach ($case in @($guard.launcherCases) + @($windowsRows) + @($waitingRun)) {
    $course = Get-CaseValue $case 'course' 'ICS4U'
    $section = Get-CaseValue $case 'section' '2'
    $want = Get-CaseValue $case 'expect' 'refused'
    $table = New-CaseTable $case "powershell.exe -NoProfile -File `"$here\preview.ps1`" `"$course`" $section"
    $refused = Test-SectionIsBeingDeployed -Snapshot $table -Course $course -Section $section -Here $here -FolderId $hereId -Self 5000
    $got = if ($refused) { 'refused' } else { 'allowed' }
    Report 'previewWhileItsSectionDeploys' $case.name ($got -eq $want) "expected $want, got $got"
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

# ---- 5. A section still being deployed is not deployed again (#467) ----
# shared-rules.json -> deployWhileItsSectionDeploys.launcherCases, every one
# of them, through Get-WhatIsDeployingThisSection as EACH launcher carries it
# (the two copies are one marked block; LauncherRulesContractTests checks
# they match, and running both here is what proves each copy works). The
# rows are translated by section 2's ConvertTo-WindowsRow. Cases marked
# appliesOn without 'windows' are skipped by that field, never by name.
$deployGuard = $shared.deployWhileItsSectionDeploys
foreach ($launcher in @('deploy.ps1', 'preview.ps1')) {
    Import-LauncherFunctions (Join-Path $repo $launcher) @('Split-CommandLine', 'Get-LaunchedScriptIndex', 'Get-ScheduledDeployTaskNames', 'Get-ScheduledDeployScriptNames', 'Get-WhatIsDeployingThisSection', 'Test-SectionIsBeingDeployed')
    $waitingForDeploy = [PSCustomObject]@{ name = $waitingRun.name; processes = $waitingRun.processes; expect = 'allowed' }
    foreach ($case in @($deployGuard.launcherCases) + @($windowsRows) + @($waitingForDeploy)) {
        $list = "deployWhileItsSectionDeploys/$launcher"
        if ($case.PSObject.Properties.Name -contains 'appliesOn' -and -not (@($case.appliesOn) -contains 'windows')) {
            Skip $list $case.name ('appliesOn ' + (@($case.appliesOn) -join ', '))
            continue
        }
        $course = Get-CaseValue $case 'course' 'ICS4U'
        $section = Get-CaseValue $case 'section' '2'
        $leg = Get-CaseValue $case 'leg' 'deploy'
        $want = Get-CaseValue $case 'expect' 'refused'
        $wantWho = Get-CaseValue $case 'who' ''
        if ($leg -eq 'build') {
            $selfLine = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$here\preview.ps1`" `"$course`" $section --build-only"
        } else {
            $selfLine = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$here\deploy.ps1`" `"$course`" $section"
        }
        $table = New-CaseTable $case $selfLine
        $who = Get-WhatIsDeployingThisSection -Snapshot $table -Course $course -Section $section -Here $here -FolderId $hereId -Self 5000
        $got = if ($who) { 'refused' } else { 'allowed' }
        if ($want -eq 'refused' -and $wantWho) {
            Report $list $case.name (($got -eq $want) -and ("$who" -eq $wantWho)) "expected $want by '$wantWho', got $got by '$who'"
        } else {
            Report $list $case.name ($got -eq $want) "expected $want, got $got"
        }
    }
}

# The words, as each launcher prints and records them. Each sentence's first
# line is a format string whose {0} is the cross, {1} the course and {2} the
# section; each trail line one whose slots are the course, the section, the
# dot, the leg and the dash (contract launcherLines, under activityTrail
# 'build declined, course busy elsewhere').
$crossText = [char]::ConvertFromUtf32(0x274C)
$dotText = [string][char]0x00B7
$dashText = [string][char]0x2014
$declined = @($shared.activityTrail.mustRecord | Where-Object { $_.event -eq 'build declined, course busy elsewhere' })[0]
$portEvent = @($shared.activityTrail.mustRecord | Where-Object { $_.event -eq 'preview did not appear' })[0]
foreach ($launcher in @('deploy.ps1', 'preview.ps1')) {
    $source = Get-Content -LiteralPath (Join-Path $repo $launcher) -Raw -Encoding UTF8
    foreach ($sentence in $deployGuard.sentences.launcher.PSObject.Properties) {
        $lines = @($sentence.Value)
        $first = $lines[0].Replace($crossText + ' ', '{0} ').Replace('{course}', '{1}').Replace('{section}', '{2}')
        Report "deployWhileItsSectionDeploys.sentences/$launcher" $sentence.Name ($source.Contains('Write-Host ("' + $first + '" -f $cross, $Course, $Section)')) "does not print '$first' word for word"
        Report "deployWhileItsSectionDeploys.sentences/$launcher" ($sentence.Name + ' (second line)') ($source.Contains('Write-Host "' + $lines[1] + '"')) "does not print '$($lines[1])'"
    }
    foreach ($field in @('launcherLineWhenALaterDeployIsStillWorking', 'launcherLineWhenItsSectionIsAlreadyBeingDeployed')) {
        $format = ([string]$declined.$field).Replace('{course}', '{0}').Replace('{section}', '{1}').Replace($dotText, '{2}').Replace('{leg}', '{3}').Replace($dashText, '{4}')
        Report "activityTrail/$launcher" $field ($source.Contains('Write-TrailLine ("' + $format + '" -f $Course, $Section, $dot, $Leg, $dash)')) "does not record '$format'"
    }
}
# #386's line and #286's, which preview.ps1 alone writes, with the dash the
# contract has (both had the dot in its place until #467).
$previewSource = Get-Content -LiteralPath (Join-Path $repo 'preview.ps1') -Raw -Encoding UTF8
foreach ($pair in @(@($declined, 'launcherLineWhenItsSectionIsBeingDeployed'), @($portEvent, 'launcherLineWhenEveryAddressIsTaken'))) {
    $format = ([string]$pair[0].($pair[1])).Replace('{course}', '{0}').Replace('{section}', '{1}').Replace($dotText, '{2}').Replace($dashText, '{3}')
    Report 'activityTrail/preview.ps1' $pair[1] ($previewSource.Contains('Write-TrailLine ("' + $format + '" -f $COURSE, $SECTION, [char]0x00B7, [char]0x2014)')) "does not record '$format'"
}

Write-Host ("{0} passed, {1} failed, {2} skipped" -f $passed, $failed, $skipped)
if ($failed -gt 0) { exit 1 }
exit 0

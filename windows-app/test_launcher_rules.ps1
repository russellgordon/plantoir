<#
.SYNOPSIS
    Runs the shared contract's launcher cases against the REAL functions in
    preview.ps1 and deploy.ps1, lifted out with the PowerShell parser (never
    dot-sourced: that would run the launcher).

.DESCRIPTION
    Ten sections; the lists are deserialised and never retyped:

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

    6. app-rules.json -> launcherTrailFolder.cases (#682, the Windows half of
       mac #664), every one, through Write-TrailLine as EACH launcher
       carries it, with LOCALAPPDATA pointed at a scratch folder and the
       current folder moved into it (so a relative value wrongly taken is
       caught there): the line must land in the expected folder and no other
       file may appear. Plus Windows-only rows for the two shapes
       [IO.Path]::IsPathRooted calls rooted and which are not absolute
       (C:state, \state\Logs), and a check that both launchers read the
       contract's variable name.

    7. app-rules.json -> savedTokenCheck.cases (#705 / mac #716), through
       deploy.ps1's Get-TokenCheckAnswer with the patterns deploy.ps1 carries,
       which must be the contract's.

    8. Invoke-TokenCheck against a listener on 127.0.0.1 (a 401 is read, a
       302 is not followed, the token goes in the Bearer header) and a closed
       port (status 0).

    9. app-rules.json -> savedDestinations.cases (#739 / mac #668), through
       deploy.ps1's Get-SavedDestinations.

    10. The real deploy.ps1, offline, in a scratch working folder with its
        credentials stubbed: the saved legs run and keep going after a failed
        one, a folder publish builds again unless the toolchain check says a
        plain yes (#749), and a saved token whose check hears nothing is kept.
        Needs the runtime's Python (PLANTOIR_RUNTIME or windows-app\Vendor\
        runtime) and skips by name without it.

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

# ---- 6. Where a launcher's own trail lines go (#682) ----
# app-rules.json -> launcherTrailFolder.cases, every one, through the REAL
# Write-TrailLine of EACH launcher. `{scratch}` is a scratch folder, `/` is
# written as `\`, no `value` means the variable is not set, and `default` is
# %LOCALAPPDATA%\Plantoir\Logs with LOCALAPPDATA pointed at scratch\home. The
# current folder - PowerShell's AND the process's, which IO.FileStream
# follows and Set-Location does not move - is the scratch folder, so a
# relative value wrongly taken lands inside it and is caught by the one-file
# check. Two Windows-only rows: C:state and \state\Logs are "rooted" to
# [IO.Path]::IsPathRooted on PowerShell 5.1 but not absolute.
$trailRules = $appRules.launcherTrailFolder
$trailVariable = [string]$trailRules.variable
$trailRows = @($trailRules.cases) + @(
    [PSCustomObject]@{ name = 'drive-relative, no separator (Windows only)'; value = 'C:state'; expect = 'default' },
    [PSCustomObject]@{ name = 'root of the current drive (Windows only)'; value = '\state\Logs'; expect = 'default' })
foreach ($launcher in @('preview.ps1', 'deploy.ps1')) {
    $source = Get-Content -LiteralPath (Join-Path $repo $launcher) -Raw -Encoding UTF8
    Report "launcherTrailFolder/$launcher" 'reads the contract''s variable' ($source.Contains('$env:' + $trailVariable)) "does not read `$env:$trailVariable"
    Import-LauncherFunctions (Join-Path $repo $launcher) @('Write-TrailLine')
    foreach ($case in $trailRows) {
        $list = "launcherTrailFolder/$launcher"
        $scratch = Join-Path ([IO.Path]::GetTempPath()) ('trail-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Force -Path $scratch
        $savedLocalAppData = $env:LOCALAPPDATA
        $savedVariable = [Environment]::GetEnvironmentVariable($trailVariable)
        $savedProcessFolder = [Environment]::CurrentDirectory
        $strayRoot = Join-Path ([IO.Path]::GetPathRoot($scratch)) 'state\Logs\activity.txt'
        $strayBefore = Test-Path -LiteralPath $strayRoot
        Push-Location -LiteralPath $scratch
        try {
            [Environment]::CurrentDirectory = $scratch
            $env:LOCALAPPDATA = Join-Path $scratch 'home'
            if ($case.PSObject.Properties.Name -contains 'value') {
                $value = ([string]$case.value).Replace('{scratch}', $scratch).Replace('/', '\')
                [Environment]::SetEnvironmentVariable($trailVariable, $value)
            } else {
                [Environment]::SetEnvironmentVariable($trailVariable, $null)
            }
            if ([string]$case.expect -eq 'default') {
                $expected = Join-Path $scratch 'home\Plantoir\Logs'
            } else {
                $expected = ([string]$case.expect).Replace('{scratch}', $scratch).Replace('/', '\').TrimEnd('\')
            }
            $what = 'case ' + [guid]::NewGuid().ToString('N')
            Write-TrailLine $what
            $file = Join-Path $expected 'activity.txt'
            $landed = (Test-Path -LiteralPath $file) -and ((Get-Content -LiteralPath $file -Raw -Encoding UTF8).Contains($what))
            $everything = @(Get-ChildItem -LiteralPath $scratch -Recurse -File -Force)
            $strayed = (-not $strayBefore) -and (Test-Path -LiteralPath $strayRoot)
            $ok = $landed -and $everything.Count -eq 1 -and -not $strayed
            $found = ($everything | ForEach-Object { $_.FullName.Substring($scratch.Length) }) -join ', '
            Report $list $case.name $ok "expected the line in $($file.Substring($scratch.Length)) and nothing else; found [$found]$(if ($strayed) { ' and ' + $strayRoot })"
            if ($strayed) { Remove-Item -LiteralPath $strayRoot -Force -ErrorAction SilentlyContinue }
        } finally {
            Pop-Location
            [Environment]::CurrentDirectory = $savedProcessFolder
            $env:LOCALAPPDATA = $savedLocalAppData
            [Environment]::SetEnvironmentVariable($trailVariable, $savedVariable)
            Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---- 7. A saved token is cleared only when the service says no (#705) ----
# app-rules.json -> savedTokenCheck.cases, every one, through deploy.ps1's
# Get-TokenCheckAnswer with the patterns deploy.ps1 itself carries
# (Get-TokenCheckPatterns) - and those patterns, and the URLs, must be the
# contract's, so neither side's table can drift from the other.
Import-LauncherFunctions (Join-Path $repo 'deploy.ps1') @('Get-TokenCheckPatterns', 'Get-TokenCheckAnswer', 'Invoke-TokenCheck', 'Get-SavedDestinations')
$tokenRules = $appRules.savedTokenCheck
foreach ($service in @('cloudflare', 'netlify')) {
    $carried = Get-TokenCheckPatterns $service
    $written = $tokenRules.services.$service
    Report 'savedTokenCheck.services' "$service url" ($carried.Url -ceq [string]$written.url) "deploy.ps1 asks '$($carried.Url)', the contract '$($written.url)'"
    Report 'savedTokenCheck.services' "$service accepted pattern" ($carried.Accepted -ceq [string]$written.acceptedWhenTheBodyMatches) "deploy.ps1 carries '$($carried.Accepted)'"
    Report 'savedTokenCheck.services' "$service refused pattern" ($carried.Refused -ceq [string]$written.refusedWhenTheBodyMatches) "deploy.ps1 carries '$($carried.Refused)'"
}
foreach ($case in @($tokenRules.cases)) {
    $patterns = Get-TokenCheckPatterns ([string]$case.service)
    $got = Get-TokenCheckAnswer ([int]$case.status) ([string]$case.body) $patterns.Accepted $patterns.Refused
    Report 'savedTokenCheck.cases' $case.name ($got -ceq [string]$case.expect) "expected $($case.expect), got $got"
}

# ---- 8. What the check hears from a real server (#705) ----
# Invoke-TokenCheck against a listener on this PC: a 401 or 403 is READ
# (Invoke-WebRequest would have thrown), a 302 is not followed, the token is
# sent as a Bearer header and nowhere else, and a closed port is status 0.
# Plain HTTP on 127.0.0.1, which needs no administrator rights here.
$probe = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$probe.Start(); $port = ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port; $probe.Stop()
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$port/")
$listener.Start()
$served = [hashtable]::Synchronized(@{})
$server = [powershell]::Create()
$null = $server.AddScript({
    param($listener, $served)
    $answers = @{
        '/refused401' = @(401, '{"success":false,"errors":[{"code":1000,"message":"Invalid API Token"}]}')
        '/filter403'  = @(403, "<html><body>Blocked by the school's web filter</body></html>")
        '/yes200'     = @(200, '{"result":{"status":"active"},"success":true}')
        '/portal302'  = @(302, '<html>Sign in to the Wi-Fi</html>')
        '/portal'     = @(200, '<html>Sign in to the Wi-Fi</html>')
    }
    while ($listener.IsListening) {
        try { $context = $listener.GetContext() } catch { break }
        $path = $context.Request.Url.AbsolutePath
        $served[$path] = [string]$context.Request.Headers['Authorization']
        $answer = $answers[$path]; if (-not $answer) { $answer = @(404, 'none') }
        $context.Response.StatusCode = [int]$answer[0]
        if ($answer[0] -eq 302) { $context.Response.RedirectLocation = 'http://127.0.0.1:' + $context.Request.Url.Port + '/portal' }
        $bytes = [Text.Encoding]::UTF8.GetBytes([string]$answer[1])
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.Close()
    }
}).AddArgument($listener).AddArgument($served)
$serving = $server.BeginInvoke()
try {
    $base = "http://127.0.0.1:$port"
    $cf = Get-TokenCheckPatterns 'cloudflare'
    foreach ($c in @(
        @{ path = '/refused401'; status = 401; word = 'refused' },
        @{ path = '/filter403';  status = 403; word = 'unheard' },
        @{ path = '/yes200';     status = 200; word = 'accepted' },
        @{ path = '/portal302';  status = 302; word = 'unheard' })) {
        $heard = Invoke-TokenCheck ($base + $c.path) 'stub-token-never-leaves-this-test'
        $word = Get-TokenCheckAnswer $heard.Status $heard.Body $cf.Accepted $cf.Refused
        Report 'tokenCheckOverHttp' $c.path (($heard.Status -eq $c.status) -and ($word -eq $c.word)) "expected $($c.status)/$($c.word), got $($heard.Status)/$word"
        Report 'tokenCheckOverHttp' ($c.path + ' sends the token as a Bearer header') ($served[$c.path] -ceq 'Bearer stub-token-never-leaves-this-test') "the server saw '$($served[$c.path])'"
    }
    Report 'tokenCheckOverHttp' 'a redirect is not followed' (-not $served.ContainsKey('/portal')) 'the portal page behind the 302 was fetched'
    # Port 9 (discard) is closed on this PC: nothing answers, and that is 0.
    $nothing = Invoke-TokenCheck 'http://127.0.0.1:9/' 'stub-token-never-leaves-this-test'
    Report 'tokenCheckOverHttp' 'nothing answering is status 0' (($nothing.Status -eq 0) -and ((Get-TokenCheckAnswer $nothing.Status $nothing.Body $cf.Accepted $cf.Refused) -eq 'unheard')) "got $($nothing.Status)"
} finally {
    $listener.Stop(); $listener.Close()
    try { $null = $server.EndInvoke($serving) } catch {}
    $server.Dispose()
}

# ---- 9. Where a course deploys when no destination is typed (#739) ----
# app-rules.json -> savedDestinations.cases, every one, through deploy.ps1's
# Get-SavedDestinations. The settings are handed over as the JSON TEXT the
# file would hold; settingsText is handed over as written.
$destRules = $appRules.savedDestinations
$destSentences = $destRules.sentences
foreach ($case in @($destRules.cases)) {
    if ($case.PSObject.Properties.Name -contains 'settingsText') { $text = [string]$case.settingsText }
    else { $text = $case.settings | ConvertTo-Json -Depth 10 }
    $legs = Get-SavedDestinations $text ([string]$destRules.course)
    if ($case.PSObject.Properties.Name -contains 'expectUnreadable' -and $case.expectUnreadable) {
        Report 'savedDestinations.cases' $case.name ($null -eq $legs) 'read settings the case says cannot be read'
        continue
    }
    if ($null -eq $legs) { Report 'savedDestinations.cases' $case.name $false 'could not read the settings'; continue }
    $legs = @($legs)
    $want = @($case.expectLegs)
    $ok = $legs.Count -eq $want.Count
    $detail = "expected $($want.Count) legs, got $($legs.Count)"
    for ($k = 0; $ok -and $k -lt $want.Count; $k++) {
        $gotFlags = (@($legs[$k].Flags) -join ' | ')
        $wantFlags = ''; if ($want[$k].PSObject.Properties.Name -contains 'flags') { $wantFlags = (@($want[$k].flags) -join ' | ') }
        $wantRefusal = ''; if ($want[$k].PSObject.Properties.Name -contains 'refusal') { $wantRefusal = [string]$want[$k].refusal }
        if ($legs[$k].Kind -cne [string]$want[$k].kind -or $gotFlags -cne $wantFlags -or ("$($legs[$k].Refusal)") -cne $wantRefusal) {
            $ok = $false
            $detail = "leg $k expected [$($want[$k].kind)] '$wantFlags' '$wantRefusal', got [$($legs[$k].Kind)] '$gotFlags' '$($legs[$k].Refusal)'"
        }
        $wordsFor = $destSentences.where.PSObject.Properties[[string]$legs[$k].Kind]
        $wantWords = if ($wordsFor) { [string]$wordsFor.Value } else { [string]$destSentences.where.netlify }
        if ($ok -and $legs[$k].Words -cne $wantWords) { $ok = $false; $detail = "leg $k reads '$($legs[$k].Words)', the contract '$wantWords'" }
    }
    Report 'savedDestinations.cases' $case.name $ok $detail
}
# The refusals Get-SavedDestinations writes are the contract's templates.
$sampleFolder = @(Get-SavedDestinations '{"deploy_target":"local_folder"}' 'ICS3U')[0].Refusal
Report 'savedDestinations.sentences' 'noFolder' ($sampleFolder -ceq ([string]$destSentences.noFolder).Replace('{course}', 'ICS3U')) "wrote '$sampleFolder'"
$sampleKind = @(Get-SavedDestinations '{"deploy_target":"x_y"}' 'ICS3U')[0].Refusal
Report 'savedDestinations.sentences' 'unknownKind' ($sampleKind -ceq ([string]$destSentences.unknownKind).Replace('{course}', 'ICS3U').Replace('{kind}', 'x_y')) "wrote '$sampleKind'"

# ---- 10. The real deploy.ps1, offline, in a scratch working folder ----
# What the pure functions above cannot show: that the launcher itself reads
# the saved legs, runs each one, keeps going after a failed leg and ends with
# the first failing leg's code (#739); that a folder publish asks which
# toolchain built the site and builds again when the answer is anything but
# a plain yes, a check that THROWS included (#749); and that a saved token is
# kept when its check hears nothing (#705). A COPY of deploy.ps1 (it runs
# from its own folder), the real runtime only for its Python
# (PLANTOIR_RUNTIME, read only), LOCALAPPDATA pointed into the scratch folder
# so the builds root is the scratch folder's, a stand-in preview.bat that says
# it was asked and exits with PREVIEW_STUB_EXIT, and a stand-in
# scripts\toolchain_paths.py whose answer is STAMP_STUB.
$runtime = $env:PLANTOIR_RUNTIME
if (-not $runtime -or -not (Test-Path -LiteralPath (Join-Path $runtime 'python\python.exe'))) {
    $runtime = Join-Path $repo 'windows-app\Vendor\runtime'
}
if (-not (Test-Path -LiteralPath (Join-Path $runtime 'python\python.exe'))) {
    Skip 'realDeploy' 'every real-launcher run' 'no runtime Python (windows-app\Vendor\fetch-runtime.ps1, or PLANTOIR_RUNTIME)'
} else {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('deploy-run-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path $work
    $saved = @{}
    foreach ($name in @('LOCALAPPDATA', 'PLANTOIR_RUNTIME', 'PLANTOIR_TRAIL_DIR', 'PREVIEW_STUB_EXIT', 'STAMP_STUB', 'TOKEN_CHECK_STUB_URL')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
    try {
        # The copy is STUBBED wherever it would touch this PC's real
        # credentials: its credential functions only say what they were asked
        # to do, both token checks ask TOKEN_CHECK_STUB_URL (a closed port), and
        # it stops before the website builder - as the mac's
        # test_deploy_token_refusal.py stubs deploy.sh. So no run here, and no
        # launcher made wrong by a mutation, can deploy anything or clear a token.
        $source = [IO.File]::ReadAllText((Join-Path $repo 'deploy.ps1'))
        $marker = "# ======================`r`n# Native run (no container)"
        if (-not $source.Contains($marker)) { $marker = "# ======================`n# Native run (no container)" }
        $stubbed = $source
        foreach ($pair in @(
            @('https://api.cloudflare.com/client/v4/user/tokens/verify', $null),
            @('https://api.netlify.com/api/v1/user', $null))) {
            Report 'realDeploy' ("deploy.ps1 still asks " + $pair[0]) ($stubbed.Contains("Url = '" + $pair[0] + "'")) 'the URL moved, so the stub below proves nothing'
            $stubbed = $stubbed.Replace("Url = '" + $pair[0] + "'", "Url = `$env:TOKEN_CHECK_STUB_URL")
        }
        $stubs = @'
function Get-CfTokenFromCredMan { 'stub-token-never-leaves-this-test' }
function Remove-CfTokenInCredMan { Write-Host 'CLEARED-THE-CLOUDFLARE-TOKEN' }
function Remove-CfAccountInCredMan { Write-Host 'CLEARED-THE-CLOUDFLARE-ACCOUNT' }
function Get-CloudflareAccountId([string]$token) { '0123456789abcdef0123456789abcdef' }
function Set-CfAccountInCredMan([string]$id) { }
function Get-TokenFromCredMan { 'stub-token-never-leaves-this-test' }
function Remove-TokenInCredMan { Write-Host 'CLEARED-THE-NETLIFY-TOKEN' }
function Set-TokenInCredMan([string]$token) { Write-Host 'WROTE-A-NETLIFY-TOKEN' }
function Set-CfTokenInCredMan([string]$token) { Write-Host 'WROTE-A-CLOUDFLARE-TOKEN' }
'@
        $anchor = 'if ($RESET_TOKEN -and $TARGET -eq ''cloudflare'') {'
        Report 'realDeploy' 'deploy.ps1 still carries the place the stubs go' ($stubbed.Contains($anchor) -and $stubbed.Contains($marker)) 'a marker moved'
        $stubbed = $stubbed.Replace($anchor, $stubs + "`r`n" + $anchor).Replace($marker, "Write-Host 'REACHED-THE-WEBSITE-BUILDER'`r`nexit 0`r`n" + $marker)
        [IO.File]::WriteAllText((Join-Path $work 'deploy.ps1'), $stubbed)
        $env:TOKEN_CHECK_STUB_URL = 'http://127.0.0.1:9/'
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $work 'scripts'), (Join-Path $work 'courses\ICS3U')
        [IO.File]::WriteAllText((Join-Path $work 'preview.bat'), "@echo off`r`necho PREVIEW-WAS-ASKED %*`r`nexit /b %PREVIEW_STUB_EXIT%`r`n")
        [IO.File]::WriteAllText((Join-Path $work 'scripts\toolchain_paths.py'),
            "import os`nwhat = os.environ.get('STAMP_STUB', '')`nif what == 'throw':`n    raise RuntimeError('a check that throws')`ndef site_was_built_by_this_toolchain(section_dir):`n    return what == 'yes'`n")
        $env:LOCALAPPDATA = Join-Path $work 'home'
        $env:PLANTOIR_RUNTIME = $runtime
        $env:PLANTOIR_TRAIL_DIR = Join-Path $work 'trail'

        function Invoke-ScratchDeploy([string[]]$Arguments) {
            $info = New-Object System.Diagnostics.ProcessStartInfo
            $info.FileName = 'powershell.exe'
            $quoted = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $work 'deploy.ps1') + '"'))
            foreach ($a in $Arguments) { if ($a -match '\s') { $quoted += ('"' + $a + '"') } else { $quoted += $a } }
            $info.Arguments = $quoted -join ' '
            $info.WorkingDirectory = $work
            $info.UseShellExecute = $false
            $info.RedirectStandardOutput = $true
            $info.RedirectStandardError = $true
            $info.RedirectStandardInput = $true
            $process = [Diagnostics.Process]::Start($info)
            $process.StandardInput.Close()
            $out = $process.StandardOutput.ReadToEndAsync(); $err = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(180000)) { try { $process.Kill() } catch {}; return [pscustomobject]@{ Code = -1; Said = 'TIMED OUT' } }
            $process.WaitForExit()
            return [pscustomobject]@{ Code = $process.ExitCode; Said = ($out.Result + $err.Result) }
        }
        function Set-Settings([string]$Json) { [IO.File]::WriteAllText((Join-Path $work 'courses\ICS3U\course_config.json'), $Json) }

        # Where the copy builds into: the launcher names it when it is missing.
        Set-Settings '{"course_code":"ICS3U"}'
        $first = Invoke-ScratchDeploy @('ICS3U', '1', '--to-folder', (Join-Path $work 'published'))
        $sectionDir = $null
        $lines = @($first.Said -split "`r?`n")
        for ($k = 0; $k -lt $lines.Count - 1; $k++) { if ($lines[$k] -like 'Section directory not found on host:*') { $sectionDir = $lines[$k + 1].Trim() } }
        Report 'realDeploy' 'the launcher names the section it builds into' ($null -ne $sectionDir -and $sectionDir.StartsWith((Join-Path $work 'home'))) ("said: " + $first.Said)
        if ($sectionDir) {
            $null = New-Item -ItemType Directory -Force -Path (Join-Path $sectionDir 'public')
            [IO.File]::WriteAllText((Join-Path $sectionDir 'public\index.html'), '<html>a built site</html>')

            # #749: a plain yes publishes as it is; no, or a check that throws, builds first.
            foreach ($c in @(
                @{ stamp = 'yes';   rebuild = $false; code = 0 },
                @{ stamp = 'no';    rebuild = $true;  code = 3 },
                @{ stamp = 'throw'; rebuild = $true;  code = 3 })) {
                $env:STAMP_STUB = $c.stamp; $env:PREVIEW_STUB_EXIT = '3'
                $run = Invoke-ScratchDeploy @('ICS3U', '1', '--to-folder', (Join-Path $work 'published'))
                $asked = $run.Said.Contains('PREVIEW-WAS-ASKED ICS3U 1 --build-only')
                $said = $run.Said.Contains('Plantoir has been updated since this site was built, so it is')
                Report 'realDeploy' ("toolchain check answering '" + $c.stamp + "'") (($asked -eq $c.rebuild) -and ($said -eq $c.rebuild) -and ($run.Code -eq $c.code)) ("exit $($run.Code), rebuilt $asked; said: " + $run.Said)
            }
            Report 'realDeploy' 'a site this version built is published' (Test-Path -LiteralPath (Join-Path $work 'published\section1\index.html')) 'nothing reached the folder'

            # #739: two saved folder legs. The first is refused by the leg
            # itself (a drive-relative folder, exit 1); the second builds first
            # and its stand-in build needs an answer (exit 3). Both run, and the
            # run ends with the FIRST failing leg's code. Then the other order.
            $env:STAMP_STUB = 'no'; $env:PREVIEW_STUB_EXIT = '3'
            $good = (Join-Path $work 'published2').Replace('\', '/')
            Set-Settings ('{"course_code":"ICS3U","deploy_target":"local_folder","deploy_folder_path":"C:relative","additional_deploy_targets":[{"type":"local_folder","path":"' + $good + '"}]}')
            $run = Invoke-ScratchDeploy @('ICS3U', '1', '--non-interactive')
            $legLine = [string]$destSentences.eachLeg
            $legLine = $legLine.Replace('{course}', 'ICS3U').Replace('{section}', '1').Replace('{where}', [string]$destSentences.where.local_folder)
            $legsSaid = ([regex]::Matches($run.Said, [regex]::Escape($legLine))).Count
            Report 'realDeploy' 'every saved leg runs, after a failed one too' (($legsSaid -eq 2) -and $run.Said.Contains('partly written') -and $run.Said.Contains('PREVIEW-WAS-ASKED ICS3U 1 --build-only --non-interactive')) ("said: " + $run.Said)
            Report 'realDeploy' 'the run ends with the first failing leg''s code (1 then 3)' ($run.Code -eq 1) "exit $($run.Code)"
            Set-Settings ('{"course_code":"ICS3U","deploy_target":"local_folder","deploy_folder_path":"' + $good + '","additional_deploy_targets":[{"type":"local_folder","path":"C:relative"}]}')
            $run = Invoke-ScratchDeploy @('ICS3U', '1', '--non-interactive')
            Report 'realDeploy' 'the run ends with the first failing leg''s code (3 then 1)' ($run.Code -eq 3) ("exit $($run.Code); said: " + $run.Said)

            # Settings that cannot be read refuse, and never fall back to
            # Netlify (which, in this copy, would meet a stand-in token).
            Set-Settings '{ not json'
            $run = Invoke-ScratchDeploy @('ICS3U', '1')
            $couldNot = ([string]$destSentences.couldNotRead[0]).Replace('{course}', 'ICS3U')
            Report 'realDeploy' 'unreadable settings refuse, and do not fall back to Netlify' (($run.Code -eq 1) -and $run.Said.Contains($couldNot) -and $run.Said.Contains([string]$destSentences.couldNotRead[1]) -and -not $run.Said.Contains('Netlify')) ("exit $($run.Code); said: " + $run.Said)

            # #705: a saved token whose check hears nothing is KEPT: the
            # copy's stand-in token is checked against a closed port.
            Set-Settings '{"course_code":"ICS3U"}'
            foreach ($service in @('cloudflare', 'netlify')) {
                $run = Invoke-ScratchDeploy @('ICS3U', '1', '--target', $service, '--non-interactive')
                $kept = (-not $run.Said.Contains('CLEARED-THE')) -and $run.Said.Contains('to check the saved token, so this section was not deployed there') -and -not $run.Said.Contains('REACHED-THE-WEBSITE-BUILDER')
                Report 'realDeploy' "a $service token whose check hears nothing is kept" ($kept -and $run.Code -eq 1) ("exit $($run.Code); said: " + $run.Said)
            }
            # A Cloudflare course, and nothing typed: the one-destination line,
            # and it is Cloudflare's token that is checked. Then a typed
            # --target netlify wins over the same settings, and nothing is read.
            Set-Settings '{"course_code":"ICS3U","deploy_target":"cloudflare_pages"}'
            $oneLine = ([string]$destSentences.oneDestination).Replace('{where}', [string]$destSentences.where.cloudflare_pages).Replace('{course}', 'ICS3U')
            $run = Invoke-ScratchDeploy @('ICS3U', '1', '--non-interactive')
            Report 'realDeploy' 'a Cloudflare course with nothing typed deploys to Cloudflare' ($run.Said.Contains($oneLine) -and $run.Said.Contains('could not reach Cloudflare')) ("said: " + $run.Said)
            $run = Invoke-ScratchDeploy @('ICS3U', '1', '--target', 'netlify', '--non-interactive')
            Report 'realDeploy' 'a typed --target wins over the settings' ((-not $run.Said.Contains("settings say")) -and $run.Said.Contains('could not reach Netlify')) ("said: " + $run.Said)
        }
    } finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
        $env:TOKEN_CHECK_STUB_URL = $null
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ("{0} passed, {1} failed, {2} skipped" -f $passed, $failed, $skipped)
if ($failed -gt 0) { exit 1 }
exit 0

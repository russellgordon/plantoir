<#
.SYNOPSIS
    Runs the SHARED stopPreview cases against the launcher's own matcher.

.DESCRIPTION
    Which processes belong to a section's preview is answered twice on this
    platform: once in scripts/stop_preview.py (which build_site.py calls, and
    which now reads a native process list too), and once in preview.ps1's
    --stop mode, which must never start anything and so cannot depend on the
    bundled interpreter being resolvable at the moment a teacher closes a
    window.

    Two implementations do not have to drift, but they will unless something
    checks. This is that something: the cases are DESERIALISED from
    contracts/shared-rules.json -> stopPreview and run against the real
    functions in preview.ps1, extracted with the PowerShell parser rather than
    dot-sourced (dot-sourcing would execute the launcher). Parsing the file
    also proves it still parses, which is worth having on a machine where the
    mac cannot run anything.

    Exactly ONE case may be skipped: the one carrying
    needsEvidence: ["workingDirectory"]. Win32_Process does not expose a
    working directory, so that case cannot be decided here - and it says so
    itself. Every other case must reach the contract's verdict with the cwd
    field blank, which is the property that makes this platform's blindness
    survivable.

    Run with:  powershell -NoProfile -File windows-app\test_stop_preview.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $repo 'preview.ps1'
$contractPath = Join-Path $repo 'contracts\shared-rules.json'

if (-not (Test-Path $launcher)) { throw "preview.ps1 not found at $launcher" }
if (-not (Test-Path $contractPath)) { throw "contract not found at $contractPath" }

# --- Lift the matcher out of the launcher, without running the launcher ---
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($launcher, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    Write-Host "preview.ps1 DOES NOT PARSE:" -ForegroundColor Red
    foreach ($e in $parseErrors) { Write-Host ("  line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) }
    exit 1
}
$wanted = @('Test-NamesPath', 'Test-ArgumentValue', 'Test-IsServing', 'Get-SectionProcessesToStop')
foreach ($name in $wanted) {
    $found = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true)
    if ($found.Count -lt 1) { throw "preview.ps1 no longer defines $name at script scope" }
    Invoke-Expression $found[0].Extent.Text
}

# --- The cases, deserialised. Never retyped. ---
$contract = (Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json).stopPreview
$cases = @($contract.cases)
if ($cases.Count -lt 23) { throw "the contract lost stopPreview cases: found $($cases.Count)" }

$passed = 0
$failed = 0
$skipped = 0
$failures = @()

foreach ($case in $cases) {
    # Win32_Process has no working directory to give, so every case runs
    # with it BLANK - including the ones whose fixture carries one. That is
    # the point: a case that still reaches its verdict without that evidence
    # is a case this platform genuinely answers.
    $snapshot = @()
    foreach ($process in $case.snapshot) {
        $snapshot += [PSCustomObject]@{
            ProcessId       = [uint32]$process.pid
            ParentProcessId = [uint32]$process.ppid
            Name            = [string]$process.name
            CommandLine     = [string]$process.commandLine
        }
    }

    $needsWorkingDirectory = $false
    if ($case.PSObject.Properties.Name -contains 'needsEvidence' -and $case.needsEvidence) {
        if (@($case.needsEvidence) -contains 'workingDirectory') { $needsWorkingDirectory = $true }
    }
    if ($needsWorkingDirectory) {
        $skipped++
        Write-Host ("SKIP  {0}" -f $case.name) -ForegroundColor Yellow
        Write-Host "        needs evidence this platform has none of: workingDirectory"
        continue
    }

    $actual = @(Get-SectionProcessesToStop -Snapshot $snapshot `
                                           -Directories @($case.section.directories) `
                                           -Course $case.section.course `
                                           -Section ([string]$case.section.number) `
                                           -Mode $case.mode)
    $expected = @($case.stops | ForEach-Object { [uint32]$_ })

    if (($actual -join ',') -eq ($expected -join ',')) {
        $passed++
        Write-Host ("ok    {0}" -f $case.name) -ForegroundColor DarkGray
    } else {
        $failed++
        $failures += $case.name
        Write-Host ("FAIL  {0}" -f $case.name) -ForegroundColor Red
        Write-Host ("        mode     {0}" -f $case.mode)
        Write-Host ("        why      {0}" -f $case.why)
        Write-Host ("        expected [{0}]" -f ($expected -join ', '))
        Write-Host ("        got      [{0}]" -f ($actual -join ', '))
    }
}

# --- Two guarantees the contract's cases cannot reach ---
# Both are real properties of this matcher that no fixture exercises: the
# cases never pass -Exclude, and the pid<=1 rule is decided on Windows by
# absent evidence rather than by the guard. Removing either guard still
# passed all 23, so they are asserted here directly.
$guard = @(
    [PSCustomObject]@{ ProcessId = 4242; ParentProcessId = 1; Name = 'node'; CommandLine = 'node C:\builds\work\ADA1O\section1\quartz\bootstrap-cli.mjs build --serve' },
    [PSCustomObject]@{ ProcessId = 4243; ParentProcessId = 4242; Name = 'esbuild'; CommandLine = 'esbuild --service' }
)
$withoutExclusion = @(Get-SectionProcessesToStop -Snapshot $guard -Directories @('C:\builds\work\ADA1O\section1') -Course 'ADA1O' -Section '1' -Mode 'everything')
if (($withoutExclusion -join ',') -eq '4242,4243') {
    $passed++; Write-Host "ok    (local) the server and its child are both found" -ForegroundColor DarkGray
} else {
    $failed++; $failures += "(local) server and child found"
    Write-Host "FAIL  (local) expected [4242, 4243], got [$($withoutExclusion -join ', ')]" -ForegroundColor Red
}
$withExclusion = @(Get-SectionProcessesToStop -Snapshot $guard -Directories @('C:\builds\work\ADA1O\section1') -Course 'ADA1O' -Section '1' -Mode 'everything' -Exclude @([uint32]4242))
if ($withExclusion.Count -eq 0) {
    $passed++; Write-Host "ok    (local) an excluded process is not stopped, and neither are its children through it" -ForegroundColor DarkGray
} else {
    $failed++; $failures += "(local) exclusion"
    Write-Host "FAIL  (local) exclusion ignored: got [$($withExclusion -join ', ')]" -ForegroundColor Red
}
# pid 1, named directly by the same evidence, must still be refused.
$initLike = @([PSCustomObject]@{ ProcessId = 1; ParentProcessId = 0; Name = 'init'; CommandLine = 'init C:\builds\work\ADA1O\section1 --serve' })
$initResult = @(Get-SectionProcessesToStop -Snapshot $initLike -Directories @('C:\builds\work\ADA1O\section1') -Course 'ADA1O' -Section '1' -Mode 'everything')
if ($initResult.Count -eq 0) {
    $passed++; Write-Host "ok    (local) pid 1 is never stopped, however well it matches" -ForegroundColor DarkGray
} else {
    $failed++; $failures += "(local) pid 1"
    Write-Host "FAIL  (local) pid 1 was stopped" -ForegroundColor Red
}

# --- The one skip is a budget, not a licence ---
if ($skipped -gt 1) {
    Write-Host "More than one case was skipped; only the workingDirectory case may be." -ForegroundColor Red
    $failed++
}

Write-Host ""
Write-Host ("{0} passed, {1} failed, {2} skipped, of {3} contract cases" -f $passed, $failed, $skipped, $cases.Count)
if ($failed -gt 0) {
    Write-Host "Failed cases:" -ForegroundColor Red
    foreach ($name in $failures) { Write-Host "  - $name" }
    exit 1
}
exit 0

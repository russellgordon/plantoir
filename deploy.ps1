#!/usr/bin/env pwsh
#requires -Version 5.1
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Show-Help {
@"
Usage:
  .\deploy.bat <COURSE_CODE> <SECTION_NUMBER> [--target netlify|cloudflare] [--diagnose] [--team <TEAM_SLUG>] [--to-folder <PATH>] [--reset-token|--logout] [--non-interactive]

Examples:
  .\deploy.bat ICS3U 1
  .\deploy.bat ICS3U 1 --diagnose
  .\deploy.bat ICS3U 1 --team my-org-slug
  .\deploy.bat ICS3U 1 --target cloudflare

Notes:
- Deploys from /teaching/courses/<COURSE>/.merged_output/section<SECTION> inside the container.
- You must build first (the static site goes to 'public/' in that section folder).
- --target chooses where the built site goes. netlify (the default) or cloudflare.
- The token for whichever service you deploy to is stored as a Windows Generic
  Credential and injected securely at runtime. Netlify and Cloudflare tokens are
  stored separately, so using one never disturbs the other.
- A Cloudflare token needs one permission: Account - Cloudflare Pages - Edit.
  The account is discovered from the token, so there is nothing else to enter.
- Use --reset-token (or --logout) to remove the saved token and re-link on next
  run; combine it with --target cloudflare to clear the Cloudflare one instead.
- If your course code ends with '0' (zero), you'll be prompted to correct it to 'O' for Open-level courses.
"@ | Out-Host
}

function Normalize-HostPath([string]$p) {
  if (-not $p) { return $p }
  try { $r = (Resolve-Path -LiteralPath $p).Path } catch { $r = $p }
  return $r.TrimEnd('\','/')
}

# Ensure we run from the script directory
$ScriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
if (-not $ScriptDir) { $ScriptDir = Get-Location }
Set-Location -LiteralPath $ScriptDir

# ======================
# Defaults / constants
# ======================
# One container per working folder, so two folders never repoint each
# other's mounts. The name is a short hash of this folder's PHYSICAL path
# (true on-disk casing, symlinks resolved) plus a trailing newline —
# parity with `pwd -P | shasum -a 256` on macOS. The app derives the
# identical name, so this derivation must not drift.
if (-not ([System.Management.Automation.PSTypeName]'Plantoir.PathApi').Type) {
  Add-Type -Namespace Plantoir -Name PathApi -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern IntPtr CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern uint GetFinalPathNameByHandleW(IntPtr hFile, System.Text.StringBuilder lpszFilePath, uint cchFilePath, uint dwFlags);
[DllImport("kernel32.dll")]
public static extern bool CloseHandle(IntPtr hObject);
'@
}
function Get-PhysicalPath([string]$p) {
  try {
    $h = [Plantoir.PathApi]::CreateFileW($p, 0, 7, [IntPtr]::Zero, 3, 0x02000000, [IntPtr]::Zero)
    if ($h.ToInt64() -ne -1) {
      $sb = New-Object System.Text.StringBuilder 4096
      $len = [Plantoir.PathApi]::GetFinalPathNameByHandleW($h, $sb, 4096, 0)
      [void][Plantoir.PathApi]::CloseHandle($h)
      if ($len -gt 0) {
        $r = $sb.ToString()
        if ($r.StartsWith('\\?\UNC\')) { $r = '\\' + $r.Substring(8) }
        elseif ($r.StartsWith('\\?\')) { $r = $r.Substring(4) }
        return $r.TrimEnd('\')
      }
    }
  } catch {}
  return ([System.IO.Path]::GetFullPath($p)).TrimEnd('\')
}
$WORKDIR_PHYSICAL = Get-PhysicalPath (Get-Location).Path
$WORKDIR_ID = ([BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes("$WORKDIR_PHYSICAL`n"))) -replace '-','').Substring(0,8).ToLower()
$CONTAINER_NAME = "teaching-quartz-$WORKDIR_ID"

# ==================== Native toolchain (no container) ====================
# When the app's bundled runtime folder is present, everything runs directly
# on this PC: no WSL2, no Docker, no administrator rights, no one-time
# machine setup at all. The runtime is found through PLANTOIR_RUNTIME (set
# by the app), falling back to the installed app's own folder so launchers
# run by hand still find it. The container path is GONE on Windows - the
# native runtime is the only way this launcher builds anything.
$NATIVE_RUNTIME = $env:PLANTOIR_RUNTIME
if (-not $NATIVE_RUNTIME) {
  $appRuntime = Join-Path $env:LOCALAPPDATA 'Programs\Plantoir\runtime'
  if (Test-Path (Join-Path $appRuntime 'manifest.json')) { $NATIVE_RUNTIME = $appRuntime }
}
if ($NATIVE_RUNTIME -and -not (Test-Path (Join-Path $NATIVE_RUNTIME 'manifest.json'))) { $NATIVE_RUNTIME = $null }

# Points the shared Python at the bundled runtime and this working folder,
# and returns the bundled interpreter's path. $WORKDIR_ID is computed below,
# before any caller runs.
function Enter-NativeRuntime {
  $env:PATH = (Join-Path $NATIVE_RUNTIME 'node') + ';' + (Join-Path $NATIVE_RUNTIME 'wrangler\node_modules\.bin') + ';' + $env:PATH
  $toolchainDir = Join-Path (Get-Location).Path '.toolchain'
  $base = if (Test-Path (Join-Path $toolchainDir 'scripts')) { $toolchainDir } else { (Get-Location).Path }
  $env:PLANTOIR_SCRIPTS_DIR = Join-Path $base 'scripts'
  $env:PLANTOIR_SUPPORT_DIR = Join-Path $base 'support'
  $env:PLANTOIR_CONTRACTS_DIR = Join-Path $base 'contracts'
  $env:PLANTOIR_QUARTZ_DIR  = Join-Path $NATIVE_RUNTIME 'quartz'
  $env:PLANTOIR_EMOJI_FONT  = Join-Path $NATIVE_RUNTIME 'fonts\NotoColorEmoji.ttf'
  $env:PLANTOIR_COURSES_DIR = Join-Path (Get-Location).Path 'courses'
  # Build output lives OUTSIDE the working folder: teachers keep working
  # folders in OneDrive, and a build's thousands of small files would sync
  # and lock in place there.
  $buildRoot = Join-Path $env:LOCALAPPDATA ('Plantoir\builds\' + $WORKDIR_ID)
  $env:PLANTOIR_BUILD_ROOT = $buildRoot
  $env:PLANTOIR_WORK_DIR   = Join-Path $buildRoot 'work'
  # The embeddable Python defaults to the ANSI code page; the scripts print
  # their progress with emoji.
  $env:PYTHONUTF8 = '1'
  $env:PYTHONIOENCODING = 'utf-8'
  return (Join-Path $NATIVE_RUNTIME 'python\python.exe')
}
# =========================================================================

# The container path is gone on Windows: a copy without the bundled runtime
# cannot build anything, and the fix for a teacher is a reinstall.
if (-not $NATIVE_RUNTIME) {
  Write-Host "ERROR: This copy of Plantoir is missing its website builder."
  Write-Host "Reinstall Plantoir, then try again."
  exit 1
}
$KEY_TARGET     = 'containerized-quartz-netlify'  # Windows Credential Manager target
# Cloudflare's token lives under its own name, so a teacher who publishes some
# courses to Netlify and others to Cloudflare keeps both without one clobbering
# the other, and --reset-token only clears the one they are actually using.
$CF_KEY_TARGET  = 'containerized-quartz-cloudflare'
# Remembered separately, and only used when the token cannot name its own
# account — a teacher should never be asked for this twice.
$CF_ACCT_TARGET = 'containerized-quartz-cloudflare-account'
$TOKENS_FILE    = Join-Path -Path $ScriptDir -ChildPath 'courses\.internal\tokens.json'
$KEY_FILE       = Join-Path -Path $ScriptDir -ChildPath 'courses\.internal\.key'

# The image is built locally from this folder's recipe. Resolved later,
# once the helper functions are defined (PowerShell reads top to bottom).
$script:IMAGE_REF = $null

# ======================
# Arg parsing
# ======================
if ($args.Count -lt 2) { Show-Help; exit 1 }

$COURSE_CODE = $args[0].ToUpperInvariant()

# A course code may not begin with a dot, and the refusal is here rather than
# in a comment claiming it cannot happen. Plantoir builds a reference course
# under a HIDDEN folder inside courses/ and renames it into place as the last
# act; handed that hidden name, this script used to treat it as an ordinary
# course, and during the copy there is no marker yet to refuse it. The app can
# never pass such a name, but a person or another program can type one.
if ($COURSE_CODE -like '.*') {
    Write-Host ""
    Write-Host "A course code cannot begin with a dot."
    Write-Host "   Choose one of your courses - the codes in Plantoir's sidebar."
    Write-Host ""
    exit 1
}
$SECTION_NUM = $args[1]
$DIAGNOSE    = ''
$TEAM_SLUG   = ''
$RESET_TOKEN = $false
$TO_FOLDER = ''
$TARGET = 'netlify'
$ACCOUNT_ARG = ''
$NON_INTERACTIVE = $false

for ($i = 2; $i -lt $args.Count; $i++) {
  switch -Regex ($args[$i]) {
    '^--help$|^-h$'      { Show-Help; exit 0 }
    '^--diagnose$'       { $DIAGNOSE = '--diagnose'; continue }
    '^--non-interactive$' { $NON_INTERACTIVE = $true; continue }
    '^--target$'         { if ($i + 1 -ge $args.Count) { Write-Host "Missing value for --target"; Show-Help; exit 1 }; $TARGET = ([string]$args[$i+1]).ToLower(); $i++; continue }
    '^--target=(.+)$'    { $TARGET = $Matches[1].ToLower(); continue }
    '^--account$'        { if ($i + 1 -ge $args.Count) { Write-Host "Missing value for --account"; Show-Help; exit 1 }; $ACCOUNT_ARG = ([string]$args[$i+1]).Trim(); $i++; continue }
    '^--account=(.+)$'   { $ACCOUNT_ARG = $Matches[1].Trim(); continue }
    '^--team$'           { if ($i + 1 -ge $args.Count) { Write-Host "Missing value for --team"; Show-Help; exit 1 }; $TEAM_SLUG = $args[$i+1]; $i++; continue }
    '^--team=(.+)$'      { $TEAM_SLUG = $Matches[1]; continue }
    '^--team-slug$'      { if ($i + 1 -ge $args.Count) { Write-Host "Missing value for --team-slug"; Show-Help; exit 1 }; $TEAM_SLUG = $args[$i+1]; $i++; continue }
    '^--team-slug=(.+)$' { $TEAM_SLUG = $Matches[1]; continue }
    '^--to-folder$'      { if ($i + 1 -ge $args.Count) { Write-Host "Missing value for --to-folder"; Show-Help; exit 1 }; $TO_FOLDER = $args[$i+1]; $i++; continue }
    '^--to-folder=(.+)$' { $TO_FOLDER = $Matches[1]; continue }
    '^--reset-token$'    { $RESET_TOKEN = $true; continue }
    '^--logout$'         { $RESET_TOKEN = $true; continue }
    default              { Write-Host "Unknown option: $($args[$i])"; Show-Help; exit 1 }
  }
}

if ($TARGET -ne 'netlify' -and $TARGET -ne 'cloudflare') {
  Write-Host ("Unknown deploy target '{0}'. Use netlify or cloudflare." -f $TARGET)
  exit 1
}

# Called immediately before every question this script asks. Under
# --non-interactive there is nobody to answer it - the deploy was set to
# happen on its own, at half six, with the app closed - so it REFUSES and says
# which question it could not ask, rather than waiting for an answer that will
# never come or quietly taking a default.
#
# Exit code 3 means that and nothing else, matching deploy.py's NEEDS_AN_ANSWER;
# the scheduled wrapper reads it and leaves a note for the app to show the
# teacher. Every other exit in this script is 0 or 1.
function Assert-CanAsk([string]$question, [string]$whatToDo) {
  if (-not $NON_INTERACTIVE) { return }
  Write-Host ""
  Write-Host "This deploy was set to happen on its own, so nobody is here to answer:"
  Write-Host ("   {0}" -f $question)
  Write-Host (" {0}" -f $whatToDo)
  Write-Host " Nothing was deployed."
  exit 3
}

# Friendly guard: 'Open' course code ended with zero
if ($COURSE_CODE -match '^[A-Z]{3}[0-9]0$') {
  $suggested = $COURSE_CODE.Substring(0, $COURSE_CODE.Length-1) + 'O'
  Write-Host ""
  Write-Host ("It looks like you entered '{0}' (ends with zero)." -f $COURSE_CODE)
  Write-Host "Ontario 'Open' level course codes end with the LETTER 'O' (oh)."
  $suggestedCfg = Join-Path -Path $ScriptDir -ChildPath ("courses\{0}\course_config.json" -f $suggested)
  $originalCfg  = Join-Path -Path $ScriptDir -ChildPath ("courses\{0}\course_config.json" -f $COURSE_CODE)
  if ((Test-Path $suggestedCfg) -and -not (Test-Path $originalCfg)) {
    Write-Host ("I see setup data for '{0}' on disk." -f $suggested)
  }
  Assert-CanAsk ("Fix course code to '{0}'? [Y/n]" -f $suggested) "Deploy this section once from Plantoir, where you can answer it."
  $ans = Read-Host ("Fix course code to '{0}'? [Y/n]" -f $suggested)
  if (-not $ans) { $ans = 'Y' }
  if ($ans -match '^[Yy]$') {
    $COURSE_CODE = $suggested
    Write-Host ("Using corrected course code: {0}" -f $COURSE_CODE)
  } else {
    Write-Host ("Continuing with: {0}" -f $COURSE_CODE)
  }
  Write-Host ""
}

# ---------- A course kept for reference is never deployed ----------
#
# HERE, early, for the same reason deploy.sh checks here: this script's own
# folder-publish branch copies host-side and never enters the container, so
# deploy.py's refusal never runs on that path. A guard written only in the
# shared Python would leave the folder destination wide open. verify.sh greps
# BOTH launchers for this, from the mac, so its absence here is caught on that
# side rather than only by somebody noticing.
#
# Plain PowerShell, reading the settings file directly: this path needs no
# python on the host and must not start to.
#
# FAILS CLOSED — a settings file that is there and cannot be read refuses. A
# settings file that is ABSENT is not this check's business; the course-folder
# check further down says that in its own words.
#
# The sentence is a constant so a test can compare it with
# contracts/shared-rules.json -> referenceCourses.refusal.sentence.
$REFERENCE_COURSE_REFUSAL = "is kept for reference, so it is never deployed. Deploy the course you are teaching instead."
$referenceCfg = Join-Path -Path $ScriptDir -ChildPath ("courses\{0}\course_config.json" -f $COURSE_CODE)
# -PathType Leaf: Test-Path matches CONTAINERS too, so a folder named
# course_config.json passed this and then threw inside Get-Content, refusing a
# course the mac and the shared Python both allow. One word, and the four
# readers agree on that row.
if (Test-Path -LiteralPath $referenceCfg -PathType Leaf) {
  $referenceText = $null
  try {
    $referenceText = Get-Content -LiteralPath $referenceCfg -Raw -ErrorAction Stop
  } catch {
    Write-Host ""
    Write-Host ("Plantoir cannot tell whether {0} is kept for reference -" -f $COURSE_CODE)
    Write-Host "   its settings file could not be read. Nothing was deployed."
    exit 1
  }
  # .NET regex: `\s` matches a newline, so no flattening is needed here — and
  # `-match` is case-INSENSITIVE by default in PowerShell, which is why the
  # bash twin spells the value out as [Tt][Rr][Uu][Ee] rather than relying on
  # a `-i` the two shells would not share. The table of inputs both launchers
  # and the shared Python must agree on is
  # contracts/shared-rules.json -> referenceCourses.markerAgreement.
  # A marker that is there with a value that is neither true nor false. Same
  # rule and the same sentence as the bash twin.
  # An object KEY written with a \u escape — see the bash twin for why, and
  # why VALUES are left alone.
  if ($referenceText -cmatch '[{,]\s*"[^"]*\\u[0-9a-fA-F]{4}[^"]*"\s*:') {
    Write-Host ""
    Write-Host ("Plantoir cannot tell whether {0} is kept for reference -" -f $COURSE_CODE)
    Write-Host "   its settings say something other than true or false. Nothing was deployed."
    Write-Host ""
    exit 1
  }
  if (($referenceText -cmatch '"[^"]*ept_for_reference"') -and
      -not ($referenceText -cmatch '"[^"]*ept_for_reference"\s*:\s*[Tt][Rr][Uu][Ee]') -and
      -not ($referenceText -cmatch '"[^"]*ept_for_reference"\s*:\s*[Ff][Aa][Ll][Ss][Ee]')) {
    Write-Host ""
    Write-Host ("Plantoir cannot tell whether {0} is kept for reference -" -f $COURSE_CODE)
    Write-Host "   its settings say something other than true or false. Nothing was deployed."
    Write-Host ""
    exit 1
  }
  # -cmatch, case-SENSITIVE. `-match` is case-insensitive in PowerShell, and
  # that applied to the KEY as well as the value — so "KEPT_FOR_REFERENCE"
  # refused here while the mac and the Python allowed it, stranding a Windows
  # teacher with a live course whose Deploy button could never work. JSON keys
  # are case-sensitive; the value's own case is spelled out instead.
  if ($referenceText -cmatch '"[^"]*ept_for_reference"\s*:\s*[Tt][Rr][Uu][Ee]') {
    # The code a TEACHER reads, which for a reference course is deliberately
    # not the folder name. Falls back to the folder when there is none.
    $referenceCode = $COURSE_CODE
    if ($referenceText -match '"course_code"\s*:\s*"([^"]*)"') {
      if ($Matches[1]) { $referenceCode = $Matches[1] }
    }
    Write-Host ""
    Write-Host ("{0} {1}" -f $referenceCode, $REFERENCE_COURSE_REFUSAL)
    Write-Host ""
    exit 1
  }
}

# >>> DEPLOY WHILE ITS SECTION DEPLOYS BLOCK >>> - identical in preview.ps1 and
# deploy.ps1. LauncherRulesContractTests checks that the two copies match, and
# windows-app/test_launcher_rules.ps1 runs every contract case against EACH
# copy. Keep the markers. ASCII only: both files are read by Windows
# PowerShell 5.1 without a BOM, so the cross, the dot and the dash are
# written as code points.

# One line on the teacher's activity trail, for a refusal made HERE - a
# launcher typed at a command line has no app to read a marker, and a refusal
# a teacher met there is exactly the one nobody else saw. Same file, same
# stamp, same lock as the app's own writer (ActivityTrail.Append: the named
# mutex Local\PlantoirActivityTrail, an append opened to share), so two
# writers cannot tear a line. Never fails the launcher.
function Write-TrailLine {
    param([string]$What)
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'Plantoir\Logs'
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
        $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture) + ' ' + [char]0x00B7 + ' ' + $What + [Environment]::NewLine
        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($line)
        $mutex = New-Object System.Threading.Mutex($false, 'Local\PlantoirActivityTrail')
        $held = $false
        try {
            try { $held = $mutex.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $held = $true }
            $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
            $stream = New-Object IO.FileStream((Join-Path $dir 'activity.txt'), [IO.FileMode]::Append, [IO.FileAccess]::Write, $share)
            try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        } finally {
            if ($held) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    } catch {}
}

# ---- Who is deploying this section, from the LIVE process table ----
# Two guards ask this, and both read Win32_Process - never a remembered
# process id, a lease file or an outcome record, so nothing left on disk can
# refuse a deploy for ever:
#   * preview.ps1 on a SERVING run (#386 / mac #381,
#     contracts/shared-rules.json -> previewWhileItsSectionDeploys);
#   * deploy.ps1, and preview.ps1 --build-only (#467 / mac #439,
#     contracts/shared-rules.json -> deployWhileItsSectionDeploys).
# What counts, each only as the PROGRAM (Get-LaunchedScriptIndex):
#   * 'later' - a deploy set for later of C/S whose wrapper is running: the
#     script Task Scheduler's run hands powershell.exe, named
#     SafeName(TaskScheduling.NameFor(C, S, folder)) + '.ps1', carrying THIS
#     folder's id (#309), or the folder-less name a task set before #309
#     still runs (counted for every folder: it names none). The app's own
#     `Plantoir.exe --run-scheduled-deploy "<task name>"` line does NOT count
#     on its own: that run waits up to ten minutes for the course BEFORE it
#     writes and starts its wrapper, and counting it would refuse the
#     window's own deploy while the run waits for the window. LauncherRules-
#     ContractTests pins these names against the app's own.
#   * 'another' - deploy.ps1 C S, whose own arguments BEGIN with the course,
#     read whole ("AP CALC" is two words however the caller quoted it; CALC 2
#     is not AP CALC 2), then exactly this section (1 is not 12) - not
#     --reset-token, --logout or --help, which deploy nothing. Its folder is
#     the script's own directory when the path names one; a relative path
#     names none, and a deploy of this very section whose folder cannot be
#     told still counts (the safe side for the deploy).
# 'later' wins when both are seen: a wrapper's own deploy leg is in the table
# beside it. This run and its ancestors never count, so a scheduled run's own
# legs are never refused by its own wrapper, and a folder deploy's own
# rebuild is never refused by the deploy.ps1 that started it. A table that
# cannot be read - the query fails or times out, or its answer does not list
# this run ($PID) - lets the run THROUGH: failing closed would refuse every
# deploy, and every scheduled run's own legs, for as long as it cannot read.
# Known limit: a script typed at an interactive prompt (.\deploy.ps1 ICS4U 2)
# runs INSIDE that prompt's process, whose line names no script, so it is not
# seen; nor is a process started elevated, whose line an ordinary one cannot
# read (documentation/03-launcher-scripts.md).
function Split-CommandLine([string]$Line) {
    $words = New-Object System.Collections.Generic.List[string]
    if (-not $Line) { return ,$words }
    foreach ($m in [regex]::Matches($Line, '"([^"]*)"|(\S+)')) {
        if ($m.Groups[1].Success) { $words.Add($m.Groups[1].Value) } else { $words.Add($m.Groups[2].Value) }
    }
    return ,$words
}

# Which word is the script a process is RUNNING, or -1: the word after -File
# (or -f, -fi, -fil - Windows PowerShell takes any of them), or, for
# powershell.exe and pwsh themselves, the first *.ps1 handed to them as a
# plain word. Nothing after -Command or -EncodedCommand is a program: that
# script is only mentioned, or run by a shell whose own child is the program.
function Get-LaunchedScriptIndex($Words) {
    if ($null -eq $Words -or $Words.Count -lt 2) { return -1 }
    $program = ($Words[0] -split '[\\/]')[-1]
    $isShell = $program -imatch '^(powershell|pwsh)(\.exe)?$'
    for ($i = 1; $i -lt $Words.Count; $i++) {
        $word = [string]$Words[$i]
        if ($word.Length -gt 1 -and ($word.StartsWith('-') -or $word.StartsWith('/'))) {
            $option = $word.Substring(1)
            if ('file'.StartsWith($option, [StringComparison]::OrdinalIgnoreCase)) {
                if ($i + 1 -lt $Words.Count) { return $i + 1 }
                return -1
            }
            if ('command'.StartsWith($option, [StringComparison]::OrdinalIgnoreCase) -or
                'encodedcommand'.StartsWith($option, [StringComparison]::OrdinalIgnoreCase) -or
                $option -ieq 'ec') { return -1 }
            continue
        }
        if ($isShell -and $word -ilike '*.ps1') { return $i }
    }
    return -1
}

# The names a deploy set for later of C/S in THIS folder can carry: the task
# TaskScheduling.NameFor names (with the folder id, #309) and the one
# OldNameFor named (none) - a task set before #309 still runs under it, and
# names no folder, so it counts for every folder. Must stay the app's own
# shape; LauncherRulesContractTests compares them with the app's.
function Get-ScheduledDeployTaskNames([string]$Course, [string]$Section, [string]$FolderId) {
    $old = 'Plantoir deploy ' + $Course.ToUpperInvariant() + ' section ' + $Section
    if ($FolderId) { return @(($old + ' ' + $FolderId), $old) }
    return @($old)
}

# The wrapper each of those tasks runs: TaskScheduling.WrapperScriptPath's
# leaf, through SafeName (letters and digits kept, anything else '-').
function Get-ScheduledDeployScriptNames([string]$Course, [string]$Section, [string]$FolderId) {
    foreach ($name in @(Get-ScheduledDeployTaskNames $Course $Section $FolderId)) {
        (-join ($name.ToCharArray() | ForEach-Object { if ([char]::IsLetterOrDigit($_)) { $_ } else { '-' } })) + '.ps1'
    }
}

# 'later', 'another', or $null (nothing, or a table that cannot be trusted).
# Pure over its arguments, so test_launcher_rules.ps1 can run the cases.
function Get-WhatIsDeployingThisSection {
    param($Snapshot, [string]$Course, [string]$Section, [string]$Here, [string]$FolderId, [uint32]$Self)
    if ($null -eq $Snapshot) { return $null }
    $rows = @($Snapshot)
    if (-not ($rows | Where-Object { [uint32]$_.ProcessId -eq $Self })) { return $null }

    # This run's own ancestors never count.
    $ancestors = New-Object 'System.Collections.Generic.HashSet[uint32]'
    $cursor = $Self
    for ($depth = 0; $depth -lt 64; $depth++) {
        $row = $rows | Where-Object { [uint32]$_.ProcessId -eq $cursor } | Select-Object -First 1
        if (-not $row -or $null -eq $row.ParentProcessId) { break }
        $parent = [uint32]$row.ParentProcessId
        if ($parent -eq 0 -or -not $ancestors.Add($parent)) { break }
        $cursor = $parent
    }

    $courseWords = @(($Course.Trim() -split '\s+') | Where-Object { $_ })
    $scheduledNames = @(Get-ScheduledDeployScriptNames ($courseWords -join ' ') $Section $FolderId)
    $seen = $null
    foreach ($proc in $rows) {
        $processId = [uint32]$proc.ProcessId
        if ($processId -eq $Self -or $ancestors.Contains($processId)) { continue }
        $words = Split-CommandLine ([string]$proc.CommandLine)
        $at = Get-LaunchedScriptIndex $words
        if ($at -lt 0) { continue }
        $script = $words[$at]
        $leaf = ($script -split '[\\/]')[-1]
        if ($scheduledNames -icontains $leaf) { return 'later' }
        if ($leaf -ine 'deploy.ps1') { continue }

        # Its own arguments, each split into words: the app and the wrapper
        # QUOTE a course with a space ("AP CALC"), and one quoted word must
        # read as the two the course is.
        $own = New-Object System.Collections.Generic.List[string]
        for ($k = $at + 1; $k -lt $words.Count; $k++) {
            foreach ($piece in ([string]$words[$k] -split '\s+')) { if ($piece) { $own.Add($piece) } }
        }
        if ($own.Count -lt $courseWords.Count + 1) { continue }
        $same = $true
        for ($w = 0; $w -lt $courseWords.Count; $w++) { if ($own[$w] -ine $courseWords[$w]) { $same = $false; break } }
        if (-not $same -or $own[$courseWords.Count] -cne $Section) { continue }
        $deploysNothing = $false
        foreach ($flag in $own) { if ($flag -in @('--reset-token', '--logout', '--help', '-h')) { $deploysNothing = $true } }
        if ($deploysNothing) { continue }

        if ($script -match '^[A-Za-z]:[\\/]|^[\\/][\\/]') {
            try {
                $folder = Get-PhysicalPath (Split-Path -Parent $script)
                if ($folder -and $Here -and ($folder -ine $Here)) { continue }
            } catch {}
        }
        $seen = 'another'
    }
    return $seen
}

# #386's question: is this section being deployed at all? Everything the
# deploy guard counts, and one thing more: a deploy set for later whose run is
# still WAITING for the course - Plantoir.exe --run-scheduled-deploy "<task>"
# for C/S, before it has started its wrapper. A preview counts that run (mac
# #381's rule: its runner lives for the whole run) because the preview would
# be serving from the folder the run is about to build into; a DEPLOY does
# not, because that run may be waiting for the very deploy it would refuse.
function Test-SectionIsBeingDeployed {
    param($Snapshot, [string]$Course, [string]$Section, [string]$Here, [string]$FolderId, [uint32]$Self)
    if (Get-WhatIsDeployingThisSection -Snapshot $Snapshot -Course $Course -Section $Section -Here $Here -FolderId $FolderId -Self $Self) { return $true }
    if ($null -eq $Snapshot) { return $false }
    $rows = @($Snapshot)
    if (-not ($rows | Where-Object { [uint32]$_.ProcessId -eq $Self })) { return $false }
    $courseWords = @(($Course.Trim() -split '\s+') | Where-Object { $_ })
    $taskNames = @(Get-ScheduledDeployTaskNames ($courseWords -join ' ') $Section $FolderId)
    foreach ($proc in $rows) {
        if ([uint32]$proc.ProcessId -eq $Self) { continue }
        $words = Split-CommandLine ([string]$proc.CommandLine)
        if ($words.Count -lt 1 -or (($words[0] -split '[\\/]')[-1]) -inotmatch '^Plantoir(\.exe)?$') { continue }
        for ($i = 1; $i -lt $words.Count - 1; $i++) {
            if ($words[$i] -ieq '--run-scheduled-deploy' -and ($taskNames -icontains $words[$i + 1])) { return $true }
        }
    }
    return $false
}

# The live table, or $null when it cannot be read. Thirty seconds at most: a
# wedged WMI service must not turn "let it through" into a run that hangs
# with its leases held at six in the morning.
function Get-ProcessTable {
    try {
        return ,@(Get-CimInstance Win32_Process -OperationTimeoutSec 30 -ErrorAction Stop | Select-Object ProcessId, ParentProcessId, CommandLine)
    } catch {
        return $null
    }
}

# ---- A section still being deployed is not deployed again (#467 / mac #439) ----
# Asked by deploy.ps1 (not with --reset-token or --logout, which deploy
# nothing) and by preview.ps1 on a --build-only run only - a serving preview
# has #386's own guard, which counts every deploy - after the arguments are
# checked and before anything is changed. LEG is 'deploy' or 'build'. The
# sentences are contracts/shared-rules.json -> deployWhileItsSectionDeploys.
# sentences.launcher, and the trail lines that entry's launcherLines; both are
# checked word for word by test_launcher_rules.ps1. Exit 1, as #386's.
function Stop-WhileThisSectionDeploys([string]$Course, [string]$Section, [string]$Leg) {
    $who = Get-WhatIsDeployingThisSection -Snapshot (Get-ProcessTable) -Course $Course -Section $Section -Here $WORKDIR_PHYSICAL -FolderId $WORKDIR_ID -Self ([uint32]$PID)
    if (-not $who) { return }
    $cross = [char]::ConvertFromUtf32(0x274C)
    $dot = [char]0x00B7
    $dash = [char]0x2014
    Write-Host ""
    if ($who -eq 'later' -and $Leg -eq 'build') {
        Write-Host ("{0} {1} section {2} is still being deployed by a deploy that was set for later, so it cannot be built until that has finished." -f $cross, $Course, $Section)
    } elseif ($who -eq 'later') {
        Write-Host ("{0} {1} section {2} is still being deployed by a deploy that was set for later, so it cannot be deployed again until that has finished." -f $cross, $Course, $Section)
    } elseif ($Leg -eq 'build') {
        Write-Host ("{0} {1} section {2} is already being deployed, so it cannot be built until that has finished." -f $cross, $Course, $Section)
    } else {
        Write-Host ("{0} {1} section {2} is already being deployed, so it cannot be deployed again until that has finished." -f $cross, $Course, $Section)
    }
    Write-Host "   Nothing was changed."
    Write-Host ""
    if ($who -eq 'later') {
        Write-TrailLine ("{0}/{1} {2} the {3} stopped before it started {4} this section was still being deployed by a deploy that was set for later" -f $Course, $Section, $dot, $Leg, $dash)
    } else {
        Write-TrailLine ("{0}/{1} {2} the {3} stopped before it started {4} this section was already being deployed" -f $Course, $Section, $dot, $Leg, $dash)
    }
    exit 1
}
# <<< DEPLOY WHILE ITS SECTION DEPLOYS BLOCK <<<

# ---------- A section still being deployed is not deployed again (#467) ----------
# After the Open-code question and the reference-course refusal (the order
# deploy.sh asks in), before anything is changed. Not for --reset-token or
# --logout, which deploy nothing; --help has already exited.
if (-not $RESET_TOKEN) { Stop-WhileThisSectionDeploys $COURSE_CODE ([string]$SECTION_NUM) 'deploy' }

# Where a --to-folder value publishes, resolved ONCE against the working
# folder (#304), or $null when it cannot be told. A plain relative name
# ("out site", "Sites\x") is taken from the working folder, as deploy.sh
# takes it. A DRIVE-relative ("C:foo") or ROOT-relative ("\out") path is
# refused: [IO.Path]::IsPathRooted calls both rooted, and GetFullPath then
# resolves them against the PROCESS directory, which is the hole the review
# of bundle 4 found (L1). Fully qualified means a drive and a separator, or
# a UNC path - the test the app's DeployFolderProblem makes.
function Resolve-PublishFolder([string]$Asked, [string]$WorkingFolder) {
  $p = $Asked.Trim()
  if ($p.Length -eq 0) { return $null }
  if ($p -match '^[A-Za-z]:[\\/]' -or $p -match '^[\\/][\\/]') { return [IO.Path]::GetFullPath($p) }
  if ($p -match '^[A-Za-z]:' -or $p -match '^[\\/]') { return $null }
  return [IO.Path]::GetFullPath((Join-Path -Path $WorkingFolder -ChildPath $p))
}

function Test-CarriesLiveReload([string]$root) {
  # Does any page under $root still carry the preview's live-reload client?
  #
  # WHY THIS IS A FUNCTION AND NOT THE OBVIOUS ONE-LINER. Windows PowerShell
  # 5.1's `Select-String -Quiet`, fed a PIPELINE of file objects, emits one
  # result PER FILE rather than one answer overall. A clean site of 314 pages
  # therefore comes back as a 314-element array of $null - and in PowerShell
  # a non-empty array is TRUE whatever is in it. So
  #
  #     if ($files | Select-String -Pattern ... -List -Quiet) { ... }
  #
  # was true whenever the site had TWO OR MORE pages, which is every real
  # site. (Exactly one page is the one case it got right, by accident: a
  # single-element array unwraps to the scalar it holds, which is falsy.)
  # The consequences were both invisible and total: every publish to a folder
  # announced "This site was built by a preview", rebuilt whether or not it
  # needed to, waited the full 30 s for a condition that could never become
  # false, and then refused with "The rebuilt site still carries the
  # preview's live-reload script. Nothing was published." Publishing to a
  # folder could not succeed on Windows, ever. Measured 2026-09-05 by
  # publishing a site whose 314 pages contained no live-reload client at all
  # and watching it be refused three times running.
  #
  # `deploy.sh` is not affected: `grep -rq` returns one exit status for the
  # whole tree, which is the answer this needs. The bug is entirely in the
  # PowerShell port of that check.
  #
  # The fix then was to test for one MatchInfo instead of a Boolean array.
  # Since #272 the function returns ONE scalar from a loop that writes
  # nothing to the pipeline, which keeps the same property: one answer for
  # the whole tree, whatever the page count.
  #
  # WHAT IS LOOKED FOR (#272, from mac #291 and #136): the client's script TAG,
  # then any run of POSIX-space bytes (space, tab, LF, VT, FF, CR - never .NET's
  # Unicode \s), then its first statement - contracts/app-rules.json ->
  # buildFreshness.previewBuild.signature. The bare address matched any page
  # that MENTIONS it (a networking lesson), so a folder publish of such a
  # course refused every time. Quartz writes the tag and the client on
  # DIFFERENT lines, so Select-String (line by line, and case-INsensitive by
  # default) cannot see it: each page is read WHOLE, as bytes, and matched
  # case-sensitively. Bytes are widened one to one (ISO-8859-1), so a byte
  # that is not UTF-8 anywhere before the client changes nothing (case 15).
  # Every *.html page, hidden (dot) folders included (-Force), front page
  # first; a page that cannot be opened is PASSED OVER, as every other reader
  # does - under this script's $ErrorActionPreference = 'Stop' an unguarded
  # read would throw and fail the publish instead.
  if (-not (Test-Path -LiteralPath $root)) { return $false }
  $signature = [regex]::new(
    [regex]::Escape('<script type="application/javascript">') + '[ \t\n\x0B\f\r]*' +
    [regex]::Escape("const socket = new WebSocket('ws://localhost:"),
    [Text.RegularExpressions.RegexOptions]::CultureInvariant)
  $latin1 = [Text.Encoding]::GetEncoding(28591)
  $pages = @()
  $front = Join-Path $root 'index.html'
  if (Test-Path -LiteralPath $front -PathType Leaf) { $pages += $front }
  $pages += @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -clike '*.html' -and $_.FullName -ne $front } |
              ForEach-Object { $_.FullName })
  foreach ($page in $pages) {
    $text = $null
    try { $text = $latin1.GetString([IO.File]::ReadAllBytes($page)) } catch { continue }
    if ($signature.IsMatch($text)) { return $true }
  }
  return $false
}

# ======================
# Preflight checks
# ======================
$COURSE_DIR_HOST  = Normalize-HostPath (Join-Path -Path (Get-Location) -ChildPath ("courses\{0}" -f $COURSE_CODE))
$MERGED_DIR_HOST  = Normalize-HostPath (Join-Path -Path $COURSE_DIR_HOST -ChildPath ".merged_output")
# The published-pages record (#392 / mac #379; contracts/file-formats.json ->
# publishedPagesRecord). The folder branch never enters deploy.py, so it
# records itself, as deploy.sh's record_published_pages does: after the copy
# succeeded, copy .visible-pages.json into
# courses/<CODE>/.publish_state/section<N>.published-pages/<yyyyMMddTHHmmssZ>-folder.json,
# only when its buildId is .build-id's (a list from an earlier build is never
# taken for this site's). Any failure records nothing and publishes anyway,
# because the pages are already out. On Windows both files sit in
# PLANTOIR_BUILD_ROOT\<CODE>\section<N>\, beside public\ — no .merged_output
# level (the trap firstDeployMarkers warns about).
# BEGIN Record-PublishedPages
function Record-PublishedPages([string]$built, [string]$course, [string]$section, [string]$destination) {
  try {
    $listing = Join-Path $built ".visible-pages.json"
    $idFile = Join-Path $built ".build-id"
    if (-not (Test-Path -LiteralPath $listing) -or -not (Test-Path -LiteralPath $idFile)) { return }
    $current = ([System.IO.File]::ReadAllText($idFile)).Trim()
    $text = [System.IO.File]::ReadAllText($listing)
    if ($text -notmatch '"buildId"\s*:\s*"([^"]*)"') { return }
    if ([string]::IsNullOrEmpty($current) -or $Matches[1] -ne $current) { return }
    $folder = Join-Path "courses" (Join-Path $course (Join-Path ".publish_state" ("section{0}.published-pages" -f $section)))
    New-Item -ItemType Directory -Force -Path $folder -ErrorAction Stop | Out-Null
    $name = "{0}-{1}.json" -f ([DateTime]::UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)), $destination
    $temporary = Join-Path $folder (".{0}.{1}.tmp" -f $name, $PID)
    Copy-Item -LiteralPath $listing -Destination $temporary -ErrorAction Stop
    Move-Item -LiteralPath $temporary -Destination (Join-Path $folder $name) -Force -ErrorAction Stop
  } catch {
    # Recording is never worth failing a publish that already happened.
  }
}
# END Record-PublishedPages

$SECTION_DIR_HOST = Normalize-HostPath (Join-Path -Path $MERGED_DIR_HOST -ChildPath ("section{0}" -f $SECTION_NUM))
$PUBLIC_DIR_HOST  = Normalize-HostPath (Join-Path -Path $SECTION_DIR_HOST -ChildPath "public")
if ($NATIVE_RUNTIME) {
  # Native builds land in the app's data folder, not the working folder
  # (teachers keep working folders in OneDrive) - same derivation as
  # Enter-NativeRuntime and toolchain_paths.merged_output_root. The first
  # smoke-test deploy failed exactly here, on the container-era path.
  $MERGED_DIR_HOST  = Normalize-HostPath (Join-Path $env:LOCALAPPDATA ("Plantoir\builds\{0}\{1}" -f $WORKDIR_ID, $COURSE_CODE))
  $SECTION_DIR_HOST = Normalize-HostPath (Join-Path $MERGED_DIR_HOST ("section{0}" -f $SECTION_NUM))
  $PUBLIC_DIR_HOST  = Normalize-HostPath (Join-Path $SECTION_DIR_HOST "public")
}

$HOST_TZ_OFFSET = (Get-Date).ToString('zzz').Replace(':','')
Write-Host ("Host timezone offset: {0}" -f $HOST_TZ_OFFSET)

if (-not (Test-Path -LiteralPath $COURSE_DIR_HOST)) {
  Write-Host "Course folder not found on host:"
  Write-Host " $COURSE_DIR_HOST"
  Write-Host ""
  Write-Host "Make sure you've run the course setup and/or preview steps."
  Write-Host ("Try: .\preview.bat {0} {1}" -f $COURSE_CODE, $SECTION_NUM)
  $coursesRoot = Join-Path -Path (Get-Location) -ChildPath 'courses'
  if (Test-Path $coursesRoot) {
    Write-Host ""
    Write-Host "Available course folders:"
    Get-ChildItem -LiteralPath $coursesRoot -Directory | ForEach-Object { " - $($_.Name)" } | Out-Host
  }
  exit 1
}

if (-not (Test-Path -LiteralPath $SECTION_DIR_HOST)) {
  Write-Host "Section directory not found on host:"
  Write-Host " $SECTION_DIR_HOST"
  Write-Host ""
  Write-Host "You likely need to build the merged output first:"
  Write-Host (" .\preview.bat {0} {1}" -f $COURSE_CODE, $SECTION_NUM)
  if (Test-Path -LiteralPath $MERGED_DIR_HOST) {
    $existing = Get-ChildItem -LiteralPath $MERGED_DIR_HOST -Directory -Filter 'section*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    if ($existing) {
      Write-Host ""
      Write-Host ("Existing merged sections for {0}:" -f $COURSE_CODE)
      $existing | ForEach-Object { " - $_" } | Out-Host
    }
  }
  exit 1
}

$builtFound = $false
for ($i = 0; $i -lt 10; $i++) {
  if ((Test-Path -LiteralPath $PUBLIC_DIR_HOST) -and (Get-ChildItem -LiteralPath $PUBLIC_DIR_HOST -Force | Select-Object -First 1)) {
    $builtFound = $true
    break
  }
  Start-Sleep -Milliseconds 200
}

if (-not $builtFound) {
  Write-Host "Built site not found at:"
  Write-Host " $PUBLIC_DIR_HOST"
  Write-Host ""
  Write-Host " If you have just built, check this section still has its front page."
  Write-Host " A section without one produces no website, so there is nothing to deploy."
  Write-Host ""
  Write-Host "Build first:"
  Write-Host (" .\preview.bat {0} {1} --build-only" -f $COURSE_CODE, $SECTION_NUM)
  exit 1
}

# ======================
# Publish to a local folder
# ======================
# The built site already sits on the host (the working folder is
# bind-mounted), so publishing to a folder is a host-side incremental
# mirror via robocopy — only changed files move, removals propagate.
# Each section lands in its own subfolder so sections never overwrite
# one another. Netlify is not involved.
if ($TO_FOLDER) {
  # Resolved ONCE, against THIS working folder, before anything uses it
  # (#304 / mac #227). The app refuses a partial path outright; a command
  # line can still hand one over, and one-argument GetFullPath (like robocopy,
  # a native program) resolves against the PROCESS directory, which
  # Set-Location does not change - so a relative path could be created in one
  # folder and copied into another. The two-argument GetFullPath does not
  # exist on .NET Framework (PowerShell 5.1), hence the Join-Path first.
  $folderAsked = Resolve-PublishFolder $TO_FOLDER $ScriptDir
  if (-not $folderAsked) {
    Write-Host "That deploy folder is blank or only partly written: a drive with no folder after it, or a folder with no drive."
    Write-Host "   Give the folder's full location, then try again. Nothing was deployed."
    exit 1
  }
  $targetDir = [IO.Path]::Combine($folderAsked.TrimEnd('\','/'), ("section{0}" -f $SECTION_NUM))
  # Not New-Item -Path, which reads [ and ] in a folder name as wildcards.
  $null = [IO.Directory]::CreateDirectory($targetDir)
  # A PREVIEW build must never reach a published site. Serve mode bakes a
  # live-reload client into every page, and on a published site that script
  # makes a student's browser ask permission to access other apps and
  # services on this device. deploy.py already refuses this, but ONLY for
  # Netlify and Cloudflare: this branch publishes host-to-host and never
  # enters the container, so deploy.py never runs. The app's own publish path
  # is protected by BuildFreshness; the command line was not. Mirrors the fix
  # made in deploy.sh on 2026-09-05 — see GUI-IMPROVEMENTS row 392.
  # The whole HTML tree, not just the front page — see the same comment in
  # deploy.sh. Detection that read only `index.html` could not see the one
  # state the wait below exists for.
  $publishedIndex = Join-Path $PUBLIC_DIR_HOST "index.html"
  if (Test-CarriesLiveReload $PUBLIC_DIR_HOST) {
    # Plain words (#296, rule 1): this used to say "bakes in a live-reload
    # script". deploy.sh took this wording (#407) and changed "for
    # publishing" to "before it is deployed", because publishing marks a page
    # for the website and this step is the deploy; taken back here word for
    # word (#438). Three dots rather than deploy.sh's ellipsis character:
    # every line this file prints is ASCII.
    Write-Host "This site was built by a preview, which adds live updating"
    Write-Host "  that students' browsers would ask about. Rebuilding it before it is deployed..."
    # Forward the flag. Without it this rebuild is a SECOND way a scheduled
    # publish can meet a question nobody is there to answer: preview.ps1 asks
    # about a course code ending in a zero, and about a section the
    # configuration does not list. Under the wrapper's -NonInteractive
    # PowerShell an unanswered Read-Host THROWS, and preview.ps1's
    # $ErrorActionPreference = 'Stop' turns that into a bare exit 1 with
    # nothing said — measured, not assumed; see the long note at the top of
    # preview.ps1, which also says why the "takes the default and builds the
    # WRONG course" story belongs to preview.sh and not here.
    #
    # Mirrors deploy.sh, which has forwarded it since 2026-09-09; this side had
    # not, and GitHub issue #124 is where that gap was named.
    $previewExtra = @()
    if ($NON_INTERACTIVE) { $previewExtra += '--non-interactive' }
    & ".\preview.bat" $COURSE_CODE $SECTION_NUM "--build-only" @previewExtra
    if ($LASTEXITCODE -eq 3) {
      # Passed straight through, because 3 means one thing: a question went
      # unanswered. A caller that saw 1 here would tell the teacher their
      # publish failed, when what it needs to say is which question nobody
      # was there to answer.
      Write-Host "Could not rebuild this site before deploying it: it needed an answer."
      exit 3
    }
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Could not rebuild this site before deploying it."
      exit 1
    }
    # Wait for the rebuild to become VISIBLE here before copying. On the mac
    # the lag is the container's bind mount; natively on Windows it is the
    # filesystem settling after a large write, and OneDrive can add to it.
    # Waits on the condition (a front page without the live-reload client),
    # not a guessed interval, and is bounded.
    # The WHOLE TREE, not the front page. Serve mode bakes the client into
    # every page and the mirror is replaced file by file, so a clean front page
    # with stale pages behind it is a real state — and publishing that mixture
    # is worse than publishing the preview wholesale, because the front page
    # looks fine. See the same comment in deploy.sh.
    for ($w = 0; $w -lt 150; $w++) {
      if ((Test-Path -LiteralPath $publishedIndex) -and
          -not (Test-CarriesLiveReload $PUBLIC_DIR_HOST)) { break }
      Start-Sleep -Milliseconds 200
    }
    if (Test-CarriesLiveReload $PUBLIC_DIR_HOST) {
      Write-Host "The rebuilt site still carries the preview's live updating."
      # "Nothing was deployed", as deploy.sh says it (#407, #438).
      Write-Host "  Nothing was deployed, rather than deploying pages students'"
      Write-Host "  browsers would ask about."
      exit 1
    }
    # deploy.sh has had this since the empty-publish bug; this side did not,
    # so after a timeout with no front page the HTML scan found nothing, the
    # loop fell through, and robocopy mirrored an empty directory while
    # reporting success. Found by review on 2026-09-05.
    if (-not (Test-Path -LiteralPath $publishedIndex)) {
      Write-Host "The rebuilt site has not appeared. Nothing was deployed."
      exit 1
    }
  }

  Write-Host ("Deploying {0} section {1} to a folder..." -f $COURSE_CODE, $SECTION_NUM)
  # /MIR mirrors (copies changes, deletes removals); robocopy exit codes
  # below 8 all mean success.
  robocopy $PUBLIC_DIR_HOST $targetDir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) {
    # deploy.sh's own words for the same failure (#304), so the app's one
    # explanation lifts both; the copy's number stays for whoever reads on.
    $copyExit = $LASTEXITCODE
    Write-Host ("{0} Not every page could be copied into the deploy folder, so it is not up to date." -f [char]::ConvertFromUtf32(0x274C))
    Write-Host ("   Folder: {0}" -f $targetDir)
    Write-Host ("   (copy error {0})" -f $copyExit)
    exit 1
  }
  $global:LASTEXITCODE = 0
  Record-PublishedPages $SECTION_DIR_HOST $COURSE_CODE $SECTION_NUM "folder"
  Write-Host "Deployed."
  Write-Host (" Folder: {0}" -f $targetDir)
  Write-Host " Upload that folder to your web host however you prefer (e.g. SFTP)."
  # The app reads this line to offer the folder in Explorer.
  Write-Host ("PUBLISHED_FOLDER={0}" -f $targetDir)
  exit 0
}

# ======================
# Netlify token (Windows Credential Manager + legacy migration)
# ======================
$CredCs = @'
using System;
using System.Runtime.InteropServices;

public static class CredApi {
  [DllImport("advapi32", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr pCredential);

  [DllImport("advapi32", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool CredWrite(ref CREDENTIAL userCredential, uint flags);

  [DllImport("advapi32", SetLastError=true)]
  public static extern void CredFree(IntPtr buffer);

  [DllImport("advapi32", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool CredDelete(string target, int type, int flags);

  public const int CRED_TYPE_GENERIC = 1;
  public const uint CRED_PERSIST_LOCAL_MACHINE = 2;

  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {
    public uint Flags;
    public uint Type;
    public string TargetName;
    public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public uint CredentialBlobSize;
    public IntPtr CredentialBlob;
    public uint Persist;
    public uint AttributeCount;
    public IntPtr Attributes;
    public string TargetAlias;
    public string UserName;
  }

  public static string ReadSecret(string target) {
    IntPtr pcred;
    if (!CredRead(target, CRED_TYPE_GENERIC, 0, out pcred)) return null;
    try {
      CREDENTIAL cred = (CREDENTIAL) Marshal.PtrToStructure(pcred, typeof(CREDENTIAL));
      if (cred.CredentialBlob == IntPtr.Zero || cred.CredentialBlobSize == 0) return null;
      byte[] bytes = new byte[cred.CredentialBlobSize];
      Marshal.Copy(cred.CredentialBlob, bytes, 0, (int)cred.CredentialBlobSize);
      return System.Text.Encoding.UTF8.GetString(bytes);
    } finally {
      CredFree(pcred);
    }
  }

  public static bool WriteSecret(string target, string username, string secret) {
    byte[] bytes = System.Text.Encoding.UTF8.GetBytes(secret ?? "");
    IntPtr blob = Marshal.AllocHGlobal(bytes.Length);
    try {
      Marshal.Copy(bytes, 0, blob, bytes.Length);
      CREDENTIAL cred = new CREDENTIAL();
      cred.Flags = 0;
      cred.Type = CRED_TYPE_GENERIC;
      cred.TargetName = target;
      cred.UserName = username ?? Environment.UserName;
      cred.CredentialBlobSize = (uint)bytes.Length;
      cred.CredentialBlob = blob;
      cred.Persist = CRED_PERSIST_LOCAL_MACHINE;
      return CredWrite(ref cred, 0);
    } finally {
      Marshal.FreeHGlobal(blob);
    }
  }

  public static bool DeleteSecret(string target) {
    return CredDelete(target, CRED_TYPE_GENERIC, 0);
  }
}
'@
Add-Type -TypeDefinition $CredCs -Language CSharp -IgnoreWarnings

function Get-TokenFromCredMan { [CredApi]::ReadSecret($KEY_TARGET) }
function Set-TokenInCredMan([string]$token) {
  $ok = [CredApi]::WriteSecret($KEY_TARGET, $env:USERNAME, $token)
  if (-not $ok) { throw "Failed to write token to Windows Credential Manager." }
}
function Remove-TokenInCredMan { [CredApi]::DeleteSecret($KEY_TARGET) | Out-Null }

function Get-CfTokenFromCredMan { [CredApi]::ReadSecret($CF_KEY_TARGET) }
function Set-CfTokenInCredMan([string]$token) {
  $ok = [CredApi]::WriteSecret($CF_KEY_TARGET, $env:USERNAME, $token)
  if (-not $ok) { throw "Failed to write token to Windows Credential Manager." }
}
function Remove-CfTokenInCredMan { [CredApi]::DeleteSecret($CF_KEY_TARGET) | Out-Null }

function Get-CfAccountFromCredMan { [CredApi]::ReadSecret($CF_ACCT_TARGET) }
function Set-CfAccountInCredMan([string]$id) { [CredApi]::WriteSecret($CF_ACCT_TARGET, $env:USERNAME, $id) | Out-Null }
function Remove-CfAccountInCredMan { [CredApi]::DeleteSecret($CF_ACCT_TARGET) | Out-Null }

# Does Cloudflare still recognise this token at all? Kept separate from the
# account lookup below because the two can disagree: a token can be perfectly
# valid and still list no accounts (see Get-CloudflareAccountId).
function Test-CloudflareToken([string]$token) {
  if (-not $token) { return $false }
  try {
    $r = Invoke-RestMethod -Uri 'https://api.cloudflare.com/client/v4/user/tokens/verify' `
                           -Headers @{ Authorization = "Bearer $token" } `
                           -Method GET -TimeoutSec 20
    return [bool]$r.success
  } catch { return $false }
}

# Best-effort account lookup, so that in the common case a teacher pastes a
# token and nothing else — the account ID is a 32-character hex string buried
# in the dashboard and asking for it loses people.
#
# This is deliberately NOT treated as proof of validity. Tested against a real
# token: /accounts can answer success with an EMPTY list, because listing
# accounts is its own permission and a token scoped only to Pages need not
# carry it. Returns $null to mean "ask the teacher", never "bad token".
function Get-CloudflareAccountId([string]$token) {
  if (-not $token) { return $null }
  try {
    $r = Invoke-RestMethod -Uri 'https://api.cloudflare.com/client/v4/accounts' `
                           -Headers @{ Authorization = "Bearer $token" } `
                           -Method GET -TimeoutSec 20
    if ($r.success) {
      $accounts = @($r.result)
      if ($accounts.Count -ge 1) { return $accounts[0].id }
    }
  } catch {}
  return $null
}

# Only reached when the token cannot name its own account.
function Read-CloudflareAccountId {
@"
One more thing from Cloudflare.

The token you just made is allowed to deploy, but not to look up which
Cloudflare account it belongs to - so the account's ID is needed as well.
This is the only time you will be asked for it.

  1. Open this page:  https://dash.cloudflare.com
  2. Choose "Workers & Pages" from the list on the left.
  3. Find "Account ID" on the right-hand side, and copy it.
     (It is also the long code in the address bar, just after
     dash.cloudflare.com/.)
"@ | Out-Host
  Assert-CanAsk "Paste Cloudflare Account ID" "Add the Account ID in this course's settings in Plantoir, under Deploying."
  $entered = (Read-Host "Paste Cloudflare Account ID").Trim()
  if ($entered -notmatch '^[0-9a-fA-F]{32}$') {
    Write-Host "That does not look like an Account ID (it should be 32 letters and digits)."
    return ''
  }
  return $entered.ToLower()
}

function Test-TokenValid([string]$token) {
  if (-not $token) { return $false }
  try {
    $r = Invoke-WebRequest -Uri 'https://api.netlify.com/api/v1/user' -Headers @{ Authorization = "Bearer $token" } -Method GET -UseBasicParsing -TimeoutSec 20
    return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300)
  } catch { return $false }
}

function Read-LegacyTokenXor {
  if (-not (Test-Path $TOKENS_FILE) -or -not (Test-Path $KEY_FILE)) { return $null }
  try {
    $json = Get-Content -LiteralPath $TOKENS_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
    $obf  = $json.tokens.netlify.obf
    if (-not $obf) { return $null }
    $raw  = [Convert]::FromBase64String($obf)
    $key  = [IO.File]::ReadAllBytes($KEY_FILE)
    $out  = New-Object byte[] ($raw.Length)
    for ($i=0; $i -lt $raw.Length; $i++) { $out[$i] = $raw[$i] -bxor $key[$i % $key.Length] }
    return [Text.Encoding]::UTF8.GetString($out)
  } catch { return $null }
}
function Read-LegacyTokenPlain {
  if (-not (Test-Path $TOKENS_FILE)) { return $null }
  try {
    $txt     = Get-Content -LiteralPath $TOKENS_FILE -Raw -Encoding UTF8
    $pattern = '(?i)"(netlify|netlify_token|NETLIFY_AUTH_TOKEN|token)"\s*:\s*"([^"]+)"'
    $m       = [regex]::Match($txt, $pattern)
    if ($m.Success) { return $m.Groups[2].Value }
  } catch {}
  return $null
}
function Prune-LegacyNetlifyEntry {
  if (-not (Test-Path $TOKENS_FILE)) { return }
  try {
    $json = Get-Content -LiteralPath $TOKENS_FILE -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($json.tokens -and $json.tokens.netlify) {
      $json.tokens.PSObject.Properties.Remove('netlify')
      if ($json.tokens.PSObject.Properties.Count -gt 0) {
        $json | ConvertTo-Json -Depth 20 | Out-File -LiteralPath $TOKENS_FILE -Encoding UTF8
      } else {
        Remove-Item -LiteralPath $TOKENS_FILE -Force
      }
    }
  } catch {}
}

if ($RESET_TOKEN -and $TARGET -eq 'cloudflare') {
  Write-Host "Clearing saved Cloudflare token from Windows Credential Manager..."
  Remove-CfTokenInCredMan
  Remove-CfAccountInCredMan
  Write-Host "Done. Next deploy will ask for a new token."
  exit 0
}

if ($RESET_TOKEN) {
  Write-Host "Clearing saved Netlify token from Windows Credential Manager..."
  Remove-TokenInCredMan
  if (Test-Path $TOKENS_FILE) {
    Write-Host "Removing legacy Netlify entry from: $TOKENS_FILE"
    Prune-LegacyNetlifyEntry
  }
  Write-Host "Done. Next run will prompt to create/paste a new token."
  exit 0
}

$CF_TOKEN   = ''
$CF_ACCOUNT = ''
if ($TARGET -eq 'cloudflare') {
  $CF_TOKEN = Get-CfTokenFromCredMan
  if ($CF_TOKEN -and -not (Test-CloudflareToken $CF_TOKEN)) {
    Write-Host "The saved Cloudflare token no longer works, so it has been cleared."
    Remove-CfTokenInCredMan
    Remove-CfAccountInCredMan
    $CF_TOKEN = ''
  }
  if (-not $CF_TOKEN) {
@"
Connect to Cloudflare.

Cloudflare hosts this section's website for free, and it needs to know that
the deploys are coming from you. It does that with an API token - a long
code that acts like a password made just for this app. Creating one takes
about two minutes, and you will not be asked again: it is saved securely on
this computer.

  1. Open this page:  https://dash.cloudflare.com/profile/api-tokens
     (Sign in if you are asked to.)
  2. Choose "Create Token", then "Create Custom Token".
  3. Name it something you will recognise later, such as "Class websites".
  4. Give it ONE permission, chosen from the three dropdowns:
     Account  ->  Cloudflare Pages  ->  Edit
  5. Under "Account Resources", choose "Include" and then your own account
     by name. A token that names no account cannot deploy anything, and
     what you get back if you skip this does not mention accounts at all.
  6. Under "TTL", set the end date to after the end of your school year -
     next July is a safe choice - or leave it with no end date. An expired
     token stops your deploys working, with nothing to say why.
  7. Choose "Continue to summary", then "Create Token".
  8. Copy the long code Cloudflare shows you - it is only shown once - and
     paste it below. Nothing appears as you paste; that is normal.
"@ | Out-Host
    Assert-CanAsk "Paste Cloudflare token" "Deploy this section once from Plantoir, where you can paste it. It is saved afterwards."
    $pastedSec = Read-Host -AsSecureString "Paste Cloudflare token"
    $plain = $null
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pastedSec)
    try   { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    if (-not (Test-CloudflareToken $plain)) {
      Write-Host "Cloudflare did not accept that token."
      Write-Host "Check that it has the 'Cloudflare Pages - Edit' permission, then try again."
      exit 1
    }
    Set-CfTokenInCredMan $plain
    $CF_TOKEN = $plain
    Write-Host "Saved token to Windows Credential Manager (target: $CF_KEY_TARGET)."
  }

  # Preferred: the token names its own account. Otherwise fall back to what we
  # were told last time, and only then ask. A token can be entirely valid and
  # still list no accounts, so an empty answer here is never treated as a bad
  # token — it just means we have to ask once.
  if ($ACCOUNT_ARG) {
    # The app collected it from the teacher, which beats any guess we can make.
    $CF_ACCOUNT = $ACCOUNT_ARG
    Set-CfAccountInCredMan $CF_ACCOUNT
  }
  if (-not $CF_ACCOUNT) { $CF_ACCOUNT = Get-CloudflareAccountId $CF_TOKEN }
  if (-not $CF_ACCOUNT) { $CF_ACCOUNT = Get-CfAccountFromCredMan }
  if (-not $CF_ACCOUNT) {
    $CF_ACCOUNT = Read-CloudflareAccountId
    if (-not $CF_ACCOUNT) { exit 1 }
    Set-CfAccountInCredMan $CF_ACCOUNT
  }
}

$TOKEN = ''
if ($TARGET -eq 'netlify') {
$TOKEN = Get-TokenFromCredMan
if ($TOKEN -and -not (Test-TokenValid $TOKEN)) {
  Write-Host "The saved Netlify token no longer works, so it has been cleared."
  Remove-TokenInCredMan
  $TOKEN = $null
}
if (-not $TOKEN -and (Test-Path $TOKENS_FILE)) {
  $migrated = $false
  $decoded = Read-LegacyTokenXor
  if ($decoded -and (Test-TokenValid $decoded)) {
    Set-TokenInCredMan $decoded
    $TOKEN = $decoded
    Write-Host "Migrated Netlify token (obfuscated) into Windows Credential Manager."
    Prune-LegacyNetlifyEntry
    $migrated = $true
  }
  if (-not $migrated -and -not $TOKEN) {
    $plain = Read-LegacyTokenPlain
    if ($plain -and (Test-TokenValid $plain)) {
      Set-TokenInCredMan $plain
      $TOKEN = $plain
      Write-Host "Migrated Netlify token into Windows Credential Manager."
      Prune-LegacyNetlifyEntry
    } elseif (-not $plain) {
      Write-Host "Legacy tokens file found, but no Netlify token key detected."
    } else {
      Write-Host "Legacy token value found, but it is invalid."
    }
  }
}

if (-not $TOKEN) {
@"
Connect to Netlify.

Netlify hosts this section's website for free, and it needs to know that the
deploys are coming from you. It does that with an access token - a long
code that acts like a password made just for this app. Creating one takes
about a minute, and you will not be asked again: it is saved securely on
this computer.

  1. Open this page:
     https://app.netlify.com/user/applications#personal-access-tokens
     (Sign in if you are asked to.)
  2. Choose "New access token".
  3. Describe it as something you will recognise later, such as
     "Class websites".
  4. Change the expiry - it starts at 7 days. A token that expires stops
     your deploys working, with nothing on screen to say why, so set a
     date after the end of your school year: next July is a safe choice.
     Choose "No expiration" instead if it is offered.
  5. Choose "Generate token", then copy the long code Netlify shows you -
     it is only shown once.
  6. Paste it below. Nothing appears as you paste; that is normal.
"@ | Out-Host
  Assert-CanAsk "Paste Netlify token" "Deploy this section once from Plantoir, where you can paste it. It is saved afterwards."
  $pastedSec = Read-Host -AsSecureString "Paste Netlify token"
  $plain = $null
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pastedSec)
  try   { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
  if (-not (Test-TokenValid $plain)) {
    Write-Host "Token invalid (Netlify rejected it). Please try again."
    exit 1
  }
  Set-TokenInCredMan $plain
  $TOKEN = $plain
  Write-Host "Saved token to Windows Credential Manager (target: $KEY_TARGET)."
}
}  # end: Netlify-only token discovery

# ======================
# Native run (no container)
# ======================
if ($NATIVE_RUNTIME) {
  $py = Enter-NativeRuntime
  $env:HOST_TZ_OFFSET = $HOST_TZ_OFFSET
  Write-Host ("Deploying {0} S{1} from this PC ..." -f $COURSE_CODE, $SECTION_NUM)
  $deployArgs = @('--host-os','windows')
  if ($TARGET -eq 'cloudflare') { $deployArgs += @('--target','cloudflare') }
  $deployArgs += @('--course', $COURSE_CODE, '--section', $SECTION_NUM)
  if ($DIAGNOSE)  { $deployArgs += $DIAGNOSE }
  # PARSING the flag is not enough - it has to reach the Python child, which is
  # where the site-name question lives. A launcher that took the flag and never
  # forwarded it would leave a green test suite and an unchanged 45-minute hang.
  if ($NON_INTERACTIVE) { $deployArgs += '--non-interactive' }
  if ($TEAM_SLUG) { $deployArgs += @('--team', $TEAM_SLUG) }
  # The token rides the child's environment, never a command line: process
  # environments are not persisted anywhere, and wrangler itself reads
  # CLOUDFLARE_API_TOKEN this way.
  if ($TARGET -eq 'cloudflare') {
    $env:CLOUDFLARE_API_TOKEN = $CF_TOKEN
    if ($CF_ACCOUNT) { $env:CLOUDFLARE_ACCOUNT_ID = $CF_ACCOUNT }
  } else {
    $env:NETLIFY_AUTH_TOKEN = $TOKEN
  }
  & $py -u (Join-Path $env:PLANTOIR_SCRIPTS_DIR 'deploy.py') @deployArgs
  $nativeExit = $LASTEXITCODE
  $env:NETLIFY_AUTH_TOKEN = $null
  $env:CLOUDFLARE_API_TOKEN = $null
  $env:CLOUDFLARE_ACCOUNT_ID = $null
  exit $nativeExit
}

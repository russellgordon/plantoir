#requires -Version 5.1
$ErrorActionPreference = 'Stop'
# ---- Determine host OS for help text ---------------------------------
function Get-HostOS {
    try { if ($IsWindows) { return 'windows' } } catch {}
    try { if ([System.Environment]::OSVersion.Platform.ToString() -eq 'Win32NT') { return 'windows' } } catch {}
    try {
        if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) { return 'windows' }
        if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX))     { return 'mac' }
        if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Linux))   { return 'linux' }
    } catch {}
    if ($env:OS -eq 'Windows_NT') { return 'windows' }
    try {
        $u = (uname -s 2>$null)
        if ($u -match 'Darwin') { return 'mac' }
        if ($u -match 'Linux')  { return 'linux' }
    } catch {}
    return 'unknown'
}
$__hostOS = Get-HostOS
if ($__hostOS -eq 'windows') {
    $SELF_CMD = '.\preview.bat'
} else {
    $SELF_CMD = './preview.sh'
}
# Cross-script command hints for help text
if ($__hostOS -eq 'windows') {
    $SETUP_CMD   = '.\setup.bat'
    $PREVIEW_CMD = '.\preview.bat'
    $DEPLOY_CMD  = '.\deploy.bat'
} else {
    $SETUP_CMD   = './setup.sh'
    $PREVIEW_CMD = './preview.sh'
    $DEPLOY_CMD  = './deploy.sh'
}

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# ======================
# preview.ps1 — Windows equivalent of preview.sh
# ======================

# ---- Positional args ----
if ($args.Count -lt 2 -or ($args[0] -eq '--help') -or ($args[0] -eq '-h')) {
    Write-Host ""
    Write-Host "USAGE:"
    Write-Host " $SELF_CMD <COURSE_CODE> <SECTION_NUMBER> [options]"
    Write-Host ""
    Write-Host "Required:"
    Write-Host "  <COURSE_CODE>     e.g., ICS3U"
    Write-Host "  <SECTION_NUMBER>  e.g., 1"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --include-social-media-previews   Enable Quartz CustomOgImages emitter"
    Write-Host "  --force-npm-install               Force npm install even if deps present"
    Write-Host "  --full-rebuild                    Clear entire output folder and re-copy scaffold"
    Write-Host "  --build-only                      Build static site only (no local preview server)"
    Write-Host "  --non-interactive                 Refuse rather than ask, for a build nobody is watching"
    Write-Host "  --stop                            Stop this section's preview processes (build or server) and exit"
    Write-Host "  --port N                          Serve the preview on port N (default 8081; 8081-8084 available)"
    Write-Host "  --help, -h                        Show this help and exit"
    Write-Host ""
    Write-Host "Output location:"
    Write-Host "  courses/<COURSE>/.merged_output/section<SECTION>"
    exit 1
}

$COURSE  = $args[0].ToUpper()

# A course code may not begin with a dot, and the refusal is here rather than
# in a comment claiming it cannot happen. Plantoir builds a reference course
# under a HIDDEN folder inside courses/ and renames it into place as the last
# act; handed that hidden name, this script used to treat it as an ordinary
# course, and during the copy there is no marker yet to refuse it. The app can
# never pass such a name, but a person or another program can type one.
if ($COURSE -like '.*') {
    Write-Host ""
    Write-Host "A course code cannot begin with a dot."
    Write-Host "   Choose one of your courses - the codes in Plantoir's sidebar."
    Write-Host ""
    exit 1
}
$SECTION = $args[1]
if (-not ($SECTION -as [int])) {
    Write-Host "SECTION_NUMBER must be an integer. Got: $SECTION"
    exit 1
}

# ---- Shift positional args and parse flags ----
$Flags = @(); if ($args.Count -gt 2) { $Flags = @($args | Select-Object -Skip 2) }
$INCLUDE_SOCIAL    = $false
$FORCE_NPM_INSTALL = $false
$FULL_REBUILD      = $false
$BUILD_ONLY        = $false
$STOP_MODE         = $false
$PREVIEW_PORT      = 8081
$OVERRIDE_IMAGE    = $null
# Nobody is at the computer. Every question this script asks becomes a refusal
# that names the question and exits 3, matching deploy.ps1 and deploy.py's
# NEEDS_AN_ANSWER.
#
# This script publishes nothing, so it is easy to think it does not need the
# flag. It does: a SCHEDULED publish builds before it publishes, and the
# wrapper Task Scheduler runs calls `preview.ps1 <course> <section>
# --build-only` first, so both questions below are put to nobody at half six in
# the morning.
#
# WHAT ACTUALLY HAPPENS THEN, measured on this machine (PowerShell 5.1.26100,
# script stdin at end of input) rather than assumed — and it is NOT what
# preview.sh does, so do not copy that file's reasoning across:
#
#   powershell -File x.ps1 < NUL          Read-Host returns $null, not "".
#   (what preview.bat starts)             ($ans -eq '') is FALSE, so the [Y/n]
#                                         default is NOT taken and the code is
#                                         kept as typed. The script carries on.
#
#   powershell -NonInteractive -File      Read-Host THROWS
#   (the scheduled wrapper's build leg)   PSInvalidOperationException, and
#                                         $ErrorActionPreference = 'Stop' at the
#                                         top of this file kills the script.
#                                         Exit 1, no build, nothing said.
#
# The second is the one that matters, and it is the whole justification: a
# scheduled publish dies at a question, mid-sentence, and the teacher's site is
# simply not updated in the morning with nothing anywhere saying why. The flag
# turns that into exit 3 and a sentence naming the question, which the wrapper
# records and the app shows.
#
# (The "takes the DEFAULT and builds a DIFFERENT course" failure is real, but
# it belongs to preview.sh: that script has no `set -e` and `${_ans:-Y}` really
# does default. It is written down in app-rules.json under nonInteractive,
# where it is true of the launcher it describes.)
$NON_INTERACTIVE   = $false

if ($Flags) {
    $i = 0
    while ($i -lt $Flags.Count) {
        switch ($Flags[$i]) {
            '--include-social-media-previews' { $INCLUDE_SOCIAL = $true; $i++; continue }
            '--force-npm-install'             { $FORCE_NPM_INSTALL = $true; $i++; continue }
            '--full-rebuild'                  { $FULL_REBUILD = $true; $i++; continue }
            '--build-only'                    { $BUILD_ONLY = $true; $i++; continue }
            '--non-interactive'               { $NON_INTERACTIVE = $true; $i++; continue }
            '--stop'                          { $STOP_MODE = $true; $i++; continue }
            '--port'                          {
                if ($i + 1 -ge $Flags.Count) { Write-Host "--port requires a value"; exit 1 }
                $PREVIEW_PORT = [int]$Flags[$i + 1]
                if ($PREVIEW_PORT -lt 8081 -or $PREVIEW_PORT -gt 8084) { Write-Host "--port must be between 8081 and 8084."; exit 1 }
                $i += 2; continue
            }
            '--image'                         {
                if ($i + 1 -ge $Flags.Count) { Write-Host "--image requires a value"; exit 1 }
                $OVERRIDE_IMAGE = $Flags[$i + 1]
                $i += 2; continue
            }
            default {
                Write-Host "Unknown option: $($Flags[$i])"
                exit 1
            }
        }
    }
}

# Called immediately before every question this script asks, and only ever on
# the line directly above the Read-Host — a guard further away is one somebody
# moves code past, and a test pins the placement.
#
# NO PRE-SCAN HERE, and that is the one difference from preview.sh worth
# knowing. That script asks its course-code question BEFORE its flag parser
# runs, so it has to look for --non-interactive twice; this one parses every
# flag above, before asking anything, exactly as deploy.ps1 does.
function Assert-CanAsk([string]$question, [string]$whatToDo) {
    if (-not $NON_INTERACTIVE) { return }
    Write-Host ""
    Write-Host "This build was set to happen on its own, so nobody is here to answer:"
    Write-Host ("   {0}" -f $question)
    Write-Host (" {0}" -f $whatToDo)
    Write-Host " Nothing was built."
    exit 3
}

# ---- Guardrail: course codes ending with zero vs letter O ----
if ($COURSE -match '^[A-Z]{3}[0-9]0$') {
    $SUGGESTED = $COURSE.Substring(0, $COURSE.Length - 1) + 'O'
    Write-Host ""
    Write-Host "It looks like you entered '$COURSE' (ends with zero)."
    Write-Host "Ontario 'Open' level course codes end with the LETTER 'O' (oh)."
    if ((Test-Path -LiteralPath ("courses/{0}/course_config.json" -f $SUGGESTED)) -and -not (Test-Path -LiteralPath ("courses/{0}/course_config.json" -f $COURSE))) {
        Write-Host "I see setup data for '$SUGGESTED' on disk."
    }
    Assert-CanAsk ("Fix course code to '{0}'? [Y/n]" -f $SUGGESTED) "Preview this section once from Plantoir, where you can answer it."
    $ans = Read-Host ("Fix course code to '{0}'? [Y/n]" -f $SUGGESTED)
    if (($ans -eq '') -or ($ans -match '^(?i:y)$')) {
        $COURSE = $SUGGESTED
        Write-Host "Using corrected course code: $COURSE"
    } else {
        Write-Host "Continuing with: $COURSE"
    }
    Write-Host ""
}

# ---- Paths ----
# Ensure we run from script directory
if ($PSScriptRoot) {
    Set-Location -LiteralPath $PSScriptRoot
} else {
    Set-Location -LiteralPath (Split-Path -Path $MyInvocation.MyCommand.Path -Parent)
}
$CoursesRoot = Join-Path (Get-Location) 'courses'
if (-not (Test-Path -LiteralPath $CoursesRoot)) {
    New-Item -ItemType Directory -Path $CoursesRoot -Force | Out-Null
}
$HOST_COURSES = (Resolve-Path -LiteralPath $CoursesRoot).Path

function Normalize-HostPath([string]$p) {
    if (-not $p) { return $p }
    try { (Resolve-Path -LiteralPath $p).Path.TrimEnd('\','/') } catch { $p.TrimEnd('\','/') }
}


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


# ---- Container handling (mount-aware) ----
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

# ---- The shared rule: which processes belong to a section's preview ----
# Defined at script scope rather than inside the stop branch, so that
# windows-app/test_stop_preview.ps1 can run the contract's own cases
# against these exact functions. A matcher nobody can run against the
# cases is a matcher that drifts, which is the whole reason the rule was
# written down.
#
# WHICH processes belong to a section is a SHARED rule, in
# contracts/shared-rules.json -> stopPreview, implemented for the
# container side in scripts/stop_preview.py. It is implemented a second
# time here because `--stop` must never START anything, and reaching the
# Python copy would mean depending on the bundled interpreter at the
# moment a teacher is closing a window. What keeps the two from drifting
# is not that they share source - they cannot - but that they answer the
# SAME 23 cases. See documentation/03-launcher-scripts.md for the --match-stdin decision.
#
#   * three kinds of evidence, any one of which is enough - the process
#     sits in the section's build folder (never visible here:
#     Win32_Process has no working directory), its command line NAMES
#     that folder, or it is build_site.py with this course and this
#     section on its command line;
#   * plus every descendant of a match, because a child spawned with a
#     RELATIVE path (npx does) carries no evidence of its own;
#   * and every comparison ends at a BOUNDARY, never a bare substring.
#
# That last clause was not true here until 2026-09-05, and the bug it
# left is the reason the rule got written down: `...\section1` is a
# prefix of `...\section10`, and `--section=1` is a prefix of
# `--section=10`, so stopping section 1 also stopped section 10 - by
# both routes at once. It needs a course with ten or more sections,
# which nothing refuses.

# A path is NAMED by a command line only when what follows it is a
# boundary: another path segment, a quote, whitespace, or the end of
# the line. Allowing the end is still safe against the section1 /
# section10 trap, because what follows `section1` in `section10` is
# `0`, which is not a boundary.
#
# Separators are normalised because the contract says both count on both
# platforms: a native Windows run passes POSIX spellings around in
# places, and the two are the same folder. Without this, a command line
# written with forward slashes silently failed to match a needle built
# with Join-Path - measured 2026-09-05 against the contract's own cases.
function Test-NamesPath {
    param([string]$Line, [string]$PathToFind)
    if (-not $Line -or -not $PathToFind) { return $false }
    $haystack = $Line.Replace('/', '\')
    $needle = $PathToFind.Replace('/', '\').TrimEnd('\')
    if (-not $needle) { return $false }
    $boundaries = @('\', ' ', "`t", '"', "'")
    $index = $haystack.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase)
    while ($index -ge 0) {
        $after = $index + $needle.Length
        if ($after -ge $haystack.Length -or $boundaries -contains [string]$haystack[$after]) {
            return $true
        }
        $index = $haystack.IndexOf($needle, $index + 1, [StringComparison]::OrdinalIgnoreCase)
    }
    return $false
}

# `--name=value` or `--name value`, read as an ARGUMENT. A substring
# test cannot tell `--section=1` from `--section=10`. Splitting on
# whitespace is safe for these two flags: a course code and a section
# number never contain a space, whatever the path beside them does.
function Test-ArgumentValue {
    param([string]$Line, [string]$Name, [string]$Value)
    if (-not $Line) { return $false }
    $tokens = @($Line -split '\s+')
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i]
        if ($token.StartsWith("--$Name=", [StringComparison]::OrdinalIgnoreCase)) {
            return ($token.Substring($Name.Length + 3) -ieq $Value)
        }
        if (($token -ieq "--$Name") -and (($i + 1) -lt $tokens.Count)) {
            return ($tokens[$i + 1] -ieq $Value)
        }
    }
    return $false
}

# A preview SERVER rather than a build. `--serve` is what the launcher
# adds to the Quartz CLI for a preview and never adds for a build, so it
# is the one honest separator between the two. A whole token, never a
# substring.
function Test-IsServing {
    param([string]$Line)
    if (-not $Line) { return $false }
    foreach ($token in ($Line -split '\s+')) { if ($token -ceq '--serve') { return $true } }
    return $false
}

# The rule itself, over a whole SNAPSHOT: the last part of it is not a
# property of any one process, since a child spawned by a relative path
# carries no evidence at all and is reachable only through its parent.
#
# $Snapshot items need ProcessId, ParentProcessId and CommandLine - which
# is what Get-CimInstance Win32_Process gives, and what the contract's
# cases are shaped into by the test runner. No filter on process NAME:
# the shared rule has none, and the `node.exe`/`python.exe` narrowing
# this had until 2026-09-05 would have refused most of the contract's
# own cases (`python3`, `npm`, `esbuild`, `sh`), as well as a cmd.exe
# running npm.cmd with the section's folder on its command line.
function Get-SectionProcessesToStop {
    param(
        [object[]]$Snapshot,
        [string[]]$Directories,
        [string]$Course,
        [string]$Section,
        [ValidateSet('everything', 'servingOnly')][string]$Mode = 'everything',
        [uint32[]]$Exclude = @()
    )
    $excluded = New-Object System.Collections.Generic.HashSet[uint32]
    foreach ($pid_ in $Exclude) { $null = $excluded.Add([uint32]$pid_) }
    $matched = New-Object System.Collections.Generic.HashSet[uint32]

    foreach ($proc in $Snapshot) {
        $processId = [uint32]$proc.ProcessId
        # pid 0 and 1 are never ours; the init process especially.
        if ($processId -le 1 -or $excluded.Contains($processId)) { continue }
        $line = [string]$proc.CommandLine
        $namesDirectory = $false
        foreach ($directory in $Directories) {
            if (Test-NamesPath $line $directory) { $namesDirectory = $true; break }
        }
        if ($Mode -eq 'servingOnly') {
            # Serving only: the directory must be NAMED and the process
            # must be a server. Never the driver - a build for publishing
            # must not stop a build, because the build it is protecting
            # is itself a build of this section.
            if ($namesDirectory -and (Test-IsServing $line)) { $null = $matched.Add($processId) }
            continue
        }
        $isDriver = ($line -and $line.ToLowerInvariant().Contains('build_site.py') -and
                     (Test-ArgumentValue $line 'course' $Course) -and
                     (Test-ArgumentValue $line 'section' $Section))
        if ($namesDirectory -or $isDriver) { $null = $matched.Add($processId) }
    }

    # Descendants: repeat until no new child turns up (the chain is
    # driver -> npm -> node -> esbuild, so one pass is not enough).
    do {
        $grew = $false
        foreach ($proc in $Snapshot) {
            $processId = [uint32]$proc.ProcessId
            if ($processId -le 1 -or $excluded.Contains($processId)) { continue }
            if ($matched.Contains($processId)) { continue }
            $parent = $proc.ParentProcessId
            if ($null -ne $parent -and $matched.Contains([uint32]$parent)) {
                $null = $matched.Add($processId)
                $grew = $true
            }
        }
    } while ($grew)

    # Snapshot order, so a caller's output and a test's expectation can
    # be compared directly.
    $ordered = @()
    foreach ($proc in $Snapshot) {
        if ($matched.Contains([uint32]$proc.ProcessId)) { $ordered += [uint32]$proc.ProcessId }
    }
    return $ordered
}

# ---- Ports and the trail ---------------------------------------------

# Every TCP port listening on this PC, read ONCE. Get-NetTCPConnection lists
# every owner's listeners, SYSTEM services included (measured for #319 - see
# documentation/03-launcher-scripts.md). A listing that cannot be read counts
# as empty: build_site.py's own bind re-probe still refuses a taken port.
function Get-ListeningPorts {
    $ports = New-Object 'System.Collections.Generic.HashSet[int]'
    try {
        foreach ($row in @(Get-NetTCPConnection -State Listen -ErrorAction Stop)) {
            $null = $ports.Add([int]$row.LocalPort)
        }
    } catch {}
    return ,$ports
}

# The first block from -From whose site port and websocket (+1000) are both
# free, walking hostBlockCount (40) steps of hostBlockStep (10). $null when
# every one is taken. Kept a pure function of its arguments so
# windows-app\test_launcher_rules.ps1 can run the contract's cases on it.
function Find-FreePreviewPort {
    param([int]$From, $Listening, [int]$Count = 40, [int]$Step = 10, [int]$WebsocketOffset = 1000)
    for ($i = 0; $i -lt $Count; $i++) {
        $candidate = $From + ($i * $Step)
        if (-not $Listening.Contains($candidate) -and -not $Listening.Contains($candidate + $WebsocketOffset)) {
            return $candidate
        }
    }
    return $null
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

# ---- Stop mode -------------------------------------------------------
# .\preview.ps1 CODE N --stop : kill this section's preview processes.
# Ending the host-side script leaves the build or server running; this
# reclaims those resources. It must never start anything - no engine
# setup, no image build, no container creation.
if ($NATIVE_RUNTIME -and $STOP_MODE) {
    $buildRoot = Join-Path $env:LOCALAPPDATA ('Plantoir\builds\' + $WORKDIR_ID)
    $sectionNeedle = Join-Path $buildRoot ('work\' + $COURSE + '\section' + $SECTION)
    Write-Host "Stopping preview processes for $COURSE section $SECTION ..."
    $snapshot = @(Get-CimInstance Win32_Process)
    $toStop = Get-SectionProcessesToStop -Snapshot $snapshot -Directories @($sectionNeedle) `
                                         -Course $COURSE -Section $SECTION -Mode 'everything' `
                                         -Exclude @([uint32]$PID)
    $stopped = 0
    foreach ($processId in $toStop) {
        try { Stop-Process -Id $processId -Force -ErrorAction Stop; $stopped++ } catch {}
    }
    # The app reads this line and puts the number on the teacher's
    # activity trail - see ReclaimedProcesses.Count. Changing the
    # wording means changing that too.
    Write-Host "Stopped $stopped process(es)."
    exit 0
}





# ---- Refuse while this section is being deployed (#386) ----
# Serving runs only, after the arguments are checked and before anything is
# changed. The cross is written as a code point: this file is read by
# Windows PowerShell 5.1 without a BOM, so only ASCII may appear in strings.
if (-not $BUILD_ONLY) {
    if (Test-SectionIsBeingDeployed -Snapshot (Get-ProcessTable) -Course $COURSE -Section ([string]$SECTION) -Here $WORKDIR_PHYSICAL -FolderId $WORKDIR_ID -Self ([uint32]$PID)) {
        $cross = [char]::ConvertFromUtf32(0x274C)
        Write-Host ("{0} {1} section {2} is being deployed right now, so it cannot be previewed until that has finished." -f $cross, $COURSE, $SECTION)
        Write-Host "   Nothing was changed."
        Write-TrailLine ("{0}/{1} {2} the preview stopped before building {3} this section was being deployed" -f $COURSE, $SECTION, [char]0x00B7, [char]0x2014)
        exit 1
    }
}

# ---- Refuse a build while this section is being deployed (#467 / mac #439) ----
# A --build-only run is the build leg of the window's Deploy, of an
# assistant's deploy and of a scheduled run - and the assistant's "rebuild
# the preview" - and it rebuilds the very folder a deploy of this section is
# uploading from. --stop never builds, so it is not asked.
if ($BUILD_ONLY -and -not $STOP_MODE) {
    Stop-WhileThisSectionDeploys $COURSE ([string]$SECTION) 'build'
}

# ---- Validate SECTION against course_config.json ----
Write-Host "Checking allowed timetable sections for $COURSE ..."

# Read course_config.json from host (bind-mounted into container), avoids quoting issues
$configPath = Join-Path (Join-Path $CoursesRoot $COURSE) 'course_config.json'
$allowed = ''
if (Test-Path -LiteralPath $configPath) {
    try {
        $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $secs = $cfg.section_numbers
        if ($secs -and $secs.Count -gt 0) {
            $allowed = ($secs | ForEach-Object { [int]$_ }) -join ','
        } else {
            $n = 1
            if ($cfg.num_sections) { $n = [int]$cfg.num_sections }
            $allowed = (1..$n) -join ','
        }
    } catch {
        $allowed = ''
    }
} else {
    Write-Host "No course_config.json found at $configPath"
}

$allowed = ($allowed -replace '\r','').Trim()
if ($allowed) {
    Write-Host "Allowed sections: $allowed"
    $list = $allowed.Split(',') | ForEach-Object { $_.Trim() }
    if ($list -notcontains ($SECTION.ToString())) {
        Write-Host "WARNING: Section $SECTION is not listed in course_config.json for $COURSE."
        # A question preview.sh does not have, so it is not in the shared
        # contract's refusal list — see the `mac` issue opened alongside this
        # change. It matters here for the same reason the guard above does: a
        # scheduled publish builds first, and this one's default is "no", so an
        # unattended build of a section that is not listed would simply exit 1
        # saying "Cancelled." with nobody to read it.
        Assert-CanAsk "Continue anyway? [y/N]" "Add this section to the course in Plantoir, or preview it once yourself to answer this."
        $c = Read-Host "Continue anyway? [y/N]"
        if ($c -notmatch '^(?i:y)$') { Write-Host "Cancelled."; exit 1 }
    }
} else {
    Write-Host "Could not determine allowed sections from course_config.json; proceeding."
}

# ---- Announce output path ----
$OUTPUT_PATH = "courses/{0}/.merged_output/section{1}" -f $COURSE, $SECTION
if ($NATIVE_RUNTIME) {
    # The real location: native builds live in the app's data folder, out of
    # OneDrive's way, and the printed path must not claim otherwise.
    $OUTPUT_PATH = Join-Path $env:LOCALAPPDATA ("Plantoir\builds\{0}\{1}\section{2}" -f $WORKDIR_ID, $COURSE, $SECTION)
}
Write-Host ("Output will be written to: {0}" -f $OUTPUT_PATH)

# ---- Map flags to build_site.py args ----
$argList = @("--course=$COURSE","--section=$SECTION","--host-os","windows")
if ($INCLUDE_SOCIAL)    { $argList += "--include-social-media-previews" }
if ($FORCE_NPM_INSTALL) { $argList += "--force-npm-install" }
if ($FULL_REBUILD)      { $argList += "--full-rebuild" }
if ($BUILD_ONLY)        { $argList += "--build-only" }
$argList += "--port=$PREVIEW_PORT"

# ---- Announce the reachable address ----
# The container port maps to this folder's probed host block, so the
# address is resolved from the container rather than assumed. The exact
# phrase below is what the app watches for.
$HOST_PREVIEW_PORT = $null
# Probe a free site+websocket pair, walking 10-apart blocks from the port
# asked for - FORTY of them, as the mac launchers and build_site.py's own
# first_free_preview_port do (contracts/app-rules.json -> previewPorts:
# hostBlockCount, hostBlockStep; GitHub #286 / mac #280). The native path
# binds ONE pair, not a published block of four, so a block here is the site
# port and its websocket (+1000). build_site.py re-probes and re-announces
# moments before the bind - this early answer only feeds the pre-build
# announcement below. The listening ports are read ONCE for all forty blocks.
if (-not $BUILD_ONLY) {
    $listening = Get-ListeningPorts
    $HOST_PREVIEW_PORT = Find-FreePreviewPort -From $PREVIEW_PORT -Listening $listening
    if (-not $HOST_PREVIEW_PORT) {
        # previewPorts.whenNoBlockIsFree.sentence, word for word with its
        # {machine} said "PC" (specialNames.platformWording.machine, #438),
        # and its exit code.
        Write-Host "Every address Plantoir can use for a preview is taken."
        Write-Host "Close Plantoir's windows for your other working folders, or restart this PC, then try again."
        Write-TrailLine ("{0}/{1} {2} stopped before starting {3} every address Plantoir can use for a preview was taken" -f $COURSE, $SECTION, [char]0x00B7, [char]0x2014)
        exit 1
    }
    $argList = @($argList | Where-Object { $_ -notlike '--port=*' }) + "--port=$HOST_PREVIEW_PORT"
}
if (-not $HOST_PREVIEW_PORT) { $HOST_PREVIEW_PORT = $PREVIEW_PORT }
if (-not $BUILD_ONLY) {
    Write-Host ("Preview will be available at: http://localhost:{0}/" -f $HOST_PREVIEW_PORT)
}

# ---- Run the build on this PC ----
$py = Enter-NativeRuntime
$env:HOST_TZ_OFFSET = (Get-Date).ToString('zzz').Replace(':','')
Write-Host "Running the website builder on this PC ..."
& $py -u (Join-Path $env:PLANTOIR_SCRIPTS_DIR 'build_site.py') @argList
exit $LASTEXITCODE

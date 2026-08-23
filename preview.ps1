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
    Write-Host "  --stop                            Stop this section's preview processes (build or server) and exit"
    Write-Host "  --port N                          Serve the preview on port N (default 8081; 8081-8084 available)"
    Write-Host "  --help, -h                        Show this help and exit"
    Write-Host ""
    Write-Host "Output location:"
    Write-Host "  courses/<COURSE>/.merged_output/section<SECTION>"
    exit 1
}

$COURSE  = $args[0].ToUpper()
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

if ($Flags) {
    $i = 0
    while ($i -lt $Flags.Count) {
        switch ($Flags[$i]) {
            '--include-social-media-previews' { $INCLUDE_SOCIAL = $true; $i++; continue }
            '--force-npm-install'             { $FORCE_NPM_INSTALL = $true; $i++; continue }
            '--full-rebuild'                  { $FULL_REBUILD = $true; $i++; continue }
            '--build-only'                    { $BUILD_ONLY = $true; $i++; continue }
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

# ---- Guardrail: course codes ending with zero vs letter O ----
if ($COURSE -match '^[A-Z]{3}[0-9]0$') {
    $SUGGESTED = $COURSE.Substring(0, $COURSE.Length - 1) + 'O'
    Write-Host ""
    Write-Host "It looks like you entered '$COURSE' (ends with zero)."
    Write-Host "Ontario 'Open' level course codes end with the LETTER 'O' (oh)."
    if ((Test-Path -LiteralPath ("courses/{0}/course_config.json" -f $SUGGESTED)) -and -not (Test-Path -LiteralPath ("courses/{0}/course_config.json" -f $COURSE))) {
        Write-Host "I see setup data for '$SUGGESTED' on disk."
    }
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

# ---- Stop mode -------------------------------------------------------
# .\preview.ps1 CODE N --stop : kill this section's preview processes
# INSIDE the container. Ending the host-side script leaves the
# container-side build or server running; this reclaims those
# resources. It must never start anything — no engine setup, no image
# build, no container creation. Processes are found by WORKING
# DIRECTORY, not port, so builds are caught as well as servers and
# other sections' processes can never be touched (parity: preview.sh).
if ($NATIVE_RUNTIME -and $STOP_MODE) {
    # Section processes are recognisable without /proc: the python build
    # carries --course/--section on its command line, and the serving node's
    # carries the section's work dir when launched with an absolute path.
    # What that misses is a child spawned with a RELATIVE path (npx does),
    # so every match's descendants go too, walked through the same process
    # snapshot's parent links.
    $buildRoot = Join-Path $env:LOCALAPPDATA ('Plantoir\builds\' + $WORKDIR_ID)
    $sectionNeedle = (Join-Path $buildRoot ('work\' + $COURSE + '\section' + $SECTION)).ToLowerInvariant()
    Write-Host "Stopping preview processes for $COURSE section $SECTION ..."
    $snapshot = @(Get-CimInstance Win32_Process)
    $matched = New-Object System.Collections.Generic.HashSet[uint32]
    foreach ($proc in $snapshot) {
        if ($proc.Name -ne 'node.exe' -and $proc.Name -ne 'python.exe') { continue }
        $line = [string]$proc.CommandLine
        if (-not $line) { continue }
        $lower = $line.ToLowerInvariant()
        $isBuild = ($lower.Contains('build_site.py') -and $lower.Contains(('--course=' + $COURSE).ToLowerInvariant()) -and $lower.Contains(('--section=' + $SECTION).ToLowerInvariant()))
        if ($lower.Contains($sectionNeedle) -or $isBuild) { $null = $matched.Add($proc.ProcessId) }
    }
    # Descendants: repeat until no new child turns up (the chain is
    # python -> cmd -> node, so one pass is not enough).
    do {
        $grew = $false
        foreach ($proc in $snapshot) {
            if ($matched.Contains($proc.ProcessId)) { continue }
            if ($proc.ParentProcessId -and $matched.Contains([uint32]$proc.ParentProcessId)) {
                $null = $matched.Add($proc.ProcessId)
                $grew = $true
            }
        }
    } while ($grew)
    $stopped = 0
    foreach ($processId in $matched) {
        try { Stop-Process -Id $processId -Force -ErrorAction Stop; $stopped++ } catch {}
    }
    Write-Host "Stopped $stopped process(es)."
    exit 0
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
# Probe a free site+websocket pair, walking 10-apart blocks (8081/8091/...).
# build_site.py re-probes and re-announces moments before the bind - this
# early answer only feeds the pre-build announcement below.
if (-not $BUILD_ONLY) {
    foreach ($candidate in @($PREVIEW_PORT, ($PREVIEW_PORT+10), ($PREVIEW_PORT+20), ($PREVIEW_PORT+30), ($PREVIEW_PORT+40), ($PREVIEW_PORT+50))) {
        $siteBusy = Get-NetTCPConnection -State Listen -LocalPort $candidate -ErrorAction SilentlyContinue
        $wsBusy   = Get-NetTCPConnection -State Listen -LocalPort ($candidate + 1000) -ErrorAction SilentlyContinue
        if (-not $siteBusy -and -not $wsBusy) { $HOST_PREVIEW_PORT = $candidate; break }
    }
    if (-not $HOST_PREVIEW_PORT) { Write-Host "Could not find free ports for this folder's previews."; exit 1 }
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

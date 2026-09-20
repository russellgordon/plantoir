#!/usr/bin/env pwsh
#requires -Version 5.1
# Windows setup script for Plantoir - runs the toolchain natively on this PC

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# -------------------- Defaults --------------------
# A range, so several previews can run at once — one per window.
$PREVIEW_PORT_RANGE = "8081-8084"
$PREVIEW_WS_RANGE = "9081-9084"

# -------------------- Config (from flags) --------------------
$FORCE_UPDATE_IMAGE      = $false
$OVERRIDE_IMAGE          = $null
$USE_LOCAL_DEV           = $false
$SKIP_PULL               = $false
$PassthruArgs            = @()
$PULL_STATUS             = ''

# -------------------- Help text --------------------
function Get-HostOS {
  try {
    if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) { return 'windows' }
    if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::OSX))     { return 'mac' }
    if ([Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Linux))   { return 'linux' }
  } catch {}
  return 'windows'
}
$__hostOS = Get-HostOS
if ($__hostOS -eq 'windows') {
  $SELF_CMD    = '.\setup.bat'
  $PREVIEW_CMD = '.\preview.bat'
} else {
  $SELF_CMD    = './setup.sh'
  $PREVIEW_CMD = './preview.sh'
}

function Show-Help {
@"
Usage: $SELF_CMD [options] [-- <args passed to setup_course.py>]

Options:
  --image REF          Use a specific already-built image instead of building
                       from this folder's recipe.
  --no-backup          (Pass-through to setup_course.py) Skip creating a backup ZIP - you will be asked to confirm.
  --help               Show this help and exit.

Notes:
- The website builder image is built LOCALLY from this folder's recipe
  (.toolchain\, kept current by the app). The first build needs an internet
  connection and takes a few minutes; after that it is cached.
- Use --local-dev to test your locally built image ($DEV_IMAGE) without pulling.
- Any arguments after a literal "--" are forwarded directly to setup_course.py.

Examples:
  $SELF_CMD
  $SELF_CMD --tag v2025.08.13
  $SELF_CMD --update-image
  $SELF_CMD --image ghcr.io/acme/teaching-quartz:edge
  $SELF_CMD --local-dev
  $SELF_CMD --context desktop-linux --local-dev
  $SELF_CMD -- --no-backup
"@ | Out-Host
}

# -------------------- Arg parsing --------------------
$idx = 0
while ($idx -lt $args.Count) {
  $a = $args[$idx]
  switch -Regex ($a) {
    '^(--help|-h)$' { Show-Help; exit 0 }
    '^--image$'     { if ($idx + 1 -ge $args.Count) { Write-Error '--image requires a value'; exit 1 }; $OVERRIDE_IMAGE = $args[$idx+1]; $idx += 2; continue }
    '^--$'          { if ($idx + 1 -lt $args.Count) { $PassthruArgs = $args[($idx+1)..($args.Count-1)] } else { $PassthruArgs = @() }; $idx = $args.Count; continue }
    default         { $PassthruArgs += $a; $idx++; continue }
  }
}

# -------------------- Resolve image to use --------------------
if ($OVERRIDE_IMAGE -and ($OVERRIDE_IMAGE -notmatch '/')) { $SKIP_PULL = $true }

# -------------------- Pre-flight checks --------------------
$ScriptDir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
if (-not $ScriptDir) { $ScriptDir = Get-Location }
Set-Location -LiteralPath $ScriptDir

# One container per working folder, so two folders never repoint each
# other's mounts. The name is a short hash of this folder's PHYSICAL path
# (true on-disk casing, symlinks resolved) plus a trailing newline —
# parity with `pwd -P | shasum -a 256` on macOS. The app derives the
# identical name, so this derivation must not drift. (Computed here,
# after Set-Location, so all three launchers hash the same folder.)
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
# and returns the bundled interpreter's path.
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

# -------------------- Folders & permissions --------------------
$CoursesRoot       = Join-Path -Path (Get-Location) -ChildPath 'courses'
$BackupsRoot       = Join-Path -Path $CoursesRoot -ChildPath '_backups'
$CreatedCoursesDir = $false
if (-not (Test-Path -LiteralPath $CoursesRoot)) {
  Write-Host "Creating 'courses' directory on host..."
  New-Item -ItemType Directory -Path $CoursesRoot -Force | Out-Null
  $CreatedCoursesDir = $true
}
if (-not (Test-Path -LiteralPath $BackupsRoot)) {
  Write-Host "Creating 'courses/_backups' directory on host..."
  New-Item -ItemType Directory -Path $BackupsRoot -Force | Out-Null
}
# Relax host attributes/perms to avoid surprises when mapping into Linux container
try { attrib -R "$CoursesRoot" 2>$null | Out-Null } catch {}
try { attrib -R "$BackupsRoot" 2>$null | Out-Null } catch {}
if ($CreatedCoursesDir) {
  try {
    $me = "$env:USERDOMAIN\$env:USERNAME"
    icacls "$CoursesRoot" /grant "${me}:(OI)(CI)M" 2>$null | Out-Null
  } catch {}
}

# -------------------- Native run (no container) --------------------
if ($NATIVE_RUNTIME) {
  $py = Enter-NativeRuntime
  $HOST_TZ_OFFSET = (Get-Date).ToString('zzz').Replace(':','')
  Write-Host "Detected host timezone offset: $HOST_TZ_OFFSET"
  Write-Host "Backups will be written to: $BackupsRoot"
  if ($PassthruArgs.Count -gt 0 -and ($PassthruArgs -contains '--no-backup')) {
    Write-Host 'You are running with --no-backup.'
    Write-Host 'This will skip creating a safety ZIP before modifying course folders.'
    $confirm = Read-Host 'Are you sure you want to proceed without a backup? (yes/no)'
    if ($confirm -notin @('yes','y','Y')) {
      Write-Host 'Cancelled.'
      exit 1
    } else {
      Write-Host 'Proceeding without backup...'
    }
  }
  if ($PassthruArgs.Count -gt 0) {
    $clean = New-Object System.Collections.Generic.List[string]
    for ($i=0; $i -lt $PassthruArgs.Count; $i++) {
      $p = $PassthruArgs[$i]
      if ($p -eq '--host-os') { $i++; continue }
      if ($p -like '--host-os=*') { continue }
      $clean.Add($p) | Out-Null
    }
    $PassthruArgs = $clean.ToArray()
  }
  $PassthruArgs += @('--host-os','windows')
  $env:HOST_TZ_OFFSET = $HOST_TZ_OFFSET
  Write-Host "Running the course setup wizard..."
  & $py -u (Join-Path $env:PLANTOIR_SCRIPTS_DIR 'setup_course.py') @PassthruArgs
  exit $LASTEXITCODE
}

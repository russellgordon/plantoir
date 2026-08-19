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

# ==================== Container runtime (Docker Engine in WSL2) ====================
# Docker Desktop is no longer required. On Windows this script uses the Docker
# Engine running inside WSL2 (Windows Subsystem for Linux) and installs/starts
# it automatically as needed. If a native 'docker' command already works (for
# example, Docker Desktop or Rancher Desktop), it is used as-is.

$env:WSL_UTF8 = '1'   # make wsl.exe emit UTF-8 so PowerShell can parse its output
$global:DockerViaWsl = $false
$global:WslUserArgs  = @()

function Test-NativeDockerReady {
    if (-not (Get-Command docker -CommandType Application -ErrorAction SilentlyContinue)) { return $false }
    try { docker info *> $null } catch { return $false }
    return ($LASTEXITCODE -eq 0)
}

function Test-WslDockerReady {
    try { wsl $global:WslUserArgs -e docker info *> $null } catch { return $false }
    return ($LASTEXITCODE -eq 0)
}

function Use-WslDocker {
    $global:DockerViaWsl = $true
    # Shadow 'docker' so every call in this script is routed through WSL.
    # PowerShell functions take precedence over external commands.
    # wsl.exe writes docker's stderr to OUR stderr; when a call site
    # redirects it (*> $null), PowerShell 5.1 wraps each line in an
    # ErrorRecord, and under ErrorActionPreference=Stop the first line
    # would TERMINATE the script even for probes that are expected to
    # fail (e.g. inspecting a not-yet-built image). Relax the preference
    # inside the wrapper so stderr stays plain output.
    # $input must be forwarded by hand: a plain function does NOT pass its
    # pipeline input on to a native command, so "script | docker exec -i"
    # would leave the remote process waiting forever on stdin (the --stop
    # hang). An empty $input just gives stdin an immediate EOF, which none
    # of the launcher's docker calls mind.
    function global:docker {
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
      if ($MyInvocation.ExpectingInput) { $input | & wsl $global:WslUserArgs -e docker @args }
      else { & wsl $global:WslUserArgs -e docker @args }
    } finally { $ErrorActionPreference = $eap }
    }
    Write-Host "Using the Docker engine inside WSL2."
}

function Ensure-ContainerRuntime {
    if (Test-NativeDockerReady) { return }

    # Stop mode must NEVER start anything — no provisioning, no prompts, no
    # waiting for an engine. Detect a running engine (native above, WSL
    # here); when none answers, there is nothing to stop.
    if ($STOP_MODE) {
        if (Test-WslDockerReady) { Use-WslDocker; return }
        $global:WslUserArgs = @('-u','root')
        if (Test-WslDockerReady) { Use-WslDocker; return }
        $global:WslUserArgs = @()
        Write-Host "Nothing to stop - the website builder isn't running."
        exit 0
    }

    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: No container runtime found."
        Write-Host "Install WSL2 (Windows Subsystem for Linux) by running this in an"
        Write-Host "Administrator PowerShell, then reboot and re-run this script:"
        Write-Host "  wsl --install"
        exit 1
    }

    $distros = @()
    try { $distros = (wsl -l -q) | Where-Object { $_ -and $_.Trim() } } catch {}
    if (-not $distros) {
        Write-Host "ERROR: WSL is present but no Linux distribution is installed."
        Write-Host "Run this in PowerShell, then reboot and re-run this script:"
        Write-Host "  wsl --install"
        exit 1
    }

    # Already-running engine inside WSL? (Try as the default user, then as root.)
    if (Test-WslDockerReady) { Use-WslDocker; return }
    $global:WslUserArgs = @('-u','root')
    if (Test-WslDockerReady) { Use-WslDocker; return }
    $global:WslUserArgs = @()

    # One-time provisioning begins here. The line below is a milestone
    # marker the app watches for (parity with the .sh launchers' one-time
    # "Setting up this Mac" moment).
    Write-Host "Setting up this PC - a one-time step that runs on its own ..."

    # Is the engine installed inside WSL at all?
    $dockerInWsl = $false
    try { wsl -e sh -c "command -v docker" *> $null; $dockerInWsl = ($LASTEXITCODE -eq 0) } catch {}

    if (-not $dockerInWsl) {
        Write-Host "The Docker engine is not installed inside WSL yet."
        $ans = Read-Host "Install it now inside your WSL distribution? (Y/n)"
        if ($ans -and $ans -notmatch '^(?i:y)') { Write-Host "Cancelled. A container runtime is required to continue."; exit 1 }
        Write-Host "Installing the Docker engine inside WSL (this can take a few minutes)..."
        wsl -u root -e sh -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Could not install the Docker engine inside WSL."
            Write-Host "Check your internet connection and re-run this script - it is safe to re-run."
            exit 1
        }
        $wslUser = ''
        try { $wslUser = (wsl -e sh -c "whoami" 2>$null | Select-Object -First 1).Trim() } catch {}
        if ($wslUser -and $wslUser -ne 'root') { try { wsl -u root -e sh -c "usermod -aG docker $wslUser" *> $null } catch {} }
    }

    Write-Host "Starting the Docker engine inside WSL..."
    try { wsl -u root -e sh -c "service docker start" *> $null } catch {}

    for ($i = 0; $i -lt 30; $i++) {
        if (Test-WslDockerReady) { Use-WslDocker; return }
        $global:WslUserArgs = @('-u','root')
        if (Test-WslDockerReady) { Use-WslDocker; return }
        $global:WslUserArgs = @()
        Start-Sleep -Seconds 2
    }

    Write-Host "ERROR: The Docker engine inside WSL did not become ready."
    Write-Host "Try these commands, then re-run this script:"
    Write-Host "  wsl -u root -e sh -c 'service docker start'"
    Write-Host "  wsl -e docker info"
    exit 1
}

# Docker running inside WSL sees Windows folders under /mnt/<drive>/...;
# translate host paths for bind mounts when routing through WSL.
function Get-MountPath([string]$winPath) {
    if (-not $global:DockerViaWsl) { return $winPath }
    try {
        $p = (wsl -e wslpath -a "$winPath" | Select-Object -First 1)
        if ($p) { return $p.Trim() }
    } catch {}
    return $winPath
}

Ensure-ContainerRuntime
$MOUNT_COURSES = Get-MountPath $HOST_COURSES
# ====================================================================

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
if ($STOP_MODE) {
    $dockerReady = $false
    try { docker info *> $null; if ($LASTEXITCODE -eq 0) { $dockerReady = $true } } catch {}
    if (-not $dockerReady) {
        Write-Host "Nothing to stop - the website builder isn't running."
        exit 0
    }
    $containerRunning = ((docker ps --format '{{.Names}}') | Where-Object { $_ -eq $CONTAINER_NAME }) -ne $null
    if (-not $containerRunning) {
        Write-Host "Nothing to stop - no container is running for this folder."
        exit 0
    }
    Write-Host "Stopping preview processes for $COURSE section $SECTION ..."
    $stopScript = @'
import os
import signal
import time

target = os.environ["TARGET_DIR"]
alt_target = target.replace("/teaching/courses/", "/tmp/quartz-builds/").replace("/.merged_output/", "/")
targets = [t for t in [target, alt_target] if t]
own_pid = os.getpid()

def preview_pids():
    """PIDs whose working directory is inside this section's output."""
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid == own_pid:
            continue
        try:
            cwd = os.readlink(f"/proc/{entry}/cwd")
        except OSError:
            continue
        if any(cwd == t or cwd.startswith(t + "/") for t in targets):
            found.append(pid)
    return found

victims = preview_pids()
for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
if victims:
    time.sleep(1)
for pid in preview_pids():
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
print(f"Stopped {len(victims)} process(es).")
'@
    $targetDir = "/teaching/courses/$COURSE/.merged_output/section$SECTION"
    $stopScript | docker exec -i -e "TARGET_DIR=$targetDir" $CONTAINER_NAME python3 -
    exit 0
}

# ---- The image is built HERE, from this folder's own recipe ----------
function Get-BuildContext {
  if (Test-Path "./Dockerfile") { return "." }
  if (Test-Path "./.toolchain/Dockerfile") { return "./.toolchain" }
  return $null
}

function Get-ToolchainHash([string]$context) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  # Hash only what the recipe is made of (parity with the .sh launchers):
  # in the repository the context is the repo root, and build outputs or
  # app sources must not steer the tag.
  # Fast directory traversal with pruning of excluded folders:
  $filesToHash = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
  $stack = [System.Collections.Generic.Stack[string]]::new()
  $fullContext = [System.IO.Path]::GetFullPath($context)
  $stack.Push($fullContext)

  while ($stack.Count -gt 0) {
    $dir = $stack.Pop()
    try {
      foreach ($subDir in [System.IO.Directory]::GetDirectories($dir)) {
        $dirName = [System.IO.Path]::GetFileName($subDir)
        if ($dirName -match '^(\.git|courses|mac-app|windows-app|node_modules|\.merged_output|bin|obj|\.gemini|\.system_generated|\.agents)$') {
          continue
        }
        $stack.Push($subDir)
      }
      foreach ($file in [System.IO.Directory]::GetFiles($dir)) {
        $fileName = [System.IO.Path]::GetFileName($file)
        if ($fileName -eq '.DS_Store') { continue }
        $filesToHash.Add([System.IO.FileInfo]::new($file))
      }
    } catch {}
  }

  $filesToHash.Sort([System.Comparison[System.IO.FileInfo]]{ param($a, $b) [System.StringComparer]::CurrentCultureIgnoreCase.Compare($a.FullName, $b.FullName) })

  $sb = [System.Text.StringBuilder]::new()
  foreach ($fileInfo in $filesToHash) {
    try {
      $stream = [System.IO.File]::OpenRead($fileInfo.FullName)
      try {
        $fileHashBytes = $sha.ComputeHash($stream)
        $null = $sb.Append(([System.BitConverter]::ToString($fileHashBytes) -replace '-',''))
      } finally {
        $stream.Dispose()
      }
    } catch {}
  }

  $combined = $sb.ToString()
  $bytes = [Text.Encoding]::UTF8.GetBytes($combined)
  return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').Substring(0,8).ToLower()
}


# BuildKit is what builds the image; the apt-installed WSL engine may lack
# the buildx plugin. Install it when missing; failing that, fall back to
# the classic builder with BuildKit enabled (mirrors the .sh launchers).
$script:UseBuildKitFallback = $false
function Ensure-Buildx {
  docker buildx version *> $null
  if ($LASTEXITCODE -eq 0) { return }
  if ($global:DockerViaWsl) {
    Write-Host "Installing the image builder (BuildKit) inside WSL ..."
    try { wsl -u root -e sh -c "apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq docker-buildx >/dev/null 2>&1 || apt-get install -y -qq docker-buildx-plugin >/dev/null 2>&1" *> $null } catch {}
    docker buildx version *> $null
    if ($LASTEXITCODE -eq 0) { return }
  }
  Write-Host "WARNING: 'docker buildx' is unavailable; using the classic builder with"
  Write-Host "         BuildKit enabled. If the built image misbehaves, install buildx."
  $script:UseBuildKitFallback = $true
}

function Build-ImageIfMissing {
  docker image inspect "$IMAGE" *> $null
  if ($LASTEXITCODE -eq 0) { Write-Host "Website builder is ready."; return }
  if (-not $BUILD_CONTEXT) {
    Write-Host "Image '$IMAGE' is not on this machine. Build it first."
    exit 1
  }
  Write-Host "Building your website builder - the first time takes a few minutes ..."
  Ensure-Buildx
  if ($script:UseBuildKitFallback) {
    if ($global:DockerViaWsl) {
      wsl @($global:WslUserArgs) -e env DOCKER_BUILDKIT=1 docker build --progress=plain -t "$IMAGE" "$BUILD_CONTEXT"
    } else {
      $env:DOCKER_BUILDKIT = '1'
      docker build --progress=plain -t "$IMAGE" "$BUILD_CONTEXT"
    }
  } else {
    docker buildx build --load --progress=plain -t "$IMAGE" "$BUILD_CONTEXT"
  }
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Could not build the website builder."
    Write-Host "The first build needs an internet connection - try again once online."
    exit 1
  }
  Write-Host "Website builder built."
}

$BUILD_CONTEXT = Get-BuildContext
if ($OVERRIDE_IMAGE) {
  $BUILD_CONTEXT = $null
  $IMAGE = $OVERRIDE_IMAGE
} elseif ($BUILD_CONTEXT) {
  Write-Host "Checking whether your website builder is up to date..."
  $IMAGE = "teaching-quartz:src-$(Get-ToolchainHash $BUILD_CONTEXT)"
} else {
  Write-Host "This folder is missing the toolchain's build recipe."
  Write-Host "Open the folder in the app once to refresh it, or run from a repository copy."
  exit 1
}
Build-ImageIfMissing


# A free block of host ports for this folder's previews (four site ports
# and their live-reload websocket ports).
function Find-FreePortBlock {
  foreach ($base in 8081, 8091, 8101, 8111, 8121, 8131) {
    $allFree = $true
    foreach ($offset in 0..3) {
      if (Get-NetTCPConnection -State Listen -LocalPort ($base + $offset) -ErrorAction SilentlyContinue) { $allFree = $false; break }
      if (Get-NetTCPConnection -State Listen -LocalPort ($base + 1000 + $offset) -ErrorAction SilentlyContinue) { $allFree = $false; break }
    }
    if ($allFree) { return $base }
  }
  return $null
}

# The one shared container from before folders each had their own.
function Retire-LegacyContainer {
  $names = docker ps -a --format '{{.Names}}'
  if ($names -contains 'teaching-quartz') {
    Write-Host "Retiring the old shared workspace container ..."
    docker rm -f teaching-quartz *> $null
  }
}

function Run-ContainerWithMount {
    Retire-LegacyContainer
    $HostBase = Find-FreePortBlock
    if (-not $HostBase) { Write-Host "Could not find free ports for this folder's previews."; exit 1 }
    Write-Host ("Binding host courses to container: {0} -> /teaching/courses" -f $MOUNT_COURSES)
    docker run -dit `
        --name "$CONTAINER_NAME" `
        -v "${MOUNT_COURSES}:/teaching/courses" `
        -p "$HostBase-$($HostBase + 3):8081-8084" `
        -p "$($HostBase + 1000)-$($HostBase + 1003):9081-9084" `
        "$IMAGE" `
        tail -f /dev/null | Out-Null
}

# A container keeps running the version it was created from, so an update
# only takes effect once the container itself is recreated.
# The line below is a milestone marker the app watches for (parity with
# preview.sh's "Starting container if needed...").
Write-Host "Starting container if needed ..."
$DESIRED_IMAGE_ID = (docker image inspect --format '{{.Id}}' "$IMAGE" 2>$null | Select-Object -First 1)
$RUNNING_IMAGE_ID = (docker inspect -f '{{.Image}}' "$CONTAINER_NAME" 2>$null | Select-Object -First 1)

$containerExists = ((docker ps -a --format '{{.Names}}') | Where-Object { $_ -eq $CONTAINER_NAME }) -ne $null
if ($containerExists) {
    # check mount
    $CURRENT_MOUNT_SRC = $null
    try {
        $cinfo = docker inspect "$CONTAINER_NAME" | ConvertFrom-Json
        if ($cinfo -and $cinfo.Count -gt 0) {
            foreach ($m in $cinfo[0].Mounts) {
                if ($m.Destination -eq "/teaching/courses") { $CURRENT_MOUNT_SRC = $m.Source; break }
            }
        }
    } catch {}
    $CURRENT_MOUNT_SRC = Normalize-HostPath $CURRENT_MOUNT_SRC
    $HOST_COURSES_N = Normalize-HostPath $MOUNT_COURSES

    if (-not $CURRENT_MOUNT_SRC) {
        Write-Host "Existing container has no /teaching/courses mount; recreating with correct mount ..."
        if ((docker ps --format '{{.Names}}' | Where-Object { $_ -eq $CONTAINER_NAME })) { docker stop "$CONTAINER_NAME" *> $null }
        docker rm "$CONTAINER_NAME" *> $null
        Run-ContainerWithMount
    } elseif ($CURRENT_MOUNT_SRC -ne $HOST_COURSES_N) {
        Write-Host "Detected different working directory:"
        Write-Host "  Existing mount: $CURRENT_MOUNT_SRC"
        Write-Host "  Desired mount:  $HOST_COURSES_N"
        Write-Host "Recreating container '$CONTAINER_NAME' to point at the new folder ..."
        if ((docker ps --format '{{.Names}}' | Where-Object { $_ -eq $CONTAINER_NAME })) { docker stop "$CONTAINER_NAME" *> $null }
        docker rm "$CONTAINER_NAME" *> $null
        Run-ContainerWithMount
    } elseif ($DESIRED_IMAGE_ID -and $RUNNING_IMAGE_ID -and ($RUNNING_IMAGE_ID -ne $DESIRED_IMAGE_ID)) {
        Write-Host "Your workspace was built from an older version; rebuilding it so the update takes effect ..."
        if ((docker ps --format '{{.Names}}' | Where-Object { $_ -eq $CONTAINER_NAME })) { docker stop "$CONTAINER_NAME" *> $null }
        docker rm "$CONTAINER_NAME" *> $null
        Run-ContainerWithMount
    } elseif (-not ((docker inspect -f '{{json .HostConfig.PortBindings}}' "$CONTAINER_NAME" 2>$null) -match '9084/tcp')) {
        # An older container publishes only one port; published ports cannot
        # change after creation, so recreating is the only way to add them.
        Write-Host "Rebuilding your workspace so several previews can run at once ..."
        if ((docker ps --format '{{.Names}}' | Where-Object { $_ -eq $CONTAINER_NAME })) { docker stop "$CONTAINER_NAME" *> $null }
        docker rm "$CONTAINER_NAME" *> $null
        Run-ContainerWithMount
    } else {
        $running = ((docker ps --format '{{.Names}}') | Where-Object { $_ -eq $CONTAINER_NAME }) -ne $null
        if (-not $running) {
            Write-Host "Starting existing container $CONTAINER_NAME ..."
            docker start "$CONTAINER_NAME" *> $null
        } else {
            Write-Host "Container $CONTAINER_NAME is already running with correct mount."
        }
    }
} else {
    Write-Host "Creating a new container named $CONTAINER_NAME (image: $IMAGE) ..."
    Run-ContainerWithMount
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
$portLine = docker port "$CONTAINER_NAME" "$PREVIEW_PORT/tcp" 2>$null | Select-Object -First 1
if ($portLine -and ($portLine -match ':(\d+)\s*$')) { $HOST_PREVIEW_PORT = $Matches[1] }
if (-not $HOST_PREVIEW_PORT) { $HOST_PREVIEW_PORT = $PREVIEW_PORT }
if (-not $BUILD_ONLY) {
    Write-Host ("Preview will be available at: http://localhost:{0}/" -f $HOST_PREVIEW_PORT)
}

# ---- Run build inside the container ----
Write-Host "Running build_site.py inside the Docker container ..."
# A terminal is what makes the container's prompts and live progress work, so
# ask for one when there IS one. But `docker exec -t` refuses to start at all
# when stdin is not a terminal, which is how this runs from a script, a CI
# job, or Plantoir's MCP server — and it fails at this line, minutes into the
# build, with nothing more useful than "the input device is not a TTY".
# Without a terminal, run python unbuffered instead, so progress still arrives
# line by line rather than in one lump when the build finishes.
$interactive = -not [Console]::IsInputRedirected
$execArgs = @("exec")
$execArgs += if ($interactive) { "-it" } else { "-i" }
$execArgs += @("$CONTAINER_NAME", "python3")
if (-not $interactive) { $execArgs += "-u" }
$execArgs += "/opt/scripts/build_site.py"
$execArgs += $argList
& docker @execArgs
# Propagate the build's exit code — without this the script reports
# success even when the run inside the container failed.
exit $LASTEXITCODE
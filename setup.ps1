#!/usr/bin/env pwsh
#requires -Version 5.1
# Windows setup script for Dockerized Quartz for Teachers

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
$DOCKER_CONTEXT_OVERRIDE = $null
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
  --context NAME       Use a specific Docker context (sets DOCKER_CONTEXT=NAME for this run).
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
    '^--context$'   { if ($idx + 1 -ge $args.Count) { Write-Error '--context requires a value'; exit 1 }; $DOCKER_CONTEXT_OVERRIDE = $args[$idx+1]; $idx += 2; continue }
    '^--$'          { if ($idx + 1 -lt $args.Count) { $PassthruArgs = $args[($idx+1)..($args.Count-1)] } else { $PassthruArgs = @() }; $idx = $args.Count; continue }
    default         { $PassthruArgs += $a; $idx++; continue }
  }
}

# -------------------- Pre-flight: context --------------------
if ($DOCKER_CONTEXT_OVERRIDE) { $env:DOCKER_CONTEXT = $DOCKER_CONTEXT_OVERRIDE }

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
  # $input forwarded by hand: a plain function does not pass pipeline input
  # on to a native command (an empty $input is a harmless immediate EOF).
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
# ====================================================================

$CURRENT_CONTEXT = (docker context show 2>$null) -as [string]; if (-not $CURRENT_CONTEXT) { $CURRENT_CONTEXT = 'unknown' }
$HOST_ARCH       = (docker info --format '{{.Architecture}}' 2>$null) -as [string];  if (-not $HOST_ARCH) { $HOST_ARCH = 'unknown' }
$HOST_OS         = (docker info --format '{{.OSType}}' 2>$null) -as [string];         if (-not $HOST_OS)   { $HOST_OS   = 'unknown' }
Write-Host "Docker context: $CURRENT_CONTEXT"
Write-Host "Host detected by Docker: $HOST_OS/$HOST_ARCH"

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

function Normalize-HostPath([string]$p) {
  if (-not $p) { return $p }
  try { $r = (Resolve-Path -LiteralPath $p).Path } catch { $r = $p }
  return $r.TrimEnd('\','/')
}
$HOST_COURSES = Normalize-HostPath $CoursesRoot
# The path the Docker daemon should mount (differs from $HOST_COURSES when the
# engine runs inside WSL2 and sees Windows drives under /mnt).
$MOUNT_COURSES = Get-MountPath $HOST_COURSES

# -------------------- Pull or verify image presence --------------------
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

function Test-ImagePresent([string]$ref) {
  try { $null = docker image inspect "$ref"; return $true } catch { return $false }
}
$BUILD_CONTEXT = Get-BuildContext
if ($OVERRIDE_IMAGE) {
  $IMAGE = $OVERRIDE_IMAGE
} elseif ($BUILD_CONTEXT) {
  $IMAGE = "teaching-quartz:src-$(Get-ToolchainHash $BUILD_CONTEXT)"
} else {
  Write-Host "This folder is missing the toolchain's build recipe."
  Write-Host "Open the folder in the app once to refresh it, or run from a repository copy."
  exit 1
}
Write-Host "Using image: $IMAGE"

Build-ImageIfMissing

# -------------------- Show image version/build info --------------------
function Show-ImageInfo([string]$_img) {
  try { $info = docker image inspect "$_img" | ConvertFrom-Json } catch { Write-Host "Could not inspect image $_img"; return }
  if (-not $info) { return }
  $obj = $info[0]
  try { $labels = $obj.Config.Labels } catch { $labels = @{} }
  if (-not $labels) { $labels = @{} }
  $ver     = $labels['org.opencontainers.image.version']; if (-not $ver) { $ver = '(no version label)' }
  $created = $labels['org.opencontainers.image.created']; if (-not $created) { $created = $obj.Created }
  $rev     = $labels['org.opencontainers.image.revision']; if (-not $rev) { $rev = '(no revision label)' }
  $src     = $labels['org.opencontainers.image.source']
  $title   = $labels['org.opencontainers.image.title'];   if (-not $title) { $title = $_img }
  Write-Host "Image info ${PULL_STATUS}:"
  Write-Host "  Title:    $title"
  Write-Host "  Version:  $ver"
  Write-Host "  Created:  $created"
  Write-Host "  Revision: $rev"
  if ($src) { Write-Host "  Source:   $src" }
  try {
    $digests = $obj.RepoDigests
    if ($digests) {
      Write-Host '  Digests:'
      foreach ($d in $digests) { if ($d) { Write-Host "   - $d" } }
    }
  } catch {}
}
Show-ImageInfo $IMAGE

# -------------------- Container helpers --------------------

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
  Write-Host "Binding host courses to container: $MOUNT_COURSES -> /teaching/courses"
  $args = @(
    'run','-dit',
    '--name', $CONTAINER_NAME,
    '-v', "${MOUNT_COURSES}:/teaching/courses",
    '-p', "$HostBase-$($HostBase + 3):8081-8084",
    '-p', "$($HostBase + 1000)-$($HostBase + 1003):9081-9084",
    $IMAGE,
    'tail','-f','/dev/null'
  )
  $null = & docker @args
}

# SINGLE-LINE writability probe to avoid ": not found" from CRLF/newlines
function Test-ContainerWriteable {
  param([string]$Name)
  try {
    $cmd = "mkdir -p /teaching/courses && echo ok > /teaching/courses/.write_probe && rm -f /teaching/courses/.write_probe"
    $null = docker exec $Name sh -lc $cmd
    return $true
  } catch {
    return $false
  }
}

# -------------------- Create/start container (mount-aware + refresh + write probe) --------------------
Write-Host "Ensuring container is running with the correct, writable mount..."
# A container keeps running the version it was created from, so an update
# only takes effect once the container itself is recreated.
$DESIRED_IMAGE_ID = (docker image inspect --format '{{.Id}}' "$IMAGE" 2>$null | Select-Object -First 1)
$RUNNING_IMAGE_ID = (docker inspect -f '{{.Image}}' "$CONTAINER_NAME" 2>$null | Select-Object -First 1)

$containerExists = ((docker ps -a --format '{{.Names}}') | Where-Object { $_ -eq $CONTAINER_NAME }) -ne $null

if ($containerExists) {
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

  if (-not $CURRENT_MOUNT_SRC) {
    Write-Host "Existing container has no /teaching/courses mount; recreating with correct mount..."
    if ((docker ps --format '{{.Names}}') | Where-Object { $_ -eq $CONTAINER_NAME }) { $null = docker stop "$CONTAINER_NAME" }
    $null = docker rm "$CONTAINER_NAME"
    Run-ContainerWithMount
  }
  elseif ($CURRENT_MOUNT_SRC -ne (Normalize-HostPath $MOUNT_COURSES)) {
    Write-Host "Detected different working directory:"
    Write-Host "  Existing mount: $CURRENT_MOUNT_SRC"
    Write-Host "  Desired mount:  $MOUNT_COURSES"
    Write-Host "Recreating container '$CONTAINER_NAME' to point at the new folder..."
    if ((docker ps --format '{{.Names}}') | Where-Object { $_ -eq $CONTAINER_NAME }) { $null = docker stop "$CONTAINER_NAME" }
    $null = docker rm "$CONTAINER_NAME"
    Run-ContainerWithMount
  }
  elseif ($DESIRED_IMAGE_ID -and $RUNNING_IMAGE_ID -and ($RUNNING_IMAGE_ID -ne $DESIRED_IMAGE_ID)) {
    Write-Host "Your workspace was built from an older version; rebuilding it so the update takes effect..."
    if ((docker ps --format '{{.Names}}') | Where-Object { $_ -eq $CONTAINER_NAME }) { $null = docker stop "$CONTAINER_NAME" }
    $null = docker rm "$CONTAINER_NAME"
    Run-ContainerWithMount
  }
  elseif (-not ((docker inspect -f '{{json .HostConfig.PortBindings}}' "$CONTAINER_NAME" 2>$null) -match '9084/tcp')) {
    # An older container publishes only one port; published ports cannot
    # change after creation, so recreating is the only way to add them.
    Write-Host "Rebuilding your workspace so several previews can run at once..."
    if ((docker ps --format '{{.Names}}') | Where-Object { $_ -eq $CONTAINER_NAME }) { $null = docker stop "$CONTAINER_NAME" }
    $null = docker rm "$CONTAINER_NAME"
    Run-ContainerWithMount
  }
  else {
    $running = ((docker ps --format '{{.Names}}') | Where-Object { $_ -eq $CONTAINER_NAME }) -ne $null
    if ($running) {
      if ($CreatedCoursesDir) {
        Write-Host "The 'courses/' folder was created just now; refreshing container to ensure a clean, writable mount..."
        $null = docker rm -f "$CONTAINER_NAME"
        Run-ContainerWithMount
      }
      elseif (-not (Test-ContainerWriteable -Name $CONTAINER_NAME)) {
        Write-Host "Mounted 'courses/' is not writable from the container - recreating it..."
        $null = docker rm -f "$CONTAINER_NAME"
        Run-ContainerWithMount
      }
      else {
        Write-Host "Container $CONTAINER_NAME is already running with correct, writable mount."
      }
    } else {
      Write-Host "Starting existing container $CONTAINER_NAME..."
      $null = docker start "$CONTAINER_NAME"
      if (-not (Test-ContainerWriteable -Name $CONTAINER_NAME)) {
        Write-Host "Mounted 'courses/' is not writable from the container after start - recreating it..."
        $null = docker rm -f "$CONTAINER_NAME"
        Run-ContainerWithMount
      }
    }
  }
}
else {
  Write-Host "Creating a new container named $CONTAINER_NAME (image: $IMAGE) ..."
  Run-ContainerWithMount
}

# -------------------- Backup confirmation (pass-through option) --------------------
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

# -------------------- Run setup inside container --------------------
# Strip any existing --host-os and force windows
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

Write-Host "Running setup_course.py inside the Docker container..."
$execArgs = @(
  'exec','-e', "HOST_TZ_OFFSET=${HOST_TZ_OFFSET}", '-it', $CONTAINER_NAME,
  'python3','/opt/scripts/setup_course.py'
) + $PassthruArgs
# DO NOT suppress output here: interactive prompts must be visible
& docker @execArgs
# Propagate the wizard's exit code — without this the script reports
# success even when the run inside the container failed.
exit $LASTEXITCODE

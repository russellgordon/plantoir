#!/usr/bin/env pwsh
#requires -Version 5.1
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Show-Help {
@"
Usage:
  .\deploy.bat <COURSE_CODE> <SECTION_NUMBER> [--target netlify|cloudflare] [--diagnose] [--team <TEAM_SLUG>] [--to-folder <PATH>] [--reset-token|--logout]

Examples:
  .\deploy.bat ICS3U 1
  .\deploy.bat ICS3U 1 --diagnose
  .\deploy.bat ICS3U 1 --team my-org-slug
  .\deploy.bat ICS3U 1 --target cloudflare

Notes:
- Deploys from /teaching/courses/<COURSE>/.merged_output/section<SECTION> inside the container.
- You must build first (the static site goes to 'public/' in that section folder).
- --target chooses where the built site goes. netlify (the default) or cloudflare.
- The token for whichever service you publish to is stored as a Windows Generic
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
$SECTION_NUM = $args[1]
$DIAGNOSE    = ''
$TEAM_SLUG   = ''
$RESET_TOKEN = $false
$TO_FOLDER = ''
$TARGET = 'netlify'
$ACCOUNT_ARG = ''

for ($i = 2; $i -lt $args.Count; $i++) {
  switch -Regex ($args[$i]) {
    '^--help$|^-h$'      { Show-Help; exit 0 }
    '^--diagnose$'       { $DIAGNOSE = '--diagnose'; continue }
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
  Write-Host ("Unknown publishing target '{0}'. Use netlify or cloudflare." -f $TARGET)
  exit 1
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

# ======================
# Preflight checks
# ======================
$COURSE_DIR_HOST  = Normalize-HostPath (Join-Path -Path (Get-Location) -ChildPath ("courses\{0}" -f $COURSE_CODE))
$MERGED_DIR_HOST  = Normalize-HostPath (Join-Path -Path $COURSE_DIR_HOST -ChildPath ".merged_output")
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
  Write-Host " A section without one produces no website, so there is nothing to publish."
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
  $targetDir = Join-Path -Path ($TO_FOLDER.TrimEnd('\','/')) -ChildPath ("section{0}" -f $SECTION_NUM)
  New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
  # A PREVIEW build must never reach a published site. Serve mode bakes a
  # live-reload client into every page, and on a published site that script
  # makes a student's browser ask permission to access other apps and
  # services on this device. deploy.py already refuses this, but ONLY for
  # Netlify and Cloudflare: this branch publishes host-to-host and never
  # enters the container, so deploy.py never runs. The app's own publish path
  # is protected by BuildFreshness; the command line was not. Mirrors the fix
  # made in deploy.sh on 2026-09-05 — see GUI-IMPROVEMENTS row 392.
  $publishedIndex = Join-Path $PUBLIC_DIR_HOST "index.html"
  if ((Test-Path -LiteralPath $publishedIndex) -and
      (Select-String -LiteralPath $publishedIndex -Pattern "ws://localhost:" -Quiet)) {
    Write-Host "This site was built by a preview, which bakes in a live-reload script"
    Write-Host "  that students' browsers would ask about. Rebuilding it for publishing..."
    & ".\preview.bat" $COURSE_CODE $SECTION_NUM "--build-only"
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Could not rebuild this site for publishing."
      exit 1
    }
    # Wait for the rebuild to become VISIBLE here before copying. On the mac
    # the lag is the container's bind mount; natively on Windows it is the
    # filesystem settling after a large write, and OneDrive can add to it.
    # Waits on the condition (a front page without the live-reload client),
    # not a guessed interval, and is bounded.
    for ($w = 0; $w -lt 75; $w++) {
      if ((Test-Path -LiteralPath $publishedIndex) -and
          -not (Select-String -LiteralPath $publishedIndex -Pattern "ws://localhost:" -Quiet)) { break }
      Start-Sleep -Milliseconds 200
    }
    if (-not (Test-Path -LiteralPath $publishedIndex)) {
      Write-Host "The rebuilt site has not appeared. Nothing was published."
      exit 1
    }
  }

  Write-Host ("Publishing {0} section {1} to a folder..." -f $COURSE_CODE, $SECTION_NUM)
  # /MIR mirrors (copies changes, deletes removals); robocopy exit codes
  # below 8 all mean success.
  robocopy $PUBLIC_DIR_HOST $targetDir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) {
    Write-Host ("Publishing to the folder failed (robocopy exit {0})." -f $LASTEXITCODE)
    exit 1
  }
  $global:LASTEXITCODE = 0
  Write-Host "Published."
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

The token you just made is allowed to publish, but not to look up which
Cloudflare account it belongs to - so the account's ID is needed as well.
This is the only time you will be asked for it.

  1. Open this page:  https://dash.cloudflare.com
  2. Choose "Workers & Pages" from the list on the left.
  3. Find "Account ID" on the right-hand side, and copy it.
     (It is also the long code in the address bar, just after
     dash.cloudflare.com/.)
"@ | Out-Host
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
  Write-Host "Done. Next publish will ask for a new token."
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
the publishing is coming from you. It does that with an API token - a long
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
     by name. A token that names no account cannot publish anything, and
     what you get back if you skip this does not mention accounts at all.
  6. Under "TTL", set the end date to after the end of your school year -
     next July is a safe choice - or leave it with no end date. An expired
     token stops your publishing working, with nothing to say why.
  7. Choose "Continue to summary", then "Create Token".
  8. Copy the long code Cloudflare shows you - it is only shown once - and
     paste it below. Nothing appears as you paste; that is normal.
"@ | Out-Host
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
publishing is coming from you. It does that with an access token - a long
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
     your publishing working, with nothing on screen to say why, so set a
     date after the end of your school year: next July is a safe choice.
     Choose "No expiration" instead if it is offered.
  5. Choose "Generate token", then copy the long code Netlify shows you -
     it is only shown once.
  6. Paste it below. Nothing appears as you paste; that is normal.
"@ | Out-Host
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

<#
Fetches the Obsidian add-ons Plantoir carries for diagrams and graphs (#581,
the mac's #495) - TikZJax and Functionplot, with their licences - into
windows-app/Vendor/obsidian-addons/<id>/<file>. Plantoir.csproj ships that
folder beside Plantoir.exe as obsidian-addons\, and the app writes the ones a
course uses into it on the teacher's one yes
(documentation/12-windows-app.md -> "Obsidian's add-ons for diagrams and
graphs on Windows (#581)").

THE PINS ARE THE CONTRACT'S, READ FROM IT - NEVER REPEATED HERE. Every
add-on's id and version, and every file's name, size, SHA-256 and address,
live in contracts/shared-rules.json -> obsidianAddOnsForFigures.addOns, which
the mac's fetch, the mac app and Plantoir.Core's ObsidianFigureAddOns.Pinned
read too; two lists would be two answers. ObsidianFigureAddOnsTests fails if a
64-character hex run is ever written into this file.

CHECKED BEFORE ANYTHING IS INSTALLED. Every file must be the size and SHA-256
its pin says; one mismatch installs NOTHING. The app hashes them again before
it writes them into a course, and the build (Plantoir.csproj ->
CheckObsidianAddOns) refuses a folder that is missing, holds a file too many
or too few, or holds a file whose hash is not that file's pin.

A CACHE OUTSIDE THE REPOSITORY, as the mac's fetch keeps one:
$env:PLANTOIR_ADDONS_CACHE, or %LOCALAPPDATA%\Plantoir-dev\obsidian-addons,
files named by their SHA-256 and checked again before use, so a second clone
or worktree costs no download.

NOT committed (12.9 MB), for the reason runtime\ and llama\ are not: this
repository ships recipes, not binaries. RUN IT ONCE PER CLONE OR WORKTREE
before building the app - the build refuses without it - and again after a
pin in the contract changes. Idempotent: a folder that already matches every
pin is left as it is.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$here        = $PSScriptRoot
$contract    = Join-Path $here "..\..\contracts\shared-rules.json"
$destination = Join-Path $here "obsidian-addons"
$cache       = if ($env:PLANTOIR_ADDONS_CACHE) { $env:PLANTOIR_ADDONS_CACHE } `
               else { Join-Path $env:LOCALAPPDATA "Plantoir-dev\obsidian-addons" }

# The contract is about 2 MB, which is past Windows PowerShell 5.1's
# ConvertFrom-Json limit, so 5.1 reads it with the serializer that limit
# comes from, its maximum raised; PowerShell 7 has no such limit.
$text = [IO.File]::ReadAllText((Resolve-Path $contract))
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $addOns = @(($text | ConvertFrom-Json).obsidianAddOnsForFigures.addOns)
    function Field($Object, [string]$Name) { $Object.$Name }
} else {
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    $addOns = @($serializer.DeserializeObject($text)['obsidianAddOnsForFigures']['addOns'])
    function Field($Object, [string]$Name) { $Object[$Name] }
}
if ($addOns.Count -eq 0) { throw "contracts/shared-rules.json has no obsidianAddOnsForFigures.addOns. Nothing was installed." }

function Sha256Of([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

# Already in place? Every pinned file present at its size and hash, and nothing else.
$inPlace = Test-Path -LiteralPath $destination
$expected = 0
foreach ($addOn in $addOns) {
    foreach ($file in (Field $addOn 'files')) {
        $expected++
        $path = Join-Path (Join-Path $destination (Field $addOn 'id')) (Field $file 'name')
        if (-not (Test-Path -LiteralPath $path) -or (Sha256Of $path) -ne (Field $file 'sha256')) { $inPlace = $false }
    }
}
if ($inPlace -and @(Get-ChildItem -LiteralPath $destination -Recurse -File -Force).Count -eq $expected) {
    Write-Host "The Obsidian add-ons are already in place ($destination)."
    exit 0
}

New-Item -ItemType Directory -Force -Path $cache | Out-Null
$staged = Join-Path $here (".obsidian-addons." + [Guid]::NewGuid().ToString("N").Substring(0, 8))
try {
    foreach ($addOn in $addOns) {
        $id = Field $addOn 'id'
        Write-Host "Fetching $id $(Field $addOn 'version')..."
        New-Item -ItemType Directory -Force -Path (Join-Path $staged $id) | Out-Null
        foreach ($file in (Field $addOn 'files')) {
            $name = Field $file 'name'; $bytes = [long](Field $file 'bytes'); $sha = Field $file 'sha256'
            $cached = Join-Path $cache $sha
            if (-not (Test-Path -LiteralPath $cached) -or (Sha256Of $cached) -ne $sha) {
                Invoke-WebRequest -UseBasicParsing -Uri (Field $file 'from') -OutFile "$cached.part"
                Move-Item -Force -LiteralPath "$cached.part" -Destination $cached
            }
            $gotBytes = (Get-Item -LiteralPath $cached).Length
            $gotSha = Sha256Of $cached
            if ($gotBytes -ne $bytes -or $gotSha -ne $sha) {
                Remove-Item -Force -LiteralPath $cached
                throw "$id/$name does not match its pin (expected $bytes bytes, $sha; got $gotBytes bytes, $gotSha). Nothing was installed."
            }
            Copy-Item -LiteralPath $cached -Destination (Join-Path (Join-Path $staged $id) $name)
        }
    }
    if (Test-Path -LiteralPath $destination) { Remove-Item -Recurse -Force -LiteralPath $destination }
    Move-Item -LiteralPath $staged -Destination $destination
} finally {
    if (Test-Path -LiteralPath $staged) { Remove-Item -Recurse -Force -LiteralPath $staged }
}
$total = (Get-ChildItem -LiteralPath $destination -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host "The Obsidian add-ons are installed into $destination ($expected files, $total bytes)."

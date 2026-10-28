<#
Known vulnerabilities in the Windows runtime's npm packages (#685): the
Windows half of verify.sh's npm audit (#667).

    .\windows-app\audit-runtime.ps1                  # the runtime in windows-app\Vendor\runtime
    .\windows-app\audit-runtime.ps1 -Runtime <dir>   # another one (an installed {app}\runtime, say)

Audits every JavaScript tree the runtime carries, with the runtime's OWN npm
(Node 22.23.4 since #675), and compares the result with the accepted list,
contracts/toolchain.json -> npmAudit, through the same comparator verify.sh
uses (scripts/npm_audit.py). Exit 0: clean (every advisory seen is accepted
for its tree at its severity, low and moderate ones reported). Exit 1: a
high or critical advisory not accepted for its tree, or accepted at a lower
severity than it has now, or a tree that could not be audited at all (no
lockfile, output that is not JSON). Exit 2: SKIPPED, the advisory database
did not answer - and then no tree counts as audited until every tree can be,
never a pass.

The five trees, as npmAudit.trees[].windowsRuntime names them:
  quartz, tikz-engine   their own lockfiles, `npm audit --package-lock-only`.
  wrangler              the lockfile npm wrote beside its prefix install
                        (runtime\wrangler\package-lock.json). NOT verify.sh's
                        copy-into-an-empty-project: in the image wrangler is
                        a GLOBAL install, whose dependencies sit inside its
                        own folder, so a copy carries them; here they are
                        hoisted into runtime\wrangler\node_modules beside it,
                        so a copy of the package alone would make npm resolve
                        its dependencies again from the registry, at whatever
                        versions are newest today, and audit a tree that was
                        never installed. The prefix's own lockfile names
                        exactly what is installed; `npm ls --all` is run first
                        and must agree, or the tree FAILS.
  pagedjs, function-plot  prebuilt files, so a lockfile is built from the
                        pins in an empty project (`npm install
                        --package-lock-only --ignore-scripts`, needs the
                        registry), as verify.sh does.

OPT-IN, deliberately in no `dotnet test` and no build: an audit queries a
database that changes every day, so a gate that ran it by default would turn
red on a new advisory with nothing in the product changed - the reason
contracts/toolchain.json -> npmAudit.note keeps it out of the image build.
RELEASING.md step 2 runs it at every cut, beside verify.sh's line.

Only npm's STDOUT is read (offline npm prints its JSON there and an error on
stderr), and it is captured by Python and written as UTF-8 without a BOM:
Windows PowerShell 5.1's `>` writes UTF-16 and Out-File a BOM, and
npm_audit.read_audit reads UTF-8 JSON (the #685 plan review's R10). Kept out
of scripts\ on purpose: everything there is in the image's build context,
and a Windows-only orchestrator there would rebuild every Mac's image.
#>
[CmdletBinding()]
param(
    [string]$Runtime = ""
)

$ErrorActionPreference = 'Stop'
# Not a parameter default: Windows PowerShell 5.1 has no $PSScriptRoot there.
if (-not $Runtime) { $Runtime = Join-Path $PSScriptRoot "Vendor\runtime" }
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path (Join-Path $Runtime "manifest.json"))) {
    Write-Host "No runtime at $Runtime (no manifest.json): run windows-app\Vendor\fetch-runtime.ps1 first." -ForegroundColor Red
    exit 1
}
$Runtime = (Resolve-Path $Runtime).Path
$python = Join-Path $Runtime "python\python.exe"
$npm = Join-Path $Runtime "node\npm.cmd"
foreach ($tool in @($python, $npm)) {
    if (-not (Test-Path $tool)) { Write-Host "$tool is missing: this runtime is incomplete." -ForegroundColor Red; exit 1 }
}

$Work = Join-Path ([IO.Path]::GetTempPath()) ("plantoir-npm-audit-" + (Get-Date).ToString("yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force $Work | Out-Null
$driver = Join-Path $Work "audit_runtime.py"
@'
import json, os, re, shutil, subprocess, sys
from pathlib import Path

repo, runtime, npm, work = (Path(a) for a in sys.argv[1:5])
sys.dont_write_bytecode = True
sys.path.insert(0, str(repo / "scripts"))
import npm_audit

toolchain = json.loads((repo / "contracts" / "toolchain.json").read_text(encoding="utf-8"))
pins = {p["pin"]: p for p in toolchain["pins"]}
contract = toolchain["npmAudit"]
env = dict(os.environ)
env["PATH"] = str(runtime / "node") + os.pathsep + env.get("PATH", "")


def npm_run(arguments, cwd):
    return subprocess.run([str(npm)] + arguments, cwd=str(cwd), env=env,
                          capture_output=True, text=True, encoding="utf-8", errors="replace")


def audit_here(folder):
    return npm_run(["audit", "--package-lock-only", "--json"], folder).stdout


def step_failed(stderr):
    first = ""
    for line in stderr.splitlines():
        if "error" in line.lower():
            first = line
            break
    message = first.replace('"', "").replace("\\", "")[:200]
    return json.dumps({"plantoir": "lockfile-step-failed", "message": message})


def synthesise(folder, name, version):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "package.json").write_text(json.dumps(
        {"name": "plantoir-audit", "private": True, "dependencies": {name: version}}), encoding="utf-8")
    made = npm_run(["install", "--package-lock-only", "--ignore-scripts", "--no-audit", "--no-fund"], folder)
    if made.returncode != 0:
        return step_failed(made.stderr)
    return audit_here(folder)


NO_LOCKFILE = json.dumps({"plantoir": "no-lockfile"})
outputs = {}
for tree, place in (("quartz", runtime / "quartz"), ("tikz-engine", runtime / "vendor" / "tikz-engine")):
    outputs[tree] = audit_here(place) if (place / "package-lock.json").is_file() else NO_LOCKFILE

wrangler = runtime / "wrangler"
if (wrangler / "package-lock.json").is_file() and (wrangler / "node_modules" / "wrangler" / "package.json").is_file():
    listed = npm_run(["ls", "--all"], wrangler)
    if listed.returncode != 0:
        outputs["wrangler"] = json.dumps({"plantoir": "lockfile-step-failed",
                                          "message": "npm ls --all disagrees with runtime\\wrangler's lockfile"})
    else:
        outputs["wrangler"] = audit_here(wrangler)
else:
    outputs["wrangler"] = NO_LOCKFILE

outputs["pagedjs"] = synthesise(work / "pagedjs", "pagedjs", pins["pagedjs"]["value"])
outputs["function-plot"] = synthesise(work / "function-plot", "function-plot", pins["functionPlot"]["value"])

audits = {}
for tree, text in outputs.items():
    path = work / (tree + ".json")
    path.write_text(text, encoding="utf-8")
    audits[tree] = npm_audit.read_audit(path)

report = npm_audit.compare(audits, contract)
for line in npm_audit.describe(report):
    print(line)
code = npm_audit.exit_code(report)
if code == 0:
    print(f"OK {report['advisories_seen']} advisories across {len(report['audited_trees'])} trees, "
          f"{len(report['accepted_seen'])} accepted, {len(report['reported'])} low or moderate reported, "
          f"{len(report['stale'])} stale")
elif code == 2:
    print("SKIPPED: " + report["unreachable_trees"][0][1][:200]
          + " - no tree counts as audited until every tree can be.")
else:
    print("PROBLEMS: see the BLOCKING and FAILED lines above.")
sys.exit(code)
'@ | Set-Content $driver -Encoding ascii

# -I: the driver reads npm's output, not code; -X utf8 because -I drops
# PYTHONUTF8 and the advisories' titles are not ASCII.
& $python -I -X utf8 $driver $RepoRoot $Runtime $npm $Work
$code = $LASTEXITCODE
Write-Host "Each tree's audit is kept in $Work"
exit $code

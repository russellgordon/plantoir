namespace Plantoir.Core.Assist;

/// <summary>
/// The question a launcher-side deploy asks before it builds (#799, the mac's
/// #768: <c>buildFreshness.reuseTheLastBuild</c>), as the scheduled wrapper
/// asks it. Two pieces of generated PowerShell, each a copy of
/// <c>deploy.ps1</c>'s own, byte for byte, which
/// <c>ScheduledDeployReusesTheLastBuildTests</c> pins against the file: a copy
/// nothing compares is a copy that drifts.
///
/// <para><b>Why the wrapper asks at all.</b> Russell's ruling, 2026-11-13:
/// the scheduled deploy follows the #768 ruling like every other way of
/// deploying. Until then the wrapper built unconditionally ("Build first,
/// always"), which never sent a stale site but rebuilt every night, and its
/// build wrote no "site built again before deploying" line: deploy.ps1, asked
/// after it, found the build current and wrote nothing, so the trail was
/// silent about a build the mac's scheduled run records.</para>
///
/// <para><b>Why the shared Python and not BuildFreshness.</b> The wrapper
/// runs with the app CLOSED, as a PowerShell script; the one reader it can
/// reach is the runtime's Python, which reads the toolchain stamp too, so it
/// asks preview, toolchain, then pages and clock, exactly as deploy.ps1 and
/// deploy.py do.</para>
/// </summary>
public static class BuildBeforeDeployingQuestion
{
    /// <summary>
    /// The Python handed to <c>python -c</c>: arguments are the scripts folder,
    /// the course folder and the section's built folder. It prints ONE word:
    /// <c>reuse</c>, or the reason (<c>preview</c>, <c>toolchain</c>,
    /// <c>pages</c>, <c>clock</c>), or <c>failed</c>; only <c>reuse</c> with
    /// exit 0 reuses, so a Python that prints nothing builds (the #799 plan's
    /// positive token, the plan review's L3). A site with files but no front
    /// page (<c>neverBuilt</c>) is a preview's if any page carries the
    /// client (the plan review's M1: asked BEFORE the stamp, so a preview's
    /// pages never reach a destination), then deployed as it stands only if
    /// this toolchain stamped it, as deploy.py's <c>why_this_deploy_builds_first</c>
    /// maps it. No double quotes: Windows PowerShell 5.1 does not escape them
    /// when it hands an argument to a native program. stderr is silenced
    /// inside Python, never redirected: under <c>$ErrorActionPreference =
    /// 'Stop'</c> a redirected native stderr line is a terminating error.
    /// <c>flush</c> before <c>os._exit</c>, which does not flush.
    /// </summary>
    public static readonly string[] PythonLines =
    {
        "import os, sys",
        "sys.stderr = open(os.devnull, 'w')",
        "answer = 'failed'",
        "try:",
        "    sys.path.insert(0, sys.argv[1])",
        "    import toolchain_paths as t",
        "    from pathlib import Path",
        "    reason = t.why_build_before_deploying(sys.argv[2], sys.argv[3])",
        "    if reason == t.REASON_NEVER_BUILT:",
        "        if t.site_carries_preview_client(Path(sys.argv[3]) / 'public'):",
        "            reason = t.REASON_PREVIEW",
        "        elif t.site_was_built_by_this_toolchain(sys.argv[3]):",
        "            reason = None",
        "        else:",
        "            reason = t.REASON_TOOLCHAIN",
        "    answer = reason if reason else 'reuse'",
        "except BaseException:",
        "    answer = 'failed'",
        "sys.stdout.write(answer)",
        "sys.stdout.flush()",
        "os._exit(0)",
    };

    /// <summary>The reasons the question answers with, other than <c>reuse</c>.</summary>
    public static readonly string[] Reasons = { "preview", "toolchain", "pages", "clock" };

    /// <summary>
    /// deploy.ps1's <c>Write-TrailLine</c>, from the guard block it shares with
    /// preview.ps1: the same file, stamp, mutex and <c>PLANTOIR_TRAIL_DIR</c>
    /// rule as the app's own writer, and it never fails its caller.
    /// </summary>
    public static readonly string[] TrailWriterLines =
    {
        "function Write-TrailLine {",
        "    param([string]$What)",
        "    try {",
        "        $dir = Join-Path $env:LOCALAPPDATA 'Plantoir\\Logs'",
        "        $handed = $env:PLANTOIR_TRAIL_DIR",
        "        if ($handed -and ($handed -match '^[A-Za-z]:[\\\\/]' -or $handed -match '^[\\\\/]{2}[^\\\\/]+[\\\\/][^\\\\/]+')) {",
        "            $trimmed = $handed.TrimEnd([char[]]@([char]92, [char]47))",
        "            if ($trimmed -match '^[A-Za-z]:$') { $trimmed += '\\' }",
        "            $dir = $trimmed",
        "        }",
        "        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }",
        "        $line = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture) + ' ' + [char]0x00B7 + ' ' + $What + [Environment]::NewLine",
        "        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($line)",
        "        $mutex = New-Object System.Threading.Mutex($false, 'Local\\PlantoirActivityTrail')",
        "        $held = $false",
        "        try {",
        "            try { $held = $mutex.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $held = $true }",
        "            $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete",
        "            $stream = New-Object IO.FileStream((Join-Path $dir 'activity.txt'), [IO.FileMode]::Append, [IO.FileAccess]::Write, $share)",
        "            try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }",
        "        } finally {",
        "            if ($held) { $mutex.ReleaseMutex() }",
        "            $mutex.Dispose()",
        "        }",
        "    } catch {}",
        "}",
    };

    /// <summary>
    /// A string as a PowerShell expression in ASCII only: the wrapper is
    /// written without a BOM and Windows PowerShell 5.1 reads such a file in
    /// the ANSI code page, so the trail line's middle dot and dash are written
    /// as code points, as the guard block writes its own.
    /// </summary>
    public static string AsciiExpression(string text)
    {
        var parts = new List<string>();
        var run = new System.Text.StringBuilder();
        foreach (char c in text)
        {
            if (c < 128)
            {
                if (c == '\'') run.Append("''"); else run.Append(c);
                continue;
            }
            if (run.Length > 0) { parts.Add("'" + run + "'"); run.Clear(); }
            parts.Add($"[char]0x{(int)c:X4}");
        }
        if (run.Length > 0) parts.Add("'" + run + "'");
        if (parts.Count == 0) return "''";
        return "(" + string.Join(" + ", parts) + ")";
    }

    /// <summary>
    /// The trail line's text after the stamp, for <paramref name="reason"/>, as
    /// an ASCII PowerShell expression: "{course}/{section} · " and the words
    /// <see cref="Scripting.ActivityTrail.BuiltBeforeDeployingWords"/> gives.
    /// </summary>
    public static string TrailLineExpression(string courseCode, int section, string reason) =>
        AsciiExpression($"{courseCode}/{section} · {Scripting.ActivityTrail.BuiltBeforeDeployingWords(reason)}");
}

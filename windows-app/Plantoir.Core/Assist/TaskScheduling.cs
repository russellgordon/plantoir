using System.Diagnostics;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// Handing a deploy to Windows Task Scheduler, via schtasks.
///
/// schtasks rather than the TaskScheduler COM library on purpose: it needs no
/// extra dependency, it is present on every Windows this app runs on, and its
/// failures arrive as text a teacher can be shown. The equivalent on macOS is
/// launchd, which is why the decision of WHETHER to schedule — and every word
/// the teacher reads — lives in Plantoir.Core, and only this last step is
/// Windows-specific.
///
/// It deliberately does not ask for a wake timer. See ScheduledDeploy for why.
/// </summary>
public static class TaskScheduling
{
    /// <summary>
    /// The date formats schtasks might want, most likely first. Which one is
    /// correct depends on the machine's locale, and it accepts exactly one.
    /// </summary>
    private static readonly string[] DateFormats = ["yyyy/MM/dd", "MM/dd/yyyy", "dd/MM/yyyy"];

    /// <summary>
    /// Create (or replace) a scheduled deploy for a SINGLE destination.
    /// Returns null on success, or the reason it could not be scheduled. A
    /// thin wrapper over the multi-destination overload below, kept so
    /// every existing caller written against "this course's ONE
    /// destination" keeps working unchanged.
    /// </summary>
    public static string? Schedule(string taskName, string workingFolder, string courseCode,
                                   int section, DateTime when, string courseDirectory,
                                   CourseConfiguration.DeployDestination destination, string cloudflareAccountID = "") =>
        Schedule(taskName, workingFolder, courseCode, section, when, courseDirectory,
            new List<CourseConfiguration.DeployDestination> { destination }, cloudflareAccountID);

    /// <summary>
    /// Create (or replace) a scheduled deploy across one or more
    /// destinations. Returns null on success, or the reason it could not be
    /// scheduled.
    ///
    /// Always writes a small wrapper .ps1 — even for a course's ordinary
    /// single destination — because the wrapper is also where the " — Edited"
    /// marker's own record gets made. See "A scheduled deploy needs its own
    /// path to the same record" in WINDOWS-HANDOFF.md: unlike the mac, whose
    /// launchd agent launches the APP binary (so it can fingerprint the
    /// section in-process before running the deploy script), Windows'
    /// scheduled task runs `powershell.exe` directly — there is no app code
    /// alive at the moment the deploy actually happens. So the wrapper itself
    /// fingerprints the section (via the bundled Python, `section_fingerprint.py`
    /// — see that file for why this is a third copy of the algorithm) right
    /// before running any destination's `deploy.ps1`, then — only if every
    /// destination succeeds — writes a sentinel file the app picks up and
    /// applies the next time it starts or comes to the front
    /// (<see cref="ScheduledDeployCompletion.ConsumePending"/>). One
    /// destination failing must not stop the others from running, the same
    /// "redundancy" rule the mac's `oneShotCommand` encodes as un-chained
    /// shell lines — so lines are deliberately NOT chained with `-and`.
    /// Mirrors `ScheduledDeploy.oneShotCommand`.
    /// </summary>
    public static string? Schedule(string taskName, string workingFolder, string courseCode,
                                   int section, DateTime when, string courseDirectory,
                                   IReadOnlyList<CourseConfiguration.DeployDestination> destinations,
                                   string cloudflareAccountID = "")
    {
        // The launcher does the deploy, exactly as the app does it.
        string launcher = Path.Combine(workingFolder, "deploy.ps1");
        if (!File.Exists(launcher))
            return $"There is no deploy.ps1 in {workingFolder}, so there is nothing to schedule.";

        var excluded = SectionPublishState.SelfPublishingSubpaths(courseDirectory, destinations);
        if (WriteWrapperScript(taskName, workingFolder, launcher, courseCode, section, courseDirectory,
                               excluded, destinations, cloudflareAccountID) is not { } scriptPath)
            return "The scheduled deploy's wrapper script could not be written.";
        string command = TaskRunCommand(scriptPath);

        // schtasks accepts the date in the format the MACHINE's locale uses,
        // and rejects every other one outright — "Invalid Start Date (Date
        // should be in yyyy/mm/dd format)" on the machine this was written on,
        // which is not the format the docs and most examples show. Rather than
        // hardcode one and move the bug to somebody else's computer, try the
        // plausible ones until Windows accepts one. It says so itself when it
        // does not.
        string lastError = "";
        foreach (string format in DateFormats)
        {
            var (exitCode, output) = Run([
                "/Create", "/F",
                "/TN", taskName,
                "/TR", command,
                "/SC", "ONCE",
                "/SD", when.ToString(format),
                "/ST", when.ToString("HH:mm"),
            ]);
            if (exitCode == 0) return null;
            lastError = output.Trim();

            // Only a date-format complaint is worth another go; anything else
            // (a bad name, no permission) will fail identically every time.
            if (!lastError.Contains("Start Date", StringComparison.OrdinalIgnoreCase)) break;
        }

        return $"Windows would not accept the scheduled task: {lastError}";
    }

    /// <summary>
    /// Where a multi-destination task's wrapper script is written —
    /// %LOCALAPPDATA%\Plantoir\scheduled, not a temp folder, because the
    /// task may fire hours or days later and a temp-folder sweep must never
    /// be the reason an overnight deploy silently does nothing.
    /// </summary>
    public static string ScheduledScriptsDirectory() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Plantoir", "scheduled");

    private static string WrapperScriptPath(string taskName) =>
        Path.Combine(ScheduledScriptsDirectory(), SafeName(taskName) + ".ps1");

    /// <summary>Single-quotes a value for PowerShell, escaping any embedded quote.</summary>
    private static string PsQuote(string value) => "'" + value.Replace("'", "''") + "'";

    /// <summary>
    /// The `/TR` value schtasks stores for the wrapper: `powershell.exe`
    /// invoking the wrapper script by path, in double quotes so a working
    /// folder with spaces in it (any Desktop folder, most OneDrive paths)
    /// still resolves.
    ///
    /// A REAL embedded quote (`\"` in C# source = one `"` character) — NOT
    /// `\\\"` (backslash + quote, TWO characters), which is what this used
    /// to say. Found 2026-08-23 as the reason a scheduled deploy never fired
    /// at all: `Run()` hands the whole command to `schtasks.exe` as ONE
    /// argument via <see cref="ProcessStartInfo.ArgumentList"/>, which
    /// already quotes and escapes the value correctly for schtasks because
    /// it contains spaces — there is no reason for this method to also
    /// escape the quotes itself, and doing so put a LITERAL backslash-quote
    /// pair into the stored command instead of a quote character. Confirmed
    /// via `schtasks /Query ... /XML`, which showed `&lt;Arguments&gt;`
    /// holding `\"C:\...\script.ps1\"` verbatim (with a stray newline
    /// besides) — a path PowerShell's `-File` could never resolve, so the
    /// task ran, found nothing to run, and failed silently every time.
    /// Internal (not private) so the test that pins this can reach it
    /// without spinning up a real scheduled task.
    /// </summary>
    /// <summary>
    /// How Task Scheduler runs the wrapper.
    ///
    /// <para><b>-NonInteractive is load-bearing, not tidiness.</b> Nobody is
    /// there to answer a question at 6 a.m. Without it, a `Read-Host` in
    /// anything the wrapper calls simply BLOCKS: the task sits at an invisible
    /// prompt until Task Scheduler's own limit (three days, by default), and
    /// the teacher's site is never updated and nothing says why. With it,
    /// `Read-Host` throws instead, the wrapper exits non-zero, and the run
    /// fails visibly.</para>
    ///
    /// <para>The question that made this real: <c>preview.ps1</c> asks
    /// "Continue anyway?" when the section is not listed in
    /// <c>course_config.json</c> — which is exactly the state a course is left
    /// in when one of its sections is archived while a scheduled deploy for
    /// that section still exists. That became reachable the moment the wrapper
    /// started building before publishing.</para>
    /// </summary>
    internal static string TaskRunCommand(string scriptPath) =>
        $"powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{scriptPath}\"";

    /// <summary>
    /// Writes the wrapper: fingerprint the section first (via the bundled
    /// Python — see <c>scripts/section_fingerprint.py</c>), then one
    /// un-chained invocation of deploy.ps1 per destination (one destination
    /// failing must not stop the others from being tried), then — only if
    /// every destination succeeded, and only if the fingerprint could be
    /// taken — a sentinel file for <see cref="ScheduledDeployCompletion"/> to
    /// pick up and apply the next time the app runs. Returns the script's
    /// path, or null if it could not be written.
    /// </summary>
    /// <summary>
    /// Internal rather than private so the suite can read the script this
    /// writes. There is no runner behind a generated wrapper — it is executed
    /// by Task Scheduler at 6 a.m. with nobody watching — so the only gate
    /// available is asserting the TEXT, and the ordering inside it is
    /// load-bearing (see the health-capture block).
    /// </summary>
    internal static string? WriteWrapperScript(
        string taskName, string workingFolder, string launcherPath, string courseCode, int section,
        string courseDirectory, IReadOnlyList<string> excludedSelfPublishingSubpaths,
        IReadOnlyList<CourseConfiguration.DeployDestination> destinations, string cloudflareAccountID)
    {
        try
        {
            Directory.CreateDirectory(ScheduledScriptsDirectory());

            string excludedArray = string.Join(", ", excludedSelfPublishingSubpaths.Select(PsQuote));
            string destinationTypesArray = string.Join(", ", destinations.Select(d => PsQuote(d.Type)));
            string destinationNamesArray = string.Join(", ", destinations.Select(d => PsQuote(DeployCommand.DestinationDescription(d))));

            var lines = new List<string>
            {
                "# Generated by Plantoir for a scheduled deploy.",
                "# See TaskScheduling.WriteWrapperScript and WINDOWS-HANDOFF.md,",
                "# \"A scheduled deploy needs its own path to the same record\".",
                "",
                "# ---- Fingerprint the section BEFORE anything runs -----------------------",
                "# Matches the mac's launchd path: the fingerprint is taken right before the",
                "# deploy actually happens, not when the teacher scheduled it, so an edit made",
                "# in between still shows up correctly either way.",
                "$fingerprint = $null",
                "try {",
                $"  $nativeRuntime = $env:PLANTOIR_RUNTIME",
                "  if (-not $nativeRuntime) {",
                "    $appRuntime = Join-Path $env:LOCALAPPDATA 'Programs\\Plantoir\\runtime'",
                "    if (Test-Path (Join-Path $appRuntime 'manifest.json')) { $nativeRuntime = $appRuntime }",
                "  }",
                "  if ($nativeRuntime) {",
                "    $pythonExe = Join-Path $nativeRuntime 'python\\python.exe'",
                $"    $toolchainScripts = Join-Path {PsQuote(workingFolder)} '.toolchain\\scripts'",
                $"    $scriptsDir = if (Test-Path $toolchainScripts) {{ $toolchainScripts }} else {{ Join-Path {PsQuote(workingFolder)} 'scripts' }}",
                "    $fpScript = Join-Path $scriptsDir 'section_fingerprint.py'",
                "    if ((Test-Path $pythonExe) -and (Test-Path $fpScript)) {",
                $"      $fpArgs = @({PsQuote(courseDirectory)}, {section}{(excludedArray.Length > 0 ? ", " + excludedArray : "")})",
                "      $fpOutput = & $pythonExe $fpScript @fpArgs 2>$null",
                "      if ($LASTEXITCODE -eq 0 -and $fpOutput) { $fingerprint = ([string]$fpOutput).Trim() }",
                "    }",
                "  }",
                "} catch { $fingerprint = $null }",
                "",
                "# ---- Build first, always -----------------------------------------------",
                "# A scheduled deploy had NO build step at all: it published whatever",
                "# happened to be in the builds folder, however old, and if nothing was",
                "# there it failed. The mac's launchd script has always tested freshness",
                "# and rebuilt when stale; this side simply never did.",
                "#",
                "# Unconditionally, rather than repeating the freshness test in shell.",
                "# This runs while the teacher is asleep, so a minute of rebuilding that",
                "# was not strictly needed costs nothing, and a freshness test written a",
                "# THIRD time — after the app's and the launcher's — is a third thing to",
                "# drift. --build-only also stops any preview still serving this section,",
                "# so it cannot overwrite what is about to go out.",
                "#",
                "# The build's output is CAPTURED, because the folder checks run inside it",
                "# and print PLANTOIR_HEALTH: lines that nothing would otherwise read: this",
                "# runs with the app closed, so the console they go to is gone by morning.",
                "# Per run, into a file deleted immediately afterwards — the mac reads its",
                "# findings out of a launchd log opened with O_APPEND and had to record the",
                "# log's SIZE beforehand to avoid re-finding last week's markers every",
                "# night. A per-run capture cannot have that bug at all.",
                "#",
                "# If the capture cannot be set up, the build runs plainly. Losing the",
                "# findings is a pity; losing the publish is not acceptable.",
                "$healthDir = $null",
                "$buildLog = $null",
                "$buildErrLog = $null",
                "try {",
                $"  $healthDir = Join-Path $env:LOCALAPPDATA {PsQuote(Path.Combine("Plantoir", "scheduled", "folder-problems"))}",
                "  New-Item -ItemType Directory -Force -Path $healthDir | Out-Null",
                $"  $buildLog = Join-Path $healthDir ({PsQuote(SafeName(taskName))} + '-' + [Guid]::NewGuid().ToString('N') + '.log')",
                "} catch { $healthDir = $null; $buildLog = $null }",
                "",
                "# Redirected by the OPERATING SYSTEM, into a child process — never",
                "# through a PowerShell pipeline. `preview.ps1` sets",
                "# $ErrorActionPreference = 'Stop', and in Windows PowerShell 5.1 merging a",
                "# native command's stderr into the pipeline (`2>&1`, `*>&1`, even",
                "# `2>$null`) turns the first stderr LINE into a TERMINATING",
                "# NativeCommandError that propagates out of the callee and kills this",
                "# wrapper with it: no exit code, no scan, no deploy, and nothing said.",
                "# The build inherits stderr to node and npm, and any Python traceback",
                "# lands there too — which is exactly the failing run whose findings",
                "# matter most. Measured on 5.1.26100: a piped callee died at its first",
                "# stderr line and took its caller with it, where the same callee run",
                "# plainly finished and returned 5.",
                "#",
                "# Start-Process also gives an exit code that does not depend on",
                "# $LASTEXITCODE surviving a pipeline. stdout and stderr must go to",
                "# DIFFERENT files (Start-Process refuses one file for both); the markers",
                "# are on stdout, and the error file is scanned too rather than assumed",
                "# empty.",
                "if ($buildLog) {",
                "  $buildErrLog = $buildLog + '.err'",
                // Built as a variable rather than continued across lines: a
                // backtick continuation in generated shell is one stray trailing
                // space away from silently splitting the command.
                // ONE STRING, with the quoting done here — not an ARRAY.
                // Start-Process joins an array with spaces and quotes nothing,
                // so a working folder whose name contains a space (every
                // Desktop folder, most OneDrive paths, and the machine this was
                // written on has one called "scheduled deploy test") is split
                // at the space and powershell.exe reports "Processing -File
                // 'C:\...\scheduled' failed because the file does not have a
                // '.ps1' extension". Measured: exit -196608, no build, no
                // findings, no deploy — every night, silently.
                "  $buildArgs = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"' + " +
                    $"{PsQuote(Path.Combine(workingFolder, "preview.ps1"))} + '\" \"' + {PsQuote(courseCode)} + '\" \"' + {PsQuote(section.ToString())} + '\" --build-only'",
                "  $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $buildArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput $buildLog -RedirectStandardError $buildErrLog",
                "  $buildExitFromChild = $proc.ExitCode",
                "} else {",
                $"  & {PsQuote(Path.Combine(workingFolder, "preview.ps1"))} {PsQuote(courseCode)} {PsQuote(section.ToString())} --build-only",
                "  $buildExitFromChild = $null",
                "}",
                "# Saved AT ONCE. Everything below runs commands of its own, and the guard",
                "# that decides whether anything is published must test THIS build's code.",
                "# The captured path takes it from the child process rather than from",
                "# $LASTEXITCODE, which is one fewer thing that has to survive.",
                "if ($null -ne $buildExitFromChild) { $buildExit = $buildExitFromChild } else { $buildExit = $LASTEXITCODE }",
                "",
                "# ---- What the build said about the folders --------------------------------",
                "# BEFORE the failure guard, deliberately. Since 2026-09-01 a section with no",
                "# index.md exits NON-ZERO from --build-only, and that is exactly the run",
                "# whose findings the teacher most needs in the morning: scanning after the",
                "# guard would say nothing about the one failure that explains itself.",
                "#",
                "# The lines are copied VERBATIM and parsed in C# with the same parser a live",
                "# build uses. No JSON is interpreted in shell.",
                "if ($buildLog -and (Test-Path -LiteralPath $buildLog)) {",
                "  try {",
                $"    $healthFile = Join-Path $healthDir {PsQuote(HealthRecordName(courseCode, section))}",
                "    $scanned = @($buildLog)",
                "    if ($buildErrLog -and (Test-Path -LiteralPath $buildErrLog)) { $scanned += $buildErrLog }",
                "    # -Encoding UTF8 because OS-level redirection writes the child's own",
                "    # bytes with no BOM, and Select-String would otherwise read them as",
                "    # ANSI and mangle any non-ASCII inside a sentence.",
                "    $markers = @(Select-String -LiteralPath $scanned -SimpleMatch 'PLANTOIR_HEALTH:' -Encoding UTF8 | ForEach-Object { $_.Line })",
                "    if ($markers.Count -gt 0) {",
                "      Set-Content -LiteralPath $healthFile -Value $markers -Encoding utf8",
                "    } else {",
                "      # Nothing wrong this time: clear anything an earlier run left, so a",
                "      # problem the teacher has since put right stops being reported.",
                "      Remove-Item -LiteralPath $healthFile -Force -ErrorAction SilentlyContinue",
                "    }",
                "  } catch { }",
                "  Remove-Item -LiteralPath $buildLog -Force -ErrorAction SilentlyContinue",
                "  if ($buildErrLog) { Remove-Item -LiteralPath $buildErrLog -Force -ErrorAction SilentlyContinue }",
                "}",
                "",
                "if ($buildExit -ne 0) {",
                "  Write-Host 'Could not build this section, so nothing was published.'",
                "  exit 1",
                "}",
                "",
                "# ---- Deploy to every destination — un-chained, on purpose ---------------",
                "$allSucceeded = $true",
            };

            foreach (var destination in destinations)
            {
                var arguments = DeployCommand.Arguments(courseCode, section, destination, cloudflareAccountID);
                string quotedArgs = string.Join(" ", arguments.Select(PsQuote));
                lines.Add($"& {PsQuote(launcherPath)} {quotedArgs}");
                lines.Add("if ($LASTEXITCODE -ne 0) { $allSucceeded = $false }");
            }

            lines.AddRange(new[]
            {
                "",
                "# ---- Record what went out, for the app to pick up ------------------------",
                "if ($allSucceeded -and $fingerprint) {",
                $"  $pendingDir = Join-Path $env:LOCALAPPDATA {PsQuote(Path.Combine("Plantoir", "scheduled", "pending"))}",
                "  New-Item -ItemType Directory -Force -Path $pendingDir | Out-Null",
                "  $sentinel = [ordered]@{",
                $"    courseCode = {PsQuote(courseCode)}",
                $"    sectionNumber = {section}",
                $"    courseDirectory = {PsQuote(courseDirectory)}",
                "    fingerprint = $fingerprint",
                $"    destinationTypes = @({destinationTypesArray})",
                $"    destinationNames = @({destinationNamesArray})",
                "    completedAtUtc = (Get-Date).ToUniversalTime().ToString('o')",
                "  } | ConvertTo-Json",
                $"  $sentinelPath = Join-Path $pendingDir ({PsQuote(SafeName(taskName))} + '-' + [Guid]::NewGuid().ToString('N') + '.json')",
                "  Set-Content -LiteralPath $sentinelPath -Value $sentinel -Encoding utf8",
                "}",
            });

            string scriptPath = WrapperScriptPath(taskName);
            File.WriteAllLines(scriptPath, lines);
            return scriptPath;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// What the wrapper calls the file it leaves this section's folder problems
    /// in, and what <see cref="ScheduledHealthFindings"/> looks for.
    ///
    /// <para>One function rather than two matching string literals, because a
    /// mismatch between the writer and the reader fails in the quietest way
    /// available: the record would be written faithfully every night and read
    /// never, and everything else would look healthy.</para>
    /// </summary>
    public static string HealthRecordName(string courseCode, int sectionNumber) =>
        $"{SafeName(courseCode)}-section{sectionNumber}.txt";

    private static string SafeName(string taskName) =>
        new string(taskName.Select(c => char.IsLetterOrDigit(c) ? c : '-').ToArray());

    /// <summary>
    /// Remove a scheduled deploy. Returns null on success. Also removes the
    /// wrapper script written by <see cref="WriteWrapperScript"/> —
    /// schtasks deleting the task does not delete a script it merely pointed
    /// at, and a leftover one is not runnable on its own so it is simply
    /// litter, but it should not accumulate every time a teacher reschedules.
    /// </summary>
    public static string? Cancel(string taskName)
    {
        try { File.Delete(WrapperScriptPath(taskName)); } catch { /* best effort — litter, not a failure */ }
        var (exitCode, output) = Run(["/Delete", "/F", "/TN", taskName]);
        return exitCode == 0 ? null : output.Trim();
    }

    /// <summary>Whether a task by this name is already scheduled.</summary>
    public static bool Exists(string taskName) => Run(["/Query", "/TN", taskName]).ExitCode == 0;

    /// <summary>The name a section's scheduled deploy carries. One per section, by construction.</summary>
    public static string NameFor(string courseCode, int sectionNumber) =>
        $"Plantoir deploy {courseCode.ToUpperInvariant()} section {sectionNumber}";

    /// <summary>
    /// When a section's scheduled deploy will run, or null if none is set.
    ///
    /// Windows is asked rather than anything of ours being written down,
    /// because Windows is where the truth lives: a teacher can delete the task
    /// in Task Scheduler, and a note kept beside it would then promise a
    /// deploy that will never happen. There is at most one per section — the
    /// name is fixed per section and scheduling replaces — so this answers
    /// with a time, not a list.
    /// </summary>
    public static DateTime? NextRun(string courseCode, int sectionNumber)
    {
        var (exitCode, output) = Run(["/Query", "/TN", NameFor(courseCode, sectionNumber), "/FO", "LIST"]);
        if (exitCode != 0) return null;

        foreach (string line in output.Split('\n'))
        {
            int colon = line.IndexOf(':');
            if (colon < 0) continue;
            // The label is localised on non-English Windows, so this leans on
            // the shape — a "Next Run Time:" row whose value parses as one.
            if (!line[..colon].Contains("Next Run", StringComparison.OrdinalIgnoreCase)) continue;

            string value = line[(colon + 1)..].Trim();
            if (DateTime.TryParse(value, out var when)) return when;
        }
        return null;
    }

    private static (int ExitCode, string Output) Run(IEnumerable<string> arguments)
    {
        var info = new ProcessStartInfo
        {
            FileName = "schtasks.exe",
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (string argument in arguments) info.ArgumentList.Add(argument);

        try
        {
            using var process = Process.Start(info);
            if (process is null) return (1, "schtasks could not be started.");
            string output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
            process.WaitForExit(30_000);
            return (process.ExitCode, output);
        }
        catch (Exception error) { return (1, error.Message); }
    }
}

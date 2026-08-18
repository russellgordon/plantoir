using System.Diagnostics;

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
    /// Create (or replace) a scheduled deploy. Returns null on success, or the
    /// reason it could not be scheduled.
    /// </summary>
    public static string? Schedule(string taskName, string workingFolder, string courseCode,
                                   int section, DateTime when, IReadOnlyList<string>? deployArguments = null)
    {
        // The launcher does the deploy, exactly as the app does it. Quoted for
        // schtasks, which takes the whole command as one argument and would
        // otherwise stop at the first space in a teacher's folder name.
        string launcher = Path.Combine(workingFolder, "deploy.ps1");
        if (!File.Exists(launcher))
            return $"There is no deploy.ps1 in {workingFolder}, so there is nothing to schedule.";

        string argString = deployArguments != null && deployArguments.Count > 0
            ? string.Join(" ", deployArguments)
            : $"{courseCode} {section}";

        string command =
            $"powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\\"{launcher}\\\" " +
            argString;

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

    /// <summary>Remove a scheduled deploy. Returns null on success.</summary>
    public static string? Cancel(string taskName)
    {
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

using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// A stand-in for Task Scheduler AND for the folder the job files live in, so
/// a test can schedule, list, cancel and run deploys without touching the real
/// scheduler or the teacher's <c>%LOCALAPPDATA%\Plantoir\scheduled</c>.
/// </summary>
/// <remarks>
/// Process-wide (it sets <see cref="TaskScheduling.SchtasksForTests"/> and
/// <see cref="TaskScheduling.ScheduledDirectoryForTests"/>), so every class
/// that uses one belongs in the <c>SharedActivityState</c> collection, and
/// disposing it puts both back.
/// </remarks>
internal sealed class FakeScheduler : IDisposable
{
    /// <summary>Registered task names, and what "Next Run Time" says for each.</summary>
    public Dictionary<string, string> Tasks { get; } = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Every name /Delete was asked for, in order.</summary>
    public List<string> Deleted { get; } = new();

    /// <summary>Every /Create, as its arguments.</summary>
    public List<IReadOnlyList<string>> Created { get; } = new();

    /// <summary>The task definition each /Create /XML carried, read at the moment of the call.</summary>
    public List<string> CreatedXml { get; } = new();

    /// <summary>What the task's job file said at the moment each /Create was called.</summary>
    public List<string?> JobAtCreate { get; } = new();

    public bool DeletingFails { get; set; }
    public bool CreatingFails { get; set; }

    public string Directory { get; }

    public FakeScheduler(string root)
    {
        Directory = Path.Combine(root, "scheduled-state");
        System.IO.Directory.CreateDirectory(Directory);
        TaskScheduling.ScheduledDirectoryForTests = Directory;
        TaskScheduling.RunnerExecutableForTests = @"C:\Program Files\Plantoir\Plantoir.exe";
        TaskScheduling.SchtasksForTests = Answer;
    }

    public void Dispose()
    {
        TaskScheduling.SchtasksForTests = null;
        TaskScheduling.ScheduledDirectoryForTests = null;
        TaskScheduling.RunnerExecutableForTests = null;
    }

    /// <summary>A task set since bundle 3: its job file names its folder.</summary>
    public string AddNew(string workingFolder, string course, int section, DateTimeOffset? when = null,
                         params string[] promised)
    {
        string name = TaskScheduling.NameFor(course, section, workingFolder);
        File.WriteAllText(TaskScheduling.JobPath(name), ScheduledRun.WriteJob(
            new ScheduledRun.Job(name, workingFolder, course, section, when ?? DateTimeOffset.Now.AddDays(1), promised)));
        Tasks[name] = "10/1/2026 6:30:00 AM";
        return name;
    }

    /// <summary>A task set before #309: the old name, and a wrapper naming its folder.</summary>
    public string AddOld(string workingFolder, string course, int section)
    {
        string name = TaskScheduling.OldNameFor(course, section);
        File.WriteAllText(TaskScheduling.WrapperScriptPath(name),
            $"$toolchainScripts = Join-Path '{workingFolder.Replace("'", "''")}' '.toolchain\\scripts'\n" +
            $"    Set-Content -LiteralPath $outcomeFile -Value @($kind, $where, '{course}', '{section}') -Encoding utf8\n");
        Tasks[name] = "10/1/2026 6:30:00 AM";
        return name;
    }

    private (int ExitCode, string Output) Answer(IReadOnlyList<string> arguments)
    {
        string name = Named(arguments);
        if (arguments.Contains("/Create"))
        {
            Created.Add(arguments);
            int xml = arguments.ToList().IndexOf("/XML");
            if (xml >= 0) CreatedXml.Add(File.ReadAllText(arguments[xml + 1]));
            string job = TaskScheduling.JobPath(name);
            JobAtCreate.Add(File.Exists(job) ? File.ReadAllText(job) : null);
            if (CreatingFails) return (1, "ERROR: Access is denied.");
            Tasks[name] = "10/1/2026 6:30:00 AM";
            return (0, "SUCCESS");
        }
        if (arguments.Contains("/Delete"))
        {
            if (DeletingFails) return (1, "ERROR: Access is denied.");
            Deleted.Add(name);
            return Tasks.Remove(name) ? (0, "SUCCESS") : (1, "ERROR: The system cannot find the file specified.");
        }
        if (arguments.Contains("/Query") && arguments.Contains("CSV"))
        {
            string csv = string.Join("\n", Tasks.Select(task => $"\"\\{task.Key}\",\"{task.Value}\",\"Ready\""));
            return (0, csv);
        }
        if (arguments.Contains("/Query"))
            return Tasks.ContainsKey(name) ? (0, "") : (1, "ERROR: The system cannot find the file specified.");
        return (1, "unexpected call");
    }

    private static string Named(IReadOnlyList<string> arguments)
    {
        int at = arguments.ToList().IndexOf("/TN");
        return at >= 0 && at + 1 < arguments.Count ? arguments[at + 1] : "";
    }

    /// <summary>A working folder with a course in it, as the run and the removal read one.</summary>
    public static string WorkingFolderWith(string root, string name, string course, string configJson)
    {
        string folder = Path.Combine(root, name);
        string courseDir = Path.Combine(folder, "courses", course);
        System.IO.Directory.CreateDirectory(courseDir);
        File.WriteAllText(Path.Combine(courseDir, "course_config.json"), configJson);
        File.WriteAllText(Path.Combine(folder, "deploy.ps1"), "# stub");
        File.WriteAllText(Path.Combine(folder, "preview.ps1"), "# stub");
        return folder;
    }
}

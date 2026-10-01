using System.Diagnostics;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// Bundle 3 fix round, ruling 1: the task a scheduled deploy registers starts on
/// battery, is not stopped by unplugging, and runs a missed start as soon as it
/// can. Ruling 3: the job is in place before the task is replaced, and a run
/// tells its own setting from a later one by a token, not by the moment.
/// </summary>
[Collection(SharedActivityState.Name)]
public class TaskDefinitionTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-taskdef").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_root, true); } catch { }
    }

    private static void HasTheThreeSettings(string xml)
    {
        Assert.Contains("<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>", xml);
        Assert.Contains("<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>", xml);
        Assert.Contains("<StartWhenAvailable>true</StartWhenAvailable>", xml);
    }

    [Fact]
    public void SchedulingRegistersATaskThatRunsOnBatteryAndAfterAMissedStart()
    {
        using var scheduler = new FakeScheduler(_root);
        string folder = FakeScheduler.WorkingFolderWith(_root, "work", "ICS3U", "{}");
        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, DateTime.Now.AddDays(1), [new("netlify", "")]));
        HasTheThreeSettings(Assert.Single(scheduler.CreatedXml));
    }

    /// <summary>
    /// Through <see cref="TaskScheduling.Schedule"/> itself (ruling 7), against
    /// the REAL Task Scheduler, read back — what Windows keeps, not what was
    /// sent. The job folder is a test folder; the course is a probe
    /// (PARITYPROBE) in a temp working folder; the task is cancelled after.
    /// </summary>
    [Fact]
    public void TheRegisteredTaskKeepsTheThreeSettingsAndCarriesItsToken()
    {
        if (!OperatingSystem.IsWindows()) return;
        string folder = FakeScheduler.WorkingFolderWith(_root, "probe", "PARITYPROBE", "{}");
        TaskScheduling.ScheduledDirectoryForTests = Path.Combine(_root, "jobs");
        TaskScheduling.RunnerExecutableForTests = @"C:\Windows\System32\cmd.exe";
        string name = TaskScheduling.NameFor("PARITYPROBE", 1, folder);
        try
        {
            Assert.Null(TaskScheduling.Schedule(folder, "PARITYPROBE", 1, DateTime.Now.AddDays(1), [new("netlify", "")]));
            var (_, back) = Schtasks("/Query", "/TN", name, "/XML");
            HasTheThreeSettings(back);
            string token = ScheduledRun.ReadJob(TaskScheduling.JobPath(name))!.Token;
            Assert.Contains($"{TaskScheduling.TokenArgument} {token}", back);
        }
        finally
        {
            Schtasks("/Delete", "/F", "/TN", name);
            TaskScheduling.ScheduledDirectoryForTests = null;
            TaskScheduling.RunnerExecutableForTests = null;
            TaskScheduling.ForgetTheList();
            Assert.NotEqual(0, Schtasks("/Query", "/TN", name).Exit);
        }
    }

    [Fact]
    public void ARunWhoseTaskCarriesAnotherTokenDoesNothingAndLeavesTheTask()
    {
        using var scheduler = new FakeScheduler(_root);
        string folder = FakeScheduler.WorkingFolderWith(_root, "crash", "ICS3U",
            """{ "course_code": "ICS3U", "section_numbers": [1], "deploy_target": "netlify" }""");
        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, DateTime.Now, [new("netlify", "")]));
        string name = TaskScheduling.NameFor("ICS3U", 1, folder);
        var ran = new List<string>();
        var world = new ScheduledRun.World
        {
            Now = () => DateTimeOffset.Now, Sleep = _ => { }, CloudflareAccountID = () => "",
            OutcomeDirectory = Path.Combine(_root, "outcomes"),
            RunWrapper = script => { ran.Add(script); return 0; },
        };
        // The OLD task (another token) finding the NEW job after a crash.
        Assert.Equal(ScheduledRun.Ending.NoLongerStands,
            ScheduledRun.Execute(TaskScheduling.JobPath(name), world, taskToken: "an-older-setting"));
        Assert.Empty(ran);
        Assert.Contains(name, scheduler.Tasks.Keys);
        Assert.Empty(scheduler.Deleted);
    }

    /// <summary>
    /// The MATCHING-token path (bundle 4 fix review M1, ruling 9): Schedule()
    /// registers the task, the command line is read back out of the task's own
    /// XML and parsed as Program.Main parses it, and the run carrying the job's
    /// OWN token deploys and clears the one-shot task. A mutant that refuses
    /// every token-carrying run used to survive.
    /// </summary>
    [Fact]
    public void ARunCarryingItsJobsOwnTokenDeploysAndClearsTheTask()
    {
        using var scheduler = new FakeScheduler(_root);
        string folder = FakeScheduler.WorkingFolderWith(_root, "own", "ICS3U",
            """{ "course_code": "ICS3U", "section_numbers": [1], "deploy_target": "netlify" }""");
        string marker = Path.Combine(folder, "courses", "ICS3U", ".netlify_sites", "section1.json");
        Directory.CreateDirectory(Path.GetDirectoryName(marker)!);
        File.WriteAllText(marker, """{ "site_id": "x", "site_name": "ics3u-s1" }""");
        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, DateTime.Now, [new("netlify", "")]));
        string name = TaskScheduling.NameFor("ICS3U", 1, folder);

        // The task's Arguments, as registered, split the way a command line is.
        var arguments = System.Text.RegularExpressions.Regex.Match(scheduler.CreatedXml.Last(), "<Arguments>(.*?)</Arguments>").Groups[1].Value
            .Replace("&quot;", "\"").Replace("&amp;", "&");
        var argv = System.Text.RegularExpressions.Regex.Matches(arguments, "\"([^\"]*)\"|(\\S+)")
            .Select(m => m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value).ToArray();
        var parsed = TaskScheduling.ScheduledRunFrom(argv);
        Assert.NotNull(parsed);
        Assert.Equal(TaskScheduling.JobPath(name), parsed!.Value.JobPath);
        Assert.Equal(ScheduledRun.ReadJob(TaskScheduling.JobPath(name))!.Token, parsed.Value.Token);

        var ran = new List<string>();
        var world = new ScheduledRun.World
        {
            Now = () => DateTimeOffset.Now, Sleep = _ => { }, CloudflareAccountID = () => "",
            OutcomeDirectory = Path.Combine(_root, "outcomes"),
            RunWrapper = script => { ran.Add(script); return 0; },
        };
        Assert.Equal(ScheduledRun.Ending.Deployed,
            ScheduledRun.Execute(parsed.Value.JobPath, world, taskToken: parsed.Value.Token));
        Assert.Single(ran);
        Assert.DoesNotContain(name, scheduler.Tasks.Keys);   // one-shot: cleared after it ran
    }

    [Fact]
    public void TheScheduledRunsCommandLineIsParsedAsTheTaskWritesIt()
    {
        Assert.Null(TaskScheduling.ScheduledRunFrom(new[] { "--state-dir", "x" }));
        Assert.Null(TaskScheduling.ScheduledRunFrom(new[] { TaskScheduling.RunArgument }));
        var noToken = TaskScheduling.ScheduledRunFrom(new[] { TaskScheduling.RunArgument, "Plantoir deploy ICS3U section 1" })!.Value;
        Assert.Equal(TaskScheduling.JobPath("Plantoir deploy ICS3U section 1"), noToken.JobPath);
        Assert.Null(noToken.Token);
        var withToken = TaskScheduling.ScheduledRunFrom(new[] { TaskScheduling.RunArgument, @"C:\x\a.job.json", TaskScheduling.TokenArgument, "abc123" })!.Value;
        Assert.Equal(@"C:\x\a.job.json", withToken.JobPath);
        Assert.Equal("abc123", withToken.Token);
        Assert.Null(TaskScheduling.ScheduledRunFrom(new[] { TaskScheduling.RunArgument, "n", TaskScheduling.TokenArgument })!.Value.Token);
    }

    [Fact]
    public void TheJobIsInPlaceBeforeTheTaskIsReplaced()
    {
        using var scheduler = new FakeScheduler(_root);
        string folder = FakeScheduler.WorkingFolderWith(_root, "work", "ICS3U", "{}");
        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, DateTime.Now.AddDays(1), [new("netlify", "")]));
        string atCreate = Assert.Single(scheduler.JobAtCreate)!;
        var job = ScheduledRun.ReadJob(TaskScheduling.JobPath(TaskScheduling.NameFor("ICS3U", 1, folder)))!;
        Assert.NotEmpty(job.Token);
        Assert.Contains(job.Token, atCreate);
    }

    [Fact]
    public void ARefusedTaskPutsTheOldJobBack()
    {
        using var scheduler = new FakeScheduler(_root);
        string folder = FakeScheduler.WorkingFolderWith(_root, "work", "ICS3U", "{}");
        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, DateTime.Now.AddDays(1), [new("netlify", "")]));
        string path = TaskScheduling.JobPath(TaskScheduling.NameFor("ICS3U", 1, folder));
        string before = File.ReadAllText(path);
        scheduler.CreatingFails = true;
        Assert.NotNull(TaskScheduling.Schedule(folder, "ICS3U", 1, DateTime.Now.AddDays(2), [new("netlify", "")]));
        Assert.Equal(before, File.ReadAllText(path));
    }

    [Fact]
    public void ADeploySetAgainForTheSameMinuteWhileTheRunWorksIsNotClearedByIt()
    {
        using var scheduler = new FakeScheduler(_root);
        string folder = FakeScheduler.WorkingFolderWith(_root, "same", "ICS3U",
            """{ "course_code": "ICS3U", "section_numbers": [1], "deploy_target": "netlify" }""");
        Directory.CreateDirectory(Path.Combine(folder, "courses", "ICS3U", ".netlify_sites"));
        File.WriteAllText(Path.Combine(folder, "courses", "ICS3U", ".netlify_sites", "section1.json"), "{}");
        var moment = DateTimeOffset.Now;
        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, moment.LocalDateTime, [new("netlify", "")]));
        string name = TaskScheduling.NameFor("ICS3U", 1, folder);
        var world = new ScheduledRun.World
        {
            Now = () => moment, Sleep = _ => { }, CloudflareAccountID = () => "",
            OutcomeDirectory = Path.Combine(_root, "outcomes"),
            RunWrapper = _ =>
            {
                // Set again for the very same minute: a different deploy, same name, same moment.
                Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, moment.LocalDateTime, [new("netlify", "")]));
                return 0;
            },
        };
        Assert.Equal(ScheduledRun.Ending.Deployed, ScheduledRun.Execute(TaskScheduling.JobPath(name), world));
        Assert.Contains(name, scheduler.Tasks.Keys);
        Assert.Empty(scheduler.Deleted);
    }

    private static (int Exit, string Output) Schtasks(params string[] arguments)
    {
        var info = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "schtasks.exe"))
        { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (string a in arguments) info.ArgumentList.Add(a);
        using var p = Process.Start(info)!;
        string output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
        p.WaitForExit();
        return (p.ExitCode, output);
    }
}

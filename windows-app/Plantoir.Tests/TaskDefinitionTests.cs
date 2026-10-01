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
    /// The definition, registered with the REAL Task Scheduler under a probe
    /// name and read back — what Windows keeps, not what was sent. Deleted after.
    /// </summary>
    [Fact]
    public void TheRegisteredTaskKeepsTheThreeSettings()
    {
        if (!OperatingSystem.IsWindows()) return;
        string name = "PlantoirParityProbe-" + Guid.NewGuid().ToString("N")[..8];
        string xmlPath = Path.Combine(_root, "task.xml");
        File.WriteAllText(xmlPath, TaskScheduling.TaskXml(@"C:\Windows\System32\cmd.exe", name, DateTime.Now.AddDays(1)),
            System.Text.Encoding.Unicode);
        try
        {
            var (created, said) = Schtasks("/Create", "/F", "/TN", name, "/XML", xmlPath);
            Assert.True(created == 0, said);
            var (_, back) = Schtasks("/Query", "/TN", name, "/XML");
            HasTheThreeSettings(back);
        }
        finally
        {
            Schtasks("/Delete", "/F", "/TN", name);
            Assert.NotEqual(0, Schtasks("/Query", "/TN", name).Exit);
        }
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

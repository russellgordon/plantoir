using System.Globalization;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #261 (the mac's #195): scheduling a section that already has a deploy set
/// REPLACES it, and the card, the dialog and the tool's result say so before;
/// the trail records it after; a failure says what it left.
/// </summary>
[Collection(SharedActivityState.Name)]
public class ScheduleReplacesTests : IDisposable
{
    private static readonly IReadOnlyList<Plantoir.Core.Models.CourseConfiguration.DeployDestination> Netlify =
        [new("netlify", "")];

    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-replaces").FullName;
    private readonly string _trail;
    private readonly FakeScheduler _scheduler;

    public ScheduleReplacesTests()
    {
        _trail = Path.Combine(_root, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        _scheduler = new FakeScheduler(_root);
        TaskScheduling.ForgetTheList();
    }

    public void Dispose()
    {
        _scheduler.Dispose();
        TaskScheduling.ForgetTheList();
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_root, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    private string Folder(string name)
    {
        string folder = Path.Combine(_root, name);
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "deploy.ps1"), "# marker");
        return folder;
    }

    private static DateTime Minute(DateTime moment) =>
        new(moment.Year, moment.Month, moment.Day, moment.Hour, moment.Minute, 0);

    private string Trail() => File.Exists(_trail) ? File.ReadAllText(_trail) : "";

    private static string Stamp(DateTime moment) => moment.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);

    [Fact]
    public void ADeployAlreadySetHereIsNamedAndTheReplacementIsRecorded()
    {
        string folder = Folder("here");
        var old = Minute(DateTime.Now.AddDays(2));
        string name = _scheduler.AddNew(folder, "ICS3U", 1, new DateTimeOffset(old));
        _scheduler.Tasks[name] = "N/A";   // Windows says nothing; the job does
        var wanted = Minute(DateTime.Now.AddDays(1));

        Assert.Equal(old, TaskScheduling.MomentItWouldReplace(folder, "ICS3U", 1, wanted, DateTime.Now));

        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, wanted, Netlify));
        Assert.Contains($"replaced the deploy set for {Stamp(old)} with one set for {Stamp(wanted)}", Trail());
    }

    /// <summary>
    /// The trap: a task whose JOB cannot be read belongs to no folder for the
    /// cancel path's filter — and <c>/Create /F</c> replaces it anyway. Read by
    /// name, it is still named.
    /// </summary>
    [Fact]
    public void ADeployWhoseJobCannotBeReadIsStillNamedBecauseItIsReadByName()
    {
        string folder = Folder("unreadable job");
        var old = Minute(DateTime.Now.AddDays(3));
        string name = _scheduler.AddNew(folder, "ICS3U", 1, new DateTimeOffset(old));
        File.Delete(TaskScheduling.JobPath(name));
        _scheduler.Tasks[name] = old.ToString(CultureInfo.CurrentCulture);

        Assert.Null(TaskScheduling.For(folder, "ICS3U", 1));   // the folder filter cannot see it
        Assert.NotNull(TaskScheduling.MomentItWouldReplace(folder, "ICS3U", 1, DateTime.Now.AddDays(1), DateTime.Now));
    }

    [Fact]
    public void AnotherFoldersDeployIsNotReplacedSoIsNotNamed()
    {
        string here = Folder("this year");
        _scheduler.AddNew(Folder("last year"), "ICS3U", 1, DateTimeOffset.Now.AddDays(2));
        Assert.Null(TaskScheduling.MomentItWouldReplace(here, "ICS3U", 1, DateTime.Now.AddDays(1), DateTime.Now));
    }

    [Fact]
    public void TheSameMinuteOrAPassedOneIsNotMentioned()
    {
        string folder = Folder("same");
        var old = Minute(DateTime.Now.AddDays(2));
        string name = _scheduler.AddNew(folder, "ICS3U", 1, new DateTimeOffset(old));
        _scheduler.Tasks[name] = "N/A";

        Assert.Null(TaskScheduling.MomentItWouldReplace(folder, "ICS3U", 1, old, DateTime.Now));
        Assert.Null(TaskScheduling.MomentItWouldReplace(folder, "ICS3U", 1, old.AddDays(1), old.AddMinutes(1)));
    }

    /// <summary>A refused write leaves the old one standing, and says so — never "turned off".</summary>
    [Fact]
    public void AFailedScheduleSaysTheOldOneStillStands()
    {
        string folder = Folder("refused");
        var old = Minute(DateTime.Now.AddDays(2));
        string name = _scheduler.AddNew(folder, "ICS3U", 1, new DateTimeOffset(old));
        _scheduler.Tasks[name] = "N/A";
        _scheduler.CreatingFails = true;

        string? problem = TaskScheduling.Schedule(folder, "ICS3U", 1, Minute(DateTime.Now.AddDays(1)), Netlify);

        Assert.NotNull(problem);
        Assert.Contains("still stands", problem);
        Assert.Contains($"the deploy already set for {Stamp(old)} still stands", Trail());
        Assert.DoesNotContain("turned off", Trail());
        Assert.Contains(name, _scheduler.Tasks.Keys);
    }

    /// <summary>The approval card says it, from the question the window answers.</summary>
    [Fact]
    public async Task TheScheduledCardSaysWhatItReplaces()
    {
        var was = new DateTime(2026, 9, 25, 6, 30, 0);
        var agent = new AssistAgent(new WindowBindingContractTests.ScriptedModel(),
                                    new WindowBindingContractTests.RecordingTools(), new JsonArray(), "ICS3U", 1)
        {
            Today = () => new DateOnly(2026, 9, 19),
            Now = () => new DateTime(2026, 9, 19, 9, 0, 0),
            TimeZone = TimeZoneInfo.Utc,
            ScheduleDeployItWouldReplace = _ => was,
        };

        var lines = await agent.Say("deploy at 6:30 am", CancellationToken.None);

        Assert.EndsWith(AssistWording.ScheduleReplaces(was.ToString("dddd d MMMM, h:mm tt")), lines[0].Text);
    }
}

using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>scheduledDeployCancellation</c> on Windows:
/// which acts turn a scheduled deploy off (#239), one alarm per working
/// folder (#309), and the sentences a teacher reads. Played through the real
/// removal, rename, rollover and scheduling code against a stand-in
/// scheduler — never the real one, whose ICS3U section 1 may be a teacher's.
/// </summary>
[Collection(SharedActivityState.Name)]
public class ScheduledDeployCancellationTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-cancel").FullName;
    private readonly FakeScheduler _scheduler;

    public ScheduledDeployCancellationTests() => _scheduler = new FakeScheduler(_root);

    public void Dispose()
    {
        _scheduler.Dispose();
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static JsonNode Cancellation => ContractLoader.LoadJson("shared-rules.json")["scheduledDeployCancellation"]!;

    private string Folder(string name, params int[] sections) =>
        FakeScheduler.WorkingFolderWith(_root, name, "ICS3U",
            $$"""{ "course_code": "ICS3U", "section_numbers": [{{string.Join(",", sections)}}], "deploy_target": "netlify" }""");

    private static Course CourseIn(string folder) =>
        ScheduledRun.ReadCourse(folder, "ICS3U")!;

    private static string Courses(string folder) => Path.Combine(folder, "courses");

    // ---- cases[] with provedBy "run" -----------------------------------------

    /// <summary>
    /// Every case the contract proves by running an act is named here, by its
    /// act, against the test that plays it — so a case added on the mac fails
    /// this test by name until somebody plays it here.
    /// </summary>
    private static readonly Dictionary<string, string> PlayedBy = new()
    {
        ["a course kept for reference is met when the working folder is read"] =
            "NOT PLAYED: this app keeps no course for reference yet (#241). The run refuses one (keptForReference), which is the backstop.",
        ["remove one section of a course that has more than one"] = nameof(RemovingOneSectionTurnsOffThatSectionOnly),
        ["remove a whole course"] = nameof(RemovingACourseTurnsOffEveryDeployThisFolderHasForItAskedOfTheScheduler),
        ["remove the only section of a course"] = nameof(RemovingACourseTurnsOffEveryDeployThisFolderHasForItAskedOfTheScheduler),
        ["remove a course whose code also exists in another working folder"] = nameof(AnotherFoldersDeployOfTheSameCourseIsNeverTouched),
        ["rename a course"] = nameof(RenamingACourseTurnsOffThisFoldersDeploysByTheirRealNames),
        ["roll a section over onto a new website"] = "RolloverWebsiteTests.StartingANewWebsiteTurnsOffAScheduledPublish",
        ["schedule a section whose code and number another working folder has also scheduled"] = nameof(SchedulingLeavesAnotherFoldersDeployStanding),
        ["schedule a section this working folder has already scheduled"] = nameof(SchedulingAgainReplacesThisFoldersOwn),
        ["schedule a section this working folder scheduled before deploys were kept per working folder"] = nameof(AnOldNamedDeployIsRetiredOnlyAfterTheNewOneIsAccepted),
        ["remove a course that another working folder has also scheduled"] = nameof(AnotherFoldersDeployOfTheSameCourseIsNeverTouched),
        ["remove a course whose deploy was scheduled before deploys were kept per working folder"] = nameof(AnOldNamedDeployIsCancelledByTheNameItReallyHas),
    };

    [Fact]
    public void EveryRunCaseInTheContractIsPlayedHere()
    {
        var acts = Cancellation["cases"]!.AsArray()
            .Where(c => c!["provedBy"]!.ToString() == "run")
            .Select(c => c!["act"]!.ToString())
            .ToList();
        var missing = acts.Where(act => !PlayedBy.ContainsKey(act)).ToList();
        Assert.True(missing.Count == 0, "Cases nobody plays on Windows: " + string.Join("; ", missing));
        var stale = PlayedBy.Keys.Where(act => !acts.Contains(act)).ToList();
        Assert.True(stale.Count == 0, "Played here but gone from the contract: " + string.Join("; ", stale));
    }

    [Fact]
    public void RemovingACourseTurnsOffEveryDeployThisFolderHasForItAskedOfTheScheduler()
    {
        string folder = Folder("this year", 1);
        string one = _scheduler.AddNew(folder, "ICS3U", 1);
        // Section 2 was removed on an earlier build and LEFT its task behind;
        // the settings no longer list it, so only the scheduler knows.
        string leftBehind = _scheduler.AddNew(folder, "ICS3U", 2);

        CourseArchiver.ArchiveAndRemoveCourse(CourseIn(folder), Courses(folder));

        Assert.Contains(one, _scheduler.Deleted);
        Assert.Contains(leftBehind, _scheduler.Deleted);
        Assert.False(Directory.Exists(Path.Combine(Courses(folder), "ICS3U")));
    }

    [Fact]
    public void RemovingOneSectionTurnsOffThatSectionOnly()
    {
        string folder = Folder("two sections", 1, 2);
        Directory.CreateDirectory(Path.Combine(Courses(folder), "ICS3U", "section2"));
        string one = _scheduler.AddNew(folder, "ICS3U", 1);
        string two = _scheduler.AddNew(folder, "ICS3U", 2);

        CourseArchiver.ArchiveAndRemoveSection(CourseIn(folder), 2, Courses(folder));

        Assert.Equal(new[] { two }, _scheduler.Deleted);
        Assert.Contains(one, _scheduler.Tasks.Keys);
    }

    [Fact]
    public void AnotherFoldersDeployOfTheSameCourseIsNeverTouched()
    {
        string thisYear = Folder("this year", 1);
        string lastYear = Folder("last year", 1);
        string mine = _scheduler.AddNew(thisYear, "ICS3U", 1);
        string theirs = _scheduler.AddNew(lastYear, "ICS3U", 1);

        CourseArchiver.ArchiveAndRemoveCourse(CourseIn(thisYear), Courses(thisYear));

        Assert.Equal(new[] { mine }, _scheduler.Deleted);
        Assert.Contains(theirs, _scheduler.Tasks.Keys);
    }

    [Fact]
    public void AnOldNamedDeployIsCancelledByTheNameItReallyHas()
    {
        string folder = Folder("before the update", 1);
        string old = _scheduler.AddOld(folder, "ICS3U", 1);

        CourseArchiver.ArchiveAndRemoveCourse(CourseIn(folder), Courses(folder));

        Assert.Equal(new[] { old }, _scheduler.Deleted);
    }

    [Fact]
    public void AFailedCancelRemovesNothingAndSaysTheContractsSentence()
    {
        string folder = Folder("stuck", 1);
        _scheduler.AddNew(folder, "ICS3U", 1);
        _scheduler.DeletingFails = true;

        var refused = Assert.Throws<ScheduledDeployRemoval.StillScheduledException>(() =>
            CourseArchiver.ArchiveAndRemoveCourse(CourseIn(folder), Courses(folder)));

        Assert.True(Directory.Exists(Path.Combine(Courses(folder), "ICS3U")), "the course was removed anyway");
        Assert.Equal(Wording("couldNotTurnItOffOneSection").Replace("{sections}", "Section 1").Replace("{course}", "ICS3U"),
                     refused.Message);
    }

    [Fact]
    public void ARemovalThatFailsAfterTheCancelSaysTheDeployStaysOff()
    {
        string folder = Folder("locked", 1);
        _scheduler.AddNew(folder, "ICS3U", 1);
        var course = CourseIn(folder);
        // A removal that cannot happen: the courses directory given is not where the course is.
        string wrong = Path.Combine(_root, "no such place", "courses");

        var failed = Assert.ThrowsAny<Exception>(() => CourseArchiver.ArchiveAndRemoveSection(course, 1, Courses(folder) + "-missing"));
        Assert.StartsWith(Wording("removalFailedAfterTurningItOffOneSection")
                              .Replace("{sections}", "Section 1").Replace("{course}", "ICS3U")
                              .Split("{reason}")[0],
                          failed.Message);
        Assert.NotEmpty(_scheduler.Deleted);
        _ = wrong;
    }

    [Fact]
    public void RenamingACourseTurnsOffThisFoldersDeploysByTheirRealNames()
    {
        string folder = Folder("renaming", 1);
        string old = _scheduler.AddOld(folder, "ICS3U", 1);
        string other = _scheduler.AddNew(Folder("elsewhere", 1), "ICS3U", 1);

        var outcome = CourseRenamer.Rename(CourseIn(folder), "ICS3X", Courses(folder), new[] { "ICS3U" });

        Assert.Equal(new[] { 1 }, outcome.StoppedScheduledSections);
        Assert.Equal(new[] { old }, _scheduler.Deleted);
        Assert.Contains(other, _scheduler.Tasks.Keys);
    }

    [Fact]
    public void SchedulingAgainReplacesThisFoldersOwn()
    {
        string folder = Folder("again", 1);
        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, DateTime.Now.AddDays(1), Netlify));
        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, DateTime.Now.AddDays(2), Netlify));

        Assert.Single(_scheduler.Tasks.Keys, name => name.StartsWith("Plantoir deploy ICS3U section 1"));
        Assert.Equal(DateTimeOffset.Now.AddDays(2).Date,
            ScheduledRun.ReadJob(TaskScheduling.JobPath(TaskScheduling.NameFor("ICS3U", 1, folder)))!.ScheduledFor!.Value.LocalDateTime.Date);
    }

    [Fact]
    public void SchedulingLeavesAnotherFoldersDeployStanding()
    {
        string thisYear = Folder("this year", 1);
        string theirs = _scheduler.AddNew(Folder("last year", 1), "ICS3U", 1);

        Assert.Null(TaskScheduling.Schedule(thisYear, "ICS3U", 1, DateTime.Now.AddDays(1), Netlify));

        Assert.Contains(theirs, _scheduler.Tasks.Keys);
        Assert.Contains(TaskScheduling.NameFor("ICS3U", 1, thisYear), _scheduler.Tasks.Keys);
        Assert.Empty(_scheduler.Deleted);
    }

    [Fact]
    public void AnOldNamedDeployIsRetiredOnlyAfterTheNewOneIsAccepted()
    {
        string folder = Folder("upgraded", 1);
        string old = _scheduler.AddOld(folder, "ICS3U", 1);

        _scheduler.CreatingFails = true;
        Assert.NotNull(TaskScheduling.Schedule(folder, "ICS3U", 1, DateTime.Now.AddDays(1), Netlify));
        Assert.Contains(old, _scheduler.Tasks.Keys);            // a refusal hands it back
        Assert.Empty(_scheduler.Deleted);

        _scheduler.CreatingFails = false;
        Assert.Null(TaskScheduling.Schedule(folder, "ICS3U", 1, DateTime.Now.AddDays(1), Netlify));
        Assert.Equal(new[] { old }, _scheduler.Deleted);         // retired once the new one stands
    }

    [Fact]
    public void AFolderSeesOnlyItsOwnDeploysAndTheNewOneWinsOverAnOldOne()
    {
        string folder = Folder("mine", 1);
        _scheduler.AddOld(folder, "ICS3U", 1);
        string mine = _scheduler.AddNew(folder, "ICS3U", 1);
        _scheduler.AddNew(Folder("theirs", 1), "ICS3U", 1);

        Assert.Equal(2, TaskScheduling.InFolder(folder).Count);
        Assert.Equal(mine, TaskScheduling.For(folder, "ics3u", 1)!.Name);
    }

    // ---- cases[] with provedBy "sourceHasNoCancel" ---------------------------

    [Fact]
    public void RestoringAndDeletingBackupsTurnNoScheduledDeployOff()
    {
        // The mac's cases name mac source files; the rule — a restore ADDS or
        // replaces contents in place, a deleted zip changes no live course —
        // is checked against this app's own. It cannot prove the act harmless,
        // only that nobody has since taught it to cancel.
        string core = Path.Combine(RepoRoot(), "windows-app", "Plantoir.Core", "Models");
        foreach (string file in new[] { "CourseRestorer.cs" })
        {
            string text = File.ReadAllText(Path.Combine(core, file));
            Assert.DoesNotContain("TaskScheduling.Cancel", text);
            Assert.DoesNotContain("CancelFor(", text);
            Assert.DoesNotContain("ScheduledDeployRemoval", text);
        }
    }

    // ---- The sentences --------------------------------------------------------

    private static string Wording(string key) => Cancellation["wording"]![key]!.ToString();

    [Fact]
    public void EverySentenceIsTheContractsOwn()
    {
        Assert.Equal(Wording("confirmationSectionRemoved").Replace("{section}", "2"),
                     ScheduledDeployRemoval.ConfirmationSectionRemoved(2));
        Assert.Equal(Wording("confirmationCourseRemovedOneSection").Replace("{sections}", "Section 1").Replace("{course}", "ICS3U"),
                     ScheduledDeployRemoval.ConfirmationCourseRemoved("ICS3U", [1]));
        Assert.Equal(Wording("confirmationCourseRemovedSeveralSections").Replace("{sections}", "Sections 1 and 2").Replace("{course}", "ICS3U"),
                     ScheduledDeployRemoval.ConfirmationCourseRemoved("ICS3U", [1, 2]));
        Assert.Equal(Wording("couldNotTurnItOffSeveralSections").Replace("{sections}", "Sections 1, 2 and 3").Replace("{course}", "ICS3U"),
                     ScheduledDeployRemoval.CouldNotTurnItOff("ICS3U", [1, 2, 3]));
        Assert.Equal(Wording("removalFailedAfterTurningItOffSeveralSections").Replace("{sections}", "Sections 1 and 2")
                         .Replace("{course}", "ICS3U").Replace("{reason}", "the disk is full"),
                     ScheduledDeployRemoval.RemovalFailedAfterTurningItOff("ICS3U", [1, 2], "the disk is full"));
    }

    private static readonly CourseConfiguration.DeployDestination[] Netlify = [new("netlify", "")];

    private static string RepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "windows-app", "Plantoir.Core"))) dir = dir.Parent;
        return dir!.FullName;
    }
}

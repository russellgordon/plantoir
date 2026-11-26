using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7b2-7: a record a sheet writes to remember a teacher's answer is
/// ONE step of that one file, made by <c>sheet</c>, never told to today's
/// undo, with Windows' own bytes: Not Today
/// (<see cref="AssistWorkspace.DeclineTodaysClass"/>, key
/// <c>notTodayOnTheFrontPage</c>) and the classes dated later kept at Deploy
/// (<see cref="LaterClassesKept.KeepAtDeploy(string?, string, string, int, IEnumerable{ClassesDatedLater.Page}, DateTime?, string?)"/>,
/// key <c>keepClassesDatedLater</c>), as the mac's <c>NotToday.write</c> and
/// <c>KeptRecord.write</c>. A record that cannot be written costs only the
/// record. Laid out on the mac's fixture
/// (<see cref="WindowsActionsOnTheMacFixture.Lay"/>). <c>Keep</c> planned
/// inside Publish Class for a Date's step makes no step of its own: W7a's
/// <c>UndoWholeUnitAndByDateStepTests.PublishClassForADateKeepsTheClassItPublishesInTheSameStep</c>.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class UndoSheetRecordStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private const string NotTodayKey = "notTodayOnTheFrontPage";
    private const string KeptKey = "keepClassesDatedLater";
    private const string Course = WindowsActionsOnTheMacFixture.Course;
    private static readonly DateOnly Morning = new(2026, 9, 30);
    private static readonly DateTime Answered = new(2026, 9, 8, 11, 0, 0, DateTimeKind.Utc);

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-sheet-records-");
    private readonly string _trail;

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string CourseDirectory => Path.Combine(Folder, "courses", Course);
    private string NotTodayRecord => UndoDoor.FullPath(Folder, "courses/ICS3U/.publish_state/section1.front-page-not-today.json");
    private string KeptRecord => UndoDoor.FullPath(Folder, "courses/ICS3U/.publish_state/section1.later-classes-kept.json");

    // ---- Initializer ---------------------------------------------------------------

    public UndoSheetRecordStepTests()
    {
        _trail = Path.Combine(_root, "trail.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        // Both recorded steps lay the mac's section; their one file is new.
        WindowsActionsOnTheMacFixture.Lay(Folder, WindowsActionsOnTheMacFixture.Recorded(NotTodayKey));
    }

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(null);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private UndoForThisProcess List() => new(ListFolder, UndoMode.Shadow, null);

    private AssistWorkspace Open(UndoHistory? history = null, UndoSeams? seams = null) =>
        new(Folder, new FakeLauncher(), undo: history)
        {
            Surface = AssistSurface.LocalWindow,
            UndoList = List(),
            UndoSeams = seams,
        };

    private TodaysClassOnTheFrontPage.Offering Offered() =>
        new("Unit 2, Day 5", "Unit 2, Day 4", Path.Combine(CourseDirectory, "section1", "All Classes", "Unit 2, Day 5.md"));

    private ClassesDatedLater.Page Ticked()
    {
        string page = Path.Combine(CourseDirectory, "section1", "All Classes", "Unit 1, Day 3.md");
        return new ClassesDatedLater.Page(ClassesDatedLater.PlaceOf(CourseDirectory, page), "Unit 1, Day 3", new DateOnly(2026, 9, 14), true);
    }

    private bool KeepAtDeploy(UndoSeams? seams = null)
    {
        UndoForThisProcess list = List();
        UndoDoor? door = seams is null ? null : new UndoDoor(list.Journal, list.Mode, list.Maintainers, seams: seams, trail: list.Trail);
        return LaterClassesKept.KeepAtDeploy(Folder, Course, CourseDirectory, 1, [Ticked()], Answered,
                                             new UndoStepMaker("sheet", KeptKey), list, door);
    }

    /// <summary>The newest step's <c>madeBy</c> and its ops, each as its kind and path.</summary>
    private (string MadeBy, List<string> Ops) NewestStep()
    {
        JsonObject step = WindowsActionsOnTheMacFixture.NewestBegin(ListFolder)!["step"]!.AsObject();
        var ops = new List<string>();
        foreach (JsonNode? op in step["ops"]!.AsArray()) ops.Add((string)op!["kind"]! + " " + (string?)op["path"]);
        return ((string)step["madeBy"]!, ops);
    }

    [Fact]
    public void NotTodayIsOneStepOfItsRecordMadeByTheSheet()
    {
        var history = new UndoHistory();

        bool remembered = Open(history).DeclineTodaysClass(Course, 1, Morning, Offered());

        Assert.True(remembered);
        Assert.Equal([NotTodayKey], WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        var (madeBy, ops) = NewestStep();
        Assert.Equal("sheet", madeBy);
        Assert.Equal([UndoOp.WriteFile + " courses/ICS3U/.publish_state/section1.front-page-not-today.json"], ops);
        Assert.Empty(history.Entries);
        JsonNode record = JsonNode.Parse(File.ReadAllText(NotTodayRecord))!;
        Assert.Equal(("2026-09-30", "Unit 2, Day 5"), ((string?)record["day"], (string?)record["class"]));
    }

    /// <summary>The record is planned as a file today's in-memory undo never keeps, as before.</summary>
    [Fact]
    public void NotTodayIsNeverToldToTodaysUndo()
    {
        AssistWorkspace workspace = Open();
        var step = new UndoActionStep(new UndoStepMaker("sheet", NotTodayKey), Folder, Course, 1, undo: List());

        Assert.True(TodaysClassOnTheFrontPage.RecordNotToday(workspace.Course(Course), 1, Morning, Offered(), step));

        Assert.False(step.TodaysUndoKeeps(NotTodayRecord), "today's undo is told of Not Today's record");
    }

    [Fact]
    public void KeptAtDeployIsOneStepOfItsRecordMadeByTheSheet()
    {
        Assert.True(KeepAtDeploy());

        Assert.Equal([KeptKey], WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        var (madeBy, ops) = NewestStep();
        Assert.Equal("sheet", madeBy);
        Assert.Equal([UndoOp.WriteFile + " courses/ICS3U/.publish_state/section1.later-classes-kept.json"], ops);
        Assert.Equal([new LaterClassesKept.Row("section1/All Classes/Unit 1, Day 3", "2026-09-14")], LaterClassesKept.Read(CourseDirectory, 1));
    }

    /// <summary>The record is planned as a file today's in-memory undo never keeps, as before.</summary>
    [Fact]
    public void KeptAtDeployIsNeverToldToTodaysUndo()
    {
        var step = new UndoActionStep(new UndoStepMaker("sheet", KeptKey), Folder, Course, 1, undo: List());

        Assert.True(LaterClassesKept.PlanInto(step, CourseDirectory, 1, [Ticked()], Answered));

        Assert.False(step.TodaysUndoKeeps(KeptRecord), "today's undo is told of the kept record");
    }

    /// <summary>
    /// The door refuses the record before anything changes: false, no
    /// throw, so the sheet goes on (the answer stands, the front page as it
    /// was), and only the record is lost.
    /// </summary>
    [Fact]
    public void ANotTodayThatCannotBeWrittenCostsOnlyTheRecord()
    {
        AssistWorkspace workspace = Open(seams: new UndoSeams { StagingWriteFailsAt = index => index == 0 });

        bool remembered = workspace.DeclineTodaysClass(Course, 1, Morning, Offered());

        Assert.False(remembered);
        Assert.False(File.Exists(NotTodayRecord));
        Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
        Assert.Contains("left the front page as it was — Not Today: Unit 2, Day 5 offered, it showed Unit 2, Day 4", File.ReadAllText(_trail));
    }

    /// <summary>The same at Deploy: false, no throw, so the deploy goes on, and the question is asked once more next time.</summary>
    [Fact]
    public void AKeptRecordThatCannotBeWrittenCostsOnlyTheRecord()
    {
        bool kept = KeepAtDeploy(new UndoSeams { StagingWriteFailsAt = index => index == 0 });

        Assert.False(kept);
        Assert.False(File.Exists(KeptRecord));
        Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
    }

    [Fact]
    public void TheSameNotTodayAgainMakesNoStep()
    {
        Assert.True(Open().DeclineTodaysClass(Course, 1, Morning, Offered()));
        byte[] first = File.ReadAllBytes(NotTodayRecord);

        Assert.True(Open().DeclineTodaysClass(Course, 1, Morning, Offered()));

        Assert.Equal([NotTodayKey], WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        Assert.Equal(first, File.ReadAllBytes(NotTodayRecord));
    }

    [Fact]
    public void TheSameKeptAnswerAgainMakesNoStep()
    {
        Assert.True(KeepAtDeploy());
        byte[] first = File.ReadAllBytes(KeptRecord);

        Assert.True(KeepAtDeploy());

        Assert.Equal([KeptKey], WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        Assert.Equal(first, File.ReadAllBytes(KeptRecord));
    }

    /// <summary>
    /// The window cannot be built in a unit test, so its answer at Deploy is
    /// read from the source: the ticked classes are kept through the step,
    /// with this workspace's folder, never by the plain <c>Keep</c> (the
    /// links checklist's, until W7b2-8).
    /// </summary>
    [Fact]
    public void TheDeployQuestionKeepsItsAnswerThroughTheStep()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SectionDetailView.xaml.cs"));

        Assert.DoesNotContain("LaterClassesKept.Keep(", source, StringComparison.Ordinal);
        Assert.Single(System.Text.RegularExpressions.Regex.Matches(source,
            System.Text.RegularExpressions.Regex.Escape("LaterClassesKept.KeepAtDeploy(_window.Workspace.WorkspacePath, _course.Code, _course.DirectoryPath, _sectionNumber, keeping);")));
    }
}

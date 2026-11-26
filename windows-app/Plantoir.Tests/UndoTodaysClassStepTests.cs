using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7b2-6: Show on Front Page
/// (<see cref="TodaysClassOnTheFrontPage.ShowOnTheFrontPage"/>, reached by
/// <see cref="AssistWorkspace.ShowTodaysClass"/>, key
/// <c>showTodaysClassOnTheFrontPage</c>, made by <c>sheet</c>) writes the
/// front page through ONE step, the page as the step's CONTENT
/// (<c>writeFile</c>), never a <c>recompute</c>: the teacher's own choice of
/// class, as the mac's <c>TodaysClassOnTheFrontPage.show</c>. Laid out on
/// the mac's recorded morning (<see cref="WindowsActionsOnTheMacFixture.Lay"/>).
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class UndoTodaysClassStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private const string Key = "showTodaysClassOnTheFrontPage";
    private const string Course = WindowsActionsOnTheMacFixture.Course;
    private static readonly DateOnly Morning = new(2026, 9, 30);

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-todays-class-");
    private readonly JsonElement _recorded = WindowsActionsOnTheMacFixture.Recorded(Key);

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string FrontPage => UndoDoor.FullPath(Folder, "courses/ICS3U/section1/index.md");

    // ---- Initializer ---------------------------------------------------------------

    public UndoTodaysClassStepTests() => WindowsActionsOnTheMacFixture.Lay(Folder, _recorded);

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private AssistWorkspace Open(UndoSeams? seams = null) =>
        new(Folder, new FakeLauncher())
        {
            Surface = AssistSurface.Menu,
            UndoList = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null),
            UndoSeams = seams,
        };

    private static TodaysClassOnTheFrontPage.Offering Offered(AssistWorkspace workspace) =>
        workspace.TodaysClassOffer(Course, 1, Morning) ?? throw new InvalidOperationException("the morning offers nothing");

    /// <summary>Another program edits the page as it is swapped in, and what it held cannot be put back: the step stops part way.</summary>
    private static UndoSeams PartWay() => new()
    {
        BetweenKeepingAndRenaming = (_, fullPath) =>
        {
            using var inPlace = new FileStream(fullPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
            byte[] edit = Encoding.UTF8.GetBytes("written by hand\n");
            inPlace.Write(edit);
            inPlace.SetLength(edit.Length);
        },
        PutBackFailsAt = index => index == 0,
    };

    private TodaysClassOnTheFrontPage.Outcome.ShownWithWhatItHeldKept ShowPartWay()
    {
        AssistWorkspace workspace = Open(PartWay());
        return Assert.IsType<TodaysClassOnTheFrontPage.Outcome.ShownWithWhatItHeldKept>(
            workspace.ShowTodaysClass(Course, 1, Morning, Offered(workspace)));
    }

    [Fact]
    public void ShowIsOneStepWithTheFrontPageAsItsContent()
    {
        AssistWorkspace workspace = Open();
        var offer = Offered(workspace);
        Assert.Equal(("Unit 2, Day 5", "Unit 2, Day 4"), (offer.Show, offer.Shows));

        var outcome = workspace.ShowTodaysClass(Course, 1, Morning, offer);

        Assert.IsType<TodaysClassOnTheFrontPage.Outcome.Written>(outcome);
        Assert.Equal([Key], WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        JsonObject step = WindowsActionsOnTheMacFixture.NewestBegin(ListFolder)!["step"]!.AsObject();
        Assert.Equal("sheet", (string?)step["madeBy"]);
        var ops = new List<string>();
        foreach (JsonNode? op in step["ops"]!.AsArray()) ops.Add((string)op!["kind"]! + " " + (string?)op["path"]);
        Assert.Equal([UndoOp.WriteFile + " courses/ICS3U/section1/index.md"], ops);
        Assert.Equal(_recorded.GetProperty("files")[0].GetProperty("after").GetString(), File.ReadAllText(FrontPage));
    }

    /// <summary>A write the door refuses before anything changes: <c>CouldNotSave</c>, true, because the page is as it was.</summary>
    [Fact]
    public void ARefusedWriteIsCouldNotSaveWithThePageAsItWas()
    {
        byte[] before = File.ReadAllBytes(FrontPage);
        AssistWorkspace workspace = Open(new UndoSeams { StagingWriteFailsAt = index => index == 0 });

        var outcome = workspace.ShowTodaysClass(Course, 1, Morning, Offered(workspace));

        Assert.IsType<TodaysClassOnTheFrontPage.Outcome.CouldNotSave>(outcome);
        Assert.Equal(before, File.ReadAllBytes(FrontPage));
        Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
    }

    /// <summary>
    /// The door leaves the page holding the new class with what it held
    /// kept beside it (another program writes into it as it is saved, and
    /// putting it back fails): <c>ShownWithWhatItHeldKept</c>, naming the
    /// kept file, never <c>CouldNotSave</c>, which would be false.
    /// </summary>
    [Fact]
    public void APartWayStopIsShownWithWhatItHeldKeptNeverCouldNotSave()
    {
        AssistWorkspace workspace = Open(PartWay());

        var outcome = workspace.ShowTodaysClass(Course, 1, Morning, Offered(workspace));

        Assert.IsNotType<TodaysClassOnTheFrontPage.Outcome.CouldNotSave>(outcome);
        var kept = Assert.IsType<TodaysClassOnTheFrontPage.Outcome.ShownWithWhatItHeldKept>(outcome);
        string onDisk = Path.GetFileName(Assert.Single(Directory.GetFiles(Path.GetDirectoryName(FrontPage)!, ".index.md.plantoir-undo-*-orig")));
        Assert.Equal([onDisk], kept.KeptNames);
        Assert.Contains("![[Unit 2, Day 5]]", File.ReadAllText(FrontPage), StringComparison.Ordinal);
    }

    /// <summary>The page already shows today's class by the time Show is pressed: <c>AlreadyShows</c>, no step, the page untouched.</summary>
    [Fact]
    public void AnAlreadyShowsAnswerMakesNoStep()
    {
        AssistWorkspace workspace = Open();
        var offer = Offered(workspace);
        File.WriteAllText(FrontPage, _recorded.GetProperty("files")[0].GetProperty("after").GetString()!, new UTF8Encoding(false));
        byte[] before = File.ReadAllBytes(FrontPage);

        var outcome = workspace.ShowTodaysClass(Course, 1, Morning, offer);

        Assert.IsType<TodaysClassOnTheFrontPage.Outcome.AlreadyShows>(outcome);
        Assert.Empty(WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        Assert.Equal(before, File.ReadAllBytes(FrontPage));
    }

    /// <summary>Asked yesterday, answered after midnight: <c>NoLongerOffered</c>, no step, the page untouched.</summary>
    [Fact]
    public void ANoLongerOfferedAnswerMakesNoStep()
    {
        AssistWorkspace workspace = Open();
        var offer = Offered(workspace);
        byte[] before = File.ReadAllBytes(FrontPage);

        var outcome = workspace.ShowTodaysClass(Course, 1, Morning.AddDays(3), offer);

        Assert.IsType<TodaysClassOnTheFrontPage.Outcome.NoLongerOffered>(outcome);
        Assert.Empty(WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        Assert.Equal(before, File.ReadAllBytes(FrontPage));
    }

    /// <summary>
    /// The part-way trail line says where what the page held went (W7b2-6
    /// review 1, L2): the mac's <c>trailLine(for:offer:)</c>, word for word.
    /// </summary>
    [Fact]
    public void ThePartWayTrailLineNamesTheHiddenFileWhatThePageHeldIsKeptIn()
    {
        string trail = Path.Combine(_root, "trail.txt");
        ActivityTrail.SetCustomLogPathForTesting(trail);
        try
        {
            var kept = ShowPartWay();
            string name = Assert.Single(kept.KeptNames);
            Assert.Contains("put today's class on the front page — Unit 2, Day 5 in place of Unit 2, Day 4. " +
                            $"What “index.md” held just before is kept beside it as the hidden file “{name}”",
                            File.ReadAllText(trail), StringComparison.Ordinal);
        }
        finally { ActivityTrail.SetCustomLogPathForTesting(null); }
    }

    /// <summary>
    /// The kept-file alert's Open Folder (#899 W7b2-9, Russell's ruling of
    /// 2026-11-25 (a)): opens the front page's FOLDER, never the kept file,
    /// and says nothing more while the file is there.
    /// </summary>
    [Fact]
    public async Task OpenFolderOpensTheFolderThatHoldsTheKeptFileNeverTheFile()
    {
        var kept = ShowPartWay();
        var opened = new List<string>();
        var said = new List<string>();

        await TodaysClassOnTheFrontPage.OpenTheKeptFolderAsync(kept.KeptOriginals,
            sentence => { said.Add(sentence); return Task.CompletedTask; }, folder => opened.Add(folder));

        Assert.Equal([Path.GetDirectoryName(FrontPage)!], opened);
        Assert.DoesNotContain(Assert.Single(kept.KeptOriginals), opened);
        Assert.Empty(said);
        Assert.True(File.Exists(Assert.Single(kept.KeptOriginals)), "the kept file is left where it is");
        Assert.True(File.GetAttributes(kept.KeptOriginals[0]).HasFlag(FileAttributes.Hidden) || !OperatingSystem.IsWindows(),
                    "the kept file stays hidden");
    }

    /// <summary>
    /// The kept file is gone by the time Open Folder is pressed: <c>keptOnWindows.keptGone</c>
    /// is said, filled with its name, and no folder is opened (the mac's
    /// <c>showInFinderPlan</c> with nothing still there).
    /// </summary>
    [Fact]
    public async Task AKeptFileGoneByThePressIsSaidAndNothingIsOpened()
    {
        var kept = ShowPartWay();
        File.Delete(kept.KeptOriginals[0]);
        var opened = new List<string>();
        var said = new List<string>();

        await TodaysClassOnTheFrontPage.OpenTheKeptFolderAsync(kept.KeptOriginals,
            sentence => { said.Add(sentence); return Task.CompletedTask; }, folder => opened.Add(folder));

        string keptGone = ContractLoader.LoadJson("class-planning.json")["todaysClassOnTheFrontPage"]!["keptOnWindows"]!["keptGone"]!.ToString();
        Assert.Equal([keptGone.Replace("{kept}", kept.KeptNames[0])], said);
        Assert.Empty(opened);
    }

    /// <summary>
    /// The alert's presses (W7b2-9 review 1, MEDIUM 1): OK, Escape, or an
    /// alert never shown opens nothing and says nothing; Open Folder opens the
    /// folder; Open Folder with the file gone shows the keptGone alert (<c>keptOnWindows.keptGone</c>) and opens nothing.
    /// </summary>
    [Fact]
    public async Task OnlyOpenFolderOpensAndAGoneFileShowsTheGoneAlert()
    {
        var kept = ShowPartWay();
        var alert = TodaysClassOnTheFrontPage.KeptAlertFor(new TodaysClassOnTheFrontPage.Offering("Unit 2, Day 5", "Unit 2, Day 4", FrontPage), kept);
        var opened = new List<string>();
        var shown = new List<TodaysClassOnTheFrontPage.AlertDescription>();
        Task Show(TodaysClassOnTheFrontPage.AlertDescription description) { shown.Add(description); return Task.CompletedTask; }

        await alert.PressedAsync(TodaysClassOnTheFrontPage.AlertButton.Close, Show, opened.Add);
        await alert.PressedAsync(null, Show, opened.Add);
        Assert.Empty(opened);
        Assert.Empty(shown);

        await alert.PressedAsync(TodaysClassOnTheFrontPage.AlertButton.Action, Show, opened.Add);
        Assert.Equal([Path.GetDirectoryName(FrontPage)!], opened);
        Assert.Empty(shown);

        opened.Clear();
        File.Delete(kept.KeptOriginals[0]);
        await alert.PressedAsync(TodaysClassOnTheFrontPage.AlertButton.Action, Show, opened.Add);
        string keptGone = ContractLoader.LoadJson("class-planning.json")["todaysClassOnTheFrontPage"]!["keptOnWindows"]!["keptGone"]!.ToString();
        Assert.Equal([new TodaysClassOnTheFrontPage.AlertDescription(null, keptGone.Replace("{kept}", kept.KeptNames[0]), null, "OK",
                                                                      TodaysClassOnTheFrontPage.AlertButton.Close)], shown);
        Assert.Empty(opened);
    }
}

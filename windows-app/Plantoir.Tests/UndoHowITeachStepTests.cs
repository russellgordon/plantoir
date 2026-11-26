using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7b2-4: every write of a course's How I Teach page is ONE step
/// through the door, held by the course (<c>holds: course</c>, no section):
/// Write How I Teach (<c>write_how_i_teach</c>, key <c>writeHowITeach</c>)
/// and Start the How I Teach Page (Course Settings' row, key
/// <c>startHowITeachPage</c>, made by <c>sheet</c>), the mac's
/// <c>write_how_i_teach</c> step and <c>HowITeachPage.startOrFind</c>.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class UndoHowITeachStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-how-i-teach-");
    private readonly UndoHistory _today = new();

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string CourseFolder => Path.Combine(Folder, "courses", "ICS3U");
    private string PagePath => Path.Combine(CourseFolder, HowITeachPage.FileName);

    // ---- Initializer ---------------------------------------------------------------

    public UndoHowITeachStepTests()
    {
        Directory.CreateDirectory(Path.Combine(CourseFolder, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(Folder, Workspace.MarkerLauncher), "");
        File.WriteAllText(Path.Combine(CourseFolder, "course_config.json"),
            "{\"course_code\":\"ICS3U\",\"course_name\":\"A course\",\"num_sections\":1,\"section_numbers\":[1],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[]}");
    }

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private UndoForThisProcess List() => new(ListFolder, UndoMode.Shadow, null);

    private AssistWorkspace Open(UndoSeams? seams = null, AssistSurface surface = AssistSurface.Outside) => new(Folder, new FakeLauncher(), undo: _today)
    {
        Surface = surface,
        UndoList = List(),
        UndoSeams = seams,
    };

    private (HowITeachSettingsRow.Outcome Outcome, string? Path, string? Problem) Press(UndoSeams? seams = null)
    {
        UndoForThisProcess list = List();
        UndoDoor door = new(list.Journal, list.Mode, list.Maintainers, seams: seams, trail: list.Trail);
        return HowITeachSettingsRow.Press(CourseFolder, "ICS3U", betweenTheLookAndTheWrite: null, list, door);
    }

    private List<JsonObject> Steps()
    {
        var steps = new List<JsonObject>();
        if (!Directory.Exists(ListFolder)) return steps;
        foreach (string segment in Directory.EnumerateFiles(ListFolder, "journal-*.jsonl").Order(StringComparer.Ordinal))
        {
            foreach (string line in File.ReadAllLines(segment))
            {
                if (JsonNode.Parse(line) is JsonObject read && (string?)read["event"] == "begin") steps.Add(read["step"]!.AsObject());
            }
        }
        return steps;
    }

    /// <summary>Another program saves its own page at the path just before the swap.</summary>
    private static UndoSeams TheirPageAppearsBeforeTheSwap(string theirs) => new()
    {
        BeforeEachSwap = (_, fullPath) => File.WriteAllText(fullPath, theirs),
    };

    [Fact]
    public void WriteHowITeachIsOneStepHeldByTheCourse()
    {
        Open().WriteHowITeach("ICS3U", "I start every class with a question.", "");

        JsonObject step = Assert.Single(Steps());
        Assert.Equal("writeHowITeach", (string?)step["action"]!["key"]);
        Assert.StartsWith("outsideAssistant::", (string?)step["madeBy"]);
        Assert.Equal("course", (string?)step["holds"]);
        Assert.Equal("ICS3U", (string?)step["course"]);
        Assert.Null(step["section"]);
        Assert.Equal(HowITeachPage.NewPageText("I start every class with a question."), File.ReadAllText(PagePath));
        Assert.Single(_today.Entries);
    }

    [Fact]
    public void StartTheHowITeachPageIsOneStepMadeByTheSheet()
    {
        var (outcome, page, problem) = Press();

        Assert.Equal(HowITeachSettingsRow.Outcome.Created, outcome);
        Assert.Equal(PagePath, page);
        Assert.Null(problem);
        JsonObject step = Assert.Single(Steps());
        Assert.Equal("startHowITeachPage", (string?)step["action"]!["key"]);
        Assert.Equal("sheet", (string?)step["madeBy"]);
        Assert.Equal("course", (string?)step["holds"]);
        Assert.Null(step["section"]);
        Assert.Equal(HowITeachSettingsRow.CreatedBytes, File.ReadAllText(PagePath));
    }

    [Fact]
    public void APageThatAppearedBeforeTheSwapIsNeverWrittenOverByTheTool()
    {
        var refusal = Assert.Throws<AssistRefusal>(() =>
            Open(TheirPageAppearsBeforeTheSwap("Mine, just now.\n")).WriteHowITeach("ICS3U", "Words.", ""));

        Assert.Equal(AssistWording.HowITeachChangedSincePlanned("ICS3U"), refusal.Message);
        Assert.Equal("Mine, just now.\n", File.ReadAllText(PagePath));
        Assert.Empty(_today.Entries);
    }

    [Fact]
    public void APageThatAppearedBeforeTheSwapIsOpenedByTheRow()
    {
        var (outcome, page, problem) = Press(TheirPageAppearsBeforeTheSwap("Mine, just now.\n"));

        Assert.Equal(HowITeachSettingsRow.Outcome.Opened, outcome);
        Assert.Equal(PagePath, page);
        Assert.Null(problem);
        Assert.Equal("Mine, just now.\n", File.ReadAllText(PagePath));
    }

    [Fact]
    public void APageThatCannotBeWrittenChangesNothing()
    {
        var unwritable = new UndoSeams { StagingWriteFailsAt = index => index == 0 };

        var refusal = Assert.Throws<AssistRefusal>(() => Open(unwritable).WriteHowITeach("ICS3U", "Words.", ""));
        Assert.StartsWith("Nothing was saved: ", refusal.Message);
        Assert.False(File.Exists(PagePath));
        Assert.Empty(_today.Entries);

        var (outcome, page, problem) = Press(unwritable);
        Assert.Equal(HowITeachSettingsRow.Outcome.CouldNotCreate, outcome);
        Assert.Null(page);
        Assert.StartsWith(HowITeachSettingsRow.CouldNotCreate(""), problem);
        Assert.False(File.Exists(PagePath));
        Assert.Equal(["course_config.json"], FileNamesIn(CourseFolder));
    }

    private static List<string> FileNamesIn(string folder)
    {
        var names = new List<string>();
        foreach (string file in Directory.GetFiles(folder)) names.Add(Path.GetFileName(file));
        return names;
    }

    /// <summary>
    /// A replaced page left part way (another program writes into it as it is
    /// saved, and putting it back fails): the part-way sentence naming the
    /// kept file, never "Nothing was changed" and never "saved".
    /// </summary>
    [Fact]
    public void AReplacedPageLeftPartWayIsSaidAsPartWay()
    {
        Open().WriteHowITeach("ICS3U", "First words.", "");
        string mark = HowITeachPage.MarkOf(File.ReadAllBytes(PagePath))!;
        var partWay = new UndoSeams
        {
            BetweenKeepingAndRenaming = (_, fullPath) =>
            {
                using var inPlace = new FileStream(fullPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
                byte[] edit = System.Text.Encoding.UTF8.GetBytes("Theirs.\n");
                inPlace.Write(edit);
                inPlace.SetLength(edit.Length);
            },
            PutBackFailsAt = index => index == 0,
        };

        var refusal = Assert.Throws<AssistRefusal>(() => Open(partWay).WriteHowITeach("ICS3U", "Second words.", mark));

        Assert.StartsWith(AssistWording.PublishStoppedPartWay("the How I Teach page", ""), refusal.Message);
        string kept = Assert.Single(Directory.GetFiles(CourseFolder, "." + HowITeachPage.FileName + ".plantoir-undo-*-orig"));
        Assert.Contains(Path.GetFileName(kept), refusal.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("Nothing was changed", refusal.Message, StringComparison.Ordinal);
        Assert.DoesNotContain(AssistWording.HowITeachSaved("ICS3U"), refusal.Message, StringComparison.Ordinal);
    }

    /// <summary>
    /// The same stop in Plantoir's own window: the bare part-way sentence, as
    /// the mac's <c>aSectionsCopyPutsItBack: false</c> says it. The page sits
    /// outside every section, so Restore Section is never named, although a
    /// copy of the course was made (review 1, MEDIUM).
    /// </summary>
    [Fact]
    public void AReplacedPageLeftPartWayInPlantoirsOwnWindowNamesNoRestoreSection()
    {
        Open().WriteHowITeach("ICS3U", "First words.", "");
        string mark = HowITeachPage.MarkOf(File.ReadAllBytes(PagePath))!;
        var partWay = new UndoSeams
        {
            BetweenKeepingAndRenaming = (_, fullPath) =>
            {
                using var inPlace = new FileStream(fullPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
                byte[] edit = System.Text.Encoding.UTF8.GetBytes("Theirs.\n");
                inPlace.Write(edit);
                inPlace.SetLength(edit.Length);
            },
            PutBackFailsAt = index => index == 0,
        };
        AssistWorkspace ownWindow = Open(partWay, AssistSurface.LocalWindow);

        var refusal = Assert.Throws<AssistRefusal>(() => ownWindow.WriteHowITeach("ICS3U", "Second words.", mark));

        Assert.NotNull(ownWindow.ConversationBackupPath);
        string kept = Assert.Single(Directory.GetFiles(CourseFolder, "." + HowITeachPage.FileName + ".plantoir-undo-*-orig"));
        Assert.StartsWith(AssistWording.PublishStoppedPartWay("the How I Teach page", ""), refusal.Message);
        Assert.Contains(Path.GetFileName(kept), refusal.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("Restore Section", refusal.Message, StringComparison.Ordinal);
        Assert.DoesNotContain(AssistWording.RestoreFromBackupPutsItBack, refusal.Message, StringComparison.Ordinal);
    }

    /// <summary>
    /// A page that appears in the last instant, after the door's check and
    /// before its rename: the rename refuses it ("in use" to the door), the
    /// page is not written over, and the tool says today's sentence, as for
    /// one that appeared a moment earlier (review 1, LOW 2).
    /// </summary>
    [Fact]
    public void APageThatAppearedJustBeforeTheRenameIsSaidAsAppearedMeanwhile()
    {
        var lastInstant = new UndoSeams { BetweenKeepingAndRenaming = (_, fullPath) => File.WriteAllText(fullPath, "Mine, just now.\n") };

        var refusal = Assert.Throws<AssistRefusal>(() => Open(lastInstant).WriteHowITeach("ICS3U", "Words.", ""));

        Assert.Equal("Mine, just now.\n", File.ReadAllText(PagePath));
        Assert.Equal(AssistWording.HowITeachChangedSincePlanned("ICS3U"), refusal.Message);
        Assert.Empty(_today.Entries);
    }

    /// <summary>
    /// A page the teacher started (no words yet) that the door refuses for
    /// another reason: the plan saw that page, so it did not appear, and the
    /// refusal says its own reason as "Nothing was saved: …", never
    /// today's changed-since sentence (review 2, MEDIUM).
    /// </summary>
    [Fact]
    public void AStartedPageRefusedForAnotherReasonSaysNothingWasSaved()
    {
        Assert.Equal(HowITeachSettingsRow.Outcome.Created, Press().Outcome);
        var unwritable = new UndoSeams { StagingWriteFailsAt = index => index == 0 };

        var refusal = Assert.Throws<AssistRefusal>(() => Open(unwritable).WriteHowITeach("ICS3U", "Words.", ""));

        Assert.StartsWith("Nothing was saved: ", refusal.Message);
        Assert.NotEqual(AssistWording.HowITeachChangedSincePlanned("ICS3U"), refusal.Message);
        Assert.Equal(HowITeachSettingsRow.CreatedBytes, File.ReadAllText(PagePath));
    }

    [Fact]
    public void TheSameWordsAgainMakeNoStepAndNoWrite()
    {
        Open().WriteHowITeach("ICS3U", "The same words.", "");
        string mark = HowITeachPage.MarkOf(File.ReadAllBytes(PagePath))!;
        var longAgo = new DateTime(2020, 1, 2, 3, 4, 5, DateTimeKind.Utc);
        File.SetLastWriteTimeUtc(PagePath, longAgo);
        int stepsBefore = Steps().Count;
        int entriesBefore = _today.Entries.Count;

        AssistResult answered = Open().WriteHowITeach("ICS3U", "The same words.", mark);

        Assert.Equal(AssistWording.HowITeachSaved("ICS3U"), answered.Message);
        Assert.Equal(stepsBefore, Steps().Count);
        Assert.Equal(entriesBefore, _today.Entries.Count);
        Assert.Equal(longAgo, File.GetLastWriteTimeUtc(PagePath));
    }
}

using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7b2-5: Get Ready for the Start of the Year
/// (<see cref="AssistWorkspace.PrepareForStartOfYear"/>, key
/// <c>getReadyForTheStartOfTheYear</c>) plans every page it changes into ONE
/// step through the door and names the section's front page as a
/// <c>recompute</c> (<c>sectionFrontPage</c>), never as a file of the step:
/// all or none, the mac's <c>StartOfYearPlanner.apply</c>. Laid out on the
/// mac's recorded fixture (<see cref="WindowsActionsOnTheMacFixture.Lay"/>).
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class UndoStartOfYearStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private const string Key = "getReadyForTheStartOfTheYear";
    private const string Course = WindowsActionsOnTheMacFixture.Course;

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-start-of-year-");
    private readonly UndoHistory _today = new();
    private readonly JsonElement _recorded = WindowsActionsOnTheMacFixture.Recorded(Key);

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string FrontPage => UndoDoor.FullPath(Folder, "courses/ICS3U/section1/index.md");

    // ---- Initializer ---------------------------------------------------------------

    public UndoStartOfYearStepTests() => WindowsActionsOnTheMacFixture.Lay(Folder, _recorded);

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private AssistWorkspace Open(UndoSeams? seams = null, AssistSurface surface = AssistSurface.LocalWindow) =>
        new(Folder, new FakeLauncher(), undo: _today)
        {
            Surface = surface,
            UndoList = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null),
            UndoSeams = seams,
        };

    private static StartOfYearOutcome Go(AssistWorkspace workspace,
                                         StartOfYearAskedFrom from = StartOfYearAskedFrom.TheAssistant) =>
        workspace.PrepareForStartOfYear(Course, 1, workspace.PlanStartOfYear(Course, 1).Code, from,
            from == StartOfYearAskedFrom.TheApp ? new BackupMaker.Teacher() : null);

    private List<string> RecordedPaths()
    {
        var paths = new List<string>();
        foreach (JsonElement file in _recorded.GetProperty("files").EnumerateArray()) paths.Add(file.GetProperty("path").GetString()!);
        return paths;
    }

    /// <summary>Every recorded page and the front page, by path, as their bytes now.</summary>
    private Dictionary<string, byte[]> PagesNow()
    {
        var pages = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (string path in RecordedPaths()) pages[path] = File.ReadAllBytes(UndoDoor.FullPath(Folder, path));
        pages["index"] = File.ReadAllBytes(FrontPage);
        return pages;
    }

    private static void AssertSamePages(Dictionary<string, byte[]> before, Dictionary<string, byte[]> now)
    {
        foreach (var (path, bytes) in before)
            Assert.True(bytes.AsSpan().SequenceEqual(now[path]), $"{path} changed");
    }

    private static List<string> KeptOriginalsUnder(string folder)
    {
        var kept = new List<string>();
        foreach (string file in Directory.GetFiles(folder, "*.plantoir-undo-*-orig", SearchOption.AllDirectories)) kept.Add(file);
        return kept;
    }

    [Fact]
    public void GoIsOneStepInTheMacsOrderWithTheFrontPageAsARecompute()
    {
        StartOfYearOutcome outcome = Go(Open());

        Assert.True(outcome.Changed, outcome.Message);
        Assert.Equal([Key], WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        JsonObject step = WindowsActionsOnTheMacFixture.NewestBegin(ListFolder)!["step"]!.AsObject();
        Assert.StartsWith("builtInAssistant:", (string?)step["madeBy"]);
        var files = new List<string>();
        var recomputes = new List<string>();
        foreach (JsonNode? op in step["ops"]!.AsArray())
        {
            if ((string?)op!["kind"] == UndoOp.Recompute)
            {
                recomputes.Add((string)op["maintainer"]! + " " + (string)op["path"]! + " " + (long)op["section"]!);
                continue;
            }
            files.Add((string)op["path"]!);
        }
        Assert.Equal(RecordedPaths(), files);
        Assert.Equal(["sectionFrontPage courses/ICS3U/section1/index.md 1"], recomputes);
        // Today's undo holds the change, the front page included where the rule moved it.
        UndoHistory.Entry entry = Assert.Single(_today.Entries);
        foreach (string path in RecordedPaths()) Assert.True(entry.Files.ContainsKey(UndoDoor.FullPath(Folder, path)), path);
    }

    [Fact]
    public void TheAppsGoIsMadeByTheSheet()
    {
        StartOfYearOutcome outcome = Go(Open(surface: AssistSurface.Menu), StartOfYearAskedFrom.TheApp);

        Assert.True(outcome.Changed, outcome.Message);
        JsonObject step = WindowsActionsOnTheMacFixture.NewestBegin(ListFolder)!["step"]!.AsObject();
        Assert.Equal(Key, (string?)step["action"]!["key"]);
        Assert.Equal("sheet", (string?)step["madeBy"]);
    }

    /// <summary>
    /// A page that cannot be written: the door refuses before anything is
    /// written, so every page and the front page are as they were, and the
    /// answer is "Nothing was changed: …" with its reason, never the sentence
    /// of a write that could not finish.
    /// </summary>
    [Fact]
    public void APageThatCannotBeWrittenChangesNothing()
    {
        var before = PagesNow();
        var unwritable = new UndoSeams { StagingWriteFailsAt = index => index == 0 };

        StartOfYearOutcome outcome = Go(Open(unwritable));

        Assert.False(outcome.Changed);
        Assert.Empty(outcome.Written);
        string first = Path.GetFileName(RecordedPaths()[0]);
        Assert.Equal($"Nothing was changed: nothing could be written beside “{first}” (the disk may be full, or Plantoir may not have permission to write there).",
            outcome.Message);
        Assert.DoesNotContain("could not finish", outcome.Message, StringComparison.Ordinal);
        AssertSamePages(before, PagesNow());
        Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
        Assert.Empty(_today.Entries);
    }

    /// <summary>
    /// The door leaves a page holding its new content with its earlier
    /// content kept beside it (another program writes into it as it is saved,
    /// and putting it back fails): the part-way sentence, naming the kept
    /// file, never "Nothing was changed", never the done sentence.
    /// </summary>
    [Fact]
    public void APartWayStopSaysThePartWaySentence()
    {
        var partWay = new UndoSeams
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

        StartOfYearOutcome outcome = Go(Open(partWay));

        Assert.False(outcome.Changed);
        Assert.StartsWith(AssistWording.PublishStoppedPartWay("the pages put into draft", ""), outcome.Message);
        string kept = Assert.Single(KeptOriginalsUnder(Path.Combine(Folder, "courses")));
        Assert.Contains(Path.GetFileName(kept), outcome.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("Nothing was changed", outcome.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("couldn’t be read", outcome.Message, StringComparison.Ordinal);
        Assert.DoesNotContain(StartOfYearWording.Done[..StartOfYearWording.Done.IndexOf('{')], outcome.Message, StringComparison.Ordinal);
    }

    /// <summary>Undo Getting Ready after a success puts back every page the act wrote, the front page included, and leaves none.</summary>
    [Fact]
    public void UndoGettingReadyAfterASuccessAnswersAsBefore()
    {
        var before = PagesNow();
        StartOfYearOutcome outcome = Go(Open(), StartOfYearAskedFrom.TheApp);
        Assert.True(outcome.Changed, outcome.Message);
        foreach (string path in RecordedPaths()) Assert.True(outcome.Written.ContainsKey(UndoDoor.FullPath(Folder, path)), path);

        var (putBack, left) = AssistWorkspace.UndoStartOfYear(outcome.Written);

        Assert.Empty(left);
        Assert.Equal(outcome.Written.Count, putBack.Count);
        AssertSamePages(before, PagesNow());
    }

    /// <summary>
    /// A plan that reaches the step and changes nothing: every page it would
    /// put into draft is one the writer declines (visible, no key, and no
    /// column-0 place for one, #421), so the step plans no change and the
    /// door is never asked: no step on the list, every page as it was.
    /// </summary>
    [Fact]
    public void APlanThatChangesNothingMakesNoStep()
    {
        foreach (JsonElement file in _recorded.GetProperty("files").EnumerateArray())
        {
            string full = UndoDoor.FullPath(Folder, file.GetProperty("path").GetString()!);
            string title = Path.GetFileNameWithoutExtension(full);
            File.WriteAllText(full, $"---\n  a: 1\ntitle: {title}\n---\n\nBody.\n");
        }
        var before = PagesNow();
        AssistWorkspace workspace = Open();
        Assert.NotEmpty(workspace.PlanStartOfYear(Course, 1).Plan.Drafts);

        StartOfYearOutcome outcome = Go(workspace);

        Assert.False(outcome.Changed, outcome.Message);
        // The answer names the declined pages (review 1, L3): never the done
        // sentence, never "Nothing was changed".
        var declined = new List<string>();
        foreach (JsonElement file in _recorded.GetProperty("files").EnumerateArray())
            declined.Add(Path.GetFileNameWithoutExtension(file.GetProperty("path").GetString()!));
        Assert.Equal(AssistWording.PagesWhoseSettingsCannotBeAddedTo(declined), outcome.Message);
        Assert.Empty(WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        AssertSamePages(before, PagesNow());
    }
}

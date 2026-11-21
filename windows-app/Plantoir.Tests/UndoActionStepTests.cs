using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7a: a daily action is ONE step through the door (the mac's
/// <c>JournaledStep</c>, U3a): planned first, its befores read at plan time,
/// made once, all or none, in shadow, with "undo could not record a step"
/// when the list cannot take it; and Publish Pages and Hide Pages through it.
/// </summary>
public sealed class UndoActionStepTests : IDisposable
{
    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-action-step-");

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private readonly List<UndoTrailLine> _trail = [];

    private const string Day1 = "courses/ICS3U/section1/All Classes/Unit 1, Day 1.md";
    private const string Day2 = "courses/ICS3U/section1/All Classes/Unit 1, Day 2.md";
    private const string Index = "courses/ICS3U/section1/index.md";

    private string Full(string relative) => UndoDoor.FullPath(Folder, relative);

    private static string Class(int day, bool draft) =>
        $"---\ntitle: Unit 1, Day {day}\ncreated: 2026-09-0{7 + day}T07:00:00.000-0400\ndraft: {(draft ? "true" : "false")}\n---\nThe lesson.\n";

    private void Write(string relative, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Full(relative))!);
        File.WriteAllText(Full(relative), text);
    }

    private void ACourse()
    {
        string course = Path.Combine(Folder, "courses", "ICS3U");
        Directory.CreateDirectory(course);
        File.WriteAllText(Path.Combine(course, "course_config.json"),
            "{\"course_code\":\"ICS3U\",\"course_name\":\"Computer Science\",\"num_sections\":1,\"section_numbers\":[1],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[]}");
        File.WriteAllText(Path.Combine(Folder, Plantoir.Core.Models.Workspace.MarkerLauncher), "");
        Write(Day1, Class(1, draft: false));
        Write(Day2, Class(2, draft: true));
        Write(Index, "---\ntitle: Section 1\ncreated: 2026-09-08T07:00:00.000-0400\ndraft: false\n---\n# Most Recent Class\n![[Unit 1, Day 1]]\n");
    }

    private UndoForThisProcess List(UndoMode mode = UndoMode.Shadow) => new(ListFolder, mode, _trail.Add);

    private UndoActionStep Step(UndoForThisProcess list, string key = "publishPages") =>
        new(new UndoStepMaker("menu", key), Folder, "ICS3U", 1, undo: list);

    /// <summary>Every begin line the list holds, in order.</summary>
    private List<JsonObject> Begins()
    {
        var begins = new List<JsonObject>();
        if (!Directory.Exists(ListFolder)) return begins;
        foreach (string segment in Directory.EnumerateFiles(ListFolder, "journal-*.jsonl").Order(StringComparer.Ordinal))
        {
            foreach (string line in File.ReadAllLines(segment))
            {
                if (JsonNode.Parse(line) is JsonObject read && (string?)read["event"] == "begin") begins.Add(read);
            }
        }
        return begins;
    }

    [Fact]
    public void TwoPagesAndTheFrontPageAreOneStepMadeOnceWithTheFrontPageAsARecompute()
    {
        ACourse();
        Write(Day1, Class(1, draft: true));
        UndoActionStep step = Step(List());
        step.Write(Full(Day1), Class(1, draft: false));
        step.Write(Full(Day2), Class(2, draft: false));
        step.KeepsTheFrontPageTrue(1, Full(Index));

        // Nothing is written until the step is made.
        Assert.Equal(Class(2, draft: true), File.ReadAllText(Full(Day2)));
        Assert.Equal(Class(2, draft: false), step.ReadText(Full(Day2)));
        step.Make();

        Assert.Equal(Class(1, draft: false), File.ReadAllText(Full(Day1)));
        Assert.Equal(Class(2, draft: false), File.ReadAllText(Full(Day2)));
        Assert.Contains("![[Unit 1, Day 2]]", File.ReadAllText(Full(Index)));
        JsonObject begin = Assert.Single(Begins());
        JsonObject step1 = begin["step"]!.AsObject();
        Assert.Equal("publishPages", (string?)step1["action"]!["key"]);
        Assert.Equal("2", (string?)step1["action"]!["arguments"]!["pageCount"]);
        Assert.Equal("menu", (string?)step1["madeBy"]);
        Assert.Equal("A", (string?)step1["class"]);
        Assert.Equal("section", (string?)step1["holds"]);
        var kinds = new List<string>();
        var paths = new List<string>();
        foreach (JsonNode? op in step1["ops"]!.AsArray())
        {
            kinds.Add((string)op!["kind"]!);
            paths.Add((string)op["path"]!);
        }
        // The front page is never a file of the step: it is re-derived once, after it.
        Assert.Equal(["editLine", "editLine", "recompute"], kinds);
        Assert.Equal([Day1, Day2, Index], paths);
        Assert.Empty(_trail);
    }

    [Fact]
    public void ABeforeIsReadAtPlanTimeSoAPageChangedInBetweenRefusesTheStepAndNothingIsWritten()
    {
        ACourse();
        UndoActionStep step = Step(List());
        step.Write(Full(Day1), Class(1, draft: true));
        step.Write(Full(Day2), Class(2, draft: false));
        // Another program edits Day 2 between the plan and the make.
        Write(Day2, Class(2, draft: true) + "An edit in Obsidian.\n");

        var refused = Assert.Throws<UndoStepRefusedException>(step.Make);

        Assert.Equal(UndoRefusalKind.ChangedSince, refused.Refusal.Kind);
        Assert.Equal(Class(1, draft: false), File.ReadAllText(Full(Day1)));
        Assert.Equal(Class(2, draft: true) + "An edit in Obsidian.\n", File.ReadAllText(Full(Day2)));
    }

    [Fact]
    public void AListThatCannotTakeTheStepLeavesTheFilesWrittenAsPlannedAndOneTrailLine()
    {
        ACourse();
        // The list's folder is a file: nothing of the list can be written.
        Directory.CreateDirectory(Path.GetDirectoryName(ListFolder)!);
        File.WriteAllText(ListFolder, "not a folder");
        UndoActionStep step = Step(List());
        step.Write(Full(Day2), Class(2, draft: false));
        step.KeepsTheFrontPageTrue(1, Full(Index));

        step.Make();

        Assert.Equal(Class(2, draft: false), File.ReadAllText(Full(Day2)));
        Assert.Contains("![[Unit 1, Day 2]]", File.ReadAllText(Full(Index)));
        UndoTrailLine line = Assert.Single(_trail);
        Assert.Equal(Plantoir.Core.Scripting.ActivityTrail.Event.UndoCouldNotRecordAStep, line.Event);
        Assert.Equal("ICS3U", line.Course);
        Assert.Equal(1L, line.Section);
        Assert.Equal("the undo list could not record publishPages: the list could not be written. The change went ahead (the list is not in use yet).", line.Words);
    }

    [Fact]
    public void TheTrailLineIsTheContractsExampleLineForABusyList()
    {
        JsonObject rules = JsonNode.Parse(File.ReadAllText(ContractLoader.GetContractPath("shared-rules.json")))!.AsObject();
        string? example = null;
        foreach (JsonNode? row in rules["activityTrail"]!["mustRecord"]!.AsArray())
        {
            if ((string?)row!["event"] == "undo could not record a step") example = (string?)row["line"];
        }
        Assert.NotNull(example);
        Assert.Equal(example, "ICS3U/1 · " + UndoTrail.CouldNotRecordWords("publishPages", "the list was busy", UndoUnrecordedChange.WentAhead));
    }

    [Fact]
    public void TheKeptSentenceIsTheContractsKeptBesideIt()
    {
        JsonObject rules = JsonNode.Parse(File.ReadAllText(ContractLoader.GetContractPath("shared-rules.json")))!.AsObject();
        string template = (string)rules["undo"]!["wording"]!["keptBesideIt"]!;
        Assert.Equal(template.Replace("{place}", "“A.md”").Replace("{kept}", ".A.md.plantoir-undo-4-apply-orig"),
                     UndoActionStep.KeptSentence("“A.md”", ".A.md.plantoir-undo-4-apply-orig"));
    }

    [Fact]
    public void PublishPagesThroughTheWorkspaceIsOneStepAndTodaysUndoStillPutsItBack()
    {
        ACourse();
        var history = new UndoHistory();
        var workspace = new AssistWorkspace(Folder, new NoLaunchers(), undo: history) { Surface = AssistSurface.Menu, UndoList = List() };
        PublishPlan plan = workspace.PlanPublish("ICS3U", 1, ["Unit 1, Day 2"], draft: false, publishes: true);

        workspace.Apply(plan, preview: false).GetAwaiter().GetResult();

        Assert.NotEqual(Class(2, draft: true), File.ReadAllText(Full(Day2)));
        JsonObject begin = Assert.Single(Begins());
        Assert.Equal("publishPages", (string?)begin["step"]!["action"]!["key"]);
        Assert.Equal("menu", (string?)begin["step"]!["madeBy"]);
        UndoHistory.Entry entry = Assert.Single(history.Entries);
        Assert.Equal(Class(2, draft: true), entry.Files[Full(Day2)].Before);
        history.Undo();
        Assert.Equal(Class(2, draft: true), File.ReadAllText(Full(Day2)));
    }

    /// <summary>A door over <paramref name="list"/>'s journal with seams, or with maintainers of a test's own.</summary>
    private static UndoDoor DoorOver(UndoForThisProcess list, UndoSeams? seams = null, IUndoMaintainers? maintainers = null) =>
        new(list.Journal, list.Mode, maintainers ?? list.Maintainers, seams: seams, trail: list.Trail);

    /// <summary>Day 1 goes in, Day 2 is read-only and refuses, and Day 1 cannot be put back: the step is left part way.</summary>
    private static UndoSeams PutBackOfTheFirstPageFails() => new() { PutBackFailsAt = index => index == 0 };

    private void StepLeftPartWay(UndoForThisProcess list)
    {
        Write(Day1, Class(1, draft: true));
        File.SetAttributes(Full(Day2), FileAttributes.ReadOnly);
        var step = new UndoActionStep(new UndoStepMaker("menu", "publishPages"), Folder, "ICS3U", 1, undo: list,
                                      door: DoorOver(list, PutBackOfTheFirstPageFails()));
        step.Write(Full(Day1), Class(1, draft: false));
        step.Write(Full(Day2), Class(2, draft: false));

        var partWay = Assert.Throws<UndoStepLeftPartWayException>(step.Make);

        File.SetAttributes(Full(Day2), FileAttributes.Normal);
        // The disk holds the new Day 1, and its earlier content is kept beside it, named.
        Assert.Equal(Class(1, draft: false), File.ReadAllText(Full(Day1)));
        Assert.Equal(Class(2, draft: true), File.ReadAllText(Full(Day2)));
        string kept = Assert.Single(partWay.KeptOriginals);
        Assert.Equal(Class(1, draft: true), File.ReadAllText(kept));
        Assert.Contains(UndoActionStep.KeptSentence("“Unit 1, Day 1.md”", Path.GetFileName(kept)), partWay.Message, StringComparison.Ordinal);
        // "hidden" is true on Windows only by the attribute (review 1, MEDIUM 1): the kept file has it, the page does not.
        Assert.True(File.GetAttributes(kept).HasFlag(FileAttributes.Hidden), "the kept file is not Hidden");
        Assert.False(File.GetAttributes(Full(Day1)).HasFlag(FileAttributes.Hidden), "the page was hidden");
        Assert.DoesNotContain("Nothing was", partWay.Message, StringComparison.Ordinal);
    }

    /// <summary>Review 1, MEDIUM 2: a recorded step left part way is said as part way (the door's <c>LeftPartWay</c> on its recorded path), never "Nothing was changed".</summary>
    [Fact]
    public void ARecordedStepLeftPartWayIsSaidAsPartWayAndNamesTheKeptFile()
    {
        ACourse();
        StepLeftPartWay(List());
        Assert.Single(Begins());
    }

    /// <summary>Review 1, MEDIUM 2: the same when the list cannot take the step (the door's shadow swap without a record), with the trail line saying it stopped part way.</summary>
    [Fact]
    public void AnUnrecordedStepLeftPartWayIsSaidAsPartWayWithItsTrailLine()
    {
        ACourse();
        Directory.CreateDirectory(Path.GetDirectoryName(ListFolder)!);
        File.WriteAllText(ListFolder, "not a folder");
        StepLeftPartWay(List());
        UndoTrailLine line = Assert.Single(_trail);
        Assert.Equal(UndoTrail.CouldNotRecordWords("publishPages", "the list could not be written", UndoUnrecordedChange.StoppedPartWay), line.Words);
    }

    private sealed class ThrowingMaintainers : IUndoMaintainers
    {
        public bool CanRun(string maintainer) => true;
        public void Rederive(UndoOp op, string root) => throw new InvalidOperationException("a front page that could not be worked out");
    }

    /// <summary>
    /// Review 1, MEDIUM 4: something unforeseen thrown while the front page is
    /// re-derived, after the swap, is never said as "Nothing was changed":
    /// the pages are in, the step stands, and no line says nothing changed.
    /// </summary>
    [Fact]
    public void AFrontPageThatThrowsAfterTheSwapIsNeverSaidAsNothingChanged()
    {
        ACourse();
        UndoForThisProcess list = List();
        var step = new UndoActionStep(new UndoStepMaker("menu", "publishPages"), Folder, "ICS3U", 1, undo: list,
                                      door: DoorOver(list, maintainers: new ThrowingMaintainers()));
        step.Write(Full(Day2), Class(2, draft: false));
        step.KeepsTheFrontPageTrue(1, Full(Index));

        step.Make();

        Assert.Equal(Class(2, draft: false), File.ReadAllText(Full(Day2)));
        Assert.Single(Begins());
        Assert.Empty(_trail);
    }

    /// <summary>
    /// Review 1, MEDIUM 3: today's in-memory undo keeps a page's earlier
    /// content as it was on the disk, so a UTF-16 page comes back byte for
    /// byte at Undo Last Change (it used to keep the text read as UTF-8).
    /// </summary>
    [Fact]
    public void AUtf16PageComesBackByteForByteAtTodaysUndo()
    {
        ACourse();
        File.WriteAllText(Full(Day2), Class(2, draft: true), new UnicodeEncoding(bigEndian: false, byteOrderMark: true));
        byte[] before = File.ReadAllBytes(Full(Day2));
        var history = new UndoHistory();
        var workspace = new AssistWorkspace(Folder, new NoLaunchers(), undo: history) { Surface = AssistSurface.Menu, UndoList = List() };
        // The step an action makes, told to today's undo as an action tells it.
        using (var recording = UndoHistory.Record(history, "published “Unit 1, Day 2” in ICS3U Section 1"))
        {
            UndoActionStep step = workspace.NewUndoStep("publishPages", "ICS3U", 1);
            step.Write(Full(Day2), step.ReadText(Full(Day2)).Replace("draft: true", "draft: false"));
            workspace.MakeTheUndoStep(step);
            recording.Done();
        }
        Assert.Contains("draft: false", File.ReadAllText(Full(Day2)), StringComparison.Ordinal);
        Assert.Equal(Class(2, draft: true), Assert.Single(history.Entries).Files[Full(Day2)].Before);
        history.Undo();

        Assert.Equal(before, File.ReadAllBytes(Full(Day2)));
    }

    private sealed class NoLaunchers : ILauncherRunner
    {
        public Task<LaunchOutcome> Run(string launcher, IReadOnlyList<string> arguments, string workingFolder,
                                                              IProgress<string>? progress, CancellationToken cancellation) =>
            throw new InvalidOperationException("No launcher in this test.");
    }
}

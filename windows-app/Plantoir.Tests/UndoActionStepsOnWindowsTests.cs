using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;
using Plantoir.Mcp;

namespace Plantoir.Tests;

/// <summary>
/// The mac's recorded section (<c>UndoActionStepsTests.section(surface:)</c>)
/// laid down on Windows, and each converted Windows action run on it the way
/// the mac's test ran its own (#899 W7b1). The pages the recorded step names
/// are laid from that step's <c>before</c> in <c>undo-action-steps.json</c>;
/// the rest of the section (the pages it does not touch, the front page, the
/// curriculum page) is the mac fixture's, which the before of every recorded
/// step that names one of them checks (<see cref="UndoActionStepsOnWindowsTests.TheFixtureIsTheMacsWhereverARecordedStepNamesAFile"/>).
/// </summary>
internal static class WindowsActionsOnTheMacFixture
{
    // ---- Stored properties ---------------------------------------------------------

    internal const string Course = "ICS3U";

    private static readonly Lazy<JsonDocument> StepsDocument =
        new(() => JsonDocument.Parse(File.ReadAllText(ContractLoader.GetContractPath("undo-action-steps.json"))));

    /// <summary>The recorded steps whose Windows action makes its step through the door, by name.</summary>
    internal static readonly IReadOnlyList<string> Converted =
    [
        "publishPages", "hidePages", "publishPagesAWholeUnit", "publishClassForADate",
        "addNextClass", "addNextClassInANewUnit", "addClasses",
    ];

    // ---- Functions -----------------------------------------------------------------

    internal static JsonElement Recorded(string stepName) =>
        StepsDocument.Value.RootElement.GetProperty("steps").EnumerateArray()
            .Single(candidate => candidate.GetProperty("name").GetString() == stepName);

    internal static IEnumerable<JsonElement> EveryRecordedStep() =>
        StepsDocument.Value.RootElement.GetProperty("steps").EnumerateArray();

    internal static byte[]? Bytes(JsonElement text) =>
        text.ValueKind == JsonValueKind.Null ? null : new UTF8Encoding(false).GetBytes(text.GetString()!);

    /// <summary>The mac fixture's files that no recorded step's own files lay: each path relative to the working folder, and its text.</summary>
    internal static IReadOnlyList<(string Path, string Text)> MacSection() =>
    [
        ("courses/ICS3U/section1/All Classes/Unit 1, Day 1.md", MacPage("Unit 1, Day 1", "true", "2026-09-08", "One.")),
        ("courses/ICS3U/section1/All Classes/Unit 1, Day 2.md", MacPage("Unit 1, Day 2", "false", "2026-09-10", "Two.")),
        ("courses/ICS3U/section1/All Classes/Unit 1, Day 3.md", MacPage("Unit 1, Day 3", "false", "2026-09-14", "Three.")),
        ("courses/ICS3U/section1/All Classes/Unit 2, Day 1.md", MacPage("Unit 2, Day 1", "false", "2026-09-16", "See [[Unit 1, Day 2]].")),
        ("courses/ICS3U/Curriculum/A1.1.md",
         "---\ntranscludeTitleSize: h4\ntags:\n  - A1\n---\nuse a variety of problem-solving strategies to solve programming problems ^text\n"),
        ("courses/ICS3U/Concepts/Loops.md",
         "---\ntitle: Loops\npublishForSection1: true\ncreatedSection1: 2026-09-08T07:00:00.000-0400\n---\n\nA loop repeats work.\n"),
        ("courses/ICS3U/section1/index.md",
         "---\ntitle: Section 1\npublish: true\ncreated: 2026-09-08T07:00:00.000-0400\n---\n# Most Recent Class\n\n![[Unit 1, Day 1]]\n"),
    ];

    /// <summary>A page as the mac's <c>AssistFixture.write(page:publish:date:body:in:)</c> writes it.</summary>
    private static string MacPage(string title, string publish, string date, string body) =>
        $"---\ntitle: {title}\npublish: {publish}\ncreated: {date}T07:00:00.000-0400\n---\n\n{body}";

    /// <summary>
    /// Lays the mac's section in <paramref name="workingFolder"/>: Windows'
    /// course settings and marker (the mac's are its own), the section's
    /// remembered dates as <c>rememberTimetable</c>'s before holds them, the
    /// fixture's pages, then every file of <paramref name="recorded"/> from
    /// its before (absent where it is null).
    /// </summary>
    internal static void Lay(string workingFolder, JsonElement recorded)
    {
        string course = Path.Combine(workingFolder, "courses", Course);
        Directory.CreateDirectory(course);
        File.WriteAllText(Path.Combine(course, "course_config.json"),
            "{\"course_code\":\"ICS3U\",\"course_name\":\"Introduction to Computer Science\",\"num_sections\":1,\"section_numbers\":[1],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[]}");
        File.WriteAllText(Path.Combine(workingFolder, Workspace.MarkerLauncher), "");
        JsonElement timetable = Recorded("rememberTimetable").GetProperty("files")[0];
        WriteAt(workingFolder, timetable.GetProperty("path").GetString()!, Bytes(timetable.GetProperty("before")));
        foreach ((string path, string text) in MacSection()) WriteAt(workingFolder, path, new UTF8Encoding(false).GetBytes(text));
        foreach (JsonElement file in recorded.GetProperty("files").EnumerateArray())
            WriteAt(workingFolder, file.GetProperty("path").GetString()!, Bytes(file.GetProperty("before")));
    }

    private static void WriteAt(string workingFolder, string relative, byte[]? bytes)
    {
        string full = UndoDoor.FullPath(workingFolder, relative);
        if (bytes is null)
        {
            if (File.Exists(full)) File.Delete(full);
            return;
        }
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllBytes(full, bytes);
    }

    /// <summary>The surface a recorded <c>madeBy</c> names.</summary>
    internal static AssistSurface SurfaceFor(string madeBy) => madeBy switch
    {
        "menu" => AssistSurface.Menu,
        "builtInAssistant" => AssistSurface.LocalWindow,
        "outsideAssistant" => AssistSurface.Outside,
        _ => throw new InvalidOperationException($"No Windows surface makes a step as “{madeBy}”."),
    };

    /// <summary>
    /// Runs the REAL Windows action of a converted step with the arguments
    /// the mac's <c>UndoActionStepsTests.recordEveryAction</c> gave its own,
    /// through the tool every Windows surface reaches it by. Returns what it
    /// answered.
    /// </summary>
    internal static string Run(string stepName, AssistWorkspace workspace)
    {
        var tools = new PlantoirTools(workspace);
        CallToolResult answered = stepName switch
        {
            "publishPages" => tools.PublishPages(Course, 1, pages: ["Unit 1, Day 2"], preview: false).GetAwaiter().GetResult(),
            "hidePages" => tools.UnpublishPages(Course, 1, pages: ["Unit 1, Day 1"], preview: false).GetAwaiter().GetResult(),
            "publishPagesAWholeUnit" => tools.PublishPages(Course, 1, pages: ["Unit 1"], preview: false).GetAwaiter().GetResult(),
            "publishClassForADate" => tools.PublishClassOn(Course, 1, "2026-09-10", null!, CancellationToken.None, preview: false).GetAwaiter().GetResult(),
            "addNextClass" => tools.AddNextClass(Course, 1),
            "addNextClassInANewUnit" => tools.AddNextClass(Course, 1, unit: "next"),
            "addClasses" => tools.AddClasses(Course, 1, unit: 2, howMany: 2),
            _ => throw new InvalidOperationException($"{stepName}: no Windows action is converted for it yet"),
        };
        return string.Join("\n", answered.Content.OfType<TextContentBlock>().Select(block => block.Text));
    }

    /// <summary>The newest begin line in a list folder, or null.</summary>
    internal static JsonObject? NewestBegin(string journalFolder)
    {
        JsonObject? last = null;
        if (!Directory.Exists(journalFolder)) return null;
        foreach (string segment in Directory.EnumerateFiles(journalFolder, "journal-*.jsonl").Order(StringComparer.Ordinal))
        {
            foreach (string line in File.ReadAllLines(segment))
            {
                if (JsonNode.Parse(line) is JsonObject read && (string?)read["event"] == "begin") last = read;
            }
        }
        return last;
    }

    /// <summary>How many begin lines a list folder holds.</summary>
    internal static int Begins(string journalFolder)
    {
        int count = 0;
        if (!Directory.Exists(journalFolder)) return 0;
        foreach (string segment in Directory.EnumerateFiles(journalFolder, "journal-*.jsonl"))
        {
            foreach (string line in File.ReadAllLines(segment))
            {
                if (JsonNode.Parse(line) is JsonObject read && (string?)read["event"] == "begin") count++;
            }
        }
        return count;
    }
}

/// <summary>
/// #899 W7b1, item 0: each converted Windows action, run on the mac's
/// fixture with the mac's arguments and surface, leaves ONE new begin line
/// that is the recorded step's: its key, its <c>madeBy</c> word, its files in
/// the recorded order, its op kinds, its recomputes, and each file's after.
/// A recorded step whose Windows action is not converted yet is held by name
/// in <see cref="NamedGapLedger.UndoActionStepsOnWindows"/> and must still
/// fail.
/// </summary>
public sealed class UndoActionStepsOnWindowsTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-steps-on-windows-");

    // ---- Computed properties ---------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    public static IEnumerable<object[]> RecordedSteps() =>
        WindowsActionsOnTheMacFixture.EveryRecordedStep().Select(step => new object[] { step.GetProperty("name").GetString()! });

    /// <summary>Every step held open by name is one the contract still records.</summary>
    [Fact]
    public void EveryHeldStepIsStillInTheContract() =>
        NamedGapLedger.StillNamed(NamedGapLedger.UndoActionStepsOnWindows, RecordedSteps().Select(row => (string)row[0]));

    /// <summary>A step is converted or held, never both.</summary>
    [Fact]
    public void NoConvertedStepIsHeld()
    {
        foreach (string name in WindowsActionsOnTheMacFixture.Converted)
            Assert.Null(NamedGapLedger.Holding(NamedGapLedger.UndoActionStepsOnWindows, name));
    }

    /// <summary>The fixture's pages are the mac's wherever a recorded step names one: never a page this class made up.</summary>
    [Fact]
    public void TheFixtureIsTheMacsWhereverARecordedStepNamesAFile()
    {
        int checkedFiles = 0;
        foreach ((string path, string text) in WindowsActionsOnTheMacFixture.MacSection())
        {
            foreach (string name in new[] { "publishPages", "hidePages", "publishPagesAWholeUnit", "makeRoomForClasses", "addCurriculumMentions" })
            {
                foreach (JsonElement file in WindowsActionsOnTheMacFixture.Recorded(name).GetProperty("files").EnumerateArray())
                {
                    if (file.GetProperty("path").GetString() != path) continue;
                    Assert.True(file.GetProperty("before").GetString() == text, $"{name}: {path}'s before is not the fixture's");
                    checkedFiles++;
                }
            }
        }
        Assert.True(checkedFiles >= 6, $"only {checkedFiles} of the fixture's files are checked against a recorded before");
    }

    [Theory]
    [MemberData(nameof(RecordedSteps))]
    public void TheWindowsActionLeavesTheRecordedStep(string name)
    {
        if (NamedGapLedger.Holding(NamedGapLedger.UndoActionStepsOnWindows, name) is { } held)
        {
            NamedGapLedger.HeldCaseStillStopsAtItsGap(held, () => MakeAndMatch(name), "no Windows action is converted for it yet", "named ");
            return;
        }
        MakeAndMatch(name);
    }

    private void MakeAndMatch(string name)
    {
        if (!WindowsActionsOnTheMacFixture.Converted.Contains(name))
            throw new InvalidOperationException($"{name}: no Windows action is converted for it yet");
        JsonElement recorded = WindowsActionsOnTheMacFixture.Recorded(name);
        WindowsActionsOnTheMacFixture.Lay(Folder, recorded);
        string madeBy = recorded.GetProperty("madeBy").GetString()!;
        var workspace = new AssistWorkspace(Folder, new FakeLauncher())
        {
            Surface = WindowsActionsOnTheMacFixture.SurfaceFor(madeBy),
            UndoList = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null),
        };
        int beginsBefore = WindowsActionsOnTheMacFixture.Begins(ListFolder);
        string answered = WindowsActionsOnTheMacFixture.Run(name, workspace);
        Assert.True(beginsBefore + 1 == WindowsActionsOnTheMacFixture.Begins(ListFolder), $"{name}: not one new step: {answered}");
        JsonObject step = WindowsActionsOnTheMacFixture.NewestBegin(ListFolder)!["step"]!.AsObject();

        Assert.Equal(recorded.GetProperty("action").GetString(), (string?)step["action"]!["key"]);
        string madeByWord = ((string)step["madeBy"]!).Split(':')[0];
        Assert.Equal(madeBy, madeByWord);

        var kinds = new List<string>();
        var paths = new List<string>();
        var recomputes = new List<string>();
        foreach (JsonNode? op in step["ops"]!.AsArray())
        {
            string kind = (string)op!["kind"]!;
            kinds.Add(kind);
            if (kind == UndoOp.Recompute)
            {
                recomputes.Add((string)op["maintainer"]! + " " + (string)op["path"]! + " " + (long)op["section"]!);
                continue;
            }
            string path = (string)op["path"]!;
            if (!paths.Contains(path)) paths.Add(path);
        }
        var recordedPaths = new List<string>();
        foreach (JsonElement file in recorded.GetProperty("files").EnumerateArray()) recordedPaths.Add(file.GetProperty("path").GetString()!);
        Assert.True(recordedPaths.SequenceEqual(paths), $"{name}: files {string.Join(" | ", paths)}");
        var recordedKinds = recorded.GetProperty("ops").EnumerateArray().Select(op => op.GetString()!).ToList();
        Assert.True(recordedKinds.SequenceEqual(kinds), $"{name}: ops {string.Join(",", kinds)}");
        var recordedRecomputes = new List<string>();
        foreach (JsonElement recompute in recorded.GetProperty("recomputes").EnumerateArray())
            recordedRecomputes.Add(recompute.GetProperty("maintainer").GetString() + " " + recompute.GetProperty("path").GetString() + " " + recompute.GetProperty("section").GetInt64());
        Assert.True(recordedRecomputes.SequenceEqual(recomputes), $"{name}: recomputes {string.Join(" | ", recomputes)}");

        foreach (JsonElement file in recorded.GetProperty("files").EnumerateArray())
        {
            string path = file.GetProperty("path").GetString()!;
            string full = UndoDoor.FullPath(Folder, path);
            byte[]? want = WindowsActionsOnTheMacFixture.Bytes(file.GetProperty("after"));
            byte[]? have = File.Exists(full) ? File.ReadAllBytes(full) : null;
            Assert.True(want is null ? have is null : have is not null && want.AsSpan().SequenceEqual(have),
                        $"{name}: {path} after is not the recorded after:\n{(have is null ? "(absent)" : Encoding.UTF8.GetString(have))}");
        }
    }
}

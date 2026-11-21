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
        "addNextClass", "addNextClassInANewUnit", "addClasses", "addCurriculumMentions", "rememberTimetable",
    ];

    /// <summary>
    /// A converted step whose file is JSON Windows writes in its own way,
    /// measured: by step name, the members that must be the mac's and why the
    /// rest differ. Its traces make the recorded step's draft.
    /// </summary>
    internal static readonly IReadOnlyDictionary<string, (string[] SameMembers, string Why)> WindowsOwnJson =
        new Dictionary<string, (string[], string)>(StringComparer.Ordinal)
        {
            ["rememberTimetable"] = (["section", "dates"],
                "Windows writes the timetable as it always has (System.Text.Json, indented two spaces, \"key\": value, its members section, dates, source, recorded in that order, no newline at the end), where the mac's JSONSerialization writes sorted keys with \" : \" and a closing newline; recorded is the day it is written (the mac's test fixed it at 2026-09-08), and a source not given is Windows' \"the teacher\" where the mac's is \"not recorded\". Both readers look members up by name"),
        };

    /// <summary>
    /// A converted step whose Windows after differs from the mac's for a
    /// reason that is Windows' own, measured (never retyped): by step name,
    /// the one line that differs and why. Its traces make the recorded
    /// step's draft, since their hashes are of the mac's bytes.
    /// </summary>
    internal static readonly IReadOnlyDictionary<string, (string After, string Why)> WindowsOwnLine =
        new Dictionary<string, (string, string)>(StringComparer.Ordinal)
        {
            ["addCurriculumMentions"] = ("%%curriculum-start%%",
                "the line under the block's start marker is Windows' own (“Today's work points here:”, since the block was first written on Windows), where the mac writes “## Curriculum connection”; with the switch off a teacher meets nothing different from before, so it is kept and measured"),
        };

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
            "{\"course_code\":\"ICS3U\",\"course_name\":\"Introduction to Computer Science\",\"num_sections\":1,\"section_numbers\":[1],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[],\"shared_folders\":[\"Curriculum\",\"Concepts\"]}");
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
            "addCurriculumMentions" => tools.AddCurriculumMentions(Course, 1, page: "Loops", codes: "A1.1"),
            "rememberTimetable" => tools.RememberTimetable(Course, 1, "2026-09-08; 2026-09-10; 2026-09-14"),
            _ => throw new InvalidOperationException($"{stepName}: no Windows action is converted for it yet"),
        };
        return string.Join("\n", answered.Content.OfType<TextContentBlock>().Select(block => block.Text));
    }

    /// <summary>
    /// The held steps whose Windows action exists and runs on this fixture:
    /// each is run, the way <see cref="Run"/> runs a converted one, with the
    /// mac's arguments, so a held row is proven to fall short for its named
    /// reason (it writes its files and leaves no step of its own), never by a
    /// guard that can only throw.
    /// </summary>
    internal static readonly IReadOnlyList<string> HeldButRunnable =
    [
        "makeRoomForClasses", "duplicateClass", "reDateClasses", "writeHowITeach", "getReadyForTheStartOfTheYear",
    ];

    /// <summary>Runs the REAL Windows action of a held step that has one here (<see cref="HeldButRunnable"/>), with the mac's arguments.</summary>
    internal static string RunHeld(string stepName, AssistWorkspace workspace)
    {
        var tools = new PlantoirTools(workspace);
        CallToolResult answered = stepName switch
        {
            "makeRoomForClasses" => tools.MakeRoomForClasses(Course, 1, unit: 1, atDay: 2),
            "duplicateClass" => tools.AddNextClass(Course, 1, duplicate: "Unit 1, Day 1"),
            "reDateClasses" => tools.ReDateClasses(Course, 1).GetAwaiter().GetResult(),
            "writeHowITeach" => tools.WriteHowITeach(Course, "I start every class with a question."),
            "getReadyForTheStartOfTheYear" => tools.PrepareForStartOfYear(Course, 1, workspace.PlanStartOfYear(Course, 1).Code),
            _ => throw new InvalidOperationException($"{stepName}: not a held step this fixture can run"),
        };
        return string.Join("\n", answered.Content.OfType<TextContentBlock>().Select(block => block.Text));
    }

    /// <summary>The action keys of every begin line in a list folder, oldest first.</summary>
    internal static List<string> BeginKeys(string journalFolder)
    {
        var keys = new List<string>();
        if (!Directory.Exists(journalFolder)) return keys;
        foreach (string segment in Directory.EnumerateFiles(journalFolder, "journal-*.jsonl").Order(StringComparer.Ordinal))
        {
            foreach (string line in File.ReadAllLines(segment))
            {
                if (JsonNode.Parse(line) is JsonObject read && (string?)read["event"] == "begin")
                    keys.Add((string?)read["step"]?["action"]?["key"] ?? "");
            }
        }
        return keys;
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
        foreach (string name in WindowsActionsOnTheMacFixture.HeldButRunnable)
            Assert.True(NamedGapLedger.Holding(NamedGapLedger.UndoActionStepsOnWindows, name) is not null, $"{name} is run as held and is not held");
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

    /// <summary>
    /// Curriculum mentions on a page that cannot be written (read-only): the
    /// step is refused before anything changes, said as "Nothing was
    /// changed", no step on the list, the page as it was.
    /// </summary>
    [Fact]
    public void CurriculumMentionsOnAPageThatCannotBeWrittenChangeNothing()
    {
        JsonElement recorded = WindowsActionsOnTheMacFixture.Recorded("addCurriculumMentions");
        WindowsActionsOnTheMacFixture.Lay(Folder, recorded);
        string page = UndoDoor.FullPath(Folder, recorded.GetProperty("files")[0].GetProperty("path").GetString()!);
        byte[] before = File.ReadAllBytes(page);
        File.SetAttributes(page, FileAttributes.ReadOnly);
        try
        {
            var workspace = new AssistWorkspace(Folder, new FakeLauncher())
            {
                Surface = AssistSurface.Outside,
                UndoList = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null),
            };
            string answered = WindowsActionsOnTheMacFixture.Run("addCurriculumMentions", workspace);

            Assert.StartsWith("Nothing was changed: ", answered);
            Assert.Equal(before, File.ReadAllBytes(page));
            Assert.Equal(0, WindowsActionsOnTheMacFixture.Begins(ListFolder));
        }
        finally { File.SetAttributes(page, FileAttributes.Normal); }
    }

    [Theory]
    [MemberData(nameof(RecordedSteps))]
    public void TheWindowsActionLeavesTheRecordedStep(string name)
    {
        if (NamedGapLedger.Holding(NamedGapLedger.UndoActionStepsOnWindows, name) is { } held)
        {
            if (WindowsActionsOnTheMacFixture.HeldButRunnable.Contains(name))
                NamedGapLedger.HeldCaseStillStopsAtItsGap(held, () => HeldStillWritesWithoutItsStep(name), "wrote its files with no step of its own");
            else
                NamedGapLedger.HeldCaseStillStopsAtItsGap(held, () => MakeAndMatch(name), "no Windows action is converted for it yet");
            return;
        }
        MakeAndMatch(name);
    }

    /// <summary>
    /// A held step whose Windows action exists here: run it on the mac's
    /// fixture with the mac's arguments. It falls short for the reason the
    /// ledger names only when it CHANGED one of the recorded step's files and
    /// left no begin line under the recorded key. An action that changed
    /// nothing fails for another reason (a real failure); one that now makes
    /// the recorded step returns, which the ledger reads as the gap closing.
    /// </summary>
    private void HeldStillWritesWithoutItsStep(string name)
    {
        JsonElement recorded = WindowsActionsOnTheMacFixture.Recorded(name);
        WindowsActionsOnTheMacFixture.Lay(Folder, recorded);
        string key = recorded.GetProperty("action").GetString()!;
        var workspace = new AssistWorkspace(Folder, new FakeLauncher())
        {
            Surface = WindowsActionsOnTheMacFixture.SurfaceFor(recorded.GetProperty("madeBy").GetString()!.Split(':')[0]),
            UndoList = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null),
        };
        int keyedBefore = WindowsActionsOnTheMacFixture.BeginKeys(ListFolder).Count(made => made == key);
        string answered = WindowsActionsOnTheMacFixture.RunHeld(name, workspace);
        if (WindowsActionsOnTheMacFixture.BeginKeys(ListFolder).Count(made => made == key) > keyedBefore) return;

        var changed = new List<string>();
        foreach (JsonElement file in recorded.GetProperty("files").EnumerateArray())
        {
            string path = file.GetProperty("path").GetString()!;
            string full = UndoDoor.FullPath(Folder, path);
            byte[]? before = WindowsActionsOnTheMacFixture.Bytes(file.GetProperty("before"));
            byte[]? now = File.Exists(full) ? File.ReadAllBytes(full) : null;
            bool same = before is null ? now is null : now is not null && before.AsSpan().SequenceEqual(now);
            if (!same) changed.Add(path);
        }
        if (changed.Count == 0)
            throw new InvalidOperationException($"{name}: the Windows action changed none of the recorded step's files: {answered}");
        throw new InvalidOperationException($"{name}: wrote its files with no step of its own ({string.Join(" | ", changed)})");
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
            if (WindowsActionsOnTheMacFixture.WindowsOwnJson.TryGetValue(name, out var json))
            {
                Assert.NotNull(want);
                Assert.NotNull(have);
                Assert.False(want!.AsSpan().SequenceEqual(have), $"{name}: {path} is now the mac's bytes: the measured difference closed");
                JsonNode mac = JsonNode.Parse(want)!;
                JsonNode windows = JsonNode.Parse(have!)!;
                foreach (string member in json.SameMembers)
                    Assert.True(JsonNode.DeepEquals(mac[member], windows[member]), $"{name}: {path}'s {member} is {windows[member]?.ToJsonString()}");
                continue;
            }
            if (WindowsActionsOnTheMacFixture.WindowsOwnLine.TryGetValue(name, out var own))
            {
                // Measured: the same lines but ONE, the line after the named
                // one, and that line differs (a difference that closed would
                // fail here, and the entry would go).
                Assert.NotNull(want);
                Assert.NotNull(have);
                string[] mac = Encoding.UTF8.GetString(want!).Split('\n');
                string[] windows = Encoding.UTF8.GetString(have!).Split('\n');
                Assert.True(mac.Length == windows.Length, $"{name}: {path} has {windows.Length} lines, the mac's {mac.Length}");
                var differing = new List<int>();
                for (int line = 0; line < mac.Length; line++)
                {
                    if (mac[line] != windows[line]) differing.Add(line);
                }
                int only = Assert.Single(differing);
                Assert.True(only > 0 && windows[only - 1] == own.After, $"{name}: {path} differs at line {only + 1}, not after “{own.After}”");
                continue;
            }
            Assert.True(want is null ? have is null : have is not null && want.AsSpan().SequenceEqual(have),
                        $"{name}: {path} after is not the recorded after:\n{(have is null ? "(absent)" : Encoding.UTF8.GetString(have))}");
        }
    }
}

using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7b1: Class Dates (<c>TimetableMemory.Write</c>, from the Class Dates
/// dialog, <c>remember_timetable</c> and the built-in assistant) is ONE step
/// through the door (the mac's <c>applyRememberTimetable</c>, key
/// <c>rememberTimetable</c>): the section's timetable file, its folder made
/// by the swap, its maker given by the caller, no step when nothing changes,
/// and a file that cannot be written costs only the record (false, as before).
/// </summary>
public sealed class UndoClassDatesStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private static readonly DateOnly Today = new(2026, 8, 14);
    private static readonly DateOnly[] Dates = [new(2026, 9, 8), new(2026, 9, 10), new(2026, 9, 14)];
    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-class-dates-");

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string TimetablePath => Path.Combine(Folder, "courses", "ICS3U", ".internal", "timetable", "section1.json");

    // ---- Initializer ---------------------------------------------------------------

    public UndoClassDatesStepTests() => Directory.CreateDirectory(Path.Combine(Folder, "courses", "ICS3U"));

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private bool Remember(IEnumerable<DateOnly> dates, string madeBy = "sheet") =>
        TimetableMemory.Write(Folder, "ICS3U", 1, dates, "block H", Today, new UndoStepMaker(madeBy, "rememberTimetable"),
                              new UndoForThisProcess(ListFolder, UndoMode.Shadow, null));

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
    public void RememberedDatesAreOneStepAndTheFolderIsMadeWithIt()
    {
        Assert.False(Directory.Exists(Path.GetDirectoryName(TimetablePath)));

        Assert.True(Remember(Dates));

        JsonObject step = Assert.Single(Begins())["step"]!.AsObject();
        Assert.Equal("rememberTimetable", (string?)step["action"]!["key"]);
        Assert.Equal("sheet", (string?)step["madeBy"]);
        JsonNode op = Assert.Single(step["ops"]!.AsArray())!;
        Assert.Equal("courses/ICS3U/.internal/timetable/section1.json", (string?)op["path"]);
        Assert.Equal(3, TimetableMemory.Read(Folder, "ICS3U", 1)!.Dates.Count);
    }

    [Fact]
    public void TheSameDatesAgainMakeNoStep()
    {
        Assert.True(Remember(Dates));
        byte[] written = File.ReadAllBytes(TimetablePath);

        Assert.True(Remember(Dates));

        Assert.Single(Begins());
        Assert.Equal(written, File.ReadAllBytes(TimetablePath));
    }

    [Fact]
    public void ATimetableThatCannotBeWrittenCostsOnlyTheRecord()
    {
        Assert.True(Remember(Dates));
        byte[] written = File.ReadAllBytes(TimetablePath);
        File.SetAttributes(TimetablePath, FileAttributes.ReadOnly);
        try
        {
            Assert.False(Remember([new DateOnly(2026, 9, 21)]));
            Assert.Equal(written, File.ReadAllBytes(TimetablePath));
        }
        finally { File.SetAttributes(TimetablePath, FileAttributes.Normal); }
    }

    /// <summary>The tool's step is made by its caller's surface, on its workspace's list: the built-in assistant here.</summary>
    [Fact]
    public void TheToolsStepIsMadeByItsCaller()
    {
        File.WriteAllText(Path.Combine(Folder, Plantoir.Core.Models.Workspace.MarkerLauncher), "");
        File.WriteAllText(Path.Combine(Folder, "courses", "ICS3U", "course_config.json"),
            "{\"course_code\":\"ICS3U\",\"course_name\":\"A course\",\"num_sections\":1,\"section_numbers\":[1],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[]}");
        var workspace = new AssistWorkspace(Folder, new FakeLauncher())
        {
            Surface = AssistSurface.LocalWindow,
            UndoList = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null),
        };

        new Plantoir.Mcp.PlantoirTools(workspace).RememberTimetable("ICS3U", 1, "2026-09-08; 2026-09-10");

        JsonObject step = Assert.Single(Begins())["step"]!.AsObject();
        Assert.StartsWith("builtInAssistant:", (string?)step["madeBy"]);
        Assert.Equal("rememberTimetable", (string?)step["action"]!["key"]);
    }

    /// <summary>
    /// Another program writes into the timetable in place as it is saved, and
    /// putting it back fails: the dates are in and what the file held is kept
    /// beside it as a hidden file (the door's part way).
    /// </summary>
    private static UndoSeams TheTimetableIsLeftPartWay() => new()
    {
        BetweenKeepingAndRenaming = (_, fullPath) =>
        {
            using var inPlace = new FileStream(fullPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
            byte[] edit = System.Text.Encoding.UTF8.GetBytes("{ \"section\": 1, \"dates\": [] }");
            inPlace.Write(edit);
            inPlace.SetLength(edit.Length);
        },
        PutBackFailsAt = index => index == 0,
    };

    private string KeptTimetable() =>
        Assert.Single(Directory.GetFiles(Path.GetDirectoryName(TimetablePath)!, ".section1.json.plantoir-undo-*-orig"));

    /// <summary>
    /// Review 1, MEDIUM 1: a Class Dates step left part way is never a plain
    /// "remembered". The outcome says the dates are on disk AND names the
    /// hidden file that holds what the timetable held, in the contract's
    /// words (the mac's applyRememberTimetable rethrows leftPartWay).
    /// </summary>
    [Fact]
    public void ATimetableLeftPartWayNamesTheKeptFile()
    {
        Assert.True(Remember(Dates));
        var list = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null);
        var door = new UndoDoor(list.Journal, list.Mode, list.Maintainers, seams: TheTimetableIsLeftPartWay(), trail: list.Trail);
        var step = new UndoActionStep(new UndoStepMaker("sheet", "rememberTimetable"), Folder, "ICS3U", 1, undo: list, door: door);

        TimetableWriteOutcome written = TimetableMemory.WriteDown(Folder, "ICS3U", 1, [new DateOnly(2026, 9, 21)], "block H", Today, step);

        Assert.True(written.Remembered);
        Assert.NotNull(written.StoppedPartWay);
        string kept = KeptTimetable();
        Assert.Equal(TimetableMemory.KeptMessage([kept]), written.WhatWasKept);
        Assert.Contains(Path.GetFileName(kept), written.WhatWasKept, StringComparison.Ordinal);
        // True to the disk: the new date is what the timetable holds.
        Assert.Equal([new DateOnly(2026, 9, 21)], TimetableMemory.Read(Folder, "ICS3U", 1)!.Dates);
    }

    /// <summary>Review 1, MEDIUM 1: remember_timetable left part way answers the part-way sentence naming the kept file, never "Recorded".</summary>
    [Fact]
    public void TheToolSaysATimetableLeftPartWayAsPartWay()
    {
        Assert.True(Remember(Dates));
        File.WriteAllText(Path.Combine(Folder, Plantoir.Core.Models.Workspace.MarkerLauncher), "");
        File.WriteAllText(Path.Combine(Folder, "courses", "ICS3U", "course_config.json"),
            "{\"course_code\":\"ICS3U\",\"course_name\":\"A course\",\"num_sections\":1,\"section_numbers\":[1],\"per_section_folders\":[\"All Classes\"],\"per_section_files\":[]}");
        var workspace = new AssistWorkspace(Folder, new FakeLauncher())
        {
            Surface = AssistSurface.Outside,
            UndoList = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null),
            UndoSeams = TheTimetableIsLeftPartWay(),
        };

        string said = new Plantoir.Mcp.PlantoirTools(workspace).RememberTimetable("ICS3U", 1, "2026-09-21").Summary();

        Assert.StartsWith(AssistWording.PublishStoppedPartWay("the class dates", ""), said);
        Assert.Contains(Path.GetFileName(KeptTimetable()), said, StringComparison.Ordinal);
        Assert.DoesNotContain("Recorded", said, StringComparison.Ordinal);
    }

    /// <summary>The sheet's words for a timetable left part way are the contract's: classDatesAreRemembered, classDatesKeptLead and one classDatesKeptBesideIt per kept file.</summary>
    [Fact]
    public void TheSheetsWordsForAKeptTimetableAreTheContracts()
    {
        JsonObject rules = JsonNode.Parse(File.ReadAllText(ContractLoader.GetContractPath("shared-rules.json")))!.AsObject();
        JsonNode wording = rules["undo"]!["wording"]!;
        string kept = Path.Combine(Folder, ".section1.json.plantoir-undo-4-apply-orig");
        string expected = (string)wording["classDatesKeptLead"]! + " " + ((string)wording["classDatesKeptBesideIt"]!)
            .Replace("{place}", "“section1.json”").Replace("{kept}", ".section1.json.plantoir-undo-4-apply-orig");
        Assert.Equal(expected, TimetableMemory.KeptMessage([kept]));
    }
}

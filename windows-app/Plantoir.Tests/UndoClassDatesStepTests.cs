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
}

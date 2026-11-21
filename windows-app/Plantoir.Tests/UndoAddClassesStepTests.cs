using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7b1: Add Next Class, Add Next Class in a New Unit and Add Classes
/// (<c>AssistWorkspace.ApplyAddClasses</c>) are each ONE step through the
/// door (the mac's <c>PlaceholderClassPlanner.apply</c>, U3a): every new page
/// a <c>writeFile</c> with no before, the class folder made by the swap with
/// them, all or none, no <c>recompute</c>, and today's undo told of each page
/// as before.
/// </summary>
public sealed class UndoAddClassesStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private static readonly DateOnly Today = new(2026, 8, 14);
    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-add-classes-");
    private readonly List<UndoTrailLine> _trail = [];

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string CourseDirectory => Path.Combine(Folder, "courses", "ICS3U");
    private string ClassFolder => Path.Combine(CourseDirectory, "section1", "All Classes");

    // ---- Initializer ---------------------------------------------------------------

    public UndoAddClassesStepTests()
    {
        Directory.CreateDirectory(Path.Combine(CourseDirectory, "section1"));
        File.WriteAllText(Path.Combine(Folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(Folder, "deploy.ps1"), "# marker");
        File.WriteAllText(Path.Combine(CourseDirectory, "course_config.json"), """
            { "course_code": "ICS3U", "course_name": "A course",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
        Assert.True(TimetableMemory.Write(Folder, "ICS3U", 1,
            Enumerable.Range(0, 10).Select(i => new DateOnly(2026, 9, 8).AddDays(i * 2)), "block H", Today));
    }

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string PagePath(string title) => Path.Combine(ClassFolder, title + ".md");

    private AssistWorkspace Open(UndoHistory history) =>
        new(Folder, new FakeLauncher(), undo: history)
        {
            Surface = AssistSurface.Outside,
            UndoList = new UndoForThisProcess(ListFolder, UndoMode.Shadow, _trail.Add),
        };

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

    private static List<string> OpsOf(JsonObject begin, string field)
    {
        var found = new List<string>();
        foreach (JsonNode? op in begin["step"]!["ops"]!.AsArray()) found.Add((string)op![field]!);
        return found;
    }

    /// <summary>A section with no class folder yet: three new pages are one step, the folder made with them, each page a writeFile in the plan's order, no recompute.</summary>
    [Fact]
    public void ThreeNewClassesAreOneStepAndTheClassFolderIsMadeWithThem()
    {
        Assert.False(Directory.Exists(ClassFolder));
        var history = new UndoHistory();
        AssistWorkspace workspace = Open(history);
        NewClassesPlan plan = workspace.PlanAddClasses("ICS3U", 1, 1, 1, 3);

        AssistResult result = workspace.ApplyAddClasses(plan);

        Assert.True(result.Succeeded, result.Message);
        JsonObject begin = Assert.Single(Begins());
        Assert.Equal("addClasses", (string?)begin["step"]!["action"]!["key"]);
        Assert.Equal(["writeFile", "writeFile", "writeFile"], OpsOf(begin, "kind"));
        Assert.Equal(["courses/ICS3U/section1/All Classes/Unit 1, Day 1.md",
                      "courses/ICS3U/section1/All Classes/Unit 1, Day 2.md",
                      "courses/ICS3U/section1/All Classes/Unit 1, Day 3.md"], OpsOf(begin, "path"));
        foreach (string day in new[] { "Unit 1, Day 1", "Unit 1, Day 2", "Unit 1, Day 3" })
            Assert.Contains("publish: false", File.ReadAllText(PagePath(day)));
        // Today's undo takes the pages back, as it did.
        UndoHistory.Entry entry = Assert.Single(history.Entries);
        Assert.Equal(3, entry.Files.Count);
        history.Undo();
        Assert.False(File.Exists(PagePath("Unit 1, Day 1")));
        Assert.Empty(_trail);
    }

    /// <summary>A page that cannot be written (its name is taken by a folder) stops the action before ANY page is written: all or none, said as "Nothing was changed".</summary>
    [Fact]
    public void AClassThatCannotBeWrittenStopsEveryClassAndNoFolderIsLeft()
    {
        AssistWorkspace workspace = Open(new UndoHistory());
        NewClassesPlan plan = workspace.PlanAddClasses("ICS3U", 1, 1, 1, 3);
        Directory.CreateDirectory(PagePath("Unit 1, Day 3"));

        var refused = Assert.Throws<AssistRefusal>(() => workspace.ApplyAddClasses(plan));

        Assert.StartsWith("Nothing was changed: ", refused.Message);
        Assert.False(File.Exists(PagePath("Unit 1, Day 1")), "a page was written before the one that could not be");
        Assert.False(File.Exists(PagePath("Unit 1, Day 2")), "a page was written before the one that could not be");
        Assert.Empty(Begins());
    }

    /// <summary>Every page of the plan appeared while it was decided: the step changes nothing, so none is made and nothing is written.</summary>
    [Fact]
    public void ClassesThatAllAppearedInBetweenMakeNoStep()
    {
        var history = new UndoHistory();
        AssistWorkspace workspace = Open(history);
        NewClassesPlan plan = workspace.PlanAddClasses("ICS3U", 1, 1, 1, 2);
        Directory.CreateDirectory(ClassFolder);
        File.WriteAllText(PagePath("Unit 1, Day 1"), "mine");
        File.WriteAllText(PagePath("Unit 1, Day 2"), "mine too");

        workspace.ApplyAddClasses(plan);

        Assert.Empty(Begins());
        Assert.Equal("mine", File.ReadAllText(PagePath("Unit 1, Day 1")));
        Assert.Equal("mine too", File.ReadAllText(PagePath("Unit 1, Day 2")));
    }

    /// <summary>add_next_class names its step as the mac's does: addNextClass, and addNextClassInANewUnit for unit "next".</summary>
    [Theory]
    [InlineData("", "addNextClass")]
    [InlineData("next", "addNextClassInANewUnit")]
    public void TheNextClassIsNamedAsTheMacNamesIt(string unit, string key)
    {
        Directory.CreateDirectory(ClassFolder);
        File.WriteAllText(PagePath("Unit 1, Day 1"), "---\ntitle: Unit 1, Day 1\npublish: false\ncreated: 2026-09-08T07:00:00.000-0400\n---\nBody.\n");
        var tools = new Plantoir.Mcp.PlantoirTools(Open(new UndoHistory()));

        tools.AddNextClass("ICS3U", 1, unit: unit);

        JsonObject begin = Assert.Single(Begins());
        Assert.Equal(key, (string?)begin["step"]!["action"]!["key"]);
    }
}

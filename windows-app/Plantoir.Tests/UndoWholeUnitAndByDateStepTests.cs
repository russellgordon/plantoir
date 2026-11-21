using System.Text.Json.Nodes;
using ModelContextProtocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Undo;
using Plantoir.Mcp;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7a: a whole unit published or hidden, and Publish Class for a Date,
/// are each ONE step through the door (the mac's <c>publishPagesAWholeUnit</c>
/// and <c>publishClassForADate</c>, U3a): every class planned into the step
/// seeing the classes planned before it, the front page named once as a
/// <c>recompute</c>, and the kept record (<c>later-classes-kept.json</c>)
/// written only inside the publish's own step.
/// </summary>
public sealed class UndoWholeUnitAndByDateStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private static readonly DateOnly Today = new(2026, 10, 8);
    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-unit-step-");
    private readonly List<UndoTrailLine> _trail = [];

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string CourseDirectory => Path.Combine(Folder, "courses", "ICS3U");
    private string IndexPath => Path.Combine(CourseDirectory, "section1", "index.md");
    private string KeptPath => LaterClassesKept.PathFor(CourseDirectory, 1);

    // ---- Initializer ---------------------------------------------------------------

    public UndoWholeUnitAndByDateStepTests()
    {
        Directory.CreateDirectory(CourseDirectory);
        File.WriteAllText(Path.Combine(Folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(Folder, "deploy.ps1"), "# marker");
        File.WriteAllText(Path.Combine(CourseDirectory, "course_config.json"), """
            { "course_code": "ICS3U", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
        File.WriteAllText(IndexPath, "---\ntitle: Section 1\ncreated: 2026-10-01T07:00:00.000-0400\npublish: true\n---\n# Most Recent Class\n![[Unit 1, Day 1]]\n");
    }

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    // ---- Functions -----------------------------------------------------------------

    private string PagePath(string title) => Path.Combine(CourseDirectory, "section1", "All Classes", title + ".md");

    private void Class(string title, DateOnly day, bool published, string body = "Body.")
    {
        Directory.CreateDirectory(Path.GetDirectoryName(PagePath(title))!);
        File.WriteAllText(PagePath(title),
            $"---\npublish: {(published ? "true" : "false")}\ncreated: {DateText.Iso(day)}T07:00:00.000-0400\n---\n{body}\n");
    }

    private AssistWorkspace Open(UndoHistory history, UndoSeams? seams = null) =>
        new(Folder, new FakeLauncher(), undo: history)
        {
            Surface = AssistSurface.Menu,
            UndoList = new UndoForThisProcess(ListFolder, UndoMode.Shadow, _trail.Add),
            UndoSeams = seams,
            Today = () => Today,
        };

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

    private static List<string> OpsOf(JsonObject begin, string field)
    {
        var found = new List<string>();
        foreach (JsonNode? op in begin["step"]!["ops"]!.AsArray()) found.Add((string)op![field]!);
        return found;
    }

    /// <summary>A unit published is ONE step: every class, then the front page once, as a recompute; today's undo puts it all back.</summary>
    [Fact]
    public async Task AWholeUnitIsOneStepWithTheFrontPageNamedOnce()
    {
        Class("Unit 1, Day 1", Today.AddDays(-7), published: true);
        Class("Unit 2, Day 1", Today.AddDays(-2), published: false);
        Class("Unit 2, Day 2", Today.AddDays(-1), published: false);
        string indexBefore = File.ReadAllText(IndexPath);
        var history = new UndoHistory();
        var workspace = Open(history);

        var result = await workspace.ApplyWholeUnit("ICS3U", 1, 2, publishing: true, preview: false);

        Assert.True(result.Succeeded, result.Message);
        Assert.Contains("publish: true", File.ReadAllText(PagePath("Unit 2, Day 1")));
        Assert.Contains("publish: true", File.ReadAllText(PagePath("Unit 2, Day 2")));
        Assert.Contains("![[Unit 2, Day 2]]", File.ReadAllText(IndexPath));
        JsonObject begin = Assert.Single(Begins());
        Assert.Equal("publishPages", (string?)begin["step"]!["action"]!["key"]);
        Assert.Equal(["editLine", "editLine", "recompute"], OpsOf(begin, "kind"));
        Assert.Equal("courses/ICS3U/section1/index.md", OpsOf(begin, "path")[2]);
        Assert.Empty(_trail);

        UndoHistory.Entry entry = Assert.Single(history.Entries);
        Assert.Equal(indexBefore, entry.Files[IndexPath].Before);
        history.Undo();
        Assert.Contains("publish: false", File.ReadAllText(PagePath("Unit 2, Day 1")));
        Assert.Contains("publish: false", File.ReadAllText(PagePath("Unit 2, Day 2")));
        Assert.Equal(indexBefore, File.ReadAllText(IndexPath));
    }

    /// <summary>
    /// Each class of a unit is planned SEEING the classes before it in the
    /// step (the mac's <c>testAWholeUnitReadsWhatItsEarlierClassesPlanned</c>):
    /// hiding Day 2 first, then Day 1, the page both use comes down with
    /// Day 1, because Day 2 already reads as hidden. A planner that read the
    /// disk would see Day 2 still published and leave the page up.
    /// </summary>
    [Fact]
    public async Task AWholeUnitHiddenPlansEachClassSeeingTheOnesBefore()
    {
        Class("Unit 1, Day 1", Today.AddDays(-7), published: true);
        Class("Unit 2, Day 1", Today.AddDays(-2), published: true, body: "[[Shared]]");
        Class("Unit 2, Day 2", Today.AddDays(-1), published: true, body: "[[Shared]]");
        string shared = Path.Combine(CourseDirectory, "Concepts", "Shared.md");
        Directory.CreateDirectory(Path.GetDirectoryName(shared)!);
        File.WriteAllText(shared, "---\npublishForSection1: true\n---\nShared.\n");

        var result = await Open(new UndoHistory()).ApplyWholeUnit("ICS3U", 1, 2, publishing: false, preview: false);

        Assert.True(result.Succeeded, result.Message);
        Assert.Contains("publishForSection1: false", File.ReadAllText(shared));
        JsonObject begin = Assert.Single(Begins());
        Assert.Equal("hidePages", (string?)begin["step"]!["action"]!["key"]);
    }

    /// <summary>A unit that cannot be written whole is not written at all, and says "Nothing was changed" (all or none).</summary>
    [Fact]
    public async Task AWholeUnitThatCannotBeWrittenWholeChangesNothing()
    {
        Class("Unit 2, Day 1", Today.AddDays(-2), published: false);
        Class("Unit 2, Day 2", Today.AddDays(-1), published: false);
        File.SetAttributes(PagePath("Unit 2, Day 2"), FileAttributes.ReadOnly);
        try
        {
            var refused = await Assert.ThrowsAsync<AssistRefusal>(() =>
                Open(new UndoHistory()).ApplyWholeUnit("ICS3U", 1, 2, publishing: true, preview: false));

            Assert.Equal("Nothing was changed: Plantoir doesn’t have permission to change one of them.", refused.Message);
            Assert.Contains("publish: false", File.ReadAllText(PagePath("Unit 2, Day 1")));
        }
        finally { File.SetAttributes(PagePath("Unit 2, Day 2"), FileAttributes.Normal); }
    }

    private static async Task<string> PublishOn(AssistWorkspace workspace, DateOnly day) =>
        (await new PlantoirTools(workspace).PublishClassOn("ICS3U", 1, DateText.Iso(day),
            new Progress<ProgressNotificationValue>(_ => { }), default, preview: false)).Summary();

    /// <summary>
    /// Publish Class for a Date: the page and the kept record are ONE step
    /// (<c>publishClassForADate</c>); the record is not part of today's
    /// change, so Undo Last Change leaves it, as it did (the mac's U3 LOW 10).
    /// </summary>
    [Fact]
    public async Task PublishClassForADateKeepsTheClassItPublishesInTheSameStep()
    {
        Class("Unit 2, Day 3", Today, published: true);
        Class("Unit 2, Day 4", Today.AddDays(1), published: true);
        Class("Unit 2, Day 5", Today.AddDays(3), published: false);
        var history = new UndoHistory();

        await PublishOn(Open(history), Today.AddDays(3));

        Assert.Contains("publish: true", File.ReadAllText(PagePath("Unit 2, Day 5")));
        Assert.Equal(new[] { new LaterClassesKept.Row("section1/All Classes/Unit 2, Day 5", DateText.Iso(Today.AddDays(3))) },
                     LaterClassesKept.Read(CourseDirectory, 1));
        JsonObject begin = Assert.Single(Begins());
        Assert.Equal("publishClassForADate", (string?)begin["step"]!["action"]!["key"]);
        Assert.Contains("courses/ICS3U/.publish_state/section1.later-classes-kept.json", OpsOf(begin, "path"));
        UndoHistory.Entry entry = Assert.Single(history.Entries);
        Assert.False(entry.Files.ContainsKey(KeptPath), "today's undo was told of the kept record");
        string record = File.ReadAllText(KeptPath);
        history.Undo();
        Assert.Contains("publish: false", File.ReadAllText(PagePath("Unit 2, Day 5")));
        Assert.Equal(record, File.ReadAllText(KeptPath));
    }

    /// <summary>A publish by date that is refused keeps nothing: the record goes in only with the pages (the mac's <c>testAPublishClassForADateThatIsRefusedKeepsNothing</c>).</summary>
    [Fact]
    public async Task APublishClassForADateThatIsRefusedKeepsNothing()
    {
        Class("Unit 2, Day 3", Today, published: true);
        Class("Unit 2, Day 4", Today.AddDays(1), published: true);
        Class("Unit 2, Day 5", Today.AddDays(3), published: false);
        File.SetAttributes(PagePath("Unit 2, Day 5"), FileAttributes.ReadOnly);
        try
        {
            string said = await PublishOn(Open(new UndoHistory()), Today.AddDays(3));

            Assert.Equal("Nothing was changed: Plantoir doesn’t have permission to change one of them.", said);
            Assert.False(File.Exists(KeptPath), "a refused publish kept its class");
            Assert.Contains("publish: false", File.ReadAllText(PagePath("Unit 2, Day 5")));
        }
        finally { File.SetAttributes(PagePath("Unit 2, Day 5"), FileAttributes.Normal); }
    }

    /// <summary>A class already published, named by its date: its pages need no change, and the record is a step of its own.</summary>
    [Fact]
    public async Task AClassAlreadyPublishedByItsDateIsKeptOnAStepOfItsOwn()
    {
        Class("Unit 2, Day 3", Today, published: true);
        Class("Unit 2, Day 4", Today.AddDays(1), published: true);
        Class("Unit 2, Day 5", Today.AddDays(3), published: true);
        var history = new UndoHistory();

        await PublishOn(Open(history), Today.AddDays(3));

        Assert.Equal(new[] { new LaterClassesKept.Row("section1/All Classes/Unit 2, Day 5", DateText.Iso(Today.AddDays(3))) },
                     LaterClassesKept.Read(CourseDirectory, 1));
        JsonObject begin = Assert.Single(Begins());
        Assert.Equal("publishClassForADate", (string?)begin["step"]!["action"]!["key"]);
        Assert.Equal(["writeFile"], OpsOf(begin, "kind"));
        Assert.Empty(history.Entries);
    }

    /// <summary>
    /// Review 1, LOW: the could-not-write sentence, said when nothing could be
    /// staged beside a page that is not read-only (a full disk, or a folder
    /// whose permissions refuse a new file), names both, and nothing changed.
    /// </summary>
    [Fact]
    public async Task ACouldNotWriteRefusalSaysTheDiskOrThePermissionAndChangesNothing()
    {
        Class("Unit 2, Day 1", Today.AddDays(-2), published: false);
        string before = File.ReadAllText(PagePath("Unit 2, Day 1"));
        var workspace = Open(new UndoHistory(), new UndoSeams { StagingWriteFailsAt = index => index == 0 });

        var refused = await Assert.ThrowsAsync<AssistRefusal>(() =>
            workspace.Apply(workspace.PlanPublish("ICS3U", 1, ["Unit 2, Day 1"], draft: false, publishes: true), preview: false));

        Assert.Equal("Nothing was changed: nothing could be written beside “Unit 2, Day 1.md” " +
                     "(the disk may be full, or Plantoir may not have permission to write there).", refused.Message);
        Assert.Equal(before, File.ReadAllText(PagePath("Unit 2, Day 1")));
    }
}

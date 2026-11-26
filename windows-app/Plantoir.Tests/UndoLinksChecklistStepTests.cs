using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7b2-8: a press on the links checklist is ONE step, key
/// <c>answerTheLinksChecklist</c>, made by <c>sheet</c>, as the mac's
/// <c>LinksChecklistPublisher.publish</c> and <c>setAside</c>. Publish holds
/// every page it publishes and dates, then the answered record, then the
/// record of the later classes it published, all or none, and names no
/// recompute (the front page is not repointed, ruling F1, and the mac's
/// step names none). Not Now holds the answered record alone. Laid out on
/// <c>shared-rules.json</c> → <c>linksChecklist.publishCases</c>' case iv-b
/// (a ticked class with the pages it brings, one of them a ticked row). The
/// record alone, with the mac's values, is the fixture row
/// (<see cref="WindowsActionsOnTheMacFixture.Run"/>); the whole press has
/// no recorded row, so these prove it.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class UndoLinksChecklistStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private const string Key = "answerTheLinksChecklist";
    private const string Course = "ICS3U";
    private const string AnsweredPath = "courses/ICS3U/.publish_state/section1.links-checklist-answered.json";
    private const string KeptPath = "courses/ICS3U/.publish_state/section1.later-classes-kept.json";

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-links-checklist-");
    private readonly JsonObject _case;
    private readonly Dictionary<string, string> _pages;
    private readonly Dictionary<string, byte[]> _pagesBefore = new(StringComparer.Ordinal);

    // ---- Computed properties -------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string CourseDirectory => Path.Combine(Folder, "courses", Course);
    private string FrontPage => Path.Combine(CourseDirectory, "section1", "index.md");
    private string Answered => UndoDoor.FullPath(Folder, AnsweredPath);
    private string Kept => UndoDoor.FullPath(Folder, KeptPath);

    // ---- Initializer ---------------------------------------------------------------

    public UndoLinksChecklistStepTests()
    {
        ActivityTrail.SetCustomLogPathForTesting(Path.Combine(_root, "trail.txt"));
        Directory.CreateDirectory(CourseDirectory);
        File.WriteAllText(Path.Combine(Folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(Folder, "deploy.ps1"), "# marker");
        File.WriteAllText(Path.Combine(CourseDirectory, "course_config.json"), $$"""
            { "course_code": "{{Course}}", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
        _case = ContractLoader.LoadJson("shared-rules.json")!["linksChecklist"]!["publishCases"]!.AsArray()
            .First(c => c!["name"]!.ToString().StartsWith("iv-b.", StringComparison.Ordinal))!.AsObject();
        _pages = Lay(_case["pages"]!.AsArray());
        File.WriteAllText(FrontPage, "---\npublish: true\n---\n## Most Recent Class\n\n![[Unit 1, Day 1]]\n");
        foreach (var (title, path) in _pages) _pagesBefore[title] = File.ReadAllBytes(path);
    }

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try
        {
            if (File.Exists(Answered)) File.SetAttributes(Answered, FileAttributes.Normal);
            Directory.Delete(_root, recursive: true);
        }
        catch { }
    }

    private UndoForThisProcess List() => new(ListFolder, UndoMode.Shadow, null);

    /// <summary>The window's workspace for the sheet, on a test's list; today is before both classes, so a class published for 20 October is one Deploy would ask about.</summary>
    private AssistWorkspace Open(UndoHistory? history = null, UndoSeams? seams = null) =>
        new(Folder, new FakeLauncher(), undo: history)
        {
            Surface = AssistSurface.LocalWindow,
            UndoList = List(),
            UndoSeams = seams,
            Today = () => new DateOnly(2026, 9, 1),
        };

    /// <summary>The sheet opened on the case's offer, ticked as the case ticks it.</summary>
    private LinksChecklistSheet Sheet(AssistWorkspace workspace)
    {
        var rows = new List<LinksChecklistRow>();
        foreach (JsonNode? row in _case["offer"]!.AsArray())
        {
            var dependsOn = new List<string>();
            foreach (JsonNode? place in row!["dependsOn"] as JsonArray ?? new JsonArray()) dependsOn.Add(place!.ToString());
            rows.Add(new LinksChecklistRow(row["place"]!.ToString(), row["group"]!.ToString(), row["ticked"]!.GetValue<bool>(), dependsOn,
                Path.GetFileName(row["place"]!.ToString()), row["date"]?.ToString(), row["why"]?.ToString(), row["firstUsedIn"]?.ToString()));
        }
        LinksChecklistSheet sheet = workspace.OpenLinksChecklist(new LinksChecklistOffer(Course, 1, "build-1", rows));
        var ticked = new HashSet<string>(StringComparer.Ordinal);
        foreach (JsonNode? place in _case["tick"]!.AsArray()) ticked.Add(LinksChecklist.Key(place!.ToString()));
        foreach (LinksChecklistRow row in sheet.Rows) sheet.Ticks[LinksChecklist.Key(row.Place)] = ticked.Contains(LinksChecklist.Key(row.Place));
        return sheet;
    }

    private Dictionary<string, string> Lay(JsonArray pages)
    {
        var paths = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (JsonNode? page in pages)
        {
            string title = page!["title"]!.ToString();
            bool isClass = page["kind"]!.ToString() == "class";
            bool visible = page["visible"]!.GetValue<bool>();
            string date = page["date"]?.ToString() ?? "2026-02-01";
            string links = "";
            foreach (JsonNode? link in page["links"] as JsonArray ?? new JsonArray()) links += $"\nSee [[{link}]].\n";
            string path = isClass
                ? Path.Combine(CourseDirectory, "section1", "All Classes", title + ".md")
                : Path.Combine(CourseDirectory, "Concepts", title + ".md");
            string front = isClass
                ? $"publish: {(visible ? "true" : "false")}\ncreated: {date}T07:00:00.000-0400"
                : $"publishForSection1: {(visible ? "true" : "false")}\ncreatedSection1: {date}T07:00:00.000-0400";
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, $"---\n{front}\n---\nA sentence.\n{links}");
            paths[title] = path;
        }
        return paths;
    }

    /// <summary>The newest step's <c>madeBy</c>, the path of each op that names one (in order), and the kind of every op.</summary>
    private (string MadeBy, List<string> Paths, List<string> Kinds) NewestStep()
    {
        JsonObject step = WindowsActionsOnTheMacFixture.NewestBegin(ListFolder)!["step"]!.AsObject();
        var paths = new List<string>();
        var kinds = new List<string>();
        foreach (JsonNode? op in step["ops"]!.AsArray())
        {
            kinds.Add((string)op!["kind"]!);
            if ((string?)op["path"] is { } path && !paths.Contains(path)) paths.Add(path);
        }
        return ((string)step["madeBy"]!, paths, kinds);
    }

    private string Relative(string full) => Path.GetRelativePath(Folder, full).Replace('\\', '/');

    private void AssertNoPageChanged()
    {
        foreach (var (title, path) in _pages) Assert.True(_pagesBefore[title].AsSpan().SequenceEqual(File.ReadAllBytes(path)), $"“{title}” changed");
    }

    [Fact]
    public void PublishIsOneStepOfThePagesThenTheAnsweredRecordThenTheKeptRecord()
    {
        var history = new UndoHistory();
        AssistWorkspace workspace = Open(history);

        LinksChecklistSheet sheet = Sheet(workspace);
        PublishPlan planBefore = Open().PlanPublish(Course, 1, [Relative(_pages["Unit 2, Day 5"])]);
        LinksChecklistPublished published = workspace.PublishAndRemember(sheet);

        Assert.Equal([Key], WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        var (madeBy, paths, kinds) = NewestStep();
        Assert.Equal("sheet", madeBy);
        // Each page's front matter is edited line by line; the two records are written whole, last.
        Assert.DoesNotContain(UndoOp.Recompute, kinds);
        Assert.Equal([UndoOp.WriteFile, UndoOp.WriteFile], kinds.TakeLast(2).ToList());
        Assert.DoesNotContain(UndoOp.WriteFile, kinds.SkipLast(2));
        // The pages the class publishes and dates, in the plan's order (W7b2-8
        // review 1, L4): the order the class's own publish plan names them
        // (the class, then the pages it brings), asked of a second workspace
        // on the folder as it was; then the two records.
        var pagesWritten = new List<string>();
        foreach (var page in planBefore.Changing) pagesWritten.Add(page.RelativePath.Replace('\\', '/'));
        Assert.Equal(new[] { "Unit 2, Day 5", "Class Notes", "Worksheet" }.Select(t => Relative(_pages[t])).Order(StringComparer.Ordinal),
                     pagesWritten.Order(StringComparer.Ordinal));
        Assert.Equal(pagesWritten, paths.Take(3).ToList());
        Assert.Equal([AnsweredPath, KeptPath], paths.Skip(3).ToList());
        Assert.Equal(3, published.Written.Count);
        foreach (string title in new[] { "Unit 2, Day 5", "Class Notes", "Worksheet" })
            Assert.Equal(PageVisibility.Visible, PageFrontmatter.Visibility(File.ReadAllText(_pages[title]), 1));
        // The class it published, dated after the next class, kept at its date.
        Assert.Equal([new LaterClassesKept.Row("section1/All Classes/Unit 2, Day 5", "2026-10-20")], LaterClassesKept.Read(CourseDirectory, 1));
        var (offered, _) = LinksChecklist.ReadAnswered(CourseDirectory, 1);
        Assert.Equal(3, offered.Count);
        // Today's undo keeps the pages, never the records, as before.
        Assert.Single(history.Entries);
    }

    /// <summary>The front page is not repointed (ruling F1): no recompute is named, as the mac's step names none, and the page is as it was.</summary>
    [Fact]
    public void ThePressNamesNoRecomputeAndLeavesTheFrontPage()
    {
        byte[] front = File.ReadAllBytes(FrontPage);
        AssistWorkspace workspace = Open();

        workspace.PublishAndRemember(Sheet(workspace));

        var (_, paths, kinds) = NewestStep();
        Assert.DoesNotContain(UndoOp.Recompute, kinds);
        Assert.DoesNotContain(Relative(FrontPage), paths);
        Assert.Equal(front, File.ReadAllBytes(FrontPage));
    }

    [Fact]
    public void NotNowIsOneStepOfTheAnsweredRecord()
    {
        AssistWorkspace workspace = Open();

        Assert.True(workspace.NotNow(Sheet(workspace)));

        Assert.Equal([Key], WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        var (madeBy, paths, kinds) = NewestStep();
        Assert.Equal("sheet", madeBy);
        Assert.Equal([UndoOp.WriteFile], kinds);
        Assert.Equal([AnsweredPath], paths);
        AssertNoPageChanged();
        var (_, leftUnticked) = LinksChecklist.ReadAnswered(CourseDirectory, 1);
        Assert.Equal(["Concepts/Published Once"], leftUnticked.ToList());
    }

    /// <summary>The door refuses the press before anything changes: nothing is written, the records included, and it is said as "Nothing was changed: …".</summary>
    [Fact]
    public void APageThatCannotBeWrittenChangesNothingRecordsIncluded()
    {
        AssistWorkspace workspace = Open(seams: new UndoSeams { StagingWriteFailsAt = index => index == 0 });
        LinksChecklistSheet sheet = Sheet(workspace);

        var refusal = Assert.Throws<AssistRefusal>(() => workspace.PublishAndRemember(sheet));

        Assert.StartsWith("Nothing was changed: ", refusal.Message, StringComparison.Ordinal);
        AssertNoPageChanged();
        Assert.False(File.Exists(Answered));
        Assert.False(File.Exists(Kept));
        Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
    }

    /// <summary>
    /// The answered record cannot be written over (read-only) after the
    /// pages went in, and the first page cannot be put back: some of the
    /// press went in, and it says the mac's checklist part-way sentence,
    /// naming the kept file, never "Nothing was changed". The words are read
    /// from the mac's <c>LinksChecklistPublisher.sentence(forRefused:)</c>,
    /// never retyped.
    /// </summary>
    [Fact]
    public void APressLeftPartWaySaysTheChecklistsPartWaySentence()
    {
        string macSource = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "mac-app", "QuartzTeachers", "Models",
            "LinksChecklist", "LinksChecklistPublisher.swift"));
        string macWords = Regex.Match(macSource, @"publishStoppedPartWay\(what: ""([^""]+)""").Groups[1].Value;
        Assert.NotEqual("", macWords);
        Assert.Equal(macWords, AssistWorkspace.PagesThePressTicked);

        AssistWorkspace workspace = Open(seams: new UndoSeams { PutBackFailsAt = index => index == 0 });
        LinksChecklistSheet sheet = Sheet(workspace);
        Directory.CreateDirectory(Path.GetDirectoryName(Answered)!);
        File.WriteAllText(Answered, "{\"offered\": [], \"leftUnticked\": []}\n");
        File.SetAttributes(Answered, FileAttributes.ReadOnly);

        var refusal = Assert.Throws<AssistRefusal>(() => workspace.PublishAndRemember(sheet));

        Assert.StartsWith(AssistWording.PublishStoppedPartWay(macWords, ""), refusal.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("Nothing was", refusal.Message, StringComparison.Ordinal);
        Assert.Contains(UndoSwap.StagedMarker, refusal.Message, StringComparison.Ordinal);
    }

    /// <summary>
    /// Every before is read when the press is planned: a page another
    /// program changes between the plan and the make refuses the step, and
    /// that change is kept, the records unwritten.
    /// </summary>
    [Fact]
    public void EveryBeforeIsReadWhenThePressIsPlanned()
    {
        AssistWorkspace workspace = Open();
        LinksChecklistSheet sheet = Sheet(workspace);
        var step = new UndoActionStep(new UndoStepMaker("sheet", Key), Folder, Course, 1, undo: List());
        workspace.PlanThePress(sheet, step);
        string byHand = File.ReadAllText(_pages["Worksheet"]) + "\nWritten by hand meanwhile.\n";
        File.WriteAllText(_pages["Worksheet"], byHand);

        Assert.Throws<UndoStepRefusedException>(step.Make);

        Assert.Equal(byHand, File.ReadAllText(_pages["Worksheet"]));
        Assert.False(File.Exists(Answered));
        Assert.False(File.Exists(Kept));
    }

    /// <summary>The sheet's name for the Worksheet page, as a refusal names it.</summary>
    private static string WorksheetOnTheSheet(LinksChecklistSheet sheet)
    {
        foreach (LinksChecklistRow row in sheet.Rows)
            if (Path.GetFileName(row.Place) == "Worksheet") return sheet.RowTitles[LinksChecklist.Key(row.Place)];
        throw new InvalidOperationException("the case's offer has no Worksheet row");
    }

    /// <summary>
    /// W7b2-8 review 1, L1: a section page another program changes after the
    /// press was planned is refused by the door, and said as the mac says it
    /// (<c>linksChecklist.wording.pageChangedSince</c>, the page named as the
    /// sheet names it), never "Nothing was changed: …" with the door's words.
    /// </summary>
    [Fact]
    public void APageChangedSinceItWasCheckedIsNamedAsTheSheetNamesIt()
    {
        string worksheet = _pages["Worksheet"];
        string byHand = File.ReadAllText(worksheet) + "\nWritten by hand meanwhile.\n";
        AssistWorkspace workspace = Open(seams: new UndoSeams { BeforeTheBegin = () => File.WriteAllText(worksheet, byHand) });
        LinksChecklistSheet sheet = Sheet(workspace);

        var refusal = Assert.Throws<AssistRefusal>(() => workspace.PublishAndRemember(sheet));

        Assert.Equal(LinksChecklistWording.Fill(LinksChecklistWording.PageChangedSince,
            new Dictionary<string, string> { ["name"] = WorksheetOnTheSheet(sheet) }), refusal.Message);
        Assert.Equal(byHand, File.ReadAllText(worksheet));
        Assert.False(File.Exists(Answered));
        Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
    }

    /// <summary>
    /// W7b2-8 review 1, L1: a page the plan cannot read, and a file the door
    /// could not read just now that really cannot be read (held by another
    /// program), are the mac's unreadable-page sentence naming the course; a
    /// door refusal of a file that CAN be read is "Nothing was changed: …".
    /// </summary>
    [Fact]
    public void AnUnreadablePageIsSaidAsTheMacSaysIt()
    {
        AssistWorkspace workspace = Open();
        LinksChecklistSheet sheet = Sheet(workspace);
        string unreadable = $"“{Course}” could not be read, so nothing was changed.";
        string worksheet = Relative(_pages["Worksheet"]);
        var cannotTell = new UndoStepRefusedException(new UndoRefusal(UndoRefusalKind.CannotTellNow, worksheet), "could not be read just now");

        Assert.Equal(unreadable, workspace.RefusalForAPressThatStopped(new IOException("held"), sheet, planning: true).Message);
        Assert.StartsWith("Nothing was changed: ", workspace.RefusalForAPressThatStopped(cannotTell, sheet, planning: false).Message, StringComparison.Ordinal);
        using (new FileStream(_pages["Worksheet"], FileMode.Open, FileAccess.Read, FileShare.None))
            Assert.Equal(unreadable, workspace.RefusalForAPressThatStopped(cannotTell, sheet, planning: false).Message);
    }

    /// <summary>
    /// The press's code writes no page itself (W7b2-8's done list: no
    /// <c>Save</c> of the press), and the sheet tells a refused press rather
    /// than dropping it.
    /// </summary>
    [Fact]
    public void NothingInThePressWritesOutsideTheStepAndTheSheetTellsARefusal()
    {
        string press = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core", "Assist", "AssistWorkspace.LinksChecklist.cs"));
        string dialog = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "LinksChecklistDialog.cs"));

        Assert.DoesNotMatch(@"[^\w.]Save\(", press);
        Assert.DoesNotContain("LaterClassesKept.Keep(", press, StringComparison.Ordinal);
        Assert.Contains("catch (AssistRefusal refusal) { return refusal.ForTheTeacher; }", dialog, StringComparison.Ordinal);
    }
}

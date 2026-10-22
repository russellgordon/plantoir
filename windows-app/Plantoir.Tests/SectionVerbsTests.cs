using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Mcp;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The Section menu's runner for one window (#489, the mac's
/// <c>SectionVerbsTests</c>): the calls it builds in code, the one runner entry
/// they go through, Undo Last Change's place, the trail's "ran from a menu"
/// lines, and the claim the in-app assistant meets.
/// </summary>
[Collection(SharedActivityState.Name)]
public class SectionVerbsTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-section-verbs").FullName;
    private readonly string _trail;
    private readonly string _course;

    public SectionVerbsTests()
    {
        SectionMenuActivity.Reset();
        _trail = Path.Combine(_folder, "trail.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        _course = Path.Combine(_folder, "courses", "ICS3U");
        Directory.CreateDirectory(_course);
        File.WriteAllText(Path.Combine(_course, "course_config.json"), """
            { "course_code": "ICS3U", "course_name": "A course", "deploy_target": "netlify",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
        int day = 8;
        foreach (string title in new[] { "Unit 1, Day 1", "Unit 1, Day 2" })
        {
            string full = Path.Combine(_course, "section1", "All Classes", title + ".md");
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            File.WriteAllText(full, $"---\npublish: false\ncreated: 2026-09-{day++:00}T07:00:00.000-0400\n---\nBody.\n");
        }
    }

    public void Dispose()
    {
        SectionMenuActivity.Reset();
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private string Page(string title) => Path.Combine(_course, "section1", "All Classes", title + ".md");

    private SectionVerbs Verbs(out AssistWorkspace workspace, UndoHistory? history = null)
    {
        var server = new AssistWorkspace(_folder, new FakeLauncher(), undo: history ?? new UndoHistory()) { Surface = AssistSurface.Menu };
        workspace = server;
        var tools = new AssistScenarioTests.RealTools(server);
        return new SectionVerbs(_folder, _ => Task.FromResult<IToolServer?>(tools),
            (course, section, toolServer) => new AssistToolRunner(toolServer, course, section, AssistSurface.Menu));
    }

    private static JsonObject Arguments(JsonObject call) =>
        (JsonObject)JsonNode.Parse(call["function"]!["arguments"]!.GetValue<string>())!;

    [Fact]
    public void PagesAreNamedByTheirFolder_AsAJsonArray()
    {
        Assert.Equal("section1/All Classes/Unit 2, Day 3",
                     SectionVerbs.PageName(_course, Path.Combine(_course, "section1", "All Classes", "Unit 2, Day 3.md")));

        var call = SectionVerbs.PublishPages("ICS3U", 1, new[] { "section1/All Classes/Unit 2; Day 3" }, plan: true);
        Assert.Equal("plan_publish_pages", call["function"]!["name"]!.GetValue<string>());
        var pages = Assert.IsType<JsonArray>(Arguments(call)["pages"]);
        Assert.Equal("section1/All Classes/Unit 2; Day 3", Assert.Single(pages)!.GetValue<string>());
        Assert.StartsWith("menu-", call["id"]!.GetValue<string>());
    }

    [Fact]
    public void ReDatingNeverSendsAWebsite_AndMakingRoomSaysWhereAndHowMany()
    {
        var reDate = Arguments(SectionVerbs.ReDateClasses("ICS3U", 1, plan: false));
        Assert.False(reDate.ContainsKey("website"));
        Assert.Equal(new[] { "course", "section" }, reDate.Select(pair => pair.Key).ToArray());

        var room = Arguments(SectionVerbs.MakeRoomForClasses("ICS3U", 1, unit: 2, atDay: 4, howMany: 3, plan: true));
        Assert.Equal(2, room["unit"]!.GetValue<int>());
        Assert.Equal(4, room["atDay"]!.GetValue<int>());
        Assert.Equal(3, room["howMany"]!.GetValue<int>());
    }

    [Fact]
    public async Task APublish_IsCarriedOut_PlacedForUndo_AndUndoTakesItBack()
    {
        await using var verbs = Verbs(out _);
        Assert.False(verbs.LastChangeIsIn("ICS3U", 1));

        var plan = await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, new[] { "section1/All Classes/Unit 1, Day 1" }, plan: true),
                                       "Section ▸ Publish Pages…", "ICS3U", 1, "1 page ticked");
        Assert.True(plan.IsPlan);
        Assert.Contains("publish: false", File.ReadAllText(Page("Unit 1, Day 1")));

        await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, new[] { "section1/All Classes/Unit 1, Day 1" }, plan: false),
                            "Section ▸ Publish Pages…", "ICS3U", 1, "1 page ticked");
        Assert.Contains("publish: true", File.ReadAllText(Page("Unit 1, Day 1")));
        Assert.True(verbs.LastChangeIsIn("ICS3U", 1));
        Assert.False(verbs.LastChangeIsIn("ICS3U", 2));

        var undone = await verbs.Perform(SectionVerbs.UndoLastChange(), "Section ▸ Undo Last Change", "ICS3U", 1);
        Assert.StartsWith("Undone. Earlier, you ", undone.Summary);
        Assert.Contains("publish: false", File.ReadAllText(Page("Unit 1, Day 1")));
        Assert.False(verbs.LastChangeIsIn("ICS3U", 1));

        string trail = File.ReadAllText(_trail);
        Assert.Contains("ICS3U/1 · Section ▸ Publish Pages… — carried out, 1 page ticked", trail);
        Assert.Contains("ICS3U/1 · Section ▸ Undo Last Change — took the last change back", trail);
        // A plan writes no line: only a change, or a cancel, does.
        Assert.Equal(1, trail.Split('\n').Count(line => line.Contains("Section ▸ Publish Pages…")));
        Assert.DoesNotContain("Unit 1, Day 1", trail.Split('\n').Where(line => line.Contains("Section ▸")).Aggregate("", string.Concat));
    }

    [Fact]
    public async Task APublishOfWhatIsAlreadyPublished_ChangedNothing()
    {
        File.WriteAllText(Page("Unit 1, Day 2"), "---\npublish: true\ncreated: 2026-09-09T07:00:00.000-0400\n---\nBody.\n");
        await using var verbs = Verbs(out _);

        await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, new[] { "section1/All Classes/Unit 1, Day 2" }, plan: false),
                            "Section ▸ Publish Pages…", "ICS3U", 1, "1 page ticked");

        Assert.Contains("ICS3U/1 · Section ▸ Publish Pages… — changed nothing, 1 page ticked", File.ReadAllText(_trail));
        Assert.False(verbs.LastChangeIsIn("ICS3U", 1));
    }

    /// <summary>
    /// Make Room for Classes keeps no undo entry, on purpose — and it CHANGED
    /// the section, which the trail must say (2B's implementation review, M1:
    /// the undo list's depth said "changed nothing").
    /// </summary>
    [Fact]
    public async Task MakingRoom_IsCarriedOut_ThoughItKeepsNoUndoEntry()
    {
        TimetableMemory.Write(_folder, "ICS3U", 1,
            new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 9), new DateOnly(2026, 9, 10), new DateOnly(2026, 9, 11) },
            "typed in by hand", new DateOnly(2026, 9, 8));
        var history = new UndoHistory();
        await using var verbs = Verbs(out _, history);

        await verbs.Perform(SectionVerbs.MakeRoomForClasses("ICS3U", 1, unit: 1, atDay: 2, howMany: 1, plan: false),
                            "Section ▸ Make Room for Classes…", "ICS3U", 1, "room for 1");

        Assert.True(File.Exists(Page("Unit 1, Day 3")), "the class after the new one was renamed");
        Assert.Empty(history.Entries);
        Assert.Contains("ICS3U/1 · Section ▸ Make Room for Classes… — carried out, room for 1", File.ReadAllText(_trail));
    }

    /// <summary>
    /// From the twenty-first change on, the undo list stays at twenty, so its
    /// depth no longer grows — and the change was still made (M1).
    /// </summary>
    [Fact]
    public async Task TheTwentyFirstChange_IsCarriedOut_ThoughTheListStaysAtTwenty()
    {
        var history = new UndoHistory();
        for (int i = 0; i < 20; i++)
        {
            string earlier = Path.Combine(_folder, $"earlier{i}.txt");
            history.Begin($"an earlier change {i}");
            history.Touch(earlier, null);
            history.Wrote(earlier, "written");
            history.End();
        }
        Assert.Equal(20, history.Entries.Count);
        await using var verbs = Verbs(out _, history);

        foreach (string title in new[] { "Unit 1, Day 1", "Unit 1, Day 2" })
            await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, new[] { "section1/All Classes/" + title }, plan: false),
                                "Section ▸ Publish Pages…", "ICS3U", 1, "1 page ticked");

        Assert.Equal(20, history.Entries.Count);
        Assert.Contains("publish: true", File.ReadAllText(Page("Unit 1, Day 2")));
        string trail = File.ReadAllText(_trail);
        Assert.Equal(2, trail.Split('\n').Count(line => line.Contains("Section ▸ Publish Pages… — carried out, 1 page ticked")));
        Assert.DoesNotContain("changed nothing", trail);
    }

    [Fact]
    public void TheEnding_PrefersWhatTheServerSays_OverTheDepth()
    {
        var changed = AssistToolAnswer.Same("Done.") with { Changed = true };
        var unchanged = AssistToolAnswer.Same("Nothing to do.") with { Changed = false };
        Assert.Equal("carried out", SectionVerbs.Ending("publish_pages", changed, 20, 20, "ICS3U", 1));
        Assert.Equal("changed nothing", SectionVerbs.Ending("publish_pages", unchanged, 3, 4, "ICS3U", 1));
        // Not told: the depth, as before.
        Assert.Equal("changed nothing", SectionVerbs.Ending("publish_pages", AssistToolAnswer.Same("x"), 2, 2, "ICS3U", 1));

        // Undo (#550, the mac's #531): the entry came off — the depth went
        // down, at any depth — is a whole undo; a change noted with the depth
        // unmoved is a partial one; anything else changed nothing. Never the
        // sentence: the partial one contains "is put back" too.
        Assert.Equal("took the last change back", SectionVerbs.Ending("undo_last_change", changed, 20, 19, "ICS3U", 1));
        Assert.Equal("took part of the last change back", SectionVerbs.Ending("undo_last_change", changed, 20, 20, "ICS3U", 1));
        Assert.Equal("changed nothing", SectionVerbs.Ending("undo_last_change", unchanged, 20, 20, "ICS3U", 1));
        var soundsWhole = AssistToolAnswer.Same("Undone. “Unit 1, Day 1” is put back.") with { Changed = false };
        Assert.Equal("changed nothing", SectionVerbs.Ending("undo_last_change", soundsWhole, 3, 3, "ICS3U", 1));
    }

    // ---- Writes with no new undo entry (#550, the mac's #531) -------------------

    /// <summary>
    /// Held open for reading and shared for reading only, so the page can still
    /// be read — by the backup and the plan — and cannot be written. NEVER
    /// <c>FileShare.None</c>: that blocks the backup's zip and the plan's read
    /// too, so the call would fail before the write it is meant to exercise
    /// (measured by #550's plan review).
    /// </summary>
    private static FileStream HeldAgainstWriting(string path) =>
        new(path, FileMode.Open, FileAccess.Read, FileShare.Read);

    private static readonly string[] BothPages =
        { "section1/All Classes/Unit 1, Day 1", "section1/All Classes/Unit 1, Day 2" };

    /// <summary>
    /// An undo that put some files back and kept its entry, because another
    /// had been edited since: "took part of the last change back" — it read
    /// "took the last change back" while the ending searched the sentence for
    /// "is put back". Pressed again once the edited page is set back to what
    /// the change left, the undo puts that page back, finds the first ALREADY
    /// back, and takes the change off the list (#564, the mac's #555, option 2:
    /// until then the first page read as edited and the entry never came off).
    /// A third press has nothing left to undo.
    /// </summary>
    [Fact]
    public async Task APartialUndo_TookPartOfTheLastChangeBack()
    {
        var history = new UndoHistory();
        await using var verbs = Verbs(out _, history);
        await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, BothPages, plan: false),
                            "Section ▸ Publish Pages…", "ICS3U", 1, "2 pages ticked");
        string published = File.ReadAllText(Page("Unit 1, Day 2"));
        File.WriteAllText(Page("Unit 1, Day 2"), published + "Edited since.\n");

        await verbs.Perform(SectionVerbs.UndoLastChange(), "Section ▸ Undo Last Change", "ICS3U", 1);

        Assert.Contains("publish: false", File.ReadAllText(Page("Unit 1, Day 1")));
        Assert.Single(history.Entries);
        Assert.Contains("ICS3U/1 · Section ▸ Undo Last Change — took part of the last change back", File.ReadAllText(_trail));
        Assert.DoesNotContain("— took the last change back", File.ReadAllText(_trail));

        File.WriteAllText(Page("Unit 1, Day 2"), published);
        var second = await verbs.Perform(SectionVerbs.UndoLastChange(), "Section ▸ Undo Last Change", "ICS3U", 1);

        Assert.Contains("publish: false", File.ReadAllText(Page("Unit 1, Day 2")));
        Assert.Contains("publish: false", File.ReadAllText(Page("Unit 1, Day 1")));
        Assert.Empty(history.Entries);
        Assert.Contains("ICS3U/1 · Section ▸ Undo Last Change — took the last change back", File.ReadAllText(_trail));

        var third = await verbs.Perform(SectionVerbs.UndoLastChange(), "Section ▸ Undo Last Change", "ICS3U", 1);
        Assert.Equal(AssistWording.NothingToUndoFromTheMenu, third.Summary);
        Assert.Contains("ICS3U/1 · Section ▸ Undo Last Change — changed nothing", File.ReadAllText(_trail));
        Assert.NotEqual(third.Summary, second.Summary);
    }

    /// <summary>
    /// #564's second press row: the page is STILL edited, so the press writes
    /// nothing new — the existing couldNotUndo, the change kept, "changed nothing".
    /// </summary>
    [Fact]
    public async Task ARepeatUndoWhileThePageIsStillEdited_ChangesNothing()
    {
        var history = new UndoHistory();
        await using var verbs = Verbs(out _, history);
        await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, BothPages, plan: false),
                            "Section ▸ Publish Pages…", "ICS3U", 1, "2 pages ticked");
        File.AppendAllText(Page("Unit 1, Day 2"), "Edited since.\n");
        await verbs.Perform(SectionVerbs.UndoLastChange(), "Section ▸ Undo Last Change", "ICS3U", 1);

        var again = await verbs.Perform(SectionVerbs.UndoLastChange(), "Section ▸ Undo Last Change", "ICS3U", 1);

        Assert.Single(history.Entries);
        Assert.StartsWith(AssistWording.CouldNotUndoFromTheMenu(history.Entries[0].Description, 1), again.Summary);
        Assert.Contains("ICS3U/1 · Section ▸ Undo Last Change — changed nothing", File.ReadAllText(_trail));
    }

    /// <summary>
    /// A publish that wrote one page and stopped at the next: the recording is
    /// abandoned, so the undo list does not move — and a page WAS written, so
    /// the line says "carried out" (it said "changed nothing").
    /// </summary>
    [Fact]
    public async Task APublishThatStoppedPartWay_IsCarriedOut()
    {
        await using var verbs = Verbs(out _);
        AssistToolAnswer answer;
        using (HeldAgainstWriting(Page("Unit 1, Day 2")))
            answer = await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, BothPages, plan: false),
                                         "Section ▸ Publish Pages…", "ICS3U", 1, "2 pages ticked");

        Assert.StartsWith(AssistWording.PublishStoppedPartWay("the pages you named", ""), answer.Summary);
        Assert.Contains("publish: true", File.ReadAllText(Page("Unit 1, Day 1")));
        Assert.Contains("ICS3U/1 · Section ▸ Publish Pages… — carried out, 2 pages ticked", File.ReadAllText(_trail));
    }

    /// <summary>The same through a whole unit, which has its own write loop.</summary>
    [Fact]
    public async Task AWholeUnitThatStoppedPartWay_IsCarriedOut()
    {
        await using var verbs = Verbs(out _);
        AssistToolAnswer answer;
        using (HeldAgainstWriting(Page("Unit 1, Day 2")))
            answer = await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, new[] { "Unit 1" }, plan: false),
                                         "Section ▸ Publish Pages…", "ICS3U", 1, "1 unit");

        Assert.StartsWith(AssistWording.PublishStoppedPartWay("Unit 1", ""), answer.Summary);
        Assert.Contains("publish: true", File.ReadAllText(Page("Unit 1, Day 1")));
        Assert.Contains("ICS3U/1 · Section ▸ Publish Pages… — carried out, 1 unit", File.ReadAllText(_trail));
    }

    /// <summary>
    /// A publish whose FIRST write fails changed nothing, and says so in the
    /// mac's words rather than "Only part of … was changed" (#550, the
    /// director's ruling on review F8).
    /// </summary>
    [Fact]
    public async Task APublishWhoseFirstWriteFails_SaysNothingWasChanged()
    {
        await using var verbs = Verbs(out _);
        AssistToolAnswer answer;
        using (HeldAgainstWriting(Page("Unit 1, Day 1")))
            answer = await verbs.Perform(SectionVerbs.PublishPages("ICS3U", 1, new[] { BothPages[0] }, plan: false),
                                         "Section ▸ Publish Pages…", "ICS3U", 1, "1 page ticked");

        Assert.StartsWith("Nothing was changed: ", answer.Summary);
        Assert.DoesNotContain("Only part of", answer.Summary);
        Assert.Contains("publish: false", File.ReadAllText(Page("Unit 1, Day 1")));
        Assert.Contains("ICS3U/1 · Section ▸ Publish Pages… — changed nothing, 1 page ticked", File.ReadAllText(_trail));
    }

    /// <summary>
    /// Re-date Classes… that stopped part way says so and names the pages
    /// already re-dated — never "Nothing was changed", and never the
    /// "couldn’t be read" a read failure gets — and the line says "carried out".
    /// </summary>
    [Fact]
    public async Task ReDateThatStoppedPartWay_SaysPartWayAndListsThePages()
    {
        RememberOctoberDates();
        await using var verbs = Verbs(out _);
        AssistToolAnswer answer;
        using (HeldAgainstWriting(Page("Unit 1, Day 2")))
            answer = await verbs.Perform(SectionVerbs.ReDateClasses("ICS3U", 1, plan: false),
                                         "Section ▸ Re-date Classes…", "ICS3U", 1);

        string said = answer.Summary + "\n" + answer.Detail;
        Assert.StartsWith(AssistWording.PublishStoppedPartWay("the section's class dates", ""), answer.Summary);
        Assert.Contains("The pages already re-dated:\n  courses/ICS3U/section1/All Classes/Unit 1, Day 1.md", said);
        // The failure's own message names the page it stopped at; the LIST of
        // pages already re-dated must not.
        string listed = answer.Summary[answer.Summary.IndexOf("The pages already re-dated:", StringComparison.Ordinal)..];
        Assert.DoesNotContain("Unit 1, Day 2.md", listed);
        Assert.DoesNotContain("couldn’t be read", said);
        Assert.DoesNotContain("Nothing was changed", said);
        Assert.Contains("2026-10-01", File.ReadAllText(Page("Unit 1, Day 1")));
        Assert.Contains("ICS3U/1 · Section ▸ Re-date Classes… — carried out", File.ReadAllText(_trail));
    }

    /// <summary>
    /// A re-date whose FIRST write fails changed no page: the mac's "Nothing
    /// was changed" (the IOException used to escape the tool as a protocol
    /// error), and "changed nothing".
    /// </summary>
    [Fact]
    public async Task ReDateWhoseFirstWriteFails_SaysNothingWasChanged()
    {
        RememberOctoberDates();
        await using var verbs = Verbs(out _);
        AssistToolAnswer answer;
        using (HeldAgainstWriting(Page("Unit 1, Day 1")))
            answer = await verbs.Perform(SectionVerbs.ReDateClasses("ICS3U", 1, plan: false),
                                         "Section ▸ Re-date Classes…", "ICS3U", 1);

        Assert.StartsWith("Nothing was changed: ", answer.Summary);
        Assert.DoesNotContain("couldn’t be read", answer.Summary);
        Assert.Contains("ICS3U/1 · Section ▸ Re-date Classes… — changed nothing", File.ReadAllText(_trail));
    }

    /// <summary>Two meetings in October, so both class pages change date, Day 1 first.</summary>
    private void RememberOctoberDates() =>
        TimetableMemory.Write(_folder, "ICS3U", 1,
            new[] { new DateOnly(2026, 10, 1), new DateOnly(2026, 10, 2) },
            "typed in by hand", new DateOnly(2026, 9, 8));

    /// <summary>
    /// The menu's server meets the same request filter every client does
    /// (2B's implementation review, L8): a course kept for reference is still
    /// refused a write on the Menu surface, and the outside-change hold —
    /// for an assistant in ANOTHER program, while a build runs — never holds
    /// the menu at the door, though it holds an outside assistant in the
    /// same moment.
    /// </summary>
    [Fact]
    public void TheMenusServer_IsRefusedAReferenceCoursesWrite_ButNotHeldAtTheDoor()
    {
        string kept = Path.Combine(_folder, "courses", "ICS3U-2025");
        Directory.CreateDirectory(Path.Combine(kept, "section1"));
        File.WriteAllText(Path.Combine(kept, "course_config.json"),
            """{"course_code":"ICS3U","kept_for_reference":true,"reference_school_year":2025,"section_numbers":[1],"num_sections":1,"deploy_target":"netlify"}""");
        var menu = new AssistWorkspace(_folder, new FakeLauncher()) { Surface = AssistSurface.Menu };
        var outside = new AssistWorkspace(_folder, new FakeLauncher()) { Surface = AssistSurface.Outside };
        static IReadOnlyDictionary<string, JsonElement> Arguments(string json) =>
            JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json)!;

        Assert.Equal(ReferenceCourse.StaysAsItIs("ICS3U"),
            ReferenceWriteGate.Refusal("publish_pages", Arguments("""{"course":"ICS3U-2025","section":1,"pages":["x"]}"""), menu));

        // Another program building ICS3U: an outside assistant is held, the menu is not.
        using var other = Process.Start(new ProcessStartInfo("cmd.exe", "/c pause")
        {
            CreateNoWindow = true, UseShellExecute = false, RedirectStandardInput = true,
        })!;
        try
        {
            string leases = Path.Combine(_folder, "courses", ".internal", "activity");
            Directory.CreateDirectory(leases);
            File.WriteAllText(Path.Combine(leases, $"ICS3U.build.{other.Id}.lease"),
                $"{other.Id}\n{other.ProcessName}\n2026-08-13T00:00:00Z\n");
            var change = Arguments("""{"course":"ICS3U","section":1,"pages":["section1/All Classes/Unit 1, Day 1"]}""");
            Assert.NotNull(OutsideChangeGate.Refusal("publish_pages", change, outside));
            Assert.Null(OutsideChangeGate.Refusal("publish_pages", change, menu));
        }
        finally { try { other.Kill(entireProcessTree: true); } catch { } }
    }

    [Fact]
    public void ACancelAtThePlanSaysSo()
    {
        SectionVerbs.NoteCancelled("Section ▸ Hide Pages…", "ICS3U", 1, "2 pages ticked");
        Assert.Contains("ICS3U/1 · Section ▸ Hide Pages… — cancelled at the plan, 2 pages ticked", File.ReadAllText(_trail));
    }

    [Fact]
    public async Task TheMenuHoldsTheSectionWhileItChanges_AndTheAssistantsWriteIsRefused()
    {
        using (SectionMenuActivity.Begin(_folder, "ICS3U", 1))
        {
            Assert.True(SectionMenuActivity.IsChanging(_folder, "ics3u", 1));
            Assert.True(SectionMenuActivity.IsChanging(_folder, "ICS3U", null));
            Assert.False(SectionMenuActivity.IsChanging(_folder, "ICS3U", 2));

            var window = new AssistWorkspace(_folder, new FakeLauncher(), undo: new UndoHistory()) { Surface = AssistSurface.LocalWindow };
            var runner = new AssistToolRunner(new AssistScenarioTests.RealTools(window), "ICS3U", 1, AssistSurface.LocalWindow)
            {
                SectionIsChangingFromTheMenu = () => SectionMenuActivity.IsChanging(_folder, "ICS3U", 1),
            };
            var (answer, handed) = await runner.Run(SectionVerbs.PublishPages("ICS3U", 1, new[] { "Unit 1, Day 1" }, plan: false), default);
            Assert.True(handed);
            Assert.Equal(AssistWording.SectionIsChangingFromTheMenu("ICS3U", "1"), answer.Summary);
            Assert.Contains("publish: false", File.ReadAllText(Page("Unit 1, Day 1")));

            // A read is never held back.
            var (read, _) = await runner.Run(SectionVerbs.PublishPages("ICS3U", 1, new[] { "Unit 1, Day 1" }, plan: true), default);
            Assert.True(read.IsPlan);
        }
        Assert.False(SectionMenuActivity.IsChanging(_folder, "ICS3U", 1));
    }

    [Fact]
    public async Task RebuildPreviewFromTheMenu_RebuildsAServingPreview_OrSaysACopyIsBeingSaved()
    {
        int rebuilt = 0, shown = 0;
        var tools = new AssistScenarioTests.RealTools(new AssistWorkspace(_folder, new FakeLauncher()) { Surface = AssistSurface.Menu });
        var runner = new AssistToolRunner(tools, "ICS3U", 1, AssistSurface.Menu)
        {
            ShowPreviewInApp = () => shown++,
            RebuildPreviewInApp = () => rebuilt++,
            CourseIsBeingCopied = () => false,
        };
        var (answer, _) = await runner.Run(SectionVerbs.RebuildPreview("ICS3U", 1), default);
        Assert.Equal(AssistWording.PreviewIsRebuilding("ICS3U", "1"), answer.Summary);
        Assert.Equal((1, 0), (rebuilt, shown));

        var copying = new AssistToolRunner(tools, "ICS3U", 1, AssistSurface.Menu)
        {
            RebuildPreviewInApp = () => rebuilt++,
            CourseIsBeingCopied = () => true,
        };
        var (refused, _) = await copying.Run(SectionVerbs.RebuildPreview("ICS3U", 1), default);
        Assert.Equal(AssistWording.CourseIsBeingCopiedFromTheMenu("ICS3U"), refused.Summary);
        Assert.Equal(1, rebuilt);
    }

    /// <summary>
    /// #564 item 6: an undo that WRITES nothing — every page already back —
    /// still puts back the preview it stopped, as any whole undo does, and
    /// answers "undid" with the change off the list.
    /// </summary>
    [Fact]
    public async Task AnUndoThatFindsEveryPageAlreadyBack_StillRestartsThePreviewItStopped()
    {
        var history = new UndoHistory();
        var tools = new AssistScenarioTests.RealTools(new AssistWorkspace(_folder, new FakeLauncher(), undo: history) { Surface = AssistSurface.Menu });
        int stopped = 0, shown = 0;
        var runner = new AssistToolRunner(tools, "ICS3U", 1, AssistSurface.Menu)
        {
            PreviewIsShowing = () => true,
            StopPreviewInApp = () => stopped++,
            ShowPreviewInApp = () => shown++,
        };
        string before = File.ReadAllText(Page("Unit 1, Day 1"));
        await runner.Run(SectionVerbs.PublishPages("ICS3U", 1, new[] { "Unit 1, Day 1" }, plan: false), default);
        Assert.Single(history.Entries);
        File.WriteAllText(Page("Unit 1, Day 1"), before);   // the teacher put it back by hand
        (stopped, shown) = (0, 0);
        string description = history.Entries[0].Description;

        var (answer, _) = await runner.Run(SectionVerbs.UndoLastChange(), default);

        Assert.Equal(AssistWording.UndidFromTheMenu(description), answer.Summary);
        Assert.Empty(history.Entries);
        Assert.Equal(before, File.ReadAllText(Page("Unit 1, Day 1")));
        Assert.Equal((1, 1), (stopped, shown));
    }

    private sealed class NoModel : IChatModel
    {
        public Task<ModelReply?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation) =>
            Task.FromResult<ModelReply?>(null);
    }

    /// <summary>
    /// "rebuild the preview", answered in code without the model, stops the
    /// preview — so it meets the Section menu's claim as the runner's
    /// rebuild_preview does (2B's implementation review, L3). Showing a
    /// preview ("preview") changes nothing and is never held.
    /// </summary>
    [Fact]
    public async Task ThePlainRebuild_MeetsTheMenusClaim_ButShowingAPreviewDoesNot()
    {
        int rebuilt = 0, shown = 0;
        var agent = new AssistAgent(new NoModel(), new AssistScenarioTests.RealTools(new AssistWorkspace(_folder, new FakeLauncher())),
                                    new JsonArray(), "ICS3U", 1)
        {
            ShowPreviewInApp = () => shown++,
            RebuildPreviewInApp = () => rebuilt++,
            SectionIsChangingFromTheMenu = () => true,
        };

        var refused = await agent.Say("rebuild the preview", CancellationToken.None);
        Assert.Contains(refused, line => line.Text == AssistWording.SectionIsChangingFromTheMenu("ICS3U", "1"));
        Assert.Equal(0, rebuilt);

        await agent.Say("preview", CancellationToken.None);
        Assert.Equal((0, 1), (rebuilt, shown));
    }

    [Fact]
    public void TheAssistantsWindowReportsWork_AndTheMenuCanSeeIt()
    {
        AssistActivity.ReportWork(_folder, "ICS3U", 1, working: true);
        try
        {
            Assert.True(AssistActivity.IsWorking(_folder, "ics3u", 1));
            Assert.False(AssistActivity.IsWorking(_folder, "ICS3U", 2));
        }
        finally { AssistActivity.ReportWork(_folder, "ICS3U", 1, working: false); }
        Assert.False(AssistActivity.IsWorking(_folder, "ICS3U", 1));
    }
}

using System.Text.Json.Nodes;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Classes ▸ Roll Over to a New Year… (#954, the mac's #897 piece B): the
/// website rule and Cloudflare's name rule from the contract
/// (<c>shared-rules.json</c> → <c>subjectMenus.rollOverSheet</c>), the marker
/// list the rule shares with the release, and the menu's server: its plan
/// lines, its copy saved first on BOTH paths, its refusal when that copy
/// cannot be made, and its finished lines. The mac's
/// <c>RollOverFromTheMenuTests</c> and <c>RollOverFromTheMenuSafetyTests</c>.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class RollOverFromTheMenuTests : IDisposable
{
    private static JsonNode Sheet => SubjectMenusContractTests.Rule["rollOverSheet"]!;

    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-rollover-menu").FullName;
    private readonly string _course;
    private readonly FakeScheduler _scheduler;

    public RollOverFromTheMenuTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        _course = Path.Combine(_folder, "courses", "ICS3U");
        Configure("netlify");
        // Two classes on one day and a remembered timetable: the first rollover
        // re-dates the second class, and the next finds the dates right.
        Class("Unit 1, Day 1", "2026-09-08");
        Class("Unit 1, Day 2", "2026-09-08");
        TimetableMemory.Write(_folder, "ICS3U", 1,
            new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10) },
            "typed in by hand", new DateOnly(2026, 9, 8));
        _scheduler = new FakeScheduler(_folder);
    }

    public void Dispose()
    {
        _scheduler.Dispose();
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private static string Camel(string name) => char.ToLowerInvariant(name[0]) + name[1..];

    // ---- The rules, from the contract ----------------------------------------------

    /// <summary>The four websites are the contract's names, in its order.</summary>
    [Fact]
    public void TheWebsitesAreTheContracts()
    {
        Assert.Equal(Sheet["websites"]!.AsObject().Select(pair => pair.Key),
                     Enum.GetValues<RollOverFromTheMenu.Website>().Select(website => Camel(website.ToString())));
    }

    /// <summary>
    /// Every <c>rollOverSheet.cases</c> case: the rule over its three facts,
    /// and what the call sends for the answer chosen (null while the question
    /// is up and unanswered). MUST FAIL with the reuse fact read after the
    /// marker, or a pinned section with no web host sent "new" unasked.
    /// </summary>
    [Fact]
    public void TheWebsiteRuleIsTheContracts()
    {
        var cases = Sheet["cases"]!.AsArray();
        Assert.Equal(8, cases.Count);
        foreach (var c in cases)
        {
            var facts = c!["facts"]!;
            var website = RollOverFromTheMenu.WebsiteFor(
                facts["sectionIsPinned"]!.GetValue<bool>(),
                facts["hasAHostedDestination"]!.GetValue<bool>(),
                facts["aNewWebsiteWouldReuseItsAddress"]!.GetValue<bool>());
            string why = c["why"]!.ToString();
            Assert.True(c["website"]!.ToString() == Camel(website.ToString()), why);
            string? answer = c["answer"]?.GetValue<string>();
            Assert.True(c["websiteSent"]?.GetValue<string>() == RollOverFromTheMenu.WebsiteSent(website, answer), why);
        }
    }

    /// <summary>Every <c>cloudflareAddressReuse</c> case. MUST FAIL with section 1's stem matching section 10's.</summary>
    [Fact]
    public void TheCloudflareNameRuleIsTheContracts()
    {
        var cases = Sheet["cloudflareAddressReuse"]!["cases"]!.AsArray();
        Assert.Equal(7, cases.Count);
        foreach (var c in cases)
        {
            var kept = c!["keptNames"]!.AsArray().Select(name => name!.ToString()).ToList();
            bool reuse = RollOverFromTheMenu.ANewWebsiteWouldReuseItsAddress(
                kept, c["courseCode"]!.ToString(), c["section"]!.GetValue<int>(), c["year"]!.GetValue<int>());
            Assert.True(c["wouldReuse"]!.GetValue<bool>() == reuse, c["why"]!.ToString());
        }
    }

    // ---- The marker list the rule shares with the release ----------------------------

    /// <summary>
    /// <c>sectionIsPinned</c> walks the markers the release walks: the legacy
    /// <c>.netlify_site.json</c> alone still asks the question, and it is the
    /// one file a rollover onto a new website then moves. MUST FAIL with the
    /// rule reading only <c>.netlify_sites</c> and <c>.cloudflare_sites</c>
    /// (the section is then "not deployed yet" and sent "new" unasked).
    /// </summary>
    [Fact]
    public void TheLegacyMarkerAloneAsksTheQuestion_AndIsWhatTheReleaseMoves()
    {
        string legacy = Path.Combine(_course, ".merged_output", "section1", ".netlify_site.json");
        Directory.CreateDirectory(Path.GetDirectoryName(legacy)!);
        File.WriteAllText(legacy, """{"site_id": "abc"}""");
        var workspace = Menu();
        var course = workspace.Course("ICS3U");

        Assert.Equal(RollOverFromTheMenu.Website.Asked, RollOverFromTheMenu.WebsiteFor(_folder, course, 1, 2026));
        Assert.Contains(legacy, AssistWorkspace.MarkersTheReleaseWalks(_folder, course, 1));

        var released = workspace.ReleaseSite(course, 1);
        Assert.Single(released.KeptFiles);
        Assert.False(File.Exists(legacy));
        Assert.Equal(RollOverFromTheMenu.Website.NotDeployedYet, RollOverFromTheMenu.WebsiteFor(_folder, course, 1, 2026));
    }

    // ---- The menu's server ---------------------------------------------------------------

    /// <summary>
    /// The plan from the menu says what happens to the website on "same" and
    /// what is set aside (<c>rollOverSheet.sheet.planLines</c>); the window's
    /// card is the plain re-date's, unchanged. MUST FAIL with the menu's
    /// lines left out, or added to the window's card.
    /// </summary>
    [Fact]
    public async Task ThePlanFromTheMenuSaysTheWebsiteAndTheRecord_TheWindowsIsUnchanged()
    {
        Marker(".netlify_sites", "ics3u-s1-2025-gordon");

        string menu = Body(await Plan(Menu(), "same"));
        Assert.Contains(AssistWording.MenuRollOverPlanKeepsTheWebsite, menu);
        Assert.EndsWith(AssistWording.MenuRollOverPlanSetsTheRecordAside, menu);

        string window = Body(await Plan(Window(), "same"));
        Assert.DoesNotContain(AssistWording.MenuRollOverPlanKeepsTheWebsite, window);
        Assert.DoesNotContain(AssistWording.MenuRollOverPlanSetsTheRecordAside, window);
    }

    /// <summary>A course deploying only to a folder is told the folder's line in the plan, on "new" too.</summary>
    [Fact]
    public async Task AFolderCourseIsToldTheFoldersLine_InThePlanAndWhenFinished()
    {
        Configure("local_folder");

        string plan = Body(await Plan(Menu(), "same"));
        Assert.Contains(AssistWording.MenuRollOverDeploysToAFolder, plan);
        Assert.DoesNotContain(AssistWording.MenuRollOverPlanKeepsTheWebsite, plan);

        string said = Summary(await Apply(Menu(), "same"));
        Assert.Contains(AssistWording.RolloverDeploysToAFolderFromTheMenu, said);
        Assert.DoesNotContain(AssistWording.RolloverKeptTheSameWebsite, said);
    }

    /// <summary>
    /// "new" from the menu: the marker is set aside and the finished line ends
    /// on the sentence true on Cloudflare, never "Plantoir will ask what to
    /// call" it. MUST FAIL with the window's finished line.
    /// </summary>
    [Fact]
    public async Task ANewWebsiteFromTheMenuPromisesNoQuestionAboutItsName()
    {
        string marker = Marker(".netlify_sites", "ics3u-s1-2025-gordon");

        string said = Summary(await Apply(Menu(), "new"));

        Assert.False(File.Exists(marker));
        Assert.Contains(AssistWording.RolloverIsOnANewWebsite, said);
        Assert.Contains(AssistWording.RolloverANewWebsiteIsMadeAtTheNextDeploy, said);
        Assert.DoesNotContain("will ask", said);
    }

    /// <summary>
    /// A Cloudflare section whose record holds this calendar year's name: a
    /// "new" that reaches the server anyway (a deploy between opening the
    /// dialog and pressing Roll Over) keeps the website and says why; the
    /// marker stays. MUST FAIL with the reuse rule skipped at the write.
    /// </summary>
    [Fact]
    public async Task ANewWebsiteThatWouldReuseItsAddressIsNotStarted()
    {
        Configure("cloudflare_pages");
        string marker = Marker(".cloudflare_sites", $"ics3u-s1-{DateTime.Now.Year}-gordon");

        string said = Summary(await Apply(Menu(), "new"));

        Assert.True(File.Exists(marker));
        Assert.Contains(AssistWording.MenuRollOverANewWebsiteWouldReuseItsAddress, said);
    }

    /// <summary>
    /// Dates already right: the menu still saves a fresh copy first (the
    /// window does not, here) and settles the website. MUST FAIL with the
    /// window's path, which saves no copy when no date changes.
    /// </summary>
    [Fact]
    public async Task WithTheDatesAlreadyRightTheMenuSavesACopyFirst()
    {
        string marker = Marker(".netlify_sites", "ics3u-s1-2025-gordon");
        await new PlantoirTools(Window()).ReDateClasses("ICS3U", 1);   // the dates, now right
        int before = MenuCopies().Length;

        string said = Summary(await Apply(Menu(), "new"));

        Assert.Equal(before + 1, MenuCopies().Length);
        Assert.StartsWith(AssistWording.EveryPageIsAlreadyOnItsDay("ICS3U", "1"), said);
        Assert.Contains(AssistWording.RolloverANewWebsiteIsMadeAtTheNextDeploy, said);
        Assert.False(File.Exists(marker));
    }

    /// <summary>
    /// No copy, no rollover, on both paths: refused with
    /// <c>wording.startOfYearNeedsABackup</c> before anything is written, so
    /// the class pages and the marker are as they were. MUST FAIL with the
    /// dates-already-right path going on without its copy.
    /// </summary>
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task WithNoCopyNothingIsRolledOver(bool datesAlreadyRight)
    {
        string marker = Marker(".netlify_sites", "ics3u-s1-2025-gordon");
        if (datesAlreadyRight) await new PlantoirTools(Window()).ReDateClasses("ICS3U", 1);
        string page = File.ReadAllText(ClassPath("Unit 1, Day 2"));
        // A file where the backups folder goes: no copy can be made. (The
        // window's re-date above saved its own copy there first.)
        string backups = Path.Combine(_folder, "courses", "_backups");
        if (Directory.Exists(backups)) Directory.Delete(backups, recursive: true);
        File.WriteAllText(backups, "not a folder");

        string said = Summary(await Apply(Menu(), "new"));

        Assert.Equal(AssistWording.StartOfYearNeedsABackup("ICS3U"), said);
        Assert.True(File.Exists(marker));
        Assert.Equal(page, File.ReadAllText(ClassPath("Unit 1, Day 2")));
    }

    // ---- Helpers ---------------------------------------------------------------------------

    private AssistWorkspace Menu() =>
        new(_folder, new FakeLauncher(), undo: new UndoHistory()) { Surface = AssistSurface.Menu };

    private AssistWorkspace Window() => new(_folder, new FakeLauncher(), undo: new UndoHistory());

    private static Task<CallToolResult> Plan(AssistWorkspace workspace, string website) =>
        new PlantoirTools(workspace).PlanReDateClasses("ICS3U", 1, timetable: "", block: "", cancellation: default,
                                                       pages: null, meetings: null, firstDay: "", startYear: 0,
                                                       website: website, rollover: "yes");

    private static Task<CallToolResult> Apply(AssistWorkspace workspace, string website) =>
        new PlantoirTools(workspace).ReDateClasses("ICS3U", 1, timetable: "", block: "", cancellation: default,
                                                   pages: null, meetings: null, firstDay: "", startYear: 0,
                                                   website: website, rollover: "yes");

    private static string Summary(CallToolResult result) =>
        result.Meta?[AssistToolAnswer.TeacherSummaryKey]?.ToString() ?? Body(result);

    private static string Body(CallToolResult result) =>
        result.Content.OfType<TextContentBlock>().FirstOrDefault()?.Text ?? "";

    private string[] MenuCopies()
    {
        string backups = Path.Combine(_folder, "courses", "_backups", "ICS3U");
        return Directory.Exists(backups) ? Directory.GetFiles(backups, "*_menu-section1.zip") : Array.Empty<string>();
    }

    private void Configure(string target)
    {
        Directory.CreateDirectory(_course);
        string folder = target == "local_folder" ? Path.Combine(_folder, "out").Replace("\\", "\\\\") : "";
        File.WriteAllText(Path.Combine(_course, "course_config.json"), $$"""
            { "course_code": "ICS3U", "course_name": "A course", "deploy_target": "{{target}}",
              "deploy_folder_path": "{{folder}}",
              "num_sections": 1, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1] }
            """);
    }

    private string Marker(string folder, string name)
    {
        string directory = Path.Combine(_course, folder);
        Directory.CreateDirectory(directory);
        string path = Path.Combine(directory, "section1.json");
        File.WriteAllText(path, $$"""{"name": "{{name}}"}""");
        return path;
    }

    private string ClassPath(string title) => Path.Combine(_course, "section1", "All Classes", title + ".md");

    private void Class(string title, string date)
    {
        string full = ClassPath(title);
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, $"---\ndraft: false\ncreated: {date}T07:00:00.000-0400\n---\nBody.\n");
    }
}

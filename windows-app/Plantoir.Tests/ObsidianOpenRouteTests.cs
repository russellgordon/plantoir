using System.Text;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// Open in Obsidian with the add-ons for diagrams and graphs (#581; the mac's
/// route tests in <c>ObsidianFigureAddOnsTests</c>, #495), driven through a
/// fake <see cref="IObsidianWorld"/> — no window, no Obsidian — one test per
/// step of <c>obsidianAddOnsForFigures.sequence</c> and per rule of what
/// counts as open.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class ObsidianOpenRouteTests : IDisposable
{
    private readonly string _root;
    private readonly string _trail;

    public ObsidianOpenRouteTests()
    {
        _root = Directory.CreateTempSubdirectory("plantoir-581-route-").FullName;
        _trail = Path.Combine(_root, "activity.txt");
        ActivityTrail.SetCustomLogPathForTesting(_trail);
        ObsidianFigureAddOnsThisRun.Forget();
    }

    public void Dispose()
    {
        ObsidianFigureAddOnsThisRun.Forget();
        ActivityTrail.SetCustomLogPathForTesting(TestTrailRedirect.ScratchTrailPath);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    /// <summary>The world, as data: what it says, and what was asked of it, in order.</summary>
    private sealed class FakeWorld : IObsidianWorld
    {
        public bool Installed = true;
        public bool Running;
        public bool StaysRunningAfterQuit;
        public string? Registry;
        public ObsidianFigureAddOnsAnswer Stored = ObsidianFigureAddOnsAnswer.NotAsked;
        public ObsidianFigureAddOnsTrail.Answered OfferAnswer = ObsidianFigureAddOnsTrail.Answered.AddThem;
        public bool ReopenAnswer = true;
        public Func<Task>? DuringScan;
        public bool ScanThrows;
        public Action? WhileOfferIsUp;
        /// <summary>When set, the offer waits for this before answering (a question left up).</summary>
        public Task? OfferAnsweredWhen;
        public readonly List<string?> PagesAskedAbout = new();
        public readonly List<string> Asked = new();
        public string? Carried;
        public string? Defaults;

        public bool IsInstalled() => Installed;
        public bool IsRunning() => Running;
        public string? RegistryText() => Registry;
        public string TargetFor(string folder, string vault) => folder;
        public Task OpenAsync(string folder, string vault, string? page = null)
        {
            Asked.Add(page is null ? "open " + Path.GetFileName(folder) : "open page " + Path.GetFileName(page));
            return Task.CompletedTask;
        }
        public Task QuitAndWaitAsync() { Asked.Add("quit"); if (!StaysRunningAfterQuit) Running = false; return Task.CompletedTask; }
        public Task ReopenAsync(IReadOnlyList<string> vaultPaths) { Asked.Add("reopen " + string.Join(",", vaultPaths.Select(Path.GetFileName))); return Task.CompletedTask; }
        public async Task<(List<ObsidianFigureAddOn> Needed, List<ObsidianFigureAddOn> WouldAdd)> ScanAsync(string coursePath)
        {
            Asked.Add("scan");
            if (DuringScan is not null) await DuringScan();
            if (ScanThrows) throw new IOException("the course could not be read");
            return await Task.Run(() => ObsidianFigureAddOns.Scan(coursePath)) is var scanned
                ? (Remap(scanned.Needed), Remap(scanned.WouldAdd)) : default;
        }
        public string? CarriedFolder => Carried;
        public string? DefaultsFolder => Defaults;
        public ObsidianFigureAddOnsAnswer Answer { get => Stored; set { Asked.Add("answer " + value); Stored = value; } }
        public async Task<ObsidianFigureAddOnsTrail.Answered> AskOfferAsync(ObsidianAddOnsRequest request)
        {
            Asked.Add(request.CourseIsOpen ? "offer while open" : "offer");
            PagesAskedAbout.Add(request.Page);
            WhileOfferIsUp?.Invoke();
            if (OfferAnsweredWhen is not null) await OfferAnsweredWhen;
            return OfferAnswer;
        }
        public Task<bool> AskReopenAsync(ObsidianAddOnsRequest request)
        {
            Asked.Add("ask reopen");
            PagesAskedAbout.Add(request.Page);
            return Task.FromResult(ReopenAnswer);
        }

        /// <summary>The scan finds the pinned add-ons; the pass writes the test's small stand-ins with the same ids.</summary>
        public List<ObsidianFigureAddOn> FakeAddOns = new();
        private List<ObsidianFigureAddOn> Remap(List<ObsidianFigureAddOn> pinned) => pinned.Select(p => FakeAddOns.Single(f => f.Id == p.Id)).ToList();
    }

    private (FakeWorld World, Course Course, ObsidianOpenRoute Route) Make(bool reference = false, bool figures = true)
    {
        string course = Path.Combine(_root, "courses", "MPM2D");
        Directory.CreateDirectory(Path.Combine(course, ".obsidian"));
        File.WriteAllText(Path.Combine(course, ".obsidian", "app.json"), "{}");
        File.WriteAllText(Path.Combine(course, "course_config.json"), reference ? "{\"kept_for_reference\": true}" : "{}");
        if (figures) File.WriteAllText(Path.Combine(course, "Graphs.md"), "```functionplot\ny = x^2\n```\n", new UTF8Encoding(false));
        var (addOns, carried) = ObsidianFigureAddOnsTests.FakeAddOns(Path.Combine(_root, "carried-for"), mismatched: false);
        var world = new FakeWorld { Carried = carried, Defaults = ObsidianFigureAddOnsTests.Defaults, FakeAddOns = addOns };
        var model = new Course("MPM2D", course, CourseConfiguration.Load(Path.Combine(course, "course_config.json")));
        return (world, model, new ObsidianOpenRoute(world));
    }

    private bool Added(Course course) => File.Exists(Path.Combine(course.DirectoryPath, ".obsidian", "plugins", "obsidian-functionplot", "manifest.json"));

    private string TrailText => File.Exists(_trail) ? File.ReadAllText(_trail) : "";

    private string OpenRegistry(Course course) => ObsidianFigureAddOnsTests.Registry((course.DirectoryPath, true), (Path.Combine(_root, "courses", "ICS3U"), true));

    // Step 1: a reference course is never scanned.
    [Fact]
    public async Task AReferenceCourseIsNeverScanned()
    {
        var (world, course, route) = Make(reference: true);
        world.Stored = ObsidianFigureAddOnsAnswer.Yes;
        await route.OpenAsync(course, course.DirectoryPath);
        await route.AfterAPreviewAsync(course);
        Assert.Equal(new[] { "open MPM2D" }, world.Asked);
        Assert.False(Added(course));
    }

    // Step 2: no Obsidian, the answer no, or Not Now this run: open, no scan.
    [Fact]
    public async Task WithoutObsidianOrWithNoItOpensWithoutScanning()
    {
        var (world, course, route) = Make();
        world.Installed = false;
        await route.OpenAsync(course, course.DirectoryPath);
        world.Installed = true;
        world.Stored = ObsidianFigureAddOnsAnswer.No;
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "open MPM2D", "open MPM2D" }, world.Asked);
    }

    // Steps 3 and 4: a second click while it scans does nothing; nothing to add just opens.
    [Fact]
    public async Task ASecondClickWhileScanningDoesNothing()
    {
        var (world, course, route) = Make(figures: false);
        var release = new TaskCompletionSource();
        world.DuringScan = () => release.Task;
        var first = route.OpenAsync(course, course.DirectoryPath);
        Assert.False(await route.OpenAsync(course, course.DirectoryPath));
        release.SetResult();
        Assert.True(await first);
        Assert.Equal(new[] { "scan", "open MPM2D" }, world.Asked);
    }

    // Step 5: a larger vault is never offered, and says why once.
    [Fact]
    public async Task ALargerVaultIsNeverOfferedAndSaysWhyOnce()
    {
        var (world, course, route) = Make();
        world.Registry = ObsidianFigureAddOnsTests.Registry((Path.Combine(_root, "courses"), false));
        await route.OpenAsync(course, course.DirectoryPath);
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "scan", "open MPM2D", "scan", "open MPM2D" }, world.Asked);
        Assert.Equal(1, TrailText.Split('\n').Count(l => l.Contains(ObsidianFigureAddOnsTrail.NotTheVault("MPM2D"))));
        Assert.False(Added(course));
    }

    // Step 6: asked BEFORE Obsidian opens; Add Them adds, then opens.
    [Fact]
    public async Task OpenInObsidianAsksBeforeOpening()
    {
        var (world, course, route) = Make();
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "scan", "offer", "answer Yes", "open MPM2D" }, world.Asked);
        Assert.True(Added(course));
        Assert.Contains(ObsidianFigureAddOnsTrail.Offered("MPM2D", ObsidianFigureAddOnsTrail.Answered.AddThem), TrailText);
        Assert.Contains("MPM2D · Obsidian add-ons for diagrams and graphs (at Open in Obsidian): Functionplot 1.2.1 added", TrailText);
    }

    // Step 6: Not Now asks no more this run; Not Now with don't ask again stores no.
    [Fact]
    public async Task NotNowAndDontAskAgain()
    {
        var (world, course, route) = Make();
        world.OfferAnswer = ObsidianFigureAddOnsTrail.Answered.NotNow;
        await route.OpenAsync(course, course.DirectoryPath);
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "scan", "offer", "open MPM2D", "open MPM2D" }, world.Asked);
        Assert.Equal(ObsidianFigureAddOnsAnswer.NotAsked, world.Stored);

        ObsidianFigureAddOnsThisRun.Forget();
        world.Asked.Clear();
        world.OfferAnswer = ObsidianFigureAddOnsTrail.Answered.NotNowDontAskAgain;
        await route.OpenAsync(course, course.DirectoryPath);
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "scan", "offer", "answer No", "open MPM2D", "open MPM2D" }, world.Asked);
        Assert.False(Added(course));
    }

    // Step 6, open in Obsidian: one dialog; Add Them closes Obsidian first and writes only once it is gone.
    [Fact]
    public async Task TheOfferWhileOpenClosesObsidianBeforeWriting()
    {
        var (world, course, route) = Make();
        world.Running = true;
        world.Registry = OpenRegistry(course);
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "scan", "offer while open", "answer Yes", "quit", "reopen ICS3U", "open MPM2D" }, world.Asked);
        Assert.True(Added(course));
        Assert.Contains("(after reopening Obsidian): Functionplot 1.2.1 added", TrailText);
    }

    // Add Them checks again when answered: the course may have been opened while the question was up.
    [Fact]
    public async Task AddThemChecksAgainWhenAnswered()
    {
        var (world, course, route) = Make();
        world.WhileOfferIsUp = () => { world.Running = true; world.Registry = OpenRegistry(course); };
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "scan", "offer", "answer Yes", "quit", "reopen ICS3U", "open MPM2D" }, world.Asked);
    }

    // Step 7: with yes and the course closed, add them, then open.
    [Fact]
    public async Task WithYesItAddsThenOpens()
    {
        var (world, course, route) = Make();
        world.Stored = ObsidianFigureAddOnsAnswer.Yes;
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "scan", "open MPM2D" }, world.Asked);
        Assert.True(Added(course));
    }

    // Step 8: course open — ask to reopen, never write under it; Reopen reopens every vault that was open, this course last.
    [Fact]
    public async Task WithTheCourseOpenItAsksToReopenAndNeverWritesUnderIt()
    {
        var (world, course, route) = Make();
        world.Stored = ObsidianFigureAddOnsAnswer.Yes;
        world.Running = true;
        world.Registry = OpenRegistry(course);
        await route.AfterAPreviewAsync(course);
        Assert.False(Added(course));
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "scan", "scan", "ask reopen", "quit", "reopen ICS3U", "open MPM2D" }, world.Asked);
        Assert.True(Added(course));
        Assert.Contains(ObsidianFigureAddOnsTrail.Reopened("MPM2D"), TrailText);
    }

    // A hidden or minimised Obsidian has no window on screen and still holds the list: the registry decides, not the windows.
    [Fact]
    public async Task AHiddenObsidianStillCountsAsOpen()
    {
        var (world, course, route) = Make();
        world.Stored = ObsidianFigureAddOnsAnswer.Yes;
        world.Running = true;   // no window is asked about at all
        world.Registry = ObsidianFigureAddOnsTests.Registry((course.DirectoryPath, true));
        world.ReopenAnswer = false;
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "scan", "ask reopen", "open MPM2D" }, world.Asked);
        Assert.False(Added(course));
    }

    [Fact]
    public async Task AnUnreadableRegistryWhileRunningCountsAsOpen()
    {
        var (world, course, route) = Make();
        world.Stored = ObsidianFigureAddOnsAnswer.Yes;
        world.Running = true;
        world.Registry = "{\"vaults\":{\"a\":";   // mid-write
        await route.AfterAPreviewAsync(course);
        Assert.False(Added(course));
    }

    // Later: nothing written, not asked again for this course this run.
    [Fact]
    public async Task LaterWritesNothingAndIsNotAskedAgain()
    {
        var (world, course, route) = Make();
        world.Stored = ObsidianFigureAddOnsAnswer.Yes;
        world.Running = true;
        world.Registry = OpenRegistry(course);
        world.ReopenAnswer = false;
        await route.OpenAsync(course, course.DirectoryPath);
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "scan", "ask reopen", "open MPM2D", "scan", "open MPM2D" }, world.Asked);
        Assert.False(Added(course));
        Assert.Contains(ObsidianFigureAddOnsTrail.ReopenDeclined("MPM2D"), TrailText);
    }

    // An Obsidian that does not close is never written under.
    [Fact]
    public async Task AnObsidianThatDoesNotCloseIsNeverWrittenUnder()
    {
        var (world, course, route) = Make();
        world.Stored = ObsidianFigureAddOnsAnswer.Yes;
        world.Running = true;
        world.StaysRunningAfterQuit = true;
        world.Registry = OpenRegistry(course);
        await route.OpenAsync(course, course.DirectoryPath);
        Assert.Equal(new[] { "scan", "ask reopen", "quit", "open MPM2D" }, world.Asked);
        Assert.False(Added(course));
        Assert.Contains(ObsidianFigureAddOnsTrail.DidNotClose("MPM2D"), TrailText);
    }

    // The second trigger: a finished preview adds them only after the yes, and only while the course is closed.
    [Fact]
    public async Task APreviewAddsThemOnlyAfterTheYesAndWhileTheCourseIsClosed()
    {
        var (world, course, route) = Make();
        await route.AfterAPreviewAsync(course);
        Assert.False(Added(course));
        Assert.Empty(world.Asked);
        world.Stored = ObsidianFigureAddOnsAnswer.Yes;
        await route.AfterAPreviewAsync(course);
        Assert.True(Added(course));
        Assert.Contains("(after a preview): Functionplot 1.2.1 added", TrailText);
        Assert.DoesNotContain("offer", string.Join(" ", world.Asked));
    }

    // ---- #681 / #690: a SECTION's press carries the page and reports early ----

    /// <summary>A page answer for the course's section 1, on disk.</summary>
    private static PreviewedPageSource.Page APage(Course course, string name = "Unit 1, Day 3")
    {
        string folder = Path.Combine(course.DirectoryPath, "section1", "All Classes");
        Directory.CreateDirectory(folder);
        string file = Path.Combine(folder, name + ".md");
        File.WriteAllText(file, "# " + name + "\n");
        return new PreviewedPageSource.Page(file, "section1/All Classes/" + name, Hidden: false);
    }

    private int PressLines => TrailText.Split('\n').Count(line => line.Contains("in Obsidian, ") && line.Contains("MPM2D/1"));

    [Fact]
    public async Task ASectionPressOpensThePageThroughThePageDoor()
    {
        var (world, course, route) = Make(figures: false);
        var page = APage(course);
        var (reported, finished) = route.Press(course, Path.Combine(course.DirectoryPath, "section1"), page, 1);
        Assert.True(await finished);
        Assert.Equal(new OpenInObsidianPress.Opened(page), await reported);
        Assert.Equal(new[] { "scan", "open page Unit 1, Day 3.md" }, world.Asked);
    }

    [Fact]
    public async Task AFallbackOpensTheSectionAsBefore()
    {
        var (world, course, route) = Make(figures: false);
        var fell = new PreviewedPageSource.FellBack(PreviewedPageSource.Fallback.NoPageShowing);
        var (reported, finished) = route.Press(course, Path.Combine(course.DirectoryPath, "section1"), fell, 1);
        await finished;
        Assert.Equal(new OpenInObsidianPress.Opened(fell), await reported);
        Assert.Equal(new[] { "scan", "open section1" }, world.Asked);
        Assert.Contains(PreviewedPageSource.TrailWords(fell), TrailText);
    }

    [Fact]
    public async Task ThePageIsCarriedThroughTheOffer()
    {
        var (world, course, route) = Make();
        var page = APage(course);
        await route.Press(course, course.DirectoryPath, page, 1).Finished;
        Assert.Equal(new[] { "scan", "offer", "answer Yes", "open page Unit 1, Day 3.md" }, world.Asked);
        Assert.Equal(new string?[] { page.File }, world.PagesAskedAbout);
    }

    [Fact]
    public async Task ThePageIsCarriedThroughTheReopenQuestion()
    {
        var (world2, course2, route2) = Make();
        var page = APage(course2);
        world2.Stored = ObsidianFigureAddOnsAnswer.Yes;
        world2.Running = true;
        world2.Registry = OpenRegistry(course2);
        world2.ReopenAnswer = false;
        await route2.Press(course2, course2.DirectoryPath, page, 1).Finished;
        Assert.Equal(new[] { "scan", "ask reopen", "open page Unit 1, Day 3.md" }, world2.Asked);
        Assert.Equal(new string?[] { page.File }, world2.PagesAskedAbout);
    }

    [Fact]
    public async Task APressWhoseQuestionIsUpReportsWaitingAndASecondPressIsToldTheSame()
    {
        var (world, course, route) = Make();
        var page = APage(course);
        var answer = new TaskCompletionSource();
        world.OfferAnsweredWhen = answer.Task;
        Task<bool>? finished = null;
        try
        {
            (var reported, finished) = route.Press(course, course.DirectoryPath, page, 1);
            Assert.IsType<OpenInObsidianPress.WaitingForAnAnswer>(await reported.WaitAsync(TimeSpan.FromSeconds(10)));
            Assert.False(finished.IsCompleted);

            var (second, secondFinished) = route.Press(course, course.DirectoryPath, page, 1);
            Assert.IsType<OpenInObsidianPress.WaitingForAnAnswer>(await second);
            Assert.False(await secondFinished);
            Assert.Equal(1, PressLines);
        }
        finally
        {
            // Releases the static BeingOpened and Asking through a real answer.
            answer.TrySetResult();
            if (finished is not null) await finished;
        }
        Assert.Empty(ObsidianFigureAddOnsThisRun.Asking);
        Assert.Empty(ObsidianFigureAddOnsThisRun.BeingOpened);
    }

    [Fact]
    public async Task ASecondPressDuringTheScanIsAlreadyOpeningAndWritesNoLine()
    {
        var (world, course, route) = Make(figures: false);
        var page = APage(course);
        var release = new TaskCompletionSource();
        world.DuringScan = () => release.Task;
        var (_, first) = route.Press(course, course.DirectoryPath, page, 1);
        var (second, secondFinished) = route.Press(course, course.DirectoryPath, page, 1);
        Assert.IsType<OpenInObsidianPress.AlreadyOpening>(await second);
        Assert.False(await secondFinished);
        release.SetResult();
        Assert.True(await first);
        Assert.Equal(1, PressLines);
    }

    [Fact]
    public async Task OnePressOneTrailLine()
    {
        var (world, course, route) = Make();
        var page = APage(course);
        await route.Press(course, course.DirectoryPath, page, 1).Finished;
        Assert.Equal(1, PressLines);
        Assert.Contains("MPM2D/1 · " + PreviewedPageSource.TrailWords(page), TrailText);

        // Without a scan (no Obsidian) too: still one line per press.
        world.Installed = false;
        await route.Press(course, course.DirectoryPath, page, 1).Finished;
        Assert.Equal(2, PressLines);
    }

    [Fact]
    public async Task ACoursePressWritesNoLine()
    {
        var (world, course, route) = Make();
        Assert.True(await route.OpenAsync(course, course.DirectoryPath));
        Assert.DoesNotContain("in Obsidian, the page the preview shows", TrailText);
        Assert.DoesNotContain("not a page of the preview", TrailText);
    }

    [Fact]
    public async Task TheReportAlwaysCompletesWhenTheScanFails()
    {
        var (world, course, route) = Make();
        world.ScanThrows = true;
        var (reported, finished) = route.Press(course, course.DirectoryPath, APage(course), 1);
        await Assert.ThrowsAsync<IOException>(() => finished);
        await Assert.ThrowsAsync<IOException>(() => reported.WaitAsync(TimeSpan.FromSeconds(10)));
        Assert.Empty(ObsidianFigureAddOnsThisRun.BeingOpened);
    }

    /// <summary>Every Open in Obsidian route in the app goes through the one function, which goes through this route.</summary>
    [Fact]
    public void EveryRouteIsStillTheOneFunction()
    {
        string views = Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views");
        string menus = File.ReadAllText(Path.Combine(views, "SidebarPane.Menus.cs"));
        Assert.Contains("ObsidianOpenRoute", menus);
        var direct = Directory.EnumerateFiles(views, "*.cs")
            .Where(f => File.ReadAllText(f).Contains("FolderActions.OpenInObsidian(")).Select(Path.GetFileName).OrderBy(f => f).ToList();
        // The world itself, the reference route (step 1), and How I Teach's
        // "open the page" (a page, not Open in Obsidian — as on the mac).
        Assert.Equal(new[] { "CourseSettingsView.xaml.cs", "ObsidianWorld.cs", "SidebarPane.Reference.cs" }, direct);
        string section = File.ReadAllText(Path.Combine(views, "SectionDetailView.xaml.cs"));
        Assert.Contains("AfterAPreviewAsync(", section);
    }
}

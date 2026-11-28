using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8b-19a3 (the mac's <c>AssistSiteWork</c> 161 and 278,
/// <c>AssistToolRunner.bringThePreviewUpToDate</c> and
/// <c>AssistSectionRestore</c>'s <c>folderRenameUnderWay</c>): while a Rename
/// folder holds a course, the window's own assistant refuses its site work and
/// its section restore before anything is asked, stopped or written, with
/// <c>undo.wording.renameFolderUnderWay</c> read by key; a reading tool still
/// answers, and nothing is refused once the rename ends.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class AssistantRefusesDuringARenameTests : IDisposable
{
    // MARK: - Stored properties

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-assistant-refuses-during-a-rename-");

    /// <summary>The tools whose work is the course's site, as the mac's <c>AssistSiteWork</c> refuses them.</summary>
    public static readonly TheoryData<string> SiteWorkTools = new() { "rebuild_preview", "deploy_section" };

    // MARK: - Computed properties

    private string Folder => Path.Combine(_root, "wf");
    private string CoursesDirectory => Path.Combine(Folder, "courses");

    private static string WindowsApp => Path.Combine(ContractLoader.RepositoryRoot, "windows-app");

    private static string Sentence(string course) =>
        ContractLoader.LoadJson("shared-rules.json")["undo"]!["wording"]!["renameFolderUnderWay"]!.ToString().Replace("{course}", course);

    // MARK: - Initializer

    public AssistantRefusesDuringARenameTests()
    {
        CourseActivity.Reset();
        Directory.CreateDirectory(Path.Combine(CoursesDirectory, "ICS3U"));
    }

    // MARK: - Functions

    public void Dispose()
    {
        CourseActivity.Reset();
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static JsonObject Call(string name) => new()
    {
        ["id"] = "call-1",
        ["function"] = new JsonObject
        {
            ["name"] = name,
            ["arguments"] = new JsonObject { ["course"] = "ICS3U", ["section"] = 1 }.ToJsonString(),
        },
    };

    /// <summary>A runner whose every in-app step is recorded, so "nothing was asked, stopped or started" can be seen.</summary>
    private AssistToolRunner Runner(CannedTools tools, List<string> happened) =>
        new(tools, "ICS3U", 1, AssistSurface.LocalWindow)
        {
            CourseNoun = ClassNoun.Class,
            WorkingFolder = Folder,
            RebuildPreviewInApp = () => { happened.Add("rebuild"); return Task.FromResult<string?>(null); },
            ShowPreviewInApp = () => happened.Add("show"),
            AskAboutClassesDatedLaterInApp = () => { happened.Add("ask"); return Task.FromResult<LaterClassesAtADeploy>(LaterClassesAnswer.CannotAsk); },
            PreviewIsShowing = () => true,
            StopPreviewInAppAsync = () => { happened.Add("stop"); return Task.CompletedTask; },
            StartDeployInAppAsync = () => { happened.Add("deploy"); return Task.FromResult<string?>("deployed"); },
        };

    [Theory]
    [MemberData(nameof(SiteWorkTools))]
    public async Task WhileARenameHoldsTheCourseTheWindowsAssistantRefusesSiteWorkBeforeAnythingIsAskedOrWritten(string tool)
    {
        using var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U")!;
        var tools = new CannedTools();
        var happened = new List<string>();

        var (answer, handed) = await Runner(tools, happened).Run(Call(tool), default);

        Assert.True(handed);
        Assert.Equal(Sentence("ICS3U"), answer.Summary);
        Assert.Empty(happened);
        Assert.Empty(tools.Calls);
    }

    [Fact]
    public async Task WhileARenameHoldsTheCourseAReadingToolStillAnswers()
    {
        using var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U")!;
        var tools = new CannedTools();
        var happened = new List<string>();

        var (answer, _) = await Runner(tools, happened).Run(Call("list_classes"), default);

        Assert.Equal("Done.", answer.Summary);
        Assert.Single(tools.Calls);
    }

    [Fact]
    public async Task ARenameOfAnotherCourseRefusesNothingHere()
    {
        using var claim = CourseActivity.BeginFolderRename(Folder, "MPM2D")!;
        var happened = new List<string>();

        var (answer, _) = await Runner(new CannedTools(), happened).Run(Call("rebuild_preview"), default);

        Assert.NotEqual(Sentence("ICS3U"), answer.Summary);
        Assert.Contains("rebuild", happened);
    }

    [Fact]
    public async Task OnceTheRenameEndsTheAssistantsRebuildGoesAhead()
    {
        var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U")!;
        claim.Dispose();
        var happened = new List<string>();

        var (answer, _) = await Runner(new CannedTools(), happened).Run(Call("rebuild_preview"), default);

        Assert.NotEqual(Sentence("ICS3U"), answer.Summary);
        Assert.Contains("rebuild", happened);
    }

    [Fact]
    public void WhileARenameHoldsTheCourseTheAssistantWindowsSectionRestoreIsRefusedWithTheSentence()
    {
        using var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U")!;
        string backup = Path.Combine(_root, "never-read.zip");

        var refused = Assert.Throws<AssistSectionRestore.Problem>(() =>
            AssistSectionRestore.Restore(backup, "ICS3U", 1, CoursesDirectory));

        Assert.Equal(Sentence("ICS3U"), refused.Message);
    }

    [Fact]
    public async Task WhileARenameHoldsTheCourseTheAssistantStillSchedulesADeployAsOnTheMac()
    {
        using var claim = CourseActivity.BeginFolderRename(Folder, "ICS3U")!;
        var tools = new CannedTools();
        var happened = new List<string>();

        var (answer, _) = await Runner(tools, happened).Run(Call("schedule_deploy"), default);

        Assert.NotEqual(Sentence("ICS3U"), answer.Summary);
        Assert.Single(tools.Calls);
    }

    /// <summary>
    /// Every place that makes a runner or an agent for the window's assistant
    /// tells it the working folder, so the refusal above is asked there too.
    /// </summary>
    [Theory]
    [InlineData("Plantoir.Core/Assist/AssistAgent.cs", "WorkingFolder = WorkingFolder,")]
    [InlineData("Plantoir/Views/AssistWindow.xaml.cs", "WorkingFolder = _folder,")]
    [InlineData("Plantoir/MainWindow.Verbs.cs", "WorkingFolder = folder,")]
    public void EveryRunnerOfTheWindowsAssistantIsToldItsWorkingFolder(string file, string wiring)
    {
        string source = File.ReadAllText(Path.Combine(WindowsApp, file));
        Assert.Contains(wiring, source);
    }
}

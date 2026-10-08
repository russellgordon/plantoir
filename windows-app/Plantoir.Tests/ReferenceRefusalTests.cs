using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// A course kept for reference is never deployed — every door Windows has
/// (#241; <c>shared-rules.json → referenceCourses.refusal.doors</c>, fifteen).
/// Every chokepoint here is met with an UNLOCKED marked course: the refusal is
/// gated on the marker alone (<c>doesNotDependOnTheLock</c>), and a test that
/// locked the course first could not tell the two apart. The launcher doors
/// (deploy.ps1, every row of markerAgreement) are
/// <see cref="ReferenceMarkerAgreementTests"/>.
/// </summary>
[Collection(SharedActivityState.Name)]
public class ReferenceRefusalTests : IDisposable
{
    private readonly string _folder;
    private readonly FakeScheduler _scheduler;

    public ReferenceRefusalTests()
    {
        _folder = Directory.CreateTempSubdirectory("plantoir-refusal").FullName;
        _scheduler = new FakeScheduler(_folder);
        File.WriteAllText(Path.Combine(_folder, Workspace.MarkerLauncher), "");
        Make("ICS3U", """{"course_code":"ICS3U","section_numbers":[1],"num_sections":1,"deploy_target":"local_folder","deploy_folder_path":"C:\\sites"}""");
        Make("ICS3U-2025", """{"course_code":"ICS3U","kept_for_reference":true,"reference_school_year":2025,"section_numbers":[1],"num_sections":1,"deploy_target":"netlify"}""");
    }

    public void Dispose()
    {
        _scheduler.Dispose();
        ReferenceFixtures.Remove(_folder);
    }

    private void Make(string folder, string config)
    {
        string course = Path.Combine(_folder, "courses", folder);
        Directory.CreateDirectory(Path.Combine(course, "section1"));
        File.WriteAllText(Path.Combine(course, "course_config.json"), config);
        File.WriteAllText(Path.Combine(course, "section1", "index.md"), "# Section 1\n");
        Directory.CreateDirectory(Path.Combine(course, ".netlify_sites"));
        File.WriteAllText(Path.Combine(course, ".netlify_sites", "section1.json"), "{}");
    }

    private Course Kept => Workspace.DiscoverCourses(_folder).Single(c => c.Code == "ICS3U-2025");

    private static string Refusal => ReferenceCourse.RefusalSentence("ICS3U");

    [Fact]
    public void TheCourseIsNotLockedSoNoRefusalBelowCanBeTheLocksDoing()
    {
        Assert.False(ReferenceLock.IsLocked(Path.Combine(Kept.DirectoryPath, "section1", "index.md")));
        Assert.True(ReferenceCourse.IsKeptForReference(Kept));
    }

    // ---- Door 1: the section window's Deploy, and the runner behind it -----

    [Fact]
    public void TheDeployButtonsFlowRefusesFirst()
    {
        // The window cannot be built in a unit test; its flow's FIRST check is
        // asserted in the source, before anything else is asked or stopped.
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "SectionDetailView.xaml.cs"));
        int start = source.IndexOf("private async Task<string?> DeployAsync()", StringComparison.Ordinal);
        int refusal = source.IndexOf("ReferenceCourse.KeptOnDisk(_course.DirectoryPath)", start, StringComparison.Ordinal);
        int firstOther = source.IndexOf("AnotherProgramStandsInTheWay", start, StringComparison.Ordinal);
        int stop = source.IndexOf("StopPreview", start, StringComparison.Ordinal);
        Assert.True(start > 0 && refusal > start && refusal < firstOther && refusal < stop,
            "SectionDetailView.DeployAsync must refuse a reference course before anything else");
        Assert.Equal("ICS3U", ReferenceCourse.KeptOnDisk(Kept.DirectoryPath));
    }

    [Fact]
    public async Task TheMultiDestinationRunnerRefusesBeforeTheFirstDestination()
    {
        var runner = new MultiDestinationDeployRunner();
        var refused = await Assert.ThrowsAsync<ReferenceCourse.Refused>(() => runner.RunAsync(Kept, 1,
            Kept.Configuration.AllDeployDestinations, "", _folder, needsBuild: true));
        Assert.Equal(Refusal, refused.Message);
        Assert.False(runner.IsRunning);
    }

    // ---- Doors 2-4: the local assistant's hand-back and the card's Go ------

    private sealed class NoModel : IChatModel
    {
        public Task<ModelReply?> Ask(JsonArray messages, JsonArray tools, CancellationToken cancellation) =>
            Task.FromResult<ModelReply?>(null);
    }

    private sealed class NoTools : IToolServer
    {
        public List<string> Calls { get; } = new();
        public Task<AssistToolAnswer> CallTool(string name, JsonObject arguments, Action<string>? progress = null,
            CancellationToken cancellation = default)
        {
            Calls.Add(name);
            return Task.FromResult(name.StartsWith("plan_", StringComparison.Ordinal)
                ? new AssistToolAnswer("Deploy it.", "Deploy it.", IsPlan: true)
                : AssistToolAnswer.Same("Done."));
        }
    }

    private (AssistAgent Agent, List<string> Acts, NoTools Tools) Rig(bool confirming)
    {
        var acts = new List<string>();
        var tools = new NoTools();
        var agent = new AssistAgent(new NoModel(), tools, new JsonArray(), "ICS3U", 1)
        {
            StopPreviewInApp = () => acts.Add("stop preview"),
            StartDeployInApp = () => acts.Add("deploy"),
            StartDeployInAppAsync = () => { acts.Add("deploy"); return Task.FromResult<string?>("Deployed."); },
            PreviewIsShowing = () => true,
            ConfirmationMode = () => confirming,
            CourseIsKeptForReference = () => true,
        };
        return (agent, acts, tools);
    }

    [Fact]
    public async Task TheLocalAssistantsDeployIsRefusedBeforeThePreviewIsStopped()
    {
        var (agent, acts, _) = Rig(confirming: false);
        var lines = await agent.Say("deploy now", CancellationToken.None);
        Assert.Empty(acts);   // no preview stopped, nothing started
        Assert.Contains(lines, line => line.Text == AssistWording.DeployRefusedForAReferenceCourse("ICS3U"));
    }

    [Fact]
    public async Task TheApprovalCardsGoIsRefusedToo()
    {
        // The card is not shown for such a course; and a card already up when
        // the course was marked (in another window) is refused at Go.
        bool kept = false;
        var acts = new List<string>();
        var agent = new AssistAgent(new NoModel(), new NoTools(), new JsonArray(), "ICS3U", 1)
        {
            StopPreviewInApp = () => acts.Add("stop preview"),
            StartDeployInAppAsync = () => { acts.Add("deploy"); return Task.FromResult<string?>("Deployed."); },
            PreviewIsShowing = () => true,
            ConfirmationMode = () => true,
            CourseIsKeptForReference = () => kept,
        };
        await agent.Say("deploy now", CancellationToken.None);
        Assert.True(agent.IsAwaitingApproval);
        kept = true;
        var lines = await agent.Approve(CancellationToken.None);
        Assert.Empty(acts);
        Assert.Contains(lines, line => line.Text == AssistWording.DeployRefusedForAReferenceCourse("ICS3U"));
    }

    // ---- Door 3: the headless deploy ---------------------------------------

    [Fact]
    public async Task TheHeadlessDeployRefusesFirst()
    {
        var launcher = new FakeLauncher();
        var workspace = new AssistWorkspace(_folder, launcher);
        var refused = await Assert.ThrowsAsync<AssistRefusal>(() => workspace.Deploy("ICS3U-2025", 1));
        Assert.Equal(AssistWording.DeployRefusedForAReferenceCourse("ICS3U"), refused.Message);
        Assert.Empty(launcher.Runs);
    }

    // ---- Doors 5 and 7: the MCP write gate ----------------------------------

    private static IReadOnlyDictionary<string, JsonElement> Arguments(string json) =>
        JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json)!;

    [Fact]
    public void TheWriteGateRefusesEveryWriteAndSaysWhichKind()
    {
        var workspace = new AssistWorkspace(_folder, new FakeLauncher());
        Assert.Equal(AssistWording.DeployRefusedForAReferenceCourse("ICS3U"),
            ReferenceWriteGate.Refusal("deploy_section", Arguments("""{"course":"ICS3U-2025","section":1}"""), workspace));
        Assert.Equal(AssistWording.DeployRefusedForAReferenceCourse("ICS3U"),
            ReferenceWriteGate.Refusal("schedule_deploy", Arguments("""{"course":"ics3u-2025","section":1,"when":"x"}"""), workspace));
        Assert.Equal(ReferenceCourse.StaysAsItIs("ICS3U"),
            ReferenceWriteGate.Refusal("publish_pages", Arguments("""{"course":"ICS3U-2025","section":1,"pages":"x"}"""), workspace));
        // The live course of the same code is untouched by any of it.
        Assert.Null(ReferenceWriteGate.Refusal("deploy_section", Arguments("""{"course":"ICS3U","section":1}"""), workspace));
        // Reading, previewing, backing up and CANCELLING are never refused.
        foreach (string allowed in new[] { "read_page", "list_pages", "rebuild_preview", "back_up_course", "cancel_scheduled_deploy" })
            Assert.Null(ReferenceWriteGate.Refusal(allowed, Arguments("""{"course":"ICS3U-2025","section":1}"""), workspace));
    }

    /// <summary>Ruling 4: a settings file that is there and cannot be read is REFUSED (fail safe), never let through.</summary>
    [Fact]
    public void TheGateRefusesWhenTheSettingsCannotBeRead()
    {
        var workspace = new AssistWorkspace(_folder, new FakeLauncher());
        string settings = Path.Combine(_folder, "courses", "ICS3U-2025", "course_config.json");
        var me = System.Security.Principal.WindowsIdentity.GetCurrent().User!;
        var deny = new System.Security.AccessControl.FileSystemAccessRule(me,
            System.Security.AccessControl.FileSystemRights.ReadData, System.Security.AccessControl.AccessControlType.Deny);
        var security = new FileInfo(settings).GetAccessControl();
        security.AddAccessRule(deny);
        new FileInfo(settings).SetAccessControl(security);
        try
        {
            Assert.Equal("Plantoir cannot tell whether ICS3U-2025 is kept for reference — its settings file could not be read.",
                ReferenceWriteGate.Refusal("publish_pages", Arguments("""{"course":"ICS3U-2025","section":1}"""), workspace));
            Assert.Null(ReferenceWriteGate.Refusal("read_page", Arguments("""{"course":"ICS3U-2025","section":1}"""), workspace));
        }
        finally
        {
            var undo = new FileInfo(settings).GetAccessControl();
            undo.RemoveAccessRuleSpecific(deny);
            new FileInfo(settings).SetAccessControl(undo);
        }
        Assert.Null(ReferenceWriteGate.Refusal("publish_pages", Arguments("""{"course":"NOSUCH","section":1}"""), workspace));
    }

    [Fact]
    public void TheGateIsChosenByEachToolsOwnReadOnlyFlag()
    {
        var served = ReferenceWriteGate.ServedTools();
        Assert.True(served.Count >= 37, $"only {served.Count} tools found");
        var notReadOnly = served.Where(t => !t.Value).Select(t => t.Key).ToHashSet();
        var expected = notReadOnly.Except(ReferenceWriteGate.StillAllowed).ToHashSet();
        Assert.Equal(expected.OrderBy(x => x), ReferenceWriteGate.Gated().OrderBy(x => x));
        Assert.Contains("deploy_section", expected);
        Assert.Contains("schedule_deploy", expected);

        // The exemptions are the contract's, not decided here again.
        var contract = ContractLoader.LoadJson("shared-rules.json")["referenceCourses"]!["refusal"]!["toolsStillAllowed"]!
            .AsArray().Select(t => t!["tool"]!.ToString()).OrderBy(x => x);
        Assert.Equal(contract, ReferenceWriteGate.StillAllowed.OrderBy(x => x));

        // A new write tool is gated by default (must-fail (c): a gate keyed
        // on a list of names would not know it).
        Assert.Contains("some_new_write", ReferenceWriteGate.Gated(typeof(ToolsWithOneMore)));
    }

    [Fact]
    public void UndoIsTheOnlyWriteWithoutACourseAndIsGatedByItsPendingChange()
    {
        var withoutCourse = typeof(PlantoirTools).GetMethods()
            .Select(m => (Method: m, Attribute: m.GetCustomAttributes(typeof(ModelContextProtocol.Server.McpServerToolAttribute), false)
                .Cast<ModelContextProtocol.Server.McpServerToolAttribute>().FirstOrDefault()))
            .Where(p => p.Attribute is { ReadOnly: false })
            .Where(p => !p.Method.GetParameters().Any(parameter => parameter.Name == "course"))
            .Select(p => p.Attribute!.Name).ToList();
        Assert.Equal(new[] { "undo_last_change" }, withoutCourse);

        var history = new UndoHistory();
        var workspace = new AssistWorkspace(_folder, new FakeLauncher(), undo: history);
        string page = Path.Combine(Kept.DirectoryPath, "section1", "index.md");
        using (var recording = UndoHistory.Record(history, "changed a page"))
        {
            history.Touch(page, File.ReadAllText(page));
            history.Wrote(page, "x");
            recording.Done();
        }
        Assert.Equal(ReferenceCourse.StaysAsItIs("ICS3U"), ReferenceWriteGate.Refusal("undo_last_change", null, workspace));
    }

    [Fact]
    public void TheServerAsksTheGateBeforeAnyToolRuns()
    {
        string program = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Mcp", "Program.cs"));
        Assert.Contains("AddCallToolFilter", program);
        Assert.Contains("ReferenceWriteGate.Refusal(", program);
    }

    /// <summary>A stand-in tool type with one write tool nobody listed.</summary>
    private sealed class ToolsWithOneMore
    {
        [ModelContextProtocol.Server.McpServerTool(Name = "some_new_write")]
        public string SomeNewWrite(string course) => course;

        [ModelContextProtocol.Server.McpServerTool(Name = "some_read", ReadOnly = true)]
        public string SomeRead(string course) => course;
    }

    // ---- Doors 6, 8 and 10: scheduling, from every route -------------------

    [Fact]
    public void TheScheduleSheetRefusesWhateverTimeWasAsked()
    {
        Assert.Equal(Refusal, ScheduledDeploy.Problem(Kept, 1, DateTime.Now.AddDays(-1), DateTime.Now));
        Assert.Equal(Refusal, ScheduledDeploy.Problem(Kept, 1, DateTime.Now.AddDays(1), DateTime.Now));
    }

    [Fact]
    public void PlanningAScheduledDeployRefusesToo()
    {
        var workspace = new AssistWorkspace(_folder, new FakeLauncher());
        var refused = Assert.Throws<AssistRefusal>(() => workspace.PlanScheduledDeploy("ICS3U-2025", 1, DateTime.Now.AddDays(1)));
        Assert.Equal(Refusal, refused.Message);
        var tools = new PlantoirTools(workspace);
        Assert.Contains(Refusal, tools.PlanScheduledDeploy("ICS3U-2025", 1, "2099-01-01 06:30").Detail());
        Assert.Contains(Refusal, tools.ScheduleDeploy("ICS3U-2025", 1, "2099-01-01 06:30").Detail());
        Assert.Empty(_scheduler.Created);
    }

    [Fact]
    public void ARunThatFiresRefusesAndCancellingIsAlwaysAllowed()
    {
        Assert.Equal("keptForReference", ScheduledDeploy.RefusalOf(Kept, 1, "")!.Key);
        string task = _scheduler.AddNew(_folder, "ICS3U-2025", 1);
        var tools = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()));
        tools.CancelScheduledDeploy("ICS3U-2025", 1);
        Assert.Contains(task, _scheduler.Deleted);
    }

    // ---- What the teacher reads ---------------------------------------------

    [Fact]
    public void ABareCodeNamesTheLiveCourseAndOnlyReferenceCoursesAreNamedNotGuessed()
    {
        var workspace = new AssistWorkspace(_folder, new FakeLauncher());
        Assert.Equal("ICS3U", workspace.Course("ics3u").Code);
        Directory.Delete(Path.Combine(_folder, "courses", "ICS3U"), recursive: true);
        var refused = Assert.Throws<AssistRefusal>(() => workspace.Course("ICS3U"));
        Assert.Equal("No course you are teaching is called ICS3U. ICS3U-2025 is kept for reference and shows that code \u2014 name it as ICS3U-2025.", refused.Message);
    }

    [Fact]
    public void ListCoursesTellsAnOutsideSessionAndNotTheLocalWindow()
    {
        var outside = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher())).ListCourses();
        Assert.Contains("ICS3U-2025 \u2014", outside);
        Assert.Contains("kept for reference \u2014 never deployed", outside);
        Assert.Contains("school year: 2025\u201326", outside);
        var local = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()) { ServesTheLocalWindow = true }).ListCourses();
        Assert.DoesNotContain("ICS3U-2025", local);
        Assert.Contains("ICS3U \u2014", local);
    }

    /// <summary>
    /// #157 review F2: a folder whose only courses are kept for reference gets
    /// noCoursesYet in the local window \u2014 never an empty answer \u2014 while an
    /// outside session is still told about the reference course.
    /// </summary>
    [Fact]
    public void ListCoursesInTheLocalWindowWithOnlyReferenceCoursesSaysNoCoursesYet()
    {
        Directory.Delete(Path.Combine(_folder, "courses", "ICS3U"), recursive: true);
        var local = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher()) { ServesTheLocalWindow = true }).ListCourses();
        Assert.Equal(AssistWording.NoCoursesYet, local);
        var outside = new PlantoirTools(new AssistWorkspace(_folder, new FakeLauncher())).ListCourses();
        Assert.Contains("ICS3U-2025 \u2014", outside);
    }

    [Fact]
    public void RemovingASectionOfAReferenceCourseStaysAsItIs()
    {
        var refused = Assert.Throws<InvalidOperationException>(() =>
            CourseArchiver.ArchiveAndRemoveSection(Kept, 1, Path.Combine(_folder, "courses")));
        Assert.Equal(ReferenceCourse.StaysAsItIs("ICS3U"), refused.Message);
        Assert.True(Directory.Exists(Path.Combine(Kept.DirectoryPath, "section1")));
    }

    /// <summary>Must-fail (e): without the Unlock, the archive or the delete meets a locked tree.</summary>
    [Fact]
    public void ARemovedReferenceCourseLeavesNothingLocked()
    {
        ReferenceLock.Lock(Kept.DirectoryPath);
        CourseArchiver.ArchiveAndRemoveCourse(Kept, Path.Combine(_folder, "courses"));
        Assert.False(Directory.Exists(Path.Combine(_folder, "courses", "ICS3U-2025")));
    }

    /// <summary>
    /// <c>scheduledDeployCancellation</c>: "a course kept for reference is met
    /// when the working folder is read" — its alarm is turned off by the read.
    /// </summary>
    [Fact]
    public void ReadingTheFolderTurnsOffAReferenceCoursesDeploy()
    {
        string task = _scheduler.AddNew(_folder, "ICS3U-2025", 1);
        string live = _scheduler.AddNew(_folder, "ICS3U", 1);
        ReferenceCourseUpkeep.BringUpToDate(_folder, Workspace.DiscoverCourses(_folder));
        Assert.Contains(task, _scheduler.Deleted);
        Assert.DoesNotContain(live, _scheduler.Deleted);
        Assert.True(ReferenceLock.IsLocked(Path.Combine(Kept.DirectoryPath, "section1", "index.md")));
    }

    /// <summary>The refusal output, read back as the teacher's sentence (<c>app-rules.json → failureExplanations</c> cases 0-2).</summary>
    [Fact]
    public void TheLauncherRefusalIsExplainedInTheTeachersWords()
    {
        // deploy.ps1's own shape: no cross, a plain hyphen, the reason on the next line.
        Assert.Equal(Refusal, FailureExplainer.Explanation("\nICS3U " + ReferenceCourse.RefusalSentenceTemplate["{course} ".Length..] + "\n"));
        Assert.Equal("Plantoir cannot tell whether ICS3U-2025 is kept for reference — its settings file could not be read. Nothing was deployed.",
            FailureExplainer.Explanation("\nPlantoir cannot tell whether ICS3U-2025 is kept for reference -\r\n   its settings file could not be read. Nothing was deployed.\r\n"));
    }
}

using System.Linq;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #467 (mac #439): a deploy refuses while that section is still being
/// deployed. The launchers' half - who counts, the sentences, the trail lines -
/// is <c>windows-app/test_launcher_rules.ps1</c>'s, through
/// <see cref="LauncherRulesContractTests"/>; this is the APP's half: the
/// window lifts the launcher's line, and the assistants say
/// <c>wording.deployRefusedWhileALaterDeployWorks</c> or
/// <c>wording.deployRefusedWhileItsSectionDeploys</c> instead of "did not
/// finish" (or "could not be built"). Everything is read from
/// <c>contracts/shared-rules.json</c> → <c>deployWhileItsSectionDeploys</c>.
/// </summary>
public class DeployWhileItsSectionDeploysTests
{
    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["deployWhileItsSectionDeploys"]!;

    private static readonly CourseConfiguration.DeployDestination Netlify = new("netlify", "");
    private static readonly CourseConfiguration.DeployDestination Folder = new("local_folder", @"C:\Sites\ics4u");

    [Fact]
    public void TheWindowLiftsTheLaunchersLineAndTheAssistantSaysItsOwnSentence()
    {
        var cases = Rule["failureExplanationCases"]!.AsArray();
        Assert.Equal(4, cases.Count);
        foreach (var c in cases)
        {
            string output = c!["output"]!.ToString();
            string expected = c["expect"]!.ToString();
            Assert.Equal(expected, FailureExplainer.Explanation(output));

            var refusal = FailureExplainer.SectionDeployRefusalOf(output);
            Assert.NotNull(refusal);
            Assert.Equal(expected, refusal!.Sentence);

            string said = MultiDestinationDeployRunner.RefusalAnswer("ICS4U", "2", refusal).Message;
            string wordingKey = c["assistant"]!.ToString();
            Assert.Equal(wordingKey == "deployRefusedWhileALaterDeployWorks", refusal.ByALaterDeploy);
            Assert.Equal(
                ContractLoader.LoadJson("assist-wording.json")["wording"]![wordingKey]!.ToString()
                    .Replace("{course}", "ICS4U").Replace("{section}", "2"),
                said);
        }
    }

    /// <summary>
    /// plantoir-mcp reads the launcher without naming an encoding, so the
    /// cross may arrive as '?' or as mojibake; the markers are ASCII, so the
    /// refusal and which sentence it calls for are still found.
    /// </summary>
    [Theory]
    [InlineData("? ICS4U section 2 is still being deployed by a deploy that was set for later, so it cannot be built until that has finished.", true)]
    [InlineData("\u00e2\u009d\u0152 ICS4U section 2 is already being deployed, so it cannot be deployed again until that has finished.", false)]
    public void ACrossThatDidNotSurviveTheConsoleDoesNotHideTheRefusal(string line, bool byALaterDeploy)
    {
        var refusal = FailureExplainer.SectionDeployRefusalOf("(The launcher exited with code 1.)\n\nLast output:\n\n" + line + "\n   Nothing was changed.");
        Assert.NotNull(refusal);
        Assert.Equal(byALaterDeploy, refusal!.ByALaterDeploy);
        // Since #471 the server SAYS the lifted sentence, so whatever the
        // cross arrived as is taken off with it, up to the course code.
        Assert.StartsWith("ICS4U section 2 ", refusal.Sentence);
    }

    /// <summary>
    /// The two sentences, against the contract's own placeholders. Also
    /// asserted in <c>ContractTests.AssistWording_MatchesContract</c>; here as
    /// well so a failure elsewhere in that long test cannot hide these two.
    /// </summary>
    [Fact]
    public void TheTwoAssistantSentencesAreTheContracts()
    {
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!;
        Assert.Equal(wording["deployRefusedWhileALaterDeployWorks"]!.ToString(),
                     AssistWording.DeployRefusedWhileALaterDeployWorks("{course}", "{section}"));
        Assert.Equal(wording["deployRefusedWhileItsSectionDeploys"]!.ToString(),
                     AssistWording.DeployRefusedWhileItsSectionDeploys("{course}", "{section}"));
    }

    /// <summary>
    /// scheduledPublishStopped.kinds.earlierDeployStillWorking: Windows never
    /// writes it, but a record of it is read and shown with the contract's
    /// sentence, earns the badge, and files under the stand-downs' event.
    /// </summary>
    [Fact]
    public void TheMacsStandDownIsReadAndShownWithTheContractsSentence()
    {
        var kind = ScheduledPublishOutcome.Kind.EarlierDeployStillWorking;
        string expected = ContractLoader.LoadJson("shared-rules.json")["scheduledPublishStopped"]!["sentences"]!
            ["earlierDeployStillWorking"]!.ToString().Replace("{course}", "ICS3U").Replace("{section}", "2");
        Assert.Equal(expected, ScheduledPublishOutcome.Sentence("ICS3U", 2,
            new ScheduledPublishOutcome.Result(kind, "", DateTime.Now, "ICS3U", 2)));
        Assert.Equal("earlierDeployStillWorking", ScheduledPublishOutcome.ContractKey(kind));
        Assert.True(ScheduledPublishOutcome.NeedsAttention(kind));
        Assert.Equal(ActivityTrail.Event.ScheduledDeployTurnedOff, ScheduledPublishOutcome.EventFor(kind));

        var read = ScheduledPublishOutcome.Parse(
            ScheduledPublishOutcome.Word(kind) + "\n\nICS3U\n2", DateTime.Now, "ICS3U", 2);
        Assert.Equal(kind, read?.Outcome);
    }

    [Fact]
    public void EveryLauncherSentenceCarriesAMarkerTheAppReads()
    {
        foreach (var pair in Rule["sentences"]!["launcher"]!.AsObject())
        {
            string first = pair.Value!.AsArray()[0]!.ToString();
            Assert.Contains(FailureExplainer.SectionDeployRefusalMarkers, marker => first.EndsWith(marker, StringComparison.Ordinal));
            Assert.Equal(pair.Key.StartsWith("later", StringComparison.Ordinal),
                         first.Contains(FailureExplainer.LaterDeployMarker, StringComparison.Ordinal));
        }
    }

    [Theory]
    [InlineData("❌ ICS4U section 2 is being deployed right now, so it cannot be previewed until that has finished.")]
    [InlineData("Error: the build failed.\nNothing was deployed.")]
    [InlineData("")]
    public void AnOrdinaryFailureIsNotThisRefusal(string output)
    {
        Assert.Null(FailureExplainer.SectionDeployRefusalOf(output));
    }

    // ---- The deploy runner's outcome -----------------------------------------

    private static MultiDestinationDeployRunner.Leg Leg(
        CourseConfiguration.DeployDestination destination, bool succeeded, bool buildFailed = false,
        FailureExplainer.SectionDeployRefusal? refused = null) =>
        new(destination, null) { IsFinished = true, Succeeded = succeeded, BuildFailed = buildFailed, RefusedWhileItsSectionDeploys = refused };

    private static readonly FailureExplainer.SectionDeployRefusal ByALater = new(true, "later");
    private static readonly FailureExplainer.SectionDeployRefusal ByAnother = new(false, "another");

    [Fact]
    public void TheOutcomeCarriesTheRefusalOnlyWhenEveryLegThatRanWasRefused()
    {
        var runner = new MultiDestinationDeployRunner();
        runner.Legs.Add(Leg(Netlify, false, refused: ByAnother));
        runner.Legs.Add(Leg(Folder, false, refused: ByAnother));
        Assert.Equal(ByAnother, runner.CurrentOutcome.Refusal);
        Assert.Equal(AssistWording.DeployRefusedWhileItsSectionDeploys("ICS4U", "2"),
            MultiDestinationDeployRunner.Result("ICS4U", "2", 2, runner.CurrentOutcome).Message);

        var oneWentOut = new MultiDestinationDeployRunner();
        oneWentOut.Legs.Add(Leg(Netlify, false, refused: ByAnother));
        oneWentOut.Legs.Add(Leg(Folder, true));
        Assert.Null(oneWentOut.CurrentOutcome.Refusal);

        var oneFailedOtherwise = new MultiDestinationDeployRunner();
        oneFailedOtherwise.Legs.Add(Leg(Netlify, false, refused: ByAnother));
        oneFailedOtherwise.Legs.Add(Leg(Folder, false));
        Assert.Null(oneFailedOtherwise.CurrentOutcome.Refusal);
        Assert.Equal(AssistWording.DeployToMultipleDestinationsDidNotFinish("ICS4U", "2"),
            MultiDestinationDeployRunner.Result("ICS4U", "2", 2, oneFailedOtherwise.CurrentOutcome).Message);
    }

    [Fact]
    public void ARefusedBuildIsSaidAsItselfAndABrokenOneAsCouldNotBeBuilt()
    {
        var refusedBuild = Leg(Netlify, false, buildFailed: true, refused: ByALater);
        Assert.Equal(AssistWording.DeployRefusedWhileALaterDeployWorks("ICS4U", "2"),
            MultiDestinationDeployRunner.AnswerWhenTheBuildDidNotFinish("ICS4U", "2", refusedBuild)!.Message);

        var brokenBuild = Leg(Netlify, false, buildFailed: true);
        Assert.Equal(AssistWording.CouldNotBuildBeforeDeploying("ICS4U", "2"),
            MultiDestinationDeployRunner.AnswerWhenTheBuildDidNotFinish("ICS4U", "2", brokenBuild)!.Message);

        Assert.Null(MultiDestinationDeployRunner.AnswerWhenTheBuildDidNotFinish("ICS4U", "2", Leg(Netlify, false)));
        Assert.Null(MultiDestinationDeployRunner.AnswerWhenTheBuildDidNotFinish("ICS4U", "2", null));
    }
}

/// <summary>
/// #471: an outside assistant's rebuild, publish and unpublish rebuild the
/// preview with the same <c>--build-only</c> leg a deploy builds with, and
/// since #467 that leg refuses while the section is being deployed. Their
/// answers say the launcher's own line, as the window does, rather than "the
/// preview couldn't be built" and a pointer at a window this process does not
/// have. Runs <c>shared-rules.json → deployWhileItsSectionDeploys.
/// refusedBuildAnswers</c> case for case, through the real
/// <see cref="Plantoir.Mcp.PlantoirTools"/>; nothing is retyped here.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class RefusedBuildAnswersTests : IDisposable
{
    private const string Course = "ICS4U";
    private const int Section = 2;
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-refused-build").FullName;
    private readonly FakeLauncher _launcher = new() { FailOn = "preview" };

    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["deployWhileItsSectionDeploys"]!;

    public RefusedBuildAnswersTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        string course = Path.Combine(_folder, "courses", Course);
        Directory.CreateDirectory(Path.Combine(course, ".netlify_sites"));
        File.WriteAllText(Path.Combine(course, "course_config.json"), """
            { "course_code": "ICS4U", "course_name": "Computer Science", "deploy_target": "netlify",
              "num_sections": 2, "per_section_folders": ["All Classes"], "per_section_files": [],
              "section_numbers": [1, 2] }
            """);
        foreach (int section in new[] { 1, 2 })
            File.WriteAllText(Path.Combine(course, ".netlify_sites", $"section{section}.json"),
                              $$"""{"name": "ics4u-s{{section}}"}""");
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    public static IEnumerable<object[]> Cases() =>
        Rule["refusedBuildAnswers"]!.AsArray().Select(c => new object[] { c!["name"]!.ToString(), c.ToJsonString() });

    [Fact]
    public void EveryPathAndBothCrossFormsAreCovered()
    {
        var cases = Rule["refusedBuildAnswers"]!.AsArray();
        var tools = cases.Select(c => c!["tool"]!.ToString()).ToHashSet();
        Assert.Equal(new HashSet<string> { "rebuild_preview", "publish_pages", "unpublish_pages" }, tools);
        Assert.Contains(cases, c => c!["crossArrivesAs"]?.ToString() == "?");
        Assert.Contains(cases, c => c!["crossArrivesAs"]?.ToString() is { Length: > 1 });
    }

    [Theory]
    [MemberData(nameof(Cases))]
    public async Task EachCaseSaysTheLaunchersOwnLine(string name, string json)
    {
        var c = JsonNode.Parse(json)!.AsObject();
        string tool = c["tool"]!.ToString();
        var launcherCase = Rule["failureExplanationCases"]!.AsArray()[c["failureExplanationCase"]!.GetValue<int>()]!;
        string output = launcherCase["output"]!.ToString();
        string lifted = launcherCase["expect"]!.ToString();
        string cross = c["crossArrivesAs"]?.ToString() ?? "❌";
        output = output.Replace("❌", cross);

        // As plantoir-mcp's LauncherRunner carries a failed launcher's output.
        _launcher.FailMessage = "(The launcher exited with code 1.)\n\nLast output:\n" + output;
        ClassPage("Unit 2, Day 3", published: tool == "unpublish_pages");

        var server = new PlantoirTools(new AssistWorkspace(_folder, _launcher));
        string[]? pages = c["arguments"]?["pages"] is { } given
            ? PlantoirTools.ClassTitles(given.ToString())
            : null;
        string[] answers = tool switch
        {
            "rebuild_preview" => new[] { await server.RebuildPreview(Course, Section, null!, CancellationToken.None) },
            "publish_pages" => Halves(await server.PublishPages(Course, Section, null!, CancellationToken.None, pages)),
            "unpublish_pages" => Halves(await server.UnpublishPages(Course, Section, null!, CancellationToken.None, pages)),
            _ => throw new InvalidOperationException($"{name}: no tool called {tool} here."),
        };

        Assert.True(_launcher.Runs.Any(run => run.Launcher == "preview" && run.Arguments.Contains("--build-only")),
            $"{name}: the preview was never rebuilt, so nothing was refused. The answer was: {string.Join(" | ", answers)}");
        string whereTheOutputIs = ContractLoader.LoadJson("assist-wording.json")["wording"]!["whereTheOutputIs"]!.ToString();
        foreach (string answer in answers)
        {
            Assert.Contains(lifted, answer);
            Assert.DoesNotContain(cross, answer);
            Assert.DoesNotContain("❌", answer);
            Assert.DoesNotContain(whereTheOutputIs, answer);
            Assert.DoesNotContain("Last output:", answer);
        }
    }

    private static string[] Halves(ModelContextProtocol.Protocol.CallToolResult result) =>
        new[] { result.Detail(), result.Summary() };

    private void ClassPage(string title, bool published)
    {
        string full = Path.Combine(_folder, "courses", Course, $"section{Section}", "All Classes", title + ".md");
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, $"---\ntitle: {title}\npublish: {(published ? "true" : "false")}\n---\nBody.\n");
    }
}

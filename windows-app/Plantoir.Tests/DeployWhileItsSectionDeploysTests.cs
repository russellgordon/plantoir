using System.Linq;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
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

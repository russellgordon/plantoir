using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Mirrors the mac's MultiDestinationDeployRunnerTests.swift — the pieces
/// testable without actually spawning deploy.ps1 (refusal reasoning,
/// milestone selection, outcome bookkeeping, and wording selection). The
/// sequencing itself (RunAsync) is exercised end to end by driving a real
/// deploy, the same way the mac's own sequencing is.
/// </summary>
public class MultiDestinationDeployRunnerTests
{
    private static readonly CourseConfiguration.DeployDestination Netlify = new("netlify", "");
    private static readonly CourseConfiguration.DeployDestination Cloudflare = new("cloudflare_pages", "");
    private static readonly string ValidFolderPath = Directory.CreateTempSubdirectory("multidest-runner-tests").FullName;
    private static readonly CourseConfiguration.DeployDestination Folder = new("local_folder", ValidFolderPath);
    private static readonly CourseConfiguration.DeployDestination BadFolder = new("local_folder", "");

    [Fact]
    public void RefusesOnAnAdditionalCloudflareTargetWithNoAccountID()
    {
        string? refusal = MultiDestinationDeployRunner.RefusalReason(
            new[] { Netlify, Cloudflare }, cloudflareAccountID: "");
        Assert.NotNull(refusal);
        Assert.Contains("Account ID", refusal);
    }

    [Fact]
    public void RefusesOnAnAdditionalFolderTargetWithNoValidPath()
    {
        string? refusal = MultiDestinationDeployRunner.RefusalReason(
            new[] { Netlify, BadFolder }, cloudflareAccountID: "0123456789abcdef0123456789abcdef");
        Assert.NotNull(refusal);
        Assert.Contains("folder", refusal, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void NoRefusalWhenEveryDestinationIsUsable()
    {
        string? refusal = MultiDestinationDeployRunner.RefusalReason(
            new[] { Netlify, Cloudflare, Folder }, cloudflareAccountID: "0123456789abcdef0123456789abcdef");
        Assert.Null(refusal);
    }

    [Fact]
    public void NetlifyNeedsNoCredentialAsEitherPrimaryOrAdditional()
    {
        Assert.Null(MultiDestinationDeployRunner.RefusalReason(new[] { Netlify }, ""));
        Assert.Null(MultiDestinationDeployRunner.RefusalReason(new[] { Cloudflare, Netlify }, "0123456789abcdef0123456789abcdef"));
    }

    [Fact]
    public void DeployOnlyMilestonesDifferPerDestinationType()
    {
        Assert.NotEqual(MultiDestinationDeployRunner.DeployOnlyMilestones("netlify"),
                         MultiDestinationDeployRunner.DeployOnlyMilestones("cloudflare_pages"));
        Assert.Equal(TaskMilestones.Deploy, MultiDestinationDeployRunner.DeployOnlyMilestones("netlify"));
        Assert.Equal(TaskMilestones.DeployToCloudflare, MultiDestinationDeployRunner.DeployOnlyMilestones("cloudflare_pages"));
        Assert.Equal(TaskMilestones.DeployToFolder, MultiDestinationDeployRunner.DeployOnlyMilestones("local_folder"));
    }

    [Fact]
    public void BuildAndDeployMilestonesMatchTheSingleDestinationLists()
    {
        Assert.Equal(TaskMilestones.BuildAndDeploy, MultiDestinationDeployRunner.BuildAndDeployMilestones("netlify"));
        Assert.Equal(TaskMilestones.BuildAndDeployToCloudflare, MultiDestinationDeployRunner.BuildAndDeployMilestones("cloudflare_pages"));
        Assert.Equal(TaskMilestones.BuildAndDeployToFolder, MultiDestinationDeployRunner.BuildAndDeployMilestones("local_folder"));
    }

    [Theory]
    [InlineData(new string[] { }, "")]
    [InlineData(new[] { "Cloudflare Pages" }, "Cloudflare Pages")]
    [InlineData(new[] { "Cloudflare Pages", "your folder" }, "Cloudflare Pages and your folder")]
    [InlineData(new[] { "Netlify", "Cloudflare Pages", "your folder" }, "Netlify, Cloudflare Pages and your folder")]
    public void JoinedWithAndHandlesEveryCount(string[] items, string expected) =>
        Assert.Equal(expected, MultiDestinationDeployRunner.JoinedWithAnd(items));

    [Fact]
    public void ASingleDestinationCourseAlwaysUsesTheUnchangedWording()
    {
        var outcome = new MultiDestinationDeployRunner.Outcome(true, Array.Empty<CourseConfiguration.DeployDestination>());
        var result = MultiDestinationDeployRunner.Result("ICS3U", "1", destinationCount: 1, outcome);
        Assert.True(result.Succeeded);
        Assert.Equal(Plantoir.Core.Assist.AssistWording.Deployed("ICS3U", "1"), result.Message);
    }

    [Fact]
    public void AllDestinationsSucceeding()
    {
        var outcome = new MultiDestinationDeployRunner.Outcome(true, Array.Empty<CourseConfiguration.DeployDestination>());
        var result = MultiDestinationDeployRunner.Result("ICS3U", "1", destinationCount: 2, outcome);
        Assert.True(result.Succeeded);
        Assert.Contains("all 2 destinations", result.Message);
    }

    [Fact]
    public void SomeDestinationsFailingNamesWhichOnes()
    {
        var outcome = new MultiDestinationDeployRunner.Outcome(true, new[] { Cloudflare });
        var result = MultiDestinationDeployRunner.Result("ICS3U", "1", destinationCount: 2, outcome);
        Assert.False(result.Succeeded);
        Assert.Contains("Cloudflare Pages", result.Message);
    }

    [Fact]
    public void EveryDestinationFailing()
    {
        var outcome = new MultiDestinationDeployRunner.Outcome(false, new[] { Netlify, Cloudflare });
        var result = MultiDestinationDeployRunner.Result("ICS3U", "1", destinationCount: 2, outcome);
        Assert.False(result.Succeeded);
        Assert.Contains("did not finish, on any of its destinations", result.Message);
    }

    [Fact]
    public void ActiveRunnerFallsBackSafelyWithNoLegs()
    {
        var runner = new MultiDestinationDeployRunner();
        Assert.NotNull(runner.ActiveRunner);
        Assert.False(runner.ActiveRunner.IsRunning);
    }

    [Fact]
    public void OutcomeAllSucceededRequiresAtLeastOneSuccessAndNoFailures()
    {
        Assert.True(new MultiDestinationDeployRunner.Outcome(true, Array.Empty<CourseConfiguration.DeployDestination>()).AllSucceeded);
        Assert.False(new MultiDestinationDeployRunner.Outcome(false, Array.Empty<CourseConfiguration.DeployDestination>()).AllSucceeded);
        Assert.False(new MultiDestinationDeployRunner.Outcome(true, new[] { Netlify }).AllSucceeded);
    }
}

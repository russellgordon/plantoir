using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json → activityTrail.mustRecord → "site built again before
/// deploying"</c> (#799, the mac's #768 and #748 part 2): the line's words
/// for every reason, read from the contract and never retyped, and the
/// reasons the app's reader can give are exactly the ones the line has words
/// for.
/// </summary>
public class BuiltBeforeDeployingTrailTests
{
    internal static JsonObject Entry =>
        ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Select(e => e!.AsObject())
            .Single(e => e["event"]!.GetValue<string>() == "site built again before deploying");

    private const string Course = "ICS4U";
    private const int Section = 2;

    /// <summary>The contract's line for a reason, with the course and section filled in.</summary>
    internal static string ContractLine(string reason)
    {
        string line = reason == BuildFreshness.ReasonNeverBuilt
            ? Entry["lineWhenItHadNotBeenBuilt"]!.GetValue<string>()
            : Entry["line"]!.GetValue<string>().Replace("{why}", Entry["whyWords"]![reason]!.GetValue<string>());
        return line.Replace("{course}", Course).Replace("{section}", Section.ToString());
    }

    public static IEnumerable<object[]> EveryReason()
    {
        foreach (var (key, _) in Entry["whyWords"]!.AsObject()) yield return new object[] { key };
        yield return new object[] { BuildFreshness.ReasonNeverBuilt };
    }

    [Theory]
    [MemberData(nameof(EveryReason))]
    public void TheLineIsTheContractsForEveryReason(string reason)
    {
        Assert.Equal(ContractLine(reason), $"{Course}/{Section} · {ActivityTrail.BuiltBeforeDeployingWords(reason)}");
    }

    [Fact]
    public void EveryReasonTheAppGivesHasWordsOnTheLine()
    {
        var words = Entry["whyWords"]!.AsObject().Select(p => p.Key).ToHashSet();
        foreach (string reason in new[]
                 {
                     BuildFreshness.ReasonFrontPageUnreadable, BuildFreshness.ReasonPreview,
                     BuildFreshness.ReasonClock, BuildFreshness.ReasonPages,
                 })
            Assert.Contains(reason, words);
        // and toolchain, which deploy.ps1 and the scheduled wrapper give
        Assert.Contains("toolchain", words);
        var reasons = ContractLoader.LoadJson("app-rules.json")["buildFreshness"]!["reuseTheLastBuild"]!["reasons"]!.AsObject();
        Assert.True(reasons.ContainsKey(BuildFreshness.ReasonNeverBuilt));
        foreach (string word in words) Assert.True(reasons.ContainsKey(word), word + " is not a reason in reuseTheLastBuild.reasons");
    }

    // ---- The app's Deploy button (MultiDestinationDeployRunner) -------------

    [Fact]
    public void ABuildThatWentThroughWritesItsReasonAndNothingElseWritesAtAll()
    {
        Assert.Equal(ActivityTrail.BuiltBeforeDeployingWords(BuildFreshness.ReasonPages),
            MultiDestinationDeployRunner.TrailLineAfterBuild(BuildFreshness.ReasonPages, built: true, cancelled: false, stopped: false));
        Assert.Equal(ActivityTrail.BuiltBeforeDeployingWords(BuildFreshness.ReasonNeverBuilt),
            MultiDestinationDeployRunner.TrailLineAfterBuild(BuildFreshness.ReasonNeverBuilt, true, false, false));
        Assert.Null(MultiDestinationDeployRunner.TrailLineAfterBuild(null, true, false, false));           // reused: no build
        Assert.Null(MultiDestinationDeployRunner.TrailLineAfterBuild(BuildFreshness.ReasonPages, false, false, false)); // failed or refused
        Assert.Null(MultiDestinationDeployRunner.TrailLineAfterBuild(BuildFreshness.ReasonPages, true, true, false));   // cancelled
        Assert.Null(MultiDestinationDeployRunner.TrailLineAfterBuild(BuildFreshness.ReasonPages, true, false, true));   // stopped
    }

    /// <summary>
    /// RunAsync has no seam for a real build (its legs are ConPTY runners),
    /// so the ORDER is pinned in its source: the line is written after the
    /// build was awaited and after the cancel and failure checks, and
    /// exactly once.
    /// </summary>
    [Fact]
    public void RunAsyncWritesTheLineOnlyAfterTheBuildsOwnChecks()
    {
        string source = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot,
            "windows-app", "Plantoir.Core", "Scripting", "MultiDestinationDeployRunner.cs"));
        int run = source.IndexOf("public async Task RunAsync(", StringComparison.Ordinal);
        int awaited = source.IndexOf("bool built = await runner.WaitUntilFinished();", run, StringComparison.Ordinal);
        int cancelCheck = source.IndexOf("if (runner.WasCancelled || runner.WasStoppedByUser)", awaited, StringComparison.Ordinal);
        int failureCheck = source.IndexOf("if (!built)", awaited, StringComparison.Ordinal);
        int written = source.IndexOf("TrailLineAfterBuild(buildReason, built, runner.WasCancelled, runner.WasStoppedByUser)", run, StringComparison.Ordinal);
        int deploy = source.IndexOf("runner.Run(DeployCommand.ScriptName", run, StringComparison.Ordinal);
        Assert.True(awaited > run && cancelCheck > awaited && failureCheck > awaited, "the build's checks moved");
        Assert.True(written > cancelCheck && written > failureCheck, "the line is written before the build's own checks");
        Assert.True(written < deploy, "the line is written after the deploy started");
        Assert.Equal(written, source.LastIndexOf("TrailLineAfterBuild(buildReason", StringComparison.Ordinal));
    }

    [Fact]
    public void TheEventIsNamedAsTheContractNamesIt()
    {
        Assert.Equal(Entry["event"]!.GetValue<string>(),
            ActivityTrail.KeyFor(ActivityTrail.Event.SiteBuiltAgainBeforeDeploying));
    }
}

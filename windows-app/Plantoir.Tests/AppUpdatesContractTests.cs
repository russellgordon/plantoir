using System.Text.Json.Nodes;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// #337: the rules of updating, played from <c>shared-rules.json → appUpdates</c>
/// — the install gate (14 cases), the quit (6 cases), the feed, and every
/// sentence a teacher reads. The engine itself is not wired yet (see
/// <see cref="AppUpdates"/>).
/// </summary>
public class AppUpdatesContractTests
{
    private static JsonNode Updates => ContractLoader.LoadJson("shared-rules.json")["appUpdates"]!;

    private static List<(string, int)> Pairs(JsonNode? node) =>
        node?.AsArray().Select(p => (p![0]!.ToString(), p[1]!.GetValue<int>())).ToList() ?? new();

    [Fact]
    public void EveryInstallGateCaseIsDecidedAsTheContractSays()
    {
        var cases = Updates["cases"]!.AsArray();
        Assert.Equal(14, cases.Count);
        foreach (var c in cases)
        {
            var g = c!["given"]!;
            var snapshot = new AppUpdates.Snapshot(
                Pairs(g["publishes"]), Pairs(g["previewBuilds"]), g["previewsOpen"]?.GetValue<int>() ?? 0,
                g["otherCopies"]?.AsArray().Select(o => new AppUpdates.OtherCopy(
                    o!["pid"]!.GetValue<int>(), o["kind"]!.ToString(), o["course"]?.ToString(), o["section"]?.GetValue<int>())).ToList()
                    ?? new List<AppUpdates.OtherCopy>(),
                g["leases"]?.AsArray().Select(l => new AppUpdates.LeaseFact(
                    l!["pid"]!.GetValue<int>(), l["kind"]!.ToString(), l["course"]!.ToString())).ToList()
                    ?? new List<AppUpdates.LeaseFact>());
            var hold = AppUpdates.Evaluate(snapshot);
            string name = c["name"]!.ToString();
            Assert.True(c["expectHeld"]!.GetValue<bool>() == hold.Held, $"{name}: held {hold.Held}");
            if (c["expectNamedAs"]?.ToString() is string named)
            {
                Assert.True(named == char.ToLowerInvariant(hold.NamedAs.ToString()[0]) + hold.NamedAs.ToString()[1..], $"{name}: named {hold.NamedAs}");
                if (c["course"] is JsonNode course) Assert.Equal(course.ToString(), hold.Course);
                if (c["section"] is JsonNode section) Assert.Equal(section.GetValue<int>(), hold.Section);
            }
        }
    }

    /// <summary>
    /// Bundle-8 ruling 2, Windows only: a running plantoir-mcp holds the
    /// install even with nothing in the contract's list under way, because the
    /// Windows installer replaces it. A FAKE pid stands for it.
    /// </summary>
    [Fact]
    public void ARunningAssistantServerHoldsTheInstallOnWindows()
    {
        var nothing = new AppUpdates.Snapshot(new List<(string, int)>(), new List<(string, int)>(), 0,
            new List<AppUpdates.OtherCopy>(), new List<AppUpdates.LeaseFact>());
        Assert.False(AppUpdates.EvaluateForInstall(nothing, Array.Empty<int>()).Held);
        var hold = AppUpdates.EvaluateForInstall(nothing, new[] { 424242 });
        Assert.True(hold.Held);
        Assert.Equal(UpdateWording.AssistantElsewhereWork, UpdateWording.Work(hold, "a deploy"));
    }

    [Fact]
    public void EveryQuitCaseIsDecidedAsTheContractSays()
    {
        var cases = Updates["atQuit"]!["cases"]!.AsArray();
        Assert.Equal(6, cases.Count);
        foreach (var c in cases)
        {
            var prepared = c!["given"]!["preparedUpdate"]!.ToString() switch
            {
                "none" => AppUpdates.Prepared.None,
                "readyToInstall" => AppUpdates.Prepared.ReadyToInstall,
                "heldForWork" => AppUpdates.Prepared.HeldForWork,
                "postponedAtInstall" => AppUpdates.Prepared.PostponedAtInstall,
                var other => throw new InvalidOperationException(other),
            };
            var decided = AppUpdates.DecideAtQuit(prepared, c["given"]!["workUnderWay"]!.GetValue<bool>());
            string expected = c["expect"]!.ToString();
            Assert.True(expected == char.ToLowerInvariant(decided.ToString()[0]) + decided.ToString()[1..],
                $"{c["name"]}: {decided}");
        }
    }

    [Fact]
    public void DevelopmentBuildsHaveNoFeed()
    {
        Assert.Null(AppUpdates.FeedFor(developmentBuild: true));
        Assert.Equal(Updates["feed"]!["windows"]!.ToString(), AppUpdates.FeedFor(developmentBuild: false));
        Assert.Equal(Updates["checkEverySeconds"]!.GetValue<int>(), AppUpdates.CheckEverySeconds);
        Assert.False(Updates["installsWithoutAsking"]!.GetValue<bool>());
    }

    [Fact]
    public void EverySentenceIsTheContractsAndNamesNoMachinery()
    {
        var w = Updates["wording"]!;
        var ww = Updates["windowsWording"]!;
        var pinned = new Dictionary<string, (string Contract, string Ours)>
        {
            ["menuItem"] = (w["menuItem"]!.ToString(), UpdateWording.MenuItem),
            ["heldTitle"] = (w["heldTitle"]!.ToString(), UpdateWording.HeldTitle),
            ["scheduledWork"] = (w["scheduledWork"]!.ToString(), UpdateWording.ScheduledWork),
            ["scheduledWorkUnnamed"] = (w["scheduledWorkUnnamed"]!.ToString(), UpdateWording.ScheduledWorkUnnamed),
            ["elsewhereWork"] = (w["elsewhereWork"]!.ToString(), UpdateWording.ElsewhereWorkContract),
            ["heldExplanation"] = (w["heldExplanation"]!.ToString(), UpdateWording.HeldExplanation),
            ["heldExplanationOnceInstalling"] = (w["heldExplanationOnceInstalling"]!.ToString(), UpdateWording.HeldExplanationOnceInstalling),
            ["okButton"] = (w["okButton"]!.ToString(), UpdateWording.OkButton),
            ["needsAdministratorTitle"] = (w["needsAdministratorTitle"]!.ToString(), UpdateWording.NeedsAdministratorTitle),
            ["needsAdministratorExplanation"] = (w["needsAdministratorExplanation"]!.ToString(), UpdateWording.NeedsAdministratorExplanation),
            ["offerTitle"] = (ww["offerTitle"]!.ToString(), UpdateWording.OfferTitle),
            ["offerInstall"] = (ww["offerInstall"]!.ToString(), UpdateWording.OfferInstall),
            ["offerLater"] = (ww["offerLater"]!.ToString(), UpdateWording.OfferLater),
            ["offerSkip"] = (ww["offerSkip"]!.ToString(), UpdateWording.OfferSkip),
            ["upToDate"] = (ww["upToDate"]!.ToString(), UpdateWording.UpToDate),
            ["couldNotCheck"] = (ww["couldNotCheck"]!.ToString(), UpdateWording.CouldNotCheck),
            ["assistantElsewhereWork"] = (ww["assistantElsewhereWork"]!.ToString(), UpdateWording.AssistantElsewhereWork),
            ["elsewhereWorkOnWindows"] = (ww["elsewhereWorkOnWindows"]!.ToString(), UpdateWording.ElsewhereWorkOnWindows),
            ["needsAdministratorExplanationOnWindows"] = (ww["needsAdministratorExplanationOnWindows"]!.ToString(), UpdateWording.NeedsAdministratorExplanationOnWindows),
        };
        foreach (var (key, (contract, ours)) in pinned)
            Assert.True(contract == ours, $"{key}: ours \"{ours}\", the contract's \"{contract}\"");

        string check = w["machineryCheck"]!.ToString();
        var banned = check[(check.IndexOf(':') + 1)..].TrimEnd('.').Split(',').Select(x => x.Trim()).Where(x => x.Length > 0).ToList();
        Assert.Contains("lease", banned);
        foreach (var (key, (_, ours)) in pinned)
            foreach (string word in banned)
                Assert.False(ours.Contains(word, StringComparison.OrdinalIgnoreCase), $"{key} says \"{word}\": {ours}");
    }

    [Fact]
    public void TheInstallerIsToldToReopenOnlyFromTheInAppInstall()
    {
        Assert.Contains("/RELAUNCH=1", AppUpdates.InstallerArguments(relaunch: true));
        Assert.DoesNotContain("RELAUNCH", AppUpdates.InstallerArguments(relaunch: false));
        Assert.Contains("/PLANTOIRUPDATE=1", AppUpdates.InstallerArguments(relaunch: false));
        Assert.Contains("/VERYSILENT", AppUpdates.InstallerArguments(relaunch: false));
        Assert.Contains("/NOCLOSEAPPLICATIONS", AppUpdates.InstallerArguments(relaunch: false));   // ruling 8

        string iss = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "installer.iss"));
        Assert.Contains("{param:RELAUNCH|0}", iss);
        Assert.Contains("Check: WantsRelaunch", iss);
        Assert.Contains("{param:PLANTOIRUPDATE|0}", iss);
        Assert.Contains("if not IsUpdate then", iss);   // the update path skips the taskkill (ruling 2)
        Assert.Contains("function InitializeSetup", iss);   // refuses an update while plantoir-mcp runs
        Assert.Contains("--update-not-installed", iss);                    // ruling 12: a refusal reopens the app
        Assert.Contains("\"/RETURNTO=C:\\P\\Plantoir.exe\"", AppUpdates.InstallerArguments(true, @"C:\P\Plantoir.exe"));
    }

    [Fact]
    public void ARefusedUpdateIsSaidOnTheNextLaunchOnly()
    {
        Assert.Null(AppUpdates.NotInstalledLine(new[] { "Plantoir.exe" }));
        Assert.Null(AppUpdates.NotInstalledLine(new[] { "Plantoir.exe", "--state-dir", "x" }));
        string? line = AppUpdates.NotInstalledLine(new[] { "Plantoir.exe", AppUpdates.UpdateNotInstalledArgument });
        Assert.NotNull(line);
        Assert.Contains("offered again", line);
    }

    [Fact]
    public void OnlyAPerUserCopyUpdatesItself()
    {
        string local = @"C:\Users\t\AppData\Local";
        Assert.True(AppUpdates.IsPerUserInstall(@"C:\Users\t\AppData\Local\Programs\Plantoir", local));
        Assert.False(AppUpdates.IsPerUserInstall(@"C:\Program Files\Plantoir", local));
        Assert.False(AppUpdates.IsPerUserInstall(@"C:\Users\t\AppData\Local\ProgramsX\Plantoir", local));
    }

    [Fact]
    public void AppUpdatedIsWrittenOnlyWhenTheVersionChanged()
    {
        Assert.Null(AppUpdates.AppUpdatedLine(null, "1.2.0", false));
        Assert.Null(AppUpdates.AppUpdatedLine("1.2.0", "1.2.0", false));
        Assert.Equal("updated from 1.1.0 to 1.2.0, by hand (a new copy installed some other way)",
                     AppUpdates.AppUpdatedLine("1.1.0", "1.2.0", false));
    }
}

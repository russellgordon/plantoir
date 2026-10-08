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
            ["needsAdministratorExplanationOnWindows"] = (ww["needsAdministratorExplanationOnWindows"]!.ToString(), UpdateWording.NeedsAdministratorExplanationOnWindows),
        };
        foreach (var (key, (contract, ours)) in pinned)
            Assert.True(contract == ours, $"{key}: ours \"{ours}\", the contract's \"{contract}\"");
        // #438: the Windows-only copy is gone; the contract's {machine} is filled instead.
        Assert.Null(ww["elsewhereWorkOnWindows"]);
        Assert.Equal("waiting for ICS3U to finish building somewhere else on this PC", UpdateWording.ElsewhereWork("ICS3U"));

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

    /// <summary>
    /// Russell, 2026-10-01 (parity bundle 10, Q9): the installer installs for
    /// ONE person only, so every copy it makes can update itself. It no longer
    /// offers "install for all users" (that dialog was
    /// <c>PrivilegesRequiredOverridesAllowed=dialog</c>); an all-users copy made
    /// by an older installer can still exist, and keeps the refusal below.
    /// </summary>
    [Fact]
    public void TheInstallerInstallsForOnePersonOnly()
    {
        string iss = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "installer.iss"));
        var setting = iss.Split('\n').Select(line => line.Trim()).Where(line => !line.StartsWith(';')).ToList();
        Assert.Contains("PrivilegesRequired=lowest", setting);
        Assert.DoesNotContain(setting, line => line.StartsWith("PrivilegesRequiredOverridesAllowed", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(@"DefaultDirName={localappdata}\Programs\Plantoir", setting);
        // What the updater calls per-user is where the installer puts it.
        Assert.True(AppUpdates.IsPerUserInstall(@"C:\Users\t\AppData\Local\Programs\Plantoir", @"C:\Users\t\AppData\Local"));
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
        Assert.Equal("updated from 1.1.0 to 1.2.0, by its own updater",
                     AppUpdates.AppUpdatedLine("1.1.0", "1.2.0", true));
    }

    /// <summary>
    /// #465's cosmetic half: one spelling. Every launch before #465 stored
    /// "1.4 (3)"; the first launch after it reads that as 1.4.3, so the same
    /// version is not taken for an update and a real one is written in one
    /// spelling ("updated from 1.4.3 to 1.4.4", never "from 1.4 (3) to 1.4.4").
    /// </summary>
    [Fact]
    public void TheVersionIsSpelledOneWayAndTheOldSpellingIsRead()
    {
        Assert.Equal("1.4.3", AppUpdates.Spell(new Version(1, 4, 3, 0)));
        Assert.Equal("1.4.0", AppUpdates.Spell(new Version(1, 4)));
        Assert.Equal("1.4.3", AppUpdates.Respell("1.4 (3)"));
        Assert.Equal("1.4.3", AppUpdates.Respell("1.4.3"));
        Assert.Null(AppUpdates.Respell(null));
        Assert.Null(AppUpdates.AppUpdatedLine("1.4 (3)", "1.4.3", false));
        Assert.Equal("updated from 1.4.3 to 1.4.4, by its own updater",
                     AppUpdates.AppUpdatedLine("1.4 (3)", "1.4.4", true));
    }

    /// <summary>
    /// <c>appUpdates.offerCases</c> (#453, appliesOn windows): whether an offer
    /// is shown, and whether it carries Skip This Version and Not Now, decided by
    /// <see cref="AppUpdates.DecideOffer"/>. A case that names an expectation
    /// this test does not know fails rather than being skipped.
    /// </summary>
    [Fact]
    public void EveryOfferCaseIsDecidedAsTheContractSays()
    {
        var block = Updates["offerCases"]!;
        Assert.Contains("windows", block["appliesOn"]!.AsArray().Select(a => a!.ToString()));
        var cases = block["cases"]!.AsArray();
        Assert.True(cases.Count >= 7, $"only {cases.Count} offer cases");
        var failures = new List<string>();
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            var newer = c["newer"]!.AsArray()
                .Select(i => (i!["version"]!.ToString(), i["important"]!.GetValue<bool>())).ToList();
            string? skipped = c["skipped"]?.ToString();
            bool asked = c["teacherAsked"]!.GetValue<bool>();
            var expect = (JsonObject)c["expect"]!;
            Assert.True(expect.Select(e => e.Key).All(k => k is "show" or "allowsSkip" or "allowsLater"),
                $"{name}: an expectation this test does not read");

            var offer = AppUpdates.DecideOffer(newer, skipped, asked);
            string got = $"show {offer.Show}, skip {offer.AllowsSkip}, later {offer.AllowsLater}";
            string wanted = $"show {expect["show"]!.GetValue<bool>()}, skip {expect["allowsSkip"]!.GetValue<bool>()}, later {expect["allowsLater"]!.GetValue<bool>()}";
            if (got != wanted) failures.Add($"{name}: {got}; the contract says {wanted}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    /// <summary>
    /// appUpdates.notes.cumulative (#428 item 2): a teacher offered 1.4.4 who
    /// skipped 1.4.3 still reads 1.4.3's notes, newest first.
    /// </summary>
    [Fact]
    public void TheOfferCarriesTheNotesOfEveryNewerRelease()
    {
        Assert.True(Updates["notes"]!["cumulative"]!.GetValue<bool>());

        Assert.Equal("", AppUpdates.NotesFor(Array.Empty<(string?, string?)>()));
        Assert.Equal("Only this.", AppUpdates.NotesFor(new (string?, string?)[] { ("1.4.3", " Only this.\n") }));
        Assert.Equal("", AppUpdates.NotesFor(new (string?, string?)[] { ("1.4.3", null) }));

        string both = AppUpdates.NotesFor(new (string?, string?)[] { ("1.4.4", "Newer."), ("1.4.3", "Back up first.") });
        Assert.Equal("1.4.4\nNewer.\n\n1.4.3\nBack up first.", both);

        // A release with no notes adds nothing, and does not hide another's.
        Assert.Equal("1.4.3\nBack up first.",
                     AppUpdates.NotesFor(new (string?, string?)[] { ("1.4.4", ""), ("1.4.3", "Back up first.") }));
    }

    /// <summary>
    /// #428 item 1: the installer's marker says "by its own updater" for the
    /// version it installed, once, and never for any other version.
    /// </summary>
    [Fact]
    public void TheUpdatersMarkerSpeaksOnlyForTheVersionItInstalled()
    {
        string folder = Path.Combine(Path.GetTempPath(), "plantoir-marker-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            string marker = Path.Combine(folder, AppUpdates.UpdatedByItselfMarker);
            var running = new Version(1, 4, 3, 0);

            Assert.False(AppUpdates.ConsumeUpdatedByItselfMarker(folder, running));      // no marker: by hand

            File.WriteAllText(marker, "1.4.3");
            Assert.True(AppUpdates.ConsumeUpdatedByItselfMarker(folder, running));
            Assert.False(File.Exists(marker));                                            // read AND removed
            Assert.False(AppUpdates.ConsumeUpdatedByItselfMarker(folder, running));      // so once only

            // A marker left for another version (an update whose app was never
            // opened, then a hand install of something else) is not believed,
            // and is still removed.
            File.WriteAllText(marker, "1.4.2");
            Assert.False(AppUpdates.ConsumeUpdatedByItselfMarker(folder, running));
            Assert.False(File.Exists(marker));

            File.WriteAllText(marker, "not a version");
            Assert.False(AppUpdates.ConsumeUpdatedByItselfMarker(folder, running));
            Assert.False(File.Exists(marker));
        }
        finally { Directory.Delete(folder, true); }
    }

    /// <summary>
    /// The installer half of the marker: every install deletes it before
    /// copying, and only an update that finished writes it, with the version
    /// it installed, where the app looks.
    /// </summary>
    [Fact]
    public void TheInstallerLeavesTheMarkerOnlyAfterAFinishedUpdate()
    {
        string iss = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "installer.iss"));
        Assert.Contains(@"{localappdata}\Plantoir\" + AppUpdates.UpdatedByItselfMarker, iss);
        string code = iss[iss.IndexOf("procedure CurStepChanged", StringComparison.Ordinal)..];
        int install = code.IndexOf("CurStep = ssInstall", StringComparison.Ordinal);
        int delete = code.IndexOf("DeleteFile(UpdatedByItselfMarker)", StringComparison.Ordinal);
        int taskkill = code.IndexOf("if not IsUpdate then", StringComparison.Ordinal);
        Assert.True(install >= 0 && delete > install && delete < taskkill, "every install deletes the marker at ssInstall, outside the update-only branch");
        Assert.Contains("(CurStep = ssPostInstall) and IsUpdate", code);
        Assert.Contains("SaveStringToFile(UpdatedByItselfMarker, '{#AppVersion}'", code);
    }
}

using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// Plantoir never closes Obsidian without asking (#1003, the mac's #995,
/// finding D21 of #975, Russell's ruling Q13): the rule, the words, the trail
/// lines and the close itself, against <c>contracts/shared-rules.json</c> →
/// <c>obsidianNeverClosedUnasked</c>, and by source scan that nothing else in
/// the app closes Obsidian. The route's answers are driven through a fake
/// world in <see cref="ObsidianOpenRouteTests"/> (the "#1003" block).
/// </summary>
public sealed class ObsidianNeverClosedUnaskedTests
{
    private static JsonNode Contract => ContractLoader.LoadJson("shared-rules.json")["obsidianNeverClosedUnasked"]!;

    private static string AppFolder => Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir");

    private static string CoreFolder => Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core");

    // ---- the rule and the words -------------------------------------------------

    [Fact]
    public void EveryCloseCase()
    {
        var cases = Contract["closeCases"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 7, $"only {cases.Count} closeCases");
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            string? registry = c["registryVaults"] is JsonArray vaults
                ? ObsidianFigureAddOnsTests.Registry(vaults.Select(v => (v!.ToString(), false)).ToArray())
                : null;
            bool asked = ObsidianClosingRule.MustAsk(c["target"]!.ToString(), c["running"]!.GetValue<bool>(), registry);
            Assert.True(c["ask"]!.GetValue<bool>() == asked, $"{name}: asked {asked}");
        }
    }

    private static string OurWords(string key) => key switch
    {
        "title" => ObsidianClosingWording.Title,
        "message" => ObsidianClosingWording.Message,
        "closesLabel" => ObsidianClosingWording.ClosesLabel,
        "closesValue" => ObsidianClosingWording.ClosesValue,
        "opensAgainLabel" => ObsidianClosingWording.OpensAgainLabel,
        "opensAgainValue" => ObsidianClosingWording.OpensAgainValue,
        "keptLabel" => ObsidianClosingWording.KeptLabel,
        "keptValue" => ObsidianClosingWording.KeptValue,
        "closeAndOpen" => ObsidianClosingWording.CloseAndOpen,
        "cancel" => ObsidianClosingWording.Cancel,
        "offerAddClosingObsidian" => ObsidianClosingWording.OfferAddClosingObsidian,
        _ => throw new Xunit.Sdk.XunitException($"obsidianNeverClosedUnasked.wording.{key} has no Windows constant"),
    };

    private static string OurAlertWords(string key) => key switch
    {
        "title" => ObsidianClosingWording.CouldNotOpenTitle,
        "didNotClose" => ObsidianClosingWording.CouldNotOpenDidNotClose,
        "notAdded" => ObsidianClosingWording.CouldNotOpenNotAdded,
        "ok" => ObsidianClosingWording.CouldNotOpenOk,
        _ => throw new Xunit.Sdk.XunitException($"obsidianNeverClosedUnasked.couldNotOpen.{key} has no Windows constant"),
    };

    [Fact]
    public void TheWordsAreTheContracts()
    {
        var wording = Contract["wording"]!.AsObject();
        int read = 0;
        foreach (var (key, value) in wording)
        {
            if (key == "factsRule") continue;
            Assert.True(value!.ToString() == OurWords(key), $"wording.{key} differs");
            read++;
        }
        Assert.Equal(11, read);

        // The question as shown: the sentence, a blank line, the three facts
        // a line each in factsRule's order.
        string Words(string key) => ObsidianClosingWording.Filling(wording[key]!.ToString(), "MPM2D");
        Assert.Equal("Close Obsidian to open MPM2D?", ObsidianClosingWording.TitleText("MPM2D"));
        Assert.Equal(Words("message") + "\n\n"
                     + Words("closesLabel") + ": " + Words("closesValue") + "\n"
                     + Words("opensAgainLabel") + ": " + Words("opensAgainValue") + "\n"
                     + Words("keptLabel") + ": " + Words("keptValue"),
            ObsidianClosingWording.MessageText("MPM2D"));
        foreach (string key in new[] { "closesLabel", "closesValue", "opensAgainLabel", "opensAgainValue", "keptLabel", "keptValue" })
            Assert.Contains(key, wording["factsRule"]!.ToString());

        // The go-ahead buttons say Obsidian closes (ruling Q13); Cancel backs out (HIG, Alerts).
        Assert.StartsWith("Close Obsidian", ObsidianClosingWording.CloseAndOpen);
        Assert.StartsWith("Close Obsidian", ObsidianClosingWording.OfferAddClosingObsidian);
        Assert.Equal("Cancel", ObsidianClosingWording.Cancel);
        // Both questions that close Obsidian say what opens again in the same words.
        Assert.Equal(ObsidianFigureAddOnsWording.OpensAgainValue, ObsidianClosingWording.OpensAgainValue);
        // The reopen question's go-ahead says it closes Obsidian too (ruling 1 on #995).
        Assert.StartsWith("Close", ObsidianFigureAddOnsWording.Reopen);
    }

    /// <summary>"Could not open {course} in Obsidian" (ruling 2 on #995): one sentence per failure, and OK alone.</summary>
    [Fact]
    public void TheAlertsWordsAreTheContracts()
    {
        var alert = Contract["couldNotOpen"]!.AsObject();
        int read = 0;
        foreach (var (key, value) in alert)
        {
            if (key == "note") continue;
            Assert.True(value!.ToString() == OurAlertWords(key), $"couldNotOpen.{key} differs");
            read++;
        }
        Assert.Equal(4, read);
        Assert.Equal(ObsidianClosingWording.Filling(alert["didNotClose"]!.ToString(), "MPM2D"),
            ObsidianClosingWording.CouldNotOpenText(ObsidianClosingTrail.Outcome.DidNotClose, "MPM2D"));
        Assert.Equal(ObsidianClosingWording.Filling(alert["notAdded"]!.ToString(), "MPM2D"),
            ObsidianClosingWording.CouldNotOpenText(ObsidianClosingTrail.Outcome.NotAdded, "MPM2D"));
        // Only a failure has an alert.
        foreach (var outcome in new[] { ObsidianClosingTrail.Outcome.Opened, ObsidianClosingTrail.Outcome.Cancelled, ObsidianClosingTrail.Outcome.NotNeeded })
            Assert.Throws<ArgumentOutOfRangeException>(() => ObsidianClosingWording.CouldNotOpenText(outcome, "MPM2D"));
    }

    [Fact]
    public void TheTrailLinesAreTheContracts()
    {
        var trail = Contract["trail"]!.AsObject();
        foreach (var outcome in Enum.GetValues<ObsidianClosingTrail.Outcome>())
        {
            string key = ObsidianFigureAddOnsTests.ContractCase(outcome.ToString());
            Assert.True(trail[key] is not null, $"trail.{key} is missing");
            Assert.Equal(ObsidianClosingWording.Filling(trail[key]!.ToString(), "MPM2D"), ObsidianClosingTrail.Line(outcome, "MPM2D"));
        }
        Assert.Equal(Enum.GetValues<ObsidianClosingTrail.Outcome>().Length + 1, trail.Count);   // every line, and its note
        Assert.Equal("asked to close Obsidian to open a course",
            Plantoir.Core.Scripting.ActivityTrail.KeyFor(Plantoir.Core.Scripting.ActivityTrail.Event.ObsidianClosingAsked));
    }

    /// <summary>The words never name the machinery (CLAUDE.md rule 1, and the add-ons offer's own list).</summary>
    [Fact]
    public void TheWordsNeverNameTheMachinery()
    {
        string[] banned = { "plugin", "vault", "json", "folder", "script", "toolchain", "registry", "docker", "container" };
        var words = new List<(string Key, string Text)>();
        foreach (var (key, value) in Contract["wording"]!.AsObject())
            if (key != "factsRule") words.Add(("wording." + key, value!.ToString()));
        foreach (var (key, value) in Contract["couldNotOpen"]!.AsObject())
            if (key != "note") words.Add(("couldNotOpen." + key, value!.ToString()));
        foreach (var (key, text) in words)
            foreach (string word in banned)
                Assert.False(text.Contains(word, StringComparison.OrdinalIgnoreCase), $"{key} says {word}");
    }

    /// <summary>The add-ons offer's yes says Obsidian closes exactly when it does: open, or cannot tell.</summary>
    [Fact]
    public void TheOffersYesSaysWhenItClosesObsidian()
    {
        var course = new Course("MPM2D", Path.Combine(Path.GetTempPath(), "MPM2D"), CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes("{}")));
        ObsidianAddOnsRequest Request(ObsidianFigureAddOnsOffer.CourseOpenState state) =>
            new(course, course.DirectoryPath, Array.Empty<ObsidianFigureAddOn>(), state);
        Assert.Equal(ObsidianFigureAddOnsWording.OfferAdd, Request(ObsidianFigureAddOnsOffer.CourseOpenState.Closed).AddButtonTitle);
        Assert.Equal(ObsidianClosingWording.OfferAddClosingObsidian, Request(ObsidianFigureAddOnsOffer.CourseOpenState.Open).AddButtonTitle);
        Assert.Equal(ObsidianClosingWording.OfferAddClosingObsidian, Request(ObsidianFigureAddOnsOffer.CourseOpenState.CannotTell).AddButtonTitle);
        // The dialog shows that title, not the constant.
        Assert.Contains("PrimaryButtonText = request.AddButtonTitle,", File.ReadAllText(Path.Combine(AppFolder, "Views", "ObsidianWorld.cs")));
    }

    // ---- the close itself -------------------------------------------------------

    /// <summary>
    /// After the quit, a still-running Obsidian is never written under and
    /// never handed anything. Once it is gone, the course is written into its
    /// list and everything the list marked open opens again, the course left
    /// for the caller to open last.
    /// </summary>
    [Fact]
    public async Task CloseAndRegisterWritesNothingUnderAnObsidianThatStayed()
    {
        string vault = @"C:\w\MPM2D";
        var registered = new List<string>();
        var reopened = new List<IReadOnlyList<string>>();
        int quits = 0;
        Task<bool> Close(bool stays) => ObsidianClosingRule.CloseAndRegisterAsync(
            vault,
            vaultsMarkedOpen: () => new[] { @"C:\w\ICS3U", @"C:\w\Notes", @"C:\w\MPM2D\" },
            quit: () => { quits++; return Task.CompletedTask; },
            stillRunning: () => stays,
            register: registered.Add,
            reopen: paths => { reopened.Add(paths); return Task.CompletedTask; });

        Assert.False(await Close(stays: true));
        Assert.Equal(1, quits);
        Assert.Empty(registered);
        Assert.Empty(reopened);

        Assert.True(await Close(stays: false));
        Assert.Equal(new[] { vault }, registered);
        Assert.Equal(new[] { @"C:\w\ICS3U", @"C:\w\Notes" }, reopened.Single());
    }

    /// <summary>What opens again is read the add-ons' reopen's way: every vault the list marks open while Obsidian runs, never only what has a window.</summary>
    [Fact]
    public void WhatOpensAgainIsWhatTheListMarksOpen()
    {
        string body = Body(Code(Path.Combine(AppFolder, "Views", "FolderActions.cs")), "public static Task<bool> CloseObsidianAndRegister(");
        Assert.Contains("ObsidianFigureAddOnsOffer.VaultsOpen(", body);
        Assert.Contains("ObsidianClosingRule.CloseAndRegisterAsync(", body);
    }

    // ---- nothing else can close it ----------------------------------------------

    /// <summary>
    /// The only code that closes Obsidian is the answer to a question that
    /// says so: the closing question's (<c>FolderActions.CloseObsidianAndRegister</c>,
    /// through the world), the add-ons offer's and the reopen question's
    /// (<c>ReopenWithAddOnsAsync</c>, through the world's <c>QuitAndWaitAsync</c>),
    /// and the rename's (Close Obsidian and Rename). Until #1003
    /// <c>FolderActions.OpenInObsidian</c> quit Obsidian itself, unasked.
    /// </summary>
    [Fact]
    public void OnlyAnAnswerClosesObsidian()
    {
        var quits = Count(AppFolder, "QuitObsidianAndWait(");
        // FolderActions: the definition and CloseObsidianAndRegister's quit.
        // ObsidianWorld: QuitAndWaitAsync. SidebarPane: the rename's answer.
        Assert.Equal(new Dictionary<string, int> { ["FolderActions.cs"] = 2, ["ObsidianWorld.cs"] = 1, ["SidebarPane.xaml.cs"] = 1 }, quits);
        Assert.Equal(new Dictionary<string, int> { ["ObsidianProcesses.cs"] = 1 }, Count(AppFolder, "CloseMainWindow("));
        Assert.Equal(new Dictionary<string, int> { ["FolderActions.cs"] = 1, ["ObsidianWorld.cs"] = 1 }, Count(AppFolder, "CloseObsidianAndRegister("));

        string open = Body(Code(Path.Combine(AppFolder, "Views", "FolderActions.cs")), "public static Task<bool> OpenInObsidian(");
        Assert.DoesNotContain("QuitObsidianAndWait", open);
        Assert.DoesNotContain("CloseObsidianAndRegister", open);

        // In the route, the world is closed from two places only, each an answer.
        string route = Code(Path.Combine(CoreFolder, "Models", "ObsidianOpenRoute.cs"));
        Assert.Equal(1, Occurrences(route, "_world.QuitAndWaitAsync("));
        Assert.Contains("_world.QuitAndWaitAsync(", Body(route, "private async Task ReopenWithAddOnsAsync("));
        Assert.Equal(1, Occurrences(route, "_world.CloseAndRegisterAsync("));
        string asking = Body(route, "private async Task AskClosingAsync(");
        Assert.Contains("_world.CloseAndRegisterAsync(", asking);
        Assert.True(asking.IndexOf("_world.AskClosingAsync(", StringComparison.Ordinal) < asking.IndexOf("_world.CloseAndRegisterAsync(", StringComparison.Ordinal),
            "the close comes after the question");
    }

    // ---- helpers ----------------------------------------------------------------

    /// <summary>The file's code with comment lines left out, so a comment that names a call is not counted as one.</summary>
    private static string Code(string file) =>
        string.Join("\n", File.ReadAllLines(file).Where(line => !line.TrimStart().StartsWith("//", StringComparison.Ordinal)));

    private static int Occurrences(string text, string what) => text.Split(what).Length - 1;

    private static Dictionary<string, int> Count(string folder, string what) =>
        Directory.EnumerateFiles(folder, "*.cs", SearchOption.AllDirectories)
            .Where(file => !file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                           && !file.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}"))
            .Select(file => (Name: Path.GetFileName(file), Count: Occurrences(Code(file), what)))
            .Where(pair => pair.Count > 0)
            .ToDictionary(pair => pair.Name, pair => pair.Count);

    /// <summary>The text from <paramref name="signature"/> to the brace that closes its body (an expression body ends at its semicolon).</summary>
    private static string Body(string code, string signature)
    {
        int start = code.IndexOf(signature, StringComparison.Ordinal);
        Assert.True(start >= 0, $"{signature} not found");
        int depth = 0;
        bool opened = false;
        for (int i = start; i < code.Length; i++)
        {
            char character = code[i];
            if (character == '{') { depth++; opened = true; }
            else if (character == '}')
            {
                depth--;
                if (opened && depth == 0) return code[start..(i + 1)];
            }
            else if (character == ';' && !opened && depth == 0) return code[start..(i + 1)];
        }
        return code[start..];
    }
}

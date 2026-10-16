using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/shared-rules.json</c> → <c>openRecent</c> (#488, the mac's
/// #457): the cap, how the list changes when a folder is opened, what each
/// entry is called, and what a folder that cannot be opened says. Cases marked
/// <c>appliesOn: ["mac"]</c> (one folder spelled two ways on the mac's disk)
/// are skipped by that declaration, not by a list here. The mac runs the same
/// cases in <c>RecentWorkingFoldersTests</c>.
/// </summary>
public class OpenRecentContractTests
{
    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["openRecent"]!;

    private static bool AppliesHere(JsonNode c) =>
        c["appliesOn"] is null || c["appliesOn"]!.AsArray().Any(p => p!.ToString() == "windows");

    private static List<string> Strings(JsonNode node) => node.AsArray().Select(n => n!.ToString()).ToList();

    [Fact]
    public void TheCapIsTheContracts() =>
        Assert.Equal(Rule["cap"]!.GetValue<int>(), RecentWorkingFolders.Cap);

    [Fact]
    public void EveryAddingCaseForWindowsGivesTheListTheContractSays()
    {
        var all = Rule["addingCases"]!.AsArray().Select(c => c!).ToList();
        var cases = all.Where(AppliesHere).ToList();
        Assert.True(cases.Count >= 5, $"addingCases for Windows: {cases.Count} (5 of 6 when this was written)");
        var failures = new List<string>();
        foreach (var c in cases)
        {
            var (after, writes) = RecentWorkingFolders.Adding(Strings(c["before"]!), c["opened"]!.ToString());
            var expected = Strings(c["after"]!);
            if (!expected.SequenceEqual(after))
                failures.Add($"{c["why"]}: expected [{string.Join(", ", expected)}], got [{string.Join(", ", after)}]");
            bool expectWrites = c["writes"]?.GetValue<bool>() ?? true;
            if (writes != expectWrites)
                failures.Add($"{c["why"]}: expected writes={expectWrites}, got {writes}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void OneFolderSpelledTwoWaysOnWindowsIsOneEntry_KeptAtTheSpellingJustOpened()
    {
        // Windows' own form of the mac-only spelling case: case and a trailing
        // separator, compared with WorkingFolder.IsTheSame.
        var (after, writes) = RecentWorkingFolders.Adding(new[] { @"C:\Users\t\Courses", @"C:\Users\t\Clubs" }, @"c:\users\t\courses\");
        Assert.True(writes);
        Assert.Equal(new[] { @"c:\users\t\courses\", @"C:\Users\t\Clubs" }, after);
    }

    [Fact]
    public void EveryTitleCaseIsTitledAsTheContractSays()
    {
        foreach (var c in Rule["titleCases"]!.AsArray().Select(c => c!))
            Assert.Equal(Strings(c["titles"]!), RecentWorkingFolders.Titles(Strings(c["folders"]!)));
    }

    [Fact]
    public void TwoFoldersOfOneNameAtTheTopOfTwoDrivesAreToldApartByTheDrive() =>
        Assert.Equal(new[] { "Courses — C:", "Courses — D:" },
                     RecentWorkingFolders.Titles(new[] { @"C:\Courses", @"D:\Courses" }));

    [Fact]
    public void TheSentencesWindowsCanSayAreTheContracts()
    {
        var wording = Rule["wording"]!;
        Assert.Equal(wording["title"]!.ToString(), OpenRecentWording.TitleTemplate);
        Assert.Equal(wording["gone"]!.ToString(), OpenRecentWording.Gone);
        Assert.Equal(wording["driveNotConnected"]!.ToString(), OpenRecentWording.DriveNotConnected);
        Assert.Equal(wording["unreadable"]!.ToString(), OpenRecentWording.Unreadable);
        Assert.Equal(wording["gone"]!.ToString(), OpenRecentWording.Sentence(LastWorkingFolder.Gone));
        Assert.Equal(wording["driveNotConnected"]!.ToString(), OpenRecentWording.Sentence(LastWorkingFolder.DriveNotConnected));
        Assert.Equal(wording["unreadable"]!.ToString(), OpenRecentWording.Sentence(LastWorkingFolder.Unreadable));
        Assert.Equal(wording["title"]!.ToString().Replace("{folder}", "Courses"), OpenRecentWording.Title(@"D:\Work\Courses\"));
    }

    [Fact]
    public void TheFirstReadSeedsTheListFromTheLastFolderAndTheRememberedWindows()
    {
        var settings = new AppSettings
        {
            WorkspacePath = @"C:\Users\t\Courses",
            RememberedWindows =
            {
                new RememberedWindow(@"C:\Users\t\courses", 0, 0, 900, 600),
                new RememberedWindow(@"C:\Users\t\Clubs", 0, 0, 900, 600),
            },
        };
        Assert.Null(settings.RecentWorkingFolders);
        Assert.Equal(new[] { @"C:\Users\t\Courses", @"C:\Users\t\Clubs" }, settings.RecentFolders);
        Assert.NotNull(settings.RecentWorkingFolders);
    }
}

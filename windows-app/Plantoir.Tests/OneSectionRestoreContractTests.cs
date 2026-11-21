using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/course-management.json</c> → <c>backups.restoreOneSection</c>
/// (#911), run from the JSON: every sentence Windows says is the template
/// filled in, and the list of a section's files outside its folder is the
/// contract's, path, kind and treatment.
/// </summary>
public sealed class OneSectionRestoreContractTests
{
    private static JsonNode Rule => ContractLoader.LoadJson("course-management.json")["backups"]!["restoreOneSection"]!;

    private static string Template(string key) => Rule["wording"]![key]!.GetValue<string>();

    private static string Filled(string key, int section, string? code = null, string? reason = null, string? kept = null) =>
        Template(key).Replace("{N}", section.ToString(System.Globalization.CultureInfo.InvariantCulture))
                     .Replace("{CODE}", code ?? "{CODE}")
                     .Replace("{REASON}", reason ?? "{REASON}")
                     .Replace("{KEPT}", kept ?? "{KEPT}");

    [Fact]
    public void TheStoppedAndLeftSentencesAreTheContractsTemplates()
    {
        Assert.Equal(Filled("leftAsItWas", 2, reason: "a file is open"), OneSectionRestoreWording.LeftAsItWas(2, "a file is open"));
        Assert.Equal(Filled("stoppedPartWay", 3, kept: @"courses\_backups\ICS3U\Section 3 before a restore 2026-11-21_031500"),
                     OneSectionRestoreWording.StoppedPartWay(3, @"courses\_backups\ICS3U\Section 3 before a restore 2026-11-21_031500"));
        Assert.Equal(Filled("stoppedPartWayNothingToOpen", 4), OneSectionRestoreWording.StoppedPartWayNothingToOpen(4));
        Assert.Equal(Template("stoppedPartWayArchived"), OneSectionRestoreWording.StoppedPartWayArchived);
    }

    [Fact]
    public void TheFilesOutsideTheSectionAreTheContractsList()
    {
        var listed = Rule["filesOutsideTheSection"]!.AsArray();
        Assert.Equal(listed.Count, OneSectionRestore.FilesOutsideTheSection.Count);
        for (int index = 0; index < listed.Count; index++)
        {
            var entry = listed[index]!;
            var ours = OneSectionRestore.FilesOutsideTheSection[index];
            Assert.Equal(entry["path"]!.GetValue<string>(), ours.PathTemplate);
            Assert.Equal(entry["folder"]!.GetValue<bool>(), ours.IsFolder);
            Assert.Equal(entry["treatment"]!.GetValue<string>(), JsonName(ours.Treatment));
        }
    }

    // ---- step 2: the offer rule and the naming rule, from the JSON ----------

    [Fact]
    public void EveryOfferCaseGivesTheContractsSection()
    {
        var cases = Rule["offerCases"]!.AsArray();
        Assert.Equal(8, cases.Count);
        foreach (var testCase in cases)
        {
            string name = testCase!["name"]!.GetValue<string>();
            int? makerSection = testCase["makerSection"]?.GetValue<int>();
            BackupMaker maker = testCase["maker"]!.GetValue<string>() switch
            {
                "menu" => new BackupMaker.Menu(makerSection!.Value, SubjectMenuLayout.Menu.Section),
                "assistant" => new BackupMaker.Assistant(makerSection!.Value),
                "teacher" => BackupMaker.DefaultTeacher,
                var other => throw new InvalidOperationException(name + ": a maker called " + other + " is not known here"),
            };
            int? offered = OneSectionRestore.OfferedSection(maker,
                testCase["sectionExistsNow"]!.GetValue<bool>(),
                testCase["keptForReference"]!.GetValue<bool>(),
                testCase["renameUnfinished"]!.GetValue<bool>(),
                testCase["backupHasTheSection"]!.GetValue<bool>(),
                testCase["namingSameAsNow"]!.GetValue<bool>());
            Assert.True(testCase["offered"]?.GetValue<int>() == offered, $"{name}: offered {offered?.ToString() ?? "null"}");
        }
    }

    [Fact]
    public void EveryNamingCaseFindsTheContractsDifference()
    {
        var cases = Rule["namingCases"]!.AsArray();
        Assert.Equal(12, cases.Count);
        foreach (var testCase in cases)
        {
            string name = testCase!["name"]!.GetValue<string>();
            var live = OneSectionRestore.Naming.Of(CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes(testCase["live"]!.ToJsonString())));
            var backup = OneSectionRestore.Naming.Of(CourseConfiguration.FromBytes(System.Text.Encoding.UTF8.GetBytes(testCase["backup"]!.ToJsonString())));
            var difference = live.DifferenceFromBackup(backup);
            string? expected = testCase["difference"]?.GetValue<string>();
            string? found = difference switch
            {
                OneSectionRestore.NamingDifference.ClassPages => "classPages",
                OneSectionRestore.NamingDifference.Folders => "folders",
                _ => null,
            };
            Assert.True(expected == found, $"{name}: {found ?? "null"}");
            Assert.Equal(testCase["same"]!.GetValue<bool>(), difference is null);
        }
    }

    [Fact]
    public void TheFactsAreReadFromTheZipsListingAndItsSettingsEntryAndAnUnreadableZipHoldsNothing()
    {
        using var fixture = new SectionSwapFixture();
        fixture.Write("a.md", "a");
        var backup = fixture.BackUp();

        var facts = OneSectionRestore.ReadFacts(backup.FilePath);
        Assert.Equal(new[] { 1, 2 }, facts.SectionsInside.OrderBy(number => number));
        Assert.NotNull(facts.Naming);
        Assert.Equal("Unit", facts.Naming!.Word);
        Assert.Equal(new[] { "Notes" }, facts.Naming.SharedFolders);

        string broken = Path.Combine(fixture.Folder, "broken.zip");
        File.WriteAllText(broken, "not a zip");
        var none = OneSectionRestore.ReadFacts(broken);
        Assert.Empty(none.SectionsInside);
        Assert.Null(none.Naming);
    }

    private static string JsonName(OneSectionRestore.Treatment treatment) => treatment switch
    {
        OneSectionRestore.Treatment.FromTheBackup => "fromTheBackup",
        OneSectionRestore.Treatment.Discarded => "discarded",
        _ => "leftAsItIs",
    };
}

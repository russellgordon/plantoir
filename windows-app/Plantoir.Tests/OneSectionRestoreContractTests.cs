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

    private static string JsonName(OneSectionRestore.Treatment treatment) => treatment switch
    {
        OneSectionRestore.Treatment.FromTheBackup => "fromTheBackup",
        OneSectionRestore.Treatment.Discarded => "discarded",
        _ => "leftAsItIs",
    };
}

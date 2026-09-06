using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// Every sentence a teacher reads when something cannot be removed, pinned
/// against <c>contracts/shared-rules.json</c> -> <c>specialNames</c>.
///
/// Nothing here is retyped: each assertion reads the contract and compares it
/// to what the app would actually show. A literal in a test is the copy that
/// keeps passing after the product's words change.
/// </summary>
public class SpecialNamesContractTests
{
    private static JsonNode SpecialNamesJson =>
        ContractLoader.LoadJson("shared-rules.json")["specialNames"]!;

    private static string Reason(string key) => SpecialNamesJson[key]!["reason"]!.ToString();

    [Fact]
    public void BlockedSentences_MatchContract()
    {
        Assert.Equal(Reason("curriculumFolderBlockedByCoverageSetting"),
                     SpecialNames.CurriculumFolderBlockedByCoverageSetting);
        Assert.Equal(Reason("curriculumFolderBlockedByCoverageMap"),
                     SpecialNames.CurriculumFolderBlockedByCoverageMap);
        Assert.Equal(Reason("lastGradedFolderBlocked"),
                     SpecialNames.LastGradedFolderBlocked);
        Assert.Equal(Reason("lastGradedFolderBlockedWizard"),
                     SpecialNames.LastGradedFolderBlockedWizard);
        Assert.Equal(Reason("classFolderBlocked"),
                     SpecialNames.ClassFolderBlocked);
        Assert.Equal(Reason("lastPerSectionFolderBlocked"),
                     SpecialNames.LastPerSectionFolderBlocked);
        Assert.Equal(Reason("sectionIndexFileBlocked"),
                     SpecialNames.SectionIndexFileBlocked);
    }

    /// <summary>
    /// The jurisdiction is substituted where the contract puts
    /// <c>{jurisdiction}</c>, so a BC teacher is told about the switch a BC
    /// teacher can see.
    /// </summary>
    [Fact]
    public void TheCurriculumPagesSentenceCarriesTheJurisdiction()
    {
        string template = Reason("curriculumFolderBlockedByCurriculumPages");
        Assert.Contains("{jurisdiction}", template);

        Assert.Equal(template.Replace("{jurisdiction}", "Ontario"),
                     SpecialNames.CurriculumFolderBlockedByCurriculumPages("Ontario"));
        Assert.Equal(template.Replace("{jurisdiction}", "British Columbia"),
                     SpecialNames.CurriculumFolderBlockedByCurriculumPages("British Columbia"));
    }

    [Fact]
    public void ConfirmationSentences_MatchContract()
    {
        var graded = SpecialNamesJson["removeGradedFolderConfirmation"]!;
        Assert.Equal(graded["title"]!.ToString().Replace("{name}", "Tasks"),
                     SpecialNames.RemoveGradedFolderTitle("Tasks"));
        Assert.Equal(graded["message"]!.ToString(), SpecialNames.RemoveGradedFolderMessage);

        var curriculum = SpecialNamesJson["removeCurriculumFolderConfirmation"]!;
        Assert.Equal(curriculum["title"]!.ToString().Replace("{name}", "Ontario Curriculum"),
                     SpecialNames.RemoveCurriculumFolderTitle("Ontario Curriculum"));
        Assert.Equal(curriculum["message"]!.ToString(), SpecialNames.RemoveCurriculumFolderMessage);
    }

    /// <summary>
    /// Russell's decision of 2026-08-24: the folder named "All Classes" is
    /// blocked outright, and the confirmation sentence that used to cover
    /// class folders is GONE from the contract. If it comes back, somebody has
    /// reintroduced a rule that was deliberately removed.
    /// </summary>
    [Fact]
    public void ThereIsNoClassFolderConfirmationAnyMore()
    {
        Assert.Null(SpecialNamesJson["removeClassFolderConfirmation"]);
    }

    /// <summary>
    /// The whole point of a blocked sentence is that it names the switch to
    /// turn off. These assertions are what stops a Windows label drifting away
    /// from the sentence that names it — which it had, before this piece: the
    /// Course Settings toggle read "Include Curriculum Coverage map" while the
    /// contract told teachers to turn off "Publish the curriculum coverage
    /// map".
    /// </summary>
    [Fact]
    public void EveryBlockedSentenceNamesASwitchTheAppActuallyHas()
    {
        Assert.Contains(SpecialNames.CoverageSwitchLabelInSettings,
                        SpecialNames.CurriculumFolderBlockedByCoverageSetting);
        Assert.Contains(SpecialNames.CoverageSwitchLabelInSettings,
                        SpecialNames.LastGradedFolderBlocked);

        Assert.Contains(SpecialNames.CoverageSwitchLabelInWizard,
                        SpecialNames.CurriculumFolderBlockedByCoverageMap);
        Assert.Contains(SpecialNames.CoverageSwitchLabelInWizard,
                        SpecialNames.LastGradedFolderBlockedWizard);

        Assert.Contains(SpecialNames.CurriculumPagesSwitchLabel("Ontario"),
                        SpecialNames.CurriculumFolderBlockedByCurriculumPages("Ontario"));
    }

    /// <summary>
    /// The flyout has to be sized for the LONGEST sentence, so the mac's
    /// truncated-popover bug cannot happen again here. This test names which
    /// one that is, so a future sentence that overtakes it fails rather than
    /// quietly becoming the one nobody checked.
    /// </summary>
    [Fact]
    public void TheLongestSentenceIsStillTheOneTheFlyoutWasSizedFor()
    {
        var all = new[]
        {
            SpecialNames.CurriculumFolderBlockedByCoverageSetting,
            SpecialNames.CurriculumFolderBlockedByCoverageMap,
            SpecialNames.CurriculumFolderBlockedByCurriculumPages("British Columbia"),
            SpecialNames.LastGradedFolderBlocked,
            SpecialNames.LastGradedFolderBlockedWizard,
            SpecialNames.ClassFolderBlocked,
            SpecialNames.LastPerSectionFolderBlocked,
            SpecialNames.SectionIndexFileBlocked,
        };

        Assert.Equal(SpecialNames.LastGradedFolderBlocked, all.OrderByDescending(s => s.Length).First());
    }

    /// <summary>
    /// Every `specialNames` entry carrying a `reason` is used by this app. A
    /// sentence the mac authored and Windows never shows is a teacher on one
    /// platform getting an explanation the other does not.
    /// </summary>
    [Fact]
    public void NoBlockedSentenceInTheContractIsUnusedHere()
    {
        var shown = new[]
        {
            SpecialNames.CurriculumFolderBlockedByCoverageSetting,
            SpecialNames.CurriculumFolderBlockedByCoverageMap,
            SpecialNames.LastGradedFolderBlocked,
            SpecialNames.LastGradedFolderBlockedWizard,
            SpecialNames.ClassFolderBlocked,
            SpecialNames.LastPerSectionFolderBlocked,
            SpecialNames.SectionIndexFileBlocked,
        }.ToHashSet();

        foreach (var (key, value) in SpecialNamesJson.AsObject())
        {
            if (value?["reason"] is null) continue;
            string reason = value["reason"]!.ToString();
            if (reason.Contains("{jurisdiction}"))
            {
                Assert.Equal(reason.Replace("{jurisdiction}", "Ontario"),
                             SpecialNames.CurriculumFolderBlockedByCurriculumPages("Ontario"));
                continue;
            }
            Assert.Contains(reason, shown);
        }
    }
}

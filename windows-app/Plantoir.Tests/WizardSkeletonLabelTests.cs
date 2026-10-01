using System.Text.Json.Nodes;
using Plantoir.Core.Catalogs;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json</c> → <c>wizard.skeletonToggleLabelSubject</c> (GitHub
/// issue #349, the mac's #336): "Start from an English skeleton", not "a
/// english". Each family is resolved through <see cref="SkeletonCatalog"/> to
/// its manifest label — never a label copied here, the skeletons being
/// generated.
/// </summary>
public class WizardSkeletonLabelTests
{
    private static JsonNode Rule =>
        ContractLoader.LoadJson("shared-rules.json")["wizard"]!["skeletonToggleLabelSubject"]!;

    private static List<string> Strings(JsonNode? node) => node!.AsArray().Select(n => n!.ToString()).ToList();

    [Fact]
    public void EveryFamilyInTheContractReadsItsOwnSentence()
    {
        var cases = Rule["cases"]!.AsArray();
        Assert.True(cases.Count >= 16, $"skeletonToggleLabelSubject lost cases: {cases.Count} (16 when this was written)");

        var failures = cases
            .Select(c => (family: c!["family"]!.ToString(), expect: c["expect"]!.ToString()))
            .Select(c => (c.family, c.expect,
                actual: SkeletonCatalog.GetFamilyByName(WizardSkeletonToggleTests.SkeletonsRoot, c.family) is { } f
                    ? WizardWording.SkeletonToggleLabel(f.Name, f.Label)
                    : $"<no family {c.family}>"))
            .Where(c => c.expect != c.actual)
            .Select(c => $"{c.family}: expected \"{c.expect}\", got \"{c.actual}\"")
            .ToList();
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void TheWordListsAreTheContracts()
    {
        Assert.Equal(Strings(Rule["properNouns"]), WizardWording.ProperNouns);
        Assert.Equal(Strings(Rule["article"]!["consonantSoundVowelStarts"]), WizardWording.ConsonantSoundVowelStarts);
        Assert.Equal(Strings(Rule["article"]!["vowelSoundConsonantStarts"]), WizardWording.VowelSoundConsonantStarts);
    }

    [Fact]
    public void TheDialogRendersTheLabelThroughTheRule()
    {
        string source = File.ReadAllText(Path.Combine(
            ContractLoader.RepositoryRoot, "windows-app", "Plantoir", "Views", "NewCourseDialog.cs"));
        Assert.Contains("WizardWording.SkeletonToggleLabel(skeleton.Name, skeleton.Label)", source);
    }
}

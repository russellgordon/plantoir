using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Copy a Page's four-step rule that makes a copy HIDDEN (#247, #258):
/// <c>copyingAPageBetweenCourses.frontmatterCases</c>, and the guard's
/// <c>builderAgreement.cases</c> — both pure, both deserialised.
/// </summary>
public class CopyAPageFrontmatterTests
{
    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["copyingAPageBetweenCourses"]!;

    [Fact]
    public void EveryFrontmatterCaseComposesAHiddenPage()
    {
        var cases = Rule["frontmatterCases"]!.AsArray();
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            var sections = c["sections"]!.AsArray().Select(n => n!.GetValue<int>()).ToList();
            string? composed = CopyPageFrontmatter.Compose(c["source"]!.ToString(), sections);
            Assert.True(composed is not null, $"{name}: no room for a key");
            foreach (var must in c["mustContain"]!.AsArray())
                Assert.True(composed!.Contains(must!.ToString(), StringComparison.Ordinal), $"{name}: lacks \"{must}\"\n{composed}");
            foreach (var mustNot in c["mustNotContain"]!.AsArray())
                Assert.False(composed!.Contains(mustNot!.ToString(), StringComparison.Ordinal), $"{name}: carries \"{mustNot}\"\n{composed}");
            foreach (var section in c["hiddenInSections"]!.AsArray())
                Assert.True(CopyPageFrontmatter.IsHiddenEverywhere(composed!, new[] { section!.GetValue<int>() }), $"{name}: not hidden in section {section}");
            Assert.True(CopyPageFrontmatter.IsCertainlyHidden(composed!, sections), $"{name}: not certified\n{composed}");
        }
        Assert.True(cases.Count >= 9, $"only {cases.Count} cases");
    }

    [Fact]
    public void EveryBuilderAgreementCaseIsTheContracts()
    {
        var cases = Rule["builderAgreement"]!["cases"]!.AsArray();
        foreach (var c in cases)
            Assert.True(c!["builderAgrees"]!.GetValue<bool>() == CopyPageFrontmatter.BuilderAgrees(c["text"]!.ToString()),
                c["name"]!.ToString());
        Assert.True(cases.Count >= 36, $"only {cases.Count} cases");
    }

    [Fact]
    public void ASourceWhoseOnlyCloseIsIndentedIsGivenABlockOfItsOwn()
    {
        string composed = CopyPageFrontmatter.Compose("---\ntitle: X\npublish: true\n  ---\nBody\n", new[] { 1 })!;
        Assert.StartsWith("---\npublishForSection1: false\npublish: false\n---\n", composed);
        Assert.True(CopyPageFrontmatter.IsCertainlyHidden(composed, new[] { 1 }));
    }

    [Fact]
    public void EveryWordingKeyIsTheContracts()
    {
        var wording = Rule["wording"]!.AsObject();
        int compared = 0;
        foreach (var (key, value) in wording)
        {
            if (key is "rule" or "machineryCheck") continue;
            Assert.True(CopyPageWording.Templates.TryGetValue(key, out string? mine), $"wording.{key} is not said here");
            Assert.Equal(value!.ToString(), mine);
            compared++;
        }
        Assert.Equal(compared, CopyPageWording.Templates.Count);
        Assert.True(compared >= 45, $"only {compared}");
    }

    [Fact]
    public void NoSentenceNamesTheMachinery()
    {
        string[] forbidden = { "frontmatter", "wikilink", "embed", "media folder", "walk", "graph", "script", "container",
                               "toolchain", "docker", "yaml", "symlink", "actor", "thread" };
        foreach (string sentence in CopyPageWording.Templates.Values)
            foreach (string word in forbidden)
                Assert.DoesNotContain(word, sentence, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ManyNamesAreListedInTheContractsShape()
    {
        Assert.Equal("These links will not lead anywhere yet: “A”, “B”, “C”.",
            CopyPageWording.Names(new[] { "A", "B", "C" }));
    }
}

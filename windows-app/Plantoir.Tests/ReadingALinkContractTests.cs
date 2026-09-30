using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>shared-rules.json → readingALink.cases</c> (#318 escaped pipe, #339 code
/// is never a link, the mac's #331 comments): the distinct targets
/// <see cref="WikiLinks.Parse"/> finds, trimmed, <c>.md</c> dropped, in order.
/// </summary>
public class ReadingALinkContractTests
{
    [Fact]
    public void EveryReadingALinkCaseIsFollowed()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["readingALink"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 40, $"{cases.Count} readingALink cases; 40 were there when #339 was filed.");
        var failures = new List<string>();
        foreach (var testCase in cases)
        {
            var expect = testCase!["expect"]!.AsArray().Select(node => node!.ToString()).ToList();
            var actual = WikiLinks.Parse(testCase["text"]!.ToString())
                .Select(link => link.Target.EndsWith(".md", StringComparison.OrdinalIgnoreCase) ? link.Target[..^3] : link.Target)
                .Distinct(StringComparer.Ordinal)
                .ToList();
            if (!expect.SequenceEqual(actual))
                failures.Add($"{testCase["name"]}: expected [{string.Join(" | ", expect)}], got [{string.Join(" | ", actual)}]");
        }
        Assert.True(failures.Count == 0,
            "shared-rules.json → readingALink.cases, played against WikiLinks.Parse:\n" + string.Join("\n", failures));
    }

    /// <summary>The escaping backslash survives a rewrite, so a table cell is not split (#318's trap).</summary>
    [Fact]
    public void ARewriteKeepsTheEscapingBackslash()
    {
        var map = new Dictionary<string, string> { ["Unit 2, Day 3"] = "Module 2, Day 3" };
        Assert.Equal("| [[Module 2, Day 3\\|Tuesday]] | `[[Unit 2, Day 3]]` |",
            WikiLinks.Rewriting("| [[Unit 2, Day 3\\|Tuesday]] | `[[Unit 2, Day 3]]` |", map));
    }
}

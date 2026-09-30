using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>course-management.json → sectionNumbers.addingKeysToAPage</c> (#282,
/// the mac's #175 and #181, and #308's #188 case): adding a section gives a
/// course-level page its pair for the new section wherever the build finds
/// the block, splicing by line so the fence, the body and the line endings
/// stay byte for byte.
/// </summary>
public class SectionAdderContractTests
{
    [Fact]
    public void EveryAddingKeysCaseIsFollowedByteForByte()
    {
        var list = ContractLoader.LoadJson("course-management.json")["sectionNumbers"]!["addingKeysToAPage"]!;
        var cases = list["cases"]!.AsArray();
        string created = list["created"]!.ToString();
        int section = list["section"]!.GetValue<int>();
        Assert.True(cases.Count >= 8,
            $"course-management.json carries {cases.Count} adding-keys cases; 8 were there on 2026-09-25.");

        var failures = new List<string>();
        foreach (var testCase in cases)
        {
            string before = testCase!["before"]!.ToString();
            string after = testCase["after"]!.ToString();
            var (written, _) = SectionAdder.ExtendFrontmatter(before, section, created);
            if (!string.Equals(after, written, StringComparison.Ordinal))
                failures.Add($"{testCase["shape"]}\n  expected: {Show(after)}\n  actual:   {Show(written)}");
        }
        Assert.True(failures.Count == 0,
            "course-management.json → sectionNumbers.addingKeysToAPage, played against SectionAdder.ExtendFrontmatter:\n\n"
            + string.Join("\n\n", failures));
    }

    /// <summary>A value that runs onto the next line is carried HELD BACK, and counted as such.</summary>
    [Fact]
    public void AValueOnTheLineBelowIsHeldBackAndCounted()
    {
        var (_, outcome) = SectionAdder.ExtendFrontmatter(
            "---\ntitle: Loops\ncreatedSection1: x\npublishForSection1:\n  false\n---\nBody.\n", 2, "d");
        Assert.Equal(SectionAdder.PageOutcome.GivenKeysAndKeptHiddenBecauseUnreadable, outcome);

        var (_, plain) = SectionAdder.ExtendFrontmatter(
            "---\ntitle: Loops\ncreatedSection1: x\npublishForSection1: false\n---\nBody.\n", 2, "d");
        Assert.Equal(SectionAdder.PageOutcome.GivenKeys, plain);
    }

    /// <summary>
    /// A QUOTED per-section key is the same key to YAML (bundle 2 review,
    /// finding 3): a page carrying only quoted keys used to be skipped, so the
    /// new section had no key and the page — hidden in section 1 — was SHOWN.
    /// </summary>
    [Fact]
    public void AQuotedPerSectionKeyIsGivenItsPairToo()
    {
        var (written, outcome) = SectionAdder.ExtendFrontmatter(
            "---\ntitle: Loops\n\"createdSection1\": 2026-09-08T07:00:00.000-0400\n\"publishForSection1\": false\n---\nBody.\n",
            2, "2026-09-25T07:00:00.000-0400");
        Assert.Equal(SectionAdder.PageOutcome.GivenKeys, outcome);
        Assert.Equal(
            "---\ntitle: Loops\n\"createdSection1\": 2026-09-08T07:00:00.000-0400\n\"publishForSection1\": false\n" +
            "createdSection2: 2026-09-25T07:00:00.000-0400\npublishForSection2: false\n---\nBody.\n", written);
    }

    [Fact]
    public void TheTrailLineIsTheMacsWordForWord()
    {
        Assert.Equal("added section 2; 1 page shared by every section given a date and a published-or-hidden setting for it",
            SectionAdder.TrailLine(2, 1));
        Assert.Equal("added section 3; 4 pages shared by every section given a date and a published-or-hidden setting for it; " +
                     "2 of them were kept hidden because its setting for the other sections could not be read",
            SectionAdder.TrailLine(3, 4, 2));
    }

    /// <summary>
    /// The section copy's landing page (#284): a title below its key goes
    /// with it, and a CRLF page keeps its carriage returns.
    /// </summary>
    [Fact]
    public void TheSectionCopyReplacesATitleWithItsContinuationAndKeepsCarriageReturns()
    {
        string before = "----\r\ntitle:\r\n  Old, Section 1\r\ncreated: 2026-09-08T07:00:00.000-0400\r\npublish: true\r\n----\r\nBody.\r\n";
        string after = SectionAdder.ReplaceTitleAndCreated(before, "Old, Section 2", "2026-09-25T07:00:00.000-0400");
        Assert.Equal("----\r\ntitle: Old, Section 2\r\ncreated: 2026-09-25T07:00:00.000-0400\r\npublish: true\r\n----\r\nBody.\r\n", after);
    }

    private static string Show(string text) => text.Replace("\r", "\\r").Replace("\n", "\\n");
}

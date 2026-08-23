using Plantoir.Core.Catalogs;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The New Course wizard's province-scoped course-code picker — no contract
/// case for this (it's visual, see WINDOWS-HANDOFF.md), so these are plain
/// unit tests mirroring the mac's CourseCatalog.matching behaviour.
/// </summary>
public class CourseCatalogTests
{
    private static readonly List<CourseCatalogEntry> Entries = new()
    {
        new("SCH3U", "Chemistry", "Chemistry, Grade 11, University Preparation", "ON"),
        new("SCH4U", "Chemistry", "Chemistry, Grade 12, University Preparation", "ON"),
        new("ICS3U", "Computer Science", "Introduction to Computer Science, Grade 11, University Preparation", "ON"),
        new("SNC1W", "Science", "Science, Grade 9 Applied", "ON"),
    };

    [Fact]
    public void EmptyQueryReturnsWholeCatalogSortedByCode()
    {
        var result = CourseCatalog.Matching(Entries, "", 10);
        Assert.Equal(new[] { "ICS3U", "SCH3U", "SCH4U", "SNC1W" }, result.Select(e => e.Code));
    }

    [Fact]
    public void CodePrefixMatchesLeadOverNameMatches()
    {
        // "sch" prefixes SCH3U/SCH4U but also appears nowhere in SNC1W's
        // name; a course whose formal name merely mentions "science" should
        // never outrank a code that actually starts with the query.
        var result = CourseCatalog.Matching(Entries, "sch", 10);
        Assert.Equal(new[] { "SCH3U", "SCH4U" }, result.Select(e => e.Code));
    }

    [Fact]
    public void MatchesAgainstNameNotJustCode()
    {
        var result = CourseCatalog.Matching(Entries, "computer science", 10);
        Assert.Equal(new[] { "ICS3U" }, result.Select(e => e.Code));
    }

    [Fact]
    public void RespectsLimit()
    {
        var result = CourseCatalog.Matching(Entries, "", 2);
        Assert.Equal(2, result.Count);
    }

    [Fact]
    public void MatchIsCaseInsensitive()
    {
        var result = CourseCatalog.Matching(Entries, "sCh3U", 10);
        Assert.Equal(new[] { "SCH3U" }, result.Select(e => e.Code));
    }
}

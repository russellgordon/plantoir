using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// What a new section inherits from an existing one, for the single most
/// consequential field in the product.
///
/// <para>Adding a section copies each course-level page's per-section pair —
/// <c>createdSection&lt;N&gt;</c> and <c>publishForSection&lt;N&gt;</c> — from
/// the lowest section the page already names. Until 2026-09-19 that copy
/// compared a legacy <c>draftSection1</c> value with the literal string
/// "true", so <c>draftSection1: yes</c> and <c>draftSection1: On</c> were
/// carried into the new section as PUBLISHED while the build went on hiding
/// the original. The same inversion was fixed in the mac's
/// <c>SectionAdder.publishValue</c> and in
/// <c>setup_course.per_section_frontmatter</c> (issue #140).</para>
///
/// <para>The current spelling is carried VERBATIM instead of being read and
/// re-written: whatever the build makes of <c>publishForSection1: oN</c> it
/// makes of <c>publishForSection2: oN</c>, so no reader standing between the
/// two can invert it by misreading it.</para>
/// </summary>
public class SectionCarryVisibilityTests
{
    private static string? Carry(params string[] frontmatterLines) =>
        SectionAdder.PublishValue(1, new List<string>(frontmatterLines));

    // ---- The current spelling: copied character for character -------------

    [Theory]
    [InlineData("true")]
    [InlineData("false")]
    [InlineData("oN")]
    [InlineData("maybe")]
    [InlineData("\"False\"")]
    [InlineData("no")]
    [InlineData("true # why")]
    public void ThePerSectionValueIsCopiedVerbatim(string value) =>
        Assert.Equal(value, Carry($"publishForSection1: {value}"));

    [Fact]
    public void AKeyWithNothingAfterItCopiesTheEmptiness()
    {
        // A null PUBLISHES the page. Writing "false" here would hide, at course
        // setup, a page the teacher's own file publishes.
        Assert.Equal("", Carry("publishForSection1:"));
        Assert.Equal("", Carry("publishForSection1:   "));
    }

    [Fact]
    public void AValueThatRunsOntoTheNextLineIsHeldBack()
    {
        // It cannot be copied — the copy would be a key with nothing after it,
        // which is a NULL and publishes. Tested before the empty case on
        // purpose: an indented value below the key makes the key LOOK empty.
        Assert.Equal("false", Carry("publishForSection1:", "  false"));
        Assert.Equal("false", Carry("publishForSection1: >-", "  false"));
        Assert.Equal("false", Carry("publishForSection1: |-", "  false"));
    }

    [Fact]
    public void TheLastOfTwoKeysWinsAndAQuotedKeyIsStillTheKey()
    {
        // PyYAML keeps the LAST of two identical keys; taking the first
        // carried the value the build throws away.
        Assert.Equal("false", Carry("publishForSection1: true", "publishForSection1: false"));
        // And a prefix test missed this line entirely, so the page was carried
        // across as though it named no section at all.
        Assert.Equal("false", Carry("\"publishForSection1\": false"));
        Assert.Equal("false", Carry("publishForSection1 : false"));
    }

    // ---- The legacy spelling: read, and INVERTED --------------------------

    [Theory]
    [InlineData("true", "false")]
    [InlineData("false", "true")]
    [InlineData("yes", "false")]      // the inversion that was shipping wrong
    [InlineData("On", "false")]
    [InlineData("TrUe", "false")]     // the build lowercases text before comparing
    [InlineData("\"true\"", "false")]
    [InlineData("\"yes\"", "true")]   // quoted, `yes` never becomes the boolean
    [InlineData("maybe", "true")]
    [InlineData("no", "true")]
    public void ALegacyDraftValueIsReadTheWayTheBuildReadsIt(string stored, string expected) =>
        Assert.Equal(expected, Carry($"draftSection1: {stored}"));

    [Fact]
    public void ALegacyValueThisAppCannotReadIsHeldBack()
    {
        // A page wrongly held back is one a teacher notices and fixes; a page
        // wrongly published is one nobody notices at all.
        Assert.Equal("false", Carry("draftSection1: !!str false"));
        Assert.Equal("false", Carry("draftSection1:", "  true"));
        Assert.Equal("false", Carry("draftSection1: [true]"));
    }

    [Fact]
    public void TheCurrentSpellingWinsOverTheLegacyOne()
    {
        Assert.Equal("true", Carry("publishForSection1: true", "draftSection1: true"));
    }

    [Fact]
    public void APageNamingNeitherKeyCarriesNothing()
    {
        Assert.Null(Carry("title: Syllabus", "createdSection1: 2026-09-08"));
        Assert.Null(Carry("publishForSection2: false"));
        Assert.Null(Carry("  publishForSection1: false"));   // indented: some other mapping's field
    }
}

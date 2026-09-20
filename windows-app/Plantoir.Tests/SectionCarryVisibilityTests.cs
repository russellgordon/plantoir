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

    /// <summary>
    /// The LEGACY key, whose value runs onto the next line, is held back too —
    /// including when the key's own line looks like a complete value.
    /// </summary>
    /// <remarks>
    /// <para>Pinned because it CHANGED and nothing else covers it. Until the
    /// reader was corrected (2026-09-19, issue #176) <c>draftSection1: false</c>
    /// with an indented line under it was read as a plain <c>false</c> and
    /// carried across as PUBLISHED.</para>
    ///
    /// <para><b>The mac still does that, so this is a real divergence and a new
    /// one.</b> The Swift's <c>reading(ofValue:followedBy:)</c> consults the
    /// line below only when the key's line is EMPTY, and
    /// <c>SectionAdder.publishValue</c> asks it — so the mac carries these as
    /// "true". Measured what the SITE does with the source page
    /// (python-frontmatter 1.3.0 / PyYAML 6.0.3, then
    /// <c>build_site._as_bool</c>): <c>'false x'</c>, <c>'no x'</c>,
    /// <c>'true x'</c> and <c>'yes x'</c> all fold into strings that are not
    /// "true", so the source page is PUBLISHED in every one of those rows, and
    /// only <c>draftSection1:</c> over <c>  true</c> is HIDDEN.</para>
    ///
    /// <para>Neither app reproduces that. Both err HELD BACK — the mac in two
    /// of those rows, this in four — and uniformly held back is the documented
    /// preference and the Python's answer. The mac's #176 fix closes it,
    /// because its carry asks the same reader.</para>
    /// </remarks>
    [Theory]
    [InlineData("draftSection1: false")]   // the row that changed, and that the mac still carries as "true"
    [InlineData("draftSection1: no")]      // and this one
    [InlineData("draftSection1: true")]
    [InlineData("draftSection1: yes")]
    [InlineData("draftSection1:")]
    [InlineData("draftSection1: >-")]
    public void ALegacyValueThatRunsOntoTheNextLineIsHeldBack(string keyLine) =>
        Assert.Equal("false", Carry(keyLine, "  x"));

    /// <summary>
    /// And the same key with nothing below it is read, not refused — the
    /// guard that keeps the theory above from passing for the wrong reason.
    /// </summary>
    [Fact]
    public void ALegacyValueOnItsOwnIsStillReadNormally()
    {
        Assert.Equal("true", Carry("draftSection1: false"));
        Assert.Equal("true", Carry("draftSection1: no"));
        Assert.Equal("false", Carry("draftSection1: true"));
        Assert.Equal("false", Carry("draftSection1: yes"));
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

    // ---- And what the WRITER then does with what this generated ------------

    /// <summary>
    /// Adding a section, then hiding the page in it: end to end, because the
    /// two halves were each right and the join was not.
    /// </summary>
    /// <remarks>
    /// <para>Copying the emptiness of a null <c>publishForSection&lt;N&gt;</c>
    /// is deliberate (a null publishes), so this generates
    /// <c>publishForSection2:</c> with nothing after it — and
    /// <c>ReplaceValue</c> used to keep the teacher's spacing, which for an
    /// empty value is NO spacing, so hiding the page wrote
    /// <c>publishForSection2:false</c>.</para>
    ///
    /// <para>That is not a key. YAML needs a space, a tab or the end of the
    /// line after the colon, and measured with python-frontmatter 1.3.0 /
    /// PyYAML 6.0.3 the line beside <c>createdSection2:</c> — which this same
    /// method always writes next to it — is a <c>ScannerError</c> that stops
    /// the whole build, while the app reports the page hidden. Plantoir
    /// corrupting a page Plantoir generated, in two ordinary steps.</para>
    /// </remarks>
    [Fact]
    public void TheEmptyCarryCanStillBeHiddenAfterwards()
    {
        string root = Path.Combine(Path.GetTempPath(), "carry-" + Guid.NewGuid().ToString("N"));
        try
        {
            var course = SectionAdderTests.MakeCourse(root, "ICS3U",
                """
                {"course_code":"ICS3U","course_name":"Computer Science","section_numbers":[1],
                 "per_section_folders":["All Classes"],"shared_folders":["Concepts"]}
                """);
            string page = Path.Combine(course.DirectoryPath, "Concepts", "Ohm's Law.md");
            Directory.CreateDirectory(Path.GetDirectoryName(page)!);
            File.WriteAllText(page,
                "---\ntitle: Ohm's Law\ncreatedSection1: 2026-09-08T07:00:00.000-0400\n" +
                "publishForSection1:\n---\nThe lesson.\n");

            SectionAdder.ExtendCourseLevelPages(course, 2, "2026-09-09T07:00:00.000-0400");

            string generated = File.ReadAllText(page);
            Assert.Contains("publishForSection2:\n", generated, StringComparison.Ordinal);
            Assert.DoesNotContain("publishForSection2: \n", generated, StringComparison.Ordinal);
            // A null publishes, so the new section says what the old one says.
            Assert.Equal(PageVisibility.Visible, PageVisibilityReader.Answer(generated, 2));

            var (hidden, edit) = PageFrontmatter.SetDraft(generated, "publishForSection2", draft: true, 2);

            Assert.True(edit.Changed);
            Assert.DoesNotContain("publishForSection2:false", hidden, StringComparison.Ordinal);
            Assert.Contains("publishForSection2: false", hidden, StringComparison.Ordinal);
            Assert.Equal(PageVisibility.Hidden, PageVisibilityReader.Answer(hidden, 2));
            // And section 1 is none of that edit's business.
            Assert.Equal(PageVisibility.Visible, PageVisibilityReader.Answer(hidden, 1));
        }
        finally { try { Directory.Delete(root, recursive: true); } catch { } }
    }
}

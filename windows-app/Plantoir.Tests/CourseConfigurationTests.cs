using System.Text;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

public class CourseConfigurationTests
{
    private static CourseConfiguration FromJson(string json) =>
        CourseConfiguration.FromBytes(Encoding.UTF8.GetBytes(json));

    [Fact]
    public void PublishingAccessorsDefaultToNetlifyAndRoundTrip()
    {
        var config = FromJson("""{"course_code":"ICS3U"}""");
        Assert.Equal("netlify", config.DeployTarget);
        Assert.False(config.DeploysToLocalFolder);

        config.DeployTarget = "local_folder";
        Assert.False(config.DeploysToLocalFolder);   // no folder chosen yet
        config.DeployFolderPath = @"C:\somewhere";
        Assert.True(config.DeploysToLocalFolder);
    }

    [Fact]
    public void CloudflareIsAThirdDestinationAndRoundTrips()
    {
        var config = FromJson("""{"course_code":"ICS3U"}""");
        Assert.False(config.DeploysToCloudflare);

        config.DeployTarget = "cloudflare_pages";
        Assert.True(config.DeploysToCloudflare);
        // The three destinations stay strangers — picking one never reads as
        // another.
        Assert.False(config.DeploysToLocalFolder);
    }

    [Fact]
    public void CloudflareAccountProblemsAreNamedInPlainWords()
    {
        Assert.Equal("Paste your Cloudflare Account ID.",
            CourseConfiguration.CloudflareAccountProblem("   "));

        // 32 hex characters is the shape Cloudflare uses; anything else is
        // caught here rather than by a failed publish.
        string valid = new string('a', 24) + "0123456f";
        Assert.Null(CourseConfiguration.CloudflareAccountProblem(valid));
        Assert.Null(CourseConfiguration.CloudflareAccountProblem("  " + valid.ToUpperInvariant() + "  "));

        Assert.NotNull(CourseConfiguration.CloudflareAccountProblem(valid[..31]));       // too short
        Assert.NotNull(CourseConfiguration.CloudflareAccountProblem(valid + "a"));       // too long
        Assert.NotNull(CourseConfiguration.CloudflareAccountProblem(valid[..31] + "z")); // not hex
    }

    [Fact]
    public void DeployFolderProblemsAreNamedInPlainWords()
    {
        Assert.Equal("Choose the folder this course deploys into.",
            CourseConfiguration.DeployFolderProblem("   "));

        string missing = Path.Combine(Path.GetTempPath(), "no-such-" + Guid.NewGuid().ToString("N"));
        Assert.Contains("doesn’t exist", CourseConfiguration.DeployFolderProblem(missing));

        string file = Path.Combine(Path.GetTempPath(), "file-" + Guid.NewGuid().ToString("N") + ".txt");
        File.WriteAllText(file, "x");
        try { Assert.Contains("That’s a file", CourseConfiguration.DeployFolderProblem(file)); }
        finally { File.Delete(file); }

        string good = Path.Combine(Path.GetTempPath(), "ok-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(good);
        try { Assert.Null(CourseConfiguration.DeployFolderProblem(good)); }
        finally { try { Directory.Delete(good); } catch { } }
    }

    /// <summary>
    /// Mirrors build_site.py's computed_landing_title: [Grade X ]Name[, Section N],
    /// each switch literal, empty name falling back to the code.
    /// </summary>
    [Theory]
    [InlineData("Computer Science", "ICS3U", 1, true, true, "Grade 11 Computer Science, Section 1")]
    [InlineData("Computer Science", "ICS3U", 1, false, true, "Computer Science, Section 1")]
    [InlineData("Computer Science", "ICS3U", 3, true, false, "Grade 11 Computer Science")]
    [InlineData("Computer Science", "ICS3U", 3, false, false, "Computer Science")]
    [InlineData("Newsroom", "CODING", 1, true, true, "Newsroom, Section 1")]   // clubs carry no grade
    [InlineData("", "ics3u", 2, true, true, "Grade 11 ICS3U, Section 2")]      // nameless falls back to code
    public void ComputedSiteTitleMatchesTheBuild(string name, string code, int section,
        bool grade, bool marker, string expected) =>
        Assert.Equal(expected, CourseConfiguration.ComputedSiteTitle(name, code, section, grade, marker));

    [Fact]
    public void UnknownKeysSurviveARoundTrip()
    {
        var config = FromJson("""{"course_code":"ICS3U","future_toolchain_key":{"nested":[1,2,3]},"course_name":"CS"}""");
        config.CourseName = "Computer Science";
        string written = Encoding.UTF8.GetString(config.SerializedBytes());
        Assert.Contains("future_toolchain_key", written);
        Assert.DoesNotContain("\r", written);   // LF only, like the toolchain
        Assert.Contains("[1,", written.Replace(" ", "").Replace("\n", ""));
    }

    [Fact]
    public void WriteSortsKeysAndEndsWithNewline()
    {
        var config = FromJson("""{"zebra":1,"apple":2,"course_code":"X"}""");
        string written = Encoding.UTF8.GetString(config.SerializedBytes());
        Assert.EndsWith("\n", written);
        Assert.True(written.IndexOf("apple") < written.IndexOf("course_code"));
        Assert.True(written.IndexOf("course_code") < written.IndexOf("zebra"));
    }

    [Fact]
    public void EmojiSurvivesWritingUnescaped()
    {
        var config = FromJson("""{"course_code":"X"}""");
        config.SetEmoji(1, "📚");
        string written = Encoding.UTF8.GetString(config.SerializedBytes());
        Assert.Contains("📚", written);
        Assert.DoesNotContain("\\u", written);
    }

    [Fact]
    public void SectionNumbersReadDirectly() =>
        Assert.Equal(new[] { 1, 3 }, FromJson("""{"course_code":"X","section_numbers":[1,3]}""").SectionNumbers);

    [Fact]
    public void SectionNumbersFallBackToNumSections() =>
        Assert.Equal(new[] { 1, 2, 3 }, FromJson("""{"course_code":"X","num_sections":3}""").SectionNumbers);

    [Fact]
    public void SectionNumbersDefaultToOne() =>
        Assert.Equal(new[] { 1 }, FromJson("""{"course_code":"X"}""").SectionNumbers);

    [Fact]
    public void SectionNumbersSortedInAscendingOrder() =>
        Assert.Equal(new[] { 2, 4, 5, 9 }, FromJson("""{"course_code":"X","section_numbers":[5,4,2,9]}""").SectionNumbers);

    [Fact]
    public void SetSectionNumbersWritesBothKeys()
    {
        var config = FromJson("""{"course_code":"X"}""");
        config.SetSectionNumbers(new[] { 2, 4 });
        Assert.Equal(2, (int)config.Values["num_sections"]!);
        Assert.Equal(new[] { 2, 4 }, config.SectionNumbers);
    }

    [Fact]
    public void LegacyGradeBoolWinsForEverySection()
    {
        var config = FromJson("""{"course_code":"ICS3U","show_grade_in_title":false}""");
        Assert.False(config.ShowsGradeInTitle(1));
        Assert.False(config.ShowsGradeInTitle(7));
    }

    [Fact]
    public void FirstPerSectionWriteReplacesLegacyBool()
    {
        var config = FromJson("""{"course_code":"ICS3U","show_grade_in_title":false}""");
        config.SetShowsGradeInTitle(2, true);
        Assert.True(config.ShowsGradeInTitle(2));
        Assert.True(config.ShowsGradeInTitle(1));   // map default, legacy gone
        Assert.IsType<JObject>(config.Values["show_grade_in_title"]);
    }

    [Fact]
    public void ColourSchemesAreFlat()
    {
        var config = FromJson("""{"course_code":"X"}""");
        config.SetColourSchemeId(1, "coastal-breeze");
        var map = Assert.IsType<JObject>(config.Values["color_schemes"]);
        Assert.Equal("coastal-breeze", (string)map["section1"]!);
        Assert.Null(map["sections"]);
        Assert.Equal("coastal-breeze", config.ColourSchemeId(1));
        Assert.Equal("", config.ColourSchemeId(2));
    }

    [Fact]
    public void EmojiDefaultsAndEmptyFallsBack()
    {
        var config = FromJson("""{"course_code":"X","emojis":{"sections":{"section1":""}}}""");
        Assert.Equal("📚", config.Emoji(1));
        Assert.Equal("📚", config.Emoji(9));
    }

    [Fact]
    public void FontResolutionFallsThroughSectionsThenDefault()
    {
        var config = FromJson("""
            {"course_code":"X","fonts":{"default":{"header":"Lora","body":"Inter","code":"Fira Code"},
             "sections":{"section2":{"header":"Poppins","body":"Merriweather","code":"Ubuntu Mono"}}}}
            """);
        Assert.Equal("Poppins", config.Font(2).Header);
        Assert.Equal("Lora", config.Font(1).Header);
        var bare = FromJson("""{"course_code":"X"}""");
        Assert.Equal(FontChoice.SystemDefault, bare.Font(1));
    }

    [Theory]
    [InlineData("https://ics3u.school.ca/", "ics3u.school.ca")]
    [InlineData("http://ics3u.school.ca/path/deep", "ics3u.school.ca")]
    [InlineData("  ics3u.school.ca  ", "ics3u.school.ca")]
    [InlineData("", "")]
    public void CustomDomainsAreNormalized(string raw, string expected) =>
        Assert.Equal(expected, CourseConfiguration.NormalizedCustomDomain(raw));

    // WINDOWS-HANDOFF.md entry 307: custom_domains.sections.sectionN moved
    // from a bare string to a map keyed by destination TYPE, since the mac
    // side can now deploy one section to more than one destination. Windows
    // has no multi-destination deploy UI yet, but must never read this map
    // as empty (a silent domain loss) or overwrite it with a bare string (an
    // actual clobber of a mac teacher's other-destination domains) just
    // because a Windows teacher opened and saved the course's settings.

    [Fact]
    public void ReadingAnOlderBareStringDomainAttributesItToThePrimaryDestinationOnly()
    {
        var config = FromJson("""
            {"course_code":"ICS3U","deploy_target":"netlify",
             "custom_domains":{"sections":{"section1":"ics3u.school.ca"}}}
            """);
        Assert.Equal("ics3u.school.ca", config.CustomDomain(1));
        Assert.Equal("ics3u.school.ca", config.CustomDomain(1, "netlify"));
        Assert.Equal("", config.CustomDomain(1, "cloudflare_pages"));
    }

    [Fact]
    public void ReadingTheNewPerDestinationMapNeverDegradesToEmpty()
    {
        var config = FromJson("""
            {"course_code":"ICS3U","deploy_target":"netlify",
             "custom_domains":{"sections":{"section1":
               {"netlify":"ics3u.school.ca","cloudflare_pages":"ics3u-mirror.school.ca"}}}}
            """);
        Assert.Equal("ics3u.school.ca", config.CustomDomain(1, "netlify"));
        Assert.Equal("ics3u-mirror.school.ca", config.CustomDomain(1, "cloudflare_pages"));
    }

    [Fact]
    public void SavingThePrimaryDestinationsDomainNeverClobbersOtherDestinationsAlreadyOnDisk()
    {
        // Simulates a mac-configured multi-destination course, opened and
        // saved on Windows without touching anything about the additional
        // destination — the exact scenario entry 307 flags as real data loss
        // if SetCustomDomain still wrote a bare string.
        var config = FromJson("""
            {"course_code":"ICS3U","deploy_target":"netlify",
             "custom_domains":{"sections":{"section1":
               {"netlify":"ics3u.school.ca","cloudflare_pages":"ics3u-mirror.school.ca"}}}}
            """);

        config.SetCustomDomain(1, "ics3u-new.school.ca");

        Assert.Equal("ics3u-new.school.ca", config.CustomDomain(1, "netlify"));
        Assert.Equal("ics3u-mirror.school.ca", config.CustomDomain(1, "cloudflare_pages"));
    }

    [Fact]
    public void SavingAnOlderBareStringDomainMigratesItIntoTheMapAttributedToThePrimary()
    {
        var config = FromJson("""
            {"course_code":"ICS3U","deploy_target":"netlify",
             "custom_domains":{"sections":{"section1":"ics3u.school.ca"}}}
            """);

        // Some future Windows UI setting the Cloudflare leg's own domain
        // must not discard the pre-existing bare-string Netlify domain.
        config.SetCustomDomain(1, "cloudflare_pages", "ics3u-mirror.school.ca");

        Assert.Equal("ics3u.school.ca", config.CustomDomain(1, "netlify"));
        Assert.Equal("ics3u-mirror.school.ca", config.CustomDomain(1, "cloudflare_pages"));
    }

    [Fact]
    public void ClearingADestinationsDomainRemovesOnlyThatEntry()
    {
        var config = FromJson("""
            {"course_code":"ICS3U","deploy_target":"netlify",
             "custom_domains":{"sections":{"section1":
               {"netlify":"ics3u.school.ca","cloudflare_pages":"ics3u-mirror.school.ca"}}}}
            """);

        config.SetCustomDomain(1, "");

        Assert.Equal("", config.CustomDomain(1, "netlify"));
        Assert.Equal("ics3u-mirror.school.ca", config.CustomDomain(1, "cloudflare_pages"));
    }

    [Fact]
    public void SavingWithNoExistingDomainStillOnlyTouchesThePrimaryDestination()
    {
        var config = FromJson("""{"course_code":"ICS3U","deploy_target":"netlify"}""");
        config.SetCustomDomain(1, "ics3u.school.ca");
        Assert.Equal("ics3u.school.ca", config.CustomDomain(1));
        Assert.Equal("", config.CustomDomain(1, "cloudflare_pages"));
    }

    [Fact]
    public void GradeWarningFiresOnlyWhenNameCarriesTheLabel()
    {
        Assert.NotNull(CourseConfiguration.GradeInTitleWarning("Computer Science, Grade 12, U", "ICS4U", true));
        Assert.Null(CourseConfiguration.GradeInTitleWarning("Computer Science", "ICS4U", true));
        Assert.Null(CourseConfiguration.GradeInTitleWarning("Computer Science, Grade 12, U", "ICS4U", false));
        Assert.Null(CourseConfiguration.GradeInTitleWarning("Coding Club Grade 12", "CODING", true));
        string warning = CourseConfiguration.GradeInTitleWarning("Grade 9 Science", "SNC1W", true)!;
        Assert.Contains("“Grade 9”", warning);
        Assert.Contains("Edit the name, or turn this off.", warning);
    }

    [Fact]
    public void DiscardChangesIsRevert()
    {
        var config = FromJson("""{"course_code":"X","course_name":"Original"}""");
        config.CourseName = "Changed";
        Assert.True(config.HasUnsavedChanges);
        config.DiscardChanges();
        Assert.Equal("Original", config.CourseName);
        Assert.False(config.HasUnsavedChanges);
    }

    [Fact]
    public void IsClubByCodeShape()
    {
        Assert.False(FromJson("""{"course_code":"ICS3U"}""").IsClub);
        Assert.True(FromJson("""{"course_code":"CODING"}""").IsClub);
        Assert.True(FromJson("""{"course_code":"ART"}""").IsClub);
    }

    [Fact]
    public void WriteRoundTripsThroughDisk()
    {
        string path = Path.Combine(Path.GetTempPath(), $"cfg-{Guid.NewGuid()}.json");
        try
        {
            var config = FromJson("""{"course_code":"X","course_name":"A"}""");
            config.CourseName = "B";
            config.Write(path);
            var reloaded = CourseConfiguration.Load(path);
            Assert.Equal("B", reloaded.CourseName);
            Assert.False(reloaded.HasUnsavedChanges);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void CurriculumCoverageAndNotesAccessorsAndRule()
    {
        var config = FromJson("""
        {
          "course_code": "ICS3U",
          "num_sections": 2,
          "section_numbers": [1, 2],
          "include_curriculum_coverage": { "sections": { "section1": true, "section2": false } },
          "include_coverage_notes": { "sections": { "section1": true, "section2": true } }
        }
        """);

        Assert.True(config.IncludesCurriculumCoverage(1));
        Assert.False(config.IncludesCurriculumCoverage(2));
        Assert.True(config.IncludesCoverageNotes(1));
        // Section 2 coverage is false, so notes must be false
        Assert.False(config.IncludesCoverageNotes(2));
        Assert.False(config.OverallIncludesCurriculumCoverage);

        // Disabling coverage disables notes
        config.SetIncludesCurriculumCoverage(1, false);
        Assert.False(config.IncludesCurriculumCoverage(1));
        Assert.False(config.IncludesCoverageNotes(1));

        // CoverageNotesEnabled pure function
        Assert.True(CourseConfiguration.CoverageNotesEnabled(true, true));
        Assert.False(CourseConfiguration.CoverageNotesEnabled(true, false));
        Assert.False(CourseConfiguration.CoverageNotesEnabled(false, true));
        Assert.False(CourseConfiguration.CoverageNotesEnabled(false, false));
    }
}

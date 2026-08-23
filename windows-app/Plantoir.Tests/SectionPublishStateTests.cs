using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Mirrors the mac's SectionPublishStateTests.swift — the " — Edited"
/// title-bar marker. Reads the same authored case list the mac suite runs,
/// from <c>contracts/app-rules.json</c> → <c>publishedFreshness</c>, so
/// both platforms are pinned against one specification rather than two
/// hand-typed copies of it. See "The ' — Edited' marker" in
/// WINDOWS-HANDOFF.md.
/// </summary>
public class SectionPublishStateTests
{
    private static string NewCourseDirectory()
    {
        string path = Directory.CreateTempSubdirectory("section-publish-state-tests").FullName;
        return path;
    }

    // ---- The marker's wording -----------------------------------------

    [Fact]
    public void Marker_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var cases = doc["publishedFreshness"]!["marker"]!["cases"]!.AsArray();

        foreach (var entry in cases)
        {
            // A case flagged "in a sentence naming the section" tests a
            // DIFFERENT rule — that sentences like "Deploying ICS3U-S1" use
            // the bare name and never call WindowTitle at all. Covered by
            // TitleText's own callers, not by this method.
            if (entry!["inASentenceNamingTheSection"]?.GetValue<bool>() == true) continue;

            string @base = entry["base"]!.ToString();
            bool hasEdits = entry["hasUnpublishedEdits"]!.GetValue<bool>();
            string expected = entry["expectTitle"]!.ToString();
            Assert.Equal(expected, SectionPublishState.WindowTitle(@base, hasEdits));
        }
    }

    [Fact]
    public void Marker_Suffix_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        string suffix = doc["publishedFreshness"]!["marker"]!["suffix"]!.ToString();
        Assert.Equal(SectionPublishState.WindowTitle("X", true), "X" + suffix);
    }

    // ---- Which files count ---------------------------------------------

    [Fact]
    public void FilesCounted_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var cases = doc["publishedFreshness"]!["filesCounted"]!["cases"]!.AsArray();

        foreach (var entry in cases)
        {
            string relativePath = entry!["path"]!.ToString().Replace('\\', '/');
            bool expectedCounts = entry["counts"]!.GetValue<bool>();

            // section1's own fingerprint is what every case in the contract
            // is written against.
            bool counts = SectionPublishState.CountsTowardFingerprint(relativePath, sectionNumber: 1);
            Assert.True(counts == expectedCounts, $"'{relativePath}' expected counts={expectedCounts}, got {counts}");
        }
    }

    [Fact]
    public void IsSectionFolderName_OnlyMatchesSectionPlusDigits()
    {
        Assert.True(SectionPublishState.IsSectionFolderName("section3"));
        Assert.True(SectionPublishState.IsSectionFolderName("section12"));
        Assert.False(SectionPublishState.IsSectionFolderName("sections"));
        Assert.False(SectionPublishState.IsSectionFolderName("section"));
        Assert.False(SectionPublishState.IsSectionFolderName("section3b"));
    }

    // ---- Self-publishing exclusion --------------------------------------

    [Fact]
    public void SelfPublishing_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("app-rules.json");
        var cases = doc["publishedFreshness"]!["selfPublishing"]!["cases"]!.AsArray();

        foreach (var entry in cases)
        {
            string courseDirectory = entry!["courseDirectory"]!.ToString();
            string destinationPath = entry["destinationPath"]!.ToString();
            string? expectExcluded = entry["expectExcluded"]?.GetValue<string?>();

            var destinations = new[] { new CourseConfiguration.DeployDestination("local_folder", destinationPath) };
            var excluded = SectionPublishState.SelfPublishingSubpaths(courseDirectory, destinations);

            if (expectExcluded is null)
                Assert.Empty(excluded);
            else
                Assert.Contains(expectExcluded, excluded);
        }
    }

    [Fact]
    public void SelfPublishing_ExclusionIsCaseInsensitive()
    {
        // NTFS is case-insensitive but case-preserving: a teacher's saved
        // destination path can differ in case from the folder's actual
        // on-disk name. Found by adversarial review — the mac's own
        // filesystem never raised the question, but this one does.
        var destinations = new[]
        {
            new CourseConfiguration.DeployDestination("local_folder", @"C:\w\courses\ICS3U\Site"),
        };
        var excluded = SectionPublishState.SelfPublishingSubpaths(@"C:\w\courses\ICS3U", destinations);
        Assert.True(SectionPublishState.IsExcluded("site", excluded));
        Assert.True(SectionPublishState.IsExcluded("site/index.html", excluded));
        Assert.True(SectionPublishState.IsExcluded("SITE/index.html", excluded));
    }

    // ---- End-to-end: on disk, with real files ---------------------------

    [Fact]
    public void NeverPublished_ShowsNoEdits()
    {
        string course = NewCourseDirectory();
        File.WriteAllText(Path.Combine(course, "course_config.json"), "{}");
        Assert.False(SectionPublishState.HasUnpublishedEdits(course, 1));
    }

    [Fact]
    public void UnchangedSincePublish_ShowsNoEdits()
    {
        string course = NewCourseDirectory();
        Directory.CreateDirectory(Path.Combine(course, "section1", "Classes"));
        File.WriteAllText(Path.Combine(course, "section1", "Classes", "Day 1.md"), "hello");

        string fingerprint = SectionPublishState.Fingerprint(course, 1);
        Assert.True(SectionPublishState.RecordPublish(course, 1, fingerprint, new[] { "netlify" }));

        Assert.False(SectionPublishState.HasUnpublishedEdits(course, 1));
    }

    [Fact]
    public void EditingAPageAfterPublish_ShowsEdits()
    {
        string course = NewCourseDirectory();
        string page = Path.Combine(course, "section1", "Classes", "Day 1.md");
        Directory.CreateDirectory(Path.GetDirectoryName(page)!);
        File.WriteAllText(page, "hello");

        string fingerprint = SectionPublishState.Fingerprint(course, 1);
        SectionPublishState.RecordPublish(course, 1, fingerprint, new[] { "netlify" });

        Thread.Sleep(20);
        File.WriteAllText(page, "hello, edited");
        Assert.True(SectionPublishState.HasUnpublishedEdits(course, 1));
    }

    [Fact]
    public void DeletingAPageAfterPublish_ShowsEdits()
    {
        string course = NewCourseDirectory();
        string page = Path.Combine(course, "section1", "Classes", "Day 1.md");
        Directory.CreateDirectory(Path.GetDirectoryName(page)!);
        File.WriteAllText(page, "hello");

        string fingerprint = SectionPublishState.Fingerprint(course, 1);
        SectionPublishState.RecordPublish(course, 1, fingerprint, new[] { "netlify" });

        File.Delete(page);
        Assert.True(SectionPublishState.HasUnpublishedEdits(course, 1));
    }

    [Fact]
    public void AnotherSectionsPageChanging_DoesNotShowEdits()
    {
        string course = NewCourseDirectory();
        string ownPage = Path.Combine(course, "section1", "Classes", "Day 1.md");
        string otherPage = Path.Combine(course, "section2", "Classes", "Day 1.md");
        Directory.CreateDirectory(Path.GetDirectoryName(ownPage)!);
        Directory.CreateDirectory(Path.GetDirectoryName(otherPage)!);
        File.WriteAllText(ownPage, "hello");
        File.WriteAllText(otherPage, "hello");

        string fingerprint = SectionPublishState.Fingerprint(course, 1);
        SectionPublishState.RecordPublish(course, 1, fingerprint, new[] { "netlify" });

        Thread.Sleep(20);
        File.WriteAllText(otherPage, "hello, edited");
        Assert.False(SectionPublishState.HasUnpublishedEdits(course, 1));
    }

    [Fact]
    public void SharedCourseLevelPageChanging_ShowsEditsForEverySection()
    {
        string course = NewCourseDirectory();
        string sharedPage = Path.Combine(course, "Unit 1", "Lesson.md");
        Directory.CreateDirectory(Path.GetDirectoryName(sharedPage)!);
        File.WriteAllText(sharedPage, "hello");

        string fp1 = SectionPublishState.Fingerprint(course, 1);
        string fp2 = SectionPublishState.Fingerprint(course, 2);
        SectionPublishState.RecordPublish(course, 1, fp1, new[] { "netlify" });
        SectionPublishState.RecordPublish(course, 2, fp2, new[] { "netlify" });

        Thread.Sleep(20);
        File.WriteAllText(sharedPage, "hello, edited");
        Assert.True(SectionPublishState.HasUnpublishedEdits(course, 1));
        Assert.True(SectionPublishState.HasUnpublishedEdits(course, 2));
    }

    [Fact]
    public void UnreadableStamp_ShowsNoEdits()
    {
        string course = NewCourseDirectory();
        Directory.CreateDirectory(Path.Combine(course, ".publish_state"));
        File.WriteAllText(SectionPublishState.StampPath(course, 1), "not json at all {{{");
        Assert.False(SectionPublishState.HasUnpublishedEdits(course, 1));
    }

    [Fact]
    public void StampFile_IsHiddenFromItsOwnFingerprint()
    {
        // Load-bearing: counted, every publish would end by declaring the
        // section edited.
        string course = NewCourseDirectory();
        Directory.CreateDirectory(Path.Combine(course, "section1"));
        File.WriteAllText(Path.Combine(course, "section1", "page.md"), "hello");

        string fingerprint = SectionPublishState.Fingerprint(course, 1);
        SectionPublishState.RecordPublish(course, 1, fingerprint, new[] { "netlify" });

        // Recomputing right after the stamp was written must still agree —
        // if .publish_state counted, this would immediately read as edited.
        Assert.False(SectionPublishState.HasUnpublishedEdits(course, 1));
    }

    [Fact]
    public void SymlinkedFolder_ContributesItsContents()
    {
        string course = NewCourseDirectory();
        string vault = Directory.CreateTempSubdirectory("section-publish-vault").FullName;
        File.WriteAllText(Path.Combine(vault, "diagram.png"), "pretend image bytes");

        string mediaLink = Path.Combine(course, "Media");
        try { Directory.CreateSymbolicLink(mediaLink, vault); }
        catch (IOException) { return; } // no privilege to create symlinks on this machine — skip rather than fail spuriously

        string fingerprint = SectionPublishState.Fingerprint(course, 1);
        SectionPublishState.RecordPublish(course, 1, fingerprint, new[] { "netlify" });
        Assert.False(SectionPublishState.HasUnpublishedEdits(course, 1));

        Thread.Sleep(20);
        File.WriteAllText(Path.Combine(vault, "diagram.png"), "pretend image bytes, edited");
        Assert.True(SectionPublishState.HasUnpublishedEdits(course, 1));
    }
}

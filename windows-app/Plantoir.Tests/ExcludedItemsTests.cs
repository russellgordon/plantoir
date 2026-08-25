using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// The <c>excluded_items</c> key: what a teacher's removal in Course Settings
/// records, and what the build then reads.
///
/// The shape is pinned by <c>contracts/file-formats.json</c> ->
/// <c>courseConfigKeys</c>; these are the behaviours that shape implies.
/// </summary>
public class ExcludedItemsTests
{
    private static CourseConfiguration Fresh(string json = """{"course_code": "ICS3U"}""") =>
        CourseConfiguration.FromDictionary(JObject.Parse(json));

    private static string Written(CourseConfiguration config) =>
        System.Text.Encoding.UTF8.GetString(config.SerializedBytes());

    /// <summary>
    /// ABSENT, not <c>{}</c>. A course nobody has excluded anything in must
    /// write the same file it always has — an empty object would appear in
    /// every course's config the first time anybody opened Settings.
    /// </summary>
    [Fact]
    public void NothingExcludedWritesNoKeyAtAll()
    {
        var config = Fresh();
        Assert.Empty(config.ExcludedItems(CourseConfiguration.SharedScope));
        Assert.DoesNotContain("excluded_items", Written(config));
    }

    [Fact]
    public void AnExclusionIsRecordedUnderItsScope()
    {
        var config = Fresh();
        config.Exclude(CourseConfiguration.SharedScope, "Discussions");

        Assert.Equal(new[] { "Discussions" }, config.ExcludedItems(CourseConfiguration.SharedScope));
        Assert.Empty(config.ExcludedItems(CourseConfiguration.PerSectionScope));

        var written = JObject.Parse(Written(config));
        Assert.Equal("Discussions", written["excluded_items"]!["shared"]![0]!.ToString());
        Assert.Null(written["excluded_items"]!["per_section"]);
    }

    /// <summary>
    /// The two scopes are matched by different scans in the build, and the
    /// same bare name can legitimately exist in both — which is the reason the
    /// key is an object rather than a flat list.
    /// </summary>
    [Fact]
    public void TheSameNameCanBeExcludedInOneScopeAndNotTheOther()
    {
        var config = Fresh();
        config.Exclude(CourseConfiguration.SharedScope, "Drafts");

        Assert.True(config.IsExcluded(CourseConfiguration.SharedScope, "Drafts"));
        Assert.False(config.IsExcluded(CourseConfiguration.PerSectionScope, "Drafts"));
    }

    [Fact]
    public void ExcludingTwiceRecordsItOnce()
    {
        var config = Fresh();
        config.Exclude(CourseConfiguration.SharedScope, "Discussions");
        config.Exclude(CourseConfiguration.SharedScope, "Discussions");

        Assert.Single(config.ExcludedItems(CourseConfiguration.SharedScope));
    }

    /// <summary>
    /// The answer is the point: an ordinary new folder is not a re-inclusion,
    /// and a trail line saying it was would be believed.
    /// </summary>
    [Fact]
    public void ReIncludingSaysWhetherItHadBeenExcluded()
    {
        var config = Fresh();
        config.Exclude(CourseConfiguration.SharedScope, "Discussions");

        Assert.True(config.ReInclude(CourseConfiguration.SharedScope, "Discussions"));
        Assert.False(config.ReInclude(CourseConfiguration.SharedScope, "Discussions"));
        Assert.False(config.ReInclude(CourseConfiguration.SharedScope, "SomethingBrandNew"));
    }

    /// <summary>
    /// The scope key goes when its last name goes, and the whole key goes when
    /// the last scope does — back to the file a course started with.
    /// </summary>
    [Fact]
    public void TheKeyDisappearsAgainWhenTheLastExclusionIsUndone()
    {
        var config = Fresh();
        config.Exclude(CourseConfiguration.SharedScope, "Discussions");
        config.Exclude(CourseConfiguration.PerSectionScope, "Drafts");

        config.ReInclude(CourseConfiguration.SharedScope, "Discussions");
        Assert.DoesNotContain("\"shared\"", Written(config));
        Assert.Contains("excluded_items", Written(config));

        config.ReInclude(CourseConfiguration.PerSectionScope, "Drafts");
        Assert.DoesNotContain("excluded_items", Written(config));
    }

    /// <summary>
    /// EXACT matching, case included, because
    /// <c>preflight_update_course_config</c> tests membership of a plain
    /// Python set. A case-insensitive answer here would have the app believe a
    /// folder is excluded while the build publishes it.
    /// </summary>
    [Fact]
    public void MatchingIsExactBecauseTheBuildsIs()
    {
        var config = Fresh();
        config.Exclude(CourseConfiguration.SharedScope, "Discussions");

        Assert.False(config.IsExcluded(CourseConfiguration.SharedScope, "discussions"));
        Assert.False(config.ReInclude(CourseConfiguration.SharedScope, "DISCUSSIONS"));
        Assert.True(config.IsExcluded(CourseConfiguration.SharedScope, "Discussions"));
    }

    [Fact]
    public void AnExistingKeyIsReadRatherThanReplaced()
    {
        var config = Fresh("""
            {"course_code": "ICS3U",
             "excluded_items": {"shared": ["Discussions"], "per_section": ["Drafts"]}}
            """);

        Assert.Equal(new[] { "Discussions" }, config.ExcludedItems(CourseConfiguration.SharedScope));
        Assert.Equal(new[] { "Drafts" }, config.ExcludedItems(CourseConfiguration.PerSectionScope));

        config.Exclude(CourseConfiguration.SharedScope, "Portfolios");
        Assert.Equal(new[] { "Discussions", "Portfolios" },
                     config.ExcludedItems(CourseConfiguration.SharedScope));
        Assert.Equal(new[] { "Drafts" }, config.ExcludedItems(CourseConfiguration.PerSectionScope));
    }

    /// <summary>
    /// The trail says "per-section"; the file says "per_section". Writing the
    /// file's spelling into a sentence is how machinery leaks in front of a
    /// teacher.
    /// </summary>
    [Fact]
    public void AScopeIsWrittenInWordsForTheTrailAndInKeysForTheFile()
    {
        Assert.Equal("shared", CourseConfiguration.ScopeInWords(CourseConfiguration.SharedScope));
        Assert.Equal("per-section", CourseConfiguration.ScopeInWords(CourseConfiguration.PerSectionScope));
        Assert.Equal("per_section", CourseConfiguration.PerSectionScope);
    }

    [Fact]
    public void AnEmptyNameIsNotAnExclusion()
    {
        var config = Fresh();
        config.Exclude(CourseConfiguration.SharedScope, "");
        Assert.DoesNotContain("excluded_items", Written(config));
        Assert.False(config.ReInclude(CourseConfiguration.SharedScope, ""));
    }
}

using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// Which folders the Marks checklist may OFFER — run from
/// <c>contracts/shared-rules.json</c> -&gt; <c>gradedFolders.choices</c>
/// against a real directory tree, because the rule is a walk and a walk over a
/// fixture is not a walk.
///
/// <para>The failure being guarded is silent and permanent: the build counts a
/// graded folder at any depth, an absent <c>graded_folders</c> key means the
/// historical rule still applies, and the FIRST TICK freezes the pool. So a
/// folder the checklist fails to offer stops counting for marks from that tick
/// onwards, and every expectation it addressed reads as never evaluated.</para>
/// </summary>
public class GradedFolderChoicesTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-graded-choices").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch (IOException) { }
    }

    private static JsonNode Choices =>
        ContractLoader.LoadJson("shared-rules.json")["gradedFolders"]!["choices"]!;

    private string MakeCourse(string name, IEnumerable<string> relativeDirectories)
    {
        string course = Path.Combine(_root, name);
        Directory.CreateDirectory(course);
        foreach (string relative in relativeDirectories)
            Directory.CreateDirectory(Path.Combine(course, relative.Replace('/', Path.DirectorySeparatorChar)));
        return course;
    }

    // ---- The contract's own cases ---------------------------------------

    [Fact]
    public void TheOfferedPoolMatchesTheContract()
    {
        var cases = Choices["cases"]!.AsArray();
        Assert.True(cases.Count >= 10,
            $"The contract lost graded-folder-choice cases: {cases.Count} present, 10 expected at least.");

        int index = 0;
        foreach (var testCase in cases)
        {
            string name = testCase!["name"]!.ToString();
            var shared = testCase["sharedFolders"]!.AsArray().Select(f => f!.ToString()).ToList();
            var perSection = testCase["perSectionFolders"]!.AsArray().Select(f => f!.ToString()).ToList();
            var directories = testCase["directories"]!.AsArray().Select(d => d!.ToString()).ToList();
            var expected = testCase["expect"]!.AsArray().Select(e => e!.ToString()).ToList();

            var values = new JObject
            {
                ["course_code"] = "ICS3U",
                ["shared_folders"] = new JArray(shared),
                ["per_section_folders"] = new JArray(perSection),
            };
            if (testCase["excludedItems"] is JsonObject excluded)
            {
                var map = new JObject();
                foreach (var scope in excluded)
                    map[scope.Key] = new JArray(scope.Value!.AsArray().Select(v => v!.ToString()));
                values["excluded_items"] = map;
            }
            var config = CourseConfiguration.FromDictionary(values);

            // A distinct folder per case: two cases both called "Tasks" must
            // not see each other's tree.
            string course = MakeCourse($"case{index++}", directories);

            Assert.Equal(expected, GradedFolderChoices.For(config, course));
        }
    }

    /// <summary>
    /// The acceptance test that the visible list alone would not have caught.
    ///
    /// <para>Before this change the checklist and the materialised pool were
    /// built from two DIFFERENT lists — the pool from the top-level folders
    /// alone. A test asserting only that "Tasks" appears in the offered list
    /// passed on the broken code, while the teacher's first tick still froze a
    /// pool without it.</para>
    ///
    /// <para><b>Be honest about what this can and cannot catch.</b> It would
    /// not have compiled against the old no-argument
    /// <c>MaterializedGradedFolders()</c> at all, and what it exercises is the
    /// rule — that materialising over the OFFERED list keeps a nested folder —
    /// rather than the view's wiring, where the bug actually lived. Nothing
    /// reachable from a unit test asserts that Course Settings passes the same
    /// list to both; making the parameter REQUIRED is what stands in for that,
    /// since the narrow pool can no longer be had by writing nothing.</para>
    /// </summary>
    [Fact]
    public void TheFrozenPoolIsMaterialisedFromTheSameListTheChecklistOffers()
    {
        var config = CourseConfiguration.FromDictionary(JObject.Parse("""
            {"course_code": "ICS3U",
             "shared_folders": ["Concepts", "Portfolios"],
             "per_section_folders": ["All Classes"]}
            """));
        string course = MakeCourse("nested", new[] { "Concepts", "Portfolios", "Portfolios/Tasks" });

        var offered = GradedFolderChoices.For(config, course);
        Assert.Contains("Tasks", offered);

        // The half that was broken: what the first tick actually freezes.
        Assert.Null(config.GradedFolders);
        Assert.Contains("Tasks", config.MaterializedGradedFolders(offered));
    }

    /// <summary>
    /// And the pool it freezes really does count that folder — the rule and
    /// the interface agreeing is the whole point, since each was already right
    /// on its own.
    /// </summary>
    [Fact]
    public void ATickedNestedFolderCountsForMarks()
    {
        var config = CourseConfiguration.FromDictionary(JObject.Parse("""
            {"course_code": "ICS3U", "shared_folders": ["Portfolios"]}
            """));
        string course = MakeCourse("counts", new[] { "Portfolios", "Portfolios/Tasks" });

        config.GradedFolders = config.MaterializedGradedFolders(GradedFolderChoices.For(config, course));

        Assert.True(config.CountsForMarks("Portfolios/Tasks/Culminating.md"));
        Assert.False(config.CountsForMarks("Concepts/Loops.md"));
    }

    // ---- The walk itself -------------------------------------------------

    [Fact]
    public void ACourseFolderThatIsNotThereOffersOnlyWhatTheCourseDeclares()
    {
        var config = CourseConfiguration.FromDictionary(JObject.Parse("""
            {"course_code": "ICS3U", "shared_folders": ["Tasks"]}
            """));

        Assert.Empty(GradedFolderChoices.NestedFolderNames(Path.Combine(_root, "not-there")));
        Assert.Empty(GradedFolderChoices.NestedFolderNames(null));
        Assert.Equal(new[] { "Tasks" }, GradedFolderChoices.For(config, Path.Combine(_root, "not-there")));
    }

    [Fact]
    public void FilesAreNotOfferedOnlyFolders()
    {
        string course = MakeCourse("files", new[] { "Tasks" });
        File.WriteAllText(Path.Combine(course, "Key Links.md"), "x");
        File.WriteAllText(Path.Combine(course, "Tasks", "Quiz.md"), "x");

        Assert.Equal(new[] { "Tasks" }, GradedFolderChoices.NestedFolderNames(course));
    }

    [Theory]
    [InlineData("section1", true)]
    [InlineData("section12", true)]
    [InlineData("SECTION3", true)]
    [InlineData("section", false)]
    [InlineData("sections", false)]
    [InlineData("section1a", false)]
    [InlineData("Sectional Tasks", false)]
    public void SectionFoldersAreRecognisedByNameAndNumberAlone(string name, bool expected) =>
        Assert.Equal(expected, GradedFolderChoices.IsSectionFolder(name));

    /// <summary>
    /// A folder marked hidden by the platform, rather than merely named with a
    /// dot. The mac skips both; so must this.
    /// </summary>
    [Fact]
    public void APlatformHiddenFolderIsNotOffered()
    {
        string course = MakeCourse("hidden", new[] { "Tasks", "Bookkeeping" });
        var bookkeeping = new DirectoryInfo(Path.Combine(course, "Bookkeeping"));
        bookkeeping.Attributes |= FileAttributes.Hidden;

        Assert.Equal(new[] { "Tasks" }, GradedFolderChoices.NestedFolderNames(course));
    }

    /// <summary>
    /// The depth cap is a number both apps must share, so it is asserted
    /// against the contract rather than against this file's own idea of it.
    /// </summary>
    [Fact]
    public void TheDepthCapIsTheOneTheContractNames() =>
        Assert.Equal(Choices["walk"]!["maxDepth"]!.GetValue<int>(), GradedFolderChoices.MaxDepth);

    [Fact]
    public void TheSkippedFoldersAreTheOnesTheContractNames() =>
        Assert.Equal(
            Choices["walk"]!["skipped"]!.AsArray().Select(s => s!.ToString()).OrderBy(s => s, StringComparer.Ordinal),
            GradedFolderChoices.SkippedFolders.OrderBy(s => s, StringComparer.Ordinal));

    /// <summary>
    /// The skip list is matched exactly, case included — a teacher's own
    /// folder called "media" is theirs, and is offered. (Only one of the two
    /// spellings can exist here: Windows' filesystem is case-insensitive, and
    /// the point is which spelling the SKIP LIST matches, not which the disk
    /// keeps.)
    /// </summary>
    [Fact]
    public void ATeachersOwnLowercaseMediaFolderIsStillOffered()
    {
        string course = MakeCourse("case-sensitive", new[] { "media" });

        Assert.Equal(new[] { "media" }, GradedFolderChoices.NestedFolderNames(course));
    }
}

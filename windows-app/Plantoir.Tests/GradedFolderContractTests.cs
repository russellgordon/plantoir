using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// Which folders count for marks, and which folder is the curriculum folder —
/// both run from <c>contracts/shared-rules.json</c> against this app's own
/// rules.
///
/// Nothing is retyped. Each case list carries a floor assertion so that a case
/// LOST from the contract fails here rather than quietly shrinking what is
/// tested, which is the failure the `ClassFolderContractTests` floors were
/// added for.
/// </summary>
public class GradedFolderContractTests
{
    private static JsonNode SharedRules => ContractLoader.LoadJson("shared-rules.json");

    // ---- graded_folders -------------------------------------------------

    [Fact]
    public void GradedFolderMatching_MatchesContract()
    {
        var cases = SharedRules["gradedFolders"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 10,
            $"The contract lost graded-folder cases: {cases.Count} present, 10 expected at least.");

        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            bool configured = c["configured"]!.GetValue<bool>();
            var graded = c["graded"]!.AsArray().Select(g => g!.ToString()).ToList();
            string path = c["path"]!.ToString();
            bool expected = c["expect"]!.GetValue<bool>();

            // "configured: false" is the ABSENT key, which is not an empty
            // list — that distinction is the whole migration.
            List<string>? pool = configured ? graded : null;

            Assert.Equal(expected, GradedFolderRule.CountsForMarks(pool, path));
        }
    }

    /// <summary>
    /// The same cases again, but driven through a real <c>course_config.json</c>
    /// so the ABSENT / EMPTY / explicit-null distinction is exercised on the
    /// JSON itself rather than on a nullable the test chose.
    /// </summary>
    [Fact]
    public void GradedFolderMatching_ThroughARealConfig()
    {
        foreach (var c in SharedRules["gradedFolders"]!["cases"]!.AsArray())
        {
            string name = c!["name"]!.ToString();
            bool configured = c["configured"]!.GetValue<bool>();
            var graded = c["graded"]!.AsArray().Select(g => g!.ToString()).ToList();
            string path = c["path"]!.ToString();
            bool expected = c["expect"]!.GetValue<bool>();

            var values = new JObject { ["course_code"] = "ICS3U" };
            if (configured) values["graded_folders"] = new JArray(graded);
            var config = CourseConfiguration.FromDictionary(values);

            Assert.Equal(expected, config.CountsForMarks(path));
        }
    }

    /// <summary>
    /// The case the contract calls out by name: an explicit JSON null is a
    /// CLEARED list, not an unset one. The key is PRESENT, and the absent case
    /// is reserved for a course that has never been asked.
    /// </summary>
    [Fact]
    public void AnExplicitNullIsAClearedListNotAnUnsetOne()
    {
        var config = CourseConfiguration.FromDictionary(
            JObject.Parse("""{"course_code": "ICS3U", "graded_folders": null}"""));

        Assert.NotNull(config.GradedFolders);
        Assert.Empty(config.GradedFolders!);
        Assert.False(config.CountsForMarks("Tasks/Culminating.md"));
    }

    [Fact]
    public void AnAbsentKeyIsNeverAskedAndKeepsTheHistoricalRule()
    {
        var config = CourseConfiguration.FromDictionary(
            JObject.Parse("""{"course_code": "ICS3U"}"""));

        Assert.Null(config.GradedFolders);
        Assert.True(config.CountsForMarks("Thinking Tasks/Problem 3.md"));
    }

    /// <summary>
    /// Absent stays absent on a save that did not touch marks: a course nobody
    /// has asked must write the same file it always has.
    /// </summary>
    [Fact]
    public void AnAbsentKeySurvivesARoundTrip()
    {
        var config = CourseConfiguration.FromDictionary(
            JObject.Parse("""{"course_code": "ICS3U", "course_name": "Intro"}"""));
        config.CourseName = "Introduction";

        string written = System.Text.Encoding.UTF8.GetString(config.SerializedBytes());
        Assert.DoesNotContain("graded_folders", written);
    }

    [Fact]
    public void AClearedListIsWrittenAsAnEmptyArray()
    {
        var config = CourseConfiguration.FromDictionary(JObject.Parse("""{"course_code": "ICS3U"}"""));
        config.GradedFolders = new List<string>();

        string written = System.Text.Encoding.UTF8.GetString(config.SerializedBytes());
        Assert.Contains("\"graded_folders\": []", written);
    }

    /// <summary>
    /// Materialising a never-asked course's pool gives back what it was
    /// ALREADY working to — not an empty list. A teacher's first tick must not
    /// silently take the marks off every other folder that mentioned tasks.
    /// </summary>
    [Fact]
    public void MaterialisingANeverAskedPoolKeepsWhatTheCourseAlreadyCounted()
    {
        var config = CourseConfiguration.FromDictionary(JObject.Parse("""
            {"course_code": "ICS3U",
             "shared_folders": ["Concepts", "Tasks", "Thinking Tasks"],
             "per_section_folders": ["All Classes"]}
            """));

        Assert.Null(config.GradedFolders);
        Assert.Equal(new[] { "Tasks", "Thinking Tasks" }, config.MaterializedGradedFolders());
    }

    [Fact]
    public void MaterialisingAnAnsweredPoolReturnsTheAnswer()
    {
        var config = CourseConfiguration.FromDictionary(JObject.Parse("""
            {"course_code": "ICS3U",
             "shared_folders": ["Concepts", "Tasks", "Thinking Tasks"],
             "graded_folders": ["Tasks"]}
            """));

        Assert.Equal(new[] { "Tasks" }, config.MaterializedGradedFolders());
    }

    /// <summary>
    /// Reconciliation is the wizard's half of
    /// <c>setup_course.py:graded_folders_for</c> — a declared name the teacher
    /// removed while setting the course up is dropped rather than written into
    /// a pool matching nothing on disk.
    /// </summary>
    [Fact]
    public void ADeclaredPoolIsNarrowedToTheFoldersTheCourseActuallyHas()
    {
        var reconciled = GradedFolderRule.Reconciled(
            new[] { "Tasks", "Portfolios" },
            new[] { "Concepts", "Portfolios", "All Classes" });

        Assert.Equal(new[] { "Portfolios" }, reconciled);
    }

    [Fact]
    public void ReconciliationKeepsTheCoursesOwnCapitalisation()
    {
        var reconciled = GradedFolderRule.Reconciled(
            new[] { "tasks" },
            new[] { "Tasks" });

        Assert.Equal(new[] { "Tasks" }, reconciled);
    }

    [Fact]
    public void ReconciliationOfNothingIsAnEmptyPoolNotAnAbsentOne()
    {
        Assert.Empty(GradedFolderRule.Reconciled(new[] { "Tasks" }, new[] { "Concepts" }));
    }

    /// <summary>
    /// A page at the root of the course counts for nothing, in either mode.
    ///
    /// <para>Written because the contract's own "the file name never counts"
    /// case cannot catch a rule that forgot to drop the file name: its path is
    /// <c>Concepts/Tasks.md</c>, and "Tasks.md" does not EQUAL "Tasks", so the
    /// answer comes out right for the wrong reason. A root-level
    /// <c>Tasks.md</c> under the historical SUBSTRING rule is the case where
    /// the two differ — it contains "task", so a rule including the file name
    /// would count it. Found by deliberately breaking the rule and watching
    /// the contract cases all still pass.</para>
    /// </summary>
    [Fact]
    public void APageAtTheRootIsNeverAssessedWorkOnAccountOfItsName()
    {
        Assert.False(GradedFolderRule.CountsForMarks(null, "Tasks.md"));
        Assert.False(GradedFolderRule.CountsForMarks(new[] { "Tasks" }, "Tasks"));
        Assert.False(GradedFolderRule.CountsForMarks(new[] { "Tasks" }, "Tasks.md"));

        // ...and the folder above it still does, so the guard has not simply
        // turned the rule off.
        Assert.True(GradedFolderRule.CountsForMarks(null, "Tasks/Anything.md"));
    }

    // ---- The curriculum folder -----------------------------------------

    [Fact]
    public void CurriculumFolderResolution_MatchesContract()
    {
        var resolution = SharedRules["specialNames"]!["curriculumFolderResolution"]!;
        var cases = resolution["cases"]!.AsArray();
        Assert.True(cases.Count >= 5,
            $"The contract lost curriculum-resolution cases: {cases.Count} present, 5 expected at least.");

        foreach (var c in cases)
        {
            string? configured = c!["configured"] is null || c["configured"] is JsonValue v && v.ToJsonString() == "null"
                ? null : c["configured"]!.ToString();
            var folders = c["folders"]!.AsArray().Select(f => f!.ToString()).ToList();
            string? expected = c["resolved"] is null ? null : c["resolved"]!.ToString();
            string why = c["why"]!.ToString();

            Assert.Equal(expected, CurriculumFolderRule.Resolve(configured, folders));
        }
    }

    /// <summary>
    /// A configured name the course no longer has must not be protected: the
    /// resolver falls back to the scan, exactly as the build's does.
    /// </summary>
    [Fact]
    public void AConfiguredNameThatIsGoneFallsBackToTheScan()
    {
        Assert.Equal("Ontario Curriculum",
            CurriculumFolderRule.Resolve("Expectations",
                new[] { "Concepts", "Ontario Curriculum", "Tasks" }));
    }

    [Fact]
    public void ACourseWithNoCurriculumFolderResolvesToNothing()
    {
        Assert.Null(CurriculumFolderRule.Resolve(null, new[] { "Concepts", "Tasks" }));
        Assert.Null(CurriculumFolderRule.Resolve("", Array.Empty<string>()));
        Assert.Null(CurriculumFolderRule.Resolve(null, null));
    }

    /// <summary>Case-insensitive on the marker, alphabetical on the answer.</summary>
    [Fact]
    public void TheScanIgnoresCaseAndTakesTheAlphabeticallyFirst()
    {
        Assert.Equal("AP CURRICULUM",
            CurriculumFolderRule.Resolve(null, new[] { "Ontario Curriculum", "AP CURRICULUM" }));
    }

    [Fact]
    public void TheConfigResolvesItsOwnCurriculumFolder()
    {
        var config = CourseConfiguration.FromDictionary(JObject.Parse("""
            {"course_code": "ICS3U",
             "curriculum_folder": "Ontario Curriculum",
             "shared_folders": ["Concepts", "Ontario Curriculum", "Tasks"]}
            """));

        Assert.Equal("Ontario Curriculum", config.ResolvedCurriculumFolder);
    }
}

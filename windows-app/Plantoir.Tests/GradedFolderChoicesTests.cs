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
        // Broad on purpose: this is temp-folder cleanup, and one case leaves a
        // junction behind, which recursive delete can refuse for reasons that
        // have nothing to do with the rule under test. A failure to tidy must
        // not be reported as a failure of the suite.
        try { Directory.Delete(_root, recursive: true); } catch (Exception) { }
    }

    private static JsonNode Choices =>
        ContractLoader.LoadJson("shared-rules.json")["gradedFolders"]!["choices"]!;

    private static JsonNode RemovingAFolder =>
        ContractLoader.LoadJson("shared-rules.json")["gradedFolders"]!["removingAFolder"]!;

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
        Assert.True(cases.Count >= 14,
            $"The contract lost graded-folder-choice cases: {cases.Count} present, 14 expected at least.");

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
    /// What a REMOVAL does to the marks pool — run from
    /// <c>gradedFolders.removingAFolder</c>, six cases, against a real tree.
    ///
    /// <para>The whole gesture is played through one Core call
    /// (<see cref="FolderRemoval.RemoveFolderFromCourse"/>) because the ORDER
    /// is the rule: the copy list and <c>excluded_items</c> are written, and
    /// only THEN is the course walked to ask what the checklist still offers. A
    /// test that called a pure pool function while the order lived in the view
    /// would pin nothing — the mac fell into exactly that trap, its own removal
    /// test passing for two days because it left the exclusion out.</para>
    ///
    /// <para>Mutation-tested 2026-09-18, since a contract-driven test is worth
    /// what it FAILS on. The whole pre-fix Windows body — a walk taken before
    /// the exclusion, materialised over, then <c>RemoveAll</c> — turns cases 1,
    /// 2, 5 and 6 red, the four the issue says fail there. Each half on its
    /// own: the old pool semantics over a CORRECT walk turn 5 and 6 red;
    /// reordering the walk before the exclusion, or leaving the exclusion out
    /// altogether, turns 3 and 4 red. (Those last two are one finding twice
    /// over: both leave the removed name among the choices.)</para>
    /// </summary>
    [Fact]
    public void WhatARemovalDoesToTheMarksPoolMatchesTheContract()
    {
        var cases = RemovingAFolder["cases"]!.AsArray();
        Assert.True(cases.Count >= 6,
            $"The contract lost removal cases: {cases.Count} present, 6 expected at least.");

        // Every case is played, and the ones that fail are reported TOGETHER.
        // A loop that stops at the first failure says "case 5 is wrong" where
        // what a mutation has to prove is WHICH cases it turns red — the
        // evidence that this list pins the rule rather than one accident of it.
        var failures = new List<string>();

        int index = 0;
        foreach (var testCase in cases)
        {
            int caseNumber = index + 1;
            string name = testCase!["name"]!.ToString();
            var shared = testCase["sharedFolders"]!.AsArray().Select(f => f!.ToString()).ToList();
            var perSection = testCase["perSectionFolders"]!.AsArray().Select(f => f!.ToString()).ToList();
            var directories = testCase["directories"]!.AsArray().Select(d => d!.ToString()).ToList();

            var values = new JObject
            {
                ["course_code"] = "ICS3U",
                ["shared_folders"] = new JArray(shared),
                ["per_section_folders"] = new JArray(perSection),
            };
            // An ARRAY is a course that HAS been asked. A JSON null is a course
            // that never was, which is the key ABSENT — writing it as a present
            // null would say the opposite, because a present null reads as a
            // CLEARED list.
            if (testCase["graded"] is JsonArray graded)
                values["graded_folders"] = new JArray(graded.Select(g => g!.ToString()));

            var config = CourseConfiguration.FromDictionary(values);
            string course = MakeCourse($"removal{index++}", directories);

            FolderRemoval.RemoveFolderFromCourse(config, course,
                testCase["remove"]!["scope"]!.ToString(),
                testCase["remove"]!["name"]!.ToString());

            bool expectAsked = testCase["expectGraded"] is JsonArray;
            try
            {
                // Named, because this is the half that fails silently in the
                // product: "asked" and "never asked" are both plausible-looking
                // configurations and only one of them keeps the marks.
                Assert.True(expectAsked == (config.GradedFolders is not null),
                    $"expected the course to be {(expectAsked ? "ASKED" : "NEVER ASKED")} after the removal.");

                if (expectAsked)
                {
                    Assert.Equal(
                        testCase["expectGraded"]!.AsArray().Select(e => e!.ToString()).ToList(),
                        config.GradedFolders);
                }
                else
                {
                    // Read back from what would be WRITTEN, so "absent" is
                    // proved rather than inferred from a null the setter could
                    // have produced either way.
                    Assert.DoesNotContain("graded_folders",
                        System.Text.Encoding.UTF8.GetString(config.SerializedBytes()));
                }
            }
            catch (Xunit.Sdk.XunitException problem)
            {
                failures.Add($"case {caseNumber} “{name}”: {problem.Message}");
            }
        }

        Assert.True(failures.Count == 0, string.Join("\n\n", failures));
    }

    /// <summary>
    /// Windows-only, and deliberately not a contract case: the contract leaves
    /// matching CASE unpinned, because the mac compares pool names exactly
    /// while this app has always dropped them with
    /// <c>OrdinalIgnoreCase</c>. What is pinned HERE is that the two halves of
    /// the rule agree with each other.
    ///
    /// <para>The walk returns names as they are spelled on disk. Remove a
    /// top-level <c>Tasks</c> while <c>Portfolios/tasks</c> survives and the
    /// checklist offers <c>tasks</c> — so an EXACT "still offered" test would
    /// answer "no longer offered", the case-insensitive drop would take
    /// <c>Tasks</c> out of the pool anyway, and <c>build_site.py</c> — which
    /// lowercases both sides — would go on counting that folder. Marks off the
    /// coverage map because of a capital letter. Proposed to the mac as a
    /// contract case by issue #163.</para>
    /// </summary>
    [Fact]
    public void ANameStillOfferedInANOTHERCasingKeepsItsPlaceInThePool()
    {
        var config = CourseConfiguration.FromDictionary(JObject.Parse("""
            {"course_code": "ICS3U",
             "shared_folders": ["Concepts", "Tasks", "Portfolios"],
             "graded_folders": ["Tasks"]}
            """));
        string course = MakeCourse("casing",
            new[] { "Concepts", "Tasks", "Portfolios", "Portfolios/tasks" });

        FolderRemoval.RemoveFolderFromCourse(config, course, CourseConfiguration.SharedScope, "Tasks");

        Assert.Equal(new[] { "Tasks" }, config.GradedFolders);
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
    /// A junction is not walked into.
    ///
    /// <para>Windows-only, and it belongs here rather than in the contract,
    /// which has no notion of a link. It pins the one line most likely to be
    /// "simplified" later: the walk tests for a real LINK TARGET rather than
    /// for the reparse-point attribute alone, because a sync provider's
    /// unmaterialised placeholders carry that attribute too and skipping them
    /// would put a cloud-synced course back on the top-level-only list. A
    /// junction needs no privilege to make, which is why it is a junction and
    /// not a symbolic link.</para>
    /// </summary>
    [Fact]
    public void AJunctionIsNotWalkedInto()
    {
        string course = MakeCourse("junction", new[] { "Tasks" });
        string away = Path.Combine(_root, "elsewhere");
        Directory.CreateDirectory(Path.Combine(away, "Linked Tasks"));

        var mklink = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(
            "cmd.exe", $"/c mklink /J \"{Path.Combine(course, "Shortcut")}\" \"{away}\"")
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true });
        mklink!.WaitForExit();
        // Nothing to assert on a machine that would not make one; saying so
        // beats a test that fails for a reason unrelated to the rule.
        if (mklink.ExitCode != 0) return;

        List<string> offered;
        try
        {
            offered = GradedFolderChoices.NestedFolderNames(course);
        }
        finally
        {
            // Unlink before the class tears its temp folder down, so nothing
            // walks through it on the way out.
            try { Directory.Delete(Path.Combine(course, "Shortcut")); } catch (Exception) { }
        }

        Assert.Equal(new[] { "Tasks" }, offered);
        Assert.DoesNotContain("Shortcut", offered);
        Assert.DoesNotContain("Linked Tasks", offered);
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

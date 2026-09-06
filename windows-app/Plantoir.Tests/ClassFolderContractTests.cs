using System.Text.Json.Nodes;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// The class-folder rule, run against the SHARED contract.
///
/// <para>The cases are deserialised from <c>contracts/class-planning.json</c> →
/// <c>classFolder</c>, never retyped — the same data the macOS suite and
/// <c>scripts/test_class_folder.py</c> run against their own implementations.
/// That is the point: this rule used to exist four times and disagree, and this
/// app's copy was the one that tested the whole directory string, so a teacher
/// whose working folder was <c>C:\Users\x\Classroom\</c> made every page in
/// every course a class page.</para>
/// </summary>
public class ClassFolderContractTests
{
    [Fact]
    public void ClassFolderNaming_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["classFolder"]!["naming"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 5, "the contract lost naming cases");

        foreach (var c in cases)
        {
            if (c is null) continue;
            var folders = c["perSectionFolders"]!.AsArray().Select(x => x!.ToString()).ToList();
            string expected = c["expect"]!.ToString();
            string name = c["name"]?.ToString() ?? "unnamed";
            // A case WITHOUT `classFolder` is a course that never recorded
            // one, so it is read with a default rather than treated as a new
            // shape — the same trap as pageNaming's `term`.
            string? recorded = c["classFolder"]?.ToString();

            Assert.True(ClassFolderRule.Name(recorded, folders) == expected,
                $"{name}: expected '{expected}', got '{ClassFolderRule.Name(recorded, folders)}'");
        }
    }

    [Fact]
    public void ClassFolderMembership_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["classFolder"]!["membership"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 4, "the contract lost membership cases");

        foreach (var c in cases)
        {
            if (c is null) continue;
            var folders = c["perSectionFolders"]!.AsArray().Select(x => x!.ToString()).ToList();
            var expected = c["expect"]!.AsArray().Select(x => x!.ToString()).ToList();
            string name = c["name"]?.ToString() ?? "unnamed";
            string? recorded = c["classFolder"]?.ToString();

            Assert.True(ClassFolderRule.Names(recorded, folders).SequenceEqual(expected),
                $"{name}: expected [{string.Join(", ", expected)}], got " +
                $"[{string.Join(", ", ClassFolderRule.Names(recorded, folders))}]");
        }
    }

    [Fact]
    public void IsClassPage_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["classFolder"]!["isClassPage"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 12, "the contract lost isClassPage cases");

        foreach (var c in cases)
        {
            if (c is null) continue;
            string path = c["path"]!.ToString();
            var folders = c["classFolders"]!.AsArray().Select(x => x!.ToString()).ToList();
            bool expected = c["expect"]!.GetValue<bool>();
            string name = c["name"]?.ToString() ?? "unnamed";

            Assert.True(ClassFolderRule.IsClassPage(path, folders) == expected,
                $"{name}: {path} against [{string.Join(", ", folders)}] should be {expected}");
        }
    }

    /// <summary>
    /// Defence in depth, and labelled as such: under segment EQUALITY these
    /// could not match anyway. The test exists so a future change to prefix or
    /// substring matching fails here rather than quietly reclassifying content
    /// that ships in the example payloads.
    /// </summary>
    [Fact]
    public void APageIsNeverALessonBecauseOfItsName()
    {
        var folders = new[] { "All Classes" };
        foreach (var page in new[]
                 {
                     "Setup/How This Class Works.md",
                     "Setup/Our Classroom Norms.md",
                     "Curriculum/B3. Connections Beyond the Classroom.md",
                     "All Classes.md",
                 })
        {
            Assert.False(ClassFolderRule.IsClassPage(page, folders), page);
        }
    }

    /// <summary>
    /// The regression that matters most on THIS platform: Plan() used to test
    /// the whole ABSOLUTE directory string, so a working folder called
    /// C:\Users\x\Classroom made every page in every course a class page.
    /// The rule is a pure segment matcher, so what protects it is Plan()
    /// passing Relative(pagePath) — asserted here as the shape the rule expects.
    /// </summary>
    [Fact]
    public void OnlyARelativePathIsEverAskedAbout()
    {
        var folders = new[] { "All Classes" };
        Assert.False(ClassFolderRule.IsClassPage(@"Concepts\Loops.md", folders));
        Assert.True(ClassFolderRule.IsClassPage(@"All Classes\Unit 1, Day 1.md", folders));
        // A page whose ancestors mention classes, once made relative, is not a
        // lesson — which is the whole point of passing Relative(pagePath).
        Assert.False(ClassFolderRule.IsClassPage(@"Concepts\Recursion.md", folders));
    }

    [Fact]
    public void ANullFolderEntryDoesNotThrow()
    {
        // These lists come from JSON, including the contract's own case data.
        Assert.Equal("All Classes", ClassFolderRule.Name(new string?[] { null }!));
        Assert.False(ClassFolderRule.IsClassPage("All Classes/x.md", new string?[] { null }!));
    }
}

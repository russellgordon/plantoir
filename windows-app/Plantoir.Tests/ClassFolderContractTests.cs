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

            Assert.True(ClassFolderRule.Name(folders) == expected,
                $"{name}: expected '{expected}', got '{ClassFolderRule.Name(folders)}'");
        }
    }

    [Fact]
    public void IsClassPage_MatchesContract()
    {
        var doc = ContractLoader.LoadJson("class-planning.json");
        var cases = doc["classFolder"]!["isClassPage"]!["cases"]!.AsArray();
        Assert.True(cases.Count >= 9, "the contract lost isClassPage cases");

        foreach (var c in cases)
        {
            if (c is null) continue;
            string path = c["path"]!.ToString();
            string folder = c["classFolder"]!.ToString();
            bool expected = c["expect"]!.GetValue<bool>();
            string name = c["name"]?.ToString() ?? "unnamed";

            Assert.True(ClassFolderRule.IsClassPage(path, folder) == expected,
                $"{name}: {path} against '{folder}' should be {expected}");
        }
    }

    /// <summary>
    /// The two bugs the rule was written to close, asserted directly as well as
    /// through the case list — so deleting a contract case cannot quietly
    /// delete the protection with it.
    /// </summary>
    [Fact]
    public void AShippedPageNamedForAClassIsNotALesson()
    {
        foreach (var page in new[]
                 {
                     "Setup/How This Class Works.md",
                     "Setup/Our Classroom Norms.md",
                     "Curriculum/B3. Connections Beyond the Classroom.md",
                 })
        {
            Assert.False(ClassFolderRule.IsClassPage(page, "All Classes"), page);
        }
    }

    [Fact]
    public void AWorkingFolderNamedClassroomCannotMakeEveryPageALesson()
    {
        // The path handed to the rule is RELATIVE, which is what makes the
        // teacher's own filing unable to reach it. This is the regression that
        // matters most on this platform.
        Assert.False(ClassFolderRule.IsClassPage(@"Concepts\Loops.md", "All Classes"));
        Assert.True(ClassFolderRule.IsClassPage(@"All Classes\Unit 1, Day 1.md", "All Classes"));
    }
}

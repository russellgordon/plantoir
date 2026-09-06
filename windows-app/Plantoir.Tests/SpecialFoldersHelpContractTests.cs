using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The "Folders Plantoir uses" sheet, driven from
/// <c>contracts/shared-rules.json</c> → <c>specialFoldersHelp</c> rather than
/// retyped here.
///
/// <para>Two properties matter and neither is obvious from reading the view:
/// it must name the folders THIS course has rather than the rule that finds
/// them, and it must not describe the machinery. Both are contract keys, so a
/// change to the rule fails a test on BOTH platforms instead of drifting on
/// one.</para>
/// </summary>
public class SpecialFoldersHelpContractTests
{
    private static JsonNode Contract() =>
        ContractLoader.LoadJson("shared-rules.json")["specialFoldersHelp"]!;

    /// <summary>
    /// A course built from the case's own inputs. `graded_folders` is written
    /// only when the case gives one, because an ABSENT key and an EMPTY list
    /// mean different things — see <c>gradedFolders.absentIsNotEmpty</c>, and
    /// the two cases here that turn on exactly that.
    /// </summary>
    private static CourseConfiguration CourseFrom(JsonNode figure)
    {
        var json = new JsonObject
        {
            ["course_code"] = "ICS3U",
            ["course_name"] = "Introduction to Computer Science",
            ["per_section_folders"] = figure["perSectionFolders"]!.DeepClone(),
            ["shared_folders"] = figure["sharedFolders"]!.DeepClone(),
        };
        // A JSON null reads back as a null node, so "never asked" simply does
        // not write the key — which is the distinction the two cases below
        // turn on, and the one a `?? new JsonArray()` would quietly erase.
        if (figure["gradedFolders"] is JsonArray graded)
            json["graded_folders"] = graded.DeepClone();
        if (figure["curriculumFolder"] is JsonValue curriculum)
            json["curriculum_folder"] = curriculum.DeepClone();

        return CourseConfiguration.FromBytes(Encoding.UTF8.GetBytes(json.ToJsonString()));
    }

    private static string NameOfRow(CourseConfiguration config, string key) => key switch
    {
        "lessons" => SpecialFoldersHelp.Entries(config)[0].Name,
        "curriculum" => SpecialFoldersHelp.Entries(config)[1].Name,
        "graded" => SpecialFoldersHelp.Entries(config)[2].Name,
        _ => throw new Xunit.Sdk.XunitException($"the contract names a row this test cannot read: {key}"),
    };

    [Fact]
    public void TheSheetNamesEachCoursesOwnFolders()
    {
        foreach (JsonNode? node in Contract()["cases"]!.AsArray())
        {
            JsonNode figure = node!;
            string name = figure["name"]!.ToString();
            CourseConfiguration config = CourseFrom(figure);

            foreach (var expected in figure["expectNames"]!.AsObject())
            {
                string actual = NameOfRow(config, expected.Key);
                Assert.True(expected.Value!.ToString() == actual,
                    $"case \"{name}\", row \"{expected.Key}\": "
                    + $"expected \"{expected.Value}\", got \"{actual}\"");
            }

            if (figure["mustNotAppear"] is JsonArray banned)
            {
                var shown = new StringBuilder();
                foreach (var entry in SpecialFoldersHelp.Entries(config))
                    shown.Append(entry.Name).Append(' ');
                foreach (JsonNode? word in banned)
                    Assert.DoesNotContain(word!.ToString(), shown.ToString());
            }
        }
    }

    [Fact]
    public void TheRowsAreTheContractsRowsInTheContractsOrder()
    {
        var config = CourseConfiguration.FromBytes(Encoding.UTF8.GetBytes(
            """{"course_code":"ICS3U","per_section_folders":["All Classes"],"shared_folders":["Tasks","Ontario Curriculum"]}"""));

        var rows = Contract()["rows"]!.AsArray();
        var entries = SpecialFoldersHelp.Entries(config);

        Assert.Equal(rows.Count, entries.Count);
        for (int i = 0; i < rows.Count; i++)
        {
            JsonNode row = rows[i]!;
            Assert.Equal(row["what"]!.ToString(), entries[i].What);
            Assert.Equal(row["why"]!.ToString(), entries[i].Why);

            // A fixed row's name is the contract's; a course-named row's is
            // not, and asserting it here would only restate the cases above.
            if (row["namedFrom"]!.ToString() == "fixed")
                Assert.Equal(row["name"]!.ToString(), entries[i].Name);
        }
    }

    [Fact]
    public void TheTitleAndIntroAreTheContractsOwn()
    {
        Assert.Equal(Contract()["title"]!.ToString(), SpecialFoldersHelp.Title);
        Assert.Equal(Contract()["intro"]!.ToString(), SpecialFoldersHelp.Intro);
        Assert.Equal(
            Contract()["rows"]!.AsArray()[1]!["placeholderWhenNone"]!.ToString(),
            SpecialFoldersHelp.NoCurriculumFolderYet);
    }

    [Fact]
    public void SeveralFoldersAreListedTheWayAPersonWouldSayThem()
    {
        foreach (JsonNode? node in Contract()["listing"]!["cases"]!.AsArray())
        {
            var names = new List<string>();
            foreach (JsonNode? n in node!["names"]!.AsArray()) names.Add(n!.ToString());

            Assert.Equal(node["expect"]!.ToString(), SpecialFoldersHelp.Listed(names));
        }

        Assert.Equal(SpecialFoldersHelp.NoneChosen, SpecialFoldersHelp.Listed(null));
    }

    /// <summary>
    /// Rule 1, plus the reason the sheet names configured folders at all: the
    /// banned list carries "substring", "segment" and "case-insensitive"
    /// alongside "container", because publishing the matching rule in words is
    /// the same mistake as printing it in a row, by another route.
    /// </summary>
    [Fact]
    public void TheSheetNamesNoMachineryAndPublishesNoMatchingRule()
    {
        var config = CourseConfiguration.FromBytes(Encoding.UTF8.GetBytes(
            """{"course_code":"ICS3U","per_section_folders":["All Classes"],"shared_folders":["Concepts","Tasks","Ontario Curriculum"]}"""));

        var shown = new StringBuilder(SpecialFoldersHelp.Title).Append(' ').Append(SpecialFoldersHelp.Intro);
        foreach (var entry in SpecialFoldersHelp.Entries(config))
            shown.Append(' ').Append(entry.Name).Append(' ').Append(entry.What).Append(' ').Append(entry.Why);
        string text = shown.ToString().ToLowerInvariant();

        foreach (JsonNode? word in Contract()["saysNoMachinery"]!["jargon"]!.AsArray())
            Assert.False(text.Contains(word!.ToString().ToLowerInvariant()),
                $"the folders help says \"{word}\" to a teacher");
    }
}

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

    /// <summary>
    /// The row a case is talking about, found by the contract's own `key`
    /// rather than by a position typed in here. Hard-coded indices would go on
    /// passing after a row was inserted above them, testing the wrong row and
    /// saying nothing — which is the failure this whole file exists to catch.
    /// </summary>
    private static string NameOfRow(CourseConfiguration config, string key)
    {
        var rows = Contract()["rows"]!.AsArray();
        for (int i = 0; i < rows.Count; i++)
            if (rows[i]!["key"]!.ToString() == key)
                return SpecialFoldersHelp.Entries(config)[i].Name;

        throw new Xunit.Sdk.XunitException($"a case names a row the contract does not list: {key}");
    }

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

    /// <summary>
    /// Every row's explanation, in the contract's order — for every course the
    /// contract lists, rather than for one hand-typed fixture. The sentences a
    /// teacher reads are the contract's, character for character.
    ///
    /// <para><b>The single fixture this used to build had a curriculum folder,
    /// and that is the hole the retired second sentence lived in.</b> The
    /// curriculum row says the same thing whichever name it carries, but
    /// nothing pinned the PLACEHOLDER branch's copy of it. The mac measured
    /// exactly that on 2026-09-06: putting the old sentence back — "One page
    /// per expectation, in a folder whose name mentions the curriculum", which
    /// publishes the matching rule in plain words — left all five folders-help
    /// tests green, and the jargon sweep below runs that branch and still
    /// cannot see it, because "mentions" is not a banned word. Banning it is
    /// not the fix either: a banned word catches only that word, and "named
    /// after the curriculum" says the same thing in different ones. Pinning
    /// the sentence catches any wording. See item 40 in
    /// <c>WINDOWS-HANDOFF.md</c>.</para>
    ///
    /// <para>Running the contract's own cases closes it without inventing a
    /// second fixture to drift: two of them end up with no curriculum folder
    /// at all, so both branches are now compared with the contract.</para>
    /// </summary>
    [Fact]
    public void TheRowsAreTheContractsRowsInTheContractsOrder()
    {
        var rows = Contract()["rows"]!.AsArray();

        // Every mismatch is COLLECTED and reported together at the end, which
        // the mac gets for free and this does not: XCTAssert records a failure
        // and carries on, where xUnit's Assert throws on the first one. Ported
        // as a straight sequence of Asserts, the count guard below would be
        // dead code and the reversion this test exists to catch would name one
        // case where the mac names both — a weaker signal for the same bug.
        var failures = new List<string>();
        void Check(bool passed, string message)
        {
            if (!passed) failures.Add(message);
        }

        // Reaching both branches is asserted at the end rather than assumed. A
        // case list edited until every course had a curriculum folder would
        // leave this test green while covering exactly what it covered before
        // — which is the shape of the failure this whole file exists to catch.
        bool sawResolvedFolder = false;
        bool sawPlaceholder = false;

        foreach (JsonNode? node in Contract()["cases"]!.AsArray())
        {
            JsonNode figure = node!;
            string name = figure["name"]!.ToString();
            var entries = SpecialFoldersHelp.Entries(CourseFrom(figure));

            // Recorded AND enforced: a mismatch has to skip this case, or the
            // indexer throws and takes the whole run down rather than failing
            // one case. `continue` rather than `return`, so one bad case does
            // not silence every case after it.
            Check(rows.Count == entries.Count,
                $"case \"{name}\": no row is ever omitted — see rowsAreOrdered "
                + $"(contract lists {rows.Count} rows, the sheet showed {entries.Count})");
            if (rows.Count != entries.Count) continue;

            for (int i = 0; i < rows.Count; i++)
            {
                JsonNode row = rows[i]!;
                string key = row["key"]!.ToString();
                string place = $"case \"{name}\", row \"{key}\"";

                string what = row["what"]!.ToString();
                Check(what == entries[i].What,
                    $"{place}: expected what \"{what}\", got \"{entries[i].What}\"");

                string why = row["why"]!.ToString();
                Check(why == entries[i].Why,
                    $"{place}: expected why \"{why}\", got \"{entries[i].Why}\"");

                // A fixed row's name is the contract's; a course-named row's is
                // not, and asserting it here would only restate the cases above.
                if (row["namedFrom"]!.ToString() == "fixed")
                {
                    string fixedName = row["name"]!.ToString();
                    Check(fixedName == entries[i].Name,
                        $"{place}: expected name \"{fixedName}\", got \"{entries[i].Name}\"");
                }

                if (key == "curriculum")
                {
                    if (entries[i].Name == SpecialFoldersHelp.NoCurriculumFolderYet)
                        sawPlaceholder = true;
                    else
                        sawResolvedFolder = true;
                }
            }
        }

        Check(sawResolvedFolder,
            "no case names a real curriculum folder, so the explanation shown beside "
            + "a folder the course HAS went unchecked");
        Check(sawPlaceholder,
            $"no case leaves a course without a curriculum folder, so the explanation "
            + $"shown beside \"{SpecialFoldersHelp.NoCurriculumFolderYet}\" went unchecked "
            + "— which is the hole the retired second sentence lived in");

        Assert.True(failures.Count == 0,
            $"{failures.Count} mismatch(es) against specialFoldersHelp:"
            + Environment.NewLine + string.Join(Environment.NewLine, failures));
    }

    [Fact]
    public void TheTitleAndIntroAreTheContractsOwn()
    {
        Assert.Equal(Contract()["title"]!.ToString(), SpecialFoldersHelp.Title);
        Assert.Equal(Contract()["intro"]!.ToString(), SpecialFoldersHelp.Intro);
        Assert.Equal(Contract()["openedBy"]!.ToString(), SpecialFoldersHelp.OpenedBy);
        Assert.Equal(Contract()["dismissedBy"]!.ToString(), SpecialFoldersHelp.DismissedBy);

        // Found by key, not by position: a hard-coded index goes on passing
        // while testing the wrong row once one is inserted above it - the same
        // trap NameOfRow was already fixed for.
        foreach (JsonNode? row in Contract()["rows"]!.AsArray())
            if (row!["key"]!.ToString() == "curriculum")
                Assert.Equal(row["placeholderWhenNone"]!.ToString(),
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
        // A computer studies course with a folder called "Scripts", and NO
        // curriculum folder — the branch no hand-typed fixture had ever
        // exercised, so "Your curriculum folder" and "None chosen" are
        // actually rendered here rather than merely declared. The row check
        // above now reaches that branch too, through the contract's own cases;
        // this fixture stays because "Scripts" appears in no case and is what
        // proves the sweep excludes a teacher's own folder names.
        var config = CourseConfiguration.FromBytes(Encoding.UTF8.GetBytes(
            """{"course_code":"ICS3U","per_section_folders":["All Classes"],"shared_folders":["Concepts","Scripts","Tasks"],"graded_folders":["Scripts","Tasks"]}"""));
        var entries = SpecialFoldersHelp.Entries(config);
        var rows = Contract()["rows"]!.AsArray();
        Assert.Equal(rows.Count, entries.Count);

        // What the PRODUCT writes: the title, the intro, both buttons, the two
        // placeholders, every row's what and why — and a row's NAME only when
        // the contract marks it `namedFrom: "fixed"` (Media, index.md, Key
        // Links.md, Curriculum Coverage), because those four are the product's
        // own words. A course-named row shows the teacher's own word back to
        // them as they typed it, and "Scripts" is not a wording bug.
        var shown = new StringBuilder()
            .Append(SpecialFoldersHelp.Title).Append(' ')
            .Append(SpecialFoldersHelp.Intro).Append(' ')
            .Append(SpecialFoldersHelp.OpenedBy).Append(' ')
            .Append(SpecialFoldersHelp.DismissedBy).Append(' ')
            .Append(SpecialFoldersHelp.NoCurriculumFolderYet).Append(' ')
            .Append(SpecialFoldersHelp.NoneChosen);
        int fixedNames = 0;
        for (int i = 0; i < entries.Count; i++)
        {
            if (rows[i]!["namedFrom"]!.ToString() == "fixed") { shown.Append(' ').Append(entries[i].Name); fixedNames++; }
            shown.Append(' ').Append(entries[i].What).Append(' ').Append(entries[i].Why);
        }
        Assert.Equal(4, fixedNames);
        string text = shown.ToString().ToLowerInvariant();

        // The exclusion is exercised, not merely written: the teacher's
        // "Scripts" counts for marks, so it is on the sheet by name, and it
        // would fail the sweep if names were in.
        Assert.Contains(entries, entry => entry.Name.Contains("Scripts"));
        Assert.Contains(entries, entry => entry.Name == SpecialFoldersHelp.NoCurriculumFolderYet);

        foreach (JsonNode? word in Contract()["saysNoMachinery"]!["jargon"]!.AsArray())
            Assert.False(text.Contains(word!.ToString().ToLowerInvariant()),
                $"the folders help says \"{word}\" to a teacher");
    }
}

using System.Text;
using System.Text.Json.Nodes;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// The pure half of a course kept for reference (#241, mac #206 branch A):
/// <c>contracts/shared-rules.json → referenceCourses</c> — the school years,
/// the shelf rule, the folder name, the neutralisation, the sentences, and how
/// the APP reads the marker (<c>markerAgreement</c>, every row). Every list is
/// deserialised, never retyped, and each runner asserts a floor so a green run
/// that ran nothing is impossible.
/// </summary>
public class ReferenceCourseTests
{
    private static JsonNode Rule => ContractLoader.LoadJson("shared-rules.json")["referenceCourses"]!;

    private static DateOnly Day(JsonNode node) => DateOnly.Parse(node.ToString());

    [Fact]
    public void TheSchoolYearLabelsAreTheContracts()
    {
        var cases = Rule["schoolYearLabel"]!["cases"]!.AsArray();
        foreach (var c in cases)
            Assert.Equal(c!["expect"]!.ToString(), SchoolYear.Label(c["startingYear"]!.GetValue<int>()));
        Assert.True(cases.Count >= 3);
    }

    [Fact]
    public void TheSchoolYearsOfferedAreTheContracts()
    {
        Assert.Equal(Rule["schoolYearsOffered"]!["floor"]!.GetValue<int>(), SchoolYear.EarliestStartingYear);
        var cases = Rule["schoolYearsOffered"]!["cases"]!.AsArray();
        foreach (var c in cases)
        {
            var expected = c!["expect"]!.AsArray().Select(y => y!.GetValue<int>()).ToList();
            Assert.Equal(expected, SchoolYear.Offered(Day(c["today"]!)));
        }
        Assert.True(cases.Count >= 4);
    }

    [Fact]
    public void AStoredSchoolYearReadsAsTheContractSays()
    {
        var cases = Rule["schoolYearRead"]!["cases"]!.AsArray();
        foreach (var c in cases)
        {
            JToken? stored = c!["storedIsAbsent"]?.GetValue<bool>() == true
                ? null
                : c["storedValue"] is null ? JValue.CreateNull() : JToken.Parse(c["storedValue"]!.ToJsonString());
            int? expected = c["expect"] is null ? null : c["expect"]!.GetValue<int>();
            Assert.True(expected == SchoolYear.Read(stored, Day(c["today"]!)), c["name"]!.ToString());
        }
        Assert.True(cases.Count >= 8);
    }

    [Fact]
    public void ACodeIsUniqueWithinOneSchoolYearGroup()
    {
        var cases = Rule["codeUniqueWithinAGroup"]!["cases"]!.AsArray();
        foreach (var c in cases)
        {
            var shelf = c!["shelf"]!.AsArray().Select((s, i) => new ReferenceCourse.Shelved(
                s!["code"]!.ToString(),
                s["year"] is null ? null : s["year"]!.GetValue<int>(),
                s["folderName"]?.ToString() ?? $"FOLDER{i}")).ToList();
            var placing = c["placing"]!;
            int? year = placing["year"] is null ? null : placing["year"]!.GetValue<int>();
            string? trouble = ReferenceCourse.ShelfTrouble(placing["code"]!.ToString(), year, shelf,
                c["ignoringFolderName"]?.ToString());
            Assert.True((c["expect"]!.ToString() == "refused") == (trouble is not null), c["name"]!.ToString());
        }
        Assert.True(cases.Count >= 7);
    }

    [Fact]
    public void TheShelfSentenceNamesTheYearOrItsAbsence()
    {
        var shelf = new[] { new ReferenceCourse.Shelved("ICS3U", 2025, "ICS3U-2025"), new ReferenceCourse.Shelved("ICS3U", null, "ICS3U-REF") };
        Assert.Equal("You already have a ICS3U kept for reference from 2025\u201326. Choose a different school year.",
            ReferenceCourse.ShelfTrouble("ics3u", 2025, shelf));
        Assert.Equal("You already have a ICS3U kept for reference with no school year. Choose a school year for this one.",
            ReferenceCourse.ShelfTrouble("ICS3U", null, shelf));
    }

    [Fact]
    public void TheFolderNameIsTheContracts()
    {
        var cases = Rule["importing"]!["folderNameProduced"]!["cases"]!.AsArray();
        foreach (var c in cases)
        {
            int? year = c!["schoolYear"] is null ? null : c["schoolYear"]!.GetValue<int>();
            var existing = c["existing"]!.AsArray().Select(e => e!.ToString());
            string made = ReferenceCourse.ProposedFolderName(c["code"]!.ToString(), year, existing);
            Assert.Equal(c["expect"]!.ToString(), made);
            Assert.Equal(made, CourseCodeValidator.Normalize(made));   // survives being normalised again
        }
        Assert.True(cases.Count >= 4);
    }

    [Fact]
    public void AFolderNameNeverOutgrowsTwelveCharacters()
    {
        string made = ReferenceCourse.ProposedFolderName("ROBOTICS 1", 2025, Array.Empty<string>());
        Assert.True(made.Length <= CourseCodeValidator.MostCharacters, made);
        Assert.EndsWith("-2025", made);
        Assert.Null(CourseCodeValidator.Problem(made, Array.Empty<string>()));
    }

    [Fact]
    public void MarkingACourseNeutralisesItsDeployingSettings()
    {
        var config = CourseConfiguration.FromDictionary(JObject.Parse("""
            {"course_code":"ICS3U","deploy_target":"netlify","deploy_folder_path":"C:\\sites",
             "additional_deploy_targets":[{"type":"cloudflare_pages"}],
             "custom_domains":{"sections":{"section1":{"netlify":"cs.example.org"}}}}
            """));
        config.MarkKeptForReference(2025);
        var keys = Rule["neutralises"]!["keys"]!.AsArray();
        foreach (var k in keys)
        {
            string key = k!["key"]!.ToString(), becomes = k["becomes"]!.ToString();
            if (becomes == "removed") Assert.Null(config.Values[key]);
            else Assert.Equal(becomes, (string?)config.Values[key]);
        }
        Assert.True(keys.Count >= 4);
        Assert.True(config.KeptForReference);
        Assert.Equal(2025, (int)config.Values["reference_school_year"]!);
        Assert.Equal("ICS3U", config.CourseCode);   // course_code is left as it was
    }

    [Fact]
    public void NoSchoolYearClearsTheKeyRatherThanWritingNull()
    {
        var config = CourseConfiguration.FromDictionary(JObject.Parse("""{"course_code":"ICS3U","reference_school_year":2024}"""));
        config.MarkKeptForReference(null);
        Assert.False(config.Values.ContainsKey("reference_school_year"));
    }

    [Fact]
    public void EverySentenceIsTheContracts()
    {
        var wording = Rule["wording"]!.AsObject();
        var notSentences = new HashSet<string> { "rule", "machineryCheck", "theCannotTellSentence", "whyTheLaunchersStillSayPublished" };
        int compared = 0;
        foreach (var (key, value) in wording)
        {
            if (notSentences.Contains(key)) continue;
            Assert.True(ReferenceCourse.Wording.TryGetValue(key, out string? mine), $"referenceCourses.wording.{key} is not said here");
            Assert.Equal(value!.ToString(), mine);
            compared++;
        }
        Assert.True(compared >= 16, $"only {compared} sentences compared");
        Assert.Equal(Rule["refusal"]!["sentence"]!.ToString(), ReferenceCourse.RefusalSentenceTemplate);
    }

    [Fact]
    public void NoSentenceNamesTheMachinery()
    {
        string[] forbidden = { "lock flag", "immutable", "permission", "chflags", "script", "container", "ACL", "access entr" };
        foreach (var sentence in ReferenceCourse.Wording.Values.Append(ReferenceCourse.RefusalSentenceTemplate))
            foreach (string word in forbidden)
                Assert.DoesNotContain(word, sentence, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// <c>markerAgreement</c>, the APP's column: every row's
    /// <c>appReadsAsReference</c>, read through the same loader the sidebar
    /// uses. A config the loader cannot open is a course the sidebar never
    /// shows, which reads as not-a-reference. And the invariant: wherever the
    /// app reads a course as kept for reference, every launcher refuses.
    /// </summary>
    [Fact]
    public void TheAppReadsTheMarkerAsEveryRowSays()
    {
        var cases = Rule["markerAgreement"]!["cases"]!.AsArray();
        int ran = 0;
        foreach (var c in cases)
        {
            string name = c!["name"]!.ToString();
            bool expected = c["appReadsAsReference"]!.GetValue<bool>();
            if (expected) Assert.True(c["expect"]!.ToString() == "refused", $"{name}: the app reads it as kept, so every launcher must refuse");
            // No file, a folder where the file should be, a file that cannot be
            // opened: the sidebar never loads such a course, so it is not one.
            if (c["configText"] is null || c["unreadable"]?.GetValue<bool>() == true) { Assert.False(expected, name); ran++; continue; }
            byte[] text = Encoding.UTF8.GetBytes(c["configText"]!.ToString());
            if (c["bom"]?.GetValue<bool>() == true) text = new byte[] { 0xEF, 0xBB, 0xBF }.Concat(text).ToArray();
            bool reads;
            try { reads = CourseConfiguration.FromBytes(text).KeptForReference; }
            catch { reads = false; }
            Assert.True(expected == reads, $"{name}: the app read it as {(reads ? "kept for reference" : "ordinary")}");
            ran++;
        }
        Assert.True(ran >= 26, $"only {ran} rows ran");
    }

    [Fact]
    public void AReferenceCourseShowsItsRealCodeAndALiveOneItsFolder()
    {
        var live = new Course("ICS3U", @"C:\x\courses\ICS3U", CourseConfiguration.FromDictionary(JObject.Parse("""{"course_code":"ICS3U"}""")));
        var kept = new Course("ICS3U-2025", @"C:\x\courses\ICS3U-2025",
            CourseConfiguration.FromDictionary(JObject.Parse("""{"course_code":"ics3u","kept_for_reference":true,"reference_school_year":2025}""")));
        Assert.Equal("ICS3U", ReferenceCourse.ShownCode(live));
        Assert.Equal("ICS3U", ReferenceCourse.ShownCode(kept));
        Assert.Equal("ICS3U \u00B7 2025\u201326", ReferenceCourse.NameWithYear(kept, new DateOnly(2026, 9, 20)));
        Assert.Equal("ICS3U", ReferenceCourse.NameWithYear(live, new DateOnly(2026, 9, 20)));
    }
}

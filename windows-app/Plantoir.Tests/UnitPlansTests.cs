using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/shared-rules.json</c> → <c>unitPlanning</c>: the plan.json
/// reader (#790 item 1) walked through <c>planFileCases</c> on a real disk, its
/// folder-name rules read from the contract, and <c>neverFolderNames</c> pinned
/// against <see cref="CourseArchiver.ExcludedFromArchives"/> (item 5). The
/// mac's twins are <c>UnitPlansTests</c> and <c>UnitPlanningContractTests</c>.
/// </summary>
public sealed class UnitPlansTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-unit-plans-" + Guid.NewGuid().ToString("N"));

    public UnitPlansTests() => Directory.CreateDirectory(_root);

    public void Dispose() => ReferenceFixtures.Remove(_root);

    internal static JsonNode UnitPlanning() => ContractLoader.LoadJson("shared-rules.json")["unitPlanning"]!;

    public static IEnumerable<object[]> PlanFileCaseNames() =>
        UnitPlanning()["planFileCases"]!["cases"]!.AsArray().Select(c => new object[] { c!["name"]!.ToString() });

    /// <summary>A course folder under the test's root, with its planning folder made.</summary>
    private string Course(string name, bool planningFolder = true)
    {
        string course = Path.Combine(_root, name);
        Directory.CreateDirectory(course);
        if (planningFolder) Directory.CreateDirectory(UnitPlans.PlanningFolder(course));
        return course;
    }

    [Fact]
    public void ThereAreAtLeastTheEighteenPlanFileCases() =>
        Assert.True(PlanFileCaseNames().Count() >= 18, "planFileCases shrank");

    [Theory]
    [MemberData(nameof(PlanFileCaseNames))]
    public void EveryPlanFileCaseHoldsAsTheContractSays(string name)
    {
        var testCase = UnitPlanning()["planFileCases"]!["cases"]!.AsArray().Single(c => c!["name"]!.ToString() == name)!;
        string course = Course("course");
        string unit = Path.Combine(UnitPlans.PlanningFolder(course), testCase["folder"]!.ToString());
        Directory.CreateDirectory(unit);
        if (testCase["file"] is { } file)
            File.WriteAllText(Path.Combine(unit, UnitPlans.PlanFileName), file.ToString(), new UTF8Encoding(false));

        var reading = UnitPlans.Read(course);
        switch (testCase["expect"]!.ToString())
        {
            case "read":
                var plan = Assert.Single(reading.Plans);
                Assert.Equal(0, reading.Unreadable);
                Assert.Equal(testCase["named"]!.ToString(), UnitPlans.NameInTheGreeting(plan));
                Assert.Equal(testCase["firstClass"]?.ToString(), plan.FirstClass?.ToString("yyyy-MM-dd"));
                break;
            case "unreadable":
                Assert.Empty(reading.Plans);
                Assert.Equal(1, reading.Unreadable);
                break;
            case "ignored":
                Assert.Empty(reading.Plans);
                Assert.Equal(0, reading.Unreadable);
                break;
            default:
                Assert.Fail("an expect this test does not know: " + testCase["expect"]);
                break;
        }
    }

    /// <summary>#790 item 5: the list is the archive's own, the same set and the same count.</summary>
    [Fact]
    public void TheNeverFolderNamesAreTheArchiveExclusions()
    {
        var never = UnitPlanning()["neverFolderNames"]!.AsArray().Select(n => n!.ToString()).ToList();
        Assert.Equal(CourseArchiver.ExcludedFromArchives.Count, never.Count);
        Assert.Equal(CourseArchiver.ExcludedFromArchives.OrderBy(n => n, StringComparer.Ordinal),
                     never.OrderBy(n => n, StringComparer.Ordinal));
    }

    [Fact]
    public void TheFolderNameRulesAreTheContracts()
    {
        Assert.Equal(UnitPlanning()["slugRules"]!["pattern"]!.ToString(), UnitPlans.SlugPattern);
        Assert.Equal(UnitPlanning()["neverSlugs"]!.AsArray().Select(n => n!.ToString()), UnitPlans.NeverSlugs);
        Assert.Equal(UnitPlanning()["planFile"]!["name"]!.ToString(), UnitPlans.PlanFileName);
        Assert.Equal(UnitPlanning()["folder"]!.ToString(), "courses/<CODE>/" + UnitPlans.FolderPath.Replace('\\', '/'));
        // neverSlugsWhy: the names in neverFolderNames that do not start with a dot, plus assets.
        var expected = UnitPlanning()["neverFolderNames"]!.AsArray().Select(n => n!.ToString())
            .Where(n => !n.StartsWith('.')).Append("assets").OrderBy(n => n, StringComparer.Ordinal);
        Assert.Equal(expected, UnitPlans.NeverSlugs.OrderBy(n => n, StringComparer.Ordinal));
        Assert.True(UnitPlans.IsUnitSlug("unit-1"));
        Assert.True(UnitPlans.IsUnitSlug("a" + new string('b', 39)));
        Assert.False(UnitPlans.IsUnitSlug("a" + new string('b', 40)));
        Assert.False(UnitPlans.IsUnitSlug("Unit-1"));
        Assert.False(UnitPlans.IsUnitSlug("1-unit"));
        // A trailing line break: .NET's $ matches before one, so the pattern alone would let it through.
        Assert.False(UnitPlans.IsUnitSlug("unit-1\n"));
    }

    /// <summary>A plan file that cannot be opened at all is counted, never thrown.</summary>
    [Fact]
    public void AFileThatCannotBeReadIsCountedAndNothingIsThrown()
    {
        string course = Course("locked");
        string unit = Path.Combine(UnitPlans.PlanningFolder(course), "unit-1");
        Directory.CreateDirectory(unit);
        string file = Path.Combine(unit, UnitPlans.PlanFileName);
        File.WriteAllText(file, "{\"unit\": \"Unit 1\"}");
        string good = Path.Combine(UnitPlans.PlanningFolder(course), "unit-2");
        Directory.CreateDirectory(good);
        File.WriteAllText(Path.Combine(good, UnitPlans.PlanFileName), "{\"unit\": \"Unit 2\"}");

        UnitPlans.Reading reading;
        using (new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.None))
            reading = UnitPlans.Read(course);
        Assert.Equal(1, reading.Unreadable);
        Assert.Equal("unit-2", Assert.Single(reading.Plans).Slug);
    }

    [Fact]
    public void AFolderThatIsNotThereReadsAsNoPlans()
    {
        var reading = UnitPlans.Read(Path.Combine(_root, "no-such-course"));
        Assert.Empty(reading.Plans);
        Assert.Equal(0, reading.Unreadable);
        Assert.Empty(UnitPlans.Read(Course("no-planning", planningFolder: false)).Plans);
    }

    /// <summary>Windows editors write a byte order mark; a plan saved with one is read.</summary>
    [Fact]
    public void APlanFileWithAByteOrderMarkIsRead()
    {
        string course = Course("bom");
        string unit = Path.Combine(UnitPlans.PlanningFolder(course), "unit-1");
        Directory.CreateDirectory(unit);
        File.WriteAllText(Path.Combine(unit, UnitPlans.PlanFileName), "{\"unit\": \"Unit 1\", \"title\": \"Matter\"}", new UTF8Encoding(true));
        Assert.Equal(0xEF, File.ReadAllBytes(Path.Combine(unit, UnitPlans.PlanFileName))[0]);
        Assert.Equal("Unit 1: Matter", UnitPlans.NameInTheGreeting(Assert.Single(UnitPlans.Read(course).Plans)));
    }

    /// <summary>A unit folder that is a junction is not read and not counted, as the mac skips a linked folder.</summary>
    [Fact]
    public void AUnitFolderThatIsAJunctionIsNotAPlan()
    {
        string elsewhere = Path.Combine(_root, "elsewhere");
        Directory.CreateDirectory(elsewhere);
        File.WriteAllText(Path.Combine(elsewhere, UnitPlans.PlanFileName), "{\"unit\": \"Unit 9\"}");
        string course = Course("linked");
        ReferenceFixtures.Junction(Path.Combine(UnitPlans.PlanningFolder(course), "unit-9"), elsewhere);
        var reading = UnitPlans.Read(course);
        Assert.Empty(reading.Plans);
        Assert.Equal(0, reading.Unreadable);
    }

    /// <summary>The read order: dated plans by first class, then the undated, a tie by folder name, whatever the disk's order.</summary>
    [Fact]
    public void PlansAreReadInTheGreetingsOrder()
    {
        string course = Course("order");
        void Make(string slug, string json)
        {
            string unit = Path.Combine(UnitPlans.PlanningFolder(course), slug);
            Directory.CreateDirectory(unit);
            File.WriteAllText(Path.Combine(unit, UnitPlans.PlanFileName), json);
        }
        Make("zeta", "{\"title\": \"Z\"}");
        Make("alpha", "{\"title\": \"A\"}");
        Make("late", "{\"title\": \"L\", \"firstClass\": \"2027-05-01\"}");
        Make("early", "{\"title\": \"E\", \"firstClass\": \"2027-01-01\"}");
        Assert.Equal(new[] { "early", "late", "alpha", "zeta" }, UnitPlans.Read(course).Plans.Select(p => p.Slug));
    }

    [Fact]
    public void OneLineCollapsesEveryKindOfWhiteSpace()
    {
        Assert.Equal("Waves and Sound", UnitPlans.OneLine(" Waves\r\n\tand\u00A0\u2028 Sound  "));
        Assert.Equal("", UnitPlans.OneLine(" \t\n"));
    }

    /// <summary>Covers: both ends included, one date read as that one day, no date no day.</summary>
    [Fact]
    public void CoversIncludesBothEnds()
    {
        var day = new DateOnly(2027, 2, 8);
        UnitPlans.Plan Plan(DateOnly? first, DateOnly? last) => new("u", "U", "", first, last, Array.Empty<string>());
        Assert.True(UnitPlans.Covers(Plan(day, day.AddDays(4)), day));
        Assert.True(UnitPlans.Covers(Plan(day, day.AddDays(4)), day.AddDays(4)));
        Assert.False(UnitPlans.Covers(Plan(day, day.AddDays(4)), day.AddDays(5)));
        Assert.False(UnitPlans.Covers(Plan(day, day.AddDays(4)), day.AddDays(-1)));
        Assert.True(UnitPlans.Covers(Plan(null, day), day));
        Assert.True(UnitPlans.Covers(Plan(day, null), day));
        Assert.False(UnitPlans.Covers(Plan(day, null), day.AddDays(1)));
        Assert.False(UnitPlans.Covers(Plan(null, null), day));
    }
}

using ModelContextProtocol;
using Plantoir.Core.Assist;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// "Publish tomorrow's class" — the commonest request in the product, and one
/// of the prompt shelf's suggested prompts.
///
/// <para>Issue #116: the eight fixed phrasings set <c>when</c>, a relative
/// day, and the tool takes a REQUIRED <c>date</c>, an absolute one. The app
/// reaches its tools through <c>plantoir-mcp</c> over JSON-RPC, and the SDK's
/// binder drops a key the method does not declare — so every one of the eight
/// failed with "That tool couldn't be run", a sentence that names machinery,
/// on a phrasing a teacher reaches by clicking.</para>
///
/// <para>These pin the fix at both ends. <see cref="AssistCardCommand"/> now
/// settles the day and sends it as <c>date</c>; the tool understands the words
/// as well, because an MCP client has no card to rename anything. The seam
/// itself — that every key a card sets is a parameter its tool declares — is
/// gated across every phrasing by
/// <c>AssistSurfaceContractTests.TheCardsArgumentsReachTheToolThatReadsThem</c>,
/// which is where this defect was found.</para>
///
/// <para>Which day each word NAMES is not asserted here: that is
/// <c>contracts/schedule-rules.json</c> → <c>relativeDays</c>, run by both
/// platforms, because the same sentence must mean the same day on either
/// machine. What is asserted here is that the day reaches the tool at all.</para>
/// </summary>
public class PublishTomorrowsClassTests : IDisposable
{
    /// <summary>A Tuesday, the same day the contract counts from.</summary>
    private static readonly DateOnly Today = new(2026, 9, 8);

    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-class-on").FullName;
    private readonly FakeLauncher _launcher = new();

    public PublishTomorrowsClassTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        AddCourse("ICS3U", 1);
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    // ---- What the app puts on the wire -----------------------------------

    /// <summary>
    /// Every one of the eight sends a <c>date</c>, and none sends a
    /// <c>when</c> the tool would never see.
    /// </summary>
    /// <remarks>
    /// The card's own arguments still say <c>when</c> — that is the mac's
    /// shape, pinned by <c>cardPhrasings</c> and asserted by
    /// <see cref="AssistCardCommandTests"/> — so this is about the JSON, which
    /// is the only thing the server is ever handed.
    /// </remarks>
    [Theory]
    [InlineData("publish tomorrow's class", "2026-09-09")]
    [InlineData("publish monday's class", "2026-09-14")]
    [InlineData("publish tuesday's class", "2026-09-08")]
    [InlineData("publish wednesday's class", "2026-09-09")]
    [InlineData("publish thursday's class", "2026-09-10")]
    [InlineData("publish friday's class", "2026-09-11")]
    [InlineData("publish saturday's class", "2026-09-12")]
    [InlineData("publish sunday's class", "2026-09-13")]
    public void EveryPhrasingSendsADateTheToolTakes(string typed, string expected)
    {
        var json = AssistCardCommand.Matching(typed)!.ToJsonObject("ICS3U", 1, Today);

        Assert.Equal(expected, json["date"]!.ToString());
        Assert.False(json.ContainsKey("when"),
            $"“{typed}” still sends \"when\", which the binder drops on the way to the tool.");
    }

    /// <summary>
    /// The day is settled BEFORE the call, so the plan a teacher read and the
    /// act they agreed to are the same day.
    /// </summary>
    /// <remarks>
    /// <c>AssistAgent.RunCommand</c> synthesises one arguments object and uses
    /// it twice: for the plan twin, then — if Go is pressed — for the act.
    /// Were the word carried through instead, a plan shown at 23:59 and agreed
    /// to at 00:01 would publish a different class than the one it described:
    /// rare, silent, and a wrong day nobody would think to look for.
    /// </remarks>
    [Fact]
    public void TheDayIsSettledOnceRatherThanTwice()
    {
        var json = AssistCardCommand.Matching("publish tomorrow's class")!.ToJsonObject("ICS3U", 1, Today);

        Assert.Equal("2026-09-09", json["date"]!.ToString());
        Assert.DoesNotContain("tomorrow", json.ToJsonString());
    }

    /// <summary>
    /// Only this tool's argument is renamed. <c>schedule_deploy</c> genuinely
    /// takes a <c>when</c> — a day AND a time — and it must go on arriving
    /// under that name.
    /// </summary>
    [Fact]
    public void NothingElseThatSaysWhenIsTouched()
    {
        var card = new AssistCardCommand("schedule_deploy",
            new Dictionary<string, string> { ["when"] = "2026-09-09 06:30" });

        var json = card.ToJsonObject("ICS3U", 1, Today);

        Assert.Equal("2026-09-09 06:30", json["when"]!.ToString());
        Assert.False(json.ContainsKey("date"));
    }

    // ---- What the tool does with it --------------------------------------

    /// <summary>
    /// The tool reads the words too, for the client that has no card.
    /// </summary>
    /// <remarks>
    /// Claude Code reaches these tools directly, and nothing between it and
    /// the server renames or settles anything. The mac's runner has always
    /// forgiven a relative day; without this the two MCP surfaces would answer
    /// the same sentence differently.
    /// </remarks>
    [Fact]
    public void AnMcpCallerMaySayTomorrow()
    {
        string plan = Tools().PlanPublishClassOn("ICS3U", 1, "tomorrow").Detail();

        Assert.Contains("Unit 1, Day 2", plan);
        Assert.DoesNotContain("Unit 1, Day 1", plan);
    }

    /// <summary>A weekday name, resolved the same way, in the same place.</summary>
    [Fact]
    public void AnMcpCallerMaySayAWeekday()
    {
        // Thursday is 2026-09-10, which is Unit 1, Day 3.
        string plan = Tools().PlanPublishClassOn("ICS3U", 1, "Thursday").Detail();

        Assert.Contains("Unit 1, Day 3", plan);
    }

    /// <summary>An absolute date still reads as one, and a non-date still does not.</summary>
    [Fact]
    public void ADateStillReadsAsADate()
    {
        Assert.Contains("Unit 1, Day 2", Tools().PlanPublishClassOn("ICS3U", 1, "2026-09-09").Detail());

        Assert.Contains("isn’t a date",
            Tools().PlanPublishClassOn("ICS3U", 1, "the day after the test").Detail());
    }

    /// <summary>
    /// The teacher is told the DAY, not the word that was sent.
    /// </summary>
    /// <remarks>
    /// "Published the class on tomorrow" is not a sentence anybody can check
    /// against their timetable a week later, which is exactly when a report
    /// about the wrong class going up gets read.
    /// </remarks>
    [Fact]
    public async Task WhatItSaysAfterwardsNamesTheDay()
    {
        var answer = await Tools().PublishClassOn(
            "ICS3U", 1, "tomorrow", new Progress<ProgressNotificationValue>(_ => { }), default);

        Assert.Contains("Published the class on 2026-09-09.", answer.Summary());
    }

    /// <summary>
    /// A day read correctly with no class on it is refused, with the days that
    /// DO have one — rather than publishing the nearest thing.
    /// </summary>
    [Fact]
    public void ADayWithNoClassIsRefusedAndTheRealOnesAreNamed()
    {
        // Saturday: a real day, correctly read, with nothing taught on it.
        string said = Tools().PlanPublishClassOn("ICS3U", 1, "saturday").Detail();

        Assert.Contains("has no class on 2026-09-12", said);
        Assert.Contains("2026-09-08 to 2026-09-10", said);
    }

    // ---- The fixture -----------------------------------------------------

    /// <summary>The tools, with today pinned to the day the fixture is built around.</summary>
    private PlantoirTools Tools() =>
        new(new AssistWorkspace(_folder, _launcher)) { Today = () => Today };

    private void AddCourse(string code, params int[] sections)
    {
        string directory = Path.Combine(_folder, "courses", code);
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "course_config.json"),
            $$"""
            {
              "course_code": "{{code}}",
              "course_name": "A course",
              "deploy_target": "netlify",
              "num_sections": {{sections.Length}},
              "per_section_folders": ["All Classes"],
              "per_section_files": ["Key Links.md"],
              "section_numbers": [{{string.Join(", ", sections)}}]
            }
            """);

        // Today, tomorrow, and the day after — so a word read as the wrong day
        // lands on a DIFFERENT class rather than on nothing at all, which is
        // the failure worth catching. Nothing on the Saturday, deliberately.
        Class(code, "Unit 1, Day 1", "2026-09-08");
        Class(code, "Unit 1, Day 2", "2026-09-09");
        Class(code, "Unit 1, Day 3", "2026-09-10");
    }

    private void Class(string course, string title, string date)
    {
        string full = Path.Combine(_folder, "courses", course, "section1", "All Classes", title + ".md");
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, $"---\npublish: false\ncreated: {date}T07:00:00.000-0400\n---\nBody.\n");
    }
}

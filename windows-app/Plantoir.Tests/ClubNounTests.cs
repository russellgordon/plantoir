using System.Text.Json.Nodes;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Mcp;

namespace Plantoir.Tests;

/// <summary>
/// "meeting" in a club (#274, mac #267): the TEACHER's card says meeting, the
/// MODEL's copy never does. The mac's
/// <c>ClubNounTests.testTheNounNeverReachesWhatTheModelReads</c> flips
/// <c>class_noun</c> on one club and requires every plan's model copy to be
/// byte-identical; this is the same test over plantoir-mcp's tools, reading
/// the TEXT content (what the model and Claude Code read) apart from the
/// <c>_meta</c> teacher summary (what the window shows).
/// </summary>
public sealed class ClubNounTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("club-noun").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private PlantoirTools Club(string? noun)
    {
        var classes = new JsonArray(
            new JsonObject { ["title"] = "Week 1", ["date"] = "2025-09-18" },
            new JsonObject { ["title"] = "Week 2", ["date"] = "2025-09-25" },
            new JsonObject { ["title"] = "Week 3", ["date"] = "2025-10-02" });
        var dates = Enumerable.Range(0, 10).Select(week => new DateOnly(2025, 9, 18).AddDays(7 * week)).ToList();
        foreach (var entry in Directory.EnumerateFileSystemEntries(_folder))
        {
            if (Directory.Exists(entry)) Directory.Delete(entry, true); else File.Delete(entry);
        }
        var workspace = ClassPlanningContractTests.ScratchCourse(_folder, new ClassPageNaming("Week", ClassPageScheme.Numbered),
                                                                 classes, dates);
        string config = Path.Combine(_folder, "courses", "ICS3U", "course_config.json");
        string text = File.ReadAllText(config);
        text = noun is null
            ? text.Replace("\"class_noun\": \"meeting\"", "\"class_noun_unused\": \"x\"")
            : text.Replace("\"class_noun\": \"meeting\"", $"\"class_noun\": \"{noun}\"");
        File.WriteAllText(config, text);
        return new PlantoirTools(workspace);
    }

    private static string ModelCopy(CallToolResult result) =>
        string.Join("\n", result.Content.OfType<TextContentBlock>().Select(block => block.Text));

    private static string TeacherCopy(CallToolResult result) =>
        result.Meta?[AssistToolAnswer.TeacherSummaryKey]?.GetValue<string>() ?? ModelCopy(result);

    private static IEnumerable<(string What, Func<PlantoirTools, CallToolResult> Call)> Plans() => new (string, Func<PlantoirTools, CallToolResult>)[]
    {
        ("make room", tools => tools.PlanMakeRoomForClasses("ICS3U", 1, 1, 2)),
        ("next page", tools => tools.PlanAddNextClass("ICS3U", 1)),
        ("duplicate", tools => tools.PlanAddNextClass("ICS3U", 1, duplicate: "Week 1")),
        ("add pages", tools => tools.PlanAddClasses("ICS3U", 1, 1, 2)),
    };

    [Fact]
    public void TheNounNeverReachesWhatTheModelReads()
    {
        foreach (var (what, call) in Plans())
        {
            string asAClass = ModelCopy(call(Club(null)));
            var meeting = call(Club("meeting"));
            Assert.Equal(asAClass, ModelCopy(meeting));
            Assert.DoesNotContain("meeting", ModelCopy(meeting), StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void AClubsTeacherReadsMeeting()
    {
        var tools = Club("meeting");
        Assert.Contains(AssistWording.WouldMakeRoomForAMeeting(1, "Week 2", "ICS3U", "1"),
                        TeacherCopy(tools.PlanMakeRoomForClasses("ICS3U", 1, 1, 2)));
        Assert.Contains(AssistWording.WouldAddPagesForAMeeting(1, "ICS3U", "1"),
                        TeacherCopy(tools.PlanAddNextClass("ICS3U", 1)));
        Assert.Contains(AssistWording.MakingRoomCannotBeUndoneForAMeeting,
                        TeacherCopy(tools.PlanAddNextClass("ICS3U", 1, duplicate: "Week 1")));
    }

    /// <summary>A refusal is one string for both audiences, in the ordinary wording.</summary>
    [Fact]
    public void ARefusalKeepsTheOrdinaryWording()
    {
        var refused = Club("meeting").PlanAddNextClass("ICS3U", 1, "next");
        Assert.Equal(NextClassPlanner.NoUnitsInANumberedCourse("ICS3U", "Week"), ModelCopy(refused));
        Assert.Null(refused.Meta?[AssistToolAnswer.TeacherSummaryKey]);
    }
}

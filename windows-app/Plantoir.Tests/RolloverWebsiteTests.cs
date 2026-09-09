using System.Text.Json.Nodes;
using ModelContextProtocol.Protocol;
using Plantoir.Core.Assist;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Rolling a section over to a new year, and the one question it asks.
///
/// <para>The decision (Russell, 2026-09-08) is that a rollover ASKS whether
/// this should be a new website or last year's, and guesses neither. These pin
/// the two things that make that safe rather than dangerous: an ordinary
/// re-date must never be asked the question, and a section cut loose must not
/// be left with a publish scheduled to run overnight with nobody to answer
/// it.</para>
///
/// <para>Serialized with the other process-wide-state classes because of
/// <see cref="TaskScheduling.SchtasksForTests"/>, which is a static. Without
/// the seam these tests would run <c>schtasks /Delete /F</c> against the real
/// Task Scheduler for "Plantoir deploy ICS3U section 1" — a task whoever is
/// running the suite may well have.</para>
/// </summary>
[Collection(SharedActivityState.Name)]
public class RolloverWebsiteTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-rollover").FullName;
    private readonly FakeLauncher _launcher = new();

    /// <summary>Task names the fake scheduler believes exist.</summary>
    private readonly HashSet<string> _scheduled = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Task names /Delete was asked to remove.</summary>
    private readonly List<string> _deleted = new();

    /// <summary>When set, every /Delete fails, which is the branch that must say something else.</summary>
    private bool _deletingFails;

    public RolloverWebsiteTests()
    {
        File.WriteAllText(Path.Combine(_folder, "preview.ps1"), "# marker");
        File.WriteAllText(Path.Combine(_folder, "deploy.ps1"), "# marker");
        AddCourse("ICS3U", 1);

        TaskScheduling.SchtasksForTests = arguments =>
        {
            string name = NamedTask(arguments);
            if (arguments.Contains("/Query"))
                return _scheduled.Contains(name) ? (0, "") : (1, "ERROR: The system cannot find the file specified.");
            if (arguments.Contains("/Delete"))
            {
                if (_deletingFails) return (1, "ERROR: Access is denied.");
                _deleted.Add(name);
                _scheduled.Remove(name);
                return (0, "");
            }
            return (1, "unexpected call");
        };
    }

    public void Dispose()
    {
        TaskScheduling.SchtasksForTests = null;
        try { Directory.Delete(_folder, recursive: true); } catch { }
        GC.SuppressFinalize(this);
    }

    private static string NamedTask(IReadOnlyList<string> arguments)
    {
        int at = arguments.ToList().IndexOf("/TN");
        return at >= 0 && at + 1 < arguments.Count ? arguments[at + 1] : "";
    }

    // ---- The question is asked of rollovers only -------------------------

    /// <summary>
    /// Three of the four phrasings that reach <c>re_date_classes</c> are NOT
    /// rollovers, and this is the regression that would hurt most.
    ///
    /// <para>A teacher re-dating after a snow day is mid-semester. Asking them
    /// whether they want a new website — and worse, letting "a new website" be
    /// answered — abandons the address their students are reading right
    /// now.</para>
    /// </summary>
    [Theory]
    [InlineData("re-date my classes")]
    [InlineData("redate my classes")]
    [InlineData("re-date this section")]
    public void AnOrdinaryReDateCarriesNoRolloverFlag(string phrasing)
    {
        var command = AssistCardCommand.Matching(phrasing);
        Assert.NotNull(command);
        Assert.Equal("re_date_classes", command!.ToolName);
        Assert.False(command.Arguments.ContainsKey("rollover"),
            $"“{phrasing}” is an ordinary re-date. Marking it a rollover would ask a teacher " +
            "mid-semester whether to abandon the address students are reading.");
    }

    [Fact]
    public void TheRolloverPhrasingsCarryWhatTheyMean()
    {
        var bare = AssistCardCommand.Matching("roll this section over to a new year");
        Assert.Equal("yes", bare!.Arguments["rollover"]);
        Assert.False(bare.Arguments.ContainsKey("website"),
            "The bare phrasing has not answered anything yet.");

        var fresh = AssistCardCommand.Matching(AssistWording.RolloverSayToStartANewWebsite);
        Assert.Equal("yes", fresh!.Arguments["rollover"]);
        Assert.Equal("new", fresh.Arguments["website"]);

        var same = AssistCardCommand.Matching(AssistWording.RolloverSayToKeepTheSameWebsite);
        Assert.Equal("yes", same!.Arguments["rollover"]);
        Assert.Equal("same", same.Arguments["website"]);
    }

    /// <summary>
    /// The sentences the assistant offers back must be sentences it accepts.
    ///
    /// <para>The reply tells a teacher to say one of two things word for word.
    /// If the matcher did not take those exact strings, the feature would
    /// invite a sentence it then failed to understand — which is worse than
    /// not offering one.</para>
    /// </summary>
    [Fact]
    public void TheOfferedAnswersAreAcceptedVerbatim()
    {
        foreach (string offered in new[] { AssistWording.RolloverSayToStartANewWebsite,
                                           AssistWording.RolloverSayToKeepTheSameWebsite })
            Assert.NotNull(AssistCardCommand.Matching(offered));
    }

    /// <summary>
    /// Both the card's arguments reach the WIRE, which is what makes this work
    /// on this platform at all.
    /// </summary>
    /// <remarks>
    /// Plantoir's own assistant window sends <see cref="AssistCardCommand.ToJsonObject"/>
    /// verbatim to <c>plantoir-mcp</c> over JSON-RPC, so an argument that is
    /// set on the card and not declared on the tool is an argument the server
    /// never sees. The mac's card and its runner share a process and so can
    /// keep <c>rollover</c> off its schema; here that would make the bare
    /// phrasing an ordinary re-date and the question would never be asked.
    /// </remarks>
    [Fact]
    public void TheCardsRolloverArgumentsSurviveBeingPutOnTheWire()
    {
        var json = AssistCardCommand.Matching(AssistWording.RolloverSayToStartANewWebsite)!
            .ToJsonObject("ICS3U", 1);
        Assert.Equal("yes", json["rollover"]!.ToString());
        Assert.Equal("new", json["website"]!.ToString());
    }

    // ---- Cutting a section loose -----------------------------------------

    /// <summary>
    /// EVERY destination type, not just the course's primary one.
    ///
    /// <para>This is the defect: <c>ReleaseSite</c> returned inside the first
    /// folder that held a marker, so a section pinned to both Netlify and
    /// Cloudflare had only its Netlify marker released and went on publishing
    /// over last year's Cloudflare site.</para>
    /// </summary>
    [Fact]
    public void ReleasingASectionReleasesEveryDestinationNotJustTheFirst()
    {
        MarkPublished("ICS3U", 1, ".cloudflare_sites");

        var release = Open().ReleaseSite(Open().Course("ICS3U"), 1);

        Assert.Equal(2, release.KeptFiles.Count);
        foreach (string folder in new[] { ".netlify_sites", ".cloudflare_sites" })
            Assert.False(File.Exists(Path.Combine(_folder, "courses", "ICS3U", folder, "section1.json")),
                $"{folder} is still pinned to last year's website.");
    }

    /// <summary>Renamed aside, never deleted — the file holds the way back.</summary>
    [Fact]
    public void TheReleasedFileIsKeptRatherThanDeleted()
    {
        var release = Open().ReleaseSite(Open().Course("ICS3U"), 1);

        string[] kept = Directory.GetFiles(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites"));
        Assert.Single(kept);
        Assert.Contains(".previous-", Path.GetFileName(kept[0]));
        Assert.Contains("ics3u-s1-2026-gordon", File.ReadAllText(kept[0]));
        Assert.Single(release.KeptFiles);
        // Named the way a teacher would find it: the folder and the file, not a
        // path relative to the working folder — the built output is outside it
        // on this platform, so that would be a run of "..\..\".
        Assert.StartsWith(".netlify_sites/", release.KeptFiles[0]);
    }

    /// <summary>
    /// A destination that could not be released must not be reported as one
    /// that was never published.
    /// </summary>
    [Fact]
    public void AMarkerThatCannotBeReleasedIsNotCalledNeverPublished()
    {
        // A directory sitting where the kept file would go makes the move fail
        // without touching the marker. The name has a timestamp in it, so it is
        // built the same way the code builds it.
        string folder = Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites");
        Directory.CreateDirectory(Path.Combine(folder,
            AssistWorkspace.ReleasedMarkerName(1, DateTime.Now.ToString("yyyy-MM-dd_HHmmss"))));

        var release = Open().ReleaseSite(Open().Course("ICS3U"), 1);

        Assert.False(release.ReleasedAnything);
        Assert.True(release.SomethingIsStillPinned, "The section is still pinned and must say so.");
        Assert.Equal(".netlify_sites/section1.json", Assert.Single(release.StillPinned));
    }

    /// <summary>A release can be taken back, which is what makes it safe to offer.</summary>
    [Fact]
    public void AReleaseCanBeUndone()
    {
        var undo = new UndoHistory();
        var workspace = new AssistWorkspace(_folder, _launcher, undo: undo);

        workspace.ReleaseSite(workspace.Course("ICS3U"), 1);
        var undone = undo.Undo();

        Assert.True(undone.Succeeded, "The release should be undoable.");
        Assert.True(
            File.Exists(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json")),
            "Undoing must put the section back on last year's website.");
    }

    // ---- What the tool actually says and does ----------------------------

    /// <summary>An ordinary re-date must say NOTHING about websites.</summary>
    [Fact]
    public async Task AnOrdinaryReDateSaysNothingAboutWebsites()
    {
        string said = await ReDate();
        Assert.DoesNotContain("website", said, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// A rollover with no answer yet asks, offers both sentences, and says
    /// plainly that nothing about the website changed.
    /// </summary>
    /// <remarks>
    /// The last part is what stops this feature quietly recreating the defect
    /// it was built to fix: the re-dating has already happened by now, so a
    /// teacher who ignores the question — or a Claude Code session, which can
    /// see no dialog at all — must not be left believing it was dealt with.
    /// </remarks>
    [Fact]
    public async Task ARolloverWithNoAnswerAsksAndChangesNoWebsite()
    {
        string said = await ReDate(rollover: "yes");

        Assert.Contains(AssistWording.RolloverWebsiteQuestion, said);
        Assert.Contains(AssistWording.RolloverSayToStartANewWebsite, said);
        Assert.Contains(AssistWording.RolloverSayToKeepTheSameWebsite, said);
        Assert.Contains(AssistWording.RolloverWebsiteNotDecided, said);
        Assert.True(
            File.Exists(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json")),
            "An unanswered question must not cut the section loose.");
    }

    /// <summary>
    /// The question must be in the SUMMARY, which is what a teacher reads.
    /// </summary>
    /// <remarks>
    /// The text content of the result is what Claude Code reads; the teacher's
    /// line rides in <c>_meta</c>. The mac shipped this in the detail only, so
    /// the feature worked over MCP alone and the app showed "Re-dated 3
    /// classes…" and no question at all.
    /// </remarks>
    [Fact]
    public async Task TheQuestionIsInWhatTheTeacherActuallyReads()
    {
        var result = await Call(rollover: "yes");
        Assert.Contains(AssistWording.RolloverWebsiteQuestion, TeacherSummary(result));
    }

    [Fact]
    public async Task KeepingTheSameWebsiteLeavesItAlone()
    {
        string said = await ReDate(rollover: "yes", website: "same");
        Assert.Contains(AssistWording.RolloverKeptTheSameWebsite, said);
        Assert.True(
            File.Exists(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json")));
    }

    [Fact]
    public async Task StartingANewWebsiteCutsTheSectionLoose()
    {
        string said = await ReDate(rollover: "yes", website: "new");
        Assert.Contains(AssistWording.RolloverIsOnANewWebsite, said);
        Assert.Contains(".previous-", said);
        Assert.False(
            File.Exists(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json")));
    }

    [Fact]
    public async Task StartingANewWebsiteForASectionThatNeverHadOne()
    {
        File.Delete(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json"));
        string said = await ReDate(rollover: "yes", website: "new");
        Assert.Contains(AssistWording.RolloverHadNoWebsiteYet, said);
    }

    /// <summary>
    /// An MCP client has no card, so <c>website</c> alone must be enough.
    /// </summary>
    /// <remarks>
    /// It is the one surface that cannot show a dialog — which is the whole
    /// stated reason this is answered in words — so a caller that could not say
    /// which website the teacher chose could not roll a section over at all.
    /// </remarks>
    [Fact]
    public async Task AnMcpCallerCanRollOverWithWebsiteAlone()
    {
        string said = await ReDate(website: "new");
        Assert.Contains(AssistWording.RolloverIsOnANewWebsite, said);
        Assert.False(
            File.Exists(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json")));
    }

    // ---- The scheduled publish -------------------------------------------

    /// <summary>
    /// Cutting a section loose turns off a publish set to happen on its own,
    /// and says so.
    /// </summary>
    /// <remarks>
    /// A section with no agreed website and a scheduled run has nobody to ask
    /// what the new one should be called — and <c>deploy.py</c>'s prompt
    /// returns its DEFAULT with no terminal rather than failing, so the
    /// overnight run would create a website nobody named while the address
    /// students read stopped updating. That is worse than the defect being
    /// fixed.
    /// </remarks>
    [Fact]
    public async Task StartingANewWebsiteTurnsOffAScheduledPublish()
    {
        _scheduled.Add(TaskScheduling.NameFor("ICS3U", 1));

        string said = await ReDate(rollover: "yes", website: "new");

        Assert.Contains(AssistWording.RolloverTurnedOffTheScheduledPublish, said);
        Assert.Equal(TaskScheduling.NameFor("ICS3U", 1), Assert.Single(_deleted));
    }

    /// <summary>
    /// When turning it off FAILS, the teacher is told something different —
    /// a task left behind still runs at its appointed time.
    /// </summary>
    [Fact]
    public async Task AScheduledPublishThatCouldNotBeTurnedOffSaysSo()
    {
        _scheduled.Add(TaskScheduling.NameFor("ICS3U", 1));
        _deletingFails = true;

        string said = await ReDate(rollover: "yes", website: "new");

        Assert.Contains(AssistWording.RolloverCouldNotTurnOffTheScheduledPublish, said);
        Assert.DoesNotContain(AssistWording.RolloverTurnedOffTheScheduledPublish, said);
    }

    /// <summary>A section with no scheduled publish is told nothing about one.</summary>
    [Fact]
    public async Task WithNoScheduledPublishNothingIsSaidAboutOne()
    {
        string said = await ReDate(rollover: "yes", website: "new");
        Assert.DoesNotContain("set to publish on its own", said);
    }

    /// <summary>Keeping the same website must not touch the scheduled publish.</summary>
    /// <remarks>
    /// The section still has an agreed address, so the overnight run has
    /// nothing to ask — turning it off would take away something the teacher
    /// set up, for no reason at all.
    /// </remarks>
    [Fact]
    public async Task KeepingTheSameWebsiteLeavesAScheduledPublishAlone()
    {
        _scheduled.Add(TaskScheduling.NameFor("ICS3U", 1));
        await ReDate(rollover: "yes", website: "same");
        Assert.Empty(_deleted);
    }

    // ---- The answer turn, which is the second one ------------------------

    /// <summary>
    /// Answering the question is the SECOND turn, and by then the pages are
    /// already on their dates.
    /// </summary>
    /// <remarks>
    /// The plan then changes nothing, and an early return on that made the
    /// whole answer a no-op: the reply talked about dates, never mentioned the
    /// website, and left the section pinned to last year's — with an offer that
    /// looked like it had worked.
    /// </remarks>
    [Fact]
    public async Task AnsweringOnASecondTurnStillCutsTheSectionLoose()
    {
        string asked = await ReDate(rollover: "yes");
        Assert.Contains(AssistWording.RolloverWebsiteQuestion, asked);

        // Put every page on the day it should be, so the plan now changes
        // nothing — which is the state the answer turn actually arrives in.
        await ReDate();

        string answered = await ReDate(rollover: "yes", website: "new");
        Assert.Contains(AssistWording.RolloverIsOnANewWebsite, answered);
        Assert.False(
            File.Exists(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json")),
            "The section is still pinned — the answer did nothing.");
    }

    /// <summary>
    /// The PLAN twin must still propose when only the website would change.
    /// </summary>
    /// <remarks>
    /// Plan mode is ON by default, and <c>AssistAgent.ShowPlan</c> returns
    /// early whenever the twin hands back something that is not a plan. The
    /// answer turn arrives once the dates are already right, so a twin that
    /// answers "already on the day it should be" there makes the release
    /// unreachable in the default configuration — a feature that works only
    /// for teachers who turned confirmation off.
    /// </remarks>
    [Fact]
    public async Task ThePlanTwinStillProposesWhenOnlyTheWebsiteWouldChange()
    {
        await ReDate();   // dates are right from here on

        var ordinary = await Call(apply: false);
        Assert.False(IsPlan(ordinary), "Nothing to do at all is an answer, not a proposal.");

        var rollover = await Call(apply: false, rollover: "yes", website: "new");
        Assert.True(IsPlan(rollover),
            "A rollover carrying an answer is still a plan even when the dates are already right — " +
            "otherwise AssistAgent.ShowPlan returns early and the release never runs.");
    }

    // ---- Fixture ---------------------------------------------------------

    private AssistWorkspace Open() => new(_folder, _launcher);

    private async Task<string> ReDate(string website = "", string rollover = "", bool apply = true)
    {
        var result = await Call(apply, website, rollover);
        // Both halves: the summary is what a teacher reads, the content is what
        // Claude Code reads, and a sentence in only one of them is invisible on
        // the other surface.
        return TeacherSummary(result) + "\n" + Body(result);
    }

    private Task<CallToolResult> Call(bool apply = true, string website = "", string rollover = "")
    {
        var tools = new PlantoirTools(Open());
        return apply
            ? tools.ReDateClasses("ICS3U", 1, timetable: "", block: "", cancellation: default,
                                  pages: null, meetings: null, firstDay: "", startYear: 0,
                                  website: website, rollover: rollover)
            : tools.PlanReDateClasses("ICS3U", 1, timetable: "", block: "", cancellation: default,
                                      pages: null, meetings: null, firstDay: "", startYear: 0,
                                      website: website, rollover: rollover);
    }

    private static string TeacherSummary(CallToolResult result) =>
        result.Meta?[AssistToolAnswer.TeacherSummaryKey]?.ToString() ?? "";

    private static string Body(CallToolResult result) =>
        result.Content.OfType<TextContentBlock>().FirstOrDefault()?.Text ?? "";

    private static bool IsPlan(CallToolResult result) =>
        result.Meta?[AssistToolAnswer.IsPlanKey]?.GetValue<bool>() == true;

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
        foreach (int section in sections) MarkPublished(code, section, ".netlify_sites");

        // Two classes and a remembered timetable, so a re-date has something to
        // do the first time and nothing to do afterwards.
        Class(code, "Unit 1, Day 1", "2026-09-08");
        Class(code, "Unit 1, Day 2", "2026-09-08");
        TimetableMemory.Write(_folder, code, 1,
            new[] { new DateOnly(2026, 9, 8), new DateOnly(2026, 9, 10) },
            "typed in by hand", new DateOnly(2026, 9, 8));
    }

    private void MarkPublished(string code, int section, string folder)
    {
        string directory = Path.Combine(_folder, "courses", code, folder);
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, $"section{section}.json"),
            $$"""{"name": "{{code.ToLowerInvariant()}}-s{{section}}-2026-gordon"}""");
    }

    private void Class(string course, string title, string date)
    {
        string full = Path.Combine(_folder, "courses", course, "section1", "All Classes", title + ".md");
        Directory.CreateDirectory(Path.GetDirectoryName(full)!);
        File.WriteAllText(full, $"---\ndraft: false\ncreated: {date}T07:00:00.000-0400\n---\nBody.\n");
    }
}

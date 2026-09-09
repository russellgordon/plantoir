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
        // The marker is held OPEN, so the MOVE cannot take the delete access it
        // needs and fails — deterministic, and it leaves the marker exactly
        // where it was. Shared with readers on purpose (FileShare.Read): the
        // rollover's own backup reads every file in the course first, and a
        // lock that shut it out failed the backup instead, which is a different
        // refusal and not the one being pinned.
        //
        // The first version of this blocked the move instead, by making a
        // directory at the name the kept file would take. That name has a
        // TIMESTAMP in it, so the test computed one and the code computed
        // another, and the two disagreed whenever the clock crossed a second
        // between them: an intermittent failure that would have looked exactly
        // like a production bug and was not one.
        string marker = Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json");
        using var held = new FileStream(marker, FileMode.Open, FileAccess.Read, FileShare.Read);

        var release = Open().ReleaseSite(Open().Course("ICS3U"), 1);

        Assert.False(release.ReleasedAnything);
        Assert.True(release.SomethingIsStillPinned, "The section is still pinned and must say so.");
        Assert.Equal(".netlify_sites/section1.json", Assert.Single(release.StillPinned));
        Assert.True(File.Exists(marker), "A release that failed must leave the marker where it was.");
    }

    /// <summary>
    /// The LEGACY marker is released too — the one <c>deploy.py</c> still reads
    /// and migrates back into the stable path.
    /// </summary>
    /// <remarks>
    /// Leaving it would make a rollover report "never published" and then
    /// publish over last year's site on the next deploy, in exactly the folders
    /// old enough to have taught somebody something. Netlify only: there has
    /// never been a Cloudflare equivalent.
    ///
    /// <para>This case is <c>&lt;CODE&gt;/.merged_output/section&lt;N&gt;/</c>, which is
    /// where a folder carried across from a mac has one. The path THIS platform
    /// reads is the build root's, and it is asserted separately in
    /// <see cref="RolloverLegacyMarkerInTheBuildRootTests"/> — which has to set
    /// an environment variable and so cannot live in this class.</para>
    /// </remarks>
    [Fact]
    public void TheLegacyMarkerInAMacShapedFolderIsReleasedToo()
    {
        string output = Path.Combine(_folder, "courses", "ICS3U", ".merged_output", "section1");
        Directory.CreateDirectory(output);
        File.WriteAllText(Path.Combine(output, ".netlify_site.json"), "{\"site\":\"last-year\"}");

        var release = Open().ReleaseSite(Open().Course("ICS3U"), 1);

        Assert.False(File.Exists(Path.Combine(output, ".netlify_site.json")),
            "deploy.py still reads this one and would migrate it back, so a rollover that " +
            "leaves it publishes over last year's site.");
        Assert.Contains(release.KeptFiles,
            kept => kept.Contains(".netlify_site.previous-", StringComparison.Ordinal));
        // Two markers, two entries: the stable one and the legacy one.
        Assert.Equal(2, release.KeptFiles.Count);
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

    /// <summary>
    /// A bare rollover on a section whose dates are already right STILL asks
    /// about the website — including through the plan twin, which is where the
    /// request stops in the default configuration.
    /// </summary>
    /// <remarks>
    /// Found by review. With confirmation ON, <c>AssistAgent.ShowPlan</c>
    /// returns early on a non-plan answer, so a twin that says only "everything
    /// is already on the right day" ends the turn — and the teacher is never
    /// asked, and the section stays pinned to last year's site. It is exactly
    /// the state a teacher reaches on their SECOND attempt: roll over, ignore
    /// the question, come back and ask again.
    /// </remarks>
    [Fact]
    public async Task ABareRolloverStillAsksWhenTheDatesAreAlreadyRight()
    {
        await ReDate();   // dates are right from here on

        foreach (var result in new[] { await Call(apply: false, rollover: "yes"),
                                       await Call(apply: true, rollover: "yes") })
        {
            Assert.Contains(AssistWording.RolloverWebsiteQuestion, TeacherSummary(result));
            Assert.Contains(AssistWording.RolloverWebsiteNotDecided, TeacherSummary(result));
        }
    }

    /// <summary>
    /// An ordinary re-date on a section that needs none says nothing about
    /// websites, plan or write.
    /// </summary>
    /// <remarks>
    /// The other half of the test above, and the one that would break if the
    /// question were simply moved earlier: three of the four phrasings reaching
    /// this tool are not rollovers at all.
    /// </remarks>
    [Fact]
    public async Task AnOrdinaryReDateThatChangesNothingStillSaysNothingAboutWebsites()
    {
        await ReDate();

        foreach (var result in new[] { await Call(apply: false), await Call(apply: true) })
            Assert.DoesNotContain("website", TeacherSummary(result) + Body(result),
                                  StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// A <c>website</c> value that is neither "new" nor "same" asks the
    /// question rather than being ignored.
    /// </summary>
    /// <remarks>
    /// "a new one" is an ordinary thing for a model to send. Dropping it
    /// silently would give an ordinary re-date with the website untouched and
    /// nothing said — the same silent-drop failure the schema argument is
    /// about, one layer up.
    /// </remarks>
    [Fact]
    public async Task AWebsiteValueNobodyRecognisesAsksRatherThanBeingIgnored()
    {
        string said = await ReDate(website: "a new one");

        Assert.Contains(AssistWording.RolloverWebsiteQuestion, said);
        Assert.True(
            File.Exists(Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json")),
            "A value nobody recognises must not be read as \"new\" and cut the section loose.");
    }

    // ---- roll_over_section, which is this platform's alone ----------------

    /// <summary>
    /// <c>roll_over_section</c> tells the truth when the release FAILS.
    /// </summary>
    /// <remarks>
    /// Found by review. It had its own copy of the sentences and got them wrong
    /// in the way a copy does: a marker that existed and could not be moved
    /// produced "this section had not been published anywhere yet" and "I could
    /// not move this section off …" one after the other, and then a trail line
    /// saying the section had been rolled onto a new website while it was still
    /// pinned to last year's. It shares one code path with the re-date now.
    /// </remarks>
    [Fact]
    public async Task RollOverSectionDoesNotSayNeverPublishedAboutASectionItCouldNotRelease()
    {
        string marker = Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json");
        using var held = new FileStream(marker, FileMode.Open, FileAccess.Read, FileShare.Read);

        string said = await new PlantoirTools(Open()).RollOverSection(
            "ICS3U", 1, timetable: ATimetableFile(), block: "F", cancellation: default,
            pages: null, meetings: null, firstDay: "", startYear: 2026);

        Assert.Contains(AssistWording.RolloverCouldNotStartANewWebsite(".netlify_sites/section1.json"),
                        said);
        Assert.DoesNotContain(AssistWording.RolloverHadNoWebsiteYet, said);
    }

    /// <summary>
    /// And it leaves a scheduled publish ALONE when the release failed.
    /// </summary>
    /// <remarks>
    /// A section still pinned has an agreed website, so its overnight publish
    /// has nothing to ask. Turning it off would take away something the teacher
    /// set up, on top of not doing the thing they asked for.
    /// </remarks>
    [Fact]
    public async Task RollOverSectionLeavesAScheduledPublishAloneWhenItCouldNotRelease()
    {
        _scheduled.Add(TaskScheduling.NameFor("ICS3U", 1));
        string marker = Path.Combine(_folder, "courses", "ICS3U", ".netlify_sites", "section1.json");
        using var held = new FileStream(marker, FileMode.Open, FileAccess.Read, FileShare.Read);

        await new PlantoirTools(Open()).RollOverSection(
            "ICS3U", 1, timetable: ATimetableFile(), block: "F", cancellation: default,
            pages: null, meetings: null, firstDay: "", startYear: 2026);

        Assert.Empty(_deleted);
    }

    // ---- Fixture ---------------------------------------------------------

    private AssistWorkspace Open() => new(_folder, _launcher);

    /// <summary>
    /// A two-meeting timetable on disk. <c>roll_over_section</c> takes a FILE
    /// rather than falling back to the remembered dates the way
    /// <c>re_date_classes</c> does, which is a divergence worth knowing and not
    /// this class's to fix.
    /// </summary>
    private string ATimetableFile()
    {
        string path = Path.Combine(_folder, "timetable.csv");
        File.WriteAllText(path, "F,\nSep-8,1,\nSep-10,2,\n");
        return path;
    }

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

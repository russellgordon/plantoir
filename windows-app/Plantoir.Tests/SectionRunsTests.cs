using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #728 (the mac's #706): a section's deploy belongs to the app, not to the
/// view showing the section. The rule is <c>shared-rules.json</c> →
/// <c>returningToASectionMidDeploy</c>, walked case by case at the end; the
/// view's half of it, which no model test can reach, is
/// <see cref="SectionDeployRunSourceTests"/>.
/// </summary>
[Collection(SharedActivityState.Name)]
public sealed class SectionRunsTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("plantoir-runs").FullName;
    private readonly string _otherFolder = Directory.CreateTempSubdirectory("plantoir-runs-other").FullName;
    private static readonly DateTime DeployStart = new(2026, 11, 1, 12, 0, 0, DateTimeKind.Utc);

    public SectionRunsTests()
    {
        SectionRuns.Reset();
        CourseActivity.Reset();
    }

    public void Dispose()
    {
        SectionRuns.Reset();
        CourseActivity.Reset();
        try { Directory.Delete(_folder, recursive: true); } catch { }
        try { Directory.Delete(_otherFolder, recursive: true); } catch { }
    }

    /// <summary>The same folder by another name: upper case and a trailing separator.</summary>
    private string Respelled(string folder) => folder.ToUpperInvariant() + Path.DirectorySeparatorChar;

    // ---- The key ---------------------------------------------------------

    [Fact]
    public void TwoSpellingsOfOneSectionAreOneKey()
    {
        var one = SectionKey.For(_folder, "exc2o", 1);
        var other = SectionKey.For(Respelled(_folder), "EXC2O", 1);
        Assert.Equal(one, other);
        Assert.True(one == other);
        Assert.Equal(one.GetHashCode(), other.GetHashCode());
    }

    [Fact]
    public void AnotherSectionOrFolderIsAnotherKey()
    {
        var one = SectionKey.For(_folder, "EXC2O", 1);
        Assert.NotEqual(one, SectionKey.For(_folder, "EXC2O", 2));
        Assert.NotEqual(one, SectionKey.For(_otherFolder, "EXC2O", 1));
        Assert.NotEqual(one, SectionKey.For(_folder, "ICS3U", 1));
    }

    // ---- The store -------------------------------------------------------

    /// <summary>Coming back finds the run the deploy is writing into, whoever spelled the folder.</summary>
    [Fact]
    public void ReturningFindsTheSameRun_NeverReplaced()
    {
        Assert.Null(SectionRuns.Find(_folder, "EXC2O", 1));
        var first = SectionRuns.Deploy(_folder, "EXC2O", 1);
        Assert.Same(first, SectionRuns.Deploy(Respelled(_folder), "exc2o", 1));
        Assert.Same(first, SectionRuns.Find(_folder, "EXC2O", 1));
        Assert.NotSame(first, SectionRuns.Deploy(_folder, "EXC2O", 2));
    }

    /// <summary>
    /// The in-process publish record alone makes a deploy under way for its
    /// section — a deploy the returning view's run cannot see — and leaves
    /// another section and another folder as they were.
    /// </summary>
    [Fact]
    public void UnavailableWhileThisAppDeploysTheSectionFromAnywhere()
    {
        var run = SectionRuns.Deploy(_folder, "EXC2O", 1);
        Assert.False(SectionDeployRun.UnderWay(run, _folder, "EXC2O", 1));
        using (CourseActivity.BeginPublish(_folder, "EXC2O", 1))
        {
            Assert.True(SectionDeployRun.UnderWay(run, _folder, "EXC2O", 1));
            Assert.False(SectionDeployRun.UnderWay(SectionRuns.Deploy(_folder, "EXC2O", 2), _folder, "EXC2O", 2));
            Assert.False(SectionDeployRun.UnderWay(SectionRuns.Deploy(_otherFolder, "EXC2O", 1), _otherFolder, "EXC2O", 1));
        }
        Assert.False(SectionDeployRun.UnderWay(run, _folder, "EXC2O", 1));
        run.IsPreparing = true;
        Assert.True(SectionDeployRun.UnderWay(run, _folder, "EXC2O", 1));
        run.IsPreparing = false;
    }

    /// <summary>
    /// The question about classes dated later is up in one window: the
    /// section is under way for every other window too, so a second window
    /// cannot answer a second question, back up and hide, and only then be
    /// refused (#728 plan review, finding 1; <c>classesDatedLater.order</c>).
    /// </summary>
    [Fact]
    public void AQuestionUpInOneWindow_MakesTheSectionUnderWayInEveryWindow()
    {
        var asking = SectionRuns.Deploy(_folder, "EXC2O", 1);
        var secondWindow = SectionRuns.Deploy(Respelled(_folder), "EXC2O", 1);
        asking.IsAsking = true;
        Assert.True(SectionDeployRun.UnderWay(secondWindow, _folder, "EXC2O", 1));
        Assert.False(secondWindow.IsShown(null), "a question being asked is not a deploy to show");
        asking.IsAsking = false;
        Assert.False(SectionDeployRun.UnderWay(secondWindow, _folder, "EXC2O", 1));
    }

    /// <summary>
    /// The deploy's claims are the RUN's, not a view's: a view taken off screen
    /// cannot give them back, and EndPublish gives back every one. The ending
    /// is announced AFTER the publish has ended, so a view redrawing on it
    /// sees Deploy available.
    /// </summary>
    [Fact]
    public void TheEndingIsAnnouncedAfterThePublishEnds()
    {
        var run = SectionRuns.Deploy(_folder, "EXC2O", 1);
        var build = new Disposed();
        var publish = new Disposed();
        run.Hold(build, publish, CourseActivity.BeginPublish(_folder, "EXC2O", 1), null);
        Assert.Equal(3, run.ClaimsHeld);
        bool? underWayWhenAnnounced = null;
        run.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(SectionDeployRun.Endings))
                underWayWhenAnnounced = SectionDeployRun.UnderWay(run, _folder, "EXC2O", 1);
        };
        run.EndPublish();
        run.NoteEnded(Array.Empty<SiteHealthFinding>(), null);
        Assert.True(build.Done && publish.Done);
        Assert.Equal(0, run.ClaimsHeld);
        Assert.False(underWayWhenAnnounced, "Deploy was still unavailable when the ending was announced");
        run.EndPublish();   // twice is harmless
    }

    [Fact]
    public void WhatTheDeployLeftIsTakenOnce()
    {
        var run = SectionRuns.Deploy(_folder, "EXC2O", 1);
        var marker = new LinksChecklistMarker("EXC2O", 1, "build-1", 3);
        run.NoteEnded(Array.Empty<SiteHealthFinding>(), marker);
        var taken = run.TakeEnding();
        Assert.NotNull(taken);
        Assert.Equal(1, taken!.Number);
        Assert.Equal(marker, taken.LinksMarker);
        Assert.Null(run.TakeEnding());
    }

    /// <summary>A finished deploy is shown until one view has displayed its ending; a new ending is shown again.</summary>
    [Fact]
    public void AnEndingOnceShownIsNotShownAgain()
    {
        var run = SectionRuns.Deploy(_folder, "EXC2O", 1);
        run.Runner.SetStateForTests(false, DeployStart);
        Assert.False(run.IsShown(run.EndingToHideOnAppearing()), "nothing has ever ended");
        run.NoteEnded(Array.Empty<SiteHealthFinding>(), null);
        Assert.True(run.IsShown(run.EndingToHideOnAppearing()), "the first view after the ending shows it");
        run.NoteEndingShown();
        Assert.True(run.IsShown(null), "the view that showed it goes on showing it");
        Assert.False(run.IsShown(run.EndingToHideOnAppearing()), "a view appearing after it was shown");
        run.NoteEnded(Array.Empty<SiteHealthFinding>(), null);
        Assert.True(run.IsShown(run.EndingToHideOnAppearing()), "a NEW ending is shown");
    }

    /// <summary>A preview of the section started after the deploy wins, whichever window started it.</summary>
    [Fact]
    public void ALaterPreviewWinsOverAFinishedDeploy()
    {
        var run = SectionRuns.Deploy(_folder, "EXC2O", 1);
        run.Runner.SetStateForTests(false, DeployStart);
        run.NoteEnded(Array.Empty<SiteHealthFinding>(), null);
        Assert.True(run.IsShown(null));
        Assert.False(run.IsShown(null, previewStartedAt: DeployStart.AddMinutes(1)), "this view's own later preview");
        Assert.True(run.IsShown(null, previewStartedAt: DeployStart.AddMinutes(-1)), "an earlier preview");
        run.NotePreviewStarted(DeployStart.AddHours(3));
        Assert.False(run.IsShown(null), "a returning view has no preview start of its own: the section's decides");
        run.Runner.SetStateForTests(true, DeployStart.AddHours(4));
        Assert.True(run.IsShown(null), "a running deploy is always shown");
    }

    // ---- The contract ----------------------------------------------------

    public static IEnumerable<object[]> Cases() =>
        ContractLoader.LoadJson("shared-rules.json")["returningToASectionMidDeploy"]!["cases"]!.AsArray()
            .Select(c => new object[] { $"{c!["startedBy"]} / {c["then"]}", c.ToJsonString() });

    [Fact]
    public void TheContractHasElevenCases() =>
        Assert.Equal(11, ContractLoader.LoadJson("shared-rules.json")["returningToASectionMidDeploy"]!["cases"]!.AsArray().Count);

    /// <summary>
    /// <c>returningToASectionMidDeploy.cases</c>, each set up as its
    /// <c>startedBy</c> says and asked as a returning view asks (the mac's
    /// <c>testReturningToASectionMidDeployCases</c>).
    /// <para><c>theAssistantWithNoWindow</c> is a SIMULATION OF THE RULE ONLY
    /// on this side: a publish record with no run. Windows' in-app assistant
    /// always deploys through a section window (<c>AssistWindow.MainWindowForBuilds</c>
    /// opens one), so in practice that deploy IS the section's run and is
    /// shown; the case pins what a record with no run must do
    /// (documentation/12-windows-app.md, "A section's deploy outlives its view").</para>
    /// </summary>
    [Theory]
    [MemberData(nameof(Cases))]
    public void ReturningToASectionMidDeploy(string label, string json)
    {
        SectionRuns.Reset();
        CourseActivity.Reset();
        var c = JsonNode.Parse(json)!;
        string startedBy = c["startedBy"]!.ToString();
        string then = c["then"]!.ToString();

        string startedFolder = _folder;
        int startedSection = 1;
        bool startedWithTheRun = true;
        switch (startedBy)
        {
            case "thisSectionBeforeLeaving": break;
            case "anotherWindowSameFolder": startedFolder = Respelled(_folder); break;   // the folder reached by another name
            case "theAssistantWithNoWindow": startedWithTheRun = false; break;            // simulation of the rule only
            case "anotherSection": startedSection = 2; break;
            case "anotherWorkingFolder": startedFolder = _otherFolder; break;
            default: Assert.Fail($"{label}: a startedBy this test does not know"); break;
        }
        SectionDeployRun? started = startedWithTheRun ? SectionRuns.Deploy(startedFolder, "EXC2O", startedSection) : null;
        started?.Runner.SetStateForTests(false, DeployStart);
        IDisposable? record = null;
        switch (then)
        {
            case "returned":
                started?.Runner.SetStateForTests(true, DeployStart);
                record = CourseActivity.BeginPublish(startedFolder, "EXC2O", startedSection);
                break;
            case "finishedWhileAway":
                started?.NoteEnded(Array.Empty<SiteHealthFinding>(), null);
                break;
            case "watchedToTheEndThenPreviewed":
                started?.NoteEnded(Array.Empty<SiteHealthFinding>(), null);
                started?.NoteEndingShown();
                started?.NotePreviewStarted(DeployStart.AddMinutes(1));
                break;
            case "watchedToTheEnd":
                started?.NoteEnded(Array.Empty<SiteHealthFinding>(), null);
                started?.NoteEndingShown();
                break;
            case "finishedWhileAwayThenPreviewedFromAnotherWindow":
                started?.NoteEnded(Array.Empty<SiteHealthFinding>(), null);
                started?.NotePreviewStarted(DeployStart.AddMinutes(1));
                break;
            default: Assert.Fail($"{label}: a then this test does not know"); break;
        }

        // The teacher comes back to section 1 of the first folder.
        var returning = SectionRuns.Deploy(_folder, "EXC2O", 1);
        bool underWay = SectionDeployRun.UnderWay(returning, _folder, "EXC2O", 1);
        bool showsTheRun = started is not null && ReferenceEquals(started, returning)
                           && returning.IsShown(returning.EndingToHideOnAppearing());

        Assert.True(c["deployAvailable"]!.GetValue<bool>() == !underWay, $"{label}: deployAvailable");
        Assert.True(c["showsTheRun"]!.GetValue<bool>() == showsTheRun, $"{label}: showsTheRun");
        // Coming back asks the store and nothing else; SectionDeployRunSourceTests holds the view to that.
        Assert.False(c["selectingStartsALauncher"]!.GetValue<bool>(), $"{label}: selecting never starts anything");
        // A press reaches a launcher only when DeployAsync's first busy check lets it through.
        Assert.True(c["aPressStartsALauncher"]!.GetValue<bool>() == !underWay, $"{label}: aPressStartsALauncher");
        record?.Dispose();
        started?.Runner.SetStateForTests(false, null);
    }

    private sealed class Disposed : IDisposable
    {
        public bool Done { get; private set; }
        public void Dispose() => Done = true;
    }
}

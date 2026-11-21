using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

/// <summary>
/// #928 (the mac's #812 and #813): a preview build recorded per start, a run
/// that never started, and a repair's Preview Again that survives its stop.
/// <c>contracts/shared-rules.json</c> →
/// <c>quittingWhileWorkIsUnderWay.previewBuildRecord</c>, every case read
/// from the JSON and walked through the real <see cref="PreviewStarts"/>,
/// <see cref="PreviewAgainPresses"/>, <see cref="CourseActivity"/>,
/// <see cref="PreviewLeases"/> and <see cref="QuitConfirmation"/>, in the
/// order <c>SectionDetailView</c> takes the steps.
/// </summary>
[Collection(SharedActivityState.Name)]
public class PreviewStartRecordTests : IDisposable
{
    private const string Folder = @"C:\plantoir-preview-build-record";
    private const string Course = "ICS3U";
    private const int Section = 1;

    /// <summary>One section window, as far as its start goes.</summary>
    private sealed class Window
    {
        public PreviewLeases.Lease? Lease;
        public IDisposable? Record;
        public bool IsWaiting;
    }

    private sealed class Counted
    {
        public int Refusals;
        public int AlreadyStarting;
    }

    public PreviewStartRecordTests()
    {
        CourseActivity.Reset();
        PreviewLeases.Reset();
    }

    public void Dispose()
    {
        CourseActivity.Reset();
        PreviewLeases.Reset();
    }

    private static JsonNode Block() =>
        ContractLoader.LoadJson("shared-rules.json")["quittingWhileWorkIsUnderWay"]!["previewBuildRecord"]!;

    /// <summary>The press path's steps: asked first whether the window's own start is under way, then the lease and this start's record.</summary>
    private static void Start(Window window, Counted counted)
    {
        if (PreviewStarts.AStartIsUnderWay(window.Record is not null || window.IsWaiting, window.Lease))
        {
            counted.AlreadyStarting++;
            return;
        }
        var began = PreviewStarts.Begin(Folder, Course, Section, owner: window);
        if (began.Refusal is not null)
        {
            counted.Refusals++;
            return;
        }
        window.Lease = began.Lease;
        window.Record = began.Record;
        window.IsWaiting = true;
    }

    /// <summary>A start ending however it ends: AbandonWait and ReleaseLease's steps.</summary>
    private static void RunEnds(Window window)
    {
        window.IsWaiting = false;
        window.Record?.Dispose();
        window.Record = null;
        if (window.Lease is { } lease) PreviewLeases.Release(lease);
        window.Lease = null;
    }

    /// <summary>The wait meets a run that returned without starting.</summary>
    private static void CouldNotStart(Window window, Counted counted)
    {
        switch (PreviewStarts.HowTheRunStands(isRunning: false, lastExitCode: null,
                                              launchProblem: "a launch problem invented for this test"))
        {
            case PreviewStarts.RunStanding.CouldNotStart:
                RunEnds(window);
                counted.Refusals++;
                break;
            case PreviewStarts.RunStanding.Ended:
                RunEnds(window);
                break;
            case PreviewStarts.RunStanding.UnderWay:
                break;
        }
    }

    private static int Records() => CourseActivity.UnderWay().PreviewsBeingBuilt;

    private static bool QuitAsks() =>
        QuitConfirmation.ShouldAsk(CourseActivity.UnderWay(), QuitConfirmation.Reason.TheTeacherAskedToQuit);

    [Fact]
    public void EveryPressCase()
    {
        var cases = Block()["pressCases"]!.AsArray();
        Assert.True(cases.Count >= 11, $"only {cases.Count} press cases");
        foreach (var entry in cases)
        {
            CourseActivity.Reset();
            PreviewLeases.Reset();
            string name = entry!["name"]!.ToString();
            var expect = entry["expect"]!;
            var a = new Window();
            var b = new Window();
            IDisposable? assistant = null;
            var counted = new Counted();
            foreach (var step in entry["steps"]!.AsArray())
            {
                switch (step!.ToString())
                {
                    case "A.start": Start(a, counted); break;
                    case "B.start": Start(b, counted); break;
                    case "A.runEnds": RunEnds(a); break;
                    case "B.runEnds": RunEnds(b); break;
                    case "A.couldNotStart": CouldNotStart(a, counted); break;
                    case "assistant.begins": assistant = CourseActivity.BeginPreviewBuild(Folder, Course, Section); break;
                    case "assistant.ends": assistant?.Dispose(); assistant = null; break;
                    default: Assert.Fail($"{name}: no step {step}"); break;
                }
            }
            int records = expect["records"]!.GetValue<int>();
            Assert.True(records == Records(), $"{name}: records {Records()}, expected {records}");
            Assert.True(expect["refusals"]!.GetValue<int>() == counted.Refusals, $"{name}: refusals {counted.Refusals}");
            Assert.True(expect["alreadyStarting"]!.GetValue<int>() == counted.AlreadyStarting,
                        $"{name}: alreadyStarting {counted.AlreadyStarting}");
            Assert.True(expect["aIsWaiting"]!.GetValue<bool>() == a.IsWaiting, $"{name}: aIsWaiting {a.IsWaiting}");
            Assert.True(QuitAsks() == records > 0, $"{name}: what a quit would ask");
        }
    }

    [Fact]
    public async Task EveryPreviewAgainCase()
    {
        var cases = Block()["previewAgainCases"]!.AsArray();
        Assert.True(cases.Count >= 10, $"only {cases.Count} Preview Again cases");
        foreach (var entry in cases)
        {
            CourseActivity.Reset();
            PreviewLeases.Reset();
            string name = entry!["name"]!.ToString();
            bool previewRunning = entry["previewRunning"]!.GetValue<bool>();
            var expect = entry["expect"]!;
            var store = new PreviewAgainPresses();
            var page = new Window();
            Guid owner = Guid.NewGuid();
            Guid otherPage = Guid.NewGuid();
            store.Press(otherPage);
            var counted = new Counted();
            int stops = 0, startsAsked = 0;
            if (previewRunning)
            {
                // A preview showing: the lease held and the wait over.
                Start(page, counted);
                page.Record?.Dispose();
                page.Record = null;
                page.IsWaiting = false;
            }
            Guid token = store.Press(owner);
            await PreviewAgainPresses.CarryOutAsync(store, owner, token, Course, Section, previewRunning,
                stop: async () =>
                {
                    stops++;
                    RunEnds(page);
                    foreach (var happening in entry["duringTheStop"]!.AsArray())
                    {
                        switch (happening!.ToString())
                        {
                            case "oldRunEnds": page.IsWaiting = false; break;
                            case "anotherWindowLeaves": store.Abandon(otherPage); break;
                            case "leave": store.Abandon(owner); RunEnds(page); break;
                            case "quit": store.AbandonEvery(); RunEnds(page); break;
                            case "pressAgain":
                                Guid second = store.Press(owner);
                                await PreviewAgainPresses.CarryOutAsync(store, owner, second, Course, Section, false,
                                    stop: () => { Assert.Fail($"{name}: the second press had nothing to stop"); return Task.CompletedTask; },
                                    start: () => { startsAsked++; Start(page, counted); });
                                store.Finish(second, owner);
                                break;
                            case "teacherStartsAPreview": Start(page, counted); break;
                            default: Assert.Fail($"{name}: no event {happening}"); break;
                        }
                    }
                },
                start: () => { startsAsked++; Start(page, counted); });
            store.Finish(token, owner);
            Assert.True(expect["stops"]!.GetValue<int>() == stops, $"{name}: stops {stops}");
            Assert.True(expect["startsAsked"]!.GetValue<int>() == startsAsked, $"{name}: startsAsked {startsAsked}");
            Assert.True(expect["records"]!.GetValue<int>() == Records(), $"{name}: records {Records()}");
            Assert.True(expect["alreadyStarting"]!.GetValue<int>() == counted.AlreadyStarting,
                        $"{name}: alreadyStarting {counted.AlreadyStarting}");
            Assert.True(counted.Refusals == 0, $"{name}: nothing is refused");
            Assert.False(store.UnderWay.ContainsKey(owner), $"{name}: the press is over");
        }
    }

    /// <summary>The window's own claims and the assistant's count the section once (whatCountsAsUnderWay).</summary>
    [Fact]
    public void ASectionWithTwoClaimsIsOnePreviewBeingBuilt()
    {
        using var assistant = CourseActivity.BeginPreviewBuild(Folder, Course, Section);
        using var window = CourseActivity.BeginPreviewBuild(Folder, Course, Section);
        Assert.Equal(1, Records());
    }

    [Fact]
    public void HowTheRunStands()
    {
        Assert.Equal(PreviewStarts.RunStanding.UnderWay, PreviewStarts.HowTheRunStands(true, null, null));
        Assert.Equal(PreviewStarts.RunStanding.UnderWay, PreviewStarts.HowTheRunStands(false, null, null));
        Assert.Equal(PreviewStarts.RunStanding.Ended, PreviewStarts.HowTheRunStands(false, 0, null));
        Assert.Equal(PreviewStarts.RunStanding.CouldNotStart, PreviewStarts.HowTheRunStands(false, null, "x"));
        // The folder's tools not ready sets both: the problem is this run's.
        Assert.Equal(PreviewStarts.RunStanding.CouldNotStart, PreviewStarts.HowTheRunStands(false, -1, "x"));
    }

    [Fact]
    public void AParkedStartRunsOnlyWhileItStillBelongs()
    {
        Guid start = Guid.NewGuid();
        Assert.True(PreviewStarts.TheStartStillBelongs(start, start, viewIsGone: false, appIsQuitting: false));
        Assert.False(PreviewStarts.TheStartStillBelongs(Guid.NewGuid(), start, false, false));
        Assert.False(PreviewStarts.TheStartStillBelongs(start, start, viewIsGone: true, appIsQuitting: false));
        Assert.False(PreviewStarts.TheStartStillBelongs(start, start, viewIsGone: false, appIsQuitting: true));
    }

    /// <summary>
    /// The review's M2: two windows, one section. Window B's sweep for rows
    /// it left behind (what its Rebuild Preview runs before it takes) leaves
    /// window A's lease, so B is refused and A keeps its port; and A's
    /// release, once A has let go and taken again, removes only the lease it
    /// still holds.
    /// </summary>
    [Fact]
    public void AnotherWindowsStartNeverEndsThisWindowsLease()
    {
        var windowA = new object();
        var windowB = new object();
        var a = PreviewStarts.Begin(Folder, Course, Section, owner: windowA);
        Assert.NotNull(a.Lease);

        PreviewLeases.ReleaseLeftBehind(windowB, Folder, Course, Section);
        var b = PreviewStarts.Begin(Folder, Course, Section, owner: windowB);

        Assert.NotNull(b.Refusal);
        Assert.Null(b.Lease);
        Assert.Equal(new[] { a.Lease }, PreviewLeases.Active.ToArray());
        Assert.Equal(1, Records());

        // A window's own left-behind row is its own to sweep.
        PreviewLeases.ReleaseLeftBehind(windowA, Folder, Course, Section);
        Assert.Empty(PreviewLeases.Active);
        a.Record!.Dispose();
    }

    /// <summary>A start that already let go never removes a later lease equal to its own in every field.</summary>
    [Fact]
    public void AReleaseRemovesOnlyTheLeaseItsStartTook()
    {
        var window = new object();
        var first = PreviewLeases.Take(Folder, Course, Section, window);
        PreviewLeases.Release(first);
        var second = PreviewLeases.Take(Folder, Course, Section, window);
        Assert.Equal(first, second);   // the same window, section and port: equal, not the same

        PreviewLeases.Release(first);

        Assert.Equal(new[] { second }, PreviewLeases.Active.ToArray());
    }

    /// <summary>A start holds its own only by reference and while it is the latest.</summary>
    [Fact]
    public void AStartHoldsItsOwnLeaseByReference()
    {
        var window = new object();
        var first = new PreviewLeases.Lease(8081, Folder, Course, Section, window);
        var second = new PreviewLeases.Lease(8081, Folder, Course, Section, window);
        Assert.True(PreviewStarts.TheStartStillHoldsItsOwn(second, second, Guid.Empty, Guid.Empty));
        Assert.False(PreviewStarts.TheStartStillHoldsItsOwn(second, first, Guid.Empty, Guid.Empty));
        Assert.False(PreviewStarts.TheStartStillHoldsItsOwn(second, second, Guid.NewGuid(), Guid.Empty));
    }

    /// <summary>The review's L1: a press during the window's own stop is not a start under way.</summary>
    [Fact]
    public void APressDuringAStopIsNotAStartUnderWay()
    {
        var lease = PreviewLeases.Take(Folder, Course, Section, new object());
        Assert.Equal(PreviewStarts.PressMeets.AStopUnderWay,
                     PreviewStarts.WhatAPressMeets(aStopIsUnderWay: true, startHasBegun: true, heldLease: lease));
        Assert.Equal(PreviewStarts.PressMeets.AStartUnderWay,
                     PreviewStarts.WhatAPressMeets(aStopIsUnderWay: false, startHasBegun: true, heldLease: lease));
        Assert.Equal(PreviewStarts.PressMeets.Nothing,
                     PreviewStarts.WhatAPressMeets(aStopIsUnderWay: false, startHasBegun: false, heldLease: lease));
    }

    /// <summary>The later press finished first and cleared its own entry: the earlier still says it was replaced.</summary>
    [Fact]
    public async Task AReplacedPressSaysItWasReplaced()
    {
        var store = new PreviewAgainPresses();
        Guid owner = Guid.NewGuid();
        Guid first = store.Press(owner);
        PreviewAgainPresses.Ending? secondEnding = null;
        var ending = await PreviewAgainPresses.CarryOutAsync(store, owner, first, Course, Section, true,
            stop: async () =>
            {
                Guid second = store.Press(owner);
                secondEnding = await PreviewAgainPresses.CarryOutAsync(store, owner, second, Course, Section, false,
                    stop: () => Task.CompletedTask, start: () => { });
                store.Finish(second, owner);
            },
            start: () => Assert.Fail("the replaced press started"));
        store.Finish(first, owner);
        Assert.Equal(PreviewAgainPresses.Ending.Started, secondEnding);
        Assert.Equal(PreviewAgainPresses.Ending.Replaced, ending);
    }

    // ---- The view asks the model (source reading) ----------------------

    private static string ViewSource() =>
        Regex.Replace(Regex.Replace(File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot,
            "windows-app", "Plantoir", "Views", "SectionDetailView.xaml.cs")), @"/\*.*?\*/", "", RegexOptions.Singleline),
            @"//[^\n]*", "");

    private static string Body(string code, string header)
    {
        int at = code.IndexOf(header, StringComparison.Ordinal);
        Assert.True(at >= 0, $"'{header}' is no longer in SectionDetailView.xaml.cs");
        int open = code.IndexOf('{', at);
        int depth = 0;
        for (int i = open; i < code.Length; i++)
        {
            if (code[i] == '{') depth++;
            else if (code[i] == '}' && --depth == 0) return code[open..(i + 1)];
        }
        throw new InvalidOperationException("unbalanced braces");
    }

    /// <summary>
    /// Both starts ask whether one is under way before anything is taken,
    /// take through <see cref="PreviewStarts.Begin"/> (never a record of
    /// their own over a held one), and park, then ask whether they still
    /// belong, before the launcher.
    /// </summary>
    [Theory]
    [InlineData("private async Task PressPreviewAsync(")]
    [InlineData("private async void StartAutomatedPreview(")]
    public void EveryStartAsksTheModelInItsOrder(string header)
    {
        string body = Body(ViewSource(), header);
        int underWay = body.IndexOf("SaidAStartIsAlreadyUnderWay()", StringComparison.Ordinal);
        int begin = body.IndexOf("PreviewStarts.Begin(", StringComparison.Ordinal);
        int park = body.IndexOf("PreviewStopper.WaitForStopsToFinish(", StringComparison.Ordinal);
        int belongs = body.IndexOf("TheParkedStartStillBelongs(", StringComparison.Ordinal);
        int run = body.IndexOf("_previewRunner.Run(", StringComparison.Ordinal);
        Assert.True(underWay >= 0 && underWay < begin, "the start does not ask first whether one is under way");
        Assert.True(begin < park && park < belongs && belongs < run, "the parked start does not ask whether it still belongs");
        Assert.DoesNotContain("PreviewLeases.Take(", body);
        Assert.DoesNotContain("CourseActivity.BeginPreviewBuild(", body);
    }

    /// <summary>The view's side of M2: its one release sweeps only this window's rows, and both starts take as this window.</summary>
    [Fact]
    public void TheViewReleasesOnlyItsOwnWindowsLeases()
    {
        string code = ViewSource();
        string release = Body(code, "private void ReleaseLease(");
        Assert.Contains("PreviewLeases.ReleaseLeftBehind(_window,", release);
        Assert.DoesNotMatch(@"PreviewLeases\.Release\(\s*wp", release);
        Assert.Equal(2, Regex.Matches(code, @"PreviewStarts\.Begin\([^;]*owner:\s*_window\)").Count);
    }

    /// <summary>The view's side of L1: the press asks about a stop under way, which the stop counts.</summary>
    [Fact]
    public void ThePressAsksWhetherTheWindowsStopIsUnderWay()
    {
        string code = ViewSource();
        Assert.Contains("aStopIsUnderWay: _stopsUnderWay > 0", Body(code, "private bool SaidAStartIsAlreadyUnderWay("));
        Assert.Contains("_stopsUnderWay++", Body(code, "public async Task StopPreviewAsync("));
    }

    /// <summary>The view's side of L2 and L5: an exception in either start hands back what it holds, and the repair's refusal after the stop is caught.</summary>
    [Fact]
    public void AFailedStartHandsBackWhatItHolds()
    {
        string code = ViewSource();
        foreach (string header in new[] { "private async Task PressPreviewAsync(", "private async void StartAutomatedPreview(" })
        {
            string body = Body(code, header);
            int caught = body.LastIndexOf("catch (Exception ex)", StringComparison.Ordinal);
            Assert.True(caught >= 0 && body.IndexOf("HandBackAfterAFailure(heldLease, heldStart)", caught, StringComparison.Ordinal) > caught,
                        $"{header}: an exception does not hand back what the start holds");
        }
        Assert.DoesNotContain("_ = PresentRepairOutcomeAsync(", Body(code, "private void StartPreviewAgainAfterTheStop("));
    }

    [Fact]
    public void TheWaitEndsARunThatNeverStartedAndTheRepairCarriesItsPress()
    {
        string code = ViewSource();
        Assert.Contains("PreviewStarts.HowTheRunStands(", Body(code, "private async Task WaitForPreviewServer("));
        string repair = Body(code, "private async Task PreviewAgainAfterRepairAsync(");
        int press = repair.IndexOf("PreviewAgainPresses.Shared.Press(", StringComparison.Ordinal);
        int firstAwait = repair.IndexOf("await ", StringComparison.Ordinal);
        Assert.True(press >= 0 && press < firstAwait, "the press is not recorded before anything is awaited");
        Assert.Contains("PreviewAgainPresses.CarryOutAsync(", repair);
        Assert.Contains("PreviewAgainPresses.Shared.Abandon(_previewAgainOwner)", Body(code, "private void OnUnloaded("));
    }
}

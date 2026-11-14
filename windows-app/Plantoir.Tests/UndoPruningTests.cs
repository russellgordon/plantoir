using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// The limits, pruning and deletion as pure decisions (<c>undo.rule.limits</c>,
/// <c>undoJournal.files</c>, <c>unknown.deleting</c>, #899 piece W1), with the
/// clock passed in. The stack cases walk the same functions end to end; these
/// pin the parts no stack case reaches: deletion of segments.
/// </summary>
public sealed class UndoPruningTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 14, 12, 0, 0, TimeSpan.Zero);

    private static string Moment(double daysAgo) => UndoMoment.Format(Now - TimeSpan.FromDays(daysAgo));

    private static string Begin(long seq, double daysAgo = 0, long pid = 1) =>
        $"{{\"v\":1,\"seq\":{seq},\"event\":\"begin\",\"at\":\"{Moment(daysAgo)}\",\"process\":{{\"pid\":{pid}}}," +
        $"\"step\":{{\"seq\":{seq},\"madeAt\":\"{Moment(daysAgo)}\",\"ops\":[]}}}}";

    private static string Event(long seq, string name, double daysAgo = 0) =>
        $"{{\"v\":1,\"seq\":{seq},\"event\":\"{name}\",\"at\":\"{Moment(daysAgo)}\"}}";

    private static UndoFolded Fold(params (int Segment, string Line)[] lines) =>
        UndoFold.Fold(lines.Select((line, place) => UndoFormat.Parse(line.Line, line.Segment, place)));

    [Fact]
    public void ThePruningDecisionTakesOneOldestRunAndStopsAtAStepKept()
    {
        var lines = new List<(int, string)>();
        for (long seq = 1; seq <= 53; seq++) { lines.Add((1, Begin(seq))); lines.Add((1, Event(seq, "applied"))); }
        var actions = UndoPruning.Decide(Fold([.. lines]), Now, _ => false);
        Assert.Equal([1L, 2, 3], actions.Select(action => action.Seq));
        Assert.All(actions, action => Assert.Equal("tooMany", Assert.IsType<UndoPruneAction.Pruned>(action).Reason));
    }

    [Fact]
    public void NothingIsPrunedForAgeWhileTheClockIsBehindTheJournal()
    {
        // Step 2 was written 3 days "in the future" of this clock: the clock is behind.
        UndoFolded folded = Fold((1, Begin(1, 70)), (1, Event(1, "applied", 70)), (1, Begin(2, -3)), (1, Event(2, "applied", -3)));
        Assert.Empty(UndoPruning.Decide(folded, Now, _ => false));
        UndoFolded trusted = Fold((1, Begin(1, 70)), (1, Event(1, "applied", 70)), (1, Begin(2)), (1, Event(2, "applied")));
        Assert.Equal("tooOld", Assert.IsType<UndoPruneAction.Pruned>(Assert.Single(UndoPruning.Decide(trusted, Now, _ => false))).Reason);
    }

    [Fact]
    public void ARunningProcessesStepInFlightStopsTheRunAndADeadOnesIsClosedUnsettled()
    {
        var lines = new List<(int, string)> { (1, Begin(1, 70, pid: 77)) };
        for (long seq = 2; seq <= 3; seq++) { lines.Add((1, Begin(seq))); lines.Add((1, Event(seq, "applied"))); }
        UndoFolded folded = Fold([.. lines]);
        Assert.Empty(UndoPruning.Decide(folded, Now, process => process?.Pid == 77));
        var closed = Assert.IsType<UndoPruneAction.ClosedUnsettled>(Assert.Single(UndoPruning.Decide(folded, Now, _ => false)));
        Assert.Equal(1, closed.Seq);
        Assert.Equal(UndoPhase.Begin, closed.Phase);
    }

    [Fact]
    public void ASegmentGoesFromTheOldestEndOnlyWhenNothingOnTheListHasAnEventInIt()
    {
        UndoFolded folded = Fold(
            (1, Begin(1)), (1, Event(1, "applied")), (1, Event(1, "pruned")),
            (2, Begin(2)), (2, Event(2, "applied")),
            (3, Begin(3)), (3, Event(3, "applied")));
        Assert.Equal([1], UndoPruning.Deletable(folded, [1, 2, 3], [], Now).Segments);

        // Step 2 still on the list holds its segment, and so every newer one.
        UndoFolded holding = Fold((1, Begin(1)), (1, Event(1, "applied")), (2, Begin(2)), (2, Event(2, "applied")), (3, Begin(3)), (3, Event(3, "applied")));
        Assert.Empty(UndoPruning.Deletable(holding, [1, 2, 3], [], Now).Segments);
    }

    [Fact]
    public void TheNewestSegmentIsNeverDeleted()
    {
        UndoFolded folded = Fold((1, Begin(1)), (1, Event(1, "applied")), (1, Event(1, "pruned")));
        Assert.Empty(UndoPruning.Deletable(folded, [1], [], Now).Segments);
    }

    [Fact]
    public void ASegmentHoldingAnUnreadableLineGoesOnlyOnceItsOwnNewestTimeIsPastSixtyDays()
    {
        string foreign = $"{{\"v\":2,\"seq\":2,\"event\":\"x\",\"at\":\"{Moment(59)}\"}}";
        UndoFolded young = Fold((1, Begin(1, 59)), (1, Event(1, "applied", 59)), (1, Event(1, "pruned", 59)), (1, foreign), (2, Begin(3)), (2, Event(3, "applied")));
        Assert.Empty(UndoPruning.Deletable(young, [1, 2], [], Now).Segments);

        string old = $"{{\"v\":2,\"seq\":2,\"event\":\"x\",\"at\":\"{Moment(61)}\"}}";
        UndoFolded aged = Fold((1, Begin(1, 61)), (1, Event(1, "applied", 61)), (1, Event(1, "pruned", 61)), (1, old), (2, Begin(3)), (2, Event(3, "applied")));
        Assert.Equal([1], UndoPruning.Deletable(aged, [1, 2], [], Now).Segments);
    }

    [Fact]
    public void ASegmentWithNoReadableTimeIsJudgedByTheFirstLaterOneThatHasOne()
    {
        // Segment 1 holds only an unreadable line with no time at all.
        UndoFolded judgedOld = Fold((1, "garbage"), (2, Begin(1, 61)), (2, Event(1, "applied", 61)), (2, Event(1, "pruned", 61)), (3, Begin(2)), (3, Event(2, "applied")));
        Assert.Equal([1, 2], UndoPruning.Deletable(judgedOld, [1, 2, 3], [], Now).Segments);

        // Kept while no later segment has a time (before the third round's rule it kept itself and all later ones for good).
        UndoFolded noTimeAnywhere = Fold((1, "garbage"), (2, "{\"v\":1,\"seq\":1,\"event\":\"note\"}"));
        Assert.Empty(UndoPruning.Deletable(noTimeAnywhere, [1, 2], [], Now).Segments);
    }

    [Fact]
    public void ABlobGoesOnlyWhenNothingKeptNamesIt()
    {
        string kept = new('1', 64);
        string byUnreadable = new('2', 64);
        string loose = new('3', 64);
        string step = $"{{\"v\":1,\"seq\":1,\"event\":\"begin\",\"at\":\"{Moment(0)}\",\"step\":{{\"seq\":1,\"madeAt\":\"{Moment(0)}\"," +
                      $"\"workingFolder\":{{\"id\":\"x\",\"pathAtTheTime\":\"p\"}},\"ops\":[{{\"kind\":\"writeFile\",\"path\":\"a.md\",\"afterSha\":\"{kept}\",\"blobs\":[\"{kept}\"]}}]}}}}";
        string foreign = $"{{\"v\":2,\"seq\":2,\"event\":\"x\",\"blob\":\"{byUnreadable}\"}}";
        UndoFolded folded = Fold((1, step), (1, Event(1, "applied")), (1, foreign));
        Assert.Equal([loose], UndoPruning.Deletable(folded, [1], [kept, byUnreadable, loose], Now).Blobs);

        UndoFolded pruned = Fold((1, step), (1, Event(1, "applied")), (1, Event(1, "pruned")));
        Assert.Equal([kept], UndoPruning.Deletable(pruned, [1], [kept], Now).Blobs);
    }

    [Theory]
    [InlineData(0.5, true)]    // half a day ahead: trusted
    [InlineData(2, false)]     // two days ahead: not trusted
    public void TheListIsJudgedAtAStepTimeUpToADayAheadOfTheClock(double daysAhead, bool trusted)
    {
        DateTimeOffset judged = UndoLimits.JudgedAt(Now, [Now + TimeSpan.FromDays(daysAhead)]);
        Assert.Equal(trusted ? Now + TimeSpan.FromDays(daysAhead) : Now, judged);
    }
}

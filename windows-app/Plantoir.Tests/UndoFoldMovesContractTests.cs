using System.Text.Json;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/file-formats.json</c> → <c>undoJournal.folding.moves</c>: the
/// table the fold is written from (#899 piece W1). The product's
/// <see cref="UndoFold.Moves"/> must be the contract's rows, word for word and
/// in order, so a row the mac adds or rewords is red here; and every row is
/// exercised against <see cref="UndoFold.Fold"/>, with the state it must reach
/// read from the row itself.
/// </summary>
public sealed class UndoFoldMovesContractTests
{
    private static List<(string From, string On, string To)> ContractRows() =>
        UndoContract.Journal.GetProperty("folding").GetProperty("moves").EnumerateArray()
            .Select(row => (row.GetProperty("from").GetString()!, row.GetProperty("on").GetString()!, row.GetProperty("to").GetString()!))
            .ToList();

    [Fact]
    public void TheTableIsTheContracts()
    {
        var contract = ContractRows();
        Assert.Equal(20, contract.Count);   // the table, not a case list: any change is one to read
        Assert.Equal(contract, UndoFold.Moves.Select(move => (move.From, move.On, move.To)).ToList());
    }

    private const string At = "2026-11-14T12:00:00Z";

    private static string Begin(long seq) =>
        $"{{\"v\":1,\"seq\":{seq},\"event\":\"begin\",\"at\":\"{At}\",\"process\":{{\"host\":\"h\",\"pid\":1,\"name\":\"n\",\"started\":\"s\"}}," +
        $"\"step\":{{\"seq\":{seq},\"madeAt\":\"{At}\",\"ops\":[]}}}}";

    private static string Event(long seq, string name, string? phase = null) =>
        phase is null
            ? $"{{\"v\":1,\"seq\":{seq},\"event\":\"{name}\",\"at\":\"{At}\"}}"
            : $"{{\"v\":1,\"seq\":{seq},\"event\":\"{name}\",\"phase\":\"{phase}\",\"at\":\"{At}\"}}";

    /// <summary>Lines that bring step 1 to a state named as the table names it.</summary>
    private static List<string> To(string state) => state switch
    {
        "(none)" => [],
        "begun" => [Begin(1)],
        "done" => [Begin(1), Event(1, "applied")],
        "undoing" => [Begin(1), Event(1, "applied"), Event(1, "undoing")],
        "undone" => [Begin(1), Event(1, "applied"), Event(1, "undoing"), Event(1, "undone")],
        "redoing" => [Begin(1), Event(1, "applied"), Event(1, "undoing"), Event(1, "undone"), Event(1, "redoing")],
        _ => throw new ArgumentException(state),
    };

    private static UndoStepState? Fold(IEnumerable<string> lines)
    {
        UndoFolded folded = UndoFold.Fold(lines.Select((line, place) => UndoFormat.Parse(line, 1, place)));
        return folded.Steps.TryGetValue(1, out UndoFoldedStep? step) ? step.State : null;
    }

    private static UndoStepState StateNamed(string name) =>
        Enum.Parse<UndoStepState>(name, ignoreCase: true);

    /// <summary>
    /// The sixteen rows of the form "state, on event (phase), to state": each
    /// row's `on` may name two events ("failed or rolledBack"), and each is
    /// tried.
    /// </summary>
    [Fact]
    public void EverySimpleRowMovesAsItSays()
    {
        int exercised = 0;
        foreach ((string from, string on, string to) in ContractRows())
        {
            if (from.Contains(',') || from.StartsWith("in flight", StringComparison.Ordinal) || from.StartsWith("anything", StringComparison.Ordinal)) continue;
            string? phase = null;
            string events = on;
            int bracket = on.IndexOf(" (phase ", StringComparison.Ordinal);
            if (bracket >= 0)
            {
                phase = on[(bracket + " (phase ".Length)..^1];
                events = on[..bracket];
            }
            foreach (string name in events.Split(" or "))
            {
                var lines = To(from);
                lines.Add(name == "begin" ? Begin(1) : Event(1, name, phase));
                Assert.True(StateNamed(to) == Fold(lines), $"{from} --{on}--> {to}");
                exercised++;
            }
        }
        Assert.True(exercised >= 18, $"only {exercised} moves exercised");
    }

    [Fact]
    public void DoneOrUndoneUpToTheClearedLinesSeqIsCleared()
    {
        Assert.Contains(ContractRows(), row => row.From == "done or undone, seq <= the cleared line's" && row.To == "cleared");
        Assert.Equal(UndoStepState.Cleared, Fold([.. To("done"), Event(1, "cleared")]));
        Assert.Equal(UndoStepState.Cleared, Fold([.. To("undone"), Event(1, "cleared")]));
        // A clearing whose seq is below the step's leaves it where it stands.
        Assert.Equal(UndoStepState.Done, Fold([.. To("done"), Event(0, "cleared")]));
    }

    [Theory]
    [InlineData("begun", "applied", "Cleared")]
    [InlineData("undoing", "undone", "Cleared")]
    [InlineData("redoing", "redone", "Cleared")]
    [InlineData("undoing", "failed", "Cleared")]           // back to done, so cleared
    [InlineData("begun", "failed", "Failed")]              // never took effect: not on the list either way
    public void AStepInFlightIsMarkedAndClearedWhenItsWorkEnds(string from, string ending, string expected)
    {
        var lines = To(from);
        lines.Add(Event(1, "cleared"));
        UndoFolded marked = UndoFold.Fold(lines.Select((line, place) => UndoFormat.Parse(line, 1, place)));
        Assert.True(marked.Steps[1].IsInFlight);
        Assert.True(marked.Steps[1].MarkedByAClearing);
        string? phase = ending == "failed" ? from switch { "begun" => "begin", _ => from } : null;
        lines.Add(Event(1, ending, phase));
        Assert.Equal(Enum.Parse<UndoStepState>(expected), Fold(lines));
    }

    [Theory]
    [InlineData("(none)")]
    [InlineData("begun")]
    [InlineData("done")]
    [InlineData("undone")]
    public void ANoteMovesNothingWhateverItCarries(string from)
    {
        var lines = To(from);
        UndoStepState? before = Fold(lines);
        lines.Add("{\"v\":1,\"seq\":1,\"event\":\"note\",\"phase\":\"undoing\",\"reason\":\"aReason\",\"about\":\"x\",\"step\":{\"seq\":1}}");
        Assert.Equal(before, Fold(lines));
    }

    [Theory]
    [InlineData("begun", "undone")]
    [InlineData("begun", "redone")]
    [InlineData("done", "applied")]
    [InlineData("done", "redone")]
    [InlineData("undone", "undone")]
    [InlineData("undoing", "redone")]
    public void AnEventThatDoesNotFollowIsIgnored(string from, string name)
    {
        var lines = To(from);
        UndoStepState? before = Fold(lines);
        lines.Add(Event(1, name));
        Assert.Equal(before, Fold(lines));
    }

    [Fact]
    public void AnEventForASeqWithNoBeginIsIgnored()
    {
        UndoFolded folded = UndoFold.Fold([UndoFormat.Parse(Event(7, "applied"))]);
        Assert.Empty(folded.Steps);
        Assert.Equal(7, folded.Highest);   // it still counts for the next number
    }

    [Fact]
    public void APhaseThatDoesNotMatchWhereTheStepStandsIsIgnored()
    {
        Assert.Equal(UndoStepState.Begun, Fold([.. To("begun"), Event(1, "failed", "undoing")]));
        Assert.Equal(UndoStepState.Undoing, Fold([.. To("undoing"), Event(1, "interrupted", "redoing")]));
    }
}

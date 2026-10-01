using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/assist-cases.json</c> → <c>deployAtATime</c>: every list, read
/// rather than retyped (#193, #281, #288). <c>accepted</c> is answered in code,
/// <c>asked</c> is the morning-or-evening question, <c>sayItAs</c> is the
/// spelling to use, <c>refused</c> is NONE of the three, and <c>resolving</c>
/// is the settler.
/// </summary>
public class DeployAtATimeContractTests
{
    private static JsonObject Family() => ContractLoader.LoadJson("assist-cases.json")["deployAtATime"]!.AsObject();

    private static string? WhenFor(string sentence) =>
        AssistCardCommand.Matching(sentence) is { ToolName: "schedule_deploy" } matched
            ? matched.Arguments["when"]
            : null;

    /// <summary>
    /// The lists are pinned by NAME, so a sixth list cannot land in the
    /// contract and go unread here.
    /// </summary>
    [Fact]
    public void EveryListIsOneThisTestReads()
    {
        var lists = Family().Where(pair => pair.Value is JsonArray).Select(pair => pair.Key).OrderBy(k => k).ToList();
        Assert.Equal(new[] { "accepted", "asked", "refused", "resolving", "sayItAs" }, lists);
    }

    [Fact]
    public void EveryAcceptedSpellingIsAnsweredInCodeWithItsTime()
    {
        var rows = Family()["accepted"]!.AsArray();
        Assert.True(rows.Count >= 23);
        foreach (var row in rows)
        {
            string input = row!["input"]!.ToString();
            Assert.True(WhenFor(input) == row["expectWhen"]!.ToString(),
                $"“{input}” gave {WhenFor(input) ?? "nothing"}: {row["why"]}");
        }
    }

    /// <summary>A refused row is neither answered, asked NOR given a spelling.</summary>
    [Fact]
    public void EveryRefusedSpellingGoesToTheModelUntouched()
    {
        var rows = Family()["refused"]!.AsArray();
        Assert.True(rows.Count >= 51);
        var caught = rows.Select(row => row!["input"]!.ToString())
            .Where(input => AssistCardCommand.Matching(input) is not null ||
                            AssistCardCommand.MorningOrEvening(input) is not null ||
                            AssistCardCommand.TimeToSayAs(input) is not null)
            .ToList();
        Assert.True(caught.Count == 0, "answered, asked or spelled in code, and the contract refuses: " +
                                       string.Join(" | ", caught));
    }

    [Fact]
    public void EveryAskedSpellingNamesTheClockAndTwoSentencesThatEachSetTheirTime()
    {
        var rows = Family()["asked"]!.AsArray();
        Assert.True(rows.Count >= 25);
        foreach (var row in rows)
        {
            string input = row!["input"]!.ToString();
            var question = AssistCardCommand.MorningOrEvening(input);
            Assert.True(question is not null, $"“{input}” was not asked about: {row["why"]}");
            Assert.Equal(row["expectClock"]!.ToString(), question!.Clock);
            Assert.Equal(row["expectSayMorning"]!.ToString(), question.SayMorning);
            Assert.Equal(row["expectSayEvening"]!.ToString(), question.SayEvening);
            // Both halves or neither: each sentence offered back must be one
            // this family accepts, at the time shown.
            Assert.Equal(row["expectMorningWhen"]!.ToString(), WhenFor(question.SayMorning));
            Assert.Equal(row["expectEveningWhen"]!.ToString(), WhenFor(question.SayEvening));
            Assert.Null(AssistCardCommand.Matching(input));
            Assert.Null(AssistCardCommand.TimeToSayAs(input));
        }
    }

    [Fact]
    public void EverySayItAsSpellingNamesTheTeachersWordsAndASentenceThatSetsTheSameMoment()
    {
        var rows = Family()["sayItAs"]!.AsArray();
        Assert.True(rows.Count >= 45);
        foreach (var row in rows)
        {
            string input = row!["input"]!.ToString();
            var respelling = AssistCardCommand.TimeToSayAs(input);
            Assert.True(respelling is not null, $"“{input}” was not given a spelling: {row["why"]}");
            Assert.Equal(row["expectWritten"]!.ToString(), respelling!.Written);
            Assert.Equal(row["expectSay"]!.ToString(), respelling.Say);
            Assert.Equal(row["expectWhen"]!.ToString(), WhenFor(respelling.Say));
            Assert.True((row["expectOnlyDifference"]!.ToString() == "theComma") == respelling.CommaIsTheOnlyDifference,
                $"“{input}”: onlyDifference should be {row["expectOnlyDifference"]}");
            Assert.Null(AssistCardCommand.Matching(input));
            Assert.Null(AssistCardCommand.MorningOrEvening(input));
        }
    }

    [Fact]
    public void EveryResolvingRowSettlesToItsMoment()
    {
        var rows = Family()["resolving"]!.AsArray();
        Assert.True(rows.Count >= 11);
        foreach (var row in rows)
        {
            var zone = TimeZoneInfo.FindSystemTimeZoneById(row!["timeZone"]!.ToString());
            var now = DateTime.ParseExact(row["now"]!.ToString(), "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
            var today = DateOnly.ParseExact(row["today"]!.ToString(), "yyyy-MM-dd", CultureInfo.InvariantCulture);
            string? settled = ScheduledMoment.Settle(row["when"]!.ToString(), today, now, zone);
            Assert.True(settled == row["expectMoment"]?.ToString(),
                $"“{row["when"]}” at {row["now"]} settled to {settled ?? "nothing"}: {row["why"]}");
            // Whatever is settled must read back through this app's own
            // reader, or the card and the trail line lose it.
            if (settled is not null) Assert.NotNull(ScheduledDeploy.ReadTheMoment(settled));
        }
    }

    // ---- Daylight saving: proposed to the mac as rows, measured here --------

    private static readonly TimeZoneInfo Toronto = TimeZoneInfo.FindSystemTimeZoneById("America/Toronto");

    /// <summary>
    /// 02:30 does not exist on 8 March 2026 in Toronto. .NET would THROW
    /// converting it; Foundation moves it forward, so the mac settles 03:30.
    /// This must too — and the result must read back.
    /// </summary>
    [Fact]
    public void ATimeThatDoesNotExistThatNightSettlesOntoOneThatDoes()
    {
        string? settled = ScheduledMoment.Settle("02:30", new DateOnly(2026, 3, 8),
                                                 new DateTime(2026, 3, 8, 1, 0, 0), Toronto);
        Assert.Equal("2026-03-08 03:30", settled);
        Assert.NotNull(ScheduledDeploy.ReadTheMoment(settled!));
    }

    /// <summary>
    /// Asked at 01:45 in the FIRST 01:00 hour of 1 November 2026, "1:30 am"
    /// is taken as the earlier instant — already gone — so it is tomorrow's,
    /// as the mac's Calendar decides.
    /// </summary>
    [Fact]
    public void ARepeatedHourIsTakenAsItsEarlierInstant()
    {
        string? settled = ScheduledMoment.Settle("01:30", new DateOnly(2026, 11, 1),
                                                 new DateTime(2026, 11, 1, 1, 45, 0), Toronto);
        Assert.Equal("2026-11-02 01:30", settled);
    }

    /// <summary>Idempotent: a whole moment is handed straight back as nothing to settle.</summary>
    [Fact]
    public void SettlingTwiceChangesNothing()
    {
        string first = ScheduledMoment.Settle("tomorrow 06:30", new DateOnly(2026, 9, 19),
                                              new DateTime(2026, 9, 19, 9, 0, 0), TimeZoneInfo.Utc)!;
        Assert.Null(ScheduledMoment.Settle(first, new DateOnly(2026, 9, 20),
                                           new DateTime(2026, 9, 20, 9, 0, 0), TimeZoneInfo.Utc));
    }

    // ---- The immediate card says it is immediate ---------------------------

    [Fact]
    public void TheImmediateDeployCardSaysItIsImmediate()
    {
        var rule = ContractLoader.LoadJson("shared-rules.json")["assistantConfirmation"]!["theImmediateDeployCardSaysItIsImmediate"]!;
        // Asserted, never read as a switch: a rule turned off from the data
        // would go quiet with the suite green.
        Assert.True(rule["value"]!.GetValue<bool>());
        Assert.True(rule["mustContainIsAWholeWord"]!.GetValue<bool>());
        string word = rule["mustContain"]!.ToString();
        // A WHOLE word, case-folded: "knows" would satisfy a substring test.
        Assert.Matches(new Regex($@"\b{Regex.Escape(word)}\b", RegexOptions.IgnoreCase), AssistWording.DeployApproval);
        Assert.DoesNotMatch(new Regex($@"\b{Regex.Escape(word)}\b", RegexOptions.IgnoreCase), "Students knows nowhere");
    }
}

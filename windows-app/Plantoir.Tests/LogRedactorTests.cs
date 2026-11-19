using System.Diagnostics;
using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Scripting;

namespace Plantoir.Tests;

public class LogRedactorTests
{
    [Fact]
    public void LogRedactor_AllContractCases_Pass()
    {
        var doc = ContractLoader.LoadJson("shared-rules.json");
        var cases = doc["problemReportRedaction"]!["cases"]!.AsArray();

        foreach (var c in cases)
        {
            if (c is null) continue;
            string input = Filled(c);
            string expected = c["expect"]!.ToString();

            string actual = LogRedactor.Redacting(input);
            Assert.Equal(expected, actual);
        }
    }

    /// <summary>
    /// A case's input, with its credential ASSEMBLED where the contract keeps
    /// it in pieces (<c>problemReportRedaction.assembledInput</c>, the mac's
    /// #844): <c>{user}</c> and <c>{password}</c> are replaced by those two
    /// values, and <c>{basic}</c> by the base64 of <c>user:password</c> in
    /// UTF-8, so no credential-shaped string is stored in the contract or
    /// here. A template with no <c>assembledFrom</c> is a mistake in the
    /// contract, and this says so.
    /// </summary>
    internal static string Filled(JsonNode c)
    {
        string input = c["input"]!.ToString();
        if (c["assembledFrom"] is not { } pieces)
        {
            foreach (string placeholder in new[] { "{user}", "{password}", "{basic}" })
                Assert.False(input.Contains(placeholder, StringComparison.Ordinal),
                    $"problemReportRedaction case \"{input}\" carries {placeholder} and no assembledFrom to fill it from");
            return input;
        }
        string user = pieces["user"]!.ToString();
        string password = pieces["password"]!.ToString();
        string basic = Convert.ToBase64String(Encoding.UTF8.GetBytes(user + ":" + password));
        return input.Replace("{user}", user).Replace("{password}", password).Replace("{basic}", basic);
    }

    /// <summary>
    /// The counterpart of the mac's
    /// <c>SharedRulesContractTests.testAnAssembledRedactionCaseIsFilledBeforeItIsRedacted</c>
    /// (#844, Windows #858): the filled template is what is redacted. An
    /// unfilled reader passes the two credential cases and fails only the
    /// tripwire (#844 review M1), so this checks the filling itself. The
    /// base64 is DECODED here, never stored: storing it is what #844 removed.
    /// </summary>
    [Fact]
    public void TheAssembledCasesAreFilledBeforeTheyAreRedacted()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["problemReportRedaction"]!["cases"]!.AsArray();
        var assembled = cases.Where(c => c?["assembledFrom"] is not null).Select(c => c!).ToList();
        Assert.Equal(12, assembled.Count);
        int decoded = 0;
        foreach (var c in assembled)
        {
            string template = c["input"]!.ToString();
            string filled = Filled(c);
            foreach (string placeholder in new[] { "{user}", "{password}", "{basic}" })
                Assert.DoesNotContain(placeholder, filled);
            Assert.NotEqual(template, filled);
            if (template.Contains("{password}") || template.Contains("{basic}"))
                Assert.NotEqual(filled, LogRedactor.Redacting(filled));
            int at = template.IndexOf("{basic}", StringComparison.Ordinal);
            if (at < 0) continue;
            // The filling is what lies between the template's own text either side of {basic}.
            string after = template[(at + "{basic}".Length)..];
            string filling = filled[at..(filled.Length - after.Length)];
            Assert.Equal("example-user:example-password", Encoding.UTF8.GetString(Convert.FromBase64String(filling)));
            decoded++;
        }
        Assert.Equal(3, decoded);
    }

    /// <summary>
    /// The pattern rules run in exactly the order the contract names
    /// (<c>problemReportRedaction.ruleOrder.order</c>, #853; Windows #941),
    /// as the mac's <c>testTheRedactionRulesRunInTheContractsOrder</c>.
    /// </summary>
    [Fact]
    public void TheRulesRunInTheContractsOrder()
    {
        var ruleOrder = ContractLoader.LoadJson("shared-rules.json")["problemReportRedaction"]!["ruleOrder"]!;
        Assert.NotNull(ruleOrder["rule"]);
        Assert.NotNull(ruleOrder["why"]);
        var expected = new List<string>();
        foreach (var name in ruleOrder["order"]!.AsArray())
            expected.Add(name!.ToString());
        var actual = new List<string>();
        foreach (var rule in LogRedactor.PatternRules)
            actual.Add(rule.Name);
        Assert.Equal(expected, actual);
    }

    /// <summary>
    /// The order is pinned by what it does as well as by name: each
    /// <c>ruleOrder.cases</c> line comes out as its <c>expect</c> in the
    /// pinned order, and differently when the rule its <c>wrongOrder</c>
    /// names is moved to run just before another (the mac's
    /// <c>testEachRuleOrderCaseDependsOnTheOrder</c>).
    /// </summary>
    [Fact]
    public void EachRuleOrderCaseDependsOnTheOrder()
    {
        var ruleOrder = ContractLoader.LoadJson("shared-rules.json")["problemReportRedaction"]!["ruleOrder"]!;
        var cases = ruleOrder["cases"]!.AsArray();
        Assert.True(cases.Count >= 2, "ruleOrder.cases holds fewer than two cases");
        foreach (var c in cases)
        {
            string template = c!["input"]!.ToString();
            string input = Filled(c);
            string expect = c["expect"]!.ToString();
            Assert.NotNull(c["why"]);
            Assert.Equal(expect, LogRedactor.Redacting(input));

            string moved = c["wrongOrder"]!["move"]!.ToString();
            string before = c["wrongOrder"]!["before"]!.ToString();
            var reordered = RulesMoving(moved, before);
            Assert.True(LogRedactor.Redacting(input, reordered) != expect,
                $"with {moved} before {before}, input \"{template}\" should come out differently");
        }
    }

    /// <summary>
    /// The app's pattern rules with the one named <paramref name="moved"/>
    /// taken out and put back just before the one named
    /// <paramref name="before"/>.
    /// </summary>
    private static List<RedactionRule> RulesMoving(string moved, string before)
    {
        RedactionRule? ruleToMove = null;
        var others = new List<RedactionRule>();
        foreach (var rule in LogRedactor.PatternRules)
        {
            if (rule.Name == moved) ruleToMove = rule;
            else others.Add(rule);
        }
        Assert.True(ruleToMove is not null, $"no rule named {moved}");
        var reordered = new List<RedactionRule>();
        bool placed = false;
        foreach (var rule in others)
        {
            if (rule.Name == before)
            {
                reordered.Add(ruleToMove!);
                placed = true;
            }
            reordered.Add(rule);
        }
        Assert.True(placed, $"no rule named {before}");
        return reordered;
    }

    /// <summary>
    /// Redacting a line that is already redacted changes nothing
    /// (<c>problemReportRedaction.redactedAgainCases</c>, #780, #853): the
    /// trail writer redacts a line, cleans it and redacts it again whenever it
    /// held a control character. The mac's
    /// <c>CourseNameCharactersTests.testRedactingTwiceChangesNothing</c>.
    /// </summary>
    [Fact]
    public void RedactingTwiceChangesNothing()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["problemReportRedaction"]!["redactedAgainCases"]!["cases"]!.AsArray();
        Assert.NotEmpty(cases);
        foreach (var c in cases)
        {
            string input = c!["input"]!.ToString();
            string expect = c["expect"]!.ToString();
            Assert.Equal(expect, LogRedactor.Redacting(input));
        }
    }

    /// <summary>
    /// The lines that were slow on the mac before #853's second round (the
    /// mac's <c>ProblemReportTests.slowShapes</c>).
    /// </summary>
    private static readonly string[] SlowShapes =
    {
        "address characters",
        "address characters and dots",
        "a quoted -u value of colons with no closing quote",
        "a dash and a run of u",
        "addresses whose passwords hold a colon",
        "a password of words with no @",
        "a home folder followed by words",
        "labels",
    };

    /// <summary>One of <see cref="SlowShapes"/>, about <paramref name="length"/> characters long.</summary>
    private static string SlowLine(string shape, int length)
    {
        switch (shape)
        {
            case "address characters": return Repeated("a", length);
            case "address characters and dots": return Repeated("a.", length / 2);
            case "a quoted -u value of colons with no closing quote": return "curl -u '" + Repeated("a:", length / 2);
            case "a dash and a run of u": return "-" + Repeated("u", length);
            case "addresses whose passwords hold a colon": return Repeated("x://y:z ", length / 8);
            case "a password of words with no @": return "https://a:b " + Repeated("c ", length / 2);
            case "a home folder followed by words": return "/Users/a " + Repeated("b ", length / 2) + "x";
            default: return Repeated("token: ", length / 7);
        }
    }

    private static string Repeated(string piece, int count)
    {
        var builder = new StringBuilder(piece.Length * count);
        for (int index = 0; index < count; index++)
            builder.Append(piece);
        return builder.ToString();
    }

    /// <summary>The seconds the redactor takes over one line, the best of <paramref name="tries"/>.</summary>
    private static double SecondsToRedact(string line, int tries)
    {
        double best = double.MaxValue;
        for (int attempt = 0; attempt < tries; attempt++)
        {
            var clock = Stopwatch.StartNew();
            LogRedactor.Redacting(line);
            double seconds = clock.Elapsed.TotalSeconds;
            if (seconds < best) best = seconds;
        }
        return best;
    }

    /// <summary>
    /// No rule takes longer than linear time, so a very long trail line cannot
    /// hold up the write that waits for it (the mac's
    /// <c>ProblemReportTests.testNoRuleTakesLongerThanLinearTime</c>, #941
    /// item 5). Bounded by GROWTH, not seconds, so a slower or busier machine
    /// passes as well as a fast one: ten times the characters may take at most
    /// fifty times as long, in the same run, the best of up to three rounds
    /// with the two lengths timed in turn. The bound is the mac's; the numbers
    /// under .NET are this test's own measurement.
    /// </summary>
    [Fact]
    public void NoRuleTakesLongerThanLinearTime()
    {
        const double growthLimit = 50;
        const int shorter = 10_000;
        const int longer = 100_000;
        foreach (string shape in SlowShapes)
        {
            string shortLine = SlowLine(shape, shorter);
            string longLine = SlowLine(shape, longer);
            double shortTime = SecondsToRedact(shortLine, 3);
            double longTime = double.MaxValue;
            int round = 0;
            while (round < 3 && longTime > growthLimit * shortTime)
            {
                double longSeconds = SecondsToRedact(longLine, 1);
                if (longSeconds < longTime) longTime = longSeconds;
                double shortSeconds = SecondsToRedact(shortLine, 1);
                if (shortSeconds < shortTime) shortTime = shortSeconds;
                round++;
            }
            double growth = longTime / Math.Max(shortTime, double.Epsilon);
            Assert.True(growth <= growthLimit,
                $"{shape}: {shorter} characters took {shortTime} s and {longer} took {longTime} s (growth {growth:F1})");
        }
    }
}

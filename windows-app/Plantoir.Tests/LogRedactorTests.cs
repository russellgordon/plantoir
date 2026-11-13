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
        Assert.Equal(3, assembled.Count);
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
        Assert.Equal(1, decoded);
    }
}

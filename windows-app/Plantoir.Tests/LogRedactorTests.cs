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

    /// <summary>The filled template is what is redacted: an unfilled reader would pass the two credential cases and fail the tripwire (#844 review M1).</summary>
    [Fact]
    public void TheAssembledCasesAreFilledBeforeTheyAreRedacted()
    {
        var cases = ContractLoader.LoadJson("shared-rules.json")["problemReportRedaction"]!["cases"]!.AsArray();
        var assembled = cases.Where(c => c?["assembledFrom"] is not null).ToList();
        Assert.True(assembled.Count >= 3, $"only {assembled.Count} assembled cases");
        foreach (var c in assembled)
            Assert.DoesNotContain("{", Filled(c!));
    }
}

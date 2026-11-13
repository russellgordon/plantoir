using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// <c>app-rules.json</c> → <c>outsideAgents.planAUnit</c> (#801 item 5): the
/// two buttons' titles, the opening message for every <c>messageCases</c>
/// case, the trail line, and that both doors carry the message in place of the
/// greeting with no unit-planning reminder. The buttons themselves are 790b.
/// </summary>
public sealed class PlanAUnitTests
{
    private static JsonNode Block() => ContractLoader.LoadJson("app-rules.json")["outsideAgents"]!["planAUnit"]!;

    [Fact]
    public void TheWordsAreTheContracts()
    {
        var block = Block();
        Assert.Equal(block["message"]!.ToString(), PlanAUnit.Message);
        Assert.Equal(block["trailLine"]!.ToString(), "{course}" + UnitPlans.TrailSeparator + PlanAUnit.TrailLine);
        var buttons = block["buttons"]!.AsArray();
        Assert.Equal(Enum.GetValues<FixWithAssistant.Assistant>().Length, buttons.Count);
        foreach (var button in buttons)
        {
            var assistant = Enum.Parse<FixWithAssistant.Assistant>(button!["assistant"]!.ToString(), ignoreCase: true);
            Assert.Equal(button["title"]!.ToString(), PlanAUnit.ButtonTitle(assistant));
        }
        // The event's own record names the same line.
        var entry = ContractLoader.LoadJson("shared-rules.json")["activityTrail"]!["mustRecord"]!.AsArray()
            .Single(e => e!["event"]!.ToString() == "asked an assistant to plan a unit")!;
        Assert.Equal(entry["line"]!.ToString(), block["trailLine"]!.ToString());
        Assert.Equal(block["trailLine"]!.ToString().Replace("{course}", "SNC2D").Replace("{assistant}", "Codex"),
                     PlanAUnit.TrailText("SNC2D", FixWithAssistant.Assistant.Codex));
    }

    [Fact]
    public void TheMessageIsTheContractsForEveryCase()
    {
        var messageCases = Block()["messageCases"]!.AsArray();
        Assert.True(messageCases.Count >= 6);
        foreach (var testCase in messageCases)
        {
            string name = testCase!["name"]!.ToString();
            string text = PlanAUnit.OpeningMessage(testCase["course"]!.ToString(), testCase["courseName"]!.ToString());
            Assert.True(testCase["text"]!.ToString() == text, $"{name}: {text}");
            Assert.DoesNotContain(";", text);
            Assert.DoesNotContain("\"", text);
            Assert.DoesNotContain("\n", text);
        }
    }

    /// <summary>
    /// Both doors carry the message in place of the greeting, so no
    /// unit-planning reminder rides along, and the door's own line is plain
    /// (<c>planAUnit.atTheClick</c>).
    /// </summary>
    [Fact]
    public void BothDoorsCarryTheMessageAndNoReminder()
    {
        string message = PlanAUnit.OpeningMessage("SNC2D", "Grade 10 Science");
        var reading = new UnitPlans.Reading(Array.Empty<UnitPlans.Plan>(), 0);
        var claude = ClaudeCodeLauncher.Prepare(@"C:\x\mcp-SNC2D.json", "SNC2D", "Grade 10 Science", reading, message);
        var codex = CodexLauncher.Prepare(@"C:\x\plantoir-mcp.exe", @"C:\work", "SNC2D", "Grade 10 Science", reading, message);
        foreach (var session in new[] { claude, codex })
        {
            Assert.Equal(message, session.Arguments[^1]);
            Assert.DoesNotContain(UnitPlans.NoneSentence, session.Arguments[^1]);
            Assert.DoesNotContain(UnitPlans.TrailSeparator, session.TrailText);
        }
    }
}

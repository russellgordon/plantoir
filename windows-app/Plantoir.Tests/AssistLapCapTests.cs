using System.Reflection;
using ModelContextProtocol.Server;
using Plantoir.Core.Assist;
using Plantoir.Mcp;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// #720 (the mac's #689): one teacher action asks the local model at most
/// <c>shared-rules.json</c> → <c>assistantLapLimit</c> →
/// <c>mostModelRequestsPerTurn</c> times, and the turn that reaches it says
/// <c>wording.wentRoundWithoutFinishing</c> — "…so nothing was changed".
/// </summary>
/// <remarks>
/// <para><b>Why the write-tools tests come first.</b> "Nothing was changed"
/// is true on Windows only because a WRITE ends the turn:
/// <c>AssistToolRunner.Run</c> hands the turn back to the app for every
/// <see cref="AssistToolRunner.IsWriteTool"/> name (and for
/// <c>check_section</c> and <c>read_remembered_timetable</c>), so the only
/// calls that come before another lap are reads. A write missing from
/// <see cref="AssistToolRunner.WriteTools"/> would run, lap, and could then
/// reach the cap, and the sentence would be false. The mac's rule is
/// per-outcome (<c>shouldContinue</c>); this list is the same rule by name,
/// and it has been wrong before (<c>roll_over_course</c> for
/// <c>roll_over_section</c>, five writes missing — <c>AssistAgent.IsWriteTool</c>'s
/// comment).</para>
///
/// <para><b>What counts as a write</b> is the server's own annotation: a
/// <c>[McpServerTool]</c> without <c>ReadOnly = true</c>.</para>
///
/// <para><b>Which tools are in scope: every tool a LAP can run.</b> Only two
/// doors lead into <c>AssistAgent.Run()</c>, the loop that laps: a sentence
/// the model answers (<c>Say</c>), where the model can name only
/// <c>ForTheLocalModel</c> (anything else it was not offered is refused before
/// it runs), and Go (<c>Approve</c>), which runs the call that was held and
/// laps only if that call was not handed back. A card's DIRECT run
/// (<c>RunCommand</c> → <c>RunTool</c>) never laps; a card held for approval
/// reaches <c>Run()</c> only through <c>Approve</c>, with a tool already in
/// scope — <c>NeedsApproval</c> (<c>DeploysToStudents</c>) or a key of
/// <c>PlanTwins</c>. That is why <c>explain_publishing</c>, a card that is not
/// annotated ReadOnly and writes nothing, is not in scope.</para>
///
/// <para><b>A known difference, unchanged:</b> <c>check_section</c> ends the
/// turn here and laps on the mac. The contract's scenario uses
/// <c>list_pages</c>, which laps on both.</para>
/// </remarks>
[Collection(SharedActivityState.Name)]
public class AssistLapCapTests
{
    // ---- Every write a lap can run ends the turn ----------------------------

    /// <summary>Every tool the MCP server serves, by name, with whether it is annotated ReadOnly.</summary>
    private static Dictionary<string, bool> ServedReadOnly()
    {
        var served = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        foreach (var method in typeof(PlantoirTools).GetMethods(BindingFlags.Public | BindingFlags.Instance))
        {
            var attribute = method.GetCustomAttribute<McpServerToolAttribute>();
            if (attribute is null) continue;
            served[attribute.Name ?? method.Name] = attribute.ReadOnly;
        }
        return served;
    }

    /// <summary>The tools a lap of the in-app assistant can run (see the remarks above).</summary>
    private static IReadOnlyCollection<string> ALapCanRun() =>
        AssistAgent.ForTheLocalModel
            .Concat(AssistAgent.DeploysToStudents)
            .Concat(AssistAgent.PlanTwins.Keys)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

    [Fact]
    public void EveryWriteALapCanRunIsAWriteTool()
    {
        var served = ServedReadOnly();
        Assert.True(served.Count >= 40, $"the reflection found {served.Count} tools; it is not reading the server");

        var missing = new List<string>();
        foreach (string tool in ALapCanRun())
        {
            Assert.True(served.ContainsKey(tool), $"{tool} can be run by a lap but the server does not serve it");
            if (!served[tool] && !AssistToolRunner.IsWriteTool(tool)) missing.Add(tool);
        }
        Assert.True(missing.Count == 0,
            "These tools write (no ReadOnly on their [McpServerTool]) and a lap can run them, but they are not in " +
            "AssistToolRunner.WriteTools, so they would not end the turn — and the lap cap's \"nothing was changed\" " +
            "would be false: " + string.Join(", ", missing));
    }

    [Fact]
    public void EveryWriteToolNamesAServedWrite()
    {
        var served = ServedReadOnly();
        foreach (string tool in AssistToolRunner.WriteTools)
        {
            Assert.True(served.ContainsKey(tool), $"WriteTools names {tool}, which the server does not serve (a misspelt name ends no turn)");
            Assert.False(served[tool], $"WriteTools names {tool}, which the server annotates ReadOnly");
        }
    }
}

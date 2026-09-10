using System.Text.Json.Nodes;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

public class AssistCardCommandTests
{
    /// <summary>
    /// What a failure here MEANS, said in the failure itself.
    ///
    /// <para>A phrasing in <c>cardPhrasings</c> that this app does not match is
    /// almost never a bug somebody just wrote. That key is a readout of the
    /// mac's own matcher, so it moves when the mac gains a tool — and the mac
    /// side opens a <c>windows</c> issue naming the phrasings in the same
    /// session (<c>CLAUDE.md</c> rule 3). The red suite IS that handover
    /// arriving.</para>
    ///
    /// <para><b>This sentence exists because the failure was misread once.</b>
    /// On 2026-09-09 a session mid-way through unrelated work met two of these
    /// red, saw <c>Assert.NotNull() Failure: Value is null</c> — naming no
    /// phrasing, no tool and nothing to look up — and filed issue #146 saying
    /// nobody had been told. Issue #70 had named all five phrasings and
    /// predicted this exact failure, in these words, at 23:52 the evening
    /// before. The assertions carried no message; the mac's equivalent
    /// (<c>AssistScenarioTests.swift</c>) has named the phrasing all along.</para>
    ///
    /// <para><b>It is "usually", not "always", and the same run proved it.</b>
    /// Two other tests failed alongside these. One was
    /// <c>AssistSurfaceContractTests</c> reporting that <c>back_up_course</c>
    /// had gained a <c>section</c> — a real contract move that NO issue named,
    /// so a reader who followed this advice would rightly have found nothing
    /// and should have opened a <c>mac</c> issue. The other was a test of this
    /// app's own that had retyped a contract value into a literal. Check the
    /// issues; do not assume one exists.</para>
    /// </summary>
    private const string Handover =
        "A phrasing the contract carries and this app does not match is usually a HANDOVER: " +
        "cardPhrasings is generated from the mac's matcher, and the mac opens a `windows` issue " +
        "naming the phrasings when it moves. Read the open `windows` issues before filing a new " +
        "one — a red suite here is the handover arriving, not evidence that nobody told you.";

    [Fact]
    public void CardPhrasings_AllMatchesFromContract_Pass()
    {
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var matches = doc["cardPhrasings"]!["matches"]!.AsArray();

        foreach (var m in matches)
        {
            if (m is null) continue;
            string phrasing = m["phrasing"]!.ToString();
            string expectedTool = m["tool"]!.ToString();
            var expectedArgs = m["arguments"]?.AsObject();

            var matched = AssistCardCommand.Matching(phrasing);
            Assert.True(matched is not null,
                $"\"{phrasing}\" is in the contract and matches nothing here, so a teacher who " +
                $"types it has it routed by the model instead of reaching {expectedTool}. " +
                Handover);
            Assert.True(expectedTool == matched!.ToolName,
                $"\"{phrasing}\" must reach {expectedTool} and reaches {matched.ToolName}. " +
                "A fixed phrasing exists because the model gets this sentence wrong, so a " +
                "phrasing wired to the wrong tool is worse than none at all.");

            if (expectedArgs != null)
            {
                foreach (var (k, v) in expectedArgs)
                {
                    Assert.True(matched.Arguments.ContainsKey(k), $"Argument key {k} missing for {phrasing}");
                    Assert.Equal(v!.ToString(), matched.Arguments[k]);
                }
            }
        }
    }

    [Fact]
    public void CardPhrasings_AllParsedExamplesFromContract_Pass()
    {
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var parsed = doc["cardPhrasings"]!["parsed"]!.AsArray();

        foreach (var p in parsed)
        {
            if (p is null) continue;
            string example = p["example"]!.ToString();
            string expectedTool = p["tool"]!.ToString();
            string notThis = p["notThis"]!.ToString();
            // The contract gives each near miss its OWN reason, and they are
            // not the same reason: make_room's is that a count and a noun
            // disagreeing would rename pages a teacher's links point at, while
            // "publish unit 4, day 3" is refused because a comma names a page
            // rather than a unit. Rendering one entry's reason for all five
            // would be the retyping this file exists to catch.
            string because = p["becauseNotThis"]?.ToString() ?? "";

            var matched = AssistCardCommand.Matching(example);
            Assert.True(matched is not null,
                $"\"{example}\" is a parsed shape in the contract and matches nothing here, so a " +
                $"teacher who types it has it routed by the model instead of reaching {expectedTool}. " +
                Handover);
            Assert.True(expectedTool == matched!.ToolName,
                $"\"{example}\" must reach {expectedTool} and reaches {matched.ToolName}.");

            var nearMiss = AssistCardCommand.Matching(notThis);
            Assert.True(nearMiss is null,
                $"\"{notThis}\" is the near miss the contract pairs with \"{example}\" and this app " +
                $"MATCHED it, sending it to {nearMiss?.ToolName}. The contract's own reason it must " +
                $"not: {because}");
        }
    }

    [Fact]
    public void CardPhrasings_AllNearMissesFromContract_DoNotMatch()
    {
        var doc = ContractLoader.LoadJson("assist-cases.json");
        var nearMisses = doc["nearMisses"]!["phrasings"]!.AsArray();

        foreach (var nm in nearMisses)
        {
            if (nm is null) continue;
            string phrasing = nm.ToString();

            var matched = AssistCardCommand.Matching(phrasing);
            Assert.True(matched is null,
                $"\"{phrasing}\" is a near miss the contract says must NOT match, and this app sent " +
                $"it to {matched?.ToolName}. These are the sentences a widened pattern swallows: " +
                "the point of a fixed shape is that it declines what it is not sure of and lets the " +
                "model answer instead.");
        }
    }
}

using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// The class links a step holding relinking moves is made on (#899 W8b-21b3;
/// the mac's <c>UndoContractKinds</c> calls <c>relinkALink</c>,
/// <c>relinkALinkLeavingAHandedOverPlace</c>, <c>relinkTwoChainedLinks</c>,
/// <c>relinkThreeChainedLinks</c> and <c>relinkThenMoveALinkIntoItsPlace</c>),
/// shared by the recovery replay (<c>recoveryCasesHow</c>'s <c>withARelink</c>)
/// and <c>UndoRelinkTests</c>' killed tests, so both lay and make the same
/// step by one spelling. Each link holds a sibling class page's name, no
/// separator, as the mac lays it; Windows never follows it.
/// </summary>
internal static class UndoRelinkForTheCases
{
    /// <summary><c>withARelink</c>'s shapes, as <c>recoveryCasesHow</c> names them, and the one Windows' killed tests add (review F's counter-example).</summary>
    internal static readonly string[] Shapes = ["alone", "leavingAHandedOverPlace", "chained", "chainedThree", "thenAMove", "aMoveThenARelink"];

    /// <summary><c>Unit 1, Day &lt;n&gt;.md</c>: the text a class link holds.</summary>
    internal static string Text(int day) => "Unit 1, Day " + day + ".md";

    private static byte[] Bytes(string text) => Encoding.UTF8.GetBytes(text);

    /// <summary>A symbolic link at Day &lt;n&gt; holding <paramref name="text"/> as written.</summary>
    internal static void LayALink(UndoScribe scribe, int day, string text)
    {
        string place = scribe.FullPath("A", UndoHandoverForTheCases.ClassPage(day));
        Directory.CreateDirectory(Path.GetDirectoryName(place)!);
        File.CreateSymbolicLink(place, text);
    }

    /// <summary>A relinking move from Day <paramref name="from"/> to Day <paramref name="to"/>, the link's text <paramref name="before"/> becoming <paramref name="after"/>, both in the list.</summary>
    internal static JsonObject Relink(int from, int to, string before, string after)
    {
        string beforeSha = UndoCheck.Sha(Bytes(before));
        string afterSha = UndoCheck.Sha(Bytes(after));
        return new JsonObject
        {
            ["kind"] = "move", ["from"] = UndoHandoverForTheCases.ClassPage(from), ["to"] = UndoHandoverForTheCases.ClassPage(to),
            ["linkShaBefore"] = beforeSha, ["linkShaAfter"] = afterSha, ["blobs"] = new JsonArray(beforeSha, afterSha),
        };
    }

    /// <summary>A plain link move from Day <paramref name="from"/> to Day <paramref name="to"/>, its text kept.</summary>
    internal static JsonObject MoveALink(int from, int to, string text) => new()
    {
        ["kind"] = "move", ["from"] = UndoHandoverForTheCases.ClassPage(from), ["to"] = UndoHandoverForTheCases.ClassPage(to),
        ["linkSha"] = UndoCheck.Sha(Bytes(text)),
    };

    /// <summary>Lays the shape's pages and links, and answers its ops and blobs.</summary>
    internal static (JsonArray Ops, List<byte[]> Blobs) Lay(UndoScribe scribe, string shape)
    {
        var ops = new JsonArray();
        var blobs = new List<byte[]>();
        void Texts(params int[] days)
        {
            foreach (int day in days) blobs.Add(Bytes(Text(day)));
        }
        switch (shape)
        {
            case "alone":
            case "leavingAHandedOverPlace":
                // Day 3 a page, Day 4 a link holding `Unit 1, Day 3.md`, moved
                // to Day 5 holding `Unit 1, Day 4.md`; leaving a handed-over
                // place, Day 3's page then moved into Day 4 and `New.` written at Day 3.
                scribe.WritePage("A", UndoHandoverForTheCases.ClassPage(3), Bytes("Three.\n"));
                LayALink(scribe, 4, Text(3));
                ops.Add(Relink(4, 5, Text(3), Text(4)));
                Texts(3, 4);
                if (shape == "leavingAHandedOverPlace")
                {
                    ops.Add(UndoKindsForTheCases.MoveFile(UndoHandoverForTheCases.ClassPage(3), UndoHandoverForTheCases.ClassPage(4), Bytes("Three.\n")));
                    ops.Add(scribe.OpsFor(UndoHandoverForTheCases.ClassPage(3), null, Bytes("New.\n"))[0]!.DeepClone());
                    blobs.Add(Bytes("New.\n"));
                }
                break;
            case "chained":
                // Review D: Day 5's link moved to Day 6 (`Day 2` becoming
                // `Day 3`), then Day 4's to Day 5 (`Day 1` becoming `Day 2`).
                LayALink(scribe, 4, Text(1));
                LayALink(scribe, 5, Text(2));
                ops.Add(Relink(5, 6, Text(2), Text(3)));
                ops.Add(Relink(4, 5, Text(1), Text(2)));
                Texts(1, 2, 3);
                break;
            case "chainedThree":
                // Review F: Day 6 to Day 7, Day 5 to Day 6, Day 4 to Day 5, each new text the next one's old.
                LayALink(scribe, 4, Text(1));
                LayALink(scribe, 5, Text(2));
                LayALink(scribe, 6, Text(3));
                ops.Add(Relink(6, 7, Text(3), Text(4)));
                ops.Add(Relink(5, 6, Text(2), Text(3)));
                ops.Add(Relink(4, 5, Text(1), Text(2)));
                Texts(1, 2, 3, 4);
                break;
            case "thenAMove":
                // Review F: Day 4 and Day 5 both holding `Day 2`; Day 5's
                // relinked to Day 6 (`Day 3`), then Day 4's moved plainly into Day 5.
                LayALink(scribe, 4, Text(2));
                LayALink(scribe, 5, Text(2));
                ops.Add(Relink(5, 6, Text(2), Text(3)));
                ops.Add(MoveALink(4, 5, Text(2)));
                Texts(2, 3);
                break;
            case "aMoveThenARelink":
                // Review F's counter-example (the mac's ChainShape
                // aMoveThenARelinkIntoItsPlace): Day 5's link (`Day 2`) moved
                // plainly to Day 6, then Day 4's (`Day 1`) relinked into Day 5
                // holding `Day 2`, the text the plain move's link holds.
                LayALink(scribe, 4, Text(1));
                LayALink(scribe, 5, Text(2));
                ops.Add(MoveALink(5, 6, Text(2)));
                ops.Add(Relink(4, 5, Text(1), Text(2)));
                Texts(1, 2);
                break;
            default:
                Xunit.Assert.Fail("a key this replay does not check: withARelink " + shape);
                break;
        }
        return (ops, blobs);
    }

    /// <summary>The <see cref="UndoHandoverForTheCases.Snapshot"/> a step of this shape leaves, made whole through the door in a scribe of its own.</summary>
    internal static string MadeWhole(string shape)
    {
        using var scribe = new UndoScribe();
        (JsonArray ops, List<byte[]> blobs) = Lay(scribe, shape);
        UndoOutcome made = scribe.Door().Perform(scribe.OpsDraft("A", ops, blobs, "insertClass"));
        Xunit.Assert.True(made.Kind == UndoOutcomeKind.Applied, "the step with a relink was not made whole: " + made.Word);
        return UndoHandoverForTheCases.Snapshot(scribe);
    }
}

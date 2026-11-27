using System.Text;
using System.Text.Json.Nodes;

namespace Plantoir.Tests;

/// <summary>
/// The kept-page guard's plain step (#1055 M5, W3; <c>recoveryCasesHow</c>'s
/// <c>withAPlainPageMove</c>, the mac's <c>movePlainPageAwayFromDay3</c>): no
/// link anywhere. Day 3's page (<c>Three.</c>) to Day 4 (Day 4 written, Day 3
/// removed), then <c>Five.</c> written at Day 5, in that order, as Insert
/// Class moves an ordinary class.
/// </summary>
internal static class UndoPlainPageMoveForTheCases
{
    internal const string ClassSection = "courses/TST1O/section1";

    /// <summary>courses/TST1O/section1/Unit 1, Day &lt;n&gt;.md.</summary>
    internal static string ClassPage(int day) => ClassSection + "/Unit 1, Day " + day + ".md";

    internal static readonly byte[] Three = "Three.\n"u8.ToArray();
    internal static readonly byte[] Five = "Five.\n"u8.ToArray();

    /// <summary>Day 3 holding <c>Three.</c>.</summary>
    internal static void Lay(UndoScribe scribe) => scribe.WritePage("A", ClassPage(3), Three);

    /// <summary>The step's three writeFile ops and the blobs they name.</summary>
    internal static (JsonArray Ops, List<byte[]> Blobs) Ops(UndoScribe scribe) =>
        (new JsonArray(
             scribe.OpsFor(ClassPage(4), null, Three)[0]!.DeepClone(),
             scribe.OpsFor(ClassPage(3), Three, null)[0]!.DeepClone(),
             scribe.OpsFor(ClassPage(5), null, Five)[0]!.DeepClone()),
         [Three, Five]);

    /// <summary>Someone's page written at Day 3, where the step removed a page (whatever the stop left there is replaced).</summary>
    internal static void WriteSomeoneElsesPageAtDay3(UndoScribe scribe)
    {
        string day3 = scribe.FullPath("A", ClassPage(3));
        if (File.Exists(day3)) File.Delete(day3);
        scribe.WritePage("A", ClassPage(3), Encoding.UTF8.GetBytes("Someone else's.\n"));
    }
}

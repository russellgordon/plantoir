using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// The class pages and their links that a step handing a place over is made
/// on (opKinds.wholeOps' second exception; the mac's U4b3 door-4 and door-5),
/// shared by the stack replay (<c>stackCasesHow</c>'s
/// <c>handAPlaceOverAfterALinksMove</c> and <c>handAPlaceOverBeforeALinksMove</c>)
/// and the recovery replay (<c>recoveryCasesHow</c>'s <c>withAHandedOverPlace</c>),
/// so both lay and read the same pages by one spelling.
/// </summary>
internal sealed class UndoHandoverForTheCases(UndoScribe scribe)
{
    internal const string ClassSection = "courses/TST1O/section1";
    internal const string Library = "courses/TST1O/library";

    private readonly Dictionary<string, byte[]> _libraryLaid = new(StringComparer.Ordinal);

    /// <summary>courses/TST1O/section1/Unit 1, Day &lt;n&gt;.md.</summary>
    internal static string ClassPage(int day) => ClassSection + "/Unit 1, Day " + day + ".md";

    /// <summary>The target each class link holds, as written: <c>../library/Day &lt;n&gt;.md</c>.</summary>
    internal static string ClassLinkTarget(int day) => "../library/Day " + day + ".md";

    internal bool Nothing(string relative) => UndoLinks.Look(scribe.FullPath("A", relative)) == UndoLinks.What.Nothing;

    /// <summary>courses/TST1O/library/Day &lt;n&gt;.md holding <paramref name="text"/>, remembered for <c>library: untouched</c>.</summary>
    internal void LayALibraryPage(int day, string text)
    {
        string relative = Library + "/Day " + day + ".md";
        byte[] bytes = Encoding.UTF8.GetBytes(text);
        scribe.WritePage("A", relative, bytes);
        _libraryLaid[relative] = bytes;
    }

    /// <summary>A symbolic link at Day &lt;n&gt; holding its library target as written (forward slash kept, as the mac writes it).</summary>
    internal void LayAClassLink(int day)
    {
        string place = scribe.FullPath("A", ClassPage(day));
        Directory.CreateDirectory(Path.GetDirectoryName(place)!);
        File.CreateSymbolicLink(place, ClassLinkTarget(day));
    }

    /// <summary>The link's <c>move</c> from Day <paramref name="from"/> to Day <paramref name="to"/>, its linkSha the SHA-256 of the target it holds as written.</summary>
    internal static JsonObject TheClassLinksMove(int from, int to) => new()
    {
        ["kind"] = "move", ["from"] = ClassPage(from), ["to"] = ClassPage(to),
        ["linkSha"] = UndoCheck.Sha(Encoding.UTF8.GetBytes(ClassLinkTarget(from))),
    };

    /// <summary>A writeFile at Day <paramref name="day"/>: no before (a new page) or no after (a removal), as the door works it out.</summary>
    internal JsonNode ClassPageOp(int day, string? before, string? after) =>
        scribe.OpsFor(ClassPage(day), before is null ? null : Encoding.UTF8.GetBytes(before), after is null ? null : Encoding.UTF8.GetBytes(after))[0]!.DeepClone();

    /// <summary>Shape A's pages: Day 3 a link to the library's Day 3, Day 4 free.</summary>
    internal void LayAfterALinksMove()
    {
        LayALibraryPage(3, "Linked.\n");
        LayAClassLink(3);
    }

    /// <summary>Shape A's ops: the link moved from Day 3 to Day 4, then <c>New.</c> written at Day 3.</summary>
    internal (JsonArray Ops, List<byte[]> Blobs) HandAPlaceOverAfterALinksMove() =>
        (new JsonArray(TheClassLinksMove(3, 4), ClassPageOp(3, null, "New.\n")), [Encoding.UTF8.GetBytes("New.\n")]);

    /// <summary>Shape B's pages: Day 2 a link to the library's Day 2, Day 3 holding <c>Three.</c>, Day 4 free.</summary>
    internal void LayBeforeALinksMove()
    {
        LayALibraryPage(2, "Two.\n");
        LayAClassLink(2);
        scribe.WritePage("A", ClassPage(3), "Three.\n"u8.ToArray());
    }

    /// <summary>Shape B's ops: Day 4 written <c>Three.</c>, Day 3 removed, the link moved from Day 2 to Day 3, then <c>New.</c> written at Day 2.</summary>
    internal (JsonArray Ops, List<byte[]> Blobs) HandAPlaceOverBeforeALinksMove() =>
        (new JsonArray(ClassPageOp(4, null, "Three.\n"), ClassPageOp(3, "Three.\n", null), TheClassLinksMove(2, 3), ClassPageOp(2, null, "New.\n")),
         [Encoding.UTF8.GetBytes("Three.\n"), Encoding.UTF8.GetBytes("New.\n")]);

    /// <summary>
    /// <c>handedOver</c>: what Day 2, Day 3 and Day 4 hold (<c>page &lt;text&gt;</c>
    /// without its last line end, <c>link &lt;target as written&gt;</c> or
    /// <c>nothing</c>), then whether the library holds what was laid.
    /// </summary>
    internal string HandedOver()
    {
        var parts = new List<string>();
        foreach (int day in new[] { 2, 3, 4 })
        {
            string full = scribe.FullPath("A", ClassPage(day));
            string holds = UndoLinks.Look(full) switch
            {
                UndoLinks.What.Nothing => "nothing",
                UndoLinks.What.Link => "link " + (new FileInfo(full).LinkTarget ?? "notALink"),
                UndoLinks.What.File => "page " + WithoutItsLastLineEnd(UndoKindsForTheCases.Text(scribe.Page("A", ClassPage(day))) ?? ""),
                UndoLinks.What other => other.ToString(),
            };
            parts.Add("Day " + day + ": " + holds);
        }
        bool untouched = true;
        foreach ((string relative, byte[] bytes) in _libraryLaid)
        {
            if (scribe.Page("A", relative) is not { } now || !now.AsSpan().SequenceEqual(bytes)) untouched = false;
        }
        parts.Add("library: " + (untouched ? "untouched" : "changed"));
        return string.Join("; ", parts);
    }

    private static string WithoutItsLastLineEnd(string text) => text.EndsWith('\n') ? text[..^1] : text;

    /// <summary>
    /// recoveryCasesHow's <c>files</c> for a step that hands a place over:
    /// every entry of section 1 and of the library, by name in ordinal order,
    /// as a link with its target as written, a page with its text, or a folder.
    /// A staged file left anywhere there shows too.
    /// </summary>
    internal static string Snapshot(UndoScribe scribe)
    {
        var parts = new List<string>();
        foreach (string folder in new[] { ClassSection, Library })
        {
            string full = scribe.FullPath("A", folder);
            if (!Directory.Exists(full)) continue;
            var names = new List<string>();
            foreach (string entry in Directory.EnumerateFileSystemEntries(full)) names.Add(Path.GetFileName(entry));
            names.Sort(StringComparer.Ordinal);
            foreach (string name in names)
            {
                string at = Path.Combine(full, name);
                string holds = UndoLinks.Look(at) switch
                {
                    UndoLinks.What.Link => "link " + (new FileInfo(at).LinkTarget ?? "notALink"),
                    UndoLinks.What.File => "page " + File.ReadAllText(at),
                    UndoLinks.What other => other.ToString(),
                };
                parts.Add(folder + "/" + name + ": " + holds);
            }
        }
        return string.Join(" | ", parts);
    }

    /// <summary>The <see cref="Snapshot"/> a step of this shape leaves, made whole through the door in a scribe of its own.</summary>
    internal static string MadeWhole(string shape)
    {
        using var scribe = new UndoScribe();
        var handover = new UndoHandoverForTheCases(scribe);
        if (shape == "afterALinksMove") handover.LayAfterALinksMove();
        else handover.LayBeforeALinksMove();
        (JsonArray ops, List<byte[]> blobs) = shape == "afterALinksMove" ? handover.HandAPlaceOverAfterALinksMove() : handover.HandAPlaceOverBeforeALinksMove();
        UndoOutcome made = scribe.Door().Perform(scribe.OpsDraft("A", ops, blobs));
        Xunit.Assert.True(made.Kind == UndoOutcomeKind.Applied, "the step handing a place over was not made whole: " + made.Word);
        return Snapshot(scribe);
    }
}

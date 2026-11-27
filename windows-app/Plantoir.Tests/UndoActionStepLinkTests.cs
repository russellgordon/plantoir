using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8b-21a6 (the mac's U4b3 door-6, <c>JournaledStep</c>): what is left
/// of an action step that moves a link (<see cref="UndoActionStep.MoveLink"/>)
/// once no step hands a place over (#1055 W3): a write at a link moved to
/// another folder is refused before anything changes (#1055 W4's to remove
/// with the link move).
/// </summary>
public sealed class UndoActionStepLinkTests : IDisposable
{
    private const string Section = "courses/TST1O/section1";
    private const string LibraryPage = "courses/TST1O/library/Day 2.md";

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-step-link-");
    private readonly List<UndoTrailLine> _trail = [];

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");

    private static string Day(int number) => Section + "/Unit 1, Day " + number + ".md";

    private string Full(string relative) => UndoDoor.FullPath(Folder, relative);

    private void Write(string relative, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Full(relative))!);
        File.WriteAllText(Full(relative), text);
    }

    /// <summary>Day 3 a link to the library's Day 2 (its target as given), Day 4 a plain page.</summary>
    private void ACourse(string target)
    {
        Directory.CreateDirectory(Path.Combine(Folder, "courses", "TST1O"));
        File.WriteAllText(Path.Combine(Folder, Plantoir.Core.Models.Workspace.MarkerLauncher), "");
        Write("courses/TST1O/course_config.json", "{\"course_code\":\"TST1O\"}");
        Write(LibraryPage, "Two.\n");
        Write(Day(4), "Four.\n");
        File.CreateSymbolicLink(Full(Day(3)), target);
    }

    private UndoForThisProcess List() => new(ListFolder, UndoMode.Shadow, _trail.Add);

    private UndoActionStep Step(UndoForThisProcess list, string? workingFolder) =>
        new(new UndoStepMaker("sheet", "insertClass"), workingFolder, "TST1O", 1, undo: list);

    /// <summary>Every entry under the working folder but courses/.internal: a link by the target it holds, a file by its bytes, a folder by null.</summary>
    private SortedDictionary<string, string?> Tree()
    {
        var tree = new SortedDictionary<string, string?>(StringComparer.Ordinal);
        foreach (string entry in Directory.EnumerateFileSystemEntries(Folder, "*", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(Folder, entry).Replace('\\', '/');
            if (UndoOp.PartInside("courses/.internal", relative) is not null) continue;
            if (UndoLinks.Look(entry) == UndoLinks.What.Link) tree[relative] = "link " + new FileInfo(entry).LinkTarget;
            else tree[relative] = Directory.Exists(entry) ? null : Convert.ToBase64String(File.ReadAllBytes(entry));
        }
        return tree;
    }

    private List<JsonObject> Begins()
    {
        var begins = new List<JsonObject>();
        if (!Directory.Exists(ListFolder)) return begins;
        foreach (string segment in Directory.EnumerateFiles(ListFolder, "journal-*.jsonl").Order(StringComparer.Ordinal))
        {
            foreach (string line in File.ReadAllLines(segment))
            {
                if (JsonNode.Parse(line) is JsonObject read && (string?)read["event"] == "begin") begins.Add(read);
            }
        }
        return begins;
    }

    /// <summary>A link moved to ANOTHER folder leads elsewhere from its new place: a write there is refused, cannotTellNow, before anything changes (the mac's <c>refusesAWrite</c>).</summary>
    [SymbolicLinkFact]
    public void AWriteAtALinkMovedToAnotherFolderIsRefusedAndNothingChanges()
    {
        ACourse("..\\library\\Day 2.md");
        UndoActionStep step = Step(List(), Folder);
        string elsewhere = "courses/TST1O/section2/Unit 1, Day 3.md";
        Directory.CreateDirectory(Path.GetDirectoryName(Full(elsewhere))!);
        SortedDictionary<string, string?> before = Tree();

        step.MoveLink(Full(Day(3)), Full(elsewhere));
        var refused = Assert.Throws<UndoStepRefusedException>(() => step.Write(Full(elsewhere), "Two, dated.\n"));

        Assert.Equal(UndoRefusalKind.CannotTellNow, refused.Refusal.Kind);
        Assert.Equal(before, Tree());
        Assert.Empty(Begins());
    }
}

using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7b2-2 review 1, L2 (and W7b2-1 review 2, L1): a planned file that
/// comes out unchanged is skipped TWICE, by the step
/// (<c>UndoActionStep.RecordableChanges</c>) and by the door
/// (<c>UndoDoor.Perform</c>'s <c>SameBytes</c>), and each masks the other in
/// an action's test. Each is pinned here alone: the door is handed the
/// unchanged file directly, past the step; the step plans an unchanged file
/// it could not name, which only its own skip keeps from making the whole
/// step unnameable.
/// </summary>
public sealed class UndoUnchangedFileSkipTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-unchanged-");

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static List<string> OpPaths(JsonObject begin)
    {
        var paths = new List<string>();
        foreach (JsonNode? op in begin["step"]!["ops"]!.AsArray())
        {
            string path = (string)op!["path"]!;
            if (!paths.Contains(path)) paths.Add(path);
        }
        return paths;
    }

    /// <summary>The door alone: a draft holding an unchanged file names no op for it and never swaps it.</summary>
    [Fact]
    public void TheDoorNamesNoOpForAFileHandedToItUnchanged()
    {
        using var scribe = new UndoScribe();
        const string changed = "courses/TST1O/section1/a.md";
        const string unchanged = "courses/TST1O/section1/b.md";
        scribe.WritePage("A", changed, Encoding.UTF8.GetBytes("A\n"));
        scribe.WritePage("A", unchanged, Encoding.UTF8.GetBytes("B\n"));
        // Its last write set in the past: a swap of its same bytes would
        // stamp it now (the swap copies the creation time, not this).
        var longAgo = new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        File.SetLastWriteTimeUtc(scribe.FullPath("A", unchanged), longAgo);

        Assert.NotNull(scribe.Step("A", [(changed, Encoding.UTF8.GetBytes("A, changed\n")), (unchanged, Encoding.UTF8.GetBytes("B\n"))]));

        JsonObject begin = Assert.Single(WindowsActionsOnTheMacFixture.AppliedBegins(scribe.JournalFolder));
        Assert.Equal(new List<string> { changed }, OpPaths(begin));
        // Never swapped: the line names no op for identical bytes either way
        // (UndoLineOps.ForAFile), so the door's skip shows only here.
        Assert.Equal(longAgo, File.GetLastWriteTimeUtc(scribe.FullPath("A", unchanged)));
    }

    /// <summary>
    /// The step alone: an unchanged planned file outside the working folder
    /// (which no step can name) is left out before the step is named, so the
    /// changed page is still made as a recorded step; without the step's
    /// skip, the whole step would be written plainly, with no begin line.
    /// </summary>
    [Fact]
    public void TheStepLeavesOutAnUnchangedFileItCouldNotName()
    {
        string folder = Path.Combine(_root, "wf");
        string listFolder = Path.Combine(_root, "state", "undo");
        WindowsActionsOnTheMacFixture.Lay(folder, WindowsActionsOnTheMacFixture.Recorded("duplicateAsTheNextClass"));
        var workspace = new AssistWorkspace(folder, new FakeLauncher(), undo: new UndoHistory())
        {
            Surface = AssistSurface.Menu,
            UndoList = new UndoForThisProcess(listFolder, UndoMode.Shadow, null),
        };
        string outside = Path.Combine(_root, "outside.md");
        File.WriteAllText(outside, "beside the working folder\n");
        string page = Path.Combine(folder, "courses", "ICS3U", "section1", "All Classes", "Unit 1, Day 1.md");

        var step = workspace.NewUndoStep("publishPages", "ICS3U", 1);
        step.Write(outside, "beside the working folder\n");
        step.Write(page, File.ReadAllText(page) + "\nA line.\n");
        step.Make();

        JsonObject begin = Assert.Single(WindowsActionsOnTheMacFixture.AppliedBegins(listFolder));
        Assert.Equal(new List<string> { "courses/ICS3U/section1/All Classes/Unit 1, Day 1.md" }, OpPaths(begin));
    }
}

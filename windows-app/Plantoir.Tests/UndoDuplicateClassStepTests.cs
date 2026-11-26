using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7b2-2: Duplicate Class (<c>ApplyDuplicateClass</c>, the step
/// <c>duplicateClass</c>) is ONE step through the door: the room it makes and
/// the copy are planned into the same step and made once, all or none, run on
/// the mac's recorded fixture (<c>undo-action-steps.json</c>) with the mac's
/// arguments (<c>add_next_class</c>, <c>duplicate</c> "Unit 1, Day 1").
/// </summary>
public sealed class UndoDuplicateClassStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private const string StepName = "duplicateClass";

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-duplicate-");

    private readonly UndoHistory _history = new();

    // ---- Computed properties ---------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private static JsonElement Recorded => WindowsActionsOnTheMacFixture.Recorded(StepName);

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private AssistWorkspace Workspace(UndoSeams? seams = null) => new(Folder, new FakeLauncher(), undo: _history)
    {
        Surface = AssistSurface.LocalWindow,
        UndoList = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null),
        UndoSeams = seams,
    };

    private string Page(string title) =>
        Path.Combine(Folder, "courses", "ICS3U", "section1", "All Classes", title + ".md");

    private static List<string> RecordedPaths()
    {
        var paths = new List<string>();
        foreach (JsonElement file in Recorded.GetProperty("files").EnumerateArray()) paths.Add(file.GetProperty("path").GetString()!);
        return paths;
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

    /// <summary>One step under the recorded key, holding the room AND the copy, its files in the mac's order and every after the mac's.</summary>
    [Fact]
    public void TheRoomAndTheCopyAreOneStepInTheMacsFileOrder()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);

        string answered = WindowsActionsOnTheMacFixture.Run(StepName, Workspace());

        JsonObject begin = Assert.Single(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
        Assert.Equal(StepName, (string?)begin["step"]!["action"]!["key"]);
        Assert.Equal(RecordedPaths(), OpPaths(begin));
        foreach (JsonElement file in Recorded.GetProperty("files").EnumerateArray())
        {
            string full = UndoDoor.FullPath(Folder, file.GetProperty("path").GetString()!);
            Assert.Equal(file.GetProperty("after").GetString(), File.ReadAllText(full));
        }
        Assert.Single(WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        Assert.Contains("Renamed 2,", answered, StringComparison.Ordinal);
        // Other classes moved, so today's in-memory undo records no entry, as before.
        Assert.Empty(_history.Entries);
    }

    /// <summary>
    /// The copy refused once the room is planned (a page of the teacher's own
    /// took a rename's new name after the plan was shown, so the place for the
    /// copy still holds a lesson): the room alone is made, in ONE step under
    /// the same key, and the answer is as before.
    /// </summary>
    [Fact]
    public void TheCopyRefusedAfterTheRoomIsPlannedMakesTheRoomAloneInOneStep()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        var workspace = Workspace();
        var plan = workspace.PlanDuplicateClass("ICS3U", 1, "Unit 1, Day 1");
        const string teachers = "---\ntitle: Unit 1, Day 4\npublish: false\n---\nMy own page.\n";
        File.WriteAllText(Page("Unit 1, Day 4"), teachers);
        string lesson = File.ReadAllText(Page("Unit 1, Day 2"));

        var refused = Assert.Throws<AssistRefusal>(() => workspace.ApplyDuplicateClass(plan));

        Assert.Equal(ClassChangeWording.ThePlaceForTheCopyIsStillTaken("Unit 1, Day 2", workspace.ConversationBackupPath), refused.Message);
        Assert.Equal(lesson, File.ReadAllText(Page("Unit 1, Day 2")));
        Assert.Equal(teachers, File.ReadAllText(Page("Unit 1, Day 4")));
        JsonObject begin = Assert.Single(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
        Assert.Equal(StepName, (string?)begin["step"]!["action"]!["key"]);
        Assert.DoesNotContain("courses/ICS3U/section1/All Classes/Unit 1, Day 2.md", OpPaths(begin));
        Assert.Single(WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        Assert.Empty(_history.Entries);
        Assert.True(workspace.TakeWhetherTheCallChangedAnything(workspace.TopOfTheUndoList), "the room was made");
    }

    /// <summary>
    /// A page that cannot be written (read-only) changes nothing: every page's
    /// bytes as before, no step applied, no entry in today's undo, said
    /// "Nothing was changed".
    /// </summary>
    [Fact]
    public void APageThatCannotBeWrittenChangesNothing()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        string later = Page("Unit 2, Day 1");
        File.SetAttributes(later, FileAttributes.ReadOnly);
        try
        {
            var workspace = Workspace();
            var plan = workspace.PlanDuplicateClass("ICS3U", 1, "Unit 1, Day 1");
            string section = Path.Combine(Folder, "courses", "ICS3U", "section1");
            List<string> before = WindowsActionsOnTheMacFixture.EveryFileBut(section, ListFolder);

            var refused = Assert.Throws<AssistRefusal>(() => workspace.ApplyDuplicateClass(plan));

            Assert.Equal("Nothing was changed: Plantoir doesn’t have permission to change one of them.", refused.Message);
            Assert.Equal(before, WindowsActionsOnTheMacFixture.EveryFileBut(section, ListFolder));
            Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
            Assert.Empty(_history.Entries);
            Assert.False(workspace.TakeWhetherTheCallChangedAnything(workspace.TopOfTheUndoList));
        }
        finally { File.SetAttributes(later, FileAttributes.Normal); }
    }

    /// <summary>
    /// The door leaves the step part way: the part-way sentence with "the
    /// classes and the copy" (the mac's saidWhenTheStepStopped words), naming
    /// the kept file, never "Nothing was changed" or "couldn’t be read".
    /// </summary>
    [Fact]
    public void APartWayStopSaysThePartWaySentence()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        var workspace = Workspace(new UndoSeams
        {
            BetweenKeepingAndRenaming = (index, fullPath) =>
            {
                if (index != 1) return;
                using var inPlace = new FileStream(fullPath, FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
                byte[] edit = Encoding.UTF8.GetBytes("written by hand\n");
                inPlace.Write(edit);
                inPlace.SetLength(edit.Length);
            },
            PutBackFailsAt = index => index == 1,
        });

        string answered = WindowsActionsOnTheMacFixture.Run(StepName, workspace);

        Assert.StartsWith(AssistWording.PublishStoppedPartWay("the classes and the copy", ""), answered);
        string classes = Path.GetDirectoryName(Page("Unit 1, Day 3"))!;
        string kept = Assert.Single(Directory.GetFiles(classes, ".*.plantoir-undo-*-orig"));
        Assert.Contains(Path.GetFileName(kept), answered, StringComparison.Ordinal);
        Assert.DoesNotContain("Nothing was changed", answered, StringComparison.Ordinal);
        Assert.DoesNotContain("couldn’t be read", answered, StringComparison.Ordinal);
        Assert.Empty(_history.Entries);
    }

    /// <summary>Reports a progress line SYNCHRONOUSLY, so a test can change the folder at the moment a stage of the planning begins.</summary>
    private sealed class AtTheStage(string stage, Action then) : IProgress<string>
    {
        public void Report(string value) { if (value.StartsWith(stage, StringComparison.Ordinal)) then(); }
    }

    /// <summary>
    /// Every before is read at plan time: another program edits the later
    /// class (its link and date already planned) while the copy is being
    /// planned, and the step is refused rather than written over it.
    /// </summary>
    [Fact]
    public void AnEditMadeWhileItPlansIsNeverWrittenOver()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        var workspace = Workspace();
        var plan = workspace.PlanDuplicateClass("ICS3U", 1, "Unit 1, Day 1");
        string later = Page("Unit 2, Day 1");
        const string byHand = "---\ntitle: Unit 2, Day 1\n---\n\nWritten by hand while it planned.\n";

        Assert.Throws<AssistRefusal>(() =>
            workspace.ApplyDuplicateClass(plan, new AtTheStage("Copying", () => File.WriteAllText(later, byHand))));

        Assert.Equal(byHand, File.ReadAllText(later));
        Assert.False(File.Exists(Page("Unit 1, Day 4")), "a class was renamed");
        Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
    }

    /// <summary>
    /// Nothing else moves (the last class duplicated): one step holding the
    /// copy alone, and today's in-memory undo records it as before, the copy
    /// with no before, so Undo takes it away.
    /// </summary>
    [Fact]
    public void WhenNothingElseMovesTodaysUndoRecordsTheCopyWithNoBefore()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        var workspace = Workspace();
        var plan = workspace.PlanDuplicateClass("ICS3U", 1, "Unit 2, Day 1");
        string copy = Page(plan.NewTitle);

        workspace.ApplyDuplicateClass(plan);

        JsonObject begin = Assert.Single(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
        Assert.Equal(StepName, (string?)begin["step"]!["action"]!["key"]);
        var entry = Assert.Single(_history.Entries);
        var (path, state) = Assert.Single(entry.Files);
        Assert.Equal(Path.GetFullPath(copy), Path.GetFullPath(path));
        Assert.Null(state.Before);
        Assert.Equal(File.ReadAllText(copy), state.After);
    }
}

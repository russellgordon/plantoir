using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7b2-3: the Section menu's Duplicate as Next Class (Classes ▸ Add
/// Class… as a copy, #927; <c>ApplyMenuDuplicate</c>, the step
/// <c>duplicateAsTheNextClass</c>) writes its one new page through ONE step
/// made by the menu, run on the mac's recorded fixture
/// (<c>undo-action-steps.json</c>) with the mac's arguments
/// (<c>SectionVerbs.duplicateAsNextClass</c>, source
/// <c>section1/All Classes/Unit 1, Day 1.md</c>). A page that appears at the
/// new name is never written over, as the exclusive create never wrote over
/// one.
/// </summary>
public sealed class UndoMenuDuplicateStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private const string StepName = "duplicateAsTheNextClass";

    private const string SourcePath = "section1/All Classes/Unit 1, Day 1.md";

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-menu-copy-");

    private readonly UndoHistory _history = new();

    // ---- Computed properties ---------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private string Section => Path.Combine(Folder, "courses", "ICS3U", "section1");
    private static JsonElement Recorded => WindowsActionsOnTheMacFixture.Recorded(StepName);

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private AssistWorkspace Workspace(UndoSeams? seams = null) => new(Folder, new FakeLauncher(), undo: _history)
    {
        Surface = AssistSurface.Menu,
        UndoList = new UndoForThisProcess(ListFolder, UndoMode.Shadow, null),
        UndoSeams = seams,
    };

    private string Page(string title) => Path.Combine(Section, "All Classes", title + ".md");

    /// <summary>One step under the recorded key, made by the menu, holding only the new page, its bytes the mac's and the disk's.</summary>
    [Fact]
    public void TheCopyIsOneStepMadeByTheMenu()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);

        string answered = WindowsActionsOnTheMacFixture.Run(StepName, Workspace());

        JsonObject begin = Assert.Single(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
        Assert.Equal(StepName, (string?)begin["step"]!["action"]!["key"]);
        Assert.Equal("menu", (string?)begin["step"]!["madeBy"]);
        JsonElement recordedFile = Assert.Single(Recorded.GetProperty("files").EnumerateArray().ToList());
        JsonNode? op = Assert.Single(begin["step"]!["ops"]!.AsArray());
        Assert.Equal(recordedFile.GetProperty("path").GetString(), (string?)op!["path"]);
        Assert.Equal(UndoOp.WriteFile, (string?)op["kind"]);
        string full = UndoDoor.FullPath(Folder, recordedFile.GetProperty("path").GetString()!);
        Assert.Equal(recordedFile.GetProperty("after").GetString(), File.ReadAllText(full));
        // What the step says it left is what is on the disk: nothing was
        // written beside the step.
        Assert.Equal((string?)op["afterSha"], UndoCheck.Sha(File.ReadAllBytes(full)));
        Assert.Single(WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
        Assert.Equal(AssistWording.DuplicatedFromTheMenu("Unit 1, Day 1", "Unit 2, Day 2", "2026-09-18"), answered);
        // No entry on today's in-memory undo (the night-3 ruling, NamedGapLedger.MenuCopyUndoEntries).
        Assert.Empty(_history.Entries);
    }

    /// <summary>
    /// A page that appears at the new name after the step was planned, in
    /// the last instant before the rename (the exclusive create's own case):
    /// refused with today's sentence (menuTheNextPageIsAlreadyThere), the
    /// page left as it is, no step applied, nothing else written. A page
    /// there before the plan is made again is refused as changed while
    /// saving a copy (AddClassContractTests.APageThatAppearedSinceThePlanIsNeverWrittenOver).
    /// </summary>
    [Fact]
    public void APageThatAppearedAtTheNewNameIsNeverWrittenOver()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        string target = Page("Unit 2, Day 2");
        const string teachers = "---\ntitle: Unit 2, Day 2\n---\n\nMy own page.\n";
        var workspace = Workspace(new UndoSeams
        {
            BeforeEachSwap = (_, _) =>
            {
                if (!File.Exists(target)) File.WriteAllText(target, teachers);
            },
        });
        var request = workspace.PlanMenuDuplicate("ICS3U", 1, SourcePath);
        List<string> before = WindowsActionsOnTheMacFixture.EveryFileBut(Section, ListFolder);

        var refused = Assert.Throws<AssistRefusal>(() => workspace.ApplyMenuDuplicate(request));

        Assert.Equal(AssistWording.MenuTheNextPageIsAlreadyThere("Unit 2, Day 2"), refused.Message);
        Assert.Equal(teachers, File.ReadAllText(target));
        var after = new List<string>();
        foreach (string file in WindowsActionsOnTheMacFixture.EveryFileBut(Section, ListFolder))
            if (!file.StartsWith("All Classes/Unit 2, Day 2.md ", StringComparison.Ordinal)) after.Add(file);
        Assert.Equal(before, after);
        Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
        Assert.Empty(_history.Entries);
    }

    /// <summary>
    /// A page that cannot be written (its staged content refused by the
    /// disk) changes nothing: said "Nothing was created: …", as the copy has
    /// said since #927, every file as before, no step applied.
    /// </summary>
    [Fact]
    public void APageThatCannotBeWrittenChangesNothing()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        var workspace = Workspace(new UndoSeams { StagingWriteFailsAt = _ => true });
        var request = workspace.PlanMenuDuplicate("ICS3U", 1, SourcePath);
        List<string> before = WindowsActionsOnTheMacFixture.EveryFileBut(Section, ListFolder);

        var refused = Assert.Throws<AssistRefusal>(() => workspace.ApplyMenuDuplicate(request));

        Assert.StartsWith("Nothing was created: ", refused.Message, StringComparison.Ordinal);
        Assert.Contains("“Unit 2, Day 2.md”", refused.Message, StringComparison.Ordinal);
        Assert.Equal(before, WindowsActionsOnTheMacFixture.EveryFileBut(Section, ListFolder));
        Assert.False(File.Exists(Page("Unit 2, Day 2")));
        Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
        Assert.Empty(_history.Entries);
        Assert.False(workspace.TakeWhetherTheCallChangedAnything(workspace.TopOfTheUndoList));
    }

    /// <summary>
    /// A step left part way says the part-way sentence with the mac's words
    /// for this action ("the copy of the class", its saidWhenTheStepStopped),
    /// naming the kept file, with the menu's way back; never "Nothing was
    /// created", "Nothing was changed" or "couldn’t be read". The door cannot
    /// leave this one-new-page step part way (nothing of it is put back), so
    /// the sentence is pinned on the answer the action gives such a stop.
    /// </summary>
    [Fact]
    public void APartWayStopSaysThePartWaySentence()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        var workspace = Workspace();
        var request = workspace.PlanMenuDuplicate("ICS3U", 1, SourcePath);
        workspace.ApplyMenuDuplicate(request);    // the conversation's backup, as a real stop has one
        const string kept = ".Unit 2, Day 2.md.plantoir-undo-7-orig";
        var stopped = new UndoStepLeftPartWayException(new UndoRefusal(UndoRefusalKind.FileIsInUse), [kept],
            "“Unit 2, Day 2.md” is in use by another program. " + kept);

        AssistRefusal said = workspace.RefusalForAMenuCopyThatStopped(stopped, request);

        Assert.StartsWith(AssistWording.PublishStoppedPartWay("the copy of the class", ""), said.Message);
        Assert.Contains(kept, said.Message, StringComparison.Ordinal);
        Assert.EndsWith(AssistWording.RestoreFromBackupPutsItBack, said.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("Nothing was", said.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("couldn’t be read", said.Message, StringComparison.Ordinal);
    }
    /// <summary>
    /// W7b2-3 review 1, L1: whether a page was at the new name is read ONCE,
    /// as the step's own before when the copy is planned, never by a second
    /// look at the disk. A page dropped at the new name after that read (a
    /// seam between the step's read and the copy's question) is a change
    /// since the plan, for the door to refuse; a page there when planned is
    /// there, whatever the disk says later.
    /// </summary>
    [Fact]
    public void WhetherThePageWasThereIsWhatTheStepPlannedAsItsBefore()
    {
        string target = Page("Unit 2, Day 2");
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        var absentWhenPlanned = new UndoActionStep(new UndoStepMaker("menu", StepName), Folder, "ICS3U", 1,
            undo: new UndoForThisProcess(ListFolder, UndoMode.Shadow, null));
        absentWhenPlanned.Write(target, "the copy");
        File.WriteAllText(target, "Dropped here after the step read its before.\n");

        Assert.False(absentWhenPlanned.WasThereWhenPlanned(target));

        var presentWhenPlanned = new UndoActionStep(new UndoStepMaker("menu", StepName), Folder, "ICS3U", 1,
            undo: new UndoForThisProcess(ListFolder, UndoMode.Shadow, null));
        presentWhenPlanned.Write(target, "the copy");
        File.Delete(target);

        Assert.True(presentWhenPlanned.WasThereWhenPlanned(target));
    }

    /// <summary>
    /// W7b2-3 review 1, L1, in the action: the menu's copy asks the step what
    /// it planned, after the step read its before, and never looks at the
    /// disk again for it.
    /// </summary>
    [Fact]
    public void TheCopyAsksTheStepWhetherThePageWasThere()
    {
        string copy = File.ReadAllText(Path.Combine(ContractLoader.RepositoryRoot, "windows-app", "Plantoir.Core", "Assist", "AssistWorkspace.MenuDuplicate.cs"));

        int planned = copy.IndexOf("step.Write(request.NewPath, request.CopyText);", StringComparison.Ordinal);
        int asked = copy.IndexOf("bool alreadyThere = step.WasThereWhenPlanned(request.NewPath);", StringComparison.Ordinal);
        Assert.True(planned >= 0, "the copy is planned into the step");
        Assert.True(asked > planned, "whether the page was there is asked of the step after it read its before");
        Assert.DoesNotContain("File.Exists(request.NewPath);", copy, StringComparison.Ordinal);
        Assert.DoesNotContain("step.Exists(request.NewPath)", copy, StringComparison.Ordinal);
    }
}

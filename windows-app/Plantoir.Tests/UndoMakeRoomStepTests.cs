using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W7b2-1: Make Room for Classes (<c>ApplyInsertClasses</c>, the step
/// <c>makeRoomForClasses</c>) is ONE step through the door, all or none, run
/// on the mac's recorded fixture (<c>undo-action-steps.json</c>) with the
/// mac's arguments (<c>make_room_for_classes</c>, unit 1, at day 2).
/// </summary>
public sealed class UndoMakeRoomStepTests : IDisposable
{
    // ---- Stored properties ---------------------------------------------------------

    private const string StepName = "makeRoomForClasses";

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-make-room-");

    // ---- Computed properties ---------------------------------------------------------

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");
    private static JsonElement Recorded => WindowsActionsOnTheMacFixture.Recorded(StepName);

    // ---- Functions -------------------------------------------------------------------

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private AssistWorkspace Workspace(UndoSeams? seams = null) => new(Folder, new FakeLauncher())
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

    /// <summary>One step, the recorded key, its files in the mac's order (the new page, then each rename's pages, then the linked later class), and every after the mac's.</summary>
    [Fact]
    public void MakingRoomIsOneStepInTheMacsFileOrder()
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
        Assert.Contains("Renamed 2,", answered, StringComparison.Ordinal);
        Assert.Single(WindowsActionsOnTheMacFixture.BeginKeys(ListFolder));
    }

    /// <summary>
    /// Making room among pages that differ only in their title and date
    /// (review 1, L3; the shape of blank pages, the one Make Room is most used
    /// on; named for that shape since W7b2-1's review 2, L2), so a renamed and
    /// re-dated page can come out byte for byte the page that stood at its
    /// new name. That file is not in the step at all; every other is, in the
    /// planned order, and every page reads as the plan meant.
    /// </summary>
    [Fact]
    public void AmongPagesThatDifferOnlyInTitleAndDateAPageThatComesOutUnchangedIsNotInTheStep()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        // Day 2 carries Day 3's lesson, so renamed to Day 3 and re-dated it is Day 3 exactly.
        string day3 = File.ReadAllText(Page("Unit 1, Day 3"));
        File.WriteAllText(Page("Unit 1, Day 2"), day3.Replace("Unit 1, Day 3", "Unit 1, Day 2").Replace("2026-09-14", "2026-09-10"));

        WindowsActionsOnTheMacFixture.Run(StepName, Workspace());

        JsonObject begin = Assert.Single(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
        var expected = new List<string>(RecordedPaths());
        expected.Remove("courses/ICS3U/section1/All Classes/Unit 1, Day 3.md");
        Assert.Equal(expected, OpPaths(begin));
        Assert.Equal(day3, File.ReadAllText(Page("Unit 1, Day 3")));
        foreach (JsonElement file in Recorded.GetProperty("files").EnumerateArray())
        {
            string path = file.GetProperty("path").GetString()!;
            if (path.EndsWith("Unit 1, Day 3.md", StringComparison.Ordinal)) continue;
            Assert.Equal(file.GetProperty("after").GetString(), File.ReadAllText(UndoDoor.FullPath(Folder, path)));
        }
    }

    /// <summary>No new page and no renamed page is ever left Hidden (the swap hides only what it keeps aside).</summary>
    [Fact]
    public void NoNewOrRenamedPageIsEverHidden()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);

        WindowsActionsOnTheMacFixture.Run(StepName, Workspace());

        foreach (string path in RecordedPaths())
        {
            FileAttributes attributes = File.GetAttributes(UndoDoor.FullPath(Folder, path));
            Assert.False(attributes.HasFlag(FileAttributes.Hidden), $"{path} is Hidden");
        }
        string classes = Path.GetDirectoryName(Page("Unit 1, Day 2"))!;
        Assert.Empty(Directory.GetFiles(classes, ".*plantoir-undo-*"));
    }

    /// <summary>
    /// A rename onto a name a teacher's page took after the plan was shown is
    /// carried past and named at plan time, the teacher's page never written
    /// over; the rest is made, in ONE step.
    /// </summary>
    [Fact]
    public void ARenameOntoATakenNameIsCarriedPastNamedAndTheRestMade()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        var workspace = Workspace();
        var plan = workspace.PlanInsertClasses("ICS3U", 1, unit: 1, atDay: 2, count: 1);
        const string teachers = "---\ntitle: Unit 1, Day 4\npublish: false\n---\nMy own page.\n";
        File.WriteAllText(Page("Unit 1, Day 4"), teachers);

        var result = workspace.ApplyInsertClasses(plan);

        Assert.Equal(teachers, File.ReadAllText(Page("Unit 1, Day 4")));
        Assert.StartsWith("Renamed 0,", result.Message);
        Assert.Contains(AssistWording.PagesAChangeCouldNotFinish(new[] { "Unit 1, Day 3", "Unit 1, Day 2" }), result.Message);
        // The re-dates still planned are made together, as one step.
        JsonObject begin = Assert.Single(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
        Assert.DoesNotContain("courses/ICS3U/section1/All Classes/Unit 1, Day 4.md", OpPaths(begin));
    }

    /// <summary>
    /// A page that cannot be written (read-only) changes nothing: every page's
    /// bytes as before, no step applied, said "Nothing was changed" — never
    /// carried past with the rest written (#550's old trail).
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
            var plan = workspace.PlanInsertClasses("ICS3U", 1, unit: 1, atDay: 2, count: 1);
            // Every page of the section (the backup taken before the step is
            // elsewhere, and is the action's own).
            string section = Path.Combine(Folder, "courses", "ICS3U", "section1");
            List<string> before = WindowsActionsOnTheMacFixture.EveryFileBut(section, ListFolder);

            var refused = Assert.Throws<AssistRefusal>(() => workspace.ApplyInsertClasses(plan));

            Assert.Equal("Nothing was changed: Plantoir doesn’t have permission to change one of them.", refused.Message);
            Assert.Equal(before, WindowsActionsOnTheMacFixture.EveryFileBut(section, ListFolder));
            Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
            Assert.False(workspace.TakeWhetherTheCallChangedAnything(workspace.TopOfTheUndoList));
        }
        finally { File.SetAttributes(later, FileAttributes.Normal); }
    }

    /// <summary>
    /// The door leaves the step part way (another program writes into a page
    /// as it is swapped, and putting it back fails): the part-way sentence,
    /// naming the kept file, never "Nothing was changed", "saved" or
    /// "couldn’t be read".
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

        Assert.StartsWith(AssistWording.PublishStoppedPartWay("the classes you made room among", ""), answered);
        string classes = Path.GetDirectoryName(Page("Unit 1, Day 3"))!;
        string kept = Assert.Single(Directory.GetFiles(classes, ".*.plantoir-undo-*-orig"));
        Assert.Contains(Path.GetFileName(kept), answered, StringComparison.Ordinal);
        Assert.DoesNotContain("Nothing was changed", answered, StringComparison.Ordinal);
        Assert.DoesNotContain("couldn’t be read", answered, StringComparison.Ordinal);
    }

    /// <summary>Reports a progress line SYNCHRONOUSLY, so a test can change the folder at the moment a stage of the planning begins.</summary>
    private sealed class AtTheStage(string stage, Action then) : IProgress<string>
    {
        public void Report(string value) { if (value.StartsWith(stage, StringComparison.Ordinal)) then(); }
    }

    /// <summary>
    /// Every before is read at plan time: another program edits the later
    /// class (its link already planned) while the new page is being planned,
    /// and the step is refused rather than written over it. The edit is kept,
    /// no class is renamed, and nothing is applied.
    /// </summary>
    [Fact]
    public void AnEditMadeWhileItPlansIsNeverWrittenOver()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        var workspace = Workspace();
        var plan = workspace.PlanInsertClasses("ICS3U", 1, unit: 1, atDay: 2, count: 1);
        string later = Page("Unit 2, Day 1");
        const string byHand = "---\ntitle: Unit 2, Day 1\n---\n\nWritten by hand while it planned.\n";

        Assert.Throws<AssistRefusal>(() =>
            workspace.ApplyInsertClasses(plan, new AtTheStage("Adding the new", () => File.WriteAllText(later, byHand))));

        Assert.Equal(byHand, File.ReadAllText(later));
        Assert.False(File.Exists(Page("Unit 1, Day 4")), "a class was renamed");
        Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
    }

    /// <summary>A plan that changes nothing makes no step and writes nothing, a backup included.</summary>
    [Fact]
    public void APlanThatChangesNothingMakesNoStepAndNoWrite()
    {
        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        var workspace = Workspace();
        var real = workspace.PlanInsertClasses("ICS3U", 1, unit: 1, atDay: 2, count: 1);
        var nothing = new InsertPlan
        {
            CourseCode = real.CourseCode, SectionNumber = real.SectionNumber, Unit = real.Unit, AtDay = real.AtDay,
            Naming = real.Naming, Added = [], Renames = [], Moves = [], LinksToRewrite = 0, Problems = [],
        };
        List<string> before = WindowsActionsOnTheMacFixture.EveryFileBut(Folder, ListFolder);

        var result = workspace.ApplyInsertClasses(nothing);

        Assert.Equal("Nothing needed moving.", result.Message);
        Assert.Equal(0, WindowsActionsOnTheMacFixture.Begins(ListFolder));
        Assert.Equal(before, WindowsActionsOnTheMacFixture.EveryFileBut(Folder, ListFolder));
    }

    /// <summary>
    /// A later class page that is a symbolic link, with the switch off. Pinned
    /// as Windows does it, which differs from the mac by name: the mac's
    /// clause of <c>undo.rule.shadow</c> (U4b2-1, 2026-11-25) never follows a
    /// link it removes or renames away, so its step is refused before anything
    /// changes. Windows writes the step plainly, as Make Room always wrote it:
    /// a plain copy at the new name, the link itself removed (and a page the
    /// chain writes where it stood is a plain file), the file it led to never
    /// touched, and no step recorded. The pieces that move a link (U4b2-14
    /// and 15) settle which of the two holds; until then this test holds the
    /// difference by name (it took the place of the ledger's
    /// Reason899W7b2MakeRoomLinkedPage row when Make Room was converted), and
    /// it reads the clause: once the contract no longer states both sides, it
    /// fails, so the difference never outlives its requirement. For a link to
    /// a file outside the working folder and one inside it alike, as the
    /// clause says.
    /// </summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacRefusesBeforeAnythingChanges_UntilU4b2Pieces14And15(bool insideTheWorkingFolder)
    {
        string clause = UndoContract.Undo.GetProperty("rule").GetProperty("shadow").GetString()!;
        const string settle = "undo.rule.shadow no longer states the linked-page difference this test holds: settle it (U4b2-14 and 15) and change this test to the contract's one rule";
        Assert.True(clause.Contains("never follows the link and is refused before anything changes", StringComparison.Ordinal), settle + " (the mac's refusal is gone)");
        Assert.True(clause.Contains("saving a plain copy at the new name and deleting the link itself, the linked file left untouched", StringComparison.Ordinal), settle + " (Windows' plain copy is gone)");
        Assert.True(clause.Contains("held by name in UndoMakeRoomStepTests." + nameof(ALinkedLaterClassIsWrittenPlainlyWithTheLinkRemovedAndItsFileUntouched_WhereTheMacRefusesBeforeAnythingChanges_UntilU4b2Pieces14And15), StringComparison.Ordinal),
                    "undo.rule.shadow no longer names this test as where the difference is held");

        WindowsActionsOnTheMacFixture.Lay(Folder, Recorded);
        string linked = Page("Unit 1, Day 3");
        string outside = insideTheWorkingFolder ? Path.Combine(Folder, "elsewhere") : Path.Combine(_root, "elsewhere");
        Directory.CreateDirectory(outside);
        string target = Path.Combine(outside, "Unit 1, Day 3.md");
        byte[] targetBytes = File.ReadAllBytes(linked);
        File.WriteAllBytes(target, targetBytes);
        File.Delete(linked);
        File.CreateSymbolicLink(linked, target);

        string answered = WindowsActionsOnTheMacFixture.Run(StepName, Workspace());

        Assert.Contains("Renamed 2,", answered, StringComparison.Ordinal);
        Assert.Equal(targetBytes, File.ReadAllBytes(target));
        Assert.Null(new FileInfo(Page("Unit 1, Day 4")).LinkTarget);
        Assert.Null(new FileInfo(linked).LinkTarget);
        foreach (JsonElement file in Recorded.GetProperty("files").EnumerateArray())
        {
            string full = UndoDoor.FullPath(Folder, file.GetProperty("path").GetString()!);
            Assert.Equal(file.GetProperty("after").GetString(), File.ReadAllText(full));
        }
        // Written plainly, without the list: no step applied.
        Assert.Empty(WindowsActionsOnTheMacFixture.AppliedBegins(ListFolder));
    }
}

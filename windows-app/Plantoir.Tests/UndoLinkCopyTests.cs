using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// #899 W8b-21b1a (Windows only; Russell's Q2, 2026-11-27, "Copy the lesson
/// instead"): where this PC cannot make a symbolic link
/// (<see cref="UndoLinks.CanMakeALink"/>, answered here by the seam saying
/// no), a step that would re-point a link instead sets the link aside, as
/// itself, under <c>.&lt;name&gt;.link-kept-by-undo</c> beside it, and writes a
/// plain copy of its lesson at the link's new place
/// (<see cref="UndoActionStep.CopyTheLessonInsteadOfALink"/>), with plain ops
/// only, so making, Undo and Redo need no privilege. The shape is Insert
/// Class's, by hand: Day 4 a link holding <c>Unit 1, Day 3.md</c>; the copy
/// planned at Day 5; Day 3's page written at Day 4 and removed; a new Day 3.
/// </summary>
public sealed class UndoLinkCopyTests : IDisposable
{
    private const string Section = "courses/TST1O/section1";
    private const string LinkText = "Unit 1, Day 3.md";

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-link-copy-");
    private readonly List<UndoTrailLine> _trail = [];

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private string Folder => Path.Combine(_root, "wf");
    private string ListFolder => Path.Combine(_root, "state", "undo");

    private static string Day(int number) => Section + "/Unit 1, Day " + number + ".md";

    private static string SetAside(string suffix = "") => Section + "/.Unit 1, Day 4.md.link-kept-by-undo" + suffix;

    private string Full(string relative) => UndoDoor.FullPath(Folder, relative);

    private void Write(string relative, string text)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Full(relative))!);
        File.WriteAllText(Full(relative), text);
    }

    /// <summary>Day 3 a plain page, Day 4 a link holding <paramref name="target"/> (Day 3's name by default).</summary>
    private void ACourse(string target = LinkText)
    {
        Directory.CreateDirectory(Path.Combine(Folder, "courses", "TST1O"));
        File.WriteAllText(Path.Combine(Folder, Plantoir.Core.Models.Workspace.MarkerLauncher), "");
        Write("courses/TST1O/course_config.json", "{\"course_code\":\"TST1O\"}");
        Write(Day(3), "Three.\n");
        File.CreateSymbolicLink(Full(Day(4)), target);
    }

    private UndoForThisProcess List() => new(ListFolder, UndoMode.Shadow, _trail.Add);

    private UndoActionStep Step(UndoForThisProcess list, string? workingFolder) =>
        new(new UndoStepMaker("sheet", "insertClass"), workingFolder, "TST1O", 1, undo: list);

    /// <summary>The seam saying no: this PC cannot make a link.</summary>
    private static readonly UndoSeams NoLinks = new() { CanMakeALinkAnswers = false };

    /// <summary>Every entry under the working folder but courses/.internal: a link by the target it holds, a file by its bytes, a folder by null.</summary>
    private SortedDictionary<string, string?> Tree()
    {
        var tree = new SortedDictionary<string, string?>(StringComparer.Ordinal);
        foreach (string entry in Directory.EnumerateFileSystemEntries(Folder, "*", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(Folder, entry).Replace('\\', '/');
            if (UndoOp.PartInside("courses/.internal", relative) is not null) continue;
            if (UndoLinks.Look(entry) == UndoLinks.What.Link) tree[relative] = "link " + new FileInfo(entry).LinkTarget;
            else tree[relative] = Directory.Exists(entry) ? null : "file " + File.ReadAllText(entry);
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

    /// <summary>Insert Class's plan before Day 3, by hand, the copy first; it says it copied.</summary>
    private void PlanInsertClassBeforeDay3(UndoActionStep step)
    {
        Assert.False(UndoLinks.CanMakeALink(NoLinks));
        Assert.True(step.CopyTheLessonInsteadOfALink(Full(Day(4)), Full(Day(5))));
        step.Write(Full(Day(4)), "Three.\n");
        step.Remove(Full(Day(3)));
        step.Write(Full(Day(3)), "New.\n");
        Assert.Equal([Path.GetFullPath(Full(Day(5)))], step.CopiedInsteadOfLinks);
    }

    private void AssertTheEndTree(string setAside)
    {
        Assert.Equal(UndoLinks.What.File, UndoLinks.Look(Full(Day(5))));
        Assert.Equal("Three.\n", File.ReadAllText(Full(Day(5))));
        Assert.Equal(UndoLinks.What.Link, UndoLinks.Look(Full(setAside)));
        Assert.Equal(LinkText, new FileInfo(Full(setAside)).LinkTarget);
        Assert.Equal(UndoLinks.What.File, UndoLinks.Look(Full(Day(4))));
        Assert.Equal("Three.\n", File.ReadAllText(Full(Day(4))));
        Assert.Equal("New.\n", File.ReadAllText(Full(Day(3))));
    }

    [SymbolicLinkFact]
    public void TheLinkIsSetAsideAndItsLessonCopiedInOneStepUndoneAndRedoneExactly()
    {
        ACourse();
        SortedDictionary<string, string?> before = Tree();
        UndoForThisProcess list = List();
        UndoActionStep step = Step(list, Folder);

        PlanInsertClassBeforeDay3(step);
        step.Make();

        AssertTheEndTree(SetAside());
        JsonArray ops = Assert.Single(Begins())["step"]!["ops"]!.AsArray();
        // The link moved as itself, and nothing else planned at its set-aside name: nothing written through it.
        int atTheSetAsideName = 0;
        foreach (JsonNode? op in ops)
        {
            if ((string?)op!["path"] == SetAside()) atTheSetAsideName++;
            if ((string?)op["to"] == SetAside())
            {
                Assert.Equal(Day(4), (string?)op["from"]);
                Assert.Equal(UndoLinkMoveTests.ShaOfTarget(LinkText), (string?)op["linkSha"]);
            }
        }
        Assert.Equal(0, atTheSetAsideName);
        Assert.Empty(_trail);
        SortedDictionary<string, string?> after = Tree();

        Assert.Equal(UndoOutcomeKind.Undone, list.Door().Undo().Kind);
        Assert.Equal(before, Tree());
        Assert.Equal("link " + LinkText, Tree()[Day(4)]);
        Assert.Equal(UndoOutcomeKind.Redone, list.Door().Redo().Kind);
        Assert.Equal(after, Tree());
    }

    [SymbolicLinkFact]
    public void ASetAsideNameAlreadyTakenGivesTheNextOne()
    {
        ACourse();
        Write(SetAside(), "Somebody's.\n");
        UndoActionStep step = Step(List(), Folder);

        PlanInsertClassBeforeDay3(step);
        step.Make();

        AssertTheEndTree(SetAside("-2"));
        Assert.Equal("Somebody's.\n", File.ReadAllText(Full(SetAside())));
    }

    [SymbolicLinkFact]
    public void ACopyEditedSinceIsChangedSinceAndUndoChangesNothing()
    {
        ACourse();
        UndoForThisProcess list = List();
        UndoActionStep step = Step(list, Folder);
        PlanInsertClassBeforeDay3(step);
        step.Make();
        File.WriteAllText(Full(Day(5)), "Three, edited.\n");
        SortedDictionary<string, string?> edited = Tree();

        UndoOutcome outcome = list.Door().Undo();

        Assert.Equal(UndoOutcomeKind.Refused, outcome.Kind);
        Assert.Equal(UndoRefusalKind.ChangedSince, outcome.Refusal!.Kind);
        Assert.Equal(edited, Tree());
    }

    [SymbolicLinkFact]
    public void UnrecordedTheSameStepGivesTheSameEndTree()
    {
        ACourse();
        UndoActionStep recorded = Step(List(), Folder);
        PlanInsertClassBeforeDay3(recorded);
        recorded.Make();
        SortedDictionary<string, string?> recordedTree = Tree();
        Directory.Delete(Folder, recursive: true);
        ACourse();
        _trail.Clear();
        int beginsBefore = Begins().Count;

        // No working folder: the list cannot take the step, and with the switch off it is made plainly.
        UndoActionStep plain = Step(List(), null);
        PlanInsertClassBeforeDay3(plain);
        plain.Make();

        AssertTheEndTree(SetAside());
        Assert.Equal(recordedTree, Tree());
        Assert.Equal(beginsBefore, Begins().Count);
    }

    /// <summary>A link leading nowhere has no lesson: nothing is copied or planned, and its caller moves it as itself.</summary>
    [SymbolicLinkFact]
    public void ALinkLeadingNowhereIsNeverCopied()
    {
        ACourse("Unit 1, Day 9.md");
        UndoActionStep step = Step(List(), Folder);

        Assert.False(step.CopyTheLessonInsteadOfALink(Full(Day(4)), Full(Day(5))));

        Assert.False(step.ChangesAnything);
        Assert.Empty(step.CopiedInsteadOfLinks);
    }

    /// <summary>
    /// Window E review 1, LOW 2: a probe link a killed process left under the
    /// probe's own fixed name is removed by the next probe, as the link
    /// itself; anything there that is not a link is left as it is, and the
    /// probe still answers.
    /// </summary>
    [SymbolicLinkTheory]
    [InlineData("a link")]
    [InlineData("a file")]
    public void TheNextProbeRemovesALeftoverProbeLinkAndNothingElse(string leftover)
    {
        Directory.CreateDirectory(ListFolder);
        string fixedName = Path.Combine(ListFolder, ".can-make-a-link");
        if (leftover == "a link") File.CreateSymbolicLink(fixedName, ".can-make-a-link-target");
        else File.WriteAllText(fixedName, "Someone's.\n");

        Assert.True(UndoLinks.CanMakeALinkIn(ListFolder));

        var left = new List<string>();
        foreach (string entry in Directory.EnumerateFileSystemEntries(ListFolder)) left.Add(Path.GetFileName(entry));
        if (leftover == "a link") Assert.Empty(left);
        else
        {
            Assert.Equal([".can-make-a-link"], left);
            Assert.Equal("Someone's.\n", File.ReadAllText(fixedName));
        }
    }

    /// <summary>
    /// Not a symbolic-link fact: on a PC that can make a link (Developer Mode
    /// on) the answer is true, on a machine that cannot make links false, and either
    /// way the probe leaves nothing in the list's folder.
    /// </summary>
    [Fact]
    public void CanMakeALinkSaysWhatMakingOneInATemporaryFolderDoes()
    {
        string temporary = Path.Combine(_root, "probe");
        Directory.CreateDirectory(temporary);
        bool made;
        try
        {
            File.CreateSymbolicLink(Path.Combine(temporary, "link.md"), "page.md");
            made = true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { made = false; }
        Directory.CreateDirectory(ListFolder);
        File.WriteAllText(Path.Combine(ListFolder, "journal-1.jsonl"), "");

        Assert.Equal(made, UndoLinks.CanMakeALinkIn(ListFolder));
        Assert.Equal(made, UndoLinks.CanMakeALink());
        Assert.Equal(["journal-1.jsonl"], Directory.EnumerateFileSystemEntries(ListFolder).Select(Path.GetFileName));
        Assert.False(UndoLinks.CanMakeALink(NoLinks));
    }
}

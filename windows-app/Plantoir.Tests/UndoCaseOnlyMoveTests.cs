using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// A capitalisation-only move on Windows (#899 W8-5; the mac's U4b part C,
/// <c>opKinds.move</c>): a <c>move</c> whose <c>from</c> and <c>to</c> are
/// spelled alike but for case, in the last part only, is readable; on NTFS the
/// two spellings are one item, judged by the spelling its folder lists and
/// renamed by ONE rename only while the folder lists the spelling it leaves.
/// </summary>
public sealed class UndoCaseOnlyMoveTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "plantoir-case-only-" + Guid.NewGuid().ToString("N"));

    public UndoCaseOnlyMoveTests() => Directory.CreateDirectory(_folder);

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); }
        catch (IOException) { }
    }

    private List<string> Listed(string folder)
    {
        var names = new List<string>();
        foreach (string entry in Directory.EnumerateFileSystemEntries(folder)) names.Add(Path.GetFileName(entry));
        return names;
    }

    /// <summary>
    /// The measured rename (the PC, NTFS): MoveFileEx without
    /// MOVEFILE_REPLACE_EXISTING renames <c>Media</c> to <c>media</c>, a folder
    /// and a file, answers 0, and the parent then lists the new spelling; onto
    /// another item it is refused (183) and replaces nothing.
    /// </summary>
    [Fact]
    public void ACaseOnlyRenameIsOneMoveFileExThatReplacesNothing()
    {
        Directory.CreateDirectory(Path.Combine(_folder, "Media"));
        File.WriteAllText(Path.Combine(_folder, "Media", "a.md"), "A\n");
        File.WriteAllText(Path.Combine(_folder, "Page.md"), "P\n");

        Assert.Equal(0, UndoSwap.Rename(Path.Combine(_folder, "Media"), Path.Combine(_folder, "media"), replace: false));
        Assert.Equal(0, UndoSwap.Rename(Path.Combine(_folder, "Page.md"), Path.Combine(_folder, "page.md"), replace: false));

        List<string> names = Listed(_folder);
        names.Sort(StringComparer.Ordinal);
        Assert.Equal(["media", "page.md"], names);
        Assert.Equal("A\n", File.ReadAllText(Path.Combine(_folder, "media", "a.md")));

        Directory.CreateDirectory(Path.Combine(_folder, "Other"));
        Assert.Equal(183, UndoSwap.Rename(Path.Combine(_folder, "media"), Path.Combine(_folder, "Other"), replace: false));
        Assert.True(File.Exists(Path.Combine(_folder, "media", "a.md")));
    }

    private static UndoOp Op(JsonObject json)
    {
        using JsonDocument document = JsonDocument.Parse(json.ToJsonString());
        return UndoFormat.ReadOp(document.RootElement);
    }

    private static JsonObject FileMove(string from, string to) => new()
    {
        ["kind"] = "move", ["from"] = from, ["to"] = to,
        ["sha"] = UndoCheck.Sha(Encoding.UTF8.GetBytes("{\"site_id\": \"aaa-111\"}\n")),
    };

    [Theory]
    [InlineData("courses/TST1O/m/a.json", "courses/TST1O/m/A.json")]
    [InlineData("courses/TST1O/Media", "courses/TST1O/media")]
    [InlineData("courses/TST1O/media", "courses/TST1O/MEDIA")]
    public void ACaseOnlyMoveInTheLastPartIsReadable(string from, string to)
    {
        Assert.True(Op(FileMove(from, to)).Readable);
    }

    [Theory]
    [InlineData("courses/TST1O/M/a.json", "courses/TST1O/m/a.json")]
    [InlineData("courses/TST1O/M/a.json", "courses/TST1O/m/A.json")]
    [InlineData("courses/tst1o/Media", "courses/TST1O/media")]
    [InlineData("courses/TST1O/Media", "courses/TST1O/Media")]
    [InlineData("courses/TST1O/Media", "courses/TST1O/media/inside")]
    public void ACaseDifferenceAboveTheLastPartStaysNotReadable(string from, string to)
    {
        Assert.False(Op(FileMove(from, to)).Readable);
    }

    private const string Course = "courses/TST1O";
    private const string Old = Course + "/Media";
    private const string New = Course + "/media";
    private static readonly byte[] OldA = Encoding.UTF8.GetBytes("Intro.\nLine one: old.\nEnd.\n");
    private static readonly byte[] NewA = Encoding.UTF8.GetBytes("Intro.\nLine one: new.\nEnd.\n");

    private static JsonObject HunkAt(string path) => new()
    {
        ["kind"] = "replaceText", ["path"] = path, ["before"] = "old", ["after"] = "new",
        ["contextBefore"] = "Line one: ", ["contextAfter"] = ".\n",
    };

    /// <summary>The spelling the course folder lists for the media folder, or null.</summary>
    private static string? Spelled(UndoScribe scribe)
    {
        foreach (string entry in Directory.EnumerateFileSystemEntries(scribe.FullPath("A", Course)))
        {
            string name = Path.GetFileName(entry);
            if (string.Equals(name.ToLowerInvariant(), "media", StringComparison.Ordinal)) return name;
        }
        return null;
    }

    /// <summary>
    /// The trap the mac had: a case-only move carrying an edit named with a
    /// part above the folder spelled another way (<c>courses/tst1o/media/a.md</c>,
    /// the same place on NTFS). Undone, the edit's kept original inside the
    /// folder is left out of the swap's last look and followed when the folder
    /// moves, and the folder goes back by ONE rename; redone and undone again,
    /// nothing staged or kept is left anywhere.
    /// </summary>
    [Fact]
    public void ACaseOnlyMoveCarryingAnEditInsideIsUndoneAndRedoneAndItsKeptOriginalFollowed()
    {
        using var scribe = new UndoScribe();
        scribe.WritePage("A", Old + "/a.md", OldA);
        scribe.WritePage("A", Old + "/b.md", Encoding.UTF8.GetBytes("B\n"));
        string listingSha = UndoTreeReading.Read(scribe.FullPath("A", Old)).ListingSha!;
        var move = new JsonObject { ["kind"] = "move", ["from"] = Old, ["to"] = New, ["listingSha"] = listingSha };

        UndoOutcome made = scribe.Door().Perform(scribe.OpsDraft("A", new JsonArray(move, HunkAt("courses/tst1o/media/a.md")), []));
        Assert.Equal(UndoOutcomeKind.Applied, made.Kind);
        Assert.Equal("media", Spelled(scribe));
        Assert.Equal(NewA, scribe.Page("A", New + "/a.md"));

        string course = scribe.FullPath("A", Course);
        var folderRenames = new List<(string From, string Onto)>();
        var seams = new UndoSeams
        {
            EachRename = (from, onto) =>
            {
                if (string.Equals(Path.GetDirectoryName(from), course, StringComparison.OrdinalIgnoreCase)
                    || string.Equals(Path.GetDirectoryName(onto), course, StringComparison.OrdinalIgnoreCase))
                    folderRenames.Add((Path.GetFileName(from), Path.GetFileName(onto)));
            },
        };
        Assert.Equal("undone", scribe.Door(seams).Undo().Word);
        Assert.Equal([("media", "Media")], folderRenames);
        Assert.Equal("Media", Spelled(scribe));
        Assert.Equal(OldA, scribe.Page("A", Old + "/a.md"));
        Assert.Empty(scribe.StagedLeftovers("A"));

        Assert.Equal("redone", scribe.Redo().Name);
        Assert.Equal("media", Spelled(scribe));
        Assert.Equal(NewA, scribe.Page("A", New + "/a.md"));
        Assert.Empty(scribe.StagedLeftovers("A"));

        Assert.Equal("undone", scribe.Undo().Name);
        Assert.Equal("Media", Spelled(scribe));
        Assert.Equal(OldA, scribe.Page("A", Old + "/a.md"));
        Assert.Empty(scribe.StagedLeftovers("A"));
    }

    /// <summary>An edit named at the <c>from</c> spelling is inside the place the move leaves: not carried, a barrier (the own part told apart as spelled).</summary>
    [Fact]
    public void AnEditNamedAtTheOldSpellingIsNotCarried()
    {
        UndoOp move = Op(new JsonObject { ["kind"] = "move", ["from"] = Old, ["to"] = New, ["listingSha"] = new UndoTreeListing([], []).Sha });
        Assert.True(move.Readable);
        Assert.True(UndoOp.MoveCarries(move, Op(HunkAt(New + "/a.md"))));
        Assert.True(UndoOp.MoveCarries(move, Op(HunkAt("courses/tst1o/media/a.md"))));
        Assert.False(UndoOp.MoveCarries(move, Op(HunkAt(Old + "/a.md"))));
        Assert.False(UndoStep.WholeOpsStandAlone([move, Op(HunkAt(Old + "/a.md"))]));
    }
}

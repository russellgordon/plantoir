using System.Text;
using System.Text.Json.Nodes;
using Plantoir.Core.Assist;

namespace Plantoir.Tests;

/// <summary>
/// What Undo Last Change does with each file a change touched, and when the
/// change comes off the list (#564, the mac's #555 and its
/// <c>UndoFilesContractTests</c>). Every row is read from
/// <c>contracts/assist-cases.json</c> → <c>undoFiles</c> and driven through
/// the real <see cref="UndoHistory"/> against real files in a temporary
/// folder; nothing typed here could disagree with the rows.
/// </summary>
public sealed class UndoFilesContractTests : IDisposable
{
    private readonly List<string> _folders = new();

    public void Dispose()
    {
        foreach (string folder in _folders)
            try { Directory.Delete(folder, recursive: true); } catch { }
    }

    private static JsonObject Family => ContractLoader.LoadJson("assist-cases.json")["undoFiles"]!.AsObject();

    /// <summary>Every <c>files</c> row: one saved file, one press, one verdict, and the disk afterwards.</summary>
    [Fact]
    public void EveryFileRowGetsItsVerdict()
    {
        Assert.NotNull(Family["note"]);
        var rows = Family["files"]!.AsArray();
        Assert.True(rows.Count >= 14, "files rows have gone missing");
        var seen = new HashSet<string>();
        foreach (var row in rows)
        {
            string name = row!["name"]!.ToString();
            Assert.True(row["why"] is not null, $"{name} has no stated reason");
            string expect = row["expect"]!.ToString();
            seen.Add(expect);
            string folder = MakeFolder();
            string path = Path.Combine(folder, "page.md");
            string? before = row["before"]?.GetValue<string>();
            string? after = row["after"]?.GetValue<string>();
            Lay(row.AsObject(), path);
            byte[]? laidOut = File.Exists(path) ? File.ReadAllBytes(path) : null;

            var state = new UndoHistory.FileState(before, after);
            Assert.True(expect == Camel(UndoVerdict.Of(path, state)), $"{name}: verdict before the press");

            var history = new UndoHistory();
            history.Remember(Change(new Dictionary<string, UndoHistory.FileState> { [path] = state }));
            var result = history.Undo();
            string verdict = result.Restored.Contains(path) ? "putBack"
                           : result.AlreadyBack.Contains(path) ? "alreadyBack" : "leftAlone";
            Assert.True(expect == verdict, $"{name}: {verdict}");
            Assert.True((history.Entries.Count == 0) == (expect != "leftAlone"), $"{name}: whether the change came off the list");

            if (expect == "putBack")
            {
                if (before is not null) Assert.True(before == File.ReadAllText(path), $"{name}: not put back");
                else Assert.False(File.Exists(path), $"{name}: not removed");
            }
            else
            {
                Assert.True(Untouched(path, laidOut, row.AsObject()), $"{name}: the file was changed");
            }
        }
        Assert.Equal(new HashSet<string> { "putBack", "alreadyBack", "leftAlone" }, seen);
    }

    /// <summary>
    /// Every <c>presses</c> row: several files, Undo pressed step by step,
    /// with the counts, the change left on the list, the sentence and the
    /// Section menu's trail ending each press must give.
    /// </summary>
    [Fact]
    public void EveryPressRowEndsAsTheContractSays()
    {
        var rows = Family["presses"]!.AsArray();
        Assert.True(rows.Count >= 3, "presses rows have gone missing");
        foreach (var row in rows)
        {
            string name = row!["name"]!.ToString();
            Assert.True(row["why"] is not null, $"{name} has no stated reason");
            string folder = MakeFolder();
            var files = new Dictionary<string, UndoHistory.FileState>(StringComparer.OrdinalIgnoreCase);
            foreach (var fileRow in row["files"]!.AsArray())
            {
                string path = Path.Combine(folder, fileRow!["name"]!.ToString());
                Lay(fileRow.AsObject(), path);
                files[path] = new UndoHistory.FileState(fileRow["before"]?.GetValue<string>(), fileRow["after"]?.GetValue<string>());
            }
            var history = new UndoHistory();
            history.Remember(Change(files));

            int index = 0;
            foreach (var step in row["steps"]!.AsArray())
            {
                string label = $"{name}, press {++index}";
                if (step!["edit"] is JsonObject edits)
                {
                    foreach (var (fileName, text) in edits)
                    {
                        string path = Path.Combine(folder, fileName);
                        if (text is null) File.Delete(path);
                        else File.WriteAllText(path, text.GetValue<string>());
                    }
                }
                int entriesBefore = history.Entries.Count;
                var result = history.Undo();
                Assert.True(step["expectPutBack"]!.GetValue<int>() == result.Restored.Count, $"{label}: put back {result.Restored.Count}");
                Assert.True(step["expectAlreadyBack"]!.GetValue<int>() == result.AlreadyBack.Count, $"{label}: already back {result.AlreadyBack.Count}");
                Assert.True(step["expectLeftAlone"]!.GetValue<int>() == result.Skipped.Count, $"{label}: left alone {result.Skipped.Count}");
                Assert.True(step["expectEntriesLeft"]!.GetValue<int>() == history.Entries.Count, $"{label}: changes left {history.Entries.Count}");
                Assert.True(step["expectSentence"]!.ToString() == Camel(result.Answer), $"{label}: sentence {Camel(result.Answer)}");

                // The server notes a write with no new undo entry exactly when
                // it answers undidPartly (PlantoirTools.UndoLastChange), and the
                // menu's ending is read from that and from the list moving.
                var answer = AssistToolAnswer.Same("") with
                {
                    Changed = history.Entries.Count != entriesBefore || result.Answer == UndoAnswer.UndidPartly,
                };
                string ending = SectionVerbs.Ending("undo_last_change", answer, entriesBefore, history.Entries.Count, "ICS3U", 1);
                Assert.True(step["expectEnding"]!.ToString() == ending, $"{label}: trail ending {ending}");
            }
        }
    }

    /// <summary>Each sentence a press can be answered with is a real wording key.</summary>
    [Fact]
    public void EverySentenceNamedIsAWordingKey()
    {
        var wording = ContractLoader.LoadJson("assist-wording.json")["wording"]!.AsObject();
        foreach (var answer in Enum.GetValues<UndoAnswer>())
            Assert.True(wording.ContainsKey(Camel(answer)), $"{Camel(answer)} is not a wording key");
    }

    /// <summary>A page saved with a byte-order mark is the same page: the copies were read without it (the plan review's B1).</summary>
    [Fact]
    public void APageWithAByteOrderMarkStillMatchesItsCopy()
    {
        string path = Path.Combine(MakeFolder(), "page.md");
        File.WriteAllText(path, "the page as the change left it", new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
        Assert.Equal(0xEF, File.ReadAllBytes(path)[0]);
        Assert.Equal(UndoVerdict.Kind.PutBack,
                     UndoVerdict.Of(path, new UndoHistory.FileState("the page before the change", "the page as the change left it")));

        File.WriteAllBytes(path, new byte[] { 0xEF, 0xBB, 0xBF, 0xFF, 0xFE });
        Assert.Equal(UndoVerdict.Kind.LeftAlone,
                     UndoVerdict.Of(path, new UndoHistory.FileState(null, "the page as the change left it")));
    }

    /// <summary>
    /// The start-of-year undo sheet sorts pages by the undo's own verdict
    /// before the teacher agrees, and the undo agrees with it: a page already
    /// back is in neither list and is not counted as put back.
    /// </summary>
    [Fact]
    public void TheStartOfYearUndoSortsPagesByTheSameVerdict()
    {
        string folder = MakeFolder();
        string untouched = Path.Combine(folder, "a.md"), back = Path.Combine(folder, "b.md"), edited = Path.Combine(folder, "c.md");
        File.WriteAllText(untouched, "after a");
        File.WriteAllText(back, "before b");
        File.WriteAllText(edited, "after c, edited since");
        var written = new Dictionary<string, (string Before, string After)>
        {
            [untouched] = ("before a", "after a"), [back] = ("before b", "after b"), [edited] = ("before c", "after c"),
        };

        var (wouldPutBack, wouldLeave) = AssistWorkspace.WhatAnUndoWouldDo(written);
        Assert.Equal(new[] { untouched }, wouldPutBack);
        Assert.Equal(new[] { edited }, wouldLeave);

        var (putBack, left) = AssistWorkspace.UndoStartOfYear(written);
        Assert.Equal(wouldPutBack, putBack);
        Assert.Equal(wouldLeave, left);
        Assert.Equal("before a", File.ReadAllText(untouched));
        Assert.Equal("before b", File.ReadAllText(back));
        Assert.Equal("after c, edited since", File.ReadAllText(edited));

        File.WriteAllText(edited, "before c");
        Assert.Equal((0, 0), (AssistWorkspace.WhatAnUndoWouldDo(written).PutBack.Count, AssistWorkspace.WhatAnUndoWouldDo(written).LeftAsTheyAre.Count));
    }

    private static UndoHistory.Entry Change(Dictionary<string, UndoHistory.FileState> files) =>
        new("published 2 pages", DateTime.Now, files);

    private string MakeFolder()
    {
        string folder = Directory.CreateTempSubdirectory("plantoir-undo-files-").FullName;
        _folders.Add(folder);
        return folder;
    }

    private static string Camel<T>(T value) where T : Enum
    {
        string name = value.ToString();
        return char.ToLowerInvariant(name[0]) + name[1..];
    }

    /// <summary>Put at the path what the row says is there now.</summary>
    private static void Lay(JsonObject row, string path)
    {
        string? kind = row["currentKind"]?.ToString();
        if (kind == "folder") { Directory.CreateDirectory(path); return; }
        if (kind == "notUTF8") { File.WriteAllBytes(path, new byte[] { 0xFF, 0xFE, 0x00, 0xC3, 0x28 }); return; }
        Assert.Null(kind);
        if (row["current"]?.GetValue<string>() is { } current) File.WriteAllText(path, current);
    }

    private static bool Untouched(string path, byte[]? laidOut, JsonObject row)
    {
        if (row["currentKind"]?.ToString() == "folder") return Directory.Exists(path);
        if (laidOut is null) return !File.Exists(path) && !Directory.Exists(path);
        return File.Exists(path) && File.ReadAllBytes(path).AsSpan().SequenceEqual(laidOut);
    }
}

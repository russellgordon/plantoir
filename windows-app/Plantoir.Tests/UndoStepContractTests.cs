using System.Text;
using System.Text.Json;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>contracts/shared-rules.json</c> → <c>undo.stepCases</c>, every case,
/// through the REAL door and the staged swap (#899 W2b). Each case's pages are
/// made in a working folder of its own, one step is made through
/// <see cref="UndoDoor.Perform(UndoStepDraft)"/>, the case's hand edit is made,
/// and Undo is asked of the door. A file in use at a swap is a REAL holder
/// (<c>FileShare.ReadWrite</c>, no delete sharing: the read succeeds and the
/// rename is refused 32), opened just before that swap; a staging write that
/// fails is the door's seam (a real full volume needs an administrator).
/// </summary>
public sealed class UndoStepContractTests : IDisposable
{
    private static readonly HashSet<string> KeysChecked = new(StringComparer.Ordinal)
    {
        "name", "pages", "step", "handEdit", "undo", "named", "others", "files", "phase", "fileInUseAtSwap", "stagingFailsAt", "why",
    };

    private readonly string _root = RunOwnedTempFolders.Create("plantoir-undo-steps-");

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    public static IEnumerable<object[]> Cases() =>
        UndoContract.Undo.GetProperty("stepCases").EnumerateArray()
            .Select(stepCase => new object[] { stepCase.GetProperty("name").GetString()! });

    [Fact]
    public void TheContractHoldsTheStepCases()
    {
        // 5 when W2b was written (U1's 3 and U2a's 2); a count that falls is a contract change to read.
        Assert.True(UndoContract.Undo.GetProperty("stepCases").GetArrayLength() >= 5);
    }

    [Theory]
    [MemberData(nameof(Cases))]
    public void EveryStepCase(string name)
    {
        JsonElement stepCase = UndoContract.Undo.GetProperty("stepCases").EnumerateArray()
            .Single(candidate => candidate.GetProperty("name").GetString() == name);
        foreach (JsonProperty key in stepCase.EnumerateObject())
            Assert.True(KeysChecked.Contains(key.Name), "a key this replay does not check: " + key.Name);

        string folder = Path.Combine(_root, "wf");
        string journalFolder = Path.Combine(_root, "undo");
        Directory.CreateDirectory(Path.Combine(folder, "courses", ".internal"));
        var clock = new UndoTestClock(new DateTimeOffset(2026, 11, 20, 12, 0, 0, TimeSpan.Zero));
        var journal = new UndoJournal(journalFolder, clock, process => process is not null && process.Pid == Environment.ProcessId,
                                      step => UndoJournalChecks.FolderIsReachable(step, clock), isLive: true,
                                      memory: new UndoProcessMemory(), readRetry: TimeSpan.Zero);

        int pages = stepCase.GetProperty("pages").GetInt32();
        string kind = stepCase.TryGetProperty("step", out JsonElement stepKind) ? stepKind.GetString()! : "oneLine";
        Assert.True(kind is "oneLine" or "twoLines", "a step this replay does not know: " + kind);
        var paths = new List<string>();
        var changes = new List<UndoFileChange>();
        for (int number = 1; number <= pages; number++)
        {
            string path = $"courses/TST1O/Section 1/Classes/Page {number}.md";
            string before = kind == "twoLines"
                ? $"---\ntitle: Page {number}\ndraft: true\n---\nBody.\n"
                : $"---\ntitle: Page {number}\npublish: false\n---\nBody.\n";
            string after = kind == "twoLines"
                ? $"---\ntitle: Page {number}\npublish: false\n---\nBody.\n"
                : JournaledSetting.SettingEntry("publish", "publish: true", before)!;
            Write(folder, path, before);
            changes.Add(new UndoFileChange(path, Encoding.UTF8.GetBytes(before), Encoding.UTF8.GetBytes(after)));
            paths.Add(path);
            if (kind == "twoLines")
            {
                // The step is two line ops on each page (stepCases: "two editLine ops").
                Assert.Equal(2, UndoLineOps.ForAFile(path, changes[^1].Before, changes[^1].After)
                    .Count(op => (string?)op!["kind"] == UndoOp.EditLine));
            }
        }
        var door = new UndoDoor(journal, UndoMode.Live);
        UndoOutcome made = door.Perform(new UndoStepDraft
        {
            ActionKey = "publishPages", MadeBy = "menu", WorkingFolder = folder, Course = "TST1O", Section = 1, Holds = "section",
            Changes = changes,
        });
        Assert.Equal(UndoOutcomeKind.Applied, made.Kind);

        string handEdit = stepCase.GetProperty("handEdit").GetString()!;
        int[] edited = handEdit switch
        {
            "none" => [],
            "line of page 2" => [2],
            "lines of pages 1 and 3" => [1, 3],
            "front matter of page 2 removed" => [],
            _ => throw new InvalidOperationException("a hand edit this replay does not know: " + handEdit),
        };
        foreach (int page in edited)
            Write(folder, paths[page - 1], UndoTraceEdits.HandEdit("sameLine", Read(folder, paths[page - 1]))!);
        if (handEdit == "front matter of page 2 removed") Write(folder, paths[1], "Body.\n");

        var snapshot = paths.Select(path => UndoCheck.Sha(File.ReadAllBytes(Full(folder, path)))).ToList();
        int? inUseAt = stepCase.TryGetProperty("fileInUseAtSwap", out JsonElement inUse) ? inUse.GetInt32() : null;
        int? stagingFailsAt = stepCase.TryGetProperty("stagingFailsAt", out JsonElement failing) ? failing.GetInt32() : null;
        FileStream? holder = null;
        UndoOutcome outcome;
        try
        {
            var seams = new UndoSeams
            {
                // A real holder that shares reading and writing but not delete,
                // as Word and many editors do: the re-read succeeds, the rename is refused.
                BeforeEachSwap = (index, fullPath) =>
                {
                    if (index == inUseAt) holder ??= new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                },
                StagingWriteFailsAt = index => index == stagingFailsAt,
            };
            outcome = new UndoDoor(journal, UndoMode.Live, seams: seams).Undo();
        }
        finally
        {
            holder?.Dispose();
        }

        Assert.Equal(stepCase.GetProperty("undo").GetString(), outcome.Word);
        if (stepCase.TryGetProperty("named", out JsonElement named))
        {
            int page = int.Parse(named.GetString()!["page ".Length..], System.Globalization.CultureInfo.InvariantCulture);
            Assert.Equal(paths[page - 1], outcome.Refusal?.Path);
            Assert.Equal(stepCase.GetProperty("others").GetInt32(), outcome.Refusal?.Others);
        }
        var now = paths.Select(path => UndoCheck.Sha(File.ReadAllBytes(Full(folder, path)))).ToList();
        switch (stepCase.GetProperty("files").GetString())
        {
            case "unchanged": Assert.Equal(snapshot, now); break;
            case "changed": Assert.NotEqual(snapshot, now); break;
            default: Assert.Fail("a files value this replay does not know"); break;
        }
        if (stepCase.TryGetProperty("phase", out JsonElement phase))
        {
            UndoReading reading = journal.Read();
            Assert.True(reading.IsFresh);
            Assert.Equal(phase.GetString(), UndoContract.Spelled(reading.Folded.Steps[made.Seq!.Value].State));
        }
        Assert.Empty(StagedFilesUnder(folder));
    }

    /// <summary>Every staged name anywhere in the working folder (<c>undoJournal.stagedFiles</c>): none may be left by any case.</summary>
    internal static IReadOnlyList<string> StagedFilesUnder(string folder) =>
        Directory.EnumerateFileSystemEntries(folder, "*", SearchOption.AllDirectories)
            .Where(path => Path.GetFileName(path).Contains(UndoSwap.StagedMarker, StringComparison.Ordinal)).ToList();

    private static string Full(string folder, string relative) => Path.Combine(folder, relative.Replace('/', Path.DirectorySeparatorChar));

    private static void Write(string folder, string relative, string text)
    {
        string path = Full(folder, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, Encoding.UTF8.GetBytes(text));
    }

    private static string Read(string folder, string relative) => UndoCheck.DecodeStrictly(File.ReadAllBytes(Full(folder, relative)))!;
}

using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using Microsoft.Win32.SafeHandles;
using Plantoir.Core.Assist;
using Plantoir.Core.Models;

namespace Plantoir.Tests;

/// <summary>
/// <c>course-management.json → backups</c> (#283 / mac #242): the pruning that
/// follows a new backup, the space backups take, and deleting several at once.
/// Every case is read from the contract, never retyped.
/// </summary>
[Collection(SharedActivityState.Name)]
public class BackupsContractTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"plantoir-backups-{Guid.NewGuid():N}");

    public BackupsContractTests()
    {
        Directory.CreateDirectory(_root);
        HeldBackups.Reset();
    }

    public void Dispose()
    {
        HeldBackups.Reset();
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    private static JsonObject Backups => ContractLoader.LoadJson("course-management.json")["backups"]!.AsObject();

    private string CoursesDir(string name)
    {
        string dir = Path.Combine(_root, name, "courses");
        Directory.CreateDirectory(dir);
        return dir;
    }

    [Fact]
    public void CourseManagement_Backups_PruneCases()
    {
        int n = 0;
        foreach (var c in Backups["pruneCases"]!.AsArray())
        {
            string course = c!["course"]!.ToString();
            string courses = CoursesDir($"prune{n++}");
            string dir = CourseArchiver.BackupsDirectory(courses, course);
            Directory.CreateDirectory(dir);
            foreach (var name in c["existing"]!.AsArray()) File.WriteAllText(Path.Combine(dir, name!.ToString()), "z");

            CourseArchiver.PruneBackups(course, courses, new DateTime(2026, 9, 20));

            var expectDeleted = c["expectDeleted"]!.AsArray().Select(x => x!.ToString()).ToHashSet();
            foreach (var name in c["existing"]!.AsArray().Select(x => x!.ToString()))
                Assert.True(File.Exists(Path.Combine(dir, name)) != expectDeleted.Contains(name),
                    $"{c["name"]}: {name} should {(expectDeleted.Contains(name) ? "" : "not ")}have been deleted.");
        }
    }

    [Fact]
    public void CourseManagement_Backups_SizeCases()
    {
        int n = 0;
        foreach (var c in Backups["sizeCases"]!.AsArray())
        {
            string courses = CoursesDir($"size{n++}");
            var found = new List<BackupItem>();
            foreach (var f in c!["files"]!.AsArray())
            {
                string course = f!["course"]!.ToString();
                string dir = CourseArchiver.BackupsDirectory(courses, course);
                Directory.CreateDirectory(dir);
                string path = Path.Combine(dir, f["name"]!.ToString());
                long bytes = f["bytes"]!.GetValue<long>();
                bool sparse = f["sparse"]?.GetValue<bool>() ?? false;
                MakeFile(path, bytes, sparse);
                if (BackupItem.From(path, course) is { } item) found.Add(item);
            }

            var summary = BackupSizes.Measure(found);

            var expected = c["expectCourses"]!.AsArray()
                .Select(e => (e!["courseCode"]!.ToString(), e["count"]!.GetValue<int>(), e["bytes"]!.GetValue<long>()))
                .ToList();
            Assert.Equal(expected, summary.Courses.Select(t => (t.CourseCode, t.Count, t.Bytes)).ToList());
            Assert.Equal(c["expectTotalCount"]!.GetValue<int>(), summary.TotalCount);
            Assert.Equal(c["expectTotalBytes"]!.GetValue<long>(), summary.TotalBytes);
            Assert.True(summary.EverySizeKnown);
        }
    }

    [Fact]
    public void CourseManagement_Backups_DeleteCases()
    {
        int n = 0;
        foreach (var c in Backups["deleteCases"]!.AsArray())
        {
            string courses = CoursesDir($"delete{n++}");
            string dir = CourseArchiver.BackupsDirectory(courses, "ICS3U");
            Directory.CreateDirectory(dir);
            var items = new Dictionary<string, BackupItem>();
            foreach (var name in c!["backups"]!.AsArray().Select(x => x!.ToString()))
            {
                string path = Path.Combine(dir, name);
                File.WriteAllText(path, "z");
                items[name] = BackupItem.From(path, "ICS3U")!;
            }
            var holds = c["heldByAnOpenConversation"]!.AsArray()
                .Select(x => HeldBackups.HoldWhileOpen(items[x!.ToString()].FilePath)).ToList();

            var held = HeldBackups.For(Path.GetDirectoryName(courses)!, items.Values, _ => Array.Empty<int>());
            var outcome = BackupDeleter.Delete(c["delete"]!.AsArray().Select(x => items[x!.ToString()]), held);
            holds.ForEach(h => h.Dispose());

            Assert.Equal(c["expectDeleted"]!.AsArray().Select(x => x!.ToString()).Order(),
                         outcome.Deleted.Select(b => Path.GetFileName(b.FilePath)).Order());
            Assert.Equal(c["expectKept"]!.AsArray().Select(x => x!.ToString()).Order(),
                         outcome.Kept.Select(b => Path.GetFileName(b.FilePath)).Order());
            foreach (var name in items.Keys)
                Assert.Equal(!outcome.Deleted.Any(b => Path.GetFileName(b.FilePath) == name),
                             File.Exists(Path.Combine(dir, name)));
        }
    }

    [Fact]
    public void TheSizeWordingIsTheContracts()
    {
        var wording = ContractLoader.LoadJson("assist-wording.json");
        var w = (wording["wording"] ?? wording)!;
        Assert.Equal(w["backupSizeCouldNotBeRead"]!.ToString(), AssistWording.BackupSizeCouldNotBeRead);
        Assert.Equal(w["backupSizeCouldNotBeReadShort"]!.ToString(), AssistWording.BackupSizeCouldNotBeReadShort);
    }

    // ---- Making the files ------------------------------------------------

    /// <summary>
    /// A file of <paramref name="bytes"/> LOGICAL size. A sparse one (the shape
    /// of a file a cloud service has evicted) is marked sparse with
    /// FSCTL_SET_SPARSE before its length is set, so it costs no disk: by
    /// allocation it is nearly nothing, by length its whole size. Needs NTFS;
    /// anywhere else the test FAILS naming why rather than skipping, because a
    /// skipped sparse case is a green line that tested nothing (plan risk 3).
    /// </summary>
    private static void MakeFile(string path, long bytes, bool sparse)
    {
        using var stream = new FileStream(path, FileMode.Create, FileAccess.ReadWrite);
        if (sparse)
        {
            Assert.True(OperatingSystem.IsWindows(), "The sparse case needs Windows (FSCTL_SET_SPARSE).");
            bool ok = DeviceIoControl(stream.SafeFileHandle, FsctlSetSparse, IntPtr.Zero, 0, IntPtr.Zero, 0, out _, IntPtr.Zero);
            Assert.True(ok, $"Could not mark {path} sparse (error {Marshal.GetLastWin32Error()}); the temp folder is not on NTFS.");
        }
        stream.SetLength(bytes);
    }

    private const uint FsctlSetSparse = 0x000900C4;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(SafeFileHandle device, uint code, IntPtr inBuffer, int inSize,
                                               IntPtr outBuffer, int outSize, out int returned, IntPtr overlapped);
}

public class BackupSizesTests
{
    private static BackupItem Item(string name, string course = "ICS3U") =>
        BackupItem.From($@"C:\x\_backups\{course}\{name}", course)!;

    [Fact]
    public void AnUnknownSizeIsLeftOutOfTheTotalAndCounted()
    {
        var summary = BackupSizes.Summarize(new (BackupItem, long?)[]
        {
            (Item("ICS3U_backup_2026-09-01_120000.zip"), 100),
            (Item("ICS3U_backup_2026-09-02_120000.zip"), null),
        });
        Assert.Equal(100, summary.TotalBytes);
        Assert.Equal(2, summary.TotalCount);
        Assert.Equal(1, summary.Unknown);
        Assert.False(summary.EverySizeKnown);
    }

    [Fact]
    public void AStaleMeasurementIsDropped()
    {
        var generation = new MeasurementGeneration();
        int first = generation.Begin();
        int second = generation.Begin();
        Assert.False(generation.IsCurrent(first));
        Assert.True(generation.IsCurrent(second));
    }

    [Fact]
    public void AFileThatCannotBeReadHasNoSize() =>
        Assert.Null(BackupSizes.LogicalSize(Path.Combine(Path.GetTempPath(), $"missing-{Guid.NewGuid():N}.zip")));
}

[Collection(SharedActivityState.Name)]
public class BackupDeleterTests
{
    private static BackupItem Item(string name) => BackupItem.From($@"C:\x\_backups\ICS3U\{name}", "ICS3U")!;

    [Fact]
    public void OneFileThatWillNotDeleteIsReportedAndTheOthersStillGo()
    {
        var a = Item("ICS3U_backup_2026-09-01_120000.zip");
        var b = Item("ICS3U_backup_2026-09-02_120000.zip");
        var c = Item("ICS3U_backup_2026-09-03_120000.zip");
        var gone = new List<BackupItem>();
        var outcome = BackupDeleter.Delete(new[] { a, b, c }, new HashSet<string>(),
            item => { if (item == b) throw new IOException("in use"); gone.Add(item); });
        Assert.Equal(new[] { a, c }, outcome.Deleted);
        Assert.Single(outcome.Failed);
        Assert.Equal(b, outcome.Failed[0].Item);
    }

    /// <summary>
    /// Ruling 9: an outside assistant's hold is the zip ON ITS RECORD, counted
    /// only while that pid holds a live assist lease — not "the newest
    /// assistant backup", which released its zip whenever the app's own
    /// assistant had made a later one. A FAKE pid stands for plantoir-mcp.
    /// </summary>
    [Fact]
    public void TheBackupOnAnotherProgramsRecordIsHeldAndOnlyWhileItLives()
    {
        string work = Path.Combine(Path.GetTempPath(), $"plantoir-heldrecord-{Guid.NewGuid():N}");
        try
        {
            string theirs = Path.Combine(work, "courses", "_backups", "ICS3U", "ICS3U_backup_2026-08-01_120000_assistant-section2.zip");
            string later = Path.Combine(work, "courses", "_backups", "ICS3U", "ICS3U_backup_2026-09-02_120000_assistant-section2.zip");
            string record = HeldBackups.RecordFor(work, "ICS3U", 424242);
            Directory.CreateDirectory(Path.GetDirectoryName(record)!);
            File.WriteAllText(record, theirs);
            var backups = new[] { BackupItem.From(theirs, "ICS3U")!, BackupItem.From(later, "ICS3U")! };

            var held = HeldBackups.For(work, backups, _ => new[] { 424242 });
            Assert.Contains(Path.GetFullPath(theirs), held);
            Assert.DoesNotContain(Path.GetFullPath(later), held);

            Assert.Empty(HeldBackups.For(work, backups, _ => Array.Empty<int>()));   // the session is gone
        }
        finally { try { Directory.Delete(work, true); } catch { } }
    }

    [Fact]
    public void HoldsAreCountedSoOneOfTwoClosingKeepsTheHold()
    {
        HeldBackups.Reset();
        string zip = Path.Combine(Path.GetTempPath(), "ICS3U_backup_2026-09-02_120000_assistant-section2.zip");
        var first = HeldBackups.HoldWhileOpen(zip);
        var second = HeldBackups.HoldWhileOpen(zip);
        first.Dispose();
        Assert.Contains(Path.GetFullPath(zip), HeldBackups.InThisApp());
        second.Dispose();
        Assert.DoesNotContain(Path.GetFullPath(zip), HeldBackups.InThisApp());
    }

    [Fact]
    public void TheTrailLineNamesFilesAndWhatWasKept()
    {
        var a = Item("ICS3U_backup_2026-09-01_120000.zip");
        var k = Item("ICS3U_backup_2026-09-02_120000_assistant-section2.zip");
        var outcome = new BackupDeleter.Outcome(new[] { a }, new[] { k }, Array.Empty<BackupDeleter.Failure>());
        string line = BackupDeleter.TrailLine(outcome, new Dictionary<string, long?> { [a.FilePath] = 11_300_000 });
        Assert.Contains("deleted 1 backup of ICS3U, 11.3 MB together: ICS3U_backup_2026-09-01_120000.zip", line);
        Assert.Contains("kept because an open assistant conversation can restore from it: ICS3U_backup_2026-09-02_120000_assistant-section2.zip", line);
    }

    /// <summary>
    /// #468 (mac #458, <c>backups deleted.carries</c>): what a Claude or Codex
    /// session still open made is named APART from what the window holds —
    /// the window's clause as it always read, the session's beside it.
    /// </summary>
    [Fact]
    public void TheTrailLineTellsASessionsKeptBackupFromTheWindows()
    {
        var a = Item("ICS3U_backup_2026-09-01_120000.zip");
        var window = Item("ICS3U_backup_2026-09-02_120000_assistant-section2.zip");
        var session = Item("ICS3U_backup_2026-09-03_120000_assistant-section1.zip");
        var outcome = new BackupDeleter.Outcome(new[] { a }, new[] { window, session }, Array.Empty<BackupDeleter.Failure>());
        string line = BackupDeleter.TrailLine(outcome, new Dictionary<string, long?>(),
            new HashSet<string>(StringComparer.OrdinalIgnoreCase) { Path.GetFullPath(session.FilePath) });
        Assert.Contains("; kept because an open assistant conversation can restore from it: ICS3U_backup_2026-09-02_120000_assistant-section2.zip;", line);
        Assert.Contains("; kept ICS3U_backup_2026-09-03_120000_assistant-section1.zip, which a Claude or Codex session still open made", line);
        Assert.DoesNotContain("restore from it: ICS3U_backup_2026-09-02_120000_assistant-section2.zip, ICS3U_backup_2026-09-03", line);
    }
}

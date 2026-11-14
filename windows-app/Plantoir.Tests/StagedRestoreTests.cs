using System.Diagnostics;
using System.IO.Compression;
using System.Security.Cryptography;
using Plantoir.Core.Models;
using Xunit;

namespace Plantoir.Tests;

/// <summary>
/// Restoring from a backup never leaves a course emptied or half restored
/// (#873): the zip is unpacked BESIDE the course, checked, and swapped in with
/// the old contents set aside until the swap has succeeded.
///
/// <para><b>What a test here proves, and how.</b> The tests that go through
/// the PUBLIC restore (<see cref="CourseRestorer.RestoreBackup(BackupItem, string)"/>)
/// were each run against the old <c>CourseRestorer.cs</c>, copied into place
/// and back (the copy-aside method), and failed there: the held file, the
/// unusable %TEMP%, the held file in a section. The ones that need a step to
/// fail or a kill to land exactly between two moves use the internal
/// <see cref="StagedRestore.Steps"/> seam, which the old code does not have;
/// those were proved red by turning the putting back off
/// (<c>StagedRestore.PutBack</c> returning at once), recorded in
/// documentation/12-windows-app.md.</para>
///
/// <para><b>ProcessEnvironment</b>: <c>PLANTOIR_BUILD_ROOT</c> is pointed at
/// the test's own folder so no restore reaches the real
/// <c>%LOCALAPPDATA%\Plantoir\builds</c>, and one test moves <c>TMP</c>.</para>
/// </summary>
[Collection(ProcessEnvironment.Name)]
public sealed class StagedRestoreTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "plantoir-staged-" + Guid.NewGuid().ToString("N")[..12]);
    private readonly string? _buildRootBefore = Environment.GetEnvironmentVariable("PLANTOIR_BUILD_ROOT");

    private string CoursesDir => Path.Combine(_root, "courses");
    private string CourseDir => Path.Combine(CoursesDir, "ICS3U");
    private string BuildsRoot => Path.Combine(_root, "builds");

    public StagedRestoreTests()
    {
        Directory.CreateDirectory(CourseDir);
        Environment.SetEnvironmentVariable("PLANTOIR_BUILD_ROOT", BuildsRoot);
        File.WriteAllText(Path.Combine(CourseDir, "course_config.json"), """{"course_code":"ICS3U","section_numbers":[1]}""");
        File.WriteAllText(Path.Combine(CourseDir, "Learning Goals.md"), "original goals");
        Directory.CreateDirectory(Path.Combine(CourseDir, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(CourseDir, "section1", "All Classes", "Unit 1, Day 1.md"), "day one");
        Directory.CreateDirectory(Path.Combine(CourseDir, "Media"));
        File.WriteAllBytes(Path.Combine(CourseDir, "Media", "picture.png"), new byte[] { 1, 2, 3, 4 });
        Directory.CreateDirectory(Path.Combine(CourseDir, ".obsidian"));
        File.WriteAllText(Path.Combine(CourseDir, ".obsidian", "app.json"), "{}");
    }

    public void Dispose()
    {
        Environment.SetEnvironmentVariable("PLANTOIR_BUILD_ROOT", _buildRootBefore);
        try
        {
            foreach (string file in Directory.EnumerateFiles(_root, "*", SearchOption.AllDirectories))
                try { File.SetAttributes(file, FileAttributes.Normal); } catch { }
            Directory.Delete(_root, recursive: true);
        }
        catch { }
    }

    // ---- helpers ---------------------------------------------------------

    private Course Course() => Workspace.DiscoverCourses(_root).First(c => c.Code == "ICS3U");

    private BackupItem BackUp() => BackupItem.From(CourseArchiver.BackUpCourse(Course(), CoursesDir), "ICS3U")!;

    /// <summary>Every entry under a folder, relative, with a hash of each file's bytes ("dir" for a folder).</summary>
    private static SortedDictionary<string, string> Snapshot(string folder)
    {
        var found = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in new DirectoryInfo(folder).EnumerateFileSystemInfos("*", new EnumerationOptions
                 { RecurseSubdirectories = true, AttributesToSkip = 0, IgnoreInaccessible = false }))
        {
            string relative = Path.GetRelativePath(folder, entry.FullName);
            found[relative] = (entry.Attributes & FileAttributes.Directory) != 0
                ? "dir"
                : Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(entry.FullName)));
        }
        return found;
    }

    /// <summary>What the teacher did since the backup: a page rewritten, one added, a folder added.</summary>
    private void ChangeSinceTheBackup()
    {
        File.WriteAllText(Path.Combine(CourseDir, "Learning Goals.md"), "rewritten since");
        File.WriteAllText(Path.Combine(CourseDir, "Added since.md"), "new page");
        Directory.CreateDirectory(Path.Combine(CourseDir, "Unit 2"));
        File.WriteAllText(Path.Combine(CourseDir, "Unit 2", "Plan.md"), "unit two");
    }

    private IEnumerable<string> Leftovers() =>
        Directory.EnumerateDirectories(CoursesDir, StagedRestore.Prefix + "*");

    /// <summary>A seam that fails the Nth move, or stops dead there as a kill would.</summary>
    private sealed class FailingSteps(int failAtMove, bool asAKill = false, int hresult = 0, bool killOnceSwapped = false) : StagedRestore.Steps
    {
        private int _moves;
        public List<(string From, string To)> Moves { get; } = new();

        public override void AfterStep(string phase, int movesSoFar)
        {
            if (killOnceSwapped && phase == "done") throw new StagedRestore.StopHereForATest();
        }

        public override void Move(string source, string target)
        {
            _moves++;
            if (_moves == failAtMove)
            {
                if (asAKill) throw new StagedRestore.StopHereForATest();
                throw hresult != 0 ? new IOException("injected", hresult) : new IOException("injected");
            }
            Moves.Add((source, target));
            base.Move(source, target);
        }
    }

    // ---- through the public restore: red on the old code ---------------------

    [Fact]
    public void AFileHeldOpenPartWayThroughLeavesTheCourseExactlyAsItWas()
    {
        var backup = BackUp();
        ChangeSinceTheBackup();
        var before = Snapshot(CourseDir);

        // Held the way an editor or a terminal holds it: no FILE_SHARE_DELETE,
        // so neither the file nor the folder it is in can be renamed or deleted.
        // "Unit 2" sorts after the folders the old restore deleted first.
        using (new FileStream(Path.Combine(CourseDir, "Unit 2", "Plan.md"), FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            Assert.ThrowsAny<Exception>(() => CourseRestorer.RestoreBackup(backup, CoursesDir));
        }

        Assert.Equal(before, Snapshot(CourseDir));
        Assert.Empty(Leftovers());
        Assert.True(File.Exists(backup.FilePath));
    }

    [Fact]
    public void ATempFolderThatCannotBeUsedDoesNotMatterBecauseNothingIsUnpackedThere()
    {
        // The stand-in for %TEMP% on another volume: the old restore made its
        // staging folder in Path.GetTempPath() and could not restore at all when
        // that was unusable. The new one never asks for it.
        var backup = BackUp();
        ChangeSinceTheBackup();
        string? tmp = Environment.GetEnvironmentVariable("TMP");
        string? temp = Environment.GetEnvironmentVariable("TEMP");
        string unusable = Path.Combine(_root, "not-a-folder.txt");
        File.WriteAllText(unusable, "a file where the temporary folder should be");
        try
        {
            Environment.SetEnvironmentVariable("TMP", unusable);
            Environment.SetEnvironmentVariable("TEMP", unusable);
            CourseRestorer.RestoreBackup(backup, CoursesDir);
        }
        finally
        {
            Environment.SetEnvironmentVariable("TMP", tmp);
            Environment.SetEnvironmentVariable("TEMP", temp);
        }
        Assert.Equal("original goals", File.ReadAllText(Path.Combine(CourseDir, "Learning Goals.md")));
        Assert.False(File.Exists(Path.Combine(CourseDir, "Added since.md")));
        Assert.Empty(Leftovers());
    }

    [Fact]
    public void ASectionWithAFileHeldOpenIsLeftExactlyAsItWas()
    {
        var backup = BackupItem.From(CourseArchiver.BackUpCourse(Course(), CoursesDir, new BackupMaker.Assistant(1)), "ICS3U")!;
        string section = Path.Combine(CourseDir, "section1");
        File.WriteAllText(Path.Combine(section, "All Classes", "Unit 1, Day 1.md"), "rewritten");
        Directory.CreateDirectory(Path.Combine(section, "Zed"));
        File.WriteAllText(Path.Combine(section, "Zed", "held.md"), "held");
        var before = Snapshot(section);

        using (new FileStream(Path.Combine(section, "Zed", "held.md"), FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            Assert.ThrowsAny<Exception>(() => CourseRestorer.RestoreSection(1, backup, CoursesDir));
        }

        Assert.Equal(before, Snapshot(section));
        Assert.Empty(Leftovers());
    }

    // ---- through the public restore: guards (pass on the old code too) ---

    [Fact]
    public void AFileHeldTheWayObsidianHoldsOneDoesNotStopTheRestore()
    {
        // FILE_SHARE_DELETE, which Node (and so Obsidian) opens with: the file
        // can be renamed aside while open. What cannot be deleted at once is
        // left for the next launch; the course is the backup's either way.
        var backup = BackUp();
        ChangeSinceTheBackup();
        using (new FileStream(Path.Combine(CourseDir, "Learning Goals.md"), FileMode.Open, FileAccess.Read,
                              FileShare.ReadWrite | FileShare.Delete))
        {
            CourseRestorer.RestoreBackup(backup, CoursesDir);
        }
        Assert.Equal("original goals", File.ReadAllText(Path.Combine(CourseDir, "Learning Goals.md")));
        Assert.False(Directory.Exists(Path.Combine(CourseDir, "Unit 2")));
        StagedRestore.RecoverLeftovers(CoursesDir, _ => false);
        Assert.Empty(Leftovers());
    }

    [Fact]
    public void AReadOnlyFileIsSetAsideAndRemovedWithTheRest()
    {
        var backup = BackUp();
        ChangeSinceTheBackup();
        string stubborn = Path.Combine(CourseDir, "Unit 2", "Plan.md");
        File.SetAttributes(stubborn, FileAttributes.ReadOnly);

        CourseRestorer.RestoreBackup(backup, CoursesDir);

        Assert.False(File.Exists(stubborn));
        Assert.Equal("original goals", File.ReadAllText(Path.Combine(CourseDir, "Learning Goals.md")));
        Assert.Empty(Leftovers());
    }

    [Fact]
    public void APathLongerThan260CharactersRestores()
    {
        string deep = CourseDir;
        while (deep.Length < 300) deep = Path.Combine(deep, "a folder with a long name");
        Directory.CreateDirectory(deep);
        string page = Path.Combine(deep, "Deep page.md");
        File.WriteAllText(page, "deep and original");
        Assert.True(page.Length > 260);
        var backup = BackUp();
        File.WriteAllText(page, "deep and rewritten");

        CourseRestorer.RestoreBackup(backup, CoursesDir);

        Assert.Equal("deep and original", File.ReadAllText(page));
        Assert.Empty(Leftovers());
    }

    [Fact]
    public void AJunctionInsideTheCourseIsSetAsideAsALinkAndWhatItPointsAtIsUntouched()
    {
        var backup = BackUp();
        string outside = Path.Combine(_root, "outside");
        Directory.CreateDirectory(outside);
        File.WriteAllText(Path.Combine(outside, "sentinel.txt"), "never touched");
        string junction = Path.Combine(CourseDir, "Linked");
        MakeJunction(junction, outside);

        CourseRestorer.RestoreBackup(backup, CoursesDir);

        Assert.False(Directory.Exists(junction));
        Assert.Equal("never touched", File.ReadAllText(Path.Combine(outside, "sentinel.txt")));
        Assert.Empty(Leftovers());
    }

    [Fact]
    public void AZipEntryThatWouldLandOutsideIsRefusedAndTheCourseIsAsItWas()
    {
        ChangeSinceTheBackup();
        var before = Snapshot(CourseDir);
        string zipPath = HandMadeBackup(("ICS3U/course_config.json", "{}"), ("ICS3U/../../escaped.txt", "out"));

        var error = Assert.Throws<CourseRestorer.RestoreException>(
            () => CourseRestorer.RestoreBackup(BackupItem.From(zipPath, "ICS3U")!, CoursesDir));

        Assert.StartsWith("The archive could not be opened:", error.Message);
        Assert.Equal(before, Snapshot(CourseDir));
        Assert.False(File.Exists(Path.Combine(_root, "escaped.txt")));
        Assert.False(File.Exists(Path.Combine(CoursesDir, "escaped.txt")));
        Assert.Empty(Leftovers());
    }

    [Fact]
    public void ALinkEntryInAZipArrivesAsAnOrdinaryFile()
    {
        // A symbolic-link entry as Info-ZIP writes one (Unix mode 0120777 in
        // the high half of the external attributes): .NET's extraction writes
        // its text, the link's target, as a plain file and makes no link.
        string zipPath = HandMadeBackup(("ICS3U/course_config.json", """{"course_code":"ICS3U","section_numbers":[1]}"""),
                                        ("ICS3U/escape", @"C:\Windows"));
        using (var zip = ZipFile.Open(zipPath, ZipArchiveMode.Update))
            zip.GetEntry("ICS3U/escape")!.ExternalAttributes = unchecked((int)(0xA1FFu << 16));

        CourseRestorer.RestoreBackup(BackupItem.From(zipPath, "ICS3U")!, CoursesDir);

        string arrived = Path.Combine(CourseDir, "escape");
        Assert.True(File.Exists(arrived));
        Assert.Equal(0, (int)(File.GetAttributes(arrived) & FileAttributes.ReparsePoint));
    }

    // ---- through the seam: a step fails, or a kill lands between two -----

    [Fact]
    public void AMoveThatFailsPartWayPutsEveryOldEntryBack()
    {
        var backup = BackUp();
        ChangeSinceTheBackup();
        var before = Snapshot(CourseDir);
        int moves = MovesOfTheSwap(backup);

        // Every move of the swap in turn: setting aside, and moving in.
        for (int failAt = 1; failAt <= moves; failAt++)
        {
            var steps = new FailingSteps(failAt);
            Assert.ThrowsAny<IOException>(() => CourseRestorer.RestoreBackup(backup, CoursesDir, steps));
            Assert.Equal(before, Snapshot(CourseDir));
            Assert.Empty(Leftovers());
        }
    }

    [Fact]
    public void AMoveRefusedBecauseItCrossesVolumesIsPutBackToo()
    {
        var backup = BackUp();
        ChangeSinceTheBackup();
        var before = Snapshot(CourseDir);
        var steps = new FailingSteps(failAtMove: 3, hresult: StagedRestore.NotSameDevice);

        var error = Assert.ThrowsAny<IOException>(() => CourseRestorer.RestoreBackup(backup, CoursesDir, steps));

        Assert.Equal(StagedRestore.NotSameDevice, error.HResult);
        Assert.Equal(before, Snapshot(CourseDir));
        Assert.Empty(Leftovers());
    }

    [Fact]
    public void EveryMoveIsARenameInsideTheCoursesFolder()
    {
        // The staging folder is beside the course, so each move is on the
        // course's own volume (measured below by the volume's own name).
        var backup = BackUp();
        ChangeSinceTheBackup();
        var steps = new FailingSteps(failAtMove: int.MaxValue);

        CourseRestorer.RestoreBackup(backup, CoursesDir, steps);

        Assert.NotEmpty(steps.Moves);
        string courses = Path.GetFullPath(CoursesDir) + Path.DirectorySeparatorChar;
        string volume = VolumeOf(CoursesDir);
        foreach (var (from, to) in steps.Moves)
        {
            Assert.StartsWith(courses, from, StringComparison.OrdinalIgnoreCase);
            Assert.StartsWith(courses, to, StringComparison.OrdinalIgnoreCase);
            Assert.Equal(volume, VolumeOf(Path.GetDirectoryName(to)!));
        }
    }

    [Fact]
    public void RunningOutOfDiskWhileUnpackingLeavesTheCourseAndNoLeftover()
    {
        var backup = BackUp();
        ChangeSinceTheBackup();
        var before = Snapshot(CourseDir);
        var steps = new DiskFillsWhileUnpacking();

        var error = Assert.Throws<CourseRestorer.RestoreException>(() => CourseRestorer.RestoreBackup(backup, CoursesDir, steps));

        Assert.StartsWith("The archive could not be opened:", error.Message);
        Assert.Equal(before, Snapshot(CourseDir));
        Assert.Empty(Leftovers());
    }

    /// <summary>Writes part of the zip, then fails as a full disk does (ERROR_DISK_FULL).</summary>
    private sealed class DiskFillsWhileUnpacking : StagedRestore.Steps
    {
        public override void Unpack(string archivePath, string into)
        {
            Directory.CreateDirectory(Path.Combine(into, "ICS3U"));
            File.WriteAllText(Path.Combine(into, "ICS3U", "course_config.json"), "{");
            throw new IOException("There is not enough space on the disk.", unchecked((int)0x80070070));
        }
    }

    [Fact]
    public void AKillAtAnyStepIsPutBackOrFinishedByTheNextLaunch()
    {
        var backup = BackUp();
        ChangeSinceTheBackup();
        var before = Snapshot(CourseDir);
        var after = SnapshotOfTheBackupRestored(backup);
        int moves = MovesOfTheSwap(backup);
        var outcomes = new List<StagedRestore.Recovery>();

        // A kill at each move, then one the moment the swap is done (moves + 1).
        for (int killAt = 1; killAt <= moves + 1; killAt++)
        {
            var steps = killAt <= moves
                ? new FailingSteps(killAt, asAKill: true)
                : new FailingSteps(int.MaxValue, killOnceSwapped: true);
            bool killed;
            try { CourseRestorer.RestoreBackup(backup, CoursesDir, steps); killed = false; }
            catch (StagedRestore.StopHereForATest) { killed = true; }

            if (killed)
            {
                // What the next launch finds: one leftover, recognisable by name.
                string leftover = Assert.Single(Leftovers());
                Assert.StartsWith(StagedRestore.Prefix + "ICS3U-", Path.GetFileName(leftover));
                Assert.DoesNotContain(Workspace.DiscoverCourses(_root), c => c.DirectoryPath.Contains(StagedRestore.Prefix));

                // Its owner is alive: left alone.
                Assert.Empty(StagedRestore.RecoverLeftovers(CoursesDir, _ => true));
                Assert.Single(Leftovers());

                var recovered = StagedRestore.RecoverLeftovers(CoursesDir, _ => false);
                Assert.Single(recovered);
                outcomes.Add(recovered[0].What);
                Assert.Empty(Leftovers());
                Assert.Equal(recovered[0].What == StagedRestore.Recovery.Finished ? after : before, Snapshot(CourseDir));
            }
            else
            {
                Assert.Equal(after, Snapshot(CourseDir));
            }

            // Back to the course as it was, for the next round.
            RestoreTheSnapshotState(before);
        }
        // A kill before the first move leaves only an unpacked zip, removed;
        // every later kill during the swap is put back; the one after it is finished.
        Assert.Equal(StagedRestore.Recovery.Removed, outcomes[0]);
        Assert.Equal(moves - 1, outcomes.Count(o => o == StagedRestore.Recovery.PutBack));
        Assert.Equal(StagedRestore.Recovery.Finished, outcomes[^1]);
    }

    /// <summary>How many renames a restore of this backup over the course makes: the course's children, then the backup's.</summary>
    private int MovesOfTheSwap(BackupItem backup)
    {
        using var zip = ZipFile.OpenRead(backup.FilePath);
        int incoming = zip.Entries.Select(e => e.FullName.Split('/')).Where(p => p.Length > 1 && p[1].Length > 0)
            .Select(p => p[1]).Distinct(StringComparer.OrdinalIgnoreCase).Count();
        return Directory.EnumerateFileSystemEntries(CourseDir).Count() + incoming;
    }

    [Fact]
    public void ALeftoverItCannotMakeSenseOfIsLeftWhereItIs()
    {
        string leftover = Path.Combine(CoursesDir, StagedRestore.Prefix + "ICS3U-999999-deadbeef");
        Directory.CreateDirectory(Path.Combine(leftover, "aside"));
        File.WriteAllText(Path.Combine(leftover, "aside", "only copy.md"), "precious");

        var recovered = StagedRestore.RecoverLeftovers(CoursesDir, _ => false);

        Assert.Equal(StagedRestore.Recovery.LeftInPlace, Assert.Single(recovered).What);
        Assert.Equal("precious", File.ReadAllText(Path.Combine(leftover, "aside", "only copy.md")));
    }

    [Fact]
    public void OnlyFoldersWithTheExactPrefixAreLookedAt()
    {
        string teachers = Path.Combine(CoursesDir, ".plantoir-restoringXYZ");
        string import = Path.Combine(CoursesDir, ReferenceStaging.Prefix + "ICS3U");
        Directory.CreateDirectory(teachers);
        Directory.CreateDirectory(import);

        Assert.Empty(StagedRestore.RecoverLeftovers(CoursesDir, _ => false));
        Assert.True(Directory.Exists(teachers));
        Assert.True(Directory.Exists(import));
    }

    // ---- the backup on the disk, and the recovery before the list ---------

    [Fact]
    public void TheZipIsFlushedToTheDiskBeforeItIsRelied_On()
    {
        string source = File.ReadAllText(Path.Combine(RepositoryRoot(), "windows-app", "Plantoir.Core", "Models", "CourseArchiver.cs"));
        int zipFolder = source.IndexOf("public static void ZipFolder(", StringComparison.Ordinal);
        int next = source.IndexOf("private static HashSet<string> PlantoirAddOnsIn", StringComparison.Ordinal);
        Assert.True(zipFolder > 0 && next > zipFolder);
        Assert.Contains("Flush(flushToDisk: true)", source[zipFolder..next]);
    }

    [Fact]
    public void LeftoversAreDealtWithBeforeTheCoursesAreListed()
    {
        string source = File.ReadAllText(Path.Combine(RepositoryRoot(), "windows-app", "Plantoir", "ViewModels", "WorkspaceViewModel.cs"));
        int recover = source.IndexOf("StagedRestore.RecoverLeftovers(", StringComparison.Ordinal);
        int discover = source.IndexOf("Workspace.DiscoverCourses(", StringComparison.Ordinal);
        Assert.True(recover > 0, "Reload never deals with a restore's leftovers");
        Assert.True(recover < discover);
    }

    // ---- small helpers ----------------------------------------------------

    private SortedDictionary<string, string> SnapshotOfTheBackupRestored(BackupItem backup)
    {
        var before = Snapshot(CourseDir);
        CourseRestorer.RestoreBackup(backup, CoursesDir);
        var after = Snapshot(CourseDir);
        RestoreTheSnapshotState(before);
        return after;
    }

    /// <summary>Puts the course back to the changed state the tests start from.</summary>
    private void RestoreTheSnapshotState(SortedDictionary<string, string> wanted)
    {
        foreach (string child in Directory.EnumerateFileSystemEntries(CourseDir)) CourseRestorer.DeleteTree(child);
        File.WriteAllText(Path.Combine(CourseDir, "course_config.json"), """{"course_code":"ICS3U","section_numbers":[1]}""");
        Directory.CreateDirectory(Path.Combine(CourseDir, "section1", "All Classes"));
        File.WriteAllText(Path.Combine(CourseDir, "section1", "All Classes", "Unit 1, Day 1.md"), "day one");
        Directory.CreateDirectory(Path.Combine(CourseDir, "Media"));
        File.WriteAllBytes(Path.Combine(CourseDir, "Media", "picture.png"), new byte[] { 1, 2, 3, 4 });
        Directory.CreateDirectory(Path.Combine(CourseDir, ".obsidian"));
        File.WriteAllText(Path.Combine(CourseDir, ".obsidian", "app.json"), "{}");
        ChangeSinceTheBackup();
        Assert.Equal(wanted, Snapshot(CourseDir));
    }

    private string HandMadeBackup(params (string Name, string Text)[] entries)
    {
        string dir = CourseArchiver.BackupsDirectory(CoursesDir, "ICS3U");
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "ICS3U_backup_2026-11-14_101500.zip");
        using var zip = ZipFile.Open(path, ZipArchiveMode.Create);
        foreach (var (name, text) in entries)
            using (var writer = new StreamWriter(zip.CreateEntry(name).Open())) writer.Write(text);
        return path;
    }

    private static void MakeJunction(string link, string target)
    {
        var start = new ProcessStartInfo("cmd.exe", $"/c mklink /J \"{link}\" \"{target}\"")
        { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
        using var process = Process.Start(start)!;
        process.WaitForExit();
        Assert.True(Directory.Exists(link), "mklink /J did not make the junction");
        Assert.NotEqual(0, (int)(File.GetAttributes(link) & FileAttributes.ReparsePoint));
    }

    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
    private static extern bool GetVolumePathNameW(string fileName, System.Text.StringBuilder volumePath, int length);

    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
    private static extern bool GetVolumeNameForVolumeMountPointW(string mountPoint, System.Text.StringBuilder volumeName, int length);

    /// <summary>The volume's own name (\\?\Volume{guid}\), never a drive letter, which subst can fake.</summary>
    private static string VolumeOf(string path)
    {
        var mount = new System.Text.StringBuilder(1024);
        Assert.True(GetVolumePathNameW(path, mount, mount.Capacity));
        var name = new System.Text.StringBuilder(1024);
        Assert.True(GetVolumeNameForVolumeMountPointW(mount.ToString(), name, name.Capacity));
        return name.ToString();
    }

    private static string RepositoryRoot()
    {
        string? folder = AppContext.BaseDirectory;
        while (folder is not null && !Directory.Exists(Path.Combine(folder, "contracts"))) folder = Path.GetDirectoryName(folder);
        // The test output holds a copy of contracts\; the repository also holds windows-app\.
        while (folder is not null && !Directory.Exists(Path.Combine(folder, "windows-app"))) folder = Path.GetDirectoryName(folder);
        return folder ?? throw new InvalidOperationException("repository root not found");
    }
}

using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.RegularExpressions;
using Plantoir.Core.Models;
using Xunit;
using Xunit.Abstractions;

namespace Plantoir.Tests;

/// <summary>
/// The NTFS lock on a reference course (#241, design A5): what it refuses and
/// what it allows, MEASURED on a real course folder in a temp directory —
/// the bundle-6 plan's §0 matrix as assertions. Every entry these tests set is
/// on files under a temp folder and is removed in <see cref="Dispose"/>, even
/// when an assertion fails.
/// </summary>
[Collection(ReferenceDiskCollection.Name)]
public class ReferenceLockTests : IDisposable
{
    private readonly string _root = Directory.CreateTempSubdirectory("plantoir-lock").FullName;
    private readonly ITestOutputHelper _output;

    public ReferenceLockTests(ITestOutputHelper output) => _output = output;

    public void Dispose()
    {
        ReferenceLock.Unlock(_root);
        try { Directory.Delete(_root, recursive: true); } catch { }
    }

    /// <summary>A small course: settings, a page beside them and below them, Obsidian's folder, a stray .tmp.</summary>
    private string Course(string name = "ICS3U-2025")
    {
        string course = Path.Combine(_root, "courses", name);
        Directory.CreateDirectory(Path.Combine(course, "Concepts"));
        Directory.CreateDirectory(Path.Combine(course, ".obsidian"));
        Directory.CreateDirectory(Path.Combine(course, "section1"));
        File.WriteAllText(Path.Combine(course, "course_config.json"), """{"course_code":"ICS3U","kept_for_reference":true}""");
        File.WriteAllText(Path.Combine(course, "Concepts", "Loops.md"), "---\ndraft: true\n---\n# Loops\n");
        File.WriteAllText(Path.Combine(course, "section1", "index.md"), "# Section 1\n");
        File.WriteAllText(Path.Combine(course, "Top page.md"), "# Top\n");
        File.WriteAllText(Path.Combine(course, ".obsidian", "workspace.json"), "{}");
        File.WriteAllText(Path.Combine(course, "course_config.json.tmp"), "{}");
        File.WriteAllText(Path.Combine(course, "desktop.ini"), "[.ShellClassInfo]");
        return course;
    }

    private static bool Refused(Action act)
    {
        try { act(); return false; }
        catch (UnauthorizedAccessException) { return true; }
        catch (IOException) { return true; }
    }

    [Fact]
    public void ALockedPageRefusesEveryOrdinaryChangeAndAllowsReading()
    {
        string course = Course();
        var outcome = ReferenceLock.Lock(course);
        Assert.Equal(3, outcome.Locked);
        Assert.True(outcome.IsQuiet || outcome.Locked > 0);
        Assert.True(outcome.EverythingThatShouldBeLockedIs, $"{outcome.LockedOnDisk} of {outcome.ShouldBeLocked}");

        string page = Path.Combine(course, "Concepts", "Loops.md");
        Assert.True(Refused(() => File.WriteAllText(page, "changed")), "write in place");
        Assert.True(Refused(() => File.AppendAllText(page, "more")), "append");
        string beside = Path.Combine(course, "Concepts", "Loops.md.new");
        File.WriteAllText(beside, "an editor's save");                                      // adding a file: allowed
        Assert.True(Refused(() => File.Move(beside, page, overwrite: true)), "rename-over");
        Assert.True(Refused(() => File.Replace(beside, page, null)), "File.Replace");
        Assert.True(Refused(() => File.Move(page, page + ".renamed")), "rename");
        Assert.True(Refused(() => File.Delete(page)), "delete");
        Assert.True(Refused(() => File.SetAttributes(page, FileAttributes.Hidden)), "attributes");
        Assert.True(Refused(() => Directory.Delete(course, recursive: true)), "removing the whole course");
        Assert.True(File.Exists(page));
        Assert.Contains("# Loops", File.ReadAllText(page));                                  // reading: allowed
    }

    [Fact]
    public void WhatPlantoirStillWritesIsLeftWritable()
    {
        string course = Course();
        ReferenceLock.Lock(course);

        // The build's preflight: an atomic replace of the never-locked settings.
        string config = Path.Combine(course, "course_config.json");
        File.WriteAllText(config + ".tmp", """{"course_code":"ICS3U","kept_for_reference":true,"shared_folders":[]}""");
        File.Move(config + ".tmp", config, overwrite: true);
        Assert.Contains("shared_folders", File.ReadAllText(config));

        // Obsidian's own folder, and a stray .tmp, and the shell's desktop.ini.
        File.WriteAllText(Path.Combine(course, ".obsidian", "workspace.json"), "{\"main\":{}}");
        File.WriteAllText(Path.Combine(course, "desktop.ini"), "[.ShellClassInfo]\nIconResource=x");
        Assert.False(ReferenceLock.IsLocked(Path.Combine(course, "course_config.json")));

        // The build output link, made and removed inside the course folder.
        string link = Path.Combine(course, ".merged_output");
        string target = Directory.CreateDirectory(Path.Combine(_root, "builds", "ICS3U-2025")).FullName;
        Assert.Equal(0, Run("cmd.exe", $"/c mklink /J \"{link}\" \"{target}\""));
        Assert.True(Directory.Exists(link));
        Directory.Delete(link);
        Assert.False(Directory.Exists(link));
    }

    [Fact]
    public void TheFolderAfterANeverLockedFileIsStillLocked()
    {
        // The mac's fault: a skip meant for course_config.json took the NEXT
        // folder with it. Here the walk skips files by name only, and the
        // census proves every page in every folder is locked.
        string course = Course();
        foreach (string folder in new[] { "a", "d", "z", "Unit 1" })
        {
            Directory.CreateDirectory(Path.Combine(course, folder));
            File.WriteAllText(Path.Combine(course, folder, "page.md"), "x");
        }
        var outcome = ReferenceLock.Lock(course);
        Assert.Equal(7, outcome.ShouldBeLocked);
        Assert.Equal(7, outcome.LockedOnDisk);
        foreach (string folder in new[] { "a", "d", "z", "Unit 1", "Concepts", "section1" })
            Assert.True(ReferenceLock.IsLocked(Directory.GetFiles(Path.Combine(course, folder))[0]), folder);
        Assert.False(ReferenceLock.IsLocked(Path.Combine(course, ".obsidian", "workspace.json")));
        Assert.False(ReferenceLock.IsLocked(Path.Combine(course, "course_config.json.tmp")));
        Assert.False(ReferenceLock.IsLocked(Path.Combine(course, "desktop.ini")));
    }

    [Fact]
    public void ASecondPassFindsNothingToDo()
    {
        string course = Course();
        ReferenceLock.Lock(course);
        var again = ReferenceLock.Lock(course);
        Assert.True(again.IsQuiet, again.ToString());
    }

    /// <summary>
    /// Bundle-6 ruling 4: a course half-locked by a crash is finished by the
    /// next pass, and a half-locked LEFTOVER is still removable once unlocked.
    /// </summary>
    [Fact]
    public void AHalfLockedCourseIsFinishedByTheNextPass()
    {
        string course = Course();
        ReferenceLock.Lock(Path.Combine(course, "Concepts"));   // the crash: one folder done
        var outcome = ReferenceLock.Lock(course);
        Assert.Equal(2, outcome.Locked);
        Assert.True(outcome.EverythingThatShouldBeLockedIs);
        ReferenceLock.Unlock(course);
        Directory.Delete(course, recursive: true);
        Assert.False(Directory.Exists(course));
    }

    [Fact]
    public void TheCensusSeesAPageThatLostItsLock()
    {
        string course = Course();
        ReferenceLock.Lock(course);
        ReferenceLock.Unlock(Path.Combine(course, "Top page.md"));   // a hand unlock in Explorer
        var census = ReferenceLock.Census(course);
        Assert.Equal(3, census.ShouldBeLocked);
        Assert.Equal(2, census.LockedOnDisk);
        Assert.Equal(1, ReferenceLock.Lock(course).Locked);          // re-asserted
    }

    [Fact]
    public void UnlockingLetsTheWholeCourseBeRemoved()
    {
        string course = Course();
        ReferenceLock.Lock(course);
        Assert.True(Refused(() => Directory.Delete(course, recursive: true)));
        ReferenceLock.Unlock(course);
        Directory.Delete(course, recursive: true);
        Assert.False(Directory.Exists(course));
    }

    /// <summary>
    /// Bundle-6 ruling 3: Unlock removes an entry of OUR SHAPE whoever it names
    /// — a course carried from another account still unlocks — and leaves a
    /// teacher's own entries alone.
    /// </summary>
    [Fact]
    public void AnEntryNamingAnotherAccountIsStillUnlockedAndATeachersOwnEntryIsKept()
    {
        string course = Course();
        string page = Path.Combine(course, "Concepts", "Loops.md");
        var stranger = new SecurityIdentifier("S-1-5-21-1111111111-2222222222-3333333333-1001");
        var security = new FileInfo(page).GetAccessControl();
        security.AddAccessRule(new FileSystemAccessRule(stranger, ReferenceLock.FileMask, AccessControlType.Deny));
        security.AddAccessRule(new FileSystemAccessRule(stranger, FileSystemRights.ReadData, AccessControlType.Deny));
        new FileInfo(page).SetAccessControl(security);
        var folderSecurity = new DirectoryInfo(Path.Combine(course, "Concepts")).GetAccessControl();
        folderSecurity.AddAccessRule(new FileSystemAccessRule(stranger, ReferenceLock.DirectoryMask, AccessControlType.Deny));
        new DirectoryInfo(Path.Combine(course, "Concepts")).SetAccessControl(folderSecurity);

        ReferenceLock.Unlock(course);

        var left = new FileInfo(page).GetAccessControl().GetAccessRules(true, false, typeof(SecurityIdentifier))
            .Cast<FileSystemAccessRule>().Where(rule => rule.AccessControlType == AccessControlType.Deny).ToList();
        var kept = Assert.Single(left);
        Assert.Equal(FileSystemRights.ReadData, kept.FileSystemRights & ~FileSystemRights.Synchronize);
        Assert.Empty(new DirectoryInfo(Path.Combine(course, "Concepts")).GetAccessControl()
            .GetAccessRules(true, false, typeof(SecurityIdentifier)).Cast<FileSystemAccessRule>()
            .Where(rule => rule.AccessControlType == AccessControlType.Deny));

        // Tidy the teacher's entry too, so Dispose leaves nothing behind.
        var tidy = new FileInfo(page).GetAccessControl();
        tidy.RemoveAccessRuleSpecific(kept);
        new FileInfo(page).SetAccessControl(tidy);
    }

    /// <summary>
    /// The lock does NOT travel through an ordinary copy — the reason it was
    /// chosen over the read-only attribute, which does.
    /// </summary>
    [Fact]
    public void ACopyOfALockedPageIsWritableAndACopyOfAReadOnlyOneIsNot()
    {
        string course = Course();
        ReferenceLock.Lock(course);
        string page = Path.Combine(course, "Concepts", "Loops.md");
        string copy = Path.Combine(_root, "copy.md");
        File.Copy(page, copy);
        File.WriteAllText(copy, "edited");                                  // an ACL never travels
        Assert.False(ReferenceLock.IsLocked(copy));

        string readOnly = Path.Combine(_root, "readonly.md");
        File.WriteAllText(readOnly, "x");
        File.SetAttributes(readOnly, FileAttributes.ReadOnly);
        string readOnlyCopy = Path.Combine(_root, "readonly-copy.md");
        File.Copy(readOnly, readOnlyCopy);
        Assert.True(File.GetAttributes(readOnlyCopy).HasFlag(FileAttributes.ReadOnly), "the attribute travels: the rejected design");
        ReferenceLock.Clear(_root);
        Assert.False(File.GetAttributes(readOnlyCopy).HasFlag(FileAttributes.ReadOnly));
    }

    /// <summary>
    /// Bundle-6 ruling 1, the honest limit: <c>robocopy /SEC</c> and
    /// <c>/COPYALL</c> carry the lock — and then stall retrying on it. Nothing
    /// in this repository may copy security that way.
    /// </summary>
    [Fact]
    public void NoRobocopyInThisRepositoryCopiesSecurity()
    {
        var copiesSecurity = new Regex(@"/(SEC|COPYALL|SECFIX)\b|/COPY:[A-Z]*S", RegexOptions.IgnoreCase);
        string root = ContractLoader.RepositoryRoot;
        var offenders = new List<string>();
        int robocopyCalls = 0;
        foreach (string file in Directory.EnumerateFiles(root, "*.*", SearchOption.AllDirectories)
                     .Where(f => f.EndsWith(".ps1") || f.EndsWith(".bat") || f.EndsWith(".cmd") || f.EndsWith(".py")
                                 || f.EndsWith(".sh") || (f.EndsWith(".cs") && !f.EndsWith("ReferenceLockTests.cs")))
                     .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}")
                                 && !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")
                                 && !f.Contains($"{Path.DirectorySeparatorChar}node_modules{Path.DirectorySeparatorChar}")
                                 && !f.Contains($"{Path.DirectorySeparatorChar}courses{Path.DirectorySeparatorChar}")))
        {
            foreach (string line in File.ReadLines(file).Where(l => l.Contains("robocopy", StringComparison.OrdinalIgnoreCase)
                                                                    && !l.TrimStart().StartsWith("#")
                                                                    && !l.TrimStart().StartsWith("//")))
            {
                robocopyCalls++;
                if (copiesSecurity.IsMatch(line)) offenders.Add($"{Path.GetRelativePath(root, file)}: {line.Trim()}");
            }
        }
        Assert.True(robocopyCalls >= 1, "found no robocopy call at all - the scan is looking in the wrong place");
        Assert.True(offenders.Count == 0, "robocopy carrying security would copy a reference course's lock: " + string.Join("; ", offenders));
    }

    /// <summary>
    /// The cost, measured, opt-in (<c>PLANTOIR_MEASURE=1</c>): lock, verify and
    /// unlock 1,200 files with .NET 9's ACL API. Written to the test output and
    /// copied into documentation/09 by hand; never asserted.
    /// </summary>
    [Fact]
    public void MeasureTheCostOnTwelveHundredFiles()
    {
        if (Environment.GetEnvironmentVariable("PLANTOIR_MEASURE") != "1") return;
        string course = Path.Combine(_root, "courses", "BIG-2025");
        for (int folder = 0; folder < 40; folder++)
        {
            Directory.CreateDirectory(Path.Combine(course, $"Unit {folder}"));
            for (int page = 0; page < 30; page++)
                File.WriteAllText(Path.Combine(course, $"Unit {folder}", $"Page {page}.md"), "# page\n");
        }
        var clock = Stopwatch.StartNew();
        var first = ReferenceLock.Lock(course);
        long lockMs = clock.ElapsedMilliseconds;
        clock.Restart();
        var second = ReferenceLock.Lock(course);
        long verifyMs = clock.ElapsedMilliseconds;
        clock.Restart();
        ReferenceLock.Unlock(course);
        long unlockMs = clock.ElapsedMilliseconds;
        _output.WriteLine($"lock {first.Locked} files: {lockMs} ms; a pass with nothing to do: {verifyMs} ms ({second.Locked} locked); unlock: {unlockMs} ms");
        Assert.Equal(1200, first.Locked);
    }

    private static int Run(string file, string arguments)
    {
        using var process = Process.Start(new ProcessStartInfo(file, arguments)
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
        })!;
        process.WaitForExit(30_000);
        return process.ExitCode;
    }
}

/// <summary>
/// The tests that lock, copy and remove real course folders on disk run one at
/// a time: the claim set and the trail are process-wide.
/// </summary>
[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class ReferenceDiskCollection
{
    public const string Name = "Reference courses on disk";
}

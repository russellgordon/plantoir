using System.Security.AccessControl;
using System.Security.Principal;

namespace Plantoir.Core.Models;

/// <summary>
/// The lock on a reference course's pages, on NTFS (#241, design A5 in the
/// bundle-6 plan; <c>documentation/09-mac-app.md</c> → "On Windows: deny
/// entries, not the read-only attribute").
///
/// <para><b>What it is.</b> On every content FILE, an explicit DENY entry for
/// this account refusing <c>WriteData, AppendData, WriteExtendedAttributes,
/// WriteAttributes, Delete</c>; on every DIRECTORY that holds a locked file,
/// a DENY of <c>DeleteSubdirectoriesAndFiles</c> for that folder only. The
/// second is what makes a DELETE refused: measured, a file's own Delete deny
/// is overridden by the parent's inherited FILE_DELETE_CHILD. Together they
/// refuse a write, a rename-over (how every editor saves), a rename and a
/// delete — by Obsidian, Explorer and <c>Remove-Item -Force</c> — and allow
/// reading, adding a new file, and replacing an UNLOCKED sibling, which is
/// what the build's preflight does to <c>course_config.json</c>.</para>
///
/// <para><b>Why not the read-only attribute</b> (rejected, measured): it
/// TRAVELS. <c>shutil.copy2</c> and <c>File.Copy</c> both carry it into the
/// build tree, the build cannot rewrite the copy's <c>draft: true</c> into
/// <c>publish: false</c>, and a page the teacher HID is published. An access
/// entry is never carried by a copy — except by <c>robocopy /SEC</c> and
/// <c>/COPYALL</c>, the honest limit, pinned by
/// <c>ReferenceLockTests.NoRobocopyInThisRepositoryCopiesSecurity</c>.</para>
///
/// <para><b>Unlock matches the SHAPE, not the account</b> (bundle-6 ruling 3):
/// our permission set is taken out of every explicit deny entry that carries
/// all of it, whoever it names (and whatever else that entry denies, which
/// stays), so a course carried from another account or computer
/// can still be unlocked and removed. The DACL is never reset: a teacher's own
/// entries survive. The owner always holds WRITE_DAC, which nothing here
/// denies, so the app cannot lock itself out.</para>
///
/// <para><b>Assert, verify, re-assert.</b> Every pass reads each entry back,
/// and an independent CENSUS — a plain listing of the course classified by the
/// never-locked rule alone — compares what should be locked with what is. A
/// pass that skipped a folder would otherwise agree with itself (the mac's
/// 842-of-934 fault). Runs off the UI thread; never on a timer.</para>
///
/// <para>The REFUSAL to deploy never depends on any of this. It is gated on
/// the marker alone (<see cref="ReferenceCourse.IsKeptForReference(Course)"/>).</para>
/// </summary>
[System.Runtime.Versioning.SupportedOSPlatform("windows")]
public static class ReferenceLock
{
    /// <summary>What a locked FILE refuses its owner.</summary>
    public const FileSystemRights FileMask =
        FileSystemRights.WriteData | FileSystemRights.AppendData | FileSystemRights.WriteExtendedAttributes
        | FileSystemRights.WriteAttributes | FileSystemRights.Delete;

    /// <summary>What a directory holding locked files refuses: deleting what is in it.</summary>
    public const FileSystemRights DirectoryMask = FileSystemRights.DeleteSubdirectoriesAndFiles;

    /// <summary>
    /// Files never locked, by name (<c>referenceCourses.frozen.neverLocked</c>),
    /// plus <c>desktop.ini</c> and <c>Thumbs.db</c> — Windows' twins of
    /// <c>.DS_Store</c>, the shell's own bookkeeping, added here and named in
    /// documentation/09 rather than in the contract. Anything ending
    /// <c>.tmp</c> is never locked either.
    /// </summary>
    public static readonly IReadOnlyList<string> NeverLockedFiles = new[]
    {
        "course_config.json", "course_config.backup.json", "course_config.json.tmp",
        ".DS_Store", "desktop.ini", "Thumbs.db",
    };

    /// <summary>Folders never descended: Obsidian's settings and the built website.</summary>
    public static readonly IReadOnlyList<string> NeverLockedFolders = new[] { ".obsidian", ".merged_output" };

    /// <summary>What one pass did.</summary>
    /// <param name="Locked">Files this pass had to lock — 0 on a course already frozen, the ordinary case.</param>
    /// <param name="DidNotTake">Files whose lock was set and did not read back, left for the next pass.</param>
    /// <param name="ShouldBeLocked">The census: regular files the never-locked rule says should be locked.</param>
    /// <param name="LockedOnDisk">The census: how many of those carry the lock afterwards.</param>
    public sealed record Outcome(int Locked, int DidNotTake, int ShouldBeLocked, int LockedOnDisk)
    {
        public bool EverythingThatShouldBeLockedIs => LockedOnDisk >= ShouldBeLocked;
        public bool IsQuiet => Locked == 0 && DidNotTake == 0 && EverythingThatShouldBeLockedIs;
        public static readonly Outcome Nothing = new(0, 0, 0, 0);
    }

    /// <summary>This account, which the lock names. Overridable by a test.</summary>
    internal static Func<SecurityIdentifier> Account { get; set; } =
        () => WindowsIdentity.GetCurrent().User!;

    // ---- Locking ----------------------------------------------------------

    /// <summary>
    /// Locks every content file of a reference course that is not locked yet.
    /// Idempotent and resumable: a course half-locked by a crash is finished
    /// by the next pass. Does nothing for a course that is not one.
    /// </summary>
    public static Outcome EnsureLocked(Course course) =>
        ReferenceCourse.IsKeptForReference(course) ? Lock(course.DirectoryPath) : Outcome.Nothing;

    /// <summary>Locks every content file under <paramref name="courseDirectory"/>, and verifies by census.</summary>
    public static Outcome Lock(string courseDirectory)
    {
        var me = Account();
        int locked = 0, didNotTake = 0;
        var foldersHoldingLocks = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string file in ContentFiles(courseDirectory))
        {
            if (!CarriesOurLock(file, me, isDirectory: false))
            {
                if (TryAdd(file, me, isDirectory: false) && CarriesOurLock(file, me, isDirectory: false)) locked++;
                else { didNotTake++; continue; }
            }
            if (Path.GetDirectoryName(file) is { } parent) foldersHoldingLocks.Add(parent);
        }
        foreach (string folder in foldersHoldingLocks)
        {
            if (CarriesOurLock(folder, me, isDirectory: true)) continue;
            // A folder whose delete-child deny did not take leaves its pages
            // deletable; the census below does not see folders, so it is
            // counted here as a page that would not stay locked.
            if (!(TryAdd(folder, me, isDirectory: true) && CarriesOurLock(folder, me, isDirectory: true))) didNotTake++;
        }
        var census = Census(courseDirectory);
        return new Outcome(locked, didNotTake, census.ShouldBeLocked, census.LockedOnDisk);
    }

    /// <summary>
    /// Removes every lock entry under <paramref name="courseDirectory"/> —
    /// every explicit DENY carrying exactly our file or folder permission set,
    /// WHOEVER it names. Called before every act that removes or writes over
    /// the course: removal, restore, the sweep of a leftover, a failed copy.
    /// Walks everything but links, the never-locked folders included, so a
    /// course locked by an older rule is still fully released.
    /// </summary>
    public static void Unlock(string path)
    {
        if (Directory.Exists(path) && !IsLink(path))
        {
            foreach (string entry in EveryEntry(path)) RemoveOurShape(entry, Directory.Exists(entry));
            RemoveOurShape(path, isDirectory: true);
        }
        else if (File.Exists(path) && !IsLink(path))
        {
            RemoveOurShape(path, isDirectory: false);
        }
    }

    /// <summary>
    /// Unlocks and clears the read-only attribute on everything under
    /// <paramref name="path"/> — what an import does to its copy before
    /// anything else, and what anything copying OUT of a reference course
    /// does to what it wrote. A stream copy carries neither today; this is the
    /// guard for the day a copy routine does (ruling 2).
    /// </summary>
    public static void Clear(string path)
    {
        Unlock(path);
        IEnumerable<string> files = Directory.Exists(path) ? EveryEntry(path).Where(File.Exists) : new[] { path };
        foreach (string file in files)
        {
            try
            {
                var attributes = File.GetAttributes(file);
                if (attributes.HasFlag(FileAttributes.ReadOnly))
                    File.SetAttributes(file, attributes & ~FileAttributes.ReadOnly);
            }
            catch { /* the next writer says what is wrong in its own words */ }
        }
    }

    /// <summary>Whether this file carries this account's lock.</summary>
    public static bool IsLocked(string file) => CarriesOurLock(file, Account(), isDirectory: false);

    // ---- The census --------------------------------------------------------

    /// <summary>
    /// An INDEPENDENT count, with none of the pass's own walking logic: every
    /// regular file in the course (links not followed), classified by the
    /// never-locked rule alone, against how many of those carry the lock.
    /// </summary>
    public static (int ShouldBeLocked, int LockedOnDisk) Census(string courseDirectory)
    {
        var me = Account();
        int should = 0, locked = 0;
        IEnumerable<string> files;
        try
        {
            files = Directory.EnumerateFiles(courseDirectory, "*", new EnumerationOptions
            {
                RecurseSubdirectories = true,
                AttributesToSkip = FileAttributes.ReparsePoint,
                IgnoreInaccessible = true,
            }).ToList();
        }
        catch { return (0, 0); }
        foreach (string file in files)
        {
            string relative = Path.GetRelativePath(courseDirectory, file);
            string[] parts = relative.Split(Path.DirectorySeparatorChar);
            if (parts[..^1].Any(part => NeverLockedFolders.Contains(part, StringComparer.Ordinal))) continue;
            if (IsNeverLockedFile(parts[^1])) continue;
            should++;
            if (CarriesOurLock(file, me, isDirectory: false)) locked++;
        }
        return (should, locked);
    }

    // ---- The walk -----------------------------------------------------------

    /// <summary>Whether a file is never locked, by its name alone.</summary>
    public static bool IsNeverLockedFile(string name) =>
        NeverLockedFiles.Contains(name, StringComparer.OrdinalIgnoreCase)
        || name.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Every content file to lock: every regular file at every depth, skipping
    /// a never-locked FILE by name (and only that file — the mac's fault was a
    /// skip that took the NEXT folder with it), never descending a never-locked
    /// FOLDER, and never following or locking a link.
    /// </summary>
    public static IEnumerable<string> ContentFiles(string courseDirectory)
    {
        var pending = new Stack<string>();
        pending.Push(courseDirectory);
        while (pending.Count > 0)
        {
            string folder = pending.Pop();
            List<FileSystemInfo> entries;
            try { entries = new DirectoryInfo(folder).EnumerateFileSystemInfos("*", Unfiltered).ToList(); }
            catch { continue; }
            foreach (var entry in entries)
            {
                if (entry.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                if (entry is DirectoryInfo)
                {
                    if (!NeverLockedFolders.Contains(entry.Name, StringComparer.Ordinal)) pending.Push(entry.FullName);
                }
                else if (!IsNeverLockedFile(entry.Name))
                {
                    yield return entry.FullName;
                }
            }
        }
    }

    /// <summary>
    /// The listing options every walk here uses: hidden and system entries
    /// INCLUDED. .NET's default skips both, which on some machines would drop
    /// <c>.obsidian</c> (the #136 trap).
    /// </summary>
    public static readonly EnumerationOptions Unfiltered = new()
    {
        AttributesToSkip = 0,
        RecurseSubdirectories = false,
        IgnoreInaccessible = false,
    };

    /// <summary>Every file and folder under <paramref name="root"/>, links neither followed nor listed.</summary>
    private static IEnumerable<string> EveryEntry(string root)
    {
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.Count > 0)
        {
            string folder = pending.Pop();
            List<FileSystemInfo> entries;
            try { entries = new DirectoryInfo(folder).EnumerateFileSystemInfos("*", Unfiltered).ToList(); }
            catch { continue; }
            foreach (var entry in entries)
            {
                if (entry.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                yield return entry.FullName;
                if (entry is DirectoryInfo) pending.Push(entry.FullName);
            }
        }
    }

    private static bool IsLink(string path)
    {
        try { return File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint); }
        catch { return false; }
    }

    // ---- The access entries ---------------------------------------------------

    private static FileSystemRights MaskFor(bool isDirectory) => isDirectory ? DirectoryMask : FileMask;

    /// <summary>A rule's rights without the Synchronize bit, which Windows may add or leave.</summary>
    private static FileSystemRights Shape(FileSystemAccessRule rule) => rule.FileSystemRights & ~FileSystemRights.Synchronize;

    private static FileSystemSecurity? Read(string path, bool isDirectory)
    {
        try
        {
            return isDirectory
                ? new DirectoryInfo(path).GetAccessControl(AccessControlSections.Access)
                : new FileInfo(path).GetAccessControl(AccessControlSections.Access);
        }
        catch { return null; }
    }

    private static void Write(string path, FileSystemSecurity security, bool isDirectory)
    {
        if (isDirectory) new DirectoryInfo(path).SetAccessControl((DirectorySecurity)security);
        else new FileInfo(path).SetAccessControl((FileSecurity)security);
    }

    /// <summary>
    /// Every explicit, non-inherited DENY entry carrying ALL of our permission
    /// set — exactly ours, or ours merged with something else. Windows MERGES
    /// two deny entries for one account into one (measured: a teacher's own
    /// ReadData deny plus ours came back as one entry of both), so matching
    /// the exact mask alone would leave such a lock behind after Remove.
    /// </summary>
    private static IEnumerable<FileSystemAccessRule> OurShapeIn(FileSystemSecurity security, bool isDirectory) =>
        security.GetAccessRules(includeExplicit: true, includeInherited: false, typeof(SecurityIdentifier))
            .Cast<FileSystemAccessRule>()
            .Where(rule => rule.AccessControlType == AccessControlType.Deny
                           && !rule.IsInherited
                           && (Shape(rule) & MaskFor(isDirectory)) == MaskFor(isDirectory)
                           && rule.InheritanceFlags == InheritanceFlags.None);

    private static bool CarriesOurLock(string path, SecurityIdentifier me, bool isDirectory) =>
        Read(path, isDirectory) is { } security
        && OurShapeIn(security, isDirectory).Any(rule => rule.IdentityReference.Equals(me));

    private static bool TryAdd(string path, SecurityIdentifier me, bool isDirectory)
    {
        try
        {
            var security = Read(path, isDirectory);
            if (security is null) return false;
            security.AddAccessRule(new FileSystemAccessRule(me, MaskFor(isDirectory),
                InheritanceFlags.None, PropagationFlags.None, AccessControlType.Deny));
            Write(path, security, isDirectory);
            return true;
        }
        catch { return false; }
    }

    private static void RemoveOurShape(string path, bool isDirectory)
    {
        try
        {
            var security = Read(path, isDirectory);
            if (security is null) return;
            var ours = OurShapeIn(security, isDirectory).ToList();
            if (ours.Count == 0) return;
            // RemoveAccessRule takes OUR bits out of the entry and keeps the
            // rest, so a teacher's own deny merged into it survives.
            foreach (var rule in ours)
                security.RemoveAccessRule(new FileSystemAccessRule(rule.IdentityReference, MaskFor(isDirectory),
                    InheritanceFlags.None, PropagationFlags.None, AccessControlType.Deny));
            Write(path, security, isDirectory);
        }
        catch { /* whatever cannot be unlocked says so when it is next written */ }
    }
}

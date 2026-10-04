using System.ComponentModel;
using System.Runtime.InteropServices;
using Plantoir.Core.Assist;

namespace Plantoir.Core.Models;

/// <summary>
/// Where a reference course is MADE before it exists (#241/#244/#245): a
/// hidden <c>courses/.plantoir-importing-&lt;FOLDER&gt;</c>, renamed into place
/// last, so nothing under <c>courses/</c> is ever a course that is not already
/// a reference course (<c>referenceCourses.importing.nothingIsVisibleUntilItIsSafe</c>).
/// Used by BOTH ways one is made — Keep a Copy and the import.
///
/// <para><b>Claiming is ONE act, and only the claimer ever removes a staging
/// folder</b> (<c>oneImportPerCourseAtATime</c>): (1) already claimed in THIS
/// app — another window — is refused; (2) take our lease, THEN look for
/// another process's live lease; (3) clear a leftover nobody live owns, and
/// one that will not go means not started; (4) make the folder EXCLUSIVELY
/// (<c>CreateDirectoryW</c>, which refuses an existing folder atomically —
/// .NET's <c>Directory.CreateDirectory</c> does not), and a folder already
/// there means somebody slipped in. Every answer but "claimed" gives our
/// lease back and removes nothing it did not put there.</para>
/// </summary>
public static class ReferenceStaging
{
    public const string Prefix = ".plantoir-importing-";

    public enum Outcome { Claimed, Refused, CouldNotStart }

    /// <summary>What a claim came to. <c>Reason</c> is the sentence for a teacher, or null when claimed.</summary>
    public sealed record Claim(Outcome Outcome, string? Reason);

    /// <summary>What making the folder answered.</summary>
    public enum CreateAnswer { Made, AlreadyThere, Failed }

    private static readonly HashSet<string> Claimed = new(StringComparer.Ordinal);
    private static readonly object Gate = new();

    public static string StagingName(string folderName) => Prefix + folderName;

    public static bool IsStagingName(string name) =>
        name.StartsWith(Prefix, StringComparison.Ordinal) && name.Length > Prefix.Length;

    public static string FolderNameFromStaging(string stagingName) => stagingName[Prefix.Length..];

    public static string ActivityDirectory(string coursesDirectory) =>
        Path.Combine(coursesDirectory, ".internal", "activity");

    public static string LeaseName(string folderName) => $"{folderName}.import.{Environment.ProcessId}.lease";

    /// <summary>
    /// The in-app key: the courses folder's REAL path (links resolved, the
    /// disk's own spelling) plus the staging name in lower case, so two
    /// windows that reached one working folder by different spellings are one
    /// claim. NTFS is case-insensitive, so the path is folded too.
    /// </summary>
    public static string ClaimKey(string coursesDirectory, string folderName) =>
        FolderContainers.PhysicalPath(coursesDirectory).TrimEnd('\\').ToUpperInvariant()
        + "\\" + StagingName(folderName).ToLowerInvariant();

    /// <summary>Claims the staging folder for <paramref name="folderName"/>. See the class summary for the order.</summary>
    /// <param name="refusalSentence">What a teacher is told when somebody else is making it.</param>
    /// <param name="removeLeftover">Clears a leftover; the default unlocks, then removes. Injected by the contract cases.</param>
    /// <param name="create">Makes the folder exclusively. Injected by the contract cases.</param>
    public static Claim TryClaim(string coursesDirectory, string folderName, string refusalSentence,
        Func<string, bool>? removeLeftover = null, Func<string, (CreateAnswer Answer, string? Reason)>? create = null)
    {
        removeLeftover ??= Remove;
        create ??= CreateExclusively;
        string key = ClaimKey(coursesDirectory, folderName);
        string staging = Path.Combine(coursesDirectory, StagingName(folderName));
        lock (Gate)
        {
            if (Claimed.Contains(key)) return new Claim(Outcome.Refused, refusalSentence);

            TakeLease(coursesDirectory, folderName);
            if (SomeoneIsWorkingOn(coursesDirectory, folderName, ignoringMyself: true))
            {
                ReleaseLease(coursesDirectory, folderName);
                return new Claim(Outcome.Refused, refusalSentence);
            }
            if (Directory.Exists(staging) || File.Exists(staging))
            {
                if (!removeLeftover(staging))
                {
                    ReleaseLease(coursesDirectory, folderName);
                    return new Claim(Outcome.CouldNotStart, ReferenceImport.LeftoverInTheWay);
                }
            }
            var (answer, reason) = create(staging);
            switch (answer)
            {
                case CreateAnswer.Made:
                    Claimed.Add(key);
                    return new Claim(Outcome.Claimed, null);
                case CreateAnswer.AlreadyThere:
                    ReleaseLease(coursesDirectory, folderName);
                    return new Claim(Outcome.Refused, refusalSentence);
                default:
                    ReleaseLease(coursesDirectory, folderName);
                    return new Claim(Outcome.CouldNotStart, reason ?? "");
            }
        }
    }

    /// <summary>Gives a claim back: forgets it in this app and removes our lease. Never touches the folder.</summary>
    public static void GiveBack(string coursesDirectory, string folderName)
    {
        lock (Gate) Claimed.Remove(ClaimKey(coursesDirectory, folderName));
        ReleaseLease(coursesDirectory, folderName);
    }

    /// <summary>Unlocks, then removes, a staging folder. True when it is gone.</summary>
    public static bool Remove(string staging)
    {
        ReferenceLock.Clear(staging);
        try
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true);
            else if (File.Exists(staging)) File.Delete(staging);
        }
        catch { }
        return !Directory.Exists(staging) && !File.Exists(staging);
    }

    /// <summary>
    /// Removes the staging folders nobody live owns — what a crash, a quit or
    /// a power cut left — and returns the folder names they were going to
    /// be. Matched on the exact prefix and nothing else: a teacher's own
    /// dot-folder is never ours to take. Unlocks first, because the lock is
    /// applied before the rename and a locked tree refuses to be removed.
    /// </summary>
    public static List<string> SweepLeftovers(string coursesDirectory)
    {
        var swept = new List<string>();
        List<DirectoryInfo> children;
        try { children = new DirectoryInfo(coursesDirectory).EnumerateDirectories("*", ReferenceLock.Unfiltered).ToList(); }
        catch { return swept; }
        foreach (var child in children.Where(c => IsStagingName(c.Name)))
        {
            string folderName = FolderNameFromStaging(child.Name);
            bool mine;
            lock (Gate) mine = Claimed.Contains(ClaimKey(coursesDirectory, folderName));
            if (mine) continue;
            if (SomeoneIsWorkingOn(coursesDirectory, folderName, ignoringMyself: false)) continue;
            if (Remove(child.FullName)) swept.Add(folderName);
        }
        return swept;
    }

    /// <summary>The one line the sweep writes (<c>unfinished import for reference tidied away</c>).</summary>
    public static string SweptTrailLine(IReadOnlyList<string> folderNames) =>
        $"tidied away {(folderNames.Count == 1 ? "an unfinished import" : "unfinished imports")} left behind by an earlier run — {string.Join(", ", folderNames)}";

    // ---- The lease ------------------------------------------------------------

    private static void TakeLease(string coursesDirectory, string folderName)
    {
        try
        {
            string folder = ActivityDirectory(coursesDirectory);
            Directory.CreateDirectory(folder);
            string path = Path.Combine(folder, LeaseName(folderName));
            string temporary = path + ".tmp";
            File.WriteAllText(temporary, WorkLease.LeaseBody(withStart: true));
            File.Move(temporary, path, overwrite: true);   // a reader never meets half a lease
        }
        catch { /* an unwritable folder: the in-app set and the exclusive create still hold */ }
    }

    private static void ReleaseLease(string coursesDirectory, string folderName)
    {
        try { File.Delete(Path.Combine(ActivityDirectory(coursesDirectory), LeaseName(folderName))); } catch { }
    }

    /// <summary>
    /// Whether another LIVE process holds an import lease on this folder name.
    /// A lease whose owner is gone is removed on the way past.
    /// </summary>
    public static bool SomeoneIsWorkingOn(string coursesDirectory, string folderName, bool ignoringMyself)
    {
        IEnumerable<string> leases;
        try { leases = Directory.EnumerateFiles(ActivityDirectory(coursesDirectory), "*.lease").ToList(); }
        catch { return false; }
        string prefix = folderName + ".import.";
        bool someoneIsAlive = false;
        foreach (string lease in leases)
        {
            string name = Path.GetFileName(lease);
            if (!name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) continue;
            if (!int.TryParse(name[prefix.Length..^".lease".Length], out int pid)) continue;
            if (ignoringMyself && pid == Environment.ProcessId) continue;
            string text;
            try { text = File.ReadAllText(lease); } catch { someoneIsAlive = true; continue; }   // cannot tell: alive
            var (recordedName, recordedStart) = WorkLease.ReadBody(text);
            if (WorkLease.OwnerIsAlive(pid, recordedName, recordedStart, WorkLease.Importing)) { someoneIsAlive = true; continue; }
            try { File.Delete(lease); } catch { }
        }
        return someoneIsAlive;
    }

    // ---- Making the folder exclusively ------------------------------------------

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "CreateDirectoryW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateDirectoryNative(string path, IntPtr securityAttributes);

    private const int ErrorAlreadyExists = 183;

    /// <summary>Makes the folder, refusing one that is already there — atomically, in one system call.</summary>
    public static (CreateAnswer Answer, string? Reason) CreateExclusively(string staging)
    {
        if (CreateDirectoryNative(staging, IntPtr.Zero)) return (CreateAnswer.Made, null);
        int error = Marshal.GetLastWin32Error();
        if (error == ErrorAlreadyExists) return (CreateAnswer.AlreadyThere, null);
        return (CreateAnswer.Failed, new Win32Exception(error).Message);
    }

    /// <summary>For tests: forget every in-app claim.</summary>
    internal static void ForgetEveryClaimForTesting()
    {
        lock (Gate) Claimed.Clear();
    }

    /// <summary>For tests: claim a key in this app without making anything, as another window would.</summary>
    internal static void ClaimInThisAppForTesting(string coursesDirectory, string folderName)
    {
        lock (Gate) Claimed.Add(ClaimKey(coursesDirectory, folderName));
    }
}

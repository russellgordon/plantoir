using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Plantoir.Core.Undo;

/// <summary>Why the list could not be written (#899 W2a). The mac's <c>UndoJournalError</c>, case for case where both have one.</summary>
internal enum UndoJournalFailure
{
    /// <summary>The lock was not granted within the wait (<c>rule.oneLock</c>).</summary>
    LockBusy,

    /// <summary><c>undo\.lock</c> could not be opened or made.</summary>
    CouldNotOpenTheLock,

    /// <summary>A blob could not be stored (room, permission): nothing of it is left behind.</summary>
    CouldNotStoreContent,

    /// <summary>A new segment could not be made.</summary>
    CouldNotStartASegment,

    /// <summary>A line could not be written or made durable.</summary>
    CouldNotWrite,

    /// <summary>
    /// The reading taken inside the lock was not fresh (a segment held without
    /// sharing past the retry, a folder that could not be listed): the hold is
    /// refused, so nothing is written or deleted from a stale fold (the W1
    /// review's M2).
    /// </summary>
    ListNotReadable,
}

/// <summary>The list could not be written; <see cref="Failure"/> says why.</summary>
internal sealed class UndoJournalException(UndoJournalFailure failure, string message, Exception? inner = null)
    : IOException(message, inner)
{
    internal UndoJournalFailure Failure { get; } = failure;
}

/// <summary>
/// What the contract says a PROCESS remembers about the list, rather than a
/// journal object (#899 W2a): whether a shadow wait has run out since the
/// lock was last taken (<c>rule.oneLock</c>: "once a shadow wait has run out a
/// process tries again only once, without waiting, until it next gets the
/// lock"), and the closing events it could not write for a busy lock, written
/// first at its next hold (the mac's <c>keepPendingClosing</c>).
///
/// <para><b>An object, never a static</b> (the plan review's H1). The app's
/// start-up makes one for the process and hands it to every journal it makes
/// (W4); a test makes its own, so two test classes can never see each other's
/// memory. Keyed by the journal's folder, as the mac keys its statics.</para>
/// </summary>
internal sealed class UndoProcessMemory
{
    private readonly object _guard = new();
    private readonly HashSet<string> _shadowGaveUp = new(StringComparer.Ordinal);
    private readonly Dictionary<string, List<System.Text.Json.Nodes.JsonObject>> _pendingClosings = new(StringComparer.Ordinal);

    /// <summary>The key a folder is remembered by: its full path, in upper case (Windows paths are not case sensitive).</summary>
    internal static string KeyOf(string folder) =>
        Path.TrimEndingDirectorySeparator(Path.GetFullPath(folder)).ToUpperInvariant();

    internal bool ShadowHasGivenUp(string folder)
    {
        lock (_guard) return _shadowGaveUp.Contains(KeyOf(folder));
    }

    internal void NoteShadowGaveUp(string folder)
    {
        lock (_guard) _shadowGaveUp.Add(KeyOf(folder));
    }

    internal void NoteTaken(string folder)
    {
        lock (_guard) _shadowGaveUp.Remove(KeyOf(folder));
    }

    internal void KeepPendingClosing(string folder, System.Text.Json.Nodes.JsonObject line)
    {
        lock (_guard)
        {
            string key = KeyOf(folder);
            if (!_pendingClosings.TryGetValue(key, out var kept)) _pendingClosings[key] = kept = [];
            kept.Add(line);
        }
    }

    internal IReadOnlyList<System.Text.Json.Nodes.JsonObject> TakePendingClosings(string folder)
    {
        lock (_guard)
        {
            string key = KeyOf(folder);
            if (!_pendingClosings.Remove(key, out var kept)) return [];
            return kept;
        }
    }

    internal int PendingClosingsFor(string folder)
    {
        lock (_guard) return _pendingClosings.TryGetValue(KeyOf(folder), out var kept) ? kept.Count : 0;
    }

    // ---- Recovery's memory (#899 W3) -------------------------------------------

    private readonly Dictionary<string, (int Refusals, DateTimeOffset NextTry)> _refusedSwaps = new(StringComparer.Ordinal);
    private readonly HashSet<string> _tidied = new(StringComparer.Ordinal);
    private readonly HashSet<string> _abandoned = new(StringComparer.Ordinal);

    /// <summary>The first wait after a refused put-back (<c>rule.recovery</c>: "one minute after a refusal").</summary>
    internal static readonly TimeSpan FirstRetry = TimeSpan.FromMinutes(1);

    /// <summary>The longest wait between tries (<c>rule.recovery</c>: "never more than an hour apart").</summary>
    internal static readonly TimeSpan LongestWait = TimeSpan.FromHours(1);

    /// <summary>Whether recovery may try this step's put-back now on the ordinary path: yes at the process's first lock, then by the schedule.</summary>
    internal bool RefusedSwapIsDue(string key, DateTimeOffset now)
    {
        lock (_guard) return !_refusedSwaps.TryGetValue(key, out var entry) || now >= entry.NextTry;
    }

    /// <summary>One more refusal: the next try one minute later, doubling with each refusal in a row, never more than an hour.</summary>
    internal void NoteARefusedSwap(string key, DateTimeOffset now)
    {
        lock (_guard)
        {
            int refusals = (_refusedSwaps.TryGetValue(key, out var entry) ? entry.Refusals : 0) + 1;
            TimeSpan wait = FirstRetry;
            for (int doubled = 1; doubled < refusals && wait < LongestWait; doubled++) wait += wait;
            if (wait > LongestWait) wait = LongestWait;
            _refusedSwaps[key] = (refusals, now + wait);
        }
    }

    internal void ForgetTheRefusedSwap(string key)
    {
        lock (_guard) _refusedSwaps.Remove(key);
    }

    /// <summary>Whether this process has already removed the staged files of a step closed <c>interrupted</c> (once per process).</summary>
    internal bool HasTidied(string key)
    {
        lock (_guard) return _tidied.Contains(key);
    }

    internal void NoteTidied(string key)
    {
        lock (_guard) _tidied.Add(key);
    }

    /// <summary>
    /// A step THIS process left in flight and gave up on (a reversal that did
    /// not go in, a closing that could not be written or kept): recovery may
    /// settle it although this process is alive, because nothing of this
    /// process is still working on it. Another process never does while this
    /// one lives, since only this process knows.
    /// </summary>
    internal void NoteAbandoned(string key)
    {
        lock (_guard) _abandoned.Add(key);
    }

    internal bool IsAbandoned(string key)
    {
        lock (_guard) return _abandoned.Contains(key);
    }

    internal void ForgetAbandoned(string key)
    {
        lock (_guard) _abandoned.Remove(key);
    }
}

/// <summary>
/// The list's one exclusive lock (<c>undo.rule.oneLock</c>, #899 W2a):
/// <c>LockFileEx(LOCKFILE_EXCLUSIVE_LOCK)</c> on byte 0 of <c>undo\.lock</c>,
/// WITHOUT <c>LOCKFILE_FAIL_IMMEDIATELY</c>, so a waiter is queued by the
/// system and woken by the grant itself, never by a timer.
///
/// <para><b>The handle.</b> Opened by <c>CreateFileW</c> directly, with
/// <c>FILE_FLAG_OVERLAPPED</c>, read/write/delete sharing and no inheritance.
/// It is never wrapped in a <see cref="FileStream"/>, so .NET never binds it to
/// the thread pool's completion port (the earlier run's P2: an overlapped
/// lock request completing through that port crashed the process). The
/// OVERLAPPED lives in unmanaged memory, with its own manual-reset event, from
/// the request until the handle is closed: the system writes into it when the
/// lock is granted, which can be after a managed object would have moved.</para>
///
/// <para><b>A wait that runs out</b> cancels the request (<c>CancelIoEx</c>) and
/// then waits for the request's own answer (<c>GetOverlappedResult</c>,
/// waiting). The grant can race the cancel and win; then the lock is held, so it
/// is let go at once and the take still refuses. A lock is never left held by
/// a take that said busy.</para>
///
/// <para><b>Whose lock.</b> A byte-range lock belongs to the HANDLE, not the
/// thread (the earlier run's P4), so two journals in one process exclude each
/// other, a hold may span an <c>await</c> and be let go on another thread, and
/// the system lets it go when the holder's process dies.</para>
///
/// <para><i>Rejected:</i> a named mutex (owned by a THREAD, so a hold across an
/// <c>await</c> is let go from the wrong one; <c>Local\</c> names are per
/// session); an exclusive open retried on a timer (a poll, and polling on the
/// mac gave up 663 of 1,600 begins with 8 processes at once);
/// <see cref="FileStream.Lock"/> (it fails at once and has no form that
/// waits).</para>
/// </summary>
internal sealed class UndoLock : IDisposable
{
    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint ShareAll = 0x1 | 0x2 | 0x4;
    private const uint OpenAlways = 4;
    private const uint FileAttributeNormal = 0x80;
    private const uint FileFlagOverlapped = 0x40000000;
    private const uint LockfileExclusiveLock = 0x2;
    private const uint LockfileFailImmediately = 0x1;
    private const int ErrorIoPending = 997;
    private const int ErrorLockViolation = 33;

    /// <summary>The OVERLAPPED's size and where its event handle sits (x64: 32 and 24).</summary>
    private static readonly int OverlappedSize = (2 * IntPtr.Size) + 8 + IntPtr.Size;
    private static readonly int EventOffset = (2 * IntPtr.Size) + 8;

    private SafeFileHandle? _handle;
    private IntPtr _overlapped;
    private ManualResetEvent? _event;

    private UndoLock(SafeFileHandle handle, IntPtr overlapped, ManualResetEvent signal)
    {
        _handle = handle;
        _overlapped = overlapped;
        _event = signal;
    }

    /// <summary>
    /// Takes the lock on <paramref name="lockPath"/>, waiting at most
    /// <paramref name="wait"/>. In shadow, once a shadow wait has run out in
    /// this process (<paramref name="memory"/>), a take only tries once without
    /// waiting, until the lock is next taken. Throws
    /// <see cref="UndoJournalException"/> with <see cref="UndoJournalFailure.LockBusy"/>
    /// when it is not granted.
    /// </summary>
    /// <param name="whenQueued">Called once the request is queued by the system and waiting (a test's signal
    /// that the waiter has asked, W2a's review LOW 3); never called for a grant at once or a refusal.</param>
    internal static UndoLock Take(string lockPath, TimeSpan wait, bool inShadow, UndoProcessMemory memory,
                                  Action? whenQueued = null)
    {
        string folder = Path.GetDirectoryName(Path.GetFullPath(lockPath))!;
        bool tryOnceOnly = inShadow && memory.ShadowHasGivenUp(folder);
        SafeFileHandle handle = CreateFileW(LongPath(lockPath), GenericRead | GenericWrite, ShareAll, IntPtr.Zero,
                                            OpenAlways, FileAttributeNormal | FileFlagOverlapped, IntPtr.Zero);
        if (handle.IsInvalid)
        {
            int error = Marshal.GetLastWin32Error();
            handle.Dispose();
            throw new UndoJournalException(UndoJournalFailure.CouldNotOpenTheLock,
                "The list's lock could not be opened.", new Win32Exception(error));
        }
        IntPtr overlapped = Marshal.AllocHGlobal(OverlappedSize);
        var signal = new ManualResetEvent(false);
        try
        {
            Marshal.Copy(new byte[OverlappedSize], 0, overlapped, OverlappedSize);
            Marshal.WriteIntPtr(overlapped, EventOffset, signal.SafeWaitHandle.DangerousGetHandle());
            uint flags = LockfileExclusiveLock | (tryOnceOnly ? LockfileFailImmediately : 0);
            bool granted = LockFileEx(handle, flags, 0, 1, 0, overlapped);
            if (!granted)
            {
                int error = Marshal.GetLastWin32Error();
                if (error == ErrorLockViolation)
                {
                    // Only a try-once asks to fail at once.
                    throw new UndoJournalException(UndoJournalFailure.LockBusy, "The list is busy.");
                }
                if (error != ErrorIoPending)
                    throw new UndoJournalException(UndoJournalFailure.CouldNotOpenTheLock,
                        "The list's lock could not be requested.", new Win32Exception(error));
                whenQueued?.Invoke();
                granted = AwaitTheGrant(handle, overlapped, signal, wait);
                if (!granted)
                {
                    if (inShadow) memory.NoteShadowGaveUp(folder);
                    throw new UndoJournalException(UndoJournalFailure.LockBusy, "The list is busy.");
                }
            }
            memory.NoteTaken(folder);
            return new UndoLock(handle, overlapped, signal);
        }
        catch
        {
            handle.Dispose();
            Marshal.FreeHGlobal(overlapped);
            signal.Dispose();
            throw;
        }
    }

    /// <summary>Waits for a queued request; on timeout cancels it and lets go of a grant that raced the cancel.</summary>
    private static bool AwaitTheGrant(SafeFileHandle handle, IntPtr overlapped, ManualResetEvent signal, TimeSpan wait)
    {
        if (wait > TimeSpan.Zero && signal.WaitOne(wait))
            return GetOverlappedResult(handle, overlapped, out _, true);
        CancelIoEx(handle, overlapped);
        // Waiting here is bounded: the request is cancelled, so its answer
        // (ERROR_OPERATION_ABORTED, or the grant that beat the cancel) is due.
        if (GetOverlappedResult(handle, overlapped, out _, true))
        {
            // The grant won the race with the cancel: never leave it held.
            Unlock(handle, overlapped, signal);
        }
        return false;
    }

    private static void Unlock(SafeFileHandle handle, IntPtr overlapped, ManualResetEvent signal)
    {
        signal.Reset();
        if (!UnlockFileEx(handle, 0, 1, 0, overlapped) && Marshal.GetLastWin32Error() == ErrorIoPending)
            GetOverlappedResult(handle, overlapped, out _, true);
    }

    /// <summary>Lets the lock go and closes the handle; safe to call twice, from any thread.</summary>
    public void Dispose()
    {
        SafeFileHandle? handle = Interlocked.Exchange(ref _handle, null);
        if (handle is null) return;
        try { Unlock(handle, _overlapped, _event!); }
        finally
        {
            handle.Dispose();   // closing the handle lets any lock on it go too
            Marshal.FreeHGlobal(_overlapped);
            _overlapped = IntPtr.Zero;
            _event!.Dispose();
            _event = null;
        }
    }

    /// <summary>A path the system accepts past 259 characters: the <c>\\?\</c> form of the full path.</summary>
    internal static string LongPath(string path)
    {
        string full = Path.GetFullPath(path);
        if (full.Length < 260 || full.StartsWith(@"\\?\", StringComparison.Ordinal)) return full;
        return full.StartsWith(@"\\", StringComparison.Ordinal) ? @"\\?\UNC\" + full[2..] : @"\\?\" + full;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security,
                                                     uint creation, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool LockFileEx(SafeFileHandle file, uint flags, uint reserved, uint lengthLow, uint lengthHigh, IntPtr overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool UnlockFileEx(SafeFileHandle file, uint reserved, uint lengthLow, uint lengthHigh, IntPtr overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CancelIoEx(SafeFileHandle file, IntPtr overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetOverlappedResult(SafeFileHandle file, IntPtr overlapped, out uint transferred, bool wait);
}

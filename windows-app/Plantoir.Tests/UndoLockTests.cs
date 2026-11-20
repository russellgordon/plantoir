using System.Diagnostics;
using System.Globalization;
using System.Text.RegularExpressions;
using Plantoir.Core.Undo;

namespace Plantoir.Tests;

/// <summary>
/// <c>undo.rule.oneLock</c> on Windows (#899 W2a): <c>LockFileEx</c> on
/// <c>undo\.lock</c>, queued by the system, bounded, never left held. The two
/// numbers the rule carries (2 seconds live, 50 milliseconds in shadow) are
/// read from the contract's sentence, never retyped. Timing is asserted only
/// from below (a refused wait lasted at least the wait), never with a tight
/// upper bound, so a busy PC cannot turn these red.
/// </summary>
public sealed class UndoLockTests : IDisposable
{
    private readonly string _folder = RunOwnedTempFolders.Create("plantoir-undo-lock-");

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); } catch { }
    }

    private string LockPath => Path.Combine(_folder, ".lock");

    private static string OneLock => UndoContract.Undo.GetProperty("rule").GetProperty("oneLock").GetString()!;

    private UndoJournal Journal(UndoProcessMemory? memory = null) =>
        new(_folder, TimeProvider.System, _ => true, _ => true, isLive: false, readRetry: TimeSpan.Zero, memory: memory);

    private static UndoJournalFailure FailureOf(Action action) =>
        Assert.IsType<UndoJournalException>(Record.Exception(action)).Failure;

    [Fact]
    public void TheWaitsAreTheContractsNumbers()
    {
        Match live = Regex.Match(OneLock, @"\((\d+) seconds live; (\d+) milliseconds in shadow");
        Assert.True(live.Success, "the rule no longer says its two waits in the words this test reads");
        Assert.Equal(TimeSpan.FromSeconds(int.Parse(live.Groups[1].Value, CultureInfo.InvariantCulture)), UndoJournal.LiveWait);
        Assert.Equal(TimeSpan.FromMilliseconds(int.Parse(live.Groups[2].Value, CultureInfo.InvariantCulture)), UndoJournal.ShadowWait);
        Assert.Contains("LockFileEx on undo\\.lock without LOCKFILE_FAIL_IMMEDIATELY", OneLock);
    }

    /// <summary>Two journals in ONE process exclude each other: the lock is the handle's, not the process's.</summary>
    [Fact]
    public void TwoJournalsInOneProcessExcludeEachOther()
    {
        UndoJournal first = Journal();
        UndoJournal second = Journal();
        first.WithLock(_ =>
        {
            Assert.Equal(UndoJournalFailure.LockBusy,
                FailureOf(() => second.WithLock(_ => { }, wait: TimeSpan.FromMilliseconds(100))));
        });
        second.WithLock(_ => { });   // free again once the first lets go
    }

    [Fact]
    public void AWaitThatRunsOutRefusesAfterTheWaitAndLeavesNothingHeld()
    {
        var memory = new UndoProcessMemory();
        using (UndoLock.Take(LockPath, UndoJournal.LiveWait, inShadow: false, memory))
        {
            TimeSpan wait = TimeSpan.FromMilliseconds(300);
            var clock = Stopwatch.StartNew();
            Assert.Equal(UndoJournalFailure.LockBusy, FailureOf(() => UndoLock.Take(LockPath, wait, false, memory)));
            Assert.True(clock.Elapsed >= wait - TimeSpan.FromMilliseconds(20), $"refused after {clock.ElapsedMilliseconds} ms");
            Assert.True(clock.Elapsed < wait * 10 + TimeSpan.FromSeconds(5), $"refused after {clock.ElapsedMilliseconds} ms");
        }
        // The refused take holds nothing: a third take is granted at once.
        var third = Stopwatch.StartNew();
        using (UndoLock.Take(LockPath, UndoJournal.LiveWait, false, memory))
            Assert.True(third.Elapsed < UndoJournal.LiveWait, "the refused take left the lock held");
    }

    /// <summary>
    /// A waiter is QUEUED and woken by the release, not refused at once
    /// (<c>LOCKFILE_FAIL_IMMEDIATELY</c> would refuse it: the must-fail proof).
    /// </summary>
    [Fact]
    public async Task AWaiterIsWokenByTheRelease()
    {
        var memory = new UndoProcessMemory();
        UndoLock held = UndoLock.Take(LockPath, UndoJournal.LiveWait, false, memory);
        Task<bool> waiter = Task.Run(() =>
        {
            using UndoLock granted = UndoLock.Take(LockPath, TimeSpan.FromSeconds(20), false, memory);
            return true;
        });
        Task first = await Task.WhenAny(waiter, Task.Delay(TimeSpan.FromMilliseconds(300)));
        Assert.False(first == waiter, "the waiter was answered while the lock was held: " + waiter.Exception?.InnerException?.Message);
        held.Dispose();
        Task second = await Task.WhenAny(waiter, Task.Delay(TimeSpan.FromSeconds(20)));
        Assert.True(second == waiter && await waiter, "the waiter was not woken by the release");
    }

    /// <summary>The lock belongs to the handle, not the thread: let go on another thread, it is free.</summary>
    [Fact]
    public async Task ALockTakenOnOneThreadIsLetGoOnAnother()
    {
        var memory = new UndoProcessMemory();
        UndoLock held = UndoLock.Take(LockPath, UndoJournal.LiveWait, false, memory);
        await Task.Run(held.Dispose);
        using UndoLock again = UndoLock.Take(LockPath, TimeSpan.FromMilliseconds(500), false, memory);
        held.Dispose();   // twice is harmless
    }

    /// <summary>
    /// <c>rule.oneLock</c>: "once a shadow wait has run out a process tries
    /// again only once, without waiting, until it next gets the lock". Asserted
    /// by outcome and from below only, never the 50 ms itself.
    /// </summary>
    [Fact]
    public void OnceAShadowWaitRunsOutShadowTakesTryOnceUntilTheLockIsNextTaken()
    {
        var memory = new UndoProcessMemory();
        var holder = new UndoProcessMemory();   // another process's memory, holding on a second handle
        UndoLock held = UndoLock.Take(LockPath, UndoJournal.LiveWait, false, holder);

        Assert.Equal(UndoJournalFailure.LockBusy, FailureOf(() => UndoLock.Take(LockPath, UndoJournal.ShadowWait, true, memory)));
        Assert.True(memory.ShadowHasGivenUp(_folder));

        // Tries once: refused without waiting the long wait it was given.
        var clock = Stopwatch.StartNew();
        Assert.Equal(UndoJournalFailure.LockBusy, FailureOf(() => UndoLock.Take(LockPath, TimeSpan.FromSeconds(30), true, memory)));
        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(15), $"a try-once waited {clock.ElapsedMilliseconds} ms");

        // A live take still waits its full wait.
        TimeSpan liveWait = TimeSpan.FromMilliseconds(300);
        clock.Restart();
        Assert.Equal(UndoJournalFailure.LockBusy, FailureOf(() => UndoLock.Take(LockPath, liveWait, false, memory)));
        Assert.True(clock.Elapsed >= liveWait - TimeSpan.FromMilliseconds(20));

        held.Dispose();
        using (UndoLock.Take(LockPath, TimeSpan.FromSeconds(30), true, memory)) { }   // the try-once is granted when free
        Assert.False(memory.ShadowHasGivenUp(_folder));
        Assert.False(holder.ShadowHasGivenUp(_folder));
    }

    /// <summary>A lock file past 259 characters is opened (the <c>\\?\</c> form).</summary>
    [Fact]
    public void ALockFilePastTheOldPathLimitIsTaken()
    {
        string deep = _folder;
        while (deep.Length < 270) deep = Path.Combine(deep, "a-folder-name-that-is-long");
        Directory.CreateDirectory(deep);
        string lockPath = Path.Combine(deep, ".lock");
        Assert.True(Path.GetFullPath(lockPath).Length >= 260);
        var memory = new UndoProcessMemory();
        using (UndoLock.Take(lockPath, UndoJournal.LiveWait, false, memory))
            Assert.Equal(UndoJournalFailure.LockBusy, FailureOf(() => UndoLock.Take(lockPath, TimeSpan.FromMilliseconds(50), false, memory)));
        Assert.True(File.Exists(UndoLock.LongPath(lockPath)));
    }

    /// <summary>The lock file is made by whoever takes it first and never deleted (<c>undoJournal.files</c> → <c>.lock</c>).</summary>
    [Fact]
    public void TheLockFileIsMadeOnceAndKept()
    {
        Assert.Contains("never deleted", UndoContract.Journal.GetProperty("files").GetProperty(".lock").GetString());
        UndoJournal journal = Journal();
        journal.WithLock(_ => { });
        Assert.True(File.Exists(LockPath));
        Assert.Equal(0, new FileInfo(LockPath).Length);
        journal.WithLock(writer => journal.Prune(writer));
        Assert.True(File.Exists(LockPath));
    }
}

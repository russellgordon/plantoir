namespace Plantoir.Core.Undo;

/// <summary>
/// The list as one PROCESS of the app holds it (#899 W4): the composition
/// root the plan review's H1 asked for, and the only code that reads the
/// switch (<see cref="UndoSwitch"/>) and the state folder
/// (<see cref="UndoJournalLocation"/>) for Undo. Both <c>Plantoir.exe</c>
/// and every <c>plantoir-mcp.exe</c> make theirs the same way, from the same
/// two places, AFTER <c>--state-dir</c> has been applied, so the window, the
/// window's own assistant server (handed <c>--state-dir</c> by
/// <c>McpClient</c>, #641) and an outside door's server (handed none) all find
/// one list: <c>%LOCALAPPDATA%\Plantoir\undo</c>, or <c>undo\</c> under the
/// redirected state folder.
///
/// <para><b>One per process</b>, holding the process's one
/// <see cref="UndoProcessMemory"/> (shadow try-once, closings kept for a busy
/// lock, recovery's schedule and the steps this process abandoned) and one
/// <see cref="UndoJournal"/>, which reads on from where it stopped. A door is
/// made for each action over that journal. A test makes its own instance with
/// its own folder, mode and trail and never touches <see cref="Current"/>.</para>
///
/// <para><b>Shadow, as the contract defines it</b> (<c>rule.shadow</c>): with
/// the switch off, a failure of the list never stops or changes what a teacher
/// asked for. The door goes ahead without a record when the begin cannot be
/// written; recovery records and never repairs; and nothing here throws to its
/// caller.</para>
/// </summary>
internal sealed class UndoForThisProcess
{
    private static readonly Lazy<UndoForThisProcess> TheProcess = new(
        () => new UndoForThisProcess(UndoJournalLocation.Folder, UndoSwitch.CurrentMode, UndoTrail.ToTheActivityTrail),
        LazyThreadSafetyMode.ExecutionAndPublication);

    /// <param name="folder">The list's folder (<c>undo\</c>).</param>
    /// <param name="mode">Live or shadow: the switch in the app, the test's own choice in a test.</param>
    /// <param name="trail">Where Undo's trail lines go: the real activity trail in the app.</param>
    /// <param name="clock">The clock the limits are judged by; the system's in the app.</param>
    /// <param name="maintainers">Who re-derives the files a rule keeps true: the app's own (<see cref="UndoSectionFrontPage"/>) unless a test passes its own.</param>
    internal UndoForThisProcess(string folder, UndoMode mode, Action<UndoTrailLine>? trail, TimeProvider? clock = null,
                                IUndoMaintainers? maintainers = null)
    {
        Folder = folder;
        Maintainers = maintainers ?? new UndoSectionFrontPage();
        Mode = mode;
        Trail = trail;
        TimeProvider theClock = clock ?? TimeProvider.System;
        Memory = new UndoProcessMemory();
        Journal = new UndoJournal(folder, theClock, UndoJournalChecks.ProcessIsAlive,
                                  step => UndoJournalChecks.FolderIsReachable(step, theClock),
                                  isLive: mode == UndoMode.Live, memory: Memory);
    }

    /// <summary>
    /// This process's list, made the first time it is asked for. Ask only after
    /// <c>--state-dir</c> has been applied (both <c>Program</c>s apply it first
    /// thing), since the folder is fixed when it is made.
    /// </summary>
    internal static UndoForThisProcess Current => TheProcess.Value;

    internal string Folder { get; }
    internal UndoMode Mode { get; }
    internal Action<UndoTrailLine>? Trail { get; }
    internal UndoProcessMemory Memory { get; }
    internal UndoJournal Journal { get; }

    /// <summary>The runners every door of this process is given (W4's review, LOW 5: never none, or a draft holding a recompute would be refused even in shadow).</summary>
    internal IUndoMaintainers Maintainers { get; }

    /// <summary>A door for one action, over this process's journal, in this process's mode, with its maintainers, writing Undo's trail lines to its trail.</summary>
    internal UndoDoor Door() =>
        new(Journal, Mode, Maintainers, trail: Trail);

    /// <summary>
    /// Recovery at launch (W3's <see cref="UndoDoor.Recover"/>): every step a
    /// gone process left in flight is settled by content, under the lock. In
    /// shadow it records what it found and writes into no working folder.
    /// Never throws: a list that cannot be had now (busy behind another
    /// process's put-back, unreadable, its folder not makeable) leaves every
    /// step where it is, for the next hold of any process to settle; the
    /// diagnostic says so. Returns the run, or null when it did not run.
    /// </summary>
    internal UndoRecoveryRun? RecoverAtLaunch(Action<string>? diagnostic = null)
    {
        try
        {
            UndoRecoveryRun run = Door().Recover();
            if (run.NotRun is { } why) diagnostic?.Invoke($"undo recovery at launch did not run: {why}");
            if (run.Settled.Count > 0) diagnostic?.Invoke($"undo recovery at launch settled {run.Settled.Count} step(s) in {Folder}");
            return run;
        }
        catch (Exception error)
        {
            // Any failure at all, the unforeseen included: a launch is never
            // stopped or changed by the list (rule.shadow).
            diagnostic?.Invoke($"undo recovery at launch did not run: {error.GetType().Name}: {error.Message}");
            return null;
        }
    }

    /// <summary>
    /// <see cref="RecoverAtLaunch"/> for this process, on a thread of its own:
    /// the window never waits on the list's lock on its UI thread, and
    /// <c>plantoir-mcp.exe</c> answers its client while it runs. Never in a
    /// deploy set for later (its run leaves <c>Program.Main</c> before the
    /// window's start-up, and it never opens the list).
    /// </summary>
    internal static Task RecoverThisProcessAtLaunch(Action<string>? diagnostic = null) =>
        Task.Run(() =>
        {
            try { Current.RecoverAtLaunch(diagnostic); }
            catch (Exception error) { diagnostic?.Invoke($"undo recovery at launch did not run: {error.GetType().Name}: {error.Message}"); }
        });
}

/// <summary>
/// What the app's two programs call at launch (#899 W4): <c>Plantoir.exe</c>
/// from <c>App.OnLaunched</c>, <c>plantoir-mcp.exe</c> from its
/// <c>Program</c>, each once, after <c>--state-dir</c> is applied. Public only
/// so those two assemblies can reach it; everything behind it stays internal.
/// </summary>
public static class UndoAtLaunch
{
    /// <summary>Recovery at launch for this process, on a thread of its own; never throws, never waited for by a UI thread.</summary>
    public static Task Recover(Action<string>? diagnostic = null) => UndoForThisProcess.RecoverThisProcessAtLaunch(diagnostic);
}

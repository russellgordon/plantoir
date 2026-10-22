using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace Plantoir.Views;

/// <summary>
/// Which Obsidian is running for THIS teacher, and asking it to quit (#581).
/// </summary>
/// <remarks>
/// <para><b>Running means: an <c>Obsidian.exe</c> in this Windows session owns a
/// top-level window, shown or not.</b> <c>Process.GetProcessesByName</c>
/// alone also returns Electron's crash reporter, GPU and utility children —
/// which can outlive the windows by a moment — and another account's
/// Obsidian on the same PC, and either would read as "Obsidian did not
/// close" (#581 plan review, H1). Counting top-level windows of ANY visibility
/// is not the same as counting windows on screen, which the add-ons' "open"
/// rule never does: a minimised Obsidian still owns its windows.</para>
/// <para><b>Quitting closes every window, not one.</b> The mac calls
/// <c>terminate()</c>; Windows has no such request, and the old
/// <c>CloseMainWindow</c> on each process closed ONE window (the process's
/// "main" one), so an Obsidian with two vaults open stayed running. Main
/// windows are closed first (no owner), pop-outs after; if any window is
/// still there once the shown ones have had their chance, each remaining
/// process gets <c>CloseMainWindow</c>, then the wait. The vaults to reopen
/// are noted BEFORE any of this (closing a vault window can unmark it in
/// Obsidian's registry).</para>
/// </remarks>
public static class ObsidianProcesses
{
    private const string ProcessName = "Obsidian";

    /// <summary>The Obsidian processes in this Windows session.</summary>
    public static List<Process> InThisSession()
    {
        int session = Process.GetCurrentProcess().SessionId;
        var found = new List<Process>();
        foreach (var process in Process.GetProcessesByName(ProcessName))
        {
            try { if (process.SessionId == session) found.Add(process); }
            catch { }
        }
        return found;
    }

    /// <summary>Whether any Obsidian.exe of this session is still alive, window or not.</summary>
    public static bool AnyProcessLeft()
    {
        var processes = InThisSession();
        foreach (var process in processes) process.Dispose();
        return processes.Count > 0;
    }

    /// <summary>Top-level windows owned by Obsidian in this session: the handle, whether it is shown, and whether another window owns it.</summary>
    public static List<(IntPtr Handle, bool Visible, bool Owned)> Windows()
    {
        var processes = InThisSession();
        var ids = new HashSet<uint>(processes.Select(p => (uint)p.Id));
        foreach (var process in processes) process.Dispose();
        var windows = new List<(IntPtr, bool, bool)>();
        if (ids.Count == 0) return windows;
        EnumWindows((handle, _) =>
        {
            GetWindowThreadProcessId(handle, out uint id);
            if (ids.Contains(id)) windows.Add((handle, IsWindowVisible(handle), GetWindow(handle, GwOwner) != IntPtr.Zero));
            return true;
        }, IntPtr.Zero);
        return windows;
    }

    /// <summary>Whether Obsidian is running for this teacher (see the remarks).</summary>
    public static bool IsRunning => Windows().Count > 0;

    /// <summary>
    /// Asks Obsidian to quit — every shown main window, then owned ones, then
    /// CloseMainWindow on what is left — and waits up to five seconds for its
    /// windows to go, then up to three more for its PROCESSES (measured on
    /// 1.14.4: windows gone at 0.4 s, processes at 0.66 s; a registry or an
    /// add-on list written in that gap could be overwritten as it exits). Any
    /// window still there afterwards means "did not close" for ALL of them:
    /// <see cref="IsRunning"/> stays true and the callers write nothing.
    /// (On Windows a pop-out is not an owned window, so "pop-outs after"
    /// orders nothing there; every window closes in the same 0.4 s.)
    /// </summary>
    /// <returns>Whether every Obsidian process of this session is gone. False
    /// with no window left means the processes outlived the 3 s: written to
    /// startup.log (for the developer, never the trail), since a write made
    /// then may still be overwritten.</returns>
    public static async Task<bool> QuitAndWaitAsync()
    {
        await CloseWindowsAndWaitAsync();
        if (IsRunning) return false;
        var clock = Stopwatch.StartNew();
        while (AnyProcessLeft() && clock.ElapsedMilliseconds < 3000) await Task.Delay(100);
        if (!AnyProcessLeft()) return true;
        App.LogDiagnostic("Obsidian: its windows closed but its processes were still running 3 s later; going on (#581).");
        return false;
    }

    private static async Task CloseWindowsAndWaitAsync()
    {
        if (!IsRunning) return;
        var shown = Windows().Where(w => w.Visible).ToList();
        foreach (var window in shown.Where(w => !w.Owned)) PostMessage(window.Handle, WmClose, IntPtr.Zero, IntPtr.Zero);
        foreach (var window in shown.Where(w => w.Owned)) PostMessage(window.Handle, WmClose, IntPtr.Zero, IntPtr.Zero);
        var clock = Stopwatch.StartNew();
        bool nudged = false;
        while (clock.ElapsedMilliseconds < 5000)
        {
            await Task.Delay(100);
            if (!IsRunning) return;
            if (!nudged && (clock.ElapsedMilliseconds > 1500 || !Windows().Any(w => w.Visible)))
            {
                // Nothing shown left, or the shown ones had their chance: a
                // window that is not shown must not be a dead end.
                nudged = true;
                foreach (var process in InThisSession())
                {
                    try { process.CloseMainWindow(); } catch { }
                    process.Dispose();
                }
            }
        }
    }

    /// <summary>Waits until Obsidian owns a window, for at most <paramref name="milliseconds"/>.</summary>
    public static async Task<bool> WaitUntilRunningAsync(int milliseconds)
    {
        var clock = Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < milliseconds)
        {
            if (IsRunning) return true;
            await Task.Delay(150);
        }
        return IsRunning;
    }

    private const uint WmClose = 0x0010;
    private const uint GwOwner = 4;

    private delegate bool EnumWindowsProc(IntPtr handle, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr handle);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr handle, uint command);

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
}

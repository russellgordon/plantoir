using System;
using System.Collections.Generic;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Services;

/// <summary>
/// The app's one File ▸ Open Recent list (#488; <c>shared-rules.json</c> →
/// <c>openRecent</c>), kept in <see cref="AppSettings.RecentWorkingFolders"/>.
/// The rule for what the list becomes is <see cref="RecentWorkingFolders"/>;
/// this is only where it is kept and who is told it changed.
/// </summary>
/// <remarks>
/// <para><b>Recorded on OPEN only</b>: <see cref="NoteOpened"/> is called by
/// <c>WorkspaceViewModel.ChooseWorkspace</c> (Open Working Folder…, Open
/// Recent, the picker) and <c>AdoptRestoredPath</c> (the app reopening a folder
/// at launch) — never on window activation, and never by Ctrl+N's window,
/// which inherits a folder rather than opening one.</para>
///
/// <para><see cref="Changed"/> is static, so every window's submenu is rebuilt
/// from one list: a folder opened in one window is offered by all of them.
/// Each window unsubscribes when it closes — a static event left subscribed
/// roots the window for the life of the process.</para>
/// </remarks>
public static class OpenRecentList
{
    /// <summary>Raised on the thread that changed the list, after it was saved.</summary>
    public static event Action? Changed;

    /// <summary>The folders, newest first.</summary>
    public static IReadOnlyList<string> Entries(AppSettings settings) => settings.RecentFolders;

    /// <summary>A folder was opened: to the top, unless it is already there spelled the same way.</summary>
    public static void NoteOpened(AppSettings settings, string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        var (after, writes) = RecentWorkingFolders.Adding(settings.RecentFolders, path);
        if (!writes) return;
        settings.RecentWorkingFolders = new List<string>(after);
        settings.Save();
        Changed?.Invoke();
    }

    /// <summary>File ▸ Open Recent ▸ Clear Menu, and the line that says so.</summary>
    public static void Clear(AppSettings settings)
    {
        int count = settings.RecentFolders.Count;
        if (count == 0) return;
        settings.RecentWorkingFolders = new List<string>();
        settings.Save();
        ActivityTrail.Note(ActivityTrail.Event.RecentWorkingFoldersCleared,
            $"recent working folders cleared — {count} {(count == 1 ? "folder" : "folders")}");
        Changed?.Invoke();
    }
}

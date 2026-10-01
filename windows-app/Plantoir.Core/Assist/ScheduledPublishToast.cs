using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Assist;

/// <summary>
/// The scheduled-publish toast's launch arguments, and what a CLICK on it does
/// (#324 / mac #306, <c>shared-rules.json → scheduledPublishStopped.notification.onClick</c>).
///
/// <para>The toast carries the course, the section and the working folder's
/// PATH — the identifier's folder id is a hash, so the path has to travel
/// beside it. The path is never shown and never written on the trail.</para>
///
/// <para>The decision is a pure function of the windows open (front to back),
/// so it is played from the contract's own cases rather than eyeballed; the
/// window itself only carries it out.</para>
/// </summary>
public static class ScheduledPublishToast
{
    public sealed record Target(string CourseCode, int Section, string WorkingFolder);

    // ---- Launch arguments --------------------------------------------------

    /// <summary><c>section=ICS3U/2&amp;folder=&lt;escaped path&gt;</c>.</summary>
    public static string Format(Target target) =>
        $"section={Uri.EscapeDataString(target.CourseCode)}/{target.Section}&folder={Uri.EscapeDataString(target.WorkingFolder)}";

    /// <summary>The target a toast names, or null when it names no section (or is not ours).</summary>
    public static Target? Parse(string? arguments)
    {
        if (string.IsNullOrWhiteSpace(arguments)) return null;
        var pairs = arguments.Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(p => p.Split('=', 2))
            .Where(p => p.Length == 2)
            .GroupBy(p => p[0], StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => Uri.UnescapeDataString(g.First()[1]), StringComparer.Ordinal);
        if (!pairs.TryGetValue("section", out var section) || !pairs.TryGetValue("folder", out var folder)) return null;
        int slash = section.LastIndexOf('/');
        if (slash <= 0 || !int.TryParse(section[(slash + 1)..], out int number) || number < 1) return null;
        if (string.IsNullOrWhiteSpace(folder)) return null;
        return new Target(section[..slash], number, folder);
    }

    // ---- What a click does -------------------------------------------------

    public enum WindowFolder { This, Other, None }

    /// <summary>One open window, front to back. <c>Busy</c>: a dialog in front of it, or a course being renamed in place.</summary>
    public sealed record OpenWindow(WindowFolder Folder, bool Busy = false);

    public enum Action { UseWindow, AdoptInto, OpenNewWindow, BringForwardOnly }

    public sealed record Decision(Action Action, int? Window, bool SelectsTheSection, bool OpensAWindow, string TrailSays);

    public const string Opened = "opened the section from its scheduled publish notification";
    public const string OpenedInANewWindow = "opened the section from its scheduled publish notification, in a new window";
    public const string OpenedInTheChoosingWindow =
        "opened the section from its scheduled publish notification, in the window that was choosing a working folder";
    public const string LeftBusyWindowAlone =
        "brought the working folder's window forward from a scheduled publish notification, and left it as it was because it was in the middle of something";
    public const string FolderGone =
        "a scheduled publish notification was clicked, but its working folder is no longer where it was, so Plantoir was only brought forward";
    public const string SectionGone =
        "showed the working folder from a scheduled publish notification; that section is no longer in it";
    public const string NamedNoSection =
        "a scheduled publish notification was clicked, but it did not say which section it was about";

    /// <summary>
    /// Show THAT section, in a window on the working folder the run was for:
    /// a window already on it (nearest the front, not busy); else a window
    /// with no folder takes it; else a new window. A window on another folder
    /// is never pointed elsewhere; a busy one is brought forward and left
    /// alone; a gone folder or a toast that names nothing only brings the app
    /// forward. Clicking changes nothing else — the record and the band stay.
    /// </summary>
    public static Decision Decide(bool carries, bool folderExists, bool sectionInFolder, IReadOnlyList<OpenWindow> windows)
    {
        if (!carries)
            return new Decision(Action.BringForwardOnly, windows.Count > 0 ? 0 : null, false, false, NamedNoSection);
        if (!folderExists)
            return new Decision(Action.BringForwardOnly, windows.Count > 0 ? 0 : null, false, false, FolderGone);

        var onIt = windows.Select((w, i) => (w, i)).Where(x => x.w.Folder == WindowFolder.This).ToList();
        if (onIt.FirstOrDefault(x => !x.w.Busy) is { w: not null } free)
            return new Decision(Action.UseWindow, free.i, sectionInFolder, false, sectionInFolder ? Opened : SectionGone);
        if (onIt.Count > 0)
            return new Decision(Action.BringForwardOnly, onIt[0].i, false, false, LeftBusyWindowAlone);

        if (sectionInFolder && windows.Select((w, i) => (w, i)).FirstOrDefault(x => x.w.Folder == WindowFolder.None && !x.w.Busy) is { w: not null } choosing)
            return new Decision(Action.AdoptInto, choosing.i, true, false, OpenedInTheChoosingWindow);

        return new Decision(Action.OpenNewWindow, null, sectionInFolder, true, sectionInFolder ? OpenedInANewWindow : SectionGone);
    }
}

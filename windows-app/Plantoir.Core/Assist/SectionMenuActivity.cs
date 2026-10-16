using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// Which sections the Section menu is changing right now, across this app
/// (#489, the mac's <c>SectionMenuActivity</c>, #457 batch B).
/// </summary>
/// <remarks>
/// <para><b>The menu's own claim.</b> A menu change runs in the window's own
/// server, the in-app assistant's in another; each keeps an undo list. If the
/// two wrote one section at once, the lists would interleave and "Undo Last
/// Change" or "undo that" would take back the other's work. So a menu change
/// holds the section here while it runs; the in-app assistant's write to that
/// section is refused before anything is backed up
/// (<see cref="AssistWording.SectionIsChangingFromTheMenu"/>), and the menu's
/// writing items grey while the assistant's window is working on it
/// (<see cref="AssistActivity.IsWorking"/>).</para>
///
/// <para><b>In-process, deliberately.</b> Both windows are in this app, so a
/// static set answers in a microsecond and needs no file. Another program's
/// work on the course is already the work leases' to say. The menu does NOT
/// hold the assistant's backups (<c>AssistActivity.holdBackups</c> on the mac,
/// which could have reopened #242).</para>
///
/// <para>Folders compare as <see cref="WorkingFolder.IsTheSame"/> does, codes
/// without regard to case. A null section asks about any section of the course.</para>
/// </remarks>
public static class SectionMenuActivity
{
    private readonly record struct Claim(string Folder, string CourseCode, int Section);

    private static readonly object Gate = new();
    private static readonly List<Claim> Claims = new();

    /// <summary>Raised whenever a claim begins or ends, so the menus can grey or come back.</summary>
    public static event Action? Changed;

    /// <summary>A menu change to this section has begun. Dispose to end it.</summary>
    public static IDisposable Begin(string folder, string courseCode, int section)
    {
        var claim = new Claim(folder, courseCode, section);
        lock (Gate) Claims.Add(claim);
        Changed?.Invoke();
        return new Ending(claim);
    }

    private sealed class Ending(Claim claim) : IDisposable
    {
        private int _ended;
        public void Dispose()
        {
            if (Interlocked.Exchange(ref _ended, 1) == 1) return;
            lock (Gate) Claims.Remove(claim);
            Changed?.Invoke();
        }
    }

    /// <summary>Whether the Section menu is changing this section (any section of the course when null).</summary>
    public static bool IsChanging(string folder, string courseCode, int? section)
    {
        lock (Gate)
            return Claims.Any(claim =>
                string.Equals(claim.CourseCode, courseCode, StringComparison.OrdinalIgnoreCase)
                && (section is null || claim.Section == section)
                && WorkingFolder.IsTheSame(claim.Folder, folder));
    }

    /// <summary>Forget everything, for tests.</summary>
    public static void Reset()
    {
        lock (Gate) Claims.Clear();
        Changed?.Invoke();
    }
}

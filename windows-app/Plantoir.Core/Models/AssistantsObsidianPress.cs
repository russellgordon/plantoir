namespace Plantoir.Core.Models;

/// <summary>
/// The order the in-app assistant's Open in Obsidian runs in, in its section's
/// main window (#690) - pulled out of <c>MainWindow.PressOpenInObsidianFor</c>
/// so a test can drive it without a window. <c>12-windows-app.md</c> → "The
/// assistant's Open in Obsidian on Windows (#690, the mac's #610)" says why each step is where
/// it is.
/// </summary>
/// <remarks>
/// <list type="number">
/// <item>No window of the folder with the course: <c>NoWindow</c>.</item>
/// <item>A question of an earlier Open in Obsidian press for the course is up
/// (<see cref="ObsidianFigureAddOnsThisRun.Asking"/>): <c>WaitingForAnAnswer</c>
/// and NO press - that press opens Obsidian once it is answered, and a second
/// one would open it twice and write a second trail line.</item>
/// <item>Any other dialog is up in the window: <c>WaitingForAnAnswer</c>, then
/// wait for it to close, at most <see cref="LongestWait"/>, and only while the
/// window is open. Nothing on screen is changed while it is awaited: swapping
/// the section under an open dialog would change what that dialog is about.
/// When the wait runs out, or the window closes, nothing is pressed.</item>
/// <item>Checked again (the folder, the course, a question) - then the section
/// is shown and the window comes forward if hidden, and only THEN pressed, so
/// the page read is the section's own.</item>
/// </list>
/// A fault anywhere completes the report with <c>DidNotOpen</c>, never an exception.
/// </remarks>
public static class AssistantsObsidianPress
{
    /// <summary>
    /// How long the press waits for a dialog already up to close. Ten minutes:
    /// long enough for a teacher to read and answer any question Plantoir asks,
    /// short enough that Obsidian never opens on its own long after the
    /// conversation has moved on.
    /// </summary>
    public static readonly TimeSpan LongestWait = TimeSpan.FromMinutes(10);

    /// <summary>How often the press looks again while it waits.</summary>
    public static readonly TimeSpan LookAgainEvery = TimeSpan.FromMilliseconds(300);

    /// <summary>What the press asks of its window.</summary>
    /// <param name="CoursePath">The course's folder in this window, or null when this window cannot show it.</param>
    /// <param name="DialogIsOpen">Whether a dialog is up in the window now.</param>
    /// <param name="IsClosed">Whether the window has closed.</param>
    /// <param name="BringUp">Shows the section and brings the window forward if hidden.</param>
    /// <param name="Press">The window's own Open in Obsidian for the section.</param>
    public sealed record Window(Func<string?> CoursePath, Func<bool> DialogIsOpen, Func<bool> IsClosed,
                                Action BringUp, Func<Task<OpenInObsidianPress>> Press);

    /// <summary>
    /// Runs the press, completing <paramref name="report"/> as soon as the
    /// outcome is known. Rethrows a fault after reporting <c>DidNotOpen</c>,
    /// so the caller can log it. <paramref name="delay"/> and
    /// <paramref name="longestWait"/> are a test's.
    /// </summary>
    public static async Task RunAsync(Window window, TaskCompletionSource<OpenInObsidianPress> report,
                                      Func<TimeSpan, Task>? delay = null, TimeSpan? longestWait = null)
    {
        delay ??= Task.Delay;
        var ceiling = longestWait ?? LongestWait;
        try
        {
            if (window.CoursePath() is not { } coursePath)
            {
                report.TrySetResult(new OpenInObsidianPress.NoWindow());
                return;
            }
            if (ObsidianFigureAddOnsThisRun.Asking.Contains(coursePath))
            {
                report.TrySetResult(new OpenInObsidianPress.WaitingForAnAnswer());
                return;
            }
            if (window.DialogIsOpen())
            {
                report.TrySetResult(new OpenInObsidianPress.WaitingForAnAnswer());
                var waited = TimeSpan.Zero;
                while (!window.IsClosed() && window.DialogIsOpen())
                {
                    if (waited >= ceiling) return;
                    await delay(LookAgainEvery);
                    waited += LookAgainEvery;
                }
                if (window.IsClosed()) return;
            }
            // Read again after any wait: the folder or the course may have
            // changed under the dialog, and the dialog may have been another
            // press's question that is up again.
            if (window.CoursePath() is not { } stillThere)
            {
                report.TrySetResult(new OpenInObsidianPress.NoWindow());
                return;
            }
            if (ObsidianFigureAddOnsThisRun.Asking.Contains(stillThere))
            {
                report.TrySetResult(new OpenInObsidianPress.WaitingForAnAnswer());
                return;
            }
            window.BringUp();
            report.TrySetResult(await window.Press());
        }
        catch
        {
            report.TrySetResult(new OpenInObsidianPress.DidNotOpen());
            throw;
        }
    }
}

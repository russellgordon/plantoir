using Plantoir.Core.Models;

namespace Plantoir.Core.Undo;

/// <summary>
/// Where this computer's list lives (#899 W2a, <c>undoJournal.directory</c>):
/// <c>undo\</c> in the app's state folder, <c>%LOCALAPPDATA%\Plantoir\undo</c>,
/// following <c>--state-dir</c> as everything the app keeps does. Never in a
/// working folder and never in OneDrive: the list must outlive a folder that
/// is moved, and a synced copy of it would be a second list.
///
/// <para>The ONLY place that reads <see cref="AppDataRoot"/> for Undo, so a
/// journal is otherwise handed its folder (the plan review's H1). Nothing
/// calls it before W4 builds the composition root.</para>
/// </summary>
internal static class UndoJournalLocation
{
    internal static string Folder => Path.Combine(AppDataRoot.Current, "undo");
}

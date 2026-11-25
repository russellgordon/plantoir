using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// The click on Restore from Backup…'s "Restore Section N" (#911 step 4, the
/// mac's <c>WorkspaceModel.restoreOneSection</c>), in its order, kept out of
/// the view so a test can hold the order: every offer condition and the busy
/// refusal asked again BEFORE the archive (a refused click leaves nothing in
/// Archived); the WHOLE course archived first, so "nothing is lost" holds
/// before Undo; the busy refusal asked again after the archive (it can take
/// seconds, and a preview or a Section menu change may have started meanwhile);
/// the restore; the <c>section restored</c> line, only once it has happened;
/// <c>page settings left as they were</c> when pages could not take a key;
/// then the finished title and sentence for the result dialog. A failure is
/// said in <see cref="BackupProblemTitle.Restoring"/> with the restorer's own
/// sentence, never "restored". No question is asked here: the one alert is
/// the caller's.
/// </summary>
public static class MenuSectionRestore
{
    /// <summary>What the result dialog says, and whether an archive was made (the sidebar then has a new Archived row to show).</summary>
    /// <param name="Finished">True only when the section was put back.</param>
    public sealed record Result(string Title, string Message, bool Finished, string? ArchivePath);

    /// <param name="busyRefusal">
    /// The sentence that refuses the restore because the course or this
    /// section is being worked on right now (a preview or deploy, an
    /// assistant's hold, the Section menu or the assistant changing this
    /// section: <see cref="OneSectionRestoreWording.Busy"/>), or null. Asked
    /// before the archive and again after it.
    /// </param>
    /// <param name="facts">The backup's facts, read once when the dialog was about to open (<see cref="OneSectionRestore.ReadFacts"/>).</param>
    public static Result Run(int sectionNumber, BackupItem item, Course? course, OneSectionRestore.BackupFacts facts,
                             string coursesDirectory, Func<string?> busyRefusal)
    {
        string refusedTitle = BackupProblemTitle.Restoring(item.CourseCode);
        if (busyRefusal() is { } busy) return new Result(refusedTitle, busy, false, null);
        if (OneSectionRestore.RefusalAtTheClick(sectionNumber, item, course, facts) is { } refusal)
            return new Result(refusedTitle, refusal, false, null);

        string? archive = null;
        try
        {
            archive = CourseArchiver.ArchiveCourseWithoutRemoving(course!, coursesDirectory);
            if (busyRefusal() is { } busyAfter) return new Result(refusedTitle, busyAfter, false, archive);

            var outcome = CourseRestorer.RestoreSectionFromTheMenu(sectionNumber, item, coursesDirectory);
            ActivityTrail.Note(ActivityTrail.Event.SectionRestored,
                ActivityTrail.RestoredOneSectionFromTheMenuLine(Path.GetFileName(item.FilePath), Path.GetFileName(archive),
                    outcome.PagesMadeSinceHidden, outcome.PagesNotSaved),
                item.CourseCode, sectionNumber);
            if (outcome.PagesNotPutBack > 0)
                ActivityTrail.Note(ActivityTrail.Event.PageSettingsLeftAsTheyWere,
                    ActivityTrail.PageSettingsLeftAsTheyWereLine("putting the section back from a backup", outcome.PagesNotPutBack),
                    item.CourseCode, sectionNumber);
            return new Result(OneSectionRestoreWording.DoneTitle(sectionNumber, item.CourseCode),
                OneSectionRestoreWording.Done(sectionNumber, item.WhenDescription, outcome), true, archive);
        }
        catch (Exception error)
        {
            return new Result(refusedTitle, error.Message, false, archive);
        }
    }
}

namespace Plantoir.Core.Models;

/// <summary>
/// The sentences of a one-section restore (#911): the mac's
/// <c>OneSectionRestoreWording</c>, word for word. Every one is a template in
/// <c>contracts/course-management.json</c> → <c>backups.restoreOneSection.wording</c>,
/// and <c>OneSectionRestoreContractTests</c> fills each template from the JSON
/// and compares it with what is here, so nothing is retyped into a test.
/// Kept out of the assistant's wording, as on the mac: they are the restore
/// dialog's and the restorer's, not the assistant's.
/// </summary>
public static class OneSectionRestoreWording
{
    /// <summary><c>wording.title</c>: the restore dialog's title when one section is offered.</summary>
    public static string Title(string course) => $"Restore {course} from this backup?";

    /// <summary><c>wording.message</c>: <paramref name="madeBy"/> is the backup's own <see cref="BackupMaker.DescriptionFor"/>, <paramref name="when"/> its <see cref="BackupItem.WhenDescription"/>.</summary>
    public static string Message(int section, string madeBy, string when) =>
        $"This backup was made {madeBy}, on {when}.\n\n" +
        $"Restore Section {section} puts back that section alone: its pages, its settings on the pages " +
        "every section shares, its class dates and its record of what was published. Your other sections " +
        $"are not touched. Anything changed in Section {section} since then goes back too, including work " +
        "done in Obsidian.\n\n" +
        "Restore Whole Course puts every section back to how it was then.\n\n" +
        "Either way, nothing is lost: the course as it is now moves to Archived, at the bottom of the " +
        "sidebar, where you can get it back. This backup is kept.";

    /// <summary><c>wording.restoreSectionButton</c>: the default button.</summary>
    public static string RestoreSectionButton(int section) => $"Restore Section {section}";

    /// <summary><c>wording.restoreWholeCourseButton</c>.</summary>
    public const string RestoreWholeCourseButton = "Restore Whole Course";

    /// <summary><c>wording.doneTitle</c>.</summary>
    public static string DoneTitle(int section, string course) => $"Section {section} of {course} is back";

    /// <summary>
    /// The finished sentence (<c>wording.done</c>, then each of the
    /// <c>hiddenSince…</c>, <c>notPutBack…</c>, <c>notSaved…</c> and
    /// <c>websiteUnchanged</c> pieces that applies, in that order, each after
    /// a blank line: <c>wording.doneJoin</c>).
    /// </summary>
    public static string Done(int section, string when, OneSectionRestore.Outcome outcome)
    {
        string text = $"Section {section} is back to how it was on {when}. Nothing in your other sections changed.";
        if (outcome.PagesMadeSinceHidden == 1)
            text += $"\n\nOne shared page that is not in the backup is now hidden from Section {section}, because the backup has no page at that place.";
        else if (outcome.PagesMadeSinceHidden > 1)
            text += $"\n\n{outcome.PagesMadeSinceHidden} shared pages that are not in the backup are now hidden from Section {section}, because the backup has no pages at those places.";
        if (outcome.PagesNotPutBack == 1)
            text += $"\n\nOne shared page kept the setting it has now for Section {section}: the settings at the top of it are written in a way Plantoir cannot add to, so that page was left exactly as it is.";
        else if (outcome.PagesNotPutBack > 1)
            text += $"\n\n{outcome.PagesNotPutBack} shared pages kept the settings they have now for Section {section}: the settings at the top of them are written in a way Plantoir cannot add to, so those pages were left exactly as they are.";
        if (outcome.PagesNotSaved == 1)
            text += $"\n\nOne shared page could not be saved, so it was left as it is. Its setting for Section {section} may not be what the backup had.";
        else if (outcome.PagesNotSaved > 1)
            text += $"\n\n{outcome.PagesNotSaved} shared pages could not be saved, so they were left as they are. Their settings for Section {section} may not be what the backup had.";
        if (outcome.WebsiteRecordDiffers)
            text += $"\n\nSection {section} still goes to the website address it has now. A restore does not change where students read it.";
        return text;
    }

    /// <summary><c>wording.notMadeForThisSection</c>: only a caller that skips the dialog's offer meets it.</summary>
    public static string NotMadeForThisSection(int section) =>
        $"This backup was not made for Section {section}. Restore Whole Course puts every section back together instead.";

    /// <summary><c>wording.foldersChanged</c>.</summary>
    public static string FoldersChanged(int section, string course) =>
        $"Section {section} cannot be put back on its own, because a folder this backup's course had has been renamed or removed in {course} since. Restore Whole Course puts every section back together instead.";

    /// <summary><c>wording.namingChanged</c>.</summary>
    public static string NamingChanged(int section, string course) =>
        $"Section {section} cannot be put back on its own, because the class pages of {course} are named differently now than they were in this backup. Restore Whole Course puts every section back together instead.";

    /// <summary><c>wording.busy</c>: the Section menu or the assistant is changing this section.</summary>
    public static string Busy(int section, string course) =>
        $"Section {section} of {course} is being changed right now. Wait for that to finish, then restore.";

    /// <summary><c>wording.sectionNotInCourse</c>.</summary>
    public static string SectionNotInCourse(int section, string course) =>
        $"{course} has no Section {section} now, so there is nowhere to put it back. Restore Whole Course puts every section back together instead.";

    /// <summary><c>wording.renameUnfinished</c>.</summary>
    public static string RenameUnfinished(int section, string course) =>
        $"Section {section} cannot be put back on its own while a rename in {course} has not finished. Finish it in Course Settings, or Restore Whole Course instead.";

    /// <summary><c>wording.leftAsItWas</c>: the swap failed and every file was put back where it was.</summary>
    public static string LeftAsItWas(int section, string reason) =>
        $"Section {section} was left as it was, because the restore could not finish: {reason}";

    /// <summary><c>wording.stoppedPartWay</c>: <paramref name="keptAt"/> is a path inside the working folder, quoted because the folder's name has spaces.</summary>
    public static string StoppedPartWay(int section, string keptAt) =>
        $"The restore of Section {section} stopped part way, so Section {section} may now hold some files from the backup " +
        $"and some as they were. Nothing was deleted: the files that were set aside are in the folder \"{keptAt}\" inside your working folder.";

    /// <summary><c>wording.stoppedPartWayNothingToOpen</c>: every page went back, and only Plantoir's own records are left set aside.</summary>
    public static string StoppedPartWayNothingToOpen(int section) =>
        $"The restore of Section {section} stopped part way, so Section {section} may now hold some files from the backup " +
        "and some as they were. Nothing was deleted, and none of your pages are left set aside.";

    /// <summary><c>wording.stoppedPartWayArchived</c>: added after a stopped sentence on the menu's route, which archives the whole course first.</summary>
    public const string StoppedPartWayArchived =
        "The course as it was before you pressed Restore is in Archived, at the bottom of the sidebar.";
}

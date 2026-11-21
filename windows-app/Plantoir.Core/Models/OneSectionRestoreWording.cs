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

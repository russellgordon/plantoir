namespace Plantoir.Core.Models;

/// <summary>
/// The sentences a one-section restore says when it stopped part way
/// (<c>course-management.json</c> → <c>backups.restoreOneSection.wording</c>,
/// pinned by <c>StagedRestoreTrailTests</c> against the templates; the mac's
/// <c>OneSectionRestoreWording</c>). Only the two the assistant window's route
/// uses on Windows today (#873); the rest of the menu route's wording belongs
/// to #911.
/// </summary>
public static class OneSectionRestoreWording
{
    /// <summary><c>wording.stoppedPartWay</c>: <paramref name="keptAt"/> is a path inside the working folder.</summary>
    public static string StoppedPartWay(int section, string keptAt) =>
        $"The restore of Section {section} stopped part way, so Section {section} may now hold some files from the backup " +
        $"and some as they were. Nothing was deleted: the files that were set aside are in the folder \"{keptAt}\" inside your working folder.";

    /// <summary><c>wording.stoppedPartWayNothingToOpen</c>: every page went back, and only hidden records are left set aside.</summary>
    public static string StoppedPartWayNothingToOpen(int section) =>
        $"The restore of Section {section} stopped part way, so Section {section} may now hold some files from the backup " +
        "and some as they were. Nothing was deleted, and none of your pages are left set aside.";
}

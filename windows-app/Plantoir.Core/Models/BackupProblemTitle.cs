namespace Plantoir.Core.Models;

/// <summary>
/// The title of the dialog a backup, restore, deletion or removal problem is
/// shown in: it names the act that failed (#491 item 9; the mac's
/// <c>BackupProblemTitle</c>, word for word). Until then Windows' said "Could
/// not back up", "Could not restore", "Could not delete" — never WHAT — which
/// names nothing on the day a teacher most needs to know what went wrong.
/// </summary>
public static class BackupProblemTitle
{
    public const string DeletingArchive = "Could not delete the archive";

    public static string BackingUp(string courseCode) => $"Could not back up {courseCode}";

    public static string Restoring(string courseCode) => $"Could not restore {courseCode}";

    public static string DeletingBackups(int count) =>
        count == 1 ? "Could not delete the backup" : "Could not delete the backups";

    /// <summary>
    /// Windows' own: removing a course or section reports its failure in a
    /// dialog of its own here (the mac's removal has no such alert). Named the
    /// same way.
    /// </summary>
    public static string Removing(string courseCode) => $"Could not remove {courseCode}";
}

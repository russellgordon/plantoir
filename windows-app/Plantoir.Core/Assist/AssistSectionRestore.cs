using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// The way back for a WHOLE conversation: one section, put back to how it was
/// when the chat started, from the copy the first change saved.
///
/// <para>A different promise from <see cref="UndoHistory"/>, which takes back
/// one change at a time. A teacher who let the assistant make six changes and
/// wants the section as it was would otherwise have to undo six times and
/// know that is what they were doing. The wording and the code live together
/// here, as they do on the mac (<c>AssistSectionRestore.swift</c>), whose
/// sentences these are verbatim.</para>
/// </summary>
public static class AssistSectionRestore
{
    public sealed class Problem(string message) : Exception(message);

    public const string NothingToRestore =
        "This conversation hasn't changed anything yet, so there is nothing to put back.";
    public const string NoWorkingFolder =
        "Plantoir cannot find the working folder these courses live in.";
    public static string UnreadableBackup(string name) =>
        $"The copy saved for this conversation ({name}) could not be read.";

    /// <summary>The ellipsis is the promise that a question comes next.</summary>
    public static string ButtonTitle(int sectionNumber) => $"Restore Section {sectionNumber}…";
    public static string BannerTitle(int sectionNumber) => $"This conversation has changed Section {sectionNumber}.";
    public static string BannerDetail() => "A copy from before it started is saved.";
    public static string ConfirmationTitle(string courseCode, int sectionNumber) =>
        $"Put {courseCode} Section {sectionNumber} back to how it was?";

    /// <summary>
    /// Three paragraphs, and the third is the one nobody guesses. It is a
    /// promise, and <see cref="CourseRestorer.RestoreSection"/> is what makes
    /// it true: the section folder is replaced wholesale, work done in
    /// Obsidian included.
    /// </summary>
    public static string ConfirmationMessage(string courseCode, int sectionNumber) =>
        $"Section {sectionNumber} goes back to exactly how it was when this conversation started — " +
        $"its pages, and whether the course's shared pages are published for Section {sectionNumber}.\n\n" +
        "Your other sections are not touched. Their pages, and their own publishing, stay exactly " +
        "as they are.\n\n" +
        $"Anything YOU changed in Section {sectionNumber} since this conversation started goes back " +
        "too — work done in Obsidian included. Plantoir cannot bring that part back.";
    public static string GoAheadTitle(int sectionNumber) => $"Restore Section {sectionNumber}";
    public static string DoneMessage(string courseCode, int sectionNumber) =>
        $"Put {courseCode} Section {sectionNumber} back to how it was when this conversation " +
        "started. Nothing in your other sections was touched. Ask me to rebuild the preview to " +
        "see it.";

    /// <summary>
    /// Puts the section back, or throws a <see cref="Problem"/> saying why
    /// not. Nothing is auto-rebuilt afterwards: the done sentence tells the
    /// teacher to ask, and a version that rebuilt on its own would contradict
    /// the sentence it had just shown.
    /// </summary>
    public static void Restore(string? backupPath, string courseCode, int sectionNumber, string? coursesDirectory)
    {
        if (backupPath is null) throw new Problem(NothingToRestore);
        if (coursesDirectory is null) throw new Problem(NoWorkingFolder);
        if (!File.Exists(backupPath) || BackupItem.From(backupPath, courseCode) is not { } item)
            throw new Problem(UnreadableBackup(Path.GetFileName(backupPath)));
        try { CourseRestorer.RestoreSection(sectionNumber, item, coursesDirectory); }
        catch (CourseRestorer.RestoreException error) { throw new Problem(error.Message); }
        catch (IOException error) { throw new Problem(error.Message); }
        catch (UnauthorizedAccessException error) { throw new Problem(error.Message); }
    }
}

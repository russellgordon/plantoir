using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Core.Models;

/// <summary>
/// Course Settings' How I Teach row (<c>shared-rules.json</c> →
/// <c>howITeachPage.settingsButton</c>; GitHub issue #360, the mac's #329):
/// "Open" when the course has a page — found by LISTING the course folder, so
/// the teacher's own spelling counts — and "Create and Open" when it has none.
/// </summary>
/// <remarks>
/// <para><b>The trap that would pass review</b> is writing the page with
/// <c>File.WriteAllText</c>: it overwrites a page the teacher made a moment
/// earlier. The page is planned as new into ONE step, which the door refuses
/// if a page appears before its swap (#899 W7b2-4), and the page that
/// appeared between the look and the write is the teacher's and is what is
/// opened. Exactly <see cref="CreatedBytes"/> and nothing else — no starter
/// words, because an assistant reads the page as the teacher's own approach
/// (#209 rejected a template); <c>emptyPageIsNotWritten</c> is what stops the
/// empty page being described as written.</para>
/// </remarks>
public static class HowITeachSettingsRow
{
    public const string RowLabel = "How I Teach page";
    public const string OpenButton = "Open";
    public const string CreateButton = "Create and Open";
    public const string Caption = "Your notes on how this course is taught, for you and any assistant you use. It is never on the website.";
    public const string CouldNotCreateTemplate = "The How I Teach page could not be made: {reason}";
    public const string CreatedBytes = "---\npublish: false\n---\n";

    public enum Outcome { Created, Opened, CouldNotCreate }

    /// <summary>What the button says for this course right now.</summary>
    public static string ButtonFor(string courseDirectory) =>
        HowITeachPage.ExistingPath(courseDirectory) is null ? CreateButton : OpenButton;

    public static string CouldNotCreate(string reason) =>
        CouldNotCreateTemplate.Replace("{reason}", reason, StringComparison.Ordinal);

    /// <summary>
    /// Press the button: the page that is there, or a new empty one made
    /// beside nothing. Opening a page that is there writes nothing, to the
    /// page or to the trail.
    /// </summary>
    public static (Outcome Outcome, string? Path, string? Problem) Press(string courseDirectory, string courseCode) =>
        Press(courseDirectory, courseCode, betweenTheLookAndTheWrite: null);

    /// <param name="betweenTheLookAndTheWrite">For the test of the race: runs after the listing found no page and before the page is planned.</param>
    public static (Outcome Outcome, string? Path, string? Problem) Press(string courseDirectory, string courseCode,
                                                                          Action? betweenTheLookAndTheWrite) =>
        Press(courseDirectory, courseCode, betweenTheLookAndTheWrite, undo: null, door: null);

    /// <summary>
    /// The same, on a test's own list and door (this process's when null):
    /// the new page is ONE step through the door (#899 W7b2-4; the mac's
    /// <c>HowITeachPage.startOrFind</c>), key <c>startHowITeachPage</c>, made
    /// by <c>sheet</c>, held by the course (<c>holds: course</c>, no section).
    /// </summary>
    /// <remarks>
    /// The exclusive create is now a check at plan time plus the door's
    /// refusal of a file changed since then: a page already there when the
    /// step reads its before is opened, never planned over; one that appears
    /// after that is refused by the swap (<c>changedSince</c>) and opened.
    /// A step of one NEW page cannot be left part way: the swap refuses only
    /// before the page goes in, and nothing else is in the step to put back.
    /// </remarks>
    internal static (Outcome Outcome, string? Path, string? Problem) Press(string courseDirectory, string courseCode,
                                                                            Action? betweenTheLookAndTheWrite,
                                                                            UndoForThisProcess? undo, UndoDoor? door)
    {
        if (HowITeachPage.ExistingPath(courseDirectory) is { } existing) return (Outcome.Opened, existing, null);
        betweenTheLookAndTheWrite?.Invoke();

        string path = Path.Combine(courseDirectory, HowITeachPage.FileName);
        var step = new UndoActionStep(new UndoStepMaker("sheet", "startHowITeachPage"), WorkingFolderOf(courseDirectory),
                                      courseCode, section: null, holds: "course", undo: undo, door: door);
        try
        {
            step.Write(path, CreatedBytes);
            // Plan time: the step's before is read now. A page there already
            // (made since the look) is the teacher's, and is what is opened.
            if (!PlannedAsANewPage(step)) return (Outcome.Opened, HowITeachPage.ExistingPath(courseDirectory) ?? path, null);
            step.Make();
            ActivityTrail.Note(ActivityTrail.Event.HowITeachPageStarted,
                $"{courseCode}: started an empty How I Teach page from Course Settings");
            return (Outcome.Created, path, null);
        }
        catch (UndoStepRefusedException) when (HowITeachPage.ExistingPath(courseDirectory) is { } appeared)
        {
            // Made between the plan and the swap: the teacher's, and opened.
            return (Outcome.Opened, appeared, null);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            ActivityTrail.Note(ActivityTrail.Event.HowITeachPageStarted,
                $"{courseCode}: could not start the How I Teach page from Course Settings: {error.Message}");
            return (Outcome.CouldNotCreate, null, CouldNotCreate(error.Message));
        }
    }

    /// <summary>Whether the step plans the page as new: its one file absent when first planned.</summary>
    private static bool PlannedAsANewPage(UndoActionStep step)
    {
        var changed = step.ChangedFiles;
        return changed.Count == 1 && changed[0].BeforeBytes is null;
    }

    /// <summary>The folder holding <c>courses\</c> above a course's folder, or null when the course is not inside one.</summary>
    private static string? WorkingFolderOf(string courseDirectory)
    {
        string? coursesFolder = Path.GetDirectoryName(Path.GetFullPath(courseDirectory).TrimEnd(Path.DirectorySeparatorChar));
        if (coursesFolder is null || !string.Equals(Path.GetFileName(coursesFolder), "courses", StringComparison.OrdinalIgnoreCase))
            return null;
        return Path.GetDirectoryName(coursesFolder);
    }
}

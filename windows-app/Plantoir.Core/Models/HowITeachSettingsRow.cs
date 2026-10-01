using Plantoir.Core.Scripting;

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
/// earlier. <see cref="FileMode.CreateNew"/> refuses, and the page that
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

    /// <param name="betweenTheLookAndTheWrite">For the test of the race: runs after the listing found no page and before the write.</param>
    public static (Outcome Outcome, string? Path, string? Problem) Press(string courseDirectory, string courseCode,
                                                                          Action? betweenTheLookAndTheWrite)
    {
        if (HowITeachPage.ExistingPath(courseDirectory) is { } existing) return (Outcome.Opened, existing, null);
        betweenTheLookAndTheWrite?.Invoke();

        string path = Path.Combine(courseDirectory, HowITeachPage.FileName);
        try
        {
            using (var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                byte[] bytes = System.Text.Encoding.UTF8.GetBytes(CreatedBytes);
                stream.Write(bytes, 0, bytes.Length);
            }
            ActivityTrail.Note(ActivityTrail.Event.HowITeachPageStarted,
                $"{courseCode}: started an empty How I Teach page from Course Settings");
            return (Outcome.Created, path, null);
        }
        catch (IOException) when (HowITeachPage.ExistingPath(courseDirectory) is { } appeared)
        {
            // Made between the look and the write: the teacher's, and opened.
            return (Outcome.Opened, appeared, null);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            ActivityTrail.Note(ActivityTrail.Event.HowITeachPageStarted,
                $"{courseCode}: could not start the How I Teach page from Course Settings: {error.Message}");
            return (Outcome.CouldNotCreate, null, CouldNotCreate(error.Message));
        }
    }
}

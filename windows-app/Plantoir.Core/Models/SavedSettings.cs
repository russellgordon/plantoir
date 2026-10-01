namespace Plantoir.Core.Models;

/// <summary>
/// The course's settings as SAVED in its file, for every act that sends a
/// site somewhere or sets a deploy (#357 / mac #335,
/// <c>shared-rules.json → actsUseTheSavedSettings</c>), and the sentences
/// that tell a teacher when unsaved Course Settings edits are being left out
/// (#272 / mac #265). Course Settings keeps unsaved edits in the window's
/// in-memory copy; the launcher, the approval card, both assistants and a
/// scheduled run all read the file — so the window's acts read it too, or a
/// publish is half from each.
///
/// <para>Rejected (the contract's list): saving automatically before the act;
/// refusing while anything is unsaved; using the unsaved edits for
/// everything; refreshing the window's copy from disk (throws edits away).
/// When the file cannot be read the act is REFUSED — a destination has no
/// safe default, so the window's copy is never used in its place.</para>
/// </summary>
public static class SavedSettings
{
    /// <summary>The course as its file says now, or null when the file cannot be read.</summary>
    public static Course? Read(Course course)
    {
        try { return new Course(course.Code, course.DirectoryPath, CourseConfiguration.Load(course.ConfigFilePath)); }
        catch { return null; }
    }

    // ---- specialNames (message only) -----------------------------------

    public static string CouldNotBeReadToDeploy(string course) =>
        $"{course}’s settings could not be read just now, so there is no telling where to deploy it. Open " +
        "Course Settings, check them and save, then try again.";

    public const string DeployUsesSavedSettings =
        "Course Settings has changes you have not saved, so this deploy uses the settings as they were last saved.";

    public const string SchedulingUsesSavedSettings =
        "Course Settings has changes you have not saved, so what is shown here is worked out from the settings as " +
        "they were last saved. A deploy set now uses whatever is saved when it runs.";

    public const string PreviewUsesSavedSettings =
        "Course Settings has changes you have not saved, so this preview uses the settings as they were last saved.";

    public const string SavedWhilePreviewing =
        "A preview of this course is still showing the settings it started with. Press Preview Again to see what " +
        "you just saved.";

    public const string SavedWhilePublishing =
        "This course is being published right now, and that publish uses the settings from before this save. " +
        "Publish again once it has finished to send what you just saved.";

    public const string PreviewAgainNothingOpen =
        "That preview has stopped since, so there is nothing to preview again. Open the section and press Preview " +
        "to see what you saved.";

    /// <summary>
    /// The trail line for <c>deploy used the saved settings</c>: the act, the
    /// KINDS the saved settings send it to, and whether the unsaved edits named
    /// a different kind — never a path or a site name.
    /// </summary>
    public static string DeployUsedTheSavedSettingsLine(string act, Course saved, Course inWindow)
    {
        var savedKinds = saved.Configuration.AllDeployDestinations.Select(d => d.Type).Distinct().ToList();
        var windowKinds = inWindow.Configuration.AllDeployDestinations.Select(d => d.Type).Distinct().ToList();
        bool differs = !savedKinds.OrderBy(k => k, StringComparer.Ordinal)
                                  .SequenceEqual(windowKinds.OrderBy(k => k, StringComparer.Ordinal));
        return $"{act} with unsaved Course Settings: used the saved settings ({string.Join(", ", savedKinds)}); " +
               (differs ? "the unsaved edits named a different kind of destination" : "the unsaved edits named the same kind");
    }
}

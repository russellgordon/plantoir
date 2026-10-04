using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// Removing a course or a section turns its scheduled deploys off FIRST (#239,
/// mac #236; <c>shared-rules.json</c> → <c>scheduledDeployCancellation</c>).
/// </summary>
/// <remarks>
/// <para><b>The order is the opposite of a rename's, and that is the point.</b>
/// A rename that cancelled before a failed move would silently drop a deploy for
/// a course still sitting there; a REMOVAL that archived before a failed cancel
/// leaves a course that is gone with a live alarm still addressed to it — and on
/// this side that alarm REPORTS SUCCESS for every folder and Cloudflare course,
/// because <c>publish_to_cloudflare</c> never refuses and the teacher surname it
/// needs lives in the working folder, which survives. So a cancel that FAILS
/// stops the removal, and if the removal then fails the deploy stays cancelled
/// and the sentence says so.</para>
///
/// <para>Until bundle 3 this app turned a SECTION's deploy off on removal and a
/// COURSE's not at all. The scheduler is asked what exists — not the course's
/// section list, which a section removed on an earlier build had already left —
/// and only this working folder's deploys are touched.</para>
/// </remarks>
public static class ScheduledDeployRemoval
{
    /// <summary>A removal that did not happen because a scheduled deploy could not be turned off.</summary>
    public sealed class StillScheduledException(string message) : InvalidOperationException(message);

    /// <summary>The sections of this course that this working folder has set to deploy on their own.</summary>
    public static IReadOnlyList<int> ScheduledSections(string workingFolder, string courseCode, int? section = null) =>
        TaskScheduling.InFolder(workingFolder)
            .Where(task => TaskScheduling.SameCode(task.CourseCode, courseCode))
            .Where(task => section is null || task.Section == section)
            .Select(task => task.Section)
            .Distinct()
            .OrderBy(number => number)
            .ToList();

    /// <summary>
    /// Turn off every scheduled deploy this working folder holds for the course
    /// (or one section of it) and put a line on the trail for each. Throws
    /// <see cref="StillScheduledException"/>, having removed nothing else, when
    /// one cannot be turned off.
    /// </summary>
    /// <returns>The sections turned off.</returns>
    public static IReadOnlyList<int> TurnOffFirst(string workingFolder, string courseCode, int? section, string why)
    {
        var (turnedOff, problem) = TaskScheduling.CancelFor(workingFolder, courseCode, section);
        foreach (int number in turnedOff)
            ActivityTrail.Note(ActivityTrail.Event.ScheduledDeployTurnedOff, $"turned off: {why}", courseCode, number);
        if (problem is null) return turnedOff;

        var still = ScheduledSections(workingFolder, courseCode, section);
        throw new StillScheduledException(CouldNotTurnItOff(courseCode, still.Count > 0 ? still : [section ?? 1]));
    }

    // ---- What a teacher reads (scheduledDeployCancellation.wording) ---------

    /// <summary>"Section 1", or "Sections 1 and 2" — the listing a rename uses.</summary>
    public static string Sections(IReadOnlyList<int> sections) => CourseRenamer.Listed(sections);

    public static string ConfirmationSectionRemoved(int section) =>
        $"Section {section} is set to deploy on its own. Removing it turns that off.";

    public static string ConfirmationCourseRemoved(string course, IReadOnlyList<int> sections) =>
        sections.Count == 1
            ? $"{Sections(sections)} of {course} is set to deploy on its own. Removing {course} turns that off."
            : $"{Sections(sections)} of {course} are set to deploy on their own. Removing {course} turns that off.";

    public static string CouldNotTurnItOff(string course, IReadOnlyList<int> sections) =>
        sections.Count == 1
            ? $"{Sections(sections)} of {course} is set to deploy on its own, and Plantoir could not turn that off — " +
              "so nothing has been removed. Turn off the scheduled deploy from the section’s menu, then try again."
            : $"{Sections(sections)} of {course} are set to deploy on their own, and Plantoir could not turn that off — " +
              "so nothing has been removed. Turn off the scheduled deploys from the section’s menu, then try again.";

    public static string RemovalFailedAfterTurningItOff(string course, IReadOnlyList<int> sections, string reason) =>
        sections.Count == 1
            ? $"{Sections(sections)} of {course} will no longer deploy on its own — that was turned off first. " +
              $"Removing it then failed: {reason}"
            : $"{Sections(sections)} of {course} will no longer deploy on their own — that was turned off first. " +
              $"Removing it then failed: {reason}";
}

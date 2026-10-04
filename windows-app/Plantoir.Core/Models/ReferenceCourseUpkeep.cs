using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// What reading a working folder does for its reference courses (#241/#244):
/// sweeps what an unfinished import left behind, re-asserts every reference
/// course's lock, and turns off any deploy a reference course still has set
/// (<c>scheduledDeployCancellation</c>, "a course kept for reference is met
/// when the working folder is read" — an alarm set before the course was
/// marked). Run OFF the UI thread on every read of the folder; never on a
/// timer. Each part writes a trail line only when it actually did something,
/// so a folder in a steady state leaves no lines at all.
/// </summary>
public static class ReferenceCourseUpkeep
{
    /// <summary>The reason a scheduled deploy is turned off when it belongs to a reference course.</summary>
    public const string TurnedOffBecause = "the course is kept for reference, and is never deployed";

    public static void BringUpToDate(string workingFolder, IReadOnlyList<Course> courses)
    {
        string coursesDirectory = Workspace.CoursesDirectory(workingFolder);
        var swept = ReferenceStaging.SweepLeftovers(coursesDirectory);
        if (swept.Count > 0)
            ActivityTrail.Note(ActivityTrail.Event.UnfinishedImportForReferenceTidiedAway, ReferenceStaging.SweptTrailLine(swept));

        foreach (var course in courses.Where(ReferenceCourse.IsKeptForReference))
        {
            var outcome = ReferenceLock.EnsureLocked(course);
            if (!outcome.IsQuiet)
                ActivityTrail.Note(ActivityTrail.Event.ReferenceCoursePagesLockedAgain, TrailLine(outcome, ReferenceCourse.ShownCode(course)));
            try
            {
                if (ScheduledDeployRemoval.ScheduledSections(workingFolder, course.Code).Count > 0)
                    ScheduledDeployRemoval.TurnOffFirst(workingFolder, course.Code, section: null, TurnedOffBecause);
            }
            catch { /* the launcher refuses it on its own when it fires; the next read tries again */ }
        }
    }

    /// <summary>
    /// <c>locked 3 pages of ICS3U again — it is kept for reference</c>, plus the
    /// census when it disagrees and the count that would not stay locked. The
    /// line says only the counts, never a cause: a cloud folder and a volume
    /// with no access rules produce the same numbers.
    /// </summary>
    public static string TrailLine(ReferenceLock.Outcome outcome, string shownCode)
    {
        string line = outcome.Locked > 0
            ? $"locked {(outcome.Locked == 1 ? "1 page" : $"{outcome.Locked} pages")} of {shownCode} again — it is kept for reference"
            : $"checked that {shownCode}’s pages are locked — it is kept for reference";
        if (!outcome.EverythingThatShouldBeLockedIs) line += $"; {outcome.LockedOnDisk} of {outcome.ShouldBeLocked} are locked";
        if (outcome.DidNotTake > 0)
            line += $"; {(outcome.DidNotTake == 1 ? "1 page" : $"{outcome.DidNotTake} pages")} would not stay locked this time";
        return line;
    }

    /// <summary>
    /// Set School Year… — the ONE thing a frozen course still lets a teacher
    /// change, and a label on the shelf rather than a page. Refused, with the
    /// shelf's sentence, when that year already holds the code. Writes
    /// <c>reference course school year changed</c> only when the year really
    /// changed and was saved; a failed write returns
    /// <see cref="ReferenceCourse.CouldNotSetSchoolYear"/> and writes nothing.
    /// </summary>
    /// <returns>Null when done, else the sentence for the teacher.</returns>
    public static string? SetSchoolYear(Course course, int? startingYear, IReadOnlyList<Course> allCourses, DateOnly today)
    {
        string shown = ReferenceCourse.ShownCode(course);
        if (!ReferenceCourse.IsKeptForReference(course)) return null;
        int? before = SchoolYear.Read(course.Configuration.StoredReferenceSchoolYear, today);
        if (before == startingYear) return null;
        if (ReferenceCourse.ShelfTrouble(shown, startingYear, ReferenceCourse.Shelf(allCourses, today), ignoringFolder: course.Code) is { } trouble)
            return trouble;
        try
        {
            course.Configuration.SetReferenceSchoolYear(startingYear);
            course.Configuration.Write(course.ConfigFilePath);
        }
        catch
        {
            try { course.Configuration.RevertToFile(course.ConfigFilePath); } catch { }
            return ReferenceCourse.CouldNotSetSchoolYear(shown);
        }
        ActivityTrail.Note(ActivityTrail.Event.ReferenceCourseSchoolYearChanged,
            $"filed {shown} ({course.Code}) under {SchoolYear.Name(startingYear)} — it was {SchoolYear.Name(before)}");
        return null;
    }
}

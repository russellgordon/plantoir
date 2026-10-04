using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// What Course Settings records when a name leaves or comes back to one of its
/// four Content Structure lists, and when Revert takes those changes back
/// (<c>shared-rules.json</c> → <c>excludedItems.recordedOnClick</c>; GitHub
/// issue #348, the mac's #152). In Core so the contract's cases run through
/// exactly what the page calls; <c>CourseSettingsView</c> is three thin call
/// sites.
/// </summary>
/// <remarks>
/// <para>Written on the CLICK, whether or not the change is ever saved: a
/// teacher who excludes and crashes before saving must leave a trace. A Save,
/// an Add Section, or any other writer records no line of its own. Recording
/// at the write was REJECTED (Russell, 2026-09-06) — the mac built it first
/// and withdrew it the same day, because a crash leaves nothing — and so was
/// leaving the revert quirk documented: a line saying a folder was excluded
/// when the Revert took it back is the false line rule 5 forbids.</para>
/// </remarks>
public static class CourseSettingsExclusions
{
    /// <summary>A name left a list. A FOLDER's removal is the whole gesture (<see cref="FolderRemoval"/>).</summary>
    public static void RecordExclusion(CourseConfiguration config, string courseCode, string? courseDirectory,
                                       string scope, string kind, string name)
    {
        if (kind == "folder") FolderRemoval.RemoveFolderFromCourse(config, courseDirectory, scope, name);
        else config.Exclude(scope, name);
        // No section on the line: these lists are COURSE-wide.
        ActivityTrail.Note(ActivityTrail.Event.ItemExcluded,
            $"{courseCode}: removed the {CourseConfiguration.ScopeInWords(scope)} {kind} “{name}” from this course's site");
    }

    /// <summary>
    /// A name came back. The line goes on ONLY when the name really was
    /// excluded — an ordinary new folder is not a re-inclusion.
    /// </summary>
    public static bool RecordReInclusion(CourseConfiguration config, string courseCode, string scope, string kind, string name)
    {
        if (!config.ReInclude(scope, name)) return false;
        ActivityTrail.Note(ActivityTrail.Event.ItemReIncluded,
            $"{courseCode}: added the {CourseConfiguration.ScopeInWords(scope)} {kind} “{name}” back to this course's site");
        return true;
    }

    /// <summary>
    /// The Revert button. Counts this copy's unsaved exclusion changes BEFORE
    /// reading the file back, and writes one <c>exclusions reverted</c> line
    /// when there were any.
    /// </summary>
    public static void Revert(CourseConfiguration config, string courseCode, string configPath)
    {
        int count = config.ExclusionChangesSinceLastRead();
        config.RevertToFile(configPath);
        if (count == 0) return;
        ActivityTrail.Note(ActivityTrail.Event.ExclusionsReverted,
            $"{courseCode}: Revert put back {count} unsaved {(count == 1 ? "change" : "changes")} to what this course's site leaves out");
    }
}

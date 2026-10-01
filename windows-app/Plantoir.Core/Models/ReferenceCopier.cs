using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Assist;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// Keep a Copy for Reference… (#241, mac #206 branch A): a frozen copy of a
/// course, under <c>CODE-YYYY</c>, made in a hidden staging folder and renamed
/// into place last. The same making — marker, year, neutralisation, site
/// markers released, the lock, reading view — finishes every import too
/// (<see cref="MakeIntoAReferenceCourse"/>).
///
/// <para><b>One failure line, from ONE catch</b> (#287): <see cref="KeepACopy"/>
/// wraps a private <c>MakeTheCopy</c> and writes <c>course could not be kept
/// for reference</c> once, around the whole act, so a way to fail added later
/// is covered without anyone remembering. A copy that was made writes
/// <c>course kept for reference</c> instead, never both.</para>
/// </summary>
public static class ReferenceCopier
{
    /// <summary>What a made reference course came to.</summary>
    public sealed record Made(string FolderName, string ShownCode, int? SchoolYear, int SectionCount);

    /// <summary>A copy that was not made, with the sentence the teacher was shown.</summary>
    public sealed class NotMade : Exception
    {
        public NotMade(string sentence) : base(sentence) { }
    }

    /// <summary>What Keep a Copy leaves behind besides the archive list: yesterday's settings.</summary>
    public static readonly IReadOnlyList<string> AlsoLeftBehind = new[] { "course_config.backup.json" };

    /// <summary>Every name Keep a Copy never copies, at any depth.</summary>
    public static IReadOnlySet<string> LeftBehindNames =>
        CourseArchiver.ExcludedFromArchives.Concat(AlsoLeftBehind).ToHashSet(StringComparer.Ordinal);

    /// <summary>
    /// Makes a reference copy of <paramref name="course"/> called
    /// <paramref name="folderName"/>, filed under <paramref name="schoolYear"/>.
    /// Throws <see cref="NotMade"/> with the sentence for the teacher; whatever
    /// was half-made is unlocked and removed first. Run it OFF the UI thread.
    /// </summary>
    public static Made KeepACopy(Course course, string folderName, int? schoolYear, string coursesDirectory,
        IProgress<ReferenceTreeCopier.Progress>? progress = null, CancellationToken stop = default)
    {
        string shownFrom = ReferenceCourse.ShownCode(course);
        try
        {
            return MakeTheCopy(course, folderName, schoolYear, coursesDirectory, progress, stop);
        }
        catch (Exception problem)
        {
            string sentence = problem is NotMade ? problem.Message : ReferenceCourse.CopyCouldNotBeMade(problem.Message);
            ActivityTrail.Note(ActivityTrail.Event.CourseCouldNotBeKeptForReference,
                FailureTrailLine(shownFrom, folderName, sentence));
            throw problem is NotMade ? problem : new NotMade(sentence);
        }
    }

    /// <summary><c>could not keep a copy of ICS3U for reference as ICS3U-2025 — &lt;sentence&gt;</c></summary>
    public static string FailureTrailLine(string copiedFrom, string folderName, string sentence) =>
        $"could not keep a copy of {copiedFrom} for reference as {folderName} — {sentence}";

    private static Made MakeTheCopy(Course course, string folderName, int? schoolYear, string coursesDirectory,
        IProgress<ReferenceTreeCopier.Progress>? progress, CancellationToken stop)
    {
        string destination = Path.Combine(coursesDirectory, folderName);
        if (Directory.Exists(destination) || File.Exists(destination))
            throw new NotMade(ReferenceCourse.FolderAlreadyThere(folderName));

        string staging = Path.Combine(coursesDirectory, ReferenceStaging.StagingName(folderName));
        var claim = ReferenceStaging.TryClaim(coursesDirectory, folderName, ReferenceCourse.CopyAlreadyBeingMade(folderName));
        if (claim.Outcome != ReferenceStaging.Outcome.Claimed)
            throw new NotMade(claim.Outcome == ReferenceStaging.Outcome.Refused
                ? claim.Reason!
                : ReferenceCourse.CopyCouldNotBeMade(claim.Reason ?? ""));
        try
        {
            var addOns = ObsidianAddOns.FoundIn(course.DirectoryPath);
            try
            {
                var survey = ReferenceTreeCopier.Walk(course.DirectoryPath, LeftBehindNames, ObsidianAddOns.LeftBehindFromTheCourse);
                if (survey.UnreadableFolders.Count > 0)
                    throw new NotMade(ReferenceImport.CouldNotReadFolder(survey.UnreadableFolders[0]));
                ReferenceTreeCopier.Copy(survey, course.DirectoryPath, staging, progress, stop);
                FinishTheCopy(staging);
                var staged = MakeIntoAReferenceCourse(staging, schoolYear);
                Directory.Move(staging, destination);
                var made = staged with { FolderName = folderName };
                ActivityTrail.Note(ActivityTrail.Event.CourseKeptForReference, TrailLine(made, ReferenceCourse.ShownCode(course), addOns));
                return made;
            }
            catch
            {
                ReferenceStaging.Remove(staging);   // only the claimer removes, and this is the claimer
                throw;
            }
        }
        finally
        {
            ReferenceStaging.GiveBack(coursesDirectory, folderName);
        }
    }

    /// <summary>
    /// What happens to a fresh copy before anything else: clear any lock or
    /// read-only bit that came with it (a stream copy carries neither today —
    /// this is the guard for the day a copy routine does), and remove the
    /// leases, which name processes on whichever machine wrote them.
    /// </summary>
    public static void FinishTheCopy(string staging)
    {
        ReferenceLock.Clear(staging);
        string leases = Path.Combine(staging, ".internal", "activity");
        try { if (Directory.Exists(leases)) Directory.Delete(leases, recursive: true); } catch { }
    }

    /// <summary>
    /// Turns the copy at <paramref name="folder"/> into a reference course, in
    /// the order that keeps every step possible: release the site markers,
    /// write the settings (marker, year, neutralisation) in one save, LOCK
    /// LAST, then reading view (into <c>.obsidian</c>, which is never locked).
    /// </summary>
    public static Made MakeIntoAReferenceCourse(string folder, int? schoolYear)
    {
        string configPath = Path.Combine(folder, "course_config.json");
        var configuration = CourseConfiguration.Load(configPath);
        ReleaseSiteMarkers(folder);
        configuration.MarkKeptForReference(schoolYear);
        configuration.Write(configPath);

        var copy = new Course(Path.GetFileName(folder), folder, configuration);
        var locked = ReferenceLock.Lock(folder);
        string shown = ReferenceCourse.ShownCode(copy);
        if (locked.DidNotTake > 0 || !locked.EverythingThatShouldBeLockedIs)
            ActivityTrail.Note(ActivityTrail.Event.ReferenceCoursePagesLockedAgain,
                $"made {shown} for reference and {locked.LockedOnDisk} of {locked.ShouldBeLocked} of its files are locked");
        MakeReadingViewTheDefault(folder);
        return new Made(Path.GetFileName(folder), shown, schoolYear, copy.SectionNumbers.Count);
    }

    private static readonly Regex SectionMarker = new(@"^section\d+\.json$", RegexOptions.CultureInvariant);

    /// <summary>
    /// Renames every section's first-deploy marker aside, under the frozen
    /// previous-marker name (<c>file-formats.json → firstDeployMarkers</c>), so
    /// a deploy that somehow ran would make a NEW site rather than overwrite
    /// last year's live one. Renamed, not deleted: it holds the site id and
    /// the admin address a teacher may still want. Every section's marker,
    /// listed or not.
    /// </summary>
    public static void ReleaseSiteMarkers(string folder)
    {
        string stamp = DateText.Invariant(DateTime.Now, "yyyy-MM-dd_HHmmss");
        foreach (string markers in new[] { ".netlify_sites", ".cloudflare_sites" })
        {
            string directory = Path.Combine(folder, markers);
            if (!Directory.Exists(directory)) continue;
            foreach (string marker in Directory.GetFiles(directory).Where(f => SectionMarker.IsMatch(Path.GetFileName(f))))
            {
                int section = int.Parse(Path.GetFileName(marker)["section".Length..^".json".Length]);
                File.Move(marker, Path.Combine(directory, AssistWorkspace.ReleasedMarkerName(section, stamp)));
            }
        }
    }

    public const string ReadingViewKey = "defaultViewMode";
    public const string ReadingView = "preview";

    /// <summary>
    /// Makes Obsidian's reading view the vault's default
    /// (<c>defaultViewMode: "preview"</c> in <c>.obsidian/app.json</c>, every
    /// other key kept), so pages open rendered rather than ready to edit.
    /// Best effort: a settings file that cannot be read is left alone, and a
    /// <c>.obsidian</c> that is a link is never written through.
    /// </summary>
    public static bool MakeReadingViewTheDefault(string courseFolder)
    {
        try
        {
            string obsidian = Path.Combine(courseFolder, ObsidianAddOns.SettingsFolderName);
            if (Directory.Exists(obsidian) && new DirectoryInfo(obsidian).Attributes.HasFlag(FileAttributes.ReparsePoint)) return false;
            string settings = Path.Combine(obsidian, "app.json");
            JObject values = new();
            if (File.Exists(settings))
            {
                if (JToken.Parse(File.ReadAllText(settings)) is not JObject existing) return false;
                values = existing;
            }
            if ((string?)values[ReadingViewKey] == ReadingView) return true;
            values[ReadingViewKey] = ReadingView;
            Directory.CreateDirectory(obsidian);
            File.WriteAllText(settings + ".tmp", values.ToString(Formatting.Indented));
            File.Move(settings + ".tmp", settings, overwrite: true);
            return true;
        }
        catch { return false; }
    }

    /// <summary><c>kept a copy of ICS3U for reference as ICS3U-2025 — shown as ICS3U, 2025–26, 2 sections</c>.</summary>
    public static string TrailLine(Made made, string copiedFrom, ObsidianAddOns.Found addOns) =>
        $"kept a copy of {copiedFrom} for reference as {made.FolderName} — shown as {made.ShownCode}, " +
        $"{SchoolYear.Name(made.SchoolYear)}, {(made.SectionCount == 1 ? "1 section" : $"{made.SectionCount} sections")}" +
        ObsidianAddOns.TrailClause(addOns);
}

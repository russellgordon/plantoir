using Newtonsoft.Json.Linq;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// Import Courses for Reference… (#244, mac #206 branch B; #245's claim and
/// #287's trail; <c>shared-rules.json → referenceCourses.importing</c>): the
/// teacher points at last year's working folder, ticks courses, gives each a
/// school year, and each comes in as an ordinary reference course — the same
/// making as Keep a Copy, from a different source.
///
/// <para><b>The chosen folder is never written.</b> Every source file is opened
/// for reading only, by <see cref="ReferenceTreeCopier"/>; the marker, the
/// neutralisation, the released site markers and the lock all happen to the
/// COPY, in staging, after it is made. Proved by a manifest of every entry —
/// path, size, last write, SHA-256, attributes and access rules — before and
/// after (<c>ReferenceImportSourceIsNeverWrittenTests</c>).</para>
///
/// <para>Only the MODERN layout is read here. The older folder-per-class
/// layout (#254) and the 2024–25 website-folder layout (#256, #258) are the
/// mac's alone by Russell's decisions; their sentences are not said here and
/// are skipped by name in the wording test, never ledgered.</para>
/// </summary>
public static class ReferenceImport
{
    // ---- The sentences: importing.wording (the modern route's keys) ---------

    /// <summary>The templates of <c>referenceCourses.importing.wording</c> this app says, by key.</summary>
    public static readonly IReadOnlyDictionary<string, string> Wording = new Dictionary<string, string>
    {
        ["menuItem"] = "Import Courses for Reference…",
        ["title"] = "Import courses for reference",
        ["explanation"] = "Plantoir copies the courses you tick into this working folder and keeps them for reference. The folder you choose is left exactly as it is.",
        ["noCoursesThere"] = "There are no courses in {folder}. Choose the folder you kept that year's classes in.",
        ["thatIsTheFolderYouHaveOpen"] = "That is the folder you already have open. To keep one of these courses for reference, use Keep a Copy for Reference… on the course itself.",
        ["insideTheFolderYouHaveOpen"] = "{folder} is inside the folder you already have open. Choose a folder somewhere else.",
        ["holdsTheFolderYouHaveOpen"] = "{folder} holds the folder you already have open. Choose a folder somewhere else.",
        ["courseSummary"] = "{sections} · {pages} · {size}",
        ["schoolYearLabel"] = "School year",
        ["settingsCouldNotBeRead"] = "Its settings could not be read, so it can’t be brought across.",
        ["couldNotReadFolder"] = "{folder} could not be read, so this course was left as it is.",
        ["builtWebsitesAreNotCopied"] = "Last year's built websites are not copied. Preview a course and Plantoir builds it again.",
        ["importButton"] = "Import",
        ["tickSomething"] = "Tick the courses you want to keep for reference.",
        ["copying"] = "Copying {course}…",
        ["copiedSoFar"] = "{copied} of {total}",
        ["doneTitle"] = "Imported",
        ["whereTheyAre"] = "They are in the sidebar under Reference Courses, filed by school year.",
        ["imported"] = "{course} — {year}, {sections}",
        ["couldNotImport"] = "{course} was not imported. {reason}",
        ["noSchoolYear"] = "no school year",
        ["stopped"] = "Stopped. The courses already imported are in the sidebar; the one in progress was not kept.",
        ["alreadyBeingImported"] = "It is already being imported in another window, or in another copy of Plantoir.",
        ["leftoverInTheWay"] = "Something left behind by an earlier attempt that did not finish could not be cleared away.",
        ["alsoTickedForThatYear"] = "{folder} is also ticked for that school year, and one {course} is kept for each year. Choose Other or a different school year for one of them.",
        ["addOnsAreLeftBehind"] = "Obsidian add-ons and their settings are not brought across, so nothing in them can publish these pages.",
    };

    /// <summary>
    /// Keys of <c>importing.wording</c> this app deliberately does not say:
    /// the two older layouts are the mac's alone (#254; #256/#258, Russell
    /// 2026-09-25), and two keys are the block's own notes rather than sentences.
    /// </summary>
    public static bool IsNotSaidHere(string key) =>
        key.StartsWith("olderLayout", StringComparison.Ordinal) || key.StartsWith("checkoutLayout", StringComparison.Ordinal)
        || key is "rule" or "machineryCheck";

    private static string Say(string key, params (string Name, string Value)[] fills) =>
        fills.Aggregate(Wording[key], (text, fill) => text.Replace("{" + fill.Name + "}", fill.Value));

    public static string MenuItem => Wording["menuItem"];
    public static string Title => Wording["title"];
    public static string Explanation => Wording["explanation"];
    public static string NoCoursesThere(string folder) => Say("noCoursesThere", ("folder", folder));
    public static string ThatIsTheFolderYouHaveOpen => Wording["thatIsTheFolderYouHaveOpen"];
    public static string InsideTheFolderYouHaveOpen(string folder) => Say("insideTheFolderYouHaveOpen", ("folder", folder));
    public static string HoldsTheFolderYouHaveOpen(string folder) => Say("holdsTheFolderYouHaveOpen", ("folder", folder));
    public static string CourseSummary(int sections, int pages, long bytes) =>
        Say("courseSummary", ("sections", sections == 1 ? "1 section" : $"{sections} sections"),
            ("pages", pages == 1 ? "1 page" : $"{pages} pages"), ("size", Size(bytes)));
    public static string SchoolYearLabel => Wording["schoolYearLabel"];
    public static string SettingsCouldNotBeRead => Wording["settingsCouldNotBeRead"];
    public static string CouldNotReadFolder(string folder) => Say("couldNotReadFolder", ("folder", folder));
    public static string BuiltWebsitesAreNotCopied => Wording["builtWebsitesAreNotCopied"];
    public static string ImportButton => Wording["importButton"];
    public static string TickSomething => Wording["tickSomething"];
    public static string Copying(string course) => Say("copying", ("course", course));
    public static string CopiedSoFar(long copied, long total) => Say("copiedSoFar", ("copied", Size(copied)), ("total", Size(total)));
    public static string DoneTitle => Wording["doneTitle"];
    public static string WhereTheyAre => Wording["whereTheyAre"];
    public static string Imported(string course, int? year, int sections) =>
        Say("imported", ("course", course), ("year", SchoolYear.Name(year, NoSchoolYear)),
            ("sections", sections == 1 ? "1 section" : $"{sections} sections"));
    public static string CouldNotImport(string course, string reason) => Say("couldNotImport", ("course", course), ("reason", reason));
    public static string NoSchoolYear => Wording["noSchoolYear"];
    public static string Stopped => Wording["stopped"];
    public static string AlreadyBeingImported => Wording["alreadyBeingImported"];
    public static string LeftoverInTheWay => Wording["leftoverInTheWay"];
    public static string AlsoTickedForThatYear(string folder, string course) => Say("alsoTickedForThatYear", ("folder", folder), ("course", course));
    public static string AddOnsAreLeftBehind => Wording["addOnsAreLeftBehind"];

    /// <summary>
    /// A size as a teacher reads it, in decimal units the way Explorer's own
    /// copy dialog does: "312 KB", "489 MB", "1.36 GB". Not contract data.
    /// </summary>
    public static string Size(long bytes)
    {
        var culture = System.Globalization.CultureInfo.InvariantCulture;
        if (bytes < 1000) return bytes == 1 ? "1 byte" : $"{bytes} bytes";
        if (bytes < 1_000_000) return $"{Math.Round(bytes / 1e3).ToString(culture)} KB";
        if (bytes < 10_000_000) return $"{(bytes / 1e6).ToString("0.#", culture)} MB";
        if (bytes < 1_000_000_000) return $"{Math.Round(bytes / 1e6).ToString(culture)} MB";
        return $"{(bytes / 1e9).ToString("0.##", culture)} GB";
    }

    // ---- What is left behind: importing.leftBehind ----------------------------

    /// <summary>What only an import meets: a Finder duplicate of the settings, and what an external disk picks up.</summary>
    public static readonly IReadOnlyList<string> AlsoLeftBehindOnImport =
        new[] { "course_config copy.json", ".Trashes", ".Spotlight-V100", ".fseventsd" };

    /// <summary>
    /// Composed rather than written out again: what an archive leaves behind,
    /// plus what a reference copy leaves behind, plus what only an import
    /// meets. Skipped WITHOUT being looked inside, at any depth.
    /// </summary>
    public static IReadOnlySet<string> LeftBehindNames =>
        ReferenceCopier.LeftBehindNames.Concat(AlsoLeftBehindOnImport).ToHashSet(StringComparer.Ordinal);

    // ---- The school year proposed: importing.schoolYearProposed ---------------

    /// <summary>
    /// The school year most of the pages were last changed in, ties going to
    /// the NEWER year; a year outside the offered list proposes nothing.
    /// </summary>
    public static int? SuggestedSchoolYear(IEnumerable<int> pageYears, DateOnly day)
    {
        var commonest = pageYears.GroupBy(year => year)
            .OrderByDescending(group => group.Count()).ThenByDescending(group => group.Key)
            .Select(group => (int?)group.Key).FirstOrDefault();
        return commonest is int year ? SchoolYear.Read(new JValue(year), day) : null;
    }

    // ---- The folder chosen: importing.foldersAccepted -------------------------

    /// <summary>One course found in the chosen folder, measured with last year's website already taken out.</summary>
    public sealed record FoundCourse(
        string FolderName, string CourseCode, string CourseName, IReadOnlyList<int> SectionNumbers,
        int PageCount, int FileCount, long ByteCount, string? Problem, int? SuggestedSchoolYear,
        string DirectoryPath, ObsidianAddOns.Found AddOns);

    /// <summary>What the chosen folder turned out to hold.</summary>
    public sealed record Source(string RootPath, string CoursesPath, IReadOnlyList<FoundCourse> Courses, string? ChosenCourseFolderName)
    {
        /// <summary>
        /// Everything (with no problem) when a working folder or a courses
        /// folder was chosen; only the one course when a course folder was.
        /// </summary>
        public IReadOnlySet<string> TickedWhenOpened =>
            ChosenCourseFolderName is { } chosen
                ? Courses.Where(c => c.FolderName == chosen && c.Problem is null).Select(c => c.FolderName).ToHashSet()
                : Courses.Where(c => c.Problem is null).Select(c => c.FolderName).ToHashSet();
    }

    public const string ConfigFileName = "course_config.json";

    /// <summary>
    /// Reads the chosen folder: the folder itself (it holds <c>courses</c>), the
    /// courses folder, or ONE course folder — resolved upward when that course
    /// sits in a courses folder, on its own when it does not. Refused, with a
    /// sentence, when it is the open working folder, inside it, or holds it, or
    /// when it holds no course. Reads names and sizes only; never writes.
    /// </summary>
    public static (Source? Found, string? Refusal) Resolve(string chosen, string? workingFolder, DateOnly day)
    {
        string chosenPath = Path.TrimEndingDirectorySeparator(Path.GetFullPath(chosen));
        string chosenName = Path.GetFileName(chosenPath);
        if (workingFolder is not null)
        {
            string here = WithSlash(workingFolder), there = WithSlash(chosenPath);
            if (string.Equals(here, there, StringComparison.OrdinalIgnoreCase)) return (null, ThatIsTheFolderYouHaveOpen);
            if (there.StartsWith(here, StringComparison.OrdinalIgnoreCase)) return (null, InsideTheFolderYouHaveOpen(chosenName));
            if (here.StartsWith(there, StringComparison.OrdinalIgnoreCase)) return (null, HoldsTheFolderYouHaveOpen(chosenName));
        }

        string? coursesPath = null;
        string? chosenCourse = null;
        bool loneCourse = false;
        if (Directory.Exists(Path.Combine(chosenPath, "courses"))) coursesPath = Path.Combine(chosenPath, "courses");
        else if (chosenName == "courses" && Directory.Exists(chosenPath)) coursesPath = chosenPath;
        else if (File.Exists(Path.Combine(chosenPath, ConfigFileName)))
        {
            string parent = Path.GetDirectoryName(chosenPath)!;
            coursesPath = parent;
            chosenCourse = chosenName;
            loneCourse = Path.GetFileName(parent) != "courses";
        }
        if (coursesPath is null) return (null, NoCoursesThere(chosenName));

        var courses = loneCourse
            ? new[] { Measure(chosenPath, day) }.ToList()
            : CoursesIn(coursesPath, day);
        if (courses.Count == 0) return (null, NoCoursesThere(chosenName));
        string root = loneCourse ? chosenPath : Path.GetDirectoryName(coursesPath)!;
        return (new Source(root, coursesPath, courses, chosenCourse), null);
    }

    private static string WithSlash(string path)
    {
        string physical = FolderContainers.PhysicalPath(path);
        return physical.EndsWith('\\') ? physical : physical + "\\";
    }

    /// <summary>A course is a folder inside courses/ holding a course_config.json — nothing else is.</summary>
    public static List<FoundCourse> CoursesIn(string coursesPath, DateOnly day)
    {
        List<DirectoryInfo> children;
        try { children = new DirectoryInfo(coursesPath).EnumerateDirectories("*", ReferenceLock.Unfiltered).ToList(); }
        catch { return new List<FoundCourse>(); }
        return children
            .Where(child => !child.Attributes.HasFlag(FileAttributes.ReparsePoint)
                            && File.Exists(Path.Combine(child.FullName, ConfigFileName)))
            .Select(child => Measure(child.FullName, day))
            .OrderBy(c => c.CourseCode, StringComparer.Ordinal).ThenBy(c => c.FolderName, StringComparer.Ordinal)
            .ToList();
    }

    /// <summary>
    /// One course's code, name, sections, and what will be COPIED — pages,
    /// files and bytes with last year's built website and the add-ons already
    /// out — plus the year its pages propose.
    /// </summary>
    public static FoundCourse Measure(string courseDirectory, DateOnly day)
    {
        string folderName = Path.GetFileName(courseDirectory);
        CourseConfiguration configuration;
        try { configuration = CourseConfiguration.Load(Path.Combine(courseDirectory, ConfigFileName)); }
        catch
        {
            return new FoundCourse(folderName, folderName, "", Array.Empty<int>(), 0, 0, 0, SettingsCouldNotBeRead, null,
                courseDirectory, ObsidianAddOns.Found.None);
        }
        string code = configuration.CourseCode.Trim();
        if (code.Length == 0) code = folderName;
        var survey = ReferenceTreeCopier.Walk(courseDirectory, LeftBehindNames, ObsidianAddOns.LeftBehindFromTheCourse);
        var pages = survey.Entries.Where(e => !e.IsFolder && e.Relative.EndsWith(".md", StringComparison.OrdinalIgnoreCase)).ToList();
        var pageYears = pages.Select(page => SchoolYear.StartingYear(DateOnly.FromDateTime(page.LastWriteUtc.ToLocalTime())));
        return new FoundCourse(folderName, code, configuration.CourseName, configuration.SectionNumbers,
            pages.Count, survey.Files, survey.Bytes,
            survey.UnreadableFolders.Count > 0 ? CouldNotReadFolder(survey.UnreadableFolders[0]) : null,
            SuggestedSchoolYear(pageYears, day), courseDirectory, ObsidianAddOns.FoundIn(courseDirectory));
    }

    // ---- Importing ---------------------------------------------------------------

    /// <summary>One ticked course and the year it goes under.</summary>
    public sealed record Request(FoundCourse Course, int? SchoolYear);

    /// <summary>What became of one course. Exactly one of the three.</summary>
    public sealed record Outcome(string Course, ReferenceCopier.Made? Made, string? NotImportedBecause, bool WasStopped);

    /// <summary>How far a run has got: the course in hand, which of how many, and BYTES.</summary>
    public readonly record struct Progress(string Course, int CourseNumber, int CourseCount, long Copied, long Total);

    /// <summary>
    /// Imports each request on its own, in order. One that cannot be — the
    /// shelf rule, a folder already there, being made elsewhere, a leftover in
    /// the way, a copy that failed — is reported with its sentence and the run
    /// carries on; ONLY Stop ends it early. Every course listed as not
    /// imported leaves its trail line through <see cref="NotImported"/>, the
    /// one way to give up on a course, BEFORE leaving it (#287). Whatever was
    /// half-made is unlocked, then removed — only by its claimer. Run OFF the
    /// UI thread.
    /// </summary>
    public static List<Outcome> ImportCourses(IReadOnlyList<Request> requests, string coursesDirectory,
        IEnumerable<string> existingFolderNames, IEnumerable<ReferenceCourse.Shelved> alreadyShelved,
        string sourceFolderName, IProgress<Progress>? progress, CancellationToken stop)
    {
        var folderNames = existingFolderNames.ToList();
        var shelf = alreadyShelved.ToList();
        var outcomes = new List<Outcome>();
        for (int index = 0; index < requests.Count; index++)
        {
            var request = requests[index];
            string shown = CourseCodeValidator.Normalize(request.Course.CourseCode);

            Outcome NotImported(string reason)
            {
                ActivityTrail.Note(ActivityTrail.Event.CourseCouldNotBeImportedForReference,
                    $"could not import {shown} for reference from {sourceFolderName} — {reason}");
                return new Outcome(shown, null, reason, false);
            }

            if (stop.IsCancellationRequested) break;
            if (request.Course.Problem is { } problem) { outcomes.Add(NotImported(problem)); continue; }
            if (ReferenceCourse.ShelfTrouble(shown, request.SchoolYear, shelf) is { } trouble) { outcomes.Add(NotImported(trouble)); continue; }

            string folderName = ReferenceCourse.ProposedFolderName(shown, request.SchoolYear, folderNames);
            string destination = Path.Combine(coursesDirectory, folderName);
            if (Directory.Exists(destination) || File.Exists(destination))
            {
                outcomes.Add(NotImported(ReferenceCourse.FolderAlreadyThere(folderName)));
                continue;
            }
            var claim = ReferenceStaging.TryClaim(coursesDirectory, folderName, AlreadyBeingImported);
            if (claim.Outcome != ReferenceStaging.Outcome.Claimed) { outcomes.Add(NotImported(claim.Reason ?? "")); continue; }

            string staging = Path.Combine(coursesDirectory, ReferenceStaging.StagingName(folderName));
            try
            {
                var clock = System.Diagnostics.Stopwatch.StartNew();
                var (made, bytes) = ImportOne(request, folderName, staging, destination, index + 1, requests.Count, progress, stop);
                ActivityTrail.Note(ActivityTrail.Event.CourseImportedForReference,
                    TrailLine(made, sourceFolderName, request.Course.AddOns)
                    + $" ({Size(bytes)} in {clock.Elapsed.TotalSeconds.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture)} s)");
                outcomes.Add(new Outcome(shown, made, null, false));
                folderNames.Add(folderName);
                shelf.Add(new ReferenceCourse.Shelved(made.ShownCode, made.SchoolYear, made.FolderName));
            }
            catch (OperationCanceledException)
            {
                ReferenceStaging.Remove(staging);
                ActivityTrail.Note(ActivityTrail.Event.CourseImportForReferenceStopped,
                    $"stopped importing {shown} for reference from {sourceFolderName} — nothing was kept for that course");
                outcomes.Add(new Outcome(shown, null, null, true));
                return outcomes;
            }
            catch (Exception failure)
            {
                ReferenceStaging.Remove(staging);
                outcomes.Add(NotImported(failure is ReferenceCopier.NotMade ? failure.Message : ReferenceCourse.CopyCouldNotBeMade(failure.Message)));
            }
            finally
            {
                ReferenceStaging.GiveBack(coursesDirectory, folderName);
            }
        }
        return outcomes;
    }

    /// <summary>
    /// The order, per course: copy into staging (by stream, never writing the
    /// source) → CLEAR any lock or read-only bit → remove copied leases →
    /// release the site markers aside → write the settings → lock LAST →
    /// reading view → rename into place, atomic within <c>courses/</c>.
    /// </summary>
    private static (ReferenceCopier.Made Made, long Bytes) ImportOne(Request request, string folderName, string staging, string destination,
        int courseNumber, int courseCount, IProgress<Progress>? progress, CancellationToken stop)
    {
        string shown = CourseCodeValidator.Normalize(request.Course.CourseCode);
        var survey = ReferenceTreeCopier.Walk(request.Course.DirectoryPath, LeftBehindNames, ObsidianAddOns.LeftBehindFromTheCourse);
        if (survey.UnreadableFolders.Count > 0) throw new ReferenceCopier.NotMade(CouldNotReadFolder(survey.UnreadableFolders[0]));
        progress?.Report(new Progress(shown, courseNumber, courseCount, 0, survey.Bytes));
        var bytes = progress is null ? null
            : new Relay<ReferenceTreeCopier.Progress>(p => progress.Report(new Progress(shown, courseNumber, courseCount, p.Copied, p.Total)));
        ReferenceTreeCopier.Copy(survey, request.Course.DirectoryPath, staging, bytes, stop);
        stop.ThrowIfCancellationRequested();
        ReferenceCopier.FinishTheCopy(staging);
        var staged = ReferenceCopier.MakeIntoAReferenceCourse(staging, request.SchoolYear);
        Directory.Move(staging, destination);
        return (staged with { FolderName = folderName }, survey.Bytes);
    }

    /// <summary>A synchronous IProgress — the caller's own marshals to the window.</summary>
    private sealed class Relay<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }

    /// <summary>
    /// <c>imported ICS4U for reference from ICS 2025 as ICS4U-2025 — 2025–26, 2 sections</c>;
    /// the caller adds the size and the time it took, so real-world copy speeds
    /// come back in problem reports (NTFS has no clone: this is a real copy).
    /// </summary>
    public static string TrailLine(ReferenceCopier.Made made, string sourceFolderName, ObsidianAddOns.Found addOns) =>
        $"imported {made.ShownCode} for reference from {sourceFolderName} as {made.FolderName} — " +
        $"{SchoolYear.Name(made.SchoolYear, NoSchoolYear)}, {(made.SectionCount == 1 ? "1 section" : $"{made.SectionCount} sections")}" +
        ObsidianAddOns.TrailClause(addOns);
}

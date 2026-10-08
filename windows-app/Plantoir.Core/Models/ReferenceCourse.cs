namespace Plantoir.Core.Models;

/// <summary>
/// A course KEPT FOR REFERENCE (#241, mac #206): last year's course — or one
/// full of example content — kept in this year's sidebar to be read, and never
/// deployed. The whole rule is <c>contracts/shared-rules.json → referenceCourses</c>;
/// this class is its pure half — identity, the shelf rule, the folder name, and
/// the sentences. The lock is <see cref="ReferenceLock"/>, the copy
/// <see cref="ReferenceCopier"/>.
///
/// <para><b>The refusal never depends on the lock.</b> Every door that would
/// START a deploy asks <see cref="IsKeptForReference(Course)"/> — the marker in
/// the settings — and nothing else. An unlocked reference course (restored
/// from a backup, or carried from another computer) is refused just the same.</para>
/// </summary>
public static class ReferenceCourse
{
    // ---- Identity -------------------------------------------------------

    /// <summary>Whether this course is kept for reference: the MARKER, read strictly.</summary>
    public static bool IsKeptForReference(Course course) => course.Configuration.KeptForReference;

    /// <summary>
    /// The code a teacher reads when the course at <paramref name="courseDirectory"/>
    /// is kept for reference AS SAVED NOW, else null. What a deploy door asks
    /// at the press: the window's copy may be older than a marker written by
    /// hand or by another window. A settings file that cannot be read reads as
    /// ordinary here — the launcher's own "cannot tell" refusal is the backstop.
    /// </summary>
    public static string? KeptOnDisk(string courseDirectory)
    {
        try
        {
            var configuration = CourseConfiguration.Load(Path.Combine(courseDirectory, "course_config.json"));
            var course = new Course(Path.GetFileName(courseDirectory), courseDirectory, configuration);
            return IsKeptForReference(course) ? ShownCode(course) : null;
        }
        catch { return null; }
    }

    /// <summary>A deploy refused at a door because the course is kept for reference; its message is the contract's sentence.</summary>
    public sealed class Refused(string shownCode) : InvalidOperationException(RefusalSentence(shownCode));

    /// <summary>
    /// The code a TEACHER reads. For a reference course that is
    /// <c>course_code</c> (ICS3U) while its folder is ICS3U-2025 — the folder is
    /// identity, the code is what is shown (<c>referenceCourses.identity</c>).
    /// Every other course shows its folder name, exactly as before.
    /// </summary>
    public static string ShownCode(Course course)
    {
        if (!course.Configuration.KeptForReference) return course.Code;
        string code = CourseCodeValidator.Normalize(course.Configuration.CourseCode);
        return code.Length > 0 ? code : course.Code;
    }

    /// <summary>
    /// How a reference course is named wherever a sheet, a summary or a trail
    /// line has to tell it from the live one of the same code: "ICS4U · 2025–26".
    /// A live course is named by its code alone.
    /// </summary>
    public static string NameWithYear(Course course, DateOnly today)
    {
        if (!course.Configuration.KeptForReference) return course.Code;
        int? year = SchoolYear.Read(course.Configuration.StoredReferenceSchoolYear, today);
        return $"{ShownCode(course)} · {SchoolYear.Name(year, NoSchoolYear)}";
    }

    // ---- The shelf rule: codeUniqueWithinAGroup ---------------------------

    /// <summary>One course on the shelf, as the uniqueness rule sees it.</summary>
    public sealed record Shelved(string ShownCode, int? SchoolYear, string FolderName);

    /// <summary>The shelf as it stands: every reference course, with the year it reads as today.</summary>
    public static List<Shelved> Shelf(IEnumerable<Course> courses, DateOnly today) =>
        courses.Where(IsKeptForReference)
            .Select(course => new Shelved(ShownCode(course),
                SchoolYear.Read(course.Configuration.StoredReferenceSchoolYear, today), course.Code))
            .ToList();

    /// <summary>
    /// The sentence refusing <paramref name="code"/> in <paramref name="schoolYear"/>
    /// when the shelf already holds that code in that group — "Other"
    /// included — or null. Courses being TAUGHT are never consulted.
    /// <paramref name="ignoringFolder"/> is the course being re-filed, so it
    /// does not find itself where it is moving from.
    /// </summary>
    public static string? ShelfTrouble(string code, int? schoolYear, IEnumerable<Shelved> shelf, string? ignoringFolder = null)
    {
        string wanted = CourseCodeValidator.Normalize(code);
        if (wanted.Length == 0) return null;
        bool clash = shelf.Any(existing =>
            !(ignoringFolder is not null && string.Equals(existing.FolderName, ignoringFolder, StringComparison.OrdinalIgnoreCase))
            && existing.SchoolYear == schoolYear
            && CourseCodeValidator.Normalize(existing.ShownCode) == wanted);
        if (!clash) return null;
        return schoolYear is int year
            ? CodeAlreadyInThatYear(wanted, SchoolYear.Label(year))
            : CodeAlreadyWithNoYear(wanted);
    }

    // ---- The folder name: importing.folderNameProduced --------------------

    /// <summary>
    /// CODE-YYYY in upper case, or CODE-REF with no school year, with -2 to -9
    /// tried in turn when the name is taken. Upper case always: the launchers
    /// upper-case their course argument, so a lower-case folder is not found.
    /// The code is shortened, never the suffix, to stay within twelve.
    /// </summary>
    public static string ProposedFolderName(string code, int? schoolYear, IEnumerable<string> existingFolderNames)
    {
        string baseCode = CourseCodeValidator.Normalize(code);
        var existing = existingFolderNames.ToList();
        var suffixes = schoolYear is int year
            ? new[] { $"-{year}" }.Concat(Enumerable.Range(2, 8).Select(n => $"-{year}-{n}")).ToList()
            : new[] { "-REF" }.Concat(Enumerable.Range(2, 8).Select(n => $"-REF{n}")).ToList();
        foreach (string suffix in suffixes)
        {
            string candidate = Fitting(baseCode, suffix);
            if (CourseCodeValidator.Problem(candidate, existing) is null) return candidate;
        }
        // Nine tries all taken is not a state a teacher reaches by accident;
        // the sheet validates the field and says what is wrong.
        return Fitting(baseCode, suffixes[0]);
    }

    private static string Fitting(string baseCode, string suffix)
    {
        int room = CourseCodeValidator.MostCharacters - suffix.Length;
        if (room < 1) return CourseCodeValidator.Normalize(suffix[1..]);
        string shortened = baseCode.Length > room ? baseCode[..room] : baseCode;
        return CourseCodeValidator.Normalize(shortened + suffix);
    }

    // ---- The sentences: referenceCourses.wording and .refusal.sentence ----
    // Each is the contract's own sentence; ReferenceCourseTests compares every
    // key with the contract, so a sentence changed there fails here.

    public const string RefusalSentenceTemplate =
        "{course} is kept for reference, so it is never deployed. Deploy the course you are teaching instead.";

    /// <summary>What every deploy door says, BEFORE anything is stopped, built or uploaded.</summary>
    public static string RefusalSentence(string course) => RefusalSentenceTemplate.Replace("{course}", course);

    /// <summary>The templates of <c>referenceCourses.wording</c>, by key.</summary>
    public static readonly IReadOnlyDictionary<string, string> Wording = new Dictionary<string, string>
    {
        ["staysAsItIs"] = "{course} is kept for reference, so it stays as it is.",
        ["couldNotSetSchoolYear"] = "{course}'s school year could not be saved. Try again in a moment.",
        ["cannotTellHeadline"] = "Plantoir cannot tell whether {course} is kept for reference",
        ["cannotTellBecauseUnreadable"] = "its settings file could not be read",
        ["cannotTellBecauseOddValue"] = "its settings say something other than true or false",
        ["pagesAreLocked"] = "Plantoir keeps this course's pages locked, so they stay as they were.",
        ["obsidianOpensThemForReading"] =
            "Obsidian opens them for reading. If you switch a page to editing and type, Obsidian will say it couldn’t save, and the page stays as it was.",
        ["neverDeployed"] = "{course} is kept for reference. Preview it to read its pages; it is never deployed.",
        ["copyAlreadyBeingMade"] = "A copy called {folder} is already being made in another window, or in another copy of Plantoir.",
        ["copyIsASnapshot"] =
            "This records {course} as it is today. You can keep teaching it as usual — nothing here changes. To take a fresher copy later, delete this one first, then copy again.",
        ["keepACopyLeavesAddOnsBehind"] =
            "The copy is made without {course}'s Obsidian add-ons and their settings, so nothing in them can put it online. {course} keeps them.",
        ["codeAlreadyInThatYear"] = "You already have a {code} kept for reference from {year}. Choose a different school year.",
        ["codeAlreadyWithNoYear"] = "You already have a {code} kept for reference with no school year. Choose a school year for this one.",
        ["groupTitle"] = "Reference Courses",
        ["keepACopyMenuItem"] = "Keep a Copy for Reference…",
        ["setSchoolYearMenuItem"] = "Set School Year…",
    };

    private static string Say(string key, params (string Name, string Value)[] fills) =>
        fills.Aggregate(Wording[key], (text, fill) => text.Replace("{" + fill.Name + "}", fill.Value));

    public static string StaysAsItIs(string course) => Say("staysAsItIs", ("course", course));
    public static string CouldNotSetSchoolYear(string course) => Say("couldNotSetSchoolYear", ("course", course));
    public static string NeverDeployed(string course) => Say("neverDeployed", ("course", course));
    public static string CopyAlreadyBeingMade(string folder) => Say("copyAlreadyBeingMade", ("folder", folder));
    public static string CopyIsASnapshot(string course) => Say("copyIsASnapshot", ("course", course));
    public static string KeepACopyLeavesAddOnsBehind(string course) => Say("keepACopyLeavesAddOnsBehind", ("course", course));
    public static string CodeAlreadyInThatYear(string code, string year) => Say("codeAlreadyInThatYear", ("code", code), ("year", year));
    public static string CodeAlreadyWithNoYear(string code) => Say("codeAlreadyWithNoYear", ("code", code));
    public static string PagesAreLocked => Wording["pagesAreLocked"];
    public static string ObsidianOpensThemForReading => Wording["obsidianOpensThemForReading"];
    public static string GroupTitle => Wording["groupTitle"];
    public static string KeepACopyMenuItem => Wording["keepACopyMenuItem"];
    public static string SetSchoolYearMenuItem => Wording["setSchoolYearMenuItem"];

    /// <summary>
    /// What a screen reader says for a reference course's sidebar row: "ICS3U,
    /// kept for reference, 2025–26", or "ICS3U, kept for reference" with no
    /// year (#426). The row SHOWS only the code, which is faithful but leaves
    /// the reference ICS3U and the live ICS3U announced identically. Windows'
    /// own (no contract key): the mac's VoiceOver reads SwiftUI rows by their
    /// labels, and #426 records no mac obligation.
    /// </summary>
    public static string SpokenRowName(string shownCode, int? schoolYear) =>
        schoolYear is int year
            ? $"{shownCode}, kept for reference, {SchoolYear.Label(year)}"
            : $"{shownCode}, kept for reference";

    /// <summary><c>referenceCourses.importing.wording.noSchoolYear</c> — how a year that is not set reads in a sentence.</summary>
    public const string NoSchoolYear = "no school year";

    /// <summary>
    /// This app's own sentence for a Keep a Copy name already on disk (the
    /// mac's <c>ReferenceCopier.Problem.folderAlreadyExists</c>, which is not
    /// contract data).
    /// </summary>
    public static string FolderAlreadyThere(string folder) =>
        $"There is already a course folder called {folder}. Choose a different name.";

    /// <summary>This app's own sentence for a copy that failed part way, carrying the system's reason.</summary>
    public static string CopyCouldNotBeMade(string reason) => $"The copy could not be made: {reason}";
}

using System.Globalization;
using System.Text.Json;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Models;

/// <summary>
/// Renaming a course's word for a unit — "Unit" to "Module", say — AFTER the
/// course is in use (#158, the mac's half of #100). The mac's
/// <c>UnitWordRenamer</c>, step for step; the rules are
/// <c>class-planning.json → renamingTheUnitWord</c> and the sentences
/// <c>shared-rules.json → specialNames.renameUnitWord</c>
/// (<see cref="UnitWordRenameWording"/>).
/// </summary>
/// <remarks>
/// <para><b>The order is the contract's</b> (<c>renamingTheUnitWord.order</c>):
/// read every planned page — one that cannot be read refuses everything;
/// back up the whole course; write the record under
/// <c>courses/.internal/renames/&lt;CODE&gt;.unit-word.json</c>; retitle each
/// page in place then MOVE it (never copy-then-delete: interrupted between
/// the two, the plan's own collision rule would refuse the re-run meant to
/// finish it); rewrite links across every page of the course with a map that
/// also carries the old names of pages a stopped rename already moved; write
/// <c>unit_word</c>; clear the record. Disk first, configuration last.</para>
/// <para><b>The trap the issue names:</b> never enumerate through the class
/// page list mid-rename — it parses with the CONFIGURED word, still the old
/// one, and cannot see pages already moved. The raw files in the class
/// folders are read and parsed with each word in turn.</para>
/// <para>Everything here works from <see cref="UnitWordRenameCourseFacts"/>,
/// five facts copied out of the course, so the walks can run OFF the UI
/// thread; only the backup, the settings write and the trail line need the
/// course itself.</para>
/// </remarks>
public static class UnitWordRenamer
{
    /// <summary>
    /// Why the typed word cannot be used, or null. Only the IDENTICAL word is
    /// "unchanged": a change of capitalisation alone is a real rename. While a
    /// stopped rename is recorded, only its target is accepted.
    /// </summary>
    public static string? Problem(string oldWord, string rawNewWord, string? interruptedTarget = null)
    {
        string newWord = rawNewWord.Trim();
        if (interruptedTarget is not null)
            return newWord == interruptedTarget ? null : UnitWordRenameWording.ProblemMustFinishFirst(interruptedTarget);
        if (newWord.Length == 0) return UnitWordRenameWording.ProblemEmpty;
        if (newWord == oldWord) return UnitWordRenameWording.ProblemUnchanged;
        return ClassPageTerm.Problem(newWord);
    }

    /// <summary>Which pages would move, the link map, and what refuses the whole rename.</summary>
    public static UnitWordRenamePlan Plan(string oldWord, string rawNewWord, UnitWordRenameCourseFacts facts)
    {
        string newWord = ClassPageTerm.Cleaned(rawNewWord);
        var renames = new List<UnitWordPageRename>();
        var linkMap = new Dictionary<string, string>(StringComparer.Ordinal);
        var problems = new List<string>();
        var sections = new SortedSet<int>();

        foreach (var page in ClassFolderPages(facts))
        {
            if (UnitDay.Parse(page.Title, oldWord) is { } numbers)
            {
                string newTitle = numbers.TitleIn(newWord);
                linkMap[page.Title] = newTitle;
                // Finishing an interrupted change of capitalisation: a page
                // already spelled the new way is not moved onto itself.
                if (newTitle == page.Title) continue;
                string toPath = Path.Combine(Path.GetDirectoryName(page.Path)!, newTitle + ".md");
                if (File.Exists(toPath) && !IsTheSameFile(page.Path, toPath))
                    problems.Add(UnitWordRenameWording.ProblemPageInTheWay(facts.Code, page.Section, newTitle));
                renames.Add(new UnitWordPageRename(page.Section, page.Title, newTitle, page.Path, toPath));
                sections.Add(page.Section);
            }
            else if (UnitDay.Parse(page.Title, newWord) is { } moved)
            {
                // Already moved by a rename that stopped: not planned again,
                // but a link to its OLD name still has to follow it.
                linkMap[moved.TitleIn(oldWord)] = page.Title;
            }
        }

        if (problems.Count > 0)
        {
            renames.Clear();
            sections.Clear();
        }
        return new UnitWordRenamePlan(facts.Code, oldWord, newWord, renames, linkMap,
            CountLinks(linkMap, facts), sections.ToList(), problems);
    }

    /// <summary>What the sheet shows before a word is typed: pages, sections, links in the CURRENT word.</summary>
    public static UnitWordSurvey Survey(UnitWordRenameCourseFacts facts)
    {
        var names = new Dictionary<string, string>(StringComparer.Ordinal);
        var sections = new SortedSet<int>();
        int pages = 0;
        foreach (var page in ClassFolderPages(facts))
        {
            if (UnitDay.Parse(page.Title, facts.CurrentWord) is null) continue;
            pages++;
            names[page.Title] = page.Title;
            sections.Add(page.Section);
        }
        return new UnitWordSurvey(pages, sections.ToList(), CountLinks(names, facts));
    }

    /// <summary>Every planned page, read into memory BEFORE anything moves; one that cannot be read refuses everything.</summary>
    public static List<string> ReadEveryPage(UnitWordRenamePlan plan)
    {
        var texts = new List<string>();
        foreach (var rename in plan.Renames)
        {
            try { texts.Add(File.ReadAllText(rename.FromPath)); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                throw new UnitWordRenameProblem(
                    UnitWordRenameWording.ProblemPageUnreadable(plan.CourseCode, rename.Section, rename.From), 0, 0, false);
            }
        }
        return texts;
    }

    /// <summary>
    /// Record, retitle-and-move, relink. The backup has been made by the
    /// caller; the settings are written afterwards by <see cref="Record"/>.
    /// </summary>
    public static UnitWordRenameOutcome CarryOut(UnitWordRenamePlan plan, IReadOnlyList<string> texts,
                                                 UnitWordRenameCourseFacts facts, string backupPath)
    {
        if (plan.Problems.Count > 0)
            throw new UnitWordRenameProblem(plan.Problems[0], 0, 0, false);

        try { RecordRenameStarting(plan.From, plan.To, facts.DirectoryPath); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new UnitWordRenameProblem(UnitWordRenameWording.ProblemRecordNotWritten(error.Message), 0, 0, false);
        }

        int renamed = 0;
        bool changedTheCourse = false;
        for (int index = 0; index < plan.Renames.Count; index++)
        {
            var rename = plan.Renames[index];
            try
            {
                string retitled = PageFrontmatter.SetTitle(texts[index], rename.To);
                if (retitled != texts[index])
                {
                    File.WriteAllText(rename.FromPath, retitled);
                    changedTheCourse = true;
                }
                // A MOVE, atomic on one volume. A change of capitalisation on
                // a case-insensitive volume moves the file onto itself, which
                // File.Move accepts and which renames it.
                File.Move(rename.FromPath, rename.ToPath);
                renamed++;
                changedTheCourse = true;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                throw new UnitWordRenameProblem(
                    UnitWordRenameWording.HalfDone(renamed, plan.Renames.Count, rename.From, error.Message),
                    renamed, 0, changedTheCourse);
            }
        }

        int linksRewritten = 0, pagesNotWritten = 0;
        if (plan.LinkMap.Count > 0)
        {
            foreach (string pagePath in PagePaths.MarkdownPages(facts.DirectoryPath))
            {
                string text;
                try { text = File.ReadAllText(pagePath); }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { continue; }
                int here = WikiLinks.CountLinksTo(plan.LinkMap.Keys, text);
                if (here == 0) continue;
                string updated = WikiLinks.Rewriting(text, plan.LinkMap);
                if (updated == text) continue;
                try
                {
                    File.WriteAllText(pagePath, updated);
                    linksRewritten += here;
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    // Skipped rather than stopping: the pages have moved, and
                    // stopping would leave MORE links broken. Counted and said.
                    pagesNotWritten++;
                }
            }
        }
        return new UnitWordRenameOutcome(renamed, linksRewritten, pagesNotWritten, plan.SectionsTouched, backupPath);
    }

    /// <summary>The whole rename on a course: read, back up, carry out, write <c>unit_word</c>, clear the record.</summary>
    /// <remarks>Records <c>word for a unit renamed</c> (rule 5) for a rename
    /// that finished AND for one that stopped part way or whose settings could
    /// not be written — the two states somebody will be asked to explain. A
    /// refusal before anything was touched records nothing.</remarks>
    public static UnitWordRenameOutcome Rename(UnitWordRenamePlan plan, Course course, string coursesDirectory)
    {
        var texts = ReadEveryPage(plan);
        if (plan.Problems.Count > 0) throw new UnitWordRenameProblem(plan.Problems[0], 0, 0, false);
        string backup = CourseArchiver.BackUpCourse(course, coursesDirectory);
        try
        {
            var outcome = CarryOut(plan, texts, Facts(course), backup);
            Record(plan, course);
            ActivityTrail.Note(ActivityTrail.Event.WordForAUnitRenamed, TrailLine(plan, outcome));
            return outcome;
        }
        catch (UnitWordRenameProblem problem) when (problem.ChangedTheCourse)
        {
            ActivityTrail.Note(ActivityTrail.Event.WordForAUnitRenamed,
                $"{course.Code} · " + StoppedTrailLine(plan, problem) + $"; backup {Path.GetFileName(backup)}");
            throw;
        }
    }

    /// <summary>Configuration last; then the record is cleared.</summary>
    public static void Record(UnitWordRenamePlan plan, Course course)
    {
        try
        {
            // Only unit_word is written, the way a folder rename writes only
            // the keys it carries: a teacher's other unsaved edits in Course
            // Settings stay unsaved rather than being saved behind their back.
            course.Configuration.RecordOnDisk(values => { values["unit_word"] = plan.To; return values; },
                                              course.ConfigFilePath);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new UnitWordRenameProblem(UnitWordRenameWording.SettingsNotWritten(plan.To, error.Message),
                plan.Renames.Count, plan.LinksToRewrite, true);
        }
        ClearRenameRecord(course.DirectoryPath);
    }

    public static UnitWordRenameCourseFacts Facts(Course course) => new(
        course.Code, course.DirectoryPath, course.Configuration.SectionNumbers.ToList(),
        ClassFolderRule.Names(course.Configuration.ClassFolder, course.Configuration.PerSectionFolders).ToList(),
        course.Configuration.UnitWord);

    // ---- The record of a rename under way --------------------------------

    public static string RenameMarkerPath(string courseDirectory)
    {
        string trimmed = courseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string courses = Path.GetDirectoryName(trimmed) ?? trimmed;
        return Path.Combine(courses, ".internal", "renames", Path.GetFileName(trimmed) + ".unit-word.json");
    }

    public static void RecordRenameStarting(string oldWord, string newWord, string courseDirectory)
    {
        string marker = RenameMarkerPath(courseDirectory);
        Directory.CreateDirectory(Path.GetDirectoryName(marker)!);
        File.WriteAllText(marker, JsonSerializer.Serialize(new Dictionary<string, string> { ["from"] = oldWord, ["to"] = newWord },
            new JsonSerializerOptions { WriteIndented = true }));
    }

    public static void ClearRenameRecord(string courseDirectory)
    {
        try { File.Delete(RenameMarkerPath(courseDirectory)); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>
    /// The word a stopped rename was heading for, or null. Believed only when
    /// BOTH the configuration and the disk agree: its <c>from</c> is still the
    /// course's word, and some class page is SPELLED the <c>to</c> way
    /// (parsing under it AND beginning with it, case-sensitively — the parser
    /// ignores case, and "Units 1, Day 1" begins with "Unit"). Otherwise it is
    /// stale and cleared rather than believed.
    /// </summary>
    public static string? InterruptedRenameTarget(UnitWordRenameCourseFacts facts)
    {
        string marker = RenameMarkerPath(facts.DirectoryPath);
        Dictionary<string, string>? note;
        try { note = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(marker)); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return null; }
        if (note is null || !note.TryGetValue("from", out var from) || !note.TryGetValue("to", out var to)) return null;
        if (from != facts.CurrentWord || to.Length == 0 || to == from)
        {
            ClearRenameRecord(facts.DirectoryPath);
            return null;
        }
        bool somethingMoved = ClassFolderPages(facts)
            .Any(page => UnitDay.Parse(page.Title, to) is not null && page.Title.StartsWith(to, StringComparison.Ordinal));
        if (!somethingMoved)
        {
            ClearRenameRecord(facts.DirectoryPath);
            return null;
        }
        return to;
    }

    /// <summary>The trail line for <c>word for a unit renamed</c>: counts and the backup's name, never a page's content.</summary>
    public static string TrailLine(UnitWordRenamePlan plan, UnitWordRenameOutcome outcome) =>
        $"{plan.CourseCode} · renamed the word for a unit from “{plan.From}” to “{plan.To}”: {outcome.PagesRenamed} class " +
        $"{(outcome.PagesRenamed == 1 ? "page" : "pages")} renamed, {outcome.LinksRewritten} " +
        $"{(outcome.LinksRewritten == 1 ? "link" : "links")} updated" +
        (outcome.PagesNotWritten > 0 ? $", {outcome.PagesNotWritten} {(outcome.PagesNotWritten == 1 ? "page" : "pages")} not written" : "") +
        $"; backup {Path.GetFileName(outcome.BackupPath)}";

    /// <summary>The trail line for a rename that stopped part way, or whose settings could not be written.</summary>
    public static string StoppedTrailLine(UnitWordRenamePlan plan, UnitWordRenameProblem problem) =>
        problem.ChangedTheCourse
            ? $"renaming the word for a unit from “{plan.From}” to “{plan.To}” stopped part way: " +
              $"{problem.PagesRenamed} of {plan.Renames.Count} class pages had moved — {problem.Message}"
            : $"did not rename the word for a unit from “{plan.From}” to “{plan.To}” — {problem.Message}";

    // ---- Walking the class folders --------------------------------------

    private sealed record ClassFolderPage(int Section, string Title, string Path);

    /// <summary>The RAW files in every section's class folders — never the class-page list, which parses with the configured word.</summary>
    private static IEnumerable<ClassFolderPage> ClassFolderPages(UnitWordRenameCourseFacts facts)
    {
        foreach (int section in facts.SectionNumbers)
            foreach (string folderName in facts.ClassFolderNames)
            {
                string folder = System.IO.Path.Combine(facts.DirectoryPath, "section" + section.ToString(CultureInfo.InvariantCulture), folderName);
                if (!Directory.Exists(folder)) continue;
                IEnumerable<string> files;
                try { files = Directory.EnumerateFiles(folder, "*.md", SearchOption.AllDirectories).ToList(); }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { continue; }
                foreach (string file in files.OrderBy(f => f, StringComparer.Ordinal))
                {
                    if (System.IO.Path.GetFileName(file).Equals("index.md", StringComparison.OrdinalIgnoreCase)) continue;
                    yield return new ClassFolderPage(section, System.IO.Path.GetFileNameWithoutExtension(file), file);
                }
            }
    }

    private static int CountLinks(IReadOnlyDictionary<string, string> linkMap, UnitWordRenameCourseFacts facts)
    {
        if (linkMap.Count == 0 || !Directory.Exists(facts.DirectoryPath)) return 0;
        int total = 0;
        foreach (string page in PagePaths.MarkdownPages(facts.DirectoryPath))
        {
            try { total += WikiLinks.CountLinksTo(linkMap.Keys, File.ReadAllText(page)); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
        return total;
    }

    /// <summary>
    /// Whether two paths are the same FILE — a change of capitalisation on a
    /// case-insensitive volume — asked of the file system, never of the
    /// spelling, so a case-sensitive folder still sees a genuine clash.
    /// </summary>
    private static bool IsTheSameFile(string first, string second)
    {
        try
        {
            var a = new FileInfo(first);
            var b = new FileInfo(second);
            if (!a.Exists || !b.Exists) return false;
            // The directory listing of the destination's folder names the file
            // by its real spelling; if that spelling is the SOURCE's, the two
            // paths are one file.
            string? real = Directory.EnumerateFiles(b.DirectoryName!, b.Name).FirstOrDefault();
            return real is not null && string.Equals(System.IO.Path.GetFileName(real), a.Name, StringComparison.Ordinal);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
    }
}

/// <summary>Five facts copied out of a course, so the walks can run off the UI thread.</summary>
public sealed record UnitWordRenameCourseFacts(
    string Code, string DirectoryPath, IReadOnlyList<int> SectionNumbers, IReadOnlyList<string> ClassFolderNames, string CurrentWord);

public sealed record UnitWordSurvey(int Pages, IReadOnlyList<int> Sections, int Links);

public sealed record UnitWordPageRename(int Section, string From, string To, string FromPath, string ToPath);

public sealed record UnitWordRenamePlan(
    string CourseCode, string From, string To, IReadOnlyList<UnitWordPageRename> Renames,
    IReadOnlyDictionary<string, string> LinkMap, int LinksToRewrite, IReadOnlyList<int> SectionsTouched,
    IReadOnlyList<string> Problems)
{
    public bool CanProceed => Problems.Count == 0;
}

public sealed record UnitWordRenameOutcome(
    int PagesRenamed, int LinksRewritten, int PagesNotWritten, IReadOnlyList<int> SectionsTouched, string BackupPath);

/// <summary>A rename that did not finish, with how far it got — the sentence is the teacher's.</summary>
public sealed class UnitWordRenameProblem(string sentence, int pagesRenamed, int linksRewritten, bool changedTheCourse)
    : Exception(sentence)
{
    public int PagesRenamed { get; } = pagesRenamed;
    public int LinksRewritten { get; } = linksRewritten;
    public bool ChangedTheCourse { get; } = changedTheCourse;
}

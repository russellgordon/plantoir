using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;
using Plantoir.Core.Models;
using Plantoir.Core.Scripting;
using Plantoir.Core.Undo;

namespace Plantoir.Core.Assist;

/// <summary>
/// Preview offers to show TODAY's class on the section's front page (#406,
/// mac #397; <c>class-planning.json</c> → <c>todaysClassOnTheFrontPage</c>).
/// </summary>
/// <remarks>
/// <para><b>Asked from the Preview BUTTON only.</b> Never from plantoir-mcp,
/// the assistant's preview, a scheduled deploy, a repair's rebuild, Start of
/// the Year or Course Settings: those would block on a question nobody may be
/// watching. This type decides and writes; the section window is the only
/// caller that asks (<c>SectionDetailView.OfferTodaysClass</c>), and a source
/// test pins that no other file calls <see cref="Offer"/>.</para>
///
/// <para><b>Today is the teacher's clock and the page's day as WRITTEN</b> —
/// the first ten characters of its <c>created</c>, never converted
/// (<c>sectionIndexPointer.dateCases.why</c>). Only a class CERTAINLY visible
/// is offered: a <c>publish:</c> this app cannot read is hidden by the build.
/// A front page with no class line is not asked about, although this app's
/// pointer would insert one: where a class belongs on such a page is the
/// teacher's (<c>whenNoClassIsTransclusion</c>).</para>
///
/// <para><b>Rejected</b> (the contract's list): the build detecting it (the
/// answer would come after the preview was built, and the container's clock is
/// not the teacher's); asking inside every preview; following the pointer's own
/// newest-visible target (offers tomorrow's class published early); remembering
/// Not Today for the whole section, or in the app's preferences.</para>
/// </remarks>
public static class TodaysClassOnTheFrontPage
{
    // ---- Wording (todaysClassOnTheFrontPage.wording; pinned by TodaysClassContractTests)

    public static string Question(string @class) => $"Show {@class} on the front page?";
    public static string Because(ClassNoun noun, string shown) =>
        $"Today’s {Noun(noun)} is published, but the front page still shows {shown}.";
    public const string Show = "Show on Front Page";
    /// <summary>The decline: "Not Now" on an offer Plantoir raised by itself (#987; it was "Not Today"). The key keeps its name.</summary>
    public const string NotToday = "Not Now";
    public const string NotChangedTitle = "The Front Page Was Not Changed";
    public static string NoLongerOffered(ClassNoun noun) =>
        $"The front page or today’s {Noun(noun)} changed while you were deciding, so it was left as it is.";
    public static string CouldNotSave(string shown) => $"The front page could not be saved, so it still shows {shown}.";

    private static string Noun(ClassNoun noun) => noun == ClassNoun.Meeting ? "meeting" : "class";

    // ---- The kept-file alert (#899 W7b2-9; the mac's U3c, Russell's ruling of 2026-11-25 (a))
    //
    // When Show on Front Page went in but what the page held could not be
    // put back (Outcome.ShownWithWhatItHeldKept), ONE alert names the kept
    // file: keptTitle, then kept and the hidden-items sentence, with OK, the
    // default, and Open Folder, which opens the front page's folder. The
    // file stays hidden on Windows, so the alert says how to see hidden
    // items rather than selecting a file File Explorer would not show.

    /// <summary><c>wording.keptTitle</c>: a complete sentence, so it ends with a full stop.</summary>
    public static string KeptTitle(string @class) => $"The front page now shows {@class}.";

    /// <summary><c>wording.kept</c>, for one kept name.</summary>
    public static string KeptSentence(string kept) => $"What the front page held a moment before is kept beside it, hidden, as “{kept}”.";

    /// <summary><c>keptOnWindows.hiddenItems</c>: Microsoft's own Windows 11 path to hidden items.</summary>
    public const string HiddenItems = "To see it in File Explorer, select View > Show, then select Hidden items.";

    /// <summary><c>keptOnWindows.showKept</c>: the path bar's open-the-folder action (<c>workingFolderPathBar</c>, its <c>windowsLabel</c>).</summary>
    public const string OpenKeptFolder = "Open Folder";

    /// <summary><c>wording.keptGone</c>, for one kept name.</summary>
    public static string KeptGoneSentence(string kept) => $"“{kept}” is no longer there, so there is nothing to show.";

    /// <summary>The alert's message: one <c>kept</c> sentence per name, then <see cref="HiddenItems"/>.</summary>
    public static string KeptMessage(IReadOnlyList<string> keptNames)
    {
        var sentences = new List<string>();
        foreach (string name in keptNames) sentences.Add(KeptSentence(name));
        sentences.Add(HiddenItems);
        return string.Join(" ", sentences);
    }

    /// <summary>
    /// What Open Folder does (the mac's <c>FolderActions.showInFinder(files:)</c>
    /// and its plan): a kept file no longer there is said with
    /// <c>keptGone</c>, one sentence per name, before anything opens; the
    /// FOLDER that holds the kept files still there is then opened, once.
    /// The file itself is never selected or revealed (Russell's ruling of
    /// 2026-11-25 (a)), and with nothing left no folder is opened.
    /// </summary>
    /// <param name="keptOriginals">Each kept file's full path (<see cref="Outcome.ShownWithWhatItHeldKept.KeptOriginals"/>).</param>
    /// <param name="sayGone">Shows the <c>keptGone</c> sentences in an alert with OK.</param>
    /// <param name="openFolder">Opens a folder in File Explorer (the path bar's <c>FolderActions.OpenFolder</c>).</param>
    public static async Task OpenTheKeptFolderAsync(IReadOnlyList<string> keptOriginals,
                                                    Func<string, Task> sayGone, Action<string> openFolder)
    {
        var gone = new List<string>();
        string? folder = null;
        foreach (string kept in keptOriginals)
        {
            if (File.Exists(kept)) folder ??= System.IO.Path.GetDirectoryName(kept);
            else gone.Add(KeptGoneSentence(System.IO.Path.GetFileName(kept)));
        }
        if (gone.Count > 0) await sayGone(string.Join(" ", gone));
        if (folder is not null) openFolder(folder);
    }

    /// <summary>The class offered and the class the line names, both by file name.</summary>
    public sealed record Offering(string Show, string Shows, string ShowPath);

    /// <summary>What Show on Front Page did (the mac's <c>TodaysClassOnTheFrontPage.Outcome</c>).</summary>
    public abstract record Outcome
    {
        private Outcome() { }

        /// <summary>The front page now shows the class asked about.</summary>
        public sealed record Written : Outcome;

        /// <summary>
        /// The front page went in and now shows the class asked about, but
        /// what it held just before (another program edited it as it was
        /// saved) could not be put back over it, so it is kept beside it as a
        /// hidden file under each name in <see cref="KeptOriginals"/> (#899
        /// W7b2-6; the mac's <c>shownKeepingWhatItHeld</c>, U3c). Never
        /// <see cref="CouldNotSave"/>, which would say the page is as it was.
        /// The section window says it in ONE alert that names the kept file
        /// (<see cref="KeptTitle"/>, <see cref="KeptMessage"/>, W7b2-9).
        /// </summary>
        /// <param name="KeptOriginals">Each kept file's full path.</param>
        public sealed record ShownWithWhatItHeldKept(IReadOnlyList<string> KeptOriginals) : Outcome
        {
            /// <summary>Each kept file's name, as the alert and the trail say it.</summary>
            public IReadOnlyList<string> KeptNames
            {
                get
                {
                    var names = new List<string>();
                    foreach (string kept in KeptOriginals) names.Add(System.IO.Path.GetFileName(kept));
                    return names;
                }
            }
        }

        /// <summary>The front page already showed today's class: nothing was written.</summary>
        public sealed record AlreadyShows : Outcome;

        /// <summary>The front page or today's class changed while the teacher was deciding: nothing was written.</summary>
        public sealed record NoLongerOffered : Outcome;

        /// <summary>The write was refused: nothing was changed, so the page still shows what it showed.</summary>
        public sealed record CouldNotSave : Outcome;
    }

    private static readonly Regex WrittenDay = new(@"^(\d{4}-\d{2}-\d{2})", RegexOptions.CultureInvariant);

    /// <summary>The day a class is for in this section, the first ten characters as written; null when none.</summary>
    internal static DateOnly? DayAsWritten(string text, int section, bool isSectionLocal)
    {
        string? raw = PageFrontmatter.StoredText(text, PageFrontmatter.CreatedKeyFor(section, isSectionLocal))
                      ?? (isSectionLocal ? null : PageFrontmatter.StoredText(text, "created"));
        if (raw is null) return null;
        string value = raw.Trim().Trim('"', '\'');
        var match = WrittenDay.Match(value);
        if (!match.Success) return null;
        return DateOnly.TryParseExact(match.Groups[1].Value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day)
            ? day : null;
    }

    private sealed record ClassFacts(string Path, string Name, bool CertainlyVisible, DateOnly? Day, UnitDay? Number);

    /// <summary>
    /// Whether to ask, and about what — or null. Reads the real files.
    /// </summary>
    /// <param name="classPages">The section's class pages (full paths).</param>
    /// <param name="indexPath">The section's front page.</param>
    public static Offering? Offer(Course course, int section, IReadOnlyList<string> classPages, string indexPath,
                                  DateOnly today)
    {
        if (course.Configuration.KeptForReference) return null;
        if (!File.Exists(indexPath)) return null;
        try
        {
            var attributes = File.GetAttributes(indexPath);
            if (attributes.HasFlag(FileAttributes.ReparsePoint) || attributes.HasFlag(FileAttributes.ReadOnly)) return null;
        }
        catch { return null; }

        string indexText;
        try { indexText = File.ReadAllText(indexPath); } catch { return null; }

        var naming = course.Configuration.Naming;
        var classes = classPages.Select(path =>
        {
            string text;
            try { text = File.ReadAllText(path); } catch { text = ""; }
            bool local = PagePaths.IsSectionLocal(course.DirectoryPath, path);
            string name = System.IO.Path.GetFileNameWithoutExtension(path);
            return new ClassFacts(path, name,
                text.Length > 0 && PageFrontmatter.Visibility(text, section) == PageVisibility.Visible,
                text.Length > 0 ? DayAsWritten(text, section, local) : null,
                naming.Parse(name));
        }).ToList();

        // (1) Today's class: certainly visible, dated today; the higher of the
        // course's own numbering breaks a tie.
        var todays = classes.Where(c => c.CertainlyVisible && c.Day == today)
            .OrderByDescending(c => c.Number ?? new UnitDay(0, 0))
            .FirstOrDefault();
        if (todays is null) return null;

        // (2) The line, found exactly as sectionIndexPointer.found says.
        if (SectionIndex.CurrentlyShowing(indexText, classes.Select(c => c.Name).ToList()) is not { } shownName) return null;
        var shown = classes.First(c => string.Equals(c.Name, shownName, StringComparison.OrdinalIgnoreCase));

        // (3) Not already right: a certainly visible class dated today or later.
        if (shown.CertainlyVisible && shown.Day is { } shownDay && shownDay >= today) return null;

        // (4) Not declined today for this class.
        if (DeclinedToday(course, section, today) == todays.Name) return null;

        return new Offering(todays.Name, shown.Name, todays.Path);
    }

    // ---- Not Today (file-formats.json → frontPageNotToday)

    public static string NotTodayPath(Course course, int section) =>
        System.IO.Path.Combine(course.DirectoryPath, ".publish_state", $"section{section}.front-page-not-today.json");

    /// <summary>The class declined on <paramref name="today"/>, or null.</summary>
    public static string? DeclinedToday(Course course, int section, DateOnly today)
    {
        try
        {
            var record = JObject.Parse(File.ReadAllText(NotTodayPath(course, section)));
            return (string?)record["day"] == today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
                ? (string?)record["class"] : null;
        }
        catch { return null; }
    }

    /// <summary>Not Today: remembered for that section, the day asked and the class offered.</summary>
    public static void RecordNotToday(Course course, int section, DateOnly askedOn, Offering offering)
    {
        string path = NotTodayPath(course, section);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        var record = new JObject
        {
            ["version"] = "1",
            ["day"] = askedOn.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            ["class"] = offering.Show,
        };
        File.WriteAllText(path, record.ToString(Newtonsoft.Json.Formatting.Indented) + "\n", new UTF8Encoding(false));
        Note(course, section, $"left the front page as it was — Not Today: {offering.Show} offered, it showed {offering.Shows}");
    }

    /// <summary>
    /// Show on Front Page: read the page AGAIN, decide again for the day the
    /// question was asked, and write only the class that was asked about. An
    /// answer after midnight, or after a later class was published in
    /// Obsidian, writes nothing.
    /// </summary>
    /// <param name="pointerFor">The pointer facts for a class (the workspace's <c>PointerFor</c>).</param>
    /// <param name="tail">The time and offset the section's pages carry.</param>
    /// <param name="newStep">Makes the ONE step the front page is written through (#899 W7b2-6): the
    /// workspace's, key <c>showTodaysClassOnTheFrontPage</c>, made by <c>sheet</c>. Asked only once
    /// the page is to be written, so an answer that writes nothing makes no step.</param>
    internal static Outcome ShowOnTheFrontPage(Course course, int section, IReadOnlyList<string> classPages, string indexPath,
                                               DateOnly askedOn, Offering asked,
                                               Func<string, SectionIndex.Pointer> pointerFor, string tail,
                                               Func<UndoActionStep> newStep)
    {
        var again = Offer(course, section, classPages, indexPath, askedOn);
        if (again is null)
        {
            bool showsIt = false;
            try
            {
                showsIt = string.Equals(SectionIndex.CurrentlyShowing(File.ReadAllText(indexPath),
                    classPages.Select(p => System.IO.Path.GetFileNameWithoutExtension(p)).ToList()),
                    asked.Show, StringComparison.OrdinalIgnoreCase);
            }
            catch { }
            Note(course, section, showsIt
                ? $"left the front page as it was — already showed today's class: {asked.Show} offered, it showed {asked.Show}"
                : $"left the front page as it was — it changed while the teacher was asked: {asked.Show} offered, it showed {asked.Shows}");
            return showsIt ? new Outcome.AlreadyShows() : new Outcome.NoLongerOffered();
        }
        if (!string.Equals(again.Show, asked.Show, StringComparison.OrdinalIgnoreCase))
        {
            Note(course, section, $"left the front page as it was — it changed while the teacher was asked: {asked.Show} offered, it showed {again.Shows}");
            return new Outcome.NoLongerOffered();
        }

        string placed = $"put today's class on the front page — {asked.Show} in place of {again.Shows}";
        try
        {
            // ONE step through the door (#899 W7b2-6; the mac's show(_:in:)):
            // the teacher's own choice of class, so the page is the step's
            // content (writeFile), never the front page's rule (recompute).
            // Its before is read now, at plan time, by the step's Write.
            string text = File.ReadAllText(indexPath);
            var day = DayAsWritten(File.ReadAllText(again.ShowPath), section, PagePaths.IsSectionLocal(course.DirectoryPath, again.ShowPath))!.Value;
            if (SectionIndex.PointedAndDated(text, pointerFor(again.ShowPath), day, tail) is not { } written)
                throw new IOException("the front page's class line could not be rewritten");
            var step = newStep();
            step.Write(indexPath, written);
            step.Make();
        }
        catch (UndoStepLeftPartWayException partWay)
        {
            // The page went in and what it held could not be put back over
            // it: it shows the class asked about, and what it held just
            // before is kept beside it. Never "could not be saved" (the
            // mac's shownKeepingWhatItHeld and its trail line).
            var keptOutcome = new Outcome.ShownWithWhatItHeldKept(partWay.KeptOriginals);
            var line = new StringBuilder(placed);
            foreach (string kept in keptOutcome.KeptNames)
                line.Append($". What “{UndoSwap.PlaceOfStagedName(kept) ?? kept}” held just before is kept beside it as the hidden file “{kept}”");
            ActivityTrail.Note(ActivityTrail.Event.PutTodaysClassOnTheFrontPage, line.ToString(), course.Code, section);
            return keptOutcome;
        }
        catch
        {
            // Refused before anything changed (all or none): the page is as it was.
            Note(course, section, $"left the front page as it was — could not be saved: {asked.Show} offered, it showed {asked.Shows}");
            return new Outcome.CouldNotSave();
        }
        ActivityTrail.Note(ActivityTrail.Event.PutTodaysClassOnTheFrontPage, placed, course.Code, section);
        return new Outcome.Written();
    }

    private static void Note(Course course, int section, string what) =>
        ActivityTrail.Note(ActivityTrail.Event.LeftTheFrontPageAsItWas, what, course.Code, section);
}

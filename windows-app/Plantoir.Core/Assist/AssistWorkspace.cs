using Plantoir.Core.Models;
using Plantoir.Core.Scripting;

namespace Plantoir.Core.Assist;

/// <summary>
/// Every Plantoir operation an assistant is allowed to ask for, locked to one
/// working folder.
///
/// Two rules run through all of it, both earned from the measurements in
/// research/ai-assist/HISTORY.md, part 1:
///
/// **Nothing named is taken on trust.** A course code, a section number and a
/// page title are all validated against what is actually on disk before
/// anything happens. Asked to "clean up my course" — a request naming no
/// course at all — the small model proposed backing up "MCV4U", a code it
/// invented. So a name that does not resolve is a refusal that says what does
/// exist, never a best guess.
///
/// **The tools do the work; the assistant only picks one.** Given fine-grained
/// tools and asked to publish a class "and everything it links to", the model
/// chose the publish tool and silently skipped the link resolution, eight
/// times out of eight. Given one coarse tool that resolves links itself, it
/// got it right eight times out of eight. So link resolution, the choice
/// between <c>publish:</c> and <c>publishForSection&lt;N&gt;:</c>, the backup, the
/// rebuild and the publish are one operation here — not steps somebody else
/// sequences.
///
/// There is deliberately no delete, no archive and no overwrite. The model
/// declines what it has no tool for, which is why "delete the Unit 1 folder"
/// was harmless in testing; that property is worth keeping by construction.
/// </summary>
public sealed partial class AssistWorkspace
{
    private readonly string _folder;
    private readonly ILauncherRunner _launcher;
    private readonly string? _lockedCourse;
    private readonly UndoHistory? _undo;

    /// <summary>
    /// Set only by tests. A test that read the real, machine-global
    /// %LOCALAPPDATA%\Plantoir\settings.json would behave differently
    /// depending on whatever Cloudflare Account ID happens to be configured
    /// on the machine running the suite — exactly the kind of surprise this
    /// override exists to make deterministic instead.
    /// </summary>
    internal static Func<string>? CloudflareAccountIdOverrideForTests;

    internal static string CurrentCloudflareAccountId() =>
        CloudflareAccountIdOverrideForTests?.Invoke() ?? AppSettings.Load().CloudflareAccountId;


    // ---- One backup per conversation ---------------------------------------

    /// <summary>
    /// The copy saved for each course this conversation has changed, keyed by
    /// course code — the mac's <c>conversationBackups</c>. This object lives
    /// for the life of the serving process, which is the life of the
    /// teacher's conversation, so "once" means once per chat.
    /// </summary>
    private readonly Dictionary<string, string> _conversationBackups = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// The sections this conversation has already been told what publishing
    /// means, as <c>CODE/N</c>. Lives beside <see cref="_conversationBackups"/>
    /// and for the same span, which is the same span the mac's
    /// <c>sectionsToldWhatPublishingMeans</c> lives for.
    /// </summary>
    private readonly HashSet<string> _sectionsToldWhatPublishingMeans = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Note that this section has now had the briefing, and say whether it
    /// had already had it BEFORE this call.
    /// </summary>
    /// <remarks>
    /// <para><b>Per conversation, not per folder — changed 2026-09-09.</b>
    /// This used to be a marker file under <c>courses/.internal/assist/</c>,
    /// so a section briefed once was never briefed again on that machine.
    /// That was defensible while a MODEL was the only caller: it is the model
    /// the repetition would bore, and a model cannot repeat itself after its
    /// session has ended anyway.</para>
    ///
    /// <para>A fixed phrasing changed the question. "What does publishing
    /// mean?" is now matched in code and reaches this tool directly, so the
    /// caller is a TEACHER asking a question — and a file on disk meant the
    /// answer arrived once per working folder, ever, with every later asking
    /// brushed off. Answering a question with "I explained that before" is
    /// refusing to answer it. A conversation cannot repeat itself after it has
    /// ended, and a teacher back a month later may genuinely have forgotten,
    /// so the smaller promise is the right one.</para>
    /// </remarks>
    public bool NoteExplainedThisConversation(string courseCode, int sectionNumber) =>
        !_sectionsToldWhatPublishingMeans.Add($"{courseCode}/{sectionNumber}");

    /// <summary>
    /// The copy saved before this conversation's FIRST change, or null while
    /// it has only read. What "Restore Section N…" puts back. The most recent
    /// one when a session unlocked to a course has changed several.
    /// </summary>
    public string? ConversationBackupPath { get; private set; }

    /// <summary>
    /// Saves a copy of the course before the first change of a conversation,
    /// and reuses it for every later change in the same conversation.
    ///
    /// <para>Until 2026-09-07 every changing tool saved its own copy, and
    /// <see cref="CourseArchiver.MostBackupsKept"/> is five — so after six
    /// changes the copy from before the conversation started had already
    /// been pruned, and a "put it all back" button could not have kept its
    /// promise. One copy per conversation is what the mac has always done,
    /// and it is what the Backups list a teacher reads describes ("before an
    /// assistant chat about Section N"). Per-change undo is
    /// <see cref="UndoHistory"/>'s promise and is unchanged.</para>
    /// </summary>
    private string BackUpOnceForThisConversation(Course course, int sectionNumber, IProgress<string>? progress = null)
    {
        // One copy in flight per course: a second write arriving while the
        // first is zipping waits for it and reuses it rather than zipping again.
        lock (_conversationBackups)
        {
            return BackUpOnceForThisConversationHeld(course, sectionNumber, progress);
        }
    }

    private string BackUpOnceForThisConversationHeld(Course course, int sectionNumber, IProgress<string>? progress)
    {
        // The recorded copy is reused even if it has since gone — deleted from
        // the Backups list, or pruned by five later conversations. Taking a
        // fresh copy of the already-changed course and calling it "from before
        // this conversation started" would make the restore dialog's promise
        // false; the mac checks only its dictionary too, and a vanished copy
        // then fails honestly with "could not be read".
        if (_conversationBackups.TryGetValue(course.Code, out var existing))
        {
            ConversationBackupPath = existing;
            return existing;
        }
        progress?.Report(AssistWording.BackingUpFirst(course.Code));
        string made = AssistantBackup(course, sectionNumber);
        _conversationBackups[course.Code] = made;
        ConversationBackupPath = made;
        // An outside assistant's conversation says which zip it may restore
        // from, so a delete in the app keeps it (#283, ruling 9).
        if (RecordsHeldBackups) HeldBackups.Record(_folder, course.Code, made);
        return made;
    }

    /// <param name="lockedCourse">
    /// When given, the session can see and touch this course and nothing else.
    /// Plantoir uses it when a teacher starts an assistant from a particular
    /// course's menu: the request was about that course, so reaching another
    /// one is never right, and a lock is a stronger guarantee than an
    /// instruction the model might drift from.
    /// </param>
    /// <param name="undo">
    /// Remembers what this session changed, so a wrong publish can be taken
    /// back without restoring a whole course. Optional: without it every write
    /// still happens, just unrecorded.
    /// </param>
    public AssistWorkspace(string workspacePath, ILauncherRunner launcher, string? lockedCourse = null,
                           UndoHistory? undo = null)
    {
        _folder = Path.GetFullPath(workspacePath);
        _launcher = launcher;
        _undo = undo;
        _lockedCourse = string.IsNullOrWhiteSpace(lockedCourse) ? null : lockedCourse.Trim();
        if (Workspace.Classify(_folder) != WorkspaceState.Ready)
            throw new AssistRefusal(
                $"“{_folder}” isn’t a Plantoir working folder — it has no {Workspace.MarkerLauncher}. " +
                "Open the folder in Plantoir once to set it up.");

        if (_lockedCourse is not null &&
            !Workspace.DiscoverCourses(_folder).Any(
                c => string.Equals(c.Code, _lockedCourse, StringComparison.OrdinalIgnoreCase)))
            throw new AssistRefusal($"There’s no course called “{_lockedCourse}” in “{_folder}”.");
    }

    public string FolderPath => _folder;

    /// <summary>Set by plantoir-mcp: write the conversation's backup to a held-backup record (#283).</summary>
    public bool RecordsHeldBackups { get; set; }

    /// <summary>What this session has changed, or null when nothing tracks it.</summary>
    public UndoHistory? History => _undo;

    /// <summary>The one course this session may touch, or null when unrestricted.</summary>
    public string? LockedCourse => _lockedCourse;

    // ---- Looking things up ----------------------------------------------

    public List<Course> Courses()
    {
        var courses = Workspace.DiscoverCourses(_folder);
        if (_lockedCourse is null) return courses;
        return courses
            .Where(c => string.Equals(c.Code, _lockedCourse, StringComparison.OrdinalIgnoreCase))
            .ToList();
    }

    /// <summary>
    /// The course with this code, or a refusal naming the codes that do exist.
    /// Matching is case-insensitive because teachers type "mcv4u".
    /// </summary>
    public Course Course(string code)
    {
        string wanted = (code ?? "").Trim();
        // A call naming no course at all is said plainly (#262), rather than
        // as a search for a course called nothing.
        if (wanted.Length == 0) throw new AssistRefusal(AssistWording.NoCourseNamed);
        var courses = Courses();
        var found = courses.FirstOrDefault(c => string.Equals(c.Code, wanted, StringComparison.OrdinalIgnoreCase));
        if (found is not null) return found;

        // A locked session says WHY, rather than claiming the course does not
        // exist. "There's no course called MCV4U" would be a lie the assistant
        // would repeat to a teacher looking straight at it in the sidebar.
        // Two sentences, from the contract (#180/#208): a code naming another
        // course that IS here says to open it; a code naming nothing here
        // (a typo, an invention) must not - "open ZZZ9Z" sends a teacher
        // looking for something that does not exist. Courses() has already
        // filtered to the lock, so the folder is asked again to tell the two
        // apart, and the folder's spelling is the one named.
        if (_lockedCourse is not null)
        {
            var elsewhere = Workspace.DiscoverCourses(_folder)
                .FirstOrDefault(c => string.Equals(c.Code, wanted, StringComparison.OrdinalIgnoreCase));
            throw new AssistRefusal(elsewhere is not null
                ? AssistWording.AskedAboutAnotherCourse(_lockedCourse, elsewhere.Code)
                : AssistWording.AskedAboutACourseThatIsNotHere(_lockedCourse, wanted));
        }

        // A bare code names the LIVE course; with no live one, a code that
        // only reference courses SHOW is refused with the candidates named
        // (#241): the two deliberately show the same code, so a guess would
        // look right every time and be wrong half of it.
        var candidates = courses
            .Where(c => ReferenceCourse.IsKeptForReference(c)
                        && string.Equals(ReferenceCourse.ShownCode(c), wanted, StringComparison.OrdinalIgnoreCase))
            .Select(c => c.Code).OrderBy(name => name, StringComparer.Ordinal).ToList();
        if (candidates.Count > 0)
        {
            string asked = CourseCodeValidator.Normalize(wanted);
            throw new AssistRefusal(candidates.Count == 1
                ? $"No course you are teaching is called {asked}. {candidates[0]} is kept for reference and shows that code — name it as {candidates[0]}."
                : $"No course you are teaching is called {asked}. These are kept for reference and show that code: {string.Join(", ", candidates)}. Name the one you mean.");
        }

        string known = courses.Count == 0
            ? "This working folder has no courses yet."
            : "The courses here are " + Humanize(courses.Select(c => c.Code)) + ".";
        throw new AssistRefusal($"There’s no course called “{wanted}” in this working folder. {known}");
    }

    /// <summary>The section, or a refusal naming the sections that do exist.</summary>
    public int Section(Course course, int sectionNumber)
    {
        var numbers = course.SectionNumbers;
        if (numbers.Contains(sectionNumber)) return sectionNumber;
        string known = numbers.Count == 0
            ? $"{course.Code} has no sections."
            : $"{course.Code} has section{(numbers.Count == 1 ? "" : "s")} " +
              Humanize(numbers.Select(n => n.ToString())) + ".";
        throw new AssistRefusal($"There’s no section {sectionNumber} in {course.Code}. {known}");
    }

    /// <summary>Every page of a section, as paths relative to the working folder.</summary>
    public List<string> Pages(Course course, int sectionNumber) =>
        PagePaths.MarkdownPages(course.DirectoryPath, sectionNumber)
            .Where(page => ListsAsAPage(course, page))   // never the How I Teach page (#340)
            .Select(Relative).ToList();

    /// <summary>
    /// The section's CLASS pages — the ones that are days of teaching, in date
    /// order.
    ///
    /// "Class page" is read from the course's own configuration rather than
    /// guessed: it is a page inside one of the folders the SHARED membership
    /// rule counts (<c>contracts/class-planning.json</c> →
    /// <c>classFolder.membership</c>), and never an <c>index.md</c>.
    ///
    /// <para>Membership, not the whole <c>per_section_folders</c> list. This
    /// walked every per-section folder until 2026-09-19, so a course
    /// configured <c>["All Classes","Handouts"]</c> counted its handouts as
    /// days of teaching here while the mac and <c>build_site.py</c> did not —
    /// a difference nobody chose. The rule can also count FEWER folders than
    /// the list: a course whose folders are <c>["Lessons","Labs"]</c> mentions
    /// classes nowhere, so membership falls back to the single name the naming
    /// half chose and the Labs pages stop being classes.</para>
    ///
    /// Both exclusions matter, and the second is the dangerous one. A section's
    /// <c>index.md</c>, its folder indexes and its Key Links page all carry the
    /// SAME date as the first class — so "every class from September 8th"
    /// filtered naively on dates alone would hide the site's own front page.
    /// </summary>
    public List<string> ClassPages(Course course, int sectionNumber)
    {
        var folders = ClassFolderRule.Names(course.Configuration.ClassFolder,
                                            course.Configuration.PerSectionFolders);
        var pages = new List<(DateOnly? Date, string Path)>();

        foreach (string folder in folders)
        {
            string root = Path.Combine(course.SectionDirectory(sectionNumber), folder);
            if (!Directory.Exists(root)) continue;
            foreach (string page in PagePaths.MarkdownPages(root, sectionNumber))
            {
                if (string.Equals(Path.GetFileName(page), "index.md", StringComparison.OrdinalIgnoreCase))
                    continue;
                pages.Add((DateOf(course, sectionNumber, page), page));
            }
        }

        // Dated pages first, in date order; undated ones keep name order after.
        return pages
            .OrderBy(p => p.Date is null)
            .ThenBy(p => p.Date ?? default)
            .ThenBy(p => p.Path, StringComparer.OrdinalIgnoreCase)
            .Select(p => p.Path)
            .ToList();
    }

    /// <summary>
    /// Pages that must never be hidden from students, whatever is asked.
    ///
    /// Two rules, both from the teacher, and both about navigation rather than
    /// content:
    ///
    /// * **Anything Key Links points at.** That page is the section's list of
    ///   things a student needs all year — the curriculum expectations, how
    ///   marks work, where to get help. Hiding one because some class happened
    ///   to link to it takes away the signpost, not the lesson. (In a real
    ///   session a teacher had to protect exactly this set by hand, then
    ///   accept a window where a safety document was hidden, because nothing
    ///   expressed the rule.)
    /// * **Index pages.** <c>All Classes/index.md</c> is where a student who
    ///   missed a class is told to start; a section's own <c>index.md</c> is
    ///   the front door. An index is a way in, not a lesson, and an empty
    ///   folder page is far better than a broken one.
    /// * **Curriculum.** The expectations are what the course is accountable
    ///   to, and students, parents and administrators may look them up at any
    ///   point in the year. They are always visible.
    ///
    /// This constrains the DRAFT FLAG only. Nothing here stops a page's
    /// <c>created</c> date being changed — rolling a course over to a new year
    /// has to be able to move these dates like any others.
    /// </summary>
    public HashSet<string> ProtectedFromHiding(Course course, int sectionNumber)
    {
        var protectedPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (string page in PagePaths.MarkdownPages(course.DirectoryPath, sectionNumber))
        {
            if (string.Equals(Path.GetFileName(page), "index.md", StringComparison.OrdinalIgnoreCase) ||
                IsCurriculum(course.DirectoryPath, page))
                protectedPaths.Add(Path.GetFullPath(page));
        }

        string keyLinks = Path.Combine(course.SectionDirectory(sectionNumber), KeyLinksFileName);
        if (!File.Exists(keyLinks)) return protectedPaths;

        protectedPaths.Add(Path.GetFullPath(keyLinks));
        try
        {
            var resolutions = WikiLinks.Resolve(
                WikiLinks.PageLinks(File.ReadAllText(keyLinks)), course.DirectoryPath, sectionNumber, keyLinks);
            foreach (var resolution in resolutions)
                if (resolution.Outcome == LinkOutcome.Resolved)
                    protectedPaths.Add(Path.GetFullPath(resolution.Path!));
        }
        catch { /* an unreadable Key Links protects what it already listed */ }

        return protectedPaths;
    }

    /// <summary>The per-section page whose links are the year-round signposts.</summary>
    private const string KeyLinksFileName = "Key Links.md";

    /// <summary>
    /// True when a page is curriculum reference material.
    ///
    /// Matches build_site.py's own rule exactly — any FOLDER segment
    /// containing "curriculum", case-insensitively, with the filename ignored.
    /// That is what makes it work for a course whose folders are called
    /// "Ontario Curriculum" and "College Board Curriculum" rather than plain
    /// "Curriculum", which is the normal case outside the example content.
    /// </summary>
    public static bool IsCurriculum(string courseDirectory, string pagePath)
    {
        string relative;
        try { relative = Path.GetRelativePath(Path.GetFullPath(courseDirectory), Path.GetFullPath(pagePath)); }
        catch { return false; }

        var segments = relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        for (int i = 0; i < segments.Length - 1; i++)          // folders only, never the file name
            if (segments[i].Contains("curriculum", StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    /// <summary>
    /// Year-round reference pages, which belong to the start of the year
    /// rather than to any one lesson: the section's own front page,
    /// everything Key Links points at, and every curriculum page.
    ///
    /// A rollover moves the classes but leaves these behind on last year's
    /// dates, where they sort oddly and show up as stragglers in the date
    /// audit. Dating them to the first day of class puts them at the
    /// beginning of the year, which is what they are.
    ///
    /// The front page is included even though publishing later moves it again
    /// — to the most recent published class — because a rolled-over course is
    /// not published yet, and until it is, the install date is simply wrong.
    /// </summary>
    private List<PlannedDate> ReferenceDates(Course course, int section, DateOnly firstDay)
    {
        var reference = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        string index = SectionIndex.PathFor(course, section);
        if (File.Exists(index)) reference.Add(Path.GetFullPath(index));

        string keyLinks = Path.Combine(course.SectionDirectory(section), KeyLinksFileName);
        if (File.Exists(keyLinks))
        {
            reference.Add(Path.GetFullPath(keyLinks));
            try
            {
                foreach (var resolution in WikiLinks.Resolve(
                             WikiLinks.PageLinks(File.ReadAllText(keyLinks)), course.DirectoryPath, section, keyLinks))
                    if (resolution.Outcome == LinkOutcome.Resolved)
                        reference.Add(Path.GetFullPath(resolution.Path!));
            }
            catch { }
        }

        foreach (string page in PagePaths.MarkdownPages(course.DirectoryPath, section))
            if (IsCurriculum(course.DirectoryPath, page)) reference.Add(Path.GetFullPath(page));

        var dates = new List<PlannedDate>();
        foreach (string page in reference.OrderBy(p => p, StringComparer.OrdinalIgnoreCase))
        {
            if (DateOf(course, section, page) == firstDay) continue;
            bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, page);
            dates.Add(new PlannedDate(
                Title: Path.GetFileNameWithoutExtension(page),
                RelativePath: Relative(page),
                FrontmatterKey: PageFrontmatter.CreatedKeyFor(section, sectionLocal),
                Current: DateOf(course, section, page),
                New: firstDay,
                MeetingNumber: 0));
        }
        return dates;
    }

    public static DateOnly? DateOf(Course course, int sectionNumber, string pagePath)
    {
        bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, pagePath);
        try { return PageFrontmatter.CreatedOn(File.ReadAllText(pagePath), sectionNumber, sectionLocal); }
        catch { return null; }
    }

    /// <summary>
    /// The single page with this title, or a refusal. A title matching several
    /// files is never resolved by picking one — publishing the wrong page is
    /// exactly the failure this whole design is built to avoid.
    /// </summary>
    public string Page(Course course, int sectionNumber, string title)
    {
        string wanted = title.Trim();
        if (wanted.Length == 0) throw new AssistRefusal("No page was named.");

        // A path was given rather than a title: honour it, but only inside.
        if (wanted.Contains('/') || wanted.Contains('\\'))
        {
            string direct = PagePaths.ResolveInside(_folder, wanted);
            if (File.Exists(direct)) return direct;
        }

        // Asked for by name, the How I Teach page is never published or
        // hidden — it is never on the site (#340, howITeachPage.notListedAsAPage).
        if (HowITeachPage.IsItsTitle(wanted))
            throw new AssistRefusal(AssistWording.HowITeachIsNeverPublished(course.Code));

        string bare = wanted.EndsWith(".md", StringComparison.OrdinalIgnoreCase) ? wanted[..^3] : wanted;
        var matches = PagePaths.MarkdownPages(course.DirectoryPath, sectionNumber)
            .Where(p => ListsAsAPage(course, p))
            .Where(p => string.Equals(System.IO.Path.GetFileNameWithoutExtension(p), bare,
                                      StringComparison.OrdinalIgnoreCase))
            .ToList();

        if (matches.Count == 1) return matches[0];
        if (matches.Count == 0)
            throw new AssistRefusal(
                $"There’s no page called “{wanted}” in {course.Code} Section {sectionNumber}.");
        throw new AssistRefusal(
            $"{course.Code} Section {sectionNumber} has {matches.Count} pages called “{wanted}” — " +
            Humanize(matches.Select(Relative)) + ". Say which one you mean.");
    }

    public string ReadPage(Course course, int sectionNumber, string title) =>
        File.ReadAllText(Page(course, sectionNumber, title));

    // ---- Planning --------------------------------------------------------

    /// <summary>
    /// Words that mean every page and name none (#352 / mac #197): a closed
    /// list, held equal to <c>assist-cases.json</c> -> <c>pagesNamingNoPage.everyPageWords</c>.
    /// </summary>
    internal static readonly string[] EveryPageWords =
        { "all", "everything", "all pages", "every page", "all of them", "all of those", "*" };

    private static bool IsAnEveryPageWord(string name) =>
        EveryPageWords.Contains(name.Trim().ToLowerInvariant(), StringComparer.Ordinal);

    private static bool SectionHasAPageCalled(Course course, int section, string name) =>
        PagePaths.MarkdownPages(course.DirectoryPath, section)
                 .Any(path => string.Equals(Path.GetFileNameWithoutExtension(path), name.Trim(),
                                            StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Something the teacher can type next: "Publish" or "Hide" and the
    /// LOWEST unit that has class pages, in the course's own word; failing
    /// that, the first page.
    /// </summary>
    private static string ExampleOfWhichPages(Course course, int section, bool hiding)
    {
        string verb = hiding ? "Hide" : "Publish";
        string unitWord = course.Configuration.UnitWord;
        var titles = PagePaths.MarkdownPages(course.DirectoryPath, section)
            .Select(path => Path.GetFileNameWithoutExtension(path))
            .ToList();
        // A numbered course has no units (#274): its FIRST class page instead,
        // built from the course's own word — "Publish Week 1".
        var naming = course.Configuration.Naming;
        if (naming.IsNumbered)
        {
            var numbers = titles.Select(title => naming.Parse(title)?.Day).OfType<int>().ToList();
            if (numbers.Count > 0) return $"{verb} {naming.Title(1, numbers.Min())}";
        }
        var units = naming.IsNumbered ? new List<int>() : titles
            .Select(title => System.Text.RegularExpressions.Regex.Match(title,
                "^" + System.Text.RegularExpressions.Regex.Escape(unitWord) + @" (\d+), ",
                System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            .Where(match => match.Success)
            .Select(match => int.Parse(match.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture))
            .ToList();
        if (units.Count > 0) return $"{verb} {unitWord} {units.Min()}";
        string? first = titles.OrderBy(title => title, StringComparer.OrdinalIgnoreCase).FirstOrDefault();
        return first is null ? verb : $"{verb} {first}";
    }

    /// <summary>The trail line for #197: the act and the word or HOW MANY, never the names.</summary>
    private static void NoteNamedNoPage(string course, int section, string what) =>
        Plantoir.Core.Scripting.ActivityTrail.Note(
            Plantoir.Core.Scripting.ActivityTrail.Event.AssistantNamedNoPage,
            "the assistant named no page it could find: " + what + "; nothing was changed", course, section);

    /// <summary>
    /// Work out what publishing (or hiding) these pages would do, without
    /// touching anything. This is what the teacher confirms.
    ///
    /// Takes a LIST, and takes any page — not just a class page. Both of those
    /// came out of a real session that the single-class-page version could not
    /// express:
    ///
    /// * Hiding 25 classes meant 25 calls, each one republishing the site: 26
    ///   deploys for what is logically one change. Batching is not a
    ///   convenience here, it is the difference between usable and not.
    /// * A safety contract linked from BOTH the first class (which must stay
    ///   up) and a later one (which must come down) made the task
    ///   unsatisfiable: following links took it down, and nothing could
    ///   put just that page back. Being able to name any page directly
    ///   dissolves it. That shape — a shared page reachable from several
    ///   classes — is the normal shape of a course, not an edge case.
    ///
    /// <para><b>Links are ALWAYS followed, in both directions (#420).</b> A
    /// publish takes every page the named pages link to, transitively,
    /// stopping at a class; an unpublish takes a linked page only when nothing
    /// students can still see needs it (<c>shared-rules.json</c> →
    /// <c>followingLinks</c>). There is no argument for it: Windows used to
    /// take an <c>includeLinked</c> flag that defaulted to false, so a
    /// model's publish that left it out published a page whose links led to
    /// pages students could not see — the one thing the contract says
    /// publishing must never do. The mac removed the flag for the same reason
    /// (<c>toolSchemas.departures.absentHere</c>: it asked the MODEL how far a
    /// publish should reach).</para>
    /// </summary>
    public PublishPlan PlanPublish(
        string courseCode, int sectionNumber, IReadOnlyList<string> pageTitles,
        bool draft = false, bool publishes = true,
        DateOnly? onOrAfter = null, DateOnly? before = null)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);

        // A list that is NOTHING BUT words meaning every page names no page
        // (#352 / mac #197). Asked of the section FIRST: a page really titled
        // "All" is a page, whatever it is called.
        var givenNames = pageTitles.Select(title => title.Trim()).Where(title => title.Length > 0).ToList();
        if (givenNames.Count > 0 && givenNames.All(IsAnEveryPageWord) &&
            !givenNames.Any(name => SectionHasAPageCalled(course, section, name)))
        {
            if (onOrAfter is null && before is null)
            {
                NoteNamedNoPage(course.Code, section,
                    $"the list was only the word \u201c{givenNames[0].ToLowerInvariant()}\u201d");
                string example = ExampleOfWhichPages(course, section, hiding: draft);
                throw new AssistRefusal(draft
                    ? AssistWording.EveryPageIsNotAPageToHide(example)
                    : AssistWording.EveryPageIsNotAPageToPublish(example));
            }
            pageTitles = Array.Empty<string>();
            givenNames.Clear();
        }

        if (pageTitles.Count == 0 && onOrAfter is null && before is null)
            throw new AssistRefusal("No page was named, and no dates were given to choose classes by.");

        // An OPEN-ENDED publish (every class from a day to the end of the
        // course) is refused. The mac's rule, and why it is code rather than
        // a sentence in a tool description is in doc 10: a typo'd "publsh
        // tomorows class" chose exactly this 10 times in 10, which would have
        // put the rest of the term in front of students. An open-ended
        // UNPUBLISH is allowed: it hides work rather than exposing it.
        if (!draft && pageTitles.Count == 0 && onOrAfter is { } openFrom && before is null)
            throw new AssistRefusal(
                $"Nothing was published: every class from {DateText.Iso(openFrom)} to the end of the course is " +
                "more than one request should put in front of students. Name the pages, or give an end date too.");
        if (onOrAfter is { } from && before is { } until && until <= from)
            throw new AssistRefusal(
                $"No class can be on or after {DateText.Iso(from)} and also before {DateText.Iso(until)}.");

        bool isDraft = draft;
        bool isPublish = !draft;

        var problems = new List<string>();
        var protectedPaths = isDraft
            ? ProtectedFromHiding(course, section)
            : new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // Read all markdown pages in the section — never the How I Teach
        // page, which no publish can put on the site (#340).
        var allMarkdown = PagePaths.MarkdownPages(course.DirectoryPath, section)
            .Where(page => ListsAsAPage(course, page)).ToList();
        // Every page is keyed by its PATH (#420 review R5). Two pages can share
        // a file name — every folder's landing page is index.md — and keying
        // the walk by file name made publishing one of them follow the OTHER
        // one's links: more published than the plan could show. Now that a
        // publish always follows links, that is the damaging direction.
        var pagesList = new List<PlannedPage>();
        var pagesByTitle = new Dictionary<string, PlannedPage>(StringComparer.OrdinalIgnoreCase);
        var pagesByPath = new Dictionary<string, PlannedPage>(StringComparer.OrdinalIgnoreCase);

        foreach (string p in allMarkdown)
        {
            var planned = Plan(course, section, p, isDraft, viaLink: false);
            pagesList.Add(planned);
            pagesByPath[planned.RelativePath] = planned;
            if (!pagesByTitle.ContainsKey(planned.Title))
                pagesByTitle[planned.Title] = planned;
        }

        // Two pages a teacher would read by the same name are named WITH their
        // folder on the plan, in the contract's one shape (startOfYear.wording
        // .pageNameInFolder: “{page}” (in {folder})), names compared trimmed,
        // ignoring case, in one Unicode form — as start of year compares them.
        foreach (var group in pagesList.GroupBy(p => ComparableName(p.DisplayTitle)).Where(g => g.Count() > 1))
            foreach (var page in group.ToList())
            {
                var withFolder = page with { Folder = FolderOf(course, page) };
                pagesList[pagesList.IndexOf(page)] = withFolder;
                pagesByPath[page.RelativePath] = withFolder;
                if (ReferenceEquals(pagesByTitle.GetValueOrDefault(page.Title), page)) pagesByTitle[page.Title] = withFolder;
            }

        // Build link graph and referrers, by path.
        var linksFrom = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        var referrers = new Dictionary<string, List<PlannedPage>>(StringComparer.OrdinalIgnoreCase);

        foreach (var page in pagesList)
        {
            string fullPath = PagePaths.ResolveInside(_folder, page.RelativePath);
            string text = File.ReadAllText(fullPath);
            var targets = new List<string>();
            foreach (var resolution in WikiLinks.Resolve(WikiLinks.PageLinks(text), course.DirectoryPath, section, fullPath))
            {
                if (resolution.Problem is { } prob)
                {
                    if (!problems.Contains(prob)) problems.Add(prob);
                    continue;
                }
                if (resolution.Outcome == LinkOutcome.Resolved && resolution.Path != null)
                {
                    string target = Relative(Path.GetFullPath(resolution.Path));
                    if (pagesByPath.ContainsKey(target) && !targets.Contains(target, StringComparer.OrdinalIgnoreCase))
                        targets.Add(target);
                }
            }
            linksFrom[page.RelativePath] = targets;
            foreach (var target in targets)
            {
                if (!referrers.TryGetValue(target, out var list))
                {
                    list = new List<PlannedPage>();
                    referrers[target] = list;
                }
                if (!list.Any(r => string.Equals(r.RelativePath, page.RelativePath, StringComparison.OrdinalIgnoreCase)))
                    list.Add(page);
            }
        }

        // Identify named pages
        var named = new List<PlannedPage>();
        var unknownNames = new List<string>();
        var chosen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);   // paths

        foreach (string title in pageTitles)
        {
            string wanted = title.Trim();
            if (wanted.Length == 0) continue;
            if (HowITeachPage.IsItsTitle(wanted))
            {
                problems.Add(AssistWording.HowITeachIsNeverPublished(course.Code));
                continue;
            }

            // Expand a whole unit if the title is like "Unit 4" - in the
            // course's OWN word, so "publish Module 4" is understood at all.
            // Reading only the literal "Unit" does not refuse: it matches
            // nothing, the request quietly names no pages, and the teacher is
            // told their unit is empty. The mac shipped exactly that for a few
            // hours; it is the input half of this feature and the half that
            // fails silently.
            string unitWord = course.Configuration.UnitWord;
            if (PublishPlan.UnitNamed(wanted, course.Configuration.Naming) is { } unitNum)
            {
                var unitPages = pagesList.Where(p => p.IsClassPage &&
                    p.Title.StartsWith($"{unitWord} {unitNum},", StringComparison.OrdinalIgnoreCase)).ToList();
                var ordered = isDraft ? unitPages.OrderByDescending(p => p.Title) : unitPages.OrderBy(p => p.Title);
                foreach (var up in ordered)
                {
                    if (chosen.Add(up.RelativePath)) named.Add(up);
                }
                continue;
            }

            string bare = wanted.EndsWith(".md", StringComparison.OrdinalIgnoreCase) ? wanted[..^3] : wanted;

            // A PATH names exactly one page — the answer to "which one?" below.
            // Read from the working folder (the way the refusal lists them),
            // then from the course folder.
            PlannedPage? byPath = null;
            if (bare.Contains('/') || bare.Contains('\\'))
            {
                foreach (string root in new[] { _folder, course.DirectoryPath })
                {
                    try
                    {
                        string rel = Relative(Path.GetFullPath(Path.Combine(root, bare.Replace('\\', '/') + ".md")));
                        if (pagesByPath.TryGetValue(rel, out byPath)) break;
                    }
                    catch { }
                }
                if (byPath is null)
                    bare = Path.GetFileNameWithoutExtension(bare.Replace('\\', '/').Split('/')[^1]);
            }

            // By file name, then by the name the teacher sees, then — the answer
            // to "which one?" — by a name with its folder, in the contract's
            // shape: “Notes” (in section1). More than one page answering to the
            // name is ASKED about, never guessed: the walk would follow
            // whichever page it picked (#420 review R5).
            var inFolder = System.Text.RegularExpressions.Regex.Match(bare, @"^[“""]?(?<page>.+?)[”""]? \(in (?<folder>[^)]+)\)$");
            var candidates = byPath is not null ? new List<PlannedPage> { byPath }
                : pagesList.Where(p => string.Equals(p.Title, bare, StringComparison.OrdinalIgnoreCase)).ToList();
            if (candidates.Count == 0)
                candidates = pagesList.Where(p => ComparableName(p.DisplayTitle) == ComparableName(bare)).ToList();
            if (candidates.Count == 0 && inFolder.Success)
                candidates = pagesList.Where(p =>
                        (ComparableName(p.DisplayTitle) == ComparableName(inFolder.Groups["page"].Value)
                         || ComparableName(p.Title) == ComparableName(inFolder.Groups["page"].Value))
                        && ComparableName(FolderOf(course, p)) == ComparableName(inFolder.Groups["folder"].Value)).ToList();
            if (candidates.Count > 1)
            {
                // Each named so the answer can be typed back: by its own name
                // when those differ (two landing pages read as their folders),
                // with its folder when they do not.
                bool namesDiffer = candidates.Select(c => ComparableName(c.DisplayTitle)).Distinct().Count() == candidates.Count;
                throw new AssistRefusal(AssistWording.MorePagesThanOneAreCalled(course.Code, section.ToString(), bare) + "\n" +
                    string.Join("\n", candidates.Select(c => "• " + (namesDiffer
                        ? StartOfYearWording.PageName(c.DisplayTitle)
                        : StartOfYearWording.PageNameInFolder(c.DisplayTitle, FolderOf(course, c))))));
            }
            if (candidates.Count == 0)
            {
                unknownNames.Add(wanted);
                continue;
            }

            var matchedPage = candidates[0];
            string full = Path.GetFullPath(PagePaths.ResolveInside(_folder, matchedPage.RelativePath));
            if (isDraft && protectedPaths.Contains(full))
            {
                problems.Add($"“{matchedPage.Title}” is never hidden — " +
                             "it is an index page or something Key Links points at. Left published.");
                continue;
            }
            if (chosen.Add(matchedPage.RelativePath)) named.Add(matchedPage);
        }

        // Every name given matched nothing: not a stray word in a mixed list,
        // but the whole list (#352 / mac #197). This used to fall through to
        // "Nothing needed changing.", success about a request that did
        // nothing. A unit that expanded to no pages, or a page that is never
        // hidden, is not an unknown name and keeps its own answer.
        if (givenNames.Count > 0 && named.Count == 0 && unknownNames.Count == givenNames.Count)
        {
            NoteNamedNoPage(course.Code, section,
                unknownNames.Count == 1 ? "1 name matched no page" : $"{unknownNames.Count} names matched no page");
            throw new AssistRefusal(unknownNames.Count == 1
                ? AssistWording.NoPageCalled(course.Code, section.ToString(), unknownNames[0])
                : AssistWording.NoPagesCalled(course.Code, section.ToString(), AssistWording.ListingEither(unknownNames)));
        }

        // Dates choose classes IN CODE. A teacher's "every class from the 15th
        // onwards" is a comparison, and comparisons are exactly what a model
        // should never be doing on a teacher's behalf — the whole design moves
        // that work here.
        if (pageTitles.Count == 0 && (onOrAfter is not null || before is not null))
        {
            int dateMatched = 0;
            foreach (var page in pagesList.Where(p => p.IsClassPage))
            {
                if (page.Date is not { } date) continue;
                if (onOrAfter is { } start && date < start) continue;
                if (before is { } end && date >= end) continue;
                dateMatched++;
                if (chosen.Add(page.RelativePath)) named.Add(page);
            }
            if (dateMatched == 0 && named.Count == 0)
                problems.Add($"No class in {course.Code} Section {section} falls in that date range.");
        }

        // Paths: every page titled Key Links, and what this section's links to.
        var mustStay = new HashSet<string>(
            pagesList.Where(p => string.Equals(p.Title, "Key Links", StringComparison.OrdinalIgnoreCase)).Select(p => p.RelativePath),
            StringComparer.OrdinalIgnoreCase);
        if (pagesByTitle.TryGetValue("Key Links", out var klPage) && linksFrom.TryGetValue(klPage.RelativePath, out var klTargets))
        {
            foreach (var t in klTargets) mustStay.Add(t);
        }

        var linked = new List<PlannedPage>();
        var stoppedAt = new List<PlannedPage>();
        var kept = new List<PlannedKept>();
        int protectedLinked = 0;
        int stillNeeded = 0;

        if (isDraft) // unpublishing
        {
            var goingDown = new HashSet<string>(named.Select(p => p.RelativePath), StringComparer.OrdinalIgnoreCase);
            bool foundMore = true;
            while (foundMore)
            {
                foundMore = false;
                var candidates = new List<PlannedPage>();
                foreach (var path in goingDown)
                {
                    if (linksFrom.TryGetValue(path, out var targets))
                    {
                        foreach (var target in targets)
                        {
                            if (pagesByPath.TryGetValue(target, out var targetPage))
                                candidates.Add(targetPage);
                        }
                    }
                }

                foreach (var candidate in candidates)
                {
                    if (goingDown.Contains(candidate.RelativePath)) continue;
                    string? reason = ReasonToKeep(candidate, mustStay, referrers, goingDown, course);
                    if (reason != null) continue;
                    goingDown.Add(candidate.RelativePath);
                    linked.Add(candidate with { ViaLink = true });
                    foundMore = true;
                }
            }

            var keptSeen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var sweepCandidates = new List<PlannedPage>();
            foreach (var path in goingDown)
            {
                if (linksFrom.TryGetValue(path, out var targets))
                {
                    foreach (var target in targets)
                    {
                        if (pagesByPath.TryGetValue(target, out var targetPage))
                            sweepCandidates.Add(targetPage);
                    }
                }
            }

            foreach (var candidate in sweepCandidates)
            {
                // REPORTING, deliberately left collapsed: this feeds the
                // "N linked pages stay visible" sentence, and a page whose
                // flag cannot be read is counted among them. Erring towards
                // mentioning a page costs a teacher a second look; the sites
                // that decide to SKIP A WRITE are the ones that require
                // VisibilityIsCertain. The mac collapses here too.
                if (!candidate.IsVisibleToStudents) continue;
                // A page that IS going down is not "staying" -- two classes
                // named together link to each other, and the second must not
                // be reported as kept because it is a class (#342).
                if (goingDown.Contains(candidate.RelativePath)) continue;
                string? reason = ReasonToKeep(candidate, mustStay, referrers, goingDown, course);
                if (reason != null && keptSeen.Add(candidate.RelativePath))
                {
                    kept.Add(new PlannedKept(candidate, reason));
                    // A class has its own line ("stays visible, because it is
                    // a class of its own") and no count: the protected
                    // sentence below says index pages, curriculum and Key
                    // Links, and a class among them would make it false
                    // (#342 / mac #201).
                    if (reason.Contains("still links to it"))
                        stillNeeded++;
                    else if (reason != ClassOfItsOwn)
                        protectedLinked++;
                }
            }

            if (protectedLinked > 0)
                problems.Add($"{protectedLinked} linked page{(protectedLinked == 1 ? " was" : "s were")} left published: " +
                             "index pages, the curriculum, and the pages Key Links points at are never hidden.");

            if (stillNeeded > 0)
                problems.Add($"{stillNeeded} linked page{(stillNeeded == 1 ? " was" : "s were")} left published " +
                             "because another class students can still see links to " +
                             (stillNeeded == 1 ? "it" : "them") + ".");
        }
        else // publishing: ALWAYS takes what the pages link to (#420)
        {
            var seenLinked = new HashSet<string>(named.Select(p => p.RelativePath), StringComparer.OrdinalIgnoreCase);
            var queue = new Queue<PlannedPage>(named);
            while (queue.Count > 0)
            {
                var cur = queue.Dequeue();
                if (linksFrom.TryGetValue(cur.RelativePath, out var targets))
                {
                    foreach (var target in targets)
                    {
                        if (pagesByPath.TryGetValue(target, out var targetPage))
                        {
                            if (seenLinked.Add(targetPage.RelativePath))
                            {
                                if (!targetPage.IsClassPage)
                                {
                                    linked.Add(targetPage with { ViaLink = true });
                                    queue.Enqueue(targetPage);
                                }
                                else
                                {
                                    // The stop (#173): neither published
                                    // nor walked through, and named to the
                                    // teacher (#203).
                                    stoppedAt.Add(targetPage);
                                }
                            }
                        }
                    }
                }
            }
        }

        var changes = new List<PlannedChange>();
        var alreadyRight = new List<PlannedPage>();

        // "Already right" has to be a CONFIDENT reading on both lists. A page
        // whose flag this app will not read REPORTS as visible, and dropping it
        // into the already-right list would tell the teacher it was published
        // while the build went on holding it back — the residue this reader
        // exists to close (issue #140).
        foreach (var page in named)
        {
            if (page.IsVisibleToStudents == isPublish && page.VisibilityIsCertain)
            {
                alreadyRight.Add(page);
            }
            else
            {
                changes.Add(new PlannedChange(page, page.FrontmatterKey, WasVisible: page.IsVisibleToStudents, WillBeVisible: isPublish, BecauseLinked: false));
            }
        }

        foreach (var page in linked)
        {
            if (page.IsVisibleToStudents == isPublish && page.VisibilityIsCertain)
            {
                if (!named.Any(n => string.Equals(n.RelativePath, page.RelativePath, StringComparison.OrdinalIgnoreCase)))
                    alreadyRight.Add(page);
            }
            else
            {
                changes.Add(new PlannedChange(page, page.FrontmatterKey, WasVisible: page.IsVisibleToStudents, WillBeVisible: isPublish, BecauseLinked: true));
            }
        }

        // #308 (the mac's #186): ask the REAL writer now whether it can write
        // each change. A page whose settings have no column-0 place for the
        // new line is declined at the write, so promising it on the card —
        // or answering "already hidden" about it — would be the lie #186 was
        // about. Declined pages leave Changes and are named instead.
        var cannotBeAddedTo = new List<PlannedPage>();
        changes.RemoveAll(change =>
        {
            if (!WriterDeclines(change.Page.RelativePath, change.Key, draft: !change.WillBeVisible, section)) return false;
            cannotBeAddedTo.Add(change.Page);
            return true;
        });

        // A declined page stays exactly as it is, so the plan must not treat it
        // as published: left out here, the front page and the dates a class
        // brings are worked out from its CURRENT state (#308 review N-a — the
        // card could otherwise point the front page at a class that stays
        // hidden; the mac decides the landing page from what is visible).
        var allPlannedPages = WithoutDeclined(named.Concat(linked), cannotBeAddedTo);
        var inherited = InheritedDates(course, section, allPlannedPages, isDraft);

        var dateMoves = new List<PlannedDateMove>();
        foreach (var date in inherited)
        {
            if (pagesByPath.TryGetValue(date.RelativePath, out var p))
            {
                string introducingTitle = p.DisplayTitle;
                // Find introducing class title
                if (referrers.TryGetValue(p.RelativePath, out var refs))
                {
                    var introducingClass = refs.Where(r => r.IsClassPage && r.Date == date.New).FirstOrDefault();
                    if (introducingClass != null) introducingTitle = introducingClass.DisplayTitle;
                }
                dateMoves.Add(new PlannedDateMove(p, date.Current, date.New, introducingTitle));
            }
        }

        var changingPages = changes.Select(c => c.Page with { Draft = !c.WillBeVisible }).ToList();
        var index = IndexChangeFor(course, section, allPlannedPages, inherited);
        var dangling = DanglingAfter(course, section, allPlannedPages);

        return new PublishPlan
        {
            CourseCode = course.Code,
            SectionNumber = section,
            Publishes = isPublish,
            UnknownNames = unknownNames,
            NamedPages = named,
            Changes = changes,
            AlreadyRight = alreadyRight,
            Kept = kept,
            DateMoves = dateMoves,
            Destination = DestinationOf(course),
            Pages = changingPages,
            Problems = problems,
            InheritedDates = inherited,
            Index = index,
            Dangling = dangling,
            StoppedAtClasses = stoppedAt,
            CannotBeAddedTo = cannotBeAddedTo,
        };
    }

    /// <summary>
    /// The planned pages less the ones the writer declined, matched by PATH
    /// (#422): two pages can share a file name — two folders' <c>index.md</c>,
    /// a shared page and a section page — and matching by title took the
    /// other one out too, so the front page and the dangling-link warning
    /// were worked out as if it stayed as it was.
    /// </summary>
    /// <summary>The folder a planned page sits in, from the course folder ("Labs", "section1/All Classes").</summary>
    private string FolderOf(Course course, PlannedPage page)
    {
        string full = Path.GetFullPath(PagePaths.ResolveInside(_folder, page.RelativePath));
        string folder = Path.GetRelativePath(course.DirectoryPath, Path.GetDirectoryName(full)!).Replace('\\', '/');
        return folder == "." ? course.Code : folder;
    }

    /// <summary>A name as the contract compares names: trimmed, ignoring case, in one Unicode form.</summary>
    private static string ComparableName(string name) =>
        name.Trim().Normalize(System.Text.NormalizationForm.FormC).ToLowerInvariant();

    internal static List<PlannedPage> WithoutDeclined(IEnumerable<PlannedPage> planned, IEnumerable<PlannedPage> declined)
    {
        var declinedPaths = new HashSet<string>(declined.Select(p => PathKey(p.RelativePath)), StringComparer.OrdinalIgnoreCase);
        return planned.Where(p => !declinedPaths.Contains(PathKey(p.RelativePath))).ToList();

        static string PathKey(string relative) => relative.Replace('\\', '/');
    }

    /// <summary>
    /// Whether <see cref="PageFrontmatter.SetDraft"/> would decline this page
    /// for want of a column-0 place for the key (#308). A page that cannot be
    /// read is not "declined" here: the write reports it the way it always has.
    /// </summary>
    private bool WriterDeclines(string relativePath, string key, bool draft, int section)
    {
        try
        {
            string text = File.ReadAllText(PagePaths.ResolveInside(_folder, relativePath));
            return PageFrontmatter.SetDraft(text, key, draft, section).Edit.NoRoomForAKey;
        }
        catch { return false; }
    }

    /// <summary>
    /// The trail's count of pages a write left as they were (#308,
    /// <c>page settings left as they were</c>) — never which pages, and nothing
    /// when the count is 0.
    /// </summary>
    private static void NoteSettingsLeftAsTheyWere(string act, int pages, string courseCode, int section)
    {
        if (pages <= 0) return;
        ActivityTrail.Note(ActivityTrail.Event.PageSettingsLeftAsTheyWere,
            ActivityTrail.PageSettingsLeftAsTheyWereLine(act, pages), courseCode, section);
    }

    /// <summary>The reason an unpublish leaves a linked class up (#342 / mac #201).</summary>
    private const string ClassOfItsOwn = "it is a class of its own.";


    private static string? ReasonToKeep(
        PlannedPage page,
        HashSet<string> mustStay,
        Dictionary<string, List<PlannedPage>> referrers,
        HashSet<string> goingDown,
        Course course)
    {
        if (page.IsFolderIndex)
            return "it is a folder's landing page, which following links never takes down.";
        if (mustStay.Contains(page.RelativePath))
            return "it is in this section's Key Links.";
        if (PagePaths.IsCurriculum(course.DirectoryPath, page.RelativePath))
            return "it is a curriculum page.";
        // An unpublish never takes a class down by following a link, and does
        // not walk into one (#342 / mac #201, mirroring #173's publish stop).
        // After the curriculum check and BEFORE the referrer test: the order
        // is pinned on the mac -- a class in Key Links keeps its Key Links
        // reason, and a class a visible page links to gets THIS reason.
        if (page.IsClassPage)
            return ClassOfItsOwn;
        if (PageStillLinking(page, referrers, goingDown) is { } referrer)
            return $"“{referrer.DisplayTitle}” still links to it.";
        return null;
    }

    private static PlannedPage? PageStillLinking(
        PlannedPage page,
        Dictionary<string, List<PlannedPage>> referrers,
        HashSet<string> goingDown)
    {
        if (referrers.TryGetValue(page.RelativePath, out var list))
        {
            foreach (var referrer in list)
            {
                if (goingDown.Contains(referrer.RelativePath)) continue;
                if (!referrer.IsVisibleToStudents) continue;
                return referrer;
            }
        }
        return null;
    }


    /// <summary>
    /// The pages one page links to, adding any unresolvable links to
    /// <paramref name="problems"/> once each.
    /// </summary>
    private List<string> Links(Course course, int section, string page, List<string> problems)
    {
        var found = new List<string>();
        string text;
        try { text = File.ReadAllText(page); } catch { return found; }

        foreach (var resolution in WikiLinks.Resolve(
                     WikiLinks.PageLinks(text), course.DirectoryPath, section, page))
        {
            if (resolution.Problem is { } problem)
            {
                if (!problems.Contains(problem)) problems.Add(problem);
                continue;
            }
            if (resolution.Outcome == LinkOutcome.Resolved) found.Add(resolution.Path!);
        }
        return found;
    }

    /// <summary>
    /// Pages taking the date of the class that INTRODUCED them.
    ///
    /// The rule is the build's own, and the teacher's: a shared page carries
    /// the date of the earliest class that links to it. So a concept first
    /// used in Unit 2, Day 3 and used again in Unit 2, Day 4 keeps Day 3's
    /// date — publishing Day 4 finds Day 3 is still the earliest linker and
    /// leaves it where it is.
    ///
    /// Taking the EARLIEST linker rather than skipping anything with more than
    /// one is what makes that hold in every case. Skipping would leave a page
    /// that two classes share on whatever date it happened to have — right
    /// only if some earlier publish had already set it, and silently wrong for
    /// a page that was never dated, or whose date came from a copy-paste.
    /// </summary>
    private List<PlannedDate> InheritedDates(
        Course course, int section, IReadOnlyList<PlannedPage> pages, bool draft)
    {
        var inherited = new List<PlannedDate>();
        if (draft) return inherited;   // hiding a class never re-dates anything

        LinkGraph graph;
        try { graph = LinkGraph.Build(course.DirectoryPath, section); }
        catch { return inherited; }

        var classPaths = new HashSet<string>(
            ClassPages(course, section).Select(Path.GetFullPath), StringComparer.OrdinalIgnoreCase);

        // A page in the published-pages record has been on a site students
        // could reach and KEEPS its date (#392, mac #379; Russell's decision 4):
        // "hidden now" no longer means "never published".
        var publishedBefore = LinksChecklist.PublishedPlaces(course.DirectoryPath, section);

        // Find all targets reachable from named class pages
        var reachableTargets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var named in pages.Where(p => !p.ViaLink))
        {
            string classPath;
            try { classPath = PagePaths.ResolveInside(_folder, named.RelativePath); }
            catch { continue; }
            if (!classPaths.Contains(Path.GetFullPath(classPath))) continue;   // only classes anchor dates

            var queue = new Queue<string>();
            var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { Path.GetFullPath(classPath) };
            queue.Enqueue(classPath);

            while (queue.Count > 0)
            {
                var cur = queue.Dequeue();
                foreach (string target in graph.TargetsOf(cur))
                {
                    string targetFull = Path.GetFullPath(target);
                    if (!visited.Add(targetFull)) continue;
                    if (classPaths.Contains(targetFull)) continue;   // a class is not material
                    queue.Enqueue(target);
                    reachableTargets.Add(targetFull);
                }
            }
        }

        foreach (string target in reachableTargets)
        {
            // Find earliest class date reaching target
            var q = new Queue<string>();
            var visitedSources = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { target };
            q.Enqueue(target);
            DateOnly? earliest = null;

            while (q.Count > 0)
            {
                var cur = q.Dequeue();
                foreach (string source in graph.SourcesOf(cur))
                {
                    string sourceFull = Path.GetFullPath(source);
                    if (classPaths.Contains(sourceFull))
                    {
                        if (DateOf(course, section, sourceFull) is { } d)
                        {
                            if (earliest is null || d < earliest) earliest = d;
                        }
                    }
                    else
                    {
                        if (visitedSources.Add(sourceFull))
                        {
                            q.Enqueue(source);
                        }
                    }
                }
            }

            if (earliest is not { } owner) continue;

            string place = Path.ChangeExtension(Path.GetRelativePath(course.DirectoryPath, target), null)
                .Replace(Path.DirectorySeparatorChar, '/');
            if (publishedBefore.Contains(LinksChecklist.Key(place))) continue;

            // Already out where students can see it — leave it alone.
            //
            // CERTAINLY out, that is. A page whose flag this app will not read
            // is REPORTED visible, and it is about to be published by the
            // change list; skipping it here would publish it with whatever
            // date it happened to have rather than the day of the class that
            // brought it. So only a confident "visible" skips.
            bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, target);
            try
            {
                var visibility = PageFrontmatter.Visibility(File.ReadAllText(target), section);
                if (visibility is PageVisibility.Visible or PageVisibility.SaysNothing) continue;
            }
            catch { }

            var current = DateOf(course, section, target);
            if (current == owner) continue; // already on this date

            inherited.Add(new PlannedDate(
                Title: Path.GetFileNameWithoutExtension(target),
                RelativePath: Relative(target),
                FrontmatterKey: PageFrontmatter.CreatedKeyFor(section, sectionLocal),
                Current: current,
                New: owner,
                MeetingNumber: 0));
        }

        return inherited;
    }



    /// <summary>
    /// What the section's front page should say once this plan is applied.
    ///
    /// Computed from the resulting state rather than "whatever we just
    /// published", which is what makes it right in both directions:
    /// publishing an older missed class does not drag the front page
    /// backwards, and hiding the newest one falls back to the previous
    /// without a line of code for the case.
    /// </summary>
    private IndexChange? IndexChangeFor(
        Course course, int section, IReadOnlyList<PlannedPage> pages, IReadOnlyList<PlannedDate> inherited)
    {
        var classPages = ClassPages(course, section);
        if (classPages.Count == 0) return null;

        var drafts = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        foreach (var page in pages)
        {
            try { drafts[Path.GetFullPath(PagePaths.ResolveInside(_folder, page.RelativePath))] = page.Draft; }
            catch { }
        }
        var dates = new Dictionary<string, DateOnly>(StringComparer.OrdinalIgnoreCase);
        foreach (var date in inherited)
        {
            try { dates[Path.GetFullPath(PagePaths.ResolveInside(_folder, date.RelativePath))] = date.New; }
            catch { }
        }

        string? newest = SectionIndex.MostRecentPublished(course, section, classPages, drafts, dates);
        if (newest is null) return null;   // nothing published: leave the front page alone

        string indexPath = SectionIndex.PathFor(course, section);
        string indexText;
        try { indexText = File.ReadAllText(indexPath); }
        catch { return null; }

        var pointer = PointerFor(course, section, newest);
        DateOnly toDate = DateOf(course, section, newest) ?? default;

        return new IndexChange(
            RelativePath: Relative(indexPath),
            FromClass: SectionIndex.CurrentlyShowing(indexText, pointer.ClassTitles),
            ToClass: pointer.PointAt,
            FromDate: PageFrontmatter.CreatedOn(indexText, section, isSectionLocal: true),
            ToDate: toDate,
            HeadingMissing: !SectionIndex.CanBePointed(indexText, pointer),
            Pointer: pointer);
    }

    /// <summary>
    /// Links a student would meet that lead nowhere, if this plan went ahead.
    ///
    /// Following links one hop is not the same as leaving the site coherent:
    /// publish a class and its concepts, and the curriculum expectations those
    /// concepts point at are still hidden. Rather than expanding the change to
    /// cover them — safe when publishing, dangerous when hiding, since each
    /// extra hop can swallow a page some published class still needs — the
    /// plan reports the consequence and lets the teacher decide.
    /// </summary>
    private List<DanglingLink> DanglingAfter(Course course, int section, IReadOnlyList<PlannedPage> pages)
    {
        LinkGraph graph;
        try { graph = LinkGraph.Build(course.DirectoryPath, section); }
        catch { return new List<DanglingLink>(); }

        var planned = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
        foreach (var page in pages)
        {
            try { planned[Path.GetFullPath(PagePaths.ResolveInside(_folder, page.RelativePath))] = page.Draft; }
            catch { }
        }

        return graph.DanglingLinks(path =>
        {
            string full = Path.GetFullPath(path);
            if (planned.TryGetValue(full, out bool willBeDraft)) return willBeDraft;
            try
            {
                // "Hidden" is the question here, and the file answers the
                // opposite one, so it has to be read in draft terms. REPORTING,
                // so a flag this app will not read collapses to visible.
                return PageFrontmatter.StoredDraft(File.ReadAllText(full), section) ?? false;
            }
            catch { return false; }
        });
    }


    /// <summary>The section's link graph, for the standalone consistency check.</summary>
    public (LinkGraph Graph, Func<string, bool> IsHidden) Inspect(Course course, int section)
    {
        var graph = LinkGraph.Build(course.DirectoryPath, section);
        return (graph, path =>
        {
            try
            {
                // "Hidden" is the question here, and the file answers the
                // opposite one, so it has to be read in draft terms. REPORTING,
                // so a flag this app will not read collapses to visible.
                return PageFrontmatter.StoredDraft(File.ReadAllText(path), section) ?? false;
            }
            catch { return false; }
        }
        );
    }


    private PlannedPage Plan(Course course, int section, string pagePath, bool draft, bool viaLink)
    {
        bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, pagePath);
        string key = PageFrontmatter.PublishKeyFor(section, sectionLocal);
        string text = File.ReadAllText(pagePath);
        bool isFolderIndex = Path.GetFileName(pagePath).Equals("index.md", StringComparison.OrdinalIgnoreCase);
        // The shared rule (contracts/class-planning.json -> classFolder), against
        // the path relative to the SECTION. This used to test the whole absolute
        // directory string, so a teacher whose working folder was
        // C:\Users\x\Classroom\ made every page in every course a class page;
        // Relative(pagePath) closed that, and PathWithinSection closes the rest
        // of it — see the helper, and the mac's pathWithinSection it mirrors.
        bool isClassPage = ClassFolderRule.IsClassPage(
            PathWithinSection(course, section, pagePath),
            ClassFolderRule.Names(course.Configuration.ClassFolder, course.Configuration.PerSectionFolders));
        // Read the way the BUILT SITE reads it, which is all four keys in build
        // order — never branching on where the page lives, since a page's
        // folder decides which key is WRITTEN and nothing about what it says.
        var visibility = PageFrontmatter.Visibility(text, section);
        return new PlannedPage(
            Title: Path.GetFileNameWithoutExtension(pagePath),
            RelativePath: Relative(pagePath),
            FrontmatterKey: key,
            CurrentValue: PageFrontmatter.StoredDraft(text, section),
            Draft: draft,
            ViaLink: viaLink,
            Date: PageFrontmatter.CreatedOn(text, section, sectionLocal),
            DisplayTitle: PagePaths.DisplayTitle(pagePath, text),
            IsFolderIndex: isFolderIndex,
            IsClassPage: isClassPage,
            IsSectionLocal: sectionLocal,
            VisibilityIsCertain: visibility != PageVisibility.CannotTell);
    }


    /// <summary>
    /// The one class taught on a given day, or a refusal that says what is
    /// there instead.
    ///
    /// "Publish tomorrow's class" is the commonest thing a teacher will ask
    /// for, and it turns on finding exactly one page — so an empty day and a
    /// double-booked day both have to be said plainly rather than guessed
    /// through.
    /// </summary>
    public string ClassOn(Course course, int sectionNumber, DateOnly date)
    {
        var matches = ClassPages(course, sectionNumber)
            .Where(p => DateOf(course, sectionNumber, p) == date)
            .ToList();

        if (matches.Count == 1) return matches[0];
        if (matches.Count > 1)
            throw new AssistRefusal(
                $"{course.Code} Section {sectionNumber} has {matches.Count} classes on {DateText.Iso(date)} — " +
                Humanize(matches.Select(m => "“" + Path.GetFileNameWithoutExtension(m) + "”")) +
                ". Say which one you mean.");

        var dated = ClassPages(course, sectionNumber)
            .Select(p => DateOf(course, sectionNumber, p))
            .Where(d => d is not null).Select(d => d!.Value).OrderBy(d => d).ToList();
        string nearby = dated.Count == 0
            ? "None of its classes have dates."
            : $"Its classes run {DateText.Iso(dated[0])} to {DateText.Iso(dated[^1])}.";
        throw new AssistRefusal(
            $"{course.Code} Section {sectionNumber} has no class on {DateText.Iso(date)}. {nearby}");
    }

    /// <summary>
    /// Rebuild and republish a section, changing no content at all.
    ///
    /// Without this there was no way to ask for a deploy on its own, so a real
    /// session ended up calling publish on a page that happened to need no
    /// changes, purely to trigger a rebuild. That only worked by luck.
    /// </summary>
    /// <summary>
    /// Put a section's built site where students can reach it.
    ///
    /// Deliberately its own operation, never a step inside publishing. The
    /// teacher asked for two things that sound contradictory — that they stay
    /// in control of what students see, and that the assistant be able to
    /// deploy — and the reconciliation is that deploying is never a SIDE
    /// EFFECT. Changing pages rebuilds the preview and stops there; putting it
    /// in front of students takes a separate, deliberate ask.
    /// </summary>
    public async Task<AssistResult> Deploy(string courseCode, int sectionNumber,
                                           IProgress<string>? progress = null,
                                           CancellationToken cancellation = default)
    {
        var course = Course(courseCode);
        // A course kept for reference is never deployed (#241, door 3, the
        // headless deploy): first, before anything else is asked or started.
        if (ReferenceCourse.IsKeptForReference(course))
            throw new AssistRefusal(AssistWording.DeployRefusedForAReferenceCourse(ReferenceCourse.ShownCode(course)));
        int section = Section(course, sectionNumber);
        RefuseIfAnotherProgramStandsInTheWay(course, section, "an assistant's deploy");

        var destinations = course.Configuration.AllDeployDestinations;

        // A Pages-scoped Cloudflare token cannot list its own account, so
        // the account id lives in Plantoir's settings and only the app —
        // never this headless process — can pass it. Checked against EVERY
        // configured destination, primary or additional: a redundancy
        // target the assistant cannot reach is refused up front rather than
        // silently skipped partway through a multi-destination deploy.
        foreach (var destination in destinations)
        {
            if (destination.Type != "cloudflare_pages") continue;
            bool isPrimary = destination.Type == course.Configuration.DeployTarget;
            throw new AssistRefusal(
                $"{course.Code} {(isPrimary ? "deploys" : "also deploys")} to Cloudflare Pages, which needs " +
                "the account ID Plantoir stores. Deploy this section from Plantoir instead.");
        }

        // With no site marker, deploy.py asks what to call the website — a
        // prompt on stdin, which is closed here, so the launcher would die
        // with an unhandled EOFError minutes into a build. Checked for
        // every destination up front, same reasoning as ScheduledDeploy.Problem.
        foreach (var destination in destinations)
        {
            if (destination.Type == "local_folder") continue;
            if (Models.DeployCommand.HasDeployedBefore(section, course, destination.Type)) continue;
            bool isPrimary = destination.Type == course.Configuration.DeployTarget;
            string destinationName = Models.DeployCommand.DestinationDescription(destination);
            throw new AssistRefusal(isPrimary
                ? $"{course.Code} Section {section} has never been deployed to {destinationName}, so deploying it " +
                  "there asks what to call the website — and that can only be answered in Plantoir. Deploy it to " +
                  $"{destinationName} once from there, and I can do it after that."
                : $"{course.Code} Section {section} has never been deployed to {destinationName}, so deploying " +
                  "it there asks what to call that site — and that can only be answered in Plantoir. Deploy it " +
                  "there once from Plantoir, and I can do it after that.");
        }

        progress?.Report($"Building Section {section} of {course.Code}…");
        using var claim = ClaimTheBuildOrDecline(course, section, "an assistant's deploy");
        var build = await _launcher.Run("preview", new[] { course.Code, section.ToString(), "--build-only", "--non-interactive" },
                                        _folder, progress, cancellation);
        if (build.NeededAnAnswer)
            // The build leg's question is the deploy's, not a destination's:
            // no destination was reached (the #132 lesson - keep the legs apart).
            return new AssistResult(false,
                AppendingFindings(course, section, build, 
                    AssistWording.DeployNeedsAnAnswer(course.Code, section.ToString())), null);
        if (!build.Succeeded)
            return new AssistResult(false,
                // What the build said about the folders belongs HERE most of
                // all: a build that failed because the front page is missing
                // is the case where the finding is the cause.
                AppendingFindings(course, section, build, 
                    $"The build failed, so nothing was deployed. {build.Message}"),
                null);

        // Every destination's own deploy — one FAILING does not stop the
        // others, the whole point of a course having more than one.
        //
        // This is a SEPARATE loop from MultiDestinationDeployRunner.RunAsync,
        // not a reuse of it, and that is a deliberate, not accidental,
        // divergence from the mac's own AssistSiteWork.deploy(), which calls
        // "the same sequencer the Deploy button uses." RunAsync is built on
        // ScriptRunner — ConPTY, live progress notifications, a WinUI
        // SynchronizationContext — which is GUI-only infrastructure this
        // process (plantoir-mcp.exe, a separate headless process with no
        // window) cannot use. ILauncherRunner is the existing, narrower
        // abstraction this whole class already runs every operation through
        // for exactly that reason. The one-build-then-N-deploys shape and the
        // "a failure never stops the others" rule ARE kept in step by hand
        // here — found and reasoned through in a parity audit, not missed —
        // rather than by sharing code, because forcing the two abstractions
        // together would be a larger, riskier change than this feature
        // warranted, with no way to verify it against the real MCP process
        // in this environment. If this drifts from RunAsync's own rules
        // again, that is the trade being made.
        var outcomeLegs = new List<(Models.CourseConfiguration.DeployDestination Destination, bool Succeeded)>();
        var askedAt = new List<Models.CourseConfiguration.DeployDestination>();
        foreach (var destination in destinations)
        {
            // unattended: --non-interactive, so a question refuses with exit 3
            // instead of waiting for ever on a terminal nobody reads (#391).
            var arguments = Models.DeployCommand.Arguments(course.Code, section, destination, unattended: true);
            progress?.Report($"Deploying to {Models.DeployCommand.DestinationDescription(destination)}…");
            var deployed = await _launcher.Run("deploy", arguments, _folder, progress, cancellation);
            outcomeLegs.Add((destination, deployed.Succeeded));
            if (deployed.NeededAnAnswer) askedAt.Add(destination);
        }

        // A destination that stopped at a question is named, and so is where
        // it DID go out (#391: wording.deployNeedsAnAnswer for one destination,
        // deployNeedsAnAnswerAt + deployWentOutTo for several).
        if (askedAt.Count > 0)
        {
            string answerMessage;
            if (destinations.Count == 1)
            {
                answerMessage = AssistWording.DeployNeedsAnAnswer(course.Code, section.ToString());
            }
            else
            {
                string Names(IEnumerable<Models.CourseConfiguration.DeployDestination> legs) =>
                    string.Join(" and ", legs.Select(Models.DeployCommand.DestinationDescription));
                answerMessage = AssistWording.DeployNeedsAnAnswerAt(course.Code, section.ToString(), Names(askedAt));
                var wentOut = outcomeLegs.Where(leg => leg.Succeeded).Select(leg => leg.Destination).ToList();
                if (wentOut.Count > 0) answerMessage += " " + AssistWording.DeployWentOutTo(Names(wentOut));
            }
            return new AssistResult(outcomeLegs.Any(leg => leg.Succeeded),
                AppendingFindings(course, section, build, answerMessage), null);
        }

        bool anySucceeded = outcomeLegs.Any(leg => leg.Succeeded);
        var failedDestinations = outcomeLegs.Where(leg => !leg.Succeeded).Select(leg => leg.Destination).ToList();
        var outcome = new MultiDestinationDeployRunner.Outcome(anySucceeded, failedDestinations);
        var result = MultiDestinationDeployRunner.Result(course.Code, section.ToString(), destinations.Count, outcome);
        // Findings come from the BUILD, not from a destination's upload: every
        // destination publishes the same built site, and the checks run inside
        // the build. Said after the outcome, never instead of it.
        return result with
        {
            Message = AppendingFindings(course, section, build, result.Message),
        };
    }

    public async Task<AssistResult> RebuildPreview(string courseCode, int sectionNumber,
                                                   IProgress<string>? progress = null,
                                                   CancellationToken cancellation = default)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        RefuseIfAnotherProgramStandsInTheWay(course, section, "an assistant's rebuild");

        progress?.Report($"Building a preview of Section {section} of {course.Code}…");
        using var claim = ClaimTheBuildOrDecline(course, section, "an assistant's rebuild");
        var build = await _launcher.Run("preview", new[] { course.Code, section.ToString(), "--build-only", "--non-interactive" },
                                        _folder, progress, cancellation);
        if (build.NeededAnAnswer)
            return new AssistResult(false,
                AppendingFindings(course, section, build, 
                    AssistWording.PreviewBuildNeedsAnAnswer(course.Code, section.ToString())), null);
        return build.Succeeded
            ? new AssistResult(true,
                AppendingFindings(course, section, build, 
                    $"Rebuilt the preview of {course.Code} Section {section}. No content was changed. " +
                    "Look it over in Plantoir, and deploy it there when you're happy."), null)
            : new AssistResult(false,
                AppendingFindings(course, section, build, 
                    $"Nothing was changed, and the preview couldn’t be built. {build.Message}"), null);
    }

    /// <summary>
    /// Where this course's site goes, named the way a teacher would name it.
    ///
    /// Public because the briefing needs the same answer: it used to say "the
    /// folder you publish into", which is a description rather than a
    /// destination — a teacher with two courses going to two different folders
    /// learns nothing from it. The folder is named.
    /// </summary>
    public static string DestinationOf(Course course) =>
        course.Configuration.DeploysToLocalFolder ? course.Configuration.DeployFolderPath
        : course.Configuration.DeploysToCloudflare ? "Cloudflare Pages"
        : "Netlify";

    // ---- Doing it --------------------------------------------------------

    /// <summary>
    /// Carry out a plan the teacher has agreed to: back up, change the flags,
    /// rebuild, publish.
    ///
    /// The backup is not optional and is not a separate tool call. Row 106
    /// built whole-course backups for precisely this scenario — "teachers will
    /// be encouraged to use an LLM for bulk edits, and an LLM can make a mess
    /// that is hard to undo" — so undo is a real button here, not advice.
    /// </summary>
    public async Task<AssistResult> Apply(PublishPlan plan, bool preview = true, IProgress<string>? progress = null,
                                          CancellationToken cancellation = default)
    {
        var course = Course(plan.CourseCode);
        int section = Section(course, plan.SectionNumber);

        string act = plan.Hiding ? "hiding pages" : "publishing pages";
        if (plan.ChangesNothing && !plan.Publishes)
        {
            NoteSettingsLeftAsTheyWere(act, plan.CannotBeAddedTo.Count, course.Code, section);
            return new AssistResult(true, plan.CannotBeAddedToSentence ?? "Nothing needed changing.", null);
        }

        // Anything that would stop the build has to be found NOW, before the
        // backup and the edits. Failing at the last step would leave the
        // teacher with changed files and a refusal — the worst of the orders.
        if (plan.Publishes) RefuseIfPlantoirIsBuilding(course);

        string backup;
        try { backup = BackUpOnceForThisConversation(course, plan.SectionNumber, progress); }
        catch (Exception error)
        {
            // No backup, no edits. This is the one step that has no fallback.
            throw new AssistRefusal(
                $"{course.Code} couldn’t be backed up, so nothing was changed: {error.Message}");
        }

        // PAST TENSE, and "unpublished" rather than "hid". This clause is
        // read back inside AssistWording.Undid — "Earlier, you {change}. Then
        // you asked me to undo that…" — so a gerund here puts a broken
        // sentence in front of the teacher at the one moment they are
        // checking that the right thing was put back.
        // The label names what the plan WILL write: a page the writer declined
        // at plan time is named in the reply, not "unpublished" here (#308).
        var declinedAtPlan = new HashSet<string>(plan.CannotBeAddedTo.Select(p => p.RelativePath), StringComparer.OrdinalIgnoreCase);
        var labelled = plan.Named.Where(p => !declinedAtPlan.Contains(p.RelativePath)).ToList();
        using var recording = UndoHistory.Record(_undo,
            $"{(plan.Hiding ? "unpublished" : "published")} " +
            $"{Humanize((labelled.Count > 0 ? labelled : plan.Named.ToList()).Select(p => "“" + p.Title + "”"))} " +
            $"in {course.Code} Section {section}");

        var changed = new List<string>();
        var declined = plan.CannotBeAddedTo.Select(p => p.DisplayTitle).ToList();
        foreach (var page in plan.Changing)
        {
            // Named as it happens, so a teacher watching the conversation
            // sees the work go by page by page rather than a silence with
            // a count at the end.
            progress?.Report($"Editing “{page.Title}”…");
            string full = PagePaths.ResolveInside(_folder, page.RelativePath);
            string text = File.ReadAllText(full);
            var (updated, edit) = PageFrontmatter.SetDraft(text, page.FrontmatterKey, page.Draft, section);
            // Edited since the plan into a shape with no room: named, never
            // counted as done (#308).
            if (edit.NoRoomForAKey) { declined.Add(page.DisplayTitle); continue; }
            if (!edit.Changed) continue;
            Save(full, updated);
            changed.Add(page.Title);
        }
        if (changed.Count > 0)
            progress?.Report($"Changed {changed.Count} page{(changed.Count == 1 ? "" : "s")}.");
        NoteSettingsLeftAsTheyWere(act, declined.Count, course.Code, section);

        // Pages only this class uses take its date.
        string tail = SiblingTimeAndOffset(course, section, ClassPages(course, section));
        foreach (var date in plan.InheritedDates.Where(d => d.WillChange))
        {
            try
            {
                string full = PagePaths.ResolveInside(_folder, date.RelativePath);
                var (updated, moved) = PageFrontmatter.SetCreated(
                    File.ReadAllText(full), date.FrontmatterKey, date.New, tail);
                if (moved) Save(full, updated);
            }
            catch { }
        }

        // And the front page catches up with what is now published.
        if (plan.Index is { WillChange: true } index) ApplyIndexChange(index, tail);

        recording.Done();

        if (!plan.Publishes)
            return new AssistResult(true, Summary(changed, previewed: false, course.Code, section, plan.Hiding, declined), backup);

        // Publishing builds a PREVIEW, and stops there.
        //
        // Deploying is a separate request with its own tool and its own yes —
        // it is not something publishing does on the way past. That
        // separation is the point: a teacher who asked for tomorrow's class to
        // be published has not asked for it to be put in front of students,
        // and the two should never be one keystroke apart.
        //
        // Every remaining sharp edge lives on the far side of that line too —
        // the site-name prompt, the Cloudflare account, the first publish, the
        // multi-minute upload — so the safety valve and the simplification are
        // the same decision.
        //
        // `preview` is false when the caller (the assistant chat window) is
        // about to put its OWN visible rebuild on screen — see
        // AssistAgent.RunTool's `arguments["preview"] = false` for
        // publish_pages/unpublish_pages. Building here too would race that
        // rebuild for the same output folder, and a failure from this hidden
        // build would hand the model a message to restate in the chat, which
        // is exactly the "every line of the build spews into the reply" bug.
        // So when told not to build, this returns the plain summary and
        // leaves the one visible build to the app.
        if (!preview)
            return new AssistResult(true, Summary(changed, previewed: false, course.Code, section, plan.Hiding, declined), backup);

        // The pages are already written: Markdown never conflicts with a
        // build, so only the REBUILD is declined when another program is
        // building, publishing or previewing this course (#289), and the note
        // where the preview would have been refreshed says so.
        using var claim = ClaimTheBuildUnlessDeclined(course, section, "an assistant's rebuild after a change");
        if (claim is null)
            return new AssistResult(true,
                Summary(changed, previewed: false, course.Code, section, plan.Hiding, declined) + " " + AssistWording.CourseIsBusy(course.Code),
                backup);
        progress?.Report($"Building a preview of Section {section} of {course.Code}…");
        var build = await _launcher.Run("preview", new[] { course.Code, section.ToString(), "--build-only", "--non-interactive" },
                                        _folder, progress, cancellation);
        if (!build.Succeeded)
            return new AssistResult(false,
                $"{WhatSurvived(changed)}, but the preview couldn’t be built. {AssistWording.WhereTheOutputIs}" +
                (declined.Count > 0 ? " " + AssistWording.PagesWhoseSettingsCannotBeAddedTo(declined) : ""), backup);

        return new AssistResult(true, Summary(changed, previewed: true, course.Code, section, plan.Hiding, declined), backup);
    }

    /// <summary>
    /// Plan a publish or unpublish operation across a whole unit.
    /// </summary>
    public WholeUnitPlanResult PlanWholeUnit(string courseCode, int sectionNumber, int unit, bool publishing)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);

        var allMarkdown = PagePaths.MarkdownPages(course.DirectoryPath, section);
        var unitPages = new List<PlannedPage>();
        foreach (var p in allMarkdown)
        {
            var planned = Plan(course, section, p, draft: !publishing, viaLink: false);
            if (planned.IsClassPage && course.Configuration.Naming.Parse(planned.Title) is { } ud && ud.Unit == unit)
            {
                unitPages.Add(planned);
            }
        }

        if (unitPages.Count == 0)
        {
            return new WholeUnitPlanResult(
                HasPages: false,
                MovingCount: 0,
                PlanText: null,
                Summary: null,
                AlreadyDoneSentence: null,
                ErrorMessage: $"I can’t find any class pages in {course.Configuration.UnitWord} {unit} of {course.Code} Section {section}.");
        }

        // Only the ones that would actually move, ordered highest day first (matching Swift)
        unitPages = unitPages.OrderByDescending(p => course.Configuration.Naming.Parse(p.Title)?.Day ?? 0).ToList();

        var moving = new List<string>();
        var declined = new List<string>();
        foreach (var p in unitPages)
        {
            // And a page whose flag this app will not read counts as moving,
            // for the reason above: it reports visible and the build may be
            // hiding it, so "the unit has already been published" would be a
            // sentence nobody can stand behind.
            if (p.IsVisibleToStudents != publishing || !p.VisibilityIsCertain)
            {
                // A page the writer will decline is NAMED, never counted as
                // moving or as already done (#308, the mac's #186).
                if (WriterDeclines(p.RelativePath, p.FrontmatterKey, draft: !publishing, section))
                    declined.Add(p.DisplayTitle);
                else
                    moving.Add(p.DisplayTitle);
            }
        }
        string? declinedSentence = declined.Count > 0 ? AssistWording.PagesWhoseSettingsCannotBeAddedTo(declined) : null;

        if (moving.Count == 0 && declinedSentence is not null)
        {
            return new WholeUnitPlanResult(
                HasPages: true,
                MovingCount: 0,
                PlanText: null,
                Summary: null,
                AlreadyDoneSentence: declinedSentence,
                ErrorMessage: null);
        }

        if (moving.Count == 0)
        {
            string already = publishing
                ? AssistWording.UnitAlreadyPublished(course.Configuration.UnitWord, unit)
                : AssistWording.UnitAlreadyHidden(course.Configuration.UnitWord, unit);
            return new WholeUnitPlanResult(
                HasPages: true,
                MovingCount: 0,
                PlanText: null,
                Summary: null,
                AlreadyDoneSentence: already,
                ErrorMessage: null);
        }

        string word = moving.Count == 1 ? "class" : "classes";
        string becoming = publishing ? "visible" : "hidden";
        string startPage = publishing ? moving[^1] : moving[0];
        string startingPhrase = publishing ? "starting at" : "starting from";

        var lines = new List<string>();
        lines.Add($"{course.Code} Section {section}: {(publishing ? "publishing" : "unpublishing")} {course.Configuration.UnitWord} {unit}.");
        lines.Add("");
        lines.Add($"{moving.Count} {word} would become {becoming}, {startingPhrase} “{startPage}”.");
        if (publishing)
        {
            lines.Add("Everything they link to becomes visible with them.");
        }
        else
        {
            lines.Add("Pages only they use come down too; anything still needed stays.");
        }
        if (declinedSentence is not null)
        {
            lines.Add("");
            lines.Add(declinedSentence);
        }

        string summary = $"Worked out what {(publishing ? "publishing" : "unpublishing")} {course.Configuration.UnitWord} {unit} would do.";
        string planText = string.Join("\n", lines);
        return new WholeUnitPlanResult(
            HasPages: true,
            MovingCount: moving.Count,
            PlanText: planText,
            Summary: summary,
            AlreadyDoneSentence: null,
            ErrorMessage: null);
    }

    /// <summary>
    /// Apply a publish or unpublish operation across a whole unit, one class page
    /// at a time in order, recorded as a single batch on the undo list.
    /// </summary>
    public async Task<AssistResult> ApplyWholeUnit(
        string courseCode, int sectionNumber, int unit, bool publishing, bool preview,
        IProgress<string>? progress = null, CancellationToken cancellation = default)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);

        var allMarkdown = PagePaths.MarkdownPages(course.DirectoryPath, section);
        var unitPages = new List<PlannedPage>();
        foreach (var p in allMarkdown)
        {
            var planned = Plan(course, section, p, draft: !publishing, viaLink: false);
            if (planned.IsClassPage && course.Configuration.Naming.Parse(planned.Title) is { Unit: var u } && u == unit)
            {
                unitPages.Add(planned);
            }
        }

        if (unitPages.Count == 0)
            return new AssistResult(false, $"I can’t find any class pages in {course.Configuration.UnitWord} {unit} of {course.Code} Section {section}.", null);

        // Highest day first to take a unit down; Day 1 first to put it up.
        unitPages = publishing
            ? unitPages.OrderBy(p => course.Configuration.Naming.Parse(p.Title)?.Day ?? 0).ToList()
            : unitPages.OrderByDescending(p => course.Configuration.Naming.Parse(p.Title)?.Day ?? 0).ToList();

        if (publishing) RefuseIfPlantoirIsBuilding(course);

        string backup;
        try { backup = BackUpOnceForThisConversation(course, section); }
        catch (Exception error)
        {
            throw new AssistRefusal($"{course.Code} couldn’t be backed up, so nothing was changed: {error.Message}");
        }

        string verb = publishing ? "published" : "unpublished";
        using var recording = UndoHistory.Record(_undo,
            $"{verb} {course.Configuration.UnitWord} {unit} in {course.Code} Section {section}");

        bool changedAnything = false;
        var changed = new List<string>();
        var declined = new List<string>();
        void Decline(string title)
        {
            if (!declined.Contains(title, StringComparer.OrdinalIgnoreCase)) declined.Add(title);
        }

        foreach (var page in unitPages)
        {
            var pagePlan = PlanPublish(
                course.Code, section, new[] { page.RelativePath }, draft: !publishing, publishes: publishing);
            foreach (var refused in pagePlan.CannotBeAddedTo) Decline(refused.DisplayTitle);

            if (pagePlan.ChangesNothing) continue;

            foreach (var change in pagePlan.Changing)
            {
                progress?.Report($"Editing “{change.Title}”…");
                string full = PagePaths.ResolveInside(_folder, change.RelativePath);
                string text = File.ReadAllText(full);
                var (updated, edit) = PageFrontmatter.SetDraft(text, change.FrontmatterKey, change.Draft, section);
                if (edit.NoRoomForAKey) { Decline(change.DisplayTitle); continue; }
                if (!edit.Changed) continue;
                Save(full, updated);
                if (!changed.Contains(change.Title)) changed.Add(change.Title);
                changedAnything = true;
            }

            string tail = SiblingTimeAndOffset(course, section, ClassPages(course, section));
            foreach (var date in pagePlan.InheritedDates.Where(d => d.WillChange))
            {
                try
                {
                    string full = PagePaths.ResolveInside(_folder, date.RelativePath);
                    var (updated, moved) = PageFrontmatter.SetCreated(
                        File.ReadAllText(full), date.FrontmatterKey, date.New, tail);
                    if (moved)
                    {
                        Save(full, updated);
                        changedAnything = true;
                    }
                }
                catch { }
            }

            if (pagePlan.Index is { WillChange: true } index)
            {
                ApplyIndexChange(index, tail);
                changedAnything = true;
            }
        }

        recording.Done();
        NoteSettingsLeftAsTheyWere(publishing ? "publishing pages" : "hiding pages", declined.Count, course.Code, section);
        string? declinedSentence = declined.Count > 0 ? AssistWording.PagesWhoseSettingsCannotBeAddedTo(declined) : null;

        if (!changedAnything)
        {
            // Never "already hidden" about pages the writer declined (#308).
            string already = declinedSentence ?? (publishing
                ? AssistWording.UnitAlreadyPublished(course.Configuration.UnitWord, unit)
                : AssistWording.UnitAlreadyHidden(course.Configuration.UnitWord, unit));
            return new AssistResult(true, already, backup);
        }

        string summary = $"{course.Configuration.UnitWord} {unit} was {verb}." +
                         (declinedSentence is null ? "" : " " + declinedSentence);

        if (!preview)
            return new AssistResult(true, summary, backup);

        // Written already; only the rebuild is declined (#289), as above.
        using var claim = ClaimTheBuildUnlessDeclined(course, section, "an assistant's rebuild after a change");
        if (claim is null)
            return new AssistResult(true, summary + " " + AssistWording.CourseIsBusy(course.Code), backup);
        progress?.Report($"Building a preview of Section {section} of {course.Code}…");
        var build = await _launcher.Run("preview", new[] { course.Code, section.ToString(), "--build-only", "--non-interactive" },
                                        _folder, progress, cancellation);
        return build.Succeeded
            ? new AssistResult(true, summary, backup)
            : new AssistResult(false, $"{summary} But the preview couldn’t be built. {AssistWording.WhereTheOutputIs}", backup);
    }

    /// <summary>
    /// Point the section's front page at its most recent published class, and
    /// give it that class's date.
    ///
    /// The only body edit anything here makes, so it keeps the same discipline
    /// as the frontmatter ones: change the one line, leave every other byte
    /// alone. The teacher may have this file open in Obsidian.
    /// </summary>
    private void ApplyIndexChange(IndexChange index, string tail)
    {
        try
        {
            string path = PagePaths.ResolveInside(_folder, index.RelativePath);
            string text = File.ReadAllText(path);
            if (index.Pointer is null
                || SectionIndex.PointedAndDated(text, index.Pointer, index.ToDate, tail) is not { } withDate) return;
            Save(path, withDate);
        }
        catch { /* the front page falling behind must not fail the publish */ }
    }

    /// <summary>
    /// What is actually true after a failure, said accurately.
    ///
    /// This used to read "The pages were changed and backed up" whatever
    /// happened — including when the plan had just established that no page
    /// needed changing. A teacher reading that reasonably concludes their
    /// content was modified and goes looking for damage that isn't there.
    /// </summary>
    private static string WhatSurvived(IReadOnlyList<string> changed) =>
        changed.Count == 0
            ? "No page needed changing, and the course was backed up"
            : $"{changed.Count} page{(changed.Count == 1 ? " was" : "s were")} changed and the course was backed up";

    private static string Summary(IReadOnlyList<string> changed, bool previewed, string code, int section, bool hiding = false,
                                  IReadOnlyList<string>? declined = null)
    {
        // Pages the writer declined are NAMED (#308): never folded into
        // "Nothing needed changing.", which would say they were already right.
        string? declinedSentence = declined is { Count: > 0 }
            ? AssistWording.PagesWhoseSettingsCannotBeAddedTo(declined)
            : null;
        if (changed.Count == 0) return declinedSentence ?? "Nothing needed changing.";
        string verb = hiding ? "Unpublished" : "Published";
        string what = changed.Count == 1
            ? $"{verb} “{changed[0]}”."
            : $"{verb} {changed.Count} pages ({string.Join(", ", changed)}).";
        string said = previewed
            ? $"{what.TrimEnd('.')} and rebuilt the preview of {code} Section {section}."
            : what;
        return declinedSentence is null ? said : said + " " + declinedSentence;
    }

    /// <summary>
    /// Refuse to build while Plantoir itself is building the same course.
    ///
    /// The other half of the lease protocol. The app writes what it is doing;
    /// this reads it. Without the check, a teacher previewing a section and an
    /// assistant publishing it would both be writing
    /// <c>.merged_output/section&lt;N&gt;/</c>, which the build clears first —
    /// so one of them serves or ships a half-written site.
    ///
    /// Only building is blocked. Reading, planning and editing frontmatter are
    /// all fine while a preview runs: the preview rebuilds from source anyway,
    /// so an edit lands rather than clashes.
    /// </summary>
    private void RefuseIfPlantoirIsBuilding(Course course)
    {
        // Only a BUILD in flight, which is the one thing that cannot happen
        // twice. This used to refuse whenever Plantoir held a preview or
        // publish lease at all — and a preview lease is held for as long as
        // the preview SERVER runs, so the assistant refused to do anything
        // for a teacher who had their preview open. That is precisely the
        // teacher this exists to help: they watch the preview to judge the
        // change while asking for the next one.
        if (!WorkLease.HeldBy(_folder, course.Code).Contains(WorkLease.Building)) return;

        throw new AssistRefusal(
            $"Plantoir is building {course.Code} right now, and building it here at the same time would " +
            "spoil both — they write to the same folder. Try again in a moment. " +
            "Reading and planning are fine meanwhile.");
    }

    /// <summary>
    /// A first look, before anything is written or backed up: decline a BUILD
    /// while another program builds, publishes or PREVIEWS this course
    /// (<c>shared-rules.json</c> → <c>workLeases.declining</c>, #289).
    /// </summary>
    /// <remarks>
    /// Stricter than <see cref="RefuseIfPlantoirIsBuilding"/>, and only for
    /// paths that BUILD: every <c>--build-only</c> first ends that section's
    /// serving preview, so a rebuild from here took down the page the teacher
    /// was reading. Writes keep the old, narrower check — refusing a WRITE
    /// during a preview made the assistant useless to a teacher watching it.
    /// The guarantee is <see cref="ClaimTheBuildOrDecline"/>; this only saves a
    /// backup and a message that would then be thrown away.
    /// </remarks>
    private void RefuseIfAnotherProgramStandsInTheWay(Course course, int section, string asked)
    {
        if (WorkLease.InTheWay(WorkLease.Asker.ABuild, _folder, course.Code, claim: null) is not { } other) return;
        ActivityTrail.Note(ActivityTrail.Event.BuildDeclinedCourseBusyElsewhere,
            WorkLease.DeclineTrailLine(asked, other), course.Code, section);
        throw new AssistRefusal(WorkLease.DeclinedForTheAssistant(course.Code, other.Kind));
    }

    /// <summary>
    /// Claim the build for as long as it runs, so Plantoir's own Preview and
    /// Deploy stand off rather than clearing the folder underneath it — TAKE
    /// first, then look, with nothing awaited in between, counting only leases
    /// taken before this one (<c>workLeases.declining.takeThenCheck</c>), so two
    /// programs that race cannot both go ahead. Declined: the lease is given
    /// back, the trail says why, and the caller is refused with the sentence an
    /// assistant working from outside is told (<c>wording.courseIsBusy</c>).
    /// </summary>
    private WorkLease.Held ClaimTheBuildOrDecline(Course course, int section, string asked)
    {
        var (held, declinedBy) = ClaimTheBuild(course, section, asked);
        return held ?? throw new AssistRefusal(WorkLease.DeclinedForTheAssistant(course.Code, declinedBy!));
    }

    /// <summary>The same, answering null rather than refusing — for a rebuild after a write that already happened.</summary>
    private WorkLease.Held? ClaimTheBuildUnlessDeclined(Course course, int section, string asked) =>
        ClaimTheBuild(course, section, asked).Held;

    /// <summary>
    /// The claim, or the KIND of lease that declined it — returned with the
    /// result rather than kept in a field, so two calls cannot read each
    /// other's answer (bundle 6a ruling 5).
    /// </summary>
    private (WorkLease.Held? Held, string? DeclinedBy) ClaimTheBuild(Course course, int section, string asked)
    {
        var claim = WorkLease.Take(_folder, course.Code, WorkLease.Building);
        if (WorkLease.InTheWay(WorkLease.Asker.ABuild, _folder, course.Code, claim.Claim) is not { } other)
            return (claim, null);
        claim.Dispose();
        ActivityTrail.Note(ActivityTrail.Event.BuildDeclinedCourseBusyElsewhere,
            WorkLease.DeclineTrailLine(asked, other), course.Code, section);
        return (null, other.Kind);
    }



    // ---- Rolling a course onto a real timetable --------------------------

    /// <summary>
    /// Work out what re-dating this section's classes onto a timetable would
    /// do, without touching anything.
    ///
    /// <paramref name="assignedPages"/> and <paramref name="assignedMeetings"/>
    /// are parallel: the page at each position takes the meeting number at the
    /// same position. Give neither and the classes are spread evenly across
    /// the block — a starting point, not an answer, because which lesson
    /// belongs on which day depends on what is IN the lesson.
    /// </summary>
    public ReDatePlan PlanReDate(
        string courseCode, int sectionNumber, Timetable timetable,
        IReadOnlyList<string> assignedPages, IReadOnlyList<int> assignedMeetings)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        var classPages = ClassPages(course, section);

        if (classPages.Count == 0)
            throw new AssistRefusal($"{course.Code} Section {section} has no class pages to re-date.");
        if (assignedPages.Count != assignedMeetings.Count)
            throw new AssistRefusal(
                $"{assignedPages.Count} pages were given but {assignedMeetings.Count} meeting numbers — " +
                "they have to line up one for one.");

        var chosen = new List<(string Page, Meeting Meeting)>();
        if (assignedPages.Count > 0)
        {
            foreach (var pair in assignedPages.Zip(assignedMeetings))
            {
                string path = Page(course, section, pair.First);
                if (timetable.ByNumber(pair.Second) is not { } meeting)
                    throw new AssistRefusal(
                        $"Block {timetable.Block} has no meeting {pair.Second}. " +
                        $"It runs 1 to {timetable.Meetings.Count}.");
                chosen.Add((path, meeting));
            }
        }
        else
        {
            var spread = timetable.EvenSpread(classPages.Count);
            for (int i = 0; i < classPages.Count; i++)
            {
                var meeting = i < spread.Count ? spread[i] : (spread.Count > 0 ? spread[^1] : timetable.Meetings[^1]);
                chosen.Add((classPages[i], meeting));
            }
        }

        string tail = SiblingTimeAndOffset(course, section, classPages);
        var dates = new List<PlannedDate>();
        for (int i = 0; i < chosen.Count; i++)
        {
            var (path, meeting) = chosen[i];
            bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, path);
            bool isOverflow = i >= timetable.Meetings.Count;
            bool isVisible = false;
            try
            {
                string full = PagePaths.ResolveInside(_folder, path);
                isVisible = !PageFrontmatter.IsDraft(File.ReadAllText(full), section);
            }
            catch { }
            bool unpublishes = isOverflow && isVisible;

            dates.Add(new PlannedDate(
                Title: Path.GetFileNameWithoutExtension(path),
                RelativePath: Relative(path),
                FrontmatterKey: PageFrontmatter.CreatedKeyFor(section, sectionLocal),
                Current: DateOf(course, section, path),
                New: meeting.Date,
                MeetingNumber: meeting.Number,
                Unpublishes: unpublishes));
        }

        var materials = ShiftMaterials(course, section, dates);

        // The first day of class is whatever the earliest re-dated class lands
        // on — a section does not span semesters, so there is exactly one.
        var reference = dates.Count > 0
            ? ReferenceDates(course, section, dates.Min(d => d.New))
            : new List<PlannedDate>();

        var moves = new List<ReDateMove>();
        foreach (var d in dates.Where(d => d.WillChange))
            moves.Add(new ReDateMove(d.Title, d.RelativePath, d.Current, d.New, ReDateReason.AClass, Unpublishes: d.Unpublishes));
        foreach (var m in materials.Where(m => m.WillChange))
        {
            string? anchor = dates.FirstOrDefault(d => d.New == m.New)?.Title;
            moves.Add(new ReDateMove(m.Title, m.RelativePath, m.Current, m.New, ReDateReason.BroughtBy, ClassTitle: anchor ?? "a class"));
        }
        foreach (var r in reference.Where(r => r.WillChange))
            moves.Add(new ReDateMove(r.Title, r.RelativePath, r.Current, r.New, ReDateReason.YearRound));

        var firstDay = dates.Count > 0 ? dates[0].New : default;
        var lastDay = dates.Count > 0 ? dates[^1].New : default;
        int spareDates = Math.Max(0, timetable.Meetings.Count - chosen.Count);

        return new ReDatePlan
        {
            CourseCode = course.Code,
            SectionNumber = section,
            Block = timetable.Block,
            Dates = dates,
            AllMeetings = timetable.Meetings.Select(meeting => meeting.Date).ToList(),
            Materials = materials,
            Reference = reference,
            CurriculumCount = reference.Count(r =>
            {
                try { return IsCurriculum(course.DirectoryPath, PagePaths.ResolveInside(_folder, r.RelativePath)); }
                catch { return false; }
            }),
            NonTeachingDays = timetable.NonTeachingDays,
            UnusedMeetings = spareDates,
            Overflowing = Math.Max(0, classPages.Count - timetable.Meetings.Count),
            Moves = moves,
            FirstDay = firstDay,
            LastDay = lastDay,
            ClassCount = dates.Count,
            SpareDates = spareDates,
            // Every date this plan would set, including the year-round pages —
            // auditing without them warns about pages the same plan is about
            // to fix, which reads as a fault in the plan itself.
            Problems = ProblemsAfter(course, section,
                dates.Concat(materials).Concat(reference).ToList(), tail),
        };
    }


    /// <summary>
    /// Concepts, exercises and tutorials moved by the same number of days as
    /// the lesson that anchors them.
    ///
    /// A material's date was derived from a class in the first place — the
    /// build gives every shared page the date of the first class that links to
    /// it — so moving classes and leaving materials behind breaks a
    /// relationship rather than preserving one. Shifting by a DELTA rather
    /// than assigning the class's date keeps any spacing the teacher set on
    /// purpose.
    ///
    /// The anchor is the linking class whose CURRENT date sits nearest the
    /// material's current date, which is the class the material was dated from
    /// however many terms ago. A page used by several classes therefore
    /// travels with the one that introduced it, not with whichever happens to
    /// come first alphabetically.
    /// </summary>
    private List<PlannedDate> ShiftMaterials(Course course, int section, IReadOnlyList<PlannedDate> classes)
    {
        var shifted = new List<PlannedDate>();
        LinkGraph graph;
        try { graph = LinkGraph.Build(course.DirectoryPath, section); }
        catch { return shifted; }

        var moves = new Dictionary<string, (DateOnly From, DateOnly To)>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in classes)
        {
            if (entry.Current is not { } from) continue;
            try { moves[PagePaths.ResolveInside(_folder, entry.RelativePath)] = (from, entry.New); }
            catch { }
        }

        var classPaths = new HashSet<string>(
            ClassPages(course, section).Select(Path.GetFullPath), StringComparer.OrdinalIgnoreCase);

        foreach (string page in graph.Pages)
        {
            if (classPaths.Contains(page)) continue;                       // classes are handled above
            if (DateOf(course, section, page) is not { } pageDate) continue;

            (DateOnly From, DateOnly To)? anchor = null;
            int nearest = int.MaxValue;
            foreach (string linker in graph.SourcesOf(page))
            {
                if (!moves.TryGetValue(Path.GetFullPath(linker), out var move)) continue;
                int gap = Math.Abs(move.From.DayNumber - pageDate.DayNumber);
                if (gap < nearest) { nearest = gap; anchor = move; }
            }
            if (anchor is not { } chosen) continue;                        // no class moved that uses this page

            int delta = chosen.To.DayNumber - chosen.From.DayNumber;
            if (delta == 0) continue;

            bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, page);
            shifted.Add(new PlannedDate(
                Title: Path.GetFileNameWithoutExtension(page),
                RelativePath: Relative(page),
                FrontmatterKey: PageFrontmatter.CreatedKeyFor(section, sectionLocal),
                Current: pageDate,
                New: pageDate.AddDays(delta),
                MeetingNumber: 0));
        }
        return shifted;
    }

    /// <summary>
    /// The date problems this re-date would LEAVE — audited against the new
    /// dates, not the current ones, so the teacher sees the world the change
    /// would create rather than the one it replaces.
    /// </summary>
    private List<string> ProblemsAfter(Course course, int section, IReadOnlyList<PlannedDate> dates, string tail)
    {
        var planned = new Dictionary<string, DateOnly>(StringComparer.OrdinalIgnoreCase);
        foreach (var date in dates)
        {
            try { planned[PagePaths.ResolveInside(_folder, date.RelativePath)] = date.New; }
            catch { }
        }

        DateOnly? Resolve(string path) =>
            planned.TryGetValue(Path.GetFullPath(path), out var moved)
                ? moved
                : DateOf(course, section, path);

        LinkGraph graph;
        try { graph = LinkGraph.Build(course.DirectoryPath, section); }
        catch { return new List<string>(); }

        var classPages = ClassPages(course, section);
        var problems = DateAudit.Run(classPages, graph, Resolve, Relative, course.Configuration.Naming);

        var newDates = dates.Select(d => d.New).ToList();
        if (newDates.Count > 0)
        {
            var others = graph.Pages.Where(p => !classPages.Contains(p)).ToList();
            problems.AddRange(DateAudit.Stragglers(
                others, newDates.Min(), newDates.Max(), Resolve, Relative));
        }
        return problems;
    }

    /// <summary>
    /// The time-of-day and offset a course already uses, so a class that never
    /// had a date joins the convention its siblings follow instead of
    /// inventing one.
    /// </summary>
    private string SiblingTimeAndOffset(Course course, int section, IReadOnlyList<string> classPages)
    {
        foreach (string path in classPages)
        {
            bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, path);
            string key = PageFrontmatter.CreatedKeyFor(section, sectionLocal);
            try
            {
                string? raw = PageFrontmatter.StoredText(File.ReadAllText(path), key);
                if (raw is { Length: > 10 }) return raw[10..];
            }
            catch { }
        }
        return "T07:00:00.000-0400";
    }

    /// <summary>
    /// Cut a section loose from last year's website, so the next publish makes
    /// a new one instead of overwriting it.
    ///
    /// The marker under <c>.netlify_sites/</c> (or <c>.cloudflare_sites/</c>)
    /// pins the section to a site whose name has the year in it —
    /// <c>exc2o-s1-2026-gordon</c>. Roll the course over without removing it
    /// and the first publish of the new year lands on last year's URL, which
    /// last year's students may still be reading.
    ///
    /// The marker is renamed rather than deleted: it holds the site id and
    /// admin URL, and a teacher who decides they wanted the old site after all
    /// has no other way back to it. <c>deploy.py</c> and <c>build_site.py</c>
    /// build exact marker paths and never glob the folder, so a
    /// <c>.previous-*.json</c> sitting beside them is inert.
    /// </summary>
    /// <remarks>
    /// <para><b>EVERY destination type, not just the course's primary — this
    /// used to <c>return</c> inside the first folder that held a marker.</b>
    /// Markers are keyed purely by destination TYPE and a course can carry
    /// additional targets, so a section pinned to both Netlify and Cloudflare
    /// had only its Netlify marker released and went on publishing over last
    /// year's Cloudflare site. Pinned by
    /// <c>contracts/file-formats.json</c> -&gt;
    /// <c>firstDeployMarkers.releasedWhenASectionRollsOver</c>.</para>
    ///
    /// <para><b>"Still pinned" is kept apart from "there was nothing to
    /// release"</b>, because both used to produce the same empty answer — so a
    /// marker that existed and could not be moved was reported as "this
    /// section had not been published anywhere yet", the opposite of the truth
    /// about the one fact this whole feature turns on.</para>
    /// </remarks>
    public SiteRelease ReleaseSite(Course course, int sectionNumber)
    {
        var kept = new List<string>();
        var stillPinned = new List<string>();
        string stamp = DateText.Invariant(DateTime.Now, "yyyy-MM-dd_HHmmss");

        // ONE undo entry for the whole release, not one per destination. A
        // rollover is a single act to the teacher, and a partial undo would
        // put a section back on last year's Netlify site while leaving it cut
        // loose from Cloudflare — a state nobody chose and nothing describes.
        using var recording = UndoHistory.Record(_undo,
            $"cut section {sectionNumber} loose from its website");

        foreach (string folder in new[] { ".netlify_sites", ".cloudflare_sites" })
        {
            string marker = Path.Combine(course.DirectoryPath, folder, $"section{sectionNumber}.json");
            string keptPath = Path.Combine(course.DirectoryPath, folder,
                ReleasedMarkerName(sectionNumber, stamp));
            Release(marker, keptPath, kept, stillPinned);
        }

        // The LEGACY marker, which `deploy.py` still reads and migrates back
        // into the stable path (`load_netlify_marker`). Leaving it would make
        // a rollover report "never published" and then publish over last
        // year's site on the next deploy — in exactly the folders old enough
        // to have taught somebody something. Netlify only: there has never
        // been a Cloudflare equivalent.
        //
        // **It lives in the BUILT OUTPUT, and on THIS platform that is not
        // `.merged_output`.** `deploy.py` computes it from `section_dir`,
        // which is `toolchain_paths.merged_output_root(...)/section<N>` — and
        // `merged_output_root` returns `PLANTOIR_BUILD_ROOT/<COURSE>` when
        // that is set, with no `.merged_output` level at all, which is the
        // Windows layout the launchers always set up. Releasing the mac's
        // literal `<CODE>/.merged_output/section<N>/…` here would repeat the
        // mac's own first-cut mistake in the other direction: a path that has
        // never held a marker on this platform, so the release would do
        // nothing and the section would keep publishing over last year's site.
        //
        // Both are attempted, guarded by existence. The build-root one is the
        // path `deploy.py` reads HERE; the `.merged_output` one is what a
        // folder carried here from a mac would have, and releasing a file that
        // is not there costs nothing.
        foreach (string sectionOutput in LegacyMarkerHomes(course, sectionNumber))
        {
            string marker = Path.Combine(sectionOutput, ".netlify_site.json");
            string keptPath = Path.Combine(sectionOutput, $".netlify_site.previous-{stamp}.json");
            Release(marker, keptPath, kept, stillPinned);
        }

        recording.Done();
        return new SiteRelease(kept, stillPinned);
    }

    /// <summary>
    /// Move one marker aside, recording it for undo, and file it under kept or
    /// still-pinned.
    /// </summary>
    private void Release(string marker, string keptPath, List<string> kept, List<string> stillPinned)
    {
        if (!File.Exists(marker)) return;   // nothing pinning this destination
        string contents;
        try { contents = File.ReadAllText(marker); }
        catch { stillPinned.Add(NameForTeacher(marker)); return; }

        try
        {
            // Recorded as a move so an undo puts the section back on last
            // year's site rather than leaving it orphaned.
            _undo?.Touch(marker, contents);
            _undo?.Touch(keptPath, null);
            File.Move(marker, keptPath);
            _undo?.Wrote(marker, null);
            _undo?.Wrote(keptPath, contents);
            kept.Add(NameForTeacher(keptPath));
        }
        catch
        {
            // A marker that could not be moved is one this section is STILL
            // pinned to, and the reply has to say so rather than reporting the
            // same empty result as "never published".
            stillPinned.Add(NameForTeacher(marker));
        }
    }

    /// <summary>
    /// The folders a legacy <c>.netlify_site.json</c> could be sitting in, in
    /// the order they are tried.
    /// </summary>
    /// <remarks>
    /// One known divergence, inherited rather than introduced:
    /// <c>BuildOutputLocation.BuildsRootFor</c> falls back to
    /// <c>AppDataRoot</c>, which <c>--state-dir</c> redirects, while the
    /// launchers compute the same root from the real <c>%LOCALAPPDATA%</c>. So
    /// a run started with <c>--state-dir</c> looks for the legacy marker
    /// somewhere the launcher would never have put one and finds nothing —
    /// the same hazard <c>run-ui-tests.ps1</c> already warns about, and
    /// harmless here because it can only cause a release to be skipped, never
    /// a wrong file to be moved.
    /// </remarks>
    private IEnumerable<string> LegacyMarkerHomes(Course course, int sectionNumber)
    {
        string fromBuildRoot;
        try
        {
            fromBuildRoot = BuildOutputLocation.ForSection(
                BuildOutputLocation.BuildsRootFor(_folder), course.Code, sectionNumber);
        }
        catch { fromBuildRoot = ""; }
        if (fromBuildRoot.Length > 0) yield return fromBuildRoot;

        yield return Path.Combine(course.DirectoryPath, ".merged_output", $"section{sectionNumber}");
    }

    /// <summary>
    /// The name a released marker is kept under.
    ///
    /// <para><b>Frozen, and shared with the mac</b> (<c>DeployCommand.releasedMarkerName</c>),
    /// so a teacher who wants back onto last year's website is told the same
    /// filename whichever app they are sitting at. Pinned in
    /// <c>contracts/file-formats.json</c> -&gt; <c>firstDeployMarkers</c>.</para>
    /// </summary>
    public static string ReleasedMarkerName(int sectionNumber, string stamp) =>
        $"section{sectionNumber}.previous-{stamp}.json";

    /// <summary>
    /// A marker named the way a teacher would find it — the folder it sits in
    /// and the file, without the rest of the path.
    /// </summary>
    /// <remarks>
    /// Not <see cref="Relative"/>, which is relative to the WORKING FOLDER: on
    /// this platform the built output lives outside it, so a legacy marker
    /// would be named with a run of <c>..\..\</c> nobody could use. The mac
    /// says it this way too, and the sentence carrying it is shared.
    /// </remarks>
    private static string NameForTeacher(string path) =>
        (Path.GetFileName(Path.GetDirectoryName(path)) ?? "") + "/" + Path.GetFileName(path);

    /// <summary>What cutting a section loose actually managed.</summary>
    /// <param name="KeptFiles">Where last year's details were put, for each destination released.</param>
    /// <param name="StillPinned">
    /// Destinations this section is STILL pinned to, because releasing them
    /// failed — kept apart from "there was nothing to release", which is the
    /// distinction that matters.
    /// </param>
    public sealed record SiteRelease(IReadOnlyList<string> KeptFiles, IReadOnlyList<string> StillPinned)
    {
        /// <summary>Whether this section was pinned to any website at all.</summary>
        public bool ReleasedAnything => KeptFiles.Count > 0;

        /// <summary>
        /// Whether anything was left pinned — either because a release failed
        /// or because only some of several destinations came loose.
        /// </summary>
        public bool SomethingIsStillPinned => StillPinned.Count > 0;
    }

    /// <summary>Carry out a re-date the teacher has agreed to, after backing the course up.</summary>
    public AssistResult ApplyReDate(ReDatePlan plan, IProgress<string>? progress = null,
                                    bool isARollover = false)
    {
        var course = Course(plan.CourseCode);
        int section = Section(course, plan.SectionNumber);
        if (plan.ChangesNothing) return new AssistResult(true, "Every class already carries that date.", null);

        string backup;
        try { backup = BackUpOnceForThisConversation(course, plan.SectionNumber); }
        catch (Exception error)
        {
            throw new AssistRefusal(
                $"{course.Code} couldn’t be backed up, so no dates were changed: {error.Message}");
        }

        // Write the timetable down now the teacher has committed to it. They
        // have just done the tedious part; asking again next week — or in the
        // next conversation — is the tedium this is here to end.
        if (plan.AllMeetings.Count > 0)
            TimetableMemory.Write(_folder, course.Code, section, plan.AllMeetings,
                $"block {plan.Block}", DateOnly.FromDateTime(DateTime.Now));

        using var recording = UndoHistory.Record(_undo,
            $"re-dated {course.Code} Section {section} onto block {plan.Block}");
        string tail = SiblingTimeAndOffset(course, section, ClassPages(course, section));
        var classPaths = new HashSet<string>(
            plan.Dates.Select(d => d.RelativePath), StringComparer.OrdinalIgnoreCase);
        int classes = 0, materials = 0;
        // Pages the writer declined (#308, the mac's #186), NAMED in the reply:
        // a date it could not set, and a hide it could not write.
        var undated = new List<string>();
        var notHidden = new List<string>();

        foreach (var date in plan.Changing)
        {
            string full = PagePaths.ResolveInside(_folder, date.RelativePath);
            string fileText = File.ReadAllText(full);
            var dateEdit = PageFrontmatter.SetCreated(fileText, date.FrontmatterKey, date.New, tail);
            string updated = dateEdit.Text;
            bool changed = dateEdit.Changed;
            if (dateEdit.Outcome == FrontmatterWriteOutcome.NoRoomForAKey) undated.Add(date.Title);
            if (date.Unpublishes)
            {
                bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, full);
                string pubKey = PageFrontmatter.PublishKeyFor(section, sectionLocal);
                var (draftUpdated, draftEdit) = PageFrontmatter.SetDraft(
                    updated, pubKey, draft: true, section);
                updated = draftUpdated;
                if (draftEdit.Changed) changed = true;
                if (draftEdit.NoRoomForAKey) notHidden.Add(date.Title);
            }
            if (!changed) continue;
            Save(full, updated);
            if (classPaths.Contains(date.RelativePath)) classes++; else materials++;
        }

        string indexPath = SectionIndex.PathFor(course, section);
        if (File.Exists(indexPath))
        {
            try
            {
                string indexText = File.ReadAllText(indexPath);
                string? newestPublished = SectionIndex.MostRecentPublished(course, section, ClassPages(course, section));
                if (newestPublished is not null)
                {
                    if (SectionIndex.Repointed(indexText, PointerFor(course, section, newestPublished)) is { } newIndexText
                        && newIndexText != indexText)
                    {
                        Save(indexPath, newIndexText);
                    }
                }
            }
            catch { }
        }

        // A ROLLOVER releases the published-pages record and the checklist's
        // answers (#392), INSIDE this undo entry as the issue asks: one
        // "undo that" puts the dates AND the record back. A separate entry
        // would let the first undo restore last year's record over this
        // year's dates.
        if (isARollover)
            LinksChecklist.ReleasePublishedPages(course.DirectoryPath, section, DateTime.Now, _undo);

        recording.Done();

        // Counted apart, because "moved 91 classes" when 26 classes and 65
        // materials moved is a sentence a teacher would rightly query — and
        // each from what was WRITTEN (#357 / mac #343), never one subtracted
        // from a total: "Re-dated 14 classes and -4 pages they use" came from
        // (pages whose date changes) - (every class in the section).
        string summary = AssistWording.ReDatedSummary(course.Code, section.ToString(), classes, materials);
        if (undated.Count > 0) summary += " " + AssistWording.PagesWhoseNewDatesCouldNotBeSet(undated);
        if (notHidden.Count > 0) summary += " " + AssistWording.PagesWhoseSettingsCannotBeAddedTo(notHidden);
        NoteSettingsLeftAsTheyWere("re-dating classes", undated.Union(notHidden, StringComparer.OrdinalIgnoreCase).Count(),
            course.Code, section);
        string detail = summary +
                        $"\n\n{BackedUpNote}" +
                        "\n\nNothing was published or hidden, so students see no change until you deploy.";

        return new AssistResult(true, detail, backup);
    }

    public const string BackedUpNote =
        "The course was backed up before this conversation changed anything, so this can also be undone from Plantoir's Backups list.";

    /// <summary>
    /// Work out what bringing a lesson's materials into date with the lesson
    /// would do, without touching anything.
    ///
    /// Naming classes scopes it to what those classes link to — the usual
    /// case, straight after the audit says a particular lesson's material is
    /// months out. Naming none brings every material into line with the
    /// EARLIEST class that links to it, which is the rule the build documents:
    /// a shared page belongs to the lesson that introduced it, not the one
    /// that revisited it.
    /// </summary>
    public SyncPlan PlanSyncDates(string courseCode, int sectionNumber, IReadOnlyList<string> classTitles)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        var classPaths = new HashSet<string>(
            ClassPages(course, section).Select(Path.GetFullPath), StringComparer.OrdinalIgnoreCase);

        var anchors = new List<string>();
        HashSet<string>? scope = null;
        if (classTitles.Count > 0)
        {
            scope = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string title in classTitles)
            {
                string path = Page(course, section, title);
                if (!classPaths.Contains(Path.GetFullPath(path)))
                    throw new AssistRefusal(
                        $"“{title}” isn’t a class page, so it can’t anchor anything's date.");
                scope.Add(Path.GetFullPath(path));
                anchors.Add(Path.GetFileNameWithoutExtension(path));
            }
        }
        else anchors.Add("every class");

        LinkGraph graph;
        try { graph = LinkGraph.Build(course.DirectoryPath, section); }
        catch (Exception error) { throw new AssistRefusal($"That section couldn’t be read: {error.Message}"); }

        var problems = new List<string>();
        var dates = new List<PlannedDate>();

        foreach (string page in graph.Pages)
        {
            if (classPaths.Contains(page)) continue;              // a class anchors, it is not anchored

            // The earliest class that links to it, within scope.
            DateOnly? target = null;
            foreach (string linker in graph.SourcesOf(page))
            {
                string full = Path.GetFullPath(linker);
                if (!classPaths.Contains(full)) continue;
                if (scope is not null && !scope.Contains(full)) continue;
                if (DateOf(course, section, linker) is not { } when) continue;
                if (target is null || when < target) target = when;
            }
            if (target is not { } newDate) continue;

            bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, page);
            dates.Add(new PlannedDate(
                Title: Path.GetFileNameWithoutExtension(page),
                RelativePath: Relative(page),
                FrontmatterKey: PageFrontmatter.CreatedKeyFor(section, sectionLocal),
                Current: DateOf(course, section, page),
                New: newDate,
                MeetingNumber: 0));
        }

        if (dates.Count == 0)
            problems.Add(scope is null
                ? "No page in this section is linked from a class that carries a date."
                : "Those classes don’t link to anything, or they have no date themselves.");

        return new SyncPlan
        {
            CourseCode = course.Code,
            SectionNumber = section,
            Anchors = anchors,
            Dates = dates,
            Problems = problems,
        };
    }

    /// <summary>Carry out a date sync the teacher has agreed to, after backing the course up.</summary>
    public AssistResult ApplySyncDates(SyncPlan plan, IProgress<string>? progress = null)
    {
        var course = Course(plan.CourseCode);
        int section = Section(course, plan.SectionNumber);
        if (plan.ChangesNothing) return new AssistResult(true, "Every page already matches its class.", null);

        string backup;
        try { backup = BackUpOnceForThisConversation(course, plan.SectionNumber); }
        catch (Exception error)
        {
            throw new AssistRefusal(
                $"{course.Code} couldn’t be backed up, so no dates were changed: {error.Message}");
        }

        using var recording = UndoHistory.Record(_undo,
            $"brought {Humanize(plan.Anchors)}’ pages into date in " +
            $"{course.Code} Section {section}");

        string tail = SiblingTimeAndOffset(course, section, ClassPages(course, section));
        int moved = 0;
        foreach (var date in plan.Changing)
        {
            string full = PagePaths.ResolveInside(_folder, date.RelativePath);
            var (updated, changed) = PageFrontmatter.SetCreated(
                File.ReadAllText(full), date.FrontmatterKey, date.New, tail);
            if (!changed) continue;
            Save(full, updated);
            moved++;
        }
        recording.Done();

        return new AssistResult(true,
            $"Brought {moved} page{(moved == 1 ? "" : "s")} into date with the class that uses " +
            (moved == 1 ? "it" : "them") + $" in {course.Code} Section {section}. Nothing was deployed.",
            backup);
    }

    /// <summary>A whole-course backup, on its own.</summary>
    /// <remarks>
    /// <para><b>Attributed to the ASSISTANT, which is what the section is
    /// for.</b> Left to default, <see cref="CourseArchiver.BackUpCourse"/>
    /// records <see cref="BackupMaker.DefaultTeacher"/> — so the Backups list
    /// says "made by you" about a copy the teacher never made, and, worse,
    /// <see cref="CourseArchiver.PruneBackups"/> deliberately skips anything
    /// that is not the assistant's. A session following this tool's own advice
    /// to back up "before any bulk editing" would write a whole-course zip
    /// every time and none of them would ever be cleared;
    /// <see cref="CourseArchiver.MostBackupsKept"/> exists precisely to stop
    /// that. The mac takes the section for the same reason, and
    /// <c>contracts/assist-cases.json</c> has required it of both since the
    /// tool arrived.</para>
    /// </remarks>
    public string BackUp(string courseCode, int sectionNumber)
    {
        var course = Course(courseCode);
        int number = Section(course, sectionNumber);
        return Relative(AssistantBackup(course, number));
    }

    /// <summary>
    /// The one door every assistant zip goes through — the conversation's first
    /// copy, back_up_course, and getting a section ready — so each REAL zip
    /// leaves one <c>assistant backed up a course</c> line with its file name,
    /// size and time (#360, mac #351): "the window hung after I approved" and
    /// "where did this zip come from" were unanswerable before it. A failed
    /// copy is never remembered, and says why.
    /// </summary>
    private string AssistantBackup(Course course, int sectionNumber)
    {
        // The course is BUSY while it is zipped (#360, mac #351): Plantoir's
        // own Preview and Deploy, a scheduled publish and any other assistant
        // see this lease and stand off, as they do on the mac.
        using var copying = WorkLease.Take(_folder, course.Code, WorkLease.Copying);
        var clock = System.Diagnostics.Stopwatch.StartNew();
        string made;
        try
        {
            made = CourseArchiver.BackUpCourse(course, Workspace.CoursesDirectory(_folder),
                                               new BackupMaker.Assistant(sectionNumber));
        }
        catch (Exception error)
        {
            ActivityTrail.Note(ActivityTrail.Event.AssistantBackedUpACourse,
                $"assistant could not back up the course: {error.Message}", course.Code, sectionNumber);
            throw;
        }
        double megabytes = 0;
        try { megabytes = new FileInfo(made).Length / (1024.0 * 1024.0); } catch { }
        ActivityTrail.Note(ActivityTrail.Event.AssistantBackedUpACourse,
            $"assistant backed up the course as {Path.GetFileName(made)} " +
            $"({megabytes.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture)} MB, " +
            $"{clock.Elapsed.TotalSeconds.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture)} s)",
            course.Code, sectionNumber);
        return made;
    }

    // ---- Helpers ---------------------------------------------------------

    /// <summary>
    /// The one place anything here writes a page, so the session's undo
    /// history sees every change without each caller having to remember.
    /// </summary>
    // ---- Deploying later ---------------------------------------------------

    /// <summary>
    /// Work out what scheduling a deploy would mean, without scheduling one.
    ///
    /// The check that matters is the last one: whether the classes the teacher
    /// is thinking of are actually PUBLISHED. A scheduled deploy that runs
    /// perfectly at half six and ships a site without tomorrow's class is the
    /// exact failure worth catching here, while somebody is awake to fix it.
    /// </summary>
    public ScheduledDeploy PlanScheduledDeploy(string courseCode, int sectionNumber, DateTime when,
                                               IReadOnlyList<string>? classesToCheck = null)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);

        // Shared with the sidebar's own "Schedule Deploy…", so a refusal
        // cannot be walked around by using the other door. The Cloudflare
        // Account ID is a per-teacher, machine-global setting — not tied to
        // this workspace — so it's read the same way the GUI's
        // SidebarPane does, via AppSettings.Load(), rather than assumed
        // unreachable from a headless process. Found missing here entirely
        // (defaulted to "") while auditing this feature for mac parity:
        // scheduling a Cloudflare-destination deploy through the assistant
        // always refused with "Paste your Cloudflare Account ID" even when
        // one was correctly configured, because this check never saw it.
        string cloudflareAccountId = CurrentCloudflareAccountId();
        if (ScheduledDeploy.Problem(course, section, when, DateTime.Now, cloudflareAccountId) is { } problem)
            throw new AssistRefusal(problem);

        // Only the classes the caller NAMED, each said as published or not
        // (#400: the section-wide unpublished list is gone from scheduling).
        var named = new List<(string Title, bool? Published)>();
        foreach (string title in classesToCheck ?? Array.Empty<string>())
        {
            try
            {
                string path = Page(course, section, title);
                named.Add((Path.GetFileNameWithoutExtension(path),
                           !PageFrontmatter.IsDraft(File.ReadAllText(path), section)));
            }
            // A page that cannot be found is said so, not refused over.
            catch (AssistRefusal) { named.Add((title, null)); }
        }

        return new ScheduledDeploy
        {
            CourseCode = course.Code,
            SectionNumber = section,
            When = when,
            ClassesNamed = named,
            // EVERY destination, from the list the run deploys to (#400).
            Destination = ScheduledDeploy.EveryDestination(course.Configuration),
        };
    }

    // ---- Curriculum expectations on a page ---------------------------------

    /// <summary>One curriculum expectation: its code, and what it actually says.</summary>
    public sealed record Expectation(string Code, string Text, string RelativePath);

    /// <summary>
    /// Every curriculum expectation in the course, with its wording.
    ///
    /// The point of returning the TEXT, not just the codes, is that matching an
    /// expectation to a lesson is a judgement about meaning — the one thing the
    /// tools cannot do and a capable model can. So this hands over everything
    /// needed to decide, and decides nothing itself.
    /// </summary>
    public List<Expectation> CurriculumExpectations(Course course, int sectionNumber)
    {
        var found = new List<Expectation>();

        foreach (string relative in Pages(course, sectionNumber))
        {
            string full;
            try { full = PagePaths.ResolveInside(_folder, relative); }
            catch { continue; }
            if (!CurriculumRules.IsCurriculumPage(full)) continue;

            string code = Path.GetFileNameWithoutExtension(full);
            // Index and strand-heading pages are not expectations; an
            // expectation is a leaf, coded like A1.1 or B2.3.
            if (!CurriculumRules.IsExpectationCode(code)) continue;

            string body;
            try { body = File.ReadAllText(full); }
            catch { continue; }

            // The wording, minus the frontmatter and the block anchor.
            string text = CurriculumRules.ExpectationWording(body);

            found.Add(new Expectation(code, text, relative));
        }

        return found.OrderBy(e => e.Code, StringComparer.OrdinalIgnoreCase).ToList();
    }

    /// <summary>
    /// Plan adding curriculum transclusions to a page.
    ///
    /// They go inside the <c>%%curriculum-start%%</c> markers the example
    /// content uses, and the markers matter: a course installed without
    /// curriculum has that whole block stripped at build time, so a
    /// transclusion outside them would leave a dangling reference on a
    /// teacher's site rather than disappearing quietly.
    /// </summary>
    public CurriculumMentionsPlan PlanCurriculumMentions(
        string courseCode, int sectionNumber, string page, IReadOnlyList<string> codes)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        string path = Page(course, section, page);
        string text = File.ReadAllText(path);

        var known = CurriculumExpectations(course, section)
            .ToDictionary(e => e.Code, StringComparer.OrdinalIgnoreCase);

        var adding = new List<Expectation>();
        var alreadyThere = new List<string>();
        var unknown = new List<string>();

        foreach (string raw in codes.Select(c => c.Trim()).Where(c => c.Length > 0).Distinct())
        {
            if (!known.TryGetValue(raw, out var expectation)) { unknown.Add(raw); continue; }
            if (text.Contains($"[[{expectation.Code}]]", StringComparison.OrdinalIgnoreCase))
            { alreadyThere.Add(expectation.Code); continue; }
            adding.Add(expectation);
        }

        return new CurriculumMentionsPlan
        {
            CourseCode = course.Code,
            SectionNumber = section,
            PageTitle = Path.GetFileNameWithoutExtension(path),
            RelativePath = Relative(path),
            Adding = adding,
            AlreadyThere = alreadyThere,
            Unknown = unknown,
            HasBlockAlready = text.Contains(CurriculumStart, StringComparison.OrdinalIgnoreCase),
        };
    }

    private const string CurriculumStart = "%%curriculum-start%%";
    private const string CurriculumEnd = "%%curriculum-end%%";

    /// <summary>Everything after the frontmatter fence, or the whole text if there is none.</summary>
    private static string BodyAfterFrontmatter(string pageText)
    {
        string[] lines = pageText.Split('\n');
        int open = -1;
        for (int i = 0; i < lines.Length; i++)
        {
            string trimmed = lines[i].Trim();
            if (trimmed.Length == 0) continue;
            if (trimmed != "---") return pageText;
            open = i;
            break;
        }
        if (open < 0) return pageText;

        for (int i = open + 1; i < lines.Length; i++)
            if (lines[i].Trim() is "---" or "...")
                return string.Join("\n", lines.Skip(i + 1));
        return pageText;
    }

    /// <summary>Write the transclusions the plan describes into the page.</summary>
    public AssistResult ApplyCurriculumMentions(CurriculumMentionsPlan plan, IProgress<string>? progress = null)
    {
        var course = Course(plan.CourseCode);
        int section = Section(course, plan.SectionNumber);
        if (plan.ChangesNothing)
            return new AssistResult(true, "Nothing to add — those expectations are already on the page.", null);

        RefuseIfPlantoirIsBuilding(course);

        string backup;
        try { backup = BackUpOnceForThisConversation(course, plan.SectionNumber); }
        catch (Exception error)
        {
            throw new AssistRefusal($"{course.Code} couldn’t be backed up, so the page was not changed: {error.Message}");
        }

        // BEGIN and END are a pair, and the END is the half that was missing
        // until 2026-09-18. `UndoHistory.Begin` ignores a nested call, so an
        // entry left open does two things, both silent: this tool records no
        // undo at all ("undo that" answers "I have not changed any pages"),
        // and the NEXT operation's files are swallowed into this open entry
        // and committed under THIS description. A teacher who added
        // expectations, then published a class, then said "undo that" was
        // told they had added expectations and had the publish taken back
        // with them.
        using var recording = UndoHistory.Record(_undo,
            $"added {plan.Adding.Count} curriculum expectations to “{plan.PageTitle}”");

        string path = PagePaths.ResolveInside(_folder, plan.RelativePath);
        string text = File.ReadAllText(path);
        string lineEnd = text.Contains("\r\n") ? "\r\n" : "\n";
        string transclusions = string.Join(lineEnd, plan.Adding.Select(e => $"![[{e.Code}]]"));

        if (plan.HasBlockAlready)
        {
            // Append inside the existing block, keeping what is already there.
            int end = text.IndexOf(CurriculumEnd, StringComparison.OrdinalIgnoreCase);
            text = text[..end].TrimEnd() + lineEnd + transclusions + lineEnd + text[end..];
        }
        else
        {
            // A new block, before the "things to do" list if there is one —
            // that list closes a class page, and the curriculum note belongs
            // with the lesson rather than after the homework.
            string block = CurriculumStart + lineEnd + "Today's work points here:" + lineEnd + lineEnd +
                           transclusions + lineEnd + CurriculumEnd + lineEnd;
            int before = text.IndexOf("## Things to do", StringComparison.OrdinalIgnoreCase);
            text = before > 0
                ? text[..before] + block + lineEnd + text[before..]
                : text.TrimEnd() + lineEnd + lineEnd + block;
        }

        Save(path, text);
        recording.Done();

        return new AssistResult(true,
            $"Added {plan.Adding.Count} curriculum expectation{(plan.Adding.Count == 1 ? "" : "s")} to " +
            $"“{plan.PageTitle}” — {string.Join(", ", plan.Adding.Select(e => e.Code))}. " +
            "They are wrapped in the curriculum markers, so a course installed without curriculum still builds. " +
            "Look the page over in Plantoir.",
            backup);
    }

    // ---- Making room in a course that is already built out -----------------

    /// <summary>A class page, understood as a numbered day of a numbered unit.</summary>
    private sealed record ClassRef(int Unit, int Day, string Path, DateOnly? Date, string Title);

    /// <summary>
    /// Read a section's class pages as "Unit U, Day D".
    ///
    /// Anything not named that way is left out entirely rather than guessed
    /// at: a teacher's "Field Trip" or "Exam Review" has no unit and no day,
    /// and shuffling it by inventing one would be worse than not touching it.
    /// Those pages keep their dates, which is the honest outcome — the plan
    /// says how many were skipped so nobody is surprised.
    /// </summary>
    private List<ClassRef> NumberedClasses(Course course, int section, out int unnumbered)
    {
        var found = new List<ClassRef>();
        unnumbered = 0;

        foreach (string path in ClassPages(course, section))
        {
            string title = Path.GetFileNameWithoutExtension(path);
            // The course's OWN word. Reading a literal "Unit" here made the
            // whole make-room feature unreachable for a Module course: every
            // page counted as unnumbered, the plan found no classes, and it
            // refused with "has no pages named ...". The title-building below
            // was converted first and could therefore never run.
            var parsed = course.Configuration.Naming.Parse(title);
            if (parsed is null) { unnumbered++; continue; }

            found.Add(new ClassRef(
                parsed.Value.Unit, parsed.Value.Day,
                path, DateOf(course, section, path), title));
        }

        return found.OrderBy(c => c.Unit).ThenBy(c => c.Day).ToList();
    }

    /// <summary>
    /// Plan making room for one or more classes part-way through a unit.
    ///
    /// Two separate things happen, and the plan keeps them apart because they
    /// read differently to a teacher. Later days IN THE SAME UNIT are
    /// RENAMED — Day 3 becomes Day 4 — and every class from the insertion
    /// point onwards, later units included, MOVES to a later meeting day
    /// without changing its name.
    /// </summary>
    public InsertPlan PlanInsertClasses(string courseCode, int sectionNumber, int unit, int atDay, int count)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        var naming = course.Configuration.Naming;

        // A numbered course (#274, mac #267) names ONE number; the frozen
        // schema's two arguments are read into it (insertion.numberedPosition).
        if (naming.IsNumbered)
        {
            int? position = NumberedPosition(unit, atDay);
            if (position is null)
                throw new AssistRefusal(
                    $"{course.Code} numbers its pages one after another — “{naming.Word} 1”, “{naming.Word} 2” — " +
                    $"so say which one to make room at, for example “{naming.Word} {Math.Max(unit, atDay)}”.");
            unit = 1;
            atDay = position.Value;
        }

        if (unit < 1 || atDay < 1) throw new AssistRefusal("Unit and day numbers start at 1.");
        if (count < 1) throw new AssistRefusal("Ask for at least one class.");

        var remembered = TimetableMemory.Read(_folder, course.Code, section)
            ?? throw new AssistRefusal(
                $"I don't know when {course.Code} Section {section} meets, so I can't move classes onto real " +
                "days. Ask the teacher for their class dates, then record them with remember_timetable.");

        var classes = NumberedClasses(course, section, out int unnumbered);
        if (classes.Count == 0)
            throw new AssistRefusal(
                $"{course.Code} Section {section} has no pages named “{naming.ShapeDescription}”, so there is nothing " +
                "to make room in.");

        var problems = new List<string>();
        if (unnumbered > 0)
            problems.Add($"{unnumbered} class page{(unnumbered == 1 ? " is" : "s are")} not named " +
                         $"“{naming.ShapeDescription}”, so I left it where it is — including its date.");

        if (naming.IsNumbered)
            return PlanNumberedInsert(course, section, naming, atDay, count, classes, remembered.Dates, problems);

        // Everything at or after the insertion point moves along: later days
        // of this unit, and every class of every later unit.
        var shifted = classes.Where(c => c.Unit > unit || (c.Unit == unit && c.Day >= atDay)).ToList();
        var untouched = classes.Except(shifted).ToList();

        // The days already spoken for by classes that are NOT moving.
        var held = untouched.Where(c => c.Date is not null).Select(c => c.Date!.Value).ToHashSet();
        var available = remembered.Dates.Where(date => !held.Contains(date)).OrderBy(d => d).ToList();

        // The first day the new classes may take: where the insertion point
        // sits today, or the next free day if this unit ends here.
        DateOnly firstFree = shifted.FirstOrDefault()?.Date
            ?? available.FirstOrDefault(d => d > (untouched.LastOrDefault()?.Date ?? DateOnly.MinValue));
        var runway = available.Where(date => date >= firstFree).ToList();

        int needed = count + shifted.Count;
        if (runway.Count < needed)
        {
            int short_ = needed - runway.Count;
            problems.Add($"This needs {needed} class days from {DateText.Iso(firstFree)} onwards and the " +
                         $"timetable only has {runway.Count}. Add {short_} more class " +
                         $"date{(short_ == 1 ? "" : "s")} and ask again.");
            return new InsertPlan
            {
                CourseCode = course.Code, SectionNumber = section, Unit = unit, AtDay = atDay, Naming = naming,
                Added = Array.Empty<NewClass>(), Renames = Array.Empty<Rename>(),
                Moves = Array.Empty<DateMove>(), LinksToRewrite = 0, Problems = problems,
            };
        }

        string folder = ClassFolder(course, section);
        var added = new List<NewClass>();
        for (int i = 0; i < count; i++)
        {
            string title = naming.Title(unit, atDay + i);
            added.Add(new NewClass(title, Relative(Path.Combine(folder, title + ".md")),
                                   runway[i], atDay + i));
        }

        // Renames: only within the unit being changed. A later unit's Day 1 is
        // still its Day 1 — it simply happens later in the year.
        var renames = new List<Rename>();
        foreach (var moving in shifted.Where(c => c.Unit == unit).OrderByDescending(c => c.Day))
        {
            string to = naming.Title(unit, moving.Day + count);
            renames.Add(new Rename(moving.Title, to, moving.Path, Path.Combine(folder, to + ".md")));
        }

        // Dates: the new classes take the first slots, then everything shifted
        // follows in its existing order.
        var moves = new List<DateMove>();
        for (int i = 0; i < shifted.Count; i++)
        {
            var moving = shifted[i];
            var to = runway[count + i];
            if (moving.Date == to) continue;

            string name = moving.Unit == unit ? naming.Title(unit, moving.Day + count) : moving.Title;
            moves.Add(new DateMove(name, Relative(moving.Path), moving.Date ?? to, to));
        }

        return new InsertPlan
        {
            CourseCode = course.Code,
            SectionNumber = section,
            Unit = unit,
            AtDay = atDay,
            Naming = naming,
            Added = added,
            Renames = renames,
            Moves = moves,
            LinksToRewrite = CountLinksTo(course, section, renames.Select(r => r.From)),
            Problems = problems,
        };
    }

    /// <summary>
    /// The one number a make-room request names in a numbered course, read
    /// from the tool's frozen <c>unit</c>/<c>atDay</c> (<c>insertion.numberedPosition</c>;
    /// mac <c>ClassInsertionPlanner.numberedPosition</c>). Two DIFFERENT numbers
    /// neither of which is 1 cannot be read and give null, so the teacher is
    /// asked rather than having pages renamed at a guess.
    /// </summary>
    public static int? NumberedPosition(int? unit, int? atDay)
    {
        if (unit is null) return atDay;
        if (atDay is null) return unit;
        if (unit == atDay) return unit;
        if (unit == 1) return atDay;
        if (atDay == 1) return unit;
        return null;
    }

    /// <summary>
    /// Making room in a numbered course (#274, mac <c>planNumbered</c>). Pages
    /// order by DATE and the numbers may have gaps (CODING: Weeks 1, 2, 8, 9 on
    /// weekly Thursdays). The new pages take the first free class days after the
    /// LATEST page numbered below the insertion point; a page is renamed only
    /// when a new number lands on its name (the run stops at the first clear
    /// number); and a later page keeps its date when it is already after the
    /// page before it — only a COLLIDING date moves. The ordinary rule, measured
    /// on CODING by the mac, dated a "make room at Week 3" page on Week 8's day
    /// and renamed two published meetings for a slot that was empty.
    /// </summary>
    private InsertPlan PlanNumberedInsert(Course course, int section, ClassPageNaming naming, int atNumber, int count,
                                          List<ClassRef> numbered, IReadOnlyList<DateOnly> timetable, List<string> problems)
    {
        var shifted = numbered.Where(c => c.Day >= atNumber).OrderBy(c => c.Day).ToList();
        var untouched = numbered.Where(c => c.Day < atNumber).ToList();

        var held = untouched.Where(c => c.Date is not null).Select(c => c.Date!.Value).ToHashSet();
        DateOnly? latestKept = untouched.Where(c => c.Date is not null).Select(c => c.Date).Max();
        var runway = timetable.Where(d => !held.Contains(d) && (latestKept is null || d > latestKept.Value))
            .OrderBy(d => d).ToList();

        InsertPlan Refused(string why)
        {
            problems.Add(why);
            return new InsertPlan
            {
                CourseCode = course.Code, SectionNumber = section, Unit = 1, AtDay = atNumber, Naming = naming,
                Added = Array.Empty<NewClass>(), Renames = Array.Empty<Rename>(),
                Moves = Array.Empty<DateMove>(), LinksToRewrite = 0, Problems = problems,
            };
        }

        if (runway.Count < count)
        {
            int missing = count - runway.Count;
            string from = latestKept is { } kept ? DateText.Iso(kept) : "the start of the course";
            return Refused($"This needs {count} class day{(count == 1 ? "" : "s")} after {from} and the timetable " +
                           $"only has {runway.Count}. Add {missing} more class date{(missing == 1 ? "" : "s")} and ask again.");
        }

        string folder = ClassFolder(course, section);
        var added = Enumerable.Range(0, count)
            .Select(offset => (Title: naming.Title(1, atNumber + offset), Offset: offset))
            .Select(x => new NewClass(x.Title, Relative(Path.Combine(folder, x.Title + ".md")),
                                      runway[x.Offset], atNumber + x.Offset))
            .ToList();

        // Renames: only the run whose numbers the new pages land on.
        var newNames = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var upward = new List<Rename>();
        int firstClear = atNumber + count;
        foreach (var page in shifted)
        {
            if (page.Day >= firstClear) break;
            string to = naming.Title(1, firstClear);
            upward.Add(new Rename(page.Title, to, page.Path, Path.Combine(folder, to + ".md")));
            newNames[page.Title] = to;
            firstClear++;
        }
        upward.Reverse();   // highest number first: no rename lands on a name in use

        var byDate = InDateOrder(shifted);
        var destinations = DestinationsKeepingGaps(byDate, runway, count);
        if (destinations is null)
            return Refused("There are not enough class days after the last page to move it onto. " +
                           "Add more class dates and ask again.");

        var moves = new List<DateMove>();
        for (int i = 0; i < byDate.Count; i++)
        {
            if (destinations[i] is not { } to || byDate[i].Date == to) continue;
            moves.Add(new DateMove(newNames.GetValueOrDefault(byDate[i].Title, byDate[i].Title),
                                   Relative(byDate[i].Path), byDate[i].Date, to));
        }

        return new InsertPlan
        {
            CourseCode = course.Code, SectionNumber = section, Unit = 1, AtDay = atNumber, Naming = naming,
            Added = added, Renames = upward, Moves = moves,
            LinksToRewrite = CountLinksTo(course, section, upward.Select(r => r.From)),
            Problems = problems,
        };
    }

    /// <summary>
    /// Pages by date, the number breaking a tie — and an UNDATED page placed by
    /// its number just before the first dated page numbered above it. Not
    /// "undated last": the mac's fix review measured that dating the old Week 1
    /// after Week 8, so the front page would have jumped to it.
    /// </summary>
    private static List<ClassRef> InDateOrder(IEnumerable<ClassRef> pages)
    {
        var dated = pages.Where(p => p.Date is not null).OrderBy(p => p.Date).ThenBy(p => p.Day).ToList();
        var undated = new Queue<ClassRef>(pages.Where(p => p.Date is null).OrderBy(p => p.Day));
        var ordered = new List<ClassRef>();
        foreach (var page in dated)
        {
            while (undated.Count > 0 && undated.Peek().Day < page.Day) ordered.Add(undated.Dequeue());
            ordered.Add(page);
        }
        ordered.AddRange(undated);
        return ordered;
    }

    /// <summary>
    /// Where each shifted page goes in a course that keeps its gaps: a page
    /// already after the page before it stays; otherwise it takes the first
    /// runway day after that page. An undated page stays undated (null). Null
    /// overall when a page has nowhere to go.
    /// </summary>
    private static List<DateOnly?>? DestinationsKeepingGaps(List<ClassRef> shifted, List<DateOnly> runway, int skippingFirst)
    {
        var destinations = new List<DateOnly?>();
        DateOnly? previous = skippingFirst > 0 && skippingFirst <= runway.Count ? runway[skippingFirst - 1] : null;
        foreach (var page in shifted)
        {
            if (page.Date is not { } own) { destinations.Add(null); continue; }
            DateOnly? chosen = previous is null || own > previous.Value ? own : null;
            chosen ??= runway.Where(d => previous is null || d > previous.Value).Cast<DateOnly?>().FirstOrDefault();
            if (chosen is null) return null;
            destinations.Add(chosen);
            previous = chosen;
        }
        return destinations;
    }

    /// <summary>How many links across the section point at any of these page names.</summary>
    private int CountLinksTo(Course course, int section, IEnumerable<string> titles)
    {
        var names = titles.ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (names.Count == 0) return 0;

        int total = 0;
        foreach (string path in Pages(course, section))
        {
            string text;
            try { text = File.ReadAllText(PagePaths.ResolveInside(_folder, path)); }
            catch { continue; }

            // The shared rewriter's own count (#339, #318): a link inside code
            // or a comment is not counted, and an escaped pipe is a link.
            total += WikiLinks.CountLinksTo(names, text);
        }
        return total;
    }

    /// <summary>Carry out the insertion: rename, re-date, relink, then create the blanks.</summary>
    public AssistResult ApplyInsertClasses(InsertPlan plan, IProgress<string>? progress = null) =>
        ApplyInsertClasses(plan, progress, out _);

    /// <param name="created">The full paths of the blank class pages this run
    /// WROTE — a page already standing at a path is not among them. The
    /// duplicate asks it, because it is the one question link rewriting and
    /// date moves cannot fool (#200 A).</param>
    private AssistResult ApplyInsertClasses(InsertPlan plan, IProgress<string>? progress, out List<string> created)
    {
        created = new List<string>();
        var course = Course(plan.CourseCode);
        int section = Section(course, plan.SectionNumber);
        if (plan.ChangesNothing)
            return new AssistResult(true, "Nothing needed moving.", null);
        if (plan.Added.Count == 0)
            throw new AssistRefusal(string.Join(" ", plan.Problems));

        RefuseIfPlantoirIsBuilding(course);

        string backup;
        try { backup = BackUpOnceForThisConversation(course, plan.SectionNumber); }
        catch (Exception error)
        {
            throw new AssistRefusal(
                $"{course.Code} couldn’t be backed up, so nothing was moved: {error.Message}");
        }

        // NO undo entry of its own, deliberately — and this is the mac's rule
        // rather than a Windows shortcut (`AssistToolRunner.makeRoomForClasses`
        // records nothing either). Making room renames later days, re-dates
        // every class from the insertion point onwards and rewrites the links
        // that pointed at the old names; an undo that put some of that back
        // and not the rest would leave a course in a state nobody chose. The
        // way back is the backup taken above, which the reply names.
        //
        // It used to call Begin here and never End, which is worse than
        // either: no entry was recorded AND the next operation's files were
        // swallowed into the open one under this description.
        //
        // The Touch/Wrote calls below stay. They do nothing while no entry is
        // open, and they are what lets a CALLER that opened its own entry —
        // ApplyDuplicateClass — record the whole of what happened.

        // Every count in the reply is of what was WRITTEN, as the mac's
        // ClassInsertionPlanner counts (#422): a rename skipped because its
        // new name is taken, or a write that failed, is not "renamed", and
        // links are counted only where a page holding them was saved. A write
        // that did not finish is NAMED (by the page's name at that moment),
        // never swallowed.
        var notFinished = new List<string>();
        int notRenamed = 0, notReDated = 0, linkPagesNotSaved = 0;

        // Highest day first, so a rename never lands on a name still in use.
        progress?.Report("Renaming the classes that come after…");
        var renamed = new List<Rename>();
        foreach (var rename in plan.Renames)
        {
            if (!File.Exists(rename.FromPath)) continue;   // nothing there to rename
            bool saved = false;
            try
            {
                if (File.Exists(rename.ToPath)) throw new IOException("the new name is taken");
                string text = File.ReadAllText(rename.FromPath);
                Save(rename.ToPath, PageFrontmatter.SetTitle(text, rename.To));
                saved = true;
                _undo?.Touch(rename.FromPath, text);
                File.Delete(rename.FromPath);
                _undo?.Wrote(rename.FromPath, null);
                renamed.Add(rename);
            }
            catch
            {
                // Saved under the new name but the old file is still there:
                // the links follow the new name (it exists), and the page is
                // named so the teacher finds the second copy.
                if (saved) renamed.Add(rename);
                notFinished.Add(rename.From);
                notRenamed++;
            }
        }

        progress?.Report("Following the links that pointed at them…");
        var (linksUpdated, linkPagesFailed) = RewriteLinks(course, section, renamed);
        notFinished.AddRange(linkPagesFailed);
        linkPagesNotSaved = linkPagesFailed.Count;

        progress?.Report("Moving the dates…");
        string tail = SiblingTimeAndOffset(course, section, ClassPages(course, section));
        // A class the writer could not date (#308, the mac's #186) is NAMED —
        // by its new name, since by now it has been renamed and moved.
        var undated = new List<string>();
        // Counted from what was WRITTEN (#308 review F1, as the mac's
        // ClassInsertionPlanner counts): a class declined, already on its
        // date, or whose write failed is not "moved".
        int moved = 0;
        // A rename that did not happen leaves its page under the OLD name — and
        // the new name may be a page of the teacher's own (that is usually why
        // it did not happen), which must not be given this class's date.
        var notRenamedTo = plan.Renames.Where(r => !renamed.Contains(r))
            .Select(r => r.To).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var move in plan.Moves)
        {
            string? full = null;
            try
            {
                // Renamed pages are found under their NEW name by now.
                full = notRenamedTo.Contains(move.Title)
                    ? PagePaths.ResolveInside(_folder, move.RelativePath)
                    : Path.Combine(ClassFolder(course, section), move.Title + ".md");
                if (!File.Exists(full)) full = PagePaths.ResolveInside(_folder, move.RelativePath);
                if (!File.Exists(full)) continue;

                bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, full);
                string key = sectionLocal ? "created" : "createdSection" + section;
                var edit = PageFrontmatter.SetCreated(File.ReadAllText(full), key, move.To, tail);
                // By the name the page has NOW: renamed if its rename went through.
                if (edit.Outcome == FrontmatterWriteOutcome.NoRoomForAKey) undated.Add(Path.GetFileNameWithoutExtension(full));
                if (edit.Changed)
                {
                    Save(full, edit.Text);
                    moved++;
                }
            }
            catch
            {
                notFinished.Add(full is not null && File.Exists(full) ? Path.GetFileNameWithoutExtension(full) : move.Title);
                notReDated++;
            }
        }
        NoteSettingsLeftAsTheyWere("making room for a class", undated.Count, course.Code, section);

        progress?.Report("Adding the new classes…");
        Directory.CreateDirectory(ClassFolder(course, section));
        int notAdded = 0;
        foreach (var added in plan.Added)
        {
            string path = Path.Combine(ClassFolder(course, section), added.Title + ".md");
            // Still taken: the class whose rename did not happen is there.
            // Not overwritten, and named rather than counted as made.
            if (File.Exists(path)) { notFinished.Add(added.Title); notAdded++; continue; }
            Save(path, ClassSkeleton(added, plan.Naming.IsNumbered ? null : plan.Unit, plan.Added.Count, tail));
            created.Add(path);
        }

        int unfinishedPages = notFinished.Distinct(StringComparer.OrdinalIgnoreCase).Count();
        if (unfinishedPages > 0)
            ActivityTrail.Note(ActivityTrail.Event.MakingRoomDidNotFinishEveryPage,
                $"making room for a class did not finish {(unfinishedPages == 1 ? "1 page" : $"{unfinishedPages} pages")}: " +
                $"{notRenamed} not renamed, {notReDated} not re-dated, {linkPagesNotSaved} with links not updated, " +
                $"{notAdded} new not added",
                course.Code, section);

        string said =
            (created.Count > 0 ? AssistWording.MadeRoom(created.Count, plan.PositionTitle) + " " : "") +
            $"Renamed {renamed.Count}, moved {moved} onto " +
            $"later class days, and updated {linksUpdated} link" +
            $"{(linksUpdated == 1 ? "" : "s")}. The new pages are unpublished until you write them. " +
            AssistWording.LookTheSectionOverBeforePublishing;
        if (undated.Count > 0) said += " " + AssistWording.PagesWhoseNewDatesCouldNotBeSet(undated);
        if (notFinished.Count > 0)
            said += " " + AssistWording.PagesAChangeCouldNotFinish(notFinished.Distinct(StringComparer.OrdinalIgnoreCase).ToList());

        // Said because it is now TRUE and was not said before: this records no
        // undo entry, so "undo that" afterwards reaches back past it to
        // whatever the conversation did before — or answers that nothing has
        // been changed. The mac says the same sentence, on the same condition
        // (`makeRoomForClasses` → `movesAnythingElse`).
        if (plan.Renames.Count > 0 || plan.Moves.Count > 0)
            said += "\n\n" + ClassChangeWording.OtherClassesMoved(backup);

        return new AssistResult(true, said, backup);
    }

    // ---- Duplicating a lesson as the next class ----------------------------

    /// <summary>
    /// Work out what "duplicate Unit 3, Day 2 as my next class" would do,
    /// changing nothing.
    ///
    /// <para>The copy becomes the SOURCE'S next day — Unit 3, Day 3 — not a
    /// page after the last class of the course. Everything from there on
    /// shuffles, which <see cref="PlanInsertClasses"/> works out; this adds
    /// only which page is being copied and what it becomes.</para>
    /// </summary>
    /// <exception cref="AssistRefusal">
    /// No such page, a page that is not numbered, a section with no remembered
    /// timetable, a timetable with no day left, or a page that cannot be read.
    /// </exception>
    public DuplicateClassPlan PlanDuplicateClass(string courseCode, int sectionNumber, string pageTitle)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);

        // ONE refusal for "no such page", reused rather than reworded. A
        // second sentence for a fact a teacher already meets elsewhere is how
        // two wordings for one thing start.
        string path = Page(course, section, pageTitle);
        string sourceTitle = Path.GetFileNameWithoutExtension(path);

        var numbers = course.Configuration.Naming.Parse(sourceTitle)
            ?? throw new AssistRefusal(
                ClassChangeWording.NotANumberedClassPage(sourceTitle));

        // The source's own next day. Throws the timetable refusal unchanged,
        // which is the sentence that asks for the class dates.
        var insertion = PlanInsertClasses(course.Code, section, numbers.Unit, numbers.Day + 1, 1);
        if (insertion.Added.Count == 0)
        {
            string why = string.Join(" ", insertion.Problems);
            throw new AssistRefusal(why.Length > 0 ? why : ClassChangeWording.NoClassDateLeft);
        }

        string sourceText;
        try { sourceText = File.ReadAllText(path); }
        catch { throw new AssistRefusal(ClassChangeWording.CouldNotBeRead(sourceTitle)); }

        var added = insertion.Added[0];
        return new DuplicateClassPlan
        {
            CourseCode = course.Code,
            SectionNumber = section,
            SourceTitle = sourceTitle,
            SourceText = sourceText,
            NewTitle = added.Title,
            NewDate = added.Date,
            Insertion = insertion,
        };
    }

    /// <summary>
    /// Make the copy: room first, then the source's words under a new title, a
    /// date of its own, and hidden.
    /// </summary>
    /// <remarks>
    /// <para><b>Hidden however the source was.</b> A page made by duplicating
    /// a published lesson is a draft of next week's, and putting it in front
    /// of students the moment it is made is the one thing it must not do. The
    /// body is copied verbatim — including the frontmatter keys belonging to
    /// OTHER sections, which is what the mac does and what a teacher copying a
    /// shared page would expect.</para>
    ///
    /// <para><b>Undoable only when nothing else moved.</b> The entry is opened
    /// HERE, before <see cref="ApplyInsertClasses"/> — which records nothing of
    /// its own — so this either records the whole change or records none of
    /// it. A partial undo that deleted the copy and left every later class
    /// renamed and re-dated would be worse than no undo at all, so when
    /// classes shuffled the entry is abandoned and the reply names the backup
    /// instead.</para>
    /// </remarks>
    public AssistResult ApplyDuplicateClass(DuplicateClassPlan plan, IProgress<string>? progress = null)
    {
        var course = Course(plan.CourseCode);
        int section = Section(course, plan.SectionNumber);
        string newPath = Path.Combine(ClassFolder(course, section), plan.NewTitle + ".md");

        // OUTERMOST, and that is the whole of why this reads the way it does.
        // Begin ignores a nested call, so whoever opens the entry first owns
        // the description — and everything ApplyInsertClasses writes lands in
        // this one. Leaving without reaching Done abandons it, so every
        // refusal below is safe by construction rather than by remembering.
        using var recording = UndoHistory.Record(_undo,
            $"duplicated “{plan.SourceTitle}” as “{plan.NewTitle}”");

        AssistResult inserted = ApplyInsertClasses(plan.Insertion, progress, out var created);

        // The one case that could destroy a lesson (#200 A, the mac's #163).
        // Asked of the PLANNER — did this run write the page standing there? —
        // not of the page's text. The text comparison this replaced was
        // defeated by the link pass: a destination whose rename was skipped
        // but which linked to a page that WAS renamed came back with different
        // text, read as "not the same page", and the copy was written over the
        // lesson. Deliberately not ANDed with "was a page there before?": a
        // sample taken before the shuffle is blind to a page appearing during
        // it, and Obsidian being open in the other window is the premise.
        if (!created.Contains(newPath, StringComparer.OrdinalIgnoreCase))
        {
            ActivityTrail.Note(ActivityTrail.Event.ClassCopyNotMade,
                "did not copy a class — the page the copy would have become still held a lesson, " +
                "and other classes may already have moved", course.Code, section);
            throw new AssistRefusal(
                ClassChangeWording.ThePlaceForTheCopyIsStillTaken(plan.NewTitle, inserted.BackupPath));
        }

        progress?.Report($"Copying “{plan.SourceTitle}”…");
        bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, newPath);
        // #200 B: REMOVE what the copy inherited, never add a per-section key
        // to hide it — see PageFrontmatter.WithoutPerSectionKeys for the page
        // that could never be published again while the reply said it was.
        string copied = PageFrontmatter.WithoutPerSectionKeys(plan.SourceText);
        copied = PageFrontmatter.SetTitle(copied, plan.NewTitle);
        copied = PageFrontmatter.SetCreated(
            copied, PageFrontmatter.CreatedKeyFor(section, sectionLocal), plan.NewDate,
            SiblingTimeAndOffset(course, section, ClassPages(course, section))).Text;
        copied = PageFrontmatter.SetDraft(
            copied, PageFrontmatter.PublishKeyFor(section, sectionLocal), draft: true, section).Text;

        // Read back what is about to be written and ABANDON the copy rather
        // than write one this app cannot vouch for. `!= Hidden`, not
        // `== Visible`: "cannot tell" may well be published by the build.
        // Reachable — a TAB used as indentation in the source's block, or a
        // block whose first line is indented (SetDraft declines, #186) — and
        // safe: the blank the insertion wrote here is `publish: false`.
        if (PageFrontmatter.Visibility(copied, section) != PageVisibility.Hidden)
        {
            ActivityTrail.Note(ActivityTrail.Event.ClassCopyNotMade,
                "did not copy a class — the copy could not be made certainly hidden, and a copy " +
                "of a published lesson must never arrive where students can read it", course.Code, section);
            throw new AssistRefusal(
                ClassChangeWording.TheCopyCouldNotBeMadeHidden(plan.SourceTitle, plan.NewTitle, inserted.BackupPath));
        }

        Save(newPath, copied);

        // Recorded ONLY when nothing else moved. Left unsettled otherwise, so
        // the scope abandons it: a partial undo that deleted the copy and left
        // every later class renamed and re-dated is worse than no undo at all,
        // and the reply names the backup instead.
        if (!plan.MovesOtherClasses) recording.Done();

        string said = ClassChangeWording.CopiedTo(plan.SourceTitle, plan.NewTitle, plan.NewDate);
        if (plan.MovesOtherClasses)
        {
            // What moved, and — already the last paragraph of that message, on
            // exactly this condition — that the backup is the way back rather
            // than "undo that". Saying ClassChangeWording.OtherClassesMoved
            // here as well would print it twice.
            said += "\n\n" + inserted.Message;
        }
        else
        {
            said += "\n\n" + AssistWording.ACreatedPageCanBeTakenBack;
        }

        return new AssistResult(true, said, inserted.BackupPath);
    }

    /// <summary>
    /// Point every link at a renamed page's new name.
    ///
    /// Obsidian does this itself when OBSIDIAN performs the rename. This one
    /// happens on disk, from another process — which Obsidian reads as a
    /// delete and a create, leaving links alone — and Obsidian may not be
    /// running at all. So it cannot be delegated. What Obsidian is good for is
    /// the list of forms that have to survive, and all of them do:
    /// <c>[[Page]]</c>, <c>[[Page|alias]]</c>, <c>![[Page]]</c>,
    /// <c>[[Page#Heading]]</c>, <c>[[Page#^block]]</c> and the combinations,
    /// because the pattern stops at <c>#</c> and <c>|</c> and only the name
    /// between the brackets moves.
    ///
    /// The one form NOT handled is Obsidian's optional Markdown-style link,
    /// <c>[text](Unit%202,%20Day%203.md)</c>. Every page Plantoir ships uses
    /// wikilinks, and the rest of the toolchain only understands those, so a
    /// vault switched to Markdown links has bigger problems than this — but it
    /// is a real gap and belongs written down rather than discovered.
    /// </summary>
    /// <returns>How many links were rewritten on pages that were SAVED (the
    /// shared rewriter's own count, as the plan counts them), and the names of
    /// the pages whose rewritten links could not be saved (#422).</returns>
    private (int Links, List<string> NotSaved) RewriteLinks(Course course, int section, IReadOnlyList<Rename> renames)
    {
        var notSaved = new List<string>();
        if (renames.Count == 0) return (0, notSaved);
        var byName = renames.ToDictionary(r => r.From, r => r.To, StringComparer.OrdinalIgnoreCase);
        var oldNames = byName.Keys.ToHashSet(StringComparer.OrdinalIgnoreCase);
        int links = 0;

        foreach (string relative in Pages(course, section))
        {
            string full;
            string text;
            try
            {
                full = PagePaths.ResolveInside(_folder, relative);
                text = File.ReadAllText(full);
            }
            catch { continue; }

            // Only the TARGET is rewritten; an alias after "|" is the
            // teacher's own words and stays exactly as written, and so do an
            // escaping backslash and a link inside code or a comment (#318,
            // #339) — the one shared rewriter.
            string updated = WikiLinks.Rewriting(text, byName);
            if (updated == text) continue;

            try
            {
                Save(full, updated);
                links += WikiLinks.CountLinksTo(oldNames, text);
            }
            catch { notSaved.Add(Path.GetFileNameWithoutExtension(full)); }
        }
        return (links, notSaved);
    }

    // ---- Laying down a unit that has not been written yet ------------------

    /// <summary>
    /// Plan the class pages for a unit, on the section's own meeting dates.
    ///
    /// The dates come from <see cref="TimetableMemory"/> and the ones already
    /// spoken for are skipped, so "give me seven days in Unit 3" lands on the
    /// next seven days this class actually meets rather than the next seven
    /// days in the calendar. A teacher should never have to work that out.
    /// </summary>
    /// <summary>
    /// The day number a unit's next class takes: one past the highest day that
    /// already EXISTS in it, or 1 for a unit with no pages yet.
    /// </summary>
    /// <remarks>
    /// <para><b>Worked out rather than asked for, since 2026-09-09.</b>
    /// <c>add_classes</c> and <c>plan_add_classes</c> used to take a
    /// <c>firstDay</c> argument described as "1 unless the earlier days
    /// already exist" — a question the caller could only answer by going and
    /// looking at the section, and one it could get wrong. Left at its
    /// default, "add five more days to Unit 4" on a unit that already has
    /// Days 1–3 planned Days 1–5, reported three of them as already there,
    /// and created TWO pages for a teacher who asked for five.</para>
    ///
    /// <para>Counted from the pages on disk, published or NOT: a class a
    /// teacher has written and not yet shown anybody is still a day of the
    /// course, and numbering over it would collide with a real file. The mac
    /// has never taken the argument, and
    /// <c>contracts/assist-cases.json</c> describes neither tool as having
    /// one — an argument nobody can get wrong beats one with a sensible
    /// default. See issue #70.</para>
    /// </remarks>
    public int DayToCarryOnFrom(string courseCode, int sectionNumber, int unit)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);

        int highestDay = 0;
        foreach (string page in ClassPages(course, section))
        {
            string title = Path.GetFileNameWithoutExtension(page) ?? "";
            if (course.Configuration.Naming.Parse(title) is { } found
                && found.Unit == unit && found.Day > highestDay)
                highestDay = found.Day;
        }
        return highestDay + 1;
    }

    public NewClassesPlan PlanAddClasses(string courseCode, int sectionNumber, int unit,
                                         int firstDay, int count)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);

        if (unit < 1) throw new AssistRefusal("A unit number starts at 1.");
        if (firstDay < 1) throw new AssistRefusal("A day number starts at 1.");
        if (count < 1) throw new AssistRefusal("Ask for at least one class.");
        var naming = course.Configuration.Naming;
        // A numbered course has one run of pages and no units (#274): any
        // unit but the one it is held as is refused BEFORE the dates are asked for.
        if (naming.IsNumbered && unit != 1)
            throw new AssistRefusal(NextClassPlanner.NoUnitsInANumberedCourse(course.Code, naming.Word));

        var remembered = TimetableMemory.Read(_folder, course.Code, section)
            ?? throw new AssistRefusal(
                $"I don’t know when {course.Code} Section {section} meets, so I can’t date new classes. {AssistWording.MayIAskForYourDates}");

        if (remembered.Dates.Count == 0)
            throw new AssistRefusal(
                $"I don’t know when {course.Code} Section {section} meets, so I can’t date new classes. {AssistWording.MayIAskForYourDates}");

        string folder = ClassFolder(course, section);
        var existing = ClassPages(course, section);

        // Dates already carried by a class page are spoken for. Working from
        // what the pages SAY, rather than counting from the start of the year,
        // means a course that has already been re-dated or reshuffled still
        // gets the right answer.
        var taken = new HashSet<DateOnly>();
        foreach (string page in existing)
            if (DateOf(course, section, page) is { } date) taken.Add(date);

        var free = remembered.Dates.Where(date => !taken.Contains(date)).ToList();

        // A numbered course orders by DATE and may have gaps (#274; mac
        // NextClassPlanner.positionAfterTheLatestPage): its next page goes on
        // the first class day after the LATEST dated page. The free-date rule
        // gave CODING's Week 10 a date five weeks before Week 8.
        if (naming.IsNumbered && taken.Count > 0)
            free = free.Where(date => date > taken.Max()).ToList();

        var classes = new List<NewClass>();
        var alreadyThere = new List<string>();
        var problems = new List<string>();
        int sharingCount = 0;

        for (int i = 0; i < count; i++)
        {
            int day = firstDay + i;
            string title = naming.Title(unit, day);
            string path = Path.Combine(folder, title + ".md");

            // Never written over. A page with this name may be a lesson the
            // teacher wrote months ago.
            if (File.Exists(path)) { alreadyThere.Add(title); continue; }

            DateOnly classDate;
            if (classes.Count < free.Count)
            {
                classDate = free[classes.Count];
            }
            else
            {
                classDate = remembered.Dates[^1];
                sharingCount++;
            }
            classes.Add(new NewClass(title, Relative(path), classDate, day));
        }

        return new NewClassesPlan
        {
            CourseCode = course.Code,
            SectionNumber = section,
            Unit = unit,
            Naming = naming,
            Classes = classes,
            AlreadyThere = alreadyThere,
            Problems = problems,
            SpareDatesLeft = Math.Max(0, free.Count - classes.Count),
            SharingTheLastDay = sharingCount,
        };
    }

    public NewClassesPlan PlanAddNextClass(string courseCode, int sectionNumber, string? unitAsked = null, int? days = null)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        var naming = course.Configuration.Naming;

        // A numbered course (#274) has no units, so "start a new unit" and
        // "add three more days to Unit 1" have nothing to act on — refused
        // BEFORE the dates are asked for (class-planning.json → refusals).
        bool aboutAUnit = string.Equals(unitAsked, "next", StringComparison.OrdinalIgnoreCase)
                          || (days is > 0 && int.TryParse(unitAsked, out _));
        if (naming.IsNumbered && aboutAUnit)
            throw new AssistRefusal(NextClassPlanner.NoUnitsInANumberedCourse(course.Code, naming.Word));

        var remembered = TimetableMemory.Read(_folder, course.Code, section)
            ?? throw new AssistRefusal(
                $"I don’t know when {course.Code} Section {section} meets, so I can’t date a new class. {AssistWording.MayIAskForYourDates}");

        if (remembered.Dates.Count == 0)
            throw new AssistRefusal(
                $"I don’t know when {course.Code} Section {section} meets, so I can’t date a new class. {AssistWording.MayIAskForYourDates}");

        var existing = ClassPages(course, section);
        var existingTitles = existing.Select(p => Path.GetFileNameWithoutExtension(p) ?? "").ToList();

        if (days is { } howMany && howMany > 0 && int.TryParse(unitAsked, out int specificUnit))
            return PlanAddClasses(courseCode, sectionNumber, specificUnit,
                                  DayToCarryOnFrom(courseCode, sectionNumber, specificUnit), howMany);

        bool startingANewUnit = string.Equals(unitAsked, "next", StringComparison.OrdinalIgnoreCase);
        UnitDay next = startingANewUnit
            ? NextClassPlanner.FirstDayOfANewUnit(existingTitles, course.Configuration.UnitWord)
            : NextClassPlanner.NextUnitAndDay(existingTitles, naming);

        return PlanAddClasses(courseCode, sectionNumber, next.Unit, next.Day, 1);
    }

    /// <summary>Create the pages the plan describes. Backed up first, and undoable.</summary>
    public AssistResult ApplyAddClasses(NewClassesPlan plan, IProgress<string>? progress = null)
    {
        var course = Course(plan.CourseCode);
        int section = Section(course, plan.SectionNumber);
        if (plan.ChangesNothing)
            return new AssistResult(true, "Nothing to add — those classes already exist.", null);

        RefuseIfPlantoirIsBuilding(course);

        string backup;
        try { backup = BackUpOnceForThisConversation(course, plan.SectionNumber); }
        catch (Exception error)
        {
            throw new AssistRefusal(
                $"{course.Code} couldn’t be backed up, so no pages were created: {error.Message}");
        }

        // Undoable, and the END is what makes that true. `Save` records each
        // created page with no "before" at all, so undo deletes it — which is
        // exactly what AssistWording.ACreatedPageCanBeTakenBack promises the
        // teacher, and what this tool did not do until 2026-09-18 because the
        // entry was opened and never closed. Nothing here renames or re-dates
        // anything else, so there is no partial-undo question to ask: the mac
        // records this one too (AssistToolRunner, the placeholder-class path).
        using var recording = UndoHistory.Record(_undo,
            $"added {plan.Classes.Count} class pages to " +
            (plan.Naming.UnitName(plan.Unit) is { } unitName ? unitName + " of " : "") +
            $"{course.Code} Section {section}");

        // Match the time of day and UTC offset the section's existing classes
        // use, so a new page sorts beside them rather than at midnight.
        string tail = SiblingTimeAndOffset(course, section, ClassPages(course, section));
        string folder = ClassFolder(course, section);
        Directory.CreateDirectory(folder);

        foreach (var created in plan.Classes)
        {
            string path = Path.Combine(folder, created.Title + ".md");
            if (File.Exists(path)) continue;       // checked again: the plan may be minutes old
            Save(path, ClassSkeleton(created, plan.Naming.IsNumbered ? null : plan.Unit, plan.Classes.Count, tail));
        }
        recording.Done();

        return new AssistResult(true,
            $"Created {plan.Classes.Count} class page{(plan.Classes.Count == 1 ? "" : "s")} in " +
            (plan.Naming.UnitName(plan.Unit) is { } unitIn ? unitIn + " of " : "") +
            $"{course.Code} Section {section}, dated " +
            $"{DateText.Iso(plan.Classes[0].Date)} to {DateText.Iso(plan.Classes[^1].Date)}. " +
            "They are unpublished, so nothing changed in the site — write them, then publish when ready.",
            backup);
    }

    /// <summary>Where a section's class pages live.</summary>
    /// <summary>
    /// What this course calls a unit. By CODE, because several planning paths
    /// carry the code rather than the course.
    /// </summary>
    public string UnitWordForCourse(string courseCode) => UnitWordFor(courseCode);

    /// <summary>
    /// A message with what the build found about the course added, as
    /// <see cref="Models.SiteHealthFinding.Appending"/> — except that the
    /// links-into-hidden-pages finding says
    /// <see cref="AssistWording.LinksIntoHiddenPagesWillBeOffered"/> instead of
    /// its pairs (#392, mac #379), ONLY when the same build printed the
    /// checklist marker, the offer on disk is that build's, and it holds
    /// something the teacher has not answered — so it never promises a sheet
    /// that will not come. Otherwise the finding's own words.
    /// </summary>
    private static string AppendingFindings(Course course, int section, LaunchOutcome build, string message)
    {
        var findings = build.Findings;
        if (findings is null || findings.Count == 0) return message;
        bool offered = build.LinksChecklist is { } marker
            && string.Equals(marker.Course, course.Code, StringComparison.OrdinalIgnoreCase)
            && marker.Section == section && marker.Pages > 0
            && LinksChecklistShowing.AfterAWatchedBuild(course, section, marker) is not null;
        if (!offered) return Models.SiteHealthFinding.Appending(message, findings);
        var parts = new List<string> { message };
        foreach (var finding in findings)
            parts.Add(finding.Name == LinksIntoHiddenPagesFinding && finding.Section == section
                ? AssistWording.LinksIntoHiddenPagesWillBeOffered(course.Code, section.ToString())
                : finding.Sentence + " " + finding.Detail);
        return string.Join("\n\n", parts);
    }

    /// <summary>The site-health check whose finding the links checklist answers (<c>siteHealth.linksIntoHiddenPages</c>).</summary>
    internal const string LinksIntoHiddenPagesFinding = "linksIntoHiddenPages";

    /// <summary>
    /// What the front-page pointer needs for one class of one section (#274,
    /// #406): every class title, the class, its place INSIDE the course folder
    /// (never the disk path) and the course's recorded heading.
    /// </summary>
    internal SectionIndex.Pointer PointerFor(Course course, int section, string classPath) =>
        new(ClassPages(course, section).Select(page => Path.GetFileNameWithoutExtension(page)).ToList(),
            Path.GetFileNameWithoutExtension(classPath),
            Path.GetRelativePath(course.DirectoryPath, Path.GetFullPath(classPath)).Replace(Path.DirectorySeparatorChar, '/'),
            course.Configuration.FrontPageHeading);

    /// <summary>
    /// Whether pressing Preview should offer today's class for the front page
    /// (#406). Called by the section window's Preview button ONLY.
    /// </summary>
    public TodaysClassOnTheFrontPage.Offering? TodaysClassOffer(string courseCode, int sectionNumber, DateOnly today)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        return TodaysClassOnTheFrontPage.Offer(course, section, ClassPages(course, section),
                                               SectionIndex.PathFor(course, section), today);
    }

    /// <summary>Show on Front Page, decided again for the day the question was asked.</summary>
    public TodaysClassOnTheFrontPage.Outcome ShowTodaysClass(string courseCode, int sectionNumber, DateOnly askedOn,
                                                             TodaysClassOnTheFrontPage.Offering offering)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        var classes = ClassPages(course, section);
        return TodaysClassOnTheFrontPage.ShowOnTheFrontPage(course, section, classes, SectionIndex.PathFor(course, section),
            askedOn, offering, path => PointerFor(course, section, path), SiblingTimeAndOffset(course, section, classes));
    }

    /// <summary>Not Today, remembered for this section, day and class.</summary>
    public void DeclineTodaysClass(string courseCode, int sectionNumber, DateOnly askedOn,
                                   TodaysClassOnTheFrontPage.Offering offering)
    {
        var course = Course(courseCode);
        TodaysClassOnTheFrontPage.RecordNotToday(course, Section(course, sectionNumber), askedOn, offering);
    }

    /// <summary>
    /// What this course's TEACHER hears a class page called (#274). For the
    /// teacher's copy only; the model's copy is always the class form.
    /// </summary>
    public ClassNoun NounForCourse(string courseCode)
    {
        try { return Course(courseCode).Configuration.ClassNoun; }
        catch (AssistRefusal) { return ClassNoun.Class; }
    }

    /// <summary>How this course names its class pages — word AND scheme (#274).</summary>
    public ClassPageNaming NamingForCourse(string courseCode)
    {
        try { return Course(courseCode).Configuration.Naming; }
        catch (AssistRefusal) { return ClassPageNaming.Standard; }
    }

    private string UnitWordFor(string courseCode)
    {
        try { return Course(courseCode).Configuration.UnitWord; }
        catch (AssistRefusal) { return ClassPageTerm.DefaultWord; }
    }

    /// <summary>
    /// A page's path relative to its SECTION folder, which is the form the
    /// class-page rule needs.
    ///
    /// <para>Nothing above the section can reach the rule this way, so what a
    /// teacher called their working folder cannot change what counts as a
    /// lesson — and neither can what they called their COURSE folder, nor the
    /// <c>courses</c> folder itself. <see cref="Relative"/> is relative to the
    /// working folder, so its segments still include <c>courses</c>, the course
    /// code and <c>sectionN</c>; that was enough for the
    /// <c>C:\Users\x\Classroom</c> bug and not enough for the rest.</para>
    ///
    /// <para>A page OUTSIDE the section folder — every course-level SHARED
    /// page, which <c>PagePaths.MarkdownPages</c> deliberately includes —
    /// falls back to its own file NAME, so it is never a class page. Returning
    /// the last two components instead, which is what the mac tried first,
    /// puts the immediate parent's name back in front of the rule: that is the
    /// discredited "does the parent mention classes" sniff, and a false
    /// POSITIVE waiting to happen, because a course-level shared folder called
    /// "All Classes" would then make every shared page under it a lesson of
    /// every section. A shared page is not a class page; say so plainly rather
    /// than guess from a fragment of path.</para>
    ///
    /// <para>Mirrors <c>AssistSectionGraph.pathWithinSection</c> on the mac —
    /// its CODE, which returns <c>url.lastPathComponent</c>; that method's own
    /// header comment still says "last two components" and is stale.</para>
    /// </summary>
    private static string PathWithinSection(Course course, int sectionNumber, string fullPath)
    {
        string root;
        string full;
        try
        {
            root = Path.GetFullPath(course.SectionDirectory(sectionNumber));
            full = Path.GetFullPath(fullPath);
        }
        catch { return Path.GetFileName(fullPath); }

        if (!root.EndsWith(Path.DirectorySeparatorChar)) root += Path.DirectorySeparatorChar;
        // Case-insensitively, because Windows paths are: a page reached as
        // SECTION1\... must not read as a page outside section1.
        if (full.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            return full[root.Length..];
        return Path.GetFileName(full);
    }

    private static string ClassFolder(Course course, int sectionNumber)
    {
        // The naming half of the shared rule
        // (contracts/class-planning.json -> classFolder.naming).
        return Path.Combine(course.SectionDirectory(sectionNumber),
                            ClassFolderRule.Name(course.Configuration.ClassFolder,
                                                 course.Configuration.PerSectionFolders));
    }

    /// <summary>
    /// An empty class page in the shape every other class page takes.
    ///
    /// The teacher's own template, down to the frontmatter keys — with one
    /// deliberate difference. It starts <c>publish: false</c>: a page nobody
    /// has written yet has no business appearing in the site, and the teacher
    /// asked for exactly that.
    /// </summary>
    private static string ClassSkeleton(NewClass created, int? unit, int howMany, string tail)
    {
        string plural = howMany == 1 ? "This page was" : $"{howMany} of these were";
        // A numbered course has no units, so its page carries no unit tag —
        // the club start in setup_course.py writes "Week 1" untagged too.
        string tags = unit is { } u ? $"tags:\n  - unit-{u}\n" : "";
        return $"""
            ---
            title: {created.Title}
            publish: false
            created: {DateText.Iso(created.Date)}{tail}
            transcludeTitleSize: h2
            enableToc: false
            excludeBacklinks: true
            {tags}---

            %%
            This is the shape every class page takes: a numbered agenda of what
            happened, with links to the pages it used, then a short list of things
            to do before next time. Nothing is explained here — the links do that.

            {plural} created for you, dated to the days this class actually meets.
            Rename them, add more, delete the ones you do not need. The `created:`
            date is what puts them in order under All Classes, so a new page needs
            one of its own.

            This page is unpublished. Write it, then publish it when it is ready.
            Delete this comment when you do — comments never reach the site either.
            %%

            ## Agenda

            1.

            ## Things to do before our next class

            - [ ]

            """;
    }

    private void Save(string path, string text)
    {
        string? before = null;
        try { if (File.Exists(path)) before = File.ReadAllText(path); } catch { }
        _undo?.Touch(path, before);
        File.WriteAllText(path, text);
        _undo?.Wrote(path, text);
    }

    /// <summary>A path as the teacher sees it: relative to the working folder, forward slashes.</summary>
    public string Relative(string fullPath) =>
        Path.GetRelativePath(_folder, fullPath).Replace('\\', '/');

    private static string Humanize(IEnumerable<string> items)
    {
        var list = items.ToList();
        if (list.Count == 0) return "none";
        if (list.Count == 1) return list[0];
        return string.Join(", ", list.Take(list.Count - 1)) + " and " + list[^1];
    }
}

/// <summary>
/// A request that will not be carried out, with a reason a teacher can act on.
/// Never a stack trace, never a code — the assistant reads this back aloud.
/// </summary>
public sealed class AssistRefusal(string message) : Exception(message);

/// <summary>How an operation ended, and where the backup went.</summary>
public sealed record AssistResult(bool Succeeded, string Message, string? BackupPath);

/// <summary>
/// Runs one of the working folder's launchers. Abstracted so the plan logic can
/// be tested without Docker, and so the same operations work on macOS, where
/// the launchers are <c>preview.sh</c> and <c>deploy.sh</c>.
/// </summary>
public interface ILauncherRunner
{
    /// <param name="launcher">"preview" or "deploy" — the implementation adds the extension.</param>
    Task<LaunchOutcome> Run(string launcher, IReadOnlyList<string> arguments, string workingFolder,
                            IProgress<string>? progress, CancellationToken cancellation);
}

/// <summary>The result of one launcher run.</summary>
///
/// <remarks>
/// <para><see cref="Findings"/> is what the build said about the course's
/// FOLDERS — the same <c>PLANTOIR_HEALTH:</c> lines the app's own
/// <c>ScriptRunner</c> collects. It is optional so that the two-argument shape
/// every other caller uses keeps working; a runner that does not look for them
/// simply reports none.</para>
/// </remarks>
public readonly record struct LaunchOutcome(
    bool Succeeded,
    string Message,
    IReadOnlyList<Models.SiteHealthFinding>? Findings = null,
    int? ExitCode = null,
    LinksChecklistMarker? LinksChecklist = null)
{
    /// <summary>
    /// deploy.py's NEEDS_AN_ANSWER, which preview.ps1 and deploy.ps1 pass
    /// through under --non-interactive: a question nobody was there to answer
    /// (#391 / mac #378). Means that alone.
    /// </summary>
    public bool NeededAnAnswer => ExitCode == NeedsAnAnswerExitCode;

    public const int NeedsAnAnswerExitCode = 3;
}

/// <summary>The result of planning a whole unit publish/unpublish.</summary>
public sealed record WholeUnitPlanResult(
    bool HasPages,
    int MovingCount,
    string? PlanText,
    string? Summary,
    string? AlreadyDoneSentence,
    string? ErrorMessage);


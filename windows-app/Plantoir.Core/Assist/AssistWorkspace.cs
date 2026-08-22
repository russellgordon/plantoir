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
public sealed class AssistWorkspace
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

    private static string CurrentCloudflareAccountId() =>
        CloudflareAccountIdOverrideForTests?.Invoke() ?? AppSettings.Load().CloudflareAccountId;

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
        string wanted = code.Trim();
        var courses = Courses();
        var found = courses.FirstOrDefault(c => string.Equals(c.Code, wanted, StringComparison.OrdinalIgnoreCase));
        if (found is not null) return found;

        // A locked session says WHY, rather than claiming the course does not
        // exist. "There's no course called MCV4U" would be a lie the assistant
        // would repeat to a teacher looking straight at it in the sidebar.
        if (_lockedCourse is not null)
            throw new AssistRefusal(
                $"This session is working on {_lockedCourse} only, so {wanted} can’t be reached from here. " +
                $"Start again from {wanted} in Plantoir to work on that course.");

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
            .Select(Relative).ToList();

    /// <summary>
    /// The section's CLASS pages — the ones that are days of teaching, in date
    /// order.
    ///
    /// "Class page" is read from the course's own configuration rather than
    /// guessed: it is a page inside one of the course's
    /// <c>per_section_folders</c> (typically "All Classes"), and never an
    /// <c>index.md</c>.
    ///
    /// Both exclusions matter, and the second is the dangerous one. A section's
    /// <c>index.md</c>, its folder indexes and its Key Links page all carry the
    /// SAME date as the first class — so "every class from September 8th"
    /// filtered naively on dates alone would hide the site's own front page.
    /// </summary>
    public List<string> ClassPages(Course course, int sectionNumber)
    {
        var folders = course.Configuration.PerSectionFolders;
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
                WikiLinks.Parse(File.ReadAllText(keyLinks)), course.DirectoryPath, sectionNumber, keyLinks);
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
                             WikiLinks.Parse(File.ReadAllText(keyLinks)), course.DirectoryPath, section, keyLinks))
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

        string bare = wanted.EndsWith(".md", StringComparison.OrdinalIgnoreCase) ? wanted[..^3] : wanted;
        var matches = PagePaths.MarkdownPages(course.DirectoryPath, sectionNumber)
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
    ///   unsatisfiable: <c>includeLinked</c> took it down, and nothing could
    ///   put just that page back. Being able to name any page directly
    ///   dissolves it. That shape — a shared page reachable from several
    ///   classes — is the normal shape of a course, not an edge case.
    /// </summary>
    public PublishPlan PlanPublish(
        string courseCode, int sectionNumber, IReadOnlyList<string> pageTitles,
        bool includeLinked, bool draft = false, bool publishes = true,
        DateOnly? onOrAfter = null, DateOnly? before = null)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);

        if (pageTitles.Count == 0 && onOrAfter is null && before is null)
            throw new AssistRefusal("No page was named, and no dates were given to choose classes by.");
        if (onOrAfter is { } from && before is { } until && until <= from)
            throw new AssistRefusal(
                $"No class can be on or after {from:yyyy-MM-dd} and also before {until:yyyy-MM-dd}.");

        bool isDraft = draft;
        bool isPublish = !draft;

        var problems = new List<string>();
        var protectedPaths = isDraft
            ? ProtectedFromHiding(course, section)
            : new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        // Read all markdown pages in the section
        var allMarkdown = PagePaths.MarkdownPages(course.DirectoryPath, section);
        var pagesList = new List<PlannedPage>();
        var pagesByTitle = new Dictionary<string, PlannedPage>(StringComparer.OrdinalIgnoreCase);

        foreach (string p in allMarkdown)
        {
            var planned = Plan(course, section, p, isDraft, viaLink: false);
            pagesList.Add(planned);
            if (!pagesByTitle.ContainsKey(planned.Title))
                pagesByTitle[planned.Title] = planned;
        }

        // Build link graph and referrers
        var linksFrom = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        var referrers = new Dictionary<string, List<PlannedPage>>(StringComparer.OrdinalIgnoreCase);

        foreach (var page in pagesList)
        {
            string fullPath = PagePaths.ResolveInside(_folder, page.RelativePath);
            string text = File.ReadAllText(fullPath);
            var targets = new List<string>();
            foreach (var resolution in WikiLinks.Resolve(WikiLinks.Parse(text), course.DirectoryPath, section, fullPath))
            {
                if (resolution.Problem is { } prob)
                {
                    if (!problems.Contains(prob)) problems.Add(prob);
                    continue;
                }
                if (resolution.Outcome == LinkOutcome.Resolved && resolution.Path != null)
                {
                    string targetTitle = Path.GetFileNameWithoutExtension(resolution.Path);
                    if (!targets.Contains(targetTitle, StringComparer.OrdinalIgnoreCase))
                        targets.Add(targetTitle);
                }
            }
            linksFrom[page.Title] = targets;
            foreach (var target in targets)
            {
                if (!referrers.TryGetValue(target, out var list))
                {
                    list = new List<PlannedPage>();
                    referrers[target] = list;
                }
                if (!list.Any(r => string.Equals(r.Title, page.Title, StringComparison.OrdinalIgnoreCase)))
                    list.Add(page);
            }
        }

        // Identify named pages
        var named = new List<PlannedPage>();
        var unknownNames = new List<string>();
        var chosen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (string title in pageTitles)
        {
            string wanted = title.Trim();
            if (wanted.Length == 0) continue;

            // Expand unit if title is like "Unit 4"
            if (wanted.StartsWith("Unit ", StringComparison.OrdinalIgnoreCase) &&
                int.TryParse(wanted[5..].Trim(), out int unitNum) && !wanted.Contains(','))
            {
                var unitPages = pagesList.Where(p => p.IsClassPage &&
                    p.Title.StartsWith($"Unit {unitNum},", StringComparison.OrdinalIgnoreCase)).ToList();
                var ordered = isDraft ? unitPages.OrderByDescending(p => p.Title) : unitPages.OrderBy(p => p.Title);
                foreach (var up in ordered)
                {
                    if (chosen.Add(up.Title)) named.Add(up);
                }
                continue;
            }

            string bare = wanted.EndsWith(".md", StringComparison.OrdinalIgnoreCase) ? wanted[..^3] : wanted;
            if (bare.Contains('/') || bare.Contains('\\'))
            {
                string direct = PagePaths.ResolveInside(_folder, bare);
                bare = Path.GetFileNameWithoutExtension(direct);
            }

            if (pagesByTitle.TryGetValue(bare, out var matchedPage))
            {
                string full = Path.GetFullPath(PagePaths.ResolveInside(_folder, matchedPage.RelativePath));
                if (isDraft && protectedPaths.Contains(full))
                {
                    problems.Add($"“{matchedPage.Title}” is never hidden — " +
                                 "it is an index page or something Key Links points at. Left published.");
                    continue;
                }
                if (chosen.Add(matchedPage.Title)) named.Add(matchedPage);
            }
            else
            {
                var dispMatch = pagesList.FirstOrDefault(p => string.Equals(p.DisplayTitle, bare, StringComparison.OrdinalIgnoreCase));
                if (dispMatch != null)
                {
                    string full = Path.GetFullPath(PagePaths.ResolveInside(_folder, dispMatch.RelativePath));
                    if (isDraft && protectedPaths.Contains(full))
                    {
                        problems.Add($"“{dispMatch.Title}” is never hidden — " +
                                     "it is an index page or something Key Links points at. Left published.");
                        continue;
                    }
                    if (chosen.Add(dispMatch.Title)) named.Add(dispMatch);
                }
                else
                {
                    unknownNames.Add(wanted);
                }
            }
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
                if (chosen.Add(page.Title)) named.Add(page);
            }
            if (dateMatched == 0 && named.Count == 0)
                problems.Add($"No class in {course.Code} Section {section} falls in that date range.");
        }

        var mustStay = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Key Links" };
        if (pagesByTitle.TryGetValue("Key Links", out var klPage) && linksFrom.TryGetValue(klPage.Title, out var klTargets))
        {
            foreach (var t in klTargets) mustStay.Add(t);
        }

        var linked = new List<PlannedPage>();
        var kept = new List<PlannedKept>();
        int protectedLinked = 0;
        int stillNeeded = 0;

        if (isDraft) // unpublishing
        {
            var goingDown = new HashSet<string>(named.Select(p => p.Title), StringComparer.OrdinalIgnoreCase);
            bool foundMore = true;
            while (foundMore)
            {
                foundMore = false;
                var candidates = new List<PlannedPage>();
                foreach (var title in goingDown)
                {
                    if (linksFrom.TryGetValue(title, out var targets))
                    {
                        foreach (var target in targets)
                        {
                            if (pagesByTitle.TryGetValue(target, out var targetPage))
                                candidates.Add(targetPage);
                        }
                    }
                }

                foreach (var candidate in candidates)
                {
                    if (goingDown.Contains(candidate.Title)) continue;
                    string? reason = ReasonToKeep(candidate, mustStay, referrers, goingDown, course);
                    if (reason != null) continue;
                    goingDown.Add(candidate.Title);
                    linked.Add(candidate with { ViaLink = true });
                    foundMore = true;
                }
            }

            var keptSeen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var sweepCandidates = new List<PlannedPage>();
            foreach (var title in goingDown)
            {
                if (linksFrom.TryGetValue(title, out var targets))
                {
                    foreach (var target in targets)
                    {
                        if (pagesByTitle.TryGetValue(target, out var targetPage))
                            sweepCandidates.Add(targetPage);
                    }
                }
            }

            foreach (var candidate in sweepCandidates)
            {
                if (!candidate.IsVisibleToStudents) continue;
                string? reason = ReasonToKeep(candidate, mustStay, referrers, goingDown, course);
                if (reason != null && keptSeen.Add(candidate.Title))
                {
                    kept.Add(new PlannedKept(candidate, reason));
                    if (reason.Contains("still links to it"))
                        stillNeeded++;
                    else
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
        else // publishing
        {
            if (includeLinked)
            {
                var seenLinked = new HashSet<string>(named.Select(p => p.Title), StringComparer.OrdinalIgnoreCase);
                var queue = new Queue<PlannedPage>(named);
                while (queue.Count > 0)
                {
                    var cur = queue.Dequeue();
                    if (linksFrom.TryGetValue(cur.Title, out var targets))
                    {
                        foreach (var target in targets)
                        {
                            if (pagesByTitle.TryGetValue(target, out var targetPage))
                            {
                                if (seenLinked.Add(targetPage.Title))
                                {
                                    if (!targetPage.IsClassPage)
                                    {
                                        linked.Add(targetPage with { ViaLink = true });
                                        queue.Enqueue(targetPage);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        var changes = new List<PlannedChange>();
        var alreadyRight = new List<PlannedPage>();

        foreach (var page in named)
        {
            if (page.IsVisibleToStudents == isPublish)
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
            if (page.IsVisibleToStudents == isPublish)
            {
                if (!named.Any(n => string.Equals(n.Title, page.Title, StringComparison.OrdinalIgnoreCase)))
                    alreadyRight.Add(page);
            }
            else
            {
                changes.Add(new PlannedChange(page, page.FrontmatterKey, WasVisible: page.IsVisibleToStudents, WillBeVisible: isPublish, BecauseLinked: true));
            }
        }

        var allPlannedPages = named.Concat(linked).ToList();
        var inherited = InheritedDates(course, section, allPlannedPages, isDraft);

        var dateMoves = new List<PlannedDateMove>();
        foreach (var date in inherited)
        {
            if (pagesByTitle.TryGetValue(date.Title, out var p))
            {
                string introducingTitle = p.DisplayTitle;
                // Find introducing class title
                if (referrers.TryGetValue(p.Title, out var refs))
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
        };
    }


    private static string? ReasonToKeep(
        PlannedPage page,
        HashSet<string> mustStay,
        Dictionary<string, List<PlannedPage>> referrers,
        HashSet<string> goingDown,
        Course course)
    {
        if (page.IsFolderIndex)
            return "it is a folder's landing page, which following links never takes down.";
        if (mustStay.Contains(page.Title))
            return "it is in this section's Key Links.";
        if (PagePaths.IsCurriculum(course.DirectoryPath, page.RelativePath))
            return "it is a curriculum page.";
        if (PageStillLinking(page, referrers, goingDown) is { } referrer)
            return $"“{referrer.DisplayTitle}” still links to it.";
        return null;
    }

    private static PlannedPage? PageStillLinking(
        PlannedPage page,
        Dictionary<string, List<PlannedPage>> referrers,
        HashSet<string> goingDown)
    {
        if (referrers.TryGetValue(page.Title, out var list))
        {
            foreach (var referrer in list)
            {
                if (goingDown.Contains(referrer.Title)) continue;
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
                     WikiLinks.Parse(text), course.DirectoryPath, section, page))
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

            // If already visible to students, leave it alone
            bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, target);
            string key = PageFrontmatter.PublishKeyFor(section, sectionLocal);
            try
            {
                bool isDraft = PageFrontmatter.StoredDraft(File.ReadAllText(target), key) ?? false;
                if (!isDraft) continue; // visible to students
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

        string toClass = Path.GetFileNameWithoutExtension(newest);
        DateOnly toDate = DateOf(course, section, newest) ?? default;
        bool headingMissing = SectionIndex.WithMostRecent(indexText, toClass) is null;

        return new IndexChange(
            RelativePath: Relative(indexPath),
            FromClass: SectionIndex.CurrentlyShowing(indexText),
            ToClass: toClass,
            FromDate: PageFrontmatter.CreatedOn(indexText, section, isSectionLocal: true),
            ToDate: toDate,
            HeadingMissing: headingMissing);
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
            bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, full);
            try
            {
                // "Hidden" is the question here, and the file answers the
                // opposite one, so it has to be read in draft terms.
                string key = PageFrontmatter.PublishKeyFor(section, sectionLocal);
                return PageFrontmatter.StoredDraft(File.ReadAllText(full), key) ?? false;
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
            bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, path);
            try
            {
                // "Hidden" is the question here, and the file answers the
                // opposite one, so it has to be read in draft terms.
                string key = PageFrontmatter.PublishKeyFor(section, sectionLocal);
                return PageFrontmatter.StoredDraft(File.ReadAllText(path), key) ?? false;
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
        bool isClassPage = !isFolderIndex && (pagePath.Contains("All Classes", StringComparison.OrdinalIgnoreCase) ||
                           Path.GetDirectoryName(pagePath)?.Contains("class", StringComparison.OrdinalIgnoreCase) == true);
        return new PlannedPage(
            Title: Path.GetFileNameWithoutExtension(pagePath),
            RelativePath: Relative(pagePath),
            FrontmatterKey: key,
            CurrentValue: PageFrontmatter.StoredDraft(text, key),
            Draft: draft,
            ViaLink: viaLink,
            Date: PageFrontmatter.CreatedOn(text, section, sectionLocal),
            DisplayTitle: PagePaths.DisplayTitle(pagePath, text),
            IsFolderIndex: isFolderIndex,
            IsClassPage: isClassPage,
            IsSectionLocal: sectionLocal);
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
                $"{course.Code} Section {sectionNumber} has {matches.Count} classes on {date:yyyy-MM-dd} — " +
                Humanize(matches.Select(m => "“" + Path.GetFileNameWithoutExtension(m) + "”")) +
                ". Say which one you mean.");

        var dated = ClassPages(course, sectionNumber)
            .Select(p => DateOf(course, sectionNumber, p))
            .Where(d => d is not null).Select(d => d!.Value).OrderBy(d => d).ToList();
        string nearby = dated.Count == 0
            ? "None of its classes have dates."
            : $"Its classes run {dated[0]:yyyy-MM-dd} to {dated[^1]:yyyy-MM-dd}.";
        throw new AssistRefusal(
            $"{course.Code} Section {sectionNumber} has no class on {date:yyyy-MM-dd}. {nearby}");
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
        int section = Section(course, sectionNumber);
        RefuseIfPlantoirIsBuilding(course);

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
                ? $"{course.Code} Section {section} has never been deployed, so deploying it asks what to call " +
                  "the website — and that can only be answered in Plantoir. Deploy it once from there, and I can " +
                  "do it after that."
                : $"{course.Code} Section {section} has never been deployed to {destinationName}, so deploying " +
                  "it there asks what to call that site — and that can only be answered in Plantoir. Deploy it " +
                  "there once from Plantoir, and I can do it after that.");
        }

        progress?.Report($"Building Section {section} of {course.Code}…");
        using var claim = ClaimTheBuild(course);
        var build = await _launcher.Run("preview", new[] { course.Code, section.ToString(), "--build-only" },
                                        _folder, progress, cancellation);
        if (!build.Succeeded)
            return new AssistResult(false, $"The build failed, so nothing was deployed. {build.Message}", null);

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
        foreach (var destination in destinations)
        {
            var arguments = Models.DeployCommand.Arguments(course.Code, section, destination);
            progress?.Report($"Deploying to {Models.DeployCommand.DestinationDescription(destination)}…");
            var deployed = await _launcher.Run("deploy", arguments, _folder, progress, cancellation);
            outcomeLegs.Add((destination, deployed.Succeeded));
        }

        bool anySucceeded = outcomeLegs.Any(leg => leg.Succeeded);
        var failedDestinations = outcomeLegs.Where(leg => !leg.Succeeded).Select(leg => leg.Destination).ToList();
        var outcome = new MultiDestinationDeployRunner.Outcome(anySucceeded, failedDestinations);
        return MultiDestinationDeployRunner.Result(course.Code, section.ToString(), destinations.Count, outcome);
    }

    public async Task<AssistResult> RebuildPreview(string courseCode, int sectionNumber,
                                                   IProgress<string>? progress = null,
                                                   CancellationToken cancellation = default)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);
        RefuseIfPlantoirIsBuilding(course);

        progress?.Report($"Building a preview of Section {section} of {course.Code}…");
        using var claim = ClaimTheBuild(course);
        var build = await _launcher.Run("preview", new[] { course.Code, section.ToString(), "--build-only" },
                                        _folder, progress, cancellation);
        return build.Succeeded
            ? new AssistResult(true,
                $"Rebuilt the preview of {course.Code} Section {section}. No content was changed. " +
                "Look it over in Plantoir, and deploy it there when you're happy.", null)
            : new AssistResult(false, $"Nothing was changed, and the preview couldn’t be built. {build.Message}", null);
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

        if (plan.ChangesNothing && !plan.Publishes)
            return new AssistResult(true, "Nothing needed changing.", null);

        // Anything that would stop the build has to be found NOW, before the
        // backup and the edits. Failing at the last step would leave the
        // teacher with changed files and a refusal — the worst of the orders.
        if (plan.Publishes) RefuseIfPlantoirIsBuilding(course);

        string backup;
        try { backup = CourseArchiver.BackUpCourse(course, Workspace.CoursesDirectory(_folder), new BackupMaker.Assistant(plan.SectionNumber)); }
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
        _undo?.Begin($"{(plan.Hiding ? "unpublished" : "published")} " +
                     $"{Humanize(plan.Named.Select(p => "“" + p.Title + "”"))} " +
                     $"in {course.Code} Section {section}");

        var changed = new List<string>();
        foreach (var page in plan.Changing)
        {
            // Named as it happens, so a teacher watching the conversation
            // sees the work go by page by page rather than a silence with
            // a count at the end.
            progress?.Report($"Editing “{page.Title}”…");
            string full = PagePaths.ResolveInside(_folder, page.RelativePath);
            string text = File.ReadAllText(full);
            var (updated, edit) = PageFrontmatter.SetDraft(text, page.FrontmatterKey, page.Draft);
            if (!edit.Changed) continue;
            Save(full, updated);
            changed.Add(page.Title);
        }
        if (changed.Count > 0)
            progress?.Report($"Changed {changed.Count} page{(changed.Count == 1 ? "" : "s")}.");

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

        _undo?.End();

        if (!plan.Publishes)
            return new AssistResult(true, Summary(changed, previewed: false, course.Code, section, plan.Hiding), backup);

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
            return new AssistResult(true, Summary(changed, previewed: false, course.Code, section, plan.Hiding), backup);

        RefuseIfPlantoirIsBuilding(course);
        progress?.Report($"Building a preview of Section {section} of {course.Code}…");
        using var claim = ClaimTheBuild(course);
        var build = await _launcher.Run("preview", new[] { course.Code, section.ToString(), "--build-only" },
                                        _folder, progress, cancellation);
        if (!build.Succeeded)
            return new AssistResult(false,
                $"{WhatSurvived(changed)}, but the preview couldn’t be built. {AssistWording.WhereTheOutputIs}", backup);

        return new AssistResult(true, Summary(changed, previewed: true, course.Code, section, plan.Hiding), backup);
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
            if (planned.IsClassPage && UnitDay.Parse(planned.Title) is { } ud && ud.Unit == unit)
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
                ErrorMessage: $"I can’t find any class pages in Unit {unit} of {course.Code} Section {section}.");
        }

        // Only the ones that would actually move, ordered highest day first (matching Swift)
        unitPages = unitPages.OrderByDescending(p => UnitDay.Parse(p.Title)?.Day ?? 0).ToList();

        var moving = new List<string>();
        foreach (var p in unitPages)
        {
            if (p.IsVisibleToStudents != publishing)
            {
                moving.Add(p.DisplayTitle);
            }
        }

        if (moving.Count == 0)
        {
            string already = publishing
                ? $"Unit {unit} has already been published."
                : $"Unit {unit} is already hidden.";
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
        lines.Add($"{course.Code} Section {section}: {(publishing ? "publishing" : "unpublishing")} Unit {unit}.");
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

        string summary = $"Worked out what {(publishing ? "publishing" : "unpublishing")} Unit {unit} would do.";
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
            if (planned.IsClassPage && UnitDay.Parse(planned.Title) is { Unit: var u } && u == unit)
            {
                unitPages.Add(planned);
            }
        }

        if (unitPages.Count == 0)
            return new AssistResult(false, $"I can’t find any class pages in Unit {unit} of {course.Code} Section {section}.", null);

        // Highest day first to take a unit down; Day 1 first to put it up.
        unitPages = publishing
            ? unitPages.OrderBy(p => UnitDay.Parse(p.Title)?.Day ?? 0).ToList()
            : unitPages.OrderByDescending(p => UnitDay.Parse(p.Title)?.Day ?? 0).ToList();

        if (publishing) RefuseIfPlantoirIsBuilding(course);

        string backup;
        try { backup = CourseArchiver.BackUpCourse(course, Workspace.CoursesDirectory(_folder), new BackupMaker.Assistant(section)); }
        catch (Exception error)
        {
            throw new AssistRefusal($"{course.Code} couldn’t be backed up, so nothing was changed: {error.Message}");
        }

        string verb = publishing ? "published" : "unpublished";
        _undo?.Begin($"{verb} Unit {unit} in {course.Code} Section {section}");

        bool changedAnything = false;
        var changed = new List<string>();

        foreach (var page in unitPages)
        {
            var pagePlan = PlanPublish(
                course.Code, section, new[] { page.Title }, includeLinked: true, draft: !publishing, publishes: publishing);

            if (pagePlan.ChangesNothing) continue;

            foreach (var change in pagePlan.Changing)
            {
                progress?.Report($"Editing “{change.Title}”…");
                string full = PagePaths.ResolveInside(_folder, change.RelativePath);
                string text = File.ReadAllText(full);
                var (updated, edit) = PageFrontmatter.SetDraft(text, change.FrontmatterKey, change.Draft);
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

        _undo?.End();

        if (!changedAnything)
        {
            string already = publishing
                ? $"Unit {unit} has already been published."
                : $"Unit {unit} is already hidden.";
            return new AssistResult(true, already, backup);
        }

        string summary = $"Unit {unit} was {verb}.";

        if (!preview)
            return new AssistResult(true, summary, backup);

        RefuseIfPlantoirIsBuilding(course);
        progress?.Report($"Building a preview of Section {section} of {course.Code}…");
        using var claim = ClaimTheBuild(course);
        var build = await _launcher.Run("preview", new[] { course.Code, section.ToString(), "--build-only" },
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
            if (SectionIndex.WithMostRecent(text, index.ToClass) is not { } withEmbed) return;
            var (withDate, _) = PageFrontmatter.SetCreated(withEmbed, "created", index.ToDate, tail);
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

    private static string Summary(IReadOnlyList<string> changed, bool previewed, string code, int section, bool hiding = false)
    {
        if (changed.Count == 0) return "Nothing needed changing.";
        string verb = hiding ? "Unpublished" : "Published";
        string what = changed.Count == 1
            ? $"{verb} “{changed[0]}”."
            : $"{verb} {changed.Count} pages ({string.Join(", ", changed)}).";
        return previewed
            ? $"{what.TrimEnd('.')} and rebuilt the preview of {code} Section {section}."
            : what;
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
    /// Claim the build for as long as it runs, so Plantoir's own Preview and
    /// Deploy stand off rather than clearing the folder underneath it.
    /// </summary>
    private IDisposable ClaimTheBuild(Course course) =>
        WorkLease.Take(_folder, course.Code, WorkLease.Building);



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
        var problems = DateAudit.Run(classPages, graph, Resolve, Relative);

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
    /// has no other way back to it.
    /// </summary>
    public string? ReleaseSite(Course course, int sectionNumber)
    {
        foreach (string folder in new[] { ".netlify_sites", ".cloudflare_sites" })
        {
            string marker = Path.Combine(course.DirectoryPath, folder, $"section{sectionNumber}.json");
            if (!File.Exists(marker)) continue;
            string kept = Path.Combine(course.DirectoryPath, folder,
                $"section{sectionNumber}.previous-{DateTime.Now:yyyy-MM-dd_HHmmss}.json");
            // Recorded as a move so an undo puts the section back on last
            // year's site rather than leaving it orphaned.
            try
            {
                string? contents = File.ReadAllText(marker);
                _undo?.Begin($"cut section {sectionNumber} loose from its website");
                _undo?.Touch(marker, contents);
                _undo?.Touch(kept, null);
                File.Move(marker, kept);
                _undo?.Wrote(marker, null);
                _undo?.Wrote(kept, contents);
                _undo?.End();
                return Relative(kept);
            }
            catch { return null; }
        }
        return null;
    }

    /// <summary>Carry out a re-date the teacher has agreed to, after backing the course up.</summary>
    public AssistResult ApplyReDate(ReDatePlan plan, IProgress<string>? progress = null)
    {
        var course = Course(plan.CourseCode);
        int section = Section(course, plan.SectionNumber);
        if (plan.ChangesNothing) return new AssistResult(true, "Every class already carries that date.", null);

        string backup;
        try { backup = CourseArchiver.BackUpCourse(course, Workspace.CoursesDirectory(_folder), new BackupMaker.Assistant(plan.SectionNumber)); }
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

        _undo?.Begin($"re-dated {course.Code} Section {section} onto block {plan.Block}");
        string tail = SiblingTimeAndOffset(course, section, ClassPages(course, section));
        var classPaths = new HashSet<string>(
            plan.Dates.Select(d => d.RelativePath), StringComparer.OrdinalIgnoreCase);
        int classes = 0, materials = 0;

        foreach (var date in plan.Changing)
        {
            string full = PagePaths.ResolveInside(_folder, date.RelativePath);
            string fileText = File.ReadAllText(full);
            var (updated, changed) = PageFrontmatter.SetCreated(
                fileText, date.FrontmatterKey, date.New, tail);
            if (date.Unpublishes)
            {
                bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, full);
                string pubKey = PageFrontmatter.PublishKeyFor(section, sectionLocal);
                var (draftUpdated, draftEdit) = PageFrontmatter.SetDraft(
                    updated, pubKey, draft: true);
                updated = draftUpdated;
                if (draftEdit.Changed) changed = true;
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
                    string targetName = Path.GetFileNameWithoutExtension(newestPublished);
                    if (SectionIndex.WithMostRecent(indexText, targetName) is { } newIndexText && newIndexText != indexText)
                    {
                        Save(indexPath, newIndexText);
                    }
                }
            }
            catch { }
        }

        _undo?.End();

        // Counted apart, because "moved 91 classes" when 26 classes and 65
        // materials moved is a sentence a teacher would rightly query.
        int moved = plan.Moves.Count > 0 ? plan.Moves.Count : plan.Changing.Count();
        int classCount = plan.ClassCount > 0 ? plan.ClassCount : plan.Dates.Count;
        int materialsMoved = moved - classCount;
        string summary = $"Re-dated {classCount} {(classCount == 1 ? "class" : "classes")}" +
                         $" and {materialsMoved} {(materialsMoved == 1 ? "page" : "pages")} they use.";
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
        try { backup = CourseArchiver.BackUpCourse(course, Workspace.CoursesDirectory(_folder), new BackupMaker.Assistant(plan.SectionNumber)); }
        catch (Exception error)
        {
            throw new AssistRefusal(
                $"{course.Code} couldn’t be backed up, so no dates were changed: {error.Message}");
        }

        _undo?.Begin($"brought {Humanize(plan.Anchors)}’ pages into date in " +
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
        _undo?.End();

        return new AssistResult(true,
            $"Brought {moved} page{(moved == 1 ? "" : "s")} into date with the class that uses " +
            (moved == 1 ? "it" : "them") + $" in {course.Code} Section {section}. Nothing was deployed.",
            backup);
    }

    /// <summary>A whole-course backup, on its own.</summary>
    public string BackUp(string courseCode)
    {
        var course = Course(courseCode);
        return Relative(CourseArchiver.BackUpCourse(course, Workspace.CoursesDirectory(_folder)));
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

        var unpublished = new List<string>();
        foreach (string title in classesToCheck ?? Array.Empty<string>())
        {
            try
            {
                string path = Page(course, section, title);
                if (PageFrontmatter.IsDraft(File.ReadAllText(path), section))
                    unpublished.Add(Path.GetFileNameWithoutExtension(path));
            }
            // A page that cannot be found is reported by the caller's own
            // lookup; it is not this check's job to refuse over it.
            catch (AssistRefusal) { }
        }

        return new ScheduledDeploy
        {
            CourseCode = course.Code,
            SectionNumber = section,
            When = when,
            UnpublishedClasses = unpublished,
            Destination = DestinationOf(course),
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
        try { backup = CourseArchiver.BackUpCourse(course, Workspace.CoursesDirectory(_folder), new BackupMaker.Assistant(plan.SectionNumber)); }
        catch (Exception error)
        {
            throw new AssistRefusal($"{course.Code} couldn’t be backed up, so the page was not changed: {error.Message}");
        }

        _undo?.Begin($"added {plan.Adding.Count} curriculum expectations to “{plan.PageTitle}”");

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
            var match = System.Text.RegularExpressions.Regex.Match(
                title, @"^Unit\s+(\d+),\s*Day\s+(\d+)$",
                System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            if (!match.Success) { unnumbered++; continue; }

            found.Add(new ClassRef(
                int.Parse(match.Groups[1].Value), int.Parse(match.Groups[2].Value),
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

        if (unit < 1 || atDay < 1) throw new AssistRefusal("Unit and day numbers start at 1.");
        if (count < 1) throw new AssistRefusal("Ask for at least one class.");

        var remembered = TimetableMemory.Read(_folder, course.Code, section)
            ?? throw new AssistRefusal(
                $"I don't know when {course.Code} Section {section} meets, so I can't move classes onto real " +
                "days. Ask the teacher for their class dates, then record them with remember_timetable.");

        var classes = NumberedClasses(course, section, out int unnumbered);
        if (classes.Count == 0)
            throw new AssistRefusal(
                $"{course.Code} Section {section} has no pages named “Unit N, Day N”, so there is nothing " +
                "to make room in.");

        var problems = new List<string>();
        if (unnumbered > 0)
            problems.Add($"{unnumbered} class page{(unnumbered == 1 ? " is" : "s are")} not named " +
                         "“Unit N, Day N”, so I left it where it is — including its date.");

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
            problems.Add($"This needs {needed} class days from {firstFree:yyyy-MM-dd} onwards and the " +
                         $"timetable only has {runway.Count}. Add {short_} more class " +
                         $"date{(short_ == 1 ? "" : "s")} and ask again.");
            return new InsertPlan
            {
                CourseCode = course.Code, SectionNumber = section, Unit = unit, AtDay = atDay,
                Added = Array.Empty<NewClass>(), Renames = Array.Empty<Rename>(),
                Moves = Array.Empty<DateMove>(), LinksToRewrite = 0, Problems = problems,
            };
        }

        string folder = ClassFolder(course, section);
        var added = new List<NewClass>();
        for (int i = 0; i < count; i++)
        {
            string title = $"Unit {unit}, Day {atDay + i}";
            added.Add(new NewClass(title, Relative(Path.Combine(folder, title + ".md")),
                                   runway[i], atDay + i));
        }

        // Renames: only within the unit being changed. A later unit's Day 1 is
        // still its Day 1 — it simply happens later in the year.
        var renames = new List<Rename>();
        foreach (var moving in shifted.Where(c => c.Unit == unit).OrderByDescending(c => c.Day))
        {
            string to = $"Unit {unit}, Day {moving.Day + count}";
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

            string name = moving.Unit == unit ? $"Unit {unit}, Day {moving.Day + count}" : moving.Title;
            moves.Add(new DateMove(name, Relative(moving.Path), moving.Date ?? to, to));
        }

        return new InsertPlan
        {
            CourseCode = course.Code,
            SectionNumber = section,
            Unit = unit,
            AtDay = atDay,
            Added = added,
            Renames = renames,
            Moves = moves,
            LinksToRewrite = CountLinksTo(course, section, renames.Select(r => r.From)),
            Problems = problems,
        };
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

            foreach (var match in System.Text.RegularExpressions.Regex
                         .Matches(text, @"!?\[\[([^\]|#]+)").Cast<System.Text.RegularExpressions.Match>())
                if (names.Contains(match.Groups[1].Value.Trim())) total++;
        }
        return total;
    }

    /// <summary>Carry out the insertion: rename, re-date, relink, then create the blanks.</summary>
    public AssistResult ApplyInsertClasses(InsertPlan plan, IProgress<string>? progress = null)
    {
        var course = Course(plan.CourseCode);
        int section = Section(course, plan.SectionNumber);
        if (plan.ChangesNothing)
            return new AssistResult(true, "Nothing needed moving.", null);
        if (plan.Added.Count == 0)
            throw new AssistRefusal(string.Join(" ", plan.Problems));

        RefuseIfPlantoirIsBuilding(course);

        string backup;
        try { backup = CourseArchiver.BackUpCourse(course, Workspace.CoursesDirectory(_folder), new BackupMaker.Assistant(plan.SectionNumber)); }
        catch (Exception error)
        {
            throw new AssistRefusal(
                $"{course.Code} couldn’t be backed up, so nothing was moved: {error.Message}");
        }

        _undo?.Begin($"made room for {plan.Added.Count} classes at Unit {plan.Unit}, Day {plan.AtDay} " +
                     $"in {course.Code} Section {section}");

        // Highest day first, so a rename never lands on a name still in use.
        progress?.Report("Renaming the classes that come after…");
        foreach (var rename in plan.Renames)
        {
            try
            {
                if (!File.Exists(rename.FromPath) || File.Exists(rename.ToPath)) continue;
                string text = File.ReadAllText(rename.FromPath);
                Save(rename.ToPath, PageFrontmatter.SetTitle(text, rename.To));
                _undo?.Touch(rename.FromPath, text);
                File.Delete(rename.FromPath);
                _undo?.Wrote(rename.FromPath, null);
            }
            catch { }
        }

        progress?.Report("Following the links that pointed at them…");
        RewriteLinks(course, section, plan.Renames);

        progress?.Report("Moving the dates…");
        string tail = SiblingTimeAndOffset(course, section, ClassPages(course, section));
        foreach (var move in plan.Moves)
        {
            try
            {
                // Renamed pages are found under their NEW name by now.
                string full = Path.Combine(ClassFolder(course, section), move.Title + ".md");
                if (!File.Exists(full)) full = PagePaths.ResolveInside(_folder, move.RelativePath);
                if (!File.Exists(full)) continue;

                bool sectionLocal = PagePaths.IsSectionLocal(course.DirectoryPath, full);
                string key = sectionLocal ? "created" : "createdSection" + section;
                var (updated, changed) = PageFrontmatter.SetCreated(
                    File.ReadAllText(full), key, move.To, tail);
                if (changed) Save(full, updated);
            }
            catch { }
        }

        progress?.Report("Adding the new classes…");
        Directory.CreateDirectory(ClassFolder(course, section));
        foreach (var added in plan.Added)
        {
            string path = Path.Combine(ClassFolder(course, section), added.Title + ".md");
            if (File.Exists(path)) continue;
            Save(path, ClassSkeleton(added, plan.Unit, plan.Added.Count, tail));
        }

        return new AssistResult(true,
            $"Made room for {plan.Added.Count} class{(plan.Added.Count == 1 ? "" : "es")} at Unit " +
            $"{plan.Unit}, Day {plan.AtDay}. Renamed {plan.Renames.Count}, moved {plan.Moves.Count} onto " +
            $"later class days, and updated {plan.LinksToRewrite} link" +
            $"{(plan.LinksToRewrite == 1 ? "" : "s")}. The new pages are unpublished until you write them. " +
            "Look the section over in Plantoir before you deploy it.",
            backup);
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
    private void RewriteLinks(Course course, int section, IReadOnlyList<Rename> renames)
    {
        if (renames.Count == 0) return;
        var byName = renames.ToDictionary(r => r.From, r => r.To, StringComparer.OrdinalIgnoreCase);

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
            // teacher's own words and stays exactly as written.
            string updated = System.Text.RegularExpressions.Regex.Replace(
                text, @"(!?\[\[)([^\]|#]+)", match =>
                {
                    string target = match.Groups[2].Value;
                    return byName.TryGetValue(target.Trim(), out string? renamed)
                        ? match.Groups[1].Value + renamed
                        : match.Value;
                });

            if (updated != text) Save(full, updated);
        }
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
    public NewClassesPlan PlanAddClasses(string courseCode, int sectionNumber, int unit,
                                         int firstDay, int count)
    {
        var course = Course(courseCode);
        int section = Section(course, sectionNumber);

        if (unit < 1) throw new AssistRefusal("A unit number starts at 1.");
        if (firstDay < 1) throw new AssistRefusal("A day number starts at 1.");
        if (count < 1) throw new AssistRefusal("Ask for at least one class.");

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

        var classes = new List<NewClass>();
        var alreadyThere = new List<string>();
        var problems = new List<string>();
        int sharingCount = 0;

        for (int i = 0; i < count; i++)
        {
            int day = firstDay + i;
            string title = $"Unit {unit}, Day {day}";
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

        var remembered = TimetableMemory.Read(_folder, course.Code, section)
            ?? throw new AssistRefusal(
                $"I don’t know when {course.Code} Section {section} meets, so I can’t date a new class. {AssistWording.MayIAskForYourDates}");

        if (remembered.Dates.Count == 0)
            throw new AssistRefusal(
                $"I don’t know when {course.Code} Section {section} meets, so I can’t date a new class. {AssistWording.MayIAskForYourDates}");

        var existing = ClassPages(course, section);
        var existingTitles = existing.Select(p => Path.GetFileNameWithoutExtension(p) ?? "").ToList();

        if (days is { } howMany && howMany > 0 && int.TryParse(unitAsked, out int specificUnit))
        {
            int highestDay = 0;
            foreach (var t in existingTitles)
            {
                if (UnitDay.Parse(t) is { } ud && ud.Unit == specificUnit && ud.Day > highestDay)
                    highestDay = ud.Day;
            }
            return PlanAddClasses(courseCode, sectionNumber, specificUnit, highestDay + 1, howMany);
        }

        bool startingANewUnit = string.Equals(unitAsked, "next", StringComparison.OrdinalIgnoreCase);
        UnitDay next = startingANewUnit
            ? NextClassPlanner.FirstDayOfANewUnit(existingTitles)
            : NextClassPlanner.NextUnitAndDay(existingTitles);

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
        try { backup = CourseArchiver.BackUpCourse(course, Workspace.CoursesDirectory(_folder), new BackupMaker.Assistant(plan.SectionNumber)); }
        catch (Exception error)
        {
            throw new AssistRefusal(
                $"{course.Code} couldn’t be backed up, so no pages were created: {error.Message}");
        }

        _undo?.Begin($"added {plan.Classes.Count} class pages to Unit {plan.Unit} of " +
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
            Save(path, ClassSkeleton(created, plan.Unit, plan.Classes.Count, tail));
        }

        return new AssistResult(true,
            $"Created {plan.Classes.Count} class page{(plan.Classes.Count == 1 ? "" : "s")} in Unit " +
            $"{plan.Unit} of {course.Code} Section {section}, dated " +
            $"{plan.Classes[0].Date:yyyy-MM-dd} to {plan.Classes[^1].Date:yyyy-MM-dd}. " +
            "They are unpublished, so nothing changed in the site — write them, then publish when ready.",
            backup);
    }

    /// <summary>Where a section's class pages live.</summary>
    private static string ClassFolder(Course course, int sectionNumber)
    {
        var folders = course.Configuration.PerSectionFolders;
        // "All Classes" by convention, but a course names its own folders and
        // the first per-section folder is where classes go.
        string name = folders.FirstOrDefault(f => f.Contains("Class", StringComparison.OrdinalIgnoreCase))
                      ?? folders.FirstOrDefault()
                      ?? "All Classes";
        return Path.Combine(course.SectionDirectory(sectionNumber), name);
    }

    /// <summary>
    /// An empty class page in the shape every other class page takes.
    ///
    /// The teacher's own template, down to the frontmatter keys — with one
    /// deliberate difference. It starts <c>publish: false</c>: a page nobody
    /// has written yet has no business appearing in the site, and the teacher
    /// asked for exactly that.
    /// </summary>
    private static string ClassSkeleton(NewClass created, int unit, int howMany, string tail)
    {
        string plural = howMany == 1 ? "This page was" : $"{howMany} of these were";
        return $"""
            ---
            title: {created.Title}
            publish: false
            created: {created.Date:yyyy-MM-dd}{tail}
            transcludeTitleSize: h2
            enableToc: false
            excludeBacklinks: true
            tags:
              - unit-{unit}
            ---

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
public readonly record struct LaunchOutcome(bool Succeeded, string Message);

/// <summary>The result of planning a whole unit publish/unpublish.</summary>
public sealed record WholeUnitPlanResult(
    bool HasPages,
    int MovingCount,
    string? PlanText,
    string? Summary,
    string? AlreadyDoneSentence,
    string? ErrorMessage);


using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// Every page of one section and what links to what, built once.
///
/// This exists to answer the question a teacher actually asks — *what will
/// students be able to see?* — which link-following alone cannot. Two things
/// go wrong with a rule that just follows links from class pages:
///
/// * **Depth.** A class links to a Concept; the Concept links to the
///   curriculum expectations behind it. Publishing one hop leaves the second
///   hop hidden, so a published page points at a page that is not there.
///   Measured on the sample course: 65 pages one hop from a class, **42 more
///   at two or three hops**.
/// * **Orphans.** Quartz publishes every page that is not a draft and lists it
///   in the explorer, whether anything links to it or not. **50 course-level
///   pages in the sample course are reachable from no class at all** — a whole
///   unit written ahead. No link rule will ever find them.
///
/// So rather than silently following links further (which is safe when
/// publishing and dangerous when hiding — each extra hop can swallow a page
/// some still-published class depends on), the graph is used to CHECK the
/// state a change would produce, and to report what is unreachable. The
/// teacher decides; the tool does the arithmetic.
/// </summary>
public sealed class LinkGraph
{
    private readonly Dictionary<string, List<string>> _targets;   // page -> pages it links to
    private readonly Dictionary<string, List<string>> _sources;   // page -> pages that link to it

    public IReadOnlyList<string> Pages { get; }

    private LinkGraph(IReadOnlyList<string> pages,
                      Dictionary<string, List<string>> targets,
                      Dictionary<string, List<string>> sources)
    {
        Pages = pages;
        _targets = targets;
        _sources = sources;
    }

    public static LinkGraph Build(string courseDirectory, int sectionNumber)
    {
        var byName = WikiLinks.IndexPages(courseDirectory, sectionNumber);
        var pages = PagePaths.MarkdownPages(courseDirectory, sectionNumber)
            .Select(Path.GetFullPath).ToList();

        var targets = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        var sources = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (string page in pages)
        {
            targets[page] = new List<string>();
            sources[page] = new List<string>();
        }

        foreach (string page in pages)
        {
            string text;
            try { text = File.ReadAllText(page); } catch { continue; }
            foreach (var resolution in WikiLinks.Resolve(WikiLinks.Parse(text), byName, courseDirectory, page))
            {
                if (resolution.Outcome != LinkOutcome.Resolved) continue;
                string target = Path.GetFullPath(resolution.Path!);
                if (!targets.ContainsKey(target)) continue;
                if (!targets[page].Contains(target)) targets[page].Add(target);
                if (!sources[target].Contains(page)) sources[target].Add(page);
            }
        }
        return new LinkGraph(pages, targets, sources);
    }

    public IReadOnlyList<string> TargetsOf(string page) =>
        _targets.TryGetValue(Path.GetFullPath(page), out var list) ? list : Array.Empty<string>();

    public IReadOnlyList<string> SourcesOf(string page) =>
        _sources.TryGetValue(Path.GetFullPath(page), out var list) ? list : Array.Empty<string>();

    /// <summary>
    /// Links from a page that would be visible to a page that would not.
    ///
    /// This is the check that makes "what will students see" answerable. Given
    /// what every page's draft flag WOULD be, it finds each place a student
    /// would meet a link to something that isn't there. It runs in both
    /// directions at once by construction: publishing a class without its
    /// deeper pages, and hiding a page some published class still points at,
    /// are the same defect seen from either end.
    /// </summary>
    public List<DanglingLink> DanglingLinks(Func<string, bool> isHidden)
    {
        var dangling = new List<DanglingLink>();
        foreach (string page in Pages)
        {
            if (isHidden(page)) continue;            // students never reach it, so its links do not matter
            foreach (string target in TargetsOf(page))
                if (isHidden(target))
                    dangling.Add(new DanglingLink(page, target));
        }
        return dangling;
    }

    public IReadOnlyList<string> VisibleSourcesOf(string page, Func<string, bool> isHidden) =>
        SourcesOf(page).Where(src => !isHidden(src)).ToList();

    /// <summary>
    /// True when a page is a curriculum page (any folder segment contains "curriculum").
    /// </summary>
    public static bool IsCurriculum(string path)
    {
        string normalized = path.Replace('\\', '/');
        var segments = normalized.Split('/');
        for (int i = 0; i < segments.Length - 1; i++)
            if (segments[i].Contains("curriculum", StringComparison.OrdinalIgnoreCase))
                return true;
        return false;
    }

    /// <summary>
    /// True when a page is a folder or section landing page (index.md).
    /// </summary>
    public static bool IsLandingPage(string path) =>
        string.Equals(Path.GetFileName(path), "index.md", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Pages that are never taken down by following links (shared-rules.json -> followingLinks).
    /// Includes landing pages (index.md), curriculum pages, and Key Links targets.
    /// </summary>
    public static bool IsExcludedFromSweep(string path, IReadOnlySet<string>? keyLinksTargets = null)
    {
        if (IsLandingPage(path)) return true;
        if (IsCurriculum(path)) return true;
        if (string.Equals(Path.GetFileName(path), "Key Links.md", StringComparison.OrdinalIgnoreCase)) return true;
        if (keyLinksTargets is not null && keyLinksTargets.Contains(Path.GetFullPath(path))) return true;
        return false;
    }

    /// <summary>
    /// Pages nothing links to. Not an error — a teacher writing next term's
    /// unit ahead produces these on purpose — but they are exactly the pages
    /// a link-following rule can never act on, so they have to be visible
    /// somewhere.
    ///
    /// <para><b>A CLASS PAGE IS NEVER ONE OF THESE.</b> Class pages are the
    /// ROOTS of a section, not its leaves: the rule the example content is
    /// built to is that every page must be reachable FROM a class, and a class
    /// is reached through the site's own navigation of All Classes. So
    /// "nothing links to this" is the ordinary, correct state for a class
    /// page. Counting them made a healthy course look broken — ICD2O Section 1
    /// reported <b>83 pages "linked from nowhere", every one of them a
    /// lesson</b>, out of 85 class pages. The mac has excluded them since it
    /// hit the same thing on an 86-period credit; this side had not, and that
    /// difference was the whole of the bug.</para>
    ///
    /// <para>Which pages those are is the COURSE's own answer, not a guess
    /// from the folder name: <c>per_section_folders</c> in
    /// <c>course_config.json</c> is what a section calls its class folders,
    /// which is why <paramref name="classPages"/> is passed in rather than
    /// worked out here.</para>
    ///
    /// <para>Per shared-rules.json → followingLinks, landing pages (index.md),
    /// curriculum pages and Key Links / its targets are excluded too. Note
    /// that list answers a DIFFERENT question — what unpublishing must never
    /// sweep up — and a class page is very much swept. The two exclusions
    /// happen to be applied in one place; do not merge them.</para>
    /// </summary>
    /// <param name="keyLinksTargets">Pages this section's Key Links points at.</param>
    /// <param name="classPages">
    /// The section's own class pages, full paths — from
    /// <c>AssistWorkspace.ClassPages</c>.
    /// </param>
    public List<string> Unreferenced(IReadOnlySet<string>? keyLinksTargets = null,
                                     IReadOnlySet<string>? classPages = null) =>
        Pages.Where(p => SourcesOf(p).Count == 0)
             .Where(p => !IsExcludedFromSweep(p, keyLinksTargets))
             .Where(p => classPages is null || !classPages.Contains(Path.GetFullPath(p)))
             .ToList();
}

/// <summary>A visible page pointing at a hidden one.</summary>
public readonly record struct DanglingLink(string From, string To);

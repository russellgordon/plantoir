using System.Text.RegularExpressions;
using Plantoir.Core.Models;

namespace Plantoir.Core.Assist;

/// <summary>
/// The section's front page, and the one class it puts at the top.
///
/// A section index carries a "Most Recent Class" heading with a single embed
/// under it:
///
/// <code>
/// # Most Recent Class
/// ![[Unit 4, Day 5]]
///
/// ![[Help Sessions]]
/// ![[Key Links]]
/// </code>
///
/// **Which class that is gets COMPUTED, never remembered** — it is the newest
/// class by date that is published in this section. That one decision makes
/// the whole thing correct in both directions and idempotent: publishing an
/// older class the teacher had missed does not drag the front page backwards,
/// and taking the newest class back down falls back to the previous one
/// without a line of code for the case. Recomputing after any change to a
/// class's draft state is enough.
///
/// This is the only place anything here edits a page's BODY rather than its
/// frontmatter, so it holds the same line: find the one line, change it, leave
/// every other byte alone. The teacher's index page may be open in Obsidian.
/// </summary>
public static class SectionIndex
{
    public static string PathFor(Course course, int sectionNumber) =>
        Path.Combine(course.SectionDirectory(sectionNumber), "index.md");

    /// <summary>
    /// The newest published class in this section, or null when none is.
    ///
    /// <paramref name="overrides"/> lets a plan ask "what WOULD be most recent
    /// if these pages changed", so the proposal and the result agree.
    /// </summary>
    public static string? MostRecentPublished(
        Course course, int sectionNumber, IReadOnlyList<string> classPages,
        IReadOnlyDictionary<string, bool>? overrides = null,
        IReadOnlyDictionary<string, DateOnly>? dateOverrides = null)
    {
        string? best = null;
        DateOnly bestDate = default;

        foreach (string page in classPages)
        {
            string full = Path.GetFullPath(page);
            string text;
            try { text = File.ReadAllText(page); } catch { continue; }

            bool draft = overrides is not null && overrides.TryGetValue(full, out bool wanted)
                ? wanted
                : PageFrontmatter.IsDraft(text, sectionNumber);
            if (draft) continue;

            DateOnly? date = dateOverrides is not null && dateOverrides.TryGetValue(full, out var moved)
                ? moved
                : PageFrontmatter.CreatedOn(text, sectionNumber,
                    PagePaths.IsSectionLocal(course.DirectoryPath, page));
            if (date is not { } when) continue;

            if (best is null || when > bestDate)
            {
                best = page;
                bestDate = when;
            }
            else if (when == bestDate && best is not null)
            {
                // The course's own word: a tie on date is broken by which page
                // is LATER in the course, and in a Module course neither name
                // parses under the default word, so the tie-break would fall
                // back to whichever file was walked first.
                var naming = course.Configuration.Naming;
                var currentUd = naming.Parse(Path.GetFileNameWithoutExtension(best));
                var newUd = naming.Parse(Path.GetFileNameWithoutExtension(page));
                if (newUd is not null && (currentUd is null || newUd.Value.CompareTo(currentUd.Value) > 0))
                {
                    best = page;
                    bestDate = when;
                }
            }
        }
        return best;
    }

    /// <summary>The heading Windows inserts under when the course recorded none.</summary>
    public const string DefaultHeadingText = "Most Recent Class";

    /// <summary>The heading the embed lives under in a course that recorded none — kept for the plan's sentence.</summary>
    public const string Heading = "# " + DefaultHeadingText;

    /// <summary>
    /// What the pointer needs to know about one section (#274 item 8, #406;
    /// <c>class-planning.json</c> → <c>sectionIndexPointer</c>).
    /// </summary>
    /// <param name="ClassTitles">Every class page of the section, by file name without .md.</param>
    /// <param name="PointAt">The class the front page should show.</param>
    /// <param name="PointAtPlace">Where that class lives INSIDE the course folder,
    /// with '/' and its .md — <c>section1/All Classes/Unit 2, Day 3.md</c>. Read
    /// against the course folder, never the disk path (whose own folder names
    /// the first #397 version picked up).</param>
    /// <param name="FrontPageHeading">The course's recorded <c>front_page_heading</c>,
    /// or null — read only by the insert fallback, never to FIND the embed.</param>
    public sealed record Pointer(IReadOnlyCollection<string> ClassTitles, string PointAt, string PointAtPlace, string? FrontPageHeading);

    /// <summary>The class embed the pointer found: its line, where the embed sits on it, and what it names.</summary>
    private sealed record Found(int LineStart, int EmbedStart, int EmbedEnd, string Inner, string ClassName);

    private static readonly Regex SectionSegment = new(@"^section\d+$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    /// <summary>
    /// The front page repointed at <see cref="Pointer.PointAt"/>, or null when
    /// it is left exactly as it is.
    /// </summary>
    /// <remarks>
    /// <para><b>Found by the CLASS PAGE it names, never by the heading.</b> The
    /// first line below the frontmatter and outside code and <c>%%</c>
    /// comments whose trimmed text is <c>![[…]]</c> and whose target — after
    /// any folder, before any <c>|</c> or <c>#</c>, without a typed
    /// <c>.md</c> — is a class page of the section. Until #274 this found the
    /// literal "# Most Recent Class" and took the first <c>![[</c> under it
    /// whatever it named, so CODING's "## Most Recent Meeting" never moved
    /// and a "Help Sessions" embed directly under the heading was REPLACED —
    /// removing it from the page every student lands on.</para>
    ///
    /// <para><b>Written in the form the teacher wrote, as far as the site can
    /// draw it</b> (<c>writtenAs</c>): a path holding a <c>section&lt;N&gt;</c>
    /// folder becomes the class's full place in the course, ALWAYS with
    /// <c>|name</c> (the build turns a section path into its display name, and
    /// without one the site gets a page it does not have — the mac's first
    /// #397 version, on Russell's MPM2DE); any other path, the class's place
    /// from the site's root; a display name equal to the old class's name
    /// follows it, any other one and a <c>#heading</c> are dropped; a typed
    /// <c>.md</c> stays; the line is rewritten BY POSITION, so another copy of
    /// it inside a comment is untouched.</para>
    ///
    /// <para><b>Where no line transcludes a class, this app INSERTS</b> — its
    /// shipped behaviour, widened to the course's own heading: on the line
    /// after the one whose trimmed text is <c>#</c>s, a space and the heading
    /// (absent → "Most Recent Class"), any level, case-insensitive; no such
    /// heading, and the page is left alone. The mac never inserts; the
    /// contract pins both (<c>whenNoClassIsTransclusion</c>,
    /// <c>expectBodyOnWindows</c>).</para>
    /// </remarks>
    public static string? Repointed(string indexText, Pointer pointer)
    {
        if (FindClassEmbed(indexText, pointer.ClassTitles) is { } found)
        {
            string rewritten = Rewritten(found, pointer);
            if (rewritten == found.Inner) return null;   // already pointing at it, in this form
            return indexText[..(found.EmbedStart + 3)] + rewritten + indexText[(found.EmbedEnd - 2)..];
        }

        // No class embed: insert under the course's own heading, or leave it.
        if (FindHeadingLine(indexText, pointer.FrontPageHeading) is not { } heading) return null;
        int lineEnd = indexText.IndexOf('\n', heading);
        bool carriageReturn = lineEnd > 0 && indexText[lineEnd - 1] == '\r';
        string embed = "![[" + pointer.PointAt + "]]" + (carriageReturn ? "\r" : "");
        return lineEnd < 0
            ? indexText + "\n" + embed
            : indexText[..(lineEnd + 1)] + embed + "\n" + indexText[(lineEnd + 1)..];
    }

    /// <summary>The class the front page shows now, by the same rule, or null.</summary>
    public static string? CurrentlyShowing(string indexText, IReadOnlyCollection<string> classTitles) =>
        FindClassEmbed(indexText, classTitles)?.ClassName;

    /// <summary>Whether this page can be pointed at all: it has a class embed, or (here) the heading to insert under.</summary>
    public static bool CanBePointed(string indexText, Pointer pointer) =>
        FindClassEmbed(indexText, pointer.ClassTitles) is not null
        || FindHeadingLine(indexText, pointer.FrontPageHeading) is not null;

    private static string Rewritten(Found found, Pointer pointer)
    {
        string inner = found.Inner;
        int bar = inner.IndexOf('|');
        string target = bar >= 0 ? inner[..bar] : inner;
        string? display = bar >= 0 ? inner[(bar + 1)..] : null;
        int hash = target.IndexOf('#');
        if (hash >= 0) target = target[..hash];
        bool typedMd = target.EndsWith(".md", StringComparison.OrdinalIgnoreCase);
        if (typedMd) target = target[..^3];

        int slash = target.LastIndexOf('/');
        string? folder = slash >= 0 ? target[..slash] : null;
        string place = pointer.PointAtPlace.Replace('\\', '/');
        if (place.EndsWith(".md", StringComparison.OrdinalIgnoreCase)) place = place[..^3];
        string md = typedMd ? ".md" : "";

        if (folder is not null && folder.Split('/').Any(segment => SectionSegment.IsMatch(segment.Trim())))
            return place + md + "|" + pointer.PointAt;

        string written = folder is null ? pointer.PointAt : FromTheSitesRoot(place);
        bool keepsName = display is not null
                         && string.Equals(display.Trim(), found.ClassName, StringComparison.OrdinalIgnoreCase);
        return written + md + (keepsName ? "|" + pointer.PointAt : "");
    }

    /// <summary>A place inside the course folder, as Quartz reads a path: from the site's root.</summary>
    private static string FromTheSitesRoot(string place)
    {
        var segments = place.Split('/');
        return segments.Length > 1 && SectionSegment.IsMatch(segments[0])
            ? string.Join("/", segments.Skip(1))
            : place;
    }

    /// <summary>Where the page's body starts: after a closing frontmatter fence, or 0.</summary>
    private static int BodyStart(string text)
    {
        if (!text.StartsWith("---", StringComparison.Ordinal)) return 0;
        int first = text.IndexOf('\n');
        if (first < 0 || text[..first].TrimEnd('\r').Trim() != "---") return 0;
        int position = first + 1;
        while (position < text.Length)
        {
            int end = text.IndexOf('\n', position);
            string line = (end < 0 ? text[position..] : text[position..end]).TrimEnd('\r');
            if (line.Trim() == "---") return end < 0 ? text.Length : end + 1;
            if (end < 0) break;
            position = end + 1;
        }
        return 0;
    }

    /// <summary>Every line of the body, with where it starts, that does not start inside code or a comment.</summary>
    private static IEnumerable<(int Start, string Line)> LinesOutsideCode(string text)
    {
        var masked = MarkdownCode.NotALinkRanges(text);
        int position = BodyStart(text);
        while (position < text.Length)
        {
            int end = text.IndexOf('\n', position);
            string line = end < 0 ? text[position..] : text[position..end];
            int firstVisible = position + (line.Length - line.TrimStart(' ', '\t').Length);
            if (!MarkdownCode.IsIn(masked, firstVisible)) yield return (position, line);
            if (end < 0) yield break;
            position = end + 1;
        }
    }

    private static Found? FindClassEmbed(string text, IReadOnlyCollection<string> classTitles)
    {
        var titles = classTitles.ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var (start, line) in LinesOutsideCode(text))
        {
            string trimmed = line.Trim(' ', '\t', '\r');
            if (!trimmed.StartsWith("![[", StringComparison.Ordinal) || !trimmed.EndsWith("]]", StringComparison.Ordinal)
                || trimmed.Length < 5)
                continue;
            string inner = trimmed[3..^2];
            string target = inner.Split('|')[0].Split('#')[0];
            if (target.EndsWith(".md", StringComparison.OrdinalIgnoreCase)) target = target[..^3];
            string name = target[(target.LastIndexOf('/') + 1)..].Trim();
            if (!titles.Contains(name)) continue;
            int embedStart = start + line.IndexOf("![[", StringComparison.Ordinal);
            int embedEnd = start + line.LastIndexOf("]]", StringComparison.Ordinal) + 2;
            return new Found(start, embedStart, embedEnd, inner, name);
        }
        return null;
    }

    private static int? FindHeadingLine(string text, string? frontPageHeading)
    {
        string heading = string.IsNullOrWhiteSpace(frontPageHeading) ? DefaultHeadingText : frontPageHeading.Trim();
        var pattern = new Regex(@"^#+ " + Regex.Escape(heading) + "$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        foreach (var (start, line) in LinesOutsideCode(text))
            if (pattern.IsMatch(line.Trim(' ', '\t', '\r'))) return start;
        return null;
    }

    /// <summary>
    /// What the pointer writes: the front page repointed (<see cref="Repointed"/>)
    /// and given that class's date. Null when the page is left as it is.
    /// Pulled out of <c>AssistWorkspace.ApplyIndexChange</c> so that
    /// <c>sectionIndexPointer.dateCases</c> runs against the transform the app
    /// really applies (#279).
    /// </summary>
    public static string? PointedAndDated(string indexText, Pointer pointer, DateOnly date, string tail)
    {
        string? withEmbed = Repointed(indexText, pointer);
        if (withEmbed is null)
        {
            // Already pointing at it: the date still follows the class (#275).
            if (!string.Equals(CurrentlyShowing(indexText, pointer.ClassTitles), pointer.PointAt,
                               StringComparison.OrdinalIgnoreCase))
                return null;
            withEmbed = indexText;
        }
        return Plantoir.Core.Models.PageFrontmatter.SetCreated(withEmbed, "created", date, tail).Text;
    }
}

namespace Plantoir.Core.Assist;

/// <summary>
/// What a change would do, worked out before anything is written.
///
/// This type is the whole safety argument of AI Assist in one object. The
/// investigation on the <c>ai-assist</c> branch found that a small model
/// inverts polarity often enough to matter — asked to HIDE tomorrow's class it
/// proposed publishing it, and the pages it links to, on some runs but not
/// others. Nothing testable defends against that. A teacher reading one
/// sentence does.
///
/// So no assistant, local or remote, is ever allowed to write directly. It
/// builds one of these, Plantoir renders it in plain words, and the teacher
/// says yes.
/// </summary>
public sealed class PublishPlan
{
    public required string CourseCode { get; init; }
    public required int SectionNumber { get; init; }

    /// <summary>
    /// Every page the plan would touch — the ones named, then the ones reached
    /// through their links. One flat list so no count can disagree with
    /// another; <see cref="PlannedPage.ViaLink"/> separates them.
    /// </summary>
    public required IReadOnlyList<PlannedPage> Pages { get; init; }

    /// <summary>Links that named nothing, or named too many things.</summary>
    public required IReadOnlyList<string> Problems { get; init; }

    /// <summary>Whether the site is republished after the flags change.</summary>
    public required bool Publishes { get; init; }

    /// <summary>Where a publish would land — "Netlify", "Cloudflare Pages", or a folder.</summary>
    public required string Destination { get; init; }

    /// <summary>True when the plan hides rather than publishes.</summary>
    public required bool Hiding { get; init; }

    /// <summary>
    /// Links a student would meet, after this change, that lead to a hidden
    /// page. Empty is the good answer.
    /// </summary>
    public IReadOnlyList<DanglingLink> Dangling { get; init; } = Array.Empty<DanglingLink>();

    /// <summary>
    /// Pages taking the date of the class that INTRODUCED them — the earliest
    /// one linking to them, which is often not the class being published.
    /// </summary>
    public IReadOnlyList<PlannedDate> InheritedDates { get; init; } = Array.Empty<PlannedDate>();

    /// <summary>The section's front page catching up, or null when it is already right.</summary>
    public IndexChange? Index { get; init; }

    public IEnumerable<PlannedPage> Named => Pages.Where(p => !p.ViaLink);
    public IEnumerable<PlannedPage> Linked => Pages.Where(p => p.ViaLink);

    /// <summary>Pages whose flag actually changes; the rest are already right.</summary>
    public IEnumerable<PlannedPage> Changing => Pages.Where(p => p.WillChange);

    /// <summary>
    /// Includes the dates and the front page, not just the draft flags —
    /// otherwise a publish whose only remaining work is catching the index up
    /// would report that there was nothing to do, and leave it behind.
    /// </summary>
    public bool ChangesNothing =>
        !Changing.Any() &&
        !InheritedDates.Any(d => d.WillChange) &&
        Index is not { WillChange: true };

    /// <summary>
    /// The whole answer, when the whole answer is that there was nothing to
    /// do — or null when something else needs saying.
    ///
    /// A teacher who asks to publish a class that is already published wants
    /// four words back, not a plan with a heading, a count and a note that
    /// nothing was changed because nothing needed to be. <see cref="Describe"/>
    /// is still right for every other shape of "nothing changed": a name that
    /// matched no page has to say so, and a request that found nothing at all
    /// is not the same as one that found everything already done.
    /// </summary>
    public string? NothingToDoSentence
    {
        get
        {
            if (!ChangesNothing || Problems.Count > 0) return null;

            var named = Named.ToList();
            if (named.Count == 0) return null;

            // Every page they NAMED is already the way they asked for it.
            // The pages reached by following links are not what "it" means.
            foreach (var page in named)
                if (page.WillChange) return null;

            // Word for word what the mac says, apostrophe included — these are
            // sentences a teacher reads, and the two apps saying them
            // differently is the drift the contract exists to catch.
            if (named.Count == 1)
                return Hiding ? "It's already hidden." : "It's already been published.";
            return Hiding ? "They have already been hidden." : "They have already been published.";
        }
    }

    /// <summary>
    /// The proposal as a teacher would read it.
    ///
    /// The shape of this is the direct result of a real session going wrong.
    /// The same call, made twice with a file edited in between, produced
    /// "nothing would change — and so are the 2 pages it links to" and then
    /// "publish the 1 page it links to". Both were correct for the state at
    /// the time, but they read as a contradiction, and the reader reasonably
    /// concluded the tool was unreliable — the plan being the one thing the
    /// whole workflow says to trust.
    ///
    /// Two rules follow, and they are why this is longer than a sentence:
    ///
    /// 1. **One count never means two things.** The number of pages involved
    ///    and the number that would CHANGE are separate sentences with
    ///    separate numbers. They used to share a phrase.
    /// 2. **State is stated.** Every changing page shows its key and its
    ///    transition, so a plan that describes a different world than an
    ///    earlier plan reads as a state change rather than a contradiction.
    /// </summary>
    public string Describe()
    {
        // "Unpublish", not "hide" — the pair a teacher actually says, and the
        // pair the briefing teaches. Two words for one act would undo the
        // point of explaining it once.
        string verb = Hiding ? "Unpublish" : "Publish";
        var lines = new List<string>();

        var named = Named.ToList();
        var linked = Linked.ToList();

        // A date range that matched nothing selects no pages at all. Saying
        // "unpublish 0 pages ... all 0 pages are already unpublished" is
        // arithmetic pretending to be a sentence; the problem line says what
        // actually happened.
        if (Pages.Count == 0)
        {
            lines.Add($"No pages were selected in {CourseCode} Section {SectionNumber}, so there is nothing to do.");
            foreach (string problem in Problems) lines.Add("• " + problem);
            return string.Join("\n", lines);
        }

        string subject = named.Count == 1
            ? $"“{named[0].Title}”"
            : $"{named.Count} pages";
        string linkNote = linked.Count switch
        {
            0 => "",
            1 => ", and the 1 page they link to",
            _ => $", and the {linked.Count} pages they link to",
        };
        lines.Add($"{verb} {subject} in {CourseCode} Section {SectionNumber}{linkNote}.");

        var changing = Changing.ToList();
        int total = Pages.Count;
        string already = Hiding ? "unpublished" : "published";

        int unchanged = total - changing.Count;
        if (changing.Count == 0)
            lines.Add(total == 1
                ? $"Nothing would change — it is already {already}."
                : $"Nothing would change — all {total} pages are already {already}.");
        else if (unchanged == 0)
            lines.Add($"{(total == 1 ? "It" : $"All {total} pages")} would change.");
        else
            lines.Add($"{changing.Count} of {total} pages would change; " +
                      $"the other {unchanged} {(unchanged == 1 ? "is" : "are")} already {already}.");

        foreach (string problem in Problems) lines.Add("• " + problem);

        if (changing.Count > 0)
        {
            lines.Add("");
            lines.Add("Would change:");
            foreach (var page in changing) lines.Add("  " + page.Transition);
        }

        if (InheritedDates.Count > 0)
        {
            lines.Add("");
            lines.Add($"{InheritedDates.Count} page{(InheritedDates.Count == 1 ? "" : "s")} would take " +
                      "the date of the class that first uses " +
                      (InheritedDates.Count == 1 ? "it" : "them") + ":");
            foreach (var date in InheritedDates.Take(MostDanglingShown)) lines.Add("  " + date.Describe());
            if (InheritedDates.Count > MostDanglingShown)
                lines.Add($"  …and {InheritedDates.Count - MostDanglingShown} more.");
        }

        if (Index is { } index)
        {
            lines.Add("");
            lines.Add(index.Describe());
        }

        AppendDangling(lines);

        if (Publishes)
        {
            lines.Add("");
            // An assistant rebuilds the PREVIEW and stops there. Making
            // something visible to students is the teacher's own action, taken
            // in front of the site they are about to change.
            lines.Add($"Then rebuild the preview of Section {SectionNumber}, so you can look it over. " +
                      $"Nothing goes live on {Destination} until you deploy it yourself in Plantoir.");
        }
        return string.Join("\n", lines);
    }

    /// <summary>How many dangling links to name before summarising.</summary>
    private const int MostDanglingShown = 8;

    /// <summary>
    /// The consequence check, in the teacher's terms: not "the graph is
    /// inconsistent" but "students would click this and find nothing".
    /// </summary>
    private void AppendDangling(List<string> lines)
    {
        if (Dangling.Count == 0) return;

        lines.Add("");
        lines.Add($"Afterwards, {Dangling.Count} link{(Dangling.Count == 1 ? "" : "s")} " +
                  $"on {(Hiding ? "pages students can still see" : "published pages")} " +
                  "would point at an unpublished page:");

        foreach (var link in Dangling.Take(MostDanglingShown))
            lines.Add($"  {Name(link.From)} → {Name(link.To)}");
        if (Dangling.Count > MostDanglingShown)
            lines.Add($"  …and {Dangling.Count - MostDanglingShown} more.");
    }

    private static string Name(string path) => Path.GetFileNameWithoutExtension(path);
}

/// <summary>
/// The section's front page catching up with what is published: which class
/// its "Most Recent Class" embed shows, and the date it carries.
/// </summary>
public sealed record IndexChange(
    string RelativePath,
    string? FromClass,
    string ToClass,
    DateOnly? FromDate,
    DateOnly ToDate,
    bool HeadingMissing)
{
    public bool WillChange => !HeadingMissing && (FromClass != ToClass || FromDate != ToDate);

    public string Describe() => HeadingMissing
        ? $"{RelativePath} has no “{SectionIndex.Heading}” heading, so its front page can’t be updated. " +
          "Nothing else is affected."
        : WillChange
            ? $"The section's front page would show “{ToClass}” ({ToDate:yyyy-MM-dd}) as the most recent class" +
              (FromClass is null ? "." : $", instead of “{FromClass}”.")
            : $"The section's front page already shows “{ToClass}”.";
}

/// <summary>One page a plan would touch, and what would happen to it.</summary>
public sealed record PlannedPage(
    string Title,
    string RelativePath,
    string FrontmatterKey,
    bool? CurrentValue,
    bool Draft,
    bool ViaLink,
    DateOnly? Date = null)
{
    /// <summary>False when the page already carries the wanted value.</summary>
    public bool WillChange => CurrentValue != Draft;

    /// <summary>
    /// The edit in full: which file, which key, and what it goes from and to.
    ///
    /// Naming the key matters more than it looks. A page under
    /// <c>section&lt;N&gt;/</c> is governed by <c>publish:</c> and a course-level
    /// page by <c>publishForSection&lt;N&gt;:</c>, and a reader who has only seen
    /// class pages will generalise from them and be wrong — that happened in
    /// a real session, and a plan listing bare paths did nothing to prevent
    /// it. Showing the key makes the two schemas impossible to miss.
    /// </summary>
    /// <summary>
    /// Shown in PUBLISH terms, because that is what the file says.
    ///
    /// <see cref="CurrentValue"/> and <see cref="Draft"/> both mean "hidden",
    /// which is the question a plan answers — but the frontmatter key means
    /// the opposite, so printing them unchanged beside it would read as a
    /// double negative and tell the teacher the reverse of the truth.
    /// </summary>
    public string Transition =>
        $"{RelativePath}  ({When}{FrontmatterKey}: {Show(Invert(CurrentValue))} → {Show(!Draft)})";

    private static bool? Invert(bool? value) => value is null ? null : !value;

    /// <summary>
    /// The class's date, when it has one. A batch chosen BY date has to be
    /// checkable by date — a list of paths alone gives the teacher no way to
    /// see that the range caught what they meant.
    /// </summary>
    private string When => Date is { } date ? $"{date:yyyy-MM-dd}, " : "";

    private static string Show(bool? value) =>
        value is null ? "not set" : value.Value ? "true" : "false";
}

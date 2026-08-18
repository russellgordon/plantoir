using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Plantoir.Core.Assist;

/// <summary>
/// What a publish or unpublish change would do, worked out before anything is written.
///
/// PLAIN TEXT. No markdown, no boldface, no machinery (no arrows, no frontmatter keys,
/// no file paths). Each changing page is described as a human sentence:
/// "“Unit 4, Day 24” will become hidden."
///
/// Matches macOS AssistPublishPlan.swift.
/// </summary>
public sealed class PublishPlan
{
    public required string CourseCode { get; init; }
    public required int SectionNumber { get; init; }

    /// <summary>The verb: true for publish, false for unpublish.</summary>
    public required bool Publishes { get; init; }

    /// <summary>Whether the plan hides rather than publishes.</summary>
    public bool Hiding
    {
        get => !Publishes;
        init => Publishes = !value;
    }

    /// <summary>Page names the teacher or model named that matched nothing.</summary>
    public IReadOnlyList<string> UnknownNames { get; init; } = Array.Empty<string>();

    /// <summary>The pages the teacher named that were found.</summary>
    public IReadOnlyList<PlannedPage> NamedPages { get; init; } = Array.Empty<PlannedPage>();

    /// <summary>Pages whose visibility will change.</summary>
    public IReadOnlyList<PlannedChange> Changes { get; init; } = Array.Empty<PlannedChange>();

    /// <summary>Pages already in the requested state.</summary>
    public IReadOnlyList<PlannedPage> AlreadyRight { get; init; } = Array.Empty<PlannedPage>();

    /// <summary>Pages kept visible during unpublish, each with its reason.</summary>
    public IReadOnlyList<PlannedKept> Kept { get; init; } = Array.Empty<PlannedKept>();

    /// <summary>Pages whose date moves onto the class's day.</summary>
    public IReadOnlyList<PlannedDateMove> DateMoves { get; init; } = Array.Empty<PlannedDateMove>();

    /// <summary>Where a publish would land — "Netlify", "Cloudflare Pages", or a folder.</summary>
    public string Destination { get; init; } = "";

    /// <summary>All pages the plan touches (named and linked).</summary>
    public IReadOnlyList<PlannedPage> Pages { get; init; } = Array.Empty<PlannedPage>();

    /// <summary>Backward-compatible problems list.</summary>
    public IReadOnlyList<string> Problems { get; init; } = Array.Empty<string>();

    /// <summary>Backward-compatible inherited dates for applying.</summary>
    public IReadOnlyList<PlannedDate> InheritedDates { get; init; } = Array.Empty<PlannedDate>();

    /// <summary>The section's front page catching up, or null when already right.</summary>
    public IndexChange? Index { get; init; }

    /// <summary>Backward-compatible dangling links list.</summary>
    public IReadOnlyList<DanglingLink> Dangling { get; init; } = Array.Empty<DanglingLink>();

    public IEnumerable<PlannedPage> Named => NamedPages.Count > 0 ? NamedPages : Pages.Where(p => !p.ViaLink);
    public IEnumerable<PlannedPage> Linked => Pages.Where(p => p.ViaLink);
    public IEnumerable<PlannedPage> Changing => Changes.Select(c => c.Page);

    public bool ChangesNothing => Changes.Count == 0 && DateMoves.Count == 0;

    /// <summary>
    /// The whole answer, when the whole answer is that there was nothing to
    /// do — or null when something else needs saying.
    /// </summary>
    public string? NothingToDoSentence
    {
        get
        {
            if (!ChangesNothing || UnknownNames.Count > 0) return null;

            var named = Named.ToList();
            if (named.Count == 0) return null;

            foreach (var page in named)
            {
                if (page.IsVisibleToStudents != Publishes)
                    return null;
            }

            string done = Publishes ? "published" : "hidden";
            if (named.Count == 1)
                return Publishes ? "It's already been published." : "It's already hidden.";
            return $"They have already been {done}.";
        }
    }

    /// <summary>
    /// The proposal as a teacher would read it.
    /// Plain sentences, no markdown, no machinery.
    /// </summary>
    public string Describe(int mostListed = 15)
    {
        var lines = new List<string>();
        string verb = Publishes ? "publishing" : "unpublishing";
        lines.Add($"{CourseCode} Section {SectionNumber}: {verb}.");
        lines.Add("");

        if (Changes.Count == 0)
        {
            lines.Add("No page's visibility would change.");
        }
        else
        {
            string word = Changes.Count == 1 ? "page" : "pages";
            lines.Add($"{Changes.Count} {word} would change:");
            int listed = 0;
            foreach (var change in Changes)
            {
                if (listed == mostListed)
                {
                    lines.Add($"…and {Changes.Count - listed} more.");
                    break;
                }
                string becoming = change.WillBeVisible ? "visible" : "hidden";
                string line = $"“{change.Page.DisplayTitle}” will become {becoming}";
                foreach (var move in DateMoves.Where(m => string.Equals(m.Page.Title, change.Page.Title, StringComparison.OrdinalIgnoreCase)))
                {
                    line += $", with the same date as “{move.TakenFrom}”";
                }
                lines.Add(line + ".");
                listed++;
            }
        }

        if (AlreadyRight.Count > 0)
        {
            string word = AlreadyRight.Count == 1 ? "page is" : "pages are";
            lines.Add($"{AlreadyRight.Count} {word} already {(Publishes ? "visible" : "hidden")}.");
        }

        if (Kept.Count > 0)
        {
            lines.Add("");
            string word = Kept.Count == 1 ? "page stays" : "pages stay";
            lines.Add($"{Kept.Count} linked {word} visible:");
            int listed = 0;
            foreach (var staying in Kept)
            {
                if (listed == mostListed)
                {
                    lines.Add($"…and {Kept.Count - listed} more.");
                    break;
                }
                lines.Add($"“{staying.Page.DisplayTitle}” stays visible, because {staying.Reason}");
                listed++;
            }
        }

        var namedAlready = new HashSet<string>(Changes.Select(c => c.Page.Title), StringComparer.OrdinalIgnoreCase);
        var orphaned = DateMoves.Where(m => !namedAlready.Contains(m.Page.Title)).ToList();
        if (orphaned.Count > 0)
        {
            lines.Add("");
            foreach (var move in orphaned)
            {
                lines.Add($"“{move.Page.DisplayTitle}” will take the same date as “{move.TakenFrom}”.");
            }
        }

        if (UnknownNames.Count > 0)
        {
            lines.Add("");
            lines.Add($"No page in this section is called {Listing(UnknownNames)}.");
        }

        return string.Join("\n", lines);
    }

    /// <summary>“a”, “a” and “b”, “a”, “b” and “c” — the way a sentence says a list.</summary>
    public static string Listing(IReadOnlyList<string> names)
    {
        var quoted = names.Select(n => $"“{n}”").ToList();
        if (quoted.Count <= 1) return quoted.FirstOrDefault() ?? "";
        string last = quoted[^1];
        quoted.RemoveAt(quoted.Count - 1);
        return string.Join(", ", quoted) + " and " + last;
    }
}

/// <summary>One page whose visibility would move.</summary>
public sealed record PlannedChange(
    PlannedPage Page,
    string Key,
    bool WasVisible,
    bool WillBeVisible,
    bool BecauseLinked);

/// <summary>One page an unpublish reached by following a link and left published.</summary>
public sealed record PlannedKept(
    PlannedPage Page,
    string Reason);

/// <summary>One page whose date would move onto the class's day.</summary>
public sealed record PlannedDateMove(
    PlannedPage Page,
    DateOnly? From,
    DateOnly To,
    string TakenFrom);

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
    DateOnly? Date = null,
    string? DisplayTitle = null,
    bool IsFolderIndex = false,
    bool IsClassPage = false,
    bool IsSectionLocal = false)
{
    /// <summary>What the teacher sees this page called (Quartz displayName).</summary>
    public string DisplayTitle { get; init; } = DisplayTitle ?? Title;

    /// <summary>True when students currently see this page.</summary>
    public bool IsVisibleToStudents => CurrentValue is null || !CurrentValue.Value;

    /// <summary>False when the page already carries the wanted value.</summary>
    public bool WillChange => CurrentValue != Draft;

    /// <summary>
    /// Legacy transition string for internal inspection.
    /// </summary>
    public string Transition =>
        $"{RelativePath}  ({When}{FrontmatterKey}: {Show(Invert(CurrentValue))} → {Show(!Draft)})";

    private static bool? Invert(bool? value) => value is null ? null : !value;

    private string When => Date is { } date ? $"{date:yyyy-MM-dd}, " : "";

    private static string Show(bool? value) =>
        value is null ? "not set" : value.Value ? "true" : "false";
}

using System;
using System.Collections.Generic;
using System.Linq;

namespace Plantoir.Core.Assist;

/// <summary>
/// Curriculum expectations that would be pointed at from a page.
///
/// Which expectations fit a lesson is a judgement about MEANING, and the
/// measurements say a 1.5B router model has no business making it — but a
/// capable one does it well. So the split is deliberate: the tools find the
/// expectations, read them out, know the transclusion syntax and where the
/// markers go, and the model driving decides which ones belong. The teacher
/// then says yes to a named list rather than to "some expectations".
/// </summary>
public sealed class CurriculumMentionsPlan
{
    public required string CourseCode { get; init; }
    public required int SectionNumber { get; init; }
    public required string PageTitle { get; init; }
    public required string RelativePath { get; init; }

    /// <summary>The expectations that would be added, with their wording.</summary>
    public required IReadOnlyList<AssistWorkspace.Expectation> Adding { get; init; }

    /// <summary>Codes the page already points at, which are left alone.</summary>
    public required IReadOnlyList<string> AlreadyThere { get; init; }

    /// <summary>Codes that match no expectation in this course.</summary>
    public required IReadOnlyList<string> Unknown { get; init; }

    /// <summary>Whether the page already has a curriculum block to add to.</summary>
    public required bool HasBlockAlready { get; init; }

    public bool ChangesNothing => Adding.Count == 0;

    public string Describe()
    {
        var lines = new List<string>();

        if (Adding.Count == 0)
        {
            lines.Add(AlreadyThere.Count > 0
                ? $"Nothing to add — “{PageTitle}” already points at {Listed(AlreadyThere)}."
                : $"Nothing to add to “{PageTitle}”.");
            AppendUnknown(lines);
            return string.Join("\n", lines);
        }

        string word = Adding.Count == 1 ? "expectation" : "expectations";
        lines.Add($"Add {Adding.Count} curriculum {word} to “{PageTitle}” in " +
                  $"{CourseCode} Section {SectionNumber}:");
        lines.Add("");

        // The WORDING, not just the code. A teacher cannot check "A2.2" for
        // themselves without going and looking it up, and the whole point of
        // confirming is that they can tell whether it fits their lesson.
        foreach (var expectation in Adding)
        {
            lines.Add($"  {expectation.Code}");
            lines.Add($"    {Shorten(expectation.Text)}");
        }

        if (AlreadyThere.Count > 0)
        {
            lines.Add("");
            lines.Add($"Already there, left alone: {Listed(AlreadyThere)}.");
        }

        AppendUnknown(lines);

        lines.Add("");
        lines.Add(HasBlockAlready
            ? "They join the curriculum block already on the page."
            : "A curriculum block is added for them, before the list of things to do.");
        lines.Add("Nothing else on the page changes, and no page's visibility changes.");
        return string.Join("\n", lines);
    }

    private void AppendUnknown(List<string> lines)
    {
        if (Unknown.Count == 0) return;
        lines.Add("");
        // Named rather than skipped: a code that matched nothing usually means
        // a typo or a different course's numbering, and silently dropping it
        // would leave the teacher believing it was added.
        lines.Add($"• {string.Join(", ", Unknown)} " +
                  $"{(Unknown.Count == 1 ? "is not an expectation" : "are not expectations")} " +
                  $"in {CourseCode}, so {(Unknown.Count == 1 ? "it was" : "they were")} left out.");
    }

    private const int MostWords = 24;

    private static string Shorten(string text)
    {
        var words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return words.Length <= MostWords ? text : string.Join(' ', words.Take(MostWords)) + "…";
    }

    private static string Listed(IReadOnlyList<string> codes)
    {
        var quoted = codes.Select(c => $"“{c}”").ToList();
        if (quoted.Count <= 1) return quoted.FirstOrDefault() ?? "";
        string last = quoted[^1];
        quoted.RemoveAt(quoted.Count - 1);
        return string.Join(", ", quoted) + " and " + last;
    }
}

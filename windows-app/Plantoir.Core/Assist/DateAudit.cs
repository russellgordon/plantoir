using System.Text.RegularExpressions;

namespace Plantoir.Core.Assist;

/// <summary>
/// Dates that would confuse a student, or that betray a copy-paste nobody
/// finished.
///
/// A class page's date is not decoration: the All Classes listing sorts by it,
/// and every category listing sorts by the date its pages inherited. So a date
/// that is wrong does not look wrong — it looks like a lesson filed in the
/// wrong week, which is much harder to notice and much worse to live with.
/// </summary>
public static class DateAudit
{
    /// <summary>
    /// How far a linked page's date may sit from the class using it before it
    /// is worth mentioning. Generous on purpose: a teacher may deliberately
    /// date material a little ahead of or behind the lesson, and being nagged
    /// about a fortnight would make the real findings invisible.
    /// </summary>
    private const int ToleranceDays = 21;

    /// <summary>
    /// Every problem worth a teacher's attention, in plain words.
    /// </summary>
    /// <param name="classPages">Class pages, in the order they are taught.</param>
    /// <param name="dateOf">A page's date, or null when it has none.</param>
    /// <param name="name">A page path as the teacher should see it.</param>
    public static List<string> Run(
        IReadOnlyList<string> classPages,
        LinkGraph graph,
        Func<string, DateOnly?> dateOf,
        Func<string, string> name)
    {
        var problems = new List<string>();
        var dated = classPages.Where(p => dateOf(p) is not null).ToList();

        // ---- Classes with no date at all ---------------------------------
        foreach (string page in classPages)
            if (dateOf(page) is null)
                problems.Add($"“{Title(page)}” has no date, so it will not sort with the other classes.");

        // ---- Two classes on one day --------------------------------------
        foreach (var sameDay in dated.GroupBy(p => dateOf(p)!.Value).Where(g => g.Count() > 1))
            problems.Add($"{sameDay.Count()} classes share {sameDay.Key:yyyy-MM-dd}: " +
                         string.Join(", ", sameDay.Select(p => "“" + Title(p) + "”")) + ".");

        // ---- Classes filed out of teaching order -------------------------
        // Only checked when every class names its unit and day, because
        // otherwise the intended order is not something to guess at.
        var numbered = new List<(int Unit, int Day, string Page)>();
        bool allNumbered = true;
        foreach (string page in dated)
        {
            var match = Regex.Match(Title(page), @"Unit\s+(\d+)\s*,\s*Day\s+(\d+)", RegexOptions.IgnoreCase);
            if (!match.Success) { allNumbered = false; break; }
            numbered.Add((int.Parse(match.Groups[1].Value), int.Parse(match.Groups[2].Value), page));
        }
        if (allNumbered && numbered.Count > 1)
        {
            var inOrder = numbered.OrderBy(n => n.Unit).ThenBy(n => n.Day).ToList();
            for (int i = 1; i < inOrder.Count; i++)
            {
                DateOnly earlier = dateOf(inOrder[i - 1].Page)!.Value;
                DateOnly later = dateOf(inOrder[i].Page)!.Value;
                if (later < earlier)
                    problems.Add($"“{Title(inOrder[i].Page)}” ({later:yyyy-MM-dd}) is dated BEFORE " +
                                 $"“{Title(inOrder[i - 1].Page)}” ({earlier:yyyy-MM-dd}), so the classes " +
                                 "would appear out of order.");
            }
        }

        // ---- Material dated nowhere near any class that uses it ----------
        //
        // The copy-paste case: a page duplicated for a new lesson, edited, and
        // its date left on last term's value. Checked against EVERY class that
        // links to the page, not just the first — a concept genuinely revisited
        // in June is dated for the September lesson that introduced it, and
        // that is correct, not a mistake.
        foreach (string page in graph.Pages)
        {
            if (IsIgnored(page)) continue;
            if (dateOf(page) is not { } pageDate) continue;
            var linkers = graph.SourcesOf(page)
                .Where(s => dateOf(s) is not null && classPages.Contains(s))
                .ToList();
            if (linkers.Count == 0) continue;

            int nearest = int.MaxValue;
            string nearestClass = "";
            foreach (string linker in linkers)
            {
                int gap = Math.Abs(dateOf(linker)!.Value.DayNumber - pageDate.DayNumber);
                if (gap < nearest) { nearest = gap; nearestClass = linker; }
            }
            if (nearest <= ToleranceDays) continue;

            DateOnly classDate = dateOf(nearestClass)!.Value;
            string direction = pageDate < classDate ? "earlier" : "later";
            problems.Add(
                $"“{Title(nearestClass)}” ({classDate:yyyy-MM-dd}) links to “{Title(page)}”, which is dated " +
                $"{pageDate:yyyy-MM-dd} — {Gap(nearest)} {direction}, and no class that links to it falls near " +
                "that date. A page copied for a new lesson whose date was never changed looks like this.");
        }

        return problems;
    }

    /// <summary>
    /// Pages left outside the taught range by a rollover, summarised as one
    /// finding rather than one per page.
    ///
    /// These are almost always the pages NO class links to — a unit written
    /// ahead, or last year's material — so nothing anchored them when the
    /// classes moved. One line naming the cause is worth more than fifty lines
    /// naming files, and fifty lines would bury the findings that need
    /// individual attention.
    ///
    /// Index pages and _DUPLICATE ME template pages are skipped: they are
    /// navigation/templates rather than teaching content.
    /// </summary>
    public static List<string> Stragglers(
        IReadOnlyList<string> pages, DateOnly firstClass, DateOnly lastClass,
        Func<string, DateOnly?> dateOf, Func<string, string> name)
    {
        var left = new List<string>();
        foreach (string page in pages)
        {
            if (IsIgnored(page)) continue;
            if (dateOf(page) is not { } date) continue;
            if (date >= firstClass.AddDays(-ToleranceDays) && date <= lastClass.AddDays(ToleranceDays)) continue;
            left.Add(page);
        }
        if (left.Count == 0) return new List<string>();

        var examples = left.Take(3).Select(Title);
        return new List<string>
        {
            $"{left.Count} page{(left.Count == 1 ? " is" : "s are")} still dated outside the course " +
            $"({firstClass:yyyy-MM-dd} to {lastClass:yyyy-MM-dd}) — for example {string.Join(", ", examples)}" +
            (left.Count > 3 ? ", …" : "") + ". No class links to " +
            (left.Count == 1 ? "it" : "them") + ", so nothing moved " +
            (left.Count == 1 ? "it" : "them") + " with the lessons. Run check_section to see them all.",
        };
    }

    /// <summary>
    /// Templates, system pages, and index pages are not teaching content and
    /// must be ignored by date auditing.
    /// </summary>
    public static bool IsIgnored(string path)
    {
        string fileName = Path.GetFileName(path);
        string stem = Path.GetFileNameWithoutExtension(path);
        if (string.Equals(fileName, "index.md", StringComparison.OrdinalIgnoreCase)) return true;
        if (string.Equals(stem, "_DUPLICATE ME", StringComparison.OrdinalIgnoreCase)) return true;
        if (fileName.StartsWith("._", StringComparison.Ordinal)) return true;
        if (fileName.StartsWith("_", StringComparison.Ordinal)) return true;
        return false;
    }

    /// <summary>"7 months", "3 weeks" — the size of the gap, the way a person would say it.</summary>
    private static string Gap(int days)
    {
        if (days >= 60) return $"about {Math.Round(days / 30.4)} months";
        if (days >= 14) return $"about {Math.Round(days / 7.0)} weeks";
        return $"{days} days";
    }

    private static string Title(string path) => Path.GetFileNameWithoutExtension(path);
}

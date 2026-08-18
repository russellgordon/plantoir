namespace Plantoir.Core.Assist;

/// <summary>
/// Class pages that do not exist yet, and the real dates they would land on.
///
/// A teacher planning the next unit knows two things — which unit, and how
/// many days they want in it — and neither of those is a date. The dates come
/// from the section's own timetable, which Plantoir now remembers, so nobody
/// has to work out that the seventh class after today falls on a Thursday in
/// November.
/// </summary>
public sealed class NewClassesPlan
{
    public required string CourseCode { get; init; }
    public required int SectionNumber { get; init; }
    public required int Unit { get; init; }

    /// <summary>The pages that would be created, in order.</summary>
    public required IReadOnlyList<NewClass> Classes { get; init; }

    /// <summary>Pages that already exist and would be left exactly as they are.</summary>
    public required IReadOnlyList<string> AlreadyThere { get; init; }

    /// <summary>Anything the teacher should know before saying yes.</summary>
    public required IReadOnlyList<string> Problems { get; init; }

    /// <summary>Meeting dates still spare after these classes take theirs.</summary>
    public required int SpareDatesLeft { get; init; }

    /// <summary>How many of these pages have no class date of their own and are sharing the last one.</summary>
    public int SharingTheLastDay { get; init; }

    /// <summary>Where the dates came from.</summary>
    public string TimetableSource { get; init; } = "";

    public bool ChangesNothing => Classes.Count == 0;

    /// <summary>The proposal, as a teacher would read it.</summary>
    public string Describe()
    {
        var lines = new List<string>();

        if (Classes.Count == 0)
        {
            lines.Add($"Nothing to add — every class asked for in Unit {Unit} of {CourseCode} " +
                      $"Section {SectionNumber} already exists.");
            foreach (string problem in Problems) lines.Add("• " + problem);
            return string.Join("\n", lines);
        }

        lines.Add($"Add {Classes.Count} class page{(Classes.Count == 1 ? "" : "s")} to Unit {Unit} of " +
                  $"{CourseCode} Section {SectionNumber}, on the {(Classes.Count == 1 ? "day" : "days")} this class actually meets:");
        lines.Add("");
        foreach (var created in Classes)
            lines.Add($"  {created.Title}  ({created.Date:yyyy-MM-dd} {created.Date.DayOfWeek})");

        if (AlreadyThere.Count > 0)
        {
            lines.Add("");
            lines.Add($"{AlreadyThere.Count} already exist{(AlreadyThere.Count == 1 ? "s" : "")} and " +
                      $"{(AlreadyThere.Count == 1 ? "is" : "are")} left alone: {string.Join(", ", AlreadyThere)}.");
        }

        foreach (string problem in Problems) lines.Add("• " + problem);

        lines.Add("");
        // Said plainly because it is the difference between a teacher seeing
        // their new pages in the preview and wondering where they went.
        lines.Add("They start unpublished, so they stay off the site until you publish them — " +
                  "write them first, publish when they are ready.");

        if (SharingTheLastDay > 0)
        {
            lines.Add($"{(SharingTheLastDay == 1 ? "This one has" : $"{SharingTheLastDay} of these have")} " +
                      $"no class date left, so {(SharingTheLastDay == 1 ? "it shares" : "they share")} " +
                      $"the last day with the class already on it. Give " +
                      $"{(SharingTheLastDay == 1 ? "it a day" : "them days")} of your own when you " +
                      "know what they are.");
        }
        else
        {
            string sourceNote = string.IsNullOrEmpty(TimetableSource)
                ? ""
                : $", out of the timetable recorded from {TimetableSource}";
            lines.Add($"{SpareDatesLeft} more class date{(SpareDatesLeft == 1 ? "" : "s")} " +
                      $"{(SpareDatesLeft == 1 ? "is" : "are")} spare after these{sourceNote}.");
        }

        return string.Join("\n", lines);
    }
}

/// <summary>One page that would be created, and the day it belongs to.</summary>
public sealed record NewClass(string Title, string RelativePath, DateOnly Date, int Day);
